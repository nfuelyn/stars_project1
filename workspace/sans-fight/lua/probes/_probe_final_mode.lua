package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = 1/30
local g = M.newGame({ scripts = A, hp = 1000000, seed = 20260927 })
g:startEnemy(23)
local t = 0
while g.state == 'enemy' and t < 60 do
  M.update(g, {}, DT); t = t + DT
  local persistent = 0
  if g.world then for _, b in ipairs(g.world.blasters or {}) do if b.persistent then persistent = persistent + 1 end end end
  if persistent > 0 then
    local soulMode = nil
    for _, c in ipairs(M.render(g)) do if c.kind == 'soul' then soulMode = c.mode end end
    print(string.format('t=%.3f persistent=%d core=%s render=%s dir=%s', t, persistent, tostring(g.soul.mode), tostring(soulMode), tostring(g.soul.dir)))
    break
  end
end
