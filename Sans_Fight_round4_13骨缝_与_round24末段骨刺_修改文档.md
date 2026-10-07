# round4/13 骨缝 + round24 末段骨刺 —— 修改文档

- **工作区**：`D:\stars\workspace\sans-fight`
- **日期**：2026-10-07
- **回合口径**：HUD `ROUND x / 24`（内部号 + 1）

| 你的轮次 | HUD | 内部 | 脚本 | 本文涉及 |
|---|---|---|---|---|
| round4 | 4 | 3 | `sans_bonegap2` | 上下骨缝（高骨/上骨） |
| round13 | 13 | 12 | `sans_bonegap2`（同一脚本，两回合共用） | 同上 |
| round24 | 24 | 23 | `final` | 阶段③末尾「两边同时」骨刺（旋转龙骨炮前） |

映射出处：`lua/core.lua:1344-1353` `FIXED_SEQ`（`[3]='sans_bonegap2'`、`[12]='sans_bonegap2'`、`[22]='sans_bonestab3'`… 终盘 `>= 23` → `final`）。

---

# 一、round4 / round13：高骨（上骨）没有按预期调高

## 1.1 定位

`prototype/attacks/sans_bonegap2.csv`（HUD4 与 HUD13 是同一个脚本，循环 `:Begin` → `JMPABS,Begin` 直到 `Total ≥ 150`，最后 `7,EndAttack`）：

```
33: 0,SUB,HeightT,118,$HeightB     ← 上骨（高骨）高度 = 118 − HeightB
34: 0,SUB,YB,386,$HeightB          ← 下骨上缘 = 386 − HeightB
50: 0,BoneV,$XL,257,$HeightT,0,$SpeedL   ← 上骨：顶 257，高 HeightT
51: 0,BoneV,$XL,$YB,$HeightB,0,$SpeedL   ← 下骨：顶 YB，高 HeightB
52: 0,BoneV,$XR,257,$HeightT,2,$SpeedR
53: 0,BoneV,$XR,$YB,$HeightB,2,$SpeedR
```

战斗框 = `133,251,508,391`（`L5`）→ **缝（上骨下缘 ↔ 下骨上缘）恒为 `129 − K`**：

| K（`SUB,HeightT` 的常量） | 上骨下缘 | 缝宽 | 灵魂视觉 16px 能否通过 |
|---|---|---|---|
| 111（**原版**） | 368 − HeightB | **18px** | ✅ 净空 2px |
| 99（10-05 改过） | 356 − HeightB | 30px | ✅ 净空 14px |
| **118（现在）** | **375 − HeightB** | **11px** | ❌ **11 < 16，画面上心必然与上下骨重叠** |

**"高骨没有按预期调高"就是这个 118**：它把上骨的下缘压到 `375 − HeightB`，缝只剩 11px —— 灵魂命中盒（`SOUL_R=2`，4px）虽然钻得过去、判定上不掉血，但**视觉上 16px 的心比缝还宽，看起来就是"卡在骨缝里/被夹住"**。要"调高"（把上骨下缘往上抬），只能把 K 减小。

## 1.2 round15 的"间隔"是多少（实测）

round15 = `multi1`，其中与 `bonegap2` 同类的是 **Attack2**（`multi1.csv` L65-66、L79-82；注释写「蓝魂通道，上下缝恒 18 高」）：

```
65: 0,SUB,HeightT,86,$HeightB        → 上骨：顶 282，高 86 − HeightB → 下缘 = 368 − HeightB
66: 0,SUB,YB,386,$HeightB            → 下骨：顶 386 − HeightB
79: 0,BoneV,$XL,282,$HeightT,0,$SpeedL
80: 0,BoneV,$XL,$YB,$HeightB,0,$SpeedL
81: 0,BoneV,$XR,282,$HeightT,2,$SpeedR
82: 0,BoneV,$XR,$YB,$HeightB,2,$SpeedR
```

→ 上骨下缘 = `368 − HeightB`，下骨上缘 = `386 − HeightB` ⇒ **缝恒为 18px**（两回合的下骨公式完全一样，都是 `386 − HeightB`；只有上骨不同）。

## 1.3 改法：把 K 从 118 改成 **111**（= 与 round15 逐像素一致）

`prototype/attacks/sans_bonegap2.csv`：

```
-- 现在（L33）
0,SUB,HeightT,118,$HeightB
-- 改为
0,SUB,HeightT,111,$HeightB
```

改完后：上骨下缘 = `257 + 111 − HeightB = 368 − HeightB`、下骨上缘 = `386 − HeightB` ⇒ **缝 = 18px，与 round15 的下缘、缝宽完全相同**（同名同值，两段只在"上骨顶 y=257 vs 282"和框高上有区别）。

| HeightB | 现在 HeightT | 现在上骨下缘 | **改后 HeightT** | **改后上骨下缘** | 缝 |
|---|---|---|---|---|---|
| 20 | 98 | 355 | **91** | **348** | 18 |
| 30 | 88 | 345 | **81** | **338** | 18 |
| 40 | 78 | 335 | **71** | **328** | 18 |
| 60 | 58 | 315 | **51** | **308** | 18 |

- 上骨高度统一 **−7px**、下缘统一 **上移 7px**（这就是"调高高骨"）；
- 下骨（`YB`）、骨速、间距、循环节奏、`7,EndAttack` **全部不动**；
- 只改 1 行（L33）。

## 1.4 代价与取舍（必须知情）

**缝 18px 与"HUD13 满跳也被上骨擦到"在 HeightB=60 那一档不可兼得。**

- 满跳顶点（脚本坐标）：地面心 = 383，满跳上升 66.9px → 顶点心 = 316.1，命中盒上缘 = **314.1**；
- 上骨"擦到满跳顶点"要求上骨下缘 **> 314.1**：
  - HeightB = 20：改后下缘 348 ✅ 仍擦到
  - 30：338 ✅　40：328 ✅
  - **60：308 ❌（高于顶点 6px，不再擦到）**
- 若你必须保住 60 档的"满跳擦伤"，只能在那一档保留旧值（条件分支，3 行）：

```
0,SUB,HeightT,111,$HeightB                 ← 默认：缝 18px
0,JMPNE,KeepApex,$HeightB,60               ← 仅 60 档走旧值（缝 11px）
0,SUB,HeightT,118,$HeightB
0,:KeepApex
```

> 注意：这个选项等于"60 档继续穿模"（缝 11px），是否值得由你定。**默认建议用 111 单一常量**（缝一致、手感一致）。

## 1.5 必须同步改的两处（否则自测/记录会不一致）

| 文件 | 位置 | 现在 | 改为 |
|---|---|---|---|
| `lua/core_selftest.lua` | L1127-1142（`bonegap2-apex` 组） | 断言 `SUB,HeightT,118`、`gap == 11`、`bottom >= 89` | 断言 `SUB,HeightT,111`、`gap == 18`；删除 `bottom >= 89`（满跳擦伤）那一条，换成 `bottom == 368 - HeightB` |
| `lua/_rounds.lua` | L350 | `{ 'sans_bonegap2', 'SUB,HeightT,118,$HeightB', 'HUD13 上骨抬到满跳命中线' }` | `{ 'sans_bonegap2', 'SUB,HeightT,111,$HeightB', 'HUD4/13 上骨抬起 → 缝 18px（=HUD15）' }` |

自测里可用的新断言（替换 L1136-1142）：

```lua
for _, hb in ipairs({ 20, 30, 40, 60 }) do
  local ht = 111 - hb
  local bottom = 257 + ht
  local gap = (386 - hb) - (257 + ht)
  ok(bottom == 368 - hb, string.format('bonegap2：HeightB=%d 上骨下缘 %d = 368-%d（与 HUD15 同）', hb, bottom, hb))
  ok(gap == 18, string.format('bonegap2：HeightB=%d 缝 %dpx（灵魂视觉 16px，净空 %dpx）', hb, gap, gap - 16))
end
```

## 1.6 关于"间隔"的另一种读法（备查，非本次口径）

如果你说的"间隔"不是**骨缝宽度**、而是**横向间距节奏**，那对应的是 L35 `ADD,X,$Total,32`（`X = Total + 32`，每次循环 Total 增 9/11/19/25）与 round15 的 `X = 22*Loop2 + 25 + Total`（`multi1.csv:67-69`）。那种改法需要新增 `Loop2` 变量并重排循环，属于**改动结构**。
本文按"高骨没调高 = 缝太窄"来写（这也是你第一轮就提的"夹缝过小"）。

---

# 二、round24：旋转龙骨炮前的「两边同时」骨刺

## 2.1 定位

`prototype/attacks/final.csv` 阶段③（L123-160）里，**"两条边一起出骨刺"（两边同时）** 共两组：

| 组 | 行 | 命令 | 方向（`core.lua:1006-1017`） | 距旋转光束 |
|---|---|---|---|---|
| 前一组 | L142 / L143 | `BoneStab,2,48,1.4,1` / `BoneStab,3,48,1.4,1` | 2 = 从左框向右刺；3 = 从上框向下刺 | 中间还隔着一组 |
| **后一组（本文主目标）** | **L151 / L152** | `BoneStab,0,48,1.4,1` / `BoneStab,1,48,1.4,1` | **0 = 从右框向左刺；1 = 从下框向上刺** | 后面只剩 L160 的**单发**，紧接着就是 L162+ 的旋转光束 |

`BoneStab` 参数（`core.lua:729-737`）：`BoneStab,方向,厚度(dist),预警(warn),停留(stay[,伸出时长 outDur])`
- 面板厚度 = `dist + 8`；伸出量 = `dist − 3`；预警带（peek）厚度也按 `dist` 走；
- 所以"厚度缩减为 4/5" = **dist × 0.8**（与开场骨刺 `29 → 23.2` 的同一口径）；
- "伸出延时 +0.5s" = **warn + 0.5**。

## 2.2 先看实测（重要）：这两组骨刺**现在根本伸不出来**

探针 `lua/_probe_final3stab.lua`（真实 `final` CSV，跳到 L151 那行执行）：

```
t= 0.02 生成骨刺 dir=0 dist=48 warn=1.4 stay=1
t= 0.02 生成骨刺 dir=1 dist=48 warn=1.4 stay=1
t= 0.92 black=1（骨头 0 根）  ← 两根骨刺在【warn 相位】就被移除
t= 1.03 black=0
t= 1.07 生成骨刺 dir=2 dist=48 warn=0.6 stay=1   ← L160 的单发
t= 1.65 相位 warn → out
t= 1.77 相位 out → stay
t= 2.77 相位 stay → in
t= 2.88 被移除
```

**原因**：`CMD.BlackScreen`（`core.lua:812-819`）在 `black ≠ 0` 时把 `w.bones` 整体清空；而这组骨刺创建后**只隔 0.9s** 就执行 `0.9,BlackScreen,1`（L153）。
→ `warn 1.4s > 0.9s` ⇒ 骨刺永远停在预警相位、**只剩预警带，没有本体**。
（L142/L143 那组同理：warn 1.4，后面同样是 `0.9,BlackScreen,1`。）

## 2.3 你要的两项改动（精确值）

**主目标（L151/L152，旋转光束前那组"两边同时"）**：

| 行 | 现在 | 改为 |
|---|---|---|
| L151 | `0.03333,BoneStab,0,48,1.4,1` | `0.03333,BoneStab,0,38.4,1.9,1` |
| L152 | `0,BoneStab,1,48,1.4,1` | `0,BoneStab,1,38.4,1.9,1` |

**可选（L142/L143，上一组"两边同时"，同样处理）**：

| 行 | 现在 | 改为 |
|---|---|---|
| L142 | `0.03333,BoneStab,2,48,1.4,1` | `0.03333,BoneStab,2,38.4,1.9,1` |
| L143 | `0,BoneStab,3,48,1.4,1` | `0,BoneStab,3,38.4,1.9,1` |

数值换算：`48 × 4/5 = 38.4`；`1.4 + 0.5 = 1.9`。
几何结果：面板厚度 `56 → 46.4px`、伸出量 `45 → 35.4px`、预警带 `45 → 35.4px`。

> L160 的**单发**骨刺（`dir=2, dist=48, warn=0.6`）不属于"两边同时"，本次不动；若要一并改，同样取 `38.4 / 1.1`。

## 2.4 ⚠ 只改这两项的话，骨刺**依旧不会伸出来**（而且更不可能）

`warn 1.9s` 仍然远大于后面那个 `0.9s` 黑屏 → 骨刺还是会在预警相位被清掉。**要让"伸出延时 +0.5s"这件事真的被看见，必须同时推迟黑屏。** 三个选项：

| 选项 | 改动 | 结果 | 段时长变化 |
|---|---|---|---|
| **A（✅ 已选定 2026-10-07）** | 只改 L151/L152（§2.3） | 预警标记/面板变薄（dist 48→38.4）；warn +0.5s 因 0.9s 黑屏**不会产生任何可见时长变化** → **骨刺本体仍然不出现**（与现状一致） | 0 |
| **B1（推荐）** | A + 把 L153 `0.9,BlackScreen,1` → **`2.2,BlackScreen,1`** | 骨刺在 1.9s 伸出、2.0s 到满、**停留 0.2s** 后被黑屏清掉（能看见） | +1.3s |
| **B2**（完整版） | A + 把 L153 改成 **`3.2,BlackScreen,1`** | 骨刺完整走完 预警1.9 + 伸出0.1 + 停留1.0 + 收回0.1 = 3.1s | +2.3s |
| **C**（不动黑屏时序） | 反向操作：warn 必须 < 0.8s（例如 `0.7`）才可能伸出 | 骨刺 0.7s 伸出、0.9s 被清掉（只闪 0.1s），与"延长延时"的要求相反 | 0 |

> **【决定】采用方案 A**（2026-10-07）：只改 L151/L152 的 `dist / warn`，**不动黑屏时序**。B1 / B2 / C 均不采用。
> 我原本推荐 B1（能让骨刺真的出现）；既然选 A，需接受"骨刺本体仍然不会出现、+0.5s 不产生可见时长效果"——最终清单与后果见 §2.7。

## 2.5 影响面

| 项 | 结论 |
|---|---|
| 只动 `final.csv` | **方案 A：只改 L151/L152 两行**（L142/L143 可选、同值）；**L153 黑屏时序不动** |
| 其它阶段 / 其它 26 个脚本 | 零影响 |
| `core.lua` | **不需要改**（`BoneStab` 已支持 `dist/warn/stay/outDur` 参数） |
| 现有自测锁定 | `_rounds.lua:356-357` 只锁**开场**骨刺（`BoneStab,$Direction,23.2,1.0,0`）→ 本改动不冲突；建议**新增**一条断言把 L151/L152 的参数钉住 |
| 难度倍率 | 仍照旧（`warn` 会被 `World:wn()` 乘 `tune.warn`），本次不改倍率、不改全局 |

**建议新增的自测断言**（`core_selftest.lua`，放在 final/终盘相关组里）：

```lua
local csvF
for _, sc in ipairs(A) do if sc.name == 'final' then csvF = sc.csv end end
ok(csvF:find('BoneStab,0,38.4,1.9,1', 1, true) ~= nil, 'final 阶段③：右边界骨刺 厚度 48→38.4、预警 1.4→1.9')
ok(csvF:find('BoneStab,1,38.4,1.9,1', 1, true) ~= nil, 'final 阶段③：下边界骨刺 厚度 48→38.4、预警 1.4→1.9')
-- 方案 A：黑屏时序不动（L153 保持 `0.9,BlackScreen,1`），因此**不加**延时断言
```

## 2.6 验收

```powershell
cd D:\stars\workspace\sans-fight
node tools/gen-attacks.mjs     # 改了 CSV 必须跑
node tools/build-save.mjs
node tools/run-lua.mjs lua/_probe_final3stab.lua   # 方案 A：期望仍是「warn 相位被移除」，只有 dist 变小
node tools/run-lua.mjs lua/_probe_jumpnum.lua      # 复核满跳 66.9px（§1.4 用）
node tools/run-lua.mjs lua/core_selftest.lua       # 期望 PASS（含 §1.5 新断言）
node tools/verify-all.mjs --quick
```

| 断言 | 期望 |
|---|---|
| `bonegap2` 缝（HeightB=20/30/40/60） | 全部 **18px**，上骨下缘 = `368 − HeightB`（= HUD15） |
| `bonegap2` 上骨高度 | `111 − HeightB` → 91 / 81 / 71 / 51 |
| final L151/L152 参数 | `38.4, 1.9, 1`（厚度 ×4/5、预警 +0.5s） |
| final 阶段③ 生命周期（**方案 A**） | 与现状一致：`t≈0.02` 生成 → `t≈0.92` 仍在 `warn` 相位被 `BlackScreen,1` 清掉（看不到本体） |
| 唯一可见差异（方案 A） | `dist 48 → 38.4`：面板 `dist+8` 56 → 46.4px、伸出量/预警带 `dist−3` 45 → 35.4px、朝框内三角尺寸同步变小 |

---

## 2.7 【决定】问题 2 采用方案 A（2026-10-07）

**最终改动清单（只 2 行；不动黑屏、不动 core、不动全局移速）**

| 文件 / 行 | 现在 | 改为 |
|---|---|---|
| `prototype/attacks/final.csv:151` | `0.03333,BoneStab,0,48,1.4,1` | `0.03333,BoneStab,0,38.4,1.9,1` |
| `prototype/attacks/final.csv:152` | `0,BoneStab,1,48,1.4,1` | `0,BoneStab,1,38.4,1.9,1` |

- `48 × 4/5 = 38.4`（厚度 −20%）、`1.4 + 0.5 = 1.9`（伸出延时 +0.5s）；
- **L153 的 `0.9,BlackScreen,1` 保持不动**（这是方案 A 与 B 的唯一区别）；
- 可选项：若上一组（L142/L143，`dir2 左` + `dir3 上`）也要同样处理 → `48 → 38.4`、`1.4 → 1.9`；
- L160 的单发骨刺（`dir=2, 48, 0.6`）**不在本次范围**。

**已知后果（请主程序一并知悉）**

1. 这两根骨刺**依旧只以预警形式出现**（实测：`t≈0.02` 生成 → `t≈0.92` 仍在 `warn` 相位就被 `BlackScreen,1` 清掉），看不到"伸出来"的骨刺本体 —— 与现状一致；
2. `warn 1.4 → 1.9`（+0.5s）在方案 A 下**没有任何可见效果**（0.9s 就被截断）。保留它是为了参数口径统一、以及"以后要放开黑屏时直接生效"；
3. **唯一可见变化 = 厚度**：`dist 48 → 38.4`
   - 面板厚度 `dist + 8`：**56 → 46.4px**
   - 伸出量 / 预警带厚度 `dist − 3`：**45 → 35.4px**
   - 朝框内的三角标记尺寸（`main.lua:1019-1030` 的 `thick = d + 8`）同步变小
4. 如果**以后**想让那 0.5s 真的体现出来，只需把 `final.csv:153` 的 `0.9,BlackScreen,1` 改成 `2.2,BlackScreen,1`（= §2.4 的 B1），其余不用再动。

**验收（方案 A）**

```powershell
cd D:\stars\workspace\sans-fight
node tools/gen-attacks.mjs
node tools/build-save.mjs
node tools/run-lua.mjs lua/_probe_final3stab.lua   # 仍是「warn 相位被移除」，dist 由 48 → 38.4
node tools/run-lua.mjs lua/core_selftest.lua
```

期望探针输出（方案 A）：

```
t= 0.02 生成骨刺 dir=0 dist=38.4 warn=1.9 stay=1
t= 0.02 生成骨刺 dir=1 dist=38.4 warn=1.9 stay=1
t= 0.92 black=1 … 骨刺(dir=0/1) 被移除，移除前相位=warn
```

> 探针 `lua/_probe_final3stab.lua` 已改成按「`dir=0` 且 `warn ≥ 1.4`」定位，改前（48/1.4）与改后（38.4/1.9）都能直接跑。

## 附录：行号索引

| 内容 | 位置 |
|---|---|
| `sans_bonegap2` 骨缝公式 | `prototype/attacks/sans_bonegap2.csv` L33-34、L50-53 |
| round15（multi1）同款骨缝 | `prototype/attacks/multi1.csv` L65-66、L79-82 |
| HUD15 Attack2 注释「上下缝恒 18 高」 | `prototype/attacks/multi1.csv` L4 |
| `bonegap2` 自测锁定 | `lua/core_selftest.lua` L1127-1142 |
| 改动登记表 | `lua/_rounds.lua` L344-352（L350 是 bonegap2 那条） |
| `BoneStab` 实现 | `lua/core.lua` L729-737（创建）、L975-995（相位）、L999-1019（命中矩形） |
| 黑屏清场 | `lua/core.lua` L812-819（`BlackScreen ≠ 0` → 清 `w.bones`） |
| final 阶段③ 骨刺 | `prototype/attacks/final.csv` L142-143、L151-152、L160 |
| 探针 | `lua/_probe_final3stab.lua`（本轮新增）、`lua/_probe_jumpnum.lua` |

*本文的"骨刺伸不出来"结论来自 `lua/_probe_final3stab.lua` 对真实 `final` CSV 的逐帧实测（列出 warn→out→stay 相位与被移除时刻）；骨缝数字来自 CSV 的算术关系（缝 = 129 − K）与 round15 的同款公式对照。*




---

## 实施记录（2026-10-07 已落地）

| 项 | 内容 | 状态 |
|---|---|---|
| round4/13 骨缝 | `prototype/attacks/sans_bonegap2.csv:33`：`SUB,HeightT,118,$HeightB` → **`111`**（缝 11 → **18px**，上骨下缘 375−HeightB → **368−HeightB**） | ✅ 已改 |
| round24 阶段③骨刺（方案 A） | `prototype/attacks/final.csv:151/152`：`48,1.4` → **`38.4,1.9`**；L153 的 `0.9,BlackScreen,1` **未动** | ✅ 已改 |
| 生成物 | `lua/attacks.lua`（`node tools/gen-attacks.mjs`）、`sans-fight.save.json`（`node tools/build-save.mjs`，513,902 字节） | ✅ 已重建 |
| 自测同步 | `lua/core_selftest.lua`：`bonegap2-apex` 组 → **`bonegap2-gap18`**（断言 `111`、`gap==18`、`bottom==368-HeightB`）；新增 **`final-stab3`** 组（3 条断言，含"黑屏仍为 0.9s"） | ✅ |
| 登记表 | `lua/_rounds.lua:350`（118→111）＋ 新增 L352/L353 两条 final 骨刺 | ✅ |
| 验收 | `core_selftest` **291 PASS / 0 FAIL**；`_rounds` **73 PASS / 0 FAIL**；`verify-all --quick` **8 / 8 通过** | ✅ |
| 实测探针 | `lua/_probe_bonegap2_gap.lua`（真实运行：缝 **恒 18px**，如 `上骨 257+81=338 / 下骨 356`）；`lua/_probe_final3stab.lua`（`dist=38.4 warn=1.9`，仍在 `warn` 相位被黑屏清掉 —— 方案 A 预期） | ✅ |

**未做（按你的口径）**：不动 `HeightB=60` 档的满跳擦伤（未加条件分支）；不动黑屏时序（未采用 B1/B2）；不动全局难度倍率、不移速、不动任何延时值。
