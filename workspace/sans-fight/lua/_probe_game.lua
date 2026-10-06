package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local core = require('lua' .. '.core')
local atk  = require('lua' .. '.attacks')
local DT = core.DT
local IDLE = { left=false,right=false,up=false,down=false,confirm=false,cancel=false }

print('=== A. 每个回合在 Game 里实际持续多久（hp 拉满，无输入） ===')
print(string.format('%-6s %-22s %-10s %-8s','round','script','dur(s)','state'))
for _, n in ipairs({0,1,2,3,8,12,15,17,18,19,22,23}) do
  local g = core.newGame({ scripts = atk, hp = 1000000, difficulty = 'original' })
  g:startEnemy(n)
  local t = 0
  while g.state == 'enemy' and t < 200 do core.update(g, IDLE, DT); t = t + DT end
  print(string.format('%-6s %-22s %-10.2f %-8s','r'..n, tostring(g.roundScript), t, tostring(g.state)))
end

print('')
print('=== B. SansSlam 在红/蓝模式下是否真的推动灵魂 ===')
local function slam(mode, dir, maxFall, wall)
  local csv = '0,HeartMode,'..mode..'\n0,HeartMaxFallSpeed,'..maxFall..'\n'
  if wall then csv = csv..'0,HeartWall,1\n' end
  csv = csv..'0,HeartTeleport,320,300\n0,SansSlam,'..dir..'\n'
  local g = core.newGame({ scripts = {{name='t', csv=csv}}, hp=1000000 })
  g:startEnemyScript('t')
  g.state = 'enemy'; g.enemyDur = 1e9; g.invuln = 0
  g.soul.x = g.box.x + g.box.w/2; g.soul.y = g.box.y + g.box.h/2
  for _=1,3 do core.update(g, IDLE, DT) end
  local x0,y0 = g.soul.x, g.soul.y
  for _=1,60 do core.update(g, IDLE, DT) end
  print(string.format('mode=%s dir=%d maxFall=%d wall=%s  dx=%7.2f dy=%7.2f',
    tostring(mode), dir, maxFall, tostring(wall or false), g.soul.x-x0, g.soul.y-y0))
end
slam(1,0,240,false); slam(1,2,240,false); slam(1,1,240,false)
slam(0,0,240,false); slam(0,2,240,false); slam(0,1,240,false)
slam(1,0,240,true);  slam(1,1,240,true)
