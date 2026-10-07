-- 复核：sans_bonegap2（HUD4/13）真实运行时的上下骨缝 = 18px？
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = M.DT
local csv
for _, s in ipairs(A) do if s.name == 'sans_bonegap2' then csv = s.csv end end
local w = M.newWorld({ seed = 20260927, script = M.parseCSV(csv) })
local seen, printed = {}, 0
for i = 1, math.floor(60 * 6) do
  w:update(DT)
  for _, b in ipairs(w.bones) do
    if not b.stab and b.axis == 'v' and not seen[b] then
      seen[b] = true
      -- 同一帧成对出现的上/下骨：上骨 y=257，下骨 y>=340
      if b.y == 257 then
        for _, b2 in ipairs(w.bones) do
          if b2 ~= b and b2.y ~= 257 and b2.axis == 'v' and b2.x == b.x then
            local gap = b2.y - (b.y + b.h)
            if printed < 6 then
              print(string.format('上骨 y=%.0f h=%.0f 下缘=%.0f | 下骨 y=%.0f h=%.0f 上缘=%.0f | 缝=%.0fpx',
                b.y, b.h, b.y + b.h, b2.y, b2.h, b2.y, gap))
              printed = printed + 1
            end
            break
          end
        end
      end
    end
  end
  if w.ended then break end
end
print('共取样 ' .. printed .. ' 组（期望缝恒 18px）')
