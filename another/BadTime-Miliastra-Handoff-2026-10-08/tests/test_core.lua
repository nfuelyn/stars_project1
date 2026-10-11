local function check(value, message) assert(value, message) end
local function game(opts)
  opts = opts or {}; opts.scripts = attacks; opts.difficulty = opts.difficulty or 'original'
  return core.newGame(opts)
end
local function safe(g) g.hurt = function() return false end; return g end
local function runEnemy(g, maxSeconds)
  local n = 0
  while g.state == 'enemy' and n < (maxSeconds or 180) * 60 do
    core.update(g, {}, 1/60); n = n + 1
  end
  check(g.state == 'menu', 'attack did not finish: ' .. tostring(g.roundScript) .. ' / ' .. tostring(g.state))
  return n / 60
end
local function fight(g)
  g:menuChoose(0); g:stopAttack()
  for _ = 1, 80 do core.update(g, {}, 1/60) end
end

-- All commands and jump targets from the downloaded, unmodified CSVs compile.
for _, attack in ipairs(attacks) do
  local compiled = core.compile(core.parseCSV(attack.csv))
  for _, line in ipairs(compiled.prog) do
    check(line.label or core.commands[line.cmd] or core.jumps[line.cmd], attack.name .. ': unsupported command ' .. tostring(line.cmd))
  end
end
print('PASS upstream attack command coverage')

local g = safe(game())
check(g.roundScript == 'sans_intro' and g.fightCount == 0, 'opening attack must precede first FIGHT')
local duration = runEnemy(g)
check(duration < 15, 'opening must end on EndAttack instead of timeout')
g.hp = 30; g.kr = 10
g:menuChoose(2); g:subConfirm()
check(g.fightCount == 0 and g.round == 0 and g.roundScript == 'sans_bonegap1', 'ITEM advances attack cursor, not FIGHT phase')
check(g.kr == 10, 'healing must not clear KR')
check(g:itemCount() == 7, 'default inventory is eight consumables')
check(#g:subRows() == 0, 'sub cleared after ITEM')
print('PASS separate attack cursor, FIGHT count, inventory and KR healing')

g = safe(game({startRound = 13}))
check(g.roundScript == 'sans_spare', 'midpoint attack')
runEnemy(g)
check(g.interlude, 'midpoint rest must be active')
g:menuChoose(2); g:subConfirm()
check(g.state == 'menu' and g.interlude and g.fightCount == 13, 'healing during rest must stay in rest')
g:menuChoose(1); g:subConfirm()
check(g.state == 'menu' and g.interlude, 'ACT during rest must stay in rest')
g:menuChoose(3)
check(g.state == 'sub', 'opening MERCY must not instantly kill')
g:subBack(); fight(g)
check(g.fightCount == 14 and not g.interlude and g.roundScript == 'multi1', 'FIGHT must resume phase two')
local spare = safe(game({startRound=13})); runEnemy(spare); spare:menuChoose(3); spare:subConfirm()
check(spare.result == 'fail' and spare.failReason == 'spared_midpoint', 'confirmed midpoint mercy is a trap')
spare:settle()
check(spare.result == 'fail' and spare.settleRequested, 'failure settlement must preserve failure')
print('PASS rest, mercy confirmation, phase two and failure settlement')

g = game({noScriptRounds=true, noSpawn=true})
g.hp=2; g.kr=40; g:updateKR(2)
check(g.hp == 1 and g.kr == 0, 'KR cannot kill or exceed HP-1')
g.hp=92; g.kr=45; g:clampKR()
check(g.kr==40, 'KR cap')
print('PASS KR cap and nonlethal floor')

local damaged=game({noScriptRounds=true,noSpawn=true})
local bone={karma=6}
damaged:hurt('hit',nil,bone)
check(damaged.hp==91 and damaged.kr==6 and bone.karma==2,'first bone hit and subsequent Karma')
damaged.invuln=0;damaged:hurt('hit',nil,bone)
check(damaged.hp==90 and damaged.kr==8 and damaged.hits==2,'later bone hit must add 2 KR')
local death=game({noScriptRounds=true,noSpawn=true})
death.box={x=0,y=0,w=160,h=165};death.soul.x=80;death.soul.y=78
death.prevX=80;death.prevY=78;death.hp=1;death.enemyT=.3
death.world=core.newWorld({script=core.parseCSV('0,BoneV,312,296,40,0,0,0\n0,EndAttack\n')})
core.update(death,{},1/60)
check(death.hp==0 and death.state=='result' and death.result=='fail','lethal hit on EndAttack frame must remain failure')
print('PASS first/repeat hit Karma and death on attack-ending frame')

local function jump(held)
  local j = safe(game({noScriptRounds=true, noSpawn=true}))
  j.box = {x=0,y=0,w=160,h=165}; j.soul.x=80; j.soul.y=157
  j.soul.mode='blue'; j.soul.dir=1; j.prevX=80; j.prevY=157
  local minY=157
  core.update(j, {up=true}, 1/60)
  for n=1,90 do
    core.update(j, {up = n <= held}, 1/60)
    minY=math.min(minY,j.soul.y)
  end
  return 157-minY
end
local short, long = jump(0), jump(20)
check(short>0 and long>short*1.5 and long<80, 'variable jump must distinguish tap/hold without 3/5-box synthetic rise')
print(string.format('PASS blue variable jump (tap %.2fpx, hold %.2fpx)',short,long))

local function idleSoul(mode)
  local j = safe(game({noScriptRounds=true, noSpawn=true}))
  j.box={x=0,y=0,w=160,h=165};j.soul.x=80;j.soul.y=50
  j.soul.mode=mode;j.soul.dir=1;j.soul.vy=0;j.prevX=80;j.prevY=50
  for _=1,30 do core.update(j,{},1/60) end
  return j.soul.y
end
check(math.abs(idleSoul('red')-50)<1e-6,'red soul should have no gravity')
check(idleSoul('blue')>50,'blue soul must fall without input')
print('PASS red free movement / blue idle gravity')

local function sample(fps)
  local j = safe(game({noScriptRounds=true,noSpawn=true}))
  j.hp=92; j.kr=35
  for _=1,fps*2 do core.update(j,{right=true},1/fps) end
  return j.soul.x, j.kr, j.hp, j.enemyT
end
local x,kr,hp,t=sample(60)
for _,fps in ipairs({30,120,144}) do
  local xx,kk,hh,tt=sample(fps)
  check(math.abs(x-xx)<1e-6 and kk==kr and hh==hp and math.abs(t-tt)<1e-6, 'frame rate dependence at '..fps)
end
print('PASS fixed-step movement and KR at 30/60/120/144fps')

local w=core.newWorld({})
core.commands.GasterBlaster(w,0,0,0,100,100,0,0.5,0)
for _=1,90 do w:update(1/60) end
check(#w.blasters==0,'BlastTime=0 must retire, not create permanent beams')
print('PASS zero-duration laser lifecycle')

g = safe(game())
local scripts = {}
local maxBlasters=0
for expected=0,23 do
  check(g.round == expected, 'FIGHT phase mismatch '..expected..' got '..g.round)
  scripts[#scripts+1] = g.roundScript
  local n=0
  while g.state=='enemy' and n<180*60 do
    core.update(g,{},1/60);n=n+1
    if g.world then maxBlasters=math.max(maxBlasters,#g.world.blasters) end
  end
  check(g.state=='menu','full run attack did not end')
  if expected<23 then fight(g) end
end
check(g.final and g.roundScript=='final', 'final timeline must run')
check(maxBlasters<24,'final rotating lasers accumulate into unavoidable field')
g:menuChoose(0); g:stopAttack(); core.step(g,2,{})
check(g.result=='kill', 'final hit must finish')
g:settle(); check(g.result=='kill', 'kill settlement must preserve outcome')
print('PASS complete 24-attack FIGHT run: '..table.concat(scripts,', '))
print('PASS laser count bounded across full run (peak '..maxBlasters..')')
