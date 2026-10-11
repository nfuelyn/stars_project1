# 橙骨（Color=2）应用研究 + 工作区可加位置建议（附：现有橙骨已全部剔除）

- **原版来源**：`D:\c2-sans-fight-src`（`Files/sans_*.csv`、`Event sheets/Battle.xml`、`Documentation/Attacks.md`、`Layouts/`）
- **工作区**：`D:\stars\workspace\sans-fight`（`prototype/attacks/*.csv` → `lua/attacks.lua`、`lua/core.lua`）
- **日期**：2026-10-09
- **本轮动作**：先**剔除工作区现有全部橙骨**（见 §4），再给出"可以在哪些地方加"的建议（§5）

---

## 1. 原版研究结论：**原版 Sans 战里一次橙骨都没用**

| 证据 | 结果 |
|---|---|
| 扫描 `Files/sans_*.csv`（26 个脚本）里 BoneV/BoneH/*Repeat 的 **Color 参数** | **Color=2（橙）共 0 行** |
| 同一扫描的蓝骨 | **Color=1 共 10 行**：`sans_bluebone.csv` 6 行（3 左 + 3 右，h=100、speed=300）、`sans_multi1.csv` 2 行（L34/L37，h=100、speed=240）、`sans_multi3.csv` 2 行（L38/L41） |
| `Documentation/Attacks.md` 的 Color 定义 | 「0 for white, 1 for blue, **2 for orange**」——只是**类型说明**，没有关卡内容引用 |
| `Battle.xml` 的 BoneH/BoneV 函数 | 把 `Function.Param(5)` 写进实例变量 Color（L4517-4518 / L4561-4562）→ **颜色完全由脚本给**，脚本没给过 2 |
| `Battle.xml` 的伤害分支 | L8028-8040 Color=0 无条件伤害；L8060-8074 Color=1 且 `Is moving`；L8093-8107 **Color=2 且未移动**（= 橙骨机制**存在**） |
| `Battle.xml` 的着色 | L7813-7846 给 Color=1/2 分别上 Tint（蓝/橙）——**渲染也支持** |
| `Layouts/*.xml` | 场景里只有 1 个 `BoneH` + 1 个 `BoneV` 模板实例，**没有预置橙色实例** |

> **结论**：原版把橙骨做成"**给作者留着的机制**"（判定 + 着色齐全），但 Sans 战的关卡内容里**完全没使用**。
> 所以"给本端口加橙骨"属于**本项目的扩写**，不是"还原原版"——这也意味着**加在哪里、加多少完全由你定**，不存在"原版对照"的约束。

---

## 2. 本端口橙骨的现状（改前）

| 来源 | 位置 | 说明 |
|---|---|---|
| 脚本（我 2026-10-07 加） | `multi3.csv` Attack5 贴地骨带段 | 每段 1 根橙色横骨（x=121 y=266 w=405 dir=1 speed=160 color=2） |
| 脚本（我 2026-10-07 加） | `sans_bonestab3.csv` 骨刺段 | 每轮 1 根橙色横骨（x=241 y=216 w=165 dir=1 speed=180 color=2），共 6 根 |
| 内置兜底生成器（本端口自创） | `core.lua` `blue_bone` 模式 | 「蓝/橙交替」`self:spawnBlue(..., self.colorFlip and 'blue' or 'orange')`（**休眠**：24 回合里每个回合都挂了脚本，`scriptOwnsRound` 会让内置生成器让位） |

---

## 3. 橙骨机制（本端口实现，供配方参考）

- **判据**：`core.lua` 的碰撞分支 `if c == 2 then if not moved then hurt('orange') end`；`moved = keys.left/right/up/down`（`core.lua` L2488）——**按 WASD 方向键才算"移动"，跳跃/确认键（Enter/Z/空格）不算**。
- **渲染**：`main.lua:31 BONE_COLORS = { 白, 蓝 0xFF2F6BFF, 橙 0xFFFF7A18 }`。
- **日志**：命中记 `hit_orange`（便于自测断言）。
- **难度**：速度/间隔/预警会自动乘难度倍率（`World:spd/itv/wn`）→ 下面的数值都按**原作档**给。
- ⚠ **设计前提（重要）**：因为判据是"按键"而不是"真实位移"，玩家**按住任意 WASD 键（哪怕原地不动）就能免疫橙骨**；反过来"站在移动平台上被运走"会被判定为"没动"。若你要的是真正的"必须位移"，需要把判据换成"位移 > 阈值"——但那会**同时改变蓝骨语义**（蓝骨也是 `moved`），牵动 ROUND 3 的蓝骨关，需单独决策。

## 4. 本轮：现有橙骨**已全部剔除**（2026-10-09）

| # | 文件 | 改动 |
|---|---|---|
| 1 | `prototype/attacks/multi3.csv` | 删除 `0,BoneH,121,266,405,1,160,2` 及其说明注释（Attack5/5Other 回到原样） |
| 2 | `prototype/attacks/sans_bonestab3.csv` | 删除 `0,BoneH,241,216,165,1,180,2` 及其注释，并把循环出口 `JMPZ,27,$Loop` **改回 26**（行号复原） |
| 3 | `lua/core.lua` | `blue_bone` 兜底生成器不再蓝/橙交替：`self:spawnBlue(self.rng() < 0.5, 'blue')`；移除 `self.colorFlip` 初始化 |
| 4 | `lua/core_selftest.lua` | `orange-sweep` 组改为"**脚本里 0 处 Color=2**" + `JMPZ,26` 复原；内置生成器断言改为"只出蓝骨（sawOrange = false）"；`orange-bone` 机制测试（手工摆骨）**保留** |
| 5 | `lua/_rounds.lua` | 删掉两条橙骨登记 |

**验收**：`prototype/attacks/*.csv` 扫描 → **橙骨 0 行**（蓝骨 14 行不变）；`core_selftest` 321 PASS / 0 FAIL、`_rounds` 74 PASS / 0 FAIL、`verify-all --quick` **9 / 9 通过**；`sans-fight.save.json` 已重建。
（扫描脚本：`D:\stars\_analysis\scan_orange.cjs`）

---

## 5. 建议在哪里加橙骨（按"当前打法能不能站桩"排序）

> 判据：**这一段玩家现在能不能靠"站着不动"过**。能站桩 = 加橙骨才有意义（否则只是加难度）。

| 优先级 | HUD 回合 | 脚本 / 段 | 为什么能站桩 | 建议橙骨形态（原作档数值） |
|---|---|---|---|---|
| ★★★ | **ROUND 22** | `multi3` Attack5「贴地骨带 + 双平台」 | 贴地骨缝 10px、灵魂判定体只 4px ⇒ **站在缝里不动**是最优解 | 橙色**横骨**扫场：`BoneH,121,266,405,1,160,2`（宽=框 405、从上往下扫、0.78s 划过框底）——**就是本轮删掉的那根**，按此规格重加即可 |
| ★★★ | **ROUND 23** | `sans_bonestab3` 骨刺段（6 轮） | 每轮「砸 + 骨刺」，玩家被甩到边角后**停着等骨刺收回** | 每轮一根橙色**横骨**：`BoneH,241,216,165,1,180,2`（宽=框 165、每轮 1 根，1.47s 飞出屏 < 每轮 1.5s）——同样就是本轮删掉的那根 |
| ★★ | ROUND 21 | `sans_boneslidev` 上下横骨列 | 上下横骨之间的安全带固定 ⇒ 玩家常**停着等骨过去** | 橙色**竖骨**横向推进：`BoneV,32,<band top>,<h>,0,150,2` + 对称一根 dir=2；h 取"安全带高度"避免逼跳 |
| ★★ | ROUND 4 / 13 | `sans_bonegap2` 18px 骨缝通道 | 玩家"跟着缝走"，位移量很小 | 沿通道方向的橙色**横骨**（厚 10px ≤ 缝 18px）：`BoneH,<x0>,<缝上缘+4>,<通道长>,0/2,140,2` |
| ★★ | ROUND 12 | `sans_bonegap2`（与 ROUND 4/13 同脚本） | 同上 | 同上 |
| ★ | ROUND 20 | `randomblaster2` | 站桩躲龙骨炮是常见打法 | 橙色**横骨**扫场（框宽 × dir=1，speed 150~180） |
| ★ | ROUND 16 | `randomblaster1` | 同上 | 同上 |
| ★ | ROUND 24 | `final` 阶段①（4 次「砸 + 骨刺」） | 每次砸完有停顿 | 阶段① 每次骨刺同时挂一根橙色横骨（宽=框、dir=1、speed 180） |
| ⚠ 慎用 | ROUND 5 / 6 / 7 / 10 | `platforms1/2/3/4hard` | **表面**能站桩（站在平台上被运走） | 若这轮本来就是「站平台躲炮」，橙骨会与"按键才算移动"的判据打架（人被平台运着走却算没动）⇒ 要加就**明确把它设计成"必须自己按方向键"** |
| ⛔ 不建议 | ROUND 3 | `sans_bluebone` | 原版设计就是"**别动**"躲蓝骨 | 加橙骨会与蓝骨机制**互相矛盾**（蓝骨要求静止、橙骨要求移动） |
| ⛔ 不建议 | ROUND 24 阶段④ | `final` / `spiral1~3` 旋转光束 | 已经强制绕圈移动 | 再加橙骨只是叠难度，意义低 |

### 5.1 三条通用配方（可直接抄）

```csv
# ① 橙色横骨「从上往下扫」，覆盖整框宽（适合"站桩躲矮骨/骨缝"的段）
0,BoneH,<框左>,<框顶-10>,<框宽>,1,<速度>,2

# ② 橙色竖骨「从一侧横向推进」（适合"上下横骨之间站桩"的段）
0,BoneV,<框外x>,<安全带顶>,<安全带高>,0,<速度>,2
0,BoneV,<框外x>,<安全带顶>,<安全带高>,2,<速度>,2

# ③ 橙色竖骨「排骨」（需要批量时，用本端口已支持的 Color 第 8 参数）
0,BoneVRepeat,<x>,<y>,<h>,0,<speed>,<count>,<spacing>,2
```

- 速度参考：**140~180 px/s**（扫过框高 115~165 用 0.7~1.2s）；
- 宽/高要**覆盖到玩家可能待的所有位置**（横骨取框宽、竖骨取安全带高）；
- 数值按"原作档"写，难度倍率会自动叠加（简单更慢、普通 ×1.053 行程）。

---

## 6. 建议的落地顺序（等你点头）

1. 先按本表 ★★★ 两处重加（就是你刚让我删掉的那两处，规格不变）；
2. 再看 ★★ 三处（boneslidev / bonegap2 ×2），每次加完跑 `core_selftest` + 手测"按住 WASD 能不能过"；
3. 最后决定是否要改"橙骨判据 = 真实位移"（会牵动蓝骨，需要单独评估）。

**回归命令**（每次加完橙骨都要跑）：

```powershell
cd D:\stars\workspace\sans-fight
node tools/gen-attacks.mjs        # 改了 CSV 才跑
node tools/build-save.mjs
node tools/run-lua.mjs lua/core_selftest.lua
node tools/verify-all.mjs --quick
```
