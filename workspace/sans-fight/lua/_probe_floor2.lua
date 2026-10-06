package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
for _, n in ipairs({ 0, 5, 23 }) do
  local g = M.newGame({ scripts = A, hp = 1000000 })
  g:startEnemy(n)
  local t, w1, w2, mx = 0, 0, 0, 0
  while g.state == 'enemy' and t < 12 do
    M.update(g, {}, M.DT); t = t + M.DT
    local nw = #(g.waves or {})
    if nw > 0 then w1 = w1 + 1 end
    if nw > mx then mx = nw end
  end
  print(string.format('内部 %2d（%s）: g.waves 活跃帧=%d, 峰值个数=%d', n, tostring(g.roundScript), w1, mx))
end
