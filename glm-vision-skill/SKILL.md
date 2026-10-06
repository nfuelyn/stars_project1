---
name: glm-vision
description: "Analyze images with Zhipu GLM vision (glm-4.6v-flash) - describe photos, OCR text, read screenshots/error messages, interpret charts and diagrams, compare multiple images. Use when the user asks what is in an image or points at an image path/URL with a question (Chinese triggers: 看图、识图、图片里是什么、识别图中文字、分析截图、图表、报错截图)."
---

# GLM 图像识别

用本机 `glm` MCP 服务器的 `glm_vision` 工具（底层 `glm-4.6v-flash`）分析图片。图片会上传到智谱 `open.bigmodel.cn` 接口，只处理用户明确指向的图片，不要主动扫描磁盘找图。

## 首选路径：调用 MCP 工具

1. 确认图片位置。用户给相对路径时，先按当前工作目录解析成绝对路径；先确认文件存在、扩展名是 png/jpg/jpeg/webp/gif、大小不超过 20MB。
2. 调用 `glm_vision`，参数为 `prompt` 和 `images`（绝对路径数组，也接受 http(s)/data URL）。多张图一次调用传完，不要拆成多次。
3. 把用户的问题原样放进 `prompt`，再补一句输出格式要求（见下）。需要模型名/token 用量时加 `include_meta: true`。

如果当前会话里找不到 `glm_vision` 工具（旧会话未加载或 MCP 未启用），按下文的命令行回退，不要凭记忆回答图片内容。

## 提示词写法

- 通用描述：`用中文描述这张图，先给结论，再列关键细节。`
- OCR / 文字提取：`逐字提取图中所有文字，保留原始换行和标点，不要翻译，不要总结。`
- 报错截图：`提取界面上的完整报错文本和堆栈，再说明出错的程序或页面是什么。`
- 图表 / 数据：`读出坐标轴、图例和可见数据点，给出你以为的结论，不确定的地方明确标注不确定。`
- 多图对比：`对每张图分别作答并编号，最后给出差异对比。`

## 回退路径（MCP 工具不可用时）

用 shell 调用同一个 MCP 的 CLI 模式：

```powershell
node D:\stars\glm-mcp\index.js --image "D:\path\a.png" --prompt "用中文描述这张图"
```

- 多图：重复传位置参数或 `--image`，例如 `--image a.png --image b.png`。
- 换模型：追加 `--model=glm-4.5v`。
- 诊断：`node D:\stars\glm-mcp\index.js --check`（连通性）、`--probe`（逐个模型状态）。
- 路径含空格时必须加引号。

## 已知约束

- 单图上限 20MB，支持 png/jpg/jpeg/webp/gif；heic、bmp、tiff 等需要先转成 png/jpg，工作区没有转换工具时直接告诉用户，不要硬传。
- `glm-4.6v-flash` 是免费模型，峰时可能返回 429 / 1305。服务器会自动重试并回退到 `glm-4v-flash`，结果里会带一行回退说明；把这个说明转达给用户，不要隐瞒模型已被替换。
- 工具报错时如实报告错误原文，不要根据文件名或常识猜测图片内容。
- 提取文字时保留原文语言；用户没要求翻译就不要翻译。

## 输出

直接给出分析结论，不要复述调用过程、参数或 MCP 协议细节。除非用户问起或结果质量受回退影响，不要提模型名和 token 用量。

