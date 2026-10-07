package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
-- 直接比较：同一脚本骨，在不同难度下的 vx，以及同一段延时的用时
local csv = '0,CombatZoneResizeInstant,121,276,526,391\n0,HeartMode,1\n0,BoneVRepeat,128,341,45,0,240,4,16\n2,EndAttack\n'
for _, key in ipairs({ 'easy', 'normal', 'hard', 'original' }) do
  local tune = M.DIFFS[key]
  local w = M.newWorld({ seed = 1, script = M.parseCSV(csv), tune = tune })
  w:update(M.DT)
  local b = w.bones[1]
  -- 段延时是否被缩放：考察 stepScript 里 wait 的推进
  local w2 = M.newWorld({ seed = 1, script = M.parseCSV(csv), tune = tune })
  local t = 0
  while not w2.ended and t < 10 do w2:update(M.DT); t = t + M.DT; if #w2.bones == 0 then break end end
  print(string.format('%-9s tune.speed=%.2f tune.interval=%.2f  首骨 vx=%6.1f   2s 延时实际用时=%.2fs',
    key, tune.speed, tune.interval, b and b.vx or 0, t))
end
