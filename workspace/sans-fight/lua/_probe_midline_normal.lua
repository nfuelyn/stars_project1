-- 复核：普通档(tune normal 0.78/1.35)下 multi1/multi3 Attack1 的骨终点
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = M.DT
local function csvOf(n) for _, s in ipairs(A) do if s.name == n then return s.csv end end end
local DIFFS = { original = { speed = 1.0, interval = 1.0, warn = 1.0 }, normal = { speed = 0.78, interval = 1.35, warn = 1.2 } }
for _, dk in ipairs({ 'original', 'normal' }) do
  local compiled = M.compile(M.parseCSV(csvOf('multi1')))
  local w = M.newWorld({ seed = 20260927, compiled = compiled, tune = DIFFS[dk] })
  w.pc = compiled.labels['Attack1']; w.wait = 0
  local stat = {}; local t = 0
  for i = 1, 60 * 4 do
    w:update(DT); t = t + DT
    local live = {}
    for _, b in ipairs(w.bones) do
      live[b] = true
      local st = stat[b] or { x0 = b.x - b.vx * DT, h = b.h, color = b.color, vx = b.vx, y = b.y }
      stat[b] = st
    end
    for b, st in pairs(stat) do if st.x1 == nil and live[b] == nil then st.x1 = b.x - (b.vx or 0) * DT; st.t1 = t end end
  end
  print('==== multi1 Attack1  tune=' .. dk .. ' (speed ' .. DIFFS[dk].speed .. ' / interval ' .. DIFFS[dk].interval .. ') ====')
  for _, st in pairs(stat) do
    local lead = (st.vx > 0) and (st.x1 + 10) or st.x1
    print(string.format('  h=%-3.0f color=%d vx=%-5.0f 生成x=%-4.0f 终点x=%-4.0f 前缘=%-4.0f 存活=%.2fs  (判定左缘318 / 视觉左缘312 / 中线323.5)',
      st.h, st.color or 0, st.vx, st.x0, st.x1, lead, st.t1))
  end
end
