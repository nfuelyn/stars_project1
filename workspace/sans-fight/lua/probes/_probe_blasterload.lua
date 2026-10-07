-- 探针：单帧「龙骨炮发数」与「控件数」的峰值（当前代码）
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local fit = require('lua' .. '.fitdata')
local DT = 1 / 30
local function blasterCost(c)
  local set = (c.lod == 'block3') and fit.blaster_block3 or fit.blaster_block2
  local n = #set.Default
  if (c.fire or 0) > 0 then
    n = ((c.fire or 0) >= 0.5) and #set.fire_2 or #set.fire_0
    n = n + 3        -- 光束 2（外壳+亮核）+ 炮口 1
  end
  return n
end
local function scan(n, label)
  local g = M.newGame({ scripts = A, hp = 1000000, seed = 20260927 })
  g:startEnemy(n)
  local t, peakN, peakC, peakT = 0, 0, 0, 0
  local peakB2, peakB3 = 0, 0
  local peakAll = 0
  while g.state == 'enemy' and t < 80 do
    M.update(g, {}, DT); t = t + DT
    local cmds = M.render(g)
    local nb, nc, all, n2, n3 = 0, 0, 0, 0, 0
    for _, c in ipairs(cmds) do
      if c.kind == 'blaster' then
        nb = nb + 1; nc = nc + blasterCost(c)
        if c.lod == 'block3' then n3 = n3 + blasterCost(c) else n2 = n2 + blasterCost(c) end
      end
      if c.kind ~= 'box' and c.kind ~= 'hudBar' and c.kind ~= 'hudText' then all = all + 1 end
    end
    if nb > peakN then peakN, peakC, peakT = nb, nc, t end
    if n2 > peakB2 then peakB2 = n2 end
    if n3 > peakB3 then peakB3 = n3 end
    if nc > peakAll then peakAll = nc end
  end
  return peakN, peakAll, peakT, t, peakB2, peakB3
end
print('回合        同屏峰值发数   龙骨炮控件数   block2/block3   出现时刻   回合时长')
for _, n in ipairs({ 0, 8, 15, 16, 19, 23 }) do
  local nb, nc, at, dur, n2, n3 = scan(n)
  print(string.format('r%-3d(HUD%2d)  %8d       %8d      %6d/%6d   t=%.1fs    %.1fs', n, n + 1, nb, nc, n2, n3, at, dur))
end
