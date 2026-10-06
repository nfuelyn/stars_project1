# -*- coding: utf-8 -*-
import io
p=r"D:\stars\workspace\sans-fight\lua\main.lua"
s=io.open(p,encoding="utf8").read()

# blaster comment block
a=s.index("-- 龙骨炮：原作那种「骷髅炮」")
b=s.index("local function drawBlaster(cmd)", a)
new='''-- 龙骨炮：exact 逐像素烘焙（reference/sprites 57×44，Default + 3 个开火帧）。
--   炮身 = fitdata 容器（每个实例一套子控件，可同时画多发）；光束/炮口亮块仍走池内旋转矩形。
--   尺寸：Size 0/1/2 → ×0.8/1.0/1.3；蓄力期再整体 0.82 → 1.0。
--   局部坐标：u 向炮口、v 向炮身上；P(u,v) 做旋转；deg = -ang（世界 Y 向下、引擎 rotationZ 逆时针）。
'''
s=s[:a]+new+s[b:]

# sans comment block
a=s.index("-- 审判者「sans 本人」：零件尺寸照原作")
b=s.index("local SANS_H = 148", a)
new='''-- 审判者「sans 本人」：exact 逐像素烘焙（reference/sprites SansBody + SansHead）。
--   身体 = fit.sans_body_*，头 = fit.sans_head_default / sans_head_blue；头按原工程 C2 image point
--   （SansHead 原点(0.5,1) 放到 SansBody 的 Head 点）合成，所以头在身体上方。
--   Left 姿势水平镜像；其余表情统一回退 Default；汗滴用参数化圆点。
--   坐标：core 输出世界绝对坐标（640×480，Y 向下）；脚底锚定 feet = cmd.y + SANS_H。
'''
s=s[:a]+new+s[b:]
io.open(p,"w",encoding="utf8",newline="").write(s)
print("main comments cleaned")

# gdd.md
g=r"D:\stars\workspace\sans-fight\docs\gdd.md"
t=io.open(g,encoding="utf8").read()
t=t.replace("| **C15 弹幕外观** | 骨头是**实体外观**（骨干 + 两端各两颗骨球，带描边）；龙骨炮由**细实线**构建（头骨折线 + 5 条细实线光束 + 拉链短横线），不用实心填充 | 视觉检查（截图 / 试玩）；命中判定仍用轴对齐矩形，与外观分离 |",
            "| **C15 弹幕外观** | 骨头是**实体外观**（骨干 + 两端各两颗骨球）；龙骨炮与 Sans 本体走 `reference/sprites` 的 exact 逐像素烘焙模型（见 `docs/model-index.md`），光束仍由池内矩形绘制 | 视觉检查（截图 / 试玩）；命中判定仍用轴对齐矩形，与外观分离 |",1)
t=t.replace("> 3. **细实线龙骨炮**：`drawBlaster()` 用细实线构建新实体——头骨为折线轮廓 + 眼窝 + 下颚线，光束为 **5 条平行细实线**（边缘 3px、内部 1.5px）+ 9 条\"拉链\"短横线；蓄力阶段只有一条 2px 细实线预警。**不使用任何实心填充**。",
            "> 3. **龙骨炮外观**：2026-10-06 起改为 exact 逐像素烘焙模型（`lua/fitdata.lua`，Default + 3 个开火帧），不再使用旧细实线近似；详见 `docs/model-index.md`。",1)
io.open(g,"w",encoding="utf8",newline="").write(t)
print("gdd updated")
