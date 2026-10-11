# ROUND 22 / ROUND 23 添加橙骨 —— 修改文档

- **工作区**：`D:\stars\workspace\sans-fight`
- **日期**：2026-10-09
- **前置状态**：按《`Sans_Fight_橙骨应用研究_与_添加位置建议.md`》先把**现有橙骨全部剔除**（脚本 2 处 + 内置兜底的蓝/橙交替），当前全仓库 **Color=2 共 0 行**；
  本文 = 按研究结论的 ★★★ 两处**重新加回**（规格与原实现一致）的**精确补丁**。
- **回合口径**：HUD `ROUND x / 24`（= 内部号 + 1）；ROUND 22 = 内部 21 = `multi3`；ROUND 23 = 内部 22 = `sans_bonestab3`

---

## 0. 两处总览

| # | HUD | 内部 | 脚本 | 段 | 橙骨 | 数量 |
|---|---|---|---|---|---|---|
| ① | ROUND 22 | 21 | `multi3` | `Attack5` / `Attack5Other`（贴地骨带 + 双平台） | `0,BoneH,121,266,405,1,160,2` | 该段每次播放 1 根 |
| ② | ROUND 23 | 22 | `sans_bonestab3` | 骨刺循环（6 轮，每轮「砸 + 骨刺」） | `0,BoneH,241,216,165,1,180,2` | **每轮 1 根 → 共 6 根** |

---

## 1. ROUND 22：`multi3` 贴地骨带段

### 1.1 插入位置（`prototype/attacks/multi3.csv`）

当前文件实际内容（注释行不参与脚本行号）：

```csv
119: # 底边骨带：贴底边(框底 391) + 顶部到第二块板(y=354) => 单根竖骨 y=354/h=37
120: 0,BoneVRepeat,121,354,37,2,0,20,20      ← 贴地骨带（20 根，间隔 20）
121: 0,RND,Side,2
122: 0,JMPZ,Attack5Other,$Side
123: 0,BoneV,521,280,35,2,240
124: 0,BoneV,1,319,65,0,240
125: 1.2,JMPABS,RndAttack
```

在 **L120 与 L121 之间**插入：

```csv
# 【2026-10-09 用户口径·ROUND22】贴地骨带段配一根橙色扫场横骨：x=121（框左）/ y=266（框顶 276 上方 10px）/
#   宽=405（= 框宽 121..526）/ dir=1 向下 / speed=160 / color=2 橙 —— 不按方向键就会挨打，逼玩家别站在骨缝里不动。
0,BoneH,121,266,405,1,160,2
```

插入后的样子：

```csv
0,BoneVRepeat,121,354,37,2,0,20,20
+（上面 2 行注释）
+0,BoneH,121,266,405,1,160,2
0,RND,Side,2
0,JMPZ,Attack5Other,$Side
```

**为什么放在 `RND,Side,2 / JMPZ,Attack5Other` 之前**：这一段用 `RND` 随机选左右分支，放在它前面 ⇒ **两个分支都会出这根橙骨** ✓。

### 1.2 参数依据

| 参数 | 值 | 依据 |
|---|---|---|
| `x` / `width` | 121 / 405 | 该段框 = `CombatZoneResizeInstant,121,276,526,391`（`multi3.csv` L112）⇒ 121+405 = 526 **正好覆盖整个战斗框** |
| `y` | 266 | 框顶 276 上方 10px（骨厚 = 10px，`BONE_W`）⇒ 下缘正好贴框顶 |
| `dir` | 1 | 向下（`core.lua`：`vy = (dir==1) and +spd`）= 从上往下扫 |
| `speed` | 160 | 0.78s 划过框底（391）、0.84s 完全离开框；段末 1.2s 由 `BlackScreen,1` 清场 ⇒ 一根只走一趟 |
| `color` | 2 | 橙：**灵魂"不移动"时才受伤**（`core.lua` 颜色分支；渲染 `0xFFFF7A18`） |

### 1.3 时序（实测，`World` 直接跑真实脚本）

```
框 = x 121..526（宽 405）  y 276..391（高 115）
橙骨 宽 = 405（= 框宽 ✓）  起始 y=266
进入框顶 t=0.02s → 骨顶划过框底 t=0.78s → 完全出框 t=0.84s → 段末被黑屏清掉 t≈1.22s
```

### 1.4 影响面 / 不破坏跳转

- 该段**每次播放加 1 根**橙骨（`multi3` 是"5 段随机抽 9 选 1"，抽到 `Attack5` 才出现）；
- `multi3` 内部全部是**标签跳转**（`:Attack5` / `JMPZ,Attack5Other` / `JMPABS,RndAttack`）与 `JMPREL,$Jump` 跳表，跳表位置在文件前部、**不受此处插入影响** ✓；
- 不动任何现有延时、不动骨带数量/间距/速度。

---

## 2. ROUND 23：`sans_bonestab3` 骨刺段（每轮一根）

### 2.1 插入位置（`prototype/attacks/sans_bonestab3.csv`）

当前文件实际内容：

```csv
28: 0.26666,SansSlam,$Direction
29: # 【2026-10-06 二次口径】尺寸再减半 dist 18→9、出现 warn 0.4→1.2、升起 out 0.22→1.02
30: 0,BoneStab,$Direction,9,1.2,0.25
31: 1.23333,JMPABS,6
32: 0,EndAttack
```

在 **L30（`BoneStab`）之前**插入：

```csv
# 【2026-10-09 用户口径·ROUND23】每一轮骨刺都配一根橙色横骨：x=241（框左）/ y=216（框顶 226 上方 10px）/
#   宽=165（= 框宽 241..406）/ dir=1 向下 / speed=180 / color=2 橙；1.47s 飞出屏 < 每轮 1.5s ⇒ 每轮只有一根在场。
0,BoneH,241,216,165,1,180,2
```

### 2.2 ⚠ 必须同时改的 1 处跳转（否则循环出口会跳错）

插入 1 行数据后，`EndAttack` 从第 **26** 行变成第 **27** 行，所以：

```diff
-0,JMPZ,26,$Loop
+0,JMPZ,27,$Loop
```

（该脚本用 `JMPZ,26,$Loop` 在 Loop 归零时跳到 `EndAttack`；`JMPREL` 那几处是相对偏移，**不用改** ✓）

### 2.3 参数依据

| 参数 | 值 | 依据 |
|---|---|---|
| `x` / `width` | 241 / 165 | 该段框 = `CombatZoneResize,241,226,406,391` ⇒ 241+165 = 406 **覆盖整个战斗框** |
| `y` | 216 | 框顶 226 上方 10px（骨厚 10） |
| `dir` / `speed` | 1 / 180 | 向下扫；0.97s 骨顶划过框底、1.03s 完全出框、1.47s 飞出屏幕 < **每轮 1.5s**（= `0.26666 SansSlam` + `1.23333 JMPABS`）⇒ 保证"每轮只有一根"、不会越积越多 |
| `color` | 2 | 橙（不动才受伤） |

### 2.4 时序（实测）

```
t=0.32 骨刺#1（dir=2） + 橙骨#1 生成   → 之后每 1.5s 一组
t=1.82 / 3.32 / 4.82 / 6.32 / 7.82  骨刺#2..#6 + 橙骨#2..#6
t=9.05 脚本 EndAttack（共 6 轮）
框 = x 241..406（宽 165）   骨刺 6 根 / 橙骨 6 根   橙骨宽度 = 框宽 ✓
```

---

## 3. 配套同步（自测 / 登记表）

| # | 文件 | 改动 |
|---|---|---|
| 1 | `lua/_rounds.lua` | 加回两条登记：`{ 'sans_bonestab3', 'BoneH,241,216,165,1,180,2', 'ROUND23 骨刺段：每轮 1 根橙色扫场横骨' }`、`{ 'multi3', 'BoneH,121,266,405,1,160,2', 'ROUND22 贴地骨带段：1 根橙色扫场横骨' }` |
| 2 | `lua/core_selftest.lua`（`orange-sweep` 组） | 断言从"脚本里 0 处 Color=2"改成"**恰好这 2 处**（且只出现在 `multi3` / `sans_bonestab3`）"；并断言 `sans_bonestab3` 的 `JMPZ,27,$Loop`（行号随插入同步） |
| 3 | `lua/core_selftest.lua`（内置生成器组） | 保持"只出蓝骨（sawOrange=false）"——**内置兜底不改回橙**（橙骨只由脚本显式下发） |

---

## 4. 重建与验收

```powershell
cd D:\stars\workspace\sans-fight
node tools/gen-attacks.mjs        # 改了 CSV 必须跑
node tools/build-save.mjs
node tools/run-lua.mjs lua/core_selftest.lua
node tools/run-lua.mjs lua/_rounds.lua
node tools/verify-all.mjs --quick
```

| 验收 | 期望 |
|---|---|
| ROUND 22 段 | 起手出现 1 根橙骨：`x 121..526`（宽 405 = 框宽）、`y` 从 266 向下、约 0.78s 划过框底、1.2s 段末被清 |
| ROUND 23 段 | 6 轮骨刺各配 1 根橙骨（共 6 根），宽 165 = 框宽，1.47s 飞出屏 |
| 判定 | 灵魂**按住 WASD 任一方向键**时不掉血；**完全静止**会掉血（记录 `hit_orange`） |
| 全仓库扫描 | Color=2 的骨行**恰好 2 行**（`multi3` 1 + `sans_bonestab3` 1） |
| 回归 | `core_selftest` 321+ PASS / 0 FAIL、`_rounds` 76 PASS / 0 FAIL、`verify-all --quick` 9 / 9 通过 |

（扫描脚本：`D:\stars\_analysis\scan_orange.cjs`；橙骨探针：`D:\stars\_analysis\probe_bonestab3_orange.lua`)

---

## 5. 已知前提（与《橙骨应用研究》一致）

1. **橙骨判据 = 按住 WASD 方向键**（`moved = keys.left/right/up/down`），**跳跃/确认键（Enter/Z/空格）不算** ⇒ 玩家按住任意方向键、原地不动即可免疫；若要"必须真实位移"，需改判据并与蓝骨语义一起评估；
2. 速度/间隔会自动乘难度倍率（`World:spd/itv`）⇒ 上面数值按**原作档**给，其它难度自动缩放；
3. 这两处都**不含蓝骨**，不会出现"蓝骨要静止 / 橙骨要移动"的机制冲突（ROUND 3 `sans_bluebone` 明确**不加**橙骨）；
4. 橙骨只在**这两段的播放期间**存在：段末 `BlackScreen,1`（ROUND 22）或自身飞屏（ROUND 23）即消失，不会跨段累积。

---

## 6. 完整补丁（可直接照抄）

```diff
--- a/prototype/attacks/multi3.csv
+++ b/prototype/attacks/multi3.csv
@@ 贴地骨带之后 @@
 0,BoneVRepeat,121,354,37,2,0,20,20
+# 【2026-10-09 用户口径·ROUND22】贴地骨带段配一根橙色扫场横骨：x=121 / y=266（框顶上方 10px）/
+#   宽=405（整框 121..526）/ dir=1 向下 / speed=160 / color=2；不按方向键就会挨打。
+0,BoneH,121,266,405,1,160,2
 0,RND,Side,2
 0,JMPZ,Attack5Other,$Side
```

```diff
--- a/prototype/attacks/sans_bonestab3.csv
+++ b/prototype/attacks/sans_bonestab3.csv
@@ 第 6 行（循环出口） @@
-0,JMPZ,26,$Loop
+0,JMPZ,27,$Loop
@@ 在 BoneStab 之前插入 @@
 0.26666,SansSlam,$Direction
+# 【2026-10-09 用户口径·ROUND23】每一轮骨刺都配一根橙色横骨：x=241 / y=216 / 宽=165（整框）/
+#   dir=1 向下 / speed=180 / color=2；1.47s 飞出屏 < 每轮 1.5s ⇒ 每轮只有一根在场。
+0,BoneH,241,216,165,1,180,2
 0,BoneStab,$Direction,9,1.2,0.25
 1.23333,JMPABS,6
```
