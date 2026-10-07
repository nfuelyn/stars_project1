package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = M.DT
local function jumpCurve(hold)
  local gj = M.newGame({ scripts = A }); gj:startEnemyScript('sans_boneslideh')
  for _ = 1, 20 do M.update(gj, {}, DT) end
  local y0 = gj.soul.y; M.jump(gj); local peak = y0
  for _ = 1, math.floor(hold / DT + 0.5) do
    M.update(gj, { jumpHeld = true }, DT); if gj.soul.y < peak then peak = gj.soul.y end
  end
  for k = 1, 600 do
    M.update(gj, { jumpHeld = false }, DT); if gj.soul.y < peak then peak = gj.soul.y end
    if gj.soul.grounded and k > 1 then break end
  end
  return y0 - peak, gj.box.h
end
local s, bh = jumpCurve(0.05); local l = jumpCurve(1.2)
print(string.format('框高 %d  轻点跳高 %.1fpx  满跳(按住) %.1fpx  满跳上缘(脚本y) = 框底-%.1f', bh, s, l, M.SOUL_CLAMP + l + M.SOUL_R))
