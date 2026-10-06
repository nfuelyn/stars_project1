package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local g = M.newGame({ scripts = A, hp = 1000000 })
g:startEnemy(23)
local t, seen, first = 0, 0, nil
while g.state == 'enemy' and t < 60 do
  M.update(g, {}, M.DT); t = t + M.DT
  if #(g.walls or {}) > 0 then seen = seen + 1; if not first then first = t end end
end
print(string.format('round24: 骨墙出现的帧数 = %d，首次 t=%.2f', seen, first or -1))
