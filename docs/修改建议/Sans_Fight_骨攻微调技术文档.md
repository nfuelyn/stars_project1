# 《Sans 战》骨攻微调技术文档
## —— 2/11/12/14 轮上骨厚度、22 轮骨带密度、24 轮开场骨刺

- **工作区**：`D:\stars\workspace\sans-fight`
- **数据源**：`prototype/attacks/*.csv`（唯一源）→ `tools/gen-attacks.mjs` → `lua/attacks.lua`
- **参考**：`D:\c2-sans-fight-src`（原版 CSV / `Battle.xml`）、`D:\stars\reference\lua\bone_battle.lua`
- **日期**：2026-10-07

---

## 0. 回合口径对照（先对齐编号）

本工程 HUD 显示 `ROUND (内部号 + 1) / 24`（`core.lua`：`'ROUND '..(g.round+1)`）。本文一律用 **HUD 号**：

| HUD | 内部 | 脚本 | 本文涉及 |
|---|---|---|---|
| 2 | 1 | `sans_bonegap1` | ✅ 上骨厚度 |
| 11 | 10 | `sans_bonegap1fast` | ✅ 上骨厚度 |
| 12 | 11 | `sans_boneslideh` | ✅ 上骨厚度 |
| **14** | 13 | **`sans_spare`（无骨头）** | ⚠️ 见 §3 |
| 13 | 12 | `sans_bonegap2` | ⚠️ 第 4 个"顶点漏伤"脚本 |
| 22 | 21 | `multi3`（开场第一抽 = Attack5） | ✅ 底边骨带密度 |
| 24 | 23 | `final` | ✅ 开场骨刺 |

> ⚠️ **HUD 14 = `sans_spare`（只有 `HeartTeleport + 0.3s EndAttack`，一根骨头都没有）**，与"上方移动骨头"描述不符。当前唯一符合"上排骨 + 满跳漏伤"的第 4 个脚本是 **`sans_bonegap2`（HUD 13 / 内部 12）**，§3 给出它的数字与候选清单。

---

## 1. 原理：蓝心"满跳顶点"与上骨下缘的几何关系

### 1.1 当前跳跃模型（已是原版冲量式）

`Game:jump`（`core.lua`）在贴地/土狼时间内给一个沿**逆重力方向**的瞬时冲量：

```
soul.v -= g * HEART_JUMP_STRENGTH        -- HEART_JUMP_STRENGTH = 180 px/s
```

之后蓝魂物理按原版 **4 档重力曲线**减速（`blue_soul.lua` 口径）：

| 沿重力方向速度 `va` | 重力 |
|---|---|
| (15, 240) | 540 |
| (−30, 15] | 180 |
| (−120, −30] | 450 |
| ≤ −120 | 180 |

由 180 初速积分可得**满跳上升高度 ≈ 67.5px**（与框高无关，只与 180 + 重力曲线有关）。

### 1.2 判定用的"顶点上缘"

- 灵魂静止站立时：`ground_y = box_bottom − SOUL_CLAMP(8)`
- 满跳顶点：`apex_y = ground_y − 67.5`
- **顶点上缘（命中用）**：`apex_top = apex_y − SOUL_R(2)`
- 上骨（竖骨）下缘：`bone_bottom = bone.y + bone.h`（脚本坐标；换算到框内相对坐标 = `bone.y − 226 + h`）

**命中条件**：`bone_bottom ≥ apex_top`（再留 ~1px 容差）。

### 1.3 实测顶点（`lua/_probe_apex.lua`）

```
sans_bonegap1   box.h=140  地面 y=157.0  顶点 y=90.1  跳高=66.9  顶点上缘=88.1（框内相对坐标）
```

- 上骨当前：脚本 `y=257` → 框内 `y=31`，高 32 → 下缘 `63`；
- 顶点上缘 `88.1` → **63 < 88.1，差 25.1px = 满跳打不到**（正是你说的问题）；
- 要让"正好打到"：`H ≥ 88.1 − 31 = 57.1` → **H = 58**（1px 容差；理论积分值 87.5→56.5，取 58 更稳）。

---

## 2. 改动 1：2 / 11 / 12 轮「上排移动骨」厚度 32 → 58

三关共用同一套几何（框都是 `133,251,508,391`，h=140；上骨都在 `y=257`）：

| HUD | 脚本 | 文件:行 | 现在 | 改为 |
|---|---|---|---|---|
| 2 | `sans_bonegap1` | `sans_bonegap1.csv:17` | `0.3,BoneVRepeat,128,257,32,0,180,8,120,1` | `0.3,BoneVRepeat,128,257,58,0,180,8,120,1` |
| 2 | `sans_bonegap1` | `sans_bonegap1.csv:18` | `0,BoneVRepeat,503,257,32,2,180,8,120,1` | `0,BoneVRepeat,503,257,58,2,180,8,120,1` |
| 11 | `sans_bonegap1fast` | `sans_bonegap1fast.csv:15` | `0.3,BoneVRepeat,128,257,32,0,210,8,133,1` | `0.3,BoneVRepeat,128,257,58,0,210,8,133,1` |
| 11 | `sans_bonegap1fast` | `sans_bonegap1fast.csv:16` | `0,BoneVRepeat,503,257,32,2,210,8,133,1` | `0,BoneVRepeat,503,257,58,2,210,8,133,1` |
| 12 | `sans_boneslideh` | `sans_boneslideh.csv:11` | `0.5,BoneVRepeat,513,257,32,2,120,8,76` | `0.5,BoneVRepeat,513,257,58,2,120,8,76` |

**说明**
- 这是"**厚度**"（垂直于上边方向的高度），不是"沿边的长度"；`Count/Spacing` 不动。
- 效果：贴着满跳顶点下缘 → **满跳必被蹭到 → 玩家必须改成短按跳**（保留可变跳高度的手感差异）。
- 备注：文件里保留的原版旧值注释 `…,257,95,…` 是原版数据，**不要**恢复成 95；95 会在起跳早期就撞上，惩罚过重。目标是"正好卡在顶点"。

---

## 3. 改动 2：第 4 关（你说的"14 轮"）——口径确认

### 3.1 HUD 14 = `sans_spare`（无骨头）

`sans_spare.csv` 全文只有 `CombatZoneResize / HeartTeleport / HeartMode / TLPause / 0.3,EndAttack`，**没有任何骨头**，所以"14 轮上方移动骨头"不可能指 HUD 14。

### 3.2 第 4 个"满跳漏伤"的脚本 = `sans_bonegap2`（HUD 13 / 内部 12）

`bonegap2` 的上骨用变量高度：

```
0,SUB,HeightT,99,$HeightB      -- HeightT = 99 - HeightB
0,BoneV,$XL,257,$HeightT,0,$SpeedL
0,BoneV,$XR,257,$HeightT,2,$SpeedR
```

`HeightB ∈ {20,30,40,60}` → `HeightT ∈ {79,69,59,39}`，下缘 = `31 + HeightT`：

| HeightB | HeightT | 下缘(框内) | 顶点上缘 88.1 | 结果 |
|---|---|---|---|---|
| 20 | 79 | 110 | 88.1 | ✅ 打到（偏早） |
| 30 | 69 | 100 | 88.1 | ✅ |
| 40 | 59 | 90 | 88.1 | ✅ 差 1.9px |
| **60** | **39** | **70** | 88.1 | ❌ **漏 18px** |

**建议**：把常量 `99` 提高到 `118`，使最薄档也正好卡在顶点：`HeightT = 118 − HeightB → {98,88,78,58}`，其中 `HeightB=60` 时 `HeightT=58` → 下缘 89 ≥ 88.1 ✅。
改动：`sans_bonegap2.csv` 的 `0,SUB,HeightT,99,$HeightB` → `0,SUB,HeightT,118,$HeightB`。
（副作用：另三档也变高 ~19px，若只想改最薄档，可加一个 `JMPNE` 分支单独处理 `$HeightB=60`。）

### 3.3 其它候选（已核对，**不需要**改）

| 脚本 | 上骨 | 下缘 | 结论 |
|---|---|---|---|
| `platforms4`（HUD 8） | `BoneVRepeat,283,267,40,3,...` | 267+40 = 307（脚本） | 已远低于顶点，**已能打到** |
| `platforms4hard`（HUD 10） | `283/443,268,40,3,...` | 308 | 同上 |
| `multi1`（HUD 15） | `BoneV,$XL,282,$HeightT`（HeightT=86−HeightB） | ≥ 348 | 同上 |

> 请确认你说的"14"是不是指 HUD 13 的 `bonegap2`；若你看到的是别的回合，把屏幕上的 `ROUND x / 24` 数字告诉我，我按同一公式补算。

---

## 4. 改动 3：22 轮底边骨带「密度」翻倍（HUD 22 = `multi3` 开场 Attack5）

当前（上一轮已把"厚度"调到贴底边 + 顶到第二块板）：

```
0,BoneVRepeat,121,354,37,2,0,10,40      -- 10 根、间距 40 → 横向 121..481（覆盖 360px）
```

你说"厚度够了、密度不够、数量翻倍" → **数量 10 → 20**。若保持同一横向覆盖（121..481 ≈ 360px），间距必须同步减半：

```
0,BoneVRepeat,121,354,37,2,0,20,20      -- 20 根、间距 20 → 横向 121..501（覆盖 380px），密度 ×2
```

- 文件：`prototype/attacks/multi3.csv:121`
- **只改数量与间距，厚度 `37` 与顶边 `354` 不动**（底边仍 391）。
- 若你确实想"数量 ×2 而间距不变（40）"：行会伸到 `x=881`，但竖骨会被 `CombatZoneClipped` 裁到框内，框内只多出 ~1 根，**达不到加密效果**——不建议。
- `multi2`（HUD 17）也有一模一样的 Attack5 段落（当前 `121,364,30,2,0,25,16`），本轮**未改**；要不要一起改请示下。

---

## 5. 改动 4：24 轮（`final`）开场拖拽攻击的骨刺

### 5.1 现状

`final.csv` 开场阶段①是 4 次循环（`SET I,0` + `JMPL 7,$I,4`），每次：

```
0.26666,SansSlam,$Direction
0.2,BoneStab,$Direction,29,0.4,0        ← 第 42 行（脚本坐标；29=伸出厚度，0.4=伸出前预警/延时，0=停留）
```

### 5.2 你要求

1. **骨刺伸出厚度变为 4/5**：`Distance 29 → 29 × 4/5 = 23.2`（取 `23.2`；若必须整数则 `23`）
2. **增加 0.6s 延时后伸出**：把"伸出前延时" `WarnTime 0.4 → 1.0`

**改为**：

```
0.2,BoneStab,$Direction,23.2,1.0,0
```

- 文件：`prototype/attacks/final.csv:42`
- 说明：`BoneStab` 的"伸出前延时"就是 **WarnTime**（第 4 个参数）——期间显示预警带、到点才滑出骨面板；`+0.6s` = `0.4 → 1.0`。
- 另一种等价写法（若你想连"甩击→骨刺"的调用时刻也推迟）：把行首延时 `0.2 → 0.8`，WarnTime 保持 `0.4`。**二选一即可，推荐前者**（只改 BoneStab 自身，不影响 SansSlam 节奏）。
- 阶段③的几处 `BoneStab,0/1/2/3,48,0.6~1.4,1` **不属于"开场几次拖拽攻击"**，本文不动。

---

## 6. 精确改动清单（可直接落地）

| # | 文件 | 行 | 现在 | 改为 | 说明 |
|---|---|---|---|---|---|
| 1 | `prototype/attacks/sans_bonegap1.csv` | 17 | `0.3,BoneVRepeat,128,257,32,0,180,8,120,1` | `…,128,257,58,0,180,8,120,1` | HUD2 上骨 32→58 |
| 2 | 同上 | 18 | `0,BoneVRepeat,503,257,32,2,180,8,120,1` | `…,503,257,58,2,180,8,120,1` | 同上 |
| 3 | `prototype/attacks/sans_bonegap1fast.csv` | 15 | `0.3,BoneVRepeat,128,257,32,0,210,8,133,1` | `…,128,257,58,0,210,8,133,1` | HUD11 |
| 4 | 同上 | 16 | `0,BoneVRepeat,503,257,32,2,210,8,133,1` | `…,503,257,58,2,210,8,133,1` | 同上 |
| 5 | `prototype/attacks/sans_boneslideh.csv` | 11 | `0.5,BoneVRepeat,513,257,32,2,120,8,76` | `…,513,257,58,2,120,8,76` | HUD12 |
| 6 | `prototype/attacks/sans_bonegap2.csv` | `SUB,HeightT` 行 | `0,SUB,HeightT,99,$HeightB` | `0,SUB,HeightT,118,$HeightB` | HUD13（第 4 关，待你确认） |
| 7 | `prototype/attacks/multi3.csv` | 121 | `0,BoneVRepeat,121,354,37,2,0,10,40` | `0,BoneVRepeat,121,354,37,2,0,20,20` | HUD22 密度 ×2 |
| 8 | `prototype/attacks/final.csv` | 42 | `0.2,BoneStab,$Direction,29,0.4,0` | `0.2,BoneStab,$Direction,23.2,1.0,0` | HUD24 开场骨刺 |

> 改完 **必须** 跑 `node tools/gen-attacks.mjs` 重新生成 `lua/attacks.lua`，再 `node tools/build-save.mjs`。
> ⚠️ 教训：`attacks.lua` 与 CSV 曾不一致（CSV 是旧的），直接用旧 CSV 生成会覆盖新值——**改前先确认 CSV 是最新**（或以 `attacks.lua` 为准反向同步）。

---

## 7. 验证

```powershell
cd D:\stars\workspace\sans-fight
node tools/gen-attacks.mjs
node tools/build-save.mjs
node tools/run-lua.mjs lua/_probe_apex.lua        # 复测顶点上缘（应仍 ≈88.1）
node tools/run-lua.mjs lua/_probe_real22.lua      # 真实 multi3：应看到 20 根 / y=354 h=37
node tools/run-lua.mjs lua/core_selftest.lua      # 期望 PASS 281 / FAIL 0
node tools/verify-all.mjs --quick
```

| 断言 | 期望 |
|---|---|
| A1 上骨命中 | 在 bonegap1/1fast/slidesh 里"满跳（一直按住）"必须被上骨打到；"短按"（约 0.1s）不被打到 |
| A2 高度值 | 上骨下缘（框内）= 31+58 = 89 ≥ 顶点上缘 88.1 |
| A3 bonegap2 | `HeightB=60` 时 `HeightT=58`，下缘 89 → 命中 |
| A4 multi3 密度 | 真实脚本里出现 20 根、间距 20、y=354/h=37、横向 121..501 |
| A5 final 骨刺 | 第 42 行 `23.2,1.0,0`；预警 1.0s 后才滑出；伸出厚度 23.2（面板 31.2） |

**复现探针**：`lua/_probe_apex.lua`（顶点）、`lua/_probe_real22.lua`（真实 22 轮）、`lua/_probe_bottomrow.lua`（骨带几何示意）。

---

## 8. 风险与备注

| 项 | 说明 |
|---|---|
| "正好"的边界 | H=58 只有 ~1px 余量，帧率/浮点差异下可能偶尔擦不到；若想稳一点可给 **59~60**，但会略微提前惩罚满跳 |
| 短按跳仍安全 | 目标就是"满跳=打、短跳=不打"；若改得过高（如恢复原版 95）会让**起跳早期**就撞上，手感全变 |
| bonegap2 的 `99→118` | 会让 `HeightB=20/30/40` 三档也变高，需确认是否接受；否则加条件分支只改 60 档 |
| multi3 密度 | 20 根会同时进场（speed 0 静止），峰值图元数上升；注意 `main.lua` 的 `BUDGET`（circle/rect 预算）是否够 |
| 24 轮延时归因 | 若你的"0.6s 延时"指的是调用时刻（行首 `0.2→0.8`），用 §5.2 的等价写法 |
| 攻击延时政策 | 本文的 0.6s 是**你本次明确要求**的；其它已有延时（SpinTime/Loop/周期）不动 |

---

*本文所有几何值均由 `lua/_probe_apex.lua`（顶点）与公式 `apex_top = box_bottom − SOUL_CLAMP − 67.5 − SOUL_R` 交叉验证；上骨下落差 1px 级别，改完请用 A1 断言实测一次。*
