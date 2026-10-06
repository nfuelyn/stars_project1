# -*- coding: utf-8 -*-
import io
# prefab-pool.md
p=r"D:\stars\workspace\sans-fight\docs\prefab-pool.md"
s=io.open(p,encoding="utf8").read()
s=s.replace("## 2. 本项目的模板池（由 `tools/build-save.mjs` 生成，共 7 个）",
            "## 2. 本项目的模板池（由 `tools/build-save.mjs` 生成，共 10 个）",1)
s=s.replace("""| 1073743009 | 全屏光标区 | cursor | — | **(0,0)-(1,1) 拉伸铺满**：唯一的输入接收面，适配层从不写它的尺寸/位置 |""",
"""| 1073743009 | 全屏光标区 | cursor | — | **(0,0)-(1,1) 拉伸铺满**：唯一的输入接收面，适配层从不写它的尺寸/位置 |
| 1073743100 | 烘焙容器·左下 | container | — | 左下 (0,0)：exact 逐像素素材（Sans 身体/头）的容器模板 |
| 1073743101 | 烘焙容器·中心 | container | — | 中心 (0.5,0.5)：exact 龙骨炮的容器模板（绕中心旋转） |
| 1073743102 | 烘焙容器根 | container | — | **(0,0)-(1,1) 拉伸铺满**：所有烘焙容器的父级；OnStart 里在 prewarm 之前创建 → 烘焙层在黑底之上、池控件之下 |""",1)
io.open(p,"w",encoding="utf8",newline="").write(s)
print("patched prefab-pool.md")

# sprite-fit.md: append implementation status
q=r"D:\stars\workspace\sans-fight\docs\sprite-fit.md"
t=io.open(q,encoding="utf8").read()
add='''

## 6. 本轮已实现（2026-10-06）

**烘焙范围（按用户删减后的口径）**

- 龙骨炮：`Default` + 3 个开火帧（`Fire/000`、`Fire/002`、`Fire/004`）；运行期按 `cmd.fire`（0→1）
  映射到 3 帧。
- Sans 身体：默认站姿（`HandRight/000`）+ 4 套姿势各一帧（`HandUp/004`、`HandDown/003`、
  `HandLeft/000`、`HandRight/004`）。
- Sans 头：只保留 `Default` 与审判眼 `BlueEye`；其余表情回退到 `Default`。
- 流汗：保留原来的参数化圆点（4px 圆×0..3），不烘焙 32×9 的 SansSweat。
- 骨头：仍用参数化 5 图元（1 rect + 4 circle），见 §2.1。

**实现方式**

- `tools/build-save.mjs` 新增 3 个容器模板（§2 的 1073743100/101/102），并把 `lua/fitdata.lua`
  作为模块内联进挂载脚本（存档 351 KB → 477 KB）。
- `lua/main.lua` 在 `OnStart` 里创建 `bakedRoot`（prewarm 之前 → 层序在黑底之上、池控件之下），
  首次绘制某个素材时惰性 `bakeSprite`：容器下实例化 exact 矩形子控件，子控件用**比例锚点**
  （`anchorMin/Max = 矩形占比`、`sizeDelta=0`），因此运行期只 `SetSizeDelta` 容器即可整体缩放。
- 逐帧成本：每个可见烘焙素材 = 1 次容器显隐/位置/尺寸写入（惰性创建只在首次）。
- 缩放：`SANS_BAKE_SCALE = 1.6`（Sans，等比，脚底锚定在 `cmd.y + 148`）；龙骨炮 57×44 × `sc`。
- 回退：`fitdata` 缺失或离线单测里被 stub 成空表时，`drawBlaster`/`drawSans` 自动走原来的参数化外观。

**验证**

- `tools/verify-client-pool.mjs`：PASS（10 项契约全部满足）。
- `tools/verify-all.mjs --quick`：6/6 通过（离线单测固定走参数化回退）。
- 另外用 `_tap` 的 mock 引擎 + 真实 fitdata 跑了一遍烘焙路径：7 个容器创建成功
  （default 295 / head 177 / down 299 / blue 181 / up 309 / right 284 / blaster 320 个矩形），
  tap 21/21、PC 输入 40/40，无 `draw ERR`。

**真机待验证（重要）**

- `SetAnchorMin` / `SetAnchorMax`（子控件比例锚点）与容器 `SetSizeDelta` 的跨平台行为；
  模拟器源码支持，真机需按 `docs/device-setup.md` 的挂载流程核验。
- 惰性烘焙的首次实例化耗时（单个容器 177–320 个子控件）；若真机首帧卡顿，可改为关卡加载期预烘焙。
- 版权口径：exact 拟合高度接近参考图，`docs/gdd.md` §7「美术用自绘几何体」的口径需要复核。
'''
t=t.rstrip()+"\n"+add
io.open(q,"w",encoding="utf8",newline="").write(t)
print("patched sprite-fit.md")
