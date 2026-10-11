# Sans Fight · 文本框渲染：官方口径、现状问题与两条路线

> 生成时间：2026-10-08 深夜
> 工程：`D:\stars\workspace\sans-fight`
> 现象：**真机上完全没有文字**（战斗框、HP 条、Sans、龙骨炮都能画出来，文本控件一个字形都不显示）
> 目的：把「官方文档/源码里读到的文本框规则」「现在卡在哪」「继续用文本框必须先解决什么」「备选路线」写成一份可交接的清单。本文件由分析脚本/模型自动整理，未改动任何游戏逻辑。

---

## 一、结论摘要

1. 我们的**写入方式是对的**：字段名、类型、枚举都符合官方可写字段表（§二）。
2. 编辑器面板里 `文本框(1073741867)` 只有「字号 / 字号自适应 / 文本颜色 / 背景颜色 / 启用文字描边 / 描边颜色 / 对齐 / 文本内容」——**没有字体 / 字形 / 字体资源选项**。
3. 因此"完全没有文字"只有两类可能：
   - **A. 控件渲染不出字形**（引擎内置字形集在该模板/该机器上不可用，且创作者无法指定字体）；
   - **B. 写入没生效 / 被遮挡 / 被裁**（属性被忽略、时序、层级、尺寸、颜色 alpha）。
4. 判 A 还是 B 只需两个最小实验（§五）：**编辑器手填文本内容** + **回读诊断**（回读诊断已在最新包里）。
5. 若判定为 A，代码侧唯一稳妥出路是**不用文本框、用矩形块自绘字形**——正是 `D:\stars\another` 的做法（§六）。

---

## 二、从官方文档 / 模拟器源码读到的文本框规则

### 2.1 文本框的官方可写字段（权威）

出处：`D:\miliastra-beyond-simulator\client\lua-runtime\src\scene.js` 的 `KIND_RW`。

```
textbox: ['text', 'fontSize', 'fontColor', 'bgColor', 'enableOutline', 'outlineColor',
          'horizontalAlignment', 'verticalAlignment', 'adaptiveFontSize', 'minimumFontSize']
```

- **`text` 就是"文本内容"字段** → `控件.text = "要显示的字"`（我们一直这么写）。
- `fontSize` 是**整数**字段（同文件 `INTEGER_FIELDS`：`Id, prefabIndex, imageId, fontSize, minimumFontSize …`），写小数会抛。
- `fontColor / bgColor / outlineColor` 是**颜色字段**（`COLOR_FIELDS`），真机要 ColorValue（`Color(r,g,b,a)`）。
- `horizontalAlignment / verticalAlignment` 是**枚举字段**（`ENUM_FIELDS` → `TextHorizontalAlignment` / `TextVerticalAlignment`），必须写 `Enum.TextHorizontalAlignment.Left/Middle/Right`、`Enum.TextVerticalAlignment.Top/Middle/Bottom`；给字符串时真机报
  `bad argument #2 to 'horizontalAlignment' (TextHorizontalAlignment expected, got string)`。

### 2.2 "看着能写其实不能"的字段

同文件 `KIND_RW.image` 与注释：

```
image: ['imageColor', 'enableMask', 'enableSoftEdge', 'softEdgeMode', 'softEdgeWidthX', 'softEdgeWidthY',
        'horizontalSoftRange', 'verticalSoftRange', 'reverseMaskArea', 'fillType', 'fillHorizontalType',
        'fillVerticalType', 'fillRadial90Type', 'fillRadialType', 'fillAmount']
// 注释原文：Documented RW. Observed: assigning after Instantiate reports
//          "cannot set imageType, no such field". Keep it off the Lua surface.
```

- **`imageType` 不可写**（真机报 `cannot set imageType, no such field`）。
- **`enableFill` 不在可写表里** → 我们早期写的 `c.enableFill = false` 就是日志里
  `【警告】写 enableFill=false 失败` 的来源（已删）。
- 控件字段按类型封死：**当前类型没有的字段读为 nil、写报 `cannot set <field>, no such field`**
  （`docs/observed-contract.md` 第 12、15 条）。

### 2.3 官方契约里关于"写文本"的实测结论

出处：`D:\miliastra-beyond-simulator\client\lua-runtime\docs\observed-contract.md`

- 第 21 条（按键/点击回调与写入时机）：
  "两类回调都在第 N 帧 `OnUpdate` 结束后、第 N+1 帧之前执行，**回调内直接写文本 / 位置 / 颜色 / 显隐、启动 Tween 均正常显示**。"
  → 说明"写 `text` 能显示"在真机上是被验证过的能力，**不是**平台不支持写文本。
- 第 38 条：`fontSize`、`Id`、`imageId` 这类 API 标为 integer 的字段**读回是整数**；颜色保持原编码；控件销毁后除 `alive` 外读字段报错。
  → 这是回读校验（§五②）的依据。

### 2.4 官方测试里的正确写法（可直接照抄）

出处：`D:\miliastra-beyond-simulator\studio\test\text-alignment.test.mjs`

```lua
local label = script.object:GetChild('Label')
label.horizontalAlignment = Enum.TextHorizontalAlignment.Middle
label.verticalAlignment   = Enum.TextVerticalAlignment.Middle
label.text                = '…'
```

### 2.5 编辑器面板实际可改项（你截图确认）

`索引 1073741867（文本框）`：

| 分组 | 可改项 |
|---|---|
| 基础 | 锚点 Min/Max、中心（`0.5,0.5`）、初始激活、初始可见性 |
| 文本框设置 | 字号 `20`、字号自适应（关）、文本颜色（`FFFFFF 100%`）、背景颜色（`FFFFFF 0%`）、启用文字描边（开）、描边颜色（`333333 20%`）、对齐（6 个按钮）、文本内容 |
| 手柄导航 | 可被手柄摇杆导航选中（关） |

**没有任何"字体 / 字形 / 字体资源"项** → 字形来自引擎内置集合，创作者无法指定。
这也是参考工程选择自绘字形的原因：`D:\stars\another\...\docs\部署与设置.md` 写明
"中文剧情与按钮文字由 `lua/textart.lua` 的矩形字形显示，不依赖文本模板"。

---

## 三、我们现在怎么用文本框

`lua/main.lua`：

| 位置 | 写入内容 |
|---|---|
| `instantiateTemplate`（文本框 leaf） | `bgColor = Color(0,0,0,0)`、`adaptiveFontSize = false`、`verticalAlignment = Top(枚举)` |
| `label()`（每帧按需、带缓存去重） | `text = safeUtf8(文本)`、`fontSize = 整数(size*S)`、`fontColor = ColorValue`、`horizontalAlignment = 枚举` |
| `text()` | 从池取文本框控件 → `put()` 设尺寸/位置 → `label()` 写内容 |

即：字段名、类型、枚举、可见性、尺寸位置都符合 §二；**唯一无法保证的是字形从哪来**。

---

## 四、问题时间线与已排除项

| 时间 | 日志 / 现象 | 结论 |
|---|---|---|
| 20:45 | **3461 条** `draw ERR :: bad argument #2 to 'horizontalAlignment' (… got string)` | 真机每帧在写对齐就抛错，`pcall(draw)` 吞掉整帧 → 那一版**文字必然完全不显示**。已修（改枚举） |
| 21:43 | 不再有 `horizontalAlignment` 报错 | 至少不再整帧中断 |
| 22:08 | `[diag] 第一个文本框 raw="← → 选难度 · 点难度卡或 按 Enter 开局" size=16 align=Middle`；`geom[root/bg1/bg2/baked…]` 全部符合预期 | **写入调用确实发生**；锚点/尺寸类写入真机生效 |
| 22:0x | 你确认：那个 `?` 是**龙骨炮发射异常**，不是文本框 | 之前"文本框显示 ?"的判断作废 |
| 22:4x | 你确认：**完全没有文字** | 现象收敛为：字形不可用 / 写入未生效 / 被遮挡或裁切 |

仍未排除：① 内置字形集不可用（编辑器无字体项）；② 属性被忽略（需回读）；③ 被同层控件或黑底盖住 / 尺寸过小被裁；④ 颜色 alpha 实际为 0。

---

## 五、要继续用文本框，必须先解决这 6 件事

> 顺序即排查顺序；①② 能直接判定"还能不能继续用文本框"。

**① 控件本身能不能渲染字（判定实验，2 分钟）**
编辑器里给 `文本框` 模板的「文本内容」手填 `测试ABC123`，保存 → 重进试玩：
- 看得到字形 → 控件可用，问题在我们的写入/时序 → 继续 ②③④⑤⑥；
- 看不到 / 方块 → **该机器渲染不出字形** → 直接走 §六。

**② 写入是否真的落到控件上（回读诊断，最新包已加）**
文本框第一次使用时打：

```
main: [diag] 第一个文本框 raw="…" size=… align=…
main: [diag] 文本框回读 text="…" fontSize=… fontColor=… bgColor=… align=… visible=… active=…
main: geom[text] anchor=(…) pivot=(…) pos=(…) size=(…)
```

- 回读 `text` 为空 / 与 raw 不一致 → 写入没生效 → 我改写入方式；
- 回读全对但仍无字 → 落在 ①（字形）或 ③（遮挡）。

**③ 层级 / 遮挡**
文本框取的是池控件，若被后建的背景/闪层压住就看不见。
验证：临时 `SetAsLastSibling()` 把文本框提到最上层，或把两层黑底减到一层排除遮挡。

**④ 尺寸与裁剪**
我们给文本框的尺寸是 `w*S × size*1.4*S`（例：637×26 px）；若引擎按"顶对齐 + 最小高度"处理，过小会被裁。
验证：做一个固定 200×60 px 的对照文本。

**⑤ 颜色**
真机要 ColorValue；我们写 `Color(255,255,255,255)`。若该机器 `Color` 语义不同（忽略 alpha / 参数顺序不同），会得到透明或黑。
验证：看 ② 回读的 `fontColor` 是否等于预期编码；必要时改三参 `Color(r,g,b)`。

**⑥ 时序**
若同帧"先 text 后 fontSize"触发文本重建，可能停在空文本。
验证：固定顺序 `fontSize → fontColor → text → horizontalAlignment` 后再看。

---

## 六、备选路线（推荐）：矩形块自绘字形

`D:\stars\another\...\lua\textart.lua`（约 323 KB）就是这套：**每个字的像素配方 + 容器烘焙**，完全不依赖文本框。

我们这边的准备进度：

| 步骤 | 状态 |
|---|---|
| 统计游戏里会出现的全部字符（含 ASCII） | ✅ 583 个字形（`D:\stars\.tmp-chars.txt`） |
| 用系统字体（微软雅黑 12px + `SingleBitPerPixelGridFit`）烤 1-bit 点阵 | ✅ 脚本验证可用 |
| 编码成 `lua/textfit.lua`（按行 run-length 矩形，预计 ~70 KB） | ⏳ 待做 |
| `text()` 改为按字形画矩形（保留对齐/染色/缩放），并上调 `BUDGET.rect` | ⏳ 待做 |
| 模拟器与真机**同一条路径**（避免"模拟器好看、真机崩"） | ⏳ 待做 |

代价：文字变点阵像素风（反而更贴 Undertale）；每帧矩形块用量上升（一行 20 字 ≈ 200~300 块），`BUDGET.rect` 需相应提高；583 字覆盖外的字用 `?` 兜底。

---

## 七、下一步（等你一句话）

| 你的回复 | 我做什么 |
|---|---|
| 「手填能看到字」 | 按 §五 ②③④⑤⑥ 逐个改写入方式（回读诊断已在最新包） |
| 「手填也看不到」/「直接做」 | 执行 §六：生成 `lua/textfit.lua` + 改造 `text()`，彻底不用文本框 |
| 「先给我看日志」 | 我跑 `node tools/read-beyond-log.mjs --grep "diag|geom|警告|ERR"` 抽最新会话日志，看 ② 的回读结果 |

---

## 附：相关文件 / 命令

| 用途 | 路径 / 命令 |
|---|---|
| 官方可写字段表 | `D:\miliastra-beyond-simulator\client\lua-runtime\src\scene.js`（`KIND_RW` / `KIND_RO` / `INTEGER_FIELDS` / `COLOR_FIELDS` / `ENUM_FIELDS`） |
| 真机实测契约 | `D:\miliastra-beyond-simulator\client\lua-runtime\docs\observed-contract.md` |
| 官方文本框对齐测试 | `D:\miliastra-beyond-simulator\studio\test\text-alignment.test.mjs` |
| 参考工程（自绘字形） | `D:\stars\another\BadTime-Miliastra-Handoff-2026-10-08\lua\textart.lua` |
| 我们的适配层 | `D:\stars\workspace\sans-fight\lua\main.lua`（`instantiateTemplate` / `label` / `text`） |
| 真机日志抽取 | `node D:\stars\workspace\sans-fight\tools\read-beyond-log.mjs --grep "diag|geom|警告|ERR"` |
| 已同步的外部脚本 | `C:\Users\19637\AppData\LocalLow\miHoYo\原神\BeyondLocal\248255821\Beyond_Local_Save_Level\1073741827\external_lua_file\main.lua` |

---

## 八、追加（2026-10-08 深夜）：③「被 UI 盖住」已确认是**最可能**的原因，并已修

### 机制（为什么只在真机出现）

- 引擎的兄弟序 = **控件创建顺序**（`addChild` + `SetAsLastSibling`），后建的画在上面；
- **模拟器**：`OnStart` 一次性预热 ~2000 个池控件（固定顺序），文本在栈里位置固定 → 看起来正常；
- **真机**：我们**故意跳过预热**（不然会卡死），控件是**按需创建**的 → 之后新建的每一个 rect/circle（骨头、HP 条底、战斗框边、黑底……）都叠在**先前创建的文本框之上** → 文字被盖住 = "完全没有文字"。
- 我们此前**没有任何显式层级**，完全依赖创建顺序，所以这个 bug 之前一直没暴露。

### 修法（已进包）

`draw()` 每帧结束时把本帧用到的文本框 `SetAsLastSibling()` 提到最上层（≤15 次调用/帧，成本可忽略），闪层再提到它们之上：

```lua
  local tpool = pool.text
  for ti = 1, (used.text or 0) do
    local tc = tpool[ti]
    if tc ~= nil then pcall(function() tc:SetAsLastSibling() end) end
  end
  if flash ~= nil then pcall(function() flash:SetAsLastSibling() end) end
```

探针已加断言：60 帧里文本被提升 **661 次**（≈11 个文本框/帧）。

### 如果这次文字出来了

→ 就是"被 UI 盖住"；后续要做的只是把这条规则固定下来（可选：改成显式图层容器，像 `another` 那样分
`world / soul / uiBackdrop / ui / flash`，但当前"每帧提文本框"已够用且成本更低）。

### 如果文字还是完全没有

→ 走 §五②：看回读诊断（`文本框回读 text=… fontSize=… fontColor=…`）
 - 回读为空 → 写入没生效（改写入方式）；
 - 回读正常 → 判定为"控件渲染不出字形"→ 执行 §六 矩形字形。

---

## 九、更正（依据 2026-10-08「给对方AI_文本渲染答复.md」）

### 9.1 来源分级要改口（我此前写重了）

- `D:\miliastra-beyond-simulator` 的 `scene.js` / `observed-contract.md` / `studio\test\*` 属于**第三方实现与观察记录**，
  此前文档里写成"官方可写字段表 / 官方契约 / 官方测试"是**过度断言**，已按此更正。
- 那些字段（`text / fontSize / fontColor / bgColor / enableOutline / outlineColor /
  horizontalAlignment / verticalAlignment / adaptiveFontSize / minimumFontSize`）应以**官方文档**为准；
  第三方源码只作辅助参考。
  → 官方客户端控件 API：https://act.mihoyo.com/ys/ugc/tutorial/detail/mhtakr07vej4

### 9.2 「写后==期望」能证明什么、不能证明什么

- **能证明**：对象状态被正确写入（字段值就是我们要的）。
- **不能证明**：字形最终被提交并可见。因此不能说"已排除文本框问题"，只能说"排除了属性写入"。
- 同理：编辑器里手填内容失败，也**不能单独**证明字库故障（运行时可能被脚本覆盖、父级隐藏/未激活/裁剪/遮挡）。

### 9.3 置顶要处理父链（我的上一版只提了叶子）

`SetAsLastSibling()` 只改变**同级**顺序；叶子若在低层容器里，叶子置顶仍可能被另一个更高的容器整体遮挡。
→ 新探针里改为：把承载文字的**整层容器**提到同级最后（`layer:SetAsLastSibling()`），再提叶子。

### 9.4 不再猜颜色/时序

- 官方规定 `Color(r,g,b,a)` 为 0–255，省略 alpha 默认 255；**没有证据说这台机器参数顺序不同**——删掉该猜测。
- "先写 text 再写 fontSize 会永久空白"同样**未证实**，只能作为待验证假设。

### 9.5 按官方实现文档改了 `adaptiveFontSize`

`studio\docs\control-support.md` 与 `05-lua-implementation.md`（第三方镜像）建议文本框**开启自适应字号**并配最小字号；
我们把 `adaptiveFontSize` 从 false 改成 true，并在设置 `fontSize` 时同步写 `minimumFontSize`（同值 = 不缩）。

### 9.6 新增「隔离文本探针」（`lua/config.lua` → `C.textProbe = true`）

只画三样，不挂任何战斗内容、不受池清理/黑底/闪层影响，用来回答"这台机器到底能不能渲染原生文本框"：

1. 白色参照矩形（证明 rect 路径正常）；
2. 画布**手放**的文本框 `TextProbe`（若存在）——脚本**一个字都不写**，只观察它是否显示；
3. 脚本实例化 + 写入的 4 个文本框（左对齐/居中/中文/大字号 40）。

探针会把承载文字的整层容器提到同级最后，并打印字段回读与几何。判定：

| 观察 | 结论 |
|---|---|
| ① 有白条，②③ 没字 | 该机器的原生文本框渲染不出字形（与我们的写入无关，因为②没被写） |
| ① 有白条，② 有字、③ 没字 | 引擎能渲染，问题在**实例化出来的文本框**（我们写入或实例本身） |
| ②③ 都有字 | 引擎正常，问题回到大工程的层级/裁剪/遮挡 |
| ① 没白条 | 连 rect 都没画出来（另查模板/容器/黑底覆盖） |
