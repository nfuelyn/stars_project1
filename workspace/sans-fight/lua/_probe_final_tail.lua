package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = M.DT
local g = M.newGame({ scripts = A, hp = 1000000 })
g:startEnemyScript('final')
g.state = 'enemy'; g.enemyDur = 1e9
local last = -1
for i = 1, math.floor(60 * 60) do
  M.update(g, {}, DT)
  local t = i * DT
  if t - last >= 0.5 then
    last = t
    local s = g.soul
    -- 是否处于"持续光束"（旋转龙骨炮阶段）
    local beam = false
    if g.world then for _, b in ipairs(g.world.blasters) do if b.persistent then beam = true end end end
    print(string.format('t=%5.1f mode=%-4s dir=%s maxFall=%s slammed=%-5s vx=%7.1f vy=%7.1f y=%6.1f %s',
      t, tostring(s.mode), tostring(s.dir), tostring(s.maxFall), tostring(s.slammed),
      s.vx or 0, s.vy or 0, s.y, beam and '◀持续光束(旋转龙骨炮)' or ''))
  end
  if g.world and g.world.ended then break end
end
