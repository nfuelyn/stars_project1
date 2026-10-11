-- 自动生成：修改 lua/*.lua 后运行 python tools/build.py。
-- 配置位于脚本开头的 config 模块；无需 require 或外部文件。
local __modules = {}
local function require(p) return __modules[p] end

__modules['default_import_file/workspace/sans-fight/lua/config'] = (function()
-- 编辑完配置后运行 python tools/build.py，再导入生成的 main.lua。
local C = {}
C.difficulty = 'original'       -- easy / normal / hard / original
C.trainingItems = false         -- true 才添加旧版的 20 个传奇面包
C.updateCallback = 'level'      -- 官方：level；仅 OnUpdate 的外部宿主：ui
C.device = 'auto'               -- auto / keyboard / mobile
C.debug = false

-- 以下是原脚本的工程模板索引。新建工程后替换为你实际的“控件模板索引”。
-- 这些数字不是所有工程通用的 ID，也不是画布中的运行时控件 id。
C.templates = {
  rect = 1073741887, circle = 1073741889, ring = 1073741890,
  rot = 1073741891, rtri = 1073741888,
  text = 1073741886, cursor = 1073741885,
  baked = 1073741884, bakedC = 1073741884, bakedRoot = 1073741884,
}
C.legacyTemplateFallback = false
-- 0 = 沿用模板内的图片；正整数才按当前工程的真实图片资产 ID 替换。
-- 模拟器的 100001 等编号不是已确认的官方通用资产编号。
C.images = { rect = 0, circle = 0, ring = 0, rot = 0, rtri = 0 }

-- 填“已配置的音效 ID”；0 表示静音。不在脚本中导入外部 mp3。
C.audio = {
  bgm = 0, bgmLoop = true,
  -- bgm=0 时，可选用现有的单音旋律；默认关闭。
  useNoteMusic = false, notes = {}, pitchClasses = {}, fallbackNote = 0,
  effects = { menu = 0, confirm = 0, cancel = 0, hit = 0, heal = 0,
              jump = 0, blasterCharge = 0, blasterFire = 0,
              soulMode = 0, slam = 0, death = 0, victory = 0,
              boneWarn = 0, boneStab = 0,
              scriptSoundFlash = 0, scriptSoundDing = 0, scriptSoundGasterBlaster = 0 },
}
C.settlement = { signal = 'SansFightSettle', retryDelay = 1, maxAttempts = 3 }
return C

end)()

__modules['default_import_file/workspace/sans-fight/lua/core'] = (function()
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
  以 Jcw87/c2-sans-fight 攻击 CSV 与 Battle.xml 为参考的 Lua 战斗实现。

  约束（刻意遵守）：
    * 不 require / 不 io / 不 os / 不 package / 不 debug / 不调用任何 game.* API
    * 只做逻辑：没有 print（自测除外），没有绘图细节
    * 文件末尾 return M；所有内部函数与命令表都是 local
    * 脚本数据由外部注入（opts.scripts = attacks.lua 的表），core 不自带数据

  目标运行时为 Lua 5.3，验证入口为 tools/run_tests.py。
  逻辑框、灵魂采用框内偏移；CSV World 保留 640×480 绝对坐标。
  显示出口 M.render() 全部转换为同一绝对坐标，适配层只缩放居中。
  默认最大 HP 为 92，可用 opts.hp 覆盖。
  ========================================================================== ]]

local M = {}

M.VERSION = "1.1.0"

-- ---------------------------------------------------------------- 常量
local VW, VH = 640, 480           -- 原版虚拟画布
local BONE_W = 10                 -- 骨头**厚度**：原版 BoneV.png=10x24 / BoneH.png=24x10 ——
local MIDFUSE_KEEP = 16           -- 【2026-10-07】中轴引信余量：骨头前缘在中线两侧留出的净空
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
local SOUL_CLAMP = 8              -- 框内钳位半径 = 心形视觉半宽（±8）→ 灵魂视觉宽 16
-- 【2026-10-06 用户口径】内置骨墙：相邻两根骨头之间的缝必须能容下灵魂。
--   灵魂视觉宽 = 2*SOUL_CLAMP = 16px，这里留 24px。
local WALL_GAP = 24
-- 【2026-10-06 用户口径】「贴地排骨」（Game:spawnFloor：从框底边升起、占满框高的整排厚骨）的单根内缩量：
--   骨头宽度 = 道宽 - FLOOR_BONE_INSET；道间缝宽 = 这个内缩量。
--   灵魂视觉宽 16px，所以内缩量要 >= 16 才钻得过去。
--   框宽 575 时 laneW≈63.9：6→w≈58（改前，截图里的粗骨）/ 24→w≈40（现在）/ 30→w≈34。
--   ★ 只影响 spawnFloor 这一支：脚本骨仍是 BONE_W=10，骨墙仍是 laneW-WALL_GAP。
local FLOOR_BONE_INSET = 24       -- 贴地排骨单根内缩量（越大越细；道间缝 = 本值）
-- 【blue_soul.lua / 原作 PlayerMovement 常量】
local HEART_JUMP = 180            -- HEART_JUMP_STRENGTH：起跳瞬时冲量 px/s
local HEART_CUTOFF = 30           -- HEART_JUMPHOLD_CUTOFF：松键截断后保留的上冲速度
local GRAVITY_UP_FAST = 540       -- Battle.xml：DownSpeed=-沿重力速度，上升时 540
local GRAVITY_UP_SLOW = 180
local GRAVITY_APEX    = 180
local GRAVITY_FALL    = 180       -- 快落 180；慢落（30..120）450
local SOUL_SPEED = 150              -- 【差距文档 V-03 / 附录B】原版红模式移速 = 150 px/s
local SOUL_SPEED_SLOW = 75          -- 按住取消键（取消/后退）时减速到 75 px/s
local KR_PER_HIT = 6              -- 原版 Karma：骨头 6 / 龙骨炮 10（见 Battle.xml 的 Karma 实例变量）
local KR_MAX = 40                  -- 【差距文档 V-02/附录B】原版 KR 上限 40
-- 参考 Battle.xml 1525-1551：按当前 KR 决定 KR_T 阈值（秒，括号内为约 60fps 帧数）
local KR_TIERS = {
  { min = 40, step = 0.033 }, -- 2 帧
  { min = 30, step = 0.066 }, -- 4 帧
  { min = 20, step = 0.166 }, -- 10 帧
  { min = 10, step = 0.500 }, -- 30 帧
  { min = 0,  step = 1.000 }, -- 60 帧（KR < 10）
}
local function krStep(kr)
  for _, tier in ipairs(KR_TIERS) do
    if kr >= tier.min then return tier.step end
  end
  return 1.0
end
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
-- 【2026-10-07 用户口径·我方行动固定长框】我方回合（menu/sub/attack）把战斗框**只加宽**到这两条边：
--   子面板因此有 (608-33)-16 = 559px 排版宽；y/高沿用当前回合的框 ⇒ Sans（y = 框顶-16-148）零位移。
local MENU_BOX_L, MENU_BOX_R = 33, 608

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
  original = { key = 'original', label = '原作', speed = 1.00, interval = 1.00, warn = 1.00, invuln = 0.033, note = '参考攻击速度与 KR 规则' },
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
CMD.HeartTeleport = function(w, x, y, dur)
  -- 【2026-10-06 用户口径】第 4 个参数 dur（秒）> 0 时改成**滑动**过去，不再硬瞬移：
  --   终盘长框段开局那一下 HeartTeleport,40,$HeartY 原本是可见的硬跳（前面还有 0.9s 停顿）。
  --   不传 dur = 老行为（瞬移），其它回合/其它脚本完全不受影响。
  local d = tonumber(dur)
  if d and d > 0 then
    w.heart.slide = { x0 = w.heart.x, y0 = w.heart.y, x1 = tonumber(x), y1 = tonumber(y), t = 0, dur = d }
    return
  end
  w.heart.x, w.heart.y, w.heart.vx, w.heart.vy = tonumber(x), tonumber(y), 0, 0
  w.heartPosDirty = true          -- 只有 HeartTeleport 会挪灵魂（HeartMode 不该顺带搬位置）
end
CMD.HeartMode = function(w, m)
  local mode = tonumber(m)
  if w.heart.mode ~= mode and w.audioEvents then w.audioEvents[#w.audioEvents + 1] = 'soulMode' end
  w.heart.mode = mode; w.heartModeDirty = true
end
-- 【2026-10-06】maxFall 也必须用脏标记：world.heart.maxFall 的**默认值就是 0**，
--   直接同步会把「没设过」也当成「设成 0」→ 蓝魂终端速度恒 0、永远不落地。
CMD.HeartMaxFallSpeed = function(w, v)
  w.heart.maxFall = tonumber(v)
  w.heartModeDirty = true
  w.heartMaxFallDirty = true
end
CMD.SansSlam = function(w, d)
  -- 【2026-10-06 依据 sans_final_fall_right.lua / 原作 Battle.xml 还原】
  --   ① 强制切蓝魂 ② heart.dir = dir（0东/1南/2西/3北）
  --   ③ heart.vx/vy = 重力单位向量 × MaxFallSpeed（满速甩出） ④ slammed = true
  --   **不瞬移、不清零速度**（上一轮那版「瞬移到边界」是长框段坏掉的根源，已回退）。
  d = tonumber(d) or 0
  if d < 0 or d > 3 then return end
  local s = w.heart.maxFall
  if s == nil then s = 750 end          -- 注意：0 要保留（终端 0 = 钉住）
  local DX = { [0] = 1, [1] = 0, [2] = -1, [3] = 0 }
  local DY = { [0] = 0, [1] = 1, [2] = 0,  [3] = -1 }
  w.heart.mode = 1
  w.heart.slammed = true
  w.heart.dir = d
  w.heart.vx = (DX[d] or 0) * s
  w.heart.vy = (DY[d] or 0) * s
  w.heartModeDirty = true
  w.heartVelDirty = true
  say(w, 'slam ' .. tostring(d))
end
CMD.HeartDir = function(w, d)
  -- 【2026-10-06 用户口径】只改「重力方向 / 心尖朝向」，**不**强制蓝魂、**不**瞬移：
  --   终盘阶段②的长框段用它把心设成 dir=0（尖朝右），让心靠重力自己滑到右边的框边，
  --   撞边之后再由脚本 HeartMode 0 切回红心 —— 这一段不是拖拽。
  d = tonumber(d) or 0
  if d < 0 or d > 3 then return end
  w.heart.dir = d
  w.heartModeDirty = true
  w.heartDirDirty = true     -- 【2026-10-06】通知 Game 侧同步 soul.dir
end

CMD.SansSlamDamage = function(w, b)
  w.slamDamage = (tonumber(b) ~= 0)
  w.slamDamageDirty = true     -- 【A-3】透传给 Game
end
CMD.GetHeartPos = function(w, xv, yv)
  w.vars[xv], w.vars[yv] = w.heart.x, w.heart.y
end

-- 骨头
local function pushBone(w, x, y, hOrW, axis, dir, speed, color, midFuse)
  local c = tonumber(color)
  if c == nil then c = 0 end
  local mf = tonumber(midFuse)
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
    karma = 6,       -- 骨头首次命中 +6，同一对象后续 +2
    -- 【2026-10-07 用户口径】中轴引信：左右夹击的侧骨在临近中线时销毁，
    -- 不越过战斗框水平中线（h=100 的骨满跳也过不去 → 越轴必定打中灵魂）。
    midFuse = (mf ~= nil and mf ~= 0) or nil,
  }
end
CMD.BoneV = function(w, x, y, h, dir, speed, color, midFuse)
  pushBone(w, x, y, h, 'v', tonumber(dir), tonumber(speed), color, midFuse)
end
CMD.BoneH = function(w, x, y, wd, dir, speed, color, midFuse)
  pushBone(w, x, y, wd, 'h', tonumber(dir), tonumber(speed), color, midFuse)
end

local function repeatBones(w, axis, x, y, size, dir, speed, count, spacing, color, midFuse)
  local d, sp, n, s = tonumber(dir), tonumber(spacing), tonumber(count), tonumber(size)
  -- 【2026-10-06 对照原作修正】BTS 的 BoneHRepeat/BoneVRepeat 逐个 loopindex 的偏移是
  --     X = StartX - cos(Direction*90)*Spacing*loopindex
  --     Y = StartY - sin(Direction*90)*Spacing*loopindex
  --   （见 Event sheets/Battle.xml，两个函数共用同一套公式）。
  -- 旧实现只挑一个轴、还把 dir=0/1 一律当 -1，于是 dir=1/3 的**竖骨列**被摊成一横行 ——
  -- round8/10 右侧那列「往上走的骨头」就成了整排横着一起飘过去、一趟就没了。
  local CA = { [0] = 1, [1] = 0, [2] = -1, [3] = 0 }
  local SA = { [0] = 0, [1] = 1, [2] = 0,  [3] = -1 }
  local ca, sa = CA[d] or 0, SA[d] or 0
  for i = 0, n - 1 do
    local bx = tonumber(x) - ca * i * sp
    local by = tonumber(y) - sa * i * sp
    pushBone(w, bx, by, s, axis, d, speed, color, midFuse)   -- pushBone 内部按 axis 决定 w/h
  end
end
CMD.BoneVRepeat = function(w, x, y, h, dir, speed, count, spacing, color, midFuse)
  -- 第 8 个参数 Color 是本项目的**向后兼容扩展**：官方 BoneVRepeat 没有 Color（只能是白骨），
  -- 但「左右高低骨」这种组合要求批量生成的骨头也能是蓝骨（Color=1）。不传 = 0 = 白。
  repeatBones(w, 'v', x, y, h, dir, speed, count, spacing, color, midFuse)
end
CMD.BoneHRepeat = function(w, x, y, wd, dir, speed, count, spacing, color, midFuse)
  repeatBones(w, 'h', x, y, wd, dir, speed, count, spacing, color, midFuse)
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
                            dir = (sp > 0) and -1 or 1, karma = 6 }
  end
end

CMD.BoneStab = function(w, dir, dist, warn, stay, outDur)
  -- 【2026-10-06 依据 D:\\stars\\reference\\lua\\bone_battle.lua 重写】
  --   参考实现（Battle.xml 的 BoneStabWarn → BoneStabH/V）：
  --     * 先出「警告矩形」：内缩 8px、沿边长度 = 框边 - 16、厚度 = distance - 3；
  --     * warnTime 到点后生成**一整块面板**（厚度 = distance + 8，横跨整条框边），
  --       以 speed = distance*10 从边界滑入 distance 像素（≈0.1s），停留 stayTime 后原路收回；
  --     * 面板最终**伸出** distance - 3。
  --   旧实现是「从边上长出来 + 可切 5 道留缺口」，与参考不符，已删除。
  w.bones[#w.bones + 1] = { stab = true, dir = tonumber(dir), dist = tonumber(dist),
                            warn = w:wn(warn), stay = tonumber(stay), outDur = tonumber(outDur),
                            t = 0, phase = 'warn', karma = 6 }
  if w.audioEvents then w.audioEvents[#w.audioEvents + 1] = 'boneWarn' end
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
                            warn = tonumber(warn), stay = tonumber(stay), t = 0, phase = 'warn', cur = 0, karma = 6 }
end

CMD.GasterBlaster = function(w, size, sx, sy, ex, ey, endAng, spin, blast, hold, extraW)
  local a0 = ATAN2(tonumber(ey) - tonumber(sy), tonumber(ex) - tonumber(sx)) * 180 / math.pi
  local bt = tonumber(blast)
  local spiral = (bt ~= nil and bt <= 0)
  local sz = clamp(math.floor(tonumber(size) or 0), 0, 2)
  -- 停靠点钳进安全区：不落在选项栏那一条（也不会出屏）。起点 sx,sy 不钳 —— 原版就是从屏幕角飞入的。
  local ex2, ey2 = tonumber(ex) or 0, tonumber(ey) or 0
  -- 【2026-10-07 用户口径·终盘旋转龙骨炮】持续光束（BlastTime <= 0）**不做终点钳制**：
  --   阶段④每发都是「起点 = 轴心(320,306) + 450u、终点 = 轴心 + 150u」的共线三点；
  --   一旦终点被 clamp，a0 = atan2(ey-sy, ex-sx) 就偏离这条射线 → 光束不再过轴心 →「轴心跳动」。
  --   实测（lua/_probe_spiral_pivot.lua）：钳制会让 122 发中的 37 发终点离线，最大 84px。
  --   普通龙骨炮（有 BlastTime）的钳制保持不变（停靠点仍不会压到选项栏）。
  local g = {
    size = sz, x = tonumber(sx), y = tonumber(sy),
    sx = tonumber(sx), sy = tonumber(sy), ex = ex2, ey = ey2,
    ang = a0, ang0 = a0, endAng = tonumber(endAng), spin = tonumber(spin),
    -- Battle.xml 的 BlastTime 是额外保持时间；0 仍然收束，不能永久留在场上。
    blast = math.max(0, bt or 0), fireDuration = 5/30 + math.max(0, bt or 0),
    -- 【2026-10-06】hold 不传时保持 nil —— 写成 `or 0` 会让 HoldTime 的默认值（0.05s）失效，
    -- 于是「落定后延时 1.5s」这类参数一旦漏传就变成同帧开火。
    hold = tonumber(hold), t = 0,
    -- 【方案A】全流程龙骨炮统一走原版像素烘焙；LOD 由 render 决策：
    --   sans_intro 的四发组合（Size=1）与持续旋转光束走 3×3，其余仍走 2×2。
    bake = true,
    karma = 10,      -- 龙骨炮首次命中 +10，同一对象后续 +2
    lod = (((w.scriptName == 'sans_intro') and sz == 1) or spiral) and 'block3' or nil,
    -- 光束宽度：Size 0/1/2 = 20/36/56；骷髅缩放：0.8/1.0/1.3
    -- extraW：双向各加宽这么多（用户口径「光束双向扩大 5px」→ 传 5，宽度 +10）
    band = (BLASTER_W[sz + 1] or BLASTER_W[1]) + (tonumber(extraW) or 0) * 2,
    scale = BLASTER_SCALE[sz + 1] or BLASTER_SCALE[1],
    state = (tonumber(spin) > 0) and 'spin' or 'charge',
  }
  w.blasters[#w.blasters + 1] = g
  if w.audioEvents then w.audioEvents[#w.audioEvents + 1] = 'blasterCharge' end
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
  end
end
CMD.Sound = function(w, n)
  say(w, 'sound ' .. tostring(n))
  if w.audioEvents then w.audioEvents[#w.audioEvents + 1] = 'scriptSound' .. tostring(n) end
end
CMD.Music = function(w, n) say(w, 'music ' .. tostring(n)) end
CMD.TLPause = function(w) w.paused = true end
CMD.TLResume = function(w) w.paused = false end
CMD.EndAttack = function(w)
  w.ended = true
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
  -- 【2026-10-06 修 · 真 bug】原来只转发**前 8 个**参数，凡是第 9 个及其以后的都被丢掉：
  --   GasterBlaster 的 BlastTime(9) / HoldTime(10) / ExtraWidth(11) 全部没进过函数，
  --   于是 ① 所有光束的实际存在时间都退化成 1 帧（`g.blast` 为 nil → 立刻 done）；
  --         ② 脚本里写的「光束双向扩大 5px」根本没生效；
  --         ③ 刚加的「落定后停 1.5s」也传不进去（探针实测落定→开火恒 0.033s）。
  --   按实际个数转发，多传的 nil 与不传等价，对老脚本无影响。
  fn(self, a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8],
        a[9], a[10], a[11], a[12])
  return nil
end

function World:stepScript(dt)
  if #self.prog == 0 then return end
  local guard = 0
  self.wait = self.wait - dt
  while (not self.paused) and (not self.ended) and self.wait <= 0 do
    guard = guard + 1
    -- 【2026-10-06 用户口径】每帧最多推进 40 行脚本：终盘长框段有 3 个零延时循环
    --   （44+12+24 组，一帧生成 ~172 根骨头 = ~860 个控件）会把这一帧拖卡。
    --   超出的部分自然顺延到下一帧（循环退出后 self.wait 仍为 0，下一帧继续），
    --   整段时长几乎不变（~0.4s 摊开），但每帧控件增量从 860 降到 ~200。
    --   原来的 5000 只是防死循环，起不到限流作用。
    if guard > 40 then break end
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
    if b.t >= b.warn then
      b.phase = 'out'; b.t = 0
      if self.audioEvents then self.audioEvents[#self.audioEvents + 1] = 'boneStab' end
    end
    return
  end
  -- 【回合差异文档 2.7】伸出时间可配置（默认 0.1s → 0.22s，约原版两倍，可读性更好）
  local outDur = b.outDur or 0.1     -- 参考：speed = distance*10 → 0.1s
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
-- 骨刺的命中矩形（依据 bone_battle.lua 的 BoneStabH/V 几何）
function World:stabRect(b)
  local z = self.zone
  local d = tonumber(b.dist) or 0
  -- b.cur 在 'out' 阶段从 0 线性涨到 d → t 就是「滑入进度 0..1」
  local t = 0
  if d > 0 then t = math.min(1, (b.cur or 0) / d) end
  local dir = b.dir
  if dir == 1 then                       -- 从下边框向上刺
    local h = d + 8
    return { x = z.l, y = z.b - 5 - d * t, w = z.r - z.l, h = h }
  elseif dir == 3 then                   -- 从上边框向下刺
    local h = d + 8
    return { x = z.l, y = z.t + 5 - h + d * t, w = z.r - z.l, h = h }
  elseif dir == 0 then                   -- 从右边框向左刺
    local w2 = d + 8
    return { x = z.r - 5 - d * t, y = z.t, w = w2, h = z.b - z.t }
  else                                   -- 从左边框向右刺
    local w2 = d + 8
    return { x = z.l + 5 - w2 + d * t, y = z.t, w = w2, h = z.b - z.t }
  end
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
  -- 【2026-10-06】HeartTeleport 的滑动（dur 秒内线性插值到目标点）
  if self.heart.slide then
    local sl = self.heart.slide
    sl.t = sl.t + dt
    local k = math.min(1, sl.t / sl.dur)
    self.heart.x = sl.x0 + (sl.x1 - sl.x0) * k
    self.heart.y = sl.y0 + (sl.y1 - sl.y0) * k
    self.heartPosDirty = true
    if k >= 1 then self.heart.slide = nil end
  end
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
      -- 【2026-10-07 用户口径·中轴引信】带 midFuse 标记的横移竖骨，前缘进入
      --   「中线 ± MIDFUSE_KEEP」禁区后立刻销毁 —— 骨头永远飞不过战斗框水平中线，
      --   灵魂贴在中线上就不会被这种“不可跳越”的骨扫到（HUD15/22 侧骨必中问题）。
      if b.midFuse and b.vx ~= 0 and (b.vy or 0) == 0 then
        local zz = self.zone
        local cx = (zz.l + zz.r) / 2
        if (b.vx > 0 and (b.x + b.w) >= cx - MIDFUSE_KEEP)
           or (b.vx < 0 and b.x <= cx + MIDFUSE_KEEP) then
          kill = true
        end
      end
      -- 【bone_battle.lua】出屏判定用整张画面：dir=0 → x>640 / 1 → y>480 / 2 → x<-w / 3 → y<-h
      if (b.vx > 0 and b.x > VW) or (b.vx < 0 and b.x < -b.w)
         or (b.vy > 0 and b.y > VH) or (b.vy < 0 and b.y < -b.h) then kill = true end
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
    local oldState = g.state
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
      -- 【2026-10-06】以前写成 `0.05 + hold`，用户口径「落定后延时 1.5s」就对不齐；
      -- 现在 hold 就是**落定后的停留秒数**，不传则保留原来的 0.05s 最小停留。
      local holdT = g.hold
      if holdT == nil then holdT = 0.05 end
      if g.t >= holdT then g.state = 'fire'; g.t = 0 end
    elseif g.state == 'fire' and g.t >= (g.fireDuration or (5/30 + (g.blast or 0))) then
      g.state = 'done'; g.t = 0
    end
    -- BlastTime 只增加停留时间；0 仍会在开火与淡出后销毁。
    if g.state == 'done' and g.t > 10/30 then table.remove(self.blasters, i) end
    if g.state == 'fire' and oldState ~= 'fire' and self.audioEvents then
      self.audioEvents[#self.audioEvents + 1] = 'blasterFire'
    end
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
local function beamAlpha(b)
  if b.state == 'fade' or b.state == 'done' then return math.max(0, 1 - (b.t or 0) * 3) end
  return 1
end
local function beamWidth(b)
  if b.state == 'fire' then return math.min(1, (b.t or 0) / (4/30)) end
  if b.state == 'done' or b.state == 'fade' then return 0.8 ^ ((b.t or 0) * 30) end
  return 0
end

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
local PHASE1_SEQ = {
  'sans_intro', 'sans_bonegap1', 'sans_bluebone', 'sans_bonegap2',
  'platforms1', 'platforms2', 'platforms3', 'platforms4', 'platformblaster',
  'platforms4hard', 'sans_bonegap1fast', 'sans_boneslideh', 'sans_bonegap2',
  'platformblasterfast',
}
local PHASE2_SEQ = { 'multi1', 'randomblaster1', 'multi2', 'sans_bonestab1',
  'sans_bonestab2', 'randomblaster2', 'sans_boneslidev', 'multi3', 'sans_bonestab3' }
local function chooseAttack(g, n)
  if n >= LAST_ROUND then return 'final' end
  if n == INTERLUDE_ROUND and not g.interludeCompleted then return 'sans_spare' end
  local phase2 = n > INTERLUDE_ROUND or g.interludeCompleted
  local seq = phase2 and PHASE2_SEQ or PHASE1_SEQ
  local key = phase2 and 'phase2Cursor' or 'phase1Cursor'
  local cursor = g[key] or 1
  g[key] = cursor + 1
  if seq[cursor] then return seq[cursor] end
  local choices = phase2 and { 'sans_bonestab3', 'multi3', 'randomblaster2' }
    or { 'sans_bonegap1fast', 'sans_bonegap2', 'sans_boneslideh', 'platformblasterfast' }
  return choices[1 + math.floor(g.rng() * #choices)]
end
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
function Game:emit(name)
  self.audioEvents[#self.audioEvents + 1] = name
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
  -- 【2026-10-07 用户口径】保留用户设定的「传奇面包（+45 HP ×20）」，并补上
  --   原版 Items.xml 注册的 4 件（回复量照抄原版：99 / 90 / 60 / 40，Type=0 食物）。
  --   short 字段 = 原版 ItemName2（菜单短名），本端口目前菜单显示全名，保留备用。
  self.items = {
    { id = 'pie',          name = '奶油糖派', short = 'Pie',       desc = '回复 99 HP', heal = 99, count = 1 },
    { id = 'noodles',      name = '速食泡面', short = 'I.Noodles', desc = '回复 90 HP', heal = 90, count = 1 },
    { id = 'steak',        name = '脸排',     short = 'Steak',     desc = '回复 60 HP', heal = 60, count = 1 },
    { id = 'lhero',        name = '传说英雄', short = 'L. Hero',   desc = '回复 40 HP', heal = 40, count = 5 },
  }
  if self.trainingItems and self.diffKey ~= 'original' then
    table.insert(self.items, 1, { id = 'legend_bread', name = '传奇面包',
      desc = '练习补给：回复 45 HP', heal = 45, count = 20 })
  end
  self.audioEvents = {}
  self.elapsed, self.hits, self.accumulator = 0, 0, 0
  self.phase1Cursor = self.bootRound > 1 and math.min(self.bootRound + 1, 15) or 1
  self.phase2Cursor = math.max(1, self.bootRound - INTERLUDE_ROUND)
  self.interludeCompleted = self.bootRound > INTERLUDE_ROUND
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
  self.resultIndex = 1
  self.settleRequested = false
  self.settleStatus, self.settleAttempts, self.settleRetryT = nil, 0, 0
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
  -- 【音乐】开战 / 重开战斗都走这里：给宿主层一个单调递增的场次号。
  -- 适配层（main.lua）看到它变化就让 BGM 从第 0 格重播，逻辑见 lua/music.lua。
  self.runSeq = (self.runSeq or 0) + 1
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
  if g.world then g.world.audioEvents = g.audioEvents end
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
  if not self.testNoScript then sname = chooseAttack(self, n) end
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
    -- 有脚本时以 EndAttack 为准；enemyDur 只供无脚本的练习生成器使用。

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
  -- 【2026-10-07 用户口径】我方行动期固定长框：**只改宽度**（y/高沿用本回合的框）
  --   → 子面板有 559px 可用；Sans 由框顶推导 ⇒ 框顶不变 ⇒ Sans 零位移。
  self.box = { x = MENU_BOX_L - BOX_OFF_X, y = self.box.y, w = MENU_BOX_R - MENU_BOX_L, h = self.box.h }
  self.menuIndex = 0
  -- fightCount 只统计 FIGHT；攻击脚本游标独立推进。
  -- 23 次 FIGHT 之后完成 final，下一次攻击进入击倒结局。
  self.final = (self.round >= LAST_ROUND)
  -- 原作第 12 次攻击后是「中场」：Sans 停手，直到玩家主动攻击——官方给的补给窗口。
  -- 只在**还没到最终回合**时进入；最终回合结束后直接给结局台词。
  if self.round == self.interludeAfter and not self.interludeCompleted and not self.final then
    self.interlude = true
    self:log('interlude')
    self:say(LINES.midpoint)
    return
  end
  if self.final then self:say(LINES.final) end
end

function Game:settle()
  if self.state ~= 'result' or self.settleStatus == 'sent' then return end
  self.resultIndex = 0
  self.settleRequested = true
  self.settleStatus, self.settleAttempts, self.settleRetryT = 'pending', 0, 0
  self:log('settle requested outcome=' .. tostring(self.result))
end

function Game:finish(outcome, reason)
  self.result = outcome
  self.resultIndex = 1
  self.settleRequested = false
  self.failReason = reason or nil
  self.state = 'result'
  self:emit(outcome == 'fail' and 'death' or 'victory')
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
-- 【统一落地模型】对应原版 HeartCheckSolid(cos(Angle), sin(Angle))：
--   战斗框的「远边」（地面）与**所有平台**（内置 R6 + 脚本 Platform）一起算，
--   沿重力方向取**最近的支撑面** —— 框底和空中板子从此是同一个模子。
--   （原版出处：Event sheets/Battle.xml 的 HeartJump / HeartCheckSolid；
--     工作区之前是「框底 floorY」+「内置平台」+「脚本平台」三套判定，天然会不一致。）
-- 返回：支撑面 surface（沿重力轴的坐标）/ 重力方向 gx,gy / 灵魂沿重力轴坐标 soulA / 踩到的平台 pf（框边为 nil）
function Game:groundQuery()
  local DX = { [0] = 1, [1] = 0, [2] = -1, [3] = 0 }
  local DY = { [0] = 0, [1] = 1, [2] = 0,  [3] = -1 }
  local dir = self.soul.dir or 1
  local gx, gy = DX[dir] or 0, DY[dir] or 1
  local function along(x, y) return x * gx + y * gy end

  local b, r = self.box, SOUL_CLAMP
  local soulA = along(self.soul.x, self.soul.y)
  -- 本帧「扫过」的最靠前位置：取 prev 与当前里更靠前的那个做参照。
  -- 不这么做的话，高速下落（HeartMaxFallSpeed 750 ≈ 25px/帧）会一帧穿过 7px 厚的平台。
  local prevA = along(self.prevX or self.soul.x, self.prevY or self.soul.y)
  local refA = math.min(soulA, prevA)

  -- ① 战斗框：沿重力方向的「远边」就是地面（dir=1 → 框底；dir=3 → 框顶）
  local surface = math.max(along(b.x, b.y), along(b.x + b.w, b.y),
                           along(b.x, b.y + b.h), along(b.x + b.w, b.y + b.h))
  local hitPf = nil

  -- ② 平台：横向必须与灵魂重叠；支撑面取**朝向灵魂的那一面**
  --    （下落时 = 顶面 py；反向重力时 = 底面 py+ph，即四角 along 的最小值）。
  --    注意平台与战斗框不同：框是边界（人留在框内 → 取远边），平台是实体（人站在面上 → 取近面）。
  local lists = { { list = self.platforms or {}, ox = 0, oy = 0 } }
  if self.world and self.world.platforms then
    lists[#lists + 1] = { list = self.world.platforms, ox = BOX_OFF_X, oy = BOX_OFF_Y }
  end
  for _, spec in ipairs(lists) do
    for _, pf in ipairs(spec.list) do
      local px, py = pf.x - spec.ox, pf.y - spec.oy
      local pw, ph = pf.w or 0, pf.h or 4
      local lateral
      if gy ~= 0 then lateral = (self.soul.x + r > px) and (self.soul.x - r < px + pw)
      else             lateral = (self.soul.y + r > py) and (self.soul.y - r < py + ph) end
      if lateral then
        local near = math.min(along(px, py), along(px + pw, py),
                              along(px, py + ph), along(px + pw, py + ph))
        -- 只接受「在本帧扫过位置的前方（容许 2px）且比当前候选更近」的支撑面
        if near >= refA + r - 2 and near <= surface then surface, hitPf = near, pf end
      end
    end
  end
  return surface, gx, gy, soulA, hitPf
end

-- 【round18/19 验收】甩击结束就把**重力方向还回去**（dir=1 南）。
--   原来 SansSlam 改过 soul.dir 之后一直不还原，蓝心就被「钉」在甩出去那一侧的框边上
--   （一直按住反方向也纹丝不动）—— 玩家看到的就是「拖拽之后控制被锁死」。
--   两侧都要清：update 里的双坐标同步每帧会把 world.heart.dir 抄回 soul.dir。
function Game:endSlam()
  self.soul.slammed = false
  self.soul.slamT = 0
  -- 【2026-10-06 用户口径修正】这里**不再**把 dir 还原成 1：
  --   蓝心要「随拖拽旋转、重力随方向变化」，一直保留到**本回合结束**；
  --   startEnemy 开新回合时会把 soul.mode / soul.dir 复位（见那里）。
  if self.world then self.world.heart.slammed = false end
end

function Game:jump()
  if self.state ~= 'enemy' or self.soul.mode ~= 'blue' then return end
  if self.soul.wall then
    -- 【箭头模块】墙模式下「跳跃」= 朝**箭头方向的反方向**冲刺一段（拖到左边 → 向右）。
    -- 距离与普通蓝心跳跃一致：0.5 框高 / JUMP_RISE_T。
    local dw = self.soul.wallDir or 0
    self.soul.dash = { dir = (dw + 2) % 4, t = JUMP_RISE_T, speed = 0.5 * self.box.h / JUMP_RISE_T }
    return
  end
  -- 【用户验收】起跳即脱离甩击状态（World 侧的标记一起清，否则脏标记会把它同步回来）
  if self.soul.jumping then return end      -- 空中不再触发：按住不放也不会反复起跳（边沿语义兜底）
  -- 【平台起跳】平台只有 7px 厚、且边移动边判定，起跳那一帧 grounded 可能刚好闪断。
  -- 加 0.12s 的 coyote time：离地 0.12s 内仍然算「站在地上」。
  local coyote = (self.soul.groundT or 99) <= 0.12
  -- 能不能跳 = 原版 HeartCheckSolid(cos(Angle), sin(Angle)) == 1 —— 框边与平台同一个模子，
  -- 不再读 self.soul.grounded（那个标记会被落地顺序影响，正是「空中板子跳不起来」的根因）。
  local surface, gx, gy, soulA = self:groundQuery()
  local onSolid = (soulA + SOUL_CLAMP) >= (surface - 2)
  if onSolid or coyote then
    self:endSlam()
    self:emit('jump')
    -- 【blue_soul.lua】起跳 = 沿**逆重力方向**给一个瞬时冲量 HEART_JUMP_STRENGTH = 180 px/s
    self.soul.vx = (self.soul.vx or 0) - gx * HEART_JUMP
    self.soul.vy = (self.soul.vy or 0) - gy * HEART_JUMP
    self.soul.grounded = false
    self.soul.jumpBase = self.soul.y          -- 起跳点（算上升高度）
    self.soul.jumping = true
    self.soul.jumpCut = false        -- 本次跳跃还没被「松手」剪断
    self.soul.jumpHeldT = 0
  end
end
function Game:press(k, down) self.keys[k] = down and true or false end
function Game:menuMove(d)
  self:emit('menu')
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
    for i, o in ipairs(ACT_OPTIONS) do
      if self.diffKey ~= 'original' or i == 1 then a[#a + 1] = o.name end
    end
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
    -- 【2026-10-07 用户口径】行动行不再显示「结束回合 / 不结束回合」备注（位置不够，改由说明行省去）
    return ''
  end
  if self.sub == 'mercy' then return (idx == 0) and (self.interlude and '接受中场饶恕会死亡' or '他不接受饶恕') or '他不让你走' end
  return ''
end
function Game:subDesc()
  local i = self.subIndex
  if self.sub == 'act' then
    -- 【2026-10-07 用户口径】行动面板不再显示底部「作用说明」（腾出 24px 行区给行名）
    return ''
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
  self:emit('menu')
  if self.state ~= 'sub' then return end
  local n = #self:subRows()
  if n == 0 then return end
  self.subIndex = (self.subIndex + d + n) % n
end
function Game:subBack()
  if self.state ~= 'sub' then return end
  self:log('sub_back kind=' .. tostring(self.sub))
  self.sub = nil; self.state = 'menu'
  self:emit('cancel')
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
    self:emit('heal')
    -- 参考 Battle.xml MenuUseItem：只回复 HP；KR / KR_T 不变。
    -- 蓝血只能按自己的燃烧曲线自然结束，不能被治疗解除。
    self:log('item_used id=' .. it.id .. ' hp=' .. self.hp .. ' left=' .. self:itemCount())
    self.sub = nil; self:afterPlayerTurn(); return
  end
  if self.sub == 'mercy' then
    if i == 0 then
      if self.interlude then
        self.sub = nil; self:finish('fail', 'spared_midpoint')
      elseif self.final and self.diffKey ~= 'original' then
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
  self:emit('confirm')
  if self.interlude then
    if idx == 3 then self:subOpen('mercy'); return end
    if idx == 1 then self:log('menu_act'); self:subOpen('act'); return end
    if idx == 2 then
      self:log('menu_item')
      if self:itemCount() > 0 then self:subOpen('item')
      -- 【第三轮 N4】空背包时把光标移回「攻击」，避免玩家卡在菜单死循环
      else self:log('item_empty'); self:say('（背包是空的）'); self.menuIndex = 0 end
      return
    end
    -- 中场只有完成 FIGHT 才离开；查看和补给仍回到此菜单。
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
  -- 中场的普通行动返回菜单；只有 FIGHT 能继续战斗。
  if self.interlude then self.state = 'menu'; return end
  -- 最后一回合之后没有"下一回合"了：菜单里只剩打 / 饶（结局由 menuChoose 决定）
  if self.final then self.state = 'menu'; return end
  self:startEnemy(self.fightCount or self.round)
end

function Game:stopAttack()
  if self.state ~= 'attack' or self.attackResult ~= nil then return end
  local acc = 1 - math.abs(self.attackCursor - 0.5) * 2
  if self.final then
    self.attackResult = 'hit'; self.attackHold = 1.2
    self:log('sans_hit final=1'); self:say('（他没能闪开）')
  else
    self.fightCount = (self.fightCount or 0) + 1
    if self.interlude then
      self.interlude, self.interludeCompleted = false, true
      self:log('interlude_end')
    end
    self.attackResult = (acc > 0.92) and 'perfect' or 'miss'
    self.attackHold = 1.0
    self:log(string.format('sans_dodge acc=%.2f', acc))
    self.sansDodge = 1
    self:say(LINES.dodge)
  end
end

-- 伤害与 KR
function Game:clampKR()
  -- 参考 Battle.xml 1521-1524：先夹 40，再夹到当前 HP-1；HP=1 时 KR 必然为 0。
  local hadKR = self.kr > 0
  if self.kr > KR_MAX then self.kr = KR_MAX end
  local cap = self.hp - 1
  if cap < 0 then cap = 0 end
  if self.kr > cap then
    if cap == 0 and hadKR and not self.krFloorLogged then
      self.krFloorLogged = true
      self:log('kr_floor hp=' .. self.hp)
    end
    self.kr = cap
  end
  if self.kr <= 0 then
    self.kr = 0
    if hadKR then
      self.krActive = false
      self:log('kr_done hp=' .. self.hp .. ' kr=0')
    end
  end
end

function Game:hurt(kind, karma, src)
  if self.state ~= 'enemy' or self.invuln > 0 then return false end
  self.hp = self.hp - 1
  self.hits = self.hits + 1
  self:emit('hit')
  self.krFloorLogged = false
  -- 参考：首次命中按对象的 Karma 加；同一攻击对象后续只加 2。
  local gain = tonumber(karma) or (src and tonumber(src.karma)) or KR_PER_HIT
  if src and src.karma == nil then src.karma = gain end
  self.kr = self.kr + gain
  self:clampKR()
  self.krActive = self.kr > 0
  if src and src.karma and src.karma >= 3 then src.karma = 2 end
  self.invuln = self.tune.invuln          -- 原作档直接伤害间隔约 0.033 秒。
  self.flash = 0.12
  if kind == 'blue' then self:log('hit_blue hp=' .. self.hp .. ' kr=' .. self.kr)
  elseif kind == 'orange' then self:log('hit_orange hp=' .. self.hp .. ' kr=' .. self.kr)
  else self:log('hit hp=' .. self.hp .. ' kr=' .. self.kr) end
  if self.hp <= 0 then self.hp = 0; self:finish('fail') end
  return true
end
function Game:debugHurt(kind) self.invuln = 0; return self:hurt(kind or 'hit') end

function Game:updateKR(dt)
  self:clampKR()
  if self.kr <= 0 then return end
  if self.hp <= 1 then return end   -- 参考父条件：HP>1 才燃烧
  self.krT = (self.krT or 0) + dt
  local step = krStep(self.kr)
  -- 60fps 下 30/60 帧累计会有约 1e-9 的浮点误差；加一个极小容差，
  -- 保证文档规定的 30 帧 / 60 帧档位能按时结算。
  if self.krT + 1e-9 < step then return end
  -- 参考：每 tick 最多结算一次，结算后 KR_T 直接归零，不做 while 补帧。
  self.krT = 0
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
        x = z.l + laneW * (L + 0.5), w = laneW - FLOOR_BONE_INSET,   -- 宽度 = 道宽 - 内缩
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
  -- 【2026-10-06】每根骨头比它那一道窄 WALL_GAP，缝隙居中 → 相邻两根之间恒有一条能过灵魂的缝。
  local boneW = laneW - WALL_GAP
  if boneW < 10 then boneW = math.max(6, laneW * 0.5) end
  self.walls[#self.walls + 1] = { t = 0, phase = 'warn', lanes = lanes, laneW = laneW,
                                  boneW = boneW,
                                  gapStart = gapStart, gapW = gapW, h = 0, karma = 6 }
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
      -- 【方案A·2026-10-06】内置 blaster 模式也必须吃同一套烘焙外观：
      -- 它绕过 CMD.GasterBlaster 直接 push，漏了 bake 就会在场上混进旧的 12 件参数化骷髅。
      bake = true,
      karma = 10,
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
  self.elapsed = self.elapsed + dt
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
          self:startEnemy(self.fightCount)
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
  -- 【2026-10-06 用户口径】蓝心的输入坐标系**跟着重力方向转**：
  --   W/S = 沿心尖方向（远离重力 / 朝重力），A/D = 垂直于心尖。
  --   dir=1（南）时就是原来的 WASD；dir=0（东、心尖朝右）时 W 向右、S 向左 ——
  --   这正是「ws 对应心尖为正向的左右移动」。红魂不受影响（保持屏幕坐标系）。
  local k = self.keys
  local vx, vy = 0, 0
  -- 【blue_soul.lua】蓝心的横向是「清零垂直分量后直接赋值 ±150」，在蓝心分支里做，
  --   这里跳过，避免叠加成 2 倍位移。
  local blueHere = (self.soul.mode == 'blue' and not self.soul.wall)
  if not blueHere then
  if self.soul.mode == "blue" and not self.soul.wall then
    local DXd = { [0] = 1, [1] = 0, [2] = -1, [3] = 0 }
    local DYd = { [0] = 0, [1] = 1, [2] = 0,  [3] = -1 }
    local d = self.soul.dir or 1
    local gx, gy = DXd[d] or 0, DYd[d] or 1
    local ux, uy = -gx, -gy            -- 「远离重力」= 心尖的反方向
    local rx, ry = gy, -gx             -- 垂直方向（dir=1 时 = +x = 右）
    local fwd = ((k.up and 1 or 0) - (k.down and 1 or 0))
    local side = ((k.right and 1 or 0) - (k.left and 1 or 0))
    vx = ux * fwd + rx * side
    vy = uy * fwd + ry * side
  else
    if k.left then vx = vx - 1 end
    if k.right then vx = vx + 1 end
    if k.up then vy = vy - 1 end
    if k.down then vy = vy + 1 end
  end
  end
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
      if self.soul.slamT > 1.2 then self:endSlam() end
      local DX = { [0]=1, [1]=0, [2]=-1, [3]=0 }
      local DY = { [0]=0, [1]=1, [2]=0,  [3]=-1 }
      local gx = DX[self.soul.dir or 1] or 0
      local gy = DY[self.soul.dir or 1] or 1
      local mf = self.soul.maxFall
      if mf == nil then mf = 750 end    -- 【2026-10-06】0 要保留（钉住）
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
        self:endSlam()
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
          self.soul.y = pf.y - SOUL_CLAMP; self.soul.vy = 0; self.soul.grounded = true
          self:endSlam()
        end
      end
    else
    -- 蓝魂沿当前重力轴积分；反重力方向/确认键起跳。
    -- 按 Battle.xml 的 DownSpeed 分段重力，松键时把上冲速度截到 -30。
    -- 横向用屏幕方向键，取消键将 150 px/s 减半；平台和框边共用支撑面。
    local DXg = { [0] = 1, [1] = 0, [2] = -1, [3] = 0 }
    local DYg = { [0] = 0, [1] = 1, [2] = 0,  [3] = -1 }
    local gdir = self.soul.dir or 1
    local ugx, ugy = DXg[gdir] or 0, DYg[gdir] or 1
    local function alongG(a, b) return (a or 0) * ugx + (b or 0) * ugy end
    local function setAlongG(target)
      local cur = alongG(self.soul.vx, self.soul.vy)
      local dlt = target - cur
      self.soul.vx = (self.soul.vx or 0) + ugx * dlt
      self.soul.vy = (self.soul.vy or 0) + ugy * dlt
    end
    local dsp = alongG(self.soul.vx, self.soul.vy)
    -- ② 松键截断
    if self.soul.jumping and not self.jumpHeld and dsp < -HEART_CUTOFF then
      setAlongG(-HEART_CUTOFF); dsp = -HEART_CUTOFF
    end
    -- ① 分段重力
    local grav = GRAVITY_FALL
    if dsp < -15 then grav = GRAVITY_UP_FAST
    elseif dsp < 30 then grav = GRAVITY_APEX
    elseif dsp < 120 then grav = 450 end
    -- ④ 前方 0.2px 有固体（框边/平台）就不加重力
    local sB, gBx, gBy, sAx = self:groundQuery()
    if (sAx + 0.2) < sB then setAlongG(dsp + grav * dt) end
    -- MaxFallSpeed（默认 750，脚本可改）
    local mf = self.soul.maxFall
    if mf == nil then mf = 750 end      -- 【2026-10-06】0 要保留（钉住）
    local dsp2 = alongG(self.soul.vx, self.soul.vy)
    if dsp2 > mf then setAlongG(mf) end
    -- ③ 横向：清零垂直分量 + 直接赋值
    local hsp = (self.keys and self.keys.cancel) and SOUL_SPEED_SLOW or SOUL_SPEED
    if ugy ~= 0 then
      self.soul.vx = 0
      if self.keys.left ~= self.keys.right then
        self.soul.vx = self.keys.left and -hsp or hsp
      end
    else
      self.soul.vy = 0
      if self.keys.up ~= self.keys.down then
        self.soul.vy = self.keys.up and -hsp or hsp
      end
    end
    -- 位移（1px 步进的碰撞由 groundQuery + 边界钳位等价实现）
    self.soul.x = self.soul.x + self.soul.vx * dt
    self.soul.y = self.soul.y + self.soul.vy * dt
    self.soul.grounded = false
    -- 【统一落地】框边与平台一个模子（对应原版 HeartCheckSolid）：
    --   这里原来是「框底 floorY」+「内置平台 for 循环」两套判定，而**脚本平台**要等
    --   分支之后的循环才判 → 落在空中板子上时下面的复位已经跑过了，jumping 一直留 true，
    --   于是板子上第 2 跳被 Game:jump 的 `if self.soul.jumping then return end` 直接拦掉。
    local surface, gx, gy, soulA, hitPf = self:groundQuery()
    local lead = soulA + SOUL_CLAMP                 -- 灵魂沿重力方向的前缘
    -- 只清「沿重力方向」的速度，保留切向输入（横向走路不该被落地吃掉）
    local va = (self.soul.vx or 0) * gx + (self.soul.vy or 0) * gy
    -- 落地三条件：① 前缘贴到/跨过支撑面（2px 容差）
    --             ② 不是正沿逆重力方向离开（起跳第一帧 va 很负，不能把刚起跳判成落地）
    --             ③ 支撑面在重力方向的前方（避免灵魂在平台**下面**时被吸附）
    if lead >= surface - 2 and va >= -1 then
      -- 必须**吸附到面**（d 正负都要），否则每帧被 fallSpeed 推下去一点，
      -- 累积几帧后支撑面就掉出 2px 容差 → grounded 闪成 false（实测第 3 帧就掉下去）
      local d = surface - lead
      if d ~= 0 then
        self.soul.x = self.soul.x + gx * d
        self.soul.y = self.soul.y + gy * d
      end
      if va > 0 then
        self.soul.vx = self.soul.vx - gx * va
        self.soul.vy = self.soul.vy - gy * va
      end
      self.soul.grounded = true
      -- 站到移动平台上就**随平台一起走**（原作：站上去就被带着，不用一直按方向键）
      if hitPf then
        local pvx = hitPf.vx or ((hitPf.dir == 0 and (hitPf.speed or 0)) or (hitPf.dir == 2 and -(hitPf.speed or 0)) or 0)
        if pvx ~= 0 then
          self.soul.x = clamp(self.soul.x + pvx * dt, self.box.x + SOUL_CLAMP, self.box.x + self.box.w - SOUL_CLAMP)
        end
      end
    end
    -- 【关键】落地复位**只此一处**：框底 / 内置平台 / 脚本平台都走这里
    if self.soul.grounded then
      self.soul.jumping = false; self.soul.jumpCut = false; self.soul.jumpBase = nil; self.soul.jumpBaseBoxY = nil
      self.soul.jumpDone = false; self.soul.jumpHeldT = 0
    end   -- 落地重置变高跳
    end   -- /【A-5】slammed 分支
  else
    -- 【方案 B】红魂永远 4 向自由移动（原版语义）：不再读 soul.maxFall，
    --   MaxFallSpeed 只对蓝魂生效（蓝魂常规分支 / slam 分支各自读取）。
    self.soul.y = clamp(self.soul.y, self.box.y + SOUL_CLAMP, self.box.y + self.box.h - SOUL_CLAMP)
  end
  self.soul.x = clamp(self.soul.x, self.box.x + SOUL_CLAMP, self.box.x + self.box.w - SOUL_CLAMP)
  -- 平台：轴对齐矩形；掉到顶面就站住（vy 归零），从下面/侧面顶到就只被挡住（不伤害）
  --   碰撞源 = 攻击脚本的 world.platforms（Platform/PlatformRepeat）+ 内置 R6 平台
  local prevSoulY = self.prevY
  if prevSoulY == nil then prevSoulY = self.soul.y end
  -- 蓝魂常规物理已经在上面用 groundQuery 统一处理过平台了（含「随平台走」），
  -- 这一段只给**其它模式**兜底：红魂 / 箭头模块（soul.wall）/ 被甩（slammed）。
  -- 原来的顺序 bug 就在这里 —— 脚本平台的落地发生在蓝魂复位**之后**，所以板子上跳不起来。
  if not (self.soul.mode == 'blue' and not self.soul.wall and not self.soul.slammed) then
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
      -- 蓝魂已在物理分支积分 vx/vy；再次叠加 push 会把甩击速度翻倍。
      if self.soul.mode ~= 'blue' then
        self.soul.push = { vx = w.heart.vx or 0, vy = w.heart.vy or 0, t = 0.55 }
      end
      self:emit('slam')
      w.heartVelDirty = false
    end
    -- 箭头模块：soul.wall 跟随脚本，方向跟随 SansBody（箭头）
    self.soul.wall = w.heart.wall and true or nil
    if self.soul.wall then
      local B = w.sans and w.sans.body
      self.soul.wallDir = (B == 'HandRight' and 0) or (B == 'HandDown' and 1)
                          or (B == 'HandLeft' and 2) or (B == 'HandUp' and 3) or self.soul.wallDir
    end
    -- 【2026-10-06 修·真根因】HeartDir / SansSlam 改了 heart.dir 后必须同步给 soul.dir。
    --   旧实现只在 heartVelDirty（仅 SansSlam 置位）时同步 → 脚本里 `HeartDir,0` 完全没生效，
    --   终盘长框段的重力方向一直停在上一次 SansSlam 的 2，蓝心「持续向左」而不是向右坠落。
    --   注意：**不能无条件同步** —— world.heart.dir 的默认值是 0（不是 nil），
    --   无条件同步会把所有竖直重力回合的 dir 改成 0（实测：蓝魂永远不落地、跳不起来）。
    --   所以用脚本侧的脏标记 heartDirDirty 精确触发。
    if w.heartDirDirty then
      self.soul.dir = w.heart.dir or self.soul.dir
      w.heartDirDirty = false
    end
    if w.heartModeDirty then
      if w.heart.mode == 1 then
        self.soul.mode = 'blue'
      else
        -- 【2026-10-07 修】切回红心必须是“完整复位”，不能只改颜色：
        --   阶段③最后一次 SansSlam 会把 dir 留在 2（尖朝左）、slammed 留在 true。
        --   旧代码只写 soul.mode='red'，于是旋转龙骨炮阶段虽然逻辑上已是红魂，
        --   画出来的心仍按 dir=2 旋转，看起来/手感仍像蓝心。这里恢复初始红心状态：
        --   dir=1（尖朝下）、无甩击、无残余冲量、速度清零。
        self.soul.mode = 'red'
        self.soul.dir = 1
        self.soul.slammed = false
        self.soul.slamT = nil
        self.soul.push = nil
        self.soul.vx, self.soul.vy = 0, 0
        w.heart.slammed = false
        w.heart.dir = 1
        w.heartDirDirty = false
      end
      -- 【2026-10-06】0/负值都是有意义的终端速度（0=钉住、负=反向走廊），不能当 nil；
      --   但只有在脚本真的设过（heartMaxFallDirty）时才写 soul —— world 默认值为 0。
      if w.heartMaxFallDirty then
        self.soul.maxFall = w.heart.maxFall
        w.heartMaxFallDirty = false
      end
      w.heartModeDirty = false
    end
    w.heart.x = self.soul.x + BOX_OFF_X
    w.heart.y = self.soul.y + BOX_OFF_Y
    w.heart.mode = (self.soul.mode == 'blue') and 1 or 0
    -- EndAttack 标记保留到帧末，不在这里切换成内置生成器。
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
  -- 有攻击 CSV 时只推进脚本；内置生成器供无脚本的练习入口使用。
  local scriptOwnsRound = self.world ~= nil and self.world.script ~= nil
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
        else bn.lethal = bn.phase ~= 'warn' and (bn.cur or 0) > 0 end
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
    -- 保留 ended 标记，帧末统一 endEnemy；不能提前清空导致收尾分支失效。
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
            self:hurt('hit', bn.karma or 6, bn)
          end
        elseif bn.kind == 'blue' then
          local orange = (bn.color == 'orange')
          local white = (bn.color == 'white' or bn.color == 0 or bn.color == nil)
          -- C6/C19：蓝骨只惩罚「移动」，橙骨只惩罚「静止」；白骨与移动无关（原作 Color 0）
          local rc = { x = bn.x, y = bn.y, w = bn.w, h = bn.h }
          if white then
            if rectHit(SX, SY, SOUL_R, rc) then
              if self:hurt('hit', bn.karma or 6, bn) then bn.hitDone = true end
            end
          elseif orange then
            if not moved and rectHit(SX, SY, SOUL_R, rc) then
              if self:hurt('orange', bn.karma or 6, bn) then bn.hitDone = true end
            end
          else
            if moved and rectHit(SX, SY, SOUL_R, rc) then
              if self:hurt('blue', bn.karma or 6, bn) then bn.hitDone = true end
            end
          end
        elseif bn.kind == 'floor' then
          local rc = { x = bn.x - bn.w / 2, y = bn.y - bn.h, w = bn.w, h = bn.h }
          if rectHit(SX, SY, SOUL_R, rc) then self:hurt('hit', bn.karma or 6, bn) end
        elseif bn.kind == 'slide' then
          local rc = { x = bn.x, y = bn.y, w = bn.w, h = bn.h }
          if rectHit(SX, SY, SOUL_R, rc) then self:hurt('hit', bn.karma or 6, bn) end
        elseif bn.kind == 'sine' then
          if sineHitTest(bn, SX, SY, SOUL_R) then self:hurt('hit', bn.karma or 6, bn) end
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
              if moved then self:hurt('blue', bn.karma or 6, bn) end
            elseif c == 2 then
              if not moved then self:hurt('orange', bn.karma or 6, bn) end
            else
              self:hurt('hit', bn.karma or 6, bn)
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
            -- 【与渲染同口径】骨头窄于道宽并居中 → 缝也能钻
            local bw = W.boneW or W.laneW
            local rc = { x = self.box.x + L * W.laneW + (W.laneW - bw) / 2,
                         y = self.box.y + self.box.h - W.h,
                         w = bw, h = W.h }
            if rectHit(self.soul.x, self.soul.y, SOUL_R, rc) then self:hurt('hit', W.karma or 6, W) end
          end
        end
      end
    end
    -- 正弦骨：**独立实体表**（w.sine，不在 w.bones 里），必须单独判定。
    -- 之前只判了 w.bones，于是正弦骨从来不打人（视觉有、判定没有）。
    for _, sn in ipairs(w2.sine) do
      if self.state ~= 'enemy' then break end
      if sineHitTest(sn, SX, SY, SOUL_R) then self:hurt('hit', sn.karma or 6, sn) end
    end
    for _, B in ipairs(w2.blasters) do
      -- 【差距文档 P-06】原版 GasterBlastHit 只在 STATE_LEAVE 且 GasterBlast1.Opacity>80 时才失效；
    -- 也就是「淡出开始后、透明度还比较高」的那一小段仍然会打人（避免看起来被扫到却不掉血）。
    local beamLethal = (B.state == 'fire') or ((B.state == 'fade' or B.state == 'done') and beamAlpha(B) > 0.8)
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
          local muzzle = 32 * (B.scale or 1)
          local mx, my = B.x + math.cos(rad) * muzzle, B.y + math.sin(rad) * muzzle
          local dx, dy = math.cos(rad) * BLASTER_BEAM_LEN, math.sin(rad) * BLASTER_BEAM_LEN
          local px, py = SX - mx, SY - my
          local len2 = dx * dx + dy * dy
          local t = (len2 > 0) and ((px * dx + py * dy) / len2) or 0
          if t < 0 then t = 0 elseif t > 1 then t = 1 end
          local nx, ny = mx + dx * t, my + dy * t
          local dist = math.sqrt((SX - nx) * (SX - nx) + (SY - ny) * (SY - ny))
          local bw = (B.band or BLASTER_W[1]) * beamWidth(B)
          if dist <= bw / 2 + SOUL_R then self:hurt('hit', B.karma or 10, B) end
          band = nil
        end
        if band and rectHit(SX, SY, SOUL_R, band) then self:hurt('hit', B.karma or 10, B) end   -- 内置模式仍用 band
      end
    end
    end   -- /outside 守卫
  end

  if self.soul.grounded then self.soul.groundT = 0 else self.soul.groundT = (self.soul.groundT or 99) + dt end
  self.prevX, self.prevY = self.soul.x, self.soul.y
  self.invuln = math.max(0, self.invuln - dt)

  -- 同一帧既命中致死又执行 EndAttack 时，失败优先，不能再改回菜单。
  if self.state ~= 'enemy' then return end

  -- 【差距文档第二轮 G13】脚本调用 EndAttack 后**立即**收尾（留 0.2s 淡出），
  -- 不再傻等 enemyDur 走完（旧行为：终盘/骨刺关打完还要空等十几秒）。
  if self.world and self.world.ended and self.enemyT > 0.2 then
    self:endEnemy()
    return
  end
  -- 【2026-10-06 用户口径·重点】不能再让「单回合时长」把还没播完的脚本掐掉：
  --   ① startEnemy 里把 enemyDur 放宽到 need + 2.5s（见那里）；
  --   ② 这里仍是**上限**语义 —— 但脚本一旦 EndAttack，上面的 world.ended 分支会立刻收尾，
  --      所以 2.5s 余量只是防「simulateLength 低估」，不会变成每回合空等。
  if not (self.world and self.world.script) and self.enemyT >= self.enemyDur then self:endEnemy() end
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
  -- 蓝心跳跃用：适配层在蓝魂态把 up/down 掩成 false，只保留按下沿；按住状态走这个字段。
  -- 【R3/J5】确认键（Enter/Z/J）同样是「跳跃键」：它触发起跳（下面 e.confirm），
  -- 但如果这里不认它，同一帧的蓝魂物理会立刻把刚起跳的 vy 覆盖成 fallSpeed，
  -- 灵魂原地落回板子 —— 探针里 confirm=true 的「第 1 跳 vy=0」就是这个原因。
  local jumpKey = ({ [0] = 'left', [1] = 'up', [2] = 'right', [3] = 'down' })[self.soul.dir or 1]
  self.jumpHeld = (input.jumpHeld or input.confirm or input[jumpKey]) and true or false
  if self.state == 'result' then
    -- 结算在左、重开在右；默认仍选重开，保留原确认键重开手感。
    if e.left or e.right then self.resultIndex = 1 - (self.resultIndex or 1) end
    if e.confirm then
      if (self.resultIndex or 1) == 0 then self:settle() else self:restart() end
    end
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
    if (e.confirm or e[jumpKey]) and self.soul.mode == 'blue' then self:jump() end
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
    local fire = (g2.state == 'fire' or g2.state == 'done') and 1 or 0
    local alpha = 1
    if g2.state == 'charge' then alpha = 0.55
    elseif g2.state == 'fade' or g2.state == 'done' then
      alpha = beamAlpha(g2)
    end
    local ang = g2.ang or 0
    local dir = math.floor(((ang % 360) + 360) % 360 / 90 + 0.5) % 4
    push(cmds, { kind = 'blaster', x = x, y = y, dir = dir, ang = ang, size = g2.size,
                 endX = g2.ex, endY = g2.ey,
                 bake = g2.bake and true or nil, lod = g2.lod,
                 w = (g2.band or BLASTER_W[(g2.size or 0) + 1] or BLASTER_W[1]) * (fire > 0 and beamWidth(g2) or 1), scale = g2.scale or 1,
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
    push(cmds, { kind = 'resultEmblem', x = 320, y = 238, size = 40, failed = g.result == 'fail' })
    local t = (g.result == 'victory') and '胜 利 结 算'
              or ((g.result == 'fail') and 'GAME OVER'
              or ((g.result == 'spare') and '饶 恕 结 局' or '击 倒 结 局'))
    push(cmds, { kind = 'hudText', text = t, x = VW / 2, y = 145, size = 36,
                 color = (g.result == 'fail') and '#ff2d2d' or '#ffcc33', align = 'center' })
    push(cmds, { kind = 'menu', x = VW / 2 - 140, y = 220, w = 130, gap = 20, h = 36,
                 items = { '结 算', '重 开' }, index = (g.resultIndex or 1), visible = true })
    push(cmds, { kind = 'hudText',
                 text = g.settleStatus == 'sent' and '已请求结算，等待服务器结束关卡'
                   or (g.settleStatus == 'failed' and '结算发送失败：选择结算可重试')
                   or (((g.resultIndex or 1) == 0) and '确认键：请求结算' or '确认键：重新开始'),
                 x = VW / 2, y = 280, size = 12, color = '#bbbbbb', align = 'center' })
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
                 lanes = W.lanes, boneW = W.boneW, gapStart = W.gapStart, gapW = W.gapW,
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
               dir = (g.soul and g.soul.dir) or 1,
               invuln = invuln, visible = not blink })
  -- HUD —— 位置照参考实现（BTS 的 Background 图层）：HP 文字 y≈402、血条 y≈416、按钮行 y=432。
  -- 也就是整行**紧贴选项栏上方**，不再占用屏幕顶部（顶部只留 Sans 的台词）。
  -- 左侧 = LV / HP / 血条 / KR，右侧 = ROUND / 难度；中间留白给 Sans 本人（世界 x≈288..352）。
  local hudY = 403
  push(cmds, { kind = 'hudBackdrop', x = 0, y = hudY - 3, w = VW, h = 24 })
  push(cmds, { kind = 'hudText', text = 'LV 19', x = 20, y = hudY, size = 12, color = '#ffffff', align = 'left' })
  push(cmds, { kind = 'hudText', text = 'HP ' .. g.hp .. '/' .. g.maxHP, x = 84, y = hudY, size = 12, color = '#ffffff', align = 'left' })
  push(cmds, { kind = 'hudBar', x = 168, y = hudY + 1, w = 96, h = 11, hp = g.hp, kr = g.kr, max = g.maxHP })
  push(cmds, { kind = 'hudText', text = 'KR ' .. math.floor(g.kr + 0.5), x = 272, y = hudY, size = 12, color = '#c9a3ff', align = 'left' })
  push(cmds, { kind = 'hudText', text = 'FIGHT ' .. (g.fightCount or 0) .. ' / 23', x = VW - 150, y = hudY, size = 12, color = '#ffffff', align = 'right' })
  push(cmds, { kind = 'hudText', text = '难度 ' .. (g.tune and g.tune.label or '普通'), x = VW - 20, y = hudY + 1, size = 11, color = '#8a8a8a', align = 'right' })
  push(cmds, { kind = 'hudBackdrop', x = 0, y = 12, w = VW, h = 24 })
  push(cmds, { kind = 'hudText', text = utf8sub(g.line, g.lineShown), x = VW / 2, y = 16, size = 14, color = '#ffffff', align = 'center' })
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
      local desc = g:subDesc()
      local pad = 8
      local px, py = boxAbs.x + pad, boxAbs.y + pad
      local pw = boxAbs.w - pad * 2
      local ph = boxAbs.h - pad * 2
      -- 【2026-10-07 用户口径】描述（回血量等）改到**面板右上角**（与标题同一行）绘制，
      --   不再占底部的 24px ⇒ 行区恒为 ph-34，列表能多放一行/行高更舒展。
      local head = 34
      local rowSpace = math.max(0, ph - head)
      -- 【方案甲·滚动视窗】先按 18px/行算出最多能放几行 → 再据此均分行高；
      --   view < 总数时用 top 决定视窗首行，且让选中项始终落在视窗内（↑↓ 即可滚动，不需要新按键）。
      local view = math.min(#rows, math.max(1, math.floor(rowSpace / 18)))
      if view < 1 then view = 1 end
      local rowH = clamp(math.floor(rowSpace / math.max(1, view)), 18, 40)
      local top = 0
      if #rows > view then top = clamp(g.subIndex - view + 1, 0, #rows - view) end
      push(cmds, { kind = 'sub', x = px, y = py, w = pw, h = ph,
                   rowH = rowH, title = SUB_TITLE[g.sub] or '', rows = rows, index = g.subIndex,
                   top = top, view = view, total = #rows,
                   notes = (function()
                     local n = {}
                     for i = 0, #rows - 1 do n[i + 1] = g:subRowNote(i) end
                     return n
                   end)(),
                   desc = desc })
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
  g.trainingItems = opts.trainingItems == true
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
  g:applyInput(input)
  dt = dt == nil and DT or dt
  if type(dt) ~= 'number' or dt ~= dt or dt < 0 or dt == math.huge then dt = 0 end
  -- 固定 60Hz：30/60/120fps 都执行同样的碰撞与 KR；严重卡顿最多追赶 0.25s。
  g.accumulator = (g.accumulator or 0) + math.min(dt, 0.25)
  while g.accumulator + 1e-9 >= DT do
    g.accumulator = math.max(0, g.accumulator - DT)
    g:update(DT)
    if g.state == 'result' then g.accumulator = 0; break end
  end
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
function M.settle(g) g:settle() end
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
M.KR_PER_HIT, M.KR_TIERS, M.krStep, M.MAX_HP = KR_PER_HIT, KR_TIERS, krStep, MAX_HP
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


end)()

__modules['default_import_file/workspace/sans-fight/lua/attacks'] = (function()
-- 数据来源：https://github.com/Jcw87/c2-sans-fight/tree/master/Files
-- CSV 保持下载时的原文；无中轴销毁、加宽光束或额外停留时间。
local M = {
  { name = "sans_bluebone", csv = [==[
0,CombatZoneResize,133,251,508,391,TLResume,
0,HeartTeleport,320,376,,,,
0,HeartMode,1,,,,,
0,TLPause,,,,,,
0.2,BoneV,503,286,100,2,300,1
0.23333,BoneV,503,366,20,2,300,0
0.5,BoneV,503,286,100,2,300,1
0.23333,BoneV,503,366,20,2,300,0
0.5,BoneV,503,286,100,2,300,1
0.23333,BoneV,503,366,20,2,300,0
0.93333,BoneV,128,366,20,0,300,0
0.4,BoneV,128,286,100,0,300,1
0.33333,BoneV,128,366,20,0,300,0
0.4,BoneV,128,286,100,0,300,1
0.33333,BoneV,128,366,20,0,300,0
0.4,BoneV,128,286,100,0,300,1
1.66666,EndAttack,,,,,,

]==] },
  { name = "sans_bonegap1", csv = [==[
0,CombatZoneResize,133,251,508,391,TLResume,,
0,HeartTeleport,320,376,,,,,
0,HeartMode,1,,,,,,
0,TLPause,,,,,,,
0.2,BoneVRepeat,128,257,95,0,180,8,120
0,BoneVRepeat,128,366,20,0,180,8,120
0,BoneVRepeat,503,257,95,2,180,8,120
0,BoneVRepeat,503,366,20,2,180,8,120
6.4,EndAttack,,,,,,,

]==] },
  { name = "sans_bonegap1fast", csv = [==[
0,CombatZoneResize,133,251,508,391,TLResume,,
0,HeartTeleport,320,376,,,,,
0,HeartMode,1,,,,,,
0,TLPause,,,,,,,
0.4,BoneVRepeat,128,257,95,0,210,8,133
0,BoneVRepeat,128,366,20,0,210,8,133
0,BoneVRepeat,503,257,95,2,210,8,133
0,BoneVRepeat,503,366,20,2,210,8,133
6,EndAttack,,,,,,,

]==] },
  { name = "sans_bonegap2", csv = [==[
0,CombatZoneResize,133,251,508,391,TLResume
0,HeartTeleport,320,376,,,
0,HeartMode,1,,,,
0,TLPause,,,,,
0,SET,Total,0,,,
0,:Begin,,,,,
0,JMPNL,End,$Total,150,,
0,RND,Choice,4,,,
0,MUL,Jump,$Choice,3,,
0,ADD,Jump,$Jump,1,,
0,JMPREL,$Jump,,,,
0,SET,HeightB,20,,,
0,ADD,Total,$Total,9,,
0,JMPREL,9,,,,
0,SET,HeightB,30,,,
0,ADD,Total,$Total,11,,
0,JMPREL,6,,,,
0,SET,HeightB,40,,,
0,ADD,Total,$Total,19,,
0,JMPREL,3,,,,
0,SET,HeightB,60,,,
0,ADD,Total,$Total,25,,
0,RND,RndSpeed,3,,,
0,SUB,RndSpeed,$RndSpeed,1,,
0,MUL,RndSpeed,$RndSpeed,2,,
0,JMPNE,SkipZeroSpeed,$HeightB,40,,
0,SET,RndSpeed,0,,,
0,:SkipZeroSpeed,,,,,
0,SUB,HeightT,111,$HeightB,,
0,SUB,YB,386,$HeightB,,
0,ADD,X,$Total,32,,
0,JMPNE,BoneL,$HeightB,60,,
0,SET,RndSpeed,-1,,,
0,:BoneL,,,,,
0,ADD,SpeedL,8,$RndSpeed,,
0,MUL,XL,$X,$SpeedL,,
0,SUB,XL,320,$XL,,
0,MUL,SpeedL,$SpeedL,30,,
0,JMPE,BoneR,$HeightB,60,,
0,MUL,RndSpeed,$RndSpeed,-1,,
0,:BoneR,,,,,
0,ADD,SpeedR,8,$RndSpeed,,
0,MUL,XR,$X,$SpeedR,,
0,ADD,XR,320,$XR,,
0,MUL,SpeedR,$SpeedR,30,,
0,BoneV,$XL,257,$HeightT,0,$SpeedL
0,BoneV,$XL,$YB,$HeightB,0,$SpeedL
0,BoneV,$XR,257,$HeightT,2,$SpeedR
0,BoneV,$XR,$YB,$HeightB,2,$SpeedR
0,MUL,Jump,$Choice,2,,
0,ADD,Jump,$Jump,1,,
0,JMPREL,$Jump,,,,
0,ADD,Total,$Total,15,,
0,JMPREL,6,,,,
0,ADD,Total,$Total,17,,
0,JMPREL,4,,,,
0,ADD,Total,$Total,19,,
0,JMPREL,2,,,,
0,ADD,Total,$Total,25,,
0,JMPABS,Begin,,,,
0,:End,,,,,
7,EndAttack,,,,,

]==] },
  { name = "sans_boneslideh", csv = [==[
0,CombatZoneResize,133,251,508,391,TLResume,,
0,HeartTeleport,320,376,,,,,
0,HeartMode,1,,,,,,
0,TLPause,,,,,,,
0.5,BoneVRepeat,128,366,20,0,120,8,76
0,BoneVRepeat,513,257,107,2,120,8,76
7.2,EndAttack,,,,,,,

]==] },
  { name = "sans_boneslidev", csv = [==[
0,CombatZoneResize,241,226,406,391,TLResume,,
0,HeartTeleport,320,304,,,,,
0,HeartMode,0,,,,,,
0,TLPause,,,,,,,
0.2,BoneHRepeat,130,-10,200,1,300,7,183
0,BoneHRepeat,330,650,200,3,300,7,183
5.76666,EndAttack,,,,,,,

]==] },
  { name = "sans_bonestab1", csv = [==[
0,CombatZoneResize,241,226,406,391,TLResume
0,HeartTeleport,320,304,,,
0,HeartMode,0,,,,
0,TLPause,,,,,
0,SET,Loop,9,,,
0,JMPZ,26,$Loop,,,
0,SUB,Loop,$Loop,1,,
0,RND,Direction,4,,,
0,ADD,Jump,$Direction,1,,
0,JMPREL,$Jump,,,,
0,JMPREL,4,,,,
0,JMPREL,5,,,,
0,JMPREL,6,,,,
0,JMPREL,7,,,,
0,SansBody,HandRight,,,,
0,JMPREL,7,,,,
0,SansBody,HandDown,,,,
0,JMPREL,5,,,,
0,SansBody,HandLeft,,,,
0,JMPREL,3,,,,
0,SansBody,HandUp,,,,
0,JMPREL,1,,,,
0.26666,SansSlam,$Direction,,,,
0.2,BoneStab,$Direction,25,0.4,0.33333,
0.6,JMPABS,6,,,,
0,EndAttack,,,,,

]==] },
  { name = "sans_bonestab2", csv = [==[
0,CombatZoneResize,241,226,406,391,TLResume
0,HeartTeleport,320,304,,,
0,HeartMode,0,,,,
0,TLPause,,,,,
0,SET,Loop,9,,,
0,JMPZ,26,$Loop,,,
0,SUB,Loop,$Loop,1,,
0,RND,Direction,4,,,
0,ADD,Jump,$Direction,1,,
0,JMPREL,$Jump,,,,
0,JMPREL,4,,,,
0,JMPREL,5,,,,
0,JMPREL,6,,,,
0,JMPREL,7,,,,
0,SansBody,HandRight,,,,
0,JMPREL,7,,,,
0,SansBody,HandDown,,,,
0,JMPREL,5,,,,
0,SansBody,HandLeft,,,,
0,JMPREL,3,,,,
0,SansBody,HandUp,,,,
0,JMPREL,1,,,,
0.26666,SansSlam,$Direction,,,,
0.2,BoneStab,$Direction,25,0.3,0.2,
0.43333,JMPABS,6,,,,
0,EndAttack,,,,,

]==] },
  { name = "sans_bonestab3", csv = [==[
0,CombatZoneResize,241,226,406,391,TLResume
0,HeartTeleport,320,304,,,
0,HeartMode,0,,,,
0,TLPause,,,,,
0,SET,Loop,9,,,
0,JMPZ,26,$Loop,,,
0,SUB,Loop,$Loop,1,,
0,RND,Direction,4,,,
0,ADD,Jump,$Direction,1,,
0,JMPREL,$Jump,,,,
0,JMPREL,4,,,,
0,JMPREL,5,,,,
0,JMPREL,6,,,,
0,JMPREL,7,,,,
0,SansBody,HandRight,,,,
0,JMPREL,7,,,,
0,SansBody,HandDown,,,,
0,JMPREL,5,,,,
0,SansBody,HandLeft,,,,
0,JMPREL,3,,,,
0,SansBody,HandUp,,,,
0,JMPREL,1,,,,
0.26666,SansSlam,$Direction,,,,
0.2,BoneStab,$Direction,29,0.4,0,
0.23333,JMPABS,6,,,,
0,EndAttack,,,,,

]==] },
  { name = "final", csv = [==[
0,CombatZoneResize,241,226,406,391,TLResume,,,
0,HeartTeleport,320,304,,,,,,
0,HeartMode,0,,,,,,,
0,TLPause,,,,,,,,
0,SansSweat,0,,,,,,,
0,SET,I,0,,,,,,
0.3,RND,Direction,4,,,,,,
0,ADD,Jump,$Direction,1,,,,,
0,JMPREL,$Jump,,,,,,,
0,JMPREL,4,,,,,,,
0,JMPREL,5,,,,,,,
0,JMPREL,6,,,,,,,
0,JMPREL,7,,,,,,,
0,SansBody,HandRight,,,,,,,
0,JMPREL,7,,,,,,,
0,SansBody,HandDown,,,,,,,
0,JMPREL,5,,,,,,,
0,SansBody,HandLeft,,,,,,,
0,JMPREL,3,,,,,,,
0,SansBody,HandUp,,,,,,,
0,JMPREL,1,,,,,,,
0.26666,SansSlam,$Direction,,,,,,,
0.2,BoneStab,$Direction,29,0.4,0,,,,
0,ADD,I,$I,1,,,,,
0,JMPL,7,$I,4,,,,,
0,BoneHRepeat,130,-10,200,1,300,3,183,
0,BoneHRepeat,330,650,200,3,300,3,183,
0.5,HeartMode,0,,,,,,,
2,SansBody,HandLeft,,,,,,,
0.2,SansSlam,2,,,,,,,
0.3,SansBody,HandRight,,,,,,,
0.2,HeartMaxFallSpeed,450,,,,,,,
0,SansSlam,0,,,,,,,
0,CombatZoneResizeInstant,241,226,449,391,,,,
0,CombatZoneSpeed,900,,,,,,,
0,CombatZoneResize,241,226,650,391,,,,
0.33333,HeartMaxFallSpeed,-300,,,,,,,
0,SansAnimation,Idle,,,,,,,
0,SansRepeat,,,,,,,,
0,CombatZoneResize,-10,226,650,391,,,,
0.3,CombatZoneSpeed,30,,,,,,,
0,CombatZoneResize,-10,264,650,369,,,,
0.9,GetHeartPos,HeartX,HeartY,,,,,,
0,HeartTeleport,40,$HeartY,,,,,,
0,HeartMaxFallSpeed,0,,,,,,,
0,SansSlam,0,,,,,,,
0,DIV,Deg,180,$pi,,,,,
0,SET,I,0,,,,,,
0,DIV,Ang,$I,2,,,,,
0,MUL,Ang,$Ang,$Deg,,,,,
0,SIN,Sine,$Ang,,,,,,
0,MUL,Sine,$Sine,25,,,,,
0,FLOOR,Sine,$Sine,,,,,,
0,MUL,X,$I,60,,,,,
0,ADD,X,$X,634,,,,,
0,SET,Y,270,,,,,,
0,ADD,H,30,$Sine,,,,,
0,BoneV,$X,$Y,$H,2,900,,,
0,ADD,Y,$Y,$H,,,,,
0,ADD,Y,$Y,34,,,,,
0,SUB,H,364,$Y,,,,,
0,BoneV,$X,$Y,$H,2,900,,,
0,ADD,I,$I,1,,,,,
0,JMPL,49,$I,44,,,,,
0,ADD,X,$X,360,,,,,
0,BoneVRepeat,$X,270,50,2,900,3,15,
0,ADD,X,$X,330,,,,,
0,BoneVRepeat,$X,314,50,2,900,3,15,
0,ADD,X,$X,300,,,,,
0,BoneVRepeat,$X,270,50,2,900,3,15,
0,ADD,X,$X,300,,,,,
0,BoneVRepeat,$X,314,50,2,900,3,15,
0,ADD,X,$X,270,,,,,
0,BoneVRepeat,$X,270,50,2,900,3,15,
0,ADD,X,$X,270,,,,,
0,BoneVRepeat,$X,314,50,2,900,3,15,
0,ADD,X,$X,240,,,,,
0,BoneVRepeat,$X,270,50,2,900,3,15,
0,ADD,X,$X,330,,,,,
0,BoneVRepeat,$X,314,50,2,900,3,15,
0,ADD,X,$X,270,,,,,
0,BoneVRepeat,$X,270,50,2,900,3,15,
0,ADD,X,$X,390,,,,,
0,SET,I,0,,,,,,
0,MUL,X2,$I,30,,,,,
0,ADD,X2,$X2,$X,,,,,
0,ADD,H,10,$I,,,,,
0,BoneV,$X2,270,$H,2,900,,,
0,SUB,Y,365,$H,,,,,
0,BoneV,$X2,$Y,$H,2,900,,,
0,ADD,I,$I,1,,,,,
0,JMPL,85,$I,24,,,,,
0,SET,I,0,,,,,,
8,HeartMaxFallSpeed,330,,,,,,,
0,SansSlam,0,,,,,,,
0,CombatZoneSpeed,540,,,,,,,
0,CombatZoneResize,-10,264,410,369,,,,
0.9,SansEndRepeat,,,,,,,,
0,SansHead,Default,,,,,,,
0,SansTorso,Default,,,,,,,
0,SansBody,HandLeft,,,,,,,
0.2,BoneStab,0,50,0.4,1,,,,
0.9,BlackScreen,1,,,,,,,
0,Sound,Flash,,,,,,,
0.4,BlackScreen,0,,,,,,,
0,Sound,Flash,,,,,,,
0,CombatZoneResizeInstant,239,226,404,391,,,,
0,HeartTeleport,320,376,,,,,,
0,HeartMode,1,,,,,,,
0,SansAnimation,HeadBob,,,,,,,
0.03333,BoneStab,1,48,0.6,1,,,,
0,BoneStab,3,48,0.6,1,,,,
0.9,BlackScreen,1,,,,,,,
0,Sound,Flash,,,,,,,
0.1,BlackScreen,0,,,,,,,
0,Sound,Flash,,,,,,,
0,HeartTeleport,262,240,,,,,,
0,SansSlam,3,,,,,,,
0.03333,BoneStab,2,48,0.6,1,,,,
0,BoneStab,3,48,0.6,1,,,,
0.9,BlackScreen,1,,,,,,,
0,Sound,Flash,,,,,,,
0.1,BlackScreen,0,,,,,,,
0,Sound,Flash,,,,,,,
0,HeartTeleport,391,376,,,,,,
0,SansSlam,0,,,,,,,
0.03333,BoneStab,0,48,0.6,1,,,,
0,BoneStab,1,48,0.6,1,,,,
0.9,BlackScreen,1,,,,,,,
0,Sound,Flash,,,,,,,
0.1,BlackScreen,0,,,,,,,
0,Sound,Flash,,,,,,,
0,HeartTeleport,262,240,,,,,,
0,SansSlam,2,,,,,,,
0,SansX,320,,,,,,,
0.03333,BoneStab,2,48,0.6,1,,,,
0.7,HeartMode,0,,,,,,,
0,SET,gt,0,,,,,,
0,SET,gin,1,,,,,,
0,MUL,Ang,$gt,-10,,,,,
0,COS,X,$Ang,,,,,,
0,SIN,Y,$Ang,,,,,,
0,MUL,EndX,$X,150,,,,,
0,MUL,EndY,$Y,150,,,,,
0,MUL,X,$EndX,3,,,,,
0,MUL,Y,$EndY,3,,,,,
0,ADD,X,$X,320,,,,,
0,ADD,Y,$Y,306,,,,,
0,ADD,EndX,$EndX,320,,,,,
0,ADD,EndY,$EndY,306,,,,,
0,ADD,Ang,$Ang,180,,,,,
0,GasterBlaster,0,$X,$Y,$EndX,$EndY,$Ang,0.5,0
0,ADD,gt,$gt,$gin,,,,,
0,JMPNL,156,$gin,1.7,,,,,
0,ADD,gin,$gin,0.015,,,,,
0.06666,JMPL,140,$gt,190,,,,,
1,SansHead,BlueEye,,,,,,,
0,HeartMaxFallSpeed,750,,,,,,,
0,SansBody,HandRight,,,,,,,
0,SansSlamDamage,1,,,,,,,
0,SET,I,0,,,,,,
0,SET,Direction,0,,,,,,
0,SET,LastDir,2,,,,,,
0,SET,Wait1,0.13333,,,,,,
0,SET,Wait2,0.13333,,,,,,
0,JMPNE,168,$Direction,$LastDir,,,,,
0,SUB,Direction,$Direction,2,,,,,
0,JMPNL,170,$Direction,0,,,,,
0,ADD,Direction,$Direction,4,,,,,
0,JMPL,172,$Direction,4,,,,,
0,SUB,Direction,$Direction,4,,,,,
0,MUL,Jump,$Direction,2,,,,,
0,ADD,Jump,$Jump,1,,,,,
0,JMPREL,$Jump,,,,,,,
0,SansBody,HandRight,,,,,,,
0,JMPREL,6,,,,,,,
0,SansBody,HandDown,,,,,,,
0,JMPREL,4,,,,,,,
0,SansBody,HandLeft,,,,,,,
0,JMPREL,2,,,,,,,
0,SansBody,HandUp,,,,,,,
$Wait1,SansSlam,$Direction,,,,,,,
$Wait2,SET,LastDir,$Direction,,,,,,
0,MOD,Odd,$I,2,,,,,
0,JMPZ,187,$Odd,,,,,,
0,RND,Direction,4,,,,,,
0,JMPNE,191,$I,21,,,,,
0,HeartMaxFallSpeed,480,,,,,,,
0,SET,Wait1,0.2,,,,,,
0,SET,Wait2,0.2,,,,,,
0,JMPNE,194,$I,25,,,,,
0,SansHead,Default,,,,,,,
0,SansSweat,1,,,,,,,
0,JMPNE,200,$I,33,,,,,
0,SansHead,Tired1,,,,,,,
0,SansSweat,2,,,,,,,
0,HeartMaxFallSpeed,330,,,,,,,
0,SET,Wait1,0.5,,,,,,
0,SET,Wait2,1.1,,,,,,
0,JMPNE,203,$I,33,,,,,
0,JMPE,186,$Direction,1,,,,,
0,JMPE,186,$Direction,$LastDir,,,,,
0,JMPNE,206,$I,35,,,,,
0,HeartMaxFallSpeed,240,,,,,,,
0,SET,Direction,3,,,,,,
0,JMPNE,210,$I,36,,,,,
0,SansHead,Tired2,,,,,,,
0,SansSweat,3,,,,,,,
0,HeartMaxFallSpeed,60,,,,,,,
0,ADD,I,$I,1,,,,,
0,JMPL,166,$I,38,,,,,
1.5,SansAnimation,Tired,,,,,,,
2.4,EndAttack,,,,,,,,

]==] },
  { name = "sans_intro", csv = [==[
0,SansAnimation,,,,,,,,
0,SansHead,ClosedEyes,,,,,,,
0,SansText,ready?,,,,,,,
0,BlackScreen,1,,,,,,,
0,Sound,Flash,,,,,,,
0.06666,BlackScreen,0,,,,,,,
0,Sound,Flash,,,,,,,
0,CombatZoneResizeInstant,239,226,404,391,,,,
0,HeartTeleport,320,304,,,,,,
0,HeartMode,0,,,,,,,
0,SansBody,HandDown,,,,,,,
0,SansHead,BlueEye,,,,,,,
0,Sound,GasterBlaster,1.4,,,,,,
0.26666,SansSlam,1,,,,,,,
0.5,SansBody,HandUp,,,,,,,
0,SansHead,NoEyes,,,,,,,
0,BoneStab,1,54,0.16666,1,,,,
0.7,HeartMode,0,,,,,,,
0,SansBody,HandRight,,,,,,,
0,Sound,Ding,,,,,,,
0.4,Sound,GasterBlaster,1.4,,,,,,
0.4,SineBones,20,-24,360,25,,,,
1.1,SansAnimation,,,,,,,,
0,GasterBlaster,1,0,0,189,246,0,0.333,0.26666
0,GasterBlaster,1,0,0,259,166,90,0.333,0.26666
0,GasterBlaster,1,640,480,449,366,180,0.333,0.26666
0,GasterBlaster,1,640,480,379,446,270,0.333,0.26666
0.9,GasterBlaster,1,0,0,189,176,45,0.333,0.26666
0,GasterBlaster,1,640,0,449,176,135,0.333,0.26666
0,GasterBlaster,1,640,480,449,436,225,0.333,0.26666
0,GasterBlaster,1,0,480,189,436,315,0.333,0.26666
0.9,GasterBlaster,1,0,0,189,246,0,0.333,0.26666
0,GasterBlaster,1,0,0,259,166,90,0.333,0.26666
0,GasterBlaster,1,640,480,449,366,180,0.333,0.26666
0,GasterBlaster,1,640,480,379,446,270,0.333,0.26666
0.7,GasterBlaster,2,0,240,139,306,0,0.666,0.5
0,GasterBlaster,2,640,240,499,306,180,0.666,0.5
3,SansHead,Default,,,,,,,
0,SansText,here we go.,,,,,,,
0,EndAttack,,,,,,,,

]==] },
  { name = "multi1", csv = [==[
0,CombatZoneResize,133,251,508,391,TLResume,,
0,HeartTeleport,320,304,,,,,
0,HeartMode,1,,,,,,
0,TLPause,,,,,,,
0,SET,Loop,5,,,,,
0,:RndAttack,,,,,,,
0,BlackScreen,1,,,,,,
0,Sound,Flash,,,,,,
0.4,BlackScreen,0,,,,,,
0,Sound,Flash,,,,,,
0,JMPZ,End,$Loop,,,,,
0,SUB,Loop,$Loop,1,,,,
0,RND,Jump,5,,,,,
0,ADD,Jump,$Jump,1,,,,
0,JMPREL,$Jump,,,,,,
0,JMPABS,Attack0,,,,,,
0,JMPABS,Attack1,,,,,,
0,JMPABS,Attack2,,,,,,
0,JMPABS,Attack3,,,,,,
0,JMPABS,Attack4,,,,,,
0,:Attack0,,,,,,,
0,CombatZoneResizeInstant,121,276,526,391,,,
0,HeartMode,1,,,,,,
0,HeartTeleport,320,376,,,,,
0,BoneVRepeat,128,341,45,0,240,4,16
0,BoneV,64,286,100,0,240,,
0,BoneVRepeat,512,341,45,2,240,4,16
0,BoneV,576,286,100,2,240,,
0.9,JMPABS,RndAttack,,,,,,
0,:Attack1,,,,,,,
0,CombatZoneResizeInstant,121,276,526,391,,,
0,HeartMode,1,,,,,,
0,HeartTeleport,320,376,,,,,
0,BoneV,128,286,100,0,240,1,
0,BoneV,56,366,20,0,240,0,
0,BoneV,24,286,100,0,240,0,
0,BoneV,512,286,100,2,240,1,
0,BoneV,584,366,20,2,240,0,
0,BoneV,616,286,100,2,240,0,
1.1,JMPABS,RndAttack,,,,,,
0,:Attack2,,,,,,,
0,CombatZoneResizeInstant,171,276,476,391,,,
0,HeartMode,1,,,,,,
0,HeartTeleport,320,376,,,,,
0,SET,Total,0,,,,,
0,SET,Loop2,0,,,,,
0,:Attack2Begin,,,,,,,
0,RND,Choice,3,,,,,
0,ADD,HeightB,$Choice,2,,,,
0,MUL,HeightB,$HeightB,10,,,,
0,SET,RndSpeed,0,,,,,
0,JMPZ,SkipRndSpeed,$Loop2,,,,,
0,RND,RndSpeed,3,,,,,
0,SUB,RndSpeed,$RndSpeed,1,,,,
0,MUL,RndSpeed,$RndSpeed,2,,,,
0,:SkipRndSpeed,,,,,,,
0,SUB,HeightT,86,$HeightB,,,,
0,SUB,YB,386,$HeightB,,,,
0,MUL,X,$Loop2,22,,,,
0,ADD,X,$X,25,,,,
0,ADD,X,$X,$Total,,,,
0,ADD,SpeedL,6,$RndSpeed,,,,
0,MUL,XL,$X,$SpeedL,,,,
0,SUB,XL,320,$XL,,,,
0,MUL,SpeedL,$SpeedL,30,,,,
0,MUL,RndSpeed,$RndSpeed,-1,,,,
0,ADD,SpeedR,6,$RndSpeed,,,,
0,MUL,XR,$X,$SpeedR,,,,
0,ADD,XR,320,$XR,,,,
0,MUL,SpeedR,$SpeedR,30,,,,
0,BoneV,$XL,282,$HeightT,0,$SpeedL,,
0,BoneV,$XL,$YB,$HeightB,0,$SpeedL,,
0,BoneV,$XR,282,$HeightT,2,$SpeedR,,
0,BoneV,$XR,$YB,$HeightB,2,$SpeedR,,
0,MUL,TotalInc,$Choice,5,,,,
0,ADD,Total,$Total,$TotalInc,,,,
0,ADD,Loop2,$Loop2,1,,,,
0,JMPL,Attack2Begin,$Loop2,4,,,,
1.9,JMPABS,RndAttack,,,,,,
0,:Attack3,,,,,,,
0,CombatZoneResizeInstant,171,276,476,391,,,
0,HeartMode,1,,,,,,
0,HeartTeleport,320,376,,,,,
0,BoneVRepeat,200,282,70,0,150,3,125
0,BoneVRepeat,200,371,15,0,150,3,125
0,BoneVRepeat,440,282,70,2,150,3,125
0,BoneVRepeat,440,371,15,2,150,3,125
1.7,JMPABS,RndAttack,,,,,,
0,:Attack4,,,,,,,
0,CombatZoneResizeInstant,121,276,526,391,,,
0,HeartMode,1,,,,,,
0,RND,Side,2,,,,,
0,JMPZ,Attack4Other,$Side,,,,,
0,HeartTeleport,506,376,,,,,
0,BoneVRepeat,200,331,55,0,360,11,24
0,BoneVRepeat,-64,371,15,0,360,10,24
1.5,JMPABS,RndAttack,,,,,,
0,:Attack4Other,,,,,,,
0,HeartTeleport,149,376,,,,,
0,BoneVRepeat,440,331,55,2,360,11,24
0,BoneVRepeat,704,371,15,2,360,10,24
1.5,JMPABS,RndAttack,,,,,,
0,:End,,,,,,,
0,CombatZoneResizeInstant,33,251,608,391,,,
0,EndAttack,,,,,,,

]==] },
  { name = "multi2", csv = [==[
0,HeartTeleport,320,304,,,,,,
0,SET,Loop,5,,,,,,
0,:RndAttack,,,,,,,,
0,BlackScreen,1,,,,,,,
0,Sound,Flash,,,,,,,
0.4,BlackScreen,0,,,,,,,
0,Sound,Flash,,,,,,,
0,JMPZ,End,$Loop,,,,,,
0,SUB,Loop,$Loop,1,,,,,
0,RND,Jump,4,,,,,,
0,ADD,Jump,$Jump,1,,,,,
0,JMPREL,$Jump,,,,,,,
0,JMPABS,Attack5,,,,,,,
0,JMPABS,Attack6,,,,,,,
0,JMPABS,Attack7,,,,,,,
0,JMPABS,Attack8,,,,,,,
0,:Attack5,,,,,,,,
0,CombatZoneResizeInstant,121,276,526,391,,,,
0,HeartMode,1,,,,,,,
0,HeartTeleport,330,304,,,,,,
0,Platform,309,314,41,0,0,,,
0,Platform,309,354,41,0,0,,,
0,BoneVRepeat,121,364,30,2,0,25,16,
0,RND,Side,2,,,,,,
0,JMPZ,Attack5Other,$Side,,,,,,
0,BoneV,521,280,35,2,240,,,
0,BoneV,1,319,65,0,240,,,
1.5,JMPABS,RndAttack,,,,,,,
0,:Attack5Other,,,,,,,,
0,BoneV,119,280,35,0,240,,,
0,BoneV,639,319,65,2,240,,,
1.5,JMPABS,RndAttack,,,,,,,
0,:Attack6,,,,,,,,
0,CombatZoneResizeInstant,241,226,406,391,,,,
0,HeartMode,0,,,,,,,
0,HeartTeleport,320,304,,,,,,
0,RND,Rot,2,,,,,,
0,JMPZ,Attack6Other,$Rot,,,,,,
0,GasterBlaster,1,191,306,191,306,0,0.6,0.26666
0,GasterBlaster,1,321,166,321,166,90,0.6,0.26666
0,GasterBlaster,1,449,306,449,306,180,0.6,0.26666
0,GasterBlaster,1,321,446,321,446,270,0.6,0.26666
1.2,JMPABS,RndAttack,,,,,,,
0,:Attack6Other,,,,,,,,
0,GasterBlaster,1,191,176,191,176,45,0.66666,0.26666
0,GasterBlaster,1,451,176,451,176,135,0.66666,0.26666
0,GasterBlaster,1,451,436,451,436,225,0.66666,0.26666
0,GasterBlaster,1,191,436,191,436,315,0.66666,0.26666
1.2,JMPABS,RndAttack,,,,,,,
0,:Attack7,,,,,,,,
0,CombatZoneResizeInstant,179,226,404,391,,,,
0,HeartMode,0,,,,,,,
0,RND,Side,2,,,,,,
0,JMPZ,Attack7Other,$Side,,,,,,
0,HeartTeleport,382,304,,,,,,
0,SineBones,16,-20,300,55,,,,
1.7,JMPABS,RndAttack,,,,,,,
0,:Attack7Other,,,,,,,,
0,HeartTeleport,267,304,,,,,,
0,SineBones,16,20,300,55,,,,
1.7,JMPABS,RndAttack,,,,,,,
0,:Attack8,,,,,,,,
0,CombatZoneResizeInstant,121,276,526,391,,,,
0,HeartMode,1,,,,,,,
0,RND,Side,2,,,,,,
0,JMPZ,Attack8Other,$Side,,,,,,
0,HeartTeleport,489,376,,,,,,
0,BoneVRepeat,345,364,20,0,120,6,76,
0,BoneVRepeat,297,280,82,2,120,6,76,
1.9,JMPABS,RndAttack,,,,,,,
0,:Attack8Other,,,,,,,,
0,HeartTeleport,168,376,,,,,,
0,BoneVRepeat,297,364,20,2,120,6,76,
0,BoneVRepeat,345,280,82,0,120,6,76,
1.9,JMPABS,RndAttack,,,,,,,
0,:End,,,,,,,,
0,CombatZoneResizeInstant,33,251,608,391,,,,
0,EndAttack,,,,,,,,

]==] },
  { name = "multi3", csv = [==[
0,CombatZoneResize,239,226,404,391,TLResume,,,
0,HeartTeleport,320,304,,,,,,
0,HeartMode,0,,,,,,,
0,TLPause,,,,,,,,
0,SET,Loop,5,,,,,,
0,:RndAttack,,,,,,,,
0,BlackScreen,1,,,,,,,
0,Sound,Flash,,,,,,,
0.13333,BlackScreen,0,,,,,,,
0,Sound,Flash,,,,,,,
0,JMPZ,End,$Loop,,,,,,
0,SUB,Loop,$Loop,1,,,,,
0,RND,Jump,9,,,,,,
0,ADD,Jump,$Jump,1,,,,,
0,JMPREL,$Jump,,,,,,,
0,JMPABS,Attack0,,,,,,,
0,JMPABS,Attack1,,,,,,,
0,JMPABS,Attack2,,,,,,,
0,JMPABS,Attack3,,,,,,,
0,JMPABS,Attack4,,,,,,,
0,JMPABS,Attack5,,,,,,,
0,JMPABS,Attack6,,,,,,,
0,JMPABS,Attack7,,,,,,,
0,JMPABS,Attack8,,,,,,,
0,:Attack0,,,,,,,,
0,CombatZoneResizeInstant,121,276,526,391,,,,
0,HeartMode,1,,,,,,,
0,HeartTeleport,320,376,,,,,,
0,BoneVRepeat,128,341,45,0,240,4,16,
0,BoneV,64,286,100,0,240,,,
0,BoneVRepeat,512,341,45,2,240,4,16,
0,BoneV,576,286,100,2,240,,,
0.9,JMPABS,RndAttack,,,,,,,
0,:Attack1,,,,,,,,
0,CombatZoneResizeInstant,121,276,526,391,,,,
0,HeartMode,1,,,,,,,
0,HeartTeleport,320,376,,,,,,
0,BoneV,128,286,100,0,240,1,,
0,BoneV,56,366,20,0,240,0,,
0,BoneV,24,286,100,0,240,0,,
0,BoneV,512,286,100,2,240,1,,
0,BoneV,584,366,20,2,240,0,,
0,BoneV,616,286,100,2,240,0,,
1.1,JMPABS,RndAttack,,,,,,,
0,:Attack2,,,,,,,,
0,CombatZoneResizeInstant,171,276,476,391,,,,
0,HeartMode,1,,,,,,,
0,HeartTeleport,320,376,,,,,,
0,SET,Total,0,,,,,,
0,SET,Loop2,0,,,,,,
0,:Attack2Begin,,,,,,,,
0,RND,Choice,3,,,,,,
0,ADD,HeightB,$Choice,2,,,,,
0,MUL,HeightB,$HeightB,10,,,,,
0,SET,RndSpeed,0,,,,,,
0,JMPZ,SkipRndSpeed,$Loop2,,,,,,
0,RND,RndSpeed,3,,,,,,
0,SUB,RndSpeed,$RndSpeed,1,,,,,
0,MUL,RndSpeed,$RndSpeed,2,,,,,
0,:SkipRndSpeed,,,,,,,,
0,SUB,HeightT,86,$HeightB,,,,,
0,SUB,YB,386,$HeightB,,,,,
0,MUL,X,$Loop2,22,,,,,
0,ADD,X,$X,25,,,,,
0,ADD,X,$X,$Total,,,,,
0,ADD,SpeedL,6,$RndSpeed,,,,,
0,MUL,XL,$X,$SpeedL,,,,,
0,SUB,XL,320,$XL,,,,,
0,MUL,SpeedL,$SpeedL,30,,,,,
0,MUL,RndSpeed,$RndSpeed,-1,,,,,
0,ADD,SpeedR,6,$RndSpeed,,,,,
0,MUL,XR,$X,$SpeedR,,,,,
0,ADD,XR,320,$XR,,,,,
0,MUL,SpeedR,$SpeedR,30,,,,,
0,BoneV,$XL,282,$HeightT,0,$SpeedL,,,
0,BoneV,$XL,$YB,$HeightB,0,$SpeedL,,,
0,BoneV,$XR,282,$HeightT,2,$SpeedR,,,
0,BoneV,$XR,$YB,$HeightB,2,$SpeedR,,,
0,MUL,TotalInc,$Choice,5,,,,,
0,ADD,Total,$Total,$TotalInc,,,,,
0,ADD,Loop2,$Loop2,1,,,,,
0,JMPL,Attack2Begin,$Loop2,4,,,,,
1.9,JMPABS,RndAttack,,,,,,,
0,:Attack3,,,,,,,,
0,CombatZoneResizeInstant,171,276,476,391,,,,
0,HeartMode,1,,,,,,,
0,HeartTeleport,320,376,,,,,,
0,BoneVRepeat,200,282,70,0,150,3,125,
0,BoneVRepeat,200,371,15,0,150,3,125,
0,BoneVRepeat,440,282,70,2,150,3,125,
0,BoneVRepeat,440,371,15,2,150,3,125,
1.7,JMPABS,RndAttack,,,,,,,
0,:Attack4,,,,,,,,
0,CombatZoneResizeInstant,121,276,526,391,,,,
0,HeartMode,1,,,,,,,
0,RND,Side,2,,,,,,
0,JMPZ,Attack4Other,$Side,,,,,,
0,HeartTeleport,506,376,,,,,,
0,BoneVRepeat,200,331,55,0,360,11,24,
0,BoneVRepeat,-64,371,15,0,360,10,24,
1.5,JMPABS,RndAttack,,,,,,,
0,:Attack4Other,,,,,,,,
0,HeartTeleport,149,376,,,,,,
0,BoneVRepeat,440,331,55,2,360,11,24,
0,BoneVRepeat,704,371,15,2,360,10,24,
1.5,JMPABS,RndAttack,,,,,,,
0,:Attack5,,,,,,,,
0,CombatZoneResizeInstant,121,276,526,391,,,,
0,HeartMode,1,,,,,,,
0,HeartTeleport,330,304,,,,,,
0,Platform,309,314,41,0,0,,,
0,Platform,309,354,41,0,0,,,
0,BoneVRepeat,121,364,30,2,0,25,16,
0,RND,Side,2,,,,,,
0,JMPZ,Attack5Other,$Side,,,,,,
0,BoneV,521,280,35,2,240,,,
0,BoneV,1,319,65,0,240,,,
1.5,JMPABS,RndAttack,,,,,,,
0,:Attack5Other,,,,,,,,
0,BoneV,119,280,35,0,240,,,
0,BoneV,639,319,65,2,240,,,
1.5,JMPABS,RndAttack,,,,,,,
0,:Attack6,,,,,,,,
0,CombatZoneResizeInstant,241,226,406,391,,,,
0,HeartMode,0,,,,,,,
0,HeartTeleport,320,304,,,,,,
0,RND,Rot,2,,,,,,
0,JMPZ,Attack6Other,$Rot,,,,,,
0,GasterBlaster,1,191,306,191,306,0,0.6,0.26666
0,GasterBlaster,1,321,166,321,166,90,0.6,0.26666
0,GasterBlaster,1,449,306,449,306,180,0.6,0.26666
0,GasterBlaster,1,321,446,321,446,270,0.6,0.26666
1.2,JMPABS,RndAttack,,,,,,,
0,:Attack6Other,,,,,,,,
0,GasterBlaster,1,191,176,191,176,45,0.66666,0.26666
0,GasterBlaster,1,451,176,451,176,135,0.66666,0.26666
0,GasterBlaster,1,451,436,451,436,225,0.66666,0.26666
0,GasterBlaster,1,191,436,191,436,315,0.66666,0.26666
1.2,JMPABS,RndAttack,,,,,,,
0,:Attack7,,,,,,,,
0,CombatZoneResizeInstant,179,226,404,391,,,,
0,HeartMode,0,,,,,,,
0,RND,Side,2,,,,,,
0,JMPZ,Attack7Other,$Side,,,,,,
0,HeartTeleport,382,304,,,,,,
0,SineBones,16,-20,300,55,,,,
1.7,JMPABS,RndAttack,,,,,,,
0,:Attack7Other,,,,,,,,
0,HeartTeleport,267,304,,,,,,
0,SineBones,16,20,300,55,,,,
1.7,JMPABS,RndAttack,,,,,,,
0,:Attack8,,,,,,,,
0,CombatZoneResizeInstant,121,276,526,391,,,,
0,HeartMode,1,,,,,,,
0,RND,Side,2,,,,,,
0,JMPZ,Attack8Other,$Side,,,,,,
0,HeartTeleport,489,376,,,,,,
0,BoneVRepeat,345,364,20,0,120,6,76,
0,BoneVRepeat,297,280,82,2,120,6,76,
1.9,JMPABS,RndAttack,,,,,,,
0,:Attack8Other,,,,,,,,
0,HeartTeleport,168,376,,,,,,
0,BoneVRepeat,297,364,20,2,120,6,76,
0,BoneVRepeat,345,280,82,0,120,6,76,
1.9,JMPABS,RndAttack,,,,,,,
0,:End,,,,,,,,
0,CombatZoneResizeInstant,33,251,608,391,,,,
0,EndAttack,,,,,,,,

]==] },
  { name = "platformblaster", csv = [==[
0,CombatZoneResize,133,251,508,391,TLResume,,,
0,HeartTeleport,320,376,,,,,,
0,HeartMode,1,,,,,,,
0,TLPause,,,,,,,,
0,PlatformRepeat,552,346,51,2,120,8,140,
0,PlatformRepeat,-20,306,51,0,120,8,160,
0,SET,Loop,5,,,,,,
0,SUB,Loop,$Loop,1,,,,,
0,RND,Y,3,,,,,,
0,MUL,Y,$Y,40,,,,,
0,ADD,Y,$Y,285,,,,,
0,GasterBlaster,0,0,0,73,$Y,0,0.56666,0.1
0.9,RND,Y,3,,,,,,
0,MUL,Y,$Y,40,,,,,
0,ADD,Y,$Y,285,,,,,
0,GasterBlaster,0,640,0,563,$Y,180,0.56666,0.1
0.9,JMPNZ,8,$Loop,,,,,,
0,EndAttack,,,,,,,,

]==] },
  { name = "platformblasterfast", csv = [==[
0,CombatZoneResize,133,251,508,391,TLResume,,,
0,HeartTeleport,320,376,,,,,,
0,HeartMode,1,,,,,,,
0,TLPause,,,,,,,,
0,PlatformRepeat,552,346,51,2,120,8,140,
0,PlatformRepeat,-20,306,51,0,120,8,160,
0,SET,Loop,6,,,,,,
0,SUB,Loop,$Loop,1,,,,,
0,RND,Y,3,,,,,,
0,MUL,Y,$Y,40,,,,,
0,ADD,Y,$Y,285,,,,,
0,GasterBlaster,0,0,0,73,$Y,0,0.56666,0.1
0.7,RND,Y,3,,,,,,
0,MUL,Y,$Y,40,,,,,
0,ADD,Y,$Y,285,,,,,
0,GasterBlaster,0,640,0,563,$Y,180,0.56666,0.1
0.7,JMPNZ,8,$Loop,,,,,,
0,EndAttack,,,,,,,,

]==] },
  { name = "platforms1", csv = [==[
0,CombatZoneResize,133,251,508,391,TLResume,,
0,HeartTeleport,320,376,,,,,
0,HeartMode,1,,,,,,
0,TLPause,,,,,,,
0,Platform,15,346,61,0,120,,
0.4,BoneVRepeat,133,356,40,0,120,41,15
1.2,Platform,-61,346,61,0,150,,
1.7,Platform,-61,346,61,0,180,,
1,BoneV,133,257,45,0,210,,
0,BoneV,119,257,45,0,210,,
0,BoneV,105,257,45,0,210,,
2.3,BoneV,133,257,95,0,270,,
1.7,EndAttack,,,,,,,

]==] },
  { name = "platforms2", csv = [==[
0,CombatZoneResize,133,251,508,391,TLResume,,
0,HeartTeleport,320,376,,,,,
0,HeartMode,1,,,,,,
0,TLPause,,,,,,,
0,Platform,640,346,51,2,150,,
0.4,BoneVRepeat,508,356,40,2,120,58,15
0.4,Platform,640,296,51,2,150,,
0.5,Platform,640,346,51,2,150,,
0.4,BoneV,508,316,70,2,150,,
0.4,Platform,640,296,31,2,60,,
0.6,Platform,640,326,51,2,150,,
0.7,Platform,640,336,51,2,150,,
0.3,BoneV,508,257,45,2,150,,
0.4,Platform,640,316,51,2,150,,
0.3,BoneV,508,257,55,2,150,,
0.7,BoneV,508,257,35,2,150,,
1.5,BoneV,133,257,95,0,90,,
0.7,BoneV,508,276,110,2,240,,
2.5,EndAttack,,,,,,,

]==] },
  { name = "platforms3", csv = [==[
0,CombatZoneResize,133,251,508,391,TLResume,,
0,HeartTeleport,320,376,,,,,
0,HeartMode,1,,,,,,
0,TLPause,,,,,,,
0,PlatformRepeat,513,346,121,2,120,5,220
0,PlatformRepeat,-71,306,161,0,120,4,280
0,SET,Loop,16,,,,,
0,JMPZ,22,$Loop,,,,,
0,SUB,Loop,$Loop,1,,,,
0,RND,Jump,3,,,,,
0,ADD,Jump,$Jump,1,,,,
0,JMPREL,$Jump,,,,,,
0,JMPREL,3,,,,,,
0,JMPREL,4,,,,,,
0,JMPREL,5,,,,,,
0,BoneV,517,257,45,2,120,,
0.5,JMPABS,8,,,,,,
0,BoneV,125,306,40,0,120,,
0.5,JMPABS,8,,,,,,
0,BoneV,517,349,35,2,120,,
0.5,JMPABS,8,,,,,,
0,EndAttack,,,,,,,

]==] },
  { name = "platforms4", csv = [==[
0,CombatZoneResize,113,231,548,391,TLResume,,
0,HeartTeleport,320,376,,,,,
0,HeartMode,1,,,,,,
0,TLPause,,,,,,,
0,Platform,151,336,41,0,90,1,
0,HeartTeleport,175,327,,,,,
0,BoneVRepeat,528,366,40,0,60,60,15
0,BoneVRepeat,283,267,40,3,90,11,85
0,BoneVRepeat,363,331,40,1,120,13,95
0,BoneVRepeat,443,248,40,3,90,11,85
7.3,EndAttack,,,,,,,

]==] },
  { name = "platforms4hard", csv = [==[
0,CombatZoneResize,113,231,548,391,TLResume,,
0,HeartTeleport,320,376,,,,,
0,HeartMode,1,,,,,,
0,TLPause,,,,,,,
0,Platform,151,336,31,0,90,1,
0,HeartTeleport,175,327,,,,,
0,BoneVRepeat,528,366,40,0,60,60,15
0,BoneVRepeat,283,268,40,3,90,12,65
0,BoneVRepeat,363,325,40,1,120,11,90
0,BoneVRepeat,443,268,40,3,90,12,65
7.3,EndAttack,,,,,,,

]==] },
  { name = "randomblaster1", csv = [==[
0,CombatZoneResize,121,186,526,391,TLResume,,,
0,HeartTeleport,320,304,,,,,,
0,HeartMode,0,,,,,,,
0,TLPause,,,,,,,,
0.5,SET,Loop,15,,,,,,
0,SUB,Loop,$Loop,1,,,,,
0,RND,Ang,360,,,,,,
0,COS,X,$Ang,,,,,,
0,SIN,Y,$Ang,,,,,,
0,MUL,EndX,$X,200,,,,,
0,MUL,EndY,$Y,200,,,,,
0,MUL,X,$X,400,,,,,
0,MUL,Y,$Y,300,,,,,
0,GetHeartPos,HeartX,HeartY,,,,,,
0,ADD,EndX,$EndX,$HeartX,,,,,
0,ADD,EndY,$EndY,$HeartY,,,,,
0,ADD,X,$X,$HeartX,,,,,
0,ADD,Y,$Y,$HeartY,,,,,
0,JMPNL,21,$EndX,50,,,,,
0,SET,EndX,50,,,,,,
0,JMPNG,23,$EndX,590,,,,,
0,SET,EndX,590,,,,,,
0,JMPNL,25,$EndY,40,,,,,
0,SET,EndY,40,,,,,,
0,JMPNG,27,$EndY,440,,,,,
0,SET,EndY,440,,,,,,
0,ANGLE,Ang,$EndX,$EndY,$HeartX,$HeartY,,,
0,GasterBlaster,0,$X,$Y,$EndX,$EndY,$Ang,0.46666,0.03333
0.53333,JMPNZ,6,$Loop,,,,,,
0,EndAttack,,,,,,,,

]==] },
  { name = "randomblaster2", csv = [==[
0,CombatZoneResize,121,186,526,391,TLResume,,,
0,HeartTeleport,320,304,,,,,,
0,HeartMode,0,,,,,,,
0,TLPause,,,,,,,,
0.4,SET,Loop,12,,,,,,
0,SUB,Loop,$Loop,1,,,,,
0,RND,Ang,360,,,,,,
0,COS,X,$Ang,,,,,,
0,SIN,Y,$Ang,,,,,,
0,MUL,EndX,$X,200,,,,,
0,MUL,EndY,$Y,200,,,,,
0,MUL,X,$X,400,,,,,
0,MUL,Y,$Y,300,,,,,
0,GetHeartPos,HeartX,HeartY,,,,,,
0,ADD,EndX,$EndX,$HeartX,,,,,
0,ADD,EndY,$EndY,$HeartY,,,,,
0,ADD,X,$X,$HeartX,,,,,
0,ADD,Y,$Y,$HeartY,,,,,
0,JMPNL,21,$EndX,50,,,,,
0,SET,EndX,50,,,,,,
0,JMPNG,23,$EndX,590,,,,,
0,SET,EndX,590,,,,,,
0,JMPNL,25,$EndY,40,,,,,
0,SET,EndY,40,,,,,,
0,JMPNG,27,$EndY,440,,,,,
0,SET,EndY,440,,,,,,
0,ANGLE,Ang,$EndX,$EndY,$HeartX,$HeartY,,,
0,GasterBlaster,1,$X,$Y,$EndX,$EndY,$Ang,0.66666,0.03333
0.66666,JMPNZ,6,$Loop,,,,,,
0,EndAttack,,,,,,,,

]==] },
  { name = "sans_spare", csv = [==[
0,CombatZoneResize,133,251,508,391,TLResume
0,HeartTeleport,320,376,,,
0,HeartMode,1,,,,
0,TLPause,,,,,
0.3,EndAttack,,,,,

]==] },
}
return M

end)()

__modules['default_import_file/workspace/sans-fight/lua/fitdata'] = (function()
-- CodeArt: 几何配方生成像素矩形；不读取 PNG、SVG 或外部纹理。
-- 接口 {w,h,rects={{x,y,w,h,c},...}}；Y 向下，颜色 0xAARRGGBB。
-- 自包含，可直接由 tools/build.py 打包；纯色矩形仍使用平台的预设图元。
local M = {}
local WHITE,BLACK,RED,BLUE,ORANGE = 0xFFFFFFFF,0xFF000000,0xFFFF2B2B,0xFF63B0FF,0xFFFF7A18
local CYAN,GREEN,YELLOW,PURPLE = 0xFF00D9FF,0xFF00FF00,0xFFFFD200,0xFF9B5CFF
local function clamp(v,l,h) return math.max(l,math.min(h,v)) end
local function alpha(c,a) return (math.floor(((c>>24)&255)*clamp(a,0,1)+.5)<<24)|(c&0xFFFFFF) end
local function spec(w,h) return {w=w,h=h,rects={}} end
local function rect(s,x,y,w,h,c)
  if w>0 and h>0 and ((c>>24)&255)>0 then s.rects[#s.rects+1]={x=x,y=y,w=w,h=h,c=c} end
end
local function append(s,child,x,y,sx,sy)
  sx,sy=sx or 1,sy or sx or 1
  for _,r in ipairs(child.rects) do rect(s,x+r.x*sx,y+r.y*sy,r.w*sx,r.h*sy,r.c) end
end
-- 配方加载时使用的小画布；战斗帧不逐像素扫描。
local function canvas(w,h) return {w=w,h=h,pixels={}} end
local function fill(p,x,y,w,h,c)
  for yy=math.max(0,math.floor(y)),math.min(p.h-1,math.ceil(y+h)-1) do
    for xx=math.max(0,math.floor(x)),math.min(p.w-1,math.ceil(x+w)-1) do p.pixels[yy*p.w+xx+1]=c end
  end
end
local function polygon(p,points,c)
  for y=0,p.h-1 do
    local scan,crossings,previous=y+.5,{},points[#points]
    for _,current in ipairs(points) do
      local ax,ay,bx,by=previous[1],previous[2],current[1],current[2]
      if (ay<=scan and by>scan) or (by<=scan and ay>scan) then crossings[#crossings+1]=ax+(scan-ay)*(bx-ax)/(by-ay) end
      previous=current
    end
    table.sort(crossings)
    for i=1,#crossings-1,2 do
      local l,r=math.ceil(crossings[i]-.5),math.ceil(crossings[i+1]-.5);fill(p,l,y,r-l,1,c)
    end
  end
end
local function disk(p,cx,cy,rx,ry,c)
  for y=math.max(0,math.floor(cy-ry)),math.min(p.h-1,math.ceil(cy+ry)-1) do
    local dy=(y+.5-cy)/ry
    if math.abs(dy)<=1 then
      local span=rx*math.sqrt(math.max(0,1-dy*dy))
      local l,r=math.ceil(cx-span-.5),math.ceil(cx+span-.5);fill(p,l,y,r-l,1,c)
    end
  end
end
-- 水平游程 + 跨行合并，保留透明孔洞，减少纯色矩形控件。
local function finish(p)
  local s,active=spec(p.w,p.h),{}
  for y=0,p.h-1 do
    local nextActive,x={},0
    while x<p.w do
      local c,l=p.pixels[y*p.w+x+1] or 0,x
      repeat x=x+1 until x==p.w or (p.pixels[y*p.w+x+1] or 0)~=c
      if ((c>>24)&255)>0 then
        local key=l..':'..(x-l)..':'..c;local old=active[key]
        if old then old.h=old.h+1;nextActive[key]=old
        else local r={x=l,y=y,w=x-l,h=1,c=c};s.rects[#s.rects+1],nextActive[key]=r,r end
      end
    end
    active=nextActive
  end
  return s
end
local function rotate90(s,turns)
  for _=1,turns%4 do
    local n=spec(s.h,s.w)
    for _,r in ipairs(s.rects) do rect(n,s.h-r.y-r.h,r.x,r.h,r.w,r.c) end
    s=n
  end
  return s
end
-- 宽颅骨、双眼窝、鼻孔和逐颗牙。状态只改五官。
local function sansHead(expression)
  local p=canvas(32,30)
  polygon(p,{{8,1},{24,1},{28,3},{30,7},{31,17},{29,22},{26,26},{22,29},{10,29},{6,26},{3,22},{1,17},{2,7},{4,3}},WHITE)
  fill(p,5,11,8,7,BLACK);fill(p,19,11,8,7,BLACK)
  if expression=='ClosedEyes' then
    fill(p,5,11,8,7,WHITE);fill(p,19,11,8,7,WHITE);fill(p,5,14,8,2,BLACK);fill(p,19,14,8,2,BLACK)
  elseif expression=='Tired1' or expression=='Tired2' or expression=='Sweat' then
    local lid=expression=='Tired2' and 5 or 3
    fill(p,5,11,8,lid,WHITE);fill(p,19,11,8,lid,WHITE);fill(p,9,16,2,1,WHITE);fill(p,21,16,2,1,WHITE)
  elseif expression=='BlueEye' then
    fill(p,8,13,2,3,WHITE);fill(p,21,12,4,5,CYAN);fill(p,22,13,2,3,WHITE)
  elseif expression~='NoEyes' then fill(p,8,13,2,3,WHITE);fill(p,22,13,2,3,WHITE) end
  fill(p,14,17,2,2,BLACK);fill(p,17,17,2,2,BLACK)
  polygon(p,{{5,19},{8,21},{24,21},{27,19},{27,24},{24,26},{8,26},{5,24}},BLACK)
  fill(p,7,22,18,2,WHITE);for x=10,22,4 do fill(p,x,22,1,2,BLACK) end
  if expression=='Tired2' then fill(p,7,24,17,1,WHITE) end
  return finish(p)
end
-- 身体包含外套、T 恤、短裤、腿、拖鞋。抬手与伸手保持脚底锚定。
local function sansBody(pose,tired)
  local side,up=pose=='right' or pose=='left',pose=='up'
  local w,h=side and 96 or 64,up and 94 or 70;local p=canvas(w,h)
  local ox,oy=(w-64)/2,up and 24 or 0;local slouch=tired and 2 or 0
  local function F(x,y,rw,rh,c) fill(p,ox+x,oy+y,rw,rh,c) end
  local function P(points,c) local pts={};for i,v in ipairs(points) do pts[i]={ox+v[1],oy+v[2]} end;polygon(p,pts,c) end
  if up then
    P({{42,10},{46,-15},{50,-18},{55,-12},{51,13}},WHITE);P({{45,10},{49,-13},{52,-12},{48,13}},BLACK)
    F(48,-23,8,9,WHITE);F(52,-24,3,5,WHITE);F(50,-19,1,4,BLACK)
  elseif side then
    P({{45,9},{75,9},{77,14},{68,20},{45,23}},WHITE);P({{48,12},{70,12},{71,14},{67,17},{48,20}},BLACK)
    F(73,8,7,10,WHITE);F(78,9,2,5,WHITE);F(74,12,1,4,BLACK)
  elseif pose=='down' then
    P({{44,9},{53,11},{55,39},{50,44},{44,36}},WHITE);P({{47,12},{51,13},{52,37},{49,39},{47,35}},BLACK)
    F(47,39,9,10,WHITE);F(49,42,1,5,BLACK);F(53,42,1,5,BLACK)
  end
  P({{20,slouch},{44,slouch},{50,5+slouch},{53,28+slouch},{45,38},{19,38},{11,28+slouch},{14,5+slouch}},WHITE)
  P({{20,3+slouch},{44,3+slouch},{47,8+slouch},{49,27+slouch},{43,35},{21,35},{15,27+slouch},{17,8+slouch}},BLACK)
  F(26,5+slouch,12,26-slouch,WHITE);F(29,5+slouch,6,3,BLACK);F(31,10+slouch,2,21-slouch,BLACK)
  F(21,18+slouch,2,12,WHITE);F(41,18+slouch,2,12,WHITE);F(18,28+slouch,6,2,WHITE);F(40,28+slouch,6,2,WHITE)
  F(15,14+slouch,3,11,WHITE)
  if pose=='default' or tired then
    F(17,24+slouch,7,6,WHITE);F(40,24+slouch,7,6,WHITE);F(20,26+slouch,1,3,BLACK);F(43,26+slouch,1,3,BLACK)
  end
  F(19,36,26,16,WHITE);F(21,38,22,12,BLACK);F(30,44,4,9,0)
  F(23,51,7,10,WHITE);F(35,51,7,10,WHITE)
  F(14,62,18,6,WHITE);F(17,60,13,3,WHITE);F(34,62,18,6,WHITE);F(35,60,13,3,WHITE)
  F(14,67,18,2,BLACK);F(34,67,18,2,BLACK)
  return finish(p),{hx=ox+16,hy=oy-24}
end
-- 长吻、双眼窝、后脑双角、双排骨齿。张嘴用下颌位移生成。
local function blaster(open)
  local p,jaw=canvas(57,44),math.floor(open*10+.5)
  polygon(p,{{3,17},{7,8},{14,4},{18,1},{24,1},{23,5},{31,6},{35,2},{39,4},{40,9},{46,12},{52,16},{57,18},{57,22},{49,23},{40,23},{34,27},{20,28},{8,26},{3,22}},WHITE)
  polygon(p,{{9,10},{13,8},{22,9},{26,14},{21,18},{13,17},{9,14}},BLACK)
  polygon(p,{{28,10},{32,9},{39,11},{42,15},{37,18},{30,16}},BLACK)
  fill(p,14,11,3,4,WHITE);fill(p,33,11,3,4,WHITE);polygon(p,{{46,16},{50,17},{53,20},{48,20}},BLACK)
  polygon(p,{{18,22},{33,23},{47,21},{56,21},{56,25+jaw},{42,26+jaw},{31,28+jaw},{17,27}},BLACK)
  polygon(p,{{7,25},{18,26},{30,29+jaw},{45,27+jaw},{56,25+jaw},{55,29+jaw},{44,32+jaw},{28,34+jaw},{14,30},{8,29}},WHITE)
  for x=26,49,6 do fill(p,x,22,3,3,WHITE);fill(p,x,28+jaw,3,3,WHITE) end
  fill(p,9,19,5,2,BLACK);return finish(p)
end
-- 同一配方的多数票采样 LOD；非透明和白骨在同票时优先。
local function lod(s,cell)
  local p=canvas(s.w,s.h);for _,r in ipairs(s.rects) do fill(p,r.x,r.y,r.w,r.h,r.c) end
  local q=canvas(math.ceil(s.w/cell),math.ceil(s.h/cell))
  for y=0,q.h-1 do for x=0,q.w-1 do
    local counts,best,count={},0,0
    for dy=0,cell-1 do for dx=0,cell-1 do
      local px,py=x*cell+dx,y*cell+dy
      if px<s.w and py<s.h then
        local c=p.pixels[py*p.w+px+1] or 0;counts[c]=(counts[c] or 0)+1
        if counts[c]>count or (counts[c]==count and c>best) then best,count=c,counts[c] end
      end
    end end
    fill(q,x,y,1,1,best)
  end end
  local out={}
  for _,r in ipairs(finish(q).rects) do out[#out+1]={x=r.x*cell,y=r.y*cell,w=math.min(r.w*cell,s.w-r.x*cell),h=math.min(r.h*cell,s.h-r.y*cell),c=r.c} end
  return out
end
M.meta={source='codeart geometric recipes',fit='procedural-rects-v1',externalTextures=false,logicalSize={640,480},colorFormat='0xAARRGGBB'}
M.sans_poses,M.sans_body_variants,M.sans_head_keys={},{},{}
for _,pose in ipairs({'default','up','down','left','right'}) do
  local key='sans_body_'..pose;local body,offset=sansBody(pose,false);M[key]=body
  M.sans_poses[pose]={body=key,hx=offset.hx,hy=offset.hy,mirror=pose=='left'}
  M.sans_body_variants[pose..'_tired']=key..'_tired';M[key..'_tired']=sansBody(pose,true)
end
for _,name in ipairs({'Default','BlueEye','ClosedEyes','NoEyes','Tired1','Tired2','Sweat'}) do
  local key='sans_head_'..name:lower();M[key],M.sans_head_keys[name]=sansHead(name),key
end
M.sans_head_default_key='sans_head_default';M.sans_head_blue_key='sans_head_blue';M.sans_head_blue=M.sans_head_blueeye
-- 可单独组合的躯干、腿和汗滴；完整身体仍是旧渲染契约的默认入口。
local function crop(s,x,y,w,h)
  local n=spec(w,h)
  for _,r in ipairs(s.rects) do
    local l,t,rr,b=math.max(x,r.x),math.max(y,r.y),math.min(x+w,r.x+r.w),math.min(y+h,r.y+r.h)
    rect(n,l-x,t-y,rr-l,b-t,r.c)
  end
  return n
end
M.sans_torso_default=crop(M.sans_body_default,0,0,64,36)
M.sans_torso_tired=crop(M.sans_body_default_tired,0,0,64,36)
M.sans_legs_default=crop(M.sans_body_default,0,36,64,34)
do
  local p=canvas(6,10);polygon(p,{{3,0},{6,6},{5,9},{1,9},{0,6}},0xFF8FD8FF);M.sans_sweat=finish(p)
end
M.blaster_default=blaster(0);M.blaster_fire_0=blaster(.3);M.blaster_fire_2=blaster(.65);M.blaster_fire_4=blaster(1)
M.blaster_keys={default='blaster_default',fire={'blaster_fire_0','blaster_fire_2','blaster_fire_4'}}
M.blaster_block2,M.blaster_block3={},{}
for label,key in pairs({Default='blaster_default',fire_0='blaster_fire_0',fire_2='blaster_fire_2',fire_4='blaster_fire_4'}) do M.blaster_block2[label]=lod(M[key],2);M.blaster_block3[label]=lod(M[key],3) end

-- 其余元素的独立配方。返回绘图矩形，不修改碰撞、触摸点击区或玩法。
local A={palette={white=WHITE,black=BLACK,red=RED,blue=BLUE,boneBlue=0xFF2F6BFF,orange=ORANGE,cyan=CYAN,green=GREEN,yellow=YELLOW,purple=PURPLE}};M.codeart=A
function A.heart(c,dir)
  local p=canvas(16,16);polygon(p,{{1,2},{5,2},{8,5},{11,2},{15,2},{16,6},{15,9},{8,16},{1,9},{0,6}},c or RED)
  return rotate90(finish(p),((dir or 1)-1)%4)
end
function A.brokenHeart(c)
  local p=canvas(18,18);for _,r in ipairs(A.heart(c or RED).rects) do fill(p,r.x+1,r.y+1,r.w,r.h,r.c) end
  polygon(p,{{8,1},{10,1},{9,6},{11,8},{8,11},{9,17},{7,17},{6,11},{9,8},{7,6}},0);return finish(p)
end
function A.bone(w,h,c,vertical)
  w,h=math.max(1,math.floor(w)),math.max(1,math.floor(h));c=c or WHITE;if vertical==nil then vertical=h>=w end
  local p,k=canvas(w,h),math.min(w,h)*.6
  if vertical then
    fill(p,(w-k)/2,k/3,k,h-2*k/3,c)
    disk(p,k/2,k/2,k/2,k/2,c);disk(p,w-k/2,k/2,k/2,k/2,c);disk(p,k/2,h-k/2,k/2,k/2,c);disk(p,w-k/2,h-k/2,k/2,k/2,c)
  else
    fill(p,k/3,(h-k)/2,w-2*k/3,k,c)
    disk(p,k/2,k/2,k/2,k/2,c);disk(p,k/2,h-k/2,k/2,k/2,c);disk(p,w-k/2,k/2,k/2,k/2,c);disk(p,w-k/2,h-k/2,k/2,k/2,c)
  end
  return finish(p)
end
function A.warning(w,h,on)
  local s=spec(w,h);if on~=false then for x=0,w-1,12 do rect(s,x,0,math.min(7,w-x),h,alpha(YELLOW,.65)) end end;return s
end
function A.stab(w,h,dir,peek)
  local p=canvas(math.max(1,math.floor(w)),math.max(1,math.floor(h)));local c=peek and alpha(WHITE,.45) or WHITE
  for _,r in ipairs(A.bone(p.w,p.h,c).rects) do fill(p,r.x,r.y,r.w,r.h,r.c) end
  local d=math.min(9,math.max(p.w,p.h))
  if dir==0 then polygon(p,{{p.w-d,0},{p.w,p.h/2},{p.w-d,p.h}},c)
  elseif dir==1 then polygon(p,{{0,p.h-d},{p.w/2,p.h},{p.w,p.h-d}},c)
  elseif dir==2 then polygon(p,{{d,0},{0,p.h/2},{d,p.h}},c)
  else polygon(p,{{0,d},{p.w/2,0},{p.w,d}},c) end
  return finish(p)
end
function A.platform(w,h,c) local s=spec(w,h);rect(s,0,0,w,h,c or GREEN);return s end
function A.frame(w,h,t,c)
  local s=spec(w,h);t=clamp(t or 4,1,math.min(w,h)/2);c=c or WHITE
  rect(s,0,0,w,t,c);rect(s,0,h-t,w,t,c);rect(s,0,t,t,h-2*t,c);rect(s,w-t,t,t,h-2*t,c);return s
end
function A.menuButton(w,h,selected)
  local s=A.frame(w,h,2,selected and YELLOW or ORANGE);if selected then append(s,A.heart(RED),7,(h-16)/2) end
  s.textBox={x=selected and 27 or 7,y=3,w=w-(selected and 34 or 14),h=h-6};return s
end
function A.attackBar(w,h,progress)
  local s=spec(w,h);rect(s,16,h/2-2,w-32,4,WHITE);rect(s,w/2-7,h/2-7,14,14,alpha(GREEN,.75))
  local x=16+clamp(progress or .5,0,1)*(w-32);rect(s,x-3,0,6,h,RED);return s
end
function A.hudBar(w,h,hp,kr,maximum)
  local s=spec(w,h);maximum=math.max(1,maximum or 92);hp=clamp(hp or maximum,0,maximum);kr=clamp(kr or 0,0,math.max(0,hp-1))
  rect(s,0,0,w,h,0xFF2A2A33);rect(s,0,0,w*hp/maximum,h,YELLOW);rect(s,w*(hp-kr)/maximum,0,w*kr/maximum,h,PURPLE);return s
end
function A.flash(w,h,c,a) local s=spec(w,h);rect(s,0,0,w,h,alpha(c or WHITE,a or 1));return s end
function A.beam(w,h,intensity)
  local s=spec(w,h);intensity=intensity or 1
  rect(s,0,0,w,h,alpha(WHITE,intensity*.78));rect(s,0,h*.3,w,h*.4,alpha(WHITE,intensity));return s
end
function A.joystick(radius,dx,dy)
  radius=math.max(8,math.floor(radius or 32));local p=canvas(radius*2,radius*2)
  disk(p,radius,radius,radius,radius,0x66FFFFFF);disk(p,radius,radius,radius-2,radius-2,0x66000000)
  local length=math.sqrt((dx or 0)^2+(dy or 0)^2);local k=length>1 and 1/length or 1
  disk(p,radius+(dx or 0)*k*radius*.55,radius+(dy or 0)*k*radius*.55,radius*.3,radius*.3,0xAAFFFFFF);return finish(p)
end
-- 5×7 英文/数字像素字。中文剧情仍由平台文本框显示。
local FONT={
 B={'11110','10001','10001','11110','10001','10001','11110'},D={'11110','10001','10001','10001','10001','10001','11110'},
 J={'00111','00010','00010','00010','00010','10010','01100'},N={'10001','11001','11001','10101','10011','10011','10001'},
 Q={'01110','10001','10001','10001','10101','10010','01101'},U={'10001','10001','10001','10001','10001','10001','01110'},
 W={'10001','10001','10001','10101','10101','10101','01010'},X={'10001','10001','01010','00100','01010','10001','10001'},
 Z={'11111','00001','00010','00100','01000','10000','11111'},
 A={'01110','10001','10001','11111','10001','10001','10001'},C={'01111','10000','10000','10000','10000','10000','01111'},
 E={'11111','10000','10000','11110','10000','10000','11111'},F={'11111','10000','10000','11110','10000','10000','10000'},
 G={'01111','10000','10000','10111','10001','10001','01111'},H={'10001','10001','10001','11111','10001','10001','10001'},
 I={'11111','00100','00100','00100','00100','00100','11111'},K={'10001','10010','10100','11000','10100','10010','10001'},
 L={'10000','10000','10000','10000','10000','10000','11111'},M={'10001','11011','10101','10101','10001','10001','10001'},
 O={'01110','10001','10001','10001','10001','10001','01110'},P={'11110','10001','10001','11110','10000','10000','10000'},
 R={'11110','10001','10001','11110','10100','10010','10001'},S={'01111','10000','10000','01110','00001','00001','11110'},
 T={'11111','00100','00100','00100','00100','00100','00100'},V={'10001','10001','10001','10001','10001','01010','00100'},
 Y={'10001','10001','01010','00100','00100','00100','00100'},
 ['0']={'01110','10001','10011','10101','11001','10001','01110'},['1']={'00100','01100','00100','00100','00100','00100','01110'},
 ['2']={'01110','10001','00001','00010','00100','01000','11111'},['3']={'11110','00001','00001','01110','00001','00001','11110'},
 ['4']={'00010','00110','01010','10010','11111','00010','00010'},['5']={'11111','10000','10000','11110','00001','00001','11110'},
 ['6']={'01110','10000','10000','11110','10001','10001','01110'},['7']={'11111','00001','00010','00100','01000','01000','01000'},
 ['8']={'01110','10001','10001','01110','10001','10001','01110'},['9']={'01110','10001','10001','01111','00001','00001','01110'},
 ['?']={'01110','10001','00001','00010','00100','00000','00100'},['/']={'00001','00001','00010','00100','01000','10000','10000'},
 ['!']={'00100','00100','00100','00100','00100','00000','00100'},['-']={'00000','00000','00000','11111','00000','00000','00000'},
 [':']={'00000','00100','00100','00000','00100','00100','00000'},['.']={'00000','00000','00000','00000','00000','00100','00100'},
}
function A.pixelText(value,c)
  value=tostring(value):upper();local p=canvas(math.max(1,#value*6-1),7)
  for i=1,#value do
    local ch=value:sub(i,i);local glyph=FONT[ch] or (ch~=' ' and FONT['?'])
    if glyph then for y,row in ipairs(glyph) do for x=1,5 do if row:sub(x,x)=='1' then fill(p,(i-1)*6+x-1,y-1,1,1,c or WHITE) end end end end
  end
  return finish(p)
end
function A.result(outcome)
  local s=spec(640,480);rect(s,0,0,640,480,BLACK)
  local failed=outcome=='fail';local title=failed and 'GAME OVER' or (outcome=='spare' and 'MERCY' or ((outcome=='kill' or outcome=='killed') and 'KILLED' or 'VICTORY'))
  local heading=A.pixelText(title,failed and RED or YELLOW);append(s,heading,(640-heading.w*4)/2,150,4)
  append(s,failed and A.brokenHeart() or A.heart(outcome=='spare' and GREEN or RED),296,226,3)
  s.textBox={x=120,y=310,w=400,h=36};return s
end
M.soul_red=A.heart(RED);M.soul_blue=A.heart(BLUE)
for name,dir in pairs({right=0,down=1,left=2,up=3}) do M['soul_blue_'..name]=A.heart(BLUE,dir) end
M.soul_broken=A.brokenHeart()
for name,c in pairs({white=WHITE,blue=0xFF2F6BFF,orange=ORANGE}) do M['bone_'..name..'_v']=A.bone(10,40,c,true);M['bone_'..name..'_h']=A.bone(40,10,c,false) end
M.bone_warning=A.warning(120,5);M.bone_stab=A.stab(10,64,3,false);M.platform_green=A.platform(72,5)
M.battle_frame=A.frame(165,165);M.menu_button=A.menuButton(140,36,false);M.menu_button_selected=A.menuButton(140,36,true)
M.attack_bar=A.attackBar(280,28,.35);M.hp_kr_bar=A.hudBar(92,18,64,18,92)
M.flash_white=A.flash(640,480,WHITE);M.flash_black=A.flash(640,480,BLACK)
M.blaster_beam=A.beam(280,20,1)
M.joystick_idle=A.joystick(28,0,0);M.joystick_move=A.joystick(28,.6,-.5)
M.result_fail=A.result('fail');M.result_victory=A.result('victory');M.result_spare=A.result('spare')
M.result_killed=A.result('killed')
M.result_kill=M.result_killed
return M

end)()

__modules['default_import_file/workspace/sans-fight/lua/music'] = (function()
-- 配置的客户端 2D BGM 与短音效；0 ID 静音。
-- 保留旧版 743 音符旋律作为 opt-in 回退，不包含原曲录音，也不是完整配乐。
-- 请在 config.audio 填当前工程的真实音效资产 ID；不在代码中推定音量/音高接口。

local M = {}
local config = require('default_import_file/workspace/sans-fight/lua/config') or {}
local audioConfig = config.audio or {}

-- ----------------------------------------------------------------------------
-- ① 音效绑定 —— ★ 唯一需要你手工填的地方
--    把千星编辑器「音效库」里的音频资源 ID 填到下面（0 = 未绑定）。
--    查找顺序：精确音名 → 同音级其它八度 → 音级兜底 → M.FALLBACK
--    ① 只填 12 个音级（M.SFX_PC）就能让整条旋律出声，只是跨八度会变成同一个音高
--    ② 想更像原曲再逐个补 M.SFX 里的精确音名
--    没绑定的音会被跳过：不报错、不卡住，只是那一下听不见。
-- ----------------------------------------------------------------------------
M.SFX = {
  ['C5'] = 0, ['C6'] = 0, ['C#4'] = 0, ['C#5'] = 0, ['C#6'] = 0, ['D4'] = 0,
  ['D5'] = 0, ['D6'] = 0, ['D#4'] = 0, ['D#5'] = 0, ['D#6'] = 0, ['E5'] = 0,
  ['E6'] = 0, ['F4'] = 0, ['F5'] = 0, ['F#3'] = 0, ['F#4'] = 0, ['F#5'] = 0,
  ['G3'] = 0, ['G4'] = 0, ['G5'] = 0, ['G#3'] = 0, ['G#4'] = 0, ['G#5'] = 0,
  ['A3'] = 0, ['A4'] = 0, ['A5'] = 0, ['A#3'] = 0, ['A#4'] = 0, ['A#5'] = 0,
  ['B3'] = 0, ['B4'] = 0, ['B5'] = 0,
}
M.SFX_PC = {
  ['C'] = 0, ['C#'] = 0, ['D'] = 0, ['D#'] = 0, ['E'] = 0, ['F'] = 0,
  ['F#'] = 0, ['G'] = 0, ['G#'] = 0, ['A'] = 0, ['A#'] = 0, ['B'] = 0,
}
M.FALLBACK = 0
for k, v in pairs(audioConfig.notes or {}) do M.SFX[k] = v end
for k, v in pairs(audioConfig.pitchClasses or {}) do M.SFX_PC[k] = v end
M.FALLBACK = audioConfig.fallbackNote or 0
local bgmVoice = nil
local effectVoices = {}
local effectClock, effectLast = 0, {}

-- ----------------------------------------------------------------------------
-- ② 音符时间轴（自动扒谱 v1，勿手改；换谱只改这一段 + STEP）
--    记号：音名（C4 = 中央 C）；'-' = 休止（v1 里没有休止）
-- ----------------------------------------------------------------------------
M.STEP = 0.192        -- 八分音符间隔（156.25 BPM）
M.RETRIG = 4          -- 同一个音连续超过 4 格（≈0.77s）就重触发一次，避免糊成一条长音

M.SCORE = [[
  B5 D#6 D#6 A4 A4 E5 E5 D#5 D#5 F5 F5 F5 C5 A5 E5 A5 E5 C#6 F5 F5
  F5 F5 F5 A5 E5 E5 D#5 D#5 F5 F5 F5 D#6 D#6 A5 E5 E5 E5 F5 F5 F5
  F5 A5 E5 A5 E5 A#5 F5 F5 F5 F5 F5 A5 E5 E5 D#5 D#5 F5 F5 F5 C5
  A5 E5 E5 D#5 D#5 F5 F5 F5 F5 F5 D#6 A5 E5 E5 F5 F5 F5 F5 F5 F5
  D6 A5 A5 G#5 G#5 F5 F5 F5 E6 A5 A5 A5 G#5 G#5 F5 F5 F5 F5 D6 A5
  A5 G#5 G#5 G#5 F5 F5 F5 F5 D6 A5 A5 G#5 G#5 F5 F5 F5 F5 F5 D6 A5
  G#5 G#5 G#5 F5 F5 F5 E6 D6 A5 A5 G#5 G#5 F5 F5 F5 D6 A5 A5 A5 A5
  F5 F5 F5 F5 F5 F5 A#5 A5 G#5 G#5 E6 F5 F5 F5 F5 F5 F5 F5 F5 F5
  D5 D5 D5 F5 F5 F5 G5 G#5 G#5 G#5 G5 F5 F5 F5 F5 G5 G#5 A5 C6 A5
  A5 A5 D6 D6 D6 D6 C6 C6 C6 C6 C6 C6 F5 F5 F5 F5 G5 F5 D5 D5
  D5 F5 A5 A5 G5 G5 F5 F5 A5 A5 A5 A5 E5 E5 F5 G5 G5 G5 F5 A#4
  A#4 D5 F5 F5 E5 E5 C6 C6 C6 E5 C6 F5 F5 F5 F5 F5 G#5 G#5 F5 F5
  G5 G5 E6 E6 E6 G#5 G#5 A5 A5 A5 G#5 F5 F5 F5 E6 C6 C#6 C6 G#5 G#5
  G#5 G5 G5 G5 F5 F5 F5 F5 F5 F5 F5 E6 E6 E6 E6 E5 E6 E6 F5 F5
  C6 G5 C6 E6 E6 A5 A5 A5 A5 A5 G#5 G#5 F#5 D#5 C#5 C#5 C#5 C#5 D#5 D#5
  D#5 D#5 D#5 F5 F5 F5 F5 F5 F5 F5 F5 F5 F5 F5 F5 F5 E6 E6 E6 E6
  E6 A5 A5 A5 A5 G#5 F5 F5 F5 E6 C6 C#6 C6 G#5 G#5 G#5 G5 G5 G5 F5
  F5 F5 F5 F5 F5 F5 E6 E6 E6 E6 E5 E6 E6 F5 F5 G5 G5 G5 E6 E6
  E6 A5 A5 A5 A5 G#5 G#5 F#5 D#5 C#5 C#5 C#5 C#5 C#5 D#5 D#5 D#5 D#5 D#5 D#5
  D#5 A#4 A#4 A#4 A#3 A#3 F4 C5 C5 B4 B4 B4 B4 B4 A4 A4 A4 A4 C#5 F5
  F5 C5 C5 C5 C5 C5 C5 C5 C5 C5 C5 F5 F5 C5 F#4 F#4 F#4 A#5 A#5 A#5
  A#4 A#4 A#3 A#3 C5 C5 B4 B4 B4 B4 B4 B4 A4 A4 A4 A4 A4 A4 A3 A3
  G#4 G#4 G#4 F#3 F#3 D#4 D#4 C#4 C#4 G#3 F#3 F#3 A3 D4 D4 D#4 A#4 A#4 D#5 F5
  F5 F5 C5 C5 B4 B4 B4 B4 B4 A4 A4 A4 A4 G4 B5 C5 F5 C5 F5 C5
  F5 C5 C5 C5 C5 E6 E6 E6 C5 C5 C5 D5 D#4 D5 D#5 A#5 D#5 E6 F5 F5
  F5 B4 B4 B4 B4 B4 B4 A4 F5 A4 F5 A4 A4 G#4 A3 G#4 E6 E6 G5 G5
  F5 F5 E6 E6 E6 D6 E6 F5 F5 F5 E6 E6 F5 F5 F5 F5 A#5 A#5 A#5 D#6
  F#5 G3 G3 D#6 D#6 C#6 C#6 B5 F5 F5 F5 F5 F5 B3 G#3 B3 D#6 D#6 D#6 D#6
  F5 E6 E6 E6 B3 E6 F5 F5 F5 F5 F5 F5 E6 D#6 D#6 A#5 A#5 F5 F5 F5
  D#6 D#6 D#6 D#6 F5 D#6 E6 C#6 F#5 F#5 F#5 F#5 F#3 F#3 A3 E6 E6 E6 F#5 F#5
  F#5 F#3 F#3 A3 C#6 C#6 F#5 F#5 F#5 F5 C#6 E6 D#6 D#6 D#6 D#6 D#6 D#6 B5 B5
  D#6 D#6 D#6 C#6 A3 A3 A3 F5 F5 A#5 A#5 A#5 F#5 F#5 G#5 G#5 F#4 B3 F#4 B5
  E6 E6 C#6 F#5 F#5 F5 F5 F5 F5 C#6 F5 C6 D#6 F#5 A#4 A#4 F5 F5 F5 F#5
  F#5 E5 D#4 D#5 D#5 F5 F5 F5 F5 F5 F5 C#6 C#6 C#6 F5 F5 F5 F5 F5 D#6
  A5 E5 D#5 D#5 F5 F5 F5 C5 A5 E5 A5 E5 C#6 F5 F5 F5 F5 F5 A5 E5
  E5 D#5 D#5 F5 F5 F5 C5 A5 E5 E5 E5 E5 F5 F5 F5 F5 D#6 A5 E5 E5
  E5 B5 F5 F5 F5 G4 G4 E5 E5 D#5 D#5 F5 F5 F5 C5 G4 G4 G4 G4 G4
  G4 B5 D#6
]]

-- ----------------------------------------------------------------------------
-- ③ 播放逻辑
-- ----------------------------------------------------------------------------
local tokens = nil
local function score()
  if not tokens then
    tokens = {}
    for s in string.gmatch(M.SCORE, '%S+') do tokens[#tokens + 1] = s end
  end
  return tokens
end

local function hasSink()
  return (type(game) == 'table') and (type(game.PlayAudio2D) == 'function')
end

local function pitchClass(name)
  local i = 1
  while i <= #name and not name:find('%d', i) do i = i + 1 end
  return name:sub(1, i - 1)
end

local idCache = {}
local function idOf(name)
  local v = idCache[name]
  if v ~= nil then return v end
  v = M.SFX[name]
  if (v == nil or v == 0) and M.SFX_PC then
    -- 同音级其它八度（先降八度再升八度，够用即可）
    local pc = pitchClass(name)
    local oct = tonumber(name:sub(#pc + 1)) or 4
    for _, o in ipairs({ oct - 1, oct + 1, oct - 2, oct + 2 }) do
      local alt = pc .. tostring(o)
      local a = M.SFX[alt]
      if a and a ~= 0 then v = a; break end
    end
    if v == nil or v == 0 then v = M.SFX_PC[pc] end
  end
  if v == nil or v == 0 then v = M.FALLBACK end
  if v == nil then v = 0 end
  idCache[name] = v
  return v
end

local function stopVoice()
  if not M.voice then return end
  local h = M.voice
  M.voice = nil
  if hasSink() then pcall(function() game.StopAudio(h) end) end
end

local function fire(name)
  stopVoice()
  local id = idOf(name)
  if id == 0 or not hasSink() then return end
  local ok, h = pcall(function() return game.PlayAudio2D(id) end)
  if ok then M.voice = h end
end

M.playing = false
M.i, M.t = 1, 0
M.voice = nil
M.lastName, M.lastIndex = nil, 0
M.starts, M.triggers, M.dropped = 0, 0, 0

local function boundCount()
  local c = 0
  for _, v in pairs(M.SFX) do if v and v ~= 0 then c = c + 1 end end
  for _, v in pairs(M.SFX_PC) do if v and v ~= 0 then c = c + 1 end end
  if M.FALLBACK and M.FALLBACK ~= 0 then c = c + 1 end
  return c
end

function M.start()
  stopVoice()
  if bgmVoice then pcall(function() game.StopAudio(bgmVoice) end); bgmVoice = nil end
  M.playing = true
  M.i, M.t = 1, 0
  M.lastName, M.lastIndex = nil, 0
  M.starts = M.starts + 1
  if (audioConfig.bgm or 0) > 0 and hasSink() then
    local ok, h = pcall(function() return game.PlayAudio2D(audioConfig.bgm) end)
    if ok then bgmVoice = h end
  end
  print(string.format('music: start #%d (score=%d 格 %.2fs, 音效绑定 %d 项)',
    M.starts, #score(), #score() * M.STEP, boundCount()))
end

function M.stop()
  M.playing = false
  M.i, M.t = 1, 0
  M.lastName, M.lastIndex = nil, 0
  stopVoice()
  if bgmVoice then pcall(function() game.StopAudio(bgmVoice) end); bgmVoice = nil end
end

function M.update(dt)
  effectClock = effectClock + (dt or 0)
  if not M.playing then return end
  if (audioConfig.bgm or 0) > 0 then
    if hasSink() and audioConfig.bgmLoop ~= false then
      local ok, alive = pcall(function() return bgmVoice and game.IsAudioAlive(bgmVoice) end)
      if ok and not alive then
        local played, h = pcall(function() return game.PlayAudio2D(audioConfig.bgm) end)
        if played then bgmVoice = h end
      end
    end
    return
  end
  if not audioConfig.useNoteMusic then return end
  local tk = score()
  local n = #tk
  if n == 0 then M.playing = false return end
  M.t = M.t + (dt or 0)
  local guard = 0
  while M.playing and guard < 256 do
    guard = guard + 1
    local due = (M.i - 1) * M.STEP
    if M.t < due then break end
    local name = tk[M.i]
    if name == '-' then
      if M.voice then stopVoice() end
      M.lastName = nil
    elseif name ~= M.lastName or (M.i - M.lastIndex) >= M.RETRIG then
      if idOf(name) == 0 then M.dropped = M.dropped + 1 end
      fire(name)
      M.triggers = M.triggers + 1
      M.lastName, M.lastIndex = name, M.i
    end
    M.i = M.i + 1
    if M.i > n then
      M.i = 1
      M.t = M.t - n * M.STEP      -- 整场循环：相位不跳，接缝不断拍
      M.lastName = nil
    end
  end
end

function M.effect(name)
  local id = (audioConfig.effects or {})[name] or 0
  if id <= 0 or not hasSink() then return end
  -- 同帧多个炮一起开火只播一次，限制持续受击音的重叠。
  if effectClock - (effectLast[name] or -100) < 0.05 then return end
  effectLast[name] = effectClock
  local alive = {}
  for _, h in ipairs(effectVoices) do
    local ok, exists = pcall(function() return game.IsAudioAlive(h) end)
    if not ok or exists then alive[#alive + 1] = h end
  end
  effectVoices = alive
  if #effectVoices >= 24 then
    local old = table.remove(effectVoices, 1)
    pcall(function() game.StopAudio(old) end)
  end
  local ok, h = pcall(function() return game.PlayAudio2D(id) end)
  if ok and h then effectVoices[#effectVoices + 1] = h end
end

function M.stopEffects()
  for _, h in ipairs(effectVoices) do pcall(function() game.StopAudio(h) end) end
  effectVoices, effectLast = {}, {}
end

function M.reset() M.start() end            -- 语义别名
function M.info() return M.i, M.t, M.playing, M.triggers end

return M


end)()

__modules['default_import_file/workspace/sans-fight/lua/main'] = (function()
-- Bad Time 战斗的千星客户端适配层：图元绘制、输入、音效与结算信号。
-- 逻辑坐标为 640×480、Y 向下；按实际画布等比居中。
-- lua/ 是可维护源码；tools/build.py 将所有模块合并为根目录 main.lua。
-- 模板和音效索引集中在 config.lua，必须使用当前工程的真实索引。

local M = {}
M.config = require('default_import_file/workspace/sans-fight/lua/config') or {}

-- 构建标记：每次改动本层就换一个，日志里一眼能看出试玩跑的是不是最新代码
-- （踩过：改了 main.lua、重建存档、重新 load，但试玩 Worker 仍在跑上一版，白查半天）
local BUILD = '2026-10-08-review-2-codeart'

local G = {
  -- 模拟器内部模板 GUID
  rect = 1073743001, circle = 1073743002, text = 1073743004,
  ring = 1073743006, rot = 1073743007, rtri = 1073743008,
  cursor = 1073743009, baked = 1073743100, bakedC = 1073743101, bakedRoot = 1073743102,
}

-- 原工程模板索引初值；不是官方跨工程通用索引，实际以 config.lua 为准。
local G_REAL = {
  rect = 1073741887, circle = 1073741889, ring = 1073741890,
  rot = 1073741891, rtri = 1073741888,
  text = 1073741886, cursor = 1073741885,
  -- 图元模板容器：优先使用当前千星编辑器的 1073741884；1073741862 作为兼容回退。
  baked = 1073741884, bakedC = 1073741884, bakedRoot = 1073741884,
  bakedFallback = 1073741862,
}
local IMAGE_ID = { rect = 0, circle = 0, ring = 0, rot = 0, rtri = 0 }
for k, v in pairs(M.config.templates or {}) do G_REAL[k] = v end
for k, v in pairs(M.config.images or {}) do IMAGE_ID[k] = v end
M.runtime = {
  ownedControls = {}, keyListeners = {}, started = false, enabled = true,
  colorCache = {}, heldConfirm = {}, heldCancel = {}, heldDirections = {}, cancelHeld = false,
}

function M.enumValue(group, name)
  local ok, value = pcall(function() return Enum[group][name] end)
  return ok and value or nil
end

function M.apiColor(value)
  if type(value) ~= 'number' then return value end
  if M.runtime.colorCache[value] then return M.runtime.colorCache[value] end
  local a = math.floor(value / 16777216) % 256
  local r = math.floor(value / 65536) % 256
  local g = math.floor(value / 256) % 256
  local b = value % 256
  local ok, c = pcall(function() return Color(r, g, b, a) end)
  if not ok then return value end  -- 旧外部宿主兼容
  M.runtime.colorCache[value] = c
  return c
end

-- 原件配色：白 0 / 蓝 1 / 橙 2（与 BTS 攻击脚本 Color 字段一致）
local BONE_COLORS = { 0xFFFFFFFF, 0xFF2F6BFF, 0xFFFF7A18 }
local C_WHITE, C_RED, C_BLUE, C_DIM = 0xFFFFFFFF, 0xFFFF2B2B, 0xFF63B0FF, 0xFFB9C6D8
local C_BOX, C_HP = 0xFFFFFFFF, 0xFFFFD200

-- 骷髅炮 / 审判者（sans 本人）的配色：两者都是「用图元拼出来的复合外观」，见下面 drawBlaster / drawSans。
-- 取值口径：颅骨与光束纯白（原作就是白），外套取偏蓝的深灰（原作 sans 的连帽衫），
-- 眼窝近黑、BlueEye 亮蓝 + 更暗的半透明外圈，汗滴浅蓝。
-- 【2026-10-06 清理】旧参数化 Sans / 6 矩形龙骨炮的配色常量已随旧模型一起删除；
-- 现在龙骨炮与 Sans 本体都走 lua/fitdata.lua 的 CodeArt 几何像素配方容器，自带原图颜色。
local C_BEAM_WHITE = 0xFFFFFFFF         -- 光束（仍由池内矩形绘制）
local C_SANS_SWEAT = 0xFF8FD8FF         -- 汗滴（参数化圆点）
-- 光束宽度表（与 core.BLASTER_W 同口径：Size 0/1/2 → 20/36/56px）。core 每条 blaster 命令都带 w，
-- 这里只是兜底（命令缺 w 时按 size 查表），两处数值必须一致。
local BLASTER_BAND = { 20, 36, 56 }
local BLASTER_MUZZLE_U = 32      -- 光束从吻部前端射出（基础世界 px，随骷髅 scale 缩放）

-- 逻辑层的颜色可能是 '#RRGGBB' / '#AARRGGBB' 字符串（核心用字符串，属性写入用整数）
local function toColor(v)
  if type(v) == 'number' then return v end
  if type(v) == 'string' then
    local hex = v:gsub('#', '')
    if #hex == 6 then return tonumber('FF' .. hex, 16) or C_WHITE end
    if #hex == 8 then return tonumber(hex, 16) or C_WHITE end
  end
  return C_WHITE
end

-- 默认按需创建并复用控件；此表仅供显式开启旧外部宿主预热时使用。
-- CodeArt 终盘使用 block3（34–43 矩形/炮），普通段 block2（68–78）。
local BUDGET = { rect = 500, circle = 200, rot = 1350, rtri = 4, ring = 2, text = 15, cursor = 1 }

local W, H = 640, 480          -- 逻辑世界尺寸
local root, flash, bgPanel, bakedRoot = nil, nil, nil, nil
local CW, CH, S, OX, OY = 1280, 720, 1.5, 160, 0

local pool, used, memo = {}, {}, {}
local curBox = { x = 240, y = 226, w = 160, h = 165 }   -- 当前**画出来**的战斗框（平滑后的值）
local boxTarget = nil                                   -- 逻辑层的目标框（每帧由 box 命令给出）

-- 原版默认战斗框 = core 的 BOX_OFF (240,226) + 160x165 → 中心 (320, 308.5)。
-- core 已统一到单一世界绝对坐标（`BOX_CX, BOX_CY = 320, 308.5`，内置回合、脚本 zone、菜单/子面板/攻击条
-- 各状态的框都在同一位置），所以这里**只用来判异常**：偏离就 WARN，不做纠正。
local ORIG_CX, ORIG_CY = 240 + 80, 226 + 82.5
local CENTER_TOL = 20
-- 框异常判定的"稳定窗口"：脚本的 CombatZoneResize 会把框动画到新尺寸（见 draw 里的注释），
-- 动画中间帧的中心偏离常量是正常的，所以要求 core 给的框连续这么多帧不变才判定。
local BOX_STABLE_FRAMES = 8
local prevCoreBox = { nil, nil, nil, nil }
local boxStableN = 0
local function boxOverflow(x, y, w, h)
  local o = 0
  if x < 0 then o = o - x end
  if y < 0 then o = o - y end
  if x + w > W then o = o + (x + w - W) end
  if y + h > H then o = o + (y + h - H) end
  return o
end
local boxFixLogged = false
local resultFlashN = 0        -- 结局态闪层已连续绘制的帧数（超过 15 帧就收起，露出结局文字）
-- 坐标：core 的 render 出口**只有一套**——世界绝对坐标 640×480（Y 向下），
-- 世界实体 / HUD / 菜单 / 子面板 / 攻击条 / 闪层全都是这一套，本层不做任何平移。
-- （曾经的 OFFX/OFFY + WOFFX/WOFFY + WORLD_KINDS「按命令类型切平移量」已随 core 单帧化删除；
--   `lua/_geometry.lua` 用「绘制 == 判定几何」逐帧对账把这件事钉住。）
local madeTotal = 0
local frame, logAcc = 0, 0
local core, attacks, music, state = nil, nil, nil, nil
local lastRunSeq = nil             -- core 每次开战/重开 +1；宿主据此让 BGM 从头播
local fit = nil                    -- lua/fitdata.lua：CodeArt 几何像素配方表（缺失时走参数化回退）
local mode = 'demo'

local input = { left = false, right = false, up = false, down = false, confirm = false, cancel = false }
local edgeConfirm, edgeCancel = false, false
-- 【J5】确认键（Enter/小键盘回车/Z/空格/J）的**按住**状态：光有按下沿不够 ——
-- 蓝魂起跳靠按住时长决定高度，只给一帧 down 会让灵魂刚起跳就被 jumpCut 剪断。
local confirmHeld = false



-- 操作方式（**按平台分成两条互不相干的路径**，见下面的「平台分流」段）：
--   PC   = WASD / 方向键移动 + Enter（Z / 空格 / 小键盘回车 由宿主归到同一个确认键）确认；
--          鼠标**只用来点 UI**（点一下 = 选中并确认）。PC 上不存在虚拟摇杆，拖动不产生任何移动。
--   触摸 = 左半屏按住拖动 = 虚拟摇杆（拖动方向 = 世界方向，Y 向下）；点按 = **二次确认**
--          （第一次点只选中/高亮并显示「再点一次确认」，再点同一项才确认；点空白取消选中）。
-- 指针不再是「灵魂跟随鼠标」——那样在手机上无法操作，也不符合原作手感。
local cursorArea = nil
local ptr = { x = nil, y = nil, down = false, logged = false }
local diagSoul = nil                     -- 转向诊断用的上一次位置
local diagAcc = 0
local lastPhase = nil
local attackT = 0        -- 攻击条已持续时长（防卡死保险用）
local lastMenu, lastSub, lastBar = nil, nil, nil
local titlePrevL, titlePrevR = false, false     -- 标题页左右选档的边沿检测
local prevUp = false           -- （保留：其它地方仍在用）
local prevJumpKey = false      -- 【原版】跳跃键 = 与重力反向的那个键，检测它的按下沿
local drawnKinds = {}          -- 上一帧真正画出去的命令种类（回归用）
local drawnBox = false         -- 上一帧是否画了战斗框（标题页必须为 false）
local pendingPhase = nil       -- 上一帧的相位（相位一变就清掉触摸端的待确认选中）

-- 触摸端「二次确认」的待确认项：{ kind = 'title' | 'menu' | 'sub', index = 0 基 }
-- 触摸没有悬停，一次点按就执行很容易误触，所以触摸分支统一两段式：
--   第一次点某个选项 = 只选中/高亮（并显示「再点一次确认」），点同一项第二次 = 真正确认；点空白取消。
-- PC 分支**不用这套**（鼠标点击 = 直接选中并确认，保持原行为）。
local pendingSel = nil
local function clearPending() pendingSel = nil end
local function samePending(kind, index)
  return pendingSel ~= nil and pendingSel.kind == kind and pendingSel.index == index
end
local function markPending(kind, index) pendingSel = { kind = kind, index = index } end

-- 虚拟摇杆（**只在触摸分支存在**）：基准点默认在左下角，按下左半屏时移到按下处
local JOY_R, JOY_DEAD = 46, 9
local JOY_HOME_X, JOY_HOME_Y = 84, 392      -- 世界坐标（默认位置）
local joy = { active = false, bx = JOY_HOME_X, by = JOY_HOME_Y, kx = 0, ky = 0, dx = 0, dy = 0, moved = false }

-- 方向死区（**归一化**，摇杆向量 dx/dy ∈ [-1,1]）：四向判定的唯一阈值。
-- 取值来源：既有 applyPointer 里硬编码的 0.22（不是新拍的数）。它与"中心像素死区"
-- JOY_DEAD/JOY_R = 9/46 ≈ 0.196 同一量级，取 0.22 稍大一点 —— 阈值附近指针会抖，
-- 稍大的死区能避免方向位在边界上反复跳（对角判定要两个方向同时"够到"才置位）。
local DEAD = 0.22

-- 归一化摇杆向量 → 四向位（**纯函数**，回归直接调）。
--   dx/dy 与世界坐标同口径：+x 右、+y 下（Y 向下，见 toWorld 的注释）。
--   规则：|dx| > DEAD → 左/右；|dy| > DEAD → 上/下；两轴都超 = **对角（两位同时置位）**；
--         两轴都不超 → 四向全假（无输入）。四个方向位互相独立，所以对角天然可用。
local function joyDirs(dx, dy)
  dx, dy = tonumber(dx) or 0, tonumber(dy) or 0
  return {
    left = dx < -DEAD, right = dx > DEAD,
    up = dy < -DEAD, down = dy > DEAD,        -- 世界 Y 向下：往上拖 = dy<0 = 上
  }
end

-- 原始偏移（世界 px）→ 摇杆向量：杆头限制在半径内，归一化 -1..1（中心一个小像素死区）。
-- 杆头 (kx,ky) 与方向位 (dx,dy) 由同一个原始偏移算出 —— 绘制与判定同源的一半。
local function joyVector(rawdx, rawdy)
  local len = math.sqrt(rawdx * rawdx + rawdy * rawdy)
  local kx, ky = rawdx, rawdy
  if len > JOY_R then kx, ky = rawdx / len * JOY_R, rawdy / len * JOY_R end
  local nx, ny = 0, 0
  if len > JOY_DEAD then nx, ny = kx / JOY_R, ky / JOY_R end
  return kx, ky, nx, ny
end

-- 触摸分支的摇杆区 = 左半屏（不用精确点中圆）；但**可点 UI 优先**：
-- 底部按钮行横跨整屏（原版就在框下），左半屏也有「攻击/行动」，不能被摇杆吞掉。
-- PC 分支**根本不调用这个函数**：鼠标永远不起摇杆（见 bindPointer）。
local function inJoyZone(wx)
  return wx < W * 0.55
end

-- ---------------------------------------------------------------- 平台分流
--
-- 曾经的判定是「指针落在左半屏 = 摇杆」，它**完全不看平台**：PC 上按住鼠标拖动也被当成摇杆
-- （还会吃掉点击），所以现在按设备把输入拆成两条独立路径。
--
-- 设备取值只用 `game.GetDevice()`，**只认源码里写死的那几种**（不猜，出处见下）：
--   * 插件 dist/worker.js（本机 dsh-plugin-beyond-simulator 2.0.8 的打包产物）：
--       GetDevice:r=>(i.pushEnumItem(r,rt("Device",i.device)),1)
--       Device:["KeyboardAndMouse","Mobile","Controller","MobileController"]
--       this.device=t.device??"KeyboardAndMouse"
--   * 模拟器源码 client/lua-runtime/src/runtime.js:458-460
--       GetDevice: (LL) => { rt.pushEnumItem(LL, makeEnumItem('Device', rt.device)); return 1 }
--     runtime.js:59  this.device = options.device ?? 'KeyboardAndMouse'
--     enums.js:15    Device: ['KeyboardAndMouse', 'Mobile', 'Controller', 'MobileController']
--   * 试玩画布档位（插件 dist/index.js 的 q 表）：pc-16-9 / pc-21-9 → luaDevice:"KeyboardAndMouse"；
--     mobile-16-9 / mobile-19.5-9 / mobile-4-3 → luaDevice:"Mobile"（切画布 = 换设备）
-- GetDevice 返回的是 **EnumItem userdata，不是字符串**：元表只放行 Name / FullName / EnumType
-- 三个字段（worker.js mtEnum：i=new Set(["Name","FullName","EnumType"])），tostring() 拿不到名字。
-- 保守口径：**只有确切等于 Mobile / MobileController 才走触摸分支**，其余（PC / 手柄 / 读不到值）
-- 一律按 PC —— 键盘方案在任何设备上都能用，读不到值时选它不会把玩家卡死。
local TOUCH_DEVICE = { Mobile = true, MobileController = true }
local isTouch = false          -- 本局走哪条分支（OnStart 时定一次）
local deviceName = 'unknown'   -- 诊断用：读到的设备名（读不到就是 unknown）

-- 试玩调试钩子：服务器变量 `Level.SansRound = N` → 直接从内部回合号 N 开局（0..19）。
--   为什么需要它：20 回合整场约 250s 游戏时间，模拟器里没法为了看某一段而打满全场 ——
--   这个钩子让"第 18/19/20 回合的螺旋龙骨炮""某回合的独有弹幕"可以一秒钟跳到。
--   变量不存在 / 不是数字 / < 1 → 行为与以前完全一致（从见面杀开始）。
--   用法：标题页把 `Level.SansRound` 设成 19（服务端变量面板 / serverSet），再按确认开局。
-- 定义位置必须在**第一个使用点之前**（Lua 的 local 作用域）—— 它是被点按与键盘两条
-- 开局路径共用的，那两处都在文件后半段。
local function bootRound()
  if not M.config.debug then return nil end
  local ok, v = pcall(function() return game.GetGlobalCustomVariableValue(M.enumValue('CustomVariableEntityType', 'Level') or 'Level', 'SansRound') end)
  if ok and type(v) == 'number' and v >= 1 then return math.floor(v) end
  return nil
end

local function readDeviceName()
  local ok, d = pcall(function() return game.GetDevice() end)
  if not ok or d == nil then return nil end
  if type(d) == 'string' then return d end        -- 万一某天改成直接返回字符串
  for _, f in ipairs({ 'Name', 'FullName', 'EnumType' }) do
    local okF, v = pcall(function() return d[f] end)
    if okF and type(v) == 'string' and v ~= '' then return v end
  end
  return nil
end

local function detectDevice()
  if M.config.device == 'mobile' then deviceName = 'Mobile'; return true end
  if M.config.device == 'keyboard' then deviceName = 'KeyboardAndMouse'; return false end
  local name = readDeviceName()
  deviceName = name or 'unknown'
  if type(name) == 'string' then
    local tail = name:match('([%w_]+)%s*$') or name   -- 'Enum.Device.Mobile' → 'Mobile'
    if TOUCH_DEVICE[tail] then return true end
  end
  return false
end

local function inRect(px, py, x, y, w, h)
  return px >= x and px <= x + w and py >= y and py <= y + h
end

local function clamp(v, a, b) if v < a then return a elseif v > b then return b else return v end end

-- 标题页四张难度卡的矩形（每帧由 title 态的 menu 命令收集；菜单行是"一条命令多张卡"，标题页是"一卡一条"）
local titleCards = {}

-- ---------------------------------------------------------------- 可点 UI 的行几何
--
-- 绘制与命中判定**必须共用同一套矩形**。踩过的坑：文字画在按钮矩形外（y+22），命中框却写死
-- y-6..y+34，于是「看得见的按钮点不到」；而按钮行 y 还会跟着框下沿被钳制
-- （小框态 ≈403、大框态钳到 434），任何写死 y 的判定都必然在某个相位失效。
-- 所以下面这些矩形既给绘制用，也给命中判定用，并且按**本帧实际绘制的那一份**（lastMenu/lastSub）算。

-- ---------------------------------------------------------------- 按钮行定位（一切以屏幕中心为参照）
--
-- 参考实现：原版 Bad Time Simulator（Construct 2 导出）https://jcw87.github.io/c2-sans-fight/
--   证据文件 = 该站的 data.js（`web_fetch` 拉不到二进制，用 Invoke-WebRequest 取回后按 JSON 解析）。
--   布局 `BattleScreen`（640×480，Y 向下）的 `Buttons` 图层，四个 110×42 的按钮实例（hotspot 0,0 → x,y 是左上角）：
--     uifight-sheet0.png (32,432)   uiact-sheet0.png (184,432)
--     uiitem-sheet0.png  (344,432)  uimercy-sheet0.png (496,432)     -- 帧尺寸 110×42 与实例一致
--   → 行顶边 y = 432 = 屏幕中心 y(240) + 192 ；行中心 y = 453 = 屏幕中心 y + 213 ；行底边 474 = 480 − 6。
--   同一布局里战斗框（CombatZone 图层的红心实例 (320,320)，以及 Overlay 实例的
--   [X1,Y1,X2,Y2] = 33,251,608,391）是 x 33..608 / y 251..391 → 框底 391 到按钮行顶 432 的间距 41px。
--
-- 我们 core 给的按钮高 bh=36（core.lua `MENU.bh`，**不改 core**），比参考的 42 矮 6：
--   按"行顶边"对齐参考实现最直接（432 逐像素一致），行中心因此是 450 而不是 453（差 3px，肉眼无感）。
--   旧规则（框下沿 +12，再钳到 H−46=434）的问题：小框相位 403 / 大框相位 434，两个相位差 31px，
--   与屏幕中心毫无固定关系；而且大框底边 438.5 > 434，行其实压在框里（实测重叠 4.5px）。
local CENTER_X, CENTER_Y = W / 2, H / 2     -- 屏幕中心 (320, 240)：本层所有 UI 位置的参照点
local MENU_ROW_DY_TOP = 192                 -- 参考实现：行顶边 432 − 屏幕中心 y 240
local MENU_ROW_DY_CENTER = 213              -- 参考实现：行中心 453 − 屏幕中心 y 240（bh=42 时的等价说法）
local MENU_ROW_GAP = 2                      -- 与战斗框下沿的最小间距（保证不重叠）
local MENU_ROW_BOTTOM_MARGIN = 3            -- 行底到世界底边的最小留白
--   为什么不是参考实现的 6px：core 的按钮矮 6px（36 vs 42），而常规大框（实测底边 438.5）下方只剩 41.5px，
--   留 6px 会把上界压到 438 —— 比"框下沿 + 2"的 440.5 还高，反而又和框重叠 0.5px。留 3px 时
--   上界 441 > 440.5，三个相位全都不与框重叠（小框 432 / 常规大框 440.5 / 终盘超大框被上界钳到 441）。

-- 按钮行 y（纯函数，便于单测）：主值 = 屏幕中心 + MENU_ROW_DY_TOP（= 432，与参考实现一致）；
-- 只在两处被修正，且都写成常量、都可断言：
--   ① 框下沿 + MENU_ROW_GAP  —— 不与战斗框重叠（框够高时才生效）；
--   ② H − bh − MENU_ROW_BOTTOM_MARGIN —— 整行留在世界 0..480 内。
-- 唯一允许的例外：终盘超大框（core 实测底边 478.5）下方只剩 1.5px，物理上放不下任何一行 → ② 生效、
-- 行压进框内（与原作"按钮画在框内黑色区域上"一致）；`lua/_flow.lua` 断言"重叠帧全部属于这一类"。
local function rowYFor(bh, boxBottom)
  bh = bh or 36
  local y = CENTER_Y + MENU_ROW_DY_TOP
  if boxBottom then
    local floor = boxBottom + MENU_ROW_GAP
    if y < floor then y = floor end
  end
  local ceil = H - bh - MENU_ROW_BOTTOM_MARGIN
  if y > ceil then y = ceil end
  return y
end
local function menuRowY(bh)
  local boxBottom = boxTarget and (boxTarget.y + boxTarget.h) or nil
  return rowYFor(bh, boxBottom)
end

-- 按钮行第 i 项（1 基）的按钮矩形：x/w 是第一个按钮的矩形，后续按 w+gap 排开（core 的约定）
local function menuButtonRect(cmd, i)
  local gap = cmd.gap or 10
  local bw = cmd.w or 110
  local bh = cmd.h or 36
  return cmd.x + (i - 1) * (bw + gap), cmd.y, bw, bh
end

-- 选择心在按钮内部，与绘制坐标一致。
local function menuHeartRect(cmd, i)
  local bx, y, _, bh = menuButtonRect(cmd, i)
  return bx + 6, y + bh / 2 - 6, 12, 12
end

-- 命中按钮行：**先按按钮矩形**（彼此不重叠），再按左侧红心（允许与邻居轻微重叠）
local function menuHitTest(cmd, wx, wy)
  local n = #(cmd.items or {})
  if n == 0 then return nil end
  local _, y, _, bh = menuButtonRect(cmd, 1)
  if wy < y - 4 or wy > y + bh + 8 then return nil end
  for i = 1, n do
    local bx, by, bw, bh2 = menuButtonRect(cmd, i)
    if wx >= bx and wx <= bx + bw and wy >= by - 4 and wy <= by + bh2 + 8 then return i end
  end
  for i = 1, n do
    local hx, hy, hw, hh = menuHeartRect(cmd, i)
    if wx >= hx and wx <= hx + hw and wy >= hy and wy <= hy + hh then return i end
  end
  return nil
end

-- 子面板行布局：core 只给面板矩形 + rowH（面板本身已保证在框内、不越 640×480），
-- 行位置由本层决定 —— 绘制与点击判定必须用同一个公式，否则点歪。
local SUB_HEAD = 34
local function subRowTop(cmd, i)
  return cmd.y + SUB_HEAD + (i - 1) * (cmd.rowH or 26)
end
-- i 是**视窗槽位**（1..view），不是数据行号；返回比行高多 4px 的容差矩形（方便触屏）
local function subRowRect(cmd, i)
  local rh = math.max(16, math.min(cmd.rowH or 26, 40))
  return cmd.x + 6, subRowTop(cmd, i) - 2, cmd.w - 12, rh + 4
end
-- 【方案甲·滚动视窗】只命中当前可见的行，并返回 1 基的**数据行号**（top + 槽位）
local function subHitTest(cmd, wx, wy)
  local view = cmd.view or #(cmd.rows or {})
  local top = cmd.top or 0
  for k = 1, view do
    local rx, ry, rw, rh = subRowRect(cmd, k)
    if wx >= rx and wx <= rx + rw and wy >= ry and wy <= ry + rh then return top + k end
  end
  return nil
end

-- 当前帧是否有可点 UI 盖在这个点上（标题页难度卡 / 菜单行 / 子面板 / 攻击条）。
-- 只用于**摇杆避让**：命中判定用上面那套精确矩形，摇杆区里点到这些地方就不起摇杆。
local function uiHit(wx, wy)
  for i = 1, #titleCards do
    local c = titleCards[i]
    if inRect(wx, wy, c.x - 8, c.y - 8, c.w + 16, c.h + 16) then return true end
  end
  if lastMenu and lastMenu.visible ~= false and menuHitTest(lastMenu, wx, wy) then return true end
  if lastSub and subHitTest(lastSub, wx, wy) then return true end
  if lastBar and inRect(wx, wy, lastBar.x, lastBar.y - 6, lastBar.w, lastBar.h + 12) then return true end
  return false
end

-- ---------------------------------------------------------------- 控件池

-- 千星真机的客户端资产经常只允许先放「容器节点」，再把图片/文字/光标作为其子控件。
-- 这里做兼容：期望叶子控件时，如果拿到的是容器，则自动取第一个子控件；模拟器当前直接模板不受影响。
function G_REAL.controlName(c)
  local ok, n = pcall(function() return c.name end)
  if ok and type(n) == 'string' then return n end
  ok, n = pcall(function() return c.Name end)
  return (ok and type(n) == 'string') and n or ''
end

function G_REAL.nameHasAny(name, ...)
  for _, key in ipairs({ ... }) do
    if name:find(key, 1, true) ~= nil then return true end
  end
  return false
end

function G_REAL.isKindControl(c, kind, targetGuid)
  if not c then return false end
  -- 模板索引相同也可能是包装容器；检测叶子接口，不按索引猜类型。
  local ok, value = pcall(function()
    if IMAGE_ID[kind] then return c.SetImage ~= nil
    elseif kind == 'text' then return c.text ~= nil
    elseif kind == 'cursor' then return c.AddCursorEventListener ~= nil end
    return false
  end)
  return ok and value or false
end

function G_REAL.findKindChild(c, kind, targetGuid)
  local ok, children = pcall(function() return c:GetChildren() end)
  if not ok or type(children) ~= 'table' then return nil end
  for _, child in ipairs(children) do
    if G_REAL.isKindControl(child, kind, targetGuid) then return child end
    local nested = G_REAL.findKindChild(child, kind, targetGuid)
    if nested ~= nil then return nested end
  end
  return nil
end

function G_REAL.isolateChild(root, keep)
  local function visit(node)
    local ok, children = pcall(function() return node:GetChildren() end)
    if not ok or type(children) ~= 'table' then return false end
    local containsKeep = false
    for _, child in ipairs(children) do
      local childKeeps = (child == keep) or visit(child)
      if childKeeps then
        containsKeep = true
        child:SetActive(true)
        if child ~= keep then G_REAL.stretchWrapper(child) end
      end
      if child ~= keep and not childKeeps then pcall(function() child:SetVisible(false) end) end
    end
    return containsKeep
  end
  visit(root)
end

function G_REAL.stretchWrapper(c)
  c:SetAnchorMin(0, 0); c:SetAnchorMax(1, 1)
  c:SetPivot(0, 0); c:SetSizeDelta(0, 0); c:SetAnchoredPosition(0, 0)
  c:SetVisible(true)
end

local function unwrapTemplate(c, kind, targetGuid)
  if not c then return nil end
  if kind == 'baked' or kind == 'bakedC' or kind == 'bakedRoot' then return c end
  if G_REAL.isKindControl(c, kind, targetGuid) then return c end
  local child = G_REAL.findKindChild(c, kind, targetGuid)
  if child ~= nil then
    G_REAL.wrapperMode = true
    G_REAL.isolateChild(c, child)
    return child
  end
  -- 兼容旧编辑器：没有类型信息时退回第一个子控件。
  local ok, first = pcall(function() return c:GetChild(1) end)
  if ok and first ~= nil then
    G_REAL.isolateChild(c, first)
    return first
  end
  return c
end

local function applyImageKind(c, kind)
  local id = IMAGE_ID[kind]
  if c ~= nil and type(id) == 'number' and id > 0 then
    -- 模拟器/真机均为两参数：SetImage(ImageSource, imageId)。
    local ok = pcall(function() c:SetImage(Enum.ImageSource.StaticReference, id) end)
    if not ok then pcall(function() c:SetImage(id) end) end
  end
  return c
end

local function instantiateTemplate(kind, parent)
  -- 1) 真机直接模板优先；2) 模拟器 GUID 回退；
  -- 3) 真机/模拟器容器节点回退：递归寻找正确的图片/文本/光标子控件。
  local candidates = { G_REAL[kind], G[kind] }
  if not M.config.legacyTemplateFallback then candidates = { G_REAL[kind] } end
  if M.config.legacyTemplateFallback and kind ~= 'baked' and kind ~= 'bakedC' and kind ~= 'bakedRoot' then
    candidates[#candidates + 1] = G_REAL.baked
    candidates[#candidates + 1] = G_REAL.bakedFallback
    candidates[#candidates + 1] = G.baked
  end
  local tried = {}
  for _, guid in ipairs(candidates) do
    if guid ~= nil and not tried[guid] then
      tried[guid] = true
      local ok, c = pcall(function() return game.InstantiateClientUIControl(guid, parent) end)
      if ok and c ~= nil then
        M.runtime.ownedControls[#M.runtime.ownedControls + 1] = c
        c:SetActive(true) -- 包装模板的父层也必须激活。
        if guid == G_REAL[kind] then G_REAL.realTemplateMode = true end
        local outer = c
        c = unwrapTemplate(c, kind, guid)
        if c ~= outer then G_REAL.stretchWrapper(outer) end
        c = applyImageKind(c, kind)
        c:SetActive(true)
        local centered = kind == 'rot' or kind == 'rtri' or kind == 'bakedC'
        local anchor = centered and 0.5 or 0
        c:SetAnchorMin(anchor, anchor); c:SetAnchorMax(anchor, anchor)
        c:SetPivot(anchor, anchor)
        c:SetAnchoredPosition(0, 0)
        if kind == 'cursor' then c.raycastTarget = true
        end
        if kind == 'text' then c.bgColor = M.apiColor(0x00000000) end
        return c, nil
      end
    end
  end
  return nil, '客户端模板缺失：' .. tostring(kind) .. ' 索引 ' .. tostring(G_REAL[kind]) .. '；请核对 config.lua 和已保存的客户端模板'
end

local instNILLogged = false     -- 模板缺失只打一次完整诊断，避免刷屏
G_REAL.wrapperMode = false          -- 真机使用容器包装模板时开启；避免启动批量预热造成卡死
G_REAL.realTemplateMode = false     -- 真机使用真实模板 GUID 时开启；真机不做 2015 控件预热

local function st(c)
  local m = memo[c]
  if not m then m = {}; memo[c] = m end
  return m
end

local function spawn(kind, parent)
  local c, err = instantiateTemplate(kind, parent or root)
  if c == nil and err ~= nil then print('main: inst ERR ' .. kind .. ' :: ' .. tostring(err)) return nil end
  if c == nil then
    -- 实例化返回 nil = 客户端模板池缺这个索引（或图元类型不对），只打一次完整诊断
    if not instNILLogged then
      instNILLogged = true
      print(string.format('main: 客户端模板缺失 —— 图元「%s」索引 %d 实例化失败；请在「UI控件-客户端」'
        .. '资产根下建齐 7 个图元（索引不可改，清单见 docs/device-setup.md 第 2 节）', kind, G[kind]))
    end
    return nil
  end
  madeTotal = madeTotal + 1
  local m = st(c)
  c:SetVisible(false)
  m.vis = false
  return c
end

local function poolOf(kind)
  local list = pool[kind]
  if not list then list = {}; pool[kind] = list end
  return list
end

local function take(kind)
  local layer = M.runtime.paintLayer or 'world'
  local key = kind .. '@' .. layer
  local list = poolOf(key)
  local i = (used[key] or 0) + 1
  used[key] = i
  local c = list[i]
  if not c then
    c = spawn(kind, M.runtime.layers and M.runtime.layers[layer])
    if not c then return nil end
    list[i] = c
  end
  local m = st(c)
  if m.vis ~= true then c:SetVisible(true); m.vis = true end
  return c
end

local function prewarm()
  if not M.config.legacyTemplateFallback then return end
  for kind, n in pairs(BUDGET) do
    local list = poolOf(kind .. '@world')
    for i = 1, n do
      list[i] = spawn(kind, M.runtime.layers and M.runtime.layers.world)
      -- 真机容器包装模式下，每个实例带多个子控件；继续预热 2015 份会卡死。
      -- 改为此后完全按需创建，已经创建的这一份保留在池里。
      if G_REAL.realTemplateMode or G_REAL.wrapperMode then
        print('main: 检测到真机模板，跳过大批量预热，改为按需创建控件')
        return
      end
    end
  end
end

-- ---------------------------------------------------------------- 世界 → 画布

local function layout()
  CW, CH = game.GetUICanvasSize()
  S = math.min(CW / W, CH / H)
  OX = (CW - W * S) / 2
  OY = (CH - H * S) / 2
end

-- 世界（640×480、Y 向下、左上原点）→ 画布（左下原点、Y 向上）：只做缩放 + 居中 + 翻一次 Y。
-- 参数一律是**世界绝对坐标**（core 出口的坐标口径，见上方「坐标」注释）。
local SHKX, SHKY = 0, 0   -- 【方案甲 A-7】SansShake 的整屏偏移（世界像素）
local function wx(x) return OX + x * S + SHKX * S end
local function wyBottom(yBottom) return OY + (H - yBottom) * S + SHKY * S end

local function put(c, cx, cy, w, h)
  local m = st(c)
  if m.w ~= w or m.h ~= h then c:SetSizeDelta(w, h); m.w, m.h = w, h end
  if m.x ~= cx or m.y ~= cy then c:SetAnchoredPosition(cx, cy); m.x, m.y = cx, cy end
end

local function tint(c, color)
  local m = st(c)
  if m.c ~= color then c.imageColor = M.apiColor(color); m.c = color end
end

local function spin(c, deg)
  local m = st(c)
  -- 【2026-10-05 修】运行时的签名是 SetLocalRotation(x, y, z)：只传一个参数会把角度写进 X 轴，
  -- Z（2D 真正用的那个）保持 0 → 旋转件其实**从来没转**过。斜/竖的龙骨炮光束因此被画成横的、
  -- 直接飞出画面（用户看到的「上下的龙骨炮丢失发射动画」）。
  if m.r ~= deg then c:SetLocalRotation(0, 0, deg); m.r = deg end
end

-- ---------------------------------------------------------------- 烘焙贴图（exact 逐像素）
-- 数据来自 lua/fitdata.lua（自包含几何配方）：每个素材一个容器，
-- 子控件用**比例锚点**（anchorMin/Max = 矩形占比、sizeDelta=0）→ 父容器 SetSizeDelta
-- 就能整体缩放（不用真机未验证的 SetLocalScale）。容器在 bakedRoot 下，
-- bakedRoot 在 prewarm 之前创建 → 烘焙层天然在黑底之上、池控件之下。
local baked = {}                       -- key -> { name, spec, center, mirror, insts = { {c,vis,used,kids}, ... } }
local BAKED_MAX_INSTS = 12             -- 同一素材同时在场上限（龙骨炮实测峰值约 7-9 发）
local fitWarned = false

local function newBakedInstance(rec)
  local parent = bakedRoot or root
  local c, instErr = instantiateTemplate(rec.center and 'bakedC' or 'baked', parent)
  local ok = (c ~= nil)
  if not ok or c == nil then
    if not instNILLogged then instNILLogged = true; print('main: baked 容器缺失 :: ' .. tostring(instErr)) end
    return nil
  end
  madeTotal = madeTotal + 1
  c:SetVisible(false)
  local spec, mirror = rec.spec, rec.mirror
  local kids = 0
  for i = 1, #spec.rects do
    local r = spec.rects[i]
    local k = instantiateTemplate('rect', c)
    if k then
      local ax0, ax1
      if mirror then
        ax0 = 1 - (r.x + r.w) / spec.w
        ax1 = 1 - r.x / spec.w
      else
        ax0 = r.x / spec.w
        ax1 = (r.x + r.w) / spec.w
      end
      k:SetAnchorMin(ax0, 1 - (r.y + r.h) / spec.h)
      k:SetAnchorMax(ax1, 1 - r.y / spec.h)
      k:SetSizeDelta(0, 0)
      k:SetPivot(0.5, 0.5); k:SetAnchoredPosition(0, 0)
      k.imageColor = M.apiColor(r.c)
      k:SetVisible(true)
      kids = kids + 1
    end
  end
  local inst = { c = c, vis = false, used = -1, kids = kids }
  st(c).vis = false
  return inst
end

-- 取一个本帧还没用过的实例；没有就新建（每个实例一套独立子控件 → 可同时画多发龙骨炮）
local function bakeInstance(name, center, mirror)
  if not fit or type(fit[name]) ~= 'table' then return nil end
  local key = mirror and (name .. '#m') or name
  local rec = baked[key]
  if not rec then
    rec = { name = name, spec = fit[name], center = center and true or false,
            mirror = mirror and true or false, insts = {} }
    baked[key] = rec
  end
  for i = 1, #rec.insts do
    local inst = rec.insts[i]
    if inst.used ~= frame then return inst end
  end
  if #rec.insts >= BAKED_MAX_INSTS then return rec.insts[1] end
  local inst = newBakedInstance(rec)
  if inst then
    rec.insts[#rec.insts + 1] = inst
    print(string.format('main: baked %s#%d %dx%d rects=%d', name, #rec.insts, rec.spec.w, rec.spec.h, inst.kids))
  end
  return inst
end

-- 左下锚点：world 左上角 (x,y)、宽高 w,h（世界 px）
local function useBakedCorner(name, x, y, w, h, mirror)
  local b = bakeInstance(name, false, mirror); if not b then return nil end
  b.used = frame
  if not b.vis then b.c:SetVisible(true); b.vis = true end
  put(b.c, wx(x), wyBottom(y + h), w * S, h * S)
  return b
end

-- 中心锚点：world 中心 (cx,cy)、宽高 w,h、旋转 deg
local function useBakedCenter(name, cx, cy, w, h, deg)
  local b = bakeInstance(name, true); if not b then return nil end
  b.used = frame
  if not b.vis then b.c:SetVisible(true); b.vis = true end
  put(b.c, wx(cx) - CW / 2, wyBottom(cy) - CH / 2, w * S, h * S)
  if deg then spin(b.c, deg) end
  return b
end

local function hideBaked()
  for _, rec in pairs(baked) do
    for i = 1, #rec.insts do
      local inst = rec.insts[i]
      if inst.used ~= frame and inst.vis then inst.c:SetVisible(false); inst.vis = false end
    end
  end
end

-- 逻辑层可能给出被按字节截断的中文（打字机效果 line:sub(1,n)）→ 非法 UTF-8 会让
-- JS 侧字符串转换抛 "cannot convert invalid utf8 to javascript string"，这里补齐/丢弃残字节。
local function safeUtf8(s)
  if type(s) ~= 'string' then return tostring(s) end
  local n = #s
  local i = n
  while i >= 1 and i > n - 4 do
    local b = s:byte(i)
    if b < 0x80 then return s:sub(1, i) end
    if b >= 0xC0 then
      local need = (b >= 0xF0) and 4 or ((b >= 0xE0) and 3 or 2)
      if i + need - 1 <= n then return s:sub(1, i + need - 1) end
      return s:sub(1, i - 1)
    end
    i = i - 1
  end
  return s:sub(1, math.max(0, i))
end

local function label(c, txt, size, color, align)
  local m = st(c)
  if m.t ~= txt then c.text = safeUtf8(txt); m.t = txt end
  -- fontSize 是**整数属性**：写小数会抛
  --   bad argument #2 to 'fontSize' (integer expected, got number)
  -- 而 draw 整体被 pcall 包着 → 整帧绘制中断，画面停住并每帧刷屏。
  -- 字号是缩放后的值（size * S），手机 S=1.5 恰好都是整数，PC S=1.875 就不是了
  -- （14*1.875=26.25 / 12*1.875=22.5）→ 这里统一四舍五入并保证 ≥1。
  local fs = tonumber(size)
  if fs then
    fs = math.floor(fs + 0.5)
    if fs < 1 then fs = 1 end
  end
  if fs and m.fs ~= fs then c.fontSize = fs; m.fs = fs end
  if color and m.fc ~= color then c.fontColor = M.apiColor(color); m.fc = color end
  if align and m.al ~= align then c.horizontalAlignment = M.enumValue('TextHorizontalAlignment', align) or align; m.al = align end
end

-- ---------------------------------------------------------------- 图元

-- 轴对齐：世界左上角 (x,y) + 宽高
local function rect(x, y, w, h, color)
  local c = take('rect'); if not c then return nil end
  put(c, wx(x), wyBottom(y + h), w * S, h * S); tint(c, color); return c
end

local function circle(x, y, d, color)
  local c = take('circle'); if not c then return nil end
  put(c, wx(x), wyBottom(y + d), d * S, d * S); tint(c, color); return c
end

-- 中心锚点 + 旋转：世界中心 (cx,cy)
local function putRot(c, cx, cy, w, h, deg)
  put(c, wx(cx) - CW / 2, wyBottom(cy) - CH / 2, w * S, h * S)
  spin(c, deg)
end

local function rrect(cx, cy, w, h, deg, color)
  local c = take('rot'); if not c then return nil end
  putRot(c, cx, cy, w, h, deg); tint(c, color); return c
end

local function rtri(cx, cy, w, h, deg, color)
  local c = take('rtri'); if not c then return nil end
  putRot(c, cx, cy, w, h, deg); tint(c, color); return c
end

local function text(s, x, y, w, size, color, align)
  local c = take('text'); if not c then return nil end
  put(c, wx(x), wyBottom(y + size * 1.4), w * S, size * 1.4 * S)
  label(c, s, size * S, color, align or 'Left')
  return c
end

-- ---------------------------------------------------------------- 复合外观

-- 骨头：骨干 + 两端各**两颗分离骨球**（按原版贴图拟合，见 tools/fit-sprites.py）
-- 参考：Textures/BoneV.png 10×24 / BoneH.png 24×10（exact 游程 13 个矩形）。
-- 参数化拟合只用 5 个图元（1 rect + 4 circle），数量与原实现相同：
--   k = 0.6 × 短边 = 骨球直径；骨干宽/高 = k；两端各收进 k/3。
-- 端点必须画成两颗球（原为两颗重合的大圆 → 胶囊形，不是骨头）。
local function drawBone(cmd)
  local x, y, w, h = cmd.x, cmd.y, cmd.w or 10, cmd.h or 10
  local col = BONE_COLORS[(cmd.color or 0) + 1] or C_WHITE
  local a = cmd.alpha or 1
  if a < 1 then
    local rgb = col & 0xFFFFFF
    col = ((math.floor(((col >> 24) & 0xFF) * a)) << 24) | rgb
  end
  local vertical = cmd.vertical
  if vertical == nil then vertical = (h >= w) end
  -- 骨球直径：短边的 0.6（原版 10 宽 → 6px 球）。钳到 ≥4，避免细骨退化成点。
  local k = math.min(w, h) * 0.6
  if k < 4 then k = 4 end
  if k > w then k = w end
  if k > h then k = h end
  if vertical then
    rect(x + (w - k) / 2, y + k / 3, k, math.max(1, h - 2 * k / 3), col)
    circle(x, y, k, col)
    circle(x + w - k, y, k, col)
    circle(x, y + h - k, k, col)
    circle(x + w - k, y + h - k, k, col)
  else
    rect(x + k / 3, y + (h - k) / 2, math.max(1, w - 2 * k / 3), k, col)
    circle(x, y, k, col)
    circle(x + w - k, y, k, col)
    circle(x, y + h - k, k, col)
    circle(x + w - k, y + h - k, k, col)
  end
end

-- 颜色工具（只给下面的复合外观用）------------------------------------------

-- 按比例调 alpha：颜色是 0xAARRGGBB 整数，k ∈ [0,1]（半透明预告/淡出都走它）
local function shade(col, k)
  if k >= 1 then return col end
  local al = 0
  if k > 0 then al = math.floor(((col >> 24) & 0xFF) * k + 0.5) end
  return (al << 24) | (col & 0xFFFFFF)
end


-- 龙骨炮：CodeArt 几何像素配方（reference/sprites 57×44，Default + 3 个开火帧）。
--   炮身 = fitdata 容器（每个实例一套子控件，可同时画多发）；光束/炮口亮块仍走池内旋转矩形。
--   尺寸：Size 0/1/2 → ×0.8/1.0/1.3；蓄力期再整体 0.82 → 1.0。
--   局部坐标：u 向炮口、v 向炮身上；P(u,v) 做旋转；deg = -ang（世界 Y 向下、引擎 rotationZ 逆时针）。
local function drawBlaster(cmd)
  -- x/y 兜底：整帧绘制被 pcall 包着 —— 少一个坐标就会中断**整帧**，宁可画在 (0,0)
  local bx, by = cmd.x or 0, cmd.y or 0
  local a = cmd.alpha or 1
  if a <= 0 then return end
  local charge = cmd.charge or 0
  if charge < 0 then charge = 0 elseif charge > 1 then charge = 1 end
  local fire = cmd.fire or 0
  if fire < 0 then fire = 0 elseif fire > 1 then fire = 1 end

  -- 朝向：优先 core 给的世界角 ang（随机角度龙骨炮），退化时按四向 dir
  local fx, fy, deg
  local ang = cmd.ang
  if type(ang) == 'number' then
    local rad = ang * math.pi / 180
    fx, fy, deg = math.cos(rad), math.sin(rad), -ang
  else
    local dir = cmd.dir or 0
    fx = (dir == 0 and 1) or (dir == 2 and -1) or 0
    fy = (dir == 1 and 1) or (dir == 3 and -1) or 0
    deg = (dir == 0 and 0) or (dir == 1 and -90) or (dir == 2 and 180) or 90
  end
  local function P(u, v) return bx + fx * u + fy * v, by + fy * u - fx * v end

  -- 尺寸：Size 0/1/2 → ×0.8/1.0/1.3；蓄力期再整体 0.82 → 1.0（飞到位时张开）
  local sc = (cmd.scale or 1) * (0.82 + 0.18 * charge)
  local u0 = BLASTER_MUZZLE_U * sc

  -- ① 光束（先画 → 沉在颅骨下面）。默认长 1200：判定带 2000px，画到能盖住整屏，
  --    保证「看得见的打得到」；宽度 = cmd.w（= 命中带宽度，两边同源）。
  local bw = cmd.w or BLASTER_BAND[(cmd.size or 0) + 1] or BLASTER_BAND[1]
  if fire > 0 then
    local len = cmd.length or 1200
    local k = a * fire
    local span = len - u0
    if span < 10 then span = 10 end
    local cxp, cyp = P(u0 + span / 2, 0)
    rrect(cxp, cyp, span, bw, deg, shade(C_BEAM_WHITE, k * 0.78))                 -- 外壳（满宽、略暗）
    rrect(cxp, cyp, span, math.max(3, bw * 0.40), deg, shade(C_BEAM_WHITE, k))    -- 亮核
  end

  -- 炮身统一使用 CodeArt 配方；终盘旋转段用较粗 LOD 控制控件数量。
  local block = fit and fit.blaster_block2
  if cmd.lod == 'block3' and fit then block = fit.blaster_block3 end
  if block then
    local key = fire > 0 and 'fire_4' or 'Default'
    local rects = block[key] or block.Default
    for _, r in ipairs(rects or {}) do
      local u = (r.x + r.w / 2 - 28.5) * sc
      local v = (22 - r.y - r.h / 2) * sc
      local px, py = P(u, v)
      rrect(px, py, r.w * sc, r.h * sc, deg, shade(r.c, a))
    end
  end

  -- ③ 炮口亮块（画在最上面）：开火时压在吻部前端
  if fire > 0 then
    local mx, my = P(u0, 0)
    local mw = math.max(10, bw * 0.9)
    rrect(mx, my, mw, mw, deg, shade(C_BEAM_WHITE, a * fire))
  end
end
-- 审判者「sans 本人」：CodeArt 几何像素配方（reference/sprites SansBody + SansHead）。
--   身体 = fit.sans_body_*，头 = fit.sans_head_default / sans_head_blue；头按原工程 C2 image point
--   （SansHead 原点(0.5,1) 放到 SansBody 的 Head 点）合成，所以头在身体上方。
--   Left 姿势水平镜像；表情和疲惫身体按脚本键选择。
--   坐标：core 输出世界绝对坐标（640×480，Y 向下）；脚底锚定 feet = cmd.y + SANS_H。
local SANS_H = 148
-- 烘焙 Sans：参考身体是 1:1 像素（64×70 / 96×48），这里整体放大到接近原观感。
-- 脚底锚定（feet = cmd.y + SANS_H），所以各姿势的帧高不同也不会漂。
local SANS_BAKE_SCALE = 1.6
local function drawSans(cmd)
  local x = cmd.x or 320
  local y = cmd.y or 326
  local a = cmd.alpha or 1
  if a <= 0 then return end
  local dodge = cmd.dodge or 0
  if dodge < 0 then dodge = 0 elseif dodge > 1 then dodge = 1 end
  x = x + 42 * dodge                              -- 闪身：整体侧移
  local head = cmd.head or 'Default'
  local body = cmd.body
  local sweat = tonumber(cmd.sweat) or 0
  if sweat < 0 then sweat = 0 elseif sweat > 3 then sweat = 3 end

  -- 只使用 CodeArt 几何像素配方模型；fitdata 缺失时**不再回退旧参数化模型**（避免新旧两套外观并存）。
  if not (fit and fit.sans_poses) then
    if not fitWarned then fitWarned = true; print('main: fitdata 缺失，Sans 烘焙模型不可用') end
    return
  end
  local poseKey = 'default'
  if body == 'HandUp' then poseKey = 'up'
  elseif body == 'HandDown' then poseKey = 'down'
  elseif body == 'HandLeft' then poseKey = 'left'
  elseif body == 'HandRight' then poseKey = 'right' end
  local pose = fit.sans_poses[poseKey]
  local bodyKey = pose and pose.body
  if cmd.anim == 'Tired' or cmd.torso == 'Tired' or cmd.torso == 'Sweat' then
    bodyKey = fit.sans_body_variants[poseKey .. '_tired'] or bodyKey
  end
  local bspec = bodyKey and fit[bodyKey]
  local hkey = (fit.sans_head_keys and fit.sans_head_keys[head]) or fit.sans_head_default_key
  local hspec = hkey and fit[hkey]
  if not (pose and bspec and hspec) then return end

  local K = SANS_BAKE_SCALE
  local kx, ky = K, K
  local bw, bh = bspec.w * kx, bspec.h * ky
  local feet = y + SANS_H
  local bx = x - bw / 2
  local by = feet - bh
  local mir = pose.mirror and true or false
  useBakedCorner(bodyKey, bx, by, bw, bh, mir)
  local offx = pose.hx or 0
  if mir then offx = bspec.w - offx - hspec.w end
  local hx = bx + offx * kx
  local hy = by + (pose.hy or 0) * ky
  useBakedCorner(hkey, hx, hy, hspec.w * kx, hspec.h * ky, mir)

  -- 【已删除·2026-10-06】原来这里画过「砸击方向提示」箭头（Sans 右侧的橙色矩形+三角）。
  -- 用户口径：删去先前指示方向的箭头模型 —— 起手方向改由 SansBody 的手势姿势本身表达。
  -- 不要再加回来：它和手势是同一信息的两次表达，叠在一起反而更乱。

  -- 汗滴：头右侧
  if sweat > 0 then
    local sx0 = hx + hspec.w * kx
    local sy0 = hy + 4 * ky
    for i = 1, sweat do
      circle(sx0 + (i - 1) * 5 * kx, sy0 + (i - 1) * 6 * ky, 4 * kx, shade(C_SANS_SWEAT, a))
    end
  end
end

-- 灵魂：双圆瓣 + 倒三角（红心近似，原作 16×16）
local function drawSoul(cmd)
  if cmd.visible == false then return end
  -- 菜单 / 子面板状态：原版的心停在选中按钮左边（由 drawMenu / drawSub 画），框里不画心
  if state and (state.state == 'menu' or state.state == 'sub') then return end
  local x, y = cmd.x, cmd.y
  absSoul = { x = x, y = y }                   -- 记绝对坐标，供指针转向比较
  local col = (cmd.mode == 'blue') and C_BLUE or C_RED
  if cmd.invuln and (frame % 8) < 4 then col = 0x66FFFFFF end
  local key = 'soul_red'
  if cmd.mode == 'blue' then
    local directions = { [0] = 'right', [1] = 'down', [2] = 'left', [3] = 'up' }
    key = 'soul_blue_' .. (directions[cmd.dir or 1] or 'down')
  end
  local spec = fit and fit[key]
  if spec then
    for _, r in ipairs(spec.rects) do
      rect(x - 8 + r.x, y - 8 + r.y, r.w, r.h, cmd.invuln and (frame % 8) < 4 and 0x66FFFFFF or r.c)
    end
  end
end

local function drawBox(cmd)
  -- 用平滑后的 curBox 画（逻辑层每帧给目标，瞬时重设看起来像乱跳）
  local x, y, w, h = curBox.x, curBox.y, curBox.w, curBox.h
  rect(x, y, w, 4, C_BOX)
  rect(x, y + h - 4, w, 4, C_BOX)
  rect(x, y, 4, h, C_BOX)
  rect(x + w - 4, y, 4, h, C_BOX)
end

local function drawPlatform(cmd)
  rect(cmd.x, cmd.y, cmd.w, cmd.h, cmd.color or 0xFF00FF00)
end

-- 菜单选择心与战斗灵魂共用像素配方。
local function heart(cx, cy, col, r)
  local spec = fit and fit.soul_red
  if not spec then return end
  local k = (r or 6) / 8
  for _, q in ipairs(spec.rects) do
    rect(cx + (q.x - 8) * k, cy + (q.y - 8) * k, q.w * k, q.h * k, col)
  end
end

-- 菜单项是否选中（抽成纯函数，便于单元测试）：
--   * 按钮行：一条命令带 N 项，`index` 是 **0 基**选中下标 → 第 i 项（1 基）选中当且仅当 i == index+1；
--   * 标题页难度卡：一卡一条命令、`index` 恒为 0，选中与否由布尔 `selected` 决定 → 布尔优先。
-- 这两条混用会出错（0 基/1 基错位让心画在上一项；或四张卡全部高亮），已经踩过两次。
local function menuItemSelected(cmd, i)
  if cmd.selected ~= nil then return cmd.selected == true end
  return i == (cmd.index or 0) + 1
end

local function drawMenu(cmd)
  if cmd.visible == false then return end
  local x, y, w = cmd.x, cmd.y, cmd.w
  local items = cmd.items or {}
  local n = #items
  if n == 0 then return end
  -- 核心的菜单是「一排等宽按钮」：x/w 是第一个按钮的矩形，后续按 w+gap 排开。
  -- 原版：框下方一行四个按钮（攻击/行动/道具/仁慈），心停在选中的那个左边，**没有横杠**。
  -- 文字与心都**画在按钮矩形内部**（跟 menuHitTest 用同一套矩形）：以前文字画在 y+22（矩形外），
  -- 命中框却在 y-6..y+34 —— 玩家点看得见的字，判定落空，表现就是「点了没反应」。
  local gap = cmd.gap or 10
  local bh = cmd.h or 36
  local fs = 22                                   -- 标签字号（世界单位）
  local ty = y + (bh - fs * 1.4) / 2              -- 文字盒顶部：让标签在按钮矩形内垂直居中
  for i, it in ipairs(items) do
    local bx = x + (i - 1) * (w + gap)
    local selected = menuItemSelected(cmd, i)
    local edge = selected and C_HP or BONE_COLORS[3]
    rect(bx, y, w, 2, edge); rect(bx, y + bh - 2, w, 2, edge)
    rect(bx, y, 2, bh, edge); rect(bx + w - 2, y, 2, bh, edge)
    if selected then heart(bx + 12, y + bh / 2, C_RED, 6) end
    text(it, bx + 22, ty, w - 26, fs, edge, 'Middle')
  end
end

-- 水平对齐映射：core 用小写 'left'/'center'/'right'，而引擎的枚举只有 Left/Middle/Right
-- （worker.js：horizontalAlignment:"TextHorizontalAlignment" → TextHorizontalAlignment:["Left","Middle","Right"]）。
-- 直接写 'center' 是无效值 → 渲染退回左对齐：标题「弹 幕 审 判」整体偏到右边、四张难度卡的注释
-- 也各自右移 170px（看着像"注释挂错卡片"）。这里统一映射，并把 340 宽的文本框按对齐方式摆正：
--   Left → x 是左边缘（原样）；Middle → x 是中心；Right → x 是右边缘。
local HUD_W = 340
local ALIGN = { left = 'Left', center = 'Middle', middle = 'Middle', right = 'Right',
                Left = 'Left', Middle = 'Middle', Right = 'Right' }

function M.paintSpec(spec, x, y, k, color)
  if not spec then return end
  for _, q in ipairs(spec.rects) do
    rect(x + q.x * k, y + q.y * k, q.w * k, q.h * k, color or q.c)
  end
end

function M.drawResultEmblem(cmd)
  local spec = fit and fit[cmd.failed and 'soul_broken' or 'soul_red']
  local size = cmd.size or 32
  if spec then M.paintSpec(spec, cmd.x - size / 2, cmd.y - size / 2, size / spec.w) end
end

function M.drawBackdrop(cmd)
  M.runtime.paintLayer = 'uiBackdrop'
  rect(cmd.x, cmd.y, cmd.w, cmd.h, 0xFF000000)
end

local function drawHud(cmd)
  local a = ALIGN[cmd.align or 'Left'] or 'Left'
  if fit and fit.codeart and cmd.text:match('^[A-Z0-9 /]+$') then
    M.runtime.pixelLabels = M.runtime.pixelLabels or {}
    local spec = M.runtime.pixelLabels[cmd.text]
    if not spec then spec = fit.codeart.pixelText(cmd.text); M.runtime.pixelLabels[cmd.text] = spec end
    local k = (cmd.size or 20) / 7
    local x = cmd.x
    if a == 'Middle' then x = x - spec.w * k / 2 elseif a == 'Right' then x = x - spec.w * k end
    M.paintSpec(spec, x, cmd.y, k, toColor(cmd.color))
    return
  end
  local x = cmd.x
  if a == 'Middle' then x = x - HUD_W / 2
  elseif a == 'Right' then x = x - HUD_W end
  text(cmd.text, x, cmd.y, HUD_W, cmd.size or 20, toColor(cmd.color), a)
end

-- 闪层是否可画（纯函数，便于单元测试）：结局态下 core 每帧推 alpha=1 的全屏白闪，
-- 而闪层是最上层控件，永久画着就会盖住结局文字与重开项 → 只允许它闪前 15 帧（约 0.5s）。
local function flashDrawable(stateName, n)
  if stateName == 'result' then return n <= 15 end
  return true
end

local function drawFlash(cmd)
  if not flash then return end
  local a = cmd.alpha or 0
  if a <= 0 then return end          -- 核心在 flash=0 时不发命令；不主动关会残留成整屏灰纱
  -- 结局态：core 每帧都推 alpha=1 的全屏白闪，而闪层是**最后创建的最上层**，
  -- 于是把「GAME OVER / 击倒结局 / 饶恕结局」文字和「重开」按钮永久盖住 → 玩家只看到白屏。
  -- 这里让它在结局态只闪约 0.5 秒（15 帧），之后收起闪层，露出结局文字与重开项。
  if state and state.state == 'result' then
    resultFlashN = resultFlashN + 1
    if not flashDrawable('result', resultFlashN) then
      local m = st(flash)
      if m.vis ~= false then flash:SetVisible(false); m.vis = false end
      return
    end
  else
    resultFlashN = 0
  end
  local col = cmd.color or C_WHITE
  local rgb = col & 0xFFFFFF
  col = ((math.floor(255 * a)) << 24) | rgb
  put(flash, 0, 0, CW, CH)
  tint(flash, col)
  local m = st(flash)
  if m.vis ~= true then flash:SetVisible(true); m.vis = true end
end

-- 骨刺：从战斗框某条边刺出的骨（peek 预告半透明 → extend 伸出 → hold → retract）
local function drawStab(cmd)
  local x, y, w, h, dir = cmd.x, cmd.y, cmd.w, cmd.h, cmd.dir or 0
  if w <= 0 or h <= 0 then return end
  local peek = (cmd.phase == 'peek')
  local alpha = peek and 0.45 or (cmd.alpha or 1)
  drawBone({ x = x, y = y, w = w, h = h, vertical = (h >= w), color = 0, alpha = alpha })
  local thick = (h >= w) and w or h
  local deg = (dir == 0 and 90) or (dir == 1 and 180) or (dir == 2 and -90) or 0
  local tx, ty
  -- 【2.6】方向语义改为 0=右 1=下 2=左 3=上 → 三角放在**朝框内**的那条边
  if dir == 0 then tx, ty = x, y + h / 2
  elseif dir == 2 then tx, ty = x + w, y + h / 2
  elseif dir == 1 then tx, ty = x + w / 2, y
  else tx, ty = x + w / 2, y + h end
  if dir == 0 or dir == 2 then
    rtri(tx, ty, 9, thick, deg, peek and 0x88FFFFFF or C_WHITE)
  else
    rtri(tx, ty, thick, 9, deg, peek and 0x88FFFFFF or C_WHITE)
  end
end

-- 细长条（正弦骨长骨）：矩形 + 两端等厚圆帽，避免 drawBone 的 13px 骨球撑破 8px 厚的长骨
local function drawBar(x, y, w, h, color)
  rect(x, y, w, h, color)
  local d = math.min(w, h)
  if w >= h then
    circle(x, y, d, color)
    circle(x + w - d, y, d, color)
  else
    circle(x, y, d, color)
    circle(x, y + h - d, d, color)
  end
end

-- 正弦骨：上下两根长骨夹一条走廊。
-- core 的 sine 命令给出 centerY（走廊中心，绝对）、gap、amp、phase；
-- `bars` 目前是 19×8 的**命中盒**而不是长骨（已反馈），所以只在它确实是细长条时才直接用。
local function drawSine(cmd)
  -- 曾经这里有一段「centerY 若在框外就整体减 BOX_OFF_Y 纠正」的回退（防 core 又多做一次平移）。
  -- core 自 2026-10-04 起 sine 也走脚本绝对帧（`bars[1].y == zone.t`，不经 shiftAbs），
  -- 该分支在 20 场完整对局里 0 次命中（临时探针实测），已删；core 若再犯平移错，
  -- `lua/_geometry.lua` 的「绘制 == 判定几何」逐帧对账会直接变红，不需要在运行时悄悄修好。
  local bars = cmd.bars
  local longEnough = false
  if type(bars) == 'table' then
    for i = 1, 2 do
      local b = bars[i]
      if b and type(b.w) == 'number' and type(b.h) == 'number' and math.max(b.w, b.h) >= 30 then
        longEnough = true
      end
    end
  end
  if longEnough then
    for i = 1, 2 do
      local b = bars[i]
      if b and b.w > 0 and b.h > 0 then drawBar(b.x, b.y, b.w, b.h, C_WHITE) end
    end
    return
  end
  -- 按 centerY / gap 拼两根长骨：从走廊口一直顶到战斗框上下边
  local gap = cmd.gap or 25
  local cy = cmd.centerY or (curBox.y + curBox.h / 2)
  local top, bot = curBox.y, curBox.y + curBox.h
  local bw = 19
  local cx = cmd.x + (cmd.w or 0) / 2          -- 命中盒中心 = 骨中心
  local upH = (cy - gap / 2) - top
  local dnH = bot - (cy + gap / 2)
  if upH > 2 then drawBar(cx - bw / 2, top, bw, upH, C_WHITE) end
  if dnH > 2 then drawBar(cx - bw / 2, cy + gap / 2, bw, dnH, C_WHITE) end
end

-- 骨墙：整高屏障原地升降，缺口预警（GDD：同时只允许一道）
local function drawWall(cmd)
  local lanes = cmd.lanes or 4
  local laneW = cmd.w / lanes
  local gapS = cmd.gapStart or 0
  local gapW = cmd.gapW or 1
  if cmd.phase == 'warn' then
    rect(cmd.x + gapS * laneW, cmd.y + cmd.h - 5, gapW * laneW, 5, 0xCCFFD200)
    return
  end
  local hCur = cmd.hCur or 0
  if hCur <= 1 then return end
  for L = 0, lanes - 1 do
    if not (L >= gapS and L < gapS + gapW) then
      -- 【2026-10-06 用户口径】每根窄于它那一道并居中：相邻两根间留 WALL_GAP 的缝，
      --   缝宽(24) > 灵魂视觉宽(16) → 可钻（core 碰撞用同一口径）。
      local bw = cmd.boneW or laneW
      drawBone({ x = cmd.x + L * laneW + (laneW - bw) / 2, y = cmd.y + cmd.h - hCur, w = bw, h = hCur,
                 vertical = true, color = 0 })
    end
  end
end

-- 中间的攻击条（原作：一条横线上的游标，决定这一回合是攻击还是落空）
local function drawAttackBar(cmd)
  local x, y, w, h = cmd.x, cmd.y, cmd.w, cmd.h
  rect(x + 16, y + h / 2 - 2, w - 32, 4, C_WHITE)
  local cxp = x + 16 + (cmd.cursor or 0.5) * (w - 32)
  rect(cxp - 3, y - 2, 6, h + 4, C_RED)
  if cmd.result == 'hit' then
    text('攻 击', x + w / 2 - 40, y - 30, 80, 18, C_HP, 'Middle')
  elseif cmd.result == 'miss' then
    text('落 空', x + w / 2 - 40, y - 30, 80, 18, C_DIM, 'Middle')
  end
end

-- 四个菜单子面板（道具 / 仁慈 / 战斗 / 行动）
-- 行布局（SUB_HEAD / subRowTop / subRowRect）定义在文件上方的「可点 UI 的行几何」段里，
-- 绘制与点击判定共用同一份，别在这里另写一套。
local function drawSub(cmd)
  local x, y, w, h = cmd.x, cmd.y, cmd.w, cmd.h
  M.runtime.paintLayer = 'uiBackdrop'
  rect(x, y, w, h, 0xE6000000)
  M.runtime.paintLayer = 'ui'
  rect(x, y, w, 4, C_WHITE)
  rect(x, y + h - 4, w, 4, C_WHITE)
  rect(x, y, 4, h, C_WHITE)
  rect(x + w - 4, y, 4, h, C_WHITE)
  text(cmd.title or '', x + 14, y + 10, w - 28, 20, C_HP, 'Left')
  local rows = cmd.rows or {}
  local total = cmd.total or #rows
  local view = cmd.view or #rows
  local top = cmd.top or 0
  for k = 1, view do
    local i = top + k                       -- 数据行号（1 基）
    local r = rows[i]
    if r then
      local ry = subRowTop(cmd, k)
      local sel = ((cmd.index or 0) + 1 == i)
      if sel then heart(x + 18, ry + 9, C_RED, 6) end
      local note = cmd.notes and cmd.notes[i]
      -- 【2026-10-07 用户口径】没有备注的行（行动）名字占满整行；有备注（道具 xN / 仁慈）时让出右侧 102px
      local fs = math.min(18, math.max(12, (cmd.rowH or 26) - 2))
      local nameW = (note and note ~= '') and (w - 142) or (w - 40)
      text(r, x + 28, ry, nameW, fs, sel and C_HP or C_WHITE, 'Left')
      -- 【2026-10-07 修】备注框原来写成 x+w-20 宽 90（text() 不会像 drawHud 那样按对齐回退宽度）→ 文字被画到面板外面；
      --   改为把框左边界放在 x+w-112、宽 92，右对齐后右缘正好落在面板内边距上。
      if note and note ~= '' then text(note, x + w - 112, ry, 92, 14, C_DIM, 'Right') end
    end
  end
  -- 【方案甲】还有未显示的行：右侧 ▲▼ + 一根细滚动条
  if total > view then
    local y0, y1 = y + 34, y + h - 8
    local span = math.max(4, y1 - y0)
    rect(x + w - 10, y0, 3, span, 0x33FFFFFF)
    local k = math.max(4, span * view / math.max(1, total))
    local ty = y0 + (span - k) * (top / math.max(1, total - view))
    rect(x + w - 10, ty, 3, k, 0xAAFFFFFF)
    if top > 0 then text('▲', x + w - 26, y + 16, 16, 12, C_DIM, 'Right') end
    if top + view < total then text('▼', x + w - 26, y + h - 30, 16, 12, C_DIM, 'Right') end
  end
  -- 【2026-10-07 用户口径】回血量/说明放到**面板右上角**（与标题同一行、右对齐），
  --   不再接在食物列表下面（那儿太挤：最后一行与说明只差 2~3px）。
  if cmd.desc and cmd.desc ~= '' then
    local dw = math.min(240, w - 120)
    text(cmd.desc, x + w - 20 - dw, y + 14, dw, 14, C_DIM, 'Right')
  end
end

-- HUD 血条：底槽 + 黄色（安全 HP）+ 紫色（KR / 蓝血）。
-- 原作口径：黄条长 = hp - kr、紫条长 = kr，合起来 = 当前 HP —— KR 燃烧时**黄段不动、紫段变短**。
-- 用池里的 rect 每帧现取（不永久占用），预算峰值见 lua/main.lua 的 BUDGET 注释 / lua/_pool.lua。
local function drawHudBar(cmd)
  local x, y, w, h = cmd.x, cmd.y, cmd.w, cmd.h
  local max = tonumber(cmd.max) or 1
  if max <= 0 then max = 1 end
  local hp = math.max(0, math.min(max, tonumber(cmd.hp) or 0))
  local kr = math.max(0, math.min(math.max(0, hp - 1), tonumber(cmd.kr) or 0)) -- 参考：KR <= HP-1，HP=1 时紫条为 0
  rect(x, y, w, h, 0xFF2A2A33)                                   -- 底槽
  rect(x, y, w * (hp / max), h, 0xFFFFD200)                      -- 黄色：当前 HP
  if kr > 0 then
    rect(x + w * ((hp - kr) / max), y, w * (kr / max), h, 0xFF9B5CFF)  -- 紫色：KR（蓝血）
  end
end

local DRAW = {
  bone = drawBone, blaster = drawBlaster, soul = drawSoul, box = drawBox,
  platform = drawPlatform, menu = drawMenu, hudText = drawHud, flash = drawFlash,
  stab = drawStab, sine = drawSine, wall = drawWall, attackBar = drawAttackBar, sub = drawSub,
  sans = drawSans,          -- 审判者本人（core 每帧都推一条，菜单/子面板态也在场）
  hudBar = drawHudBar,      -- 等级/血量/蓝血那条 HUD 血条
  resultEmblem = M.drawResultEmblem,
  hudBackdrop = M.drawBackdrop,
}

local function frameBegin()
  SHKX, SHKY = 0, 0   -- 【A-7】每帧先清零，由 shake 命令写入
  for k in pairs(used) do used[k] = 0 end
  -- 闪层每帧先关，由本帧的 flash 命令决定是否再打开（否则会残留）
  if flash then
    local m = st(flash)
    if m.vis == true then flash:SetVisible(false); m.vis = false end
  end
end

local function frameEnd()
  hideBaked()
  for kind, list in pairs(pool) do
    local u = used[kind] or 0
    for i = u + 1, #list do
      local c = list[i]
      if c then
        local m = st(c)
        if m.vis ~= false then c:SetVisible(false); m.vis = false end
      end
    end
  end
  -- 闪层永远最后创建 → 天然在最上层
  if flash then flash:SetAsLastSibling() end
end

-- 触摸端「再点一次确认」提示：位置按**本帧实际绘制的矩形**算；下面放不下就画到上面。
-- 只画给触摸分支（PC 点一下就生效，没有第二段）。
local function drawPendingHint()
  if not isTouch or not pendingSel then return nil end
  local bx, by, bw, bh
  if pendingSel.kind == 'menu' and lastMenu then
    bx, by, bw, bh = menuButtonRect(lastMenu, pendingSel.index + 1)
  elseif pendingSel.kind == 'sub' and lastSub then
    bx, by, bw, bh = subRowRect(lastSub, pendingSel.index + 1)
  else
    return nil                      -- 标题页的提示走那行固定文案（见 draw）
  end
  local boxW = 200
  local hx = clamp(bx + bw / 2 - boxW / 2, 2, W - boxW - 2)
  local hy = by + bh + 2
  if hy > H - 18 then hy = by - 15 end
  if hy < 2 then hy = H - 18 end
  return text('再 点 一 次 确 认', hx, hy, boxW, 12, C_HP, 'Middle')
end

local function draw(cmds)
  frameBegin()
  lastMenu, lastSub, lastBar = nil, nil, nil
  titleCards = {}
  for i = 1, #cmds do
    if cmds[i] and cmds[i].kind == 'shake' then SHKX, SHKY = cmds[i].x or 0, cmds[i].y or 0 end   -- 【A-7】
    local cmd = cmds[i]
    if cmd.kind == 'box' then
      -- core 契约（已统一）：render 出口就是**世界绝对坐标 640×480**，框中心恒为 (320, 308.5)。
      -- 这里**不再做任何坐标纠正** —— 曾经为了兼容 core 的帧③双平移/菜单上移 hack 写过自校正，
      -- core 改成单帧后它变成死代码，留着只会把真 bug 悄悄盖掉。现在只做「异常告警」：
      -- 中心偏离 >20px 或整框越界，就按原样画并打一条 WARN（只打一次），让问题暴露在日志里。
      --
      -- 【框必须"稳定"才判定】20 回合版里每个攻击脚本都会用 CombatZoneResize 把框从旧尺寸
      -- 动画到新尺寸（例如 randomblaster 的 165×165 → 405×165），动画中间那几帧框本来就在
      -- 半路上，中心自然偏离常量 —— 那不是 bug。所以先看 **core 给的框** 是否与上一帧相同，
      -- 连续 STABLE_FRAMES 帧不变才做判定（延迟判定，稳定的异常照样会报，只是晚几帧）。
      local bx, by, bw, bh = cmd.x, cmd.y, cmd.w, cmd.h
      if bx == prevCoreBox[1] and by == prevCoreBox[2] and bw == prevCoreBox[3] and bh == prevCoreBox[4] then
        boxStableN = boxStableN + 1
      else
        prevCoreBox = { bx, by, bw, bh }
        boxStableN = 0
      end
      local dxc = (bx + bw / 2) - ORIG_CX
      local dyc = (by + bh / 2) - ORIG_CY
      local ovr = boxOverflow(bx, by, bw, bh)
      if boxStableN >= BOX_STABLE_FRAMES
         and (math.abs(dxc) > CENTER_TOL or math.abs(dyc) > CENTER_TOL or ovr > 0) and not boxFixLogged then
        boxFixLogged = true
        print(string.format('main: WARN 战斗框坐标异常 (%.0f,%.0f) %.0fx%.0f 中心偏(%+.0f,%+.0f) 越界%.0fpx -- 已按原样绘制，请查 core',
          bx, by, bw, bh, dxc, dyc, ovr))
      end
      boxTarget = { x = bx, y = by, w = bw, h = bh }
    elseif cmd.kind == 'menu' then
      if state and state.state == 'title' then
        -- 标题页：每张难度卡各是一条 menu 命令，画在原位（core 给的 y=210），**不**挪到框下。
        titleCards[#titleCards + 1] = cmd
      else
        -- 按钮行 y：以**屏幕中心**为参照的固定值（CENTER_Y + MENU_ROW_DY_TOP = 432，逐像素对齐参考实现），
        -- 详见上面「按钮行定位」段。核心给的 y 只作参考（core 把行画在框内 y=306/400），这里整体改写。
        cmd.y = menuRowY(cmd.h)
        lastMenu = cmd
      end
    elseif cmd.kind == 'sub' then lastSub = cmd
    elseif cmd.kind == 'attackBar' then lastBar = cmd
    end
  end
  -- 脚本核心已经逐帧插值战斗框；再平滑一次会让显示边界落后于碰撞边界。
  if boxTarget then
    curBox.x, curBox.y, curBox.w, curBox.h = boxTarget.x, boxTarget.y, boxTarget.w, boxTarget.h
  end
  -- 标题页提示行（core 只发标题 + 四张难度卡与注释，操作提示由本层补；两平台给不同的提示）
  local titleNow = (state ~= nil and state.state == 'title')
  M.runtime.paintLayer = 'ui'
  if titleNow then
    if isTouch then
      if pendingSel and pendingSel.kind == 'title' then
        text('再 点 一 次 开 始    ·    点其它难度卡可改选', 0, 296, W, 16, C_HP, 'Middle')
      else
        text('点难度卡选中    ·    再点一次开始', 0, 296, W, 16, C_DIM, 'Middle')
      end
    else
      text('← → 选难度    ·    Z / 空格确认    ·    X 返回', 0, 296, W, 16, C_DIM, 'Middle')
    end
  end
  -- 本帧真正画出去的命令种类（回归用：标题页必须没有 box）
  drawnKinds = {}
  for i = 1, #cmds do
    local cmd = cmds[i]
    if DRAW[cmd.kind] then
      -- 标题页**不画战斗框**：core 在 title 态也会推一条 box（战斗态复用同一位置），
      -- 但它会把白框横穿四张难度卡 —— 直接跳过绘制，其它状态照旧。
      local skip = cmd.kind == 'box' and (titleNow or (state and state.state == 'result'))
      if not skip then
        M.runtime.paintLayer = ({menu=true,sub=true,hudText=true,hudBar=true,hudBackdrop=true,attackBar=true,resultEmblem=true})[cmd.kind]
          and 'ui' or (cmd.kind == 'soul' and 'soul' or 'world')
        if cmd.kind == 'box' then drawnBox = true end
        drawnKinds[#drawnKinds + 1] = cmd.kind
        DRAW[cmd.kind](cmd)
      end
    end
  end
  -- 两平台各自的常驻操作提示（PC = 键位；触摸 = 两段式点按）
  M.runtime.paintLayer = 'ui'
  if not titleNow then
    M.runtime.paintLayer = 'uiBackdrop'
    rect(0, 42, W, 18, 0xFF000000)
    M.runtime.paintLayer = 'ui'
    if isTouch then
      text('左半屏拖动移动    ·    点击选项选中，再次点击确认', 0, 44, W - 20, 10, C_DIM, 'Right')
    else
      text('WASD / 方向键移动    ·    Z / 空格确认    ·    X 返回 / 慢走', 0, 44, W - 20, 10, C_DIM, 'Right')
    end
  end
  drawPendingHint()      -- 触摸端「再点一次确认」提示（画在选中项旁边）
  frameEnd()
end

-- ---------------------------------------------------------------- 输入

-- 按键诊断（**只打第一条**）：试玩页那一层负责把物理键（WASD/方向键/Enter…）翻成引擎语义键
-- （`KeyboardMoveForwardKeyDown` 等，见 studio/play/browser-session.js 的 SEMANTIC_KEY_CODES），
-- 插件试玩页加载的是 dsh-plugin/dist/play-renderer.js 里打包的同一张表。
-- 如果用户按了 WASD 却**从未**看到这行，就说明按键在试玩页那一层就被丢了（映射缺失/页面没转发），
-- 而不是游戏逻辑没响应；看到这行则说明事件已到达 Lua，问题在别处。
local keyDiagLogged = false
local function bind(name, fn)
  if not root then return end
  local event = M.enumValue('KeyEventType', name)
  if event == nil then return end
  local ok, err = pcall(function()
    local callback = function()
      if not keyDiagLogged then
        keyDiagLogged = true
        print(string.format('main: 收到按键事件 %s（若你按了 WASD 却从未出现这行，说明试玩页那层没转发按键）', name))
      end
      fn()
      return true
    end
    root:AddKeyEventListener(event, callback)
    M.runtime.keyListeners[#M.runtime.keyListeners + 1] = { event, callback }
  end)
  if not ok then print('main: bind fail ' .. name .. ' :: ' .. tostring(err)) end
end

-- 官方语义按键：WASD 与方向键分别注册，按住状态按实际按键合并。
-- 可选的 MenuConfirm/MenuBack 仅用于旧外部模拟器；官方不存在时跳过。
local KEY_DIRS = {
  { dir = 'up',    down = 'KeyboardMoveForwardKeyDown',  up = 'KeyboardMoveForwardKeyUp' },
  { dir = 'down',  down = 'KeyboardMoveBackwardKeyDown', up = 'KeyboardMoveBackwardKeyUp' },
  { dir = 'left',  down = 'KeyboardMoveLeftKeyDown',     up = 'KeyboardMoveLeftKeyUp' },
  { dir = 'right', down = 'KeyboardMoveRightKeyDown',    up = 'KeyboardMoveRightKeyUp' },
}

-- 方向位写入：按下/抬起各写一次，值没变就不打日志（防刷屏）。日志用于试玩实证。
local function setDir(dir, v)
  if input[dir] == v then return end
  input[dir] = v
  print(string.format('main: 键盘 %s %s', v and '按下' or '抬起', dir))
end

local function bindKeys()
  local dirs = {
    up = { 'KeyboardMoveForwardKey', 'KeyboardCraftspersonKey36', 'ControllerCharacterSkill3Key' },
    down = { 'KeyboardMoveBackwardKey', 'KeyboardCraftspersonKey37', 'ControllerCraftspersonKey2' },
    left = { 'KeyboardMoveLeftKey', 'KeyboardCraftspersonKey38', 'ControllerCraftspersonKey1' },
    right = { 'KeyboardMoveRightKey', 'KeyboardCraftspersonKey39', 'ControllerCharacterSkill4Key' },
  }
  for dir, names in pairs(dirs) do
    local d = dir
    M.runtime.heldDirections[d] = {}
    for _, name in ipairs(names) do
      local n = name
      local function change(value)
        M.runtime.heldDirections[d][n] = value
        local active = false
        for _, v in pairs(M.runtime.heldDirections[d]) do if v then active = true end end
        setDir(d, active)
      end
      bind(n .. 'Down', function() change(true) end)
      bind(n .. 'Up', function() change(false) end)
    end
  end
  local function bindAction(names, held, confirm)
    for _, name in ipairs(names) do
      local n = name
      local function change(value)
        local before = false
        for _, v in pairs(held) do if v then before = true end end
        held[n] = value
        local active = false
        for _, v in pairs(held) do if v then active = true end end
        if confirm then
          if active and not before then edgeConfirm = true end
          confirmHeld = active
        else
          if active and not before then edgeCancel = true end
          M.runtime.cancelHeld = active
        end
      end
      bind(n .. 'Down', function() change(true) end)
      bind(n .. 'Up', function() change(false) end)
    end
  end
  bindAction({ 'KeyboardCraftspersonKey12', 'KeyboardCraftspersonKey19',
    'KeyboardJumpKey', 'ControllerJumpKey', 'ControllerMenuConfirmKey',
    'KeyboardMenuConfirmKey' }, M.runtime.heldConfirm, true)
  bindAction({ 'KeyboardDropKey', 'KeyboardCraftspersonKey42',
    'ControllerNormalAttackKey', 'ControllerMenuBackKey',
    'KeyboardMenuBackKey' }, M.runtime.heldCancel, false)
end

local function consumeEdges()
  local c, x = edgeConfirm, edgeCancel
  edgeConfirm, edgeCancel = false, false
  return c, x
end

-- ---------------------------------------------------------------- 指针 / 触摸

local function ptrPos(e)
  local x, y
  local ok = pcall(function() x, y = e.x, e.y end)
  if not ok or type(x) ~= 'number' or type(y) ~= 'number' then
    local ok2, a, b = pcall(function() return e:GetUIPos() end)
    if ok2 then x, y = a, b end
  end
  if type(x) ~= 'number' or type(y) ~= 'number' then return nil end
  return x, y
end

function M.touchId(e)
  local ok, id = pcall(function() return e.touchId end)
  return ok and id or 0
end

local handleClick          -- 前置声明：事件回调里同步调用（定义在下面）
local toWorld              -- 前置声明：画布 → 世界绝对坐标

local function onPointer(e, isClick, name)
  local x, y = ptrPos(e)
  if not ptr.logged or (name and name ~= 'CursorDrag') then
    ptr.logged = true
    print(string.format('main: 游标 %s x=%s y=%s click=%s moved=%s', tostring(name), tostring(x), tostring(y),
      tostring(isClick), tostring(ptr.moved)))
  end
  if not x then return end
  ptr.x, ptr.y = x, y
  if isClick then
    -- 只处理「命中界面元素」的点按；没命中就什么都不做。
    -- 以前这里兜底成一次「确认」，导致随便拖动/松手都会推进相位，战斗框在两套位置间反复跳。
    handleClick(x, y)
  end
end

local function bindPointer()
  if not cursorArea then
    print('main: 无游标控件，指针输入不可用')
    return
  end
  local ok, err = pcall(function()
    cursorArea:AddCursorEventListener(M.enumValue('CursorEventType', 'CursorDown') or 'CursorDown', function(e)
      if M.runtime.pointerTouch ~= nil then return true end
      M.runtime.pointerTouch = M.touchId(e)
      ptr.down = true
      ptr.tapPending = false
      joy.consumed = false
      local x, y = ptrPos(e)
      if not x then return end
      ptr.downX, ptr.downY, ptr.moved = x, y, false
      if isTouch then
        -- 触摸分支：左半屏按下 = 虚拟摇杆（不必精确点中圆）；点在菜单/面板/攻击条上则交给 UI。
        -- 只在**敌方阶段**起摇杆：其它状态 core 根本不读方向输入（菜单/子面板/攻击条/结局），
        -- 起了只会把点按吞掉（实测：攻击条阶段点左半屏本来该结算，却因为摇杆消费了 CursorUp 而没反应）。
        local twx, twy = toWorld(x, y)
        if state and state.state == 'enemy' and inJoyZone(twx) and not uiHit(twx, twy) then
          joy.active = true
          joy.bx, joy.by = twx, twy
          joy.kx, joy.ky, joy.dx, joy.dy = 0, 0, 0, 0
        end
      end
      -- PC 分支：这里**什么都不做** —— 鼠标只在 UI 上起作用，拖动不产生任何移动、也不画摇杆
      onPointer(e, false, 'CursorDown')
    end)
    cursorArea:AddCursorEventListener(M.enumValue('CursorEventType', 'CursorDrag') or 'CursorDrag', function(e)
      if M.runtime.pointerTouch ~= M.touchId(e) then return true end
      ptr.down = true
      local x, y = ptrPos(e)
      if not x then return end
      ptr.x, ptr.y = x, y
      if isTouch and joy.active then
        local twx, twy = toWorld(x, y)
        -- 全用**世界坐标**（Y 向下）算：往上拖 = 世界 y 变小 = dy<0 → 上（灵魂 y 减小）。
        -- 杆头 (kx,ky) 与方向位 (dx,dy) 来自**同一个**原始偏移（joyVector），
        -- 绘制那侧再走同一个 (kx,ky)，所以"拖上去、圈画在下面"这种上下翻转不可能出现。
        local dx, dy = twx - joy.bx, twy - joy.by
        local kx, ky, nx, ny = joyVector(dx, dy)
        joy.kx, joy.ky = kx, ky
        joy.dx, joy.dy = nx, ny
      elseif ptr.downX and (math.abs(x - ptr.downX) + math.abs(y - ptr.downY) > 12) then
        ptr.moved = true
      end
    end)
    cursorArea:AddCursorEventListener(M.enumValue('CursorEventType', 'CursorUp') or 'CursorUp', function(e)
      if M.runtime.pointerTouch ~= M.touchId(e) then return true end
      M.runtime.lastPointerTouch = M.runtime.pointerTouch
      M.runtime.pointerTouch = nil
      ptr.down = false
      local x, y = ptrPos(e)
      if x then ptr.x, ptr.y = x, y end
      if joy.active then
        joy.active, joy.consumed = false, true
        joy.dx, joy.dy, joy.kx, joy.ky = 0, 0, 0, 0
        ptr.tapPending = false
        onPointer(e, false, 'CursorUp')
        return
      end
      -- 点按 = 按下后没有明显拖动（此时才交界面处理）
      ptr.tapPending = not ptr.moved
      onPointer(e, ptr.tapPending, 'CursorUp')
    end)
    cursorArea:AddCursorEventListener(M.enumValue('CursorEventType', 'CursorClick') or 'CursorClick', function(e)
      if M.runtime.pointerTouch ~= nil then return true end
      if M.runtime.lastPointerTouch ~= nil and M.runtime.lastPointerTouch ~= M.touchId(e) then return true end
      if ptr.tapPending then
        ptr.tapPending = false
        return                       -- 紧跟 CursorUp 的同一个点按，去重
      end
      if joy.consumed then return end
      if ptr.moved then return end   -- 拖动过的一律不算点按（PC / 触摸同一口径）
      onPointer(e, true, 'CursorClick')
    end)
  end)
  if not ok then print('main: 游标监听注册失败 :: ' .. tostring(err)) end
end

-- 画布坐标 → 世界绝对坐标（640×480，**Y 向下**）。
--
-- ⚠ 这里必须**翻一次 Y**：千星画布的原点在**左下、Y 向上**（与绘制端的 wyBottom() 同一套约定），
-- 而指针事件的 y 用的就是这套坐标 —— 证据（都在源码里，不是推断）：
--   * 插件试玩页 dist/play-renderer.js：
--       function W(w,V){return hv(w,V.getBoundingClientRect(),o.canvasWidth,o.canvasHeight)}
--       function hv(i,t,e,r){return{x:(i.clientX-t.left)*e/t.width, y:(t.bottom-i.clientY)*r/t.height}}
--     DOM 的 clientY 向下增大，`rect.bottom - clientY` 就是**离画布底边的距离** → Y 向上。
--     模拟器仓库同一份代码：studio/play/browser-session.js:27 stagePoint()（同样 (rect.bottom - clientY)）。
--   * 事件数据是原样透传的：dist/index.js ni() → runtime.makeCursorEventData({x:t,y:i})，
--     宿主指针分发 oi() 也只做 Number() 转换。
--   * 引擎自己的命中判定也用同一套 Y 向上盒子（dist/index.js Ne()：
--     `te = parentBottom + anchorMinY*parentH + anchoredPositionY - sizeY*pivotY` 即 bottom 从下往上量），
--     所以页面发上来的 y 直接拿去比 box.bottom/box.top 是一致的。
-- 曾经写成不翻（`(py-OY)/S`）——后果是**所有点按上下镜像**：点在底部的按钮行上，
-- 世界坐标算到屏幕上方，于是「点了没反应」；摇杆也一起反了（往上拖，dy>0 → 灵魂往下走）。
toWorld = function(px, py)
  return (px - OX) / S, H - (py - OY) / S
end

-- 点按处理：同步执行（Web 端试玩 Worker 只在被轮询时推进，不能等下一帧）。
-- 返回 true 表示这次点按已被界面消费。
handleClick = function(px, py)
  if not core or not state then return false end
  local twx, twy = toWorld(px, py)
  local st = state.state
  -- 标题页（难度选择）：点难度卡直接以该档开局；点空白 = 用当前选中的档开局（防"点了没反应"）
  if st == 'title' then
    for i = 1, #titleCards do
      local card = titleCards[i]
      if inRect(twx, twy, card.x - 8, card.y - 8, card.w + 16, card.h + 16) then
        if isTouch and not samePending('title', i - 1) then
          -- 触摸：第一次点只选中该难度（不直接开局，避免误触）
          local cur = core.titleIndex(state) or 0
          if i - 1 ~= cur then pcall(function() core.titleMove(state, (i - 1) - cur) end) end
          markPending('title', i - 1)
          print(string.format('main: 触摸点按难度卡 %d → 选中（再点一次开局）', i))
          return true
        end
        clearPending()
        do  -- 与键盘路径同样的调试钩子：Level.SansRound 指定从哪个内部回合号开局
          local br = bootRound()
          if br then state.bootRound = br end
        end
        pcall(function() core.titleChoose(state, i - 1) end)
        print(string.format('main: 点按难度卡 %d → 开局', i))
        return true
      end
    end
    if isTouch then
      -- 触摸：点空白 = 取消选中，不直接开局
      if pendingSel then
        clearPending()
        print('main: 触摸点按标题页空白 → 取消选中')
        return true
      end
      return false
    end
    pcall(function() core.titleChoose(state, nil) end)
    print('main: 点按标题页空白 → 用当前难度开局')
    return true
  end
  -- 攻击条阶段：点哪里都算「结算」（原作就是按一下确认）。
  -- 只认那 22px 的条会让玩家点空白处永远不结算 —— 表现就是卡死。
  if st == 'attack' then
    clearPending()
    pcall(function() core.stopAttack(state) end)
    print('main: 点按 → 攻击条结算')
    return true
  end
  -- 结局页：点哪里都算「重开」（原作就是按一下确认）。这一支必须放在菜单行之前：
  -- 结局页也画着一行「重 开」菜单，先命中菜单行的话 core.menuChoose 在 result 态是空操作，
  -- 于是"点重开按钮没反应"。
  if st == 'result' then
    clearPending()
    local hit = lastMenu and menuHitTest(lastMenu, twx, twy) or nil
    if hit == 1 then
      pcall(function() core.settle(state) end)
      print('main: 点按 → 结算并退出奇域')
    else
      -- hit==2 或点空白：保持旧的“点结局页重开”手感。
      pcall(function() core.restart(state) end)
      print('main: 点按 → 重开')
    end
    return true
  end
  -- 子面板：面板内的行 = 选项；面板外 = 返回上一级，避免又一处「点了没反应」
  if st == 'sub' and lastSub then
    if not inRect(twx, twy, lastSub.x, lastSub.y, lastSub.w, lastSub.h) then
      clearPending()
      pcall(function() core.subBack(state) end)
      print('main: 点按面板外 → 返回菜单')
      return true
    end
    local hit = subHitTest(lastSub, twx, twy)
    if hit then
      local want = hit - 1                      -- subIndex 是 0 基
      -- 当前选中项取**活状态**：绘制命令里的 index 是上一帧的，点一下改完状态还没重画时它是陈旧的，
      -- 拿它算增量会连跳两项（实测：点「行动」结果开出「仁慈」面板）。
      local cur = (state and state.subIndex) or lastSub.index or 0
      if isTouch and not samePending('sub', want) then
        if want ~= cur then pcall(function() state:subMove(want - cur) end) end
        markPending('sub', want)
        print(string.format('main: 触摸点按子面板第 %d 行 → 选中（再点一次确认）', hit))
        return true
      end
      if want ~= cur then pcall(function() state:subMove(want - cur) end) end
      clearPending()
      pcall(function() core.subConfirm(state) end)
      print(string.format('main: 点按子面板第 %d 行 (%.0f,%.0f)', hit, twx, twy))
      return true
    end
    if isTouch and pendingSel then
      clearPending()
      print('main: 触摸点按面板空白 → 取消选中')
      return true
    end
    return false
  end
  -- 战斗菜单行（攻击/行动/道具/仁慈）：命中按**本帧实际绘制的那一行矩形**（menuHitTest）
  if lastMenu and lastMenu.visible ~= false then
    local items = lastMenu.items or {}
    local hit = menuHitTest(lastMenu, twx, twy)
    if hit then
      local want = hit - 1                        -- menuIndex 是 0 基
      -- 同 drawSub：当前选中项要取**活状态**，命令里的 index 在"点一下还没重画"时是陈旧的
      local cur = (state and state.menuIndex) or lastMenu.index or 0
      if isTouch and not samePending('menu', want) then
        if want ~= cur then pcall(function() state:menuMove(want - cur) end) end
        markPending('menu', want)
        print(string.format('main: 触摸点按菜单第 %d 项（%s）→ 选中（再点一次确认）', hit, tostring(items[hit])))
        return true
      end
      if want ~= cur then pcall(function() state:menuMove(want - cur) end) end
      clearPending()
      pcall(function() core.menuChoose(state, nil) end)
      print(string.format('main: 点按菜单第 %d 项（%s）', hit, tostring(items[hit])))
      return true
    end
    if isTouch and st == 'menu' and pendingSel then
      clearPending()
      print('main: 触摸点按空白 → 取消选中')
      return true
    end
  end
  if lastBar and inRect(twx, twy, lastBar.x, lastBar.y - 10, lastBar.w, lastBar.h + 20) then
    clearPending()
    pcall(function() core.stopAttack(state) end)
    print('main: 点按攻击条 → 结算')
    return true
  end
  if st == 'menu' or st == 'attack' then
    -- 菜单阶段点到空白：不要推进相位（以前这里兜底成确认，导致战斗框在两种位置间乱跳）
    return false
  end
  return false
end

-- 每帧把摇杆向量翻译成方向输入。
-- 只有触摸分支会走到（PC 分支 joy.active 永远是 false，键盘输入直接由 AddKeyEventListener 写 input）。
-- 四向判定统一走 joyDirs（带死区 DEAD，对角 = 两位同时置位，见文件上方常量注释）；
-- 摇杆**只在敌方阶段会 active**（CursorDown 里判 state.state == 'enemy'），
-- 所以菜单/子面板/攻击条/结局阶段既不会起摇杆、也不会吞掉点按。
local function applyPointer()
  if not core or not state then return false end
  local d = isTouch and joy.active and joyDirs(joy.dx, joy.dy) or {}
  for _, direction in ipairs({ 'left', 'right', 'up', 'down' }) do
    local held = false
    for _, v in pairs(M.runtime.heldDirections[direction] or {}) do if v then held = true end end
    input[direction] = held or d[direction] or false
  end
  if ptr.wasJoy and not joy.active then diagSoul = nil end
  ptr.wasJoy = joy.active
  return false
end

-- 摇杆几何（**绘制与判定同源**，回归可直接断言）：底座圆心 = 基准点 (bx,by)，
-- 杆头中心 = 基准点 + (kx,ky) —— kx/ky 就是上面 CursorDrag 里由原始偏移算出的那一份
-- （同一份 dx/dy 归一化后的向量，方向位也由它派生）。两者都走 wx()/wyBottom() 换算到画布坐标
-- （千星画布原点在左下、Y 向上，wyBottom(y) = OY + (H-y)*S 已经翻过一次），
-- 所以往上拖（世界 ky<0）杆头画在圈心**上方**，不会出现"拖上去、圈画在下面"。
local function joystickGeom()
  if not (isTouch and joy.active) then return nil end
  local bx, by, kx, ky = joy.bx, joy.by, joy.kx, joy.ky
  local d = 26
  return {
    bx = bx, by = by, kx = kx, ky = ky, dx = joy.dx, dy = joy.dy, r = JOY_R, dead = DEAD,
    ring = { x = wx(bx - JOY_R), y = wyBottom(by + JOY_R), w = JOY_R * 2 * S, h = JOY_R * 2 * S },
    knob = { x = wx(bx + kx - d / 2), y = wyBottom(by + ky + d / 2), w = d * S, h = d * S },
  }
end

-- 虚拟摇杆：底座（圆环）+ 摇杆头（圆）。只在**触摸分支**真的按住左半屏（且不是点 UI）时显示，
-- PC 上永远没有摇杆圈。几何全部来自 joystickGeom()，绘制与输入判定不会各算一套。
local function drawJoystick()
  local g = joystickGeom()
  if not g then return end
  local alpha = 0.8
  local rc = take('ring')
  if rc then
    put(rc, g.ring.x, g.ring.y, g.ring.w, g.ring.h)
    tint(rc, ((math.floor(255 * alpha)) << 24) | 0xFFFFFF)
  end
  local kc = take('circle')
  if kc then
    put(kc, g.knob.x, g.knob.y, g.knob.w, g.knob.h)
    tint(kc, ((math.floor(255 * math.min(1, alpha + 0.15))) << 24) | 0xFFFFFF)
  end
end

-- ---------------------------------------------------------------- 内置演示（core 缺失时）

local demo = { t = 0, blasterT = 0, hp = 92, kr = 0, soul = { x = 312, y = 376 } }

local function demoCmds(dt)
  demo.t = demo.t + dt
  demo.blasterT = demo.blasterT + dt
  local sp = 108 * dt
  if input.left then demo.soul.x = demo.soul.x - sp end
  if input.right then demo.soul.x = demo.soul.x + sp end
  if input.up then demo.soul.y = demo.soul.y - sp end
  if input.down then demo.soul.y = demo.soul.y + sp end
  local bx, by, bw, bh = 200, 280, 240, 140
  demo.soul.x = math.max(bx + 8, math.min(bx + bw - 24, demo.soul.x))
  demo.soul.y = math.max(by + 8, math.min(by + bh - 24, demo.soul.y))

  local cmds = { { kind = 'box', x = bx, y = by, w = bw, h = bh } }

  -- 四根竖骨：peek(0.5) → extend(0.15) → hold(0.55) → retract(0.2)
  for i = 0, 3 do
    local period = 1.4
    local t = (demo.t + i * 0.35) % period
    local h, alpha = 0, 1
    if t < 0.5 then h, alpha = 26, 0.55
    elseif t < 0.65 then h = 26 + (t - 0.5) / 0.15 * 114
    elseif t < 1.2 then h = 140
    else h = 140 * (1 - (t - 1.2) / 0.2); alpha = 1 - (t - 1.2) / 0.2 end
    if h > 0 then
      cmds[#cmds + 1] = { kind = 'bone', x = bx + 40 + i * 52, y = by + bh - h, w = 19, h = h,
                          vertical = true, color = i % 3, alpha = math.max(0, alpha) }
    end
  end

  -- 龙骨炮：蓄力 1.1s → 开火 0.5s
  local cycle = (demo.blasterT % 2.4)
  local charge = math.min(1, cycle / 1.1)
  local fire = (cycle > 1.4) and math.min(1, (cycle - 1.4) / 0.12) or 0
  cmds[#cmds + 1] = { kind = 'blaster', x = 320, y = 130, dir = 1,
                      charge = charge, fire = fire, length = 150 }

  cmds[#cmds + 1] = { kind = 'soul', x = demo.soul.x, y = demo.soul.y, mode = 'red' }
  cmds[#cmds + 1] = { kind = 'hudText', text = string.format('HP %d/92    KR %d', demo.hp, demo.kr),
                      x = 176, y = 16, size = 20 }
  cmds[#cmds + 1] = { kind = 'hudText', text = '审判者', x = 176, y = 46, size = 16, color = C_DIM }
  cmds[#cmds + 1] = { kind = 'hudText', text = '* 内置演示（core.lua 未就绪）：方向键移动灵魂',
                      x = 176, y = 436, size = 16, color = C_DIM }
  local fl = 0
  if cycle > 1.38 and cycle < 1.46 then fl = 0.35 end
  cmds[#cmds + 1] = { kind = 'flash', alpha = fl, color = C_WHITE }
  return cmds
end

-- ---------------------------------------------------------------- 生命周期

local function tryLoadFit()
  local ok, m = pcall(require, 'default_import_file/workspace/sans-fight/lua/fitdata')
  -- 主路径成功即返回（离线单测会把它 stub 成空表 → 走参数化回退）
  if ok and type(m) == 'table' then return m end
  local ok2, m2 = pcall(require, 'lua' .. '.fitdata')
  if ok2 and type(m2) == 'table' then return m2 end
  print('main: fitdata 未加载（用参数化外观）:: ' .. tostring(m))
  return nil
end

local function tryLoadCore()
  local ok, mod = pcall(require, 'default_import_file/workspace/sans-fight/lua/core')
  if not ok or type(mod) ~= 'table' or type(mod.newGame) ~= 'function' then
    print('main: core 未加载（用内置演示）:: ' .. tostring(mod))
    return nil
  end
  local okA, atk = pcall(require, 'default_import_file/workspace/sans-fight/lua/attacks')
  if not okA or type(atk) ~= 'table' then
    print('main: attacks 未加载 :: ' .. tostring(atk))
    atk = {}
  end
  attacks = atk
  -- 不再读 core 的 BOX_OFF_*：core 的 render 出口已是世界绝对坐标（640×480），
  -- 本层不需要任何平移量（`lua/_geometry.lua` 逐帧对账「绘制 == 判定几何」把这条钉住）。
  return mod
end

-- 战斗 BGM（客户端音效拼旋律）：单独一个模块，缺失时静默降级（不影响战斗）
local function tryLoadMusic()
  local ok, m = pcall(require, 'default_import_file/workspace/sans-fight/lua/music')
  if ok and type(m) == 'table' and type(m.start) == 'function' and type(m.update) == 'function' then return m end
  local ok2, m2 = pcall(require, 'lua' .. '.music')
  if ok2 and type(m2) == 'table' and type(m2.start) == 'function' then return m2 end
  print('main: music 未加载（本局无 BGM）:: ' .. tostring(m))
  return nil
end

local function difficulty()
  local ok, v = pcall(function() return game.GetGlobalCustomVariableValue(M.enumValue('CustomVariableEntityType', 'Level') or 'Level', 'SansDifficulty') end)
  if ok and type(v) == 'string' and v ~= '' then return v end
  return M.config.difficulty or 'original'
end

-- （调试钩子 bootRound() 定义在文件上方「平台分流」段，这里不再重复定义）

function M.OnInit()
  -- 真实千星最可靠：脚本挂载对象本身就是父容器（1073741857）。
  -- 模拟器/旧运行时再按 GUID 或运行期 Id 回退。
  local scriptOk, scriptObj = pcall(function() return script.object end)
  if scriptOk and scriptObj ~= nil then root = scriptObj end
  if root == nil then
    for _, rid in ipairs({ 1073741857, 1073741856, 1 }) do
      local ok, candidate = pcall(function() return game.GetClientUIControl(rid) end)
      if ok and candidate ~= nil then root = candidate; break end
    end
  end
  layout()
  print(string.format('main init: root=%s canvas=%.0fx%.0f scale=%.3f ox=%.1f oy=%.1f',
    tostring(root ~= nil), CW, CH, S, OX, OY))
end

function M.OnUpdate(dt)
  if M.config.updateCallback == 'ui' then return M.OnLevelUpdate(dt, true) end
end

function M.OnStart()
  if M.runtime.started then return end
  if not root then M.OnInit() end
  if not root then error('找不到脚本宿主容器：请把 main.lua 挂在客户端画布的根容器节点上') end
  M.runtime.started, M.runtime.enabled = true, true
  root.disableKeyEventPassthrough = true
  root.disableCursorEventPassthrough = true
  root.showCursor = true
  layout()
  pcall(function() script:EnableUpdate(true) end)
  isTouch = detectDevice()      -- 平台分流：只认 Mobile / MobileController，其余（含读不到）按 PC
  -- 纯黑背景板：**在所有控件之前**创建 → 兄弟序天然在最底层（新实例默认置顶，先建的在下面）。
  -- 模拟器试玩页/截图里的舞台底色是宿主画的渐变，真机底色也不可控 → 背景必须由 Lua 自己糊一层。
  -- 黑底覆盖实际画布，宽屏两侧留黑边。
  bgPanel = spawn('rect')
  if bgPanel then
    put(bgPanel, 0, 0, CW, CH)
    tint(bgPanel, 0xFF000000)
    bgPanel:SetVisible(true)
    st(bgPanel).vis = true
  end
  -- 烘焙容器根：必须在 prewarm 之前创建 → 烘焙层在黑底之上、池控件之下。
  bakedRoot = spawn('bakedRoot')
  if bakedRoot then
    put(bakedRoot, 0, 0, CW, CH)
    bakedRoot:SetVisible(true)
    st(bakedRoot).vis = true
  end
  -- 稳定父层序：Sans 在下，弹幕、灵魂、界面依次在上。
  -- 每类池在独立容器内复用，避免旧矩形被后来创建的激光永久压住。
  M.runtime.layers = {}
  for _, name in ipairs({ 'world', 'soul', 'uiBackdrop', 'ui' }) do
    local layer = spawn('bakedRoot')
    if layer then
      put(layer, 0, 0, CW, CH); layer:SetVisible(true); st(layer).vis = true
      M.runtime.layers[name] = layer
    end
  end
  fit = tryLoadFit()
  prewarm()
  cursorArea = spawn('cursor') -- 不参与图元池显隐，始终接收指针。
  if cursorArea then cursorArea:SetVisible(true) end
  flash = spawn('rect')
  core = tryLoadCore()
  music = tryLoadMusic()
  if core then
    local ok, s = pcall(function()
      return core.newTitle({ difficulty = difficulty(), scripts = attacks, hp = 92,
                             startRound = bootRound(), trainingItems = M.config.trainingItems })
    end)
    if ok and type(s) == 'table' then
      state = s
      mode = 'core'
    else
      print('main: newGame 失败 :: ' .. tostring(s))
    end
  end
  -- 两条分支各自注册输入：PC 只绑键盘（鼠标点 UI），触摸只用指针（摇杆 + 两段式点按）
  if isTouch then
    print('main: 平台 = 触摸分支（左半屏摇杆 + 点按二次确认，保留键盘/手柄监听）')
  else
    print('main: 平台 = PC 分支（键盘移动/确认；指针只点 UI，无摇杆）')
  end
  bindKeys()
  bindPointer()
  -- 显式层序（防「真机同级层叠顺序与模拟器相反」这类差异，见 6nimmt 的 AGENTS.md）：
  -- 背景钉最底、闪层钉最上；池内控件的相对顺序仍由创建顺序决定（后取的压在上面）。
  if bgPanel then pcall(function() bgPanel:SetAsFirstSibling() end) end
  if flash then pcall(function() flash:SetAsLastSibling() end) end
  print(string.format('main start: build=%s device=%s touch=%s mode=%s pool=%d flash=%s cursor=%s',
    BUILD, deviceName, tostring(isTouch), mode, madeTotal, tostring(flash ~= nil), tostring(cursorArea ~= nil)))
end

local function requestSettlement(dt)
  if not (state and state.settleRequested) then return end
  state.settleRetryT = math.max(0, (state.settleRetryT or 0) - dt)
  if state.settleRetryT > 0 then return end
  local cfg = M.config.settlement or {}
  state.settleAttempts = (state.settleAttempts or 0) + 1
  local ok, err = pcall(function()
    local sig = game.ServerSignal(cfg.signal or 'SansFightSettle')
    -- 官方 API 按参数次序传值，不能把字段名当作第一个实参。
    sig:AddString(tostring(state.result or 'fail'))
    sig:AddInt(math.floor(state.hp or 0))
    sig:AddInt(math.floor(state.kr or 0))
    sig:AddInt(math.floor(state.fightCount or 0))
    sig:AddFloat(state.elapsed or 0)
    sig:AddInt(math.floor(state.hits or 0))
    sig:AddString(tostring(state.diffKey or 'original'))
    sig:SendSignal()
  end)
  if ok then
    state.settleRequested, state.settleStatus = false, 'sent'
    if music then music.stop() end
    print('main: 已发送 SansFightSettle，等待服务器结算（本地发送成功不代表服务器已结算）')
  elseif state.settleAttempts >= (cfg.maxAttempts or 3) then
    state.settleRequested, state.settleStatus = false, 'failed'
    print('main: 结算发送失败，可再次选择结算 :: ' .. tostring(err))
  else
    state.settleRetryT = cfg.retryDelay or 1
  end
end

function M.OnLevelUpdate(dt, fromUI)
  if not M.runtime.started or not M.runtime.enabled then return end
  if M.config.updateCallback == 'ui' and not fromUI then return end
  if type(dt) ~= 'number' or dt ~= dt or dt < 0 or dt == math.huge then dt = 0 end
  dt = math.min(dt, 0.25)
  layout()
  if bgPanel then put(bgPanel, 0, 0, CW, CH) end
  if bakedRoot then put(bakedRoot, 0, 0, CW, CH) end
  for _, layer in pairs(M.runtime.layers or {}) do put(layer, 0, 0, CW, CH) end
  if cursorArea then put(cursorArea, 0, 0, CW, CH) end
  frame = frame + 1
  local cmds
  if mode == 'core' and state then
    -- 相位一变，触摸端的「待确认选中」就作废（否则跨状态会把不相干的项当成已选中过）
    if state.state ~= pendingPhase then
      pendingPhase = state.state
      clearPending()
    end
    local c, x = consumeEdges()
    if applyPointer() then c = false end     -- 点击已被界面消费时不再另外发确认
    input.confirm, input.cancel = c, (M.runtime.cancelHeld or x)
    -- 标题页：core.update 在 title 态不处理输入，这里自己处理（左右选难度 + 确认开局），边沿触发防连滚
    if state.state == 'title' then
      local l, r = input.left, input.right
      if l and not titlePrevL then pcall(core.titleMove, state, -1) end
      if r and not titlePrevR then pcall(core.titleMove, state, 1) end
      titlePrevL, titlePrevR = l, r
      if c then
        -- 调试钩子在这里**再读一次** Level.SansRound：这样在标题页设变量 → 按确认就能生效，
        -- 不必在 OnStart 之前就设好（模拟器里"设变量再按开始"是最顺手的验证姿势）。
        local br = bootRound()
        if br then state.bootRound = br end
        pcall(core.titleChoose, state, nil)
      end
    end
    -- 攻击条防卡死：6 秒仍未结算就自动结算（玩家可能一直没点，或点在了空白处）
    -- 只在**还没结算**时触发：否则大 dt（试玩 step 或掉帧）下会每帧重复结算 + 刷屏。
    if state.state == 'attack' and state.attackResult == nil then
      attackT = attackT + dt
      if attackT > 6 then
        attackT = 0
        pcall(function() core.stopAttack(state) end)
        print('main: 攻击条超时 → 自动结算（防卡死）')
      end
    else
      attackT = 0
    end
    -- 跳跃按下沿统一由核心消费；按住状态独立传入用于变高跳。
    local coreInput = { left = input.left, right = input.right, up = input.up, down = input.down,
      confirm = input.confirm, cancel = input.cancel, jumpHeld = confirmHeld }
    local ok, out = pcall(function() return core.update(state, coreInput, dt) end)
    requestSettlement(dt)
    -- 战斗 BGM：core 在 Game:start()（开局 / 重开）里把 runSeq +1 → 这里从头播。
    -- 整场循环由 music 模块内部完成；结算在 requestSettlement() 里停。
    if state.runSeq ~= lastRunSeq then
      lastRunSeq = state.runSeq
      if music then music.start() end
    end
    if music then
      if state.state == 'result' or state.interlude then music.stop()
      elseif state.state ~= 'title' then
        if not music.playing then music.start() end
        music.update(dt)
      end
      for _, event in ipairs(state.audioEvents or {}) do music.effect(event) end
    end
    state.audioEvents = {}
    if state.world then state.world.audioEvents = state.audioEvents end
    if not ok and not M.updateErrorLogged then
      M.updateErrorLogged = true
      print('main: core.update ERR :: ' .. tostring(out))
    end
    if ok and type(out) == 'table' and out[1] and out[1].kind then
      cmds = out
    else
      local ok2, out2 = pcall(function() return core.render(state) end)
      if ok2 and type(out2) == 'table' then cmds = out2 end
      if not cmds then
        if frame % 60 == 0 then print('main: core.render 无输出 :: ' .. tostring(out)) end
        cmds = {}
      end
    end
    -- HUD 由 core.render 自己输出（LV/HP/KR/ROUND/台词），这里只把 hud() 用于日志
  else
    consumeEdges()
    cmds = demoCmds(dt)
  end
  local okR, err = pcall(draw, cmds)
  if not okR then
    print('main: draw ERR :: ' .. tostring(err))
    return
  end
  pcall(drawJoystick)          -- 摇杆画在最上层（仅触摸分支会真的画）
  -- 移动诊断：任一方向输入生效且灵魂位置变化就记一条（限速 0.6s），键盘与摇杆都覆盖
  local moving = input.left or input.right or input.up or input.down
  if moving and absSoul then
    local moved = (not diagSoul) or (math.abs(absSoul.x - diagSoul.x) + math.abs(absSoul.y - diagSoul.y) > 6)
    if moved and diagAcc >= 0.6 then
      diagAcc = 0
      print(string.format('main: 移动 %s%s%s%s joy=(%.2f,%.2f) soul=(%.0f,%.0f)',
        input.left and 'L' or '', input.right and 'R' or '', input.up and 'U' or '', input.down and 'D' or '',
        joy.dx, joy.dy, absSoul.x, absSoul.y))
      diagSoul = { x = absSoul.x, y = absSoul.y }
    end
  end
  logAcc = logAcc + dt
  diagAcc = diagAcc + dt
  -- 阶段变化记录：无界面时也能从日志看出回合流程（菜单 → 攻击条 → 敌方回合 → …）
  if mode == 'core' and state then
    local ph = tostring(state.state) .. (state.sub and (':' .. tostring(state.sub)) or '')
    if ph ~= lastPhase then
      print('main: 阶段 ' .. tostring(lastPhase) .. ' → ' .. ph
        .. string.format(' (round=%s hp=%s)', tostring(state.round), tostring(state.hp)))
      lastPhase = ph
    end
  end
  if logAcc >= 5 then
    logAcc = 0
    local hp, phase = '?', '?'
    if core and state then
      local okH, h = pcall(core.hud, state)
      if okH and type(h) == 'table' then hp, phase = tostring(h.hp), tostring(h.phase) end
    end
    print(string.format('main: mode=%s device=%s touch=%s frame=%d pool=%d cmds=%d box=(%.0f,%.0f,%.0f,%.0f) hp=%s phase=%s soul=%s joy=%s',
      mode, deviceName, tostring(isTouch), frame, madeTotal, #cmds, curBox.x, curBox.y, curBox.w, curBox.h, hp, phase,
      absSoul and string.format('%.0f,%.0f', absSoul.x, absSoul.y) or 'nil',
      joy.active and string.format('on(%.2f,%.2f)', joy.dx, joy.dy) or 'off'))
  end
end

function M.clearInput()
  input = { left = false, right = false, up = false, down = false, confirm = false, cancel = false }
  for k in pairs(M.runtime.heldConfirm) do M.runtime.heldConfirm[k] = nil end
  for k in pairs(M.runtime.heldCancel) do M.runtime.heldCancel[k] = nil end
  M.runtime.heldDirections = {}
  for _, d in ipairs({ 'left', 'right', 'up', 'down' }) do M.runtime.heldDirections[d] = {} end
  edgeConfirm, edgeCancel, confirmHeld, M.runtime.cancelHeld = false, false, false, false
  joy.active, ptr.down, ptr.wasJoy = false, false, false
  M.runtime.pointerTouch, M.runtime.lastPointerTouch = nil, nil
  clearPending()
  if state then state.keys, state.prevKeys = {}, {} end
end

function M.OnDisable()
  M.runtime.enabled = false
  M.clearInput()
  if music then music.stop(); music.stopEffects() end
end

function M.OnEnable()
  M.runtime.enabled = true
  if M.runtime.started then M.clearInput() end
end

function M.OnDestroy()
  M.OnDisable()
  if root then
    for _, listener in ipairs(M.runtime.keyListeners) do
      pcall(function() root:RemoveKeyEventListener(listener[1], listener[2]) end)
    end
  end
  if cursorArea then pcall(function() cursorArea:RemoveAllCursorEventListeners() end) end
  for i = #M.runtime.ownedControls, 1, -1 do
    local c = M.runtime.ownedControls[i]
    pcall(function() if c.alive ~= false then game.DestroyClientUIControl(c) end end)
  end
  M.runtime.ownedControls, M.runtime.keyListeners, pool, memo, baked = {}, {}, {}, {}, {}
  M.runtime.layers = nil
  state, M.runtime.started = nil, false
end

-- 测试钩子：无头测试台（lua/_adapter.lua）与集成用例用它读逻辑层状态
function M.state() return state end
function M.mode() return mode end
function M.pointer() return ptr, joy end
function M.drawJoystick() return drawJoystick() end   -- 供截图前的静态检查
function M.box() return curBox, boxTarget end          -- 画出来的框 / 逻辑层目标框
function M.toWorld(px, py) return toWorld(px, py) end   -- 画布 → 世界（回归用）
function M.click(px, py) return handleClick(px, py) end -- 直接打点按链路（回归用）
function M.soul() return absSoul end                   -- 画出来的灵魂绝对坐标
function M.boxDelta() return { x = 0, y = 0 } end        -- 保留接口（core 单帧后修正量恒为 0）
function M.menuItemSelected(cmd, i) return menuItemSelected(cmd, i) end   -- 菜单选中判定（回归用）
function M.flashDrawable(stateName, n) return flashDrawable(stateName, n) end   -- 结局闪层门控（回归用）
M.boxOverflow = boxOverflow
-- 平台分流 / 命中几何 / 标题页去框（都是回归用的只读钩子）
function M.device() return isTouch, deviceName end          -- 当前分支（true=触摸）与读到的设备名
function M.isTouch() return isTouch end
function M.lastRects() return lastMenu, lastSub, lastBar end -- 本帧实际绘制的可点 UI 命令
function M.menuRowRect(cmd, i) return menuButtonRect(cmd, i) end              -- 按钮行第 i 项的按钮矩形
-- 按钮行定位常量与纯函数（回归断言「行与世界中心/框矩形的相对偏移 == 写死的常量」用）
function M.layoutConstants()
  return { centerX = CENTER_X, centerY = CENTER_Y,
           rowDyTop = MENU_ROW_DY_TOP, rowDyCenter = MENU_ROW_DY_CENTER,
           gap = MENU_ROW_GAP, bottomMargin = MENU_ROW_BOTTOM_MARGIN }
end
function M.menuRowYFor(bh, boxBottom) return rowYFor(bh, boxBottom) end
function M.menuHeartRect(cmd, i) return menuHeartRect(cmd, i) end
function M.menuHitTest(cmd, wx, wy) return menuHitTest(cmd, wx, wy) end       -- 菜单行命中（1 基 / nil）
function M.subRowRect(cmd, i) return subRowRect(cmd, i) end
function M.subHitTest(cmd, wx, wy) return subHitTest(cmd, wx, wy) end
function M.drawnBoxVisible() return drawnBox end            -- 上一帧是否画了战斗框（标题页应为 false）
function M.drawnKinds() return drawnKinds end               -- 上一帧真正画出去的命令种类
function M.pending() return pendingSel end                  -- 触摸端待确认选中（PC 恒为 nil）

-- ---- 四向输入回归钩子（本轮新增；上面所有旧钩子一律保留）------------------
-- 交给 core 的方向位（键盘 / 摇杆都写进这一份）：PC 与触摸两条路径的方向断言都用它
function M.dirs() return { left = input.left, right = input.right, up = input.up, down = input.down } end
-- 摇杆四向判定（纯函数）：直接喂归一化 (dx,dy) 验死区/对角规则，不必真拖
function M.joyDirs(dx, dy) return joyDirs(dx, dy) end
function M.deadzone() return DEAD end                       -- 归一化死区常量（0.22，出处见其注释）
-- 键盘四向绑定表（方向 → 按下/抬起事件名），回归据此核对 8 个事件名与配对
function M.keyBindings()
  local out = {}
  for i, k in ipairs(KEY_DIRS) do out[i] = { dir = k.dir, down = k.down, up = k.up } end
  return out
end
-- 摇杆实际画出去的几何（画布坐标，底座圆 + 杆头圆）；未起摇杆时返回 nil（PC 恒为 nil）
function M.joystickGeom() return joystickGeom() end
-- 摇杆原始偏移 → 杆头/归一化向量（与 CursorDrag 同一函数，回归可核对同源）
function M.joyVector(dx, dy) local kx, ky, nx, ny = joyVector(dx, dy); return { kx = kx, ky = ky, dx = nx, dy = ny } end

return M


end)()

local M = __modules['default_import_file/workspace/sans-fight/lua/main']
local function call(name, ...)
  if M and M[name] then return M[name](...) end
end
function OnInit() return call('OnInit') end
function OnEnable() return call('OnEnable') end
function OnStart() return call('OnStart') end
function OnUpdate(dt) return call('OnUpdate', dt) end
function OnLevelUpdate(dt) return call('OnLevelUpdate', dt) end
function OnDisable() return call('OnDisable') end
function OnDestroy() return call('OnDestroy') end
