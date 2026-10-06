package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = M.DT
local g = M.newGame({ scripts = A, hp = 1000000 })
g:startEnemy(8)
local t = 0
while g.state == 'enemy' and t < 1.6 do
  M.update(g, {}, DT); t = t + DT
  local w = g.world
  if w and w.blasters[1] then
    local b = w.blasters[1]
    if b.state ~= 'spin' then
      print(string.format('  t=%.3f state=%-9s g.t=%.3f', t, tostring(b.state), b.t))
    end
  end
end
