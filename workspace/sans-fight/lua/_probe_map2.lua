package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local g = M.newGame({ scripts = A, hp = 92 })
local desc = {
  sans_intro='见面杀（黑屏闪 → 框 165 → SansSlam → BoneStab → 正弦骨 → 4 组龙骨炮）',
  sans_bonegap1='左右高低骨缝（高骨是蓝骨）', sans_bluebone='蓝/白成对横穿',
  sans_bonegap2='上下同列骨缝', platforms1='平台 + 骨阵', platforms2='平台 + 骨阵',
  platforms3='平台 + 骨阵', platforms4='大框平台 + 四组定向骨阵',
  platformblaster='双平台间躲龙骨炮', platforms4hard='platforms4 高难变体',
  sans_bonegap1fast='高低骨缝（加速）', sans_boneslideh='横向滑骨',
  sans_spare='★ 饶恕/中场演出（无弹幕）', multi1='多段随机攻击组（基础 5 选 1）',
  randomblaster1='随机方向龙骨炮（Size0）', multi2='多段随机攻击组（后半场）',
  sans_bonestab1='骨刺三档①（骨墙从框边升起）', sans_bonestab2='骨刺三档②',
  randomblaster2='随机方向龙骨炮（Size1）', sans_boneslidev='上下滑骨',
  multi3='多段随机攻击组（最长，9 选 1）', sans_bonestab3='骨刺三档③',
  final='★ 终盘 sans_final（四阶段 + 睡意演出，约 53s）',
}
print('HUD   内部   脚本                 说明')
for n = 0, 23 do
  local s = tostring(M.scriptForRound(g, n))
  print(string.format('%3d   %3d    %-20s %s', n + 1, n, s, desc[s] or ''))
end
