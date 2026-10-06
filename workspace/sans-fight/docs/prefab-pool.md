# 客户端控件「模板池」契约与模拟器 API 实测事实

本文记录**在模拟器源码里读到、并在试玩中实测验证**的客户端 Lua 能力边界，以及本项目据此建立的
prefab 模板池。真机（千星奇域编辑器）接入时按同样契约执行，若真机行为不同，以真机检视器显示为准。

## 1. 动态实例化的正确用法（关键，曾误判为「不支持」）

```lua
-- 只在 OnStart / OnEnable / OnLevelUpdate 里调用；OnInit 里调用**一定返回 nil**
local parent = game.GetClientUIControl(1)          -- 挂载脚本的容器控件
local c = game.InstantiateClientUIControl(prefabIndex, parent)   -- 恰好 2 个参数
```

运行时实现（`dist/worker.js`）：

```js
instantiate(t, parent, phase) {
  if (phase === "OnInit" || phase === "OnDestroy") return null;   // ← 生命周期守卫
  const spec = this.templates.get(Number(t));
  if (!spec || !parent) return null;
  ...
}
```

* **模板池来源**：存档 `assets.client`（客户端控件模板资产）的 `root.children`，
  每个子节点的 `guid` 就是它的 `prefabIndex`（`spec.prefabIndex = node.guid`）。
* 因此「加更多可实例化外观」= 在客户端资产的根下加子节点，不需要别的机制。
* 子节点可挂脚本（`mountSpecScripts`），实例化时脚本会一起挂上。
* `FindClientUIRoot` 传 1 返回 nil；`GetClientUIControl` **不支持按名字**，只认运行期 Id（number）。

## 2. 本项目的模板池（由 `tools/build-save.mjs` 生成，共 10 个）

只登记**真的会被 `lua/main.lua` 的 `take('<kind>')` 取用**的图元：判定要同时满足
① 源码里没有 `take('<kind>')`；② 整场对局里该 guid 的实例化次数为 0
（后者由 `node tools/run-lua.mjs lua/_pool.lua` 的 C 节逐 guid 统计）。
按此删除了 `100004 fourstar`（guid 1073743005，从未被取用）与 `100003` 的**左下锚点**三角
（guid 1073743003；三角只用中心锚点的 `rtri` 1073743008）→ 模板数 9 → 7。
`tools/verify-client-pool.mjs` 会断言「存档里的模板数 == 契约表条数」，两边一起改才算同步。

| guid | 名称 | 类型 | 图元 | 锚点/中心 |
|---|---|---|---|---|
| 1073743001 | 矩形图元 | image | 100001 rect | 左下 (0,0) |
| 1073743002 | 圆形图元 | image | 100002 circle | 左下 (0,0) |
| 1073743004 | 文本图元 | textbox | — | 左下 (0,0) |
| 1073743006 | 圆环图元 | image | 100006 ring | 左下 (0,0) |
| 1073743007 | 旋转图元（旋转矩形件） | image | 100001 rect | **中心 (0.5,0.5)**，供旋转件用 |
| 1073743008 | 旋转三角图元 | image | 100003 triangle | **中心 (0.5,0.5)**，供旋转件用 |
| 1073743009 | 全屏光标区 | cursor | — | **(0,0)-(1,1) 拉伸铺满**：唯一的输入接收面，适配层从不写它的尺寸/位置 |
| 1073743100 | 烘焙容器·左下 | container | — | 左下 (0,0)：exact 逐像素素材（Sans 身体/头）的容器模板 |
| 1073743101 | 烘焙容器·中心 | container | — | 中心 (0.5,0.5)：exact 龙骨炮的容器模板（绕中心旋转） |
| 1073743102 | 烘焙容器根 | container | — | **(0,0)-(1,1) 拉伸铺满**：所有烘焙容器的父级；OnStart 里在 prewarm 之前创建 → 烘焙层在黑底之上、池控件之下 |

名字列与 `tools/build-save.mjs` 生成的模板名逐字一致。
三角只用**中心锚点件 1073743008**；若要加回左下锚点的三角，guid 用 **1073743003**（本轮删除前就是它）。

字号约束：`c.fontSize` 是**整数属性**，写小数会抛
`bad argument #2 to 'fontSize' (integer expected, got number)`；而绘制整体包在 `pcall` 里，
一旦抛出会**中断整帧**并每帧刷屏。适配层写的是缩放后字号（`size * S`），手机 `S=1.5` 恰好都是整数、
PC `S=1.875` 会出现 `14*1.875=26.25` 这种小数，因此 `label()` 里统一取整（`math.floor(size+0.5)`，且 ≥1）。

图元 id 映射（`worker.js`）：`{100001:"rect", 100002:"circle", 100003:"triangle",
100004:"fourstar", 100005:"fivestar", 100006:"ring"}`。图元**随控件矩形拉伸**，
所以「一根骨头」= 1 个矩形（骨干）+ 4 个圆形（两端各两颗骨球），
「战斗框」= 4 条细矩形，「龙骨炮」= 骷髅炮身 6 件（颅骨 + 吻部 + 2 眼窝 + 2 獠牙）
+ 光束 3 条细长矩形 + 4 段拉链短横（共 ≤14 件），「审判者（sans）」= ≤13 件
（腿/身体/内衬/躯干/1~2 手臂/头/2~3 眼窝/0~3 汗滴，全部走旋转矩形池以保证层叠顺序）。

### 2.1 控件池预算（`main.lua` 的 `BUDGET`）

预算 = 实测峰值 + 20%，`OnStart` 一次性预热；**不足会触发运行期实例化**，而新控件按创建顺序
排在闪层之后（会盖住结局画面），所以必须 ≥ 峰值。20 回合结构重测（含螺旋档、四档难度取大）：

| kind | 峰值 | 出现在 | 预算 |
|---|---|---|---|
| rect | 70 | round13 `platforms4hard`（60 根骨头） | 84 |
| circle | 265 | round13 `platforms4hard`（骨头两端骨球） | 318 |
| rot | 88 | round19 `spiral3`（螺旋龙骨炮 + sans 13 件） | 106 |
| rtri | 2 | round0 `sans_intro` | 4 |
| ring | 1 | round0 `sans_intro` | 2 |
| text | 12 | round0（攻击条态） | 15 |
| cursor | 1 | 全程 | 1（必须恰好 1，多份会抢指针事件） |

合计 439 → **530**（+ 闪层 1 = 池总量 531）。旧预算 354 在 20 回合下不够：
rect/circle 峰值从 47/149 涨到 70/265（回合全部由脚本驱动，`platforms4hard` 一回合就 60 根骨头），
整场会出现约 98 次运行期追加（`_flow.lua` 日志里的 `pool=453` 就是它）。

## 3. 控件 Lua API 的硬事实（实测）

| 能力 | 正确写法 | 备注 |
|---|---|---|
| 显隐 | `c:SetVisible(true/false)` | `c.visible = x` **报错** `cannot set visible, no such field`（只读属性） |
| 激活 | `c:SetActive(bool)` | 同上，`active` 只读 |
| 位置 | `c:SetAnchoredPosition(x, y)` | 2 参数；相对锚点 |
| 尺寸 | `c:SetSizeDelta(w, h)` | 2 参数 |
| 旋转 | `c:SetLocalRotation(deg)` | 正角 = 逆时针；旋转件需中心锚点模板 |
| 换图元 | `c:SetImage(id)` | 在 image 控件上可用 |
| 颜色 | `c.imageColor = 0xAARRGGBB` | 属性写入；**alpha 生效**（半透明预告骨靠它） |
| 文本 | `c.text = "..."` | **没有 `SetText`**（在 textbox/textwindow 上均为 nil），只能写属性 |
| 字号/对齐 | `c.fontSize = n` / `c.horizontalAlignment = "Left"/"Middle"/"Right"` | 属性写入 |
| 取子树 | `c:GetChildren()` / `c:GetChild(i)` / `c:FindChild(name)` | |
| 按键 | `c:AddKeyEventListener("KeyboardMoveLeftKeyDown", fn)` | 键名形如 `Keyboard*KeyDown/Up`；`KeyboardMenuConfirmKeyDown` = 确认 |
| 指针 | `c:AddCursorEventListener(...)`（cursor/button 控件） | 光标事件还需要祖先容器 `showCursor = true` |

几何公式（`worker.js` 的 `Ae`，用于推算落点）：

```
width  = (anchorMax.x - anchorMin.x) * parentW + sizeX
height = (anchorMax.y - anchorMin.y) * parentH + sizeY
left   = parentLeft + anchorMin.x * parentW + offsetX - sizeX * pivotX
bottom = parentBottom + anchorMin.y * parentH + offsetY - sizeY * pivotY
```

本项目模板一律 `anchorMin = anchorMax`、`pivot = (0,0)`（旋转件为 `(0.5,0.5)`），
于是 `SetAnchoredPosition(x, y)` 直接就是画布左下原点坐标（千星原点在左下、Y 向上）。

## 4. 画布映射（世界 640×480、Y 向下 → 画布）

```lua
S  = math.min(CW / 640, CH / 480)   -- 等比
OX = (CW - 640 * S) / 2             -- 居中留边
OY = (CH - 480 * S) / 2
x_canvas    = OX + x * S
y_bottom    = OY + (480 - (y + h)) * S
```

`mobile-16-9`（1280×720）下 `S = 1.5`、`OX = 160`、`OY = 0`。
已用截图核对：世界 (320,376) 的灵魂落在画布 x≈640、距底≈150，与公式一致。

## 5. 坐标系：core 出口已统一为「世界绝对坐标 640×480」

> 本节曾是"两套坐标 + 适配层按命令类型平移"的记录，**已作废**：core 现已统一到单一世界绝对坐标
> （`BOX_CX, BOX_CY = 320, 308.5`，即原版默认框中心），所有命令（世界实体、HUD/菜单/子面板/攻击条/闪层）
> 一律是 640×480 绝对坐标，适配层不再做任何平移，也不做"几何自校正"。
>
> * 战斗框在**所有状态**（敌方/菜单/子面板/攻击条/结算）都是同一位置；只有脚本 `CombatZoneResize`
>   变形时是逐帧插值，适配层再加一层 `k=0.35` 平滑让过渡不跳。
> * 适配层保留一条**只告警不纠正**的 canary：框中心偏离 (320,308.5) 超过 20px、或框越出 0..640/0..480，
>   就打印 `main: WARN 战斗框坐标异常`（只打一次）并照原样绘制 —— 避免适配层把 core 的回归悄悄改好。
> * 世界实体的"框内相对坐标"只存在于 core 内部（`BOX_OFF` 是它自己的中间表示），不再泄露到适配层。

## 6. 字符串与 UTF-8

模拟器的 Lua↔JS 桥会**校验 UTF-8**：把按字节截断的中文（例如打字机效果 `s:sub(1, n)`）
写进控件 `text` 会抛 `cannot convert invalid utf8 to javascript string`，
并且**中断整个绘制帧**（画面全黑）。两处防护：

* 逻辑层按**字符**推进打字机（`utf8.offset`）；
* 适配层 `safeUtf8()` 在写入前丢弃残缺的多字节尾巴。

## 7. 其它边界

* `imageId` 只有 100001–100006 在模拟器里能预览，其余显示缺失框（真机需换成正式素材）。
* 旋转进入运行时渲染，但**点击命中仍按旋转前的轴对齐矩形**。
* 切画布 = 换真机：时间归零、历史重置；模板池会按新平台的 `transformByPlatform` 槽位重新解算。
* 存档里 `assets.scripts[].controlId` 决定脚本挂在哪个控件上；GIA 导出**不保存挂载关系**，
  真机导入后需要手动挂脚本（见 `docs/production-plan.md` 的导出步骤）。
