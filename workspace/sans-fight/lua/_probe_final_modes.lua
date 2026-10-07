package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = M.DT
local g = M.newGame({ scripts = A, hp = 1000000 })
g:startEnemyScript('final'); g.state = 'enemy'; g.enemyDur = 1e9
local prev = nil
for i = 1, math.floor(60*60) do
  M.update(g, {}, DT)
  local s = g.soul
  if s.mode ~= prev then
    print(string.format('t=%5.2f  模式切换 → %-4s  maxFall=%s  y=%.1f', i*DT, tostring(s.mode), tostring(s.maxFall), s.y))
    prev = s.mode
  end
  if g.world and g.world.ended then break end
end
