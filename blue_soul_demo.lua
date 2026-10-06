--=============================================================================
-- blue_soul_demo.lua  --  blue_soul.lua 的可运行演示 / 自检
--   运行（在 D:\stars 下）:  D:\5.1\lua.exe blue_soul_demo.lua
--=============================================================================
local BlueSoul = dofile("blue_soul.lua")

local DT = 1.0 / 60.0
local function fmt(v) return string.format("%8.2f", v) end

-- 造一个 320x240 的场地，底边即地面（5px 厚的边界墙）
local function makeArena(extraPlatforms)
    return BlueSoul.newWorld({ left = 0, top = 0, right = 320, bottom = 240,
                               platforms = extraPlatforms })
end

local function settle(soul, world)
    for _ = 1, 180 do soul:update(DT, {}, world) end
end

-------------------------------------------------------------------------------
-- 1) 轻点跳 vs 按住跳
-------------------------------------------------------------------------------
local function jumpTest(holdFrames, label)
    local world = makeArena()
    local soul  = BlueSoul.new({ x = 160, y = 210, angle = 90 })
    settle(soul, world)
    local groundY = soul.y

    local peak, minVy = groundY, 0
    local airborne = false
    for i = 1, 400 do
        local input = { up = (i <= holdFrames) }
        soul:update(DT, input, world)
        if soul.y < peak then peak = soul.y end
        if soul.dy < minVy then minVy = soul.dy end
        if i > 3 and soul.grounded then
            if airborne then break end
        else
            airborne = true
        end
    end
    print(string.format("%-10s  地面y=%.1f  最高y=%.1f  跳跃高度=%6.2f px  起跳峰值速度=%7.2f px/s",
        label, groundY, peak, groundY - peak, minVy))
    return groundY - peak
end

print("=== 1) 蓝色灵魂：轻点跳 vs 按住跳 (dt=1/60) ===")
jumpTest(2,   "轻点(2f)")
jumpTest(6,   "中按(6f)")
jumpTest(60,  "满按(60f)")
print("")

-------------------------------------------------------------------------------
-- 2) 一次满跳的逐帧轨迹（观察分段重力）
-------------------------------------------------------------------------------
print("=== 2) 满跳轨迹（重力向下，按住 30 帧）===")
print("  frame |     y   |    vy    | Gravity | 阶段")
local world = makeArena()
local soul  = BlueSoul.new({ x = 160, y = 210, angle = 90 })
settle(soul, world)
local baseY = soul.y
for i = 1, 90 do
    local input = { up = (i <= 30) }
    soul:update(DT, input, world)
    if i <= 8 or i % 6 == 0 or soul.grounded then
        local phase = soul.dy < -30 and "上升" or (soul.dy > 15 and "下落" or "顶点")
        print(string.format("  %5d | %7.2f | %8.2f | %7d | %s%s",
            i, soul.y, soul.dy, soul.gravity, phase,
            soul.grounded and " (落地)" or ""))
    end
    if i > 5 and soul.grounded then break end
end
print(string.format("  （地面 y = %.2f）", baseY))
print("")

-------------------------------------------------------------------------------
-- 3) 松键截断：上升途中松开 -> 速度立即被钳到 -30
-------------------------------------------------------------------------------
print("=== 3) 松键截断（第 10 帧松开）===")
world = makeArena()
soul  = BlueSoul.new({ x = 160, y = 210, angle = 90 })
settle(soul, world)
for i = 1, 40 do
    local input = { up = (i <= 10) }
    soul:update(DT, input, world)
    if i >= 8 and i <= 14 then
        print(string.format("  frame %2d  vy = %8.2f   %s", i, soul.dy,
            i == 11 and "<- 松开瞬间被钳到 -30" or ""))
    end
    if i > 12 and soul.grounded then break end
end
print("")

-------------------------------------------------------------------------------
-- 4) 横向移动（无惯性、Cancel 减速）
-------------------------------------------------------------------------------
print("=== 4) 横向移动：按住右键 0.5s 的位移 ===")
local function lateralTest(cancel)
    local w = makeArena()
    local s = BlueSoul.new({ x = 40, y = 210, angle = 90 })
    settle(s, w)
    local x0 = s.x
    for _ = 1, 30 do s:update(DT, { right = true, cancel = cancel }, w) end
    print(string.format("  cancel=%-5s  水平速度=%7.2f px/s  0.5s 位移=%6.2f px",
        tostring(cancel), s.dx, s.x - x0))
end
lateralTest(false)
lateralTest(true)
print("")

-------------------------------------------------------------------------------
-- 5) 重力旋转：角度 0 = 重力向右，灵魂落向右侧墙
-------------------------------------------------------------------------------
print("=== 5) 重力旋转（角度 0 -> 重力向右）===")
world = makeArena()
soul  = BlueSoul.new({ x = 60, y = 120, angle = 0 })
for i = 1, 120 do
    soul:update(DT, {}, world)
    if i % 20 == 0 then
        print(string.format("  第 %3d 帧: x=%7.2f  y=%7.2f  vx=%8.2f  vy=%7.2f",
            i, soul.x, soul.y, soul.dx, soul.dy))
    end
end
print("")

-------------------------------------------------------------------------------
-- 6) 跳到移动平台上并被带走
-------------------------------------------------------------------------------
print("=== 6) 站上移动平台并被平台带走（重力向下）===")
local plat = { x = 150, y = 190, w = 70, h = 10, vx = 40, vy = 0 }
world = makeArena({ plat })
soul  = BlueSoul.new({ x = 185, y = 182, angle = 90, maxFallSpeed = 750 })
-- 稍微下落到平台上
for _ = 1, 60 do
    plat.x = plat.x + plat.vx * DT
    soul:update(DT, {}, world)
end
local rideX0 = soul.x
for _ = 1, 60 do
    plat.x = plat.x + plat.vx * DT
    soul:update(DT, {}, world)
end
print(string.format("  grounded=%s  平台x=%7.2f  灵魂x=%7.2f  1s 内灵魂被带走 %+.2f px",
    tostring(soul.grounded), plat.x, soul.x, soul.x - rideX0))
print("")

-------------------------------------------------------------------------------
-- 7) SansSlam：猛砸撞墙
-------------------------------------------------------------------------------
print("=== 7) SansSlam(1) 重力向下猛砸地面 ===")
world = makeArena()
soul  = BlueSoul.new({ x = 160, y = 40, angle = 90 })
local slammedSpeed = nil
soul.onSlam = function(_, speed) slammedSpeed = speed end
soul:setSlamDamage(true)
local hp0 = soul.hp
soul:slam(1)                    -- 角度 90 -> 重力向下
print(string.format("  初始 vy=%8.2f  Slammed=%s", soul.dy, tostring(soul.slammed)))
for i = 1, 200 do
    soul:update(DT, {}, world)
    if not soul.slammed then
        print(string.format("  第 %d 帧撞墙：撞击速度=%.2f  Slammed 清除，HP %d -> %d",
            i, slammedSpeed or 0, hp0, soul.hp))
        break
    end
end

print("")
print("demo 结束。")