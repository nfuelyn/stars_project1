local function sineBars(s, gm, offY)
  offY = offY or 0
  local zoneT = (gm.zoneT or 0) + offY
  local zoneB = (gm.zoneB or VH) + offY
  local topEdge = gm.top + offY             -- 走廊上口（上骨底）
  local botEdge = gm.bottom + offY          -- 走廊下口（下骨顶）
  local bars = {}
  local h1 = topEdge - (zoneT + 6)
  if h1 > 0 then bars[#bars + 1] = { x = gm.x, y = zoneT + 6, w = gm.w, h = h1, vertical = true } end
  local h2 = (zoneB - 5) - botEdge
  if h2 > 0 then bars[#bars + 1] = { x = gm.x, y = botEdge, w = gm.w, h = h2, vertical = true } end
  return bars
end
--[[ ==========================================================================
  Sans 弹幕审判 · 纯 Lua 逻辑核心（零外部依赖）
  ---------------------------------------------------------------------------
  这是 prototype/attack-engine.js + prototype/game.js 的 1:1 语义移植。

  约束（刻意遵守）：
    * 不 require / 不 io / 不 os / 不 package / 不 debug / 不调用任何 game.* API
    * 只做逻辑：没有 print（自测除外），没有绘图细节
    * 文件末尾 return M；所有内部函数与命令表都是 local
    * 脚本数据由外部注入（opts.scripts = attacks.lua 的表），core 不自带数据

  目标语义 = Lua 5.3（fengari）；同时兼容 Lua 5.1（本机 D:\5.1\lua.exe），
  差异只出现在位运算与 math.atan 上，已在文件顶部集中处理（BIT / ATAN）。

  坐标：本模块内部一律用原版 640x480、Y 向下（与 CSV 数值逐字一致）。
  M.render() 直接输出 640x480 世界坐标；攻击脚本自己的战斗框在脚本坐标里
  通常是 (240,226)-(400,391)，本模块在载入脚本时把它平移到 (0,0)-(160,165)，
  这样脚本坐标与游戏坐标共用同一个「框内偏移」参照，渲染时再加回来。

  HP 上限：20。与 prototype/game.js 的 MAX_HP 一致——这是自测断言（HP=20 /
  hp=2 的 KR 用例）的基准。资料里的 92 是后续正式版的值，可用 opts.hp 覆盖。

  运行自测见 lua/core_selftest.lua。
  ========================================================================== ]]

local M = {}

M.VERSION = "1.0.0"

-- ---------------------------------------------------------------- 常量
local VW, VH = 640, 480           -- 原版虚拟画布
local BONE_W = 10                 -- 骨头**厚度**：原版 BoneV.png=10x24 / BoneH.png=24x10 ——
                                  -- 脚本只 Set height/width，所以竖骨恒 10 宽、横骨恒 10 高。
                                  -- 【2026-10-05 第十二轮】旧值 19 是自绘外观的拍脑袋值：
                                  -- 判定比原版粗了近一倍（擦着边就掉血），这里照原版改回 10。
local BONE_HIT_W = 16
                                  -- 旧值 8（16×16）在 bonegap 那种 14px 骨缝里钻不过去 → 「无法躲避」。
local BLASTER_BEAM_LEN = 2000
local BLASTER_W = { 20, 36, 56 }        -- Size 0/1/2 的光束宽度（命中判定与渲染共用）
local BLASTER_SCALE = { 0.8, 1.0, 1.3 } -- Size 0/1/2 的**骷髅**缩放：原版 Size 档确实改炮身大小，
                                       -- 旧实现只让光束变宽、骷髅永远一样大 → 这就是「大小需修正」
-- 龙骨炮的**停靠点**（开火位置）安全区。选项栏（按钮行）顶边 y=432，HUD 行在 y≈403，
local BLASTER_SAFE = { xmin = 34, xmax = 606, ymin = 30, ymax = 372 }
local GRAVITY = 600               -- 蓝魂重力（px/s^2）
-- 蓝心跳跃参数 = 原版 BTS `Event sheets/Battle.xml` → 「PlayerMovement」组（逐条转写，不自己调）：
--   HEART_JUMP_STRENGTH  = 180  起跳初速（px/s）
--   HEART_JUMPHOLD_CUTOFF = 30  按住时把上升速度托回 -30 → 按住期间以 30px/s 匀速上升（= 变高跳，线性）
--   MaxFallSpeed          = 750
--   Gravity 按 dy（= PlayerHeart.CustomMovement.dy）分**四档**。XML 里是 4 个并列事件，用 DownSpeed = -dy 判定：
--       DownSpeed < 240 && DownSpeed > 15   → 540   即 dy < -15        （**上升中**：快速减速）
--       DownSpeed ≤ 15 && DownSpeed > -30   → 180   即 -15 ≤ dy < 30   （顶点附近）
--       DownSpeed ≤ -30 && DownSpeed > -120 → 450   即 30 ≤ dy < 120   （下落）
--       DownSpeed ≤ -120                    → 180   即 dy ≥ 120        （快落）
-- BTS 与我们的世界同为 640×480、单位同为 px/s → **1:1 直接用**，不需要换算。
--
-- ⚠ 2026-10-05 修（真 bug）：旧实现写成 `vy < -30 → 180` / `vy > 240 → 540`，**把 180/540 用反了**。
--   后果：轻按一下弹到 87px（0.62 框高，原版只有 ~30px = 1/5 框高），而按住只多 3px/s 级的手感差，
--   玩家报的「跳太高」「长按不改变高度」都是这一处。按上面四档改回后：轻按 ≈30px、按住 +30px/s 线性增长。
local JUMP_STRENGTH = 180       -- 保留：红魂/砸击相关逻辑仍读它
local MAX_FALL_SPEED = 750
-- 【蓝心跳跃规则（用户口径 2026-10-05 第五轮）】
--   按住跳跃键 → **匀速上升**：速度 = 0.6 × 框高 / 0.25s ⇒ 0.25s 升到 **3/5 框高**；
--   松开跳跃键 → **立刻停止上升**，转为**等速下降**：速度 = 0.5 × 框高 / 0.75s。
--   **按住超过 0.25s 不再上升**：到点就停、转为自然下落（不会再「按住一直浮空」）。
local JUMP_RISE_T = 0.25         -- 上升窗口（秒）：按住只有这么久，之后自然下落
local JUMP_HEIGHT = 0.6          -- 跳跃高度 = 3/5 框高（用户第十一轮口径）
local JUMP_FALL_T = 0.75         -- 从 1/2 框高落回地面所需时间（秒）
local SINE_HIT_W = 19             -- 正弦骨的命中盒边长（原版无此数据，见 records/lua-port.md）
local SINE_BAR_H = 8              -- 正弦长骨的视觉/命中厚度
local PLATFORM_TRAVEL = 100       -- Platform 往返（BooleanReverse=1）的边界半径 px

-- 骨头四段生命
local PEEK, EXTEND, HOLD, RETRACT, TIP_H = 0.5, 0.15, 0.55, 0.20, 16
local LETHAL_H = 24               -- 与视觉一致：高过 24 才算"看得见骨头"

-- 玩家
local SOUL_R = 2                  -- 【差距文档 H-01】原版心贴图 16×16，但真正的判定物是
                                  -- `PlayerHitbox` = **4×4** 精灵（每帧跟随心），判定只用它。
                                  -- 我们原来 SOUL_R=4（8×8）比原版大一倍 → 擦边就掉血。现在照原版改成 4×4。
local SOUL_CLAMP = 8              -- 框内钳位半径 = 心形视觉半宽（±8）：保证心本身不画出框外
local SOUL_SPEED = 150              -- 【差距文档 V-03 / 附录B】原版红模式移速 = 150 px/s
local SOUL_SPEED_SLOW = 75          -- 按住取消键（取消/后退）时减速到 75 px/s
local KR_PER_HIT = 6              -- 原版 Karma：骨头 6 / 龙骨炮 10（见 Battle.xml 的 Karma 实例变量）
local KR_TICK = 0.5
local KR_MAX = 40                  -- 【差距文档 V-02/附录B】原版 KR 上限 40
local MAX_HP = 92                 -- 【第三轮 N5 · 原作体验】HP 上限 92（传奇面包 +45 不变）                 -- 见文件头说明
local DT = 1 / 60

-- 设计板（1280x720）里的 UI 几何；渲染时 x0.5 落回 640x480 世界坐标
-- 内置回合的战斗框中心：**绝对坐标 (320, 308.5)**。
-- 308.5 = BTS 默认战斗框 (240,226)-(400,391) 的中心 y = 226 + 165/2。
-- 曾经写 183（那是 HTML 原型 1280x720 设计板 640x366 折半来的），
-- 会让所有内置回合的框（以及被钳在框上的灵魂）整体**偏高 125.5px**。
local BOX_CX, BOX_CY = 320, 308.5
-- 菜单按钮行：**在框外下方**（原版 FIGHT/ACT/ITEM/MERCY 排在框下沿之外，y≈400..440；
-- 默认框 (240,226)-(400,391) 的下沿就是 391）。这里给的是**逻辑提示值**：
-- 适配层会按 `min(box.y + box.h + 12, 480 - 46)` 统一挪位（移动端还要与摇杆区让位）。
-- 别把它当成"画在框内"—— 曾经这么写过，是错的。
local MENU = { bw = 110, bh = 42, gap = 10, y = 400 }   -- 真值来自 Animations/UIFight|Act|Item|Mercy = 110×42
local MENU_LABELS = { "攻击", "行动", "道具", "仁慈" }
local BOX_OFF_X, BOX_OFF_Y = 240, 226  -- 攻击脚本坐标 -> 游戏坐标的平移量
local SCRIPT_BOX_W, SCRIPT_BOX_H = 160, 165

-- 骨刺墙内部阶段 -> GDD C14 契约阶段名（render 输出用契约名）
local STAB_PHASE = { warn = 'peek', out = 'extend', stay = 'hold', ['in'] = 'retract' }

local ROUND_DEF = {
  { n = 1, bw = 420, bh = 260, dur = 9,  pattern = 'bone_floor', p = { interval = 1.35 } },
  { n = 2, bw = 420, bh = 260, dur = 10, pattern = 'bone_wall',  p = { speed = 110, gap = 4, interval = 2.20 } },
  { n = 3, bw = 420, bh = 260, dur = 10, pattern = 'blue_bone',  p = { blue = 1.80, white = 2.60 } },
  { n = 4, bw = 420, bh = 260, dur = 10, pattern = 'blaster',    p = { interval = 2.20, warn = 0.90 } },
  { n = 5, bw = 360, bh = 240, dur = 11, pattern = 'mixed',      p = { interval = 1.15, wallSpeed = 130, wallInterval = 2.40 } },
  { n = 6, bw = 600, bh = 340, dur = 12, pattern = 'blue_soul',  p = { gravity = 820, jump = -560, boneInterval = 1.60 } },
}

local SURPRISE = { n = 0, bw = 420, bh = 260, dur = 2.8, pattern = 'surprise', p = { interval = 1.4 } }

-- ==========================================================================
-- 20 回合结构（用户验收要求：原作不止六回合，见面杀之后全是随机抽模板）
--   内部回合号 0..19；HUD 显示号 = 内部号 + 1（所以"ROUND 1 / 20"就是见面杀）
--     0        见面杀（sans_intro，固定，不参与抽签）
--     1..16    多套模板**随机抽取**：不连续重复、优先没抽过的、难度随回合递增
--     17/18/19 螺旋龙骨炮三档（spiral1/2/3，spiral3 = 原作 final 阶段④逐字参数 + 阶段⑤力竭）
--   原作是"12 次攻击后中场"，所以中场落在内部号 11（显示 ROUND 12 / 20）。
-- ==========================================================================
local TOTAL_ROUNDS = 24
local LAST_ROUND = TOTAL_ROUNDS - 1     -- 内部号 23 = 最后一回合（原作 ≥23 是 sans_final → 胜利）
local SPIRAL_FROM = 17                  -- 内部号 >= 17 走螺旋档
local INTERLUDE_ROUND = 13              -- 【差距文档 §1/B-01】原作 HitAttempts==13（= sans_spare 休息回合）
-- Sans 的站位（世界坐标 640×480，Y 向下）：头顶 326、脚底 474，零件尺寸照原版
-- （头 32×30 / 躯干 54×25 / 身体 64×70 / 腿 44×23，合计 148 高）。
-- 框下沿默认 391 —— 他的头因此**探进框里 65px**，这正是原版的构图（框底 391、屏幕底 480，
-- 只有 89px 装不下 148 高的他）。
local SANS_H = 148                    -- sans 参考身高（世界 px）：头 30 + 躯干 25 + 身体 70 + 腿 23
local SANS_HEAD_TOP = 326             -- 兜底头顶点（有战斗框时按 `框顶 - SANS_H` 算，见 render）

-- 螺旋档：战斗框按脚本自己的 CombatZoneResize 走（脚本 zone 会覆盖这里给的 bw/bh），
-- 这里的 bw/bh/dur 只是"脚本没给 zone"时的兜底；pattern 决定灵魂初始形态与内置生成器，
-- 而脚本接管的回合里内置生成器一律让位（见 update 的 scriptOwnsRound）。
local SPIRAL_DEFS = {
  { n = 17, bw = 305, bh = 165, dur = 9,  pattern = 'bone_floor', p = { interval = 1.35 } },  -- spiral1 轻（脚本 zone 476-171=305）
  { n = 18, bw = 237, bh = 165, dur = 11, pattern = 'bone_floor', p = { interval = 1.35 } },  -- spiral2 中（脚本 zone 442-205=237）
  { n = 19, bw = 165, bh = 165, dur = 24, pattern = 'bone_floor', p = { interval = 1.35 } },  -- spiral3 = 原作阶段④+⑤（zone 406-241=165）
}
-- 普通随机回合的兜底定义（真实框/时长由脚本的 zone 与脚本时长决定）
local SCRIPT_ROUND = { bw = 420, bh = 260, dur = 8, pattern = 'bone_floor', p = { interval = 1.35 } }

-- ---------------------------------------------------------------- 多套模板
-- 分档抽签：回合越后参与抽签的模板套越多（前 4 回合只抽骨头，最后 4 回合四套全上）
local TEMPLATE_TIERS = {
  { 'bones' },
  { 'bones', 'stabs' },
  { 'stabs', 'platform' },
  { 'bones', 'stabs', 'platform', 'blaster' },
}
-- 每套模板都是 attacks.lua 里逐行转写自原作的一个攻击脚本（multi* 本身就是原作的随机组）
local TEMPLATE_SETS = {
  bones    = { 'sans_bonegap1', 'sans_bonegap1fast', 'sans_boneslideh', 'sans_boneslidev', 'sans_bluebone', 'multi1' },
  stabs    = { 'sans_bonestab1', 'sans_bonestab2', 'sans_bonegap2', 'multi2' },
  platform = { 'platforms1', 'platforms2', 'platforms3', 'platformblaster', 'platforms4' },
  blaster  = { 'randomblaster1', 'randomblaster2', 'platformblasterfast', 'platforms4hard', 'sans_bonestab3', 'multi3' },
}
local SPIRAL_SCRIPTS = { 'spiral1', 'spiral2', 'spiral3' }

local DIFFS = {
  easy     = { key = 'easy',     label = '简单', speed = 0.60, interval = 1.60, warn = 1.45, invuln = 1.00, note = '慢速 · 间隔大 · 预警长' },
  normal   = { key = 'normal',   label = '普通', speed = 0.78, interval = 1.35, warn = 1.20, invuln = 0.80, note = '推荐' },
  hard     = { key = 'hard',     label = '困难', speed = 1.00, interval = 1.00, warn = 1.00, invuln = 0.55, note = '基准速度' },
  original = { key = 'original', label = '原作', speed = 1.00, interval = 1.00, warn = 1.00, invuln = 0.033, note = '原版无敌帧 1 帧（差距文档 H-04/V-06）' },
}
local DIFF_ORDER = { 'easy', 'normal', 'hard', 'original' }

local ACT_OPTIONS = {
  { id = 'inspect', name = '检查', hint = '看他的数据（结束回合）',   effect = 'end',
    result = '审判者　ATK 1　DEF 1 —— 他只有 1 点 HP，但他从不站着让你打。' },
  { id = 'taunt',   name = '挑衅', hint = '下一回合他更快（结束回合）', effect = 'taunt',
    result = '（他眯起眼睛）好啊。那我再快一点。' },
  { id = 'beg',     name = '求饶', hint = '立刻清空 KR（结束回合）',    effect = 'beg',
    result = '（他叹了口气）……你身上的紫气淡了一点。' },
  { id = 'wait',    name = '沉默', hint = '什么都不做（不结束回合）',    effect = 'wait',
    result = '（你什么也没做。他也什么都没做。）' },
}
local SUB_TITLE = { act = '行动', item = '道具', mercy = '仁慈' }

local LINES = {
  surprise = '（他没有打招呼，先动手了。）',
  r1 = '站住别动，让我看看你躲得怎么样。',
  r2 = '骨头是会走路的东西，别被它撞上。',
  r3 = '蓝色的骨头：别动。你动一下，它就咬你。',
  r4 = '抬头看看，朋友。',
  r5 = '你还没死？那我再认真一点。',
  -- 20 回合版把台词按"阶段"分了组（原来只有 r1..r6，回合 >6 时全都落到 r6，
  -- 于是 ROUND 20 / 20 的屏幕上还写着"你已经撑过六回合了" —— 试玩截图里抓到的）。
  r6 = '……你已经撑过六回合了。',
  mid = '撑过一半了？那我换个打法。',            -- 内部号 6..10
  late = '你还在动。越来越有意思了。',              -- 内部号 12..16（中场之后）
  spiral1 = '站好，抬头看。',                      -- 内部号 17
  spiral2 = '别眨眼。',                            -- 内部号 18
  spiral3 = '——好吧。轮到你了。',                  -- 内部号 19（最后一回合）
  dodge = '（他侧身闪开了）',
  refuse = '（他摇了摇头）',
  flee = '（他摇了摇头）你逃不掉的。',
  final = '好吧。轮到你了。',
  midpoint = '……中场。他停手了。',
}

-- 本回合该说哪句：把台词按阶段分组（0 = 见面杀；1..5 = r1..r5；6..10 = mid；
-- 11 = 中场那句由 endEnemy 说；12..16 = late；17/18/19 = 三档螺旋各自的台词）。
local function lineForRound(n)
  if n <= 0 then return LINES.surprise end
  if n <= 5 then return LINES['r' .. n] or LINES.r5 end
  if n <= 10 then return LINES.mid end
  if n < SPIRAL_FROM then return LINES.late end
  return LINES['spiral' .. (n - SPIRAL_FROM + 1)] or LINES.spiral3
end

-- ==========================================================================
-- 位运算兼容层：**整层都用纯 double 算术实现**，Lua 5.1 / 5.3（fengari）逐位一致。
-- 为什么不用原生位运算：
--   * Lua 5.3 的 `&` 得到**有符号**整数，`x & 0xFFFFFFFF` 仍是负数状态，
--     转成 double 后除 2^n 会得到负数，与 Lua 5.1 的取模实现结果不同（两运行时行为分叉）；
--   * Lua 5.3 的 `>>` 是**算术**右移（负数补 1），而 JS 的 `>>>` 补 0。
-- 统一走 `% 2^32` 取模算术后，中间值都是 double，逐位对齐 JS（mulberry32 逐值一致）。
-- ==========================================================================
local function u32(a)
  a = a % 4294967296
  if a < 0 then a = a + 4294967296 end
  return a
end
local function s32(a)
  a = u32(a)
  if a >= 2147483648 then a = a - 4294967296 end
  return a
end
local function bitop(a, b, keep)
  a, b = u32(a), u32(b)
  local r, bit = 0, 1
  for _ = 1, 32 do
    local x, y = a % 2, b % 2
    if keep(x, y) then r = r + bit end
    a, b, bit = (a - x) / 2, (b - y) / 2, bit * 2
  end
  return s32(r)
end
local BAND = function(a, b) return bitop(a, b, function(x, y) return x == 1 and y == 1 end) end
local BOR  = function(a, b) return bitop(a, b, function(x, y) return x == 1 or y == 1 end) end
local BXOR = function(a, b) return bitop(a, b, function(x, y) return x ~= y end) end
local BNOT = function(a) return s32(-1 - a) end
-- 逻辑右移 = JS 的 `>>>`
local function lrshift(v, n)
  local u = u32(v)
  return math.floor(u / 2 ^ n)
end
local RSHIFT = lrshift
-- int32 截断乘法 = JS 的 Math.imul。
-- **不能直接写 (a*b) % 2^32**：a、b 最大约 2^31，乘积接近 2^62，
-- 超过 double 的 53 位精度，取模后会引入 ±64 级别的误差（实测 seed 20261004
-- 的第一个随机值因此全错）。这里按 16 位拆开做，所有中间值都 < 2^48。
local MASK16 = 65535
local function imul(a, b)
  a, b = u32(a), u32(b)
  local al, ah = a % 65536, math.floor(a / 65536)
  local bl, bh = b % 65536, math.floor(b / 65536)
  local x = al * bh + ah * bl
  local r = al * bl + (x % 65536) * 65536        -- 高 16 位贡献已在 % 2^32 下被丢弃
  r = r % 4294967296
  if r >= 2147483648 then r = r - 4294967296 end
  return r
end
local IMUL = imul
local WRAP = s32
-- JS 的 `^` 结果自动按 int32 截断（`(x ^ y) | 0`）；Lua 的位运算是 64 位，
-- 所以每次 XOR 之后都要显式折回 int32，否则随后的 `>>> 14` 会算错。
local TOINT = s32
if not math.atan then
  math.atan = function(y, x) return math.atan2(y, x) end
end
local ATAN2 = math.atan           -- Lua 5.3 的 math.atan(y, x) 等价于 atan2
local FLOOR = math.floor

-- =============================================================================
-- mulberry32：与 prototype/attack-engine.js **逐值一致**（C10 确定性地基）
--   JS 语义： a |= 0; a = a + 0x6D2B79F5 | 0;
--             t = imul(a ^ (a>>>15), 1|a);
--             t = ((t + imul((t ^ (t>>>7))|0, 61|t)) ^ t) | 0;
--             return (t ^ (t>>>14)) >>> 0 / 2^32
--   要点：① `>>>` 是零填充右移（见 lrshift）；② 每个 `^` 之后都要折回 int32（TOINT），
--         否则最终 `t ^ (t>>>14)` 会是正数、整条序列全错（实测第一个值差 4 个数量级）。
--   参考值（由 attack-engine.js 打印）：见 core_selftest.lua 的 extra-rng 用例。
-- =============================================================================
local function mulberry32(a)
  local st = a or 0
  return function()
    st = WRAP(st + 0x6D2B79F5)
    -- 逐字对照 JS（三个易错点都踩过）：
    --   ① `>>>` 是零填充右移（见 RSHIFT），不是算术右移；
    --   ② `61 | t` 是"或"，不是常量 61；
    --   ③ `t + imul(...) ^ t` 里的 `^ t` 作用在**整个和**上，不是只作用在 imul 的结果上；
    --   ④ 每个 `^` 之后都要折回 int32（TOINT），否则最终 `^ (t>>>14)` 会算错。
    --   var t = Math.imul(a ^ a >>> 15, 1 | a);
    local t = IMUL(TOINT(BXOR(st, RSHIFT(st, 15))), BOR(1, st))
    --   t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
    local m2 = IMUL(TOINT(BXOR(t, RSHIFT(t, 7))), BOR(61, t))
    t = TOINT(BXOR(t + m2, t))
    --   return ((t ^ t >>> 14) >>> 0) / 4294967296;
    -- 【曾经的 bug，2026-10 修】这里原来写的是 `RSHIFT(..., 14)` —— 把 JS 的 `>>> 0`
    -- （只为取无符号 32 位，等价于不移位）写成了**再右移 14 位**，于是所有随机值都被
    -- 额外除以 2^14，输出恒在 1e-5 量级：
    --   * `rng() < 0.5` 恒为真（蓝/橙骨永远同色、生成方向永远同一侧）
    --   * `math.floor(rng() * n)` 恒为 0（骨墙缺口永远在最左、抽模板永远只抽到第 1 个）
    -- 因为 prototype/attack-engine.js 里是对的（`>>> 0`），移植时抄错了这一处；
    -- core_selftest 的"参考值"当年是从**这个错误实现**打印的，所以测试一直是绿的。
    return RSHIFT(TOINT(BXOR(t, RSHIFT(t, 14))), 0) / 4294967296
  end
end

-- ==========================================================================
-- 小工具
-- ==========================================================================
local function clamp(v, a, b) if v < a then return a elseif v > b then return b else return v end end

local function trim(s)
  s = tostring(s or "")
  local a = s:find("[^ \t\r\n\f\v]")
  if not a then return "" end
  local b = s:reverse():find("[^ \t\r\n\f\v]")
  return s:sub(a, #s - b + 1)
end

-- JS 的 Number(v)：数字串 -> 数值，非数字串 -> 原字符串，Infinity -> 原字符串
local function tonum_or_str(s)
  local n = tonumber(s)
  if n == nil then return s end
  if n ~= n or n == math.huge or n == -math.huge then return s end
  return n
end

local function rectHit(cx, cy, r, rc)
  local nx, ny = clamp(cx, rc.x, rc.x + rc.w), clamp(cy, rc.y, rc.y + rc.h)
  local dx, dy = cx - nx, cy - ny
  return dx * dx + dy * dy <= r * r
end

-- ---------------------------------------------------------------- UTF-8 工具
-- 台词与菜单全是中文：**绝对不能用按字节的 string.sub/# 去截断**，
-- 否则会切出非法 UTF-8 字节串，写进控件 text 属性时 JS 侧直接抛
-- "cannot convert invalid utf8 to javascript string"，整帧 draw 中断（真机全黑）。
-- 优先用标准 utf8 库（Lua 5.3 / fengari 自带），缺失时按首字节长度自己数。
local has_utf8 = (type(utf8) == "table") and (type(utf8.len) == "function")
local function utf8len(s)
  s = tostring(s or "")
  if has_utf8 then
    local n = utf8.len(s)
    if n ~= nil then return n end
    return #s                                  -- 非法字节串的兜底
  end
  local n, i, L = 0, 1, #s
  while i <= L do
    local b = s:byte(i)
    local step = 1
    if b >= 0xF0 then step = 4
    elseif b >= 0xE0 then step = 3
    elseif b >= 0xC0 then step = 2 end
    i = i + step
    n = n + 1
  end
  return n
end
-- 取前 k 个**字符**（k >= 字符数时返回整串；k <= 0 返回空串）
local function utf8sub(s, k)
  s = tostring(s or "")
  if k == nil or k <= 0 then return "" end
  if has_utf8 then
    if k >= utf8len(s) then return s end
    local i = utf8.offset(s, k + 1)
    if not i then return s end
    return s:sub(1, i - 1)
  end
  local n, i, L = 0, 1, #s
  while i <= L do
    if n >= k then return s:sub(1, i - 1) end
    local b = s:byte(i)
    local step = 1
    if b >= 0xF0 then step = 4
    elseif b >= 0xE0 then step = 3
    elseif b >= 0xC0 then step = 2 end
    i = i + step
    n = n + 1
  end
  return s
end

local function say(w, s) w.log[#w.log + 1] = s end

-- ==========================================================================
-- CSV 解析（对应 attack-loader.js 的 parseCSV）
-- ==========================================================================
local function split(text, sep)
  local out, from = {}, 1
  while true do
    local i = text:find(sep, from, true)
    if not i then
      out[#out + 1] = text:sub(from)
      break
    end
    out[#out + 1] = text:sub(from, i - 1)
    from = i + 1
  end
  return out
end

local function parseCSV(text)
  local rows = {}
  for _, ln in ipairs(split(tostring(text or ""):gsub("\r", ""), "\n")) do
    if trim(ln) ~= "" and ln:sub(1, 1) ~= "#" then
      local cells = split(ln, ",")
      while #cells > 0 and cells[#cells] == "" do cells[#cells] = nil end
      for i = 1, #cells do cells[i] = trim(cells[i]) end
      rows[#rows + 1] = cells
    end
  end
  return rows
end

-- ==========================================================================
-- 攻击脚本编译（对应 attack-engine.js 的 compile）
--   * 标签行**占一行**（空操作）：JMPABS/JMPZ 用的是 1-based 物理行号
--   * JMPREL 的第 1 个参数是**相对偏移**，其余 JMP* 是目标（行号或标签）
--   * 目标 / 相对量在编译期解析并存成 line.target / line.rel，
--     exec 里一律读 line.cmd / line.rel（不要用局部字符串变量代替，会错位）
-- ==========================================================================
local function compile(rows)
  local prog, labels = {}, {}
  for i = 1, #rows do
    local r = rows[i]
    local raw = r[1]
    local delay
    if type(raw) == "string" and raw:sub(1, 1) == "$" then
      delay = raw
    else
      delay = tonumber(raw) or 0
    end
    local name = r[2]
    -- 参数**逐个按位**保留（含空串占位）：JS 用 r.slice(2).filter(a => a !== undefined && a !== '')，
    -- 但 CSV 里出现空单元格时会整体左移参数位（如 `0,BlackScreen,1` 之前若多一个逗号，
    -- BlackScreen 就会吃到后面的值）。这里按位保留，空串由 val() 转成 0，
    -- 位置语义与“第 N 个参数”一致，不会再错位。
    local args = {}
    for k = 3, #r do
      args[#args + 1] = r[k]
    end
    while #args > 0 and args[#args] == "" do args[#args] = nil end
    -- 标签行：`:,Name` 或单独一行 `:Name`（第二列缺失时也要认得）
    local label = nil
    if type(raw) == "string" and raw:sub(1, 1) == ":" then
      label = raw:sub(2)
      delay = 0
    elseif type(name) == "string" and name:sub(1, 1) == ":" then
      label = name:sub(2)
    end
    if label ~= nil then
      labels[label] = #prog
      prog[#prog + 1] = { delay = delay, cmd = nil, args = {}, label = label }
    else
      prog[#prog + 1] = { delay = delay, cmd = name, args = args }
    end
  end
  for j = 1, #prog do
    local c = prog[j]
    if type(c.cmd) == "string" and c.cmd:sub(1, 3) == "JMP" and #c.args > 0 then
      local t = c.args[1]
      if c.cmd == "JMPREL" then
        c.rel = t
      elseif type(t) == "string" and labels[t] ~= nil then
        c.target = labels[t]        -- 注意：标签可能在 pc=0（第一个位置），所以只能比 nil
      elseif type(t) == "string" and t:sub(1, 1) == "$" then
        c.target = t
      else
        c.target = (tonumber(t) or 0) - 1
      end
    end
  end
  return { prog = prog, labels = labels }
end

-- ==========================================================================
-- 战斗世界（对应 attack-engine.js 的 World）
-- ==========================================================================
local World = {}
World.__index = World

local function newWorld(opts)
  opts = opts or {}
  local w = setmetatable({}, World)
  w.seed = opts.seed
  w.tune = opts.tune
  if w.seed == nil then w.seed = 20261004 end
  w.script = opts.script and compile(opts.script) or nil      -- 已编译则直接用
  if opts.compiled then w.script = opts.compiled end
  w:reset()
  return w
end

function World:reset()
  self.rng = mulberry32(self.seed)
  -- G3：难度倍率（构造时可传 tune；不传 = 全 1 = 原版原值）
  self.vars = {}
  self.zone = { l = 240, t = 226, r = 400, b = 391,
                tl = 240, tt = 226, tr = 400, tb = 391, speed = 0, resizing = false, finish = nil }
  self.heart = { x = 320, y = 304, mode = 0, vx = 0, vy = 0, maxFall = 0, dir = 0, wall = nil }
  self.bones, self.blasters, self.platforms, self.sine = {}, {}, {}, {}
  self.flash, self.black = 0, 0
  self.sans = { head = 'Default', body = nil, torso = 'Default', anim = 'Idle', sweat = 0, x = 320, repeating = false, text = '' }
  self.log = {}
  self.time = 0
  self.ended = false
  self.paused = false
  self.prog = self.script and self.script.prog or {}
  self.pc = 0
  self.wait = 0
  self.hitCount = 0
  -- 延时语义 = 「执行该行前要等的时间」：首行的延时也要等
  if #self.prog > 0 then
    local d0 = self.prog[1].delay
    self.wait = (type(d0) == "string") and (self.vars[d0:sub(2)] or 0) or self:itv(d0)
  end
end

function World:val(v)
  if type(v) == "string" and v:sub(1, 1) == "$" then
    local n = self.vars[v:sub(2)]
    if n == nil then return 0 end
    return n
  end
  if type(v) == "number" then return v end
  if v == nil then return 0 end
  if v == "" then return 0 end
  return tonum_or_str(v)
end

-- ---------------------------------------------------------------- 命令表
local CMD = {}

-- 战斗框
CMD.CombatZoneResize = function(w, l, t, r, b, finish)
  w.zone.tl, w.zone.tt, w.zone.tr, w.zone.tb = tonumber(l), tonumber(t), tonumber(r), tonumber(b)
  w.zone.resizing = true
  w.zone.finish = (finish ~= nil and finish ~= "") and finish or nil
  if not w.zone.speed or w.zone.speed == 0 then w.zone.speed = 300 end
end
CMD.CombatZoneResizeInstant = function(w, l, t, r, b)
  w.zone.l, w.zone.t, w.zone.r, w.zone.b = tonumber(l), tonumber(t), tonumber(r), tonumber(b)
  w.zone.tl, w.zone.tt, w.zone.tr, w.zone.tb = tonumber(l), tonumber(t), tonumber(r), tonumber(b)
  w.zone.resizing = false
end
CMD.CombatZoneSpeed = function(w, s) w.zone.speed = tonumber(s) end
CMD.CombatZonePos = function(w, l, t)          -- 扩展（原版无此命令）
  local dl, dt = tonumber(l) - w.zone.l, tonumber(t) - w.zone.t
  for _, k in ipairs({ 'l', 'r', 'tl', 'tr' }) do w.zone[k] = w.zone[k] + dl end
  for _, k in ipairs({ 't', 'b', 'tt', 'tb' }) do w.zone[k] = w.zone[k] + dt end
end

-- 灵魂
CMD.HeartTeleport = function(w, x, y)
  w.heart.x, w.heart.y, w.heart.vx, w.heart.vy = tonumber(x), tonumber(y), 0, 0
  w.heartPosDirty = true          -- 只有 HeartTeleport 会挪灵魂（HeartMode 不该顺带搬位置）
end
CMD.HeartMode = function(w, m) w.heart.mode = tonumber(m); w.heartModeDirty = true end
CMD.HeartMaxFallSpeed = function(w, v) w.heart.maxFall = tonumber(v); w.heartModeDirty = true end
CMD.SansSlam = function(w, d)   -- 【方案甲 A-2】原版语义：强制蓝魂 + 设方向 + 满速甩出
  d = tonumber(d) or 0
  if d < 0 or d > 3 then return end
  local s = w.heart.maxFall
  if not s or s == 0 then s = 750 end
  w.heart.mode = 1
  w.heart.slammed = true
  w.heart.dir = d
  w.heart.vx = (d == 0) and s or ((d == 2) and -s or 0)
  w.heart.vy = (d == 1) and s or ((d == 3) and -s or 0)
  w.heartModeDirty = true
  w.heartVelDirty = true
  say(w, 'slam ' .. tostring(d))
end
CMD.SansSlamDamage = function(w, b)
  w.slamDamage = (tonumber(b) ~= 0)
  w.slamDamageDirty = true     -- 【A-3】透传给 Game
end
CMD.GetHeartPos = function(w, xv, yv)
  w.vars[xv], w.vars[yv] = w.heart.x, w.heart.y
end

-- 骨头
local function pushBone(w, x, y, hOrW, axis, dir, speed, color)
  local c = tonumber(color)
  if c == nil then c = 0 end
  w.bones[#w.bones + 1] = {
    x = tonumber(x), y = tonumber(y), axis = axis,   -- axis: 'v' 竖骨 / 'h' 横骨（渲染朝向必须跟它走）
    w = (axis == 'v') and BONE_W or tonumber(hOrW),
    h = (axis == 'v') and tonumber(hOrW) or BONE_W,
    vx = (dir == 0) and w:spd(speed) or ((dir == 2) and -w:spd(speed) or 0),
    vy = (dir == 1) and w:spd(speed) or ((dir == 3) and -w:spd(speed) or 0),
    -- 【2026-10-05 修】脚本骨（BoneV/BoneH/Repeat）一直没写 lethal 字段，而碰撞循环是
    -- `if bn.lethal then ... end` → 这些骨头**全部穿人**（bonegap / boneslide / platforms /
    -- multi / final 这些脚本关全中招）——玩家看到的就是「蓝心没有碰撞箱」。脚本骨本来就该伤人。
    lethal = true,
    color = c,
  }
end
CMD.BoneV = function(w, x, y, h, dir, speed, color)
  pushBone(w, x, y, h, 'v', tonumber(dir), tonumber(speed), color)
end
CMD.BoneH = function(w, x, y, wd, dir, speed, color)
  pushBone(w, x, y, wd, 'h', tonumber(dir), tonumber(speed), color)
end

local function repeatBones(w, axis, x, y, size, dir, speed, count, spacing, color)
  local d, sp, n, s = tonumber(dir), tonumber(spacing), tonumber(count), tonumber(size)
  for i = 0, n - 1 do
    -- 【真 bug（本轮修）】骨群要排在**来向**（领头骨后面），才会一根接一根到达；
    -- 旧实现四种方向全反了（东行往东排、西行往西排…）→ 起手整排骨同时压在框里，
    -- 玩家看到的是「两侧骨头一上来就铺满屏」而不是交错飞入（用户实测反馈）。
    -- 规则：往运动方向**相反**的一侧排开 —— 东行往西、西行往东、南行往北、北行往南。
    local off = ((d == 0 or d == 1) and -1 or 1) * i * sp
    if axis == 'v' then pushBone(w, tonumber(x) + off, y, s, 'v', d, speed, color)
    else pushBone(w, tonumber(x), tonumber(y) + off, s, 'h', d, speed, color) end
  end
end
CMD.BoneVRepeat = function(w, x, y, h, dir, speed, count, spacing, color)
  -- 第 8 个参数 Color 是本项目的**向后兼容扩展**：官方 BoneVRepeat 没有 Color（只能是白骨），
  -- 但「左右高低骨」这种组合要求批量生成的骨头也能是蓝骨（Color=1）。不传 = 0 = 白。
  repeatBones(w, 'v', x, y, h, dir, speed, count, spacing, color)
end
CMD.BoneHRepeat = function(w, x, y, wd, dir, speed, count, spacing, color)
  repeatBones(w, 'h', x, y, wd, dir, speed, count, spacing, color)
end

CMD.SineBones = function(w, count, spacing, speed, height)
  -- **照抄原版**（c2-sans-fight `Event sheets/Battle.xml` → Function "SineBones"）：
  --   for i in 0..Count-1:
  --     Sine = floor(sin(i/3 弧度) * 28)          ← 幅度固定 28px、相位 i/3、向下取整
  --     Spacing > 0 → X = 框右 + Spacing*i，方向 2（向西）
  --     Spacing < 0 → X = 框左 + Spacing*i，方向 0（向东）
  --     上长骨：Y = 框顶 + 6，高 = Height + Sine
  --     下长骨：Y = 框顶 + 6 + Height + Sine + 39（**走廊固定 39px**），一直铺到框底 - 5
  -- 注意：这是**静态波形整体平移**（每根骨头的 Sine 只跟序号有关），不是逐帧摇相位的动画。
  local n, sp, spd, hgt = tonumber(count), tonumber(spacing), w:spd(speed), tonumber(height)
  local z = w.zone
  for i = 0, n - 1 do
    local sine = math.floor(math.sin(i / 3) * 28)
    local x
    if sp > 0 then x = z.r + sp * i else x = z.l + sp * i end
    w.sine[#w.sine + 1] = { x = x, t = 0, speed = spd, gap = 39,
                            sine = sine, height = hgt, amp = 28, phase = 0,
                            zoneT = z.t, zoneB = z.b, bar = SINE_BAR_H,
                            dir = (sp > 0) and -1 or 1 }
  end
end

CMD.BoneStab = function(w, dir, dist, warn, stay)
  -- 从战斗框侧面弹出的骨刺墙：先预警 warn 秒，再伸出 dist，停留 stay 秒后收回
  w.bones[#w.bones + 1] = { stab = true, dir = tonumber(dir), dist = tonumber(dist),
                            warn = w:wn(warn), stay = tonumber(stay), t = 0, phase = 'warn' }
end

CMD.HeartWall = function(w, on)
  -- 【箭头模块统一模板】把蓝心切到「贴墙模式」：自由移动（不吃普通蓝心重力/悬停规则），
  -- 跳跃键 = 朝「箭头方向的反方向」冲刺（见 Game:jump）。方向取自 SansBody（箭头）。
  w.heart.wall = (tonumber(on) ~= 0) and true or nil
  w.heartModeDirty = true
end

CMD.ArrowBone = function(w, dir, warn, stay)
  -- 「箭头模块」的骨头：从箭头那条边**升起**，高度/长度上限 = 1/2 框高（**不超过蓝心最大跳跃高度**）。
  -- 相位与 BoneStab 共用（warn → out → stay → in），只是命中矩形不同（见 World:stabRect）。
  local z = w.zone
  local h = z.b - z.t
  local d = tonumber(dir)
  local maxRise
  -- 伸出长度 ≤ 跳跃最高高度（= 3/5 框高），同时按用户口径取 1/4 框宽——两者取小。
  local depthW = 0.25 * (z.r - z.l)
  local depthH = JUMP_HEIGHT * h
  maxRise = math.min(depthW, depthH)
  w.bones[#w.bones + 1] = { arrowbone = true, dir = d, dist = maxRise,
                            warn = tonumber(warn), stay = tonumber(stay), t = 0, phase = 'warn', cur = 0 }
end

CMD.GasterBlaster = function(w, size, sx, sy, ex, ey, endAng, spin, blast, hold, extraW)
  local a0 = ATAN2(tonumber(ey) - tonumber(sy), tonumber(ex) - tonumber(sx)) * 180 / math.pi
  local bt = tonumber(blast)
  local persistent = (bt ~= nil and bt <= 0)       -- BlastTime=0 → 持续光束（sans_final 阶段④）
  local sz = clamp(math.floor(tonumber(size) or 0), 0, 2)
  -- 停靠点钳进安全区：不落在选项栏那一条（也不会出屏）。起点 sx,sy 不钳 —— 原版就是从屏幕角飞入的。
  local ex2 = clamp(tonumber(ex) or 0, BLASTER_SAFE.xmin, BLASTER_SAFE.xmax)
  local ey2 = clamp(tonumber(ey) or 0, BLASTER_SAFE.ymin, BLASTER_SAFE.ymax)
  local g = {
    size = sz, x = tonumber(sx), y = tonumber(sy),
    sx = tonumber(sx), sy = tonumber(sy), ex = ex2, ey = ey2,
    ang = a0, ang0 = a0, endAng = tonumber(endAng), spin = tonumber(spin),
    blast = bt, persistent = persistent, hold = tonumber(hold) or 0, t = 0,
    -- 【方案A】初见杀用原版像素龙骨炮（block2 烘焙）；其余关卡保持 12 件参数化
    bake = (w.scriptName == 'sans_intro'),
    -- 光束宽度：Size 0/1/2 = 20/36/56；骷髅缩放：0.8/1.0/1.3
    -- extraW：双向各加宽这么多（用户口径「光束双向扩大 5px」→ 传 5，宽度 +10）
    band = (BLASTER_W[sz + 1] or BLASTER_W[1]) + (tonumber(extraW) or 0) * 2,
    scale = BLASTER_SCALE[sz + 1] or BLASTER_SCALE[1],
    state = (tonumber(spin) > 0) and 'spin' or 'charge',
  }
  w.blasters[#w.blasters + 1] = g
  if persistent then
    -- 持续光束：登记进"下一次 EndAttack 时统一收束"的名单
    w.persistent = w.persistent or {}
    w.persistent[#w.persistent + 1] = g
  end
end

CMD.Platform = function(w, x, y, wd, dir, speed, reverse, ramp)
  -- 第 8 个参数 Ramp = 「从 0 加速到全速用几秒」（本项目扩展；原版 sans_platforms4 的已知问题就是
  -- 作者偷懒让平台一上来就是全速 —— 见仓库 readme.md「Known Issues」第 2 条）。不传 = 0 = 立刻全速。
  w.platforms[#w.platforms + 1] = { x = tonumber(x), y = tonumber(y), w = tonumber(wd), h = 7,   -- 素材真值：Textures/Platform1.png = 16×7
                                    dir = tonumber(dir), speed = w:spd(speed),
                                    reverse = (tonumber(reverse) or 0) ~= 0,
                                    ramp = tonumber(ramp) or 0, t = 0,
                                    -- 往返边界（CSV 没给范围）：以生成点为原点 ±PLATFORM_TRAVEL
                                    x0 = tonumber(x), y0 = tonumber(y), travel = PLATFORM_TRAVEL }
end
CMD.PlatformRepeat = function(w, x, y, wd, dir, speed, count, spacing)
  for i = 0, tonumber(count) - 1 do
    -- 同 repeatBones：排在来向（东行往西排、西行往东排），平台才会依次进场。
    local d = tonumber(dir)
    local off = ((d == 0 or d == 1) and -1 or 1) * i * tonumber(spacing)
    CMD.Platform(w, tonumber(x) + off, y, wd, dir, speed, 0)
  end
end

-- 流程 / 表现
CMD.BlackScreen = function(w, b)
  w.black = tonumber(b)
  if tonumber(b) ~= 0 then
    -- 【2026-10-05 修】原来只清 bones/sine/blasters —— multi2/3 的 Attack5 会 `Platform` 出落脚板，
    -- 下一段 BlackScreen 清不掉它 → 后面几段攻击里平台一直挂在场上（用户说的「攻击模板叠加」）。
    w.bones, w.sine, w.blasters, w.platforms = {}, {}, {}, {}
    w.persistent = nil
  end
end
CMD.Sound = function(w, n) say(w, 'sound ' .. tostring(n)) end
CMD.Music = function(w, n) say(w, 'music ' .. tostring(n)) end
CMD.TLPause = function(w) w.paused = true end
CMD.TLResume = function(w) w.paused = false end
CMD.EndAttack = function(w)
  w.ended = true
  -- 持续光束（BlastTime=0）不会自己消失：攻击结束时统一收束（state -> done，0.15s 淡出）
  if w.persistent then
    for _, g in ipairs(w.persistent) do
      if g.state == 'fire' or g.state == 'spinning' then
        g.state = 'done'; g.t = 0
      end
    end
  end
end

CMD.SansAnimation = function(w, n) w.sans.anim = (n ~= nil and n ~= "") and n or 'Idle' end
CMD.SansHead = function(w, n) w.sans.head = (n ~= nil and n ~= "") and n or 'Default' end
CMD.SansBody = function(w, n) w.sans.body = (n ~= nil and n ~= "") and n or nil end
CMD.SansTorso = function(w, n) w.sans.torso = (n ~= nil and n ~= "") and n or 'Default' end
CMD.SansSweat = function(w, n) w.sans.sweat = tonumber(n) end
CMD.SansX = function(w, x) w.sans.x = tonumber(x) end
CMD.SansRepeat = function(w) w.sans.repeating = true end
CMD.SansEndRepeat = function(w) w.sans.repeating = false end
CMD.SansText = function(w, t) w.sans.text = tostring(t); say(w, 'text ' .. tostring(t)) end

-- 运算（13 个）
CMD.SET   = function(w, v, a) w.vars[v] = w:val(a) end
CMD.ADD   = function(w, v, a, b) w.vars[v] = w:val(a) + w:val(b) end
CMD.SUB   = function(w, v, a, b) w.vars[v] = w:val(a) - w:val(b) end
CMD.MUL   = function(w, v, a, b) w.vars[v] = w:val(a) * w:val(b) end
CMD.DIV   = function(w, v, a, b) w.vars[v] = w:val(a) / w:val(b) end
CMD.MOD   = function(w, v, a, b) w.vars[v] = w:val(a) % w:val(b) end
CMD.FLOOR = function(w, v, a) w.vars[v] = FLOOR(w:val(a)) end
CMD.DEG   = function(w, v, a) w.vars[v] = w:val(a) * 180 / math.pi end
CMD.RAD   = function(w, v, a) w.vars[v] = w:val(a) * math.pi / 180 end
CMD.SIN   = function(w, v, a) w.vars[v] = math.sin(w:val(a) * math.pi / 180) end
CMD.COS   = function(w, v, a) w.vars[v] = math.cos(w:val(a) * math.pi / 180) end
CMD.ANGLE = function(w, v, x1, y1, x2, y2)
  w.vars[v] = ATAN2(w:val(y2) - w:val(y1), w:val(x2) - w:val(x1)) * 180 / math.pi
end
CMD.RND   = function(w, v, n) w.vars[v] = FLOOR(w.rng() * w:val(n)) end

-- 跳转（10 个）：第 1 个参数是**目标**，测试参数从第 2 个开始
local JUMPS = {
  JMPABS = function() return true end,
  JMPREL = function() return true end,
  JMPZ   = function(w, t, a) return w:val(a) == 0 end,
  JMPNZ  = function(w, t, a) return w:val(a) ~= 0 end,
  JMPE   = function(w, t, a, b) return w:val(a) == w:val(b) end,
  JMPNE  = function(w, t, a, b) return w:val(a) ~= w:val(b) end,
  JMPL   = function(w, t, a, b) return w:val(a) < w:val(b) end,
  JMPNL  = function(w, t, a, b) return w:val(a) >= w:val(b) end,
  JMPG   = function(w, t, a, b) return w:val(a) > w:val(b) end,
  JMPNG  = function(w, t, a, b) return w:val(a) <= w:val(b) end,
}

local function nextDelay(w, line)
  if line == nil then return 0 end
  local d = line.delay
  if type(d) == "string" then return w.vars[d:sub(2)] or 0 end
  return d
end

function World:exec(line)
  local c = line.cmd
  if c == nil then return nil end                 -- 标签行：空操作
  if JUMPS[c] then
    local rest = {}
    for i = 2, #line.args do rest[#rest + 1] = self:val(line.args[i]) end
    local okjump = JUMPS[c](self, line.target, rest[1], rest[2])
    if okjump then
      if c == "JMPREL" then
        local off = line.rel
        if type(off) == "string" and off:sub(1, 1) == "$" then
          off = self.vars[off:sub(2)] or 0
        else
          off = tonumber(off) or 0
        end
        self.pc = self.pc + off
      else
        local t = line.target
        if type(t) == "string" then self.pc = self.vars[t:sub(2)] or 0
        else self.pc = FLOOR(t or 0) end
      end
      return true
    end
    return nil
  end
  local fn = CMD[c]
  if not fn then say(self, 'unknown ' .. tostring(c)); return nil end
  local a = {}
  for i = 1, #line.args do a[i] = self:val(line.args[i]) end
  fn(self, a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8])
  return nil
end

function World:stepScript(dt)
  if #self.prog == 0 then return end
  local guard = 0
  self.wait = self.wait - dt
  while (not self.paused) and (not self.ended) and self.wait <= 0 do
    guard = guard + 1
    if guard > 5000 then break end
    if self.pc < 0 or self.pc >= #self.prog then self.pc = #self.prog; return end
    local line = self.prog[self.pc + 1]
    local jumped = self:exec(line)
    if self.ended then return end
    if jumped == nil then self.pc = self.pc + 1 end
    if self.pc >= #self.prog then return end
    local nd = nextDelay(self, self.prog[self.pc + 1])
    self.wait = (type(nd) == 'number') and self:itv(nd) or nd   -- G3：间隔吃难度倍率
    if self.wait > 0 then return end
  end
end

function World:stepZone(dt)
  local z = self.zone
  local sp = z.speed * dt
  local done = true
  local keys = { 'l', 't', 'r', 'b' }
  for _, k in ipairs(keys) do
    local target = z['t' .. k]
    if math.abs(z[k] - target) <= sp then z[k] = target
    else
      z[k] = z[k] + ((target > z[k]) and sp or -sp)
      done = false
    end
  end
  if done then
    z.resizing = false
    local f = z.finish
    z.finish = nil
    if f ~= nil and CMD[f] then CMD[f](self) end
  end
end

function World:stepStab(b, dt)
  b.t = b.t + dt
  if b.phase == 'warn' then
    if b.t >= b.warn then b.phase = 'out'; b.t = 0 end
    return
  end
  -- 【回合差异文档 2.7】伸出时间可配置（默认 0.1s → 0.22s，约原版两倍，可读性更好）
  local outDur = b.outDur or 0.22
  if b.phase == 'out' then
    b.cur = math.min(b.dist, b.dist * (b.t / outDur))
    if b.t >= outDur then b.phase = 'stay'; b.t = 0; b.cur = b.dist end
    return
  end
  if b.phase == 'stay' then
    b.cur = b.dist
    if b.t >= b.stay then b.phase = 'in'; b.t = 0 end
    return
  end
  b.cur = b.dist * math.max(0, 1 - b.t / 0.1)
  if b.t >= 0.1 then b.cur = 0; b.dead = true end
end

-- 骨刺墙的命中矩形
function World:stabRect(b)
  local z = self.zone
  local d = b.cur or 0
  if b.arrowbone then
    -- 箭头模块（第十一轮改造）：dir 那条边**整条升起一排骨头**，一起向框内伸出 depth。
    --   0=东（右边框）/ 2=西（左边框）：整条竖边；1=南（下边框）/ 3=北（上边框）：整条横边。
    if b.dir == 0 then return { x = z.r - d, y = z.t, w = d, h = z.b - z.t } end
    if b.dir == 2 then return { x = z.l, y = z.t, w = d, h = z.b - z.t } end
    if b.dir == 1 then return { x = z.l, y = z.b - d, w = z.r - z.l, h = d } end
    return { x = z.l, y = z.t, w = z.r - z.l, h = d }
  end
  -- 【回合差异文档 2.6】与原版一致：0=右 1=下 2=左 3=上（旧实现整体反向）
  if b.dir == 0 then return { x = z.r - d, y = z.t, w = d, h = z.b - z.t } end
  if b.dir == 2 then return { x = z.l, y = z.t, w = d, h = z.b - z.t } end
  if b.dir == 1 then return { x = z.l, y = z.b - d, w = z.r - z.l, h = d } end
  return { x = z.l, y = z.t, w = z.r - z.l, h = d }
end

-- 脚本自身的时间线长度 = 各行延时之和（延时语义是"执行该行前等多久"，首行也要等）。
-- 含变量延时（`$var`）或**循环**（JMPABS 回跳）时静态算不出来 → 返回 nil。
-- 【差距文档第二轮 G1/G2】静态求和还会**严重低估**有循环的脚本（spiral1 静态 0.09s / 实际 10.58s，
-- 低估 118 倍），导致回合被 enemyDur 掐断、后半段永远播不到。补救见下面的 simulateLength()。
-- 【G3】难度倍率助手：脚本里的速度/间隔/预警统一乘难度系数（原版档 = 1.0 = 原值）
function World:spd(v) return (tonumber(v) or 0) * (self.tune and self.tune.speed or 1) * (self.tauntMul or 1) end   -- N3：挑衅也乘进来
function World:itv(v) return (tonumber(v) or 0) * (self.tune and self.tune.interval or 1) end
function World:wn(v) return (tonumber(v) or 0) * (self.tune and self.tune.warn or 1) end

function World:scriptLength()
  local t = 0
  for _, line in ipairs(self.prog) do
    local d = line.delay
    if type(d) ~= 'number' then return nil end
    t = t + d
  end
  return t
end

-- 【G1/G2】干跑求**真实**时长：复制一份 world（同 seed / 同脚本），把心钉在框中心，
-- 只推进 World:update（不渲染、不碰撞判定）直到 EndAttack 或超时，返回秒数。
-- 这样循环（JMPABS）、变量延时（$Wait1）、条件分支都能算准。
function World:simulateLength(maxSec)
  maxSec = maxSec or 120
  local probe = newWorld({ seed = self.seed, compiled = self.script })
  local steps = math.floor(maxSec / DT)
  for i = 1, steps do
    -- 心钉住（GetHeartPos 会读它；不钉的话骨刺/坠落会把脚本带偏）
    probe.heart.x, probe.heart.y = 320, 304
    probe:update(DT)
    if probe.ended then return i * DT end
  end
  return nil
end

function World:update(dt)
  if self.ended then return end
  self.time = self.time + dt
  if (self.shakeI or 0) > 0 then   -- 【A-7】SansShake：每 1/30s 随机跳一次偏移
    self.shakeT = (self.shakeT or 0) + dt
    while self.shakeT >= 1 / 30 do
      self.shakeT = self.shakeT - 1 / 30
      self.shakeI = self.shakeI - 1
      self.shakeX = self.shakeI * ((self.rng() < 0.5) and -1 or 1)
      self.shakeY = self.shakeI * ((self.rng() < 0.5) and -1 or 1)
      if self.shakeI <= 0 then self.shakeX, self.shakeY = 0, 0 break end
    end
  end
  if self.flash > 0 then self.flash = math.max(0, self.flash - dt) end

  -- 1) 脚本推进（TLPause 时暂停脚本，但战斗框变形照旧）
  --    每帧**只推进一步** zone 变形：曾经在 paused 分支里调一次、下面又无条件调一次，
  --    结果框体入场变形按 2 倍速完成（11 个靠 CombatZoneResize...TLResume 起手的关卡都变短）。
  if not self.paused then
    self:stepScript(dt)
  end
  -- 2) 战斗框变形（无条件执行一次；stepScript 里可能刚把 resizing 打开）
  if self.zone.resizing then self:stepZone(dt) end

  -- 3) 实体运动
  local i = #self.bones
  while i >= 1 do
    local b = self.bones[i]
    local kill = false
    if b.stab or b.arrowbone then
      self:stepStab(b, dt)
      if b.dead then kill = true end
    elseif b.custom then
      -- 游戏侧自建骨头（floor / blue / slide）：位置由 Game:update 驱动，这里不动
      kill = false
    else
      b.x = b.x + b.vx * dt
      b.y = b.y + b.vy * dt
      if b.x > VW + 400 or b.x < -400 or b.y > VH + 400 or b.y < -400 then kill = true end
    end
    if kill then table.remove(self.bones, i) end
    i = i - 1
  end
  i = #self.sine
  while i >= 1 do
    local s = self.sine[i]
    s.x = s.x + s.dir * s.speed * dt
    s.t = (s.t or 0) + dt
    -- 原版波形是**静态**的（Sine 只跟序号有关），这里不做相位推进，只整体平移。
    if s.x > VW + 400 or s.x < -400 then table.remove(self.sine, i) end
    i = i - 1
  end
  i = #self.blasters
  while i >= 1 do
    local g = self.blasters[i]
    g.t = g.t + dt
    if g.state == 'spin' then
      local k = math.min(1, g.t / g.spin)
      g.x = g.sx + (g.ex - g.sx) * k
      g.y = g.sy + (g.ey - g.sy) * k
      g.ang = g.ang0 + (g.endAng - g.ang0) * k
      if k >= 1 then g.state = 'spinning'; g.t = 0 end
    elseif g.axis and g.state == 'charge' then
      -- 内置模式的龙骨炮（axis/pos 表达）：没有 SpinTime 字段，用 warn 计时后直接开火。
      -- 修复前它永远停在 charge —— 渲染/判定都要求 state=='fire'，于是整条内置龙骨炮形同虚设。
      if g.t >= (g.warn or 0.7) then g.state = 'fire'; g.t = 0 end
    elseif g.state == 'spinning' then
      g.ang = g.endAng
      -- HoldTime（本项目扩展，第 10 个参数）：转到位后再停 hold 秒才发射
      if g.t >= 0.05 + (g.hold or 0) then g.state = 'fire'; g.t = 0 end
    elseif g.state == 'fire' and not g.persistent and g.t >= (g.blast or 0) then
      g.state = 'done'
    end
    -- 持续光束（blast=0 / persistent）：一直停在 fire，直到 EndAttack 收束
    if g.state == 'done' and g.t > (g.blast or 0) + 0.15 then table.remove(self.blasters, i) end
    i = i - 1
  end
  for _, p in ipairs(self.platforms) do
    p.t = (p.t or 0) + dt
    local sp = p.speed or 0
    if (p.ramp or 0) > 0 then sp = sp * math.min(1, p.t / p.ramp) end   -- 0 → 全速
    local vx = (p.dir == 0) and sp or ((p.dir == 2) and -sp or 0)
    local vy = (p.dir == 1) and sp or ((p.dir == 3) and -sp or 0)
    p.vx, p.vy = vx, vy                     -- 供「站在平台上被平台带着走」用同一份速度
    p.x = p.x + vx * dt
    p.y = p.y + vy * dt
    -- BooleanReverse=1：到往返边界就掉头（CSV 未给范围，用 x0/y0 ± travel）
    -- 【用户验收】reverse 往返的边界 = **整条战斗框**（横跨整个框再返回），不再用固定 ±PLATFORM_TRAVEL
    if p.reverse and (p.speed or 0) > 0 then
      local zz = self.zone
      local axis = (vx ~= 0) and 'x' or ((vy ~= 0) and 'y' or nil)
      if axis then
        local lo, hi
        if axis == 'x' then lo, hi = zz.l, zz.r - (p.w or 0) else lo, hi = zz.t, zz.b - (p.h or 0) end
        local o = lo
        p.travel = hi - lo
        if p[axis] > hi or p[axis] < lo then
          p.dir = (p.dir + 2) % 4                     -- 0<->2（x 轴）/ 1<->3（y 轴）
          p[axis] = clamp(p[axis], lo, hi)
          -- 【第三轮 N7】反弹后要用**当前 ramp 速度**重算（不能用 p.speed 直接全速），并写回 p.vx/p.vy
          vx = (p.dir == 0) and sp or ((p.dir == 2) and -sp or 0)
          vy = (p.dir == 1) and sp or ((p.dir == 3) and -sp or 0)
          p.vx, p.vy = vx, vy
        end
      end
    end
  end

  -- 【差距文档第二轮 G5：删掉 World 侧的灵魂物理】
  -- 旧实现这里还有一套「蓝魂沿重力方向积分 w.heart.vx/vy」的物理，而 Game:update 里又跑一套
  -- 「匀速上升/下落」的蓝魂物理，并且在帧末把 w.heart.x/y 覆盖回 Game.soul —— 两套物理、两份状态，
  -- 谁后跑谁赢（探针实测 World 侧那套在真游戏里 100% 是死代码）。
  -- 现在 World.heart **只做脚本的坐标/速度寄存器**（HeartTeleport / GetHeartPos / SansSlam 写它），
  -- 真正的物理与钳位一律由 Game.soul 负责（见 Game:update 与帧末的镜像）。
end

-- ------------------------------------------------------------ 坐标/几何
-- 战斗框的**唯一参照**是 world.zone。回合 1-5 没有攻击脚本，此时造一个"只有框"
-- 的默认 world，**zone 必须等于本次回合的 box 抬到世界帧**（box② + BOX_OFF），否则骨头会落在
-- 框外、命中判定全错。所有生成/几何都走同一条路径，避免"有脚本 / 没脚本"两套坐标。
local function ensureWorld(self)
  if not self.world then
    local b = self.box
    local w = newWorld({ seed = self.bootSeed })
    w.zone.l, w.zone.t = b.x + BOX_OFF_X, b.y + BOX_OFF_Y
    w.zone.r, w.zone.b = w.zone.l + b.w, w.zone.t + b.h
    w.zone.tl, w.zone.tt = w.zone.l, w.zone.t
    w.zone.tr, w.zone.tb = w.zone.r, w.zone.b
    self.world = w
  end
  return self.world
end

-- 坐标契约（唯一口径，两套帧，别混）：
--   ① 世界帧 = 原版 640×480 屏幕坐标：world.zone（zone.tl/tt/tr/tb）、world 里的
--      骨头/骨刺/龙骨炮/正弦/平台、以及 **M.render 的唯一输出口径**。
--      CSV 里的数值直接就是这一帧（`CombatZoneResizeInstant,239,226,404,391` =
--      原版那个 165×165 框在屏幕上的位置），所以 **① == 画布落地帧**，中间不再有平移。
--   ② 框内相对帧 = ① - (BOX_OFF_X, BOX_OFF_Y)：Game.box、Game.soul、walls、内置弹幕/平台。
--      只有这一类在 render 出口 **+BOX_OFF 一次**。
--   Game.box 永远跟随 world.zone（zoneOf），所以①和②始终只差一个常量偏移。
--   判定侧同口径：碰撞循环把 soul(②) 用 +BOX_OFF 抬到①再和世界实体比（见 update）。
local function zoneOf(w)
  local z = w.zone
  return { x = z.l - BOX_OFF_X, y = z.t - BOX_OFF_Y, w = z.r - z.l, h = z.b - z.t }
end
local function absOfBox(b)
  return { x = b.x + BOX_OFF_X, y = b.y + BOX_OFF_Y, w = b.w, h = b.h }
end
local function stabRectOf(w, b)
  local r = w:stabRect(b)                 -- 脚本坐标
  return { x = r.x - BOX_OFF_X, y = r.y - BOX_OFF_Y, w = r.w, h = r.h }
end
-- 正弦骨几何：**命中盒与走廊渲染共用同一份 centerY**（否则会出现"看着躲开了却掉血"）
--   centerY = clamp(baseY + amp*sin(phase), zone.t+half, zone.b-half)
--   走廊   = centerY ± half（half = |gap|/2）
--   两根长骨 = 走廊上下壁到**战斗框上下边**之间的竖骨（不是命中盒！见 bars 的注释）
local function sineGeom(s)
  -- 原版 SineBones 的走廊：上骨从 zone.t+6 起、高 (height + sine)，走廊再从它下面量 39px。
  local zoneT = s.zoneT or 0
  local zoneB = s.zoneB or VH
  local hgt = s.height or 25
  local sine = s.sine or 0
  local top = zoneT + 6 + hgt + sine                       -- 上骨底 = 走廊上口
  local bottom = top + (s.gap or 39)                       -- 走廊下口（原版固定 +39）
  return {
    x = s.x - BONE_W / 2, w = BONE_W,
    top = top, bottom = bottom, centerY = (top + bottom) / 2,
    gap = bottom - top, amp = s.amp or 28, phase = s.phase or 0, bar = s.bar or SINE_BAR_H,
    zoneT = zoneT, zoneB = zoneB,
  }
end
-- 两根长骨的矩形（**世界帧**，与 world.zone 同帧、与 render 输出同帧）。
-- 约定：**竖骨，厚度 = w（=19，与命中盒同宽），长度 = h**；从战斗框上下边顶到走廊口。
-- h <= 0（走廊被夹到框边）时不输出该根。
local function sineBars(s, gm, offY)
  offY = offY or 0
  local zoneT = (s.zoneT or 0) + offY
  local zoneB = (s.zoneB or VH) + offY
  local topEdge = gm.centerY + offY - math.abs(s.gap or 25) * 0.5     -- 走廊上口
  local botEdge = gm.centerY + offY + math.abs(s.gap or 25) * 0.5     -- 走廊下口
  local bars = {}
  local h1 = topEdge - zoneT
  if h1 > 0 then
    bars[#bars + 1] = { x = gm.x, y = zoneT, w = gm.w, h = h1, vertical = true }
  end
  local h2 = zoneB - botEdge
  if h2 > 0 then
    bars[#bars + 1] = { x = gm.x, y = botEdge, w = gm.w, h = h2, vertical = true }
  end
  return bars
end
-- 正弦骨的命中：**打的是看得见的两根长骨**（= 命中盒与视觉同形）。
-- 为什么不是"走廊中心的小方块"：SineBones 的视觉是"上下两根长骨夹一条走廊"，
-- 玩家靠**看**判断该不该躲；如果判定只在走廊中心一个 19×19 的隐形小盒子上，
-- 就会出现"明明站在骨头上却不掉血"。走廊宽度 = gap 不变，所以难度并没有变高
-- （旧写法只覆盖 gap 中间一条缝，反而更宽松）。
local function sineHitTest(s, SX, SY, r)
  local gm = sineGeom(s)
  for _, rc in ipairs(sineBars(s, gm, 0)) do
    if rectHit(SX, SY, r, rc) then return true end
  end
  return false
end

-- ==========================================================================
-- 【原版保真：CombatZoneClipped】竖骨的裁剪
-- --------------------------------------------------------------------------
-- BTS（jcw87/c2-sans-fight）里每种对象建在哪个图层是写死的：
--     BoneV / BoneVRepeat / BoneStabV / BoneStabH -> CombatZoneClipped
--     BoneH / BoneHRepeat / GasterBlaster          -> CombatZone（**不裁**）
-- 而 CombatZoneClipped 图层外框由 4 块 CombatZoneClipper(TiledBg) 盖住
-- （CombatZoneTick：上/左/右/下各一块，尺寸按 CombatZone 现算），所以
-- **只有竖骨**会被裁到战斗框内；横骨和龙骨炮要能露出框外（龙骨炮本来就从屏幕角飞进来）。
--
-- 我们这边是图元拼装、没有裁剪层，于是直接把**竖骨的矩形裁进 zone**：
--   * 灵魂永远被钳在框内 → “裁后的矩形”和“整根骨头”的命中结果**完全等价**
--     （不是削弱判定，是把框外那段本来就不可能碰到的部分去掉）；
--   * 视觉上骨头从框边探出来（BoneVRepeat,128,... 框左 133 → 只画 133..147），
--     而不是整根飘在框外 —— 与 BTS 一致（用户验收：避免攻击超出战斗框范围）。
-- 返回 nil = 整根都在框外，这一帧不必输出。
local function clipVZone(x, y, w, h, z)
  if not z then return x, y, w, h end
  local x2 = (x < z.l) and z.l or x
  local y2 = (y < z.t) and z.t or y
  local r2 = ((x + w) > z.r) and z.r or (x + w)
  local b2 = ((y + h) > z.b) and z.b or (y + h)
  if r2 - x2 <= 0 or b2 - y2 <= 0 then return nil end
  return x2, y2, r2 - x2, b2 - y2
end

-- ==========================================================================
-- 游戏（对应 game.js 的 Game）
-- ==========================================================================
local Game = {}
Game.__index = Game

local function scriptOf(scripts, name)
  for _, s in ipairs(scripts or {}) do
    if s.name == name then return s.csv end
  end
  return nil
end

local function roundDef(g, n)
  if n == 0 then return SURPRISE end
  -- 【P-02】不再是「17..19 = 螺旋档」：固定序列表里这些回合是 bonestab/multi 等；
  -- 旋转光束只出现在终盘 sans_final 里（脚本自己带 CombatZoneResize）。
  if n > #ROUND_DEF then return SCRIPT_ROUND end
  return ROUND_DEF[n]
end

-- ---------------------------------------------------------------- 抽签
-- "除了见面杀之外都用随机函数抽取模板攻击"（用户验收要求）。规则：
--   ① 只在当前难度档包含的模板套里抽（回合越后档位越高，见 TEMPLATE_TIERS）；
--   ② 连续两回合不抽同一个脚本；③ 整场抽到越少的越优先（12 次采样里挑用得最少的；抽到"没用过"就停）。
-- 随机源是 Game 自己的 mulberry32（固定 seed）→ 同一难度、同一操作序列下抽签结果可复现，
-- 离线回归（_rounds.lua）与模拟器日志查的是同一条序列。
local function drawTemplate(g, n)
  local tier = TEMPLATE_TIERS[clamp(math.floor((n - 1) / 4) + 1, 1, #TEMPLATE_TIERS)]
  local pool = {}
  for _, setName in ipairs(tier) do
    for _, name in ipairs(TEMPLATE_SETS[setName] or {}) do pool[#pool + 1] = name end
  end
  if #pool == 0 then return nil end
  local best, bestUses = nil, math.huge
  for _ = 1, 12 do
    local cand = pool[1 + math.floor(g.rng() * #pool)]
    local uses = g.scriptUses[cand] or 0
    if cand ~= g.lastScript and uses < bestUses then best, bestUses = cand, uses end
    if bestUses == 0 then break end
  end
  if not best then best = pool[1 + math.floor(g.rng() * #pool)] end
  return best
end

-- 【差距文档 P-02 + §1 总表】原作是**固定编排**（23 个攻击回合 + 终盘），不是每回合随机抽。
-- 下面这张表逐行抄自《Sans_Fight_差距与修改文档》§1 的「回合 ↔ 攻击脚本」对照表。
local FIXED_SEQ = {
  [1]  = 'sans_bonegap1',      [2]  = 'sans_bluebone',     [3]  = 'sans_bonegap2',
  [4]  = 'platforms1',    [5]  = 'platforms2',   [6]  = 'platforms3',
  [7]  = 'platforms4',    [8]  = 'platformblaster', [9] = 'platforms4hard',
  [10] = 'sans_bonegap1fast',  [11] = 'sans_boneslideh',   [12] = 'sans_bonegap2',
  [13] = 'sans_spare',         [14] = 'multi1',       [15] = 'randomblaster1',
  [16] = 'multi2',        [17] = 'sans_bonestab1',    [18] = 'sans_bonestab2',
  [19] = 'randomblaster2',[20] = 'sans_boneslidev',   [21] = 'multi3',
  [22] = 'sans_bonestab3',
}
-- 本回合照哪个脚本打：0 = 见面杀；>= LAST_ROUND（23）= 原作 sans_final（终盘/胜利）；其余查固定表。
local function scriptForRound(g, n)
  if n == 0 then return 'sans_intro' end
  if n >= LAST_ROUND then return 'final' end
  return FIXED_SEQ[n]
end

function Game:setDiff(i)
  self.titleIndex = clamp(i, 0, #DIFF_ORDER - 1)
  self.diffKey = DIFF_ORDER[self.titleIndex + 1]
  return self.diffKey
end

function Game:sp(v) return v * self.tune.speed end
function Game:it(v) return v * self.tune.interval end

function Game:log(s)
  self.logs[#self.logs + 1] = s
end
function Game:hasLog(s)
  for i = 1, #self.logs do
    if self.logs[i]:find(s, 1, true) then return true end
  end
  return false
end
function Game:logsFrom(n)
  local out = {}
  for i = n + 1, #self.logs do out[#out + 1] = self.logs[i] end
  return out
end

function Game:resetRun()
  self.hp = self.bootHP
  self.kr = 0
  -- 【2026-10-05 第九轮 · 用户口径】食物大量增加，**全部**是「传奇面包」，每口回复 45 HP。
  self.items = {
    { id = 'legend_bread', name = '传奇面包', desc = '回复 45 HP', heal = 45, count = 20 },
  }
  self.taunt = 0
  self.talk = {}
  self.round = self.bootRound
  -- B-01：调试钩子直接从第 N 回合开局时，把「FIGHT 次数」也对齐到 N（否则 final 门控永远不成立）
  self.fightCount = ((self.bootRound or 1) > 1) and self.bootRound or 0
  self.invuln = 0
  self.flash = 0
  self.krFloorLogged = false
  self.shakeI, self.shakeT, self.shakeX, self.shakeY = 0, 0, 0, 0   -- 【A-7】SansShake
  self.krActive = false
  self.krT = 0
  self.final = false
  -- 抽签状态：整场每个模板被抽到几次（用于"优先没抽过的"）、上一次抽到谁（防连续重复）
  self.scriptUses = {}
  self.lastScript = nil
  self.roundScript = nil
  self.result = nil
  self.failReason = nil
  self.interlude = false
  self.menuIndex = 0
  self.attackCursor = 0
  self.attackDir = 1
  self.attackResult = nil
  self.attackHold = 0
  self.sansDodge = 0
  self.line = ''
  self.lineShown = 0
  self.lineT = 0
  self.rng = mulberry32(self.bootSeed)
  -- 初始框与灵魂都在**帧②（框内相对坐标）**：绝对中心 (320,183) 的 420x260
  self.box = { x = (BOX_CX - 210) - BOX_OFF_X, y = (BOX_CY - 130) - BOX_OFF_Y, w = 420, h = 260 }
  -- 灵魂必须放在**框内**（曾经写的是绝对 320,183，框改成帧②后那已经跑到框外 240px）
  self.soul = { dir = 1, slammed = false, x = self.box.x + self.box.w / 2, y = self.box.y + self.box.h / 2,
                vx = 0, vy = 0, mode = 'red', grounded = false }
  self.walls = {}
  self.world = nil
  self.sine = {}
  self.wave = 0
  self.wavesAlive = {}
  self.prevX, self.prevY = self.soul.x, self.soul.y
  self.keys = {}
  self.prevKeys = {}
  self.hitT = 0
end

function Game:start()
  self.tune = DIFFS[self.diffKey] or DIFFS.normal
  self:resetRun()
  self:log('game_start hp=' .. self.hp .. ' kr=' .. self.kr .. ' round=' .. self.round ..
           ' seed=' .. tostring(self.bootSeed) .. ' diff=' .. self.tune.key)
  self:startEnemy(self.bootRound > 1 and self.bootRound or 0)
end

function Game:restart()
  self:log('restart')
  self:start()
end

local function makeWorld(g, name)
  local csv = scriptOf(g.scripts, name)
  if not csv then return nil end
  -- 【G3】把难度档的 speed/interval/warn 传进 World：脚本回合也要吃难度
  return newWorld({ seed = g.bootSeed, script = parseCSV(csv), tune = g.tune })
end

local function startScript(g, name)
  g.world = makeWorld(g, name)
  if g.world then
    local raw = g.scripts and scriptOf(g.scripts, name)
    g.scriptName = raw and name or name
    -- 首帧之前先把战斗框放到与游戏帧一致的位置（避免开局一帧错位）
    g.box = zoneOf(g.world)
  if g.world then g.world.scriptName = name end   -- 【方案A】供 CMD.GasterBlaster 判断是否初见杀
  if g.world then g.world.tauntMul = 1 + 0.10 * (g.taunt or 0) end
    g.sine = g.world.sine
  end
end

-- （FINAL_SCRIPTS 已删除：最后三回合改走螺旋档 SPIRAL_SCRIPTS，不再"复用现成脚本凑三段"）

-- 仅供测试/适配层：按名字挂载一个攻击脚本世界
-- 【N3】挑衅（ACT）现在对**脚本回合**也生效：World:spd 会乘上这个倍率
function Game:startEnemyScript(name)
  startScript(self, name)
  return self.world
end

-- 内置回合的战斗框尺寸：以**绝对中心 (BOX_CX, BOX_CY)** 摆放，再钳进 640x480。
-- 为什么要钳：R6（重力）在原型里是 660x400 —— 那是按 1280x720 设计板写的；
-- 落到 640x480 世界后，中心 y=308.5 能容纳的最大对称框是 640x343，
-- 660x400 会左右各出界 10px、上下各出界 28.5px（"框跑到世界外"的一部分）。
-- 下面 R6/FINAL1 已把设计值下调到 600x340，钳位只是兜底 + 记日志。
local BOX_MAX_W, BOX_MAX_H = 620, 340
local function fitBoxSize(bw, bh)
  local w, h = bw, bh
  if w > BOX_MAX_W then w = BOX_MAX_W end
  if h > BOX_MAX_H then h = BOX_MAX_H end
  if w ~= bw or h ~= bh then
    -- 不刷屏：只记一次（真正的修复应该在 ROUND_DEF 里改数值）
    if not _G.SANS_BOX_CLAMP_LOGGED then
      _G.SANS_BOX_CLAMP_LOGGED = true
      -- luacheck: ignore
      print(string.format('[core] box size clamped: %dx%d -> %dx%d (world %dx%d, center %.1f,%.1f)',
        bw, bh, w, h, VW, VH, BOX_CX, BOX_CY))
    end
  end
  -- 再按世界尺寸兜一层底
  return math.min(w, VW), math.min(h, VH)
end

function Game:startEnemy(n)
  local d = roundDef(self, n)
  self.round = n
  -- **写入帧②（框内相对坐标）**：self.box 是"脚本坐标 - BOX_OFF"，
  -- M.render 输出时再 +BOX_OFF 变回绝对坐标。
  -- 曾经这里直接写绝对中心（BOX_CX/BOX_CY 就是绝对 320/183），render 又加了一次
  -- → 内置回合的框被双平移，跑到世界外（"战斗框随机移动"的主因）。
  local bw, bh = fitBoxSize(d.bw, d.bh)
  local absL, absT = BOX_CX - bw / 2, BOX_CY - bh / 2
  self.box = { x = absL - BOX_OFF_X, y = absT - BOX_OFF_Y, w = bw, h = bh }
  self.state = 'enemy'
  self.enemyT = 0
  self.enemyDur = d.dur
  self.spawnT = self:it((d.pattern == 'bone_wall' or d.pattern == 'mixed') and 0.9 or 0.8)
  self.wallT = self:it(1.6)
  self.warn = (d.p.warn or 0.6) * self.tune.warn
  self.warnWall = 0.75 * self.tune.warn
  if n == 2 then self.firstBarrierDone = false end
  self.spd = 1 + 0.10 * (self.taunt or 0)
  self.wave = 0
  self.wavesAlive = {}
  self.floorLock = 0
  self.colorFlip = false
  self.walls = {}
  self.world = nil
  self.sine = {}
  self.whiteT = nil
  self.soul.mode = (d.pattern == 'blue_soul') and 'blue' or 'red'
  self.soul.vx, self.soul.vy = 0, 0
  self.soul.dir = 1                 -- 【A-1】重力方向：0东 1南(默认) 2西 3北
  self.soul.slammed = false
  self.soul.maxFall = nil
  -- 帧②：灵魂摆在框的水平中心、垂直居中（blue_soul 落到底部）
  self.soul.x = self.box.x + self.box.w / 2
  self.soul.y = (d.pattern == 'blue_soul') and (self.box.y + self.box.h - 40) or (self.box.y + self.box.h / 2)
  self.prevX, self.prevY = self.soul.x, self.soul.y
  -- 【ROUND 7 幽灵平台 bug（第七轮修）】原来这里**无条件**给 blue_soul 回合造内置平台，
  -- 可是 20 回合版里这一回合照样会挂攻击脚本 → 场上同时有「脚本骨头」和「内置平台」，
  -- 玩家看到的『不应存在的平台』就是这么来的。改成：**只有这一回合不带脚本时才造**（见下面 sname 之后）。
  self:log('round_start round=' .. n)

  -- 攻击脚本挂载：0 = 见面杀，>=17 = 螺旋档，其余 = 从多套模板里随机抽（见 scriptForRound）。
  -- `testNoScript`（newGame 的 opts.noScriptRounds）是**测试钩子**：置位后本回合不挂脚本，
  -- 用来测"没有脚本时的内置生成器兜底"（bone_floor / bone_wall / difficulty 节拍那些用例）。
  -- 抽签结果与"这个脚本整场被抽到几次"都记日志 —— 模拟器里一眼能看出这 20 回合抽了什么。
  -- 注意别写成 `self.testNoScript and nil or scriptForRound(...)`：
  -- `true and nil` 就是 nil，`nil or f()` 会把 f() 算出来 —— 钩子会静默失效（踩过）。
  local sname
  if not self.testNoScript then sname = scriptForRound(self, n) end
  if sname then
    self.scriptUses[sname] = (self.scriptUses[sname] or 0) + 1
    self.lastScript = sname
    self.roundScript = sname
    self:log(string.format('round_script round=%d script=%s used=%d',
      n, sname, self.scriptUses[sname]))
    startScript(self, sname)
  else
    self.roundScript = nil
  end
  -- blue_soul 的内置平台只在**没有攻击脚本**时才是这一回合的内容（见上面 run7 幽灵平台注释）
  if d.pattern == 'blue_soul' and sname == nil then self:buildPlatforms() end

  -- 挂脚本后框会被脚本的 zone 改写（如 sans_intro 的 165x165）：
  -- 灵魂要重新摆到**新框的中心**（不是钳到边界！钳到边界会正好落进骨头的格子），
  -- 并把 prev 一起对齐，避免第一帧被判成"发生位移"而吃到蓝骨判定。
  if self.world then
    self.box = zoneOf(self.world)
    local b = self.box
    self.soul.x = b.x + b.w / 2
    self.soul.y = (d.pattern == 'blue_soul') and (b.y + b.h - 40) or (b.y + b.h / 2)
    self.soul.mode = (d.pattern == 'blue_soul') and 'blue' or 'red'
    self.prevX, self.prevY = self.soul.x, self.soul.y
    -- 回合时长必须**覆盖脚本自己的时间线**，否则脚本后半段永远播不到。
    -- 实例（用户核对"初见杀序列"时发现）：sans_intro 全长 8.93s
    -- （骨刺 0.83s → 正弦骨 2.33s → 三组龙骨炮 3.43 / 4.33 / 5.23s → 大字转场 8.93s），
    -- 而 SURPRISE.dur 只有 2.8s —— 回合在 2.8s 就被 endEnemy 掐断，
    -- **三组龙骨炮一发都没打出来**，正弦骨只扫了 0.47s。
    -- 只延长、不缩短：脚本比回合短时仍然是回合时长说了算（如最终回合三段）。
    local need = self.world:scriptLength()
    -- 【G1/G2】静态求和只对「线性、无循环」的脚本准确；含变量延时（$Wait）会返回 nil，
    -- 含循环（spiral1 JMPABS 回跳）会**严重低估**（0.09s vs 实际 10.58s；bonestab3 5.27 vs 26.55）。
    -- 所以一律用干跑值兜底，取两者**较大**的：宁可长一点，也不能把后半段截断。
    -- 【第三轮 N2】按脚本名缓存干跑结果（final 单次约 1.15s CPU，不缓存会导致每回合开局卡顿）
    self.durCache = self.durCache or {}
    local ck = self.roundScript or ('r' .. tostring(n))
    local real = self.durCache[ck]
    if real == nil then
      real = self.world:simulateLength() or false
      self.durCache[ck] = real
    end
    if real == false then real = nil end
    if real and (need == nil or real > need) then need = real end
    if need and (need + DT) > self.enemyDur then self.enemyDur = need + DT end
  end

  -- 【第三轮 N8】ROUND 0 同时挂着 sans_intro 脚本，内置「意外攻击」地面骨会让场上有两套弹幕。
  -- 原来这里不受 scriptOwnsRound 保护 → 现在也让它让位（有脚本时不补内置地面骨）。
  if d.pattern == 'surprise' and self.world == nil then
    if not self.testNoSpawn then
      self:spawnFloor(d.p.peek)
      -- 原版 game.js 在这里还有一次 spawnBlaster(1)；但一旦本移植把 sans_intro 接进回合 0，
      -- 它的 `0,BlackScreen,1` 会把所有弹幕清空（含这发冲击波），于是这发**永远打不出来**，
      -- 却会在 startEnemy 里立刻以 state='charge' 建立、同一帧就因 warn=0 转 fire → 命中灵魂。
      -- 为了与原版一致（不产生"开局秒命中"的假伤害），回合 0 不再补这一发。
      -- 注意：这里**不乘难度间隔**（JS 里也是裸值，改成 self:it(...) 会让简单档拖到 2.24s）
      self.spawnT = d.p.interval
    else
      self.spawnT = 1e9
    end
  end
  self:say(lineForRound(n))
end

function Game:endEnemy()
  self:log('round_clear round=' .. self.round)
  -- 【回合结束必须清空**全部**场地实体】
  -- 曾经只清 world/sine：内置生成器的骨墙walls、蓝魂平台platforms、波次记账wavesAlive
  -- 都留在原处，而 M.render 在菜单/子面板/攻击条态**照样**画它们 →
  -- 回合 6 是 blue_soul（带平台），玩家看到的正是"六回合打完了，平台还挂在场上"。
  -- 现在统一在这里清；M.render 也加了 state 守卫（双保险，见那边的注释）。
  self.world = nil
  self.sine = {}
  self.walls = {}
  self.platforms = {}          -- 必须是空表而不是 nil：下面平台碰撞循环会 ipairs 它
  self.wavesAlive = {}
  self.whiteT = nil
  self.floorLock = 0
  self.state = 'menu'
  self.menuIndex = 0
  -- 最后一回合打完之后 final = true：原作里这时 Sans 已经力竭、躲不开，
  -- 玩家在菜单里选「攻击」就是致命一击（stopAttack 按 self.final 走"必中"分支），
  -- 选「仁慈」则是饶恕结局。中间任何一回合结束都不会置位。
  -- 【差距文档 B-01】原版 `HitAttempts` **只在 FIGHT 闪避走完时 +1**；ACT/ITEM/MERCY 不推进阶段。
  -- 我们把它拆成两个量：`round`（攻击脚本序列，每次行动都 +1）与 `fightCount`（阶段门控，只数 FIGHT）。
  -- 【第三轮 N1】门控统一到 `round`（攻击序列号）：非 FIGHT 打法也能走到终盘；fightCount 只作统计。
  self.final = (self.round >= LAST_ROUND)
  -- 原作第 12 次攻击后是「中场」：Sans 停手，直到玩家主动攻击——官方给的补给窗口。
  -- 只在**还没到最终回合**时进入；最终回合结束后直接给结局台词。
  if self.round == self.interludeAfter and not self.final then
    self.interlude = true
    self:log('interlude')
    self:say(LINES.midpoint)
    return
  end
  if self.final then self:say(LINES.final) end
end

function Game:finish(outcome, reason)
  self.result = outcome
  self.failReason = reason or nil
  self.state = 'result'
  if outcome == 'fail' then self:log('fail ' .. (reason or 'hp_zero'))
  else self:log('win outcome=' .. outcome) end
end

function Game:sansShake(intensity)   -- 【A-7】撞墙抖屏
  self.shakeI = math.max(0, math.floor(intensity or 0))
  self.shakeT = 0
end
function Game:say(t) self.line = t; self.lineShown = 0; self.lineT = 0 end

-- 玩家输入
function Game:move(dx, dy)
  if self.state ~= 'enemy' then return end
  self.soul.x = clamp(self.soul.x + dx, self.box.x + SOUL_CLAMP, self.box.x + self.box.w - SOUL_CLAMP)
  self.soul.y = clamp(self.soul.y + dy, self.box.y + SOUL_CLAMP, self.box.y + self.box.h - SOUL_CLAMP)
end
function Game:jump()
  if self.state ~= 'enemy' or self.soul.mode ~= 'blue' then return end
  -- 【平台起跳】平台只有 4px 厚、且边移动边判定，起跳那一帧 rooted 状态可能刚好闪断。
  -- 加 0.12s 的 coyote time：离地 0.12s 内仍然算「站在地上」，平台上一定能起跳。
  local coyote = (self.soul.groundT or 99) <= 0.12
  if self.soul.wall then
    -- 【箭头模块】墙模式下「跳跃」= 朝**箭头方向的反方向**冲刺一段（拖到左边 → 向右）。
    -- 距离与普通蓝心跳跃一致：0.5 框高 / JUMP_RISE_T。
    local dw = self.soul.wallDir or 0
    self.soul.dash = { dir = (dw + 2) % 4, t = JUMP_RISE_T, speed = 0.5 * self.box.h / JUMP_RISE_T }
    return
  end
  -- 【用户验收】起跳即脱离甩击状态（World 侧的标记一起清，否则脏标记会把它同步回来）
  self.soul.slammed = false
  if self.world then self.world.heart.slammed = false end
  if self.soul.jumping then return end      -- 空中不再触发：按住不放也不会反复起跳（边沿语义兜底）
  if self.soul.grounded or coyote then
    -- 【方案甲 A-8】沿**逆重力方向**起跳（dir=1 时就是原来的向上跳，行为不变）
    local DX = { [0] = 1, [1] = 0, [2] = -1, [3] = 0 }
    local DY = { [0] = 0, [1] = 1, [2] = 0,  [3] = -1 }
    local jdx = DX[self.soul.dir or 1] or 0
    local jdy = DY[self.soul.dir or 1] or 1
    local jv = JUMP_HEIGHT * self.box.h / JUMP_RISE_T
    self.soul.vx = (self.soul.vx or 0) - jdx * jv
    self.soul.vy = (self.soul.vy or 0) - jdy * jv
    self.soul.grounded = false
    self.soul.jumpBase = self.soul.y          -- 起跳点（算上升高度）
    self.soul.jumping = true
    self.soul.jumpCut = false        -- 本次跳跃还没被「松手」剪断
    self.soul.jumpHeldT = 0
  end
end
function Game:press(k, down) self.keys[k] = down and true or false end
function Game:menuMove(d)
  if self.state ~= 'menu' then return end
  self.menuIndex = (self.menuIndex + d + 4) % 4
end

function Game:itemCount()
  local n = 0
  for _, it in ipairs(self.items) do n = n + it.count end
  return n
end
function Game:itemList()
  local out = {}
  for _, it in ipairs(self.items) do if it.count > 0 then out[#out + 1] = it end end
  return out
end
function Game:subOpen(kind)
  self.sub = kind; self.subIndex = 0; self.state = 'sub'
  self:log('sub_open kind=' .. kind)
end
function Game:subRows()
  if self.sub == 'act' then
    local a = {}
    for _, o in ipairs(ACT_OPTIONS) do a[#a + 1] = o.name end
    return a
  end
  if self.sub == 'item' then
    local b = {}
    for _, it in ipairs(self:itemList()) do b[#b + 1] = it.name end
    return b
  end
  if self.sub == 'mercy' then return { '饶恕', '逃跑' } end
  return {}
end
function Game:subRowNote(idx)
  if self.sub == 'item' then
    local l = self:itemList()
    return l[idx + 1] and ('x' .. l[idx + 1].count) or ''
  end
  if self.sub == 'act' then
    local o = ACT_OPTIONS[idx + 1]
    if not o then return '' end
    return (o.effect == 'wait') and '不结束回合' or '结束回合'
  end
  if self.sub == 'mercy' then return (idx == 0) and '撑过 6 回合后才有效' or '他不让你走' end
  return ''
end
function Game:subDesc()
  local i = self.subIndex
  if self.sub == 'act' then
    local o = ACT_OPTIONS[i + 1]
    return o and o.hint or ''
  end
  if self.sub == 'item' then
    local l = self:itemList()
    return l[i + 1] and l[i + 1].desc or ''
  end
  if self.sub == 'mercy' then
    return (i == 0) and '放过他，结束这场审判' or '转身离开（大概不会成功）'
  end
  return ''
end
function Game:subMove(d)
  if self.state ~= 'sub' then return end
  local n = #self:subRows()
  if n == 0 then return end
  self.subIndex = (self.subIndex + d + n) % n
end
function Game:subBack()
  if self.state ~= 'sub' then return end
  self:log('sub_back kind=' .. tostring(self.sub))
  self.sub = nil; self.state = 'menu'
end

function Game:subConfirm()
  if self.state ~= 'sub' then return end
  local rows = self:subRows()
  if #rows == 0 then self:subBack(); return end
  local i = clamp(self.subIndex, 0, #rows - 1)
  if self.sub == 'act' then
    local o = ACT_OPTIONS[i + 1]
    self:log('act_result id=' .. o.id)
    self:say(o.result)
    if o.effect == 'wait' then self:subBack(); return end
    if o.effect == 'taunt' then self.taunt = self.taunt + 1; self:log('act_taunt level=' .. self.taunt) end
    if o.effect == 'beg' and self.kr > 0 then
      self.kr = 0; self.krT = 0; self:log('kr_cleared by=beg')
    end
    self.sub = nil; self:afterPlayerTurn(); return
  end
  if self.sub == 'item' then
    local it = self:itemList()[i + 1]
    if not it then self:subBack(); return end
    it.count = it.count - 1
    self.hp = math.min(self.maxHP, self.hp + it.heal)
    -- 原作：**治疗会顺带清掉 KR**（业障随治疗消散），这也是原作里「吃一口再打」的战术价值。
    if self.kr > 0 then self.kr = 0; self.krT = 0; self.krActive = false; self:log('kr_cleared by=item') end
    self:log('item_used id=' .. it.id .. ' hp=' .. self.hp .. ' left=' .. self:itemCount())
    self.sub = nil; self:afterPlayerTurn(); return
  end
  if self.sub == 'mercy' then
    if i == 0 then
      if self.final then
        self.sub = nil; self:say('（他放下了手）'); self:finish('spare')
      else
        self:log('mercy_refused'); self:say(LINES.refuse); self.sub = nil; self:afterPlayerTurn()
      end
    else
      self:log('flee_refused'); self:say(LINES.flee); self.sub = nil; self:afterPlayerTurn()
    end
    return
  end
end

function Game:menuChoose(i)
  if self.state ~= 'menu' then return end
  if i ~= nil then self.menuIndex = i end
  local idx = self.menuIndex
  -- B-01：只有「攻击（FIGHT）」推进阶段计数；行动/道具/仁慈不推进（与原版 HitAttempts 同口径）
  if idx == 0 then self.fightCount = (self.fightCount or 0) + 1 end
  if self.interlude then
    if idx == 3 then
      self:log('fail spared_midpoint')
      self:say('（他把手放下了。你没能再站起来。）')
      self:finish('fail', 'spared_midpoint')
      return
    end
    if idx == 1 then self:log('menu_act'); self:subOpen('act'); return end
    if idx == 2 then
      self:log('menu_item')
      if self:itemCount() > 0 then self:subOpen('item')
      -- 【第三轮 N4】空背包时把光标移回「攻击」，避免玩家卡在菜单死循环
      else self:log('item_empty'); self:say('（背包是空的）'); self.menuIndex = 0 end
      return
    end
    self.interlude = false
  end
  if idx == 0 then
    self:log('menu_attack final=' .. (self.final and 1 or 0))
    self.state = 'attack'; self.attackCursor = 0; self.attackDir = 1; self.attackResult = nil
  elseif idx == 1 then
    self:log('menu_act'); self:subOpen('act')
  elseif idx == 2 then
    self:log('menu_item')
    if self:itemCount() > 0 then self:subOpen('item')
    -- 【第三轮 N4】空背包时把光标移回「攻击」，避免玩家卡在菜单死循环
    else self:log('item_empty'); self:say('（背包是空的）'); self.menuIndex = 0 end
  else
    self:log('menu_mercy'); self:subOpen('mercy')
  end
end

function Game:afterPlayerTurn()
  if self.state == 'result' then return end
  -- 【第三轮 N1】中场不再要求「必须 FIGHT」：任何**完成**的行动（检查/挑衅/求饶/吃面包）都算过场，
  -- 直接结束中场继续下一回合 —— 否则只玩 ACT/ITEM 的玩家会被永久困在中场菜单里。
  if self.interlude then
    self.interlude = false
    self:log('interlude_end')
  end
  -- 最后一回合之后没有"下一回合"了：菜单里只剩打 / 饶（结局由 menuChoose 决定）
  if self.final then self.state = 'menu'; return end
  self:startEnemy(self.round + 1)
end

function Game:stopAttack()
  if self.state ~= 'attack' then return end
  local acc = 1 - math.abs(self.attackCursor - 0.5) * 2
  if self.final then
    self.attackResult = 'hit'; self.attackHold = 1.2
    self:log('sans_hit final=1'); self:say('（他没能闪开）')
  else
    self.attackResult = (acc > 0.92) and 'perfect' or 'miss'
    self.attackHold = 1.0
    self:log(string.format('sans_dodge acc=%.2f', acc))
    self.sansDodge = 1
    self:say(LINES.dodge)
  end
end

-- 伤害与 KR
function Game:hurt(kind, karma)
  if self.state ~= 'enemy' or self.invuln > 0 then return false end
  local hpBefore = self.hp
  self.hp = self.hp - 1
  -- 【2026-10-05 修】旧实现把 KR 增量按 `hpBefore-1` 截断：血量掉到 2~3 时 KR 只加 1~2（低到 0），
  -- 玩家看到的紫条几乎不动 → 像「受击判定消失」。现在照原作：**每次命中都照常加满 KR**，
  -- 「不致死」由 updateKR 的 `hp > 1` 下限保证（KR 永远烧不到 0 血）。
  -- 原版：骨头 +6、龙骨炮 +10；【差距文档 V-02/附录B】**KR 上限 40**
  self.kr = math.min(KR_MAX, self.kr + (karma or KR_PER_HIT))
  self.krActive = self.kr > 0
  self.krFloorLogged = false
  self.invuln = self.tune.invuln          -- 原作没有无敌帧 -> 原作档只有 0.15s
  self.flash = 0.12
  if kind == 'blue' then self:log('hit_blue hp=' .. self.hp .. ' kr=' .. self.kr)
  elseif kind == 'orange' then self:log('hit_orange hp=' .. self.hp .. ' kr=' .. self.kr)
  else self:log('hit hp=' .. self.hp .. ' kr=' .. self.kr) end
  if self.hp <= 0 then self.hp = 0; self:finish('fail') end
  return true
end
function Game:debugHurt(kind) self.invuln = 0; return self:hurt(kind or 'hit') end

function Game:updateKR(dt)
  if self.kr <= 0 then self.kr = 0; return end
  self.krT = (self.krT or 0) + dt
  while self.krT >= KR_TICK and self.kr > 0 do
    self.krT = self.krT - KR_TICK
    self.kr = self.kr - 1
    if self.hp > 1 then
      self.hp = self.hp - 1
    elseif not self.krFloorLogged then
      self.krFloorLogged = true; self:log('kr_floor hp=' .. self.hp)
    end
    if self.kr <= 0 then
      self.kr = 0; self.krActive = false; self:log('kr_done hp=' .. self.hp .. ' kr=0')
    end
  end
end

-- 弹幕生成
function Game:buildPlatforms()
  local b, H = self.box, self.box.h
  self.platforms = {
    { x = b.x + 0.06 * b.w, y = b.y + H - 48,  w = 0.30 * b.w, h = 12 },
    { x = b.x + 0.40 * b.w, y = b.y + H - 120, w = 0.30 * b.w, h = 12 },
    { x = b.x + 0.12 * b.w, y = b.y + H - 192, w = 0.60 * b.w, h = 12 },
  }
end

function Game:spawnFloor(peekSec)
  local w = ensureWorld(self)
  local z = w.zone
  local b = self.box
  local laneW = 60
  local lanes = math.max(4, math.floor(b.w / laneW))
  laneW = b.w / lanes
  local peek = peekSec
  if peek == nil then peek = PEEK end
  local safe = {}
  local function addSafe(L) safe[#safe + 1] = L end
  if (self.round == 1 or self.round == 0) and self.wave == 0 and not self.testAimWave1 then
    addSafe(math.floor(lanes / 2))                  -- 第 1 回合第 1 波：出生点必留安全位
  elseif self.testAimWave1 and self.wave == 0 then
    local cur = math.floor((self.soul.x - b.x) / laneW)
    local a, bb = clamp(cur - 1, 0, lanes - 1), clamp(cur + 1, 0, lanes - 1)
    if a == bb then addSafe(bb) else addSafe(a); addSafe(bb) end
  else
    local n = 1 + math.floor(self.rng() * 2)
    for _ = 1, n do addSafe(math.floor(self.rng() * lanes)) end
  end
  local wave = self.wave + 1
  self.wave = wave
  for L = 0, lanes - 1 do
    local isSafe = false
    for _, s in ipairs(safe) do if s == L then isSafe = true end end
    if not isSafe then
      w.bones[#w.bones + 1] = {
        kind = 'floor', wave = wave, custom = true, abs = true,
        x = z.l + laneW * (L + 0.5), w = laneW - 6,
        y = z.b, targetH = z.b - z.t, h = TIP_H, t = 0,
        phase = 'peek', peekDur = peek, lethal = false, color = 'white',
      }
    end
  end
  -- 致命窗口不重叠：下一波要等这一波的"保持"结束
  self.floorLock = peek + EXTEND + HOLD
  self:log('wave_peek wave=' .. wave .. ' lanes=' .. (lanes - #safe) .. ' hp=' .. self.hp)
end

function Game:spawnWall(gapW)
  local w = ensureWorld(self)
  local z = w.zone
  if #self.walls > 0 then return end                    -- 反饱和：同一时刻只有一道屏障
  local lanes = 9
  local laneW = (z.r - z.l) / lanes
  local gapStart
  if self.round == 2 and not self.firstBarrierDone and not self.testAimWave1 then
    gapStart = 3                                        -- 第 1 道缺口居中（上手保证）
  else
    gapStart = math.floor(self.rng() * (lanes - gapW + 1))
  end
  if self.round == 2 then self.firstBarrierDone = true end
  self.walls[#self.walls + 1] = { t = 0, phase = 'warn', lanes = lanes, laneW = laneW,
                                  gapStart = gapStart, gapW = gapW, h = 0 }
end

function Game:spawnBlue(fromBottom, color)
  local w = ensureWorld(self)
  local z = w.zone                            -- 脚本坐标
  w.bones[#w.bones + 1] = {
    kind = 'blue', custom = true, x = z.l, w = z.r - z.l, h = 22,
    y = fromBottom and (z.b + 24) or (z.t - 24),
    vy = (fromBottom and -150 or 150) * self.tune.speed * self.spd,
    lethal = true, color = color or 'blue', passed = false,
  }
end

function Game:spawnWhiteSlide()
  local w = ensureWorld(self)
  local z = w.zone
  local fromLeft = self.rng() < 0.5
  w.bones[#w.bones + 1] = {
    kind = 'slide', custom = true,
    x = fromLeft and (z.l - 12) or (z.r + 12), w = 11, h = 45,
    y = z.t + 20 + self.rng() * ((z.b - z.t) - 65),
    vx = (fromLeft and 210 or -210) * self.tune.speed * self.spd,
    lethal = true, color = 'white',
  }
end

function Game:spawnBlaster(count)
  local w = ensureWorld(self)
  local b = self.box                            -- 框内相对坐标
  local z = w.zone
  local sx = (z.r - z.l) / b.w
  local sy = (z.b - z.t) / b.h
  for _ = 1, count do
    local vertical = self.rng() < 0.5
    local pos = vertical and (b.x + b.w * (0.2 + 0.6 * self.rng()))
                       or (b.y + b.h * (0.2 + 0.6 * self.rng()))
    -- 回合 0（不意打ち）把光束放到离灵魂最远的一侧
    if self.round == 0 then
      local avoid = vertical and self.soul.x or self.soul.y
      local lo = (vertical and b.x or b.y) + 30
      local hi = (vertical and (b.x + b.w) or (b.y + b.h)) - 30
      pos = ((avoid - lo) > (hi - avoid)) and lo or hi
    end
    local side = self.rng() < 0.5 and -1 or 1
    -- 渲染停靠点/朝向：竖炮停在框的上/下方朝框内打，横炮停在框左/右朝框内打。
    -- 修复前这里恒为 x=z.l, y=z.t（画在 zone 左上角），和 axis/pos 表达的光束带对不上。
    local rx, ry, rang
    if vertical then
      rx, ry = pos, (side < 0) and (b.y - 46) or (b.y + b.h + 46)
      rang = (side < 0) and 90 or 270
    else
      rx, ry = (side < 0) and (b.x - 46) or (b.x + b.w + 46), pos
      rang = (side < 0) and 0 or 180
    end
    w.blasters[#w.blasters + 1] = {
      axis = vertical and 'v' or 'h',
      pos = z.l + (pos - b.x) * sx,
      side = side,
      t = 0, state = 'charge', warn = 0.7, blast = 0.35, band = 92 * (vertical and sx or sy),
      x = z.l + (rx - b.x) * sx, y = z.t + (ry - b.y) * sy,
      ang = rang, size = 1, scale = BLASTER_SCALE[2],
      w = z.r - z.l, h = z.b - z.t,
    }
  end
end

function Game:spawnFloorBoneBlue()
  local w = ensureWorld(self)
  local z = w.zone
  local fromLeft = self.rng() < 0.5
  w.bones[#w.bones + 1] = {
    kind = 'slide', custom = true,
    x = fromLeft and (z.l - 12) or (z.r + 12), w = 11, h = 24,
    y = z.b - 24,
    vx = (fromLeft and 230 or -230) * self.tune.speed * self.spd,
    lethal = true, color = 'white',
  }
end

-- ---------------------------------------------------------------- 更新
function Game:update(dt)
  if self.state == 'title' or self.state == 'result' then return end
  self.flash = math.max(0, self.flash - dt)
  -- 打字机：lineShown 的单位是**字符**（不是字节），速度 = 每 0.028s 一个字
  local lineChars = utf8len(self.line)
  if self.lineShown < lineChars then
    self.lineT = self.lineT + dt
    self.lineShown = math.min(lineChars, math.floor(self.lineT / 0.028))
  end
  self.sansDodge = math.max(0, self.sansDodge - dt * 2.2)

  if self.state == 'attack' then
    -- 原作里 KR 在整个玩家回合（含攻击条）持续燃烧；旧实现只在 enemy/menu/sub 掉，攻击条那几秒是
    -- 白送的喘息，和原作不一致。
    self:updateKR(dt)
    self.attackCursor = self.attackCursor + self.attackDir * dt * 1.2
    if self.attackCursor > 1 then self.attackCursor = 1; self.attackDir = -1 end
    if self.attackCursor < 0 then self.attackCursor = 0; self.attackDir = 1 end
    if self.attackResult then
      self.attackHold = self.attackHold - dt
      if self.attackHold <= 0 then
        if self.final then
          -- 最后一回合之后：这一击就是结局（原作里他这时候已经躲不开了）
          self:finish('kill')
        else
          self.attackResult = nil
          self:startEnemy(self.round + 1)
        end
      end
    end
    return
  end
  if self.state == 'menu' or self.state == 'sub' then self:updateKR(dt); return end
  if self.state ~= 'enemy' then return end

  self:updateKR(dt)
  if self.state ~= 'enemy' then return end

  -- 灵魂移动
  local k = self.keys
  local vx, vy = 0, 0
  if k.left then vx = vx - 1 end
  if k.right then vx = vx + 1 end
  if k.up then vy = vy - 1 end
  if k.down then vy = vy + 1 end
  if vx ~= 0 or vy ~= 0 then
    local len = math.sqrt(vx * vx + vy * vy)
    if len == 0 then len = 1 end
    -- V-03：原版按住「取消」键时移速减半（150 → 75）
    local spd = self.keys and self.keys.cancel and SOUL_SPEED_SLOW or SOUL_SPEED
    self.soul.x = self.soul.x + vx / len * spd * dt
    self.soul.y = self.soul.y + vy / len * spd * dt
  end
  -- 【G4】冲量（SansSlam）：三种模式共用，位移叠加在位置上，0.55s 内线性衰减
  if self.soul.push then
    local P = self.soul.push
    self.soul.x = self.soul.x + (P.vx or 0) * dt
    self.soul.y = self.soul.y + (P.vy or 0) * dt
    P.t = P.t - dt
    if P.t <= 0 then self.soul.push = nil end
  end
  local d = roundDef(self, self.round)
  if self.soul.wall then
    -- 【箭头模块 · 不可直接套用普通蓝心物理规则】
    --   1) 不吃重力、不悬停 —— 就是红魂那样的四向自由移动（走下面 `else` 分支那套）；
    --   2) 「跳跃」= 沿 soul.dash 朝箭头反方向冲一段（Game:jump 设置）；
    --   3) SansSlam 的推速真的积分进位移并快速衰减 —— 把灵魂「拖」到箭头那条框边。
    local dd = self.soul.dash
    if dd and dd.t > 0 then
      local sp = dd.speed * dt
      if dd.dir == 0 then self.soul.x = self.soul.x + sp
      elseif dd.dir == 2 then self.soul.x = self.soul.x - sp
      elseif dd.dir == 1 then self.soul.y = self.soul.y + sp
      else self.soul.y = self.soul.y - sp end
      dd.t = dd.t - dt
      if dd.t <= 0 then self.soul.dash = nil end
    end
    local svx, svy = self.soul.vx or 0, self.soul.vy or 0
    if svx ~= 0 or svy ~= 0 then
      self.soul.x = self.soul.x + svx * dt
      self.soul.y = self.soul.y + svy * dt
      local k = math.max(0, 1 - 6 * dt)
      self.soul.vx, self.soul.vy = svx * k, svy * k
      if math.abs(self.soul.vx) < 2 then self.soul.vx = 0 end
      if math.abs(self.soul.vy) < 2 then self.soul.vy = 0 end
    end
  end
  if self.soul.mode == 'blue' and not self.soul.wall then
    -- 【方案甲 A-5/A-6】被甩（slammed）：沿 dir 方向重力加速 → 撞墙结算；
    -- **不走下面那套跳跃模型**（原版 CustomMovement）。dir 默认 1（南）= 与旧行为一致。
    if self.soul.slammed then
      -- 【用户验收】被甩后必须还能跳：1.2s 超时自动解除；落到平台上也算落地
      self.soul.slamT = (self.soul.slamT or 0) + dt
      if self.soul.slamT > 1.2 then self.soul.slammed = false; if self.world then self.world.heart.slammed = false end end
      local DX = { [0]=1, [1]=0, [2]=-1, [3]=0 }
      local DY = { [0]=0, [1]=1, [2]=0,  [3]=-1 }
      local gx = DX[self.soul.dir or 1] or 0
      local gy = DY[self.soul.dir or 1] or 1
      local mf = self.soul.maxFall
      if mf == nil or mf == 0 then mf = 750 end
      local va = (self.soul.vx or 0) * gx + (self.soul.vy or 0) * gy
      local na = va + GRAVITY * dt
      if na > mf then na = mf end
      local dlt = na - va
      self.soul.vx = (self.soul.vx or 0) + gx * dlt
      self.soul.vy = (self.soul.vy or 0) + gy * dlt
      self.soul.x = self.soul.x + self.soul.vx * dt
      self.soul.y = self.soul.y + self.soul.vy * dt
      local b = self.box
      local hitL = self.soul.x <= b.x + SOUL_CLAMP
      local hitR = self.soul.x >= b.x + b.w - SOUL_CLAMP
      local hitT = self.soul.y <= b.y + SOUL_CLAMP
      local hitB = self.soul.y >= b.y + b.h - SOUL_CLAMP
      if hitL or hitR or hitT or hitB then
        self.soul.slammed = false
        local v = math.max(math.abs(self.soul.vx or 0), math.abs(self.soul.vy or 0))
        if v > 330 then                                  -- 原版阈值
          self:sansShake(math.floor(v / 90))             -- 原版 floor(|v|/30/3)
          if self.slamDamage and self.hp > 1 then        -- 原版：直接扣、不走无敌帧、不加 KR
            self.hp = self.hp - 1
            self:log('slam_damage hp=' .. self.hp)
          end
        end
        if hitL then self.soul.x = b.x + SOUL_CLAMP elseif hitR then self.soul.x = b.x + b.w - SOUL_CLAMP end
        if hitT then self.soul.y = b.y + SOUL_CLAMP elseif hitB then self.soul.y = b.y + b.h - SOUL_CLAMP end
        if hitL or hitR then self.soul.vx = 0 end
        if hitT or hitB then self.soul.vy = 0 end
        self.soul.grounded = true
        if self.world then self.world.heart.slammed = false end
      end
      if self.soul.grounded then
        self.soul.jumping = false; self.soul.jumpCut = false; self.soul.jumpBase = nil; self.soul.jumpBaseBoxY = nil
        self.soul.jumpDone = false; self.soul.jumpHeldT = 0
      end
      -- 平台落地 → 结束甩击（否则 slammed 永真、永远跳不起来）
      for _, pf in ipairs(self.platforms or {}) do
        if (self.soul.vy or 0) > 0 and (self.prevY + SOUL_CLAMP) <= (pf.y + 2)
           and (self.soul.y + SOUL_CLAMP) >= pf.y
           and self.soul.x >= (pf.x - 4) and self.soul.x <= (pf.x + pf.w + 4) then
          self.soul.y = pf.y - SOUL_CLAMP; self.soul.vy = 0; self.soul.slammed = false; self.soul.grounded = true
          if self.world then self.world.heart.slammed = false end
        end
      end
    else
    -- 【蓝心跳跃（用户口径 2026-10-05 第六轮）】
    --   * 按住 → **匀速**上升，速度 = 0.6×框高 / 0.25s（**0.25s 到 3/5 框高**）；
    --   * **上升窗口只有 0.25s**：按住超过 0.25s 也停，然后**自然下落**（不再悬停/浮空）；
    --   * 松开 → **立刻停止上升**，等速下降（速度 = 0.5×框高 / 0.75s）；
    --   * 松手后这一次跳跃被「剪断」（jumpCut）→ **下降途中再按跳跃键不会重新上升**（不能二段跳）；
    --   * 另有「起跳点上方 3/5 框高」和战斗框上沿两道兜底。
    local riseSpeed = JUMP_HEIGHT * self.box.h / JUMP_RISE_T
    local fallSpeed = 0.5 * self.box.h / JUMP_FALL_T   -- 下落速率不变（0.5 框高 / 0.75s）
    local maxRise = JUMP_HEIGHT * self.box.h
    if not self.jumpHeld then self.soul.jumpCut = true end
    local risen = (self.soul.jumpBase or self.soul.y) - self.soul.y
    local heldT = self.soul.jumpHeldT or 0
    if self.soul.jumping and self.jumpHeld and not self.soul.jumpCut
       and heldT < JUMP_RISE_T - 1e-9 and risen < maxRise - 0.01 then
      self.soul.vy = -riseSpeed
      self.soul.jumpHeldT = heldT + dt
    else
      self.soul.vy = fallSpeed                   -- 超时 / 松手 / 已剪断：等速下降（自然下落）
    end
    -- HeartMaxFallSpeed：脚本可再压一档（原作「砸击」的三档速度；负值 = 反向重力走廊）
    local mf = self.soul.maxFall
    if mf and self.soul.vy > mf then self.soul.vy = mf end
    self.soul.y = self.soul.y + self.soul.vy * dt
    self.soul.grounded = false
    local ceilY = self.box.y + SOUL_CLAMP
    local floorY = self.box.y + self.box.h - SOUL_CLAMP
    if self.soul.y <= ceilY then
      self.soul.y = ceilY; self.soul.vy = 0        -- 顶在框沿：按住也不越界
    end
    if self.soul.y >= floorY then
      self.soul.y = floorY; self.soul.vy = 0; self.soul.grounded = true
    end
    for _, pf in ipairs(self.platforms or {}) do
      if self.soul.vy > 0 and (self.prevY + SOUL_CLAMP) <= (pf.y + 2)
         and (self.soul.y + SOUL_CLAMP) >= pf.y
         and self.soul.x >= (pf.x - 4) and self.soul.x <= (pf.x + pf.w + 4) then
        self.soul.y = pf.y - SOUL_CLAMP; self.soul.vy = 0; self.soul.grounded = true
      end
    end
    if self.soul.grounded then
      self.soul.jumping = false; self.soul.jumpCut = false; self.soul.jumpBase = nil; self.soul.jumpBaseBoxY = nil
      self.soul.jumpDone = false; self.soul.jumpHeldT = 0
    end   -- 落地重置变高跳
    end   -- /【A-5】slammed 分支
  else
    -- 红魂默认不吃重力；但脚本给过 HeartMaxFallSpeed（非 0）就吃 ——
    -- 原作最终回合阶段②的「反向重力走廊」正是 HeartMaxFallSpeed -300。
    local mf = self.soul.maxFall
    if mf then
      local g = d.p.gravity or GRAVITY
      self.soul.vy = self.soul.vy + g * dt
      if self.soul.vy > mf then self.soul.vy = mf end
      self.soul.y = self.soul.y + self.soul.vy * dt
      local floorY = self.box.y + self.box.h - SOUL_CLAMP
      if self.soul.y >= floorY then self.soul.y = floorY; self.soul.vy = 0 end
    end
    self.soul.y = clamp(self.soul.y, self.box.y + SOUL_CLAMP, self.box.y + self.box.h - SOUL_CLAMP)
  end
  self.soul.x = clamp(self.soul.x, self.box.x + SOUL_CLAMP, self.box.x + self.box.w - SOUL_CLAMP)
  -- 平台：轴对齐矩形；掉到顶面就站住（vy 归零），从下面/侧面顶到就只被挡住（不伤害）
  --   碰撞源 = 攻击脚本的 world.platforms（Platform/PlatformRepeat）+ 内置 R6 平台
  local prevSoulY = self.prevY
  if prevSoulY == nil then prevSoulY = self.soul.y end
  do
    local lists = { { list = self.platforms or {}, ox = 0, oy = 0 } }
    if self.world and self.world.platforms then
      lists[#lists + 1] = { list = self.world.platforms, ox = BOX_OFF_X, oy = BOX_OFF_Y }
    end
    for _, spec in ipairs(lists) do
      for _, pf in ipairs(spec.list) do
        local px, py = pf.x - spec.ox, pf.y - spec.oy
        local pw, ph = pf.w or 0, pf.h or 4
        if self.soul.x + SOUL_CLAMP > px and self.soul.x - SOUL_CLAMP < px + pw
           and self.soul.y + SOUL_CLAMP > py and self.soul.y - SOUL_CLAMP < py + ph then
          local landed = ((self.soul.vy or 0) >= 0)
                         and (prevSoulY + SOUL_CLAMP <= py + 2)
                         and (self.soul.y + SOUL_CLAMP >= py)
          if landed then
            -- 站到顶面 + **随平台一起走**（原作：站上去就被平台带着，不用一直按方向键）
            self.soul.y = py - SOUL_CLAMP
            self.soul.vy = 0
            self.soul.grounded = true
            -- 【用户验收：移动平台上必须能起跳】差距文档 M-02 说原版这条「平台带走心」是 disabled，
            -- 但实测照文档关掉后，120~150px/s 的平台会在 0.1s 内从脚下溜走 → grounded 立刻变 false → 根本跳不起来。
            -- 按用户口径**恢复平台带走**（站上去就被平台平移），这样平台上随时可以起跳。
            local pvx = pf.vx or ((pf.dir == 0 and (pf.speed or 0)) or (pf.dir == 2 and -(pf.speed or 0)) or 0)
            if pvx ~= 0 then
              self.soul.x = self.soul.x + pvx * dt
              self.soul.x = clamp(self.soul.x, self.box.x + SOUL_CLAMP, self.box.x + self.box.w - SOUL_CLAMP)
            end
          else
            -- 【差距文档 H-06】原版 `HeartCheckSolid` 里 Angle=0/Angle=180（平台**侧面**）两个分支是
            -- `disabled="1"` —— 心从侧面撞平台不会发生实体碰撞，只有上/下（90/270）有效。
            -- 所以这里**不做**「解算到最近一条边」（那是把侧面也当实体），直接放过。
            local _ = pf
            local dyTop = math.abs((self.soul.y + SOUL_CLAMP) - py)
            local dyBot = math.abs((self.soul.y - SOUL_CLAMP) - (py + ph))
            local dxL = math.abs((self.soul.x + SOUL_CLAMP) - px)
            local dxR = math.abs((self.soul.x - SOUL_CLAMP) - (px + pw))
            -- （H-06）侧面不做实体解算；dyTop/dyBot 仅保留给平台顶面吸附分支使用
            local _m = math.min(dyTop, dyBot, dxL, dxR)
          end
        end
      end
    end
  end
  self.soul.x = clamp(self.soul.x, self.box.x + SOUL_CLAMP, self.box.x + self.box.w - SOUL_CLAMP)
  self.soul.y = clamp(self.soul.y, self.box.y + SOUL_CLAMP, self.box.y + self.box.h - SOUL_CLAMP)
  local dx, dy = self.soul.x - self.prevX, self.soul.y - self.prevY
  -- moved：>1px/帧 才算「动了」（原 0.7 会把贴地/到顶时的亚像素抖动误判成移动，蓝骨冤枉扣血）
  -- 【差距文档第二轮 G9】原来用「本帧位移 >1px」判 moved —— 会被**重力下落 / 平台带走 / SansSlam 冲量**
  -- 污染（玩家没按方向键也会被判成「移动」，蓝骨冤枉扣血）。改成看**输入与冲量**：
  --   按住任意方向键，或正被 SansSlam 冲量推着走 —— 才算「移动」。
  local moved = (self.keys.left or self.keys.right or self.keys.up or self.keys.down) and true or false
  if self.soul.push then moved = true end

  -- 攻击脚本世界
  if self.world then
    local w = self.world
    w:update(dt)
    self.box = zoneOf(w)                    -- 框跟随脚本 zone（变形期间逐帧更新）
    -- 双坐标同步：脚本世界的心只用于 GetHeartPos / SansSlam 演出，
    -- 实际判定一律用 game.soul；这里把 game.soul 的脚本坐标写回去，避免两个"灵魂"跑偏。
    -- 【2026-10-05 修】脚本的 HeartTeleport / HeartMode / HeartMaxFallSpeed / SansSlam 才是权威：
    -- 这一帧脚本动过心，就把它**采纳**进 game.soul（旧实现只做 soul→heart 单向镜像，
    -- 于是脚本的 HeartMode 1（蓝魂）和 HeartTeleport 全被抹掉 —— 蓝魂关卡全变红魂、
    -- 位置也被拉回框中心，玩家看到的就是「该有重力的蓝心却浮着不动」）。
    if w.heartPosDirty then
      local hx, hy = (w.heart.x or 0) - BOX_OFF_X, (w.heart.y or 0) - BOX_OFF_Y
      self.soul.x, self.soul.y = hx, hy
      self.soul.vy = w.heart.vy or 0
      self.soul.vx = w.heart.vx or 0
      -- 瞬移后**立刻钳回框内**：soul 落在框外时碰撞会被 outside 守卫整段跳过，
      -- 表现就是「蓝心没有碰撞箱」（脚本的 HeartTeleport 目标点不一定在当前 zone 内）。
      self.soul.x = clamp(self.soul.x, self.box.x + SOUL_CLAMP, self.box.x + self.box.w - SOUL_CLAMP)
      self.soul.y = clamp(self.soul.y, self.box.y + SOUL_CLAMP, self.box.y + self.box.h - SOUL_CLAMP)
      self.prevX, self.prevY = self.soul.x, self.soul.y   -- 别把「瞬移」当成移动（否则蓝骨会误判）
      w.heartPosDirty = false
    end
    if w.heartVelDirty then                  -- 【A-4】SansSlam：速度 + 标记交给蓝魂物理
      self.soul.vy = w.heart.vy or 0
      self.soul.vx = w.heart.vx or 0
      self.soul.dir = w.heart.dir or self.soul.dir or 1
      self.soul.slammed = w.heart.slammed and true or false
      self.soul.push = nil
      -- 【G4】关键修复：`soul.vx/vy` 在红魂里不被积分、在蓝魂里每帧被跳跃模型覆盖 ——
      -- 所以 SansSlam 原来等于没写（探针：水平位移 0.00）。改成**独立冲量** `soul.push`，
      -- 在三种模式（红 / 普通蓝 / 贴墙）下都统一把位移加到位置上，并按时间衰减。
      self.soul.push = { vx = w.heart.vx or 0, vy = w.heart.vy or 0, t = 0.55 }
      w.heartVelDirty = false
    end
    -- 箭头模块：soul.wall 跟随脚本，方向跟随 SansBody（箭头）
    self.soul.wall = w.heart.wall and true or nil
    if self.soul.wall then
      local B = w.sans and w.sans.body
      self.soul.wallDir = (B == 'HandRight' and 0) or (B == 'HandDown' and 1)
                          or (B == 'HandLeft' and 2) or (B == 'HandUp' and 3) or self.soul.wallDir
    end
    if w.heartModeDirty then
      self.soul.mode = (w.heart.mode == 1) and 'blue' or 'red'
      self.soul.maxFall = ((w.heart.maxFall ~= nil) and w.heart.maxFall ~= 0) and w.heart.maxFall or nil
      w.heartModeDirty = false
    end
    w.heart.x = self.soul.x + BOX_OFF_X
    w.heart.y = self.soul.y + BOX_OFF_Y
    w.heart.mode = (self.soul.mode == 'blue') and 1 or 0
    if w.ended then self.world = nil; self.sine = {} end
  end

  -- 回合计时与生成
  self.enemyT = self.enemyT + dt
  self.spawnT = self.spawnT - dt
  if self.testHitsAt and #self.testHitsAt > 0 then
    self.hitT = (self.hitT or 0) + dt
    while #self.testHitsAt > 0 and self.hitT >= self.testHitsAt[1] do
      table.remove(self.testHitsAt, 1)
      self:hurt('hit')                       -- 不重置无敌帧：让测试走真实的 i-frame 判定
      if self.state ~= 'enemy' then return end
    end
  end
  if self.floorLock > 0 then self.floorLock = self.floorLock - dt end
  -- 「脚本接管这一回合」：挂上攻击脚本的回合，内置生成器一律让位 —— 它是**没有脚本时的兜底**
  -- （见 startEnemy 的注释"可选；没有脚本时用内置模式生成"）。
  -- 为什么必须让位：回合时长已按脚本时长延长（startEnemy 的 `World:scriptLength()` →
  -- enemyDur），2.8s 的 SURPRISE 波次节奏会在 8.93s 的脚本演出里插进 ~6 波地面骨，
  -- 玩家看到的"初见杀"就不再是原版那一条（骨刺 → 正弦骨 → 四段龙骨炮）。
  -- 判据用 `world.script`：内置回合的 world 是 ensureWorld 惰性造的"只有框"的 world（无 script），
  -- 不能用 `self.world ~= nil` 判，否则内置生成器造完第一波就把自己关了。
  -- 例外：最终回合（self.final）是"三段复用现成脚本 + 内置生成器混跑"的**已知偏差**
  -- （records/lua-port.md §已知差异），这一轮保持原样，避免改变最终回合节奏。
  -- 注意：这条守卫只关"内置生成器"，**不影响**本回合时长 —— enemyDur 仍由脚本时长决定。
  local scriptOwnsRound = (self.world ~= nil and self.world.script ~= nil) and not self.final
  if self.spawnT <= 0 and not self.testNoSpawn and not scriptOwnsRound then
    if d.pattern == 'bone_floor' or d.pattern == 'mixed' or d.pattern == 'surprise' then
      if self.floorLock <= 0 then
        self:spawnFloor(d.p.peek); self.spawnT = self:it(d.p.interval)
      else
        self.spawnT = 0                      -- 等这一波的致命窗口结束
      end
    elseif d.pattern == 'bone_wall' then
      self:spawnWall(d.p.gap); self.spawnT = self:it(d.p.interval)
    elseif d.pattern == 'blue_bone' then
      self.colorFlip = not self.colorFlip     -- 蓝/橙交替
      self:spawnBlue(self.rng() < 0.5, self.colorFlip and 'blue' or 'orange')
      self.spawnT = self:it(d.p.blue)
    elseif d.pattern == 'blaster' then
      self:spawnBlaster(self.enemyT > self:it(4) and 2 or 1)
      self.spawnT = self:it(d.p.interval)
    elseif d.pattern == 'blue_soul' then
      self:spawnFloorBoneBlue(); self.spawnT = self:it(d.p.boneInterval)
    end
  end
  -- 这两个"旁路"生成器（白骨滑行 / 骨墙）吃的是同一个规则：脚本接管的回合里也让位。
  -- 今天对回合 0 是空操作（它的 pattern 是 surprise），但规则要一致，否则以后给别的回合挂脚本
  -- 又会漏出内置弹幕。
  if d.pattern == 'blue_bone' and not scriptOwnsRound then
    self.whiteT = (self.whiteT or 0) - dt
    if self.whiteT <= 0 then self:spawnWhiteSlide(); self.whiteT = self:it(d.p.white) end
  end
  if d.pattern == 'mixed' and not scriptOwnsRound then
    self.wallT = self.wallT - dt
    if self.wallT <= 0 then self:spawnWall(4); self.wallT = self:it(d.p.wallInterval) end
  end
  -- 骨头更新（地板骨四段生命 / 蓝骨 / 滑行骨 / 攻击脚本骨头）
  local aliveWaves = {}
  local w2 = self.world
  if w2 then
    local i = #w2.bones
    while i >= 1 do
      local bn = w2.bones[i]
      bn.t = (bn.t or 0) + dt
      local kill = false
      if bn.stab or bn.arrowbone then
        if bn.arrowbone then
          -- 箭头模块的骨头：伸出(out) + 停留(stay) 两个阶段都伤人（与渲染里的 extend/hold 一致）
          bn.lethal = ((bn.phase == 'out' or bn.phase == 'stay') and (bn.cur or 0) > 0)
        elseif bn.phase == 'out' and (bn.cur or 0) > 0 then bn.lethal = true else bn.lethal = false end
      elseif bn.kind == 'floor' then
        if bn.phase == 'peek' then
          bn.h = TIP_H; bn.lethal = false
          if bn.t >= (bn.peekDur or PEEK) then bn.phase = 'extend'; bn.t = 0 end
        elseif bn.phase == 'extend' then
          bn.h = TIP_H + (bn.targetH - TIP_H) * math.min(1, bn.t / EXTEND)
          bn.lethal = bn.h > LETHAL_H
          if bn.t >= EXTEND then bn.phase = 'hold'; bn.t = 0; bn.h = bn.targetH end
        elseif bn.phase == 'hold' then
          bn.h = bn.targetH; bn.lethal = true
          if bn.t >= HOLD then bn.phase = 'retract'; bn.t = 0 end
        else
          bn.h = bn.targetH * math.max(0, 1 - bn.t / RETRACT)
          bn.lethal = bn.h > LETHAL_H
          if bn.t >= RETRACT then kill = true end
        end
      elseif bn.kind == 'blue' then
        bn.y = bn.y + (bn.vy or 0) * dt
        if (bn.y + bn.h) < (w2.zone.t - 60) or bn.y > (w2.zone.b + 60) then
          if not bn.passed and not bn.hitDone then
            self:log('blue_pass_clean hp=' .. self.hp)
          end
          kill = true
        end
      elseif bn.kind == 'slide' then
        bn.x = bn.x + (bn.vx or 0) * dt
        if (bn.x + bn.w) < (w2.zone.l - 60) or bn.x > (w2.zone.r + 60) then kill = true end
      elseif bn.kind == 'sine' then
        bn.x = bn.x + (bn.vx or 0) * dt
        if bn.x > VW + 400 or bn.x < -400 then kill = true end
      else
        kill = false
      end
      if kill then table.remove(w2.bones, i) end
      if bn.wave ~= nil and w2.bones[i] == bn then aliveWaves[bn.wave] = true end
      i = i - 1
    end
    if w2.ended then self.world = nil; self.sine = {} end
  end
  for wv in pairs(self.wavesAlive) do
    if not aliveWaves[wv] then
      self:log('wave_clear wave=' .. wv .. ' hp=' .. self.hp)
      self.wavesAlive[wv] = nil
    end
  end
  for wv in pairs(aliveWaves) do self.wavesAlive[wv] = true end

  -- 骨墙（原地升降）
  local i = #self.walls
  while i >= 1 do
    local wl = self.walls[i]
    wl.t = wl.t + dt
    if wl.phase == 'warn' then
      if wl.t >= self.warnWall then wl.phase = 'rise'; wl.t = 0 end
    elseif wl.phase == 'rise' then
      wl.h = self.box.h * math.min(1, wl.t / 0.25)
      if wl.t >= 0.25 then wl.phase = 'hold'; wl.t = 0; wl.h = self.box.h end
    elseif wl.phase == 'hold' then
      if wl.t >= 0.55 then wl.phase = 'retract'; wl.t = 0 end
    else
      wl.h = self.box.h * math.max(0, 1 - wl.t / 0.25)
      if wl.t >= 0.25 then table.remove(self.walls, i) end
    end
    i = i - 1
  end

  -- 冲击波（内置模式）
  if w2 then
    for _, bl in ipairs(w2.blasters) do
      bl.t = bl.t + dt
      if bl.state == 'charge' and bl.t >= self.warn then
        bl.state = 'fire'; bl.t = 0
      elseif bl.state == 'fire' and bl.t >= 0.35 then
        bl.state = 'fade'; bl.t = 0
      elseif bl.state == 'fade' and bl.t >= 0.3 then
        bl.dead = true
      end
    end
    local j = #w2.blasters
    while j >= 1 do
      if w2.blasters[j].dead then table.remove(w2.blasters, j) end
      j = j - 1
    end
  end

  -- 碰撞（world 实体在脚本坐标；soul/walls 在框内相对坐标；统一换算到脚本坐标比对）
  if w2 then
    local SX, SY = self.soul.x + BOX_OFF_X, self.soul.y + BOX_OFF_Y
    -- 灵魂跑到框外 = 内部不一致（帧混用/框没跟随 zone）。此时不要判伤害：
    -- 否则会变成"隔空挨打"，把真正的坐标 bug 伪装成难度问题。宁可漏一帧伤害。
    -- 【差距文档第二轮 G10】守卫原来给 ±1px 容差、且在框外就整段跳过判定 → 边界处等于**整帧无敌**。
    -- 收紧到 ±0.25px（真正的坐标错位）并把灵魂**钳回框内**，判定照跑。
    if self.soul.x < self.box.x then self.soul.x = self.box.x end
    if self.soul.y < self.box.y then self.soul.y = self.box.y end
    if self.soul.x > self.box.x + self.box.w then self.soul.x = self.box.x + self.box.w end
    if self.soul.y > self.box.y + self.box.h then self.soul.y = self.box.y + self.box.h end
    local outside = (self.soul.x < self.box.x - 0.25) or (self.soul.x > self.box.x + self.box.w + 0.25)
                    or (self.soul.y < self.box.y - 0.25) or (self.soul.y > self.box.y + self.box.h + 0.25)
    if outside then
      if not self._outsideLogged then
        self._outsideLogged = true
        self:log('soul_outside_box soul=' .. math.floor(self.soul.x) .. ',' .. math.floor(self.soul.y) ..
                 ' box=' .. math.floor(self.box.x) .. ',' .. math.floor(self.box.y) ..
                 ',' .. math.floor(self.box.w) .. ',' .. math.floor(self.box.h))
      end
    else
    self._outsideLogged = false
    for _, bn in ipairs(w2.bones) do
      if self.state ~= 'enemy' then break end
      if bn.lethal then
        if bn.stab or bn.arrowbone then
          local rc = w2:stabRect(bn)
          if rc.w > 0 and rc.h > 0 and rectHit(SX, SY, SOUL_R, rc) then
            self:hurt('hit')
          end
        elseif bn.kind == 'blue' then
          local orange = (bn.color == 'orange')
          local white = (bn.color == 'white' or bn.color == 0 or bn.color == nil)
          -- C6/C19：蓝骨只惩罚「移动」，橙骨只惩罚「静止」；白骨与移动无关（原作 Color 0）
          local rc = { x = bn.x, y = bn.y, w = bn.w, h = bn.h }
          if white then
            if rectHit(SX, SY, SOUL_R, rc) then
              if self:hurt('hit') then bn.hitDone = true end
            end
          elseif orange then
            if not moved and rectHit(SX, SY, SOUL_R, rc) then
              if self:hurt('orange') then bn.hitDone = true end
            end
          else
            if moved and rectHit(SX, SY, SOUL_R, rc) then
              if self:hurt('blue') then bn.hitDone = true end
            end
          end
        elseif bn.kind == 'floor' then
          local rc = { x = bn.x - bn.w / 2, y = bn.y - bn.h, w = bn.w, h = bn.h }
          if rectHit(SX, SY, SOUL_R, rc) then self:hurt('hit') end
        elseif bn.kind == 'slide' then
          local rc = { x = bn.x, y = bn.y, w = bn.w, h = bn.h }
          if rectHit(SX, SY, SOUL_R, rc) then self:hurt('hit') end
        elseif bn.kind == 'sine' then
          if sineHitTest(bn, SX, SY, SOUL_R) then self:hurt('hit') end
        else
          -- 纯攻击脚本骨头（BoneV / BoneH / Repeat）：**X,Y 是左上角**（对齐参考实现的 C2 原点）。
          -- 旧实现按中心算 → 整根骨头偏移 (-w/2,-h/2)：高骨会戳出框顶、底部矮骨会浮在半空，
          -- 左右两侧的骨缝（bonegap/multi 的中心镜像组）还会互相错位。
          local rc = { x = bn.x, y = bn.y, w = bn.w, h = bn.h }
          if bn.axis == 'v' then
            -- 竖骨在 BTS 里建在 CombatZoneClipped 图层 → 裁到战斗框（横骨不裁，见 clipVZone 注释）
            local cx, cy, cw, ch = clipVZone(rc.x, rc.y, rc.w, rc.h, w2.zone)
            if cx == nil then rc = nil else rc = { x = cx, y = cy, w = cw, h = ch } end
          end
          if rc and rectHit(SX, SY, SOUL_R, rc) then
            -- 脚本骨的颜色语义（Documentation/Attacks.md：0 白 / 1 蓝 / 2 橙）——
            -- 原来这里不看颜色，蓝骨一样无条件扣血，所以「脚本蓝骨」一直等于白骨。
            -- 蓝骨只惩罚「移动」，橙骨只惩罚「静止」，白骨无条件伤害（与内置 blue/orange 骨同一套 moved 判定）。
            local c = bn.color
            if c == 1 then
              if moved then self:hurt('blue') end
            elseif c == 2 then
              if not moved then self:hurt('orange') end
            else
              self:hurt('hit')
            end
          end
        end
      end
    end
    for _, W in ipairs(self.walls) do
      if self.state ~= 'enemy' then break end
      if W.phase ~= 'warn' and not (W.phase == 'retract' and W.h < LETHAL_H) then
        for L = 0, W.lanes - 1 do
          if not (L >= W.gapStart and L < W.gapStart + W.gapW) then
            local rc = { x = self.box.x + L * W.laneW,
                         y = self.box.y + self.box.h - W.h,
                         w = W.laneW, h = W.h }
            if rectHit(self.soul.x, self.soul.y, SOUL_R, rc) then self:hurt('hit', 10) end
          end
        end
      end
    end
    -- 正弦骨：**独立实体表**（w.sine，不在 w.bones 里），必须单独判定。
    -- 之前只判了 w.bones，于是正弦骨从来不打人（视觉有、判定没有）。
    for _, sn in ipairs(w2.sine) do
      if self.state ~= 'enemy' then break end
      if sineHitTest(sn, SX, SY, SOUL_R) then self:hurt('hit') end
    end
    for _, B in ipairs(w2.blasters) do
      -- 【差距文档 P-06】原版 GasterBlastHit 只在 STATE_LEAVE 且 GasterBlast1.Opacity>80 时才失效；
    -- 也就是「淡出开始后、透明度还比较高」的那一小段仍然会打人（避免看起来被扫到却不掉血）。
    local beamLethal = (B.state == 'fire')
    if not beamLethal and (B.state == 'fade' or B.state == 'done') then
      local bb = (B.blast and B.blast > 0) and B.blast or 1
      local al = math.max(0, 1 - math.max(0, B.t - bb) / 0.15)
      beamLethal = al > (80 / 255)
    end
    if beamLethal then
        local band
        if B.axis then
          -- 内置模式冲击波：axis/pos 表达
          if B.axis == 'v' then
            band = { x = B.pos - B.band / 2, y = w2.zone.t, w = B.band, h = w2.zone.b - w2.zone.t }
          else
            band = { x = w2.zone.l, y = B.pos - B.band / 2, w = w2.zone.r - w2.zone.l, h = B.band }
          end
        else
          -- 脚本 GasterBlaster：从炮口沿 ang 射出 2000px、宽 band 的**线段**。
          -- 旧实现取整条线段的 AABB → 斜射时那个矩形覆盖一大片根本不在光束上的区域，
          -- 玩家看到的是「没光束的地方也掉血」（用户第十一轮：18 回合螺旋光束判定有问题）。
          -- 现在改成「灵魂中心到线段的最短距离 ≤ band/2 + SOUL_R」——与画出来的光束同宽。
          local rad = math.rad(B.ang or 0)
          local mx, my = B.x, B.y
          local dx, dy = math.cos(rad) * BLASTER_BEAM_LEN, math.sin(rad) * BLASTER_BEAM_LEN
          local px, py = SX - mx, SY - my
          local len2 = dx * dx + dy * dy
          local t = (len2 > 0) and ((px * dx + py * dy) / len2) or 0
          if t < 0 then t = 0 elseif t > 1 then t = 1 end
          local nx, ny = mx + dx * t, my + dy * t
          local dist = math.sqrt((SX - nx) * (SX - nx) + (SY - ny) * (SY - ny))
          local bw = B.band or BLASTER_W[1]
          if dist <= bw / 2 + SOUL_R then self:hurt('hit', 10) end
          band = nil
        end
        if band and rectHit(SX, SY, SOUL_R, band) then self:hurt('hit', 10) end   -- 内置模式仍用 band
      end
    end
    end   -- /outside 守卫
  end

  if self.soul.grounded then self.soul.groundT = 0 else self.soul.groundT = (self.soul.groundT or 99) + dt end
  self.prevX, self.prevY = self.soul.x, self.soul.y
  self.invuln = math.max(0, self.invuln - dt)

  -- 【差距文档第二轮 G13】脚本调用 EndAttack 后**立即**收尾（留 0.2s 淡出），
  -- 不再傻等 enemyDur 走完（旧行为：终盘/骨刺关打完还要空等十几秒）。
  if self.world and self.world.ended and self.enemyT > 0.2 then
    self:endEnemy()
    return
  end
  -- enemyDur 降级为「安全上限」：脚本因故没 EndAttack 时兜底
  if self.enemyT >= self.enemyDur then self:endEnemy() end
end

-- 输入消费（按下沿 + 边沿动作）
function Game:applyInput(input)
  input = input or {}
  local p = self.prevKeys
  local e = {
    left = (input.left and not p.left) or false,
    right = (input.right and not p.right) or false,
    up = (input.up and not p.up) or false,
    down = (input.down and not p.down) or false,
    confirm = (input.confirm and not p.confirm) or false,
    cancel = (input.cancel and not p.cancel) or false,
  }
  self.prevKeys = { left = input.left or false, right = input.right or false,
                    up = input.up or false, down = input.down or false,
                    confirm = input.confirm or false, cancel = input.cancel or false }
  self:press('left', input.left); self:press('right', input.right)
  self:press('up', input.up); self:press('down', input.down)
  self:press('cancel', input.cancel)   -- V-03：减速键要按住状态
  -- 蓝心跳跃用：适配层在蓝魂态把 up/down 掩成 false，只保留按下沿；按住状态走这个字段
  self.jumpHeld = input.jumpHeld and true or false
  if self.state == 'result' then
    if e.confirm then self:restart() end
  elseif self.state == 'attack' then
    if e.confirm then self:stopAttack() end
  elseif self.state == 'menu' then
    if e.left then self:menuMove(-1) end
    if e.right then self:menuMove(1) end
    if e.confirm then self:menuChoose(nil) end
  elseif self.state == 'sub' then
    if e.up then self:subMove(-1) end
    if e.down then self:subMove(1) end
    if e.confirm then self:subConfirm() end
    if e.cancel then self:subBack() end
  elseif self.state == 'enemy' then
    if e.confirm and self.soul.mode == 'blue' then self:jump() end
  end
end

-- ==========================================================================
-- 渲染（纯函数，不改状态）
-- ==========================================================================
local function menuLayout()
  local total = MENU.bw * 4 + MENU.gap * 3
  local x0 = (VW - total) / 2
  return x0, total
end
local MENU_X0, MENU_TOTAL = menuLayout()

local function push(t, v) t[#t + 1] = v; return t end

local function renderWorld(g)
  local cmds = {}
  local w = g.world
  if not w then return cmds end
  -- 骨头（世界帧 ① = 输出帧；输出前不再做任何平移）
  for _, bn in ipairs(w.bones) do
    if bn.arrowbone then
      -- 箭头模块：从箭头那条边升起的骨头（形状见 World:stabRect），按普通骨头画
      local rc = w:stabRect(bn)
      if rc.w > 0 and rc.h > 0 then
        local vert = (rc.h >= rc.w)
        local bx, by, bw, bh = rc.x, rc.y, rc.w, rc.h
        if vert then
          local cx, cy, cw, ch = clipVZone(bx, by, bw, bh, w.zone)
          if cx == nil then bx = nil else bx, by, bw, bh = cx, cy, cw, ch end
        end
        if bx ~= nil then
          push(cmds, { kind = 'bone', x = bx, y = by, w = bw, h = bh, vertical = vert,
                       color = 0, alpha = 1, phase = bn.phase, lethal = bn.lethal and true or false })
        end
      end
    elseif bn.stab then
      local rc = w:stabRect(bn)
      -- 阶段名对齐 GDD C14：peek(预警) / extend(伸出) / hold(停留) / retract(收回)
      local phase = STAB_PHASE[bn.phase] or 'peek'
      push(cmds, { kind = 'stab', x = rc.x, y = rc.y, w = rc.w, h = rc.h,
                   dir = bn.dir, phase = phase, phaseRaw = bn.phase,
                   alpha = 1, lethal = (phase == 'extend' or phase == 'hold') })
    elseif bn.kind == 'floor' then
      local alpha = (bn.phase == 'peek') and 0.9 or 1
      push(cmds, { kind = 'bone', x = bn.x - bn.w / 2, y = bn.y - bn.h,
                   w = bn.w, h = bn.h, vertical = true, color = 0, alpha = alpha, phase = bn.phase,
                   wave = bn.wave, lethal = bn.lethal, telegraph = (bn.phase == 'peek') })
    else
      local color = 0
      -- 脚本骨 Color 是**数字** 0/1/2（0 白 / 1 蓝 / 2 橙，见 Documentation/Attacks.md）；
      -- 内置生成器写的是字符串 'blue'/'orange'。两种都要认，否则蓝骨会被画成白的。
      if type(bn.color) == 'number' then color = bn.color
      elseif bn.color == 'blue' then color = 1 elseif bn.color == 'orange' then color = 2 end
      -- 锚点必须与**判定**一致（同一次审计里的第二个 bug）：内置生成器的 blue/slide 骨在
      -- 碰撞里用的是**左上角** (bn.x, bn.y) 画出的矩形（见 update 里
      -- `local rc = { x = bn.x, y = bn.y, w = bn.w, h = bn.h }`），
      -- 这里以前按**中心** (bn.x, bn.y) 输出 → 视觉整体偏 (w/2, h/2)。
      -- blue 骨 w = 整框宽（420），偏 210px 时"看得见的骨头只有一半能打到你"。
      -- 纯脚本骨（BoneV/BoneH）判定用的就是中心，保持中心不变。
      -- 锚点：blue/slide 一直是左上角；纯脚本骨（BoneV/BoneH）也是左上角（见 update 里碰撞的同一处注释）。
      local bx, by, bw, bh = bn.x, bn.y, bn.w, bn.h
      -- 朝向：blue = 横向整框骨；slide = 竖向矮骨；纯脚本骨按脚本给的 axis（BoneV/BoneH）。
      -- 【真 bug（本轮修）】旧实现恒写 vertical = (bn.kind ~= 'blue') → BoneH/BoneHRepeat 被当**竖骨**画：
      -- 判定仍是 200×19 的横条，视觉却只剩几个小骨帽 → 试玩里表现为「场上一堆不消失的白色方块」。
      local vertical
      if bn.kind == 'blue' then vertical = false
      elseif bn.kind == 'slide' then vertical = true
      elseif bn.axis ~= nil then vertical = (bn.axis == 'v')
      else vertical = (bn.h or 0) >= (bn.w or 0) end
      if vertical and bn.axis == 'v' then
        -- 竖骨：裁到战斗框（与碰撞用的是同一个 clipVZone，保证“画出来的 == 打得中的”）
        local cx, cy, cw, ch = clipVZone(bx, by, bw, bh, w.zone)
        if cx == nil then bx = nil else bx, by, bw, bh = cx, cy, cw, ch end
      end
      if bx ~= nil then
        push(cmds, { kind = 'bone', x = bx, y = by,
                     w = bw, h = bh, vertical = vertical, color = color, alpha = 1,
                     phase = 'hold', lethal = bn.lethal and true or false })
      end
    end
  end
  -- 正弦骨不在这里输出（它是独立实体表 w.sine，不在 w.bones 里，见上面 update 的碰撞段），
  -- 由 M.render 单独追加；坐标系与这里完全相同（world.zone 帧），**两者都不再平移**。
  -- 龙骨炮（世界帧 ① = 输出帧）
  for _, g2 in ipairs(w.blasters) do
    local x, y = g2.x, g2.y
    local spinT = (g2.spin and g2.spin > 0) and g2.spin or 1
    local charge = 1
    if g2.state == 'spin' then charge = math.min(1, g2.t / spinT)
    elseif g2.state == 'spinning' or g2.state == 'fire' then charge = 1
    elseif g2.state == 'done' then charge = 1 end
    local fire = 0
    if g2.state == 'fire' then
      local b = (g2.blast and g2.blast > 0) and g2.blast or 1
      fire = math.min(1, g2.t / b)
    elseif g2.state == 'done' then fire = 1 end
    local alpha = 1
    if g2.state == 'charge' then alpha = 0.55
    elseif g2.state == 'fade' or g2.state == 'done' then
      local b = (g2.blast and g2.blast > 0) and g2.blast or 1
      alpha = math.max(0, 1 - math.max(0, g2.t - b) / 0.15)
    end
    local ang = g2.ang or 0
    local dir = math.floor(((ang % 360) + 360) % 360 / 90 + 0.5) % 4
    push(cmds, { kind = 'blaster', x = x, y = y, dir = dir, ang = ang, size = g2.size,
                 endX = g2.ex, endY = g2.ey,
                 bake = g2.bake and true or nil, w = g2.band or BLASTER_W[(g2.size or 0) + 1] or BLASTER_W[1], scale = g2.scale or 1,
                 charge = charge, fire = fire, state = g2.state, alpha = alpha })
  end
  -- 平台（世界帧 ① = 输出帧）
  for _, p in ipairs(w.platforms) do
    push(cmds, { kind = 'platform', x = p.x, y = p.y, w = p.w, h = p.h,
                 dir = p.dir, speed = p.speed, reverse = p.reverse and true or false,
                 x0 = p.x0 or p.x, y0 = p.y0 or p.y })
  end
  return cmds
end

-- 【已删除 shiftAbs】曾经这里把 renderWorld 出来的世界实体整体 +BOX_OFF 一次，
-- 理由是"脚本坐标 ① 要转成屏幕绝对坐标 ③"。**这个前提是错的**：① 和 ③ 是同一个
-- 640×480 画面帧 —— world.zone 里的数值本来就是原版屏幕坐标
-- （sans_intro 的 `CombatZoneResizeInstant,239,226,404,391` 就是原版那个 165×165 框在
--  屏幕上的位置；(239,226) = box②(0,0) + BOX_OFF），
-- 证据（三条互相独立，都能在离线自测/探针里复现）：
--   1) 正弦骨走 abs=true 从不平移，bars[1].y == zone.t == 226 正好压在框上沿；
--      它的命中判定用的也是这份几何，玩家实测"站骨头上掉血"是对的 —— 说明 zone 帧就是画帧；
--   2) box 命令 = g.box(②) + BOX_OFF = zone 本身，画出来正好落在 zone 位置；
--   3) 碰撞循环（见 update 里"world 实体在脚本坐标"那段）把 soul 用 +BOX_OFF 抬到 zone 帧
--      再和骨头/骨刺/龙骨炮/平台比 —— 判定侧从来没有第二套帧。
-- 所以这一平移让**所有世界实体**（骨头 / 骨刺 / 龙骨炮 / 平台，含内置生成器与 CSV 脚本）
-- 在画面上比判定多跑了一个 BOX_OFF（右下 +240/+226），判定却仍在框里 —— 就是玩家看到的
-- "打得到但看不见、看得见的打不到"。现在 renderWorld 的输出**直接就是最终 640×480 坐标**，
-- 适配层除了画布换算（S/OX/OY）不再做任何平移。
-- 保留说明：这里**不做画面外裁剪**——BTS 引擎本来就允许实体在画面外存在（例如 sans_intro
-- 的正弦骨从 x≈444 起步向右排开、再扫回画面），引擎自己的 ±400px 出界清理才是唯一口径。
-- 唯一的例外是**战斗框裁剪**（不是画面裁剪）：竖骨按 BTS 的 CombatZoneClipped 语义裁到 zone，
-- 见 renderWorld 里对 bn.axis=='v' 调用 clipVZone 的那一处（横骨/龙骨炮不裁）。

function M.render(g)
  local cmds = {}
  cmds[#cmds + 1] = { kind = 'shake', x = g.shakeX or 0, y = g.shakeY or 0 }   -- 【A-7】整屏偏移 (main.lua 消费)
  -- 战斗框：**输出绝对坐标**。框在所有状态下都在同一位置（不再按状态上移）——
  -- 按钮行 y 306..342 本来就在框内（框 y 178.5..438.5），原版也画在框内。
  local boxAbs = { x = g.box.x + BOX_OFF_X, y = g.box.y + BOX_OFF_Y, w = g.box.w, h = g.box.h }
  push(cmds, { kind = 'box', x = boxAbs.x, y = boxAbs.y, w = boxAbs.w, h = boxAbs.h,
               baseY = boxAbs.y, shifted = false })
  if g.state == 'title' then
    push(cmds, { kind = 'hudText', text = '弹 幕 审 判', x = VW / 2, y = 100, size = 28, color = '#ffffff', align = 'center' })
    for i = 0, #DIFF_ORDER - 1 do
      local D = DIFFS[DIFF_ORDER[i + 1]]
      local sel = (i == g.titleIndex)
      push(cmds, { kind = 'menu', x = 32 + i * 145, y = 210, w = 130, h = 40,
                   items = { D.label }, index = 0, visible = true, selected = sel })
      push(cmds, { kind = 'hudText', text = D.note, x = 32 + i * 145 + 65, y = 262, size = 12,
                   color = sel and '#c9b26a' or '#666666', align = 'center' })
    end
    return cmds
  end
  if g.state == 'result' then
    push(cmds, { kind = 'flash', alpha = 1 })
    local t = (g.result == 'fail') and 'GAME OVER' or ((g.result == 'spare') and '饶 恕 结 局' or '击 倒 结 局')
    push(cmds, { kind = 'hudText', text = t, x = VW / 2, y = 145, size = 36,
                 color = (g.result == 'fail') and '#ff2d2d' or '#ffcc33', align = 'center' })
    push(cmds, { kind = 'menu', x = VW / 2 - 65, y = 220, w = 130, h = 36,
                 items = { '重 开' }, index = 0, visible = true })
    push(cmds, { kind = 'hudText', text = '确认键重开', x = VW / 2, y = 280, size = 12,
                 color = '#bbbbbb', align = 'center' })
    return cmds
  end

  -- 【Sans 本人】
  -- 画在框之后、弹幕/灵魂之前：骨头、龙骨炮、心都盖在他身上 —— 与原版一致
  -- （他站在框下沿、头探进框里，心在框里飞）。菜单/子面板/攻击条态也画：他的"站姿"一直在场，
  -- 只是脚本不再驱动他（world 为 nil 时用默认姿势）。
  -- 契约（适配层按原版零件尺寸自己排布，见 main.lua 的 drawSans）：
  --   x     = 站位中心 x（脚本 SansX 可改，默认 320）
  --   y     = **头顶** y（世界坐标，Y 向下；326 = 原版 sans 头顶，脚底落在 474）
  --   head  = Default / ClosedEyes / BlueEye / NoEyes / Tired1 / Tired2
  --   body  = nil / HandRight / HandDown / HandLeft / HandUp（砸击抬手）
  --   torso = Default / ...（脚本 SansTorso）
  --   anim  = Idle / ... / Tired
  --   sweat = 0..3（汗滴数量）  dodge = 0..1（1 = 刚闪开，适配层据此侧移）
  do
    local sk = g.world and g.world.sans or nil
    push(cmds, { kind = 'sans',
                 x = (sk and sk.x) or 320, y = boxAbs.y - 16 - SANS_H,  -- 站在框**上方**：留 16px 空隙，不贴框
                 head = (sk and sk.head) or 'Default',
                 body = sk and sk.body or nil,
                 torso = (sk and sk.torso) or 'Default',
                 anim = (sk and sk.anim) or 'Idle',
                 sweat = (sk and sk.sweat) or 0,
                 dodge = g.sansDodge or 0, alpha = 1 })
  end

  -- 【场地实体只在战斗态渲染】
  -- Enemy 侧的实体表在菜单/子面板/攻击条态**不再更新**（update 在这几个状态直接 return），
  -- 但渲染以前完全不看状态 → 回合结束后残留的骨墙 / 平台 / 骨头会一直挂在画面上
  -- （玩家实测："第一轮六回合结束后场地上实体没有删除"）。
  -- 主修复是 Game:endEnemy 里的清表；这里是双保险：漏清任何一个也不会再画出来。
  local fieldOn = (g.state == 'enemy')
  -- 骨墙（原地升降 + 缺口）
  for _, W in ipairs(fieldOn and g.walls or {}) do
    push(cmds, { kind = 'wall', x = boxAbs.x, y = boxAbs.y, w = boxAbs.w, h = boxAbs.h,
                 lanes = W.lanes, gapStart = W.gapStart, gapW = W.gapW,
                 hCur = W.h, phase = W.phase, boxY = boxAbs.y, boxH = boxAbs.h })
  end
  -- 平台（内置 blue_soul 模式，框内相对坐标 -> 绝对）
  for _, p in ipairs(fieldOn and g.platforms or {}) do
    push(cmds, { kind = 'platform', x = p.x + BOX_OFF_X, y = p.y + BOX_OFF_Y, w = p.w, h = p.h,
                 dir = p.dir or 0, speed = p.speed or 0, reverse = p.reverse and true or false })
  end
  -- 攻击脚本实体：renderWorld 的输出**已经是最终 640×480 坐标**（与 world.zone / box 同一帧），
  -- 这里不再做任何平移（曾经的 shiftAbs +BOX_OFF 是重复平移，见上面【已删除 shiftAbs】）。
  local worldCmds = fieldOn and renderWorld(g) or {}
  for _, c in ipairs(worldCmds) do push(cmds, c) end
  -- 正弦骨：本就在 world.zone 帧（与其它世界实体同帧），单独追加。
  -- 命中判定（sineRectOf）与这里用的是同一个 centerY，两者同帧 —— 之前漏这条一致性
  -- 导致"视觉在 226..391、判定在 452..486"，正弦骨完全不造成伤害。
  if fieldOn and g.world then
    for _, s in ipairs(g.world.sine) do
      local gm = sineGeom(s)
      local bars = sineBars(s, gm, 0)
      local first = bars[1]
      -- abs=true 现在只是"我已经在世界帧、不许再平移"的显式标记（平移器已删除，见上）；
      -- 保留它可以在未来有人重新引入平移器时立刻暴露矛盾。
      push(cmds, { kind = 'sine', abs = true,
                   x = gm.x, y = first and first.y or gm.centerY,
                   w = gm.w, h = first and first.h or 0,
                   vertical = true,
                   centerY = gm.centerY, baseY = gm.baseY, amp = gm.amp,
                   gap = s.gap, phase = gm.phase, speed = s.speed, dir = s.dir, alpha = 1,
                   bars = bars, barThickness = gm.w,
                   gapTop = gm.top, gapBottom = gm.bottom,
                   -- 判定用的就是 bars（看得见的骨头）；这条 hit 只是走廊中心的调试标记
                   hit = { x = gm.x, y = gm.centerY - SINE_HIT_W / 2, w = SINE_HIT_W, h = SINE_HIT_W } })
    end
  end
  -- 内置骨头（仅当这一回合没有 world 时；Game 级数组是**框内相对坐标 ②** → +BOX_OFF 一次）
  if fieldOn and not g.world then
    for _, bn in ipairs(g.bones or {}) do
      local color = 0
      -- 脚本骨 Color 是**数字** 0/1/2（0 白 / 1 蓝 / 2 橙，见 Documentation/Attacks.md）；
      -- 内置生成器写的是字符串 'blue'/'orange'。两种都要认，否则蓝骨会被画成白的。
      if type(bn.color) == 'number' then color = bn.color
      elseif bn.color == 'blue' then color = 1 elseif bn.color == 'orange' then color = 2 end
      local x, y, wd, ht, vertical, phase = bn.x, bn.y, bn.w, bn.h, true, 'hold'
      if bn.kind == 'floor' then
        x, y, wd, ht, vertical = bn.x - bn.w / 2, bn.y - bn.h, bn.w, bn.h, true
        phase = bn.phase
      elseif bn.kind == 'slide' then
        vertical = true; phase = 'hold'
      end
      push(cmds, { kind = 'bone', x = x + BOX_OFF_X, y = y + BOX_OFF_Y, w = wd, h = ht,
                   vertical = vertical, color = color, alpha = 1, phase = phase,
                   lethal = bn.lethal and true or false })
    end
    for _, bl in ipairs(g.blasters or {}) do
      local band = bl.band or 92
      local vertical = (bl.axis == 'v')
      local blx, bly = bl.x or (g.box.x + BOX_OFF_X), bl.y or (g.box.y + BOX_OFF_Y)
      local blw, blh = bl.w or g.box.w, bl.h or g.box.h
      local bx, by, bw, bh
      if vertical then
        bx, by, bw, bh = bl.pos - band / 2, bly, band, blh
      else
        bx, by, bw, bh = blx, bl.pos - band / 2, blw, band
      end
      local charge, fire, alpha = 0, 0, 1
      if bl.state == 'charge' then charge = math.min(1, bl.t / math.max(0.0001, g.warn))
      elseif bl.state == 'fire' then charge, fire = 1, math.min(1, bl.t / 0.35)
      elseif bl.state == 'fade' then charge, fire = 1, 1; alpha = math.max(0, 1 - bl.t / 0.3) end
      push(cmds, { kind = 'blaster', x = bx, y = by, w = bw, h = bh,
                   dir = vertical and ((bl.side or 1) < 0 and 3 or 1) or ((bl.side or 1) < 0 and 2 or 0),
                   charge = charge, fire = fire, state = bl.state, alpha = alpha })
    end
  end
  -- 灵魂（**一律按游戏内的灵魂渲染**，转成绝对坐标；保证屏幕上只有一个灵魂、不会跳）
  local invuln = (g.invuln > 0)
  local blink = invuln and (math.floor(g.invuln * 20) % 2 == 0)
  local soulX, soulY = VW / 2, VH / 2                 -- 兜底：屏幕中心（绝对坐标）
  local soulMode = 'red'
  if g.soul then
    soulX, soulY, soulMode = g.soul.x + BOX_OFF_X, g.soul.y + BOX_OFF_Y, g.soul.mode
  end
  push(cmds, { kind = 'soul', x = soulX, y = soulY, mode = soulMode,
               invuln = invuln, visible = not blink })
  -- HUD —— 位置照参考实现（BTS 的 Background 图层）：HP 文字 y≈402、血条 y≈416、按钮行 y=432。
  -- 也就是整行**紧贴选项栏上方**，不再占用屏幕顶部（顶部只留 Sans 的台词）。
  -- 左侧 = LV / HP / 血条 / KR，右侧 = ROUND / 难度；中间留白给 Sans 本人（世界 x≈288..352）。
  local hudY = 403
  push(cmds, { kind = 'hudText', text = 'LV 19', x = 20, y = hudY, size = 13, color = '#ffffff', align = 'left' })
  push(cmds, { kind = 'hudText', text = 'HP ' .. g.hp .. '/' .. g.maxHP, x = 76, y = hudY, size = 13, color = '#ffffff', align = 'left' })
  push(cmds, { kind = 'hudBar', x = 168, y = hudY + 1, w = 96, h = 11, hp = g.hp, kr = g.kr, max = g.maxHP })
  push(cmds, { kind = 'hudText', text = 'KR ' .. math.floor(g.kr + 0.5), x = 272, y = hudY, size = 12, color = '#c9a3ff', align = 'left' })
  push(cmds, { kind = 'hudText', text = 'ROUND ' .. (g.round + 1) .. ' / ' .. TOTAL_ROUNDS, x = VW - 150, y = hudY, size = 13, color = '#ffffff', align = 'right' })
  push(cmds, { kind = 'hudText', text = '难度 ' .. (g.tune and g.tune.label or '普通'), x = VW - 20, y = hudY + 1, size = 11, color = '#8a8a8a', align = 'right' })
  push(cmds, { kind = 'hudText', text = utf8sub(g.line, g.lineShown), x = VW / 2, y = 86, size = 14, color = '#ffffff', align = 'center' })
  if g.flash > 0 then
    push(cmds, { kind = 'flash', alpha = 0.35 * g.flash / 0.12 })
  end
  -- 菜单
  if g.state == 'menu' or g.state == 'attack' or g.state == 'sub' then
    push(cmds, { kind = 'menu', x = MENU_X0, y = MENU.y, w = MENU.bw, h = MENU.bh,
                 items = MENU_LABELS, index = g.menuIndex, visible = true,
                 active = (g.state == 'menu'), interlude = g.interlude and true or false })
    if g.state == 'attack' then
      local ax, ay, aw, ah = boxAbs.x, boxAbs.y + boxAbs.h / 2 - 11, boxAbs.w, 22
      push(cmds, { kind = 'attackBar', x = ax, y = ay, w = aw, h = ah,
                   cursor = g.attackCursor, result = g.attackResult })
    end
    if g.state == 'sub' then
      local rows = g:subRows()
      -- 子面板画在**框内**（原版 ACT/ITEM 面板就在框里，框的白边保留），
      -- 并且面板矩形本身必须落在框内、也落在 0..640/0..480 内 ——
      -- 之前是 y=348 + panelH(4 行 212) = 348..560，掉出世界底边 80px，行被切掉。
      local pad = 8
      local px, py = boxAbs.x + pad, boxAbs.y + pad
      local pw = boxAbs.w - pad * 2
      local ph = boxAbs.h - pad * 2
      -- 标题 34 + 描述 24 = 58；剩下的按行数均分（行高限制在 24..40，行少时不会撑得难看）
      local rowSpace = math.max(0, ph - 58)
      local rowH = clamp(math.floor(rowSpace / math.max(1, #rows)), 24, 40)
      push(cmds, { kind = 'sub', x = px, y = py, w = pw, h = ph,
                   rowH = rowH, title = SUB_TITLE[g.sub] or '', rows = rows, index = g.subIndex,
                   notes = (function()
                     local n = {}
                     for i = 0, #rows - 1 do n[i + 1] = g:subRowNote(i) end
                     return n
                   end)(),
                   desc = g:subDesc() })
    end
  end
  return cmds
end

function M.hud(g)
  local phase = g.state
  if g.state == 'enemy' then phase = 'enemy'
  elseif g.state == 'menu' then phase = g.interlude and 'interlude' or 'menu'
  elseif g.state == 'sub' then phase = 'sub_' .. tostring(g.sub)
  elseif g.state == 'attack' then phase = 'attack'
  elseif g.state == 'result' then phase = 'result_' .. tostring(g.result)
  elseif g.state == 'title' then phase = 'title' end
  return { hp = math.floor(g.hp), kr = math.floor(g.kr + 0.5), phase = phase, round = g.round }
end

function M.debug(g)
  local w = g.world
  return {
    state = g.state,
    round = g.round,
    final = g.final,
    roundScript = g.roundScript,
    scriptUses = g.scriptUses,
    interlude = g.interlude,
    hp = g.hp,
    kr = g.kr,
    krT = g.krT,
    invuln = g.invuln,
    diff = g.diffKey,
    spd = g.spd,
    wave = g.wave,
    wavesAlive = (function()
      local n = 0
      for _ in pairs(g.wavesAlive) do n = n + 1 end
      return n
    end)(),
    floorLock = g.floorLock,
    bones = w and #w.bones or #(g.bones or {}),
    sine = w and #w.sine or 0,
    blasters = w and #w.blasters or #(g.blasters or {}),
    platforms = w and #w.platforms or #(g.platforms or {}),
    walls = #g.walls,
    script = g.scriptName,
    pc = w and w.pc or nil,
    progLen = w and #w.prog or nil,
    wait = w and w.wait or nil,
    scriptEnded = w and w.ended or nil,
    zone = w and { l = w.zone.l, t = w.zone.t, r = w.zone.r, b = w.zone.b, resizing = w.zone.resizing } or nil,
    hitCount = w and w.hitCount or nil,
    enemyT = g.enemyT,
    enemyDur = g.enemyDur,
    logCount = #g.logs,
  }
end

-- 快照（对应 game.js 的 snapshot，供断言/日志用）
function M.snapshot(g)
  local w = g.world
  return {
    state = g.state, hp = g.hp, kr = math.floor(g.kr * 100 + 0.5) / 100,
    round = g.round, final = g.final, result = g.result, diff = g.diffKey,
    sub = g.sub, subIndex = g.subIndex, items = g:itemCount(),
    soul = { x = math.floor(g.soul.x + 0.5), y = math.floor(g.soul.y + 0.5), mode = g.soul.mode },
    bones = w and #w.bones or #(g.bones or {}),
    logs = g.logs,
  }
end

-- ==========================================================================
-- 对外构造
-- ==========================================================================
local function newGame(opts)
  opts = opts or {}
  local g = setmetatable({}, Game)
  g.bootSeed = opts.seed
  if g.bootSeed == nil then g.bootSeed = 20260927 end
  g.maxHP = opts.hp or MAX_HP
  g.bootHP = g.maxHP
  g.bootRound = opts.startRound or 1
  g.testAimWave1 = opts.aimWave1 and true or false
  g.testNoSpawn = opts.noSpawn and true or false
  g.testHitsAt = {}
  for _, v in ipairs(opts.hitsAt or {}) do g.testHitsAt[#g.testHitsAt + 1] = v end
  g.scripts = opts.scripts or {}
  -- 中场（原作第 12 次攻击后）默认落在内部号 11；测试想提前触发也可以显式传 interludeAfter
  g.interludeAfter = opts.interludeAfter or INTERLUDE_ROUND
  -- 测试钩子：本局不挂攻击脚本，走内置生成器兜底（见 startEnemy）
  g.testNoScript = opts.noScriptRounds and true or false
  g.logs = {}
  g.titleIndex = 1
  local di = 0
  for i, k in ipairs(DIFF_ORDER) do if k == opts.difficulty then di = i - 1 end end
  if type(opts.difficulty) == "number" then di = clamp(opts.difficulty, 0, #DIFF_ORDER - 1) end
  g:setDiff(di)
  g.platforms = {}
  g.bones = {}
  g.blasters = {}
  g.walls = {}
  g.sine = {}
  g.world = nil
  g.scriptName = nil
  g.state = 'title'
  g:resetRun()
  return g
end

function M.newGame(opts)
  local g = newGame(opts)
  g:start()
  return g
end

-- 标题页（难度选择）：建一局但**停在 title 态**，由适配层渲染标题 + 四档难度卡供玩家挑选。
function M.newTitle(opts) return newGame(opts) end

-- 标题页交互：左右选档 / 确认开局
function M.titleMove(g, d)
  if not g or g.state ~= 'title' then return end
  g:setDiff((g.titleIndex or 0) + (d or 0))
end

function M.titleChoose(g, i)
  if not g or g.state ~= 'title' then return end
  if i ~= nil then g:setDiff(i) end
  g:start()
end

function M.titleIndex(g) return g and g.titleIndex or 0 end

-- M.update(state, input, dt) -> cmds
--   input = { left, right, up, down, confirm, cancel }
--     * left/right/up/down 是**按住状态**（true/false）
--     * confirm / cancel 用**按下沿**判定：既接受"上一帧 false 这一帧 true"的
--       持续状态，也接受适配层自己做出来的"单帧脉冲"（下一帧回 false）——
--       两种约定都不会重复触发，因为边沿只在 false->true 的那一帧成立。
--   返回值就是 M.render(state) 的结果（适配层可直接使用；也可忽略后自行调 render）
function M.update(g, input, dt)
  if g.state == 'result' then
    if input and input.confirm and not (g.prevKeys and g.prevKeys.confirm) then
      g.prevKeys = { confirm = true }
      g:restart()
    else
      g.prevKeys = { confirm = input and input.confirm or false }
    end
    return M.render(g)
  end
  g:applyInput(input)
  g:update(dt or DT)
  return M.render(g)
end

function M.step(g, seconds, input)
  local n = math.floor((seconds or 0) / DT + 0.5)
  for _ = 1, n do
    M.update(g, input, DT)
    if g.state == 'result' then return end
  end
end

-- 调试/测试入口（与 game.js 同名同义）
function M.move(g, dx, dy) g:move(dx, dy) end
function M.jump(g) g:jump() end
function M.menuChoose(g, i) g:menuChoose(i) end
function M.subConfirm(g) g:subConfirm() end
function M.subMove(g, d) g:subMove(d) end
function M.subBack(g) g:subBack() end
function M.stopAttack(g) g:stopAttack() end
function M.debugHurt(g, kind) return g:debugHurt(kind) end
function M.restart(g) g:restart() end
function M.hasLog(g, s) return g:hasLog(s) end

-- ==========================================================================
-- 常量与元数据
-- ==========================================================================
M.DT = DT
M.VW, M.VH = VW, VH
M.BOX_OFF_X, M.BOX_OFF_Y = BOX_OFF_X, BOX_OFF_Y
M.BONE_W = BONE_W
M.BLASTER_W, M.BLASTER_BEAM_LEN, M.GRAVITY = BLASTER_W, BLASTER_BEAM_LEN, GRAVITY
M.BLASTER_SCALE, M.BLASTER_SAFE = BLASTER_SCALE, BLASTER_SAFE
M.SOUL_R, M.SOUL_SPEED = SOUL_R, SOUL_SPEED
M.SOUL_CLAMP = SOUL_CLAMP
M.KR_PER_HIT, M.KR_TICK, M.MAX_HP = KR_PER_HIT, KR_TICK, MAX_HP
M.PEEK, M.EXTEND, M.HOLD, M.RETRACT, M.TIP_H = PEEK, EXTEND, HOLD, RETRACT, TIP_H
M.DIFFS, M.DIFF_ORDER = DIFFS, DIFF_ORDER
M.ROUNDS, M.SURPRISE = ROUND_DEF, SURPRISE
M.TOTAL_ROUNDS, M.LAST_ROUND, M.SPIRAL_FROM = TOTAL_ROUNDS, LAST_ROUND, SPIRAL_FROM
M.INTERLUDE_ROUND, M.SANS_HEAD_TOP = INTERLUDE_ROUND, SANS_HEAD_TOP
M.SANS_H = SANS_H
M.TEMPLATE_SETS, M.TEMPLATE_TIERS, M.SPIRAL_SCRIPTS = TEMPLATE_SETS, TEMPLATE_TIERS, SPIRAL_SCRIPTS
M.scriptForRound = function(g, n) return scriptForRound(g, n) end
M.ACT_OPTIONS = ACT_OPTIONS
M.cmdCount = (function() local n = 0; for _ in pairs(CMD) do n = n + 1 end; return n end)()
M.jumpCount = (function() local n = 0; for _ in pairs(JUMPS) do n = n + 1 end; return n end)()
M.commands = CMD
M.jumps = JUMPS
M.parseCSV = parseCSV
M.compile = compile
M.newWorld = newWorld
M.World = World
M.mulberry32 = mulberry32
-- UTF-8 工具（渲染适配层也可复用；都是纯函数）
M.utf8len = utf8len
M.utf8sub = utf8sub
M.sineGeom = sineGeom
M.clipVZone = clipVZone
M.sineBars = sineBars
M.sineHitTest = sineHitTest

return M

