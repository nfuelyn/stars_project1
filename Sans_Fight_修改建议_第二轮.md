# 《千星奇域 Sans 战》战斗逻辑缺陷复核与第二轮修改建议

- **复核对象**：`D:\stars\Sans_Fight_修改记录.md`、`D:\stars\workspace\sans-fight\lua\core.lua`、`lua\attacks.lua`、`lua\main.lua`
- **复核方法**：静态阅读 + 可复现探针（`lua/_probe_dur.lua`、`lua/_probe_game.lua`、`lua/_probe_diff.lua`）
- **复现命令**（在 `D:\stars\workspace\sans-fight` 下）：
  ```powershell
  node tools/run-lua.mjs lua/_probe_dur.lua     # 脚本静态时长 vs 实际执行时长
  node tools/run-lua.mjs lua/_probe_game.lua    # 每回合在 Game 里实际持续多久 + SansSlam 位移
  node tools/run-lua.mjs lua/_probe_diff.lua    # 难度对脚本回合的影响 / KR 速率 / 脚本可达性
  ```
  （探针备份在 `D:\stars\_analysis\round2\`）
- **生成日期**：2026-10-05

---

## 0. 结论速览

修改记录里的方向大体正确，但**当前战斗逻辑存在 5 个 P0 级缺陷**，其中两条足以让"移植是否成功"这个结论站不住：

| 编号 | 缺陷 | 严重度 | 一句话证据 |
|---|---|---|---|
| **G1** | **终盘 `final` 只播 8.02s，脚本实际需要 53.02s** | P0 | 探针 A：r23 回合 8.02s 结束，85% 内容（螺旋光束、最终弹幕）从未播放 |
| **G2** | **回合时长用"静态延时求和"推导，循环/条件脚本被截断** | P0 | 探针 A：spiral1 静态 0.09s / 实际 10.58s（低估 118×）；bonestab3 5.27 / 26.55 |
| **G3** | **难度对脚本回合完全无效** | P0 | 探针 C：easy/normal/hard/original 首骨 vx 全 = 180、enemyDur 全 = 9.00 |
| **G4** | **`SansSlam` 在红魂/普通蓝魂下失效** | P0 | 探针 B：蓝魂 dir0/dir2 水平 dx = 0.00；红魂 dir0/dir1 dx = 0.00 |
| **G5** | **双灵魂 + 双坐标系 + 两套蓝魂物理并存** | P0 | `World:update` 用 GRAVITY=600 积分 `w.heart`，`Game:update` 又跑一套匀速蓝魂并覆盖它 |

**P1 级（体验/一致性，建议紧随其后修）**：G6 KR 燃烧被简化、G7 HP/治疗数值自相矛盾、G8 回合双计数器漂移、G9 蓝/橙判定用位移而非移动、G10 `outside` 守卫过渡期无敌、G11 固定编排与随机/螺旋系统并存（3 个脚本永不出现）、G12 三关骨刺被改成同一套模板、G13 `EndAttack` 不结束回合。

---

## 1. P0 缺陷详述

### G1 终盘 `final` 被截断：8.02s / 应 53.02s

- **现象**：最后一回合（内部号 23，脚本 `final`）只播放 8 秒就切回菜单，螺旋光束、最终连打弹幕全部看不到。
- **实测证据**（`_probe_dur.lua` + `_probe_game.lua`）：
  - `final` 脚本从第 1 行执行到 `EndAttack` 需要 **53.02 秒**。
  - 但在 Game 里 `startEnemy(23)` 的回合只持续 **8.02 秒**（`enemyDur` 兜底 = `SCRIPT_ROUND.dur = 8`）。
  - 原因链：`final` 含变量延时（`$Wait1`/`$Wait2`）→ `World:scriptLength()` 返回 `nil` → `startEnemy` 的 `if need and ...` 不成立 → `enemyDur` 停在默认 8s。
- **代码位置**：`core.lua:924`（`World:scriptLength`）、`core.lua:1442`（`need = self.world:scriptLength()`）、`core.lua:2422`（`if self.enemyT >= self.enemyDur then self:endEnemy()`）、`core.lua:1483`（`final` 门控）。
- **影响**：终盘是整场的高潮，现在只演了前 ~15%（骨刺连打 + 骨墙段），后面 45 秒全部丢失。这直接违背"按原作固定编排"的目标。
- **建议**：
  1. **编译期干跑求真实时长**：新增 `World:simulateLength(seed)`，用固定 seed、把 `GetHeartPos` 固定为框中心，纯逻辑跑 VM（不渲染/不碰撞）直到 `ended` 或步数上限，得到真实秒数；死循环则报错。
  2. **`EndAttack` 直接结束回合**：`CMD.EndAttack` 置 `w.ended` 后，让 `Game:update` 立即进入 `endEnemy()`（留 0.15~0.3s 淡出尾巴），把 `enemyDur` 降级为"安全上限"。
  3. **`attacks.lua` 每条脚本显式登记 `dur`**（人工核准值），不再从脚本推导。

### G2 回合时长推导错误：循环/条件脚本被截断或空等

- **现象**：多个回合的时长 = 8.02s，但脚本真实时长从 8.9s 到 26.6s 不等；`multi3` 反而空等 14s。
- **实测证据**（`_probe_dur.lua`）：

| 脚本 | 行数 | 静态时长(s) | 实际执行(s) | 比值 | Game 内实际回合(s) | 结果 |
|---|---|---|---|---|---|---|
| `final` | 213 | nil | **53.02** | — | **8.02** | 严重截断 |
| `sans_bonestab3` | 27 | 5.27 | **26.55** | 5.04 | **8.02** | 严重截断 |
| `randomblaster2` | 30 | 1.07 | 8.85 | 8.30 | 8.02 | 截断 |
| `randomblaster1` | 30 | 4.60 | 9.18 | 2.00 | 8.02 | 截断 |
| `platformblaster` | 18 | 1.80 | 9.38 | 5.21 | 8.02 | 截断 |
| `platforms3` | 22 | 1.50 | 8.65 | 5.77 | 8.02 | 截断 |
| `spiral1` | 30 | 0.09 | 10.58 | **117.6** | 未使用 | 参考 |
| `spiral2` | 30 | 0.07 | 8.83 | **117.8** | 未使用 | 参考 |
| `multi3` | 168 | 21.93 | 7.98 | 0.36 | 21.93 | 空等 14s |
| `multi2` | 78 | 13.60 | 10.50 | 0.77 | 13.60 | 空等 3s |

- **根因**：`World:scriptLength()` 只是把**每一行的延时各加一次**——循环体（`JMPABS/JMPREL/JMP*`）会被重复执行 N 次却只统计 1 次；被条件跳过的行也被统计；反过来 `multi3` 里大量 `JMPABS` 跳过了大段行，静态和远大于实际。
- **代码位置**：`core.lua:924-932`、`core.lua:1442-1447`。
- **建议**：同 G1 的"干跑求时长"；并在 `_rounds.lua` / `core_selftest.lua` 里为每个脚本断言 `实际时长 - 回合时长 ∈ [-0.3s, +0.5s]`。

### G3 难度对脚本回合完全无效

- **现象**：四档难度（简单/普通/困难/原作）在脚本回合里的弹速、间隔、预警**完全一样**，只有无敌帧不同。
- **实测证据**（`_probe_diff.lua`）：

| 难度 | tune.speed | tune.interval | enemyDur | 首骨 vx |
|---|---|---|---|---|
| easy | 0.60 | 1.60 | 9.00 | **180.0** |
| normal | 0.78 | 1.35 | 9.00 | **180.0** |
| hard | 1.00 | 1.00 | 9.00 | **180.0** |
| original | 1.25 | 1.00 | 9.00 | **180.0** |

- **根因**：`tune.speed/interval/warn` 只被 `Game:sp`、`Game:it`、`self.spd` 使用，而这些只作用于 `Game:spawnFloor/spawnWall/spawnBlue/spawnWhiteSlide/spawnBlaster` 这套**内置生成器**；但每个回合（0..22）都被攻击脚本接管，`scriptOwnsRound == true` 会把内置生成器整个关掉。`World` 从未拿到 `tune`，CSV 的 `BoneV speed=180` 原样执行。
- **加重问题**：`original` 档 `speed=1.25`，即所谓"原作难度"比脚本原值还快 25%，名不副实。
- **代码位置**：`core.lua:179-185`（DIFFS）、`core.lua:1237-1238`（Game:sp/it）、`core.lua:2161`（`scriptOwnsRound` 守卫）、`core.lua:1319-1325`（`makeWorld` 没传 tune）。
- **建议**：
  1. 把 `tune` 传进 `newWorld({ tune = self.tune })`，在 `World` 内统一缩放：每行 `delay × tune.interval`、骨头/平台/龙骨炮 `speed × tune.speed`、`warn × tune.warn`（或在 `World:update` 用 `dt_eff = dt × tune.speed`，但注意这也会改跳跃/无敌帧，需分开）。
  2. 把"原作"档改为真正的原值：`speed=1.0 / interval=1.0 / warn=1.0 / invuln=0.033`，其余档在此基础上加减。

### G4 `SansSlam` 在红魂/普通蓝魂下失效

- **现象**：脚本调用 `SansSlam,0/2`（水平甩出）时灵魂纹丝不动；`sans_final` 里"把心砸来砸去"的段落实际没有推力。
- **实测证据**（`_probe_game.lua`，60 帧位移）：

| 模式 | dir | maxFall | wall | dx | dy |
|---|---|---|---|---|---|
| 蓝魂 | 0（右） | 240 | 否 | **0.00** | 79.33 |
| 蓝魂 | 2（左） | 240 | 否 | **0.00** | 79.33 |
| 蓝魂 | 1（下） | 240 | 否 | 0.00 | 75.33 |
| 红魂 | 0（右） | 240 | 否 | **0.00** | 82.50 |
| 红魂 | 2（左） | 240 | 否 | **0.00** | 82.50 |
| 红魂 | 1（下） | 240 | 否 | 0.00 | 75.00 |
| 蓝魂 | 0（右） | 240 | **是** | 32.09 | 82.35 |

- **根因**：`CMD.SansSlam` 写的是 `w.heart.vx/vy`；`Game:update` 把它经 `heartVelDirty` 抄进 `soul.vx/vy`。但实际移动模型里：红魂只读方向键（不积分 vx/vy）；蓝魂只积分 `vy` 且每帧被跳跃模型**重新赋值**，`vx` 从不积分；只有 `soul.wall`（箭头模块）才真正积分 `vx/vy`。所以除箭头关外，Slam 等于没写。
- **代码位置**：`core.lua:582-590`（CMD.SansSlam）、`core.lua:1983-2012`（蓝魂跳跃每帧覆盖 vy）、`core.lua:1935-1942`（红/蓝只读方向键）、`core.lua:1965` 前后（wall 分支才积分 vx/vy）。
- **建议**：给灵魂加一个**独立冲量** `soul.push = {vx, vy, t}`，在红/蓝/墙三种模式下都统一 `x += push.vx*dt; y += push.vy*dt` 并按 `decay` 衰减；`SansSlam` 只写 `push`，不写会被覆盖的 `soul.vx/vy`。蓝魂里冲量与跳跃模型**相加**而不是互相覆盖。

### G5 双灵魂 + 双坐标系 + 两套蓝魂物理并存（架构性根因）

- **现象**：`self.soul`（Game，框内相对坐标）与 `w.heart`（World，脚本绝对坐标）各存一份灵魂，用 `heartPosDirty/heartVelDirty/heartModeDirty` 三个脏标记手工同步；`self.box` 与 `w.zone` 又各存一份战斗框，用 `BOX_OFF_X/Y = 240/226` 手工换算。
- **实测旁证**：`_probe_dur.lua` 直接跑 `World:update` 时 `SansSlam` 在蓝魂水平方向 **能** 产生 ±71.5px 位移；但 `_probe_game.lua` 走真实 Game 路径时是 **0** —— 说明 `World` 里那套物理在真游戏里被覆盖成了死代码。
- **根因**：`World:update` 仍在用 `GRAVITY=600` 积分 `w.heart` 并改 `w.heart.vx/vy`；`Game:update` 跑另一套"匀速上升/下落"蓝魂模型，每帧末又把 `w.heart.x/y = self.soul.x/y + BOX_OFF` 覆盖回去。两套物理 + 两份状态，注释里也能看到多轮"修了这里坏了那里"。
- **代码位置**：`core.lua:1002-1055`（World 的蓝魂物理）、`core.lua:1960-2035`（Game 的蓝魂物理）、`core.lua:2090-2126`（脏标记同步）、`core.lua:2283`（判定时再 +BOX_OFF）。
- **建议（二选一，推荐后者）**：
  - A. 让 `World` 成为唯一物理/判定层，`Game` 只做输入与流程；
  - B. **让 `Game.soul` 成为唯一权威**，删掉 `w.heart` 的位置/速度物理；`GetHeartPos / HeartTeleport / HeartMode / SansSlam` 直接读写 `Game.soul`；脚本实体生成时统一换算到同一坐标系，只在**一个**函数里做 `BOX_OFF` 转换。
  - 顺带删掉已无用的 `HEART_HIT`、`BONE_HIT_W` 常量（均只出现 2 次 = 定义 + 导出）。

---

## 2. P1 缺陷详述

### G6 KR 燃烧被简化，失去原作核心张力

- **现象**：无论身上挂多少 KR，都按固定 `KR_TICK = 0.5s` 每 0.5 秒扣 1 KR + 1 HP（= 2 HP/s）。
- **实测**（`_probe_diff.lua`）：KR 6 → 3.02s 烧完、掉 6 血；KR 20 → 10.02s、掉 19 血；KR 40 → 20.02s、掉 19 血。**速率完全相同**。
- **原作/BTS 语义**：KR 越多烧得越快（BTS 的分档是 `>40:0.033s / >30:0.066s / >20:0.166s / >10:0.5s / 其余 1s`），所以"受伤后必须尽快吃到/清 KR"的压力才成立。
- **代码位置**：`core.lua:98`（KR_TICK）、`core.lua:1730-1746`（updateKR）。
- **建议**：恢复分档（或改成连续函数 `tick = f(KR)`），每 tick 扣 1 KR + 1 HP；配一条回归断言"KR=40 的 DPS > KR=6 的 DPS"。

### G7 HP 与治疗数值自相矛盾（代码 vs 记录）

- **现象**：`MAX_HP = 20`（`core.lua:100`，注释说与 `prototype/game.js` 一致），但唯一道具"传奇面包"`heal = 45`（`core.lua:1260`）——**一口必满血**，20 个面包毫无意义。而《修改记录》§3 写的是"HP 92；传奇面包 ×20（+45 HP/个）"。
- **影响**：要么记录是错的，要么代码是错的；当前状态下回复数值失去意义，"清 KR 的战术价值"也被满血掩盖。
- **建议**：二选一并同步文档——
  - 目标原作体验：`MAX_HP = 92`，面包 +45（吃两口满血），保留清 KR；
  - 保留 20 血短局：面包改 +8 左右、数量降到 3~4，并重新平衡 KR（20 血 + KR 上限 40 非常容易暴死）。

### G8 `round` 与 `fightCount` 双计数器漂移

- **现象**：`round`（攻击序列号）每次行动 +1；`fightCount` 只在选"攻击"时 +1。但**中场 / 终盘门控用的是 `fightCount`**（`core.lua:1483`、`1486`），攻击序列用的是 `round`（`scriptForRound`）。玩家用 ACT/ITEM 就会让两个计数器错位：中场触发时机随打法漂移；`scriptForRound(24..)` 恒等于 `final`（`core.lua:1225-1230`），于是一个"只用行动/道具"的玩家可以在 `final` 脚本上无限循环而永远不进入终盘结算。
- **实测**：`_probe_diff.lua` 输出 `24:final 25:final ... 30:final`。
- **代码位置**：`core.lua:1652-1655`（menuChoose 的 `fightCount+1`）、`core.lua:1483/1486`（endEnemy 门控）、`core.lua:1225-1230`（scriptForRound）、`core.lua:1684-1691`（afterPlayerTurn）。
- **建议**：只保留一个决策计数器（推荐 `round`）：中场 = `round == 13`、终盘 = `round >= 23`；`fightCount` 若只是统计/显示就改名并明确不参与门控。同时明确"非 FIGHT 回合是否推进 `round`"（原作是 ACT/ITEM 也推进、Sans 每回合都攻击）。

### G9 蓝/橙骨判定用"位移 > 1px/帧"而不是"是否在移动"

- **现象**：`moved = sqrt(dx*dx+dy*dy) > 1.0`（`core.lua:2080`）。顶着墙/顶着框沿按方向键时位移≈0 → 被判定为"没动"，于是蓝骨不伤人、橙骨反而伤人；被移动平台带走的位移则会被算成"玩家在动"。
- **原作语义**：BTS 用 `PlayerHeart.CustomMovement.Is moving`（速度 ≠ 0），与原作"蓝色=别动 / 橙色=保持移动"一致。
- **建议**：改为"本帧有移动输入 或 速度非零"；平台带走是否算移动需按原作裁定（原作算）。至少不要让"顶墙"被当成静止。

### G10 `outside` 守卫会在变框过渡帧给玩家无敌

- **现象**：`core.lua:2286` 起，只要灵魂相对 `self.box` 超出 1px，就**整段跳过所有伤害**。而 `self.box` 是在 `w:update` 之后才从新 `zone` 刷新的；`CombatZoneResize` 变形期间灵魂可能短暂落在新框外 → 这几帧对所有弹幕免疫，同时**掩盖真正的坐标 bug**（代码注释自己也承认）。
- **建议**：出框时不要整段免疫；应把灵魂硬钳回框内（或按"上一合法框"判定），仅在真正坐标错误时记日志。变框期间让灵魂位置跟随框插值。

### G11 固定编排表与随机/螺旋系统并存，3 个脚本永不出现

- **现象**：`scriptForRound` 已改用 `FIXED_SEQ`，但 `drawTemplate`、`TEMPLATE_TIERS`、`TEMPLATE_SETS`、`scriptUses`、`lastScript`、抽签用 `rng`、`SPIRAL_DEFS`、`SPIRAL_FROM`、`SPIRAL_SCRIPTS` 仍在（大多为死代码）。`_probe_diff.lua` 实测**未被任何回合使用**的脚本：`platformblasterfast`、`spiral1`、`spiral2`、`spiral3`。
- **矛盾点**：《修改记录》§2.6 与 `_rounds.lua` 的部分断言仍在讲"最后几回合走螺旋龙骨炮三档"，但正常流程里 ROUND 17/18/19 = `sans_bonestab1/2` + `randomblaster2`，螺旋永远不出现。
- **代码位置**：`core.lua:154-177`（SPIRAL_*）、`core.lua:164-176`（TEMPLATE_*）、`core.lua:1194-1212`（drawTemplate，仅定义未被调用）、`core.lua:1214-1230`（FIXED_SEQ/scriptForRound）。
- **建议**：二选一并保持自测一致——(a) 删除死代码，把 spiral 从 `_rounds.lua` 断言里去掉；(b) 或把 spiral1/2/3 接回 ROUND 17/18/19（若这是想要的"最后几回合高强度螺旋"）。同时决定 `platformblasterfast` 是否回归固定表。

### G12 三关骨刺被改成同一套"箭头模块"

- **现象**：《修改记录》§2.5 明说 `sans_bonestab1/2/3` 是"同一套内容"（仅第 22 回合延时/滞留不同）。三关体验重复；且机制已从原作的 `BoneStab`（侧边预警→弹出→停留→收回，4 方向）换成"贴墙拖拽 + 整边升骨 + 反方向冲刺"。
- **证据**：三脚本真实时长 7.38 / 7.38 / 26.55s（后两者靠延时拉开），但内容模板相同。
- **建议**：恢复原作 BoneStab 的三档差异（warn/stay/方向数/数量/是否叠加），把"箭头模块"保留为其中一关的新机制，而不是三关通用模板。

### G13 `EndAttack` 不结束回合

- **现象**：`CMD.EndAttack` 只置 `w.ended = true`，`Game:update` 把 `self.world` 置 nil，但**回合仍要等 `enemyT >= enemyDur` 才 `endEnemy`**。
- **后果**：脚本早结束 → 玩家空等（`multi3` 空等 ~14s）；脚本晚结束 → 被截断（G1/G2）。
- **建议**：`w.ended` 后立刻开始回合收尾（或置 `roundDone`），`enemyDur` 仅作安全上限；这样"回合时长"与"脚本时长"天然一致。

### G14 平台：`reverse` 反弹绕过 `ramp`，且平台只带 `vx`

- **现象**：`World:update` 里 ramp 算出的 `sp` 只用于直线段；一旦 `p.reverse` 触发掉头，速度被重算为 `p.speed`（全速），加速平台在第一次反弹瞬间"窜"出去（`core.lua:1003` vs `1011-1019`）。另外平台携带只改 `soul.x`（vx），纵向平台不会带 `vy`（`core.lua:2035-2050` 附近）。
- **建议**：反弹后用当前 `sp`/`p.dir` 重算；平台携带同时处理 vx/vy；`travel`（往返半径）从脚本/配置给，而不是硬编码 `PLATFORM_TRAVEL = 100`。

### G15 ROUND 0 的内置地面骨与 `sans_intro` 叠加

- **现象**：`startEnemy` 的 `if d.pattern == 'surprise'` 分支**不受 `scriptOwnsRound` 保护**，会 `spawnFloor(d.p.peek)`；而 ROUND 0 同时又挂了 `sans_intro` 脚本。于是"意外攻击"回合里，内置地面骨波和原版"骨刺→正弦骨→四段龙骨炮"同时在场。
- **代码位置**：`core.lua:1449-1460`（startEnemy 的 surprise 分支）、`core.lua:2161`（scriptOwnsRound 守卫只作用于周期生成器）。
- **建议**：把 `spawnFloor` 也纳入 `scriptOwnsRound` 判断（或明确它是设计并写进 GDD）。注释里"为了与原版一致"只处理了 blaster，漏了地板骨。

---

## 3. 与《修改记录》的对照：哪些"已改"还是表面修改

| 记录里的改动 | 实际状态 | 对应缺陷 |
|---|---|---|
| B-01 回合计数拆成 `round` + `fightCount` | **引入了新的漂移**：门控与序列用不同计数器，终盘可无限循环 | G8 |
| H-04 / V-06 "原作 1 帧" | `DIFFS.original.invuln = 0.033` 正确；但 `Game:hurt` 注释仍写"原作没有无敌帧 → 原作档只有 0.15s"，且其它档 0.55~1.0s 让"难度"≈"无敌时长" | G3/注释 |
| P-02 改"原作固定编排" | 加了 `FIXED_SEQ`，但没清理随机/螺旋系统；spiral1/2/3 与 platformblasterfast 变成永不可达 | G11 |
| M-01 平台加 `Ramp` | 直线段生效，`reverse` 反弹时被绕过 | G14 |
| H-01 心判定盒 4×4 | `SOUL_R=2` 正确；但 `HEART_HIT`/`BONE_HIT_W` 已成死常量 | G5 |
| V-02 新增 `KR_MAX=40` | 只加了上限，**没做分档衰减** | G6 |
| §3 "血量 92" | 与代码 `MAX_HP=20` 直接冲突 | G7 |
| §2.5 骨刺三关统一模板 | 三关重复度高、且机制与原作不同 | G12 |

---

## 4. 建议的修复顺序与验收标准

### 阶段 0：先补回归（在改任何逻辑之前）
- 断言每条脚本的"真实执行时长"：`实际 = EndAttack 时刻`，允许误差 ±0.3s。
- 断言每个回合的实际时长 ≈ 该脚本真实时长（不再空等/截断）。
- 断言四档难度的同一脚本在弹速/间隔上**必须不同**（原作档 = 原值）。
- 断言 `SansSlam` 在红/蓝/墙三种模式下都产生对应方向的位移（>10px）。

### 阶段 1（P0）
1. **G1/G2/G13**：干跑求真实时长 + `EndAttack` 结束回合 + 每脚本显式 `dur`。
2. **G4**：`soul.push` 冲量，红/蓝/墙三模式统一积分。
3. **G3**：`tune` 传入 `World` 并统一缩放；"原作"档改回 1.0。
4. **G5**：确立 `Game.soul` 唯一权威，删除 `World:update` 的 `w.heart` 物理与死常量。

### 阶段 2（P1）
5. **G6** KR 分档衰减；**G7** HP/治疗定案并同步文档。
6. **G8** 单一回合计数器；**G9** 蓝/橙改"移动"判定；**G10** 出框不再免疫。

### 阶段 3（P2）
7. **G11** 清理死代码或接回 spiral；**G12** 骨刺三关差异化；**G14** 平台 ramp/携带；**G15** ROUND 0 叠加。

---

## 附录：探针与实测数据

### 探针文件
- `lua/_probe_dur.lua`：脚本静态时长 vs 实际执行时长（表 A）
- `lua/_probe_game.lua`：Game 内回合实际时长 + SansSlam 位移（表 B）
- `lua/_probe_diff.lua`：难度影响 + KR 速率 + 脚本可达性（表 C/D/F）
- 备份：`D:\stars\_analysis\round2\`

### 表 A：静态 vs 实际（节选）
| 脚本 | 静态(s) | 实际(s) | 比值 |
|---|---|---|---|
| final | nil | 53.02 | — |
| sans_bonestab3 | 5.27 | 26.55 | 5.04 |
| randomblaster2 | 1.07 | 8.85 | 8.30 |
| randomblaster1 | 4.60 | 9.18 | 2.00 |
| platformblaster | 1.80 | 9.38 | 5.21 |
| platforms3 | 1.50 | 8.65 | 5.77 |
| spiral1 | 0.09 | 10.58 | 117.59 |
| spiral2 | 0.07 | 8.83 | 117.78 |
| multi3 | 21.93 | 7.98 | 0.36 |
| multi2 | 13.60 | 10.50 | 0.77 |

### 表 B：Game 内回合时长（`difficulty=original`，HP 拉满，无输入）
| 回合 | 脚本 | 时长(s) |
|---|---|---|
| r0 | sans_intro | 9.35 |
| r1 | sans_bonegap1 | 9.00 |
| r2 | sans_bluebone | 10.00 |
| r3 | sans_bonegap2 | 10.00 |
| r8 | platformblaster | 8.02 |
| r12 | sans_bonegap2 | 8.02 |
| r15 | randomblaster1 | 8.02 |
| r17 | sans_bonestab1 | 8.02 |
| r18 | sans_bonestab2 | 8.02 |
| r19 | randomblaster2 | 8.02 |
| r22 | sans_bonestab3 | 8.02 |
| r23 | final | **8.02**（应 53.02） |

### 表 C：难度对脚本回合无影响
| 难度 | tune.speed | enemyDur | 首骨 vx |
|---|---|---|---|
| easy | 0.60 | 9.00 | 180.0 |
| normal | 0.78 | 9.00 | 180.0 |
| hard | 1.00 | 9.00 | 180.0 |
| original | 1.25 | 9.00 | 180.0 |

### 表 D：KR 速率
| KR | 用时(s) | 掉血 |
|---|---|---|
| 6 | 3.02 | 6 |
| 20 | 10.02 | 19 |
| 40 | 20.02 | 19 |

### 表 E：SansSlam 位移（60 帧）
| 模式 | dir | wall | dx | dy |
|---|---|---|---|---|
| 蓝 | 0 | 否 | **0.00** | 79.33 |
| 蓝 | 2 | 否 | **0.00** | 79.33 |
| 红 | 0 | 否 | **0.00** | 82.50 |
| 红 | 1 | 否 | 0.00 | 75.00 |
| 蓝 | 0 | 是 | 32.09 | 82.35 |

### 表 F：永不可达的脚本
`platformblasterfast`、`spiral1`、`spiral2`、`spiral3`

---

*本复核以工程内可复现探针为准；所有结论均可用上述三条命令重跑。*
