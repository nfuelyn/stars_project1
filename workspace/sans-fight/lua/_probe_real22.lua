package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = M.DT

-- 直接从 attacks.lua 取真实 multi3
local csv
for _, s in ipairs(A) do if s.name == 'multi3' then csv = s.csv end end
assert(csv and csv:find('BoneVRepeat,121,354,37,2,0,20,20', 1, true),
       'attacks.lua 里没有新的底边骨带行')

local function trySeed(seed)
  -- 真实游戏路径：startRound=21 -> HUD ROUND 22 = multi3
  local g = M.newGame({ scripts = A, hp = 1000000, startRound = 21, seed = seed, difficulty = 'original' })
  local hit, snap = false, nil
  for i = 1, 60 * 120 do
    M.update(g, {}, DT)
    if g.world then
      local row = {}
      for _, b in ipairs(g.world.bones) do
        if b.axis == 'v' and math.abs((b.y or -1) - 354) < 0.5 and math.abs((b.h or -1) - 37) < 0.5 then
          row[#row + 1] = b
        end
      end
      if #row > 0 then
        hit = true
        table.sort(row, function(p, q) return p.x < q.x end)
        snap = string.format('段用时=%.1fs  骨数=%d  y=%.0f h=%.0f  x=%.0f..%.0f  框=(%d,%d)-(%d,%d)',
          i * DT, #row, row[1].y, row[1].h, row[1].x, row[#row].x,
          g.world.zone.l, g.world.zone.t, g.world.zone.r, g.world.zone.b)
        break
      end
    end
    if g.state ~= 'enemy' then break end
  end
  return g.roundScript, hit, snap
end

for _, seed in ipairs({ 20260927, 1, 7, 42, 99, 2026, 123 }) do
  local script, hit, snap = trySeed(seed)
  print(string.format('seed=%-9s script=%-8s %s', tostring(seed), tostring(script), hit and ('命中：' .. snap) or '未抽到 Attack5'))
  if hit then break end
end
