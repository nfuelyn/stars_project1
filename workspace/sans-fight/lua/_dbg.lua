-- _dbg.lua —— 临时调试：内置生成器兜底为什么不跑了（用完即删）
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local E = {}
local DT = M.DT

local function probe(name, opts)
  local g = M.newGame(opts)
  print(string.format('-- %s: testNoScript=%s testNoSpawn=%s round=%s script=%s world=%s world.script=%s',
    name, tostring(g.testNoScript), tostring(g.testNoSpawn), tostring(g.round), tostring(g.roundScript),
    tostring(g.world ~= nil), tostring(g.world and g.world.script ~= nil)))
  local walls, floors = 0, 0
  for i = 1, math.floor(4 / DT) do
    M.update(g, E, DT)
    if #g.walls > walls then walls = #g.walls end
    for _, b in ipairs((g.world and g.world.bones) or {}) do
      if b.kind == 'floor' and floors == 0 then floors = i end
    end
  end
  print(string.format('   wallsPeak=%d firstFloorFrame=%d state=%s', walls, floors, g.state))
  for _, l in ipairs(g.logs or {}) do print('   log: ' .. l) end
end

probe('round2 hard noScript', { seed = 7, startRound = 2, difficulty = 'hard', scripts = A, noScriptRounds = true })
probe('round2 hard default ', { seed = 7, startRound = 2, difficulty = 'hard', scripts = A })
probe('round1 noScript', { seed = 1, scripts = A, noScriptRounds = true })
