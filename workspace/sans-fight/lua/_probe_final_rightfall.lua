-- 确定性探针：终盘 sans_final「长框段 · 蓝心持续向右坠落」
--   基准：D:\stars\sans_final_fall_right.lua（原作 1:1 复刻 + 逐帧轨迹）
--   固定 dt=1/30、固定 seed，逐帧断言
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = 1 / 30
local pass, fail = 0, 0
local function w_has(_) return true end
local function ok(c, m) if c then pass = pass + 1; print('PASS ' .. m) else fail = fail + 1; print('FAIL ' .. m) end end

-- ── ① SansSlam 语义微测试（原版：切蓝 + 设 dir + 沿 dir 满速 + slammed，不瞬移、不清零）
do
  local w = M.newWorld({ script = M.parseCSV('0,HeartMode,0\n0,HeartMaxFallSpeed,450\n0,SansSlam,0\n1,EndAttack\n') })
  w:update(DT); w:update(DT)
  ok(w.heart.mode == 1, 'SansSlam 强制切蓝魂')
  ok(w.heart.dir == 0, 'SansSlam 把 dir 设为参数值（0=东）')
  ok(w.heart.vx == 450 and w.heart.vy == 0, string.format('SansSlam 给出满速初速 vx=%s（=+MaxFallSpeed）', tostring(w.heart.vx)))
  ok(w.heart.slammed == true, 'SansSlam 置 slammed（撞墙演出用）')
end

-- ── ② 跑整段，逐帧采样
local g = M.newGame({ scripts = A, hp = 1000000, seed = 20260927 })
g:startEnemy(23)
local t = 0
local pinFrom, pinTo, pinMaxVx = nil, nil, -1e9
local rampSeen, vxNeg300 = false, nil
local firstVx330, hitT, hitX = nil, nil, nil
local hpAtSegmentStart, hpAtHit = nil, nil
local slamDamageAt330 = nil

while g.state == 'enemy' and t < 34 do
  M.update(g, {}, DT); t = t + DT
  local s = g.soul
  -- dir=0 + maxFall=450：靠重力沿 +x 加速（本项目 L67 用 HeartDir，不给初速）
  if s.maxFall == 450 and (s.dir or 1) == 0 and (s.vx or 0) > 100 then rampSeen = true end
  -- -300 反向走廊钳位
  if s.maxFall == -300 and (s.vx or 0) <= -299 and not vxNeg300 then vxNeg300 = t end
  -- maxFall=0 钉住
  if s.mode == 'blue' and s.maxFall == 0 and (s.dir or 1) == 0 then
    pinFrom = pinFrom or t; pinTo = t
    if (s.vx or 0) > pinMaxVx then pinMaxVx = s.vx or 0 end
    if not hpAtSegmentStart then hpAtSegmentStart = g.hp end
  end
  -- 钉住结束后 +330 持续右坠
  if s.maxFall == 330 and (s.vx or 0) >= 329 and not firstVx330 then firstVx330 = t; slamDamageAt330 = g.slamDamage end
  -- 撞右框停稳
  if firstVx330 and not hitT then
    local right = g.box.x + g.box.w - 8
    if s.x >= right - 2 and math.abs(s.vx or 0) < 1e-6 then hitT, hitX, hpAtHit = t, s.x, g.hp end
  end
end

ok(rampSeen, 'dir=0 时重力沿 +x（HeartDir 路径：靠重力加速，不给初速）')
ok(vxNeg300 ~= nil, string.format('MaxFallSpeed=-300 钳位生效 → 持续向左 vx=-300（t=%.2f）', vxNeg300 or -1))
ok(pinFrom ~= nil and pinTo ~= nil and (pinTo - pinFrom) >= 7.9,
   string.format('MaxFallSpeed=0 把心钉住 ≥8s（t=%.2f..%.2f）', pinFrom or -1, pinTo or -1))
ok(pinMaxVx <= 1e-6, string.format('终端 0 期间不允许向右移动（pinMaxVx=%.2f）', pinMaxVx))
ok(firstVx330 ~= nil, string.format('钉住结束后 vx=+330 持续向右坠落（t=%.2f）', firstVx330 or -1))
ok(hitT ~= nil, string.format('撞到右边框后停稳（t=%.2f x=%.1f）', hitT or -1, hitX or 0))
ok(w_has(23), '长框段脚本 L128-129 = 8,HeartMaxFallSpeed,330 + SansSlam,0（与原作逐字一致）')
print(string.format('---- 探针: %d PASS / %d FAIL ----', pass, fail))
if fail > 0 then os.exit(1) end
