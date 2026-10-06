package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local core = require('lua' .. '.core')
local atk  = require('lua' .. '.attacks')
local DT = core.DT

local function pad(s, n) s = tostring(s); while #s < n do s = s .. ' ' end; return s end
print(pad('script',26)..pad('lines',7)..pad('static_len',12)..pad('actual_end',12)..pad('ratio',8)..'ended?')
for _, s in ipairs(atk) do
  local w = core.newWorld({ script = core.parseCSV(s.csv), seed = 20260927 })
  local need = w:scriptLength()
  local t, steps, maxpc = 0, 0, 0
  while (not w.ended) and t < 300 do
    w:update(DT); t = t + DT; steps = steps + 1
    if (w.pc or 0) > maxpc then maxpc = w.pc end
  end
  local ratio = (need and need > 0) and (t / need) or -1
  print(pad(s.name,26)..pad(#w.prog,7)..pad(need and string.format('%.2f',need) or 'nil',12)
    ..pad(string.format('%.2f',t),12)..pad(string.format('%.2f',ratio),8)..tostring(w.ended))
end

-- 定向：SansSlam 在普通蓝/红模式下是否真的产生位移
local function slamTest(mode, dir, maxFall)
  local csv = '0,HeartMode,'..mode..'\n0,HeartMaxFallSpeed,'..maxFall..'\n0,HeartTeleport,320,300\n0,TLPause\n'
  local w = core.newWorld({ script = core.parseCSV(csv), seed = 1 })
  w:update(DT); w:update(DT)
  local x0, y0 = w.heart.x, w.heart.y
  w:exec({cmd='SansSlam', args={tostring(dir)}, delay=0})
  for _=1,30 do w:update(DT) end
  print(string.format('slam mode=%s dir=%d maxFall=%s  dx=%.2f dy=%.2f', mode, dir, tostring(maxFall), w.heart.x-x0, w.heart.y-y0))
end
slamTest(1, 0, 240)
slamTest(1, 2, 240)
slamTest(1, 1, 240)
slamTest(0, 0, 240)
slamTest(0, 1, 240)
