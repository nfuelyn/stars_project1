# 骨缝 / 骨头消失速度 / 旋转龙骨炮轴心 —— 修改文档

- **工作区**：`D:\stars\workspace\sans-fight`
- **数据源**：`prototype/attacks/*.csv` → `tools/gen-attacks.mjs` → `lua/attacks.lua`
- **日期**：2026-10-07
- **回合号口径**：HUD `ROUND x / 24` = 内部号 + 1

| 你的轮次 | HUD | 内部 | 脚本 |
|---|---|---|---|
| round4 | 4 | 3 | `sans_bonegap2` |
| round13 | 13 | 12 | `sans_bonegap2`（与 round4 同一个脚本） |
| round15 | 15 | 14 | `multi1` |
| round22 | 22 | 21 | `multi3` |
| round24 | 24 | 23 | `final` |

---

## 1. round4 / round13：蓝心跳过上下骨缝，缝太小（`sans_bonegap2`）

### 1.1 现状（是上一次改动留下的）

`sans_bonegap2.csv:33`：

```
0,SUB,HeightT,118,$HeightB
```

配合上下骨：

```
0,BoneV,$XL,257,$HeightT,0,$SpeedL      -- 上骨：顶 y=257，高 HeightT
0,BoneV,$XL,$YB,$HeightB,0,$SpeedL      -- 下骨：顶 y=YB=386-HeightB，高 HeightB
```

- 上骨下缘 = `257 + HeightT = 257 + (118 − HeightB) = 375 − HeightB`
- 下骨上缘 = `YB = 386 − HeightB`
- **缝 = (386−HeightB) − (375−HeightB) = 11px**（与 HeightB 无关，恒 11）

对比：
| 常数 | 缝 |
|---|---|
| 原版 `99` | **30px** |
| 当前 `118`（上次误改） | **11px** ← 太窄，魂（视觉 16px）钻不过 |
| 目标 | 30 × 1.3 = **39px** |

### 1.2 改法（只动上骨）

保持下骨（`YB=386−HeightB`、`HeightB`）不动，把**上骨的高度公式**改小：

```
0,SUB,HeightT,118,$HeightB     →     0,SUB,HeightT,90,$HeightB
```

推导：上骨下缘 = `257 + (90 − HeightB) = 347 − HeightB`；缝 = `(386−HeightB) − (347−HeightB)` = **39px** = 原版 30 × 1.3 ✓

| HeightB | 原版 HeightT(99) | 现在(118) | **改为(90)** | 缝 |
|---|---|---|---|---|
| 20 | 79 | 98 | **70** | 39 |
| 30 | 69 | 88 | **60** | 39 |
| 40 | 59 | 78 | **50** | 39 |
| 60 | 39 | 58 | **30** | 39 |

> 只改这一行（`SUB,HeightT` 的常量），**不要动** `YB` / `HeightB` / `BoneV,$XL,257,...`。

---

## 2. round15 / round22：左右两侧骨头向中间汇聚的"消失速度"

### 2.1 先确认位置

- HUD 15 = `multi1`、HUD 22 = `multi3`；
- "左右两侧骨头向中间移动、靠蓝心跳跃躲避" = 两个脚本的 **Attack0 / Attack1**：

```
multi1 / multi3 Attack0:
  0,BoneVRepeat,128,341,45,0,240,4,16     -- 左侧 4 根，向东（向中间）
  0,BoneV,64,286,100,0,240                -- 左侧高骨
  0,BoneVRepeat,512,341,45,2,240,4,16     -- 右侧 4 根，向西（向中间）
  0,BoneV,576,286,100,2,240               -- 右侧高骨
```

### 2.2 现状 diff（vs 原版 `D:\c2-sans-fight-src\Files\sans_multi*.csv`）

| 脚本 | 结论 |
|---|---|
| `multi1` | **逐行完全一致**（105/105 行）——侧骨的数量、位置、速度、间距**都是原版值** |
| `multi3` | 骨行也一致；差异只有：① 龙骨炮延时（1.5↔1.2、Spin 0.66666↔0.6，属"延时政策"不动）；② **我在《骨攻微调技术文档》§4 改过的 Attack5 底边骨带**：`0,BoneVRepeat,121,354,37,2,0,20,20`（原版 `121,364,30,2,0,25,16`） |

运行期两处"骨头消失"相关逻辑也都已是原版口径：

- **渲染/判定裁剪**（竖骨裁进战斗框，逐段裁剪而非整体消失）：
  `core.lua:1287 clipVZone(x,y,w,h,z)` → 与 `BCT` 的 `CombatZoneClipped` + 4 条 clipper 同义；
- **出屏销毁**：`core.lua:1096-1100`
  ```lua
  if (b.vx > 0 and b.x > VW) or (b.vx < 0 and b.x < -b.w)
     or (b.vy > 0 and b.y > VH) or (b.vy < 0 and b.y < -b.h) then kill = true end
  ```
  = 原版 `dir0→X>640 / dir1→Y>480 / dir2→X<-w / dir3→Y<-h` ✓

### 2.3 "我上次文档改错"的候选（按可能性排序）

| # | 候选 | 现在的值 | 原版值 | 是否需要恢复 |
|---|---|---|---|---|
| **a** | **`multi3 Attack5` 底边骨带**（我在《骨攻微调技术文档》§4 改的"密度×2"） | `0,BoneVRepeat,121,354,37,2,0,20,20` | `0,BoneVRepeat,121,364,30,2,0,25,16` | **若你指的就是它 → 改回原版** |
| b | 第八轮记录里对 `multi3 Attack0/4/5` 的"降密度降尺寸"（Attack0 4→3 根@16→30、高45→35/100→70；Attack4 11/10→7 根@24→40、高55→45/15→12；Attack5 25→16 根@16→26、高30→26） | **当前文件已是原版值**（该批改动已不在文件里） | 原版值 | 无需再动 |
| c | 运行期 `pushBone` 把脚本骨速度乘了难度系数 `w:spd()` | `vx = ±w:spd(speed)`，`spd = speed × tune.speed` | 原版无难度缩放（恒 1×） | 若你要"任何难度都=原版速度" → 去掉 `w:spd` |

> `tune.speed`：简单 0.60 / 普通 0.78 / 困难 1.00 / 原作 1.00。
> 也就是说：**只有在"原作"难度下，侧骨速度才等于原版 240**；在简单/普通档它们会更慢（"消失"更慢），这是"难度接入脚本"（我第二轮文档 G3）带来的。

**建议**：
1. 先把 **a** 恢复成原版（`121,364,30,2,0,25,16`）——这是我在骨骼数据上唯一动过 multi3 的地方；
2. 若仍觉得"消失速度"不对，检查你试玩时选的难度；要绝对原版速度就得处理 **c**（去掉脚本骨的 `spd` 缩放，或只在"原作"档禁用缩放）；
3. b 目前已无需处理。

---

## 3. round24：旋转龙骨炮的轴心在特定发射段向上偏移（`final` 阶段④）

### 3.1 现象与实测

`lua/_probe_spiral_pivot.lua`（真实 `final` 脚本 + 真实 Game 路径）输出：

```
  光束#20  实际终点(198,372)  应有终点(198,393)  偏差 21px  ang=-35.6
  光束#21  实际终点(221,372)  应有终点(221,418)  偏差 46px  ang=-48.5
  光束#22  实际终点(248,372)  应有终点(248,438)  偏差 66px  ang=-61.5
  光束#23  实际终点(280,372)  应有终点(280,451)  偏差 79px  ang=-74.6
  光束#24  实际终点(315,372)  应有终点(315,456)  偏差 84px  ang=-87.9
  ...
旋转阶段共 122 发持续光束，其中 37 发终点被钳制（轴心偏移）
```

→ 转一圈 122 发里，**37 发**被钳制，偏差最大 **84px**，全部发生在"朝下"的那半圈 —— 这就是你看到的"轴心在特定发射段向上偏移"。

### 3.2 根因（逐行）

`final` 阶段④的脚本（`final.csv` L162–180）：

```
SET gt 0 / SET gin 1
Ang = gt × (-10)
X = cos(Ang) ; Y = sin(Ang)
EndX = X×150 ; EndY = Y×150
X = EndX×3 ; Y = EndY×3
X += 320 ; Y += 306 ; EndX += 320 ; EndY += 306
Ang += 180
GasterBlaster,0,$X,$Y,$EndX,$EndY,$Ang,0.5,0
```

即：**起点 = 轴心(320,306) + 450·u，终点 = 轴心 + 150·u**（同一射线）→ 光束的轴线必过轴心 (320,306)。

而 `core.lua` 的 `CMD.GasterBlaster`（L764–765）对**终点**做了安全区钳制：

```lua
local ex2 = clamp(tonumber(ex) or 0, BLASTER_SAFE.xmin, BLASTER_SAFE.xmax)   -- 34..606
local ey2 = clamp(tonumber(ey) or 0, BLASTER_SAFE.ymin, BLASTER_SAFE.ymax)   -- 30..372
...
g = { x = sx, y = sy, sx = sx, sy = sy, ex = ex2, ey = ey2, ang = a0, ... }
```

螺旋的终点 `y = 306 + 150·sin` ∈ **[156, 456]**，当 `sin > 0.44`（朝下那半圈）时 `ey > 372` → **被钳到 372**：
- 终点不再落在"轴心→起点"的射线上 → `a0 = atan2(ey−sy, ex−sx)` 算出的**角度也偏**；
- 光柱因此不再汇聚到 (320,306)，看起来像**轴心向上挪了**。

（`BLASTER_SAFE` 的注释是"停靠点不落在选项栏那一条"，对普通炮是合理的；但持续旋转光束的终点本来就会扫到框下沿，钳制在这里反而破坏了轴心。）

### 3.3 修法

**方案 A（推荐，最贴原版）：持续光束不做终点钳制**

```lua
-- core.lua CMD.GasterBlaster
local persistent = (bt ~= nil and bt <= 0)     -- 已在上面算过
local ex2 = clamp(tonumber(ex) or 0, BLASTER_SAFE.xmin, BLASTER_SAFE.xmax)
local ey2 = clamp(tonumber(ey) or 0, BLASTER_SAFE.ymin, BLASTER_SAFE.ymax)
-- 【修】旋转龙骨炮（持续光束）必须保持"起点→终点→轴心"共线，否则轴心会偏：
if persistent then
  ex2 = tonumber(ex) or ex2
  ey2 = tonumber(ey) or ey2
end
```

- 影响面：只影响 `BlastTime<=0` 的持续光束（`final` 阶段④的旋转段），普通龙骨炮的钳制不变；
- 原版本来就没有这个钳制，所以这是"回归原版"。

**方案 B（保守）：沿射线等比缩放起点+终点，保持轴心不变**

若你担心终点跑到选项栏，可改为：当终点超出安全区时，把**起点与终点沿同一条射线一起缩放**，使终点落在安全区内 —— 轴线仍然过原轴心：

```
k = 允许的最大缩放（由终点到安全区边界的距离 / 原距离）
sx, sy, ex, ey = 轴心 + k·(sx-轴心), 轴心 + k·(ey-轴心) ...
```

（实现略复杂，且会改变炮身进场路径；除非 UI 遮挡是硬约束，否则用方案 A。）

### 3.4 验收

| 断言 | 期望 |
|---|---|
| S1 | 螺旋阶段每发：`(ex,ey)` 与 `轴心 + (sx-轴心)/3` 的偏差 < 1px |
| S2 | `_probe_spiral_pivot.lua` → "被钳制 0 发" |
| S3 | 旋转光束的视觉轴线始终过 (320,306)；不再出现"某半圈轴心上移" |
| S4 | 普通（非持续）龙骨炮仍受 `BLASTER_SAFE` 钳制，不压选项栏 |

复现：`node tools/run-lua.mjs lua/_probe_spiral_pivot.lua`

---

## 4. 精确改动清单

| # | 文件 | 位置 | 现在 | 改为 | 说明 |
|---|---|---|---|---|---|
| 1 | `prototype/attacks/sans_bonegap2.csv` | L33（`SUB,HeightT`） | `0,SUB,HeightT,118,$HeightB` | `0,SUB,HeightT,90,$HeightB` | round4/13 缝 11→39（=原版30×1.3），只改上骨 |
| 2 | `prototype/attacks/multi3.csv` | Attack5 底边骨带行 | `0,BoneVRepeat,121,354,37,2,0,20,20` | `0,BoneVRepeat,121,364,30,2,0,25,16` | **仅当你要恢复"我上次文档改动"时**（round22 骨带回到原版） |
| 3 | `lua/core.lua` | `CMD.GasterBlaster`（约 L764–765） | 终点无条件 `clamp` | `persistent` 时不做终点钳制 | round24 旋转轴心不再偏移 |
| 4（可选） | `lua/core.lua` | `pushBone`（`w:spd(speed)`） | 脚本骨速度乘难度系数 | 若要与原版绝对一致，去掉缩放 | 影响所有脚本骨速度（难度设计取舍） |

> 改完 1/2 后必须 `node tools/gen-attacks.mjs` 重新生成 `lua/attacks.lua`，再 `node tools/build-save.mjs`。
> 只改 core.lua（3/4）时**不要**跑 `gen-attacks.mjs`（CSV 与 attacks.lua 可能不同步，之前出过覆盖事故）。

---

## 5. 总验收

```powershell
cd D:\stars\workspace\sans-fight
node tools/gen-attacks.mjs            # 仅当改了 CSV（1/2）
node tools/build-save.mjs
node tools/run-lua.mjs lua/_probe_spiral_pivot.lua   # 期望：被钳制 0 发
node tools/run-lua.mjs lua/core_selftest.lua         # 期望 PASS 281 / FAIL 0
node tools/verify-all.mjs --quick
```

| 项 | 期望 |
|---|---|
| round4 / round13 | 上下骨缝 = 39px（原版 30 的 1.3 倍），下骨未动 |
| round15 / round22 | 侧骨数据 = 原版（multi1 本就一致；multi3 若按 #2 恢复则也一致） |
| round24 | 旋转光束 122 发全部共线于 (320,306)，零钳制 |

---

## 附录：行号索引

| 内容 | 位置 |
|---|---|
| `sans_bonegap2` 缝公式 | `prototype/attacks/sans_bonegap2.csv` L33–34、L50–53 |
| `multi1` Attack0 侧骨 | `prototype/attacks/multi1.csv` L33–36 |
| `multi3` Attack0/5 骨行 | `prototype/attacks/multi3.csv` L33–36 / L121 |
| `CMD.GasterBlaster` 终点钳制 | `lua/core.lua:764-765`（`BLASTER_SAFE` L56） |
| `pushBone` 速度缩放 | `lua/core.lua`（`local function pushBone`，`w:spd(speed)`） |
| `repeatBones`（已对原版） | `lua/core.lua:676` |
| 竖骨裁剪 | `lua/core.lua:1287 clipVZone` |
| 出屏销毁 | `lua/core.lua:1096-1100` |
| final 旋转段脚本 | `prototype/attacks/final.csv` L162–180 |
| 探针 | `lua/_probe_spiral_pivot.lua` |

---

*第 1、3 项均已用数值/探针实测确认；第 2 项已给出与《原版 CSV》的逐行 diff 与三个候选改动（含精确 before/after），其中只有 `multi3 Attack5` 那条是近期由我文档引入的骨骼数据改动。*
