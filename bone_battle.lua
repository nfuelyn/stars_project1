--=============================================================================
-- bone_battle.lua  --  Sans 战斗「骨头攻击」复刻模板（附带 round 号）
--=============================================================================
-- 来源：D:\c2-sans-fight-src  (Construct 2 工程 "Bad Time Simulator" / Sans Fight)
--
--   * Event sheets/Battle.xml
--       - 事件组 "Bones"        : BoneH / BoneV / BoneHRepeat / BoneVRepeat / SineBones
--                                + 每帧位移 & 出屏销毁
--       - 事件组 "BoneStab"     : BoneStabWarn -> BoneStabH/V 出刺、停留、回收
--       - 顶层 StartAttack/EndAttack + SansLegs.NextAttack 的**回合分配表**
--   * Event sheets/Timeline.xml : TLPlay 脚本机
--       - 每行格式: delay, command, param0..param8
--       - ":" 开头为标签; "$name" 为变量; 支持数学/JMP 系列指令
--   * Files/sans_*.csv          : 每个回合的攻击脚本（本模板直接读取并解释执行）
--   * Layouts/System.xml        : 骨骼默认尺寸
--       BoneH 48x10 (hotspot 左上)   BoneV 10x48
--       BoneStabH 48x12              BoneStabV 12x48
--       BoneStabWarn 16x16
--   * Battle.xml PlayerDamage   : 骨头 Damage=1, Karma=6; 命中冷却 0.033s
--
-------------------------------------------------------------------------------
-- 【骨骼方向约定】Direction = 0/1/2/3 -> 右/下/左/上
--     dx = cos(dir*90)   dy = sin(dir*90)        (Construct 2 的 sin/cos 取"度")
--   BoneH(水平骨): 宽由参数决定，高固定 10
--   BoneV(垂直骨): 高由参数决定，宽固定 10
--   BoneHRepeat / BoneVRepeat: 以 (startX,startY) 为起点，沿 Direction 反方向
--       每根平移 Spacing 像素，共 Count 根。公式:
--           X = StartX - cos(dir*90)*Spacing*i
--           Y = StartY - sin(dir*90)*Spacing*i
--   SineBones(count, spacing, speed, height):
--       spacing > 0 -> 从 CombatZone 右边界生成，dir=2(向左)
--       spacing < 0 -> 从 CombatZone 左边界生成，dir=0(向右)
--       sine = floor(sin(i/3 * 180/pi [度]) * 28)
--       上骨 y = Zone.Top+6,  高 = height+sine
--       下骨 y = Zone.Top+6+height+sine+39, 高 = Zone.Bottom-5-y
--   BoneStab(dir, distance, warnTime, stayTime):
--       先出警告矩形(Width/Height 按 dir 计算)，WarnTime 归零后生成 BoneStabH/V，
--       以 speed = distance*10 从边界刺入 distance 像素，停留 stayTime，再原路收回并销毁。
--=============================================================================

local BoneBattle = {}
BoneBattle.__index = BoneBattle
BoneBattle.VERSION = "1.0"

--=============================================================================
-- 常量（对应源码实例变量 / 布局默认尺寸）
--=============================================================================
BoneBattle.BONE_H_THICK = 10      -- BoneH.Height
BoneBattle.BONE_V_THICK = 10      -- BoneV.Width
BoneBattle.STAB_H_THICK = 12      -- BoneStabH.Height
BoneBattle.STAB_V_THICK = 12      -- BoneStabV.Width
BoneBattle.BONE_DAMAGE = 1        -- BoneH/BoneV.Damage
BoneBattle.BONE_KARMA = 6         -- BoneH/BoneV.Karma
BoneBattle.HIT_COOLDOWN = 0.033   -- PlayerDamage 的 LastDamageTime 间隔

BoneBattle.DIR_X = { [0] = 1, [1] = 0, [2] = -1, [3] = 0 }
BoneBattle.DIR_Y = { [0] = 0, [1] = 1, [2] = 0, [3] = -1 }

--=============================================================================
-- 回合表（round 号）
--   phase = "A"  对应源里 HitAttempts < 13 的段，NextAttack 0..14
--   phase = "B"  对应源里 13 < HitAttempts <= 22 的段，NextAttack 0..9
--   next  = 源码 SansLegs.NextAttack 的取值（每段从 0 开始）
--   bones = 该回合脚本是否会产生骨头（由脚本内容判定）
--=============================================================================
BoneBattle.ROUNDS = {
  -- ---- 第一阶段：HitAttempts < 13 ----
  { round =  1, phase = "A", next =  0, attack = "sans_intro",             bones = true,  note = "开场：BoneStab + SineBones" },
  { round =  2, phase = "A", next =  1, attack = "sans_bonegap1",          bones = true,  note = "左右 BoneVRepeat 骨墙" },
  { round =  3, phase = "A", next =  2, attack = "sans_bluebone",          bones = true,  note = "蓝心 + 两侧 BoneV" },
  { round =  4, phase = "A", next =  3, attack = "sans_bonegap2",          bones = true,  note = "随机 BoneV 骨墙" },
  { round =  5, phase = "A", next =  4, attack = "sans_platforms1",        bones = true,  note = "平台 + BoneV/BoneVRepeat" },
  { round =  6, phase = "A", next =  5, attack = "sans_platforms2",        bones = true,  note = "平台 + BoneV/BoneVRepeat" },
  { round =  7, phase = "A", next =  6, attack = "sans_platforms3",        bones = true,  note = "平台 + BoneV" },
  { round =  8, phase = "A", next =  7, attack = "sans_platforms4",        bones = true,  note = "移动平台 + BoneVRepeat" },
  { round =  9, phase = "A", next =  8, attack = "sans_platformblaster",   bones = false, note = "平台 + 加斯特冲击波（无骨）" },
  { round = 10, phase = "A", next =  9, attack = "sans_platforms4hard",    bones = true,  note = "困难移动平台 + BoneVRepeat" },
  { round = 11, phase = "A", next = 10, attack = "sans_bonegap1fast",      bones = true,  note = "快速骨墙" },
  { round = 12, phase = "A", next = 11, attack = "sans_boneslideh",        bones = true,  note = "水平滑动骨墙" },
  { round = 13, phase = "A", next = 12, attack = "sans_bonegap2",          bones = true,  note = "再次随机骨墙" },
  { round = 14, phase = "A", next = 13, attack = "sans_platformblasterfast", bones = false, note = "快速平台冲击波（无骨）" },
  { round = 15, phase = "A", next = 14, attack = "*choose(bonegap1fast,bonegap2,boneslideh,platformblasterfast)", bones = true, note = "随机循环" },
  -- ---- 特殊：HitAttempts == 13 ----
  { round = "SP", phase = "-", next = nil, attack = "sans_spare", bones = false, note = "HitAttempts==13，Sans 休息" },
  -- ---- 第二阶段：13 < HitAttempts <= 22 ----
  { round = 16, phase = "B", next = 0, attack = "sans_multi1",        bones = true,  note = "5 选 1 随机骨阵" },
  { round = 17, phase = "B", next = 1, attack = "sans_randomblaster1",bones = false, note = "纯随机冲击波" },
  { round = 18, phase = "B", next = 2, attack = "sans_multi2",        bones = true,  note = "4 选 1（含 SineBones/BoneV）" },
  { round = 19, phase = "B", next = 3, attack = "sans_bonestab1",     bones = true,  note = "BoneStab 连刺" },
  { round = 20, phase = "B", next = 4, attack = "sans_bonestab2",     bones = true,  note = "BoneStab 连刺（更快）" },
  { round = 21, phase = "B", next = 5, attack = "sans_randomblaster2",bones = false, note = "纯随机冲击波" },
  { round = 22, phase = "B", next = 6, attack = "sans_boneslidev",    bones = true,  note = "垂直滑动骨墙（BoneHRepeat）" },
  { round = 23, phase = "B", next = 7, attack = "sans_multi3",        bones = true,  note = "9 选 1 大杂烩（含骨）" },
  { round = 24, phase = "B", next = 8, attack = "sans_bonestab3",     bones = true,  note = "BoneStab 连刺（最长）" },
  { round = 25, phase = "B", next = 9, attack = "*choose(bonestab3,multi3,randomblaster2)", bones = true, note = "随机循环" },
  -- ---- 终局 ----
  { round = "FINAL", phase = "-", next = nil, attack = "sans_final", bones = true, note = "HitAttempts>22，最终连招" },
}

--=============================================================================
-- 小工具
--=============================================================================
local function num(v)
    if v == nil then return 0 end
    return tonumber(v) or 0
end

local function split(s, sep)
    local out = {}
    local pattern = "([^" .. sep .. "]*)" .. sep .. "?"
    for tok in string.gmatch(s .. sep, pattern) do
        out[#out + 1] = tok
    end
    if out[#out] == "" and #out > 1 then out[#out] = nil end
    return out
end

-- Construct 2 的三角函数以"度"为单位
local function sdeg(d) return math.sin(math.rad(d)) end
local function cdeg(d) return math.cos(math.rad(d)) end

local function aabb(ax, ay, aw, ah, bx, by, bw, bh)
    return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
end

local function approach(cur, target, step)
    if cur < target then
        return math.min(cur + step, target)
    elseif cur > target then
        return math.max(cur - step, target)
    end
    return cur
end

--=============================================================================
-- 时间轴脚本机（对应 Timeline.xml 的 TLPlay / TLLoadLine / 主循环）
--=============================================================================
local TL = {}
TL.__index = TL

function TL.new(host)
    return setmetatable({
        host = host, lines = {}, labels = {}, vars = { pi = math.pi },
        line = 1, t = 0, running = false, runCount = 0, cur = nil,
    }, TL)
end

-- 变量替换：$name -> vars[name]（缺失按 0）
function TL:subst(tok)
    if type(tok) == "string" and tok:sub(1, 1) == "$" then
        local v = self.vars[tok:sub(2)]
        if v == nil then return 0 end
        return v
    end
    return tok
end

function TL:load(text)
    self.lines, self.labels, self.runCount = {}, {}, 0
    self.vars = { pi = math.pi }
    local i = 0
    for raw in (text .. "\n"):gmatch("(.-)\r?\n") do
        local fields = split(raw, ",")
        i = i + 1
        self.lines[i] = fields
        local cmd = fields[2] or ""
        if cmd:sub(1, 1) == ":" then
            self.labels[cmd:sub(2)] = i          -- 标签行号（1 基）
        end
    end
end

-- 载入 line 指向的行，做变量替换（对应 TLLoadLine）
function TL:loadLine()
    local fields = self.lines[self.line]
    if not fields then self.cur = nil; return end
    local p = {}
    for k = 3, #fields do p[#p + 1] = self:subst(fields[k]) end
    self.cur = {
        delay = num(self:subst(fields[1])),
        cmd   = self:subst(fields[2]),
        p     = p,
    }
end

function TL:play(text, startLine)
    self:load(text)
    self.t = 0
    self.line = startLine or 1
    self:loadLine()
    self.running = true
end

function TL:stop()  self.running = false end
function TL:pause() self.running = false end
function TL:resume() self.running = true end

function TL:jumpAbs(target)
    local n = tonumber(target)
    if n then
        self.line = math.floor(n) - 1
    elseif self.labels[target] then
        self.line = self.labels[target] - 1
    else
        self.running = false
        self.host:panic("Label " .. tostring(target) .. " does not exist line " .. self.line)
    end
end

function TL:exec(cmd, p)
    local fn = BoneBattle.cmd[cmd]
    if fn then
        fn(self.host, p)
    else
        self.host:logEvent("unknown_cmd", cmd)
    end
end

-- 主循环：与源里 While 块一致（先把累计时间 T 内到期的行都执行掉，再加 dt）
function TL:update(dt)
    if self.running then
        local guard = 0
        while self.running and self.line >= 1 and self.cur do
            if self.t < self.cur.delay then break end
            local cmd = self.cur.cmd or ""
            if cmd ~= "" and cmd:sub(1, 1) ~= ":" then
                self:exec(cmd, self.cur.p)
            end
            self.t = self.t - self.cur.delay
            self.line = self.line + 1
            self:loadLine()
            self.runCount = self.runCount + 1
            if self.runCount >= 1000 then
                self.running = false
                self.host:panic("Infinite loop detected line " .. self.line)
            end
            guard = guard + 1
            if guard > 200000 then break end
        end
        if self.running then self.t = self.t + dt end
    end
end

--=============================================================================
-- 构造
--=============================================================================
function BoneBattle.new(opts)
    opts = opts or {}
    local self = setmetatable({}, BoneBattle)

    self.bones      = {}     -- 普通骨头 (H/V)
    self.warns      = {}     -- BoneStabWarn
    self.stabs      = {}     -- BoneStabH/V
    self.platforms  = {}     -- Platform1（可站立移动平台）
    self.blasters   = {}     -- 加斯特冲击波（仅记录）
    self.events     = {}     -- 事件日志

    -- CombatZone 初始尺寸取自 Layouts/BattleScreen.xml: x=32,y=240,w=576,h=144
    self.zone = {
        left = opts.left or 32, top = opts.top or 240,
        right = opts.right or 608, bottom = opts.bottom or 384,
        targets = nil,
    }
    self.resizeSpeed = 480
    self.layoutW = opts.layoutW or 640
    self.layoutH = opts.layoutH or 480

    -- 灵魂（只作为"受击盒"；位置可由 blue_soul.lua 每帧同步）
    self.heart = opts.heart or { x = 320, y = 376, w = 16, h = 16, mode = 1, maxFallSpeed = 750 }

    self.tl = TL.new(self)
    self.attackName = nil
    self.attackDone = false
    self.hitTimer = 0
    self.hitCooldown = opts.hitCooldown or BoneBattle.HIT_COOLDOWN
    self.dataDir = opts.dataDir
    self.csv = {}                     -- 缓存 name -> 文本
    self.rand = opts.rand or math.random

    self.onBoneSpawn = opts.onBoneSpawn   -- function(bb, bone)
    self.onDamage    = opts.onDamage      -- function(bb, bone)
    self.onEvent     = opts.onEvent       -- function(bb, kind, data)

    return self
end

function BoneBattle:logEvent(kind, data)
    self.events[#self.events + 1] = { kind = kind, data = data }
    if self.onEvent then self.onEvent(self, kind, data) end
end

function BoneBattle:panic(msg)
    self:logEvent("panic", msg)
end

--=============================================================================
-- 战场区域（对应 CombatZoneResize / CombatZoneResizeInstant / CombatZoneSpeed）
--=============================================================================
function BoneBattle:resize(l, t, r, b, endFunc)
    self.zone.targets = { left = l, top = t, right = r, bottom = b, endFunc = endFunc }
end

function BoneBattle:resizeInstant(l, t, r, b)
    self.zone.left, self.zone.top, self.zone.right, self.zone.bottom = l, t, r, b
    self.zone.targets = nil
end

function BoneBattle:updateZone(dt)
    local z = self.zone
    local tg = z.targets
    if not tg then return end
    local step = self.resizeSpeed * dt
    z.left   = approach(z.left,   tg.left,   step)
    z.top    = approach(z.top,    tg.top,    step)
    z.right  = approach(z.right,  tg.right,  step)
    z.bottom = approach(z.bottom, tg.bottom, step)
    if z.left == tg.left and z.top == tg.top and z.right == tg.right and z.bottom == tg.bottom then
        local fn = tg.endFunc
        z.targets = nil
        if fn and fn ~= "" then
            local f = BoneBattle.cmd[fn]
            if f then f(self, {}) end
        end
    end
end

function BoneBattle:zoneW() return self.zone.right - self.zone.left end
function BoneBattle:zoneH() return self.zone.bottom - self.zone.top end

--=============================================================================
-- 骨头生成
--=============================================================================
function BoneBattle:spawnBoneH(x, y, w, dir, speed, color)
    local b = {
        kind = "H", x = num(x), y = num(y), w = num(w), h = BoneBattle.BONE_H_THICK,
        dir = num(dir), speed = num(speed), color = num(color),
        damage = BoneBattle.BONE_DAMAGE, karma = BoneBattle.BONE_KARMA,
    }
    self.bones[#self.bones + 1] = b
    if self.onBoneSpawn then self.onBoneSpawn(self, b) end
    return b
end

function BoneBattle:spawnBoneV(x, y, h, dir, speed, color)
    local b = {
        kind = "V", x = num(x), y = num(y), w = BoneBattle.BONE_V_THICK, h = num(h),
        dir = num(dir), speed = num(speed), color = num(color),
        damage = BoneBattle.BONE_DAMAGE, karma = BoneBattle.BONE_KARMA,
    }
    self.bones[#self.bones + 1] = b
    if self.onBoneSpawn then self.onBoneSpawn(self, b) end
    return b
end

-- BoneHRepeat / BoneVRepeat：沿 Direction 反方向排 Count 根，间距 Spacing
function BoneBattle:boneRepeat(kind, sx, sy, size, dir, speed, count, spacing)
    sx, sy, size = num(sx), num(sy), num(size)
    dir, speed = num(dir), num(speed)
    count, spacing = math.floor(num(count)), num(spacing)
    local ux, uy = BoneBattle.DIR_X[dir] or 0, BoneBattle.DIR_Y[dir] or 0
    for i = 0, count - 1 do
        local x = sx - ux * spacing * i
        local y = sy - uy * spacing * i
        if kind == "H" then self:spawnBoneH(x, y, size, dir, speed, 0)
        else self:spawnBoneV(x, y, size, dir, speed, 0) end
    end
end

-- SineBones：正弦形上下骨墙
function BoneBattle:SineBones(count, spacing, speed, height)
    count, spacing, speed, height = math.floor(num(count)), num(spacing), num(speed), num(height)
    local z = self.zone
    for i = 0, count - 1 do
        local x, dir
        if spacing > 0 then
            x, dir = z.right + spacing * i, 2
        elseif spacing < 0 then
            x, dir = z.left + spacing * i, 0
        else
            x, dir = z.left, 0
        end
        -- 源: floor(sin(loopindex/3*180/pi)*28)，sin 取"度"
        local sine = math.floor(sdeg(i / 3 * 180 / math.pi) * 28)
        local y1 = z.top + 6
        self:spawnBoneV(x, y1, height + sine, dir, speed, 0)
        local y2 = z.top + 6 + height + sine + 39
        self:spawnBoneV(x, y2, z.bottom - 5 - y2, dir, speed, 0)
    end
end

-- BoneStab：先警告后出刺
function BoneBattle:boneStab(dir, distance, warnTime, stayTime)
    dir, distance = num(dir), num(distance)
    warnTime, stayTime = num(warnTime), num(stayTime)
    local z = self.zone
    local w, h, x, y
    if dir == 0 or dir == 2 then
        w, h = distance - 3, self:zoneH() - 16
        x = (dir == 0) and (z.right - w - 8) or (z.left + 8)
        y = z.top + 8
    else
        w, h = self:zoneW() - 16, distance - 3
        x = z.left + 8
        y = (dir == 1) and (z.bottom - h - 8) or (z.top + 8)
    end
    self.warns[#self.warns + 1] = {
        dir = dir, distance = distance, warnTime = warnTime, stayTime = stayTime,
        x = x, y = y, w = w, h = h,
    }
    self:logEvent("warn", { dir = dir, distance = distance })
end

-- 警告计时到 0 时生成实际刺
function BoneBattle:_spawnStab(warn)
    local z = self.zone
    local dir, distance = warn.dir, warn.distance
    local s
    if dir == 1 or dir == 3 then
        s = {
            kind = "SV", dir = dir, distance = distance, stayTime = warn.stayTime,
            x = z.left, w = self:zoneW(), h = distance + 8,
            reverse = false, speed = distance * 10,
            damage = 1, karma = BoneBattle.BONE_KARMA,
        }
        if dir == 1 then
            s.y = z.bottom - 5; s.destY = z.bottom - 5 - distance
        else
            s.y = z.top + 5 - s.h; s.destY = z.top + 5 - s.h + distance
        end
        s.destX = s.x
    else
        s = {
            kind = "SH", dir = dir, distance = distance, stayTime = warn.stayTime,
            y = z.top, h = self:zoneH(), w = distance + 8,
            reverse = false, speed = distance * 10,
            damage = 1, karma = BoneBattle.BONE_KARMA,
        }
        if dir == 0 then
            s.x = z.right - 5; s.destX = z.right - 5 - distance
        else
            s.x = z.left + 5 - s.w; s.destX = z.left + 5 - s.w + distance
        end
        s.destY = s.y
    end
    self.stabs[#self.stabs + 1] = s
    self:logEvent("stab", { dir = dir, distance = distance })
    return s
end

--=============================================================================
-- 每帧更新
--=============================================================================
function BoneBattle:updateBones(dt)
    local keep, W, H = {}, self.layoutW, self.layoutH
    for i = 1, #self.bones do
        local b = self.bones[i]
        b.x = b.x + (BoneBattle.DIR_X[b.dir] or 0) * dt * b.speed
        b.y = b.y + (BoneBattle.DIR_Y[b.dir] or 0) * dt * b.speed
        local dead = false
        if     b.dir == 0 and b.x > W then dead = true
        elseif b.dir == 1 and b.y > H then dead = true
        elseif b.dir == 2 and b.x < -b.w then dead = true
        elseif b.dir == 3 and b.y < -b.h then dead = true
        end
        if not dead then keep[#keep + 1] = b end
    end
    self.bones = keep
end

function BoneBattle:updateWarns(dt)
    local keep = {}
    for i = 1, #self.warns do
        local w = self.warns[i]
        w.warnTime = w.warnTime - dt
        if w.warnTime <= 0 then
            self:_spawnStab(w)
        else
            keep[#keep + 1] = w
        end
    end
    self.warns = keep
end

function BoneBattle:updateStabs(dt)
    local keep = {}
    for i = 1, #self.stabs do
        local s = self.stabs[i]
        local ux, uy = BoneBattle.DIR_X[s.dir] or 0, BoneBattle.DIR_Y[s.dir] or 0
        if s.reverse then
            s.x = s.x + ux * dt * s.speed
            s.y = s.y + uy * dt * s.speed
            if s.x < -s.w or s.x > self.layoutW + s.w or s.y < -s.h or s.y > self.layoutH + s.h then
                s = nil
            end
        else
            s.x = s.x - ux * dt * s.speed
            s.y = s.y - uy * dt * s.speed
            -- 到达 Dest（源：Is within angle + Compare X/Y）
            local reached
            if s.kind == "SH" then reached = (ux > 0 and s.x <= s.destX) or (ux < 0 and s.x >= s.destX)
            else reached = (uy > 0 and s.y <= s.destY) or (uy < 0 and s.y >= s.destY) end
            if reached then
                s.x, s.y = s.destX, s.destY
                s.stayTime = s.stayTime - dt
                if s.stayTime <= 0 then s.reverse = true end
            end
        end
        if s then keep[#keep + 1] = s end
    end
    self.stabs = keep
end

function BoneBattle:updatePlatforms(dt)
    for i = 1, #self.platforms do
        local p = self.platforms[i]
        p.x = p.x + (BoneBattle.DIR_X[p.dir] or 0) * dt * p.speed
        p.y = p.y + (BoneBattle.DIR_Y[p.dir] or 0) * dt * p.speed
    end
end

-- 把灵魂限制在 CombatZone 内（对应 CombatZone 事件组的夹取）
function BoneBattle:clampHeart()
    local h, z = self.heart, self.zone
    local hw, hh = h.w * 0.5, h.h * 0.5
    if h.x - hw < z.left + 5 then h.x = z.left + 5 + hw end
    if h.y - hh < z.top + 5 then h.y = z.top + 5 + hh end
    if h.x + hw > z.right - 5 then h.x = z.right - 5 - hw end
    if h.y + hh > z.bottom - 5 then h.y = z.bottom - 5 - hh end
end

-- 受击检测：返回本帧命中列表（源：PlayerHitbox 与 AttackSprite/Attack9Patch 重叠）
function BoneBattle:collectHits()
    if self.hitTimer > 0 then return {} end
    local hx = self.heart.x - self.heart.w * 0.5
    local hy = self.heart.y - self.heart.h * 0.5
    local out = {}
    for i = 1, #self.bones do
        local b = self.bones[i]
        if b.damage > 0 and aabb(hx, hy, self.heart.w, self.heart.h, b.x, b.y, b.w, b.h) then
            out[#out + 1] = b
        end
    end
    for i = 1, #self.stabs do
        local s = self.stabs[i]
        if s.damage > 0 and aabb(hx, hy, self.heart.w, self.heart.h, s.x, s.y, s.w, s.h) then
            out[#out + 1] = s
        end
    end
    if #out > 0 then
        self.hitTimer = self.hitCooldown
        for i = 1, #out do
            if self.onDamage then self.onDamage(self, out[i]) end
        end
    end
    return out
end

function BoneBattle:update(dt)
    if self.hitTimer > 0 then self.hitTimer = self.hitTimer - dt end
    self.tl:update(dt)
    self:updateZone(dt)
    self:updateWarns(dt)
    self:updateStabs(dt)
    self:updateBones(dt)
    self:updatePlatforms(dt)
    self:clampHeart()
    return self:collectHits()
end

--=============================================================================
-- 攻击脚本装载 / 回合控制
--=============================================================================
function BoneBattle:loadFromFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local text = f:read("*a"); f:close()
    return text
end

-- 取脚本文本：优先内存缓存，其次 dataDir 下的 <name>.csv
function BoneBattle:getScript(name)
    if self.csv[name] then return self.csv[name] end
    if self.dataDir then
        local text = self:loadFromFile(self.dataDir .. "/" .. name .. ".csv")
        if text then self.csv[name] = text; return text end
    end
    return nil
end

function BoneBattle:setScript(name, text) self.csv[name] = text end

function BoneBattle:clearAttack()
    self.bones, self.warns, self.stabs = {}, {}, {}
end

function BoneBattle:endAttack()
    self.tl:stop()
    self.attackDone = true
    self:clearAttack()
    self:logEvent("end_attack", self.attackName)
end

-- 运行一个具名攻击（对应 RunAttack + StartAttack）
function BoneBattle:runAttack(name)
    local text = self:getScript(name)
    if not text then
        self:logEvent("missing_script", name)
        return false
    end
    self:clearAttack()
    self.attackName = name
    self.attackDone = false
    self.tl:play(text)
    self:logEvent("start_attack", name)
    return true
end

-- 回合号 -> 攻击
function BoneBattle:roundInfo(roundNo)
    for i = 1, #BoneBattle.ROUNDS do
        if BoneBattle.ROUNDS[i].round == roundNo then return BoneBattle.ROUNDS[i] end
    end
    return nil
end

function BoneBattle:roundsUsingBones()
    local out = {}
    for i = 1, #BoneBattle.ROUNDS do
        if BoneBattle.ROUNDS[i].bones then out[#out + 1] = BoneBattle.ROUNDS[i] end
    end
    return out
end

-- 按 round 号开打
function BoneBattle:startRound(roundNo)
    local info = self:roundInfo(roundNo)
    if not info then self:logEvent("bad_round", roundNo); return false end
    if info.attack:sub(1, 1) == "*" then
        self:logEvent("random_round", info.attack)   -- 随机回合由调用方选择具体脚本
        return false
    end
    return self:runAttack(info.attack)
end

-- 按源码 NextAttack 规则推进（保留"随机循环"语义）
function BoneBattle:nextRound(currentRound)
    local info = self:roundInfo(currentRound)
    if not info then return nil end
    if type(info.round) ~= "number" then return nil end
    local nxt = info.round + 1
    local candidate = self:roundInfo(nxt)
    if candidate and candidate.phase == info.phase then return candidate end
    return nil
end

--=============================================================================
-- 时间轴指令表（BoneBattle.cmd[命令名](bb, params)）
--   params[1] 即源的 Function.Param(0)
--=============================================================================
BoneBattle.cmd = {}

-- ---- 骨头生成 ----
BoneBattle.cmd.BoneH = function(bb, p) bb:spawnBoneH(p[1], p[2], p[3], p[4], p[5], p[6]) end
BoneBattle.cmd.BoneV = function(bb, p) bb:spawnBoneV(p[1], p[2], p[3], p[4], p[5], p[6]) end
BoneBattle.cmd.BoneHRepeat = function(bb, p) bb:boneRepeat("H", p[1], p[2], p[3], p[4], p[5], p[6], p[7]) end
BoneBattle.cmd.BoneVRepeat = function(bb, p) bb:boneRepeat("V", p[1], p[2], p[3], p[4], p[5], p[6], p[7]) end
BoneBattle.cmd.SineBones = function(bb, p) bb:SineBones(p[1], p[2], p[3], p[4]) end
BoneBattle.cmd.BoneStab = function(bb, p) bb:boneStab(p[1], p[2], p[3], p[4]) end

-- ---- 时间轴控制 ----
BoneBattle.cmd.TLPause = function(bb) bb.tl:pause() end
BoneBattle.cmd.TLResume = function(bb) bb.tl:resume() end
BoneBattle.cmd.EndAttack = function(bb) bb:endAttack() end
BoneBattle.cmd.Debug = function() end

-- ---- 数学 / 变量 ----
BoneBattle.cmd.SET = function(bb, p) bb.tl.vars[p[1]] = p[2] end
BoneBattle.cmd.ADD = function(bb, p) bb.tl.vars[p[1]] = num(p[2]) + num(p[3]) end
BoneBattle.cmd.SUB = function(bb, p) bb.tl.vars[p[1]] = num(p[2]) - num(p[3]) end
BoneBattle.cmd.MUL = function(bb, p) bb.tl.vars[p[1]] = num(p[2]) * num(p[3]) end
BoneBattle.cmd.DIV = function(bb, p) bb.tl.vars[p[1]] = num(p[2]) / num(p[3]) end
BoneBattle.cmd.MOD = function(bb, p) bb.tl.vars[p[1]] = num(p[2]) % num(p[3]) end
BoneBattle.cmd.FLOOR = function(bb, p) bb.tl.vars[p[1]] = math.floor(num(p[2])) end
BoneBattle.cmd.DEG = function(bb, p) bb.tl.vars[p[1]] = num(p[2]) * 180 / math.pi end
BoneBattle.cmd.RAD = function(bb, p) bb.tl.vars[p[1]] = num(p[2]) * math.pi / 180 end
BoneBattle.cmd.SIN = function(bb, p) bb.tl.vars[p[1]] = sdeg(num(p[2])) end
BoneBattle.cmd.COS = function(bb, p) bb.tl.vars[p[1]] = cdeg(num(p[2])) end
BoneBattle.cmd.ANGLE = function(bb, p)
    bb.tl.vars[p[1]] = math.deg(math.atan2(num(p[4]) - num(p[2]), num(p[3]) - num(p[1])))
end
BoneBattle.cmd.RND = function(bb, p) bb.tl.vars[p[1]] = math.floor(bb.rand() * num(p[2])) end

-- ---- 跳转 ----
BoneBattle.cmd.JMPABS = function(bb, p) bb.tl:jumpAbs(p[1]) end
BoneBattle.cmd.JMPREL = function(bb, p) bb.tl.line = bb.tl.line + num(p[1]) - 1 end
BoneBattle.cmd.JMPZ  = function(bb, p) if num(p[2]) == 0 then bb.tl:jumpAbs(p[1]) end end
BoneBattle.cmd.JMPNZ = function(bb, p) if num(p[2]) ~= 0 then bb.tl:jumpAbs(p[1]) end end
BoneBattle.cmd.JMPE  = function(bb, p) if num(p[2]) == num(p[3]) then bb.tl:jumpAbs(p[1]) end end
BoneBattle.cmd.JMPNE = function(bb, p) if num(p[2]) ~= num(p[3]) then bb.tl:jumpAbs(p[1]) end end
BoneBattle.cmd.JMPL  = function(bb, p) if num(p[2]) <  num(p[3]) then bb.tl:jumpAbs(p[1]) end end
BoneBattle.cmd.JMPNL = function(bb, p) if num(p[2]) >= num(p[3]) then bb.tl:jumpAbs(p[1]) end end
BoneBattle.cmd.JMPG  = function(bb, p) if num(p[2]) >  num(p[3]) then bb.tl:jumpAbs(p[1]) end end
BoneBattle.cmd.JMPNG = function(bb, p) if num(p[2]) <= num(p[3]) then bb.tl:jumpAbs(p[1]) end end

-- ---- 灵魂 / 场景 ----
BoneBattle.cmd.HeartTeleport = function(bb, p) bb.heart.x, bb.heart.y = num(p[1]), num(p[2]) end
BoneBattle.cmd.HeartMode = function(bb, p) bb.heart.mode = num(p[1]) end
BoneBattle.cmd.HeartMaxFallSpeed = function(bb, p) bb.heart.maxFallSpeed = num(p[1]) end
BoneBattle.cmd.GetHeartPos = function(bb, p) bb.tl.vars[p[1]] = bb.heart.x; bb.tl.vars[p[2]] = bb.heart.y end
BoneBattle.cmd.CombatZoneResize = function(bb, p) bb:resize(num(p[1]), num(p[2]), num(p[3]), num(p[4]), p[5]) end
BoneBattle.cmd.CombatZoneResizeInstant = function(bb, p) bb:resizeInstant(num(p[1]), num(p[2]), num(p[3]), num(p[4])) end
BoneBattle.cmd.CombatZoneSpeed = function(bb, p) bb.resizeSpeed = num(p[1]) end

-- ---- 平台 ----
local function platform(bb, x, y, w, dir, speed, reverse)
    local p = { x = num(x), y = num(y), w = num(w), h = 10, dir = num(dir),
                speed = num(speed), reverse = reverse and true or false }
    bb.platforms[#bb.platforms + 1] = p
    return p
end
BoneBattle.cmd.Platform = function(bb, p) platform(bb, p[1], p[2], p[3], p[4], p[5], tonumber(p[6]) and tonumber(p[6]) > 0) end
BoneBattle.cmd.PlatformRepeat = function(bb, p)
    local sx, sy, size, dir, speed = num(p[1]), num(p[2]), num(p[3]), num(p[4]), num(p[5])
    local count, spacing = math.floor(num(p[6])), num(p[7])
    for i = 0, count - 1 do
        platform(bb, sx - (BoneBattle.DIR_X[dir] or 0) * spacing * i,
                    sy - (BoneBattle.DIR_Y[dir] or 0) * spacing * i, size, dir, speed)
    end
end

-- ---- 非骨头类（记录事件即可，保证脚本可完整执行） ----
local function rec(kind) return function(bb, p) bb:logEvent(kind, p) end end
BoneBattle.cmd.GasterBlaster = function(bb, p) bb.blasters[#bb.blasters + 1] = { p = p }; bb:logEvent("gaster_blaster", p) end
BoneBattle.cmd.SansSlam = function(bb, p) bb.slam = num(p[1]); bb:logEvent("sans_slam", p) end
BoneBattle.cmd.SansSlamDamage = function(bb, p) bb.slamDamage = num(p[1]); bb:logEvent("sans_slam_damage", p) end
BoneBattle.cmd.BlackScreen = rec("black_screen")
BoneBattle.cmd.Sound = rec("sound")
BoneBattle.cmd.Music = rec("music")
BoneBattle.cmd.SansBody = rec("sans_body")
BoneBattle.cmd.SansHead = rec("sans_head")
BoneBattle.cmd.SansAnimation = rec("sans_animation")
BoneBattle.cmd.SansText = rec("sans_text")
BoneBattle.cmd.SansSweat = rec("sans_sweat")
BoneBattle.cmd.SansRepeat = rec("sans_repeat")
BoneBattle.cmd.SansEndRepeat = rec("sans_end_repeat")
BoneBattle.cmd.SansX = rec("sans_x")

--=============================================================================
-- 回合表文本（便于打印/文档）
--=============================================================================
function BoneBattle.roundTableText()
    local out = {}
    out[#out + 1] = string.format("%-6s %-5s %-5s %-32s %-5s %s",
        "round", "phase", "next", "attack", "bones", "note")
    for i = 1, #BoneBattle.ROUNDS do
        local r = BoneBattle.ROUNDS[i]
        out[#out + 1] = string.format("%-6s %-5s %-5s %-32s %-5s %s",
            tostring(r.round), r.phase, tostring(r.next or "-"),
            r.attack, r.bones and "yes" or "no", r.note or "")
    end
    return table.concat(out, "\n")
end

return BoneBattle