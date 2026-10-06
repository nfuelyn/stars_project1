# glm-mcp

自建 MCP (stdio) 服务器，底层调用智谱开放平台 OpenAI 兼容接口，默认模型 **glm-4.6v-flash**（视觉多模态）。

- 零依赖：只用 Node.js 内置模块，不需要 npm install
- 两个工具：glm_chat（纯文本）、glm_vision（图像理解）
- 限流自愈：429 / 1305（模型访问量过大）等容量错误自动指数退避重试，仍失败则按备用模型链自动回退
- 支持本地图片路径 / http(s) / data URL，单图上限 20MB

## 1. 配置 API Key

在 https://open.bigmodel.cn/usercenter/apikeys 申请 Key，写入 D:\stars\glm-mcp\.env：

```
GLM_API_KEY=你的Key
```

## 2. 自检

```powershell
node D:\stars\glm-mcp\index.js --check     # 主模型（含重试与回退）
node D:\stars\glm-mcp\index.js --probe     # 逐个探测主模型与备用模型，打印状态表
node D:\stars\glm-mcp\index.js --ask "用一句话介绍你自己"
node D:\stars\glm-mcp\scripts\smoke.mjs    # 纯本地 MCP 协议冒烟测试，不联网
```

遇到 429 [1305] 该模型当前访问量过大，属于 glm-4.6v-flash 免费模型峰时容量限制，服务器会自动重试并回退，无需手工处理。想立即看各模型状态就跑 --probe。

## 3. 注册到 Codex（已完成）

配置位于 C:\Users\19637\.codex\config.toml：

```toml
[mcp_servers.glm]
command = "node"
args = ['D:\stars\glm-mcp\index.js']
```

常用命令：

```powershell
codex mcp get glm
codex mcp remove glm
```

服务器是 stdio 类型，Key 由同目录 .env 读取，不写进 Codex 配置。若 Codex 启动时找不到 node，把命令换成绝对路径重新添加：

```powershell
codex mcp add glm -- D:\harness\node.exe D:\stars\glm-mcp\index.js
```

修改代码或 .env 后需要新开 Codex 会话（或重启应用）让 MCP 重新加载。

## 4. 工具

### glm_chat

| 参数 | 类型 | 说明 |
| --- | --- | --- |
| prompt | string（必填） | 提示词 |
| system | string | 系统提示词 |
| model | string | 默认 glm-4.6v-flash，可换其他智谱模型 |
| temperature | number | 采样温度 |
| max_tokens | integer | 最大输出 token |
| thinking | boolean | 是否开启深度思考（模型支持时有效） |
| include_meta | boolean | 结果末尾附加模型名 / token 用量，默认 false |
| include_reasoning | boolean | 是否返回思考过程（reasoning_content），默认 false |

### glm_vision

与 glm_chat 相同，额外必填：

| 参数 | 类型 | 说明 |
| --- | --- | --- |
| images | string[]（必填） | 本地路径（如 D:\pics\a.png）或 http(s)/data URL，支持 png/jpg/jpeg/webp/gif |

在 Codex 里可以这样说：

- 用 glm_chat 把这段代码的注释改写成中文
- 用 glm_vision 看看 D:\pics\shot.png 里的报错是什么

思考过程（reasoning_content）默认不返回，需要时把 include_reasoning 设为 true。发生回退时会在返回文本末尾附一行说明，例如：（注：glm-4.6v-flash 当前繁忙或不可用，已自动回退到 glm-4.5-flash。）

## 5. 可选配置

| 环境变量 | 默认值 | 说明 |
| --- | --- | --- |
| GLM_API_KEY | 无（必填） | 智谱 API Key |
| GLM_MODEL | glm-4.6v-flash | 主模型 |
| GLM_FALLBACK_MODELS | glm-4.5-flash,glm-4-flash | 纯文本备用模型链（逗号分隔） |
| GLM_VISION_FALLBACK_MODELS | glm-4v-flash | 图像备用模型链（需支持视觉） |
| GLM_RETRIES | 2 | 单个模型的重试次数（2s / 4s 退避 + 抖动） |
| GLM_BASE_URL | https://open.bigmodel.cn/api/paas/v4 | 接口根地址 |
| GLM_API_URL | 由 GLM_BASE_URL 推导 | 直接覆盖完整 chat/completions 地址 |
| GLM_TIMEOUT_MS | 180000 | 单次请求超时 |
| GLM_MAX_TOKENS | 4096 | 默认最大输出 token |
| GLM_IMAGE_ROOT | 进程工作目录 | 相对图片路径的基准目录 |

自定义示例（想用更强的模型兜底）：

```
GLM_FALLBACK_MODELS=glm-4.6,glm-4.5-flash
GLM_VISION_FALLBACK_MODELS=glm-4.5v,glm-4v-flash
```

## 6. 卸载

```powershell
codex mcp remove glm
```

## 7. 命令行识图与 Codex Skill

不想经过 MCP 时可直接用命令行识图（与 glm_vision 同一套逻辑）：

```powershell
node D:\stars\glm-mcp\index.js --image "D:\pics\a.png" --prompt "用中文描述这张图"
node D:\stars\glm-mcp\index.js --image a.png --image b.png --prompt "对比这两张图"
```

配套 Codex Skill 已安装到 C:\Users\19637\.codex\skills\glm-vision，源码在 D:\stars\glm-vision-skill。当用户说“看图 / 识图 / 识别图中文字 / 分析截图”等，Codex 会自动走这个 skill：优先调 glm_vision MCP 工具，工具不可用时回退到上面的命令行。
