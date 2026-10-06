package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = M.DT
local g = M.newGame({ scripts = A, hp = 1000000 })
g:startEnemyScript('sans_bonestab1')
for i = 1, 10 do M.update(g, {}, DT) end
print(string.format('起始: x=%.1f y=%.1f dir=%s slammed=%s grounded=%s jumping=%s',
  g.soul.x, g.soul.y, tostring(g.soul.dir), tostring(g.soul.slammed), tostring(g.soul.grounded), tostring(g.soul.jumping)))
local held = { left = true }
for i = 1, 240 do                      -- 4 秒：一直按住左
  M.update(g, held, DT)
  if i % 20 == 0 then
    print(string.format('  帧%3d x=%6.1f y=%6.1f dir=%s slammed=%s grounded=%s jumping=%s  (按住左键)',
      i, g.soul.x, g.soul.y, tostring(g.soul.dir), tostring(g.soul.slammed), tostring(g.soul.grounded), tostring(g.soul.jumping)))
  end
end
