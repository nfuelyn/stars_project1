package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = M.DT
-- 直接观察 BoneStab 的矩形随时间变化（4 个方向）
for _, dir in ipairs({0,1,2,3}) do
  local w = M.newWorld({ seed = 1, script = M.parseCSV(
    '0,CombatZoneResizeInstant,241,226,406,391\n0,BoneStab,'..dir..',23.2,1.0,0\n2,EndAttack\n') })
  local z = w.zone
  print(string.format('--- dir=%d  zone=(%d,%d)-(%d,%d) ---', dir, z.l, z.t, z.r, z.b))
  local marks = {0.4, 0.9, 1.02, 1.08, 1.3}
  local mi = 1
  local t = 0
  for i = 1, 120 do
    w:update(DT); t = t + DT
    local b = w.bones[1]
    local rc = b and w:stabRect(b)
    if mi <= #marks and t >= marks[mi] then
      if rc then
        print(string.format('  t=%.2f phase=%s  rect=(x=%.0f,y=%.0f,w=%.0f,h=%.0f)', t, tostring(b.phase), rc.x, rc.y, rc.w, rc.h))
      else
        print(string.format('  t=%.2f 无骨头', t))
      end
      mi = mi + 1
    end
  end
end
