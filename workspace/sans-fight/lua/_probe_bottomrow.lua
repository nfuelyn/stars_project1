package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local w = M.newWorld({ seed = 1, script = M.parseCSV(
  '0,CombatZoneResizeInstant,121,276,526,391\n' ..
  '0,HeartMode,1\n' ..
  '0,Platform,309,314,41,0,0\n' ..
  '0,Platform,309,354,41,0,0\n' ..
  '0,BoneVRepeat,121,354,37,2,0,20,20\n' ..
  '1,EndAttack\n') })
w:update(M.DT)
local z = w.zone
print(string.format('zone = (%d,%d)-(%d,%d)  框底=%d', z.l, z.t, z.r, z.b, z.b))
local n = 0
for _, b in ipairs(w.bones) do
  n = n + 1
  if n <= 3 or n == #w.bones then
    print(string.format('  bone#%d  x=%d y=%d w=%d h=%d  → y..y+h = %d..%d  (贴底边? %s)', n, b.x, b.y, b.w, b.h, b.y, b.y + b.h, tostring(b.y + b.h == z.b)))
  end
end
print('骨头总数 = ' .. #w.bones)
