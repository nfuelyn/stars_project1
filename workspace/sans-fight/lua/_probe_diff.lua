package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local core = require('lua' .. '.core')
local atk  = require('lua' .. '.attacks')
local DT = core.DT
local IDLE = { left=false,right=false,up=false,down=false,confirm=false,cancel=false }

print('=== C. 难度对“脚本回合”的影响（同一脚本 R1） ===')
for _, diff in ipairs({'easy','normal','hard','original'}) do
  local g = core.newGame({ scripts = atk, hp = 1000000, difficulty = diff })
  g:startEnemy(1)
  local bone
  for _=1,600 do
    core.update(g, IDLE, DT)
    if g.world and g.world.bones[1] then bone = g.world.bones[1]; break end
  end
  print(string.format('%-9s tune.speed=%.2f interval=%.2f  enemyDur=%.2f  首骨vx=%.1f vy=%.1f',
    diff, g.tune.speed, g.tune.interval, g.enemyDur, bone and bone.vx or 0, bone and bone.vy or 0))
end

print('')
print('=== D. KR 燃烧速率（直接调 updateKR） ===')
for _, kr0 in ipairs({6, 20, 40}) do
  local g = core.newGame({ scripts = atk, hp = 1000000 })
  g.hp, g.kr = 20, kr0
  local t = 0
  while g.kr > 0 and t < 120 do g:updateKR(DT); t = t + DT end
  print(string.format('KR %2d -> 0  用时 %5.2fs  掉血 %2d  (KR_TICK=%.2f)', kr0, t, 20 - g.hp, core.KR_TICK))
end

print('')
print('=== E. 螺旋脚本是否在固定编排里被使用 ===')
local g = core.newGame({ scripts = atk, hp = 1000000, difficulty = 'normal' })
local seen = {}
for n = 0, 30 do seen[#seen+1] = n .. ':' .. tostring(core.scriptForRound(g, n)) end
print(table.concat(seen, '  '))
local used = {}
for n = 0, 23 do local s = core.scriptForRound(g, n); used[s] = true end
for _, s in ipairs(atk) do if not used[s.name] then print('未被任何回合使用: ' .. s.name) end end
