package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = M.DT
local g = M.newGame({ scripts = A, hp = 1000000 })
g:startEnemyScript('final'); g.state='enemy'; g.enemyDur=1e9
local seen = {}
local n, bad = 0, 0
for i = 1, math.floor(60*60) do
  M.update(g, {}, DT)
  if g.world then
    for _, b in ipairs(g.world.blasters) do
      if b.persistent and not seen[b] then
        seen[b] = true; n = n + 1
        -- 轴心应为 (320,306)：起点 = 轴心 + 450u，终点应为 轴心 + 150u = 轴心 + (起点-轴心)/3
        local ix = 320 + (b.sx - 320) / 3
        local iy = 306 + (b.sy - 306) / 3
        local dx, dy = b.ex - ix, b.ey - iy
        local off = math.sqrt(dx*dx + dy*dy)
        if off > 1 then
          bad = bad + 1
          if bad <= 8 then
            print(string.format('  光束#%d  实际终点(%.0f,%.0f)  应有终点(%.0f,%.0f)  偏差 %.0fpx  ang=%.1f',
              n, b.ex, b.ey, ix, iy, off, b.ang or 0))
          end
        end
      end
    end
  end
  if g.world and g.world.ended then break end
end
print(string.format('旋转阶段共 %d 发持续光束，其中 %d 发终点被钳制（轴心偏移）', n, bad))
