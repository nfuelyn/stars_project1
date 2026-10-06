package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
for _, n in ipairs({ 0, 5, 23 }) do
  local g = M.newGame({ scripts = A, hp = 1000000 })
  g:startEnemy(n)
  local t, frames, peak, firstT = 0, 0, 0, nil
  while g.state == 'enemy' and t < 25 do
    M.update(g, {}, M.DT); t = t + M.DT
    local c = 0
    if g.world then for _, b in ipairs(g.world.bones) do if b.kind == 'floor' then c = c + 1 end end end
    if c > 0 then frames = frames + 1; if not firstT then firstT = t end; if c > peak then peak = c end end
  end
  print(string.format('内部 %2d（%s）: 地板骨 活跃帧=%d 首次t=%.2f 峰值=%d 根',
    n, tostring(g.roundScript), frames, firstT or -1, peak))
end
