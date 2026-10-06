# 《千星奇域 Sans 战》回合差异与蓝心物理 —— 修改意见文档

- **对照源**：`D:\c2-sans-fight-src`（Construct 2 版 Bad Time Simulator，commit 0bb6afe）
- **工作区**：`D:\stars\workspace\sans-fight`（`lua/core.lua`、`prototype/attacks/*.csv`、`lua/attacks.lua`（自动生成）、`lua/main.lua`）
- **方法**：把工作区 27 个脚本与原版 CSV **逐行 diff** + 逐段审代码
- **日期**：2026-10-06

---

## 0. 结论速览

| 你的描述 | 定位（脚本 / 内部号 / HUD 号） | 根因 | 修法 |
|---|---|---|---|
| **round7 与原版有差异** | `platforms3` / 内部 6 / HUD 7 | 三根骨头被削短：32/24/24（原版 45/40/35） | 恢复原版高度 |
| **round8 与原版有差异** | `platforms4` / 内部 7 / HUD 8 | `Platform` 多了第 8 参 `Ramp=1`（原版无） | 去掉 Ramp |
| **round9 龙骨炮光束过小** | `platformblaster` / 内部 8 / HUD 9 | 光束宽度表 `{20,36,56}`，原版等效约 **{35,70,105}**（命中体 3/4） | 改宽度表 + 拆分"视觉/命中"宽度 |
| **round10 与原版有差异** | `platforms4hard` / 内部 9 / HUD 10 | 同 R8：多了 `Ramp=1` | 同 R8 |
| **round16 龙骨炮出现间隔太大、发射间隔拉长** | `randomblaster1` / 内部 15 / HUD 16（另一口径是 `multi2`） | randomblaster1：`Loop 2`（原版 **15**）、`SpinTime 1.5 + Hold 2.5`（原版 **0.46666**）；multi2：`SpinTime 2`（原版 **0.6/0.66666**）、循环延时 1.5（原版 **1.2**） | 全部恢复原版参数 |
| **round18 拖拽方向与骨头升起方向应一致** | `sans_bonestab*` / 内部 17/18/22 / HUD 18/19/23 | `World:stabRect` 的 dir 映射**整体反向**（0↔2、1↔3），骨头从拖拽的**反方向**升起 | 交换 stabRect 映射，并同步 `drawStab` 的三角朝向 |
| **round22 骨头升起时间太短** | `sans_bonestab3`（HUD 23）或 `multi3`（HUD 22） | bonestab3 原版 `StayTime=0`；且 `stepStab` 的伸出/收回硬编码 0.1s | 延长伸出时间；给 bonestab3 非零停留 |
| **round24 战斗模式不一致、空缺太长** | `final` / 内部 23 / HUD 24 | ① 蓝/红切换与 slam 物理冲突（见 §3）② 相位 ②/③ 的 8s 段被清场或模式卡住 | 见 §3；对齐相位时长与模式 |
| **红蓝心切换错误** | 全部含 `HeartMode` 的脚本 | `slammed` 分支只在蓝魂生效、切红后 `slammed` 残留；模式在**一帧后才生效** | 见 §3.3 |
| **拖拽战斗时蓝心物理法则错误（重点）** | `sans_bonestab1/2/3`、`final` 阶段①/⑤ | 工作区把"甩击"做成了**独立的 slam 物理**，只在 `slammed` 期间沿 dir 加速到墙；非 slam 时仍是**垂直匀速模型**。原版是**蓝魂全程沿 dir 重力 + 跳跃反方向** | 见 §3.1/§3.2：合并为单一方向重力物理 |

---

## 1. 回合号对照（先消除歧义）

本工程 HUD 显示 `ROUND (内部号 + 1) / 24`（`core.lua` `M.hud`：`'ROUND '..(g.round+1)..' / '..TOTAL_ROUNDS`）。因此：

| 你说的轮次 | HUD 号 | 内部号 | 脚本 |
|---|---|---|---|
| round7 | 7 | 6 | `platforms3` |
| round8 | 8 | 7 | `platforms4` |
| round9 | 9 | 8 | `platformblaster` |
| round10 | 10 | 9 | `platforms4hard` |
| round16 | 16 | 15 | `randomblaster1` |
| round18 | 18 | 17 | `sans_bonestab1` |
| round22 | 22 | 21 | `multi3`（**注意**） |
| round24 | 24 | 23 | `final` |

> ⚠️ **round22 的歧义**：按 HUD 号 22 是 `multi3`（原版 multi3 没有"骨头升起"）；按**攻击/原版 HitAttempts 号** 22 是 `sans_bonestab3`（有骨头升起）。结合你描述的是"骨头升起时间太短"，**你指的应是 `sans_bonestab3`（HUD 23）**。本文对 `bonestab1/2/3` 三个回合都给出统一修法，避免漏改。

---

## 2. 逐项差异与修法

### 2.1 round7 = `platforms3`（HUD 7 / 内部 6）

**实测 diff**（工作区 vs 原版）：

| 行 | 工作区 | 原版 |
|---|---|---|
| L16 | `0,BoneV,517,257,32,2,120` | `0,BoneV,517,257,45,2,120` |
| L18 | `0,BoneV,125,306,24,0,120` | `0,BoneV,125,306,40,0,120` |
| L20 | `0,BoneV,517,349,24,2,120` | `0,BoneV,517,349,35,2,120` |

**修法**：把三处高度恢复为 **45 / 40 / 35**（原版值）。这三处是此前"高骨公平性"降高（46/95/107→32）的遗留，属于**有意差异**；你要求与原版一致，就应回退。

### 2.2 round8 = `platforms4`（HUD 8 / 内部 7）

**实测 diff**：`0,Platform,151,336,41,0,90,1,1` vs 原版 `0,Platform,151,336,41,0,90,1` —— 工作区多了第 8 参 **`Ramp=1`**。

**修法**：去掉末尾的 `,1`，恢复"平台一上来就是全速"的原版行为（这正是原版 readme 自述的 Known Issue）。若你更想要"从 0 加速"的手感，则保留 Ramp，但要在文档里标注为**有意差异**——二者只能选一个。

### 2.3 round9 = `platformblaster`（HUD 9 / 内部 8）

**两个差异**：

1. **光束宽度过小**：
   - 工作区：`BLASTER_W = {20, 36, 56}`（`core.lua:52`）、`main.lua BLASTER_BAND = {20,36,56}`（`main.lua:44`），且**命中/渲染共用同一个 band**。
   - 原版真值（`Battle.xml` GasterBlasters 组）：`BaseSize = 35 * GasterBlaster.Height / ImageHeight`，Size 0/1/2 分别是炮身高 44/88/132 → **BaseSize = 35 / 70 / 105**；`SineSize = sin(...) * BaseSize / 4`（视觉在 0.75~1.25×之间脉动）；而**命中体** `GasterBlastHit.Height = BaseSize * 3/4` = **26.25 / 52.5 / 78.75**。
   - 结论：工作区的 20/36/56 ≈ 原版命中体的 **0.75 倍**，视觉上明显偏细。
   - **修法**：把"视觉宽度"和"命中宽度"分开：
     ```lua
     -- core.lua 常量
     local BLASTER_W     = { 35, 70, 105 }              -- 视觉基准（= 原版 BaseSize）
     local BLASTER_HIT_W = { 26.25, 52.5, 78.75 }        -- 命中基准（= BaseSize*3/4）
     -- CMD.GasterBlaster 里：
     band     = BLASTER_W[sz+1] + (extraW or 0)*2,       -- 渲染用
     hitBand  = BLASTER_HIT_W[sz+1] + (extraW or 0)*2,   -- 判定用
     -- 判定处（Game:update 光束段）用 B.hitBand 而不是 B.band
     ```
     `main.lua` 的 `BLASTER_BAND` 同步改为 `{35,70,105}`。

2. **蓄力（SpinTime）被拉长**：工作区 `SpinTime 1.56666`，原版 **0.56666**（+1s）。
   **修法**：改回 `0.56666`。

### 2.4 round10 = `platforms4hard`（HUD 10 / 内部 9）

同 §2.2：`Platform,...,1,1` 多了 `Ramp=1`。修法一致。

### 2.5 round16 龙骨炮：出现间隔太大、发射间隔拉长

这里有两个可能的脚本，取决于你的轮次口径，**两个都改**：

**(a) `randomblaster1`（HUD 16 / 内部 15）**

| 行 | 工作区 | 原版 |
|---|---|---|
| L5 | `0.5,SET,Loop,2` | `0.5,SET,Loop,15` |
| L28 | `0,GasterBlaster,0,$X,$Y,$EndX,$EndY,$Ang,1.5,0.03333,2.5,5` | `0,GasterBlaster,0,$X,$Y,$EndX,$EndY,$Ang,0.46666,0.03333` |
| L29 | `4.1,JMPNZ,6,$Loop` | `0.53333,JMPNZ,6,$Loop` |

→ 工作区只放 **2 发**激光、每发蓄力 1.5s + 停 2.5s，所以"出现间隔极大"；原版是 **15 发**、蓄力 0.46666s。
**修法**：Loop 改回 15、`1.5,0.03333,2.5,5` 改回 `0.46666,0.03333`、`4.1` 改回 `0.53333`。

**(b) `multi2` / `multi3`（HUD 17 / 22）**

| 行 | 工作区 | 原版 |
|---|---|---|
| multi2 L39–42 | `...,0,2,0.26666` | `...,0,0.6,0.26666` |
| multi2 L45–48 | `...,45,2,0.26666` | `...,45,0.66666,0.26666` |
| multi2 L43/L49 | `1.5,JMPABS,RndAttack` | `1.2,JMPABS,RndAttack` |
| multi3 L129–132 | `...,0,2,0.26666` | `...,0,0.6,0.26666` |
| multi3 L135–138 | `...,45,2,0.26666` | `...,45,0.66666,0.26666` |
| multi3 L133/L139 | `1.5,JMPABS,RndAttack` | `1.2,JMPABS,RndAttack` |

**修法**：`2` → `0.6`（正交四发）或 `0.66666`（斜角四发），循环延时 `1.5` → `1.2`。

> 同类问题还有 `sans_intro`（`SpinTime 1` vs 原版 `0.333/0.666`、延时 `1.2` vs `1.1`）——如果你要求"所有龙骨炮都对原版"，也应一并回退。

### 2.6 round18 = 拖拽方向与骨头升起方向必须一致（`sans_bonestab*`）

**根因：`World:stabRect` 的 dir 映射整体反向。**

工作区当前（`core.lua` `World:stabRect` 非 `arrowbone` 分支）：

```lua
if b.dir == 0 then return { x = z.l,        ... } end   -- dir0 = 左边框
if b.dir == 2 then return { x = z.r - d,    ... } end   -- dir2 = 右边框
if b.dir == 1 then return { x = z.l, y = z.t,        ... } end   -- dir1 = 上边框
return             { x = z.l, y = z.b - d, ... }                  -- dir3 = 下边框
```

原版（`Battle.xml` BoneStab 组）是：

| dir | 原版预警块位置 | 骨头从哪条边升起 |
|---|---|---|
| 0 | `X = BBoxRight - Width - 8` | **右** |
| 1 | `Y = BBoxBottom - Height - 8` | **下** |
| 2 | `X = BBoxLeft + 8` | **左** |
| 3 | `Y = BBoxTop + 8` | **上** |

而 `SansSlam(dir)` 的 dir 是：0 东 / 1 南 / 2 西 / 3 北。所以原版是"**甩向哪条边，骨头就从哪条边升起**"；工作区正好相反 → 与你观察到的"拖拽方向和骨头升起方向不一致"完全对上。

**修法**（交换 0↔2、1↔3）：

```lua
  -- 【修正】与原版一致：0=右 1=下 2=左 3=上
  if b.dir == 0 then return { x = z.r - d, y = z.t, w = d, h = z.b - z.t } end
  if b.dir == 2 then return { x = z.l,     y = z.t, w = d, h = z.b - z.t } end
  if b.dir == 1 then return { x = z.l, y = z.b - d, w = z.r - z.l, h = d } end
  return             { x = z.l, y = z.t,     w = z.r - z.l, h = d }             -- dir3 = 上
```

**同时必须改 `main.lua drawStab` 的三角朝向**（否则画出来的箭头会指向框外）：
当前 `dir==0 → tx = x + w`（矩形右缘）；改完 dir0 的矩形在**右边**，三角应放在**左缘（内缘）**：

```lua
if dir == 0 then tx, ty = x, y + h / 2          -- 右边缘矩形 → 三角在左（内）缘
elseif dir == 2 then tx, ty = x + w, y + h / 2  -- 左边缘矩形 → 三角在右（内）缘
elseif dir == 1 then tx, ty = x + w / 2, y      -- 下边缘矩形 → 三角在上（内）缘
else tx, ty = x + w / 2, y + h end              -- 上边缘矩形 → 三角在下（内）缘
```

> 注意：`ArrowBone` 分支的映射本来就是对的（0=右/1=下/2=左/3=上），改动时**不要动 arrowbone 分支**。若未来重新启用 arrow 模块，它和 BoneStab 现在会共用同一套方向语义。

### 2.7 round22 = 骨头升起时间太短（`sans_bonestab3`，HUD 23）

**两点**：

1. **原版 bonestab3 的 `StayTime = 0`** —— 骨头弹出后立刻收回，确实"升起时间太短"。三档原版参数：
   | 脚本 | Distance | WarnTime | StayTime |
   |---|---|---|---|
   | bonestab1 | 25 | 0.4 | 0.33333 |
   | bonestab2 | 25 | 0.3 | 0.2 |
   | bonestab3 | 29 | 0.4 | **0** |
2. **工作区 `World:stepStab` 把"伸出/收回"硬编码成 0.1s**：
   ```lua
   if b.phase == 'out' then b.cur = math.min(b.dist, b.dist*(b.t/0.1)); if b.t>=0.1 then ... end
   ```
   所以无论 Distance 多大，视觉上都是"0.1 秒弹到位"。

**修法（二选一或同时）**：
- 若要与原版一致：bonestab3 保持 `StayTime=0`（那就没有"升起太短"的修复空间）；
- 若你希望**可读性更好**（你的反馈是"太短"）：把 `stepStab` 的伸出时间做成可配置（比如 `outDur`），或在 CSV 里给 bonestab3 一个非零停留，例如 `0.2,BoneStab,$Direction,29,0.4,0.2`。
  建议：`outDur` 从 0.1s → **0.22s**（大约是原版的两倍），bonestab3 的 Stay 给 **0.2s**。

### 2.8 round24 = `final`（HUD 24 / 内部 23）

`final` 的脚本内容与原版**只差一处**（`$pi` 写成数值），所以"战斗模式不一致 / 空缺太长"不是脚本数据问题，而是**运行期**问题。三个可疑点：

1. **相位②/③的 8 秒段**：原版 `sans_final` L113 是 `8,HeartMaxFallSpeed,330`——这 8 秒里前面（L84–L92）生成的**骨墙**应当仍在场（玩家要在骨墙里撑 8 秒）。工作区若在 `BlackScreen` / 清场 / 相位切换时把骨墙清掉，这 8 秒就变成**空场等待**（"空缺太长"）。
   - **修法**：核对 `BlackScreen(1)` 的清理时机——确认它不在相位③之前把 L84–L92 的骨墙清掉；并核对 `simulateLength`/`enemyDur` 没有在相位②之间插入额外等待。
2. **红蓝切换（见 §3.3）**：final 的 `HeartMode` 序列是 0 →（多次 SansSlam 强制蓝）→ 0 → 1 → 0。若 slam 物理与模式切换冲突，玩家会看到"模式乱"。
3. **相位⑤的 38 连砸**：需要 §3 的方向重力 + 撞墙伤害，否则那段只是"空旷地站着"。

---

## 3. 重点：拖拽战斗时蓝心物理法则错误（必须修）

### 3.1 原版的蓝心法则（`Battle.xml` → PlayerMovement / HeartJump / SansSlam）

1. **蓝魂的重力方向 = 心的 Angle**（`dir*90`）：0 东 / 1 南 / 2 西 / 3 北。重力沿该方向施加，`HeartMaxFallSpeed` 是沿该方向的**终端速度**（负值 = 反向走廊）。
2. **跳跃 = 沿重力反方向**：`HeartJump()` 里 `X=cos(Angle), Y=sin(Angle)`，只有 `HeartCheckSolid(X,Y)==1`（贴地）才允许，初速 `HEART_JUMP_STRENGTH=180`；松手时把上升速度截到 `HEART_JUMPHOLD_CUTOFF=30`（可变高跳）。
3. **重力 4 档曲线**（按沿重力方向的速度 `DownSpeed`）：`(15,240)→540`、`(−30,15]→180`、`(−120,−30]→450`、`≤−120→180`。
4. **`SansSlam` 只是"进入蓝魂 + 给初速 + 标记 Slammed"**：它本身不改变物理规则；之后玩家仍可以用跳跃沿 −重力 往回弹。
5. **撞墙**：`Slammed` + `HeartCheckSolid` → 清标记；`|v|>330` → 伤害/抖屏/音效。

### 3.2 工作区错在哪

当前实现（`core.lua` 蓝魂段）把物理拆成了两套：

| 状态 | 工作区物理 | 与原版差异 |
|---|---|---|
| 普通蓝魂（`slammed == false`） | **垂直匀速**：按住上升 0.25s / 松手下落 0.75s；`soul.dir` **完全不参与** | 原版是"重力沿 dir"；工作区只支持竖直向下 |
| 被甩中（`slammed == true`） | 单独分支：沿 dir 用 `GRAVITY=600` 加速到 `maxFall`，积分到撞墙；**期间不读跳跃输入** | 原版 slam 只是"给初速+切蓝魂"，之后仍受重力、仍可跳；工作区把它做成"单向推到墙" |

后果（与你观察一致）：

- **拖拽战斗时蓝心"法则不对"**：甩出去后玩家**无法按跳跃往回弹**（slam 分支忽略跳跃），只能被推到墙；这不是原版的蓝色灵魂。
- **方向重力只在 slam 期间存在**：一旦撞墙/`slammed=false`，立刻回到"只竖直"的模型；所以水平甩击在落地后不会再持续拉你。
- **红蓝切换会残留 `slammed`**：若脚本在撞墙前 `HeartMode,0`（切红），红魂分支不检查 `slammed` → 标记永久为 true，后续受击/伤害判断会错乱（§3.3）。

### 3.3 正确实现（建议直接替换）

**核心思想**：蓝魂只有一个物理 —— **重力沿 `soul.dir`**；`SansSlam` 只负责切蓝 + 设 dir + 给初速 + 标 `slammed`；`slammed` 仅用于"撞墙是否算伤害/抖屏"。

**（1）`CMD.SansSlam`（已基本正确，保留）**：强制蓝魂 + 设 dir + 满速初速 + `slammed=true`。**不要再另建一套 slam 物理**。

**（2）蓝魂物理合并为一段（替换现有 `if self.soul.slammed then ... else ... end`）**：

```lua
if self.soul.mode == 'blue' and not self.soul.wall then
  local DX = { [0]=1, [1]=0, [2]=-1, [3]=0 }
  local DY = { [0]=0, [1]=1, [2]=0,  [3]=-1 }
  local gx = DX[self.soul.dir or 1] or 0
  local gy = DY[self.soul.dir or 1] or 1
  local function vAlong() return self.soul.vx*gx + self.soul.vy*gy end
  local function setVAlong(v)
    local d = v - vAlong(); self.soul.vx = self.soul.vx + gx*d; self.soul.vy = self.soul.vy + gy*d
  end

  -- ① 沿重力方向的 4 档重力（原版曲线）
  local va = vAlong()
  local g = (va > 15 and va < 240) and 540
         or (va <= 15 and va > -30) and 180
         or (va <= -30 and va > -120) and 450 or 180
  self.soul.vx = self.soul.vx + gx * g * dt
  self.soul.vy = self.soul.vy + gy * g * dt

  -- ② MaxFallSpeed 封顶（负值 = 反向走廊）
  local mf = self.soul.maxFall; if mf == nil or mf == 0 then mf = 750 end
  if vAlong() > mf then setVAlong(mf) end

  -- ③ 跳跃：沿 −重力；松手把上升速度截到 30（可变高跳）
  if self.soul.jumping and not self.jumpHeld then
    if vAlong() < -HEART_JUMPHOLD_CUTOFF then setVAlong(-HEART_JUMPHOLD_CUTOFF) end
    self.soul.jumping = false
  end

  -- ④ 位移
  self.soul.x = self.soul.x + self.soul.vx * dt
  self.soul.y = self.soul.y + self.soul.vy * dt

  -- ⑤ 撞墙：沿重力方向贴边 = grounded；slammed 且速度>330 → 伤害/抖屏（原版）
  ...（沿用现有 A-6 的撞墙段，去掉"只在 slammed 才进这个分支"的限制，
      改为常规贴地判定 + 仅在 slammed 时结算伤害）
end
```

**（3）`Game:jump` 改为沿 −重力方向**（当前是 `self.soul.vy = -riseSpeed`，只支持竖直）：

```lua
function Game:jump()
  if self.state ~= 'enemy' or self.soul.mode ~= 'blue' then return end
  if self.soul.jumping then return end
  if self.soul.grounded or (self.soul.groundT or 99) <= 0.12 then
    local DX = { [0]=1, [1]=0, [2]=-1, [3]=0 }
    local DY = { [0]=0, [1]=1, [2]=0,  [3]=-1 }
    local gx = DX[self.soul.dir or 1] or 0
    local gy = DY[self.soul.dir or 1] or 1
    self.soul.vx = self.soul.vx - gx * HEART_JUMP_STRENGTH
    self.soul.vy = self.soul.vy - gy * HEART_JUMP_STRENGTH
    self.soul.grounded = false; self.soul.jumping = true; self.soul.jumpCut = false
  end
end
```

**（4）红蓝切换错误的修法**：

- `soul.slammed` 必须在以下时机清零：撞墙、`HeartMode` 切到红、回合结束（`endEnemy`）。
  在 `Game:update` 同步 `heartModeDirty` 的地方加：
  ```lua
  if self.soul.mode ~= 'blue' then self.soul.slammed = false end
  ```
- `HeartMode` 的生效不要延迟：当前脚本在 `w:update` 里跑，而灵魂物理在同一帧的**前面**执行，所以模式切换会晚一帧。若在意，可在 `Game:update` 的"脚本世界"之后补一次模式复位（或把灵魂物理移到 `w:update` 之后）。
- 确认 `HeartMode` 的**颜色**与**模式**同步：`main.lua` 用 `cmd.mode == 'blue'` 取 `C_BLUE`，`core.render` 用 `g.soul.mode`；两者都来自 `soul.mode`，只要模式对，颜色就对。

---

## 4. 修改清单（按优先级）

| 优先级 | 文件 | 改动 |
|---|---|---|
| **P0** | `lua/core.lua` | §3.3：合并蓝魂物理为**单一方向重力**；跳跃沿 −重力；`slammed` 只做撞墙结算；切红/回合结束清 `slammed` |
| **P0** | `lua/core.lua` `stabRect` + `lua/main.lua` `drawStab` | §2.6：交换 dir 0↔2、1↔3；三角指内缘 |
| **P0** | `prototype/attacks/*.csv` → 重新 `gen-attacks.mjs` | §2.3 光束宽度表；§2.5 randomblaster1/multi2/multi3 参数；§2.1/2.2/2.4 平台/骨高回退 |
| P1 | `lua/core.lua` 常量 | `BLASTER_W` → `{35,70,105}`、新增 `BLASTER_HIT_W`（3/4）；`main.lua BLASTER_BAND` 同步 |
| P1 | `lua/core.lua` `stepStab` | 伸出时间 0.1s → 可配置（建议 0.22s）；bonestab3 给非零 Stay |
| P2 | `lua/core.lua` | round24 相位②/③的 8s 段：确认骨墙不被 `BlackScreen` 提前清掉 |

---

## 5. 验收

```powershell
cd D:\stars\workspace\sans-fight
node tools/gen-attacks.mjs        # CSV → lua/attacks.lua
node tools/build-save.mjs
node tools/run-lua.mjs lua/core_selftest.lua
node tools/run-lua.mjs lua/_geometry.lua
node tools/verify-all.mjs --quick
```

**逐条验收**：

| 项 | 期望 |
|---|---|
| R7 platforms3 | 骨高 45/40/35（与原版 CSV 逐字一致） |
| R8/R10 | `Platform` 不再带 `,1` 末尾参数（或文档标注保留差异） |
| R9 光束 | 视觉宽度 ≈35/70/105；命中 ≈26/53/79 |
| R16 | randomblaster1 Loop=15、Spin=0.46666；multi2/3 Spin=0.6/0.66666、循环=1.2 |
| R18 | 甩向 dir → 骨头从**同一条**边升起；箭头指向框内 |
| R22 | 骨头伸出 ≈0.22s；bonestab3 有非零停留 |
| R24 | 相位②的 8s 里骨墙仍在场；相位⑤ 38 连砸可掉血；红蓝切换无残留 |
| 蓝心物理 | 被甩向 dir 后，按跳跃键能沿 −dir 往回弹；撞墙 >330 才掉血 |

**复现 diff**：`node D:\stars\_analysis\diff-attacks.mjs`（27 个脚本与原版逐行对照）。

---

## 附录 A：本次 diff 的完整证据（节选）

```
platforms3     L16 端口 0,BoneV,517,257,32,2,120   原版 0,BoneV,517,257,45,2,120
platforms3     L18 端口 0,BoneV,125,306,24,0,120   原版 0,BoneV,125,306,40,0,120
platforms3     L20 端口 0,BoneV,517,349,24,2,120   原版 0,BoneV,517,349,35,2,120
platforms4     L5  端口 0,Platform,151,336,41,0,90,1,1   原版 0,Platform,151,336,41,0,90,1
platforms4hard L5  端口 0,Platform,151,336,31,0,90,1,1   原版 0,Platform,151,336,31,0,90,1
platformblaster L12 端口 ...,0,1.56666,0.1   原版 ...,0,0.56666,0.1
randomblaster1 L5  端口 0.5,SET,Loop,2        原版 0.5,SET,Loop,15
randomblaster1 L28 端口 ...,0.46666→1.5,0.03333,2.5,5   原版 ...,0.46666,0.03333
multi2 L39-42 端口 ...,0,2,0.26666   原版 ...,0,0.6,0.26666
multi2 L45-48 端口 ...,45,2,0.26666  原版 ...,45,0.66666,0.26666
multi3 L129-138 同上
sans_intro L24-37 端口 SpinTime 1 / 原版 0.333、0.666
```

## 附录 B：关键行号

| 内容 | 位置 |
|---|---|
| `BLASTER_W` | `lua/core.lua:52` |
| `CMD.GasterBlaster`（band/extraW） | `lua/core.lua:700-720` |
| 光束判定（用 band） | `lua/core.lua:2540-2550` |
| `World:stabRect` | `lua/core.lua`（`function World:stabRect`） |
| `World:stepStab`（0.1s 伸出） | `lua/core.lua`（`function World:stepStab`） |
| `CMD.SansSlam` | `lua/core.lua:583` |
| 蓝魂物理 / slammed 分支 | `lua/core.lua:2049-2135` |
| `Game:jump` | `lua/core.lua`（`function Game:jump`） |
| `main.lua drawStab` | `lua/main.lua`（`local function drawStab`） |
| `main.lua BLASTER_BAND` | `lua/main.lua:44` |
| HUD ROUND | `lua/core.lua:2901` |
| 原版 final HeartMode | `D:\c2-sans-fight-src\Files\sans_final.csv` L3/28/109/137 |

---

*本文所有 diff 均为工作区 `prototype/attacks/*.csv` 与原版 `D:\c2-sans-fight-src\Files\sans_*.csv` 的逐行对照结果；蓝心物理论断来自 `core.lua` 与 `Battle.xml` 的逐段比对。*
