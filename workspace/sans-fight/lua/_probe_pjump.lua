if type(_G.LUA_ROOT) == 'string' then
  package.path = _G.LUA_ROOT .. '/?.lua;' .. _G.LUA_ROOT .. '/lua/?.lua;' .. package.path
end
local M = require('core')
local A = require('attacks')
local DT = M.DT
local g = M.newGame({ scripts = A })
g:startEnemyScript('platforms1')
for i=1,200 do M.update(g, {}, DT) end
-- 手动把灵魂放到第一块平台顶面
local pf = g.world.platforms[1]
if not pf then for _,p in ipairs(g.world.platforms) do print('plat', p.x, p.y, p.w, p.dir, p.speed) end end
for _, p in ipairs(g.world.platforms) do
  local px, py = p.x - 240, p.y - 226
  if px > g.box.x and px < g.box.x + g.box.w then pf = p; break end
end
print('chosen platform', pf and (pf.x-240) or 'nil', pf and (pf.y-226) or '')
local px, py = pf.x - 240, pf.y - 226
g.soul.x, g.soul.y = px + pf.w/2, py - 8
g.prevX, g.prevY = g.soul.x, g.soul.y
for i=1,5 do M.update(g, {}, DT) end
print('on plat: y', g.soul.y, 'platTop', py, 'grounded', tostring(g.soul.grounded), 'vy', g.soul.vy)
local y0 = g.soul.y
M.jump(g)
print('after jump: vy', g.soul.vy, 'jumping', tostring(g.soul.jumping), 'grounded', tostring(g.soul.grounded))
for i=1,10 do M.update(g, { jumpHeld = true }, DT) end
print('after 10f: y', string.format('%.1f', g.soul.y), '(y0=%.1f) risen=%.1f' , y0, y0-g.soul.y)
