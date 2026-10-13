# Sans 的发言：按**原版仓库**全面替换 + 位置修正

- **原版来源**：`D:\c2-sans-fight-src`（`Event sheets/Battle.xml`、`Event sheets/RPGText.xml`、`Documentation/Sans.md`）
- **工作区**：`D:\stars\workspace\sans-fight`（`lua/core.lua`）
- **日期**：2026-10-13
- **你的口径**：①研究原版仓库内 Sans 的发言，**全面替换**；②给台词**找个合适的位置**（现在会和 Sans 重合）

---

## 1. 原版研究：Sans 在战斗里**只说两句**

原版的台词全部走 `SansText(Text, EndFunc)`（`Documentation/Sans.md` 的 `SansText`：Sans 的 speech bubble，建议只放短句），实现见 `RPGText.xml`（SpeechBubble + `SansSpeak` 音效）。

**战斗内（BTS 的 Sans 战）——只有 2 句**：

| 时机 | 原文 | 出处 |
|---|---|---|
| Sans 力竭（`SansHead Tired2` 之后，函数 `Win1`） | `"huff... puff..."` | `Event sheets/Battle.xml` **L1415-1417** |
| 紧接着（函数 `Win2`） | `"alright, i guess you win."` | `Event sheets/Battle.xml` **L1482-1484** |

**其余全部时机（第 1~N 回合开始、中场、螺旋档…）原版一个字都没有** —— Sans 全程沉默。

**另外 6 句是 BTS 自己的"无特效教程"**（只在浏览器不支持 WebGL / 特效不可用时播，不是战斗台词）：

| 函数 | 原文 | 出处 |
|---|---|---|
| NoEffects1 | `"so, uh, your browser doesn't seem to support webGL."` | L290 |
| NoEffects2 | `"thats kind of a problem."` | L383 |
| NoEffects3 | `"some effects aren't going to work."` | L401 |
| NoEffects4 | `"i had to make my speech bubble inverted just so you can see what i'm saying."` | L419 |
| NoEffects5 | `"most importantly, my blue attacks will look like normal attacks."` | L437 |
| NoEffects6 | `"continue if you dare."` | L455 |

**非台词的系统文本**（保留，不属于"发言"）：`Battle.xml` L99 `uppercase(Name) & "   LV 19"`（HUD）、`MainMenu.xml` L100 `"UPDATE AVAILABLE. PLEASE REFRESH THE PAGE."`（版本提示）。

---

## 2. 替换口径（已实施）

`lua/core.lua` 的 `LINES` 表重写成**原版口径**：

| 键 | 现在 | 说明 |
|---|---|---|
| `tired` | **`呼……呼……`** | = 原版 `"huff... puff..."`（L1416） |
| `win` | **`好吧。算你赢了。`** | = 原版 `"alright, i guess you win."`（L1483） |
| `surprise / r1..r6 / mid / late / spiral1..3 / final / midpoint / dodge / refuse / flee` | **空串（不说话）** | 原版对应时机**没有台词** |
| `extra = false` | 回退开关 | 旧口径的 18 条文本原样收在 `LINES.extraText` 里；把 `extra` 改 `true` 即可一键回到"每回合都说话" |

- **功能提示不算"发言"，照旧保留**：`（背包是空的）`、`再按一次确认重开　（结算 = 结束本局）` 等是 UI 文本（不在 `LINES` 里），不受影响；
- 触发点（core）：
  - **力竭**：`Game:update` 里盯 `world.sans.anim == 'Tired'`（只触发一次）→ `say(LINES.tired)`；
  - **赢了**：`Game:finish` 里 `outcome == 'spare' or 'kill'` → `say(LINES.win)`（`fail` 玩家阵亡时不说）。

---

## 3. 位置修正（已实施）

**问题**：原来台词固定在 `y = 86` 居中画（`renderWorld`），而 Sans 的头顶 y = `框顶 − 16 − SANS_H`（标准框 226 → **62**）⇒ 台词落在 Sans 身上 **62~86 区间**，必然重合。

**改法**（同一算式、跟着 Sans 走）：

```lua
if g.line and g.line ~= '' then
  local lineY = (boxAbs.y - 16 - SANS_H) - 30      -- Sans 头顶**上方 30px**（原版就是头顶的 SpeechBubble）
  if lineY < 2 then lineY = 2 end                   -- 贴到屏幕顶时兜底
  push(cmds, { kind = 'hudText', text = utf8sub(g.line, g.lineShown), x = VW / 2, y = lineY,
               size = 14, color = '#ffffff', align = 'center' })
end
```

- 顺带加了**空串守卫**：`line == ''` 时**不推文本**（省一个池位，也避免画一条空行）；
- 因为 y 由「框顶 − Sans 身高」推导，**框变形/大框回合**（Sans 会上下移动）台词都会跟着他走，不会出现"框一变就重合"。

---

## 4. 验收

```
_check / _rounds 75 / core_selftest 324 / _tap 42 / _title 33 / _input 241 /
_probe_sandbox_adapter 68 / build-save / verify-client-pool   结论：9 / 9 通过
sans-fight.save.json 已重建（925,781 字节）
```

| 手测 | 期望 |
|---|---|
| 第 1~5 回合、中场、螺旋三档开始 | **没有任何台词**（原版沉默） |
| `final` 力竭（`SansAnimation Tired`） | 出现「**呼……呼……**」，位置在 **Sans 头顶上方**，不压他 |
| 结局（饶恕/击倒） | 出现「**好吧。算你赢了。**」 |
| 想回退丰富台词 | 把 `lua/core.lua` 的 `LINES.extra` 改成 `true`，`build-save` 即可 |

---

## 附：原版台词原文（英文，便于对照）

```
huff... puff...                          -- Battle.xml L1416（Win1）
alright, i guess you win.                -- Battle.xml L1483（Win2，两行显示）
```
