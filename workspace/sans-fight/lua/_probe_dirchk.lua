package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local g = M.newGame({ scripts = A, hp = 92 })
g:startEnemyScript('sans_boneslideh')
print('world.heart.dir 初值 = ' .. tostring(g.world and g.world.heart.dir))
for i = 1, 20 do M.update(g, {}, M.DT) end
print(string.format('20 帧后: soul.dir=%s heart.dir=%s grounded=%s y=%.1f mode=%s',
  tostring(g.soul.dir), tostring(g.world.heart.dir), tostring(g.soul.grounded), g.soul.y, tostring(g.soul.mode)))
