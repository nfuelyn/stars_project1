# 蓝心跳跃修正 + 攻击延时政策变更

- **工作区**：`D:\stars\workspace\sans-fight`
- **对照源**：`D:\c2-sans-fight-src`（`Event sheets/Battle.xml` → `HeartJump` / `HeartCheckSolid` / `PlayerMovement`）
- **日期**：2026-10-06
- **性质**：修改意见文档（含可直接落地的 before/after 代码）

---

## 0. 政策变更（先记一笔，后续文档一律遵守）

> **从本文起，不再对现有攻击延时提出任何要求。** 脚本里已经调过的 `SpinTime / HoldTime / Loop 次数 / 各行 delay / 平台 Ramp / ExtraWidth` 等，都是针对真实手感做的**有意修改**，一律保留，不再要求回退成原版数值。

因此：

- 之前《回合差异与蓝心物理》里所有"把 1.5 改回 0.46666、Loop 2 改回 15、去掉 Ramp"之类的**延时类建议作废**；
- 后续文档只讨论**游戏规则/物理/判定**层面的错误（例如本文的蓝心跳跃），不再以"原版数值"为由要求改延时。

---

## 1. 问题复现：空中板子上跳不起来

我写了两个探针（都在 `D:\stars\workspace\sans-fight\lua\`，可直接重跑）：

```powershell
cd D:\stars\workspace\sans-fight
node tools/run-lua.mjs lua/_probe_groundjump.lua   # 地面：能连跳
node tools/run-lua.mjs lua/_probe_platjump.lua     # 空中板子：第 2 跳被拦
```

**实测输出**：

| 场景 | 站在面上 | 第 1 跳 | 落回后 | 第 2 跳 |
|---|---|---|---|---|
| **地面**（`sans_bonegap1`，框底） | grounded=true, jumping=false | vy=-336 ✅ | grounded=true, **jumping=false** | vy=-336 ✅ |
| **空中板子**（`platforms1` 的脚本平台） | grounded=true, jumping=false | vy=0（见 R3） | grounded=true, **jumping=true** | **vy=0（跳不起来）❌** |

结论：**地面能连续起跳，空中板子不能** —— 落地后 `jumping` 没有被复位，第 2 跳被 `Game:jump` 里的 `if self.soul.jumping then return end` 直接拦掉。

---

## 2. 根因（三条）

### R1（主因）：`jumping` 的"落地复位"写在蓝魂分支里，而空中板子的落地在那之后才检测

当前 `core.lua` 蓝魂分支内（约 2100–2135 行）：

```lua
if self.soul.mode == 'blue' and not self.soul.wall then
  ...
  -- ① 框底（地面）判定
  if self.soul.y >= floorY then self.soul.y = floorY; self.soul.vy = 0; self.soul.grounded = true end
  -- ② 内置平台（self.platforms）判定
  for _, pf in ipairs(self.platforms or {}) do ... self.soul.grounded = true ... end
  -- ③ 落地复位（只在这里！）
  if self.soul.grounded then
    self.soul.jumping = false; self.soul.jumpCut = false; self.soul.jumpBase = nil; ...
  end
end
-- ④ 脚本平台（self.world.platforms）的落地判定在**分支之后**才做：
local lists = { {list=self.platforms}, {list=self.world.platforms, ox=BOX_OFF_X, oy=BOX_OFF_Y} }
for ... if landed then self.soul.y = py - SOUL_CLAMP; self.soul.vy = 0; self.soul.grounded = true end end
```

于是：

- 落在**框底 / 内置平台** → ③ 执行 → `jumping=false` → 能连跳；
- 落在**脚本平台（空中板子）** → ③ 执行时 `grounded` 还是 false → `jumping` 保持 true；④ 之后才把 `grounded=true`，但**没有人再复位 `jumping`** → 下一帧起跳被 `if self.soul.jumping then return end` 拦下。

这就是你说的"空中板子和地面不是一个模子"。

### R2：原版是"一个统一函数"，工作区是"两套判定"

原版（`Battle.xml`）：

```
HeartJump()：
  X = cos(PlayerHeart.Angle); Y = sin(PlayerHeart.Angle)
  IF HeartCheckSolid(X, Y) == 1 THEN   -- ← 沿重力方向有没有实体（框边 **或** Platform1）
     speed(1) -= X * 180
     speed(2) -= Y * 180

HeartCheckSolid(dx, dy)：
  IF 与 CombatZoneBorder 重叠 → 返回 1
  IF 与 Platform1 重叠（且满足方向/相对速度/边界条件）→ 返回 1
  否则返回 0
```

即**框边和平台走同一个函数**。工作区把"框底"写成 `soul.y >= floorY`、把平台写成 AABB + `vy>=0` + `prevY` 容差两套逻辑，天然会不一致。

### R3：用"确认键"起跳时，上升被同帧切断

工作区的跳跃是"按住上升 0.25s / 松手下落"的模型，条件里要求 `self.jumpHeld`。而适配层给 core 的 `jumpHeld = input.up` —— 如果玩家用**确认键**（Enter/Z/J）起跳，`jumpHeld=false`，同一帧的蓝魂物理就会把 `vy` 覆盖成 `fallSpeed`（下落），灵魂原地落回板子，`jumping` 更不会复位。探针里 `confirm=true` 的第 1 跳 vy=0 就是这个原因。

---

## 3. 修改建议（推荐方案：空中板子与地面用同一套模型）

### 3.1 核心思路

用**一个** `groundQuery()` 取代"框底判定 + 平台判定"，完全对应原版的 `HeartCheckSolid`：

- 沿重力方向（`gx,gy = cos/sin(dir*90)`）计算"灵魂前缘"的坐标；
- 在**战斗框的远边**与**所有平台（内置 + 脚本）的远面**里，取**最近的那个实体面**；
- 谁近就用谁吸附 —— 空中板子和地面从此是同一个模子。

### 3.2 新增统一落地函数（放 `core.lua`，替代上面 ① ② ③）

```lua
-- 【统一落地模型】对应原版 HeartCheckSolid(cos(Angle), sin(Angle))：
--   框边 + 平台 一起算，沿重力方向取"最近的实体面"。
-- 返回：面坐标 surface / 重力方向 gx,gy / 灵魂沿重力坐标 soulA / 落在哪个平台 pf（框边为 nil）
function Game:groundQuery()
  local DX = { [0]=1, [1]=0, [2]=-1, [3]=0 }
  local DY = { [0]=0, [1]=1, [2]=0,  [3]=-1 }
  local dir = self.soul.dir or 1
  local gx, gy = DX[dir] or 0, DY[dir] or 1
  local function along(x, y) return x * gx + y * gy end

  local b, r = self.box, SOUL_CLAMP
  local soulA = along(self.soul.x, self.soul.y)

  -- ① 战斗框的"远边" = 地面（dir=1 时就是框底）
  local surface = math.max(along(b.x, b.y), along(b.x + b.w, b.y),
                           along(b.x, b.y + b.h), along(b.x + b.w, b.y + b.h))
  local hitPf = nil

  -- ② 平台：只取"沿重力方向的远面"，横向必须重叠
  local lists = { { list = self.platforms or {}, ox = 0, oy = 0 } }
  if self.world and self.world.platforms then
    lists[#lists + 1] = { list = self.world.platforms, ox = BOX_OFF_X, oy = BOX_OFF_Y }
  end
  for _, spec in ipairs(lists) do
    for _, pf in ipairs(spec.list) do
      local px, py = pf.x - spec.ox, pf.y - spec.oy
      local pw, ph = pf.w or 0, pf.h or 4
      local lateral
      if gy ~= 0 then lateral = (self.soul.x + r > px) and (self.soul.x - r < px + pw)
      else             lateral = (self.soul.y + r > py) and (self.soul.y - r < py + ph) end
      if lateral then
        local far = math.max(along(px, py), along(px + pw, py),
                             along(px, py + ph), along(px + pw, py + ph))
        -- 只接受"在灵魂前方（容许 2px 容差）且比当前面更近"的面
        if far >= soulA - r - 2 and far <= surface then surface, hitPf = far, pf end
      end
    end
  end
  return surface, gx, gy, soulA, hitPf
end
```

在蓝魂物理里，把原来的"框底 + 平台 + 复位"整段替换为：

```lua
  -- 【统一落地】框边与平台一个模子
  self.soul.grounded = false
  local surface, gx, gy, soulA, hitPf = self:groundQuery()
  local lead = soulA + SOUL_CLAMP                 -- 灵魂沿重力方向的前缘
  if lead >= surface - 2 then                     -- 贴到实体面
    local d = surface - lead                      -- 需要沿重力方向补偿的距离
    if d > 0 then
      self.soul.x = self.soul.x + gx * d
      self.soul.y = self.soul.y + gy * d
    end
    -- 只清"沿重力方向"的速度，保留切向输入
    local va = (self.soul.vx or 0) * gx + (self.soul.vy or 0) * gy
    if va > 0 then
      self.soul.vx = self.soul.vx - gx * va
      self.soul.vy = self.soul.vy - gy * va
    end
    self.soul.grounded = true
    -- 平台带走（保留原有体验）：水平平台携带 soul
    if hitPf then
      local pvx = hitPf.vx or ((hitPf.dir == 0 and (hitPf.speed or 0)) or (hitPf.dir == 2 and -(hitPf.speed or 0)) or 0)
      if pvx ~= 0 then
        self.soul.x = clamp(self.soul.x + pvx * dt, self.box.x + SOUL_CLAMP, self.box.x + self.box.w - SOUL_CLAMP)
      end
    end
  end
  -- 【关键】落地复位**统一放在这里**：不管落在框底还是空中板子都生效
  if self.soul.grounded then
    self.soul.jumping = false
    self.soul.jumpCut = false
    self.soul.jumpBase, self.soul.jumpBaseX, self.soul.jumpBaseY = nil, nil, nil
    self.soul.jumpHeldT = 0
  end
```

同时**删除**原来蓝魂分支里的三块：框底 `floorY` 判定、`for _, pf in ipairs(self.platforms)` 判定、以及分支末尾的 `if self.soul.grounded then ... jumping=false ... end`；并删除分支之后那个重复的 `lists` 平台循环（它的功能已被 `groundQuery` + 平台带走替代）。

### 3.3 `Game:jump` 的对应修改

```lua
function Game:jump()
  if self.state ~= 'enemy' or self.soul.mode ~= 'blue' then return end
  self.soul.slammed = false
  if self.world then self.world.heart.slammed = false end
  if self.soul.jumping then return end
  -- 用统一的落地查询判断"能不能跳"（等价于原版 HeartCheckSolid(cos,sin)==1）
  local surface, gx, gy, soulA = self:groundQuery()
  local onSolid = (soulA + SOUL_CLAMP) >= (surface - 2)
  if onSolid or (self.soul.groundT or 99) <= 0.12 then
    local jv = JUMP_HEIGHT * self.box.h / JUMP_RISE_T   -- 沿用现有"按住变高跳"的手感
    self.soul.vx = (self.soul.vx or 0) - gx * jv
    self.soul.vy = (self.soul.vy or 0) - gy * jv
    self.soul.grounded = false
    self.soul.jumping = true
    self.soul.jumpCut = false
    self.soul.jumpHeldT = 0
    self.soul.jumpBaseX, self.soul.jumpBaseY = self.soul.x, self.soul.y
  end
end
```

### 3.4 顺手修 R3（确认键起跳被同帧切断）

适配层（`lua/main.lua`，约 1903 行）当前：

```lua
coreInput = { ..., jumpHeld = input.up, confirm = input.confirm, cancel = input.cancel }
```

建议改成"确认键 / 上键都算按住跳跃"：

```lua
jumpHeld = (input.up or input.confirm),
```

或在 core 的蓝魂物理里去掉 `jumpHeld` 对第一帧的限制（让"点按确认键"至少也有一段上升）。两种任选，推荐改适配层这一行，改动最小。

---

## 4. 验收标准

| 编号 | 断言 | 期望 |
|---|---|---|
| J1 | **地面**连续两跳 | 第 2 跳 `vy < 0`（现状已通过） |
| J2 | **空中板子**连续两跳 | 第 2 跳 `vy < 0`（现状失败，改后应通过） |
| J3 | 落在脚本平台后 `jumping` | 必须变为 `false`（当前恒为 true） |
| J4 | 平台带走 | 站在移动平台上仍会被带着走（不要因为重写落地而丢掉） |
| J5 | 确认键起跳 | `confirm=true`（不按上键）也能起跳，不再同帧落回 |
| J6 | 方向重力下的跳跃 | `dir=0/1/2/3` 时，跳跃方向 = −重力方向（方案甲 A-8） |

**复现命令**：

```powershell
cd D:\stars\workspace\sans-fight
node tools/run-lua.mjs lua/_probe_groundjump.lua
node tools/run-lua.mjs lua/_probe_platjump.lua
node tools/run-lua.mjs lua/core_selftest.lua
node tools/run-lua.mjs lua/_geometry.lua
node tools/verify-all.mjs --quick
```

**改完之后的期望输出**（以 `_probe_platjump.lua` 为例）：

```
站在空中板子上: grounded=true  jumping=false
第1跳后: vy<0  jumping=true
落回板子: grounded=true  jumping=false     ← 关键：这里必须是 false
第2跳后: vy<0  jumping=true                ← 能在板子上连续跳
```

---

## 5. 影响面与回归

| 项 | 说明 |
|---|---|
| 受影响脚本 | 所有带 `Platform` 的回合：`platforms1/2/3/4/4hard`、`platformblaster*`、`multi1/2/3`、`final` |
| 受影响测试 | `core_selftest.lua` 的 blue-jump / platforms3-safe 段、`_input.lua` 的 pc4/touch4 蓝魂跳跃段、`_probe_pjump.lua` |
| 不受影响 | 攻击延时（本次政策明确不动）、红魂物理、骨刺/光束判定 |
| 必做 | 改完 `.lua` 后 `node tools/build-save.mjs` 重建存档 |

---

## 附录 A：原版对应代码（`Battle.xml`）

```
HeartJump：
  IF PlayerHeart.Mode == HEARTMODE_BLUE
    X = cos(PlayerHeart.Angle); Y = sin(PlayerHeart.Angle)
    IF HeartCheckSolid(X, Y) == 1 THEN
      Set speed(1, dx - X * HEART_JUMP_STRENGTH)     -- 180
      Set speed(2, dy - Y * HEART_JUMP_STRENGTH)

HeartCheckSolid(dx, dy)：
  与 CombatZoneBorder 重叠 → 1
  与 Platform1 重叠（方向/相对速度/边界满足）→ 1
  否则 → 0
```

**要点**：原版"能不能跳"= `HeartCheckSolid(cos,sin)==1`，**框边与平台共用同一个函数** —— 这正是"空中板子和地面一个模子"的原始出处。

## 附录 B：本文件相关行号

| 内容 | 位置 |
|---|---|
| `Game:jump` | `lua/core.lua`（`function Game:jump`，约 1565–1595） |
| 蓝魂物理（框底/平台/复位） | `lua/core.lua` 约 2100–2135 |
| 脚本平台落地循环（分支之后） | `lua/core.lua` 约 2137–2190 |
| 适配层 jumpHeld | `lua/main.lua` 约 1903 |
| 复现探针 | `lua/_probe_groundjump.lua`、`lua/_probe_platjump.lua` |

---

*本文只改"游戏规则/物理"，不涉及任何攻击延时；§0 的政策自本文起对后续所有修改文档生效。*
