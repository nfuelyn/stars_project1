package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = M.DT
local g = M.newGame({ scripts = A, hp = 1000000 })
g:startEnemyScript('sans_bonegap1')          -- 蓝魂、无平台
for i = 1, 30 do M.update(g, {}, DT) end
print(string.format('地面: y=%.1f grounded=%s jumping=%s', g.soul.y, tostring(g.soul.grounded), tostring(g.soul.jumping)))
M.update(g, { confirm = true, jumpHeld = true }, DT)
print(string.format('第1跳: vy=%.1f jumping=%s', g.soul.vy, tostring(g.soul.jumping)))
for i = 1, 200 do
  M.update(g, { jumpHeld = false }, DT)
  if g.soul.grounded and i > 2 then print(string.format('落回地面: frame=%d grounded=%s jumping=%s', i, tostring(g.soul.grounded), tostring(g.soul.jumping))) break end
end
M.update(g, { confirm = true, jumpHeld = true }, DT)
print(string.format('第2跳: vy=%.1f jumping=%s  ← 地面能连跳则 vy<0', g.soul.vy, tostring(g.soul.jumping)))
