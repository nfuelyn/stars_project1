# 四选项菜单（攻击/行动/道具/仁慈）UI —— 原版研究 + 当前优化方案

- **原版来源**：`D:\c2-sans-fight-src`（`Layouts/BattleScreen.xml`、`Animations/UIFight|UIAct|UIItem|UIMercy`、`Bad Time Simulator (Sans Fight).caproj`、`Event sheets/Battle.xml`）
- **工作区**：`D:\stars\workspace\sans-fight`（`lua/core.lua`、`lua/main.lua`）
- **日期**：2026-10-09

---

## 1. 原版四选项 UI 研究

### 1.1 对象与家族

| 项 | 内容 |
|---|---|
| 4 个独立 Sprite 对象 | `UIFight` / `UIAct` / `UIItem` / `UIMercy` |
| 家族 | **`UIButtons`**（`.caproj` L1005-1016：members = UIAct/UIFight/UIItem/UIMercy；实例变量 `ID`、`Action`） |
| 各按钮实例变量 | `ID` = 0/1/2/3；`Action` = `MenuFight` / `MenuAct` / `MenuItem` / `MenuMercy`（`BattleScreen.xml` L408-409 / 434-435 / 460-461 / 486-487） |
| 贴图 | 每个按钮 **2 个动画**：`Default` 与 **`Highlight`**，两者都是 **110×42**（`Animations/<对象>/<动画>/000.png` 实测像素尺寸全部 110×42） |

**贴图长什么样**（逐张看过）：

| 按钮 | Default | Highlight |
|---|---|---|
| UIFight | 黑底 + **橙色** `FIGHT` + 左侧小剑图标 | 黑底 + **黄色** `FIGHT`（图标隐去/变暗） |
| UIAct | 黑底 + **橙色** `ACT` + 左侧小图标 | 黑底 + **黄色** `ACT` |
| （UIItem / UIMercy 同规则） | 彩色字 + 小图标 | **黄字** |

> 结论：原版「选中」= **换成 Highlight 贴图（黄字）**，不是改 tint；因为按钮贴图是黑底，在黑色战斗背景上等于"只有文字变色"。

### 1.2 布局（`Layouts/BattleScreen.xml` L400-503）

| 对象 | x | y | w | h |
|---|---|---|---|---|
| UIFight | **32** | 432 | 110 | 42 |
| UIAct | **184** | 432 | 110 | 42 |
| UIItem | **344** | 432 | 110 | 42 |
| UIMercy | **496** | 432 | 110 | 42 |

- **间距：152 / 160 / 152**（即缝隙 42 / 50 / 42）——**不是等距**；
- 整行 **x 32..606**（左 32 / 右 34 边距，基本居中）；
- 行底 **y 432+42 = 474**（画布高 480 → 距底 6px）；
- hotspot = (0,0) 左上角，`width/height` 就是贴图原始尺寸（无缩放）。

### 1.3 选中逻辑与红心（`Battle.xml` L2657-2726）

```
MenuState == 0 → 所有 UIButtons 设回 "Default"
MenuState == 1 → 只把玩家心 Set position to UIButtons."Heart" 图像点（贴图不变）
MenuState == 2 → 先全部 "Default"，再把 ID == MenuStack.Back 的那个：
                   ① 心移到它的 "Heart" 图像点
                   ② 该按钮 Set animation "Highlight"
MenuState == 3 （子面板）→ 心移到 MenuItem.X + 8
```

- **“Heart”图像点**：每个按钮的每一帧都定义了 `image-point name="Heart" x="0.145455" y="0.5"`（`.caproj` L125/130/140/145…）⇒ **0.145455 × 110 = 16px、垂直居中** ⇒ 红心画在**按钮内部左侧 16px**处（不是按钮外面）。
- 按钮的功能分流：`MenuFight` 与 `MenuFightEnemy` 两个函数（`Battle.xml` L1845 / L1868）——同一颗"攻击"在不同情境走不同流程。

---

## 2. 工作区现状

| 位置 | 现状 |
|---|---|
| `lua/core.lua:142` | `local MENU = { bw = 110, bh = 42, gap = 10, y = 400 }`（尺寸已按原版 110×42） |
| `lua/core.lua:143` | `MENU_LABELS = { "攻击", "行动", "道具", "仁慈" }`（**中文**，有意本地化） |
| `lua/core.lua:3010-3015` | `menuLayout()` = 把 4 个按钮按 `bw*4 + gap*3 = 470` **居中** ⇒ `MENU_X0 = 85` ⇒ 按钮 x = **85 / 205 / 325 / 445**（等距 120） |
| `lua/core.lua:3312` | 推 `kind='menu'`：`x=MENU_X0, y=MENU.y, w=110, h=42, items, index, active, interlude` |
| `lua/main.lua:392-405` | `rowYFor(bh, boxBottom)` / `menuRowY(bh)`：按钮行的 y 会**随战斗框底部推挤**（小框 → 432，大框 → 440.5） |
| `lua/main.lua:1800` | 适配层用 `cmd.y = menuRowY(cmd.h)` 覆盖行 y |
| `lua/main.lua:1468-1488` | `drawMenu`：纯**文字**标签（字号 22）、居中；选中 = **红心画在按钮左侧外**（`bx-16, y+bh/2`）+ 文字染黄 |
| `lua/main.lua:409-420` | `menuButtonRect`（同 core 布局）；`menuHeartRect` = 心命中区 `bx-26 … bx-6` |
| `lua/main.lua:423-435` | `menuHitTest`：先测 4 个按钮矩形，再测左侧心区（PC 单击即生效、触屏两段确认） |

---

## 3. 差异对照

| 项 | 原版 | 工作区 | 判定 |
|---|---|---|---|
| 按钮尺寸 | 110×42 | 110×42 | ✅ 一致 |
| 行 y | 432（固定） | 432（小框）/ 440.5（大框，避让框底） | ✅ 基本一致（大框有意的推挤） |
| 按钮 x | **32 / 184 / 344 / 496** | **85 / 205 / 325 / 445** | ❌ 行**偏窄且右移**（整行 470 vs 574） |
| 间距 | **152 / 160 / 152**（非等距） | 120 / 120 / 120（等距） | ❌ |
| 红心位置 | 按钮**内部**左侧 16px、垂直居中 | 按钮**左侧外面** 16px | ❌ |
| 选中视觉 | 整张贴图切 `Highlight`（**黄字**，图标隐去） | 文字染**黄**（C_HP） | ≈ 等价（颜色对，缺"图标/底"层次） |
| 按钮底/图标 | 贴图自带黑底 + 小图标（剑/语音/…） | 纯文字、无底无图标 | ❌（本地化取舍） |
| 语言 | 英文（FIGHT/ACT/ITEM/MERCY） | 中文（攻击/行动/道具/仁慈） | 有意偏离 ✅ |
| 子面板心位置 | 行内（`MenuItem.X + 8`） | 行内（`x + 18`） | ✅ 一致 |
| 触屏 | 单击选中、再点确认 | 同（PC 单击直接生效） | ✅ |

---

## 4. 优化方案

### 方案 A（推荐，低风险：把"位置/心/选中态"对齐原版）

| # | 改动 | 位置 | 具体 |
|---|---|---|---|
| A1 | 按钮行改为**原版非等距布局** | `core.lua` `MENU`（L142）+ `menuLayout()`（L3010） | 用显式 x 表：`MENU.xs = { 32, 184, 344, 496 }`（或 `gaps = {42,50,42}`），`MENU_TOTAL = 574`、`MENU_X0 = 32` ⇒ 按钮 x = **32/184/344/496**，整行 **32..606**（≈居中） |
| A2 | `menuButtonRect` 支持 `xs` | `main.lua:409-414` | `if cmd.xs then return cmd.xs[i], cmd.y, cmd.w, cmd.h end`（命中/绘制/触屏自动跟随，`_input`/`_tap` 的断言也会跟着新矩形走） |
| A3 | 红心移到**按钮内左 16px** | `main.lua:1485`、`menuHeartRect`（L417-420） | 画心：`heart(bx + 16, y + bh / 2, C_RED, 7)`；命中区：`bx + 7, y + bh/2 - 9, 20, 18` |
| A4 | 标签留出内边距（避免与心重叠） | `main.lua:1486` | 文字框从 `bx + 26` 起、宽 `w - 32`、仍居中 ⇒ 中文 2 字（≈44px）在 78px 里，与心（bx+9..bx+23）不重叠 |
| A5 | 选中/未选中配色明确 | `main.lua:1486` | 选中 = 黄（`C_HP`，= 原版 Highlight 的黄），未选中 = 白（`C_WHITE`）——**保持现状即可**，A3/A4 做完观感即与原版一致 |

**预期新几何**

```
按钮 x: 32 | 184 | 344 | 496      间距 152 / 160 / 152      整行 32..606
按钮 y: 432（小框）/ 440.5（大框，避让）        尺寸 110×42
红心:  (bx + 16, y + 21)          命中区 20×18（与相邻按钮不再重叠 ⇒ 命中优先级可简化）
```

### 方案 B（建议，观感更像原版：给按钮加"底 + 描边"）

- 用千星预设节点给每个按钮加：**黑色底 + 1px 白色描边**（未选中）/ **黄字 + 描边不变**（选中）；
- 选中时把图标**隐去或压暗**（对应原版 Highlight 贴图里图标不可见）；
- 代价：多 4 个矩形节点（池预算足够，见 `docs/prefab-pool.md`），并将 4 个按钮从"纯文本"升级为"文本 + 底框"。

### 方案 C（可选：图标与动效）

1. 按钮左侧加小图标（剑 / 语音 / 背包 / 双手）——与原版 Default 贴图一致；
2. 选中瞬间做 1~2 帧的轻微放大或描边加粗（原版是换贴图，硬切即可，不必加动画）；
3. 中场（`interlude`）时给"攻击"一个提示态（原版中场仍保留按钮行，只有"攻击"能推进回合）。

### 不建议改的

- 行 y 的"大框推挤"（`menuRowY`）：那是为了避免按钮压到战斗框底边，属**有意偏离**，保留；
- 中文标签：本地化取舍，宽度在 110px 内够用（2 字 × 22px ≈ 44px）。

---

## 5. 影响面与验收

| 面 | 影响 |
|---|---|
| 命中/触屏 | `menuButtonRect`/`menuHeartRect`/`menuHitTest` 共用同一套公式 ⇒ 改布局后**绘制与判定仍同源** |
| 现有自测 | `_input.lua` 的 `menuRowYFor` 断言（432/440.5/441 等）**不受影响**（那测的是 y）；`_tap.lua` 用 `main.menuRowRect` 现算坐标 ⇒ 自动跟随 |
| 需要新增断言 | ① 4 个按钮 x = 32/184/344/496；② 红心 = `(bx+16, y+21)` 且落在按钮矩形内；③ 相邻按钮不再被心区覆盖（`menuHeartRect` 与邻居矩形不相交） |
| 回归 | `node tools/build-save.mjs`（**无 CSV 改动 → 不跑 gen-attacks**）→ `core_selftest` / `_input` / `_tap` / `verify-all --quick` |

**验证方式**：改完后用无头试玩抓一张菜单截图（`D:\stars\_analysis\ui_kb_shots.mjs` 同款流程），对照原版贴图检查：按钮行铺开到 32..606、选中项黄字、红心在按钮内左侧、四项间距 152/160/152。

---

## 附：原版证据索引

| 内容 | 位置 |
|---|---|
| 4 个按钮实例（x/y/w/h、ID/Action） | `D:\c2-sans-fight-src\Layouts\BattleScreen.xml` L400-503 |
| 家族 UIButtons 与实例变量 | `Bad Time Simulator (Sans Fight).caproj` L1005-1016 |
| Default / Highlight 两个动画 + Heart 图像点 (0.145455, 0.5) | 同 `.caproj` L120-177 |
| 贴图（110×42，橙字/黄字） | `Animations\UIFight|UIAct|UIItem|UIMercy\{Default,Highlight}\000.png` |
| 选中逻辑（MenuState 0/1/2/3、心定位、切 Highlight） | `Event sheets\Battle.xml` L2657-2726 |
| 按钮功能分流 MenuFight / MenuFightEnemy | `Event sheets\Battle.xml` L1845 / L1868 |
