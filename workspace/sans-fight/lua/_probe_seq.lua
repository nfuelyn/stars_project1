package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core'); local A = require('lua' .. '.attacks')
local g = M.newGame({ scripts = A })
local out = {}
for n = 0, 25 do out[#out+1] = n .. ':' .. tostring(M.scriptForRound(g, n)) end
print(table.concat(out, '  '))
