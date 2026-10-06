package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = 1 / 30
local g = M.newGame({ scripts = A, hp = 1000000, seed = 20260927 })
g:startEnemy(23)
local t = 0
while g.state == 'enemy' and t < 11.6 do
  M.update(g, {}, DT); t = t + DT
  if t >= 10.3 and t <= 11.4 then
    local s = g.soul
    print(string.format('t=%.3f pc=%3d maxFall=%-6s dir=%s vx=%8.1f vy=%6.1f x=%7.1f',
      t, g.world and g.world.pc or -1, tostring(s.maxFall), tostring(s.dir), s.vx or 0, s.vy or 0, s.x))
  end
end
