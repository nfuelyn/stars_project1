# 原版仓库图片索引（reference/sprites）

- 来源：`D:\c2-sans-fight-src`（Construct 2 版 Bad Time Simulator，commit 0bb6afe）
- 落盘位置：`D:\stars\workspace\sans-fight\reference\sprites\`
- 共 **106** 个 PNG：animations 78 / textures 22 / icons 6
- 机器可读清单：`reference/sprites/manifest.json`（106 条，含 原路径 / 工作区路径 / 实体 / 动画 / 尺寸 / 用途 / 代码对应）
- **重要**：本目录是**参考素材**，游戏运行期并不加载它们（见 docs/gdd.md §7：不使用任何 Undertale 素材/字体/音乐）。当前画面全部由 7 个图元模板运行期拼装；这些图片用于尺寸/形状校对，以及将来若决定改用贴图时的素材来源。

---

## 1. animations（78）—— 按实体分组

| 实体 | 动画 | 帧数 | 尺寸 | 用途 | 代码/现状对应 |
|---|---|---|---|---|---|
| `GasterBlaster` | Default(x1, 57x44)；Fire(x5, 57x44) | 6 | 57x44 | 龙骨炮炮身（骷髅炮） | main.lua drawBlaster() / core.lua GasterBlaster（现状：rot 图元拼装 ≈57×44） |
| `HeartShard` | Default(x4, 16x16) | 4 | 16x16 | 死亡时灵魂碎片 | core.lua 死亡序列 HeartShard |
| `HP` | Default(x1, 23x10) | 1 | 23x10 | HP 血条小条 | core.lua HUD（现状：rect 拼装） |
| `KR` | Default(x1, 23x10) | 1 | 23x10 | KR 血条小条 | core.lua HUD（现状：rect 拼装） |
| `MenuBoneBottom` | Default(x1, 14x44) | 1 | 14x44 | 挡菜单按钮的下方骨头 | core.lua 菜单骨（MenuBoneBottom） |
| `MenuBoneLeft` | Default(x1, 14x44) | 1 | 14x44 | 扫过菜单的横向骨头 | core.lua 菜单骨（MenuBoneLeft） |
| `MenuItem` | Default(x1, 16x16) | 1 | 16x16 | 菜单光标（心形） | main.lua 菜单选中态 |
| `PlayerHeart` | Default(x1, 16x16)；Split(x1, 16x20) | 2 | 16x16/16x20 | 灵魂贴图：Default 红心 / Split 死亡分裂 | core.lua Game.soul / main.lua 灵魂绘制（16×16） |
| `PlayerHitbox` | Default(x1, 4x4) | 1 | 4x4 | 灵魂真实判定盒 4×4 | core.lua SOUL_R=2（判定物就是它） |
| `SansBody` | HandDown(x4, 64x70)；HandLeft(x5, 96x48)；HandRight(x5, 96x48)；HandUp(x5, 64x70) | 19 | 64x70/96x48 | Sans 全身姿势（HandUp/Down/Left/Right） | main.lua drawSans()（现状：rot 图元拼装） |
| `SansHead` | BlueEye(x2, 32x30)；ClosedEyes(x1, 32x30)；Default(x1, 32x30)；LookLeft(x1, 32x30)；NoEyes(x1, 32x30)；Tired1(x1, 32x30)；Tired2(x1, 32x30)；Wink(x1, 32x30) | 9 | 32x30 | Sans 头部/表情（Default/LookLeft/Wink/ClosedEyes/NoEyes/BlueEye/Tired1/Tired2） | main.lua drawSans()（32×30） |
| `SansLegs` | Sitting(x1, 52x17)；Standing(x1, 44x23) | 2 | 52x17/44x23 | Sans 腿部：Standing 站姿 / Sitting 坐姿 | main.lua drawSans()（44×23 / 52×17） |
| `SansSweat` | Sweat1(x1, 32x9)；Sweat2(x1, 32x9)；Sweat3(x1, 32x9) | 3 | 32x9 | 汗滴等级 1/2/3 | core.lua SansSweat / main.lua drawSans() |
| `SansTorso` | Default(x1, 54x25)；Shrug(x1, 72x24) | 2 | 54x25/72x24 | 躯干：Default / Shrug | main.lua drawSans()（54×25 / 72×24） |
| `SpeechBubble` | Default(x1, 237x104)；NoEffects(x1, 237x104) | 2 | 237x104 | 对话框：Default / NoEffects | core.lua SansText（237×104） |
| `Strike` | Default(x6, 4x6/4x22/6x42/8x64/14x32/14x12) | 6 | 4x6/4x22/6x42/8x64/14x32/14x12 | FIGHT 刀光 6 帧 | core.lua 攻击命中演出（Strike） |
| `Target` | Default(x1, 548x117) | 1 | 548x117 | FIGHT 攻击条底板 548×117 | core.lua attack 态（现状：rect 拼装） |
| `TargetChoice` | Default(x2, 14x128) | 2 | 14x128 | 攻击条滑动游标 14×128 | core.lua TargetChoice |
| `TouchA` | Default(x1, 48x48)；Pressed(x1, 48x48) | 2 | 48x48 | 触摸确认键（48×48） | main.lua 触摸 UI（按下/默认） |
| `TouchB` | Default(x1, 48x48)；Pressed(x1, 48x48) | 2 | 48x48 | 触摸取消键（48×48） | main.lua 触摸 UI（按下/默认） |
| `TouchDPad` | Default(x1, 48x48) | 1 | 48x48 | 虚拟十字键底盘 48×48 | main.lua 触摸摇杆 |
| `UIAct` | Default(x1, 110x42)；Highlight(x1, 110x42) | 2 | 110x42 | 菜单按钮「行动」110×42（默认/高亮） | main.lua 菜单按钮 |
| `UIFight` | Default(x1, 110x42)；Highlight(x1, 110x42) | 2 | 110x42 | 菜单按钮「攻击」110×42（默认/高亮） | main.lua 菜单按钮 |
| `UIItem` | Default(x1, 110x42)；Highlight(x1, 110x42) | 2 | 110x42 | 菜单按钮「道具」110×42（默认/高亮） | main.lua 菜单按钮 |
| `UIMercy` | Default(x1, 110x42)；Highlight(x1, 110x42) | 2 | 110x42 | 菜单按钮「仁慈」110×42（默认/高亮） | main.lua 菜单按钮 |
| `VPad` | Default(x1, 32x32) | 1 | 32x32 | 虚拟方向键 32×32 | main.lua 触摸/手柄 UI |

## 2. textures（22）—— 按用途分组

| 文件 | 尺寸 | 用途 | 代码/现状对应 |
|---|---|---|---|
| `textures/BattleFont.png` | 96x24 | 战斗字体位图 96×24 | 不接入：平台用 textbox 文本控件（IP + 无字体打包能力） |
| `textures/BoneH.png` | 24x10 | 横骨 24×10 | core.lua BoneH / main.lua drawBone()（BONE_W=10） |
| `textures/BoneStabH.png` | 24x12 | 横向骨刺 24×12 | core.lua BoneStab / ArrowBone |
| `textures/BoneStabV.png` | 12x24 | 纵向骨刺 12×24 | core.lua BoneStab / ArrowBone |
| `textures/BoneStabWarn.png` | 16x16 | 骨刺预警块 16×16 | core.lua BoneStab 预警阶段（半透明预告骨） |
| `textures/BoneV.png` | 10x24 | 竖骨 10×24 | core.lua BoneV / main.lua drawBone()（BONE_W=10） |
| `textures/CombatZone.png` | 16x16 | 战斗框九宫格底 16×16 | core.lua CombatZone / main.lua 战斗框 |
| `textures/CombatZoneBorder.png` | 4x4 | 战斗框边框 4×4 | core.lua CombatZoneTick（4 条边） |
| `textures/CombatZoneClipper.png` | 16x16 | 战斗框裁剪层 16×16 | core.lua 竖骨裁剪（clipVZone） |
| `textures/CombatZoneUnclipper.png` | 16x16 | 裁剪恢复层 16×16 | core.lua 裁剪配对 |
| `textures/DamageFont.png` | 528x192 | 伤害数字字体位图 528×192 | 不接入：同上（MISS/伤害字用文本控件） |
| `textures/DefaultFont.png` | 160x96 | 默认字体位图 160×96 | 不接入：同上 |
| `textures/GasterBlast1.png` | 16x16 | 光束外层 16×16（宽度 20/36/56） | core.lua BLASTER_W / main.lua 光束 |
| `textures/GasterBlast2.png` | 16x16 | 光束中层 16×16 | core.lua BLASTER_W / main.lua 光束 |
| `textures/GasterBlast3.png` | 16x16 | 光束内层 16×16 | core.lua BLASTER_W / main.lua 光束 |
| `textures/GasterBlastHit.png` | 16x16 | 光束命中体 16×16 | core.lua 光束判定（线段最短距离） |
| `textures/HPBackground.png` | 16x16 | HP 条底 16×16 | core.lua HUD HPBackground |
| `textures/HPBar.png` | 16x16 | HP 条填充 16×16 | core.lua HUD HPBar |
| `textures/KRBar.png` | 16x16 | KR 条填充 16×16 | core.lua HUD KRBar |
| `textures/Platform1.png` | 16x7 | 平台（逻辑）16×7 | core.lua Platform / main.lua 平台绘制 |
| `textures/Platform2.png` | 16x7 | 平台（视觉，容器联动）16×7 | core.lua Platform2 / main.lua 平台绘制 |
| `textures/SansFont.png` | 256x96 | Sans 台词字体位图 256×96 | 不接入：同上 |

## 3. icons（6）—— 平台侧资源

| 文件 | 尺寸 | 用途 |
|---|---|---|
| `icons/icon-114.png` | 114x114 | 应用图标（16/32/114/128/256） |
| `icons/icon-128.png` | 128x128 | 应用图标（16/32/114/128/256） |
| `icons/icon-16.png` | 16x16 | 应用图标（16/32/114/128/256） |
| `icons/icon-256.png` | 256x256 | 应用图标（16/32/114/128/256） |
| `icons/icon-32.png` | 32x32 | 应用图标（16/32/114/128/256） |
| `icons/loading-logo.png` | 32x32 | 加载页 logo 32×32 |

---

## 4. 与当前实现的对应关系（要点）

| 原版素材 | 当前实现（7 图元拼装） | 差值/可改进点 |
|---|---|---|
| `Textures/BoneV.png` 10×24、`BoneH.png` 24×10 | `main.lua drawBone()` 用 rect+circle 拼装，`core.lua BONE_W=10` | 厚度已对齐 10px；端点骨球形状与贴图仍有差异 |
| `Textures/GasterBlast1/2/3.png` 16×16 | `main.lua drawBlaster()` 用 rot 矩形拼炮身，光束用 3 条矩形 | 炮身按 57×44（`Animations/GasterBlaster`）重画；光束宽度 20/36/56 见 `core.BLASTER_W` |
| `Animations/GasterBlaster/*.png` 57×44 | 同上 | 炮身包围盒目标值 57×44；现状 ≈59×44 |
| `Animations/PlayerHeart/Default/000.png` 16×16 | `main.lua` 灵魂（circle/rect 拼装，红色 tint） | 贴图是 16×16 红心；判定用 4×4（PlayerHitbox） |
| `Animations/PlayerHitbox/Default/000.png` 4×4 | `core.lua SOUL_R=2` | **正好对应**：判定物就是这张 4×4 |
| `Animations/SansHead/*.png` 32×30 | `main.lua drawSans()` 用 rot 拼头 | 头部按 32×30；表情（Default/LookLeft/Wink/ClosedEyes/NoEyes/BlueEye/Tired1/Tired2）齐全 |
| `Animations/SansBody/*.png` 64×70 / 96×48 | 同上 | HandUp/Down 64×70，HandLeft/Right 96×48 |
| `Animations/SansLegs/*.png` 44×23 / 52×17 | 同上 | Standing 44×23 / Sitting 52×17 |
| `Animations/SansTorso/*.png` 54×25 / 72×24 | 同上 | Default / Shrug |
| `Animations/SansSweat/Sweat1-3.png` 32×9 | `main.lua drawSans()` 汗滴 | 三档汗量 |
| `Animations/SpeechBubble/*.png` 237×104 | `core.lua SansText`（当前用平台 textbox） | 对话框底板 237×104 |
| `Animations/Target/Default/000.png` 548×117 | `core.lua` attack 态（rect 拼装） | FIGHT 攻击条底板真值 548×117 |
| `Animations/TargetChoice/*.png` 14×128 | `core.lua` 攻击条游标 | 游标尺寸 14×128 |
| `Animations/UI{Fight,Act,Item,Mercy}/*.png` 110×42 | `main.lua` 菜单按钮 | 按钮真值 110×42（当前 MENU.bw=110/bh=36） |
| `Animations/Strike/*.png` 4×6 ~ 14×32（6 帧） | `core.lua` 攻击命中演出 | 刀光 6 帧序列 |
| `Animations/TouchA/B/*.png` 48×48、`VPad` 32×32、`TouchDPad` 48×48 | `main.lua` 触摸/摇杆 UI | 触摸件尺寸 |
| `Animations/HP`、`KR`、`MenuItem`、`HeartShard`、`MenuBoneLeft/Bottom` | `core.lua` HUD / 菜单 / 死亡 | 见上表逐条 |
| `Textures/BattleFont/DamageFont/DefaultFont/SansFont` | 平台 textbox 文本（不接入位图字体） | 位图字体仅作字形参考 |

## 5. 如果要「真的用上这些图片」需要做什么（未做，仅方案）

1. 在 `tools/build-save.mjs` 的 `TEMPLATES` 里为每张要用的图新建客户端模板（各自 `guid` + `imageId`），保持 `tools/verify-client-pool.mjs` 的 `EXPECT` 同步；
2. 在 `lua/main.lua` 的 `G` 表里登记新 guid，并用 `take("<kind>")` 取用；
3. 逐条替换 `drawBone/drawBlaster/drawSans` 里的图元拼装为 `SetImage(...)`；
4. **版权前置**：`docs/gdd.md` §7 明确「不使用任何 Undertale 素材」——若改用原版贴图，需要先改这条产品/法务口径。

