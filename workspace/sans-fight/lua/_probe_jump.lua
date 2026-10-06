if type(_G.LUA_ROOT) == 'string' then
  package.path = _G.LUA_ROOT .. '/?.lua;' .. _G.LUA_ROOT .. '/lua/?.lua;' .. package.path
end
local M = require('core')
local A = require('attacks')
local DT = M.DT
local function measure(hold)
  local g = M.newGame({ scripts = A })
  g:startEnemyScript('sans_boneslideh')
  for i=1,20 do M.update(g, {}, DT) end
  local y0 = g.soul.y
  M.jump(g)
  local peak = y0
  local n = math.floor(hold / DT + 0.5)
  for i=1,n do M.update(g, { jumpHeld = true }, DT); if g.soul.y < peak then peak = g.soul.y end end
  for i=1,400 do
    M.update(g, { jumpHeld = false }, DT)
    if g.soul.y < peak then peak = g.soul.y end
    if g.soul.grounded and i > 3 then break end
  end
  return y0 - peak
end
local boxH = 140
for _, h in ipairs({0, 0.05, 0.1, 0.2, 0.3, 0.5, 0.75, 1.0, 1.5}) do
  local dh = measure(h)
  print(string.format('hold=%.2fs  height=%6.1fpx  = %.3f x 框高(140)  %.1f%%', h, dh, dh/boxH, 100*dh/boxH))
end
