-- Run every normal FIGHT phase through the real adapter, sampling twice a second.
-- Damage is disabled for timeline verification; this is not a playability test.
main.OnInit();main.OnStart()
core.titleChoose(main.state(),nil)
local g=main.state();g.hurt=function() return false end
for phase=0,23 do
  local frames=0
  while g.state=='enemy' and frames<180*60 do
    core.update(g,{},1/60);frames=frames+1
    if frames%30==0 then main.OnLevelUpdate(0) end
  end
  assert(g.state=='menu','render flow failed at phase '..phase)
  main.OnLevelUpdate(0)
  if phase<23 then
    g:menuChoose(0);g:stopAttack()
    for _=1,80 do core.update(g,{},1/60) end
  end
end
g:menuChoose(0);g:stopAttack();core.step(g,2,{})
main.OnLevelUpdate(0)
assert(g.result=='kill')
for _,message in ipairs(logs) do
  assert(not message:find(' ERR ') and not message:find('监听注册失败'),message)
end
io.write('PASS all 24 phases sampled through adapter; created '..#controls..' mock controls\n')
main.OnDestroy()
