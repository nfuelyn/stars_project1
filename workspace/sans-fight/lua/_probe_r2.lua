package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local core = require('lua' .. '.core')
local atk  = require('lua' .. '.attacks')

print('=== 只用“行动/道具/仁慈”（不选 FIGHT）能否走到结局 ===')
local function run(strategy, label)
  local g = core.newGame({ scripts = atk, hp = 1000000, difficulty = 'normal' })
  local guard, visits, maxr = 0, {}, -1
  while g.state ~= 'result' and guard < 120 do
    guard = guard + 1
    if g.state == 'enemy' then
      if g.round > maxr then maxr = g.round end
      local k = tostring(g.round)
      visits[k] = (visits[k] or 0) + 1
      g:endEnemy()
    elseif g.state == 'menu' then g:menuChoose(strategy)
    elseif g.state == 'sub' then g:subConfirm()
    else core.update(g, { left=false,right=false,up=false,down=false,confirm=false,cancel=false }, core.DT) end
  end
  print(string.format('  %s: guard=%d state=%s 最高回合=%d fightCount=%s result=%s interlude=%s final=%s',
    label, guard, tostring(g.state), maxr, tostring(g.fightCount), tostring(g.result), tostring(g.interlude), tostring(g.final)))
  local rep = {}
  for k, v in pairs(visits) do if v > 1 then rep[#rep+1] = k..'x'..v end end
  table.sort(rep, function(a,b) return (tonumber(a:match('^(%d+)')) or 0) < (tonumber(b:match('^(%d+)')) or 0) end)
  print('      重复访问的回合: ' .. (table.concat(rep, '  ') or '(无)'))
end
run(1, '只选“行动”（ACT->检查）')
run(2, '只选“道具”（ITEM->面包）')
run(3, '只选“仁慈”->饶恕')
