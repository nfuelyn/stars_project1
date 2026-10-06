# 千星 2D+Lua 游戏 · 制作计划（PREFLIGHT）

- 项目根（会话工作区）：`D:\stars`
- 当前步骤：**PREFLIGHT 未完成**（被工具加载阻塞，尚未进入七步的第 1 步）
- 更新日期：2026-09-27
- 依据：`qxqy-game-studio` 技能（`dsh-plugin-beyond-simulator` 附带的 Agent 预设）与仓库 README 的七步工作流

## 1. 环境核查结果（已验证事实）

| 项 | 结果 | 证据 |
|---|---|---|
| 插件 `dsh-plugin-beyond-simulator` | 已安装 | `D:\my-dsh\profiles\web\node_modules\dsh-plugin-beyond-simulator`，目录 mtime 2026-09-27 17:10:29 |
| 插件 `dsh-plugin-miliastra-toolbox` | 已安装（知识库，已生效） | 同上 profile；本会话可用 `get_node_info` / `list_documents` / `get_document` / `rag_search` |
| profile 注册 | 两者都在 bundles 里 | `D:\my-dsh\profiles\web\package.json` → `dsh.profile.bundles` |
| patch 层 | 为空（正常） | `cordis.patch.yml` = `[]`；`cordis.yml` 为生成文件，注释说明"编辑 cordis.patch.yml，不要编辑此文件" |
| **模拟器工具 `qxqy_studio_*`** | **当前不可见** | 本会话工具表里没有；`http://127.0.0.1:3080/qxqy-simulator/play` 返回 404 |
| 根因 | **运行中的服务早于插件安装** | 监听 3080 的 node 进程 PID 30624 启动于 17:00:39，插件安装于 17:10:29（相差约 10 分钟） |

结论：配置本身没问题，**只差一次 `dsh web` 重启**把新 bundle 载入服务进程。

## 2. 待用户执行的动作

```sh
# 在 dsh web 所在终端按 Ctrl+C 停掉，然后重新启动
dsh web
```

重启后：

1. 打开 GUI（`http://127.0.0.1:3080`）；
2. **新建一个会话**（旧会话的工具表在创建时已固定，不会热加载）；
3. 新会话请选择「**千星 2D+Lua 游戏制作**」预设（`wonderland-lua-builder`），它带 `qxqy-game-studio` 技能与模拟器操作技能；
4. 打开「模拟器」标签，并为会话绑定项目工作区（本项目为 `D:\stars`）。

预期可见工具：`qxqy_studio_get`、`qxqy_studio_patch`、`qxqy_studio_play`、`qxqy_studio_play_screenshot`、`qxqy_studio_ui_screenshot`、`qxqy_studio_load`。

> 说明：重启会中断当前这个会话所在的服务进程，所以我没有自行重启；如果你希望我来做，说一声，我会把它作为受管后台任务启动并回报确切 URL。

## 3. 阻塞项（写 Lua 之前必须解决）

| 阻塞项 | 影响 | 解决方式 |
|---|---|---|
| 官方 2D Lua API 文档缺失 | 不能凭猜测写 `game.*` / 控件方法名；技能明确要求"没有文档时请用户补齐，不猜接口" | ① 用户提供官方 API 文档 / 示例工程（放进 `D:\stars` 即可）② 或安装/启用含 Lua 章节的知识库（当前 KB 按「客户端脚本 / 控件容器 / Lua」检索均为 0 篇） |
| 游戏选题未定 | 无法进入第 1 步策划案 | 用户给一句话玩法 + 目标平台（手机 / PC） |

已有的替代证据：`docs/api-simulator-derived.md`（从模拟器运行时提取的候选 API 名称，**非官方、无语义定义**，只能用于交叉核对，不能当作规格）。

## 4. 七步进度

```text
PREFLIGHT  ← 当前（环境已核查，等重启 + API 文档 + 选题）
  1 策划案          docs/gdd.md                     未开始
  2 TDD 测试用例    tests/*.json                    未开始
  3 HTML 效果展示   prototype/index.html            未开始
  4 美术参考与素材  docs/art-bible.md               未开始
  5 Lua 编码实现    workspace/<slug>/*.lua + 存档   未开始
  6 测试            用例 + 截图 + 多画布             未开始
  7 真机试玩与修复  records/playtest.md             未开始
```

步骤 1–4 不需要模拟器工具，只要选题确定即可开工；步骤 5 起必须有模拟器工具与 API 文档。

## 5. 目录约定（按技能规范）

```text
D:\stars\
├─ docs\gdd.md                  策划案（步骤 1）
├─ docs\production-plan.md      本文件：当前步骤 / 退出证据 / 阻塞项
├─ docs\art-bible.md            美术与素材（步骤 4）
├─ tests\*.json                 qxqy-autotest 用例（步骤 2，format=qxqy-autotest, version=1）
├─ prototype\index.html         HTML 效果展示（步骤 3，不是交付物）
├─ workspace\<slug>\<slug>.save.json   模拟器完整存档（步骤 5）
└─ records\playtest.md          html | simulator | device 三级试玩记录
```

## 6. 硬约束备忘（写代码前自查）

- 画布原点**左下、Y 向上**；HTML 原点左上、Y 向下，禁止直接搬 CSS 像素。
- 布局基准是**手机 16:9（`mobile-16-9`，1280×720）整屏完整可见**；PC 同设计板等比放大或留边，不裁掉手机可见内容；缩放容器不要再叠全屏不透明兄弟节点。
- 五个画布：`pc-16-9` 1600×900、`pc-21-9` 2100×900、`mobile-16-9` 1280×720、`mobile-19.5-9` 1560×720、`mobile-4-3` 1280×960。
- 服务端「客户端控件容器」**不能挂客户端脚本**，脚本挂在客户端控件/模板上。
- `imageId` 只有 `100001–100006` 在模拟器里能预览，其余显示缺失框——记 `targetId`，留真机核验。
- 存档文件名固定 `workspace/<slug>/<slug>.save.json`，文件头附近含 `"format": "qxqy-simulator-save"`。
- GIA **不保存脚本挂载关系**，交付说明必须单列挂载步骤。
- 模拟器绿灯 ≠ 真机通过；真机未跑时状态只能标"模拟器候选"。
