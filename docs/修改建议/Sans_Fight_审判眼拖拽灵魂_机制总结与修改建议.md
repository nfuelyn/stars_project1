# 原版「审判眼 · 拖拽灵魂」攻击机制总结 与 工作区错误实现修改建议

- **原版来源**：`D:\c2-sans-fight-src`（Construct 2 版 Bad Time Simulator，commit 0bb6afe）
- **工作区**：`D:\stars\workspace\sans-fight`（`lua/core.lua` / `lua/attacks.lua` / `lua/main.lua`）
- **方法**：原版 `Event sheets/Battle.xml` + `Files/*.csv` 逐行对照；工作区代码逐行审计
- **日期**：2026-10-06

**术语**
- **审判眼** = `SansHead,BlueEye`（Sans 左眼亮蓝的招牌表情）
- **拖拽灵魂** = `SansSlam,<dir>`（把人灵魂甩向战斗框某条边；原版由「蓝魂 + 方向重力」实现）

---

## 0. 结论速览

原版的「审判眼拖拽」是 **蓝魂重力甩击** 机制；工作区把它改成了 **贴墙模式 + 衰减冲量 + 整边升骨** 的自创玩法，两者不是同一件事。

| 维度 | 原版（C2 仓库） | 工作区现状 | 判定 |
|---|---|---|---|
| 灵魂模式 | `SansSlam` **强制切成蓝魂**（`HeartMode(HEARTMODE_BLUE)`） | `HeartMode,1` + `HeartWall,1` → **贴墙模式（无重力）** | ❌ 机制被替换 |
| 位移模型 | 沿角度**满速甩出**（`MaxFallSpeed`），撞墙即停 | `soul.push`：0.55s **线性衰减**的冲量，穿墙滑动 | ❌ 手感不同 |
| 蓝魂重力方向 | **4 方向**：重力沿 `PlayerHeart.Angle = dir*90` | **只垂直**：`soul.dir` 只写不读，重力恒向下 | ❌ 方向重力缺失 |
| 撞墙判定 | `Slammed` + `HeartCheckSolid` → 撞墙处理 | **完全没有** | ❌ 缺失 |
| 撞击伤害 | 撞墙速度 `>330` → 伤害音 + `SansShake`；`SlamDamage` 控制是否 -1 HP | `slamDamage` **只写不读** → 最终 38 连砸**不掉血** | ❌ 失效 |
| 撞击反馈 | `Slam` + `PlayerDamaged` 音效 + 屏幕抖动 | 工作区**没有音频系统**（`CMD.Sound` 只写日志）、**没有 SansShake** | ❌ 缺失 |
| 骨刺 | `BoneStab`：单侧骨刺，Distance 25/25/29、Warn 0.4/0.3/0.4、Stay 0.333/0.2/0 | `ArrowBone`：**整条边**升起一排骨，深度 `min(1/4框宽, 3/5框高)` | ❌ 形状/尺寸不同 |
| 三档差异 | `bonestab1/2/3` 参数各不相同 | 三份脚本**合并成同一套模板** | ❌ 差异丢失 |
| 跳跃 | 沿**重力反方向**、初速 180、4 档重力曲线 | 贴墙模式：朝箭头反方向**冲刺 0.5 框高**（不走重力） | ❌ 模型不同 |
| 适配层输入 | — | 蓝魂态把 `up/down` 掩成 false → 贴墙模式号称"四向"实际**只有左右** | ❌ 自相矛盾 |

**一句话结论**：工作区的「箭头模块」既没有原版的**方向重力**，也没有原版的**撞墙伤害/反馈**，`SansSlamDamage 1` 是死代码；它是一套全新的自创玩法，不是原版「审判眼拖拽」的移植。

---

## 1. 原版机制详解

### 1.1 审判眼出现的两处

| 位置 | CSV | 行 | 内容 |
|---|---|---|---|
| 初见杀 | `sans_intro.csv` | 12 / 14 / 17 | `SansHead,BlueEye` → `SansSlam,1` → `BoneStab,1,54,0.16666,1` |
| 最终阶段⑤ | `sans_final.csv` | 157–212 | `SansHead,BlueEye` → `HeartMaxFallSpeed,750` → `SansSlamDamage,1` → **38 次连续甩击** |

另外每个循环都会先做 `SansBody,HandRight/HandDown/HandLeft/HandUp`（手指向哪个方向），再做同方向的 `SansSlam`。

### 1.2 `SansSlam` 的 5 步（原版 `Battle.xml`，SansSlam 函数）

```
IF Function On function (Name="SansSlam")
  IF param(0) >= 0 AND param(0) <= 3
    DO HeartMode(HEARTMODE_BLUE)              -- ① 强制切蓝魂
    DO PlayerHeart.Slammed = 1                -- ② 标记"正在被甩"
    DO PlayerHeart.Angle = floor(param0)*90   -- ③ 设定重力/甩出方向
    DO PlayerHeart.speed(1) = cos(Angle)*MaxFallSpeed   -- ④ 满速甩出
    DO PlayerHeart.speed(2) = sin(Angle)*MaxFallSpeed
```

关键点：**`SansSlam` 自己就会把灵魂变成蓝魂**（不需要脚本另外写 `HeartMode`），并把心的 `Angle` 设成甩击方向 —— 蓝魂的重力方向就跟着变成那条边。

### 1.3 蓝魂 = 4 方向重力

原版蓝魂的重力**不是恒向下**，而是沿 `PlayerHeart.Angle`：

- 重力方向 `X,Y = cos(Angle), sin(Angle)`；`Angle = dir*90`（0 东 / 1 南 / 2 西 / 3 北）。
- `HeartJump()` = 沿**重力反方向**，初速 `HEART_JUMP_STRENGTH = 180`，且必须先 `HeartCheckSolid(cos,sin)==1`（贴着"地面"）才能起跳：
  ```
  X = cos(Angle); Y = sin(Angle)
  IF HeartCheckSolid(X, Y) == 1:
     speed(1) -= X * 180
     speed(2) -= Y * 180
  ```
- 重力按"沿重力方向的速度 `DownSpeed`"分 4 档：`(15,240)→540`、`(−30,15]→180`、`(−120,−30]→450`、`≤−120→180`，并以 `MaxFallSpeed` 封顶。

> 所以原版的体验是：**被甩向某条边 → 重力也朝那条边 → 按跳跃键朝反方向弹回**。工作区没有这一层。

### 1.4 撞墙判定与撞击伤害（原版 `PlayerMovement` 组）

```
IF PlayerHeart On horizontal/vertical step
IF HeartCheckSolid(0,0) == 1                 -- 贴到 CombatZoneBorder / Platform
  IF PlayerHeart.Slammed:
     PlayerHeart.Slammed = 0
     IF abs(dx 或 dy) > 330:                 -- 只有够快才算"砸"
        Play PlayerDamaged + Play Slam
        SansShake(floor(abs(v)/30/3))        -- 屏幕抖动
        IF PlayerHeart.SlamDamage AND HP > 1:
           HP -= 1
  把该轴速度归零
```

即：**甩得够快撞墙 → 有音效 + 屏幕抖动 + （可选）1 点伤害**；`SansSlamDamage(0/1)` 就是这条伤害的开关。

### 1.5 `HeartMaxFallSpeed`：既是终端速度，也是甩出速度

| 值 | 用在哪 | 效果 |
|---|---|---|
| 750（默认） | `ResetVars` | 常规最大下落速度 |
| 450 | `sans_final` L32 | 加速甩击 |
| −300 | `sans_final` L37 | **反向重力走廊**（向上吸） |
| 330 | `sans_final` L94 | 最终连砸前的基准 |
| 0 | `sans_final` L45 | 关闭下落（悬浮） |
| 480 / 330 / 240 / 60 | `sans_final` L188/197/204/209 | 38 连砸里**逐级降低**甩出速度 |

### 1.6 `BoneStab`：单侧骨刺（不是整边升骨）

参数 `Direction, Distance, WarnTime, StayTime`：先在框边生成同尺寸**预警块**并等待 `WarnTime`，再以 `Distance*10 px/s` 从那条边弹出 `Distance` 距离，停留 `StayTime` 后收回。

三档差异（原版 CSV）：

| 脚本 | Direction | Distance | WarnTime | StayTime |
|---|---|---|---|---|
| `sans_bonestab1` | 随机 0–3 | **25** | **0.4** | **0.33333** |
| `sans_bonestab2` | 随机 0–3 | **25** | **0.3** | **0.2** |
| `sans_bonestab3` | 随机 0–3 | **29** | **0.4** | **0** |

### 1.7 一个完整循环（`sans_bonestab1.csv` L15–L24）

```
0,SansBody,HandRight      -- 手指向方向（随机跳转表选出的那个）
...
0.26666,SansSlam,$Direction   -- 甩向该方向（内部强制蓝魂 + 满速）
0.2,BoneStab,$Direction,25,0.4,0.33333   -- 同一侧弹出骨刺
...
0.43333,JMPABS,6          -- 下一轮
```

### 1.8 最终阶段⑤：38 连砸（`sans_final.csv` L157–L212）

- L157：`1,SansHead,BlueEye` → **审判眼亮起**
- L158–L160：`HeartMaxFallSpeed,750`、`SansBody,HandRight`、`SansSlamDamage,1`（**这次会真的掉血**）
- L161–L174：`I=0..38` 循环；方向交替且避免与上一次相同（L166–L174 的跳转表）
- L175–L182：按方向做 `SansBody,Hand*` → `$Wait1` 后 `SansSlam,$Direction`
- L184–L190：I 为偶数才随机换方向；`I≥21` 时把 MaxFall 降到 480、Wait 降到 0.2
- L191–L199：`I≥25` → `SansHead,Default` + 汗 1；`I≥33` → `Tired1` + 汗 2 + MaxFall 330 + Wait 0.5/1.1
- L200–L205：`I=35` → MaxFall 240 + 强制朝北（`Direction,3`）
- L206–L209：`I=36` → `Tired2` + 汗 3 + MaxFall 60
- L212：`SansAnimation,Tired` 收尾

这是一段"越来越快、甩击越来越弱、Sans 越来越累"的表演，**核心乐趣来自方向重力 + 撞墙伤害**。

---

## 2. 工作区错误实现详解（逐条）

### 2.1 `HeartWall` 贴墙模式替换了蓝魂重力 —— 机制被换掉

工作区 `attacks.lua` 的 `sans_bonestab1/2/3` 开头是：

```
0,HeartMode,1
0,HeartWall,1     -- ← 本项目扩展命令，原版没有
```

`core.lua` 的 `CMD.HeartWall` 把灵魂切进"贴墙模式"（注释自称"不吃普通蓝心的重力/悬停规则，四向自由移动"）。这直接**删掉了原版蓝魂的方向重力**，改用 `soul.push` 冲量 + `dash` 冲刺。

### 2.2 `SansSlam` 退化成 0.55s 线性衰减的冲量

工作区 `CMD.SansSlam`：

```lua
CMD.SansSlam = function(w, d)
  local s = w.heart.maxFall; if not s or s == 0 then s = 240 end
  w.heart.dir = d
  w.heart.vx = (d == 0) and s or ((d == 2) and -s or 0)
  w.heart.vy = (d == 1) and s or ((d == 3) and -s or 0)
  w.heartVelDirty = true
end
```

而 `Game:update` 只把它转成一个 0.55s 衰减的 `soul.push`：

```lua
if self.soul.push then
  self.soul.x = self.soul.x + (P.vx or 0) * dt
  self.soul.y = self.soul.y + (P.vy or 0) * dt
  P.t = P.t - dt
  if P.t <= 0 then self.soul.push = nil end
end
```

对照原版：原版是 `Slammed=1` + `Angle=dir*90` + `speed=MaxFallSpeed` **持续到撞墙**；工作区是"0.55 秒后自己停"，**不存在"甩到框边撞停"**这回事。

### 2.3 `soul.dir` 只写不读 —— 蓝魂只有垂直重力

全工程检索 `soul.dir`：只有 `CMD.SansSlam` 在写（`w.heart.dir = d`），**没有任何物理/判定读取它**。工作区的蓝魂物理是固定"按住上升 / 松手下落"的垂直模型：

```lua
if self.soul.mode == 'blue' and not self.soul.wall then
  local riseSpeed = JUMP_HEIGHT * self.box.h / JUMP_RISE_T
  local fallSpeed = 0.5 * self.box.h / JUMP_FALL_T
  ...
  self.soul.vy = -riseSpeed  或 fallSpeed
  self.soul.y = self.soul.y + self.soul.vy * dt
```

所以：**水平方向的"重力甩击"在原版里靠 4 方向重力实现，在工作区里根本不存在**，只能靠 `push` 滑一下。

### 2.4 `slamDamage` 只写不读 —— 最终 38 连砸不掉血

- `CMD.SansSlamDamage` 只把参数写进 `w.slamDamage`；
- 全工程检索 `slamDamage`：**除自测断言外没有任何读取点**；
- `attacks.lua` 在 `sans_final` 的注释里写"阶段⑤ … SansSlamDamage 1（**这次真的会掉血**）"，与实现矛盾。

结论：**审判眼最终阶段的 38 次甩击，玩家一次都不会因此掉血**，只承担骨刺/光束的伤害。

### 2.5 没有 `Slammed` / 撞墙判定 / SansShake / 撞击音效

- 工作区没有 `Slammed` 实例变量/字段；
- 没有"贴到框边 → 判断撞墙速度"的分支；
- 没有 `SansShake`（原版 `SansShake` 组：`Intensity=int(param)`，每 1/30s 抖一次、强度递减，`Scroll to Center ± Intensity`）；
- 工作区**根本没有音频系统**：`CMD.Sound = function(w,n) say(w,'sound '..tostring(n)) end` 只写日志，不播放；原版的 `Slam` / `PlayerDamaged` 音效无从谈起。

### 2.6 `ArrowBone` 整边升骨 ≠ 原版 `BoneStab`

工作区 `CMD.ArrowBone`：

```lua
local depthW = 0.25 * (z.r - z.l)
local depthH = JUMP_HEIGHT * h
local maxRise = math.min(depthW, depthH)
-- 命中矩形 = 整条边向内伸出 maxRise（见 World:stabRect 的 arrowbone 分支）
```

原版 `BoneStab` 是**单条骨刺**，`Distance` 只有 25/25/29px；工作区是**整条边**升起一排骨头，深度取 `min(1/4 框宽, 3/5 框高)`（在 406×165 的框里约 101×101 → 实际 101px 深），量级完全不同。

### 2.7 `bonestab1/2/3` 被合并成同一套模板

工作区三份脚本的注释明确写"bonestab1/2/3 共用同一份内容…原版差异参数（距离 25/25/29、预警 0.4/0.3/0.4、停留 0.333/0.2/0）**已废弃**"。因此：

- 三个回合的**节奏、预警时间、停留时间完全一样**（bonestab3 只是把延时 0.8→0.9、停留 0.3→0.8）；
- 原版"越往后骨刺越难躲"的曲线消失。

### 2.8 适配层在蓝魂态掩掉 `up/down` —— 贴墙"四向"实际只有左右

`main.lua`：

```lua
local blue = (state.state == 'enemy') and state.soul ~= nil and state.soul.mode == 'blue'
...
if blue then
  coreInput = { left = input.left, right = input.right, up = false, down = false, jumpHeld = input.up }
```

`HeartWall` 是通过 `HeartMode,1` + `HeartWall,1` 进入的，`soul.mode` 仍是 `'blue'`，所以**贴墙模式也吃这条掩码** → 玩家在箭头关里按上/下不会上下移动（上会变成"跳跃/冲刺"）。`CMD.HeartWall` 注释里的"四向自由移动"与适配层实现直接冲突。

### 2.9 自测只断言"标记"，不断言"伤害" —— 虚假信心

`core_selftest.lua` 的 `extra-wall-slam` 段：

```lua
local w = M.newWorld({ seed=1, script = M.parseCSV('0,SansSlamDamage,0\n0,HeartMaxFallSpeed,300\n0,HeartMode,1\n0,SansSlam,0\n1,EndAttack\n') })
w:update(DT)
ok(w.slamDamage == false, 'SansSlamDamage 0 → w.slamDamage=false')
ok(w.heart.mode == 1 and w.heart.maxFall == 300 and w.heart.dir == 0, '砸击参数已写入')
ok(w.heart.vx == 300 and w.heart.vy == 0, 'SansSlam 0（东）→ vx=+maxFall、vy=0')
```

它验证的是"参数写进去了"，**没有一条断言"撞墙时 HP 掉 1 / 不掉"**，所以 2.4 的死代码一直没被测试抓到。

### 2.10 注释与实现矛盾清单

| 位置 | 注释说 | 实际 |
|---|---|---|
| `attacks.lua` final 注释 | "SansSlamDamage 1（这次真的会掉血）" | 不掉血 |
| `CMD.HeartWall` 注释 | "四向自由移动" | 适配层掩掉 up/down，只有左右 |
| `CMD.SansSlam` 注释 | "只借初速" | 实际是 0.55s 就消失的 push |
| 第二轮文档 G4 | "三模式统一积分冲量（dx=±136）" | 探针实测 ±64（60 帧），且与"甩到框边"无关 |

---

## 3. 修改建议

### 方案甲（推荐）：回归原版「方向重力 + 撞墙」机制

#### S1 恢复蓝魂的 4 方向重力

让 `soul.dir` 真正驱动物理（当前完全没读）：

```lua
-- 蓝魂物理（替换现有"只垂直"模型）
local GX = { [0]=1, [1]=0, [2]=-1, [3]=0 }
local GY = { [0]=0, [1]=1, [2]=0,  [3]=-1 }
local dx, dy = GX[soul.dir or 1], GY[soul.dir or 1]
-- 沿重力方向积分 + MaxFallSpeed 封顶
soul.vx = soul.vx + dx * gravity * dt
soul.vy = soul.vy + dy * gravity * dt
local vAlong = soul.vx * dx + soul.vy * dy
if vAlong > maxFall then
  soul.vx = soul.vx - dx * (vAlong - maxFall)
  soul.vy = soul.vy - dy * (vAlong - maxFall)
end
-- 跳跃 = 沿 -重力方向，初速 180，且需贴地
```

重力分档沿用原版：`(15,240)→540`、`(−30,15]→180`、`(−120,−30]→450`、`≤−120→180`（按 `vAlong` 判）。这不是"再调参"，而是把现有的"匀速上升/下落"模型换成原版模型 —— 后者同样可以保留"按住变高跳"的手感（按住把 `vAlong` 托在 `-30` 附近即可，原版就是 `HEART_JUMPHOLD_CUTOFF=30`）。

#### S2 `SansSlam` 恢复为「强制蓝魂 + 满速甩出 + Slammed」

```lua
CMD.SansSlam = function(w, d)
  d = clamp(floor(tonumber(d) or 0), 0, 3)
  w.heart.mode = 1                      -- 强制蓝魂（原版行为）
  w.heart.dir = d
  w.heart.slammed = true
  local s = w.heart.maxFall; if not s or s == 0 then s = 750 end
  w.heart.vx = ({[0]=s,[1]=0,[2]=-s,[3]=0})[d]
  w.heart.vy = ({[0]=0,[1]=s,[2]=0,[3]=-s})[d]
  w.heartModeDirty, w.heartVelDirty = true, true
end
```

并用"持续到撞墙"替代"0.55s 后消失"：不要给 push 设固定 `t`，而是把速度直接交给蓝魂物理，由撞墙/贴地来清零。

#### S3 恢复撞墙判定 + 伤害 + 抖屏 + 音效

在 `Game:update` 的位置结算之后、边界钳位之前，加"撞墙"检测：

```lua
if soul.slammed then
  local hitX = (soul.x <= box.x + SOUL_CLAMP or soul.x >= box.x + box.w - SOUL_CLAMP)
  local hitY = (soul.y <= box.y + SOUL_CLAMP or soul.y >= box.y + box.h - SOUL_CLAMP)
  if hitX or hitY then
    soul.slammed = false
    local v = math.max(math.abs(soul.vx), math.abs(soul.vy))
    if v > 330 then
      self:sansShake(math.floor(v / 90))
      self:play('Slam'); self:play('PlayerDamaged')
      if self.worldSlamDamage and self.hp > 1 then self:hp = self.hp - 1 end
    end
    if hitX then soul.vx = 0 end
    if hitY then soul.vy = 0 end
  end
end
```

同时把 `CMD.SansSlamDamage` 的 `w.slamDamage` **真正传进 Game**（当前只写不读）：可在 world→game 同步时读 `w.slamDamage` 存到 `self.worldSlamDamage`。

#### S4 补 `SansShake`（当前完全没有）

按原版移植到 core 的渲染层：`shakeIntensity`、`shakeTimer`，每 `1/30s` 强度 -1，渲染时给整个世界加 `(±intensity, ±intensity)` 的偏移；调用点：撞墙、龙骨炮开火、以及原版 `SansShake` 的其它调用处。

#### S5 音效（工作区当前无音频）

如果要还原撞击反馈，需要在适配层接一个音频通道（`Slam` / `PlayerDamaged` / `GasterBlaster` / `Flash`…）。这依赖千星客户端的音频能力，属于平台侧工作；至少应把 `CMD.Sound` 从"只写日志"改成真正的事件出口。

#### S6 `bonestab1/2/3` 回归 `BoneStab` 三档

- 把 `ArrowBone` 从 `bonestab1/2/3` 移出，改回 `BoneStab,$Direction,25,0.4,0.33333`（b1）、`25,0.3,0.2`（b2）、`29,0.4,0`（b3）；
- 若仍想要"整边升骨"的表现，把它作为**新扩展**用在别处，而不是覆盖原版骨刺。

#### S7 修适配层的 `up/down` 掩码

```lua
local blue = state.soul.mode == 'blue'
local wall = state.soul.wall == true      -- 贴墙模式需要真正的上下移动
if blue and not wall then
  coreInput.up, coreInput.down = false, false
  coreInput.jumpHeld = input.up
else
  coreInput.up, coreInput.down = input.up, input.down
end
```

（若按方案甲删掉 `HeartWall`，这条自然消失——但蓝魂的"只读左右 + 跳跃"语义仍要保留。）

#### S8 审计其它"只写不读"的字段

以 `slamDamage` 为戒，用脚本扫一遍 `CMD.*` 写入、但全工程无读取的实例变量（`heart.dir`、`heart.slammed`、`world.slamDamage`、`heartModeDirty` 的部分分支…），逐个确认是"预留"还是"死代码"。

#### S9 更新自测/断言

见 §4。

### 方案乙（妥协：保留箭头模块，但补齐它的"错"）

如果产品上确实想要"箭头 + 整边升骨"这套自创玩法，那么至少要修掉四处硬伤：

1. **贴墙模式也要有方向重力**：`soul.wall` 时同样读 `soul.dir`，让"拖到那条边"由重力完成（而不是 0.55s 冲量）；
2. **恢复撞墙伤害**：贴到框边且速度 >330 → `SansShake` + 伤害（受 `SlamDamage` 控制）；
3. **解禁上下移动**：修 S7 的掩码，否则"四向自由移动"是假的；
4. **补反馈**：至少在撞墙/升骨时给屏幕抖动（音效视平台能力）。

---

## 4. 验收标准（探针 + 断言）

| 编号 | 断言 | 期望 |
|---|---|---|
| A1 | 蓝魂方向重力 | `dir=0` 甩击后 x 单调增大到框右边；`dir=2` 单调减小；`dir=1/3` 同理 y |
| A2 | 撞墙伤害 | `MaxFall=400` + `SlamDamage=1` 撞墙 → `hp -1`；`MaxFall=300` → `hp` 不变；`SlamDamage=0` → `hp` 不变 |
| A3 | `Slammed` 生命周期 | 甩出时 true；撞墙后 false；未撞墙（被跳跃抵消）不误判 |
| A4 | `SansShake` | 强度 = `floor(|v|/90)`，每 1/30s -1，直到 0 |
| A5 | BoneStab 三档 | b1/b2/b3 的 Distance=25/25/29、Warn=0.4/0.3/0.4、Stay=0.333/0.2/0 与 CSV 一致 |
| A6 | 贴墙上下移动 | 在 wall 模式按 up/down，soul.y 必须变化（当前会失败） |
| A7 | 最终阶段⑤ | I=0..38 每次 `SansSlam` 都产生对应方向的位移；`SansSlamDamage=1` 时撞墙可掉血 |

复现命令（工程根目录）：

```powershell
node tools/run-lua.mjs lua/core_selftest.lua   # 现有 283 项
node tools/run-lua.mjs lua/_geometry.lua       # 绘制==判定对账（最慢）
node tools/verify-all.mjs --quick
```

---

## 5. 附录

### A. 行号索引

| 内容 | 位置 |
|---|---|
| 原版 `SansSlam` | `D:\stars\_analysis\Battle.xml.txt` → `On function SansSlam`（约 619 行） |
| 原版 `Slammed` 撞墙处理 | 同上 → `PlayerHeart On horizontal/vertical step`（约 667 行） |
| 原版 `HeartJump` | 同上 → `On function HeartJump`（约 690 行） |
| 原版 `HeartMode` / 蓝魂重力 | 同上 → `PlayerMovement` 组 |
| 原版 `SansShake` | 同上 → `GROUP: SansShake` |
| 原版 `BoneStab` | 同上 → `GROUP: BoneStab` |
| 工作区 `CMD.SansSlam` | `lua/core.lua:583` |
| 工作区 `CMD.SansSlamDamage` | `lua/core.lua:593` |
| 工作区 `CMD.HeartWall` | `lua/core.lua:670` |
| 工作区 `CMD.ArrowBone` | `lua/core.lua:677` |
| 工作区 `soul.push` 积分 | `lua/core.lua:1983` 起 |
| 工作区蓝魂物理（垂直模型） | `lua/core.lua:2017` 起 |
| 工作区墙模式移动 | `lua/core.lua:1996` 起 |
| 工作区 `Game:jump` 墙模式冲刺 | `lua/core.lua` `Game:jump` |
| 工作区 `main.lua` 蓝魂掩码 | `lua/main.lua:1851` 起 |
| 工作区 bonestab1/2/3 | `lua/attacks.lua:1018 / 1058 / 1098` |
| 工作区自测 `extra-wall-slam` | `lua/core_selftest.lua:716` |

### B. 原版 `SansSlam` 代码（节选）

```
IF Function On function (Name="SansSlam")
IF Function Compare parameter (Index=0, Comparison=5, Value=0)
IF Function Compare parameter (Index=0, Comparison=3, Value=3)
DO Function Call function (Name="HeartMode", Parameter=HEARTMODE_BLUE)
DO PlayerHeart Set boolean (Instance variable=Slammed, Value=1)
DO PlayerHeart Set angle (Angle=floor(Function.Param(0))*90)
DO PlayerHeart Set speed (Which=1, Speed=cos(PlayerHeart.Angle)*MaxFallSpeed)
DO PlayerHeart Set speed (Which=2, Speed=sin(PlayerHeart.Angle)*MaxFallSpeed)
```

### C. 工作区 `SansSlam` / push / 墙模式（节选）

```lua
CMD.SansSlam = function(w, d)
  local s = w.heart.maxFall; if not s or s == 0 then s = 240 end
  w.heart.dir = d
  w.heart.vx = (d == 0) and s or ((d == 2) and -s or 0)
  w.heart.vy = (d == 1) and s or ((d == 3) and -s or 0)
  w.heartVelDirty = true
end
-- Game:update：
if self.soul.push then
  self.soul.x = self.soul.x + (P.vx or 0) * dt
  self.soul.y = self.soul.y + (P.vy or 0) * dt
  P.t = P.t - dt
  if P.t <= 0 then self.soul.push = nil end
end
```

### D. 原版 `bonestab1/2/3` 关键行

```
sans_bonestab1: 0.26666,SansSlam,$Direction   0.2,BoneStab,$Direction,25,0.4,0.33333
sans_bonestab2: 0.26666,SansSlam,$Direction   0.2,BoneStab,$Direction,25,0.3,0.2
sans_bonestab3: 0.26666,SansSlam,$Direction   0.2,BoneStab,$Direction,29,0.4,0
```

### E. 原版 `sans_final` 阶段⑤ 行清单（157–212）

```
157 1,SansHead,BlueEye
158 0,HeartMaxFallSpeed,750
159 0,SansBody,HandRight
160 0,SansSlamDamage,1
161 0,SET,I,0
162 0,SET,Direction,0
163 0,SET,LastDir,2
164 0,SET,Wait1,0.13333
165 0,SET,Wait2,0.13333
166 0,JMPNE,168,$Direction,$LastDir
...（方向交替跳转表 166–174）
175 0,SansBody,HandRight
182 $Wait1,SansSlam,$Direction
183 $Wait2,SET,LastDir,$Direction
184 0,MOD,Odd,$I,2
188 0,HeartMaxFallSpeed,480
192 0,SansHead,Default      193 0,SansSweat,1
195 0,SansHead,Tired1       196 0,SansSweat,2       197 0,HeartMaxFallSpeed,330
204 0,HeartMaxFallSpeed,240 205 0,SET,Direction,3
207 0,SansHead,Tired2       208 0,SansSweat,3       209 0,HeartMaxFallSpeed,60
210 0,ADD,I,$I,1            211 0,JMPL,166,$I,38
212 1.5,SansAnimation,Tired
```

---

*本报告的原版结论来自 `D:\c2-sans-fight-src` 的事件表与 CSV；工作区结论来自 `lua/core.lua`/`attacks.lua`/`main.lua`/`core_selftest.lua` 逐行审计。*
