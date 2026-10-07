-- 探针：sans_bonestab3（round22 骨刺阶段）——每轮骨刺是否各配一根橙色横骨
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = M.DT
local csv
for _, s in ipairs(A) do if s.name == 'sans_bonestab3' then csv = s.csv end end
assert(csv, 'sans_bonestab3 未找到')
local w = M.newWorld({ seed = 20260927, script = M.parseCSV(csv) })
local seenBar, seenStab, t = {}, {}, 0
local nBar, nStab = 0, 0
local firstBar = nil
for i = 1, math.floor(60 * 20) do
  w:update(DT); t = t + DT
  for _, b in ipairs(w.bones) do
    if b.color == 2 and b.axis == 'h' and not seenBar[b] then
      seenBar[b] = t; nBar = nBar + 1; firstBar = firstBar or { b = b, t = t }
      print(string.format('t=%5.2f 橙骨#%d 生成：x=%.0f..%.0f（宽 %.0f）y=%.0f vy=%.0f',
        t, nBar, b.x, b.x + b.w, b.w, b.y, b.vy or 0))
    end
    if b.stab and not seenStab[b] then
      seenStab[b] = t; nStab = nStab + 1
      print(string.format('t=%5.2f 骨刺#%d 生成：dir=%s dist=%s warn=%.2f stay=%s',
        t, nStab, tostring(b.dir), tostring(b.dist), b.warn or 0, tostring(b.stay)))
    end
  end
  if w.ended then print(string.format('t=%5.2f 脚本 EndAttack（共 %d 轮）', t, nStab)); break end
end
local z = w.zone
print(string.format('框 = x %d..%d（宽 %d） 骨刺 %d 根 / 橙骨 %d 根', z.l, z.r, z.r - z.l, nStab, nBar))
print(string.format('橙骨宽度 = 框宽？ %s（橙骨 %.0f vs 框 %.0f）',
  (firstBar and firstBar.b.w == (z.r - z.l)) and '一致 ✓' or '不一致 ✗',
  firstBar and firstBar.b.w or -1, z.r - z.l))
