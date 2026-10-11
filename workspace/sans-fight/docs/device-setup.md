# 真机 / 沙箱配置清单（照抄即可）

本文是「审判者战」在**千星沙箱真机**（以及模拟器会话）里落地所需的全部配置项：资产、坐标、样式、
脚本导入与脚本映射流程。数值全部来自仓库内的生成器与校验脚本，不是手抄：

* `tools/build-save.mjs` —— 生成完整存档（服务端容器 + 客户端模板池 + 4 条脚本）
* `tools/verify-client-pool.mjs` —— 逐项校验客户端控件组契约（当前 PASS，7 项）
* `sans-fight.save.json` —— 上述生成结果，可直接回读

---

## 0. 三类资产与总览

| 资产 | 作用 | 内容 |
|---|---|---|
| `UI控件-服务端`（界面控件组） | 运行时容器 + 脚本挂载点 | `sc1` 客户端控件容器 → `n1` 容器节点 |
| `UI控件-客户端`（界面控件模板） | 可被 Lua 动态实例化的图元池 | `c1` 根 + **10 个模板**（7 图元 + 3 烘焙容器） |
| `Lua 脚本` | 逻辑层与适配层 | **1 条自足脚本**（内联 core+attacks+main，≈208 KB） |

游戏**所有画面**（HUD、战斗框、心、骨头、龙骨炮、菜单、标题页、摇杆）都是运行期用这 10 个模板
实例化出来的；编辑器里看不到实体控件，试玩时才会出现。这是本项目「外观全部由 Lua 承担」的设计。

---

## 1. 服务端控件：两个节点

| 字段 | `sc1` 客户端控件容器 | `n1` 容器节点（**脚本挂这里**） |
|---|---|---|
| 索引/guid | 1073741850 | 1073741851 |
| 类型 | container（服务端根） | container |
| 锚点类型 | **双向拉伸** | **双向拉伸** |
| anchorMin | (0, 0) | (0, 0) |
| anchorMax | (1, 1) | (1, 1) |
| pivot | (0.5, 0.5) | (0.5, 0.5) |
| size | 0 × 0（拉伸后即画布全屏） | 0 × 0 |
| 初始激活 / 可见 | true / true | true / true |
| **显示常驻光标 `showCursor`** | 默认即可 | **true** ← 不开收不到任何指针/触摸事件 |
| 屏蔽按键事件穿透 `disableKeyEventPassthrough` | 默认 | **false** ← 开着收不到 WASD / 确认键 |
| 屏蔽区域内点击事件穿透 `disableCursorEventPassthrough` | 默认 | **false** |
| 同步信息至所有设备 `syncAllDevices` | true | true |
| 可被手柄摇杆导航选中 `canControllerFocus` | false（不需要） | false（不需要） |
| 隔离手柄导航 `isolateNavigation` | false | false |
| **脚本映射** | 无 | **挂 boot 脚本（索引 1073742105）** |

> 三个「false / true」是本项目唯一必须在编辑器里逐项确认的业务字段；其余保持默认即可。
> 服务端容器本身只是资源分组，脚本要挂在它下面的客户端节点（本项目就是 `n1`）上。

---

## 2. 客户端模板池：10 个模板（7 图元 + 3 烘焙容器）

根节点：`c1`，索引 **1073742999**，双向拉伸（0,0)-(1,1)、pivot (0.5,0.5)、size 0，无脚本映射。

| 索引/guid | 名称 | 类型 | 图元 `imageId` | 默认尺寸 | 锚点 / 中心 | 平台槽 |
|---|---|---|---|---|---|---|
| 1073743001 | 矩形图元 | image | 100001 rect | 8 × 8 | 左下 (0,0) / (0,0) | 4 |
| 1073743002 | 圆形图元 | image | 100002 circle | 8 × 8 | 左下 (0,0) / (0,0) | 4 |
| 1073743004 | 文本图元 | textbox | — | 200 × 40 | 左下 (0,0) / (0,0) | 4 |
| 1073743006 | 圆环图元 | image | 100006 ring | 8 × 8 | 左下 (0,0) / (0,0) | 4 |
| 1073743007 | 旋转图元（旋转矩形件） | image | 100001 rect | 8 × 8 | **中心 (0.5,0.5)** | 4 |
| 1073743008 | 旋转三角图元 | image | 100003 triangle | 8 × 8 | **中心 (0.5,0.5)** | 4 |
| 1073743009 | 全屏光标区 | **cursor** | — | 拉伸铺满 | (0,0)-(1,1)，pivot (0.5,0.5) | 4 |
| 1073743100 | 烘焙容器·左下 | **container** | — | 0 × 0 | 左下 (0,0) / (0,0) | 4 |
| 1073743101 | 烘焙容器·中心 | **container** | — | 0 × 0 | **中心 (0.5,0.5)** | 4 |
| 1073743102 | 烘焙容器根 | **container** | — | 拉伸铺满 | (0,0)-(1,1)，pivot (0.5,0.5) | 4 |

名字列与 `tools/build-save.mjs` 生成的模板名逐字一致（编辑器里按名字核对）。
三角只用**中心锚点件 1073743008**；若要加回左下锚点的三角，guid 用 **1073743003**（本轮删除前就是它）。

**关于最后 3 个「烘焙容器」**：它们不参与 `take()` 池（
`tools/verify-client-pool.mjs` 的契约里单列），用途是承载**逐像素烘焙**的 Sans 身体/头部 ——
容器下的每个子矩形在运行期用 `SetAnchorMin/SetAnchorMax` 按素材像素定位，整块只创建一次、之后不再写属性。
容器根（1073743102）挂在最底层之上、控件池之下，保证层序正确。

**只留真的会被取用的图元**（模板数 9 → 7，再加上 3 个烘焙容器 = 10）：判定要同时满足两条 —— ① `lua/main.lua` 里没有
`take('<kind>')`；② 整场对局里该 guid 的实例化次数为 0（`lua/_pool.lua` 的 C 节逐 guid 统计）。
按此删掉的是 **100004 fourstar（1073743005，从未被取用）** 与
**100003 的左下锚点三角（1073743003，三角只用中心锚点的 `rtri` 1073743008）**。
保留的都有明确调用点：`ring` 虚拟摇杆、`rot`/`rtri` 旋转件、`text` 文本、`cursor` 全屏输入面。
`tools/verify-client-pool.mjs` 会断言「存档模板数 == 契约表条数」，两边一起改才算同步。

**索引不可改**：Lua 里 `game.InstantiateClientUIControl(prefabIndex, parent)` 的首参就是这个索引。
索引一变，实例化返回 nil，表现为屏幕全空、日志里只有 `main: inst NIL xxx`。
平台槽 4 = KEYBOARD / TOUCHSCREEN / CONTROLLER_CONSOLE / CONTROLLER_MOBILE 四套变换，缺哪台补哪台。

**锚点必须按表**：适配层写 `SetAnchoredPosition` 时，轴对齐件假设「锚点=中心=左下」，旋转件假设
「锚点=中心=中心」。全屏光标区必须是拉伸（适配层从不写它的尺寸/位置，靠拉伸自动铺满）。

---

## 3. 样式（颜色、图元构成、文本）

默认字段一律保持生成值：`imageColor = 0xFFFFFFFF`、`enableMask/enableSoftEdge/enableFill = false`、
`imageSource = StaticReference`、`raycastTarget` 只在光标区为 true。**颜色与尺寸全部由 Lua 每帧写入**，
编辑器里设的默认值只影响未运行时的外观。

### 3.1 运行期颜色（`c.imageColor = 0xAARRGGBB`，alpha 生效）

| 用途 | 值 |
|---|---|
| 骨·白 / 骨·蓝 / 骨·橙 | `0xFFFFFFFF` / `0xFF2F6BFF` / `0xFFFF7A18` |
| 心·红 / 心·蓝 | `0xFFFF2B2B` / `0xFF63B0FF` |
| 心·无敌帧闪烁 | `0x66FFFFFF`（每 4 帧交替） |
| 战斗框 / 边界 / 平台 / 骨墙 | `0xFFFFFFFF` |
| 血条黄 `HP` / 紫 `KR` | `0xFFFFD200` / `0xFF9B59FF` |
| 龙骨炮蓄力 | 白，alpha 0.55；开火 1.0 |
| 骨刺预警 `peek` | 白，alpha 0.9 |
| 文字 | 由逻辑层下发 `#RRGGBB`，适配层转 ARGB |

### 3.2 复合外观（都是这 7 个图元拼的，便于核对"画出来对不对"；Sans 本体走第 8~10 个烘焙容器）

| 实体 | 构成 |
|---|---|
| 一根骨 | 1 条矩形（骨干）+ 4 个圆（两端各两颗骨球） |
| 正弦骨 | 多段长矩形（`19 × 79.7` / `19 × 60.3`）沿正弦分布 |
| 龙骨炮 | 1 个方形炮身 + 5 条细长矩形光束 + 9 段拉链短横 |
| 战斗框 | 4 条细矩形（上下左右各一条） |
| 心 | 2 个圆（双瓣）+ 1 个倒三角 |
| 骨刺 | 1 条矩形，按方向旋转（用旋转图元） |
| 骨墙 | 多条矩形 + 中间缺口 |
| 虚拟摇杆 | 1 个圆环（外圈）+ 1 个圆（摇杆头） |
| 标题页 / HUD / 菜单 / 面板 | 文本图元 + 细矩形 |

### 3.3 文本图元字段

`text`（默认空，运行期写）、`fontSize`（运行期 10–36）、`horizontalAlignment`（Left/Middle/Right）、
`verticalAlignment`（Top）、`fontColor 0xFFFFFFFF`、`bgColor 0x00FFFFFF`（透明底）、
`enableOutline true` + `outlineColor 0x33333333`。**没有 `SetText` 方法**，只能写 `c.text` 属性。

---

## 4. 坐标

### 4.1 画布

原点**左下**，锚点相对父矩形 0–1。五个预设在 `build-save.mjs` 里都生成了变换槽；
本项目按「世界 640×480 等比缩放 + 居中留边」绘制，公式：

```lua
S  = math.min(CW / 640, CH / 480)
OX = (CW - 640 * S) / 2      -- 左右留边
OY = (CH - 480 * S) / 2      -- 上下留边
canvas_x        = OX + world_x * S
canvas_y_bottom = OY + (480 - (world_y + world_h)) * S     -- 注意取的是"下边"
```

| 画布 | 像素 | S | OX | OY |
|---|---|---|---|---|
| mobile-16-9（**构图基准**） | 1280 × 720 | 1.5 | 160 | 0 |
| mobile-19.5-9 | 1560 × 720 | 1.5 | 300 | 0 |
| mobile-4-3 | 1280 × 960 | 2 | 0 | 0 |
| pc-16-9 | 1600 × 900 | 1.875 | 200 | 0 |
| pc-21-9 | 2100 × 900 | 1.875 | 450 | 0 |

### 4.2 编辑器里不需要摆任何控件

战斗框、心、骨头的位置全是运行期算的，编辑器里没有可摆的节点。要核对"画对没有"，用世界坐标换算：

| 参照物 | 世界坐标（640×480，Y 向下） | 换算到 mobile-16-9 画布（left/bottom/宽/高） |
|---|---|---|
| 默认战斗框 | (240, 226) 160 × 165 | left 520, bottom 133.5, 240 × 247.5 |
| 回合 1 战斗框 | (110, 179) 420 × 260 | left 325, bottom 61.5, 630 × 390 |
| 高难回合战斗框（R6） | (20, 139) 600 × 340 | left 190, bottom 1.5, 900 × 510 |
| 按钮行（4 项） | **y 432..468**（行顶 = 屏幕中心 240 + 192，对齐参考实现），x 85..555 | left 287.5, bottom 18, 705 × 54 |
| 标题页难度卡（第 i 张，i=0..3） | x = 32 + i×145，y 210，130 × 40 | left = 208 + i×217.5, bottom 345, 195 × 60 |
| HUD 台词行 | 居中 y 86 | 居中，bottom 591 |
| 摇杆（按住左半屏出现） | 半径 46 | 半径 69 |

按钮行只有两种修正：**框下沿 +2**（有空间时不压框）、**`480 − 行高36 − 3` 的世界内上界**。
**唯一允许与战斗框重叠的情形** = 终盘超大框（框底 478.5，下方只剩 1.5px，物理上放不下 36px 的行）：
此时行被上界钳到 **441**、压在框内（与原作"按钮画在框内黑色区域上"一致）。
三个相位实测：小框（框底 391）→ 432；常规大框（框底 438.5）→ 440.5；终盘超大框 → 441。
整场逐帧断言见 `lua/_flow.lua`（偏离常量 0 帧 / 越界 0 帧 / 框下有空间却重叠 0 帧）。

三个状态（战斗 / 菜单 / 攻击条 / 子面板）战斗框位置**完全相同**，只有脚本 `CombatZoneResize`
变形时才是逐帧平滑缩放——如果观察到框在这些状态之间跳动，那是回归。

---

## 5. 脚本导入

### 5.1 一条**自足**挂载脚本（2026-10-05 起）

| 索引 | 内容 | 角色 | 挂载 |
|---|---|---|---|
| 1073742105 | 内联包（core.lua + attacks.lua + main.lua + 模块垫片，≈208 KB） | **唯一需要的脚本**：自带 `local __modules/require` 垫片，把三个模块原样内联；末尾定义 7 个生命周期函数 | 挂在 `n1` |

**为什么不再用 4 条脚本 / require 路径**：参考仓库 nightingale-0/millastra-6nimmt 的 `AGENTS.md` 写了
实测结论 ——「The official client Lua sandbox has no `require` global」。我们原来靠
`require('default_import_file/workspace/sans-fight/lua/main')` 在模拟器里能跑，但**真机可能直接起不来**。
现在由 `tools/build-save.mjs` 在构建时把三个 `.lua` 内联进挂载脚本（做法与 6nimmt 的 `bundleModules` 一致），
真机只需要这一条脚本，不再依赖任何路径解析。

源码仍然是分文件的（`lua/core.lua` / `lua/attacks.lua` / `lua/main.lua` / `lua/boot.lua`），
**改完任何 `.lua` 都要跑 `node tools/build-save.mjs` 重建存档**，模拟器/真机跑的是存档里的内联包。

### 5.2 目录布局

只有 `lua/boot.lua` 需要（可选地）映射到客户端导入根；**内联包不读文件、不 require 路径**，
所以目录怎么放都不影响运行。若仍想用旧的多文件方式（调试 require 路径时），把
`tools/build-save.mjs --script lua/boot.lua` 传进去即可生成"只挂 boot"的旧式存档。

### 5.3 三种导入方式

1. **从存档回读**（模拟器/沙箱最省事）：载入 `sans-fight.save.json`，1 条自足脚本一次就位。
2. **手工建脚本**：在 `Lua 脚本` 页建 1 条，把 `outputs` 里那条内联包（或 `sans-fight.save.json` 的
   `assets.scripts[0].source`）整段贴进去，设为挂载脚本挂到 `n1`。
3. **实机脚本同步**（推荐，避免手抄）：
   ```json
   { "action": "configure", "args": {
       "config": { "version": 1,
                   "workspaceDir": "D:/stars/workspace/sans-fight",
                   "clientImportRoot": "<千星客户端导入根>",
                   "clientSubdir": "workspace/sans-fight" },
       "expectedRevision": <最新 revision> } }
   ```
   然后 `preview` 看差异 → **由用户在「Lua 脚本 → 实机脚本同步」页面点「确认复制」**。
   AI 不代按、不用 shell 绕过；`workspaceDir` 与 `clientSubdir` 通常同值，以保留 GIA 映射的相对路径。
   当前本机 `discover` 没有任何候选目录，所以 `clientImportRoot` 需要你给出。

---

## 6. 脚本映射流程（端到端）

1. **建资产**：服务端容器 `sc1`/`n1`（第 1 节）+ 客户端模板池 7 图元（第 2 节）。
   GIA 整合包会两类并排写入，导入时自动拆回。
2. **放脚本**：把 `sans-fight.save.json` 里那条内联包（`assets.scripts[0].source`）整段录成一个脚本；
   或直接「从存档回读」，脚本会自己就位（真机不读文件、不 require 路径，见 5.1）。
3. **建脚本映射**：把这条脚本 **挂到 `n1`**（编辑器里选中 `n1` → 脚本映射 → 选它）——只需这一条。
4. **同步内容**（改了 Lua 之后）：`qxqy_script_sync` 的 `configure` → `preview` →
   **用户在页面确认复制** → 覆盖前会自动备份、过期计划会被拒绝。
5. **沙箱里保存并重新试玩**：新增脚本还要补映射与挂载；已有脚本内容变更复制后直接重开即可。
6. **验证**（见第 7 节）。
7. **导出 GIA 送回真机链路**时注意：**GIA 不保存脚本挂载关系**，导入后必须回到第 3 步手工挂一次；
   脚本索引在导入后可能被重新分配，若发生重映射，用 `controlGuidChanges` 记录把 Lua 里的索引引用
   一起改正（不能只改控件索引就宣称修好）。

---

## 7. 自检清单

试玩后按日志逐条对：

| 期望日志 | 含义 |
|---|---|
| `main init: root=true canvas=… scale=… ox=…` | `n1.showCursor` 与画布读取正常；`root=false` 说明挂载点不对 |
| `main start: mode=core pool=2018` | 10 个模板全部实例化成功、预分配 **2015** 个控件（= `BUDGET` 之和）+ 背景 + 闪层 + 烘焙容器根 ≈ 2018；`mode=demo` 或 `pool` 很小 = 模板池/挂载有问题。**试玩中 `pool=` 不应再增长**：增长说明 BUDGET 小于实测峰值（预算表见 `lua/main.lua` 的 BUDGET 注释） |
| 无 `main: inst NIL …` | 有这条 → 该图元的**索引**或**图元 id** 不对 |
| `阶段 nil → title` | 正常：停在标题页等选难度 |
| `点按难度卡 N → 开局` → `阶段 title → enemy (round=0)` | 指针事件链路通（`showCursor` 生效） |
| `点按菜单第 1 项（攻击）` → `阶段 menu → attack` → `点按 → 攻击条结算` | 菜单/攻击条交互链路通 |
| 无 `main: WARN 战斗框坐标异常` | 战斗框坐标契约正常（出现即 core 回归；demo 回退路径的演示框不适用此条） |
| 无 `boot: require main 失败` | require 路径与目录布局一致 |

常见症状对照：

| 症状 | 原因 |
|---|---|
| 试玩全空、只有 HUD 文字 | 图元索引/`imageId` 不对（看 `inst NIL`） |
| 点哪里都没反应 | `n1.showCursor` 没开，或点击穿透被屏蔽 |
| WASD 不动 | `disableKeyEventPassthrough = true` |
| 画面整体偏移/贴边 | `sc1`/`n1` 锚点不是双向拉伸 |
| 文字竖着叠在一起 | 写的是 `c.visible` 之类只读属性；用 `SetVisible()` / `c.text` |
| 换设备后错位被裁 | 模板缺对应平台槽（应各 4 套） |

---

## 8. 本地校验命令

```powershell
# 推荐：一条命令跑完全部离线回归 + 重建存档 + 契约校验（自动判读汇总行，失败退出码 1）
node tools/verify-all.mjs             # 全部（_geometry ≈6 分钟、_pool ≈25 分钟）
node tools/verify-all.mjs --quick     # 跳过最慢的 _geometry / _pool
node tools/verify-all.mjs --no-build  # 只跑测试，不重建存档

# 想单跑某几项：
node tools/build-save.mjs            # 生成存档（会按内容筛选编辑器快照，跳过演示模板时期的快照）
node tools/verify-client-pool.mjs    # 客户端控件组契约校验（期望 PASS，7 项）
node tools/run-lua.mjs lua/_check.lua          # 语法 + 四档难度 900 帧（不该出现 RUN FAIL）
node tools/run-lua.mjs lua/_rounds.lua         # 20 回合结构/抽签/清场/螺旋档保真（期望 54 PASS / 0 FAIL）
node tools/run-lua.mjs lua/core_selftest.lua   # 逻辑层自测（期望 278 PASS / 0 FAIL）
node tools/run-lua.mjs lua/_tap.lua            # 画布→世界→UI 命中的点按链路（期望 40 pass / 0 fail）
node tools/run-lua.mjs lua/_title.lua          # 标题页/难度选择（期望 33 pass / 0 fail）
node tools/run-lua.mjs lua/_input.lua          # 平台分流 + 四向矩阵 + 按钮行定位（期望 249 pass / 0 fail）
node tools/run-lua.mjs lua/_geometry.lua       # 绘制 == 判定逐帧对账（≈6 分钟，期望 33 PASS / 0 FAIL）
node tools/run-lua.mjs lua/_flow.lua           # 20 回合整场流程 + 框/心几何（≈6 分钟，期望 溢出 0 / 出框 0 / 错误 0 / 结局文字已渲染）
node tools/run-lua.mjs lua/_pool.lua           # 控件池峰值实测（≈25 分钟，BUDGET 的依据；"运行期追加"必须为 0）
node tools/run-lua.mjs lua/probes/_probe_sandbox_adapter.lua   # 沙箱接轨层（候选索引/包装解开/生命周期/更新回调，≈2 秒）
```

> **改完 Lua 必须先重建存档再试玩**：模拟器跑的是**存档里内嵌**的脚本（`scripts[].source`），
> 不是工作区里的 `.lua` 文件 —— 改了 `main/core/attacks` 而不 `build-save`，试玩跑的还是旧代码。
> 一眼判据：试玩日志 `main start: … pool=` 必须等于 `main.lua` 的 BUDGET 合计 + 1（闪层）。
> 20 回合版的正确值是 **531**（旧版 355）。

---

## 2.1 真机编辑器：容器包装写法

真机编辑器可能没有模拟器里的“根节点 / 子节点”文字，也可能要求客户端资产只能新增“容器节点”。按下面方式对应即可。

### 服务端控件容器

- 在服务端界面中新建一个“客户端控件容器”。
- 在该容器项的属性面板中设置：
  - `showCursor = true`
  - `disableKeyEventPassthrough = false`
  - `disableCursorEventPassthrough = false`
  - `syncAllDevices = true`
- 找到“脚本映射 / 挂载脚本 / Script Mapping”，把脚本 `1073741825` 挂到容器节点 `1073741857`。
- 如果编辑器额外显示一个“容器节点 / 挂载节点”输入框，则把它的 GUID 设为 `1073741851`；没有该输入框时，直接在容器项上挂脚本。

### 客户端模板：用容器节点包装

如果客户端资产只能添加“容器节点”，不要强行找“图片节点 / 文本节点 / 光标节点”入口，改用包装结构：

```text
容器节点  GUID=1073743001  名称=矩形图元
└─ 图片控件               imageId=100001

容器节点  GUID=1073743002  名称=圆形图元
└─ 图片控件               imageId=100002

容器节点  GUID=1073743004  名称=文本图元
└─ 文本框

容器节点  GUID=1073743006  名称=圆环图元
└─ 图片控件               imageId=100006

容器节点  GUID=1073743007  名称=旋转图元
└─ 图片控件               imageId=100001

容器节点  GUID=1073743008  名称=旋转三角图元
└─ 图片控件               imageId=100003

容器节点  GUID=1073743009  名称=全屏光标区
└─ 光标检测控件

容器节点  GUID=1073743100  名称=烘焙容器·左下
└─ 烘焙子控件由 Lua 运行期生成
```

容器包装的 GUID 必须仍然使用映射表里的 GUID；子控件类型按上表放置。`main.lua` 已兼容这种结构：实例化叶子模板时，如果拿到的是容器，会自动取容器的第一个子控件；直接图片/文字模板仍保持兼容。

---

## 2.2 真实千星 GUID 对照

真实千星已确认以下通用模板：

| 项目 | GUID |
|---|---:|
| 客户端控件容器 | `1073741856` |
| 容器节点（脚本挂载点） | `1073741857` |
| 客户端脚本 | `1073741825` |
| 客户端模板·光标检测 | `1073741860` |
| 客户端模板·容器节点 | `1073741862` |
| 客户端模板·矩形 | `1073741865` |
| 客户端模板·文本框 | `1073741867` |
| 客户端模板·圆形 | `1073741871` |
| 客户端模板·圆环 | `1073741875` |
| 客户端模板·旋转图元 | `1073741877` |
| 客户端模板·旋转三角形图元 | `1073741879` |

各图片模板使用上述独立 GUID，**模板本身自带图案**。
注意：适配层默认**不再调用 `SetImage`**（见 2.3）—— 模拟器的 `100001..100006` 是内置图元编号，
真机没有对应资产，写上去会把本来有图案的图元刷成空白。只有确认真机图片资产 ID 后才在
`lua/config.lua` 的 `C.images` 里填正整数。

---

## 2.3 沙箱接轨层（lua/config.lua + 候选索引）

接轨部分集中在 `lua/main.lua`，环境相关的项集中在 `lua/config.lua`（**改完要 `node tools/build-save.mjs` 重建存档**）。

| 项 | 默认 | 说明 |
|---|---|---|
| `C.updateCallback` | `'level'` | 只推进 `OnLevelUpdate`（与关卡暂停一致）。**只有**外部宿主只调用 `OnUpdate` 时才改 `'ui'`；两个都推进会每帧跑两遍 |
| `C.device` | `'auto'` | 读 `game.GetDevice()`；`keyboard` / `touch` 可强制分支（真机调试） |
| `C.templatesFirst` | `'sim'` | 先试模拟器索引（真机拿不到会返回 nil，自动接着试真机索引）；纯真机工程可改 `'real'` |
| `C.legacyTemplateFallback` | `true` | 是否允许回退到模拟器 GUID |
| `C.templates` | `nil` | 覆盖单个图元的模板索引（留 nil 用 `lua/main.lua` 里的候选列表） |
| `C.images` | `nil` | `nil`/`0` = **沿用模板自带图片**（真机推荐）；只有确认真实图片资产 ID 才填正整数 |

模板索引走**候选列表**，逐个试到实例化成功为止（不认识的索引只会返回 nil，不会污染结果）：

| 图元 | 候选 1（用户确认的客户端控件模板） | 候选 2（交接包实测的挂载后索引） | 容器回退 |
|---|---:|---:|---:|
| 矩形 | `1073741865` | `1073741887` | `1073741862` / `1073741884` |
| 圆形 | `1073741871` | `1073741889` | 同上 |
| 圆环 | `1073741875` | `1073741890` | 同上 |
| 旋转图元 | `1073741877` | `1073741891` | 同上 |
| 旋转三角形 | `1073741879` | `1073741888` | 同上 |
| 文本框 | `1073741867` | `1073741886` | 同上 |
| 光标检测 | `1073741860` | `1073741885` | 同上 |
| 模拟器 | `1073743001 / 3002 / 3004 / 3006 / 3007 / 3008 / 3009` + 容器 `1073743100 / 3101 / 3102` | — | — |

接轨层的硬约束（`lua/probes/_probe_sandbox_adapter.lua` 逐条断言）：

1. **类型不能靠 `prefabIndex` 判**：包装模板的父层与叶子 `prefabIndex` 相同，用它短路就永远钻不进叶子
   → 只能拿到空容器（屏幕全黑 / 只有一张空图）。只认叶子接口（`SetImage` / `text` / `AddCursorEventListener`）。
2. 包装层要**拉伸铺满父容器**，叶子要归一化成左下 `(0,0)`（旋转件中心 `(0.5,0.5)`），父子都要
   `SetActive(true)` + `SetVisible(true)`。
3. 颜色统一走 `Color(r,g,b,a)`（真机要 ColorValue，整数直接写 `imageColor/fontColor/bgColor` 不生效）；`fontSize` 必须是整数。
4. `script.object` 就是脚本挂载的根容器节点，优先拿它当 `root`（回退 `1073741857 / 1073741856 / 1`），
   并在这个 root 上开 `showCursor` / `disableKeyEventPassthrough` / `disableCursorEventPassthrough`。
5. `memo` 的键是**控件对象本身**，不是 `c.Id`（真机运行期身份是小写 `id`，`c.Id` 可能是 nil，
   会把所有控件串成同一份状态）。
6. `OnStart` 幂等（宿主可能重复触发）；`OnDestroy` 摘掉键盘/游标监听 + 销毁**自建**控件，绝不销毁宿主 root。
7. 真机模板是「容器 + 叶子」→ 每个实例都带子控件，**不做** 2000 份批量预热，改按需创建（否则真机卡死）。

自检：`node tools/run-lua.mjs lua/probes/_probe_sandbox_adapter.lua` → 期望 `31 PASS / 0 FAIL`。

### 5.4 当前本机实际导入路径

```text
clientImportRoot:
C:\Users\19637\AppData\LocalLow\miHoYo\原神\BeyondLocal\248255821\Beyond_Local_Save_Level\1073741827\external_lua_file

脚本相对路径:
main.lua
```

外部目标文件为 `external_lua_file\main.lua`，内容为当前存档的 `assets.scripts[1073742105].source` 自足包。
## 2.4 真机接口类型（2026-10-08 真机日志实测）

真机日志给出三条**类型**事实 + 一条销毁期限制，适配层已按「先字符串、抛错再枚举」双通道实现
（模拟器与真机共用同一段代码，不靠分支猜平台）：

| 真机报错 | 适配层做法 |
|---|---|
| `AddKeyEventListener` 要 `KeyEventType`，给字符串就抛 | `G_REAL.addKeyEvent`：先字符串（模拟器/试玩页就是字符串），抛错再注册 `Enum.KeyEventType.<name>`；返回真正生效的键供 `OnDestroy` 摘除 |
| `AddCursorEventListener` 要 `CursorEventType` | `G_REAL.addCursorEvent`，同上 |
| `horizontalAlignment` 要 `TextHorizontalAlignment` | `G_REAL.setAlign`：第一次先试字符串，被拒就永久切枚举（只探测一次） |
| 销毁阶段不能调 `DestroyClientUIControl` | `OnDestroy` 只摘监听 + 清引用，不主动销毁控件（容器销毁时引擎回收） |

**确认键**：`Enum.KeyEventType` 的键盘项里**没有** `KeyboardMenuConfirmKey`（只有 `ControllerMenuConfirmKey`）。
适配层把「确认」做成多来源聚合：`KeyboardMenuConfirmKey`（试玩页）+ `ControllerMenuConfirmKey` +
`KeyboardJumpKey` + `KeyboardNormalAttackKey`（J）+ `KeyboardInteractKey`（F/E）；
「取消」为 `KeyboardMenuBackKey` + `ControllerMenuBackKey` + `KeyboardDropKey`。
任一来源按住即算按住（`confirmHeld` 按来源聚合，蓝心长按跳跃高度才准）；枚举里没有的来源只打印
「跳过可选键」，不算错误。

真机自检（正常）：

```text
main init: root=true canvas=1600x900 scale=1.875 ox=200.0 oy=0.0
main: 检测到真机模板，跳过大批量预热，改为按需创建控件
main: 跳过可选键 KeyboardMenuConfirmKeyDown（本宿主不认字符串键名，枚举里也没有这一项）
main start: build=2026-10-08-sandbox-adapter device=KeyboardAndMouse touch=false mode=core pool=4 …
```

真机上 `pool=` 很小是正常的（预热被主动跳过、控件按需创建）。**不应**再出现
`main: draw ERR` / 方向键 `bind fail` / `游标监听注册失败` / `无法调用 DestroyClientUIControl`。

### 14.3 确认键还是没反应？用键位诊断

`lua/config.lua` 里把 `C.keyDiag = true`（改完重建存档），OnStart 会把 `Enum.KeyEventType` 里**所有**
事件都挂上「按到就打印」的监听，日志会先打一行：

```text
main: [keyDiag] 已挂 <N> 个按键监听（随便按键，看日志打出的事件名）
```

然后在关卡里按你打算用做「确认」的物理键，日志会打出它对应的事件名，例如
`main: [keyDiag] KeyboardJumpKeyDown`。把那个名字发我，或直接写进 `lua/config.lua` 的候选表
（`lua/main.lua` 的 `bindKeys()` 里那两行 `ipairs({...})`）即可。诊断完把 `C.keyDiag` 改回 `false`
（它会额外挂一百多个监听，只适合排查用）。

---

## 2.5 锚点 / pivot：真机上「黑底只黑左下角」的根因（2026-10-08 真机实证）

### 现象
真机（PC 1600×900）里黑色背景**只铺了屏幕左下角一块**，其它图元也整体偏移，看起来像「坐标原点跑到了屏幕中心」。

### 根因
千星编辑器里新建的控件，RectTransform 默认是 Unity 那套：**锚点 (0.5,0.5)、pivot (0.5,0.5)**。
而适配层 `put()` / `putRot()` 用的是「锚点在左下角 (0,0)、pivot 也在左下角」的口径 ——
`SetAnchoredPosition(cx,cy)` 表示「**锚点到控件左下角**的偏移」。两者不一致时：

- 黑底背景：尺寸 3 倍画布、位置 `(-CW,-CH)`。pivot=0.5 时这个位置变成「**面板中心**」，
  于是面板中心被放到画布左下角外，只有右下四分之一盖住画布 → 只剩左下角是黑的。
- 其它图元：同理按 pivot 反向偏移半宽半高 → 整幅画面错位。

### 修法（已实现）
1. `instantiateTemplate` 里**无条件**调用 `G_REAL.normalizeLeaf(c, kind)`（不再只在「容器包装」分支里做）：
   - 轴对齐件（rect / circle / ring / text / baked）：`anchorMin = anchorMax = pivot = (0,0)`
   - 旋转件与中心容器（rot / rtri / bakedC）：`= (0.5,0.5)`
   - 全屏件（cursor / bakedRoot）：`anchorMin (0,0)`、`anchorMax (1,1)`、`sizeDelta 0`、`anchoredPosition 0`
2. `OnStart` 里把**宿主 root 也拉成铺满画布**（官方文档要求 Root 覆盖画布，锚点 (0,0)-(1,1)、尺寸差 0）——
   用户没在编辑器里配的话，子控件的绝对坐标会相对一个「小盒子」定位。
3. 图片叶子额外清掉 **羽化 / 遮罩 / 填充裁切**（`enableMask=false`、`enableSoftEdge=false`、`enableFill=false`），
   否则拉伸到全屏的黑底会被裁成一小块或边缘发虚。

> 参照物：交接包 `D:\stars\another\...\lua\main.lua` 的 `instantiateTemplate` 同样是**无条件**
> `SetAnchorMin/SetAnchorMax/SetPivot/SetAnchoredPosition`；其 `docs/部署与设置.md` 还明确要求
> 「Root 锚点 (0,0)-(1,1)、位置与尺寸差异都为 0」「图片用基础完整显示、清空软边和填充裁切」
> 「矩形模板要能被拉伸到 1px 小块及全屏尺寸」「父层有内边距/网格/自动布局要先移除」。

### 编辑器里仍需你确认的两点
- `rect` 模板：纯白实心块、alpha 255、**无羽化 / 无遮罩 / 不用填充裁切**，能拉伸（代码会拉成 1px 小条与 3 倍全屏）。
- 父层（客户端控件容器 / 根节点）不要有内边距、网格布局、自动布局 —— 否则比例锚点会偏移。

> 关于「有没有用图片模板自带的资源」：`C.images = nil/0` 表示**沿用模板自带图片**、不调 `SetImage`
> （交接包的 `config.lua` 也是全 0）。真机日志里 `baked sans_body_default … rects=295` 说明 CodeArt
> 贴图配方已在正常生成 —— 这次的问题**不是**图片资源，而是 RectTransform 的锚点/pivot。

自检：`node tools/run-lua.mjs lua/probes/_probe_sandbox_adapter.lua`
→ `PASS 60 / FAIL 0`（含「真机直接模板、Unity 默认中心锚点」替身：断言黑底 pivot 归零、
3 倍画布覆盖、光标区/烘焙根拉伸铺满）。

---

## 2.6 文本框 / 龙骨炮（CodeArt 烘焙）在真机上的口径 —— 2026-10-08

### 黑底（已修）
`bgPanel`（stretch 锚点、尺寸差 0）＋ `bgOver`（stretch 锚点、尺寸差 `+2CW/+2CH`，四周各外扩 1 倍画布）
两层叠加：第一层精确铺满 Root（Root 已被 `stretchFull` 拉成铺满画布），第二层兜住画布外沿。
两层都不依赖 pivot 的绝对摆放。

### 文本框
按交接包文档「背景完全透明、固定字号、不启用自动压缩字号、顶对齐」逐条对齐：

| 属性 | 写法 | 为什么 |
|---|---|---|
| `bgColor` | `Color(0,0,0,0)` | 模板自带底色会糊在画面上 |
| `adaptiveFontSize` | `false` | 真机模板若开着自动压缩，长句会被压小/挤在一起 |
| `verticalAlignment` | `Enum.TextVerticalAlignment.Top` | 我们的排版按「y 是文本框顶边」算 |
| `horizontalAlignment` | `Enum.TextHorizontalAlignment.{Left,Middle,Right}` | 真机只吃枚举（字符串会抛） |
| `fontSize` | 整数 | 小数会抛异常 |

诊断：第一次画文字会打 `main: [diag] 第一个文本框 raw="…" size=… align=…`，随后 `geom[…text…]` 回读几何。

### 龙骨炮 / Sans（CodeArt 烘焙子块）
`newBakedInstance` 里每个像素块现在都显式设 **`SetPivot(0.5,0.5)` + `SetAnchoredPosition(0,0)`**，
与比例锚点（anchorMin/Max = 图块占比）配套。只给比例锚点、pivot 留在 0 时，真机按「锚点到 pivot」解释位置，
**每个像素块会偏半个自身尺寸** —— 龙骨炮/Sans 的烘焙模型就会糊成一团（交接包 `another` 的
`newBakedInstance` 是同口径）。

诊断：
- `main: [diag] blaster bake=… block=… rects=… sc=… deg=…` —— 第一次画炮时打出走的是哪条路径（
  `block=true` = 走 fit 像素配方；`block=false` = 回退到参数化外观）。
- `main: geom[baked:<素材>] …` / `main: geom[baked-child:<素材>] …` —— 每种素材第一次创建时回读
  容器与首个像素块的 anchor/pivot/pos/size。
- `main: geom[root] …` / `geom[bg1-stretch] …` / `geom[bg2-overscan] …` —— 启动时回读根与两层黑底。
