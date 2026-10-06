--=============================================================================
-- blue_soul.lua  --  蓝色灵魂（Blue SOUL / 重力模式）运动与物理复刻
--=============================================================================
-- 来源：D:\c2-sans-fight-src  (Construct 2 工程 "Bad Time Simulator" / Sans Fight)
--
--   * Event sheets/Battle.xml  ->  事件组 "PlayerMovement"
--        - 函数 HeartMode / HeartCheckSolid / HeartJump / SansSlam / HeartMaxFallSpeed
--        - 常量 HEART_JUMP_STRENGTH = 180
--               HEART_JUMPHOLD_CUTOFF = 30
--               HeartSpeed            = 150   (按住 Cancel 时 = 75)
--               MaxFallSpeed          = 750   (可被 HeartMaxFallSpeed 改写)
--   * Layouts/BattleScreen.xml ->  PlayerHeart 实例
--        - 16 x 16、hotspot 居中、初始 angle = 1.5707963 rad (= 90 度, 重力向下)
--        - CustomMovement: stepping-mode = "Horizontal then vertical",
--          pixels-per-step = 1
--   * Layouts/System.xml       ->  VPad 虚拟手柄
--        - Up / Down / Left / Right / Cancel 与 LastUp..LastCancel (上一帧, 用于边沿)
--   * Files/sans_platforms*.csv、sans_multi3.csv 等 -> "HeartMode,1/0" 切换红/蓝模式,
--        "Platform, ..." 生成可站立的移动平台
--
-- 本文件是**独立的纯 Lua (5.1+) 参考实现**，不依赖 LÖVE 或任何引擎，可直接被
-- `require` 或 `dofile`。它把上面源码里的规则一一对应地重写为可运行的物理循环。
--
-------------------------------------------------------------------------------
-- 【运动方式与物理规则摘要】
--
-- 1) 两种模式
--      RED  (0)：四方向匀速移动，无重力、无惯性；对轴同时按下则停住。
--      BLUE (1)：重力模式。灵魂 16x16，沿 "重力方向" 受重力，可起跳、可变跳跃高度、
--                可横向匀速微调。
--
-- 2) 重力方向由灵魂角度决定：(gx, gy) = (cos(a), sin(a))
--      a =   0 度 -> 重力向右      a =  90 度 -> 重力向下（默认蓝色）
--      a = 180 度 -> 重力向左      a = 270 度 -> 重力向上
--    蓝色灵魂进入时源里统一 Set angle = 90（重力向下）。
--
-- 3) 重力是"分段的"（按沿重力方向的速度投影 DownSpeed 选大小，单位 px/s^2）：
--      DownSpeed <= -120              -> 180   （高速上冲：轻，保持冲劲）
--      -120 < DownSpeed <= -30        -> 450   （中速上升：重，迅速刹车）
--      -30  < DownSpeed <= 15         -> 180   （顶点附近：轻，滞空）
--      15   < DownSpeed <  240        -> 540   （下落：重）
--      DownSpeed >= 240               -> 源里四个 IF 都不命中，沿用上一 tick 的
--                                        Gravity（实际恒为 540）
--    注意：DownSpeed 取的是"施加本帧重力之前"的速度（与源里事件顺序一致）。
--
-- 4) 重力施加与下落限速
--      若 (0.2 * 重力单位矢量) 处没有固体：
--          v += 重力单位矢量 * Gravity * dt
--      并把沿重力方向的速度分量钳制到 MaxFallSpeed（默认 750，可改）。
--      "前方 0.2px 有固体就不加" 是为了避免把灵魂压进地面/平台。
--
-- 5) 起跳
--      与重力反向的那个键（重力向下->上，向下向上->下，向右->左，向左->右）
--      被"刚按下"时，若 (1 * 重力单位矢量) 处有固体（即站在地面/平台上）：
--          v -= 重力单位矢量 * HEART_JUMP_STRENGTH(180)
--      即起跳初速 180 px/s。
--
-- 6) 可变跳跃高度（松键截断）
--      松开跳跃键的瞬间，若仍在上冲且上升速度 > 30 px/s，
--      把沿重力方向的速度分量直接设为 -30（= 保持 30 px/s 上冲）。
--      => 轻点 = 小跳；按住 = 满跳。
--
-- 7) 横向移动（无惯性，直接赋值）
--      每 tick 先把"垂直于重力"的速度分量清零，再：
--        重力竖直（90/270）：Left / Right -> vx = -/+ HeartSpeed
--        重力水平（0/180）  ：Up   / Down  -> vy = -/+ HeartSpeed
--      HeartSpeed = 150；按住 Cancel（Shift）时 = 75。
--      左右（或上下）同时按下：该轴速度为 0（源里只在两键不相等时才赋值）。
--
-- 8) 站立 / 平台
--      重力竖直时，若在 (0.5 * 重力单位矢量) 偏移处与平台重叠，则
--      吸附到平台迎重力面（向下->平台顶，向上->平台底），并继承平台速度。
--      源里"重力水平"分支的平台吸附被禁用（DISABLED），只有竖直重力会踩平台。
--      HeartCheckSolid：竖直重力时平台算固体；水平重力时平台分支在源里被禁用，
--      因此水平重力下只有边界墙算固体。
--
-- 9) 碰撞 / 步进
--      CustomMovement 以 1px 为步长、按 "先水平后竖直" 推进。
--      撞到边界墙时把该轴速度清零（源里 On horizontal/vertical step +
--      HeartCheckSolid(0,0) + Stop stepping）。
--
-- 10) 猛砸 (SansSlam)
--      被 SansSlam(dir) 命中时：切到 BLUE、角度 = dir*90、沿重力方向给出
--      MaxFallSpeed 的初速，并置 Slammed = true。
--      之后一旦撞墙：清除 Slammed；若撞击速度 >= 330 则触发震动/音效，
--      并在 SlamDamage=true 且 HP>1 时扣 1 点 HP。
--
--------------------------------------------------------------------------------
-- 与源实现的少量工程化差异（已在注释中标注，便于对照）：
--   * 源的实体/事件是数据驱动的；这里用纯表格 (x,y,w,h,vx,vy) 描述平台与边墙。
--   * "On horizontal/vertical step" 的 C2 内部触发语义，这里等价实现为
--     "1px 步进时该轴被挡 -> 该轴速度清零"。
--   * 源用数组 Current/Last 索引保存 VPad 边沿；这里由输入表 + lastInput 复现。
--==============================================================================

local BlueSoul = {}
BlueSoul.__index = BlueSoul
BlueSoul.VERSION = "1.0"

--=============================================================================
-- 常量（对应 Battle.xml 中 PlayerMovement 的 constant 变量）
--=============================================================================
BlueSoul.MODE_RED  = 0
BlueSoul.MODE_BLUE = 1

BlueSoul.JUMP_STRENGTH     = 180    -- HEART_JUMP_STRENGTH
BlueSoul.JUMPHOLD_CUTOFF   = 30     -- HEART_JUMPHOLD_CUTOFF
BlueSoul.HEART_SPEED       = 150    -- HeartSpeed
BlueSoul.HEART_SPEED_SLOW  = 75     -- Cancel 按住时 HeartSpeed
BlueSoul.DEFAULT_MAX_FALL  = 750    -- MaxFallSpeed
BlueSoul.PIXELS_PER_STEP   = 1      -- CustomMovement "pixels-per-step"
BlueSoul.SLAM_DAMAGE_SPEED = 330    -- 撞墙 >= 330 触发震动/伤害

-- 重力分段大小（px/s^2）
BlueSoul.GRAVITY_UP_FAST = 180      -- DownSpeed <= -120
BlueSoul.GRAVITY_UP_SLOW = 450      -- -120 < DownSpeed <= -30
BlueSoul.GRAVITY_APEX    = 180      -- -30  < DownSpeed <= 15
BlueSoul.GRAVITY_FALL    = 540      -- DownSpeed > 15（含 >=240 的沿用情形）

local abs, min = math.abs, math.min
local cos, sin, pi = math.cos, math.sin, math.pi

local function deg2rad(d) return d * pi / 180 end
local function rad2deg(r) return r * 180 / pi end

-- AABB 相交：soul 的包围盒 (sx,sy,sw,sh) 与矩形 r 是否重叠
local function overlaps(sx, sy, sw, sh, r)
    return sx < r.x + r.w and r.x < sx + sw
       and sy < r.y + r.h and r.y < sy + sh
end

--=============================================================================
-- 重力分段选择（严格对应源里四个独立的 IF，按顺序判断）
--   v = DownSpeed，prev = 上一 tick 的 Gravity
--=============================================================================
function BlueSoul.gravityBandFor(v, prev)
    if v > 15 and v < 240 then
        return BlueSoul.GRAVITY_FALL     -- IF DownSpeed < 240 and > 15
    elseif v > -30 and v <= 15 then
        return BlueSoul.GRAVITY_APEX     -- IF DownSpeed <= 15 and > -30
    elseif v > -120 and v <= -30 then
        return BlueSoul.GRAVITY_UP_SLOW  -- IF DownSpeed <= -30 and > -120
    elseif v <= -120 then
        return BlueSoul.GRAVITY_UP_FAST  -- IF DownSpeed <= -120
    end
    -- v >= 240：源里不命中任何分支，沿用旧值
    return prev or BlueSoul.GRAVITY_FALL
end

--=============================================================================
-- 世界 / 场景
--   world = {
--     borders   = { {x,y,w,h}, ... },              -- 硬固体（对应 CombatZoneBorder，带 Solid 行为）
--     platforms = { {x,y,w,h,vx=0,vy=0}, ... },    -- 单向平台（对应 Platform1，可移动）
--   }
--=============================================================================
function BlueSoul.newWorld(opts)
    opts = opts or {}
    local left   = opts.left   or 0
    local top    = opts.top    or 0
    local right  = opts.right  or 640
    local bottom = opts.bottom or 480
    local t      = opts.thickness or 5
    local world = {
        borders = {
            { x = left,        y = top,          w = right - left,  h = t },              -- 上
            { x = left,        y = top,          w = t,             h = bottom - top },   -- 左
            { x = left,        y = bottom - t,   w = right - left,  h = t },              -- 下
            { x = right - t,   y = top,          w = t,             h = bottom - top },   -- 右
        },
        platforms = {},
    }
    if opts.platforms then
        for i = 1, #opts.platforms do
            world.platforms[i] = opts.platforms[i]
        end
    end
    return world
end

--=============================================================================
-- 构造
--=============================================================================
function BlueSoul.new(opts)
    opts = opts or {}
    local self = setmetatable({}, BlueSoul)

    self.w = opts.w or 16                 -- PlayerHeart 宽
    self.h = opts.h or 16                 -- PlayerHeart 高
    self.x = opts.x or 320                -- 中心坐标
    self.y = opts.y or 320
    self.dx = opts.dx or 0                -- CustomMovement.dx (px/s)
    self.dy = opts.dy or 0                -- CustomMovement.dy (px/s)

    self.mode = opts.mode or BlueSoul.MODE_BLUE
    self.angle = opts.angle ~= nil and deg2rad(opts.angle) or deg2rad(90)  -- 存弧度，同 C2 的 Angle 表达式
    self.maxFallSpeed = opts.maxFallSpeed or BlueSoul.DEFAULT_MAX_FALL

    self.gravity  = 0                     -- 上一 tick 选中的重力，用于 >=240 时"沿用"
    self.hp       = opts.hp or 20
    self.slammed  = false
    self.slamDamage = false
    self.visible  = true

    self.grounded = false
    self.world = opts.world

    -- 上一帧输入（对应 VPad.Last*）
    self.lastInput = { up = false, down = false, left = false, right = false, cancel = false }

    -- 回调（可选）：撞墙猛砸时触发
    self.onSlam = opts.onSlam

    return self
end

--=============================================================================
-- 基础存取
--=============================================================================
function BlueSoul:gravityUnit()
    return cos(self.angle), sin(self.angle)
end

function BlueSoul:getAngleDegrees()
    return rad2deg(self.angle)
end

function BlueSoul:setAngleDegrees(deg)
    self.angle = deg2rad(deg)
end

function BlueSoul:teleport(x, y)
    self.x, self.y = x, y
    self.visible = true
end

function BlueSoul:setMaxFallSpeed(v)
    self.maxFallSpeed = v
end

-- 对应 HeartMode(0/1)
function BlueSoul:setMode(mode)
    self.mode = mode
    if mode == BlueSoul.MODE_BLUE then
        self:setAngleDegrees(90)   -- 源里进入蓝色时 Set angle = 90
        self.gravity = 0
    end
end

-- 沿重力轴的速度分量（DownSpeed）
function BlueSoul:downSpeed()
    local gx, gy = self:gravityUnit()
    return self.dx * gx + self.dy * gy
end

-- 把"沿重力轴的速度分量"设为 target（保留垂直分量）
function BlueSoul:_setGravityAxisSpeed(gx, gy, target)
    if gy ~= 0 then
        self.dy = gy * target
    elseif gx ~= 0 then
        self.dx = gx * target
    end
end

-- 对应 HeartMaxFallSpeed 的下落限速
function BlueSoul:_clampFallSpeed(gx, gy)
    local vg = self.dx * gx + self.dy * gy
    if vg > self.maxFallSpeed then
        self:_setGravityAxisSpeed(gx, gy, self.maxFallSpeed)
    end
end

--=============================================================================
-- HeartCheckSolid(ox, oy)
--   把灵魂包围盒平移 (ox, oy)，与"固体"相交则返回 true（源里返回 1）。
--   固体 = 边界墙 + 平台；但平台只在竖直重力（角度约 90/270）时参与判定，
--   与源里 angle 0/180 分支被 DISABLED 的事实一致。
--=============================================================================
function BlueSoul:checkSolid(ox, oy, world)
    world = world or self.world
    local sx = self.x + ox - self.w * 0.5
    local sy = self.y + oy - self.h * 0.5

    if world then
        for i = 1, #world.borders do
            if overlaps(sx, sy, self.w, self.h, world.borders[i]) then
                return true
            end
        end
        local gx, gy = self:gravityUnit()
        if gy ~= 0 then
            for i = 1, #world.platforms do
                if overlaps(sx, sy, self.w, self.h, world.platforms[i]) then
                    return true
                end
            end
        end
    end
    return false
end

-- 返回在 (nx, ny) 处与灵魂相交的第一个平台（单向平台判定用）
function BlueSoul:_platformAt(nx, ny, world)
    local sx = nx - self.w * 0.5
    local sy = ny - self.h * 0.5
    for i = 1, #world.platforms do
        local p = world.platforms[i]
        if overlaps(sx, sy, self.w, self.h, p) then
            return p
        end
    end
    return nil
end

--=============================================================================
-- 站立/骑乘平台：对应源里 "Is overlapping at offset(Platform1, X*0.5, Y*0.5)"
-- 仅在竖直重力下生效，吸附到平台迎重力面并继承平台速度。
--=============================================================================
function BlueSoul:_ridePlatform(world, gx, gy)
    if gy == 0 then return end                       -- 源里水平重力分支被禁用
    local p = self:_platformAt(self.x + gx * 0.5, self.y + gy * 0.5, world)
    if not p then return end

    local pvx, pvy = p.vx or 0, p.vy or 0

    -- 严格对应源里的四个前置条件（尤其是速度方向：
    -- 向外跳时不会被平台“吸住”）。
    if gy > 0 then
        -- Angle 90: Platform.Y > Heart.Y 且 Heart.dy >= Platform.dy 且 Heart.BBoxBottom < Platform.BBoxTop+2
        if not (p.y > self.y) then return end
        if not (self.dy >= pvy) then return end
        if not (self.y + self.h * 0.5 < p.y + 2) then return end
        self.y = p.y - self.h * 0.5
    else
        -- Angle 270: Platform.Y < Heart.Y 且 Heart.dy <= Platform.dy 且 Heart.BBoxTop > Platform.BBoxBottom-2
        if not (p.y < self.y) then return end
        if not (self.dy <= pvy) then return end
        if not (self.y - self.h * 0.5 > p.y + p.h - 2) then return end
        self.y = p.y + p.h + self.h * 0.5
    end

    -- 源里两分量都赋为平台速度
    self.dx = pvx
    self.dy = pvy
    self.grounded = true
end

--=============================================================================
-- 撞墙处理：对应 On horizontal/vertical step + HeartCheckSolid(0,0)
--=============================================================================
function BlueSoul:_onAxisBlocked(axis)
    local v = axis == "x" and self.dx or self.dy
    if axis == "x" then self.dx = 0 else self.dy = 0 end

    if self.slammed then
        self.slammed = false                         -- 撞到即清除
        if abs(v) >= BlueSoul.SLAM_DAMAGE_SPEED then
            if self.onSlam then self.onSlam(self, abs(v), axis) end
            if self.slamDamage and self.hp > 1 then
                self.hp = self.hp - 1
            end
        end
    end
end

-- 该轴是否撞到硬固体（边界墙）
function BlueSoul:_blocksAt(nx, ny, world)
    local sx = nx - self.w * 0.5
    local sy = ny - self.h * 0.5
    for i = 1, #world.borders do
        if overlaps(sx, sy, self.w, self.h, world.borders[i]) then
            return true
        end
    end
    return false
end

-- 平台吸附：把灵魂贴到平台迎重力面，并继承平台沿重力方向的速度
function BlueSoul:_snapOntoPlatform(p, gx, gy)
    if gy > 0 then
        self.y = p.y - self.h * 0.5
    elseif gy < 0 then
        self.y = p.y + p.h + self.h * 0.5
    elseif gx > 0 then
        self.x = p.x - self.w * 0.5
    else
        self.x = p.x + p.w + self.w * 0.5
    end
    self.dx = p.vx or 0
    self.dy = p.vy or 0
    self.grounded = true
end

-- 沿单轴以 1px 步长推进，遇墙清零、遇单向平台吸附
function BlueSoul:_stepAxis(axis, dist, world, gx, gy)
    if dist == 0 then return end
    local sign = dist > 0 and 1 or -1
    local remain = abs(dist)
    local stepLen = BlueSoul.PIXELS_PER_STEP
    local gravityDir = (axis == "x") and gx or gy   -- 该轴上的重力符号

    while remain > 1e-9 do
        local d = min(stepLen, remain)
        local nx, ny = self.x, self.y
        if axis == "x" then nx = nx + sign * d else ny = ny + sign * d end

        if self:_blocksAt(nx, ny, world) then
            self:_onAxisBlocked(axis)
            return
        end

        -- 单向平台：仅当"沿重力方向"下落踏到平台时吸附
        if gravityDir ~= 0 and sign == gravityDir then
            local p = self:_platformAt(nx, ny, world)
            if p then
                self.x, self.y = nx, ny
                self:_snapOntoPlatform(p, gx, gy)
                return
            end
        end

        self.x, self.y = nx, ny
        remain = remain - d
    end
end

-- 位移 + 碰撞：严格"先水平后竖直"（源 stepping-mode = Horizontal then vertical）
function BlueSoul:_moveWithCollisions(dt, world, gx, gy)
    self:_stepAxis("x", self.dx * dt, world, gx, gy)
    self:_stepAxis("y", self.dy * dt, world, gx, gy)
end

--=============================================================================
-- 输入归一化
--=============================================================================
local function normInput(input)
    input = input or {}
    return {
        up     = input.up     and true or false,
        down   = input.down   and true or false,
        left   = input.left   and true or false,
        right  = input.right  and true or false,
        cancel = input.cancel and true or false,
    }
end

-- 与重力反向的那个跳跃键（当前值, 上一帧值）
function BlueSoul:_jumpKey(input, gx, gy)
    local cur
    if gy > 0 then          cur = input.up
    elseif gy < 0 then      cur = input.down
    elseif gx > 0 then      cur = input.left
    else                    cur = input.right end

    local last
    if gy > 0 then          last = self.lastInput.up
    elseif gy < 0 then      last = self.lastInput.down
    elseif gx > 0 then      last = self.lastInput.left
    else                    last = self.lastInput.right end
    return cur, last
end

--=============================================================================
-- 红心模式（对照用）：四方向匀速，无惯性
--=============================================================================
function BlueSoul:_updateRed(input)
    local speed = input.cancel and BlueSoul.HEART_SPEED_SLOW or BlueSoul.HEART_SPEED
    if input.up ~= input.down then
        if input.up then self.dy = -speed end
        if input.down then self.dy = speed end
    else
        self.dy = 0
    end
    if input.left ~= input.right then
        if input.left then self.dx = -speed end
        if input.right then self.dx = speed end
    else
        self.dx = 0
    end
end

--=============================================================================
-- 蓝心模式：核心物理
--=============================================================================
function BlueSoul:_updateBlue(dt, input, world)
    local gx, gy = self:gravityUnit()
    local vertical = (gy ~= 0)

    -- (2) DownSpeed 用"施加本帧重力之前"的速度（与源事件顺序一致）
    local downSpeed = self.dx * gx + self.dy * gy
    self.gravity = BlueSoul.gravityBandFor(downSpeed, self.gravity)

    -- (4) 施加重力：前方 0.2px 无固体才加，避免压进地面
    if not self:checkSolid(gx * 0.2, gy * 0.2, world) then
        self.dx = self.dx + gx * self.gravity * dt
        self.dy = self.dy + gy * self.gravity * dt
        self:_clampFallSpeed(gx, gy)
    end

    -- (5)(6) 起跳 / 松键截断
    local jumpCur, jumpLast = self:_jumpKey(input, gx, gy)
    if jumpCur and not jumpLast and self:checkSolid(gx, gy, world) then
        self.dx = self.dx - gx * BlueSoul.JUMP_STRENGTH
        self.dy = self.dy - gy * BlueSoul.JUMP_STRENGTH
    end
    if (not jumpCur) and jumpLast then
        local vg = self.dx * gx + self.dy * gy
        if vg < -BlueSoul.JUMPHOLD_CUTOFF then
            self:_setGravityAxisSpeed(gx, gy, -BlueSoul.JUMPHOLD_CUTOFF)
        end
    end

    -- (7) 横向：垂直分量清零后直接赋值
    local speed = input.cancel and BlueSoul.HEART_SPEED_SLOW or BlueSoul.HEART_SPEED
    if vertical then
        self.dx = 0
        self:_ridePlatform(world, gx, gy)            -- 源里平台吸附在此分支
        if input.left ~= input.right then
            if input.left then self.dx = -speed end
            if input.right then self.dx = speed end
        end
    else
        self.dy = 0
        if input.up ~= input.down then
            if input.up then self.dy = -speed end
            if input.down then self.dy = speed end
        end
    end

    self.grounded = self:checkSolid(gx, gy, world)

    -- (9) 位移 + 碰撞
    self:_moveWithCollisions(dt, world, gx, gy)
end

--=============================================================================
-- 每帧更新（替代 Construct 的 Every tick）
--   input: {up,down,left,right,cancel}
--   world: 见 BlueSoul.newWorld
--=============================================================================
function BlueSoul:update(dt, input, world)
    world = world or self.world
    self.world = world
    local cur = normInput(input)

    if self.mode == BlueSoul.MODE_BLUE then
        self:_updateBlue(dt, cur, world)
    else
        self:_updateRed(cur)
        self:_moveWithCollisions(dt, world, 0, 0)
    end

    self.lastInput = cur
    return self
end

--=============================================================================
-- 事件接口（对应源里的函数调用）
--=============================================================================

-- SansSlam(dir)：dir 0/1/2/3 -> 角度 0/90/180/270；沿重力方向给 MaxFallSpeed
function BlueSoul:slam(dir)
    self:setMode(BlueSoul.MODE_BLUE)
    self:setAngleDegrees((dir or 0) * 90)
    self.slammed = true
    local gx, gy = self:gravityUnit()
    self.dx = gx * self.maxFallSpeed
    self.dy = gy * self.maxFallSpeed
end

-- SansSlamDamage(on)
function BlueSoul:setSlamDamage(on)
    self.slamDamage = on and true or false
end

return BlueSoul