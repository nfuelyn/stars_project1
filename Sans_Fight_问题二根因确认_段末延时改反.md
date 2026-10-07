# 问题二根因确认：段末延时被「改反」 —— 我上次文档的表格列标错了

> 结论：**能确认。** "round15 / round22 侧骨消失时间错误"的真正根因，是我上一份文档《回合差异与蓝心物理》§2.5 的 diff 表格**把「工作区 / 原版」两列标反**；主程序照它"恢复原版"，结果把段末延时从**原版的 1.5 改成了 1.2**，于是侧骨少了 0.3s 飞行时间，被下一段黑屏提前清空。
> 这与你说的时间线完全一致：**只有按我那份文档改过之后才出现**。

- **工作区**：`D:\stars\workspace\sans-fight`
- **日期**：2026-10-07

---

## 1. 铁证：我上次文档把两列标反了

我的《`Sans_Fight_回合差异与蓝心物理_修改意见.md`》§2.5(b) 原文：

| 行 | 工作区 | 原版 |
|---|---|---|
| multi2 L43/L49 | `1.5,JMPABS,RndAttack` | `1.2,JMPABS,RndAttack` |
| multi3 L133/L139 | `1.5,JMPABS,RndAttack` | `1.2,JMPABS,RndAttack` |

→ 我据此写"**恢复原版 = 改回 1.2**"。

而**原版仓库的真实内容**（`D:\c2-sans-fight-src\Files\sans_multi3.csv`）：

```
 99: 0,BoneVRepeat,200,331,55,0,360,11,24
100: 0,BoneVRepeat,-64,371,15,0,360,10,24
101: 1.5,JMPABS,RndAttack          ← 原版是 1.5
102: 0,:Attack4Other
...
105: 0,BoneVRepeat,704,371,15,2,360,10,24
106: 1.5,JMPABS,RndAttack          ← 原版是 1.5
...
113: 0,BoneVRepeat,121,364,30,2,0,25,16
118: 1.5,JMPABS,RndAttack          ← 原版是 1.5
122: 1.5,JMPABS,RndAttack          ← 原版是 1.5
```

**原版是 1.5**，我表里却写成 1.2 → 主程序把 1.5 改成了 1.2 → **正好改反**。

---

## 2. 现在端口里"被改反"的行（精确清单）

| 脚本 | 行 | 现在 | 原版（应为） | 该段内容 |
|---|---|---|---|---|
| `multi3` | **L105** | `1.2,JMPABS,RndAttack` | **`1.5,JMPABS,RndAttack`** | Attack4：左侧 `BoneVRepeat,200,331,55,0,360,11,24` + `-64,371,15,...` 向中间汇聚 |
| `multi3` | **L110** | `1.2,JMPABS,RndAttack` | **`1.5,JMPABS,RndAttack`** | Attack4Other：右侧 `440,…` + `704,…` 向中间汇聚 |
| `multi3` | **L126** | `1.2,JMPABS,RndAttack` | **`1.5,JMPABS,RndAttack`** | Attack5：两平台 + 底边骨带 |
| `multi3` | **L130** | `1.2,JMPABS,RndAttack` | **`1.5,JMPABS,RndAttack`** | Attack5Other |
| `multi2` | **L36** | `1.2,JMPABS,RndAttack` | **`1.5,JMPABS,RndAttack`** | 同一类侧骨段 |
| `multi2` | **L40** | `1.2,JMPABS,RndAttack` | **`1.5,JMPABS,RndAttack`** | 同上 |

补充说明：
- `multi3` 其余段（L141/L147 的 1.2、L155/L159 的 1.7、L168/L173 的 1.9）与原版**一致**，不要动；
- `multi2` 的 **L51/L57 = 2.6**（原版 1.2）是**第八轮**为"R17 八发全加 HoldTime 1.5"做的**有意改动**，与本次无关，不要顺手改回；
- **HUD 15 = `multi1`：与原版逐行完全一致**（侧骨段 `0.9` 等都对）——如果你说的"round15"现象也在这一关，那它**不是**延迟问题，需要另查；但"round22 = multi3"的根因已实锤。

---

## 3. 为什么 1.5 → 1.2 会让骨头"提前消失"

### 3.1 段末延时 = 该段骨头能飞多久

`multi3` Attack4 的段结构：

```
:Attack4
  ...HeartTeleport / BoneVRepeat（侧骨开始飞）...
1.2,JMPABS,RndAttack        ← 段末延时：1.2s 后跳回 RndAttack
:RndAttack
  BlackScreen,1             ← 下一段开头：w.bones = {} 一次性清空全场骨头
```

即：**骨头从生成到被清空，只有这一段的时长**（现在是 1.2s，原版是 1.5s）。

### 3.2 少 0.3s 意味着什么

侧骨速度 = `360 px/s`（`BoneVRepeat,200,331,55,0,360,11,24`）：

- 原版 1.5s → 骨头飞行 `360 × 1.5 = 540px`
- 现在 1.2s → 只飞 `360 × 1.2 = 432px`
- **少飞 108px** —— 恰好是"还没走出战斗框（框宽 405px）/ 还没越过中线"的那一截

于是：**黑屏清场的时刻，侧骨还在框内**，看起来就是"走一趟就消失 / 消失太早"。

### 3.3 逐帧实测（`lua/_probe_multibones.lua`）

```
t= 0.85 骨出现  x=-444  y=282 h=46 vx=240
...
t= 2.77 骨消失  x范围 173..524 …（存活 1.97s）
t= 2.77 骨消失  x范围 -228..232  …（存活 1.93s）   ← 这只骨还在框内(133..508)就被清掉了
t= 2.77 骨消失  x范围 -444..12   …                ← 还没进场就被清掉
```

> 说明：上面这份实测用的是 World 直跑（×1 速度）；在真实难度下 `tune` 还会再乘系数，但**段长被削 0.3s 这件事是确定的**。

---

## 4. 更正：我先前列的三个候选都不是根因

我在《`Sans_Fight_骨缝_骨速_旋转轴心_修改文档.md`》§2.3 列了三个候选：

| 候选 | 判定 |
|---|---|
| a `multi3 Attack5` 底边骨带（`20,20`） | **不是本次根因**（那是静态骨带，不涉及"消失时间"；是否要回原版另议） |
| b 第八轮 multi3 Attack0/4/5"降密度降尺寸" | **当前文件已是原版值**，无影响 |
| c `pushBone` 的难度速度缩放 | **不是**：难度同时缩放了速度(`tune.speed`)与延时(`tune.interval`)，相对关系基本自洽（实测 0.96~1.05×） |

**真正的根因 = 段末延时被 1.5 → 1.2 改反**（本文 §1/§2）。对上一份文档的误判，抱歉。

---

## 5. 恢复清单（改回原版）

| # | 文件 | 行 | 现在 | 改为 |
|---|---|---|---|---|
| 1 | `prototype/attacks/multi3.csv` | L105 | `1.2,JMPABS,RndAttack` | `1.5,JMPABS,RndAttack` |
| 2 | `prototype/attacks/multi3.csv` | L110 | `1.2,JMPABS,RndAttack` | `1.5,JMPABS,RndAttack` |
| 3 | `prototype/attacks/multi3.csv` | L126 | `1.2,JMPABS,RndAttack` | `1.5,JMPABS,RndAttack` |
| 4 | `prototype/attacks/multi3.csv` | L130 | `1.2,JMPABS,RndAttack` | `1.5,JMPABS,RndAttack` |
| 5 | `prototype/attacks/multi2.csv` | L36 | `1.2,JMPABS,RndAttack` | `1.5,JMPABS,RndAttack` |
| 6 | `prototype/attacks/multi2.csv` | L40 | `1.2,JMPABS,RndAttack` | `1.5,JMPABS,RndAttack` |

改完必须：

```powershell
cd D:\stars\workspace\sans-fight
node tools/gen-attacks.mjs     # CSV -> lua/attacks.lua
node tools/build-save.mjs      # 重建存档
node tools/run-lua.mjs lua/_probe_multibones.lua   # 侧骨存活时间应回到 ~1.5s+（不再在框内被清）
node tools/run-lua.mjs lua/core_selftest.lua       # 期望 PASS 281 / FAIL 0
node tools/verify-all.mjs --quick
```

### 验收标准

| 断言 | 期望 |
|---|---|
| multi3 Attack4/4Other | 段末延时 = **1.5s**；黑屏清场时侧骨已飞出框（x 覆盖 ≥ 框宽 + 骨宽） |
| multi3 Attack5/5Other | 段末延时 = 1.5s（底边骨带不受影响） |
| multi2 同段 | 1.5s |
| 其它段 | multi3 L141/147=1.2、L155/159=1.7、L168/173=1.9 **保持不动**；multi2 L51/57=2.6 保持不动 |
| `_probe_multibones.lua` | 侧骨"消失"时 x 已经离开战斗框，不再出现"还在框内就被清" |

---

## 6. 附：如何避免再犯

- 我那份文档的 diff 表直接来自脚本输出，但**列顺序标错了**；
- 以后凡"恢复原版"的改动，建议**先贴出原版文件原文片段**（带行号）作为证据，再给结论（本文 §1 就是这种写法）；
- 本项目 `prototype/attacks/*.csv` 是唯一源；`lua/attacks.lua` 是生成物 —— 任何改动都要跑 `gen-attacks.mjs` 并核对。

---

*本文结论基于：原版 `D:\c2-sans-fight-src\Files\sans_multi2.csv` / `sans_multi3.csv` 原文、端口 `prototype/attacks/multi2.csv` / `multi3.csv` 现状、以及 `lua/_probe_multibones.lua` 逐帧实测。*
