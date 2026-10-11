# 战斗 BGM：用千星音效拟合播放（`lua/music.lua`）

> 引入版本：`2026-10-07-settle` 之后（构建说明见 `docs/device-setup.md`）
> 权威来源：`lua/music.lua`、`lua/main.lua`、`tools/build-save.mjs`

## 1. 为什么是「客户端音效拼旋律」

千星客户端 Lua 只有**音效**通道：`game.PlayAudio2D(audioId)`（返回句柄）、`StopAudio(handle)`、`IsAudioAlive(handle)`。
背景音乐库那条路（`modifyPlayerBackgroundMusic` / `startPausePlayerBackgroundMusic`）属于**服务端节点图**。

本作 BGM 走音效方案 → **不需要服务端节点图，也不需要新的挂载点**，只是原脚本多内联一个模块。

## 2. 播放语义（用户口径）

| 事件 | 行为 |
|---|---|
| 开战（标题页确认开局） | 从第 0 格开始播 |
| 整场战斗 | 播到最后一格自动回到第 0 格继续（无缝循环，不重置拍子相位） |
| 重开战斗（结局页「重开」，含确认键） | 停掉当前音，重新从第 0 格播 |
| 结算（结局页「结算」→ `SansFightSettle`） | 立即 `StopAudio`，之后不再触发 |

## 3. 接线方式

- **core**：`Game:start()` 里 `self.runSeq = (self.runSeq or 0) + 1`（开战与重开都走这里，core 不碰任何宿主 API）
- **适配层**：`main.lua` 的 `OnLevelUpdate` 里，`state.runSeq ~= lastRunSeq` → `music.start()`；每帧 `music.update(dt)`
- **结算**：`requestSettlement()` 里 `music.stop()`

## 4. 填音效 ID（唯一手工步骤）

`lua/music.lua` 顶部三段：

```lua
M.SFX = { ['F5'] = 0, ... }      -- 精确音名 → 音效资源 ID
M.SFX_PC = { ['C'] = 0, ... }    -- 音级兜底（12 个，推荐先只填这段）
M.FALLBACK = 0                   -- 全兜底
```

查找顺序：精确音名 → 同音级其它八度 → 音级兜底 → `M.FALLBACK`。
ID 为 `0` 的音直接跳过：不报错、不卡住，只是那一下听不见。

## 5. 谱面

自动扒谱 v1（来源 `music1.mp3`）：156.25 BPM / 4-4 / 八分音符网格 `M.STEP = 0.192s`，
共 743 格 ≈ 142.66s；原曲 158.57s，末尾收尾段未扒。
换谱只改 `M.STEP` 与 `M.SCORE` 两处（`M.SCORE` 是空格分隔的音名串，`-` 为休止）。

## 6. 已知限制 / 待真机验证

- 模拟器的 `PlayAudio2D` 只登记句柄、**不出声**（见 `dist/worker.js`）→ 音色、音量、是否串音只能在真机听。
- 同时发声数上限未知。当前实现：新音到达时 `StopAudio` 掉上一个；同音名连续超过 `M.RETRIG = 4` 格（≈0.77s）重触发一次（避免糊成一条长音）。
- 模拟器里 `PlayAudio2D` 的签名是 **1 个参数**（`audioId`）。真机若还支持音量/音高参数，音效库只需 1–2 个音色就能拼出整条旋律 —— 属于待探针项。

## 7. 验证证据

- 模块探针（fengari）：驱动 200s（超过谱长）→ 循环回绕不越界；`stop()` 后不再触发。
- 集成探针：标题页静音 → 开局起播 → 重开重播 → 结算停止且不再触发。
- `node tools/verify-all.mjs --quick`：8/8 通过（含 `_check` / `_rounds` / `core_selftest` / `_tap` / `_title` / `_input` / build-save / verify-client-pool）。
