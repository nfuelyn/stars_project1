-- _probe_blue_fall.lua —— 蓝心「自由落体终端速度」探针
-- 依据：D:\stars\Sans_Fight_原版蓝心运动逻辑与现状对比.md §4.1
--   原版 Battle.xml 的四个分段重力是**并列**事件，DownSpeed/Gravity 都是 <variable static="0">
--   → 每 tick 归 0；DownSpeed >= 240 时四档全不命中 → 本帧不加重力 → 自然终端 ≈243 px/s。
--   修前工作区在 dsp > 15 一律 540 → 一路加速到 MaxFallSpeed(750)。
-- 用法：node tools/run-lua.mjs lua/probes/_probe_blue_fall.lua
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = M.DT

local pass, fail = 0, 0
local function ok(cond, msg)
  if cond then pass = pass + 1; print('  PASS ' .. msg)
  else fail = fail + 1; print('  FAIL ' .. msg) end
end

-- 把蓝心放到框顶、清空脚本实体，只留"方向重力 + 终端钳位"这一套物理
local function fall(mf, dir, frames, trace)
  local g = M.newGame({ scripts = A, hp = 1000000 })
  g:startEnemyScript('sans_boneslideh')
  for _ = 1, 3 do M.update(g, {}, DT) end
  local s = g.soul
  s.mode, s.wall, s.slammed, s.jumping = 'blue', false, false, false
  s.dir = dir or 1
  s.maxFall = mf
  s.vx, s.vy = 0, 0
  s.x = g.box.x + g.box.w / 2
  s.y = g.box.y + 8
  s.grounded = false
  local vmax, vmin = 0, 0
  for i = 1, (frames or 90) do
    if g.world then g.world.bones, g.world.blasters, g.world.sine = {}, {}, {} end
    g.platforms = {}
    M.update(g, {}, DT)
    local v = s.vy or 0
    if v > vmax then vmax = v end
    if v < vmin then vmin = v end
    if trace and i <= trace then
      print(string.format('    f%-3d vy=%8.2f  y=%.1f%s', i, v, s.y, s.grounded and '  [落地]' or ''))
    end
  end
  return vmax, vmin, s
end

print('=== 蓝心自由落体终端探针（重力向下 dir=1）===')
print('')
print('[1] 默认 MaxFallSpeed = 750（脚本未改）—— 原版应为 ≈243，而不是 750')
print('    前 30 帧逐帧：')
local v1 = fall(750, 1, 90, 30)
print(string.format('    终端 vy = %.1f', v1))
ok(v1 > 235 and v1 < 250, string.format('自由落体终端 ≈243 px/s（实测 %.1f）', v1))
ok(v1 < 300, string.format('终端远低于 MaxFallSpeed(750)，说明死区生效（实测 %.1f）', v1))

print('')
print('[2] 脚本把 MaxFallSpeed 设成 330 / 450 / 480（都 > 243）—— 原版三者等价，都够不到')
local v330 = fall(330, 1, 90)
local v450 = fall(450, 1, 90)
local v480 = fall(480, 1, 90)
print(string.format('    maxFall=330 → %.1f   maxFall=450 → %.1f   maxFall=480 → %.1f', v330, v450, v480))
ok(math.abs(v330 - v1) < 1 and math.abs(v450 - v1) < 1 and math.abs(v480 - v1) < 1,
   '330/450/480 与原版一致：都等价于自然终端')

print('')
print('[3] MaxFallSpeed 是真·终端（< 243 时仍生效）')
local v60 = fall(60, 1, 90)
local v0 = fall(0, 1, 90)
print(string.format('    maxFall=60 → %.1f    maxFall=0 → %.1f', v60, v0))
ok(math.abs(v60 - 60) < 1, string.format('maxFall=60 被钳在 60（实测 %.1f）', v60))
ok(math.abs(v0) < 0.001, string.format('maxFall=0 钉住不动（实测 %.1f）', v0))

print('')
print('[4] 负值 = 反向走廊（maxFall=-300 沿重力反方向匀速）')
local vneg = select(1, fall(-300, 1, 90))
local _, vnegMin = fall(-300, 1, 90)
print(string.format('    maxFall=-300 → vy 上界 %.1f（应为负）', vnegMin))
ok(math.abs(vnegMin + 300) < 1, string.format('反向走廊匀速 -300（实测 %.1f）', vnegMin))

print('')
print('[5] 上升仍未被破坏：满跳峰值应仍是 ≈66.9 px（0.683s 到顶）')
do
  local g = M.newGame({ scripts = A, hp = 1000000 })
  g:startEnemyScript('sans_boneslideh')
  for _ = 1, 20 do M.update(g, {}, DT) end
  local s = g.soul
  local y0 = s.y
  M.jump(g)
  local peak, t = y0, 0
  for _ = 1, 300 do
    M.update(g, { jumpHeld = true }, DT); t = t + DT
    if s.y < peak then peak = s.y end
    if s.grounded and t > 0.05 then break end
  end
  local rise = y0 - peak
  print(string.format('    满跳峰值 = %.2f px（到顶/滞空约 %.3f s）', rise, t))
  ok(rise > 60 and rise < 72, string.format('满跳峰值 ≈66.9 px（实测 %.2f）', rise))
end

print('')
print(string.format('PASS %d / FAIL %d', pass, fail))
if fail > 0 then os.exit(1) end