# 原版贴图拟合 · Sans / 龙骨炮 / 骨头

- 日期：2026-10-06
- 工具：`tools/fit-sprites.py`
- 数据：`reference/sprites/fit/fitdata.json`、`lua/fitdata.lua`
- 对比图：`reference/sprites/fit/<素材名>.png`（左 原图 | 中 exact | 右 block2）
- 详细统计：`reference/sprites/fit/REPORT.md`

## 1. 拟合口径

| 口径 | 做法 | 特点 |
|---|---|---|
| `exact` | 逐像素游程（RLE）矩形，同色同宽上下合并 | 1:1 还原原图；矩形数 = 真实控件成本 |
| `block2` | 2×2 采样 + 游程合并 | 数量约 exact 的 30–50%；线稿会碎，只适合块状图 |
| `param` | 少量 rect/circle/triangle 参数化外形 | 运行期最省，但只能拟合比例/剪影 |

坐标一律是**图像像素坐标（左上原点、Y 向下）**，接入千星时按 `x_canvas = wx(x)`、`y_canvas = wyBottom(y+h)` 换算；颜色 `#RRGGBB`（千星用 `0xFFRRGGBB`）。

## 2. 三类目标的结果

### 2.1 骨头攻击（已接入运行期）

参考：`Textures/BoneV.png` 10×24、`BoneH.png` 24×10、`BoneStabV/H`、`BoneStabWarn`。

- `BoneV/H` exact 只有 **13 个矩形**；`BoneStab` 同为 13；`BoneStabWarn` 30（16×16 红框）。
- 原图端部是**两颗分离的骨球**，不是一颗大圆。参数化拟合：

  ```
  k   = 0.6 × min(w, h)      -- 骨球直径（10 宽 -> 6）
  骨干 = 中心的 (k × (短边 - 2k/3)) 矩形
  骨球 = 四角 (x, y) / (x+w-k, y) / (x, y+h-k) / (x+w-k, y+h-k) 四颗 k×k 圆
  ```

- 图元数 **5（1 rect + 4 circle）**，与原实现相同，不增加池预算。
- `lua/main.lua` 的 `drawBone()` 已按该模型改写；`reference/sprites/fit/bone_param_preview.png` 是原图/拟合对比。
- exact 表在 `lua/fitdata.lua` 的 `M.bone_vertical` / `M.bone_horizontal` / `M.bone_stab_vertical` / `M.bone_stab_horizontal` / `M.bone_warn`。

### 2.2 龙骨炮（GasterBlaster）

参考：`Animations/GasterBlaster/Default/000.png` 57×44，Fire 5 帧同为 57×44。

- exact：**302–330 个矩形/帧**；block2：119–133。
- 当前运行期是 6 个 rot 矩形（后颅/吻部/2 眼窝/口腔/牙条），剪影接近、细节不足；把它换成 exact 会超出 `rot=106` 的池预算。
- 建议：
  - **A（运行期低预算）**：保持 6 图元参数化，只按参考校准包围盒（57×44）与眼窝/口腔位置。
  - **B（像素级）**：把某一帧的 exact 表烘焙进**容器模板**（子控件静态），运行期只移动/显隐容器；Fire 用 5 个容器切换。exact 表已生成，接入步骤见 §4。

### 2.3 Sans 本体

参考：`SansBody` 64×70（HandUp/Down）/ 96×48（Left/Right）、`SansHead` 32×30（8 表情）、`SansTorso` 54×25 / 72×24、`SansLegs` 44×23 / 52×17。

- exact：身体 **284–653 个矩形/帧**、头 182–198/帧、躯干 346–369/帧、腿 115–214/帧；block2 会让描边碎成点。
- 当前运行期是 13 个 rot 图元（头 32×30、躯干/身体块、双臂、眼窝、汗滴），预算友好但外形是自绘风格，不是原版线稿。
- 建议同上：**A** 继续参数化（按参考 bbox 校准），**B** exact 烘焙容器做像素级还原。Sans 有 8 套头表情 + 4 套身体姿势，若要像素级，建议只烘焙「默认站姿 + 8 表情」两套容器，其余保留参数化。

## 3. 为什么不能直接逐帧画 exact

当前池预算（`lua/main.lua` BUDGET）：`rect=119`、`circle=443`、`rot=106`、`rtri=4`、`ring=2`、`text=15`、`cursor=1`，整场峰值约 406。Sans 本体 exact 单帧就要 284–653 个 rect，龙骨炮 302–330 个，直接逐帧拼装必然触发运行期追加控件（`_pool` 会报「运行期追加 > 0」）。

## 4. 像素级接入（烘焙容器）步骤

1. 用 `tools/fit-sprites.py` 产出目标素材的 `exact` 矩形表（已在 `lua/fitdata.lua`）。
2. 在 `tools/build-save.mjs` 里新增一个**容器模板**：容器本身 1 个 `guid`，children 按 exact 表循环生成 `image` 节点（`imageId=100001`、`imageColor=0xFFRRGGBB`、`size` = 矩形 w/h、位置 = 左下原点换算）。
3. `lua/main.lua` 的 `G` 表登记容器 guid；运行期 `game.InstantiateClientUIControl(guid, parent)` 一次，之后只 `SetAnchoredPosition` / `SetVisible`（每次 1 写）。
4. 同步 `tools/verify-client-pool.mjs` 的 `EXPECT`，跑 `tools/verify-all.mjs` 确认「模板数 == 契约条数」且运行期追加为 0。
5. 体积预估：Sans 身体 600 rect × 约 0.6KB/节点 ≈ 360KB/容器；龙骨炮 330 ≈ 200KB/容器。存档会从约 350KB 涨到 1–3MB，属可接受范围（千星单存档限制需真机确认）。

## 5. 复现命令

```powershell
& 'D:\anaconda\python.exe' D:\stars\workspace\sans-fight\tools\fit-sprites.py
node D:\stars\workspace\sans-fight\tools\verify-all.mjs --quick
```


## 6. 本轮已实现（2026-10-06）

**烘焙范围（按用户删减后的口径）**

- 龙骨炮：`Default` + 3 个开火帧（`Fire/000`、`Fire/002`、`Fire/004`）；运行期按 `cmd.fire`（0→1）
  映射到 3 帧。
- Sans 身体：默认站姿（`HandRight/000`）+ 4 套姿势各一帧（`HandUp/004`、`HandDown/003`、
  `HandLeft/000`、`HandRight/004`）。
- Sans 头：只保留 `Default` 与审判眼 `BlueEye`；其余表情回退到 `Default`。
- 左右姿势：`HandLeft` 用 `mirror = true` 水平镜像（原素材两套姿势朝向相同，原作靠镜像区分左/右）。
- 流汗：保留原来的参数化圆点（4px 圆×0..3），不烘焙 32×9 的 SansSweat。
- 骨头：仍用参数化 5 图元（1 rect + 4 circle），见 §2.1。

**实现方式**

- `tools/build-save.mjs` 新增 3 个容器模板（§2 的 1073743100/101/102），并把 `lua/fitdata.lua`
  作为模块内联进挂载脚本（存档 351 KB → 477 KB）。
- `lua/main.lua` 在 `OnStart` 里创建 `bakedRoot`（prewarm 之前 → 层序在黑底之上、池控件之下），
  首次绘制某个素材时惰性 `bakeSprite`：容器下实例化 exact 矩形子控件，子控件用**比例锚点**
  （`anchorMin/Max = 矩形占比`、`sizeDelta=0`），因此运行期只 `SetSizeDelta` 容器即可整体缩放。
- 逐帧成本：每个可见烘焙素材 = 1 次容器显隐/位置/尺寸写入（惰性创建只在首次）。
- 缩放：`SANS_BAKE_SCALE = 1.6`（Sans，等比，脚底锚定在 `cmd.y + 148`）；龙骨炮 57×44 × `sc`。
- 回退：`fitdata` 缺失或离线单测里被 stub 成空表时，`drawBlaster`/`drawSans` 自动走原来的参数化外观。

**验证**

- `tools/verify-client-pool.mjs`：PASS（10 项契约全部满足）。
- `tools/verify-all.mjs --quick`：6/6 通过（离线单测固定走参数化回退）。
- 另外用 `_tap` 的 mock 引擎 + 真实 fitdata 跑了一遍烘焙路径：7 个容器创建成功
  （default 295 / head 177 / down 299 / blue 181 / up 309 / right 284 / blaster 320 个矩形），
  tap 21/21、PC 输入 40/40，无 `draw ERR`。

**真机待验证（重要）**

- `SetAnchorMin` / `SetAnchorMax`（子控件比例锚点）与容器 `SetSizeDelta` 的跨平台行为；
  模拟器源码支持，真机需按 `docs/device-setup.md` 的挂载流程核验。
- 惰性烘焙的首次实例化耗时（单个容器 177–320 个子控件）；若真机首帧卡顿，可改为关卡加载期预烘焙。
- 版权口径：exact 拟合高度接近参考图，`docs/gdd.md` §7「美术用自绘几何体」的口径需要复核。
