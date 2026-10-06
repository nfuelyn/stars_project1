# Bad Time Simulator（jcw87/c2-sans-fight）研究笔记

> 来源：[在线站](https://jcw87.github.io/c2-sans-fight/)（标题 *Bad Time Simulator (Sans Fight)*）
> 与开源仓库 [Jcw87/c2-sans-fight](https://github.com/Jcw87/c2-sans-fight)（Construct 2 工程，"Undertale Sans Fight Clone"）。
> 本笔记读的是仓库的**文档 + 攻击数据文件**（`Documentation/*.md`、`Files/sans_*.csv`、`Textures/*`），
> 没有去啃 628KB 的 `Event sheets/Battle.xml`。所有数值都来自原文件，不是推测。

这个工程的价值：它把 Sans 战做成了**数据驱动的攻击脚本系统**——每种攻击是一个 CSV 时序表，
每行 `延时, 命令, 参数...`。这正好是我们千星侧 Lua 架构可以直接抄的作业。

## 1. 攻击脚本语言（来自 `Documentation/*.md`）

### 单位与约定（**校准我们数值的关键**）

| 项 | 约定 |
|---|---|
| **速度** | px/秒。**"把原作数值 × 30（FPS）就是这里的等效值"**（原作按 30fps 的 px/帧计量） |
| **方向 Direction** | 0=东，每 +1 顺时针 90°（0 东 / 1 南 / 2 西 / 3 北） |
| **颜色 Color** | **0 白 / 1 蓝 / 2 橙** |
| 时间 | 秒；角度 | 度；布尔 | 0/1 |

### 弹幕命令

| 命令 | 参数 | 说明 |
|---|---|---|
| `BoneH` | X, Y, Width, Direction, Speed, Color | 横向骨头 |
| `BoneV` | X, Y, Height, Direction, Speed, Color | 纵向骨头 |
| `BoneHRepeat` / `BoneVRepeat` | StartX, StartY, Width/Height, Direction, Speed, Count, Spacing | 批量骨头 |
| `SineBones` | Count, Spacing, Speed, Height | 正弦骨（作者自称"当年偷懒做的"，留缝是正弦形） |
| **`BoneStab`** | **Direction, Distance, WarnTime, StayTime** | **从战斗框侧面弹出的骨刺墙——自带 `WarnTime` 预警** |
| `GasterBlaster` | Size, StartX, StartY, EndX, EndY, EndAngle, SpinTime, BlastTime | 龙骨炮：移动到位 → 旋转 → 开火 |
| `Platform` / `PlatformRepeat` | X, Y, Width, Direction, Speed, (BooleanReverse), Count, Spacing | 平台 |

### 灵魂与战斗框

| 命令 | 参数 | 说明 |
|---|---|---|
| `HeartMode` | 0 红 / 1 蓝 | 切换灵魂模式 |
| `HeartTeleport` | X, Y | 灵魂瞬移（开局摆位/演出用） |
| `HeartMaxFallSpeed` | MaxSpeed | **砸落速度可调 → 对应原作"低速/中速/高速重力"三种砸** |
| `SansSlam` | Direction | 把灵魂往某方向砸 |
| `SansSlamDamage` | 0/1 | **可以关掉砸击伤害 → 这就是"壁ドン不致死"的实现方式** |
| `CombatZoneResize` | L, T, R, B, FinishAction | 带动画的框体变形，完成后执行 `FinishAction`（一般是 `TLResume`） |
| `CombatZoneResizeInstant` | L, T, R, B | 瞬间变形 |
| `CombatZoneSpeed` | Speed | 变形速度 |
| `GetHeartPos` | X变量, Y变量 | 读灵魂坐标 |

### 流程与表现

`BlackScreen`(0/1，同时清空弹幕)、`Sound`、`Music`、`TLPause`、`TLResume`、`EndAttack`(**不调用攻击永不结束**)；
Sans 侧：`SansAnimation`(Idle/HeadBob/Tired)、`SansBody`(HandUp/Down/Left/Right)、`SansTorso`(Default/Shrug)、
`SansHead`(Default/LookLeft/Wink/ClosedEyes/NoEyes/BlueEye/Tired1/Tired2)、`SansSweat`(0–3)、
`SansX`、`SansRepeat`/`SansEndRepeat`（左右滑动）、`SansText`（气泡台词）。

### 脚本控制（`Jumps.md` / `Math.md`）

- **标签**：第 2 列填 `:名字` 即可被跳转；标签行的时间延时仍然生效。
- **跳转**：`JMPABS` / `JMPREL` / `JMPZ` / `JMPNZ` / `JMPE` / `JMPNE` / `JMPL` / `JMPNL` / `JMPG` / `JMPNG`（都带 绝对行号 + 1~2 个测试值）。
- **变量**：`$变量名` 取值。
- **数学**：`SET/ADD/SUB/MUL/DIV/MOD/FLOOR/DEG/RAD/SIN/COS/ANGLE/RND`。

## 2. 逐行解码两个真实攻击（`Files/*.csv`）

### `sans_intro.csv` —— **回合 0「不意打ち」**（这就是原作开局偷袭）

```text
0        SansText, ready?                    ← 台词「ready?」
0        BlackScreen 1 / Sound Flash / BlackScreen 0   ← 黑屏闪白（登场演出）
0        CombatZoneResizeInstant 239,226,404,391        ← 战斗框 165×165（640×480 画布）
0        HeartTeleport 320,304               ← 灵魂先摆到 (320,304)
0        HeartMode 0                          ← 红魂
0        SansBody HandDown / SansHead BlueEye ← 抬手下压 + 蓝眼
0.26666  SansSlam 1                           ← 把红魂往下砸（方向 1=南）
0        BoneStab 1, 54, 0.16666, 1           ← 骨刺墙：方向南、距离 54、**预警 0.16666s**、停留 1s
0.4      SineBones 20, -24, 360, 25           ← 20 根正弦骨，间距 -24、速度 360px/s、高 25
0.4~     GasterBlaster ×8 (Size 1) + ×4 (Size 2)，SpinTime 0.333/0.666、BlastTime 0.2667/0.5
3        SansText, here we go. + EndAttack     ← 结束偷袭
```

**要点**：`BoneStab` 的预警原文只有 **0.16666s（5 帧）**；我们用的 **0.5s** 是刻意放宽的可读性改动（用户指定）。
`SineBones` 的"正弦骨"就是我们 R1 里想做的"骨缝穿越"的原版做法。

### `sans_bluebone.csv` —— **蓝骨 + 白骨交替**

```text
0        CombatZoneResize 133,251,508,391,TLResume   ← 带过渡的变形，完成后续跑
0        HeartTeleport 320,376 / HeartMode 1         ← 蓝魂
0        TLPause
0.2      BoneV 503,286,100,2,300,1    ← X=503 Y=286 高100 方向西 速度300 **颜色1=蓝**
0.23333  BoneV 503,366, 20,2,300,0    ← 同侧、高20、**颜色0=白**
0.5      BoneV 503,286,100,2,300,1    ← 再来一组……
0.93333  BoneV 128,366, 20,0,300,0    ← 换成从左侧向东的白骨
…
1.66666  EndAttack
```

**要点**：**蓝骨（高 100）与白骨（高 20）成对出现**——蓝骨横穿时你必须静止，紧接着的小白骨必须动。
这就是攻略里"青骨静止、青骨过去瞬间最小跳"的原始写法。**我们之前只做了蓝骨，没有白骨配对，更没有橙骨。**

## 3. 攻击清单（`Files/` 目录即原作的回合表）

`sans_intro`（回合 0）· `sans_bonestab1/2/3`（骨刺）· `sans_bonegap1 / bonegap1fast / bonegap2`（骨缝穿越）·
`sans_boneslideh / boneslidev`（横/纵滑行骨）· `sans_bluebone`（蓝骨）· `sans_platforms1/2/3/4 / platforms4hard`（平台）·
`sans_platformblaster / platformblasterfast`（平台+炮）· `sans_randomblaster1/2` · `sans_multi1/2/3`（多段混合）·
`sans_final`（最终回合，5.6KB，最长）· `sans_spare`（饶恕）。

贴图里还有一枚 **`Textures/BoneStabWarn.png`**——即"骨头冒头/预警"的专用素材，佐证 `WarnTime` 那段是**先出预警再弹刺**。

## 4. 对照我们的实现：采纳 / 修正 / 不做

| 项 | 工程做法 | 我们的现状 | 结论 |
|---|---|---|---|
| **橙骨（Color=2）** | 有 | ❌ 完全没有 | **已采纳**：橙=必须移动，蓝=必须静止，交替生成 + 画图例 |
| `BoneStab.WarnTime`（冒头预示） | 0.16666s | ✅ 已有 0.5s（用户指定） | 保留 0.5s（更友好），**参数名对齐** |
| 速度换算 | 原作值 × 30 | 我们自定 150–230px/s | **已记录**：原作档速度 ×1.25 作为第一步逼近（真按换算会接近 ×2.9，留给后续专项调） |
| 蓝骨**配对白骨** | 蓝骨+白骨成对 | ⚠️ 只有蓝骨 | **待做**：R3 改成"蓝骨 → 紧跟白骨"的成对节奏 |
| 战斗框连续变形 | `CombatZoneResize` + 速度 + 完成回调 | ⚠️ 3 档固定尺寸 | **待做**：框体带过渡（千星侧用 `Tween`/逐帧插值） |
| `HeartTeleport` | 有 | ❌ 没有 | 待做（演出用） |
| `SansSlam` + `SansSlamDamage` | 砸击方向 + **可关伤害** | ⚠️ 我们的重力是持续向下的蓝魂 | **待做**：真正的"砸"（含低速/中速/高速三档，用 `HeartMaxFallSpeed` 思路）+ 不伤人的壁ドン |
| 攻击脚本形态 | **CSV 时序表 + 标签/JMP/数学/RND** | Lua 里写死的状态机 | **架构采纳**：步骤 5 把 6 个回合改成**表驱动**（`{t, cmd, args}` 列表 + 跳转），便于加回合、调参、移植 |
| GasterBlaster 细节 | Size/起点/终点/终角/**SpinTime**/BlastTime | 只有 charge/fire 两段 | **待做**：加"移到位置+旋转"的蓄力段 |
| 灵魂模式 | `HeartMode` 0/1 | ✅ 红/蓝 | 一致 |
| Sans 表情/身体 | 8 种头 + 4 种身 + 汗 + 气泡 + 左右滑动 | 只有几何占位 + 台词 | P1（千星侧可用客户端模板做表情切换） |

## 5. 移植到千星时的硬约束

- 他们画布 **640×480**，框体坐标是绝对值；我们设计板 **1280×720**（手机 16:9 基准），坐标要按比例换算，**不能照抄像素**。
- 千星控件是**轴对齐矩形**，没有 canvas 的 `arc/bezier`；他们的骨头/骨头炮都是**贴图**（`BoneV.png`、`GasterBlast1/2/3.png`），
  我们用细长图片控件拼——比他们"用贴图"更原始，但可行。
- 他们的 `EndAttack` 语义（不调用就永不结束）值得照搬：我们的回合结束条件也应显式化，避免"回合卡死"。

## 6. 从 .ref/data.js 解出的布局常量（`node .ref/resolve.mjs`，原型追溯）

本仓库 `.ref/` 存的是该站的 Construct 2 工程数据 `data.js`（640×480）。`resolve.mjs` 解析出**类型表 + BattleScreen 各图层实例**，
下面这些就是本轮视觉修正直接照抄的数值（不是推测）：

| 对象 / 图层 | 常量 | 用途 |
|---|---|---|
| `gasterblaster-sheet0.png` | 帧 **57×44** | 龙骨炮炮身尺寸 —— 骷髅整体包围盒要对齐它（我们做到 ≈59×44） |
| `sanshead / sansbody / sanslegs / sanstorso / sanssweat` | 32×30 / 64×70 / 44×23 / 54×25 / 32×9 | 审判者本人各零件（`drawSans` 逐件照抄） |
| `playerheart-sheet1.png` | 16×16 | 灵魂 |
| `hp-sheet0.png` / `kr-sheet0.png` | 23×10 | HP / KR 血条小条 |
| 图层 `Background` | `HP` 文本 @(416,400) 128×20；`PlayerName` @(32,402) 192×20；血条 @(224,416)/@(400,416) | **等级/血量 UI 在选项栏正上方**（y≈400~426）——本轮 HUD 搬家的依据 |
| 图层 `Buttons` | uifight(32,432) uiact(184,432) uiitem(344,432) uimercy(496,432)，均 110×42 | 按钮行 y=432（我们 `menuRowY` 已对齐） |
| 图层 `CombatZone` | playerheart @(320,320) 16×16 | 红心基准位 |
| 图层 `Overlay` | 战斗框 [X1,Y1,X2,Y2] = 33,251,608,391 | 大框矩形 |

另外 `Documentation/Attacks.md` + `Files/sans_*.csv` 的口径（速度 ×30、方向 0=东顺时针、颜色 0白/1蓝/2橙、
`GasterBlaster Size,StartX,StartY,EndX,EndY,EndAngle,SpinTime,BlastTime`）在 `docs/attack-manifest.md` 与 `records/lua-port.md` 里有逐条对照。

## 7. 蓝心跳跃的原版参数（直接来自 `Event sheets/Battle.xml` → 「PlayerMovement」事件组）

原版 `c2-sans-fight` 仓库（`git clone https://github.com/Jcw87/c2-sans-fight`）里，蓝魂跳跃不是"按住加力"，
而是「**一次冲量 + 分段重力 + 按住托底**」，常量就在 Battle 事件表里：

| 常量 | 值 | 含义 |
|---|---|---|
| `HEART_JUMP_STRENGTH` | **180** | 起跳冲量（px/s）。设为 `dy - Y*180`（Y 是输入方向） |
| `HEART_JUMPHOLD_CUTOFF` | **30** | 按住方向键时的"托底速度"：**4 个方向都用了这个常量**（上/下/左/右各一段：慢了就抬到 ±30）。所以它同时是"按住上升"的速度 |
| `Gravity` | **540 / 180 / 450 / 180** | **四档**，用 `DownSpeed = -dy` 判定（XML 里是 4 个并列事件，靠后的覆盖前面的）：`15 < DownSpeed < 240`（即 **dy < -15**，上升中）→ 540；`-30 < DownSpeed ≤ 15`（-15 ≤ dy < 30，顶点附近）→ 180；`-120 < DownSpeed ≤ -30`（30 ≤ dy < 120，下落）→ 450；`DownSpeed ≤ -120`（dy ≥ 120，快落）→ 180 |
| `MaxFallSpeed` | **750** | 下落速度上限 |
| `HeartSpeed` | **150** | 蓝魂横向移动速度 |

换算关系：BTS 与我们的世界**同为 640×480、单位同为 px/s** → 这五个数**1:1 直接用**，不需要 ×1.5 或 ×30。
现在 `core.lua` 里的 `JUMP_STRENGTH / MAX_FALL_SPEED / gravityFor()` 就是照抄这一组（见 `lua/core.lua` 顶部注释）。
就是照抄这一组（见 `lua/core.lua` 顶部注释）。

> 注意：托底必须写成「慢了才抬上来」（`vy > -30 → vy = -30`）。写成 `vy < -30 → vy = -30` 会把起跳的 -180
> 当场砍成 -30，跳都跳不起来（第一轮踩过）。
> 当场砍成 -30，跳都跳不起来（本轮踩过）。
## 8. 从事件表逐条核对后的修正（2026-10-05）

把 `Event sheets/Battle.xml` 里每个攻击函数的实现读了一遍，逐条对照我们的 Lua 引擎：

| 函数 | 原版实现（Battle.xml） | 我们的状态 |
|---|---|---|
| `BoneV` / `BoneH` | `X=int(P0)`、`Y=int(P1)`、`Height=int(P2)`；实例变量 `Damage=1`、**`Karma=6`**；`BoneV` 建在 `CombatZoneClipped` 图层（**裁到战斗框内**），`BoneH` 建在 `CombatZone` 图层（**不裁**） | 锚点/判定已对齐（左上角）；Karma 已改 6；**裁剪已实现**（见 §9） |
| `BoneHRepeat` / `BoneVRepeat` | `X = StartX - cos(dir*90)*Spacing*i`、`Y = StartY - sin(dir*90)*Spacing*i` → **排在来向** | ✅ 已按同一规则修过（东行往西排 …） |
| `SineBones` | `Sine = floor(sin(i/3) * 28)`（幅度固定 28、相位 i/3）；Spacing>0 从**框右**、<0 从**框左**排开；上骨 `Y=框顶+6`、高 `Height+Sine`；下骨从 `上骨底+39` 铺到 `框底-5` | ✅ 本轮按原版重写（旧版是"框中线 ± Height/2 的动画正弦"，几何完全不同） |
| `GasterBlaster` | 飞到位 → 旋转到 EndAngle → 开火；`GasterBlastHit.Karma=10` | ✅ 飞行/旋转/开火已实现；Karma 已改 10 |
| `Platform` / `PlatformRepeat` | 平台按 `Direction/Speed` 平移，`BooleanReverse` 到边界掉头；`PlatformRepeat` 与骨头同样"排在来向" | ✅ 平移/掉头已实现；本轮补上"**站在平台上会被平台带着走**" |
| `BoneStab` | 从战斗框侧面弹出，`WarnTime` 预警 → 伸出 `Distance` → 停留 `StayTime` → 收回；`Karma=6` | ✅ 同结构 |
| 蓝心跳跃 | `HEART_JUMP_STRENGTH=180`、四档 Gravity 540/180/450/180、`MaxFallSpeed=750` | ✅ 2026-10-05 第三轮按原版四档**重新落实**（见 §10）；用户口径的"按住变高"另加 0.40×框高/秒的托底 |

（此处的“已知视觉差异”已在 2026-10-05 第二轮修掉，见 §9。）

## 9. CombatZoneClipped：只有竖骨会被裁到战斗框内（2026-10-05 第二轮）

来源：`Event sheets/Battle.xml` 的 `Create object` 动作里每种对象的 `Layer` 参数，
以及 `CombatZoneTick` 里对 `CombatZoneClipper` 的摆位动作。

### 9.1 图层表（逐字核对）

| 对象 | 图层 | 效果 |
|---|---|---|
| `BoneV` / `BoneVRepeat` | `CombatZoneClipped` | 被裁 |
| `BoneStabV` / `BoneStabH` | `CombatZoneClipped` | 被裁（但骨刺本来就生在框边，裁不裁一样） |
| `BoneH` / `BoneHRepeat` | `CombatZone` | **不裁** |
| `GasterBlaster` | `CombatZone` | **不裁**（炮身要从屏幕角飞进来，必须露出框外） |
| `CombatZoneBorder` | `Overlay` | 画在最上层 |

裁剪不是引擎的图层裁剪，而是**4 块黑色 `CombatZoneClipper`（TiledBg）**盖在
`CombatZoneClipped` 图层的框外区域上。`CombatZoneTick` 里的四个实例：

```text
#0  X=-10, Y=-10           Size(LayoutWidth+20, CombatZone.Y+10)   -- 上
#1  X=-10, Y=CombatZone.Y  Size(CombatZone.X+10, ...)             -- 左
#2/#3                                             ...             -- 右 / 下
```

所以视觉结果是：竖骨只有落在战斗框内的那段能被看见（横骨/龙骨炮可以露到框外）。

### 9.2 我们的等价实现（`lua/core.lua` 的 `clipVZone`）

我们只有 7 种图元、没有裁剪层，于是直接把**竖骨的矩形裁进 `world.zone`**：

* 灵魂永远被钳在框内 → 「裁后矩形」与「整根骨头」的命中结果**完全等价**；
* 同一份裁剪同时喂给**碰撞循环**和**渲染出口** → 「画出来的 == 打得中的」这条不变式继续成立；
* 整根在框外的竖骨这一帧直接不输出控件（省控件，也避免框外闪光）。

`_geometry.lua` 的 B 段（绘制 == 判定）与 `core_selftest.lua` 的 `clip-zone` 段都按这条契约断言。

## 10. 蓝心跳跃：四档重力 + 按住变高（2026-10-05 第三轮）

> ⚠ 本节已被 §11 取代（用户第五轮改成「按住匀速上升 / 松开等速下降」）。原版四档重力仅作记录。

玩家反馈「蓝心缺失了随按键时长改变高度的特性」。查 `Battle.xml` 发现**旧实现把 180/540 用反了**：

| | 旧实现（错） | 原版（`Battle.xml` 四档） |
|---|---|---|
| 上升中 | `vy < -30` → **180** | `dy < -15` → **540** |
| 顶点附近 | — | `-15 ≤ dy < 30` → **180** |
| 下落 | `vy > 240` → **540** | `30 ≤ dy < 120` → **450** |
| 快落 | 中段 450 | `dy ≥ 120` → **180** |

后果（`探针_probe_jump（该一次性探针已在“lua 目录瘦身”轮清理，数值结论保留）` 实测，框高 140）：

```text
旧：轻按 87.0px（0.62 框高）  按住 1.0s 90.4px  按住 1.5s 101.6px   ← 跳太高 + 按住几乎没手感
新：轻按 28.7px（0.205 框高） 按住 0.5s 43.9px  按住 1.0s 71.9px（0.513 框高）
```

改动两处（`lua/core.lua`）：

1. `gravityFor(vy)`：按原版四档取值（上升 540 → 起跳弹道只有 ~0.2 框高）。
2. 「托底」**挪到重力之后**：原来夹在重力之前，每帧先被重力吃掉 18px/s，净上升只剩 2/3。
   托底速度取 `0.40 × 框高/秒` → 轻按 0.2 框高、**按住 1s ≈ 0.5 框高**，且随按住时长**线性**增长
   （原版是固定 30px/s，1s 只到 ~0.36 框高；这里按用户口径换成框高比例）。

回归：`core_selftest.lua` 的 `blue-jump` 段把「轻按 1/5 框高 / 按住 1s ≈ 1/2 框高 / 单调 / 每 0.5s 增量相等」四条钉住。

## 11. 蓝心跳跃改为「按住匀速上升 / 到顶悬停 / 松开等速下降」（2026-10-05 第五~六轮，用户口径）

用户口径（第七轮）：**上升 0.55s、下落 0.9s（比上升慢）；下降过程中不能二次跳跃；长按不能无限飞升；首轮龙骨炮出现→释放 0.6s。**
（第五轮原话是 0.7s，第六轮改成 0.6s 并补上「到顶悬停」「松手剪断」两条。）

这是一条**明确偏离原版**的规则（原版是冲量 + 四档重力的弹道），实现写在 `lua/core.lua` 蓝魂物理段：

```lua
local riseSpeed = 0.5 * self.box.h / JUMP_RISE_T   -- JUMP_RISE_T = 0.55
    local fallSpeed = 0.5 * self.box.h / JUMP_FALL_T   -- JUMP_FALL_T = 0.9（下落比上升慢）
local maxRise   = 0.5 * self.box.h                 -- 1/2 框高就悬停
if not self.jumpHeld then self.soul.jumpCut = true end   -- 松手即「剪断」本次跳跃
if self.soul.jumping and self.jumpHeld and not self.soul.jumpCut then
  local risen = (self.soul.jumpBase or self.soul.y) - self.soul.y
  self.soul.vy = (risen >= maxRise) and 0 or -riseSpeed   -- 到顶悬停，不无限飞升
else
  self.soul.vy = riseSpeed        -- 松手后再按也不回升（不能二段跳）→ 等速下降
end
```

* 上升速度 = `0.5 × 框高 / 0.55s`；框高 140 → **127.3px/s**（按 0.55s 正好 70px = 1/2 框高）
* 上升完全线性；松开当帧换向，**下落速度 = 0.5 × 框高 / 0.9s**（框高 140 → 77.8px/s，0.9s 落回地面，比上升慢）
* **松手后本次跳跃被剪断** → 下降途中再按跳跃键不会重新上升
* 上界 = **起跳点上方 1/2 框高**（到顶悬停，长按不会无限飞升）；另加战斗框上沿兜底
* 红魂完全不走这一支

实测（`探针_probe_jump（该一次性探针已在“lua 目录瘦身”轮清理，数值结论保留）`，框高 140）：

| 按住 | 上升高度 | 占框高 |
|---|---|---|
| 0.35s | 44.5px | 0.318 |
| 0.5s | 50px | 0.357 |
| **0.55s** | **70px** | **1/2** |
| 1.0s | 70px | 1/2（悬停，不再上升） |
| 2.0s | 70px | 1/2（悬停） |

### 11.1 顺带修掉的：脚本骨的颜色语义

`Documentation/Attacks.md`：`Color` 0 白 / 1 蓝 / 2 橙。但脚本骨的碰撞分支**从来没看颜色**
（`if rectHit(...) then self:hurt('hit') end`），渲染也只会认字符串 `'blue'`/`'orange'` 而不是数字 ——
所以脚本里的 `BoneV,...,1`（蓝骨）以前等于白骨，画出来也是白的。

现在：渲染认数字（0/1/2）；碰撞按内置蓝/橙骨同一套 `moved` 语义 —— 蓝骨只有「移动」扣血、
橙骨只有「静止」扣血、白骨无条件扣血。第四回合的高骨正是靠这条才成立。

### 11.2 第六轮澄清：蓝高骨是给「左右高低骨组合」的，不是 ROUND 4

用户原话：「round4 的上方不需要是蓝骨，我说的是**左右高低骨进入的组合**时高骨为蓝骨」。

| 脚本 | 结构 | 高骨颜色 |
|---|---|---|
| `sans_bonegap1` / `sans_bonegap1fast`（ROUND 3 / 5） | **左右两侧各自出一高一矮** | **蓝骨 Color=1** |
| `sans_boneslideh`（ROUND 4） | 矮骨只从左边来、高骨只从右边来 | 白骨（恢复） |

批量命令 `BoneVRepeat` 在官方文档里**没有 Color 参数**，所以本项目给它加了第 8 个可选参数
（`Color`，不传 = 0 = 白），这样「左右高低骨」两行批量骨也能直接写成蓝骨。

## 12. 重读整仓库后的判定/模板修正（2026-10-05 第十二轮）

按用户要求把仓库**重新完整克隆**到 `D:\c2-sans-fight-src`（commit `0bb6afe`）逐文件读了一遍：
`Event sheets/Battle.xml`（事件表全文）、`Files/sans_*.csv`（24 个脚本）、`Documentation/*.md`、
`Layouts/*.xml`、`Textures/*.png`（逐张量了尺寸）、`Bad Time Simulator (Sans Fight).caproj`（对象定义）。

### 12.1 骨头厚度：19 → **10**（判定 + 外观一起改）

`Textures/BoneV.png` = **10×24**、`Textures/BoneH.png` = **24×10**；脚本只 `Set height` / `Set width`，
所以竖骨恒 **10 宽**、横骨恒 **10 高**（Construct 2 的 NinePatch 碰撞盒 = 整个对象矩形）。
我们原来 `BONE_W = 19`（自绘外观拍的值）→ 判定比原版粗了近一倍，正是「擦着骨头过去却掉血」的来源。
现在 `BONE_W = 10`，`drawBone` 的骨干/骨帽按当前厚度收缩（不再写死 7/13），`_geometry` 的 `shaftOf` 同步。

### 12.2 平台加速：`sans_platforms4` / `platforms4hard`（作者自己列的 Known Issue）

仓库 `readme.md` → **Known Issues** 原文：

> - Heart hitbox is probably not accurate.
> - On the sans_platforms4 and sans_platforms4hard attacks, the platform is supposed to accelerate from 0
>   to its full speed, but I was lazy and started it at full speed immediately.

第二条已经修：给 `Platform` 加了第 8 个参数 `Ramp`（几秒从 0 加到全速），`platforms4/4hard` 传 `1`；
「站在平台上被平台带着走」也改成用**当帧速度**（`p.vx`），不会出现平台没加速人却按全速被拖的情况。

第一条（红心判定盒）作者自己承认不准，而**仓库里没有 PlayerHeart 的贴图**（`Textures/` 里没有 heart 图），
所以精确尺寸无法从仓库反推 —— 我们只能沿用「心形图案有多大、判定盒就多大」这条用户口径（当前 `SOUL_R = 4`）。

### 12.3 已核对、确认一致的部分（本轮复查）

| 项 | 仓库真值 | 我们 |
|---|---|---|
| 竖骨锚点 | NinePatch 左上角 + 只设 height | ✅ 左上角矩形 |
| 批量骨排列 | `X = StartX - cos(dir*90)*Spacing*i` | ✅ |
| 正弦骨 | `Sine = floor(sin(i/3)*28)`、上骨 `Y=框顶+6`、走廊 +39 | ✅ |
| 骨刺 | 从框边向 dir 方向生长，`WarnTime` 预警 | ✅（判定按 `cur` 生长） |
| 龙骨炮 | 飞到位 → 转到 EndAngle → 开火；本轮的「出现→发射」= SpinTime(+HoldTime) | ✅ |
| 伤害/KR | 骨头 `Damage 1 / Karma 6`，龙骨炮 `Karma 10` | ✅ |
| CombatZoneClipped | 竖骨在那层被 4 块 Clipper 裁掉；横骨不裁 | ✅（clipVZone） |

## 13. 《Sans_Fight_差距与修改文档》逐条处理表（2026-10-05 第十三轮）

> 文档：`D:\stars\Sans_Fight_差距与修改文档.md`（699 行 / 50 条）。下表是**逐条**处理结果：
> 「已改」= 本项目按文档改了代码/数据；「本来就对」= 复查后我们已符合；「N/A」= 本移植版没有对应机制；
> 「保留差异」= 与文档相反，是用户明确要求或本项目刻意如此。

| 编号 | 结论 | 说明 |
|---|---|---|
| H-01 心判定盒 | **已改** | 原版判定物是 `PlayerHitbox` **4×4**（贴图 16×16）→ `SOUL_R 4 → 2` |
| H-02 蓝/橙基于 Is moving | 本来就对 | 我们就是按「帧位移 >1px」判 moved |
| H-03 橙色攻击零使用 | N/A | 引擎支持 Color=2，脚本里确实没用 |
| H-04 无敌帧 0.033s | **已改** | 「原作」难度 0.15 → **0.033s**（其余三档保留放宽，作为难度） |
| H-05 同帧多攻击只结算一次 | 本来就对 | 我们用 `invuln` 门控，同帧只吃一次 |
| H-06 平台侧面碰撞 disabled | **已改** | 侧面不再解算实体（只保留顶面吸附） |
| M-01 平台无加速 | **已改** | `Platform` 加 `Ramp` 参数，platforms4/4hard 传 1s |
| M-02 左右重力平台吸附 disabled | **已改** | 移除「站上平台被带走」 |
| M-03 重力分段常数 | 本来就对 | 四档 540/180/450/180 |
| M-04 夹取硬编码 5/8 | 本来就对 | 我们 `SOUL_CLAMP = 8`；判定盒另用 `SOUL_R` |
| M-05 减速键 150→75 | **已改（V-03 同源）** | 按住取消键移速减半 |
| M-06 MaxFallSpeed 负值 | 本来就对 | `clamp` 方向已按脚本值处理 |
| P-01 SineBones 自创 | 保留差异 | 我们按仓库实现**逐字复刻**（原版脚本里 sans_intro 就在用） |
| P-02 大量 RND / 固定序列 | **已改** | 整场改为文档 §1 的**原作固定编排**；回合总数 20 → 24（含终盘） |
| P-03 光束未纳家族 | 本来就对 | 光束是 blaster 的 state，随 world 一起清 |
| P-04 Repeat 丢 Color/Reverse | **已改** | `BoneVRepeat/BoneHRepeat/PlatformRepeat` 加可选第 8 参 |
| P-05 Size=0 不设高度 | 本来就对 | 我们的 Size 表 0/1/2 = 20/36/56 全部显式 |
| P-06 光束只在 leave 且 opacity>80 有效 | **已改** | 判定窗口加「淡出且 alpha>80/255 仍算命中」 |
| P-07 骨刺 UID 并发 | N/A | 我们用对象引用而非 UID |
| P-08 速度/尺寸手调 | 保留差异 | 出怪节奏/难度倍率是本项目的难度设计；脚本数值逐字来自仓库 |
| P-09 战斗框逐招变化 | 本来就对 | 各脚本自带 `CombatZoneResize`，与原版一致 |
| P-10 直接 BoneV 缺 Color | **已改** | 脚本骨颜色语义（0/1/2）已实现并加回归 |
| B-01 回合只在 FIGHT 后 +1 | **已改** | 拆成 `round`（攻击序列）与 `fightCount`（阶段门控） |
| B-02 NextAttack 13/14 不可达 | 本来就对 | 我们是模板池，`platformblasterfast` 可达 |
| B-03 / B-04 Practice 模式 | N/A | 按用户指示不做 Practice |
| B-05 缺对白 | 保留差异 | 我们写了中文台词（用户口径） |
| B-06 KR 高值提示 | 本来就对 | HUD 一直显示 KR 数值 |
| B-07 FIGHT 恒 MISS | 本来就对 | 攻击条结算 + Sans 闪避动画 |
| B-08 菜单骨 HP≥1 | 本来就对 | `updateKR` 的 `hp > 1` 保底 |
| B-09 敌人列表写死 | N/A | 单敌人 |
| B-10 Debug 命令风险 | **已改** | 本项目无对外 Debug 命令 |
| B-11 胜利无演出 | 本来就对 | 我们有击倒/饶恕两种结局画面 |
| B-12 BlackScreen 清理范围 | 本来就对 | 黑屏同时清 bones/sine/blasters/platforms |
| V-01 伤害/Karma | 本来就对 | 骨头 1/6、激光 1/10 |
| V-02 KR 上限/保底 | **已改** | 新增 `KR_MAX = 40`（保底 `hp > 1` 原有） |
| V-03 心速/跳跃/重力 | **已改** | 移速 260 → **150**，按住取消 75；跳跃/重力此前已按仓库改 |
| V-04 激光尺寸近似 | 本来就对 | Size 0/1/2 = 20/36/56，与 `BLASTER_W` 表一致 |
| V-05 撞击阈值 >330 | N/A | 我们的蓝魂是**匀速**模型（无冲量式 slam），阈值不适用 |
| V-06 无敌帧（同 H-04） | **已改** | 同上 |
| D-01 ResizeAuto 命名 | 本来就对 | 我们用 `CombatZoneResizeInstant` |
| D-02 Jumps.md 的 JMPG/JMPNG | 本来就对 | 我们的跳转语义与仓库实现一致 |
| D-03/D-04 SansText 参数、示例逗号 | N/A | 我们不自带 `Documentation/` 与 `Examples/` |
| D-05 维护性注释 | 本来就对 | 本项目注释密度高（每处改动都写了依据） |
| D-06 README 三条已知问题 | **已改 2/3** | 平台加速、心判定盒已修；「对话缺失」我们反而补了中文台词 |
| D-07 物品 8 格只注册 4 种 | 保留差异 | 按用户口径改成「传奇面包 ×20」 |
| D-08 多点触控 ID 脆弱 | 本来就对 | 我们的触摸分流按指针 ID 记录并回归 |
| D-09/D-10 Debug/BlackScreen 文档 | 本来就对 | 本项目文档已写明副作用 |

## 14. 《修改建议_第二轮》逐条处理（G1~G13）

| 编号 | 结论 | 说明 |
|---|---|---|
| **G1** 终盘只播 8.02s / 应 53.02s | **已改** | 新增 `World:simulateLength()` 干跑求真实时长；`startEnemy` 取 `max(静态, 干跑)`。实测 final 8.02 → **53.03s** |
| **G2** 循环/条件脚本时长被低估 | **已改** | 同上。spiral1 静态 0.09 / 干跑 10.58；bonestab3 5.27 / 26.55 → 回合时长都按干跑值 |
| **G3** 难度对脚本回合无效 | **已改** | `tune` 传进 `World`，`spd/itv/wn` 缩放速度/间隔/预警；「原作」档改回 1.00/1.00/1.00 |
| **G4** SansSlam 在红魂/普通蓝魂失效 | **已改** | 新增独立冲量 `soul.push`，三种模式统一积分（实测 dx=±136 / dy=122，原来全 0） |
| **G5** 双灵魂 + 双坐标系 + 两套蓝魂物理 | **已改** | 删掉 `World:update` 里的灵魂物理；`World.heart` 降级为脚本寄存器；`Game.soul` 唯一权威；清掉 `HEART_HIT`/`BONE_HIT_W` |
| **G6** KR 燃烧被简化 | **已核** | 速率（0.5s/点）、上限 40、保底 `hp>1` 都用断言钉住；原作的逐帧曲线仓库里没有，维持现状 |
| **G7** HP/治疗数值自相矛盾 | **已统一** | 文档口径统一为：HP 上限 92、传奇面包 +45（并清 KR） |
| **G8** 回合双计数器漂移 | **已核** | `round`（攻击序列）与 `fightCount`（只数 FIGHT）加断言：`fightCount ≤ round` |
| **G9** 蓝/橙判定用位移而非移动 | **已改** | `moved` 改成「按了方向键 或 正被 SansSlam 冲量推」 |
| **G10** `outside` 守卫过渡期无敌 | **已改** | 先钳回框内，守卫收紧到 ±0.25px，判定照跑 |
| **G11** 固定编排里 3 个脚本永不出现 | **已标注** | 固定表用 `final`（内含螺旋光束）；`spiral1/2/3` 保留为**终盘分档/调试素材**，不再出现在 0..22 的序列里 |
| **G12** 三关骨刺被改成同一套模板 | **保留差异** | 与用户「对这样的箭头模块统一一套战斗模板」的要求冲突，按用户口径**保持统一** |
| **G13** `EndAttack` 不结束回合 | **已改** | `EndAttack` 后留 0.2s 淡出即 `endEnemy`；`enemyDur` 降级为安全上限 |
