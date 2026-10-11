# 三个问题：技术分析与可行性方案（附 main 备份说明）

- **工作区（沙箱）**：`D:\stars\workspace\sans-fight`
- **日期**：2026-10-11
- **备份**：✅ 已把沙箱 main 文件备份到 **`D:\stars\main_备份_2026-10-11.lua`**（原文 + 顶部【重点标注】注释块：三个问题各自相关的函数与行号；未改任何代码）

---

## 备份里的「重点标注」（速查）

| 问题 | 相关位置（备份文件行号 = 原文行号 + 27 行表头） |
|---|---|
| ① PC 鼠标点选 | `bindPointer()` ~L2109；`onPointer()` ~L2093；`handleClick()` ~L2211；`menuButtonRect/menuHitTest` ~L409/427；`M.OnLevelUpdate` 的 confirm 回退 ~L2772；设备分流 `detectDevice()` ~L332 / `bindKeys+bindPointer` ~L2611-2618 |
| ② 移动端摇杆 | `joy` 表 ~L246；`joyVector()` ~L268；`inJoyZone()` ~L280；`CursorDown` 起摇杆 ~L2129-2139；`applyPointer()` ~L2356 |
| ③ 升起骨（骨刺）判定 | main 侧只画：`drawStab()` ~L1576；**判定在 `core.lua`**：`World:stabRect()` / `Game:update` 的 `bn.stab` 分支 |

---

# 问题 1：PC 鼠标只能"确认"，不能直接点选

## 1.1 现状（代码事实）

- 指针链路：`bindPointer()` 注册 `CursorDown/Drag/Up/Click`（**PC 与触摸都注册**，`main.lua:2611-2618`）→
  `CursorUp` 里若没拖动过（`ptr.moved == false`）就 `onPointer(e, true, 'CursorUp')` →
  `handleClick(px, py)`（`main.lua:2211`）按坐标命中：**标题难度卡 / 子面板行 / 战斗菜单四选项 / 攻击条**，PC 分支是"**一击即选**"（触摸才是两段式确认）。
- 也就是说：**代码本来就支持"点哪选哪"**；`docs/api-2d-lua.md:115` 也指出过"点底部按钮没反应"是坐标翻转 bug（已修）。
- 模拟器实测：用**正确的画布坐标**（注意指针 y 是**自下而上**：`canvasY = (480 - worldY) × S`）点击「道具」可以开出道具面板；若 y 用错（自上而下），`handleClick` 收不到命中 → 表现就是"点了没反应/像只按了确认"。

## 1.2 真机上"只有确认"的可能原因（按可能性排序）

| # | 原因 | 判据 / 验证方法 |
|---|---|---|
| A | **平台把鼠标点击直接映射成 `KeyboardMenuConfirmKey`**，而指针坐标事件没到 `cursorArea` | 真机日志看有没有 `main: 游标 CursorClick x=… y=…`；只有 confirm 的日志而无游标日志 = 命中本因 |
| B | 祖先容器 `showCursor=false` → 光标事件不派发（`docs/plugin-keymap.md:143`、`api-2d-lua.md:116`：本存档 `n1` 已开 → 若换画布/模板需复核） | 同上：无游标日志 |
| C | 命中矩形与"实际画出来的按钮"不一致（菜单行 y 被 `menuRowY()` 改写、或 `lastMenu` 是上一帧的陈旧命令） | 模拟器里点按钮四角，看是否四角都能命中 |
| D | 玩家在 PC 上"拖动"了鼠标（超过 12px）→ `ptr.moved=true` → 该次点按被丢弃（`L2157/2182`） | 日志 `moved=true` |

## 1.3 解决法案（推荐 A1+A2 一起做）

**A1（必做，PC 端"悬停即选中 + 点击即确认"）**
- 新增 `CursorMove`（鼠标移动）监听：把 `toWorld()` 后的坐标喂给 `handleClick` 的**只选中不确认**版本（例如 `handleHover(x,y)`：命中菜单行/子面板行就 `state:menuMove/subMove` 到该项，命中标题卡就 `titleMove`）；
- 这样鼠标移到「道具」上时选中框就跟着走，点一下即生效 —— 完全不需要 WASD。

**A2（保底，用"确认 + 指针位置"反查命中）**
- 平台若只给 `confirm`，则在 `M.OnLevelUpdate` 的 `input.confirm` 处理前，先读一次指针位置
  （API 表里有 **`GetCursorUIPos`**，见 `docs/api-2d-lua.md:38`）→ 把它交给 `handleClick` 做命中：
  命中到哪一项就选哪一项，**没命中再走原来的"确认"语义**；
- 这条不依赖 Cursor 事件是否派发，**是"只有确认"这个现象的直接兜底**。

**A3（体验润色，可选）**
- 鼠标悬停时给当前项加"高亮"（对应原版 `Highlight` 贴图，见《四选项菜单UI》文档）；
- 命中矩形在按钮外再放宽 4~8px（现在上下已有 `-4/+8`，左右可各加 4px），提高"点得中"的概率。

## 1.4 可行性

| 项 | 结论 |
|---|---|
| 需要改的文件 | 只改 `lua/main.lua`（输入层），**core 不用动** |
| 依赖 API | `AddCursorEventListener`（已有）、`GetCursorUIPos`（已确认存在） |
| 风险 | 低：`handleClick` 已是"命中才消费"，新增的 hover 只改 `menuIndex/subIndex`，不推进相位 |
| 回归 | `_input`（241 条）/`_tap`（40 条，PC 单击菜单第 3 项 → `sub='item'`）必须继续过；新增断言：hover 命中第 3 项后 `sub` 打开的是道具 |

---

# 问题 2：移动端摇杆是"浮动摇杆"，要改成**固定摇杆**（对齐原神预设位置）

## 2.1 现状（代码事实）

```lua
local JOY_R, JOY_DEAD = 46, 9                 -- 半径 / 像素死区
local JOY_HOME_X, JOY_HOME_Y = 84, 392        -- 世界坐标（y 向下）= 左下角默认位
local joy = { active=false, bx=JOY_HOME_X, by=JOY_HOME_Y, ... }
...
-- CursorDown（触摸）：
if state.state=='enemy' and inJoyZone(twx) and not uiHit(twx,twy) then
  joy.active = true
  joy.bx, joy.by = twx, twy                   -- ← 基准点跟着手指跑 = 浮动摇杆
end
-- inJoyZone(wx) = wx < W*0.55                 -- 左半屏按下都能起摇杆
```

- **问题**：每次按下位置不同 → 摇杆中心漂移，方向手感每次都不一样（用户说的"非固定摇杆，体验差"）。

## 2.2 解决法案（推荐 B1+B2，B3 可选）

**B1（核心）基准点固定**
- 把 `joy.bx, joy.by = twx, twy` 改成**永远用 `JOY_HOME_X, JOY_HOME_Y`**（不再跟随按下点）；
- `JOY_HOME` 就取"原神预设位置"：本端口现值 **(84, 392) = 13.1% × 81.7%**（画布 640×480），与预设左下摇杆位置一致；若你在编辑器里量到预设坐标不同，**只改这两个常量**即可（其它逻辑全不依赖）。

**B2（触区）围绕固定中心的"吸附区"**
- `inJoyZone(wx)` 从"左半屏（`wx < 0.55W`）"改成**以中心为准的矩形/圆**，建议：`|wx-84| ≤ 120 且 |wy-392| ≤ 150`（或半径 120 的圆）；
- 好处：点左下角**任意处**都能抓到摇杆（不要求精确点中圆），同时不会吞掉屏幕中部/右上角的点按；
- 手指可以落在中心以外：方向 = `(手指 − 中心)`，杆头按 `JOY_R=46` 截断（现有 `joyVector()` 直接复用）。

**B3（视觉，可选）**
- 未按住时也画一个 20% 透明的底盘（圆环），按住时画实心杆头 —— 让玩家知道"摇杆固定在这儿"；
- 松手（`CursorUp`）时杆头归位（现有逻辑已做）。
- 与 Genshin 预设一致性：底盘直径建议 **92**（= 2×JOY_R）、杆头直径 **40~46**；PC（16:9 试玩）用半径 69 的放大档（`docs/device-setup.md:167` 已有两档记录）。

## 2.3 可行性

| 项 | 结论 |
|---|---|
| 改动量 | `main.lua` 3 处：`JOY_HOME` 常量（若要校准）、`CursorDown` 的基准点赋值、`inJoyZone()`；**可选**加一次底盘绘制 |
| 风险 | 低。纯输入层；`joyDirs()` 纯函数与 `applyPointer()` 的喂入方式都不变 → 现有 `_input` 的摇杆断言不受影响 |
| 需要注意 | `uiHit()` 优先级必须保留（底部按钮行在左半屏，不能被摇杆吞），B2 的吸附区要避开菜单行 y 区间 |
| 验收 | 手测：在左下角不同位置按下，方向手感完全一致；在屏幕中部按下**不再**起摇杆；底部四按钮仍可点 |

---

# 问题 3：拖拽后升起的骨头（骨刺）判定与形态

## 3.1 实测现状（真实 `Game` / 真实脚本）

| 对象 | 实测结果 | 结论 |
|---|---|---|
| `sans_bonestab1/2/3`（HUD 18/19/23）的 `BoneStab` | 把灵魂钉在框底跑 12s：出现 dir=0/1/2 三种骨刺，**命中 3 次**（`hit` 日志） | **有判定** ✅（整条边 = 判定矩形，伸缩期才致命） |
| `final` 阶段① 的 `BoneStab`（`BoneStab,$Direction,23.2,1.0,0`） | 同上机制 | **有判定** ✅ |
| **`final` 阶段③ 的两组「双方向骨刺」** | 实测相位永远停在 `warn` → 被紧随其后的 `0.9,BlackScreen,1` 清掉，**从未进入 out/stay** | ❌ **没有判定**（= 你报的"拖拽后升起的骨头没有攻击判定"） |
| `final` 阶段① 收尾的两条 `BoneHRepeat,130,-10,200,1,300,3,183` / `BoneHRepeat,330,650,200,3,300,3,183` | 是 **200×10 的长条（平行于边）**，x 只覆盖 130..330（框 241..406 里只有左 89px），从上下边升起 | 判定有（普通骨头），但**形态/覆盖**与"骨刺墙"的预期不符 → 你要求改成"一排垂直于边的小骨头" |

## 3.2 解决法案（C1 判定 / C2 形态 / C3 加厚）

**C1 让"永不伸出"的骨刺真的伸出来（修判定）**
- 现象根因：`warn 1.9s` > 后面的 `0.9,BlackScreen,1`（黑屏会清空所有骨头）⇒ 骨刺在预警期就被删；
- 修法（任选其一）：
  - **C1-a（推荐）**：把该段紧随其后的 `0.9,BlackScreen,1` 延后到 **`2.2,BlackScreen,1`**（warn 1.9 + out 0.1 + 停留 0.2）⇒ 骨刺能伸出并被看见（段长 +1.3s）；
  - C1-b：把 `warn` 压回 `≤0.8`（`0.7`）：骨刺 0.7s 伸出、0.9s 被清掉 —— 与"延长预警"的要求相反；
  - C1-c：把黑屏拆到骨刺完全收回之后（段长 +2.3s）。
- 建议同时把 `stay`（停留）在 C1-a 下调到 `0.2`，让"伸出→被打/躲开→收"读得清楚。

**C2 形态：把"平行于边的长条"改成"一排垂直于边的小骨头"（间隙 < 灵魂判定）**
- 灵魂判定：`SOUL_R = 2` ⇒ 判定盒 **4×4 px**；视觉心宽 16px；
- 目标：相邻小骨的**间隙 ≤ 3px**（< 4px）⇒ 灵魂**绝对钻不过去**（视觉上 16px 的心也明显过不去）；
- 具体参数（以 `BoneStab` 的面板为例，边长 = 框边长 L）：
  - 小骨宽 = `BONE_W = 10`，间距 `spacing = 13`（间隙 3px），数量 `N = ceil(L / 13)`；
  - 每根高度 = 原 `dist`（面板伸出量），从边外滑入 `dist` 后原路收回（相位机不变）；
- **推荐实现（改动最小）**：判定仍用**整条边**（`World:stabRect` 不变 ⇒ 等价于"缝隙过不去"），只把**渲染**改成"一排小骨"：
  - `main.drawStab()` 里把"一个整条矩形"画成 `N` 个 `10×dist` 的小矩形（等距 13px）；
  - 好处：① 判定天然无缝（100% 满足"间隙小于判定"）；② 不改 `World:stepStab` 相位机；③ 闪烁的预警条仍可用整条（一看见就知道整条边会出）。
- 备选实现（更"实体化"，工作量更大）：用 N 个 `BoneV` 实体替换 `BoneStab`，逐根滑入/收回（需要新命令或 core 侧生成器，且要保证 3px 缝不产生"卡边"抖动）。

**C3 除 final 轮的"对应攻击"加厚为 **1.5 倍**
- 口径：`BoneStab` 的厚度参数 = **`dist`**（面板厚 = dist+8、伸出量 = dist−3）；
- 非 final 轮现值与目标（×1.5）：

| 脚本（HUD） | 现值 `dist` | 目标 1.5× | 备注 |
|---|---|---|---|
| `sans_bonestab1`（18） | 9 | **13.5** | 三档骨刺 |
| `sans_bonestab2`（19） | 9 | **13.5** | |
| `sans_bonestab3`（23） | 9 | **13.5** | |
| `sans_intro`（1，初见杀） | 23.2 | **34.8** | 该值本身是上一轮用户口径 29→23.2（×0.8）后的结果；要不要一起 ×1.5 需你点头 |
| `final`（24） | 23.2 / 38.4 | **不动** | 按你的口径"除 final 轮" |

- 若你说的"对应攻击"是指 **final 阶段①收尾的升起长条**（`BoneHRepeat`）而不是 `BoneStab`，那"C3 加厚"就落到那些长条所在段（目前只有 final 有）⇒ 此项自然只影响 final，与"除 final"矛盾 —— 所以按 C3 表（BoneStab）理解更自洽。

## 3.3 可行性

| 项 | 结论 |
|---|---|
| C1 | 只改 CSV 的**一个延时数值**（`final.csv` 阶段③ 的 `0.9,BlackScreen,1` → `2.2,...`），或按 C1-c 再加一段黑屏；段长会变长（+1.3s）——需要你确认节奏 |
| C2 | 只改 `main.lua` 的 `drawStab()`（渲染），**判定与相位不动**；若选备选实现则要动 core（中风险） |
| C3 | 只改 CSV 的 `dist` 数值（3~4 行），跑 `gen-attacks` 重新生成即可 |
| 验证 | `probe_rise_bones.lua`（`D:\stars\_analysis\`，已存在）可继续用来盯"骨刺是否真的进入 out/stay、是否命中"；C2 改完用无头截图看"一排小骨"的观感 |
| 回归 | `node tools/gen-attacks.mjs`（改了 CSV）→ `build-save` → `core_selftest` / `_rounds` / `verify-all --quick` |

---

# 4. 汇总：建议的落地顺序与改动清单

| 顺序 | 问题 | 文件 | 改动 | 风险 |
|---|---|---|---|---|
| 1 | ② 固定摇杆 | `lua/main.lua` | `JOY_HOME` 校准 + `CursorDown` 不再改基准点 + `inJoyZone()` 改为围绕中心的吸附区（+可选底盘绘制） | 低 |
| 2 | ① PC 鼠标点选 | `lua/main.lua` | 加 `CursorMove → hover 选中`；再用 `GetCursorUIPos` 在 confirm 路径做一次坐标命中兜底 | 低 |
| 3 | ③-C1 让骨刺伸出 | `prototype/attacks/final.csv` | 阶段③ 的 `0.9,BlackScreen,1` → `2.2,...`（stay 建议 0.2） | 中（段长 +1.3s） |
| 4 | ③-C2 骨刺形态 | `lua/main.lua` | `drawStab()` 改画"一排 10px 小骨、间距 13px（缝 3px < 判定 4px）" | 低（判定不变） |
| 5 | ③-C3 非 final 加厚 | `prototype/attacks/sans_bonestab{1,2,3}.csv` | `dist 9 → 13.5`（`sans_intro` 待你确认） | 低 |

**回归命令**

```powershell
cd D:\stars\workspace\sans-fight
node tools/gen-attacks.mjs        # 只改了 CSV 才跑
node tools/build-save.mjs
node tools/run-lua.mjs lua/core_selftest.lua
node tools/run-lua.mjs lua/_input.lua
node tools/run-lua.mjs lua/_tap.lua
node tools/verify-all.mjs --quick
```

> 本文只做"技术分析与可行性方案"，**未改工作区任何代码**；唯一已执行的动作是把 `main.lua` 备份到 `D:\stars\main_备份_2026-10-11.lua`（并在备份顶部加了【重点标注】）。

---

## 5. 实施记录（2026-10-11 已落地；鼠标项按你要求**搁置**）

### 5.1 根因定论：bonestab「没有攻击判定」= **伸得太浅**（不是缺判定分支）

实测（`D:\stars\_analysis\probe_stab_depth.lua`，真实 `Game` + `sans_bonestab1`，12s）：

| 灵魂中心离框底 | 改前（dist=9，致命深 5+9=14px） | 改后（dist=13.5，深 18.5px） |
|---|---|---|
| 8 / 14 / 16 / 20 px | 9 / 6 / 3 / 6 次命中 | 9 / 8 / 6 / 6 |
| **25 px** | **0 次** | **3 次** ✅ |
| 40 / 80 px | 0 | 0 |

→ 结论：骨刺的致命区只有**离边 `dist+5` 深**；灵魂中心超过约 20px 就**完全打不到**（移动端被摇杆带得离边更远，所以体感"没有判定"）。另外 **final 阶段③ 的两组双骨刺根本没伸出**（`warn 1.9 > 0.9 BlackScreen` ⇒ 相位永远停在 warn）——那是另一条独立的"没判定"。

### 5.2 已改动清单

| # | 文件 | 改动 | 验证 |
|---|---|---|---|
| ① | `lua/main.lua` | **固定摇杆**：`CursorDown` 基准点固定为 `JOY_HOME(84,392)`（不再跟随按下点）；`inJoyZone` 改为围绕中心的吸附区（±120 / ±150）；`joystickGeom` 触摸分支常显（未按住画 0.28 淡底盘） | `_input` 4dir 矩阵 151/151 pass（测试已同步为"按下点取 HOME"） |
| ② | `prototype/attacks/final.csv` | 阶段③ 两处 `0.9,BlackScreen,1` → **`2.2,BlackScreen,1`** ⇒ 双骨刺真的伸出 | 相位实测：`t=1.92 warn→out`、`t=2.03 out→stay`、`t=2.23` 被黑屏清（伸出 0.2s） |
| ③ | `prototype/attacks/sans_bonestab{1,2,3}.csv` | **dist 9 → 13.5（×1.5）**（"除 final 轮的对应攻击加厚"） | 深度表见 5.1；`core_selftest` A-9 期望值同步为 `13.5,1.2,*` |
| ④ | `lua/main.lua` `drawStab()` | **形态**：整条平行于边的骨刺改画成**一排垂直于边的小骨**（沿边间距 13px、单根厚 10px ⇒ **缝 3px < 灵魂判定 4px**，钻不过去）；**判定仍用整条边**（`core.World:stabRect` 未动 ⇒ 视觉有缝、实际无缝） | 需在真机/截图复核观感 |

> 附带修复：`main.lua` 主 chunk 的局部变量已达 Lua 上限（200）——把 `drawStab` 移到 `drawBar` 之后、并把摇杆吸附区常量内联，**不再新增 chunk 级 local**，否则 `_title/_input/_tap` 全部报 `too many local variables`。

### 5.3 验收

```
_check / _rounds / core_selftest / _tap / _title / _input / _probe_sandbox_adapter / build-save / verify-client-pool
结论：9 / 9 通过
  core_selftest 324 PASS / 0 FAIL
  _input        241 PASS / 0 FAIL（4dir 矩阵 151/151）
sans-fight.save.json 已重建（919,967 字节）
```

**仍未做（按你要求搁置）**：问题 1（PC 鼠标 hover 选中 + `GetCursorUIPos` 兜底）。
