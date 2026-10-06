# 千星客户端脚本 2D/Lua API（实测版）

> **来源**：在千星沙箱 UI 模拟器里跑**单问题探针**得到的真实运行时结果，不是猜测、不是从 3D 节点经验推断。
> 探针脚本：`probe.lua`（同目录留有原始版本）。执行记录见 `../records/playtest.md`。
> 官方《综合指南》目前没有这部分条目（按「客户端脚本 / 客户端控件 / Lua」检索为 0 篇），所以本文件是**当前唯一可用的接口依据**。
> 标记：✅ = 已在模拟器里实测到；❓ = 尚未验证，写代码前必须再探针。

## 1. 全局环境 ✅

`_G` 共 32 个键：`Color`(table)、`Enum`(table)、`_G`、`game`(table)、`script`(userdata)、`require`(function)、
`typeof`(function)、`print`/`printerr`、`math`、`string`、`table`、`utf8`、`os`(table)、`debug`(table)、
`assert`/`error`/`pcall`/`xpcall`/`select`/`next`/`pairs`/`ipairs`/`rawequal`/`rawget`/`rawset`/`rawlen`/
`getmetatable`/`setmetatable`/`tonumber`/`tostring`/`type`。

- `_VERSION` 为 **nil**（沙箱裁剪过，别依赖它判断 Lua 版本）。
- `string.dump/pack/unpack`、`io`、`os.execute/getenv/…`、`package`、`load/loadfile/dofile`、`collectgarbage`、
  `coroutine`、`fengari` 均被移除 → **不能用协程、不能用 io/os**。

## 2. 生命周期：**全局函数** ✅（不是 `script` 的字段）

| 钩子 | 实测 | 说明 |
|---|---|---|
| `OnInit()` | ✅ 触发 | 脚本初始化 |
| `OnEnable()` | ✅ 触发 | 紧随 OnInit |
| `OnStart()` | ✅ 触发 | 紧随 OnEnable |
| **`OnLevelUpdate(dt)`** | ✅ **每帧触发**（实测每帧 0.0333s，`step 0.05` 时收到 0.05） | **游戏主循环就挂这里**；`dt` 是秒 |
| `OnDisable()` / `OnDestroy()` | ❓ 未验证 | 名字来自实现产物，需探针确认 |

- 写法：`function OnInit() ... end`（全局），**不是** `script.OnInit = ...`——`script` 是 userdata，
  写不存在的字段会报 `cannot set OnUpdate, no such field` 并**中断整个脚本**（实测踩到）。
- 脚本顶层代码在初始化时执行一次（探针的 `print` 在 `time=0` 就出现）。

## 3. `game` 表（26 个函数）✅

```
DestroyClientUIControl   FindClientUIRoot        GetClientUIControl    GetClientUIRoots
GetControllerFocus       GetControllerLeftStickAxis  GetControllerRightStickAxis
GetCursorUIPos           GetDevice                GetGlobalCustomVariableValue
GetLanguageType          GetStageMode             GetText
GetUICanvasSize          InstantiateClientUIControl   IsAudioAlive
IsLevelTimePaused        IsTestPlay               PauseLevelTime
PlayAudio2D              PrintClientUITree        ServerSignal
SetControllerFocus       StopAudio                Tween        TweenSequence
```

要点（部分已实测）：
- `game.PrintClientUITree()` ✅ 打印整棵控件树 + **运行时 Id**（调试神器）。
- `game.GetClientUIControl(runtimeId)` ✅ 返回控件对象（userdata）。
- `game.FindClientUIRoot(...)` ✅ 可调用，但 `FindClientUIRoot(1)` 返回 **nil**（❓ 参数语义待定，可能需要玩家侧参数）。
- `game.ServerSignal` ✅ 存在，配合 `AddInt/AddFloat/AddString/AddBool/…` 类型化参数发服务端信号。
- `game.GetGlobalCustomVariableValue` / `GetText` / `GetLanguageType` / `GetStageMode` / `IsTestPlay` 等 ❓ 参数待探针。
- `game.Tween` / `TweenSequence` ✅ 存在（缓动枚举见 worker 抽取值：`InSine/OutBounce/InOutElastic` 等全套）。

## 4. 控件：11 类与运行时 Id ✅

`game.PrintClientUITree()` 实测输出（**Id 是按实例分配的，不是固定值**）：

| Id | 名称 | 类型 |
|---|---|---|
| 1 | 容器节点 | `ClientUIContainerControl` |
| 2 | 文本框 | `ClientUITextBoxControl` |
| 3 | 光标检测区域 | `ClientUICursorEventAreaControl` |
| 4 | 模板引用控件 | `ClientUIReferenceControl` |
| 5 | 网格视窗 | `ClientUIGridScrollerControl` |
| 6 | 预设按钮 | `ClientUIPresetButtonControl` |
| 7 | 文本视窗 | `ClientUITextWindowControl` |
| 8 | 按键提示 | `ClientUIKeyHintControl` |
| 9 | 图片 | `ClientUIImageControl` |
| 10 | 界面动效 | `ClientUIAnimationControl` |
| 11 | 全屏动效 | `ClientUIFullscreenAnimationControl` |

控件对象是 **userdata**：`Id` 是 **number 字段**（✅ 实测）；元表只有
`__eq/__index(function)/__name/__newindex` → **无法遍历方法名**，只能按名字访问（不存在则为 `nil`）。

### 已实测存在的控件方法 ✅（在 `ClientUIImageControl` 上验证）

`SetVisible`、`SetActive`、`SetAnchoredPosition`、`GetAnchoredPosition`、`SetSizeDelta`、`GetSizeDelta`、
`SetImage`、`AddKeyEventListener`、`SetAnchorMin`、`SetPivot`、`SetSiblingIndex`

### 实测在该控件上为 `nil`（= 类型专属，需在对应控件上再验）❓

`SetFillAmount`（→ 进度条）、`PlayAnimation`（→ 界面动效）、`AddCursorEventListener`（→ 光标检测区域）、
`SetText` / `GetText`（→ 文本框 / 文本视窗）

### 候选方法名（来自模拟器运行时字符串，**未逐个验证**）❓

变换：`GetAnchorMax` `GetPivot` `GetLocalScale` `SetLocalScale` `GetLocalRotation` `SetLocalRotation`
层级/树：`GetChild` `GetChildren` `FindChild` `GetSiblingIndex` `SetAsFirstSibling` `SetAsLastSibling`
显隐：`SetVisible`（已验证）
文本：`AutoWrap` `TextHorizontalAlignment` `TextVerticalAlignment`
填充：`SetFillHorizontal` `SetFillVertical` `SetFillRadial90/180/360` `SetFillUnused` `SetSoftEdgeWidth`
动画：`PlayAnimation` `StopAnimation` `Tween` `TweenSequence`
事件：`AddCursorEventListener` `AddKeyEventListener` `AddNavigationEventListener` + 对应 `Remove*`/`RemoveAll*`
列表：`RefreshItems` `ScrollToItemAt` `GetItemIndex` `GetItemSize` `GetItemSpacing` `GetContentLength`
手柄：`GetControllerNavigation` `SetControllerNavigation` `NearestControl`

> **纪律**：写任何未验证的方法前，先用「一次探针一条问题」的方式确认，**不要凭名字猜参数**。
> 未知参数个数会被运行时拒绝并报 `bad argument count to 'X' (N expected, got M)`（✅ 实测到该错误形态）。

## 5. 服务端薄模拟（非官方节点图）✅

- 变量作用域：`Level` / `PlayerSelf` / `AvatarSelf` / `Player1`–`Player8` / `Avatar1`–`Avatar8`。
- 未定义变量的 Get 返回 `nil`。
- `ServerSignal`：`AddParam/AddInt/AddIntList/AddFloat/AddFloatList/AddString/AddStringList/AddVector3/AddVector3List/AddBool/AddBoolList/AddGuid/AddGuidList/AddEntity/AddEntityList/AddPrefabId/AddPrefabIdList/AddConfigId/AddConfigIdList` + `SendSignal()`。
- 服务端逻辑规则（模拟器存档格式，**不是**官方节点图）：`setServerLogic` 的 `rules[]`，按信号名监听，动作 `setCustomVariable` / `sendClientScriptSignal`，参数可用 `{"fromSignalParam": N}` 引用入参。

## 6. 输入事件（已核实，2026-10-05）

### 指针 / 触摸 ✅

- 事件回调拿到的是 **画布坐标**，原点**左下、Y 向上**（与控件盒子同一套）。
  出处：试玩页 `dist/play-renderer.js` 的 `hv(){y:(t.bottom-i.clientY)*…}`（DOM 的 clientY 向下增大）；
  引擎盒子 `Ne()` 的 `bottom = parentBottom + anchorMinY*H + anchoredPositionY - sizeY*pivotY`。
- 世界是 640×480、**Y 向下** → 适配层换算 `y_world = 480 - (y_canvas - OY)/S`，**必须翻且只翻一次**。
  漏翻的表现是「点底部按钮没反应」+「摇杆上下颠倒」（两者是同一个 bug）。
- 光标事件需要祖先容器 `showCursor = true` 才会派发（`cursorEventsEnabled`）；本项目存档里 `n1` 已开。

### 键盘 ✅（枚举 + 宿主映射，详见 `docs/plugin-keymap.md`）

- 引擎派发的事件名形如 `Keyboard<键码名><Down|Up>`，键码枚举来自 `worker.js` 的 `KeyboardKeyCode`：
  `MoveForwardKey / MoveBackwardKey / MoveLeftKey / MoveRightKey / SprintKey / JumpKey / DropKey /
   OpenShortcutWheelKey / InteractKey / NormalAttackKey / CharacterSkill1..4Key / CraftspersonKey1..43 / None`。
- 键盘枚举里**没有** `MenuConfirmKey` / `MenuBackKey`（只有手柄枚举有 `ControllerMenuConfirmKey*`）；
  `KeyboardMenuConfirmKeyDown` 只由**试玩页的物理键映射**产生（Enter / 小键盘回车 / 空格 / Z 都归到它）。
- 监听前提：控件 alive 且 `activeInHierarchy`，按**精确同名**匹配即可；
  不需要 `SetControllerFocus` / `canControllerFocus`，也不读 `disableKeyEventPassthrough`。

## 7. 写代码时的硬约束（来自技能 + 实测）

1. **布局基准是 `mobile-16-9`（1280×720）整屏可见**；PC 用固定设计板等比放大或留边，禁止 PC 铺满后在手机裁切。
2. 原点**左下、Y 向上**；锚点相对父矩形 0–1。
3. 脚本挂在**客户端控件**上（服务端「客户端控件容器」本身不挂脚本）；`mountTargets` 里同名 Id 会同时出现在两类资产下，挂载时要确认 `assetType`。
4. `imageId` 只有 `100001–100006` 在模拟器里能预览，其余显示缺失框（记 `targetId`，真机核验）。
5. 旋转进入运行时，但点击命中仍按**旋转前**的轴对齐矩形计算。
6. 切画布 = 换真机：时间归零、历史重置；用例不跨设备。
