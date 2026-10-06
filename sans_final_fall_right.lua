--=============================================================================
-- sans_final_fall_right.lua
-- 专注复刻：Sans 最后一段攻击（sans_final）中
--          「蓝心持续向右坠落」的长框段  ——  sans_final.csv L28 ~ L98
--=============================================================================
-- 来源：D:\c2-sans-fight-src
--   * Files/sans_final.csv            本段脚本（逐行对照见下方 SEGMENT）
--   * Event sheets/Battle.xml         PlayerMovement 组：蓝魂方向重力 + MaxFallSpeed 钳位
--   * Event sheets/Timeline.xml       TLPlay 脚本机（delay/命令/变量/JMP）
--   * Event sheets/Battle.xml CombatZone 组：战斗框伸缩 + 把灵魂夹在框内
--
-------------------------------------------------------------------------------
-- 【这段在干什么】
--   顺序（相对本段起点 t=0）：
--     t=0.50  HeartMode,0              红魂
--     t=2.70  SansSlam,2               甩向左（蓝魂、角度 180、v = -MaxFallSpeed）
--     t=3.20  HeartMaxFallSpeed,450
--     t=3.20  SansSlam,0               切蓝 + 角度 0（**重力向右**）+ v = +450
--     t=3.20  CombatZoneResizeInstant / Speed 900 / Resize ...
--             CombatZone 右边界 449 -> 650（**把框向右拉长**，越过屏幕右缘）
--     t=3.53  HeartMaxFallSpeed,-300   终端速度取负 -> 钳位把 vx 压到 -300（反向走廊）
--     t=3.53  CombatZoneResize -10,226,650,391  框向左铺满
--     t=3.83  CombatZoneSpeed 30 / Resize -10,264,650,369  缩成一条细走廊
--     t=4.73  GetHeartPos / HeartTeleport,40,<HeartY>
--             HeartMaxFallSpeed,0 / SansSlam,0
--             => 灵魂被钉在左端 x=40；重力仍向右，但终端速度 0，vx 被钳成 0，
--                玩家能向左/上下躲，却**无法向右移动**
--     t=4.73  L49~L92 生成整片骨墙（BoneV / BoneVRepeat，一律 speed=900 向左扫）
--     t=12.73 HeartMaxFallSpeed,330 / SansSlam,0
--             => ★ 蓝心开始**持续向右坠落**：vx 被钉在 +330 px/s（终端速度）
--     t=12.73 CombatZoneSpeed,540 / Resize -10,264,410,369
--             => 右边界 650 -> 410 收拢，灵魂一路向右滑到右框边并撞停
--     t=13.63 SansEndRepeat
--
-- 【物理要点（原版 Battle.xml / PlayerMovement 组）】
--   1) 蓝魂重力方向 = PlayerHeart.Angle = dir*90；dir 0/1/2/3 = 东/南/西/北
--      本段 dir=0 -> 重力沿 +x（向右）。
--   2) 沿重力方向的速度分量叫 DownSpeed；本段 DownSpeed = vx。
--      重力按 4 档曲线取值（本段 vx>=240 时不再加速，因此表现为"匀速右坠"）。
--   3) 每帧先施加重力，再做终端速度钳位：
--           if vx > MaxFallSpeed then vx = MaxFallSpeed end
--      于是 MaxFallSpeed 就是"持续右坠"的恒定速度：
--           450 -> 3.20s 一瞬；-300 -> 反向；0 -> 钉住；330 -> 持续右坠
--   4) 撞框（Slammed 且 |vx| >= 330）触发撞击演出；本段 SansSlamDamage=0，不额外扣 HP。
--   5) CombatZone 每帧把灵魂夹在框内（内缩 5px 边界 + 灵魂半身）。
--
-- 【与工作区的差异（重要）】
--   工作区 lua/attacks.lua 把本段的 L33 `SansSlam,0` 改写成 `HeartDir,0`：
--   只改重力方向、不给初速，让灵魂"靠重力自己滑到右框边"。
--   本文件默认复刻**原版**（SansSlam,0 会给 +450 初速）；
--   需要工作区语义时传 opts.evolve = "gravity_only"。
--=============================================================================

local SansFinalFallRight = {}
SansFinalFallRight.__index = SansFinalFallRight
SansFinalFallRight.VERSION = "1.0"

-- ---- 载入已校验的蓝魂物理模块 --------------------------------------------
local function loadBlueSoul()
    local ok, mod = pcall(dofile, "blue_soul.lua")
    if ok and type(mod) == "table" then return mod end
    local ok2, mod2 = pcall(require, "blue_soul")
    if ok2 and type(mod2) == "table" then return mod2 end
    error("需要 blue_soul.lua（与本文件同目录）")
end
local BlueSoul = loadBlueSoul()

--=============================================================================
-- 本段脚本（逐条对应 sans_final.csv L28 ~ L98）
--   每条 = { 相对上一行的 delay, 命令, {参数...} }
--   L49~L92 是骨墙生成循环，这里折叠成一条 "BoneWall"
--=============================================================================
SansFinalFallRight.SEGMENT = {
    { 0.5,     "HeartMode",              { 0 } },              -- L28
    { 2,       "SansBody",               { "HandLeft" } },     -- L29
    { 0.2,     "SansSlam",               { 2 } },              -- L30  甩向左
    { 0.3,     "SansBody",               { "HandRight" } },    -- L31
    { 0.2,     "HeartMaxFallSpeed",      { 450 } },            -- L32
    { 0,       "SansSlamOrDir",          { 0 } },              -- L33  原版=SansSlam,0；工作区=HeartDir,0
    { 0,       "CombatZoneResizeInstant",{ 241, 226, 449, 391 } },
    { 0,       "CombatZoneSpeed",        { 900 } },
    { 0,       "CombatZoneResize",       { 241, 226, 650, 391 } },   -- 右边界拉到 650
    { 0.33333, "HeartMaxFallSpeed",      { -300 } },           -- L37  反向走廊
    { 0,       "SansAnimation",          { "Idle" } },
    { 0,       "SansRepeat",             {} },
    { 0,       "CombatZoneResize",       { -10, 226, 650, 391 } },
    { 0.3,     "CombatZoneSpeed",        { 30 } },
    { 0,       "CombatZoneResize",       { -10, 264, 650, 369 } },   -- 细长走廊
    { 0.9,     "GetHeartPos",            { "HeartX", "HeartY" } },
    { 0,       "HeartTeleport",          { 40, "$HeartY" } },  -- 钉到左端
    { 0,       "HeartMaxFallSpeed",      { 0 } },              -- 终端速度 0
    { 0,       "SansSlam",               { 0 } },              -- 重力向右但 vx 被钳成 0
    { 0,       "BoneWall",               {} },                 -- L49 ~ L92 整片骨墙
    { 8,       "HeartMaxFallSpeed",      { 330 } },            -- L94
    { 0,       "SansSlam",               { 0 } },              -- L95  ★ 持续向右坠落 330
    { 0,       "CombatZoneSpeed",        { 540 } },
    { 0,       "CombatZoneResize",       { -10, 264, 410, 369 } },   -- 右边收拢到 410
    { 0.9,     "SansEndRepeat",          {} },                 -- L98
}

local DX = { [0] = 1, [1] = 0, [2] = -1, [3] = 0 }
local DY = { [0] = 0, [1] = 1, [2] = 0, [3] = -1 }

local function num(v) return tonumber(v) or 0 end
local function sdeg(d) return math.sin(math.rad(d)) end
local function approach(cur, target, step)
    if cur < target then return math.min(cur + step, target)
    elseif cur > target then return math.max(cur - step, target) end
    return cur
end
local function aabb(ax, ay, aw, ah, b)
    return ax < b.x + b.w and b.x < ax + aw and ay < b.y + b.h and b.y < ay + ah
end

--=============================================================================
-- 构造
--=============================================================================
function SansFinalFallRight.new(opts)
    opts = opts or {}
    local self = setmetatable({}, SansFinalFallRight)

    self.evolve = opts.evolve or "original"     -- "original" | "gravity_only"
    self.layoutW, self.layoutH = 640, 480

    -- CombatZone 初值取 Layouts/BattleScreen.xml: x=32,y=240,w=576,h=144
    self.zone = { left = 32, top = 240, right = 608, bottom = 384 }
    self.zoneTargets = nil
    self.resizeSpeed = 480

    -- 灵魂：初始与 sans_final 一致 (320,304)，红魂
    self.slamImpact = nil
    self.soul = BlueSoul.new({
        x = 320, y = 304, angle = 90, mode = BlueSoul.MODE_RED,
        -- 【关键】BlueSoul 在撞墙时会先把 Slammed 清零，撞击速度必须在回调里取
        onSlam = function(_, speed, axis)
            if not self.slamImpact then
                self.slamImpact = { t = self.t, speed = speed, axis = axis }
                self:log("slam_impact", self.slamImpact)
            end
        end,
    })
    self.soul.maxFallSpeed = 750

    self.bones = {}                 -- 本段骨墙（BoneV，一律 dir=2 向左）
    self.vars = { pi = math.pi }
    self.events = {}                -- 执行轨迹（便于观察/回归）
    self.hits = 0
    self.slamImpact = nil

    self.t = 0
    self.ei = 1
    local acc = 0
    for i = 1, #SansFinalFallRight.SEGMENT do
        acc = acc + SansFinalFallRight.SEGMENT[i][1]
        SansFinalFallRight.SEGMENT[i].abs = acc
    end

    return self
end

--=============================================================================
-- 场景 / 灵魂辅助
--=============================================================================
function SansFinalFallRight:log(kind, data)
    self.events[#self.events + 1] = { t = self.t, kind = kind, data = data }
end

function SansFinalFallRight:resize(l, t, r, b) self.zoneTargets = { l, t, r, b } end
function SansFinalFallRight:resizeInstant(l, t, r, b)
    self.zoneTargets = nil
    self.zone.left, self.zone.top, self.zone.right, self.zone.bottom = l, t, r, b
end

function SansFinalFallRight:updateZone(dt)
    local z = self.zone
    local tg = self.zoneTargets
    if not tg then return end
    local s = self.resizeSpeed * dt
    z.left   = approach(z.left,   tg[1], s)
    z.top    = approach(z.top,    tg[2], s)
    z.right  = approach(z.right,  tg[3], s)
    z.bottom = approach(z.bottom, tg[4], s)
    if z.left == tg[1] and z.top == tg[2] and z.right == tg[3] and z.bottom == tg[4] then
        self.zoneTargets = nil
    end
end

-- 由当前战斗框生成"边界墙"（对应 CombatZoneBorder，带 Solid 行为）
function SansFinalFallRight:zoneWorld()
    local z, th = self.zone, 5
    return {
        borders = {
            { x = z.left,          y = z.top,             w = z.right - z.left, h = th },
            { x = z.left,          y = z.top,             w = th,                h = z.bottom - z.top },
            { x = z.left,          y = z.bottom - th,     w = z.right - z.left, h = th },
            { x = z.right - th,    y = z.top,             w = th,                h = z.bottom - z.top },
        },
        platforms = {},
    }
end

-- 源里 CombatZone 组每帧把灵魂夹回框内（内缩 5px + 半身）
function SansFinalFallRight:clampSoul()
    local h, z = self.soul, self.zone
    local hw, hh = h.w * 0.5, h.h * 0.5
    if h.x - hw < z.left + 5 then h.x = z.left + 5 + hw end
    if h.y - hh < z.top + 5 then h.y = z.top + 5 + hh end
    if h.x + hw > z.right - 5 then h.x = z.right - 5 - hw end
    if h.y + hh > z.bottom - 5 then h.y = z.bottom - 5 - hh end
end

-- SansSlam(dir)：切蓝 + 设角度 + 沿重力满速甩出（原版 Battle.xml）
function SansFinalFallRight:sansSlam(dir)
    local s = self.soul
    s:setMode(BlueSoul.MODE_BLUE)          -- 会先把角度重置为 90（向下）
    s:setAngleDegrees(dir * 90)            -- 再设成本次甩击方向
    s.slammed = true
    local gx, gy = s:gravityUnit()
    s.dx = gx * s.maxFallSpeed
    s.dy = gy * s.maxFallSpeed
    self:log("sans_slam", { dir = dir, vx = s.dx, vy = s.dy, maxFall = s.maxFallSpeed })
end

-- HeartDir(dir)：只改重力方向（工作区语义），不给初速、不强制模式
function SansFinalFallRight:heartDir(dir)
    self.soul:setAngleDegrees(dir * 90)
    self:log("heart_dir", { dir = dir })
end

--=============================================================================
-- 骨墙（对应 sans_final.csv L49 ~ L92）
--   L49~L64: I=0..43，每列上下两根；x = 634 + I*60
--            Sine = floor(sin((I/2)*(180/pi) 度) * 25)
--            上骨 y=270 h=30+Sine；下骨 y=270+h+34, h2=364-y
--   L65~L83: 13 组 BoneVRepeat(…,3,15)，x 逐条累加
--   L84~L92: I=0..23，每列两根；x = 末值 + I*30, h = 10+I
--   全部 dir=2（向左）、speed=900
--=============================================================================
function SansFinalFallRight:spawnBoneWall()
    local n = 0
    local function boneV(x, y, h, dir, speed)
        self.bones[#self.bones + 1] = { x = x, y = y, w = 10, h = h, dir = dir or 2, speed = speed or 900 }
        n = n + 1
    end
    local function repeat3(x, y, h)
        for i = 0, 2 do boneV(x + 15 * i, y, h) end
    end

    -- L49 ~ L64
    for I = 0, 43 do
        local sine = math.floor(sdeg((I / 2) * (180 / math.pi)) * 25)
        local x = 634 + I * 60
        local hTop = 30 + sine
        boneV(x, 270, hTop)
        local y = 270 + hTop + 34
        boneV(x, y, 364 - y)
    end

    -- L65 ~ L83
    local X = 634 + 43 * 60
    local steps = { 360, 330, 300, 300, 270, 270, 240, 330, 270, 390 }
    local ys   = { 270, 314, 270, 314, 270, 314, 270, 314, 270, 314 }
    for k = 1, #steps do
        X = X + steps[k]
        repeat3(X, ys[k], 50)
    end

    -- L84 ~ L92
    for I = 0, 23 do
        local x2 = X + I * 30
        local h = 10 + I
        boneV(x2, 270, h)
        boneV(x2, 365 - h, h)
    end

    self:log("bone_wall", { count = n })
    return n
end

function SansFinalFallRight:updateBones(dt)
    local keep = {}
    for i = 1, #self.bones do
        local b = self.bones[i]
        b.x = b.x + (DX[b.dir] or 0) * dt * b.speed
        b.y = b.y + (DY[b.dir] or 0) * dt * b.speed
        if not (b.dir == 2 and b.x < -b.w) then keep[#keep + 1] = b end
    end
    self.bones = keep
end

--=============================================================================
-- 事件执行
--=============================================================================
function SansFinalFallRight:exec(ev)
    local cmd, p = ev[2], ev[3] or {}
    local s = self.soul

    if cmd == "HeartMode" then
        if num(p[1]) == 0 then s.mode = BlueSoul.MODE_RED else s:setMode(BlueSoul.MODE_BLUE) end
        self:log("heart_mode", { mode = num(p[1]) })
    elseif cmd == "HeartMaxFallSpeed" then
        s.maxFallSpeed = num(p[1])
        self:log("max_fall", { v = s.maxFallSpeed })
    elseif cmd == "HeartTeleport" then
        local x = p[1]
        local y = p[2]
        if type(y) == "string" and y:sub(1, 1) == "$" then y = self.vars[y:sub(2)] or 0 end
        s:teleport(num(x), num(y))
        self:log("teleport", { x = s.x, y = s.y })
    elseif cmd == "GetHeartPos" then
        self.vars[p[1]] = s.x
        self.vars[p[2]] = s.y
    elseif cmd == "SansSlam" then
        self:sansSlam(num(p[1]))
    elseif cmd == "SansSlamOrDir" then
        -- 只改这一处：工作区把原版 L33 的 SansSlam,0 换成 HeartDir,0
        if self.evolve == "gravity_only" then self:heartDir(num(p[1]))
        else self:sansSlam(num(p[1])) end
    elseif cmd == "CombatZoneResizeInstant" then
        self:resizeInstant(num(p[1]), num(p[2]), num(p[3]), num(p[4]))
        self:log("zone_instant", { l = self.zone.left, t = self.zone.top, r = self.zone.right, b = self.zone.bottom })
    elseif cmd == "CombatZoneResize" then
        self:resize(num(p[1]), num(p[2]), num(p[3]), num(p[4]))
        self:log("zone_resize", { l = num(p[1]), t = num(p[2]), r = num(p[3]), b = num(p[4]) })
    elseif cmd == "CombatZoneSpeed" then
        self.resizeSpeed = num(p[1])
    elseif cmd == "BoneWall" then
        self:spawnBoneWall()
    else
        self:log("cmd", { cmd = cmd })
    end
end

--=============================================================================
-- 每帧更新
--=============================================================================
function SansFinalFallRight:update(dt, input)
    self.t = self.t + dt

    -- 时间轴
    while self.ei <= #SansFinalFallRight.SEGMENT and self.t >= SansFinalFallRight.SEGMENT[self.ei].abs do
        self:exec(SansFinalFallRight.SEGMENT[self.ei])
        self.ei = self.ei + 1
    end

    self:updateZone(dt)

    -- 蓝魂物理（方向重力 / 跳跃 / 终端速度钳位）
    self.soul:update(dt, input or {}, self:zoneWorld())
    self:clampSoul()

    self:updateBones(dt)

    -- 骨墙命中（16x16 灵魂判定盒）
    local sx = self.soul.x - 8
    local sy = self.soul.y - 8
    for i = 1, #self.bones do
        if aabb(sx, sy, 16, 16, self.bones[i]) then
            self.hits = self.hits + 1
            self:log("bone_hit", { x = self.bones[i].x, y = self.bones[i].y })
            break
        end
    end
end

function SansFinalFallRight:run(seconds, dt, inputFn)
    dt = dt or 1 / 60
    local steps = math.floor((seconds or 15) / dt)
    for i = 1, steps do
        self:update(dt, inputFn and inputFn(self.t) or nil)
    end
    return self
end

--=============================================================================
-- 直接运行时的演示：打印"持续向右坠落"全过程
--=============================================================================
local function main()
    print("==================================================================")
    print(" sans_final.csv L28~L98  「蓝心持续向右坠落」长框段")
    print("==================================================================")
    print(string.format("%6s | %-21s | %7s | %4s | %8s | %8s | %4s | %s",
        "t(s)", "zone(l,r)", "maxFall", "蓝/红", "soul.x", "soul.vx", "骨", "note"))

    local sc = SansFinalFallRight.new()
    local dt = 1 / 60
    local lastNote, nextPrint = "", 0

    local function noteOf(t)
        if t >= 12.733 then return "★持续向右坠落 vx=330"
        elseif t >= 4.733 then return "钉在左端(重力向右/终端0)"
        elseif t >= 3.533 then return "反向走廊 -300"
        elseif t >= 3.200 then return "右甩 +450"
        elseif t >= 2.700 then return "甩向左 -750"
        end
        return "红魂/准备"
    end

    for i = 1, math.floor(15.0 / dt) do
        sc:update(dt, nil)
        if sc.t >= nextPrint then
            local note = noteOf(sc.t)
            if note ~= lastNote then note = "  <-- " .. note; lastNote = noteOf(sc.t) end
            print(string.format("%6.2f | %7.0f..%-11.0f | %7.0f | %4d | %8.1f | %8.1f | %4d | %s",
                sc.t, sc.zone.left, sc.zone.right, sc.soul.maxFallSpeed,
                sc.soul.mode == BlueSoul.MODE_BLUE and 0 or 1,
                sc.soul.x, sc.soul.dx, #sc.bones, note))
            nextPrint = nextPrint + 0.5
        end
    end

    print("")
    print(string.format("结束位置 x=%.1f  vx=%.1f  grounded=%s  累计骨墙命中=%d",
        sc.soul.x, sc.soul.dx, tostring(sc.soul.grounded), sc.hits))
    if sc.slamImpact then
        print(string.format("撞墙时刻 t=%.3fs（|v|=%.0f，SansSlamDamage=0，本段不扣 HP）",
            sc.slamImpact.t, sc.slamImpact.speed))
    end
    print("")
    print("说明：t=4.73~12.73 之间 maxFall=0，灵魂被钉在 x=40（重力向右但 vx 钳成 0）；")
    print("      t=12.73 起 maxFall=330，灵魂以 +330px/s 匀速右坠，直到右边框收拢到 410 撞停。")
end

-- 仅当"直接运行本文件"时才打印演示；被 require/dofile 引用时不执行
if arg and arg[0] and tostring(arg[0]):match("sans_final_fall_right%.lua$") then main() end

return SansFinalFallRight