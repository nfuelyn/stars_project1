# Bad Time 战斗 · 千星客户端 Lua

本次审查后的导入文件是根目录 **main.lua**。它包含战斗核心、24 份参考攻击 CSV、CodeArt 配方、输入、音效和结算发送逻辑；正式工程只需为这个文件建立一个客户端脚本映射。

这是一份以 Bad Time Simulator 为参考的战斗改进版。见面杀、两阶段攻击、中场补给、饶恕陷阱、蓝魂、KR 和终盘攻击已接通。角色采用几何像素重绘；中文使用 CodeArt 矩形字形。原作的菜单骨头攻击和末尾睡眠后推框偷袭仍未实现，不应把本版称为逐项完整的一比一复刻。

- [沙箱与游戏编辑器部署方案](docs/部署与设置.md)：模板、脚本映射、操控、音效、服务器结算和真机验收。
- [项目交接与开发说明](docs/项目交接与开发说明.md)：完整架构、设计思路、新机器复现、已知缺口和可复制的 AI 接手说明。
- [审查与验证记录](docs/审查与验证.md)：问题、修改、测试和剩余差异。
- [CodeArt 说明](docs/CodeArt说明.md)：全部元素配方、图集与性能说明。
- [角色图集](docs/previews/codeart-characters.png)、[适配层开场预览](docs/previews/adapter-opening.png)：均为离线预览。

## 配置与重新打包

先编辑 `lua/config.lua`，填入当前工程的客户端**模板根节点索引**和音效资产 ID，然后在本目录运行：

```powershell
python tools/build.py
python tools/run_tests.py
```

模板索引默认保留原脚本工程的值，无法替新建工程自动生成。`images` 中的 0 表示沿用模板里的图元图片；`audio` 中的 0 表示静音。不要把外部模拟器的图元编号直接当作官方图片资产 ID。

可维护源码位于 `lua/`，根目录 `main.lua` 是生成文件，直接改它会在下次打包时被覆盖。原文件保存在 `reference/main.original.lua`，参考项目原数据在 `reference/upstream/`。

可选的离线视觉检查：

```powershell
python tools/preview_codeart.py
python tools/render_adapter_preview.py
```

工具使用 Lua 5.3 的 `lupa`，预览另需 Pillow。当前环境从父目录已有的运行库只读加载；迁移到其他机器时安装到项目自己的 Python 环境。仅 `build.py` 使用 Python 标准库即可运行。`extract_sources.py` 和两份迁移编辑脚本是审查过程记录，不是日常重建步骤。

所有修改与下载均保存在本工作目录内，父级知识库只作读取。尚未在官方沙箱或原神游戏窗口内运行验收；必须完成部署方案里的真机检查后再发布。

## 交接包

运行 `python tools/package_project.py` 生成 ZIP、根目录文件清单 `PACKAGE_MANIFEST.json` 和压缩包 SHA-256。包包含源码、生成脚本、全部文档/预览、测试、工具和参考快照；不包含 Python 环境、父级知识库或官方游戏工程存档。

给朋友或其 AI：先读交接文档和 `AGENTS.md`，修改 `lua/` 后构建，不要重跑一次性迁移工具。新机器的离线验证依赖见 `requirements-dev.txt`；已经生成的游戏脚本运行不需要 Python。
