package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = M.DT
for _, diff in ipairs({ 'original', 'normal' }) do
  local g = M.newGame({ scripts = A, hp = 1000000, difficulty = diff })
  g:startEnemy(8)
  local t, n, settle, prev = 0, 0, {}, {}
  local out = {}
  while g.state == 'enemy' and t < 8 do
    M.update(g, {}, DT); t = t + DT
    local w = g.world
    if w then
      for _, b in ipairs(w.blasters) do
        if prev[b] ~= b.state then
          if b.state == 'spinning' then n = n + 1; b.__id = n; settle[n] = t end
          if b.state == 'fire' and b.__id and settle[b.__id] then
            out[#out+1] = string.format('%.3f', t - settle[b.__id]); settle[b.__id] = nil
          end
          prev[b] = b.state
        end
      end
    end
  end
  print(string.format('diff=%-9s 落定->开火: %s  回合长 %.1fs', diff, table.concat(out, ' / '), t))
end
