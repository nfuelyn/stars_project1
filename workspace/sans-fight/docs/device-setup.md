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
| `UI控件-客户端`（界面控件模板） | 可被 Lua 动态实例化的图元池 | `c1` 根 + 7 个图元模板 |
| `Lua 脚本` | 逻辑层与适配层 | **1 条自足脚本**（内联 core+attacks+main，≈208 KB） |

游戏**所有画面**（HUD、战斗框、心、骨头、龙骨炮、菜单、标题页、摇杆）都是运行期用这 7 个图元
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

## 2. 客户端模板池：7 个图元

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

名字列与 `tools/build-save.mjs` 生成的模板名逐字一致（编辑器里按名字核对）。
三角只用**中心锚点件 1073743008**；若要加回左下锚点的三角，guid 用 **1073743003**（本轮删除前就是它）。

**只留真的会被取用的图元**（模板数 9 → 7）：判定要同时满足两条 —— ① `lua/main.lua` 里没有
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

### 3.2 复合外观（都是这 7 个图元拼的，便于核对"画出来对不对"）

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
| `main start: mode=core pool=355` | 7 个图元全部实例化成功、预分配 **354** 个控件（= `BUDGET` 之和）+ 1 个闪层 = 355；`mode=demo` 或 `pool` 很小 = 模板池/挂载有问题。**试玩中 `pool=` 不应再增长**：增长说明 BUDGET 小于实测峰值（预算表见 `lua/main.lua` 的 BUDGET 注释） |
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
node tools/run-lua.mjs lua/core_selftest.lua   # 逻辑层自测 + 27 个脚本空跑（期望 215 PASS / 0 FAIL）
node tools/run-lua.mjs lua/_tap.lua            # 画布→世界→UI 命中的点按链路（期望 40 pass / 0 fail）
node tools/run-lua.mjs lua/_title.lua          # 标题页/难度选择（期望 33 pass / 0 fail）
node tools/run-lua.mjs lua/_input.lua          # 平台分流 + 四向矩阵 + 按钮行定位（期望 249 pass / 0 fail）
node tools/run-lua.mjs lua/_geometry.lua       # 绘制 == 判定逐帧对账（≈6 分钟，期望 33 PASS / 0 FAIL）
node tools/run-lua.mjs lua/_flow.lua           # 20 回合整场流程 + 框/心几何（≈6 分钟，期望 溢出 0 / 出框 0 / 错误 0 / 结局文字已渲染）
node tools/run-lua.mjs lua/_pool.lua           # 控件池峰值实测（≈25 分钟，BUDGET 的依据；"运行期追加"必须为 0）
```

> **改完 Lua 必须先重建存档再试玩**：模拟器跑的是**存档里内嵌**的脚本（`scripts[].source`），
> 不是工作区里的 `.lua` 文件 —— 改了 `main/core/attacks` 而不 `build-save`，试玩跑的还是旧代码。
> 一眼判据：试玩日志 `main start: … pool=` 必须等于 `main.lua` 的 BUDGET 合计 + 1（闪层）。
> 20 回合版的正确值是 **531**（旧版 355）。
