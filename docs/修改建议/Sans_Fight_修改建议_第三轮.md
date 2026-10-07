# 《千星奇域 Sans 战》第三轮修改建议 · 含原版图片索引与本次改动

- **复核对象**：`D:\stars\docs\修改建议\Sans_Fight_改动总结与难点.md`、`D:\stars\workspace\sans-fight\lua\core.lua` / `attacks.lua` / `main.lua`
- **复核方法**：静态阅读 + 4 个可复现探针（见附录 A）
- **本次附带动作**：把原版仓库 `D:\c2-sans-fight-src` 的 **106 张 PNG** 复制进工程 `reference/sprites/`，并生成 `manifest.json` + `INDEX.md`（见 §3）
- **生成日期**：2026-10-06

---

## 0. 结论速览

第二轮 G1~G13 的**核心几条已实测修好**（终盘时长、SansSlam、难度接入、双灵魂），但复核后发现 **1 个 P0 + 3 个 P1** 仍然会让"完整通关"出问题：

| 编号 | 级别 | 问题 | 一句话证据 |
|---|---|---|---|
| **N1** | **P0** | 不选 FIGHT 就永远打不完：终盘门控仍挂在 `fightCount` 上 | 只选 ACT / 只选 MERCY 的探针走到 **round 39**、`fightCount=0`、`result=nil`；只选 ITEM 在 round 20 卡菜单 |
| **N2** | P1 | `simulateLength()` 每个回合开局重复干跑，切换回合卡顿 | 实测 `final` 单次 **1.153s CPU**、`spiral3` 1.122s；无缓存 |
| **N3** | P1 | ACT「挑衅」在脚本回合**完全没有效果** | `self.spd` 只被 3 个内置生成器读取，而它们被 `scriptOwnsRound` 全关 |
| **N4** | P1 | 道具用尽后卡在菜单死循环 | ITEM-only 探针在 round 20 之后 `state=menu`、`itemCount=0`，无限循环 |

P2：N5 HP/面包数值仍未统一、N6 KR 仍固定 0.5s/点、N7 平台反弹仍绕过 ramp、N8 ROUND 0 内置地面骨与 `sans_intro` 叠加、N9 探针 `_probe_dur.lua` 的 SansSlam 段测错层、N10 `spiral1/2/3` 死脚本。

---

## 1. 已验证修好的部分（附本次复测数据）

| 项 | 改动总结的说法 | 本次实测 | 结论 |
|---|---|---|---|
| G1 终盘时长 | 8.02s → 53.03s | `startEnemy(23)` 实测 **53.05s**、脚本 `simulateLength=53.02s` | ✅ 修好 |
| G2 循环脚本时长 | bonestab3 5.27→26.55、spiral1 0.09→10.58 | r22 = **26.58s**、r19 = **8.87s**、r15 = **9.20s**、r8 = **9.40s** | ✅ 修好 |
| G3 难度接入脚本 | tune 传进 World，原作档 1.00 | `DIFFS.original = speed/interval/warn 1.00`；`World:spd/itv/wn` 已存在 | ✅ 机制已接（缺"四档必须不同"的断言） |
| G4 SansSlam 冲量 | 红/蓝/贴墙三模式统一积分，dx=±136 / dy=122 | Game 层实测：蓝 dir0 dx=**+64**、dir2 dx=**-64**、dir1 dy=**71**；红 dir0 dx=**+64**、dir2 dx=**-64** | ✅ 修好（数值与文档的 ±136 有出入，见 N9） |
| G5 双灵魂 | `Game.soul` 唯一权威，`World.heart` 降级为寄存器 | `World:update` 里的灵魂物理段已删除，改为注释 | ✅ 修好 |
| G9 蓝/橙「移动」判据 | 按住方向键 或 被 SansSlam 推 | `moved` 已改为 `push` + 输入判定 | ✅ 修好 |
| G10 框外守卫 | 先钳回框内，守卫收紧到 ±0.25px | 代码已按此实现 | ✅ 修好 |

> 注意：G4 的探针 `_probe_dur.lua` 里那段 SansSlam 测试**走的是 World 层**，而 World.heart 现在是"脚本寄存器"，所以在那里读到的位移仍然是 0——这是**探针测错层**，不是游戏 bug（见 N9）。

---

## 2. 仍需修改的问题与建议（N 系列）

### N1（P0）不选 FIGHT 就永远打不完：终盘门控仍挂在 `fightCount` 上

- **现象**：玩家若一直使用 ACT / ITEM / MERCY（不点「攻击」），`round`（攻击序列）会一路涨过 23，但 `fightCount` 始终为 0，`self.final` 永远为 false → 游戏不会结算；`scriptForRound(n>=23)` 恒返回 `final`，于是不断重播终盘。
- **实测**（`lua/_probe_r2.lua`，用 `g:endEnemy()` 直接推进状态机）：
  - 只选 ACT（行动→检查）：`guard=120`，**最高回合 = 39**，`fightCount=0`，`result=nil`，`interlude=false`
  - 只选 MERCY（仁慈→饶恕）：同样 **最高回合 = 39**，`result=nil`
  - 只选 ITEM（道具→面包）：最高回合 = 20，之后**卡在菜单**（面包 ×20 用尽）
- **根因**：
  - `endEnemy` 里 `self.final = (fightCount >= LAST_ROUND)`、`if fightCount == interludeAfter`（`core.lua:1495-1498`）
  - `scriptForRound` 用 `round`（`core.lua:1231`），且 `n >= LAST_ROUND` 恒返回 `final`
  - 两个计数器各管一半逻辑 → 非 FIGHT 打法下 `round` 与 `fightCount` 永久脱节
- **建议**：**门控统一到 `round`（攻击序列号）**：
  1. 中场：`round == INTERLUDE_ROUND`（13）
  2. 终盘：`round >= LAST_ROUND`（23）即进入终盘菜单，不再 `startEnemy`
  3. `fightCount` 若只用于统计/成就，改名 `fightStat` 并明确不参与门控
  4. `_rounds.lua` 增加三条断言：只用 ACT / 只用 ITEM / 只用 MERCY 的策略都能在 ≤ 40 回合内到达 `result`（ITEM 需要先修 N4）
- **优先级**：P0（直接导致"不打人就通不了关"）

### N2（P1）`simulateLength()` 重复干跑，回合切换卡顿

- **现象**：`startEnemy` 每次开局都调一次 `World:simulateLength()`（`core.lua:946`、`1453`），它 `newWorld` + 最多 120s/DT = 7200 次 `probe:update`。实测：
  | 脚本 | 判定时长 | 单次 CPU |
  |---|---|---|
  | `final` | 53.02s | **1.153s** |
  | `spiral3` | 30.65s | **1.122s** |
  | `sans_bonestab3` | 26.55s | 0.068s |
  | `sans_bonegap1` | 7.02s | 0.147s |
  | `multi1` | 8.80s | 0.168s |
  我在跑"三种策略"探针时，因为反复开局被拖到 **150s+ 仍未跑完**——真机上这会是每回合一次 1 秒级卡顿。
- **建议**（任选其一，推荐 1+2）：
  1. **按脚本名 memoize**：`local DUR_CACHE = {}`，`DUR_CACHE[name] or simulateLength()`；
  2. **预烘焙**：在 `attacks.lua` 每条脚本加 `dur = <实测秒>`，运行时直接读，干跑只作为开发期校验；
  3. 或在 `tools/build-save.mjs` 构建时算一次写进存档。
- **验收**：第二次取同一脚本时长 < 1ms；整场 24 回合开局总 CPU < 100ms。
- **优先级**：P1（性能/体验）

### N3（P1）ACT「挑衅」在脚本回合无任何效果

- **现象**：`ACT_OPTIONS.taunt` 会 `self.taunt += 1`，`self.spd = 1 + 0.10 * taunt`；但 `self.spd` 只在 `spawnBlue` / `spawnWhiteSlide` / `spawnFloorBoneBlue` 三处使用，而这三处都是**内置生成器**，被 `scriptOwnsRound` 关掉（0..22 回合全都有脚本）。
- **代码位置**：`core.lua:1392`（self.spd）、`1630`（taunt+1）、`1831/1844/1897`（唯三处使用）、`2178`（scriptOwnsRound 守卫）
- **建议**：把 taunt 倍率接进 `World`（如构造时 `tune.tauntMul = 1 + 0.1*taunt`，或给 `World` 加一个 `world.tauntMul`），让 `World:spd()` 一并乘上；或把 taunt 改成**可感知的即时效果**（例如下一回合预警更短、骨头更多、伤害/Karma 更高）。
- **验收**：挑衅后下一回合的首骨 `vx`（或 warn 时长）必须与未挑衅不同。
- **优先级**：P1（菜单选项是假的）

### N4（P1）道具用尽后卡在菜单

- **现象**：背包空时 `menuChoose(2)` 只 `log('item_empty')` + `say('（背包是空的）')`，然后 `return`——**状态仍是 menu**，玩家如果不改选其它项就永远出不去；ITEM-only 探针因此在 round 20 卡死。
- **建议**：空背包时把「道具」按钮画成灰/不可选，或在 `subOpen('item')` 前拦截并自动把光标移到「攻击」；同时给菜单加"无有效选项"的看门狗。
- **优先级**：P1（可卡死）

### N5（P2）`MAX_HP=20` 与「传奇面包 +45」仍未统一

- **现象**：`core.lua:99` `MAX_HP = 20`，`core.lua:1262` 面包 `heal = 45, count = 20` —— 一口必满，20 个面包无意义；而《改动总结》§一.5 写的是"传奇面包 ×20，每口 +45 HP"，§三又写"G7 已统一口径"。
- **建议**：定案并同步文档——(a) 原作体验：`MAX_HP=92` + 面包 +45；(b) 保留 20 血短局：面包改 +8 左右、数量 3~4，并重设 KR。
- **优先级**：P2

### N6（P2）KR 仍固定 0.5s/点

- **现象**：`KR_TICK=0.5`、`updateKR` 每 0.5s 扣 1 KR + 1 HP，与 KR 数量无关（第二轮的 G6；改动总结 §二.A.2 自述为"合理近似"）。
- **建议**：若仍要近似，至少写成连续曲线 `tick = f(KR)` 并加断言"KR=40 的 DPS > KR=6"；若接受近似，请在文档里显式标注"非原作逐帧"。
- **优先级**：P2

### N7（P2）平台 `reverse` 反弹仍绕过 `ramp`

- **现象**：`World:update` 的 `local sp = p.speed; if p.ramp then sp = sp * min(1, t/ramp)` 只用于直线段；一旦 `p.reverse` 触发掉头，速度被重算为 `p.speed`（全速），且 `p.vx/p.vy` 未同步更新（`core.lua:1031` vs `1037-1043`）。
- **建议**：反弹后用当前 `sp` 重算 `vx/vy`，并同步写回 `p.vx/p.vy`；`travel`（往返半径）从脚本/配置给，而不是硬编码 `PLATFORM_TRAVEL=100`。
- **优先级**：P2

### N8（P2）ROUND 0 内置地面骨与 `sans_intro` 叠加

- **现象**：`startEnemy` 的 `if d.pattern == 'surprise'` 分支会 `self:spawnFloor(d.p.peek)`，**不受 `scriptOwnsRound` 保护**；而 ROUND 0 同时挂着 `sans_intro` 脚本 → 内置地面骨波与原版"骨刺→正弦骨→四段龙骨炮"同时在场。
- **建议**：把 `spawnFloor` 也纳入 `scriptOwnsRound` 判断，或在注释/GDD 里明确这是"意外攻击"的设计。
- **优先级**：P2

### N9（P2）探针卫生：`_probe_dur.lua` 的 SansSlam 段测错层

- **现象**：该段用 `core.newWorld` + `w:update` 直接读 `w.heart` 位移，但 G5 之后 `World.heart` 只是脚本寄存器，真正的移动在 `Game.soul.push`。于是探针打印 dx=0.00，容易被误读成"Slam 又坏了"。
- **建议**：把该段改成 Game 层（同 `_probe_game.lua`），或直接删除；`_probe_r2.lua` 也建议并入统一的 `_probe_*` 说明。
- **优先级**：P2（工程卫生）

### N10（P2）`spiral1/2/3` 死脚本

- **现象**：固定编排里 ROUND 17/18/19 = `sans_bonestab1/2` + `randomblaster2`，`spiral1/2/3` 与 `platformblasterfast` 永不被 `scriptForRound` 返回（第二轮 E 表已列）。改动总结 §二.C.15 已把它标为"保留为终盘分档/调试素材"。
- **建议**：二选一并保持一致——(a) 真正接回 ROUND 17/18/19（若想要"最后几回合螺旋"）；(b) 归档到 `reference/` 或从 `attacks.lua` 移出，避免 `_rounds.lua` 里还在断言一段永不执行的逻辑。
- **优先级**：P2

---

## 3. 本次实际改动：原版仓库图片 → 工作区（索引）

### 3.1 做了什么

| 项 | 内容 |
|---|---|
| 来源 | `D:\c2-sans-fight-src\Animations\`、`\Textures\`、`\Files\icon-*`、`\Files\loading-logo.png` |
| 目的地 | `D:\stars\workspace\sans-fight\reference\sprites\`（此目录原先为空） |
| 复制数量 | **106 张 PNG** = animations **78** + textures **22** + icons **6** |
| 新增索引 | `reference\sprites\INDEX.md`（人类可读，11KB/111 行）+ `reference\sprites\manifest.json`（机器可读，106 条） |
| 代码改动 | **无**。图片只放在 `reference/` 参考区，不进游戏运行期；`build-save.mjs` / `verify-client-pool.mjs` / `main.lua` 的 7 图元契约未动，回归不受影响 |

目录结构：

```
reference/sprites/
├── INDEX.md                 # 索引：实体 / 动画 / 帧数 / 尺寸 / 用途 / 代码对应
├── manifest.json            # 106 条：original + workspace 路径 + 实体 + 动画 + 尺寸 + 用途 + 代码
├── animations/              # 78 张，按 <实体>/<动画>/<帧>.png
│   ├── GasterBlaster/{Default,Fire}/...
│   ├── PlayerHeart/{Default,Split}/...
│   ├── PlayerHitbox/Default/000.png        # ★ 4×4 真判定物
│   ├── SansBody/{HandUp,HandDown,HandLeft,HandRight}/...
│   ├── SansHead/{Default,LookLeft,Wink,ClosedEyes,NoEyes,BlueEye,Tired1,Tired2}/...
│   ├── SansLegs/{Standing,Sitting}/...
│   ├── SansSweat/Sweat{1,2,3}/...
│   ├── SansTorso/{Default,Shrug}/...
│   ├── SpeechBubble/{Default,NoEffects}/...
│   ├── Strike/Default/000..005.png
│   ├── Target/Default/000.png
│   ├── TargetChoice/Default/{000,001}.png
│   ├── TouchA|TouchB|TouchDPad|VPad/...
│   ├── UIFight|UIAct|UIItem|UIMercy/{Default,Highlight}/...
│   └── HeartShard|HP|KR|MenuBoneLeft|MenuBoneBottom|MenuItem/...
├── textures/                # 22 张，原样保留文件名
│   ├── BoneH.png / BoneV.png / BoneStabH.png / BoneStabV.png / BoneStabWarn.png
│   ├── CombatZone.png / CombatZoneBorder.png / CombatZoneClipper.png / CombatZoneUnclipper.png
│   ├── GasterBlast1.png / GasterBlast2.png / GasterBlast3.png / GasterBlastHit.png
│   ├── HPBackground.png / HPBar.png / KRBar.png
│   ├── Platform1.png / Platform2.png
│   └── BattleFont.png / DamageFont.png / DefaultFont.png / SansFont.png
└── icons/                   # 6 张
    ├── icon-16/32/114/128/256.png
    └── loading-logo.png
```

### 3.2 关键索引（摘要，完整版见 `reference/sprites/INDEX.md`）

| 原版素材 | 尺寸 | 对应游戏实体 | 当前实现位置 | 差值/可改进点 |
|---|---|---|---|---|
| `Animations/PlayerHeart/Default/000.png` | 16×16 | 灵魂（红心） | `main.lua` 灵魂绘制 / `core.lua Game.soul` | 当前用 circle/rect 拼；贴图 16×16 是原值 |
| `Animations/PlayerHitbox/Default/000.png` | **4×4** | **灵魂真实判定盒** | `core.lua SOUL_R = 2` | **正好对应**：原版判定物就是这张 4×4 |
| `Textures/BoneV.png` / `BoneH.png` | 10×24 / 24×10 | 竖骨 / 横骨 | `core.lua BONE_W=10` / `main.lua drawBone()` | 厚度已对齐 10px；端点骨球形状仍是拼装 |
| `Animations/GasterBlaster/Default/000.png` | 57×44 | 龙骨炮炮身 | `main.lua drawBlaster()`（≈59×44） | 包围盒目标值 57×44，现状接近 |
| `Textures/GasterBlast1/2/3.png` | 16×16 | 光束三层 | `core.BLASTER_W = {20,36,56}` / `main.lua` 光束 | 宽度表是自定，可对照贴图再核 |
| `Textures/GasterBlastHit.png` | 16×16 | 光束命中体 | `core.lua` 线段最短距离判定 | 判定带宽与贴图的对应关系可复核 |
| `Animations/SansHead/*.png` | 32×30 | Sans 头/8 种表情 | `main.lua drawSans()` | 头部真值 32×30；表情齐全 |
| `Animations/SansBody/*.png` | 64×70 / 96×48 | Sans 全身姿势 | `main.lua drawSans()` | HandUp/Down 与 Left/Right 两套尺寸 |
| `Animations/SansLegs/*.png` | 44×23 / 52×17 | 站姿 / 坐姿 | `main.lua drawSans()` | — |
| `Animations/SansTorso/*.png` | 54×25 / 72×24 | 躯干 Default/Shrug | `main.lua drawSans()` | — |
| `Animations/SansSweat/Sweat1-3.png` | 32×9 | 汗滴 3 档 | `core.lua SansSweat` | — |
| `Animations/SpeechBubble/*.png` | 237×104 | 对话框 | `core.lua SansText` | 当前用平台 textbox |
| `Animations/Target/Default/000.png` | **548×117** | FIGHT 攻击条底板 | `core.lua` attack 态 | 真值 548×117，可校正攻击条尺寸 |
| `Animations/TargetChoice/*.png` | 14×128 | 攻击条游标 | `core.lua TargetChoice` | — |
| `Animations/Strike/*.png` | 4×6 ~ 14×32（6 帧） | 命中刀光 | `core.lua` 攻击命中演出 | 6 帧序列 |
| `Animations/UI{Fight,Act,Item,Mercy}/*.png` | 110×42 | 四个菜单按钮 | `main.lua` 菜单按钮 | 按钮真值 110×42（当前 MENU.bh=36） |
| `Animations/TouchA/B`, `TouchDPad`, `VPad` | 48×48 / 32×32 | 触摸/摇杆 UI | `main.lua` 触摸层 | — |
| `Textures/HPBackground/HPBar/KRBar.png` | 16×16 | HUD 血条 | `core.lua HUD` | 另有 `Animations/HP`、`Animations/KR` 23×10 小条 |
| `Textures/CombatZone*.png` | 16×16 / 4×4 | 战斗框与裁剪层 | `core.lua CombatZone` / `clipVZone` | — |
| `Textures/Platform1/2.png` | 16×7 | 平台（逻辑/视觉） | `core.lua Platform` | — |
| `Textures/BattleFont/DamageFont/DefaultFont/SansFont.png` | 96×24 / 528×192 / 160×96 / 256×96 | 位图字体 | 平台 textbox（不接入） | 仅作字形参考；无字体打包能力 |
| `Files/icon-*.png`, `loading-logo.png` | 16~256 | 应用图标/加载页 | 平台侧资源 | 不进游戏逻辑 |

### 3.3 版权与产品口径（重要）

`docs/gdd.md` §7 明确写着"**不使用任何 Undertale 素材、字体、音乐与原文台词**，美术用千星自带图元与自绘几何体"。因此本次把原版图片放在 **`reference/`（参考区）**，用途限定为：

1. 尺寸/形状校对（例如 `BoneV=10×24`、`GasterBlaster=57×44`、`Target=548×117`、`PlayerHitbox=4×4`）；
2. 将来若决定改用贴图时的素材来源与映射依据。

**若要真的把它们接进游戏**（而非参考），必须先改产品/法务口径，并按 §4 的方案 B 注册客户端模板。

---

## 4. 若要"真的用上这些图片"——三种接入方案

| 方案 | 做法 | 风险 | 建议 |
|---|---|---|---|
| **A（推荐，默认）** | 保持现有 7 图元程序化绘制；用 `reference/sprites` + `INDEX.md` 做**尺寸/形状校对** | 无 | 立即可用；本次已完成 |
| **B（高保真）** | 把 PNG 注册为客户端模板（新 `guid` + `imageId`），`main.lua` 用 `SetImage` 替换 `drawBone/drawBlaster/drawSans` 的拼装 | 需同步 `TEMPLATES`/`EXPECT`/`G`；真机素材需正式打包；**版权口径要改** | 若目标是"像素级还原"再上 |
| **C（折中）** | 只替换高辨识度件：灵魂、Sans 头/身体、龙骨炮、骨头；其余保留图元 | 中 | 观感提升明显、改动可控 |

方案 B 的实施步骤（未执行，仅方案）：
1. `tools/build-save.mjs` 的 `TEMPLATES` 增加每条要用的贴图模板（`guid` 不冲突、`imageId` 指向正式素材、锚点按用途选 corner/center）；
2. `tools/verify-client-pool.mjs` 的 `EXPECT` 同步增加，保持"模板数 == 契约条数"；
3. `lua/main.lua` 的 `G` 表登记新 guid，`draw*` 函数改用 `take('<kind>')` + `SetImage`；
4. 逐条跑 `_geometry.lua`（绘制==判定对账）与 `verify-client-pool.mjs`；
5. 更新 `docs/gdd.md` §7 的素材口径与 `docs/prefab-pool.md` 的模板表。

---

## 5. 修复优先级

| 优先级 | 编号 | 动作 |
|---|---|---|
| **P0** | N1 | 终盘/中场门控统一到 `round`；补"非 FIGHT 打法也能通关"断言 |
| **P1** | N2 | `simulateLength` memoize 或预烘焙 `dur` |
| **P1** | N3 | taunt 接进 World（或改成实际效果） |
| **P1** | N4 | 背包空不再死循环 |
| P2 | N5 | HP/面包数值定案（92 或改 heal） |
| P2 | N6 | KR 分档或明确标注近似 |
| P2 | N7 | 平台反弹用 ramp 后的速度 + 同步 p.vx/vy |
| P2 | N8 | ROUND 0 的 spawnFloor 纳入 scriptOwnsRound |
| P2 | N9 | 修正 `_probe_dur.lua` 的 SansSlam 测层 |
| P2 | N10 | spiral1/2/3 接回或归档 |

---

## 附录 A：本次使用的探针

| 探针 | 用途 | 复现命令（在 `D:\stars\workspace\sans-fight` 下） |
|---|---|---|
| `lua/_probe_dur.lua` | 脚本静态时长 vs 实际执行时长 | `node tools/run-lua.mjs lua/_probe_dur.lua` |
| `lua/_probe_game.lua` | 每回合实际时长 + SansSlam 位移 | `node tools/run-lua.mjs lua/_probe_game.lua` |
| `lua/_probe_diff.lua` | 难度影响 / KR 速率 / 脚本可达性 | `node tools/run-lua.mjs lua/_probe_diff.lua` |
| `lua/_probe_r2.lua` | `simulateLength` CPU 开销 + ACT/ITEM/MERCY 策略能否通关 | `node tools/run-lua.mjs lua/_probe_r2.lua` |

## 附录 B：本次图片索引的机器可读字段（manifest.json）

```json
{ "group": "textures", "entity": "BoneV", "anim": "",
  "file": "textures/BoneV.png", "original": "Textures/BoneV.png",
  "w": 10, "h": 24,
  "usage": "竖骨 10×24",
  "code": "core.lua BoneV / main.lua drawBone()（BONE_W=10）" }
```

---

*本报告基于工程内可复现探针；N1~N4 均有直接证据，N5~N10 为代码阅读 + 第二轮结论的复查。*
