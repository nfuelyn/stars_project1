# 左上角「退出」：位置提示图标 + 事件穿透（手机 / PC）

- **用户口径（2026-10-17）**：千星游玩时自带的那个退出键点不到。要的是**点那个位置能穿过 Lua 绘制的界面、触发原生按钮**；
  我们画的东西**只是位置提示**。
- **工作区**：`D:\stars\workspace\sans-fight`
- **结论**：不需要客户端发任何退出信号 —— 只要把**事件穿透**按文档打开、并让**光标检测区顶部让出一条带**，
  原生退出键就能收到点按。图标纯粹是给玩家指位置。

---

## 一、为什么原生退出键点不到（两个原因，都修了）

### ① 穿透开关被硬编码成 true（与文档相反）

`lua/main.lua` 的 `M.OnStart` 原来写死：

```lua
root.disableKeyEventPassthrough = true
root.disableCursorEventPassthrough = true
```

而本项目自己的 `docs/device-setup.md` 明确要求这两个字段是 **false**：

> `disableKeyEventPassthrough` | 默认 | **false** ← 开着收不到 WASD / 确认键
> `disableCursorEventPassthrough` | 默认 | **false**

脚本把编辑器的 `false` 覆盖成 `true` ⇒ 事件被扣在 UI 层 ⇒ 原生退出键收不到点按、按键也可能收不到。
**现在改成按配置下发，默认 false。**

### ② 全屏光标检测区把整个画面都吃掉了

`cursorArea` 是一块**铺满画布**的光标检测区域，它会接收并消费指针事件。
就算穿透打开了，只要光标区盖住左上角，原生按钮依然点不到。

**修复**：给光标区**顶部让出一条带**（世界像素 `C.cursorTopInset = 48`）。
这条带里没有光标区 → 点按继续往下传 → 落到原生退出键上。

> 为什么让"一条带"而不是"一个小方块"：光标检测区是**矩形**控件，打不出洞。
> 顶部这条带里没有任何可点元素（只有提示文字），让出来是安全的；可点 UI 全都在 y≈210 以下。

---

## 二、客户端行为

| 项 | 值 |
|---|---|
| 图标出现 | 进入关卡（OnStart 后）累计 **60 秒** |
| 位置 | 世界坐标 **(8, 8)**、边长 **34**（640×480，左上角原点、Y 向下） |
| 外观 | 半透明黑底 + 白圆环 + 白色 × |
| 作用 | **仅位置提示**，不拦截点按、不发信号 |
| 点击该位置 | 穿透到千星原生退出键（由千星自己处理退出） |

### 配置（`lua/config.lua`）

```lua
C.exitIcon = true                 -- false = 不显示提示图标
C.exitDelay = 60                  -- 多少秒后出现
C.exitIconX, C.exitIconY = 8, 8   -- 世界坐标：对齐原生退出键
C.exitIconSize = 34
C.exitIconClickSignal = false     -- ★ 默认 false = 只做提示；true = 兜底发服务端信号

C.blockKeyPassthrough = false     -- 必须 false（见 docs/device-setup.md）
C.blockCursorPassthrough = false  -- 必须 false
C.cursorTopInset = 48             -- 光标区顶部让出的世界像素；0 = 不让（旧行为）
```

**如果位置没对上**：调 `C.exitIconX / C.exitIconY / C.exitIconSize`（世界像素 = 画布像素 / S），
并同步调 `C.cursorTopInset`（要让出的带必须覆盖原生键）。

---

## 三、兜底方案（只在原生键仍然拿不到时用）

有些宿主版本可能不允许「穿透 + 子控件收事件」同时成立。这时把：

```lua
C.exitIconClickSignal = true
C.exitSignal = 'SansFightExit'     -- 或 'SansFightSettle'
```

点图标就会**自己发服务端信号**：

```text
[客户端 Lua：左上角图标]
      │ game.ServerSignal("SansFightExit")
      ▼
[服务端：收到服务器信号 SansFightExit]
      ▼
[结算关卡]        ← 执行后关卡结束
```

- `C.exitSignal = 'SansFightSettle'` 则复用**现有结算节点**（会自动带 result/hp/kr/round；代价：按胜利结算退出）。
- 这条路径**默认关闭**（因为用户要的是穿透原生键，不是自己发信号）。

---

## 四、回归

- `lua/probes/_probe_touch_tutorial.lua`（**触摸端**、真实事件回调）现在断言：
  1. `disableKeyEventPassthrough == false`、`disableCursorEventPassthrough == false`；
  2. 光标区 `anchorMaxY < 1`（顶部确实让出了 48 世界像素 → 0.9）；
  3. 1 分钟前图标不出现、之后出现；
  4. **点图标不发任何信号**（穿透交给原生键）。
- `lua/probes/_probe_sandbox_adapter.lua` 的两条断言从 `true` 改成 `false`（对齐 device-setup 文档）。
- `verify-all --quick` → **14 / 14**。

## 五、技术来源

| 内容 | 位置 |
|---|---|
| 穿透字段的正确取值（false） | `workspace/sans-fight/docs/device-setup.md`（"三个 false/true 必须逐项确认"那段） |
| 原实现硬编码 true | `lua/main.lua` `M.OnStart` 的 `disableKeyEventPassthrough / disableCursorEventPassthrough` |
| 光标区让位 | `lua/main.lua` `cursorArea = take('cursor')` 之后的 `C.cursorTopInset` 段 |
| 提示图标 | `lua/main.lua` `G_REAL.drawExitIcon`（`drawJoystick` 之后调用） |
| 兜底信号 | `lua/main.lua` `G_REAL.requestExitKick`（仅在 `C.exitIconClickSignal = true` 时挂钩） |
| 客户端无退出 API | `D:\miliastra-beyond-simulator` 全库检索 `ExitLevel/QuitLevel/结算关卡` 均无客户端项 |