# Bad Time 战斗的 CodeArt

画面由 Lua 的几何配方和平台纯色图元组成，运行时无需导入 Sans、骨头、灵魂或龙骨炮的图片。`lua/fitdata.lua` 已从大型图片游程表改为自包含配方；旧渲染层所需的键名仍保留。这里的 Sans 和龙骨炮是可以修改的几何像素重绘，**不是原作贴图逐像素一致的复制品**。

「无外部贴图」指不依赖自定义 PNG、SVG 和在线图片；千星客户端的纯色矩形、圆、三角与环仍通过图片控件中的平台预设图元显示。中文剧情、道具说明、结算文案也使用 lua/textart.lua 的 CodeArt 字形。字形按颜色和图层缓存，运行时不需要字体资产或文本模板；增加了控件数量，设备性能需实测。英文 A–Z、数字 0–9 以及 `! ? - : . /` 已提供 5×7 像素字配方，可以用于 `FIGHT / ACT / ITEM / MERCY / HP / KR / GAME OVER` 等标签。

## 预览与验证

以下均是配方的离线渲染，供检查视觉和尺寸；不是已经在沙箱窗口或游戏窗口运行的截图。

- [Sans、六种表情、龙骨炮开合与 LOD](previews/codeart-characters.png)
- [全部元素图集](previews/codeart-elements.png)
- [战斗画面组合示意](previews/codeart-scene.png)
- [验证与矩形数量报告](previews/codeart-validation.json)

重建这些图集的方法：在工作目录运行 `python tools/preview_codeart.py`。工具使用 Lua 5.3 真实加载配方，再绘制矩形；会检查素材尺寸、正面积、有限坐标、边界、原接口关键键、四种不同的龙骨炮开口、六种不同表情、五种姿态一致的头顶至脚底高度，以及全部英文字母和数字的独立字形。它不会修改父级知识库或其他项目文件。

## 画面覆盖清单

| 画面元素 | CodeArt 入口 | 说明 |
| --- | --- | --- |
| Sans 默认站姿 | `sans_body_default` + `sans_head_default` | 包含连帽衫、T 恤、袖口、短裤、腿与拖鞋；头身体分离 |
| 抬手、落手、向左、向右 | `sans_poses.up/down/left/right` | 左手由右向配方镜像；所有姿态共用脚底锚点 |
| 闭眼、黑眼、发光眼、疲惫 1/2 | `sans_head_keys` | 对应脚本的 `ClosedEyes / NoEyes / BlueEye / Tired1 / Tired2` |
| 疲惫身姿 | `sans_body_variants[pose .. '_tired']` | 领肩下沉，腿脚保持原位置 |
| 独立躯干、腿、汗滴 | `sans_torso_default/tired`、`sans_legs_default`、`sans_sweat` | 可单独组合；实际汗滴数量、呼吸和闪身由渲染/战斗时间驱动 |
| 龙骨炮闭口与三阶段张嘴 | `blaster_keys` | 基础尺寸仍为 57×44；伸口变化不改变光束判定 |
| 龙骨炮 2 px / 3 px LOD | `blaster_block2 / blaster_block3` | 来自同一几何配方的采样，保留 `Default/fire_0/fire_2/fire_4` 兼容键 |
| 龙骨炮光束 | `codeart.beam` | 外层和亮核两个矩形；实际运行可继续用现有旋转矩形绘制 |
| 红心、四向蓝心 | `soul_red`、`soul_blue_up/down/left/right` | 16×16；蓝心方向 0=右、1=下、2=左、3=上；不改变逻辑中心和判定半径 |
| 破碎灵魂 | `soul_broken` / `codeart.brokenHeart` | 独立裂缝图形；只用于死亡表现 |
| 白、蓝、橙骨 | `bone_white/blue/orange_v/h` / `codeart.bone` | 颜色与白/蓝/橙攻击语义一致；运行时原有矩形加四圆端帽已是 CodeArt |
| 骨刺与预警 | `bone_stab`、`bone_warning` / `codeart.stab/warning` | 骨、尖端、半透明预告、黄色条纹均为图元配方 |
| 正弦骨、长骨、骨墙 | 现有 `drawBar/drawSine/drawWall` | 复用骨/条形配方，位置、缺口和长度直接来自逻辑层 |
| 绿色平台 | `platform_green` / `codeart.platform` | 完整矩形尺寸直接来自平台命令，无额外碰撞尺寸 |
| 战斗框、子菜单边框 | `battle_frame` / `codeart.frame` | 四条矩形，尺寸可变；内侧空间与原边框厚度一致 |
| 菜单、选中红心、按钮框 | `menu_button/selected` / `codeart.menuButton` | 配方中的 `textBox` 是推荐文字区域；实际点击区继续使用原布局计算 |
| 攻击条、中央提示、游标 | `attack_bar` / `codeart.attackBar` | 只画视觉，不重新计算命中或落空 |
| HP 与 KR | `hp_kr_bar` / `codeart.hudBar` | 黄色安全血、紫色 KR 和深色底槽；KR 不超过 HP−1 |
| 黑白闪屏、转场 | `flash_black/white` / `codeart.flash` | 一个全屏矩形；显示时间、淡出和结局防遮挡由现有状态机控制 |
| 手机摇杆与方向 | `joystick_idle/move` / `codeart.joystick` | 图集展示像素环；运行时环+圆的低成本组合同样是 CodeArt |
| 死亡、击倒、胜利、饶恕画面 | `result_fail/killed/victory/spare` / `codeart.result` | 黑底、像素英文标题、灵魂图标；中文说明与结算/重开按钮由平台文本框与原菜单提供 |
| 中文剧情、对话、说明 | 平台文本框 | 自带字体；文字本身不是自绘 CodeArt，保持 UTF-8 安全与可读性 |
| 屏幕抖动、闪身、呼吸 | 现有时间与坐标参数 | 属于已有图元的变换，不需要额外图片 |

图集覆盖素材配方；战斗状态机决定哪些元素真正出现。静态预览中的标题、菜单和结局配方不会自动新增分支或改变结算流程。

## 兼容接口与接入

所有可直接显示的素材使用以下结构。坐标从左上开始、Y 向下，矩形颜色为 `0xAARRGGBB`。

```lua
{
  w = 32,
  h = 30,
  rects = {
    {x = 8, y = 1, w = 16, h = 1, c = 0xFFFFFFFF},
    -- 更多矩形由配方生成
  },
}
```

渲染层把每个矩形变成纯色图片控件。Sans 可用子控件比例锚点挂在一个容器下，再整体缩放、移动、镜像；龙骨炮的 LOD 矩形可逐个旋转并通过现有控件池复用。不要逐帧重建 Sans 的像素子控件。

头部键从 `fit.sans_head_keys[cmd.head]` 选择，未知值回退 `fit.sans_head_default_key`。疲惫身体从 `fit.sans_body_variants[poseKey .. '_tired']` 选择；普通身体仍取 `fit.sans_poses[poseKey].body`。正常/default/down 的身体为 64×70，上手为 64×94，左右手为 96×70；相应头偏移保存在 `sans_poses`。各姿态满足 `body.h - pose.hy == 94`，按 1.6 倍显示时头顶到脚底约 150 px，脚底不漂移。左手镜像时连同头部一起镜像，并按身体宽度换算头偏移。

`fit.codeart` 提供下列可重用工厂。既有渲染函数已经用图元画出的骨、光束、边框、HP 与摇杆可以继续保留，避免为了使用像素配方而每帧增加栅格扫描和控件数量。

```lua
local A = fit.codeart
local heart = A.heart(A.palette.blue, 0)             -- 朝右蓝心，16×16
local bone = A.bone(10, 80, A.palette.boneBlue, true)
local box = A.frame(165, 165, 4, A.palette.white)
local bar = A.hudBar(92, 18, 64, 18, 92)
local label = A.pixelText('GAME OVER', A.palette.red)
```

其中 `bone / stab / joystick` 的工厂会做一次像素合并，适合素材加载、图集与预览，或按尺寸缓存。骨头、平台和战斗框尺寸频繁变化时，实际战斗优先使用现有直接图元绘制。`frame / platform / beam / flash / hudBar` 直接输出少量矩形。

## 控件数量与性能

本次实测矩形数如下，完整明细见 JSON 报告。数量不含根容器和中文文本控件；头部蓝眼的兼容别名指向同一配方。

| 元素 | 矩形数量 |
| --- | ---: |
| Sans 普通身体 | 默认 99；上 119；下 114；左/右 116 |
| Sans 疲惫身体 | 默认 94；上 121；下 114；左/右 115 |
| Sans 头部 | Default 60；BlueEye 63；ClosedEyes/NoEyes 52；Tired1/Tired2 58 |
| 独立躯干、腿、汗滴 | 躯干 82/77；腿 17；汗滴 5 |
| 龙骨炮完整细节 | 闭口 111；三开口阶段 117/125/131 |
| 龙骨炮 block2 | 闭口 68；三开口阶段 72/76/78 |
| 龙骨炮 block3 | 闭口 34；三开口阶段 36/41/43 |
| 红/蓝心、破碎心 | 完整心 16；破碎心 22 |
| 骨头、骨刺、预警 | 竖骨 7；横骨 9；骨刺 8；示例条纹预警 10 |
| 绿色平台、边框 | 平台 1；边框 4 |
| 攻击条、HP/KR、光束 | 攻击条 3；HP/KR 3；光束 2 |
| 黑/白闪屏 | 每种 1 |
| 像素摇杆 | 静止 131；示例拖动 138；实际原生环+圆通常只需 2 个图元 |
| 示例结局 | GAME OVER 68；KILLED 42；MERCY 45；VICTORY 47 |

多个龙骨炮同时出现时，预算按每发累加。例如 9 发 block2 的颅骨部分可接近 700 个旋转矩形；block3 约为 300–390。建议一般段使用 block2，密集旋转段用 block3，并保留动态扩容和场外隐藏。降低 LOD 只能降低视觉复杂度，不应改变光束宽度、骨头宽度、灵魂判定半径或攻击事件的时间。

## 平台与编辑器边界

[官方图片控件说明](https://act.mihoyo.com/ys/ugc/tutorial/detail/mh2oih9jou22)支持在界面控件组中添加图片、选择素材资产并配置颜色。父级本地客户端 API 文档列出了图片控件的 `SetImage`、`imageColor`，以及通用控件的位置、大小、锚点和旋转；这些字段是本项目图元适配的依据。

正式编辑器内仍需要根容器、纯色图元模板、文本框模板和交互输入区域，模板映射由 `lua/config.lua` 配置。模板索引与图元素材 ID 以当前项目为准；CodeArt 本身不会自动创建或导入这些编辑器资产。完整沙箱窗口、游戏窗口的操控、音效和结算设置见 [部署与设置](部署与设置.md)。

本次 CodeArt 验证确认了配方可生成、接口相容和离线视觉可读。正式客户端的锚点、旋转、裁剪、UI 层级与控件性能仍需要按主设置说明在游戏窗口验收。尤其要检查左手镜像、上手头的位置、蓝心四向旋转，以及所有转场结束后闪屏是否隐藏。
