# final 旋转龙骨炮阶段「红心仍像蓝心」—— 问题定位与修改文档

- **工作区**：`D:\stars\workspace\sans-fight`
- **相关文件**：`prototype/attacks/final.csv`、`lua/core.lua`
- **复现探针**：`lua/_probe_final_tail.lua`
- **日期**：2026-10-07

---

## 0. 结论速览

| 项 | 内容 |
|---|---|
| **现象** | final 阶段④「旋转龙骨炮」（持续光束，约 t=36~51s）时，灵魂**已经是红心**（`mode=red`），但**仍被重力持续向下拉**，松开按键会自己往下掉、贴到框底 → 手感像蓝心 |
| **根因** | `soul.maxFall` 保留了上一阶段的 `HeartMaxFallSpeed,330`；而红魂分支写成「`if soul.maxFall then 施加引力`」→ 红心被这个**跨阶段残留值**持续拉下去 |
| **缺陷点** | 切红复位（`HeartMode 0`）清了 `dir/slammed/slamT/push/vx/vy`，**唯独没清 `maxFall`**；而 `maxFall` 只在**回合开始**才被清 |
| **一句话** | "红魂是否受重力"被错误地绑在"`maxFall` 是否为 nil"上，而 `maxFall` 是跨阶段残留的 |
| **修法** | 方案 A（推荐）：切红时把 `soul.maxFall` 清成 `nil`；方案 B：删掉红魂分支的引力块（红魂永远自由，符合原版） |

---

## 1. 实测证据（真实 final 脚本 + 真实 Game 路径）

`node tools/run-lua.mjs lua/_probe_final_tail.lua` 输出（节选）：

```
t= 30.1 mode=red  dir=1 maxFall=330  slammed=false vx=0.0 vy=  0.0 y=157.0
t= 36.1 mode=red  dir=1 maxFall=330  slammed=false vx=0.0 vy= 50.0 y= 16.5  ◀持续光束(旋转龙骨炮)
t= 36.6 mode=red  dir=1 maxFall=330  slammed=false vx=0.0 vy=330.0 y=118.5  ◀持续光束(旋转龙骨炮)
t= 37.1 mode=red  dir=1 maxFall=330  slammed=false vx=0.0 vy=  0.0 y=157.0  ◀持续光束(旋转龙骨炮)   ← 落到框底
t= 51.1 mode=red  dir=1 maxFall=330  slammed=false vx=0.0 vy=  0.0 y=157.0
t= 52.1 mode=blue dir=0 maxFall=750  slammed=false vx=750.0 vy=0.0 y=157.0                     ← 阶段⑤才转蓝
```

要点：
- **模式是对的**（`mode=red`），**物理是错的**：`maxFall=330` 让红心以最高 330px/s 下落；
- 无输入时灵魂从 `y=16.5` 被拉到 `y=157`（框底）—— 这就是"像蓝心"的直接来源；
- 对照 `t=0~7`（`mode=red, maxFall=nil`）：红心静止不动，才是正常的自由移动。

---

## 2. 代码链路（逐行定位）

### 2.1 设置与同步

```
core.lua:608   CMD.HeartMaxFallSpeed = function(w, v)
                 w.heart.maxFall = tonumber(v)
                 w.heartMaxFallDirty = true          -- 只把值写进 world
core.lua:2551  if w.heartMaxFallDirty then
                 self.soul.maxFall = w.heart.maxFall  -- 再同步到 game
                 w.heartMaxFallDirty = false
               end
```

### 2.2 红魂分支 —— **只看 maxFall，不问它来自哪一阶段**

```
core.lua:2404  else
                 -- 红魂默认不吃重力；但脚本给过 HeartMaxFallSpeed（非 0）就吃
core.lua:2406    local mf = self.soul.maxFall
                 if mf then
                   local g = d.p.gravity or GRAVITY
                   self.soul.vy = self.soul.vy + g * dt
                   if self.soul.vy > mf then self.soul.vy = mf end
                   self.soul.y = self.soul.y + self.soul.vy * dt
                   ...（贴地清零）
                 end
```

### 2.3 切红复位 —— **漏了 maxFall**（缺陷点）

```
core.lua:2534  else                                  -- HeartMode 0（切红）
                 self.soul.mode   = 'red'
                 self.soul.dir    = 1
                 self.soul.slammed= false
                 self.soul.slamT  = nil
                 self.soul.push   = nil
                 self.soul.vx, self.soul.vy = 0, 0
                 w.heart.slammed  = false
                 w.heart.dir      = 1
                 -- ❌ 没有 self.soul.maxFall = nil
```

### 2.4 `maxFall` 只在回合开始被清

```
core.lua:1533  self.soul.maxFall = nil     -- startEnemy：一回合只清一次
```

→ 同一回合（`final` 是一个 53 秒的超长回合）内，`maxFall` 会**跨阶段残留**。

---

## 3. 为什么偏偏在"旋转龙骨炮"暴露

`final` 的 `HeartMode / HeartMaxFallSpeed` 时间线（脚本行号）：

| 行 | 指令 | 说明 |
|---|---|---|
| L115 | `8,HeartMaxFallSpeed,330` | 阶段②/③ 设置终端速度 330 → `soul.maxFall = 330` |
| L130 | `0,HeartMode,0` | 切红（阶段③黑屏骨刺）→ **复位没清 maxFall** |
| L141/150/158 | `SansSlam,3/0/2` | 短暂强制蓝（这几秒是蓝魂） |
| **L161** | `0.7,HeartMode,0` | **切红准备旋转龙骨炮** → 仍没清 maxFall |
| **L162–180** | 旋转龙骨炮：`GasterBlaster,...,0.5,0`（持续光束循环） | **本应是红魂自由移动，却带着 330 的重力** |
| L182 | `0,HeartMaxFallSpeed,750` + `L184 SansSlamDamage,1` | 阶段⑤（审判眼连砸）才重新需要引力（此时 `SansSlam` 会强制蓝） |

**原版语义**：`MaxFallSpeed` 只作用于**蓝魂**；红魂永远 4 向自由移动。
工作区把"红魂受重力"实现成 `maxFall ~= nil` 的开关，于是"上一阶段的蓝魂终端速度"泄漏进了"这一阶段的红魂"。

---

## 4. 修改建议

### 方案 A（推荐，最小改动）：切红时清 `maxFall`

在 `core.lua` 的 `if w.heartModeDirty then ... else`（切红）分支里补两行：

```lua
      else
        -- 【修】切回红心 = 完整复位
        self.soul.mode = 'red'
        self.soul.dir = 1
        self.soul.slammed = false
        self.soul.slamT = nil
        self.soul.push = nil
        self.soul.vx, self.soul.vy = 0, 0
        self.soul.maxFall = nil            -- ★ 新增：清掉上一阶段残留的 HeartMaxFallSpeed
        w.heart.slammed = false
        w.heart.dir = 1
        w.heartDirDirty = false
        w.heartMaxFallDirty = false        -- ★ 新增：防止脏标记把它再同步回来
      end
```

**兼容性说明**
- 真正需要"重力"的段落（如 final 阶段②的反向重力走廊）在脚本里是 **`SansSlam`（强制蓝）之后** 才设 `HeartMaxFallSpeed`，走的是**蓝魂分支**，不受本次修改影响；
- 将来若要做"红魂 + 重力"的新招式，只要按 `HeartMode,0` → `HeartMaxFallSpeed,<v>` 的**先后顺序**写脚本即可（切红先清、随后置位）。

### 方案 B（更贴原版）：删掉红魂的引力块

直接把 `core.lua:2406-2413` 的 `if mf then ... end` 整段删除 —— 红魂从此**永远自由移动**，`MaxFallSpeed` 只对蓝魂生效（= 原版语义）。
风险略高于 A（若某处确实依赖"红魂 + maxFall 引力"会失去该行为），但目前脚本里没有这种正当用法。

### 方案 C（脚本侧临时规避，不推荐）

在 `final.csv` L161 的 `HeartMode,0` 后补一行 `0,HeartMaxFallSpeed,0`。
注意：红魂里 `mf=0` 是**"钉住"**（`if mf` 对 0 仍为真，只把下落速度压到 0），并不是真正的"无重力"；能止血但语义不干净。

---

## 5. 验证

```powershell
cd D:\stars\workspace\sans-fight
node tools/run-lua.mjs lua/_probe_final_tail.lua     # 改后：旋转龙骨炮段 maxFall 应为 nil
node tools/run-lua.mjs lua/core_selftest.lua         # 期望 PASS 281 / FAIL 0
node tools/build-save.mjs
node tools/verify-all.mjs --quick
```

| 断言 | 期望 |
|---|---|
| A1 | `HeartMode,0` 执行后 `soul.maxFall == nil` |
| A2 | 红魂 + 无输入 60 帧：`soul.y` 不变（无重力） |
| A3 | final 阶段④（持续光束期间）：`mode=='red'` 且 `maxFall==nil`，`abs(vy) < 1` |
| A4 | 蓝魂段落（bonegap 等）：`maxFall` 仍按脚本设置生效（`HeartMaxFallSpeed 330/-300/0` 不改行为） |
| A5 | final 阶段⑤：`SansSlam` 后仍能进入蓝魂 + 750 的连砸（不受影响） |

---

## 6. 影响面

| 项 | 说明 |
|---|---|
| 顺带修正 | 所有"红魂 + 残留 maxFall"的段落（final 的 L22 / L47 / L130 / L161 切红点） |
| 不受影响 | final 阶段②反向重力走廊（`SansSlam`→蓝）、阶段⑤连砸、其它蓝魂关卡 |
| 渲染 | 红心的朝向（`dir=1`）此前已修；本次只修"运动/重力" |
| 必做 | 改完 `lua/*.lua` 后 `node tools/build-save.mjs` 重建存档 |
| 提醒 | `prototype/attacks/*.csv` 与 `lua/attacks.lua` 必须保持同步（近两天出过一次 CSV 滞后、重新生成覆盖 10 个脚本的事故） |

---

## 附录：行号索引

| 内容 | 位置 |
|---|---|
| `CMD.HeartMaxFallSpeed` | `lua/core.lua:608` |
| `soul.maxFall` 同步 | `lua/core.lua:2551` |
| 红魂引力块（缺陷） | `lua/core.lua:2404-2413` |
| 切红复位（漏清 maxFall） | `lua/core.lua:2534-2549` |
| 回合开始清 maxFall | `lua/core.lua:1533` |
| final 时间线关键行 | `prototype/attacks/final.csv` L115 / L130 / L161 / L162–180 / L182 |
| 复现探针 | `lua/_probe_final_tail.lua` |

---

*本文结论由真实 `final` 脚本 + 真实 `Game` 路径的逐帧探针验证（`mode=red / maxFall=330 / vy→330 / y→157`），并逐行定位到红魂分支与切红复位之间的状态泄漏。*
