package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = M.DT
local IDLE = {}

print('=== A. 龙骨炮「落定 -> 开火」间隔（应为 1.5s）===')
for _, map in ipairs({ {8,'round9  platformblaster'}, {15,'round16 randomblaster1'},
                       {16,'round17 multi2'},        {19,'round20 randomblaster2'} }) do
  local n, label = map[1], map[2]
  local g = M.newGame({ scripts = A, hp = 1000000 })
  g:startEnemy(n)
  local t = 0
  local settle, fires, spins, prev = {}, {}, {}, {}
  while g.state == 'enemy' and t < 60 do
    M.update(g, IDLE, DT); t = t + DT
    local w = g.world
    if w then
      for _, b in ipairs(w.blasters) do
        if prev[b] ~= b.state then
          if b.state == 'spinning' then settle[b] = t; spins[#spins+1] = b.spin end
          if b.state == 'fire' and settle[b] then fires[#fires+1] = t - settle[b] end
          prev[b] = b.state
        end
      end
    end
  end
  local mn, mx = 9e9, -9e9
  for _, v in ipairs(fires) do mn = math.min(mn, v); mx = math.max(mx, v) end
  local s0, sx = 9e9, -9e9
  for _, v in ipairs(spins) do s0 = math.min(s0, v); sx = math.max(sx, v) end
  print(string.format('  %-24s 开火 %2d 次  落定->开火 %.3f..%.3f s  spin %.3f..%.3f  回合 %.1fs',
    label, #fires, mn == 9e9 and -1 or mn, mx == -9e9 and -1 or mx,
    s0 == 9e9 and -1 or s0, sx == -9e9 and -1 or sx, t))
end

print('')
print('=== B. round18/19 甩击后重力方向是否还原 ===')
for _, n in ipairs({17, 18}) do
  local g = M.newGame({ scripts = A, hp = 1000000 })
  g:startEnemy(n)
  local t, changed, restored = 0, false, false
  while g.state == 'enemy' and t < 60 do
    M.update(g, {}, DT); t = t + DT
    if g.soul.dir ~= 1 then changed = true end
    if changed and g.soul.dir == 1 and not g.soul.slammed then restored = true end
  end
  print(string.format('  round%d (%s) 曾改过方向=%s  之后还原 dir=1 且未在甩=%s',
    n + 1, tostring(g.roundScript), tostring(changed), tostring(restored)))
end
