package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = M.DT
local g = M.newGame({ scripts = A, hp = 1000000 })
g:startEnemyScript('sans_bonegap1')
for i = 1, 90 do M.update(g, {}, DT) end
print(string.format('起跳前: y=%.2f grounded=%s mode=%s box.h=%d jumpHeld=%s',
  g.soul.y, tostring(g.soul.grounded), tostring(g.soul.mode), g.box.h, tostring(g.jumpHeld)))
M.jump(g)
print(string.format('jump() 后: vy=%.1f jumping=%s', g.soul.vy, tostring(g.soul.jumping)))
for i = 1, 24 do
  M.update(g, { jumpHeld = true }, DT)
  print(string.format('  f%02d y=%7.2f vy=%7.1f heldT=%.3f jumping=%s grounded=%s cut=%s',
    i, g.soul.y, g.soul.vy, g.soul.jumpHeldT or -1, tostring(g.soul.jumping), tostring(g.soul.grounded), tostring(g.soul.jumpCut)))
end
