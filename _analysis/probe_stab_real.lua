-- 真实流程：按住"下"把红心钉在框底，看骨刺矩形与灵魂是否真的相交
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = M.DT
local g = M.newGame({ scripts = A, hp = 9999, difficulty = 'original' })
g:startEnemyScript('sans_bonestab1')
local t, seen = 0, 0
for i = 1, math.floor(60*12) do
  M.update(g, { down = true }, DT); t = t + DT
  local w = g.world
  if w then
    local SX, SY = g.soul.x + M.BOX_OFF_X, g.soul.y + M.BOX_OFF_Y
    for _, b in ipairs(w.bones) do
      if b.stab and (b.phase == 'out' or b.phase == 'stay') then
        local rc = w:stabRect(b)
        local hit = SX + M.SOUL_R > rc.x and SX - M.SOUL_R < rc.x + rc.w
                and SY + M.SOUL_R > rc.y and SY - M.SOUL_R < rc.y + rc.h
        seen = seen + 1
        if seen <= 8 then
          print(string.format('t=%5.2f dir=%s 相位=%s 灵魂(%.0f,%.0f) 骨刺矩形 x=%.0f..%.0f y=%.0f..%.0f 相交=%s 框=%d..%d/%d..%d',
            t, tostring(b.dir), tostring(b.phase), SX, SY, rc.x, rc.x+rc.w, rc.y, rc.y+rc.h, tostring(hit), w.zone.l,w.zone.r,w.zone.t,w.zone.b))
        end
      end
    end
    for _, l in ipairs(g.logs) do if l:find('^hit') then print(string.format('t=%5.2f ★命中日志 %s（灵魂 %.0f,%.0f）', t, l, SX, SY)) end end
    g.logs = {}
  end
  if w and w.ended then break end
end
print('致命相位帧数='..seen)
