-- 探针（不碰工作区文件）：验证「在 multi3 的 Attack5 段插入一根橙色下落横骨」的几何/时序
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = M.DT
local csv
for _, s in ipairs(A) do if s.name == 'multi3' then csv = s.csv end end
local anchor = '0,BoneVRepeat,121,354,37,2,0,20,20'
assert(csv:find(anchor, 1, true), '锚点行未找到')
local NEWLINE = '0,BoneH,121,266,405,1,160,2'
local patched = csv:gsub(anchor, anchor .. '\n' .. NEWLINE, 1)
local prog = M.compile(M.parseCSV(patched))
local w = M.newWorld({ seed = 20260927, compiled = prog })
w.pc = prog.labels['Attack5']; w.wait = 0
local t, z, bar = 0, nil, nil
local tEnter, tCoverBox, tExit, tClear = nil, nil, nil, nil
for i = 1, math.floor(60 * 4) do
  w:update(DT); t = t + DT
  z = z or { l = w.zone.l, t = w.zone.t, r = w.zone.r, b = w.zone.b }
  for _, b in ipairs(w.bones) do
    if b.color == 2 and b.axis == 'h' then
      bar = b
      if not tEnter and (b.y + b.h) >= z.t then tEnter = t end
      if not tCoverBox and b.y >= z.b then tCoverBox = t end
      if not tExit and b.y > z.b + 40 then tExit = t end
    end
  end
  if bar and not tClear then
    local alive = false
    for _, b in ipairs(w.bones) do if b == bar then alive = true end end
    if not alive then tClear = t end
  end
  if bar and i % 15 == 0 then
    print(string.format('  t=%4.2f 橙骨 x=%.0f..%.0f  y=%.0f..%.0f  vy=%.0f  phase=%s',
      t, bar.x, bar.x + bar.w, bar.y, bar.y + bar.h, bar.vy or 0, tostring(bar.phase)))
  end
end
print(string.format('框 = x %d..%d (宽%d)  y %d..%d (高%d)', z.l, z.r, z.r - z.l, z.t, z.b, z.b - z.t))
print(string.format('橙骨 宽=%.0f（= 框宽 %s）  起始 y=266  速度=160px/s（原速，未乘难度）',
  bar and bar.w or -1, (bar and bar.w == (z.r - z.l)) and '一致 ✓' or '不一致 ✗'))
print(string.format('进入框顶 t=%.2fs   完全划过框底 t=%.2fs   超出框底40px t=%.2fs   被清 t=%.2fs',
  tEnter or -1, tCoverBox or -1, tExit or -1, tClear or -1))
