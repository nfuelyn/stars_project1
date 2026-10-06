# 原版复刻 · 攻击脚本移植清单

目标：**1:1 复刻**，不做玩法简化。数据源为参考实现的 `Files/sans_*.csv`（18 个攻击脚本）
与 `Documentation/*.md`（命令集），已在 `docs/bts-study.md` 记录出处与解码过程。

## 保真的关键决定

| 决定 | 理由 |
|---|---|
| **内部坐标系统一用原版 640×480**，渲染时整幅 ×1.5 居中到 1280×720 | 640×1.5=960、480×1.5=720 正好铺满高度。所有 CSV 数值**逐字照用**，不存在换算误差 |
| **攻击脚本保留 CSV 格式**（`延时, 命令, 参数…`） | 与原版可逐行对照；`JMPABS/JMPZ` 用 **1-based 物理行号**，标签行也**占一行**，否则行号会整体错位 |
| 延时语义 = **执行该行前要等的时间** | 首行的延时也要等（如 `randomblaster1` 的 0.5s 起手），循环跳回后延时重新计 |
| 速度不做任何缩放 | 原版 CSV 里的速度已经是 px/s（原作值 ×30），直接用 |

## 引擎已实现的命令（`prototype/attack-engine.js`）

| 类别 | 命令 |
|---|---|
| 弹幕 | `BoneV` `BoneH` `BoneVRepeat` `BoneHRepeat` `SineBones` `BoneStab` `GasterBlaster` |
| 平台 | `Platform` `PlatformRepeat` |
| 灵魂 | `HeartMode` `HeartTeleport` `HeartMaxFallSpeed` `SansSlam` `SansSlamDamage` `GetHeartPos` |
| 战斗框 | `CombatZoneResize`(带 FinishAction) `CombatZoneResizeInstant` `CombatZoneSpeed` |
| 流程 | `TLPause` `TLResume` `EndAttack` `BlackScreen` `Sound` `Music` |
| 表现 | `SansAnimation` `SansHead` `SansBody` `SansTorso` `SansSweat` `SansX` `SansRepeat` `SansEndRepeat` `SansText` |
| 运算 | `SET` `ADD` `SUB` `MUL` `DIV` `MOD` `FLOOR` `DEG` `RAD` `SIN` `COS` `ANGLE` `RND` |
| 跳转 | `JMPABS` `JMPREL`(相对) `JMPZ` `JMPNZ` `JMPE` `JMPNE` `JMPL` `JMPNL` `JMPG` `JMPNG` + 标签 `:Name` + `$变量` |

几何常量（原版贴图里量不到二进制，按原版视觉标定，集中在一处便于调）：
`BONE_W=19`（命中盒 16）、`HEART_HIT=8`、光束宽 `Size 0/1/2 = 20/36/56`、`GRAVITY=600`。

## 攻击脚本状态（27 个）

全部 27 个脚本现已移植完毕（原型 24 个在 `prototype/attacks/*.csv`，新增的 3 个螺旋档在 `lua/attacks.lua`），`node prototype/attack-selftest.js` 自动扫描目录，
实测 **PASS 48 / FAIL 0**；Lua 侧自测报 `attacks=27`。**原版那 24 个没有任何一个是自撰近似**：24 个文件全部是 BTS `Files/sans_*.csv` 的逐行转写
（延时/命令/参数逐字照抄，只去掉行尾多余空单元格），新转写的 13 个已用脚本与原文做过逐字节比对。
新增的 3 个螺旋档（`spiral1/2/3`）**几何逐字取自 `sans_final.csv` 阶段④**，只改总转角上限 gt、角速度增量上限 gin 与每发间隔。

| # | 脚本 | 内容（解码后） | 状态 | 数据来源 |
|---|---|---|---|---|
| 1 | `sans_intro` | 回合 0 偷袭：黑屏闪 → 框 165×165 → `SansSlam 1` → `BoneStab(1,54,0.167,1)` → `SineBones(20,-24,360,25)` → **14 发龙骨炮分 4 段**（① 十字 ② 交叉 ③ 上下 ④ 左右 Size2；Size1 Spin0.333 Blast0.267 / Size2 Spin0.666 Blast0.5）。**脚本全长 8.93s**，所以回合时长必须按脚本时长延长（`startEnemy` 用 `World:scriptLength()` 抬 `enemyDur`）——以前 `SURPRISE.dur=2.8s` 会把 ①②③④ 全部掐掉；反过来，挂脚本的回合内置生成器**让位**（`scriptOwnsRound`，回合 0 因此只跑这条脚本序列），否则 1.4s 一波的内置地面骨会插进脚本演出。**正弦骨方向**：生成在框**右侧**（`x = zone.r + 40 + idx*\|Spacing\|`）并向**左**扫（`dir=-1`），即**右→左**；生成侧与行进方向都由 `Spacing=-24` 的**符号**编码，与 BTS 原文逐字节一致，**按原版保留**（用户口述"由左往右进入"与该数据相反，属印象偏差，未改）。第 ③ 段相对 BTS 是**有意偏离**（原版此处是第 ① 段的逐字重复），按用户验收描述改成"上下"，原行保留在 CSV 注释里 | ✅ 已移植 | 逐行转写（先行批次；仅第 ③ 段按验收描述调整） |
| 2 | `sans_bonestab1` | 9 次循环：随机方向砸 + 骨刺（距离 25 / 预警 0.4 / 停留 0.333） | ✅ 已移植 | 原始逐行转写（先行批次） |
| 3 | `sans_bonestab2` | 同上，停留 0.2、循环 0.433（更快） | ✅ 已移植 | 原始逐行转写（先行批次） |
| 4 | `sans_bonestab3` | 距离 29、停留 **0**、循环 0.233（最凶） | ✅ 已移植 | 原始逐行转写（先行批次） |
| 5 | `sans_bluebone` | 蓝骨(高100,Color1) + 白骨(高20,Color0) 成对横穿 | ✅ 已移植 | 原始逐行转写（先行批次） |
| 6 | `sans_bonegap1` | 宽矮框：两侧高骨 95 + 底矮骨 20，速度 180、间距 120 | ✅ 已移植 | 原始逐行转写（先行批次） |
| 7 | `sans_bonegap1fast` | 同上，速度 210、间距 133 | ✅ 已移植 | 原始逐行转写（先行批次） |
| 8 | `sans_bonegap2` | 循环版：从中心镜像飞出，**上下骨缝恒 111 高**，速度档 210/270/330，间距递增 | ✅ 已移植 | 原始逐行转写（先行批次） |
| 9 | `sans_boneslideh` | 底矮骨向东 + 上部高骨向西，速度 120、间距 76 | ✅ 已移植 | 原始逐行转写（先行批次） |
| 10 | `sans_boneslidev` | 上下两组横骨（宽 200）向南/向北，速度 300、间距 183 | ✅ 已移植 | 原始逐行转写（先行批次） |
| 11 | `sans_spare` | 饶恕用空攻击（框变形 + 0.3s 结束） | ✅ 已移植 | 原始逐行转写（先行批次） |
| 12-16 | `sans_platforms1/2/3/4/4hard` | 平台 + 骨：`platforms1` 平台 61 宽 + 41 根矮骨地毯；`platforms2` 58 根骨地毯 + 多平台；`platforms3` 循环随机三位置骨 + 两组 `PlatformRepeat`；`platforms4` 大框多列上下骨；`4hard` 为高难变体（平台更窄 31、骨阵更密更快） | ✅ 已移植 | 原始逐行转写（本次，已与原文逐字比对） |
| 17-18 | `sans_platformblaster(+fast)` | 两组 `PlatformRepeat` + 5/6 次循环随机高度的左右快速炮（Spin0.567 Blast**0.1**） | ✅ 已移植 | 原始逐行转写（本次） |
| 19-20 | `sans_randomblaster1/2` | 15/12 次循环：以灵魂为中心、半径 400×300 随机角度，终点钳制到 [50,590]×[40,440]；Size0 Blast**0.033**（≈1 帧）/ Size1 Spin0.667 | ✅ 已移植 | 原始逐行转写（本次） |
| 21-23 | `sans_multi1/2/3` | 多段随机攻击组：黑屏闪 + 从 5/5/9 种攻击里随机（`Attack0..Attack8`），含**旋转 45° 的四连炮**、`SineBones`、镜像骨缝、`Platform` 静止平台等 | ✅ 已移植 | 原始逐行转写（本次） |
| 24 | `sans_final` | 最终回合四阶段：① 4 次随机砸+骨刺 ② 框体横向扩张 + `HeartMaxFallSpeed -300` + Sans 滑动 + **44 根正弦起伏高速骨横スク** + 10 组骨墙 + 24 根上下骨 ③ 缩框 + 4 组「黑屏闪 + 双骨刺 + 传送 + 砸」 ④ **旋转光束：Ang=-10·gt，gin 1→1.7 加速，BlastTime 0** ⑤ 撑过后 38 次砸击（`SansSlamDamage 1`，Wait 0.2→0.133，含 Tired1/Tired2/Sweat 递进）直到他睡着 | ✅ 已移植（本轮起**仅作参考实现**：最后三回合改走 `spiral1/2/3`，不再接进流程） | 原始逐行转写（本次，1 处等价改写：行 47 `$pi` → π 字面量） |
| 25 | `spiral1` | **螺旋龙骨炮 · 轻档**（内部号 17 = HUD ROUND 18 / 20）：几何逐字取自 `sans_final` 阶段④；三档只改「总转角上限 gt / 角速度增量上限 gin / 每发间隔」→ gt→140、gin→1.40、0.09s；框 305×165（约 103 发） | ✅ 已移植 | 转写自 `sans_final` 阶段④，只改 3 个参数 |
| 26 | `spiral2` | **螺旋龙骨炮 · 中档**（内部号 18 = HUD ROUND 19 / 20）：gt→160、gin→1.70、0.075s；框 237×165（约 104 发） | ✅ 已移植 | 同上 |
| 27 | `spiral3` | **螺旋龙骨炮 · 原作强度**（内部号 19 = HUD ROUND 20 / 20）：gt→190、gin→1.70、0.06666s；框 165×165（**= 原作强度**，约 122 发）＋ 原作阶段⑤「力竭」段逐字转写（38 次砸击、`SansSlamDamage 1` 真掉血、I=25 冒汗 / I=33 Tired1 / I=35 强制朝北 / I=36 Tired2） | ✅ 已移植 | 转写自 `sans_final` 阶段④＋⑤ |

> **螺旋三档的共同几何**（逐字取自 `sans_final.csv` 阶段④「旋转光束」）：中心 (320,306)、`Ang = -10·gt`、
> 半径 150→450（炮身在外圈 450、光束指向内侧）、`SpinTime 0.5`、`BlastTime 0`（瞬发）。
> 光束判定 = 从炮身沿 ang 射 **2000px 的整条 AABB**，所以光束**会穿过框中心**，玩法是"躲在两束光之间的缝里"。
> 三档只差 gt / gin / 每发间隔与框宽：305×165 → 237×165 → 165×165。

## 原版的回合结构（用于重排我们的流程）

- 前半 12 回合 → 中场（可回血，仁慈=即死）→ 后半 11 回合 → 最终回合四阶段 → 撑过后 Sans 用"什么都不做的特殊攻击"拖时间 → 睡着 → 把框推到左下才能击杀。
- 攻击顺序：intro → bonestab1 → bluebone → bonegap1 → platforms1 → platforms2 → platforms3 → platforms4 → randomblaster1 → multi1 → multi2 → multi3 → **中场** → bonestab2 → boneslideh → boneslidev → platformblaster → platforms4hard → randomblaster2 → bonegap1fast → platformblasterfast → bonegap2 → bonestab3 → **final**。

**我们的回合映射（本轮）**：内部号 0 = `sans_intro`（见面杀，固定、不参与抽签）；1–16 = 从当前档的模板里**随机抽**（`TEMPLATE_SETS` / `TEMPLATE_TIERS`：`bones` → `bones`+`stabs` → `stabs`+`platform` → 四套全上，每 4 个回合升一档；相邻两回合不重复、整场抽到越少的越优先）；17/18/19 = `spiral1`/`spiral2`/`spiral3`（HUD 显示 ROUND 18/19/20）。`final`（`sans_final` 全文）**仅作参考实现**留在 `lua/attacks.lua`，不接进流程；中场落在内部号 11（HUD 显示 ROUND 12 / 20）。

## 转写时确认的原作细节 / 遗留不确定项

1. **`final` 的 `$pi`**：`Files/sans_final.csv` 第 47 行是 `DIV,Deg,180,$pi`，但 `Event sheets/Globals.xml`
   没有声明 `pi`，`Documentation/Math.md` 也没列常量——说明 π 由 BTS 的表达式层直接提供。
   本引擎 `val()` 对未定义变量返回 0，会让 `Deg = 180/0 = Infinity` → 整面正弦骨变 NaN。
   故该行写死字面量 `3.141592653589793`（**行数不变**，所有 1-based 跳转行号照旧）。
   180/π 是唯一的「弧度→角度」换算，也是唯一能让正弦骨墙正常起伏的取值：骨高 H ∈ [5,55]，
   上下两骨之间恒留 34 高的正弦走廊。若日后给 `attack-engine.js` 加 π 内置量，可把 `$pi` 还原。
2. **`Platform` 的 `BooleanReverse`**：`platforms4/4hard` 用了 `Platform,151,336,41,0,90,1`（第 7 参数 = 1）。
   引擎已解析并保存该标志，但 `update()` 里的平台运动**尚未实现往返**。平台碰撞也还没做
   （`platforms1/2/3/4/4hard`、`platformblaster(+fast)`、`multi2/multi3` 的 Attack5 都依赖它）。
3. **`GasterBlaster` 的 `BlastTime = 0`**：`final` 阶段④ 用 `...,0.5,0` 生成连续旋转光束，
   BTS 里 0 表示瞬发/持续；引擎目前把 `blast=0` 当成「0 秒开火、0.15s 后移除」，光束渲染要另做。
4. **暂停期间的框体变形会被走两遍**：`attack-engine.js` 的 `update()` 里 `stepZone` 在 `paused` 分支和
   紧随其后的无条件 `if (this.zone.resizing)` 各调用一次，所以 `TLPause` + `CombatZoneResize...TLResume`
   的入场变形按 2× 速度完成。`platforms1/2/3/4/4hard`、`platformblaster(+fast)`、`randomblaster1/2`、
   `multi1`、`multi3`、`final` 的起手都靠这个 FinishAction 恢复脚本，故起手比原作略短。
   （这是引擎问题，不是转写问题；改法是把暂停分支的那次 `stepZone` 去掉。）
5. `final` 空跑需 **53.0s**，已接近自测脚本 60s 的上限——以后若再往 `final` 前后加内容要注意。
6. 这 13 个脚本**都没有用到 `SansText`**，因此本次没有引入任何台词文本；贴图 / 音频 / 字体一律未取。

## 下一步

1. ~~移植剩余 13 个脚本（data 层，直接转写）。~~ ✅ 已完成（原版 24/24 + 螺旋档 3 个 = **27**，selftest PASS 48 / FAIL 0）。
2. 把引擎接进游戏：**回合流程改成 20 回合结构（内部号 0 = `sans_intro`，1–16 = 随机抽模板，17/18/19 = `spiral1/2/3`；`final` 仅作参考实现）**、命中判定（骨头 / 骨刺 / 光束 / 蓝橙骨 / 砸击）、HP 92 & KR、菜单骨。
3. 渲染改为「640×480 世界 ×1.5」：骨头按 19 宽 + 两端骨球、龙骨炮做**旋转蓄力段**、战斗框连续变形、黑屏闪白。
4. 补引擎缺口：平台碰撞 + `BooleanReverse` 往返、`BlastTime 0` 的持续光束、暂停期间 `stepZone` 双步进。
5. 贴图拟合：`Textures/*.png` 目前被 GitHub API 限流挡住（403），待限流恢复或改走 CDN 后再取尺寸/形状校对。
   *（可用的旁路：`https://data.jsdelivr.com/v1/packages/gh/jcw87/c2-sans-fight@master?structure=flat`
   能列出全部文件与字节数，`raw.githubusercontent.com` 也能直接取到任意文件——本次攻击脚本就是这么拿的。）*
