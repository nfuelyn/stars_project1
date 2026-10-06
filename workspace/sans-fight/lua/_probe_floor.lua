package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local g = M.newGame({ scripts = A, hp = 1000000 })
g:startEnemy(23)
local t, floorFrames = 0, 0
while g.state == 'enemy' and t < 20 do
  M.update(g, {}, M.DT); t = t + M.DT
  if #(g.wavesAlive or {}) > 0 then floorFrames = floorFrames + 1 end
end
print('round24 内置地板骨活跃帧数 = ' .. floorFrames)
