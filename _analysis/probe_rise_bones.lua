-- 探针（只读）：拖拽后「升起骨」的判定是否存在
-- ① sans_bonestab1：把灵魂钉在框底，看 BoneStab 能不能打中
-- ② final 阶段① 的 BoneHRepeat（从上下边升起的横骨）几何与命中
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = M.DT
local function scriptOf(n) for _,s in ipairs(A) do if s.name==n then return s end end end

print('===== ① sans_bonestab1：灵魂钉在框底 =====')
local g = M.newGame({ scripts = A, hp = 999 })
g:startEnemyScript('sans_bonestab1')
local stabs, hits, phases = {}, 0, {}
for i = 1, math.floor(60*12) do
  M.update(g, {}, DT)
  if g.world then
    if g.soul then g.soul.x = g.box.x + g.box.w/2; g.soul.y = g.box.y + g.box.h - M.SOUL_CLAMP end
    for _, b in ipairs(g.world.bones) do
      if b.stab then
        local key = tostring(b.dir)
        if not stabs[key] then
          stabs[key] = true
          print(string.format('  骨刺 dir=%s dist=%s warn=%.2f  生成时灵魂=(%.0f,%.0f) 框底=%.0f',
            tostring(b.dir), tostring(b.dist), b.warn or 0, g.soul.x, g.soul.y, g.box.y+g.box.h))
        end
        local p = b.phase
        if phases[key] ~= p then phases[key] = p end
      end
    end
    for _, l in ipairs(g.logs) do if l:find('^hit') then hits = hits + 1; g.logs = {} end end
  end
  if g.world and g.world.ended then break end
end
print(string.format('  结果：出现过的骨刺方向 = %s ；灵魂钉框底期间命中次数 = %d', (function() local t={} for k in pairs(stabs) do t[#t+1]=k end table.sort(t) return table.concat(t,',') end)(), hits))

print('')
print('===== ② final 阶段①「升起骨」= BoneHRepeat 的几何 =====')
local csv
for _,s in ipairs(A) do if s.name=='final' then csv=s.csv end end
local n=0
for ln in tostring(csv):gmatch('[^\n]+') do
  if ln:find('BoneHRepeat', 1, true) then
    n=n+1
    print('  '..ln)
  end
end
print('  共 '..n..' 行（宽 200 / 高 10 = 平行于边的长条；dir=1 从上向下、dir=3 从下向上）')
