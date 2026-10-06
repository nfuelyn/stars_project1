package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = M.DT
local g = M.newGame({ scripts = A, hp = 1000000 })
g:startEnemy(8)
local t = 0
local settleAt, fireAt = {}, {}
local prevState = {}
local n = 0
while g.state == 'enemy' and t < 6 do
  M.update(g, {}, DT); t = t + DT
  local w = g.world
  if w then
    for _, b in ipairs(w.blasters) do
      if prevState[b] ~= b.state then
        if b.state == 'spinning' then
          n = n + 1; b.__id = n; settleAt[n] = t
          print(string.format('  #%d 落定 t=%.3f (spin=%s hold=%s)', n, t, tostring(b.spin), tostring(b.hold)))
        elseif b.state == 'fire' and b.__id then
          fireAt[b.__id] = t
          print(string.format('  #%d 开火 t=%.3f  落定后 %.3f s', b.__id, t, t - settleAt[b.__id]))
        end
        prevState[b] = b.state
      end
    end
  end
end
