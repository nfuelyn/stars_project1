package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = M.DT
local IDLE = {}
local g = M.newGame({ scripts = A, hp = 1000000 })
g:startEnemyScript('platforms1')
for i = 1, 120 do M.update(g, IDLE, DT) end
local pf = g.world.platforms[1]
print('platforms count = ' .. #g.world.platforms .. '  first = ' .. tostring(pf and (pf.x .. ',' .. pf.y .. ' w=' .. pf.w)))
if not pf then os.exit(0) end
pf.speed = 0; pf.vx, pf.vy = 0, 0            -- 冻结
local px, py = pf.x - 240, pf.y - 226
g.soul.x, g.soul.y = px + pf.w / 2, py - 8
g.prevX, g.prevY = g.soul.x, g.soul.y
for i = 1, 8 do M.update(g, IDLE, DT) end
print(string.format('站在空中板子上: y=%.1f 板面=%.1f grounded=%s jumping=%s',
  g.soul.y, py, tostring(g.soul.grounded), tostring(g.soul.jumping)))

M.update(g, { confirm = true }, DT)
print(string.format('第1跳后: vy=%.1f jumping=%s grounded=%s', g.soul.vy, tostring(g.soul.jumping), tostring(g.soul.grounded)))

local landedFrame = nil
for i = 1, 200 do
  M.update(g, {}, DT)
  if g.soul.grounded and i > 2 then landedFrame = i break end
end
print(string.format('落回板子: frame=%s y=%.1f grounded=%s jumping=%s',
  tostring(landedFrame), g.soul.y, tostring(g.soul.grounded), tostring(g.soul.jumping)))

M.update(g, { confirm = true }, DT)
print(string.format('第2跳后: vy=%.1f jumping=%s grounded=%s   ← 若 vy>=0 且 jumping=true 即复现',
  g.soul.vy, tostring(g.soul.jumping), tostring(g.soul.grounded)))
