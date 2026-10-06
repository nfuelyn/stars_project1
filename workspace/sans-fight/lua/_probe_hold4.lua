package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = M.DT
local g = M.newGame({ scripts = A, hp = 1000000 })
g:startEnemy(8)
local t, n, settle, prev = 0, 0, {}, {}
while g.state == 'enemy' and t < 8 do
  M.update(g, {}, DT); t = t + DT
  local w = g.world
  if w then
    for _, b in ipairs(w.blasters) do
      if prev[b] ~= b.state then
        if b.state == 'spinning' then n = n + 1; b.__id = n; settle[n] = t end
        if b.state == 'fire' and b.__id and settle[b.__id] then
          print(string.format('  #%d 落定 t=%.3f -> 开火 t=%.3f  实测 %.3f s  (hold=%s, g.t=%.3f)',
            b.__id, settle[b.__id], t, t - settle[b.__id], tostring(b.hold), b.t))
          settle[b.__id] = nil
        end
        prev[b] = b.state
      end
    end
  end
end
