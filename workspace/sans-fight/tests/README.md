# tests/ —— 步骤 2 用例（draft）

- 格式：`qxqy-autotest` / `version: 1`，`events[] + asserts[]`，与技能的用例 schema 一致（见 `qxqy-game-studio/references/design-and-tests.md` §4）。
- **`asserts` 只用了两种已文档化的 kind**：`log`（`contains` + `source`）与 `tree`（`name` + `exists`）。所有需要数值断言的地方，都改成断言游戏自己打印的**稳定领域事件**（`hit hp=1 kr=4`、`kr_floor hp=1`、`round_clear round=1`…），避免依赖未文档化的 `control` / `lua` 断言的字段名。
- **`events` 是 draft**：`serverSet` 与 `pointer` 用的是 `qxqy_studio_play` 已文档化的参数形状；`step` / `click` 同源。步骤 5 首次跑通后，应用 `saveCase` 重新产出**权威**用例 JSON 再回填本目录——技能明确"不要自创 schema"，而权威 schema 只能由 `saveCase` 给出。
- **测试入口约定**：客户端脚本在 `boot` 阶段读取服务端自定义变量 `TestSeed` / `TestHP` / `TestStartRound`（未定义时用默认值）。这样随机弹幕与初始状态都可复现，且不需要往用例里塞长输入序列（design-and-tests.md 的 L1「可注入 seed/序列」）。
- 本轮只做了静态/schema 检查，**没有启动模拟器、没有 runCase**（步骤 1–4 的硬约束）。

## 用例与契约对照

| 文件 | 覆盖 CONTRACT | 关键 oracle |
|---|---|---|
| `boot.json` | C9 / C10 | `game_start` + `round_start round=1` + HUD/Box/Menu 控件存在 |
| `first-success.json` | C5 / C8 | `round_clear round=1` 且 `hp=20` |
| `first-fail.json` | C1 / C4 | `fail hp_zero` + 结算面板与重开按钮 |
| `restart.json` | C9 | `restart` → `game_start` → `round_start round=1` |
| `mobile-smoke.json` | 布局 | mobile-16-9 下最短成功路径 + 菜单可点 |
| `kr-floor.json` | C2 / C3 | `hit hp=1 kr=4` → `kr_floor hp=1` → `kr_done hp=1 kr=0`，无 fail |
| `blue-bone-still.json` | C6 | 静止 `blue_pass_clean`；移动后 `hit_blue` |

## ⚠ 坐标口径变更（2026-10-05）：`pointer` 事件的 y 是**左下原点、Y 向上**

试玩页把指针换算成画布坐标时用的是 `y = (rect.bottom - clientY) * H / rect.height`
（`dist/play-renderer.js` 的 `hv()`，见 `docs/plugin-keymap.md` §5），**从画布底边往上量**；
而世界是 640×480、Y 向下。所以用例里写坐标必须用：

```
x_canvas = OX + x_world * S
y_canvas = OY + (480 - y_world) * S          # ← 与旧写法（y_canvas = OY + y_world * S）相反
```

例（`mobile-16-9`：S=1.5、OX=160、OY=0）：菜单第 1 个按钮中心 = 世界 (140, 421) → 画布 **(370, 88.5)**；
标题页第 1 张难度卡中心 = 世界 (97, 230) → 画布 (305.5, 375)。

本目录里仍带**旧口径**坐标的用例（等重录时一并改）：

- `mobile-smoke.json`：`{"type":"click","x":280,"y":636}`（desc 里也写着 636）
- `blue-bone-still.json`：拖动 (640,300) → (720,300)

`tests/full-run.case.json` 已由 `tools/gen-full-run-case.mjs` 重新生成（新口径），
`boot/first-*/kr-floor/restart/menu-panels` 这六个用的是 `{"kind":"click","name":…}` 找控件名，
而那批控件名属于更早的探针脚本，重录前都不作数。

## 待补（P0 之后）

`edge-contact`、`input-spam`、`pause-resume`、`restart-twice`、`large-dt`，以及 `pc-16-9` / `pc-21-9` / `mobile-19.5-9` / `mobile-4-3` 四个画布的 smoke。
