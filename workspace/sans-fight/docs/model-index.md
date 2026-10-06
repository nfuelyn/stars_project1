# 外观模型索引（Sans / 龙骨炮 / 骨头）

- 更新：2026-10-06
- 运行时数据：`lua/fitdata.lua`（由 `tools/fit-sprites.py` 生成）
- 原始素材：`reference/sprites/`
- 拟合报告：`reference/sprites/fit/REPORT.md`、`docs/sprite-fit.md`

## 1. 运行时模型（唯一生效的一套）

所有 Sans 本体 / 头部 / 龙骨炮都走 **exact 逐像素烘焙**：每个素材一个容器，容器下是
1px 粒度的矩形子控件；子控件用比例锚点，运行期只改容器位置/尺寸/旋转。

| 模型 key（fitdata） | 用途 | 源素材 | 帧尺寸 | 矩形数 | 备注 |
|---|---|---|---:|---:|---|
| `blaster_default` | 龙骨炮蓄力/待机 | `animations/GasterBlaster/Default/000.png` | 57×44 | 320 | 中心锚点，随 `deg` 旋转 |
| `blaster_fire_0` | 龙骨炮开火（起） | `animations/GasterBlaster/Fire/000.png` | 57×44 | 306 | `fire < 0.334` |
| `blaster_fire_2` | 龙骨炮开火（中） | `animations/GasterBlaster/Fire/002.png` | 57×44 | 316 | `0.334 ≤ fire < 0.667` |
| `blaster_fire_4` | 龙骨炮开火（满） | `animations/GasterBlaster/Fire/004.png` | 57×44 | 297 | `fire ≥ 0.667` |
| `sans_body_default` | Sans 默认站姿 | `animations/SansBody/HandRight/000.png` | 96×48 | 295 | 头偏移 (17,−24) |
| `sans_body_up` | 砸击向上 | `animations/SansBody/HandUp/004.png` | 64×70 | 309 | 头偏移 (14,−2) |
| `sans_body_down` | 砸击向下 | `animations/SansBody/HandDown/003.png` | 64×70 | 299 | 头偏移 (14,1) |
| `sans_body_left` | 砸击向左 | `animations/SansBody/HandLeft/000.png` | 96×48 | 284 | **水平镜像**，头偏移 (18,−24) |
| `sans_body_right` | 砸击向右 | `animations/SansBody/HandRight/004.png` | 96×48 | 284 | 头偏移 (18,−24) |
| `sans_head_default` | 默认头 | `animations/SansHead/Default/000.png` | 32×30 | 177 | 与身体按 C2 `Head` 点合成 |
| `sans_head_blue` | 审判眼 | `animations/SansHead/BlueEye/000.png` | 32×30 | 181 | 其余表情统一回退 Default |

非烘焙（仍由图元池逐帧绘制，属于当前正式实现）：

| 模型 | 实现 | 源素材 | 说明 |
|---|---|---|---|
| 骨头（骨刺/横竖骨/骨墙） | `drawBone()` 参数化 5 图元（1 rect + 4 circle） | `Textures/BoneV.png` 10×24 / `BoneH.png` 24×10 | `k = 0.6×短边`，两端各两颗骨球 |
| 光束 / 炮口亮块 | `drawBlaster()` 池内矩形 | `GasterBlast1/2/3.png` | 宽度 = 命中带宽度 |
| 汗滴 | 参数化圆点 ×0–3 | `Animations/SansSweat` | 本轮按用户要求只保留“流汗”观感，不烘焙素材 |
| 灵魂 / 平台 / 战斗框 / UI | 池内图元 | 各参考图 | 未在本轮范围内 |

## 2. 容器模板 guid（`tools/build-save.mjs`，共 10 个）

| guid | 名称 | 类型 | 用途 |
|---|---|---|---|
| 1073743001 | 矩形图元 | image 100001 | 骨头、UI、烘焙子控件、箭头 |
| 1073743002 | 圆形图元 | image 100002 | 骨球、汗滴、摇杆 |
| 1073743004 | 文本图元 | textbox | 所有文字 |
| 1073743006 | 圆环图元 | image 100006 | 虚拟摇杆 |
| 1073743007 | 旋转图元 | image 100001 中心锚点 | 光束、旋转件 |
| 1073743008 | 旋转三角图元 | image 100003 中心锚点 | 骨刺尖、箭头、心尖 |
| 1073743009 | 全屏光标区 | cursor | 指针输入 |
| 1073743100 | 烘焙容器·左下 | container | 烘焙 Sans 身体/头 |
| 1073743101 | 烘焙容器·中心 | container | 烘焙龙骨炮（绕中心旋转） |
| 1073743102 | 烘焙容器根 | container | 所有烘焙容器的父级 |

## 3. 已清除的错误老版模型（2026-10-06）

| 老版内容 | 位置（清理前） | 问题 | 处理 |
|---|---|---|---|
| 彩色块状参数化 Sans（外套/衬衫/裤/手臂/眼窝） | `lua/main.lua` `drawSans()` 尾部 | 与 exact 烘焙模型并存时会出现两套 Sans；头部定位靠手调 | **整段删除**，`fitdata` 缺失时不再回退 |
| 6 矩形参数化龙骨炮（后颅/吻部/眼窝/口腔/牙条） | `lua/main.lua` `drawBlaster()` else 分支 | 旧近似外形；曾被 `if false` 临时禁用 | **整段删除**，改回烘焙容器 + 多实例 |
| 旧骨头“两颗重合大圆”胶囊帽 | `lua/main.lua` `drawBone()` | 端部不像骨头（宽度依赖 min(w,h) 写死） | 上一轮已换成 5 图元拟合 |
| 旧配色常量 `C_SKULL_EYE*` / `C_SANS_EYE*` / `C_SANS_COAT*` / `C_SANS_SHIRT` / `C_SANS_PANTS` / `C_SANS_BONE` | `lua/main.lua` 顶部 | 只服务旧模型 | **删除** |
| `mixCol()`、`SANS_SX/SANS_SY` | `lua/main.lua` | 只服务旧模型 | **删除** |
| `lua/fitdata.lua` 中未使用的素材表（其它表情、Fire 全 5 帧、躯干、腿、骨头 exact） | `lua/fitdata.lua` | 运行时从不读取 | 从 Lua 输出移除；**保留在 `fitdata.json` / `REPORT.md`** 作参考 |
| 首次烘焙预览（头部相关性对齐错误） | `reference/sprites/fit/baked_preview.png` | 头部被压到身体中部 | 已按 C2 image point 重算并覆盖 |

## 4. 历史归档（不参与运行，未删除）

这些是开发过程的记录，不是运行模型；如需瘦身可单独删：

- `records/play-headless/**`、`records/*.png`：旧模型时期的试玩截图与日志
- `records/*.save.json`（若存在）：旧内联脚本的存档快照
- `pool-before.txt` / `pool-after.txt` / `pool-final.txt` / `pool-out.txt`：旧控件池测量输出
- `probe.lua`、`lua/_probe_*.lua`：一次性探针
- `prototype/**`：步骤 3 的 HTML 原型（旧占位外观），不是千星运行时模型

## 5. 复现 / 校验

```powershell
# 重新生成拟合数据与对比图（fitdata.lua + fitdata.json + REPORT.md + 预览）
& 'D:\anaconda\python.exe' D:\stars\workspace\sans-fight\tools\fit-sprites.py
# 重建存档
node D:\stars\workspace\sans-fight\tools\build-save.mjs
# 模板契约 + 离线回归
node D:\stars\workspace\sans-fight\tools\verify-client-pool.mjs
node D:\stars\workspace\sans-fight\tools\verify-all.mjs --quick
```
