package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = M.DT

local function apex(name)
  local g = M.newGame({ scripts = A, hp = 1000000 })
  g:startEnemyScript(name)
  for i = 1, 90 do M.update(g, {}, DT) end          -- 等框动画结束 + 落地
  local y0 = g.soul.y
  M.jump(g)                                          -- 起跳
  local minY = y0
  for i = 1, 200 do
    M.update(g, { jumpHeld = true }, DT)             -- 一直按住 = 最高跳
    if g.soul.y < minY then minY = g.soul.y end
    if i > 3 and g.soul.grounded then break end
  end
  local src = 2   -- core.SOUL_R
  print(string.format('%-20s box.h=%3d  box.b=%3d  地面 y=%.1f  顶点 y=%.1f  跳高=%.1f  顶点上缘=%.1f',
    name, g.box.h, g.box.b or (g.box.y+g.box.h), y0, minY, y0 - minY, minY - src))
  return minY - src, g.box
end
apex('sans_bonegap1')
apex('sans_bonegap1fast')
apex('sans_boneslideh')
apex('sans_bonegap2')
apex('platforms4')
apex('platforms4hard')
