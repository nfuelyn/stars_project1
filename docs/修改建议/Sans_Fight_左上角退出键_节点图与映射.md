# 左上角「退出」图标：客户端行为 + 服务端节点图

- **用户口径（2026-10-17）**：千星游玩时自带的那个退出键点不到；要**进入关卡 1 分钟后**在**同一位置**出现一个图标，点击**直接退出**；手机端与电脑端都要。
- **工作区**：`D:\stars\workspace\sans-fight`
- **结论**：客户端 Lua **没有**「退出关卡」API（`D:\miliastra-beyond-simulator` 全库检索 `ExitLevel/QuitLevel/结算关卡` 均无客户端入口）。
  所以图标点击只能**发服务端信号**，由节点图「结算关卡」真正退出。

---

## 一、为什么原生退出键点不到

本项目为了收指针事件，铺了一层**全屏 `cursorArea`**（光标检测区域），并在 `M.OnStart` 里把根容器设成：

```lua
root.disableKeyEventPassthrough = true
root.disableCursorEventPassthrough = true
root.showCursor = true
```

⇒ 按键/光标事件**留在 UI 层**（脚本的子控件监听才收得到），同时也把千星原生的退出键盖住/抢走了点按。
这就是"原生退出键没了"的根因（不是新引入的，是移植期就有的取舍）。

## 二、客户端行为（已实现）

| 项 | 值 |
|---|---|
| 出现时机 | 进入关卡（`OnStart` 之后）累计 **60 秒** |
| 位置 | 世界坐标 `(8, 8)`、边长 `34`（640×480，左上角原点、Y 向下）→ 与原生退出键同角 |
| 外观 | 半透明黑底 + 白色圆环 + 白色 × |
| 点击 | 手机（触摸点按）与电脑（鼠标点击）**同一条点按链路**；触摸额外给 10px 容差 |
| 动作 | 发服务端信号 **`SansFightExit`**（无参数） |

### 配置（`lua/config.lua`）

```lua
C.exitIcon = true                 -- false = 完全不显示
C.exitDelay = 60                  -- 多少秒后出现
C.exitIconX, C.exitIconY = 8, 8   -- 世界坐标，对齐原生退出键
C.exitIconSize = 34
C.exitSignal = 'SansFightExit'    -- 服务端信号名
```

> 位置如果和原生键差几像素：直接改 `C.exitIconX / C.exitIconY / C.exitIconSize`（世界像素 = 画布像素 / S）。

## 三、服务端节点图（**必须加，否则点了不会退出**）

```text
[客户端 Lua：左上角退出图标]
        │  game.ServerSignal("SansFightExit")
        ▼
[服务端：收到服务器信号  SansFightExit]
        │
        ▼
[结算关卡]        ← 官方「关卡结算」节点；执行后关卡结束
```

要点：

1. **信号名必须是 `SansFightExit`**（或在 `C.exitSignal` 里改成同名）。
2. 这个信号**不带参数**（不是结算结果，只是"我要走了"）。
3. `[结算关卡]` 放最后；如果前面还要写展示数据，先写再结算。
4. **去重**：如果同一关卡里还有 `SansFightSettle` 的处理，两个信号互不冲突；
   但建议在 `SansFightExit` 分支里也读一个 `SansSettled` 之类的去重变量，避免重复结算。

### 备选：不想新增节点

把配置改成：

```lua
C.exitSignal = 'SansFightSettle'
```

就会走**现有的结算信号**（客户端会自动带上 `result=true / hp / kr / round`）。
代价：退出会被当成**胜利结算**，而不是"纯退出"。

## 四、回归

- `lua/probes/_probe_touch_tutorial.lua` 追加 2 条（**触摸端**、真实事件回调）：
  - 1 分钟前点左上角 → **不发**信号；
  - 快进 ~63 秒后点左上角 → 发出 **`SansFightExit`**（日志：`main: 已发送退出信号 SansFightExit`）。
- `verify-all --quick` → **14 / 14**（该探针 11 条）。

## 五、技术来源

| 内容 | 位置 |
|---|---|
| 客户端无退出 API（全库检索） | `D:\miliastra-beyond-simulator`（`ExitLevel/QuitLevel/结算关卡` 均无客户端项） |
| 穿透开关（原生退出键被盖的原因） | `lua/main.lua` `M.OnStart`（`disableKeyEventPassthrough` / `disableCursorEventPassthrough` / `showCursor`） |
| 图标绘制与点击判定 | `lua/main.lua` `G_REAL.drawExitIcon` / `handleClick` 开头 |
| 信号发送 | `lua/main.lua` `G_REAL.requestExitKick` |
| 现有结算信号（备选路径） | `lua/main.lua` `G_REAL.sendSettleSignal`；`docs/结算按钮_节点图与挂载映射.md` |