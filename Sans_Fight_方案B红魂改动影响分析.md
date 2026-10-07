# 方案 B（删除红魂重力）影响面分析

> 方案 B = 删掉 `lua/core.lua` 红魂分支里的引力块，让**红魂永远 4 向自由移动**（= 原版语义），`MaxFallSpeed` 只对蓝魂生效。

- **工作区**：`D:\stars\workspace\sans-fight`
- **相关文件**：`lua/core.lua`、`prototype/attacks/final.csv`、`prototype/attacks/spiral3.csv`、`lua/core_selftest.lua`
- **日期**：2026-10-07

---

## 0. 方案 B 精确改哪里

**文件**：`lua/core.lua`　**位置**：红魂分支（`else`）约 2404–2413 行

```lua
  else
    -- 红魂默认不吃重力；但脚本给过 HeartMaxFallSpeed（非 0）就吃 ——
    -- 原作最终回合阶段②的「反向重力走廊」正是 HeartMaxFallSpeed -300。
    local mf = self.soul.maxFall
    if mf then                                   -- ← 方案 B：删掉这个 if 块（连同注释）
      local g = d.p.gravity or GRAVITY
      self.soul.vy = self.soul.vy + g * dt
      if self.soul.vy > mf then self.soul.vy = mf end
      self.soul.y = self.soul.y + self.soul.vy * dt
      local floorY = self.box.y + self.box.h - SOUL_CLAMP
      if self.soul.y >= floorY then self.soul.y = floorY; self.soul.vy = 0 end
    end
    self.soul.y = clamp(self.soul.y, self.box.y + SOUL_CLAMP, self.box.y + self.box.h - SOUL_CLAMP)  -- ← 保留
  end
```

**改动量**：删 ~8 行（`if mf then ... end`），保留后面的 `clamp`。红魂的**四向按键移动在同一帧更早的位置执行**，不受影响。

---

## 1. `soul.maxFall` 的 4 个读取点 —— 只有 1 个被改

| 位置 | 用途 | 方案 B 后 |
|---|---|---|
| `core.lua:2256` | **蓝魂 slam 分支**的甩出速度（`mf==nil→750`） | ❌ 不受影响 |
| `core.lua:2344` | **蓝魂常规分支**的终端速度上限（`mf==nil→750`） | ❌ 不受影响 |
| **`core.lua:2406`** | **红魂引力块 ← 本次删除** | ✅ 受影响（红魂不再被 maxFall 拉） |
| `core.lua:2552` | World→Game 的 `maxFall` 同步（照旧写入） | ❌ 不受影响（值仍会写入 `soul.maxFall`，只是红魂不再使用） |

---

## 2. 谁会设置 `HeartMaxFallSpeed`（全 27 脚本扫描）

只有两个脚本用到它：

| 脚本 | 行 | 值 | 是否活脚本 |
|---|---|---|---|
| `final.csv` | L51 / L56 / L66 / L115 / L182 / L212 / L221 / L228 / L233 | 450 / −300 / 0 / 330 / 750 / 480 / 330 / 240 / 60 | ✅ HUD 24（唯一受影响） |
| `spiral3.csv` | L43 / L79 / L90 / L99 / L105 | 750 / 480 / 330 / 240 / 60 | ❌ **死脚本**（不在 `FIXED_SEQ`） |

验证：`M.scriptForRound(g, 0..25)` 输出为
`intro, bonegap1, bluebone, bonegap2, platforms1..4, platformblaster, platforms4hard, bonegap1fast, boneslideh, bonegap2, spare, multi1, randomblaster1, multi2, bonestab1, bonestab2, randomblaster2, boneslidev, multi3, bonestab3, final, final, ...`
→ **spiral1/2/3 永远不会被调度**（只在注释/自测里出现）。
**结论：实际战斗中方案 B 只影响 `final` 一关。**

---

## 3. `final` 里"红魂 + maxFall"的真实时段（探针实测）

`lua/_probe_final_modes.lua` 输出的模式切换时间线：

```
t= 0.02  模式 → red   maxFall=nil  y=78.0
t= 0.97  模式 → blue  maxFall=nil
t= 5.85  模式 → red   maxFall=nil  y=157.0
t= 9.40  模式 → blue  maxFall=nil          ← 阶段②反向走廊：SansSlam 强制蓝
t=29.75  模式 → red   maxFall=330  y=150.0  ← 红 + 残留330（≈1.7s）
t=31.43  模式 → blue  maxFall=330
t=36.00  模式 → red   maxFall=330  y=14.0   ← ★ 旋转龙骨炮段（Bug）
t=52.07  模式 → blue  maxFall=750           ← 阶段⑤审判眼连砸
```

影响对照：

| 时段 | 模式 | maxFall | 现在（方案 B 前） | 方案 B 后 |
|---|---|---|---|---|
| t=0.02–0.97 | red | nil | 自由 | 自由（不变） |
| t=0.97–5.85 | blue | nil | 蓝魂 | 不变 |
| t=5.85–9.40 | red | nil | 自由 | 不变 |
| t=9.40–29.75 | blue | 450 / −300 / 0 / 330 | 蓝魂（**反向重力走廊在这里**） | 不变 |
| t=29.75–31.43 | red | 330 | 被重力往下拉（≈1.7s） | **改为自由** |
| t=31.43–36.00 | blue | 330 | 蓝魂 | 不变 |
| **t=36.00–52.07** | **red** | **330** | **旋转龙骨炮段被重力拉（本次要修）** | **改为自由 ✅** |
| t=52.07+ | blue | 750 | 蓝魂（审判眼连砸） | 不变 |

**净效果**：方案 B 只改变 `final` 中两段红魂的下落（1.7s + 16s），其中 16s 那段正是"旋转龙骨炮"；蓝魂段落、阶段②反向走廊、阶段⑤连砸**都不受影响**。

---

## 4. 明确**不受影响**的部分

| 系统 | 为什么不受影响 |
|---|---|
| 蓝魂常规物理（4 档重力、可变跳、空中板子 `groundQuery` 落地） | 走 `if self.soul.mode == 'blue'` 分支，`maxFall` 由 `core.lua:2344` 读取 |
| 蓝魂 slam（`SansSlam` 甩击、撞墙伤害/抖屏 `SansShake`） | 走蓝魂内的 `slammed` 分支（`core.lua:2256`） |
| **"反向重力走廊"（final 阶段②）** | 实测该段是 **blue**（`SansSlam` 强制切蓝），走蓝魂分支 → 不受影响 |
| 阶段⑤审判眼连砸 | 每次循环内 `SansSlam,$Direction` 都会切蓝 → 走蓝魂分支 |
| 蓝/橙骨 "moved" 判定 | 按**输入**（是否按方向键）判定，不看 `vy` |
| 红魂四向移动 / 红心渲染（颜色、`dir=1` 朝向） | 移动在同帧更早的位置用方向键直接赋值；渲染只看 `mode/dir` |
| 平台落地（红魂兜底循环） | 仍保留；只是没有重力后，红魂要靠**按下键**才会落到平台上 —— 这与原版一致 |
| 其它 25 个脚本 | 全都不使用 `HeartMaxFallSpeed`，行为完全不变 |

---

## 5. 方案 B 会"失去"的能力（代价）

| 失去 | 说明 |
|---|---|
| "红魂 + 重力"这个组合 | 目前工作区把它实现成 `HeartMode,0` + `HeartMaxFallSpeed,<非0>` → 红魂也吃重力。方案 B 后该组合**不再产生重力** |
| "红魂钉住"（`HeartMaxFallSpeed,0`） | 红魂本来就自由，钉住无意义；不会丢功能 |
| 现状依赖 | **没有任何正当脚本依赖它** —— `final` 里出现的两段红+重力（330）都是阶段②残留的**泄漏**，是 bug；`spiral3` 是死脚本 |

> 将来若确实要做"红魂重力"新招式，需要另加机制（例如新增 `HeartGravity,<g>` 命令），而不是复用 `HeartMaxFallSpeed`。

---

## 6. 测试影响

| 项 | 情况 |
|---|---|
| `core_selftest.lua:718-725`（`extra-wall-slam`） | World 层断言（`w.heart.maxFall == 300`、`vx == maxFall`），**不经过红魂分支** → 不受影响 |
| `_input.lua` / `_geometry.lua` / `_flow.lua` | 不涉及"红魂 + maxFall 引力" → 不受影响 |
| **现有测试是否覆盖红魂引力** | **没有**。方案 B 不会让测试变红，但也意味着"改坏/改错"不会被自动发现 |

**建议新增 3 条断言（写进 `core_selftest.lua`）**：

```lua
-- 1) 红魂 + HeartMaxFallSpeed 不再产生重力
local g = newGame({scripts=A}); ... g:startEnemyScript(<红魂脚本>)
g.soul.maxFall = 300; g.soul.mode='red'
local y0 = g.soul.y; for i=1,60 do M.update(g, {}, DT) end
ok(math.abs(g.soul.y - y0) < 0.5, '红魂不再吃 maxFall 重力（方案B）')

-- 2) 蓝魂 + 同样设置仍然下落（证明只影响红魂）
-- 3) final 阶段④：持续光束期间 mode=='red' 且 vy==0
```

**探针**：`lua/_probe_final_tail.lua`（改后 t=36~52 应 `vy=0`、无输入 `y` 不变）；`lua/_probe_final_modes.lua`（模式时间线）。

---

## 7. 方案 A vs 方案 B（供取舍）

| | 方案 A（切红时清 `maxFall`） | **方案 B（删红魂引力块）** |
|---|---|---|
| 改动量 | 2 行 | 删 ~8 行 |
| 红魂语义 | 红魂自由；但脚本可在 `HeartMode,0` **之后**再设 `HeartMaxFallSpeed` 来重新启用"红+重力" | 红魂**永远**自由（= 原版） |
| 修 `final` 旋转段 | ✅（切红即清） | ✅（红魂不吃重力） |
| 保留扩展性 | 保留"红+重力"能力 | 失去该能力（如将来要做需另加命令） |
| 风险 | 低 | 低（无正当依赖） |
| 适合 | 想保留自定义扩展 | **追求原版语义（你的选择）** |

---

## 8. 落地步骤（方案 B）

1. 编辑 `lua/core.lua`：删除红魂分支 `core.lua:2404-2413` 的 `if mf then ... end`（保留后面的 `clamp`），并按需更新注释；
2. `node tools/run-lua.mjs lua/_probe_final_tail.lua` → 旋转龙骨炮段应 `vy=0`、无输入 `y` 不变；
3. `node tools/run-lua.mjs lua/_probe_final_modes.lua` → 确认 t≈36~52 为 red 且不再下落；
4. `node tools/run-lua.mjs lua/core_selftest.lua` → 期望仍 **PASS 281 / FAIL 0**；
5. `node tools/build-save.mjs` → 重建存档（试玩页才生效）；
6. `node tools/verify-all.mjs --quick`；
7.（建议）补 §6 的三条断言，防止以后再引入"跨阶段残留"。

---

## 附录：行号与脚本索引

| 内容 | 位置 |
|---|---|
| 红魂引力块（方案 B 删除目标） | `lua/core.lua:2404-2413` |
| 蓝魂 slam 读 `maxFall` | `lua/core.lua:2256` |
| 蓝魂常规读 `maxFall` | `lua/core.lua:2344` |
| `maxFall` 同步 | `lua/core.lua:2552` |
| 回合开始清 `maxFall` | `lua/core.lua:1533` |
| `HeartMaxFallSpeed` 定义 | `lua/core.lua:608` |
| `final` 相关行 | `prototype/attacks/final.csv` L51/56/66/115/161/182 |
| `spiral3`（死脚本） | `prototype/attacks/spiral3.csv` L43/79/90/99/105 |
| 模式时间线探针 | `lua/_probe_final_modes.lua` |
| 逐帧状态探针 | `lua/_probe_final_tail.lua` |

---

*本文影响范围由「全脚本 `HeartMaxFallSpeed` 扫描 + `scriptForRound` 实际调度表 + `final` 逐帧模式探针」三重交叉确认：方案 B 在实际战斗中只影响 HUD 24 的 `final`，且其蓝魂段落与阶段②反向走廊不受影响。*
