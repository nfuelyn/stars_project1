# Sans Fight · 结算信号与节点图（官方文档总结）

> 生成：2026-10-09 ｜ 工程：`D:\stars\workspace\sans-fight`
> 结论先说：**客户端 Lua 没有"退出奇域"的 API**，所以「结算 + 退出」必须由**服务端节点图**完成；
> 客户端只负责：结局页按「结 算」→ 发一条服务端信号 `SansFightSettle`（带 4 个参数）→ 显示「胜 利 结 算」。

---

## 一、客户端发出的信号（规格，照抄即可）

`lua/main.lua` 的 `requestSettlement()`：

```lua
local sig = game.ServerSignal('SansFightSettle')
sig:AddString('result', tostring(state.result or 'victory'))  -- 'victory' / 'spare' / 'kill' / 'fail'
sig:AddInt('hp',    math.floor(state.hp or 0))                -- 结算时的 HP
sig:AddInt('kr',    math.floor(state.kr or 0))                -- 结算时的 KR
sig:AddInt('round', math.floor((state.round or 0) + 1))       -- HUD 口径的回合，1..24
sig:SendSignal()
```

| 参数 | 类型 | 取值 / 含义 |
|---|---|---|
| `result` | **String** | 玩家主动结算 = `'victory'`；未主动结算时可能是 `'kill'`（击倒）/`'spare'`（饶恕）/`'fail'`（失败） |
| `hp` | **Int** | 结算那一刻的 HP（0..92） |
| `kr` | **Int** | 结算那一刻的 KR（0..hp） |
| `round` | **Int** | 当前回合（HUD 显示的 `ROUND x / 24`，1..24） |

**触发时机**：结局页默认选中「重 开」，按 ←（或点左侧按钮）切到「结 算」→ 确认 →
`core.settle()` 把 `result` 置为 `'victory'` 并置 `settleRequested`，随后每一帧由 `requestSettlement()` 发一次信号（发完立即清除标志）。

> 想加条件（例如"打满 1 分钟才能结算"）**不要改 main** —— 见 §三，在节点图/关卡变量里做。

---

## 二、官方文档里这张节点图怎么画

依据官方教程的四个页面（信号配置 / 执行节点 / 查询节点 / 关卡结算）：

- 信号配置：https://act.mihoyo.com/ys/ugc/tutorial/detail/mhlaj0r9bldi
- 执行节点：https://act.mihoyo.com/ys/ugc/tutorial/detail/mh66orrrfkm
- 查询节点：https://act.mihoyo.com/ys/ugc/tutorial/detail/mh65asiyhv2k
- 关卡结算：https://act.mihoyo.com/ys/ugc/tutorial/detail/mhx1du08nhwo

### 2.1 先在「信号配置」里声明信号

| 项 | 填什么 |
|---|---|
| 信号名 | `SansFightSettle`（**必须与 Lua 里的字符串完全一致**） |
| 参数 1 | `result` — String |
| 参数 2 | `hp` — Int |
| 参数 3 | `kr` — Int |
| 参数 4 | `round` — Int |

⚠ 参数**名字与类型必须和 `AddString/AddInt` 一一对应**；类型不匹配时节点图里读到的会是默认值（0/空串），这是最常见的"信号收到了但数据不对"。

### 2.2 服务端节点图（照这个顺序连）

```text
[收到服务器信号]  信号名 = SansFightSettle
        │  （读取 4 个参数：result / hp / kr / round）
        ▼
[查询变量]  SansSettled（布尔，关卡开始时初始化为 false）
        │
        ├─ 已为 true ────────────────────────────────► [结束]（去重：同一次只结算一次）
        │
        ▼ false
[设置变量]  SansSettled = true
        │
        ▼
[分支] result == "victory" 或 "spare" ？     ←【执行节点的比较/分支】
        ├─ 是 → [设置玩家结算状态 = 胜利 / 通关成功]
        └─ 否 → [设置玩家结算状态 = 失败]
        │
        ▼
[设置结算展示数据]（最多三条，例如：用时 / HP / 回合）
        │  ★ 必须"先设置展示数据与胜负"，最后再结算
        ▼
[结算关卡]   ← 官方"关卡结算"节点；执行后整个关卡结束
```

要点（官方文档 + 踩坑）：

1. **玩家实体**要从「获取在场玩家实体列表」取（长度=1 时取唯一玩家），不要把「控制物件」或 3D 角色实体直接接到"玩家实体"引脚。
2. **信号是全局广播**：整个关卡里只保留**一处**监听 `SansFightSettle`，否则会重复结算。
3. **「结算关卡」放最后**：它一执行关卡就结束，前面没设置好的展示数据会丢。
4. 需要"失败也有结局"时，用同一个信号 + `result == "fail"` 分支即可（客户端失败时 `result='fail'`）。
5. 想记录排行榜/积分：`round` 与 `hp` 是 Int，可直接写入排行数值；`result` 是 String，可用作状态标签。

---

## 三、"打满 1 分钟才能结算" —— 放在节点图侧（不动 main）

按你的要求，这个门槛**不写进客户端脚本**。两种纯服务端做法，任选一种：

### 做法 1：关卡开始时起一个 60 秒计时（推荐）

```text
[关卡开始/玩家进入] ──► [设置变量] SettleReady = false
                    └─► [计时器 60 秒] ──► [设置变量] SettleReady = true
```

- `SettleReady` 建议放在 **Level（关卡级）自定义变量**上，客户端将来若要拿它控制按钮显示，可以读
  `game.GetGlobalCustomVariableValue('Level', 'SettleReady')`（要接的话跟我说，我再加进 main）。
- 也可以把 `SettleReady=true` 那一刻换成/附带一个 UI 提示节点（"现在可以结算了"）。

### 做法 2：收到信号时再判时间

```text
[收到服务器信号 SansFightSettle]
        ├─[查询变量] Level.SettleReady == true  → 走 §2.2 的结算流程
        └─ 否 → [设置变量] SettleTooEarly = true（或直接忽略）
```

优点：客户端永远显示「结 算」，是否真正结算由服务端说了算；缺点是玩家点了可能"没反应"，需要额外给提示。
**建议用做法 1**（按钮/提示在客户端就同步了）。

---

## 四、验收清单

| 端 | 看什么 |
|---|---|
| 客户端日志 | `main: 已发送结算信号 SansFightSettle`（未出现 = 信号没发出去：`game.ServerSignal` 不可用或被 core 拦下） |
| 客户端画面 | 结算后标题变「胜 利 结 算」 |
| 服务端节点图 | 收到信号后：`SansSettled` 置 true → 玩家胜负已设置 → 展示数据已写 → **最后**执行「结算关卡」 |
| 结果 | 玩家看到结算面板/回到大厅/退出奇域（取决于你接的等价节点） |

---

## 五、相关文件与代码位置

| 用途 | 位置 |
|---|---|
| 信号发送（4 个参数） | `lua/main.lua` → `requestSettlement()` |
| 结算请求入口 | `lua/core.lua` → `Game:settle()`（把 `result` 置 `victory`、`settleRequested = true`） |
| 结局页按钮 | `lua/core.lua` → render 的 `kind='menu'`（`{ '结 算', '重 开' }`，默认 index=1=重开） |
| 既有节点图说明 | `docs\结算按钮_节点图与挂载映射.md` |
| 官方教程 | 信号配置 mhlaj0r9bldi ／ 执行节点 mh66orrrfkm ／ 查询节点 mh65asiyhv2k ／ 关卡结算 mhx1du08nhwo |
