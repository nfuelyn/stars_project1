package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = 1 / 30
local g = M.newGame({ scripts = A, hp = 1000000, seed = 20260927 })
g:startEnemy(23)
local t, next = 0, 3.0
while g.state == 'enemy' and t < 15 do
  M.update(g, {}, DT); t = t + DT
  if t >= next then
    local s = g.soul
    print(string.format('t=%5.2f dir=%s mode=%-5s maxFall=%-6s x=%7.1f vx=%7.1f box=[%6.1f..%6.1f] slammed=%s',
      t, tostring(s.dir), tostring(s.mode), tostring(s.maxFall), s.x, s.vx or 0,
      g.box.x, g.box.x + g.box.w, tostring(s.slammed)))
    next = next + 0.5
  end
end
