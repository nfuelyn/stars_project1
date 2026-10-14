# 新手教程阶段：现状调研 + 实施方案

- **需求（用户口径）**：在**开始菜单之前**插入一个「新手教程阶段」；先给一个**二选一**界面（进入新手教程 / 否）；
  教程内部依次教：①红心移动 ②骨头攻击 ③蓝心移动 ④蓝心四向跳跃 ⑤蓝骨机制 ⑥橙骨机制。
- **工作区**：`D:\stars\workspace\sans-fight`（`lua/core.lua`、`lua/main.lua`、`lua/config.lua`、`prototype/attacks/*.csv`）
- **日期**：2026-10-14
- **方法**：逐条读状态机 / 输入 / 渲染 / 攻击脚本管线，所有结论都标了行号；未标注的部分是设计建议。

---

## 0. 一句话结论

**可行，而且比想象中干净** —— 因为本作的攻击脚本引擎已经能表达教程需要的全部要素：

- **红/蓝心切换**：`HeartMode` 命令（0 红 / 1 蓝）
- **四向重力**：`HeartDir`（0 东 1 南 2 西 3 北）+ `HeartMaxFallSpeed`
- **蓝骨 / 橙骨**：`BoneV/BoneH/BoneVRepeat/BoneHRepeat` 都带 `color` 参数（**1=蓝骨、2=橙骨**），
  碰撞已经按「移动才受伤 / 静止才受伤」判定（`core.lua` L2940-2951）

所以**六节教学可以全部写成 CSV 攻击脚本**（`prototype/attacks/tut_*.csv`），不用新造弹幕代码。

真正需要动的是**状态机**：加两个状态（`tut_ask` 二选一、`tutorial` 教程进行中），并把现有 10 处
`state == 'enemy'` 门闸放行 `tutorial`。

**最大的坑不在代码，在服务端计时器**（§5.1）：`SansFightStart` 已经在 OnStart 发出、服务端 120s 计时
从那一刻起跑；教程若插在开局之后，会**吃掉计时器时间**。这条必须先定口径再动手。

---

## 1. 现状调研（全部带行号）

### 1.1 状态机

| 状态 | 进入位置 | `M.render` 行为 | 输入由谁处理 |
|---|---|---|---|
| `title` | `Game.new` **L1548**；`retitle` **L1548** | **L3237 早退**：标题 + 4 张难度卡 + 提示，然后 `return` | **main.lua 自己处理**（键盘 L2857-2870 / 鼠标 L2297-2328） |
| `enemy` | `startEnemy` **L1613** | 落进战斗段（box L3235 / sans L3285 / soul L3389 / HUD L3396-3401 / 骨头 / 龙骨炮） | core `applyInput` **L3083** |
| `menu` / `attack` / `sub` | L1732 / L2022 / L1901 | 战斗段 + 菜单 | core `applyInput` L3072-3082 |
| `result` | `finish` **L1774** | **L3252 分支**（结算页） | core `applyInput` L3059-3071 |

关键点：**`title` 是唯一"core 不处理输入、由适配层代管"的状态**（`applyInput` 里没有 title 分支）。
教程的二选一界面可以照抄这套分工。

### 1.2 需要放行 `tutorial` 的 enemy 门闸（共 10 处）

| 行 | 原判断 | 作用 | 教程态 |
|---|---|---|---|
| **L1787** | `state ~= 'enemy'` | `sansShake` 抖屏 | 需放行 |
| **L1855** | `state ~= 'enemy' or soul.mode ~= 'blue'` | `jump()` 蓝心跳 | 需放行（第 4 节） |
| **L2092** | `state ~= 'enemy'` | `hurt()` 受伤 | 需放行（第 2/5/6 节要能"被打到"） |
| **L2321** | `state ~= 'enemy'` | `Game:update` 主体（物理/碰撞） | 需放行 |
| **L2324** | `state ~= 'enemy'` | 同上（KR 之后二次确认） | 需放行 |
| **L2720** | `state ~= 'enemy'` | 测试钩子 `testHitsAt` | 建议放行 |
| **L2897 / L2957 / L2974** | `state ~= 'enemy'` | 三个碰撞循环的 `break` | 需放行 |
| **L3083** | `state == 'enemy'` | `applyInput` 的跳跃分支 | 需放行 |
| **L3300** | `g.state == 'enemy'`（`fieldOn`） | 骨墙/骨头/龙骨炮**是否绘制** | 需放行，否则教程里什么都看不见 |
| **L3460** | `M.hud` 的 phase | HUD 状态机 | 建议映射成 `enemy` |

**推荐做法**：在 `core.lua` 顶部加一个判定函数，然后把上面这些替换成它 ——
```lua
-- 【新手教程】战斗态判定：教程进行中复用 enemy 的物理/碰撞/绘制，只是不推进回合
local function inFight(g) return g.state == 'enemy' or g.state == 'tutorial' end
```
（用函数而不是 `or` 散写，避免以后再加状态时漏改。）

### 1.3 攻击脚本系统（教程内容的载体）

- **CSV 格式**：`<时间>,<命令>,<参数…>`，`#` 开头是注释；例见 `prototype/attacks/sans_spare.csv`（6 行）
- **生成**：`node tools/gen-attacks.mjs` → `lua/attacks.lua`（当前 27 个脚本）
- **可用命令全集**（`core.lua` 的 `CMD.*`，共 46 个）：
  `HeartMode` / `HeartDir` / `HeartTeleport` / `HeartMaxFallSpeed` / `HeartWall` /
  `BoneV` / `BoneH` / `BoneVRepeat` / `BoneHRepeat` / `BoneStab` / `ArrowBone` / `SineBones` /
  `GasterBlaster` / `Platform` / `PlatformRepeat` / `CombatZoneResize` / `CombatZoneResizeInstant` /
  `CombatZonePos` / `CombatZoneSpeed` / `SansSlam` / `SansSlamDamage` / `SansAnimation` / `SansHead` /
  `SansBody` / `SansTorso` / `SansText` / `SansSweat` / `SansX` / `SansRepeat` / `SansEndRepeat` /
  `Sound` / `Music` / `BlackScreen` / `TLPause` / `TLResume` / `EndAttack` / `GetHeartPos` /
  `SET` / `ADD` / `SUB` / `MUL` / `DIV` / `MOD` / `SIN` / `COS` / `RAD` / `DEG` / `RND` / `FLOOR` / `ANGLE`
- **★ 蓝骨 / 橙骨在脚本里怎么写**：
  `CMD.BoneV(w, x, y, h, dir, speed, color, midFuse)`（**L717**）、
  `CMD.BoneH(w, x, y, wd, dir, speed, color, midFuse)`（**L720**）、
  `BoneVRepeat/BoneHRepeat(..., color, midFuse)`（**L725** 起）。
  碰撞侧 **L2940-2951**：`color == 1` → 只在**移动**时受伤；`color == 2` → 只在**静止**时受伤；其余 → 无条件受伤。
- **抽签不会污染正片**：回合→脚本是**固定表** `FIXED_SEQ`（**L1410-1419**）+ 显式白名单
  `TEMPLATE_SETS`（**L215-218**）。新增 `tut_*.csv` **不会**被任何回合抽到。
- **但有一条测试会自动遍历全部脚本**：`core_selftest.lua` **L722-748**
  「attack-scripts：attacks.lua 里**全部**攻击脚本编译 + 空跑」要求每个脚本
  ①**无未知命令** ②**90s 内 `EndAttack`**。教程脚本必须满足（这其实是好事，等于自带体检）。

### 1.4 输入与点击（二选一界面要复用的链路）

| 层 | 位置 | 说明 |
|---|---|---|
| 鼠标点标题卡 | main.lua **L2297-2328** | 遍历 `titleCards`（**L357-358** 收集、**L1902** 填充），命中 → `core.titleMove` / `core.titleChoose`；触摸端还有「点两次确认」`pendingSel`（**L236**） |
| 键盘选难度 | main.lua **L2857-2870** | 左右边沿 + 确认 → `core.titleMove` / `core.titleChoose` |
| 画布不画战斗框 | main.lua **L1928-1947** | `titleNow` → `skip = (cmd.kind == 'box' and titleNow)` |

**结论**：二选一界面**直接复用菜单卡（`kind='menu'`）**，只要把 main.lua 里「收集/点击/键盘」的
`state == 'title'` 放宽成「选择类界面」，动作换成 `core.tutChoose`。这样触摸二段确认、
键盘鼠标双通道、命中矩形都不用重写。

### 1.5 文案与 HUD

- 文案走 `hudText` 命令（`size` / `color` / `align` 都有），中文由 `lua/textart.lua` 自绘（`C.textMode='art'`）
- 现有 HUD 是**写死**的：`LV 19` / `HP n/92` / 血条 / `KR n` / `ROUND n / 24` / `难度 x`（**L3396-3401**）
  → 教程态要把 `ROUND n / 24` 换成 `教程 n / 6`（其余可保留）
- Sans 的台词系统：`Game:say(t)`（**L1783**）+ `LINES`（**L238** 起），带打字机效果（`lineShown`）
  → 教程里让 Sans 当"教官"可以直接用它

---

## 2. 流程设计

```
OnStart
  └─ state = 'tut_ask'         ← 新增：二选一界面
        ├─ 选「进入新手教程」 → state = 'tutorial'（tutIdx = 1）
        │        ├─ 第1节 红心移动      → 完成 → 2
        │        ├─ 第2节 骨头攻击      → 完成 → 3
        │        ├─ 第3节 蓝心移动      → 完成 → 4
        │        ├─ 第4节 蓝心四向跳跃  → 完成 → 5
        │        ├─ 第5节 蓝骨机制      → 完成 → 6
        │        └─ 第6节 橙骨机制      → 完成 → 教程结束
        │               └─→ state = 'title'   （落到原有开始菜单：选难度 → 开局）
        └─ 选「直接开始」       → state = 'title'   （原有开始菜单）

任意时刻按 ESC/取消 → 跳过教程 → state = 'title'（防卡死）
```

**待你拍板的分支**：教程结束后是「回到开始菜单」还是「直接开局」。本文按「回到开始菜单」写
（因为需求写的是"在开始菜单**前**加一个阶段"）；若要直接开局，把结束动作从 `retitle()` 换成 `start()` 即可。

---

## 3. 六节教学的设计

统一约定：

- **每节 = 一个 CSV**（`tut_1_redmove.csv` … `tut_6_orange.csv`），只负责"摆场景 + 放弹幕"
- **进度的推进由 core 的"教程导演"负责**（CSV 无法表达"玩家移动了 40px"这类条件）
- **被打到不判负**：教程内 `hurt` 照常生效（心的透明度闪烁 + 抖屏 + 日志），但
  ① HP 归零不 `finish('fail')` ② 本节**重来**并把 HP 恢复到入场值
- **每节顶部一条指令条**（`hudText`，y 紧贴战斗框上沿）+ 右上 `教程 n / 6`
- 每节都有 **1.5s 的准备期**（先显示文字、不出弹幕），避免"还没看就死"

| # | 教学 | 战斗框 | 灵魂 | 场景（CSV 内容） | 完成条件 |
|---|---|---|---|---|---|
| 1 | **红心移动** | 375×140 | 红 | 无弹幕。框内画四个方向的箭头提示（`hudText`） | 四个方向**各移动 ≥ 40px**（或累计位移 ≥ 150px） |
| 2 | **骨头攻击** | 375×140 | 红 | 一根**慢速**`BoneV`居中推过（speed 打 0.6 难度倍数），留出左右可躲的空隙 | 撑过 6s 且**未被命中** |
| 3 | **蓝心移动** | 375×140 | 蓝（dir=1 重力下） | 无弹幕，落地后左右移动 | 左右**各移动 ≥ 40px** |
| 4 | **蓝心四向跳跃** | 200×200 | 蓝，`HeartDir` 每 2.5s 轮换 0→1→2→3 | 四周皆为"地面"（框边即地面） | 四个方向**各成功起跳 1 次**（`jump()` 被调用且离地） |
| 5 | **蓝骨机制** | 375×140 | 红 | 一条 `BoneH,...,color=1`（**蓝骨**）缓慢横推 | 让它通过且**未受伤**（= 全程没动） |
| 6 | **橙骨机制** | 375×140 | 红 | 一条 `BoneH,...,color=2`（**橙骨**）缓慢横推 | 让它通过且**未受伤**（= 全程在动） |

每节的失败反馈（复用 `Game:say`）：

| 节 | 失败时说什么 |
|---|---|
| 2 | 「被骨头碰到了。往空隙那边挪。」 |
| 5 | 「**蓝骨**：别动。你一动它就咬你。」 |
| 6 | 「**橙骨**：动起来。站着不动才会挨打。」 |

> 第 5/6 节的判定方向相反，建议**成对教学**（先蓝后橙），并在节内用颜色强调：
> 蓝骨画青色描边、橙骨画橙色描边（`hudText` 已经支持 `color`）。

---

## 4. 技术方案

### 4.1 core.lua 改动清单

| # | 位置 | 改动 |
|---|---|---|
| 1 | 顶部 | 新增 `local function inFight(g)`；把 §1.2 那 10 处判断换成它 |
| 2 | `Game.new` **L1548** | `self.state = self.bootTutorial and 'tut_ask' or 'title'`（★ 默认仍是 `title`，见 §5.3） |
| 3 | 新增 | `Game:startTutorial(idx)` / `Game:tutUpdate(dt)`（导演：计时、完成判定、失败重来） |
| 4 | 新增 | `Game:tutDone()` → `self:retitle()`（或 `start()`） |
| 5 | `applyInput` | 新增 `elseif self.state == 'tutorial' then` 分支：确认/取消 = 跳过本节或退出教程 |
| 6 | `M.render` | `tut_ask` 分支：**照抄 title 分支**（L3237-3251），只把 4 张难度卡换成 2 个选项；`tutorial` **不早退**，落进战斗段 |
| 7 | `M.render` HUD 段 **L3400** | `ROUND` 那行在教程态改成 `教程 n / 6` |
| 8 | `M.render` 战斗段 | 教程态多推一条 `hudText`（本节指令，y = 框上沿 -30）与一条 `hudText`（进度） |
| 9 | `M.**` 对外 API | 新增 `M.tutChoose(g, i)` / `M.tutIndex(g)` / `M.tutLesson(g)`（给测试与适配层用） |
| 10 | `Game:hurt` | 教程态：`hp` 有 1 的下限、不 `finish('fail')`；命中即触发本节重来 |

**定位数值（供实现时直接抄）**：框上沿 y=178.5、指令条 y≈150；HUD 行 y=403；按钮行 y=432。
（`BOX_CY=308.5`、`BOX_OFF=(240,226)`，见 core 顶部与 main 的 `ORIG_CX/ORIG_CY`。）

### 4.2 main.lua 改动清单

| # | 位置 | 改动 |
|---|---|---|
| 1 | **L2683** | `core.newTitle({...})` 增加 `tutorial = (C.tutorial ~= false)` |
| 2 | **L1902 / L1928 / L2297 / L2857** | 把「`state == 'title'`」放宽为「title 或 tut_ask」；动作按状态分派到 `core.tutChoose` / `core.titleChoose` |
| 3 | **L1928-1947** | `tut_ask` 与 title 一样**不画战斗框**（`skip` 条件带上 tut_ask） |
| 4 | — | 教程态无需新代码：战斗框/Sans/灵魂/HUD 自然走现有绘制 |

### 4.3 config.lua

```lua
-- 新手教程：开局先问「进不进教程」。false = 直接进开始菜单（排查问题时用）
C.tutorial = true
```

### 4.4 新增资产

```
prototype/attacks/tut_1_redmove.csv      (红心移动)
prototype/attacks/tut_2_bone.csv         (骨头攻击)
prototype/attacks/tut_3_bluemove.csv     (蓝心移动)
prototype/attacks/tut_4_bluejump4.csv    (蓝心四向跳跃)
prototype/attacks/tut_5_bluebone.csv     (蓝骨机制)
prototype/attacks/tut_6_orangebone.csv   (橙骨机制)
```
生成：`node tools/gen-attacks.mjs` → `lua/attacks.lua`（27 → 33 个）
**不要**把它们加进 `TEMPLATE_SETS` / `FIXED_SEQ` / `SPIRAL_SCRIPTS`。

---

## 5. 风险与对策

### 5.1 ★ 服务端 120s 计时器会被教程吃掉（**必须先定口径**）

- `C.startSignal = 'SansFightStart'` 在 **OnStart 只发一次**；你的服务端节点图收到就起 120s 计时，
  到点解锁「胜利结算」。
- 教程如果插在开局之后，**玩家看教程的时间会算进这 120 秒** → 教程做得越久，留给战斗的时间越少；
  如果教程超过 120s，理论上"还没打就能结算"。
- 三种对策（按推荐度）：
  1. **教程放在 `SansFightStart` 之前**：先走二选一+教程，教程结束、玩家在开始菜单按下确认的那一刻
     才发 `SansFightStart`。**最干净**，但要改 main.lua 的发信号时机（当前在 `OnStart`）。
  2. 服务端计时只在收到「战斗开始」时才起 —— 即把信号改名/加一个 `phase` 参数区分"进教程"和"开打"。
  3. 直接接受，把服务端计时从 120s 放宽（例如 150s）。

### 5.2 结算信号不能被教程触发
教程内不得调用 `settle()` / 不得发 `SansFightSettle`；`finish` 在教程态也要屏蔽（§4.1 #10）。

### 5.3 ★ 不能让既有回归全红（**测试口径**）

`newGame` 目前默认 `state = 'title'`，**所有**既有测试都依赖这一点
（`_rounds` 75 条、`_check` 四档各 900 帧、`_tap` 42、`_title` 33、`_input` 241、`core_selftest` 329 …）。
如果 `newGame` 默认进 `tut_ask`，**这些会成片失败**。

**对策**：教程**只由 opts 打开** —— `newGame({ tutorial = true })`；
`main.lua` 传 `C.tutorial ~= false`，测试一律不传（= 默认关）。
这样新增教程对既有 700+ 条断言**零影响**。

### 5.4 教程脚本会被"全脚本空跑"测试遍历
（见 §1.3）→ 教程 CSV 必须：只用合法命令 + 90s 内 `EndAttack`。
另外注意 `TLPause` 不要忘了配 `TLResume`（`sans_spare.csv` 的写法可以照抄）。

### 5.5 Lua 200 局部变量上限
本项目已经踩过这个坑（见 `records/lua-port.md`）。教程代码优先**挂到 `Game:` 方法**或**表字段**上，
不要在 `core.lua` 顶层再加一堆 `local`。

### 5.6 触摸端
二选一复用 title 的「点两次确认」（`pendingSel`，main.lua **L236**）—— 免费获得，
但**要确认选中态的高亮**在 `tut_ask` 下也画得出来（title 用的是 `menu` 命令的 `selected` 字段）。

### 5.7 交付节奏
每次改完仍必须：`node tools/gen-attacks.mjs`（改了 CSV）→ `node tools/build-save.mjs` →
`node tools/sync-sandbox.mjs` → **完全退出试玩重进**。

---

## 6. 验收标准

**可自动化断言（建议写进 `core_selftest.lua`）**

- [ ] `newGame({})` 的 `state == 'title'`（**默认不进教程**，保护既有回归）
- [ ] `newGame({ tutorial = true })` 的 `state == 'tut_ask'`
- [ ] `tutChoose(g, 1)` → `state == 'title'`；`tutChoose(g, 0)` → `state == 'tutorial'` 且 `tutIdx == 1`
- [ ] 教程态下 `M.render(g)` 能拿到 `kind == 'box'`、`'soul'`、`'hudText'`（说明没被早退掉）
- [ ] 六节依次推完 → `state == 'title'`
- [ ] 教程态 `hurt()` 到 HP 下限**不会**把 `state` 变成 `'result'`
- [ ] 六个 `tut_*.csv` 在 `attacks.lua` 中存在、无未知命令、90s 内结束（由 §1.3 那条测试自动覆盖）
- [ ] `verify-all --quick` 从 10/10 保持 10/10（既有无回归）

**必须真机确认**

- [ ] 二选一界面键盘（左右+空格）与鼠标都能选
- [ ] 第 5/6 节的蓝骨/橙骨**真的按"别动/动起来"判定**（这是教程的核心教学点，离线只能断言 `moved` 逻辑）
- [ ] 指令文字不遮挡 Sans / 骨头，且在真机字号下可读
- [ ] 服务端计时口径符合 §5.1 的选定方案

---

## 7. 分步实施建议（每步都能单独验收）

| 步 | 内容 | 产出 |
|---|---|---|
| 1 | 只加 `tut_ask` 二选一（+ `C.tutorial` 开关、main 的收集/点击/键盘） | 能进能出，教程还是空的 |
| 2 | 加 `tutorial` 状态 + `inFight()` 放行 + 空教程（只有文字和进度） | 状态机能跑通 6 节 |
| 3 | 写 6 个 CSV（先只做"摆场景"，完成判定统一用"撑过 N 秒"） | 六节都有内容 |
| 4 | 逐个把完成判定换成真实条件（位移/起跳/未受伤） | 真正的教学 |
| 5 | 补断言 + 真机验收（§6） | 可交付 |

---

## 8. 附：来源速查

| 内容 | 位置 |
|---|---|
| 状态机 / 各状态进入点 | `lua/core.lua` L1548(title) / L1613(enemy) / L1732(menu) / L1774(result) / L1901(sub) / L2022(attack) |
| 需放行的 10 处 enemy 门闸 | 同上 L1787 / L1855 / L2092 / L2321 / L2324 / L2720 / L2897 / L2957 / L2974 / L3083 / L3300 / L3460 |
| `M.render` 的 title 早退与战斗段 | L3237-3251（title）/ L3252+（result）/ L3235(box) / L3285(sans) / L3389(soul) / L3396-3401(HUD) |
| `applyInput` 分支 | L3059-3085（在 title 态**不处理输入**） |
| 蓝骨/橙骨（脚本） | `CMD.BoneV` L717 / `CMD.BoneH` L720 / Repeat L725；碰撞 L2940-2951 |
| 蓝骨/橙骨（内置） | `Game:spawnBlue(fromBottom, color)` L2206 |
| 其它内置生成器 | `spawnFloor` L2145 / `spawnWall` L2185 / `spawnWhiteSlide` L2217 / `spawnBlaster` L2230 |
| 抽签与脚本表 | `FIXED_SEQ` L1410-1419 / `TEMPLATE_SETS` L215-218 / `scriptForRound` L1421-1425 |
| 全脚本空跑测试 | `lua/core_selftest.lua` L722-748 |
| 适配层标题页交互 | `lua/main.lua` L357-358 / L1902 / L1928-1947 / L2297-2328 / L2683 / L2857-2870 |
| 攻击脚本管线 | `tools/gen-attacks.mjs` → `lua/attacks.lua`；源 `prototype/attacks/*.csv` |
| CSV 最小示例 | `prototype/attacks/sans_spare.csv`（6 行，含 `TLPause` + `EndAttack`） |
| 开局信号与结算 | `lua/config.lua` `C.startSignal` / `C.probeVars`；`docs/结算按钮_节点图与挂载映射.md` |