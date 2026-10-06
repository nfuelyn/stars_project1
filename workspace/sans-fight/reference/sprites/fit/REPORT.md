# 原版贴图 → 千星图元拟合报告

生成工具：`tools/fit-sprites.py`；数据：`reference/sprites/fit/fitdata.json`、`lua/fitdata.lua`。

- `exact`：逐像素游程矩形（无损还原原图）。
- `block2`：2×2 采样 + 游程合并（近似，数量约为 exact 的 30–50%）。
- 坐标：图像像素坐标（左上原点、Y 向下）；颜色 `#RRGGBB`。

| 组 | 素材 | 尺寸 | exact 矩形 | block2 矩形 |
|---|---|---|---:|---:|
| sans | `sans_body_HandDown_000` | 64×70 | 309 | 109 |
| sans | `sans_body_HandDown_001` | 64×70 | 310 | 109 |
| sans | `sans_body_HandDown_002` | 64×70 | 344 | 124 |
| sans | `sans_body_HandDown_003` | 64×70 | 299 | 103 |
| sans | `sans_body_HandLeft_000` | 96×48 | 284 | 103 |
| sans | `sans_body_HandLeft_001` | 96×48 | 308 | 112 |
| sans | `sans_body_HandLeft_002` | 96×48 | 324 | 116 |
| sans | `sans_body_HandLeft_003` | 96×48 | 324 | 111 |
| sans | `sans_body_HandLeft_004` | 96×48 | 295 | 105 |
| sans | `sans_body_HandRight_000` | 96×48 | 295 | 105 |
| sans | `sans_body_HandRight_001` | 96×48 | 324 | 111 |
| sans | `sans_body_HandRight_002` | 96×48 | 324 | 116 |
| sans | `sans_body_HandRight_003` | 96×48 | 308 | 112 |
| sans | `sans_body_HandRight_004` | 96×48 | 284 | 103 |
| sans | `sans_body_HandUp_000` | 64×70 | 299 | 108 |
| sans | `sans_body_HandUp_001` | 64×70 | 299 | 103 |
| sans | `sans_body_HandUp_002` | 64×70 | 344 | 124 |
| sans | `sans_body_HandUp_003` | 64×70 | 310 | 109 |
| sans | `sans_body_HandUp_004` | 64×70 | 309 | 109 |
| sans | `sans_head_Default` | 32×30 | 177 | 73 |
| sans | `sans_head_BlueEye` | 32×30 | 181 | 72 |
| sans | `sans_head_ClosedEyes` | 32×30 | 163 | 58 |
| sans | `sans_head_LookLeft` | 32×30 | 177 | 68 |
| sans | `sans_head_NoEyes` | 32×30 | 169 | 69 |
| sans | `sans_head_Tired1` | 32×30 | 182 | 71 |
| sans | `sans_head_Tired2` | 32×30 | 182 | 71 |
| sans | `sans_head_Wink` | 32×30 | 173 | 65 |
| sans | `sans_torso_Default` | 54×25 | 333 | 97 |
| sans | `sans_torso_Shrug` | 72×24 | 216 | 75 |
| sans | `sans_legs_Sitting` | 52×17 | 115 | 49 |
| sans | `sans_legs_Standing` | 44×23 | 142 | 52 |
| blaster | `blaster_Default` | 57×44 | 320 | 123 |
| blaster | `blaster_Fire_000` | 57×44 | 306 | 115 |
| blaster | `blaster_Fire_001` | 57×44 | 294 | 117 |
| blaster | `blaster_Fire_002` | 57×44 | 316 | 126 |
| blaster | `blaster_Fire_003` | 57×44 | 293 | 124 |
| blaster | `blaster_Fire_004` | 57×44 | 297 | 112 |
| bone | `bone_BoneV` | 10×24 | 13 | 7 |
| bone | `bone_BoneH` | 24×10 | 13 | 7 |
| bone | `bone_BoneStabV` | 12×24 | 13 | 7 |
| bone | `bone_BoneStabH` | 24×12 | 13 | 7 |
| bone | `bone_BoneStabWarn` | 16×16 | 30 | 14 |

## 结论

- **骨头**：`BoneV/H` 的 exact 只有 13 个矩形；用 1 个骨干矩形 + 4 个骨球圆（5 图元）即可得到 95% 以上的观感，是唯一适合运行期逐帧拼装的。
- **龙骨炮 / Sans 本体**：exact 需要 200–600 个矩形/帧；逐帧拼装会超出当前控件池预算（rect 119 / circle 443 / rot 106）。
- 推荐：把 exact 表**烘焙进容器模板**（每个骨骼/角色一个容器，子控件静态），运行期只移动/显隐容器（1 次写入），即可像素级还原且不吃逐帧预算。

