package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = M.DT
local R = 8   -- SOUL_CLAMP

print('=== J4 平台带走：站在移动平台上是否被带着走 ===')
do
  local g = M.newGame({ scripts = A, hp = 1000000 })
  g:startEnemyScript('platforms1')
  local pf
  for i = 1, 400 do
    M.update(g, {}, DT)
    for _, p in ipairs(g.world.platforms) do
      local px, py = p.x - 240, p.y - 226
      if px > g.box.x and px + p.w < g.box.x + g.box.w and (p.speed or 0) > 0 then pf = p break end
    end
    if pf then break end
  end
  if pf then
    local px, py = pf.x - 240, pf.y - 226
    g.soul.x, g.soul.y = px + pf.w / 2, py - R
    g.prevX, g.prevY = g.soul.x, g.soul.y
    local x0, p0 = g.soul.x, pf.x
    for i = 1, 30 do M.update(g, {}, DT) end
    local sdx, pdx = g.soul.x - x0, pf.x - p0
    print(string.format('  平台 30 帧移动 %+.2f px，灵魂移动 %+.2f px（grounded=%s）→ %s',
      pdx, sdx, tostring(g.soul.grounded),
      (math.abs(pdx) < 0.01) and 'SKIP 平台没动' or (math.abs(sdx - pdx) < 12 and 'OK 被带走' or 'FAIL 没跟上')))
  else
    print('  FAIL 400 帧内没找到框内的移动脚本平台')
  end
end

print('')
print('=== J6 方向重力起跳：起跳速度必须沿 -重力 ===')
for _, d in ipairs({ 0, 1, 2, 3 }) do
  local g = M.newGame({ scripts = A, hp = 1000000 })
  g:startEnemyScript('sans_bonegap1')
  for i = 1, 20 do M.update(g, {}, DT) end
  local b = g.box
  g.soul.dir = d
  if d == 0 then g.soul.x = b.x + b.w - R
  elseif d == 2 then g.soul.x = b.x + R
  elseif d == 1 then g.soul.y = b.y + b.h - R
  else g.soul.y = b.y + R end
  g.soul.vx, g.soul.vy = 0, 0
  g.soul.jumping = false
  g.prevX, g.prevY = g.soul.x, g.soul.y
  local surface, gx, gy, soulA = g:groundQuery()
  local onSolid = (soulA + R) >= (surface - 2)
  M.jump(g)
  local va = g.soul.vx * gx + g.soul.vy * gy
  print(string.format('  dir=%d onSolid=%s  起跳 v=(%.1f, %.1f) 沿重力分量=%+.1f → %s',
    d, tostring(onSolid), g.soul.vx, g.soul.vy, va, (onSolid and va < -1) and 'OK 逆重力' or 'FAIL'))
end
