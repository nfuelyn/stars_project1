-- 探针：终盘长框段的「骨头一次性生成量」与总时长（限流前后对比）
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = 1 / 30
local g = M.newGame({ scripts = A, hp = 1000000, seed = 20260927 })
g:startEnemy(23)
local t, prev, maxAdd, addFrame = 0, 0, 0, 0
local frames, firstBig = 0, nil
while g.state == 'enemy' and t < 60 do
  local before = g.world and #g.world.bones or 0
  M.update(g, {}, DT); t = t + DT; frames = frames + 1
  local after = g.world and #g.world.bones or 0
  local add = after - before
  if add > maxAdd then maxAdd, addFrame = add, frames; firstBig = t end
end
print(string.format('单帧最多新增骨头 = %d 根（t=%.2f）  全程 %d 帧（%.1fs）', maxAdd, firstBig or -1, frames, t))
print('（限流前：终盘长框段一帧 ~172 根 = ~860 个控件；限流后应 <= 约 45 根/帧）')
