local f, err = loadfile(LUA_ROOT .. '/lua/main.lua')
print(f and 'main.lua SYNTAX OK' or ('main.lua SYNTAX ERROR: ' .. tostring(err)))
