# 给主程序的提示词 —— 缩减「贴地排骨」的骨头宽度

> 直接整段复制给主程序。目标仓库：`D:\stars\workspace\sans-fight`

---

## 任务

缩减**内置"贴地排骨"**（从战斗框底边向上升起的整排厚骨，即附件截图里那种骨头）的单根宽度。
只改这一支生成器，**不要**动其它回合的脚本骨粗细。

## 一、要改的代码（唯一一处）

文件：`D:\stars\workspace\sans-fight\lua\core.lua`

```lua
1962: function Game:spawnFloor(peekSec)            -- ★ 贴地排骨生成器
1966:   local laneW = 60
1967:   local lanes = math.max(4, math.floor(b.w / laneW))
1968:   laneW = b.w / lanes
...
1985:   for L = 0, lanes - 1 do
1989:       w.bones[#w.bones + 1] = {
1990:         kind = 'floor', wave = wave, custom = true, abs = true,
1991:         x = z.l + laneW * (L + 0.5), w = laneW - 6,   -- ★★ 骨头宽度在这里 ★★
1992:         y = z.b, targetH = z.b - z.t, h = TIP_H, t = 0,
1993:         phase = 'peek', peekDur = peek, lethal = false, color = 'white',
1994:       }
```

现状（框宽 575 时）：`lanes = 9`，`laneW ≈ 63.9`，**`w = laneW - 6 ≈ 58px`**。

## 二、怎么改

把内缩量 6 提成一个具名常量，再按需求调大（**内缩越大 → 骨头越细 → 道间缝越宽**）：

```lua
-- core.lua 顶部常量区（与 WALL_GAP / BONE_W 放一起，约 L45 / L96 附近）
local FLOOR_BONE_INSET = 6      -- 原值 6；调大即变细（如 20 / 30）

-- L1991
x = z.l + laneW * (L + 0.5), w = laneW - FLOOR_BONE_INSET,
```

参考换算（框宽 575，`laneW ≈ 63.9`）：

| FLOOR_BONE_INSET | 骨头宽度 w | 视觉说明 |
|---|---|---|
| 6（现状） | ≈ 58 | 截图里的粗骨 |
| 20 | ≈ 44 | 明显变细 |
| 30 | ≈ 34 | 细骨、缝很宽 |
| — | `w = (laneW - 6) * k` | 想按比例缩就乘系数 k（0<k<1） |

> 也可以直接在 L1991 写 `w = (laneW - 6) * 0.6`（缩到 60%），但**建议用常量**，便于以后调。

## 三、不用改的地方（已自动跟随）

- **渲染**：`core.lua` L2911–2915
  `push(cmds, { kind='bone', x = bn.x - bn.w/2, y = bn.y - bn.h, w = bn.w, h = bn.h, vertical=true, ... })`
  → 直接读 `bn.w`，改生成宽度即变。
- **判定（命中盒）**：`core.lua` L2716–2718
  `local rc = { x = bn.x - bn.w/2, y = bn.y - bn.h, w = bn.w, h = bn.h }`
  → 也读 `bn.w`，视觉/判定天然一致（不会"看着细、判定粗"）。
- 骨头在各自"道"里居中（`x = z.l + laneW*(L+0.5)` 再 `x - w/2`），所以**缩宽 = 缝变宽**，道数与位置不变。

## 四、技术代码与权威来源（从这里取）

1. **本项目要改的代码**
   - `D:\stars\workspace\sans-fight\lua\core.lua`
     - L45 `local BONE_W = 10`（脚本骨粗细，**不要动**）
     - L96 `local WALL_GAP = 24`（骨墙内缩，**不要动**）
     - L1962–2000 `Game:spawnFloor`（★ 本次改动）
     - L2002–2021 `Game:spawnWall`（另一支厚骨：`boneW = laneW - WALL_GAP`，**本次不要动**）
     - L2716–2718 贴地骨的命中盒；L2911–2915 贴地骨的渲染
   - `D:\stars\workspace\sans-fight\lua\main.lua`
     - L648–676 `drawBone()` —— 真正把 w/h 画出来：
       竖直骨骨杆宽 = `0.6 * min(w,h)`，总宽 = `w`（所以总宽 58 → 骨杆 ≈35，与截图吻合）
2. **参考仓库（原作）**
   - `D:\c2-sans-fight-src\Event sheets\Battle.xml` → 事件组 `Bones`
       `BoneH` / `BoneV` / `BoneHRepeat` / `BoneVRepeat` / `SineBones` 的尺寸与位移规则
   - `D:\c2-sans-fight-src\Layouts\System.xml` → `BoneV` 默认 **10×48**、`BoneH` **48×10**
   - `D:\c2-sans-fight-src\Textures\BoneV.png` = 10×24、`BoneH.png` = 24×10
   - ⚠ 结论：原作 BoneV 本体就是 **10px 厚**；截图里的"厚骨"是**本项目自建的内置排骨**，
     所以"缩宽"是改本项目生成器，不是改原作贴图。
3. **我给出的独立复刻 / 量化参考**
   - `D:\stars\reference\lua\bone_battle.lua`：`BONE_V_THICK = 10` / `BONE_H_THICK = 10`（脚本骨尺寸与位移）
   - `D:\stars\reference\lua\bonestab_floor_rise.lua`：骨刺几何（`BoneStabV` 宽 12 / `BoneStabH` 高 12）
   - `D:\stars\prompt_round14_bone_thickness.md`：本次的分析与图像实测数据

## 五、验收标准

- [ ] 框宽 575 时，贴地排骨单根总宽从 ≈58 变成你指定的值（如 44 / 34）。
- [ ] 道数与骨头位置不变（仍 `lanes = max(4, floor(框宽/60))`，仍居中于各自道）。
- [ ] 命中盒宽度 == 渲染宽度（同一帧 `w` 一致）。
- [ ] **其它回合不受影响**：脚本骨仍是 `BONE_W = 10`，骨墙仍是 `laneW - WALL_GAP`。
- [ ] 补一个确定性探针：固定框宽（如 575）生成一波贴地排骨，断言 `w == laneW - FLOOR_BONE_INSET`，
      并打印 `lanes / laneW / w` 与相邻骨间隙 `laneW - w`。

## 六、不要做的事

- 不要改 `BONE_W`（会把**所有**脚本骨一起变细，包括 bonegap / bluebone / multi 等回合）。
- 不要改 `WALL_GAP`（那是骨墙的，不是贴地排骨的）。
- 不要分别去改渲染和碰撞——它们都读 `bn.w`，只改生成宽度一处即可。