package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = M.DT
local g = M.newGame({ scripts = A, hp = 1000000 })
g:startEnemyScript('platforms4')
for i = 1, 80 do M.update(g, {}, DT) end
local b
for _, x in ipairs(g.world.bones) do if x.vx ~= 0 then b = x break end end
if not b then print('no moving bone'); return end
local x0 = b.x
for i = 1, 30 do M.update(g, {}, DT) end
local dx = b.x - x0
print(string.format('bone vx=%.0f  30 帧(1.0s) 实测位移 %.1f px', b.vx, dx))
local pf = g.world.platforms[1]
if pf then
  local p0 = pf.x
  for i = 1, 30 do M.update(g, {}, DT) end
  print(string.format('platform speed=%.0f  30 帧(1.0s) 实测位移 %.1f px', pf.speed or -1, pf.x - p0))
end
