--[[ ==========================================================================
  attacks.lua —— 攻击脚本数据（**自动生成，请勿手改**）
  ---------------------------------------------------------------------------
  生成器：tools/gen-attacks.mjs
  来源：  prototype/attacks/*.csv（27 个）
  生成日期：2026-10-06

  每项 = { name = "sans_xxx", csv = <该 CSV 的全文> }
  core.lua 通过 M.newGame({ scripts = require("attacks") }) 注入使用；
  也接受任意同构的表（便于测试注入自制脚本）。
  长括号层级：[==[ ... ]==]
  ========================================================================== ]]

local M = {
  { name = "final", csv = [==[
# final —— 最终回合（四阶段 + 撑过后的睡意演出），原作最长的一段
#   阶段① 行 1-27   4 次随机方向「抬手 → 砸 + 骨刺(距离29/预警0.4/停留0)」，
#                   收尾两组 BoneHRepeat(130,-10,200,南,300,3,183) 与 (330,650,200,北,300,3,183)
#   阶段② 行 28-98  框体横向扩张；HeartMaxFallSpeed -300 造出「反向重力走廊」；
#                   SansRepeat 左右滑屏；44 根正弦起伏高速骨（行 49-64 小循环）+ 10 组骨墙 +
#                   24 根上下开合骨（行 85-92 小循环）
#   阶段③ 行 99-137 4 组「黑屏闪 + 双方向骨刺(48/预警0.6/停留1) + HeartTeleport + SansSlam」
#   阶段④ 行 138-156 旋转光束：Ang = -10·gt，gin 从 1 每次 +0.015 递增到 1.7，
#                   gt 累加到 190 才停（约 122 发、每发 0.06666s，BlastTime = 0 即瞬发）
#   阶段⑤ 行 157-213 撑过光束后的 38 次连续砸击：SansSlamDamage 1（这次真的会掉血），
#                   Wait 由 0.2 递减；I=25 开始冒汗、I=33 出现 Tired1、I=35 强制朝北、
#                   I=36 起 Tired2（此时 MaxFallSpeed 只剩 60）→ 最后 SansAnimation Tired
# 数据来源：BTS（jcw87/c2-sans-fight, GPL-3.0）Files/sans_final.csv 逐行转写。
# 跳转沿用原作 1-based 行号（只数非注释行，故以上注释不改变任何行号）：
#   7 / 49 / 85 / 140 / 156 / 166 / 168 / 170 / 172 / 186 / 187 / 191 / 194 / 200 / 203 / 206 / 210
# 唯一改动（数值等价、行数不变）：第 47 行 DIV,Deg,180,$pi → 写死 π 的字面量 3.141592653589793。
#   BTS 里 $pi 由表达式层提供（Event sheets/Globals.xml 未声明该变量），本引擎的 val() 对未定义
#   变量返回 0，会让 Deg = 180/0 变 Infinity 进而使整面正弦骨 NaN。180/π 是「弧度→角度」换算，
#   是唯一能让正弦骨墙正常起伏的取值（H ∈ [5,55]，上下骨之间恒为 34 高的正弦走廊）。
0,CombatZoneResize,241,226,406,391,TLResume
0,HeartTeleport,320,304
0,HeartMode,0
0,TLPause
0,SansSweat,0
0,SET,I,0
0.3,RND,Direction,4
0,ADD,Jump,$Direction,1
0,JMPREL,$Jump
0,JMPREL,4
0,JMPREL,5
0,JMPREL,6
0,JMPREL,7
0,SansBody,HandRight
0,JMPREL,7
0,SansBody,HandDown
0,JMPREL,5
0,SansBody,HandLeft
0,JMPREL,3
0,SansBody,HandUp
0,JMPREL,1
0.26666,SansSlam,$Direction
0.2,BoneStab,$Direction,29,0.4,0
0,ADD,I,$I,1
0,JMPL,7,$I,4
0,BoneHRepeat,130,-10,200,1,300,3,183
0,BoneHRepeat,330,650,200,3,300,3,183
0.5,HeartMode,0
2,SansBody,HandLeft
0.2,SansSlam,2
0.3,SansBody,HandRight
0.2,HeartMaxFallSpeed,450
0,HeartDir,0
0,CombatZoneResizeInstant,241,226,449,391
0,CombatZoneSpeed,900
0,CombatZoneResize,241,226,650,391
0.33333,HeartMaxFallSpeed,-300
0,SansAnimation,Idle
0,SansRepeat
0,CombatZoneResize,-10,226,650,391
0.3,CombatZoneSpeed,30
0,CombatZoneResize,-10,264,650,369
0.9,GetHeartPos,HeartX,HeartY
0,HeartTeleport,40,$HeartY
0,HeartMaxFallSpeed,0
0,SansSlam,0
0,DIV,Deg,180,3.141592653589793
0,SET,I,0
0,DIV,Ang,$I,2
0,MUL,Ang,$Ang,$Deg
0,SIN,Sine,$Ang
0,MUL,Sine,$Sine,25
0,FLOOR,Sine,$Sine
0,MUL,X,$I,60
0,ADD,X,$X,634
0,SET,Y,270
0,ADD,H,30,$Sine
0,BoneV,$X,$Y,$H,2,900
0,ADD,Y,$Y,$H
0,ADD,Y,$Y,34
0,SUB,H,364,$Y
0,BoneV,$X,$Y,$H,2,900
0,ADD,I,$I,1
0,JMPL,49,$I,44
0,ADD,X,$X,360
0,BoneVRepeat,$X,270,50,2,900,3,15
0,ADD,X,$X,330
0,BoneVRepeat,$X,314,50,2,900,3,15
0,ADD,X,$X,300
0,BoneVRepeat,$X,270,50,2,900,3,15
0,ADD,X,$X,300
0,BoneVRepeat,$X,314,50,2,900,3,15
0,ADD,X,$X,270
0,BoneVRepeat,$X,270,50,2,900,3,15
0,ADD,X,$X,270
0,BoneVRepeat,$X,314,50,2,900,3,15
0,ADD,X,$X,240
0,BoneVRepeat,$X,270,50,2,900,3,15
0,ADD,X,$X,330
0,BoneVRepeat,$X,314,50,2,900,3,15
0,ADD,X,$X,270
0,BoneVRepeat,$X,270,50,2,900,3,15
0,ADD,X,$X,390
0,SET,I,0
0,MUL,X2,$I,30
0,ADD,X2,$X2,$X
0,ADD,H,10,$I
0,BoneV,$X2,270,$H,2,900
0,SUB,Y,365,$H
0,BoneV,$X2,$Y,$H,2,900
0,ADD,I,$I,1
0,JMPL,85,$I,24
0,SET,I,0
8,HeartMaxFallSpeed,330
0,SansSlam,0
0,CombatZoneSpeed,540
0,CombatZoneResize,-10,264,410,369
0.9,SansEndRepeat
0,SansHead,Default
0,SansTorso,Default
0,SansBody,HandLeft
0.2,BoneStab,0,50,0.4,1
0.9,BlackScreen,1
0,Sound,Flash
0.4,BlackScreen,0
0,Sound,Flash
0,CombatZoneResizeInstant,239,226,404,391
0,HeartTeleport,320,376
0,HeartMode,0
0,SansAnimation,HeadBob
0.03333,BoneStab,1,48,0.6,1
0,BoneStab,3,48,0.6,1
0.9,BlackScreen,1
0,Sound,Flash
0.1,BlackScreen,0
0,Sound,Flash
# 【2026-10-06 用户口径·二次】这一段（两条边一起出骨刺）**保持蓝心**（原作 SansSlam 语义：
#   切蓝 + 设重力方向），并把两根骨刺「出来」的预警各延长 0.8s（0.6 → 1.4）。
0,HeartTeleport,262,240
0,SansSlam,3
0.03333,BoneStab,2,48,1.4,1
0,BoneStab,3,48,1.4,1
0.9,BlackScreen,1
0,Sound,Flash
0.1,BlackScreen,0
0,Sound,Flash
# 【2026-10-06 用户口径·二次】同上：保持蓝心（SansSlam），骨刺预警 0.6 → 1.4（+0.8s）。
0,HeartTeleport,391,376
0,SansSlam,0
0.03333,BoneStab,0,48,1.4,1
0,BoneStab,1,48,1.4,1
0.9,BlackScreen,1
0,Sound,Flash
0.1,BlackScreen,0
0,Sound,Flash
0,HeartTeleport,262,240
0,SansSlam,2
0,SansX,320
0.03333,BoneStab,2,48,0.6,1
0.7,HeartMode,0
0,SET,gt,0
0,SET,gin,1
0,MUL,Ang,$gt,-10
0,COS,X,$Ang
0,SIN,Y,$Ang
0,MUL,EndX,$X,150
0,MUL,EndY,$Y,150
0,MUL,X,$EndX,3
0,MUL,Y,$EndY,3
0,ADD,X,$X,320
0,ADD,Y,$Y,306
0,ADD,EndX,$EndX,320
0,ADD,EndY,$EndY,306
0,ADD,Ang,$Ang,180
0,GasterBlaster,0,$X,$Y,$EndX,$EndY,$Ang,0.5,0
0,ADD,gt,$gt,$gin
0,JMPNL,156,$gin,1.7
0,ADD,gin,$gin,0.015
0.06666,JMPL,140,$gt,190
1,SansHead,BlueEye
0,HeartMaxFallSpeed,750
0,SansBody,HandRight
0,SansSlamDamage,1
0,SET,I,0
0,SET,Direction,0
0,SET,LastDir,2
0,SET,Wait1,0.13333
0,SET,Wait2,0.13333
0,JMPNE,168,$Direction,$LastDir
0,SUB,Direction,$Direction,2
0,JMPNL,170,$Direction,0
0,ADD,Direction,$Direction,4
0,JMPL,172,$Direction,4
0,SUB,Direction,$Direction,4
0,MUL,Jump,$Direction,2
0,ADD,Jump,$Jump,1
0,JMPREL,$Jump
0,SansBody,HandRight
0,JMPREL,6
0,SansBody,HandDown
0,JMPREL,4
0,SansBody,HandLeft
0,JMPREL,2
0,SansBody,HandUp
$Wait1,SansSlam,$Direction
$Wait2,SET,LastDir,$Direction
0,MOD,Odd,$I,2
0,JMPZ,187,$Odd
0,RND,Direction,4
0,JMPNE,191,$I,21
0,HeartMaxFallSpeed,480
0,SET,Wait1,0.2
0,SET,Wait2,0.2
0,JMPNE,194,$I,25
0,SansHead,Default
0,SansSweat,1
0,JMPNE,200,$I,33
0,SansHead,Tired1
0,SansSweat,2
0,HeartMaxFallSpeed,330
0,SET,Wait1,0.5
0,SET,Wait2,1.1
0,JMPNE,203,$I,33
0,JMPE,186,$Direction,1
0,JMPE,186,$Direction,$LastDir
0,JMPNE,206,$I,35
0,HeartMaxFallSpeed,240
0,SET,Direction,3
0,JMPNE,210,$I,36
0,SansHead,Tired2
0,SansSweat,3
0,HeartMaxFallSpeed,60
0,ADD,I,$I,1
0,JMPL,166,$I,38
1.5,SansAnimation,Tired
2.4,EndAttack
]==] },
  { name = "multi1", csv = [==[
# multi1 —— 多段随机攻击组：每回合先黑屏闪一下，再从 5 种攻击里随机挑一种，共 5 段
#   Attack0 两侧骨墙夹击（repeat 4×16 + 单根高 100）
#   Attack1 左右对称的「高骨 + 底矮骨」三次冲击（Color 0/1 交替）
#   Attack2 内层循环 4 次：纵向间距 Total 逐次加大、骨高/速度随机（蓝魂通道，上下缝恒 18 高）
#   Attack3 双侧 repeat 3×125 的「高 70 + 矮 15」双层骨墙
#   Attack4 随机左/右：11 根高 55 @360 与 10 根矮 15 @360 的高速骨流
# 数据来源：BTS（jcw87/c2-sans-fight, GPL-3.0）Files/sans_multi1.csv 逐行转写，数值未改。
# 标签行（:RndAttack / :Attack0..4 / :Attack2Begin / :SkipRndSpeed / :End）与原作同名同位。
0,CombatZoneResize,133,251,508,391,TLResume
0,HeartTeleport,320,304
0,HeartMode,1
0,TLPause
0,SET,Loop,5
0,:RndAttack
0,BlackScreen,1
0,Sound,Flash
0.4,BlackScreen,0
0,Sound,Flash
0,JMPZ,End,$Loop
0,SUB,Loop,$Loop,1
0,RND,Jump,5
0,ADD,Jump,$Jump,1
0,JMPREL,$Jump
0,JMPABS,Attack0
0,JMPABS,Attack1
0,JMPABS,Attack2
0,JMPABS,Attack3
0,JMPABS,Attack4
0,:Attack0
0,CombatZoneResizeInstant,121,276,526,391
0,HeartMode,1
0,HeartTeleport,320,376
0,BoneVRepeat,128,341,45,0,240,4,16
0,BoneV,64,286,100,0,240
0,BoneVRepeat,512,341,45,2,240,4,16
0,BoneV,576,286,100,2,240
0.9,JMPABS,RndAttack
0,:Attack1
0,CombatZoneResizeInstant,121,276,526,391
0,HeartMode,1
0,HeartTeleport,320,376
0,BoneV,128,286,100,0,240,1
0,BoneV,56,366,20,0,240,0
0,BoneV,24,286,100,0,240,0
0,BoneV,512,286,100,2,240,1
0,BoneV,584,366,20,2,240,0
0,BoneV,616,286,100,2,240,0
1.1,JMPABS,RndAttack
0,:Attack2
0,CombatZoneResizeInstant,171,276,476,391
0,HeartMode,1
0,HeartTeleport,320,376
0,SET,Total,0
0,SET,Loop2,0
0,:Attack2Begin
0,RND,Choice,3
0,ADD,HeightB,$Choice,2
0,MUL,HeightB,$HeightB,10
0,SET,RndSpeed,0
0,JMPZ,SkipRndSpeed,$Loop2
0,RND,RndSpeed,3
0,SUB,RndSpeed,$RndSpeed,1
0,MUL,RndSpeed,$RndSpeed,2
0,:SkipRndSpeed
0,SUB,HeightT,86,$HeightB
0,SUB,YB,386,$HeightB
0,MUL,X,$Loop2,22
0,ADD,X,$X,25
0,ADD,X,$X,$Total
0,ADD,SpeedL,6,$RndSpeed
0,MUL,XL,$X,$SpeedL
0,SUB,XL,320,$XL
0,MUL,SpeedL,$SpeedL,30
0,MUL,RndSpeed,$RndSpeed,-1
0,ADD,SpeedR,6,$RndSpeed
0,MUL,XR,$X,$SpeedR
0,ADD,XR,320,$XR
0,MUL,SpeedR,$SpeedR,30
0,BoneV,$XL,282,$HeightT,0,$SpeedL
0,BoneV,$XL,$YB,$HeightB,0,$SpeedL
0,BoneV,$XR,282,$HeightT,2,$SpeedR
0,BoneV,$XR,$YB,$HeightB,2,$SpeedR
0,MUL,TotalInc,$Choice,5
0,ADD,Total,$Total,$TotalInc
0,ADD,Loop2,$Loop2,1
0,JMPL,Attack2Begin,$Loop2,4
1.9,JMPABS,RndAttack
0,:Attack3
0,CombatZoneResizeInstant,171,276,476,391
0,HeartMode,1
0,HeartTeleport,320,376
0,BoneVRepeat,200,282,70,0,150,3,125
0,BoneVRepeat,200,371,15,0,150,3,125
0,BoneVRepeat,440,282,70,2,150,3,125
0,BoneVRepeat,440,371,15,2,150,3,125
1.7,JMPABS,RndAttack
0,:Attack4
0,CombatZoneResizeInstant,121,276,526,391
0,HeartMode,1
0,RND,Side,2
0,JMPZ,Attack4Other,$Side
0,HeartTeleport,506,376
0,BoneVRepeat,200,331,55,0,360,11,24
0,BoneVRepeat,-64,371,15,0,360,10,24
1.5,JMPABS,RndAttack
0,:Attack4Other
0,HeartTeleport,149,376
0,BoneVRepeat,440,331,55,2,360,11,24
0,BoneVRepeat,704,371,15,2,360,10,24
1.5,JMPABS,RndAttack
0,:End
0,CombatZoneResizeInstant,33,251,608,391
0,EndAttack
]==] },
  { name = "multi2", csv = [==[
# multi2 —— 多段随机攻击组（后半场版）：从 4 种攻击里随机挑一种，共 5 段，各段 1.2~1.9s
#   Attack5 静止平台 + 从一侧飞来的 22 根静止矮骨（repeat 25×16 速度 0）与两根高速骨
#   Attack6 红魂四连炮：随机「正交 0/90/180/270」或「斜向 45/135/225/315」两套
#   Attack7 随机方向 SineBones(16, ±20, 300, 55)
#   Attack8 镜像骨缝：6 根矮 20 @120 与 6 根高 82 @120（间距 76）
# 数据来源：BTS（jcw87/c2-sans-fight, GPL-3.0）Files/sans_multi2.csv 逐行转写，数值未改。
# 注意：本脚本**没有**起手的 CombatZoneResize/TLPause，直接进入循环（原作即如此）。
0,HeartTeleport,320,304
0,SET,Loop,5
0,:RndAttack
0,BlackScreen,1
0,Sound,Flash
0.4,BlackScreen,0
0,Sound,Flash
0,JMPZ,End,$Loop
0,SUB,Loop,$Loop,1
0,RND,Jump,4
0,ADD,Jump,$Jump,1
0,JMPREL,$Jump
0,JMPABS,Attack5
0,JMPABS,Attack6
0,JMPABS,Attack7
0,JMPABS,Attack8
0,:Attack5
0,CombatZoneResizeInstant,121,276,526,391
0,HeartMode,1
0,HeartTeleport,330,304
0,Platform,309,314,41,0,0
0,Platform,309,354,41,0,0

0,BoneVRepeat,121,364,30,2,0,25,16
0,RND,Side,2
0,JMPZ,Attack5Other,$Side
0,BoneV,521,280,35,2,240
0,BoneV,1,319,65,0,240
1.2,JMPABS,RndAttack
0,:Attack5Other
0,BoneV,119,280,35,0,240
0,BoneV,639,319,65,2,240
1.2,JMPABS,RndAttack
0,:Attack6
0,CombatZoneResizeInstant,241,226,406,391
0,HeartMode,0
0,HeartTeleport,320,304
0,RND,Rot,2
0,JMPZ,Attack6Other,$Rot
0,GasterBlaster,1,191,306,191,306,0,0.6,0.26666,1.5
0,GasterBlaster,1,321,166,321,166,90,0.6,0.26666,1.5
0,GasterBlaster,1,449,306,449,306,180,0.6,0.26666,1.5
0,GasterBlaster,1,321,446,321,446,270,0.6,0.26666,1.5
2.6,JMPABS,RndAttack
0,:Attack6Other
0,GasterBlaster,1,191,176,191,176,45,0.6,0.26666,1.5
0,GasterBlaster,1,451,176,451,176,135,0.6,0.26666,1.5
0,GasterBlaster,1,451,436,451,436,225,0.6,0.26666,1.5
0,GasterBlaster,1,191,436,191,436,315,0.6,0.26666,1.5
2.6,JMPABS,RndAttack
0,:Attack7
0,CombatZoneResizeInstant,179,226,404,391
0,HeartMode,0
0,RND,Side,2
0,JMPZ,Attack7Other,$Side
0,HeartTeleport,382,304
0,SineBones,16,-20,300,55
1.7,JMPABS,RndAttack
0,:Attack7Other
0,HeartTeleport,267,304
0,SineBones,16,20,300,55
1.7,JMPABS,RndAttack
0,:Attack8
0,CombatZoneResizeInstant,121,276,526,391
0,HeartMode,1
0,RND,Side,2
0,JMPZ,Attack8Other,$Side
0,HeartTeleport,489,376
0,BoneVRepeat,345,364,20,0,120,6,76
0,BoneVRepeat,297,280,82,2,120,6,76
1.9,JMPABS,RndAttack
0,:Attack8Other
0,HeartTeleport,168,376
0,BoneVRepeat,297,364,20,2,120,6,76
0,BoneVRepeat,345,280,82,0,120,6,76
1.9,JMPABS,RndAttack
0,:End
0,CombatZoneResizeInstant,33,251,608,391
0,EndAttack
]==] },
  { name = "multi3", csv = [==[
# multi3 —— 多段随机攻击组（最长版）：从 9 种攻击里随机挑一种，共 5 段，黑屏闪更快（0.13333s）
#   Attack0..Attack4 与 multi1 完全同参；Attack5..Attack8 与 multi2 完全同参。
# 数据来源：BTS（jcw87/c2-sans-fight, GPL-3.0）Files/sans_multi3.csv 逐行转写，数值未改。
# 跳转沿用原作 1-based 行号：JMPREL,$Jump 的跳表起点后紧跟 9 行 JMPABS（行 16~24）。
0,CombatZoneResize,239,226,404,391,TLResume
0,HeartTeleport,320,304
0,HeartMode,0
0,TLPause
0,SET,Loop,5
0,:RndAttack
0,BlackScreen,1
0,Sound,Flash
0.13333,BlackScreen,0
0,Sound,Flash
0,JMPZ,End,$Loop
0,SUB,Loop,$Loop,1
0,RND,Jump,9
0,ADD,Jump,$Jump,1
0,JMPREL,$Jump
0,JMPABS,Attack0
0,JMPABS,Attack1
0,JMPABS,Attack2
0,JMPABS,Attack3
0,JMPABS,Attack4
0,JMPABS,Attack5
0,JMPABS,Attack6
0,JMPABS,Attack7
0,JMPABS,Attack8
0,:Attack0
0,CombatZoneResizeInstant,121,276,526,391
0,HeartMode,1
0,HeartTeleport,320,376
0,BoneVRepeat,128,341,45,0,240,4,16
0,BoneV,64,286,100,0,240
0,BoneVRepeat,512,341,45,2,240,4,16
0,BoneV,576,286,100,2,240
0.9,JMPABS,RndAttack
0,:Attack1
0,CombatZoneResizeInstant,121,276,526,391
0,HeartMode,1
0,HeartTeleport,320,376
0,BoneV,128,286,100,0,240,1
0,BoneV,56,366,20,0,240,0
0,BoneV,24,286,100,0,240,0
0,BoneV,512,286,100,2,240,1
0,BoneV,584,366,20,2,240,0
0,BoneV,616,286,100,2,240,0
1.1,JMPABS,RndAttack
0,:Attack2
0,CombatZoneResizeInstant,171,276,476,391
0,HeartMode,1
0,HeartTeleport,320,376
0,SET,Total,0
0,SET,Loop2,0
0,:Attack2Begin
0,RND,Choice,3
0,ADD,HeightB,$Choice,2
0,MUL,HeightB,$HeightB,10
0,SET,RndSpeed,0
0,JMPZ,SkipRndSpeed,$Loop2
0,RND,RndSpeed,3
0,SUB,RndSpeed,$RndSpeed,1
0,MUL,RndSpeed,$RndSpeed,2
0,:SkipRndSpeed
0,SUB,HeightT,86,$HeightB
0,SUB,YB,386,$HeightB
0,MUL,X,$Loop2,22
0,ADD,X,$X,25
0,ADD,X,$X,$Total
0,ADD,SpeedL,6,$RndSpeed
0,MUL,XL,$X,$SpeedL
0,SUB,XL,320,$XL
0,MUL,SpeedL,$SpeedL,30
0,MUL,RndSpeed,$RndSpeed,-1
0,ADD,SpeedR,6,$RndSpeed
0,MUL,XR,$X,$SpeedR
0,ADD,XR,320,$XR
0,MUL,SpeedR,$SpeedR,30
0,BoneV,$XL,282,$HeightT,0,$SpeedL
0,BoneV,$XL,$YB,$HeightB,0,$SpeedL
0,BoneV,$XR,282,$HeightT,2,$SpeedR
0,BoneV,$XR,$YB,$HeightB,2,$SpeedR
0,MUL,TotalInc,$Choice,5
0,ADD,Total,$Total,$TotalInc
0,ADD,Loop2,$Loop2,1
0,JMPL,Attack2Begin,$Loop2,4
1.9,JMPABS,RndAttack
0,:Attack3
0,CombatZoneResizeInstant,171,276,476,391
0,HeartMode,1
0,HeartTeleport,320,376
0,BoneVRepeat,200,282,70,0,150,3,125
0,BoneVRepeat,200,371,15,0,150,3,125
0,BoneVRepeat,440,282,70,2,150,3,125
0,BoneVRepeat,440,371,15,2,150,3,125
1.7,JMPABS,RndAttack
0,:Attack4
0,CombatZoneResizeInstant,121,276,526,391
0,HeartMode,1
0,RND,Side,2
0,JMPZ,Attack4Other,$Side
0,HeartTeleport,506,376
0,BoneVRepeat,200,331,55,0,360,11,24
0,BoneVRepeat,-64,371,15,0,360,10,24
1.2,JMPABS,RndAttack
0,:Attack4Other
0,HeartTeleport,149,376
0,BoneVRepeat,440,331,55,2,360,11,24
0,BoneVRepeat,704,371,15,2,360,10,24
1.2,JMPABS,RndAttack
0,:Attack5
0,CombatZoneResizeInstant,121,276,526,391
0,HeartMode,1
0,HeartTeleport,330,304
0,Platform,309,314,41,0,0
0,Platform,309,354,41,0,0

# 【2026-10-06 用户口径·round22】贴地那排骨头：25 根 × 间距 16（缝仅 6px，灵魂宽 16 钻不过去）
#   → 10 根 × 间距 40（缝 30px，能容下灵魂），高 30 → 15（大小减半）；横向覆盖宽度不变。
0,BoneVRepeat,121,364,15,2,0,10,40
0,RND,Side,2
0,JMPZ,Attack5Other,$Side
0,BoneV,521,280,35,2,240
0,BoneV,1,319,65,0,240
1.2,JMPABS,RndAttack
0,:Attack5Other
0,BoneV,119,280,35,0,240
0,BoneV,639,319,65,2,240
1.2,JMPABS,RndAttack
0,:Attack6
0,CombatZoneResizeInstant,241,226,406,391
0,HeartMode,0
0,HeartTeleport,320,304
0,RND,Rot,2
0,JMPZ,Attack6Other,$Rot
0,GasterBlaster,1,191,306,191,306,0,0.6,0.26666
0,GasterBlaster,1,321,166,321,166,90,0.6,0.26666
0,GasterBlaster,1,449,306,449,306,180,0.6,0.26666
0,GasterBlaster,1,321,446,321,446,270,0.6,0.26666
1.2,JMPABS,RndAttack
0,:Attack6Other
0,GasterBlaster,1,191,176,191,176,45,0.6,0.26666
0,GasterBlaster,1,451,176,451,176,135,0.6,0.26666
0,GasterBlaster,1,451,436,451,436,225,0.6,0.26666
0,GasterBlaster,1,191,436,191,436,315,0.6,0.26666
1.2,JMPABS,RndAttack
0,:Attack7
0,CombatZoneResizeInstant,179,226,404,391
0,HeartMode,0
0,RND,Side,2
0,JMPZ,Attack7Other,$Side
0,HeartTeleport,382,304
0,SineBones,16,-20,300,55
1.7,JMPABS,RndAttack
0,:Attack7Other
0,HeartTeleport,267,304
0,SineBones,16,20,300,55
1.7,JMPABS,RndAttack
0,:Attack8
0,CombatZoneResizeInstant,121,276,526,391
0,HeartMode,1
0,RND,Side,2
0,JMPZ,Attack8Other,$Side
0,HeartTeleport,489,376
0,BoneVRepeat,345,364,20,0,120,6,76
0,BoneVRepeat,297,280,82,2,120,6,76
1.9,JMPABS,RndAttack
0,:Attack8Other
0,HeartTeleport,168,376
0,BoneVRepeat,297,364,20,2,120,6,76
0,BoneVRepeat,345,280,82,0,120,6,76
1.9,JMPABS,RndAttack
0,:End
0,CombatZoneResizeInstant,33,251,608,391
0,EndAttack
]==] },
  { name = "platformblaster", csv = [==[
# platformblaster —— 蓝魂双平台（右上 8 块向西 / 左下 8 块向东）间躲炮
#                   循环 5 次：左右各一发随机高度的 Size0 龙骨炮（Spin 0.56666 / Blast 仅 0.1）
# 数据来源：BTS（jcw87/c2-sans-fight, GPL-3.0）Files/sans_platformblaster.csv 逐行转写，数值未改。
# 跳转沿用原作 1-based 行号：JMPNZ,8,$Loop → 第 8 行 SUB,Loop,$Loop,1。
0,CombatZoneResize,133,251,508,391,TLResume
0,HeartTeleport,320,376
0,HeartMode,1
0,TLPause
0,PlatformRepeat,552,346,51,2,120,8,140
0,PlatformRepeat,-20,306,51,0,120,8,160
0,SET,Loop,5
0,SUB,Loop,$Loop,1
0,RND,Y,3
0,MUL,Y,$Y,60
0,ADD,Y,$Y,285
0,GasterBlaster,0,0,0,73,$Y,0,0.56666,0.1,1.5
0.9,RND,Y,3
0,MUL,Y,$Y,60
0,ADD,Y,$Y,285
0,GasterBlaster,0,640,0,563,$Y,180,0.56666,0.1,1.5
0.9,JMPNZ,8,$Loop
# 【2026-10-06】末尾留 2.2s：两发都要走完「落定 → 停 1.5s → 发射 0.1s」，
#   不留白的话 EndAttack 会先把还在等待里的龙骨炮 done 掉（只有前几发真打得出来）。
2.2,EndAttack
]==] },
  { name = "platformblasterfast", csv = [==[
# platformblasterfast —— platformblaster 的加速版：循环 6 次、两侧间隔由 0.9 压到 0.7
# 数据来源：BTS（jcw87/c2-sans-fight, GPL-3.0）Files/sans_platformblasterfast.csv 逐行转写，数值未改。
0,CombatZoneResize,133,251,508,391,TLResume
0,HeartTeleport,320,376
0,HeartMode,1
0,TLPause
0,PlatformRepeat,552,346,51,2,120,8,140
0,PlatformRepeat,-20,306,51,0,120,8,160
0,SET,Loop,6
0,SUB,Loop,$Loop,1
0,RND,Y,3
0,MUL,Y,$Y,40
0,ADD,Y,$Y,285
0,GasterBlaster,0,0,0,73,$Y,0,0.56666,0.1
0.7,RND,Y,3
0,MUL,Y,$Y,40
0,ADD,Y,$Y,285
0,GasterBlaster,0,640,0,563,$Y,180,0.56666,0.1
0.7,JMPNZ,8,$Loop
0,EndAttack
]==] },
  { name = "platforms1", csv = [==[
# platforms1 —— 蓝魂站平台：向东的平台 + 41 根矮骨地毯（间距 15），后半改由两侧高骨推挤
# 数据来源：BTS（jcw87/c2-sans-fight, GPL-3.0）Files/sans_platforms1.csv 逐行转写，数值未改。
# 坐标系：原版 640×480，Y 向下；战斗框参数为 (左, 上, 右, 下)。速度单位 px/s（= 原作值 ×30）。
0,CombatZoneResize,133,251,508,391,TLResume
0,HeartTeleport,320,376
0,HeartMode,1
0,TLPause
0,Platform,15,346,61,0,120
0.4,BoneVRepeat,133,356,40,0,120,41,15
1.2,Platform,-61,346,61,0,150
1.7,Platform,-61,346,61,0,180
1,BoneV,133,257,45,0,210
0,BoneV,119,257,45,0,210
0,BoneV,105,257,45,0,210
2.3,BoneV,133,257,95,0,270
1.7,EndAttack
]==] },
  { name = "platforms2", csv = [==[
# platforms2 —— 蓝魂：58 根矮骨地毯（间距 15）持续压迫，同时从右侧连续送来 6 块平台
# 数据来源：BTS（jcw87/c2-sans-fight, GPL-3.0）Files/sans_platforms2.csv 逐行转写，数值未改。
# 坐标系：原版 640×480，Y 向下；战斗框参数为 (左, 上, 右, 下)。速度单位 px/s（= 原作值 ×30）。
0,CombatZoneResize,133,251,508,391,TLResume
0,HeartTeleport,320,376
0,HeartMode,1
0,TLPause
0,Platform,640,346,51,2,150
0.4,BoneVRepeat,508,356,40,2,120,58,15
0.4,Platform,640,296,51,2,150
0.5,Platform,640,346,51,2,150
0.4,BoneV,508,316,56,2,150
0.4,Platform,640,296,31,2,60
0.6,Platform,640,326,51,2,150
0.7,Platform,640,336,51,2,150
0.3,BoneV,508,257,45,2,150
0.4,Platform,640,316,51,2,150
0.3,BoneV,508,257,55,2,150
0.7,BoneV,508,257,35,2,150
1.5,BoneV,133,257,95,0,90
0.7,BoneV,508,276,96,2,240
2.5,EndAttack
]==] },
  { name = "platforms3", csv = [==[
# platforms3 —— 循环 16 次：从 3 个位置里随机挑一处弹出一根骨（RND + JMPREL 跳表），
#              两组 PlatformRepeat 提供持续移动的落脚点（右上 5 块向西、左下 4 块向东）
# 数据来源：BTS（jcw87/c2-sans-fight, GPL-3.0）Files/sans_platforms3.csv 逐行转写。
# 【2026-10-05 第十轮 · 用户口径】ROUND 10 有根「过不去的骨头」——两根吊顶/中段骨正好盖住了平台的
#   站立带（平台顶面 -SOUL_CLAMP-4..+4），站在平台上必被扫到、没有落脚点：
#     * 517,257,45 → 257..302 盖住 y=306 平台的站立带 294..302 → 高度 45 → **32**（257..289，让出 5px）
#     * 125,306,40 → 306..346 盖住 y=346 平台的站立带 334..342 → 高度 40 → **24**（306..330，让出 4px）
#   第十一轮补充：贴地骨 517,349,35 → **24**（349..373）—— 原高度压住地面站立带 379..387，
#   玩家说的「最后从右边过来的骨头没法躲」就是它；现在地面也让开了。
# 跳转沿用原作 1-based 行号（行号只数非注释行，故上方注释不影响）：JMPZ,22 → 第 22 行 EndAttack；
# JMPABS,8 → 第 8 行 JMPZ,22,$Loop（循环回跳）。
0,CombatZoneResize,133,251,508,391,TLResume
0,HeartTeleport,320,376
0,HeartMode,1
0,TLPause
0,PlatformRepeat,513,346,121,2,120,5,220
0,PlatformRepeat,-71,306,161,0,120,4,280
0,SET,Loop,16
0,JMPZ,22,$Loop
0,SUB,Loop,$Loop,1
0,RND,Jump,3
0,ADD,Jump,$Jump,1
0,JMPREL,$Jump
0,JMPREL,3
0,JMPREL,4
0,JMPREL,5
0,BoneV,517,257,45,2,120
0.5,JMPABS,8
0,BoneV,125,306,40,0,120
0.5,JMPABS,8
0,BoneV,517,349,35,2,120
0.5,JMPABS,8
0,EndAttack
]==] },
  { name = "platforms4", csv = [==[
# platforms4 —— 大框（113,231,548,391）蓝魂站上一块向东移动的平台（宽 41）
#              同时四组定向骨阵：右底 60 根向南、左 11 根向北、中 13 根向南、右 11 根向北
# 数据来源：BTS（jcw87/c2-sans-fight, GPL-3.0）同名 sans_*.csv 逐行转写。
# 【第十二轮】按仓库 readme.md「Known Issues」第 2 条：这块平台应当**从 0 加速到全速**，
#   旧实现一上来就是 90px/s。给 Platform 加第 8 个参数 Ramp=1（1 秒到全速），数值其余不动。
# 注意：原文件第 4 行 TLPause 后无 TLResume，靠第 1 行 CombatZoneResize 的 FinishAction 恢复脚本。
0,CombatZoneResize,113,231,548,391,TLResume
0,HeartTeleport,320,376
0,HeartMode,1
0,TLPause
0,Platform,151,336,41,0,90,1
0,HeartTeleport,175,327
# ↓ 恢复 BTS 原版参数（2026-10-05 第二轮：用户要求“优先学习参考仓库的代码制作攻击模式”）。
#   原来这里被改成“静止 29 根、只铺满框宽”，是为了绕开“骨墙 900px 横扫出框”；
#   现在 core 按 BTS 的 CombatZoneClipped 语义**把竖骨裁进战斗框**（见 core.lua 的 clipVZone），
#   所以 60 根 × 间距 15 的原版骨毯**保持原数值**也不会再画出框外 —— 数值不再改动。
0,BoneVRepeat,528,366,40,0,60,60,15
0,BoneVRepeat,283,267,40,3,90,11,85
0,BoneVRepeat,363,331,40,1,120,13,95
0,BoneVRepeat,443,248,40,3,90,11,85
7.3,EndAttack
]==] },
  { name = "platforms4hard", csv = [==[
# platforms4hard —— platforms4 的高难变体：平台更窄（31），三组骨阵的数量/间距/速度都加压
#                  （右底 60×15 不变；左侧 12 根间距 65、中列 11 根间距 90、右列 12 根间距 65）
# 数据来源：BTS（jcw87/c2-sans-fight, GPL-3.0）Files/sans_platforms4hard.csv 逐行转写，数值未改。
0,CombatZoneResize,113,231,548,391,TLResume
0,HeartTeleport,320,376
0,HeartMode,1
0,TLPause
0,Platform,151,336,31,0,90,1
0,HeartTeleport,175,327
# ↓ 恢复 BTS 原版参数（2026-10-05 第二轮：用户要求“优先学习参考仓库的代码制作攻击模式”）。
#   原来这里被改成“静止 29 根、只铺满框宽”，是为了绕开“骨墙 900px 横扫出框”；
#   现在 core 按 BTS 的 CombatZoneClipped 语义**把竖骨裁进战斗框**（见 core.lua 的 clipVZone），
#   所以 60 根 × 间距 15 的原版骨毯**保持原数值**也不会再画出框外 —— 数值不再改动。
0,BoneVRepeat,528,366,40,0,60,60,15
0,BoneVRepeat,283,268,40,3,90,12,65
0,BoneVRepeat,363,325,40,1,120,11,90
0,BoneVRepeat,443,268,40,3,90,12,65
7.3,EndAttack
]==] },
  { name = "randomblaster1", csv = [==[
# randomblaster1 —— 红魂：以灵魂为中心、半径 400×300 上取随机角度，炮口从该方向的圆周外飞入
#                  终点钳制到 [50,590]×[40,440]，循环 15 次；Size0、Spin 0.46666、Blast 仅 0.03333
# 数据来源：BTS（jcw87/c2-sans-fight, GPL-3.0）Files/sans_randomblaster1.csv 逐行转写，数值未改。
# 跳转沿用原作 1-based 行号（只数非注释行）：
#   JMPNL,21 / JMPNG,23 / JMPNL,25 / JMPNG,27 是四个边界钳制；JMPNZ,6 → 第 6 行 SUB,Loop,$Loop,1。
# 【2026-10-05 第十一轮 · 用户口径】ROUND 14：单个龙骨炮「出现花 1.5s，到发射再等 1s」——
#   SpinTime 0.46666 → **1.5**，并给本项目扩展的第 10 个参数 HoldTime 传 **1.0**（转到位后停 1s 再发射）；
#   循环次数 15 → 3（单发周期 1.5+1+0.03 ≈ 2.6s，3 发 ≈ 7.8s，落在 8s 回合内）。
0,CombatZoneResize,121,186,526,391,TLResume
0,HeartTeleport,320,304
0,HeartMode,0
0,TLPause
0.5,SET,Loop,15
0,SUB,Loop,$Loop,1
0,RND,Ang,360
0,COS,X,$Ang
0,SIN,Y,$Ang
0,MUL,EndX,$X,200
0,MUL,EndY,$Y,200
0,MUL,X,$X,400
0,MUL,Y,$Y,300
0,GetHeartPos,HeartX,HeartY
0,ADD,EndX,$EndX,$HeartX
0,ADD,EndY,$EndY,$HeartY
0,ADD,X,$X,$HeartX
0,ADD,Y,$Y,$HeartY
0,JMPNL,21,$EndX,50
0,SET,EndX,50
0,JMPNG,23,$EndX,590
0,SET,EndX,590
0,JMPNL,25,$EndY,40
0,SET,EndY,40
0,JMPNG,27,$EndY,440
0,SET,EndY,440
0,ANGLE,Ang,$EndX,$EndY,$HeartX,$HeartY
0,GasterBlaster,0,$X,$Y,$EndX,$EndY,$Ang,0.46666,0.83333,1.5,5
0.53333,JMPNZ,6,$Loop
# 【2026-10-06】同上：末尾留 2.2s 让最后一发走完 0.46666 + 1.5 + 0.03333
2.2,EndAttack
]==] },
  { name = "randomblaster2", csv = [==[
# randomblaster2 —— randomblaster1 的后期版本：炮更大（Size1）、蓄力更久（Spin 0.66666）
#                  循环 12 次（起手 0.4s、间隔 0.66666s），Blast 仍为 0.03333
# 数据来源：BTS（jcw87/c2-sans-fight, GPL-3.0）Files/sans_randomblaster2.csv 逐行转写，数值未改。
0,CombatZoneResize,121,186,526,391,TLResume
0,HeartTeleport,320,304
0,HeartMode,0
0,TLPause
0.4,SET,Loop,12
0,SUB,Loop,$Loop,1
0,RND,Ang,360
0,COS,X,$Ang
0,SIN,Y,$Ang
0,MUL,EndX,$X,200
0,MUL,EndY,$Y,200
0,MUL,X,$X,400
0,MUL,Y,$Y,300
0,GetHeartPos,HeartX,HeartY
0,ADD,EndX,$EndX,$HeartX
0,ADD,EndY,$EndY,$HeartY
0,ADD,X,$X,$HeartX
0,ADD,Y,$Y,$HeartY
0,JMPNL,21,$EndX,50
0,SET,EndX,50
0,JMPNG,23,$EndX,590
0,SET,EndX,590
0,JMPNL,25,$EndY,40
0,SET,EndY,40
0,JMPNG,27,$EndY,440
0,SET,EndY,440
0,ANGLE,Ang,$EndX,$EndY,$HeartX,$HeartY
0,GasterBlaster,1,$X,$Y,$EndX,$EndY,$Ang,0.66666,0.83333,1.5,5
0.66666,JMPNZ,6,$Loop
# 【2026-10-06】同上：末尾留 2.4s 让最后一发走完 0.66666 + 1.5 + 0.03333
2.4,EndAttack
]==] },
  { name = "sans_bluebone", csv = [==[
# sans_bluebone —— 蓝骨（Color 1，高 100）与白骨（Color 0，高 20）成对横穿
0,CombatZoneResize,133,251,508,391,TLResume
0,HeartTeleport,320,376
0,HeartMode,1
0,TLPause
0.2,BoneV,503,286,100,2,300,1
0.23333,BoneV,503,366,20,2,300,0
0.5,BoneV,503,286,100,2,300,1
0.23333,BoneV,503,366,20,2,300,0
0.5,BoneV,503,286,100,2,300,1
0.23333,BoneV,503,366,20,2,300,0
0.93333,BoneV,128,366,20,0,300,0
0.4,BoneV,128,286,100,0,300,1
0.33333,BoneV,128,366,20,0,300,0
0.4,BoneV,128,286,100,0,300,1
0.33333,BoneV,128,366,20,0,300,0
0.4,BoneV,128,286,100,0,300,1
1.66666,EndAttack
]==] },
  { name = "sans_bonegap1", csv = [==[
# sans_bonegap1 —— 宽矮框（375×140）**左右两侧各出一高一矮**，速度 180、间距 120
# 【2026-10-05 第六轮 · 用户口径】「左右高低骨进入的组合」→ **高骨为蓝骨（Color=1）**，矮骨保持白骨。
#   前四行的第 9 列就是 Color（本项目给 BoneVRepeat 加的向后兼容扩展；官方该命令没有 Color）。
#   高骨 32 高（严格低于 0.6s 跳跃高度 70px），且两行高骨都跟在两行矮骨后面 0.3s。
#   原版照抄（改前）：
#     0.2,BoneVRepeat,128,257,95,0,180,8,120
#     0,BoneVRepeat,128,366,20,0,180,8,120
#     0,BoneVRepeat,503,257,95,2,180,8,120
#     0,BoneVRepeat,503,366,20,2,180,8,120
#     6.4,EndAttack
0,CombatZoneResize,133,251,508,391,TLResume
0,HeartTeleport,320,376
0,HeartMode,1
0,TLPause
0.2,BoneVRepeat,128,366,20,0,180,8,120,0
0,BoneVRepeat,503,366,20,2,180,8,120,0
0.3,BoneVRepeat,128,257,32,0,180,8,120,1
0,BoneVRepeat,503,257,32,2,180,8,120,1
6.1,EndAttack
]==] },
  { name = "sans_bonegap1fast", csv = [==[
# sans_bonegap1fast —— 同 bonegap1，速度 210、间距 133、起手 0.4s
# 【2026-10-05 第六轮 · 用户口径】同上：**高骨为蓝骨（Color=1）**，矮骨白骨；高骨跟在矮骨后 0.3s。
#   原版照抄（改前）：
#     0.4,BoneVRepeat,128,257,95,0,210,8,133
#     0,BoneVRepeat,128,366,20,0,210,8,133
#     0,BoneVRepeat,503,257,95,2,210,8,133
#     0,BoneVRepeat,503,366,20,2,210,8,133
#     6,EndAttack
0,CombatZoneResize,133,251,508,391,TLResume
0,HeartTeleport,320,376
0,HeartMode,1
0,TLPause
0.4,BoneVRepeat,128,366,20,0,210,8,133,0
0,BoneVRepeat,503,366,20,2,210,8,133,0
0.3,BoneVRepeat,128,257,32,0,210,8,133,1
0,BoneVRepeat,503,257,32,2,210,8,133,1
5.7,EndAttack
]==] },
  { name = "sans_bonegap2", csv = [==[
# sans_bonegap2
# 【2026-10-05 第七轮】上下骨同列前进的「缝」太窄（18px，灵魂 8px 只剩 10px 可站）→ 把
#   HeightT = 111 - HeightB 改成 99 - HeightB，缝宽 18 → **30px**（可站 22px）。其余数值不动。 —— 从中心向两侧镜像飞出的骨缝（上下骨缝恒为 111 高），越来越快
# 用循环 + 标签实现：Total 累加控制横向间距，Choice 决定骨高与增量
0,CombatZoneResize,133,251,508,391,TLResume
0,HeartTeleport,320,376
0,HeartMode,1
0,TLPause
0,SET,Total,0
0,:Begin
0,JMPNL,End,$Total,150
0,RND,Choice,4
0,MUL,Jump,$Choice,3
0,ADD,Jump,$Jump,1
0,JMPREL,$Jump
0,SET,HeightB,20
0,ADD,Total,$Total,9
0,JMPREL,9
0,SET,HeightB,30
0,ADD,Total,$Total,11
0,JMPREL,6
0,SET,HeightB,40
0,ADD,Total,$Total,19
0,JMPREL,3
0,SET,HeightB,60
0,ADD,Total,$Total,25
0,RND,RndSpeed,3
0,SUB,RndSpeed,$RndSpeed,1
0,MUL,RndSpeed,$RndSpeed,2
0,JMPNE,SkipZeroSpeed,$HeightB,40
0,SET,RndSpeed,0
0,:SkipZeroSpeed
0,SUB,HeightT,99,$HeightB
0,SUB,YB,386,$HeightB
0,ADD,X,$Total,32
0,JMPNE,BoneL,$HeightB,60
0,SET,RndSpeed,-1
0,:BoneL
0,ADD,SpeedL,8,$RndSpeed
0,MUL,XL,$X,$SpeedL
0,SUB,XL,320,$XL
0,MUL,SpeedL,$SpeedL,30
0,JMPE,BoneR,$HeightB,60
0,MUL,RndSpeed,$RndSpeed,-1
0,:BoneR
0,ADD,SpeedR,8,$RndSpeed
0,MUL,XR,$X,$SpeedR
0,ADD,XR,320,$XR
0,MUL,SpeedR,$SpeedR,30
0,BoneV,$XL,257,$HeightT,0,$SpeedL
0,BoneV,$XL,$YB,$HeightB,0,$SpeedL
0,BoneV,$XR,257,$HeightT,2,$SpeedR
0,BoneV,$XR,$YB,$HeightB,2,$SpeedR
0,MUL,Jump,$Choice,2
0,ADD,Jump,$Jump,1
0,JMPREL,$Jump
0,ADD,Total,$Total,15
0,JMPREL,6
0,ADD,Total,$Total,17
0,JMPREL,4
0,ADD,Total,$Total,19
0,JMPREL,2
0,ADD,Total,$Total,25
0,JMPABS,Begin
0,:End
7,EndAttack
]==] },
  { name = "sans_boneslideh", csv = [==[
# sans_boneslideh —— 底部矮骨向东、上部高骨向西，速度 120、间距 76
# 【2026-10-05 第六轮 · 用户澄清】这一关的高骨**不是**蓝骨，恢复普通白骨：
#   用户原话：「round4 的上方不需要是蓝骨，我说的是**左右高低骨进入的组合**时高骨为蓝骨」。
#   「左右高低骨」= sans_bonegap1 / sans_bonegap1fast（左右两侧各自出一高一矮），蓝骨改在那边。
#   这里保持第四轮的两条口径：高骨 32 高（严格低于 0.6s 跳跃高度）、跟在矮骨后面 0.5s 进场。
0,CombatZoneResize,133,251,508,391,TLResume
0,HeartTeleport,320,376
0,HeartMode,1
0,TLPause
0.5,BoneVRepeat,128,366,20,0,120,8,76
0.5,BoneVRepeat,513,257,32,2,120,8,76
6.7,EndAttack
]==] },
  { name = "sans_boneslidev", csv = [==[
# sans_boneslidev —— 上下两组横向骨（宽 200）分别向南/向北，速度 300、间距 183
0,CombatZoneResize,241,226,406,391,TLResume
0,HeartTeleport,320,304
0,HeartMode,0
0,TLPause
0.2,BoneHRepeat,130,-10,200,1,300,7,183
0,BoneHRepeat,330,650,200,3,300,7,183
5.76666,EndAttack
]==] },
  { name = "sans_bonestab1", csv = [==[
# 【方案甲 A-9】本文件逐字抄自参考仓库 Files/sans_bonestab1.csv（原版 BoneStab 三档）
0,CombatZoneResize,241,226,406,391,TLResume
0,HeartTeleport,320,304
0,HeartMode,0
0,TLPause
0,SET,Loop,9
0,JMPZ,26,$Loop
0,SUB,Loop,$Loop,1
0,RND,Direction,4
0,ADD,Jump,$Direction,1
0,JMPREL,$Jump
0,JMPREL,4
0,JMPREL,5
0,JMPREL,6
0,JMPREL,7
0,SansBody,HandRight
0,JMPREL,7
0,SansBody,HandDown
0,JMPREL,5
0,SansBody,HandLeft
0,JMPREL,3
0,SansBody,HandUp
0,JMPREL,1
0.26666,SansSlam,$Direction
0.2,BoneStab,$Direction,9,1.2,0.33333
0.6,JMPABS,6
0,EndAttack
]==] },
  { name = "sans_bonestab2", csv = [==[
# 【方案甲 A-9】本文件逐字抄自参考仓库 Files/sans_bonestab2.csv（原版 BoneStab 三档）
0,CombatZoneResize,241,226,406,391,TLResume
0,HeartTeleport,320,304
0,HeartMode,0
0,TLPause
0,SET,Loop,9
0,JMPZ,26,$Loop
0,SUB,Loop,$Loop,1
0,RND,Direction,4
0,ADD,Jump,$Direction,1
0,JMPREL,$Jump
0,JMPREL,4
0,JMPREL,5
0,JMPREL,6
0,JMPREL,7
0,SansBody,HandRight
0,JMPREL,7
0,SansBody,HandDown
0,JMPREL,5
0,SansBody,HandLeft
0,JMPREL,3
0,SansBody,HandUp
0,JMPREL,1
0.26666,SansSlam,$Direction
0.2,BoneStab,$Direction,9,1.2,0.2
0.93333,JMPABS,6
0,EndAttack
]==] },
  { name = "sans_bonestab3", csv = [==[
# 【方案甲 A-9】本文件逐字抄自参考仓库 Files/sans_bonestab3.csv（原版 BoneStab 三档）
0,CombatZoneResize,241,226,406,391,TLResume
0,HeartTeleport,320,304
0,HeartMode,0
0,TLPause
# 【2026-10-06 用户口径·round22（内部 22 = HUD 23 = sans_bonestab3）】
#   「地面向上升起的骨头攻击」= BoneStab：骨墙太厚太密 → 削薄 + 降次数 + 每轮 +1s；
#   并把整条边切成 5 段、每隔 1 段留空 → **骨墙保留 2 个能钻过去的缺口**（lanes=5, gapEvery=2）。
#   dist 18 → 12（伸出更短、更细）；Loop 9 → 6（9 根降到 6 根）；周期 0.23333 → 1.23333。
0,SET,Loop,6
0,JMPZ,26,$Loop
0,SUB,Loop,$Loop,1
0,RND,Direction,4
0,ADD,Jump,$Direction,1
0,JMPREL,$Jump
0,JMPREL,4
0,JMPREL,5
0,JMPREL,6
0,JMPREL,7
0,SansBody,HandRight
0,JMPREL,7
0,SansBody,HandDown
0,JMPREL,5
0,SansBody,HandLeft
0,JMPREL,3
0,SansBody,HandUp
0,JMPREL,1
0.26666,SansSlam,$Direction
# 【2026-10-06 二次口径】尺寸再减半 dist 18→9、出现 warn 0.4→1.2、升起 out 0.22→1.02
0,BoneStab,$Direction,9,1.2,0.25
1.23333,JMPABS,6
0,EndAttack
]==] },
  { name = "sans_intro", csv = [==[
# sans_intro —— 回合 0「不意打ち」
# 【2026-10-05 第九轮 · 用户口径】首轮（sans_intro）全部龙骨炮的「出现 → 释放」间隔 = **1.0s**：
#   SpinTime 0.333（Size1）/ 0.666（Size2）→ **1.0**（第六轮先改 0.6，第九轮再加到 1.0）；BlastTime 按原版不变。
#   只在 SpinTime 这一列做了改动，其余数值与下面「原版对照」逐字一致。
# 数值（时序 / 坐标 / 参数）按参考实现逐字转写以保证保真；文件文本为本项目自行编排。
# 坐标系：原版 640×480，Y 向下。战斗框参数为 (左, 上, 右, 下)。
# 唯一的**有意偏离**：第 3 段龙骨炮由原版的"第 1 段重复"改成「上下」（见该段前的注释与文末原文对照）。
# 序列：黑屏闪 → 框 165×165 → SansSlam → BoneStab(自上而下) → SineBones(20,-24,360,25)
#       → ① 十字 → ② 交叉 → ③ 上下 → ④ 左右(Size2) → "here we go." → EndAttack
# 注意（2026-10-05 调整）：四组龙骨炮之间的间隔各 +0.1s（用户验收「初见杀龙骨炮间隔略微延长」）——脚本全长 8.93s，回合时长必须覆盖它（core 的 startEnemy 已按脚本时长延长 enemyDur），
#       否则回合会在 2.8s 掐断，①②③④ 一段都打不出来。
0,SansAnimation
0,SansHead,ClosedEyes
0,SansText,ready?
0,BlackScreen,1
0,Sound,Flash
0.06666,BlackScreen,0
0,Sound,Flash
0,CombatZoneResizeInstant,239,226,404,391
0,HeartTeleport,320,304
0,HeartMode,0
0,SansBody,HandDown
0,SansHead,BlueEye
0,Sound,GasterBlaster
0.26666,SansSlam,1
0.5,SansBody,HandUp
0,SansHead,NoEyes
0,BoneStab,1,54,0.16666,1
0.7,HeartMode,0
0,SansBody,HandRight
0,Sound,Ding
0.4,Sound,GasterBlaster
0.4,SineBones,20,-24,360,25
1.2,SansAnimation
0,GasterBlaster,1,0,0,189,246,0,1,0.26666
0,GasterBlaster,1,0,0,259,166,90,1,0.26666
0,GasterBlaster,1,640,480,449,366,180,1,0.26666
0,GasterBlaster,1,640,480,379,446,270,1,0.26666
1.0,GasterBlaster,1,0,0,189,176,45,1,0.26666
0,GasterBlaster,1,640,0,449,176,135,1,0.26666
0,GasterBlaster,1,640,480,449,436,225,1,0.26666
0,GasterBlaster,1,0,480,189,436,315,1,0.26666
# ↓ 第 3 段：上下（本次按用户验收描述改；BTS 原版这里是与第 1 段**逐字重复**的第 3 组"十字"，
#   原行保留在文件末尾的注释里，数值一个没丢）。四发的参数全部取自本文件既有的原版值：
#   起点 (0,0)/(640,0)/(0,480)/(640,480) 与第 2 段相同；落点 x=259/379、y=166/446 与第 1 段相同；
#   角度 90=南（向下）、270=北（向上）；SpinTime/BlastTime 与 Size1 各段相同。
#   效果：x=259 与 x=379 两条全高光柱，各自上下对射 → 中间 x≈277..361 留一条可躲的缝。
1.0,GasterBlaster,1,0,0,259,166,90,1,0.26666
0,GasterBlaster,1,640,0,379,166,90,1,0.26666
0,GasterBlaster,1,0,480,259,446,270,1,0.26666
0,GasterBlaster,1,640,480,379,446,270,1,0.26666
0.8,GasterBlaster,2,0,240,139,306,0,1,0.5
0,GasterBlaster,2,640,240,499,306,180,1,0.5
3,SansHead,Default
0,SansText,here we go.
0,EndAttack
# ---------------------------------------------------------------- 原版对照（BTS 逐字原文）
# 上面第 3 段那 4 行在 BTS `Files/sans_intro.csv` 里是**与第 1 段逐字重复**的（已用
#   https://raw.githubusercontent.com/Jcw87/c2-sans-fight/master/Files/sans_intro.csv 逐字节比对），
# 即原版的龙骨炮是「十字 → 交叉 → 十字(重复) → 左右(Size2)」。按用户验收描述改成「十字 → 交叉 → 上下」，
# 被替换掉的原版 4 行原样保留在这里，随时可以换回来：
# 0.9,GasterBlaster,1,0,0,189,246,0,0.333,0.26666
# 0,GasterBlaster,1,0,0,259,166,90,0.333,0.26666
# 0,GasterBlaster,1,640,480,449,366,180,0.333,0.26666
# 0,GasterBlaster,1,640,480,379,446,270,0.333,0.26666
# 其余行（含 Size2 的「左右」收尾）与 BTS 原文逐字一致。
# 注意：上面正文里的 SpinTime 已按用户口径改成 0.6（原版 0.333 / 0.666）。
]==] },
  { name = "sans_spare", csv = [==[
# sans_spare —— 饶恕时用的空攻击：蓝魂、宽矮框、0.3s 后结束
0,CombatZoneResize,133,251,508,391,TLResume
0,HeartTeleport,320,376
0,HeartMode,1
0,TLPause
0.3,EndAttack
]==] },
  { name = "spiral1", csv = [==[
# spiral1 —— 螺旋龙骨炮 · 轻档（内部回合 17，HUD 显示 ROUND 18 / 20）
# 几何逐字取自原作 sans_final.csv 阶段④「旋转光束」：中心 (320,306)、Ang = -10·gt、
#   半径 150→450（炮身在外圈 450、光束指向内侧）、SpinTime 0.5、BlastTime 0（瞬发）。
#   位移公式一字未改：EndX/EndY = 单位向量×150，X/Y = 同一方向×450。
# 三档螺旋**只改**「总转角上限 gt」「角速度增量上限 gin」「每发间隔」：
#   spiral1  gt→140 / gin→1.40 / 0.09s     （框 305 宽，实测 103 发）
#   spiral2  gt→160 / gin→1.70 / 0.075s    （框 237 宽，实测 104 发）
#   spiral3  gt→190 / gin→1.70 / 0.06666s  （= 原作强度，实测 122 发，接原作阶段⑤力竭）
# 发数是 core_selftest 的「全部脚本空跑」实测值（`实体：… 龙骨炮 N`），不是估算。
# 光束判定是"从炮身沿 ang 射 2000px"的整条 AABB（core 的 GasterBlaster 判定），
# 所以光束会**穿过框中心**：玩家要躲在两束光之间的缝里，而不是站在中间不动。
# 框给 305 宽（比原版阶段④的 165 宽），轻档留出更多走位空间。
0,CombatZoneResize,171,226,476,391,TLResume
0,HeartTeleport,320,306
0,HeartMode,0
0,TLPause
0,SansHead,BlueEye
0,SansX,320
0,Sound,GasterBlaster
0,SET,gt,0
0,SET,gin,1
0,:Loop
0,MUL,Ang,$gt,-10
0,COS,X,$Ang
0,SIN,Y,$Ang
0,MUL,EndX,$X,150
0,MUL,EndY,$Y,150
0,MUL,X,$EndX,3
0,MUL,Y,$EndY,3
0,ADD,X,$X,320
0,ADD,Y,$Y,306
0,ADD,EndX,$EndX,320
0,ADD,EndY,$EndY,306
0,ADD,Ang,$Ang,180
0,GasterBlaster,0,$X,$Y,$EndX,$EndY,$Ang,0.5,0,0,5
0,ADD,gt,$gt,$gin
0,JMPNL,Tail,$gin,1.4
0,ADD,gin,$gin,0.02
0,:Tail
0.09,JMPL,Loop,$gt,140
0,SansHead,Default
0,EndAttack
]==] },
  { name = "spiral2", csv = [==[
# spiral2 —— 螺旋龙骨炮 · 中档（内部回合 18，HUD 显示 ROUND 19 / 20）
# 与 spiral1 同一套几何（原作阶段④），参数收到更接近原作：gt→160 / gin→1.70 / 0.015 / 0.075s，
# 框缩到 237 宽 —— 每发转角更大（10·gin 度）、间隔更短、走位空间更小。
0,CombatZoneResize,205,226,442,391,TLResume
0,HeartTeleport,320,306
0,HeartMode,0
0,TLPause
0,SansHead,BlueEye
0,SansX,320
0,Sound,GasterBlaster
0,SET,gt,0
0,SET,gin,1
0,:Loop
0,MUL,Ang,$gt,-10
0,COS,X,$Ang
0,SIN,Y,$Ang
0,MUL,EndX,$X,150
0,MUL,EndY,$Y,150
0,MUL,X,$EndX,3
0,MUL,Y,$EndY,3
0,ADD,X,$X,320
0,ADD,Y,$Y,306
0,ADD,EndX,$EndX,320
0,ADD,EndY,$EndY,306
0,ADD,Ang,$Ang,180
0,GasterBlaster,0,$X,$Y,$EndX,$EndY,$Ang,0.5,0,0,5
0,ADD,gt,$gt,$gin
0,JMPNL,Tail,$gin,1.7
0,ADD,gin,$gin,0.015
0,:Tail
0.075,JMPL,Loop,$gt,160
0,SansHead,Default
0,EndAttack
]==] },
  { name = "spiral3", csv = [==[
# spiral3 —— 螺旋龙骨炮 · 原作强度（内部回合 19 = 最后一回合，HUD 显示 ROUND 20 / 20）
# 阶段 A：原作 sans_final.csv 阶段④「旋转光束」**逐字**参数（gt→190 / gin 1→1.7 每次 +0.015 /
#        每发 0.06666s / Ang = -10·gt / 半径 150→450 / SpinTime 0.5 / BlastTime 0），
#        框也用原版阶段③留下的 165×165（(239,226)-(404,391)）。
# 阶段 B：原作阶段⑤「力竭」段（sans_final.csv 行 157-213）逐字转写 ——
#        38 次砸击、SansSlamDamage 1（真的掉血）、Wait 递减、I=25 冒汗 / I=33 出现 Tired1 /
#        I=35 强制朝北 / I=36 起 Tired2（MaxFallSpeed 只剩 60）→ 最后 SansAnimation Tired。
# 唯一改动：原作用的是**数字行号**跳转，这里插了标签行，行号会整体平移，
#        所以把所有 JMP* 的数字目标换成等价标签（JMPREL 是相对偏移，原样保留）。
# 跳转目标对照（原行号 → 本文件标签，全部按"标签落在原行号那一行"放置）：
#   166→SlamLoop  168→DirClampA  170→DirClampB  172→Dispatch  186→RandDir
#   187→AfterRand 191→T21        194→T25        200→T33       203→T33b
#   206→T35       210→T36
0,CombatZoneResize,241,226,406,391,TLResume
0,HeartTeleport,320,306
0,HeartMode,0
0,TLPause
0,SansHead,BlueEye
0,SansX,320
0,Sound,GasterBlaster
0,SET,gt,0
0,SET,gin,1
0,:Loop
0,MUL,Ang,$gt,-10
0,COS,X,$Ang
0,SIN,Y,$Ang
0,MUL,EndX,$X,150
0,MUL,EndY,$Y,150
0,MUL,X,$EndX,3
0,MUL,Y,$EndY,3
0,ADD,X,$X,320
0,ADD,Y,$Y,306
0,ADD,EndX,$EndX,320
0,ADD,EndY,$EndY,306
0,ADD,Ang,$Ang,180
0,GasterBlaster,0,$X,$Y,$EndX,$EndY,$Ang,0.5,0,0,5
0,ADD,gt,$gt,$gin
0,JMPNL,Tail,$gin,1.7
0,ADD,gin,$gin,0.015
0,:Tail
0.06666,JMPL,Loop,$gt,190
1,SansHead,BlueEye
0,HeartMaxFallSpeed,750
0,SansBody,HandRight
0,SansSlamDamage,1
0,SET,I,0
0,SET,Direction,0
0,SET,LastDir,2
0,SET,Wait1,0.13333
0,SET,Wait2,0.13333
0,:SlamLoop
0,JMPNE,DirClampA,$Direction,$LastDir
0,SUB,Direction,$Direction,2
0,:DirClampA
0,JMPNL,DirClampB,$Direction,0
0,ADD,Direction,$Direction,4
0,:DirClampB
0,JMPL,Dispatch,$Direction,4
0,SUB,Direction,$Direction,4
0,:Dispatch
0,MUL,Jump,$Direction,2
0,ADD,Jump,$Jump,1
0,JMPREL,$Jump
0,SansBody,HandRight
0,JMPREL,6
0,SansBody,HandDown
0,JMPREL,4
0,SansBody,HandLeft
0,JMPREL,2
0,SansBody,HandUp
$Wait1,SansSlam,$Direction
$Wait2,SET,LastDir,$Direction
0,MOD,Odd,$I,2
0,JMPZ,AfterRand,$Odd
0,:RandDir
0,RND,Direction,4
0,:AfterRand
0,JMPNE,T21,$I,21
0,HeartMaxFallSpeed,480
0,SET,Wait1,0.2
0,SET,Wait2,0.2
0,:T21
0,JMPNE,T25,$I,25
0,SansHead,Default
0,SansSweat,1
0,:T25
0,JMPNE,T33,$I,33
0,SansHead,Tired1
0,SansSweat,2
0,HeartMaxFallSpeed,330
0,SET,Wait1,0.5
0,SET,Wait2,1.1
0,:T33
0,JMPNE,T33b,$I,33
0,JMPE,RandDir,$Direction,1
0,JMPE,RandDir,$Direction,$LastDir
0,:T33b
0,JMPNE,T35,$I,35
0,HeartMaxFallSpeed,240
0,SET,Direction,3
0,:T35
0,JMPNE,T36,$I,36
0,SansHead,Tired2
0,SansSweat,3
0,HeartMaxFallSpeed,60
0,:T36
0,ADD,I,$I,1
0,JMPL,SlamLoop,$I,38
1.5,SansAnimation,Tired
2.4,EndAttack
]==] },
}

return M
