--=============================================================================
-- bonestab_floor_rise.lua
-- 专注复刻：Sans 骨刺的「底边向上升起」（BoneStab，Direction = 1 / 南）
--=============================================================================
-- 来源：D:\c2-sans-fight-src
--   * Event sheets/Battle.xml  -> 事件组 "BoneStab"
--       - BoneStab(dir, distance, warnTime, stayTime)：
--           1) 先建 BoneStabWarn（预警矩形），按 dir 决定贴在框的哪条边、尺寸多少
--           2) WarnTime 归零 -> 生成 BoneStabV / BoneStabH，位置在框外，Dest 在框内
--           3) 以 speed = Distance*10 从起点滑到 Dest（正好 0.1s）
--           4) 在 Dest 停留 StayTime
--           5) Reverse = true，沿 Direction 原路退回，出屏销毁
--   * Files/sans_bonestab1.csv / sans_bonestab2.csv / sans_bonestab3.csv
--   * Files/sans_final.csv（阶段③ 的 BoneStab,1,48,0.6,1）与 sans_intro.csv
--   * Layouts/System.xml -> BoneStabV 默认 12×48、BoneStabH 默认 48×12
--                            BoneStabWarn 默认 16×16（都会在运行时按 dir/distance 改尺寸）
--
-------------------------------------------------------------------------------
-- 【Direction 语义】0=东(右边框) 1=南(底边框) 2=西(左边框) 3=北(上边框)
--   dir=1（南）就是本题的「底边骨刺向上升起」：
--       预警矩形: 宽 = 框宽-16, 高 = distance-3,
--                 贴在框底内侧 (x = 框左+8, y = 框底 - 高 - 8)
--       骨刺实体: BoneStabV, x = 框左, y = 框底-5, 宽 = 框宽, 高 = distance+8
--                 DestY = 框底-5 - distance
--       运动: 骨刺的**顶边**从 框底-5 升到 框底-5-distance
--                 => 从底边向上探出 distance 像素
--   对照 dir=3（北）是"顶边向下刺"，方向相反；dir=0/2 是左右横刺。
--
-- 【三档参数（原版）】
--   sans_bonestab1: Loop=9, BoneStab,$dir,25,0.4,0.33333
--   sans_bonestab2: Loop=9, BoneStab,$dir,25,0.3,0.2
--   sans_bonestab3: Loop=9, BoneStab,$dir,29,0.4,0
--   （工作区把 dist 改成 9、warn 1.2、stay 0.25/0.33333/0.2，并把 Loop 降到 6——属于有意差异）
--
-- 【回合号（消除歧义）】
--   原作 HitAttempts / 工作区内部号 : 17 = bonestab1, 18 = bonestab2, 22 = bonestab3
--   工作区 HUD 号 (= 内部+1)         : 18 = bonestab1, 19 = bonestab2, 23 = bonestab3
--   另外含 dir=1 底边骨刺的还有：sans_intro(HUD 1) 与 sans_final 阶段③(HUD 24)
--   ⚠ 内部号 14 = multi1、HUD 14 = sans_spare —— 两者都**不含** BoneStab。
--=============================================================================

local BoneStabFloorRise = {}
BoneStabFloorRise.__index = BoneStabFloorRise
BoneStabFloorRise.VERSION = "1.0"

-- 三档原版参数（Loop 次数 / distance / warnTime / stayTime）
BoneStabFloorRise.TIERS = {
    { key = 1, loop = 9, distance = 25, warnTime = 0.40, stayTime = 0.33333 },
    { key = 2, loop = 9, distance = 25, warnTime = 0.30, stayTime = 0.20 },
    { key = 3, loop = 9, distance = 29, warnTime = 0.40, stayTime = 0.0 },
}

BoneStabFloorRise.STAB_V_W = 12      -- BoneStabV 默认宽（Layouts/System.xml）
BoneStabFloorRise.STAB_H_H = 12      -- BoneStabH 默认高
BoneStabFloorRise.EXTEND_SPEED_K = 10 -- speed = distance * 10  -> 0.1s 伸出

local DIR_NAME = { [0] = "东(右)", [1] = "南(底/向上)", [2] = "西(左)", [3] = "北(顶/向下)" }

--=============================================================================
-- 构造
--=============================================================================
function BoneStabFloorRise.new(opts)
    opts = opts or {}
    local self = setmetatable({}, BoneStabFloorRise)
    self.zone = opts.zone or { l = 241, t = 226, r = 406, b = 391 }   -- 骨刺回合标准框
    self.layoutW = opts.layoutW or 640
    self.layoutH = opts.layoutH or 480
    self.warns = {}      -- 预警矩形
    self.stabs = {}      -- 实际骨刺（含 phase）
    self.events = {}
    return self
end

function BoneStabFloorRise:zoneW() return self.zone.r - self.zone.l end
function BoneStabFloorRise:zoneH() return self.zone.b - self.zone.t end

function BoneStabFloorRise:log(kind, d)
    self.events[#self.events + 1] = { kind = kind, t = self.t or 0, data = d }
end

--=============================================================================
-- BoneStab(dir, distance, warnTime, stayTime)
--   对应 Battle.xml -> Function On "BoneStab" 的前半段
--=============================================================================
function BoneStabFloorRise:spawn(dir, distance, warnTime, stayTime)
    dir = math.floor(tonumber(dir) or 0)
    distance = tonumber(distance) or 0
    warnTime = tonumber(warnTime) or 0
    stayTime = tonumber(stayTime) or 0
    local z = self.zone
    local w, h, x, y

    if dir == 0 or dir == 2 then
        w, h = distance - 3, self:zoneH() - 16
        x = (dir == 0) and (z.r - w - 8) or (z.l + 8)
        y = z.t + 8
    else
        w, h = self:zoneW() - 16, distance - 3
        x = z.l + 8
        y = (dir == 1) and (z.b - h - 8) or (z.t + 8)
    end

    self.warns[#self.warns + 1] = {
        dir = dir, distance = distance, warnTime = warnTime, stayTime = stayTime,
        x = x, y = y, w = w, h = h, phase = "warn", t = 0,
    }
    self:log("warn", { dir = dir, name = DIR_NAME[dir], distance = distance, warn = warnTime, stay = stayTime })
end

-- 预警到点 -> 生成骨刺实体（对应源里 UID 关联那一段）
function BoneStabFloorRise:_spawnStab(warn)
    local z = self.zone
    local dir, distance = warn.dir, warn.distance
    local s = { dir = dir, distance = distance, stayTime = warn.stayTime,
                speed = distance * BoneStabFloorRise.EXTEND_SPEED_K,
                reverse = false, phase = "out", stayLeft = warn.stayTime }

    if dir == 1 or dir == 3 then
        -- 竖直：BoneStabV，宽固定 12，高 distance+8
        s.kind = "V"
        s.w = self:zoneW()
        s.h = distance + 8
        s.x = z.l
        if dir == 1 then                       -- 南：从框底向上升起
            s.y = z.b - 5
            s.destY = z.b - 5 - distance
        else                                   -- 北：从框顶向下刺
            s.y = z.t + 5 - s.h
            s.destY = z.t + 5 - s.h + distance
        end
        s.destX = s.x
    else
        -- 水平：BoneStabH，高固定 12，宽 distance+8
        s.kind = "H"
        s.h = self:zoneH()
        s.w = distance + 8
        s.y = z.t
        if dir == 0 then                       -- 东：从右边框向左刺
            s.x = z.r - 5
            s.destX = z.r - 5 - distance
        else                                   -- 西：从左边框向右刺
            s.x = z.l + 5 - s.w
            s.destX = z.l + 5 - s.w + distance
        end
        s.destY = s.y
    end

    self.stabs[#self.stabs + 1] = s
    self:log("stab", { dir = dir, name = DIR_NAME[dir], kind = s.kind,
                       from = { x = s.x, y = s.y }, dest = { x = s.destX, y = s.destY } })
    return s
end

--=============================================================================
-- 每帧推进（对应源里 BoneStabWarn 倒计时 + 两个 BoneStab 移动分支）
--=============================================================================
function BoneStabFloorRise:update(dt)
    self.t = (self.t or 0) + dt

    -- 1) 预警倒计时
    local keepWarn = {}
    for i = 1, #self.warns do
        local w = self.warns[i]
        w.t = w.t + dt
        if w.t >= w.warnTime then
            self:_spawnStab(w)
        else
            keepWarn[#keepWarn + 1] = w
        end
    end
    self.warns = keepWarn

    -- 2) 骨刺本体：out -> stay -> in -> 出屏销毁
    local keepStab = {}
    for i = 1, #self.stabs do
        local s = self.stabs[i]
        local ux = (s.dir == 0 and 1) or (s.dir == 2 and -1) or 0
        local uy = (s.dir == 1 and 1) or (s.dir == 3 and -1) or 0

        if s.phase == "out" then
            -- 朝 Dest 移动 = 沿 -Direction 方向
            s.x = s.x - ux * dt * s.speed
            s.y = s.y - uy * dt * s.speed
            local reached
            if s.kind == "V" then reached = (uy > 0 and s.y <= s.destY) or (uy < 0 and s.y >= s.destY)
            else reached = (ux > 0 and s.x <= s.destX) or (ux < 0 and s.x >= s.destX) end
            if reached then
                s.x, s.y = s.destX, s.destY
                s.phase = "stay"
                s.stayLeft = s.stayTime
                self:log("reached", { dir = s.dir })
            end
        elseif s.phase == "stay" then
            s.stayLeft = s.stayLeft - dt
            if s.stayLeft <= 0 then s.phase = "in"; self:log("retract", { dir = s.dir }) end
        else -- "in"
            s.x = s.x + ux * dt * s.speed
            s.y = s.y + uy * dt * s.speed
            local gone
            if ux > 0 then gone = s.x > self.layoutW + s.w
            elseif ux < 0 then gone = s.x + s.w < -s.w
            elseif uy > 0 then gone = s.y > self.layoutH + s.h
            else gone = s.y + s.h < -s.h end
            if gone then s = nil end
        end
        if s then keepStab[#keepStab + 1] = s end
    end
    self.stabs = keepStab
end

-- 命中矩形就是骨刺实体自身 AABB（源里 PlayerHitbox 与 Attack9Patch 重叠）
function BoneStabFloorRise:hitRects()
    local out = {}
    for i = 1, #self.stabs do
        local s = self.stabs[i]
        out[#out + 1] = { x = s.x, y = s.y, w = s.w, h = s.h, dir = s.dir, phase = s.phase }
    end
    return out
end

-- 便捷：只跑 dir=1（底边向上升起）的一根，返回它
function BoneStabFloorRise:spawnFloorRise(distance, warnTime, stayTime)
    self:spawn(1, distance, warnTime, stayTime)
    return self
end

-- 便捷：完整复刻某一档的 Loop（原作 dir 随机 0..3）
function BoneStabFloorRise:runTier(tierKey, rnd)
    local tier
    for i = 1, #BoneStabFloorRise.TIERS do
        if BoneStabFloorRise.TIERS[i].key == tierKey then tier = BoneStabFloorRise.TIERS[i] end
    end
    if not tier then return end
    rnd = rnd or math.random
    local dirs = {}
    for _ = 1, tier.loop do
        local d = math.floor(rnd() * 4)
        dirs[#dirs + 1] = d
        self:spawn(d, tier.distance, tier.warnTime, tier.stayTime)
    end
    return dirs
end

--=============================================================================
-- 直接运行时的演示
--=============================================================================
local function main()
    print("================================================================")
    print(" BoneStab（骨刺）· 底边向上升起  dir=1 / 南")
    print("================================================================")

    print("\n--- 三档原版参数 ---")
    print(string.format("%-14s %-6s %-10s %-10s %-10s", "script", "Loop", "distance", "warnTime", "stayTime"))
    print(string.format("%-14s %-6d %-10d %-10.2f %-10.5f", "bonestab1", 9, 25, 0.40, 0.33333))
    print(string.format("%-14s %-6d %-10d %-10.2f %-10.2f", "bonestab2", 9, 25, 0.30, 0.20))
    print(string.format("%-14s %-6d %-10d %-10.2f %-10.2f", "bonestab3", 9, 29, 0.40, 0.0))

    print("\n--- dir=1 底边骨刺：几何（框 241,226,406,391 / distance=29）---")
    local sc = BoneStabFloorRise.new()
    sc:spawnFloorRise(29, 0.4, 0.25)
    print(string.format("框底 y = %d；骨刺起点 y = %d（框底-5），目标 DestY = %d（上升 %d px）",
        sc.zone.b, sc.zone.b - 5, sc.zone.b - 5 - 29, 29))

    print("\n--- dir=1 逐帧（t / phase / 骨刺顶边 y / 伸出量）---")
    local dt = 1 / 60
    local base = sc.zone.b - 5
    local shown = {}
    for i = 1, math.floor(1.2 / dt) do
        sc:update(dt)
        local st = sc.stabs[1]
        local y = st and st.y or nil
        local lead = y and (base - y) or 29
        local tag = string.format("t=%.2f  %s", sc.t, st and st.phase or "gone")
        if not shown[tag] then
            shown[tag] = true
            print(string.format("  %s  顶边 y=%s  伸出=%s", tag,
                y and string.format("%6.1f", y) or "   -  ",
                y and string.format("%5.1f px", lead) or "  -"))
        end
    end

    print("\n--- bonestab3 完整 Loop（9 次随机方向）---")
    local sc2 = BoneStabFloorRise.new()
    local seed = 20261006
    local rnd = function() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
    local dirs = sc2:runTier(3, rnd)
    local names, floorCnt = {}, 0
    for i, d in ipairs(dirs) do
        names[#names + 1] = string.format("#%d dir=%d(%s)", i, d, DIR_NAME[d])
        if d == 1 then floorCnt = floorCnt + 1 end
    end
    print("  " .. table.concat(names, "  "))
    print(string.format("  其中 dir=1（底边向上升起）：%d / %d 次", floorCnt, #dirs))
    print("")
    print("说明：Dir=1 时骨刺贴在框底内侧、BoneStabV 从框底外沿向上探出 distance px；")
    print("      伸出速度 = distance*10（0.1s 到位），停留 stayTime 后原路退回并出屏销毁。")
end

if arg and arg[0] and tostring(arg[0]):match("bonestab_floor_rise%.lua$") then main() end

return BoneStabFloorRise