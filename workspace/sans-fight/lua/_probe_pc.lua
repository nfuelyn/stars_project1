package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = 1 / 30
local g = M.newGame({ scripts = A, hp = 1000000, seed = 20260927 })
g:startEnemy(23)
print('roundScript = ' .. tostring(g.roundScript) .. '  prog 行数 = ' .. #(g.world and g.world.prog or {}))
local t, next = 0, 0.5
while g.state == 'enemy' and t < 12 do
  M.update(g, {}, DT); t = t + DT
  if t >= next then
    local w = g.world
    local line = w and w.prog[w.pc + 1]
    print(string.format('t=%5.2f pc=%3d cmd=%-22s boxW=%6.1f maxFall=%-6s dir=%s',
      t, w and w.pc or -1, line and tostring(line.cmd or line.target or '?') or '-',
      g.box.w, tostring(g.soul.maxFall), tostring(g.soul.dir)))
    next = next + 1.0
  end
end
