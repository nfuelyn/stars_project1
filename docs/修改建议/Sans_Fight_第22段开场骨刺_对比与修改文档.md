# 原版「第 22 段」开场骨刺（BoneStab）模式 vs 工作区实现 —— 对比与修改文档

- **原版来源**：`D:\c2-sans-fight-src`（`Event sheets/Battle.xml` BoneStab 组 + `Files/sans_bonestab3.csv`）
- **工作区**：`D:\stars\workspace\sans-fight`（`prototype/attacks/sans_bonestab3.csv` → `lua/attacks.lua`、`lua/core.lua`、`lua/main.lua`）
- **辅助参考**：`D:\stars\reference\lua\bone_battle.lua`（工程内已存在的骨攻复刻模板，含 round 号表）
- **日期**：2026-10-07

---

## 0. 先说清"第 22 段"是哪一个（三种口径并存）

工程里同时存在三套轮次编号，必须先对齐，否则会改错脚本：

| 口径 | 来源 | 第 22 段 = |
|---|---|---|
| **A. 原作攻击序号**（HitAttempts 22） | `D:\c2-sans-fight-src\Files\sans_bonestab3.csv`；`Battle.xml` StartAttack 的 `NextAttack` 链 | **`sans_bonestab3`**（BoneStab 连刺，最长档） |
| **B. 工作区 HUD**（`ROUND x / 24`，= 内部号+1） | `core.lua` `'ROUND '..(g.round+1)`；`FIXED_SEQ` | HUD 22 = 内部 21 = **`multi3`** |
| **C. `bone_battle.lua` 的 round 表** | `D:\stars\reference\lua\bone_battle.lua` 的 `BoneBattle.ROUNDS` | round 22 = **`sans_boneslidev`** |

**判定**：你说的是"**骨头模式**"、"**最开始攻击**"，且此前反馈过"骨头升起时间太短" —— 与 **BoneStab（骨刺从边上升起）** 完全对应。**本文按口径 A：第 22 段 = `sans_bonestab3`**（工作区内部号 22 / HUD 23）。

> 如果你实际指的是 B（`multi3`）或 C（`boneslidev`）：它们的**骨头脚本数据与原版逐行一致**（见 §3.2 的 diff 结论），骨阵参数没有差异，无需改动；C 的 `boneslidev` 只可能是运行期渲染/判定问题，不在本文范围。

---

## 1. 原版第 22 段（`sans_bonestab3`）开场骨头模式

### 1.1 脚本（原版 `Files/sans_bonestab3.csv`，全文 26 行）

```
 1  0,CombatZoneResize,241,226,406,391,TLResume
 2  0,HeartTeleport,320,304
 3  0,HeartMode,0
 4  0,TLPause
 5  0,SET,Loop,9
 6  0,JMPZ,26,$Loop
 7  0,SUB,Loop,$Loop,1
 8  0,RND,Direction,4
 9  0,ADD,Jump,$Direction,1
10  0,JMPREL,$Jump
11  0,JMPREL,4
12  0,JMPREL,5
13  0,JMPREL,6
14  0,JMPREL,7
15  0,SansBody,HandRight
16  0,JMPREL,7
17  0,SansBody,HandDown
18  0,JMPREL,5
19  0,SansBody,HandLeft
20  0,JMPREL,3
21  0,SansBody,HandUp
22  0,JMPREL,1
23  0.26666,SansSlam,$Direction
24  0.2,BoneStab,$Direction,29,0.4,0
25  0.23333,JMPABS,6
26  0,EndAttack
```

**开场骨头 = 第 24 行的 `BoneStab(dir, 29, 0.4, 0)`**，方向 `$Direction` 由第 8 行 `RND Direction,4` 随机（0/1/2/3），先 `SansSlam` 同方向甩击，再同侧刺骨。

### 1.2 原版 `BoneStab(dir, Distance, WarnTime, StayTime)` 的完整机制（`Battle.xml` BoneStab 组）

**阶段① 预警（WarnTime = 0.4s）** —— 生成 `BoneStabWarn`（16×16 九宫格）放在 **框内、贴边内缩 8px**：

| dir | 尺寸 | 位置 |
|---|---|---|
| 0（右） | `Width = Distance-3`，`Height = 框高-16` | `X = 框右 - Width - 8`，`Y = 框顶 + 8` |
| 1（下） | `Width = 框宽-16`，`Height = Distance-3` | `X = 框左 + 8`，`Y = 框底 - Height - 8` |
| 2（左） | `Width = Distance-3`，`Height = 框高-16` | `X = 框左 + 8`，`Y = 框顶 + 8` |
| 3（上） | `Width = 框宽-16`，`Height = Distance-3` | `X = 框左 + 8`，`Y = 框顶 + 8` |

即：**一条厚度 `Distance-3`、贴着该边、四角各内缩 8px 的警示带**（并在循环开始时播 `Warning` 音效）。

**阶段② 出刺（0.1s）** —— `WarnTime` 归零后播 `BoneStab` 音效、销毁预警块，生成整块面板：

| dir | 面板尺寸 | 起始位置 | 终点 Dest | 方向 |
|---|---|---|---|---|
| 0（右） | `(Distance+8) × 框高` | `X = 框右 - 5` | `DestX = 框右 - 5 - Distance` | 向左滑入 |
| 1（下） | `框宽 × (Distance+8)` | `Y = 框底 - 5` | `DestY = 框底 - 5 - Distance` | 向上滑入 |
| 2（左） | `(Distance+8) × 框高` | `X = 框左 + 5 - Width` | `DestX = X + Distance` | 向右滑入 |
| 3（上） | `框宽 × (Distance+8)` | `Y = 框顶 + 5 - Height` | `DestY = Y + Distance` | 向下滑入 |

滑入速度 `Speed = Distance * 10`（px/s）→ 用时 ≈ **0.1s**；到 Dest 后若 `StayTime<=0` 立即反转。

**阶段③ 停留（StayTime）** —— 停 `StayTime` 秒（本例 = **0**，即不停留）。

**阶段④ 收回** —— `Reverse=1`，原路以同速退回，出屏后 `Destroy`。

**关键数值（dir=0，框 241,226–406,391）**：
- 预警带：`X=406-26-8=372`，宽 `29-3=26`，`Y=234`，高 `165-16=149` → **[372,398] × [234,383]**（完全在框内）。
- 骨面板：`37 × 165`，从 `X=401` 滑到 `X=372`（伸入 **29px**）。

---

## 2. 工作区当前实现

### 2.1 脚本（`prototype/attacks/sans_bonestab3.csv`）

与原版逐行一致，**只有第 24 行参数不同**：

```
原版   24: 0.2,BoneStab,$Direction,29,0.4,0
工作区 25: 0.2,BoneStab,$Direction,18,0.4,0.25
```

差异：**Distance 29 → 18**、**StayTime 0 → 0.25**（WarnTime 都是 0.4）。

### 2.2 运行期实现

- `CMD.BoneStab(w, dir, dist, warn, stay, outDur)`（`core.lua`）：建实体 `{stab, dir, dist=18, warn=0.4×难度, stay=0.25, outDur=nil, phase='warn'}`。
- `World:stepStab`：`warn(0.4) → out(默认 0.1s，cur 0→18) → stay(0.25) → in(0.1s)`。
- `World:stabRect`（当前已是原版几何）：

  ```
  dir1(下): { x=z.l,             y=z.b-5-d*t,             w=框宽, h=d+8 }
  dir3(上): { x=z.l,             y=z.t+5-(d+8)+d*t,       w=框宽, h=d+8 }
  dir0(右): { x=z.r-5-d*t,       y=z.t,                   w=d+8, h=框高 }
  dir2(左): { x=z.l+5-(d+8)+d*t, y=z.t,                   w=d+8, h=框高 }
  ```

  → **方向、尺寸（d+8）、起点（边外 5px）、滑入距离（d）都与原版一致**（探针已验，见 §3.1）。
- `renderWorld`：对 stab 实体统一发 `kind='stab'`，`x/y/w/h` 取 `stabRect`，`phase = peek/extend/hold/retract`。
- `main.lua drawStab`：`peek` 时用 **alpha 0.45 画同一块骨头**（+ 一个三角指示），`extend/hold` 时不透明。

### 2.3 实测（`lua/_probe_stab.lua` 输出，dir=0、d=29、warn=0.4、stay=0）

```
t=0.22 phase=warn  rect=(x=401, y=226, w=37, h=165)   ← 预警阶段画的是"边上的整块骨头"
t=0.47 phase=out   rect=(x=387, ...)
t=0.55 phase=in    rect=(x=372, ...)                  ← 滑到位（与原版 DestX 一致）
t=0.63 phase=in    rect=(x=396, ...)
```

---

## 3. 差异对照

### 3.1 已经完全一致的部分（不要再改）

| 项 | 原版 | 工作区 | 结论 |
|---|---|---|---|
| 方向语义 | 0 右 / 1 下 / 2 左 / 3 上 | 同 | ✅ 一致 |
| 面板尺寸 | `Distance+8` × 框宽/高 | 同 | ✅ 一致 |
| 起始位置 | 边外 5px（`框右-5` 等） | 同 | ✅ 一致 |
| 滑入距离 | `Distance` | 同（按自身 d） | ✅ 一致 |
| 滑入速度/时长 | `Distance*10` px/s ≈ 0.1s | `outDur` 默认 0.1s | ✅ 一致 |
| 收回 | 原路退回、出屏销毁 | `in` 阶段 0.1s 后 dead | ✅ 一致 |
| 每击伤害/Karma | 1 / 6 | 脚本骨 1 / 6 | ✅ 一致 |

### 3.2 仍有差异的部分

| 项 | 原版 | 工作区 | 类型 |
|---|---|---|---|
| **BoneStab 距离（伸入深度）** | `29` | **`18`** | **尺寸**（非延时） |
| **骨头面板尺寸** | `29+8 = 37` | `18+8 = 26` | 同上 |
| **预警带（最关键）** | 框内**内缩 8px 的警示带**：厚 `Distance-3=26`、长 `框高-16=149`，位于 `[372,398]×[234,383]` | 画**边上的整块骨头**（`x=401,w=26`），半透明；框内只露 **5px**（`[401,406]`） | **表现差异 → 建议修** |
| **StayTime** | `0`（不停留） | `0.25` | 时长（**按你的新政策：不强制回退**） |
| 预警音效 | `Warning.ogg` + 出刺 `BoneStab.ogg` | 工作区无音频系统 | 平台差异 |

> 其余两个口径的 diff 结论：
> - **B（HUD 22 = `multi3`）**：`multi3.csv` 与原版仅**龙骨炮延时**不同（新政策不动），骨阵（`BoneVRepeat/BoneV`）逐行一致 → **骨头模式无需改**。
> - **C（`bone_battle` round 22 = `sans_boneslidev`）**：CSV **完全一致** → 同上。

---

## 4. 修改建议（尊重"不改现有攻击延时"的政策）

> 本文不要求改动任何 **延时/时长**（`WarnTime`、`StayTime`、`outDur`、循环 delay 等）。下面只动**尺寸**与**表现**。

### 4.1【已实施】只调整预警带的长度（两端各内缩 8px）

按你的要求，**只动"预警带长度"这一项**；厚度、位置语义、`WarnTime`/`StayTime`/伤害/`Distance` 一律不动。

**改动位置**：`lua/main.lua` → `drawStab()` 的 `peek`（预警）阶段。沿**框边方向**两端各内缩 8px，即长度 = 原版 `BoneStabWarn` 的「**框边 − 16**」：

```lua
local function drawStab(cmd)
  local x, y, w, h, dir = cmd.x, cmd.y, cmd.w, cmd.h, cmd.dir or 0
  if w <= 0 or h <= 0 then return end
  local peek = (cmd.phase == 'peek')
  -- 【预警带长度】沿框边方向两端各内缩 8px（= 原版 BoneStabWarn 的「框边-16」）。
  -- 只动长度：厚度、位置语义、WarnTime/StayTime/伤害一律不变。
  if peek then
    if h >= w then h = math.max(1, h - 16); y = y + 8   -- 竖向带（dir 0/2）
    else w = math.max(1, w - 16); x = x + 8 end          -- 横向带（dir 1/3）
  end
  local alpha = peek and 0.45 or (cmd.alpha or 1)
  ...（其余不变）
```

| dir | 长度方向 | 改前 | 改后 |
|---|---|---|---|
| 0 / 2（右/左） | 竖向（沿框高） | 框高（例 165） | **框高 − 16（例 149）** |
| 1 / 3（下/上） | 横向（沿框宽） | 框宽 | **框宽 − 16** |

**保持不变**：
- 厚度仍是骨面板截面（`Distance + 8`）；
- 位置语义（0 右 / 1 下 / 2 左 / 3 上）与三角形"指向框内"；
- 出刺 / 停留 / 收回三个阶段完全不动（仍走 `World:stabRect`）；
- `WarnTime`、`StayTime`、`outDur`、`Distance`、伤害/Karma 全部不动。

**未做**：早先设想的"另画一条独立警示带（新增 `warnBand` 图元）"这次**不做**，仅调长度。
（若以后想用原版 `BoneStabWarn.png` 贴图，素材已在 `reference/sprites/textures/BoneStabWarn.png`。）

**已验证**：`node tools/run-lua.mjs lua/_syntax_main.lua` → `main.lua SYNTAX OK`。

### 4.2【可选】BoneStab 距离：18 vs 29（这是**尺寸**，不是延时）

- 原版第 22 段 = **29**（面板 37px、伸入 29px）；工作区 = **18**（面板 26px、伸入 18px）。
- 这是此前为"可读性/公平性"主动削短的，**不属于延时**，因此不在新政策豁免范围内 —— 但它是**有意差异**，请二选一：
  - **要还原原版图案**：把 `prototype/attacks/sans_bonestab3.csv` 第 25 行改回 `0.2,BoneStab,$Direction,29,0.4,0.25`（`StayTime` 保留你的 0.25，不违反政策）；同族的 `sans_bonestab1/2` 由 16 改回 25 视需要。
  - **保留当前手感**：不改数值，仅在文档标注为有意差异。
- 注意：改完 CSV 必须跑 `node tools/gen-attacks.mjs` 重新生成 `lua/attacks.lua`。

### 4.3【不改】StayTime = 0.25

原版是 `0`（出刺后立即收回）。当前 0.25 是你此前"骨头升起时间太短"的修正，**按新政策保留**，本文不建议回退。

### 4.4 附带：出刺相位不要被难度缩放

`CMD.BoneStab` 里 `warn = w:wn(warn)`（难度缩放预警）是合理的；但 `outDur`（滑入时长）**没有被难度缩放**，原版也不是按难度改的 —— 保持 0.1s 即可，不要因为"延时政策"去动它。

---

## 5. 验收

```powershell
cd D:\stars\workspace\sans-fight
node tools/gen-attacks.mjs        # 若改了 CSV
node tools/build-save.mjs
node tools/run-lua.mjs lua/_probe_stab.lua        # 看 warn/out/in 的矩形
node tools/run-lua.mjs lua/core_selftest.lua
node tools/verify-all.mjs --quick
```

| 项 | 期望 |
|---|---|
| 预警阶段 | 框内有一条厚度 `d-3`、四角内缩 8px 的警示带（不再是框外的整块骨头） |
| 出刺阶段 | 面板 `d+8` 宽/高，从边外 5px 滑入 `d` 像素（与原版公式一致） |
| 收回 | 原路退回并消失 |
| 判定 | 面板矩形与绘制同源（`stabRect`），不出现"看着躲开却掉血" |
| 尺寸 | 若选择还原：`d=29`（面板 37）；否则记录为有意差异 |

**复现探针**：`lua/_probe_stab.lua`（4 方向 × 4 时间点打印矩形），本文所有几何数字均由它实测。

---

## 附录 A：原版 BoneStab 关键代码（`Battle.xml` BoneStab 组）

```
BoneStab(dir, Distance, WarnTime, StayTime)：
  建 BoneStabWarn；按 dir 设 size/pos（内缩 8、厚 Distance-3、长 框边-16）；播 Warning
  WarnTime 每秒递减；归零后：
    播 BoneStab；销毁 Warn；按 dir 建 BoneStabH/V：
      dir0/2 → BoneStabH，size = (Distance+8) × 框高
      dir1/3 → BoneStabV，size = 框宽 × (Distance+8)
      起点在框外 5px，Dest = 起点 ∓ Distance
  每帧：Speed = Distance*10；先朝 Dest 移动，到了以后 StayTime 递减，归零后 Reverse=1 原路退回，出屏 Destroy
```

## 附录 B：行号与文件

| 内容 | 位置 |
|---|---|
| 原版第 22 段脚本 | `D:\c2-sans-fight-src\Files\sans_bonestab3.csv` |
| 原版 BoneStab 实现 | `D:\stars\_analysis\Battle.xml.txt` → `GROUP: BoneStab` |
| 工作区脚本 | `prototype\attacks\sans_bonestab3.csv`（自动生成到 `lua/attacks.lua`） |
| 工作区命令 | `lua/core.lua` `CMD.BoneStab` / `World:stepStab` / `World:stabRect` |
| 工作区渲染 | `lua/core.lua` `renderWorld` 的 stab 分支；`lua/main.lua` `drawStab` |
| 骨攻模板（round 表） | `D:\stars\reference\lua\bone_battle.lua` |
| 原版骨刺贴图 | `reference\sprites\textures\BoneStabWarn.png`、`BoneStabH.png`、`BoneStabV.png` |
| 探针 | `lua\_probe_stab.lua` |

---

*本文只对比"第 22 段开场骨刺模式"；不涉及任何攻击延时调整（遵循 2026-10-07 政策）。*
