-- 判定"骨刺太浅"假设：灵魂钉在离边 different 深度，看命中次数
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = M.DT
local function run(depth)   -- depth = 灵魂中心离框底的像素
  local g = M.newGame({ scripts = A, hp = 9999, difficulty = 'original' })
  g:startEnemyScript('sans_bonestab1')
  local hits = 0
  for i = 1, math.floor(60*12) do
    M.update(g, {}, DT)
    if g.world and g.soul then
      g.soul.x = g.box.x + g.box.w/2
      g.soul.y = g.box.y + g.box.h - depth
      g.invuln = 0
    end
    for _, l in ipairs(g.logs) do if l:find('^hit') or l:find('^hit_') then hits = hits + 1 end end
    g.logs = {}
    if g.world and g.world.ended then break end
  end
  return hits
end
for _, d in ipairs({ 8, 14, 16, 20, 25, 40, 80 }) do
  print(string.format('灵魂中心离框底 %3dpx（判定体近边距 %3dpx）→ 12s 内命中次数 = %d', d, d - 2, run(d)))
end
print('（dist=9 ⇒ 致命条只覆盖离边 5+9 = 14px 深）')
