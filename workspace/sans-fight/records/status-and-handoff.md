# 当前状态与交接（审判者战 · 试玩验证）

更新时间：`BUILD = 2026-10-05-beam`（**参考仓库保真轮**：按 BTS 的 `CombatZoneClipped` 语义裁竖骨 +
platforms4 恢复原值；上一轮是 20 回合结构轮 `rounds20`，再上一轮是优化轮 `optimized`）。
本文只记"已验证 / 未验证 / 怎么复现"，细节见 `records/playtest.md`、`records/lua-port.md`
与 `docs/device-setup.md`。

**改完 Lua 必须先 `node tools/build-save.mjs` 再试玩**：模拟器跑的是**存档内嵌**的脚本
（`scripts[].source`），不是工作区里的 `.lua`。判据：`main start: … build=2026-10-05-jump025
… pool=531`（更旧版是 `build=2026-10-05-rounds20 … pool=531` / `build=2026-10-05-optimized … pool=355`）。一条命令跑完全部回归 + 重建：
`node tools/verify-all.mjs`。

## 跳跃 3/5 框高 · 光束线段判定 · 箭头整边升骨 · ROUND14 单发（2026-10-05 第十一轮）

| 用户口径 | 处理 |
|---|---|
| 跳跃高度提高到 3/5 框高 | `JUMP_HEIGHT = 0.6`；上升窗口仍是 0.25s（速度 = 0.6×框高/0.25s = 336px/s @140），下落速率不变 |
| 高骨必须仍低于跳跃高度 | `boneslideh / bonegap1 / bonegap1fast` 高骨 46 → **32**（底沿 289 ≤ 跳跃最高点矩形上沿 295−3） |
| 18 回合螺旋光束「没光束也有伤害」 | 光束判定从**整条线段 AABB** 改成**灵魂中心到线段的最短距离 ≤ band/2 + SOUL_R** —— 与画出来的光束同宽 |
| 箭头模板：整条边升起一排骨头 | `ArrowBone` 命中矩形改为**整条边**（西/东整条竖边、南/北整条横边），向内伸出 `min(1/4 框宽, 3/5 框高)` |
| ROUND 14 单个龙骨炮：出现 1.5s + 到发射再等 1s | `randomblaster1`：SpinTime 0.46666 → **1.5**，新增第 10 个参数 **HoldTime=1.0**；循环 15 → 3 发（8s 内跑完） |
| ROUND 10 最后那根从右边来的骨头 | 贴地骨 `BoneV,517,349,35` → **24**（349..373），地面站立带 379..387 让开 |
| ROUND 17 骨头再多等 0.9s | `sans_bonestab3`：`0,ArrowBone` → `0.9,ArrowBone`，循环延时 1.2 → 2.1（总长仍 ≈7.5s） |

回归：`core_selftest` **277 PASS / 0 FAIL**（blue-jump 改判 3/5 框高、platforms3-safe 加地面带、新增 r14-blaster、arrow-module 放宽 bonestab3 差异）；
`_geometry` 33 PASS / 0 FAIL；`_flow` 0 错误；`_input` 249 / `_rounds` 54 / `_check` 无 FAIL。存档 339,898 bytes，`build=2026-10-05-beam`。

**待确认（本轮没动）**：

* 第九回合龙骨炮发射间隔 1.5s —— ROUND 9 = `multi1`，该脚本里没有 `GasterBlaster`，需要你确认是哪一关/哪一段。
* 14/15 回合光束「太小判定不到」—— 判定已改成与光束同宽；若仍觉得细，可以把 Size0/1 的光束加宽（会同时变粗）。
* 左右拖拽箭头的三角位置 —— 需要你说明是「离得远/近」还是「方向反了」。


## 蓝心 0.25s 跳跃 + 不再浮空 + ROUND 10 让路骨头（2026-10-05 第十轮）

用户口径：round10 有根过不去的骨头；蓝心按着跳跃不动会一直浮空，需要自然下落；跳跃时间再次修改为 0.25s。

### 1. 蓝心跳跃：上升 0.25s、**到点自然下落**（不再悬停）

| 项 | 行为 |
|---|---|
| 上升 | 按住 → 匀速上升，速度 = 0.5×框高 / **0.25s**（框高 140 → 280px/s），0.25s 正好到 1/2 框高 |
| 超时 | **按住超过 0.25s 不再上升** → 转等速下落（旧版会在 1/2 框高一直悬停＝玩家说的「一直浮空」） |
| 下落 | 速度 = 0.5×框高 / 0.75s（框高 140 → 93.3px/s） |
| 二段跳 | 松手即剪断本次跳跃，下降途中再按不会回升 |

实现：`heldT < JUMP_RISE_T - 1e-9`（时间窗口）+ `risen < maxRise - 0.01`（高度上限，防浮点多跑一帧）两道闸。

### 2. ROUND 10（`sans_platforms3`）两根「过不去」的骨头

这一关两块落脚平台的站立带 = `平台顶面 - SOUL_CLAMP(8) ± SOUL_R(4)`：

| 平台 | 站立带 y | 原来被哪根骨头盖住 | 处理 |
|---|---|---|---|
| y=306 | 294..302 | `BoneV,517,257,45`（257..302）→ 站上去必被扫 | 高度 **45 → 32**（257..289，让出 5px） |
| y=346 | 334..342 | `BoneV,125,306,40`（306..346）→ 站上去必被扫 | 高度 **40 → 24**（306..330，让出 4px） |
| 地面 | 379..387 | `BoneV,517,349,35`（349..384） | 保持不变（它逼你上平台，而两块平台现在都安全） |

回归：`platforms3-safe` 直接按站立带公式扫三种骨头，断言两条平台站立带「挡住它的骨头 = 0 根」。

### 3. 证据

| 项 | 结果 | 证据 |
|---|---|---|
| 逻辑自测 | **274 PASS / 0 FAIL**（`blue-jump` 加「按住 2s 必须落回地面」；新增 `platforms3-safe`） | `core_selftest` |
| 绘制 == 判定 | **33 PASS / 0 FAIL** | `records/captures/geometry-27.txt` |
| 整场流程 | 错误 0 / draw ERR 0 | `records/captures/flow-jump025.txt` |
| 其余 | `_input` 249 / `_title` 33 / `_rounds` 54 / `_tap` 40 / `_check` 无 FAIL | 各 `tools/run-lua.mjs` |
| 画面 | ROUND 10 平台站立带不再被骨头覆盖 | `records/captures/r10-fixed/` |
| 存档 | 338,297 bytes，`build=2026-10-05-jump025` | `build-save` |


## 首轮龙骨炮 1.0s 预警 + 传奇面包（2026-10-05 第九轮）

用户口径：龙骨炮出现与发射间隔增加为 1s；食物大量增加，均为回 45 血的传奇面包。

### 1. 首轮（`sans_intro`）龙骨炮：SpinTime 0.6 → **1.0**

16 发全部（14 发 Size1 + 2 发 Size2）的 `SpinTime` = **1.0s**（出现 → 旋转到位 = 1.0s，之后固定 0.05s 转开火）。
BlastTime 仍按原版（0.26666 / 0.5）。回归：`intro-blaster` 断言改判 1.0。

### 2. 食物：单一「传奇面包」×20，每口回 45 HP

`Game:resetRun` 的 `self.items` 从「雪镇薯条 ×1 / 热猫 ×1」改成：

```lua
self.items = { { id = 'legend_bread', name = '传奇面包', desc = '回复 45 HP', heal = 45, count = 20 } }
```

回归：`items` 段断言「全部是传奇面包且 heal=45」「总量 ≥10」「吃一口 10 → 55 且数量 -1」。

### 3. 证据

| 项 | 结果 | 证据 |
|---|---|---|
| 逻辑自测 | **270 PASS / 0 FAIL**（含新的 `items` 与改判的 `intro-blaster`） | `core_selftest` |
| 绘制 == 判定 | **33 PASS / 0 FAIL** | `records/captures/geometry-26.txt` |
| 整场流程 | 错误 0 / draw ERR 0 | `records/captures/flow-bread.txt` |
| 其余 | `_input` 249 / `_title` 33 / `_rounds` 54 / `_tap` 40 / `_check` 无 FAIL | 各 `tools/run-lua.mjs` |
| 画面 | 首轮龙骨炮蓄力 1.0s | `records/captures/intro-spin1/` |
| 存档 | 337,630 bytes，`build=2026-10-05-bread` | `build-save` |


## 蓝心 0.75s 下落 · ROUND 7 幽灵平台 · 骨缝加宽 · 箭头模块（2026-10-05 第八轮）

用户口径：

> round7 出现不应存在的平台，上下骨同列前进的空隙不足以无伤穿过，下落改为 0.75s，以及箭头出现时应当为蓝心，
> 并朝着箭头方向拖拽灵魂致战斗框边上，此时骨头升起高度不超过蓝心最大跳跃高度。对这样的箭头模块统一一套战斗模板，
> 拖拽灵魂到即将出现骨头的框边……骨头等待 0.8s 伸出，此时蓝色灵魂的跳跃实现是与拖拽方向相反……
> 这种攻击下不可直接套用普通蓝心物理规则。

### 1. ROUND 7 幽灵平台（真 bug）

`Game:startEnemy` 原来**无条件**给 `blue_soul` 回合调 `buildPlatforms()`，但 20 回合版里这一回合照样挂攻击脚本
→ 场上同时有「脚本骨头」和「内置平台」。现在改成**只有这一回合不带脚本时才造平台**。
回归：`round7-platform` 断言 `#g.platforms == 0` 且确实挂了脚本。

### 2. 上下骨同列的缝：18px → 30px

`sans_bonegap2` 的 `HeightT = 111 - HeightB` → **`99 - HeightB`**（缝 = 129-HeightB-HeightT 恒为 18 → **30px**）。
灵魂 8px，可站宽度从 10px 提到 **22px**。回归：`bonegap2-gap`（四种 HeightB 逐一代入核对）。

### 3. 下落 0.9s → 0.75s

`JUMP_FALL_T = 0.9 → 0.75`（上升仍是 0.55s）。回归：`blue-jump` 的「落回 0.75s」「下落速率恒定」。

### 4. 箭头模块：统一战斗模板（`sans_bonestab1/2/3` 内容完全一致）

| 要素 | 实现 |
|---|---|
| 箭头出现 = 蓝心 | `HeartMode,1` |
| 不可套用普通蓝心物理 | 新命令 `HeartWall,1`：**贴墙模式** —— 不吃重力/悬停，四向自由移动 |
| 沿箭头把灵魂拖到框边 | `SansSlam,$Direction` 的推速**真的积分进位移**（以前 `soul.vx` 只赋值不位移，等于没砸） |
| 骨头等 0.8s 伸出 | 新命令 `ArrowBone,$Direction,0.8,0.3` |
| 骨头升起高度 ≤ 最大跳跃高度 | 骨头长度/高度恒 = **1/2 框高** |
| 跳跃 = 拖拽方向的反方向 | 墙模式下 `Game:jump` 改成「朝箭头反方向冲刺 0.55s」；拖到左边 → 向右 |
| 统一模板 | 三个 bonestab 脚本逐字节相同；原版 25/25/29、0.4/0.3/0.4 等差异参数废弃 |

回归：`arrow-module`（模板一致 / HeartMode / HeartWall / ArrowBone 0.8 / 高度 ≤1/2 框 / 运行时反向冲刺）全过。

### 5. 证据

| 项 | 结果 | 证据 |
|---|---|---|
| 逻辑自测 | **265 PASS / 0 FAIL**（新增 round7-platform / bonegap2-gap / arrow-module 三组） | `core_selftest` |
| 绘制 == 判定 | **33 PASS / 0 FAIL** | `records/captures/geometry-25.txt` |
| 整场流程 | 错误 0 / draw ERR 0 | `records/captures/flow-arrow2.txt` |
| 其余 | `_input` 249 / `_title` 33 / `_rounds` 54 / `_tap` 40 / `_check` 无 FAIL | 各 `tools/run-lua.mjs` |
| 画面 | ROUND 6 箭头向下、蓝心被拖到左下、骨头从左边缘升起 | `records/captures/arrow-mod*/` |
| 存档 | 337,590 bytes，`build=2026-10-05-arrow` | `build-save` |


## 蓝心 0.55s 上升 / 0.9s 下落 + 首轮龙骨炮 0.6s 预警（2026-10-05 第七轮）

用户口径：

> 上升 0.55s，下落减缓为 0.9s，首轮龙骨炮出现和释放中间间隔 0.6s。

### 1. 蓝心跳跃（`lua/core.lua`）

| 项 | 行为 |
|---|---|
| 上升 | 按住 → 匀速上升，速度 = `0.5 × 框高 / 0.55s`（框高 140 → **127.3px/s**）→ **0.55s 到 1/2 框高** |
| 下落 | 松开 → 匀速下落，速度 = `0.5 × 框高 / 0.9s`（框高 140 → **77.8px/s**）→ **从 1/2 框高落回用 0.9s**（比上升慢） |
| 悬停/二段跳 | 与前一轮相同：到 1/2 框高悬停；松手剪断，下降途中再按不会回升 |

### 2. 首轮（`sans_intro`）龙骨炮：出现 → 释放 = 0.6s

| 参数 | 原版 | 现在 |
|---|---|---|
| `SpinTime`（Size 1，14 发） | 0.333 | **0.6** |
| `SpinTime`（Size 2 收尾，2 发） | 0.666 | **0.6** |
| `BlastTime` | 0.26666 / 0.5 | 不变 |

运行时「出现→释放」= `SpinTime + 0.05`（`spinning` 段固定 0.05s）≈ **0.65s**。
只在 SpinTime 这一列改动，原版数值逐字保留在 CSV 头注释里。

### 3. 证据

| 项 | 结果 | 证据 |
|---|---|---|
| 跳跃曲线 | `blue-jump` 8 条（0.55s=1/2 框高 / 0.35s=0.318 / 正比 / 悬停封顶 / **落回 0.9s** / 下落速率恒定 / 不能二段跳）全过 | `core_selftest` → **248 PASS / 0 FAIL** |
| 首轮龙骨炮 | `intro-blaster` 断言：16 发全部 SpinTime=0.6 | 同上 |
| 绘制 == 判定 | `_geometry` **33 PASS / 0 FAIL** | `records/captures/geometry-23.txt` |
| 整场流程 | `_flow` 错误 0 / draw ERR 0 / 按钮行 4225 帧全合法 | `records/captures/flow-jump55.txt` |
| 其余 | `_input` 249 / `_title` 33 / `_rounds` 54 / `_tap` 40 / `_check` 无 FAIL / 契约 7/7 | 各 `tools/run-lua.mjs` |
| 存档 | 328,695 bytes，`build=2026-10-05-jump55` | `build-save` |


## 蓝心 0.6s 匀速跳 + 蓝高骨挪到「左右高低骨」组合（2026-10-05 第六轮）

用户口径：

> 上升改为 0.6s，并且下降过程中不能二次跳跃，以及长按不能无限飞升。
> round4 的上方不需要是蓝骨，我说的是左右高低骨进入的组合时高骨为蓝骨。

### 1. 蓝心跳跃（`lua/core.lua`）

| 项 | 现在的行为 |
|---|---|
| 上升 | 按住 → 匀速上升，速度 = `0.5 × 框高 / 0.6s`（框高 140 → **116.7px/s**）→ **0.6s 正好到 1/2 框高** |
| 到顶 | 到**起跳点上方 1/2 框高**就 `vy = 0` **悬停** → 长按不会无限飞升（从平台起跳按新起跳点算，另有框顶兜底） |
| 松开 | 当帧改**同速等速下降** |
| 二段跳 | 松手即把本次跳跃「剪断」（`soul.jumpCut`）→ **下降途中再按跳跃键不会重新上升** |

新增回归：`blue-jump` 里补了「按 2.0s 与按 0.6s 高度相同（悬停）」与「下降途中按住 0.5s 也不会重新上升」两条。

### 2. 蓝高骨的位置纠正

| 脚本 | 结构 | 高骨 |
|---|---|---|
| `sans_boneslideh`（**ROUND 4**） | 矮骨只从左边来、高骨只从右边来 | **恢复白骨**（撤掉第五轮加的 Color=1） |
| `sans_bonegap1`（ROUND 3） | **左右两侧各自出一高一矮** | **蓝骨 Color=1** |
| `sans_bonegap1fast`（ROUND 5） | 同上 | **蓝骨 Color=1** |

配套：官方 `BoneVRepeat` 没有 Color 参数 → 本项目给它加了第 8 个可选参数（不传 = 0 = 白），
并把脚本骨的**渲染认数字颜色**、**碰撞按 moved 判定蓝/橙**补齐（第五轮已做，本轮复用）。

### 3. 证据

| 项 | 结果 | 证据 |
|---|---|---|
| 跳跃/悬停/二段跳 | `blue-jump` 7 条断言全过 | `core_selftest` → **246 PASS / 0 FAIL** |
| 高骨颜色口径 | `fair-bone` 15 条（含 bonegap1/1fast 高骨必须 Color=1、boneslideh 高骨必须白骨）全过 | 同上 |
| 画面 | ROUND 3：高骨**蓝**、矮骨白；ROUND 4：上方那根**白** | `records/captures/r3-blue/mobile-16-9-t3_00.png` / `records/captures/r4-white/mobile-16-9-t3_00.png` |
| 绘制 == 判定 | `_geometry` **33 PASS / 0 FAIL** | `records/captures/geometry-22.txt` |
| 整场流程 | `_flow` 错误 0 / draw ERR 0 / 按钮行 4225 帧全合法 | `records/captures/flow-blue06.txt` |
| 其余 | `_input` 249 / `_title` 33 / `_rounds` 54 / `_tap` 40 / `_check` 无 FAIL | 各 `tools/run-lua.mjs` |
| 存档 | 328,057 bytes，`build=2026-10-05-blue06` | `build-save` |


## 蓝心匀速跳 + 第四回合蓝高骨（2026-10-05 第五轮）

用户口径：

> 蓝心用这样一套跳跃规则：0.7s 内升到战斗框 1/2 高度，其中松开跳跃键就不再继续上升，进行等速下降。
> 第四回合的高低骨组合应当为高骨为蓝骨，低骨为普通骨头攻击。

### 1. 蓝心跳跃整段重写（`lua/core.lua`）

| | 规则 |
|---|---|
| 上升 | 按住 → **匀速**上升，速度 = `0.5 × 框高 / 0.7s`（框高 140 → **100px/s**） |
| 松开 | **立刻停止上升**，同速**等速下降**（没有惯性、没有重力加速度） |
| 上界 | 战斗框上沿（按住会一直升到框顶；平台关需要）——**新增框顶钳位**，旧实现按住会直接飞出框 |

实测（`探针_probe_jump（该一次性探针已在“lua 目录瘦身”轮清理，数值结论保留）`，框高 140）：0.35s → 35px（1/4 框高）、**0.7s → 70px（1/2 框高）**、
1.0s → 100px、1.5s → 124px（框顶封顶）。完全线性。

### 2. 脚本骨的颜色语义（顺带修的真 bug）

`Documentation/Attacks.md` 规定 `Color`：0 白 / 1 蓝 / 2 橙。但**脚本骨的碰撞分支从来没看颜色**
（一律 `hurt('hit')`），渲染也只认字符串 `'blue'`/`'orange'`、不认数字 —— 脚本里的蓝骨一直是「画成白的 + 打到就扣血」。
现在渲染认数字，碰撞按内置蓝/橙骨同一套 `moved` 语义：蓝骨只有**移动**扣血、橙骨只有**静止**扣血、白骨无条件扣血。

### 3. 第四回合（`sans_boneslideh`）= 高骨蓝骨 + 低骨白骨

高骨原来是 `BoneVRepeat`（该命令**没有 Color 参数**，只能是白的）→ 改成 8 条显式 `BoneV`，`Color=1`：

```text
0.5,BoneVRepeat,128,366,20,0,120,8,76    ← 低骨：普通白骨，跳过去躲
0.5,BoneV,513,257,46,2,120,1             ← 高骨：Color=1 蓝骨 ×8（X = 513 + 76*i）
0,BoneV,589,257,46,2,120,1
…（741 / 817 / 893 / 969 / 1045）
6.7,EndAttack
```

位置、高度、速度与原来逐根一致（只是加了颜色），高骨仍然跟在矮骨后面 0.5s 进场。

### 4. 证据

| 项 | 结果 | 证据 |
|---|---|---|
| 跳跃曲线 | `blue-jump` 4 条（0.7s=1/2 框高 / 0.35s=1/4 / 正比 / 升降同速）全过 | `core_selftest` → **241 PASS / 0 FAIL** |
| 蓝骨语义 | `blue-script-bone` 2 条（静止不扣血 / 移动扣血）全过 | 同上 |
| 高骨公平性 | `fair-bone` 12 条（含改判据为 0.7s 跳跃）全过 | 同上 |
| 画面 | ROUND 4 高骨是**蓝色**、低骨是**白色** | `records/captures/round4-blue/mobile-16-9-t9_00.png` |
| 其余 | `_input` 249 / `_title` 33 / `_rounds` 54 / `_tap` 40 / `_check` 无 FAIL / 契约 7/7 | 各 `tools/run-lua.mjs` |
| 存档 | 327,615 bytes，`build=2026-10-05-bluehold` | `build-save` |


## 高骨公平性轮（2026-10-05 第四轮）：高骨降高 + 跟在矮骨后面进场

触发：玩家口径「**高骨必须严格低于灵魂起跳高度，并且一定跟在矮的后面进入框内，不然没有足够反应空间**」。

### 改动（`prototype/attacks/`，原版数值保留在文件头注释里，可一键回退）

| 脚本 | 高骨高度 | 高骨进场时机 | 矮骨 |
|---|---|---|---|
| `sans_boneslideh`（ROUND 4） | 107 → **46** | 高骨行延时 0 → **0.5s**（矮骨先进 0.5s） | 20，不变 |
| `sans_bonegap1`（ROUND 3） | 95 → **46** | 矮骨两行提到前面，高骨两行跟后 **0.3s**（180px/s → 落后 54px） | 20，不变 |
| `sans_bonegap1fast`（ROUND 5） | 95 → **46** | 同上，落后 0.3s（210px/s → 落后 63px） | 20，不变 |

三张脚本的 `EndAttack` 延时同步扣掉，**脚本总时长不变**（7.7 / 6.6 / 6.4s），回合节奏不受影响。

### 为什么是 46（框 375×140）

```text
灵魂贴地中心      = 391 - SOUL_CLAMP(8) = 383
按住 1s 跳跃高度   = 71.9px（blue-jump 轮实测；设计口径 0.5×140 = 70）
最高点矩形上沿    = 383 - 71.9 - SOUL_R(4) = 307.1
高骨底沿上限      = 307.1 - 3(余量) = 304.1  →  高度 ≤ 47  →  取 46（底沿 303）
```

于是：**跳起来躲矮骨时，高骨底沿 303 永远在灵魂最高点 307.1 之上 → 撞不到**；同时 `46 < 71.9`，
字面上也满足「高骨高度严格低于灵魂起跳高度」。

### 证据

| 项 | 结果 | 证据 |
|---|---|---|
| 公平性契约 | `fair-bone` 12 条断言（3 个脚本 × 高度/底沿/进场顺序）全过 | `core_selftest` → **239 PASS / 0 FAIL** |
| 画面 | ROUND 4 高骨只剩上三分之一，矮骨先进场、高骨随后从右侧滑入 | `records/captures/round4-fixed/mobile-16-9-t45_00.png` / `t47_00.png` |
| 其余回归 | `_check` 无 FAIL / `_input` 249 / `_title` 33 / `_rounds` 54 / `_tap` 40 | 各 `tools/run-lua.mjs` |
| 存档 | 326,289 bytes，`build=2026-10-05-bluejump` | `build-save` + `verify-client-pool` PASS 7/7 |

**没动的**：`sans_bluebone`（高骨是蓝骨，机制是"别动"不是"跳过去"）、`sans_bonegap2`（高度随机、
缺口固定 18px 的"骨头缝"关）、`sans_intro`（演出关）。**要一起改说一声。**


## 蓝心跳跃轮（2026-10-05 第三轮）：四档重力 + 按住变高（真 bug）

触发：玩家反馈「round4 攻击有问题：最高骨头超越了蓝心起跳最高高度，而且蓝心缺失了随按键时长改变高度的特性」。

### 1. 根因（`Battle.xml` 逐条核对）

原版 `PlayerMovement` 里 `Gravity` 是**四档**，用 `DownSpeed = -dy` 判定；我们的实现**把 180 / 540 用反了**：

| 段 | 旧实现（错） | 原版（真值） |
|---|---|---|
| 上升中 | `vy < -30` → 180 | `dy < -15` → **540** |
| 顶点附近 | 中段 450 | `-15 ≤ dy < 30` → **180** |
| 下落 | 中段 450 | `30 ≤ dy < 120` → **450** |
| 快落 | `vy > 240` → 540 | `dy ≥ 120` → **180** |

第二个 bug：「托底」夹在**重力之前**，每帧先被重力吃掉 18px/s，净上升只剩 2/3。

### 2. 改动（`lua/core.lua`）

* 新增 `gravityFor(vy)`，按上表四档取值 → 起跳弹道 = `180²/(2×540)` ≈ **30px = 1/5 框高**（框高 140）。
* 「托底」挪到重力**之后**；托底速度 = `0.40 × 框高/秒` → 轻按 0.2 框高、**按住 1s ≈ 0.5 框高**，随按住时长**线性**增长。

### 3. 实测曲线（`探针_probe_jump（该一次性探针已在“lua 目录瘦身”轮清理，数值结论保留）`，框高 140）

```text
                    旧实现        新实现
轻按                 87.0px        28.7px   (0.205 框高)
按住 0.5s            87.0px        43.9px   (0.313 框高)
按住 1.0s            90.4px        71.9px   (0.513 框高)
按住 1.5s           101.6px        99.9px   (0.713 框高)
```

### 4. 证据

| 项 | 结果 | 证据（级别） |
|---|---|---|
| 跳跃曲线契约 | `blue-jump` 4 条断言（1/5 框高 / 1s≈1/2 框高 / 单调 / 线性）全过 | `core_selftest` → **227 PASS / 0 FAIL** |
| 其余回归 | `_check` 无 FAIL / `_input` 249 / `_title` 33 / `_rounds` 54 / `_tap` 40 | 各 `tools/run-lua.mjs` |
| 存档重建 | 324,408 bytes，`build=2026-10-05-bluejump` | `build-save` |

### 5. round 4（HUD ROUND 4/20 = 内部号 3）= `sans_boneslideh`

逐字比对：`prototype/attacks/sans_boneslideh.csv` 与参考 `Files/sans_boneslideh.csv` **完全相同**（仅注释差异）：

```text
0,CombatZoneResize,133,251,508,391,TLResume     ← 框 375×140
0,HeartTeleport,320,376 / 0,HeartMode,1 (蓝魂)
0.5,BoneVRepeat,128,366,20,0,120,8,76           ← 矮骨(20) 框底，从**左**向东
0,BoneVRepeat,513,257,107,2,120,8,76            ← 高骨(107) 框顶，从**右**向西
7.2,EndAttack
```

高骨下沿 = 257+107 = **364**，矮骨上沿 = **366** → 同一 x 上只有 2px 缝，**必须靠左右走位穿缝**（不是跳过去）。
玩家截图（`records/captures/round4/mobile-16-9-t50_00.png`）证实画面与这条数据一致。


## 参考仓库保真轮（2026-10-05 第二轮）：CombatZoneClipped 竖骨裁剪 + platforms4 恢复原值

触发：用户指令「优先学习该链接内代码，制作攻击模式」（[Jcw87/c2-sans-fight](https://github.com/Jcw87/c2-sans-fight)）
+ 此前反馈「避免攻击超出战斗框范围」。做法是**回到 `Event sheets/Battle.xml` 找真值**，不是调参。

### 1. 参考仓库怎么裁（逐字核对，不是猜）

`Battle.xml` 里每种对象建在哪个图层是写死的；`CombatZoneTick` 会造 4 块 `CombatZoneClipper`
（TiledBg）盖住 `CombatZoneClipped` 图层的框外区域（上/左/右/下各一块，尺寸按 `CombatZone` 现算）：

| 对象 | 建在哪个图层 | 是否被战斗框裁 |
|---|---|---|
| `BoneV` / `BoneVRepeat` / `BoneStabV` / `BoneStabH` | `CombatZoneClipped` | **裁** |
| `BoneH` / `BoneHRepeat` / `GasterBlaster` | `CombatZone` | 不裁（龙骨炮本来就从屏幕角飞进来） |

### 2. 改动

**`lua/core.lua`**：新增 `clipVZone(x,y,w,h,zone)`；对**竖骨**在
① 碰撞判定、② 渲染出口 两处用**同一份**裁剪后的矩形。灵魂永远被钳在框内，所以「裁后矩形」与
「整根骨头」的命中结果**完全等价**（不是削弱判定，是把框外那段本来就不可能碰到的部分去掉）。
横骨/龙骨炮不裁；整根在框外的竖骨这一帧直接不输出控件。导出 `M.clipVZone` 给离线回归复用。

**`prototype/attacks/platforms4.csv` / `platforms4hard.csv`**：第 4 组骨毯恢复 BTS 原值
`BoneVRepeat,528,366,40,0,60,60,15`（上一轮为绕开「60 根 × 间距 15 拉出 900px 骨墙出框」把它改成了
「静止 29 根、只铺满框宽」）。现在裁剪接管了「不出框」，脚本数值不再偏离参考仓库。

### 3. 证据

| 项 | 结果 | 证据（级别） |
|---|---|---|
| 裁剪契约（竖骨裁 / 横骨不裁 / 全出框返回 nil / 渲染出口同步裁） | `clip-zone` 8 条断言全过 | `node tools/run-lua.mjs lua/core_selftest.lua` → **223 PASS / 0 FAIL**（L1 离线） |
| 绘制 == 判定（含裁后竖骨） | 整场 7 类实体逐帧对账，**41059/41059** 条一致；骨骼命令 39902 → 21624 条（框外的竖骨不再输出控件） | `node tools/run-lua.mjs lua/_geometry.lua` → `records/captures/geometry-18.txt` **33 PASS / 0 FAIL**（L1 离线） |
| 其余回归 | `_check` 无 FAIL / `_input` 249 pass / `_title` 33 pass / `_rounds` 54 pass / `_tap` 40 pass | 同上一列的命令（L1 离线） |
| 控件池峰值（含恢复后的 platforms4hard 60 根骨毯） | rect 69 / circle **245** / rot 76 / rtri 3 / ring 1 / text 12 / cursor 1 = **407**；四档整场**运行期追加实例化 0**、draw ERR 0 | `node tools/run-lua.mjs lua/_pool.lua` → `records/captures/pool-15.txt`（L1 离线） |
| 整场流程（标题→R0..R19→终盘→结局） | 错误 0 / 属性写入类型违规 0 / 框溢出 0px / 按钮行 4225 帧全部合法 | `node tools/run-lua.mjs lua/_flow.lua`（L1 离线） |
| 存档重建 | 323,068 bytes，模板 7 / 脚本 1 条内联包，契约 PASS 7/7 | `node tools/build-save.mjs` + `node tools/verify-client-pool.mjs` |
| 模拟器实跑截图（竖骨全在框内） | ROUND 3/20 骨缝关：3 根高骨 + 3 根矮骨全部落在框内，无一伸出框沿 | `records/captures/clipzone-enemy/mobile-16-9-t32_00.png`（模拟器证据，非真机） |

### 4. 27 个攻击脚本 vs 参考仓库的逐行比对（`Files/sans_*.csv`）

比对方法：剥掉注释行与行尾多余逗号后逐行逐字段比较。结论：**除下面 3 处有记录的偏离外，全部逐字相同**。

| 脚本 | 偏离 | 原因 |
|---|---|---|
| `sans_intro` | 四组龙骨炮间隔各 +0.1s；`Sound GasterBlaster` 少一个音量参数 `1.4`；第 3 组由原版「十字（与第 1 段逐字重复）」改为「上下」4 发 | 间隔 +0.1s = 用户验收要求；音量参数本项目 `Sound` 命令不读；第 3 组 = 用户验收描述（原版 4 行原样保留在 CSV 注释里，可一键换回） |
| `final` | 第 47 行 `$pi` → 字面量 `3.141592653589793` | 本项目解释器不内置 `$pi`；数值完全等价 |
| `spiral1/2/3` | 本项目自建 | 参考仓库的终盘阶段④（旋转持续光束）按难度拆成三档；`spiral3` 的参数逐字来自 `sans_final` |


## 接管轮（2026-10-05）：交接三项 + 模拟器实跑到结局

这一轮只做验证与补工具，**没有改动任何 `lua/` 源码**（存档因此与上一轮逐字节同尺寸 300,771 bytes）。

| 项 | 结果 | 证据（级别） |
|---|---|---|
| `_geometry` 新龙骨炮外观 | **33 PASS / 0 FAIL**，48,302 条命令"绘制 == 判定" | `node tools/run-lua.mjs lua/_geometry.lua`（L1 离线） |
| `_pool` 运行期追加 | 四档全部 **0**；draw ERR=0；OnStart 实例化 531 | `records/play-headless/pool-latest.txt` A 节（L1 离线） |
| 存档重建 | 300,771 bytes，模板 7 / 脚本 4，契约 PASS 7/7 | `node tools/build-save.mjs` + `verify-client-pool`（L1 离线） |
| **模拟器 Runtime 实跑** | mobile-16-9 走完 **20 回合 → `阶段 attack → result (round=19)` → 击倒结局 → 重开**，全程 `pool=531`、0 错误 | `tools/play-headless.mjs` + `records/play-headless/**`（模拟器证据，非真机） |
| PC 画布 | pc-16-9（1600×900，S=1.875、OX=200，键鼠设备）0 错误 | 同上 `records/play-headless/pc/**` |

新工具 **`tools/play-headless.mjs`**：用 `studio/index.js` 的 `createStudio` 直接加载存档、
`playStart/playStep/playPointer/playGet` 驱动，`host-png.js` 的 `renderScenePng` 出 PNG。
它不依赖 dsh-plugin（正式 `qxqy_studio_play` 工具只在装好插件的 DSH 会话里可见），离线/CI 可用：

```powershell
node tools/play-headless.mjs --seconds 360 --shots 0,1,120,240,330,355        # mobile-16-9
node tools/play-headless.mjs --canvas pc-16-9 --seconds 40 --shots 0,1,20,40
node tools/play-headless.mjs --seconds 60 --drive none                       # 只推进、不给输入
```

驱动坐标由「世界 640×480」换算到当前画布（`w2c`），换画布不用改常量；产物在
`records/play-headless/<outdir>/`（`run.json` + `logs.txt` + 各时刻 PNG）。

> 结局截图用的是**测试变体** `records/play-headless/debug-hp9999.save.json`（只把 main.lua 的
> `hp = 92` 换成 9999，让不会闪避的自动点击机器人活到最后），**不是交付存档**；交付存档仍是
> `sans-fight.save.json`（HP 92）。

## 可躲避性 / 跳跃速度 / 平台 / 初见杀节奏（2026-10-05，按试玩反馈 3）

| 项 | 改动 | 依据 |
|---|---|---|
| **「两侧向中间」的包围型攻击躲不掉（真 bug）** | 灵魂判定半径是 8 → 判定盒 **16×16**，而 `bonegap1` 两骨之间的骨缝只有 **14px** → 数学上就钻不过去。改成原版/BTS 口径：**判定盒 8×8（半径 4）**；另设 `SOUL_CLAMP = 8`（心形视觉半宽）**只**用于框内钳位与站台，保证心本身不画出框外、也能稳稳站在平台/地面上 | 探针：骨缝 14px vs 判定 8px → 钻得过去；轻按跳 28px（框高 140 的 1/5）→ 灵魂从框底 383 升到 355，正落在骨缝 352..366 → **可躲** |
| **蓝心跳跃的「上升速度」表述纠正** | 改成**匀速上升**：速度 = 框高 × 0.5 / 1s，**大小跳同一个速度**；目标高度 = 速度 × 按住时长（下限 1/5、上限 1/2 框高）→ 高度随按住时长**线性**；松手/到顶即交回重力。另在 `Game:jump` 加「空中不再触发」兜底（按住不会反复起跳） | 框高 140 实测：轻按 30px(22%)、0.6s 44px(32%)、0.8s 58px(42%)、1.0s 72px(52%)、≥1s 封顶 ✓ 线性 |
| **平台攻击仿原作** | 站到移动平台上会**被平台带着走**（原来平台一动、人要一直按方向键，否则直接掉下去）——原作就是站上去跟着走 | `CMD.Platform` 的 dir/speed 直接推动 `soul.x`（并钳在框内） |
| **初见杀龙骨炮间隔 +0.1s** | `sans_intro.csv` 四组龙骨炮之间的延时各 +0.1s（1.1→1.2 / 0.9→1.0 / 0.9→1.0 / 0.7→0.8）；脚本时长由 `scriptLength()` 自动延长，回合不会被掐断 | 用户验收「初见杀的龙骨炮攻击间隔略微延长 0.1s」 |

## 脚本骨判定 / 心形图元修正（2026-10-05，按试玩反馈 2）

| 项 | 改动 | 依据 |
|---|---|---|
| **蓝心依旧没有碰撞箱（真 bug，影响所有脚本骨）** | 根因：`pushBone` 造的**脚本骨（BoneV / BoneH / BoneVRepeat / BoneHRepeat）从来没写 `lethal` 字段**，而碰撞循环第一句是 `if bn.lethal then ... end` → 这些骨头**全部穿人**。`bonegap* / boneslide* / platforms* / platformblaster / multi* / final / spiral3` 这些靠脚本骨的关卡全中招 —— 这既是「蓝心没有碰撞箱」，也是红魂关里"骨头擦过去没反应"的来源。现在 `pushBone` 里 `lethal = true` | 探针：`core.commands.BoneV` 造的骨头 `lethal=nil` → 修后 `true`；压在灵魂上 90 帧由 **0 次掉血 → 9 次**；同一回合 HP 从 67/92 变成 25/92（骨头真的在打人了） |
| **蓝心图案错误（真 bug）** | 根因：`circle(x, y, d)` 的 `(x,y)` 是**左上角**（和 `rrect` 的中心锚点不同），红蓝心都用 `circle(x∓3.5, y-2.5, 9)` 摆两瓣 → 两个圆瓣整体**右下偏 (4.5,4.5)**，心形看着是歪的一坨。改成 `circle(x-8, y-7, 9)` / `circle(x-1, y-7, 9)`（圆心正好落在 x∓3.5, y-2.5）；`heart()`（菜单/子面板的小红心）同一处错误一并修正 | 用户反馈「蓝心图案错误」；放大截图对比（修前歪、修后是标准心形） |
| **红蓝心碰撞箱绑定** | 判定半径两边本来就都是 `SOUL_R=8`；这次把**视觉外接盒**也收成 ±8（两瓣 x±8 / y-7，三角 y-7..y+8），所以红心蓝心是同一个碰撞箱、而且和画出来的形状一致 | 用户验收「将蓝心和红心碰撞箱绑定」；`_geometry` 的灵魂期望同步改成新图元坐标，33 PASS |
验证（本轮重跑）：脚本骨探针 **0 → 9 次掉血**；同一回合 HP 67→25；六套快速回归 + `build-save` + `verify-client-pool` = **8/8**；
`_geometry` **33 PASS / 0 FAIL**（灵魂三件套期望已同步）；`_pool` 四档 **运行期追加=0**、`draw ERR=0`、`OnStart 实例化=692`，峰值 407
（rect 69 / circle 245 / rot 76 / rtri 3 / ring 1 / text 12 / cursor 1）；存档 318,310 bytes。
截图：`records/captures/heart-fixed-zoom.png`、`heart-blue-fixed.png`（标准心形）、`final-heart/**`（同一回合 HP 25/92 = 骨头真的在打）。

## 旋转 / 跳跃 / 碰撞修正轮（2026-10-05，按试玩反馈）

| 项 | 改动 | 依据 |
|---|---|---|
| **上下龙骨炮没有发射动画（真 bug，影响所有旋转件）** | 运行时的签名是 `SetLocalRotation(x, y, z)`，适配层只传了一个参数 → 角度写进了 **X 轴**，2D 真正用的 **Z 永远是 0** ——「旋转件从来没转起来」。斜/竖的光束因此被画成横的、直接飞出画面。改成 `c:SetLocalRotation(0, 0, deg)` | 用户在试玩里看到「上下的龙骨炮丢失发射动画」；探针：光束控件的 scene matrix `a=1,b=0,c=0,d=1`（无旋转）+ paint 中心在画布外 → 修复后 4 条斜光束正常交叉、竖光束正常落地 |
| **蓝心跳跃高度** | 按验收数值重做：目标高度 = 框高 ×(0.2 → 0.5)，随按住时长在 **1s 内线性**增长；上升期用**弹道伺服**（每帧把 vy 设成「从当前位置恰好飞到目标高度」所需的速度 `v=√(2gΔh)`），松手/按满 1s 后目标冻结、交回重力 | 用户验收「轻按 1/5 框高、长按 1s 1/2 框高、线性增长」；框高 260 实测：轻按 **63px(24%)**、0.5s **89px(34%)**、1s **128px(49%)**（目标 52/91/130） |
| **蓝心碰撞箱** | 确认骨头/平台碰撞都正常（探针：压在致命骨上 120 帧掉 9 次血；静态平台上能站住 `soul.y=平台顶-8`）。为堵住唯一可疑路径：脚本 `HeartTeleport` 之后**立刻把 soul 钳回框内** —— 否则 soul 落在 frame② 判定框外时，碰撞会被 `outside` 守卫整段跳过（表现就是「没有碰撞箱」） | 用户反馈 + 探针复核 |
验证（本轮重跑）：六套快速回归 + `build-save` + `verify-client-pool` = **8/8**；`_geometry` **33 PASS / 0 FAIL**；
`_pool` 四档 **运行期追加=0**、`draw ERR=0`、`OnStart 实例化=692`，峰值 406（rect 68 / circle 245 / rot 76 / rtri 3 / ring 1 / text 12 / cursor 1）；
存档 317,546 bytes。截图：`records/captures/final-beams/**`（斜光束 X 形）、`final-blue2/**`（蓝心贴地）、`vert3/**`。

## 灵魂 / 判定修正轮（2026-10-05，按截图反馈）

| 项 | 改动 | 依据 |
|---|---|---|
| **蓝魂关卡变成红魂（真 bug）** | 根因：`startEnemy` 在**挂完脚本之后**又把 `soul.x/y/mode` 覆盖成「框中心 + 按 pattern 猜的红/蓝」，而逐帧只做 `soul → heart` **单向镜像** —— 脚本里的 `HeartTeleport / HeartMode / SansSlam / HeartMaxFallSpeed` **全部失效**（bonegap/bluebone/platforms/multi 这些蓝魂关卡因此全变红魂、还被拉回框中心浮着）。现在：心指令打**分开的**脏标记（位置 / 模式 / 初速），update 里采纳进 `game.soul`：位置只由 `HeartTeleport` 挪（`HeartMode` 不再顺带搬位置）、`HeartMode 1` 切蓝魂+重力、`SansSlam` 只借初速、`HeartMaxFallSpeed` 当下落限速；红魂在给了 `maxFall` 时也吃重力（原作最终回合的反向重力走廊） | 用户截图「这些场景应该是有重力的蓝心」；20 回合探针：`sans_bonegap1 / bluebone / boneslideh / multi1 / bonegap2 / platforms1-4 / platformblaster` 全部 `mode=blue` 且灵魂落到框底（距地 0），`bonestab*/randomblaster/spiral*` 仍红魂 ✓ |
| **骨头判定有偏差（真 bug）** | `drawBone` 的圆帽坐标算错：19 宽的骨头上两个 13 直径的圆只铺到 `x-6.5..x+12.5`，而判定矩形是 `x..x+19` —— 视觉比判定**偏左半个骨头**（擦着骨头过去却掉血 / 明明重叠却没事）。现在圆帽正好铺满骨头矩形（左圆左边缘 = x、右圆右边缘 = x+w），骨头宽/厚 < 13 时自动收窄 | 用户截图；`_geometry`「绘制 == 判定」仍 33 PASS / 0 FAIL |

验证（本轮重跑）：

* `_geometry` **33 PASS / 0 FAIL**（灵魂期望已改成「位置由脚本 HeartTeleport 决定」，骨头的绘制/判定仍逐帧对账）；
* `_pool` 四档 **运行期追加=0**、`draw ERR=0`、`OnStart 实例化=692`，峰值仍是 406（rect 68 / circle 245 / rot 76 / rtri 3 / ring 1 / text 12 / cursor 1）；
* 六套快速回归 **6/6**；`build-save` + `verify-client-pool` 通过；
* 蓝魂探针：20 个回合里 11 个脚本回合 `mode=blue` 且灵魂落到框底（距地 0），其余红魂回合仍是红心浮空；
* 截图：`records/captures/final-blue/**`（ROUND 4：蓝色横骨 + 蓝心贴地）、`seq2/**`（红魂对比）。
顺带：`cmd.HeartMode` 之类的测试夹具（`core_selftest` 的正弦骨探针、`_input` 的「红魂上键 = 普通上移」用例）改成用**无脚本回合**取红魂，
因为现在"脚本的 HeartMode 才是权威"——有脚本时不能再假设红魂。

## 玩法修正轮（2026-10-05，按试玩反馈）

| 项 | 改动 | 依据 |
|---|---|---|
| **低血量「受击判定消失」（真 bug）** | 根因：`hurt()` 把 KR 增量按 `hpBefore-1` 截断 —— 血量 2~3 时 KR 只加 0~2，紫条几乎不动、看着像没挨打。改成照原作**每次命中都加满 KR**；「不致死」继续由 `updateKR` 的 `hp>1` 下限保证 | 用户反馈；`core_selftest` 的 kr-floor 用例同步改成 `hit hp=1 kr=4`（血量一路掉到 0=fail 的整场模拟也复现过） |
| **sans 再上移** | `y = 框顶 - 16 - SANS_H`：站在框**上方**留 16px 空隙（原来 +6 是轻微重叠、贴着框） | 用户验收「不要贴着战斗框」 |
| **红心碰撞箱贴合** | 心整体改成**以 (x,y) 为中心、外接半径 ≈8**（= `SOUL_R`/`HEART_HIT` 同一口径）。旧画法整体偏右下（圆心 x+3.5、底尖到 y+13），贴框时会露到框外，而碰撞/钳位用的是中心 ±8 | 用户验收「以中心点为标准会出现红心超出战斗框」 |
| **蓝心变高跳（新）** | 轻点 = 0.72 倍初速（实测跳 **105px**）；按住继续给向上加速度，上升量封顶 `box.h * 0.5`（实测 **131px** ≈ 半框 130px）；落地重置。适配层在蓝魂态把 `jumpHeld` 透给 core（原来只给"按下沿"，长按完全没反应） | 用户验收「很多场景长按跳跃没实现 / 高度随按住时长、上限约半框」；`_tmp` 探针实测 1/2/4/8/16/40/120 帧的跳高曲线 |
| **攻击模板叠加（真 bug）** | 根因：`BlackScreen` 只清 `bones/sine/blasters` —— multi2/3 的 `Attack5` 用 `Platform` 摆落脚板，下一段的 BlackScreen 清不掉 → 平台跨段一直挂着。现在 BlackScreen 连 `platforms`（和 persistent 名单）一起清 | multi2/3 CSV 里 Attack5→Attack6 之间只有 `BlackScreen` 一道清场 |
| **浮空板关卡的底骨** | `platforms4` / `platforms4hard` 的底部骨毯：`60 根 × 间距 15、速度 60 横扫` → **静止**、29 根从 x=122 起，正好铺满框 113..548 | 用户验收「地面骨头可以保持静止，避免攻击超出战斗框范围」 |
| **sans 砸击方向箭头（新）** | 蓝眼/砸击预警时在 sans **右侧**画一支黄色箭头，指向 = body 手势方向（东/南/西/北）；朝向映射与 `drawStab` 的骨刺尖端同一套（不用三角函数） | 用户验收「蓝眼形态手势指向不明确，改成右侧箭头提示」 |

验证（本轮重跑）：

* 六套快速回归 + `build-save` + `verify-client-pool` = **8/8**；`_geometry` **33 PASS / 0 FAIL**（心的期望值已改成三件、中心锚点）；
* `_pool` 四档 **运行期追加=0**、`draw ERR=0`、`OnStart 实例化=692`；**新峰值 406**（rect 68 / circle 245 / rot 76 / rtri 3 / ring 1 / text 12 / cursor 1）
  —— 比上一轮 560 低，因为 `platforms4/4hard` 的底骨从 60 根横扫改成了 29 根静止；BUDGET 保持 690（池是启动期预分配，多出的空槽不写入）；
* 变高跳实测（框高 260）：按住 1 帧 → **105px**、按住 ≥16 帧 → **131px**（上限 130 = 半个框高）；
* 低血量：`hp=2` 命中后 `hp=1 kr=4`（旧实现是 kr=1）；
* `BlackScreen` 后 `bones/sine/blasters/platforms` 全为 0；
* 截图：`records/captures/arrow2/**`（砸击箭头 下/上 两个方向）、`ship4r0/**`（Sans 在框上方）、`ship4blue/**`（心居中）、`ship4plat/**`（浮空板关卡）。
顺带修了个流程坑：`prototype/attacks/spiral{1,2,3}.csv` 补成**正式 CSV**（原来只写在 attacks.lua 里），
这样 `node tools/gen-attacks.mjs` 重新生成不会再丢螺旋档（本轮踩到过一次，`_rounds`/`core_selftest` 立刻变红）。

## 排版修正轮（2026-10-05，按验收快照）

| 项 | 改动 | 依据 |
|---|---|---|
| **脚本骨锚点（真 bug）** | `BoneV/BoneH/BoneVRepeat/BoneHRepeat` 的 `(X,Y)` 是**左上角**（参考实现里 C2 骨头的原点是 top-center/左上）。旧实现渲染与判定都按**中心**算 → 整根偏 `(-w/2,-h/2)`：高骨戳出框顶、底部矮骨浮在半空、两侧骨缝互相错位。现在判定（`update` 的 `rc`）与渲染（`render` 的 `bx,by`）都按左上角 | 三处 CSV 交叉验证：`sans_bonegap1`（高 95@257 / 矮 20@366 正好在 133..508×251..391 里留出 14px 骨缝）、`sans_bonegap2`（`YB=386-HeightB` 的矮骨底边压在框底）、`multi1:Attack5`（`BoneVRepeat,121,364,30,2,0,25,16` 的静态矮骨正好铺满 121..526 的框底） |
| **骨群排布方向（真 bug）** | 重复骨群/平台群要排在**来向**（领头骨后面）才会依次到达 —— 规则 = 与运动方向相反（东行往西排、西行往东排、南行往北排、北行往南排）。旧实现四种方向**全反**，起手整排骨同时压在框里 | 用户反馈「两侧交错骨头定位错误」；`sans_boneslideh`（右侧 513 往西的高骨，只有排在更东边才能一根根进场）、`multi1:Attack4`（`BoneVRepeat,-64,...` 的"高速骨流"）、`multi1:Attack5`（静态矮骨铺满框底） |
| **sans 位置** | 从屏幕下方搬到**战斗框正上方**：`y = 框顶 + 6 - SANS_H`（脚踩框顶、6px 轻微重叠），对齐参考实现（BTS 里 sans 的脚在框顶一带） | BTS 布局 `Enemies` 层：head@128 torso@176 legs@224（脚 ≈247）、框顶 226 |
| **sans 尺寸** | 横向 `SANS_SX=1.15`、纵向 `SANS_SY=0.95` **分别**缩放，锚点取**脚底**（宽一点、矮一点；横向变宽不挪位置、纵向变矮只是头顶下移） | 用户验收「可以扩大一点」+「纵向应该缩小」 |
| 锁进程 | `README.md` / `tools/play-headless.mjs` 之前的写法锁随沙箱解除后消失：README 已按最近两轮改写，重复的 `play-headless.mjs` 已删除（规范名 = `tools/play-capture.mjs`） | — |

验证：`_rounds` 的 sans 站位断言改成「脚踩框顶」；`_geometry` 的脚本骨期望值改成左上角；六套快速回归 8/8 通过；
`_geometry` / `_pool` 见 `records/captures/geometry-5.txt`、`pool-5.txt`。截图 `records/captures/ship3r0/**`（Sans 站在框上方 + 骨流）、`ship3r19/**`（螺旋档）、`fix2r4/**`（交错横向骨）。

## 参考学习轮（2026-10-05）：6nimmt 经验 + 两项验收修复

参考仓库 `nightingale-0/millastra-6nimmt`（纯 UI 的千星 Lua 奇域仓库，快照在 `workspace/_refs/millastra-6nimmt`）——
完整笔记见 [docs/ref-millastra-6nimmt.md](../docs/ref-millastra-6nimmt.md)。本轮采纳 3 条 + 修 2 件事：

| 项 | 改动 | 依据 |
|---|---|---|
| **客户端没有 require（真机风险）** | 存档脚本从「boot + 3 条路径模块」改成**自足单文件**：自带 `local __modules/require` 垫片，把 core/attacks/main 原样内联；存档里只剩 **1 条脚本**（≈208 KB） | 6nimmt `AGENTS.md`：官方客户端沙箱没有 require 全局（实测结论）；`scripts/build.mjs` 的 `bundleModules` 同做法 |
| **背景 3 倍画布** | `bgPanel` 由 `CW×CH` 改成 `put(bgPanel,-CW,-CH, CW*3, CH*3)`（3 倍居中） | 6nimmt `build.mjs`：`rect(Background,640,360,3840,2160)` —— 21:9 也要盖住舞台 |
| **显式层序** | `OnStart` 末尾 `bgPanel:SetAsFirstSibling()` / `flash:SetAsLastSibling()`，不再只靠创建顺序 | 6nimmt `AGENTS.md`：真机同级层叠顺序可能与模拟器相反 |
| **「龙骨炮图像滞留在场上」→ 其实是横骨画错** | **根因**：core 渲染脚本骨时恒写 `vertical = (bn.kind ~= 'blue')`，于是 `BoneH/BoneHRepeat`（宽 200、厚 19 的**横**骨）被当**竖骨**画：只剩 7×7 的骨干 + 4 个骨帽（场上一堆不消失的白色方块），而**判定仍是 200×19 的横条**（看得见的打不到、打得到的看不见）。**改法**：`pushBone` 记录 `axis`，渲染按 `axis` 出朝向；`_geometry` 的期望值也从硬编码 `true` 改成按 axis 推 | 试玩截图 + `DBGbone` 探针（`t=14 r=1 tiny=9 (30,201 200x19) …`）；`sans_boneslidev.csv` 的 `BoneHRepeat,130,-10,200,1,300,7,183` |
| **sans 模型放大** | `SANS_SCALE = 1.15`，锚点取**参考身高中线**（头顶往上长、脚底只出屏 5px 被选项栏遮住）；零件尺寸/偏移全部按 K 缩放，`cmd.y` 语义不变 | 用户验收「sans 模型可以扩大一点」 |

验证（本轮重跑）：`_geometry` **33 PASS / 0 FAIL**（期望值已改成按 axis 判朝向）；
`_pool` 四档全部 `运行期追加=0`、`draw ERR=0`、`OnStart 实例化=692`（骨群排布修正后峰值变大，BUDGET 已同步抬到 690）
（`rect 99 / circle 369 / rot 76 / rtri 2 / ring 1 / text 12 / cursor 1`，合计 560）；
六套快速回归 + `build-save` + `verify-client-pool` 全绿；内联包用 fengari 编译通过、模拟器实测 `mode=core`（不再是内置演示）。
截图：`records/captures/ship2/**`（回合 2 的横向长骨）、`records/captures/ship2r19/**`（放大后的 sans + 螺旋档）。
> 横骨那条 bug 是**判定与视觉不一致**，比"多画了几个方块"严重：修好之前，`sans_boneslidev` 这一档的骨头
> 会隐形地扫过玩家。`_geometry`（绘制 == 判定）当时**没能抓住它**，因为期望值里把朝向硬编码成了 `true` ——
> 本轮已把期望值改成与 core 同源的轴判断，之后再画错朝向会直接变红。

## 视觉 / 手感修正轮（2026-10-05，按用户验收）

| 项 | 改动 | 依据 |
|---|---|---|
| **背景纯黑** | 新增 `bgPanel`（`OnStart` 里**最先**创建的全屏矩形 → 兄弟序最底层），盖住模拟器舞台的深蓝渐变 | 参考实现 Background 层是纯黑场景 |
| **等级/血量 UI 搬到选项栏上方** | HUD 从屏幕左上搬到世界 **y=403** 那一行：左 = `LV 19` / `HP n/92` / 血条 / `KR n`，右 = `ROUND n/20` / `难度` | BTS `Background` 层：HP 文本 y=400、血条 y=416；`Buttons` 层按钮 y=432 |
| **血条（新）** | `hudBar` 命令：底槽 + **黄色 HP** + **紫色 KR**；口径 = 黄段 `hp-kr`、紫段 `kr` —— KR 燃烧时黄段不动、紫段变短 | 原作 KR 血条口径 |
| **龙骨炮大小** | Size 0/1/2 → 骷髅 ×**0.8 / 1.0 / 1.3**（旧实现只让光束变宽、炮身永远一样大 → 用户说的「大小需修正」） | BTS `GasterBlaster` 的 Size 参数 |
| **龙骨炮形象** | 重画成原版**长吻头骨**：后颅 32×44 + 吻部 34×22 + 2 眼窝 11×12 + 口腔 18×9 + 牙条 14×4，整体 ≈**59×44** | `.ref/data.js` 里 `gasterblaster-sheet0.png` 帧 = **57×44** |
| **龙骨炮不再压选项栏** | 新增停靠安全区 `BLASTER_SAFE`，开火位置钳到 `y ≤ 372` → 整只骷髅落在 HUD 行上方（起点不钳，仍照原版从屏幕角飞入） | 用户验收「龙骨炮不要在选项栏方向出现」 |
| **光束** | 默认长度 360 → **1200**（判定带是 2000px，画到能盖住整屏）；外壳亮度 0.45 → 0.78 | 「看得见的打得到」 |
| **内置龙骨炮（兜底路径）** | 修 2 个真 bug：① 渲染恒画在 `zone` 左上角（和 axis/pos 判定带对不上）→ 按 axis/side 停在框外朝框内；② 永远停在 `charge` 从不发射 → 补 `warn→fire` | `lua/_check.lua` 四档空跑 |
| **KR（蓝血）机制** | ① 治疗道具**清空 KR**（原作「业障被治掉」）；② KR 在**攻击条阶段也继续燃烧**（原作整段玩家回合都在烧，旧实现白送几秒喘息） | 原作 KR 机制 |

验证（本轮重跑）：`_geometry` / `_pool` / 六套快速回归 / `build-save` + `verify-client-pool` 全绿；
`_pool` 四档 `运行期追加=0`、`draw ERR=0`、`OnStart 实例化=692`（690 + 背景板 1 + 闪层 1）；
新峰值 `rect 99 / circle 369 / rot 76 / rtri 2 / ring 1 / text 12 / cursor 1`（合计 560，仍在 BUDGET 内）。
模拟器无头截图见 `records/captures/**`（r0 = 回合 0 的骨刺/正弦骨/龙骨炮，r19 = 螺旋龙骨炮三档）。

## 本轮（20 回合结构 / 2026-10-05）

| 项 | 前 → 后 | 依据（证据级别） |
|---|---|---|
| 回合并发数 | 6 回合 + 最终三段 → **20 回合**（内部号 0..19，HUD 显示号 = 内部号 + 1） | `_rounds.lua` 54 PASS：0 = 见面杀、1..16 随机、17/18/19 = spiral1/2/3、走完 20 回合能到结局 |
| 每回合的攻击来源 | 内置生成器（bone_floor/bone_wall/...） → **随机抽 attacks.lua 模板**（四档分档、相邻不重复、优先没抽过的、12 次采样） | `_rounds.lua`（档位包含性、不重复、同 seed 可复现）；日志 `round_script round=N script=X used=K` |
| 内置生成器 | 主路径 → **兜底路径**（只在没有脚本时跑，测试钩子 `newGame({ noScriptRounds = true })`） | `core_selftest` 的 bone-telegraph / bone_wall / difficulty 三组用例走这条路径 |
| 最后三回合 | 「最终回合分三段」（`FINAL_PHASES` + `finalPhase`） → **螺旋龙骨炮三档** | `_rounds.lua`：spiral3 的 13 行几何与原版 `sans_final` 阶段④**逐字一致**、三档强度 140 < 160 < 190；`core_selftest`：全部 27 个脚本 90s 内 EndAttack（spiral3 打出 122 发，与原版"约 122 发"一致） |
| 回合结束残留实体（用户实测） | 骨墙/平台/骨头留在场上 → **清空** | `_rounds.lua`：20 个回合逐个验证"清场后实体 0 且菜单态不再渲染" |
| `mulberry32` 随机数 | 恒 ~1e-5（`rng() < 0.5` 恒真、`floor(rng()*n)` 恒 0） → **正确** | `core_selftest` extra-rng：4 seed × 6 值与 JS 原型逐值一致 + 200 次取值铺开断言 |
| sans / 龙骨炮形象 | 无 sans；龙骨炮是旋转方块 → **图元拼装**（sans ≤13 件、龙骨炮 ≤14 件） | `_check`/`_flow` 无 `draw ERR`、`inst NIL`；**外观实机观感尚未确认**（见下） |
| 控件池预算 | 354 → **530**（rect 57→84、circle 179→318、rot 96→106） | `_pool.lua` 重测（含螺旋档，四档取大）：rect 70 / circle 265 / rot 88 / rtri 2 / ring 1 / text 12 / cursor 1 |

**已跑的回归（全部离线，`tools/run-lua.mjs`）**：`_rounds` 54 PASS / 0 FAIL；`core_selftest`
215 PASS / 0 FAIL（含 27 个脚本空跑）；`_tap` 40 / `_title` 33 / `_input` 249 pass；`_flow`
整场跑到 round=19 → `kill` 结局（t=338.7s，绘制框溢出 0、结局文字已渲染、按钮行 0 违规）；
`_geometry` 33 PASS（20 回合下 48,272 条实体命令"绘制 == 判定"对账）。

**接手轮已把这三件全部验证（2026-10-05，见本文最上面的「接管轮」）**：
1. `_geometry` 在**新龙骨炮外观**下重跑 → **33 PASS / 0 FAIL**（48,302 条实体命令"绘制 == 判定"逐帧对账）。
2. `_pool.lua` 重跑 → 四档（pc-normal / touch-normal / easy / hard / original）全部 **`运行期追加=0`**、
   `draw ERR=0`、`未注册 guid=0`；`OnStart 实例化=531`。BUDGET 530 + 闪层 1 = 531，压住了运行期新建。
3. 存档已用新代码重建（`node tools/build-save.mjs` → 300,771 bytes，`verify-client-pool` PASS 7/7）；
   并新增 `tools/play-headless.mjs`，在模拟器 Runtime 里从标题页实跑到 **击倒结局**（见下节）。

## 本轮（optimized / 内容优化，不加功能）

| 项 | 前 → 后 | 依据 |
|---|---|---|
| 客户端模板数 | 9 → **7**（删 `100004 fourstar` 1073743005、`100003` 左下锚点三角 1073743003） | `take()` 全量检索 + `lua/_pool.lua` C 节：整场实例化次数 0 |
| 控件池预分配 BUDGET | 合计 345 → **354**（rect 168→57、circle 96→179、rot 40→96、rtri 8→4、ring 8→2、text 12→15、cursor 1；tri/star 随模板删除）。试玩日志 `pool=` 含闪层 1 个：346 → 355 | `lua/_pool.lua` 峰值：rect 47 / circle 149 / rot 80 / rtri 2 / ring 1 / text 12 / cursor 1，统一 +20% |
| 试玩中运行期追加实例化 | 70~93 次 → **0 次** | 旧预算 circle/rot 欠配（峰值 149/80 > 96/40），take() 取不到就当场新建 |
| 存档字节数 | 276,997 → **269,245**（-7,752） | `node tools/build-save.mjs` |
| 每帧控件写入 | 16.54 → **16.53 次/帧**（冗余写入 2/171,869 = 0.00%） | 文本 memo 本来就只写变化值，未改 |
| 模拟器实测（mobile-16-9，`BUILD=2026-10-05-optimized`） | `main start: … pool=355`；整场 5 秒日志 `pool=355` 恒定不增长（旧版会涨到 346+70）；无 WARN / `inst NIL` / `draw ERR` | `records/optimized-r3-bones.png`（回合 3：白骨 + 蓝骨 + 战斗框 + 心位置正确） |

**为什么池预算反而变大**：实测 peaks 是 292（四档难度取大），旧值不是超配而是**错配** ——
rect 超配 3.6×，circle/rot 欠配 1.6~2×。欠配的代价是运行期新建控件，而新控件按创建顺序排在
**闪层之后**（会盖住全屏闪），所以预算必须 ≥ 峰值。测量方法与峰值表写在 `lua/main.lua` 的 BUDGET 注释里。

## 本轮（layout-center / 按键诊断）

**按钮行的定位规则换了**：旧规则「框下沿 +12px，再钳到世界内 y≤434」有两个毛病 —— 小框相位 403、
大框相位 434（两个相位差 **31px**，与屏幕中心毫无固定关系），而且常规大框底边 **438.5 > 434**，
行其实压在框里（实测重叠 4.5px）。现在按参考实现（原版 Construct 2 导出 `data.js` 的
`BattleScreen` / `Buttons` 图层：四个 110×42 按钮 y=432）取：

```lua
CENTER_Y = 240 ; MENU_ROW_DY_TOP = 192      -- 行顶边 = 240 + 192 = 432（参考实现逐像素一致）
MENU_ROW_GAP = 2 ; MENU_ROW_BOTTOM_MARGIN = 3
y = clamp(max(CENTER_Y + MENU_ROW_DY_TOP, boxBottom + GAP), -inf, 480 - bh - MARGIN)
```

实测三个相位：框底 391 → 行 432（与参考实现的「框底→行顶 41px」完全一致）；
框底 438.5 → 行 440.5（不重叠）；终盘超大框框底 478.5 → 被上界钳到 441（下方只剩 1.5px，
物理上放不下 36px 的行，是**唯一**允许重叠的情形）。`lua/_flow.lua` 逐帧断言：
2130 个按钮行帧里「偏离常量公式 0 帧、越界 0 帧、框下有空间却重叠 0 帧」。

**按键诊断（只打一次）**：`lua/main.lua` 的 `bind()` 会在**收到第一个键盘事件**时打
`main: 收到按键事件 <事件名>（若你按了 WASD 却从未出现这行，说明试玩页那层没转发按键）`
—— 一眼区分「试玩页没转发」和「游戏没响应」。

**插件试玩页的 WASD（结论已改写）**：物理键→语义键的映射表在磁盘上**已经补齐**（5 份产物），
插件的试玩页加载的是 `%DSH_HOME%\profiles\web\node_modules\dsh-plugin-beyond-simulator\dsh-plugin\dist\play-renderer.js`
（`index.js` 的 `Nu()` 读它并**缓存一次**）。但实测运行中的 `dsh web` 仍在发**补表之前**的字节
（`Invoke-WebRequest /qxqy-simulator/play-renderer.js` → SHA256 == `.bak-pre-keymap`，`MoveForwardKey=0`）
→ **必须重启 `dsh web`**，刷新页面不够。详见 `docs/plugin-keymap.md` 第 3 节。

## 最近一轮修复（结局白屏 + 自动化两个坑）

**结局白屏（真 bug，已修）**：`result` 态下 core 每帧推 `flash alpha=1`，而适配层的闪层是**最后创建的最上层**
全屏控件 → 永久盖住「GAME OVER / 击倒结局 / 饶恕结局」文字与「重开」项，玩家只看到白屏。
现象证据：子代理跑到终盘第 2 阶段（hp 2）时截图到"整帧纯白、无任何图元"。
修法（适配层）：结局态闪层只画 15 帧（约 0.5 秒），随后 `SetVisible(false)` 收起。

**易误读**：终盘阶段（core 的 `FINAL_PHASES`）的 `round` 是 `1/2/3`，所以日志里
`回合 6 → round=1` **不是重开**，而是进入终盘第一阶段。要看是不是重开，得看是否回到 `title`（不会）
或 `round=0`。

**自动化两个坑（已修进 `tools/gen-full-run-case.mjs`）**：
1. 用例 `dt` 必须调粗（默认 **0.2**）。`1/30` 跑 220 秒会触发 `runCase` 的 **8000 ms** 墙钟上限，
   而且**超时会直接杀掉试玩会话**（之后 `get` 返回 `play session has not started`）。
2. 按钮行 y **跟着战斗框下沿走并被钳制**（小框态 631、大框态 678），只点一个候选会出现
   "有 `游标 CursorUp ... click=true`、但没有 `点按菜单第 N 项`"，整场永远停在菜单里。
   生成器现在每波把 **631/656/678** 三个候选全点一遍。

## 已用证据闭环的

| 项 | 证据 |
|---|---|
| 客户端控件**全部**由 Lua 运行期生成 | 服务端 `n1` 下 0 个预置控件；试玩日志 `main start: mode=core pool=354`；`verify-client-pool.mjs` PASS 7/7 |
| 客户端模板池契约（guid/图元/锚点） | `node tools/verify-client-pool.mjs` → PASS（7 项契约，且断言「模板数 == 契约条数」）；存档内嵌脚本与磁盘源码一致（已逐项 grep 核对） |
| 控件池预算与实测峰值 | `node tools/run-lua.mjs lua/_pool.lua`：PC+触摸 × 四档难度各跑整场到结局，峰值 rect 47 / circle 149 / rot 80 / rtri 2 / ring 1 / text 12 / cursor 1（合计 292），BUDGET 合计 354；整场运行期追加实例化 **0** 次 |
| 标题页 + 四档难度选择 | 模拟器截图（只有选中卡高亮 + 一颗心）+ 日志 `点按难度卡 1 → 开局`；`lua/_title.lua` 19/19 |
| 回合 0→2 真实输入链路（点按/攻击条结算/框几何） | 本会话 `runCase` 通过（1096 帧）：`title → enemy(R0) → menu → attack → 结算 → enemy(R1) → … → enemy(R2)`，框在 enemy/attack 两态都是 `(110,179,420,260)`，无 WARN / draw ERR / inst NIL |
| 整场到结局（离线，两种画布） | `lua/_flow.lua`：标题页 → 回合 0→6 → 终盘三阶段 → `result`；错误 0、属性写入类型违规 0、整帧绘制失败 0 |
| 死亡 → 结局 → 重开 | `lua/_tap.lua` 18/18（重开直接回回合 0 的敌方阶段，不回标题页，与原作一致） |
| PC 画布渲染（`fontSize` 整数路径） | 模拟器 `pc-16-9`（S=1.875）渲染 285 帧零 `draw ERR`；`_tap.lua` 固定在 PC 画布跑并带整数守卫 |
| 存档可回读 | `verify-client-pool.mjs` + 脚本/模板/挂载逐项核对（boot 挂 `n1`、3 条路径模块） |

## 未验证（不要当成已通过）

1. **模拟器端回合 3→6、中场/间奏、终盘、结局画面与重开**：离线已过，真机画面未逐帧看。子代理
   （`f1369ebc`）在跑这条线，尚未回报。
2. **真机 `runtime=device`**：从未在千星真机试玩过；`qxqy_script_sync` 的 `config` 仍为 `null`，
   且本机 `discover` 没找到客户端导入目录 —— 需要用户提供导入根目录后才能配。
3. **GIA 导出后手工补挂**：GIA 不保存脚本挂载关系，导入真机后必须把 boot 重新挂到 `n1`。

## 怎么复现"整场跑通"（一次调用）

```powershell
node tools/gen-full-run-case.mjs 220 tests/full-run.case.json
```

然后把 `tests/full-run.case.json` 的内容作为 `case` 传给 `qxqy_studio_play`：

```
qxqy_studio_play { "action": "runCase", "args": { "canvasId": "mobile-16-9",
  "case": <tests/full-run.case.json 的内容> } }
```

要点（踩过）：

* 用例格式 `qxqy-autotest` v1：`{format,version,name,dt,playerCount,events[],asserts[]}`，
  事件形如 `{t, source:"user", kind:"pointer", payload:{type:"click",x,y}}`，`t` 是引擎时钟。
* **断言必须带 `at`**：不带时 runner 在 `t=0` 就求值，必失败（日志里那时还没有对应行）。
* 事件刻意冗余：每波同时点 `(370,631)` 与 `(370,678)` —— 「攻击」按钮行的 y 会随战斗框变
  （回合 0 在 631，回合 1 起被钳到 678）；点在敌方阶段/攻击条上无害。菜单会无限等输入，
  所以间隔放大到 10 秒也照样推进，用例对时序不敏感。
* 回放按 `dt=1/30` 固定步长推进，不受墙钟影响。
* **单次 `runCase` 有 8 秒墙钟上限**：实测 36 秒引擎时间的用例能跑完（约 4.5 倍速），
  但 130 秒的用例直接 `play worker timed out after 8000ms`。所以整场要拆成**多段 ≤36 秒**的用例分别跑，
  或者用人工 `pointer` + `step` 推进；不要指望一次调用跑完 220 秒。
* **更正**：把用例 `dt` 调粗（0.2）**并不能**让 220 秒的整场塞进一次调用 —— 超时看的是**墙钟**，
  而回放要推进的**引擎时间**没变（220 秒）。`dt` 只减少帧数、降低每帧开销，所以只能在边界附近起作用。
  实测两个子代理都在"跑 220 秒整场"这一步反复超时并挂住（超时还会杀掉试玩会话）。结论：
  **要一次跑到结局，只能分多段（每段 ≤36 秒引擎时间）或用人工 `pointer`+`step` 推**；
  另注意 `runCase` 会从标题页重放，分段之间不能简单接力（除非确认它保留当前运行态）。

## 本地回归一键跑

```powershell
node tools/run-lua.mjs lua/_check.lua    # 语法 + 四档难度 900 帧 + 命令直方图
node tools/run-lua.mjs lua/_input.lua    # 平台分流 + 四向矩阵 + 按钮行定位（249 pass / 0 fail）
node tools/run-lua.mjs lua/_tap.lua      # 点按链路 + 死亡/结局/重开（PC 画布，40 pass）
node tools/run-lua.mjs lua/_title.lua    # 标题页/难度选择/菜单选中判定（33 pass）
node tools/run-lua.mjs lua/_geometry.lua # 绘制 == 判定逐帧对账（33 pass / 0 fail）
node tools/run-lua.mjs lua/_flow.lua     # 整场：标题→R0..R6→终盘→结局（类型守卫 + draw ERR + 按钮行三断言）
node tools/run-lua.mjs lua/_pool.lua     # 控件池峰值 + 每帧控件写入统计（BUDGET 的依据，非断言型）
node tools/run-lua.mjs lua/core_selftest.lua   # 逻辑层自测（166 PASS / 0 FAIL）
node tools/verify-client-pool.mjs        # 客户端控件组契约（PASS 7/7）
node tools/build-save.mjs                # 重建存档（会按内容筛选编辑器快照）
```


## 全流程龙骨炮烘焙（2026-10-06，BUILD = 2026-10-06-fitblaster-all）

需求（用户口径）：**见面杀（`sans_intro`）之后的所有龙骨炮与见面杀同款** —— 也就是整场都用
`fitdata.blaster_block2` 的逐像素烘焙外观，不再出现旧的 12 件参数化骷髅。

### 改了什么

| 文件 | 改动 |
| --- | --- |
| `lua/core.lua` `CMD.GasterBlaster` | `bake = (w.scriptName == 'sans_intro')` → **`bake = true`**（脚本路径：见面杀 / multi2 / randomblaster / 终盘阶段④…） |
| `lua/core.lua` `Game:spawnBlaster` | **补上 `bake = true`**。这条内置 `blaster` 模式绕过 CMD 直接 push，漏了 bake 时会在第 5 回合（platforms1）混进旧参数化骷髅 |
| `lua/main.lua` `BUDGET` | `rect 640→200`、**`rot 106→1350`**（见下） |
| `lua/main.lua` `BUILD` | `2026-10-06-fitblaster` → `2026-10-06-fitblaster-all`（试玩页判据） |
| `lua/_rounds.lua` | 新增 4 条回归：回合 0/4/16 必须产出龙骨炮，且**全部** `bake=true`（58 PASS） |
| `lua/_flow.lua` | 修测试台：白名单补 `SetAnchorMin/SetAnchorMax/SetPivot/SetLocalScale`；帧预算 11000→18000 |

### 关键结论：烘焙龙骨炮吃的是 **rot 池**，不是 rect 池

`main.drawBlaster` 的 bake 分支逐条走 `rrect()` → `take('rot')`。每发 = block2 的 112~126 个
rrect + 光束 2 + 炮口亮块 1 ≈ **129 件**。所以「全流程烘焙」后 rot 峰值会从原来的 106 档直接跳到：

| 场景 | 同屏龙骨炮 | rot 件数 |
| --- | --- | --- |
| 见面杀 `sans_intro` | 4 | ≈ 517 |
| `multi2`（内部回合 16） | 4 | ≈ 516 |
| **终盘 `final` 阶段④ 旋转光束（内部回合 23）** | **9** | **≈ 1221（实测峰值）** |

上一轮把预算加在 `rect` 上是**误判**（实测 rect 峰值只有 48）—— 这一轮把那 440 个多余槽位还给了 rot。
`take()` 取不到时会当场实例化一个新控件，而新控件排在闪层**之后** → 会画在全屏闪层之上
（终盘阶段③的黑屏闪正好紧挨阶段④的旋转光束），所以必须预热到位。

### 测量与证据

```powershell
node tools/run-lua.mjs lua/_probe_bake.lua    # 每回合同屏龙骨炮峰值 + bake 校对 + 时间窗
node tools/run-lua.mjs lua/_probe_pool2.lua   # 真实 main.lua 的控件池峰值（~3min，单场景加速版）
```

- `_probe_bake.lua`：24 个回合逐一体检，`maxBake == maxN` 全部成立；峰值 = 回合 23 `final` 的 **9 发 / 1161~1221 件**。
- `_probe_pool2.lua`（真实 `main.lua` + 真实 `fitdata`，排除烘焙容器子控件）：
  `rot 峰值 1221 @ 帧12256 round=23 final`、`circle 164`、`rect 48`；对照数据存 `records/pool-peak-allblasterbaked.txt`。
  它是 `_pool.lua` 的加速版（O(1) 可见计数器 + 单场景），整趟 40min → ~3min。
- 模拟器无头试玩（`tools/play-capture.mjs`）实拍确认：内部回合 16 同屏 4 发、回合 23 阶段④同屏 9 发
  都是 fit 像素骷髅，截图存 `records/captures/fit-all-blasterverify/`。
- 在线自检：主日志 `baked=` 字段（临时诊断，验证后已撤）在终盘阶段④打到 **1161**，与离线推算一致。

### 验收时要注意的坑

终盘阶段④的**时间窗随难度整体平移**（回合总长都是 53s）：

| 难度 | 光束窗口（回合内秒） | 同屏峰值 |
| --- | --- | --- |
| easy | 35.62 … 50.32 | 6 发 |
| normal | 30.10 … 42.78 | 6 发 |
| hard | 22.42 … 31.07 | 9 发 |
| original | 22.42 … 31.07 | 9 发 |

试玩页默认点第 1 张难度卡 = **easy**，所以 `--round 23` 截图必须等到 **t≈36s 之后**才拍得到龙骨炮；
在 24~31s 拍只会拍到空档（这一轮就是这么排查出来的）。

### 回归结果（2026-10-06）

`node tools/verify-all.mjs --quick` → **8 / 8 通过**：`_check` OK /`_rounds` 58 PASS /`core_selftest` 280 PASS /
`_tap` 40 / `_title` 33 / `_input` 249 / `build-save` OK（495,446 B）/ `verify-client-pool` 10 项契约全过。
`node tools/run-lua.mjs lua/_flow.lua` → 整场跑到结局（t=445.3s）：`draw ERR = 0`、`结局文字已渲染 = true`、
`灵魂跑出框外最大 0.0px`、按钮行三断言全过。

## 蓝心跳跃修正（统一落地模型）+ 删去方向箭头（2026-10-06）

依据：`D:\stars\docs\修改建议\Sans_Fight_蓝心跳跃修正与延时政策.md`（对照原版 `Battle.xml` 的
`HeartJump` / `HeartCheckSolid`）。**§0 政策同时生效：从本文起不再对攻击延时提任何要求**，
脚本里已调过的 `SpinTime / HoldTime / Loop / delay / Ramp / ExtraWidth` 全部保留。

### 问题（文档 R1/R2/R3）

- **R1/R2**：能不能落地是**三套判定**——蓝魂分支里的「框底 `floorY`」、分支里的「内置平台 for 循环」、
  分支之后的「脚本平台循环」。而 `jumping` 的复位只写在分支里（在脚本平台判定**之前**），
  于是落在空中板子上时 `jumping` 一直留 `true`，第 2 跳被 `Game:jump` 的
  `if self.soul.jumping then return end` 直接拦掉。
- **R3**：用**确认键**起跳时，适配层只给 `jumpHeld = input.up`；同一帧的蓝魂物理看不到「按住」，
  立刻 `jumpCut = true` 并把 `vy` 覆盖成 `fallSpeed` → 灵魂原地落回。

### 改了什么

| 文件 | 改动 |
| --- | --- |
| `lua/core.lua` | 新增 **`Game:groundQuery()`**：框边「远边」+ 内置平台 + 脚本平台**一起**算，沿重力方向取最近支撑面（= 原版 `HeartCheckSolid`） |
| `lua/core.lua` 蓝魂分支 | 删掉 `floorY` + 内置平台循环 + 复位，换成 `groundQuery` 的统一落地块；**落地复位只此一处**（框底/内置平台/脚本平台都走这里） |
| `lua/core.lua` 分支之后 | 平台循环只给「其它模式」兜底（红魂 / 箭头模块 `soul.wall` / 被甩 `slammed`），蓝魂常规物理不再重复处理 |
| `lua/core.lua` `applyInput` | `self.jumpHeld = (input.jumpHeld or input.confirm)` —— 确认键也是跳跃键 |
| `lua/core.lua` `Game:jump` | 改用 `groundQuery` 判「能不能跳」（不再读被落地顺序影响的 `soul.grounded`） |
| `lua/main.lua` | 新增 `confirmHeld` + 绑定 `KeyboardMenuConfirmKeyUp` / `KeyboardNormalAttackKeyUp`；`jumpHeld = (input.up or confirmHeld)` |
| `lua/main.lua` | **删去砸击方向提示箭头**（Sans 右侧的橙色矩形+三角）—— 用户口径「删去先前指示方向的箭头模型」 |
| `lua/core_selftest.lua` | 新增 `blue-jump-on-platform` 段 4 条断言（284 PASS） |
| `tools/play-capture.mjs` | 新增 `--jump-at <秒>`：在真机无头试玩里按一次确认键，用来复现/验收蓝心起跳 |

### 与文档示例代码的三处**有意偏离**（示例代码本身有坑）

1. **平台支撑面取「近面」而不是「远面」**。文档示例的 `far = math.max(四角 along)` 对**战斗框**是对的
   （边界，人留在框内 → 落远边），但对**平台**会取到底面 `py+ph`，灵魂会沉进板子里 7px。
   平台是实体、人站在面上 → 取 `math.min(四角 along)`（下落时 = 顶面 `py`）。
2. **多了「必须吸附到面」这一步**（`d` 正负都要补偿）。只补 `d>0` 的话，灵魂每帧被 `fallSpeed` 推下去一点，
   几帧后支撑面就掉出 2px 容差 → `grounded` 闪成 `false`（实测第 3 帧就掉下去）。
3. **多了两个守卫**：`refA = min(当前, 上一帧)`（高速下落 750px/s ≈ 25px/帧 会一帧穿过 7px 平台），
   以及 `va >= -1`（起跳第一帧 `va` 很负，不能把刚起跳判成落地）。
   另外保留了文档漏掉的 `soul.wall` 分支 —— 箭头模块的「跳跃 = 反方向冲刺」靠它，删掉会坏。

### 验收（文档 §4 的 J1–J6 全部通过）

```powershell
node tools/run-lua.mjs lua/_probe_groundjump.lua   # J1
node tools/run-lua.mjs lua/_probe_platjump.lua     # J2 / J3 / J5
node tools/run-lua.mjs lua/_probe_jumpcheck.lua    # J4（平台带走）/ J6（四向重力起跳）
```

| 编号 | 断言 | 结果 |
| --- | --- | --- |
| J1 | 地面连续两跳 | 第 1/2 跳 `vy=-336` ✅ |
| J2 | 空中板子连续两跳 | 第 1/2 跳 `vy=-336`（修复前第 2 跳 `vy=0`）✅ |
| J3 | 落在脚本平台后 `jumping` | `false`（修复前恒 `true`）✅ |
| J4 | 平台带走 | 30 帧平台 `+36.00px` / 灵魂 `+36.00px` ✅ |
| J5 | 确认键起跳 | `confirm=true` 即 `vy=-336`，不再同帧落回 ✅ |
| J6 | 方向重力起跳 | `dir=0/1/2/3` 沿重力分量全 `-336` ✅ |

真机无头复核（`--canvas pc-16-9`，键盘分支才绑键）：

```powershell
node tools/play-capture.mjs --canvas pc-16-9 --round 4 --seconds 9.4 --shots 8.1,8.6 --jump-at 8.2
```

截图：`records/captures/bluesoul-jump-fix/blue-soul-before-jump.png`（心被底部骨排挡住）
→ `blue-soul-jump-confirm-key.png`（按 Enter 后 0.4s，蓝心已升到框中部）。
同一目录还有 `sans-no-direction-arrow.png` —— 方向箭头已删除，只剩 Sans 手势。

### 回归结果（2026-10-06）

`verify-all --quick` → **8 / 8**：`_check` OK /`_rounds` 58 PASS /`core_selftest` **284 PASS** /
`_tap` 40 / `_title` 33 / `_input` 249 / `build-save` OK（501,450 B）/ `verify-client-pool` 10 项契约全过。
`_flow` 整场到结局：`draw ERR = 0`、`结局文字已渲染 = true`、`灵魂跑出框外最大 0.0px`。
`_geometry` **29 PASS / 0 FAIL**（绘制 == 判定逐帧对账，55715 条）。

## 第八轮验收：round8~22 逐条修正（2026-10-06）

| 编号（HUD） | 内部 | 脚本 | 改动 |
| --- | --- | --- | --- |
| round8 / round10 | 7 / 9 | platforms4 / platforms4hard | **修 repeatBones 公式**（见下），右侧 x=443 那列恢复成真正「向上走的竖列」 |
| round9 | 8 | platformblaster | 两发 SpinTime 统一 0.56666（原来第二发是 1.56666）；都加 HoldTime 1.5；Y 随机区间 40→60（285..345，覆盖上下两排板面之间） |
| round16 / round20 | 15 / 19 | randomblaster1 / 2 | 加 HoldTime 1.5；ExtraWidth 5（光束双向 +5px）；末尾留白 2.2/2.4s 让最后一发打得出来 |
| round17 | 16 | multi2 | Attack6 八发全部加 HoldTime 1.5；两段 1.2 → 2.6s |
| round18 / round19 | 17 / 18 | sans_bonestab1 / 2 | **甩击结束还原重力方向**（见下） |
| round22 | 21 | multi3 | Attack0/4/5 降密度降尺寸（4→3 根 @16→30、11/10→7 根 @24→40、25→16 根 @16→26；高 45→35/100→70/55→45/15→12/30→26），段长各 +1s |

### 两个真 bug（都是根因，不是调参）

1. **`repeatBones` 位移公式错**（`core.lua`）：BTS 的 BoneHRepeat/BoneVRepeat 逐个 loopindex 是
   `X = StartX − cos(Dir·90)·Spacing·i`、`Y = StartY − sin(Dir·90)·Spacing·i`（两个函数同一套）。
   旧实现只挑一个轴、还把 `dir=0/1` 一律当 −1 → **dir=1/3 的竖骨列被摊成一横行**。
   这正是用户说的「右侧本来该有循环向上移动的骨头，结果走一趟就消失」。现已逐字对齐原作。
2. **脚本执行器只转发前 8 个参数**（`World:exec` 的 `fn(self, a[1] … a[8])`）：
   `GasterBlaster` 的 **BlastTime(9) / HoldTime(10) / ExtraWidth(11) 从来没进过函数** ——
   所以 ① 所有光束实际只存在 1 帧（`g.blast` 为 nil → 立刻 done）；② 脚本里写的「光束双向 +5px」没生效；
   ③ 刚加的「落定后停 1.5s」也传不进去。现改为按实际个数转发（最多 12 个）。
   顺带把 `hold = tonumber(hold) or 0` 改成保留 nil —— 写成 `or 0` 会让 HoldTime 的默认值（0.05s）失效。

### 甩击锁控制（round18/19）

`SansSlam` 会把 `soul.dir` 改成甩出方向，而**旧实现从不还原** → 蓝心被「钉」在那一侧的框边上
（一直按住反方向也纹丝不动），玩家看到的就是「拖拽之后控制被锁死」。
新增 `Game:endSlam()`：甩击结束（超时 / 撞墙 / 落平台 / 起跳）时把 `soul.dir` 与 `world.heart.dir`
都还原成 1（南），并把 `slammed / slamT` 清零。探针实测：round18/19 期间「改过方向 = true，之后还原 dir=1 且未在甩 = true」。

### 验收（2026-10-06）

- `verify-all --quick` **8 / 8**：`_check` OK / `_rounds` 58 PASS / `core_selftest` 284 PASS / `_tap` 40 / `_title` 33 / `_input` 249 / `build-save` OK（504,222 B）/ `verify-client-pool` 10 项契约全过。
- `_flow` 整场到结局：`draw ERR = 0`、`结局文字已渲染 = true`、`灵魂跑出框外最大 0.0px`。
- 探针：`探针_probe_rounds（该一次性探针已在“lua 目录瘦身”轮清理，数值结论保留）`（落定→开火间隔 + 甩击方向还原）、`探针_probe_cols（该一次性探针已在“lua 目录瘦身”轮清理，数值结论保留）`（骨列/骨毯定位）。

**注**：离线探针的 `M.update` 每步推进的是 1/60 秒的**计数**、而世界内部按 1/30 推进（与试玩页一致），
所以探针里读到的 0.767 就是真实 1.5s —— 别再拿探针的 t 当秒用（这一轮踩过）。

## lua 目录瘦身（2026-10-06）

`lua/` 曾达到 **62 个 .lua 文件**（43 个是排查期写的一次性 `_probe_*` 探针）。现已精简到 **27 个**：

| 类别 | 数量 | 说明 |
| --- | --- | --- |
| 正式文件 | 6 | `boot / main / core / attacks / fitdata / probe` |
| 回归套件 | 13 | `core_selftest` + `_check / _flow / _geometry / _input / _pool / _rounds / _tap / _title / _sine / _box / _adapter / _dbg`（**全部保留**） |
| 长期探针 | 8 | 见下表（有验收价值/被注释引用的） |

长期保留的 8 个探针：

| 探针 | 用途 |
| --- | --- |
| `_probe_final_rightfall.lua` | 终盘长框段「蓝心持续右坠」确定性验收（11 断言） |
| `_probe_floorwidth.lua` | 贴地排骨单根宽度 = 道宽 - FLOOR_BONE_INSET |
| `_probe_bake.lua` | 全流程龙骨炮烘焙普查（rot 池峰值依据） |
| `_probe_pool2.lua` | 控件池峰值快测（BUDGET 注释引用） |
| `_probe_spawnburst.lua` | 骨刺爆发限流效果（单帧新增骨头数） |
| `_probe_groundjump.lua` | J1 地面连跳 |
| `_probe_platjump.lua` | J2/J3 空中板子连跳与落地复位 |
| `_probe_jumpcheck.lua` | J4 平台带走 / J6 四向重力起跳 |

被清理的都是只服务单次排查的（`_probe_hold*` / `_probe_floor*` / `_probe_wall*` / `_probe_r2*` / `_probe_map*` 等）。
根目录的 `Sans_Fight_*.md` 是需求文档，里面提到这些探针的地方**保留原文**（历史证据，不改写）。
