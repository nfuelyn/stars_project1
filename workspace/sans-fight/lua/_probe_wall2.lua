package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
print('内部号  HUD   脚本                  骨墙出现帧数')
for n = 0, 23 do
  local g = M.newGame({ scripts = A, hp = 1000000 })
  g:startEnemy(n)
  local t, seen = 0, 0
  while g.state == 'enemy' and t < 80 do
    M.update(g, {}, M.DT); t = t + M.DT
    if #(g.walls or {}) > 0 then seen = seen + 1 end
  end
  if seen > 0 then
    print(string.format('  %2d    %2d    %-20s  %d 帧', n, n + 1, tostring(g.roundScript), seen))
  end
end
print('（只打印出现过骨墙的回合）')
