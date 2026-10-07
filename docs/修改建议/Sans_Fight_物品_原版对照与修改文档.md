# Sans 战「物品」部分：原版内容提取 + 修改文档（**保留你设定的传奇面包**）

- **原版来源**：`D:\c2-sans-fight-src`（`Event sheets/Items.xml`、`Event sheets/Battle.xml`、`Event sheets/Globals.xml`）
- **工作区**：`D:\stars\workspace\sans-fight`（`lua/core.lua`、`lua/main.lua`、`lua/core_selftest.lua`）
- **日期**：2026-10-07
- **口径**：**保留你设定的「传奇面包（+45 HP ×20）」**，在此基础上把原版注册的 4 件补进来（本文只给代码/建议，未改工作区）

---

## 0. 结论摘要

| 项 | 原版 | 工作区现状 | 建议 |
|---|---|---|---|
| 物品数量 | **4 件**（注册在 ItemDB） | **1 件**（全是传奇面包，用户设定） | **5 件 = 用户的面包 + 原版 4 件**（保留面包） |
| 回复量 | Pie 99 / Noodles 90 / Steak 60 / L.Hero 40 | 面包 +45 | 照抄原版 99/90/60/40；面包维持 **+45** |
| 数量 | 每格 1 件（用完 `Delete` 掉该格） | `count` 计数制（面包 ×20） | 面包保留 ×20；原版 4 件给 `count = 1` |
| HP 上限 | `HP > MaxHP → HP = MaxHP`（Battle.xml 8317-8330） | 加血时 `min(maxHP, hp+heal)` | 等价 ✓ 不动 |
| 使用后 | 文本播完 `EndFunc = StartAttack`（**消耗一个回合**） | `afterPlayerTurn()`（消耗回合） | 等价 ✓ 不动 |
| KR | **不碰 KR / KR_T** | 也不碰（注释已引用 Battle.xml） | 等价 ✓ 不动 |
| 菜单 | 每页 4 格（2×2）、显示**短名**、第 2 页在 x=640 外 | 单列列表、显示全名 + `xN` | 中文名不长 → 保持单列；**需 1 处行高下限修正**（见 §4.2） |

---

## 1. 原版「物品」部分原文提取

### 1.1 注册的物品表（`Event sheets/Items.xml` L6-29）

注释 L6 给出四个字段名：`ItemType, ItemMod, ItemName1, ItemName2`；L7-30 在开局注册 4 件：

```xml
<!-- L15  RegisterItem(0, 99, "Butterscotch Pie", "Pie")        -->
<!-- L19  RegisterItem(0, 90, "Instant Noodles",   "I.Noodles") -->
<!-- L23  RegisterItem(0, 60, "Face Steak",        "Steak")     -->
<!-- L27  RegisterItem(0, 40, "Legendary Hero",    "L. Hero")   -->
```

| 字段（0 基） | 含义 | 例 |
|---|---|---|
| `ItemType` | 0 = 可食用（回复类）※MenuUseItem 只处理 Type 0（Battle.xml L2462） | 全部是 0 |
| `ItemMod` | 回复量（HP） | 99 / 90 / 60 / 40 |
| `ItemName1` | 全名（用在"* You eat the X."） | Butterscotch Pie |
| `ItemName2` | 短名（用在菜单 "* X"） | Pie |

### 1.2 菜单里的物品（`Battle.xml` L2359-2422）

- 数据源是 `PlayerItems`（玩家的物品槽数组），**每页 4 格**（2 列 × 2 行）：
  - 第 0..3 格：`X = 64 + (loopindex%2)*256`、`Y = 272 + floor(loopindex/2)*32`（L2373-2379）
  - 第 4 格起：`X = 640 + 64 + (loopindex%2)*256`（**画到屏幕右侧外 = 翻页**，L2405-2411）
- 菜单文字用**短名**：`"* " & ItemDB.At(PlayerItems.At(i), 3)`（L2383 / L2415）
- 点击/确认回调名：`MenuUseItem`（L2387 / L2419）

### 1.3 使用物品（`Battle.xml` L2425-2516，函数 `MenuUseItem`）

```
① 关菜单 / 隐藏灵魂（L2432-2436）
② ItemSlot ← 菜单栈；ItemID ← PlayerItems[ItemSlot]（L2451-2456）
③ 仅当 ItemDB[ItemID].Type == 0（食物）才继续（L2462-2467）
④ HP += ItemDB[ItemID].Mod            （L2470-2473）
⑤ 播 PlayerHeal 音效                   （L2474-2479）
⑥ 显示两行文本：                       （L2493-2503）
     "* You eat the <全名>."
     "* You recovered <回复量> HP!"
⑦ 文本 EndFunc = "StartAttack"         （L2504-2511）→ 吃完**进入下一回合**
⑧ PlayerItems.Delete(ItemSlot)         （L2512-2515）→ **消耗该格**（数组前移，不留空格）
```

- **没有**任何 KR / KR_T 的操作（该函数里只有 ④ 一条加 HP）✓
- **没有**在菜单里做 HP 上限钳制 —— 上限在别处统一做：`Battle.xml` L8317-8330

### 1.4 HP 上限（`Battle.xml` L8317-8330 + `Globals.xml` L17-18）

```
L8319-8322  if HP > MaxHP      L8326-8328  HP = MaxHP
Globals:    HP = 92            MaxHP = 92
```

---

## 2. 工作区现状

### 2.1 物品表（`lua/core.lua:1422-1428`）—— **你的面包设定（保留）**

```lua
  -- 【2026-10-05 第九轮 · 用户口径】食物大量增加，**全部**是「传奇面包」，每口回复 45 HP。
  self.items = {
    { id = 'legend_bread', name = '传奇面包', desc = '回复 45 HP', heal = 45, count = 20 },
  }
```

### 2.2 使用逻辑（`lua/core.lua:1904-1912`）与原版逐条对照

| 原版 | 工作区 | 判定 |
|---|---|---|
| `HP += Mod` | `self.hp = math.min(self.maxHP, self.hp + it.heal)` | ✅ 等价（上限在加血时钳） |
| 播 PlayerHeal | （HUD/音效层，P1 未接） | ⚠ 可选 |
| 两行台词 "* You eat … / recovered N HP!" | 只记 log，无台词 | ⚠ 可选 |
| `EndFunc = StartAttack` | `self:afterPlayerTurn()` | ✅ 等价（消耗回合） |
| `Delete(ItemSlot)` | `it.count = it.count - 1` | ✅ 等价（计数制扩展） |
| 不碰 KR | 注释明确"只回复 HP；KR / KR_T 不变" | ✅ 等价 |

### 2.3 菜单（`core.lua:1820-1875`、`core.lua:3305-3324`、`main.lua:1122-1142`）

- 列表 = `itemList()`（只列 `count > 0`），行文字 = **全名**，右侧备注 = `x<count>`，底部 = `desc`；
- 面板在战斗框内，行高自动分配：`rowH = clamp(floor((面板高 − 58) / 行数), 24, 40)`（`core.lua:3316`）。

### 2.4 实测：**5 行会溢出 5px**（探针 `D:\stars\_analysis\probe_items_layout.lua`）

```
面板 y=234 h=149  rowH=24  行数=5  行底=388  面板底=383  溢出=5
说明行 y = 355
吃奶油糖派：hp 10 → 92（上限钳制正确）；剩余总数 23
```

→ 面板可用行区 `= 149 − 58 = 91px`，5 行需要 ≥18px/行，但当前**行高下限是 24** ⇒ 溢 5px，且和底部说明行重叠。

---

## 3. 差距对照表

| # | 差距 | 原版 | 工作区 | 处理 |
|---|---|---|---|---|
| G1 | 物品数量/种类 | 4 件（99/90/60/40） | 只有面包 | **补 4 件，保留面包** |
| G2 | 菜单容量 | 4/页 + 翻页（最多 8 格） | 单列、行高下限 24 | 改行高下限 18（5 行够用，§4.2） |
| G3 | 菜单用短名 | `ItemName2` | 全名 | 中文本就短 → 不改（可加 `short` 字段备用） |
| G4 | 吃完的两行台词 | 有 | 无 | 可选（P1） |
| G5 | 音效 PlayerHeal | 有 | 未接 | 可选（P1） |
| G6 | 自测断言 | —— | `core_selftest.lua:576-585` 断言"**所有**物品都是传奇面包且 +45" | **必须改**，否则补 4 件后 FAIL（§4.3） |
| G7 | GDD 文本 | —— | `docs/gdd.md:142` 还写着"雪镇薯条 x1（+8）/ 热猫 x1（+12）" | 顺手改成实际配置 |

---

## 4. 修改建议（**保留面包**）

### 4.1 物品表（`lua/core.lua:1422-1428` → 5 件）

```lua
  -- 【2026-10-07 用户口径】保留用户设定的「传奇面包（+45 ×20）」；
  --   并补上原版 Items.xml 注册的 4 件（回复量照抄原版：99 / 90 / 60 / 40）。
  --   原版字段对照：Type=0（食物）/ Mod=回复量 / Name1=全名 / Name2=短名。
  self.items = {
    { id = 'legend_bread', name = '传奇面包', short = '传奇面包', desc = '回复 45 HP', heal = 45, count = 20 },
    { id = 'pie',          name = '奶油糖派', short = 'Pie',       desc = '回复 99 HP', heal = 99, count = 1 },
    { id = 'noodles',      name = '速食泡面', short = 'I.Noodles', desc = '回复 90 HP', heal = 90, count = 1 },
    { id = 'steak',        name = '脸排',     short = 'Steak',     desc = '回复 60 HP', heal = 60, count = 1 },
    { id = 'lhero',        name = '传说英雄', short = 'L. Hero',   desc = '回复 40 HP', heal = 40, count = 1 },
  }
```

> 面包仍在**第一行**（现有自测"吃第一口 10 → 55"的期望不用动）。
> 原版是"每格 1 件"，这里 4 件给 `count = 1`（沿用本项目的计数制扩展）；需要备货就把 count 调大。

### 4.2 行高下限（让 5 行排得下）

`lua/core.lua:3316`：

```lua
-- 现在
local rowH = clamp(math.floor(rowSpace / math.max(1, #rows)), 24, 40)
-- 改为（91px / 5 行 = 18px，正好排进 165 高的框，不与底部说明行重叠）
local rowH = clamp(math.floor(rowSpace / math.max(1, #rows)), 18, 40)
```

`lua/main.lua:1135`（行文字号跟着行高走，避免 18px 行高时文字挤在一起）：

```lua
-- 现在
    text(r, x + 28, ry, w - 120, 18, sel and C_HP or C_WHITE, 'Left')
-- 改为
    local fs = math.min(18, math.max(12, (cmd.rowH or 26) - 2))
    text(r, x + 28, ry, w - 120, fs, sel and C_HP or C_WHITE, 'Left')
```

> 如果以后物品超过 **7 件**（91/7 = 13 < 18），就得按原版做"4 格/页 + 翻页"，届时另行处理。

### 4.3 自测断言必须同步（`lua/core_selftest.lua:576-585`）

现在这条断言会挡住"补 4 件"（它要求**所有**物品都叫传奇面包且 +45）：

```lua
  head('items：食物全部是「传奇面包」，每口回 45 HP 且数量很多')
  ...
    if it.name ~= '传奇面包' or it.heal ~= 45 then allBread45 = false end
```

建议替换为：

```lua
  head('items：传奇面包（用户设定 +45 ×20）+ 原版 4 件（99/90/60/40）')
  local gi = newGame({ seed = 5, noSpawn = true })
  local want = { legend_bread = 45, pie = 99, noodles = 90, steak = 60, lhero = 40 }
  local kinds, total, bad = 0, 0, {}
  for _, it in ipairs(gi.items or {}) do
    kinds = kinds + 1; total = total + (it.count or 0)
    if want[it.id] == nil or it.heal ~= want[it.id] then bad[#bad + 1] = tostring(it.id) end
  end
  ok(kinds == 5, 'items：共 5 种（用户面包 + 原版 4 件）')
  ok(#bad == 0, 'items：回复量与表一致（异常：' .. table.concat(bad, ',') .. '）')
  ok(gi.items[1].id == 'legend_bread' and gi.items[1].heal == 45 and gi.items[1].count == 20,
     'items：第一行仍是用户设定的传奇面包（+45 ×20）')
  ok(total >= 10, 'items：总量足够（合计 ' .. total .. ' 个）')
```

（L587-599 的"吃第一口 10 → 55 / 不清 KR / 中场消耗 1 个"三条**保持不动**，仍然成立。）

### 4.4 不需要改的（已与原版一致）

- HP 上限：`min(maxHP, hp + heal)`（等价于原版 L8317-8330 的全局钳制）✓
- 使用物品消耗一个回合（`afterPlayerTurn()` ↔ `EndFunc=StartAttack`）✓
- **不清 KR / KR_T**（原版 MenuUseItem 没有 KR 操作）✓
- 空背包提示 `item_empty`、`xN` 数量显示（本项目扩展）✓

---

## 5. 影响面

| 面 | 影响 |
|---|---|
| 中场（内部 11 / HUD 12）补给 | 多 4 件一次性道具可吃；`item_used` 日志/回合消耗逻辑不变 |
| `itemCount` / `itemList` / `subRowNote` | 自动适配（按 count>0 列项）→ 只多 4 行 |
| 自测 | §4.3 那条必须改；`_input`/`_tap` 里关于**主菜单 4 个按钮**的断言不受影响（那是按钮不是物品） |
| 存档（`sans-fight.save.json`） | 会随 `core.lua` 重建变化 |
| 面包 | **数值/名称/数量完全不动**（+45 / ×20 / 第一行） |

---

## 6. 验收（改完执行）

```powershell
cd D:\stars\workspace\sans-fight
node tools/build-save.mjs            # 只改 core/main：不要跑 gen-attacks
node tools/run-lua.mjs lua/core_selftest.lua   # 期望 PASS（含 §4.3 新断言）
node tools/run-lua.mjs lua/_input.lua
node tools/verify-all.mjs --quick
```

| 手测 | 期望 |
|---|---|
| 打开「道具」 | 5 行：传奇面包 x20 / 奶油糖派 x1 / 速食泡面 x1 / 脸排 x1 / 传说英雄 x1，全部排进框内、不与底部说明重叠 |
| 吃传奇面包（HP 10） | HP → 55，面包 20 → 19 |
| 吃奶油糖派（HP 10） | HP → 92（上限钳制），奶油糖派消失（0 件后不再列出） |
| 带 KR 时吃任何一件 | **KR / KR_T 不变**（继续按档位燃烧） |
| 用完后 | 进入下一回合（消耗一个回合） |

---

## 附录：行号索引

| 内容 | 位置 |
|---|---|
| 原版物品注册（4 件 + 字段注释） | `D:\c2-sans-fight-src\Event sheets\Items.xml` L6-29 |
| 原版物品菜单（4/页、短名、翻页） | 同仓库 `Event sheets\Battle.xml` L2359-2422 |
| 原版使用物品 `MenuUseItem` | `Battle.xml` L2425-2516（HP 加算 L2470-2473、台词 L2493-2503、StartAttack L2504-2511、Delete L2512-2515） |
| 原版 HP 上限 | `Battle.xml` L8317-8330；`Globals.xml` L17-18（HP=MaxHP=92） |
| 工作区物品表（面包，保留） | `D:\stars\workspace\sans-fight\lua\core.lua` L1422-1428 |
| 工作区使用逻辑 | `lua/core.lua` L1904-1912 |
| 工作区菜单数据/渲染 | `lua/core.lua` L1820-1875、L3305-3324；`lua/main.lua` L1122-1142 |
| 需要改的自测 | `lua/core_selftest.lua` L576-585 |
| 需要顺带更新的 GDD 文本 | `docs/gdd.md` L142 |
| 本文实测探针 | `D:\stars\_analysis\probe_items_layout.lua` |

*本文只做"原版内容提取 + 修改建议"，**未修改工作区任何文件**；§2.4 的布局实测来自内存里改写 `items` 表的真实 `Game.render` 输出。*

---

## 7. 实施记录（2026-10-07 已落地）

| # | 文件 / 位置 | 改动 | 状态 |
|---|---|---|---|
| 1 | `lua/core.lua:1425-1434`（`resetRun` 的物品表） | 5 件：**传奇面包 +45 ×20（第一行，用户设定保留）** + 奶油糖派 +99 / 速食泡面 +90 / 脸排 +60 / 传说英雄 +40（各 ×1），并加 `short` 字段（原版 ItemName2） | ✅ |
| 2 | `lua/core.lua:3322` | `rowH` 下限 `24 → 18`（165 高框里 5 行物品正好排下） | ✅ |
| 3 | `lua/main.lua:1136-1137` | 行文字号跟随行高：`fs = min(18, max(12, rowH-2))` | ✅ |
| 4 | `lua/core_selftest.lua:576-591` | `items` 断言改为"共 5 种 + 回复量 45/99/90/60/40 + **第一行仍是面包 (+45 ×20)**"（原"全部是面包"的断言会挡住这次改动） | ✅ |
| 5 | `docs/gdd.md:142` | 道具行文本由"雪镇薯条/热猫"更新为实际配置 | ✅ |

**未改**：使用逻辑（`core.lua:1904-1912`）—— 加血钳上限、消耗 1 个、消耗一个回合、**不清 KR / KR_T**，与原版 `MenuUseItem` 逐条等价；面包数值 `+45`、数量 `20`、位置（第一行）一律不动。

**验收**

```
布局探针 probe_items_layout.lua：
  面板 y=234 h=149  rowH=18  行数=5  行底=358  面板底=383  溢出=0
  吃奶油糖派：hp 10 → 92（上限钳制）；剩余总数 23
core_selftest        315 PASS / 0 FAIL（items 组 4 条新断言全过）
_rounds               76 PASS / 0 FAIL
_input               241 PASS / 0 FAIL
verify-all --quick     8 / 8 通过；sans-fight.save.json 已重建（519,850 字节）
```

> 只改了 `core.lua` / `main.lua` / `core_selftest.lua` / `gdd.md`（**没有 CSV 改动，所以没有跑 `gen-attacks.mjs`**，避免覆盖 `lua/attacks.lua`）。
