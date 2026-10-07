package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = M.DT

local function track(name)
  local csv
  for _, s in ipairs(A) do if s.name == name then csv = s.csv end end
  local w = M.newWorld({ seed = 20260927, script = M.parseCSV(csv) })
  print('\n===== '..name..' =====')
  local seen, maxx, minx = {}, {}, {}
  local t = 0
  for i = 1, math.floor(60*40) do
    w:update(DT); t = t + DT
    local live = {}
    for _, b in ipairs(w.bones) do
      live[b] = true
      if seen[b] == nil then
        seen[b] = t
        print(string.format('  t=%5.2f 骨出现  x=%.0f y=%.0f w=%.0f h=%.0f vx=%.0f axis=%s',
          t, b.x, b.y, b.w, b.h, b.vx or 0, tostring(b.axis)))
      end
      maxx[b] = math.max(maxx[b] or b.x, b.x)
      minx[b] = math.min(minx[b] or b.x, b.x)
    end
    for b, ts in pairs(seen) do
      if ts and live[b] == nil then
        print(string.format('  t=%5.2f 骨消失  x范围 %.0f..%.0f  y=%.0f（存活 %.2fs）',
          t, minx[b], maxx[b], b.y, t - ts))
        seen[b] = nil
      end
    end
    if w.ended then print(string.format('  t=%.2f 脚本 EndAttack', t)); break end
  end
end
track('multi1')
