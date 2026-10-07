# 《千星奇域 Sans 战》方案甲修改文档
## —— 回归原版「方向重力 + 撞墙甩击」，修复审判眼拖拽灵魂

- **工作区**：`D:\stars\workspace\sans-fight`
- **依据**：`D:\stars\docs\修改建议\Sans_Fight_审判眼拖拽灵魂_机制总结与修改建议.md`（方案甲）
- **原版对照**：`D:\c2-sans-fight-src`（commit 0bb6afe）
- **日期**：2026-10-06
- **性质**：补丁式修改文档（含 before/after 代码，可直接照改）

---

## 0. 本次要解决什么

工作区当前把「审判眼拖拽灵魂」实现成了 **贴墙模式 + 0.55s 衰减冲量 + 整边升骨**，与原版机制无关。
方案甲的目标是把它改回 **原版的蓝魂方向重力甩击**：

1. `SansSlam` 强制切蓝魂、设定方向、**满速甩出**；
2. 蓝魂重力**沿甩出方向**（0 东 / 1 南 / 2 西 / 3 北）；
3. 撞到战斗框/平台时结束甩击；速度 >330 → **伤害 + 屏幕抖动 + 音效**；
4. `SansSlamDamage` 真正控制是否 -1 HP（当前是死代码）；
5. `bonestab1/2/3` 回到原版 `BoneStab` 三档（Distance 25/25/29、Warn 0.4/0.3/0.4、Stay 0.333/0.2/0）。

**不改动**：7 图元模板池、坐标口径、回合编排（`FIXED_SEQ`）、骨墙/激光/平台等其它攻击、难度倍率框架。

---

## 1. 关键决定：跳跃模型选 A1 还是 A2

原版的跳跃是「**冲量 180 + 松手截断 30 + 4 档重力曲线**」；工作区此前按你的口径改成了「**按住匀速上升 0.25s / 松手匀速下落**」。
方案甲只要求"方向重力 + 撞墙"，**不强制改跳跃手感**。因此给出两档：

| 档 | 跳跃实现 | 好处 | 代价 |
|---|---|---|---|
| **A1 完全原版** | 冲量 180，沿 −重力方向；松手时把"上升速度"截到 30；4 档重力曲线 | 100% 原版手感 | 会推翻你此前"匀速上升/下落"的要求；`core_selftest` 的 blue-jump 段要重写 |
| **A2 混合（推荐）** | 保留"按住 0.25s 匀速上升 / 松手 0.75s 匀速下落"，但**沿 −重力/ +重力方向**执行 | 既拿到方向重力，又保留你已验收的跳跃手感 | 与"逐帧原版"仍有差异；`core_selftest` 只需把"竖直"断言改成"沿方向" |

**本文正文按 A2 写**，A1 的差异点用 `【A1 变体】` 标注。

---

## 2. 改动总览

| 编号 | 文件 | 位置 | 改动 | 破坏性 |
|---|---|---|---|---|
| A-1 | `lua/core.lua` | `resetRun` / `startEnemy` | `soul` 增加 `dir`(默认 1) 与 `slammed` 字段 | 无 |
| A-2 | `lua/core.lua` | `CMD.SansSlam` | 重写：强制蓝魂 + 设 dir + 满速 + slammed | 行为变更 |
| A-3 | `lua/core.lua` | `CMD.SansSlamDamage` | `w.slamDamage` 透传到 Game | 无 |
| A-4 | `lua/core.lua` | World→Game 同步块 | 删掉 `soul.push` 构造，改为写入速度 + slam 标记 | 行为变更 |
| A-5 | `lua/core.lua` | 蓝魂物理段 | 由"仅垂直"改为**方向重力**（A2 混合） | 核心变更 |
| A-6 | `lua/core.lua` | 钳位处 | 新增**撞墙判定 + 伤害 + 抖屏** | 新增 |
| A-7 | `lua/core.lua` + `lua/main.lua` | 渲染 | 移植 `SansShake`（core 状态 + shake 命令 + 画布偏移） | 新增 |
| A-8 | `lua/core.lua` | `Game:jump` | 沿 −重力方向起跳（A2：沿方向匀速上升） | 行为变更 |
| A-9 | `lua/attacks.lua` | `sans_bonestab1/2/3` | 去掉 `HeartWall`/`ArrowBone`，恢复 `BoneStab` 三档 | 内容替换 |
| A-10 | `lua/main.lua` | 蓝魂掩码 | 方向重力下重新定义"上=跳/左右=移动"（含 4 方向重力时的输入映射） | 行为变更 |
| A-11 | 可选 | 音效出口 | `CMD.Sound` 从"只写日志"接到真实音频 | 平台相关 |
| A-12 | 测试 | `core_selftest` / `_input` / 探针 | 同步断言（见 §5） | 必须 |

---

## 3. 逐步补丁

### A-1 `soul` 增加 `dir` / `slammed` 字段

**`Game:resetRun()`（`core.lua`，`self.soul = {...}` 处）**

before:
```lua
  self.soul = { x = self.box.x + self.box.w / 2, y = self.box.y + self.box.h / 2,
                vx = 0, vy = 0, mode = 'red', grounded = false }
```
after:
```lua
  self.soul = { x = self.box.x + self.box.w / 2, y = self.box.y + self.box.h / 2,
                vx = 0, vy = 0, mode = 'red', grounded = false,
                dir = 1, slammed = false }        -- 【A-1】dir: 0东 1南 2西 3北
```

**`Game:startEnemy(n)`（`self.soul.mode = ...` 附近）**

after（在 `self.soul.vx, self.soul.vy = 0, 0` 后补一行）:
```lua
  self.soul.vx, self.soul.vy = 0, 0
  self.soul.dir = 1                 -- 【A-1】默认重力向下（= 原版 HeartMode 默认 Angle 90）
  self.soul.slammed = false
  self.soul.maxFall = nil
  self.soul.push = nil              -- 【A-4】不再使用冲量
```

---

### A-2 重写 `CMD.SansSlam`

before（`core.lua:583`）:
```lua
CMD.SansSlam = function(w, d)
  local s = w.heart.maxFall
  if not s or s == 0 then s = 240 end
  d = tonumber(d)
  w.heart.dir = d
  w.heart.vx = (d == 0) and s or ((d == 2) and -s or 0)
  w.heart.vy = (d == 1) and s or ((d == 3) and -s or 0)
  w.heartVelDirty = true
  say(w, 'slam ' .. tostring(d))
end
```
after（对齐原版 `SansSlam`）:
```lua
CMD.SansSlam = function(w, d)
  d = tonumber(d) or 0
  if d < 0 or d > 3 then return end
  local s = w.heart.maxFall
  if not s or s == 0 then s = 750 end          -- 原版默认 MaxFallSpeed=750
  -- ① 强制切蓝魂（原版 SansSlam 自己就会切，不依赖脚本写 HeartMode）
  w.heart.mode = 1
  -- ② 标记"正在被甩"，③ 设定方向
  w.heart.slammed = true
  w.heart.dir = d
  -- ④ 沿方向满速甩出（0 东 / 1 南 / 2 西 / 3 北）
  w.heart.vx = (d == 0) and s or ((d == 2) and -s or 0)
  w.heart.vy = (d == 1) and s or ((d == 3) and -s or 0)
  w.heartModeDirty = true
  w.heartVelDirty = true
  say(w, 'slam ' .. tostring(d))
end
```

> 注意：原版 `SansSlam` 里 `HeartMode(HEARTMODE_BLUE)` 会在**同一帧**把心切成蓝魂，因此 `heartModeDirty` 必须置位（旧实现漏了这一点，只置了 `heartVelDirty`）。

---

### A-3 `SansSlamDamage` 透传

before（`core.lua:593`）:
```lua
CMD.SansSlamDamage = function(w, b) w.slamDamage = (tonumber(b) ~= 0) end
```
after:
```lua
CMD.SansSlamDamage = function(w, b)
  w.slamDamage = (tonumber(b) ~= 0)
  w.slamDamageDirty = true
end
```

---

### A-4 World→Game 同步：用速度 + 标记，而不是 `push`

before（`core.lua`，`if w.heartVelDirty then ... end`）:
```lua
    if w.heartVelDirty then                  -- SansSlam：只借初速，不动位置
      self.soul.vy = w.heart.vy or 0
      self.soul.vx = w.heart.vx or 0
      -- 【G4】…改成独立冲量 soul.push…
      self.soul.push = { vx = w.heart.vx or 0, vy = w.heart.vy or 0, t = 0.55 }
      w.heartVelDirty = false
    end
```
after:
```lua
    if w.heartVelDirty then                  -- 【A-4】SansSlam：把速度与标记交给蓝魂物理
      self.soul.vx = w.heart.vx or 0
      self.soul.vy = w.heart.vy or 0
      self.soul.dir = w.heart.dir or self.soul.dir or 1
      self.soul.slammed = w.heart.slammed and true or false
      self.soul.push = nil                   -- 不再用冲量
      w.heartVelDirty = false
    end
    if w.slamDamageDirty then                -- 【A-3/A-6】把"甩击是否掉血"接进 Game
      self.slamDamage = w.slamDamage and true or false
      w.slamDamageDirty = false
    end
```

**同时删除** `Game:update` 里旧的 `soul.push` 积分块（`core.lua:1983` 附近）：
```lua
  -- 【G4】冲量（SansSlam）：三种模式共用，位移叠加在位置上，0.55s 内线性衰减
  if self.soul.push then
    local P = self.soul.push
    self.soul.x = self.soul.x + (P.vx or 0) * dt
    self.soul.y = self.soul.y + (P.vy or 0) * dt
    P.t = P.t - dt
    if P.t <= 0 then self.soul.push = nil end
  end
```

---

### A-5 蓝魂物理：改为方向重力（A2 混合版）

**删除**旧的"仅垂直"蓝魂段与 `soul.wall` 分支（`core.lua:1996` 起的 `if self.soul.wall then ...` 与 `core.lua:2017` 起的 `if self.soul.mode == 'blue' and not self.soul.wall then ...`）。

**替换为**（A2 混合：按住 0.25s 匀速上升 / 松手 0.75s 匀速下落，但**沿重力方向**）：

```lua
  -- 【A-5】蓝魂：方向重力（0东/1南/2西/3北）
  if self.soul.mode == 'blue' then
    local DX = { [0]=1, [1]=0, [2]=-1, [3]=0 }
    local DY = { [0]=0, [1]=1, [2]=0,  [3]=-1 }
    local gx = DX[self.soul.dir or 1] or 0
    local gy = DY[self.soul.dir or 1] or 1

    local function vAlong() return self.soul.vx * gx + self.soul.vy * gy end
    local function setVAlong(v)
      local d = v - vAlong()
      self.soul.vx = self.soul.vx + gx * d
      self.soul.vy = self.soul.vy + gy * d
    end

    local mf = self.soul.maxFall
    if mf == nil then mf = 750 end

    -- ── 跳跃手感（A2：沿重力方向做匀速上升/下落）──
    local riseSpeed = JUMP_HEIGHT * self.box.h / JUMP_RISE_T
    local fallSpeed = 0.5 * self.box.h / JUMP_FALL_T
    local maxRise   = JUMP_HEIGHT * self.box.h
    if not self.jumpHeld then self.soul.jumpCut = true end
    local heldT = self.soul.jumpHeldT or 0
    -- 沿 −重力 方向已经上升的位移
    local risen = 0
    if self.soul.jumpBaseX then
      risen = (self.soul.x - self.soul.jumpBaseX) * (-gx) + (self.soul.y - self.soul.jumpBaseY) * (-gy)
    end
    if self.soul.jumping and self.jumpHeld and not self.soul.jumpCut
       and heldT < JUMP_RISE_T - 1e-9 and risen < maxRise - 0.01 then
      setVAlong(-riseSpeed)
      self.soul.jumpHeldT = heldT + dt
    else
      setVAlong(fallSpeed)
    end

    -- ── HeartMaxFallSpeed 封顶（负值 = 反向走廊，与原版一致）──
    if vAlong() > mf then setVAlong(mf) end

    -- ── 位移 ──
    self.soul.x = self.soul.x + self.soul.vx * dt
    self.soul.y = self.soul.y + self.soul.vy * dt
  end
```

**【A1 变体】**若要完全原版，把上面"跳跃手感"整段换成：

```lua
    -- A1：原版 = 初速 180（沿 −重力），松手把上升速度截到 30
    if self.soul.jumping and not self.jumpHeld then
      if vAlong() < -HEART_JUMPHOLD_CUTOFF then setVAlong(-HEART_JUMPHOLD_CUTOFF) end
      self.soul.jumping = false
    end
    -- 4 档重力曲线（按 vAlong 分档；沿重力方向施加）
    local va = vAlong()
    local g
    if va > 15 and va < 240 then g = 540
    elseif va <= 15 and va > -30 then g = 180
    elseif va <= -30 and va > -120 then g = 450
    else g = 180 end
    self.soul.vx = self.soul.vx + gx * g * dt
    self.soul.vy = self.soul.vy + gy * g * dt
    if vAlong() > mf then setVAlong(mf) end
    self.soul.x = self.soul.x + self.soul.vx * dt
    self.soul.y = self.soul.y + self.soul.vy * dt
```

**"贴地"判定（沿重力方向）**：把原来只看"底边"的 `grounded` 改成沿重力方向：

```lua
  -- 【A-5】沿重力方向贴到框边 = 站住
  local b = self.box
  local gx2 = ({[0]=1,[1]=0,[2]=-1,[3]=0})[self.soul.dir or 1] or 0
  local gy2 = ({[0]=0,[1]=1,[2]=0,[3]=-1})[self.soul.dir or 1] or 1
  local px = self.soul.x + gx2 * SOUL_CLAMP
  local py = self.soul.y + gy2 * SOUL_CLAMP
  local onBox =
       (gx2 > 0 and px >= b.x + b.w) or (gx2 < 0 and px <= b.x)
    or (gy2 > 0 and py >= b.y + b.h) or (gy2 < 0 and py <= b.y)
  if onBox then
    -- 沿重力方向的速度清零，并把位置钉到边界
    if gx2 > 0 then self.soul.x = b.x + b.w - SOUL_CLAMP
    elseif gx2 < 0 then self.soul.x = b.x + SOUL_CLAMP end
    if gy2 > 0 then self.soul.y = b.y + b.h - SOUL_CLAMP
    elseif gy2 < 0 then self.soul.y = b.y + SOUL_CLAMP end
    setVAlong(0)
    self.soul.grounded = true
  end
```
（平台同理：沿重力方向的平台面 = 可站立面。）

---

### A-6 撞墙判定 + 伤害 + 抖屏

在 **钳位之前**插入（同一帧里"撞墙"要用未钳位的坐标判断）：

```lua
  -- 【A-6】撞墙判定（原版：Slammed + HeartCheckSolid + |v|>330）
  do
    local b = self.box
    local hitL = self.soul.x <= b.x + SOUL_CLAMP
    local hitR = self.soul.x >= b.x + b.w - SOUL_CLAMP
    local hitT = self.soul.y <= b.y + SOUL_CLAMP
    local hitB = self.soul.y >= b.y + b.h - SOUL_CLAMP
    if self.soul.slammed and (hitL or hitR or hitT or hitB) then
      self.soul.slammed = false
      local v = math.max(math.abs(self.soul.vx), math.abs(self.soul.vy))
      if v > 330 then                                  -- 原版阈值
        self:sansShake(math.floor(v / 90))             -- 原版 floor(|v|/30/3)
        self:playSfx('slam')                           -- 可选（见 A-11）
        if self.slamDamage and self.hp > 1 then        -- 原版保底 HP>1，直接扣，不走无敌帧
          self.hp = self.hp - 1
          self:log('slam_damage hp=' .. self.hp)
        end
      end
      if hitL or hitR then self.soul.vx = 0 end
      if hitT or hitB then self.soul.vy = 0 end
    end
  end
```

> 关键点：原版的甩击伤害**不走 `Game:hurt` 的无敌帧**，而是直接 `HP -= 1`（且要求 `HP > 1`）。用 `hurt()` 会被 i-frame 吞掉，且会额外加 KR —— 那是**骨刺**的伤害路径，不是甩击的。

---

### A-7 移植 `SansShake`

**core 状态**（`resetRun` 里补）:
```lua
  self.shakeI, self.shakeT, self.shakeX, self.shakeY = 0, 0, 0, 0
```
**core 方法**:
```lua
function Game:sansShake(intensity)
  self.shakeI = math.max(0, math.floor(intensity or 0))
  self.shakeT = 0
end
```
**`Game:update` 每帧**（放在最前面，任何状态都生效）:
```lua
  if (self.shakeI or 0) > 0 then
    self.shakeT = (self.shakeT or 0) + dt
    while self.shakeT >= 1 / 30 do
      self.shakeT = self.shakeT - 1 / 30
      self.shakeI = self.shakeI - 1
      self.shakeX = self.shakeI * ((self.rng() < 0.5) and -1 or 1)
      self.shakeY = self.shakeI * ((self.rng() < 0.5) and -1 or 1)
      if self.shakeI <= 0 then self.shakeX, self.shakeY = 0, 0 break end
    end
  end
```
**`M.render`**：在 `cmds` 最前面推一条：
```lua
  push(cmds, { kind = 'shake', x = g.shakeX or 0, y = g.shakeY or 0 })
```
**`main.lua`**：
- `frameBegin()` 里 `SHKX, SHKY = 0, 0`；
- `draw()` 的第一轮循环里：
  ```lua
  if cmd.kind == 'shake' then SHKX, SHKY = cmd.x or 0, cmd.y or 0 end
  ```
- 坐标助手加偏移（`SHKX/SHKY` 是世界像素，要乘 `S`）：
  ```lua
  local function wx(x) return OX + x * S + (SHKX or 0) * S end
  local function wyBottom(yBottom) return OY + (H - yBottom) * S + (SHKY or 0) * S end
  ```
- `DRAW` 表**不要**登记 `shake`（它不是绘制，只是设置偏移）。

---

### A-8 重写 `Game:jump`

before（`core.lua`）:
```lua
function Game:jump()
  if self.state ~= 'enemy' or self.soul.mode ~= 'blue' then return end
  local coyote = (self.soul.groundT or 99) <= 0.12
  if self.soul.wall then ... end            -- 箭头模块：反方向冲刺（方案甲删除）
  if self.soul.jumping then return end
  if self.soul.grounded or coyote then
    self.soul.vy = -(JUMP_HEIGHT * self.box.h / JUMP_RISE_T)
    ...
  end
end
```
after（A2；沿 −重力方向）:
```lua
function Game:jump()
  if self.state ~= 'enemy' or self.soul.mode ~= 'blue' then return end
  local coyote = (self.soul.groundT or 99) <= 0.12
  if self.soul.jumping then return end
  if self.soul.grounded or coyote then
    local DX = { [0]=1, [1]=0, [2]=-1, [3]=0 }
    local DY = { [0]=0, [1]=1, [2]=0,  [3]=-1 }
    local gx = DX[self.soul.dir or 1] or 0
    local gy = DY[self.soul.dir or 1] or 1
    local rise = JUMP_HEIGHT * self.box.h / JUMP_RISE_T      -- A2；A1 用 180
    self.soul.vx = self.soul.vx - gx * rise
    self.soul.vy = self.soul.vy - gy * rise
    self.soul.grounded = false
    self.soul.jumping = true
    self.soul.jumpCut = false
    self.soul.jumpHeldT = 0
    self.soul.jumpBaseX, self.soul.jumpBaseY = self.soul.x, self.soul.y
  end
end
```
**【A1 变体】**把 `rise` 换成 `HEART_JUMP_STRENGTH`，并在物理段做"松手截断 30"。

---

### A-9 `bonestab1/2/3` 回到原版 `BoneStab` 三档

把 `lua/attacks.lua` 里三份脚本（约 1018 / 1058 / 1098 行）整体替换为下面的内容（去掉 `HeartWall` / `ArrowBone`；`HeartMode,0` 是起始红魂，`SansSlam` 自己会切蓝）：

**`sans_bonestab1`**
```
0,CombatZoneResize,241,226,406,391,TLResume
0,HeartTeleport,320,304
0,HeartMode,0
0,TLPause
0,SET,Loop,9
0,JMPZ,26,$Loop
0,SUB,Loop,$Loop,1
0,RND,Direction,4
0,ADD,Jump,$Direction,1
0,JMPREL,$Jump
0,JMPREL,4
0,JMPREL,5
0,JMPREL,6
0,JMPREL,7
0,SansBody,HandRight
0,JMPREL,7
0,SansBody,HandDown
0,JMPREL,5
0,SansBody,HandLeft
0,JMPREL,3
0,SansBody,HandUp
0,JMPREL,1
0.26666,SansSlam,$Direction
0.2,BoneStab,$Direction,25,0.4,0.33333
0.43333,JMPABS,6
0,EndAttack
```
**`sans_bonestab2`**：同 b1，仅最后两行参数改为 `25,0.3,0.2`。
**`sans_bonestab3`**：同 b1，仅参数改为 `29,0.4,0`。

> `ArrowBone` 与 `HeartWall` 这两个命令**可以保留在 CMD 表里**（供将来做新玩法 / 调试），但不要再出现在 `bonestab1/2/3`。若坚持不用，可从 `CMD` 表删除；注意 `core_selftest` 的 `extra-cmd-coverage` 列表里目前含 `HeartWall`/`ArrowBone`（见 §5）。

---

### A-10 `main.lua` 蓝魂输入掩码

方向重力下，"跳跃键"仍只有**一个**（确认键 / 上推），但左右移动要保留。当前掩码：

```lua
if blue then
  coreInput = { left = input.left, right = input.right, up = false, down = false, jumpHeld = input.up }
end
```
**保持 up/down 的掩码是合理的**（蓝魂只读左右移动 + 确认键跳跃）—— 前提是"跳跃 = 沿 −重力方向"，这正是 A-8 的实现。
因此 A-10 在 A1/A2 下**无需改动**；只有当你想在 4 方向重力下用"方向键朝向重力方向"做位移时，才需要放开 up/down。

---

### A-11 音效（可选）

当前 `CMD.Sound = function(w, n) say(w, 'sound ' .. tostring(n)) end` 只写日志。若要还原撞击反馈，需要在适配层加音频出口（`slam` / `player_damaged`），并让 `Game:playSfx(name)` 转发。**平台相关，未验证，列为可选。**

---

### A-12 测试同步（见 §5）

---

## 4. 完整关键代码（可整段替换）

### 4.1 `CMD.SansSlam`（A-2）
见 §3 A-2 的 after 代码。

### 4.2 蓝魂物理（A-5，A2 混合版）
见 §3 A-5 的 after 代码（含 `vAlong/setVAlong`、方向重力、`HeartMaxFallSpeed` 封顶、位移）。

### 4.3 撞墙（A-6）
见 §3 A-6。

### 4.4 `SansShake`（A-7）
见 §3 A-7。

---

## 5. 测试同步清单

### 5.1 会被方案甲改红的现有断言

| 文件 | 位置 | 断言 | 处理 |
|---|---|---|---|
| `lua/core_selftest.lua` | `blue-jump` 段（约 1044–1085） | "按住 0.25s 升到 3/5 框高"、"0.1s = 0.24 框高（线性）"、"上升高度与按住时长成正比"、"下落 0.5框高/0.75s" | **A2 下多数保留**（仍是匀速）；**A1 下全部重写**为"冲量 180 + 松手截断" |
| `lua/core_selftest.lua` | `extra-wall-slam`（716） | 只断言 `w.slamDamage` / `w.heart.dir` / `w.heart.vx` | 补一条"撞墙 → HP-1"的 Game 级断言 |
| `lua/core_selftest.lua` | `extra-cmd-coverage`（726） | 命令覆盖表含 `HeartWall`/`ArrowBone` | 若删命令则同步删；若保留则不动 |
| `lua/_input.lua` | 659–721 | `pc4-blue-jump-vy-negative`（vy<-50）、`lifts-y`、`hold-no-repeat` | A2 下保留；A1 下 `vy<-50` 仍成立（-180），但 hold/落差曲线要复测 |
| `lua/_probe_dur.lua` | 21–35 | 走 World 层测 SansSlam（现为 0） | 改成 Game 层（同 `_probe_game.lua`），或删除该段 |
| `lua/_probe_game.lua` | 18–35 | 走 `HeartWall` 测 push 位移 | 改为测"方向重力 + 撞墙" |

### 5.2 新增断言（建议写进 `core_selftest.lua`）

```lua
-- A1 方向重力：dir=0 甩击后 x 增大；dir=2 减小；dir=1/3 对应 y
-- A2 撞墙伤害：MaxFall=400 + SlamDamage=1 撞墙 → hp-1；MaxFall=300 → hp 不变；SlamDamage=0 → hp 不变
-- A3 Slammed 生命周期：甩出 true → 撞墙 false
-- A4 SansShake：强度 = floor(|v|/90)，每 1/30s -1
-- A5 BoneStab 三档：Distance 25/25/29、Warn 0.4/0.3/0.4、Stay 0.333/0.2/0
```

---

## 6. 风险与回退

| 风险 | 说明 | 缓解 |
|---|---|---|
| 推翻"匀速跳跃"验收 | A1 会改掉你此前要求的 0.25s/0.75s 手感 | 用 **A2**（方向匀速），手感不变、只是方向可变 |
| `_geometry` 对账 | 判定逻辑不变，但灵魂位移轨迹变化，可能触发新的对账断言 | 改完先 `node tools/run-lua.mjs lua/_geometry.lua` 看差异 |
| 存挡/回归 | 改任何 lua 必须重建存档 | `node tools/build-save.mjs` |
| `HeartWall` 残留 | 删命令会影响覆盖表 | 保留命令、只从 CSV 移除（推荐） |
| KR 交互 | 甩击伤害**不**加 KR（原版是直接 HP-1） | 用 §3 A-6 的实现，别走 `hurt()` |

---

## 7. 验收与复现

```powershell
cd D:\stars\workspace\sans-fight
node tools/build-save.mjs
node tools/run-lua.mjs lua/core_selftest.lua   # 期望全绿；blue-jump 段按 A1/A2 调整
node tools/run-lua.mjs lua/_geometry.lua       # 绘制==判定（最慢，约 5 分钟）
node tools/verify-all.mjs --quick
```

手工验收（试玩页 `http://127.0.0.1:4173/`，看日志 `build=`）：
1. 进 ROUND 17/18/22（`bonestab`）：Sans 抬手 → 灵魂被甩向该方向 → 撞框有**抖动**；难度「原作」下撞得够快会掉血；
2. 进 ROUND 24（`final` 阶段⑤）：BlueEye 亮起后连续甩击，`SansSlamDamage 1` 生效（撞框掉血）；
3. 蓝魂关卡（bonegap/bluebone）：重力方向为下，左右移动 + 上键跳跃与改动前一致（A2）。

---

## 附录：行号索引

| 内容 | 位置 |
|---|---|
| `CMD.SansSlam` | `lua/core.lua:583` |
| `CMD.SansSlamDamage` | `lua/core.lua:593` |
| `CMD.HeartWall` / `CMD.ArrowBone` | `lua/core.lua:670` / `677` |
| `soul.push` 积分 | `lua/core.lua:1983` 起（删除） |
| 蓝魂物理（垂直模型） | `lua/core.lua:2017` 起（替换） |
| World→Game 同步 | `lua/core.lua` `if w.heartVelDirty then` 段 |
| `Game:jump` | `lua/core.lua` `function Game:jump` |
| `main.lua` 蓝魂掩码 | `lua/main.lua:1851` 起 |
| `main.lua` 坐标助手 | `lua/main.lua:448` `wx` / `449` `wyBottom` |
| `main.lua` 绘制循环 | `lua/main.lua:1162` `draw()` |
| `bonestab1/2/3` | `lua/attacks.lua:1018 / 1058 / 1098` |
| `blue-jump` 断言 | `lua/core_selftest.lua:1044` 起 |
| `extra-wall-slam` 断言 | `lua/core_selftest.lua:716` |
| 原版 `SansSlam` | `D:\stars\_analysis\Battle.xml.txt` `On function SansSlam`（约 619 行） |
| 原版撞墙处理 | 同上 `PlayerHeart On horizontal/vertical step`（约 667 行） |
| 原版 `HeartJump` | 同上 `On function HeartJump` |
| 原版 `SansShake` | 同上 `GROUP: SansShake` |
| 原版 `bonestab1/2/3` | `D:\c2-sans-fight-src\Files\sans_bonestab{1,2,3}.csv` |

---

*本文是"方案甲"的实施说明；所有 before 代码均取自工作区当前版本，after 代码按原版语义给出，可直接落地。*
