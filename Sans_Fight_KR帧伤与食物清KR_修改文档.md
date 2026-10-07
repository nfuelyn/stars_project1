# Sans Fight：帧伤 / 蓝血（KR）机制对照与修改文档

> 日期：2026-10-07
>
> 参考文件：
> - `D:\stars\_analysis\Battle.xml.txt`（Construct 2 `Battle.xml` 的可读导出，本文主要引用）
> - `D:\stars\workspace\_refs\c2-sans-fight\Event sheets\Battle.xml`（原始事件表）
> - `D:\stars\workspace\_refs\c2-sans-fight\Event sheets\Items.xml`（道具表）
> - `D:\stars\workspace\_refs\c2-sans-fight\Bad Time Simulator (Sans Fight).caproj`（对象族/实例变量）
>
> 当前实现：
> - `D:\stars\workspace\sans-fight\lua\core.lua`（主逻辑；行号按 2026-10-07 工作区）
> - `D:\stars\workspace\sans-fight\lua\main.lua`（HUD 血条绘制）
> - `D:\stars\workspace\sans-fight\lua\core_selftest.lua`（回归）
>
> 历史对照：`D:\stars\workspace\sans-fight\prototype\game.js`（旧 JS 原型，部分行为比 Lua 更接近参考）

---

## 0. 结论摘要

本次对照后，当前 Lua 实现有 **3 个必须修（P0）**、**1 个建议修（P1）**、**2 个保留差异（P2）**：

| 优先级 | 机制 | 参考文件行为 | 当前 Lua 行为 | 处理建议 |
|---|---|---|---|---|
| **P0** | 食物/道具与 KR | 只加 HP；`KR`、`KR_T` 完全不变 | `item` 使用后把 `KR`、`KR_T` 清零 | **删除清 KR 代码** |
| **P0** | KR 上限 | `KR = min(40, KR + Karma)` 后再夹到 `当前HP - 1` | 只夹 40；低 HP 时 KR 可远大于 HP | **补 `KR <= HP-1` 夹取** |
| **P0** | KR 燃烧档位（帧伤曲线） | 40 档 0.033s；30 档 0.066s；20 档 0.166s；10 档 0.5s；其余 1.0s | 一律 0.5s/点 | **改为分级阈值** |
| **P1** | 同一攻击对象的 Karma 衰减 | 首次命中后若 `Karma >= 3`，置为 2；再次命中只加 2 | 每次命中都按 6/10 加 | 建议补逐对象 `karma` 状态 |
| P2 | 非原作难度的命中冷却 | 参考实现固定 0.033s（约 2 帧@60fps） | `original` 档 0.033s；其他难度 1.0/0.8/0.55 | 若这是难度设计，保留并标注 |
| P2 | 求饶清 KR | 参考的 `Spare` 不清 KR，只进入攻击 | 当前自定义 `beg` 清 KR | 若追求严格复刻，改为不清；否则保留并标明自定义 |

**一句话结论**：当前实现把“蓝血”当成了固定 0.5s 跳一次的简化中毒，并且治疗会把它直接清掉；参考文件的实际规则是 **“先按上限夹取，再按 KR 高低以 2/4/10/30/60 帧的节奏逐点燃烧；治疗只回 HP，不能解除 KR”**。低 HP 时 KR 会被夹到 `HP-1`，这正是之前被误判为“受击判定消失”的现象。

---

## 1. 参考文件中的机制拆解

### 1.1 术语与对象

- **帧伤 / 命中冷却**：参考事件表用 `LastDamageTime` 控制“多久允许再次受到一次接触伤害”。对应 `Battle.xml.txt:1482`。
- **蓝血 / KR**：参考事件表里的 `KR` 与 `KR_T` 两个全局变量。`KR` 是紫色条的当前值，`KR_T` 是燃烧计时器。
- **Karma**：每个攻击对象携带的“命中时增加多少 KR”的数值。骨头为 6，龙骨炮为 10。
- **Damage**：攻击对象的直接伤害。参考实现里骨头/龙骨炮通常为 1。

### 1.2 命中：一次伤害如何结算

参考文件 `PlayerDamage` 组的核心顺序（`Battle.xml.txt:1459-1520`）：

1. `LastDamageTime = time`（记录本次命中时刻）。
2. `HP -= Damage`（直接伤害）。
3. `KR += Karma`（蓝血增加）。
4. 播放 `PlayerDamaged`。
5. 对攻击对象做 Karma 衰减：若该对象的 `Karma >= 3`，把它改为 `2`（`Battle.xml.txt:1488-1489`、`1502-1503`、`1509-1520`）。

其中第 5 点是当前实现缺失的：

- 骨头 `BoneH/BoneV`：`Damage=1`，`Karma=6`（`Battle.xml.txt:835-837`、`846-847`）。
- 骨刺 `BoneStabH/BoneStabV`：`Karma=6`（`Battle.xml.txt:979`、`995`）。
- 龙骨炮命中体 `GasterBlastHit`：`Damage=1`，`Karma=10`（`Battle.xml.txt:1105-1106`）。

因此参考实现的第一次命中是 **+6 / +10 KR**，同一个攻击对象后续再命中只加 **2 KR**。这不是“一个攻击对象只打一次 HP”，而是 **HP 仍按冷却逐次扣，KR 增量按对象衰减**。

> 说明：Construct 2 的比较码在本工程中为 `4 = >`、`5 = >=`、`2 = <`。因此 `Karma Comparison=5 Value=3` 读作 `Karma >= 3`；`LastDamageTime Comparison=2 time-0.033` 读作 `LastDamageTime < time - 0.033`，即距上次命中至少 0.033s。

### 1.3 帧伤门限：0.033s

参考事件表的接触伤害外层条件（`Battle.xml.txt:1482`）：

```
IF System :: Compare variable  (Variable=LastDamageTime, Comparison=2, Value=time-0.033)
```

含义：只有当 `LastDamageTime < time - 0.033` 时，才允许本帧继续检查攻击对象的重叠伤害。也就是：

- 两次接触伤害之间至少间隔 **0.033s**；
- 按 60fps 计算约为 **2 帧**；
- 这是“帧伤”的节奏来源，而不是 KR 的燃烧节奏。

当前 Lua 在 `original` 难度下用 `invuln = 0.033`（`core.lua:199`），这一点与参考一致；其他难度档把冷却拉长到 1.0/0.8/0.55（`core.lua:196-198`），属于有意的难度设计，不是必须修的 bug。

### 1.4 KR 的上限：先 40，再 `HP-1`

参考文件每个 tick 都会执行（`Battle.xml.txt:1521-1524`）：

```
IF KR >= 40  -> KR = 40
IF KR >= HP  -> KR = HP - 1
```

两个条件按顺序执行，所以有效上限是：

```
KR_effective_max = min(40, HP - 1)
```

关键后果：

- `HP=1` 时：`KR = 0`，紫色条消失，不再燃烧；
- 紫色条永远不能覆盖最后一格 HP；血条上至少保留 1 点黄色；
- 低 HP 时 KR 会被大幅夹取。例如：
  - `HP=3` 被骨头命中：先 `HP=2`、`KR=6`，再夹到 `KR=1`；
  - `HP=2` 被骨头命中：先 `HP=1`、`KR=6`，再夹到 `KR=0`；
  - `HP=9` 被龙骨炮命中：先 `HP=8`、`KR=10`，再夹到 `KR=7`。

当前 Lua 只做了 `min(40, ...)`（`core.lua:1975`），没有 `HP-1` 夹取，导致低 HP 时 KR 可以保持很大的数值，紫色条（或 HUD 数字）与实际危险度不符。

### 1.5 KR 燃烧：按 KR 档位改变的“帧伤”曲线

参考文件的燃烧块（`Battle.xml.txt:1525-1551`）结构如下：

- 父条件：`KR > 0` 且 `HP > 1`；
- 每 tick：`KR_T += dt`；
- 然后按顺序检查 5 个档位，**命中第一个满足条件的档位后** 执行 `KR -= 1`、`HP -= 1`、`KR_T = 0`。

| 顺序 | 条件 | 阈值 | 约 60fps 帧数 | 动作 |
|---|---|---|---|---|
| 1 | `KR >= 40` 且 `KR_T >= 0.033` | 0.033s | 2 帧 | KR-1、HP-1、KR_T=0 |
| 2 | `KR >= 30` 且 `KR_T >= 0.066` | 0.066s | 4 帧 | 同上 |
| 3 | `KR >= 20` 且 `KR_T >= 0.166` | 0.166s | 10 帧 | 同上 |
| 4 | `KR >= 10` 且 `KR_T >= 0.5` | 0.5s | 30 帧 | 同上 |
| 5 | `KR_T >= 1`（覆盖 `KR < 10`） | 1.0s | 60 帧 | 同上 |

要点：

- **档位按“当前 KR”判定**。例如 `KR=40` 烧一次后变成 39，下一次不再走 0.033s 档，而是走 `KR>=30` 的 0.066s 档。
- 因为每次结算后 `KR_T` 归零，**同一 tick 只结算一次**。参考实现是逐帧事件，不是“补帧”的 while 循环。
- 父条件 `HP > 1` 保证烧血不会把 HP 烧到 0；再配合 1.4 的 `KR <= HP-1`，最终 HP 会停在 1、KR 归 0。
- `KR_T` 只在结算后清零。参考文件没有在“增加 KR”时清零 `KR_T`，所以连续命中时计时器是连续累计的。

### 1.6 食物/道具：只回 HP，不清 KR

参考文件的 `MenuUseItem` 事件（`Battle.xml.txt:471-492`，原始 XML `Battle.xml:2426-2517`）在成功使用道具时只做这些事：

1. `HP += ItemDB.At(ItemID, 1)`；
2. 播放 `PlayerHeal`；
3. 生成“你吃掉了……恢复了……HP”的文字；
4. 从 `PlayerItems` 删除该道具。

**没有任何 `KR` 或 `KR_T` 写入。** 因此：

- 吃东西时如果身上有蓝血，蓝血不会消失；
- 蓝血计时器也不会重置；
- 治疗只是把 HP 垫高，让蓝血有更多 HP 可以烧；
- 参考的 `Spare`（`Battle.xml.txt:499-504`）也同样不清 KR，它只是隐藏灵魂并进入攻击。

参考道具表（`Items.xml:15-27`）为：Butterscotch Pie +99、Instant Noodles +90、Face Steak +60、Legendary Hero +40。当前游戏把道具统一成“传奇面包 +45”是另一项有意的内容差异；本次只要求 **“使用道具不改变 KR/KR_T”** 这一行为与参考一致。

### 1.7 HUD 口径

参考 `HPBar` 每 tick（`Battle.xml.txt:1590-1594`）：

```
HPBar.Width = HPBackground.Width * HP / MaxHP
KRBar.Width = ceil(HPBackground.Width * KR / MaxHP)
KRBar.X     = HPBackground.X + HPBackground.Width * (HP - KR) / MaxHP
```

即黄段长度 = `HP - KR`，紫段长度 = `KR`。因为模型里有 `KR <= HP-1`，所以黄段永远至少 1 格。

当前 `main.lua:1144-1157` 的绘制公式与参考一致，但做了 `kr = min(hp, kr)` 的显示层夹取（`main.lua:1152`），而不是 `hp - 1`。如果按本文修正模型，这个显示层夹取就不再会掩盖真实状态；也可以顺手改成 `math.min(math.max(0, hp - 1), kr)` 作为防御性显示。

---

## 2. 当前工作区实现逐项对照

### 2.1 对照总表

| 机制 | 参考文件 | 当前 Lua 实现 | 结论 |
|---|---|---|---|
| 命中冷却 | 固定 0.033s | `original=0.033`；easy/normal/hard=1.0/0.8/0.55 | `original` 一致；其他档为难度设计 |
| 单次命中 HP | -1 | -1 | 一致 |
| 骨头 KR | 首次 +6，之后同对象 +2 | 每次 +6 | 缺 Karma 衰减 |
| 龙骨炮 KR | 首次 +10，之后同对象 +2 | 每次 +10 | 缺 Karma 衰减 |
| KR 上限 40 | 有 | 有（`KR_MAX=40`） | 一致 |
| KR 上限 HP-1 | 有 | 无 | **缺** |
| KR 燃烧 | 0.033/0.066/0.166/0.5/1.0 五档 | 固定 0.5 | **不符** |
| 燃烧时 HP=1 | KR 被夹到 0，不再烧 | KR 继续减到 0，HP 保持 1 | **低血量状态不符** |
| 道具 | 只加 HP | 加 HP 并把 KR/KR_T 清零 | **不符** |
| 求饶/Spare | Spare 不清 KR | 自定义 beg 清 KR | 自定义差异 |
| 菜单/攻击条期间燃烧 | 继续燃烧 | `menu/sub/attack/enemy` 都调用 `updateKR` | 一致 |

### 2.2 当前代码定位

| 位置 | 现状 | 问题 |
|---|---|---|
| `core.lua:113-115` | `KR_PER_HIT=6`、`KR_TICK=0.5`、`KR_MAX=40` | 只有单一 `KR_TICK`，没有档位表 |
| `core.lua:1871-1873` | `beg` 清 KR | 自定义行为，参考 Spare 不清 |
| `core.lua:1881-1882` | `item` 清 KR、KR_T | **与参考直接冲突** |
| `core.lua:1967-1985` | `hurt()` 只做 `min(40, kr + karma)` | **缺 `HP-1` 夹取** |
| `core.lua:1988-2003` | `updateKR()` 固定 0.5s，while 循环 | **无档位、可一帧多跳、HP=1 仍烧 KR** |
| `core.lua:2168-2192` | attack/menu/sub/enemy 都调用 updateKR | 这部分与参考一致，保留 |
| `main.lua:1144-1157` | HUD 黄/紫分段 | 公式一致；显示层夹到 `hp` 而非 `hp-1` |
| `core_selftest.lua:285-296` | 期望 `hit hp=1 kr=6` | 这是夹取前的中间值；修正后应改为 `kr=0` |
| `core_selftest.lua:544-562` | 只断言回血，不断言 KR 保留 | **缺“食物不清 KR”回归** |

### 2.3 与旧 JS 原型的关系

旧原型 `prototype/game.js` 在两个点上比 Lua 更接近参考：

- `prototype/game.js:351-356`：道具只加 HP，**不清 KR**；
- `prototype/game.js:388-395`：`hurt()` 有 `kr = min(kr + KR_PER_HIT, max(0, hpBefore - 1))` 的夹取。

但 JS 原型也有自己的偏差：

- `KR_PER_HIT = 4`（`prototype/game.js:75`），不是参考的 6/10；
- 夹取用的是 `hpBefore - 1`，它等于 **命中后的 HP**，比参考的“命中后 HP-1”多 1；因此 `HP=2` 命中后 JS 得到 `kr=1`，参考是 `kr=0`（`prototype/selftest.js:91` 的旧断言正是 `hit hp=1 kr=1`）；
- `updateKR()` 仍是固定 0.5s（`prototype/game.js:407-418`），没有参考的五档曲线；
- `original` 难度的 invuln 是 0.15，不是参考的 0.033（`prototype/game.js:54`）。

因此本次修复以 **参考事件表** 为准，JS 原型的“道具不清 KR”可以借鉴，但夹取公式要再减 1、燃烧要换成五档。

---

## 3. 建议修改

### P0-1：食物/道具不再清 KR

参考行为是“只加 HP”。当前代码（`core.lua:1876-1884`）应改为：

```lua
  if self.sub == 'item' then
    local it = self:itemList()[i + 1]
    if not it then self:subBack(); return end
    it.count = it.count - 1
    self.hp = math.min(self.maxHP, self.hp + it.heal)
    -- 参考 Battle.xml MenuUseItem：只回复 HP；KR / KR_T 不变。
    -- 蓝血只能按自己的燃烧曲线自然结束，不能被治疗解除。
    self:log('item_used id=' .. it.id .. ' hp=' .. self.hp .. ' left=' .. self:itemCount())
    self.sub = nil; self:afterPlayerTurn(); return
  end
```

也就是删除原来的：

```lua
    -- 原作：**治疗会顺带清掉 KR**（业障随治疗消散），这也是原作里「吃一口再打」的战术价值。
    if self.kr > 0 then self.kr = 0; self.krT = 0; self.krActive = false; self:log('kr_cleared by=item') end
```

注意：删除后，吃东西时如果 `KR > 0`，它会在接下来的 `attack` 条阶段继续按档位燃烧。这正是参考文件的行为。

### P0-2：恢复 `KR <= HP-1` 夹取

新增一个统一的夹取函数，并在 `hurt()` 加完 KR 后、以及 `updateKR()` 开头调用。建议把 `clampKR` 定义放在 `hurt/updateKR` 之前（至少保证模块加载完成），避免运行期调用顺序问题。这样：

- 命中后的日志/HUD 立刻反映夹取后的 KR；
- 不会出现“HP=1 时 KR 还挂着一大截”的状态。

推荐实现：

```lua
-- 参考 Battle.xml 1521-1524：
--   先夹 40，再夹到当前 HP-1；HP=1 时 KR 必然为 0。
function Game:clampKR()
  local hadKR = self.kr > 0
  if self.kr > KR_MAX then self.kr = KR_MAX end

  local cap = self.hp - 1
  if cap < 0 then cap = 0 end

  if self.kr > cap then
    if cap == 0 and hadKR and not self.krFloorLogged then
      self.krFloorLogged = true
      self:log('kr_floor hp=' .. self.hp)
    end
    self.kr = cap
  end

  if self.kr <= 0 then
    self.kr = 0
    if hadKR then
      self.krActive = false
      self:log('kr_done hp=' .. self.hp .. ' kr=0')
    end
  end
end
```

`hurt()` 里把原来的 KR 赋值改成：

```lua
  local hpBefore = self.hp
  self.hp = self.hp - 1

  self.krFloorLogged = false
  self.kr = self.kr + (karma or KR_PER_HIT)
  self:clampKR()
  self.krActive = self.kr > 0
```

> 关于 `hpBefore`：当前 `hurt()` 已经没有别的用途，可以删除；这里保留只是说明不应再用“命中前 HP”做上限。参考用的是 **命中后的 HP - 1**。

**这一步会重新引入“低血量紫条几乎不动”的现象，但它是参考文件的原意**：

- `HP=3` 命中后：`HP=2, KR=1`（不是 KR=6）；
- `HP=2` 命中后：`HP=1, KR=0`（不是 KR=6）；
- 旧文档 `records/playtest.md:93` 把“KR 上限用命中后 HP 计算”当成 bug，改成“命中前 HP-1”，这是方向反了的。参考事件表明确是 `KR >= HP -> KR = HP-1`，即 **命中后的 HP - 1**。

如果项目出于手感考虑要保留“低血量也能看到大紫条”的差异，可以保留现状，但必须在文档中明确标为**有意偏离参考**，而不是“照原作”。

### P0-3：把固定 0.5s 改成五档燃烧

把 `KR_TICK` 常量替换为档位表：

```lua
local KR_MAX = 40

-- 参考 Battle.xml 1525-1551：按当前 KR 决定 KR_T 阈值。
-- 数值为秒；括号内为约 60fps 帧数。
local KR_TIERS = {
  { min = 40, step = 0.033 }, -- 2 帧
  { min = 30, step = 0.066 }, -- 4 帧
  { min = 20, step = 0.166 }, -- 10 帧
  { min = 10, step = 0.500 }, -- 30 帧
  { min = 0,  step = 1.000 }, -- 60 帧（KR < 10）
}

local function krStep(kr)
  for _, tier in ipairs(KR_TIERS) do
    if kr >= tier.min then return tier.step end
  end
  return 1.0
end
```

`updateKR()` 改为“每帧最多结算一次”：

```lua
function Game:updateKR(dt)
  self:clampKR()
  if self.kr <= 0 then return end
  if self.hp <= 1 then return end   -- 参考父条件：HP>1 才燃烧

  self.krT = (self.krT or 0) + dt
  local step = krStep(self.kr)
  if self.krT < step then return end

  -- 参考：结算一次后 KR_T 直接归零，不做 while 补帧。
  self.krT = 0
  self.kr = self.kr - 1
  if self.hp > 1 then
    self.hp = self.hp - 1
  elseif not self.krFloorLogged then
    self.krFloorLogged = true
    self:log('kr_floor hp=' .. self.hp)
  end

  if self.kr <= 0 then
    self.kr = 0
    self.krActive = false
    self:log('kr_done hp=' .. self.hp .. ' kr=0')
  end
end
```

要点：

- 使用 `if` 而不是 `while`。参考事件表每 tick 只可能命中一个档位，并在结算后把 `KR_T` 清零；
- `step` 用 **结算前的当前 KR** 计算，所以 `KR=40` 先按 0.033s 跳一次，之后 39 按 0.066s；
- `self:clampKR()` 放在开头，保证 `HP=1` 时 KR 先归 0，不会出现“HP=1 还在烧”；
- 当前 `updateKR` 的调用点（`core.lua:2168-2192`）不需要改：attack、menu、sub、enemy 都继续调用它，符合参考“菜单/攻击条都持续燃烧”。

> 关于 `KR_T` 归零时机：参考文件在“命中夹取”路径不显式重置 `KR_T`，只在燃烧结算后重置。上面的 `clampKR()` 也没有重置 `KR_T`。如果实现时为了状态干净而重置，影响仅限于“KR 被夹到 0 后立刻又获得 KR”的极端情况；建议按参考不重置。

### P1：补同一攻击对象的 Karma 衰减

参考文件在每次 `DamagePlayer` 后做（`Battle.xml.txt:1488-1520`）：

```
IF AttackSprite.Karma >= 3 -> AttackSprite.Karma = 2
IF AttackTiled.Karma  >= 3 -> AttackTiled.Karma  = 2
IF Attack9Patch.Karma >= 3 -> Attack9Patch.Karma = 2
```

当前 Lua 的 `hurt(kind, karma)` 只接受一个数字，无法记录“这个骨头/这个龙骨炮已经打过一次”。建议改为：

```lua
function Game:hurt(kind, karma, src)
  if self.state ~= 'enemy' or self.invuln > 0 then return false end
  ...
  local gain = karma or (src and src.karma) or KR_PER_HIT
  self.kr = self.kr + gain
  self:clampKR()

  -- 参考：同一攻击对象首次命中后，若 Karma >= 3，后续命中降为 2。
  if src and src.karma and src.karma >= 3 then
    src.karma = 2
  end
  ...
end
```

调用侧：

- 脚本骨头：生成时给 `bn.karma = bn.karma or 6`；碰撞时 `self:hurt('hit', bn.karma, bn)`；
- 龙骨炮：给 `B.karma = B.karma or 10`；光束判定时 `self:hurt('hit', B.karma, B)`；
- 骨墙/正弦骨等如果同属一个持续对象，也应传入该对象；
- 若暂时不想改 `hurt` 签名，可以先只把“多次命中扣 6/10”记为已知差异，但这会让高密度弹幕比参考更惩罚。

**优先级**：这是 P1，不是本次“食物不清 KR”的直接阻塞项；但它属于“蓝血机制”的一部分，建议在同一次修改中一起做，避免后续再改一次伤害签名。

### P2：命中冷却与求饶

- **命中冷却**：参考固定 0.033s；当前 `original` 档已经一致，其他难度是有意放宽。如果目标是“所有难度都复刻参考”，把 `core.lua:196-199` 的 `invuln` 全部改成 0.033；如果保留难度设计，在 README 中注明“只有原作档使用参考的 2 帧冷却”。
- **求饶清 KR**：参考的 `Spare` 不清 KR。当前 `core.lua:1871-1873` 是自定义的“求饶”效果。如果保留，请在 `README`/GDD 中写成“本作自定义：求饶可清一次 KR”，不要写成“原作机制”。

---

## 4. 行为对照示例

下面用 60fps 模拟，展示修正前/后的关键差异。

### 4.1 单次骨头命中（+6 KR）

场景：`HP=10, KR=0`，被同一根骨头命中一次，之后不再受击。

| 实现 | 命中后 | 燃烧结束 | 总燃烧时间 | 说明 |
|---|---|---|---|---|
| 参考文件 | `HP=9, KR=6` | `HP=3, KR=0` | 约 6.0s | KR<10，1s/点，稳定 6 秒 |
| 当前 Lua | `HP=9, KR=6` | `HP=3, KR=0` | 约 3.0s | 固定 0.5s/点，压力更短更急 |

两者最终 HP 相同，但参考的蓝血持续更久，玩家有更长的“被追着掉血”的压迫期。

### 4.2 单次龙骨炮命中（+10 KR）

场景：`HP=10, KR=0`，被龙骨炮命中一次。

| 实现 | 命中后 | 燃烧结束 | 总燃烧时间 |
|---|---|---|---|
| 参考文件 | `HP=9, KR=min(10,8)=8` | `HP=1, KR=0` | 约 8.0s |
| 当前 Lua | `HP=9, KR=10` | `HP=1, KR=0` | 约 5.0s |

当前 Lua 因为不夹 `HP-1`，低 HP 时 KR 会比参考多；又因为固定 0.5s，燃烧更快。两个偏差叠加后，实际感受与参考相差很大。

### 4.3 低 HP 被骨头命中：夹取差异

场景：`HP=3, KR=0`，被骨头命中一次。

| 实现 | 命中后 | 后续 |
|---|---|---|
| 参考文件 | `HP=2, KR=min(6,1)=1` | 1s 后 `HP=1, KR=0`；紫条先 1、黄条 1 |
| 当前 Lua | `HP=2, KR=6` | 0.5s 后 `HP=1, KR=5`；随后 KR 继续减到 0，HP 保持 1，约 3s 才结束 |

参考的“低血量紫条很短”不是 bug，而是 `KR <= HP-1` 夹取的自然结果。当前实现的 `hit hp=1 kr=6` 只是夹取前的中间值；如果按参考在命中后立刻夹取，日志/HUD 应直接显示 `kr=0`。

### 4.4 食物不会清 KR

场景：`HP=10, KR=9`（已接近当前 HP-1 上限），吃一个 +45 的食物。

| 实现 | 吃后 | 后续 |
|---|---|---|
| 参考文件 | `HP=55, KR=9` | KR 继续按 `KR<10` 档 1s/点燃烧；约 9s 后 `HP=46, KR=0` |
| 当前 Lua | `HP=55, KR=0` | 蓝血直接消失，玩家立即安全 |

这是本次用户明确指出的特性：**吃东西只回 HP，不会清空蓝血**。当前 Lua 与参考不一致，且这是 P0。

---

## 5. 建议的最小补丁顺序

1. **先删 item 清 KR**（P0-1）。这是用户明确指出的问题，改动面最小，且旧 JS 原型本来就是这么做的。
2. **加 `clampKR()` 并在 `hurt()`/`updateKR()` 调用**（P0-2）。先让低 HP 的状态正确，再接燃烧曲线，否则燃烧报表会被无夹取的 KR 干扰。
3. **替换 `KR_TICK` 为 `KR_TIERS` + `krStep()`，`updateKR` 改成单次结算**（P0-3）。
4. **按需补 `hurt(kind, karma, src)` 的 Karma 衰减**（P1）。
5. **最后同步回归与文档**。

建议的提交顺序也是这个顺序；每一步都可以单独跑 `core_selftest.lua`，避免一次性改太多导致定位困难。

---

## 6. 回归与测试计划

### 6.1 必须更新的旧断言

| 位置 | 旧断言/期望 | 新期望 |
|---|---|---|
| `core_selftest.lua:291` | `has(g, 'hit hp=1 kr=6')` | 若在 hurt 内夹取，改为 `hit hp=1 kr=0`；若只在 updateKR 夹取，改为下一帧断言 `kr=0` |
| `core_selftest.lua:293-294` | `kr_floor hp=1`、`kr_done hp=1 kr=0` | 保留；确保 `clampKR()` 会记录这两个日志 |
| `core_selftest.lua:460-469` | `kr_cleared by=beg` | 若保留 beg 清 KR，保留；若严格复刻 Spare，改为断言 `beg` 不清 KR |
| `core_selftest.lua:521-528` | `gk.kr <= 40`；HP 最终 >=1 | 再断言 `gk.kr <= math.max(0, gk.hp - 1)`；燃烧时间按档位断言 |
| `core_selftest.lua:544-562` | 只断言 `hp==55` | 增加 `kr` 不变的断言，再步进验证继续燃烧 |

### 6.2 新增用例建议

1. **items-do-not-clear-kr**
   - 构造 `hp=10, kr=9, krT=0, noSpawn=true`；
   - 打开 item 子面板并确认使用；
   - 断言 `hp==55, kr==9, krT==0`；
   - `step(g, 1.0)` 后断言 `hp==54, kr==8`（`KR=9 < 10`，1s 一跳）。

2. **kr-clamp-hp-minus-1**
   - `hp=10, kr=40` -> `clampKR`/`updateKR(0)` 后 `kr==9`；
   - `hp=3, kr=6` -> `kr==1`；
   - `hp=2, kr=6` -> `kr==0`；
   - `hp=1, kr=5` -> `kr==0`，且不产生 HP 变化。

3. **kr-tier-40**
   - `hp=92, kr=40, krT=0`；
   - 步进 2 帧（约 0.0333s）后：`kr==39, hp==91`；
   - 再步进 2 帧：`krT < 0.066`，不结算；
   - 再步进 2 帧（累计 4 帧）：`kr==38, hp==90`。

4. **kr-tier-30 / 20 / 10 / low**
   - `kr=35`：0.066s 后结算；
   - `kr=25`：0.166s 后结算；
   - `kr=15`：0.5s 后结算；
   - `kr=9`：1.0s 后结算。

5. **kr-hp1-no-burn**
   - `hp=1, kr=5, krT=0`；
   - 调 `updateKR(dt)` 或步进 2s；
   - 断言 `hp==1, kr==0`，且没有 HP 变化。

6. **karma-decay（P1 时）**
   - 构造一个 `src={karma=6}` 的攻击对象；
   - 第一次 `hurt('hit', src.karma, src)`：KR +6，`src.karma==2`；
   - 第二次：KR 只 +2。

### 6.3 现有测试的注意事项

`core_selftest.lua` 的 `step(g, seconds)` 使用 `DT = 1/60`（`core.lua:117`），因此：

- `0.033` 档会在第 2 帧（0.0333s）达到；
- `0.066` 档会在第 4 帧（0.0667s）达到；
- `0.166` 档会在第 10 帧（0.1667s）达到；
- `0.5` 档正好 30 帧；
- `1.0` 档正好 60 帧。

不要用 `step(g, 1.0)` 一次性验证 0.033 档的“只跳一次”，因为当前新实现是单次结算，跳一次后 `KR_T` 归零，剩余的 dt 会被丢弃；这正是参考的逐帧语义。要验证档位，按帧分段步进。

---

## 7. 文档同步清单

修改代码后，以下文档中的旧口径必须同步，否则后续会再次误导实现：

| 文件 | 行 | 旧口径 | 新口径 |
|---|---|---|---|
| `README.md` | 106 | “治疗道具清 KR” | “治疗道具只回 HP，不清 KR；KR 在攻击条阶段继续燃烧” |
| `README.md` | 111 | “KR 增量原来按 hp-1 截断……改成每次命中都加满 KR” | 改为“参考文件用 `KR <= 当前HP-1` 夹取；低血量紫条短是参考行为；若保留当前差异需标注为有意偏离” |
| `docs/bts-study.md` | 413 | “速率 0.5s/点……原作逐帧曲线仓库里没有，维持现状” | 改为五档曲线表，并注明本次已实现 |
| `docs/bts-study.md` | 414 | “传奇面包 +45（并清 KR）” | “传奇面包 +45（不清 KR）” |
| `records/status-and-handoff.md` | 577 | “治疗道具清空 KR” | “治疗道具只加 HP，不清 KR” |
| `records/status-and-handoff.md` | 510、524 | “低血量受击判定消失……每次命中都加满 KR” | 说明参考实际是 `KR <= HP-1`；当前改动是与参考的偏离 |
| `records/playtest.md` | 93 | “KR 上限用命中后 HP 计算 → HP=2 时 KR 恒为 0；改为命中前 HP-1” | 这条方向反了；参考是命中后 HP-1 |
| `records/playtest.md` | 95 | “每 0.5s 整数结算 1 点” | 改为按 KR 档位 0.033/0.066/0.166/0.5/1.0 |
| `docs/original-research.md` | 17、67-68 | “一直掉到 HP=1 就停（效果还在也不再往下掉）” | 明确 BTS 参考是 `KR=HP-1`，HP=1 时 KR=0、紫条消失 |
| `records/lua-port.md` | 220 | “每 0.5s 扣 1 等都与上限无关” | 改为“按档位燃烧；上限为 min(40, HP-1)” |
| `docs/gdd.md` | 141 | “求饶=清空 KR” | 若保留，标为“本作自定义”；不要写成原作机制 |

---

## 8. 风险与决策点

1. **低 HP 手感**
   - 恢复 `KR <= HP-1` 后，低 HP 时紫条会明显变短，甚至 HP=1 时直接消失；
   - 这符合参考文件，但会推翻之前“低血量受击判定消失”的修复方向；
   - 建议以参考为准；若保留当前手感，必须在 README 和回归注释中写明是“有意偏离”。

2. **单次结算 vs 补帧**
   - 参考是“每帧最多结算一次，`KR_T` 清零”；
   - 如果改用 `while` 补帧，在高帧率下总时间接近，但在低帧率/卡顿时会与参考不一致；
   - 本项目的自测固定 1/60，因此单次结算最贴近参考。

3. **Karma 衰减的改动面**
   - 需要给骨头/龙骨炮加 `karma` 字段，并修改 `hurt()` 签名；
   - 如果不做，高密度弹幕会比参考更惩罚；建议至少先记录为已知差异，不要默认已经 1:1。

4. **难度档的 invuln**
   - 参考只有 0.033s；当前 easy/normal/hard 是玩法设计；
   - 如果用户要求“全难度复刻”，再统一改成 0.033；否则保留，并在文档里区分“参考一致”与“难度放宽”。

5. **求饶清 KR**
   - 参考 Spare 不清 KR；当前 beg 是自定义；
   - 保留与否是设计决策，不是数值 bug；建议保留时改名/改文案，避免被理解为原作机制。

---

## 9. 参考证据索引

| 内容 | 可读导出 | 原始 XML |
|---|---|---|
| `DamagePlayer`：HP-1、KR+Karma、LastDamageTime | `_analysis/Battle.xml.txt:1459-1469` | `Event sheets/Battle.xml:7775-7801` |
| 0.033s 命中冷却 | `_analysis/Battle.xml.txt:1482` | `Event sheets/Battle.xml:7873-7879` |
| Karma 首次后降为 2 | `_analysis/Battle.xml.txt:1488-1520` | `Event sheets/Battle.xml:7903-8122` |
| KR 上限 40、`KR <= HP-1` | `_analysis/Battle.xml.txt:1521-1524` | `Event sheets/Battle.xml:8130-8159` |
| KR 五档燃烧 | `_analysis/Battle.xml.txt:1525-1551` | `Event sheets/Battle.xml:8160-8315` |
| 道具只加 HP | `_analysis/Battle.xml.txt:471-492` | `Event sheets/Battle.xml:2426-2517` |
| 道具表数值 | — | `Event sheets/Items.xml:15-27` |
| Spare 不清 KR | `_analysis/Battle.xml.txt:499-504` | `Event sheets/Battle.xml:2545-2566` |
| HUD 黄/紫分段 | `_analysis/Battle.xml.txt:1590-1594` | `Event sheets/Battle.xml:8487-8505` |
| Karma 对象族 | — | `Bad Time Simulator (Sans Fight).caproj:1038-1056`、`1017-1026` |

---

## 10. 最终建议

如果只做一件事：**删掉 `core.lua:1882` 的 item 清 KR**。

如果做完整对齐：按 **P0-1 → P0-2 → P0-3 → P1** 的顺序修改，并同步本文件 §6、§7 的测试和文档。完成后，蓝血的行为应该是：

1. 命中先扣 HP，再加 Karma；
2. 立即把 KR 夹到 `min(40, 当前HP - 1)`；
3. 只要 `KR > 0` 且 `HP > 1`，就按当前 KR 档位逐点燃烧；
4. 治疗只回 HP，KR 和 KR_T 不变；
5. HP=1 时 KR 必为 0，不再有紫色余量。