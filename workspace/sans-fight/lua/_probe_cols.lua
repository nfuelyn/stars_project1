package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local funcs = { 'platforms4', 'platforms4hard' }
for _, name in ipairs(funcs) do
  local g = M.newGame({ scripts = A })
  g:startEnemyScript(name)
  for i = 1, 120 do M.update(g, {}, M.DT) end
  local byx, byy = {}, {}
  for _, b in ipairs(g.world.bones) do
    local kx, ky = math.floor(b.x + 0.5), math.floor(b.y + 0.5)
    byx[kx] = (byx[kx] or 0) + 1
    byy[ky] = (byy[ky] or 0) + 1
  end
  print('=== ' .. name .. ' ：骨头总数 = ' .. #g.world.bones)
  local ks = {}
  for k, v in pairs(byx) do if v >= 2 then ks[#ks + 1] = k end end
  table.sort(ks)
  for _, k in ipairs(ks) do print(string.format('   竖列 x=%-5d  %d 根', k, byx[k])) end
  local ks2 = {}
  for k, v in pairs(byy) do if v >= 8 then ks2[#ks2 + 1] = k end end
  table.sort(ks2)
  for _, k in ipairs(ks2) do print(string.format('   横排 y=%-5d  %d 根（骨毯）', k, byy[k])) end
end
