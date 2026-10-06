package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local g = M.newGame({ scripts = {}, hp = 92 })
for _, n in ipairs({ 13, 14 }) do
  print(string.format('  内部号 %2d  -> HUD ROUND %2d/24  -> 脚本 = %s', n, n + 1, tostring(M.scriptForRound(g, n))))
end
