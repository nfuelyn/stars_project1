# 试玩与验证记录

按 `runtime=html | simulator | device` 分级记录来源、结果、未知与回归。**模拟器绿灯不等于真机通过；真机未跑必须标注。**

## 2026-09-27 · runtime=simulator · 首次在客户端控件模拟器里跑通演示

- 目标：把复刻引擎搬进千星模拟器，用**客户端控件**驱动并截图验证。
- 探针结果（关键接口）：
  - ✅ **`game.GetUICanvasSize()` = 1280×720**（与我们的设计板完全一致 → 世界 640×480 只需 ×1.5 居中、偏移 +160）
  - ✅ 控件运行时 Id = 1..11（容器/文本框/光标区/模板引用/网格/按钮/文本视窗/按键提示/图片/界面动效/全屏动效）
  - ❌ `game.GetClientUIControl('名字')` 不支持按名取控件（返回 nil）
  - ❌ `game.FindClientUIRoot()` 需要 1 个参数（0 参报 bad argument count）
  - ✅ `game.InstantiateClientUIControl` 是**2 参数**；`InstantiateClientUIControl(1073742100, 容器)` 调用成功但**返回 nil**（该索引不是有效模板索引）
- 演示脚本（`1073742105`，挂在客户端控件 `n1`）：迷你 BTS 引擎（BoneVRepeat + 延时语义）+ 世界→画布映射 + 自动躲避 + 逐帧 `OnLevelUpdate` 驱动控件。
- 实测日志：`demo init: boneSlots=4 heart=true hud=true flash=true`、`prog=5 lines (sans_bonegap1 slice)`。
- 截图证据：`qxqy_studio_play_screenshot`（mobile-16-9，frame 228）——画面中可见**一颗星星（图片控件=灵魂）与左上默认文本框**。
  - ✅ **灵魂位置与数学推导一致**：world(320,376) → 画布 x≈640、距底≈150px；截图中星星位于 (≈639, 距顶≈561)，偏差来自自动躲避的位移 → **世界→画布映射公式验证通过**
  - ❌ 4 个"骨头槽位"（网格/按钮/按键提示/界面动效）**没有渲染出矩形**：这 4 类控件缺资源时不画东西
  - ❌ HUD 文本未出现：`SetText` 在文本视窗上很可能不存在（被 pcall 吞掉）
- 结论：**引擎与控件驱动链路已在模拟器里跑通**（灵魂可控可动、攻击脚本按时序推进）；缺的是"骨头"的可视载体（需要一批**图片控件**）与 HUD 文本能力。
- 下一步：① 用 patch `add` 批量加图片控件（或找到正确的客户端模板索引让 `InstantiateClientUIControl` 可用）② 补 `SetText` 等按控件类型的方法 ③ 再补剩余 13 个攻击脚本 ④ 完整 HUD / 菜单 / 结算

## 2026-09-27 · 步骤 1–3 v5 · runtime=web 检索 · 学习 jcw87 的 Bad Time Simulator

- 用户指定参考：[jcw87.github.io/c2-sans-fight](https://jcw87.github.io/c2-sans-fight/)（*Bad Time Simulator (Sans Fight)*），仓库 [Jcw87/c2-sans-fight](https://github.com/Jcw87/c2-sans-fight)
- 读到的内容（全部来自仓库原文件，非推测）：`Documentation/{Attacks,Jumps,Math,Combat,Generalities,Sans}.md` 的命令集，以及 `Files/sans_*.csv` 的真实攻击数据
- 关键收获：
  - **速度换算：原作值 × 30 = px/s**（原作按 30fps 的 px/帧）
  - **颜色语义 `0 白 / 1 蓝 / 2 橙`** → 我们漏了**橙骨（必须移动）**
  - **`BoneStab` 自带 `WarnTime`**（原作仅 0.16666s）＝我们"冒头预示"的官方对应物；还有专用贴图 `Textures/BoneStabWarn.png`
  - 逐行解码了 `sans_intro.csv`（回合 0 偷袭：台词 ready? → 黑屏闪 → 框 165×165 → `SansSlam 1` → `BoneStab 1,54,0.16666,1` → `SineBones 20,-24,360,25` → 16 发 `GasterBlaster` → `here we go.`）
  - 逐行解码了 `sans_bluebone.csv`：**蓝骨（高 100，Color 1）与白骨（高 20，Color 0）成对**出现——原作确实把"静止骨"和"必须动的骨"配对
  - 攻击清单 16 个脚本（intro/bonestab1-3/bonegap×3/boneslide×2/bluebone/platforms×5/platformblaster×2/randomblaster×2/multi×3/final/spare）
  - `SansSlamDamage 0/1` 可关闭砸击伤害 → 这就是"壁ドン不致死"的实现方式
- 本轮实现：**橙骨（Color=2：静止受伤、移动安全）** + 蓝/橙交替 + 颜色图例（"蓝=别动 / 橙=快动"）；「原作」档速度 1.00 → 1.25
- 自测：`node prototype/selftest.js` → **68 PASS / 0 FAIL**（新增 orange-bone 段）
- 研究笔记：`docs/bts-study.md`（含"采纳 / 修正 / 不做"对照表）
- 待做（据研究补）：蓝骨配对白骨、战斗框连续变形、`HeartTeleport`、真正的砸击（含不伤人的壁ドン）、龙骨炮旋转蓄力段、**Lua 攻击脚本改为表驱动**

## 2026-09-27 · 步骤 1–3 v4 · runtime=web 检索 · 原作内容研究 + fidelity 修正

- 用户要求：上网搜索详细游戏内容
- 检索结果与出处：写入 `docs/original-research.md`。可访问源为日文攻略站 [神ゲー攻略](https://kamigame.jp/undertale/page/206025294560134270.html)；
  [Undertale Wiki](https://undertale.fandom.com/wiki/Sans?diff=prev&oldid=39073)、[萌娘百科](https://moegirl.icu/zh-hant/Sans(undertale))、[pixiv百科事典](https://dic.pixiv.net/a/Sans) 正文均被网络拦截（403 / fetch failed），只用到了它们的检索片段
- 关键发现（与原设计对照）：**无无敌帧**、KR 掉到 1 HP 停（我们已一致）、菜单内持续掉血（已一致）、**第 12 次攻击后有中场且选仁慈即死**（缺）、**回合 0 不意打ち**（缺）、最终回合三段与菜单骨（缺）
- 本轮实现：回合 0 不意打ち、中场（含仁慈即死）、「原作」难度档（无敌帧 0.15s）
- 自测：`node prototype/selftest.js` → **66 PASS / 0 FAIL**
- 发现并修掉的度量缺陷：旧难度断言用"固定时间窗内波数"，存在**幸存者偏差**（越难越早死 → 波数反而更少）；改为测「相邻两波生成间隔」（easy 1.85s / normal 1.57s / hard 1.20s）
- 待做（已进 P0 第二阶段）：菜单骨、最终回合三段（横スク / 旋转光束）、壁ドン 0 伤害彩蛋、Sans 睡着后的收尾演出

## 2026-09-27 · 步骤 3 v3 · runtime=html · 骨头外观 / 冒头预示 / 细实线龙骨炮

- 用户要求：① 增加骨头攻击外观的模拟 ② 第一段攻击的预示（骨头冒头再伸出，间隔 0.5s）③ 用细实线构建新实体模拟原版龙骨炮
- 改动：
  - `drawBone()`：骨干 + 两端各两颗骨球 + 深色描边（竖骨/横骨共用）
  - 地面骨头改为四段生命：`peek 0.5s（非致命）→ extend 0.15s → hold 0.55s → retract 0.2s`；`floorLock` 防止致命窗口重叠；新增日志 `wave_peek wave=n`
  - `drawBlaster()`：头骨折线轮廓 + 5 条平行细实线光束（3px/1.5px）+ 9 条拉链短横线 + 蓄力细实线预警，**无实心填充**
- 自测：`node prototype/selftest.js` → **61 PASS / 0 FAIL**（新增 bone-telegraph 段：冒头期不致命、实测约 0.50s）
- 同步：`tests/first-success.json`（步进 2.2→2.8s，加 `wave_peek` 断言）、`tests/mobile-smoke.json`（8.5→9.3s，R1 时长 9s）、新增 `tests/bone-telegraph.json`
- 说明：视觉仍未经我本人试玩（无浏览器工具），标 `browser-run: user`；视觉到千星控件的映射见 `docs/production-plan.md`

## 2026-09-27 · 步骤 5 前置 · runtime=simulator · API 探针（单问题探针）

- 目的：官方综合指南没有客户端脚本 API 条目，用探针在模拟器里**实测**接口，替代猜测。
- 方法：`qxqy_studio_patch addScript`（内联 source）→ `updateScript` 挂到客户端控件 `n1` → `play start` / `step` 读日志。
- 结果（详见 `docs/api-2d-lua.md`）：
  - ✅ 生命周期是**全局函数**：`OnInit` → `OnEnable` → `OnStart` 均实测触发
  - ✅ **`OnLevelUpdate(dt)` 是逐帧回调**（实测每帧 0.0333s；`step 0.05` 收到 0.05）→ 游戏主循环可用
  - ✅ `_VERSION` 为 nil；协程/io/os/package/load 被移除
  - ✅ `game` 表 26 个函数（含 `GetClientUIControl`、`PrintClientUITree`、`InstantiateClientUIControl`、`ServerSignal`、`Tween`、`TweenSequence`、`GetUICanvasSize`）
  - ✅ `game.PrintClientUITree()` 返回 11 类控件的**运行时 Id**（容器=1…全屏动效=11）
  - ✅ 控件是 userdata，`Id` 为 number；实测存在 `SetVisible/SetActive/SetAnchoredPosition/SetSizeDelta/SetImage/SetAnchorMin/SetPivot/SetSiblingIndex/AddKeyEventListener`
  - ❓ 踩到的坑：`script.OnUpdate = ...` 报 `cannot set OnUpdate, no such field` 并**中断整个脚本** → 钩子必须写成全局函数
  - ❓ 待验：类型专属方法（进度条 `SetFillAmount`、动效 `PlayAnimation`、光标区 `AddCursorEventListener`、文本 `SetText`）、`OnDisable`/`OnDestroy`、各 `game.*` 的参数语义
- 当前模拟器存档状态：**只有探针脚本**（`id=1073742105`，挂在 `n1`），控件树仍是默认 11 类模板，**还没建游戏本体**。
- 证据等级：`runtime=simulator`（不是真机）。

## 2026-09-27 · 步骤 3 v2 · runtime=html · 按用户反馈重做后自测

- 用户反馈：攻击速度太快 / 第二轮攻击全饱和 / 需要更丰富的选项 UI / 要能直接导入千星奇域
- 改动：三档难度（标题页可选）；R2 平移墙 → 原地升降墙 + 缺口预警 + 同时只有一道；所有间隔速度乘难度系数；
  四个菜单各有独立面板（攻击时机条 / 行动 4 项 / 道具 2 项 / 仁慈 2 项）
- 自测：`node prototype/selftest.js` → **58 PASS / 0 FAIL**（新增难度密度、骨墙反饱和、子菜单语义断言）
- 关键发现：**平移骨墙是"全饱和"根因**——缺口跟着墙一起移动，玩家必须追着缺口跑
- 说明：仍无浏览器工具，**实际手感未经我本人试玩**，标 `browser-run: user`

## 2026-09-27 · 步骤 3 · runtime=html · 自动化自测（L1）

- 命令：`node prototype/selftest.js`
- 结果：**33 PASS / 0 FAIL**
- 覆盖：开局初始化（C9/C10）、第 1 波无伤（C5/C8）、KR 不致死（C2/C3）、HP/KR 整数、直接命中致死（C1/C4）、重开复位（C9）、蓝骨静止安全（C6）、确定性同 seed 同结果（C10）、回合推进与菜单
- 结果中修掉的缺陷：
  1. KR 上限用命中后 HP 计算 → HP=2 时 KR 恒为 0；改为命中前 HP-1
  2. 蓝骨命中被前一次命中的 0.8s 无敌帧吃掉 → 用例显式清无敌帧以隔离 C6
  3. KR 连续扣血产生小数 HP（17.93）→ 改为每 0.5s 整数结算 1 点
- 说明：这是 HTML 侧逻辑证据，**不能**当作模拟器或真机证据。

## 2026-10-04 · 步骤 5–6 · runtime=simulator · 模板池打通 + 游戏本体跑起来

**突破**：客户端 Lua 的 `game.InstantiateClientUIControl(prefabIndex, parent)` **是可用的**，
之前判成「不支持」是误判——运行时有生命周期守卫 `if (phase === "OnInit" || phase === "OnDestroy") return null`，
而当时的探针全写在 `OnInit` 里。模板池来源是**客户端控件模板资产 `root.children` 的 `guid`**。

据此做了两件事：

1. `tools/build-save.mjs`：从模拟器导出的 patch 快照克隆节点结构，**直接生成存档**
   `workspace/sans-fight/sans-fight.save.json`（不再逐个 `add` 控件，省掉大量 patch 往返）。
   客户端资产里放了 8 个图元模板（rect/circle/triangle/text/fourstar/ring + 2 个中心锚点旋转件），
   服务端资产只留脚本挂载容器，脚本 = `boot.lua`（薄引导）+ `main.lua`/`core.lua`/`attacks.lua`（模块，走 `require`）。
2. 载入路径：`qxqy_studio_load workspace/sans-fight/sans-fight.save.json` → `warnings: []` ✓

**模拟器实测证据（截图逐帧核对）**：

| 观察 | 结果 |
|---|---|
| 启动日志 | `main init: … scale=1.500 ox=160.0` / `main start: mode=core pool=345 flash=true` |
| 控件池 | OnStart 一次性实例化 345 个控件，无 `inst NIL/ERR` |
| HUD | `LV 19` / `HP 92/92` / `KR 0` / `ROUND 0 / 6` / 台词「（他没有打招呼，先动手了。）」全部正确渲染 |
| 战斗框 | 白色四边矩形，位置/尺寸与公式推算一致（世界 (239,226,404,391)） |
| 骨头 | 骨干 + 两端各两颗骨球，白/蓝/橙三色都出现过（`sans_intro` 的 BoneStab / SineBones） |
| 龙骨炮 | 方形炮身 + 5 条平行细实线光束，旋转 90° 正常（`putRot` + `SetLocalRotation`） |
| 菜单回合 | 骨头菜单条 + 「攻击 / 行动 / 道具 / 仁慈」四项 + 攻击条（`sans_intro` 结束后自动进入） |
| 攻击脚本轮转 | `core.debug().script = sans_intro`，回合 0 不计偷袭（C17 ✓） |

**这一轮抓到的真 bug（都已在模拟器里复现 → 修 → 复测无报错）**：

1. `c.visible = false` → `cannot set visible, no such field`：`visible`/`active` 是**只读属性**，
   必须用 `c:SetVisible()` / `c:SetActive()`。整个 `OnStart` 曾因此中断（只创建了 1 个控件就抛错）。
2. **坐标系混用**：逻辑层的世界实体是「框内相对坐标」（已减 `BOX_OFF_X=240, BOX_OFF_Y=226`），
   而 HUD/菜单/子面板是 640×480 绝对坐标。没区分时战斗框画到了画布左上角、灵魂跑到框角上。
   适配层按命令类型切换平移量后落点正确。
3. `cannot convert invalid utf8 to javascript string`：核心的打字机效果用 `g.line:sub(1, g.lineShown)`
   **按字节**截断中文，切进多字节字符中间 → 写控件 `text` 时 JS 侧抛错并**中断整帧绘制（全黑）**。
   适配层加 `safeUtf8()` 防御，核心侧改为按字符推进。
4. `drawBone` 的 `vertical = cmd.vertical ~= false and h >= w`：显式 `vertical=true` 会被 `h>=w` 推断覆盖，
   短骨被画成横骨。改为显式优先。

**本地测试台**：子智能体建了 `tools/run-lua.mjs`，用**与模拟器同款的 fengari（Lua 5.3）**跑测，
`lua/_check.lua` 做「语法 + 接口 + 4 档难度各 900 帧 + 命令种类直方图」集成检查，
不必每次往返模拟器。注意：**本地 fengari 不校验 UTF-8**，第 3 类 bug 只有模拟器/真机能暴露。

**未验证 / 待补**（不许当作已通过）：

- ❓ 龙骨炮「蓄力 → 开火 → 淡出」全周期、正弦骨摆动、骨墙缺口预警、子面板的实际观感，只看到个别帧，未逐段核对
- ❓ **模拟器里的按键输入未验证**：`AddKeyEventListener("KeyboardMoveLeftKeyDown"…)` 已注册成功，但尚未用 `play {key}` 真正驱动过灵魂移动
- ❓ 命中判定/HP-KR 在模拟器里的表现（本地 fengari 里 4 档难度已确认伤害不同：easy 92 / normal 87 / hard 82 / original 72）
- ❓ 回合推进到 R1–R6、中场（第 12 次攻击后）、最终回合三段：本地跑通脚本轮转，模拟器里尚未推进那么远
- ❓ `platforms*` 关卡的平台碰撞（引擎缺口，已派给子智能体实现）
- ❌ 真机（`runtime=device`）未跑；GIA 导出与脚本挂载步骤未做

## 2026-10-04 · 步骤 6–7 预备 · runtime=web · 从源码搭起模拟器网页试玩 + 插件升级 2.0.8

上游仓库：<https://github.com/1475505/miliastra-beyond-simulator>（GPL-3.0，正是本机 DSH 插件的上游）。
克隆到 `D:\miliastra-beyond-simulator`，HEAD `864f5fd (2026-10-02) feat: add basic viewport scrolling`；
仓库根 `package.json` version **2.0.8**、`packageManager: pnpm@10.15.0`。

**「更新控件」的实际收益**（依据 `studio/docs/control-support.md`，检查日期 2026-10-02）：
文本视窗与网格视窗新增**基础滚动**——滚轮/拖拽/触摸、滚动条轨道点击与滑块拖动、边界限制、
`RefreshItems` 真实例化与复用、`ScrollToItemAt`/`scrollProgress`/`GetContentLength` 等查询；
此前网格七方法是**直接抛 `not implemented`**。另新增回放用的 `pointer type:"wheel"` 与 `type:"cancel"`。
（本作只用图片/文本框/图元，未受益于滚动，但这是本机插件 2.0.2 → 2.0.8 的实质差异。）

**按仓库文档构建并启动**：

```sh
pnpm install --frozen-lockfile        # 31s
pnpm build                            # Built dsh-plugin / mcp / web
node web/server.js --workspace D:\stars\workspace\sans-fight --file sans-fight.save.json --host 127.0.0.1 --port 4173
```

`web/public` 生成了 `editor.js`(280KB)、`play-renderer.js`(569KB)、`play.js/html/css`（仓库里只提交了占位）。
入口：`http://127.0.0.1:4173/`（只读预览，自动发现并载入最新 `qxqy-simulator-save`）、
`/editor`（编辑 + 试玩，试玩在 `/editor/play`）、`/health`。

**验证证据（observed / runtime=web）**：

| 检查 | 结果 |
|---|---|
| `/health` | `{"status":"ok"}` |
| `/api/preview` | `service=beyond-simulator-web 0.3.5`、`workspace=D:\stars\workspace\sans-fight`、`activePath=sans-fight.save.json`、`lastError=""`、`name=审判者战 · sans-fight` |
| `/api/state` | `archives:1`（195572 bytes，与 DSH 侧 `qxqy_studio_load` 报的字节/mtime 完全一致）、`scriptCount:4`、`discovery` 无截断/无警告 |
| 驱动试玩 | `POST /api/play {start, canvasId:mobile-16-9}` → `running=true`；`pause` + `step 5s` → `frame=748 / time=29.9s` |
| 运行日志 | `main init: root=true canvas=1280x720 scale=1.500` → `main start: mode=core pool=345 flash=true` → 稳定 `mode=core frame=… cmds=9 off=(240,226) box=(-1,0,165,165) hp=82 phase=menu` |

⚠️ **试玩画面由浏览器端 Pixi/WebGL 渲染**（`/play-renderer.js`），服务端 `/api/editor.png` 只是**编辑器舞台底板**
（我取到的是一张棋盘格），所以试玩帧必须由人在浏览器里看，不能用服务端 PNG 冒充试玩证据。

**插件升级**：`dsh plugin --profile web add dsh-plugin-beyond-simulator@2.0.8` → 已装 **2.0.8**（原 2.0.2），
`dist/worker.js` 225KB → 234KB；`@napi-rs/canvas`（含 `skia.win32-x64-msvc.node` 原生二进制）、`fengari`、
`protobufjs` 均在位；peer `cordis`/`dsh-tools` 由宿主提供（`--dump-config` 退出码 0、无错误）。

**踩坑（环境级，值得记住）**：为构建仓库我先全局装了 `pnpm@10.15.0`，随后 `dsh plugin add` 报
`ERR_PNPM_UNEXPECTED_STORE`——profile 的 `node_modules` 由 pnpm 12（store v11）安装，pnpm 10 想用 store v10。
**修法：把全局 pnpm 还原成 12.4.2**。仓库侧已构建完毕，运行只需要 `node`
（`node web/server.js`、`node scripts/build.mjs`），不必再动 pnpm。

**未验证 / 待办**：

- ❓ 插件 2.0.8 需**重启 `dsh web`** 才在本会话生效（上游文档明确「只构建不会替运行中的进程重新加载模块」）；
  重启前本会话仍运行 2.0.2 的内存代码
- ❓ 网页试玩的**实际操作手感**（键盘移动灵魂、菜单四项、攻击条时机）需用户在浏览器里试，我只能给结构化日志证据
- ❌ 真机（`runtime=device`）仍未跑

### 追加：网页试玩缺键盘 → 给游戏补指针/触摸控制（2026-10-04 同轮）

**发现**：全仓库（源码 + 构建产物）搜 `KeyboardMoveLeftKeyDown` **零命中** —— 网页试玩页只有鼠标/触摸，
不把真实键盘转发成脚本监听的键名；我们的游戏是键盘驱动的，所以在网页里灵魂根本不动
（日志里 `phase=menu` 卡了 30 秒即为证）。真机是手机优先，键盘-only 本就不成立。

**做法**：客户端模板池新增 `全屏光标区`（guid 1073743009，stretch 铺满画布），
容器 `n1` 打开 `showCursor`（worker 里 `cursorEventsEnabled` 要求祖先容器开启才派发），
`main.lua` 注册 `CursorDown/Drag/Up/Click` 并实现：
- 按住/拖动 → 灵魂朝指针走（等价方向输入，死区 2px）
- 点按（按下后未拖动就抬起）→ 命中菜单项/子面板行/攻击条则直接选择，否则当确认

**实测证据（runtime=web，经 /api/play 注入 + 读日志）**：

```
main start: mode=core pool=346 flash=true cursor=true
main: 游标 CursorDown x=370.0 y=245.0 click=false moved=false
main: 游标 CursorUp   x=370.0 y=245.0 click=true  moved=false
main: 点按菜单第 1 项（攻击）
main: 阶段 menu → attack (round=0 hp=92)
main: 阶段 attack → enemy (round=1 hp=92)
main: 指针转向 soul=(522,305) 目标=(360,193) ptr=(700,430)
```

按住指针把灵魂拉到安全位的那一轮：**HP 全程 92 未掉血**（无输入时是 84/87/82）。

**过程中修掉的三个真问题**：

1. **逻辑层有三套世界坐标**：脚本回合 = 绝对−BOX_OFF；内置回合 = 绝对+BOX_OFF；菜单/结算 = 绝对。
   原先按 `state.world` / `box.x < 50` 判定都会错（内置回合也有 `world`），
   改为**几何自校正**：三种平移各试一次，取「整框落在 640×480 内且中心最接近画面中心」者——
   三种情形的正解都恰好居中，实测分别解出 `off=(240,226)` / `off=(-240,-226)` / `off=(0,0)`。
   建议上游把 render 统一成一套绝对坐标（已反馈）。
2. **点按不能延到下一帧处理**：Web 端试玩 Worker 只在被轮询时推进（注入前后 `frame` 不变），
   改为在事件回调里**同步**处理点按。
3. `CursorUp` 与 `CursorClick` 会连着发同一个点按（worker 的 up 分支在未拖动且同控件时补发 Click）
   → 加 `tapPending` 去重。

**新增入口**：`http://127.0.0.1:4173/editor`（编辑 → 试玩 ↗），或 `http://127.0.0.1:4173/`（预览，已自动载入本存档）。
服务由托管后台作业运行：`node web/server.js --workspace D:\stars\workspace\sans-fight --file sans-fight.save.json --port 4173`。

**未验证 / 待办**：

- ❓ **真实浏览器里的操作手感**（拖动躲弹幕、点按选菜单、攻击条时机）只能由人试；我只能给结构化日志证据
- ❓ 商店/行动/道具/仁慈四个子面板的点按命中（代码已写、菜单项点按已验证，子面板未逐项实测）
- ❓ 上游是否愿意统一坐标约定；`tCursor` 模板依赖 `showCursor`，真机行为待验

## 2026-10-04 · 步骤 6 · runtime=simulator · 接入 core 的「render 只输出绝对坐标」契约

core 交付（fengari + Lua 5.1 双运行时 **141 PASS / 0 FAIL**）后改了三处适配层：

1. **删掉按框位置猜偏移的启发式**：`M.render` 现在只输出绝对 640×480，`OFFX/OFFY` 固定 0。
   本地扫描 1200 帧确认 **box 命令 0 次越界**（永远满足 `0<=x,y` 且 `x+w<=640, y+h<=480`）。
   截图核对：脚本框 (239,226,404,391) 画在画布 518..766 ✓ 与 zone 完全一致。
2. **正弦骨改用 core 的 `bars`**：核对数值 `centerY=544.16`（−226 = 318.16 ≈ 框中线）、`gap=25`、
   `amp=12.5`（= gap/2，**不是** 10）；`bars` 从最初的 `19×8`（命中盒尺寸）修成长骨
   `19×79.7` / `19×60.3` 后，适配层再加一次 `−226` 修正即严丝合缝贴住框的上下边。
   另加细长条绘制器 `drawBar`（矩形 + 两端等厚圆帽），避免 13px 骨球撑破 19px 宽的骨。
3. `M.update` 现在直接返回 cmds，适配层原有的分支已命中。

**未确认项 → 已查明一半**：最后一张截图与修复前逐像素相同，原因不是缓存而是**那一帧正弦骨还没进画面**
（core 的 dump：t=2.40 时摆在绝对 x≈1124 → 画布 x≈1846，仍在屏幕外；轮次在 2.8s 就切菜单了）。
画面右下那三个小 dumbbell 是**别的实体**（不是正弦骨），尚未定位——已给出像素坐标供后续核对。

**新发现（已反馈 core）**：sine 的 `centerY`/`bars`/`hit` 被 `shiftAbs` 多平移了一次 `BOX_OFF_Y`
（452 = 226 + 226，它把 452 当成「框顶」，而战斗框命令的绝对坐标是 `(239,226,404,391)`）。
后果是**判定与视觉相差 226px**：我按回退后的 226 画（正确贴框），但 `hit` 中心在 544，
而灵魂在框内相对帧 → **正弦骨目前完全不造成伤害**（`sans_intro` 的骨成了纯装饰）。
修法已给出（sine 不走 `shiftAbs`），并要求补一条「灵魂站在可见长骨上应掉血 / 站在可见走廊里应不掉血」的行为回归——
这次正是几何自洽但跨帧比较才漏掉的。适配层暂时保留 `dy = -226` 的自校正，等 core 统一后再删。

## 2026-10-04 · 步骤 6 · 操作方式改造：PC 用 WASD、移动端用虚拟摇杆（去掉指针跟随）

用户反馈：双端都是鼠标指针跟随、战斗框到处移动。三处定位与修改：

**① 模拟器只转发数字键（真根因）**：`studio/play/browser-session.js` 的 `keyEventName()` 以前只把
`Digit1–9` 映射成 `KeyboardCraftspersonKeyN`，WASD/方向键**从来没有被转发过**——所以键盘在浏览器里必然无效。
已补上 `KeyW/A/S/D`、`Arrow*`、`Enter/Space/Z`、`Escape/X`、`Shift`、`J/F/E` → 对应的
`KeyboardMoveForward/MoveLeft/MoveBackward/MoveRight/MenuConfirm/MenuBack/Sprint/NormalAttack/InteractKey{Down,Up}`。
同步改了既有断言（原来是 `KeyA → ''`，现在应为 `KeyboardMoveLeftKeyDown`），`node --test studio/test/browser-session.test.mjs` **6/6 通过**，
`node scripts/build.mjs web` 重建，`web/public/play-renderer.js` 已含新映射，Web 服务已重启。

**② 游戏侧改成键盘 + 虚拟摇杆**（`lua/main.lua`）：
- PC：WASD/方向键 → 方向输入（原本就绑了，现在真能收到）；
- 移动端：屏幕左下**虚拟摇杆**——按住左半屏任意位置出现摇杆，拖动方向即移动方向（死区 9px，半径 46px）；
- 点按（未拖动就抬起、且不在摇杆区）：命中菜单项/子面板行/攻击条才生效；
- 删掉了「灵魂跟随鼠标」。

**③ 战斗框到处移动 = 松手即确认**：以前 `CursorUp` 处理成「兜底一次确认」，指针跟随时几乎每次拖动都会产生一次
点按 → 相位在 菜单/攻击/敌方 之间反复切 → 框在两个位置间来回跳。现在拖动（左半屏）是摇杆不产生点按，
且**点按没命中任何界面元素就什么都不做**。另外 core 侧核对过：60 秒里 box 命令只变化 2 次
（开场的 zone 调整 + 进菜单时上移 96px，后者是为了不与四个按钮重叠，属设计内行为）。

**实测证据（runtime=simulator）**：

```
main start: mode=core pool=346 flash=true cursor=true
main: 移动 L joy=(0.00,0.00) soul=(247,287)     ← 纯键盘：KeyboardMoveLeftKeyDown 生效，灵魂左移
main: mode=core frame=151 … phase=menu joy=on(0.00,0.00)  ← 摇杆已激活
（截图）摇杆底座画在按下点 (400,400)、摇杆头被拖向右上；菜单「攻击」高亮、战斗框居中
空地点按后 step 0.6s → 无「阶段 menu → …」日志  ← 误确认已消除
```

**未验证**：浏览器里真实按下 WASD 的端到端手感（页面映射已改并重建，但我没有浏览器工具，
只能保证 bundle 里含新映射 + 游戏侧 key 链路实测通过）；真机未跑。

## 2026-10-04 · 步骤 6 · sine 坐标系与判定口径确认（C20）

core 修完两处后，我在本地 dump 核对（`lua/_sine.lua`）：

```
box=(239,226,165,165)                 ← 与 sans_intro 的 zone 一致
bar1 = (884.5, 226.0) 19x79.7         ← y == zone.t，下沿 305.7 = 走廊口
bar2 = (884.5, 330.7) 19x60.3         ← 走廊口 → 框底 391
centerY=318.16 gap=25 amp=12.5         ← 走廊中心 = 框中线
适配层 dy=0                            ← 我此前的「回退 226」自校正已自然失效
```

**确认判定口径（新增契约 C20）**：正弦骨的命中体 = **屏幕上那两根长骨**，`gap` 走廊安全；走廊宽度恒为 `gap`。
采纳理由：19×19 的写法会造成「站在看得见的长骨上不掉血、只有一个走廊中心的隐形方块咬人」，
与 C14/「画什么打什么」原则冲突，且比现在**更宽松**（旧写法只覆盖 gap 中间的 19px 缝）。
已写入 `docs/gdd.md` C20，并给出可观察断言（站长骨掉血 / 站走廊不掉血 / `bars[1].y == zone.t`）。

core 顺带修的两处假伤害也确认合理：① 回合 0 不再补发那枚原版永远打不出来的炮（`BlackScreen,1` 会清空弹幕）；
② 自测夹具 `clearHazards(g)` 隔离脚本弹幕污染 —— 我写集成用例时会复用。

**注意（玩法影响）**：正弦骨此前「有视觉、无判定」，现在会真的打人，所以回合 0 与含 SineBones 的关卡
（`multi*` 的 Attack7）难度上升 —— 这是修 bug 而非调难度，无需改数值。

## 2026-10-05 · 步骤 7 · runtime=simulator · 输入按平台分流 + 指针 Y 轴根因 + 标题页去框

用户报的三个问题：① PC 也在用摇杆且上下颠倒 ② 标题页白框压在四张难度卡上 ③ 我方四个选项框点不动。

**根因（两条都在源码里核实，不是推断）**：

1. **指针事件的 y 是「左下原点、Y 向上」，而适配层当时按「Y 向下」直接用** —— 于是**所有点按上下镜像**：
   点在屏幕底部的按钮行上 → 世界坐标算到屏幕上方 → 「点了没反应」；摇杆同理往上拖却给下方向 → 「上下颠倒」。
   出处：试玩页 `dist/play-renderer.js`：`function W(w,V){return hv(w,V.getBoundingClientRect(),o.canvasWidth,o.canvasHeight)}`、
   `hv(){y:(t.bottom-i.clientY)*r/t.height}`（DOM 的 clientY 向下增大 → 该式是「离画布底边的距离」）；
   引擎盒子 `Ne()` 也是 `bottom = parentBottom + anchorMinY*H + anchoredPositionY - sizeY*pivotY`（从下往上量）。
   修法：`M.toWorld(px,py) = ((px-OX)/S, H - (py-OY)/S)`，**只翻一次**。
2. **命中框写死在按钮矩形之外**：文字画在 `y+22`，命中判定却是 `y-6..y+34` —— 看得见的字点不到。
   现在绘制与命中**共用** `menuButtonRect/menuHitTest`、`subRowRect/subHitTest`，行 y 取本帧实际绘制的 `lastMenu/lastSub`。

**平台分流（`game.GetDevice()`，取值来自 worker.js/enums.js 原文）**：
`Device:["KeyboardAndMouse","Mobile","Controller","MobileController"]`（`GetDevice:r=>(i.pushEnumItem(r,rt("Device",i.device)),1)`，
默认 `KeyboardAndMouse`）；画布档位 `pc-16-9/pc-21-9 → luaDevice:"KeyboardAndMouse"`、`mobile-* → "Mobile"`。
**只有确切等于 Mobile / MobileController 才走触摸分支**，其余（含读不到值）一律按 PC。
- PC：只绑键盘（`KeyboardMoveForward/Backward/Left/RightKey{Down,Up}`、`KeyboardMenuConfirmKeyDown`、
  `KeyboardNormalAttackKeyDown`、`KeyboardMenuBackKeyDown`）；鼠标只点 UI，**没有摇杆**；顶部提示「WASD 移动 · Enter 确认」。
- 触摸：只收指针，**不注册任何键盘监听**；左半屏拖动 = 摇杆；点按 = 二次确认（第一次选中 + 「再 点 一 次 确 认」提示，
  再点同一项才确认，点空白取消）；顶部提示「左半屏拖动移动 · 点击选项选中，再次点击确认」。
- 摇杆**只在敌方阶段**存在：其它阶段 core 不读方向输入，起了只会把点按吞掉（攻击条阶段点左半屏原本结算不了）。

**标题页去框**：`state=='title'` 时跳过 `box` 命令的绘制（core 仍会推这条命令，战斗态照旧画）。
另外修了 `drawHud` 的对齐：core 传小写 `'center'/'left'/'right'`，而引擎枚举只认 `Left/Middle/Right`，
无效值退回左对齐 → 标题与四张卡的注释整体右移 170px（看着像注释挂错卡片）。

**实测证据（runtime=simulator，build=2026-10-05-input-split-2）**：

```
# 触摸（mobile-19.5-9，1560×720，OX=300 S=1.5）
main start: build=2026-10-05-input-split-2 device=Mobile touch=true
main: 触摸点按难度卡 1 → 选中（再点一次开局）        ← 第一次点只选中
main: 点按难度卡 1 → 开局                          ← 第二次点才开局
main: 游标 CursorDown x=510.0 y=88.5               ← 世界(140,421) 的画布坐标（Y 向上）
main: 触摸点按菜单第 1 项（攻击）→ 选中（再点一次确认）
main: 阶段 menu → attack
main: 移动 U joy=(0.00,-1.00) soul=(320,283)       ← 往上拖，灵魂 y 变小（不颠倒）
main: mode=core … phase=menu soul=320,234 joy=off  ← 菜单阶段摇杆不存在（不吞点按）
# PC（pc-16-9，1600×900）
main start: build=2026-10-05-input-split-2 device=KeyboardAndMouse touch=false
main: 移动 U joy=(0.00,0.00) soul=(320,283)        ← 纯键盘（joy 恒 0，PC 无摇杆）
```
截图：`records/pc-title-no-box.png`（标题页无白框、四卡不重叠、标题居中）、
`records/pc-battle-menu.png`（框下按钮行 + 右上 PC 键位提示 + ROUND 右对齐）、
`records/touch-joystick-up.png`（摇杆头画在底座**上方** = 往上拖）。

**离线回归**：`lua/_tap.lua` 39 条、`lua/_title.lua` 33 条、`lua/_input.lua` 90 条（新增，PC/触摸双平台）、
`lua/_flow.lua` 全绿；`node tools/build-save.mjs` 重建存档（259861 B）+ `verify-client-pool` PASS 9/9。

**未验证 / 待办**：

- ❗ **插件自带试玩页不转发 WASD**：`dsh-plugin/dist/play-renderer.js` 里 `Yu()` 只把数字键转成
  `KeyboardCraftspersonKeyN`，没有语义键表 → 在插件试玩页里按 WASD 不会有任何事件。
  修法与完整键位表见 `docs/plugin-keymap.md`（模拟器仓库 `web/public/play-renderer.js` 已经带上该表）。
  修好之前，PC 键控可用 `play {action:"key"}` 注入验证（本次就是这么验的）。
- `runtime=device`：真机未跑；键盘枚举里没有 `MenuConfirmKey`（只有手柄侧有），真机上 Enter 是否派发
  `KeyboardMenuConfirmKeyDown` 仍需真机确认（当前同时绑了 `KeyboardNormalAttackKeyDown` 作备用确认）。
- 触摸的「二次确认」是否该覆盖标题页难度卡（现已覆盖，且再点同一张才开局）——若觉得两步太慢可只保留菜单/子面板。

## 待补

- `runtime=web · browser-run: user`：用户在 `http://127.0.0.1:4173/editor` 实际试玩的手感与截屏反馈
- `runtime=html · browser-run: user`：用户打开 `prototype/index.html` 的实玩反馈（本会话无浏览器工具）
- `runtime=simulator`：用 `play {key}` 驱动灵魂验证输入链路；推进到 R1–R6 与中场
- `runtime=simulator`：`runCase` 回归（`tests/*.json` 里的 8 个用例需要按当前存档重录，旧用例指向探针脚本）
- `runtime=device`：步骤 7，千星奇域真机试玩 + GIA 导出 + 手动挂脚本
