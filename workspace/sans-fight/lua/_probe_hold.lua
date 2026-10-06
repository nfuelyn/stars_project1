package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = M.DT
local g = M.newGame({ scripts = A, hp = 1000000 })
g:startEnemy(8)
local t = 0
local logged = 0
while g.state == 'enemy' and t < 4 do
  M.update(g, {}, DT); t = t + DT
  local w = g.world
  if w then
    for _, b in ipairs(w.blasters) do
      if logged < 20 then
        print(string.format('  t=%.3f state=%-9s g.t=%.3f spin=%s hold=%s blast=%s band=%.1f',
          t, tostring(b.state), b.t, tostring(b.spin), tostring(b.hold), tostring(b.blast), b.band or -1))
        logged = logged + 1
      end
    end
  end
end
