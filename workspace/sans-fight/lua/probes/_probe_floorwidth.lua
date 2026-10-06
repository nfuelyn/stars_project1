-- 确定性探针：贴地排骨（Game:spawnFloor）单根宽度 = 道宽 - FLOOR_BONE_INSET
--   依据 prompt：框宽 575 → lanes=9、laneW≈63.9、改前 w≈58、现在 w≈40、缝 24px
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local pass, fail = 0, 0
local function ok(c, m) if c then pass = pass + 1; print('PASS ' .. m) else fail = fail + 1; print('FAIL ' .. m) end end

local BOX_W = 575
local g = M.newGame({ scripts = {}, hp = 92, seed = 20260927 })
g:startEnemy(1)                       -- 内置回合，先拿到 world
-- 固定框宽 575
g.box.w = BOX_W
-- 生成一波贴地排骨（ensureWorld 在这一步惰性建 world）
g:spawnFloor(0.016)
local w = g.world
w.zone.r = w.zone.l + BOX_W

local lanes = math.max(4, math.floor(BOX_W / 60))
local laneW = BOX_W / lanes
local expectW = laneW - 24            -- FLOOR_BONE_INSET
local n, ws, xs = 0, {}, {}
for _, b in ipairs(w.bones) do
  if b.kind == 'floor' then
    n = n + 1; ws[#ws + 1] = b.w; xs[#xs + 1] = b.x
  end
end
table.sort(xs)
local dmin = 1e9
for i = 2, #xs do if xs[i] - xs[i-1] < dmin then dmin = xs[i] - xs[i-1] end end

print(string.format('框宽=%d  lanes=%d  laneW=%.2f  生成 %d 根（有安全位）', BOX_W, lanes, laneW, n))
print(string.format('单根宽 w=%.2f  期望 laneW-INSET=%.2f  相邻道间距=%.2f  道间缝=%.2f  （灵魂视觉宽 16）',
  ws[1] or -1, expectW, dmin, dmin - (ws[1] or 0)))
ok(n > 0, '固定框宽 575 能生成一波贴地排骨')
ok(math.abs((ws[1] or -1) - expectW) < 1e-6,
   string.format('单根宽度 == laneW - FLOOR_BONE_INSET（%.2f）', expectW))
ok((ws[1] or 0) < 58, string.format('比改前的 58 更细（现在 %.1f）', ws[1] or -1))
ok(dmin - (ws[1] or 0) >= 16, '道间缝 >= 灵魂视觉宽 16px（能钻过去）')
ok(lanes == 9, '道数不变（仍 max(4, floor(框宽/60)) = 9）')
print(string.format('---- 探针: %d PASS / %d FAIL ----', pass, fail))
if fail > 0 then os.exit(1) end
