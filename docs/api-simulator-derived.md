# 候选 Lua API 名称清单（从模拟器运行时提取）

> **性质声明：这不是官方 API 文档，也不是规格。**
> 来源：本机已安装的 `dsh-plugin-beyond-simulator` 的运行时产物
> `D:\my-dsh\profiles\web\node_modules\dsh-plugin-beyond-simulator\dsh-plugin\dist\worker.js`
> （该文件内置 `fengari` Lua 解释器与到控件对象的绑定）。
> 提取方法：对该打包产物做正则抽取 `"([A-Za-z_][A-Za-z0-9_]{3,40})"` 后按首字母大写筛选、去重，共 565 个字符串标识符。
>
> **用途限制**：只能用于与官方文档交叉核对名称是否拼对；**不能**据此推断参数、返回值、调用时机或生命周期语义。技能明确要求"未知 API 先查文档或做单问题探针，不猜字段"。官方 2D API 文档到手后，本文件应被替换或删除。

## 1. 生命周期 / 脚本入口（疑似）

`OnInit`、`OnStart`、`OnUpdate`、`OnEnable`、`OnDisable`、`OnDestroy`、`OnLevelUpdate`

> 旁证：worker 产物里出现过字符串 `客户端控件生命周期处于创建或销毁时，无法调用DestroyClientUIControl`，说明销毁/创建期调用 API 会报错——属于待官方文档确认的 `UNKNOWN`。

## 2. 控件类型（10 类 + 引用）

`ClientUIContainerControl`、`ClientUITextBoxControl`、`ClientUITextWindowControl`、
`ClientUIImageControl`、`ClientUIPresetButtonControl`、`ClientUICursorEventAreaControl`、
`ClientUIGridScrollerControl`、`ClientUIKeyHintControl`、`ClientUIAnimationControl`、
`ClientUIFullscreenAnimationControl`、`ClientUIReferenceControl`

（技能文档写的是"创建 11 类客户端控件"，与上面 11 个名称数量吻合。）

## 3. 控件方法（Get/Set 成对出现，疑似属性读写）

- 变换：`GetAnchoredPosition` / `SetAnchoredPosition`、`GetSizeDelta` / `SetSizeDelta`、
  `GetAnchorMin` / `SetAnchorMin`、`GetAnchorMax` / `SetAnchorMax`、
  `GetPivot` / `SetPivot`、`GetLocalRotation` / `SetLocalRotation`、
  `GetLocalScale` / `SetLocalScale`
- 显隐与层级：`SetActive`、`SetVisible`、`SetAsFirstSibling`、`SetAsLastSibling`、
  `SetSiblingIndex`、`GetSiblingIndex`
- 树：`GetChild`、`GetChildren`、`FindChild`、`Root`
- 文本：`AutoWrap`、`TextHorizontalAlignment`、`TextVerticalAlignment`、`FullName`
- 图片/填充：`SetImage`、`ImageSource`、`SetFillHorizontal`、`SetFillVertical`、
  `SetFillRadial90`、`SetFillRadial180`、`SetFillRadial360`、`SetFillUnused`、
  `SetSoftEdgeWidth`、`ImageMaskSoftEdgeMode`、`ImageFillHorizontalType` 等填充类型枚举
- 动画：`PlayAnimation`、`StopAnimation`、`Tween`、`TweenSequence`、`TweenSequence`
  缓动枚举：`Linear`、`InSine/OutSine/InOutSine`、`InQuad…InOutQuint`、
  `InBack/OutBack/InOutBack`、`InBounce/OutBounce/InOutBounce`、`InElastic/OutElastic/InOutElastic`、
  `InExpo/OutExpo/InOutExpo`、`InCirc/OutCirc/InOutCirc`
- 列表/滚动（GridScroller）：`RefreshItems`、`ScrollToItemAt`、`GetItemIndex`、`GetItemSize`、
  `GetItemSpacing`、`GetContentLength`、`GetPadding`、`ScrollDirection`、`ScrollLayoutConstraint`
- 输入：`AddCursorEventListener`、`AddKeyEventListener`、`AddNavigationEventListener`
  及对应 `Remove*` / `RemoveAll*`；事件名候选 `CursorClick`、`CursorDown`、`CursorUp`、
  `CursorDrag`、`CursorBeginDrag`、`CursorEndDrag`、`CursorEnter`、`CursorExit`、`CursorEventData`、
  `SimulateCursorClick`、`Focus`、`LostFocus`、`Confirm`、`Cancel`、`DropKey`、`InteractKey`
- 手柄导航：`GetControllerNavigation` / `SetControllerNavigation`、`NearestControl`、
  `CONTROLLER_MOBILE`、`CONTROLLER_CONSOLE`、`KEYBOARD`、`TOUCHSCREEN`、`KeyboardAndMouse`、`MobileController`
- 脚本查询：`GetScript`、`GetScripts`、`GetScriptByPath`、`Script`、`Prefab`、`PrefabId`
- 排序/锚点枚举：`TopLeft`、`TopRight`、`BottomLeft`、`BottomRight`、`Left`、`Right`、`Top`、`Bottom`、
  `Middle`、`Stretch`、`Fixed`、`Percentage`、`Pixel`、`Horizontal`、`Vertical`、`Normal`

## 4. 服务端信号（客户端 → 服务端）

`ServerSignal`，带类型化 `Add*` 方法：
`AddParam`、`AddInt`、`AddIntList`、`AddFloat`、`AddFloatList`、`AddString`、`AddStringList`、
`AddVector3`、`AddVector3List`、`AddBool`、`AddBoolList`、`AddGuid`、`AddGuidList`、
`AddEntity`、`AddEntityList`、`AddPrefabId`、`AddPrefabIdList`、`AddConfigId`、`AddConfigIdList`，
以及 `SendSignal`。类型枚举：`Int/Float/String/Bool/Guid/Entity/PrefabId/ConfigId` 及其 `*List`、
`Vector3`、`Vector3List`、`Dict`、`Struct`、`List`、`EnumItem`、`EnumType`、`LanguageType`。

## 5. 实体 / 变量作用域（服务端薄模拟侧）

`PlayerSelf`、`AvatarSelf`、`Level`、`AllPlayers`；自定义变量类型枚举 `Currency`、`Equipment`、`Item`、
`Skill`、`UnitStatus`、`Faction`、`Control`、`Basic`、`Classic`、`Beyond`、`StageMode`。

## 6. 平台 / 输入键名候选

`JumpKey`、`NormalAttackKey`、`CharacterSkill1Key`…`CharacterSkill4Key`、`SprintKey`、
`SwitchToWalkOrRunKey`、`OpenShortcutWheelKey`、`MenuConfirmKey`、`MenuBackKey`、
`MoveForwardKey`、`MoveBackwardKey`、`MoveLeftKey`、`MoveRightKey`、
`LeftStickUp/Down/Left/Right`、`RightStickUp/Down/Left/Right`。

多语言枚举：`LanguageChs/Cht/Eng/Jpn/Kor/Deu/Fra/Rus/Spa/Por/Ita/Tha/Vie/Ind/Tur/None`。

## 7. 尚未确认的关键项（必须查官方文档或做探针）

- 全局入口表名与全局函数（如画布尺寸、创建/销毁控件、取自身玩家等）在上面的抽取里**没有出现**，说明它们的注册路径不同——不要凭记忆猜。
- 各方法的参数个数与类型（worker 里存在"参数个数不符就报错"的检查，写错会直接运行时出错）。
- 生命周期回调相对帧/动画的时序，以及销毁期可调用的 API 白名单。
- 服务端信号的注册与回传链路（模拟器侧只能模拟变量与信号，不含官方节点图）。
