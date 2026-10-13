-- 自动生成（tools/build-save.mjs）—— 请勿手改；改逻辑请改 lua/*.lua 后重建存档。
-- 千星客户端 Lua 沙箱没有 require：这里自带模块垫片，把 core/attacks/fitdata/music/main 内联成一个自足脚本。
local __modules = {}
local function require(p) return __modules[p] end

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
local GRAVITY_UP_FAST = 180       -- 分段重力：高速上冲
local GRAVITY_UP_SLOW = 450       -- 分段重力：中速上升
local GRAVITY_APEX    = 180       -- 分段重力：顶点附近
local GRAVITY_FALL    = 540       -- 分段重力：下落              -- 框内钳位半径 = 心形视觉半宽（±8）：保证心本身不画出框外
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
-- 【方案 A1·2026-10-09】按钮 x 用**原版非等距**布局（Layouts/BattleScreen.xml L400-503：
--   UIFight 32 / UIAct 184 / UIItem 344 / UIMercy 496，间距 152/160/152，整行 32..606）。
--   gap 保留只为兼容旧引用（xs 存在时不再参与排布）。
-- 【2026-10-09 用户口径】四个选项 **以屏幕中心为对称**：左右边距严格相等、彼此等距。
--   总宽 = 4×110 + 3×gap = 574（沿用原版整行宽度）→ 左边距 = (VW(640) - 574)/2 = 33，右边距同样 33；
--   相邻间距 = (574 - 110)/3 = 154.667 ⇒ x = 33 / 187.667 / 342.333 / 497
local MENU = { bw = 110, bh = 42, gap = 154.66666666667 - 110, y = 400,
               xs = { 33, 187.66666666667, 342.33333333333, 497 } }   -- 真值来自 Animations/UIFight|Act|Item|Mercy = 110×42
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
  -- 【2026-10-13 用户口径】"研究原版仓库内 sans 的发言，全面替换" ——
  --   原版 BTS（D:\c2-sans-fight-src\Event sheets\Battle.xml）里，Sans 在战斗中**只有两句**：
  --     L1416（SansTired 之后，函数 Win1）："huff... puff..."
  --     L1483（紧接着，函数 Win2）       ："alright, i guess you win."
  --   其余所有时机（第 1~5 回合、中场、螺旋档…）**原版一个字都没有**（Sans 全程沉默）。
  --   因此这里照原版办理：对不上的键一律空串，渲染层遇到空串就不画（见 renderWorld 的台词守卫）。
  tired = '呼……呼……',                  -- 原版 "huff... puff..."
  win   = '好吧。算你赢了。',            -- 原版 "alright, i guess you win."
  -- 以下时机原版没有台词（全面替换口径下 = 不说话）
  surprise = '', r1 = '', r2 = '', r3 = '', r4 = '', r5 = '', r6 = '',
  mid = '', late = '', spiral1 = '', spiral2 = '', spiral3 = '', final = '',
  midpoint = '', dodge = '', refuse = '', flee = '',
  -- 旧口径（每回合都说话的版本）原样收在同一张表里：把 extra 改成 true 即可回退
  extra = false,
  extraText = {
    surprise = '（他没有打招呼，先动手了。）',
    r1 = '站住别动，让我看看你躲得怎么样。',
    r2 = '骨头是会走路的东西，别被它撞上。',
    r3 = '蓝色的骨头：别动。你动一下，它就咬你。',
    r4 = '抬头看看，朋友。',
    r5 = '你还没死？那我再认真一点。',
    r6 = '……你已经撑过六回合了。',
    mid = '撑过一半了？那我换个打法。',
    late = '你还在动。越来越有意思了。',
    spiral1 = '站好，抬头看。',
    spiral2 = '别眨眼。',
    spiral3 = '——好吧。轮到你了。',
    dodge = '（他侧身闪开了）',
    refuse = '（他摇了摇头）',
    flee = '（他摇了摇头）你逃不掉的。',
    final = '好吧。轮到你了。',
    midpoint = '……中场。他停手了。',
  },
}
if LINES.extra then for k, v in pairs(LINES.extraText) do LINES[k] = v end end

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
CMD.HeartMode = function(w, m) w.heart.mode = tonumber(m); w.heartModeDirty = true end
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
  local persistent = (bt ~= nil and bt <= 0)       -- BlastTime=0 → 持续光束（sans_final 阶段④）
  local sz = clamp(math.floor(tonumber(size) or 0), 0, 2)
  -- 停靠点钳进安全区：不落在选项栏那一条（也不会出屏）。起点 sx,sy 不钳 —— 原版就是从屏幕角飞入的。
  local ex2 = clamp(tonumber(ex) or 0, BLASTER_SAFE.xmin, BLASTER_SAFE.xmax)
  local ey2 = clamp(tonumber(ey) or 0, BLASTER_SAFE.ymin, BLASTER_SAFE.ymax)
  -- 【2026-10-07 用户口径·终盘旋转龙骨炮】持续光束（BlastTime <= 0）**不做终点钳制**：
  --   阶段④每发都是「起点 = 轴心(320,306) + 450u、终点 = 轴心 + 150u」的共线三点；
  --   一旦终点被 clamp，a0 = atan2(ey-sy, ex-sx) 就偏离这条射线 → 光束不再过轴心 →「轴心跳动」。
  --   实测（lua/_probe_spiral_pivot.lua）：钳制会让 122 发中的 37 发终点离线，最大 84px。
  --   普通龙骨炮（有 BlastTime）的钳制保持不变（停靠点仍不会压到选项栏）。
  if persistent then ex2, ey2 = tonumber(ex) or ex2, tonumber(ey) or ey2 end
  local g = {
    size = sz, x = tonumber(sx), y = tonumber(sy),
    sx = tonumber(sx), sy = tonumber(sy), ex = ex2, ey = ey2,
    ang = a0, ang0 = a0, endAng = tonumber(endAng), spin = tonumber(spin),
    blast = bt, persistent = persistent,
    -- 【2026-10-06】hold 不传时保持 nil —— 写成 `or 0` 会让 HoldTime 的默认值（0.05s）失效，
    -- 于是「落定后延时 1.5s」这类参数一旦漏传就变成同帧开火。
    hold = tonumber(hold), t = 0,
    -- 【方案A】全流程龙骨炮统一走原版像素烘焙；LOD 由 render 决策：
    --   sans_intro 的四发组合（Size=1）与持续旋转光束走 3×3，其余仍走 2×2。
    bake = true,
    karma = 10,      -- 龙骨炮首次命中 +10，同一对象后续 +2
    lod = (((w.scriptName == 'sans_intro') and sz == 1) or persistent) and 'block3' or nil,
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
    if b.t >= b.warn then b.phase = 'out'; b.t = 0 end
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
  -- 【2026-10-07 用户口径】保留用户设定的「传奇面包（+45 HP ×20）」，并补上
  --   原版 Items.xml 注册的 4 件（回复量照抄原版：99 / 90 / 60 / 40，Type=0 食物）。
  --   short 字段 = 原版 ItemName2（菜单短名），本端口目前菜单显示全名，保留备用。
  self.items = {
    { id = 'legend_bread', name = '传奇面包', short = '传奇面包', desc = '回复 45 HP', heal = 45, count = 20 },
    { id = 'pie',          name = '奶油糖派', short = 'Pie',       desc = '回复 99 HP', heal = 99, count = 1 },
    { id = 'noodles',      name = '速食泡面', short = 'I.Noodles', desc = '回复 90 HP', heal = 90, count = 1 },
    { id = 'steak',        name = '脸排',     short = 'Steak',     desc = '回复 60 HP', heal = 60, count = 1 },
    { id = 'lhero',        name = '传说英雄', short = 'L. Hero',   desc = '回复 40 HP', heal = 40, count = 1 },
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
  self.resultIndex = 1
  self.settleRequested = false
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

-- 【2026-10-11 用户口径·重开二次确认（PC 也要）】第一次调用只"上膛"并提示，再确认一次才真的重开。
function Game:requestRestart()
  if self.restartArmed then
    self.restartArmed = false
    self:restart()
    return
  end
  self.restartArmed = true
  self:say('再按一次确认重开　（结算 = 结束本局）')
  self:log('restart_armed')
end

-- 【2026-10-09 用户口径】「重选难度」：回到标题页重新选难度（本局进度丢弃）。
--   复用标题页流程：state='title' → 玩家左右选卡 → 确认 = M.titleChoose(g) → g:start()。
function Game:retitle()
  self:log('retitle')
  self:resetRun()
  self.result = nil
  self.resultIndex = 1
  self.settleRequested = false
  self.state = 'title'
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
  -- （colorFlip 已随'内置橙骨剔除'一并移除）
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
    -- 【2026-10-06】留 2.5s 余量：simulateLength 对「循环里带变量」的行会低估，
    --   余量不足时脚本会被 enemyDur 在播完前掐掉（用户报的「一轮没打完就结束」）。
    if need and (need + 2.5) > self.enemyDur then self.enemyDur = need + 2.5 end
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
  -- 【2026-10-10 用户口径】我方行动期（菜单 / 子面板 / 攻击条）战斗框**固定尺寸 575×140**：
  --   原来只改宽度、**高度沿用上一段攻击的框** → 每回合框高都不同（140 / 165 / …），看着"大小不固定"。
  --   注意 y（框顶）仍沿用本回合的顶：Sans 的位置是由框顶推导的，固定顶才能保证他不会在阶段间跳动。
  self.box = { x = MENU_BOX_L - BOX_OFF_X, y = (BOX_CY - 70) - BOX_OFF_Y,
               w = MENU_BOX_R - MENU_BOX_L, h = 140 }
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

function Game:settle()
  -- 客户端只负责请求结算；真正「退出奇域 / 胜利结算」由服务端节点图处理。
  if self.result == 'victory' then return end
  self.result = 'victory'
  self.resultIndex = 0
  self.settleRequested = true
  self:log('settle victory hp=' .. self.hp)
end

function Game:finish(outcome, reason)
  -- 【2026-10-13 用户口径】原版结局台词（Battle.xml L1483 "alright, i guess you win."）：
  --   只在**饶恕/击倒**（即"赢了"）时说；fail（玩家阵亡）不说。
  if (outcome == 'spare' or outcome == 'kill') and LINES.win ~= '' then self:say(LINES.win) end
  self.result = outcome
  self.resultIndex = 1
  self.settleRequested = false
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
  self:endSlam()      -- 起跳即脱离甩击，并把重力方向还原（含 world 侧）
  if self.soul.jumping then return end      -- 空中不再触发：按住不放也不会反复起跳（边沿语义兜底）
  -- 【平台起跳】平台只有 7px 厚、且边移动边判定，起跳那一帧 grounded 可能刚好闪断。
  -- 加 0.12s 的 coyote time：离地 0.12s 内仍然算「站在地上」。
  local coyote = (self.soul.groundT or 99) <= 0.12
  -- 能不能跳 = 原版 HeartCheckSolid(cos(Angle), sin(Angle)) == 1 —— 框边与平台同一个模子，
  -- 不再读 self.soul.grounded（那个标记会被落地顺序影响，正是「空中板子跳不起来」的根因）。
  local surface, gx, gy, soulA = self:groundQuery()
  local onSolid = (soulA + SOUL_CLAMP) >= (surface - 2)
  if onSolid or coyote then
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
    -- 【2026-10-07 用户口径】行动行不再显示「结束回合 / 不结束回合」备注（位置不够，改由说明行省去）
    return ''
  end
  if self.sub == 'mercy' then return (idx == 0) and '撑过 6 回合后才有效' or '他不让你走' end
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
    -- 参考 Battle.xml MenuUseItem：只回复 HP；KR / KR_T 不变。
    -- 蓝血只能按自己的燃烧曲线自然结束，不能被治疗解除。
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
  -- 【2026-10-10 修复】已经结算过就不再结算：
  --   攻击条按下后状态仍是 'attack'（还有 attackHold ≈1s 才进敌方回合），
  --   这期间连按空格会反复调用本函数 → 反复重设 sansDodge（闪避动画重放）+ 重放台词。
  --   加这道幂等保护后，一次攻击只结算一次。
  if self.attackResult ~= nil then return end
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
  self.krFloorLogged = false
  -- 参考：首次命中按对象的 Karma 加；同一攻击对象后续只加 2。
  local gain = tonumber(karma) or (src and tonumber(src.karma)) or KR_PER_HIT
  if src and src.karma == nil then src.karma = gain end
  self.kr = self.kr + gain
  self:clampKR()
  self.krActive = self.kr > 0
  if src and src.karma and src.karma >= 3 then src.karma = 2 end
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
    -- 【蓝心跳跃（用户口径 2026-10-05 第六轮）】
    --   * 按住 → **匀速**上升，速度 = 0.6×框高 / 0.25s（**0.25s 到 3/5 框高**）；
    --   * **上升窗口只有 0.25s**：按住超过 0.25s 也停，然后**自然下落**（不再悬停/浮空）；
    --   * 松开 → **立刻停止上升**，等速下降（速度 = 0.5×框高 / 0.75s）；
    --   * 松手后这一次跳跃被「剪断」（jumpCut）→ **下降途中再按跳跃键不会重新上升**（不能二段跳）；
    --   * 另有「起跳点上方 3/5 框高」和战斗框上沿两道兜底。
    -- 【2026-10-06 · 完全依据 D:\\stars\\reference\\lua\\blue_soul.lua（= 原作 PlayerMovement）重写】
    --   ① 重力**分段**：按「施加本帧重力之前」的沿重力速度 DownSpeed 选档（px/s²）
    --        DownSpeed <= -120            → 180   （高速上冲，保持冲劲）
    --        -120 < DownSpeed <= -30      → 450   （中速上升，迅速刹车）
    --        -30  < DownSpeed <=  15      → 180   （顶点附近，滞空）
    --        其它（> 15）                  → 540   （下落，重）
    --   ② 松键截断（HEART_JUMPHOLD_CUTOFF = 30）：松手瞬间若仍上冲且速度 > 30，
    --      把沿重力分量**直接钳到 -30** —— 轻点=小跳、按住=满跳，**不再用按住计时**。
    --   ③ 横向：先清零「垂直」分量，再按轴直接赋值 ±150（按住 Cancel = 75）。
    --      竖直重力用左右键；水平重力用上下键（与原版一致）。
    --   ④ 前方 0.2px 有固体就不加重力，避免把灵魂压进地面/平台。
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
    if dsp <= -120 then grav = GRAVITY_UP_FAST
    elseif dsp <= -30 then grav = GRAVITY_UP_SLOW
    elseif dsp <= 15 then grav = GRAVITY_APEX end
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
      -- 【2026-10-09 用户口径·剔除现有橙骨】原版 `sans_bluebone` 只有蓝骨（Files/sans_bluebone.csv：6 行 Color=1），
      --   本端口内置兜底生成器原来是"蓝/橙交替"（自创）→ 现在**只出蓝骨**，橙骨一律由脚本显式下发。
      self:spawnBlue(self.rng() < 0.5, 'blue')
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

  -- 【2026-10-13 用户口径】原版在 SansTired 之后说 "huff... puff..."（Battle.xml Win1）
  do
    local sw = self.world
    if sw and sw.sans and sw.sans.anim == 'Tired' and not self.tiredSaid then
      self.tiredSaid = true
      self:say(LINES.tired)
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
  -- 蓝心跳跃用：适配层在蓝魂态把 up/down 掩成 false，只保留按下沿；按住状态走这个字段。
  -- 【R3/J5】确认键（Enter/Z/J）同样是「跳跃键」：它触发起跳（下面 e.confirm），
  -- 但如果这里不认它，同一帧的蓝魂物理会立刻把刚起跳的 vy 覆盖成 fallSpeed，
  -- 灵魂原地落回板子 —— 探针里 confirm=true 的「第 1 跳 vy=0」就是这个原因。
  self.jumpHeld = (input.jumpHeld or input.confirm) and true or false
  if self.state == 'result' then
    -- 结算在左、重开在右；默认仍选重开，保留原确认键重开手感。
    -- 三项：0=结算 1=重开 2=重选难度（左右循环，默认停在「重开」）
    if e.left then self.resultIndex = ((self.resultIndex or 1) - 1) % 3 end
    if e.right then self.resultIndex = ((self.resultIndex or 1) + 1) % 3 end
    -- 【2026-10-11 用户口径】结局页「重开」要二次确认（键盘与鼠标同口径）；换项即撤销
    if e.left or e.right then self.restartArmed = false end
    if e.confirm then
      local ri = self.resultIndex or 1
      if ri == 0 then self:settle()
      elseif ri == 1 then self:requestRestart()
      else self:retitle() end
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
    if e.confirm and self.soul.mode == 'blue' then self:jump() end
  end
end

-- ==========================================================================
-- 渲染（纯函数，不改状态）
-- ==========================================================================
local function menuLayout()
  if MENU.xs ~= nil then                      -- 方案 A1：原版显式 x 表（非等距）
    local xs = MENU.xs
    return xs[1], (xs[#xs] + MENU.bw) - xs[1]
  end
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
                 bake = g2.bake and true or nil, lod = g2.lod or (g2.persistent and 'block3' or nil),
                 w = g2.band or BLASTER_W[(g2.size or 0) + 1] or BLASTER_W[1], scale = g2.scale or 1,
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
    -- 【2026-10-10 修复】PC 端提示原来画在 y=300，而标题页那行提示在 y=296（字号 16）→ **两者重叠**。
    --   这里下移到 y=336（标题提示 296、难度注释 262，之间留出空档），并缩短文案。
    push(cmds, { kind = 'hudText', text = 'PC：空格 确认开局（鼠标不可选定）', x = VW / 2, y = 336, size = 13,
                 color = '#c9b26a', align = 'center' })
    return cmds
  end
  if g.state == 'result' then
    push(cmds, { kind = 'flash', alpha = 1 })
    local t = (g.result == 'victory') and '胜 利 结 算'
              or ((g.result == 'fail') and 'GAME OVER'
              or ((g.result == 'spare') and '饶 恕 结 局' or '击 倒 结 局'))
    push(cmds, { kind = 'hudText', text = t, x = VW / 2, y = 145, size = 36,
                 color = (g.result == 'fail') and '#ff2d2d' or '#ffcc33', align = 'center' })
    -- 结算 / 重开 / 重选难度（三项居中排开：130×3 + 20×2 = 430 ⇒ x 从 105 起）
    local ri = g.resultIndex or 1
    local hint = (ri == 0) and '确认键：结算并退出奇域'
                 or ((ri == 1) and '确认键：同难度重新开始' or '确认键：回到标题页重选难度')
    push(cmds, { kind = 'menu', x = VW / 2 - 215, y = 220, w = 130, gap = 20, h = 36,
                 items = { '结 算', '重 开', '重选难度' }, index = ri, visible = true })
    push(cmds, { kind = 'hudText', text = hint,
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
  push(cmds, { kind = 'hudText', text = 'LV 19', x = 20, y = hudY, size = 13, color = '#ffffff', align = 'left' })
  push(cmds, { kind = 'hudText', text = 'HP ' .. g.hp .. '/' .. g.maxHP, x = 76, y = hudY, size = 13, color = '#ffffff', align = 'left' })
  push(cmds, { kind = 'hudBar', x = 168, y = hudY + 1, w = 96, h = 11, hp = g.hp, kr = g.kr, max = g.maxHP })
  push(cmds, { kind = 'hudText', text = 'KR ' .. math.floor(g.kr + 0.5), x = 272, y = hudY, size = 12, color = '#c9a3ff', align = 'left' })
  push(cmds, { kind = 'hudText', text = 'ROUND ' .. (g.round + 1) .. ' / ' .. TOTAL_ROUNDS, x = VW - 150, y = hudY, size = 13, color = '#ffffff', align = 'right' })
  push(cmds, { kind = 'hudText', text = '难度 ' .. (g.tune and g.tune.label or '普通'), x = VW - 20, y = hudY + 1, size = 11, color = '#8a8a8a', align = 'right' })
  -- 【2026-10-13 用户口径】台词改画在 **Sans 头顶上方**（原版是头顶的 SpeechBubble），
  --   并且**空台词不画**（全面替换口径下多数时机不说话）。算式与 sans 命令的 y 同源。
  if g.line and g.line ~= '' then
    local lineY = (boxAbs.y - 16 - SANS_H) - 30
    if lineY < 2 then lineY = 2 end
    push(cmds, { kind = 'hudText', text = utf8sub(g.line, g.lineShown), x = VW / 2, y = lineY, size = 14,
                 color = '#ffffff', align = 'center' })
  end
  if g.flash > 0 then
    push(cmds, { kind = 'flash', alpha = 0.35 * g.flash / 0.12 })
  end
  -- 菜单
  if g.state == 'menu' or g.state == 'attack' or g.state == 'sub' then
    push(cmds, { kind = 'menu', x = MENU_X0, y = MENU.y, w = MENU.bw, h = MENU.bh,
                 xs = MENU.xs,          -- 【修复】必须带出去：main 的 menuButtonRect 靠它做"以屏幕中心对称 + 等距"
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
    g:applyInput(input)
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
function M.requestRestart(g) g:requestRestart() end
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
--[[ ==========================================================================
  attacks.lua —— 攻击脚本数据（**自动生成，请勿手改**）
  ---------------------------------------------------------------------------
  生成器：tools/gen-attacks.mjs
  来源：  prototype/attacks/*.csv（27 个）
  生成日期：2026-10-13

  每项 = { name = "sans_xxx", csv = <该 CSV 的全文> }
  core.lua 通过 M.newGame({ scripts = require("attacks") }) 注入使用；
  也接受任意同构的表（便于测试注入自制脚本）。
  长括号层级：[==[ ... ]==]
  ========================================================================== ]]

local M = {
  { name = "final", csv = [==[
# final —— 最终回合（四阶段 + 撑过后的睡意演出），原作最长的一段
#   阶段① 行 1-27   4 次随机方向「抬手 → 砸 + 骨刺(距离29/预警0.4/停留0)」，
#                   收尾两组 BoneHRepeat(130,-10,200,南,300,3,183) 与 (330,650,200,北,300,3,183)
#   阶段② 行 28-98  框体横向扩张；HeartMaxFallSpeed -300 造出「反向重力走廊」；
#                   SansRepeat 左右滑屏；44 根正弦起伏高速骨（行 49-64 小循环）+ 10 组骨墙 +
#                   24 根上下开合骨（行 85-92 小循环）
#   阶段③ 行 99-137 4 组「黑屏闪 + 双方向骨刺(48/预警0.6/停留1) + HeartTeleport + SansSlam」
#   阶段④ 行 138-156 旋转光束：Ang = -10·gt，gin 从 1 每次 +0.015 递增到 1.7，
#                   gt 累加到 190 才停（约 122 发、每发 0.06666s，BlastTime = 0 即瞬发）
#   阶段⑤ 行 157-213 撑过光束后的 38 次连续砸击：SansSlamDamage 1（这次真的会掉血），
#                   Wait 由 0.2 递减；I=25 开始冒汗、I=33 出现 Tired1、I=35 强制朝北、
#                   I=36 起 Tired2（此时 MaxFallSpeed 只剩 60）→ 最后 SansAnimation Tired
# 数据来源：BTS（jcw87/c2-sans-fight, GPL-3.0）Files/sans_final.csv 逐行转写。
# 跳转沿用原作 1-based 行号（只数非注释行，故以上注释不改变任何行号）：
#   7 / 49 / 85 / 140 / 156 / 166 / 168 / 170 / 172 / 186 / 187 / 191 / 194 / 200 / 203 / 206 / 210
# 唯一改动（数值等价、行数不变）：第 47 行 DIV,Deg,180,$pi → 写死 π 的字面量 3.141592653589793。
#   BTS 里 $pi 由表达式层提供（Event sheets/Globals.xml 未声明该变量），本引擎的 val() 对未定义
#   变量返回 0，会让 Deg = 180/0 变 Infinity 进而使整面正弦骨 NaN。180/π 是「弧度→角度」换算，
#   是唯一能让正弦骨墙正常起伏的取值（H ∈ [5,55]，上下骨之间恒为 34 高的正弦走廊）。
0,CombatZoneResize,241,226,406,391,TLResume
0,HeartTeleport,320,304
0,HeartMode,0
0,TLPause
0,SansSweat,0
0,SET,I,0
0.3,RND,Direction,4
0,ADD,Jump,$Direction,1
0,JMPREL,$Jump
0,JMPREL,4
0,JMPREL,5
0,JMPREL,6
0,JMPREL,7
0,SansBody,HandRight
0,JMPREL,7
0,SansBody,HandDown
0,JMPREL,5
0,SansBody,HandLeft
0,JMPREL,3
0,SansBody,HandUp
0,JMPREL,1
0.26666,SansSlam,$Direction
0.2,BoneStab,$Direction,23.2,1.0,0
0,ADD,I,$I,1
0,JMPL,7,$I,4
0,BoneHRepeat,130,-10,200,1,300,3,183
0,BoneHRepeat,330,650,200,3,300,3,183
0.5,HeartMode,0
2,SansBody,HandLeft
0.2,SansSlam,2
0.3,SansBody,HandRight
0.2,HeartMaxFallSpeed,450
0,HeartDir,0
0,CombatZoneResizeInstant,241,226,449,391
0,CombatZoneSpeed,900
0,CombatZoneResize,241,226,650,391
0.33333,HeartMaxFallSpeed,-300
0,SansAnimation,Idle
0,SansRepeat
0,CombatZoneResize,-10,226,650,391
0.3,CombatZoneSpeed,30
0,CombatZoneResize,-10,264,650,369
0.9,GetHeartPos,HeartX,HeartY
# 【2026-10-06 用户口径·优化】长框段开局这一下原来是无提示的**硬瞬移**（前面还有 0.9s 停顿），
#   改成 0.35s 滑动过去（HeartTeleport 第 4 个参数 = 时长；不传仍是瞬移）。
0,HeartTeleport,40,$HeartY,0.35
0,HeartMaxFallSpeed,0
0,SansSlam,0
0,DIV,Deg,180,3.141592653589793
0,SET,I,0
0,DIV,Ang,$I,2
0,MUL,Ang,$Ang,$Deg
0,SIN,Sine,$Ang
0,MUL,Sine,$Sine,25
0,FLOOR,Sine,$Sine
0,MUL,X,$I,60
0,ADD,X,$X,634
0,SET,Y,270
0,ADD,H,30,$Sine
0,BoneV,$X,$Y,$H,2,900
0,ADD,Y,$Y,$H
0,ADD,Y,$Y,34
0,SUB,H,364,$Y
0,BoneV,$X,$Y,$H,2,900
0,ADD,I,$I,1
0,JMPL,49,$I,44
0,ADD,X,$X,360
0,BoneVRepeat,$X,270,50,2,900,3,15
0,ADD,X,$X,330
0,BoneVRepeat,$X,314,50,2,900,3,15
0,ADD,X,$X,300
0,BoneVRepeat,$X,270,50,2,900,3,15
0,ADD,X,$X,300
0,BoneVRepeat,$X,314,50,2,900,3,15
0,ADD,X,$X,270
0,BoneVRepeat,$X,270,50,2,900,3,15
0,ADD,X,$X,270
0,BoneVRepeat,$X,314,50,2,900,3,15
0,ADD,X,$X,240
0,BoneVRepeat,$X,270,50,2,900,3,15
0,ADD,X,$X,330
0,BoneVRepeat,$X,314,50,2,900,3,15
0,ADD,X,$X,270
0,BoneVRepeat,$X,270,50,2,900,3,15
0,ADD,X,$X,390
0,SET,I,0
0,MUL,X2,$I,30
0,ADD,X2,$X2,$X
0,ADD,H,10,$I
0,BoneV,$X2,270,$H,2,900
0,SUB,Y,365,$H
0,BoneV,$X2,$Y,$H,2,900
0,ADD,I,$I,1
0,JMPL,85,$I,24
0,SET,I,0
8,HeartMaxFallSpeed,330
0,SansSlam,0
0,CombatZoneSpeed,540
0,CombatZoneResize,-10,264,410,369
0.9,SansEndRepeat
0,SansHead,Default
0,SansTorso,Default
0,SansBody,HandLeft
0.2,BoneStab,0,50,0.4,1
0.9,BlackScreen,1
0,Sound,Flash
0.4,BlackScreen,0
0,Sound,Flash
0,CombatZoneResizeInstant,239,226,404,391
0,HeartTeleport,320,376
0,HeartMode,0
0,SansAnimation,HeadBob
0.03333,BoneStab,1,48,0.6,1
0,BoneStab,3,48,0.6,1
0.9,BlackScreen,1
0,Sound,Flash
0.1,BlackScreen,0
0,Sound,Flash
# 【2026-10-06 用户口径·二次】这一段（两条边一起出骨刺）**保持蓝心**（原作 SansSlam 语义：
#   切蓝 + 设重力方向），并把两根骨刺「出来」的预警各延长 0.8s（0.6 → 1.4）。
0,HeartTeleport,262,240
0,SansSlam,3
0.03333,BoneStab,2,48,1.4,1
0,BoneStab,3,48,1.4,1
2.2,BlackScreen,1
0,Sound,Flash
0.1,BlackScreen,0
0,Sound,Flash
# 【2026-10-06 用户口径·二次】同上：保持蓝心（SansSlam），骨刺预警 0.6 → 1.4（+0.8s）。【2026-10-07 用户口径·round24 方案A】本组「两边同时」骨刺：厚度 48 → 38.4（×4/5）、伸出延时 1.4 → 1.9（+0.5s）；注意其后的 0.9,BlackScreen,1 会先清场（0.9 < 1.9），所以这两根仍只以预警形式出现，本次可见变化只有厚度。另：其后的【单发】骨刺（L160）也按同一口径调整：厚度 48 → 38.4、伸出延时 0.6 → 1.1（+0.5s）。
0,HeartTeleport,391,376
0,SansSlam,0
0.03333,BoneStab,0,38.4,1.9,1
0,BoneStab,1,38.4,1.9,1
2.2,BlackScreen,1
0,Sound,Flash
0.1,BlackScreen,0
0,Sound,Flash
0,HeartTeleport,262,240
0,SansSlam,2
0,SansX,320
0.03333,BoneStab,2,38.4,1.1,1
0.7,HeartMode,0
0,SET,gt,0
0,SET,gin,1
0,MUL,Ang,$gt,-10
0,COS,X,$Ang
0,SIN,Y,$Ang
0,MUL,EndX,$X,150
0,MUL,EndY,$Y,150
0,MUL,X,$EndX,3
0,MUL,Y,$EndY,3
0,ADD,X,$X,320
0,ADD,Y,$Y,306
0,ADD,EndX,$EndX,320
0,ADD,EndY,$EndY,306
0,ADD,Ang,$Ang,180
0,GasterBlaster,0,$X,$Y,$EndX,$EndY,$Ang,0.5,0
0,ADD,gt,$gt,$gin
0,JMPNL,156,$gin,1.7
0,ADD,gin,$gin,0.015
0.06666,JMPL,140,$gt,190
1,SansHead,BlueEye
0,HeartMaxFallSpeed,750
0,SansBody,HandRight
0,SansSlamDamage,1
0,SET,I,0
0,SET,Direction,0
0,SET,LastDir,2
0,SET,Wait1,0.13333
0,SET,Wait2,0.13333
0,JMPNE,168,$Direction,$LastDir
0,SUB,Direction,$Direction,2
0,JMPNL,170,$Direction,0
0,ADD,Direction,$Direction,4
0,JMPL,172,$Direction,4
0,SUB,Direction,$Direction,4
0,MUL,Jump,$Direction,2
0,ADD,Jump,$Jump,1
0,JMPREL,$Jump
0,SansBody,HandRight
0,JMPREL,6
0,SansBody,HandDown
0,JMPREL,4
0,SansBody,HandLeft
0,JMPREL,2
0,SansBody,HandUp
$Wait1,SansSlam,$Direction
$Wait2,SET,LastDir,$Direction
0,MOD,Odd,$I,2
0,JMPZ,187,$Odd
0,RND,Direction,4
0,JMPNE,191,$I,21
0,HeartMaxFallSpeed,480
0,SET,Wait1,0.2
0,SET,Wait2,0.2
0,JMPNE,194,$I,25
0,SansHead,Default
0,SansSweat,1
0,JMPNE,200,$I,33
0,SansHead,Tired1
0,SansSweat,2
0,HeartMaxFallSpeed,330
0,SET,Wait1,0.5
0,SET,Wait2,1.1
0,JMPNE,203,$I,33
0,JMPE,186,$Direction,1
0,JMPE,186,$Direction,$LastDir
0,JMPNE,206,$I,35
0,HeartMaxFallSpeed,240
0,SET,Direction,3
0,JMPNE,210,$I,36
0,SansHead,Tired2
0,SansSweat,3
0,HeartMaxFallSpeed,60
0,ADD,I,$I,1
0,JMPL,166,$I,38
1.5,SansAnimation,Tired
2.4,EndAttack
]==] },
  { name = "multi1", csv = [==[
# multi1 —— 多段随机攻击组：每回合先黑屏闪一下，再从 5 种攻击里随机挑一种，共 5 段
#   Attack0 两侧骨墙夹击（repeat 4×16 + 单根高 100）
#   Attack1 左右对称的「高骨 + 底矮骨」三次冲击（Color 0/1 交替）
#   Attack2 内层循环 4 次：纵向间距 Total 逐次加大、骨高/速度随机（蓝魂通道，上下缝恒 18 高）
#   Attack3 双侧 repeat 3×125 的「高 70 + 矮 15」双层骨墙
#   Attack4 随机左/右：11 根高 55 @360 与 10 根矮 15 @360 的高速骨流
# 数据来源：BTS（jcw87/c2-sans-fight, GPL-3.0）Files/sans_multi1.csv 逐行转写，数值未改。
# 标签行（:RndAttack / :Attack0..4 / :Attack2Begin / :SkipRndSpeed / :End）与原作同名同位。
0,CombatZoneResize,133,251,508,391,TLResume
0,HeartTeleport,320,304
0,HeartMode,1
0,TLPause
0,SET,Loop,5
0,:RndAttack
0,BlackScreen,1
0,Sound,Flash
0.4,BlackScreen,0
0,Sound,Flash
0,JMPZ,End,$Loop
0,SUB,Loop,$Loop,1
0,RND,Jump,5
0,ADD,Jump,$Jump,1
0,JMPREL,$Jump
0,JMPABS,Attack0
0,JMPABS,Attack1
0,JMPABS,Attack2
0,JMPABS,Attack3
0,JMPABS,Attack4
0,:Attack0
0,CombatZoneResizeInstant,121,276,526,391
0,HeartMode,1
0,HeartTeleport,320,376
0,BoneVRepeat,128,341,45,0,240,4,16
0,BoneV,64,286,100,0,240,0,1
0,BoneVRepeat,512,341,45,2,240,4,16
0,BoneV,576,286,100,2,240,0,1
0.9,JMPABS,RndAttack
0,:Attack1
0,CombatZoneResizeInstant,121,276,526,391
0,HeartMode,1
0,HeartTeleport,320,376
0,BoneV,128,286,100,0,240,1
0,BoneV,56,366,20,0,240,0
0,BoneV,24,286,100,0,240,0,1
0,BoneV,512,286,100,2,240,1
0,BoneV,584,366,20,2,240,0
0,BoneV,616,286,100,2,240,0,1
1.1,JMPABS,RndAttack
0,:Attack2
0,CombatZoneResizeInstant,171,276,476,391
0,HeartMode,1
0,HeartTeleport,320,376
0,SET,Total,0
0,SET,Loop2,0
0,:Attack2Begin
0,RND,Choice,3
0,ADD,HeightB,$Choice,2
0,MUL,HeightB,$HeightB,10
0,SET,RndSpeed,0
0,JMPZ,SkipRndSpeed,$Loop2
0,RND,RndSpeed,3
0,SUB,RndSpeed,$RndSpeed,1
0,MUL,RndSpeed,$RndSpeed,2
0,:SkipRndSpeed
0,SUB,HeightT,86,$HeightB
0,SUB,YB,386,$HeightB
0,MUL,X,$Loop2,22
0,ADD,X,$X,25
0,ADD,X,$X,$Total
0,ADD,SpeedL,6,$RndSpeed
0,MUL,XL,$X,$SpeedL
0,SUB,XL,320,$XL
0,MUL,SpeedL,$SpeedL,30
0,MUL,RndSpeed,$RndSpeed,-1
0,ADD,SpeedR,6,$RndSpeed
0,MUL,XR,$X,$SpeedR
0,ADD,XR,320,$XR
0,MUL,SpeedR,$SpeedR,30
0,BoneV,$XL,282,$HeightT,0,$SpeedL
0,BoneV,$XL,$YB,$HeightB,0,$SpeedL
0,BoneV,$XR,282,$HeightT,2,$SpeedR
0,BoneV,$XR,$YB,$HeightB,2,$SpeedR
0,MUL,TotalInc,$Choice,5
0,ADD,Total,$Total,$TotalInc
0,ADD,Loop2,$Loop2,1
0,JMPL,Attack2Begin,$Loop2,4
1.9,JMPABS,RndAttack
0,:Attack3
0,CombatZoneResizeInstant,171,276,476,391
0,HeartMode,1
0,HeartTeleport,320,376
0,BoneVRepeat,200,282,70,0,150,3,125
0,BoneVRepeat,200,371,15,0,150,3,125
0,BoneVRepeat,440,282,70,2,150,3,125
0,BoneVRepeat,440,371,15,2,150,3,125
1.7,JMPABS,RndAttack
0,:Attack4
0,CombatZoneResizeInstant,121,276,526,391
0,HeartMode,1
0,RND,Side,2
0,JMPZ,Attack4Other,$Side
0,HeartTeleport,506,376
0,BoneVRepeat,200,331,55,0,360,11,24
0,BoneVRepeat,-64,371,15,0,360,10,24
1.5,JMPABS,RndAttack
0,:Attack4Other
0,HeartTeleport,149,376
0,BoneVRepeat,440,331,55,2,360,11,24
0,BoneVRepeat,704,371,15,2,360,10,24
1.5,JMPABS,RndAttack
0,:End
0,CombatZoneResizeInstant,33,251,608,391
0,EndAttack
]==] },
  { name = "multi2", csv = [==[
# multi2 —— 多段随机攻击组（后半场版）：从 4 种攻击里随机挑一种，共 5 段，各段 1.2~1.9s
#   Attack5 静止平台 + 从一侧飞来的 22 根静止矮骨（repeat 25×16 速度 0）与两根高速骨
#   Attack6 红魂四连炮：随机「正交 0/90/180/270」或「斜向 45/135/225/315」两套
#   Attack7 随机方向 SineBones(16, ±20, 300, 55)
#   Attack8 镜像骨缝：6 根矮 20 @120 与 6 根高 82 @120（间距 76）
# 数据来源：BTS（jcw87/c2-sans-fight, GPL-3.0）Files/sans_multi2.csv 逐行转写，数值未改。
# 注意：本脚本**没有**起手的 CombatZoneResize/TLPause，直接进入循环（原作即如此）。
0,HeartTeleport,320,304
0,SET,Loop,5
0,:RndAttack
0,BlackScreen,1
0,Sound,Flash
0.4,BlackScreen,0
0,Sound,Flash
0,JMPZ,End,$Loop
0,SUB,Loop,$Loop,1
0,RND,Jump,4
0,ADD,Jump,$Jump,1
0,JMPREL,$Jump
0,JMPABS,Attack5
0,JMPABS,Attack6
0,JMPABS,Attack7
0,JMPABS,Attack8
0,:Attack5
0,CombatZoneResizeInstant,121,276,526,391
0,HeartMode,1
0,HeartTeleport,330,304
0,Platform,309,314,41,0,0
0,Platform,309,354,41,0,0

0,BoneVRepeat,121,364,30,2,0,25,16
0,RND,Side,2
0,JMPZ,Attack5Other,$Side
0,BoneV,521,280,35,2,240
0,BoneV,1,319,65,0,240
1.2,JMPABS,RndAttack
0,:Attack5Other
0,BoneV,119,280,35,0,240
0,BoneV,639,319,65,2,240
1.2,JMPABS,RndAttack
0,:Attack6
0,CombatZoneResizeInstant,241,226,406,391
0,HeartMode,0
0,HeartTeleport,320,304
0,RND,Rot,2
0,JMPZ,Attack6Other,$Rot
0,GasterBlaster,1,191,306,191,306,0,0.6,0.26666,1.5
0,GasterBlaster,1,321,166,321,166,90,0.6,0.26666,1.5
0,GasterBlaster,1,449,306,449,306,180,0.6,0.26666,1.5
0,GasterBlaster,1,321,446,321,446,270,0.6,0.26666,1.5
2.6,JMPABS,RndAttack
0,:Attack6Other
0,GasterBlaster,1,191,176,191,176,45,0.6,0.26666,1.5
0,GasterBlaster,1,451,176,451,176,135,0.6,0.26666,1.5
0,GasterBlaster,1,451,436,451,436,225,0.6,0.26666,1.5
0,GasterBlaster,1,191,436,191,436,315,0.6,0.26666,1.5
2.6,JMPABS,RndAttack
0,:Attack7
0,CombatZoneResizeInstant,179,226,404,391
0,HeartMode,0
0,RND,Side,2
0,JMPZ,Attack7Other,$Side
0,HeartTeleport,382,304
0,SineBones,16,-20,300,55
1.7,JMPABS,RndAttack
0,:Attack7Other
0,HeartTeleport,267,304
0,SineBones,16,20,300,55
1.7,JMPABS,RndAttack
0,:Attack8
0,CombatZoneResizeInstant,121,276,526,391
0,HeartMode,1
0,RND,Side,2
0,JMPZ,Attack8Other,$Side
0,HeartTeleport,489,376
0,BoneVRepeat,345,364,20,0,120,6,76
0,BoneVRepeat,297,280,82,2,120,6,76
1.9,JMPABS,RndAttack
0,:Attack8Other
0,HeartTeleport,168,376
0,BoneVRepeat,297,364,20,2,120,6,76
0,BoneVRepeat,345,280,82,0,120,6,76
1.9,JMPABS,RndAttack
0,:End
0,CombatZoneResizeInstant,33,251,608,391
0,EndAttack
]==] },
  { name = "multi3", csv = [==[
# multi3 —— 多段随机攻击组（最长版）：从 9 种攻击里随机挑一种，共 5 段，黑屏闪更快（0.13333s）
#   Attack0..Attack4 与 multi1 完全同参；Attack5..Attack8 与 multi2 完全同参。
# 数据来源：BTS（jcw87/c2-sans-fight, GPL-3.0）Files/sans_multi3.csv 逐行转写，数值未改。
# 跳转沿用原作 1-based 行号：JMPREL,$Jump 的跳表起点后紧跟 9 行 JMPABS（行 16~24）。
0,CombatZoneResize,239,226,404,391,TLResume
0,HeartTeleport,320,304
0,HeartMode,0
0,TLPause
0,SET,Loop,5
0,:RndAttack
0,BlackScreen,1
0,Sound,Flash
0.13333,BlackScreen,0
0,Sound,Flash
0,JMPZ,End,$Loop
0,SUB,Loop,$Loop,1
0,RND,Jump,9
0,ADD,Jump,$Jump,1
0,JMPREL,$Jump
0,JMPABS,Attack0
0,JMPABS,Attack1
0,JMPABS,Attack2
0,JMPABS,Attack3
0,JMPABS,Attack4
0,JMPABS,Attack5
0,JMPABS,Attack6
0,JMPABS,Attack7
0,JMPABS,Attack8
0,:Attack0
0,CombatZoneResizeInstant,121,276,526,391
0,HeartMode,1
0,HeartTeleport,320,376
0,BoneVRepeat,128,341,45,0,240,4,16
0,BoneV,64,286,100,0,240,0,1
0,BoneVRepeat,512,341,45,2,240,4,16
0,BoneV,576,286,100,2,240,0,1
0.9,JMPABS,RndAttack
0,:Attack1
0,CombatZoneResizeInstant,121,276,526,391
0,HeartMode,1
0,HeartTeleport,320,376
0,BoneV,128,286,100,0,240,1
0,BoneV,56,366,20,0,240,0
0,BoneV,24,286,100,0,240,0,1
0,BoneV,512,286,100,2,240,1
0,BoneV,584,366,20,2,240,0
0,BoneV,616,286,100,2,240,0,1
1.1,JMPABS,RndAttack
0,:Attack2
0,CombatZoneResizeInstant,171,276,476,391
0,HeartMode,1
0,HeartTeleport,320,376
0,SET,Total,0
0,SET,Loop2,0
0,:Attack2Begin
0,RND,Choice,3
0,ADD,HeightB,$Choice,2
0,MUL,HeightB,$HeightB,10
0,SET,RndSpeed,0
0,JMPZ,SkipRndSpeed,$Loop2
0,RND,RndSpeed,3
0,SUB,RndSpeed,$RndSpeed,1
0,MUL,RndSpeed,$RndSpeed,2
0,:SkipRndSpeed
0,SUB,HeightT,86,$HeightB
0,SUB,YB,386,$HeightB
0,MUL,X,$Loop2,22
0,ADD,X,$X,25
0,ADD,X,$X,$Total
0,ADD,SpeedL,6,$RndSpeed
0,MUL,XL,$X,$SpeedL
0,SUB,XL,320,$XL
0,MUL,SpeedL,$SpeedL,30
0,MUL,RndSpeed,$RndSpeed,-1
0,ADD,SpeedR,6,$RndSpeed
0,MUL,XR,$X,$SpeedR
0,ADD,XR,320,$XR
0,MUL,SpeedR,$SpeedR,30
0,BoneV,$XL,282,$HeightT,0,$SpeedL
0,BoneV,$XL,$YB,$HeightB,0,$SpeedL
0,BoneV,$XR,282,$HeightT,2,$SpeedR
0,BoneV,$XR,$YB,$HeightB,2,$SpeedR
0,MUL,TotalInc,$Choice,5
0,ADD,Total,$Total,$TotalInc
0,ADD,Loop2,$Loop2,1
0,JMPL,Attack2Begin,$Loop2,4
1.9,JMPABS,RndAttack
0,:Attack3
0,CombatZoneResizeInstant,171,276,476,391
0,HeartMode,1
0,HeartTeleport,320,376
0,BoneVRepeat,200,282,70,0,150,3,125
0,BoneVRepeat,200,371,15,0,150,3,125
0,BoneVRepeat,440,282,70,2,150,3,125
0,BoneVRepeat,440,371,15,2,150,3,125
1.7,JMPABS,RndAttack
0,:Attack4
0,CombatZoneResizeInstant,121,276,526,391
0,HeartMode,1
0,RND,Side,2
0,JMPZ,Attack4Other,$Side
0,HeartTeleport,506,376
0,BoneVRepeat,200,331,55,0,360,11,24
0,BoneVRepeat,-64,371,15,0,360,10,24
1.2,JMPABS,RndAttack
0,:Attack4Other
0,HeartTeleport,149,376
0,BoneVRepeat,440,331,55,2,360,11,24
0,BoneVRepeat,704,371,15,2,360,10,24
1.2,JMPABS,RndAttack
0,:Attack5
0,CombatZoneResizeInstant,121,276,526,391
0,HeartMode,1
0,HeartTeleport,330,304
0,Platform,309,314,41,0,0
0,Platform,309,354,41,0,0
# 【2026-10-06 用户口径·round22】贴地那排骨头：25 根 × 间距 16（缝仅 6px，灵魂宽 16 钻不过去）
#   → 10 根 × 间距 40（缝 30px，能容下灵魂）；横向覆盖宽度不变。（注：以下"10×40"是目标口径，当前未生效）
# 底边骨带：贴底边(框底 391) + 顶部到第二块板(y=354) => 单根竖骨 y=354/h=37
0,BoneVRepeat,121,354,37,2,0,20,20
0,RND,Side,2
0,JMPZ,Attack5Other,$Side
0,BoneV,521,280,35,2,240
0,BoneV,1,319,65,0,240
1.2,JMPABS,RndAttack
0,:Attack5Other
0,BoneV,119,280,35,0,240
0,BoneV,639,319,65,2,240
1.2,JMPABS,RndAttack
0,:Attack6
0,CombatZoneResizeInstant,241,226,406,391
0,HeartMode,0
0,HeartTeleport,320,304
0,RND,Rot,2
0,JMPZ,Attack6Other,$Rot
0,GasterBlaster,1,191,306,191,306,0,0.6,0.26666
0,GasterBlaster,1,321,166,321,166,90,0.6,0.26666
0,GasterBlaster,1,449,306,449,306,180,0.6,0.26666
0,GasterBlaster,1,321,446,321,446,270,0.6,0.26666
1.2,JMPABS,RndAttack
0,:Attack6Other
0,GasterBlaster,1,191,176,191,176,45,0.6,0.26666
0,GasterBlaster,1,451,176,451,176,135,0.6,0.26666
0,GasterBlaster,1,451,436,451,436,225,0.6,0.26666
0,GasterBlaster,1,191,436,191,436,315,0.6,0.26666
1.2,JMPABS,RndAttack
0,:Attack7
0,CombatZoneResizeInstant,179,226,404,391
0,HeartMode,0
0,RND,Side,2
0,JMPZ,Attack7Other,$Side
0,HeartTeleport,382,304
0,SineBones,16,-20,300,55
1.7,JMPABS,RndAttack
0,:Attack7Other
0,HeartTeleport,267,304
0,SineBones,16,20,300,55
1.7,JMPABS,RndAttack
0,:Attack8
0,CombatZoneResizeInstant,121,276,526,391
0,HeartMode,1
0,RND,Side,2
0,JMPZ,Attack8Other,$Side
0,HeartTeleport,489,376
0,BoneVRepeat,345,364,20,0,120,6,76
0,BoneVRepeat,297,280,82,2,120,6,76
1.9,JMPABS,RndAttack
0,:Attack8Other
0,HeartTeleport,168,376
0,BoneVRepeat,297,364,20,2,120,6,76
0,BoneVRepeat,345,280,82,0,120,6,76
1.9,JMPABS,RndAttack
0,:End
0,CombatZoneResizeInstant,33,251,608,391
0,EndAttack
]==] },
  { name = "platformblaster", csv = [==[
# platformblaster —— 蓝魂双平台（右上 8 块向西 / 左下 8 块向东）间躲炮
#                   循环 5 次：左右各一发随机高度的 Size0 龙骨炮（Spin 0.56666 / Blast 仅 0.1）
# 数据来源：BTS（jcw87/c2-sans-fight, GPL-3.0）Files/sans_platformblaster.csv 逐行转写，数值未改。
# 跳转沿用原作 1-based 行号：JMPNZ,8,$Loop → 第 8 行 SUB,Loop,$Loop,1。
0,CombatZoneResize,133,251,508,391,TLResume
0,HeartTeleport,320,376
0,HeartMode,1
0,TLPause
0,PlatformRepeat,552,346,51,2,120,8,140
0,PlatformRepeat,-20,306,51,0,120,8,160
0,SET,Loop,5
0,SUB,Loop,$Loop,1
0,RND,Y,3
0,MUL,Y,$Y,60
0,ADD,Y,$Y,285
0,GasterBlaster,0,0,0,73,$Y,0,0.56666,0.1,1.5
0.9,RND,Y,3
0,MUL,Y,$Y,60
0,ADD,Y,$Y,285
0,GasterBlaster,0,640,0,563,$Y,180,0.56666,0.1,1.5
0.9,JMPNZ,8,$Loop
# 【2026-10-06】末尾留 2.2s：两发都要走完「落定 → 停 1.5s → 发射 0.1s」，
#   不留白的话 EndAttack 会先把还在等待里的龙骨炮 done 掉（只有前几发真打得出来）。
2.2,EndAttack
]==] },
  { name = "platformblasterfast", csv = [==[
# platformblasterfast —— platformblaster 的加速版：循环 6 次、两侧间隔由 0.9 压到 0.7
# 数据来源：BTS（jcw87/c2-sans-fight, GPL-3.0）Files/sans_platformblasterfast.csv 逐行转写，数值未改。
0,CombatZoneResize,133,251,508,391,TLResume
0,HeartTeleport,320,376
0,HeartMode,1
0,TLPause
0,PlatformRepeat,552,346,51,2,120,8,140
0,PlatformRepeat,-20,306,51,0,120,8,160
0,SET,Loop,6
0,SUB,Loop,$Loop,1
0,RND,Y,3
0,MUL,Y,$Y,40
0,ADD,Y,$Y,285
0,GasterBlaster,0,0,0,73,$Y,0,0.56666,0.1
0.7,RND,Y,3
0,MUL,Y,$Y,40
0,ADD,Y,$Y,285
0,GasterBlaster,0,640,0,563,$Y,180,0.56666,0.1
0.7,JMPNZ,8,$Loop
0,EndAttack
]==] },
  { name = "platforms1", csv = [==[
# platforms1 —— 蓝魂站平台：向东的平台 + 41 根矮骨地毯（间距 15），后半改由两侧高骨推挤
# 数据来源：BTS（jcw87/c2-sans-fight, GPL-3.0）Files/sans_platforms1.csv 逐行转写，数值未改。
# 坐标系：原版 640×480，Y 向下；战斗框参数为 (左, 上, 右, 下)。速度单位 px/s（= 原作值 ×30）。
0,CombatZoneResize,133,251,508,391,TLResume
0,HeartTeleport,320,376
0,HeartMode,1
0,TLPause
0,Platform,15,346,61,0,120
0.4,BoneVRepeat,133,356,40,0,120,41,15
1.2,Platform,-61,346,61,0,150
1.7,Platform,-61,346,61,0,180
1,BoneV,133,257,45,0,210
0,BoneV,119,257,45,0,210
0,BoneV,105,257,45,0,210
2.3,BoneV,133,257,95,0,270
1.7,EndAttack
]==] },
  { name = "platforms2", csv = [==[
# platforms2 —— 蓝魂：58 根矮骨地毯（间距 15）持续压迫，同时从右侧连续送来 6 块平台
# 数据来源：BTS（jcw87/c2-sans-fight, GPL-3.0）Files/sans_platforms2.csv 逐行转写，数值未改。
# 坐标系：原版 640×480，Y 向下；战斗框参数为 (左, 上, 右, 下)。速度单位 px/s（= 原作值 ×30）。
0,CombatZoneResize,133,251,508,391,TLResume
0,HeartTeleport,320,376
0,HeartMode,1
0,TLPause
0,Platform,640,346,51,2,150
0.4,BoneVRepeat,508,356,40,2,120,58,15
0.4,Platform,640,296,51,2,150
0.5,Platform,640,346,51,2,150
0.4,BoneV,508,316,56,2,150
0.4,Platform,640,296,31,2,60
0.6,Platform,640,326,51,2,150
0.7,Platform,640,336,51,2,150
0.3,BoneV,508,257,45,2,150
0.4,Platform,640,316,51,2,150
0.3,BoneV,508,257,55,2,150
0.7,BoneV,508,257,35,2,150
1.5,BoneV,133,257,95,0,90
0.7,BoneV,508,276,96,2,240
2.5,EndAttack
]==] },
  { name = "platforms3", csv = [==[
# platforms3 —— 循环 16 次：从 3 个位置里随机挑一处弹出一根骨（RND + JMPREL 跳表），
#              两组 PlatformRepeat 提供持续移动的落脚点（右上 5 块向西、左下 4 块向东）
# 数据来源：BTS（jcw87/c2-sans-fight, GPL-3.0）Files/sans_platforms3.csv 逐行转写。
# 【2026-10-05 第十轮 · 用户口径】ROUND 10 有根「过不去的骨头」——两根吊顶/中段骨正好盖住了平台的
#   站立带（平台顶面 -SOUL_CLAMP-4..+4），站在平台上必被扫到、没有落脚点：
#     * 517,257,45 → 257..302 盖住 y=306 平台的站立带 294..302 → 高度 45 → **32**（257..289，让出 5px）
#     * 125,306,40 → 306..346 盖住 y=346 平台的站立带 334..342 → 高度 40 → **24**（306..330，让出 4px）
#   第十一轮补充：贴地骨 517,349,35 → **24**（349..373）—— 原高度压住地面站立带 379..387，
#   玩家说的「最后从右边过来的骨头没法躲」就是它；现在地面也让开了。
# 跳转沿用原作 1-based 行号（行号只数非注释行，故上方注释不影响）：JMPZ,22 → 第 22 行 EndAttack；
# JMPABS,8 → 第 8 行 JMPZ,22,$Loop（循环回跳）。
0,CombatZoneResize,133,251,508,391,TLResume
0,HeartTeleport,320,376
0,HeartMode,1
0,TLPause
0,PlatformRepeat,513,346,121,2,120,5,220
0,PlatformRepeat,-71,306,161,0,120,4,280
0,SET,Loop,16
0,JMPZ,22,$Loop
0,SUB,Loop,$Loop,1
0,RND,Jump,3
0,ADD,Jump,$Jump,1
0,JMPREL,$Jump
0,JMPREL,3
0,JMPREL,4
0,JMPREL,5
0,BoneV,517,257,45,2,120
0.5,JMPABS,8
0,BoneV,125,306,40,0,120
0.5,JMPABS,8
0,BoneV,517,349,35,2,120
0.5,JMPABS,8
0,EndAttack
]==] },
  { name = "platforms4", csv = [==[
# platforms4 —— 大框（113,231,548,391）蓝魂站上一块向东移动的平台（宽 41）
#              同时四组定向骨阵：右底 60 根向南、左 11 根向北、中 13 根向南、右 11 根向北
# 数据来源：BTS（jcw87/c2-sans-fight, GPL-3.0）同名 sans_*.csv 逐行转写。
# 【第十二轮】按仓库 readme.md「Known Issues」第 2 条：这块平台应当**从 0 加速到全速**，
#   旧实现一上来就是 90px/s。给 Platform 加第 8 个参数 Ramp=1（1 秒到全速），数值其余不动。
# 注意：原文件第 4 行 TLPause 后无 TLResume，靠第 1 行 CombatZoneResize 的 FinishAction 恢复脚本。
0,CombatZoneResize,113,231,548,391,TLResume
0,HeartTeleport,320,376
0,HeartMode,1
0,TLPause
0,Platform,151,336,41,0,90,1
0,HeartTeleport,175,327
# ↓ 恢复 BTS 原版参数（2026-10-05 第二轮：用户要求“优先学习参考仓库的代码制作攻击模式”）。
#   原来这里被改成“静止 29 根、只铺满框宽”，是为了绕开“骨墙 900px 横扫出框”；
#   现在 core 按 BTS 的 CombatZoneClipped 语义**把竖骨裁进战斗框**（见 core.lua 的 clipVZone），
#   所以 60 根 × 间距 15 的原版骨毯**保持原数值**也不会再画出框外 —— 数值不再改动。
0,BoneVRepeat,528,366,40,0,60,60,15
0,BoneVRepeat,283,267,40,3,90,11,85
0,BoneVRepeat,363,331,40,1,120,13,95
0,BoneVRepeat,443,248,40,3,90,11,85
7.3,EndAttack
]==] },
  { name = "platforms4hard", csv = [==[
# platforms4hard —— platforms4 的高难变体：平台更窄（31），三组骨阵的数量/间距/速度都加压
#                  （右底 60×15 不变；左侧 12 根间距 65、中列 11 根间距 90、右列 12 根间距 65）
# 数据来源：BTS（jcw87/c2-sans-fight, GPL-3.0）Files/sans_platforms4hard.csv 逐行转写，数值未改。
0,CombatZoneResize,113,231,548,391,TLResume
0,HeartTeleport,320,376
0,HeartMode,1
0,TLPause
0,Platform,151,336,31,0,90,1
0,HeartTeleport,175,327
# ↓ 恢复 BTS 原版参数（2026-10-05 第二轮：用户要求“优先学习参考仓库的代码制作攻击模式”）。
#   原来这里被改成“静止 29 根、只铺满框宽”，是为了绕开“骨墙 900px 横扫出框”；
#   现在 core 按 BTS 的 CombatZoneClipped 语义**把竖骨裁进战斗框**（见 core.lua 的 clipVZone），
#   所以 60 根 × 间距 15 的原版骨毯**保持原数值**也不会再画出框外 —— 数值不再改动。
0,BoneVRepeat,528,366,40,0,60,60,15
0,BoneVRepeat,283,268,40,3,90,12,65
0,BoneVRepeat,363,325,40,1,120,11,90
0,BoneVRepeat,443,268,40,3,90,12,65
7.3,EndAttack
]==] },
  { name = "randomblaster1", csv = [==[
# randomblaster1 —— 红魂：以灵魂为中心、半径 400×300 上取随机角度，炮口从该方向的圆周外飞入
#                  终点钳制到 [50,590]×[40,440]，循环 15 次；Size0、Spin 0.46666、Blast 仅 0.03333
# 数据来源：BTS（jcw87/c2-sans-fight, GPL-3.0）Files/sans_randomblaster1.csv 逐行转写，数值未改。
# 跳转沿用原作 1-based 行号（只数非注释行）：
#   JMPNL,21 / JMPNG,23 / JMPNL,25 / JMPNG,27 是四个边界钳制；JMPNZ,6 → 第 6 行 SUB,Loop,$Loop,1。
# 【2026-10-05 第十一轮 · 用户口径】ROUND 14：单个龙骨炮「出现花 1.5s，到发射再等 1s」——
#   SpinTime 0.46666 → **1.5**，并给本项目扩展的第 10 个参数 HoldTime 传 **1.0**（转到位后停 1s 再发射）；
#   循环次数 15 → 3（单发周期 1.5+1+0.03 ≈ 2.6s，3 发 ≈ 7.8s，落在 8s 回合内）。
0,CombatZoneResize,121,186,526,391,TLResume
0,HeartTeleport,320,304
0,HeartMode,0
0,TLPause
0.5,SET,Loop,15
0,SUB,Loop,$Loop,1
0,RND,Ang,360
0,COS,X,$Ang
0,SIN,Y,$Ang
0,MUL,EndX,$X,200
0,MUL,EndY,$Y,200
0,MUL,X,$X,400
0,MUL,Y,$Y,300
0,GetHeartPos,HeartX,HeartY
0,ADD,EndX,$EndX,$HeartX
0,ADD,EndY,$EndY,$HeartY
0,ADD,X,$X,$HeartX
0,ADD,Y,$Y,$HeartY
0,JMPNL,21,$EndX,50
0,SET,EndX,50
0,JMPNG,23,$EndX,590
0,SET,EndX,590
0,JMPNL,25,$EndY,40
0,SET,EndY,40
0,JMPNG,27,$EndY,440
0,SET,EndY,440
0,ANGLE,Ang,$EndX,$EndY,$HeartX,$HeartY
0,GasterBlaster,0,$X,$Y,$EndX,$EndY,$Ang,0.46666,0.83333,1.5,5
0.53333,JMPNZ,6,$Loop
# 【2026-10-06】同上：末尾留 2.2s 让最后一发走完 0.46666 + 1.5 + 0.03333
2.2,EndAttack
]==] },
  { name = "randomblaster2", csv = [==[
# randomblaster2 —— randomblaster1 的后期版本：炮更大（Size1）、蓄力更久（Spin 0.66666）
#                  循环 12 次（起手 0.4s、间隔 0.66666s），Blast 仍为 0.03333
# 数据来源：BTS（jcw87/c2-sans-fight, GPL-3.0）Files/sans_randomblaster2.csv 逐行转写，数值未改。
0,CombatZoneResize,121,186,526,391,TLResume
0,HeartTeleport,320,304
0,HeartMode,0
0,TLPause
0.4,SET,Loop,12
0,SUB,Loop,$Loop,1
0,RND,Ang,360
0,COS,X,$Ang
0,SIN,Y,$Ang
0,MUL,EndX,$X,200
0,MUL,EndY,$Y,200
0,MUL,X,$X,400
0,MUL,Y,$Y,300
0,GetHeartPos,HeartX,HeartY
0,ADD,EndX,$EndX,$HeartX
0,ADD,EndY,$EndY,$HeartY
0,ADD,X,$X,$HeartX
0,ADD,Y,$Y,$HeartY
0,JMPNL,21,$EndX,50
0,SET,EndX,50
0,JMPNG,23,$EndX,590
0,SET,EndX,590
0,JMPNL,25,$EndY,40
0,SET,EndY,40
0,JMPNG,27,$EndY,440
0,SET,EndY,440
0,ANGLE,Ang,$EndX,$EndY,$HeartX,$HeartY
0,GasterBlaster,1,$X,$Y,$EndX,$EndY,$Ang,0.66666,0.83333,1.5,5
0.66666,JMPNZ,6,$Loop
# 【2026-10-06】同上：末尾留 2.4s 让最后一发走完 0.66666 + 1.5 + 0.03333
2.4,EndAttack
]==] },
  { name = "sans_bluebone", csv = [==[
# sans_bluebone —— 蓝骨（Color 1，高 100）与白骨（Color 0，高 20）成对横穿
0,CombatZoneResize,133,251,508,391,TLResume
0,HeartTeleport,320,376
0,HeartMode,1
0,TLPause
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
1.66666,EndAttack
]==] },
  { name = "sans_bonegap1", csv = [==[
# sans_bonegap1 —— 宽矮框（375×140）**左右两侧各出一高一矮**，速度 180、间距 120
# 【2026-10-05 第六轮 · 用户口径】「左右高低骨进入的组合」→ **高骨为蓝骨（Color=1）**，矮骨保持白骨。
#   前四行的第 9 列就是 Color（本项目给 BoneVRepeat 加的向后兼容扩展；官方该命令没有 Color）。
#   高骨 32 高（严格低于 0.6s 跳跃高度 70px），且两行高骨都跟在两行矮骨后面 0.3s。
#   原版照抄（改前）：
#     0.2,BoneVRepeat,128,257,95,0,180,8,120
#     0,BoneVRepeat,128,366,20,0,180,8,120
#     0,BoneVRepeat,503,257,95,2,180,8,120
#     0,BoneVRepeat,503,366,20,2,180,8,120
#     6.4,EndAttack
0,CombatZoneResize,133,251,508,391,TLResume
0,HeartTeleport,320,376
0,HeartMode,1
0,TLPause
0.2,BoneVRepeat,128,366,20,0,180,8,120,0
0,BoneVRepeat,503,366,20,2,180,8,120,0
0.3,BoneVRepeat,128,257,58,0,180,8,120,1
0,BoneVRepeat,503,257,58,2,180,8,120,1
6.1,EndAttack
]==] },
  { name = "sans_bonegap1fast", csv = [==[
# sans_bonegap1fast —— 同 bonegap1，速度 210、间距 133、起手 0.4s
# 【2026-10-05 第六轮 · 用户口径】同上：**高骨为蓝骨（Color=1）**，矮骨白骨；高骨跟在矮骨后 0.3s。
#   原版照抄（改前）：
#     0.4,BoneVRepeat,128,257,95,0,210,8,133
#     0,BoneVRepeat,128,366,20,0,210,8,133
#     0,BoneVRepeat,503,257,95,2,210,8,133
#     0,BoneVRepeat,503,366,20,2,210,8,133
#     6,EndAttack
0,CombatZoneResize,133,251,508,391,TLResume
0,HeartTeleport,320,376
0,HeartMode,1
0,TLPause
0.4,BoneVRepeat,128,366,20,0,210,8,133,0
0,BoneVRepeat,503,366,20,2,210,8,133,0
0.3,BoneVRepeat,128,257,58,0,210,8,133,1
0,BoneVRepeat,503,257,58,2,210,8,133,1
5.7,EndAttack
]==] },
  { name = "sans_bonegap2", csv = [==[
# sans_bonegap2
# 【2026-10-07 用户口径·round4/13】高骨（上骨）按预期抬起 7px：HeightT 回到 111 - HeightB（= 原版值），
#   上骨下缘 = 368 - HeightB、下骨上缘 = 386 - HeightB → 缝恒 18px（与 round15 / multi1 Attack2 逐像素一致）；下骨、骨速、间距、循环均不动。
# 用循环 + 标签实现：Total 累加控制横向间距，Choice 决定骨高与增量
0,CombatZoneResize,133,251,508,391,TLResume
0,HeartTeleport,320,376
0,HeartMode,1
0,TLPause
0,SET,Total,0
0,:Begin
0,JMPNL,End,$Total,150
0,RND,Choice,4
0,MUL,Jump,$Choice,3
0,ADD,Jump,$Jump,1
0,JMPREL,$Jump
0,SET,HeightB,20
0,ADD,Total,$Total,9
0,JMPREL,9
0,SET,HeightB,30
0,ADD,Total,$Total,11
0,JMPREL,6
0,SET,HeightB,40
0,ADD,Total,$Total,19
0,JMPREL,3
0,SET,HeightB,60
0,ADD,Total,$Total,25
0,RND,RndSpeed,3
0,SUB,RndSpeed,$RndSpeed,1
0,MUL,RndSpeed,$RndSpeed,2
0,JMPNE,SkipZeroSpeed,$HeightB,40
0,SET,RndSpeed,0
0,:SkipZeroSpeed
0,SUB,HeightT,111,$HeightB
0,SUB,YB,386,$HeightB
0,ADD,X,$Total,32
0,JMPNE,BoneL,$HeightB,60
0,SET,RndSpeed,-1
0,:BoneL
0,ADD,SpeedL,8,$RndSpeed
0,MUL,XL,$X,$SpeedL
0,SUB,XL,320,$XL
0,MUL,SpeedL,$SpeedL,30
0,JMPE,BoneR,$HeightB,60
0,MUL,RndSpeed,$RndSpeed,-1
0,:BoneR
0,ADD,SpeedR,8,$RndSpeed
0,MUL,XR,$X,$SpeedR
0,ADD,XR,320,$XR
0,MUL,SpeedR,$SpeedR,30
0,BoneV,$XL,257,$HeightT,0,$SpeedL
0,BoneV,$XL,$YB,$HeightB,0,$SpeedL
0,BoneV,$XR,257,$HeightT,2,$SpeedR
0,BoneV,$XR,$YB,$HeightB,2,$SpeedR
0,MUL,Jump,$Choice,2
0,ADD,Jump,$Jump,1
0,JMPREL,$Jump
0,ADD,Total,$Total,15
0,JMPREL,6
0,ADD,Total,$Total,17
0,JMPREL,4
0,ADD,Total,$Total,19
0,JMPREL,2
0,ADD,Total,$Total,25
0,JMPABS,Begin
0,:End
7,EndAttack
]==] },
  { name = "sans_boneslideh", csv = [==[
# sans_boneslideh —— 底部矮骨向东、上部高骨向西，速度 120、间距 76
# 【2026-10-05 第六轮 · 用户澄清】这一关的高骨**不是**蓝骨，恢复普通白骨：
#   用户原话：「round4 的上方不需要是蓝骨，我说的是**左右高低骨进入的组合**时高骨为蓝骨」。
#   「左右高低骨」= sans_bonegap1 / sans_bonegap1fast（左右两侧各自出一高一矮），蓝骨改在那边。
#   这里保持第四轮的两条口径：高骨 32 高（严格低于 0.6s 跳跃高度）、跟在矮骨后面 0.5s 进场。
0,CombatZoneResize,133,251,508,391,TLResume
0,HeartTeleport,320,376
0,HeartMode,1
0,TLPause
0.5,BoneVRepeat,128,366,20,0,120,8,76
0.5,BoneVRepeat,513,257,58,2,120,8,76
6.7,EndAttack
]==] },
  { name = "sans_boneslidev", csv = [==[
# sans_boneslidev —— 上下两组横向骨（宽 200）分别向南/向北，速度 300、间距 183
0,CombatZoneResize,241,226,406,391,TLResume
0,HeartTeleport,320,304
0,HeartMode,0
0,TLPause
0.2,BoneHRepeat,130,-10,200,1,300,7,183
0,BoneHRepeat,330,650,200,3,300,7,183
5.76666,EndAttack
]==] },
  { name = "sans_bonestab1", csv = [==[
# 【方案甲 A-9】本文件逐字抄自参考仓库 Files/sans_bonestab1.csv（原版 BoneStab 三档）
0,CombatZoneResize,241,226,406,391,TLResume
0,HeartTeleport,320,304
0,HeartMode,0
0,TLPause
0,SET,Loop,9
0,JMPZ,26,$Loop
0,SUB,Loop,$Loop,1
0,RND,Direction,4
0,ADD,Jump,$Direction,1
0,JMPREL,$Jump
0,JMPREL,4
0,JMPREL,5
0,JMPREL,6
0,JMPREL,7
0,SansBody,HandRight
0,JMPREL,7
0,SansBody,HandDown
0,JMPREL,5
0,SansBody,HandLeft
0,JMPREL,3
0,SansBody,HandUp
0,JMPREL,1
0.26666,SansSlam,$Direction
0.2,BoneStab,$Direction,13.5,1.2,0.33333
0.6,JMPABS,6
0,EndAttack
]==] },
  { name = "sans_bonestab2", csv = [==[
# 【方案甲 A-9】本文件逐字抄自参考仓库 Files/sans_bonestab2.csv（原版 BoneStab 三档）
0,CombatZoneResize,241,226,406,391,TLResume
0,HeartTeleport,320,304
0,HeartMode,0
0,TLPause
0,SET,Loop,9
0,JMPZ,26,$Loop
0,SUB,Loop,$Loop,1
0,RND,Direction,4
0,ADD,Jump,$Direction,1
0,JMPREL,$Jump
0,JMPREL,4
0,JMPREL,5
0,JMPREL,6
0,JMPREL,7
0,SansBody,HandRight
0,JMPREL,7
0,SansBody,HandDown
0,JMPREL,5
0,SansBody,HandLeft
0,JMPREL,3
0,SansBody,HandUp
0,JMPREL,1
0.26666,SansSlam,$Direction
0.2,BoneStab,$Direction,13.5,1.2,0.2
0.93333,JMPABS,6
0,EndAttack
]==] },
  { name = "sans_bonestab3", csv = [==[
# 【方案甲 A-9】本文件逐字抄自参考仓库 Files/sans_bonestab3.csv（原版 BoneStab 三档）
0,CombatZoneResize,241,226,406,391,TLResume
0,HeartTeleport,320,304
0,HeartMode,0
0,TLPause
# 【2026-10-06 用户口径·round22（内部 22 = HUD 23 = sans_bonestab3）】
#   「地面向上升起的骨头攻击」= BoneStab：骨墙太厚太密 → 削薄 + 降次数 + 每轮 +1s；
#   并把整条边切成 5 段、每隔 1 段留空 → **骨墙保留 2 个能钻过去的缺口**（lanes=5, gapEvery=2）。
#   dist 18 → 12（伸出更短、更细）；Loop 9 → 6（9 根降到 6 根）；周期 0.23333 → 1.23333。
0,SET,Loop,6
0,JMPZ,27,$Loop
0,SUB,Loop,$Loop,1
0,RND,Direction,4
0,ADD,Jump,$Direction,1
0,JMPREL,$Jump
0,JMPREL,4
0,JMPREL,5
0,JMPREL,6
0,JMPREL,7
0,SansBody,HandRight
0,JMPREL,7
0,SansBody,HandDown
0,JMPREL,5
0,SansBody,HandLeft
0,JMPREL,3
0,SansBody,HandUp
0,JMPREL,1
0.26666,SansSlam,$Direction
# 【2026-10-06 二次口径】尺寸再减半 dist 18→9、出现 warn 0.4→1.2、升起 out 0.22→1.02
# 【2026-10-09 用户口径·ROUND23】每一轮骨刺都配一根橙色横骨（x=241 框左 / y=216 框顶上方 10px / 宽=165 整框 /
#   dir=1 向下 / speed=180 / color=2）；1.47s 飞出屏 < 每轮 1.5s ⇒ 每轮只有一根在场。
0,BoneH,241,216,165,1,180,2
0,BoneStab,$Direction,13.5,1.2,0.25
1.23333,JMPABS,6
0,EndAttack
]==] },
  { name = "sans_intro", csv = [==[
# sans_intro —— 回合 0「不意打ち」
# 【2026-10-05 第九轮 · 用户口径】首轮（sans_intro）全部龙骨炮的「出现 → 释放」间隔 = **1.0s**：
#   SpinTime 0.333（Size1）/ 0.666（Size2）→ **1.0**（第六轮先改 0.6，第九轮再加到 1.0）；BlastTime 按原版不变。
#   只在 SpinTime 这一列做了改动，其余数值与下面「原版对照」逐字一致。
# 数值（时序 / 坐标 / 参数）按参考实现逐字转写以保证保真；文件文本为本项目自行编排。
# 坐标系：原版 640×480，Y 向下。战斗框参数为 (左, 上, 右, 下)。
# 唯一的**有意偏离**：第 3 段龙骨炮由原版的"第 1 段重复"改成「上下」（见该段前的注释与文末原文对照）。
# 序列：黑屏闪 → 框 165×165 → SansSlam → BoneStab(自上而下) → SineBones(20,-24,360,25)
#       → ① 十字 → ② 交叉 → ③ 上下 → ④ 左右(Size2) → "here we go." → EndAttack
# 注意（2026-10-05 调整）：四组龙骨炮之间的间隔各 +0.1s（用户验收「初见杀龙骨炮间隔略微延长」）——脚本全长 8.93s，回合时长必须覆盖它（core 的 startEnemy 已按脚本时长延长 enemyDur），
#       否则回合会在 2.8s 掐断，①②③④ 一段都打不出来。
0,SansAnimation
0,SansHead,ClosedEyes
0,SansText,ready?
0,BlackScreen,1
0,Sound,Flash
0.06666,BlackScreen,0
0,Sound,Flash
0,CombatZoneResizeInstant,239,226,404,391
0,HeartTeleport,320,304
0,HeartMode,0
0,SansBody,HandDown
0,SansHead,BlueEye
0,Sound,GasterBlaster
0.26666,SansSlam,1
0.5,SansBody,HandUp
0,SansHead,NoEyes
# 【2026-10-06 用户口径】整场第一段（初见杀）的骨刺「太厚」→ 厚度减半：
#   BoneStab(dir, distance, warn, stay) 的第 2 个参数是伸出厚度，54 → 27。
#   （实际板厚 = distance+8，露出 = distance-3，所以从 51px 变成 24px。）
0,BoneStab,1,27,0.16666,1
0.7,HeartMode,0
0,SansBody,HandRight
0,Sound,Ding
0.4,Sound,GasterBlaster
0.4,SineBones,20,-24,360,25
1.2,SansAnimation
0,GasterBlaster,1,0,0,189,246,0,1,0.26666
0,GasterBlaster,1,0,0,259,166,90,1,0.26666
0,GasterBlaster,1,640,480,449,366,180,1,0.26666
0,GasterBlaster,1,640,480,379,446,270,1,0.26666
1.0,GasterBlaster,1,0,0,189,176,45,1,0.26666
0,GasterBlaster,1,640,0,449,176,135,1,0.26666
0,GasterBlaster,1,640,480,449,436,225,1,0.26666
0,GasterBlaster,1,0,480,189,436,315,1,0.26666
# ↓ 第 3 段：上下（本次按用户验收描述改；BTS 原版这里是与第 1 段**逐字重复**的第 3 组"十字"，
#   原行保留在文件末尾的注释里，数值一个没丢）。四发的参数全部取自本文件既有的原版值：
#   起点 (0,0)/(640,0)/(0,480)/(640,480) 与第 2 段相同；落点 x=259/379、y=166/446 与第 1 段相同；
#   角度 90=南（向下）、270=北（向上）；SpinTime/BlastTime 与 Size1 各段相同。
#   效果：x=259 与 x=379 两条全高光柱，各自上下对射 → 中间 x≈277..361 留一条可躲的缝。
1.0,GasterBlaster,1,0,0,259,166,90,1,0.26666
0,GasterBlaster,1,640,0,379,166,90,1,0.26666
0,GasterBlaster,1,0,480,259,446,270,1,0.26666
0,GasterBlaster,1,640,480,379,446,270,1,0.26666
0.8,GasterBlaster,2,0,240,139,306,0,1,0.5
0,GasterBlaster,2,640,240,499,306,180,1,0.5
3,SansHead,Default
0,SansText,here we go.
0,EndAttack
# ---------------------------------------------------------------- 原版对照（BTS 逐字原文）
# 上面第 3 段那 4 行在 BTS `Files/sans_intro.csv` 里是**与第 1 段逐字重复**的（已用
#   https://raw.githubusercontent.com/Jcw87/c2-sans-fight/master/Files/sans_intro.csv 逐字节比对），
# 即原版的龙骨炮是「十字 → 交叉 → 十字(重复) → 左右(Size2)」。按用户验收描述改成「十字 → 交叉 → 上下」，
# 被替换掉的原版 4 行原样保留在这里，随时可以换回来：
# 0.9,GasterBlaster,1,0,0,189,246,0,0.333,0.26666
# 0,GasterBlaster,1,0,0,259,166,90,0.333,0.26666
# 0,GasterBlaster,1,640,480,449,366,180,0.333,0.26666
# 0,GasterBlaster,1,640,480,379,446,270,0.333,0.26666
# 其余行（含 Size2 的「左右」收尾）与 BTS 原文逐字一致。
# 注意：上面正文里的 SpinTime 已按用户口径改成 0.6（原版 0.333 / 0.666）。
]==] },
  { name = "sans_spare", csv = [==[
# sans_spare —— 饶恕时用的空攻击：蓝魂、宽矮框、0.3s 后结束
0,CombatZoneResize,133,251,508,391,TLResume
0,HeartTeleport,320,376
0,HeartMode,1
0,TLPause
0.3,EndAttack
]==] },
  { name = "spiral1", csv = [==[
# spiral1 —— 螺旋龙骨炮 · 轻档（内部回合 17，HUD 显示 ROUND 18 / 20）
# 几何逐字取自原作 sans_final.csv 阶段④「旋转光束」：中心 (320,306)、Ang = -10·gt、
#   半径 150→450（炮身在外圈 450、光束指向内侧）、SpinTime 0.5、BlastTime 0（瞬发）。
#   位移公式一字未改：EndX/EndY = 单位向量×150，X/Y = 同一方向×450。
# 三档螺旋**只改**「总转角上限 gt」「角速度增量上限 gin」「每发间隔」：
#   spiral1  gt→140 / gin→1.40 / 0.09s     （框 305 宽，实测 103 发）
#   spiral2  gt→160 / gin→1.70 / 0.075s    （框 237 宽，实测 104 发）
#   spiral3  gt→190 / gin→1.70 / 0.06666s  （= 原作强度，实测 122 发，接原作阶段⑤力竭）
# 发数是 core_selftest 的「全部脚本空跑」实测值（`实体：… 龙骨炮 N`），不是估算。
# 光束判定是"从炮身沿 ang 射 2000px"的整条 AABB（core 的 GasterBlaster 判定），
# 所以光束会**穿过框中心**：玩家要躲在两束光之间的缝里，而不是站在中间不动。
# 框给 305 宽（比原版阶段④的 165 宽），轻档留出更多走位空间。
0,CombatZoneResize,171,226,476,391,TLResume
0,HeartTeleport,320,306
0,HeartMode,0
0,TLPause
0,SansHead,BlueEye
0,SansX,320
0,Sound,GasterBlaster
0,SET,gt,0
0,SET,gin,1
0,:Loop
0,MUL,Ang,$gt,-10
0,COS,X,$Ang
0,SIN,Y,$Ang
0,MUL,EndX,$X,150
0,MUL,EndY,$Y,150
0,MUL,X,$EndX,3
0,MUL,Y,$EndY,3
0,ADD,X,$X,320
0,ADD,Y,$Y,306
0,ADD,EndX,$EndX,320
0,ADD,EndY,$EndY,306
0,ADD,Ang,$Ang,180
0,GasterBlaster,0,$X,$Y,$EndX,$EndY,$Ang,0.5,0,0,5
0,ADD,gt,$gt,$gin
0,JMPNL,Tail,$gin,1.4
0,ADD,gin,$gin,0.02
0,:Tail
0.09,JMPL,Loop,$gt,140
0,SansHead,Default
0,EndAttack
]==] },
  { name = "spiral2", csv = [==[
# spiral2 —— 螺旋龙骨炮 · 中档（内部回合 18，HUD 显示 ROUND 19 / 20）
# 与 spiral1 同一套几何（原作阶段④），参数收到更接近原作：gt→160 / gin→1.70 / 0.015 / 0.075s，
# 框缩到 237 宽 —— 每发转角更大（10·gin 度）、间隔更短、走位空间更小。
0,CombatZoneResize,205,226,442,391,TLResume
0,HeartTeleport,320,306
0,HeartMode,0
0,TLPause
0,SansHead,BlueEye
0,SansX,320
0,Sound,GasterBlaster
0,SET,gt,0
0,SET,gin,1
0,:Loop
0,MUL,Ang,$gt,-10
0,COS,X,$Ang
0,SIN,Y,$Ang
0,MUL,EndX,$X,150
0,MUL,EndY,$Y,150
0,MUL,X,$EndX,3
0,MUL,Y,$EndY,3
0,ADD,X,$X,320
0,ADD,Y,$Y,306
0,ADD,EndX,$EndX,320
0,ADD,EndY,$EndY,306
0,ADD,Ang,$Ang,180
0,GasterBlaster,0,$X,$Y,$EndX,$EndY,$Ang,0.5,0,0,5
0,ADD,gt,$gt,$gin
0,JMPNL,Tail,$gin,1.7
0,ADD,gin,$gin,0.015
0,:Tail
0.075,JMPL,Loop,$gt,160
0,SansHead,Default
0,EndAttack
]==] },
  { name = "spiral3", csv = [==[
# spiral3 —— 螺旋龙骨炮 · 原作强度（内部回合 19 = 最后一回合，HUD 显示 ROUND 20 / 20）
# 阶段 A：原作 sans_final.csv 阶段④「旋转光束」**逐字**参数（gt→190 / gin 1→1.7 每次 +0.015 /
#        每发 0.06666s / Ang = -10·gt / 半径 150→450 / SpinTime 0.5 / BlastTime 0），
#        框也用原版阶段③留下的 165×165（(239,226)-(404,391)）。
# 阶段 B：原作阶段⑤「力竭」段（sans_final.csv 行 157-213）逐字转写 ——
#        38 次砸击、SansSlamDamage 1（真的掉血）、Wait 递减、I=25 冒汗 / I=33 出现 Tired1 /
#        I=35 强制朝北 / I=36 起 Tired2（MaxFallSpeed 只剩 60）→ 最后 SansAnimation Tired。
# 唯一改动：原作用的是**数字行号**跳转，这里插了标签行，行号会整体平移，
#        所以把所有 JMP* 的数字目标换成等价标签（JMPREL 是相对偏移，原样保留）。
# 跳转目标对照（原行号 → 本文件标签，全部按"标签落在原行号那一行"放置）：
#   166→SlamLoop  168→DirClampA  170→DirClampB  172→Dispatch  186→RandDir
#   187→AfterRand 191→T21        194→T25        200→T33       203→T33b
#   206→T35       210→T36
0,CombatZoneResize,241,226,406,391,TLResume
0,HeartTeleport,320,306
0,HeartMode,0
0,TLPause
0,SansHead,BlueEye
0,SansX,320
0,Sound,GasterBlaster
0,SET,gt,0
0,SET,gin,1
0,:Loop
0,MUL,Ang,$gt,-10
0,COS,X,$Ang
0,SIN,Y,$Ang
0,MUL,EndX,$X,150
0,MUL,EndY,$Y,150
0,MUL,X,$EndX,3
0,MUL,Y,$EndY,3
0,ADD,X,$X,320
0,ADD,Y,$Y,306
0,ADD,EndX,$EndX,320
0,ADD,EndY,$EndY,306
0,ADD,Ang,$Ang,180
0,GasterBlaster,0,$X,$Y,$EndX,$EndY,$Ang,0.5,0,0,5
0,ADD,gt,$gt,$gin
0,JMPNL,Tail,$gin,1.7
0,ADD,gin,$gin,0.015
0,:Tail
0.06666,JMPL,Loop,$gt,190
1,SansHead,BlueEye
0,HeartMaxFallSpeed,750
0,SansBody,HandRight
0,SansSlamDamage,1
0,SET,I,0
0,SET,Direction,0
0,SET,LastDir,2
0,SET,Wait1,0.13333
0,SET,Wait2,0.13333
0,:SlamLoop
0,JMPNE,DirClampA,$Direction,$LastDir
0,SUB,Direction,$Direction,2
0,:DirClampA
0,JMPNL,DirClampB,$Direction,0
0,ADD,Direction,$Direction,4
0,:DirClampB
0,JMPL,Dispatch,$Direction,4
0,SUB,Direction,$Direction,4
0,:Dispatch
0,MUL,Jump,$Direction,2
0,ADD,Jump,$Jump,1
0,JMPREL,$Jump
0,SansBody,HandRight
0,JMPREL,6
0,SansBody,HandDown
0,JMPREL,4
0,SansBody,HandLeft
0,JMPREL,2
0,SansBody,HandUp
$Wait1,SansSlam,$Direction
$Wait2,SET,LastDir,$Direction
0,MOD,Odd,$I,2
0,JMPZ,AfterRand,$Odd
0,:RandDir
0,RND,Direction,4
0,:AfterRand
0,JMPNE,T21,$I,21
0,HeartMaxFallSpeed,480
0,SET,Wait1,0.2
0,SET,Wait2,0.2
0,:T21
0,JMPNE,T25,$I,25
0,SansHead,Default
0,SansSweat,1
0,:T25
0,JMPNE,T33,$I,33
0,SansHead,Tired1
0,SansSweat,2
0,HeartMaxFallSpeed,330
0,SET,Wait1,0.5
0,SET,Wait2,1.1
0,:T33
0,JMPNE,T33b,$I,33
0,JMPE,RandDir,$Direction,1
0,JMPE,RandDir,$Direction,$LastDir
0,:T33b
0,JMPNE,T35,$I,35
0,HeartMaxFallSpeed,240
0,SET,Direction,3
0,:T35
0,JMPNE,T36,$I,36
0,SansHead,Tired2
0,SansSweat,3
0,HeartMaxFallSpeed,60
0,:T36
0,ADD,I,$I,1
0,JMPL,SlamLoop,$I,38
1.5,SansAnimation,Tired
2.4,EndAttack
]==] },
}

return M

end)()

__modules['default_import_file/workspace/sans-fight/lua/fitdata'] = (function()
-- fitdata.lua —— 自动生成（tools/fit-sprites.py），请勿手改。
-- 来源：reference/sprites；exact = 逐像素游程矩形，1:1 还原原图。
-- 坐标：图像像素坐标（左上原点，Y 向下）；颜色 0xAARRGGBB。
-- 用途：烘焙到容器模板 / 离线对照；直接逐帧绘制会吃掉大量控件预算。

local M = {}

M.meta = {
  source = 'reference/sprites',
  fit = 'exact-rle',
}

-- Sans 合成参数：body = 身体容器；head = 头容器；hx/hy = 头的左上角相对身体左上角的像素偏移；sweat = 流汗覆盖层偏移（相对头左上角）。
M.sans_poses = {
  -- hx/hy = SansHead 左上角相对 SansBody 左上角的像素偏移；由原工程 C2 image point 换算：
  --   头原点(0.5,1) 放到 body 的 Head 点(x*W, y*H)，y 从顶边量起 → hy = y*H - 30。
  default = { body = 'sans_body_default', hx = 17, hy = -24 },
  up      = { body = 'sans_body_up',      hx = 14, hy = -2 },
  down    = { body = 'sans_body_down',    hx = 14, hy = 1 },
  left    = { body = 'sans_body_left',    hx = 18, hy = -24, mirror = true },
  right   = { body = 'sans_body_right',   hx = 18, hy = -24 },
}
M.sans_head_default_key = 'sans_head_default'
M.sans_head_blue_key = 'sans_head_blue'
M.blaster_keys = { default = 'blaster_default', fire = { 'blaster_fire_0', 'blaster_fire_2', 'blaster_fire_4' } }

--- 龙骨炮默认（57x44，320 个矩形）
M.blaster_default = { w=57, h=44, rects={
  {x=17,y=1,w=5,h=1,c=0xFF000000},{x=34,y=1,w=1,h=1,c=0xFF000000},{x=15,y=2,w=2,h=1,c=0xFF000000},{x=17,y=2,w=5,h=1,c=0xFFFFFFFF},{x=22,y=2,w=2,h=1,c=0xFF000000},{x=33,y=2,w=1,h=1,c=0xFF000000},{x=34,y=2,w=1,h=1,c=0xFFFFFFFF},{x=35,y=2,w=1,h=1,c=0xFF000000},
  {x=13,y=3,w=2,h=1,c=0xFF000000},{x=15,y=3,w=9,h=1,c=0xFFFFFFFF},{x=24,y=3,w=1,h=1,c=0xFF000000},{x=33,y=3,w=1,h=1,c=0xFF000000},{x=34,y=3,w=1,h=1,c=0xFFFFFFFF},{x=35,y=3,w=4,h=1,c=0xFF000000},{x=10,y=4,w=3,h=1,c=0xFF000000},{x=13,y=4,w=12,h=1,c=0xFFFFFFFF},
  {x=25,y=4,w=4,h=1,c=0xFF000000},{x=34,y=4,w=1,h=1,c=0xFF000000},{x=35,y=4,w=4,h=1,c=0xFFFFFFFF},{x=39,y=4,w=2,h=1,c=0xFF000000},{x=9,y=5,w=1,h=1,c=0xFF000000},{x=10,y=5,w=19,h=1,c=0xFFFFFFFF},{x=29,y=5,w=4,h=1,c=0xFF000000},{x=35,y=5,w=1,h=1,c=0xFF000000},
  {x=36,y=5,w=5,h=1,c=0xFFFFFFFF},{x=41,y=5,w=1,h=1,c=0xFF000000},{x=8,y=6,w=1,h=1,c=0xFF000000},{x=9,y=6,w=24,h=1,c=0xFFFFFFFF},{x=33,y=6,w=4,h=1,c=0xFF000000},{x=37,y=6,w=5,h=1,c=0xFFFFFFFF},{x=42,y=6,w=1,h=1,c=0xFF000000},{x=7,y=7,w=1,h=1,c=0xFF000000},
  {x=8,y=7,w=3,h=1,c=0xFFFFFFFF},{x=11,y=7,w=2,h=1,c=0xFF000000},{x=13,y=7,w=7,h=1,c=0xFFFFFFFF},{x=20,y=7,w=10,h=1,c=0xFF000000},{x=30,y=7,w=13,h=1,c=0xFFFFFFFF},{x=43,y=7,w=1,h=1,c=0xFF000000},{x=6,y=8,w=1,h=1,c=0xFF000000},{x=7,y=8,w=2,h=1,c=0xFFFFFFFF},
  {x=9,y=8,w=2,h=1,c=0xFF000000},{x=12,y=8,w=1,h=1,c=0xFF000000},{x=13,y=8,w=6,h=1,c=0xFFFFFFFF},{x=19,y=8,w=3,h=1,c=0xFF000000},{x=22,y=8,w=3,h=1,c=0xFFFFFFFF},{x=25,y=8,w=10,h=1,c=0xFF000000},{x=35,y=8,w=9,h=1,c=0xFFFFFFFF},{x=44,y=8,w=1,h=1,c=0xFF000000},
  {x=5,y=9,w=1,h=1,c=0xFF000000},{x=6,y=9,w=2,h=1,c=0xFFFFFFFF},{x=8,y=9,w=1,h=1,c=0xFF000000},{x=11,y=9,w=1,h=1,c=0xFF000000},{x=12,y=9,w=6,h=1,c=0xFFFFFFFF},{x=18,y=9,w=1,h=1,c=0xFF000000},{x=19,y=9,w=11,h=1,c=0xFFFFFFFF},{x=30,y=9,w=2,h=1,c=0xFF000000},
  {x=35,y=9,w=2,h=1,c=0xFF000000},{x=37,y=9,w=8,h=1,c=0xFFFFFFFF},{x=45,y=9,w=1,h=1,c=0xFF000000},{x=5,y=10,w=1,h=1,c=0xFF000000},{x=6,y=10,w=1,h=1,c=0xFFFFFFFF},{x=7,y=10,w=1,h=1,c=0xFF000000},{x=10,y=10,w=1,h=1,c=0xFF000000},{x=11,y=10,w=12,h=1,c=0xFFFFFFFF},
  {x=23,y=10,w=5,h=1,c=0xFF000000},{x=28,y=10,w=4,h=1,c=0xFFFFFFFF},{x=32,y=10,w=6,h=1,c=0xFF000000},{x=38,y=10,w=7,h=1,c=0xFFFFFFFF},{x=45,y=10,w=1,h=1,c=0xFF000000},{x=6,y=11,w=1,h=1,c=0xFF000000},{x=9,y=11,w=1,h=1,c=0xFF000000},{x=10,y=11,w=12,h=1,c=0xFFFFFFFF},
  {x=22,y=11,w=1,h=1,c=0xFF000000},{x=26,y=11,w=5,h=1,c=0xFF000000},{x=31,y=11,w=7,h=1,c=0xFFFFFFFF},{x=38,y=11,w=4,h=1,c=0xFF000000},{x=42,y=11,w=4,h=1,c=0xFFFFFFFF},{x=46,y=11,w=1,h=1,c=0xFF000000},{x=9,y=12,w=1,h=1,c=0xFF000000},{x=10,y=12,w=12,h=1,c=0xFFFFFFFF},
  {x=22,y=12,w=1,h=1,c=0xFF000000},{x=25,y=12,w=1,h=1,c=0xFF000000},{x=26,y=12,w=4,h=1,c=0xFFFFFFFF},{x=30,y=12,w=1,h=1,c=0xFF000000},{x=31,y=12,w=5,h=1,c=0xFFFFFFFF},{x=36,y=12,w=2,h=1,c=0xFF000000},{x=42,y=12,w=2,h=1,c=0xFF000000},{x=44,y=12,w=3,h=1,c=0xFFFFFFFF},
  {x=47,y=12,w=1,h=1,c=0xFF000000},{x=8,y=13,w=1,h=1,c=0xFF000000},{x=9,y=13,w=13,h=1,c=0xFFFFFFFF},{x=22,y=13,w=1,h=1,c=0xFF000000},{x=24,y=13,w=1,h=1,c=0xFF000000},{x=25,y=13,w=2,h=1,c=0xFFFFFFFF},{x=27,y=13,w=2,h=1,c=0xFF000000},{x=29,y=13,w=2,h=1,c=0xFFFFFFFF},
  {x=31,y=13,w=1,h=1,c=0xFF000000},{x=32,y=13,w=6,h=1,c=0xFFFFFFFF},{x=38,y=13,w=7,h=1,c=0xFF000000},{x=45,y=13,w=3,h=1,c=0xFFFFFFFF},{x=48,y=13,w=1,h=1,c=0xFF000000},{x=8,y=14,w=1,h=1,c=0xFF000000},{x=9,y=14,w=14,h=1,c=0xFFFFFFFF},{x=23,y=14,w=2,h=1,c=0xFF000000},
  {x=25,y=14,w=2,h=1,c=0xFFFFFFFF},{x=27,y=14,w=3,h=1,c=0xFF000000},{x=30,y=14,w=1,h=1,c=0xFFFFFFFF},{x=31,y=14,w=1,h=1,c=0xFF000000},{x=32,y=14,w=17,h=1,c=0xFFFFFFFF},{x=49,y=14,w=2,h=1,c=0xFF000000},{x=7,y=15,w=1,h=1,c=0xFF000000},{x=8,y=15,w=16,h=1,c=0xFFFFFFFF},
  {x=24,y=15,w=2,h=1,c=0xFF000000},{x=26,y=15,w=5,h=1,c=0xFFFFFFFF},{x=31,y=15,w=1,h=1,c=0xFF000000},{x=32,y=15,w=7,h=1,c=0xFFFFFFFF},{x=39,y=15,w=8,h=1,c=0xFF000000},{x=47,y=15,w=4,h=1,c=0xFFFFFFFF},{x=51,y=15,w=2,h=1,c=0xFF000000},{x=7,y=16,w=1,h=1,c=0xFF000000},
  {x=8,y=16,w=17,h=1,c=0xFFFFFFFF},{x=25,y=16,w=7,h=1,c=0xFF000000},{x=32,y=16,w=10,h=1,c=0xFFFFFFFF},{x=42,y=16,w=1,h=1,c=0xFF000000},{x=47,y=16,w=4,h=1,c=0xFF000000},{x=51,y=16,w=2,h=1,c=0xFFFFFFFF},{x=53,y=16,w=2,h=1,c=0xFF000000},{x=6,y=17,w=1,h=1,c=0xFF000000},
  {x=7,y=17,w=22,h=1,c=0xFFFFFFFF},{x=29,y=17,w=3,h=1,c=0xFF000000},{x=32,y=17,w=9,h=1,c=0xFFFFFFFF},{x=41,y=17,w=1,h=1,c=0xFF000000},{x=47,y=17,w=1,h=1,c=0xFF000000},{x=48,y=17,w=7,h=1,c=0xFFFFFFFF},{x=55,y=17,w=1,h=1,c=0xFF000000},{x=5,y=18,w=1,h=1,c=0xFF000000},
  {x=6,y=18,w=36,h=1,c=0xFFFFFFFF},{x=42,y=18,w=5,h=1,c=0xFF000000},{x=48,y=18,w=4,h=1,c=0xFF000000},{x=52,y=18,w=4,h=1,c=0xFFFFFFFF},{x=4,y=19,w=1,h=1,c=0xFF000000},{x=5,y=19,w=29,h=1,c=0xFFFFFFFF},{x=34,y=19,w=4,h=1,c=0xFF000000},{x=38,y=19,w=9,h=1,c=0xFFFFFFFF},
  {x=47,y=19,w=3,h=1,c=0xFF000000},{x=50,y=19,w=6,h=1,c=0xFFFFFFFF},{x=1,y=20,w=3,h=1,c=0xFF000000},{x=4,y=20,w=28,h=1,c=0xFFFFFFFF},{x=32,y=20,w=2,h=1,c=0xFF000000},{x=38,y=20,w=1,h=1,c=0xFF000000},{x=39,y=20,w=3,h=1,c=0xFFFFFFFF},{x=42,y=20,w=6,h=1,c=0xFF000000},
  {x=48,y=20,w=8,h=1,c=0xFFFFFFFF},{x=1,y=21,w=11,h=1,c=0xFFFFFFFF},{x=12,y=21,w=20,h=1,c=0xFF000000},{x=38,y=21,w=1,h=1,c=0xFF000000},{x=39,y=21,w=2,h=1,c=0xFFFFFFFF},{x=41,y=21,w=1,h=1,c=0xFF000000},{x=47,y=21,w=1,h=1,c=0xFF000000},{x=48,y=21,w=8,h=1,c=0xFFFFFFFF},
  {x=1,y=22,w=11,h=1,c=0xFFFFFFFF},{x=12,y=22,w=20,h=1,c=0xFF000000},{x=38,y=22,w=1,h=1,c=0xFF000000},{x=39,y=22,w=2,h=1,c=0xFFFFFFFF},{x=41,y=22,w=1,h=1,c=0xFF000000},{x=47,y=22,w=1,h=1,c=0xFF000000},{x=48,y=22,w=8,h=1,c=0xFFFFFFFF},{x=1,y=23,w=3,h=1,c=0xFF000000},
  {x=4,y=23,w=28,h=1,c=0xFFFFFFFF},{x=32,y=23,w=2,h=1,c=0xFF000000},{x=38,y=23,w=1,h=1,c=0xFF000000},{x=39,y=23,w=3,h=1,c=0xFFFFFFFF},{x=42,y=23,w=6,h=1,c=0xFF000000},{x=48,y=23,w=8,h=1,c=0xFFFFFFFF},{x=4,y=24,w=1,h=1,c=0xFF000000},{x=5,y=24,w=29,h=1,c=0xFFFFFFFF},
  {x=34,y=24,w=4,h=1,c=0xFF000000},{x=38,y=24,w=9,h=1,c=0xFFFFFFFF},{x=47,y=24,w=3,h=1,c=0xFF000000},{x=50,y=24,w=6,h=1,c=0xFFFFFFFF},{x=5,y=25,w=1,h=1,c=0xFF000000},{x=6,y=25,w=36,h=1,c=0xFFFFFFFF},{x=42,y=25,w=5,h=1,c=0xFF000000},{x=48,y=25,w=4,h=1,c=0xFF000000},
  {x=52,y=25,w=4,h=1,c=0xFFFFFFFF},{x=6,y=26,w=1,h=1,c=0xFF000000},{x=7,y=26,w=22,h=1,c=0xFFFFFFFF},{x=29,y=26,w=3,h=1,c=0xFF000000},{x=32,y=26,w=9,h=1,c=0xFFFFFFFF},{x=41,y=26,w=1,h=1,c=0xFF000000},{x=47,y=26,w=1,h=1,c=0xFF000000},{x=48,y=26,w=7,h=1,c=0xFFFFFFFF},
  {x=55,y=26,w=1,h=1,c=0xFF000000},{x=7,y=27,w=1,h=1,c=0xFF000000},{x=8,y=27,w=17,h=1,c=0xFFFFFFFF},{x=25,y=27,w=7,h=1,c=0xFF000000},{x=32,y=27,w=10,h=1,c=0xFFFFFFFF},{x=42,y=27,w=1,h=1,c=0xFF000000},{x=47,y=27,w=4,h=1,c=0xFF000000},{x=51,y=27,w=2,h=1,c=0xFFFFFFFF},
  {x=53,y=27,w=2,h=1,c=0xFF000000},{x=7,y=28,w=1,h=1,c=0xFF000000},{x=8,y=28,w=16,h=1,c=0xFFFFFFFF},{x=24,y=28,w=2,h=1,c=0xFF000000},{x=26,y=28,w=5,h=1,c=0xFFFFFFFF},{x=31,y=28,w=1,h=1,c=0xFF000000},{x=32,y=28,w=7,h=1,c=0xFFFFFFFF},{x=39,y=28,w=8,h=1,c=0xFF000000},
  {x=47,y=28,w=4,h=1,c=0xFFFFFFFF},{x=51,y=28,w=2,h=1,c=0xFF000000},{x=8,y=29,w=1,h=1,c=0xFF000000},{x=9,y=29,w=14,h=1,c=0xFFFFFFFF},{x=23,y=29,w=2,h=1,c=0xFF000000},{x=25,y=29,w=2,h=1,c=0xFFFFFFFF},{x=27,y=29,w=3,h=1,c=0xFF000000},{x=30,y=29,w=1,h=1,c=0xFFFFFFFF},
  {x=31,y=29,w=1,h=1,c=0xFF000000},{x=32,y=29,w=17,h=1,c=0xFFFFFFFF},{x=49,y=29,w=2,h=1,c=0xFF000000},{x=8,y=30,w=1,h=1,c=0xFF000000},{x=9,y=30,w=13,h=1,c=0xFFFFFFFF},{x=22,y=30,w=1,h=1,c=0xFF000000},{x=24,y=30,w=1,h=1,c=0xFF000000},{x=25,y=30,w=2,h=1,c=0xFFFFFFFF},
  {x=27,y=30,w=2,h=1,c=0xFF000000},{x=29,y=30,w=2,h=1,c=0xFFFFFFFF},{x=31,y=30,w=1,h=1,c=0xFF000000},{x=32,y=30,w=6,h=1,c=0xFFFFFFFF},{x=38,y=30,w=7,h=1,c=0xFF000000},{x=45,y=30,w=3,h=1,c=0xFFFFFFFF},{x=48,y=30,w=1,h=1,c=0xFF000000},{x=9,y=31,w=1,h=1,c=0xFF000000},
  {x=10,y=31,w=12,h=1,c=0xFFFFFFFF},{x=22,y=31,w=1,h=1,c=0xFF000000},{x=25,y=31,w=1,h=1,c=0xFF000000},{x=26,y=31,w=4,h=1,c=0xFFFFFFFF},{x=30,y=31,w=1,h=1,c=0xFF000000},{x=31,y=31,w=5,h=1,c=0xFFFFFFFF},{x=36,y=31,w=2,h=1,c=0xFF000000},{x=42,y=31,w=2,h=1,c=0xFF000000},
  {x=44,y=31,w=3,h=1,c=0xFFFFFFFF},{x=47,y=31,w=1,h=1,c=0xFF000000},{x=6,y=32,w=1,h=1,c=0xFF000000},{x=9,y=32,w=1,h=1,c=0xFF000000},{x=10,y=32,w=12,h=1,c=0xFFFFFFFF},{x=22,y=32,w=1,h=1,c=0xFF000000},{x=26,y=32,w=5,h=1,c=0xFF000000},{x=31,y=32,w=7,h=1,c=0xFFFFFFFF},
  {x=38,y=32,w=4,h=1,c=0xFF000000},{x=42,y=32,w=4,h=1,c=0xFFFFFFFF},{x=46,y=32,w=1,h=1,c=0xFF000000},{x=5,y=33,w=1,h=1,c=0xFF000000},{x=6,y=33,w=1,h=1,c=0xFFFFFFFF},{x=7,y=33,w=1,h=1,c=0xFF000000},{x=10,y=33,w=1,h=1,c=0xFF000000},{x=11,y=33,w=12,h=1,c=0xFFFFFFFF},
  {x=23,y=33,w=5,h=1,c=0xFF000000},{x=28,y=33,w=4,h=1,c=0xFFFFFFFF},{x=32,y=33,w=6,h=1,c=0xFF000000},{x=38,y=33,w=7,h=1,c=0xFFFFFFFF},{x=45,y=33,w=1,h=1,c=0xFF000000},{x=5,y=34,w=1,h=1,c=0xFF000000},{x=6,y=34,w=2,h=1,c=0xFFFFFFFF},{x=8,y=34,w=1,h=1,c=0xFF000000},
  {x=11,y=34,w=1,h=1,c=0xFF000000},{x=12,y=34,w=6,h=1,c=0xFFFFFFFF},{x=18,y=34,w=1,h=1,c=0xFF000000},{x=19,y=34,w=11,h=1,c=0xFFFFFFFF},{x=30,y=34,w=2,h=1,c=0xFF000000},{x=35,y=34,w=2,h=1,c=0xFF000000},{x=37,y=34,w=8,h=1,c=0xFFFFFFFF},{x=45,y=34,w=1,h=1,c=0xFF000000},
  {x=6,y=35,w=1,h=1,c=0xFF000000},{x=7,y=35,w=2,h=1,c=0xFFFFFFFF},{x=9,y=35,w=2,h=1,c=0xFF000000},{x=12,y=35,w=1,h=1,c=0xFF000000},{x=13,y=35,w=6,h=1,c=0xFFFFFFFF},{x=19,y=35,w=3,h=1,c=0xFF000000},{x=22,y=35,w=3,h=1,c=0xFFFFFFFF},{x=25,y=35,w=10,h=1,c=0xFF000000},
  {x=35,y=35,w=9,h=1,c=0xFFFFFFFF},{x=44,y=35,w=1,h=1,c=0xFF000000},{x=7,y=36,w=1,h=1,c=0xFF000000},{x=8,y=36,w=3,h=1,c=0xFFFFFFFF},{x=11,y=36,w=2,h=1,c=0xFF000000},{x=13,y=36,w=7,h=1,c=0xFFFFFFFF},{x=20,y=36,w=10,h=1,c=0xFF000000},{x=30,y=36,w=13,h=1,c=0xFFFFFFFF},
  {x=43,y=36,w=1,h=1,c=0xFF000000},{x=8,y=37,w=1,h=1,c=0xFF000000},{x=9,y=37,w=24,h=1,c=0xFFFFFFFF},{x=33,y=37,w=4,h=1,c=0xFF000000},{x=37,y=37,w=5,h=1,c=0xFFFFFFFF},{x=42,y=37,w=1,h=1,c=0xFF000000},{x=9,y=38,w=1,h=1,c=0xFF000000},{x=10,y=38,w=19,h=1,c=0xFFFFFFFF},
  {x=29,y=38,w=4,h=1,c=0xFF000000},{x=35,y=38,w=1,h=1,c=0xFF000000},{x=36,y=38,w=5,h=1,c=0xFFFFFFFF},{x=41,y=38,w=1,h=1,c=0xFF000000},{x=10,y=39,w=3,h=1,c=0xFF000000},{x=13,y=39,w=12,h=1,c=0xFFFFFFFF},{x=25,y=39,w=4,h=1,c=0xFF000000},{x=34,y=39,w=1,h=1,c=0xFF000000},
  {x=35,y=39,w=4,h=1,c=0xFFFFFFFF},{x=39,y=39,w=2,h=1,c=0xFF000000},{x=13,y=40,w=2,h=1,c=0xFF000000},{x=15,y=40,w=9,h=1,c=0xFFFFFFFF},{x=24,y=40,w=1,h=1,c=0xFF000000},{x=33,y=40,w=1,h=1,c=0xFF000000},{x=34,y=40,w=1,h=1,c=0xFFFFFFFF},{x=35,y=40,w=4,h=1,c=0xFF000000},
  {x=15,y=41,w=2,h=1,c=0xFF000000},{x=17,y=41,w=5,h=1,c=0xFFFFFFFF},{x=22,y=41,w=2,h=1,c=0xFF000000},{x=33,y=41,w=1,h=1,c=0xFF000000},{x=34,y=41,w=1,h=1,c=0xFFFFFFFF},{x=35,y=41,w=1,h=1,c=0xFF000000},{x=17,y=42,w=5,h=1,c=0xFF000000},{x=34,y=42,w=1,h=1,c=0xFF000000},
}}

--- 龙骨炮开火 0（57x44，306 个矩形）
M.blaster_fire_0 = { w=57, h=44, rects={
  {x=17,y=2,w=5,h=1,c=0xFF000000},{x=34,y=2,w=1,h=1,c=0xFF000000},{x=15,y=3,w=2,h=1,c=0xFF000000},{x=17,y=3,w=5,h=1,c=0xFFFFFFFF},{x=22,y=3,w=2,h=1,c=0xFF000000},{x=33,y=3,w=1,h=1,c=0xFF000000},{x=34,y=3,w=1,h=1,c=0xFFFFFFFF},{x=35,y=3,w=1,h=1,c=0xFF000000},
  {x=13,y=4,w=2,h=1,c=0xFF000000},{x=15,y=4,w=9,h=1,c=0xFFFFFFFF},{x=24,y=4,w=1,h=1,c=0xFF000000},{x=33,y=4,w=1,h=1,c=0xFF000000},{x=34,y=4,w=1,h=1,c=0xFFFFFFFF},{x=35,y=4,w=4,h=1,c=0xFF000000},{x=10,y=5,w=3,h=1,c=0xFF000000},{x=13,y=5,w=12,h=1,c=0xFFFFFFFF},
  {x=25,y=5,w=4,h=1,c=0xFF000000},{x=34,y=5,w=1,h=1,c=0xFF000000},{x=35,y=5,w=4,h=1,c=0xFFFFFFFF},{x=39,y=5,w=2,h=1,c=0xFF000000},{x=9,y=6,w=1,h=1,c=0xFF000000},{x=10,y=6,w=19,h=1,c=0xFFFFFFFF},{x=29,y=6,w=4,h=1,c=0xFF000000},{x=35,y=6,w=1,h=1,c=0xFF000000},
  {x=36,y=6,w=5,h=1,c=0xFFFFFFFF},{x=41,y=6,w=1,h=1,c=0xFF000000},{x=8,y=7,w=1,h=1,c=0xFF000000},{x=9,y=7,w=24,h=1,c=0xFFFFFFFF},{x=33,y=7,w=4,h=1,c=0xFF000000},{x=37,y=7,w=5,h=1,c=0xFFFFFFFF},{x=42,y=7,w=1,h=1,c=0xFF000000},{x=7,y=8,w=1,h=1,c=0xFF000000},
  {x=8,y=8,w=3,h=1,c=0xFFFFFFFF},{x=11,y=8,w=2,h=1,c=0xFF000000},{x=13,y=8,w=7,h=1,c=0xFFFFFFFF},{x=20,y=8,w=10,h=1,c=0xFF000000},{x=30,y=8,w=13,h=1,c=0xFFFFFFFF},{x=43,y=8,w=1,h=1,c=0xFF000000},{x=6,y=9,w=1,h=1,c=0xFF000000},{x=7,y=9,w=2,h=1,c=0xFFFFFFFF},
  {x=9,y=9,w=2,h=1,c=0xFF000000},{x=12,y=9,w=1,h=1,c=0xFF000000},{x=13,y=9,w=6,h=1,c=0xFFFFFFFF},{x=19,y=9,w=3,h=1,c=0xFF000000},{x=22,y=9,w=3,h=1,c=0xFFFFFFFF},{x=25,y=9,w=10,h=1,c=0xFF000000},{x=35,y=9,w=9,h=1,c=0xFFFFFFFF},{x=44,y=9,w=1,h=1,c=0xFF000000},
  {x=5,y=10,w=1,h=1,c=0xFF000000},{x=6,y=10,w=2,h=1,c=0xFFFFFFFF},{x=8,y=10,w=1,h=1,c=0xFF000000},{x=11,y=10,w=1,h=1,c=0xFF000000},{x=12,y=10,w=6,h=1,c=0xFFFFFFFF},{x=18,y=10,w=1,h=1,c=0xFF000000},{x=19,y=10,w=11,h=1,c=0xFFFFFFFF},{x=30,y=10,w=2,h=1,c=0xFF000000},
  {x=35,y=10,w=2,h=1,c=0xFF000000},{x=37,y=10,w=8,h=1,c=0xFFFFFFFF},{x=5,y=11,w=1,h=1,c=0xFF000000},{x=6,y=11,w=1,h=1,c=0xFFFFFFFF},{x=7,y=11,w=1,h=1,c=0xFF000000},{x=10,y=11,w=1,h=1,c=0xFF000000},{x=11,y=11,w=12,h=1,c=0xFFFFFFFF},{x=23,y=11,w=5,h=1,c=0xFF000000},
  {x=28,y=11,w=4,h=1,c=0xFFFFFFFF},{x=32,y=11,w=6,h=1,c=0xFF000000},{x=38,y=11,w=7,h=1,c=0xFFFFFFFF},{x=45,y=11,w=1,h=1,c=0xFF000000},{x=6,y=12,w=1,h=1,c=0xFF000000},{x=9,y=12,w=1,h=1,c=0xFF000000},{x=10,y=12,w=12,h=1,c=0xFFFFFFFF},{x=22,y=12,w=1,h=1,c=0xFF000000},
  {x=26,y=12,w=5,h=1,c=0xFF000000},{x=31,y=12,w=7,h=1,c=0xFFFFFFFF},{x=38,y=12,w=4,h=1,c=0xFF000000},{x=42,y=12,w=3,h=1,c=0xFFFFFFFF},{x=45,y=12,w=1,h=1,c=0xFF000000},{x=9,y=13,w=1,h=1,c=0xFF000000},{x=10,y=13,w=12,h=1,c=0xFFFFFFFF},{x=22,y=13,w=1,h=1,c=0xFF000000},
  {x=25,y=13,w=1,h=1,c=0xFF000000},{x=26,y=13,w=4,h=1,c=0xFFFFFFFF},{x=30,y=13,w=1,h=1,c=0xFF000000},{x=31,y=13,w=5,h=1,c=0xFFFFFFFF},{x=36,y=13,w=2,h=1,c=0xFF000000},{x=42,y=13,w=2,h=1,c=0xFF000000},{x=44,y=13,w=2,h=1,c=0xFFFFFFFF},{x=46,y=13,w=1,h=1,c=0xFF000000},
  {x=8,y=14,w=1,h=1,c=0xFF000000},{x=9,y=14,w=13,h=1,c=0xFFFFFFFF},{x=22,y=14,w=3,h=1,c=0xFF000000},{x=25,y=14,w=2,h=1,c=0xFFFFFFFF},{x=27,y=14,w=2,h=1,c=0xFF000000},{x=29,y=14,w=2,h=1,c=0xFFFFFFFF},{x=31,y=14,w=1,h=1,c=0xFF000000},{x=32,y=14,w=6,h=1,c=0xFFFFFFFF},
  {x=38,y=14,w=7,h=1,c=0xFF000000},{x=45,y=14,w=2,h=1,c=0xFFFFFFFF},{x=47,y=14,w=2,h=1,c=0xFF000000},{x=7,y=15,w=1,h=1,c=0xFF000000},{x=8,y=15,w=16,h=1,c=0xFFFFFFFF},{x=24,y=15,w=2,h=1,c=0xFF000000},{x=26,y=15,w=5,h=1,c=0xFFFFFFFF},{x=31,y=15,w=1,h=1,c=0xFF000000},
  {x=32,y=15,w=7,h=1,c=0xFFFFFFFF},{x=39,y=15,w=6,h=1,c=0xFF000000},{x=45,y=15,w=4,h=1,c=0xFFFFFFFF},{x=49,y=15,w=2,h=1,c=0xFF000000},{x=7,y=16,w=1,h=1,c=0xFF000000},{x=8,y=16,w=17,h=1,c=0xFFFFFFFF},{x=25,y=16,w=7,h=1,c=0xFF000000},{x=32,y=16,w=10,h=1,c=0xFFFFFFFF},
  {x=42,y=16,w=1,h=1,c=0xFF000000},{x=45,y=16,w=2,h=1,c=0xFF000000},{x=47,y=16,w=4,h=1,c=0xFFFFFFFF},{x=51,y=16,w=2,h=1,c=0xFF000000},{x=6,y=17,w=1,h=1,c=0xFF000000},{x=7,y=17,w=22,h=1,c=0xFFFFFFFF},{x=29,y=17,w=3,h=1,c=0xFF000000},{x=32,y=17,w=9,h=1,c=0xFFFFFFFF},
  {x=41,y=17,w=1,h=1,c=0xFF000000},{x=47,y=17,w=4,h=1,c=0xFF000000},{x=51,y=17,w=2,h=1,c=0xFFFFFFFF},{x=53,y=17,w=2,h=1,c=0xFF000000},{x=5,y=18,w=1,h=1,c=0xFF000000},{x=6,y=18,w=36,h=1,c=0xFFFFFFFF},{x=42,y=18,w=3,h=1,c=0xFF000000},{x=47,y=18,w=1,h=1,c=0xFF000000},
  {x=48,y=18,w=7,h=1,c=0xFFFFFFFF},{x=55,y=18,w=1,h=1,c=0xFF000000},{x=4,y=19,w=1,h=1,c=0xFF000000},{x=5,y=19,w=29,h=1,c=0xFFFFFFFF},{x=34,y=19,w=4,h=1,c=0xFF000000},{x=38,y=19,w=7,h=1,c=0xFFFFFFFF},{x=45,y=19,w=2,h=1,c=0xFF000000},{x=48,y=19,w=4,h=1,c=0xFF000000},
  {x=52,y=19,w=4,h=1,c=0xFFFFFFFF},{x=1,y=20,w=3,h=1,c=0xFF000000},{x=4,y=20,w=28,h=1,c=0xFFFFFFFF},{x=32,y=20,w=2,h=1,c=0xFF000000},{x=38,y=20,w=1,h=1,c=0xFF000000},{x=39,y=20,w=3,h=1,c=0xFFFFFFFF},{x=42,y=20,w=3,h=1,c=0xFF000000},{x=45,y=20,w=2,h=1,c=0xFFFFFFFF},
  {x=47,y=20,w=3,h=1,c=0xFF000000},{x=50,y=20,w=6,h=1,c=0xFFFFFFFF},{x=1,y=21,w=11,h=1,c=0xFFFFFFFF},{x=12,y=21,w=20,h=1,c=0xFF000000},{x=38,y=21,w=1,h=1,c=0xFF000000},{x=39,y=21,w=2,h=1,c=0xFFFFFFFF},{x=41,y=21,w=1,h=1,c=0xFF000000},{x=45,y=21,w=3,h=1,c=0xFF000000},
  {x=48,y=21,w=8,h=1,c=0xFFFFFFFF},{x=1,y=22,w=11,h=1,c=0xFFFFFFFF},{x=12,y=22,w=20,h=1,c=0xFF000000},{x=38,y=22,w=1,h=1,c=0xFF000000},{x=39,y=22,w=2,h=1,c=0xFFFFFFFF},{x=41,y=22,w=1,h=1,c=0xFF000000},{x=46,y=22,w=2,h=1,c=0xFF000000},{x=48,y=22,w=8,h=1,c=0xFFFFFFFF},
  {x=1,y=23,w=3,h=1,c=0xFF000000},{x=4,y=23,w=28,h=1,c=0xFFFFFFFF},{x=32,y=23,w=2,h=1,c=0xFF000000},{x=38,y=23,w=1,h=1,c=0xFF000000},{x=39,y=23,w=3,h=1,c=0xFFFFFFFF},{x=42,y=23,w=4,h=1,c=0xFF000000},{x=46,y=23,w=1,h=1,c=0xFFFFFFFF},{x=47,y=23,w=3,h=1,c=0xFF000000},
  {x=50,y=23,w=6,h=1,c=0xFFFFFFFF},{x=4,y=24,w=1,h=1,c=0xFF000000},{x=5,y=24,w=29,h=1,c=0xFFFFFFFF},{x=34,y=24,w=4,h=1,c=0xFF000000},{x=38,y=24,w=8,h=1,c=0xFFFFFFFF},{x=46,y=24,w=1,h=1,c=0xFF000000},{x=48,y=24,w=4,h=1,c=0xFF000000},{x=52,y=24,w=4,h=1,c=0xFFFFFFFF},
  {x=5,y=25,w=1,h=1,c=0xFF000000},{x=6,y=25,w=36,h=1,c=0xFFFFFFFF},{x=42,y=25,w=4,h=1,c=0xFF000000},{x=47,y=25,w=1,h=1,c=0xFF000000},{x=48,y=25,w=7,h=1,c=0xFFFFFFFF},{x=55,y=25,w=1,h=1,c=0xFF000000},{x=6,y=26,w=1,h=1,c=0xFF000000},{x=7,y=26,w=22,h=1,c=0xFFFFFFFF},
  {x=29,y=26,w=3,h=1,c=0xFF000000},{x=32,y=26,w=9,h=1,c=0xFFFFFFFF},{x=41,y=26,w=1,h=1,c=0xFF000000},{x=47,y=26,w=4,h=1,c=0xFF000000},{x=51,y=26,w=2,h=1,c=0xFFFFFFFF},{x=53,y=26,w=2,h=1,c=0xFF000000},{x=7,y=27,w=1,h=1,c=0xFF000000},{x=8,y=27,w=17,h=1,c=0xFFFFFFFF},
  {x=25,y=27,w=7,h=1,c=0xFF000000},{x=32,y=27,w=10,h=1,c=0xFFFFFFFF},{x=42,y=27,w=1,h=1,c=0xFF000000},{x=46,y=27,w=1,h=1,c=0xFF000000},{x=47,y=27,w=4,h=1,c=0xFFFFFFFF},{x=51,y=27,w=2,h=1,c=0xFF000000},{x=7,y=28,w=1,h=1,c=0xFF000000},{x=8,y=28,w=16,h=1,c=0xFFFFFFFF},
  {x=24,y=28,w=2,h=1,c=0xFF000000},{x=26,y=28,w=5,h=1,c=0xFFFFFFFF},{x=31,y=28,w=1,h=1,c=0xFF000000},{x=32,y=28,w=7,h=1,c=0xFFFFFFFF},{x=39,y=28,w=7,h=1,c=0xFF000000},{x=46,y=28,w=3,h=1,c=0xFFFFFFFF},{x=49,y=28,w=2,h=1,c=0xFF000000},{x=8,y=29,w=1,h=1,c=0xFF000000},
  {x=9,y=29,w=13,h=1,c=0xFFFFFFFF},{x=22,y=29,w=3,h=1,c=0xFF000000},{x=25,y=29,w=2,h=1,c=0xFFFFFFFF},{x=27,y=29,w=2,h=1,c=0xFF000000},{x=29,y=29,w=2,h=1,c=0xFFFFFFFF},{x=31,y=29,w=1,h=1,c=0xFF000000},{x=32,y=29,w=6,h=1,c=0xFFFFFFFF},{x=38,y=29,w=7,h=1,c=0xFF000000},
  {x=45,y=29,w=2,h=1,c=0xFFFFFFFF},{x=47,y=29,w=2,h=1,c=0xFF000000},{x=9,y=30,w=1,h=1,c=0xFF000000},{x=10,y=30,w=12,h=1,c=0xFFFFFFFF},{x=22,y=30,w=1,h=1,c=0xFF000000},{x=25,y=30,w=1,h=1,c=0xFF000000},{x=26,y=30,w=4,h=1,c=0xFFFFFFFF},{x=30,y=30,w=1,h=1,c=0xFF000000},
  {x=31,y=30,w=5,h=1,c=0xFFFFFFFF},{x=36,y=30,w=2,h=1,c=0xFF000000},{x=42,y=30,w=2,h=1,c=0xFF000000},{x=44,y=30,w=2,h=1,c=0xFFFFFFFF},{x=46,y=30,w=1,h=1,c=0xFF000000},{x=6,y=31,w=1,h=1,c=0xFF000000},{x=9,y=31,w=1,h=1,c=0xFF000000},{x=10,y=31,w=12,h=1,c=0xFFFFFFFF},
  {x=22,y=31,w=1,h=1,c=0xFF000000},{x=26,y=31,w=5,h=1,c=0xFF000000},{x=31,y=31,w=7,h=1,c=0xFFFFFFFF},{x=38,y=31,w=4,h=1,c=0xFF000000},{x=42,y=31,w=4,h=1,c=0xFFFFFFFF},{x=5,y=32,w=1,h=1,c=0xFF000000},{x=6,y=32,w=1,h=1,c=0xFFFFFFFF},{x=7,y=32,w=1,h=1,c=0xFF000000},
  {x=10,y=32,w=1,h=1,c=0xFF000000},{x=11,y=32,w=12,h=1,c=0xFFFFFFFF},{x=23,y=32,w=5,h=1,c=0xFF000000},{x=28,y=32,w=4,h=1,c=0xFFFFFFFF},{x=32,y=32,w=6,h=1,c=0xFF000000},{x=38,y=32,w=7,h=1,c=0xFFFFFFFF},{x=45,y=32,w=1,h=1,c=0xFF000000},{x=5,y=33,w=1,h=1,c=0xFF000000},
  {x=6,y=33,w=2,h=1,c=0xFFFFFFFF},{x=8,y=33,w=1,h=1,c=0xFF000000},{x=11,y=33,w=1,h=1,c=0xFF000000},{x=12,y=33,w=6,h=1,c=0xFFFFFFFF},{x=18,y=33,w=1,h=1,c=0xFF000000},{x=19,y=33,w=11,h=1,c=0xFFFFFFFF},{x=30,y=33,w=2,h=1,c=0xFF000000},{x=35,y=33,w=2,h=1,c=0xFF000000},
  {x=37,y=33,w=8,h=1,c=0xFFFFFFFF},{x=45,y=33,w=1,h=1,c=0xFF000000},{x=6,y=34,w=1,h=1,c=0xFF000000},{x=7,y=34,w=2,h=1,c=0xFFFFFFFF},{x=9,y=34,w=2,h=1,c=0xFF000000},{x=12,y=34,w=1,h=1,c=0xFF000000},{x=13,y=34,w=6,h=1,c=0xFFFFFFFF},{x=19,y=34,w=3,h=1,c=0xFF000000},
  {x=22,y=34,w=3,h=1,c=0xFFFFFFFF},{x=25,y=34,w=10,h=1,c=0xFF000000},{x=35,y=34,w=9,h=1,c=0xFFFFFFFF},{x=44,y=34,w=1,h=1,c=0xFF000000},{x=7,y=35,w=1,h=1,c=0xFF000000},{x=8,y=35,w=3,h=1,c=0xFFFFFFFF},{x=11,y=35,w=2,h=1,c=0xFF000000},{x=13,y=35,w=7,h=1,c=0xFFFFFFFF},
  {x=20,y=35,w=10,h=1,c=0xFF000000},{x=30,y=35,w=13,h=1,c=0xFFFFFFFF},{x=43,y=35,w=1,h=1,c=0xFF000000},{x=8,y=36,w=1,h=1,c=0xFF000000},{x=9,y=36,w=24,h=1,c=0xFFFFFFFF},{x=33,y=36,w=4,h=1,c=0xFF000000},{x=37,y=36,w=5,h=1,c=0xFFFFFFFF},{x=42,y=36,w=1,h=1,c=0xFF000000},
  {x=9,y=37,w=1,h=1,c=0xFF000000},{x=10,y=37,w=19,h=1,c=0xFFFFFFFF},{x=29,y=37,w=4,h=1,c=0xFF000000},{x=35,y=37,w=1,h=1,c=0xFF000000},{x=36,y=37,w=5,h=1,c=0xFFFFFFFF},{x=41,y=37,w=1,h=1,c=0xFF000000},{x=10,y=38,w=3,h=1,c=0xFF000000},{x=13,y=38,w=12,h=1,c=0xFFFFFFFF},
  {x=25,y=38,w=4,h=1,c=0xFF000000},{x=34,y=38,w=1,h=1,c=0xFF000000},{x=35,y=38,w=4,h=1,c=0xFFFFFFFF},{x=39,y=38,w=2,h=1,c=0xFF000000},{x=13,y=39,w=2,h=1,c=0xFF000000},{x=15,y=39,w=9,h=1,c=0xFFFFFFFF},{x=24,y=39,w=1,h=1,c=0xFF000000},{x=33,y=39,w=1,h=1,c=0xFF000000},
  {x=34,y=39,w=1,h=1,c=0xFFFFFFFF},{x=35,y=39,w=4,h=1,c=0xFF000000},{x=15,y=40,w=2,h=1,c=0xFF000000},{x=17,y=40,w=5,h=1,c=0xFFFFFFFF},{x=22,y=40,w=2,h=1,c=0xFF000000},{x=33,y=40,w=1,h=1,c=0xFF000000},{x=34,y=40,w=1,h=1,c=0xFFFFFFFF},{x=35,y=40,w=1,h=1,c=0xFF000000},
  {x=17,y=41,w=5,h=1,c=0xFF000000},{x=34,y=41,w=1,h=1,c=0xFF000000},
}}

--- 龙骨炮开火 2（57x44，316 个矩形）
M.blaster_fire_2 = { w=57, h=44, rects={
  {x=15,y=1,w=2,h=1,c=0xFF000000},{x=17,y=1,w=5,h=1,c=0xFFFFFFFF},{x=22,y=1,w=2,h=1,c=0xFF000000},{x=33,y=1,w=1,h=1,c=0xFF000000},{x=34,y=1,w=1,h=1,c=0xFFFFFFFF},{x=35,y=1,w=1,h=1,c=0xFF000000},{x=13,y=2,w=2,h=1,c=0xFF000000},{x=15,y=2,w=9,h=1,c=0xFFFFFFFF},
  {x=24,y=2,w=1,h=1,c=0xFF000000},{x=33,y=2,w=1,h=1,c=0xFF000000},{x=34,y=2,w=1,h=1,c=0xFFFFFFFF},{x=35,y=2,w=4,h=1,c=0xFF000000},{x=10,y=3,w=3,h=1,c=0xFF000000},{x=13,y=3,w=12,h=1,c=0xFFFFFFFF},{x=25,y=3,w=4,h=1,c=0xFF000000},{x=34,y=3,w=1,h=1,c=0xFF000000},
  {x=35,y=3,w=4,h=1,c=0xFFFFFFFF},{x=39,y=3,w=2,h=1,c=0xFF000000},{x=9,y=4,w=1,h=1,c=0xFF000000},{x=10,y=4,w=19,h=1,c=0xFFFFFFFF},{x=29,y=4,w=4,h=1,c=0xFF000000},{x=35,y=4,w=1,h=1,c=0xFF000000},{x=36,y=4,w=5,h=1,c=0xFFFFFFFF},{x=41,y=4,w=1,h=1,c=0xFF000000},
  {x=8,y=5,w=1,h=1,c=0xFF000000},{x=9,y=5,w=24,h=1,c=0xFFFFFFFF},{x=33,y=5,w=4,h=1,c=0xFF000000},{x=37,y=5,w=5,h=1,c=0xFFFFFFFF},{x=42,y=5,w=1,h=1,c=0xFF000000},{x=48,y=5,w=1,h=1,c=0xFF000000},{x=7,y=6,w=1,h=1,c=0xFF000000},{x=8,y=6,w=3,h=1,c=0xFFFFFFFF},
  {x=11,y=6,w=2,h=1,c=0xFF000000},{x=13,y=6,w=7,h=1,c=0xFFFFFFFF},{x=20,y=6,w=10,h=1,c=0xFF000000},{x=30,y=6,w=13,h=1,c=0xFFFFFFFF},{x=43,y=6,w=1,h=1,c=0xFF000000},{x=47,y=6,w=1,h=1,c=0xFF000000},{x=48,y=6,w=1,h=1,c=0xFFFFFFFF},{x=49,y=6,w=2,h=1,c=0xFF000000},
  {x=6,y=7,w=1,h=1,c=0xFF000000},{x=7,y=7,w=2,h=1,c=0xFFFFFFFF},{x=9,y=7,w=2,h=1,c=0xFF000000},{x=12,y=7,w=1,h=1,c=0xFF000000},{x=13,y=7,w=6,h=1,c=0xFFFFFFFF},{x=19,y=7,w=3,h=1,c=0xFF000000},{x=22,y=7,w=3,h=1,c=0xFFFFFFFF},{x=25,y=7,w=10,h=1,c=0xFF000000},
  {x=35,y=7,w=9,h=1,c=0xFFFFFFFF},{x=44,y=7,w=1,h=1,c=0xFF000000},{x=47,y=7,w=1,h=1,c=0xFF000000},{x=48,y=7,w=3,h=1,c=0xFFFFFFFF},{x=51,y=7,w=2,h=1,c=0xFF000000},{x=5,y=8,w=1,h=1,c=0xFF000000},{x=6,y=8,w=2,h=1,c=0xFFFFFFFF},{x=8,y=8,w=1,h=1,c=0xFF000000},
  {x=11,y=8,w=1,h=1,c=0xFF000000},{x=12,y=8,w=6,h=1,c=0xFFFFFFFF},{x=18,y=8,w=1,h=1,c=0xFF000000},{x=19,y=8,w=11,h=1,c=0xFFFFFFFF},{x=30,y=8,w=2,h=1,c=0xFF000000},{x=35,y=8,w=2,h=1,c=0xFF000000},{x=37,y=8,w=8,h=1,c=0xFFFFFFFF},{x=45,y=8,w=1,h=1,c=0xFF000000},
  {x=48,y=8,w=3,h=1,c=0xFF000000},{x=51,y=8,w=2,h=1,c=0xFFFFFFFF},{x=53,y=8,w=2,h=1,c=0xFF000000},{x=5,y=9,w=1,h=1,c=0xFF000000},{x=6,y=9,w=1,h=1,c=0xFFFFFFFF},{x=7,y=9,w=1,h=1,c=0xFF000000},{x=10,y=9,w=1,h=1,c=0xFF000000},{x=11,y=9,w=12,h=1,c=0xFFFFFFFF},
  {x=23,y=9,w=5,h=1,c=0xFF000000},{x=28,y=9,w=4,h=1,c=0xFFFFFFFF},{x=32,y=9,w=6,h=1,c=0xFF000000},{x=38,y=9,w=8,h=1,c=0xFFFFFFFF},{x=46,y=9,w=2,h=1,c=0xFF000000},{x=48,y=9,w=7,h=1,c=0xFFFFFFFF},{x=55,y=9,w=1,h=1,c=0xFF000000},{x=6,y=10,w=1,h=1,c=0xFF000000},
  {x=9,y=10,w=1,h=1,c=0xFF000000},{x=10,y=10,w=12,h=1,c=0xFFFFFFFF},{x=22,y=10,w=1,h=1,c=0xFF000000},{x=26,y=10,w=5,h=1,c=0xFF000000},{x=31,y=10,w=7,h=1,c=0xFFFFFFFF},{x=38,y=10,w=4,h=1,c=0xFF000000},{x=42,y=10,w=5,h=1,c=0xFFFFFFFF},{x=47,y=10,w=5,h=1,c=0xFF000000},
  {x=52,y=10,w=4,h=1,c=0xFFFFFFFF},{x=9,y=11,w=1,h=1,c=0xFF000000},{x=10,y=11,w=12,h=1,c=0xFFFFFFFF},{x=22,y=11,w=1,h=1,c=0xFF000000},{x=25,y=11,w=1,h=1,c=0xFF000000},{x=26,y=11,w=4,h=1,c=0xFFFFFFFF},{x=30,y=11,w=1,h=1,c=0xFF000000},{x=31,y=11,w=5,h=1,c=0xFFFFFFFF},
  {x=36,y=11,w=2,h=1,c=0xFF000000},{x=42,y=11,w=2,h=1,c=0xFF000000},{x=44,y=11,w=4,h=1,c=0xFFFFFFFF},{x=48,y=11,w=2,h=1,c=0xFF000000},{x=50,y=11,w=6,h=1,c=0xFFFFFFFF},{x=8,y=12,w=1,h=1,c=0xFF000000},{x=9,y=12,w=13,h=1,c=0xFFFFFFFF},{x=22,y=12,w=1,h=1,c=0xFF000000},
  {x=24,y=12,w=1,h=1,c=0xFF000000},{x=25,y=12,w=6,h=1,c=0xFFFFFFFF},{x=31,y=12,w=1,h=1,c=0xFF000000},{x=32,y=12,w=6,h=1,c=0xFFFFFFFF},{x=38,y=12,w=7,h=1,c=0xFF000000},{x=45,y=12,w=11,h=1,c=0xFFFFFFFF},{x=8,y=13,w=1,h=1,c=0xFF000000},{x=9,y=13,w=14,h=1,c=0xFFFFFFFF},
  {x=23,y=13,w=2,h=1,c=0xFF000000},{x=25,y=13,w=6,h=1,c=0xFFFFFFFF},{x=31,y=13,w=1,h=1,c=0xFF000000},{x=32,y=13,w=13,h=1,c=0xFFFFFFFF},{x=45,y=13,w=2,h=1,c=0xFF000000},{x=47,y=13,w=9,h=1,c=0xFFFFFFFF},{x=7,y=14,w=1,h=1,c=0xFF000000},{x=8,y=14,w=16,h=1,c=0xFFFFFFFF},
  {x=24,y=14,w=2,h=1,c=0xFF000000},{x=26,y=14,w=5,h=1,c=0xFFFFFFFF},{x=31,y=14,w=1,h=1,c=0xFF000000},{x=32,y=14,w=7,h=1,c=0xFFFFFFFF},{x=39,y=14,w=6,h=1,c=0xFF000000},{x=47,y=14,w=9,h=1,c=0xFF000000},{x=7,y=15,w=1,h=1,c=0xFF000000},{x=8,y=15,w=17,h=1,c=0xFFFFFFFF},
  {x=25,y=15,w=7,h=1,c=0xFF000000},{x=32,y=15,w=10,h=1,c=0xFFFFFFFF},{x=42,y=15,w=1,h=1,c=0xFF000000},{x=6,y=16,w=1,h=1,c=0xFF000000},{x=7,y=16,w=22,h=1,c=0xFFFFFFFF},{x=29,y=16,w=3,h=1,c=0xFF000000},{x=32,y=16,w=9,h=1,c=0xFFFFFFFF},{x=41,y=16,w=1,h=1,c=0xFF000000},
  {x=45,y=16,w=2,h=1,c=0xFF000000},{x=5,y=17,w=1,h=1,c=0xFF000000},{x=6,y=17,w=36,h=1,c=0xFFFFFFFF},{x=42,y=17,w=3,h=1,c=0xFF000000},{x=45,y=17,w=2,h=1,c=0xFFFFFFFF},{x=47,y=17,w=1,h=1,c=0xFF000000},{x=4,y=18,w=1,h=1,c=0xFF000000},{x=5,y=18,w=29,h=1,c=0xFFFFFFFF},
  {x=34,y=18,w=4,h=1,c=0xFF000000},{x=38,y=18,w=7,h=1,c=0xFFFFFFFF},{x=45,y=18,w=2,h=1,c=0xFF000000},{x=1,y=19,w=3,h=1,c=0xFF000000},{x=4,y=19,w=28,h=1,c=0xFFFFFFFF},{x=32,y=19,w=2,h=1,c=0xFF000000},{x=38,y=19,w=1,h=1,c=0xFF000000},{x=39,y=19,w=3,h=1,c=0xFFFFFFFF},
  {x=42,y=19,w=3,h=1,c=0xFF000000},{x=1,y=20,w=11,h=1,c=0xFFFFFFFF},{x=12,y=20,w=20,h=1,c=0xFF000000},{x=38,y=20,w=1,h=1,c=0xFF000000},{x=39,y=20,w=2,h=1,c=0xFFFFFFFF},{x=41,y=20,w=1,h=1,c=0xFF000000},{x=1,y=23,w=11,h=1,c=0xFFFFFFFF},{x=12,y=23,w=20,h=1,c=0xFF000000},
  {x=38,y=23,w=1,h=1,c=0xFF000000},{x=39,y=23,w=2,h=1,c=0xFFFFFFFF},{x=41,y=23,w=1,h=1,c=0xFF000000},{x=1,y=24,w=3,h=1,c=0xFF000000},{x=4,y=24,w=28,h=1,c=0xFFFFFFFF},{x=32,y=24,w=2,h=1,c=0xFF000000},{x=38,y=24,w=1,h=1,c=0xFF000000},{x=39,y=24,w=3,h=1,c=0xFFFFFFFF},
  {x=42,y=24,w=3,h=1,c=0xFF000000},{x=4,y=25,w=1,h=1,c=0xFF000000},{x=5,y=25,w=29,h=1,c=0xFFFFFFFF},{x=34,y=25,w=4,h=1,c=0xFF000000},{x=38,y=25,w=7,h=1,c=0xFFFFFFFF},{x=45,y=25,w=2,h=1,c=0xFF000000},{x=5,y=26,w=1,h=1,c=0xFF000000},{x=6,y=26,w=36,h=1,c=0xFFFFFFFF},
  {x=42,y=26,w=3,h=1,c=0xFF000000},{x=45,y=26,w=2,h=1,c=0xFFFFFFFF},{x=47,y=26,w=1,h=1,c=0xFF000000},{x=6,y=27,w=1,h=1,c=0xFF000000},{x=7,y=27,w=22,h=1,c=0xFFFFFFFF},{x=29,y=27,w=3,h=1,c=0xFF000000},{x=32,y=27,w=9,h=1,c=0xFFFFFFFF},{x=41,y=27,w=1,h=1,c=0xFF000000},
  {x=45,y=27,w=2,h=1,c=0xFF000000},{x=7,y=28,w=1,h=1,c=0xFF000000},{x=8,y=28,w=17,h=1,c=0xFFFFFFFF},{x=25,y=28,w=7,h=1,c=0xFF000000},{x=32,y=28,w=10,h=1,c=0xFFFFFFFF},{x=42,y=28,w=1,h=1,c=0xFF000000},{x=7,y=29,w=1,h=1,c=0xFF000000},{x=8,y=29,w=16,h=1,c=0xFFFFFFFF},
  {x=24,y=29,w=2,h=1,c=0xFF000000},{x=26,y=29,w=5,h=1,c=0xFFFFFFFF},{x=31,y=29,w=1,h=1,c=0xFF000000},{x=32,y=29,w=7,h=1,c=0xFFFFFFFF},{x=39,y=29,w=6,h=1,c=0xFF000000},{x=47,y=29,w=9,h=1,c=0xFF000000},{x=8,y=30,w=1,h=1,c=0xFF000000},{x=9,y=30,w=14,h=1,c=0xFFFFFFFF},
  {x=23,y=30,w=2,h=1,c=0xFF000000},{x=25,y=30,w=6,h=1,c=0xFFFFFFFF},{x=31,y=30,w=1,h=1,c=0xFF000000},{x=32,y=30,w=13,h=1,c=0xFFFFFFFF},{x=45,y=30,w=2,h=1,c=0xFF000000},{x=47,y=30,w=9,h=1,c=0xFFFFFFFF},{x=8,y=31,w=1,h=1,c=0xFF000000},{x=9,y=31,w=13,h=1,c=0xFFFFFFFF},
  {x=22,y=31,w=1,h=1,c=0xFF000000},{x=24,y=31,w=1,h=1,c=0xFF000000},{x=25,y=31,w=6,h=1,c=0xFFFFFFFF},{x=31,y=31,w=1,h=1,c=0xFF000000},{x=32,y=31,w=6,h=1,c=0xFFFFFFFF},{x=38,y=31,w=7,h=1,c=0xFF000000},{x=45,y=31,w=11,h=1,c=0xFFFFFFFF},{x=9,y=32,w=1,h=1,c=0xFF000000},
  {x=10,y=32,w=12,h=1,c=0xFFFFFFFF},{x=22,y=32,w=1,h=1,c=0xFF000000},{x=25,y=32,w=1,h=1,c=0xFF000000},{x=26,y=32,w=4,h=1,c=0xFFFFFFFF},{x=30,y=32,w=1,h=1,c=0xFF000000},{x=31,y=32,w=5,h=1,c=0xFFFFFFFF},{x=36,y=32,w=2,h=1,c=0xFF000000},{x=42,y=32,w=2,h=1,c=0xFF000000},
  {x=44,y=32,w=4,h=1,c=0xFFFFFFFF},{x=48,y=32,w=2,h=1,c=0xFF000000},{x=50,y=32,w=6,h=1,c=0xFFFFFFFF},{x=6,y=33,w=1,h=1,c=0xFF000000},{x=9,y=33,w=1,h=1,c=0xFF000000},{x=10,y=33,w=12,h=1,c=0xFFFFFFFF},{x=22,y=33,w=1,h=1,c=0xFF000000},{x=26,y=33,w=5,h=1,c=0xFF000000},
  {x=31,y=33,w=7,h=1,c=0xFFFFFFFF},{x=38,y=33,w=4,h=1,c=0xFF000000},{x=42,y=33,w=5,h=1,c=0xFFFFFFFF},{x=47,y=33,w=5,h=1,c=0xFF000000},{x=52,y=33,w=4,h=1,c=0xFFFFFFFF},{x=5,y=34,w=1,h=1,c=0xFF000000},{x=6,y=34,w=1,h=1,c=0xFFFFFFFF},{x=7,y=34,w=1,h=1,c=0xFF000000},
  {x=10,y=34,w=1,h=1,c=0xFF000000},{x=11,y=34,w=12,h=1,c=0xFFFFFFFF},{x=23,y=34,w=5,h=1,c=0xFF000000},{x=28,y=34,w=4,h=1,c=0xFFFFFFFF},{x=32,y=34,w=6,h=1,c=0xFF000000},{x=38,y=34,w=8,h=1,c=0xFFFFFFFF},{x=46,y=34,w=2,h=1,c=0xFF000000},{x=48,y=34,w=7,h=1,c=0xFFFFFFFF},
  {x=55,y=34,w=1,h=1,c=0xFF000000},{x=5,y=35,w=1,h=1,c=0xFF000000},{x=6,y=35,w=2,h=1,c=0xFFFFFFFF},{x=8,y=35,w=1,h=1,c=0xFF000000},{x=11,y=35,w=1,h=1,c=0xFF000000},{x=12,y=35,w=6,h=1,c=0xFFFFFFFF},{x=18,y=35,w=1,h=1,c=0xFF000000},{x=19,y=35,w=11,h=1,c=0xFFFFFFFF},
  {x=30,y=35,w=2,h=1,c=0xFF000000},{x=35,y=35,w=2,h=1,c=0xFF000000},{x=37,y=35,w=8,h=1,c=0xFFFFFFFF},{x=45,y=35,w=1,h=1,c=0xFF000000},{x=48,y=35,w=3,h=1,c=0xFF000000},{x=51,y=35,w=2,h=1,c=0xFFFFFFFF},{x=53,y=35,w=2,h=1,c=0xFF000000},{x=6,y=36,w=1,h=1,c=0xFF000000},
  {x=7,y=36,w=2,h=1,c=0xFFFFFFFF},{x=9,y=36,w=2,h=1,c=0xFF000000},{x=12,y=36,w=1,h=1,c=0xFF000000},{x=13,y=36,w=6,h=1,c=0xFFFFFFFF},{x=19,y=36,w=3,h=1,c=0xFF000000},{x=22,y=36,w=3,h=1,c=0xFFFFFFFF},{x=25,y=36,w=10,h=1,c=0xFF000000},{x=35,y=36,w=9,h=1,c=0xFFFFFFFF},
  {x=44,y=36,w=1,h=1,c=0xFF000000},{x=47,y=36,w=1,h=1,c=0xFF000000},{x=48,y=36,w=3,h=1,c=0xFFFFFFFF},{x=51,y=36,w=2,h=1,c=0xFF000000},{x=7,y=37,w=1,h=1,c=0xFF000000},{x=8,y=37,w=3,h=1,c=0xFFFFFFFF},{x=11,y=37,w=2,h=1,c=0xFF000000},{x=13,y=37,w=7,h=1,c=0xFFFFFFFF},
  {x=20,y=37,w=10,h=1,c=0xFF000000},{x=30,y=37,w=13,h=1,c=0xFFFFFFFF},{x=43,y=37,w=1,h=1,c=0xFF000000},{x=47,y=37,w=1,h=1,c=0xFF000000},{x=48,y=37,w=1,h=1,c=0xFFFFFFFF},{x=49,y=37,w=2,h=1,c=0xFF000000},{x=8,y=38,w=1,h=1,c=0xFF000000},{x=9,y=38,w=24,h=1,c=0xFFFFFFFF},
  {x=33,y=38,w=4,h=1,c=0xFF000000},{x=37,y=38,w=5,h=1,c=0xFFFFFFFF},{x=42,y=38,w=1,h=1,c=0xFF000000},{x=48,y=38,w=1,h=1,c=0xFF000000},{x=9,y=39,w=1,h=1,c=0xFF000000},{x=10,y=39,w=19,h=1,c=0xFFFFFFFF},{x=29,y=39,w=4,h=1,c=0xFF000000},{x=35,y=39,w=1,h=1,c=0xFF000000},
  {x=36,y=39,w=5,h=1,c=0xFFFFFFFF},{x=41,y=39,w=1,h=1,c=0xFF000000},{x=10,y=40,w=3,h=1,c=0xFF000000},{x=13,y=40,w=12,h=1,c=0xFFFFFFFF},{x=25,y=40,w=4,h=1,c=0xFF000000},{x=34,y=40,w=1,h=1,c=0xFF000000},{x=35,y=40,w=4,h=1,c=0xFFFFFFFF},{x=39,y=40,w=2,h=1,c=0xFF000000},
  {x=13,y=41,w=2,h=1,c=0xFF000000},{x=15,y=41,w=9,h=1,c=0xFFFFFFFF},{x=24,y=41,w=1,h=1,c=0xFF000000},{x=33,y=41,w=1,h=1,c=0xFF000000},{x=34,y=41,w=1,h=1,c=0xFFFFFFFF},{x=35,y=41,w=4,h=1,c=0xFF000000},{x=15,y=42,w=2,h=1,c=0xFF000000},{x=17,y=42,w=5,h=1,c=0xFFFFFFFF},
  {x=22,y=42,w=2,h=1,c=0xFF000000},{x=33,y=42,w=1,h=1,c=0xFF000000},{x=34,y=42,w=1,h=1,c=0xFFFFFFFF},{x=35,y=42,w=1,h=1,c=0xFF000000},
}}

--- 龙骨炮开火 4（57x44，297 个矩形）
M.blaster_fire_4 = { w=57, h=44, rects={
  {x=17,y=1,w=5,h=1,c=0xFF000000},{x=34,y=1,w=1,h=1,c=0xFF000000},{x=47,y=1,w=1,h=1,c=0xFF000000},{x=48,y=1,w=1,h=1,c=0xFFFFFFFF},{x=49,y=1,w=2,h=1,c=0xFF000000},{x=15,y=2,w=2,h=1,c=0xFF000000},{x=17,y=2,w=5,h=1,c=0xFFFFFFFF},{x=22,y=2,w=2,h=1,c=0xFF000000},
  {x=33,y=2,w=1,h=1,c=0xFF000000},{x=34,y=2,w=1,h=1,c=0xFFFFFFFF},{x=35,y=2,w=1,h=1,c=0xFF000000},{x=47,y=2,w=1,h=1,c=0xFF000000},{x=48,y=2,w=3,h=1,c=0xFFFFFFFF},{x=51,y=2,w=2,h=1,c=0xFF000000},{x=13,y=3,w=2,h=1,c=0xFF000000},{x=15,y=3,w=9,h=1,c=0xFFFFFFFF},
  {x=24,y=3,w=1,h=1,c=0xFF000000},{x=33,y=3,w=1,h=1,c=0xFF000000},{x=34,y=3,w=1,h=1,c=0xFFFFFFFF},{x=35,y=3,w=4,h=1,c=0xFF000000},{x=48,y=3,w=3,h=1,c=0xFF000000},{x=51,y=3,w=2,h=1,c=0xFFFFFFFF},{x=53,y=3,w=3,h=1,c=0xFF000000},{x=10,y=4,w=3,h=1,c=0xFF000000},
  {x=13,y=4,w=12,h=1,c=0xFFFFFFFF},{x=25,y=4,w=4,h=1,c=0xFF000000},{x=34,y=4,w=1,h=1,c=0xFF000000},{x=35,y=4,w=4,h=1,c=0xFFFFFFFF},{x=39,y=4,w=2,h=1,c=0xFF000000},{x=47,y=4,w=1,h=1,c=0xFF000000},{x=48,y=4,w=8,h=1,c=0xFFFFFFFF},{x=9,y=5,w=1,h=1,c=0xFF000000},
  {x=10,y=5,w=19,h=1,c=0xFFFFFFFF},{x=29,y=5,w=4,h=1,c=0xFF000000},{x=35,y=5,w=1,h=1,c=0xFF000000},{x=36,y=5,w=5,h=1,c=0xFFFFFFFF},{x=41,y=5,w=2,h=1,c=0xFF000000},{x=48,y=5,w=4,h=1,c=0xFF000000},{x=52,y=5,w=4,h=1,c=0xFFFFFFFF},{x=8,y=6,w=1,h=1,c=0xFF000000},
  {x=9,y=6,w=24,h=1,c=0xFFFFFFFF},{x=33,y=6,w=4,h=1,c=0xFF000000},{x=37,y=6,w=6,h=1,c=0xFFFFFFFF},{x=43,y=6,w=7,h=1,c=0xFF000000},{x=50,y=6,w=6,h=1,c=0xFFFFFFFF},{x=7,y=7,w=1,h=1,c=0xFF000000},{x=8,y=7,w=3,h=1,c=0xFFFFFFFF},{x=11,y=7,w=2,h=1,c=0xFF000000},
  {x=13,y=7,w=7,h=1,c=0xFFFFFFFF},{x=20,y=7,w=10,h=1,c=0xFF000000},{x=30,y=7,w=26,h=1,c=0xFFFFFFFF},{x=6,y=8,w=1,h=1,c=0xFF000000},{x=7,y=8,w=2,h=1,c=0xFFFFFFFF},{x=9,y=8,w=2,h=1,c=0xFF000000},{x=12,y=8,w=1,h=1,c=0xFF000000},{x=13,y=8,w=6,h=1,c=0xFFFFFFFF},
  {x=19,y=8,w=3,h=1,c=0xFF000000},{x=22,y=8,w=3,h=1,c=0xFFFFFFFF},{x=25,y=8,w=10,h=1,c=0xFF000000},{x=35,y=8,w=20,h=1,c=0xFFFFFFFF},{x=55,y=8,w=1,h=1,c=0xFF000000},{x=5,y=9,w=1,h=1,c=0xFF000000},{x=6,y=9,w=2,h=1,c=0xFFFFFFFF},{x=8,y=9,w=1,h=1,c=0xFF000000},
  {x=11,y=9,w=1,h=1,c=0xFF000000},{x=12,y=9,w=6,h=1,c=0xFFFFFFFF},{x=18,y=9,w=1,h=1,c=0xFF000000},{x=19,y=9,w=11,h=1,c=0xFFFFFFFF},{x=30,y=9,w=2,h=1,c=0xFF000000},{x=35,y=9,w=2,h=1,c=0xFF000000},{x=37,y=9,w=11,h=1,c=0xFFFFFFFF},{x=48,y=9,w=7,h=1,c=0xFF000000},
  {x=5,y=10,w=1,h=1,c=0xFF000000},{x=6,y=10,w=1,h=1,c=0xFFFFFFFF},{x=7,y=10,w=1,h=1,c=0xFF000000},{x=10,y=10,w=1,h=1,c=0xFF000000},{x=11,y=10,w=12,h=1,c=0xFFFFFFFF},{x=23,y=10,w=5,h=1,c=0xFF000000},{x=28,y=10,w=4,h=1,c=0xFFFFFFFF},{x=32,y=10,w=6,h=1,c=0xFF000000},
  {x=38,y=10,w=8,h=1,c=0xFFFFFFFF},{x=46,y=10,w=2,h=1,c=0xFF000000},{x=6,y=11,w=1,h=1,c=0xFF000000},{x=9,y=11,w=1,h=1,c=0xFF000000},{x=10,y=11,w=12,h=1,c=0xFFFFFFFF},{x=22,y=11,w=1,h=1,c=0xFF000000},{x=28,y=11,w=3,h=1,c=0xFF000000},{x=31,y=11,w=7,h=1,c=0xFFFFFFFF},
  {x=38,y=11,w=8,h=1,c=0xFF000000},{x=9,y=12,w=1,h=1,c=0xFF000000},{x=10,y=12,w=12,h=1,c=0xFFFFFFFF},{x=22,y=12,w=1,h=1,c=0xFF000000},{x=30,y=12,w=1,h=1,c=0xFF000000},{x=31,y=12,w=5,h=1,c=0xFFFFFFFF},{x=36,y=12,w=2,h=1,c=0xFF000000},{x=8,y=13,w=1,h=1,c=0xFF000000},
  {x=9,y=13,w=13,h=1,c=0xFFFFFFFF},{x=22,y=13,w=1,h=1,c=0xFF000000},{x=31,y=13,w=1,h=1,c=0xFF000000},{x=32,y=13,w=6,h=1,c=0xFFFFFFFF},{x=38,y=13,w=7,h=1,c=0xFF000000},{x=8,y=14,w=1,h=1,c=0xFF000000},{x=9,y=14,w=14,h=1,c=0xFFFFFFFF},{x=23,y=14,w=1,h=1,c=0xFF000000},
  {x=31,y=14,w=1,h=1,c=0xFF000000},{x=32,y=14,w=13,h=1,c=0xFFFFFFFF},{x=45,y=14,w=1,h=1,c=0xFF000000},{x=7,y=15,w=1,h=1,c=0xFF000000},{x=8,y=15,w=16,h=1,c=0xFFFFFFFF},{x=24,y=15,w=1,h=1,c=0xFF000000},{x=31,y=15,w=1,h=1,c=0xFF000000},{x=32,y=15,w=7,h=1,c=0xFFFFFFFF},
  {x=39,y=15,w=6,h=1,c=0xFF000000},{x=7,y=16,w=1,h=1,c=0xFF000000},{x=8,y=16,w=17,h=1,c=0xFFFFFFFF},{x=25,y=16,w=4,h=1,c=0xFF000000},{x=31,y=16,w=1,h=1,c=0xFF000000},{x=32,y=16,w=10,h=1,c=0xFFFFFFFF},{x=42,y=16,w=1,h=1,c=0xFF000000},{x=6,y=17,w=1,h=1,c=0xFF000000},
  {x=7,y=17,w=22,h=1,c=0xFFFFFFFF},{x=29,y=17,w=3,h=1,c=0xFF000000},{x=32,y=17,w=9,h=1,c=0xFFFFFFFF},{x=41,y=17,w=1,h=1,c=0xFF000000},{x=45,y=17,w=2,h=1,c=0xFF000000},{x=5,y=18,w=1,h=1,c=0xFF000000},{x=6,y=18,w=36,h=1,c=0xFFFFFFFF},{x=42,y=18,w=3,h=1,c=0xFF000000},
  {x=45,y=18,w=2,h=1,c=0xFFFFFFFF},{x=47,y=18,w=1,h=1,c=0xFF000000},{x=4,y=19,w=1,h=1,c=0xFF000000},{x=5,y=19,w=29,h=1,c=0xFFFFFFFF},{x=34,y=19,w=4,h=1,c=0xFF000000},{x=38,y=19,w=7,h=1,c=0xFFFFFFFF},{x=45,y=19,w=2,h=1,c=0xFF000000},{x=1,y=20,w=3,h=1,c=0xFF000000},
  {x=4,y=20,w=28,h=1,c=0xFFFFFFFF},{x=32,y=20,w=2,h=1,c=0xFF000000},{x=38,y=20,w=1,h=1,c=0xFF000000},{x=39,y=20,w=3,h=1,c=0xFFFFFFFF},{x=42,y=20,w=3,h=1,c=0xFF000000},{x=1,y=21,w=11,h=1,c=0xFFFFFFFF},{x=12,y=21,w=20,h=1,c=0xFF000000},{x=38,y=21,w=1,h=1,c=0xFF000000},
  {x=39,y=21,w=2,h=1,c=0xFFFFFFFF},{x=41,y=21,w=1,h=1,c=0xFF000000},{x=1,y=22,w=11,h=1,c=0xFFFFFFFF},{x=12,y=22,w=20,h=1,c=0xFF000000},{x=38,y=22,w=1,h=1,c=0xFF000000},{x=39,y=22,w=2,h=1,c=0xFFFFFFFF},{x=41,y=22,w=1,h=1,c=0xFF000000},{x=1,y=23,w=3,h=1,c=0xFF000000},
  {x=4,y=23,w=28,h=1,c=0xFFFFFFFF},{x=32,y=23,w=2,h=1,c=0xFF000000},{x=38,y=23,w=1,h=1,c=0xFF000000},{x=39,y=23,w=3,h=1,c=0xFFFFFFFF},{x=42,y=23,w=3,h=1,c=0xFF000000},{x=4,y=24,w=1,h=1,c=0xFF000000},{x=5,y=24,w=29,h=1,c=0xFFFFFFFF},{x=34,y=24,w=4,h=1,c=0xFF000000},
  {x=38,y=24,w=7,h=1,c=0xFFFFFFFF},{x=45,y=24,w=2,h=1,c=0xFF000000},{x=5,y=25,w=1,h=1,c=0xFF000000},{x=6,y=25,w=36,h=1,c=0xFFFFFFFF},{x=42,y=25,w=3,h=1,c=0xFF000000},{x=45,y=25,w=2,h=1,c=0xFFFFFFFF},{x=47,y=25,w=1,h=1,c=0xFF000000},{x=6,y=26,w=1,h=1,c=0xFF000000},
  {x=7,y=26,w=22,h=1,c=0xFFFFFFFF},{x=29,y=26,w=3,h=1,c=0xFF000000},{x=32,y=26,w=9,h=1,c=0xFFFFFFFF},{x=41,y=26,w=1,h=1,c=0xFF000000},{x=45,y=26,w=2,h=1,c=0xFF000000},{x=7,y=27,w=1,h=1,c=0xFF000000},{x=8,y=27,w=17,h=1,c=0xFFFFFFFF},{x=25,y=27,w=7,h=1,c=0xFF000000},
  {x=32,y=27,w=10,h=1,c=0xFFFFFFFF},{x=42,y=27,w=1,h=1,c=0xFF000000},{x=7,y=28,w=1,h=1,c=0xFF000000},{x=8,y=28,w=16,h=1,c=0xFFFFFFFF},{x=24,y=28,w=2,h=1,c=0xFF000000},{x=26,y=28,w=5,h=1,c=0xFFFFFFFF},{x=31,y=28,w=1,h=1,c=0xFF000000},{x=32,y=28,w=7,h=1,c=0xFFFFFFFF},
  {x=39,y=28,w=6,h=1,c=0xFF000000},{x=8,y=29,w=1,h=1,c=0xFF000000},{x=9,y=29,w=14,h=1,c=0xFFFFFFFF},{x=23,y=29,w=2,h=1,c=0xFF000000},{x=25,y=29,w=6,h=1,c=0xFFFFFFFF},{x=31,y=29,w=1,h=1,c=0xFF000000},{x=32,y=29,w=13,h=1,c=0xFFFFFFFF},{x=45,y=29,w=1,h=1,c=0xFF000000},
  {x=8,y=30,w=1,h=1,c=0xFF000000},{x=9,y=30,w=13,h=1,c=0xFFFFFFFF},{x=22,y=30,w=1,h=1,c=0xFF000000},{x=24,y=30,w=1,h=1,c=0xFF000000},{x=25,y=30,w=6,h=1,c=0xFFFFFFFF},{x=31,y=30,w=1,h=1,c=0xFF000000},{x=32,y=30,w=6,h=1,c=0xFFFFFFFF},{x=38,y=30,w=7,h=1,c=0xFF000000},
  {x=9,y=31,w=1,h=1,c=0xFF000000},{x=10,y=31,w=12,h=1,c=0xFFFFFFFF},{x=22,y=31,w=1,h=1,c=0xFF000000},{x=25,y=31,w=1,h=1,c=0xFF000000},{x=26,y=31,w=4,h=1,c=0xFFFFFFFF},{x=30,y=31,w=1,h=1,c=0xFF000000},{x=31,y=31,w=5,h=1,c=0xFFFFFFFF},{x=36,y=31,w=2,h=1,c=0xFF000000},
  {x=6,y=32,w=1,h=1,c=0xFF000000},{x=9,y=32,w=1,h=1,c=0xFF000000},{x=10,y=32,w=12,h=1,c=0xFFFFFFFF},{x=22,y=32,w=1,h=1,c=0xFF000000},{x=26,y=32,w=5,h=1,c=0xFF000000},{x=31,y=32,w=7,h=1,c=0xFFFFFFFF},{x=38,y=32,w=8,h=1,c=0xFF000000},{x=5,y=33,w=1,h=1,c=0xFF000000},
  {x=6,y=33,w=1,h=1,c=0xFFFFFFFF},{x=7,y=33,w=1,h=1,c=0xFF000000},{x=10,y=33,w=1,h=1,c=0xFF000000},{x=11,y=33,w=12,h=1,c=0xFFFFFFFF},{x=23,y=33,w=5,h=1,c=0xFF000000},{x=28,y=33,w=4,h=1,c=0xFFFFFFFF},{x=32,y=33,w=6,h=1,c=0xFF000000},{x=38,y=33,w=8,h=1,c=0xFFFFFFFF},
  {x=46,y=33,w=2,h=1,c=0xFF000000},{x=5,y=34,w=1,h=1,c=0xFF000000},{x=6,y=34,w=2,h=1,c=0xFFFFFFFF},{x=8,y=34,w=1,h=1,c=0xFF000000},{x=11,y=34,w=1,h=1,c=0xFF000000},{x=12,y=34,w=6,h=1,c=0xFFFFFFFF},{x=18,y=34,w=1,h=1,c=0xFF000000},{x=19,y=34,w=11,h=1,c=0xFFFFFFFF},
  {x=30,y=34,w=2,h=1,c=0xFF000000},{x=35,y=34,w=2,h=1,c=0xFF000000},{x=37,y=34,w=11,h=1,c=0xFFFFFFFF},{x=48,y=34,w=7,h=1,c=0xFF000000},{x=6,y=35,w=1,h=1,c=0xFF000000},{x=7,y=35,w=2,h=1,c=0xFFFFFFFF},{x=9,y=35,w=2,h=1,c=0xFF000000},{x=12,y=35,w=1,h=1,c=0xFF000000},
  {x=13,y=35,w=6,h=1,c=0xFFFFFFFF},{x=19,y=35,w=3,h=1,c=0xFF000000},{x=22,y=35,w=3,h=1,c=0xFFFFFFFF},{x=25,y=35,w=10,h=1,c=0xFF000000},{x=35,y=35,w=20,h=1,c=0xFFFFFFFF},{x=55,y=35,w=1,h=1,c=0xFF000000},{x=7,y=36,w=1,h=1,c=0xFF000000},{x=8,y=36,w=3,h=1,c=0xFFFFFFFF},
  {x=11,y=36,w=2,h=1,c=0xFF000000},{x=13,y=36,w=7,h=1,c=0xFFFFFFFF},{x=20,y=36,w=10,h=1,c=0xFF000000},{x=30,y=36,w=26,h=1,c=0xFFFFFFFF},{x=8,y=37,w=1,h=1,c=0xFF000000},{x=9,y=37,w=24,h=1,c=0xFFFFFFFF},{x=33,y=37,w=4,h=1,c=0xFF000000},{x=37,y=37,w=6,h=1,c=0xFFFFFFFF},
  {x=43,y=37,w=7,h=1,c=0xFF000000},{x=50,y=37,w=6,h=1,c=0xFFFFFFFF},{x=9,y=38,w=1,h=1,c=0xFF000000},{x=10,y=38,w=19,h=1,c=0xFFFFFFFF},{x=29,y=38,w=4,h=1,c=0xFF000000},{x=35,y=38,w=1,h=1,c=0xFF000000},{x=36,y=38,w=5,h=1,c=0xFFFFFFFF},{x=41,y=38,w=2,h=1,c=0xFF000000},
  {x=48,y=38,w=4,h=1,c=0xFF000000},{x=52,y=38,w=4,h=1,c=0xFFFFFFFF},{x=10,y=39,w=3,h=1,c=0xFF000000},{x=13,y=39,w=12,h=1,c=0xFFFFFFFF},{x=25,y=39,w=4,h=1,c=0xFF000000},{x=34,y=39,w=1,h=1,c=0xFF000000},{x=35,y=39,w=4,h=1,c=0xFFFFFFFF},{x=39,y=39,w=2,h=1,c=0xFF000000},
  {x=47,y=39,w=1,h=1,c=0xFF000000},{x=48,y=39,w=8,h=1,c=0xFFFFFFFF},{x=13,y=40,w=2,h=1,c=0xFF000000},{x=15,y=40,w=9,h=1,c=0xFFFFFFFF},{x=24,y=40,w=1,h=1,c=0xFF000000},{x=33,y=40,w=1,h=1,c=0xFF000000},{x=34,y=40,w=1,h=1,c=0xFFFFFFFF},{x=35,y=40,w=4,h=1,c=0xFF000000},
  {x=48,y=40,w=3,h=1,c=0xFF000000},{x=51,y=40,w=2,h=1,c=0xFFFFFFFF},{x=53,y=40,w=3,h=1,c=0xFF000000},{x=15,y=41,w=2,h=1,c=0xFF000000},{x=17,y=41,w=5,h=1,c=0xFFFFFFFF},{x=22,y=41,w=2,h=1,c=0xFF000000},{x=33,y=41,w=1,h=1,c=0xFF000000},{x=34,y=41,w=1,h=1,c=0xFFFFFFFF},
  {x=35,y=41,w=1,h=1,c=0xFF000000},{x=47,y=41,w=1,h=1,c=0xFF000000},{x=48,y=41,w=3,h=1,c=0xFFFFFFFF},{x=51,y=41,w=2,h=1,c=0xFF000000},{x=17,y=42,w=5,h=1,c=0xFF000000},{x=34,y=42,w=1,h=1,c=0xFF000000},{x=47,y=42,w=1,h=1,c=0xFF000000},{x=48,y=42,w=1,h=1,c=0xFFFFFFFF},
  {x=49,y=42,w=2,h=1,c=0xFF000000},
}}

--- Sans 本体 HandRight 第 0 帧（96x48，295 个矩形）
M.sans_body_default = { w=96, h=48, rects={
  {x=48,y=0,w=3,h=1,c=0xFFFFFFFF},{x=15,y=1,w=3,h=1,c=0xFFFFFFFF},{x=47,y=1,w=5,h=1,c=0xFFFFFFFF},{x=14,y=2,w=5,h=1,c=0xFFFFFFFF},{x=46,y=2,w=4,h=1,c=0xFFFFFFFF},{x=14,y=3,w=6,h=1,c=0xFFFFFFFF},{x=45,y=3,w=4,h=1,c=0xFFFFFFFF},{x=51,y=3,w=1,h=1,c=0xFFFFFFFF},
  {x=13,y=4,w=1,h=1,c=0xFFFFFFFF},{x=17,y=4,w=5,h=1,c=0xFFFFFFFF},{x=45,y=4,w=3,h=1,c=0xFFFFFFFF},{x=52,y=4,w=1,h=1,c=0xFFFFFFFF},{x=20,y=5,w=3,h=1,c=0xFFFFFFFF},{x=44,y=5,w=3,h=1,c=0xFFFFFFFF},{x=52,y=5,w=2,h=1,c=0xFFFFFFFF},{x=21,y=6,w=3,h=1,c=0xFFFFFFFF},
  {x=29,y=6,w=1,h=1,c=0xFFFFFFFF},{x=35,y=6,w=1,h=1,c=0xFFFFFFFF},{x=42,y=6,w=4,h=1,c=0xFFFFFFFF},{x=53,y=6,w=2,h=1,c=0xFFFFFFFF},{x=12,y=7,w=1,h=1,c=0xFFFFFFFF},{x=23,y=7,w=3,h=1,c=0xFFFFFFFF},{x=29,y=7,w=7,h=1,c=0xFFFFFFFF},{x=41,y=7,w=4,h=1,c=0xFFFFFFFF},
  {x=49,y=7,w=1,h=1,c=0xFFFFFFFF},{x=54,y=7,w=1,h=1,c=0xFFFFFFFF},{x=11,y=8,w=1,h=1,c=0xFFFFFFFF},{x=17,y=8,w=1,h=1,c=0xFFFFFFFF},{x=24,y=8,w=4,h=1,c=0xFFFFFFFF},{x=30,y=8,w=5,h=1,c=0xFFFFFFFF},{x=38,y=8,w=4,h=1,c=0xFFFFFFFF},{x=48,y=8,w=1,h=1,c=0xFFFFFFFF},
  {x=55,y=8,w=1,h=1,c=0xFFFFFFFF},{x=10,y=9,w=1,h=1,c=0xFFFFFFFF},{x=17,y=9,w=1,h=1,c=0xFFFFFFFF},{x=24,y=9,w=1,h=1,c=0xFFFFFFFF},{x=25,y=9,w=2,h=1,c=0xFF000000},{x=27,y=9,w=2,h=1,c=0xFFFFFFFF},{x=31,y=9,w=4,h=1,c=0xFFFFFFFF},{x=36,y=9,w=4,h=1,c=0xFFFFFFFF},
  {x=48,y=9,w=1,h=1,c=0xFFFFFFFF},{x=55,y=9,w=2,h=1,c=0xFFFFFFFF},{x=9,y=10,w=1,h=1,c=0xFFFFFFFF},{x=17,y=10,w=1,h=1,c=0xFFFFFFFF},{x=24,y=10,w=1,h=1,c=0xFFFFFFFF},{x=25,y=10,w=2,h=1,c=0xFF000000},{x=27,y=10,w=1,h=1,c=0xFFFFFFFF},{x=37,y=10,w=1,h=1,c=0xFFFFFFFF},
  {x=38,y=10,w=1,h=1,c=0xFF000000},{x=39,y=10,w=1,h=1,c=0xFFFFFFFF},{x=48,y=10,w=1,h=1,c=0xFFFFFFFF},{x=56,y=10,w=2,h=1,c=0xFFFFFFFF},{x=9,y=11,w=1,h=1,c=0xFFFFFFFF},{x=17,y=11,w=1,h=1,c=0xFFFFFFFF},{x=24,y=11,w=1,h=1,c=0xFFFFFFFF},{x=25,y=11,w=2,h=1,c=0xFF000000},
  {x=27,y=11,w=1,h=1,c=0xFFFFFFFF},{x=30,y=11,w=4,h=1,c=0xFFFFFFFF},{x=37,y=11,w=1,h=1,c=0xFFFFFFFF},{x=38,y=11,w=1,h=1,c=0xFF000000},{x=39,y=11,w=1,h=1,c=0xFFFFFFFF},{x=47,y=11,w=2,h=1,c=0xFFFFFFFF},{x=57,y=11,w=1,h=1,c=0xFFFFFFFF},{x=8,y=12,w=1,h=1,c=0xFFFFFFFF},
  {x=17,y=12,w=1,h=1,c=0xFFFFFFFF},{x=24,y=12,w=4,h=1,c=0xFFFFFFFF},{x=30,y=12,w=5,h=1,c=0xFFFFFFFF},{x=36,y=12,w=4,h=1,c=0xFFFFFFFF},{x=46,y=12,w=3,h=1,c=0xFFFFFFFF},{x=57,y=12,w=2,h=1,c=0xFFFFFFFF},{x=8,y=13,w=1,h=1,c=0xFFFFFFFF},{x=17,y=13,w=2,h=1,c=0xFFFFFFFF},
  {x=20,y=13,w=5,h=1,c=0xFFFFFFFF},{x=25,y=13,w=2,h=1,c=0xFF000000},{x=27,y=13,w=1,h=1,c=0xFFFFFFFF},{x=30,y=13,w=5,h=1,c=0xFFFFFFFF},{x=36,y=13,w=2,h=1,c=0xFFFFFFFF},{x=38,y=13,w=1,h=1,c=0xFF000000},{x=39,y=13,w=1,h=1,c=0xFFFFFFFF},{x=44,y=13,w=3,h=1,c=0xFFFFFFFF},
  {x=47,y=13,w=1,h=1,c=0xFF000000},{x=48,y=13,w=1,h=1,c=0xFFFFFFFF},{x=57,y=13,w=2,h=1,c=0xFFFFFFFF},{x=7,y=14,w=2,h=1,c=0xFFFFFFFF},{x=17,y=14,w=3,h=1,c=0xFFFFFFFF},{x=20,y=14,w=5,h=1,c=0xFF000000},{x=25,y=14,w=1,h=1,c=0xFFFFFFFF},{x=26,y=14,w=2,h=1,c=0xFF000000},
  {x=28,y=14,w=1,h=1,c=0xFFFFFFFF},{x=30,y=14,w=5,h=1,c=0xFFFFFFFF},{x=36,y=14,w=1,h=1,c=0xFFFFFFFF},{x=37,y=14,w=2,h=1,c=0xFF000000},{x=39,y=14,w=1,h=1,c=0xFFFFFFFF},{x=42,y=14,w=3,h=1,c=0xFFFFFFFF},{x=45,y=14,w=3,h=1,c=0xFF000000},{x=48,y=14,w=1,h=1,c=0xFFFFFFFF},
  {x=58,y=14,w=1,h=1,c=0xFFFFFFFF},{x=7,y=15,w=2,h=1,c=0xFFFFFFFF},{x=17,y=15,w=1,h=1,c=0xFFFFFFFF},{x=18,y=15,w=7,h=1,c=0xFF000000},{x=25,y=15,w=1,h=1,c=0xFFFFFFFF},{x=26,y=15,w=1,h=1,c=0xFF000000},{x=27,y=15,w=2,h=1,c=0xFFFFFFFF},{x=30,y=15,w=5,h=1,c=0xFFFFFFFF},
  {x=36,y=15,w=4,h=1,c=0xFFFFFFFF},{x=41,y=15,w=1,h=1,c=0xFFFFFFFF},{x=42,y=15,w=6,h=1,c=0xFF000000},{x=48,y=15,w=2,h=1,c=0xFFFFFFFF},{x=58,y=15,w=1,h=1,c=0xFFFFFFFF},{x=7,y=16,w=2,h=1,c=0xFFFFFFFF},{x=16,y=16,w=1,h=1,c=0xFFFFFFFF},{x=17,y=16,w=8,h=1,c=0xFF000000},
  {x=25,y=16,w=2,h=1,c=0xFFFFFFFF},{x=27,y=16,w=1,h=1,c=0xFF000000},{x=28,y=16,w=1,h=1,c=0xFFFFFFFF},{x=30,y=16,w=5,h=1,c=0xFFFFFFFF},{x=36,y=16,w=1,h=1,c=0xFFFFFFFF},{x=37,y=16,w=2,h=1,c=0xFF000000},{x=39,y=16,w=1,h=1,c=0xFFFFFFFF},{x=41,y=16,w=1,h=1,c=0xFFFFFFFF},
  {x=42,y=16,w=7,h=1,c=0xFF000000},{x=49,y=16,w=1,h=1,c=0xFFFFFFFF},{x=58,y=16,w=1,h=1,c=0xFFFFFFFF},{x=8,y=17,w=2,h=1,c=0xFFFFFFFF},{x=16,y=17,w=1,h=1,c=0xFFFFFFFF},{x=17,y=17,w=8,h=1,c=0xFF000000},{x=25,y=17,w=1,h=1,c=0xFFFFFFFF},{x=26,y=17,w=2,h=1,c=0xFF000000},
  {x=28,y=17,w=1,h=1,c=0xFFFFFFFF},{x=30,y=17,w=5,h=1,c=0xFFFFFFFF},{x=36,y=17,w=1,h=1,c=0xFFFFFFFF},{x=37,y=17,w=2,h=1,c=0xFF000000},{x=39,y=17,w=1,h=1,c=0xFFFFFFFF},{x=41,y=17,w=1,h=1,c=0xFFFFFFFF},{x=42,y=17,w=7,h=1,c=0xFF000000},{x=49,y=17,w=1,h=1,c=0xFFFFFFFF},
  {x=58,y=17,w=1,h=1,c=0xFFFFFFFF},{x=9,y=18,w=2,h=1,c=0xFFFFFFFF},{x=16,y=18,w=1,h=1,c=0xFFFFFFFF},{x=17,y=18,w=8,h=1,c=0xFF000000},{x=25,y=18,w=1,h=1,c=0xFFFFFFFF},{x=26,y=18,w=1,h=1,c=0xFF000000},{x=27,y=18,w=2,h=1,c=0xFFFFFFFF},{x=30,y=18,w=5,h=1,c=0xFFFFFFFF},
  {x=36,y=18,w=3,h=1,c=0xFFFFFFFF},{x=39,y=18,w=1,h=1,c=0xFF000000},{x=40,y=18,w=1,h=1,c=0xFFFFFFFF},{x=41,y=18,w=8,h=1,c=0xFF000000},{x=49,y=18,w=1,h=1,c=0xFFFFFFFF},{x=57,y=18,w=2,h=1,c=0xFFFFFFFF},{x=10,y=19,w=2,h=1,c=0xFFFFFFFF},{x=16,y=19,w=1,h=1,c=0xFFFFFFFF},
  {x=17,y=19,w=9,h=1,c=0xFF000000},{x=26,y=19,w=1,h=1,c=0xFFFFFFFF},{x=27,y=19,w=1,h=1,c=0xFF000000},{x=28,y=19,w=1,h=1,c=0xFFFFFFFF},{x=30,y=19,w=5,h=1,c=0xFFFFFFFF},{x=36,y=19,w=1,h=1,c=0xFFFFFFFF},{x=37,y=19,w=1,h=1,c=0xFF000000},{x=38,y=19,w=1,h=1,c=0xFFFFFFFF},
  {x=39,y=19,w=1,h=1,c=0xFF000000},{x=40,y=19,w=1,h=1,c=0xFFFFFFFF},{x=41,y=19,w=8,h=1,c=0xFF000000},{x=49,y=19,w=1,h=1,c=0xFFFFFFFF},{x=56,y=19,w=2,h=1,c=0xFFFFFFFF},{x=11,y=20,w=3,h=1,c=0xFFFFFFFF},{x=16,y=20,w=1,h=1,c=0xFFFFFFFF},{x=17,y=20,w=9,h=1,c=0xFF000000},
  {x=26,y=20,w=1,h=1,c=0xFFFFFFFF},{x=27,y=20,w=1,h=1,c=0xFF000000},{x=28,y=20,w=1,h=1,c=0xFFFFFFFF},{x=30,y=20,w=5,h=1,c=0xFFFFFFFF},{x=36,y=20,w=1,h=1,c=0xFFFFFFFF},{x=37,y=20,w=1,h=1,c=0xFF000000},{x=38,y=20,w=2,h=1,c=0xFFFFFFFF},{x=40,y=20,w=9,h=1,c=0xFF000000},
  {x=49,y=20,w=1,h=1,c=0xFFFFFFFF},{x=55,y=20,w=2,h=1,c=0xFFFFFFFF},{x=12,y=21,w=2,h=1,c=0xFFFFFFFF},{x=16,y=21,w=1,h=1,c=0xFFFFFFFF},{x=17,y=21,w=9,h=1,c=0xFF000000},{x=26,y=21,w=1,h=1,c=0xFFFFFFFF},{x=27,y=21,w=1,h=1,c=0xFF000000},{x=28,y=21,w=1,h=1,c=0xFFFFFFFF},
  {x=36,y=21,w=1,h=1,c=0xFFFFFFFF},{x=37,y=21,w=1,h=1,c=0xFF000000},{x=38,y=21,w=1,h=1,c=0xFFFFFFFF},{x=39,y=21,w=9,h=1,c=0xFF000000},{x=48,y=21,w=2,h=1,c=0xFFFFFFFF},{x=54,y=21,w=2,h=1,c=0xFFFFFFFF},{x=13,y=22,w=1,h=1,c=0xFFFFFFFF},{x=16,y=22,w=3,h=1,c=0xFFFFFFFF},
  {x=19,y=22,w=7,h=1,c=0xFF000000},{x=26,y=22,w=13,h=1,c=0xFFFFFFFF},{x=39,y=22,w=8,h=1,c=0xFF000000},{x=47,y=22,w=3,h=1,c=0xFFFFFFFF},{x=51,y=22,w=3,h=1,c=0xFFFFFFFF},{x=15,y=23,w=5,h=1,c=0xFFFFFFFF},{x=20,y=23,w=6,h=1,c=0xFF000000},{x=26,y=23,w=5,h=1,c=0xFFFFFFFF},
  {x=37,y=23,w=12,h=1,c=0xFFFFFFFF},{x=51,y=23,w=2,h=1,c=0xFFFFFFFF},{x=17,y=24,w=9,h=1,c=0xFFFFFFFF},{x=47,y=24,w=2,h=1,c=0xFFFFFFFF},{x=40,y=26,w=2,h=1,c=0xFFFFFFFF},{x=47,y=26,w=1,h=1,c=0xFFFFFFFF},{x=18,y=27,w=1,h=1,c=0xFFFFFFFF},{x=21,y=27,w=2,h=1,c=0xFFFFFFFF},
  {x=40,y=27,w=2,h=1,c=0xFFFFFFFF},{x=47,y=27,w=1,h=1,c=0xFFFFFFFF},{x=17,y=28,w=1,h=1,c=0xFFFFFFFF},{x=21,y=28,w=2,h=1,c=0xFFFFFFFF},{x=40,y=28,w=2,h=1,c=0xFFFFFFFF},{x=48,y=28,w=1,h=1,c=0xFFFFFFFF},{x=17,y=29,w=1,h=1,c=0xFFFFFFFF},{x=20,y=29,w=2,h=1,c=0xFFFFFFFF},
  {x=32,y=29,w=1,h=1,c=0xFFFFFFFF},{x=40,y=29,w=2,h=1,c=0xFFFFFFFF},{x=48,y=29,w=1,h=1,c=0xFFFFFFFF},{x=17,y=30,w=1,h=1,c=0xFFFFFFFF},{x=20,y=30,w=2,h=1,c=0xFFFFFFFF},{x=31,y=30,w=1,h=1,c=0xFFFFFFFF},{x=33,y=30,w=1,h=1,c=0xFFFFFFFF},{x=40,y=30,w=2,h=1,c=0xFFFFFFFF},
  {x=48,y=30,w=1,h=1,c=0xFFFFFFFF},{x=17,y=31,w=1,h=1,c=0xFFFFFFFF},{x=20,y=31,w=2,h=1,c=0xFFFFFFFF},{x=31,y=31,w=1,h=1,c=0xFFFFFFFF},{x=33,y=31,w=1,h=1,c=0xFFFFFFFF},{x=40,y=31,w=3,h=1,c=0xFFFFFFFF},{x=48,y=31,w=1,h=1,c=0xFFFFFFFF},{x=17,y=32,w=1,h=1,c=0xFFFFFFFF},
  {x=20,y=32,w=2,h=1,c=0xFFFFFFFF},{x=31,y=32,w=1,h=1,c=0xFFFFFFFF},{x=33,y=32,w=1,h=1,c=0xFFFFFFFF},{x=40,y=32,w=3,h=1,c=0xFFFFFFFF},{x=49,y=32,w=1,h=1,c=0xFFFFFFFF},{x=16,y=33,w=1,h=1,c=0xFFFFFFFF},{x=19,y=33,w=2,h=1,c=0xFFFFFFFF},{x=31,y=33,w=1,h=1,c=0xFFFFFFFF},
  {x=34,y=33,w=1,h=1,c=0xFFFFFFFF},{x=40,y=33,w=3,h=1,c=0xFFFFFFFF},{x=49,y=33,w=1,h=1,c=0xFFFFFFFF},{x=16,y=34,w=1,h=1,c=0xFFFFFFFF},{x=19,y=34,w=2,h=1,c=0xFFFFFFFF},{x=30,y=34,w=2,h=1,c=0xFFFFFFFF},{x=34,y=34,w=1,h=1,c=0xFFFFFFFF},{x=40,y=34,w=3,h=1,c=0xFFFFFFFF},
  {x=49,y=34,w=1,h=1,c=0xFFFFFFFF},{x=16,y=35,w=1,h=1,c=0xFFFFFFFF},{x=19,y=35,w=2,h=1,c=0xFFFFFFFF},{x=30,y=35,w=1,h=1,c=0xFFFFFFFF},{x=34,y=35,w=1,h=1,c=0xFFFFFFFF},{x=41,y=35,w=2,h=1,c=0xFFFFFFFF},{x=49,y=35,w=1,h=1,c=0xFFFFFFFF},{x=16,y=36,w=1,h=1,c=0xFFFFFFFF},
  {x=19,y=36,w=2,h=1,c=0xFFFFFFFF},{x=30,y=36,w=1,h=1,c=0xFFFFFFFF},{x=34,y=36,w=1,h=1,c=0xFFFFFFFF},{x=41,y=36,w=2,h=1,c=0xFFFFFFFF},{x=49,y=36,w=1,h=1,c=0xFFFFFFFF},{x=16,y=37,w=1,h=1,c=0xFFFFFFFF},{x=19,y=37,w=2,h=1,c=0xFFFFFFFF},{x=30,y=37,w=1,h=1,c=0xFFFFFFFF},
  {x=34,y=37,w=1,h=1,c=0xFFFFFFFF},{x=41,y=37,w=2,h=1,c=0xFFFFFFFF},{x=49,y=37,w=1,h=1,c=0xFFFFFFFF},{x=16,y=38,w=5,h=1,c=0xFFFFFFFF},{x=30,y=38,w=1,h=1,c=0xFFFFFFFF},{x=34,y=38,w=1,h=1,c=0xFFFFFFFF},{x=41,y=38,w=3,h=1,c=0xFFFFFFFF},{x=46,y=38,w=4,h=1,c=0xFFFFFFFF},
  {x=21,y=39,w=9,h=1,c=0xFFFFFFFF},{x=35,y=39,w=11,h=1,c=0xFFFFFFFF},{x=39,y=41,w=1,h=1,c=0xFFFFFFFF},{x=15,y=42,w=4,h=1,c=0xFFFFFFFF},{x=21,y=42,w=4,h=1,c=0xFFFFFFFF},{x=39,y=42,w=7,h=1,c=0xFFFFFFFF},{x=49,y=42,w=3,h=1,c=0xFFFFFFFF},{x=14,y=43,w=7,h=1,c=0xFFFFFFFF},
  {x=21,y=43,w=1,h=1,c=0xFF000000},{x=22,y=43,w=3,h=1,c=0xFFFFFFFF},{x=38,y=43,w=7,h=1,c=0xFFFFFFFF},{x=47,y=43,w=7,h=1,c=0xFFFFFFFF},{x=13,y=44,w=9,h=1,c=0xFFFFFFFF},{x=23,y=44,w=2,h=1,c=0xFFFFFFFF},{x=38,y=44,w=6,h=1,c=0xFFFFFFFF},{x=44,y=44,w=1,h=1,c=0xFF000000},
  {x=45,y=44,w=10,h=1,c=0xFFFFFFFF},{x=13,y=45,w=9,h=1,c=0xFFFFFFFF},{x=44,y=45,w=11,h=1,c=0xFFFFFFFF},{x=13,y=46,w=10,h=1,c=0xFFFFFFFF},{x=24,y=46,w=2,h=1,c=0xFFFFFFFF},{x=37,y=46,w=6,h=1,c=0xFFFFFFFF},{x=44,y=46,w=10,h=1,c=0xFFFFFFFF},
}}

--- Sans 本体 HandUp 第 4 帧（64x70，309 个矩形）
M.sans_body_up = { w=64, h=70, rects={
  {x=54,y=5,w=3,h=1,c=0xFFFFFFFF},{x=53,y=6,w=5,h=1,c=0xFFFFFFFF},{x=52,y=7,w=7,h=2,c=0xFFFFFFFF},{x=50,y=9,w=1,h=1,c=0xFFFFFFFF},{x=52,y=9,w=7,h=1,c=0xFFFFFFFF},{x=50,y=10,w=2,h=1,c=0xFFFFFFFF},{x=52,y=10,w=1,h=1,c=0xFF000000},{x=53,y=10,w=6,h=1,c=0xFFFFFFFF},
  {x=50,y=11,w=9,h=3,c=0xFFFFFFFF},{x=50,y=14,w=1,h=1,c=0xFFFFFFFF},{x=55,y=14,w=3,h=1,c=0xFFFFFFFF},{x=50,y=15,w=1,h=1,c=0xFFFFFFFF},{x=58,y=15,w=1,h=1,c=0xFFFFFFFF},{x=50,y=16,w=1,h=1,c=0xFFFFFFFF},{x=58,y=16,w=1,h=1,c=0xFFFFFFFF},{x=49,y=17,w=1,h=1,c=0xFFFFFFFF},
  {x=57,y=17,w=1,h=1,c=0xFFFFFFFF},{x=49,y=18,w=1,h=1,c=0xFFFFFFFF},{x=57,y=18,w=1,h=1,c=0xFFFFFFFF},{x=48,y=19,w=1,h=1,c=0xFFFFFFFF},{x=57,y=19,w=1,h=1,c=0xFFFFFFFF},{x=48,y=20,w=1,h=1,c=0xFFFFFFFF},{x=57,y=20,w=1,h=2,c=0xFFFFFFFF},{x=45,y=22,w=3,h=1,c=0xFFFFFFFF},
  {x=56,y=22,w=1,h=1,c=0xFFFFFFFF},{x=12,y=23,w=3,h=1,c=0xFFFFFFFF},{x=44,y=23,w=5,h=1,c=0xFFFFFFFF},{x=56,y=23,w=1,h=1,c=0xFFFFFFFF},{x=11,y=24,w=5,h=1,c=0xFFFFFFFF},{x=43,y=24,w=4,h=1,c=0xFFFFFFFF},{x=56,y=24,w=1,h=1,c=0xFFFFFFFF},{x=11,y=25,w=6,h=1,c=0xFFFFFFFF},
  {x=42,y=25,w=4,h=1,c=0xFFFFFFFF},{x=55,y=25,w=1,h=1,c=0xFFFFFFFF},{x=10,y=26,w=1,h=1,c=0xFFFFFFFF},{x=14,y=26,w=5,h=1,c=0xFFFFFFFF},{x=42,y=26,w=3,h=1,c=0xFFFFFFFF},{x=55,y=26,w=1,h=1,c=0xFFFFFFFF},{x=17,y=27,w=3,h=1,c=0xFFFFFFFF},{x=41,y=27,w=3,h=1,c=0xFFFFFFFF},
  {x=54,y=27,w=1,h=1,c=0xFFFFFFFF},{x=18,y=28,w=3,h=1,c=0xFFFFFFFF},{x=26,y=28,w=1,h=1,c=0xFFFFFFFF},{x=32,y=28,w=1,h=1,c=0xFFFFFFFF},{x=39,y=28,w=4,h=1,c=0xFFFFFFFF},{x=54,y=28,w=1,h=1,c=0xFFFFFFFF},{x=9,y=29,w=1,h=1,c=0xFFFFFFFF},{x=20,y=29,w=3,h=1,c=0xFFFFFFFF},
  {x=26,y=29,w=7,h=1,c=0xFFFFFFFF},{x=38,y=29,w=4,h=1,c=0xFFFFFFFF},{x=46,y=29,w=1,h=1,c=0xFFFFFFFF},{x=53,y=29,w=1,h=1,c=0xFFFFFFFF},{x=8,y=30,w=1,h=1,c=0xFFFFFFFF},{x=14,y=30,w=1,h=1,c=0xFFFFFFFF},{x=21,y=30,w=4,h=1,c=0xFFFFFFFF},{x=27,y=30,w=5,h=1,c=0xFFFFFFFF},
  {x=35,y=30,w=4,h=1,c=0xFFFFFFFF},{x=45,y=30,w=1,h=1,c=0xFFFFFFFF},{x=52,y=30,w=1,h=1,c=0xFFFFFFFF},{x=7,y=31,w=1,h=1,c=0xFFFFFFFF},{x=14,y=31,w=1,h=1,c=0xFFFFFFFF},{x=21,y=31,w=1,h=1,c=0xFFFFFFFF},{x=22,y=31,w=2,h=1,c=0xFF000000},{x=24,y=31,w=2,h=1,c=0xFFFFFFFF},
  {x=28,y=31,w=4,h=1,c=0xFFFFFFFF},{x=33,y=31,w=4,h=1,c=0xFFFFFFFF},{x=45,y=31,w=1,h=1,c=0xFFFFFFFF},{x=51,y=31,w=1,h=1,c=0xFFFFFFFF},{x=6,y=32,w=1,h=1,c=0xFFFFFFFF},{x=14,y=32,w=1,h=1,c=0xFFFFFFFF},{x=21,y=32,w=1,h=1,c=0xFFFFFFFF},{x=22,y=32,w=2,h=1,c=0xFF000000},
  {x=24,y=32,w=1,h=1,c=0xFFFFFFFF},{x=34,y=32,w=1,h=1,c=0xFFFFFFFF},{x=35,y=32,w=1,h=1,c=0xFF000000},{x=36,y=32,w=1,h=1,c=0xFFFFFFFF},{x=45,y=32,w=1,h=1,c=0xFFFFFFFF},{x=49,y=32,w=2,h=1,c=0xFFFFFFFF},{x=6,y=33,w=1,h=1,c=0xFFFFFFFF},{x=14,y=33,w=1,h=1,c=0xFFFFFFFF},
  {x=21,y=33,w=1,h=1,c=0xFFFFFFFF},{x=22,y=33,w=2,h=1,c=0xFF000000},{x=24,y=33,w=1,h=1,c=0xFFFFFFFF},{x=27,y=33,w=4,h=1,c=0xFFFFFFFF},{x=34,y=33,w=1,h=1,c=0xFFFFFFFF},{x=35,y=33,w=1,h=1,c=0xFF000000},{x=36,y=33,w=1,h=1,c=0xFFFFFFFF},{x=44,y=33,w=2,h=1,c=0xFFFFFFFF},
  {x=47,y=33,w=2,h=1,c=0xFFFFFFFF},{x=5,y=34,w=1,h=1,c=0xFFFFFFFF},{x=14,y=34,w=1,h=1,c=0xFFFFFFFF},{x=21,y=34,w=4,h=1,c=0xFFFFFFFF},{x=27,y=34,w=5,h=1,c=0xFFFFFFFF},{x=33,y=34,w=4,h=1,c=0xFFFFFFFF},{x=43,y=34,w=3,h=1,c=0xFFFFFFFF},{x=5,y=35,w=1,h=1,c=0xFFFFFFFF},
  {x=14,y=35,w=2,h=1,c=0xFFFFFFFF},{x=17,y=35,w=5,h=1,c=0xFFFFFFFF},{x=22,y=35,w=2,h=1,c=0xFF000000},{x=24,y=35,w=1,h=1,c=0xFFFFFFFF},{x=27,y=35,w=5,h=1,c=0xFFFFFFFF},{x=33,y=35,w=2,h=1,c=0xFFFFFFFF},{x=35,y=35,w=1,h=1,c=0xFF000000},{x=36,y=35,w=1,h=1,c=0xFFFFFFFF},
  {x=41,y=35,w=3,h=1,c=0xFFFFFFFF},{x=44,y=35,w=1,h=1,c=0xFF000000},{x=45,y=35,w=1,h=1,c=0xFFFFFFFF},{x=4,y=36,w=2,h=1,c=0xFFFFFFFF},{x=14,y=36,w=3,h=1,c=0xFFFFFFFF},{x=17,y=36,w=5,h=1,c=0xFF000000},{x=22,y=36,w=1,h=1,c=0xFFFFFFFF},{x=23,y=36,w=2,h=1,c=0xFF000000},
  {x=25,y=36,w=1,h=1,c=0xFFFFFFFF},{x=27,y=36,w=5,h=1,c=0xFFFFFFFF},{x=33,y=36,w=1,h=1,c=0xFFFFFFFF},{x=34,y=36,w=2,h=1,c=0xFF000000},{x=36,y=36,w=1,h=1,c=0xFFFFFFFF},{x=39,y=36,w=3,h=1,c=0xFFFFFFFF},{x=42,y=36,w=3,h=1,c=0xFF000000},{x=45,y=36,w=1,h=1,c=0xFFFFFFFF},
  {x=4,y=37,w=2,h=1,c=0xFFFFFFFF},{x=14,y=37,w=1,h=1,c=0xFFFFFFFF},{x=15,y=37,w=7,h=1,c=0xFF000000},{x=22,y=37,w=1,h=1,c=0xFFFFFFFF},{x=23,y=37,w=1,h=1,c=0xFF000000},{x=24,y=37,w=2,h=1,c=0xFFFFFFFF},{x=27,y=37,w=5,h=1,c=0xFFFFFFFF},{x=33,y=37,w=4,h=1,c=0xFFFFFFFF},
  {x=38,y=37,w=1,h=1,c=0xFFFFFFFF},{x=39,y=37,w=6,h=1,c=0xFF000000},{x=45,y=37,w=2,h=1,c=0xFFFFFFFF},{x=4,y=38,w=2,h=1,c=0xFFFFFFFF},{x=13,y=38,w=1,h=1,c=0xFFFFFFFF},{x=14,y=38,w=8,h=1,c=0xFF000000},{x=22,y=38,w=2,h=1,c=0xFFFFFFFF},{x=24,y=38,w=1,h=1,c=0xFF000000},
  {x=25,y=38,w=1,h=1,c=0xFFFFFFFF},{x=27,y=38,w=5,h=1,c=0xFFFFFFFF},{x=33,y=38,w=1,h=1,c=0xFFFFFFFF},{x=34,y=38,w=2,h=1,c=0xFF000000},{x=36,y=38,w=1,h=1,c=0xFFFFFFFF},{x=38,y=38,w=1,h=1,c=0xFFFFFFFF},{x=39,y=38,w=7,h=1,c=0xFF000000},{x=46,y=38,w=1,h=1,c=0xFFFFFFFF},
  {x=5,y=39,w=2,h=1,c=0xFFFFFFFF},{x=13,y=39,w=1,h=1,c=0xFFFFFFFF},{x=14,y=39,w=8,h=1,c=0xFF000000},{x=22,y=39,w=1,h=1,c=0xFFFFFFFF},{x=23,y=39,w=2,h=1,c=0xFF000000},{x=25,y=39,w=1,h=1,c=0xFFFFFFFF},{x=27,y=39,w=5,h=1,c=0xFFFFFFFF},{x=33,y=39,w=1,h=1,c=0xFFFFFFFF},
  {x=34,y=39,w=2,h=1,c=0xFF000000},{x=36,y=39,w=1,h=1,c=0xFFFFFFFF},{x=38,y=39,w=1,h=1,c=0xFFFFFFFF},{x=39,y=39,w=7,h=1,c=0xFF000000},{x=46,y=39,w=1,h=1,c=0xFFFFFFFF},{x=6,y=40,w=2,h=1,c=0xFFFFFFFF},{x=13,y=40,w=1,h=1,c=0xFFFFFFFF},{x=14,y=40,w=8,h=1,c=0xFF000000},
  {x=22,y=40,w=1,h=1,c=0xFFFFFFFF},{x=23,y=40,w=1,h=1,c=0xFF000000},{x=24,y=40,w=2,h=1,c=0xFFFFFFFF},{x=27,y=40,w=5,h=1,c=0xFFFFFFFF},{x=33,y=40,w=3,h=1,c=0xFFFFFFFF},{x=36,y=40,w=1,h=1,c=0xFF000000},{x=37,y=40,w=1,h=1,c=0xFFFFFFFF},{x=38,y=40,w=8,h=1,c=0xFF000000},
  {x=46,y=40,w=1,h=1,c=0xFFFFFFFF},{x=7,y=41,w=2,h=1,c=0xFFFFFFFF},{x=13,y=41,w=1,h=1,c=0xFFFFFFFF},{x=14,y=41,w=9,h=1,c=0xFF000000},{x=23,y=41,w=1,h=1,c=0xFFFFFFFF},{x=24,y=41,w=1,h=1,c=0xFF000000},{x=25,y=41,w=1,h=1,c=0xFFFFFFFF},{x=27,y=41,w=5,h=1,c=0xFFFFFFFF},
  {x=33,y=41,w=1,h=1,c=0xFFFFFFFF},{x=34,y=41,w=1,h=1,c=0xFF000000},{x=35,y=41,w=1,h=1,c=0xFFFFFFFF},{x=36,y=41,w=1,h=1,c=0xFF000000},{x=37,y=41,w=1,h=1,c=0xFFFFFFFF},{x=38,y=41,w=8,h=1,c=0xFF000000},{x=46,y=41,w=1,h=1,c=0xFFFFFFFF},{x=8,y=42,w=3,h=1,c=0xFFFFFFFF},
  {x=13,y=42,w=1,h=1,c=0xFFFFFFFF},{x=14,y=42,w=9,h=1,c=0xFF000000},{x=23,y=42,w=1,h=1,c=0xFFFFFFFF},{x=24,y=42,w=1,h=1,c=0xFF000000},{x=25,y=42,w=1,h=1,c=0xFFFFFFFF},{x=27,y=42,w=5,h=1,c=0xFFFFFFFF},{x=33,y=42,w=1,h=1,c=0xFFFFFFFF},{x=34,y=42,w=1,h=1,c=0xFF000000},
  {x=35,y=42,w=2,h=1,c=0xFFFFFFFF},{x=37,y=42,w=9,h=1,c=0xFF000000},{x=46,y=42,w=1,h=1,c=0xFFFFFFFF},{x=9,y=43,w=2,h=1,c=0xFFFFFFFF},{x=13,y=43,w=1,h=1,c=0xFFFFFFFF},{x=14,y=43,w=9,h=1,c=0xFF000000},{x=23,y=43,w=1,h=1,c=0xFFFFFFFF},{x=24,y=43,w=1,h=1,c=0xFF000000},
  {x=25,y=43,w=1,h=1,c=0xFFFFFFFF},{x=33,y=43,w=1,h=1,c=0xFFFFFFFF},{x=34,y=43,w=1,h=1,c=0xFF000000},{x=35,y=43,w=1,h=1,c=0xFFFFFFFF},{x=36,y=43,w=9,h=1,c=0xFF000000},{x=45,y=43,w=2,h=1,c=0xFFFFFFFF},{x=10,y=44,w=1,h=1,c=0xFFFFFFFF},{x=13,y=44,w=3,h=1,c=0xFFFFFFFF},
  {x=16,y=44,w=7,h=1,c=0xFF000000},{x=23,y=44,w=13,h=1,c=0xFFFFFFFF},{x=36,y=44,w=8,h=1,c=0xFF000000},{x=44,y=44,w=3,h=1,c=0xFFFFFFFF},{x=12,y=45,w=5,h=1,c=0xFFFFFFFF},{x=17,y=45,w=6,h=1,c=0xFF000000},{x=23,y=45,w=5,h=1,c=0xFFFFFFFF},{x=34,y=45,w=12,h=1,c=0xFFFFFFFF},
  {x=14,y=46,w=9,h=1,c=0xFFFFFFFF},{x=44,y=46,w=2,h=1,c=0xFFFFFFFF},{x=37,y=48,w=2,h=1,c=0xFFFFFFFF},{x=44,y=48,w=1,h=1,c=0xFFFFFFFF},{x=15,y=49,w=1,h=1,c=0xFFFFFFFF},{x=18,y=49,w=2,h=1,c=0xFFFFFFFF},{x=37,y=49,w=2,h=1,c=0xFFFFFFFF},{x=44,y=49,w=1,h=1,c=0xFFFFFFFF},
  {x=14,y=50,w=1,h=1,c=0xFFFFFFFF},{x=18,y=50,w=2,h=1,c=0xFFFFFFFF},{x=37,y=50,w=2,h=1,c=0xFFFFFFFF},{x=45,y=50,w=1,h=1,c=0xFFFFFFFF},{x=14,y=51,w=1,h=1,c=0xFFFFFFFF},{x=17,y=51,w=2,h=1,c=0xFFFFFFFF},{x=29,y=51,w=1,h=1,c=0xFFFFFFFF},{x=37,y=51,w=2,h=1,c=0xFFFFFFFF},
  {x=45,y=51,w=1,h=1,c=0xFFFFFFFF},{x=14,y=52,w=1,h=1,c=0xFFFFFFFF},{x=17,y=52,w=2,h=1,c=0xFFFFFFFF},{x=28,y=52,w=1,h=1,c=0xFFFFFFFF},{x=30,y=52,w=1,h=1,c=0xFFFFFFFF},{x=37,y=52,w=2,h=1,c=0xFFFFFFFF},{x=45,y=52,w=1,h=1,c=0xFFFFFFFF},{x=14,y=53,w=1,h=1,c=0xFFFFFFFF},
  {x=17,y=53,w=2,h=1,c=0xFFFFFFFF},{x=28,y=53,w=1,h=1,c=0xFFFFFFFF},{x=30,y=53,w=1,h=1,c=0xFFFFFFFF},{x=37,y=53,w=3,h=1,c=0xFFFFFFFF},{x=45,y=53,w=1,h=1,c=0xFFFFFFFF},{x=14,y=54,w=1,h=1,c=0xFFFFFFFF},{x=17,y=54,w=2,h=1,c=0xFFFFFFFF},{x=28,y=54,w=1,h=1,c=0xFFFFFFFF},
  {x=30,y=54,w=1,h=1,c=0xFFFFFFFF},{x=37,y=54,w=3,h=1,c=0xFFFFFFFF},{x=46,y=54,w=1,h=1,c=0xFFFFFFFF},{x=13,y=55,w=1,h=1,c=0xFFFFFFFF},{x=16,y=55,w=2,h=1,c=0xFFFFFFFF},{x=28,y=55,w=1,h=1,c=0xFFFFFFFF},{x=31,y=55,w=1,h=1,c=0xFFFFFFFF},{x=37,y=55,w=3,h=1,c=0xFFFFFFFF},
  {x=46,y=55,w=1,h=1,c=0xFFFFFFFF},{x=13,y=56,w=1,h=1,c=0xFFFFFFFF},{x=16,y=56,w=2,h=1,c=0xFFFFFFFF},{x=27,y=56,w=2,h=1,c=0xFFFFFFFF},{x=31,y=56,w=1,h=1,c=0xFFFFFFFF},{x=37,y=56,w=3,h=1,c=0xFFFFFFFF},{x=46,y=56,w=1,h=1,c=0xFFFFFFFF},{x=13,y=57,w=1,h=1,c=0xFFFFFFFF},
  {x=16,y=57,w=2,h=1,c=0xFFFFFFFF},{x=27,y=57,w=1,h=1,c=0xFFFFFFFF},{x=31,y=57,w=1,h=1,c=0xFFFFFFFF},{x=38,y=57,w=2,h=1,c=0xFFFFFFFF},{x=46,y=57,w=1,h=1,c=0xFFFFFFFF},{x=13,y=58,w=1,h=1,c=0xFFFFFFFF},{x=16,y=58,w=2,h=1,c=0xFFFFFFFF},{x=27,y=58,w=1,h=1,c=0xFFFFFFFF},
  {x=31,y=58,w=1,h=1,c=0xFFFFFFFF},{x=38,y=58,w=2,h=1,c=0xFFFFFFFF},{x=46,y=58,w=1,h=1,c=0xFFFFFFFF},{x=13,y=59,w=1,h=1,c=0xFFFFFFFF},{x=16,y=59,w=2,h=1,c=0xFFFFFFFF},{x=27,y=59,w=1,h=1,c=0xFFFFFFFF},{x=31,y=59,w=1,h=1,c=0xFFFFFFFF},{x=38,y=59,w=2,h=1,c=0xFFFFFFFF},
  {x=46,y=59,w=1,h=1,c=0xFFFFFFFF},{x=13,y=60,w=5,h=1,c=0xFFFFFFFF},{x=27,y=60,w=1,h=1,c=0xFFFFFFFF},{x=31,y=60,w=1,h=1,c=0xFFFFFFFF},{x=38,y=60,w=3,h=1,c=0xFFFFFFFF},{x=43,y=60,w=4,h=1,c=0xFFFFFFFF},{x=18,y=61,w=9,h=1,c=0xFFFFFFFF},{x=32,y=61,w=11,h=1,c=0xFFFFFFFF},
  {x=36,y=63,w=1,h=1,c=0xFFFFFFFF},{x=12,y=64,w=4,h=1,c=0xFFFFFFFF},{x=18,y=64,w=4,h=1,c=0xFFFFFFFF},{x=36,y=64,w=7,h=1,c=0xFFFFFFFF},{x=46,y=64,w=3,h=1,c=0xFFFFFFFF},{x=11,y=65,w=7,h=1,c=0xFFFFFFFF},{x=18,y=65,w=1,h=1,c=0xFF000000},{x=19,y=65,w=3,h=1,c=0xFFFFFFFF},
  {x=35,y=65,w=7,h=1,c=0xFFFFFFFF},{x=44,y=65,w=7,h=1,c=0xFFFFFFFF},{x=10,y=66,w=9,h=1,c=0xFFFFFFFF},{x=20,y=66,w=2,h=1,c=0xFFFFFFFF},{x=35,y=66,w=6,h=1,c=0xFFFFFFFF},{x=41,y=66,w=1,h=1,c=0xFF000000},{x=42,y=66,w=10,h=1,c=0xFFFFFFFF},{x=10,y=67,w=9,h=1,c=0xFFFFFFFF},
  {x=41,y=67,w=11,h=1,c=0xFFFFFFFF},{x=10,y=68,w=10,h=1,c=0xFFFFFFFF},{x=21,y=68,w=2,h=1,c=0xFFFFFFFF},{x=34,y=68,w=6,h=1,c=0xFFFFFFFF},{x=41,y=68,w=10,h=1,c=0xFFFFFFFF},
}}

--- Sans 本体 HandDown 第 3 帧（64x70，299 个矩形）
M.sans_body_down = { w=64, h=70, rects={
  {x=45,y=25,w=3,h=1,c=0xFFFFFFFF},{x=12,y=26,w=3,h=1,c=0xFFFFFFFF},{x=44,y=26,w=5,h=1,c=0xFFFFFFFF},{x=11,y=27,w=5,h=1,c=0xFFFFFFFF},{x=43,y=27,w=4,h=1,c=0xFFFFFFFF},{x=50,y=27,w=1,h=1,c=0xFFFFFFFF},{x=11,y=28,w=6,h=1,c=0xFFFFFFFF},{x=42,y=28,w=4,h=1,c=0xFFFFFFFF},
  {x=50,y=28,w=1,h=1,c=0xFFFFFFFF},{x=10,y=29,w=1,h=1,c=0xFFFFFFFF},{x=14,y=29,w=5,h=1,c=0xFFFFFFFF},{x=42,y=29,w=3,h=1,c=0xFFFFFFFF},{x=51,y=29,w=1,h=1,c=0xFFFFFFFF},{x=17,y=30,w=3,h=1,c=0xFFFFFFFF},{x=41,y=30,w=3,h=1,c=0xFFFFFFFF},{x=51,y=30,w=1,h=1,c=0xFFFFFFFF},
  {x=18,y=31,w=3,h=1,c=0xFFFFFFFF},{x=26,y=31,w=1,h=1,c=0xFFFFFFFF},{x=32,y=31,w=1,h=1,c=0xFFFFFFFF},{x=39,y=31,w=4,h=1,c=0xFFFFFFFF},{x=52,y=31,w=1,h=1,c=0xFFFFFFFF},{x=9,y=32,w=1,h=1,c=0xFFFFFFFF},{x=20,y=32,w=3,h=1,c=0xFFFFFFFF},{x=26,y=32,w=7,h=1,c=0xFFFFFFFF},
  {x=38,y=32,w=4,h=1,c=0xFFFFFFFF},{x=46,y=32,w=1,h=1,c=0xFFFFFFFF},{x=52,y=32,w=1,h=1,c=0xFFFFFFFF},{x=8,y=33,w=1,h=1,c=0xFFFFFFFF},{x=14,y=33,w=1,h=1,c=0xFFFFFFFF},{x=21,y=33,w=4,h=1,c=0xFFFFFFFF},{x=27,y=33,w=5,h=1,c=0xFFFFFFFF},{x=35,y=33,w=4,h=1,c=0xFFFFFFFF},
  {x=45,y=33,w=1,h=1,c=0xFFFFFFFF},{x=53,y=33,w=1,h=1,c=0xFFFFFFFF},{x=7,y=34,w=1,h=1,c=0xFFFFFFFF},{x=14,y=34,w=1,h=1,c=0xFFFFFFFF},{x=21,y=34,w=1,h=1,c=0xFFFFFFFF},{x=22,y=34,w=2,h=1,c=0xFF000000},{x=24,y=34,w=2,h=1,c=0xFFFFFFFF},{x=28,y=34,w=4,h=1,c=0xFFFFFFFF},
  {x=33,y=34,w=4,h=1,c=0xFFFFFFFF},{x=45,y=34,w=1,h=1,c=0xFFFFFFFF},{x=53,y=34,w=1,h=1,c=0xFFFFFFFF},{x=6,y=35,w=1,h=1,c=0xFFFFFFFF},{x=14,y=35,w=1,h=1,c=0xFFFFFFFF},{x=21,y=35,w=1,h=1,c=0xFFFFFFFF},{x=22,y=35,w=2,h=1,c=0xFF000000},{x=24,y=35,w=1,h=1,c=0xFFFFFFFF},
  {x=34,y=35,w=1,h=1,c=0xFFFFFFFF},{x=35,y=35,w=1,h=1,c=0xFF000000},{x=36,y=35,w=1,h=1,c=0xFFFFFFFF},{x=45,y=35,w=1,h=1,c=0xFFFFFFFF},{x=54,y=35,w=1,h=1,c=0xFFFFFFFF},{x=6,y=36,w=1,h=1,c=0xFFFFFFFF},{x=14,y=36,w=1,h=1,c=0xFFFFFFFF},{x=21,y=36,w=1,h=1,c=0xFFFFFFFF},
  {x=22,y=36,w=2,h=1,c=0xFF000000},{x=24,y=36,w=1,h=1,c=0xFFFFFFFF},{x=27,y=36,w=4,h=1,c=0xFFFFFFFF},{x=34,y=36,w=1,h=1,c=0xFFFFFFFF},{x=35,y=36,w=1,h=1,c=0xFF000000},{x=36,y=36,w=1,h=1,c=0xFFFFFFFF},{x=44,y=36,w=2,h=1,c=0xFFFFFFFF},{x=54,y=36,w=1,h=1,c=0xFFFFFFFF},
  {x=5,y=37,w=1,h=1,c=0xFFFFFFFF},{x=14,y=37,w=1,h=1,c=0xFFFFFFFF},{x=21,y=37,w=4,h=1,c=0xFFFFFFFF},{x=27,y=37,w=5,h=1,c=0xFFFFFFFF},{x=33,y=37,w=4,h=1,c=0xFFFFFFFF},{x=43,y=37,w=3,h=1,c=0xFFFFFFFF},{x=54,y=37,w=1,h=1,c=0xFFFFFFFF},{x=5,y=38,w=1,h=1,c=0xFFFFFFFF},
  {x=14,y=38,w=2,h=1,c=0xFFFFFFFF},{x=17,y=38,w=5,h=1,c=0xFFFFFFFF},{x=22,y=38,w=2,h=1,c=0xFF000000},{x=24,y=38,w=1,h=1,c=0xFFFFFFFF},{x=27,y=38,w=5,h=1,c=0xFFFFFFFF},{x=33,y=38,w=2,h=1,c=0xFFFFFFFF},{x=35,y=38,w=1,h=1,c=0xFF000000},{x=36,y=38,w=1,h=1,c=0xFFFFFFFF},
  {x=41,y=38,w=3,h=1,c=0xFFFFFFFF},{x=44,y=38,w=1,h=1,c=0xFF000000},{x=45,y=38,w=1,h=1,c=0xFFFFFFFF},{x=54,y=38,w=1,h=1,c=0xFFFFFFFF},{x=4,y=39,w=2,h=1,c=0xFFFFFFFF},{x=14,y=39,w=3,h=1,c=0xFFFFFFFF},{x=17,y=39,w=5,h=1,c=0xFF000000},{x=22,y=39,w=1,h=1,c=0xFFFFFFFF},
  {x=23,y=39,w=2,h=1,c=0xFF000000},{x=25,y=39,w=1,h=1,c=0xFFFFFFFF},{x=27,y=39,w=5,h=1,c=0xFFFFFFFF},{x=33,y=39,w=1,h=1,c=0xFFFFFFFF},{x=34,y=39,w=2,h=1,c=0xFF000000},{x=36,y=39,w=1,h=1,c=0xFFFFFFFF},{x=39,y=39,w=3,h=1,c=0xFFFFFFFF},{x=42,y=39,w=3,h=1,c=0xFF000000},
  {x=45,y=39,w=1,h=1,c=0xFFFFFFFF},{x=55,y=39,w=1,h=1,c=0xFFFFFFFF},{x=4,y=40,w=2,h=1,c=0xFFFFFFFF},{x=14,y=40,w=1,h=1,c=0xFFFFFFFF},{x=15,y=40,w=7,h=1,c=0xFF000000},{x=22,y=40,w=1,h=1,c=0xFFFFFFFF},{x=23,y=40,w=1,h=1,c=0xFF000000},{x=24,y=40,w=2,h=1,c=0xFFFFFFFF},
  {x=27,y=40,w=5,h=1,c=0xFFFFFFFF},{x=33,y=40,w=4,h=1,c=0xFFFFFFFF},{x=38,y=40,w=1,h=1,c=0xFFFFFFFF},{x=39,y=40,w=6,h=1,c=0xFF000000},{x=45,y=40,w=2,h=1,c=0xFFFFFFFF},{x=55,y=40,w=1,h=1,c=0xFFFFFFFF},{x=4,y=41,w=2,h=1,c=0xFFFFFFFF},{x=13,y=41,w=1,h=1,c=0xFFFFFFFF},
  {x=14,y=41,w=8,h=1,c=0xFF000000},{x=22,y=41,w=2,h=1,c=0xFFFFFFFF},{x=24,y=41,w=1,h=1,c=0xFF000000},{x=25,y=41,w=1,h=1,c=0xFFFFFFFF},{x=27,y=41,w=5,h=1,c=0xFFFFFFFF},{x=33,y=41,w=1,h=1,c=0xFFFFFFFF},{x=34,y=41,w=2,h=1,c=0xFF000000},{x=36,y=41,w=1,h=1,c=0xFFFFFFFF},
  {x=38,y=41,w=1,h=1,c=0xFFFFFFFF},{x=39,y=41,w=7,h=1,c=0xFF000000},{x=46,y=41,w=1,h=1,c=0xFFFFFFFF},{x=55,y=41,w=1,h=1,c=0xFFFFFFFF},{x=5,y=42,w=2,h=1,c=0xFFFFFFFF},{x=13,y=42,w=1,h=1,c=0xFFFFFFFF},{x=14,y=42,w=8,h=1,c=0xFF000000},{x=22,y=42,w=1,h=1,c=0xFFFFFFFF},
  {x=23,y=42,w=2,h=1,c=0xFF000000},{x=25,y=42,w=1,h=1,c=0xFFFFFFFF},{x=27,y=42,w=5,h=1,c=0xFFFFFFFF},{x=33,y=42,w=1,h=1,c=0xFFFFFFFF},{x=34,y=42,w=2,h=1,c=0xFF000000},{x=36,y=42,w=1,h=1,c=0xFFFFFFFF},{x=38,y=42,w=1,h=1,c=0xFFFFFFFF},{x=39,y=42,w=7,h=1,c=0xFF000000},
  {x=46,y=42,w=1,h=1,c=0xFFFFFFFF},{x=55,y=42,w=1,h=1,c=0xFFFFFFFF},{x=6,y=43,w=2,h=1,c=0xFFFFFFFF},{x=13,y=43,w=1,h=1,c=0xFFFFFFFF},{x=14,y=43,w=8,h=1,c=0xFF000000},{x=22,y=43,w=1,h=1,c=0xFFFFFFFF},{x=23,y=43,w=1,h=1,c=0xFF000000},{x=24,y=43,w=2,h=1,c=0xFFFFFFFF},
  {x=27,y=43,w=5,h=1,c=0xFFFFFFFF},{x=33,y=43,w=3,h=1,c=0xFFFFFFFF},{x=36,y=43,w=1,h=1,c=0xFF000000},{x=37,y=43,w=1,h=1,c=0xFFFFFFFF},{x=38,y=43,w=8,h=1,c=0xFF000000},{x=46,y=43,w=1,h=1,c=0xFFFFFFFF},{x=56,y=43,w=1,h=1,c=0xFFFFFFFF},{x=7,y=44,w=2,h=1,c=0xFFFFFFFF},
  {x=13,y=44,w=1,h=1,c=0xFFFFFFFF},{x=14,y=44,w=9,h=1,c=0xFF000000},{x=23,y=44,w=1,h=1,c=0xFFFFFFFF},{x=24,y=44,w=1,h=1,c=0xFF000000},{x=25,y=44,w=1,h=1,c=0xFFFFFFFF},{x=27,y=44,w=5,h=1,c=0xFFFFFFFF},{x=33,y=44,w=1,h=1,c=0xFFFFFFFF},{x=34,y=44,w=1,h=1,c=0xFF000000},
  {x=35,y=44,w=1,h=1,c=0xFFFFFFFF},{x=36,y=44,w=1,h=1,c=0xFF000000},{x=37,y=44,w=1,h=1,c=0xFFFFFFFF},{x=38,y=44,w=8,h=1,c=0xFF000000},{x=46,y=44,w=1,h=1,c=0xFFFFFFFF},{x=56,y=44,w=1,h=1,c=0xFFFFFFFF},{x=8,y=45,w=3,h=1,c=0xFFFFFFFF},{x=13,y=45,w=1,h=1,c=0xFFFFFFFF},
  {x=14,y=45,w=9,h=1,c=0xFF000000},{x=23,y=45,w=1,h=1,c=0xFFFFFFFF},{x=24,y=45,w=1,h=1,c=0xFF000000},{x=25,y=45,w=1,h=1,c=0xFFFFFFFF},{x=27,y=45,w=5,h=1,c=0xFFFFFFFF},{x=33,y=45,w=1,h=1,c=0xFFFFFFFF},{x=34,y=45,w=1,h=1,c=0xFF000000},{x=35,y=45,w=2,h=1,c=0xFFFFFFFF},
  {x=37,y=45,w=9,h=1,c=0xFF000000},{x=46,y=45,w=1,h=1,c=0xFFFFFFFF},{x=56,y=45,w=1,h=1,c=0xFFFFFFFF},{x=9,y=46,w=2,h=1,c=0xFFFFFFFF},{x=13,y=46,w=1,h=1,c=0xFFFFFFFF},{x=14,y=46,w=9,h=1,c=0xFF000000},{x=23,y=46,w=1,h=1,c=0xFFFFFFFF},{x=24,y=46,w=1,h=1,c=0xFF000000},
  {x=25,y=46,w=1,h=1,c=0xFFFFFFFF},{x=33,y=46,w=1,h=1,c=0xFFFFFFFF},{x=34,y=46,w=1,h=1,c=0xFF000000},{x=35,y=46,w=1,h=1,c=0xFFFFFFFF},{x=36,y=46,w=9,h=1,c=0xFF000000},{x=45,y=46,w=2,h=1,c=0xFFFFFFFF},{x=56,y=46,w=1,h=1,c=0xFFFFFFFF},{x=10,y=47,w=1,h=1,c=0xFFFFFFFF},
  {x=13,y=47,w=3,h=1,c=0xFFFFFFFF},{x=16,y=47,w=7,h=1,c=0xFF000000},{x=23,y=47,w=13,h=1,c=0xFFFFFFFF},{x=36,y=47,w=8,h=1,c=0xFF000000},{x=44,y=47,w=3,h=1,c=0xFFFFFFFF},{x=56,y=47,w=1,h=1,c=0xFFFFFFFF},{x=12,y=48,w=5,h=1,c=0xFFFFFFFF},{x=17,y=48,w=6,h=1,c=0xFF000000},
  {x=23,y=48,w=5,h=1,c=0xFFFFFFFF},{x=34,y=48,w=12,h=1,c=0xFFFFFFFF},{x=56,y=48,w=1,h=1,c=0xFFFFFFFF},{x=14,y=49,w=9,h=1,c=0xFFFFFFFF},{x=44,y=49,w=2,h=1,c=0xFFFFFFFF},{x=48,y=49,w=1,h=1,c=0xFFFFFFFF},{x=56,y=49,w=1,h=1,c=0xFFFFFFFF},{x=48,y=50,w=1,h=1,c=0xFFFFFFFF},
  {x=56,y=50,w=1,h=1,c=0xFFFFFFFF},{x=14,y=51,w=1,h=1,c=0xFFFFFFFF},{x=17,y=51,w=2,h=1,c=0xFFFFFFFF},{x=29,y=51,w=1,h=1,c=0xFFFFFFFF},{x=37,y=51,w=2,h=1,c=0xFFFFFFFF},{x=44,y=51,w=1,h=1,c=0xFFFFFFFF},{x=48,y=51,w=1,h=1,c=0xFFFFFFFF},{x=54,y=51,w=3,h=1,c=0xFFFFFFFF},
  {x=14,y=52,w=1,h=1,c=0xFFFFFFFF},{x=17,y=52,w=2,h=1,c=0xFFFFFFFF},{x=28,y=52,w=1,h=1,c=0xFFFFFFFF},{x=30,y=52,w=1,h=1,c=0xFFFFFFFF},{x=37,y=52,w=2,h=1,c=0xFFFFFFFF},{x=44,y=52,w=1,h=1,c=0xFFFFFFFF},{x=48,y=52,w=10,h=1,c=0xFFFFFFFF},{x=14,y=53,w=1,h=1,c=0xFFFFFFFF},
  {x=17,y=53,w=2,h=1,c=0xFFFFFFFF},{x=28,y=53,w=1,h=1,c=0xFFFFFFFF},{x=30,y=53,w=1,h=1,c=0xFFFFFFFF},{x=37,y=53,w=2,h=1,c=0xFFFFFFFF},{x=45,y=53,w=1,h=1,c=0xFFFFFFFF},{x=49,y=53,w=10,h=1,c=0xFFFFFFFF},{x=14,y=54,w=1,h=1,c=0xFFFFFFFF},{x=17,y=54,w=2,h=1,c=0xFFFFFFFF},
  {x=28,y=54,w=1,h=1,c=0xFFFFFFFF},{x=30,y=54,w=1,h=1,c=0xFFFFFFFF},{x=37,y=54,w=2,h=1,c=0xFFFFFFFF},{x=45,y=54,w=1,h=1,c=0xFFFFFFFF},{x=48,y=54,w=12,h=1,c=0xFFFFFFFF},{x=13,y=55,w=1,h=1,c=0xFFFFFFFF},{x=16,y=55,w=2,h=1,c=0xFFFFFFFF},{x=28,y=55,w=1,h=1,c=0xFFFFFFFF},
  {x=31,y=55,w=1,h=1,c=0xFFFFFFFF},{x=37,y=55,w=3,h=1,c=0xFFFFFFFF},{x=45,y=55,w=1,h=1,c=0xFFFFFFFF},{x=48,y=55,w=3,h=1,c=0xFFFFFFFF},{x=54,y=55,w=7,h=1,c=0xFFFFFFFF},{x=13,y=56,w=1,h=1,c=0xFFFFFFFF},{x=16,y=56,w=2,h=1,c=0xFFFFFFFF},{x=27,y=56,w=2,h=1,c=0xFFFFFFFF},
  {x=31,y=56,w=1,h=1,c=0xFFFFFFFF},{x=37,y=56,w=3,h=1,c=0xFFFFFFFF},{x=45,y=56,w=1,h=1,c=0xFFFFFFFF},{x=55,y=56,w=6,h=1,c=0xFFFFFFFF},{x=13,y=57,w=1,h=1,c=0xFFFFFFFF},{x=16,y=57,w=2,h=1,c=0xFFFFFFFF},{x=27,y=57,w=1,h=1,c=0xFFFFFFFF},{x=31,y=57,w=1,h=1,c=0xFFFFFFFF},
  {x=37,y=57,w=3,h=1,c=0xFFFFFFFF},{x=46,y=57,w=1,h=1,c=0xFFFFFFFF},{x=57,y=57,w=3,h=1,c=0xFFFFFFFF},{x=13,y=58,w=1,h=1,c=0xFFFFFFFF},{x=16,y=58,w=2,h=1,c=0xFFFFFFFF},{x=27,y=58,w=1,h=1,c=0xFFFFFFFF},{x=31,y=58,w=1,h=1,c=0xFFFFFFFF},{x=38,y=58,w=2,h=1,c=0xFFFFFFFF},
  {x=46,y=58,w=1,h=1,c=0xFFFFFFFF},{x=13,y=59,w=1,h=1,c=0xFFFFFFFF},{x=16,y=59,w=2,h=1,c=0xFFFFFFFF},{x=27,y=59,w=1,h=1,c=0xFFFFFFFF},{x=31,y=59,w=1,h=1,c=0xFFFFFFFF},{x=38,y=59,w=2,h=1,c=0xFFFFFFFF},{x=46,y=59,w=1,h=1,c=0xFFFFFFFF},{x=13,y=60,w=5,h=1,c=0xFFFFFFFF},
  {x=27,y=60,w=1,h=1,c=0xFFFFFFFF},{x=31,y=60,w=1,h=1,c=0xFFFFFFFF},{x=38,y=60,w=3,h=1,c=0xFFFFFFFF},{x=43,y=60,w=4,h=1,c=0xFFFFFFFF},{x=18,y=61,w=9,h=1,c=0xFFFFFFFF},{x=32,y=61,w=11,h=1,c=0xFFFFFFFF},{x=36,y=63,w=1,h=1,c=0xFFFFFFFF},{x=12,y=64,w=4,h=1,c=0xFFFFFFFF},
  {x=18,y=64,w=4,h=1,c=0xFFFFFFFF},{x=36,y=64,w=7,h=1,c=0xFFFFFFFF},{x=46,y=64,w=3,h=1,c=0xFFFFFFFF},{x=11,y=65,w=7,h=1,c=0xFFFFFFFF},{x=18,y=65,w=1,h=1,c=0xFF000000},{x=19,y=65,w=3,h=1,c=0xFFFFFFFF},{x=35,y=65,w=7,h=1,c=0xFFFFFFFF},{x=44,y=65,w=7,h=1,c=0xFFFFFFFF},
  {x=10,y=66,w=9,h=1,c=0xFFFFFFFF},{x=20,y=66,w=2,h=1,c=0xFFFFFFFF},{x=35,y=66,w=6,h=1,c=0xFFFFFFFF},{x=41,y=66,w=1,h=1,c=0xFF000000},{x=42,y=66,w=10,h=1,c=0xFFFFFFFF},{x=10,y=67,w=9,h=1,c=0xFFFFFFFF},{x=41,y=67,w=11,h=1,c=0xFFFFFFFF},{x=10,y=68,w=10,h=1,c=0xFFFFFFFF},
  {x=21,y=68,w=2,h=1,c=0xFFFFFFFF},{x=34,y=68,w=6,h=1,c=0xFFFFFFFF},{x=41,y=68,w=10,h=1,c=0xFFFFFFFF},
}}

--- Sans 本体 HandLeft 第 0 帧（96x48，284 个矩形）
M.sans_body_left = { w=96, h=48, rects={
  {x=49,y=0,w=3,h=1,c=0xFFFFFFFF},{x=16,y=1,w=3,h=1,c=0xFFFFFFFF},{x=48,y=1,w=5,h=1,c=0xFFFFFFFF},{x=15,y=2,w=5,h=1,c=0xFFFFFFFF},{x=47,y=2,w=4,h=1,c=0xFFFFFFFF},{x=53,y=2,w=18,h=1,c=0xFFFFFFFF},{x=15,y=3,w=6,h=1,c=0xFFFFFFFF},{x=46,y=3,w=4,h=1,c=0xFFFFFFFF},
  {x=71,y=3,w=8,h=1,c=0xFFFFFFFF},{x=14,y=4,w=1,h=1,c=0xFFFFFFFF},{x=18,y=4,w=5,h=1,c=0xFFFFFFFF},{x=46,y=4,w=3,h=1,c=0xFFFFFFFF},{x=71,y=4,w=10,h=1,c=0xFFFFFFFF},{x=21,y=5,w=3,h=1,c=0xFFFFFFFF},{x=45,y=5,w=3,h=1,c=0xFFFFFFFF},{x=70,y=5,w=12,h=1,c=0xFFFFFFFF},
  {x=22,y=6,w=3,h=1,c=0xFFFFFFFF},{x=30,y=6,w=1,h=1,c=0xFFFFFFFF},{x=36,y=6,w=1,h=1,c=0xFFFFFFFF},{x=43,y=6,w=4,h=1,c=0xFFFFFFFF},{x=70,y=6,w=12,h=1,c=0xFFFFFFFF},{x=13,y=7,w=1,h=1,c=0xFFFFFFFF},{x=24,y=7,w=3,h=1,c=0xFFFFFFFF},{x=30,y=7,w=7,h=1,c=0xFFFFFFFF},
  {x=42,y=7,w=4,h=1,c=0xFFFFFFFF},{x=50,y=7,w=1,h=1,c=0xFFFFFFFF},{x=70,y=7,w=12,h=1,c=0xFFFFFFFF},{x=12,y=8,w=1,h=1,c=0xFFFFFFFF},{x=18,y=8,w=1,h=1,c=0xFFFFFFFF},{x=25,y=8,w=4,h=1,c=0xFFFFFFFF},{x=31,y=8,w=5,h=1,c=0xFFFFFFFF},{x=39,y=8,w=4,h=1,c=0xFFFFFFFF},
  {x=49,y=8,w=1,h=1,c=0xFFFFFFFF},{x=71,y=8,w=10,h=1,c=0xFFFFFFFF},{x=11,y=9,w=1,h=1,c=0xFFFFFFFF},{x=18,y=9,w=1,h=1,c=0xFFFFFFFF},{x=25,y=9,w=1,h=1,c=0xFFFFFFFF},{x=26,y=9,w=2,h=1,c=0xFF000000},{x=28,y=9,w=2,h=1,c=0xFFFFFFFF},{x=32,y=9,w=4,h=1,c=0xFFFFFFFF},
  {x=37,y=9,w=4,h=1,c=0xFFFFFFFF},{x=49,y=9,w=1,h=1,c=0xFFFFFFFF},{x=72,y=9,w=8,h=1,c=0xFFFFFFFF},{x=10,y=10,w=1,h=1,c=0xFFFFFFFF},{x=18,y=10,w=1,h=1,c=0xFFFFFFFF},{x=25,y=10,w=1,h=1,c=0xFFFFFFFF},{x=26,y=10,w=2,h=1,c=0xFF000000},{x=28,y=10,w=1,h=1,c=0xFFFFFFFF},
  {x=38,y=10,w=1,h=1,c=0xFFFFFFFF},{x=39,y=10,w=1,h=1,c=0xFF000000},{x=40,y=10,w=1,h=1,c=0xFFFFFFFF},{x=49,y=10,w=1,h=1,c=0xFFFFFFFF},{x=61,y=10,w=16,h=1,c=0xFFFFFFFF},{x=10,y=11,w=1,h=1,c=0xFFFFFFFF},{x=18,y=11,w=1,h=1,c=0xFFFFFFFF},{x=25,y=11,w=1,h=1,c=0xFFFFFFFF},
  {x=26,y=11,w=2,h=1,c=0xFF000000},{x=28,y=11,w=1,h=1,c=0xFFFFFFFF},{x=31,y=11,w=4,h=1,c=0xFFFFFFFF},{x=38,y=11,w=1,h=1,c=0xFFFFFFFF},{x=39,y=11,w=1,h=1,c=0xFF000000},{x=40,y=11,w=1,h=1,c=0xFFFFFFFF},{x=48,y=11,w=2,h=1,c=0xFFFFFFFF},{x=51,y=11,w=10,h=1,c=0xFFFFFFFF},
  {x=9,y=12,w=1,h=1,c=0xFFFFFFFF},{x=18,y=12,w=1,h=1,c=0xFFFFFFFF},{x=25,y=12,w=4,h=1,c=0xFFFFFFFF},{x=31,y=12,w=5,h=1,c=0xFFFFFFFF},{x=37,y=12,w=4,h=1,c=0xFFFFFFFF},{x=47,y=12,w=3,h=1,c=0xFFFFFFFF},{x=9,y=13,w=1,h=1,c=0xFFFFFFFF},{x=18,y=13,w=2,h=1,c=0xFFFFFFFF},
  {x=21,y=13,w=5,h=1,c=0xFFFFFFFF},{x=26,y=13,w=2,h=1,c=0xFF000000},{x=28,y=13,w=1,h=1,c=0xFFFFFFFF},{x=31,y=13,w=5,h=1,c=0xFFFFFFFF},{x=37,y=13,w=2,h=1,c=0xFFFFFFFF},{x=39,y=13,w=1,h=1,c=0xFF000000},{x=40,y=13,w=1,h=1,c=0xFFFFFFFF},{x=45,y=13,w=3,h=1,c=0xFFFFFFFF},
  {x=48,y=13,w=1,h=1,c=0xFF000000},{x=49,y=13,w=1,h=1,c=0xFFFFFFFF},{x=8,y=14,w=2,h=1,c=0xFFFFFFFF},{x=18,y=14,w=3,h=1,c=0xFFFFFFFF},{x=21,y=14,w=5,h=1,c=0xFF000000},{x=26,y=14,w=1,h=1,c=0xFFFFFFFF},{x=27,y=14,w=2,h=1,c=0xFF000000},{x=29,y=14,w=1,h=1,c=0xFFFFFFFF},
  {x=31,y=14,w=5,h=1,c=0xFFFFFFFF},{x=37,y=14,w=1,h=1,c=0xFFFFFFFF},{x=38,y=14,w=2,h=1,c=0xFF000000},{x=40,y=14,w=1,h=1,c=0xFFFFFFFF},{x=43,y=14,w=3,h=1,c=0xFFFFFFFF},{x=46,y=14,w=3,h=1,c=0xFF000000},{x=49,y=14,w=1,h=1,c=0xFFFFFFFF},{x=8,y=15,w=2,h=1,c=0xFFFFFFFF},
  {x=18,y=15,w=1,h=1,c=0xFFFFFFFF},{x=19,y=15,w=7,h=1,c=0xFF000000},{x=26,y=15,w=1,h=1,c=0xFFFFFFFF},{x=27,y=15,w=1,h=1,c=0xFF000000},{x=28,y=15,w=2,h=1,c=0xFFFFFFFF},{x=31,y=15,w=5,h=1,c=0xFFFFFFFF},{x=37,y=15,w=4,h=1,c=0xFFFFFFFF},{x=42,y=15,w=1,h=1,c=0xFFFFFFFF},
  {x=43,y=15,w=6,h=1,c=0xFF000000},{x=49,y=15,w=2,h=1,c=0xFFFFFFFF},{x=8,y=16,w=2,h=1,c=0xFFFFFFFF},{x=17,y=16,w=1,h=1,c=0xFFFFFFFF},{x=18,y=16,w=8,h=1,c=0xFF000000},{x=26,y=16,w=2,h=1,c=0xFFFFFFFF},{x=28,y=16,w=1,h=1,c=0xFF000000},{x=29,y=16,w=1,h=1,c=0xFFFFFFFF},
  {x=31,y=16,w=5,h=1,c=0xFFFFFFFF},{x=37,y=16,w=1,h=1,c=0xFFFFFFFF},{x=38,y=16,w=2,h=1,c=0xFF000000},{x=40,y=16,w=1,h=1,c=0xFFFFFFFF},{x=42,y=16,w=1,h=1,c=0xFFFFFFFF},{x=43,y=16,w=7,h=1,c=0xFF000000},{x=50,y=16,w=1,h=1,c=0xFFFFFFFF},{x=9,y=17,w=2,h=1,c=0xFFFFFFFF},
  {x=17,y=17,w=1,h=1,c=0xFFFFFFFF},{x=18,y=17,w=8,h=1,c=0xFF000000},{x=26,y=17,w=1,h=1,c=0xFFFFFFFF},{x=27,y=17,w=2,h=1,c=0xFF000000},{x=29,y=17,w=1,h=1,c=0xFFFFFFFF},{x=31,y=17,w=5,h=1,c=0xFFFFFFFF},{x=37,y=17,w=1,h=1,c=0xFFFFFFFF},{x=38,y=17,w=2,h=1,c=0xFF000000},
  {x=40,y=17,w=1,h=1,c=0xFFFFFFFF},{x=42,y=17,w=1,h=1,c=0xFFFFFFFF},{x=43,y=17,w=7,h=1,c=0xFF000000},{x=50,y=17,w=1,h=1,c=0xFFFFFFFF},{x=10,y=18,w=2,h=1,c=0xFFFFFFFF},{x=17,y=18,w=1,h=1,c=0xFFFFFFFF},{x=18,y=18,w=8,h=1,c=0xFF000000},{x=26,y=18,w=1,h=1,c=0xFFFFFFFF},
  {x=27,y=18,w=1,h=1,c=0xFF000000},{x=28,y=18,w=2,h=1,c=0xFFFFFFFF},{x=31,y=18,w=5,h=1,c=0xFFFFFFFF},{x=37,y=18,w=3,h=1,c=0xFFFFFFFF},{x=40,y=18,w=1,h=1,c=0xFF000000},{x=41,y=18,w=1,h=1,c=0xFFFFFFFF},{x=42,y=18,w=8,h=1,c=0xFF000000},{x=50,y=18,w=1,h=1,c=0xFFFFFFFF},
  {x=11,y=19,w=2,h=1,c=0xFFFFFFFF},{x=17,y=19,w=1,h=1,c=0xFFFFFFFF},{x=18,y=19,w=9,h=1,c=0xFF000000},{x=27,y=19,w=1,h=1,c=0xFFFFFFFF},{x=28,y=19,w=1,h=1,c=0xFF000000},{x=29,y=19,w=1,h=1,c=0xFFFFFFFF},{x=31,y=19,w=5,h=1,c=0xFFFFFFFF},{x=37,y=19,w=1,h=1,c=0xFFFFFFFF},
  {x=38,y=19,w=1,h=1,c=0xFF000000},{x=39,y=19,w=1,h=1,c=0xFFFFFFFF},{x=40,y=19,w=1,h=1,c=0xFF000000},{x=41,y=19,w=1,h=1,c=0xFFFFFFFF},{x=42,y=19,w=8,h=1,c=0xFF000000},{x=50,y=19,w=1,h=1,c=0xFFFFFFFF},{x=12,y=20,w=3,h=1,c=0xFFFFFFFF},{x=17,y=20,w=1,h=1,c=0xFFFFFFFF},
  {x=18,y=20,w=9,h=1,c=0xFF000000},{x=27,y=20,w=1,h=1,c=0xFFFFFFFF},{x=28,y=20,w=1,h=1,c=0xFF000000},{x=29,y=20,w=1,h=1,c=0xFFFFFFFF},{x=31,y=20,w=5,h=1,c=0xFFFFFFFF},{x=37,y=20,w=1,h=1,c=0xFFFFFFFF},{x=38,y=20,w=1,h=1,c=0xFF000000},{x=39,y=20,w=2,h=1,c=0xFFFFFFFF},
  {x=41,y=20,w=9,h=1,c=0xFF000000},{x=50,y=20,w=1,h=1,c=0xFFFFFFFF},{x=13,y=21,w=2,h=1,c=0xFFFFFFFF},{x=17,y=21,w=1,h=1,c=0xFFFFFFFF},{x=18,y=21,w=9,h=1,c=0xFF000000},{x=27,y=21,w=1,h=1,c=0xFFFFFFFF},{x=28,y=21,w=1,h=1,c=0xFF000000},{x=29,y=21,w=1,h=1,c=0xFFFFFFFF},
  {x=37,y=21,w=1,h=1,c=0xFFFFFFFF},{x=38,y=21,w=1,h=1,c=0xFF000000},{x=39,y=21,w=1,h=1,c=0xFFFFFFFF},{x=40,y=21,w=9,h=1,c=0xFF000000},{x=49,y=21,w=2,h=1,c=0xFFFFFFFF},{x=14,y=22,w=1,h=1,c=0xFFFFFFFF},{x=17,y=22,w=3,h=1,c=0xFFFFFFFF},{x=20,y=22,w=7,h=1,c=0xFF000000},
  {x=27,y=22,w=13,h=1,c=0xFFFFFFFF},{x=40,y=22,w=8,h=1,c=0xFF000000},{x=48,y=22,w=3,h=1,c=0xFFFFFFFF},{x=16,y=23,w=5,h=1,c=0xFFFFFFFF},{x=21,y=23,w=6,h=1,c=0xFF000000},{x=27,y=23,w=5,h=1,c=0xFFFFFFFF},{x=38,y=23,w=12,h=1,c=0xFFFFFFFF},{x=18,y=24,w=9,h=1,c=0xFFFFFFFF},
  {x=48,y=24,w=2,h=1,c=0xFFFFFFFF},{x=40,y=26,w=2,h=1,c=0xFFFFFFFF},{x=47,y=26,w=1,h=1,c=0xFFFFFFFF},{x=18,y=27,w=1,h=1,c=0xFFFFFFFF},{x=21,y=27,w=2,h=1,c=0xFFFFFFFF},{x=40,y=27,w=2,h=1,c=0xFFFFFFFF},{x=47,y=27,w=1,h=1,c=0xFFFFFFFF},{x=17,y=28,w=1,h=1,c=0xFFFFFFFF},
  {x=21,y=28,w=2,h=1,c=0xFFFFFFFF},{x=40,y=28,w=2,h=1,c=0xFFFFFFFF},{x=48,y=28,w=1,h=1,c=0xFFFFFFFF},{x=17,y=29,w=1,h=1,c=0xFFFFFFFF},{x=20,y=29,w=2,h=1,c=0xFFFFFFFF},{x=32,y=29,w=1,h=1,c=0xFFFFFFFF},{x=40,y=29,w=2,h=1,c=0xFFFFFFFF},{x=48,y=29,w=1,h=1,c=0xFFFFFFFF},
  {x=17,y=30,w=1,h=1,c=0xFFFFFFFF},{x=20,y=30,w=2,h=1,c=0xFFFFFFFF},{x=31,y=30,w=1,h=1,c=0xFFFFFFFF},{x=33,y=30,w=1,h=1,c=0xFFFFFFFF},{x=40,y=30,w=2,h=1,c=0xFFFFFFFF},{x=48,y=30,w=1,h=1,c=0xFFFFFFFF},{x=17,y=31,w=1,h=1,c=0xFFFFFFFF},{x=20,y=31,w=2,h=1,c=0xFFFFFFFF},
  {x=31,y=31,w=1,h=1,c=0xFFFFFFFF},{x=33,y=31,w=1,h=1,c=0xFFFFFFFF},{x=40,y=31,w=3,h=1,c=0xFFFFFFFF},{x=48,y=31,w=1,h=1,c=0xFFFFFFFF},{x=17,y=32,w=1,h=1,c=0xFFFFFFFF},{x=20,y=32,w=2,h=1,c=0xFFFFFFFF},{x=31,y=32,w=1,h=1,c=0xFFFFFFFF},{x=33,y=32,w=1,h=1,c=0xFFFFFFFF},
  {x=40,y=32,w=3,h=1,c=0xFFFFFFFF},{x=49,y=32,w=1,h=1,c=0xFFFFFFFF},{x=16,y=33,w=1,h=1,c=0xFFFFFFFF},{x=19,y=33,w=2,h=1,c=0xFFFFFFFF},{x=31,y=33,w=1,h=1,c=0xFFFFFFFF},{x=34,y=33,w=1,h=1,c=0xFFFFFFFF},{x=40,y=33,w=3,h=1,c=0xFFFFFFFF},{x=49,y=33,w=1,h=1,c=0xFFFFFFFF},
  {x=16,y=34,w=1,h=1,c=0xFFFFFFFF},{x=19,y=34,w=2,h=1,c=0xFFFFFFFF},{x=30,y=34,w=2,h=1,c=0xFFFFFFFF},{x=34,y=34,w=1,h=1,c=0xFFFFFFFF},{x=40,y=34,w=3,h=1,c=0xFFFFFFFF},{x=49,y=34,w=1,h=1,c=0xFFFFFFFF},{x=16,y=35,w=1,h=1,c=0xFFFFFFFF},{x=19,y=35,w=2,h=1,c=0xFFFFFFFF},
  {x=30,y=35,w=1,h=1,c=0xFFFFFFFF},{x=34,y=35,w=1,h=1,c=0xFFFFFFFF},{x=41,y=35,w=2,h=1,c=0xFFFFFFFF},{x=49,y=35,w=1,h=1,c=0xFFFFFFFF},{x=16,y=36,w=1,h=1,c=0xFFFFFFFF},{x=19,y=36,w=2,h=1,c=0xFFFFFFFF},{x=30,y=36,w=1,h=1,c=0xFFFFFFFF},{x=34,y=36,w=1,h=1,c=0xFFFFFFFF},
  {x=41,y=36,w=2,h=1,c=0xFFFFFFFF},{x=49,y=36,w=1,h=1,c=0xFFFFFFFF},{x=16,y=37,w=1,h=1,c=0xFFFFFFFF},{x=19,y=37,w=2,h=1,c=0xFFFFFFFF},{x=30,y=37,w=1,h=1,c=0xFFFFFFFF},{x=34,y=37,w=1,h=1,c=0xFFFFFFFF},{x=41,y=37,w=2,h=1,c=0xFFFFFFFF},{x=49,y=37,w=1,h=1,c=0xFFFFFFFF},
  {x=16,y=38,w=5,h=1,c=0xFFFFFFFF},{x=30,y=38,w=1,h=1,c=0xFFFFFFFF},{x=34,y=38,w=1,h=1,c=0xFFFFFFFF},{x=41,y=38,w=3,h=1,c=0xFFFFFFFF},{x=46,y=38,w=4,h=1,c=0xFFFFFFFF},{x=21,y=39,w=9,h=1,c=0xFFFFFFFF},{x=35,y=39,w=11,h=1,c=0xFFFFFFFF},{x=39,y=41,w=1,h=1,c=0xFFFFFFFF},
  {x=15,y=42,w=4,h=1,c=0xFFFFFFFF},{x=21,y=42,w=4,h=1,c=0xFFFFFFFF},{x=39,y=42,w=7,h=1,c=0xFFFFFFFF},{x=49,y=42,w=3,h=1,c=0xFFFFFFFF},{x=14,y=43,w=7,h=1,c=0xFFFFFFFF},{x=21,y=43,w=1,h=1,c=0xFF000000},{x=22,y=43,w=3,h=1,c=0xFFFFFFFF},{x=38,y=43,w=7,h=1,c=0xFFFFFFFF},
  {x=47,y=43,w=7,h=1,c=0xFFFFFFFF},{x=13,y=44,w=9,h=1,c=0xFFFFFFFF},{x=23,y=44,w=2,h=1,c=0xFFFFFFFF},{x=38,y=44,w=6,h=1,c=0xFFFFFFFF},{x=44,y=44,w=1,h=1,c=0xFF000000},{x=45,y=44,w=10,h=1,c=0xFFFFFFFF},{x=13,y=45,w=9,h=1,c=0xFFFFFFFF},{x=44,y=45,w=11,h=1,c=0xFFFFFFFF},
  {x=13,y=46,w=10,h=1,c=0xFFFFFFFF},{x=24,y=46,w=2,h=1,c=0xFFFFFFFF},{x=37,y=46,w=6,h=1,c=0xFFFFFFFF},{x=44,y=46,w=10,h=1,c=0xFFFFFFFF},
}}

--- Sans 本体 HandRight 第 4 帧（96x48，284 个矩形）
M.sans_body_right = { w=96, h=48, rects={
  {x=49,y=0,w=3,h=1,c=0xFFFFFFFF},{x=16,y=1,w=3,h=1,c=0xFFFFFFFF},{x=48,y=1,w=5,h=1,c=0xFFFFFFFF},{x=15,y=2,w=5,h=1,c=0xFFFFFFFF},{x=47,y=2,w=4,h=1,c=0xFFFFFFFF},{x=53,y=2,w=18,h=1,c=0xFFFFFFFF},{x=15,y=3,w=6,h=1,c=0xFFFFFFFF},{x=46,y=3,w=4,h=1,c=0xFFFFFFFF},
  {x=71,y=3,w=8,h=1,c=0xFFFFFFFF},{x=14,y=4,w=1,h=1,c=0xFFFFFFFF},{x=18,y=4,w=5,h=1,c=0xFFFFFFFF},{x=46,y=4,w=3,h=1,c=0xFFFFFFFF},{x=71,y=4,w=10,h=1,c=0xFFFFFFFF},{x=21,y=5,w=3,h=1,c=0xFFFFFFFF},{x=45,y=5,w=3,h=1,c=0xFFFFFFFF},{x=70,y=5,w=12,h=1,c=0xFFFFFFFF},
  {x=22,y=6,w=3,h=1,c=0xFFFFFFFF},{x=30,y=6,w=1,h=1,c=0xFFFFFFFF},{x=36,y=6,w=1,h=1,c=0xFFFFFFFF},{x=43,y=6,w=4,h=1,c=0xFFFFFFFF},{x=70,y=6,w=12,h=1,c=0xFFFFFFFF},{x=13,y=7,w=1,h=1,c=0xFFFFFFFF},{x=24,y=7,w=3,h=1,c=0xFFFFFFFF},{x=30,y=7,w=7,h=1,c=0xFFFFFFFF},
  {x=42,y=7,w=4,h=1,c=0xFFFFFFFF},{x=50,y=7,w=1,h=1,c=0xFFFFFFFF},{x=70,y=7,w=12,h=1,c=0xFFFFFFFF},{x=12,y=8,w=1,h=1,c=0xFFFFFFFF},{x=18,y=8,w=1,h=1,c=0xFFFFFFFF},{x=25,y=8,w=4,h=1,c=0xFFFFFFFF},{x=31,y=8,w=5,h=1,c=0xFFFFFFFF},{x=39,y=8,w=4,h=1,c=0xFFFFFFFF},
  {x=49,y=8,w=1,h=1,c=0xFFFFFFFF},{x=71,y=8,w=10,h=1,c=0xFFFFFFFF},{x=11,y=9,w=1,h=1,c=0xFFFFFFFF},{x=18,y=9,w=1,h=1,c=0xFFFFFFFF},{x=25,y=9,w=1,h=1,c=0xFFFFFFFF},{x=26,y=9,w=2,h=1,c=0xFF000000},{x=28,y=9,w=2,h=1,c=0xFFFFFFFF},{x=32,y=9,w=4,h=1,c=0xFFFFFFFF},
  {x=37,y=9,w=4,h=1,c=0xFFFFFFFF},{x=49,y=9,w=1,h=1,c=0xFFFFFFFF},{x=72,y=9,w=8,h=1,c=0xFFFFFFFF},{x=10,y=10,w=1,h=1,c=0xFFFFFFFF},{x=18,y=10,w=1,h=1,c=0xFFFFFFFF},{x=25,y=10,w=1,h=1,c=0xFFFFFFFF},{x=26,y=10,w=2,h=1,c=0xFF000000},{x=28,y=10,w=1,h=1,c=0xFFFFFFFF},
  {x=38,y=10,w=1,h=1,c=0xFFFFFFFF},{x=39,y=10,w=1,h=1,c=0xFF000000},{x=40,y=10,w=1,h=1,c=0xFFFFFFFF},{x=49,y=10,w=1,h=1,c=0xFFFFFFFF},{x=61,y=10,w=16,h=1,c=0xFFFFFFFF},{x=10,y=11,w=1,h=1,c=0xFFFFFFFF},{x=18,y=11,w=1,h=1,c=0xFFFFFFFF},{x=25,y=11,w=1,h=1,c=0xFFFFFFFF},
  {x=26,y=11,w=2,h=1,c=0xFF000000},{x=28,y=11,w=1,h=1,c=0xFFFFFFFF},{x=31,y=11,w=4,h=1,c=0xFFFFFFFF},{x=38,y=11,w=1,h=1,c=0xFFFFFFFF},{x=39,y=11,w=1,h=1,c=0xFF000000},{x=40,y=11,w=1,h=1,c=0xFFFFFFFF},{x=48,y=11,w=2,h=1,c=0xFFFFFFFF},{x=51,y=11,w=10,h=1,c=0xFFFFFFFF},
  {x=9,y=12,w=1,h=1,c=0xFFFFFFFF},{x=18,y=12,w=1,h=1,c=0xFFFFFFFF},{x=25,y=12,w=4,h=1,c=0xFFFFFFFF},{x=31,y=12,w=5,h=1,c=0xFFFFFFFF},{x=37,y=12,w=4,h=1,c=0xFFFFFFFF},{x=47,y=12,w=3,h=1,c=0xFFFFFFFF},{x=9,y=13,w=1,h=1,c=0xFFFFFFFF},{x=18,y=13,w=2,h=1,c=0xFFFFFFFF},
  {x=21,y=13,w=5,h=1,c=0xFFFFFFFF},{x=26,y=13,w=2,h=1,c=0xFF000000},{x=28,y=13,w=1,h=1,c=0xFFFFFFFF},{x=31,y=13,w=5,h=1,c=0xFFFFFFFF},{x=37,y=13,w=2,h=1,c=0xFFFFFFFF},{x=39,y=13,w=1,h=1,c=0xFF000000},{x=40,y=13,w=1,h=1,c=0xFFFFFFFF},{x=45,y=13,w=3,h=1,c=0xFFFFFFFF},
  {x=48,y=13,w=1,h=1,c=0xFF000000},{x=49,y=13,w=1,h=1,c=0xFFFFFFFF},{x=8,y=14,w=2,h=1,c=0xFFFFFFFF},{x=18,y=14,w=3,h=1,c=0xFFFFFFFF},{x=21,y=14,w=5,h=1,c=0xFF000000},{x=26,y=14,w=1,h=1,c=0xFFFFFFFF},{x=27,y=14,w=2,h=1,c=0xFF000000},{x=29,y=14,w=1,h=1,c=0xFFFFFFFF},
  {x=31,y=14,w=5,h=1,c=0xFFFFFFFF},{x=37,y=14,w=1,h=1,c=0xFFFFFFFF},{x=38,y=14,w=2,h=1,c=0xFF000000},{x=40,y=14,w=1,h=1,c=0xFFFFFFFF},{x=43,y=14,w=3,h=1,c=0xFFFFFFFF},{x=46,y=14,w=3,h=1,c=0xFF000000},{x=49,y=14,w=1,h=1,c=0xFFFFFFFF},{x=8,y=15,w=2,h=1,c=0xFFFFFFFF},
  {x=18,y=15,w=1,h=1,c=0xFFFFFFFF},{x=19,y=15,w=7,h=1,c=0xFF000000},{x=26,y=15,w=1,h=1,c=0xFFFFFFFF},{x=27,y=15,w=1,h=1,c=0xFF000000},{x=28,y=15,w=2,h=1,c=0xFFFFFFFF},{x=31,y=15,w=5,h=1,c=0xFFFFFFFF},{x=37,y=15,w=4,h=1,c=0xFFFFFFFF},{x=42,y=15,w=1,h=1,c=0xFFFFFFFF},
  {x=43,y=15,w=6,h=1,c=0xFF000000},{x=49,y=15,w=2,h=1,c=0xFFFFFFFF},{x=8,y=16,w=2,h=1,c=0xFFFFFFFF},{x=17,y=16,w=1,h=1,c=0xFFFFFFFF},{x=18,y=16,w=8,h=1,c=0xFF000000},{x=26,y=16,w=2,h=1,c=0xFFFFFFFF},{x=28,y=16,w=1,h=1,c=0xFF000000},{x=29,y=16,w=1,h=1,c=0xFFFFFFFF},
  {x=31,y=16,w=5,h=1,c=0xFFFFFFFF},{x=37,y=16,w=1,h=1,c=0xFFFFFFFF},{x=38,y=16,w=2,h=1,c=0xFF000000},{x=40,y=16,w=1,h=1,c=0xFFFFFFFF},{x=42,y=16,w=1,h=1,c=0xFFFFFFFF},{x=43,y=16,w=7,h=1,c=0xFF000000},{x=50,y=16,w=1,h=1,c=0xFFFFFFFF},{x=9,y=17,w=2,h=1,c=0xFFFFFFFF},
  {x=17,y=17,w=1,h=1,c=0xFFFFFFFF},{x=18,y=17,w=8,h=1,c=0xFF000000},{x=26,y=17,w=1,h=1,c=0xFFFFFFFF},{x=27,y=17,w=2,h=1,c=0xFF000000},{x=29,y=17,w=1,h=1,c=0xFFFFFFFF},{x=31,y=17,w=5,h=1,c=0xFFFFFFFF},{x=37,y=17,w=1,h=1,c=0xFFFFFFFF},{x=38,y=17,w=2,h=1,c=0xFF000000},
  {x=40,y=17,w=1,h=1,c=0xFFFFFFFF},{x=42,y=17,w=1,h=1,c=0xFFFFFFFF},{x=43,y=17,w=7,h=1,c=0xFF000000},{x=50,y=17,w=1,h=1,c=0xFFFFFFFF},{x=10,y=18,w=2,h=1,c=0xFFFFFFFF},{x=17,y=18,w=1,h=1,c=0xFFFFFFFF},{x=18,y=18,w=8,h=1,c=0xFF000000},{x=26,y=18,w=1,h=1,c=0xFFFFFFFF},
  {x=27,y=18,w=1,h=1,c=0xFF000000},{x=28,y=18,w=2,h=1,c=0xFFFFFFFF},{x=31,y=18,w=5,h=1,c=0xFFFFFFFF},{x=37,y=18,w=3,h=1,c=0xFFFFFFFF},{x=40,y=18,w=1,h=1,c=0xFF000000},{x=41,y=18,w=1,h=1,c=0xFFFFFFFF},{x=42,y=18,w=8,h=1,c=0xFF000000},{x=50,y=18,w=1,h=1,c=0xFFFFFFFF},
  {x=11,y=19,w=2,h=1,c=0xFFFFFFFF},{x=17,y=19,w=1,h=1,c=0xFFFFFFFF},{x=18,y=19,w=9,h=1,c=0xFF000000},{x=27,y=19,w=1,h=1,c=0xFFFFFFFF},{x=28,y=19,w=1,h=1,c=0xFF000000},{x=29,y=19,w=1,h=1,c=0xFFFFFFFF},{x=31,y=19,w=5,h=1,c=0xFFFFFFFF},{x=37,y=19,w=1,h=1,c=0xFFFFFFFF},
  {x=38,y=19,w=1,h=1,c=0xFF000000},{x=39,y=19,w=1,h=1,c=0xFFFFFFFF},{x=40,y=19,w=1,h=1,c=0xFF000000},{x=41,y=19,w=1,h=1,c=0xFFFFFFFF},{x=42,y=19,w=8,h=1,c=0xFF000000},{x=50,y=19,w=1,h=1,c=0xFFFFFFFF},{x=12,y=20,w=3,h=1,c=0xFFFFFFFF},{x=17,y=20,w=1,h=1,c=0xFFFFFFFF},
  {x=18,y=20,w=9,h=1,c=0xFF000000},{x=27,y=20,w=1,h=1,c=0xFFFFFFFF},{x=28,y=20,w=1,h=1,c=0xFF000000},{x=29,y=20,w=1,h=1,c=0xFFFFFFFF},{x=31,y=20,w=5,h=1,c=0xFFFFFFFF},{x=37,y=20,w=1,h=1,c=0xFFFFFFFF},{x=38,y=20,w=1,h=1,c=0xFF000000},{x=39,y=20,w=2,h=1,c=0xFFFFFFFF},
  {x=41,y=20,w=9,h=1,c=0xFF000000},{x=50,y=20,w=1,h=1,c=0xFFFFFFFF},{x=13,y=21,w=2,h=1,c=0xFFFFFFFF},{x=17,y=21,w=1,h=1,c=0xFFFFFFFF},{x=18,y=21,w=9,h=1,c=0xFF000000},{x=27,y=21,w=1,h=1,c=0xFFFFFFFF},{x=28,y=21,w=1,h=1,c=0xFF000000},{x=29,y=21,w=1,h=1,c=0xFFFFFFFF},
  {x=37,y=21,w=1,h=1,c=0xFFFFFFFF},{x=38,y=21,w=1,h=1,c=0xFF000000},{x=39,y=21,w=1,h=1,c=0xFFFFFFFF},{x=40,y=21,w=9,h=1,c=0xFF000000},{x=49,y=21,w=2,h=1,c=0xFFFFFFFF},{x=14,y=22,w=1,h=1,c=0xFFFFFFFF},{x=17,y=22,w=3,h=1,c=0xFFFFFFFF},{x=20,y=22,w=7,h=1,c=0xFF000000},
  {x=27,y=22,w=13,h=1,c=0xFFFFFFFF},{x=40,y=22,w=8,h=1,c=0xFF000000},{x=48,y=22,w=3,h=1,c=0xFFFFFFFF},{x=16,y=23,w=5,h=1,c=0xFFFFFFFF},{x=21,y=23,w=6,h=1,c=0xFF000000},{x=27,y=23,w=5,h=1,c=0xFFFFFFFF},{x=38,y=23,w=12,h=1,c=0xFFFFFFFF},{x=18,y=24,w=9,h=1,c=0xFFFFFFFF},
  {x=48,y=24,w=2,h=1,c=0xFFFFFFFF},{x=40,y=26,w=2,h=1,c=0xFFFFFFFF},{x=47,y=26,w=1,h=1,c=0xFFFFFFFF},{x=18,y=27,w=1,h=1,c=0xFFFFFFFF},{x=21,y=27,w=2,h=1,c=0xFFFFFFFF},{x=40,y=27,w=2,h=1,c=0xFFFFFFFF},{x=47,y=27,w=1,h=1,c=0xFFFFFFFF},{x=17,y=28,w=1,h=1,c=0xFFFFFFFF},
  {x=21,y=28,w=2,h=1,c=0xFFFFFFFF},{x=40,y=28,w=2,h=1,c=0xFFFFFFFF},{x=48,y=28,w=1,h=1,c=0xFFFFFFFF},{x=17,y=29,w=1,h=1,c=0xFFFFFFFF},{x=20,y=29,w=2,h=1,c=0xFFFFFFFF},{x=32,y=29,w=1,h=1,c=0xFFFFFFFF},{x=40,y=29,w=2,h=1,c=0xFFFFFFFF},{x=48,y=29,w=1,h=1,c=0xFFFFFFFF},
  {x=17,y=30,w=1,h=1,c=0xFFFFFFFF},{x=20,y=30,w=2,h=1,c=0xFFFFFFFF},{x=31,y=30,w=1,h=1,c=0xFFFFFFFF},{x=33,y=30,w=1,h=1,c=0xFFFFFFFF},{x=40,y=30,w=2,h=1,c=0xFFFFFFFF},{x=48,y=30,w=1,h=1,c=0xFFFFFFFF},{x=17,y=31,w=1,h=1,c=0xFFFFFFFF},{x=20,y=31,w=2,h=1,c=0xFFFFFFFF},
  {x=31,y=31,w=1,h=1,c=0xFFFFFFFF},{x=33,y=31,w=1,h=1,c=0xFFFFFFFF},{x=40,y=31,w=3,h=1,c=0xFFFFFFFF},{x=48,y=31,w=1,h=1,c=0xFFFFFFFF},{x=17,y=32,w=1,h=1,c=0xFFFFFFFF},{x=20,y=32,w=2,h=1,c=0xFFFFFFFF},{x=31,y=32,w=1,h=1,c=0xFFFFFFFF},{x=33,y=32,w=1,h=1,c=0xFFFFFFFF},
  {x=40,y=32,w=3,h=1,c=0xFFFFFFFF},{x=49,y=32,w=1,h=1,c=0xFFFFFFFF},{x=16,y=33,w=1,h=1,c=0xFFFFFFFF},{x=19,y=33,w=2,h=1,c=0xFFFFFFFF},{x=31,y=33,w=1,h=1,c=0xFFFFFFFF},{x=34,y=33,w=1,h=1,c=0xFFFFFFFF},{x=40,y=33,w=3,h=1,c=0xFFFFFFFF},{x=49,y=33,w=1,h=1,c=0xFFFFFFFF},
  {x=16,y=34,w=1,h=1,c=0xFFFFFFFF},{x=19,y=34,w=2,h=1,c=0xFFFFFFFF},{x=30,y=34,w=2,h=1,c=0xFFFFFFFF},{x=34,y=34,w=1,h=1,c=0xFFFFFFFF},{x=40,y=34,w=3,h=1,c=0xFFFFFFFF},{x=49,y=34,w=1,h=1,c=0xFFFFFFFF},{x=16,y=35,w=1,h=1,c=0xFFFFFFFF},{x=19,y=35,w=2,h=1,c=0xFFFFFFFF},
  {x=30,y=35,w=1,h=1,c=0xFFFFFFFF},{x=34,y=35,w=1,h=1,c=0xFFFFFFFF},{x=41,y=35,w=2,h=1,c=0xFFFFFFFF},{x=49,y=35,w=1,h=1,c=0xFFFFFFFF},{x=16,y=36,w=1,h=1,c=0xFFFFFFFF},{x=19,y=36,w=2,h=1,c=0xFFFFFFFF},{x=30,y=36,w=1,h=1,c=0xFFFFFFFF},{x=34,y=36,w=1,h=1,c=0xFFFFFFFF},
  {x=41,y=36,w=2,h=1,c=0xFFFFFFFF},{x=49,y=36,w=1,h=1,c=0xFFFFFFFF},{x=16,y=37,w=1,h=1,c=0xFFFFFFFF},{x=19,y=37,w=2,h=1,c=0xFFFFFFFF},{x=30,y=37,w=1,h=1,c=0xFFFFFFFF},{x=34,y=37,w=1,h=1,c=0xFFFFFFFF},{x=41,y=37,w=2,h=1,c=0xFFFFFFFF},{x=49,y=37,w=1,h=1,c=0xFFFFFFFF},
  {x=16,y=38,w=5,h=1,c=0xFFFFFFFF},{x=30,y=38,w=1,h=1,c=0xFFFFFFFF},{x=34,y=38,w=1,h=1,c=0xFFFFFFFF},{x=41,y=38,w=3,h=1,c=0xFFFFFFFF},{x=46,y=38,w=4,h=1,c=0xFFFFFFFF},{x=21,y=39,w=9,h=1,c=0xFFFFFFFF},{x=35,y=39,w=11,h=1,c=0xFFFFFFFF},{x=39,y=41,w=1,h=1,c=0xFFFFFFFF},
  {x=15,y=42,w=4,h=1,c=0xFFFFFFFF},{x=21,y=42,w=4,h=1,c=0xFFFFFFFF},{x=39,y=42,w=7,h=1,c=0xFFFFFFFF},{x=49,y=42,w=3,h=1,c=0xFFFFFFFF},{x=14,y=43,w=7,h=1,c=0xFFFFFFFF},{x=21,y=43,w=1,h=1,c=0xFF000000},{x=22,y=43,w=3,h=1,c=0xFFFFFFFF},{x=38,y=43,w=7,h=1,c=0xFFFFFFFF},
  {x=47,y=43,w=7,h=1,c=0xFFFFFFFF},{x=13,y=44,w=9,h=1,c=0xFFFFFFFF},{x=23,y=44,w=2,h=1,c=0xFFFFFFFF},{x=38,y=44,w=6,h=1,c=0xFFFFFFFF},{x=44,y=44,w=1,h=1,c=0xFF000000},{x=45,y=44,w=10,h=1,c=0xFFFFFFFF},{x=13,y=45,w=9,h=1,c=0xFFFFFFFF},{x=44,y=45,w=11,h=1,c=0xFFFFFFFF},
  {x=13,y=46,w=10,h=1,c=0xFFFFFFFF},{x=24,y=46,w=2,h=1,c=0xFFFFFFFF},{x=37,y=46,w=6,h=1,c=0xFFFFFFFF},{x=44,y=46,w=10,h=1,c=0xFFFFFFFF},
}}

--- Sans 头 Default（32x30，177 个矩形）
M.sans_head_default = { w=32, h=30, rects={
  {x=7,y=1,w=3,h=1,c=0xFF000000},{x=10,y=1,w=12,h=1,c=0xFFFFFFFF},{x=22,y=1,w=3,h=1,c=0xFF000000},{x=5,y=2,w=2,h=1,c=0xFF000000},{x=7,y=2,w=18,h=1,c=0xFFFFFFFF},{x=25,y=2,w=2,h=1,c=0xFF000000},{x=4,y=3,w=1,h=1,c=0xFF000000},{x=5,y=3,w=22,h=1,c=0xFFFFFFFF},
  {x=27,y=3,w=1,h=1,c=0xFF000000},{x=3,y=4,w=1,h=1,c=0xFF000000},{x=4,y=4,w=24,h=1,c=0xFFFFFFFF},{x=28,y=4,w=1,h=1,c=0xFF000000},{x=2,y=5,w=1,h=1,c=0xFF000000},{x=3,y=5,w=26,h=1,c=0xFFFFFFFF},{x=29,y=5,w=1,h=1,c=0xFF000000},{x=1,y=6,w=1,h=1,c=0xFF000000},
  {x=2,y=6,w=28,h=1,c=0xFFFFFFFF},{x=30,y=6,w=1,h=1,c=0xFF000000},{x=1,y=7,w=1,h=1,c=0xFF000000},{x=2,y=7,w=28,h=1,c=0xFFFFFFFF},{x=30,y=7,w=1,h=1,c=0xFF000000},{x=1,y=8,w=30,h=2,c=0xFFFFFFFF},{x=1,y=10,w=5,h=1,c=0xFFFFFFFF},{x=6,y=10,w=6,h=1,c=0xFF000000},
  {x=12,y=10,w=8,h=1,c=0xFFFFFFFF},{x=20,y=10,w=6,h=1,c=0xFF000000},{x=26,y=10,w=5,h=1,c=0xFFFFFFFF},{x=1,y=11,w=3,h=1,c=0xFFFFFFFF},{x=4,y=11,w=9,h=1,c=0xFF000000},{x=13,y=11,w=6,h=1,c=0xFFFFFFFF},{x=19,y=11,w=9,h=1,c=0xFF000000},{x=28,y=11,w=3,h=1,c=0xFFFFFFFF},
  {x=1,y=12,w=2,h=1,c=0xFFFFFFFF},{x=3,y=12,w=10,h=1,c=0xFF000000},{x=13,y=12,w=6,h=1,c=0xFFFFFFFF},{x=19,y=12,w=10,h=1,c=0xFF000000},{x=29,y=12,w=2,h=1,c=0xFFFFFFFF},{x=1,y=13,w=2,h=1,c=0xFFFFFFFF},{x=3,y=13,w=5,h=1,c=0xFF000000},{x=8,y=13,w=2,h=1,c=0xFFFFFFFF},
  {x=10,y=13,w=3,h=1,c=0xFF000000},{x=13,y=13,w=6,h=1,c=0xFFFFFFFF},{x=19,y=13,w=3,h=1,c=0xFF000000},{x=22,y=13,w=2,h=1,c=0xFFFFFFFF},{x=24,y=13,w=5,h=1,c=0xFF000000},{x=29,y=13,w=2,h=1,c=0xFFFFFFFF},{x=1,y=14,w=2,h=1,c=0xFFFFFFFF},{x=3,y=14,w=5,h=1,c=0xFF000000},
  {x=8,y=14,w=2,h=1,c=0xFFFFFFFF},{x=10,y=14,w=3,h=1,c=0xFF000000},{x=13,y=14,w=6,h=1,c=0xFFFFFFFF},{x=19,y=14,w=3,h=1,c=0xFF000000},{x=22,y=14,w=2,h=1,c=0xFFFFFFFF},{x=24,y=14,w=5,h=1,c=0xFF000000},{x=29,y=14,w=2,h=1,c=0xFFFFFFFF},{x=1,y=15,w=1,h=1,c=0xFF000000},
  {x=2,y=15,w=2,h=1,c=0xFFFFFFFF},{x=4,y=15,w=8,h=1,c=0xFF000000},{x=12,y=15,w=3,h=1,c=0xFFFFFFFF},{x=15,y=15,w=2,h=1,c=0xFF000000},{x=17,y=15,w=3,h=1,c=0xFFFFFFFF},{x=20,y=15,w=8,h=1,c=0xFF000000},{x=28,y=15,w=2,h=1,c=0xFFFFFFFF},{x=30,y=15,w=1,h=1,c=0xFF000000},
  {x=1,y=16,w=1,h=1,c=0xFF000000},{x=2,y=16,w=4,h=1,c=0xFFFFFFFF},{x=6,y=16,w=6,h=1,c=0xFF000000},{x=12,y=16,w=3,h=1,c=0xFFFFFFFF},{x=15,y=16,w=2,h=1,c=0xFF000000},{x=17,y=16,w=3,h=1,c=0xFFFFFFFF},{x=20,y=16,w=6,h=1,c=0xFF000000},{x=26,y=16,w=4,h=1,c=0xFFFFFFFF},
  {x=30,y=16,w=1,h=1,c=0xFF000000},{x=2,y=17,w=1,h=1,c=0xFF000000},{x=3,y=17,w=7,h=1,c=0xFFFFFFFF},{x=10,y=17,w=1,h=1,c=0xFF000000},{x=11,y=17,w=3,h=1,c=0xFFFFFFFF},{x=14,y=17,w=4,h=1,c=0xFF000000},{x=18,y=17,w=3,h=1,c=0xFFFFFFFF},{x=21,y=17,w=1,h=1,c=0xFF000000},
  {x=22,y=17,w=7,h=1,c=0xFFFFFFFF},{x=29,y=17,w=1,h=1,c=0xFF000000},{x=2,y=18,w=1,h=1,c=0xFF000000},{x=3,y=18,w=5,h=1,c=0xFFFFFFFF},{x=8,y=18,w=2,h=1,c=0xFF000000},{x=10,y=18,w=4,h=1,c=0xFFFFFFFF},{x=14,y=18,w=4,h=1,c=0xFF000000},{x=18,y=18,w=4,h=1,c=0xFFFFFFFF},
  {x=22,y=18,w=2,h=1,c=0xFF000000},{x=24,y=18,w=5,h=1,c=0xFFFFFFFF},{x=29,y=18,w=1,h=1,c=0xFF000000},{x=1,y=19,w=1,h=1,c=0xFF000000},{x=2,y=19,w=4,h=1,c=0xFFFFFFFF},{x=6,y=19,w=1,h=1,c=0xFF000000},{x=7,y=19,w=7,h=1,c=0xFFFFFFFF},{x=14,y=19,w=4,h=1,c=0xFF000000},
  {x=18,y=19,w=7,h=1,c=0xFFFFFFFF},{x=25,y=19,w=1,h=1,c=0xFF000000},{x=26,y=19,w=4,h=1,c=0xFFFFFFFF},{x=30,y=19,w=1,h=1,c=0xFF000000},{x=1,y=20,w=1,h=1,c=0xFF000000},{x=2,y=20,w=4,h=1,c=0xFFFFFFFF},{x=6,y=20,w=2,h=1,c=0xFF000000},{x=8,y=20,w=17,h=1,c=0xFFFFFFFF},
  {x=25,y=20,w=2,h=1,c=0xFF000000},{x=27,y=20,w=3,h=1,c=0xFFFFFFFF},{x=30,y=20,w=1,h=1,c=0xFF000000},{x=1,y=21,w=1,h=1,c=0xFF000000},{x=2,y=21,w=2,h=1,c=0xFFFFFFFF},{x=4,y=21,w=3,h=1,c=0xFF000000},{x=7,y=21,w=1,h=1,c=0xFFFFFFFF},{x=8,y=21,w=2,h=1,c=0xFF000000},
  {x=10,y=21,w=13,h=1,c=0xFFFFFFFF},{x=23,y=21,w=5,h=1,c=0xFF000000},{x=28,y=21,w=2,h=1,c=0xFFFFFFFF},{x=30,y=21,w=1,h=1,c=0xFF000000},{x=1,y=22,w=1,h=1,c=0xFF000000},{x=2,y=22,w=4,h=1,c=0xFFFFFFFF},{x=6,y=22,w=1,h=1,c=0xFF000000},{x=7,y=22,w=1,h=1,c=0xFFFFFFFF},
  {x=8,y=22,w=1,h=1,c=0xFF000000},{x=9,y=22,w=1,h=1,c=0xFFFFFFFF},{x=10,y=22,w=13,h=1,c=0xFF000000},{x=23,y=22,w=1,h=1,c=0xFFFFFFFF},{x=24,y=22,w=2,h=1,c=0xFF000000},{x=26,y=22,w=4,h=1,c=0xFFFFFFFF},{x=30,y=22,w=1,h=1,c=0xFF000000},{x=2,y=23,w=1,h=1,c=0xFF000000},
  {x=3,y=23,w=4,h=1,c=0xFFFFFFFF},{x=7,y=23,w=2,h=1,c=0xFF000000},{x=9,y=23,w=3,h=1,c=0xFFFFFFFF},{x=12,y=23,w=1,h=1,c=0xFF000000},{x=13,y=23,w=2,h=1,c=0xFFFFFFFF},{x=15,y=23,w=1,h=1,c=0xFF000000},{x=16,y=23,w=3,h=1,c=0xFFFFFFFF},{x=19,y=23,w=1,h=1,c=0xFF000000},
  {x=20,y=23,w=2,h=1,c=0xFFFFFFFF},{x=22,y=23,w=1,h=1,c=0xFF000000},{x=23,y=23,w=1,h=1,c=0xFFFFFFFF},{x=24,y=23,w=1,h=1,c=0xFF000000},{x=25,y=23,w=4,h=1,c=0xFFFFFFFF},{x=29,y=23,w=1,h=1,c=0xFF000000},{x=2,y=24,w=1,h=1,c=0xFF000000},{x=3,y=24,w=5,h=1,c=0xFFFFFFFF},
  {x=8,y=24,w=2,h=1,c=0xFF000000},{x=10,y=24,w=2,h=1,c=0xFFFFFFFF},{x=12,y=24,w=1,h=1,c=0xFF000000},{x=13,y=24,w=2,h=1,c=0xFFFFFFFF},{x=15,y=24,w=1,h=1,c=0xFF000000},{x=16,y=24,w=3,h=1,c=0xFFFFFFFF},{x=19,y=24,w=1,h=1,c=0xFF000000},{x=20,y=24,w=2,h=1,c=0xFFFFFFFF},
  {x=22,y=24,w=2,h=1,c=0xFF000000},{x=24,y=24,w=5,h=1,c=0xFFFFFFFF},{x=29,y=24,w=1,h=1,c=0xFF000000},{x=3,y=25,w=1,h=1,c=0xFF000000},{x=4,y=25,w=6,h=1,c=0xFFFFFFFF},{x=10,y=25,w=3,h=1,c=0xFF000000},{x=13,y=25,w=2,h=1,c=0xFFFFFFFF},{x=15,y=25,w=1,h=1,c=0xFF000000},
  {x=16,y=25,w=3,h=1,c=0xFFFFFFFF},{x=19,y=25,w=1,h=1,c=0xFF000000},{x=20,y=25,w=1,h=1,c=0xFFFFFFFF},{x=21,y=25,w=2,h=1,c=0xFF000000},{x=23,y=25,w=5,h=1,c=0xFFFFFFFF},{x=28,y=25,w=1,h=1,c=0xFF000000},{x=4,y=26,w=1,h=1,c=0xFF000000},{x=5,y=26,w=7,h=1,c=0xFFFFFFFF},
  {x=12,y=26,w=9,h=1,c=0xFF000000},{x=21,y=26,w=6,h=1,c=0xFFFFFFFF},{x=27,y=26,w=1,h=1,c=0xFF000000},{x=5,y=27,w=2,h=1,c=0xFF000000},{x=7,y=27,w=18,h=1,c=0xFFFFFFFF},{x=25,y=27,w=2,h=1,c=0xFF000000},{x=7,y=28,w=3,h=1,c=0xFF000000},{x=10,y=28,w=12,h=1,c=0xFFFFFFFF},
  {x=22,y=28,w=3,h=1,c=0xFF000000},
}}

--- Sans 头 BlueEye（32x30，181 个矩形）
M.sans_head_blue = { w=32, h=30, rects={
  {x=7,y=1,w=3,h=1,c=0xFF000000},{x=10,y=1,w=12,h=1,c=0xFFFFFFFF},{x=22,y=1,w=3,h=1,c=0xFF000000},{x=5,y=2,w=2,h=1,c=0xFF000000},{x=7,y=2,w=18,h=1,c=0xFFFFFFFF},{x=25,y=2,w=2,h=1,c=0xFF000000},{x=4,y=3,w=1,h=1,c=0xFF000000},{x=5,y=3,w=22,h=1,c=0xFFFFFFFF},
  {x=27,y=3,w=1,h=1,c=0xFF000000},{x=3,y=4,w=1,h=1,c=0xFF000000},{x=4,y=4,w=24,h=1,c=0xFFFFFFFF},{x=28,y=4,w=1,h=1,c=0xFF000000},{x=2,y=5,w=1,h=1,c=0xFF000000},{x=3,y=5,w=26,h=1,c=0xFFFFFFFF},{x=29,y=5,w=1,h=1,c=0xFF000000},{x=1,y=6,w=1,h=1,c=0xFF000000},
  {x=2,y=6,w=28,h=1,c=0xFFFFFFFF},{x=30,y=6,w=1,h=1,c=0xFF000000},{x=1,y=7,w=1,h=1,c=0xFF000000},{x=2,y=7,w=28,h=1,c=0xFFFFFFFF},{x=30,y=7,w=1,h=1,c=0xFF000000},{x=1,y=8,w=30,h=2,c=0xFFFFFFFF},{x=1,y=10,w=5,h=1,c=0xFFFFFFFF},{x=6,y=10,w=6,h=1,c=0xFF000000},
  {x=12,y=10,w=8,h=1,c=0xFFFFFFFF},{x=20,y=10,w=6,h=1,c=0xFF000000},{x=26,y=10,w=5,h=1,c=0xFFFFFFFF},{x=1,y=11,w=3,h=1,c=0xFFFFFFFF},{x=4,y=11,w=9,h=1,c=0xFF000000},{x=13,y=11,w=6,h=1,c=0xFFFFFFFF},{x=19,y=11,w=3,h=1,c=0xFF000000},{x=22,y=11,w=3,h=1,c=0xFF84FFF2},
  {x=25,y=11,w=3,h=1,c=0xFF000000},{x=28,y=11,w=3,h=1,c=0xFFFFFFFF},{x=1,y=12,w=2,h=1,c=0xFFFFFFFF},{x=3,y=12,w=10,h=1,c=0xFF000000},{x=13,y=12,w=6,h=1,c=0xFFFFFFFF},{x=19,y=12,w=2,h=1,c=0xFF000000},{x=21,y=12,w=5,h=1,c=0xFF84FFF2},{x=26,y=12,w=3,h=1,c=0xFF000000},
  {x=29,y=12,w=2,h=1,c=0xFFFFFFFF},{x=1,y=13,w=2,h=1,c=0xFFFFFFFF},{x=3,y=13,w=10,h=1,c=0xFF000000},{x=13,y=13,w=6,h=1,c=0xFFFFFFFF},{x=19,y=13,w=1,h=1,c=0xFF000000},{x=20,y=13,w=3,h=1,c=0xFF84FFF2},{x=23,y=13,w=1,h=1,c=0xFF000000},{x=24,y=13,w=3,h=1,c=0xFF84FFF2},
  {x=27,y=13,w=2,h=1,c=0xFF000000},{x=29,y=13,w=2,h=1,c=0xFFFFFFFF},{x=1,y=14,w=2,h=1,c=0xFFFFFFFF},{x=3,y=14,w=10,h=1,c=0xFF000000},{x=13,y=14,w=6,h=1,c=0xFFFFFFFF},{x=19,y=14,w=2,h=1,c=0xFF000000},{x=21,y=14,w=5,h=1,c=0xFF84FFF2},{x=26,y=14,w=3,h=1,c=0xFF000000},
  {x=29,y=14,w=2,h=1,c=0xFFFFFFFF},{x=1,y=15,w=1,h=1,c=0xFF000000},{x=2,y=15,w=2,h=1,c=0xFFFFFFFF},{x=4,y=15,w=8,h=1,c=0xFF000000},{x=12,y=15,w=3,h=1,c=0xFFFFFFFF},{x=15,y=15,w=2,h=1,c=0xFF000000},{x=17,y=15,w=3,h=1,c=0xFFFFFFFF},{x=20,y=15,w=2,h=1,c=0xFF000000},
  {x=22,y=15,w=3,h=1,c=0xFF84FFF2},{x=25,y=15,w=3,h=1,c=0xFF000000},{x=28,y=15,w=2,h=1,c=0xFFFFFFFF},{x=30,y=15,w=1,h=1,c=0xFF000000},{x=1,y=16,w=1,h=1,c=0xFF000000},{x=2,y=16,w=4,h=1,c=0xFFFFFFFF},{x=6,y=16,w=6,h=1,c=0xFF000000},{x=12,y=16,w=3,h=1,c=0xFFFFFFFF},
  {x=15,y=16,w=2,h=1,c=0xFF000000},{x=17,y=16,w=3,h=1,c=0xFFFFFFFF},{x=20,y=16,w=6,h=1,c=0xFF000000},{x=26,y=16,w=4,h=1,c=0xFFFFFFFF},{x=30,y=16,w=1,h=1,c=0xFF000000},{x=2,y=17,w=1,h=1,c=0xFF000000},{x=3,y=17,w=7,h=1,c=0xFFFFFFFF},{x=10,y=17,w=1,h=1,c=0xFF000000},
  {x=11,y=17,w=3,h=1,c=0xFFFFFFFF},{x=14,y=17,w=4,h=1,c=0xFF000000},{x=18,y=17,w=3,h=1,c=0xFFFFFFFF},{x=21,y=17,w=1,h=1,c=0xFF000000},{x=22,y=17,w=7,h=1,c=0xFFFFFFFF},{x=29,y=17,w=1,h=1,c=0xFF000000},{x=2,y=18,w=1,h=1,c=0xFF000000},{x=3,y=18,w=5,h=1,c=0xFFFFFFFF},
  {x=8,y=18,w=2,h=1,c=0xFF000000},{x=10,y=18,w=4,h=1,c=0xFFFFFFFF},{x=14,y=18,w=4,h=1,c=0xFF000000},{x=18,y=18,w=4,h=1,c=0xFFFFFFFF},{x=22,y=18,w=2,h=1,c=0xFF000000},{x=24,y=18,w=5,h=1,c=0xFFFFFFFF},{x=29,y=18,w=1,h=1,c=0xFF000000},{x=1,y=19,w=1,h=1,c=0xFF000000},
  {x=2,y=19,w=4,h=1,c=0xFFFFFFFF},{x=6,y=19,w=1,h=1,c=0xFF000000},{x=7,y=19,w=7,h=1,c=0xFFFFFFFF},{x=14,y=19,w=4,h=1,c=0xFF000000},{x=18,y=19,w=7,h=1,c=0xFFFFFFFF},{x=25,y=19,w=1,h=1,c=0xFF000000},{x=26,y=19,w=4,h=1,c=0xFFFFFFFF},{x=30,y=19,w=1,h=1,c=0xFF000000},
  {x=1,y=20,w=1,h=1,c=0xFF000000},{x=2,y=20,w=4,h=1,c=0xFFFFFFFF},{x=6,y=20,w=2,h=1,c=0xFF000000},{x=8,y=20,w=17,h=1,c=0xFFFFFFFF},{x=25,y=20,w=2,h=1,c=0xFF000000},{x=27,y=20,w=3,h=1,c=0xFFFFFFFF},{x=30,y=20,w=1,h=1,c=0xFF000000},{x=1,y=21,w=1,h=1,c=0xFF000000},
  {x=2,y=21,w=2,h=1,c=0xFFFFFFFF},{x=4,y=21,w=3,h=1,c=0xFF000000},{x=7,y=21,w=1,h=1,c=0xFFFFFFFF},{x=8,y=21,w=2,h=1,c=0xFF000000},{x=10,y=21,w=13,h=1,c=0xFFFFFFFF},{x=23,y=21,w=5,h=1,c=0xFF000000},{x=28,y=21,w=2,h=1,c=0xFFFFFFFF},{x=30,y=21,w=1,h=1,c=0xFF000000},
  {x=1,y=22,w=1,h=1,c=0xFF000000},{x=2,y=22,w=4,h=1,c=0xFFFFFFFF},{x=6,y=22,w=1,h=1,c=0xFF000000},{x=7,y=22,w=1,h=1,c=0xFFFFFFFF},{x=8,y=22,w=1,h=1,c=0xFF000000},{x=9,y=22,w=1,h=1,c=0xFFFFFFFF},{x=10,y=22,w=13,h=1,c=0xFF000000},{x=23,y=22,w=1,h=1,c=0xFFFFFFFF},
  {x=24,y=22,w=2,h=1,c=0xFF000000},{x=26,y=22,w=4,h=1,c=0xFFFFFFFF},{x=30,y=22,w=1,h=1,c=0xFF000000},{x=2,y=23,w=1,h=1,c=0xFF000000},{x=3,y=23,w=4,h=1,c=0xFFFFFFFF},{x=7,y=23,w=2,h=1,c=0xFF000000},{x=9,y=23,w=3,h=1,c=0xFFFFFFFF},{x=12,y=23,w=1,h=1,c=0xFF000000},
  {x=13,y=23,w=2,h=1,c=0xFFFFFFFF},{x=15,y=23,w=1,h=1,c=0xFF000000},{x=16,y=23,w=3,h=1,c=0xFFFFFFFF},{x=19,y=23,w=1,h=1,c=0xFF000000},{x=20,y=23,w=2,h=1,c=0xFFFFFFFF},{x=22,y=23,w=1,h=1,c=0xFF000000},{x=23,y=23,w=1,h=1,c=0xFFFFFFFF},{x=24,y=23,w=1,h=1,c=0xFF000000},
  {x=25,y=23,w=4,h=1,c=0xFFFFFFFF},{x=29,y=23,w=1,h=1,c=0xFF000000},{x=2,y=24,w=1,h=1,c=0xFF000000},{x=3,y=24,w=5,h=1,c=0xFFFFFFFF},{x=8,y=24,w=2,h=1,c=0xFF000000},{x=10,y=24,w=2,h=1,c=0xFFFFFFFF},{x=12,y=24,w=1,h=1,c=0xFF000000},{x=13,y=24,w=2,h=1,c=0xFFFFFFFF},
  {x=15,y=24,w=1,h=1,c=0xFF000000},{x=16,y=24,w=3,h=1,c=0xFFFFFFFF},{x=19,y=24,w=1,h=1,c=0xFF000000},{x=20,y=24,w=2,h=1,c=0xFFFFFFFF},{x=22,y=24,w=2,h=1,c=0xFF000000},{x=24,y=24,w=5,h=1,c=0xFFFFFFFF},{x=29,y=24,w=1,h=1,c=0xFF000000},{x=3,y=25,w=1,h=1,c=0xFF000000},
  {x=4,y=25,w=6,h=1,c=0xFFFFFFFF},{x=10,y=25,w=3,h=1,c=0xFF000000},{x=13,y=25,w=2,h=1,c=0xFFFFFFFF},{x=15,y=25,w=1,h=1,c=0xFF000000},{x=16,y=25,w=3,h=1,c=0xFFFFFFFF},{x=19,y=25,w=1,h=1,c=0xFF000000},{x=20,y=25,w=1,h=1,c=0xFFFFFFFF},{x=21,y=25,w=2,h=1,c=0xFF000000},
  {x=23,y=25,w=5,h=1,c=0xFFFFFFFF},{x=28,y=25,w=1,h=1,c=0xFF000000},{x=4,y=26,w=1,h=1,c=0xFF000000},{x=5,y=26,w=7,h=1,c=0xFFFFFFFF},{x=12,y=26,w=9,h=1,c=0xFF000000},{x=21,y=26,w=6,h=1,c=0xFFFFFFFF},{x=27,y=26,w=1,h=1,c=0xFF000000},{x=5,y=27,w=2,h=1,c=0xFF000000},
  {x=7,y=27,w=18,h=1,c=0xFFFFFFFF},{x=25,y=27,w=2,h=1,c=0xFF000000},{x=7,y=28,w=3,h=1,c=0xFF000000},{x=10,y=28,w=12,h=1,c=0xFFFFFFFF},{x=22,y=28,w=3,h=1,c=0xFF000000},
}}

-- 【方案A】龙骨炮 block2 表（2×2 采样）：初见杀用，逐帧直接画 ~123 个 rrect/发
M.blaster_block2 = {
  Default = { {x=18,y=0,w=4,h=2,c=0xFF000000},{x=14,y=2,w=2,h=2,c=0xFF000000},{x=16,y=2,w=6,h=2,c=0xFFFFFFFF},{x=22,y=2,w=2,h=2,c=0xFF000000},{x=32,y=2,w=2,h=2,c=0xFF000000},{x=34,y=2,w=2,h=2,c=0xFFFFFFFF},{x=36,y=2,w=2,h=2,c=0xFF000000},{x=10,y=4,w=2,h=2,c=0xFF000000},{x=12,y=4,w=14,h=2,c=0xFFFFFFFF},{x=26,y=4,w=6,h=2,c=0xFF000000},{x=34,y=4,w=2,h=2,c=0xFF000000},{x=36,y=4,w=4,h=2,c=0xFFFFFFFF},{x=40,y=4,w=2,h=2,c=0xFF000000},{x=8,y=6,w=26,h=2,c=0xFFFFFFFF},{x=34,y=6,w=2,h=2,c=0xFF000000},{x=36,y=6,w=6,h=2,c=0xFFFFFFFF},{x=42,y=6,w=2,h=2,c=0xFF000000},{x=6,y=8,w=2,h=2,c=0xFFFFFFFF},{x=8,y=8,w=4,h=2,c=0xFF000000},{x=12,y=8,w=8,h=2,c=0xFFFFFFFF},{x=20,y=8,w=2,h=2,c=0xFF000000},{x=22,y=8,w=4,h=2,c=0xFFFFFFFF},{x=26,y=8,w=10,h=2,c=0xFF000000},{x=36,y=8,w=8,h=2,c=0xFFFFFFFF},{x=44,y=8,w=2,h=2,c=0xFF000000},{x=6,y=10,w=2,h=2,c=0xFF000000},{x=10,y=10,w=12,h=2,c=0xFFFFFFFF},{x=22,y=10,w=6,h=2,c=0xFF000000},{x=28,y=10,w=4,h=2,c=0xFFFFFFFF},{x=32,y=10,w=6,h=2,c=0xFF000000},{x=38,y=10,w=8,h=2,c=0xFFFFFFFF},{x=8,y=12,w=2,h=2,c=0xFF000000},{x=10,y=12,w=12,h=2,c=0xFFFFFFFF},{x=22,y=12,w=4,h=2,c=0xFF000000},{x=26,y=12,w=4,h=2,c=0xFFFFFFFF},{x=30,y=12,w=2,h=2,c=0xFF000000},{x=32,y=12,w=4,h=2,c=0xFFFFFFFF},{x=36,y=12,w=8,h=2,c=0xFF000000},{x=44,y=12,w=4,h=2,c=0xFFFFFFFF},{x=8,y=14,w=16,h=2,c=0xFFFFFFFF},{x=24,y=14,w=2,h=2,c=0xFF000000},{x=26,y=14,w=2,h=2,c=0xFFFFFFFF},{x=28,y=14,w=2,h=2,c=0xFF000000},{x=30,y=14,w=20,h=2,c=0xFFFFFFFF},{x=50,y=14,w=2,h=2,c=0xFF000000},{x=6,y=16,w=2,h=2,c=0xFF000000},{x=8,y=16,w=18,h=2,c=0xFFFFFFFF},{x=26,y=16,w=6,h=2,c=0xFF000000},{x=32,y=16,w=10,h=2,c=0xFFFFFFFF},{x=46,y=16,w=4,h=2,c=0xFF000000},{x=50,y=16,w=4,h=2,c=0xFFFFFFFF},{x=54,y=16,w=2,h=2,c=0xFF000000},{x=4,y=18,w=2,h=2,c=0xFF000000},{x=6,y=18,w=36,h=2,c=0xFFFFFFFF},{x=42,y=18,w=10,h=2,c=0xFF000000},{x=52,y=18,w=4,h=2,c=0xFFFFFFFF},{x=2,y=20,w=2,h=2,c=0xFF000000},{x=4,y=20,w=28,h=2,c=0xFFFFFFFF},{x=32,y=20,w=2,h=2,c=0xFF000000},{x=38,y=20,w=2,h=2,c=0xFF000000},{x=40,y=20,w=2,h=2,c=0xFFFFFFFF},{x=42,y=20,w=6,h=2,c=0xFF000000},{x=48,y=20,w=8,h=2,c=0xFFFFFFFF},{x=2,y=22,w=10,h=2,c=0xFFFFFFFF},{x=12,y=22,w=22,h=2,c=0xFF000000},{x=38,y=22,w=2,h=2,c=0xFF000000},{x=40,y=22,w=2,h=2,c=0xFFFFFFFF},{x=42,y=22,w=6,h=2,c=0xFF000000},{x=48,y=22,w=8,h=2,c=0xFFFFFFFF},{x=4,y=24,w=2,h=2,c=0xFF000000},{x=6,y=24,w=28,h=2,c=0xFFFFFFFF},{x=34,y=24,w=4,h=2,c=0xFF000000},{x=38,y=24,w=8,h=2,c=0xFFFFFFFF},{x=46,y=24,w=4,h=2,c=0xFF000000},{x=50,y=24,w=6,h=2,c=0xFFFFFFFF},{x=6,y=26,w=2,h=2,c=0xFF000000},{x=8,y=26,w=20,h=2,c=0xFFFFFFFF},{x=28,y=26,w=4,h=2,c=0xFF000000},{x=32,y=26,w=10,h=2,c=0xFFFFFFFF},{x=46,y=26,w=2,h=2,c=0xFF000000},{x=48,y=26,w=6,h=2,c=0xFFFFFFFF},{x=54,y=26,w=2,h=2,c=0xFF000000},{x=8,y=28,w=16,h=2,c=0xFFFFFFFF},{x=24,y=28,w=2,h=2,c=0xFF000000},{x=26,y=28,w=14,h=2,c=0xFFFFFFFF},{x=40,y=28,w=6,h=2,c=0xFF000000},{x=46,y=28,w=4,h=2,c=0xFFFFFFFF},{x=50,y=28,w=2,h=2,c=0xFF000000},{x=8,y=30,w=2,h=2,c=0xFF000000},{x=10,y=30,w=12,h=2,c=0xFFFFFFFF},{x=22,y=30,w=4,h=2,c=0xFF000000},{x=26,y=30,w=12,h=2,c=0xFFFFFFFF},{x=38,y=30,w=6,h=2,c=0xFF000000},{x=44,y=30,w=4,h=2,c=0xFFFFFFFF},{x=6,y=32,w=2,h=2,c=0xFF000000},{x=10,y=32,w=12,h=2,c=0xFFFFFFFF},{x=22,y=32,w=8,h=2,c=0xFF000000},{x=30,y=32,w=8,h=2,c=0xFFFFFFFF},{x=38,y=32,w=4,h=2,c=0xFF000000},{x=42,y=32,w=4,h=2,c=0xFFFFFFFF},{x=6,y=34,w=2,h=2,c=0xFFFFFFFF},{x=8,y=34,w=4,h=2,c=0xFF000000},{x=12,y=34,w=6,h=2,c=0xFFFFFFFF},{x=18,y=34,w=2,h=2,c=0xFF000000},{x=20,y=34,w=10,h=2,c=0xFFFFFFFF},{x=30,y=34,w=6,h=2,c=0xFF000000},{x=36,y=34,w=8,h=2,c=0xFFFFFFFF},{x=44,y=34,w=2,h=2,c=0xFF000000},{x=8,y=36,w=12,h=2,c=0xFFFFFFFF},{x=20,y=36,w=10,h=2,c=0xFF000000},{x=30,y=36,w=12,h=2,c=0xFFFFFFFF},{x=42,y=36,w=2,h=2,c=0xFF000000},{x=10,y=38,w=18,h=2,c=0xFFFFFFFF},{x=28,y=38,w=4,h=2,c=0xFF000000},{x=34,y=38,w=2,h=2,c=0xFF000000},{x=36,y=38,w=4,h=2,c=0xFFFFFFFF},{x=40,y=38,w=2,h=2,c=0xFF000000},{x=14,y=40,w=2,h=2,c=0xFF000000},{x=16,y=40,w=8,h=2,c=0xFFFFFFFF},{x=32,y=40,w=2,h=2,c=0xFF000000},{x=34,y=40,w=2,h=2,c=0xFFFFFFFF},{x=36,y=40,w=2,h=2,c=0xFF000000},{x=18,y=42,w=4,h=2,c=0xFF000000} },
  fire_0 = { {x=16,y=2,w=8,h=2,c=0xFF000000},{x=34,y=2,w=2,h=2,c=0xFF000000},{x=10,y=4,w=4,h=2,c=0xFF000000},{x=14,y=4,w=10,h=2,c=0xFFFFFFFF},{x=24,y=4,w=4,h=2,c=0xFF000000},{x=34,y=4,w=2,h=2,c=0xFFFFFFFF},{x=36,y=4,w=4,h=2,c=0xFF000000},{x=8,y=6,w=2,h=2,c=0xFF000000},{x=10,y=6,w=20,h=2,c=0xFFFFFFFF},{x=30,y=6,w=6,h=2,c=0xFF000000},{x=36,y=6,w=6,h=2,c=0xFFFFFFFF},{x=6,y=8,w=2,h=2,c=0xFF000000},{x=8,y=8,w=2,h=2,c=0xFFFFFFFF},{x=10,y=8,w=4,h=2,c=0xFF000000},{x=14,y=8,w=6,h=2,c=0xFFFFFFFF},{x=20,y=8,w=10,h=2,c=0xFF000000},{x=30,y=8,w=14,h=2,c=0xFFFFFFFF},{x=4,y=10,w=2,h=2,c=0xFF000000},{x=6,y=10,w=2,h=2,c=0xFFFFFFFF},{x=10,y=10,w=2,h=2,c=0xFF000000},{x=12,y=10,w=18,h=2,c=0xFFFFFFFF},{x=30,y=10,w=8,h=2,c=0xFF000000},{x=38,y=10,w=8,h=2,c=0xFFFFFFFF},{x=8,y=12,w=2,h=2,c=0xFF000000},{x=10,y=12,w=12,h=2,c=0xFFFFFFFF},{x=22,y=12,w=2,h=2,c=0xFF000000},{x=26,y=12,w=6,h=2,c=0xFF000000},{x=32,y=12,w=6,h=2,c=0xFFFFFFFF},{x=38,y=12,w=4,h=2,c=0xFF000000},{x=42,y=12,w=4,h=2,c=0xFFFFFFFF},{x=8,y=14,w=14,h=2,c=0xFFFFFFFF},{x=22,y=14,w=4,h=2,c=0xFF000000},{x=26,y=14,w=12,h=2,c=0xFFFFFFFF},{x=38,y=14,w=8,h=2,c=0xFF000000},{x=46,y=14,w=2,h=2,c=0xFFFFFFFF},{x=48,y=14,w=2,h=2,c=0xFF000000},{x=6,y=16,w=2,h=2,c=0xFF000000},{x=8,y=16,w=18,h=2,c=0xFFFFFFFF},{x=26,y=16,w=6,h=2,c=0xFF000000},{x=32,y=16,w=10,h=2,c=0xFFFFFFFF},{x=46,y=16,w=2,h=2,c=0xFF000000},{x=48,y=16,w=4,h=2,c=0xFFFFFFFF},{x=52,y=16,w=2,h=2,c=0xFF000000},{x=4,y=18,w=2,h=2,c=0xFF000000},{x=6,y=18,w=36,h=2,c=0xFFFFFFFF},{x=42,y=18,w=6,h=2,c=0xFF000000},{x=48,y=18,w=8,h=2,c=0xFFFFFFFF},{x=2,y=20,w=2,h=2,c=0xFF000000},{x=4,y=20,w=28,h=2,c=0xFFFFFFFF},{x=32,y=20,w=2,h=2,c=0xFF000000},{x=38,y=20,w=2,h=2,c=0xFF000000},{x=40,y=20,w=2,h=2,c=0xFFFFFFFF},{x=42,y=20,w=8,h=2,c=0xFF000000},{x=50,y=20,w=6,h=2,c=0xFFFFFFFF},{x=2,y=22,w=10,h=2,c=0xFFFFFFFF},{x=12,y=22,w=22,h=2,c=0xFF000000},{x=38,y=22,w=2,h=2,c=0xFF000000},{x=40,y=22,w=2,h=2,c=0xFFFFFFFF},{x=42,y=22,w=6,h=2,c=0xFF000000},{x=48,y=22,w=8,h=2,c=0xFFFFFFFF},{x=4,y=24,w=2,h=2,c=0xFF000000},{x=6,y=24,w=28,h=2,c=0xFFFFFFFF},{x=34,y=24,w=4,h=2,c=0xFF000000},{x=38,y=24,w=8,h=2,c=0xFFFFFFFF},{x=46,y=24,w=6,h=2,c=0xFF000000},{x=52,y=24,w=4,h=2,c=0xFFFFFFFF},{x=6,y=26,w=2,h=2,c=0xFF000000},{x=8,y=26,w=20,h=2,c=0xFFFFFFFF},{x=28,y=26,w=4,h=2,c=0xFF000000},{x=32,y=26,w=10,h=2,c=0xFFFFFFFF},{x=46,y=26,w=8,h=2,c=0xFF000000},{x=8,y=28,w=16,h=2,c=0xFFFFFFFF},{x=24,y=28,w=2,h=2,c=0xFF000000},{x=26,y=28,w=12,h=2,c=0xFFFFFFFF},{x=38,y=28,w=8,h=2,c=0xFF000000},{x=46,y=28,w=2,h=2,c=0xFFFFFFFF},{x=48,y=28,w=2,h=2,c=0xFF000000},{x=8,y=30,w=2,h=2,c=0xFF000000},{x=10,y=30,w=12,h=2,c=0xFFFFFFFF},{x=22,y=30,w=2,h=2,c=0xFF000000},{x=26,y=30,w=4,h=2,c=0xFFFFFFFF},{x=30,y=30,w=2,h=2,c=0xFF000000},{x=32,y=30,w=4,h=2,c=0xFFFFFFFF},{x=36,y=30,w=8,h=2,c=0xFF000000},{x=44,y=30,w=2,h=2,c=0xFFFFFFFF},{x=4,y=32,w=2,h=2,c=0xFF000000},{x=6,y=32,w=2,h=2,c=0xFFFFFFFF},{x=10,y=32,w=2,h=2,c=0xFF000000},{x=12,y=32,w=12,h=2,c=0xFFFFFFFF},{x=24,y=32,w=4,h=2,c=0xFF000000},{x=28,y=32,w=4,h=2,c=0xFFFFFFFF},{x=32,y=32,w=6,h=2,c=0xFF000000},{x=38,y=32,w=8,h=2,c=0xFFFFFFFF},{x=6,y=34,w=2,h=2,c=0xFF000000},{x=8,y=34,w=2,h=2,c=0xFFFFFFFF},{x=10,y=34,w=4,h=2,c=0xFF000000},{x=14,y=34,w=6,h=2,c=0xFFFFFFFF},{x=20,y=34,w=2,h=2,c=0xFF000000},{x=22,y=34,w=2,h=2,c=0xFFFFFFFF},{x=24,y=34,w=10,h=2,c=0xFF000000},{x=34,y=34,w=10,h=2,c=0xFFFFFFFF},{x=8,y=36,w=2,h=2,c=0xFF000000},{x=10,y=36,w=22,h=2,c=0xFFFFFFFF},{x=32,y=36,w=4,h=2,c=0xFF000000},{x=36,y=36,w=6,h=2,c=0xFFFFFFFF},{x=10,y=38,w=4,h=2,c=0xFF000000},{x=14,y=38,w=10,h=2,c=0xFFFFFFFF},{x=24,y=38,w=4,h=2,c=0xFF000000},{x=34,y=38,w=2,h=2,c=0xFF000000},{x=36,y=38,w=2,h=2,c=0xFFFFFFFF},{x=38,y=38,w=2,h=2,c=0xFF000000},{x=16,y=40,w=2,h=2,c=0xFF000000},{x=18,y=40,w=4,h=2,c=0xFFFFFFFF},{x=22,y=40,w=2,h=2,c=0xFF000000},{x=34,y=40,w=2,h=2,c=0xFF000000} },
  fire_2 = { {x=18,y=0,w=4,h=2,c=0xFFFFFFFF},{x=22,y=0,w=2,h=2,c=0xFF000000},{x=10,y=2,w=4,h=2,c=0xFF000000},{x=14,y=2,w=10,h=2,c=0xFFFFFFFF},{x=24,y=2,w=4,h=2,c=0xFF000000},{x=34,y=2,w=2,h=2,c=0xFFFFFFFF},{x=36,y=2,w=4,h=2,c=0xFF000000},{x=8,y=4,w=2,h=2,c=0xFF000000},{x=10,y=4,w=20,h=2,c=0xFFFFFFFF},{x=30,y=4,w=6,h=2,c=0xFF000000},{x=36,y=4,w=6,h=2,c=0xFFFFFFFF},{x=6,y=6,w=2,h=2,c=0xFF000000},{x=8,y=6,w=2,h=2,c=0xFFFFFFFF},{x=10,y=6,w=4,h=2,c=0xFF000000},{x=14,y=6,w=6,h=2,c=0xFFFFFFFF},{x=20,y=6,w=10,h=2,c=0xFF000000},{x=30,y=6,w=14,h=2,c=0xFFFFFFFF},{x=46,y=6,w=2,h=2,c=0xFF000000},{x=48,y=6,w=2,h=2,c=0xFFFFFFFF},{x=50,y=6,w=2,h=2,c=0xFF000000},{x=4,y=8,w=2,h=2,c=0xFF000000},{x=6,y=8,w=2,h=2,c=0xFFFFFFFF},{x=10,y=8,w=2,h=2,c=0xFF000000},{x=12,y=8,w=18,h=2,c=0xFFFFFFFF},{x=30,y=8,w=8,h=2,c=0xFF000000},{x=38,y=8,w=8,h=2,c=0xFFFFFFFF},{x=46,y=8,w=4,h=2,c=0xFF000000},{x=50,y=8,w=4,h=2,c=0xFFFFFFFF},{x=54,y=8,w=2,h=2,c=0xFF000000},{x=8,y=10,w=2,h=2,c=0xFF000000},{x=10,y=10,w=12,h=2,c=0xFFFFFFFF},{x=22,y=10,w=2,h=2,c=0xFF000000},{x=26,y=10,w=6,h=2,c=0xFF000000},{x=32,y=10,w=6,h=2,c=0xFFFFFFFF},{x=38,y=10,w=4,h=2,c=0xFF000000},{x=42,y=10,w=6,h=2,c=0xFFFFFFFF},{x=48,y=10,w=4,h=2,c=0xFF000000},{x=52,y=10,w=4,h=2,c=0xFFFFFFFF},{x=8,y=12,w=2,h=2,c=0xFF000000},{x=10,y=12,w=12,h=2,c=0xFFFFFFFF},{x=22,y=12,w=4,h=2,c=0xFF000000},{x=26,y=12,w=12,h=2,c=0xFFFFFFFF},{x=38,y=12,w=8,h=2,c=0xFF000000},{x=46,y=12,w=10,h=2,c=0xFFFFFFFF},{x=6,y=14,w=2,h=2,c=0xFF000000},{x=8,y=14,w=16,h=2,c=0xFFFFFFFF},{x=24,y=14,w=2,h=2,c=0xFF000000},{x=26,y=14,w=4,h=2,c=0xFFFFFFFF},{x=30,y=14,w=2,h=2,c=0xFF000000},{x=32,y=14,w=8,h=2,c=0xFFFFFFFF},{x=40,y=14,w=4,h=2,c=0xFF000000},{x=48,y=14,w=8,h=2,c=0xFF000000},{x=6,y=16,w=24,h=2,c=0xFFFFFFFF},{x=30,y=16,w=2,h=2,c=0xFF000000},{x=32,y=16,w=10,h=2,c=0xFFFFFFFF},{x=42,y=16,w=6,h=2,c=0xFF000000},{x=2,y=18,w=2,h=2,c=0xFF000000},{x=4,y=18,w=30,h=2,c=0xFFFFFFFF},{x=34,y=18,w=4,h=2,c=0xFF000000},{x=38,y=18,w=6,h=2,c=0xFFFFFFFF},{x=44,y=18,w=2,h=2,c=0xFF000000},{x=2,y=20,w=10,h=2,c=0xFFFFFFFF},{x=12,y=20,w=20,h=2,c=0xFF000000},{x=2,y=22,w=10,h=2,c=0xFFFFFFFF},{x=12,y=22,w=20,h=2,c=0xFF000000},{x=2,y=24,w=2,h=2,c=0xFF000000},{x=4,y=24,w=28,h=2,c=0xFFFFFFFF},{x=32,y=24,w=6,h=2,c=0xFF000000},{x=38,y=24,w=4,h=2,c=0xFFFFFFFF},{x=42,y=24,w=4,h=2,c=0xFF000000},{x=6,y=26,w=36,h=2,c=0xFFFFFFFF},{x=42,y=26,w=6,h=2,c=0xFF000000},{x=6,y=28,w=2,h=2,c=0xFF000000},{x=8,y=28,w=16,h=2,c=0xFFFFFFFF},{x=24,y=28,w=8,h=2,c=0xFF000000},{x=32,y=28,w=10,h=2,c=0xFFFFFFFF},{x=42,y=28,w=2,h=2,c=0xFF000000},{x=48,y=28,w=8,h=2,c=0xFF000000},{x=8,y=30,w=2,h=2,c=0xFF000000},{x=10,y=30,w=12,h=2,c=0xFFFFFFFF},{x=22,y=30,w=4,h=2,c=0xFF000000},{x=26,y=30,w=30,h=2,c=0xFFFFFFFF},{x=8,y=32,w=2,h=2,c=0xFF000000},{x=10,y=32,w=12,h=2,c=0xFFFFFFFF},{x=22,y=32,w=2,h=2,c=0xFF000000},{x=26,y=32,w=4,h=2,c=0xFFFFFFFF},{x=30,y=32,w=2,h=2,c=0xFF000000},{x=32,y=32,w=4,h=2,c=0xFFFFFFFF},{x=36,y=32,w=8,h=2,c=0xFF000000},{x=44,y=32,w=4,h=2,c=0xFFFFFFFF},{x=48,y=32,w=2,h=2,c=0xFF000000},{x=50,y=32,w=6,h=2,c=0xFFFFFFFF},{x=4,y=34,w=2,h=2,c=0xFF000000},{x=6,y=34,w=2,h=2,c=0xFFFFFFFF},{x=10,y=34,w=2,h=2,c=0xFF000000},{x=12,y=34,w=12,h=2,c=0xFFFFFFFF},{x=24,y=34,w=4,h=2,c=0xFF000000},{x=28,y=34,w=4,h=2,c=0xFFFFFFFF},{x=32,y=34,w=6,h=2,c=0xFF000000},{x=38,y=34,w=8,h=2,c=0xFFFFFFFF},{x=46,y=34,w=2,h=2,c=0xFF000000},{x=48,y=34,w=6,h=2,c=0xFFFFFFFF},{x=54,y=34,w=2,h=2,c=0xFF000000},{x=6,y=36,w=2,h=2,c=0xFF000000},{x=8,y=36,w=2,h=2,c=0xFFFFFFFF},{x=10,y=36,w=4,h=2,c=0xFF000000},{x=14,y=36,w=6,h=2,c=0xFFFFFFFF},{x=20,y=36,w=2,h=2,c=0xFF000000},{x=22,y=36,w=2,h=2,c=0xFFFFFFFF},{x=24,y=36,w=10,h=2,c=0xFF000000},{x=34,y=36,w=10,h=2,c=0xFFFFFFFF},{x=46,y=36,w=2,h=2,c=0xFF000000},{x=48,y=36,w=2,h=2,c=0xFFFFFFFF},{x=50,y=36,w=2,h=2,c=0xFF000000},{x=8,y=38,w=2,h=2,c=0xFF000000},{x=10,y=38,w=22,h=2,c=0xFFFFFFFF},{x=32,y=38,w=4,h=2,c=0xFF000000},{x=36,y=38,w=6,h=2,c=0xFFFFFFFF},{x=10,y=40,w=4,h=2,c=0xFF000000},{x=14,y=40,w=10,h=2,c=0xFFFFFFFF},{x=24,y=40,w=4,h=2,c=0xFF000000},{x=34,y=40,w=2,h=2,c=0xFF000000},{x=36,y=40,w=2,h=2,c=0xFFFFFFFF},{x=38,y=40,w=2,h=2,c=0xFF000000},{x=18,y=42,w=4,h=2,c=0xFFFFFFFF},{x=22,y=42,w=2,h=2,c=0xFF000000} },
  fire_4 = { {x=18,y=0,w=4,h=2,c=0xFF000000},{x=14,y=2,w=2,h=2,c=0xFF000000},{x=16,y=2,w=6,h=2,c=0xFFFFFFFF},{x=22,y=2,w=2,h=2,c=0xFF000000},{x=32,y=2,w=2,h=2,c=0xFF000000},{x=34,y=2,w=2,h=2,c=0xFFFFFFFF},{x=36,y=2,w=2,h=2,c=0xFF000000},{x=48,y=2,w=4,h=2,c=0xFFFFFFFF},{x=52,y=2,w=4,h=2,c=0xFF000000},{x=10,y=4,w=2,h=2,c=0xFF000000},{x=12,y=4,w=14,h=2,c=0xFFFFFFFF},{x=26,y=4,w=6,h=2,c=0xFF000000},{x=34,y=4,w=2,h=2,c=0xFF000000},{x=36,y=4,w=4,h=2,c=0xFFFFFFFF},{x=40,y=4,w=2,h=2,c=0xFF000000},{x=48,y=4,w=8,h=2,c=0xFFFFFFFF},{x=8,y=6,w=26,h=2,c=0xFFFFFFFF},{x=34,y=6,w=2,h=2,c=0xFF000000},{x=36,y=6,w=8,h=2,c=0xFFFFFFFF},{x=44,y=6,w=6,h=2,c=0xFF000000},{x=50,y=6,w=6,h=2,c=0xFFFFFFFF},{x=6,y=8,w=2,h=2,c=0xFFFFFFFF},{x=8,y=8,w=4,h=2,c=0xFF000000},{x=12,y=8,w=8,h=2,c=0xFFFFFFFF},{x=20,y=8,w=2,h=2,c=0xFF000000},{x=22,y=8,w=4,h=2,c=0xFFFFFFFF},{x=26,y=8,w=10,h=2,c=0xFF000000},{x=36,y=8,w=18,h=2,c=0xFFFFFFFF},{x=54,y=8,w=2,h=2,c=0xFF000000},{x=6,y=10,w=2,h=2,c=0xFF000000},{x=10,y=10,w=12,h=2,c=0xFFFFFFFF},{x=22,y=10,w=6,h=2,c=0xFF000000},{x=28,y=10,w=4,h=2,c=0xFFFFFFFF},{x=32,y=10,w=6,h=2,c=0xFF000000},{x=38,y=10,w=8,h=2,c=0xFFFFFFFF},{x=46,y=10,w=2,h=2,c=0xFF000000},{x=8,y=12,w=2,h=2,c=0xFF000000},{x=10,y=12,w=12,h=2,c=0xFFFFFFFF},{x=22,y=12,w=2,h=2,c=0xFF000000},{x=30,y=12,w=2,h=2,c=0xFF000000},{x=32,y=12,w=4,h=2,c=0xFFFFFFFF},{x=36,y=12,w=8,h=2,c=0xFF000000},{x=8,y=14,w=16,h=2,c=0xFFFFFFFF},{x=30,y=14,w=2,h=2,c=0xFF000000},{x=32,y=14,w=12,h=2,c=0xFFFFFFFF},{x=44,y=14,w=2,h=2,c=0xFF000000},{x=6,y=16,w=2,h=2,c=0xFF000000},{x=8,y=16,w=18,h=2,c=0xFFFFFFFF},{x=26,y=16,w=6,h=2,c=0xFF000000},{x=32,y=16,w=10,h=2,c=0xFFFFFFFF},{x=4,y=18,w=2,h=2,c=0xFF000000},{x=6,y=18,w=36,h=2,c=0xFFFFFFFF},{x=42,y=18,w=6,h=2,c=0xFF000000},{x=2,y=20,w=2,h=2,c=0xFF000000},{x=4,y=20,w=28,h=2,c=0xFFFFFFFF},{x=32,y=20,w=2,h=2,c=0xFF000000},{x=38,y=20,w=2,h=2,c=0xFF000000},{x=40,y=20,w=2,h=2,c=0xFFFFFFFF},{x=42,y=20,w=2,h=2,c=0xFF000000},{x=2,y=22,w=10,h=2,c=0xFFFFFFFF},{x=12,y=22,w=22,h=2,c=0xFF000000},{x=38,y=22,w=2,h=2,c=0xFF000000},{x=40,y=22,w=2,h=2,c=0xFFFFFFFF},{x=42,y=22,w=2,h=2,c=0xFF000000},{x=4,y=24,w=2,h=2,c=0xFF000000},{x=6,y=24,w=28,h=2,c=0xFFFFFFFF},{x=34,y=24,w=4,h=2,c=0xFF000000},{x=38,y=24,w=8,h=2,c=0xFFFFFFFF},{x=46,y=24,w=2,h=2,c=0xFF000000},{x=6,y=26,w=2,h=2,c=0xFF000000},{x=8,y=26,w=20,h=2,c=0xFFFFFFFF},{x=28,y=26,w=4,h=2,c=0xFF000000},{x=32,y=26,w=10,h=2,c=0xFFFFFFFF},{x=8,y=28,w=16,h=2,c=0xFFFFFFFF},{x=24,y=28,w=2,h=2,c=0xFF000000},{x=26,y=28,w=14,h=2,c=0xFFFFFFFF},{x=40,y=28,w=6,h=2,c=0xFF000000},{x=8,y=30,w=2,h=2,c=0xFF000000},{x=10,y=30,w=12,h=2,c=0xFFFFFFFF},{x=22,y=30,w=4,h=2,c=0xFF000000},{x=26,y=30,w=12,h=2,c=0xFFFFFFFF},{x=38,y=30,w=6,h=2,c=0xFF000000},{x=6,y=32,w=2,h=2,c=0xFF000000},{x=10,y=32,w=12,h=2,c=0xFFFFFFFF},{x=22,y=32,w=8,h=2,c=0xFF000000},{x=30,y=32,w=8,h=2,c=0xFFFFFFFF},{x=38,y=32,w=10,h=2,c=0xFF000000},{x=6,y=34,w=2,h=2,c=0xFFFFFFFF},{x=8,y=34,w=4,h=2,c=0xFF000000},{x=12,y=34,w=6,h=2,c=0xFFFFFFFF},{x=18,y=34,w=2,h=2,c=0xFF000000},{x=20,y=34,w=10,h=2,c=0xFFFFFFFF},{x=30,y=34,w=6,h=2,c=0xFF000000},{x=36,y=34,w=12,h=2,c=0xFFFFFFFF},{x=48,y=34,w=8,h=2,c=0xFF000000},{x=8,y=36,w=12,h=2,c=0xFFFFFFFF},{x=20,y=36,w=10,h=2,c=0xFF000000},{x=30,y=36,w=26,h=2,c=0xFFFFFFFF},{x=10,y=38,w=18,h=2,c=0xFFFFFFFF},{x=28,y=38,w=4,h=2,c=0xFF000000},{x=34,y=38,w=2,h=2,c=0xFF000000},{x=36,y=38,w=4,h=2,c=0xFFFFFFFF},{x=40,y=38,w=2,h=2,c=0xFF000000},{x=48,y=38,w=4,h=2,c=0xFF000000},{x=52,y=38,w=4,h=2,c=0xFFFFFFFF},{x=14,y=40,w=2,h=2,c=0xFF000000},{x=16,y=40,w=8,h=2,c=0xFFFFFFFF},{x=32,y=40,w=2,h=2,c=0xFF000000},{x=34,y=40,w=2,h=2,c=0xFFFFFFFF},{x=36,y=40,w=2,h=2,c=0xFF000000},{x=48,y=40,w=8,h=2,c=0xFF000000},{x=18,y=42,w=4,h=2,c=0xFF000000} },
}


-- 【旋转龙骨炮 LOD】3×3 采样（由 block2 占用图降采样，与 blaster_lod_levels.png 的 3×3 档一致）。
M.blaster_block3 = {
  Default = { {x=12,y=3,w=12,h=3,c=0xFFFFFFFF},{x=36,y=3,w=3,h=3,c=0xFFFFFFFF},{x=9,y=6,w=24,h=3,c=0xFFFFFFFF},{x=36,y=6,w=6,h=3,c=0xFFFFFFFF},{x=12,y=9,w=9,h=3,c=0xFFFFFFFF},{x=36,y=9,w=9,h=3,c=0xFFFFFFFF},{x=9,y=12,w=15,h=3,c=0xFFFFFFFF},{x=27,y=12,w=9,h=3,c=0xFFFFFFFF},{x=42,y=12,w=6,h=3,c=0xFFFFFFFF},{x=9,y=15,w=18,h=3,c=0xFFFFFFFF},{x=30,y=15,w=12,h=3,c=0xFFFFFFFF},{x=51,y=15,w=3,h=3,c=0xFFFFFFFF},{x=6,y=18,w=36,h=3,c=0xFFFFFFFF},{x=51,y=18,w=6,h=3,c=0xFFFFFFFF},{x=3,y=21,w=9,h=3,c=0xFFFFFFFF},{x=39,y=21,w=3,h=3,c=0xFFFFFFFF},{x=48,y=21,w=9,h=3,c=0xFFFFFFFF},{x=6,y=24,w=39,h=3,c=0xFFFFFFFF},{x=48,y=24,w=6,h=3,c=0xFFFFFFFF},{x=9,y=27,w=33,h=3,c=0xFFFFFFFF},{x=48,y=27,w=3,h=3,c=0xFFFFFFFF},{x=9,y=30,w=12,h=3,c=0xFFFFFFFF},{x=27,y=30,w=12,h=3,c=0xFFFFFFFF},{x=42,y=30,w=6,h=3,c=0xFFFFFFFF},{x=12,y=33,w=18,h=3,c=0xFFFFFFFF},{x=36,y=33,w=9,h=3,c=0xFFFFFFFF},{x=9,y=36,w=12,h=3,c=0xFFFFFFFF},{x=30,y=36,w=12,h=3,c=0xFFFFFFFF},{x=15,y=39,w=9,h=3,c=0xFFFFFFFF} },
  fire_0 = { {x=15,y=3,w=9,h=3,c=0xFFFFFFFF},{x=9,y=6,w=21,h=3,c=0xFFFFFFFF},{x=36,y=6,w=6,h=3,c=0xFFFFFFFF},{x=6,y=9,w=3,h=3,c=0xFFFFFFFF},{x=12,y=9,w=18,h=3,c=0xFFFFFFFF},{x=36,y=9,w=9,h=3,c=0xFFFFFFFF},{x=9,y=12,w=12,h=3,c=0xFFFFFFFF},{x=30,y=12,w=9,h=3,c=0xFFFFFFFF},{x=42,y=12,w=3,h=3,c=0xFFFFFFFF},{x=9,y=15,w=18,h=3,c=0xFFFFFFFF},{x=30,y=15,w=12,h=3,c=0xFFFFFFFF},{x=48,y=15,w=3,h=3,c=0xFFFFFFFF},{x=6,y=18,w=36,h=3,c=0xFFFFFFFF},{x=48,y=18,w=9,h=3,c=0xFFFFFFFF},{x=3,y=21,w=9,h=3,c=0xFFFFFFFF},{x=39,y=21,w=3,h=3,c=0xFFFFFFFF},{x=48,y=21,w=9,h=3,c=0xFFFFFFFF},{x=6,y=24,w=39,h=3,c=0xFFFFFFFF},{x=9,y=27,w=30,h=3,c=0xFFFFFFFF},{x=12,y=30,w=12,h=3,c=0xFFFFFFFF},{x=27,y=30,w=3,h=3,c=0xFFFFFFFF},{x=33,y=30,w=3,h=3,c=0xFFFFFFFF},{x=42,y=30,w=3,h=3,c=0xFFFFFFFF},{x=12,y=33,w=12,h=3,c=0xFFFFFFFF},{x=36,y=33,w=9,h=3,c=0xFFFFFFFF},{x=12,y=36,w=18,h=3,c=0xFFFFFFFF},{x=36,y=36,w=6,h=3,c=0xFFFFFFFF},{x=18,y=39,w=6,h=3,c=0xFFFFFFFF} },
  fire_2 = { {x=18,y=0,w=6,h=3,c=0xFFFFFFFF},{x=12,y=3,w=18,h=3,c=0xFFFFFFFF},{x=36,y=3,w=6,h=3,c=0xFFFFFFFF},{x=12,y=6,w=9,h=3,c=0xFFFFFFFF},{x=30,y=6,w=15,h=3,c=0xFFFFFFFF},{x=48,y=6,w=3,h=3,c=0xFFFFFFFF},{x=12,y=9,w=12,h=3,c=0xFFFFFFFF},{x=33,y=9,w=6,h=3,c=0xFFFFFFFF},{x=42,y=9,w=6,h=3,c=0xFFFFFFFF},{x=51,y=9,w=3,h=3,c=0xFFFFFFFF},{x=9,y=12,w=15,h=3,c=0xFFFFFFFF},{x=27,y=12,w=12,h=3,c=0xFFFFFFFF},{x=48,y=12,w=6,h=3,c=0xFFFFFFFF},{x=6,y=15,w=24,h=3,c=0xFFFFFFFF},{x=33,y=15,w=9,h=3,c=0xFFFFFFFF},{x=3,y=18,w=30,h=3,c=0xFFFFFFFF},{x=39,y=18,w=3,h=3,c=0xFFFFFFFF},{x=3,y=21,w=9,h=3,c=0xFFFFFFFF},{x=6,y=24,w=27,h=3,c=0xFFFFFFFF},{x=36,y=24,w=6,h=3,c=0xFFFFFFFF},{x=6,y=27,w=18,h=3,c=0xFFFFFFFF},{x=30,y=27,w=12,h=3,c=0xFFFFFFFF},{x=9,y=30,w=12,h=3,c=0xFFFFFFFF},{x=27,y=30,w=30,h=3,c=0xFFFFFFFF},{x=12,y=33,w=12,h=3,c=0xFFFFFFFF},{x=27,y=33,w=6,h=3,c=0xFFFFFFFF},{x=39,y=33,w=15,h=3,c=0xFFFFFFFF},{x=12,y=36,w=12,h=3,c=0xFFFFFFFF},{x=36,y=36,w=6,h=3,c=0xFFFFFFFF},{x=12,y=39,w=12,h=3,c=0xFFFFFFFF},{x=36,y=39,w=3,h=3,c=0xFFFFFFFF},{x=18,y=42,w=3,h=2,c=0xFFFFFFFF} },
  fire_4 = { {x=12,y=3,w=12,h=3,c=0xFFFFFFFF},{x=36,y=3,w=3,h=3,c=0xFFFFFFFF},{x=48,y=3,w=6,h=3,c=0xFFFFFFFF},{x=9,y=6,w=24,h=3,c=0xFFFFFFFF},{x=36,y=6,w=9,h=3,c=0xFFFFFFFF},{x=48,y=6,w=6,h=3,c=0xFFFFFFFF},{x=12,y=9,w=9,h=3,c=0xFFFFFFFF},{x=36,y=9,w=12,h=3,c=0xFFFFFFFF},{x=9,y=12,w=15,h=3,c=0xFFFFFFFF},{x=33,y=12,w=3,h=3,c=0xFFFFFFFF},{x=9,y=15,w=15,h=3,c=0xFFFFFFFF},{x=33,y=15,w=9,h=3,c=0xFFFFFFFF},{x=6,y=18,w=36,h=3,c=0xFFFFFFFF},{x=3,y=21,w=9,h=3,c=0xFFFFFFFF},{x=39,y=21,w=3,h=3,c=0xFFFFFFFF},{x=6,y=24,w=39,h=3,c=0xFFFFFFFF},{x=9,y=27,w=33,h=3,c=0xFFFFFFFF},{x=9,y=30,w=12,h=3,c=0xFFFFFFFF},{x=27,y=30,w=12,h=3,c=0xFFFFFFFF},{x=12,y=33,w=18,h=3,c=0xFFFFFFFF},{x=36,y=33,w=12,h=3,c=0xFFFFFFFF},{x=9,y=36,w=12,h=3,c=0xFFFFFFFF},{x=30,y=36,w=27,h=3,c=0xFFFFFFFF},{x=15,y=39,w=9,h=3,c=0xFFFFFFFF} },
}
return M

end)()

__modules['default_import_file/workspace/sans-fight/lua/music'] = (function()
-- ============================================================================
-- music.lua —— 战斗 BGM：用千星「音效」逐音符拟合播放（客户端侧，无需服务端节点图）
-- ----------------------------------------------------------------------------
-- 数据来源：music1.mp3 自动扒谱 v1
--   速度 156.25 BPM（4/4），八分音符网格 STEP = 0.192s，共 743 格 ≈ 142.66s，整场循环
--   原曲时长 158.57s —— 本谱只覆盖前 142.66s（约 90%），末尾收尾段没扒；要整首得补谱
-- 版权：本文件只有「音符时间轴 + 平台音效 ID」，不含任何原曲录音；音效全部来自千星音效库。
-- ----------------------------------------------------------------------------
-- 宿主接法（lua/main.lua）：
--   music:start()     开战 / 重开战斗 → 从头播
--   music:update(dt)  每帧推进（OnLevelUpdate 里调）
--   music:stop()      结算 / 退出奇域 → 停
-- ============================================================================

local M = {}

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
  M.playing = true
  M.i, M.t = 1, 0
  M.lastName, M.lastIndex = nil, 0
  M.starts = M.starts + 1
  print(string.format('music: start #%d (score=%d 格 %.2fs, 音效绑定 %d 项)',
    M.starts, #score(), #score() * M.STEP, boundCount()))
end

function M.stop()
  M.playing = false
  M.i, M.t = 1, 0
  M.lastName, M.lastIndex = nil, 0
  stopVoice()
end

function M.update(dt)
  if not M.playing then return end
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

function M.reset() M.start() end            -- 语义别名
function M.info() return M.i, M.t, M.playing, M.triggers end

return M

end)()

__modules['default_import_file/workspace/sans-fight/lua/textart'] = (function()
-- Generated rectangle glyphs: no runtime font or text template required.
local T = { height = 20, glyphs = {} }
T.glyphs[32] = {w=11, advance=9, rects={}}
T.glyphs[33] = {w=11, advance=9, rects={{3,1,2,2},{4,3,1,6},{3,10,2,2}}}
T.glyphs[34] = {w=11, advance=9, rects={{2,1,2,4},{5,1,2,4}}}
T.glyphs[35] = {w=11, advance=9, rects={{3,2,1,1},{6,2,1,3},{2,3,2,2},{1,5,8,1},{2,6,2,1},{5,6,2,2},{2,7,1,1},{0,8,8,1},{2,9,1,3},{5,9,1,3}}}
T.glyphs[36] = {w=11, advance=9, rects={{4,0,2,2},{2,2,5,1},{1,3,2,3},{4,3,1,3},{2,6,3,1},{3,7,4,1},{3,8,2,3},{6,8,2,3},{1,11,6,1},{3,12,1,2}}}
T.glyphs[37] = {w=11, advance=9, rects={{1,1,3,1},{7,1,1,1},{0,2,2,3},{3,2,1,1},{6,2,2,1},{3,3,2,1},{6,3,1,1},{3,4,1,1},{5,4,1,1},{1,5,5,1},{4,6,1,1},{3,7,5,1},{2,8,4,1},{7,8,1,1},{2,9,1,1},{4,9,2,2},{7,9,2,1},{1,10,2,1},{7,10,1,1},{0,11,2,1},{5,11,3,1}}}
T.glyphs[38] = {w=11, advance=9, rects={{2,1,4,1},{2,2,1,1},{5,2,2,3},{1,3,2,2},{2,5,4,1},{2,6,3,1},{1,7,4,1},{6,7,2,1},{0,8,2,2},{4,8,4,1},{5,9,3,2},{1,10,2,1},{2,11,7,1}}}
T.glyphs[39] = {w=11, advance=9, rects={{3,1,2,2},{4,3,1,2}}}
T.glyphs[40] = {w=11, advance=9, rects={{5,0,2,1},{4,1,2,1},{4,2,1,1},{3,3,2,1},{3,4,1,1},{2,5,2,5},{3,10,1,1},{3,11,2,1},{4,12,2,2},{5,14,2,1}}}
T.glyphs[41] = {w=11, advance=9, rects={{2,0,1,1},{2,1,2,1},{3,2,2,1},{4,3,2,2},{5,5,1,2},{5,7,2,1},{5,8,1,2},{4,10,2,2},{3,12,2,1},{2,13,2,1},{2,14,1,1}}}
T.glyphs[42] = {w=11, advance=9, rects={{4,1,1,2},{1,2,2,1},{6,2,1,1},{2,3,5,1},{3,4,3,1},{2,5,5,1},{1,6,2,1},{4,6,1,2},{6,6,1,1}}}
T.glyphs[43] = {w=11, advance=9, rects={{4,4,1,3},{1,7,7,1},{4,8,1,3}}}
T.glyphs[44] = {w=11, advance=9, rects={{3,10,2,1},{3,11,3,1},{4,12,2,1},{3,13,2,1},{2,14,2,1}}}
T.glyphs[45] = {w=11, advance=9, rects={{2,7,5,1}}}
T.glyphs[46] = {w=11, advance=9, rects={{3,10,2,1},{3,11,3,1}}}
T.glyphs[47] = {w=11, advance=9, rects={{6,1,1,2},{5,3,2,1},{5,4,1,1},{4,5,2,1},{4,6,1,1},{3,7,2,2},{3,9,1,1},{2,10,2,1},{2,11,1,1},{1,12,2,2}}}
T.glyphs[48] = {w=11, advance=9, rects={{2,2,4,1},{1,3,2,2},{5,3,2,1},{6,4,2,2},{1,5,1,3},{4,6,4,1},{3,7,2,1},{7,7,1,1},{1,8,2,3},{6,8,2,2},{5,10,2,1},{2,11,4,1}}}
T.glyphs[49] = {w=11, advance=9, rects={{3,2,3,1},{2,3,4,1},{1,4,1,1},{4,4,2,7},{1,11,7,1}}}
T.glyphs[50] = {w=11, advance=9, rects={{2,2,4,1},{1,3,2,1},{5,3,2,1},{6,4,1,2},{5,6,2,1},{4,7,2,2},{3,9,2,1},{2,10,2,1},{1,11,7,1}}}
T.glyphs[51] = {w=11, advance=9, rects={{1,2,5,1},{5,3,2,1},{6,4,1,1},{5,5,2,1},{2,6,4,1},{5,7,2,1},{6,8,2,2},{5,10,2,1},{1,11,5,1}}}
T.glyphs[52] = {w=11, advance=9, rects={{4,2,3,2},{3,4,4,1},{2,5,2,1},{5,5,2,4},{2,6,1,1},{1,7,2,1},{1,8,1,1},{0,9,9,1},{5,10,2,2}}}
T.glyphs[53] = {w=11, advance=9, rects={{1,2,6,1},{1,3,2,3},{1,6,5,1},{5,7,2,1},{6,8,2,2},{5,10,2,1},{1,11,5,1}}}
T.glyphs[54] = {w=11, advance=9, rects={{3,2,4,1},{2,3,2,1},{1,4,2,2},{1,6,6,1},{1,7,2,4},{6,7,2,4},{2,11,5,1}}}
T.glyphs[55] = {w=11, advance=9, rects={{1,2,7,1},{6,3,2,1},{6,4,1,1},{5,5,2,1},{5,6,1,1},{4,7,2,1},{4,8,1,1},{3,9,2,1},{3,10,1,1},{2,11,2,1}}}
T.glyphs[56] = {w=11, advance=9, rects={{2,2,5,1},{1,3,2,2},{6,3,2,2},{2,5,2,1},{5,5,2,1},{3,6,3,1},{2,7,2,1},{5,7,2,1},{1,8,2,3},{6,8,2,3},{2,11,5,1}}}
T.glyphs[57] = {w=11, advance=9, rects={{2,2,4,1},{1,3,2,1},{5,3,2,1},{1,4,1,2},{6,4,2,3},{1,6,2,1},{2,7,6,1},{6,8,2,1},{6,9,1,1},{4,10,3,1},{1,11,4,1}}}
T.glyphs[58] = {w=11, advance=9, rects={{3,5,2,2},{3,10,2,2}}}
T.glyphs[59] = {w=11, advance=9, rects={{3,5,2,2},{3,10,2,1},{4,11,2,2},{3,13,2,1},{2,14,2,1}}}
T.glyphs[60] = {w=11, advance=9, rects={{6,3,1,1},{4,4,3,1},{3,5,2,1},{2,6,2,1},{1,7,2,1},{2,8,2,1},{3,9,2,1},{4,10,3,1},{6,11,1,1}}}
T.glyphs[61] = {w=11, advance=9, rects={{1,6,7,1},{1,9,7,1}}}
T.glyphs[62] = {w=11, advance=9, rects={{2,3,1,1},{2,4,2,1},{3,5,3,1},{5,6,2,1},{5,7,3,1},{5,8,2,1},{3,9,3,1},{2,10,2,1},{2,11,1,1}}}
T.glyphs[63] = {w=11, advance=9, rects={{2,1,3,1},{4,2,3,1},{5,3,2,1},{6,4,1,1},{5,5,2,1},{3,6,3,1},{3,7,2,2},{3,10,2,2}}}
T.glyphs[64] = {w=11, advance=9, rects={{3,1,4,1},{2,2,2,1},{6,2,2,1},{1,3,2,1},{7,3,1,1},{1,4,1,1},{7,4,2,1},{0,5,2,2},{3,5,6,1},{3,6,1,1},{5,6,4,1},{0,7,1,4},{2,7,2,2},{5,7,1,2},{7,7,2,2},{2,9,4,1},{7,9,1,1},{3,10,5,1},{0,11,2,2},{1,13,2,1},{6,13,1,1},{2,14,4,1}}}
T.glyphs[65] = {w=11, advance=9, rects={{3,2,3,2},{2,4,2,2},{5,4,1,1},{5,5,2,2},{2,6,1,1},{1,7,2,2},{6,7,1,1},{6,8,2,1},{1,9,7,1},{0,10,2,2},{7,10,1,1},{7,11,2,1}}}
T.glyphs[66] = {w=11, advance=9, rects={{1,2,6,1},{1,3,2,3},{6,3,2,2},{5,5,2,1},{1,6,6,1},{1,7,2,4},{6,7,2,4},{1,11,5,1}}}
T.glyphs[67] = {w=11, advance=9, rects={{3,2,4,1},{2,3,2,1},{7,3,1,1},{1,4,2,2},{1,6,1,2},{1,8,2,2},{2,10,2,1},{7,10,1,1},{3,11,4,1}}}
T.glyphs[68] = {w=11, advance=9, rects={{1,2,5,1},{1,3,1,8},{5,3,2,1},{6,4,2,1},{7,5,1,3},{6,8,2,2},{5,10,2,1},{1,11,5,1}}}
T.glyphs[69] = {w=11, advance=9, rects={{1,2,7,1},{1,3,2,3},{1,6,6,1},{1,7,2,4},{1,11,7,1}}}
T.glyphs[70] = {w=11, advance=9, rects={{1,2,6,1},{1,3,2,4},{1,7,6,1},{1,8,2,4}}}
T.glyphs[71] = {w=11, advance=9, rects={{3,2,4,1},{2,3,2,1},{7,3,1,1},{1,4,2,1},{1,5,1,1},{0,6,2,2},{4,7,4,1},{1,8,1,1},{6,8,2,3},{1,9,2,1},{1,10,3,1},{3,11,5,1}}}
T.glyphs[72] = {w=11, advance=9, rects={{1,2,1,4},{6,2,2,4},{1,6,7,1},{1,7,1,5},{6,7,2,5}}}
T.glyphs[73] = {w=11, advance=9, rects={{1,2,7,1},{4,3,1,8},{1,11,7,1}}}
T.glyphs[74] = {w=11, advance=9, rects={{1,2,6,1},{5,3,2,8},{1,10,1,1},{2,11,4,1}}}
T.glyphs[75] = {w=11, advance=9, rects={{1,2,2,4},{6,2,2,1},{5,3,2,1},{4,4,2,1},{4,5,1,1},{1,6,3,1},{1,7,4,1},{1,8,2,4},{4,8,1,1},{4,9,2,1},{5,10,2,1},{6,11,2,1}}}
T.glyphs[76] = {w=11, advance=9, rects={{2,2,1,9},{2,11,6,1}}}
T.glyphs[77] = {w=11, advance=9, rects={{1,2,2,3},{6,2,2,2},{5,4,3,1},{1,5,1,2},{3,5,1,2},{5,5,1,2},{7,5,1,6},{0,7,2,5},{3,7,2,1},{4,8,1,1},{7,11,2,1}}}
T.glyphs[78] = {w=11, advance=9, rects={{1,2,2,1},{6,2,2,6},{1,3,3,2},{1,5,1,7},{3,5,1,1},{4,6,1,2},{4,8,4,1},{5,9,3,2},{6,11,2,1}}}
T.glyphs[79] = {w=11, advance=9, rects={{2,2,5,1},{1,3,2,1},{6,3,2,2},{1,4,1,1},{0,5,2,4},{7,5,1,4},{1,9,1,1},{6,9,2,1},{1,10,2,1},{6,10,1,1},{2,11,4,1}}}
T.glyphs[80] = {w=11, advance=9, rects={{1,2,6,1},{1,3,2,4},{6,3,2,4},{1,7,5,1},{1,8,2,4}}}
T.glyphs[81] = {w=11, advance=9, rects={{2,2,5,1},{1,3,2,1},{6,3,2,2},{1,4,1,1},{0,5,2,4},{7,5,1,4},{1,9,1,1},{6,9,2,1},{1,10,2,1},{6,10,1,1},{2,11,4,1},{4,12,1,1},{4,13,2,1},{8,13,1,1},{5,14,3,1}}}
T.glyphs[82] = {w=11, advance=9, rects={{1,2,5,1},{1,3,2,3},{5,3,2,1},{6,4,2,1},{5,5,2,1},{1,6,5,1},{1,7,2,5},{4,7,2,1},{5,8,2,2},{6,10,2,2}}}
T.glyphs[83] = {w=11, advance=9, rects={{2,2,5,1},{1,3,2,3},{2,6,3,1},{4,7,3,1},{6,8,2,3},{1,11,5,1}}}
T.glyphs[84] = {w=11, advance=9, rects={{1,2,7,1},{4,3,1,9}}}
T.glyphs[85] = {w=11, advance=9, rects={{1,2,1,8},{6,2,2,8},{1,10,2,1},{6,10,1,1},{2,11,4,1}}}
T.glyphs[86] = {w=11, advance=9, rects={{0,2,2,2},{7,2,2,1},{7,3,1,1},{1,4,2,3},{6,4,2,2},{6,6,1,1},{2,7,2,3},{5,7,2,2},{5,9,1,1},{3,10,3,2}}}
T.glyphs[87] = {w=11, advance=9, rects={{0,2,2,4},{7,2,2,1},{7,3,1,6},{4,5,1,1},{1,6,1,3},{3,6,2,1},{3,7,3,1},{3,8,1,1},{5,8,1,1},{1,9,3,1},{5,9,3,2},{1,10,2,2},{6,11,2,1}}}
T.glyphs[88] = {w=11, advance=9, rects={{1,2,2,2},{6,2,2,2},{2,4,2,1},{5,4,2,1},{3,5,3,3},{2,8,4,1},{2,9,2,1},{5,9,2,1},{1,10,2,1},{6,10,2,2},{0,11,2,1}}}
T.glyphs[89] = {w=11, advance=9, rects={{0,2,2,1},{7,2,2,1},{1,3,2,2},{6,3,2,1},{6,4,1,1},{2,5,2,1},{5,5,2,1},{3,6,3,2},{4,8,1,4}}}
T.glyphs[90] = {w=11, advance=9, rects={{1,2,7,1},{6,3,1,1},{5,4,2,1},{4,5,2,1},{4,6,1,1},{3,7,2,1},{3,8,1,1},{2,9,2,1},{1,10,2,1},{1,11,7,1}}}
T.glyphs[91] = {w=11, advance=9, rects={{3,1,4,1},{3,2,1,12},{3,14,4,1}}}
T.glyphs[92] = {w=11, advance=9, rects={{1,1,2,1},{2,2,1,1},{2,3,2,1},{3,4,1,1},{3,5,2,2},{4,7,1,1},{4,8,2,1},{5,9,1,1},{5,10,2,2},{6,12,1,1},{6,13,2,1}}}
T.glyphs[93] = {w=11, advance=9, rects={{2,1,4,1},{5,2,1,12},{2,14,4,1}}}
T.glyphs[94] = {w=11, advance=9, rects={{3,2,2,1},{3,3,3,1},{2,4,2,1},{5,4,2,1},{2,5,1,1},{6,5,1,1},{1,6,2,1},{6,6,2,1}}}
T.glyphs[95] = {w=11, advance=9, rects={{0,14,9,1}}}
T.glyphs[96] = {w=11, advance=9, rects={{2,1,2,1},{3,2,2,1}}}
T.glyphs[97] = {w=11, advance=9, rects={{2,5,5,1},{2,6,1,1},{6,6,1,1},{6,7,2,1},{2,8,6,1},{1,9,2,2},{6,9,2,1},{5,10,3,1},{2,11,6,1}}}
T.glyphs[98] = {w=11, advance=9, rects={{1,1,2,4},{1,5,6,1},{1,6,3,1},{6,6,2,4},{1,7,2,4},{6,10,1,1},{1,11,5,1}}}
T.glyphs[99] = {w=11, advance=9, rects={{3,5,4,1},{2,6,2,1},{1,7,2,3},{2,10,2,1},{3,11,4,1}}}
T.glyphs[100] = {w=11, advance=9, rects={{6,1,2,4},{2,5,6,1},{1,6,2,2},{6,6,2,4},{1,8,1,2},{1,10,2,1},{5,10,3,1},{2,11,3,1},{6,11,2,1}}}
T.glyphs[101] = {w=11, advance=9, rects={{2,5,5,1},{1,6,2,2},{6,6,2,2},{1,8,7,1},{1,9,2,2},{2,11,6,1}}}
T.glyphs[102] = {w=11, advance=9, rects={{4,1,4,1},{3,2,2,3},{0,5,8,1},{3,6,2,6}}}
T.glyphs[103] = {w=11, advance=9, rects={{2,5,6,1},{1,6,2,3},{5,6,2,1},{6,7,1,1},{5,8,2,1},{1,9,5,1},{1,10,2,1},{1,11,7,1},{1,12,2,2},{6,12,2,2},{1,14,6,1}}}
T.glyphs[104] = {w=11, advance=9, rects={{1,1,2,4},{1,5,6,1},{1,6,3,1},{6,6,1,1},{1,7,2,5},{6,7,2,5}}}
T.glyphs[105] = {w=11, advance=9, rects={{3,1,2,2},{1,5,4,1},{4,6,1,5},{1,11,7,1}}}
T.glyphs[106] = {w=11, advance=9, rects={{5,1,2,2},{1,5,6,1},{5,6,2,7},{1,13,1,1},{4,13,2,1},{2,14,3,1}}}
T.glyphs[107] = {w=11, advance=9, rects={{1,1,2,6},{6,5,2,1},{4,6,2,1},{1,7,4,2},{1,9,2,3},{4,9,2,1},{5,10,2,1},{6,11,2,1}}}
T.glyphs[108] = {w=11, advance=9, rects={{1,1,4,1},{4,2,1,9},{1,11,7,1}}}
T.glyphs[109] = {w=11, advance=9, rects={{1,5,7,1},{1,6,2,1},{4,6,2,1},{7,6,1,6},{1,7,1,5},{4,7,1,5}}}
T.glyphs[110] = {w=11, advance=9, rects={{1,5,6,1},{1,6,3,1},{6,6,2,6},{1,7,2,5}}}
T.glyphs[111] = {w=11, advance=9, rects={{2,5,5,1},{1,6,2,1},{6,6,2,2},{1,7,1,3},{7,8,1,1},{6,9,2,2},{1,10,2,1},{2,11,5,1}}}
T.glyphs[112] = {w=11, advance=9, rects={{1,5,6,1},{1,6,3,1},{6,6,2,4},{1,7,2,4},{6,10,1,1},{1,11,5,1},{1,12,2,3}}}
T.glyphs[113] = {w=11, advance=9, rects={{2,5,6,1},{1,6,2,2},{6,6,2,4},{1,8,1,2},{1,10,2,1},{5,10,3,1},{2,11,3,1},{6,11,2,4}}}
T.glyphs[114] = {w=11, advance=9, rects={{1,5,2,1},{4,5,3,1},{1,6,3,1},{6,6,2,2},{1,7,2,5}}}
T.glyphs[115] = {w=11, advance=9, rects={{2,5,5,1},{2,6,1,1},{2,7,2,1},{3,8,4,1},{5,9,2,1},{6,10,1,1},{1,11,6,1}}}
T.glyphs[116] = {w=11, advance=9, rects={{3,2,1,3},{0,5,8,1},{3,6,1,4},{3,10,2,1},{3,11,5,1}}}
T.glyphs[117] = {w=11, advance=9, rects={{1,5,2,6},{6,5,2,5},{5,10,3,1},{2,11,6,1}}}
T.glyphs[118] = {w=11, advance=9, rects={{1,5,1,1},{6,5,2,2},{1,6,2,2},{6,7,1,1},{2,8,2,2},{5,8,2,1},{5,9,1,1},{3,10,3,2}}}
T.glyphs[119] = {w=11, advance=9, rects={{0,5,2,2},{7,5,2,1},{7,6,1,4},{1,7,1,3},{4,7,1,1},{3,8,3,1},{3,9,1,1},{5,9,1,1},{1,10,3,1},{5,10,3,2},{1,11,2,1}}}
T.glyphs[120] = {w=11, advance=9, rects={{1,5,2,1},{6,5,2,1},{2,6,2,1},{5,6,2,1},{3,7,3,2},{3,9,1,1},{5,9,1,1},{2,10,1,1},{5,10,2,1},{1,11,2,1},{6,11,2,1}}}
T.glyphs[121] = {w=11, advance=9, rects={{1,5,1,1},{6,5,2,2},{1,6,2,1},{2,7,1,1},{6,7,1,1},{2,8,2,2},{5,8,2,1},{5,9,1,1},{3,10,3,1},{3,11,2,2},{2,13,2,1},{0,14,3,1}}}
T.glyphs[122] = {w=11, advance=9, rects={{1,5,6,1},{5,6,2,1},{4,7,2,1},{4,8,1,1},{3,9,1,1},{2,10,2,1},{1,11,7,1}}}
T.glyphs[123] = {w=11, advance=9, rects={{4,1,3,1},{4,2,1,1},{3,3,2,4},{1,7,3,1},{3,8,2,5},{4,13,1,1},{4,14,3,1}}}
T.glyphs[124] = {w=11, advance=9, rects={{4,0,1,15}}}
T.glyphs[125] = {w=11, advance=9, rects={{2,1,2,1},{3,2,2,1},{4,3,1,3},{4,6,2,1},{5,7,3,1},{4,8,2,1},{4,9,1,4},{3,13,2,1},{2,14,2,1}}}
T.glyphs[126] = {w=11, advance=9, rects={{1,6,3,1},{7,6,1,2},{1,7,1,1},{3,7,2,1},{0,8,2,1},{5,8,2,1}}}
T.glyphs[167] = {w=10, advance=8, rects={{2,4,4,1},{2,5,2,1},{5,5,1,1},{1,6,2,1},{2,7,2,1},{2,8,3,1},{1,9,5,1},{1,10,2,2},{5,10,2,3},{2,12,2,1},{3,13,3,1},{4,14,2,1},{5,15,1,1},{1,16,2,1},{4,16,2,1},{1,17,4,1}}}
T.glyphs[177] = {w=14, advance=12, rects={{5,8,2,3},{2,11,8,1},{5,12,2,3},{2,16,8,1}}}
T.glyphs[183] = {w=6, advance=4, rects={{1,11,2,2}}}
T.glyphs[215] = {w=14, advance=12, rects={{2,8,2,1},{8,8,1,1},{3,9,2,1},{7,9,2,1},{4,10,4,1},{5,11,2,1},{4,12,4,1},{3,13,2,1},{7,13,2,1},{2,14,2,1},{8,14,1,1}}}
T.glyphs[8211] = {w=11, advance=9, rects={{0,12,9,1}}}
T.glyphs[8212] = {w=19, advance=17, rects={{0,12,17,1}}}
T.glyphs[8220] = {w=18, advance=16, rects={{11,5,1,2},{14,5,1,1},{13,6,2,2},{10,7,2,2},{13,8,1,1}}}
T.glyphs[8221] = {w=18, advance=16, rects={{2,5,1,1},{4,5,2,2},{1,6,2,2},{4,7,1,2},{1,8,1,1}}}
T.glyphs[8230] = {w=15, advance=13, rects={{1,15,2,2},{6,15,1,2},{10,15,2,2}}}
T.glyphs[8592] = {w=18, advance=16, rects={{3,8,1,1},{2,9,2,1},{1,10,15,1},{2,11,2,1},{3,12,1,1}}}
T.glyphs[8593] = {w=10, advance=8, rects={{3,4,2,2},{2,6,4,1},{1,7,1,1},{3,7,2,11},{6,7,1,1}}}
T.glyphs[8594] = {w=18, advance=16, rects={{12,8,1,1},{12,9,2,1},{0,10,15,1},{12,11,2,1},{12,12,1,1}}}
T.glyphs[8595] = {w=10, advance=8, rects={{3,4,2,11},{1,14,1,1},{6,14,1,1},{2,15,4,1},{3,16,2,2}}}
T.glyphs[8596] = {w=13, advance=11, rects={{1,5,9,1},{1,6,2,10},{8,6,2,10},{1,16,9,1}}}
T.glyphs[8658] = {w=13, advance=11, rects={{1,5,9,1},{1,6,2,10},{8,6,2,10},{1,16,9,1}}}
T.glyphs[8712] = {w=18, advance=16, rects={{5,7,9,1},{3,8,3,1},{3,9,1,1},{2,10,2,1},{2,11,12,1},{2,12,2,2},{3,14,1,1},{3,15,3,1},{5,16,9,1}}}
T.glyphs[8722] = {w=14, advance=12, rects={{2,11,8,1}}}
T.glyphs[8776] = {w=14, advance=12, rects={{2,9,4,1},{9,9,1,1},{2,10,1,1},{5,10,5,1},{2,13,4,1},{9,13,1,1},{2,14,1,1},{5,14,5,1}}}
T.glyphs[8804] = {w=14, advance=12, rects={{8,8,2,1},{6,9,3,1},{3,10,4,1},{2,11,3,1},{3,12,4,1},{6,13,4,1},{8,14,2,1},{2,16,8,1}}}
T.glyphs[8805] = {w=14, advance=12, rects={{2,8,2,1},{3,9,3,1},{5,10,4,1},{7,11,3,1},{5,12,4,1},{3,13,3,1},{2,14,2,1},{2,16,8,1}}}
T.glyphs[9312] = {w=18, advance=16, rects={{5,5,6,1},{3,6,3,1},{10,6,3,1},{2,7,2,1},{12,7,2,1},{2,8,1,1},{7,8,2,1},{13,8,1,1},{1,9,1,7},{5,9,4,1},{14,9,1,7},{8,10,1,5},{7,15,2,1},{2,16,1,1},{6,16,5,1},{13,16,1,1},{2,17,2,1},{12,17,2,1},{4,18,2,1},{10,18,2,1},{5,19,6,1}}}
T.glyphs[9313] = {w=18, advance=16, rects={{5,5,6,1},{3,6,3,1},{10,6,3,1},{2,7,2,1},{12,7,2,1},{2,8,1,1},{6,8,4,1},{13,8,1,1},{1,9,1,7},{5,9,2,1},{9,9,2,3},{14,9,1,7},{8,12,2,1},{7,13,2,1},{6,14,2,1},{5,15,2,1},{2,16,1,1},{5,16,6,1},{13,16,1,1},{2,17,2,1},{12,17,2,1},{4,18,2,1},{10,18,2,1},{5,19,6,1}}}
T.glyphs[9314] = {w=18, advance=16, rects={{5,5,6,1},{3,6,3,1},{10,6,3,1},{2,7,2,1},{12,7,2,1},{2,8,1,1},{6,8,4,1},{13,8,1,1},{1,9,1,7},{6,9,1,1},{8,9,2,1},{14,9,1,7},{9,10,1,1},{8,11,2,1},{6,12,4,1},{8,13,3,1},{9,14,2,2},{5,15,1,1},{2,16,1,1},{6,16,4,1},{13,16,1,1},{2,17,2,1},{12,17,2,1},{4,18,2,1},{10,18,2,1},{5,19,6,1}}}
T.glyphs[9315] = {w=18, advance=16, rects={{5,5,6,1},{3,6,3,1},{10,6,3,1},{2,7,2,1},{12,7,2,1},{2,8,1,1},{8,8,2,1},{13,8,1,1},{1,9,1,7},{7,9,3,2},{14,9,1,7},{6,11,1,1},{8,11,2,3},{5,12,2,1},{5,13,1,1},{4,14,7,1},{8,15,2,2},{2,16,1,1},{13,16,1,1},{2,17,2,1},{12,17,2,1},{4,18,2,1},{10,18,2,1},{5,19,6,1}}}
T.glyphs[9316] = {w=18, advance=16, rects={{5,5,6,1},{3,6,3,1},{10,6,3,1},{2,7,2,1},{12,7,2,1},{2,8,1,1},{6,8,4,1},{13,8,1,1},{1,9,1,7},{6,9,1,2},{14,9,1,7},{6,11,4,1},{8,12,2,1},{9,13,2,2},{5,15,2,1},{8,15,2,1},{2,16,1,1},{6,16,3,1},{13,16,1,1},{2,17,2,1},{12,17,2,1},{4,18,2,1},{10,18,2,1},{5,19,6,1}}}
T.glyphs[9650] = {w=18, advance=16, rects={{7,7,2,2},{6,9,4,2},{5,11,6,2},{4,13,8,2},{3,15,10,2}}}
T.glyphs[9660] = {w=18, advance=16, rects={{2,6,11,1},{3,7,10,1},{4,8,8,2},{5,10,6,2},{6,12,4,2},{7,14,2,2}}}
T.glyphs[9733] = {w=15, advance=13, rects={{6,5,1,3},{5,8,3,1},{1,9,7,1},{2,10,10,1},{3,11,7,1},{4,12,5,2},{3,14,3,1},{7,14,3,1},{3,15,2,1},{8,15,2,1},{3,16,1,1},{9,16,1,1}}}
T.glyphs[9888] = {w=13, advance=11, rects={{1,5,9,1},{1,6,2,10},{8,6,2,10},{1,16,9,1}}}
T.glyphs[12288] = {w=18, advance=16, rects={}}
T.glyphs[12289] = {w=18, advance=16, rects={{1,15,1,1},{2,16,1,1},{3,17,1,1},{3,18,2,1}}}
T.glyphs[12290] = {w=18, advance=16, rects={{2,15,2,1},{1,16,4,1},{1,17,1,1},{4,17,1,1},{2,18,2,1}}}
T.glyphs[12298] = {w=18, advance=16, rects={{11,4,1,1},{13,4,2,1},{10,5,2,1},{13,5,1,1},{10,6,1,2},{12,6,2,1},{12,7,1,1},{9,8,4,1},{9,9,1,1},{11,9,1,2},{8,10,2,1},{8,11,1,1},{10,11,2,1},{8,12,2,1},{11,12,1,2},{9,13,1,1},{9,14,4,1},{10,15,1,2},{12,15,1,1},{12,16,2,1},{10,17,2,1},{13,17,1,1},{11,18,1,1},{13,18,2,1}}}
T.glyphs[12299] = {w=18, advance=16, rects={{1,4,2,1},{4,4,1,1},{2,5,1,1},{4,5,2,1},{2,6,2,1},{5,6,1,1},{3,7,1,1},{5,7,2,1},{3,8,4,1},{4,9,1,1},{6,9,1,1},{4,10,4,1},{4,11,2,1},{7,11,1,1},{4,12,4,1},{4,13,1,1},{6,13,1,2},{3,14,2,1},{3,15,1,1},{5,15,2,1},{2,16,2,1},{5,16,1,1},{2,17,1,1},{4,17,2,1},{1,18,2,1},{4,18,1,1}}}
T.glyphs[12300] = {w=18, advance=16, rects={{10,4,5,1},{10,5,2,14}}}
T.glyphs[12301] = {w=18, advance=16, rects={{4,4,2,14},{1,18,5,1}}}
T.glyphs[12302] = {w=18, advance=16, rects={{9,4,6,1},{9,5,2,1},{14,5,1,1},{9,6,6,1},{9,7,4,12}}}
T.glyphs[12303] = {w=18, advance=16, rects={{4,4,3,12},{1,16,6,1},{1,17,1,1},{5,17,2,1},{1,18,6,1}}}
T.glyphs[12304] = {w=18, advance=16, rects={{9,4,5,1},{9,5,4,1},{9,6,3,2},{9,8,2,6},{9,14,3,3},{9,17,4,1},{9,18,5,1}}}
T.glyphs[12305] = {w=18, advance=16, rects={{2,4,5,1},{3,5,4,1},{4,6,3,2},{5,8,2,7},{4,15,3,2},{3,17,4,1},{2,18,5,1}}}
T.glyphs[12385] = {w=18, advance=16, rects={{6,5,1,2},{5,7,2,1},{11,7,2,1},{2,8,11,1},{4,9,2,3},{4,12,1,1},{6,12,6,1},{3,13,5,1},{10,13,3,1},{3,14,2,1},{12,14,1,2},{10,16,3,1},{6,17,6,1}}}
T.glyphs[19968] = {w=18, advance=16, rects={{0,11,16,1},{1,12,14,1}}}
T.glyphs[19971] = {w=18, advance=16, rects={{6,4,1,5},{9,8,7,1},{1,9,12,1},{0,10,7,1},{6,11,1,5},{14,14,1,2},{6,16,2,1},{13,16,2,1},{6,17,9,1}}}
T.glyphs[19975] = {w=18, advance=16, rects={{0,5,16,1},{5,6,2,3},{5,9,9,1},{5,10,2,1},{12,10,2,4},{5,11,1,1},{4,12,2,2},{4,14,1,1},{12,14,1,2},{3,15,2,1},{2,16,2,1},{11,16,2,1},{1,17,2,1},{7,17,6,1},{1,18,1,1}}}
T.glyphs[19977] = {w=18, advance=16, rects={{1,5,14,1},{2,11,12,1},{0,17,16,1}}}
T.glyphs[19978] = {w=18, advance=16, rects={{6,5,2,4},{6,9,9,1},{6,10,2,7},{0,17,16,1}}}
T.glyphs[19979] = {w=18, advance=16, rects={{0,5,16,1},{6,6,2,3},{6,9,4,1},{6,10,2,9},{9,10,2,1},{10,11,3,1},{12,12,2,1},{13,13,1,1}}}
T.glyphs[19981] = {w=18, advance=16, rects={{0,5,16,1},{7,6,3,1},{7,7,1,1},{6,8,3,1},{5,9,4,1},{5,10,1,1},{7,10,2,9},{10,10,1,1},{3,11,2,1},{10,11,3,1},{2,12,2,1},{12,12,3,1},{1,13,2,1},{14,13,2,1},{0,14,2,1}}}
T.glyphs[19982] = {w=18, advance=16, rects={{3,5,2,1},{3,6,13,1},{3,7,2,1},{3,8,1,2},{3,10,12,1},{13,11,2,1},{13,12,1,4},{0,13,12,1},{12,16,2,1},{7,17,6,1}}}
T.glyphs[19988] = {w=18, advance=16, rects={{2,5,12,1},{2,6,2,3},{12,6,2,3},{2,9,12,1},{2,10,2,3},{12,10,2,3},{2,13,12,1},{2,14,2,3},{12,14,2,3},{0,17,16,1}}}
T.glyphs[19990] = {w=18, advance=16, rects={{7,4,1,4},{12,4,1,4},{2,5,2,3},{0,8,16,1},{2,9,2,8},{6,9,2,1},{12,9,2,1},{7,10,1,3},{12,10,1,3},{7,13,6,1},{7,14,1,1},{12,14,1,1},{2,17,13,1}}}
T.glyphs[19996] = {w=18, advance=16, rects={{5,4,1,1},{4,5,2,1},{0,6,16,1},{3,7,2,2},{8,8,1,3},{2,9,2,2},{2,11,13,1},{8,12,1,6},{11,12,1,1},{4,13,1,1},{11,13,2,1},{3,14,2,1},{12,14,1,1},{2,15,2,1},{12,15,2,1},{1,16,2,1},{13,16,2,1},{1,17,1,1},{14,17,2,2},{0,18,2,1},{5,18,4,1}}}
T.glyphs[19997] = {w=18, advance=16, rects={{4,5,1,1},{11,5,1,1},{3,6,2,1},{10,6,2,1},{3,7,1,1},{10,7,1,1},{2,8,2,1},{6,8,1,1},{9,8,2,1},{13,8,1,1},{1,9,2,1},{5,9,2,1},{9,9,1,1},{12,9,2,1},{1,10,5,1},{8,10,5,1},{4,11,2,1},{7,11,3,1},{11,11,2,1},{3,12,2,1},{10,12,2,1},{3,13,1,1},{9,13,2,1},{1,14,6,1},{8,14,7,1},{1,15,4,1},{8,15,4,1},{0,17,16,1}}}
T.glyphs[20002] = {w=18, advance=16, rects={{8,4,6,1},{1,5,12,1},{7,6,2,2},{1,8,14,1},{7,9,2,3},{0,12,16,1},{5,13,2,2},{10,14,1,1},{4,15,2,1},{10,15,2,1},{3,16,2,1},{11,16,2,1},{2,17,12,1},{2,18,1,1},{13,18,1,2}}}
T.glyphs[20004] = {w=18, advance=16, rects={{0,5,16,1},{5,6,2,2},{9,6,2,1},{10,7,1,1},{1,8,14,1},{1,9,2,5},{5,9,2,1},{9,9,2,3},{13,9,2,4},{5,10,1,2},{4,12,4,1},{9,12,3,1},{4,13,1,1},{7,13,3,1},{11,13,4,1},{1,14,4,1},{7,14,2,1},{12,14,3,1},{1,15,3,1},{7,15,1,1},{13,15,2,2},{1,16,2,2},{10,17,4,1}}}
T.glyphs[20005] = {w=18, advance=16, rects={{0,5,16,1},{5,6,2,1},{9,6,2,4},{2,7,2,1},{6,7,1,3},{13,7,1,1},{3,8,1,1},{12,8,2,1},{2,10,14,1},{2,11,1,3},{1,14,2,2},{1,16,1,1},{0,17,2,2}}}
T.glyphs[20010] = {w=18, advance=16, rects={{7,4,2,1},{6,5,4,1},{6,6,1,1},{9,6,1,1},{5,7,2,1},{9,7,2,1},{4,8,2,1},{10,8,2,1},{2,9,3,1},{7,9,2,10},{11,9,3,1},{1,10,2,1},{12,10,3,1},{0,11,2,1},{14,11,1,1}}}
T.glyphs[20013] = {w=18, advance=16, rects={{7,5,2,2},{1,7,14,1},{1,8,2,4},{7,8,2,4},{13,8,2,4},{1,12,14,1},{1,13,2,1},{7,13,2,6},{13,13,2,1}}}
T.glyphs[20018] = {w=18, advance=16, rects={{7,4,2,2},{2,6,12,1},{2,7,1,2},{7,7,2,2},{13,7,1,2},{2,9,12,1},{2,10,1,1},{7,10,2,2},{13,10,1,1},{1,12,14,1},{1,13,2,2},{7,13,2,2},{13,13,2,2},{1,15,14,1},{1,16,2,1},{7,16,2,3},{13,16,2,1}}}
T.glyphs[20020] = {w=18, advance=16, rects={{4,4,1,15},{8,4,2,1},{8,5,1,1},{1,6,1,12},{7,6,9,1},{6,7,2,2},{6,9,1,1},{10,9,2,1},{11,10,1,1},{7,11,8,1},{7,12,1,5},{10,12,2,5},{14,12,1,5},{7,17,8,1},{7,18,1,1},{14,18,1,1}}}
T.glyphs[20026] = {w=18, advance=16, rects={{2,4,2,1},{7,4,1,4},{3,5,2,1},{4,6,1,1},{1,8,14,1},{6,9,2,2},{13,9,2,7},{6,11,1,1},{9,11,1,1},{5,12,2,2},{9,12,2,1},{10,13,2,1},{4,14,2,1},{3,15,2,2},{12,16,2,1},{1,17,3,1},{8,17,6,1},{1,18,1,1}}}
T.glyphs[20027] = {w=18, advance=16, rects={{7,4,1,1},{7,5,2,1},{8,6,1,1},{1,7,14,1},{7,8,2,4},{1,12,14,1},{7,13,2,4},{0,17,16,1}}}
T.glyphs[20030] = {w=18, advance=16, rects={{2,4,1,1},{7,4,1,1},{12,4,2,1},{2,5,2,1},{7,5,2,1},{11,5,2,2},{3,6,2,2},{8,6,1,1},{0,8,16,1},{4,9,2,1},{10,9,2,1},{4,10,1,1},{7,10,2,2},{11,10,1,1},{3,11,1,1},{11,11,2,1},{1,12,2,1},{4,12,11,1},{0,13,2,1},{7,13,2,2},{14,13,2,1},{1,15,14,1},{7,16,2,3}}}
T.glyphs[20037] = {w=18, advance=16, rects={{5,4,1,1},{4,5,2,1},{4,6,7,1},{3,7,2,1},{9,7,2,3},{2,8,2,2},{1,10,2,1},{8,10,2,2},{7,12,3,1},{6,13,2,1},{9,13,2,1},{5,14,2,1},{10,14,1,1},{4,15,2,1},{10,15,2,1},{3,16,2,1},{11,16,2,1},{1,17,3,1},{12,17,3,1},{1,18,1,1},{14,18,1,1}}}
T.glyphs[20040] = {w=18, advance=16, rects={{7,4,1,1},{6,5,2,2},{5,7,2,1},{10,7,2,2},{4,8,2,1},{3,9,2,1},{9,9,2,1},{2,10,2,1},{8,10,2,1},{1,11,2,1},{7,11,2,2},{0,12,2,1},{11,12,1,1},{6,13,2,1},{11,13,2,1},{5,14,2,1},{12,14,1,1},{4,15,2,1},{12,15,2,2},{3,16,2,1},{2,17,13,1},{2,18,2,1},{14,18,1,2}}}
T.glyphs[20041] = {w=18, advance=16, rects={{6,4,2,1},{3,5,1,3},{7,5,1,1},{12,5,1,3},{7,6,2,1},{8,7,1,1},{3,8,2,1},{11,8,2,1},{4,9,1,1},{11,9,1,1},{4,10,2,1},{10,10,2,2},{5,11,1,1},{5,12,2,1},{9,12,2,1},{6,13,4,1},{7,14,2,1},{6,15,4,1},{4,16,3,1},{9,16,3,1},{1,17,4,1},{11,17,4,1},{1,18,2,1},{13,18,2,1}}}
T.glyphs[20043] = {w=18, advance=16, rects={{7,4,1,1},{7,5,2,1},{8,6,1,1},{1,7,13,1},{12,8,2,1},{11,9,2,1},{9,10,3,1},{8,11,2,1},{7,12,2,1},{5,13,3,1},{3,14,3,1},{1,15,4,1},{0,16,2,1},{4,16,3,1},{0,17,1,1},{5,17,11,1}}}
T.glyphs[20046] = {w=18, advance=16, rects={{8,4,7,1},{1,5,12,1},{7,6,2,6},{2,7,2,1},{12,7,2,2},{3,8,1,1},{3,9,2,1},{11,9,2,1},{4,10,1,1},{11,10,1,1},{0,12,16,1},{7,13,2,5},{4,18,4,1}}}
T.glyphs[20048] = {w=18, advance=16, rects={{8,4,6,1},{2,5,11,1},{2,6,2,2},{7,7,2,4},{2,8,1,3},{1,11,14,1},{7,12,2,6},{4,13,1,1},{11,13,1,1},{3,14,2,1},{11,14,2,1},{2,15,2,1},{12,15,2,1},{1,16,2,2},{13,16,2,1},{14,17,1,2},{1,18,1,1},{4,18,5,1}}}
T.glyphs[20056] = {w=18, advance=16, rects={{9,4,6,1},{1,5,11,1},{7,6,2,1},{0,7,16,1},{7,8,2,4},{4,9,1,1},{11,9,1,1},{13,9,2,1},{1,10,4,1},{11,10,4,1},{4,11,1,1},{11,11,1,2},{14,11,2,2},{1,12,4,1},{6,12,4,1},{0,13,3,1},{4,13,6,1},{11,13,4,1},{4,14,2,1},{7,14,2,5},{10,14,1,1},{3,15,2,1},{11,15,2,1},{1,16,3,1},{12,16,3,1},{0,17,2,1},{14,17,1,1}}}
T.glyphs[20063] = {w=18, advance=16, rects={{7,4,2,3},{2,6,2,2},{7,7,7,1},{1,8,13,1},{0,9,5,1},{7,9,2,4},{13,9,1,3},{2,10,2,7},{12,12,2,1},{7,13,6,1},{7,14,2,1},{14,14,2,2},{14,16,1,1},{3,17,12,1}}}
T.glyphs[20064] = {w=18, advance=16, rects={{1,5,13,1},{13,6,1,9},{3,8,2,1},{4,9,4,1},{7,10,2,1},{10,11,2,1},{7,12,4,1},{4,13,5,1},{1,14,5,1},{1,15,2,1},{12,15,2,2},{7,17,6,1},{8,18,3,1}}}
T.glyphs[20081] = {w=18, advance=16, rects={{4,4,4,1},{10,4,1,14},{1,5,6,1},{4,6,1,2},{0,8,9,1},{4,9,1,3},{1,12,7,1},{1,13,1,4},{7,13,1,4},{14,14,2,4},{1,17,7,1},{1,18,1,1},{7,18,1,1},{10,18,5,1}}}
T.glyphs[20102] = {w=18, advance=16, rects={{1,5,14,1},{11,6,4,1},{10,7,3,1},{8,8,3,1},{7,9,2,8},{3,17,6,1}}}
T.glyphs[20107] = {w=18, advance=16, rects={{7,4,2,1},{0,5,16,1},{7,6,2,1},{2,7,12,1},{2,8,2,1},{7,8,2,1},{12,8,2,1},{2,9,12,1},{7,10,2,1},{1,11,13,1},{7,12,2,1},{13,12,1,1},{0,13,16,1},{7,14,2,1},{13,14,1,1},{1,15,13,1},{7,16,2,1},{13,16,1,1},{4,17,4,1}}}
T.glyphs[20108] = {w=18, advance=16, rects={{1,6,14,1},{0,16,16,1}}}
T.glyphs[20110] = {w=18, advance=16, rects={{1,5,14,1},{7,6,2,4},{0,10,16,1},{7,11,2,6},{4,17,5,1}}}
T.glyphs[20114] = {w=18, advance=16, rects={{1,5,14,1},{3,6,2,2},{3,8,10,1},{3,9,2,1},{11,9,2,4},{3,10,1,3},{2,13,11,1},{11,14,2,3},{0,17,16,1}}}
T.glyphs[20116] = {w=18, advance=16, rects={{1,5,14,1},{5,6,2,4},{1,10,12,1},{5,11,1,2},{12,11,1,6},{4,13,2,3},{4,16,1,1},{0,17,16,1}}}
T.glyphs[20122] = {w=18, advance=16, rects={{1,5,14,1},{5,6,2,11},{9,6,2,8},{1,8,2,2},{14,8,1,1},{13,9,2,1},{2,10,1,1},{13,10,1,1},{2,11,2,2},{12,11,2,2},{3,13,1,2},{12,13,1,1},{9,14,4,1},{9,15,2,2},{0,17,16,1}}}
T.glyphs[20123] = {w=18, advance=16, rects={{5,4,1,3},{9,4,2,2},{13,5,2,1},{2,6,1,5},{9,6,5,1},{5,7,7,1},{5,8,1,2},{9,8,2,2},{14,8,2,2},{5,10,6,1},{14,10,1,1},{1,11,6,1},{10,11,5,1},{0,12,3,1},{2,14,12,1},{1,17,14,1}}}
T.glyphs[20129] = {w=18, advance=16, rects={{7,4,1,1},{7,5,2,1},{8,6,1,1},{0,7,16,1},{2,8,2,9},{2,17,13,1}}}
T.glyphs[20132] = {w=18, advance=16, rects={{7,4,1,1},{7,5,2,1},{0,6,16,1},{5,8,1,1},{10,8,1,1},{4,9,2,1},{10,9,3,1},{3,10,3,1},{10,10,4,1},{1,11,2,1},{5,11,1,1},{10,11,1,1},{13,11,2,1},{1,12,1,1},{5,12,2,1},{9,12,2,1},{14,12,1,1},{6,13,1,1},{9,13,1,1},{6,14,4,2},{4,16,3,1},{9,16,2,1},{2,17,3,1},{10,17,4,1},{1,18,2,1},{13,18,2,1}}}
T.glyphs[20135] = {w=18, advance=16, rects={{7,4,1,1},{7,5,2,1},{0,6,16,1},{4,7,2,2},{11,7,1,1},{10,8,2,1},{5,9,1,1},{9,9,2,1},{2,10,13,1},{2,11,1,4},{1,15,2,2},{1,17,1,1},{0,18,2,1}}}
T.glyphs[20142] = {w=18, advance=16, rects={{7,4,1,1},{7,5,2,1},{1,6,14,1},{3,8,10,1},{3,9,1,1},{12,9,1,1},{3,10,10,1},{1,12,14,1},{1,13,1,1},{14,13,1,1},{4,14,7,1},{4,15,2,2},{10,15,1,3},{14,15,2,3},{2,17,3,1},{1,18,2,1},{10,18,5,1}}}
T.glyphs[20154] = {w=18, advance=16, rects={{7,4,2,5},{6,9,3,1},{6,10,4,1},{6,11,1,1},{9,11,1,1},{5,12,2,2},{9,12,2,2},{4,14,2,1},{10,14,2,1},{3,15,2,1},{11,15,2,1},{2,16,2,1},{11,16,3,1},{1,17,2,1},{12,17,3,1},{1,18,1,1},{14,18,1,1}}}
T.glyphs[20160] = {w=18, advance=16, rects={{4,4,1,1},{10,4,1,5},{3,5,2,1},{3,6,1,1},{2,7,2,2},{1,9,3,2},{5,9,11,1},{9,10,2,1},{0,11,4,1},{10,11,1,8},{0,12,1,1},{2,12,2,7}}}
T.glyphs[20161] = {w=18, advance=16, rects={{3,4,2,2},{3,6,1,1},{6,6,9,1},{2,7,2,2},{1,9,3,2},{0,11,4,1},{2,12,2,7},{5,17,11,1}}}
T.glyphs[20165] = {w=18, advance=16, rects={{4,4,1,1},{3,5,12,1},{3,6,1,1},{6,6,2,3},{13,6,2,2},{2,7,2,2},{13,8,1,1},{1,9,3,2},{7,9,1,1},{12,9,2,2},{7,10,2,2},{0,11,4,1},{12,11,1,1},{0,12,1,1},{2,12,2,7},{8,12,1,1},{11,12,2,1},{8,13,4,1},{9,14,2,1},{8,15,4,1},{7,16,2,1},{11,16,2,1},{5,17,3,1},{12,17,3,1},{5,18,1,1},{14,18,1,1}}}
T.glyphs[20170] = {w=18, advance=16, rects={{7,4,2,1},{6,5,4,1},{5,6,2,1},{9,6,2,1},{4,7,2,1},{10,7,2,1},{3,8,2,1},{7,8,1,1},{11,8,2,1},{1,9,3,1},{7,9,2,1},{12,9,3,1},{0,10,2,1},{8,10,1,1},{14,10,2,1},{2,12,12,1},{11,13,2,2},{10,15,2,1},{9,16,2,1},{8,17,2,1},{8,18,1,1}}}
T.glyphs[20173] = {w=18, advance=16, rects={{3,4,2,1},{3,5,11,1},{3,6,1,1},{7,6,2,5},{12,6,2,1},{2,7,2,2},{12,7,1,1},{11,8,2,1},{1,9,3,2},{11,9,1,1},{11,10,4,1},{0,11,4,1},{7,11,1,4},{14,11,1,5},{0,12,1,1},{2,12,2,6},{6,15,2,2},{13,16,2,2},{5,17,2,1},{2,18,4,2},{10,18,4,1}}}
T.glyphs[20174] = {w=18, advance=16, rects={{3,4,2,6},{9,4,2,7},{3,10,3,1},{3,11,1,2},{5,11,2,1},{9,11,3,1},{6,12,2,1},{9,12,1,1},{11,12,1,2},{2,13,2,2},{7,13,3,1},{8,14,1,1},{11,14,2,1},{2,15,1,1},{7,15,2,1},{12,15,1,1},{1,16,2,1},{6,16,2,1},{12,16,2,1},{1,17,1,1},{5,17,2,1},{13,17,2,1},{0,18,2,1},{5,18,1,1},{14,18,1,1}}}
T.glyphs[20179] = {w=18, advance=16, rects={{7,4,2,1},{6,5,4,1},{5,6,2,1},{9,6,2,1},{4,7,2,1},{10,7,2,1},{3,8,2,1},{11,8,2,1},{1,9,3,1},{12,9,3,1},{0,10,2,1},{3,10,9,1},{14,10,1,1},{3,11,2,6},{11,11,1,3},{13,13,2,3},{7,14,5,1},{12,16,2,1},{4,17,10,1}}}
T.glyphs[20182] = {w=18, advance=16, rects={{3,4,2,2},{9,4,2,3},{3,6,1,1},{6,6,1,2},{2,7,2,2},{9,7,6,1},{5,8,10,1},{1,9,7,1},{9,9,2,3},{13,9,2,3},{0,10,4,1},{6,10,1,7},{0,11,1,1},{2,11,2,8},{9,12,5,1},{9,13,2,2},{14,14,2,3},{6,17,9,1}}}
T.glyphs[20195] = {w=18, advance=16, rects={{4,4,1,1},{3,5,2,1},{8,5,2,4},{11,5,1,1},{3,6,1,1},{12,6,2,1},{2,7,2,2},{13,7,1,1},{1,9,3,2},{7,9,9,1},{5,10,8,1},{0,11,4,1},{8,11,2,1},{0,12,1,1},{2,12,2,7},{9,12,1,1},{9,13,2,2},{10,15,1,1},{14,15,2,2},{10,16,2,1},{11,17,4,1},{12,18,3,1}}}
T.glyphs[20196] = {w=18, advance=16, rects={{7,4,2,1},{6,5,4,1},{5,6,2,1},{9,6,2,1},{4,7,2,1},{10,7,2,1},{3,8,2,1},{7,8,1,1},{11,8,2,1},{1,9,3,1},{7,9,2,1},{12,9,3,1},{0,10,2,1},{8,10,1,1},{14,10,2,1},{2,12,12,1},{11,13,2,1},{10,14,2,1},{4,15,3,1},{9,15,2,1},{5,16,5,1},{7,17,3,1},{9,18,1,1}}}
T.glyphs[20197] = {w=18, advance=16, rects={{6,4,1,1},{12,4,1,7},{1,5,2,10},{6,5,2,2},{7,7,2,2},{11,11,2,2},{6,13,1,1},{11,13,1,1},{5,14,2,1},{10,14,3,1},{1,15,5,1},{9,15,2,1},{12,15,2,1},{1,16,3,1},{8,16,2,1},{13,16,2,1},{1,17,2,1},{6,17,3,1},{14,17,2,1},{6,18,1,1},{14,18,1,1}}}
T.glyphs[20204] = {w=18, advance=16, rects={{3,4,2,2},{6,4,1,1},{6,5,2,1},{9,5,6,1},{3,6,1,1},{7,6,1,1},{13,6,2,1},{2,7,2,2},{6,7,1,12},{14,7,1,10},{1,9,3,2},{0,11,4,1},{0,12,1,1},{2,12,2,7},{13,17,2,1},{10,18,5,1}}}
T.glyphs[20214] = {w=18, advance=16, rects={{3,4,2,2},{10,4,2,3},{7,5,1,1},{3,6,1,1},{6,6,2,1},{2,7,2,1},{6,7,9,1},{1,8,3,2},{6,8,1,1},{10,8,2,4},{5,9,2,1},{0,10,4,1},{5,10,1,1},{0,11,1,1},{2,11,2,7},{5,12,11,1},{10,13,2,5}}}
T.glyphs[20215] = {w=18, advance=16, rects={{3,4,2,1},{9,4,2,1},{3,5,1,2},{8,5,3,1},{7,6,2,1},{11,6,1,1},{2,7,2,2},{6,7,2,1},{11,7,2,1},{5,8,2,1},{13,8,2,1},{1,9,5,1},{14,9,2,1},{1,10,3,1},{7,10,1,5},{11,10,2,9},{0,11,4,1},{0,12,1,1},{2,12,2,7},{6,15,2,2},{5,17,2,1},{5,18,1,1}}}
T.glyphs[20219] = {w=18, advance=16, rects={{4,4,1,1},{3,5,2,2},{10,5,5,1},{6,6,8,1},{2,7,2,2},{10,7,1,4},{1,9,3,2},{0,11,4,1},{5,11,11,1},{0,12,1,1},{2,12,2,7},{10,12,1,5},{5,17,11,1}}}
T.glyphs[20221] = {w=18, advance=16, rects={{4,4,1,1},{10,4,1,1},{3,5,2,1},{8,5,1,1},{10,5,2,1},{3,6,1,1},{7,6,2,1},{11,6,1,1},{2,7,2,2},{7,7,1,1},{11,7,2,1},{6,8,2,1},{12,8,2,1},{1,9,3,1},{5,9,2,1},{13,9,2,1},{1,10,5,1},{14,10,2,1},{0,11,14,1},{0,12,1,1},{2,12,2,6},{7,12,2,3},{12,12,2,1},{12,13,1,5},{7,15,1,1},{6,16,2,1},{5,17,2,1},{2,18,4,1},{8,18,5,1}}}
T.glyphs[20241] = {w=18, advance=16, rects={{4,4,1,1},{9,4,2,3},{3,5,2,1},{3,6,1,1},{2,7,2,2},{5,7,10,1},{8,8,3,1},{1,9,3,1},{8,9,4,2},{0,10,4,1},{0,11,1,1},{2,11,2,4},{7,11,1,2},{9,11,4,1},{9,12,2,7},{12,12,1,1},{6,13,1,1},{12,13,2,1},{5,14,2,1},{13,14,2,1},{2,15,4,1},{14,15,1,1},{2,16,3,1},{14,16,2,1},{2,17,2,2}}}
T.glyphs[20248] = {w=18, advance=16, rects={{4,4,1,1},{8,4,1,4},{11,4,1,1},{3,5,2,1},{12,5,2,1},{3,6,1,1},{13,6,1,1},{2,7,2,1},{2,8,14,1},{1,9,3,1},{8,9,1,2},{10,9,1,7},{0,10,4,1},{0,11,1,1},{2,11,2,6},{7,11,2,2},{7,13,1,2},{14,14,2,3},{6,15,2,1},{5,16,2,1},{10,16,2,1},{2,17,4,1},{10,17,5,1},{2,18,3,1}}}
T.glyphs[20250] = {w=18, advance=16, rects={{7,5,2,1},{6,6,4,1},{5,7,2,1},{9,7,2,1},{4,8,2,1},{10,8,2,1},{3,9,2,1},{11,9,2,1},{1,10,14,1},{0,11,2,1},{14,11,2,1},{1,13,14,1},{6,14,1,1},{5,15,1,1},{10,15,1,1},{7,16,5,1},{4,17,9,1},{3,18,1,1},{12,18,2,1},{2,19,1,1},{13,19,1,1}}}
T.glyphs[20256] = {w=18, advance=16, rects={{3,4,2,2},{9,4,1,1},{8,5,2,1},{3,6,1,1},{5,6,10,1},{2,7,2,2},{8,7,1,1},{7,8,2,1},{1,9,3,2},{5,9,11,1},{7,10,2,1},{0,11,4,1},{7,11,1,1},{0,12,1,1},{2,12,2,7},{6,12,9,1},{13,13,2,1},{6,14,2,1},{12,14,2,1},{7,15,2,1},{11,15,2,1},{9,16,3,1},{10,17,2,1},{11,18,2,1}}}
T.glyphs[20260] = {w=18, advance=16, rects={{3,4,2,2},{7,4,2,2},{3,6,1,1},{6,6,10,1},{2,7,2,2},{6,7,1,1},{5,8,2,1},{9,8,1,1},{1,9,3,2},{5,9,1,1},{8,9,2,1},{5,10,10,1},{0,11,4,1},{8,11,2,2},{13,11,2,1},{0,12,1,1},{2,12,2,6},{14,12,1,1},{8,13,1,1},{13,13,2,4},{7,14,2,1},{6,15,2,1},{5,16,2,1},{5,17,1,1},{9,17,5,1}}}
T.glyphs[20266] = {w=18, advance=16, rects={{3,4,2,1},{8,4,2,2},{3,5,4,1},{3,6,1,1},{6,6,4,1},{2,7,2,2},{8,7,2,1},{5,8,10,1},{1,9,3,2},{8,9,2,2},{13,9,2,1},{14,10,1,4},{0,11,4,1},{8,11,1,1},{0,12,1,1},{2,12,2,5},{7,12,2,2},{10,12,2,1},{11,13,1,1},{7,14,1,1},{13,14,2,3},{6,15,2,1},{5,16,2,1},{2,17,4,1},{10,17,4,1}}}
T.glyphs[20272] = {w=18, advance=16, rects={{3,4,2,2},{9,4,2,3},{3,6,1,1},{2,7,14,1},{2,8,2,1},{9,8,2,3},{1,9,3,2},{0,11,4,1},{5,11,10,1},{0,12,1,1},{2,12,2,7},{5,12,2,5},{13,12,2,5},{5,17,10,1},{5,18,2,1},{13,18,2,1}}}
T.glyphs[20280] = {w=18, advance=16, rects={{3,4,2,1},{9,4,2,2},{3,5,1,1},{2,6,2,2},{5,6,10,1},{5,7,2,2},{9,7,2,2},{14,7,1,2},{2,8,1,1},{1,9,2,1},{5,9,10,1},{0,10,3,1},{5,10,2,3},{9,10,2,3},{14,10,1,3},{0,11,1,1},{2,11,1,8},{5,13,10,1},{5,14,2,1},{9,14,2,5},{14,14,1,1}}}
T.glyphs[20284] = {w=18, advance=16, rects={{3,4,1,2},{8,4,1,1},{13,4,1,6},{8,5,2,1},{2,6,2,1},{5,6,2,8},{9,6,1,1},{2,7,1,2},{9,7,2,1},{10,8,1,1},{1,9,2,2},{12,10,2,3},{0,11,3,1},{0,12,1,1},{2,12,1,7},{9,13,2,1},{12,13,1,1},{5,14,5,1},{11,14,2,1},{5,15,4,1},{11,15,3,1},{5,16,2,1},{10,16,2,1},{13,16,2,1},{9,17,2,1},{14,17,1,2},{8,18,2,1}}}
T.glyphs[20294] = {w=18, advance=16, rects={{4,4,1,1},{3,5,2,1},{6,5,9,1},{3,6,1,1},{6,6,1,3},{13,6,2,3},{2,7,2,2},{1,9,3,2},{6,9,9,1},{6,10,1,3},{13,10,2,3},{0,11,4,1},{0,12,1,1},{2,12,2,5},{6,13,9,1},{6,14,1,1},{13,14,2,1},{2,17,14,1},{2,18,2,1}}}
T.glyphs[20301] = {w=18, advance=16, rects={{3,4,2,2},{9,4,1,1},{9,5,2,1},{3,6,1,1},{10,6,1,1},{2,7,2,2},{5,7,11,1},{1,9,3,2},{6,9,1,1},{13,9,1,2},{6,10,2,2},{0,11,4,1},{12,11,2,2},{0,12,1,1},{2,12,2,5},{7,12,1,1},{7,13,2,2},{12,13,1,1},{11,14,2,2},{8,15,1,1},{11,16,1,1},{2,17,14,1},{2,18,2,1}}}
T.glyphs[20302] = {w=18, advance=16, rects={{4,4,1,1},{11,4,4,1},{3,5,2,1},{6,5,8,1},{3,6,1,1},{6,6,1,4},{10,6,1,4},{2,7,2,1},{2,8,1,1},{1,9,2,1},{0,10,3,1},{6,10,10,1},{0,11,1,1},{2,11,1,7},{6,11,1,4},{10,11,2,2},{11,13,1,2},{9,14,1,1},{6,15,4,1},{11,15,2,1},{15,15,1,1},{5,16,3,1},{9,16,1,1},{12,16,4,1},{5,17,2,1},{10,17,1,1},{13,17,2,1}}}
T.glyphs[20303] = {w=18, advance=16, rects={{4,4,1,1},{9,4,2,1},{3,5,2,1},{10,5,1,1},{3,6,1,1},{5,6,10,1},{2,7,2,2},{9,7,2,1},{10,8,1,3},{1,9,3,1},{0,10,2,1},{3,10,1,9},{0,11,1,1},{6,11,9,1},{9,12,2,1},{10,13,1,4},{5,17,11,1}}}
T.glyphs[20307] = {w=18, advance=16, rects={{3,4,2,1},{9,4,1,3},{3,5,1,1},{2,6,2,1},{2,7,13,1},{1,8,2,2},{8,8,4,1},{7,9,5,1},{0,10,3,1},{7,10,1,1},{9,10,1,4},{11,10,1,1},{0,11,1,1},{2,11,1,4},{6,11,2,1},{11,11,2,1},{6,12,1,1},{12,12,2,1},{5,13,2,1},{13,13,1,1},{4,14,2,1},{7,14,8,1},{2,15,3,1},{9,15,2,1},{14,15,2,1},{2,16,1,3},{9,16,1,3}}}
T.glyphs[20309] = {w=18, advance=16, rects={{3,4,2,1},{3,5,1,1},{5,5,11,1},{2,6,2,2},{13,6,2,10},{1,8,3,2},{6,8,5,1},{6,9,1,4},{10,9,1,4},{0,10,4,1},{0,11,1,1},{2,11,2,7},{6,13,5,1},{6,14,1,1},{13,16,1,1},{10,17,4,1}}}
T.glyphs[20313] = {w=18, advance=16, rects={{7,4,2,1},{6,5,4,1},{5,6,2,1},{9,6,2,1},{4,7,2,1},{10,7,2,1},{3,8,2,1},{11,8,2,1},{1,9,14,1},{0,10,2,1},{7,10,2,2},{14,10,2,1},{1,12,14,1},{3,13,2,1},{7,13,2,5},{10,13,2,1},{2,14,3,1},{11,14,2,1},{1,15,3,1},{12,15,3,1},{1,16,1,1},{14,16,1,1},{4,18,4,1}}}
T.glyphs[20316] = {w=18, advance=16, rects={{3,4,2,2},{7,4,2,1},{7,5,1,1},{3,6,1,1},{7,6,9,1},{2,7,2,2},{6,7,2,1},{9,7,1,3},{5,8,2,1},{1,9,3,2},{5,9,1,2},{9,10,6,1},{0,11,4,1},{9,11,1,3},{0,12,1,1},{2,12,2,7},{9,14,6,1},{9,15,1,4}}}
T.glyphs[20320] = {w=18, advance=16, rects={{4,4,1,1},{8,4,1,1},{3,5,2,2},{7,5,2,1},{7,6,9,1},{3,7,1,1},{6,7,2,1},{14,7,2,1},{2,8,2,1},{5,8,2,1},{10,8,1,9},{14,8,1,1},{1,9,3,2},{5,9,1,1},{13,9,2,1},{0,11,4,1},{7,11,1,1},{0,12,1,1},{2,12,2,7},{6,12,2,2},{13,12,1,1},{13,13,2,1},{6,14,1,1},{14,14,1,1},{5,15,2,1},{14,15,2,1},{5,16,1,1},{9,17,2,1},{7,18,4,1}}}
T.glyphs[20351] = {w=18, advance=16, rects={{3,5,2,1},{9,5,2,1},{3,6,13,1},{2,7,2,1},{9,7,2,1},{2,8,1,1},{5,8,10,1},{1,9,2,1},{5,9,2,2},{9,9,2,2},{14,9,1,2},{0,10,3,1},{0,11,1,1},{2,11,1,7},{5,11,10,1},{9,12,2,1},{14,12,1,1},{6,13,1,1},{9,13,1,1},{6,14,4,1},{7,15,3,1},{6,16,7,1},{4,17,3,1},{11,17,5,1}}}
T.glyphs[20363] = {w=18, advance=16, rects={{3,4,1,2},{14,4,1,14},{5,5,6,1},{2,6,2,1},{6,6,2,1},{2,7,1,2},{6,7,1,1},{11,7,1,9},{6,8,4,1},{1,9,2,2},{5,9,2,1},{9,9,1,2},{5,10,1,2},{0,11,3,1},{8,11,2,1},{0,12,1,1},{2,12,1,7},{4,12,2,1},{8,12,1,1},{4,13,1,1},{7,13,2,2},{7,15,1,1},{6,16,1,1},{5,17,2,1},{4,18,2,1},{11,18,4,1}}}
T.glyphs[20379] = {w=18, advance=16, rects={{4,4,1,1},{7,4,1,3},{12,4,1,3},{3,5,2,1},{3,6,1,1},{2,7,2,1},{5,7,10,1},{1,8,3,2},{7,8,2,1},{11,8,2,1},{7,9,1,3},{12,9,1,3},{0,10,4,1},{0,11,1,1},{2,11,2,1},{2,12,14,1},{2,13,2,5},{7,15,2,1},{11,15,2,1},{5,16,3,1},{12,16,3,1},{5,17,1,1},{14,17,1,1}}}
T.glyphs[20381] = {w=18, advance=16, rects={{3,4,1,3},{9,4,1,2},{9,6,2,1},{2,7,14,1},{2,8,1,1},{8,8,2,2},{1,9,2,2},{7,10,4,1},{13,10,2,1},{0,11,3,1},{6,11,2,1},{10,11,1,1},{12,11,2,1},{0,12,1,1},{2,12,1,2},{5,12,3,1},{10,12,3,1},{4,13,4,1},{10,13,2,1},{2,14,3,1},{6,14,2,2},{11,14,2,1},{2,15,1,4},{9,15,2,1},{12,15,2,1},{6,16,4,1},{13,16,2,1},{6,17,3,1},{14,17,1,1},{6,18,2,1}}}
T.glyphs[20391] = {w=18, advance=16, rects={{3,4,1,1},{14,4,1,14},{2,5,8,1},{2,6,4,1},{9,6,1,9},{11,6,2,10},{2,7,1,1},{4,7,2,7},{7,7,1,7},{1,8,2,3},{0,11,3,1},{0,12,1,1},{2,12,1,7},{4,14,4,1},{6,15,3,1},{5,16,2,1},{8,16,2,1},{4,17,2,1},{9,17,2,1},{4,18,1,1},{11,18,4,1}}}
T.glyphs[20415] = {w=18, advance=16, rects={{3,4,2,1},{3,5,13,1},{3,6,1,1},{9,6,2,1},{2,7,2,2},{5,7,10,1},{5,8,2,1},{9,8,2,1},{14,8,1,1},{1,9,3,2},{5,9,10,1},{5,10,2,2},{9,10,2,2},{14,10,1,2},{0,11,4,1},{0,12,1,1},{2,12,2,6},{5,12,10,1},{9,13,2,1},{14,13,1,1},{6,14,1,1},{9,14,1,1},{6,15,4,1},{7,16,5,1},{6,17,2,1},{10,17,6,1},{2,18,5,1}}}
T.glyphs[20445] = {w=18, advance=16, rects={{3,4,1,2},{6,5,9,1},{2,6,2,1},{6,6,1,3},{13,6,2,3},{2,7,1,1},{1,8,2,2},{6,9,9,1},{0,10,3,1},{6,10,1,1},{9,10,2,2},{13,10,2,1},{0,11,1,1},{2,11,1,7},{4,12,12,1},{8,13,4,1},{7,14,1,1},{9,14,4,1},{5,15,2,1},{9,15,2,3},{13,15,2,1},{4,16,2,1},{14,16,2,1}}}
T.glyphs[20449] = {w=18, advance=16, rects={{3,4,2,2},{9,4,1,1},{9,5,2,1},{3,6,13,1},{2,7,2,2},{5,8,10,1},{1,9,3,2},{5,10,10,1},{0,11,4,1},{0,12,1,1},{2,12,2,6},{6,13,9,1},{6,14,1,3},{13,14,2,3},{6,17,9,1}}}
T.glyphs[20462] = {w=18, advance=16, rects={{3,4,1,1},{8,4,2,1},{2,5,2,1},{8,5,7,1},{2,6,4,1},{7,6,2,1},{12,6,2,1},{2,7,1,1},{4,7,4,1},{9,7,1,1},{11,7,2,1},{1,8,2,2},{4,8,2,2},{9,8,3,1},{8,9,7,1},{0,10,3,1},{4,10,4,1},{13,10,3,1},{0,11,1,1},{2,11,1,8},{4,11,2,4},{9,11,3,1},{7,12,3,1},{12,12,1,1},{10,13,3,1},{8,14,3,1},{14,14,1,1},{7,15,2,1},{12,15,2,1},{10,16,3,1},{8,17,3,1},{6,18,2,1}}}
T.glyphs[20493] = {w=18, advance=16, rects={{3,4,2,1},{9,4,1,1},{3,5,1,2},{9,5,2,1},{5,6,10,1},{2,7,2,1},{6,7,2,1},{12,7,2,1},{2,8,1,1},{7,8,1,1},{12,8,1,1},{1,9,2,2},{7,9,2,1},{11,9,2,1},{4,10,12,1},{0,11,3,1},{0,12,1,1},{2,12,1,7},{6,13,9,1},{6,14,1,3},{13,14,2,3},{6,17,9,1},{6,18,1,1},{13,18,2,1}}}
T.glyphs[20498] = {w=18, advance=16, rects={{3,4,1,1},{14,4,1,14},{2,5,9,1},{2,6,2,1},{6,6,2,1},{11,6,2,3},{2,7,1,1},{5,7,2,1},{8,7,2,1},{1,8,2,3},{4,8,2,1},{9,8,1,1},{4,9,9,1},{7,10,1,3},{10,10,3,1},{0,11,3,1},{11,11,2,4},{0,12,1,1},{2,12,1,7},{4,13,6,1},{7,14,1,2},{5,16,6,1},{4,17,5,1},{11,18,4,1}}}
T.glyphs[20505] = {w=18, advance=16, rects={{3,4,1,1},{2,5,2,1},{7,5,7,1},{2,6,1,2},{4,6,2,2},{12,6,2,2},{1,8,2,2},{4,8,12,1},{4,9,2,2},{8,9,1,1},{0,10,3,1},{7,10,8,1},{0,11,1,1},{2,11,1,7},{4,11,4,1},{10,11,2,2},{4,12,2,1},{4,13,12,1},{4,14,2,1},{10,14,2,1},{9,15,1,1},{11,15,2,1},{7,16,2,1},{12,16,3,1},{5,17,3,1},{14,17,2,1}}}
T.glyphs[20540] = {w=18, advance=16, rects={{3,4,1,3},{9,4,2,2},{5,6,11,1},{2,7,2,1},{9,7,2,2},{2,8,1,1},{1,9,2,2},{5,9,9,1},{5,10,2,1},{13,10,1,1},{0,11,3,1},{5,11,9,1},{0,12,1,1},{2,12,1,7},{5,12,2,1},{13,12,1,1},{5,13,9,1},{5,14,2,1},{13,14,1,1},{5,15,9,1},{5,16,2,1},{13,16,1,1},{4,17,12,1}}}
T.glyphs[20551] = {w=18, advance=16, rects={{3,4,1,1},{2,5,2,1},{5,5,10,1},{2,6,1,2},{5,6,1,2},{8,6,2,2},{14,6,1,2},{1,8,2,2},{5,8,10,1},{5,9,1,2},{8,9,2,1},{14,9,1,1},{0,10,3,1},{0,11,1,1},{2,11,1,7},{5,11,10,1},{5,12,1,2},{10,12,1,1},{13,12,2,1},{10,13,2,1},{13,13,1,1},{5,14,4,1},{11,14,3,1},{5,15,1,3},{11,15,2,1},{10,16,5,1},{8,17,2,1},{14,17,2,1}}}
T.glyphs[20559] = {w=18, advance=16, rects={{3,4,2,1},{9,4,2,2},{3,5,1,2},{5,6,10,1},{2,7,2,1},{5,7,1,1},{14,7,1,1},{2,8,1,1},{5,8,10,1},{1,9,2,2},{5,9,1,2},{14,9,1,1},{0,11,3,1},{5,11,10,1},{0,12,1,1},{2,12,1,5},{5,12,1,3},{7,12,1,2},{9,12,1,2},{11,12,2,2},{14,12,1,2},{7,14,8,1},{4,15,2,2},{7,15,1,4},{9,15,1,3},{11,15,2,3},{14,15,1,3},{2,17,3,2},{12,18,3,1}}}
T.glyphs[20570] = {w=18, advance=16, rects={{3,4,1,2},{6,4,2,3},{11,4,2,1},{11,5,1,2},{2,6,2,1},{2,7,8,1},{11,7,5,1},{2,8,1,1},{6,8,2,3},{10,8,2,2},{14,8,1,1},{1,9,2,2},{13,9,2,3},{9,10,3,1},{0,11,3,1},{4,11,6,1},{11,11,1,2},{0,12,1,1},{2,12,1,7},{4,12,2,4},{8,12,2,4},{13,12,1,1},{11,13,3,1},{12,14,2,2},{4,16,6,1},{11,16,1,1},{13,16,1,1},{4,17,2,1},{10,17,1,1},{14,17,1,1},{9,18,1,1},{15,18,1,1}}}
T.glyphs[20572] = {w=18, advance=16, rects={{3,4,1,2},{9,4,1,2},{3,6,13,1},{2,7,2,1},{2,8,1,1},{6,8,8,1},{1,9,2,2},{6,9,1,1},{12,9,2,1},{6,10,8,1},{0,11,3,1},{0,12,1,1},{2,12,1,7},{4,12,12,1},{4,13,1,1},{14,13,2,1},{6,14,8,1},{10,15,1,2},{9,17,2,1},{7,18,4,1}}}
T.glyphs[20599] = {w=18, advance=16, rects={{3,4,2,1},{9,4,2,1},{3,5,1,2},{8,5,3,1},{7,6,2,1},{11,6,1,1},{2,7,2,1},{6,7,2,1},{11,7,2,1},{2,8,1,1},{5,8,10,1},{1,9,2,2},{4,9,2,1},{14,9,2,1},{5,10,5,1},{11,10,1,6},{13,10,1,7},{0,11,3,1},{5,11,1,1},{8,11,2,1},{0,12,1,1},{2,12,1,6},{5,12,5,1},{5,13,1,1},{8,13,2,1},{5,14,5,1},{5,15,1,3},{8,15,2,2},{7,17,2,1},{11,17,3,1}}}
T.glyphs[20667] = {w=18, advance=16, rects={{3,4,2,1},{8,4,2,1},{3,5,12,1},{3,6,1,1},{5,6,2,2},{8,6,1,1},{11,6,1,1},{13,6,2,3},{2,7,2,1},{9,7,3,1},{2,8,1,1},{5,8,4,1},{11,8,1,1},{1,9,2,1},{5,9,10,1},{0,10,3,1},{7,10,1,1},{12,10,1,1},{0,11,1,1},{2,11,1,7},{5,11,4,1},{13,11,2,1},{4,12,2,1},{7,12,8,1},{6,13,2,1},{12,13,1,1},{5,14,1,1},{8,14,1,1},{11,14,2,1},{8,15,4,1},{7,16,6,1},{4,17,3,1},{12,17,3,1}}}
T.glyphs[20687] = {w=18, advance=16, rects={{3,4,2,1},{7,4,2,1},{3,5,1,1},{6,5,7,1},{2,6,2,1},{5,6,2,1},{10,6,2,1},{2,7,13,1},{1,8,2,2},{5,8,2,1},{9,8,2,1},{14,8,1,1},{5,9,10,1},{0,10,3,1},{5,10,5,1},{13,10,2,1},{0,11,1,1},{2,11,1,7},{6,11,2,1},{9,11,1,1},{12,11,2,1},{4,12,2,1},{8,12,5,1},{6,13,2,1},{10,13,1,1},{12,13,2,1},{4,14,3,1},{9,14,3,1},{13,14,1,1},{7,15,2,1},{10,15,2,1},{13,15,2,1},{5,16,2,1},{10,16,1,1},{14,16,1,1},{4,17,2,1},{7,17,4,1}}}
T.glyphs[20799] = {w=18, advance=16, rects={{4,4,2,8},{9,4,2,13},{4,12,1,2},{14,13,2,4},{3,14,2,2},{2,16,2,1},{1,17,2,1},{9,17,6,1},{1,18,1,1}}}
T.glyphs[20801] = {w=18, advance=16, rects={{6,4,2,1},{5,5,3,1},{5,6,2,1},{10,6,2,1},{4,7,2,1},{11,7,2,2},{3,8,2,1},{1,9,3,1},{12,9,2,1},{1,10,14,1},{5,11,1,3},{9,11,1,5},{14,11,1,1},{4,14,2,2},{14,14,2,3},{3,16,2,1},{9,16,2,1},{1,17,3,1},{9,17,6,1},{0,18,2,1}}}
T.glyphs[20803] = {w=18, advance=16, rects={{2,5,12,1},{0,10,16,1},{5,11,1,3},{9,11,2,7},{4,14,2,2},{14,15,2,3},{4,16,1,1},{3,17,2,1},{1,18,3,1},{10,18,5,1},{1,19,1,1}}}
T.glyphs[20804] = {w=18, advance=16, rects={{2,5,12,1},{2,6,2,4},{12,6,2,4},{2,10,12,1},{2,11,2,1},{5,11,2,2},{9,11,2,1},{12,11,2,1},{9,12,1,4},{5,13,1,1},{4,14,2,1},{14,14,2,3},{3,15,2,1},{2,16,2,1},{9,16,2,1},{0,17,3,1},{9,17,6,1}}}
T.glyphs[20805] = {w=18, advance=16, rects={{7,4,1,1},{7,5,2,1},{0,6,16,1},{5,7,3,1},{4,8,3,1},{10,8,2,1},{3,9,3,1},{11,9,2,2},{2,10,3,1},{2,11,12,1},{5,12,2,1},{9,12,2,5},{13,12,2,1},{5,13,1,1},{4,14,2,2},{14,14,2,3},{2,16,2,1},{0,17,3,1},{10,17,5,1}}}
T.glyphs[20808] = {w=18, advance=16, rects={{3,4,2,2},{7,4,2,3},{3,6,1,1},{2,7,13,1},{1,8,3,1},{7,8,2,3},{1,9,2,1},{0,11,16,1},{5,12,1,2},{9,12,2,5},{4,14,2,2},{14,14,2,3},{3,16,2,1},{1,17,3,1},{9,17,6,1},{0,18,2,1}}}
T.glyphs[20809] = {w=18, advance=16, rects={{7,4,2,6},{2,5,1,1},{13,5,1,1},{2,6,2,1},{12,6,2,1},{3,7,2,1},{11,7,2,1},{4,8,1,1},{11,8,1,1},{0,10,16,1},{5,11,1,3},{9,11,2,6},{4,14,2,1},{14,14,2,3},{4,15,1,1},{3,16,2,1},{1,17,3,1},{10,17,5,1},{0,18,2,1}}}
T.glyphs[20813] = {w=18, advance=16, rects={{5,4,1,1},{4,5,2,1},{4,6,8,1},{3,7,2,1},{10,7,2,1},{2,8,2,1},{9,8,2,1},{1,9,13,1},{0,10,3,1},{7,10,2,1},{12,10,2,2},{2,11,1,1},{7,11,1,1},{2,12,12,1},{2,13,1,1},{6,13,2,1},{12,13,2,1},{5,14,2,1},{8,14,1,2},{14,14,2,3},{5,15,1,1},{3,16,2,1},{8,16,2,1},{1,17,3,1},{8,17,7,1},{1,18,1,1}}}
T.glyphs[20828] = {w=18, advance=16, rects={{2,4,2,1},{7,4,2,1},{1,5,3,1},{5,5,6,1},{12,5,3,1},{1,6,2,4},{5,6,1,2},{10,6,1,2},{13,6,2,5},{5,8,6,1},{5,9,1,2},{10,9,1,2},{1,10,3,2},{5,11,6,1},{12,11,3,1},{5,13,1,2},{9,13,2,4},{14,14,2,3},{4,15,2,1},{2,16,3,1},{0,17,3,1},{10,17,5,1}}}
T.glyphs[20837] = {w=18, advance=16, rects={{5,5,1,1},{5,6,2,1},{6,7,2,1},{7,8,2,2},{6,10,4,1},{6,11,1,1},{9,11,1,1},{5,12,2,1},{9,12,2,1},{5,13,1,1},{10,13,1,1},{4,14,2,1},{10,14,2,1},{3,15,2,1},{11,15,2,1},{2,16,2,1},{12,16,2,1},{1,17,2,1},{13,17,2,1},{1,18,1,1},{14,18,1,1}}}
T.glyphs[20840] = {w=18, advance=16, rects={{7,4,2,1},{6,5,4,1},{5,6,2,1},{9,6,2,1},{4,7,2,1},{10,7,2,1},{3,8,2,1},{11,8,2,1},{1,9,3,1},{12,9,3,1},{0,10,2,1},{3,10,10,1},{14,10,2,1},{7,11,2,2},{2,13,12,1},{7,14,2,3},{1,17,14,1}}}
T.glyphs[20843] = {w=18, advance=16, rects={{5,5,1,3},{9,5,2,4},{4,8,2,4},{10,9,1,2},{10,11,2,2},{4,12,1,1},{3,13,2,1},{11,13,1,1},{3,14,1,1},{11,14,2,1},{2,15,2,1},{12,15,1,1},{1,16,2,2},{12,16,2,1},{13,17,2,1},{0,18,2,1},{14,18,1,1}}}
T.glyphs[20844] = {w=18, advance=16, rects={{5,5,1,1},{9,5,2,2},{4,6,2,2},{10,7,2,1},{3,8,2,1},{11,8,2,1},{2,9,2,1},{12,9,2,1},{1,10,2,1},{13,10,2,1},{1,11,1,1},{6,11,2,2},{14,11,1,1},{5,13,2,1},{10,13,1,2},{5,14,1,1},{4,15,1,1},{10,15,2,1},{3,16,2,1},{11,16,2,1},{2,17,11,1},{2,18,2,1},{12,18,2,1},{13,19,1,1}}}
T.glyphs[20845] = {w=18, advance=16, rects={{7,4,1,1},{7,5,2,2},{0,8,16,1},{5,11,1,1},{10,11,1,1},{4,12,2,2},{10,12,2,2},{3,14,2,1},{11,14,2,1},{2,15,2,2},{12,15,2,1},{12,16,3,1},{1,17,2,1},{13,17,2,1},{1,18,1,1},{14,18,1,1}}}
T.glyphs[20849] = {w=18, advance=16, rects={{4,4,2,3},{10,4,2,3},{1,7,14,1},{4,8,2,4},{10,8,2,4},{0,12,16,1},{5,14,1,1},{10,14,1,1},{3,15,3,1},{10,15,2,1},{2,16,3,1},{11,16,3,1},{1,17,3,1},{12,17,3,1},{1,18,1,1},{14,18,1,1}}}
T.glyphs[20851] = {w=18, advance=16, rects={{3,4,2,1},{11,4,1,1},{4,5,2,1},{10,5,2,1},{5,6,1,1},{9,6,2,1},{1,7,14,1},{7,8,2,3},{1,11,15,1},{7,12,2,1},{6,13,4,1},{6,14,1,1},{9,14,1,1},{5,15,2,1},{10,15,1,1},{3,16,3,1},{10,16,3,1},{2,17,2,1},{12,17,3,1},{1,18,2,1},{13,18,2,1}}}
T.glyphs[20854] = {w=18, advance=16, rects={{3,4,1,2},{12,4,1,2},{0,6,16,1},{3,7,1,1},{12,7,1,1},{3,8,10,1},{3,9,1,1},{12,9,1,1},{3,10,10,1},{3,11,1,3},{12,11,1,3},{0,14,16,1},{4,16,2,1},{10,16,2,1},{2,17,3,1},{11,17,4,1},{0,18,3,1},{14,18,2,1}}}
T.glyphs[20855] = {w=18, advance=16, rects={{2,5,12,1},{2,6,2,1},{12,6,2,1},{2,7,12,1},{2,8,2,1},{12,8,2,1},{2,9,12,1},{2,10,2,1},{12,10,2,1},{2,11,12,1},{2,12,2,1},{12,12,2,1},{0,13,16,1},{4,16,2,1},{9,16,3,1},{1,17,4,1},{11,17,4,1},{1,18,2,1},{13,18,2,1}}}
T.glyphs[20860] = {w=18, advance=16, rects={{4,4,1,1},{10,4,1,1},{4,5,2,1},{9,5,2,1},{0,6,16,1},{5,7,1,1},{9,7,1,1},{1,8,13,1},{5,9,1,2},{9,9,1,2},{12,9,2,2},{0,11,16,1},{5,12,1,2},{9,12,1,2},{12,12,2,2},{1,14,13,1},{4,15,2,1},{9,15,2,1},{2,16,2,1},{5,16,1,3},{9,16,1,3},{11,16,3,1},{0,17,2,1},{13,17,2,1}}}
T.glyphs[20869] = {w=18, advance=16, rects={{7,4,2,3},{1,7,14,1},{1,8,2,6},{7,8,2,3},{13,8,2,8},{6,11,4,1},{5,12,2,1},{9,12,2,1},{4,13,2,1},{10,13,2,1},{1,14,4,1},{11,14,1,1},{1,15,2,3},{13,16,1,1},{10,17,4,1}}}
T.glyphs[20876] = {w=18, advance=16, rects={{2,5,5,1},{9,5,5,1},{2,6,1,4},{6,6,1,4},{9,6,1,4},{13,6,1,4},{0,10,16,1},{2,11,1,3},{5,11,2,1},{9,11,1,3},{13,11,1,6},{6,12,1,3},{1,14,2,2},{8,14,2,2},{5,15,2,1},{1,16,1,2},{4,16,3,1},{8,16,1,2},{10,17,4,1}}}
T.glyphs[20877] = {w=18, advance=16, rects={{1,5,14,1},{7,6,2,2},{2,8,12,1},{2,9,2,2},{7,9,2,2},{12,9,2,2},{2,11,12,1},{2,12,2,2},{7,12,2,2},{12,12,2,2},{0,14,16,1},{2,15,2,4},{12,15,2,3},{9,18,4,1}}}
T.glyphs[20889] = {w=18, advance=16, rects={{1,5,14,1},{1,6,1,2},{14,6,1,2},{4,8,10,1},{3,9,2,1},{3,10,1,1},{3,11,11,1},{13,12,1,4},{0,14,12,1},{12,16,2,1},{8,17,5,1}}}
T.glyphs[20900] = {w=18, advance=16, rects={{1,4,14,1},{1,5,1,3},{5,5,1,1},{14,5,1,3},{4,6,2,1},{4,7,8,1},{3,8,1,1},{10,8,2,1},{2,9,2,1},{10,9,1,1},{1,10,13,1},{1,11,3,1},{7,11,2,1},{13,11,1,1},{2,12,12,1},{2,13,2,1},{6,13,3,1},{11,13,1,1},{5,14,2,1},{8,14,1,2},{11,14,2,1},{4,15,2,1},{12,15,1,1},{15,15,1,1},{2,16,3,1},{8,16,2,1},{14,16,2,1},{1,17,2,1},{8,17,7,1}}}
T.glyphs[20914] = {w=18, advance=16, rects={{9,4,2,3},{1,5,1,1},{1,6,2,1},{2,7,2,2},{5,7,10,1},{5,8,2,5},{9,8,2,5},{13,8,2,5},{3,11,1,1},{2,12,2,2},{5,13,10,1},{1,14,2,2},{5,14,2,1},{9,14,2,5},{13,14,2,1},{1,16,1,2}}}
T.glyphs[20915] = {w=18, advance=16, rects={{9,4,1,3},{1,5,1,1},{1,6,2,1},{2,7,2,1},{5,7,9,1},{3,8,1,1},{8,8,2,4},{12,8,2,1},{13,9,1,3},{2,11,1,1},{2,12,14,1},{2,13,1,1},{8,13,2,1},{1,14,2,2},{8,14,3,1},{7,15,2,1},{10,15,2,1},{0,16,2,1},{6,16,2,1},{11,16,2,1},{1,17,1,1},{4,17,3,1},{12,17,3,1},{4,18,1,1},{13,18,2,1}}}
T.glyphs[20928] = {w=18, advance=16, rects={{7,4,2,1},{1,5,1,1},{6,5,7,1},{1,6,2,2},{6,6,1,1},{11,6,2,1},{5,7,1,1},{10,7,2,1},{2,8,1,1},{4,8,10,1},{9,9,1,1},{13,9,1,1},{2,10,1,3},{4,10,12,1},{9,11,1,2},{13,11,1,2},{1,13,2,2},{5,13,9,1},{9,14,1,3},{13,14,1,1},{1,15,1,2},{6,17,4,1}}}
T.glyphs[20934] = {w=18, advance=16, rects={{7,4,1,1},{10,4,1,1},{1,5,1,1},{6,5,2,2},{10,5,2,1},{1,6,2,1},{11,6,1,1},{2,7,2,2},{5,7,11,1},{5,8,2,1},{10,8,2,2},{4,9,3,1},{4,10,1,1},{6,10,9,1},{6,11,1,2},{10,11,2,2},{2,12,2,1},{2,13,1,2},{6,13,9,1},{6,14,1,3},{10,14,2,3},{1,15,2,1},{1,16,1,2},{6,17,10,1},{6,18,1,1}}}
T.glyphs[20943] = {w=18, advance=16, rects={{11,4,1,2},{13,4,1,1},{1,5,1,1},{13,5,2,1},{1,6,2,1},{4,6,12,1},{2,7,1,1},{4,7,2,1},{11,7,1,5},{4,8,6,1},{4,9,2,5},{14,9,1,2},{2,10,1,2},{7,11,3,1},{13,11,2,1},{1,12,2,2},{7,12,1,3},{9,12,1,3},{11,12,3,2},{1,14,1,2},{4,14,1,2},{11,14,2,2},{7,15,3,1},{15,15,1,1},{0,16,2,1},{3,16,2,1},{7,16,1,1},{10,16,3,1},{14,16,2,1},{3,17,1,2},{9,17,2,1},{12,17,4,1},{9,18,1,1},{13,18,2,1}}}
T.glyphs[20945] = {w=18, advance=16, rects={{9,4,1,2},{1,5,1,1},{1,6,2,1},{4,6,11,1},{2,7,1,1},{8,7,2,1},{2,8,2,1},{5,8,10,1},{8,9,1,1},{4,10,12,1},{2,11,1,2},{6,11,2,1},{11,11,1,1},{5,12,8,1},{1,13,2,3},{4,13,2,1},{9,13,1,1},{13,13,2,1},{4,14,12,1},{8,15,2,1},{1,16,1,2},{7,16,5,1},{5,17,3,1},{11,17,3,1},{4,18,2,1},{13,18,2,1}}}
T.glyphs[20960] = {w=18, advance=16, rects={{4,5,8,1},{4,6,1,6},{10,6,2,11},{3,12,2,3},{14,14,2,3},{3,15,1,1},{2,16,2,1},{1,17,2,1},{10,17,5,1},{0,18,2,1}}}
T.glyphs[20961] = {w=18, advance=16, rects={{3,4,9,1},{3,5,2,1},{10,5,2,13},{3,6,1,8},{6,9,1,1},{6,10,2,1},{7,11,2,1},{8,12,1,1},{2,14,2,2},{14,14,2,3},{1,16,2,1},{0,17,3,1},{14,17,1,1},{1,18,1,1},{11,18,4,1}}}
T.glyphs[20986] = {w=18, advance=16, rects={{7,4,2,6},{2,5,1,5},{13,5,1,5},{2,10,12,1},{7,11,2,6},{12,11,2,1},{1,13,2,4},{13,13,2,4},{1,17,14,1},{13,18,2,1}}}
T.glyphs[20987] = {w=18, advance=16, rects={{7,4,2,2},{1,6,14,1},{7,7,2,3},{0,10,16,1},{7,11,2,6},{2,13,1,4},{13,13,1,4},{2,17,12,1},{13,18,1,1}}}
T.glyphs[20989] = {w=18, advance=16, rects={{2,5,11,1},{10,6,3,1},{8,7,3,1},{1,8,4,1},{8,8,1,3},{11,8,4,1},{1,9,2,4},{5,9,2,1},{10,9,2,1},{13,9,2,4},{6,11,5,1},{4,12,8,1},{1,13,5,1},{8,13,1,1},{11,13,4,1},{1,14,3,1},{7,14,2,1},{12,14,3,1},{1,15,2,2},{5,15,4,1},{13,15,2,2},{1,17,14,1},{13,18,2,1}}}
T.glyphs[20998] = {w=18, advance=16, rects={{5,4,2,1},{9,4,1,1},{5,5,1,1},{9,5,2,1},{4,6,2,1},{10,6,1,1},{3,7,2,1},{10,7,2,1},{2,8,2,1},{11,8,3,1},{1,9,2,1},{12,9,3,1},{0,10,2,1},{14,10,2,1},{2,11,11,1},{5,12,2,1},{11,12,2,4},{5,13,1,2},{4,15,2,1},{3,16,2,1},{11,16,1,1},{2,17,2,1},{7,17,5,1},{1,18,2,1}}}
T.glyphs[20999] = {w=18, advance=16, rects={{2,4,2,4},{6,5,9,1},{8,6,2,1},{13,6,2,10},{9,7,1,1},{2,8,5,1},{8,8,2,5},{0,9,5,1},{2,10,2,4},{6,13,1,1},{8,13,1,2},{2,14,5,1},{2,15,3,1},{7,15,2,1},{2,16,2,1},{6,16,2,1},{13,16,1,1},{5,17,2,1},{9,17,5,1},{5,18,1,1}}}
T.glyphs[21015] = {w=18, advance=16, rects={{13,4,2,13},{1,5,9,1},{3,6,2,2},{10,6,1,9},{3,8,6,1},{2,9,2,1},{7,9,2,1},{2,10,1,1},{7,10,1,1},{1,11,2,1},{6,11,2,2},{0,12,2,1},{3,12,2,1},{0,13,1,1},{4,13,3,1},{5,14,2,1},{4,15,2,1},{3,16,2,1},{1,17,3,1},{10,17,5,1},{1,18,2,1}}}
T.glyphs[21017] = {w=18, advance=16, rects={{13,4,2,13},{1,5,7,1},{1,6,2,9},{7,6,1,9},{10,6,2,9},{4,7,2,5},{4,12,1,2},{4,14,2,1},{3,15,4,1},{2,16,2,1},{6,16,3,1},{1,17,2,1},{7,17,2,1},{10,17,5,1},{0,18,2,1}}}
T.glyphs[21018] = {w=18, advance=16, rects={{14,4,1,13},{1,5,9,1},{1,6,1,1},{8,6,2,1},{11,6,1,9},{1,7,3,1},{6,7,4,1},{1,8,1,6},{3,8,1,1},{6,8,1,1},{8,8,2,6},{3,9,4,1},{4,10,2,2},{4,12,3,1},{3,13,1,1},{6,13,1,1},{1,14,3,1},{6,14,4,1},{1,15,1,3},{8,15,2,2},{5,17,4,1},{11,17,4,1}}}
T.glyphs[21019] = {w=18, advance=16, rects={{4,5,2,1},{13,5,2,12},{3,6,5,1},{10,6,2,10},{2,7,2,1},{7,7,2,1},{1,8,2,1},{8,8,1,1},{0,9,9,1},{2,10,1,8},{7,10,2,2},{7,12,1,2},{4,14,4,1},{8,16,1,2},{10,17,5,1},{2,18,7,1}}}
T.glyphs[21021] = {w=18, advance=16, rects={{2,4,1,1},{2,5,2,1},{6,5,9,1},{3,6,1,1},{8,6,2,1},{13,6,2,11},{0,7,6,1},{9,7,1,3},{4,8,1,1},{3,9,2,1},{3,10,1,1},{5,10,2,1},{8,10,2,4},{2,11,4,1},{1,12,5,1},{0,13,4,1},{5,13,2,1},{0,14,1,1},{2,14,2,5},{6,14,3,1},{7,15,2,1},{6,16,2,1},{5,17,2,1},{10,17,4,1},{5,18,1,1}}}
T.glyphs[21024] = {w=18, advance=16, rects={{14,4,1,13},{1,5,4,1},{6,5,4,1},{1,6,2,4},{4,6,1,4},{6,6,1,4},{9,6,1,4},{11,6,2,4},{0,10,13,1},{1,11,2,3},{4,11,1,5},{6,11,1,5},{9,11,1,6},{11,11,2,4},{1,14,1,3},{4,16,3,1},{0,17,1,1},{2,17,4,1},{7,17,3,1},{11,17,4,1}}}
T.glyphs[21028] = {w=18, advance=16, rects={{4,4,2,5},{14,4,1,13},{1,5,1,1},{8,5,1,1},{1,6,2,1},{7,6,2,1},{10,6,2,9},{2,7,1,1},{7,7,1,1},{1,9,8,1},{4,10,2,2},{0,12,9,1},{3,13,2,2},{3,15,1,1},{2,16,2,1},{1,17,2,1},{13,17,2,1},{1,18,1,1},{10,18,5,1}}}
T.glyphs[21033] = {w=18, advance=16, rects={{3,4,5,1},{13,4,2,14},{1,5,6,1},{10,5,1,11},{4,6,1,2},{0,8,9,1},{3,9,2,2},{3,11,4,1},{2,12,1,1},{4,12,3,1},{1,13,2,1},{4,13,1,6},{7,13,1,1},{1,14,1,1},{7,14,2,1},{0,15,2,1},{11,18,3,1}}}
T.glyphs[21035] = {w=18, advance=16, rects={{13,4,2,13},{1,5,8,1},{1,6,2,2},{7,6,2,2},{10,6,2,9},{1,8,8,1},{1,9,2,1},{7,9,2,1},{3,10,2,2},{1,12,8,1},{3,13,2,1},{7,13,2,3},{3,14,1,1},{2,15,2,2},{7,16,1,1},{1,17,2,1},{4,17,4,1},{10,17,5,1},{0,18,2,1}}}
T.glyphs[21040] = {w=18, advance=16, rects={{14,4,1,12},{0,5,10,1},{3,6,2,1},{10,6,2,9},{3,7,1,1},{6,7,2,1},{2,8,2,1},{7,8,1,1},{1,9,8,1},{1,10,5,1},{8,10,1,2},{4,11,2,1},{1,12,8,1},{4,13,2,3},{1,16,9,1},{13,16,2,1},{0,17,8,1},{11,17,4,1}}}
T.glyphs[21046] = {w=18, advance=16, rects={{2,6,8,1},{11,6,1,3},{14,6,1,10},{1,7,1,2},{5,7,1,2},{0,9,12,1},{5,10,1,2},{11,10,1,5},{1,12,9,1},{1,13,2,5},{5,13,1,3},{8,13,2,3},{5,16,4,1},{13,16,2,1},{5,17,1,2},{11,17,4,1}}}
T.glyphs[21047] = {w=18, advance=16, rects={{14,4,1,12},{2,5,8,1},{2,6,1,2},{9,6,1,2},{11,6,1,9},{2,8,8,1},{2,9,1,2},{9,9,1,1},{1,11,9,1},{1,12,4,3},{6,12,1,4},{9,12,1,4},{1,15,1,1},{3,15,2,2},{0,16,2,1},{6,16,4,1},{13,16,2,1},{0,17,1,1},{6,17,1,1},{11,17,4,1}}}
T.glyphs[21050] = {w=18, advance=16, rects={{4,4,2,2},{14,4,1,13},{0,6,10,1},{11,6,1,10},{4,7,2,1},{1,8,8,1},{1,9,2,1},{4,9,2,3},{8,9,1,3},{1,10,1,3},{4,12,5,1},{3,13,3,1},{2,14,5,1},{2,15,1,1},{4,15,4,1},{1,16,1,2},{4,16,2,3},{7,16,2,1},{8,17,1,1},{13,17,2,1},{11,18,3,1}}}
T.glyphs[21051] = {w=18, advance=16, rects={{4,4,2,1},{14,4,1,12},{5,5,1,1},{1,6,9,1},{11,6,1,9},{3,7,2,1},{2,8,2,1},{6,8,2,1},{2,9,1,1},{6,9,1,1},{1,10,6,1},{8,10,1,1},{4,11,2,1},{7,11,2,1},{3,12,2,1},{7,12,1,1},{1,13,2,1},{6,13,2,1},{0,14,2,1},{5,14,3,1},{4,15,2,1},{7,15,2,1},{2,16,2,1},{8,16,2,2},{13,16,2,1},{1,17,2,1},{11,17,4,1}}}
T.glyphs[21066] = {w=18, advance=16, rects={{4,4,2,4},{13,4,2,13},{1,5,2,1},{8,5,1,1},{2,6,1,1},{7,6,1,1},{10,6,2,8},{1,8,8,1},{1,9,2,2},{8,9,1,2},{1,11,8,1},{1,12,2,2},{8,12,1,2},{1,14,8,1},{1,15,2,3},{8,15,1,2},{5,17,4,1},{10,17,5,1}}}
T.glyphs[21069] = {w=18, advance=16, rects={{4,4,2,1},{10,4,2,1},{5,5,1,1},{10,5,1,1},{0,6,16,1},{1,8,7,1},{10,8,1,7},{13,8,2,9},{1,9,2,2},{7,9,1,2},{1,11,7,1},{1,12,2,2},{7,12,1,2},{1,14,7,1},{1,15,2,3},{7,15,1,2},{5,17,3,1},{10,17,4,1}}}
T.glyphs[21095] = {w=18, advance=16, rects={{14,4,1,13},{1,5,9,1},{1,6,2,2},{8,6,2,2},{11,6,1,10},{1,8,9,1},{1,9,2,2},{8,9,2,1},{6,10,1,1},{1,11,9,1},{1,12,2,2},{6,12,1,2},{1,14,8,1},{1,15,1,2},{3,15,2,1},{8,15,1,2},{3,16,1,1},{0,17,2,1},{3,17,6,1},{13,17,2,1},{0,18,1,1},{3,18,2,1},{8,18,1,1},{11,18,4,1}}}
T.glyphs[21097] = {w=18, advance=16, rects={{5,4,5,1},{14,4,1,13},{1,5,7,1},{5,6,1,1},{11,6,2,1},{0,7,13,1},{5,8,1,5},{11,8,2,1},{3,9,1,1},{7,9,1,1},{9,9,4,1},{0,10,4,1},{7,10,3,1},{11,10,2,2},{3,11,1,1},{7,11,1,2},{0,12,4,1},{9,12,4,1},{3,13,3,1},{7,13,3,1},{11,13,2,3},{3,14,4,1},{2,15,2,1},{5,15,3,1},{1,16,2,1},{5,16,1,3},{7,16,2,1},{1,17,1,1},{9,17,1,1},{13,17,2,1},{11,18,4,1}}}
T.glyphs[21098] = {w=18, advance=16, rects={{4,4,2,1},{10,4,2,1},{5,5,1,1},{10,5,1,1},{0,6,16,1},{2,7,1,1},{7,7,1,1},{2,8,6,1},{10,8,1,3},{13,8,1,4},{2,9,1,1},{7,9,1,1},{2,10,6,1},{2,11,1,2},{7,11,1,1},{5,12,3,1},{10,12,4,1},{1,14,14,1},{5,15,2,1},{13,15,1,2},{4,16,2,1},{3,17,2,1},{8,17,6,1},{1,18,2,1}}}
T.glyphs[21147] = {w=18, advance=16, rects={{6,4,2,3},{1,7,14,1},{6,8,2,1},{13,8,2,4},{6,9,1,3},{5,12,2,2},{13,12,1,4},{4,14,2,2},{2,16,3,1},{12,16,2,1},{1,17,3,1},{8,17,5,1},{1,18,1,1}}}
T.glyphs[21151] = {w=18, advance=16, rects={{9,4,1,3},{0,6,7,1},{2,7,2,1},{6,7,9,1},{3,8,1,5},{8,8,2,5},{13,8,2,9},{3,13,4,1},{8,13,1,1},{1,14,5,1},{7,14,2,1},{0,15,3,1},{7,15,1,1},{6,16,2,1},{5,17,2,1},{9,17,5,1},{4,18,2,1}}}
T.glyphs[21152] = {w=18, advance=16, rects={{3,4,1,3},{9,6,6,1},{0,7,8,1},{9,7,2,9},{14,7,1,9},{2,8,2,1},{6,8,2,8},{3,9,1,2},{2,11,2,3},{2,14,1,2},{1,16,2,1},{6,16,1,1},{9,16,6,1},{0,17,2,1},{3,17,4,1},{9,17,2,1},{14,17,1,1},{0,18,1,1}}}
T.glyphs[21153] = {w=18, advance=16, rects={{4,4,2,2},{3,6,11,1},{2,7,4,1},{11,7,2,1},{1,8,2,1},{5,8,2,1},{10,8,2,1},{1,9,1,1},{6,9,5,1},{5,10,8,1},{2,11,4,1},{10,11,6,1},{0,12,3,1},{6,12,1,1},{1,13,13,1},{5,14,2,2},{12,14,2,1},{12,15,1,2},{4,16,2,1},{2,17,3,1},{8,17,5,1},{1,18,2,1}}}
T.glyphs[21160] = {w=18, advance=16, rects={{10,4,1,3},{1,5,6,1},{7,7,8,1},{9,8,2,1},{14,8,1,8},{0,9,8,1},{10,9,1,1},{3,10,1,1},{9,10,2,4},{2,11,2,2},{5,12,1,1},{2,13,1,1},{5,13,2,2},{1,14,2,1},{9,14,1,1},{0,15,5,1},{6,15,1,1},{8,15,2,1},{1,16,2,1},{6,16,3,1},{13,16,2,1},{7,17,2,1},{10,17,5,1},{7,18,1,1}}}
T.glyphs[21161] = {w=18, advance=16, rects={{1,5,6,1},{10,5,1,2},{1,6,2,2},{6,6,1,2},{8,7,7,1},{1,8,6,1},{9,8,2,1},{13,8,2,9},{1,9,2,2},{6,9,1,2},{10,9,1,1},{9,10,2,4},{1,11,6,1},{1,12,2,3},{6,12,1,3},{9,14,1,1},{1,15,9,1},{0,16,5,1},{8,16,1,1},{7,17,2,1},{10,17,4,1},{7,18,1,1}}}
T.glyphs[21183] = {w=18, advance=16, rects={{3,4,2,2},{9,4,1,2},{1,6,5,1},{7,6,6,1},{3,7,2,1},{9,7,1,1},{12,7,1,3},{2,8,8,1},{1,9,4,1},{8,9,2,1},{15,9,1,1},{3,10,2,1},{7,10,2,1},{10,10,1,1},{12,10,4,1},{1,11,3,1},{6,11,2,1},{13,11,2,1},{5,12,2,1},{1,13,13,1},{6,14,1,1},{12,14,2,3},{5,15,2,1},{4,16,2,1},{2,17,3,1},{8,17,5,1},{1,18,2,1}}}
T.glyphs[21247] = {w=18, advance=16, rects={{4,4,2,1},{4,5,1,1},{3,6,12,1},{3,7,1,1},{6,7,2,2},{10,7,2,1},{13,7,2,8},{2,8,2,1},{10,8,1,2},{1,9,2,1},{6,9,1,1},{1,10,1,1},{5,10,2,1},{9,10,2,2},{4,11,2,2},{9,12,1,1},{3,13,2,1},{8,13,2,1},{1,14,3,1},{7,14,2,1},{1,15,1,1},{7,15,1,1},{13,15,1,1},{5,16,3,1},{12,16,2,1},{4,17,2,1},{8,17,6,1},{4,18,1,1}}}
T.glyphs[21248] = {w=18, advance=16, rects={{4,4,2,1},{4,5,1,1},{3,6,12,1},{2,7,2,1},{13,7,2,7},{2,8,1,1},{4,8,2,1},{1,9,2,1},{5,9,2,1},{1,10,1,1},{6,10,2,1},{7,11,1,1},{9,12,3,1},{5,13,6,1},{1,14,6,1},{13,14,1,2},{1,15,3,1},{12,16,2,1},{8,17,6,1},{8,18,1,1},{10,18,2,1}}}
T.glyphs[21253] = {w=18, advance=16, rects={{4,4,1,1},{3,5,2,1},{3,6,11,1},{2,7,2,1},{12,7,2,7},{1,8,2,1},{1,9,9,1},{0,10,4,1},{8,10,2,2},{2,11,2,1},{2,12,8,1},{2,13,2,4},{12,14,1,1},{14,14,2,2},{8,15,5,1},{14,16,1,1},{3,17,12,1}}}
T.glyphs[21270] = {w=18, advance=16, rects={{4,4,1,2},{8,4,2,6},{3,6,2,1},{13,6,2,2},{3,7,1,1},{2,8,2,2},{12,8,2,1},{11,9,2,1},{1,10,3,1},{8,10,4,1},{0,11,4,1},{8,11,3,1},{0,12,1,1},{3,12,1,7},{7,12,3,1},{6,13,4,1},{5,14,2,1},{8,14,2,3},{14,14,2,3},{9,17,6,1}}}
T.glyphs[21271] = {w=18, advance=16, rects={{5,4,1,4},{9,4,2,4},{13,7,2,1},{0,8,6,1},{9,8,6,1},{5,9,1,5},{9,9,4,1},{9,10,2,7},{14,13,2,3},{3,14,3,1},{1,15,3,1},{5,15,1,4},{0,16,2,1},{14,16,1,1},{10,17,5,1}}}
T.glyphs[21306] = {w=18, advance=16, rects={{1,5,14,1},{1,6,2,11},{4,7,2,1},{12,7,1,1},{5,8,2,1},{11,8,2,1},{6,9,2,1},{10,9,2,1},{7,10,4,1},{8,11,2,1},{7,12,4,1},{5,13,3,1},{10,13,3,1},{4,14,3,1},{11,14,3,1},{4,15,1,1},{12,15,2,1},{1,17,14,1}}}
T.glyphs[21313] = {w=18, advance=16, rects={{7,4,2,6},{0,10,16,1},{7,11,2,8}}}
T.glyphs[21315] = {w=18, advance=16, rects={{8,4,6,1},{1,5,13,1},{7,6,2,5},{0,11,16,1},{7,12,2,7}}}
T.glyphs[21319] = {w=18, advance=16, rects={{11,4,1,6},{5,5,4,1},{1,6,7,1},{4,7,2,3},{0,10,16,1},{4,11,2,3},{10,11,2,1},{11,12,1,7},{4,14,1,1},{3,15,2,2},{1,17,3,1},{1,18,1,1}}}
T.glyphs[21322] = {w=18, advance=16, rects={{7,4,2,5},{2,5,1,1},{13,5,1,1},{2,6,3,1},{11,6,3,1},{4,7,1,1},{11,7,1,1},{1,9,14,1},{7,10,2,3},{0,13,16,1},{7,14,2,5}}}
T.glyphs[21333] = {w=18, advance=16, rects={{4,4,1,1},{11,4,1,1},{4,5,2,1},{10,5,2,1},{5,6,1,1},{10,6,1,1},{2,7,12,1},{2,8,1,1},{7,8,2,1},{13,8,1,1},{2,9,12,1},{2,10,1,2},{7,10,2,2},{13,10,1,2},{2,12,12,1},{2,13,1,1},{7,13,2,2},{13,13,1,1},{0,15,16,1},{7,16,2,3}}}
T.glyphs[21335] = {w=18, advance=16, rects={{7,4,2,2},{0,6,16,1},{7,7,2,2},{1,9,14,1},{1,10,2,5},{5,10,1,1},{10,10,1,1},{13,10,2,5},{6,11,1,1},{9,11,2,1},{4,12,8,1},{7,13,2,2},{1,15,14,1},{1,16,2,3},{7,16,2,3},{13,16,2,2},{10,18,5,1}}}
T.glyphs[21344] = {w=18, advance=16, rects={{7,4,1,3},{7,7,9,1},{7,8,1,3},{2,11,12,1},{2,12,2,5},{12,12,2,5},{2,17,12,1},{2,18,2,1},{12,18,2,1}}}
T.glyphs[21345] = {w=18, advance=16, rects={{7,4,1,2},{7,6,8,1},{7,7,1,3},{0,10,16,1},{7,12,1,1},{7,13,3,1},{7,14,1,5},{9,14,3,1},{11,15,3,1},{13,16,1,1}}}
T.glyphs[21355] = {w=18, advance=16, rects={{1,5,13,1},{5,6,2,1},{13,6,1,5},{6,7,1,10},{12,11,2,2},{8,13,5,1},{0,17,16,1}}}
T.glyphs[21360] = {w=18, advance=16, rects={{4,4,3,1},{1,5,4,1},{8,5,7,1},{1,6,2,4},{8,6,2,10},{13,6,2,10},{1,10,6,1},{1,11,2,5},{6,14,1,1},{4,15,3,1},{1,16,4,1},{8,16,6,1},{1,17,1,1},{8,17,2,2}}}
T.glyphs[21363] = {w=18, advance=16, rects={{1,5,7,1},{9,5,6,1},{1,6,2,2},{6,6,2,2},{9,6,2,10},{13,6,2,10},{1,8,7,1},{1,9,2,2},{6,9,2,2},{1,11,7,1},{1,12,2,5},{6,12,2,1},{5,13,1,1},{5,14,2,1},{5,15,3,1},{4,16,4,1},{9,16,5,1},{1,17,4,1},{7,17,1,1},{9,17,2,2},{1,18,3,1},{1,19,2,1}}}
T.glyphs[21364] = {w=18, advance=16, rects={{4,4,1,3},{9,5,6,1},{9,6,2,1},{13,6,2,1},{1,7,7,1},{9,7,1,4},{14,7,1,7},{4,8,1,3},{0,11,10,1},{3,12,2,1},{9,12,1,3},{2,13,2,1},{5,13,2,1},{2,14,1,1},{6,14,1,1},{13,14,2,1},{1,15,7,1},{9,15,6,1},{0,16,4,1},{7,16,1,2},{9,16,1,3}}}
T.glyphs[21387] = {w=18, advance=16, rects={{2,5,14,1},{2,6,2,4},{9,7,1,3},{2,10,13,1},{2,11,2,1},{9,11,1,6},{2,12,1,3},{12,12,1,1},{12,13,2,1},{13,14,1,2},{1,15,2,2},{1,17,1,2},{3,17,13,1}}}
T.glyphs[21402] = {w=18, advance=16, rects={{2,5,14,1},{2,6,1,7},{5,7,9,1},{5,8,1,1},{13,8,1,1},{5,9,9,1},{5,10,1,1},{13,10,1,1},{5,11,9,1},{1,13,2,2},{5,13,9,1},{11,14,1,1},{1,15,1,2},{3,15,13,1},{9,16,2,1},{0,17,2,1},{6,17,4,1}}}
T.glyphs[21407] = {w=18, advance=16, rects={{2,5,14,1},{2,6,1,8},{8,6,2,1},{5,7,9,1},{5,8,1,1},{13,8,1,1},{5,9,9,1},{5,10,1,2},{13,10,1,2},{5,12,9,1},{5,13,1,1},{9,13,1,4},{13,13,1,1},{1,14,2,2},{6,14,1,1},{12,14,1,1},{5,15,2,1},{12,15,2,1},{0,16,2,1},{4,16,2,1},{13,16,2,1},{0,17,1,1},{3,17,2,1},{6,17,4,1},{14,17,1,1}}}
T.glyphs[21435] = {w=18, advance=16, rects={{7,4,2,3},{2,7,13,1},{7,8,2,3},{0,11,16,1},{6,12,2,1},{5,13,2,1},{10,13,1,1},{4,14,2,2},{10,14,2,1},{11,15,2,1},{3,16,2,1},{7,16,7,1},{2,17,7,1},{13,17,1,1},{13,18,2,1}}}
T.glyphs[21442] = {w=18, advance=16, rects={{6,4,1,1},{5,5,2,1},{10,5,1,1},{3,6,2,1},{10,6,2,1},{2,7,12,1},{6,8,1,1},{13,8,1,1},{1,9,14,1},{4,10,2,1},{10,10,2,1},{3,11,2,1},{8,11,1,1},{11,11,2,1},{1,12,2,1},{6,12,2,1},{12,12,3,1},{0,13,2,1},{3,13,3,1},{9,13,2,1},{14,13,2,1},{7,14,3,1},{11,14,2,1},{4,15,4,1},{10,15,2,1},{2,16,3,1},{8,16,3,1},{5,17,3,1},{2,18,3,1}}}
T.glyphs[21448] = {w=18, advance=16, rects={{1,5,12,1},{3,6,2,2},{11,6,2,3},{4,8,1,2},{11,9,1,1},{4,10,2,1},{10,10,2,1},{5,11,1,1},{10,11,1,1},{5,12,2,1},{9,12,2,1},{6,13,4,1},{7,14,2,1},{6,15,4,1},{4,16,3,1},{9,16,3,1},{1,17,4,1},{11,17,4,1},{1,18,2,1},{13,18,2,1}}}
T.glyphs[21449] = {w=18, advance=16, rects={{1,5,13,1},{2,6,2,1},{12,6,2,1},{3,7,1,1},{7,7,1,2},{12,7,1,1},{3,8,2,2},{11,8,2,2},{7,9,2,1},{4,10,1,1},{8,10,1,1},{11,10,1,1},{4,11,2,1},{10,11,2,1},{5,12,2,1},{9,12,2,1},{6,13,4,1},{7,14,3,1},{6,15,4,1},{4,16,3,1},{9,16,3,1},{1,17,4,1},{11,17,4,1},{1,18,2,1},{13,18,2,1}}}
T.glyphs[21450] = {w=18, advance=16, rects={{1,5,12,1},{4,6,2,4},{11,6,1,1},{10,7,2,1},{10,8,1,1},{9,9,5,1},{4,10,3,1},{12,10,2,1},{4,11,1,1},{6,11,1,1},{12,11,1,1},{3,12,2,2},{6,12,2,1},{11,12,2,1},{7,13,1,1},{11,13,1,1},{3,14,1,1},{8,14,4,1},{2,15,2,1},{8,15,3,1},{1,16,2,2},{7,16,5,1},{5,17,3,1},{11,17,4,1},{1,18,1,1},{4,18,2,1},{13,18,2,1}}}
T.glyphs[21451] = {w=18, advance=16, rects={{5,5,2,2},{1,7,15,1},{4,8,2,2},{4,10,10,1},{4,11,3,1},{12,11,2,1},{3,12,2,1},{6,12,1,1},{11,12,2,1},{3,13,1,1},{7,13,1,1},{11,13,1,1},{2,14,2,1},{7,14,5,1},{2,15,1,1},{7,15,4,1},{1,16,2,1},{5,16,4,1},{10,16,5,1},{0,17,2,1},{3,17,3,1},{13,17,2,1}}}
T.glyphs[21452] = {w=18, advance=16, rects={{0,5,15,1},{5,6,2,3},{8,6,1,3},{13,6,2,2},{1,7,1,1},{1,8,2,1},{13,8,1,2},{2,9,2,1},{5,9,1,1},{8,9,2,2},{3,10,3,2},{12,10,2,1},{9,11,1,1},{12,11,1,1},{4,12,2,1},{9,12,4,1},{3,13,3,1},{10,13,2,1},{2,14,2,1},{5,14,2,1},{10,14,3,1},{2,15,1,1},{6,15,1,1},{8,15,3,1},{12,15,2,1},{1,16,2,1},{7,16,2,1},{13,16,2,1},{0,17,2,1},{6,17,2,1},{14,17,1,1}}}
T.glyphs[21453] = {w=18, advance=16, rects={{9,4,6,1},{2,5,12,1},{2,6,2,2},{2,8,12,1},{2,9,2,2},{5,9,1,1},{12,9,2,2},{5,10,2,1},{2,11,1,3},{6,11,1,1},{11,11,2,1},{6,12,2,1},{10,12,2,1},{7,13,4,1},{1,14,2,2},{8,14,3,1},{6,15,6,1},{1,16,1,1},{4,16,4,1},{11,16,4,1},{0,17,1,1},{3,17,2,1},{13,17,2,1}}}
T.glyphs[21457] = {w=18, advance=16, rects={{2,4,1,1},{6,4,2,1},{10,4,2,1},{1,5,2,2},{6,5,1,2},{11,5,2,1},{12,6,1,1},{1,7,15,1},{5,8,2,1},{5,9,1,1},{4,10,10,1},{4,11,3,1},{12,11,2,1},{4,12,1,1},{6,12,2,1},{12,12,1,1},{3,13,2,1},{7,13,1,1},{11,13,2,1},{2,14,2,1},{7,14,2,1},{10,14,2,1},{2,15,1,1},{8,15,3,1},{1,16,2,1},{7,16,5,1},{0,17,2,1},{4,17,4,1},{11,17,4,1},{3,18,3,1},{13,18,2,1}}}
T.glyphs[21462] = {w=18, advance=16, rects={{0,5,8,1},{1,6,2,2},{6,6,1,2},{8,6,7,1},{8,7,2,1},{13,7,2,2},{1,8,6,1},{9,8,1,3},{1,9,2,2},{6,9,1,2},{13,9,1,2},{1,11,6,1},{9,11,2,1},{12,11,2,1},{1,12,2,2},{6,12,1,2},{10,12,1,1},{12,12,1,1},{10,13,3,2},{1,14,8,1},{0,15,7,1},{9,15,5,1},{6,16,1,1},{8,16,2,1},{13,16,2,1},{6,17,3,1},{14,17,2,1}}}
T.glyphs[21463] = {w=18, advance=16, rects={{9,4,5,1},{1,5,11,1},{2,6,2,1},{7,6,1,1},{12,6,1,1},{3,7,1,1},{7,7,2,1},{11,7,2,1},{3,8,2,1},{8,8,1,1},{11,8,1,1},{1,9,14,1},{1,10,1,1},{14,10,1,1},{3,11,10,1},{4,12,2,1},{10,12,2,1},{5,13,1,1},{10,13,1,1},{6,14,4,2},{3,16,4,1},{9,16,5,1},{0,17,4,1},{12,17,3,1}}}
T.glyphs[21464] = {w=18, advance=16, rects={{7,4,1,1},{7,5,2,1},{0,6,16,1},{5,7,2,4},{9,7,2,4},{3,8,1,1},{12,8,1,1},{2,9,2,1},{12,9,2,1},{1,10,2,1},{13,10,2,1},{1,11,1,1},{14,11,1,1},{2,12,11,1},{4,13,2,1},{10,13,2,1},{5,14,2,1},{9,14,2,1},{6,15,4,1},{3,16,10,1},{1,17,3,1},{10,17,6,1}}}
T.glyphs[21472] = {w=18, advance=16, rects={{2,5,11,1},{3,6,1,1},{9,6,3,1},{4,7,10,1},{1,9,14,1},{2,10,2,1},{5,10,1,1},{9,10,2,1},{12,10,2,1},{1,11,6,1},{8,11,3,1},{12,11,3,1},{1,13,14,1},{1,14,1,1},{3,14,1,1},{12,14,1,1},{14,14,1,1},{3,15,10,1},{3,16,1,1},{12,16,1,1},{0,17,16,1}}}
T.glyphs[21475] = {w=18, advance=16, rects={{2,5,12,1},{2,6,1,10},{13,6,1,10},{2,16,12,1},{2,17,1,2},{13,17,1,2}}}
T.glyphs[21477] = {w=18, advance=16, rects={{4,4,1,1},{3,5,2,1},{3,6,12,1},{2,7,2,1},{13,7,2,5},{2,8,1,1},{1,9,9,1},{1,10,1,1},{3,10,1,4},{9,10,1,4},{13,12,1,5},{3,14,7,1},{3,15,1,1},{11,17,3,1},{7,18,6,1}}}
T.glyphs[21478] = {w=18, advance=16, rects={{2,5,12,1},{2,6,2,3},{12,6,2,3},{2,9,12,1},{2,10,2,1},{12,10,2,1},{1,12,14,1},{5,13,2,1},{13,13,2,2},{5,14,1,1},{4,15,2,1},{13,15,1,1},{2,16,3,1},{12,16,2,1},{1,17,2,1},{8,17,6,1}}}
T.glyphs[21482] = {w=18, advance=16, rects={{2,5,12,1},{2,6,2,5},{12,6,2,5},{2,11,12,1},{2,12,2,1},{12,12,2,1},{5,13,1,1},{10,13,1,1},{4,14,2,1},{10,14,2,1},{3,15,2,1},{11,15,2,1},{2,16,2,1},{12,16,2,1},{1,17,2,1},{13,17,2,1},{1,18,1,1},{14,18,1,1}}}
T.glyphs[21487] = {w=18, advance=16, rects={{0,5,16,1},{12,6,1,10},{2,8,7,1},{2,9,1,5},{7,9,2,1},{8,10,1,4},{2,14,7,1},{2,15,1,1},{8,16,1,1},{11,16,2,1},{8,17,5,1}}}
T.glyphs[21488] = {w=18, advance=16, rects={{6,4,2,1},{6,5,1,1},{5,6,2,1},{11,6,1,1},{4,7,2,1},{11,7,2,1},{3,8,2,1},{12,8,2,1},{2,9,2,1},{7,9,8,1},{1,10,10,1},{14,10,2,2},{1,11,1,1},{2,13,12,1},{2,14,2,3},{12,14,2,3},{2,17,12,1},{2,18,2,1},{12,18,2,1}}}
T.glyphs[21491] = {w=18, advance=16, rects={{7,4,1,1},{6,5,2,1},{0,6,16,1},{5,7,2,1},{5,8,1,1},{4,9,2,1},{4,10,1,1},{3,11,11,1},{2,12,3,1},{13,12,1,5},{1,13,4,1},{1,14,2,1},{4,14,1,3},{1,15,1,1},{4,17,10,1},{4,18,1,2},{13,18,1,2}}}
T.glyphs[21494] = {w=18, advance=16, rects={{10,4,2,5},{1,6,5,1},{1,7,2,7},{5,7,1,2},{5,9,11,1},{5,10,1,4},{10,10,2,9},{1,14,5,1},{1,15,2,2},{5,15,1,1}}}
T.glyphs[21495] = {w=18, advance=16, rects={{3,5,10,1},{3,6,1,2},{12,6,1,2},{3,8,10,1},{3,9,1,1},{12,9,1,1},{0,11,16,1},{3,12,2,2},{3,14,11,1},{12,15,2,1},{12,16,1,1},{6,17,7,1},{9,18,2,1}}}
T.glyphs[21497] = {w=18, advance=16, rects={{1,5,14,1},{1,6,1,8},{4,6,2,1},{7,6,2,3},{13,6,2,2},{5,7,1,7},{13,8,1,2},{8,9,1,2},{12,10,2,1},{8,11,2,1},{12,11,1,1},{9,12,1,1},{11,12,2,1},{9,13,3,1},{1,14,5,1},{10,14,2,1},{1,15,1,1},{9,15,4,1},{8,16,2,1},{12,16,2,1},{6,17,2,1},{13,17,2,1},{5,18,2,1},{14,18,1,1}}}
T.glyphs[21507] = {w=18, advance=16, rects={{8,4,2,2},{1,6,5,1},{8,6,1,1},{1,7,1,7},{4,7,2,2},{7,7,9,1},{7,8,1,1},{4,9,4,1},{4,10,10,1},{4,11,2,3},{11,11,2,1},{10,12,2,1},{9,13,2,1},{14,13,2,3},{1,14,5,1},{8,14,2,1},{1,15,1,2},{4,15,2,2},{7,15,2,1},{7,16,1,1},{14,16,1,1},{7,17,8,1}}}
T.glyphs[21508] = {w=18, advance=16, rects={{4,4,2,1},{4,5,1,1},{3,6,11,1},{2,7,4,1},{11,7,2,1},{1,8,2,1},{5,8,2,1},{10,8,2,1},{1,9,1,1},{6,9,5,1},{6,10,6,1},{2,11,4,1},{10,11,6,1},{0,12,3,1},{3,13,11,1},{3,14,1,3},{12,14,2,3},{3,17,11,1},{3,18,1,1},{12,18,2,1}}}
T.glyphs[21512] = {w=18, advance=16, rects={{7,4,2,1},{6,5,4,1},{5,6,2,1},{9,6,2,1},{4,7,2,1},{10,7,2,1},{3,8,2,1},{11,8,2,1},{1,9,14,1},{0,10,2,1},{14,10,2,1},{2,12,12,1},{2,13,2,4},{12,13,2,4},{2,17,12,1},{2,18,2,1},{12,18,2,1}}}
T.glyphs[21516] = {w=18, advance=16, rects={{1,5,14,1},{1,6,2,2},{13,6,2,2},{1,8,14,1},{1,9,2,10},{13,9,2,9},{5,11,6,1},{5,12,1,3},{10,12,1,3},{5,15,6,1},{5,16,1,1},{10,18,4,1}}}
T.glyphs[21517] = {w=18, advance=16, rects={{5,4,2,2},{4,6,10,1},{3,7,2,1},{12,7,2,1},{1,8,3,1},{5,8,1,1},{10,8,3,1},{1,9,1,1},{5,9,2,1},{9,9,2,1},{6,10,4,1},{5,11,3,1},{2,12,12,1},{0,13,5,1},{13,13,1,4},{3,14,2,3},{3,17,11,1},{3,18,2,1},{13,18,1,1}}}
T.glyphs[21518] = {w=18, advance=16, rects={{9,4,5,1},{2,5,12,1},{2,6,2,1},{2,7,1,1},{2,8,14,1},{2,9,2,1},{2,10,1,5},{5,12,9,1},{5,13,1,4},{13,13,1,4},{1,15,2,1},{1,16,1,1},{0,17,2,1},{5,17,9,1},{0,18,1,1},{5,18,1,1},{13,18,1,1}}}
T.glyphs[21521] = {w=18, advance=16, rects={{6,4,2,2},{1,6,14,1},{1,7,2,11},{13,7,2,10},{5,9,6,1},{5,10,1,3},{10,10,1,3},{5,13,6,1},{5,14,1,1},{10,17,4,1}}}
T.glyphs[21534] = {w=18, advance=16, rects={{2,5,12,1},{7,6,2,1},{6,7,2,1},{0,8,16,1},{5,9,2,1},{9,9,2,1},{4,10,2,1},{10,10,1,1},{3,11,3,1},{10,11,3,1},{1,12,4,1},{11,12,4,1},{0,13,16,1},{3,14,2,3},{12,14,1,3},{3,17,10,1},{3,18,2,1},{12,18,1,1}}}
T.glyphs[21542] = {w=18, advance=16, rects={{1,5,14,1},{7,6,2,1},{6,7,5,1},{5,8,1,1},{7,8,2,3},{10,8,2,1},{3,9,2,1},{12,9,2,1},{1,10,3,1},{13,10,2,1},{1,11,1,1},{14,11,2,1},{2,12,12,1},{2,13,2,4},{12,13,2,4},{2,17,12,1},{2,18,2,1},{12,18,2,1}}}
T.glyphs[21543] = {w=18, advance=16, rects={{6,5,9,1},{1,6,4,1},{6,6,2,5},{10,6,1,5},{13,6,2,5},{1,7,1,6},{4,7,1,6},{6,11,9,1},{6,12,2,5},{13,12,2,2},{1,13,4,1},{1,14,1,2},{4,14,1,1},{14,14,2,3},{7,17,8,1}}}
T.glyphs[21547] = {w=18, advance=16, rects={{7,4,2,1},{6,5,4,1},{5,6,2,1},{9,6,2,1},{3,7,2,1},{7,7,1,1},{10,7,3,1},{1,8,3,1},{7,8,2,1},{12,8,3,1},{0,9,2,1},{14,9,2,1},{3,10,10,1},{10,11,2,1},{9,12,2,1},{2,13,12,1},{2,14,2,3},{12,14,2,3},{2,17,12,1},{2,18,2,1},{12,18,2,1}}}
T.glyphs[21548] = {w=18, advance=16, rects={{11,4,4,1},{1,5,5,1},{7,5,6,1},{1,6,2,8},{4,6,2,8},{7,6,2,4},{7,10,9,1},{7,11,2,4},{12,11,1,8},{1,14,5,1},{1,15,2,1},{7,15,1,1},{6,16,2,2},{5,18,2,1}}}
T.glyphs[21551] = {w=18, advance=16, rects={{7,4,1,1},{7,5,2,1},{2,6,13,1},{2,7,1,2},{13,7,2,2},{2,9,13,1},{2,10,1,4},{13,10,2,1},{4,13,11,1},{1,14,2,2},{4,14,2,3},{13,14,2,3},{1,16,1,1},{0,17,2,1},{4,17,11,1},{0,18,1,1},{4,18,2,1},{13,18,2,1}}}
T.glyphs[21560] = {w=18, advance=16, rects={{1,4,13,1},{1,5,1,9},{4,5,1,9},{7,5,2,1},{12,5,2,1},{7,6,1,2},{12,6,1,1},{11,7,2,1},{7,8,2,3},{11,8,1,1},{11,9,4,1},{13,10,2,1},{7,11,3,1},{13,11,1,1},{7,12,1,1},{9,12,1,1},{12,12,2,1},{6,13,2,2},{9,13,2,1},{12,13,1,1},{1,14,4,1},{10,14,3,2},{1,15,1,1},{6,15,1,1},{5,16,2,1},{9,16,2,1},{12,16,2,1},{4,17,2,1},{7,17,3,1},{13,17,3,1},{4,18,1,1},{7,18,2,1},{14,18,1,1}}}
T.glyphs[21563] = {w=18, advance=16, rects={{8,4,1,1},{7,5,2,2},{1,6,4,1},{1,7,1,7},{4,7,1,2},{7,7,8,1},{6,8,2,1},{9,8,1,2},{11,8,2,2},{14,8,1,4},{4,9,3,2},{8,10,2,1},{11,10,1,2},{4,11,1,3},{8,11,1,1},{7,12,2,1},{10,12,2,1},{13,12,2,5},{7,13,1,1},{10,13,1,1},{1,14,7,1},{9,14,2,1},{1,15,1,2},{4,15,3,1},{8,15,2,1},{4,16,1,1},{7,16,2,1},{7,17,1,1},{10,17,4,1}}}
T.glyphs[21578] = {w=18, advance=16, rects={{3,5,2,1},{8,5,1,1},{3,6,12,1},{2,7,2,1},{8,7,1,3},{1,8,2,1},{0,10,16,1},{2,13,12,1},{2,14,2,3},{12,14,2,3},{2,17,12,1},{2,18,2,1},{12,18,2,1}}}
T.glyphs[21608] = {w=18, advance=16, rects={{2,5,13,1},{2,6,1,7},{14,6,1,11},{4,8,8,1},{8,9,1,2},{4,11,9,1},{1,13,2,3},{5,13,7,1},{5,14,1,2},{10,14,2,2},{1,16,1,1},{5,16,7,1},{0,17,2,1},{5,17,1,1},{13,17,2,1},{0,18,1,1},{10,18,5,1}}}
T.glyphs[21628] = {w=18, advance=16, rects={{11,4,4,1},{6,5,8,1},{1,6,4,1},{10,6,1,5},{1,7,2,1},{4,7,1,4},{7,7,1,1},{14,7,1,1},{1,8,1,6},{7,8,2,1},{13,8,2,1},{8,9,1,1},{12,9,2,1},{4,11,12,1},{4,12,1,2},{10,12,2,1},{10,13,1,4},{1,14,4,1},{1,15,2,1},{4,15,1,2},{1,16,1,1},{7,17,4,1}}}
T.glyphs[21629] = {w=18, advance=16, rects={{7,4,2,1},{6,5,4,1},{5,6,2,1},{9,6,2,1},{3,7,3,1},{11,7,2,1},{1,8,3,1},{12,8,3,1},{0,9,2,1},{4,9,8,1},{14,9,2,1},{2,12,5,1},{8,12,6,1},{2,13,1,3},{6,13,1,3},{8,13,2,3},{13,13,1,3},{2,16,5,1},{8,16,6,1},{2,17,1,1},{6,17,1,1},{8,17,2,2}}}
T.glyphs[21644] = {w=18, advance=16, rects={{3,4,4,1},{1,5,5,1},{3,6,2,2},{8,6,7,1},{8,7,2,1},{14,7,1,9},{0,8,10,1},{3,9,2,1},{8,9,2,7},{2,10,3,1},{2,11,4,1},{1,12,6,1},{1,13,1,1},{3,13,2,5},{6,13,1,1},{0,14,2,1},{0,15,1,1},{8,16,7,1},{8,17,1,1},{14,17,1,1}}}
T.glyphs[21676] = {w=18, advance=16, rects={{10,4,1,3},{1,5,5,1},{1,6,1,8},{4,6,2,1},{4,7,12,1},{4,8,2,2},{8,8,2,1},{7,9,2,1},{12,9,1,1},{4,10,4,1},{12,10,3,2},{4,11,3,1},{8,11,1,2},{4,12,2,2},{12,12,1,1},{8,13,2,1},{11,13,2,1},{1,14,5,1},{9,14,3,2},{1,15,1,1},{7,16,3,1},{11,16,3,1},{5,17,3,1},{13,17,3,1}}}
T.glyphs[21709] = {w=18, advance=16, rects={{9,4,2,1},{9,5,1,1},{1,6,4,1},{6,6,9,1},{1,7,1,8},{4,7,1,8},{6,7,1,12},{13,7,2,2},{8,9,7,1},{8,10,2,4},{11,10,4,4},{8,14,7,1},{1,15,4,1},{8,15,2,1},{13,15,2,3},{1,16,1,1},{4,16,1,1},{11,18,3,1}}}
T.glyphs[21738] = {w=18, advance=16, rects={{5,5,5,1},{11,5,4,1},{1,6,3,1},{6,6,1,2},{8,6,2,2},{11,6,1,4},{14,6,1,1},{1,7,1,7},{3,7,1,1},{13,7,2,2},{3,8,7,1},{3,9,1,3},{6,9,1,3},{8,9,2,3},{13,9,1,1},{11,10,3,1},{11,11,1,5},{13,11,2,1},{3,12,7,1},{14,12,1,1},{3,13,1,1},{5,13,2,2},{8,13,2,4},{14,13,2,3},{1,14,3,1},{1,15,1,1},{5,15,1,1},{4,16,2,1},{11,16,4,1},{3,17,2,1},{6,17,3,1},{11,17,1,2},{3,18,1,1}}}
T.glyphs[21807] = {w=18, advance=16, rects={{8,4,1,1},{10,4,2,1},{7,5,2,1},{11,5,1,2},{1,6,4,1},{7,6,1,1},{1,7,1,7},{4,7,1,2},{6,7,10,1},{6,8,2,1},{11,8,1,2},{4,9,4,1},{4,10,11,1},{4,11,1,3},{6,11,2,2},{11,11,1,2},{6,13,9,1},{1,14,4,1},{6,14,2,3},{11,14,1,3},{1,15,1,2},{4,15,1,1},{6,17,10,1},{6,18,2,1}}}
T.glyphs[21834] = {w=18, advance=16, rects={{5,5,11,1},{1,6,3,1},{5,6,1,3},{7,6,2,1},{13,6,2,2},{1,7,1,7},{3,7,1,7},{7,7,1,2},{9,8,6,1},{5,9,3,1},{9,9,2,2},{12,9,3,4},{5,10,1,4},{7,10,1,1},{7,11,4,1},{8,12,3,1},{7,13,8,1},{1,14,3,1},{5,14,3,1},{13,14,2,3},{1,15,1,1},{5,15,1,3},{11,17,3,1}}}
T.glyphs[21890] = {w=18, advance=16, rects={{6,4,9,1},{1,5,4,1},{6,5,1,2},{10,5,1,2},{13,5,2,2},{1,6,1,8},{4,6,1,6},{6,7,9,1},{6,8,1,2},{10,8,1,2},{13,8,2,2},{6,10,9,1},{4,12,12,1},{4,13,1,1},{6,13,2,3},{9,13,2,1},{1,14,4,1},{10,14,1,1},{13,14,2,1},{1,15,1,1},{4,15,1,1},{9,15,4,1},{6,16,4,1},{12,16,2,1},{6,17,2,1},{13,17,3,1}}}
T.glyphs[21912] = {w=18, advance=16, rects={{10,4,1,4},{6,5,1,3},{13,5,2,3},{1,6,4,1},{1,7,1,8},{4,7,1,3},{6,8,9,1},{4,10,12,1},{4,11,1,4},{9,11,1,1},{6,12,9,1},{6,13,1,5},{8,13,2,4},{11,13,1,4},{14,13,1,4},{1,15,4,1},{1,16,1,1},{4,16,1,1},{12,17,3,1}}}
T.glyphs[22068] = {w=18, advance=16, rects={{8,4,1,1},{11,4,1,1},{5,5,2,1},{8,5,4,1},{14,5,1,1},{1,6,6,1},{8,6,1,1},{11,6,3,1},{1,7,1,8},{3,7,7,1},{11,7,1,1},{14,7,2,1},{3,8,6,1},{11,8,4,1},{3,9,2,2},{7,9,2,1},{7,10,6,1},{3,11,4,1},{10,11,2,1},{3,12,12,1},{3,13,2,2},{6,13,1,1},{10,13,1,1},{14,13,1,1},{6,14,9,1},{1,15,4,1},{6,15,1,1},{10,15,1,1},{14,15,1,1},{1,16,1,1},{5,16,10,1},{5,17,2,1},{10,17,1,1},{13,17,2,1},{4,18,2,1},{10,18,4,1}}}
T.glyphs[22120] = {w=18, advance=16, rects={{1,5,6,1},{9,5,5,1},{1,6,2,1},{6,6,1,1},{9,6,1,1},{13,6,1,1},{1,7,6,1},{9,7,5,1},{1,8,2,1},{6,8,1,1},{9,8,1,1},{13,8,1,1},{7,9,1,1},{11,9,1,1},{1,10,15,1},{4,11,3,1},{8,11,4,1},{0,12,5,1},{10,12,5,1},{1,13,6,1},{9,13,5,1},{1,14,2,2},{6,14,1,2},{9,14,1,2},{13,14,1,2},{1,16,6,1},{9,16,5,1},{1,17,2,1},{6,17,1,1},{9,17,1,1},{13,17,1,1}}}
T.glyphs[22218] = {w=18, advance=16, rects={{7,4,2,1},{1,5,14,3},{2,8,2,2},{6,8,4,2},{12,8,2,2},{1,10,14,1},{5,11,1,1},{10,11,1,1},{2,12,12,1},{1,13,14,1},{5,14,2,1},{8,14,2,1},{12,14,2,1},{2,15,4,1},{9,15,4,1},{0,16,3,1},{4,16,5,1},{11,16,3,1},{4,17,3,1},{13,17,3,1}}}
T.glyphs[22235] = {w=18, advance=16, rects={{1,5,14,1},{1,6,2,8},{5,6,2,1},{9,6,2,7},{13,6,2,7},{6,7,1,3},{5,10,2,2},{5,12,1,1},{4,13,2,1},{10,13,5,1},{1,14,4,1},{13,14,2,3},{1,15,2,2},{1,17,14,1},{1,18,2,1},{13,18,2,1}}}
T.glyphs[22238] = {w=18, advance=16, rects={{1,5,14,1},{1,6,2,11},{13,6,2,11},{5,8,6,1},{5,9,1,4},{10,9,1,4},{5,13,6,1},{5,14,1,1},{10,14,1,1},{1,17,14,1},{1,18,2,1},{13,18,2,1}}}
T.glyphs[22240] = {w=18, advance=16, rects={{1,5,14,1},{1,6,2,3},{13,6,2,3},{7,7,2,2},{1,9,14,1},{1,10,2,5},{7,10,2,2},{13,10,2,7},{6,12,4,1},{5,13,2,1},{9,13,2,1},{4,14,2,1},{10,14,2,1},{1,15,4,1},{11,15,1,1},{1,16,2,1},{1,17,14,1},{1,18,2,1},{13,18,2,1}}}
T.glyphs[22256] = {w=18, advance=16, rects={{1,5,14,1},{1,6,2,3},{13,6,2,3},{7,7,2,2},{1,9,14,1},{1,10,2,3},{6,10,3,1},{13,10,2,7},{6,11,4,1},{5,12,1,1},{7,12,4,1},{1,13,4,1},{7,13,2,3},{10,13,2,1},{1,14,3,1},{11,14,1,1},{1,15,2,2},{1,17,14,1},{1,18,2,1},{13,18,2,1}}}
T.glyphs[22260] = {w=18, advance=16, rects={{1,5,14,1},{1,6,2,1},{13,6,2,1},{1,7,1,10},{14,7,1,10},{3,8,10,1},{7,9,1,1},{4,10,8,1},{7,11,1,1},{3,12,9,1},{7,13,1,4},{11,13,1,2},{9,15,3,1},{1,17,14,1},{1,18,2,1},{13,18,2,1}}}
T.glyphs[22266] = {w=18, advance=16, rects={{1,5,14,1},{1,6,2,1},{13,6,2,1},{1,7,1,10},{14,7,1,10},{3,8,10,1},{7,9,2,2},{5,11,6,1},{5,12,1,2},{10,12,1,2},{5,14,6,1},{5,15,1,1},{10,15,1,1},{1,17,14,1},{1,18,2,1},{13,18,2,1}}}
T.glyphs[22270] = {w=18, advance=16, rects={{1,5,14,1},{1,6,1,6},{6,6,1,1},{13,6,2,1},{5,7,7,1},{14,7,1,4},{4,8,2,1},{10,8,2,1},{3,9,1,1},{6,9,1,1},{9,9,2,1},{7,10,3,1},{5,11,10,1},{1,12,4,1},{11,12,4,1},{1,13,1,4},{6,13,4,1},{14,13,1,4},{9,14,1,1},{4,15,3,1},{5,16,6,1},{1,17,14,1},{1,18,1,1},{13,18,2,1}}}
T.glyphs[22278] = {w=18, advance=16, rects={{1,5,14,1},{1,6,1,11},{13,6,2,1},{4,7,8,1},{14,7,1,9},{4,8,2,1},{10,8,2,1},{4,9,8,1},{4,11,8,1},{4,12,1,2},{7,12,2,2},{11,12,1,2},{4,14,8,1},{3,15,3,1},{11,15,2,1},{13,16,2,1},{1,17,14,1},{1,18,1,1},{14,18,1,1}}}
T.glyphs[22280] = {w=18, advance=16, rects={{1,5,14,1},{1,6,1,3},{4,6,2,1},{7,6,2,1},{10,6,2,1},{14,6,1,3},{3,7,10,1},{6,8,2,1},{1,9,14,1},{1,10,1,3},{5,10,1,1},{10,10,1,1},{14,10,1,3},{4,11,8,1},{3,12,3,1},{9,12,1,1},{11,12,2,1},{1,13,3,1},{5,13,1,2},{7,13,3,1},{11,13,4,1},{1,14,1,3},{11,14,1,1},{14,14,1,3},{5,15,7,1},{1,17,14,1},{1,18,1,1},{14,18,1,1}}}
T.glyphs[22312] = {w=18, advance=16, rects={{6,4,1,1},{5,5,2,1},{0,6,16,1},{4,7,2,2},{9,8,2,3},{3,9,2,1},{3,10,1,1},{2,11,2,1},{5,11,10,1},{1,12,3,2},{9,12,2,5},{0,14,1,1},{3,14,1,3},{3,17,13,1},{3,18,1,1}}}
T.glyphs[22320] = {w=18, advance=16, rects={{2,4,2,4},{10,4,1,4},{6,6,2,3},{12,7,3,1},{0,8,5,1},{9,8,6,1},{2,9,2,5},{6,9,6,1},{14,9,1,1},{5,10,3,1},{10,10,1,2},{13,10,2,2},{6,11,2,3},{10,12,5,1},{10,13,1,3},{14,13,2,4},{2,14,6,1},{1,15,4,1},{6,15,2,2},{0,16,2,1},{7,17,8,1}}}
T.glyphs[22330] = {w=18, advance=16, rects={{2,4,2,4},{6,5,8,1},{11,6,3,1},{10,7,2,1},{0,8,6,1},{8,8,3,1},{2,9,2,4},{7,9,2,1},{6,10,9,1},{8,11,1,1},{11,11,1,2},{14,11,1,5},{7,12,2,1},{2,13,4,1},{7,13,1,1},{10,13,2,1},{1,14,4,1},{6,14,2,1},{10,14,1,1},{0,15,2,1},{5,15,2,1},{9,15,1,1},{4,16,1,1},{7,16,2,1},{13,16,2,1},{7,17,1,1},{10,17,4,1}}}
T.glyphs[22343] = {w=18, advance=16, rects={{2,4,2,4},{8,4,1,2},{7,6,8,1},{7,7,1,1},{14,7,1,5},{0,8,8,1},{2,9,2,5},{6,9,1,1},{8,9,1,1},{9,10,2,1},{10,11,1,1},{11,12,4,1},{5,13,1,1},{9,13,6,1},{2,14,4,1},{7,14,3,1},{13,14,2,3},{1,15,3,1},{6,15,2,1},{0,16,2,1},{9,17,5,1}}}
T.glyphs[22351] = {w=18, advance=16, rects={{2,4,2,4},{6,5,10,1},{10,6,1,1},{9,7,2,1},{0,8,6,1},{9,8,1,1},{2,9,2,4},{8,9,3,2},{12,9,1,1},{12,10,2,2},{7,11,2,1},{10,11,1,7},{5,12,3,1},{13,12,2,1},{2,13,5,1},{14,13,2,2},{1,14,3,1},{5,14,1,1},{0,15,2,1}}}
T.glyphs[22352] = {w=18, advance=16, rects={{7,4,2,7},{3,5,2,1},{12,5,1,2},{3,6,1,2},{11,7,2,2},{2,8,3,1},{2,9,1,1},{4,9,2,1},{10,9,4,1},{1,10,2,1},{5,10,1,2},{10,10,1,1},{13,10,2,1},{1,11,1,1},{7,11,3,1},{14,11,1,1},{0,12,2,1},{7,12,2,1},{2,13,12,1},{7,14,2,3},{0,17,16,1}}}
T.glyphs[22353] = {w=18, advance=16, rects={{2,4,2,4},{9,4,1,1},{9,5,2,1},{10,6,1,1},{6,7,9,1},{0,8,6,1},{2,9,2,4},{7,10,6,1},{7,11,2,2},{11,11,2,1},{12,12,1,5},{2,13,4,1},{7,13,1,2},{1,14,4,1},{0,15,2,1},{6,15,2,2},{14,15,2,2},{5,17,2,1},{12,17,3,1},{4,18,2,1}}}
T.glyphs[22359] = {w=18, advance=16, rects={{2,4,2,4},{9,4,1,3},{6,7,8,1},{0,8,6,1},{9,8,1,4},{13,8,1,4},{2,9,2,5},{5,12,11,1},{8,13,3,1},{1,14,5,1},{7,14,2,1},{10,14,1,1},{0,15,4,1},{6,15,2,1},{11,15,2,1},{5,16,2,1},{12,16,2,1},{4,17,2,1},{13,17,2,1}}}
T.glyphs[22368] = {w=18, advance=16, rects={{10,4,1,3},{1,5,6,1},{1,6,2,4},{5,6,2,1},{4,7,2,1},{9,7,3,2},{5,8,1,1},{5,9,2,1},{8,9,2,1},{11,9,2,1},{1,10,6,1},{8,10,1,1},{12,10,2,1},{1,11,2,2},{6,11,2,1},{13,11,2,1},{6,12,1,1},{14,12,1,1},{7,13,2,1},{2,14,12,1},{7,15,2,2},{0,17,16,1}}}
T.glyphs[22402] = {w=18, advance=16, rects={{9,4,5,1},{1,5,10,1},{7,6,2,2},{1,8,14,1},{3,9,2,2},{7,9,2,2},{11,9,2,2},{0,11,16,1},{3,12,2,2},{7,12,2,2},{11,12,2,2},{1,14,14,1},{7,15,2,2},{1,17,14,1}}}
T.glyphs[22411] = {w=18, advance=16, rects={{13,4,2,8},{1,5,8,1},{10,5,2,3},{3,6,1,2},{6,6,2,2},{0,8,12,1},{2,9,2,2},{6,9,2,4},{10,9,2,1},{1,11,2,1},{1,12,1,1},{11,12,3,1},{7,13,2,1},{2,14,12,1},{7,15,2,2},{0,17,16,1}}}
T.glyphs[22495] = {w=18, advance=16, rects={{2,4,1,4},{10,4,2,3},{13,4,1,1},{13,5,2,1},{5,7,11,1},{0,8,5,1},{10,8,2,1},{2,9,2,1},{5,9,7,1},{2,10,1,4},{5,10,2,2},{8,10,2,2},{11,10,1,3},{14,10,1,1},{13,11,2,1},{5,12,5,1},{13,12,1,1},{5,13,2,1},{8,13,2,1},{11,13,3,1},{2,14,3,1},{11,14,2,2},{1,15,4,1},{6,15,4,1},{14,15,2,2},{0,16,2,1},{4,16,4,1},{10,16,3,1},{9,17,2,1},{12,17,4,1},{8,18,2,1},{13,18,2,1}}}
T.glyphs[22522] = {w=18, advance=16, rects={{3,4,2,2},{11,4,2,2},{1,6,14,1},{3,7,2,1},{11,7,2,1},{3,8,10,1},{3,9,2,1},{11,9,2,1},{3,10,10,1},{3,11,2,1},{11,11,2,1},{0,12,16,1},{3,13,2,1},{10,13,3,1},{2,14,2,1},{12,14,2,1},{0,15,16,1},{7,16,2,1},{1,17,14,1}}}
T.glyphs[22534] = {w=18, advance=16, rects={{2,4,2,4},{8,4,1,1},{11,4,1,2},{7,5,2,2},{11,6,2,1},{6,7,10,1},{0,8,8,1},{11,8,1,2},{2,9,2,5},{5,9,3,1},{5,10,1,1},{7,10,8,1},{7,11,1,2},{11,11,1,2},{7,13,8,1},{2,14,4,1},{7,14,1,3},{11,14,1,3},{1,15,5,1},{0,16,3,1},{7,17,9,1},{7,18,1,1}}}
T.glyphs[22635] = {w=18, advance=16, rects={{2,4,2,4},{10,4,1,1},{5,5,11,1},{10,6,1,1},{6,7,8,1},{0,8,8,1},{13,8,1,1},{2,9,2,5},{6,9,8,1},{6,10,2,1},{13,10,1,1},{6,11,8,1},{6,12,2,1},{13,12,1,1},{6,13,8,1},{1,14,7,1},{13,14,1,1},{0,15,4,1},{5,15,11,1},{8,16,1,1},{11,16,2,1},{6,17,2,1},{13,17,2,1},{5,18,1,1},{14,18,2,1}}}
T.glyphs[22681] = {w=18, advance=16, rects={{2,4,2,3},{10,4,1,1},{5,5,10,1},{6,6,2,1},{10,6,1,3},{13,6,2,1},{0,7,5,1},{7,7,2,1},{12,7,2,1},{2,8,2,6},{5,9,11,1},{6,11,9,1},{6,12,1,2},{14,12,1,5},{8,13,5,1},{1,14,6,1},{8,14,1,1},{12,14,1,1},{0,15,3,1},{6,15,1,2},{8,15,5,1},{6,17,9,1},{6,18,1,1},{14,18,1,1}}}
T.glyphs[22686] = {w=18, advance=16, rects={{2,4,2,4},{7,4,1,1},{12,4,1,1},{8,5,1,1},{11,5,2,1},{5,6,10,1},{5,7,2,1},{10,7,1,3},{12,7,1,2},{14,7,1,3},{0,8,9,1},{2,9,2,5},{5,9,2,1},{8,9,1,1},{5,10,10,1},{5,11,2,1},{14,11,1,1},{6,13,9,1},{2,14,3,1},{6,14,1,1},{13,14,2,1},{1,15,4,1},{6,15,9,1},{0,16,2,1},{6,16,1,1},{13,16,2,1},{6,17,9,1},{6,18,1,1},{13,18,2,1}}}
T.glyphs[22721] = {w=18, advance=16, rects={{11,4,1,2},{2,5,6,1},{2,6,1,1},{6,6,9,1},{2,7,6,1},{9,7,1,1},{13,7,1,1},{1,8,2,2},{6,8,2,1},{9,8,2,1},{12,8,2,1},{8,9,8,1},{1,10,7,1},{11,10,1,1},{0,11,2,1},{3,11,1,1},{6,11,9,1},{0,12,1,1},{3,12,5,1},{11,12,1,2},{3,13,1,1},{6,13,2,1},{7,14,2,1},{2,15,12,1},{7,16,2,1},{0,17,16,1}}}
T.glyphs[22768] = {w=18, advance=16, rects={{7,4,2,1},{0,5,16,1},{7,6,2,2},{2,8,13,1},{2,10,12,1},{2,11,2,3},{7,11,2,3},{13,11,1,3},{2,14,12,1},{2,15,2,1},{13,15,1,1},{1,16,2,2},{0,18,2,1}}}
T.glyphs[22771] = {w=18, advance=16, rects={{7,4,2,2},{0,6,16,1},{7,7,2,1},{2,8,12,1},{1,10,14,1},{1,11,1,2},{14,11,1,2},{4,12,7,1},{4,13,2,2},{9,13,2,1},{10,14,1,3},{14,14,2,2},{4,15,1,1},{2,16,2,1},{14,16,1,1},{1,17,2,1},{10,17,5,1}}}
T.glyphs[22788] = {w=18, advance=16, rects={{3,5,1,1},{9,5,2,3},{2,6,2,1},{2,7,6,1},{2,8,1,1},{6,8,2,2},{9,8,3,1},{1,9,2,2},{9,9,5,1},{6,10,1,2},{9,10,2,5},{13,10,2,1},{0,11,4,1},{14,11,1,1},{0,12,1,1},{3,12,1,1},{5,12,2,1},{3,13,3,1},{4,14,2,1},{3,15,4,1},{10,15,1,1},{2,16,2,1},{6,16,4,1},{1,17,2,1},{8,17,8,1},{1,18,1,1}}}
T.glyphs[22791] = {w=18, advance=16, rects={{4,4,2,1},{4,5,1,1},{3,6,11,1},{2,7,4,1},{11,7,2,1},{1,8,2,1},{5,8,2,1},{9,8,3,1},{1,9,1,1},{6,9,4,1},{3,10,4,1},{9,10,4,1},{0,11,4,1},{12,11,4,1},{2,12,12,1},{2,13,2,1},{7,13,2,1},{12,13,2,1},{2,14,12,1},{2,15,2,2},{7,15,2,2},{12,15,2,2},{2,17,12,1},{2,18,2,1},{12,18,2,1}}}
T.glyphs[22797] = {w=18, advance=16, rects={{3,4,2,1},{3,5,13,1},{2,6,2,1},{1,7,13,1},{0,8,4,1},{13,8,1,1},{2,9,12,1},{2,10,2,1},{13,10,1,1},{2,11,12,1},{4,12,2,1},{4,13,10,1},{3,14,3,1},{11,14,2,1},{1,15,2,1},{6,15,5,1},{0,16,2,1},{4,16,9,1},{1,17,4,1},{11,17,5,1}}}
T.glyphs[22806] = {w=18, advance=16, rects={{3,5,2,1},{10,5,1,4},{3,6,1,1},{3,7,6,1},{2,8,2,1},{7,8,1,3},{2,9,1,1},{10,9,3,1},{1,10,2,1},{10,10,4,1},{0,11,2,1},{3,11,2,1},{6,11,2,1},{10,11,1,7},{13,11,2,1},{0,12,1,1},{4,12,3,1},{14,12,2,1},{5,13,2,1},{4,14,2,1},{3,15,2,1},{2,16,2,1},{1,17,2,1}}}
T.glyphs[22810] = {w=18, advance=16, rects={{6,4,2,1},{5,5,2,1},{4,6,10,1},{3,7,2,1},{11,7,3,1},{2,8,2,1},{5,8,1,1},{10,8,2,1},{1,9,2,1},{5,9,2,1},{8,9,3,1},{5,10,4,1},{2,11,4,1},{8,11,2,1},{1,12,2,1},{7,12,8,1},{5,13,3,1},{13,13,2,1},{3,14,3,1},{7,14,1,1},{11,14,2,1},{2,15,2,1},{7,15,5,1},{7,16,3,1},{3,17,5,1},{1,18,4,1}}}
T.glyphs[22815] = {w=18, advance=16, rects={{2,4,2,2},{10,4,2,1},{10,5,1,1},{2,6,5,1},{9,6,6,1},{1,7,2,1},{6,7,1,1},{8,7,2,1},{13,7,2,1},{0,8,2,1},{6,8,3,1},{10,8,1,1},{12,8,2,1},{0,9,5,1},{6,9,1,2},{10,9,3,1},{1,10,1,4},{4,10,1,4},{9,10,3,1},{6,11,3,1},{11,11,1,1},{6,12,1,3},{10,12,6,1},{9,13,2,1},{14,13,1,1},{1,14,4,1},{8,14,2,1},{13,14,2,1},{1,15,1,1},{6,15,3,1},{10,15,3,1},{6,16,1,1},{10,16,2,1},{5,17,2,1},{8,17,3,1},{3,18,3,1},{7,18,2,1}}}
T.glyphs[22823] = {w=18, advance=16, rects={{7,4,2,4},{0,8,16,1},{7,9,2,3},{6,12,4,1},{6,13,1,1},{9,13,1,1},{5,14,2,1},{9,14,2,1},{4,15,2,1},{10,15,2,1},{3,16,2,1},{11,16,2,1},{1,17,3,1},{12,17,3,1},{1,18,1,1},{14,18,1,1}}}
T.glyphs[22825] = {w=18, advance=16, rects={{1,5,14,1},{7,6,2,4},{0,10,16,1},{7,11,2,1},{6,12,3,1},{6,13,2,1},{9,13,1,1},{5,14,2,1},{9,14,2,1},{4,15,2,1},{10,15,2,1},{3,16,2,1},{11,16,2,1},{1,17,3,1},{12,17,3,1},{1,18,1,1},{14,18,1,1}}}
T.glyphs[22826] = {w=18, advance=16, rects={{7,4,2,4},{0,8,16,1},{7,9,2,2},{6,11,4,1},{6,12,1,1},{9,12,1,1},{5,13,2,1},{9,13,2,1},{5,14,1,1},{10,14,1,1},{4,15,4,1},{10,15,2,1},{3,16,2,1},{7,16,2,1},{11,16,2,1},{1,17,3,1},{8,17,1,1},{12,17,3,1},{1,18,1,1},{14,18,1,1}}}
T.glyphs[22830] = {w=18, advance=16, rects={{7,4,2,3},{2,7,12,1},{2,8,2,4},{7,8,2,4},{12,8,2,4},{0,12,16,1},{7,13,2,1},{6,14,4,1},{5,15,2,1},{9,15,2,1},{4,16,2,1},{10,16,2,1},{2,17,3,1},{11,17,3,1},{1,18,2,1},{13,18,2,1}}}
T.glyphs[22833] = {w=18, advance=16, rects={{7,4,2,3},{3,5,2,1},{3,6,1,1},{2,7,13,1},{1,8,2,1},{7,8,2,3},{1,9,1,1},{0,11,16,1},{7,12,2,1},{6,13,4,1},{6,14,1,1},{9,14,1,1},{5,15,2,1},{10,15,1,1},{3,16,3,1},{11,16,2,1},{1,17,3,1},{12,17,3,1},{1,18,2,1},{14,18,1,1}}}
T.glyphs[22836] = {w=18, advance=16, rects={{3,4,1,1},{8,4,2,8},{3,5,3,1},{5,6,2,1},{1,7,2,1},{6,7,1,1},{2,8,2,1},{3,9,3,1},{4,10,2,1},{0,12,16,1},{7,13,2,1},{7,14,3,1},{6,15,2,1},{9,15,2,1},{4,16,3,1},{10,16,3,1},{2,17,3,1},{12,17,3,1},{1,18,2,1},{14,18,1,1}}}
T.glyphs[22841] = {w=18, advance=16, rects={{7,4,2,2},{1,6,14,1},{7,7,2,5},{2,8,2,1},{12,8,1,1},{3,9,2,1},{11,9,2,1},{4,10,1,1},{10,10,2,1},{0,12,16,1},{7,13,2,1},{6,14,4,1},{5,15,2,1},{9,15,2,1},{4,16,2,1},{10,16,2,1},{1,17,3,1},{11,17,4,1},{1,18,2,1},{13,18,2,1}}}
T.glyphs[22855] = {w=18, advance=16, rects={{7,4,2,1},{1,5,14,1},{6,6,3,1},{4,7,3,1},{8,7,5,1},{1,8,4,1},{11,8,3,1},{0,10,16,1},{12,11,1,6},{2,12,7,1},{2,13,2,3},{8,13,1,3},{2,16,7,1},{2,17,2,1},{11,17,2,1},{9,18,4,1}}}
T.glyphs[22865] = {w=18, advance=16, rects={{4,4,1,1},{8,4,7,1},{1,5,7,1},{10,5,1,3},{13,5,2,6},{4,6,1,2},{1,8,7,1},{9,8,2,1},{4,9,1,1},{9,9,1,1},{1,10,9,1},{4,11,1,2},{8,11,1,2},{10,11,4,1},{7,13,2,1},{1,14,14,1},{6,15,4,1},{5,16,2,1},{9,16,2,1},{1,17,5,1},{10,17,5,1},{1,18,2,1},{13,18,2,1}}}
T.glyphs[22871] = {w=18, advance=16, rects={{7,4,1,1},{6,5,2,1},{1,6,14,1},{4,7,2,1},{10,7,2,1},{2,8,12,1},{0,9,2,1},{3,9,2,1},{14,9,2,1},{3,10,10,1},{3,11,2,1},{3,12,10,1},{3,13,2,1},{0,14,16,1},{4,15,2,1},{3,16,2,1},{11,16,2,1},{2,17,12,1},{13,18,1,1}}}
T.glyphs[22902] = {w=18, advance=16, rects={{2,4,2,3},{6,4,8,1},{8,5,2,1},{12,5,2,2},{8,6,1,7},{0,7,6,1},{12,7,1,1},{2,8,1,2},{5,8,1,3},{11,8,2,1},{11,9,4,1},{1,10,2,1},{14,10,1,5},{1,11,1,1},{4,11,2,1},{1,12,2,1},{4,12,1,1},{2,13,3,1},{7,13,2,1},{3,14,3,1},{7,14,1,1},{2,15,2,1},{5,15,3,1},{13,15,2,2},{1,16,2,1},{5,16,2,2},{0,17,2,1},{10,17,4,1}}}
T.glyphs[22909] = {w=18, advance=16, rects={{2,4,2,3},{7,5,8,1},{13,6,2,1},{0,7,6,1},{12,7,2,1},{2,8,1,2},{5,8,1,3},{11,8,2,1},{10,9,2,2},{1,10,2,2},{4,11,12,1},{1,12,1,1},{4,12,2,1},{10,12,2,6},{2,13,3,1},{3,14,2,1},{3,15,3,1},{2,16,1,1},{5,16,2,1},{1,17,2,1},{0,18,2,1},{8,18,3,1}}}
T.glyphs[22914] = {w=18, advance=16, rects={{3,4,1,2},{2,6,2,1},{8,6,7,1},{0,7,7,1},{8,7,2,9},{13,7,2,9},{2,8,2,1},{6,8,1,2},{2,9,1,1},{1,10,2,3},{5,10,2,3},{2,13,2,1},{5,13,1,1},{3,14,3,2},{2,16,2,1},{5,16,2,1},{8,16,7,1},{1,17,2,1},{6,17,4,1},{13,17,2,2},{0,18,2,1},{8,18,2,1}}}
T.glyphs[22987] = {w=18, advance=16, rects={{2,4,2,3},{9,4,2,2},{9,6,1,1},{12,6,2,2},{0,7,6,1},{8,7,2,1},{2,8,1,1},{5,8,1,2},{8,8,1,1},{13,8,2,1},{1,9,2,2},{7,9,8,1},{5,10,6,1},{14,10,2,1},{1,11,1,1},{4,11,2,2},{1,12,2,1},{7,12,8,1},{2,13,3,1},{7,13,1,3},{13,13,2,3},{3,14,2,1},{2,15,4,1},{1,16,2,1},{5,16,1,1},{7,16,8,1},{0,17,2,1},{7,17,1,1},{13,17,2,1}}}
T.glyphs[23039] = {w=18, advance=16, rects={{1,4,2,1},{7,4,1,1},{3,5,1,1},{6,5,9,1},{5,6,2,1},{9,6,2,2},{13,6,2,1},{4,7,2,1},{13,7,1,1},{3,8,2,1},{8,8,4,1},{1,9,2,1},{6,9,3,1},{11,9,3,1},{1,10,1,1},{5,10,2,1},{13,10,2,1},{6,11,1,1},{0,12,16,1},{4,13,2,1},{11,13,1,1},{3,14,3,1},{10,14,2,1},{5,15,6,1},{4,16,9,1},{1,17,5,1},{12,17,3,1}}}
T.glyphs[23041] = {w=18, advance=16, rects={{10,4,1,2},{12,4,2,1},{13,5,1,1},{2,6,14,1},{2,7,1,1},{10,7,1,3},{2,8,7,1},{2,9,1,2},{5,9,2,2},{14,9,1,1},{10,10,2,2},{13,10,2,1},{2,11,7,1},{13,11,1,1},{2,12,1,2},{4,12,2,2},{8,12,1,1},{10,12,4,1},{7,13,2,1},{11,13,2,3},{1,14,2,2},{4,14,4,1},{6,15,2,1},{14,15,2,2},{1,16,1,1},{5,16,4,1},{10,16,3,1},{0,17,2,1},{4,17,2,1},{9,17,2,1},{12,17,3,1},{0,18,1,1},{3,18,2,1},{8,18,2,1},{13,18,2,1}}}
T.glyphs[23376] = {w=18, advance=16, rects={{2,5,12,1},{11,6,3,1},{10,7,2,1},{8,8,2,1},{7,9,2,2},{0,11,16,1},{7,12,2,5},{4,17,5,1}}}
T.glyphs[23380] = {w=18, advance=16, rects={{10,4,1,13},{1,5,7,1},{6,6,2,1},{5,7,2,1},{4,8,3,1},{4,9,2,1},{4,10,5,1},{1,11,6,1},{0,12,3,1},{4,12,1,5},{14,13,2,4},{1,17,4,1},{10,17,5,1}}}
T.glyphs[23383] = {w=18, advance=16, rects={{7,4,1,1},{7,5,2,1},{1,6,14,1},{1,7,1,2},{14,7,1,2},{3,9,10,1},{10,10,2,1},{8,11,3,1},{0,12,16,1},{7,13,2,1},{8,14,1,2},{7,16,2,1},{4,17,5,1}}}
T.glyphs[23384] = {w=18, advance=16, rects={{5,4,2,1},{5,5,1,1},{0,6,16,1},{4,7,2,1},{4,8,1,1},{3,9,2,1},{6,9,9,1},{2,10,2,2},{11,10,3,1},{10,11,1,2},{1,12,3,1},{0,13,2,1},{3,13,13,1},{3,14,1,4},{10,14,1,3},{7,17,4,1}}}
T.glyphs[23425] = {w=18, advance=16, rects={{7,4,2,2},{1,6,14,1},{1,7,2,1},{13,7,2,1},{1,8,1,1},{14,8,1,1},{0,10,16,1},{7,11,2,1},{8,12,1,4},{7,16,2,1},{4,17,5,1},{4,18,3,1}}}
T.glyphs[23427] = {w=18, advance=16, rects={{7,4,1,1},{7,5,2,1},{1,6,14,1},{1,7,1,2},{14,7,1,2},{3,9,2,4},{12,10,2,1},{9,11,4,1},{6,12,4,1},{3,13,5,1},{3,14,2,3},{14,14,1,1},{13,15,2,2},{3,17,11,1}}}
T.glyphs[23432] = {w=18, advance=16, rects={{7,4,1,1},{7,5,2,1},{1,6,14,1},{1,7,2,2},{13,7,2,2},{10,8,2,2},{0,10,16,1},{10,11,2,6},{3,12,1,1},{3,13,2,1},{4,14,2,1},{5,15,1,1},{7,17,4,1}}}
T.glyphs[23433] = {w=18, advance=16, rects={{7,4,1,1},{7,5,2,1},{1,6,14,1},{1,7,2,1},{14,7,1,2},{1,8,1,1},{6,8,2,1},{5,9,2,1},{0,10,16,1},{4,11,2,1},{11,11,2,1},{3,12,2,1},{10,12,2,1},{3,13,3,1},{10,13,1,1},{5,14,3,1},{9,14,2,1},{7,15,3,1},{5,16,7,1},{2,17,5,1},{11,17,3,1},{1,18,3,1},{13,18,1,1}}}
T.glyphs[23436] = {w=18, advance=16, rects={{7,4,1,1},{7,5,2,1},{1,6,14,1},{1,7,1,1},{14,7,1,1},{2,9,12,1},{1,12,15,1},{5,13,1,2},{9,13,2,1},{9,14,1,2},{4,15,2,1},{14,15,2,2},{3,16,2,1},{9,16,2,1},{2,17,2,1},{9,17,6,1},{1,18,2,1}}}
T.glyphs[23448] = {w=18, advance=16, rects={{7,4,2,1},{8,5,1,1},{1,6,14,1},{1,7,1,1},{14,7,1,1},{3,8,10,1},{3,9,1,2},{12,9,1,2},{3,11,10,1},{3,12,1,2},{12,12,1,1},{3,14,11,1},{3,15,1,2},{12,15,2,2},{3,17,11,1},{3,18,1,1},{12,18,2,1}}}
T.glyphs[23450] = {w=18, advance=16, rects={{7,4,2,2},{1,6,14,1},{1,7,2,1},{13,7,2,1},{14,8,1,1},{0,9,16,1},{7,10,2,1},{3,11,1,3},{8,11,1,2},{8,13,7,1},{2,14,2,1},{8,14,1,2},{2,15,3,1},{1,16,2,1},{4,16,5,1},{1,17,1,1},{5,17,11,1},{0,18,2,1}}}
T.glyphs[23454] = {w=18, advance=16, rects={{7,4,2,2},{1,6,14,1},{1,7,1,2},{14,7,1,2},{4,8,1,1},{9,8,1,3},{4,9,3,1},{2,10,2,1},{6,10,1,1},{3,11,2,1},{8,11,2,2},{5,12,1,1},{0,13,16,1},{7,14,2,1},{6,15,5,1},{5,16,2,1},{10,16,3,1},{2,17,4,1},{12,17,3,1},{1,18,2,1},{14,18,1,1}}}
T.glyphs[23457] = {w=18, advance=16, rects={{7,4,1,1},{7,5,2,1},{1,6,14,1},{1,7,1,1},{14,7,1,1},{2,9,12,1},{2,10,2,2},{7,10,2,2},{12,10,2,2},{2,12,12,1},{2,13,2,2},{7,13,2,2},{12,13,2,2},{2,15,12,1},{2,16,2,1},{7,16,2,3},{12,16,2,1}}}
T.glyphs[23458] = {w=18, advance=16, rects={{7,4,1,1},{7,5,2,1},{1,6,14,1},{1,7,1,1},{5,7,1,1},{14,7,1,1},{4,8,9,1},{3,9,3,1},{11,9,2,1},{2,10,2,1},{5,10,2,1},{9,10,2,1},{1,11,2,1},{6,11,4,1},{5,12,3,1},{9,12,3,1},{2,13,4,1},{11,13,5,1},{0,14,13,1},{3,15,1,2},{12,15,1,2},{3,17,10,1},{3,18,1,1},{12,18,1,1}}}
T.glyphs[23475] = {w=18, advance=16, rects={{7,4,1,1},{7,5,2,1},{1,6,14,1},{1,7,1,1},{7,7,2,1},{14,7,1,1},{2,8,12,1},{7,9,2,1},{2,10,12,1},{7,11,2,1},{1,12,14,1},{7,13,2,1},{3,14,10,1},{3,15,1,2},{12,15,1,2},{3,17,10,1},{3,18,1,1},{12,18,1,1}}}
T.glyphs[23478] = {w=18, advance=16, rects={{7,4,1,1},{7,5,2,1},{1,6,14,1},{1,7,1,1},{14,7,1,1},{2,8,12,1},{5,9,3,1},{3,10,5,1},{1,11,3,1},{6,11,2,1},{12,11,2,1},{5,12,4,1},{10,12,3,1},{2,13,3,1},{8,13,4,1},{1,14,2,1},{7,14,3,1},{11,14,2,1},{5,15,2,1},{8,15,2,2},{12,15,3,1},{2,16,4,1},{14,16,1,1},{1,17,2,1},{5,17,4,1}}}
T.glyphs[23481] = {w=18, advance=16, rects={{7,4,1,1},{7,5,2,1},{1,6,14,1},{1,7,1,2},{14,7,1,2},{5,8,1,1},{10,8,1,1},{2,9,3,1},{7,9,2,1},{11,9,3,1},{1,10,2,1},{5,10,5,1},{13,10,2,1},{4,11,2,1},{9,11,3,1},{1,12,4,1},{11,12,4,1},{0,13,15,1},{3,14,1,3},{12,14,1,3},{3,17,10,1},{3,18,1,1},{12,18,1,1}}}
T.glyphs[23485] = {w=18, advance=16, rects={{7,4,1,1},{7,5,2,1},{1,6,14,1},{1,7,1,1},{14,7,1,1},{5,8,1,1},{10,8,1,1},{0,9,16,1},{5,10,1,1},{10,10,1,1},{2,11,11,1},{2,12,2,3},{12,12,1,4},{7,13,1,1},{7,14,2,1},{14,14,2,3},{6,15,3,1},{3,16,3,1},{8,16,2,1},{1,17,3,1},{8,17,7,1}}}
T.glyphs[23487] = {w=18, advance=16, rects={{7,4,2,2},{1,6,14,1},{1,7,1,2},{4,7,1,1},{13,7,2,1},{3,8,12,1},{3,9,1,1},{9,9,2,2},{2,10,2,2},{6,11,8,1},{1,12,3,2},{6,12,1,2},{13,12,1,2},{0,14,4,1},{6,14,8,1},{2,15,2,4},{6,15,1,2},{13,15,1,2},{6,17,8,1},{6,18,1,1},{13,18,1,1}}}
T.glyphs[23492] = {w=18, advance=16, rects={{7,4,1,1},{7,5,2,1},{1,6,14,1},{1,7,1,1},{7,7,2,1},{14,7,1,1},{3,8,10,1},{6,9,4,1},{2,10,5,1},{9,10,4,1},{2,11,1,1},{12,11,2,1},{0,12,16,1},{12,13,1,5},{2,14,7,1},{2,15,2,2},{8,15,1,2},{2,17,7,1},{2,18,2,1},{9,18,4,1}}}
T.glyphs[23544] = {w=18, advance=16, rects={{10,4,2,3},{0,7,16,1},{10,8,2,9},{3,9,1,1},{3,10,2,1},{4,11,2,1},{4,12,3,1},{5,13,2,1},{5,17,7,1}}}
T.glyphs[23545] = {w=18, advance=16, rects={{13,4,1,4},{0,6,7,1},{5,7,2,1},{1,8,1,1},{5,8,11,1},{1,9,2,1},{5,9,1,2},{12,9,2,1},{2,10,2,1},{8,10,1,1},{13,10,1,6},{3,11,3,1},{8,11,2,1},{3,12,2,1},{9,12,2,2},{3,13,3,1},{3,14,4,1},{2,15,2,1},{5,15,2,1},{1,16,2,1},{6,16,1,1},{12,16,2,1},{0,17,2,1},{9,17,5,1}}}
T.glyphs[23547] = {w=18, advance=16, rects={{2,5,12,1},{13,6,1,1},{2,7,12,1},{13,8,1,2},{2,10,12,1},{13,11,1,1},{11,12,2,1},{0,13,16,1},{11,14,2,3},{3,15,2,1},{5,16,1,1},{8,17,4,1}}}
T.glyphs[23548] = {w=18, advance=16, rects={{2,5,11,1},{2,6,1,2},{12,6,1,2},{2,8,11,1},{14,8,1,1},{2,9,1,1},{12,9,1,1},{14,9,2,1},{2,10,2,1},{14,10,1,1},{2,11,13,1},{11,12,2,1},{0,13,16,1},{11,14,2,3},{3,15,2,1},{5,16,1,1},{8,17,4,1}}}
T.glyphs[23556] = {w=18, advance=16, rects={{3,4,2,2},{13,4,1,3},{1,6,6,1},{1,7,2,1},{6,7,10,1},{1,8,6,1},{12,8,2,1},{1,9,2,1},{6,9,1,1},{13,9,1,7},{1,10,6,1},{8,10,2,1},{1,11,2,2},{6,11,1,2},{9,11,1,1},{9,12,2,1},{0,13,7,1},{10,13,1,1},{4,14,3,1},{3,15,2,1},{6,15,1,2},{1,16,2,1},{12,16,2,1},{0,17,2,1},{4,17,3,1},{9,17,5,1}}}
T.glyphs[23558] = {w=18, advance=16, rects={{3,4,1,8},{8,4,2,1},{8,5,1,1},{7,6,8,1},{0,7,2,1},{6,7,2,1},{13,7,2,1},{1,8,1,1},{5,8,1,1},{8,8,2,1},{11,8,2,1},{8,9,3,1},{5,10,3,1},{12,10,2,2},{2,12,2,1},{5,12,11,1},{1,13,3,1},{7,13,1,1},{12,13,2,5},{0,14,2,1},{3,14,1,5},{7,14,2,1},{0,15,1,1},{8,15,1,2},{9,18,4,1}}}
T.glyphs[23567] = {w=18, advance=16, rects={{7,4,2,14},{3,8,2,2},{11,8,1,1},{11,9,2,1},{3,10,1,1},{12,10,1,1},{2,11,2,1},{12,11,2,1},{2,12,1,1},{13,12,1,1},{1,13,2,1},{13,13,2,1},{1,14,1,2},{14,14,1,1},{14,15,2,1},{4,18,5,1}}}
T.glyphs[23569] = {w=18, advance=16, rects={{7,4,2,9},{4,6,1,1},{11,6,1,1},{3,7,2,1},{11,7,2,1},{3,8,1,1},{12,8,2,1},{2,9,2,1},{13,9,2,1},{2,10,1,1},{12,10,1,1},{14,10,1,1},{1,11,2,1},{11,11,2,1},{1,12,1,1},{10,12,2,1},{9,13,2,1},{7,14,3,1},{5,15,3,1},{2,16,4,1},{1,17,3,1}}}
T.glyphs[23572] = {w=18, advance=16, rects={{4,4,2,2},{3,6,13,1},{3,7,1,1},{13,7,2,2},{2,8,2,1},{7,8,2,9},{1,9,2,1},{13,9,1,1},{1,10,1,1},{4,10,1,1},{11,10,1,1},{3,11,2,1},{11,11,2,1},{3,12,1,1},{12,12,1,1},{2,13,2,1},{12,13,2,1},{1,14,2,1},{13,14,2,2},{1,15,1,1},{14,16,1,1},{4,17,5,1}}}
T.glyphs[23574] = {w=18, advance=16, rects={{7,4,2,6},{4,6,1,1},{11,6,1,1},{3,7,2,1},{11,7,3,1},{1,8,3,1},{13,8,2,1},{1,9,1,1},{14,9,1,1},{7,11,2,1},{1,12,14,1},{7,13,3,1},{6,14,2,1},{9,14,1,1},{5,15,2,1},{10,15,2,1},{2,16,3,1},{11,16,3,1},{0,17,3,1},{13,17,2,1}}}
T.glyphs[23601] = {w=18, advance=16, rects={{3,4,2,1},{10,4,1,4},{4,5,1,1},{12,5,2,1},{0,6,9,1},{13,6,2,1},{1,8,14,1},{1,9,2,2},{6,9,2,2},{9,9,4,3},{1,11,7,1},{4,12,1,5},{9,12,1,2},{11,12,2,5},{2,13,1,1},{6,13,1,1},{1,14,2,1},{6,14,4,1},{14,14,2,3},{1,15,1,1},{7,15,3,1},{0,16,2,1},{7,16,2,1},{2,17,3,1},{7,17,1,1},{12,17,3,1},{6,18,2,1}}}
T.glyphs[23610] = {w=18, advance=16, rects={{2,5,12,1},{2,6,2,4},{12,6,2,4},{2,10,12,1},{2,11,2,4},{7,11,2,2},{12,11,2,1},{8,13,1,1},{8,14,2,1},{2,15,1,1},{9,15,2,1},{1,16,2,1},{10,16,3,1},{1,17,1,1},{12,17,3,1},{0,18,2,1},{13,18,2,1}}}
T.glyphs[23614] = {w=18, advance=16, rects={{2,5,13,1},{2,6,1,1},{13,6,2,1},{2,7,13,1},{2,8,1,4},{13,8,2,1},{9,9,6,1},{4,10,8,1},{7,11,2,1},{2,12,12,1},{2,13,1,1},{7,13,3,1},{1,14,14,1},{1,15,2,1},{8,15,1,2},{14,15,2,1},{1,16,1,1},{14,16,1,1},{0,17,2,1},{8,17,7,1},{0,18,1,1}}}
T.glyphs[23616] = {w=18, advance=16, rects={{2,5,12,1},{2,6,1,1},{13,6,1,1},{2,7,12,1},{2,8,1,2},{13,8,1,1},{2,10,13,1},{2,11,1,3},{13,11,2,6},{5,12,7,1},{5,13,1,2},{10,13,2,2},{1,14,2,2},{5,15,7,1},{1,16,1,1},{5,16,1,1},{0,17,2,1},{9,17,5,1}}}
T.glyphs[23618] = {w=18, advance=16, rects={{2,5,13,1},{2,6,1,2},{14,6,1,2},{2,8,13,1},{2,9,1,5},{14,9,1,1},{4,11,10,1},{2,14,14,1},{1,15,2,1},{6,15,3,1},{11,15,1,1},{1,16,1,1},{5,16,2,1},{11,16,2,1},{0,17,2,1},{4,17,11,1},{0,18,1,1},{14,18,1,1}}}
T.glyphs[23621] = {w=18, advance=16, rects={{2,5,12,1},{2,6,1,2},{13,6,1,2},{2,8,12,1},{2,9,1,2},{13,9,1,1},{8,10,2,1},{2,11,14,1},{2,12,1,3},{8,12,2,2},{4,14,10,1},{1,15,2,2},{4,15,2,2},{13,15,1,2},{0,17,2,2},{4,17,10,1},{4,18,2,1},{13,18,1,1}}}
T.glyphs[23631] = {w=18, advance=16, rects={{2,5,13,1},{2,6,1,2},{14,6,1,2},{2,8,13,1},{2,9,1,5},{6,9,2,1},{11,9,2,1},{7,10,1,1},{10,10,2,1},{4,11,11,1},{6,12,2,2},{11,12,1,2},{1,14,15,1},{1,15,2,1},{6,15,1,1},{11,15,1,3},{0,16,2,2},{5,16,2,1},{4,17,2,1}}}
T.glyphs[23637] = {w=18, advance=16, rects={{2,5,13,1},{2,6,1,1},{13,6,2,1},{2,7,13,1},{2,8,1,2},{13,8,2,1},{6,9,2,1},{10,9,2,1},{2,10,13,1},{2,11,1,2},{6,11,2,2},{10,11,2,2},{2,13,14,1},{2,14,1,1},{5,14,1,3},{8,14,1,1},{1,15,2,2},{9,15,1,1},{11,15,3,1},{9,16,3,1},{1,17,1,2},{5,17,4,1},{11,17,3,1},{5,18,2,1},{13,18,2,1}}}
T.glyphs[23646] = {w=18, advance=16, rects={{2,4,13,1},{2,5,1,1},{14,5,1,1},{2,6,13,1},{2,7,1,8},{4,8,11,1},{9,9,1,1},{5,10,9,1},{5,11,1,1},{9,11,1,1},{13,11,1,1},{5,12,9,1},{9,13,1,1},{4,14,11,1},{1,15,2,1},{4,15,1,4},{9,15,1,1},{11,15,2,1},{14,15,1,3},{1,16,1,1},{6,16,7,1},{0,17,2,1},{12,17,1,1},{0,18,1,1},{11,18,4,1}}}
T.glyphs[23792] = {w=18, advance=16, rects={{3,4,1,12},{9,4,1,1},{8,5,6,1},{1,6,1,10},{5,6,1,1},{7,6,2,1},{13,6,1,1},{5,7,3,1},{9,7,1,1},{12,7,1,1},{5,8,1,2},{9,8,3,1},{8,9,7,1},{5,10,4,1},{13,10,3,1},{5,11,1,5},{10,11,2,1},{7,12,8,1},{10,13,2,1},{7,14,8,1},{10,15,2,1},{1,16,15,1},{5,17,1,1},{10,17,2,2}}}
T.glyphs[24037] = {w=18, advance=16, rects={{1,5,14,1},{7,6,2,11},{0,17,16,1}}}
T.glyphs[24038] = {w=18, advance=16, rects={{5,5,2,2},{1,7,15,1},{5,8,1,1},{4,9,2,2},{4,11,11,1},{3,12,2,1},{8,12,2,5},{3,13,1,1},{2,14,2,1},{1,15,2,1},{1,16,1,1},{0,17,2,1},{3,17,13,1}}}
T.glyphs[24046] = {w=18, advance=16, rects={{4,4,1,1},{11,4,1,1},{5,5,1,1},{10,5,2,1},{1,6,14,1},{6,7,2,1},{1,8,14,1},{6,9,1,1},{0,10,16,1},{4,11,2,1},{4,12,1,1},{3,13,11,1},{2,14,2,1},{8,14,2,3},{1,15,2,1},{0,16,2,1},{3,17,13,1}}}
T.glyphs[24049] = {w=18, advance=16, rects={{2,5,12,1},{13,6,1,4},{2,10,12,1},{2,11,2,1},{13,11,1,1},{2,12,1,4},{14,14,2,3},{2,16,2,1},{3,17,12,1}}}
T.glyphs[24050] = {w=18, advance=16, rects={{1,5,13,1},{12,6,2,4},{2,8,1,2},{2,10,12,1},{2,11,1,5},{12,11,2,1},{14,13,2,2},{14,15,1,1},{2,16,2,1},{13,16,2,1},{2,17,13,1}}}
T.glyphs[24067] = {w=18, advance=16, rects={{6,4,2,1},{6,5,1,1},{0,6,16,1},{4,7,2,2},{8,8,2,2},{3,9,2,1},{3,10,11,1},{2,11,3,1},{8,11,2,5},{13,11,1,5},{1,12,4,1},{0,13,2,1},{3,13,2,5},{8,16,6,1},{8,17,2,2}}}
T.glyphs[24102] = {w=18, advance=16, rects={{3,4,2,2},{7,4,2,2},{11,4,2,2},{0,6,16,1},{3,7,2,2},{7,7,2,2},{11,7,2,2},{1,10,14,1},{1,11,1,1},{14,11,1,1},{2,13,12,1},{2,14,2,4},{7,14,2,5},{12,14,2,3},{10,17,3,1}}}
T.glyphs[24103] = {w=18, advance=16, rects={{3,3,1,3},{10,3,2,2},{10,5,6,1},{1,6,5,1},{10,6,2,2},{1,7,1,8},{3,7,1,7},{5,7,1,7},{7,8,8,1},{7,9,2,7},{13,9,2,1},{10,10,2,4},{14,10,1,6},{3,14,3,1},{10,14,1,1},{3,15,1,4},{10,15,2,1},{9,16,4,1},{7,17,3,1},{13,17,2,1},{6,18,2,1},{14,18,1,1}}}
T.glyphs[24120] = {w=18, advance=16, rects={{3,4,1,1},{7,4,2,2},{12,4,2,1},{4,5,1,1},{11,5,2,1},{1,6,14,1},{1,7,1,2},{14,7,1,2},{3,8,10,1},{3,9,1,2},{12,9,1,2},{3,11,10,1},{3,12,1,1},{7,12,2,2},{12,12,1,1},{2,14,13,1},{2,15,1,3},{7,15,2,4},{13,15,2,1},{13,16,1,1},{10,17,4,1}}}
T.glyphs[24125] = {w=18, advance=16, rects={{3,4,1,3},{7,5,8,1},{7,6,1,1},{14,6,1,1},{1,7,5,1},{7,7,8,1},{1,8,1,8},{3,8,1,7},{5,8,1,7},{7,8,1,1},{14,8,1,1},{7,9,8,1},{7,11,8,1},{7,12,2,1},{13,12,2,1},{7,13,8,1},{7,14,2,1},{13,14,2,1},{3,15,3,1},{7,15,8,1},{3,16,1,3},{7,16,2,1},{13,16,2,1},{7,17,8,1},{7,18,2,1},{13,18,2,1}}}
T.glyphs[24133] = {w=18, advance=16, rects={{3,4,1,3},{6,5,10,1},{1,7,5,1},{7,7,8,1},{1,8,1,8},{3,8,1,7},{5,8,1,7},{7,8,2,1},{13,8,2,1},{7,9,8,1},{7,10,2,1},{13,10,2,1},{7,12,8,1},{7,13,1,1},{10,13,2,1},{14,13,1,1},{7,14,8,1},{3,15,3,1},{7,15,1,2},{10,15,2,2},{14,15,1,2},{3,16,1,3},{7,17,8,1},{7,18,1,1},{14,18,1,1}}}
T.glyphs[24149] = {w=18, advance=16, rects={{5,4,1,1},{10,4,1,1},{0,5,16,1},{5,6,1,1},{10,6,1,1},{2,7,12,1},{2,8,2,1},{12,8,2,1},{2,9,12,1},{2,10,2,1},{12,10,2,1},{2,11,12,1},{5,12,2,1},{1,13,14,1},{2,14,3,1},{7,14,2,1},{11,14,2,1},{0,15,15,1},{3,16,1,2},{7,16,2,3},{12,16,1,1},{14,16,2,1},{10,17,3,1}}}
T.glyphs[24178] = {w=18, advance=16, rects={{1,5,14,1},{7,6,2,5},{0,11,16,1},{7,12,2,7}}}
T.glyphs[24179] = {w=18, advance=16, rects={{1,5,14,1},{7,6,2,6},{2,7,2,1},{12,7,2,2},{3,8,2,2},{10,9,3,1},{4,10,2,1},{10,10,2,1},{0,12,16,1},{7,13,2,6}}}
T.glyphs[24180] = {w=18, advance=16, rects={{3,4,2,2},{3,6,12,1},{2,7,2,1},{8,7,2,3},{1,8,2,2},{1,10,1,1},{3,10,12,1},{3,11,1,3},{8,11,2,3},{0,14,16,1},{8,15,2,4}}}
T.glyphs[24182] = {w=18, advance=16, rects={{4,4,1,1},{11,4,1,1},{4,5,2,1},{10,5,2,1},{5,6,1,1},{10,6,1,1},{1,7,14,1},{4,8,2,4},{10,8,2,4},{0,12,16,1},{4,13,2,2},{10,13,2,6},{4,15,1,1},{3,16,2,1},{2,17,2,1},{1,18,2,1}}}
T.glyphs[24189] = {w=18, advance=16, rects={{7,4,2,4},{4,5,1,2},{10,5,2,1},{1,6,1,3},{10,6,1,2},{14,6,1,8},{3,7,2,1},{3,8,1,1},{5,8,6,1},{12,8,1,1},{1,9,3,1},{5,9,1,1},{7,9,3,1},{11,9,2,1},{1,10,5,1},{7,10,5,1},{1,11,1,3},{4,11,1,2},{7,11,2,2},{11,11,1,1},{10,12,1,1},{3,13,1,1},{5,13,6,1},{12,13,1,1},{1,14,14,1},{1,15,1,2},{6,15,3,1},{13,15,2,1},{7,16,2,1},{14,16,1,1},{1,17,14,1},{14,18,1,1}}}
T.glyphs[24207] = {w=18, advance=16, rects={{8,4,1,1},{8,5,2,1},{2,6,14,1},{2,7,1,5},{4,8,11,1},{11,9,3,1},{7,10,2,1},{10,10,2,1},{8,11,3,1},{2,12,14,1},{2,13,1,1},{9,13,2,1},{14,13,1,1},{1,14,2,2},{9,14,1,4},{13,14,2,1},{13,15,1,1},{1,16,1,1},{0,17,2,1},{0,18,1,1},{6,18,4,1}}}
T.glyphs[24211] = {w=18, advance=16, rects={{8,4,1,1},{8,5,2,1},{2,6,14,1},{2,7,1,7},{7,7,2,1},{7,8,1,1},{4,9,11,1},{5,10,2,1},{5,11,1,1},{4,12,11,1},{9,13,2,2},{1,14,2,1},{1,15,15,1},{1,16,1,1},{9,16,2,3},{0,17,2,1},{0,18,1,1}}}
T.glyphs[24212] = {w=18, advance=16, rects={{8,4,1,1},{8,5,2,1},{2,6,14,1},{2,7,2,1},{2,8,1,6},{8,8,1,2},{4,9,1,1},{13,9,1,1},{4,10,2,2},{8,10,2,3},{12,10,2,2},{5,12,1,1},{12,12,1,2},{5,13,2,3},{9,13,1,2},{1,14,2,2},{11,14,2,1},{11,15,1,1},{1,16,1,1},{10,16,2,1},{0,17,2,1},{3,17,13,1},{0,18,1,1}}}
T.glyphs[24213] = {w=18, advance=16, rects={{8,4,1,1},{2,5,14,1},{2,6,1,8},{12,7,3,1},{5,8,10,1},{5,9,1,3},{9,9,2,3},{5,12,11,1},{5,13,1,3},{10,13,1,2},{1,14,2,2},{8,15,1,1},{10,15,2,1},{14,15,2,2},{1,16,1,1},{5,16,4,1},{11,16,2,1},{0,17,2,2},{4,17,3,1},{8,17,2,1},{12,17,4,1},{5,18,1,1},{9,18,2,1},{13,18,2,1}}}
T.glyphs[24223] = {w=18, advance=16, rects={{8,4,1,1},{8,5,2,1},{2,6,14,1},{2,7,1,7},{4,8,2,1},{7,8,2,2},{12,8,2,1},{4,9,1,1},{4,10,12,1},{7,11,1,1},{6,12,8,1},{6,13,3,1},{12,13,2,1},{1,14,2,1},{5,14,2,1},{8,14,2,1},{11,14,2,1},{1,15,1,2},{4,15,2,1},{9,15,3,1},{4,16,1,1},{7,16,6,1},{0,17,1,1},{3,17,1,1},{5,17,3,1},{12,17,3,1}}}
T.glyphs[24230] = {w=18, advance=16, rects={{8,4,1,1},{8,5,2,1},{2,6,14,1},{2,7,1,2},{6,8,1,1},{11,8,2,1},{2,9,14,1},{2,10,1,4},{6,10,1,1},{11,10,2,1},{6,11,7,1},{4,13,10,1},{1,14,2,2},{6,14,1,1},{11,14,2,1},{7,15,5,1},{0,16,2,1},{5,16,8,1},{0,17,1,1},{3,17,3,1},{12,17,3,1}}}
T.glyphs[24231] = {w=18, advance=16, rects={{8,4,1,2},{1,6,14,1},{1,7,2,4},{8,7,2,4},{5,8,1,2},{12,8,1,2},{4,10,3,1},{11,10,3,1},{1,11,4,1},{6,11,6,1},{13,11,2,1},{1,12,3,1},{7,12,4,1},{14,12,1,1},{1,13,2,3},{8,13,2,1},{4,14,11,1},{8,15,2,2},{1,16,1,1},{0,17,2,1},{3,17,13,1},{1,18,1,1}}}
T.glyphs[24266] = {w=18, advance=16, rects={{8,4,1,1},{8,5,2,1},{2,6,14,1},{2,7,1,7},{6,7,1,2},{4,9,5,1},{10,9,5,1},{4,10,1,1},{8,10,1,1},{10,10,1,5},{13,10,2,1},{4,11,5,1},{13,11,1,1},{4,12,1,1},{8,12,1,1},{12,12,2,1},{4,13,5,1},{13,13,2,1},{1,14,2,2},{4,14,1,2},{8,14,1,1},{14,14,1,2},{7,15,1,1},{10,15,2,1},{1,16,1,2},{4,16,5,2},{10,16,5,1},{10,17,1,2},{0,18,2,1},{4,18,2,1}}}
T.glyphs[24310] = {w=18, advance=16, rects={{11,4,4,1},{0,5,14,1},{3,6,2,1},{10,6,2,3},{3,7,1,1},{2,8,2,1},{7,8,1,6},{1,9,2,1},{10,9,5,1},{1,10,5,1},{10,10,2,4},{4,11,1,2},{1,12,1,2},{3,13,2,1},{1,14,4,1},{7,14,8,1},{2,15,2,1},{2,16,5,1},{1,17,2,1},{5,17,11,1},{1,18,1,1}}}
T.glyphs[24314] = {w=18, advance=16, rects={{9,4,1,1},{0,5,5,1},{6,5,8,1},{3,6,2,1},{9,6,1,1},{13,6,1,1},{2,7,2,1},{5,7,11,1},{2,8,1,1},{9,8,1,1},{13,8,1,1},{1,9,2,1},{6,9,8,1},{1,10,4,1},{9,10,1,2},{13,10,1,1},{4,11,1,1},{1,12,1,2},{3,12,2,2},{6,12,8,1},{9,13,1,1},{1,14,3,1},{5,14,10,1},{2,15,2,1},{9,15,1,1},{1,16,5,1},{9,16,2,1},{0,17,2,1},{4,17,12,1}}}
T.glyphs[24320] = {w=18, advance=16, rects={{1,5,14,1},{4,6,2,5},{10,6,2,5},{0,11,16,1},{4,12,2,3},{10,12,2,7},{4,15,1,1},{3,16,2,1},{1,17,3,1},{1,18,1,1}}}
T.glyphs[24322] = {w=18, advance=16, rects={{2,5,11,1},{2,6,1,2},{12,6,1,2},{2,8,11,1},{2,9,1,1},{12,9,1,1},{14,9,1,2},{2,10,2,1},{2,11,13,1},{0,14,16,1},{4,15,1,1},{10,15,2,1},{3,16,2,1},{11,16,1,3},{2,17,2,1},{1,18,2,1}}}
T.glyphs[24323] = {w=18, advance=16, rects={{7,4,1,1},{7,5,2,1},{0,6,16,1},{5,7,2,1},{4,8,2,1},{10,8,1,1},{2,9,3,1},{11,9,2,1},{2,10,12,1},{13,11,1,1},{4,12,2,2},{10,12,2,2},{0,14,16,1},{4,15,2,1},{10,15,2,4},{3,16,2,1},{2,17,2,1},{1,18,2,1}}}
T.glyphs[24335] = {w=18, advance=16, rects={{9,4,1,3},{12,4,1,1},{13,5,1,1},{0,7,16,1},{9,8,2,1},{9,9,1,1},{1,10,7,1},{9,10,2,4},{4,11,1,4},{10,14,1,1},{4,15,5,1},{10,15,2,2},{14,15,2,2},{1,16,6,1},{0,17,3,1},{11,17,4,1},{12,18,3,1}}}
T.glyphs[24341] = {w=18, advance=16, rects={{13,4,1,15},{1,5,8,1},{7,6,2,1},{8,7,1,1},{2,8,7,1},{2,9,1,2},{7,9,2,1},{1,11,2,1},{1,12,8,1},{7,13,2,1},{8,14,1,1},{7,15,2,2},{3,17,5,1}}}
T.glyphs[24351] = {w=18, advance=16, rects={{4,4,1,1},{11,4,1,1},{4,5,2,1},{10,5,2,1},{5,6,1,1},{9,6,2,1},{1,7,14,1},{7,8,2,2},{13,8,2,2},{2,10,13,1},{1,11,2,2},{7,11,2,2},{13,11,2,1},{1,13,14,1},{5,14,4,1},{14,14,1,2},{4,15,2,1},{7,15,2,4},{3,16,2,1},{13,16,2,1},{1,17,3,1},{10,17,5,1},{0,18,2,1}}}
T.glyphs[24352] = {w=18, advance=16, rects={{7,4,2,4},{13,4,2,1},{1,5,5,1},{12,5,2,1},{4,6,2,2},{11,6,2,1},{10,7,2,1},{1,8,5,1},{7,8,4,1},{1,9,1,3},{7,9,2,1},{5,10,11,1},{7,11,2,5},{10,11,2,2},{1,12,5,1},{4,13,2,2},{11,13,1,1},{11,14,2,1},{4,15,1,2},{10,15,1,1},{12,15,2,1},{7,16,4,1},{13,16,2,1},{1,17,4,1},{7,17,3,1},{14,17,1,1},{7,18,1,1}}}
T.glyphs[24358] = {w=18, advance=16, rects={{10,4,1,1},{0,5,6,1},{10,5,2,1},{4,6,12,1},{4,7,2,1},{9,7,2,1},{1,8,5,1},{8,8,2,1},{1,9,1,3},{4,9,2,1},{8,9,1,1},{12,9,2,1},{7,10,1,1},{11,10,2,1},{6,11,6,1},{0,12,6,1},{10,12,2,1},{4,13,2,1},{9,13,2,1},{12,13,1,1},{4,14,1,3},{8,14,2,1},{13,14,1,2},{7,15,2,1},{6,16,9,1},{1,17,4,1},{14,17,1,1},{14,18,2,1}}}
T.glyphs[24359] = {w=18, advance=16, rects={{12,4,3,1},{0,5,6,1},{7,5,7,1},{4,6,2,2},{7,6,1,6},{9,6,2,8},{12,6,2,4},{1,8,5,1},{1,9,1,3},{4,9,2,1},{13,10,1,4},{0,12,5,1},{6,12,2,3},{4,13,1,3},{9,14,3,1},{13,14,2,1},{6,15,1,2},{9,15,4,2},{14,15,1,1},{3,16,2,1},{14,16,2,2},{1,17,3,1},{5,17,2,1},{9,17,2,1},{12,17,1,1}}}
T.glyphs[24369] = {w=18, advance=16, rects={{1,5,6,1},{8,5,7,1},{6,6,1,2},{13,6,2,2},{1,8,6,1},{9,8,6,1},{1,9,2,1},{6,9,1,1},{9,9,1,1},{13,9,2,1},{1,10,1,1},{8,10,2,1},{1,11,6,1},{8,11,7,1},{2,12,1,1},{6,12,1,4},{9,12,1,1},{14,12,1,4},{2,13,2,1},{9,13,3,1},{4,14,1,1},{9,14,4,1},{1,15,4,1},{8,15,5,1},{0,16,3,1},{5,16,2,1},{13,16,2,1},{2,17,4,1},{10,17,4,1}}}
T.glyphs[24377] = {w=18, advance=16, rects={{8,4,1,2},{12,4,2,2},{0,5,5,1},{4,6,1,3},{8,6,2,1},{11,6,2,1},{6,7,9,1},{6,8,2,2},{10,8,1,2},{14,8,1,2},{1,9,4,1},{1,10,1,2},{4,10,1,1},{6,10,9,1},{6,11,2,2},{10,11,1,2},{14,11,1,2},{1,12,4,1},{4,13,1,3},{6,13,9,1},{6,14,2,1},{10,14,1,2},{14,14,1,1},{3,16,13,1},{3,17,2,1},{10,17,1,3},{0,18,4,1}}}
T.glyphs[24378] = {w=18, advance=16, rects={{0,5,5,1},{7,5,7,1},{4,6,1,3},{7,6,1,2},{13,6,1,2},{7,8,7,1},{1,9,4,1},{7,9,1,1},{10,9,1,2},{13,9,1,1},{1,10,1,2},{4,10,1,1},{6,11,9,1},{1,12,4,1},{6,12,1,2},{10,12,1,2},{14,12,1,2},{4,13,1,4},{6,14,9,1},{6,15,1,1},{10,15,1,2},{13,16,2,1},{3,17,2,1},{6,17,9,1},{1,18,3,1},{5,18,5,1},{14,18,2,1}}}
T.glyphs[24402] = {w=18, advance=16, rects={{4,4,2,1},{4,5,11,1},{1,6,2,9},{4,6,2,8},{13,6,2,4},{7,10,8,1},{13,11,2,6},{4,14,1,2},{3,16,2,1},{3,17,1,1},{6,17,9,1},{2,18,2,1},{13,18,2,1}}}
T.glyphs[24403] = {w=18, advance=16, rects={{7,4,2,6},{2,5,1,1},{13,5,1,1},{2,6,2,1},{12,6,2,1},{3,7,2,1},{11,7,2,1},{4,8,2,1},{10,8,2,1},{1,10,14,1},{13,11,2,2},{2,13,13,1},{13,14,2,3},{1,17,14,1},{13,18,2,1}}}
T.glyphs[24405] = {w=18, advance=16, rects={{2,5,11,1},{12,6,1,2},{2,8,11,1},{12,9,1,2},{0,11,16,1},{7,12,3,2},{2,13,3,1},{11,13,3,1},{5,14,4,1},{10,14,2,1},{3,15,6,1},{11,15,2,1},{1,16,3,1},{7,16,2,1},{12,16,3,1},{0,17,2,1},{4,17,4,1},{14,17,1,1}}}
T.glyphs[24418] = {w=18, advance=16, rects={{14,4,1,1},{1,5,9,1},{12,5,2,1},{2,6,2,4},{6,6,2,4},{11,6,2,1},{10,7,2,1},{9,8,2,1},{14,8,1,1},{13,9,2,1},{0,10,10,1},{11,10,3,1},{2,11,2,3},{6,11,2,7},{10,11,2,1},{9,12,2,1},{14,12,2,1},{13,13,2,1},{2,14,1,1},{12,14,2,1},{1,15,2,1},{11,15,2,1},{1,16,1,1},{9,16,3,1},{0,17,2,1},{9,17,1,1}}}
T.glyphs[24433] = {w=18, advance=16, rects={{1,5,8,1},{13,5,1,1},{1,6,1,1},{8,6,1,1},{12,6,2,1},{1,7,8,1},{10,7,3,1},{1,8,1,1},{8,8,1,1},{10,8,1,1},{14,8,1,1},{1,9,8,1},{13,9,2,1},{4,10,2,1},{12,10,2,1},{0,11,10,1},{11,11,2,1},{10,12,2,1},{14,12,2,1},{1,13,8,1},{10,13,1,1},{14,13,1,1},{1,14,2,1},{7,14,2,1},{13,14,2,1},{1,15,8,1},{12,15,2,1},{1,16,2,1},{4,16,2,2},{7,16,1,1},{11,16,2,1},{0,17,2,1},{8,17,4,1},{2,18,3,1},{9,18,2,1}}}
T.glyphs[24444] = {w=18, advance=16, rects={{4,4,1,1},{10,4,1,2},{3,5,2,1},{2,6,2,1},{6,6,9,1},{1,7,2,1},{6,7,1,3},{10,7,1,3},{14,7,1,1},{1,8,1,1},{4,8,1,1},{13,8,2,1},{3,9,2,1},{2,10,2,1},{6,10,8,1},{1,11,3,1},{6,11,1,3},{8,11,1,1},{13,11,1,1},{0,12,4,1},{8,12,2,1},{12,12,2,1},{0,13,1,1},{2,13,2,4},{9,13,1,1},{12,13,1,1},{5,14,2,2},{9,14,3,1},{9,15,4,1},{5,16,1,1},{7,16,3,1},{12,16,3,1},{2,17,3,1},{6,17,2,1},{13,17,3,1}}}
T.glyphs[24448] = {w=18, advance=16, rects={{9,4,1,1},{4,5,1,1},{9,5,2,1},{3,6,2,1},{2,7,2,1},{5,7,10,1},{1,8,2,1},{4,8,1,1},{10,8,1,4},{1,9,1,1},{3,9,2,1},{2,10,2,2},{0,12,4,1},{6,12,9,1},{0,13,2,1},{3,13,1,6},{10,13,1,4},{5,17,11,1}}}
T.glyphs[24452] = {w=18, advance=16, rects={{4,4,1,1},{3,5,2,1},{6,5,8,1},{2,6,2,1},{12,6,2,1},{1,7,2,1},{11,7,2,1},{0,8,2,1},{4,8,1,1},{10,8,2,1},{3,9,2,1},{8,9,5,1},{2,10,2,1},{6,10,3,1},{12,10,3,1},{1,11,3,1},{5,11,2,1},{14,11,2,1},{0,12,4,1},{0,13,1,1},{2,13,2,6},{6,13,9,1},{10,14,1,3},{5,17,11,1}}}
T.glyphs[24453] = {w=18, advance=16, rects={{3,4,2,2},{10,4,1,2},{2,6,2,1},{6,6,9,1},{1,7,2,1},{10,7,1,2},{0,8,2,1},{4,8,1,1},{3,9,13,1},{2,10,2,2},{1,12,3,1},{5,12,11,1},{0,13,4,1},{12,13,1,5},{0,14,1,1},{2,14,2,6},{6,14,2,1},{7,15,2,1},{8,16,1,1},{9,18,4,1}}}
T.glyphs[24456] = {w=18, advance=16, rects={{4,4,1,1},{3,5,2,1},{6,5,9,1},{3,6,1,1},{6,6,2,2},{13,6,2,2},{2,7,1,1},{1,8,2,1},{4,8,1,1},{6,8,9,1},{0,9,2,1},{3,9,2,1},{6,9,2,2},{13,9,2,2},{3,10,1,1},{2,11,2,1},{6,11,9,1},{0,12,4,1},{6,12,2,5},{9,12,2,1},{13,12,2,2},{0,13,1,1},{3,13,1,6},{10,13,1,1},{10,14,4,1},{11,15,2,1},{9,16,2,1},{12,16,1,1},{6,17,4,1},{13,17,2,1},{6,18,2,1},{14,18,1,1}}}
T.glyphs[24459] = {w=18, advance=16, rects={{3,4,2,1},{9,4,2,2},{3,5,1,1},{2,6,2,1},{6,6,8,1},{1,7,2,1},{9,7,2,1},{13,7,1,1},{0,8,2,1},{3,8,13,1},{3,9,1,1},{9,9,2,1},{13,9,1,1},{2,10,2,1},{6,10,8,1},{1,11,3,1},{9,11,2,2},{13,11,1,1},{0,12,4,1},{0,13,1,1},{2,13,2,2},{5,13,10,1},{9,14,2,1},{2,15,14,1},{2,16,2,3},{9,16,2,3}}}
T.glyphs[24471] = {w=18, advance=16, rects={{3,4,2,1},{3,5,1,1},{6,5,8,1},{2,6,2,1},{6,6,2,1},{13,6,1,1},{1,7,2,1},{6,7,8,1},{0,8,2,1},{4,8,1,1},{6,8,2,1},{13,8,1,1},{3,9,2,1},{6,9,8,1},{2,10,2,1},{1,11,3,1},{5,11,11,1},{0,12,4,1},{12,12,2,1},{0,13,1,1},{2,13,2,5},{5,13,11,1},{7,14,1,1},{12,14,2,3},{7,15,2,1},{9,17,4,1}}}
T.glyphs[24490] = {w=18, advance=16, rects={{3,4,1,1},{10,4,5,1},{2,5,2,1},{5,5,8,1},{2,6,1,1},{5,6,1,2},{10,6,2,2},{1,7,2,1},{0,8,1,1},{3,8,1,2},{5,8,11,1},{5,9,2,1},{10,9,2,1},{2,10,2,1},{5,10,1,6},{7,10,8,1},{1,11,2,1},{7,11,2,1},{13,11,2,1},{0,12,3,1},{7,12,8,1},{0,13,1,1},{2,13,1,4},{7,13,2,1},{13,13,2,1},{7,14,8,1},{7,15,2,2},{13,15,2,2},{4,16,2,1},{2,17,4,1},{7,17,8,1},{2,18,3,1},{7,18,2,1},{13,18,2,1}}}
T.glyphs[24494] = {w=18, advance=16, rects={{3,4,1,1},{7,4,1,3},{12,4,1,2},{2,5,2,1},{5,5,1,1},{9,5,1,2},{1,6,2,1},{4,6,2,1},{11,6,2,1},{0,7,2,1},{3,7,7,1},{11,7,5,1},{0,8,1,1},{2,8,2,1},{9,8,1,1},{11,8,1,1},{14,8,1,3},{2,9,1,1},{10,9,2,1},{1,10,2,2},{5,10,7,1},{11,11,4,1},{0,12,3,1},{5,12,4,1},{12,12,2,3},{0,13,1,1},{2,13,1,5},{5,13,1,3},{8,13,1,2},{10,14,1,1},{8,15,6,1},{4,16,2,1},{8,16,4,1},{14,16,1,1},{4,17,1,1},{10,17,1,1},{15,17,1,1}}}
T.glyphs[24515] = {w=18, advance=16, rects={{7,4,1,1},{7,5,2,1},{8,6,1,1},{4,7,2,10},{8,7,2,1},{9,8,1,1},{12,8,1,1},{2,9,1,1},{12,9,2,1},{1,10,2,2},{13,10,2,2},{1,12,1,1},{14,12,2,2},{0,13,2,2},{12,13,1,3},{11,16,2,1},{5,17,7,1}}}
T.glyphs[24517] = {w=18, advance=16, rects={{6,4,2,1},{7,5,1,1},{12,5,2,1},{4,6,2,7},{7,6,2,1},{12,6,1,1},{8,7,1,1},{11,7,2,1},{2,8,1,2},{10,8,2,1},{9,9,2,2},{12,9,2,1},{1,10,2,2},{13,10,1,1},{8,11,2,1},{13,11,2,1},{1,12,1,2},{7,12,2,1},{14,12,1,2},{4,13,4,1},{4,14,3,1},{12,14,1,2},{3,15,3,1},{1,16,5,1},{11,16,2,1},{1,17,1,1},{5,17,8,1}}}
T.glyphs[24535] = {w=18, advance=16, rects={{7,4,2,2},{0,6,16,1},{7,7,2,3},{2,10,12,1},{7,11,1,1},{2,12,1,1},{4,12,1,4},{7,12,2,1},{13,12,1,1},{1,13,2,2},{8,13,1,2},{13,13,2,1},{11,14,1,2},{14,14,1,2},{1,15,1,2},{4,16,2,1},{10,16,2,1},{4,17,8,1}}}
T.glyphs[24555] = {w=18, advance=16, rects={{2,4,2,3},{9,4,1,3},{1,7,4,1},{6,7,8,1},{1,8,5,1},{9,8,1,4},{13,8,1,4},{0,9,4,2},{5,9,1,1},{0,11,1,1},{2,11,2,7},{5,12,11,1},{8,13,3,2},{7,15,2,1},{10,15,2,1},{6,16,2,1},{11,16,2,1},{5,17,2,1},{12,17,3,1},{2,18,4,1},{13,18,2,1}}}
T.glyphs[24573] = {w=18, advance=16, rects={{4,4,2,1},{4,5,1,1},{3,6,12,1},{2,7,2,1},{6,7,2,1},{9,7,2,2},{13,7,2,2},{2,8,1,1},{6,8,1,1},{1,9,1,1},{5,9,2,1},{9,9,1,1},{13,9,1,2},{4,10,2,1},{8,10,2,1},{3,11,2,1},{7,11,2,1},{12,11,2,1},{2,12,1,1},{6,12,2,1},{9,12,5,1},{5,13,3,1},{1,14,2,2},{4,14,1,2},{7,14,2,1},{11,14,3,1},{8,15,2,1},{11,15,4,1},{1,16,1,2},{4,16,2,1},{11,16,1,1},{14,16,2,1},{4,17,8,1}}}
T.glyphs[24577] = {w=18, advance=16, rects={{7,4,2,2},{1,6,14,1},{6,7,3,1},{6,8,1,1},{9,8,1,1},{5,9,2,1},{10,9,2,1},{3,10,5,1},{11,10,3,1},{1,11,3,1},{7,11,2,1},{13,11,2,1},{0,12,2,1},{7,13,1,1},{2,14,1,1},{4,14,2,3},{7,14,2,1},{12,14,2,1},{1,15,2,1},{8,15,1,1},{11,15,1,1},{13,15,2,2},{1,16,1,1},{10,16,2,1},{5,17,7,1},{14,17,1,1}}}
T.glyphs[24590] = {w=18, advance=16, rects={{4,4,1,1},{3,5,2,1},{2,6,13,1},{2,7,2,1},{5,7,2,1},{1,8,2,1},{5,8,9,1},{1,9,1,1},{5,9,2,2},{5,11,9,1},{5,12,2,1},{2,13,1,1},{7,13,2,1},{13,13,1,1},{1,14,2,1},{4,14,2,3},{8,14,1,1},{11,14,1,2},{13,14,2,1},{1,15,1,2},{14,15,1,1},{10,16,2,1},{14,16,2,1},{4,17,8,1}}}
T.glyphs[24605] = {w=18, advance=16, rects={{2,5,12,1},{2,6,1,2},{7,6,2,2},{13,6,1,2},{2,8,12,1},{2,9,1,2},{7,9,2,2},{13,9,1,2},{2,11,12,1},{2,12,1,1},{7,12,1,1},{13,12,1,1},{7,13,2,1},{1,14,2,1},{4,14,2,3},{8,14,1,1},{13,14,1,1},{1,15,1,1},{11,15,1,2},{13,15,2,1},{0,16,2,1},{14,16,1,1},{4,17,8,1}}}
T.glyphs[24615] = {w=18, advance=16, rects={{2,4,2,2},{10,4,1,3},{7,5,1,2},{2,6,3,1},{1,7,14,1},{1,8,4,1},{6,8,1,1},{10,8,1,4},{0,9,4,1},{5,9,2,1},{0,10,1,1},{2,10,2,9},{5,10,1,1},{6,12,9,1},{10,13,1,4},{5,17,11,1}}}
T.glyphs[24635] = {w=18, advance=16, rects={{4,4,1,1},{10,4,2,2},{4,5,2,1},{5,6,1,1},{9,6,2,1},{2,7,12,1},{2,8,2,3},{12,8,2,3},{2,11,12,1},{2,12,2,1},{12,12,2,1},{7,13,2,1},{1,14,2,1},{4,14,2,3},{8,14,1,1},{12,14,2,1},{1,15,1,1},{13,15,2,1},{0,16,2,1},{11,16,1,1},{14,16,1,1},{5,17,7,1}}}
T.glyphs[24658] = {w=18, advance=16, rects={{2,4,2,3},{5,5,11,1},{2,7,3,1},{1,8,14,1},{0,9,4,2},{5,9,3,1},{13,9,2,2},{6,10,2,1},{2,11,2,8},{6,11,9,1},{6,12,2,2},{13,12,2,2},{6,14,9,1},{6,15,2,1},{13,15,2,1},{5,17,11,1}}}
T.glyphs[24661] = {w=18, advance=16, rects={{3,4,1,1},{0,5,15,1},{2,6,1,2},{6,6,1,3},{8,6,2,5},{13,6,2,5},{1,8,2,1},{1,9,3,1},{5,9,2,1},{3,10,3,1},{3,11,4,1},{8,11,7,1},{1,12,3,1},{6,12,1,1},{8,12,2,1},{13,12,2,1},{1,13,1,1},{7,13,1,1},{1,14,2,2},{4,14,2,4},{7,14,2,1},{13,14,1,1},{8,15,1,1},{11,15,1,2},{13,15,2,1},{1,16,1,1},{14,16,1,1},{0,17,2,1},{10,17,2,1},{5,18,6,1}}}
T.glyphs[24674] = {w=18, advance=16, rects={{2,4,2,3},{7,4,1,2},{5,6,11,1},{2,7,3,1},{7,7,1,1},{1,8,4,1},{6,8,2,3},{10,8,2,4},{0,9,4,1},{0,10,1,1},{2,10,2,4},{14,10,1,1},{6,11,1,1},{8,11,1,1},{13,11,2,1},{5,12,2,1},{8,12,4,1},{13,12,1,1},{5,13,1,1},{9,13,3,1},{2,14,4,1},{9,14,4,1},{2,15,3,1},{8,15,2,1},{12,15,2,1},{2,16,2,2},{7,16,2,1},{13,16,2,1},{6,17,2,1},{14,17,1,1}}}
T.glyphs[24676] = {w=18, advance=16, rects={{2,4,1,2},{9,4,1,1},{8,5,2,1},{2,6,2,1},{5,6,10,1},{1,7,6,1},{8,7,1,10},{11,7,1,10},{13,7,2,10},{0,8,3,1},{4,8,3,1},{0,9,1,2},{2,9,1,10},{5,9,2,8},{4,17,12,1}}}
T.glyphs[24687] = {w=18, advance=16, rects={{6,4,2,1},{2,5,12,1},{2,6,2,1},{12,6,2,1},{2,7,12,1},{2,8,2,1},{12,8,2,1},{2,9,12,1},{2,10,2,1},{12,10,2,1},{2,11,12,1},{2,12,2,1},{12,12,2,1},{7,13,1,1},{1,14,2,1},{4,14,1,3},{7,14,2,1},{13,14,1,1},{1,15,1,1},{8,15,1,1},{11,15,1,2},{13,15,2,1},{0,16,2,1},{14,16,2,1},{4,17,8,1}}}
T.glyphs[24688] = {w=18, advance=16, rects={{2,4,2,2},{10,4,2,1},{9,5,3,1},{2,6,3,1},{8,6,2,1},{11,6,2,1},{1,7,5,1},{7,7,2,1},{12,7,2,1},{1,8,3,1},{5,8,3,1},{13,8,2,1},{0,9,4,1},{5,9,2,1},{14,9,2,1},{0,10,1,1},{2,10,2,9},{7,10,7,1},{6,13,9,1},{6,14,2,3},{13,14,2,3},{6,17,9,1},{6,18,2,1},{13,18,2,1}}}
T.glyphs[24708] = {w=18, advance=16, rects={{2,5,2,2},{6,5,1,1},{10,5,1,3},{13,5,2,1},{6,6,2,1},{13,6,1,1},{2,7,3,1},{7,7,2,1},{1,8,14,1},{0,9,4,2},{6,9,1,2},{14,9,1,2},{0,11,1,1},{2,11,2,7},{6,11,9,1},{6,12,1,2},{14,12,1,2},{6,14,9,1},{6,15,1,3},{14,15,1,2},{11,17,4,1}}}
T.glyphs[24748] = {w=18, advance=16, rects={{2,5,12,1},{2,6,2,1},{12,6,2,1},{2,7,12,1},{2,8,2,1},{12,8,2,1},{2,9,12,1},{2,10,2,1},{12,10,2,1},{0,11,16,1},{3,12,3,1},{10,12,2,1},{2,13,11,1},{13,14,1,1},{1,15,2,1},{4,15,2,2},{7,15,2,1},{13,15,2,2},{1,16,1,2},{11,16,1,1},{5,17,7,1},{14,17,2,1}}}
T.glyphs[24773] = {w=18, advance=16, rects={{2,4,2,3},{9,4,2,1},{5,5,11,1},{9,6,2,1},{2,7,13,1},{1,8,4,1},{9,8,2,1},{0,9,4,2},{5,9,11,1},{0,11,1,1},{2,11,2,8},{6,11,9,1},{6,12,1,1},{13,12,2,1},{6,13,9,1},{6,14,1,1},{13,14,2,1},{6,15,9,1},{6,16,1,3},{13,16,2,2},{10,18,4,1}}}
T.glyphs[24809] = {w=18, advance=16, rects={{3,4,2,1},{2,5,2,1},{5,5,10,1},{1,6,2,1},{10,6,1,2},{1,7,1,1},{4,7,1,1},{3,8,2,1},{6,8,2,4},{10,8,5,1},{2,9,2,1},{10,9,1,3},{1,10,3,1},{0,11,4,1},{2,12,2,1},{5,12,11,1},{1,14,2,2},{4,14,2,3},{7,14,2,1},{13,14,1,1},{8,15,1,1},{11,15,1,2},{13,15,2,1},{1,16,1,1},{14,16,2,1},{5,17,7,1}}}
T.glyphs[24811] = {w=18, advance=16, rects={{4,4,2,1},{3,5,11,1},{2,6,4,1},{10,6,3,1},{1,7,1,1},{5,7,6,1},{3,8,9,1},{0,9,5,1},{11,9,4,1},{2,10,12,1},{2,11,2,1},{7,11,2,1},{12,11,2,1},{2,12,12,1},{2,13,2,1},{7,13,2,1},{12,13,2,1},{4,14,10,1},{2,15,1,1},{4,15,2,2},{7,15,1,1},{1,16,2,1},{8,16,1,1},{11,16,1,1},{13,16,2,1},{0,17,2,1},{5,17,7,1},{14,17,1,1}}}
T.glyphs[24819] = {w=18, advance=16, rects={{3,4,1,3},{7,5,8,1},{7,6,1,1},{13,6,2,1},{0,7,15,1},{3,8,3,1},{7,8,1,1},{13,8,2,1},{2,9,4,1},{7,9,8,1},{1,10,1,1},{3,10,1,3},{5,10,3,1},{13,10,2,2},{0,11,2,1},{7,11,1,1},{0,12,1,1},{7,12,8,1},{1,14,2,2},{4,14,2,3},{7,14,1,1},{11,14,1,2},{8,15,1,1},{13,15,2,1},{1,16,1,1},{10,16,2,1},{14,16,1,1},{0,17,2,1},{5,17,7,1}}}
T.glyphs[24847] = {w=18, advance=16, rects={{7,4,2,1},{1,5,14,1},{4,6,2,1},{10,6,2,1},{0,7,16,1},{2,9,12,1},{2,10,2,1},{12,10,2,1},{2,11,12,1},{2,12,2,1},{12,12,2,1},{2,13,12,1},{7,14,2,1},{13,14,1,1},{1,15,2,1},{4,15,1,1},{8,15,1,1},{13,15,2,1},{1,16,1,2},{4,16,2,1},{11,16,1,1},{14,16,2,1},{4,17,8,1}}}
T.glyphs[24863] = {w=18, advance=16, rects={{10,4,1,2},{12,4,1,1},{13,5,1,1},{2,6,14,1},{2,7,1,1},{10,7,1,2},{2,8,7,1},{13,8,1,2},{2,9,1,2},{10,9,2,1},{4,10,5,1},{10,10,3,1},{1,11,2,2},{4,11,1,1},{8,11,1,1},{11,11,2,1},{14,11,2,2},{4,12,5,1},{10,12,3,1},{1,13,1,2},{4,13,1,1},{9,13,2,1},{12,13,3,1},{7,14,2,1},{2,15,1,1},{4,15,2,2},{8,15,1,1},{11,15,1,1},{1,16,2,1},{10,16,2,1},{13,16,2,1},{1,17,1,1},{4,17,7,1},{14,17,1,1}}}
T.glyphs[24904] = {w=18, advance=16, rects={{5,4,1,1},{10,4,1,1},{0,5,16,1},{3,6,2,1},{10,6,2,1},{3,7,1,1},{6,7,1,1},{9,7,2,1},{13,7,1,1},{1,8,2,1},{5,8,2,1},{8,8,2,1},{12,8,2,1},{1,9,5,1},{8,9,5,1},{4,10,1,1},{10,10,2,1},{2,11,2,1},{6,11,1,1},{9,11,2,1},{13,11,1,1},{1,12,14,1},{7,13,1,1},{14,13,1,1},{1,14,2,2},{7,14,2,1},{13,14,1,1},{4,15,2,3},{8,15,2,1},{11,15,1,2},{13,15,2,1},{1,16,1,1},{14,16,1,2},{0,17,2,1},{10,17,2,1},{5,18,6,1}}}
T.glyphs[24930] = {w=18, advance=16, rects={{2,5,2,2},{6,5,8,1},{6,6,1,1},{13,6,1,1},{1,7,4,1},{6,7,8,1},{1,8,6,1},{13,8,1,1},{1,9,13,1},{0,10,4,2},{5,11,10,1},{0,12,1,1},{2,12,2,7},{5,12,1,1},{8,12,1,1},{11,12,1,1},{14,12,1,1},{5,13,10,1},{5,15,9,1},{7,16,2,1},{11,16,3,1},{8,17,4,1},{5,18,4,1},{11,18,4,1}}}
T.glyphs[25042] = {w=18, advance=16, rects={{2,4,1,3},{6,4,1,2},{11,4,1,1},{11,5,4,1},{4,6,7,1},{13,6,1,2},{2,7,2,1},{6,7,1,2},{10,7,1,1},{1,8,4,1},{9,8,2,1},{12,8,2,1},{0,9,3,2},{4,9,5,1},{10,9,5,1},{4,10,1,2},{6,10,1,2},{8,10,1,2},{10,10,1,5},{12,10,1,5},{14,10,1,5},{0,11,1,1},{2,11,1,5},{4,12,5,1},{6,13,2,1},{5,14,4,1},{4,15,3,1},{8,15,2,1},{11,15,2,1},{2,16,3,1},{6,16,1,3},{11,16,3,1},{2,17,1,2},{4,17,1,1},{10,17,2,1},{14,17,1,1},{9,18,2,1},{14,18,2,1}}}
T.glyphs[25103] = {w=18, advance=16, rects={{9,4,1,3},{11,4,2,1},{0,5,6,1},{12,5,2,1},{5,6,1,3},{13,6,1,1},{1,7,1,1},{9,7,7,1},{1,8,2,1},{7,8,6,1},{2,9,1,1},{4,9,2,1},{9,9,2,3},{13,9,2,1},{2,10,3,1},{13,10,1,1},{3,11,2,2},{12,11,2,1},{10,12,3,1},{3,13,3,1},{10,13,2,1},{2,14,2,1},{5,14,2,1},{9,14,3,1},{14,14,2,3},{1,15,2,1},{6,15,1,1},{8,15,4,1},{1,16,1,1},{7,16,2,1},{11,16,2,1},{0,17,1,1},{6,17,2,1},{12,17,3,1}}}
T.glyphs[25104] = {w=18, advance=16, rects={{9,4,1,3},{12,4,1,1},{12,5,2,1},{2,7,14,1},{2,8,1,2},{9,8,2,1},{9,9,1,1},{2,10,6,1},{9,10,2,3},{13,10,2,1},{2,11,1,2},{6,11,2,3},{13,11,1,1},{12,12,2,1},{1,13,2,2},{10,13,3,1},{6,14,1,1},{10,14,2,1},{15,14,1,1},{1,15,1,1},{3,15,4,1},{9,15,3,1},{14,15,2,1},{0,16,2,1},{8,16,2,1},{11,16,5,1},{0,17,1,1},{7,17,2,1},{12,17,3,1}}}
T.glyphs[25105] = {w=18, advance=16, rects={{2,4,5,1},{9,4,1,4},{11,4,2,1},{1,5,6,1},{12,5,2,1},{3,6,2,2},{13,6,2,1},{0,8,16,1},{3,9,2,2},{9,9,1,2},{13,10,2,1},{3,11,5,1},{9,11,2,1},{12,11,2,1},{1,12,6,1},{9,12,4,1},{0,13,5,1},{10,13,2,1},{3,14,2,3},{9,14,3,1},{14,14,2,2},{7,15,5,1},{6,16,2,1},{11,16,2,1},{14,16,1,1},{1,17,4,1},{12,17,3,1}}}
T.glyphs[25110] = {w=18, advance=16, rects={{9,3,1,3},{11,3,2,1},{13,4,1,1},{0,6,16,1},{9,7,1,3},{1,8,6,1},{1,9,2,3},{6,9,1,3},{13,9,1,2},{9,10,2,2},{12,11,2,1},{1,12,6,1},{9,12,4,1},{1,13,2,1},{6,13,1,1},{10,13,2,2},{15,14,1,1},{1,15,7,1},{9,15,3,1},{14,15,2,2},{0,16,5,1},{8,16,2,1},{11,16,2,1},{7,17,2,1},{12,17,3,1}}}
T.glyphs[25112] = {w=18, advance=16, rects={{3,4,2,3},{9,4,2,4},{12,4,2,1},{3,7,5,1},{13,7,3,1},{3,8,2,3},{8,8,6,1},{7,9,4,1},{14,9,1,1},{10,10,1,2},{13,10,2,1},{1,11,6,1},{13,11,1,1},{1,12,1,4},{6,12,1,4},{10,12,3,2},{10,14,2,1},{15,14,1,1},{8,15,2,1},{11,15,2,1},{14,15,2,1},{1,16,8,1},{12,16,4,1},{1,17,1,1},{6,17,1,1},{13,17,2,1}}}
T.glyphs[25130] = {w=18, advance=16, rects={{5,4,1,1},{10,4,1,4},{1,5,8,1},{12,5,2,1},{5,6,1,2},{13,6,2,1},{0,8,16,1},{2,9,2,2},{5,9,1,1},{10,9,1,2},{6,10,1,1},{14,10,1,1},{1,11,11,1},{13,11,2,1},{1,12,2,1},{5,12,2,1},{10,12,2,1},{13,12,1,1},{0,13,1,1},{2,13,7,1},{10,13,4,1},{2,14,1,1},{5,14,2,1},{11,14,2,2},{2,15,7,1},{15,15,1,1},{2,16,1,1},{5,16,2,1},{10,16,3,1},{14,16,2,2},{2,17,8,1},{12,17,1,1},{2,18,1,1},{12,18,3,1}}}
T.glyphs[25139] = {w=18, advance=16, rects={{0,5,9,1},{10,5,2,3},{13,5,1,1},{4,6,1,1},{8,6,1,2},{14,6,1,1},{1,7,2,1},{4,7,3,1},{2,8,3,1},{6,8,3,1},{10,8,6,1},{0,9,2,1},{4,9,3,1},{8,9,6,1},{2,10,1,1},{5,10,1,1},{11,10,1,3},{14,10,1,2},{1,11,8,1},{0,12,3,1},{5,12,1,1},{13,12,2,1},{0,13,9,1},{11,13,3,1},{1,14,2,1},{5,14,1,1},{11,14,2,1},{15,14,1,2},{1,15,8,1},{10,15,3,1},{1,16,2,1},{5,16,1,1},{9,16,2,1},{12,16,4,1},{1,17,9,1},{13,17,3,1},{1,18,2,2}}}
T.glyphs[25143] = {w=18, advance=16, rects={{7,4,2,2},{2,6,13,1},{2,7,2,4},{13,7,2,4},{2,11,13,1},{2,12,2,1},{13,12,2,1},{2,13,1,2},{1,15,2,2},{0,17,2,2}}}
T.glyphs[25152] = {w=18, advance=16, rects={{5,4,2,1},{12,4,3,1},{1,5,6,1},{8,5,6,1},{1,6,2,2},{8,6,2,4},{1,8,6,1},{1,9,2,3},{6,9,1,3},{8,10,8,1},{8,11,2,2},{12,11,2,8},{1,12,6,1},{1,13,2,2},{6,13,1,1},{8,13,1,2},{1,15,1,2},{7,15,2,2},{0,17,2,1},{6,17,2,1},{0,18,1,1},{6,18,1,1}}}
T.glyphs[25163] = {w=18, advance=16, rects={{9,4,5,1},{1,5,12,1},{7,6,2,3},{1,9,14,1},{7,10,2,3},{0,13,16,1},{7,14,2,3},{4,17,5,1},{4,18,1,1}}}
T.glyphs[25165] = {w=18, advance=16, rects={{10,4,2,3},{1,7,15,1},{9,8,3,1},{8,9,4,1},{8,10,1,1},{10,10,2,6},{7,11,1,1},{6,12,1,1},{4,13,2,1},{3,14,2,1},{1,15,3,1},{1,16,1,1},{7,16,1,1},{9,16,3,1},{6,17,5,1}}}
T.glyphs[25170] = {w=18, advance=16, rects={{2,4,2,3},{7,4,2,8},{12,4,1,7},{0,7,6,1},{2,8,2,2},{2,10,4,1},{1,11,4,1},{12,11,2,3},{0,12,4,1},{7,12,1,1},{2,13,2,4},{6,13,2,2},{13,14,1,1},{5,15,2,2},{13,15,2,1},{14,16,2,1},{0,17,4,1},{5,17,1,1},{14,17,1,1}}}
T.glyphs[25171] = {w=18, advance=16, rects={{3,4,1,3},{7,5,9,1},{12,6,1,10},{0,7,7,1},{3,8,2,1},{3,9,1,2},{5,10,2,1},{3,11,4,1},{1,12,4,1},{0,13,2,1},{3,13,1,4},{11,16,2,1},{1,17,3,1},{8,17,5,1}}}
T.glyphs[25176] = {w=18, advance=16, rects={{3,4,1,3},{8,5,6,1},{6,6,7,1},{0,7,6,1},{9,7,1,3},{3,8,1,3},{8,10,8,1},{2,11,11,1},{0,12,4,1},{9,12,1,5},{3,13,1,3},{14,13,2,3},{2,16,2,1},{14,16,1,1},{0,17,4,1},{9,17,6,1}}}
T.glyphs[25187] = {w=18, advance=16, rects={{3,4,1,3},{7,5,8,1},{7,6,1,10},{13,6,2,10},{0,7,6,1},{2,8,2,1},{3,9,1,1},{3,10,3,1},{1,11,4,1},{0,12,4,1},{3,13,1,3},{2,16,2,1},{7,16,8,1},{0,17,4,1},{7,17,1,1},{13,17,2,1}}}
T.glyphs[25191] = {w=18, advance=16, rects={{2,4,2,3},{8,4,1,3},{0,7,14,1},{2,8,2,3},{8,8,1,2},{12,8,2,1},{12,9,1,4},{6,10,3,1},{1,11,4,1},{7,11,2,1},{0,12,4,1},{7,12,3,1},{2,13,2,4},{7,13,1,1},{10,13,1,1},{12,13,2,2},{6,14,2,1},{15,14,1,1},{6,15,1,1},{12,15,4,2},{5,16,2,1},{0,17,3,1},{5,17,1,1},{13,17,2,1}}}
T.glyphs[25193] = {w=18, advance=16, rects={{2,4,2,3},{10,4,2,1},{11,5,1,1},{6,6,10,1},{0,7,8,1},{2,8,2,2},{6,8,2,2},{2,10,6,1},{1,11,4,1},{6,11,2,4},{0,12,4,1},{2,13,2,4},{6,15,1,1},{5,16,2,2},{0,17,4,1},{5,18,1,1}}}
T.glyphs[25195] = {w=18, advance=16, rects={{2,4,2,3},{6,5,9,1},{13,6,2,5},{0,7,6,1},{2,8,2,2},{2,10,4,1},{1,11,4,1},{7,11,8,1},{0,12,4,1},{13,12,2,5},{2,13,2,4},{0,17,4,1},{5,17,10,1},{13,18,2,2}}}
T.glyphs[25209] = {w=18, advance=16, rects={{2,4,2,3},{6,4,1,5},{10,4,2,5},{0,7,5,1},{14,7,1,1},{2,8,2,2},{13,8,2,1},{6,9,8,1},{2,10,3,1},{6,10,2,1},{10,10,3,1},{1,11,3,1},{6,11,1,5},{10,11,2,4},{0,12,4,1},{2,13,2,4},{14,13,2,4},{8,15,4,1},{6,16,6,1},{0,17,3,1},{6,17,2,1},{11,17,4,1}}}
T.glyphs[25214] = {w=18, advance=16, rects={{3,4,1,3},{9,4,1,3},{11,4,2,1},{12,5,2,1},{0,7,7,1},{9,7,7,1},{3,8,1,2},{6,8,8,1},{9,9,1,2},{13,9,2,1},{1,10,6,1},{13,10,1,1},{0,11,4,1},{9,11,2,1},{12,11,1,1},{3,12,1,5},{9,12,3,1},{9,13,2,1},{8,14,3,1},{14,14,2,2},{6,15,3,1},{10,15,2,1},{5,16,2,1},{11,16,2,1},{14,16,1,1},{1,17,3,1},{12,17,3,1}}}
T.glyphs[25220] = {w=18, advance=16, rects={{2,4,2,3},{10,4,1,9},{7,6,1,2},{13,6,1,1},{0,7,6,1},{13,7,2,1},{2,8,2,2},{6,8,2,2},{14,8,1,2},{2,10,5,1},{1,11,3,1},{13,11,2,2},{0,12,4,1},{2,13,2,4},{12,13,2,1},{11,14,2,1},{9,15,2,1},{6,16,4,1},{0,17,4,1},{5,17,2,1}}}
T.glyphs[25226] = {w=18, advance=16, rects={{2,4,2,3},{6,5,9,1},{6,6,1,1},{9,6,2,4},{13,6,2,4},{0,7,7,1},{2,8,2,2},{6,8,1,2},{2,10,13,1},{1,11,3,1},{6,11,1,6},{13,11,2,1},{0,12,4,1},{2,13,2,4},{14,13,2,3},{14,16,1,1},{0,17,3,1},{6,17,9,1}}}
T.glyphs[25235] = {w=18, advance=16, rects={{2,4,2,3},{10,4,5,1},{6,5,8,1},{6,6,1,8},{9,6,1,12},{12,6,1,5},{0,7,5,1},{2,8,2,2},{2,10,3,1},{1,11,3,1},{12,11,2,3},{0,12,4,1},{2,13,2,3},{5,14,2,2},{13,14,1,1},{13,15,2,1},{2,16,4,1},{14,16,1,2},{0,17,3,1},{4,17,2,1}}}
T.glyphs[25238] = {w=18, advance=16, rects={{2,4,2,3},{12,4,1,8},{7,5,1,1},{8,6,2,1},{0,7,6,1},{9,7,1,1},{2,8,2,2},{6,8,2,1},{7,9,2,1},{2,10,4,1},{8,10,2,1},{1,11,3,1},{0,12,4,1},{11,12,5,1},{2,13,2,4},{6,13,9,1},{5,14,4,1},{12,14,1,4},{0,17,4,1}}}
T.glyphs[25240] = {w=18, advance=16, rects={{2,4,2,3},{11,4,4,1},{6,5,8,1},{6,6,2,1},{0,7,8,1},{2,8,2,2},{6,8,2,2},{2,10,14,1},{1,11,3,1},{6,11,2,4},{11,11,2,1},{0,12,4,1},{12,12,1,6},{2,13,2,4},{6,15,1,1},{5,16,2,2},{0,17,4,1},{5,18,1,1}}}
T.glyphs[25243] = {w=18, advance=16, rects={{2,4,1,3},{6,4,1,4},{11,4,1,3},{0,7,5,1},{10,7,5,1},{2,8,1,3},{5,8,4,1},{11,8,1,5},{13,8,2,7},{6,9,1,5},{8,9,1,6},{2,11,3,1},{1,12,3,1},{0,13,3,1},{10,13,2,2},{2,14,1,4},{5,14,2,3},{8,15,8,1},{8,16,3,1},{14,16,2,2},{5,17,1,1},{8,17,2,1},{0,18,3,1},{4,18,2,1},{9,18,6,1},{4,19,1,1}}}
T.glyphs[25252] = {w=18, advance=16, rects={{2,4,2,3},{10,4,1,1},{10,5,2,1},{6,6,9,1},{0,7,8,1},{14,7,1,4},{2,8,2,2},{6,8,2,2},{2,10,6,1},{1,11,4,1},{6,11,9,1},{0,12,4,1},{6,12,2,3},{14,12,1,1},{2,13,2,4},{6,15,1,1},{5,16,2,2},{0,17,4,1},{5,18,1,1}}}
T.glyphs[25253] = {w=18, advance=16, rects={{2,4,2,3},{6,5,9,1},{6,6,2,1},{13,6,2,2},{0,7,8,1},{2,8,2,2},{6,8,2,2},{10,8,4,1},{2,10,13,1},{1,11,4,1},{6,11,4,1},{13,11,2,1},{0,12,4,1},{6,12,2,4},{9,12,1,1},{13,12,1,1},{2,13,2,4},{9,13,2,1},{12,13,2,1},{10,14,3,2},{6,16,5,1},{12,16,3,1},{0,17,4,1},{6,17,3,1},{14,17,2,1}}}
T.glyphs[25260] = {w=18, advance=16, rects={{2,4,2,3},{9,4,1,1},{8,5,2,1},{8,6,1,1},{12,6,1,1},{0,7,6,1},{7,7,2,1},{12,7,2,1},{2,8,2,3},{6,8,2,1},{13,8,2,1},{5,9,10,1},{14,10,2,1},{1,11,5,1},{0,12,4,1},{6,12,9,1},{2,13,2,4},{6,13,2,4},{13,13,2,4},{0,17,3,1},{6,17,9,1},{6,18,2,1},{13,18,2,1}}}
T.glyphs[25273] = {w=18, advance=16, rects={{2,4,2,4},{9,4,2,3},{5,7,10,1},{0,8,5,1},{9,8,2,2},{2,9,2,2},{6,10,9,1},{1,11,4,1},{9,11,3,1},{0,12,4,1},{8,12,4,1},{2,13,2,3},{7,13,4,1},{12,13,1,1},{6,14,2,1},{9,14,2,4},{12,14,2,1},{5,15,2,1},{13,15,2,1},{2,16,4,1},{14,16,2,1},{0,17,3,1}}}
T.glyphs[25277] = {w=18, advance=16, rects={{2,4,2,3},{10,4,1,3},{0,7,15,1},{2,8,2,3},{6,8,1,3},{10,8,1,4},{14,8,1,4},{2,11,5,1},{1,12,3,1},{6,12,9,1},{0,13,4,1},{6,13,1,4},{10,13,1,4},{14,13,1,4},{2,14,2,4},{6,17,9,1},{0,18,3,1},{6,18,1,1},{14,18,1,1}}}
T.glyphs[25286] = {w=18, advance=16, rects={{2,4,2,3},{11,4,4,1},{6,5,8,1},{6,6,2,1},{0,7,8,1},{2,8,2,2},{6,8,2,1},{6,9,10,1},{2,10,6,1},{11,10,2,2},{1,11,3,1},{6,11,2,3},{0,12,4,1},{9,12,4,1},{2,13,2,4},{10,13,4,1},{6,14,1,1},{11,14,4,1},{5,15,2,2},{11,15,2,3},{0,17,4,1},{5,17,1,1}}}
T.glyphs[25289] = {w=18, advance=16, rects={{2,4,2,4},{9,4,2,1},{10,5,1,2},{6,7,9,1},{0,8,6,1},{2,9,2,2},{7,9,1,1},{12,9,2,3},{7,10,2,2},{2,11,4,1},{1,12,4,1},{8,12,1,3},{12,12,1,2},{0,13,4,1},{2,14,2,4},{11,14,2,1},{8,15,2,1},{11,15,1,2},{5,17,11,1},{0,18,4,1}}}
T.glyphs[25293] = {w=18, advance=16, rects={{2,4,2,3},{9,4,2,1},{9,5,1,1},{6,6,9,1},{0,7,8,1},{14,7,1,4},{2,8,2,3},{6,8,2,3},{2,11,13,1},{1,12,3,1},{6,12,2,5},{14,12,1,5},{0,13,4,1},{2,14,2,4},{6,17,9,1},{0,18,4,1},{6,18,2,1},{14,18,1,1}}}
T.glyphs[25302] = {w=18, advance=16, rects={{2,4,2,3},{7,4,2,1},{7,5,1,1},{6,6,9,1},{0,7,7,1},{2,8,2,2},{5,8,2,1},{10,8,1,1},{6,9,2,1},{10,9,5,1},{2,10,3,1},{6,10,9,1},{1,11,3,1},{5,11,3,1},{9,11,2,1},{13,11,2,2},{0,12,4,1},{6,12,2,5},{10,12,1,1},{2,13,2,4},{10,13,4,1},{10,14,1,2},{15,14,1,1},{14,15,2,2},{0,17,3,1},{7,17,8,1}}}
T.glyphs[25307] = {w=18, advance=16, rects={{2,4,2,3},{6,5,9,1},{8,6,2,2},{14,6,1,3},{0,7,6,1},{2,8,2,3},{8,8,1,1},{6,9,2,1},{13,9,2,1},{5,10,2,1},{10,10,4,1},{2,11,3,1},{1,12,4,1},{6,12,9,1},{0,13,4,1},{6,13,2,4},{13,13,2,4},{2,14,2,4},{6,17,9,1},{0,18,3,1},{6,18,2,1},{13,18,2,1}}}
T.glyphs[25311] = {w=18, advance=16, rects={{2,4,2,3},{8,4,1,1},{12,4,2,7},{6,5,1,8},{8,5,2,1},{9,6,2,1},{0,7,5,1},{10,7,1,1},{2,8,2,2},{2,10,3,1},{1,11,3,1},{12,11,1,2},{0,12,4,1},{9,12,1,1},{2,13,2,4},{6,13,4,1},{11,13,2,1},{6,14,2,1},{11,14,3,1},{6,15,1,1},{10,15,2,1},{13,15,2,2},{9,16,2,1},{0,17,3,1},{8,17,1,1},{14,17,2,1}}}
T.glyphs[25318] = {w=18, advance=16, rects={{2,4,2,3},{7,4,2,1},{13,4,1,1},{8,5,2,1},{12,5,2,1},{11,6,2,1},{0,7,16,1},{2,8,2,3},{2,11,4,1},{1,12,4,1},{7,12,8,1},{0,13,4,1},{2,14,2,4},{5,17,11,1},{0,18,4,1}}}
T.glyphs[25321] = {w=18, advance=16, rects={{2,4,2,3},{6,5,9,1},{7,6,1,1},{13,6,2,1},{0,7,6,1},{8,7,1,1},{12,7,2,1},{2,8,2,3},{9,8,4,1},{6,9,8,1},{5,10,3,1},{12,10,4,1},{2,11,3,1},{10,11,1,1},{1,12,4,1},{6,12,9,1},{0,13,4,1},{10,13,1,2},{2,14,2,4},{5,15,11,1},{10,16,1,3},{0,18,3,1}}}
T.glyphs[25324] = {w=18, advance=16, rects={{2,4,2,3},{10,4,5,1},{6,5,8,1},{10,6,1,3},{0,7,5,1},{2,8,2,3},{5,9,11,1},{10,10,1,3},{2,11,3,1},{1,12,3,1},{0,13,4,1},{6,13,9,1},{2,14,2,4},{6,14,1,3},{13,14,2,3},{6,17,9,1},{0,18,3,1},{6,18,1,2},{13,18,2,2}}}
T.glyphs[25340] = {w=18, advance=16, rects={{2,4,2,3},{7,4,2,1},{13,4,1,1},{8,5,1,1},{12,5,2,1},{11,6,2,1},{0,7,15,1},{2,8,2,2},{7,8,2,4},{12,8,2,1},{12,9,1,3},{2,10,4,1},{0,11,4,2},{5,12,11,1},{2,13,2,4},{7,13,2,2},{12,13,2,1},{12,14,1,4},{6,15,2,1},{5,16,2,1},{0,17,4,1},{5,17,1,1}}}
T.glyphs[25341] = {w=18, advance=16, rects={{2,4,2,3},{9,4,2,2},{6,6,9,1},{0,7,7,1},{9,7,2,2},{13,7,2,2},{2,8,2,2},{6,8,1,1},{6,9,9,1},{2,10,5,1},{9,10,2,2},{13,10,2,2},{1,11,3,1},{6,11,1,1},{0,12,4,1},{6,12,9,1},{2,13,2,4},{6,13,1,1},{9,13,2,1},{10,14,1,1},{12,14,2,1},{10,15,3,1},{6,16,7,1},{14,16,2,1},{0,17,3,1},{5,17,3,1},{12,17,3,1}}}
T.glyphs[25343] = {w=18, advance=16, rects={{6,4,4,1},{5,5,2,1},{9,5,3,1},{2,6,13,1},{0,7,4,1},{12,7,3,1},{3,8,10,1},{3,9,1,1},{12,9,1,1},{3,10,10,1},{1,12,13,1},{8,13,1,1},{2,14,12,1},{8,15,1,1},{0,16,16,1},{7,17,2,1},{5,18,4,1}}}
T.glyphs[25345] = {w=18, advance=16, rects={{2,4,2,3},{10,4,1,2},{6,6,9,1},{0,7,6,1},{10,7,1,2},{2,8,2,3},{5,9,11,1},{2,11,3,1},{12,11,1,2},{1,12,4,1},{0,13,4,1},{5,13,11,1},{2,14,2,4},{12,14,2,1},{7,15,1,1},{12,15,1,3},{7,16,2,1},{0,18,3,1},{9,18,4,1}}}
T.glyphs[25346] = {w=18, advance=16, rects={{2,4,2,3},{10,4,1,2},{6,6,9,1},{0,7,5,1},{10,7,1,2},{2,8,2,3},{6,9,10,1},{2,11,3,1},{1,12,3,1},{10,12,1,1},{0,13,4,1},{6,13,9,1},{2,14,2,4},{10,14,1,3},{5,17,11,1},{0,18,3,1}}}
T.glyphs[25351] = {w=18, advance=16, rects={{2,4,2,3},{6,4,2,3},{13,5,2,1},{9,6,5,1},{0,7,11,1},{14,7,2,2},{2,8,2,3},{6,8,2,1},{7,9,8,1},{1,11,4,1},{6,11,9,1},{0,12,4,1},{6,12,2,1},{13,12,2,1},{2,13,2,4},{6,13,9,1},{6,14,2,2},{13,14,2,2},{6,16,9,1},{0,17,3,1},{6,17,2,1},{13,17,2,1}}}
T.glyphs[25353] = {w=18, advance=16, rects={{2,4,2,3},{9,4,2,1},{10,5,1,1},{6,6,9,1},{0,7,7,1},{14,7,1,2},{2,8,2,2},{6,8,1,1},{9,8,1,1},{8,9,2,2},{2,10,3,1},{0,11,16,1},{0,12,4,1},{7,12,2,1},{12,12,2,1},{2,13,2,5},{7,13,1,1},{12,13,1,1},{6,14,3,1},{11,14,2,1},{8,15,4,1},{9,16,4,1},{6,17,4,1},{12,17,3,1},{0,18,3,1},{5,18,2,1},{14,18,1,1}}}
T.glyphs[25361] = {w=18, advance=16, rects={{2,4,2,3},{8,4,1,4},{11,4,1,5},{6,6,1,1},{14,6,1,1},{0,7,7,1},{13,7,2,1},{2,8,2,3},{6,8,3,2},{13,8,1,1},{11,9,3,1},{8,10,1,1},{11,10,1,1},{2,11,3,1},{7,11,2,1},{11,11,2,1},{1,12,3,1},{5,12,4,1},{11,12,4,1},{0,13,4,1},{5,13,1,1},{8,13,1,1},{11,13,1,5},{14,13,1,1},{2,14,2,4},{7,14,2,1},{7,15,1,1},{15,15,1,1},{6,16,2,1},{14,16,2,2},{5,17,2,1},{0,18,3,1},{5,18,1,1},{11,18,4,1}}}
T.glyphs[25377] = {w=18, advance=16, rects={{2,4,2,3},{9,4,2,5},{5,5,1,1},{14,5,1,1},{6,6,1,1},{13,6,2,1},{0,7,8,1},{12,7,2,1},{2,8,2,3},{7,8,1,1},{12,8,1,1},{5,9,10,1},{13,10,2,3},{2,11,3,1},{1,12,3,1},{0,13,4,1},{6,13,9,1},{2,14,2,4},{13,14,2,3},{5,17,10,1},{0,18,3,1},{13,18,2,1}}}
T.glyphs[25380] = {w=18, advance=16, rects={{2,4,2,3},{9,4,2,1},{10,5,1,1},{6,6,10,1},{0,7,6,1},{7,7,1,1},{12,7,2,1},{2,8,2,2},{7,8,2,1},{12,8,1,1},{8,9,2,1},{11,9,2,1},{2,10,3,1},{9,10,3,1},{1,11,4,1},{7,11,3,1},{11,11,3,1},{0,12,4,1},{5,12,3,1},{13,12,3,1},{2,13,2,5},{7,13,2,2},{12,13,1,6},{7,15,1,1},{6,16,2,1},{5,17,2,1},{0,18,3,1},{5,18,1,1}}}
T.glyphs[25384] = {w=18, advance=16, rects={{2,4,2,3},{9,4,2,1},{8,5,2,1},{12,5,1,1},{7,6,2,1},{12,6,2,1},{0,7,9,1},{12,7,3,1},{2,8,2,2},{6,8,9,1},{7,9,1,1},{2,10,13,1},{1,11,3,1},{6,11,1,1},{10,11,1,2},{0,12,4,1},{5,12,2,1},{2,13,2,4},{5,13,11,1},{9,14,3,1},{8,15,2,1},{11,15,2,1},{6,16,3,1},{12,16,2,1},{0,17,3,1},{5,17,2,1},{13,17,3,1}}}
T.glyphs[25386] = {w=18, advance=16, rects={{2,4,1,3},{4,5,6,1},{11,5,5,1},{6,6,1,2},{9,6,1,2},{11,6,1,9},{14,6,1,2},{0,7,4,1},{2,8,1,3},{4,8,6,1},{13,8,2,1},{6,9,1,3},{9,9,1,3},{13,9,1,1},{13,10,2,1},{1,11,3,1},{14,11,1,1},{0,12,3,1},{4,12,6,1},{14,12,2,3},{2,13,1,4},{5,13,2,1},{8,13,2,4},{5,14,1,2},{11,15,4,1},{4,16,2,1},{11,16,1,2},{0,17,3,1},{4,17,1,1},{6,17,3,1}}}
T.glyphs[25442] = {w=18, advance=16, rects={{2,4,2,2},{8,4,1,1},{7,5,7,1},{0,6,5,1},{7,6,1,1},{12,6,1,1},{2,7,2,3},{6,7,1,1},{11,7,1,1},{5,8,10,1},{6,9,1,4},{9,9,2,1},{13,9,2,4},{2,10,3,1},{10,10,1,2},{1,11,3,1},{0,12,4,1},{9,12,2,1},{2,13,2,3},{5,13,11,1},{9,14,2,1},{8,15,2,1},{11,15,1,1},{2,16,1,1},{6,16,3,1},{12,16,2,1},{0,17,3,1},{4,17,3,1},{13,17,2,1}}}
T.glyphs[25454] = {w=18, advance=16, rects={{2,4,2,3},{6,5,9,1},{6,6,1,1},{14,6,1,2},{0,7,7,1},{2,8,2,3},{6,8,9,1},{6,9,1,2},{10,9,2,2},{14,9,1,2},{2,11,3,1},{6,11,10,1},{1,12,6,1},{10,12,2,2},{0,13,4,1},{5,13,2,1},{2,14,2,3},{5,14,10,1},{5,15,1,2},{7,15,2,2},{14,15,1,2},{2,17,4,1},{7,17,8,1},{0,18,3,1},{4,18,1,1},{7,18,2,1},{14,18,1,1}}}
T.glyphs[25481] = {w=18, advance=16, rects={{2,4,2,3},{9,4,2,1},{9,5,7,1},{9,6,2,1},{0,7,5,1},{6,7,9,1},{2,8,2,3},{6,8,1,2},{13,8,2,2},{6,10,9,1},{2,11,3,1},{6,11,1,2},{13,11,2,2},{1,12,3,1},{0,13,4,1},{6,13,9,1},{2,14,2,4},{6,14,1,1},{9,14,2,2},{13,14,2,1},{5,16,11,1},{9,17,2,3},{0,18,3,1}}}
T.glyphs[25488] = {w=18, advance=16, rects={{2,4,2,3},{8,4,1,1},{7,5,2,1},{7,6,8,1},{0,7,8,1},{12,7,2,1},{2,8,2,2},{5,8,2,1},{11,8,2,1},{8,9,2,1},{2,10,7,1},{11,10,4,1},{1,11,3,1},{6,11,1,2},{14,11,1,2},{0,12,4,1},{2,13,2,4},{6,13,4,1},{11,13,4,1},{6,14,1,2},{14,14,1,2},{6,16,9,1},{0,17,3,1},{6,17,1,1},{14,17,1,1}}}
T.glyphs[25490] = {w=18, advance=16, rects={{2,4,2,3},{8,4,1,3},{11,4,1,3},{0,7,9,1},{11,7,5,1},{2,8,2,2},{8,8,1,3},{11,8,1,3},{2,10,3,1},{2,11,7,1},{11,11,4,2},{0,12,4,1},{6,12,3,1},{0,13,1,1},{2,13,2,2},{8,13,1,2},{11,13,1,2},{2,15,7,1},{11,15,5,1},{2,16,2,1},{8,16,1,3},{11,16,1,3},{2,17,1,1},{0,18,3,1}}}
T.glyphs[25506] = {w=18, advance=16, rects={{2,4,2,3},{6,5,9,1},{6,6,1,1},{14,6,1,2},{0,7,7,1},{8,7,1,1},{11,7,2,1},{2,8,2,3},{7,8,2,1},{12,8,2,1},{6,9,2,1},{13,9,2,1},{6,10,1,1},{10,10,1,2},{14,10,1,1},{2,11,3,1},{1,12,15,1},{0,13,4,1},{8,13,4,1},{2,14,2,4},{8,14,1,1},{10,14,1,5},{12,14,1,1},{7,15,1,1},{12,15,2,1},{5,16,2,1},{13,16,2,1},{5,17,1,1},{14,17,2,1},{0,18,3,1}}}
T.glyphs[25509] = {w=18, advance=16, rects={{2,5,2,3},{9,5,2,1},{10,6,1,1},{6,7,9,1},{0,8,6,1},{7,8,2,1},{12,8,2,1},{2,9,2,2},{8,9,1,1},{11,9,2,1},{5,10,11,1},{2,11,3,1},{9,11,1,1},{1,12,4,1},{8,12,2,1},{0,13,4,1},{5,13,11,1},{2,14,2,3},{7,14,2,1},{12,14,1,1},{7,15,6,1},{8,16,6,1},{0,17,3,1},{5,17,4,1},{12,17,3,1}}}
T.glyphs[25511] = {w=18, advance=16, rects={{2,5,2,3},{9,5,2,1},{10,6,1,1},{6,7,9,1},{0,8,7,1},{14,8,1,1},{2,9,2,2},{8,9,2,1},{12,9,1,1},{7,10,2,1},{12,10,3,1},{1,11,6,1},{14,11,1,1},{0,12,4,1},{6,12,9,1},{2,13,2,4},{10,13,1,4},{0,17,4,1},{5,17,11,1}}}
T.glyphs[25512] = {w=18, advance=16, rects={{2,3,2,3},{7,3,2,2},{10,3,1,1},{10,4,2,1},{6,5,2,1},{11,5,1,1},{0,6,16,1},{2,7,2,4},{5,7,2,2},{10,7,2,2},{6,9,9,1},{6,10,1,3},{10,10,2,3},{1,11,4,1},{0,12,4,1},{2,13,2,5},{6,13,9,1},{6,14,1,3},{10,14,2,3},{6,17,10,1},{0,18,3,1},{6,18,1,2}}}
T.glyphs[25513] = {w=18, advance=16, rects={{2,4,2,3},{9,4,2,1},{9,5,1,1},{5,6,10,1},{0,7,5,1},{7,7,2,1},{11,7,2,1},{2,8,2,3},{7,8,1,1},{9,8,2,2},{12,8,1,1},{5,9,2,1},{13,9,2,1},{5,10,11,1},{2,11,3,1},{6,11,1,1},{9,11,2,1},{13,11,1,1},{1,12,4,1},{6,12,8,1},{0,13,4,1},{6,13,1,2},{9,13,2,2},{13,13,1,2},{2,14,2,4},{6,15,8,1},{15,15,1,1},{6,16,1,1},{9,16,2,2},{14,16,2,2},{0,18,3,1},{10,18,5,1}}}
T.glyphs[25551] = {w=18, advance=16, rects={{2,4,2,3},{8,4,1,2},{12,4,1,2},{5,6,11,1},{0,7,5,1},{7,7,2,1},{12,7,1,2},{2,8,2,3},{8,8,1,1},{5,10,10,1},{2,11,5,1},{10,11,1,2},{14,11,1,2},{1,12,3,1},{5,12,2,1},{0,13,4,1},{5,13,10,1},{2,14,2,4},{5,14,2,3},{10,14,1,3},{14,14,1,3},{5,17,10,1},{0,18,3,1},{5,18,2,1},{14,18,1,1}}}
T.glyphs[25552] = {w=18, advance=16, rects={{2,4,2,3},{6,5,8,1},{6,6,2,1},{13,6,1,1},{0,7,14,1},{2,8,2,2},{6,8,2,1},{13,8,1,1},{6,9,8,1},{2,10,3,2},{6,10,2,1},{13,10,1,1},{0,12,4,1},{5,12,11,1},{0,13,1,1},{2,13,2,5},{10,13,1,2},{6,14,2,3},{10,15,5,1},{10,16,1,1},{5,17,1,1},{8,17,3,1},{0,18,3,1},{4,18,2,1},{9,18,7,1}}}
T.glyphs[25554] = {w=18, advance=16, rects={{2,4,1,3},{11,4,4,1},{6,5,7,1},{10,6,1,2},{0,7,5,1},{2,8,2,1},{5,8,11,1},{2,9,1,1},{10,9,1,2},{2,10,3,1},{7,10,2,1},{2,11,6,1},{10,11,5,1},{0,12,4,1},{5,12,2,2},{10,12,1,2},{14,12,1,2},{0,13,1,1},{2,13,1,5},{5,14,10,1},{5,15,2,2},{10,15,1,2},{14,15,1,2},{5,17,10,1},{0,18,3,1},{5,18,2,2},{14,18,1,2}}}
T.glyphs[25644] = {w=18, advance=16, rects={{2,4,1,3},{6,4,2,1},{6,5,1,1},{10,5,4,1},{5,6,4,1},{10,6,2,2},{13,6,1,3},{0,7,6,1},{8,7,1,2},{2,8,1,3},{5,8,2,1},{10,8,1,1},{5,9,1,2},{7,9,4,1},{13,9,3,1},{8,10,1,1},{1,11,14,1},{0,12,3,1},{5,12,1,1},{8,12,1,2},{10,12,1,1},{13,12,2,1},{2,13,1,5},{5,13,2,1},{10,13,2,1},{13,13,1,2},{5,14,4,1},{11,14,1,1},{5,15,1,1},{7,15,2,1},{11,15,2,1},{4,16,2,1},{8,16,1,2},{11,16,3,1},{4,17,1,2},{10,17,2,1},{13,17,2,1},{0,18,3,1},{6,18,5,1},{14,18,2,1}}}
T.glyphs[25670] = {w=18, advance=16, rects={{2,4,2,3},{5,5,10,1},{5,6,2,1},{8,6,1,2},{11,6,1,2},{14,6,1,2},{0,7,7,1},{2,8,2,3},{5,8,10,1},{5,9,2,1},{9,9,2,2},{14,9,1,1},{2,11,3,1},{6,11,9,1},{1,12,4,1},{9,12,2,1},{0,13,4,1},{5,13,11,1},{2,14,2,4},{8,14,2,1},{7,15,2,1},{12,15,1,1},{6,16,2,1},{12,16,2,1},{5,17,10,1},{0,18,3,1},{14,18,1,1}}}
T.glyphs[25671] = {w=18, advance=16, rects={{2,4,1,3},{10,4,5,1},{5,5,8,1},{9,6,1,1},{13,6,2,1},{0,7,5,1},{6,7,1,2},{9,7,2,1},{13,7,1,1},{2,8,2,1},{10,8,1,1},{12,8,2,1},{2,9,1,1},{6,9,2,1},{2,10,3,1},{6,10,9,1},{2,11,5,1},{10,11,1,2},{0,12,4,1},{0,13,1,1},{2,13,1,5},{4,13,12,1},{10,14,1,3},{6,15,1,2},{13,15,2,2},{6,17,9,1},{0,18,3,1},{13,18,2,1}}}
T.glyphs[25674] = {w=18, advance=16, rects={{2,4,1,3},{9,4,2,2},{12,4,1,2},{4,6,4,1},{9,6,1,1},{12,6,2,1},{0,7,4,1},{6,7,2,1},{9,7,7,1},{2,8,1,3},{6,8,4,1},{12,8,1,3},{4,9,1,1},{6,9,1,1},{8,9,2,1},{4,10,6,1},{2,11,13,1},{1,12,3,1},{5,12,2,2},{9,12,1,2},{12,12,1,2},{0,13,3,1},{2,14,1,3},{5,14,3,1},{9,14,6,1},{4,15,2,1},{7,15,1,1},{9,15,1,1},{12,15,1,2},{4,16,1,1},{7,16,3,1},{2,17,3,1},{9,17,7,1},{0,18,3,1},{9,18,1,1}}}
T.glyphs[25720] = {w=18, advance=16, rects={{2,4,2,3},{7,4,2,1},{11,4,2,1},{5,5,11,1},{7,6,2,1},{11,6,2,1},{0,7,5,1},{2,8,2,3},{6,8,8,1},{6,9,1,1},{13,9,1,1},{6,10,8,1},{1,11,6,1},{13,11,1,1},{0,12,4,1},{6,12,8,1},{2,13,2,5},{6,13,1,1},{9,13,2,2},{13,13,1,1},{5,15,11,1},{8,16,4,1},{6,17,3,1},{11,17,3,1},{0,18,3,1},{5,18,2,1},{13,18,3,1}}}
T.glyphs[25745] = {w=18, advance=16, rects={{2,4,1,2},{7,4,1,2},{10,4,1,2},{13,4,1,1},{12,5,2,1},{0,6,16,1},{2,7,2,1},{5,7,2,1},{14,7,2,1},{2,8,1,2},{5,8,1,1},{7,8,9,1},{7,9,1,1},{13,9,1,1},{2,10,3,1},{7,10,7,1},{1,11,3,1},{7,11,1,1},{0,12,3,1},{6,12,9,1},{2,13,1,4},{10,13,1,1},{6,14,9,1},{10,15,1,1},{4,16,12,1},{0,17,3,1},{7,17,4,1}}}
T.glyphs[25758] = {w=18, advance=16, rects={{9,3,2,2},{2,4,2,3},{6,5,9,1},{7,6,2,1},{12,6,1,1},{0,7,16,1},{2,8,2,2},{6,9,9,1},{2,10,3,1},{6,10,1,1},{10,10,1,1},{14,10,1,1},{1,11,4,1},{6,11,9,1},{0,12,4,1},{6,12,1,1},{10,12,1,1},{14,12,1,1},{2,13,2,4},{6,13,9,1},{10,14,1,1},{6,15,9,1},{10,16,1,1},{0,17,3,1},{5,17,11,1}}}
T.glyphs[25773] = {w=18, advance=16, rects={{2,4,2,3},{10,4,5,1},{5,5,9,1},{6,6,1,1},{9,6,2,2},{12,6,2,1},{0,7,5,1},{7,7,1,1},{12,7,1,1},{2,8,2,2},{5,8,11,1},{8,9,5,1},{2,10,3,1},{7,10,1,1},{9,10,2,2},{12,10,3,1},{2,11,5,1},{14,11,2,1},{0,12,15,1},{0,13,1,1},{2,13,2,5},{6,13,1,1},{9,13,2,1},{13,13,2,1},{6,14,9,1},{6,15,1,2},{10,15,1,2},{13,15,2,2},{6,17,9,1},{0,18,3,1},{6,18,1,1},{13,18,2,1}}}
T.glyphs[25805] = {w=18, advance=16, rects={{2,4,1,3},{6,5,8,1},{6,6,2,1},{12,6,2,1},{0,7,5,1},{6,7,8,1},{2,8,1,3},{5,9,4,1},{11,9,4,1},{5,10,1,1},{8,10,1,2},{11,10,1,2},{14,10,1,2},{2,11,4,1},{1,12,3,1},{5,12,4,1},{11,12,4,1},{0,13,3,1},{9,13,2,1},{2,14,1,4},{4,14,12,1},{8,15,4,1},{7,16,1,1},{9,16,4,1},{5,17,2,1},{9,17,2,2},{12,17,3,1},{0,18,3,1},{4,18,2,1},{14,18,2,1}}}
T.glyphs[25806] = {w=18, advance=16, rects={{3,3,1,1},{6,3,1,1},{10,3,1,2},{1,4,8,1},{1,5,3,1},{6,5,1,1},{10,5,6,1},{1,6,7,1},{9,6,2,2},{13,6,1,2},{0,7,1,1},{7,7,1,1},{2,8,4,1},{7,8,2,1},{11,8,2,1},{2,9,1,1},{5,9,1,1},{7,9,1,1},{10,9,4,1},{2,10,6,1},{9,10,2,1},{13,10,2,1},{1,12,13,1},{8,13,1,1},{2,14,12,1},{8,15,1,1},{1,16,14,1},{7,17,2,1},{5,18,4,1}}}
T.glyphs[25830] = {w=18, advance=16, rects={{9,3,1,2},{2,4,1,3},{5,5,10,1},{5,6,1,1},{14,6,1,1},{0,7,5,1},{6,7,9,1},{2,8,1,3},{6,8,1,2},{8,8,4,1},{13,8,2,1},{8,9,1,1},{11,9,1,1},{13,9,1,1},{5,10,1,1},{7,10,2,1},{11,10,3,1},{2,11,4,1},{7,11,1,1},{12,11,2,1},{1,12,3,1},{6,12,6,1},{13,12,2,1},{0,13,3,1},{5,13,2,1},{14,13,2,1},{2,14,1,4},{4,14,10,1},{9,15,2,3},{6,16,2,1},{12,16,1,1},{5,17,2,1},{13,17,2,1},{0,18,3,1},{5,18,1,1},{7,18,3,1},{14,18,1,1}}}
T.glyphs[25903] = {w=18, advance=16, rects={{7,4,2,2},{0,6,16,1},{7,7,2,2},{2,9,11,1},{3,10,2,1},{11,10,2,2},{4,11,2,1},{5,12,1,1},{10,12,2,1},{5,13,2,1},{9,13,2,1},{6,14,4,1},{5,15,6,1},{2,16,5,1},{9,16,5,1},{1,17,3,1},{12,17,3,1}}}
T.glyphs[25910] = {w=18, advance=16, rects={{4,4,2,4},{8,4,2,1},{8,5,1,1},{1,6,1,8},{7,6,2,1},{7,7,9,1},{4,8,5,3},{12,8,2,2},{12,10,1,2},{4,11,2,2},{8,11,1,1},{8,12,2,1},{11,12,2,1},{3,13,3,1},{9,13,3,2},{1,14,5,1},{1,15,1,1},{4,15,2,2},{8,15,5,1},{7,16,3,1},{12,16,3,1},{4,17,4,1},{13,17,3,1}}}
T.glyphs[25913] = {w=18, advance=16, rects={{9,3,1,1},{1,4,5,1},{8,4,2,1},{5,5,1,3},{8,5,8,1},{8,6,1,1},{12,6,2,3},{7,7,2,1},{5,8,4,1},{1,9,6,1},{8,9,1,1},{12,9,1,2},{1,10,2,1},{5,10,1,1},{8,10,2,2},{1,11,1,4},{11,11,2,1},{9,12,3,3},{5,13,1,1},{4,14,2,1},{1,15,4,1},{8,15,2,1},{11,15,2,1},{1,16,2,1},{6,16,3,1},{12,16,3,1},{1,17,1,1},{5,17,2,1},{14,17,1,1}}}
T.glyphs[25915] = {w=18, advance=16, rects={{8,4,2,2},{0,6,7,1},{8,6,1,1},{2,7,2,1},{7,7,9,1},{3,8,1,6},{7,8,2,1},{13,8,2,1},{6,9,3,1},{13,9,1,1},{6,10,1,1},{8,10,1,1},{12,10,2,2},{8,11,2,1},{9,12,1,1},{11,12,2,1},{9,13,3,1},{1,14,6,1},{10,14,2,1},{0,15,6,1},{8,15,5,1},{6,16,3,1},{12,16,3,1},{5,17,2,1},{14,17,1,1}}}
T.glyphs[25918] = {w=18, advance=16, rects={{3,4,2,2},{10,4,1,1},{9,5,2,2},{0,7,8,1},{9,7,7,1},{2,8,2,2},{8,8,2,1},{13,8,2,1},{7,9,3,1},{13,9,1,2},{2,10,6,1},{9,10,1,1},{2,11,2,1},{6,11,1,3},{9,11,2,2},{12,11,2,1},{2,12,1,3},{12,12,1,1},{10,13,3,2},{5,14,2,3},{1,15,2,1},{9,15,4,1},{1,16,1,1},{8,16,2,1},{12,16,3,1},{0,17,1,1},{3,17,3,1},{7,17,2,1},{14,17,2,1}}}
T.glyphs[25928] = {w=18, advance=16, rects={{4,4,1,1},{10,4,1,2},{0,6,8,1},{9,6,7,1},{9,7,2,1},{13,7,2,2},{2,8,1,1},{5,8,2,1},{8,8,3,1},{1,9,2,1},{6,9,5,1},{13,9,1,2},{0,10,2,1},{7,10,1,1},{10,10,1,2},{2,11,1,1},{5,11,2,2},{12,11,2,1},{2,12,2,1},{10,12,3,1},{3,13,3,2},{11,13,2,1},{10,14,3,1},{2,15,2,1},{5,15,2,1},{9,15,2,1},{12,15,2,1},{1,16,2,1},{6,16,1,1},{8,16,2,1},{13,16,2,1},{0,17,2,1},{8,17,1,1},{14,17,2,1}}}
T.glyphs[25932] = {w=18, advance=16, rects={{4,4,4,1},{10,4,1,1},{0,5,7,1},{9,5,2,2},{3,6,2,2},{8,7,8,1},{0,8,10,1},{13,8,1,3},{3,9,2,3},{7,9,3,1},{9,10,2,2},{12,11,2,1},{1,12,6,1},{10,12,1,1},{12,12,1,1},{1,13,1,3},{6,13,1,3},{10,13,3,2},{9,15,5,1},{1,16,9,1},{13,16,2,1},{1,17,1,1},{7,17,2,1},{14,17,2,1}}}
T.glyphs[25937] = {w=18, advance=16, rects={{4,4,1,2},{6,4,1,1},{10,4,1,2},{7,5,1,1},{0,6,8,1},{9,6,2,1},{4,7,1,3},{9,7,7,1},{1,8,1,1},{7,8,1,1},{9,8,1,1},{13,8,2,1},{1,9,2,1},{6,9,4,1},{13,9,1,2},{2,10,5,1},{8,10,2,1},{4,11,1,1},{8,11,3,1},{12,11,2,2},{3,12,3,1},{9,12,2,1},{2,13,5,1},{10,13,3,3},{1,14,2,1},{4,14,1,3},{6,14,2,1},{1,15,1,1},{7,15,1,1},{9,16,2,1},{12,16,2,1},{3,17,2,1},{7,17,3,1},{13,17,2,1},{1,18,3,1},{7,18,1,1},{14,18,1,1}}}
T.glyphs[25968] = {w=18, advance=16, rects={{4,4,1,4},{10,4,2,1},{1,5,2,1},{7,5,1,1},{10,5,1,2},{2,6,1,1},{6,6,2,1},{9,7,7,1},{0,8,8,1},{9,8,2,1},{13,8,2,2},{3,9,4,1},{8,9,3,1},{1,10,2,1},{4,10,1,2},{6,10,5,1},{13,10,1,2},{0,11,2,1},{7,11,1,1},{10,11,1,2},{3,12,1,1},{12,12,2,1},{0,13,8,1},{10,13,4,1},{2,14,1,1},{6,14,2,1},{11,14,2,2},{2,15,2,1},{5,15,2,1},{3,16,4,1},{10,16,4,1},{1,17,4,1},{6,17,5,1},{13,17,2,1},{0,18,3,1},{8,18,1,1},{14,18,2,1}}}
T.glyphs[25972] = {w=18, advance=16, rects={{4,4,1,1},{10,4,1,2},{1,5,8,1},{4,6,1,1},{9,6,7,1},{1,7,7,1},{9,7,2,1},{13,7,2,1},{1,8,1,1},{4,8,1,1},{7,8,2,1},{10,8,1,1},{13,8,1,1},{1,9,7,1},{10,9,4,1},{3,10,3,1},{11,10,2,1},{1,11,2,1},{4,11,4,1},{10,11,5,1},{0,12,2,1},{4,12,1,1},{7,12,1,1},{9,12,2,1},{13,12,2,1},{1,13,14,1},{7,14,2,1},{3,15,1,2},{7,15,7,1},{7,16,2,1},{0,17,16,1}}}
T.glyphs[25991] = {w=18, advance=16, rects={{7,3,1,1},{7,4,2,1},{8,5,1,1},{0,6,16,1},{3,7,2,1},{11,7,2,1},{4,8,1,1},{11,8,1,1},{4,9,2,2},{10,9,2,2},{5,11,2,1},{9,11,2,1},{6,12,1,1},{9,12,1,1},{6,13,4,2},{4,15,3,1},{9,15,3,1},{2,16,3,1},{10,16,5,1},{1,17,2,1},{13,17,2,1}}}
T.glyphs[26007] = {w=18, advance=16, rects={{10,4,1,8},{4,5,1,1},{4,6,3,1},{2,7,1,1},{5,7,3,1},{2,8,3,1},{7,8,1,1},{3,9,3,1},{4,10,3,1},{5,11,1,1},{9,12,7,1},{1,13,14,1},{0,14,6,1},{10,14,1,5}}}
T.glyphs[26012] = {w=18, advance=16, rects={{4,4,2,1},{12,4,2,9},{3,5,3,1},{9,5,1,1},{2,6,2,1},{5,6,2,1},{9,6,2,1},{2,7,1,1},{6,7,2,1},{10,7,1,2},{1,8,2,1},{7,8,1,1},{0,9,7,1},{8,9,1,1},{4,10,1,2},{9,10,2,1},{10,11,1,1},{0,12,8,1},{4,13,1,4},{11,13,5,1},{2,14,1,1},{6,14,8,1},{1,15,1,1},{6,15,2,1},{12,15,2,4},{0,16,2,1},{7,16,1,1},{3,17,2,1},{2,18,3,1}}}
T.glyphs[26029] = {w=18, advance=16, rects={{1,4,1,1},{5,4,1,3},{13,4,3,1},{1,5,3,1},{7,5,7,1},{1,6,1,3},{3,6,1,2},{7,6,1,1},{9,6,2,3},{5,7,3,1},{5,8,1,1},{1,9,15,1},{1,10,1,3},{4,10,2,1},{9,10,2,2},{13,10,1,8},{4,11,3,1},{3,12,5,1},{9,12,1,3},{1,13,3,1},{5,13,1,3},{7,13,1,1},{1,14,2,1},{1,15,1,1},{8,15,2,1},{1,16,8,1},{8,17,1,1}}}
T.glyphs[26032] = {w=18, advance=16, rects={{3,4,2,1},{4,5,1,1},{12,5,3,1},{1,6,7,1},{9,6,6,1},{2,7,1,2},{6,7,1,1},{9,7,1,2},{5,8,2,1},{0,9,10,1},{4,10,1,2},{9,10,7,1},{9,11,1,3},{12,11,2,7},{1,12,7,1},{4,13,1,4},{1,14,2,1},{6,14,1,1},{8,14,2,1},{0,15,2,1},{6,15,4,1},{7,16,2,1},{2,17,3,1},{7,17,1,1}}}
T.glyphs[26041] = {w=18, advance=16, rects={{7,3,1,1},{7,4,2,1},{8,5,1,1},{0,6,16,1},{4,7,2,1},{5,8,1,2},{4,10,10,1},{4,11,2,3},{12,11,2,1},{12,12,1,4},{3,14,2,2},{2,16,2,1},{11,16,2,1},{1,17,2,1},{7,17,5,1},{0,18,2,1}}}
T.glyphs[26049] = {w=18, advance=16, rects={{7,3,1,1},{7,4,2,1},{1,5,14,1},{4,6,1,1},{10,6,2,1},{4,7,2,1},{10,7,1,1},{1,8,14,1},{1,9,1,1},{7,9,1,1},{14,9,1,1},{7,10,2,1},{0,11,16,1},{4,12,2,1},{4,13,9,1},{4,14,1,2},{12,14,1,2},{3,16,1,1},{11,16,2,1},{2,17,1,1},{8,17,5,1},{1,18,1,1}}}
T.glyphs[26059] = {w=18, advance=16, rects={{2,4,2,1},{8,4,1,2},{3,5,1,2},{7,6,9,1},{0,7,8,1},{2,8,1,2},{6,8,2,1},{6,9,9,1},{2,10,4,1},{10,10,2,3},{14,10,1,1},{2,11,1,3},{4,11,2,5},{13,11,2,1},{7,12,2,2},{10,13,5,1},{1,14,2,1},{7,14,1,1},{10,14,2,2},{1,15,1,2},{7,15,2,1},{4,16,8,1},{0,17,1,1},{2,17,3,1},{6,17,1,1},{10,17,6,1}}}
T.glyphs[26080] = {w=18, advance=16, rects={{2,5,13,1},{7,6,2,1},{7,7,1,2},{0,9,16,1},{6,10,2,1},{6,11,1,1},{8,11,2,6},{5,12,2,1},{5,13,1,1},{4,14,2,1},{14,14,2,3},{3,15,2,1},{1,16,3,1},{1,17,1,1},{9,17,6,1}}}
T.glyphs[26082] = {w=18, advance=16, rects={{1,5,6,1},{8,5,7,1},{1,6,2,1},{6,6,1,2},{11,6,2,1},{1,7,1,1},{8,7,2,1},{11,7,1,3},{1,8,6,1},{8,8,1,2},{1,9,2,1},{6,9,1,2},{1,10,1,1},{8,10,8,1},{1,11,6,1},{10,11,2,1},{1,12,2,1},{6,12,1,1},{10,12,3,2},{1,13,1,3},{5,13,1,2},{9,14,4,1},{15,14,1,1},{4,15,3,1},{9,15,1,1},{11,15,2,2},{14,15,2,2},{1,16,4,1},{6,16,1,1},{8,16,2,1},{1,17,2,1},{7,17,2,1},{12,17,3,1},{6,18,2,1}}}
T.glyphs[26085] = {w=18, advance=16, rects={{2,5,12,1},{2,6,2,5},{12,6,2,5},{2,11,12,1},{2,12,2,5},{12,12,2,5},{2,17,12,1},{2,18,2,1},{12,18,2,1}}}
T.glyphs[26086] = {w=18, advance=16, rects={{2,5,12,1},{2,6,2,3},{12,6,2,3},{2,9,12,1},{2,10,2,3},{12,10,2,3},{2,13,12,1},{2,14,2,1},{12,14,2,1},{0,17,16,1}}}
T.glyphs[26087] = {w=18, advance=16, rects={{1,5,2,13},{5,5,10,1},{5,6,2,4},{13,6,2,4},{5,10,10,1},{5,11,2,5},{13,11,2,5},{5,16,10,1},{5,17,2,1},{13,17,2,1}}}
T.glyphs[26102] = {w=18, advance=16, rects={{12,4,2,3},{1,5,5,1},{1,6,1,3},{5,6,1,1},{5,7,11,1},{5,8,1,1},{12,8,2,9},{1,9,5,1},{1,10,1,5},{5,10,1,5},{8,10,1,1},{8,11,2,2},{9,13,1,1},{1,15,5,1},{1,16,1,2},{5,16,1,2},{9,17,4,1}}}
T.glyphs[26126] = {w=18, advance=16, rects={{1,5,5,1},{8,5,7,1},{1,6,2,1},{5,6,1,4},{8,6,1,3},{13,6,2,3},{1,7,1,3},{8,9,7,1},{1,10,5,1},{8,10,1,3},{13,10,2,3},{1,11,2,1},{5,11,1,4},{1,12,1,3},{8,13,7,1},{8,14,1,1},{13,14,2,4},{1,15,5,1},{7,15,2,1},{1,16,2,1},{7,16,1,1},{6,17,2,1},{5,18,2,1},{10,18,5,1},{5,19,1,1}}}
T.glyphs[26131] = {w=18, advance=16, rects={{2,5,12,1},{2,6,2,1},{12,6,2,1},{2,7,12,1},{2,8,2,1},{12,8,2,1},{2,9,12,1},{4,10,2,1},{12,10,2,1},{3,11,2,1},{2,12,13,1},{1,13,3,1},{6,13,1,1},{9,13,2,2},{13,13,2,4},{0,14,2,1},{5,14,2,1},{4,15,2,1},{8,15,2,1},{2,16,3,1},{7,16,2,1},{1,17,2,1},{6,17,2,1},{13,17,1,1},{5,18,2,1},{9,18,5,1}}}
T.glyphs[26143] = {w=18, advance=16, rects={{2,5,12,1},{2,6,2,1},{13,6,1,1},{2,7,12,1},{2,8,2,1},{13,8,1,1},{2,9,12,1},{3,10,1,1},{13,10,1,1},{2,11,2,1},{8,11,1,1},{2,12,13,1},{1,13,2,1},{8,13,1,1},{1,14,1,1},{3,14,12,1},{8,15,1,2},{1,17,15,1}}}
T.glyphs[26144] = {w=18, advance=16, rects={{10,4,1,2},{1,5,4,1},{1,6,1,4},{4,6,1,4},{7,6,8,1},{7,7,1,5},{10,7,1,5},{13,7,2,5},{1,10,4,1},{1,11,1,5},{4,11,1,1},{4,12,12,1},{4,13,1,3},{9,13,3,1},{9,14,1,1},{11,14,1,1},{8,15,2,1},{11,15,2,1},{1,16,4,1},{7,16,2,1},{12,16,2,1},{1,17,1,1},{6,17,2,1},{13,17,2,1},{5,18,2,1},{14,18,1,1}}}
T.glyphs[26159] = {w=18, advance=16, rects={{3,5,10,1},{3,6,1,1},{12,6,1,1},{3,7,10,1},{3,8,1,1},{12,8,1,1},{3,9,10,1},{3,10,1,1},{12,10,1,1},{0,12,16,1},{7,13,2,1},{3,14,2,1},{8,14,7,1},{3,15,1,1},{8,15,1,1},{2,16,4,1},{7,16,2,1},{1,17,2,1},{5,17,11,1},{0,18,2,1}}}
T.glyphs[26174] = {w=18, advance=16, rects={{2,5,12,1},{2,6,2,1},{12,6,2,1},{2,7,12,1},{2,8,2,2},{12,8,2,2},{2,10,12,1},{2,11,2,1},{12,11,2,1},{1,12,2,1},{13,12,2,1},{2,13,2,2},{5,13,2,4},{9,13,1,4},{13,13,1,1},{12,14,2,1},{3,15,1,1},{12,15,1,1},{0,17,16,1}}}
T.glyphs[26202] = {w=18, advance=16, rects={{8,3,2,2},{1,5,4,1},{7,5,7,1},{1,6,1,4},{4,6,1,2},{7,6,1,1},{12,6,1,1},{6,7,2,1},{11,7,2,1},{4,8,11,1},{4,9,1,1},{6,9,2,3},{10,9,1,3},{14,9,1,3},{1,10,4,1},{1,11,1,4},{4,11,1,4},{6,12,9,1},{6,13,2,1},{9,13,3,1},{14,13,1,1},{9,14,1,1},{11,14,1,3},{15,14,1,2},{1,15,4,1},{8,15,2,1},{1,16,1,2},{7,16,2,1},{14,16,2,1},{6,17,2,1},{11,17,4,1},{5,18,2,1}}}
T.glyphs[26222] = {w=18, advance=16, rects={{4,4,2,1},{10,4,2,2},{5,5,1,1},{1,6,14,1},{5,7,2,1},{9,7,2,1},{2,8,2,1},{6,8,1,2},{9,8,1,2},{12,8,2,1},{3,9,1,1},{12,9,1,1},{0,10,16,1},{2,12,12,1},{2,13,2,1},{12,13,2,1},{2,14,12,1},{2,15,2,2},{12,15,2,2},{2,17,12,1},{2,18,2,1},{12,18,2,1}}}
T.glyphs[26223] = {w=18, advance=16, rects={{2,5,12,1},{2,6,2,1},{12,6,2,1},{2,7,12,1},{2,8,2,1},{12,8,2,1},{2,9,12,1},{7,10,1,1},{1,11,14,1},{2,13,12,1},{2,14,2,1},{12,14,2,1},{2,15,12,1},{4,16,2,1},{7,16,2,2},{10,16,2,1},{2,17,3,1},{11,17,4,1},{1,18,2,1},{5,18,4,1},{13,18,2,1}}}
T.glyphs[26242] = {w=18, advance=16, rects={{3,3,1,2},{12,4,3,1},{0,5,8,1},{9,5,5,1},{2,6,1,1},{9,6,1,2},{1,7,2,1},{4,7,1,1},{1,8,7,1},{9,8,7,1},{4,9,1,1},{8,9,2,1},{12,9,1,3},{0,10,9,1},{4,11,1,1},{8,11,1,1},{3,12,10,1},{3,13,1,1},{12,13,1,1},{3,14,10,1},{3,15,1,2},{12,15,1,2},{3,17,10,1},{3,18,1,1},{12,18,1,1}}}
T.glyphs[26263] = {w=18, advance=16, rects={{10,3,1,2},{1,5,14,1},{1,6,1,4},{4,6,2,3},{8,6,1,3},{13,6,1,1},{12,7,2,1},{12,8,1,1},{4,9,12,1},{1,10,5,1},{1,11,1,4},{4,11,2,4},{7,11,8,1},{7,12,1,2},{13,12,2,2},{7,14,8,1},{1,15,5,1},{7,15,1,2},{13,15,2,2},{1,16,1,1},{4,16,2,1},{7,17,8,1},{7,18,1,1},{13,18,2,1}}}
T.glyphs[26292] = {w=18, advance=16, rects={{2,5,12,1},{2,6,2,1},{13,6,1,1},{2,7,12,1},{2,8,2,1},{13,8,1,1},{2,9,12,1},{5,10,1,1},{10,10,1,1},{1,11,14,1},{5,12,1,1},{10,12,1,1},{1,13,14,1},{4,14,2,1},{10,14,2,1},{2,15,12,1},{0,16,2,1},{5,16,6,1},{13,16,3,1},{3,17,3,1},{7,17,2,1},{10,17,3,1},{2,18,2,1},{5,18,4,1},{12,18,2,1}}}
T.glyphs[26354] = {w=18, advance=16, rects={{5,4,2,3},{9,4,2,3},{1,7,14,1},{1,8,2,4},{5,8,2,4},{9,8,2,4},{13,8,2,4},{1,12,14,1},{1,13,2,4},{5,13,2,4},{9,13,2,4},{13,13,2,4},{1,17,14,1},{1,18,2,1},{13,18,2,1}}}
T.glyphs[26356] = {w=18, advance=16, rects={{1,4,14,1},{7,5,2,1},{2,6,12,1},{2,7,1,2},{7,7,2,2},{13,7,1,2},{2,9,12,1},{2,10,1,2},{7,10,2,2},{13,10,1,2},{2,12,12,1},{3,13,1,1},{7,13,1,1},{13,13,1,1},{3,14,2,1},{6,14,2,1},{4,15,3,1},{4,16,6,1},{2,17,3,1},{8,17,8,1},{0,18,3,1}}}
T.glyphs[26366] = {w=18, advance=16, rects={{4,4,2,1},{10,4,2,1},{5,5,1,1},{10,5,1,1},{1,6,14,1},{1,7,1,3},{7,7,2,3},{14,7,1,3},{4,8,1,1},{11,8,1,1},{4,9,2,1},{10,9,2,1},{1,10,14,1},{3,12,10,1},{3,13,1,1},{12,13,1,1},{3,14,10,1},{3,15,1,2},{12,15,1,2},{3,17,10,1},{3,18,1,1},{12,18,1,1}}}
T.glyphs[26367] = {w=18, advance=16, rects={{4,4,1,1},{11,4,1,1},{1,5,14,1},{4,6,1,1},{11,6,1,1},{0,7,16,1},{3,8,2,1},{10,8,3,1},{3,9,3,1},{9,9,2,1},{12,9,1,1},{1,10,2,1},{6,10,1,1},{8,10,1,1},{13,10,1,1},{0,11,2,1},{14,11,2,1},{2,12,12,1},{2,13,2,1},{12,13,2,1},{2,14,12,1},{2,15,2,1},{12,15,2,1},{2,16,12,1},{2,17,2,1},{12,17,2,1}}}
T.glyphs[26368] = {w=18, advance=16, rects={{2,5,12,1},{2,6,2,1},{12,6,2,1},{2,7,12,1},{2,8,2,1},{12,8,2,1},{2,9,12,1},{0,11,16,1},{2,12,1,1},{6,12,2,1},{2,13,13,1},{2,14,1,1},{6,14,2,1},{9,14,2,1},{13,14,1,1},{2,15,6,1},{10,15,1,1},{12,15,2,1},{2,16,1,1},{6,16,2,1},{10,16,3,1},{0,17,14,1},{6,18,4,1},{13,18,3,1}}}
T.glyphs[26377] = {w=18, advance=16, rects={{6,4,1,2},{0,6,16,1},{4,7,2,2},{3,9,11,1},{2,10,3,1},{12,10,2,1},{1,11,13,1},{0,12,2,1},{3,12,2,2},{12,12,2,2},{3,14,11,1},{3,15,2,3},{12,15,2,2},{9,17,5,1}}}
T.glyphs[26379] = {w=18, advance=16, rects={{2,5,5,1},{9,5,6,1},{2,6,1,3},{6,6,1,3},{9,6,1,3},{14,6,1,3},{2,9,5,1},{9,9,6,1},{2,10,1,3},{6,10,1,3},{9,10,1,3},{13,10,2,1},{14,11,1,2},{2,13,5,1},{9,13,6,1},{1,14,2,3},{6,14,1,3},{8,14,2,3},{14,14,1,3},{1,17,1,2},{6,17,3,1},{13,17,2,1},{3,18,6,1},{11,18,4,1}}}
T.glyphs[26381] = {w=18, advance=16, rects={{1,5,5,1},{7,5,8,1},{1,6,2,3},{5,6,1,3},{7,6,1,5},{13,6,2,2},{10,8,4,1},{1,9,5,1},{1,10,2,3},{5,10,1,3},{7,11,8,1},{7,12,1,6},{9,12,1,1},{13,12,2,1},{1,13,5,1},{9,13,2,1},{13,13,1,1},{1,14,2,1},{5,14,1,3},{10,14,1,1},{12,14,2,1},{1,15,1,3},{10,15,3,2},{4,17,2,1},{9,17,2,1},{12,17,3,1},{0,18,2,1},{3,18,3,1},{7,18,3,1},{14,18,2,1}}}
T.glyphs[26395] = {w=18, advance=16, rects={{3,4,1,1},{3,5,2,1},{8,5,7,1},{0,6,7,1},{8,6,1,1},{13,6,2,1},{2,7,1,2},{8,7,7,1},{8,8,1,1},{13,8,2,1},{2,9,13,1},{2,10,3,1},{7,10,1,1},{13,10,2,1},{6,11,2,1},{11,11,3,1},{1,13,14,1},{7,14,2,1},{2,15,12,1},{7,16,2,1},{0,17,16,1}}}
T.glyphs[26397] = {w=18, advance=16, rects={{4,4,1,2},{9,5,6,1},{0,6,8,1},{9,6,2,1},{14,6,1,2},{4,7,1,1},{9,7,1,1},{1,8,7,1},{9,8,6,1},{1,9,1,1},{6,9,2,1},{9,9,2,1},{13,9,2,1},{1,10,7,1},{9,10,1,2},{14,10,1,2},{1,11,1,1},{6,11,2,1},{1,12,7,1},{9,12,6,1},{1,13,1,1},{4,13,1,2},{6,13,2,1},{9,13,1,2},{14,13,1,3},{0,15,10,1},{4,16,1,2},{7,16,2,1},{13,16,2,1},{7,17,1,1},{11,17,4,1}}}
T.glyphs[26399] = {w=18, advance=16, rects={{2,5,1,1},{6,5,1,1},{9,5,6,1},{0,6,11,1},{14,6,1,3},{2,7,1,1},{6,7,2,1},{9,7,2,2},{2,8,5,1},{2,9,1,2},{6,9,1,2},{9,9,6,1},{9,10,2,3},{14,10,1,3},{2,11,5,1},{2,12,1,2},{6,12,1,2},{9,13,6,1},{0,14,11,1},{14,14,1,3},{2,15,2,1},{5,15,2,1},{9,15,1,1},{1,16,2,1},{6,16,4,1},{0,17,2,1},{8,17,2,1},{11,17,4,1},{8,18,1,1}}}
T.glyphs[26410] = {w=18, advance=16, rects={{7,4,2,2},{1,6,14,1},{7,7,2,3},{0,10,16,1},{6,11,4,1},{5,12,5,1},{4,13,2,1},{7,13,2,5},{10,13,2,1},{3,14,2,1},{11,14,2,1},{1,15,3,1},{12,15,3,1},{0,16,2,1},{14,16,2,1}}}
T.glyphs[26411] = {w=18, advance=16, rects={{7,3,2,3},{1,6,14,1},{7,7,2,3},{1,10,14,1},{6,11,4,2},{5,13,1,1},{7,13,2,6},{10,13,1,1},{4,14,1,1},{11,14,1,1},{3,15,1,1},{11,15,2,1},{1,16,2,1},{13,16,2,1},{0,17,2,1},{14,17,2,1}}}
T.glyphs[26412] = {w=18, advance=16, rects={{7,4,2,2},{0,6,16,1},{6,7,4,2},{5,9,6,1},{5,10,1,1},{7,10,2,5},{10,10,1,1},{4,11,1,1},{11,11,1,1},{3,12,2,1},{11,12,2,1},{2,13,2,1},{12,13,2,1},{1,14,2,1},{13,14,2,1},{1,15,1,1},{4,15,8,1},{14,15,1,1},{7,16,2,2}}}
T.glyphs[26415] = {w=18, advance=16, rects={{7,4,2,4},{10,4,2,1},{11,5,2,1},{12,6,1,1},{0,8,16,1},{6,9,4,2},{5,11,1,1},{7,11,2,7},{10,11,1,1},{4,12,2,1},{10,12,2,1},{3,13,2,1},{11,13,2,1},{2,14,2,1},{12,14,2,1},{1,15,2,1},{13,15,2,1},{0,16,2,1},{14,16,2,1}}}
T.glyphs[26426] = {w=18, advance=16, rects={{3,4,1,3},{7,5,6,1},{7,6,2,6},{11,6,2,1},{0,7,6,1},{12,7,1,10},{2,8,2,2},{2,10,3,1},{1,11,3,1},{5,11,1,1},{1,12,1,1},{3,12,1,6},{7,12,1,2},{0,13,2,1},{0,14,1,1},{6,14,2,2},{15,14,1,1},{14,15,2,2},{5,16,2,1},{5,17,1,1},{12,17,3,1}}}
T.glyphs[26432] = {w=18, advance=16, rects={{3,4,2,1},{12,4,1,1},{4,5,3,1},{10,5,2,1},{6,6,5,2},{3,8,4,1},{10,8,3,1},{2,9,2,1},{7,9,2,2},{12,9,2,1},{1,11,14,1},{7,12,2,5},{4,13,1,1},{10,13,2,1},{3,14,2,1},{11,14,2,1},{2,15,2,1},{13,15,2,1},{1,16,1,1},{14,16,1,1},{5,17,4,1}}}
T.glyphs[26435] = {w=18, advance=16, rects={{3,4,1,3},{6,5,9,1},{7,6,1,3},{13,6,2,2},{0,7,6,1},{2,8,2,2},{13,8,1,2},{7,9,2,1},{2,10,3,1},{8,10,1,2},{12,10,2,1},{1,11,3,1},{5,11,1,1},{12,11,1,1},{1,12,1,1},{3,12,1,7},{5,12,2,1},{8,12,2,1},{11,12,2,2},{0,13,2,1},{9,13,1,1},{0,14,1,1},{9,14,3,2},{7,16,3,1},{11,16,2,1},{6,17,2,1},{12,17,3,1},{5,18,2,1},{14,18,1,1}}}
T.glyphs[26438] = {w=18, advance=16, rects={{3,4,1,3},{7,5,8,1},{10,6,2,5},{0,7,7,1},{2,8,2,2},{2,10,3,1},{1,11,15,1},{1,12,1,1},{3,12,1,7},{5,12,1,1},{10,12,2,7},{0,13,2,1}}}
T.glyphs[26448] = {w=18, advance=16, rects={{3,4,1,3},{12,4,2,3},{0,7,16,1},{3,8,1,1},{11,8,3,2},{2,9,2,1},{2,10,4,1},{10,10,4,1},{1,11,3,1},{5,11,2,1},{10,11,1,1},{12,11,2,6},{1,12,1,1},{3,12,1,7},{6,12,1,1},{9,12,2,1},{0,13,2,1},{8,13,2,1},{7,14,2,1},{6,15,2,1},{6,16,1,1},{9,17,4,1}}}
T.glyphs[26463] = {w=18, advance=16, rects={{7,3,2,2},{0,5,16,1},{7,6,2,2},{2,8,12,1},{2,9,1,3},{7,9,2,3},{13,9,1,3},{2,12,12,1},{2,13,1,1},{6,13,4,1},{13,13,1,1},{5,14,6,1},{3,15,2,1},{7,15,2,4},{10,15,2,1},{1,16,3,1},{12,16,3,1},{0,17,2,1},{14,17,2,1}}}
T.glyphs[26464] = {w=18, advance=16, rects={{3,5,1,3},{6,6,9,1},{10,7,2,10},{0,8,7,1},{2,9,2,2},{2,11,4,1},{1,12,3,1},{5,12,1,1},{0,13,2,1},{3,13,1,6},{5,13,2,1},{0,14,1,1},{5,17,11,1}}}
T.glyphs[26465] = {w=18, advance=16, rects={{5,3,2,1},{4,4,2,1},{3,5,10,1},{2,6,4,1},{11,6,2,1},{1,7,3,1},{5,7,2,1},{10,7,2,1},{1,8,2,1},{6,8,4,1},{5,9,6,1},{2,10,4,1},{10,10,4,1},{0,11,3,1},{7,11,2,1},{13,11,2,1},{2,12,12,1},{7,13,2,4},{4,14,1,1},{11,14,1,1},{3,15,2,1},{11,15,3,1},{1,16,3,1},{12,16,3,1},{1,17,1,1},{5,17,4,1},{14,17,1,1}}}
T.glyphs[26469] = {w=18, advance=16, rects={{7,4,2,2},{1,6,14,1},{7,7,2,4},{3,8,2,1},{11,8,2,1},{4,9,1,1},{10,9,2,1},{0,11,16,1},{6,12,4,1},{5,13,5,1},{4,14,2,1},{7,14,2,5},{10,14,2,1},{3,15,2,1},{11,15,2,1},{1,16,2,1},{12,16,3,1},{0,17,2,1},{14,17,2,1}}}
T.glyphs[26494] = {w=18, advance=16, rects={{3,5,1,3},{8,5,2,2},{11,5,1,1},{11,6,2,1},{8,7,1,1},{12,7,1,1},{0,8,6,1},{7,8,2,1},{12,8,2,1},{2,9,2,1},{7,9,1,1},{13,9,2,1},{2,10,3,1},{6,10,2,1},{9,10,2,2},{14,10,2,2},{2,11,5,1},{1,12,3,1},{5,12,1,1},{9,12,1,1},{0,13,2,1},{3,13,1,5},{8,13,2,1},{12,13,1,1},{0,14,1,1},{8,14,1,1},{12,14,2,1},{7,15,2,1},{13,15,1,1},{6,16,9,1},{6,17,4,1},{14,17,1,1}}}
T.glyphs[26495] = {w=18, advance=16, rects={{3,4,1,3},{13,4,2,1},{6,5,9,1},{6,6,2,1},{0,7,8,1},{2,8,2,2},{6,8,2,1},{6,9,9,1},{2,10,3,1},{6,10,4,1},{13,10,2,2},{1,11,3,2},{5,11,3,1},{9,11,1,2},{6,12,2,2},{13,12,1,1},{0,13,2,1},{3,13,1,5},{9,13,2,1},{12,13,2,1},{0,14,1,1},{6,14,1,2},{10,14,3,2},{5,16,2,1},{9,16,4,1},{5,17,1,1},{8,17,2,1},{13,17,2,1},{3,18,3,1},{7,18,2,1},{14,18,1,1}}}
T.glyphs[26497] = {w=18, advance=16, rects={{2,4,2,3},{6,5,8,1},{7,6,1,2},{12,6,1,1},{0,7,6,1},{11,7,2,1},{2,8,2,2},{7,8,2,3},{11,8,1,1},{11,9,4,1},{2,10,3,1},{13,10,2,1},{1,11,5,1},{7,11,3,1},{13,11,1,1},{1,12,3,1},{5,12,1,1},{7,12,1,1},{9,12,1,1},{12,12,2,1},{0,13,4,1},{6,13,2,2},{9,13,2,1},{12,13,1,1},{0,14,1,1},{2,14,2,4},{10,14,3,2},{6,15,1,1},{5,16,2,1},{9,16,5,1},{5,17,1,1},{8,17,2,1},{13,17,2,1},{2,18,3,1},{7,18,2,1},{14,18,1,1}}}
T.glyphs[26500] = {w=18, advance=16, rects={{2,4,2,3},{8,4,1,1},{7,5,2,1},{7,6,8,1},{0,7,8,1},{14,7,1,8},{2,8,2,1},{6,8,1,1},{9,8,1,1},{2,9,3,1},{8,9,2,1},{1,10,5,1},{8,10,1,1},{1,11,3,1},{5,11,1,1},{7,11,2,1},{0,12,4,1},{6,12,2,1},{10,12,1,1},{0,13,1,1},{2,13,2,5},{6,13,6,1},{12,14,1,1},{13,15,2,2},{9,17,5,1}}}
T.glyphs[26505] = {w=18, advance=16, rects={{3,4,1,3},{7,4,8,1},{10,5,2,5},{0,7,6,1},{2,8,2,2},{2,10,3,1},{7,10,8,1},{1,11,3,1},{5,11,1,2},{10,11,2,6},{1,12,1,1},{3,12,1,6},{0,13,2,1},{0,14,1,1},{6,17,10,1}}}
T.glyphs[26512] = {w=18, advance=16, rects={{3,4,1,3},{11,4,4,1},{7,5,7,1},{7,6,1,4},{0,7,6,1},{2,8,2,1},{2,9,3,1},{2,10,4,1},{7,10,9,1},{1,11,3,1},{5,11,1,2},{7,11,1,3},{11,11,2,8},{1,12,1,1},{3,12,1,7},{0,13,2,1},{6,14,2,2},{6,16,1,1},{5,17,2,1},{5,18,1,1}}}
T.glyphs[26522] = {w=18, advance=16, rects={{3,4,1,3},{8,4,1,1},{7,5,2,2},{0,7,6,1},{7,7,9,1},{2,8,2,2},{6,8,2,2},{12,8,2,1},{12,9,1,2},{2,10,3,1},{6,10,3,1},{1,11,5,1},{7,11,2,1},{11,11,2,2},{1,12,1,1},{3,12,1,7},{5,12,1,1},{8,12,1,1},{0,13,2,1},{8,13,2,1},{11,13,1,1},{9,14,3,2},{8,16,5,1},{6,17,3,1},{12,17,3,1},{5,18,2,1},{14,18,2,1}}}
T.glyphs[26524] = {w=18, advance=16, rects={{2,5,12,1},{2,6,1,1},{7,6,2,1},{13,6,1,1},{2,7,12,1},{2,8,1,2},{7,8,2,2},{13,8,1,2},{2,10,12,1},{2,11,1,1},{7,11,2,2},{13,11,1,1},{0,13,16,1},{5,14,5,1},{4,15,2,1},{7,15,2,4},{10,15,2,1},{2,16,3,1},{11,16,3,1},{0,17,3,1},{13,17,3,1}}}
T.glyphs[26564] = {w=18, advance=16, rects={{2,4,2,3},{6,5,10,1},{10,6,2,1},{0,7,6,1},{10,7,1,1},{2,8,2,2},{6,8,9,1},{6,9,2,3},{10,9,1,2},{14,9,1,5},{2,10,3,1},{1,11,4,1},{9,11,3,1},{1,12,3,1},{5,12,3,1},{9,12,4,1},{0,13,4,1},{6,13,2,1},{9,13,1,1},{12,13,1,1},{0,14,1,1},{2,14,2,5},{6,14,3,2},{12,14,3,1},{14,15,1,3},{6,16,2,3},{11,18,4,1}}}
T.glyphs[26576] = {w=18, advance=16, rects={{3,4,2,2},{11,4,2,2},{0,6,16,1},{3,7,2,1},{11,7,2,1},{3,8,10,1},{3,9,2,1},{11,9,2,1},{3,10,10,1},{3,11,2,1},{7,11,2,2},{11,11,2,1},{0,13,16,1},{6,14,4,1},{4,15,2,1},{7,15,2,4},{10,15,2,1},{2,16,3,1},{11,16,3,1},{1,17,2,1},{13,17,2,1}}}
T.glyphs[26579] = {w=18, advance=16, rects={{2,4,2,1},{8,4,1,2},{3,5,2,1},{1,6,1,1},{6,6,7,1},{2,7,1,1},{7,7,2,1},{11,7,2,1},{7,8,1,1},{12,8,1,2},{15,8,1,1},{3,9,2,1},{6,9,2,1},{14,9,2,1},{1,10,8,1},{12,10,3,1},{1,11,2,1},{7,11,2,2},{0,13,16,1},{5,14,6,1},{4,15,2,1},{7,15,2,4},{10,15,2,1},{2,16,2,1},{11,16,3,1},{1,17,2,1},{13,17,3,1}}}
T.glyphs[26597] = {w=18, advance=16, rects={{7,3,2,2},{1,5,14,1},{6,6,4,1},{4,7,2,1},{7,7,2,2},{10,7,2,1},{2,8,2,1},{12,8,2,1},{0,9,16,1},{2,10,2,1},{12,10,2,1},{2,11,12,1},{2,12,2,2},{12,12,2,2},{2,14,12,1},{2,15,2,1},{12,15,2,1},{0,17,16,1}}}
T.glyphs[26631] = {w=18, advance=16, rects={{3,4,1,3},{6,5,9,1},{0,7,6,1},{2,8,2,2},{6,8,10,1},{10,9,2,1},{1,10,4,1},{10,10,1,7},{1,11,3,1},{5,11,1,1},{13,11,1,2},{0,12,2,1},{3,12,1,6},{7,12,1,1},{0,13,1,1},{6,13,2,2},{13,13,2,1},{14,14,1,1},{5,15,2,1},{14,15,2,2},{5,16,1,1},{7,17,4,1}}}
T.glyphs[26639] = {w=18, advance=16, rects={{3,4,1,3},{7,4,2,1},{13,4,1,1},{8,5,1,1},{12,5,2,1},{8,6,2,1},{11,6,2,1},{0,7,16,1},{2,8,2,2},{2,10,3,1},{1,11,5,1},{1,12,1,1},{3,12,1,7},{5,12,1,1},{7,12,8,1},{0,13,2,1},{5,17,11,1}}}
T.glyphs[26657] = {w=18, advance=16, rects={{10,3,1,3},{2,4,2,3},{6,6,10,1},{0,7,6,1},{2,8,2,1},{8,8,1,1},{12,8,1,1},{2,9,3,2},{7,9,2,1},{12,9,2,1},{6,10,2,1},{13,10,2,1},{1,11,3,2},{5,11,4,1},{12,11,1,2},{14,11,1,1},{8,12,1,1},{0,13,4,1},{8,13,2,1},{11,13,2,1},{0,14,1,1},{2,14,2,5},{9,14,3,2},{8,16,5,1},{6,17,3,1},{12,17,3,1},{5,18,2,1},{13,18,3,1}}}
T.glyphs[26679] = {w=18, advance=16, rects={{3,4,1,3},{7,4,2,1},{13,4,1,1},{8,5,1,1},{12,5,2,1},{8,6,2,1},{11,6,2,1},{0,7,15,1},{2,8,2,2},{10,8,1,2},{2,10,3,1},{6,10,9,1},{1,11,5,1},{10,11,1,3},{1,12,1,1},{3,12,1,7},{5,12,1,1},{0,13,2,1},{5,14,11,1},{10,15,1,4}}}
T.glyphs[26680] = {w=18, advance=16, rects={{2,4,2,3},{10,4,1,1},{10,5,2,1},{6,6,10,1},{0,7,6,1},{8,7,2,1},{2,8,2,2},{8,8,1,1},{12,8,2,2},{7,9,2,1},{2,10,3,1},{6,10,7,1},{1,11,11,1},{14,11,1,1},{1,12,3,1},{5,12,1,1},{9,12,2,1},{13,12,2,1},{0,13,4,1},{8,13,2,1},{12,13,2,1},{0,14,1,1},{2,14,2,5},{6,14,3,1},{11,14,2,1},{5,15,2,1},{10,15,3,1},{9,16,2,1},{12,16,2,1},{7,17,3,1},{13,17,2,1},{6,18,2,1},{14,18,2,1}}}
T.glyphs[26681] = {w=18, advance=16, rects={{2,4,2,3},{7,5,8,1},{7,6,1,2},{13,6,2,2},{0,7,6,1},{2,8,2,2},{7,8,8,1},{7,9,1,2},{13,9,2,2},{2,10,3,1},{1,11,5,1},{7,11,8,1},{1,12,3,1},{5,12,1,1},{7,12,1,5},{9,12,2,1},{0,13,4,1},{10,13,1,1},{13,13,2,1},{0,14,1,1},{2,14,2,5},{10,14,4,1},{11,15,2,1},{9,16,2,1},{12,16,2,1},{6,17,4,1},{13,17,2,1},{7,18,1,1},{14,18,1,1}}}
T.glyphs[26684] = {w=18, advance=16, rects={{2,3,2,3},{8,3,2,1},{8,4,1,1},{7,5,8,1},{0,6,6,1},{7,6,2,1},{13,6,2,1},{2,7,2,2},{6,7,1,2},{8,7,2,1},{12,7,2,1},{9,8,4,2},{2,9,3,1},{1,10,3,3},{5,10,5,1},{12,10,3,1},{5,11,2,1},{14,11,2,1},{0,13,4,1},{7,13,8,1},{0,14,1,1},{2,14,2,5},{7,14,1,3},{13,14,2,3},{7,17,8,1},{7,18,1,1},{13,18,2,1}}}
T.glyphs[26694] = {w=18, advance=16, rects={{2,4,2,3},{6,5,10,1},{6,6,2,1},{0,7,7,1},{2,8,2,2},{6,8,1,3},{8,8,7,1},{11,9,1,2},{2,10,3,1},{1,11,3,2},{5,11,2,1},{8,11,7,1},{6,12,1,2},{11,12,1,2},{0,13,4,1},{0,14,1,1},{2,14,2,5},{6,14,10,1},{6,15,1,2},{6,17,10,1}}}
T.glyphs[26696] = {w=18, advance=16, rects={{7,3,1,1},{7,4,2,1},{1,5,14,1},{1,6,1,1},{14,6,1,1},{6,7,1,1},{0,8,16,1},{4,9,1,1},{10,9,2,1},{4,10,4,1},{9,10,2,1},{5,11,7,1},{1,12,5,1},{11,12,3,1},{7,13,2,1},{0,14,16,1},{5,15,6,1},{2,16,3,1},{7,16,2,3},{10,16,4,1},{1,17,2,1},{13,17,2,1}}}
T.glyphs[26723] = {w=18, advance=16, rects={{2,4,2,3},{10,4,1,5},{6,5,1,1},{14,5,1,1},{6,6,2,1},{13,6,2,1},{0,7,6,1},{7,7,2,1},{13,7,1,1},{2,8,2,2},{6,9,9,1},{2,10,3,1},{14,10,1,3},{1,11,5,1},{1,12,3,1},{5,12,1,1},{0,13,4,1},{6,13,9,1},{0,14,1,1},{2,14,2,5},{14,14,1,3},{5,17,10,1},{14,18,1,1}}}
T.glyphs[26816] = {w=18, advance=16, rects={{2,4,2,3},{9,4,2,1},{9,5,3,1},{8,6,2,1},{11,6,2,1},{0,7,6,1},{7,7,2,1},{12,7,2,1},{2,8,2,2},{6,8,2,1},{13,8,2,1},{6,9,1,1},{14,9,2,1},{2,10,3,1},{7,10,7,1},{1,11,5,1},{1,12,3,1},{6,12,2,2},{9,12,1,1},{13,12,1,2},{0,13,4,1},{9,13,2,1},{0,14,1,1},{2,14,2,5},{7,14,1,2},{10,14,1,2},{12,14,2,1},{12,15,1,1},{11,16,2,1},{5,17,11,1}}}
T.glyphs[26893] = {w=18, advance=16, rects={{2,4,2,3},{10,4,1,2},{5,6,10,1},{0,7,6,1},{10,7,1,2},{2,8,2,2},{6,9,9,1},{2,10,3,1},{6,10,2,1},{13,10,2,1},{1,11,14,1},{1,12,7,1},{13,12,2,1},{0,13,4,1},{6,13,9,1},{0,14,1,1},{2,14,2,5},{6,14,2,3},{13,14,2,3},{5,17,11,1}}}
T.glyphs[27010] = {w=18, advance=16, rects={{2,4,1,3},{5,5,4,1},{10,5,5,1},{5,6,1,1},{8,6,1,2},{12,6,2,2},{0,7,6,1},{10,7,1,4},{2,8,1,2},{5,8,4,1},{12,8,1,3},{5,9,1,2},{8,9,1,2},{1,10,3,1},{1,11,8,1},{10,11,5,1},{1,12,2,1},{5,12,1,4},{8,12,1,1},{12,12,1,1},{0,13,1,2},{2,13,1,7},{7,13,2,1},{11,13,2,3},{8,14,1,1},{7,15,2,1},{15,15,1,2},{5,16,6,1},{12,16,1,2},{5,17,1,1},{9,17,2,1},{14,17,2,1},{8,18,2,1},{12,18,3,1},{8,19,1,1}}}
T.glyphs[27133] = {w=18, advance=16, rects={{2,4,2,3},{8,4,2,1},{11,4,1,1},{5,5,11,1},{8,6,2,1},{11,6,1,1},{0,7,15,1},{2,8,2,2},{6,8,1,1},{8,8,2,1},{11,8,1,1},{14,8,1,1},{6,9,9,1},{1,10,4,1},{6,10,1,1},{8,10,2,1},{11,10,1,1},{14,10,1,1},{1,11,14,1},{0,12,4,1},{0,13,1,1},{2,13,2,6},{6,13,9,1},{6,14,1,1},{13,14,2,1},{6,15,9,1},{6,16,1,1},{13,16,2,1},{6,17,9,1},{6,18,1,1},{13,18,2,1}}}
T.glyphs[27169] = {w=18, advance=16, rects={{2,4,2,4},{8,4,1,2},{12,4,1,2},{5,6,11,1},{8,7,1,2},{12,7,1,2},{0,8,6,1},{2,9,2,2},{6,9,9,1},{6,10,2,1},{13,10,2,1},{1,11,4,1},{6,11,9,1},{1,12,7,1},{13,12,2,1},{0,13,4,1},{6,13,9,1},{0,14,1,1},{2,14,2,5},{10,14,1,1},{5,15,11,1},{9,16,3,1},{7,17,2,1},{12,17,2,1},{5,18,2,1},{13,18,3,1}}}
T.glyphs[27178] = {w=18, advance=16, rects={{3,4,1,3},{8,4,1,2},{12,4,1,2},{6,6,9,1},{0,7,6,1},{8,7,1,2},{12,7,1,2},{2,8,2,3},{5,9,11,1},{10,10,1,1},{1,11,4,1},{6,11,9,1},{1,12,7,1},{10,12,1,1},{14,12,1,1},{0,13,2,1},{3,13,1,6},{6,13,9,1},{0,14,1,1},{6,14,2,1},{10,14,1,1},{14,14,1,1},{6,15,9,1},{8,16,2,1},{11,16,2,1},{6,17,3,1},{12,17,3,1},{5,18,2,1},{14,18,2,1}}}
T.glyphs[27225] = {w=18, advance=16, rects={{2,4,2,3},{10,4,1,1},{13,4,1,1},{5,5,9,1},{8,6,2,1},{11,6,2,1},{14,6,1,1},{0,7,5,1},{6,7,1,1},{8,7,1,1},{11,7,4,1},{2,8,2,2},{6,8,2,1},{12,8,2,1},{6,9,9,1},{1,10,5,1},{14,10,2,1},{1,11,4,1},{6,11,8,1},{1,12,3,1},{6,12,1,2},{13,12,1,2},{0,13,4,1},{0,14,1,1},{2,14,2,5},{6,14,8,1},{7,15,2,1},{12,15,1,1},{8,16,1,1},{11,16,2,1},{5,17,11,1}}}
T.glyphs[27425] = {w=18, advance=16, rects={{7,4,2,1},{1,5,1,1},{7,5,1,1},{1,6,2,1},{6,6,9,1},{2,7,2,1},{6,7,1,1},{13,7,2,1},{3,8,1,1},{5,8,2,1},{9,8,1,2},{13,8,1,2},{5,9,1,1},{3,10,1,2},{9,10,2,1},{8,11,3,1},{2,12,2,1},{8,12,1,1},{10,12,1,1},{2,13,1,1},{7,13,2,1},{11,13,1,1},{1,14,2,1},{7,14,1,1},{11,14,2,1},{0,15,2,1},{6,15,2,1},{12,15,2,1},{1,16,1,1},{4,16,2,1},{13,16,2,1},{4,17,1,1},{14,17,1,1}}}
T.glyphs[27490] = {w=18, advance=16, rects={{8,4,2,4},{3,6,2,11},{8,8,7,1},{8,9,2,8},{0,17,16,1}}}
T.glyphs[27491] = {w=18, advance=16, rects={{1,5,14,1},{8,6,2,5},{3,8,1,9},{8,11,7,1},{8,12,2,5},{0,17,16,1}}}
T.glyphs[27492] = {w=18, advance=16, rects={{5,4,1,4},{9,4,2,4},{14,6,1,1},{1,7,2,9},{12,7,3,1},{5,8,8,1},{5,9,1,6},{9,9,3,1},{9,10,2,5},{14,13,2,3},{5,15,6,1},{1,16,7,1},{9,16,2,1},{14,16,1,1},{0,17,4,1},{10,17,5,1}}}
T.glyphs[27493] = {w=18, advance=16, rects={{8,4,1,2},{3,5,2,4},{8,6,6,1},{8,7,1,2},{0,9,16,1},{7,11,2,4},{4,12,1,1},{13,12,1,1},{3,13,2,1},{12,13,2,1},{2,14,2,1},{10,14,3,1},{1,15,1,1},{9,15,2,1},{6,16,4,1},{2,17,6,1},{1,18,3,1}}}
T.glyphs[27498] = {w=18, advance=16, rects={{1,4,14,1},{7,5,2,1},{5,6,3,1},{3,7,6,1},{10,7,3,1},{1,8,4,1},{7,8,2,2},{11,8,4,1},{0,9,3,1},{13,9,2,1},{1,11,14,1},{7,12,2,2},{3,13,1,1},{3,14,2,4},{7,14,7,1},{7,15,2,3},{0,18,16,1}}}
T.glyphs[27515] = {w=18, advance=16, rects={{0,5,16,1},{3,6,2,1},{9,6,2,4},{3,7,1,1},{3,8,5,1},{14,8,1,1},{2,9,2,1},{7,9,1,1},{13,9,2,1},{2,10,1,1},{6,10,2,2},{9,10,4,1},{1,11,3,1},{9,11,3,1},{1,12,1,1},{3,12,2,1},{6,12,1,1},{9,12,2,5},{0,13,1,1},{4,13,3,1},{14,13,2,3},{4,14,2,1},{4,15,1,1},{3,16,2,1},{14,16,1,1},{1,17,3,1},{10,17,5,1},{1,18,1,1}}}
T.glyphs[27531] = {w=18, advance=16, rects={{8,4,2,3},{11,4,1,1},{0,5,7,1},{12,5,2,1},{2,6,2,2},{9,7,1,1},{2,8,4,1},{8,8,7,1},{2,9,1,1},{5,9,8,1},{1,10,2,1},{5,10,1,2},{9,10,1,1},{1,11,1,1},{8,11,7,1},{1,12,11,1},{0,13,1,1},{3,13,2,2},{9,13,2,1},{13,13,2,1},{9,14,5,1},{3,15,1,1},{9,15,3,1},{14,15,2,2},{2,16,2,1},{7,16,5,1},{1,17,2,1},{5,17,3,1},{11,17,2,1},{14,17,1,1},{1,18,1,1},{12,18,3,1}}}
T.glyphs[27573] = {w=18, advance=16, rects={{4,4,3,1},{1,5,5,1},{8,5,6,1},{1,6,2,2},{8,6,2,2},{12,6,2,3},{1,8,6,1},{8,8,1,1},{1,9,2,3},{7,9,2,1},{13,9,3,1},{7,10,1,1},{7,11,8,1},{1,12,6,1},{8,12,1,1},{13,12,1,1},{1,13,2,2},{8,13,2,1},{12,13,2,1},{9,14,1,1},{11,14,2,1},{1,15,6,1},{9,15,3,1},{0,16,4,1},{9,16,4,1},{1,17,2,2},{7,17,3,1},{12,17,3,1},{6,18,2,1},{14,18,2,1}}}
T.glyphs[27585] = {w=18, advance=16, rects={{3,4,1,1},{1,5,7,1},{9,5,5,1},{1,6,2,1},{6,6,2,2},{9,6,1,2},{13,6,1,3},{1,7,1,1},{1,8,9,1},{1,9,1,1},{6,9,3,1},{13,9,3,1},{1,10,7,1},{1,11,1,1},{6,11,9,1},{9,12,1,2},{13,12,2,1},{1,13,7,1},{13,13,1,1},{3,14,2,2},{9,14,2,1},{12,14,2,1},{10,15,3,2},{1,16,7,1},{0,17,5,1},{8,17,3,1},{12,17,3,1},{7,18,2,1},{14,18,2,1}}}
T.glyphs[27599] = {w=18, advance=16, rects={{3,4,2,1},{3,5,13,1},{2,6,2,1},{1,7,2,1},{0,8,2,1},{3,8,11,1},{3,9,1,3},{7,9,1,2},{12,9,2,3},{8,11,1,1},{0,12,16,1},{2,13,2,2},{6,13,2,1},{12,13,2,1},{7,14,1,1},{12,14,1,2},{2,15,1,1},{7,15,2,1},{2,16,13,1},{11,17,2,1},{8,18,5,1}}}
T.glyphs[27604] = {w=18, advance=16, rects={{1,4,2,5},{8,4,1,6},{14,6,1,1},{13,7,2,1},{12,8,2,1},{1,9,6,1},{11,9,2,1},{1,10,2,6},{8,10,4,1},{8,11,3,1},{8,12,2,1},{8,13,1,3},{14,13,2,3},{6,14,1,1},{4,15,3,1},{1,16,4,1},{8,16,2,1},{14,16,1,1},{1,17,2,1},{8,17,7,1}}}
T.glyphs[27627] = {w=18, advance=16, rects={{7,3,1,1},{7,4,2,1},{0,5,16,1},{3,7,10,1},{3,8,1,1},{12,8,1,1},{3,9,10,1},{1,11,14,1},{1,12,1,1},{7,12,6,1},{14,12,1,1},{2,13,7,1},{6,14,8,1},{2,15,6,1},{6,16,10,1},{0,17,9,1},{14,17,1,1},{7,18,8,1}}}
T.glyphs[27668] = {w=18, advance=16, rects={{3,4,2,1},{3,5,12,1},{2,6,2,1},{2,7,1,1},{1,8,13,1},{1,9,1,1},{0,10,2,1},{0,11,1,1},{2,11,11,1},{12,12,1,4},{15,14,1,1},{14,15,2,1},{12,16,4,1},{13,17,2,1}}}
T.glyphs[27700] = {w=18, advance=16, rects={{7,4,2,4},{13,6,1,1},{12,7,2,1},{1,8,5,1},{7,8,3,1},{11,8,2,1},{4,9,2,2},{7,9,5,1},{7,10,4,1},{4,11,1,1},{7,11,2,6},{10,11,1,1},{3,12,2,1},{10,12,2,1},{2,13,2,1},{11,13,2,1},{2,14,1,1},{12,14,2,1},{1,15,2,1},{13,15,2,1},{1,16,1,1},{14,16,1,1},{4,17,4,1}}}
T.glyphs[27704] = {w=18, advance=16, rects={{5,4,2,1},{6,5,4,1},{8,6,2,1},{2,7,7,1},{7,8,2,1},{13,8,2,1},{7,9,3,1},{11,9,3,1},{1,10,5,1},{7,10,5,1},{4,11,2,1},{7,11,4,1},{4,12,1,1},{7,12,2,5},{10,12,2,1},{3,13,2,1},{11,13,2,1},{2,14,2,1},{12,14,2,1},{1,15,2,1},{13,15,2,1},{0,16,2,1},{14,16,1,1},{4,17,5,1}}}
T.glyphs[27714] = {w=18, advance=16, rects={{7,4,2,3},{11,4,2,1},{0,7,16,1},{7,8,2,2},{2,9,2,1},{3,10,2,1},{7,10,3,2},{13,10,1,1},{4,11,1,1},{12,11,1,1},{6,12,6,1},{4,13,5,1},{10,13,2,1},{3,14,2,1},{7,14,2,4},{11,14,2,1},{1,15,3,1},{11,15,3,1},{1,16,1,1},{13,16,2,1},{14,17,1,1},{4,18,4,1}}}
T.glyphs[27735] = {w=18, advance=16, rects={{1,4,2,1},{2,5,2,1},{5,5,10,1},{3,6,1,1},{9,6,2,5},{0,8,2,1},{1,9,3,1},{2,10,2,1},{5,11,11,1},{9,12,2,7},{2,13,2,2},{1,15,2,2},{1,17,1,1}}}
T.glyphs[27744] = {w=18, advance=16, rects={{1,4,2,1},{9,4,2,3},{2,5,2,1},{3,6,1,1},{5,6,2,2},{9,7,6,1},{0,8,2,1},{5,8,10,1},{1,9,2,1},{4,9,4,1},{9,9,2,3},{13,9,2,3},{2,10,1,1},{5,10,2,7},{2,12,2,2},{9,12,5,1},{9,13,2,2},{14,13,2,3},{2,14,1,1},{1,15,2,3},{14,16,1,1},{6,17,9,1},{1,18,1,1}}}
T.glyphs[27745] = {w=18, advance=16, rects={{1,4,2,1},{1,5,3,1},{5,5,10,1},{3,6,1,1},{0,8,2,1},{1,9,2,1},{4,9,12,1},{2,10,2,1},{7,10,1,1},{6,11,2,2},{2,12,2,2},{6,13,9,1},{2,14,1,2},{13,14,1,2},{1,16,2,2},{12,16,2,1},{8,17,6,1},{1,18,1,1}}}
T.glyphs[27785] = {w=18, advance=16, rects={{1,4,1,1},{1,5,3,1},{5,5,10,1},{3,6,1,1},{5,6,1,2},{13,6,2,2},{0,8,2,1},{1,9,2,1},{7,9,6,1},{2,10,1,1},{7,10,1,2},{11,10,2,7},{2,12,2,2},{6,12,2,3},{2,14,1,1},{14,14,2,3},{1,15,2,2},{5,15,2,1},{4,16,3,1},{1,17,1,1},{4,17,1,1},{11,17,4,1}}}
T.glyphs[27809] = {w=18, advance=16, rects={{1,4,1,1},{1,5,3,1},{7,5,6,1},{3,6,1,1},{7,6,1,1},{12,6,1,1},{6,7,2,1},{12,7,2,1},{0,8,2,1},{6,8,1,1},{12,8,4,1},{1,9,2,1},{5,9,1,1},{2,10,1,1},{5,11,9,1},{2,12,2,2},{6,12,2,1},{12,12,2,1},{7,13,2,1},{11,13,2,1},{1,14,2,2},{8,14,4,2},{1,16,1,2},{6,16,8,1},{4,17,3,1},{13,17,2,1}}}
T.glyphs[27833] = {w=18, advance=16, rects={{1,4,2,1},{9,4,2,2},{2,5,2,1},{3,6,1,1},{5,6,10,1},{5,7,1,4},{9,7,2,4},{14,7,1,4},{0,8,2,1},{1,9,2,1},{2,10,1,1},{5,11,10,1},{2,12,1,1},{5,12,1,4},{9,12,2,4},{14,12,1,4},{2,13,2,1},{2,14,1,1},{1,15,2,2},{5,16,10,1},{1,17,1,1},{5,17,1,1},{14,17,1,1}}}
T.glyphs[27835] = {w=18, advance=16, rects={{1,4,2,1},{8,4,2,1},{2,5,2,1},{8,5,1,1},{3,6,1,1},{7,6,2,1},{12,6,1,1},{6,7,2,1},{12,7,2,1},{0,8,2,1},{5,8,2,1},{13,8,2,1},{1,9,2,1},{5,9,10,1},{2,10,2,1},{14,10,2,1},{2,12,2,2},{5,12,9,1},{5,13,2,3},{13,13,1,3},{2,14,1,1},{1,15,2,2},{5,16,9,1},{1,17,1,1},{5,17,2,1},{13,17,1,1}}}
T.glyphs[27839] = {w=18, advance=16, rects={{1,4,2,1},{2,5,2,1},{6,5,7,1},{3,6,1,1},{6,6,2,3},{12,6,1,2},{0,8,2,1},{12,8,2,1},{1,9,2,1},{5,9,2,1},{12,9,4,1},{2,10,1,1},{5,10,1,1},{6,11,8,1},{2,12,2,2},{6,12,1,4},{13,12,1,4},{2,14,1,2},{1,16,2,2},{6,16,8,1},{6,17,1,1},{13,17,1,1}}}
T.glyphs[27861] = {w=18, advance=16, rects={{1,4,1,1},{9,4,2,3},{2,5,2,1},{3,6,1,1},{5,7,10,1},{0,8,2,1},{9,8,2,3},{1,9,2,1},{2,10,1,1},{4,11,12,1},{2,12,2,2},{8,12,2,1},{8,13,1,1},{2,14,1,1},{7,14,2,1},{11,14,2,1},{1,15,2,1},{6,15,2,1},{12,15,2,1},{1,16,1,2},{5,16,2,1},{10,16,5,1},{5,17,10,1}}}
T.glyphs[27873] = {w=18, advance=16, rects={{1,4,1,1},{6,4,2,1},{2,5,2,1},{6,5,9,1},{3,6,1,1},{5,6,2,1},{13,6,2,2},{4,7,2,1},{0,8,2,1},{4,8,8,1},{13,8,1,6},{1,9,2,1},{5,9,2,3},{10,9,2,3},{2,10,1,1},{2,12,1,3},{5,12,7,1},{5,13,2,4},{9,14,7,1},{1,15,2,3},{14,15,2,1},{14,16,1,1},{6,17,9,1},{1,18,1,1}}}
T.glyphs[27874] = {w=18, advance=16, rects={{1,4,1,1},{10,4,1,2},{2,5,2,1},{3,6,1,1},{5,6,11,1},{0,7,2,1},{5,7,2,2},{10,7,1,2},{14,7,1,1},{1,8,2,1},{2,9,1,1},{5,9,10,1},{5,10,4,1},{13,10,1,1},{2,11,1,3},{5,11,1,4},{8,11,1,1},{12,11,2,2},{8,12,2,1},{9,13,1,1},{11,13,2,1},{1,14,2,2},{9,14,3,1},{4,15,2,1},{9,15,4,1},{1,16,1,2},{3,16,2,1},{7,16,3,1},{12,16,3,1},{3,17,1,1},{6,17,2,1},{13,17,3,1}}}
T.glyphs[27880] = {w=18, advance=16, rects={{1,4,1,1},{9,4,1,1},{1,5,3,1},{9,5,2,1},{3,6,1,1},{5,6,10,1},{9,7,2,4},{0,8,2,1},{1,9,2,1},{2,10,1,1},{5,11,10,1},{2,12,1,2},{9,12,2,5},{1,14,2,2},{1,16,1,2},{4,17,12,1}}}
T.glyphs[27934] = {w=18, advance=16, rects={{1,4,1,1},{2,5,13,1},{3,6,3,1},{14,6,1,12},{4,7,2,1},{0,8,2,1},{4,8,9,1},{1,9,2,1},{4,9,2,10},{2,10,1,1},{7,11,6,1},{2,12,1,2},{7,12,2,1},{11,12,2,3},{7,13,1,2},{1,14,2,3},{7,15,6,1},{7,16,2,1},{1,17,1,2},{10,18,5,1}}}
T.glyphs[27963] = {w=18, advance=16, rects={{1,4,1,1},{10,4,5,1},{1,5,3,1},{5,5,9,1},{3,6,1,1},{9,6,2,2},{0,8,2,1},{4,8,12,1},{1,9,2,1},{9,9,2,3},{2,10,2,1},{2,12,2,2},{5,12,10,1},{5,13,2,3},{13,13,2,3},{2,14,1,2},{1,16,2,2},{5,16,10,1},{5,17,2,1},{13,17,2,1},{1,18,1,1}}}
T.glyphs[27966] = {w=18, advance=16, rects={{1,4,2,1},{10,4,5,1},{2,5,2,1},{5,5,9,1},{3,6,1,1},{5,6,1,8},{11,7,4,1},{0,8,2,1},{8,8,6,1},{1,9,2,1},{8,9,1,7},{11,9,1,2},{2,10,1,1},{14,10,1,1},{11,11,3,1},{2,12,1,2},{11,12,2,1},{12,13,1,1},{1,14,2,2},{4,14,2,2},{12,14,2,1},{10,15,2,1},{13,15,2,1},{1,16,1,2},{3,16,2,1},{8,16,3,1},{14,16,1,1},{3,17,1,1},{8,17,1,1}}}
T.glyphs[27969] = {w=18, advance=16, rects={{1,4,1,1},{9,4,1,1},{1,5,3,1},{9,5,2,1},{3,6,12,1},{7,7,2,1},{0,8,2,1},{5,8,3,1},{12,8,1,1},{1,9,2,1},{5,9,9,1},{2,10,1,4},{14,10,1,1},{9,11,1,7},{12,11,1,6},{6,12,1,2},{1,14,2,3},{5,14,2,2},{15,14,1,2},{4,16,2,1},{14,16,2,1},{1,17,1,1},{3,17,2,1},{12,17,3,1}}}
T.glyphs[27973] = {w=18, advance=16, rects={{1,4,2,1},{8,4,2,3},{11,4,1,1},{2,5,2,1},{12,5,1,1},{3,6,1,1},{8,7,7,1},{0,8,2,1},{5,8,7,1},{1,9,2,1},{8,9,2,1},{2,10,1,1},{7,10,8,1},{4,11,9,1},{9,12,1,1},{13,12,1,1},{2,13,2,2},{9,13,2,1},{12,13,2,1},{9,14,3,1},{14,14,2,2},{2,15,1,1},{8,15,4,1},{1,16,2,2},{5,16,4,1},{10,16,3,1},{14,16,1,1},{4,17,3,1},{12,17,3,1},{1,18,1,1}}}
T.glyphs[27979] = {w=18, advance=16, rects={{1,4,1,1},{14,4,1,14},{1,5,2,1},{4,5,6,1},{11,5,2,10},{2,6,4,1},{9,6,1,8},{4,7,2,5},{7,7,1,5},{0,8,1,1},{1,9,1,1},{1,10,2,1},{2,11,1,1},{4,12,4,2},{2,13,1,2},{6,14,2,2},{1,15,2,2},{5,16,2,1},{8,16,1,1},{1,17,1,2},{4,17,2,1},{9,17,1,1},{3,18,1,1},{10,18,5,1}}}
T.glyphs[28014] = {w=18, advance=16, rects={{1,5,1,1},{10,5,5,1},{1,6,12,1},{3,7,1,1},{5,7,1,1},{8,7,2,1},{12,7,2,1},{0,8,2,1},{6,8,1,1},{9,8,1,1},{12,8,1,1},{1,9,2,1},{2,10,1,1},{5,10,9,1},{11,11,3,1},{2,12,1,2},{10,12,2,1},{4,13,12,1},{1,14,2,2},{9,14,2,3},{1,16,1,2},{6,17,5,1}}}
T.glyphs[28040] = {w=18, advance=16, rects={{1,5,1,1},{5,5,1,1},{9,5,2,5},{13,5,2,1},{1,6,3,1},{5,6,2,1},{12,6,3,1},{3,7,1,1},{6,7,2,1},{12,7,2,1},{7,8,1,1},{0,9,2,1},{2,10,1,1},{5,10,10,1},{5,11,2,1},{13,11,2,1},{2,12,1,2},{5,12,10,1},{5,13,1,1},{13,13,2,1},{1,14,2,2},{5,14,10,1},{5,15,1,3},{13,15,2,2},{1,16,1,2},{10,17,5,1}}}
T.glyphs[28072] = {w=18, advance=16, rects={{1,4,2,1},{9,4,1,6},{2,5,5,1},{14,5,1,1},{6,6,1,3},{13,6,1,1},{11,7,2,1},{0,8,2,1},{11,8,1,1},{2,9,1,1},{4,9,3,1},{4,10,1,1},{8,10,8,1},{3,11,2,1},{9,11,1,4},{11,11,2,1},{3,12,4,1},{12,12,1,1},{2,13,1,1},{6,13,1,4},{12,13,2,1},{1,14,2,2},{13,14,1,1},{9,15,3,2},{13,15,2,1},{1,16,1,2},{14,16,2,1},{3,17,4,1},{9,17,1,1}}}
T.glyphs[28129] = {w=18, advance=16, rects={{1,4,1,1},{5,4,2,1},{9,4,2,4},{13,4,2,1},{1,5,3,1},{6,5,2,1},{12,5,2,1},{3,6,1,1},{7,6,1,1},{0,8,2,1},{8,8,5,1},{1,9,2,1},{6,9,3,1},{12,9,3,1},{2,10,1,1},{5,10,2,1},{9,10,2,5},{14,10,1,1},{2,12,1,3},{5,12,2,1},{13,12,2,1},{6,13,2,1},{12,13,2,1},{12,14,1,1},{1,15,2,2},{8,15,4,1},{7,16,2,1},{11,16,2,1},{1,17,1,2},{5,17,3,1},{12,17,3,1},{4,18,2,1},{14,18,1,1}}}
T.glyphs[28145] = {w=18, advance=16, rects={{1,4,2,1},{2,5,2,1},{5,5,10,1},{3,6,1,1},{5,6,2,1},{14,6,1,2},{5,7,1,1},{8,7,1,1},{11,7,2,1},{0,8,2,1},{6,8,2,1},{12,8,2,1},{1,9,2,1},{5,9,2,1},{9,9,2,2},{13,9,2,1},{2,10,2,1},{5,11,11,1},{2,12,2,2},{9,12,2,1},{8,13,4,1},{2,14,1,1},{7,14,1,1},{9,14,2,5},{12,14,1,1},{1,15,2,2},{6,15,2,1},{12,15,2,1},{4,16,3,1},{13,16,2,1},{1,17,1,2},{4,17,1,1},{14,17,1,1}}}
T.glyphs[28151] = {w=18, advance=16, rects={{1,4,2,1},{2,5,2,1},{5,5,10,1},{3,6,1,1},{5,6,1,1},{13,6,2,1},{5,7,10,1},{0,8,2,1},{5,8,1,1},{13,8,2,1},{1,9,2,1},{5,9,10,1},{2,10,2,1},{5,10,1,1},{13,10,2,1},{5,12,1,1},{10,12,1,1},{14,12,1,1},{2,13,2,2},{5,13,6,1},{12,13,3,1},{5,14,1,3},{10,14,3,1},{2,15,1,1},{10,15,1,3},{14,15,2,2},{1,16,2,2},{8,16,1,1},{5,17,3,1},{14,17,1,1},{1,18,1,1},{5,18,1,1},{10,18,5,1}}}
T.glyphs[28155] = {w=18, advance=16, rects={{1,4,1,1},{1,5,3,1},{5,5,10,1},{3,6,1,1},{8,6,2,2},{0,8,2,1},{4,8,12,1},{1,9,2,1},{7,9,2,1},{10,9,2,1},{2,10,1,1},{7,10,1,1},{11,10,2,1},{6,11,2,1},{12,11,2,1},{5,12,2,1},{9,12,1,2},{13,12,2,1},{2,13,1,2},{4,13,1,1},{14,13,2,1},{6,14,1,2},{9,14,3,1},{13,14,1,1},{1,15,2,2},{9,15,1,2},{11,15,1,2},{13,15,2,1},{5,16,2,1},{14,16,1,1},{1,17,1,2},{5,17,1,1},{8,17,2,1},{11,17,2,1},{6,18,4,1}}}
T.glyphs[28165] = {w=18, advance=16, rects={{1,4,1,1},{9,4,2,1},{2,5,2,1},{5,5,11,1},{3,6,1,1},{9,6,2,1},{5,7,10,1},{0,8,2,1},{9,8,2,1},{1,9,2,1},{4,9,12,1},{2,10,1,1},{5,11,10,1},{2,12,1,3},{5,12,2,1},{13,12,2,1},{5,13,10,1},{5,14,2,1},{13,14,2,1},{1,15,2,3},{5,15,10,1},{5,16,2,3},{13,16,2,2},{1,18,1,1},{10,18,4,1}}}
T.glyphs[28176] = {w=18, advance=16, rects={{1,4,1,1},{5,4,2,1},{13,4,2,1},{1,5,2,1},{5,5,1,1},{10,5,5,1},{2,6,9,1},{4,7,2,1},{10,7,1,3},{0,8,2,1},{4,8,3,1},{1,9,2,1},{4,9,1,2},{6,9,1,2},{2,10,1,1},{10,10,6,1},{3,11,6,1},{10,11,1,3},{13,11,1,8},{6,12,1,2},{2,13,1,1},{1,14,2,1},{4,14,7,1},{1,15,7,1},{9,15,2,1},{1,16,1,3},{6,16,1,3},{9,16,1,1},{8,17,2,2}}}
T.glyphs[28210] = {w=18, advance=16, rects={{1,4,1,1},{9,4,1,1},{2,5,1,1},{9,5,2,1},{3,6,12,1},{4,7,2,1},{14,7,1,1},{0,8,2,1},{5,8,9,1},{1,9,2,1},{2,10,2,1},{5,10,9,1},{5,11,2,1},{13,11,1,1},{2,12,2,2},{5,12,9,1},{5,13,2,1},{13,13,1,1},{2,14,1,1},{5,14,9,1},{1,15,2,2},{5,15,2,1},{13,15,1,1},{1,17,1,1},{4,17,12,1}}}
T.glyphs[28216] = {w=18, advance=16, rects={{1,4,1,1},{5,4,2,1},{10,4,2,1},{1,5,2,1},{6,5,1,1},{10,5,1,1},{2,6,1,1},{10,6,6,1},{3,7,8,1},{0,8,1,1},{5,8,1,2},{9,8,1,1},{0,9,2,1},{9,9,6,1},{1,10,2,1},{5,10,4,1},{13,10,2,1},{2,11,1,1},{5,11,1,2},{7,11,2,2},{12,11,2,1},{12,12,1,1},{2,13,1,2},{4,13,2,2},{7,13,9,1},{7,14,2,4},{12,14,1,4},{1,15,2,2},{4,15,1,2},{1,17,1,2},{3,17,2,1},{3,18,1,1},{5,18,3,1},{10,18,3,1}}}
T.glyphs[28304] = {w=18, advance=16, rects={{1,4,1,1},{2,5,2,1},{5,5,11,1},{3,6,1,1},{5,6,1,8},{10,6,1,1},{9,7,2,1},{0,8,2,1},{7,8,8,1},{1,9,2,1},{7,9,2,1},{13,9,2,1},{2,10,2,1},{7,10,8,1},{7,11,2,1},{13,11,2,1},{2,12,1,2},{7,12,8,1},{10,13,2,5},{1,14,2,2},{4,14,2,2},{8,14,1,1},{13,14,1,1},{7,15,2,1},{13,15,2,1},{1,16,1,3},{4,16,1,1},{6,16,2,1},{14,16,1,2},{3,17,2,1},{6,17,1,1},{3,18,1,1},{8,18,3,1}}}
T.glyphs[28316] = {w=18, advance=16, rects={{1,4,1,1},{7,4,8,1},{1,5,2,1},{5,5,3,1},{10,5,2,4},{14,5,1,5},{2,6,2,1},{5,6,1,3},{7,6,1,1},{7,7,2,2},{0,9,3,1},{5,9,6,1},{2,10,4,1},{9,10,2,1},{12,10,2,1},{9,11,1,1},{5,12,10,1},{2,13,2,1},{5,13,1,2},{9,13,2,1},{13,13,2,2},{2,14,1,2},{9,14,1,1},{5,15,10,1},{1,16,2,2},{5,16,1,2},{9,16,2,2},{13,16,2,2},{1,18,1,1},{5,18,10,1}}}
T.glyphs[28369] = {w=18, advance=16, rects={{1,4,1,1},{2,5,2,1},{6,5,8,1},{3,6,1,1},{6,6,1,1},{12,6,2,3},{6,7,5,1},{0,8,2,1},{6,8,1,1},{9,8,2,1},{1,9,2,1},{4,9,11,1},{2,10,1,1},{4,10,2,1},{14,10,1,1},{6,11,8,1},{2,12,1,2},{6,12,1,1},{12,12,2,1},{6,13,8,1},{1,14,2,2},{6,14,1,1},{12,14,2,1},{6,15,8,1},{1,16,1,2},{6,16,1,2},{12,16,2,1},{10,17,3,1}}}
T.glyphs[28378] = {w=18, advance=16, rects={{1,4,2,1},{9,4,2,1},{2,5,2,1},{5,5,11,1},{3,6,1,1},{7,6,2,1},{11,6,2,1},{6,7,2,1},{12,7,2,1},{0,8,2,1},{5,8,2,1},{9,8,1,1},{13,8,2,1},{1,9,2,1},{5,9,1,1},{8,9,2,1},{14,9,1,1},{2,10,1,1},{7,10,2,1},{11,10,1,1},{6,11,2,1},{11,11,3,1},{5,12,9,1},{2,13,1,2},{8,13,3,1},{14,13,1,1},{7,14,2,1},{10,14,2,1},{13,14,1,1},{1,15,2,1},{5,15,3,1},{11,15,2,1},{1,16,4,1},{7,16,1,1},{9,16,2,1},{12,16,2,1},{1,17,1,2},{7,17,3,1},{13,17,3,1},{7,18,1,1}}}
T.glyphs[28385] = {w=18, advance=16, rects={{1,4,1,1},{7,4,1,1},{11,4,2,1},{1,5,2,1},{4,5,12,1},{2,6,1,1},{7,6,1,1},{11,6,2,1},{0,8,2,1},{4,8,12,1},{1,9,2,1},{7,9,2,2},{11,9,1,2},{2,10,1,1},{4,11,11,1},{2,12,1,2},{4,12,2,3},{7,12,2,2},{11,12,1,2},{14,12,1,3},{1,14,2,2},{7,14,6,1},{4,15,4,1},{9,15,2,2},{12,15,3,1},{1,16,1,3},{4,16,3,1},{13,16,2,1},{4,17,2,2},{9,17,1,1},{14,17,1,1},{11,18,4,1}}}
T.glyphs[28404] = {w=18, advance=16, rects={{1,4,1,1},{9,4,1,1},{2,5,1,1},{4,5,12,1},{3,6,1,1},{7,6,1,2},{12,6,1,1},{11,7,2,2},{0,8,2,1},{7,8,2,1},{1,9,2,1},{5,9,10,1},{2,10,1,1},{5,10,1,9},{9,10,2,1},{14,10,1,8},{7,11,6,1},{9,12,2,1},{2,13,1,2},{7,13,5,1},{7,14,2,2},{11,14,1,2},{1,15,2,2},{7,16,5,1},{1,17,1,2},{7,17,2,1},{11,18,4,1}}}
T.glyphs[28418] = {w=18, advance=16, rects={{1,4,1,1},{4,4,12,1},{1,5,2,1},{7,5,2,2},{11,5,1,2},{2,6,2,1},{4,7,11,1},{1,8,1,1},{4,8,2,2},{7,8,2,2},{11,8,1,2},{14,8,1,2},{1,9,2,1},{2,10,13,1},{6,12,8,1},{2,13,1,2},{4,14,12,1},{1,15,2,2},{6,15,1,1},{9,15,2,3},{5,16,2,1},{12,16,2,1},{1,17,1,2},{3,17,3,1},{13,17,3,1},{7,18,3,1}}}
T.glyphs[28431] = {w=18, advance=16, rects={{1,4,1,1},{1,5,2,1},{4,5,11,1},{2,6,1,1},{4,6,2,1},{14,6,1,1},{4,7,11,1},{0,8,2,1},{4,8,2,1},{1,9,2,1},{4,9,12,1},{2,10,1,1},{4,10,2,1},{10,10,1,1},{4,11,11,1},{2,12,1,1},{4,12,3,1},{10,12,1,2},{14,12,1,2},{1,13,2,3},{4,13,1,3},{6,13,1,2},{8,13,1,1},{12,13,1,1},{8,14,3,1},{13,14,2,1},{6,15,3,1},{10,15,1,1},{12,15,1,2},{14,15,1,3},{1,16,1,2},{3,16,2,1},{6,16,1,3},{8,16,3,1},{3,17,1,2},{10,17,1,2},{0,18,2,1},{12,18,3,1}}}
T.glyphs[28436] = {w=18, advance=16, rects={{1,4,2,1},{9,4,1,1},{2,5,13,1},{3,6,3,1},{14,6,1,2},{4,7,2,1},{0,8,2,1},{6,8,8,1},{1,9,2,1},{9,9,1,1},{2,10,1,1},{5,10,9,1},{5,11,2,1},{9,11,1,1},{13,11,1,1},{5,12,9,1},{2,13,2,2},{5,13,2,1},{9,13,1,1},{13,13,1,1},{5,14,9,1},{2,15,1,1},{5,15,2,1},{13,15,1,1},{1,16,2,2},{7,16,2,1},{11,16,2,1},{5,17,3,1},{11,17,4,1},{1,18,1,1},{4,18,2,1},{13,18,2,1}}}
T.glyphs[28608] = {w=18, advance=16, rects={{1,4,1,1},{6,4,1,1},{11,4,2,1},{1,5,2,1},{4,5,6,1},{11,5,1,1},{2,6,1,1},{4,6,1,1},{8,6,2,1},{11,6,5,1},{4,7,6,1},{11,7,1,1},{14,7,1,2},{0,8,2,1},{4,8,1,1},{8,8,4,1},{1,9,2,1},{4,9,8,1},{13,9,2,2},{6,10,1,2},{10,10,2,1},{11,11,3,1},{3,12,7,1},{12,12,2,3},{2,13,1,1},{5,13,1,2},{1,14,2,1},{1,15,1,3},{4,15,5,1},{11,15,3,1},{4,16,2,1},{8,16,1,1},{10,16,2,1},{14,16,1,1},{3,17,2,1},{6,17,5,1},{15,17,1,1}}}
T.glyphs[28779] = {w=18, advance=16, rects={{7,4,2,8},{2,7,1,1},{13,7,1,1},{2,8,2,1},{12,8,2,1},{3,9,2,2},{11,9,2,1},{10,10,2,2},{4,11,1,1},{6,12,3,1},{6,13,2,1},{9,13,1,1},{5,14,2,1},{9,14,2,1},{4,15,2,1},{10,15,2,1},{3,16,2,1},{11,16,2,1},{1,17,3,1},{12,17,3,1},{1,18,1,1},{13,18,2,1}}}
T.glyphs[28784] = {w=18, advance=16, rects={{4,4,1,2},{1,6,14,1},{4,7,1,2},{9,8,1,4},{3,9,2,1},{13,9,1,1},{3,10,4,1},{12,10,2,2},{3,11,1,2},{6,11,1,1},{6,12,5,1},{12,12,1,1},{2,13,2,1},{8,13,1,1},{10,13,1,1},{1,14,2,1},{7,14,2,1},{11,14,1,1},{1,15,1,1},{6,15,2,1},{11,15,2,1},{0,16,2,1},{5,16,2,1},{12,16,3,1},{4,17,1,1},{14,17,2,1}}}
T.glyphs[28789] = {w=18, advance=16, rects={{2,5,12,1},{13,6,1,1},{2,7,12,1},{13,8,1,1},{2,9,12,1},{13,10,1,1},{7,11,2,3},{2,12,1,1},{13,12,1,1},{2,13,3,1},{12,13,2,1},{3,14,2,1},{6,14,4,1},{11,14,2,1},{5,15,2,1},{9,15,3,1},{4,16,2,1},{10,16,2,1},{2,17,3,1},{11,17,3,1},{1,18,2,1},{12,18,4,1}}}
T.glyphs[28846] = {w=18, advance=16, rects={{2,4,2,3},{8,4,1,1},{7,5,2,1},{0,6,1,1},{5,6,1,1},{7,6,8,1},{0,7,8,2},{13,7,2,6},{1,9,11,1},{1,10,4,1},{6,10,2,2},{11,10,1,2},{2,11,2,2},{6,12,6,1},{2,13,3,1},{6,13,2,2},{13,13,1,1},{2,14,1,1},{4,14,1,1},{10,14,6,1},{1,15,2,1},{4,15,4,1},{14,15,2,1},{1,16,1,1},{7,16,1,1},{14,16,1,1},{0,17,1,1},{7,17,8,1}}}
T.glyphs[28857] = {w=18, advance=16, rects={{7,4,2,1},{7,5,9,1},{7,6,2,2},{2,8,12,1},{2,9,2,3},{13,9,1,3},{2,12,12,1},{2,13,2,1},{13,13,1,1},{2,15,1,1},{5,15,1,1},{9,15,1,2},{13,15,1,1},{1,16,2,1},{5,16,2,2},{13,16,2,2},{1,17,1,2},{9,17,2,1},{6,18,1,1},{10,18,1,1},{14,18,1,1}}}
T.glyphs[28888] = {w=18, advance=16, rects={{2,4,2,3},{8,4,1,3},{12,4,1,3},{0,7,1,1},{2,7,13,1},{0,8,5,1},{7,8,2,1},{12,8,1,4},{1,9,4,2},{8,9,1,3},{2,11,2,1},{2,12,1,1},{5,12,11,1},{2,13,2,1},{2,14,3,1},{8,14,1,1},{11,14,2,1},{1,15,2,1},{4,15,1,1},{7,15,2,1},{12,15,2,1},{1,16,1,1},{5,16,3,1},{13,16,2,1},{0,17,1,1},{5,17,1,1},{14,17,2,1}}}
T.glyphs[28903] = {w=18, advance=16, rects={{2,4,2,3},{8,4,1,1},{8,5,7,1},{6,6,8,1},{0,7,1,1},{2,7,4,1},{9,7,1,1},{12,7,2,1},{0,8,6,1},{9,8,3,1},{14,8,2,2},{1,9,4,1},{7,9,5,1},{2,10,6,1},{11,10,4,1},{2,11,1,2},{12,11,3,1},{2,13,2,1},{5,13,10,1},{2,14,3,1},{7,14,2,2},{11,14,1,4},{1,15,2,2},{4,15,1,2},{14,15,2,2},{7,16,1,1},{1,17,1,1},{6,17,2,1},{14,17,1,1},{0,18,1,1},{5,18,2,1},{11,18,4,1},{5,19,1,1}}}
T.glyphs[28909] = {w=18, advance=16, rects={{3,4,1,2},{8,4,2,2},{0,6,13,1},{3,7,1,1},{8,7,2,1},{12,7,1,4},{3,8,7,1},{1,9,4,1},{7,9,3,1},{0,10,2,1},{3,10,1,3},{8,10,3,1},{15,10,1,2},{7,11,2,1},{10,11,1,1},{12,11,2,1},{7,12,1,1},{12,12,4,1},{1,13,3,1},{6,13,1,1},{13,13,2,1},{5,14,2,1},{2,15,1,2},{9,15,1,2},{5,16,1,1},{13,16,1,1},{1,17,2,1},{5,17,2,2},{9,17,2,1},{13,17,2,1},{1,18,1,2},{10,18,1,2},{14,18,1,2},{6,19,1,1}}}
T.glyphs[28953] = {w=18, advance=16, rects={{2,4,2,4},{10,4,1,2},{6,6,9,1},{0,7,1,1},{5,7,1,1},{7,7,1,1},{12,7,2,2},{0,8,6,1},{7,8,2,1},{0,9,5,1},{8,9,1,1},{11,9,2,1},{1,10,3,1},{5,10,11,1},{2,11,2,2},{6,12,9,1},{2,13,3,1},{6,13,2,2},{13,13,2,3},{2,14,1,1},{4,14,1,1},{1,15,2,1},{4,15,4,1},{1,16,1,1},{4,16,11,1},{0,17,1,1},{6,17,2,1},{13,17,2,1}}}
T.glyphs[28982] = {w=18, advance=16, rects={{3,3,2,1},{3,4,1,1},{10,4,2,3},{13,4,1,1},{2,5,6,1},{14,5,1,1},{2,6,2,1},{6,6,2,1},{2,7,3,1},{6,7,10,1},{1,8,2,1},{4,8,3,1},{10,8,2,2},{0,9,3,1},{5,9,2,1},{0,10,1,1},{3,10,1,1},{5,10,1,1},{9,10,4,1},{4,11,2,1},{9,11,2,1},{12,11,1,1},{3,12,2,1},{8,12,2,1},{12,12,2,1},{1,13,3,1},{7,13,2,1},{13,13,2,1},{1,14,1,1},{6,14,2,1},{14,14,2,1},{2,15,1,2},{5,15,1,1},{9,15,1,1},{13,15,1,1},{5,16,2,1},{9,16,2,1},{13,16,2,1},{1,17,2,1},{6,17,1,2},{10,17,1,2},{14,17,1,2},{1,18,1,1}}}
T.glyphs[29031] = {w=18, advance=16, rects={{1,5,5,1},{7,5,8,1},{1,6,2,3},{5,6,1,3},{9,6,1,2},{14,6,1,1},{13,7,2,1},{8,8,2,1},{11,8,3,1},{1,9,5,1},{7,9,2,1},{1,10,2,3},{5,10,1,3},{8,10,7,1},{8,11,1,2},{14,11,1,2},{1,13,5,1},{8,13,7,1},{1,14,2,1},{5,14,1,1},{8,14,1,1},{14,14,1,1},{2,16,1,1},{5,16,1,1},{9,16,1,1},{13,16,1,1},{1,17,2,1},{5,17,2,1},{9,17,2,1},{13,17,2,1},{1,18,1,1},{6,18,1,1},{10,18,1,1},{14,18,1,1}}}
T.glyphs[29123] = {w=18, advance=16, rects={{2,4,1,3},{6,4,2,2},{11,4,3,1},{11,5,4,1},{0,6,1,2},{4,6,1,1},{6,6,4,1},{11,6,2,2},{14,6,1,1},{2,7,5,1},{8,7,2,1},{0,8,16,1},{1,9,2,1},{4,9,2,1},{7,9,2,1},{11,9,2,2},{2,10,1,4},{4,10,5,1},{6,11,3,1},{10,11,4,1},{6,12,2,1},{9,12,2,1},{13,12,1,1},{5,13,2,1},{8,13,2,1},{13,13,2,1},{1,14,3,1},{5,14,1,1},{8,14,1,3},{14,14,2,1},{1,15,4,1},{6,15,1,1},{10,15,2,1},{13,15,1,1},{1,16,1,1},{4,16,3,1},{11,16,1,2},{13,16,2,1},{0,17,2,1},{5,17,1,2},{8,17,2,2},{14,17,1,2}}}
T.glyphs[29238] = {w=18, advance=16, rects={{5,5,2,1},{9,5,2,1},{4,6,2,1},{10,6,2,1},{3,7,2,1},{11,7,2,1},{2,8,3,1},{12,8,2,1},{1,9,4,1},{11,9,1,2},{13,9,2,1},{1,10,1,1},{4,10,2,1},{14,10,1,1},{5,11,1,1},{10,11,2,1},{5,12,2,1},{9,12,2,2},{6,13,1,1},{7,14,3,1},{6,15,4,1},{4,16,3,1},{9,16,3,1},{2,17,3,1},{11,17,4,1},{1,18,2,1},{13,18,2,1}}}
T.glyphs[29255] = {w=18, advance=16, rects={{3,4,2,4},{10,4,2,4},{3,8,13,1},{3,9,2,3},{3,12,9,1},{3,13,2,1},{11,13,1,6},{3,14,1,1},{2,15,2,2},{1,17,2,1},{1,18,1,1}}}
T.glyphs[29256] = {w=18, advance=16, rects={{1,4,2,5},{4,4,1,5},{12,4,3,1},{7,5,7,1},{7,6,1,3},{1,9,14,1},{1,10,2,2},{7,10,1,6},{9,10,1,1},{13,10,2,2},{9,11,2,2},{1,12,4,1},{13,12,1,1},{1,13,2,1},{4,13,1,4},{10,13,1,1},{12,13,2,1},{1,14,1,3},{10,14,3,1},{11,15,2,1},{6,16,2,1},{10,16,4,1},{0,17,2,1},{4,17,3,2},{8,17,3,1},{13,17,2,1},{0,18,1,1},{8,18,1,1},{14,18,2,1}}}
T.glyphs[29273] = {w=18, advance=16, rects={{1,5,14,1},{10,6,2,1},{3,7,1,1},{10,7,1,3},{2,8,2,1},{2,9,1,1},{2,10,14,1},{8,11,4,1},{7,12,2,1},{10,12,1,5},{6,13,2,1},{5,14,2,1},{4,15,2,1},{3,16,2,1},{1,17,3,1},{6,17,1,1},{9,17,2,1},{1,18,1,1},{6,18,5,1}}}
T.glyphs[29289] = {w=18, advance=16, rects={{3,4,2,3},{8,4,1,1},{1,5,1,2},{7,5,2,1},{7,6,8,1},{1,7,7,1},{9,7,1,3},{11,7,2,3},{14,7,1,6},{0,8,2,2},{3,8,2,3},{6,8,1,2},{0,10,1,1},{8,10,2,1},{11,10,1,2},{3,11,3,1},{8,11,1,1},{1,12,5,1},{7,12,2,1},{10,12,2,1},{0,13,5,1},{7,13,1,1},{10,13,1,1},{13,13,2,4},{3,14,2,1},{6,14,2,1},{9,14,2,1},{3,15,4,1},{8,15,2,1},{3,16,2,3},{7,16,2,1},{7,17,1,1},{10,17,4,1}}}
T.glyphs[29359] = {w=18, advance=16, rects={{1,4,1,1},{1,5,2,1},{4,5,2,1},{7,5,8,1},{2,6,3,1},{7,6,1,11},{13,6,2,3},{2,7,2,1},{1,8,3,1},{1,9,1,1},{3,9,2,3},{13,9,1,3},{2,12,3,1},{10,12,4,1},{1,13,2,1},{4,13,1,4},{1,14,1,1},{14,15,2,3},{3,17,2,1},{7,17,2,1},{1,18,3,1},{7,18,8,1}}}
T.glyphs[29366] = {w=18, advance=16, rects={{4,4,1,4},{9,4,2,4},{12,4,1,1},{12,5,2,1},{1,6,1,1},{13,6,2,1},{1,7,2,2},{4,8,12,1},{2,9,1,1},{4,9,1,2},{9,9,2,2},{3,11,2,1},{9,11,3,1},{2,12,3,1},{8,12,2,2},{11,12,1,1},{1,13,2,1},{4,13,1,4},{11,13,2,1},{0,14,2,1},{7,14,2,1},{12,14,1,1},{7,15,1,1},{12,15,2,1},{6,16,2,1},{13,16,2,1},{4,17,3,1},{14,17,1,1}}}
T.glyphs[29420] = {w=18, advance=16, rects={{1,4,1,1},{10,4,1,3},{1,5,2,1},{4,5,2,1},{2,6,3,1},{2,7,2,1},{6,7,9,1},{1,8,3,1},{6,8,2,5},{10,8,1,5},{13,8,2,5},{1,9,1,1},{3,9,1,1},{3,10,2,2},{2,12,3,2},{6,13,9,1},{1,14,1,2},{4,14,1,3},{6,14,2,1},{10,14,1,4},{13,15,1,2},{3,17,2,2},{13,17,2,1},{9,18,6,1},{1,19,3,1},{5,19,6,1},{14,19,2,1}}}
T.glyphs[29468] = {w=18, advance=16, rects={{1,4,1,1},{4,4,1,1},{10,4,1,1},{1,5,4,1},{6,5,10,1},{2,6,2,2},{10,6,1,1},{6,7,9,1},{1,8,3,1},{10,8,1,1},{1,9,1,1},{3,9,13,1},{3,10,2,1},{2,11,3,2},{6,12,9,1},{1,13,2,1},{4,13,1,4},{6,13,2,1},{13,13,2,1},{0,14,2,1},{6,14,9,1},{6,15,2,1},{13,15,2,1},{6,16,9,1},{3,17,2,1},{6,17,2,2},{13,17,2,1},{1,18,3,1},{10,18,4,1}}}
T.glyphs[29486] = {w=18, advance=16, rects={{4,4,2,1},{11,4,4,1},{0,5,9,1},{11,5,2,2},{14,5,1,1},{4,6,2,2},{9,7,7,1},{1,8,8,1},{11,8,2,4},{1,9,1,3},{3,9,1,3},{6,9,1,1},{8,9,1,3},{5,10,2,1},{5,11,1,1},{1,12,8,1},{11,12,3,2},{1,13,1,1},{4,13,2,1},{8,13,1,1},{1,14,8,1},{10,14,2,2},{13,14,1,2},{1,15,1,4},{4,15,2,3},{8,15,1,2},{10,16,1,1},{13,16,2,1},{7,17,4,1},{14,17,1,2},{4,18,6,1}}}
T.glyphs[29575] = {w=18, advance=16, rects={{7,3,1,1},{7,4,2,1},{0,5,16,1},{7,6,1,1},{1,7,1,1},{6,7,2,1},{9,7,2,1},{13,7,2,1},{1,8,2,1},{5,8,2,1},{9,8,1,1},{12,8,2,1},{2,9,2,1},{5,9,4,1},{12,9,1,2},{3,10,2,1},{7,10,1,1},{9,10,1,1},{2,11,5,1},{9,11,2,1},{12,11,2,1},{1,12,2,1},{4,12,8,1},{13,12,2,1},{1,13,1,1},{7,13,2,2},{11,13,1,1},{14,13,1,1},{0,15,16,1},{7,16,2,3}}}
T.glyphs[29609] = {w=18, advance=16, rects={{0,5,6,1},{7,5,8,1},{2,6,2,4},{6,9,10,1},{0,10,6,1},{7,10,2,1},{11,10,2,7},{2,11,2,3},{8,11,1,1},{7,12,2,3},{2,14,4,1},{15,14,1,1},{1,15,4,1},{7,15,1,1},{14,15,2,2},{0,16,2,1},{6,16,2,1},{5,17,2,1},{11,17,4,1},{4,18,2,1}}}
T.glyphs[29615] = {w=18, advance=16, rects={{0,5,15,1},{2,6,2,4},{9,6,2,3},{8,9,2,1},{0,10,6,1},{8,10,5,1},{2,11,2,3},{7,11,4,1},{12,11,1,1},{7,12,2,1},{10,12,1,8},{12,12,2,1},{6,13,2,1},{13,13,1,1},{2,14,5,1},{13,14,2,1},{1,15,5,1},{14,15,2,1},{0,16,2,1},{14,16,1,1}}}
T.glyphs[29616] = {w=18, advance=16, rects={{0,5,15,1},{2,6,2,4},{6,6,2,4},{13,6,2,8},{10,7,1,5},{0,10,8,1},{2,11,2,4},{6,11,2,4},{9,12,2,1},{9,13,3,3},{2,15,4,1},{14,15,2,3},{0,16,5,1},{8,16,1,1},{10,16,2,2},{7,17,2,1},{5,18,2,1},{11,18,4,1},{5,19,1,1}}}
T.glyphs[29699] = {w=18, advance=16, rects={{10,4,1,3},{12,4,2,1},{0,5,6,1},{13,5,1,1},{2,6,2,4},{6,7,10,1},{10,8,1,3},{6,9,1,1},{0,10,8,1},{14,10,1,1},{2,11,2,5},{7,11,2,1},{10,11,2,1},{13,11,2,1},{8,12,1,1},{10,12,4,1},{8,13,5,1},{7,14,4,1},{12,14,1,1},{6,15,2,1},{10,15,1,3},{12,15,2,1},{2,16,4,1},{13,16,2,1},{1,17,3,1},{14,17,2,1},{0,18,2,1},{7,18,4,1}}}
T.glyphs[29702] = {w=18, advance=16, rects={{0,5,15,1},{2,6,2,4},{6,6,2,2},{10,6,1,2},{13,6,2,2},{6,8,9,1},{6,9,2,1},{10,9,1,2},{13,9,2,2},{0,10,8,1},{2,11,2,4},{6,11,9,1},{6,12,2,1},{10,12,1,2},{13,12,2,1},{6,14,9,1},{1,15,5,1},{10,15,1,2},{0,16,5,1},{5,17,11,1}}}
T.glyphs[29923] = {w=18, advance=16, rects={{2,4,1,1},{8,4,3,1},{13,4,1,1},{0,5,10,1},{11,5,5,1},{1,6,1,2},{4,6,1,2},{6,6,4,4},{11,6,1,1},{14,6,1,3},{11,7,2,1},{1,8,3,1},{12,8,1,1},{0,10,16,1},{2,11,2,2},{5,11,6,1},{13,11,1,2},{5,12,3,1},{10,12,1,1},{1,13,7,1},{10,13,6,1},{2,14,1,3},{5,14,1,3},{7,14,4,1},{13,14,1,5},{7,15,1,1},{9,15,2,1},{7,16,5,1},{1,17,1,2},{4,17,2,1},{7,17,1,1},{9,17,3,1},{4,18,1,1},{11,18,1,1}}}
T.glyphs[29983] = {w=18, advance=16, rects={{3,5,2,1},{7,5,2,2},{3,6,1,1},{2,7,13,1},{2,8,1,1},{7,8,2,4},{1,9,2,1},{1,10,1,1},{0,11,2,1},{2,12,13,1},{7,13,2,4},{0,17,16,1}}}
T.glyphs[29992] = {w=18, advance=16, rects={{2,5,13,1},{2,6,2,1},{7,6,2,1},{13,6,2,3},{2,7,1,2},{8,7,1,2},{2,9,13,1},{2,10,2,1},{8,10,1,3},{13,10,2,3},{2,11,1,2},{2,13,13,1},{2,14,1,1},{8,14,1,4},{13,14,2,3},{1,15,2,2},{1,17,1,2},{10,17,5,1}}}
T.glyphs[29993] = {w=18, advance=16, rects={{2,4,12,1},{2,5,1,2},{7,5,2,2},{13,5,1,2},{2,7,12,1},{2,8,1,2},{7,8,2,2},{13,8,1,2},{2,10,12,1},{2,11,1,3},{7,11,2,6},{13,11,1,2},{12,13,2,1},{1,14,2,1},{10,14,6,1},{1,15,1,2},{14,15,2,2},{0,17,1,1},{8,17,7,1}}}
T.glyphs[30001] = {w=18, advance=16, rects={{7,4,2,3},{1,7,14,1},{1,8,2,4},{7,8,2,4},{13,8,2,4},{1,12,14,1},{1,13,2,4},{7,13,2,4},{13,13,2,4},{1,17,14,1},{1,18,2,1},{13,18,2,1}}}
T.glyphs[30002] = {w=18, advance=16, rects={{2,4,12,1},{2,5,1,3},{7,5,2,3},{13,5,1,3},{2,8,12,1},{2,9,1,3},{7,9,2,3},{13,9,1,3},{2,12,12,1},{2,13,1,1},{7,13,2,5},{13,13,1,1}}}
T.glyphs[30011] = {w=18, advance=16, rects={{0,5,16,1},{1,8,2,9},{4,8,8,1},{13,8,2,9},{4,9,1,2},{7,9,2,2},{10,9,2,1},{11,10,1,1},{4,11,8,1},{4,12,1,2},{7,12,2,2},{10,12,2,1},{11,13,1,1},{4,14,8,1},{4,15,1,1},{10,15,2,1},{1,17,14,1},{13,18,2,1}}}
T.glyphs[30028] = {w=18, advance=16, rects={{2,5,12,1},{2,6,1,2},{7,6,2,2},{13,6,1,2},{2,8,12,1},{2,9,1,2},{7,9,2,2},{13,9,1,2},{2,11,12,1},{2,12,1,1},{5,12,2,1},{9,12,2,1},{13,12,1,1},{4,13,2,1},{10,13,2,1},{2,14,4,1},{10,14,4,1},{0,15,2,1},{4,15,2,2},{10,15,2,4},{13,15,3,1},{3,17,2,1},{2,18,1,1}}}
T.glyphs[30041] = {w=18, advance=16, rects={{4,4,3,1},{1,5,5,1},{8,5,7,1},{1,6,2,2},{5,6,1,1},{9,6,2,1},{13,6,2,3},{5,7,2,1},{9,7,1,1},{1,8,9,1},{1,9,3,1},{6,9,3,1},{10,9,4,1},{2,11,12,1},{2,12,1,2},{7,12,2,2},{13,12,1,2},{2,14,12,1},{2,15,1,2},{7,15,2,2},{13,15,1,2},{2,17,12,1},{2,18,1,1},{13,18,1,1}}}
T.glyphs[30053] = {w=18, advance=16, rects={{9,3,1,1},{8,4,2,1},{1,5,6,1},{8,5,7,1},{1,6,1,4},{3,6,1,4},{5,6,5,2},{13,6,2,1},{12,7,2,1},{5,8,3,1},{9,8,4,1},{5,9,2,1},{10,9,3,1},{1,10,6,1},{8,10,3,1},{12,10,3,1},{1,11,1,4},{3,11,1,4},{5,11,4,1},{14,11,2,1},{5,12,2,3},{8,13,7,1},{8,14,1,3},{13,14,2,3},{1,15,6,1},{1,16,1,1},{5,16,2,1},{8,17,7,1},{8,18,1,1},{13,18,2,1}}}
T.glyphs[30103] = {w=18, advance=16, rects={{8,4,2,2},{3,6,13,1},{3,7,1,3},{0,8,2,1},{1,9,1,1},{5,9,10,1},{1,10,3,1},{12,10,2,1},{3,11,1,1},{10,11,3,1},{1,12,3,1},{9,12,2,6},{0,13,4,1},{2,14,2,2},{2,16,1,1},{1,17,2,1},{1,18,1,1},{6,18,4,1}}}
T.glyphs[30130] = {w=18, advance=16, rects={{8,4,2,1},{2,5,14,1},{2,6,2,1},{10,6,1,2},{0,7,4,2},{5,8,10,1},{1,9,3,2},{5,9,1,3},{10,9,1,3},{14,9,1,2},{2,11,2,1},{1,12,3,1},{5,12,10,1},{0,13,4,1},{5,13,3,1},{13,13,1,1},{2,14,1,2},{5,14,1,1},{7,14,2,1},{12,14,2,1},{4,15,2,2},{8,15,2,1},{11,15,2,1},{1,16,2,1},{9,16,3,1},{1,17,1,2},{3,17,2,1},{6,17,4,1},{11,17,4,1},{3,18,1,1},{6,18,2,1},{13,18,2,1}}}
T.glyphs[30333] = {w=18, advance=16, rects={{6,3,2,1},{6,4,1,1},{1,5,13,1},{1,6,2,5},{13,6,1,5},{1,11,13,1},{1,12,2,5},{13,12,1,5},{1,17,13,1},{1,18,2,1},{13,18,1,1}}}
T.glyphs[30340] = {w=18, advance=16, rects={{3,4,2,1},{9,4,2,1},{3,5,1,1},{9,5,1,1},{1,6,6,1},{9,6,6,1},{1,7,1,4},{5,7,2,1},{8,7,2,1},{14,7,1,7},{6,8,1,1},{8,8,1,1},{6,9,4,1},{6,10,1,1},{9,10,2,1},{1,11,6,1},{10,11,1,1},{1,12,1,4},{5,12,2,1},{10,12,2,1},{6,13,1,3},{11,13,1,1},{13,14,2,3},{1,16,6,1},{1,17,1,1},{5,17,2,1},{9,17,5,1}}}
T.glyphs[30417] = {w=18, advance=16, rects={{5,4,1,5},{9,4,2,1},{1,5,2,6},{9,5,1,1},{8,6,8,1},{8,7,1,1},{7,8,2,1},{10,8,2,1},{5,9,3,1},{11,9,2,1},{5,10,1,1},{12,10,2,1},{2,12,12,1},{2,13,2,1},{5,13,2,1},{9,13,2,1},{12,13,2,1},{2,14,1,3},{6,14,1,3},{9,14,1,3},{13,14,1,3},{0,17,16,1}}}
T.glyphs[30418] = {w=18, advance=16, rects={{7,3,2,1},{6,4,4,1},{5,5,2,1},{9,5,2,1},{3,6,3,1},{10,6,3,1},{1,7,14,1},{0,8,2,1},{14,8,2,1},{3,9,10,1},{3,10,1,1},{12,10,1,1},{3,11,10,1},{2,13,12,1},{2,14,2,3},{6,14,1,3},{9,14,1,3},{12,14,2,3},{0,17,16,1}}}
T.glyphs[30422] = {w=18, advance=16, rects={{4,4,2,1},{10,4,2,1},{5,5,1,1},{10,5,1,1},{1,6,14,1},{7,7,2,1},{1,8,14,1},{7,9,2,1},{0,10,16,1},{2,12,12,1},{2,13,1,4},{5,13,2,4},{9,13,1,4},{13,13,1,4},{0,17,16,1}}}
T.glyphs[30424] = {w=18, advance=16, rects={{7,4,1,1},{3,5,11,1},{3,6,2,2},{7,6,1,1},{12,6,2,2},{8,7,1,1},{0,8,16,1},{3,9,1,1},{6,9,2,1},{12,9,2,1},{2,10,2,1},{8,10,1,1},{10,10,3,1},{1,11,1,1},{2,12,12,1},{2,13,2,4},{6,13,1,4},{9,13,1,4},{13,13,1,4},{0,17,16,1}}}
T.glyphs[30446] = {w=18, advance=16, rects={{2,5,12,1},{2,6,2,3},{12,6,2,3},{2,9,12,1},{2,10,2,3},{12,10,2,3},{2,13,12,1},{2,14,2,3},{12,14,2,3},{2,17,12,1},{2,18,2,1},{12,18,2,1}}}
T.glyphs[30452] = {w=18, advance=16, rects={{7,4,2,1},{0,5,16,1},{7,6,2,1},{2,7,12,1},{2,8,2,2},{12,8,2,2},{2,10,12,1},{2,11,2,1},{12,11,2,1},{2,12,12,1},{2,13,2,1},{12,13,2,1},{2,14,12,1},{2,15,2,2},{12,15,2,2},{0,17,16,1}}}
T.glyphs[30456] = {w=18, advance=16, rects={{3,4,1,3},{7,5,8,1},{7,6,1,1},{14,6,1,3},{0,7,8,1},{2,8,2,2},{7,8,1,1},{7,9,8,1},{2,10,3,1},{7,10,1,2},{14,10,1,3},{1,11,5,1},{1,12,1,1},{3,12,1,7},{5,12,3,1},{0,13,2,1},{7,13,8,1},{0,14,1,1},{7,14,1,3},{14,14,1,3},{7,17,8,1},{7,18,1,1},{14,18,1,1}}}
T.glyphs[30462] = {w=18, advance=16, rects={{9,4,6,1},{2,5,11,1},{2,6,1,2},{8,6,2,2},{2,8,14,1},{2,9,1,5},{8,9,2,2},{4,11,10,1},{4,12,2,1},{13,12,1,1},{4,13,10,1},{1,14,2,2},{4,14,2,1},{13,14,1,1},{4,15,10,1},{1,16,1,1},{4,16,2,1},{13,16,1,1},{0,17,2,2},{4,17,10,1},{4,18,2,1},{13,18,1,1}}}
T.glyphs[30465] = {w=18, advance=16, rects={{7,4,2,4},{4,5,2,1},{11,5,1,1},{3,6,2,1},{11,6,3,1},{1,7,3,1},{13,7,2,1},{1,8,1,1},{10,8,3,1},{14,8,1,1},{6,9,5,1},{2,10,5,1},{0,11,14,1},{3,12,1,1},{13,12,1,1},{3,13,11,1},{3,14,1,1},{13,14,1,1},{3,15,11,1},{3,16,1,1},{13,16,1,1},{3,17,11,1},{3,18,1,1},{13,18,1,1}}}
T.glyphs[30475] = {w=18, advance=16, rects={{8,4,7,1},{1,5,10,1},{6,6,2,1},{1,7,14,1},{5,8,2,1},{0,9,16,1},{4,10,2,1},{3,11,11,1},{2,12,3,1},{12,12,2,1},{1,13,2,1},{4,13,10,1},{0,14,2,1},{4,14,1,1},{12,14,2,1},{4,15,10,1},{4,16,1,1},{12,16,2,1},{4,17,10,1},{4,18,1,1},{12,18,2,1}}}
T.glyphs[30495] = {w=18, advance=16, rects={{7,4,2,1},{0,5,15,1},{7,6,2,1},{3,7,10,1},{3,8,1,1},{12,8,1,1},{3,9,10,1},{3,10,1,1},{12,10,1,1},{3,11,10,1},{3,12,1,1},{12,12,1,1},{3,13,10,1},{3,14,1,1},{12,14,1,1},{0,15,16,1},{4,16,2,1},{10,16,2,1},{2,17,4,1},{10,17,5,1},{1,18,2,1},{13,18,2,1}}}
T.glyphs[30504] = {w=18, advance=16, rects={{1,4,14,1},{1,5,1,4},{4,5,2,4},{10,5,1,1},{9,6,2,1},{10,7,2,2},{1,9,5,1},{1,10,1,3},{4,10,11,1},{4,11,2,2},{12,11,2,1},{12,12,1,1},{1,13,5,1},{11,13,1,1},{1,14,1,2},{4,14,2,2},{9,14,2,1},{8,15,2,1},{1,16,5,1},{7,16,2,1},{1,17,1,1},{6,17,4,1},{6,18,1,1},{9,18,7,1}}}
T.glyphs[30511] = {w=18, advance=16, rects={{10,4,1,6},{1,5,5,1},{7,5,1,2},{13,5,2,1},{1,6,1,2},{4,6,2,2},{13,6,1,1},{7,7,2,1},{12,7,2,1},{1,8,5,1},{8,8,1,1},{12,8,1,1},{1,9,1,2},{4,9,2,1},{4,10,12,1},{1,11,5,1},{9,11,3,1},{1,12,1,3},{4,12,2,3},{9,12,4,1},{8,13,1,1},{10,13,3,1},{7,14,2,1},{10,14,1,4},{12,14,2,1},{1,15,7,1},{13,15,2,1},{1,16,1,1},{5,16,2,1},{14,16,1,1}}}
T.glyphs[30524] = {w=18, advance=16, rects={{1,4,5,1},{7,4,8,1},{1,5,2,3},{5,5,1,3},{7,5,2,2},{13,5,2,2},{7,7,8,1},{1,8,5,1},{7,8,2,2},{13,8,2,2},{1,9,2,3},{5,9,1,3},{7,10,8,1},{7,11,2,6},{10,11,1,2},{13,11,2,1},{1,12,5,1},{14,12,2,1},{1,13,2,3},{5,13,1,3},{10,13,2,1},{13,13,2,1},{11,14,3,1},{11,15,2,1},{1,16,5,1},{10,16,1,1},{12,16,2,1},{1,17,2,2},{5,17,1,1},{7,17,4,1},{13,17,2,1},{7,18,2,1},{14,18,2,1}}}
T.glyphs[30528] = {w=18, advance=16, rects={{5,4,1,1},{10,4,2,1},{1,5,14,1},{6,6,1,1},{2,7,12,1},{5,8,1,1},{0,9,16,1},{4,10,1,1},{3,11,11,1},{2,12,3,1},{13,12,1,1},{1,13,13,1},{0,14,2,1},{3,14,2,1},{13,14,1,1},{3,15,11,1},{3,16,2,1},{13,16,1,1},{3,17,11,1},{3,18,2,1},{13,18,1,1}}}
T.glyphs[30555] = {w=18, advance=16, rects={{1,4,5,1},{10,4,2,1},{1,5,1,4},{4,5,12,1},{4,6,2,3},{10,6,2,1},{7,7,8,1},{10,8,2,1},{1,9,15,1},{1,10,1,3},{4,10,2,3},{7,11,8,1},{7,12,1,1},{14,12,1,1},{1,13,5,1},{7,13,8,1},{1,14,1,2},{4,14,2,2},{7,14,1,2},{14,14,1,2},{1,16,5,1},{7,16,8,1},{1,17,1,1},{4,17,2,1},{7,17,1,2},{13,17,2,1},{10,18,4,1}}}
T.glyphs[30636] = {w=18, advance=16, rects={{10,4,5,1},{1,5,11,1},{1,6,1,3},{3,6,2,3},{6,6,1,1},{9,6,2,1},{13,6,1,1},{7,7,1,2},{10,7,1,2},{12,7,2,1},{12,8,1,1},{1,9,15,1},{1,10,1,2},{3,10,3,1},{14,10,2,1},{3,11,2,1},{6,11,2,1},{12,11,2,1},{1,12,4,1},{6,12,10,1},{1,13,1,3},{3,13,4,1},{8,13,6,1},{3,14,6,1},{10,14,1,1},{12,14,2,1},{3,15,2,1},{7,15,2,1},{10,15,6,1},{1,16,4,1},{7,16,1,1},{12,16,2,3},{1,17,1,1},{5,17,2,1},{5,18,1,1}}}
T.glyphs[30683] = {w=18, advance=16, rects={{2,5,12,1},{11,6,3,1},{5,7,1,1},{10,7,2,1},{5,8,6,1},{7,9,3,1},{0,10,16,1},{6,11,4,1},{14,11,1,1},{6,12,1,1},{8,12,2,5},{13,12,2,1},{5,13,1,1},{13,13,1,1},{4,14,1,1},{3,15,1,1},{1,16,2,1},{0,17,2,1},{8,17,1,1},{5,18,4,1}}}
T.glyphs[30693] = {w=18, advance=16, rects={{2,3,1,2},{1,5,2,1},{8,5,7,1},{1,6,9,1},{14,6,1,10},{1,7,1,1},{3,7,2,1},{8,7,2,4},{0,8,2,2},{4,8,1,1},{3,9,2,2},{0,11,10,1},{3,12,2,2},{8,12,2,4},{3,14,3,1},{2,15,2,1},{5,15,2,1},{2,16,1,1},{6,16,9,1},{1,17,2,1},{6,17,4,1},{14,17,1,2},{0,18,2,1},{8,18,2,1}}}
T.glyphs[30697] = {w=18, advance=16, rects={{2,4,1,1},{1,5,2,1},{7,5,9,1},{1,6,8,1},{1,7,1,1},{3,7,2,1},{7,7,1,2},{0,8,2,1},{3,8,1,3},{0,9,1,1},{7,9,8,1},{7,10,2,1},{13,10,2,3},{0,11,8,1},{3,12,1,2},{7,12,1,1},{7,13,8,1},{2,14,3,1},{7,14,2,1},{13,14,2,1},{2,15,4,1},{7,15,1,1},{2,16,1,1},{5,16,3,1},{1,17,2,1},{7,17,9,1},{0,18,2,1}}}
T.glyphs[30701] = {w=18, advance=16, rects={{2,4,1,1},{1,5,2,2},{6,5,10,1},{1,7,5,1},{0,8,2,2},{3,8,1,3},{7,8,8,1},{7,9,1,2},{13,9,2,3},{0,11,8,1},{3,12,1,1},{7,12,8,1},{2,13,3,1},{7,13,1,1},{13,13,2,1},{2,14,4,1},{7,14,2,1},{13,14,1,1},{2,15,1,1},{5,15,1,1},{8,15,1,1},{12,15,2,1},{1,16,2,1},{8,16,2,1},{11,16,2,1},{1,17,1,1},{5,17,11,1},{0,18,2,1}}}
T.glyphs[30702] = {w=18, advance=16, rects={{2,4,1,1},{11,4,4,1},{1,5,2,1},{6,5,9,1},{1,6,5,1},{10,6,1,1},{0,7,2,2},{3,7,1,3},{6,7,10,1},{8,8,5,1},{7,9,2,1},{10,9,1,2},{12,9,2,1},{0,10,7,1},{14,10,2,1},{2,11,2,2},{9,11,2,1},{5,12,11,1},{2,13,3,1},{8,13,1,1},{12,13,1,1},{2,14,4,1},{7,14,2,1},{11,14,2,1},{1,15,2,1},{5,15,1,1},{9,15,3,1},{1,16,1,1},{8,16,6,1},{0,17,2,1},{5,17,4,1},{13,17,2,1}}}
T.glyphs[30721] = {w=18, advance=16, rects={{1,5,13,1},{3,6,1,1},{13,6,1,2},{2,7,2,2},{8,7,1,3},{12,8,2,3},{2,9,1,1},{1,10,5,1},{7,10,2,1},{1,11,2,1},{5,11,1,3},{7,11,8,1},{0,12,3,1},{14,12,1,4},{2,13,1,3},{5,14,8,1},{5,15,1,1},{2,16,4,1},{13,16,2,1},{2,17,1,1},{5,17,1,1},{10,17,4,1}}}
T.glyphs[30772] = {w=18, advance=16, rects={{11,4,1,2},{0,5,6,1},{2,6,2,1},{6,6,10,1},{2,7,1,2},{6,7,2,2},{11,7,1,2},{14,7,2,1},{1,9,14,1},{1,10,2,1},{4,10,6,1},{13,10,2,2},{0,11,3,2},{4,11,4,3},{9,11,1,1},{9,12,2,1},{13,12,1,1},{2,13,1,2},{10,13,1,1},{12,13,2,1},{4,14,3,1},{10,14,3,2},{2,15,5,1},{2,16,1,1},{5,16,2,1},{8,16,3,1},{12,16,3,1},{5,17,1,1},{7,17,2,1},{14,17,2,1}}}
T.glyphs[30776] = {w=18, advance=16, rects={{0,4,6,1},{7,4,9,1},{2,5,2,1},{7,5,1,12},{2,6,1,3},{11,6,2,1},{9,7,6,1},{9,8,1,7},{11,8,2,6},{14,8,1,6},{1,9,5,1},{1,10,2,1},{4,10,2,6},{0,11,3,2},{2,13,1,3},{11,14,4,1},{11,15,2,2},{2,16,4,1},{2,17,1,1},{4,17,2,1},{7,17,9,1}}}
T.glyphs[30784] = {w=18, advance=16, rects={{10,4,2,6},{0,5,6,1},{7,5,1,5},{14,5,1,5},{2,6,2,1},{2,7,1,2},{1,9,5,1},{1,10,2,1},{4,10,2,5},{7,10,8,1},{0,11,3,2},{10,11,2,6},{2,13,1,2},{7,13,1,4},{14,13,1,4},{2,15,4,1},{2,16,1,2},{4,16,2,1},{7,17,8,1},{14,18,1,1}}}
T.glyphs[30828] = {w=18, advance=16, rects={{6,5,10,1},{0,6,6,1},{10,6,2,1},{2,7,2,1},{7,7,8,1},{2,8,1,2},{7,8,1,1},{10,8,1,1},{14,8,1,1},{7,9,8,1},{1,10,5,1},{7,10,1,2},{10,10,1,2},{14,10,1,2},{0,11,3,2},{4,11,2,4},{7,12,8,1},{2,13,1,2},{7,13,1,1},{10,13,1,1},{14,13,1,1},{8,14,3,2},{2,15,4,1},{2,16,1,1},{6,16,8,1},{5,17,2,1},{12,17,4,1}}}
T.glyphs[30830] = {w=18, advance=16, rects={{8,4,2,1},{0,5,6,1},{7,5,7,1},{2,6,2,1},{7,6,1,1},{12,6,1,1},{2,7,1,2},{6,7,2,1},{11,7,2,1},{5,8,10,1},{1,9,5,1},{7,9,1,2},{10,9,2,2},{14,9,1,2},{1,10,2,1},{4,10,2,4},{0,11,3,1},{7,11,8,1},{0,12,1,1},{2,12,1,3},{7,12,1,2},{10,12,2,2},{14,12,1,2},{4,14,11,1},{2,15,6,1},{10,15,2,2},{14,15,1,2},{2,16,1,1},{6,16,1,1},{5,17,2,1},{10,17,5,1}}}
T.glyphs[30896] = {w=18, advance=16, rects={{7,4,2,1},{13,4,1,1},{0,5,6,1},{8,5,1,1},{12,5,2,1},{2,6,2,2},{8,6,2,1},{11,6,2,1},{6,7,10,1},{2,8,1,2},{9,8,1,6},{11,8,2,4},{1,10,6,1},{14,10,1,2},{0,11,3,2},{4,11,4,2},{11,12,4,2},{1,13,2,3},{4,13,2,3},{7,13,1,1},{7,14,3,1},{11,14,3,1},{9,15,1,2},{11,15,2,2},{1,16,5,1},{1,17,2,1},{4,17,12,1}}}
T.glyphs[31034] = {w=18, advance=16, rects={{2,5,12,1},{0,9,16,1},{7,10,2,1},{3,11,2,1},{8,11,1,5},{11,11,2,2},{3,12,1,1},{2,13,2,1},{12,13,2,1},{1,14,2,2},{13,14,2,1},{14,15,1,1},{1,16,1,1},{7,16,2,1},{14,16,2,1},{4,17,5,1}}}
T.glyphs[31080] = {w=18, advance=16, rects={{1,5,14,1},{5,6,2,1},{9,6,2,1},{1,7,14,1},{1,8,2,2},{5,8,2,2},{9,8,2,2},{13,8,2,2},{1,10,14,1},{1,12,14,1},{0,14,16,1},{7,15,2,3},{3,16,2,1},{10,16,2,1},{1,17,3,1},{11,17,4,1},{0,18,2,1},{5,18,3,1},{14,18,1,1}}}
T.glyphs[31105] = {w=18, advance=16, rects={{4,4,1,1},{11,4,1,1},{1,5,14,1},{3,6,2,1},{10,6,3,1},{2,7,4,1},{9,7,5,1},{1,8,2,1},{4,8,1,2},{6,8,1,1},{8,8,2,1},{11,8,1,2},{13,8,2,1},{0,9,2,1},{7,9,2,1},{14,9,2,1},{2,11,12,1},{0,13,16,1},{7,14,2,1},{4,15,1,1},{8,15,1,2},{10,15,2,1},{3,16,1,1},{11,16,2,1},{1,17,2,1},{7,17,2,1},{12,17,3,1},{1,18,1,1},{5,18,4,1},{14,18,1,1}}}
T.glyphs[31163] = {w=18, advance=16, rects={{7,3,1,1},{7,4,2,1},{0,5,16,1},{4,6,2,1},{10,6,2,1},{2,7,1,4},{5,7,3,1},{9,7,2,1},{13,7,1,4},{6,8,4,1},{4,9,3,1},{10,9,2,1},{2,11,12,1},{7,12,1,1},{1,13,14,1},{1,14,2,5},{6,14,1,1},{9,14,1,1},{13,14,2,4},{5,15,1,1},{9,15,2,1},{4,16,8,1},{11,17,1,1},{11,18,3,1}}}
T.glyphs[31181] = {w=18, advance=16, rects={{3,4,3,1},{10,4,2,3},{0,5,5,1},{3,6,1,1},{0,7,15,1},{2,8,2,1},{7,8,1,3},{10,8,2,4},{14,8,1,4},{2,9,3,1},{2,10,4,1},{2,11,2,1},{5,11,3,1},{1,12,3,1},{5,12,10,1},{1,13,1,1},{3,13,1,6},{7,13,1,1},{10,13,2,6},{14,13,1,1},{0,14,2,1},{0,15,1,1}}}
T.glyphs[31186] = {w=18, advance=16, rects={{3,4,3,1},{10,4,1,10},{0,5,5,1},{3,6,1,2},{7,6,2,2},{13,6,1,2},{0,8,6,1},{7,8,1,2},{13,8,2,1},{2,9,2,2},{14,9,1,2},{6,10,2,2},{2,11,3,1},{1,12,5,1},{13,12,2,2},{1,13,1,1},{3,13,1,6},{5,13,1,1},{0,14,2,1},{12,14,2,1},{0,15,1,1},{11,15,2,1},{9,16,3,1},{7,17,3,1},{5,18,3,1}}}
T.glyphs[31215] = {w=18, advance=16, rects={{3,5,3,1},{0,6,5,1},{7,6,8,1},{3,7,1,2},{7,7,1,5},{14,7,1,5},{0,9,6,1},{2,10,2,1},{2,11,3,1},{1,12,5,1},{7,12,8,1},{1,13,1,1},{3,13,1,6},{5,13,1,2},{7,13,1,1},{14,13,1,1},{0,14,2,1},{0,15,1,1},{8,15,1,1},{12,15,2,1},{7,16,2,1},{13,16,1,1},{6,17,2,1},{13,17,2,1},{6,18,1,1},{14,18,2,1}}}
T.glyphs[31216] = {w=18, advance=16, rects={{8,3,2,2},{2,4,5,1},{0,5,5,1},{7,5,2,1},{3,6,1,2},{7,6,8,1},{6,7,2,1},{14,7,1,1},{0,8,8,1},{10,8,1,10},{13,8,2,1},{2,9,2,1},{6,9,1,1},{13,9,1,1},{2,10,3,1},{2,11,4,1},{7,11,2,2},{12,11,1,1},{1,12,3,1},{5,12,1,1},{12,12,2,1},{1,13,1,1},{3,13,1,6},{7,13,1,1},{13,13,2,2},{0,14,2,1},{6,14,2,1},{0,15,1,1},{6,15,1,2},{14,15,2,2},{7,18,4,1}}}
T.glyphs[31227] = {w=18, advance=16, rects={{9,3,1,1},{3,4,3,1},{8,4,2,1},{0,5,5,1},{8,5,7,1},{3,6,1,2},{7,6,2,1},{13,6,2,1},{6,7,2,1},{12,7,2,1},{0,8,7,1},{9,8,4,1},{2,9,2,2},{9,9,3,1},{8,10,3,1},{2,11,6,1},{9,11,2,1},{1,12,3,1},{5,12,1,1},{8,12,8,1},{1,13,1,1},{3,13,1,6},{7,13,3,1},{14,13,1,1},{0,14,2,1},{6,14,4,1},{13,14,2,1},{0,15,1,1},{6,15,1,1},{9,15,2,1},{12,15,2,1},{10,16,3,1},{8,17,3,1},{6,18,2,1}}}
T.glyphs[31243] = {w=18, advance=16, rects={{3,4,3,1},{0,5,5,1},{7,5,8,1},{3,6,1,2},{7,6,1,2},{13,6,2,2},{0,8,6,1},{7,8,8,1},{2,9,2,2},{7,9,1,1},{13,9,2,1},{2,11,3,1},{6,11,9,1},{1,12,5,1},{10,12,1,2},{1,13,1,1},{3,13,1,6},{5,13,1,1},{0,14,2,1},{6,14,9,1},{0,15,1,1},{10,15,1,2},{5,17,11,1}}}
T.glyphs[31245] = {w=18, advance=16, rects={{3,4,5,1},{10,4,2,5},{14,4,1,2},{0,5,5,1},{7,5,1,1},{3,6,1,2},{7,6,2,1},{13,6,2,1},{8,7,1,1},{13,7,1,1},{0,8,6,1},{2,9,2,2},{6,9,9,1},{6,10,2,2},{14,10,1,2},{2,11,3,1},{1,12,1,2},{3,12,12,1},{3,13,1,5},{5,13,3,2},{14,13,1,2},{0,14,1,2},{6,15,9,1},{6,16,2,2},{13,16,2,1},{11,17,4,1}}}
T.glyphs[31283] = {w=18, advance=16, rects={{8,3,1,1},{3,4,3,1},{7,4,2,1},{0,5,5,1},{7,5,6,1},{2,6,2,3},{6,6,2,1},{11,6,2,1},{6,7,1,1},{11,7,1,1},{6,8,9,1},{0,9,6,1},{13,9,2,1},{2,10,2,1},{6,10,9,1},{2,11,3,1},{13,11,2,1},{1,12,3,2},{5,12,10,1},{9,13,2,1},{13,13,2,1},{0,14,4,1},{5,14,4,1},{10,14,1,2},{14,14,1,2},{0,15,1,1},{2,15,2,4},{5,15,1,3},{7,15,2,3},{12,16,4,1},{12,17,2,1},{15,17,1,1},{8,18,5,1}}}
T.glyphs[31354] = {w=18, advance=16, rects={{7,4,1,1},{7,5,2,1},{1,6,14,1},{1,7,1,2},{14,7,1,2},{5,8,2,1},{9,8,2,1},{4,9,2,1},{10,9,2,1},{2,10,3,1},{11,10,3,1},{1,11,3,1},{13,11,2,1},{1,12,14,1},{7,13,2,4},{1,17,14,1}}}
T.glyphs[31359] = {w=18, advance=16, rects={{7,4,1,1},{7,5,2,1},{1,6,14,1},{1,7,1,2},{14,7,1,2},{4,8,3,1},{9,8,3,1},{2,9,3,1},{11,9,3,1},{1,11,15,1},{10,12,1,2},{2,13,2,1},{2,14,14,1},{7,15,2,1},{10,15,1,2},{5,16,3,1},{2,17,4,1},{9,17,2,1},{0,18,3,1},{7,18,4,1}}}
T.glyphs[31364] = {w=18, advance=16, rects={{7,4,1,1},{7,5,2,1},{1,6,14,1},{1,7,1,2},{14,7,1,2},{4,8,3,1},{9,8,3,1},{2,9,3,1},{11,9,3,1},{4,10,2,1},{3,11,13,1},{1,12,3,1},{6,12,1,1},{1,13,1,1},{6,13,8,1},{6,14,1,1},{6,15,9,1},{6,16,1,3}}}
T.glyphs[31383] = {w=18, advance=16, rects={{7,4,1,1},{7,5,2,1},{1,6,14,1},{1,7,1,1},{4,7,3,1},{9,7,3,1},{14,7,1,1},{1,8,5,1},{7,8,2,1},{11,8,4,1},{0,9,3,1},{7,9,1,1},{14,9,2,1},{2,10,12,1},{2,11,1,6},{6,11,1,1},{13,11,1,6},{4,12,8,1},{4,13,1,1},{6,13,2,1},{9,13,2,1},{7,14,4,1},{4,15,3,1},{10,15,2,1},{2,17,12,1},{2,18,1,1},{13,18,1,1}}}
T.glyphs[31389] = {w=18, advance=16, rects={{7,4,1,1},{7,5,2,1},{1,6,14,1},{1,7,1,1},{14,7,1,1},{5,8,2,1},{9,8,3,1},{1,9,5,1},{11,9,4,1},{0,10,13,1},{14,10,2,1},{3,11,2,1},{11,11,2,1},{3,12,10,1},{7,13,2,1},{1,14,14,1},{1,15,2,2},{6,15,3,1},{13,15,2,3},{5,16,6,1},{1,17,5,1},{10,17,2,1},{1,18,2,1},{11,18,3,1}}}
T.glyphs[31435] = {w=18, advance=16, rects={{7,3,1,1},{7,4,2,2},{1,6,14,1},{3,8,1,1},{12,8,1,1},{3,9,2,2},{11,9,2,2},{4,11,1,1},{11,11,1,1},{4,12,2,2},{10,12,2,2},{5,14,1,2},{10,14,1,1},{9,15,2,1},{9,16,1,1},{0,17,16,1}}}
T.glyphs[31446] = {w=18, advance=16, rects={{4,4,2,1},{1,5,2,6},{4,5,11,1},{4,6,2,4},{7,6,2,1},{12,6,2,1},{8,7,2,1},{11,7,2,1},{9,8,3,1},{7,9,6,1},{4,10,5,1},{12,10,3,1},{7,11,2,1},{2,12,13,1},{4,13,1,1},{11,13,1,1},{4,14,2,1},{10,14,2,2},{5,15,1,2},{9,16,2,1},{0,17,16,1}}}
T.glyphs[31449] = {w=18, advance=16, rects={{2,4,2,1},{10,4,2,3},{3,5,1,2},{0,7,7,1},{10,7,6,1},{10,8,2,4},{1,9,1,1},{5,9,1,3},{1,10,2,2},{2,12,1,3},{4,12,2,2},{7,12,8,1},{7,13,2,3},{14,13,1,4},{4,14,1,2},{2,16,7,1},{0,17,5,1},{7,17,8,1},{7,18,2,1},{14,18,1,1}}}
T.glyphs[31469] = {w=18, advance=16, rects={{2,4,2,1},{7,4,8,1},{3,5,1,2},{7,5,1,2},{13,5,2,2},{0,7,6,1},{7,7,8,1},{7,8,1,1},{13,8,2,1},{1,9,1,3},{4,9,1,3},{7,9,8,1},{7,10,2,1},{6,11,9,1},{1,12,2,2},{4,12,3,1},{10,12,1,1},{14,12,1,5},{4,13,1,1},{6,13,2,1},{10,13,2,1},{1,14,4,1},{7,14,3,1},{11,14,2,1},{3,15,2,1},{7,15,1,1},{2,16,4,1},{7,16,6,1},{0,17,4,1},{13,17,2,1},{10,18,4,1}}}
T.glyphs[31471] = {w=18, advance=16, rects={{2,4,1,1},{10,4,1,3},{2,5,2,1},{6,5,2,2},{13,5,2,2},{3,6,1,1},{0,7,15,1},{13,8,2,1},{1,9,1,4},{4,9,1,1},{4,10,12,1},{4,11,1,2},{10,11,1,1},{9,12,2,1},{1,13,4,2},{6,13,9,1},{6,14,1,2},{9,14,1,4},{11,14,1,4},{14,14,1,4},{3,15,1,1},{2,16,5,1},{0,17,5,1},{6,17,1,2},{12,18,3,1}}}
T.glyphs[31526] = {w=18, advance=16, rects={{3,4,2,1},{10,4,1,1},{2,5,2,1},{9,5,2,1},{2,6,14,1},{1,7,2,2},{4,7,2,1},{8,7,2,1},{11,7,2,1},{5,8,1,1},{7,8,2,2},{12,8,1,1},{0,9,2,1},{3,10,2,1},{12,10,1,1},{3,11,13,1},{2,12,2,1},{12,12,1,5},{0,13,4,1},{6,13,2,1},{0,14,2,1},{3,14,1,5},{7,14,2,2},{11,17,2,1},{9,18,4,1}}}
T.glyphs[31532] = {w=18, advance=16, rects={{3,4,2,1},{10,4,1,1},{2,5,2,1},{9,5,2,1},{2,6,14,1},{1,7,2,1},{4,7,1,1},{8,7,2,1},{11,7,1,1},{0,8,2,1},{4,8,2,1},{8,8,1,1},{11,8,2,1},{2,9,12,1},{7,10,2,1},{13,10,1,1},{2,11,12,1},{2,12,1,1},{7,12,2,2},{13,12,1,1},{1,13,2,1},{1,14,14,1},{5,15,4,1},{13,15,2,2},{4,16,2,1},{7,16,2,3},{2,17,3,1},{10,17,4,1},{0,18,3,1}}}
T.glyphs[31561] = {w=18, advance=16, rects={{3,4,2,1},{10,4,1,1},{2,5,2,1},{9,5,2,1},{2,6,14,1},{1,7,2,1},{4,7,1,1},{8,7,2,1},{11,7,1,1},{0,8,2,1},{4,8,2,1},{7,8,2,1},{11,8,2,1},{1,9,14,1},{7,10,2,2},{0,12,16,1},{10,13,2,2},{1,15,14,1},{4,16,2,1},{10,16,2,2},{5,17,1,1},{7,18,5,1}}}
T.glyphs[31574] = {w=18, advance=16, rects={{3,4,1,1},{10,4,1,1},{2,5,6,1},{9,5,7,1},{1,6,2,1},{4,6,1,1},{8,6,2,1},{11,6,1,1},{0,7,2,1},{4,7,2,1},{8,7,1,1},{11,7,2,1},{5,8,1,1},{7,8,2,1},{12,8,1,1},{1,9,15,1},{7,10,2,1},{2,11,12,1},{2,12,1,3},{7,12,2,1},{13,12,1,2},{6,13,4,1},{5,14,9,1},{4,15,2,1},{7,15,2,4},{10,15,2,1},{2,16,2,1},{12,16,2,1},{0,17,2,1},{13,17,3,1}}}
T.glyphs[31614] = {w=18, advance=16, rects={{3,4,1,1},{10,4,1,1},{2,5,14,1},{2,6,1,1},{8,6,2,1},{1,7,1,1},{4,7,1,1},{7,7,2,1},{11,7,2,1},{0,8,2,1},{4,8,6,1},{12,8,1,1},{4,9,3,1},{9,9,2,1},{3,10,2,1},{10,10,3,1},{1,11,14,1},{0,12,2,1},{14,12,1,1},{7,14,1,1},{12,14,1,1},{3,15,1,1},{7,15,2,1},{11,15,2,1},{3,16,2,1},{10,16,2,1},{1,17,14,1}}}
T.glyphs[31616] = {w=18, advance=16, rects={{3,4,1,1},{10,4,1,1},{2,5,6,1},{9,5,7,1},{1,6,2,1},{4,6,2,1},{8,6,2,1},{11,6,1,1},{0,7,2,1},{5,7,1,1},{8,7,1,1},{12,7,1,1},{3,8,1,1},{6,8,9,1},{3,9,2,1},{13,9,2,9},{1,10,2,9},{5,10,6,1},{5,11,1,2},{10,11,1,2},{5,13,6,1},{5,14,1,2},{10,14,1,2},{5,16,6,1},{11,18,3,1}}}
T.glyphs[31639] = {w=18, advance=16, rects={{3,4,1,1},{10,4,1,1},{2,5,6,1},{9,5,7,1},{1,6,2,1},{4,6,1,1},{8,6,2,1},{11,6,2,1},{0,7,2,1},{5,7,1,1},{8,7,1,1},{12,7,1,1},{2,8,12,1},{2,9,2,1},{12,9,2,1},{2,10,12,1},{2,11,2,1},{12,11,2,1},{2,12,12,1},{2,13,2,1},{12,13,2,1},{2,14,12,1},{0,15,16,1},{4,16,2,1},{11,16,1,3},{3,17,2,1},{1,18,3,1}}}
T.glyphs[31649] = {w=18, advance=16, rects={{3,4,1,1},{10,4,1,1},{2,5,14,1},{1,6,2,1},{4,6,1,1},{9,6,1,1},{11,6,1,1},{0,7,2,1},{4,7,2,1},{7,7,2,1},{12,7,1,1},{1,8,14,1},{1,9,1,1},{14,9,1,1},{3,10,9,1},{3,11,1,1},{11,11,1,1},{3,12,9,1},{3,13,1,1},{3,14,11,1},{3,15,1,2},{12,15,2,2},{3,17,11,1}}}
T.glyphs[31661] = {w=18, advance=16, rects={{3,5,1,1},{10,5,1,1},{2,6,6,1},{9,6,7,1},{1,7,2,1},{5,7,1,1},{8,7,2,1},{12,7,1,1},{0,8,2,1},{4,8,3,1},{8,8,1,1},{10,8,3,1},{4,9,2,1},{10,9,1,1},{0,10,16,1},{1,12,7,1},{10,12,1,5},{13,12,1,6},{1,13,2,1},{7,13,1,1},{1,14,7,1},{1,15,2,1},{7,15,1,1},{1,16,7,1},{1,17,2,2},{7,17,1,1},{5,18,3,1},{10,18,4,1}}}
T.glyphs[31665] = {w=18, advance=16, rects={{3,4,2,1},{10,4,1,1},{2,5,2,1},{9,5,2,1},{2,6,14,1},{1,7,2,1},{4,7,2,1},{8,7,2,1},{11,7,1,1},{0,8,2,1},{5,8,1,1},{8,8,1,1},{12,8,1,1},{3,9,1,1},{7,9,8,1},{0,10,6,1},{7,10,1,2},{13,10,2,2},{3,11,1,1},{2,12,2,1},{7,12,8,1},{2,13,4,1},{7,13,1,1},{13,13,2,1},{1,14,3,1},{5,14,1,1},{7,14,8,1},{0,15,2,1},{3,15,1,4},{7,15,1,2},{13,15,2,2},{0,16,1,1},{7,17,8,1},{7,18,1,1},{13,18,2,1}}}
T.glyphs[31867] = {w=18, advance=16, rects={{2,4,2,1},{7,4,2,4},{12,4,2,1},{3,5,2,1},{11,5,2,1},{4,6,2,1},{10,6,2,1},{1,8,14,1},{5,9,4,1},{4,10,2,1},{7,10,4,1},{1,11,3,1},{9,11,5,1},{1,12,2,1},{13,12,2,1},{1,13,14,1},{6,14,4,1},{6,15,2,1},{9,15,1,1},{4,16,3,1},{10,16,2,1},{1,17,5,1},{11,17,4,1},{1,18,2,1},{13,18,2,1}}}
T.glyphs[31895] = {w=18, advance=16, rects={{3,4,1,4},{0,5,1,1},{6,5,1,1},{8,5,7,1},{1,6,1,3},{5,6,2,1},{8,6,1,3},{13,6,2,3},{5,7,1,1},{3,8,3,1},{3,9,1,1},{8,9,7,1},{0,10,7,1},{8,10,1,3},{13,10,2,3},{2,11,2,1},{2,12,4,1},{1,13,5,1},{8,13,7,1},{0,14,2,1},{3,14,1,5},{6,14,1,1},{8,14,1,3},{13,14,2,3},{0,15,1,1},{6,17,10,1}}}
T.glyphs[31934] = {w=18, advance=16, rects={{3,4,1,2},{10,4,2,1},{0,5,2,1},{5,5,11,1},{1,6,1,1},{3,6,3,1},{10,6,2,1},{1,7,4,1},{7,7,8,1},{3,8,1,1},{10,8,2,1},{0,9,16,1},{2,10,2,2},{7,11,8,1},{2,12,3,1},{7,12,1,1},{14,12,1,1},{1,13,5,1},{7,13,8,1},{1,14,1,1},{3,14,1,5},{5,14,1,1},{7,14,1,1},{14,14,1,1},{0,15,2,1},{7,15,8,1},{0,16,1,1},{7,16,1,3},{14,16,1,1},{13,17,2,1},{10,18,4,1}}}
T.glyphs[31946] = {w=18, advance=16, rects={{2,4,2,1},{7,4,1,3},{0,5,1,1},{2,5,4,1},{10,5,5,1},{1,6,4,1},{10,6,2,1},{14,6,1,2},{1,7,11,1},{2,8,2,1},{7,8,1,3},{10,8,5,1},{0,9,6,1},{10,9,2,2},{14,9,1,3},{2,10,2,1},{2,11,10,1},{1,12,6,1},{8,12,7,1},{1,13,3,1},{5,13,2,2},{8,13,4,1},{14,13,1,4},{0,14,1,1},{2,14,2,4},{8,14,3,1},{5,15,6,1},{5,16,2,1},{9,16,2,1},{9,17,1,1},{12,17,3,1}}}
T.glyphs[31958] = {w=18, advance=16, rects={{3,3,1,4},{10,3,1,1},{10,4,2,1},{0,5,1,1},{5,5,11,1},{1,6,1,2},{5,6,3,1},{11,6,1,1},{3,7,2,1},{6,7,9,1},{3,8,1,1},{6,8,2,1},{11,8,1,1},{14,8,1,1},{0,9,16,1},{2,10,2,2},{6,10,2,1},{11,10,1,1},{14,10,1,1},{6,11,9,1},{2,12,5,1},{11,12,1,1},{1,13,3,1},{6,13,1,3},{1,14,1,1},{3,14,1,5},{8,14,7,1},{0,15,2,1},{8,15,1,2},{13,15,2,2},{0,16,1,1},{5,16,2,1},{5,17,1,2},{8,17,7,1},{8,18,1,1},{13,18,2,1}}}
T.glyphs[31995] = {w=18, advance=16, rects={{8,4,7,1},{1,5,12,1},{6,6,2,1},{4,7,2,1},{2,8,11,1},{2,9,10,1},{5,10,5,1},{2,11,5,1},{10,11,2,1},{2,12,12,1},{7,13,2,4},{14,13,1,1},{3,14,2,1},{11,14,1,1},{2,15,2,1},{11,15,2,1},{1,16,2,1},{13,16,2,1},{0,17,2,1},{5,17,4,1},{14,17,1,1}}}
T.glyphs[32032] = {w=18, advance=16, rects={{7,3,2,2},{1,5,14,1},{7,6,2,1},{2,7,12,1},{7,8,2,1},{0,9,16,1},{3,10,3,1},{10,10,2,1},{2,11,9,1},{5,12,4,1},{11,12,1,1},{3,13,10,1},{2,14,7,1},{13,14,1,1},{7,15,2,3},{14,15,1,1},{3,16,2,1},{10,16,2,1},{1,17,3,1},{11,17,3,1},{1,18,1,1},{5,18,3,1},{13,18,2,1}}}
T.glyphs[32034] = {w=18, advance=16, rects={{7,3,2,2},{1,5,14,1},{7,6,2,2},{1,8,14,1},{1,9,1,2},{6,9,2,1},{14,9,1,2},{4,10,2,1},{9,10,2,1},{3,11,7,1},{6,12,2,1},{11,12,1,1},{3,13,11,1},{2,14,7,1},{13,14,2,1},{7,15,2,3},{3,16,2,1},{10,16,2,1},{1,17,3,1},{12,17,3,1},{0,18,2,1},{5,18,3,1},{14,18,2,1}}}
T.glyphs[32039] = {w=18, advance=16, rects={{4,4,2,5},{1,5,2,4},{7,5,7,1},{8,6,1,1},{12,6,2,1},{9,7,4,1},{7,8,6,1},{4,9,4,1},{11,9,4,1},{4,10,3,1},{10,10,2,1},{3,11,7,1},{6,12,2,1},{11,12,2,1},{3,13,11,1},{2,14,7,1},{14,14,1,1},{4,15,1,1},{8,15,1,2},{11,15,1,1},{2,16,3,1},{11,16,4,1},{1,17,2,1},{5,17,4,1},{13,17,2,1}}}
T.glyphs[32043] = {w=18, advance=16, rects={{4,3,2,2},{9,3,1,2},{1,4,2,4},{13,4,1,1},{4,5,6,1},{11,5,3,1},{4,6,2,2},{9,6,3,1},{9,7,1,2},{14,7,2,2},{1,8,7,1},{0,9,8,1},{9,9,6,1},{4,10,2,1},{10,10,2,1},{2,11,9,1},{6,12,3,1},{11,12,2,1},{3,13,11,1},{2,14,7,1},{14,14,1,1},{8,15,1,2},{4,16,1,1},{10,16,2,1},{2,17,3,1},{7,17,2,1},{11,17,4,1},{1,18,2,1},{5,18,4,1},{13,18,2,1}}}
T.glyphs[32047] = {w=18, advance=16, rects={{2,5,12,1},{2,6,1,1},{7,6,2,1},{13,6,1,1},{2,7,12,1},{2,8,1,1},{7,8,2,1},{13,8,1,1},{2,9,12,1},{5,10,2,1},{10,10,2,1},{3,11,3,1},{8,11,3,1},{2,12,7,1},{5,13,3,1},{11,13,1,1},{3,14,3,1},{8,14,5,1},{2,15,8,1},{13,15,1,1},{3,16,2,1},{8,16,1,1},{11,16,4,2},{1,17,4,1},{7,17,2,1},{1,18,1,1},{4,18,5,1},{14,18,1,1}}}
T.glyphs[32416] = {w=18, advance=16, rects={{3,4,1,1},{13,4,1,8},{2,5,2,1},{2,6,1,1},{5,6,1,2},{8,6,1,7},{1,7,2,1},{1,8,1,1},{4,8,2,1},{0,9,5,1},{3,10,1,1},{2,11,2,1},{1,12,6,1},{10,12,4,1},{1,13,3,1},{7,13,5,1},{13,13,1,5},{7,14,2,1},{4,15,3,1},{1,16,5,1},{1,17,2,1}}}
T.glyphs[32418] = {w=18, advance=16, rects={{3,3,2,1},{3,4,1,1},{2,5,2,1},{6,5,9,1},{2,6,1,1},{10,6,2,11},{1,7,2,1},{5,7,1,1},{1,8,1,1},{4,8,2,1},{0,9,5,1},{3,10,1,1},{2,11,1,1},{1,12,5,1},{1,13,3,1},{4,15,2,1},{1,16,4,1},{0,17,2,1},{5,17,11,1}}}
T.glyphs[32422] = {w=18, advance=16, rects={{3,3,1,2},{8,3,2,2},{2,5,2,1},{8,5,1,1},{2,6,1,1},{5,6,1,1},{7,6,8,1},{1,7,2,1},{4,7,2,1},{7,7,2,1},{14,7,1,6},{1,8,1,1},{4,8,1,1},{6,8,2,1},{0,9,5,1},{6,9,1,1},{3,10,1,1},{8,10,1,1},{2,11,1,1},{8,11,2,1},{1,12,5,1},{9,12,2,1},{1,13,3,1},{10,13,1,1},{13,13,2,4},{4,15,3,1},{1,16,4,1},{0,17,2,1},{9,17,5,1}}}
T.glyphs[32423] = {w=18, advance=16, rects={{3,4,1,1},{2,5,2,1},{6,5,8,1},{2,6,1,1},{7,6,1,2},{12,6,1,1},{1,7,2,1},{4,7,2,1},{11,7,2,1},{1,8,1,1},{4,8,1,1},{7,8,2,3},{11,8,1,1},{0,9,5,1},{11,9,4,1},{2,10,2,1},{13,10,2,1},{1,11,2,1},{7,11,3,1},{13,11,1,1},{1,12,5,1},{7,12,1,1},{9,12,1,1},{12,12,2,1},{6,13,2,1},{10,13,3,1},{1,14,6,1},{10,14,2,1},{0,15,3,1},{5,15,2,1},{9,15,4,1},{4,16,2,2},{8,16,2,1},{12,16,3,1},{7,17,2,1},{14,17,1,1}}}
T.glyphs[32431] = {w=18, advance=16, rects={{3,4,1,1},{10,4,1,2},{2,5,2,1},{2,6,1,1},{6,6,9,1},{1,7,2,1},{4,7,2,1},{10,7,1,5},{1,8,1,1},{4,8,1,1},{6,8,2,4},{13,8,2,4},{0,9,5,1},{2,10,2,1},{2,11,1,1},{1,12,14,1},{1,13,3,1},{10,13,1,4},{14,14,2,3},{1,15,5,1},{0,16,3,1},{10,17,5,1}}}
T.glyphs[32433] = {w=18, advance=16, rects={{3,4,2,1},{10,4,1,9},{3,5,1,1},{2,6,2,1},{7,6,2,2},{13,6,1,2},{1,7,2,1},{4,7,2,1},{1,8,1,1},{4,8,1,1},{7,8,1,1},{13,8,2,1},{0,9,5,1},{6,9,2,1},{14,9,2,2},{2,10,2,1},{6,10,1,1},{2,11,1,1},{1,12,5,1},{13,12,2,1},{1,13,3,1},{12,13,2,1},{11,14,2,1},{2,15,4,1},{9,15,3,1},{0,16,4,1},{7,16,3,1},{5,17,3,1}}}
T.glyphs[32435] = {w=18, advance=16, rects={{3,3,1,1},{10,3,1,3},{2,4,2,2},{2,6,1,1},{4,6,11,1},{1,7,2,1},{4,7,1,2},{6,7,2,5},{10,7,1,3},{14,7,1,6},{0,8,2,1},{0,9,4,1},{3,10,1,1},{9,10,3,1},{2,11,1,1},{9,11,1,1},{11,11,2,1},{1,12,9,1},{12,12,1,1},{1,13,3,1},{6,13,3,1},{13,13,2,1},{1,14,1,1},{6,14,2,1},{14,14,1,3},{3,15,5,1},{1,16,3,1},{6,16,2,2},{0,17,2,1},{11,17,4,1}}}
T.glyphs[32441] = {w=18, advance=16, rects={{3,4,1,1},{9,4,2,1},{2,5,2,1},{10,5,1,1},{2,6,1,1},{10,6,2,1},{1,7,2,1},{6,7,10,1},{1,8,1,1},{4,8,2,1},{7,8,2,2},{13,8,1,2},{1,9,4,1},{3,10,1,1},{8,10,1,1},{12,10,2,1},{2,11,1,1},{8,11,2,1},{12,11,1,1},{1,12,5,1},{9,12,1,1},{11,12,2,1},{1,13,3,1},{9,13,3,2},{4,14,2,1},{1,15,4,1},{8,15,2,1},{11,15,2,1},{1,16,1,1},{6,16,3,1},{12,16,3,1},{5,17,2,1},{14,17,2,1}}}
T.glyphs[32447] = {w=18, advance=16, rects={{3,4,1,1},{8,4,2,1},{12,4,2,1},{2,5,2,1},{9,5,1,1},{2,6,1,1},{4,6,2,1},{8,6,7,1},{1,7,2,1},{4,7,9,1},{1,8,1,1},{4,8,1,1},{9,8,1,2},{0,9,4,1},{3,10,1,1},{8,10,8,1},{2,11,1,1},{5,11,8,1},{1,12,5,1},{9,12,2,2},{1,13,3,1},{13,13,2,1},{1,14,1,1},{10,14,4,1},{1,15,5,1},{10,15,2,1},{14,15,2,2},{0,16,4,1},{7,16,6,1},{5,17,3,1},{12,17,3,1}}}
T.glyphs[32451] = {w=18, advance=16, rects={{3,4,1,1},{9,4,1,2},{2,5,2,2},{5,6,10,1},{2,7,1,1},{8,7,2,1},{1,8,2,1},{4,8,2,1},{8,8,1,1},{0,9,2,1},{4,9,8,1},{0,10,5,1},{7,10,1,1},{11,10,1,2},{2,11,2,1},{6,11,2,1},{2,12,1,1},{6,12,9,1},{1,13,5,1},{11,13,1,4},{1,14,3,1},{8,14,1,1},{13,14,1,1},{1,15,1,1},{7,15,2,1},{13,15,2,1},{1,16,5,1},{7,16,1,1},{14,16,2,2},{0,17,4,1},{6,17,2,1},{10,17,2,1},{6,18,1,1},{8,18,4,1}}}
T.glyphs[32452] = {w=18, advance=16, rects={{3,4,1,1},{2,5,2,1},{7,5,8,1},{2,6,1,1},{5,6,1,1},{7,6,1,3},{13,6,2,3},{1,7,2,1},{4,7,2,1},{1,8,1,1},{4,8,1,1},{0,9,4,1},{7,9,8,1},{3,10,1,1},{7,10,1,3},{13,10,2,3},{2,11,1,1},{1,12,5,1},{1,13,2,1},{7,13,8,1},{7,14,1,3},{13,14,2,3},{1,15,5,1},{1,16,3,1},{5,17,11,1}}}
T.glyphs[32454] = {w=18, advance=16, rects={{3,4,1,1},{2,5,2,1},{6,5,9,1},{2,6,1,1},{6,6,2,1},{10,6,1,4},{14,6,1,4},{1,7,2,1},{4,7,3,1},{1,8,1,1},{4,8,1,1},{6,8,1,2},{0,9,5,1},{2,10,2,1},{6,10,9,1},{2,11,1,1},{6,11,2,1},{10,11,1,5},{14,11,1,5},{1,12,6,1},{1,13,2,1},{6,13,1,2},{1,15,6,1},{0,16,3,1},{6,16,9,1},{6,17,2,1},{14,17,1,1}}}
T.glyphs[32456] = {w=18, advance=16, rects={{3,4,1,1},{8,4,1,2},{2,5,2,1},{2,6,1,1},{4,6,2,1},{7,6,8,1},{1,7,2,1},{4,7,1,2},{7,7,2,1},{13,7,2,1},{1,8,1,1},{6,8,1,2},{8,8,2,1},{12,8,2,1},{0,9,4,1},{9,9,4,1},{2,10,2,1},{9,10,3,1},{2,11,1,1},{7,11,3,1},{11,11,4,1},{1,12,9,1},{13,12,3,1},{1,13,2,1},{9,13,4,1},{12,14,1,1},{1,15,5,1},{7,15,3,1},{0,16,3,1},{8,16,6,1},{11,17,3,1}}}
T.glyphs[32463] = {w=18, advance=16, rects={{3,4,1,2},{6,5,8,1},{2,6,2,1},{12,6,2,1},{1,7,2,1},{4,7,2,2},{11,7,2,1},{1,8,1,1},{9,8,3,1},{0,9,5,1},{7,9,3,1},{11,9,4,1},{3,10,1,1},{5,10,3,1},{14,10,2,1},{2,11,2,1},{1,12,2,1},{6,12,9,1},{1,13,5,1},{10,13,1,4},{1,14,2,1},{4,15,2,1},{1,16,4,1},{0,17,2,1},{5,17,11,1}}}
T.glyphs[32465] = {w=18, advance=16, rects={{2,4,2,2},{7,4,1,3},{10,5,5,1},{2,6,1,1},{10,6,2,1},{14,6,1,1},{1,7,2,1},{5,7,7,1},{13,7,2,2},{0,8,2,1},{3,8,2,1},{7,8,1,2},{10,8,2,2},{0,9,4,1},{13,9,1,2},{2,10,2,1},{5,10,7,1},{1,11,2,1},{7,11,1,2},{10,11,2,2},{13,11,2,1},{1,12,4,1},{14,12,1,1},{1,13,2,1},{5,13,7,1},{14,13,2,2},{6,14,2,2},{10,14,2,1},{1,15,4,1},{10,15,5,1},{0,16,3,1},{5,16,2,1},{10,16,2,2},{5,17,1,1}}}
T.glyphs[32467] = {w=18, advance=16, rects={{3,4,1,1},{10,4,1,2},{2,5,2,1},{2,6,1,1},{6,6,10,1},{1,7,2,1},{10,7,2,1},{1,8,1,1},{4,8,2,1},{10,8,1,1},{0,9,5,1},{6,9,9,1},{3,10,1,1},{2,11,1,1},{1,12,14,1},{1,13,3,1},{6,13,2,2},{13,13,2,3},{1,14,1,1},{1,15,7,1},{0,16,4,1},{6,16,9,1},{6,17,2,1},{13,17,2,1}}}
T.glyphs[32469] = {w=18, advance=16, rects={{3,4,1,1},{8,4,1,1},{2,5,2,1},{8,5,7,1},{2,6,1,1},{5,6,7,1},{1,7,2,1},{4,7,1,2},{9,7,1,1},{13,7,1,1},{1,8,1,1},{9,8,4,1},{0,9,5,1},{8,9,4,1},{14,9,2,1},{2,10,2,1},{5,10,3,1},{11,10,4,1},{2,11,1,1},{1,12,14,1},{1,13,2,1},{7,13,2,2},{11,13,1,4},{14,14,1,1},{1,15,5,1},{7,15,1,1},{14,15,2,1},{0,16,3,1},{6,16,2,1},{14,16,1,1},{5,17,2,1},{11,17,4,1},{5,18,1,1}}}
T.glyphs[32472] = {w=18, advance=16, rects={{2,4,2,2},{9,4,2,2},{2,6,1,1},{8,6,4,1},{1,7,1,1},{4,7,2,1},{7,7,2,1},{11,7,2,1},{0,8,2,1},{4,8,1,1},{7,8,1,1},{12,8,2,1},{0,9,5,1},{6,9,2,1},{13,9,2,1},{2,10,2,1},{5,10,8,1},{14,10,2,1},{2,11,1,1},{1,12,2,1},{0,13,5,1},{6,13,9,1},{8,14,2,1},{7,15,2,2},{11,15,1,1},{1,16,5,1},{12,16,1,1},{0,17,3,1},{6,17,2,1},{12,17,2,1},{6,18,9,1},{13,19,2,1}}}
T.glyphs[32473] = {w=18, advance=16, rects={{3,4,1,1},{9,4,2,1},{2,5,2,1},{9,5,3,1},{2,6,1,1},{8,6,2,1},{11,6,2,1},{1,7,2,1},{4,7,2,1},{7,7,2,1},{12,7,2,1},{1,8,1,1},{4,8,4,1},{13,8,2,1},{0,9,16,1},{2,10,2,1},{2,11,1,1},{1,12,2,1},{6,12,8,1},{1,13,4,1},{6,13,2,3},{13,13,1,4},{1,16,7,1},{0,17,3,1},{6,17,8,1},{6,18,2,1},{13,18,1,1}}}
T.glyphs[32477] = {w=18, advance=16, rects={{2,4,2,2},{8,4,2,1},{8,5,1,1},{2,6,1,1},{7,6,6,1},{1,7,1,1},{4,7,1,2},{7,7,1,1},{11,7,2,1},{0,8,2,1},{6,8,1,1},{11,8,1,1},{0,9,4,1},{5,9,10,1},{2,10,2,1},{5,10,2,1},{10,10,1,2},{13,10,2,2},{2,11,1,1},{6,11,1,1},{1,12,4,1},{6,12,9,1},{1,13,2,1},{6,13,1,2},{13,13,2,1},{1,15,6,1},{14,15,2,2},{0,16,3,1},{6,16,2,1},{6,17,9,1}}}
T.glyphs[32479] = {w=18, advance=16, rects={{3,4,1,1},{9,4,2,1},{2,5,2,1},{10,5,1,1},{2,6,1,1},{5,6,11,1},{1,7,2,1},{8,7,2,1},{1,8,1,1},{4,8,1,1},{7,8,2,1},{12,8,1,1},{0,9,5,1},{6,9,2,1},{12,9,2,1},{2,10,2,1},{6,10,9,1},{2,11,1,1},{8,11,1,3},{11,11,1,6},{14,11,1,1},{1,12,4,1},{1,13,3,1},{1,14,1,1},{3,14,3,1},{7,14,2,1},{14,14,2,3},{1,15,3,1},{7,15,1,1},{0,16,2,1},{6,16,2,1},{5,17,2,1},{11,17,4,1},{4,18,2,1}}}
T.glyphs[32487] = {w=18, advance=16, rects={{2,4,2,2},{11,4,1,4},{6,5,1,5},{8,5,1,1},{13,5,2,2},{2,6,1,1},{8,6,2,2},{1,7,1,1},{4,7,1,1},{13,7,1,1},{0,8,2,1},{3,8,2,1},{9,8,1,1},{11,8,3,1},{0,9,4,1},{11,9,1,1},{2,10,1,1},{6,10,9,1},{1,11,2,1},{6,11,1,4},{10,11,2,1},{1,12,4,1},{9,12,4,1},{9,13,1,1},{11,13,1,3},{13,13,2,1},{8,14,1,1},{14,14,1,1},{1,15,4,1},{6,15,3,1},{0,16,3,1},{6,16,1,1},{6,17,10,1}}}
T.glyphs[32490] = {w=18, advance=16, rects={{3,4,1,1},{9,4,1,2},{14,4,1,1},{2,5,2,1},{13,5,2,1},{2,6,1,1},{6,6,8,1},{1,7,2,1},{4,7,2,1},{9,7,1,2},{12,7,1,1},{1,8,1,1},{4,8,1,1},{11,8,2,1},{0,9,16,1},{3,10,1,1},{9,10,2,1},{2,11,1,1},{7,11,7,1},{1,12,8,1},{13,12,1,1},{1,13,3,1},{5,13,9,1},{7,14,2,2},{13,14,1,2},{2,15,4,1},{0,16,4,1},{7,16,7,1},{7,17,2,1},{13,17,1,1}}}
T.glyphs[32493] = {w=18, advance=16, rects={{2,4,2,1},{10,4,1,1},{2,5,1,1},{6,5,9,1},{1,6,2,1},{4,6,1,1},{10,6,1,1},{1,7,1,1},{4,7,12,1},{0,8,5,1},{14,8,1,1},{2,9,2,1},{7,9,2,1},{10,9,2,1},{13,9,2,2},{2,10,1,1},{8,10,4,1},{1,11,2,1},{6,11,2,1},{10,11,2,2},{0,12,5,1},{7,12,2,1},{5,13,11,1},{9,14,3,1},{1,15,4,1},{8,15,2,1},{12,15,2,1},{0,16,3,1},{7,16,2,1},{13,16,2,1},{5,17,2,1},{14,17,2,1}}}
T.glyphs[32500] = {w=18, advance=16, rects={{2,4,2,2},{8,4,1,1},{10,4,2,1},{7,5,2,1},{11,5,1,1},{2,6,1,1},{7,6,1,1},{11,6,2,1},{1,7,2,1},{4,7,1,1},{6,7,10,1},{0,8,2,1},{3,8,2,1},{6,8,2,1},{11,8,1,2},{0,9,4,1},{5,9,3,1},{2,10,2,1},{5,10,10,1},{2,11,1,1},{6,11,2,2},{11,11,1,2},{1,12,2,1},{1,13,4,1},{6,13,9,1},{0,14,3,1},{6,14,2,2},{11,14,1,3},{1,16,7,1},{0,17,4,1},{6,17,10,1},{6,18,2,1}}}
T.glyphs[32511] = {w=18, advance=16, rects={{3,4,1,1},{2,5,2,1},{6,5,8,1},{2,6,1,1},{13,6,1,1},{1,7,2,1},{4,7,10,1},{1,8,1,1},{4,8,1,1},{13,8,1,1},{0,9,4,1},{5,9,11,1},{2,10,2,1},{10,10,1,1},{2,11,1,1},{10,11,2,1},{14,11,1,1},{1,12,4,1},{6,12,2,1},{10,12,5,1},{1,13,3,1},{8,13,5,1},{1,14,1,1},{7,14,2,1},{10,14,1,3},{12,14,2,1},{1,15,4,1},{6,15,2,1},{13,15,2,1},{0,16,3,1},{5,16,2,1},{14,16,1,1},{7,17,4,1}}}
T.glyphs[32534] = {w=18, advance=16, rects={{3,4,1,1},{9,4,2,2},{2,5,2,1},{2,6,1,1},{5,6,10,1},{1,7,2,1},{5,7,2,1},{14,7,1,2},{1,8,1,1},{4,8,3,1},{0,9,2,1},{3,9,12,1},{0,10,4,1},{5,10,2,1},{2,11,1,1},{5,11,10,1},{1,12,2,1},{5,12,3,1},{9,12,1,2},{12,12,1,2},{14,12,1,2},{0,13,6,1},{7,13,1,1},{5,14,1,2},{7,14,8,1},{7,15,1,4},{9,15,1,3},{12,15,1,3},{14,15,1,3},{1,16,5,1},{0,17,2,1},{4,17,1,1},{3,18,2,1},{12,18,3,1}}}
T.glyphs[32536] = {w=18, advance=16, rects={{3,4,1,1},{7,4,2,1},{2,5,2,1},{7,5,7,1},{2,6,1,1},{7,6,1,1},{12,6,2,1},{1,7,2,1},{4,7,2,1},{7,7,7,1},{1,8,1,1},{4,8,1,1},{12,8,1,1},{0,9,16,1},{2,10,2,1},{8,10,2,1},{2,11,1,1},{7,11,4,1},{13,11,1,1},{1,12,2,1},{5,12,2,1},{9,12,5,1},{1,13,4,1},{8,13,1,1},{10,13,4,1},{6,14,2,1},{10,14,2,1},{13,14,1,2},{5,15,2,1},{9,15,3,1},{1,16,4,1},{8,16,1,1},{11,16,1,1},{14,16,1,1},{0,17,3,1},{6,17,2,1},{10,17,2,1},{14,17,2,1},{5,18,2,1},{8,18,3,1}}}
T.glyphs[32541] = {w=18, advance=16, rects={{2,4,2,2},{5,4,1,1},{9,4,2,1},{5,5,2,1},{9,5,6,1},{2,6,1,1},{6,6,1,1},{8,6,2,1},{13,6,1,1},{1,7,1,1},{4,7,1,1},{7,7,2,1},{10,7,3,1},{0,8,2,1},{3,8,2,1},{9,8,5,1},{0,9,10,1},{13,9,3,1},{2,10,1,1},{5,10,2,2},{11,10,1,1},{1,11,2,1},{8,11,7,1},{1,12,6,1},{11,12,1,1},{5,13,2,2},{8,13,7,1},{11,14,1,1},{1,15,15,1},{0,16,3,1},{5,16,3,1},{11,16,1,1},{4,17,2,1},{7,17,9,1},{4,18,1,1}}}
T.glyphs[32553] = {w=18, advance=16, rects={{3,4,1,1},{9,4,2,1},{2,5,2,1},{10,5,1,1},{2,6,1,1},{5,6,10,1},{1,7,2,1},{4,7,3,1},{14,7,1,1},{1,8,1,1},{3,8,2,1},{7,8,1,1},{0,9,4,1},{7,9,9,1},{2,10,1,1},{6,10,2,1},{11,10,1,2},{1,11,2,1},{5,11,2,1},{1,12,6,1},{9,12,6,1},{5,13,2,1},{9,13,1,1},{13,13,2,1},{6,14,1,5},{9,14,6,1},{1,15,4,1},{9,15,1,2},{13,15,2,2},{0,16,3,1},{9,17,6,1},{9,18,1,1},{13,18,2,1}}}
T.glyphs[32570] = {w=18, advance=16, rects={{2,4,1,1},{10,4,2,3},{2,5,5,1},{1,6,1,2},{3,6,2,4},{8,7,7,1},{0,8,2,1},{10,8,2,3},{13,8,2,3},{0,10,8,1},{3,11,2,5},{7,11,9,1},{1,12,1,4},{6,12,1,4},{10,12,2,2},{9,14,4,1},{8,15,2,1},{12,15,2,1},{1,16,8,1},{13,16,2,1},{6,17,3,1},{14,17,2,1}}}
T.glyphs[32602] = {w=18, advance=16, rects={{1,5,14,1},{1,6,2,2},{5,6,2,2},{9,6,2,2},{13,6,2,2},{1,8,14,1},{3,10,1,1},{8,10,2,7},{13,10,1,8},{3,11,2,1},{4,12,1,1},{0,13,4,1},{2,14,2,1},{3,15,1,2},{6,15,1,1},{5,16,2,1},{2,17,3,1},{2,18,2,1},{10,18,4,1}}}
T.glyphs[32622] = {w=18, advance=16, rects={{1,5,14,1},{1,6,2,1},{5,6,2,1},{9,6,2,1},{13,6,2,1},{1,7,14,1},{7,8,2,1},{1,9,14,1},{7,10,2,1},{2,11,12,1},{2,12,2,1},{12,12,2,1},{2,13,12,1},{2,14,2,1},{12,14,2,1},{2,15,12,1},{2,16,2,1},{12,16,2,1},{0,17,16,1}}}
T.glyphs[32763] = {w=18, advance=16, rects={{5,4,2,1},{1,5,5,1},{8,5,7,1},{1,6,2,1},{4,6,1,2},{6,6,1,1},{10,6,1,4},{14,6,1,6},{0,8,9,1},{12,8,1,3},{3,9,2,1},{8,9,1,1},{2,10,4,1},{9,10,2,1},{1,11,2,1},{4,11,1,2},{6,11,1,1},{10,11,1,1},{0,12,2,1},{7,12,1,1},{9,12,2,1},{13,12,2,1},{1,13,10,1},{12,13,3,1},{1,14,1,1},{4,14,1,1},{6,14,3,1},{10,14,1,4},{14,14,1,4},{1,15,7,1},{1,16,1,1},{4,16,1,1},{6,16,2,1},{1,17,7,1},{1,18,1,1},{6,18,5,1},{12,18,3,1}}}
T.glyphs[32769] = {w=18, advance=16, rects={{6,4,2,2},{2,6,9,1},{13,6,1,1},{6,7,2,2},{12,7,2,1},{10,8,3,1},{0,9,16,1},{7,10,3,1},{5,11,3,1},{4,12,3,1},{11,12,2,1},{1,13,5,1},{9,13,3,1},{0,14,2,1},{4,14,2,1},{7,14,3,1},{13,14,1,2},{4,15,4,1},{4,16,2,1},{12,16,2,1},{5,17,9,1}}}
T.glyphs[32771] = {w=18, advance=16, rects={{6,4,1,2},{13,5,1,1},{2,6,9,1},{12,6,2,1},{6,7,1,2},{10,7,3,1},{9,8,2,1},{0,9,16,1},{6,10,3,1},{4,11,11,1},{1,12,6,1},{0,13,3,1},{5,13,8,1},{11,14,2,2},{11,16,1,1},{6,17,6,1},{9,18,1,1}}}
T.glyphs[32773] = {w=18, advance=16, rects={{6,4,2,2},{13,5,1,1},{2,6,12,1},{6,7,2,2},{11,7,2,1},{10,8,2,1},{0,9,16,1},{6,10,3,1},{4,11,4,1},{2,12,11,1},{0,13,5,1},{12,13,1,1},{3,14,10,1},{3,15,2,2},{12,15,1,2},{3,17,10,1},{3,18,2,1},{12,18,1,1}}}
T.glyphs[32780] = {w=18, advance=16, rects={{0,5,16,1},{7,6,2,1},{7,7,1,2},{1,9,14,1},{1,10,2,9},{5,10,2,8},{9,10,2,8},{13,10,2,8},{11,18,3,1}}}
T.glyphs[32905] = {w=18, advance=16, rects={{7,4,2,2},{1,6,14,1},{1,7,2,8},{7,7,2,1},{13,7,2,3},{6,8,4,1},{5,9,2,1},{9,9,3,1},{4,10,1,1},{7,10,2,3},{11,10,4,1},{13,11,2,6},{6,13,5,1},{4,14,3,1},{10,14,2,1},{1,15,4,1},{11,15,1,1},{1,16,2,3},{10,17,4,1}}}
T.glyphs[32972] = {w=18, advance=16, rects={{5,4,2,2},{9,4,1,2},{12,5,3,1},{1,6,6,1},{9,6,5,1},{5,7,2,1},{9,7,1,2},{14,7,2,2},{1,8,6,1},{0,9,3,1},{5,9,2,1},{9,9,6,1},{2,11,12,1},{2,12,2,1},{12,12,2,1},{2,13,12,1},{2,14,2,1},{12,14,2,1},{2,15,12,1},{2,16,2,3},{12,16,2,2},{8,18,5,1}}}
T.glyphs[32988] = {w=18, advance=16, rects={{10,4,2,4},{1,5,5,1},{7,5,2,3},{1,6,2,3},{4,6,2,3},{7,8,9,1},{1,9,7,1},{10,9,2,3},{1,10,2,3},{4,10,4,1},{4,11,2,2},{7,12,8,1},{1,13,5,1},{10,13,2,4},{1,14,2,2},{4,14,2,3},{1,16,1,1},{0,17,2,1},{4,17,12,1},{1,18,4,1}}}
T.glyphs[33014] = {w=18, advance=16, rects={{10,4,1,1},{1,5,5,1},{10,5,2,1},{1,6,2,3},{4,6,12,1},{4,7,2,2},{8,8,1,1},{12,8,1,1},{1,9,5,1},{7,9,2,1},{12,9,2,1},{1,10,2,3},{4,10,4,1},{13,10,2,1},{4,11,3,1},{8,11,1,1},{12,11,3,1},{4,12,2,1},{8,12,2,1},{12,12,1,1},{1,13,5,1},{9,13,1,1},{11,13,2,1},{1,14,2,1},{4,14,2,4},{9,14,3,1},{1,15,1,3},{10,15,2,1},{9,16,4,1},{7,17,3,1},{12,17,3,1},{0,18,1,1},{3,18,5,1},{13,18,2,1}}}
T.glyphs[33021] = {w=18, advance=16, rects={{3,4,1,1},{9,4,1,2},{2,5,2,1},{13,5,2,1},{2,6,1,1},{5,6,2,1},{9,6,5,1},{1,7,2,1},{6,7,1,1},{9,7,3,1},{14,7,1,1},{0,8,8,1},{9,8,1,1},{14,8,2,1},{7,9,1,1},{9,9,2,1},{14,9,1,1},{1,10,7,1},{9,10,6,1},{1,11,2,2},{6,11,2,2},{9,12,1,2},{14,12,1,1},{1,13,7,1},{13,13,2,1},{1,14,2,1},{6,14,2,1},{9,14,4,1},{1,15,7,1},{9,15,3,1},{14,15,2,2},{1,16,2,3},{6,16,2,2},{9,16,1,2},{14,17,1,1},{4,18,3,1},{9,18,6,1}}}
T.glyphs[33033] = {w=18, advance=16, rects={{8,4,2,1},{1,5,4,1},{9,5,3,1},{1,6,2,1},{4,6,1,3},{11,6,2,1},{1,7,1,2},{6,7,5,1},{10,8,1,1},{14,8,1,1},{1,9,4,1},{10,9,2,1},{13,9,2,1},{1,10,1,3},{4,10,5,1},{10,10,4,1},{4,11,1,2},{8,11,1,2},{10,11,3,3},{1,13,4,1},{7,13,2,1},{1,14,1,3},{4,14,1,2},{7,14,1,1},{10,14,1,4},{12,14,2,1},{6,15,2,1},{13,15,1,1},{4,16,3,2},{13,16,2,1},{0,17,2,1},{14,17,2,1},{0,18,5,1},{8,18,3,1}}}
T.glyphs[33039] = {w=18, advance=16, rects={{10,4,2,1},{1,5,5,1},{11,5,1,1},{1,6,1,3},{4,6,2,3},{7,6,9,1},{7,7,1,4},{11,8,1,3},{1,9,5,1},{1,10,1,3},{4,10,2,3},{7,11,8,1},{7,12,1,3},{11,12,1,5},{1,13,5,1},{1,14,1,4},{4,14,2,1},{4,15,4,2},{4,17,12,1},{0,18,5,1},{6,18,1,1}}}
T.glyphs[33041] = {w=18, advance=16, rects={{10,4,1,1},{1,5,5,1},{10,5,2,1},{1,6,2,3},{4,6,12,1},{4,7,2,2},{8,8,2,1},{12,8,1,2},{1,9,5,1},{7,9,1,6},{9,9,1,1},{14,9,1,6},{1,10,2,3},{4,10,2,3},{9,10,4,1},{10,11,2,2},{1,13,5,1},{9,13,4,1},{1,14,2,1},{4,14,2,4},{9,14,1,1},{12,14,1,1},{1,15,1,2},{7,15,3,1},{12,15,3,1},{7,16,1,1},{14,16,1,1},{0,17,2,1},{7,17,8,1},{0,18,5,1},{14,18,1,1}}}
T.glyphs[33050] = {w=18, advance=16, rects={{7,4,2,3},{1,5,4,1},{11,5,4,1},{1,6,1,3},{4,6,1,3},{11,6,1,4},{14,6,1,10},{6,7,4,1},{7,8,2,2},{1,9,4,1},{1,10,1,3},{4,10,8,1},{4,11,1,2},{7,11,1,2},{11,11,1,5},{1,13,4,1},{6,13,4,1},{1,14,1,3},{4,14,1,2},{6,14,1,1},{9,14,1,1},{6,15,4,1},{4,16,4,1},{9,16,6,1},{0,17,2,1},{4,17,1,1},{11,17,1,2},{0,18,1,1},{2,18,3,1}}}
T.glyphs[33073] = {w=18, advance=16, rects={{8,4,1,1},{12,4,2,1},{1,5,5,1},{8,5,2,2},{12,5,1,1},{1,6,1,3},{4,6,2,3},{11,6,2,1},{7,7,8,1},{7,8,1,3},{13,8,2,3},{1,9,5,1},{1,10,1,3},{4,10,2,3},{7,11,8,1},{7,12,1,1},{9,12,1,1},{11,12,1,5},{13,12,2,2},{1,13,5,1},{7,13,3,1},{1,14,1,3},{4,14,2,3},{8,14,2,1},{8,15,1,1},{14,15,2,3},{7,16,2,1},{0,17,2,1},{4,17,1,1},{6,17,2,1},{11,17,2,1},{0,18,1,1},{2,18,3,1},{6,18,1,1},{11,18,4,1}}}
T.glyphs[33080] = {w=18, advance=16, rects={{10,4,2,1},{1,5,5,1},{9,5,3,1},{1,6,2,1},{4,6,2,2},{8,6,2,1},{11,6,2,1},{1,7,1,2},{7,7,2,1},{12,7,2,1},{4,8,4,1},{13,8,2,1},{1,9,6,1},{14,9,2,1},{1,10,2,1},{4,10,2,3},{7,10,7,1},{1,11,1,2},{7,12,1,2},{10,12,1,3},{13,12,2,1},{1,13,5,1},{13,13,1,1},{1,14,1,3},{4,14,2,3},{7,14,2,1},{12,14,2,1},{8,15,1,1},{10,15,4,1},{12,16,1,1},{0,17,2,1},{4,17,12,1},{0,18,1,1},{2,18,3,1}}}
T.glyphs[33150] = {w=18, advance=16, rects={{10,4,1,3},{1,5,4,1},{7,5,1,1},{13,5,1,1},{1,6,1,3},{4,6,1,3},{7,6,2,1},{12,6,2,1},{6,7,9,1},{9,8,1,1},{1,9,15,1},{1,10,1,3},{4,10,1,2},{7,10,2,1},{12,10,1,1},{6,11,8,1},{4,12,3,1},{11,12,2,2},{14,12,2,1},{1,13,4,1},{7,13,2,1},{1,14,1,4},{4,14,1,2},{7,14,8,1},{13,15,2,1},{4,16,11,1},{4,17,1,1},{13,17,2,1},{0,18,5,1},{10,18,4,1}}}
T.glyphs[33151] = {w=18, advance=16, rects={{1,5,4,1},{6,5,1,1},{9,5,6,1},{1,6,1,3},{4,6,1,3},{6,6,2,1},{9,6,1,1},{13,6,2,1},{7,7,1,1},{9,7,6,1},{9,8,1,2},{13,8,2,2},{1,9,4,1},{1,10,1,3},{4,10,4,1},{9,10,6,1},{4,11,1,2},{6,11,2,6},{9,11,1,4},{14,11,1,2},{11,12,1,1},{1,13,4,1},{11,13,3,2},{1,14,1,4},{4,14,1,3},{9,15,3,1},{13,15,2,1},{9,16,1,1},{14,16,1,1},{4,17,3,1},{8,17,2,1},{0,18,1,1},{2,18,4,1},{9,18,7,1}}}
T.glyphs[33258] = {w=18, advance=16, rects={{6,4,2,2},{2,6,12,1},{2,7,1,3},{13,7,1,3},{2,10,12,1},{2,11,1,2},{13,11,1,2},{2,13,12,1},{2,14,1,3},{13,14,1,3},{2,17,12,1},{2,18,1,1},{13,18,1,1}}}
T.glyphs[33268] = {w=18, advance=16, rects={{10,4,1,1},{0,5,8,1},{9,5,2,1},{3,6,1,1},{9,6,1,1},{2,7,2,1},{5,7,1,1},{8,7,8,1},{2,8,1,1},{5,8,2,1},{8,8,2,1},{13,8,1,3},{1,9,9,1},{1,10,3,1},{6,10,2,1},{9,10,1,2},{3,11,2,2},{12,11,2,2},{9,12,2,1},{0,13,8,1},{10,13,1,1},{12,13,1,1},{3,14,2,2},{10,14,3,2},{2,16,6,1},{9,16,4,1},{0,17,5,1},{8,17,2,1},{13,17,2,1},{7,18,2,1},{14,18,2,1}}}
T.glyphs[33293] = {w=18, advance=16, rects={{7,4,2,1},{6,5,4,1},{5,6,2,1},{9,6,2,1},{3,7,2,1},{11,7,2,1},{1,8,14,1},{0,9,2,1},{7,9,2,2},{14,9,2,1},{1,11,14,1},{7,12,2,1},{3,13,10,1},{3,14,1,3},{12,14,1,3},{3,17,10,1},{3,18,1,1},{12,18,1,1}}}
T.glyphs[33298] = {w=18, advance=16, rects={{3,4,2,1},{3,5,4,1},{8,5,7,1},{2,6,2,1},{6,6,2,1},{13,6,2,1},{1,7,2,1},{7,7,1,1},{10,7,1,1},{12,7,2,1},{1,8,6,1},{10,8,3,1},{0,9,1,1},{4,9,1,2},{11,9,2,1},{8,10,8,1},{0,11,8,1},{11,11,1,7},{14,11,2,2},{4,12,1,2},{14,13,1,1},{1,14,6,1},{1,15,2,2},{6,15,1,2},{1,17,6,1},{1,18,2,1},{6,18,1,1},{8,18,4,1}}}
T.glyphs[33310] = {w=18, advance=16, rects={{2,4,2,1},{1,5,14,1},{3,6,1,2},{6,6,1,2},{9,6,1,2},{12,6,1,2},{1,8,14,1},{3,9,1,2},{6,9,1,2},{9,9,1,2},{12,9,1,2},{0,11,16,1},{3,12,1,1},{11,12,2,1},{2,13,14,1},{1,14,2,1},{6,14,4,1},{11,14,2,2},{0,15,2,1},{3,15,1,1},{5,15,2,1},{8,15,1,1},{3,16,3,1},{8,16,8,1},{2,17,3,1},{11,17,2,2},{1,18,2,1}}}
T.glyphs[33394] = {w=18, advance=16, rects={{5,3,1,1},{4,4,2,1},{3,5,9,1},{2,6,2,1},{9,6,2,1},{1,7,2,1},{9,7,1,1},{0,8,14,1},{2,9,2,1},{7,9,2,3},{12,9,2,1},{2,10,1,2},{13,10,1,2},{2,12,12,1},{2,13,2,1},{12,13,2,1},{2,14,1,2},{14,15,2,2},{2,16,2,1},{2,17,13,1}}}
T.glyphs[33410] = {w=18, advance=16, rects={{5,4,1,2},{10,4,1,2},{0,6,16,1},{4,7,2,1},{10,7,2,1},{5,8,1,1},{10,8,1,1},{1,10,13,1},{5,11,2,8},{12,11,2,5},{8,16,5,1}}}
T.glyphs[33509] = {w=18, advance=16, rects={{4,3,2,2},{10,3,2,2},{0,5,16,1},{4,6,2,2},{10,6,2,2},{7,7,1,1},{6,8,2,1},{0,9,16,1},{5,10,2,1},{4,11,2,1},{3,12,11,1},{1,13,4,1},{12,13,2,4},{0,14,2,1},{3,14,2,3},{3,17,11,1},{3,18,2,1},{12,18,2,1}}}
T.glyphs[33521] = {w=18, advance=16, rects={{4,4,2,2},{10,4,2,2},{0,6,16,1},{4,7,2,1},{10,7,2,1},{7,8,2,1},{2,9,12,1},{2,10,2,3},{7,10,2,3},{12,10,2,3},{0,13,16,1},{6,14,4,1},{5,15,2,1},{9,15,2,1},{2,16,4,1},{10,16,3,1},{1,17,2,1},{12,17,3,1}}}
T.glyphs[33539] = {w=18, advance=16, rects={{5,3,1,2},{10,3,2,2},{0,5,16,1},{4,6,2,1},{10,6,2,1},{2,7,2,1},{3,8,2,1},{6,8,8,1},{1,9,1,1},{4,9,1,1},{6,9,2,8},{12,9,2,4},{0,10,3,1},{1,11,2,1},{2,12,1,1},{3,13,2,2},{9,13,4,1},{14,14,2,3},{2,15,2,1},{1,16,2,2},{7,17,8,1}}}
T.glyphs[33616] = {w=18, advance=16, rects={{5,4,1,1},{10,4,2,1},{1,5,15,1},{5,6,1,1},{10,6,2,1},{5,7,2,1},{1,8,14,1},{4,9,2,1},{3,10,2,2},{6,11,9,1},{2,12,3,1},{11,12,3,1},{1,13,4,1},{10,13,2,1},{0,14,2,1},{3,14,13,1},{3,15,2,4},{10,15,2,3},{7,18,4,1}}}
T.glyphs[33756] = {w=18, advance=16, rects={{5,4,1,1},{10,4,1,1},{0,5,16,1},{5,6,1,1},{10,6,1,1},{1,8,13,1},{3,10,1,1},{7,10,1,1},{11,10,2,1},{3,11,2,1},{10,11,2,1},{7,12,2,1},{0,13,16,1},{5,14,6,1},{4,15,2,1},{7,15,2,4},{10,15,2,1},{2,16,2,1},{11,16,3,1},{1,17,2,1},{13,17,2,1}}}
T.glyphs[33853] = {w=18, advance=16, rects={{5,4,1,1},{10,4,2,1},{0,5,16,1},{4,6,2,1},{10,6,2,1},{1,7,2,1},{7,7,1,1},{2,8,2,1},{6,8,8,1},{5,9,3,1},{12,9,2,1},{0,10,2,1},{4,10,2,1},{7,10,2,1},{11,10,2,1},{1,11,2,1},{8,11,4,1},{4,12,5,1},{10,12,6,1},{2,13,2,2},{6,14,8,1},{2,15,1,1},{6,15,1,2},{12,15,2,1},{1,16,2,1},{13,16,1,1},{1,17,1,2},{6,17,8,1},{6,18,1,1},{12,18,2,1}}}
T.glyphs[33988] = {w=18, advance=16, rects={{5,4,1,1},{10,4,2,1},{0,5,16,1},{5,6,1,1},{7,6,2,1},{10,6,2,1},{1,7,14,1},{4,8,3,1},{10,8,3,1},{2,9,11,1},{4,10,4,1},{12,10,2,1},{2,11,13,1},{14,12,1,1},{2,13,12,1},{2,14,1,1},{7,14,2,1},{13,14,1,1},{2,15,12,1},{2,16,1,1},{7,16,2,1},{13,16,1,1},{2,17,12,1},{2,18,1,1},{13,18,1,1}}}
T.glyphs[34013] = {w=18, advance=16, rects={{5,4,1,1},{10,4,1,1},{0,5,16,1},{5,6,1,1},{10,6,1,1},{9,7,1,1},{2,8,1,4},{5,8,2,2},{8,8,8,1},{8,9,2,1},{5,10,4,2},{11,10,1,1},{12,11,2,1},{2,13,12,1},{2,14,2,3},{6,14,1,3},{9,14,2,1},{13,14,1,3},{9,15,1,2},{0,17,16,1}}}
T.glyphs[34394] = {w=18, advance=16, rects={{7,4,1,1},{7,5,8,1},{7,6,1,1},{2,7,13,1},{2,8,1,2},{7,8,1,1},{14,8,1,2},{6,9,7,1},{2,10,7,1},{2,11,1,2},{7,11,7,1},{1,13,2,3},{4,13,1,1},{7,13,1,4},{10,13,1,4},{13,13,1,1},{4,14,2,1},{12,14,2,1},{5,15,1,1},{12,15,1,1},{0,16,2,1},{0,17,1,1},{3,17,13,1}}}
T.glyphs[34429] = {w=18, advance=16, rects={{3,5,10,1},{3,6,1,2},{12,6,1,2},{3,8,10,1},{3,9,1,1},{7,9,2,2},{12,9,1,1},{2,11,12,1},{2,12,1,2},{7,12,2,2},{13,12,1,2},{2,14,12,1},{2,15,1,1},{7,15,2,2},{12,15,1,1},{12,16,2,1},{0,17,15,1},{14,18,1,1}}}
T.glyphs[34746] = {w=18, advance=16, rects={{3,4,1,2},{7,4,8,1},{7,5,1,1},{10,5,2,1},{14,5,1,1},{1,6,5,1},{7,6,8,1},{1,7,1,4},{3,7,1,4},{5,7,1,4},{7,7,1,1},{10,7,2,1},{14,7,1,1},{7,8,8,1},{9,9,2,1},{7,10,3,1},{12,10,2,1},{1,11,5,1},{7,11,6,1},{1,12,1,1},{3,12,1,3},{9,12,3,1},{13,12,1,1},{5,13,1,2},{7,13,3,1},{13,13,2,1},{7,14,9,1},{0,15,6,1},{8,15,1,1},{10,15,4,1},{5,16,4,1},{10,16,2,1},{13,16,2,1},{6,17,1,1},{8,17,3,1},{14,17,2,1}}}
T.glyphs[34880] = {w=18, advance=16, rects={{6,3,2,3},{2,6,12,1},{2,7,2,1},{5,7,2,10},{9,7,2,1},{12,7,2,1},{2,8,1,9},{9,8,1,9},{13,8,1,9},{0,17,16,1}}}
T.glyphs[34885] = {w=18, advance=16, rects={{3,4,2,1},{11,4,1,6},{3,5,1,1},{7,5,2,1},{14,5,1,2},{1,6,6,1},{8,6,1,1},{1,7,1,8},{3,7,2,8},{6,7,1,3},{8,7,2,1},{13,7,2,1},{9,8,1,1},{13,8,1,1},{6,10,9,1},{6,11,1,2},{11,11,1,2},{6,13,10,1},{6,14,1,1},{11,14,1,4},{1,15,7,1},{0,16,5,1}}}
T.glyphs[34892] = {w=18, advance=16, rects={{4,4,1,1},{3,5,2,1},{7,5,8,1},{2,6,2,1},{1,7,2,1},{1,8,1,1},{4,8,2,1},{4,9,1,1},{3,10,2,1},{6,10,10,1},{2,11,2,1},{11,11,2,7},{1,12,3,1},{0,13,4,1},{0,14,1,1},{3,14,1,5},{8,18,4,1}}}
T.glyphs[34917] = {w=18, advance=16, rects={{3,4,1,1},{9,4,2,5},{3,5,2,1},{0,7,6,1},{4,8,2,1},{3,9,2,2},{9,9,3,1},{6,10,2,1},{9,10,4,1},{1,11,3,1},{5,11,2,1},{9,11,2,8},{12,11,2,1},{0,12,6,1},{13,12,2,1},{0,13,1,1},{3,13,4,1},{14,13,1,1},{3,14,1,5},{6,14,1,1}}}
T.glyphs[34920] = {w=18, advance=16, rects={{7,4,2,1},{1,5,14,1},{7,6,2,2},{1,8,14,1},{7,9,2,1},{0,10,16,1},{6,11,3,1},{5,12,2,1},{8,12,1,1},{4,13,2,1},{9,13,1,1},{12,13,2,1},{3,14,3,1},{9,14,4,1},{1,15,3,1},{5,15,1,2},{10,15,2,1},{0,16,2,1},{8,16,2,1},{11,16,3,1},{4,17,5,1},{13,17,2,1},{4,18,2,1}}}
T.glyphs[34923] = {w=18, advance=16, rects={{2,4,2,1},{13,4,1,1},{3,5,1,2},{12,5,2,1},{10,6,3,1},{0,7,6,1},{8,7,3,1},{4,8,2,1},{7,8,2,1},{3,9,2,1},{13,9,2,1},{2,10,2,1},{6,10,1,1},{11,10,3,1},{1,11,3,1},{5,11,1,1},{9,11,3,1},{0,12,6,1},{7,12,3,1},{0,13,1,1},{3,13,3,1},{14,13,2,1},{3,14,1,5},{5,14,1,1},{13,14,2,1},{11,15,3,1},{9,16,3,1},{6,17,4,1},{6,18,2,1}}}
T.glyphs[34928] = {w=18, advance=16, rects={{7,4,1,1},{7,5,2,1},{1,6,14,1},{2,8,11,1},{2,9,2,1},{12,9,1,1},{0,10,16,1},{2,11,2,1},{12,11,1,1},{2,12,11,1},{6,13,3,1},{13,13,1,1},{4,14,2,1},{8,14,2,1},{11,14,2,1},{2,15,4,1},{9,15,3,1},{0,16,2,1},{4,16,2,1},{7,16,2,1},{11,16,3,1},{4,17,4,1},{13,17,2,1},{4,18,2,1}}}
T.glyphs[34955] = {w=18, advance=16, rects={{4,4,2,1},{8,4,1,1},{11,4,1,1},{3,5,2,1},{8,5,2,1},{12,5,1,1},{2,6,2,1},{8,6,7,1},{1,7,3,1},{5,7,10,1},{0,8,2,1},{3,8,1,3},{9,8,2,1},{14,8,2,2},{10,9,2,1},{7,10,1,1},{11,10,4,1},{7,11,2,1},{0,12,16,1},{6,13,3,1},{13,13,1,1},{4,14,3,1},{8,14,2,1},{12,14,2,1},{2,15,4,1},{9,15,3,1},{0,16,3,1},{4,16,2,1},{8,16,1,1},{10,16,2,1},{4,17,4,1},{11,17,3,1},{4,18,2,1},{13,18,2,1}}}
T.glyphs[34987] = {w=18, advance=16, rects={{2,4,1,1},{10,4,2,2},{2,5,2,1},{3,6,1,1},{6,6,10,1},{0,7,8,1},{10,7,2,3},{14,7,1,2},{4,8,1,1},{6,8,2,2},{3,9,2,1},{2,10,2,1},{5,10,10,1},{1,11,9,1},{13,11,1,2},{0,12,5,1},{6,12,2,2},{9,12,1,2},{0,13,1,1},{2,13,3,1},{12,13,2,1},{2,14,2,5},{5,14,2,1},{9,14,2,1},{12,14,1,1},{6,15,1,1},{10,15,3,2},{5,16,2,1},{5,17,1,2},{8,17,2,1},{12,17,3,1},{7,18,2,1},{14,18,1,1}}}
T.glyphs[35009] = {w=18, advance=16, rects={{4,4,2,1},{9,4,2,1},{12,4,1,1},{1,5,10,1},{12,5,2,1},{4,6,2,2},{9,6,2,2},{13,6,2,1},{0,8,16,1},{4,9,1,1},{9,9,2,1},{4,10,2,1},{10,10,1,3},{13,10,1,2},{0,11,9,1},{3,12,2,1},{12,12,2,1},{2,13,2,1},{7,13,2,1},{10,13,3,2},{1,14,3,1},{5,14,3,1},{0,15,4,1},{6,15,2,1},{10,15,2,1},{14,15,2,3},{2,16,2,1},{5,16,1,1},{7,16,6,1},{2,17,4,1},{8,17,2,1},{12,17,1,1},{2,18,2,1},{7,18,2,1},{12,18,3,1}}}
T.glyphs[35013] = {w=18, advance=16, rects={{5,4,1,2},{10,4,2,2},{1,5,2,1},{2,6,14,1},{4,7,2,1},{10,7,2,2},{2,8,4,1},{1,9,2,1},{5,9,1,2},{7,9,8,1},{1,10,1,1},{7,10,1,1},{7,11,2,1},{0,12,16,1},{6,13,3,1},{13,13,1,1},{4,14,3,1},{8,14,2,1},{12,14,2,1},{2,15,4,1},{9,15,3,1},{0,16,3,1},{4,16,2,1},{8,16,4,1},{4,17,4,1},{11,17,3,1},{4,18,2,1},{13,18,2,1}}}
T.glyphs[35044] = {w=18, advance=16, rects={{2,4,1,1},{10,4,1,1},{2,5,2,2},{10,5,2,1},{6,6,10,1},{0,7,5,1},{6,7,1,2},{3,8,2,1},{10,8,1,2},{2,9,2,1},{5,9,2,1},{1,10,4,1},{6,10,10,1},{0,11,5,1},{6,11,1,1},{9,11,1,1},{11,11,2,2},{0,12,1,1},{2,12,5,1},{8,12,2,1},{2,13,1,5},{6,13,1,1},{8,13,7,1},{5,14,2,1},{11,14,2,1},{5,15,1,1},{7,15,9,1},{4,16,2,1},{11,16,2,2},{4,17,1,1}}}
T.glyphs[35064] = {w=18, advance=16, rects={{2,4,1,1},{2,5,2,2},{6,5,9,1},{6,6,1,2},{9,6,2,2},{13,6,2,2},{0,7,5,1},{3,8,2,1},{6,8,9,1},{3,9,1,1},{6,9,1,1},{9,9,2,1},{13,9,2,1},{2,10,13,1},{1,11,4,1},{6,11,1,1},{9,11,2,2},{13,11,2,1},{0,12,5,1},{0,13,1,1},{2,13,13,1},{2,14,1,5},{4,14,1,1},{8,14,4,1},{7,15,4,1},{12,15,1,1},{5,16,3,1},{9,16,2,3},{13,16,2,1},{4,17,2,1},{14,17,2,1}}}
T.glyphs[35199] = {w=18, advance=16, rects={{0,5,16,1},{5,6,2,1},{9,6,2,2},{6,7,1,1},{1,8,14,1},{1,9,2,5},{5,9,2,2},{9,9,2,4},{14,9,1,4},{5,11,1,1},{4,12,2,1},{4,13,1,1},{10,13,5,1},{1,14,3,1},{14,14,1,3},{1,15,2,2},{1,17,14,1},{1,18,2,1},{14,18,1,1}}}
T.glyphs[35201] = {w=18, advance=16, rects={{1,5,14,1},{5,6,2,1},{9,6,2,1},{1,7,14,1},{1,8,2,2},{5,8,2,2},{9,8,2,2},{13,8,2,2},{1,10,14,1},{1,11,2,1},{5,11,2,2},{13,11,2,1},{0,13,16,1},{4,14,1,1},{10,14,2,1},{3,15,4,1},{9,15,2,1},{5,16,5,1},{4,17,9,1},{1,18,4,1},{12,18,2,1}}}
T.glyphs[35206] = {w=18, advance=16, rects={{1,4,14,1},{5,5,2,1},{9,5,2,1},{1,6,14,1},{1,7,2,1},{5,7,2,1},{9,7,2,1},{13,7,2,1},{2,8,13,1},{6,9,2,1},{3,10,1,1},{5,10,10,1},{1,11,2,1},{6,11,1,1},{13,11,1,1},{1,12,1,1},{6,12,8,1},{3,13,2,1},{6,13,1,1},{13,13,1,1},{2,14,2,1},{6,14,8,1},{1,15,3,1},{6,15,3,1},{11,15,2,1},{2,16,4,1},{8,16,4,1},{2,17,2,2},{6,17,8,1},{5,18,3,1},{12,18,4,1}}}
T.glyphs[35265] = {w=18, advance=16, rects={{2,5,12,1},{2,6,2,9},{12,6,2,9},{7,7,2,5},{7,12,1,1},{7,13,3,1},{6,14,4,2},{14,15,2,3},{5,16,2,1},{8,16,2,2},{3,17,3,1},{1,18,3,1},{8,18,7,1},{1,19,2,1}}}
T.glyphs[35266] = {w=18, advance=16, rects={{7,5,8,1},{0,6,6,1},{7,6,1,8},{13,6,2,8},{4,7,2,3},{10,7,1,6},{1,9,1,1},{1,10,2,1},{4,10,1,1},{2,11,3,2},{3,13,2,2},{10,13,2,1},{9,14,3,2},{2,15,4,1},{14,15,2,3},{1,16,2,1},{4,16,2,1},{8,16,2,1},{11,16,1,2},{1,17,1,1},{5,17,1,1},{7,17,2,1},{0,18,2,1},{6,18,2,1},{11,18,4,1},{5,19,2,1}}}
T.glyphs[35268] = {w=18, advance=16, rects={{3,3,1,3},{7,4,8,1},{7,5,1,5},{13,5,2,9},{0,6,6,1},{10,6,1,7},{3,7,1,3},{0,10,8,1},{2,11,2,2},{7,11,1,3},{2,13,3,1},{9,13,3,2},{2,14,1,2},{4,14,2,1},{5,15,2,1},{9,15,1,1},{11,15,1,3},{14,15,2,3},{1,16,2,1},{6,16,1,1},{8,16,2,1},{1,17,1,1},{7,17,2,1},{0,18,1,1},{6,18,2,1},{11,18,4,1},{6,19,1,1}}}
T.glyphs[35270] = {w=18, advance=16, rects={{2,4,1,1},{2,5,2,1},{6,5,9,1},{3,6,1,1},{6,6,2,1},{13,6,2,8},{0,7,8,1},{10,7,1,5},{3,8,2,2},{6,8,2,4},{2,10,2,1},{1,11,4,1},{0,12,8,1},{9,12,2,1},{0,13,1,1},{2,13,2,7},{5,13,3,1},{9,13,3,3},{15,15,1,2},{8,16,4,1},{7,17,2,1},{11,17,1,1},{14,17,2,1},{6,18,2,1},{11,18,4,1},{5,19,1,1}}}
T.glyphs[35273] = {w=18, advance=16, rects={{2,4,2,1},{7,4,1,1},{12,4,2,1},{3,5,1,1},{7,5,2,1},{11,5,2,1},{3,6,2,1},{8,6,1,1},{11,6,1,1},{1,7,14,1},{1,8,1,2},{14,8,1,2},{3,10,10,1},{3,11,1,5},{12,11,1,5},{7,12,2,1},{7,13,1,1},{7,14,2,1},{6,15,3,1},{14,15,2,3},{6,16,1,1},{8,16,1,1},{4,17,2,1},{8,17,2,1},{2,18,3,1},{8,18,7,1},{0,19,3,1}}}
T.glyphs[35282] = {w=18, advance=16, rects={{4,4,2,1},{4,5,8,1},{3,6,2,1},{10,6,2,1},{2,7,2,1},{9,7,2,1},{1,8,14,1},{1,9,3,1},{7,9,2,1},{13,9,2,2},{2,10,2,1},{8,10,1,1},{2,11,13,1},{2,12,2,2},{7,12,2,1},{13,12,2,2},{8,13,1,1},{2,14,13,1},{2,15,1,1},{7,15,2,1},{13,15,2,3},{1,16,2,2},{8,16,1,3},{1,18,1,1},{10,18,4,1}}}
T.glyphs[35299] = {w=18, advance=16, rects={{3,4,1,1},{2,5,2,1},{8,5,7,1},{1,6,5,1},{9,6,2,2},{13,6,2,3},{1,7,1,1},{4,7,2,1},{0,8,7,1},{9,8,1,1},{1,9,2,2},{4,9,1,2},{6,9,1,1},{8,9,2,1},{11,9,3,1},{6,10,3,1},{1,11,6,1},{9,11,1,1},{11,11,2,1},{1,12,2,2},{4,12,1,2},{6,12,1,2},{9,12,6,1},{8,13,1,2},{11,13,2,2},{1,14,6,1},{1,15,1,2},{4,15,1,2},{6,15,10,1},{6,16,1,2},{11,16,2,3},{0,17,2,2},{4,18,3,1}}}
T.glyphs[35302] = {w=18, advance=16, rects={{3,3,1,1},{2,4,2,1},{11,4,1,3},{2,5,5,1},{1,6,2,1},{5,6,1,1},{1,7,1,1},{4,7,2,1},{8,7,7,1},{0,8,7,1},{8,8,2,4},{11,8,1,4},{14,8,1,4},{1,9,1,2},{4,9,1,2},{6,9,1,2},{1,11,6,1},{1,12,1,2},{4,12,1,2},{6,12,1,2},{8,12,7,1},{8,13,2,1},{11,13,1,3},{1,14,6,1},{13,14,1,1},{1,15,1,2},{4,15,1,2},{6,15,1,2},{13,15,2,1},{10,16,5,1},{0,17,2,1},{6,17,6,1},{14,17,2,2},{0,18,1,1},{4,18,3,1}}}
T.glyphs[35328] = {w=18, advance=16, rects={{7,4,1,1},{7,5,2,1},{0,6,16,1},{2,8,12,1},{2,10,12,1},{2,12,12,1},{2,13,2,3},{12,13,2,3},{2,16,12,1},{2,17,2,1},{12,17,2,1}}}
T.glyphs[35686] = {w=18, advance=16, rects={{3,4,1,1},{6,4,1,1},{10,4,2,1},{0,5,9,1},{10,5,1,1},{1,6,2,1},{9,6,7,1},{1,7,7,1},{9,7,2,1},{13,7,1,1},{2,8,1,1},{5,8,1,1},{7,8,1,2},{9,8,1,1},{11,8,3,2},{2,9,4,1},{2,10,1,1},{5,10,3,1},{9,10,2,1},{13,10,2,1},{8,11,1,1},{0,12,16,1},{3,14,10,1},{2,16,12,1},{3,17,1,1},{12,17,1,1},{3,18,10,1}}}
T.glyphs[35745] = {w=18, advance=16, rects={{1,4,1,1},{10,4,1,5},{1,5,2,1},{2,6,2,1},{3,7,1,1},{0,9,4,1},{5,9,11,1},{2,10,2,6},{10,10,1,9},{6,15,1,1},{2,16,5,1},{2,17,3,1},{2,18,2,1}}}
T.glyphs[35748] = {w=18, advance=16, rects={{2,4,1,1},{9,4,2,8},{2,5,2,1},{3,6,2,1},{4,7,1,1},{0,9,4,1},{2,10,2,5},{9,12,3,1},{8,13,2,1},{11,13,1,1},{5,14,1,1},{8,14,1,1},{11,14,2,1},{2,15,3,1},{7,15,2,1},{12,15,1,1},{2,16,2,1},{6,16,2,1},{12,16,2,1},{2,17,1,1},{5,17,2,1},{13,17,2,1},{5,18,1,1},{14,18,1,1}}}
T.glyphs[35753] = {w=18, advance=16, rects={{2,3,1,1},{9,3,2,5},{2,4,2,1},{3,5,2,1},{4,6,1,1},{9,8,6,1},{0,9,4,1},{9,9,2,8},{2,10,2,5},{5,14,1,1},{2,15,4,1},{2,16,3,1},{2,17,2,1},{5,17,11,1}}}
T.glyphs[35760] = {w=18, advance=16, rects={{1,4,2,2},{5,5,10,1},{2,6,2,1},{13,6,2,4},{3,7,1,1},{0,10,4,1},{6,10,9,1},{2,11,2,5},{6,11,2,5},{13,11,2,1},{14,14,2,3},{2,16,6,1},{2,17,3,1},{6,17,2,1},{13,17,2,1},{2,18,2,1},{7,18,8,1}}}
T.glyphs[35768] = {w=18, advance=16, rects={{1,4,1,1},{7,4,1,2},{1,5,2,1},{2,6,2,1},{6,6,9,1},{3,7,1,1},{6,7,1,1},{10,7,1,4},{5,8,2,1},{0,9,4,1},{5,9,1,1},{2,10,2,5},{5,11,11,1},{10,12,1,7},{5,14,1,1},{2,15,4,1},{2,16,3,1},{2,17,2,1},{2,18,1,1}}}
T.glyphs[35774] = {w=18, advance=16, rects={{2,5,1,1},{7,5,6,1},{2,6,2,1},{7,6,1,2},{12,6,1,2},{3,7,1,1},{5,8,3,1},{12,8,2,1},{0,9,4,1},{5,9,2,1},{12,9,4,1},{2,10,2,5},{5,11,9,1},{6,12,2,1},{12,12,2,1},{7,13,2,1},{12,13,1,1},{8,14,1,1},{11,14,2,1},{2,15,4,2},{9,15,3,1},{8,16,4,1},{2,17,2,1},{5,17,4,1},{11,17,4,1},{4,18,3,1},{13,18,2,1}}}
T.glyphs[35777] = {w=18, advance=16, rects={{1,4,1,1},{1,5,2,1},{5,5,11,1},{2,6,2,1},{10,6,2,1},{3,7,1,1},{10,7,1,4},{0,9,3,1},{6,9,2,8},{2,10,1,4},{10,11,5,1},{10,12,2,1},{10,13,1,4},{2,14,3,1},{2,15,2,1},{2,16,1,1},{4,17,12,1}}}
T.glyphs[35786] = {w=18, advance=16, rects={{2,4,1,1},{9,4,2,1},{2,5,2,1},{8,5,3,1},{3,6,1,2},{7,6,2,1},{11,6,1,1},{6,7,2,1},{11,7,2,1},{5,8,2,1},{10,8,1,1},{13,8,2,1},{0,9,3,1},{4,9,2,1},{8,9,3,1},{14,9,2,1},{2,10,1,6},{7,10,2,1},{12,10,1,1},{6,11,1,1},{10,11,3,1},{9,12,2,1},{7,13,3,1},{13,13,2,1},{6,14,2,1},{12,14,2,1},{4,15,1,1},{11,15,2,1},{2,16,3,1},{9,16,3,1},{2,17,1,1},{6,17,4,1},{5,18,2,1}}}
T.glyphs[35789] = {w=18, advance=16, rects={{1,4,1,1},{1,5,2,1},{5,5,10,1},{2,6,2,1},{13,6,2,1},{3,7,1,1},{14,7,1,10},{5,8,8,1},{0,10,3,1},{2,11,1,5},{6,11,6,1},{6,12,1,3},{10,12,2,3},{4,15,1,1},{6,15,6,1},{2,16,3,1},{6,16,1,1},{2,17,2,1},{13,17,2,1},{2,18,1,1},{10,18,5,1}}}
T.glyphs[35793] = {w=18, advance=16, rects={{1,5,2,1},{5,5,10,1},{2,6,2,1},{7,6,1,1},{13,6,2,1},{3,7,1,1},{7,7,2,1},{12,7,2,1},{8,8,4,1},{0,9,3,1},{7,9,6,1},{2,10,1,6},{5,10,3,1},{12,10,4,1},{9,11,2,1},{6,12,9,1},{9,13,2,2},{5,15,11,1},{2,16,3,2},{9,16,2,3},{2,18,1,1}}}
T.glyphs[35797] = {w=18, advance=16, rects={{1,4,1,1},{10,4,4,1},{1,5,2,1},{10,5,2,2},{13,5,2,1},{2,6,2,1},{3,7,1,1},{5,7,11,1},{10,8,2,2},{0,9,3,1},{2,10,1,5},{11,10,1,1},{5,11,7,1},{7,12,1,4},{11,12,1,3},{2,15,3,2},{11,15,2,1},{14,15,2,2},{6,16,5,1},{12,16,1,1},{2,17,2,1},{5,17,4,1},{12,17,4,1},{2,18,1,1},{13,18,2,1}}}
T.glyphs[35805] = {w=18, advance=16, rects={{1,4,2,1},{10,4,5,1},{2,5,2,1},{5,5,8,1},{3,6,1,1},{9,6,2,2},{4,8,12,1},{0,9,4,1},{9,9,2,2},{2,10,2,6},{6,11,8,1},{6,12,2,1},{13,12,1,5},{6,13,1,3},{2,16,5,1},{2,17,3,1},{6,17,8,1},{2,18,2,1},{6,18,2,1},{13,18,1,1}}}
T.glyphs[35810] = {w=18, advance=16, rects={{1,4,2,1},{7,4,1,1},{2,5,2,1},{6,5,9,1},{3,6,1,1},{5,6,2,1},{14,6,1,9},{5,7,1,1},{0,8,3,1},{4,8,2,1},{2,9,1,7},{6,9,6,1},{6,10,1,1},{10,10,2,1},{6,11,6,1},{6,12,1,2},{10,12,2,2},{6,14,6,1},{4,15,1,1},{6,15,1,1},{13,15,2,2},{2,16,3,1},{2,17,1,1},{10,17,4,1}}}
T.glyphs[35813] = {w=18, advance=16, rects={{1,4,2,1},{9,4,2,1},{2,5,2,1},{10,5,1,1},{3,6,1,1},{5,6,11,1},{8,7,1,1},{7,8,2,1},{12,8,1,1},{0,9,3,1},{7,9,1,1},{11,9,2,1},{2,10,1,7},{6,10,2,1},{10,10,3,1},{5,11,7,1},{13,11,2,1},{5,12,2,1},{9,12,2,1},{12,12,2,2},{7,13,3,1},{6,14,2,1},{10,14,3,1},{5,15,2,1},{9,15,4,1},{4,16,1,1},{8,16,2,1},{12,16,2,1},{2,17,3,1},{6,17,3,1},{13,17,2,1},{2,18,1,1},{5,18,2,1},{14,18,1,1}}}
T.glyphs[35814] = {w=18, advance=16, rects={{1,5,1,1},{6,5,2,1},{12,5,2,1},{1,6,3,1},{7,6,2,1},{11,6,2,1},{2,7,2,1},{5,7,10,1},{9,8,2,2},{0,9,3,1},{2,10,1,5},{5,10,10,1},{9,11,2,2},{4,13,12,1},{9,14,2,4},{2,15,3,2},{2,17,1,1}}}
T.glyphs[35821] = {w=18, advance=16, rects={{1,3,1,1},{1,4,2,1},{5,4,10,1},{2,5,2,1},{8,5,1,2},{3,6,1,1},{5,7,9,1},{7,8,2,2},{12,8,2,2},{0,9,3,1},{2,10,1,6},{4,10,12,1},{6,13,8,1},{6,14,1,2},{13,14,1,2},{4,15,1,1},{2,16,3,1},{6,16,8,1},{2,17,1,1},{6,17,1,1},{13,17,1,1}}}
T.glyphs[35823] = {w=18, advance=16, rects={{1,5,2,1},{6,5,9,1},{2,6,2,1},{6,6,1,2},{13,6,2,2},{3,7,1,1},{6,8,9,1},{0,9,3,1},{6,9,1,1},{13,9,2,1},{2,10,1,6},{5,11,10,1},{9,12,2,2},{4,14,12,1},{4,15,1,1},{8,15,3,1},{2,16,3,1},{7,16,2,1},{11,16,2,1},{2,17,1,1},{5,17,3,1},{12,17,3,1},{4,18,3,1},{13,18,2,1}}}
T.glyphs[35828] = {w=18, advance=16, rects={{1,4,2,1},{6,4,2,1},{12,4,1,1},{2,5,2,1},{7,5,1,1},{11,5,2,1},{3,6,1,1},{7,6,2,1},{11,6,1,1},{5,7,9,1},{5,8,2,4},{13,8,1,4},{0,9,3,1},{2,10,1,6},{5,12,9,1},{5,13,2,1},{8,13,1,1},{10,13,2,5},{13,13,1,1},{7,14,2,2},{4,15,1,1},{14,15,2,3},{2,16,3,1},{6,16,2,1},{2,17,1,1},{5,17,2,1},{4,18,2,1},{11,18,4,1}}}
T.glyphs[35831] = {w=18, advance=16, rects={{1,4,2,1},{9,4,2,1},{2,5,2,1},{5,5,11,1},{3,6,1,1},{9,6,2,1},{5,7,10,1},{9,8,2,1},{0,9,16,1},{2,10,2,4},{6,11,9,1},{6,12,1,1},{13,12,2,1},{6,13,9,1},{2,14,13,1},{2,15,3,1},{6,15,1,3},{13,15,2,2},{2,16,2,1},{2,17,1,1},{10,17,4,1}}}
T.glyphs[35835] = {w=18, advance=16, rects={{1,4,2,2},{9,4,2,2},{2,6,2,1},{5,6,10,1},{3,7,1,1},{9,7,2,2},{4,9,11,1},{0,10,3,1},{6,10,2,1},{14,10,1,2},{2,11,1,5},{5,11,4,1},{10,11,2,3},{7,12,1,1},{4,14,12,1},{4,15,1,1},{9,15,2,1},{2,16,3,1},{8,16,5,1},{2,17,2,1},{6,17,3,1},{12,17,3,1},{2,18,1,1},{5,18,2,1},{14,18,1,1}}}
T.glyphs[35841] = {w=18, advance=16, rects={{1,4,1,1},{7,4,1,1},{10,4,1,1},{1,5,2,1},{6,5,2,2},{10,5,2,1},{2,6,2,1},{11,6,1,1},{3,7,1,1},{5,7,11,1},{5,8,2,1},{10,8,2,2},{4,9,3,1},{0,10,3,1},{4,10,1,1},{6,10,9,1},{2,11,1,5},{6,11,1,2},{10,11,2,2},{6,13,9,1},{6,14,1,3},{10,14,2,3},{4,15,1,1},{2,16,3,1},{2,17,2,1},{6,17,10,1},{2,18,1,1},{6,18,1,1}}}
T.glyphs[35843] = {w=18, advance=16, rects={{1,4,2,1},{2,5,1,1},{5,5,10,1},{2,6,2,1},{5,6,2,2},{14,6,1,4},{3,7,1,1},{9,7,2,1},{5,8,8,1},{0,9,3,1},{5,9,2,1},{9,9,2,1},{2,10,1,4},{5,10,10,1},{5,11,2,2},{14,11,1,6},{8,12,5,1},{4,13,2,1},{8,13,1,1},{11,13,2,1},{2,14,4,1},{8,14,5,1},{2,15,1,1},{4,15,2,1},{8,15,1,1},{4,16,1,1},{3,17,2,1},{11,17,4,1}}}
T.glyphs[35889] = {w=18, advance=16, rects={{1,4,1,1},{7,4,1,1},{12,4,1,1},{1,5,2,1},{7,5,2,1},{11,5,2,1},{2,6,2,1},{5,6,10,1},{8,7,1,3},{11,7,1,3},{5,8,2,1},{13,8,2,1},{0,9,3,1},{6,9,1,1},{13,9,1,1},{2,10,1,6},{4,10,12,1},{6,12,8,1},{6,13,1,2},{13,13,1,2},{4,15,1,1},{6,15,8,1},{2,16,3,1},{6,16,1,2},{13,16,1,2},{2,17,2,1},{6,18,8,1}}}
T.glyphs[35937] = {w=18, advance=16, rects={{5,4,1,1},{4,5,8,1},{3,6,1,1},{10,6,2,1},{1,7,14,1},{0,8,3,1},{7,8,2,2},{13,8,2,2},{2,9,1,1},{2,10,13,1},{5,11,3,1},{13,11,1,1},{3,12,3,1},{7,12,2,1},{11,12,2,1},{0,13,3,1},{5,13,7,1},{2,14,4,1},{7,14,3,1},{11,14,1,1},{1,15,2,1},{6,15,2,1},{9,15,1,2},{12,15,1,1},{4,16,2,1},{13,16,2,1},{2,17,3,1},{8,17,2,1},{14,17,2,1},{0,18,2,1},{5,18,4,1}}}
T.glyphs[36127] = {w=18, advance=16, rects={{5,3,1,1},{4,4,2,1},{3,5,9,1},{2,6,2,1},{9,6,2,1},{1,7,2,1},{9,7,1,1},{0,8,14,1},{2,9,2,6},{13,9,1,6},{7,10,2,4},{7,14,3,1},{7,15,4,1},{5,16,2,1},{10,16,3,1},{2,17,4,1},{12,17,3,1},{1,18,3,1},{14,18,1,1}}}
T.glyphs[36129] = {w=18, advance=16, rects={{2,4,12,1},{7,5,2,2},{0,7,16,1},{2,9,12,1},{2,10,2,5},{12,10,2,5},{7,11,2,3},{7,14,3,1},{5,15,7,1},{3,16,3,1},{11,16,4,1},{1,17,3,1},{13,17,2,1}}}
T.glyphs[36131] = {w=18, advance=16, rects={{7,4,2,1},{1,5,14,1},{7,6,2,1},{2,7,12,1},{7,8,2,2},{0,10,16,1},{2,12,12,1},{2,13,2,3},{12,13,2,3},{7,14,2,2},{7,16,4,1},{4,17,3,1},{10,17,5,1},{0,18,5,1},{13,18,2,1}}}
T.glyphs[36133] = {w=18, advance=16, rects={{9,4,1,3},{1,5,6,1},{1,6,1,8},{6,6,1,3},{3,7,2,6},{8,7,8,1},{8,8,2,1},{13,8,1,2},{6,9,4,1},{6,10,2,1},{9,10,1,3},{12,10,2,2},{6,11,1,3},{12,12,1,2},{3,13,1,1},{9,13,2,1},{3,14,2,1},{10,14,3,1},{3,15,1,1},{5,15,1,1},{10,15,2,1},{2,16,1,1},{5,16,2,1},{9,16,4,1},{1,17,2,1},{6,17,4,1},{12,17,3,1},{0,18,2,1},{7,18,1,1},{14,18,2,1}}}
T.glyphs[36134] = {w=18, advance=16, rects={{1,5,6,1},{8,5,2,3},{13,5,2,1},{1,6,1,8},{5,6,2,1},{12,6,2,1},{3,7,4,3},{11,7,2,1},{8,8,4,1},{8,9,2,1},{3,10,13,1},{3,11,1,3},{5,11,2,3},{8,11,2,5},{11,11,1,2},{11,13,2,1},{3,14,2,1},{12,14,1,1},{2,15,4,1},{12,15,2,1},{2,16,1,1},{5,16,2,1},{8,16,4,1},{13,16,2,1},{1,17,2,1},{6,17,1,1},{8,17,3,1},{14,17,2,1},{1,18,1,1},{8,18,2,1}}}
T.glyphs[36148] = {w=18, advance=16, rects={{10,3,2,4},{1,4,6,1},{1,5,1,9},{6,5,1,9},{3,7,2,8},{10,7,6,1},{10,8,2,4},{8,12,7,1},{8,13,1,4},{14,13,1,4},{3,15,3,1},{2,16,2,1},{5,16,2,1},{1,17,2,1},{6,17,1,1},{8,17,7,1},{1,18,1,1},{8,18,1,1},{14,18,1,1}}}
T.glyphs[36153] = {w=18, advance=16, rects={{6,4,1,1},{10,4,1,1},{1,5,14,1},{6,6,1,1},{10,6,1,1},{13,6,2,1},{2,7,13,1},{2,8,1,1},{5,8,2,1},{10,8,1,1},{2,9,13,1},{4,10,2,1},{12,10,3,1},{2,11,11,1},{0,12,2,1},{3,12,1,4},{12,12,1,4},{7,13,2,2},{7,15,3,1},{6,16,2,1},{9,16,3,1},{3,17,4,1},{11,17,3,1},{1,18,4,1},{13,18,2,1}}}
T.glyphs[36164] = {w=18, advance=16, rects={{1,4,2,1},{7,4,1,1},{2,5,2,1},{6,5,9,1},{5,6,2,1},{9,6,2,2},{13,6,2,1},{4,7,2,1},{13,7,1,1},{2,8,2,1},{8,8,4,1},{1,9,2,1},{6,9,3,1},{11,9,3,1},{1,10,1,1},{5,10,2,1},{13,10,2,1},{2,11,12,1},{2,12,2,4},{12,12,2,4},{7,13,2,3},{6,16,5,1},{3,17,4,1},{10,17,4,1},{1,18,4,1},{13,18,2,1}}}
T.glyphs[36171] = {w=18, advance=16, rects={{12,4,1,1},{1,5,5,1},{7,5,4,1},{12,5,3,1},{1,6,1,8},{5,6,1,2},{12,6,1,2},{14,6,1,1},{3,7,1,7},{5,8,11,1},{5,9,1,6},{9,9,1,3},{12,9,1,3},{7,11,1,5},{9,12,4,1},{9,13,1,3},{12,13,1,2},{1,14,3,1},{2,15,3,1},{12,15,2,1},{15,15,1,2},{2,16,1,1},{4,16,10,1},{1,17,1,1},{6,17,4,1},{13,17,3,1},{0,18,2,1},{13,18,2,1}}}
T.glyphs[36182] = {w=18, advance=16, rects={{3,4,2,1},{10,4,1,1},{0,5,8,1},{9,5,5,1},{3,6,2,2},{8,6,2,1},{12,6,2,1},{7,7,2,1},{12,7,1,1},{1,8,6,1},{8,8,7,1},{1,9,1,3},{3,9,2,3},{6,9,1,3},{8,9,2,6},{14,9,1,6},{11,10,1,5},{1,12,6,1},{1,13,1,1},{3,13,2,1},{6,13,1,1},{2,14,3,1},{1,15,5,1},{10,15,2,1},{0,16,2,1},{3,16,4,1},{10,16,1,1},{12,16,2,1},{0,17,1,1},{3,17,2,2},{6,17,4,1},{13,17,2,1},{7,18,2,1},{14,18,2,1}}}
T.glyphs[36194] = {w=18, advance=16, rects={{7,3,1,1},{7,4,2,1},{0,5,16,1},{2,6,2,1},{2,7,12,1},{2,9,12,1},{2,10,2,1},{12,10,2,1},{1,11,13,1},{1,12,1,1},{4,12,1,1},{6,12,1,1},{9,12,3,2},{13,12,1,2},{1,13,4,1},{6,13,2,3},{1,14,1,1},{4,14,1,1},{9,14,5,2},{1,15,4,1},{1,16,1,2},{4,16,1,2},{7,16,2,1},{10,16,1,1},{13,16,1,2},{15,16,1,2},{6,17,1,1},{8,17,3,1},{0,18,1,1},{2,18,4,1},{9,18,2,1},{13,18,2,1}}}
T.glyphs[36208] = {w=18, advance=16, rects={{7,4,2,2},{2,6,12,1},{7,7,2,3},{1,10,14,1},{7,11,2,2},{3,12,1,2},{7,13,7,1},{2,14,2,1},{7,14,2,3},{2,15,3,1},{1,16,2,1},{4,16,2,1},{1,17,1,1},{5,17,11,1}}}
T.glyphs[36214] = {w=18, advance=16, rects={{4,4,1,2},{8,5,7,1},{1,6,6,1},{11,6,1,4},{4,7,1,2},{0,9,8,1},{4,10,2,1},{8,10,8,1},{1,11,2,4},{4,11,1,2},{11,11,1,5},{4,13,4,1},{4,14,2,1},{1,15,4,1},{1,16,1,1},{3,16,3,1},{0,17,2,1},{4,17,12,1},{0,18,1,1}}}
T.glyphs[36215] = {w=18, advance=16, rects={{3,4,2,2},{8,5,7,1},{1,6,7,1},{13,6,2,3},{3,7,2,2},{0,9,15,1},{4,10,1,3},{8,10,2,3},{1,11,2,4},{14,11,1,1},{14,12,2,1},{4,13,6,1},{14,13,1,1},{4,14,1,1},{9,14,6,1},{1,15,4,1},{1,16,1,1},{3,16,3,1},{0,17,2,1},{4,17,12,1}}}
T.glyphs[36229] = {w=18, advance=16, rects={{3,4,2,2},{7,5,8,1},{1,6,6,1},{9,6,2,2},{14,6,1,1},{3,7,2,3},{13,7,2,2},{9,8,1,1},{8,9,2,1},{11,9,3,1},{0,10,9,1},{4,11,1,2},{8,11,7,1},{1,12,2,4},{8,12,2,1},{13,12,2,2},{4,13,3,1},{8,13,1,1},{4,14,1,2},{8,14,7,1},{8,15,2,1},{13,15,2,1},{1,16,4,1},{0,17,2,1},{4,17,12,1}}}
T.glyphs[36234] = {w=18, advance=16, rects={{3,4,2,2},{10,4,2,3},{13,4,1,2},{1,6,6,1},{13,6,2,1},{3,7,2,2},{8,7,8,1},{8,8,1,1},{10,8,2,1},{0,9,9,1},{11,9,1,2},{13,9,2,1},{4,10,1,3},{8,10,1,2},{13,10,1,1},{1,11,2,4},{10,11,4,1},{8,12,2,1},{11,12,2,2},{14,12,1,1},{4,13,5,1},{14,13,2,1},{4,14,1,1},{7,14,1,1},{10,14,3,1},{14,14,1,1},{1,15,4,1},{9,15,2,1},{12,15,3,1},{1,16,1,1},{3,16,2,1},{9,16,1,1},{0,17,2,1},{4,17,12,1}}}
T.glyphs[36255] = {w=18, advance=16, rects={{3,4,1,2},{10,4,1,4},{7,5,1,1},{14,5,1,1},{1,6,5,1},{7,6,2,1},{13,6,2,1},{3,7,1,2},{8,7,1,1},{12,7,2,1},{7,8,8,1},{0,9,6,1},{7,9,1,7},{14,9,1,6},{3,10,2,1},{9,10,4,1},{1,11,4,1},{9,11,1,2},{12,11,1,2},{1,12,1,1},{3,12,3,1},{1,13,4,3},{9,13,4,1},{9,14,1,1},{11,15,4,1},{0,16,2,1},{3,16,2,1},{4,17,12,1}}}
T.glyphs[36291] = {w=18, advance=16, rects={{13,4,2,1},{1,5,14,1},{1,6,2,3},{5,6,2,3},{10,6,2,4},{1,9,6,1},{1,10,2,1},{4,10,1,2},{6,10,10,1},{10,11,2,2},{1,12,1,4},{4,12,3,1},{4,13,1,3},{9,13,3,1},{9,14,1,1},{11,14,2,1},{8,15,2,1},{12,15,1,1},{1,16,6,1},{8,16,1,1},{12,16,2,1},{0,17,4,1},{7,17,1,1},{13,17,2,1},{6,18,1,1},{14,18,1,1}}}
T.glyphs[36305] = {w=18, advance=16, rects={{8,4,2,1},{1,5,5,1},{8,5,1,1},{1,6,2,3},{5,6,1,2},{8,6,7,1},{7,7,1,1},{13,7,2,5},{5,8,3,1},{1,9,11,1},{1,10,1,1},{3,10,2,2},{6,10,2,1},{10,10,2,2},{7,11,1,1},{1,12,1,4},{3,12,3,1},{7,12,5,1},{13,12,1,2},{3,13,2,3},{7,13,1,3},{10,14,6,1},{14,15,2,1},{1,16,8,1},{14,16,1,1},{0,17,5,1},{7,17,8,1}}}
T.glyphs[36317] = {w=18, advance=16, rects={{1,5,5,1},{7,5,9,1},{1,6,1,3},{5,6,1,3},{7,6,2,3},{1,9,5,1},{7,9,8,1},{1,10,1,1},{3,10,2,2},{7,10,2,2},{13,10,2,3},{1,12,1,4},{3,12,6,1},{3,13,2,3},{7,13,8,1},{7,14,2,2},{13,14,2,1},{1,16,8,1},{0,17,5,1},{7,17,9,1}}}
T.glyphs[36319] = {w=18, advance=16, rects={{1,5,5,1},{7,5,8,1},{1,6,1,3},{5,6,1,3},{7,6,2,2},{13,6,2,2},{7,8,8,1},{1,9,5,1},{7,9,2,2},{13,9,2,2},{1,10,1,1},{3,10,2,2},{7,11,8,1},{1,12,1,4},{3,12,6,1},{10,12,1,2},{13,12,2,1},{3,13,2,3},{7,13,2,3},{14,13,1,1},{10,14,4,1},{11,15,2,1},{1,16,8,1},{10,16,1,1},{12,16,2,1},{0,17,5,1},{7,17,4,1},{13,17,2,1},{7,18,1,1},{14,18,1,1}}}
T.glyphs[36328] = {w=18, advance=16, rects={{10,4,1,1},{1,5,5,1},{9,5,2,1},{1,6,1,3},{5,6,11,1},{5,7,1,2},{8,7,2,1},{12,7,1,1},{7,8,2,1},{13,8,2,1},{1,9,15,1},{3,10,1,2},{6,10,1,1},{6,11,9,1},{1,12,1,4},{3,12,3,1},{8,12,1,1},{3,13,1,2},{7,13,2,1},{7,14,7,1},{3,15,3,1},{13,15,1,1},{1,16,4,1},{12,16,2,1},{0,17,2,1},{8,17,6,1}}}
T.glyphs[36335] = {w=18, advance=16, rects={{9,4,1,1},{1,5,5,1},{8,5,2,1},{1,6,1,3},{5,6,1,2},{8,6,7,1},{7,7,2,1},{13,7,2,1},{5,8,5,1},{12,8,2,1},{1,9,7,1},{9,9,4,1},{1,10,1,1},{3,10,2,2},{10,10,3,1},{8,11,2,1},{12,11,3,1},{1,12,1,4},{3,12,5,1},{14,12,2,1},{3,13,2,3},{7,13,8,1},{7,14,2,2},{13,14,2,3},{1,16,8,1},{0,17,4,1},{7,17,8,1},{7,18,2,1},{13,18,2,1}}}
T.glyphs[36339] = {w=18, advance=16, rects={{8,4,2,4},{11,4,1,4},{1,5,5,1},{1,6,1,3},{4,6,2,1},{14,6,1,1},{4,7,3,1},{13,7,2,1},{4,8,6,1},{11,8,3,1},{1,9,5,1},{7,9,3,1},{11,9,1,2},{1,10,1,1},{3,10,1,2},{8,10,2,2},{11,11,2,1},{1,12,1,4},{3,12,3,1},{7,12,3,1},{11,12,4,1},{3,13,1,3},{6,13,3,1},{11,13,1,5},{14,13,1,1},{6,14,1,1},{8,14,1,2},{15,15,1,1},{1,16,5,1},{7,16,2,1},{14,16,2,2},{0,17,3,1},{6,17,2,1},{5,18,2,1},{11,18,4,1}}}
T.glyphs[36393] = {w=18, advance=16, rects={{11,4,4,1},{1,5,12,1},{1,6,1,3},{5,6,1,3},{7,7,1,2},{10,7,1,3},{13,7,2,1},{13,8,1,1},{1,9,5,1},{7,9,2,1},{12,9,1,1},{3,10,1,2},{1,11,1,5},{10,11,1,1},{3,12,13,1},{3,13,1,2},{9,13,3,1},{8,14,5,1},{3,15,3,1},{7,15,2,1},{10,15,1,4},{12,15,2,1},{1,16,4,1},{6,16,2,1},{13,16,2,1},{0,17,2,1},{6,17,1,1},{14,17,1,1}}}
T.glyphs[36523] = {w=18, advance=16, rects={{6,3,2,2},{2,5,11,1},{2,6,2,2},{12,6,1,2},{2,8,11,1},{2,9,2,1},{12,9,1,1},{2,10,11,1},{15,10,1,1},{2,11,2,2},{12,11,1,1},{14,11,1,1},{12,12,2,1},{0,13,14,1},{9,14,4,1},{7,15,3,1},{12,15,1,2},{5,16,3,1},{2,17,4,1},{11,17,2,1},{1,18,2,1},{8,18,5,1}}}
T.glyphs[36527] = {w=18, advance=16, rects={{3,4,1,2},{7,4,9,1},{7,5,2,1},{1,6,5,1},{7,6,3,1},{14,6,1,1},{1,7,1,1},{5,7,1,1},{7,7,4,1},{13,7,2,1},{1,8,5,1},{7,8,2,6},{10,8,2,1},{13,8,1,1},{1,9,1,1},{5,9,1,1},{11,9,3,1},{1,10,5,1},{11,10,2,2},{1,11,1,1},{5,11,1,1},{0,12,6,1},{10,12,4,1},{4,13,2,1},{10,13,1,1},{13,13,1,1},{3,14,3,1},{7,14,4,1},{13,14,2,1},{2,15,2,1},{5,15,1,2},{7,15,3,1},{14,15,1,1},{2,16,1,1},{7,16,2,1},{1,17,1,1},{3,17,3,1},{7,17,9,1},{0,18,1,1}}}
T.glyphs[36530] = {w=18, advance=16, rects={{3,4,1,1},{8,4,6,1},{2,5,2,1},{8,5,2,1},{12,5,2,1},{1,6,5,1},{8,6,1,3},{13,6,1,3},{1,7,1,1},{5,7,1,1},{1,8,5,1},{1,9,1,1},{5,9,1,1},{7,9,2,1},{13,9,3,1},{1,10,5,1},{7,10,1,1},{10,10,2,2},{1,11,1,1},{5,11,1,1},{0,12,6,1},{7,12,9,1},{3,13,3,1},{9,13,4,1},{2,14,2,1},{5,14,1,2},{8,14,6,1},{1,15,2,1},{7,15,2,1},{10,15,2,3},{13,15,2,1},{0,16,2,1},{5,16,2,1},{14,16,2,1},{3,17,3,1}}}
T.glyphs[36710] = {w=18, advance=16, rects={{5,4,2,2},{1,6,14,1},{4,7,2,1},{3,8,2,2},{8,8,1,3},{2,10,2,1},{2,11,12,1},{8,12,1,3},{0,15,16,1},{8,16,1,3}}}
T.glyphs[36716] = {w=18, advance=16, rects={{3,3,1,3},{10,3,2,1},{10,4,1,2},{2,6,13,1},{2,7,1,2},{9,7,2,1},{4,8,1,4},{9,8,1,1},{1,9,2,1},{7,9,9,1},{1,10,1,2},{8,10,2,2},{0,12,7,1},{8,12,7,1},{4,13,1,1},{13,13,2,1},{2,14,5,1},{8,14,1,1},{12,14,2,1},{0,15,5,1},{8,15,5,1},{4,16,1,3},{10,16,2,1},{11,17,2,1},{12,18,2,1}}}
T.glyphs[36718] = {w=18, advance=16, rects={{3,4,1,1},{10,4,2,1},{2,5,2,1},{9,5,3,1},{0,6,7,1},{8,6,2,1},{11,6,2,1},{2,7,1,1},{8,7,1,1},{12,7,2,1},{1,8,4,2},{7,8,1,1},{13,8,2,1},{6,9,1,1},{14,9,2,1},{1,10,1,2},{3,10,2,2},{8,10,1,3},{12,11,2,1},{0,12,7,1},{11,12,2,1},{3,13,2,2},{8,13,4,1},{8,14,2,1},{2,15,5,1},{8,15,1,3},{14,15,1,2},{0,16,5,1},{3,17,2,3},{13,17,2,1},{8,18,6,1}}}
T.glyphs[36724] = {w=18, advance=16, rects={{3,4,1,1},{10,4,2,3},{2,5,2,1},{0,6,6,1},{2,7,1,1},{7,7,8,1},{1,8,4,1},{7,8,1,4},{10,8,2,4},{14,8,1,4},{1,9,1,2},{3,9,2,2},{0,11,6,1},{3,12,2,2},{7,12,8,1},{7,13,1,4},{10,13,2,4},{14,13,1,4},{2,14,4,1},{0,15,5,1},{3,16,2,3},{7,17,8,1},{7,18,1,1},{14,18,1,1}}}
T.glyphs[36731] = {w=18, advance=16, rects={{2,4,2,2},{7,5,7,1},{0,6,6,1},{12,6,2,1},{2,7,1,1},{11,7,2,1},{1,8,4,1},{10,8,2,1},{1,9,1,2},{3,9,2,2},{9,9,5,1},{7,10,3,1},{13,10,2,1},{0,11,8,1},{14,11,2,1},{3,12,2,2},{7,13,8,1},{3,14,3,1},{10,14,2,1},{0,15,5,1},{10,15,1,1},{3,16,2,3},{10,16,2,1},{6,17,10,1}}}
T.glyphs[36733] = {w=18, advance=16, rects={{4,4,1,1},{9,4,2,1},{12,4,2,1},{1,5,10,1},{13,5,2,1},{4,6,1,1},{9,6,2,1},{0,7,16,1},{3,8,2,2},{9,8,2,2},{13,9,1,2},{1,10,8,1},{10,10,1,2},{2,11,2,1},{5,11,1,2},{12,11,2,1},{1,12,2,1},{10,12,3,2},{1,13,8,1},{5,14,1,1},{10,14,2,2},{4,15,5,1},{14,15,2,2},{1,16,5,1},{9,16,4,1},{5,17,1,2},{8,17,2,1},{12,17,3,1},{7,18,2,1},{13,18,2,1}}}
T.glyphs[36739] = {w=18, advance=16, rects={{3,4,1,1},{10,4,1,1},{2,5,2,1},{10,5,2,1},{0,6,16,1},{2,7,1,1},{1,8,4,1},{8,8,2,1},{12,8,2,1},{1,9,1,2},{3,9,2,2},{7,9,2,1},{13,9,2,1},{7,10,1,1},{14,10,1,1},{0,11,6,1},{8,11,1,1},{12,11,2,2},{3,12,2,2},{8,12,2,1},{9,13,1,1},{11,13,2,1},{2,14,5,1},{9,14,4,1},{0,15,5,1},{10,15,2,1},{3,16,2,3},{9,16,4,1},{7,17,3,1},{12,17,3,1},{6,18,2,1},{14,18,1,1}}}
T.glyphs[36753] = {w=18, advance=16, rects={{3,4,1,2},{7,5,8,1},{2,6,2,1},{7,6,1,1},{13,6,2,1},{0,7,15,1},{2,8,1,1},{7,8,1,1},{13,8,2,1},{1,9,4,1},{1,10,1,2},{3,10,2,2},{6,10,10,1},{7,11,1,1},{13,11,2,1},{0,12,6,1},{7,12,8,1},{3,13,2,1},{7,13,1,1},{13,13,2,1},{2,14,13,1},{0,15,5,1},{7,15,1,1},{13,15,2,1},{3,16,2,3},{6,16,10,1},{13,17,2,2}}}
T.glyphs[36755] = {w=18, advance=16, rects={{2,4,2,1},{9,4,3,1},{2,5,1,1},{9,5,1,1},{11,5,1,1},{0,6,6,1},{8,6,1,1},{12,6,1,1},{1,7,2,1},{7,7,2,1},{12,7,2,1},{1,8,1,2},{6,8,9,1},{3,9,1,2},{5,9,1,1},{14,9,2,1},{0,10,2,1},{6,10,4,1},{14,10,1,8},{0,11,7,1},{9,11,1,2},{11,11,2,5},{3,12,1,2},{6,12,1,1},{6,13,4,1},{2,14,5,1},{9,14,1,1},{0,15,4,1},{6,15,4,1},{3,16,1,3},{6,16,1,2},{9,16,1,2},{6,18,4,1},{11,18,4,1}}}
T.glyphs[36793] = {w=18, advance=16, rects={{1,4,1,1},{8,4,2,3},{1,5,2,1},{2,6,2,1},{3,7,1,1},{5,7,10,1},{8,8,2,2},{13,8,2,6},{0,10,4,1},{8,10,1,2},{2,11,2,5},{7,12,2,1},{7,13,1,1},{6,14,2,1},{13,14,1,1},{5,15,2,1},{9,15,5,1},{2,16,4,1},{0,17,2,1},{3,17,3,1},{5,18,11,1}}}
T.glyphs[36798] = {w=18, advance=16, rects={{1,4,1,1},{9,4,1,4},{1,5,2,1},{2,6,2,1},{3,7,1,1},{5,8,10,1},{9,9,1,2},{0,10,4,1},{2,11,2,6},{8,11,2,1},{8,12,3,1},{7,13,2,1},{11,13,2,1},{6,14,2,1},{12,14,2,1},{5,15,2,1},{13,15,1,1},{5,16,1,1},{13,16,2,1},{1,17,4,1},{0,18,2,1},{4,18,12,1}}}
T.glyphs[36807] = {w=18, advance=16, rects={{1,4,1,1},{11,4,2,3},{1,5,2,1},{2,6,2,1},{3,7,1,1},{5,7,11,1},{11,8,2,7},{0,9,4,1},{6,9,1,1},{2,10,2,6},{6,10,2,2},{7,12,2,1},{8,13,1,1},{8,15,5,1},{1,16,3,1},{0,17,2,1},{3,17,3,1},{4,18,12,1}}}
T.glyphs[36816] = {w=18, advance=16, rects={{1,4,1,1},{1,5,2,1},{6,5,9,1},{2,6,2,1},{3,7,1,1},{5,9,11,1},{0,10,4,1},{8,10,2,1},{2,11,2,6},{7,11,2,2},{11,11,1,1},{11,12,2,1},{6,13,2,2},{12,13,1,1},{11,14,3,1},{5,15,10,1},{5,16,3,1},{13,16,2,1},{0,17,2,1},{3,17,3,1},{4,18,12,1}}}
T.glyphs[36817] = {w=18, advance=16, rects={{1,4,2,1},{10,4,5,1},{2,5,2,1},{6,5,7,1},{3,6,1,1},{6,6,2,3},{0,9,4,1},{6,9,10,1},{2,10,2,6},{6,10,2,3},{11,10,2,7},{6,13,1,1},{5,14,2,2},{1,16,3,1},{5,16,1,1},{0,17,2,1},{3,17,3,1},{4,18,12,1}}}
T.glyphs[36820] = {w=18, advance=16, rects={{1,4,2,1},{11,4,4,1},{2,5,1,1},{6,5,8,1},{2,6,2,1},{6,6,1,2},{3,7,1,1},{6,8,9,1},{0,9,4,1},{6,9,1,3},{13,9,2,1},{2,10,2,5},{8,10,1,1},{13,10,1,1},{8,11,2,1},{12,11,2,1},{5,12,2,2},{9,12,4,1},{10,13,3,1},{5,14,1,1},{9,14,5,1},{2,15,4,1},{7,15,3,1},{13,15,2,1},{1,16,4,1},{6,16,2,1},{14,16,1,1},{0,17,2,1},{3,17,2,1},{0,18,1,1},{4,18,12,1}}}
T.glyphs[36824] = {w=18, advance=16, rects={{1,4,2,1},{2,5,1,1},{5,5,11,1},{2,6,2,1},{9,6,2,3},{3,7,1,1},{0,9,4,1},{8,9,4,1},{2,10,2,4},{7,10,6,1},{7,11,1,1},{9,11,2,6},{12,11,2,1},{6,12,1,1},{13,12,2,1},{5,13,1,1},{14,13,1,1},{2,14,3,1},{2,15,2,1},{1,16,3,1},{0,17,2,1},{3,17,2,1},{0,18,1,1},{4,18,12,1}}}
T.glyphs[36825] = {w=18, advance=16, rects={{1,3,2,2},{9,3,1,1},{9,4,2,2},{2,5,2,2},{5,6,11,1},{3,7,1,1},{12,8,2,1},{0,9,4,1},{6,9,1,1},{12,9,1,1},{2,10,2,6},{6,10,2,1},{11,10,2,1},{7,11,3,1},{11,11,1,1},{9,12,3,2},{7,14,3,1},{11,14,2,1},{5,15,3,1},{12,15,2,1},{1,16,3,1},{5,16,1,1},{13,16,1,1},{0,17,2,1},{3,17,2,1},{0,18,1,1},{4,18,12,1}}}
T.glyphs[36827] = {w=18, advance=16, rects={{1,4,1,1},{7,4,1,3},{11,4,2,3},{1,5,2,1},{2,6,2,1},{3,7,1,1},{5,7,10,1},{7,8,2,1},{11,8,2,3},{7,9,1,2},{0,10,4,1},{2,11,14,1},{2,12,2,4},{7,12,1,1},{11,12,2,5},{6,13,2,2},{5,15,2,1},{1,16,3,1},{5,16,1,1},{0,17,2,1},{3,17,2,1},{0,18,1,1},{4,18,12,1}}}
T.glyphs[36828] = {w=18, advance=16, rects={{1,4,2,1},{2,5,1,1},{5,5,9,1},{2,6,2,1},{3,7,1,1},{0,9,15,1},{2,10,2,6},{7,10,2,1},{10,10,2,1},{7,11,1,3},{11,11,1,5},{14,13,1,3},{6,14,2,1},{5,15,2,1},{1,16,3,1},{5,16,1,1},{11,16,4,1},{0,17,5,1},{0,18,1,1},{4,18,12,1}}}
T.glyphs[36830] = {w=18, advance=16, rects={{1,4,2,1},{8,4,1,2},{2,5,1,1},{2,6,2,1},{5,6,10,1},{3,7,1,1},{7,7,1,1},{6,8,2,1},{10,8,1,2},{0,9,4,1},{5,9,2,1},{2,10,2,3},{5,10,10,1},{10,11,1,2},{2,13,14,1},{2,14,2,2},{10,14,1,3},{0,16,2,1},{3,16,2,1},{4,17,12,1}}}
T.glyphs[36831] = {w=18, advance=16, rects={{1,4,1,1},{1,5,2,1},{6,5,8,1},{2,6,2,1},{6,6,2,4},{13,6,1,4},{3,7,1,1},{0,10,4,1},{6,10,8,1},{2,11,2,6},{6,11,2,2},{13,11,1,1},{9,12,2,1},{6,13,1,1},{10,13,2,1},{5,14,2,2},{11,14,2,1},{12,15,3,1},{5,16,1,1},{14,16,1,1},{0,17,2,1},{3,17,3,1},{5,18,11,1}}}
T.glyphs[36848] = {w=18, advance=16, rects={{1,4,2,1},{9,4,2,3},{12,4,2,1},{1,5,3,1},{2,6,2,1},{5,7,10,1},{8,8,3,2},{0,9,4,1},{2,10,2,4},{7,10,5,1},{7,11,1,1},{9,11,4,1},{6,12,2,1},{9,12,2,5},{12,12,2,1},{5,13,2,1},{13,13,2,1},{2,14,4,2},{14,14,1,1},{2,16,2,1},{1,17,4,1},{0,18,2,1},{4,18,12,1}}}
T.glyphs[36861] = {w=18, advance=16, rects={{1,4,1,1},{8,4,2,2},{1,5,2,1},{2,6,2,1},{5,6,9,1},{3,7,1,1},{5,7,2,2},{13,7,1,2},{5,9,9,1},{0,10,4,1},{5,10,2,2},{13,10,1,1},{2,11,2,6},{5,12,9,1},{5,13,2,2},{13,13,1,2},{5,15,9,1},{5,16,2,1},{13,16,1,1},{0,17,2,1},{3,17,3,1},{4,18,12,1}}}
T.glyphs[36864] = {w=18, advance=16, rects={{1,4,2,1},{6,4,8,1},{2,5,1,1},{6,5,1,2},{13,5,1,2},{2,6,2,1},{3,7,1,1},{6,7,8,1},{6,8,1,2},{13,8,1,2},{0,9,4,1},{2,10,2,6},{6,10,8,1},{6,11,1,4},{8,12,2,1},{13,12,2,1},{9,13,5,1},{9,14,4,1},{6,15,4,1},{12,15,2,1},{1,16,3,1},{6,16,2,1},{14,16,1,1},{0,17,2,1},{3,17,2,1},{0,18,1,1},{4,18,12,1}}}
T.glyphs[36865] = {w=18, advance=16, rects={{1,4,1,1},{6,4,2,1},{12,4,2,1},{1,5,2,1},{7,5,2,2},{12,5,1,1},{2,6,2,1},{11,6,1,1},{3,7,1,1},{5,7,10,1},{9,8,2,3},{0,9,4,1},{2,10,2,1},{2,11,14,1},{2,12,2,5},{9,12,1,1},{8,13,3,1},{8,14,5,1},{6,15,3,1},{12,15,2,1},{5,16,2,1},{13,16,2,1},{1,17,1,1},{3,17,2,1},{0,18,1,1},{4,18,12,1}}}
T.glyphs[36866] = {w=18, advance=16, rects={{1,4,2,1},{10,4,5,1},{2,5,1,1},{5,5,8,1},{2,6,2,1},{9,6,2,2},{3,7,1,1},{5,8,11,1},{0,9,4,1},{9,9,2,2},{2,10,2,6},{6,11,8,1},{6,12,1,3},{13,12,1,3},{6,15,8,1},{1,16,3,1},{6,16,1,1},{13,16,1,1},{0,17,2,1},{3,17,2,1},{0,18,1,1},{4,18,12,1}}}
T.glyphs[36867] = {w=18, advance=16, rects={{1,4,1,1},{7,4,2,3},{10,4,2,4},{1,5,2,1},{2,6,2,1},{5,6,1,1},{13,6,2,1},{5,7,4,1},{13,7,1,1},{6,8,3,1},{10,8,4,1},{0,9,3,1},{7,9,2,1},{10,9,2,2},{2,10,1,6},{6,10,3,1},{4,11,5,1},{10,11,4,1},{4,12,2,1},{7,12,2,1},{10,12,2,3},{13,12,2,1},{7,13,1,1},{6,14,2,2},{14,14,1,2},{11,15,1,1},{1,16,3,1},{5,16,2,1},{11,16,4,1},{0,17,6,1},{4,18,12,1}}}
T.glyphs[36870] = {w=18, advance=16, rects={{1,3,1,1},{6,3,2,1},{12,3,2,1},{1,4,2,1},{7,4,2,2},{12,4,1,1},{2,5,2,1},{11,5,2,1},{3,6,1,1},{5,6,10,1},{9,7,2,5},{6,8,1,4},{13,8,1,4},{0,9,4,1},{2,10,2,7},{6,12,8,1},{9,13,1,1},{13,13,1,1},{8,14,2,1},{7,15,2,1},{6,16,2,1},{1,17,1,1},{3,17,2,1},{0,18,1,1},{4,18,12,1}}}
T.glyphs[36873] = {w=18, advance=16, rects={{1,5,2,1},{6,5,2,2},{9,5,2,2},{2,6,1,1},{2,7,2,1},{5,7,10,1},{3,8,1,1},{5,8,2,1},{9,8,2,2},{0,10,16,1},{2,11,2,5},{7,11,2,2},{11,11,1,4},{14,12,1,1},{7,13,1,1},{14,13,2,1},{5,14,3,1},{14,14,1,1},{5,15,2,1},{11,15,4,1},{0,16,2,1},{3,16,2,1},{0,17,1,1},{4,17,12,1}}}
T.glyphs[36879] = {w=18, advance=16, rects={{1,4,2,1},{10,4,4,1},{2,5,1,1},{5,5,7,1},{2,6,2,1},{9,6,1,1},{3,7,1,1},{5,7,10,1},{8,8,4,1},{6,9,2,1},{9,9,1,2},{12,9,2,1},{0,10,6,1},{13,10,3,1},{2,11,2,6},{5,11,8,1},{7,12,2,1},{11,12,2,1},{7,13,1,1},{11,13,4,1},{6,14,2,1},{13,14,2,1},{6,15,1,1},{13,15,1,1},{5,16,1,1},{10,16,4,1},{1,17,1,1},{3,17,3,1},{0,18,1,1},{4,18,12,1}}}
T.glyphs[36880] = {w=18, advance=16, rects={{1,4,2,1},{2,5,1,1},{5,5,10,1},{2,6,2,1},{8,6,2,1},{3,7,1,1},{7,7,3,1},{13,7,2,1},{5,8,3,1},{9,8,1,1},{12,8,2,1},{4,9,2,1},{8,9,5,1},{0,10,3,1},{7,10,2,1},{10,10,2,1},{2,11,1,5},{5,11,3,1},{9,11,4,1},{4,12,2,1},{8,12,6,1},{7,13,2,1},{11,13,1,1},{13,13,2,1},{5,14,3,1},{10,14,2,2},{14,14,1,1},{4,15,2,1},{1,16,3,1},{7,16,4,1},{0,17,2,1},{3,17,2,1},{0,18,1,1},{4,18,12,1}}}
T.glyphs[36882] = {w=18, advance=16, rects={{1,3,1,1},{6,3,2,1},{12,3,1,1},{1,4,2,1},{7,4,1,2},{11,4,2,1},{2,5,2,2},{11,5,1,1},{5,6,10,1},{9,7,2,2},{13,7,2,2},{0,9,4,1},{5,9,10,1},{2,10,2,5},{5,10,2,1},{9,10,2,2},{13,10,2,1},{5,11,1,1},{5,12,10,1},{7,13,4,1},{14,13,1,1},{5,14,3,1},{9,14,2,1},{13,14,2,1},{2,15,4,1},{9,15,6,1},{1,16,3,1},{9,16,2,1},{0,17,2,1},{3,17,3,1},{4,18,12,1}}}
T.glyphs[36887] = {w=18, advance=16, rects={{1,4,1,1},{1,5,2,1},{5,5,10,1},{2,6,2,1},{3,7,1,1},{6,7,8,1},{6,8,1,2},{13,8,1,2},{0,10,4,1},{6,10,8,1},{2,11,2,4},{6,11,1,1},{13,11,1,1},{7,13,1,1},{12,13,1,1},{7,14,2,1},{11,14,2,1},{2,15,13,1},{2,16,2,1},{1,17,1,1},{3,17,3,1},{0,18,1,1},{4,18,12,1}}}
T.glyphs[36890] = {w=18, advance=16, rects={{1,4,2,1},{2,5,1,1},{5,5,10,1},{2,6,2,1},{12,6,2,1},{3,7,1,1},{7,7,2,1},{10,7,3,1},{8,8,3,1},{5,9,10,1},{0,10,4,1},{5,10,2,1},{9,10,2,1},{13,10,2,1},{2,11,2,5},{5,11,10,1},{5,12,2,1},{9,12,2,1},{13,12,2,1},{5,13,10,1},{5,14,2,3},{9,14,2,2},{13,14,2,2},{1,16,3,1},{9,16,5,1},{0,17,2,1},{3,17,2,1},{0,18,1,1},{4,18,12,1}}}
T.glyphs[36895] = {w=18, advance=16, rects={{1,4,1,1},{9,4,2,2},{1,5,2,1},{2,6,2,1},{5,6,11,1},{3,7,1,1},{9,7,2,1},{5,8,10,1},{0,9,4,1},{5,9,2,2},{9,9,2,2},{13,9,2,2},{2,10,2,5},{5,11,10,1},{5,12,2,1},{8,12,3,1},{13,12,2,1},{7,13,6,1},{5,14,3,1},{9,14,2,2},{12,14,3,1},{1,15,3,1},{5,15,1,1},{14,15,1,1},{0,16,5,1},{0,17,2,1},{4,17,12,1}}}
T.glyphs[36896] = {w=18, advance=16, rects={{1,4,2,1},{6,4,2,2},{10,4,1,2},{2,5,1,1},{2,6,2,1},{5,6,10,1},{3,7,1,1},{5,7,2,1},{9,7,2,1},{10,8,1,1},{0,9,4,1},{5,9,11,1},{2,10,2,6},{6,12,8,1},{6,13,1,2},{13,13,1,2},{6,15,8,1},{1,16,3,1},{6,16,1,1},{13,16,1,1},{0,17,2,1},{3,17,2,1},{0,18,1,1},{4,18,12,1}}}
T.glyphs[36923] = {w=18, advance=16, rects={{1,5,2,1},{5,5,10,1},{2,6,2,2},{5,6,1,2},{8,6,1,2},{11,6,1,2},{14,6,1,2},{5,8,10,1},{5,9,1,1},{7,9,2,2},{14,9,1,1},{0,10,4,1},{2,11,2,2},{6,11,8,1},{5,12,2,1},{12,12,2,1},{2,13,4,1},{7,13,2,1},{11,13,2,1},{2,14,3,1},{8,14,4,1},{2,15,2,1},{8,15,3,1},{1,16,3,1},{6,16,3,1},{0,17,7,1},{0,18,1,1},{4,18,12,1}}}
T.glyphs[36947] = {w=18, advance=16, rects={{1,4,1,1},{7,4,1,1},{12,4,1,1},{1,5,2,1},{7,5,2,1},{11,5,2,1},{2,6,2,2},{5,6,11,1},{9,7,1,2},{5,9,10,1},{0,10,4,1},{5,10,2,1},{13,10,2,1},{2,11,2,6},{5,11,10,1},{5,12,2,1},{13,12,2,1},{5,13,10,1},{5,14,2,1},{13,14,2,1},{5,15,10,1},{5,16,2,1},{13,16,2,1},{1,17,4,1},{0,18,1,1},{4,18,12,1}}}
T.glyphs[36981] = {w=18, advance=16, rects={{1,4,1,1},{7,4,1,1},{11,4,1,1},{1,5,2,1},{4,5,11,1},{2,6,1,2},{8,6,1,1},{10,6,2,1},{5,7,10,1},{5,8,1,3},{7,8,1,1},{10,8,2,1},{13,8,2,1},{11,9,4,1},{0,10,3,1},{13,10,2,1},{2,11,1,6},{5,11,10,1},{5,12,1,1},{13,12,2,1},{5,13,9,1},{12,14,1,1},{4,15,11,1},{6,16,1,1},{12,16,1,1},{1,17,3,1},{7,17,1,1},{9,17,4,1},{0,18,2,1},{3,18,3,1},{0,19,1,1},{4,19,12,1}}}
T.glyphs[36991] = {w=18, advance=16, rects={{12,4,1,2},{1,5,1,1},{5,5,4,1},{1,6,2,1},{5,6,1,3},{8,6,8,1},{2,7,1,1},{8,7,1,2},{10,8,2,1},{14,8,1,1},{5,9,4,1},{11,9,1,1},{13,9,1,1},{0,10,3,1},{5,10,1,1},{10,10,6,1},{2,11,1,2},{4,11,6,1},{12,11,1,2},{4,12,3,1},{8,12,2,1},{2,13,5,1},{8,13,8,1},{2,14,2,1},{5,14,2,1},{8,14,2,1},{12,14,1,3},{2,15,1,1},{5,15,5,1},{1,16,3,1},{5,16,2,1},{8,16,2,1},{0,17,2,1},{3,17,2,1},{0,18,1,1},{4,18,12,1}}}
T.glyphs[37027] = {w=18, advance=16, rects={{0,5,8,1},{10,5,5,1},{3,6,1,2},{7,6,1,2},{10,6,1,10},{14,6,1,1},{13,7,2,1},{0,8,8,1},{13,8,1,1},{3,9,1,3},{7,9,1,3},{12,9,2,2},{13,11,2,1},{0,12,8,1},{14,12,1,1},{2,13,2,2},{7,13,1,2},{14,13,2,2},{2,15,1,1},{6,15,2,2},{13,15,2,1},{1,16,2,1},{10,16,5,1},{1,17,1,1},{3,17,4,1},{10,17,1,2},{0,18,2,1}}}
T.glyphs[37051] = {w=18, advance=16, rects={{4,4,2,1},{3,5,4,1},{10,5,5,1},{3,6,1,1},{6,6,2,1},{10,6,1,2},{14,6,1,1},{2,7,2,1},{7,7,2,1},{13,7,2,1},{1,8,2,1},{4,8,1,1},{8,8,3,1},{13,8,1,1},{0,9,2,1},{5,9,1,1},{10,9,1,6},{12,9,2,2},{1,11,7,1},{13,11,2,1},{6,12,2,2},{14,12,1,1},{14,13,2,2},{2,14,1,1},{5,14,2,2},{2,15,2,1},{10,15,5,1},{3,16,3,1},{10,16,1,3},{4,17,2,1},{5,18,1,1}}}
T.glyphs[37096] = {w=18, advance=16, rects={{4,4,1,1},{4,5,2,1},{10,5,6,1},{1,6,8,1},{10,6,1,4},{14,6,1,1},{2,7,1,1},{6,7,2,2},{13,7,2,1},{2,8,2,1},{13,8,1,1},{3,9,1,1},{5,9,2,1},{12,9,2,2},{0,10,11,1},{10,11,1,5},{13,11,2,1},{14,12,2,3},{1,13,7,1},{1,14,2,3},{7,14,1,3},{12,15,4,1},{10,16,5,1},{1,17,7,1},{10,17,1,2},{1,18,2,1},{7,18,1,1}}}
T.glyphs[37117] = {w=18, advance=16, rects={{4,4,1,2},{10,5,6,1},{1,6,6,1},{8,6,1,1},{10,6,1,3},{14,6,1,1},{4,7,1,2},{7,7,2,1},{13,7,2,1},{6,8,2,1},{13,8,1,1},{0,9,11,1},{12,9,2,2},{4,10,2,1},{10,10,1,6},{3,11,2,1},{13,11,2,1},{1,12,7,1},{14,12,1,1},{0,13,3,1},{7,13,1,1},{14,13,2,2},{2,14,6,1},{2,15,1,2},{7,15,1,2},{13,15,3,1},{10,16,5,1},{2,17,6,1},{10,17,1,2},{2,18,1,1},{7,18,1,1}}}
T.glyphs[37197] = {w=18, advance=16, rects={{0,5,15,1},{3,6,1,2},{5,6,1,2},{14,6,1,4},{1,8,8,1},{1,9,1,3},{3,9,1,3},{5,9,1,3},{7,9,2,1},{7,10,8,1},{7,11,4,1},{14,11,1,1},{1,12,3,1},{5,12,6,1},{1,13,2,1},{7,13,4,2},{1,14,1,1},{14,14,2,3},{1,15,10,1},{1,16,1,1},{7,16,4,1},{1,17,8,1},{10,17,1,1},{14,17,1,1},{1,18,1,1},{7,18,2,1},{10,18,5,1}}}
T.glyphs[37319] = {w=18, advance=16, rects={{9,4,6,1},{1,5,12,1},{7,6,1,2},{13,6,1,1},{2,7,1,1},{12,7,2,1},{2,8,2,1},{7,8,2,1},{12,8,1,1},{3,9,2,2},{8,9,1,1},{11,9,2,1},{7,10,2,2},{11,10,1,1},{0,12,16,1},{6,13,4,1},{5,14,6,1},{3,15,3,1},{7,15,2,4},{10,15,3,1},{1,16,3,1},{12,16,3,1},{0,17,2,1},{13,17,3,1}}}
T.glyphs[37322] = {w=18, advance=16, rects={{3,4,3,1},{0,5,5,1},{7,5,8,1},{3,6,1,4},{8,6,1,1},{13,6,2,1},{1,7,1,2},{5,7,2,1},{9,7,1,1},{12,7,2,1},{5,8,1,1},{9,8,4,1},{8,9,7,1},{0,10,9,1},{13,10,3,1},{2,11,2,1},{10,11,2,2},{2,12,3,1},{2,13,4,1},{7,13,8,1},{1,14,1,1},{3,14,1,5},{5,14,1,1},{10,14,2,1},{0,15,2,1},{6,15,10,1},{0,16,1,1},{10,16,2,3}}}
T.glyphs[37324] = {w=18, advance=16, rects={{2,5,12,1},{2,6,1,2},{7,6,2,2},{13,6,1,2},{2,8,12,1},{2,9,1,2},{7,9,2,2},{13,9,1,2},{2,11,12,1},{2,12,1,1},{7,12,2,2},{13,12,1,1},{1,14,14,1},{7,15,2,2},{0,17,16,1}}}
T.glyphs[37325] = {w=18, advance=16, rects={{13,4,1,1},{1,5,13,1},{7,6,2,1},{0,7,16,1},{7,8,2,1},{2,9,12,1},{2,10,1,1},{7,10,2,1},{13,10,1,1},{2,11,12,1},{2,12,1,1},{7,12,2,1},{13,12,1,1},{2,13,12,1},{7,14,2,1},{1,15,14,1},{7,16,2,1},{0,17,16,1}}}
T.glyphs[37327] = {w=18, advance=16, rects={{3,5,10,1},{3,6,1,1},{12,6,1,1},{3,7,10,1},{3,8,1,1},{12,8,1,1},{4,9,8,1},{0,11,16,1},{3,12,1,1},{7,12,2,1},{12,12,2,1},{3,13,11,1},{3,14,1,1},{7,14,2,1},{12,14,2,1},{1,15,14,1},{7,16,2,1},{0,17,16,1}}}
T.glyphs[38024] = {w=18, advance=16, rects={{2,4,2,1},{11,4,1,5},{2,5,1,1},{2,6,5,1},{1,7,2,1},{1,8,1,1},{0,9,16,1},{0,10,1,1},{3,10,1,2},{10,10,2,1},{11,11,1,8},{0,12,7,1},{3,13,1,3},{6,15,1,1},{3,16,4,1},{3,17,2,1},{3,18,1,1}}}
T.glyphs[38025] = {w=18, advance=16, rects={{2,4,2,1},{2,5,1,1},{7,5,9,1},{2,6,5,1},{12,6,1,11},{1,7,2,1},{0,8,2,1},{0,9,7,1},{3,10,1,2},{0,12,7,1},{3,13,1,3},{6,15,1,1},{3,16,4,1},{3,17,2,1},{11,17,2,1},{3,18,1,1},{8,18,5,1},{9,19,2,1}}}
T.glyphs[38047] = {w=18, advance=16, rects={{2,4,2,1},{10,4,2,3},{2,5,1,1},{2,6,4,1},{1,7,1,1},{7,7,8,1},{0,8,2,1},{7,8,1,5},{10,8,2,5},{14,8,1,5},{0,9,6,1},{2,10,2,2},{0,12,6,1},{2,13,2,4},{7,13,8,1},{7,14,1,1},{10,14,2,5},{14,14,1,1},{5,16,1,1},{2,17,4,1},{2,18,2,1}}}
T.glyphs[38057] = {w=18, advance=16, rects={{2,4,2,1},{8,4,1,1},{2,5,1,1},{7,5,2,1},{2,6,4,1},{7,6,8,1},{1,7,1,1},{7,7,1,1},{14,7,1,9},{0,8,2,1},{6,8,2,1},{9,8,1,1},{0,9,7,1},{8,9,2,1},{2,10,2,2},{8,10,1,1},{7,11,2,1},{10,11,1,1},{0,12,6,1},{7,12,1,1},{10,12,2,1},{2,13,2,4},{6,13,2,1},{11,13,1,1},{6,14,7,1},{12,15,1,1},{5,16,1,1},{13,16,2,2},{2,17,4,1},{2,18,2,1},{9,18,5,1}}}
T.glyphs[38062] = {w=18, advance=16, rects={{2,4,2,1},{2,5,1,1},{6,5,9,1},{2,6,4,1},{8,6,2,5},{13,6,2,5},{1,7,1,1},{0,8,2,1},{0,9,6,1},{2,10,2,2},{6,11,9,1},{0,12,6,1},{8,12,2,2},{13,12,2,4},{2,13,2,3},{8,14,1,3},{5,15,1,1},{2,16,4,1},{13,16,1,1},{2,17,2,1},{5,17,11,1}}}
T.glyphs[38067] = {w=18, advance=16, rects={{2,4,2,1},{7,4,1,2},{13,4,1,2},{2,5,1,1},{2,6,14,1},{1,7,1,1},{7,7,1,4},{13,7,1,4},{0,8,2,1},{0,9,6,1},{2,10,2,2},{7,11,7,1},{0,12,6,1},{7,12,1,5},{13,12,1,5},{2,13,2,4},{5,16,1,1},{2,17,4,1},{7,17,7,1},{2,18,2,1},{7,18,1,1},{13,18,1,1}}}
T.glyphs[38075] = {w=18, advance=16, rects={{2,4,2,1},{10,4,1,3},{2,5,1,1},{2,6,5,1},{1,7,1,1},{10,7,6,1},{0,8,2,1},{10,8,1,4},{0,9,6,1},{2,10,2,2},{0,12,6,1},{7,12,8,1},{2,13,2,4},{7,13,1,4},{14,13,1,4},{5,16,1,1},{2,17,4,1},{7,17,8,1},{2,18,2,1},{7,18,1,1},{14,18,1,1}}}
T.glyphs[38138] = {w=18, advance=16, rects={{2,4,1,2},{10,4,1,2},{12,4,1,1},{12,5,2,1},{1,6,15,1},{1,7,1,1},{10,7,1,2},{0,8,2,1},{0,9,5,1},{6,9,9,1},{2,10,2,1},{6,10,1,2},{10,10,1,2},{14,10,1,2},{2,11,1,1},{0,12,15,1},{2,13,2,1},{6,13,1,1},{10,13,1,1},{14,13,1,1},{2,14,1,2},{6,14,9,1},{6,15,1,4},{10,15,1,3},{14,15,1,2},{2,16,3,2},{13,17,2,1},{2,18,1,1},{10,18,5,1}}}
T.glyphs[38142] = {w=18, advance=16, rects={{2,4,1,2},{6,4,1,1},{11,4,1,2},{6,5,2,1},{1,6,7,1},{9,6,7,1},{1,7,1,1},{7,7,1,1},{10,7,1,1},{0,8,2,1},{9,8,2,1},{12,8,1,2},{0,9,8,1},{9,9,1,1},{2,10,2,2},{6,10,2,1},{9,10,6,1},{7,11,1,2},{12,11,1,2},{0,12,6,1},{2,13,2,2},{7,13,9,1},{6,14,2,2},{12,14,1,2},{2,15,3,1},{2,16,2,1},{6,16,1,1},{8,16,1,1},{2,17,1,1},{5,17,2,1},{9,17,7,1},{5,18,1,1}}}
T.glyphs[38144] = {w=18, advance=16, rects={{2,4,2,1},{10,4,1,4},{2,5,1,1},{6,5,2,1},{14,5,1,1},{2,6,4,1},{7,6,2,1},{13,6,2,1},{1,7,1,1},{12,7,2,1},{0,8,2,1},{6,8,9,1},{0,9,8,1},{13,9,2,1},{2,10,2,2},{6,10,2,1},{14,10,1,1},{6,11,9,1},{0,12,8,1},{13,12,2,1},{2,13,2,3},{6,13,2,1},{14,13,1,1},{6,14,9,1},{6,15,2,1},{13,15,2,1},{2,16,6,1},{14,16,1,1},{2,17,3,1},{6,17,2,2},{13,17,2,1},{2,18,2,1},{10,18,5,1}}}
T.glyphs[38145] = {w=18, advance=16, rects={{2,4,2,1},{6,4,1,1},{10,4,1,4},{14,4,1,1},{2,5,1,1},{6,5,2,1},{13,5,2,1},{1,6,5,1},{7,6,1,1},{13,6,1,1},{1,7,1,1},{0,8,1,1},{6,8,9,1},{1,9,7,1},{14,9,1,6},{2,10,2,2},{6,10,2,2},{10,10,1,5},{0,12,8,1},{2,13,2,3},{6,13,2,2},{9,15,3,1},{2,16,4,1},{8,16,2,1},{11,16,3,1},{2,17,3,1},{6,17,3,1},{13,17,2,1},{2,18,2,1},{5,18,2,1},{14,18,1,1}}}
T.glyphs[38169] = {w=18, advance=16, rects={{2,4,1,2},{8,4,1,2},{12,4,1,2},{1,6,14,1},{1,7,1,1},{8,7,1,2},{12,7,1,2},{0,8,2,1},{0,9,16,1},{2,10,2,2},{6,11,9,1},{0,12,8,1},{13,12,2,2},{2,13,2,3},{6,13,2,1},{6,14,9,1},{6,15,2,2},{13,15,2,2},{2,16,3,1},{2,17,2,1},{6,17,9,1},{2,18,1,1},{6,18,2,1},{13,18,2,1}}}
T.glyphs[38170] = {w=18, advance=16, rects={{2,4,1,2},{8,4,1,2},{12,4,1,2},{1,6,15,1},{1,7,1,1},{8,7,1,2},{12,7,1,2},{0,8,2,1},{0,9,5,1},{2,10,2,2},{6,10,9,1},{6,11,2,1},{10,11,1,2},{14,11,1,2},{0,12,7,1},{2,13,2,3},{6,13,9,1},{6,14,1,2},{10,14,1,3},{14,14,1,3},{2,16,5,1},{2,17,3,1},{6,17,9,1},{2,18,1,1},{6,18,2,1},{14,18,1,1}}}
T.glyphs[38190] = {w=18, advance=16, rects={{2,4,1,1},{11,4,1,2},{1,5,2,2},{5,6,3,1},{9,6,6,1},{1,7,4,1},{6,7,2,1},{11,7,1,1},{13,7,2,1},{0,8,2,1},{6,8,1,1},{8,8,8,1},{0,9,7,1},{11,9,1,1},{13,9,2,1},{2,10,1,2},{5,10,3,1},{9,10,6,1},{7,11,1,1},{11,11,1,1},{13,11,2,1},{0,12,5,1},{7,12,8,1},{2,13,1,3},{5,13,3,1},{11,13,1,1},{5,14,2,1},{8,14,7,1},{4,15,1,1},{6,15,1,1},{11,15,1,2},{2,16,2,1},{5,16,4,1},{2,17,1,1},{5,17,1,1},{8,17,8,1},{4,18,1,1}}}
T.glyphs[38236] = {w=18, advance=16, rects={{2,4,1,1},{9,4,2,1},{1,5,2,1},{6,5,9,1},{1,6,4,1},{7,6,2,1},{12,6,1,1},{0,7,2,1},{8,7,1,1},{11,7,2,1},{0,8,16,1},{2,9,2,2},{6,10,8,1},{0,11,5,1},{6,11,1,1},{13,11,1,1},{2,12,2,3},{6,12,8,1},{6,13,1,1},{13,13,1,1},{6,14,8,1},{2,15,3,2},{6,15,1,1},{8,15,1,1},{11,15,1,2},{13,15,1,1},{7,16,2,1},{14,16,2,1},{2,17,1,1},{5,17,2,1},{11,17,4,1}}}
T.glyphs[38271] = {w=18, advance=16, rects={{3,5,2,5},{12,5,1,1},{10,6,3,1},{9,7,2,1},{7,8,3,1},{6,9,2,1},{0,10,16,1},{3,11,2,5},{7,11,2,1},{8,12,2,2},{9,14,2,1},{6,15,2,1},{10,15,3,1},{3,16,5,1},{12,16,3,1},{3,17,2,1},{13,17,2,1}}}
T.glyphs[38376] = {w=18, advance=16, rects={{2,4,2,1},{3,5,2,1},{6,5,9,1},{4,6,1,1},{13,6,2,13},{1,7,2,13},{10,19,4,1}}}
T.glyphs[38378] = {w=18, advance=16, rects={{2,4,1,1},{2,5,2,1},{6,5,9,1},{3,6,2,1},{13,6,2,12},{1,7,2,8},{7,7,2,4},{7,11,3,1},{6,12,2,1},{9,12,2,1},{5,13,2,1},{10,13,1,1},{4,14,2,1},{10,14,2,1},{1,15,4,1},{11,15,1,1},{1,16,2,3},{10,18,5,1}}}
T.glyphs[38381] = {w=18, advance=16, rects={{2,4,1,1},{2,5,3,1},{6,5,9,1},{3,6,2,1},{14,6,1,12},{1,7,1,12},{9,7,1,2},{3,9,10,1},{8,10,2,1},{7,11,3,1},{7,12,1,1},{9,12,1,5},{6,13,1,1},{5,14,1,1},{4,15,1,1},{3,16,1,1},{6,17,4,1},{10,18,5,1}}}
T.glyphs[38382] = {w=18, advance=16, rects={{2,4,1,1},{2,5,3,1},{6,5,9,1},{3,6,2,1},{13,6,2,1},{1,7,1,11},{14,7,1,9},{5,9,6,1},{5,10,1,3},{10,10,1,3},{5,13,6,1},{5,14,1,1},{13,16,2,1},{10,17,5,1}}}
T.glyphs[38388] = {w=18, advance=16, rects={{2,4,1,1},{2,5,2,1},{6,5,9,1},{3,6,2,1},{14,6,1,12},{1,7,1,12},{5,8,6,1},{5,9,1,2},{10,9,1,2},{5,11,6,1},{5,12,1,3},{10,12,1,3},{5,15,6,1},{5,16,1,1},{10,18,5,1}}}
T.glyphs[38408] = {w=18, advance=16, rects={{2,4,1,1},{3,5,1,1},{6,5,9,1},{3,6,2,1},{8,6,3,1},{14,6,1,2},{1,7,1,12},{8,7,2,1},{11,7,1,1},{3,8,12,1},{8,9,2,1},{14,9,1,9},{9,10,1,2},{11,10,2,1},{3,11,5,1},{11,11,1,1},{3,12,2,1},{7,12,1,1},{9,12,3,1},{3,13,5,1},{9,13,2,2},{3,14,2,1},{12,14,1,1},{4,15,5,1},{10,15,3,1},{3,16,3,1},{11,16,2,1},{11,18,4,1}}}
T.glyphs[38450] = {w=18, advance=16, rects={{9,4,2,1},{1,5,5,1},{10,5,1,1},{1,6,1,9},{4,6,12,1},{4,7,1,2},{8,7,2,1},{8,8,1,2},{3,9,2,2},{8,10,7,1},{4,11,1,1},{8,11,1,2},{13,11,2,2},{4,12,2,3},{7,13,2,2},{13,13,1,4},{1,15,4,1},{7,15,1,1},{1,16,1,3},{6,16,2,1},{5,17,2,1},{9,17,5,1},{4,18,2,1}}}
T.glyphs[38454] = {w=18, advance=16, rects={{10,3,1,1},{1,4,5,1},{9,4,3,1},{1,5,1,10},{4,5,1,2},{8,5,2,1},{11,5,1,1},{8,6,1,1},{11,6,2,1},{3,7,2,2},{7,7,2,1},{12,7,2,1},{6,8,2,1},{13,8,2,1},{3,9,1,1},{5,9,2,1},{14,9,2,1},{3,10,2,1},{7,10,2,5},{12,10,1,10},{4,11,1,1},{4,12,2,3},{1,15,4,1},{7,15,1,2},{1,16,1,4},{6,17,2,1},{6,18,1,1},{5,19,2,1}}}
T.glyphs[38468] = {w=18, advance=16, rects={{8,4,1,1},{13,4,1,4},{1,5,5,1},{7,5,2,1},{1,6,1,10},{4,6,2,1},{7,6,1,2},{4,7,1,1},{3,8,2,2},{6,8,10,1},{6,9,2,1},{12,9,2,1},{3,10,1,1},{5,10,3,1},{13,10,1,7},{3,11,5,1},{9,11,1,1},{4,12,1,1},{7,12,1,8},{9,12,2,1},{4,13,2,3},{10,13,1,1},{1,16,4,1},{1,17,1,3},{12,17,2,1},{9,18,5,1}}}
T.glyphs[38469] = {w=18, advance=16, rects={{1,5,14,1},{1,6,1,9},{4,6,2,1},{4,7,1,1},{3,8,2,1},{3,9,13,1},{3,10,2,1},{10,10,1,7},{4,11,1,1},{4,12,2,2},{7,12,1,2},{12,12,2,1},{13,13,1,1},{4,14,4,1},{13,14,2,1},{1,15,6,1},{14,15,1,1},{1,16,1,3},{5,16,2,1},{14,16,2,1},{9,17,2,1},{7,18,4,1}}}
T.glyphs[38472] = {w=18, advance=16, rects={{9,4,1,1},{1,5,5,1},{8,5,2,1},{1,6,1,10},{4,6,12,1},{4,7,1,1},{7,7,2,2},{3,8,2,2},{10,8,2,3},{7,9,1,1},{3,10,1,1},{6,10,2,1},{3,11,2,1},{6,11,10,1},{4,12,1,1},{10,12,2,6},{4,13,2,2},{7,13,2,1},{13,13,1,1},{7,14,1,1},{13,14,2,1},{4,15,4,1},{14,15,1,1},{1,16,6,1},{14,16,2,1},{1,17,1,2},{7,18,4,1}}}
T.glyphs[38477] = {w=18, advance=16, rects={{8,4,2,2},{1,5,5,1},{1,6,1,9},{4,6,1,2},{7,6,8,1},{6,7,3,1},{12,7,2,1},{3,8,2,3},{6,8,1,1},{9,8,4,1},{8,9,6,1},{6,10,3,1},{12,10,4,1},{4,11,1,2},{10,11,2,1},{6,12,9,1},{4,13,2,1},{10,13,2,3},{4,14,4,1},{1,15,4,1},{6,15,2,1},{1,16,1,3},{6,16,9,1},{10,17,2,2}}}
T.glyphs[38480] = {w=18, advance=16, rects={{1,4,5,1},{7,4,7,1},{1,5,1,10},{4,5,2,1},{7,5,1,2},{13,5,1,2},{4,6,1,2},{7,7,7,1},{3,8,2,3},{7,8,1,2},{13,8,1,2},{7,10,7,1},{4,11,1,1},{7,11,1,6},{9,11,2,1},{13,11,1,1},{4,12,2,3},{10,12,1,1},{14,12,1,1},{10,13,4,1},{11,14,2,2},{1,15,4,1},{1,16,1,3},{9,16,2,1},{12,16,3,1},{6,17,4,1},{14,17,1,1},{7,18,1,1}}}
T.glyphs[38500] = {w=18, advance=16, rects={{9,4,2,1},{1,5,5,1},{9,5,3,1},{1,6,1,8},{4,6,1,2},{8,6,2,1},{11,6,2,1},{7,7,2,1},{12,7,2,1},{3,8,2,1},{6,8,2,1},{13,8,2,1},{3,9,1,1},{5,9,11,1},{3,10,2,1},{10,10,1,2},{4,11,1,1},{4,12,11,1},{4,13,2,1},{10,13,1,3},{1,14,4,1},{7,14,1,1},{12,14,1,1},{1,15,1,3},{6,15,2,1},{12,15,2,1},{5,16,2,1},{9,16,2,1},{13,16,2,1},{5,17,1,1},{7,17,4,1},{14,17,1,1}}}
T.glyphs[38505] = {w=18, advance=16, rects={{9,4,2,1},{1,5,5,1},{9,5,3,1},{1,6,1,9},{4,6,1,2},{8,6,2,1},{11,6,2,1},{7,7,2,1},{12,7,2,1},{3,8,2,1},{6,8,2,1},{13,8,2,1},{3,9,1,2},{5,9,1,1},{14,9,2,1},{7,10,7,1},{3,11,2,1},{4,12,1,3},{9,12,1,1},{13,12,2,1},{6,13,1,1},{9,13,2,1},{13,13,1,1},{6,14,2,1},{10,14,1,2},{12,14,2,2},{1,15,4,1},{7,15,1,1},{1,16,1,3},{11,16,2,1},{5,17,10,1}}}
T.glyphs[38543] = {w=18, advance=16, rects={{6,4,1,3},{11,4,1,1},{1,5,4,1},{10,5,2,1},{1,6,1,8},{4,6,1,1},{8,6,8,1},{3,7,2,1},{6,7,2,1},{9,7,2,1},{3,8,1,2},{9,8,6,1},{5,9,2,1},{8,9,2,1},{13,9,2,1},{3,10,2,1},{6,10,9,1},{4,11,1,3},{6,11,1,5},{9,11,1,1},{13,11,2,1},{9,12,6,1},{9,13,1,3},{13,13,2,2},{1,14,4,1},{1,15,1,4},{11,15,3,1},{5,16,3,1},{5,17,1,1},{7,17,9,1},{4,18,1,1}}}
T.glyphs[38544] = {w=18, advance=16, rects={{8,4,1,1},{1,5,5,1},{7,5,2,1},{1,6,1,8},{4,6,10,1},{4,7,1,1},{6,7,1,1},{11,7,2,1},{3,8,12,1},{3,9,1,1},{13,9,2,1},{3,10,2,1},{6,10,9,1},{4,11,1,1},{13,11,2,1},{4,12,11,1},{4,13,2,1},{9,13,1,1},{1,14,7,1},{9,14,2,1},{13,14,1,1},{1,15,1,4},{5,15,1,2},{7,15,1,1},{10,15,1,1},{12,15,3,1},{7,16,2,1},{12,16,1,1},{14,16,2,1},{4,17,2,1},{7,17,6,1}}}
T.glyphs[38548] = {w=18, advance=16, rects={{1,5,4,1},{6,5,10,1},{1,6,1,9},{4,6,1,2},{7,7,7,1},{3,8,2,1},{7,8,1,1},{13,8,1,1},{3,9,1,2},{7,9,7,1},{3,11,2,1},{6,11,9,1},{4,12,1,3},{6,12,1,3},{8,12,1,1},{12,12,1,1},{14,12,1,3},{8,13,2,1},{11,13,2,1},{9,14,1,1},{11,14,1,1},{1,15,4,1},{6,15,9,1},{1,16,1,3},{6,16,1,3},{10,16,1,3},{14,16,1,2},{12,18,3,1}}}
T.glyphs[38553] = {w=18, advance=16, rects={{9,4,2,1},{1,5,4,1},{7,5,4,1},{12,5,1,1},{1,6,1,10},{4,6,1,1},{6,6,2,1},{9,6,2,2},{13,6,2,1},{3,7,4,1},{14,7,2,1},{3,8,2,1},{6,8,8,1},{3,9,1,2},{6,9,2,1},{13,9,1,1},{6,10,8,1},{3,11,2,1},{6,11,2,1},{13,11,1,1},{4,12,1,4},{6,12,8,1},{6,13,2,1},{10,13,1,4},{13,13,1,1},{7,15,1,1},{12,15,1,1},{1,16,4,1},{6,16,2,1},{13,16,1,1},{1,17,1,2},{5,17,2,1},{9,17,2,1},{14,17,1,1},{5,18,1,1},{7,18,4,1},{15,18,1,1}}}
T.glyphs[38556] = {w=18, advance=16, rects={{9,4,2,1},{1,5,4,1},{10,5,1,1},{1,6,1,9},{4,6,1,1},{6,6,9,1},{3,7,2,1},{7,7,2,1},{12,7,2,1},{3,8,13,1},{3,9,1,2},{6,10,9,1},{3,11,2,1},{6,11,1,1},{13,11,2,1},{4,12,1,3},{6,12,9,1},{6,13,1,1},{13,13,2,1},{6,14,9,1},{1,15,4,1},{10,15,1,1},{1,16,1,2},{5,16,11,1},{10,17,1,1}}}
T.glyphs[38590] = {w=18, advance=16, rects={{8,3,1,1},{10,3,2,1},{7,4,2,1},{11,4,1,2},{1,5,4,1},{7,5,1,1},{4,6,1,3},{7,6,8,1},{1,7,1,1},{6,7,2,2},{11,7,1,2},{1,8,2,1},{1,9,14,1},{2,10,4,1},{7,10,1,3},{11,10,1,3},{2,11,2,1},{2,12,3,2},{7,13,8,1},{2,14,1,1},{4,14,2,2},{7,14,1,2},{11,14,1,2},{1,15,2,1},{0,16,2,1},{7,16,9,1},{0,17,1,1},{7,17,1,1}}}
T.glyphs[38596] = {w=18, advance=16, rects={{3,4,1,3},{8,4,2,1},{11,4,1,2},{8,5,1,1},{7,6,2,1},{11,6,2,1},{0,7,16,1},{2,8,2,1},{7,8,2,1},{11,8,1,2},{2,9,1,2},{6,9,3,1},{4,10,1,2},{6,10,9,1},{1,11,2,1},{7,11,2,3},{11,11,1,3},{1,12,1,1},{3,12,2,1},{0,13,2,1},{3,13,1,2},{0,14,1,1},{5,14,1,2},{7,14,8,1},{2,15,1,1},{7,15,2,1},{11,15,1,2},{1,16,8,1},{1,17,15,1},{7,18,2,1}}}
T.glyphs[38598] = {w=18, advance=16, rects={{4,4,1,1},{8,4,1,1},{3,5,2,1},{8,5,2,1},{2,6,13,1},{2,7,2,1},{8,7,1,1},{1,8,13,1},{0,9,4,1},{8,9,1,1},{2,10,12,1},{2,11,2,1},{8,11,1,1},{2,12,13,1},{7,13,2,1},{1,14,14,1},{5,15,6,1},{2,16,3,1},{7,16,2,2},{10,16,4,1},{0,17,3,1},{13,17,3,1}}}
T.glyphs[38646] = {w=18, advance=16, rects={{1,5,13,1},{7,6,2,1},{1,7,14,1},{1,8,1,2},{3,8,3,1},{7,8,2,2},{10,8,3,1},{14,8,1,2},{3,11,3,1},{7,11,6,1},{5,12,2,1},{8,12,3,1},{2,13,4,1},{7,13,1,1},{10,13,4,1},{0,14,3,1},{7,14,2,1},{13,14,3,1},{3,15,10,1},{10,16,2,1},{4,17,6,1},{8,18,3,1}}}
T.glyphs[38656] = {w=18, advance=16, rects={{2,5,12,1},{7,6,2,1},{1,7,14,1},{1,8,1,2},{7,8,2,1},{14,8,1,2},{3,9,10,1},{7,10,2,1},{3,11,10,1},{0,13,16,1},{7,14,1,1},{2,15,12,1},{2,16,1,3},{5,16,2,3},{9,16,2,2},{13,16,1,2},{9,18,5,1}}}
T.glyphs[38706] = {w=18, advance=16, rects={{2,5,12,1},{7,6,2,1},{1,7,14,1},{1,8,1,1},{7,8,2,1},{14,8,1,1},{2,9,12,1},{8,10,2,1},{1,11,5,1},{8,11,6,1},{1,12,2,1},{5,12,1,1},{7,12,3,1},{12,12,2,1},{1,13,7,1},{9,13,4,1},{3,14,2,1},{8,14,2,1},{12,14,2,1},{1,15,1,3},{3,15,6,1},{13,15,3,1},{3,16,2,2},{8,16,6,1},{8,17,1,1},{13,17,1,1},{0,18,7,1},{8,18,6,1}}}
T.glyphs[38745] = {w=18, advance=16, rects={{9,3,2,1},{3,4,2,1},{9,4,1,1},{0,5,7,1},{8,5,6,1},{3,6,2,1},{7,6,2,1},{12,6,1,1},{1,7,6,1},{11,7,2,1},{3,8,2,1},{7,8,8,1},{0,9,7,1},{10,9,2,2},{13,9,2,2},{1,11,15,1},{1,12,1,1},{5,12,2,1},{10,12,2,2},{13,12,2,2},{1,13,6,1},{1,14,1,1},{5,14,10,1},{1,15,6,1},{10,15,2,3},{13,15,2,1},{1,16,1,3},{5,16,2,2},{3,18,3,1},{8,18,3,1}}}
T.glyphs[38750] = {w=18, advance=16, rects={{5,4,2,2},{9,4,2,2},{1,6,6,1},{9,6,6,1},{5,7,2,3},{9,7,2,3},{1,10,6,1},{9,10,6,1},{5,11,2,3},{9,11,2,3},{0,14,7,1},{9,14,7,1},{5,15,2,4},{9,15,2,4}}}
T.glyphs[38752] = {w=18, advance=16, rects={{3,4,2,1},{7,4,2,1},{2,5,12,1},{2,6,1,1},{7,6,2,1},{0,7,16,1},{2,9,12,1},{2,10,2,1},{12,10,2,1},{2,11,12,1},{6,12,1,1},{9,12,1,1},{1,13,6,1},{9,13,6,1},{6,14,1,1},{9,14,1,1},{1,15,6,1},{9,15,6,1},{6,16,1,1},{9,16,1,1},{0,17,7,1},{9,17,7,1},{6,18,1,1},{9,18,1,1}}}
T.glyphs[38754] = {w=18, advance=16, rects={{0,5,16,1},{7,6,1,1},{6,7,2,1},{1,8,14,1},{1,9,2,8},{5,9,1,2},{10,9,1,2},{13,9,2,8},{5,11,6,1},{5,12,1,2},{10,12,1,2},{5,14,6,1},{5,15,1,2},{10,15,1,2},{1,17,14,1},{1,18,2,1},{13,18,2,1}}}
T.glyphs[38795] = {w=18, advance=16, rects={{2,4,1,1},{5,4,1,1},{11,4,1,2},{0,5,8,1},{2,6,1,2},{5,6,1,2},{8,6,7,1},{11,7,1,3},{2,8,4,1},{3,9,2,1},{1,10,15,1},{1,11,1,2},{3,11,2,2},{6,11,1,2},{11,12,1,2},{1,13,6,1},{1,14,1,1},{3,14,2,2},{6,14,1,1},{8,14,7,1},{11,15,1,3},{0,16,8,1},{3,17,2,2},{7,18,9,1}}}
T.glyphs[38899] = {w=18, advance=16, rects={{7,4,2,1},{1,5,14,1},{4,6,2,2},{10,6,2,2},{0,8,16,1},{2,10,12,1},{2,11,2,2},{12,11,2,2},{2,13,12,1},{2,14,2,2},{12,14,2,2},{2,16,12,1},{2,17,2,1},{12,17,2,1}}}
T.glyphs[39029] = {w=18, advance=16, rects={{0,4,16,1},{7,5,2,1},{7,6,1,1},{2,7,12,1},{2,8,2,7},{12,8,2,7},{7,9,2,5},{6,14,4,1},{6,15,2,1},{9,15,3,1},{4,16,3,1},{10,16,3,1},{2,17,3,1},{12,17,3,1},{1,18,2,1},{14,18,1,1}}}
T.glyphs[39030] = {w=18, advance=16, rects={{0,5,16,1},{3,6,1,10},{10,6,1,1},{9,7,2,1},{6,8,9,1},{6,9,2,6},{14,9,1,6},{10,10,1,5},{9,15,3,1},{2,16,2,1},{8,16,2,1},{11,16,3,1},{0,17,4,1},{6,17,3,1},{13,17,2,1},{5,18,2,1},{14,18,1,1}}}
T.glyphs[39033] = {w=18, advance=16, rects={{6,5,10,1},{0,6,6,1},{10,6,1,1},{2,7,2,6},{9,7,2,1},{6,8,9,1},{6,9,2,4},{13,9,2,6},{10,10,1,4},{2,13,6,1},{1,14,7,1},{9,14,2,1},{0,15,2,1},{8,15,5,1},{6,16,3,1},{12,16,3,1},{5,17,2,1},{14,17,1,1}}}
T.glyphs[39034] = {w=18, advance=16, rects={{1,4,2,1},{5,4,2,1},{1,5,15,1},{1,6,6,4},{10,6,2,2},{8,8,7,1},{8,9,1,7},{14,9,1,7},{1,10,1,7},{3,10,4,8},{11,10,1,5},{10,15,2,1},{9,16,5,1},{0,17,2,1},{8,17,2,1},{13,17,2,1},{0,18,1,1},{7,18,2,1},{14,18,2,1}}}
T.glyphs[39035] = {w=18, advance=16, rects={{4,4,1,1},{3,5,2,1},{6,5,10,1},{3,6,1,1},{10,6,1,1},{2,7,2,1},{9,7,2,1},{1,8,2,1},{4,8,1,2},{6,8,9,1},{0,9,2,1},{6,9,2,4},{13,9,2,1},{3,10,1,1},{10,10,1,5},{14,10,1,5},{2,11,2,1},{0,12,3,1},{0,13,2,1},{4,13,4,1},{4,14,1,1},{6,14,2,1},{3,15,2,1},{9,15,3,1},{2,16,2,1},{8,16,2,1},{11,16,3,1},{0,17,3,1},{6,17,3,1},{13,17,2,1},{1,18,1,1},{5,18,2,1},{14,18,1,1}}}
T.glyphs[39039] = {w=18, advance=16, rects={{3,4,2,2},{7,5,9,1},{0,6,7,1},{11,6,1,2},{3,7,2,5},{1,8,1,4},{6,8,1,4},{8,8,7,1},{8,9,1,7},{14,9,1,7},{11,10,1,5},{1,12,6,1},{3,13,2,4},{6,13,1,1},{10,15,3,1},{6,16,1,1},{9,16,2,1},{12,16,2,1},{3,17,4,1},{8,17,2,1},{13,17,2,1},{3,18,2,1},{8,18,1,1},{14,18,1,1}}}
T.glyphs[39044] = {w=18, advance=16, rects={{0,5,16,1},{4,6,2,1},{10,6,2,2},{2,7,1,1},{4,7,1,1},{2,8,2,1},{7,8,8,1},{3,9,1,1},{7,9,2,1},{14,9,1,7},{0,10,9,1},{11,10,1,1},{3,11,1,6},{5,11,4,1},{10,11,2,5},{5,12,1,2},{7,12,2,4},{9,16,5,1},{2,17,2,1},{7,17,2,1},{13,17,2,1},{0,18,4,1},{6,18,2,1},{14,18,2,1}}}
T.glyphs[39045] = {w=18, advance=16, rects={{3,4,2,2},{7,4,9,1},{10,5,2,2},{3,6,4,1},{3,7,2,2},{8,7,7,1},{8,8,1,7},{14,8,1,7},{1,9,6,1},{11,9,1,4},{1,10,2,1},{5,10,2,2},{1,11,1,1},{1,12,6,1},{1,13,1,3},{5,13,2,1},{10,13,2,2},{9,15,4,1},{0,16,2,1},{8,16,2,1},{12,16,3,1},{0,17,1,1},{7,17,2,1},{14,17,2,1}}}
T.glyphs[39052] = {w=18, advance=16, rects={{3,4,2,1},{7,4,9,1},{2,5,3,1},{10,5,2,2},{2,6,1,1},{5,6,1,1},{1,7,2,1},{5,7,2,1},{8,7,7,1},{0,8,2,1},{6,8,3,1},{14,8,1,7},{0,9,6,1},{8,9,1,6},{11,9,1,4},{1,12,6,1},{1,13,1,3},{5,13,2,3},{10,13,2,2},{9,15,5,1},{1,16,6,1},{8,16,2,1},{13,16,2,1},{1,17,1,1},{5,17,4,1},{14,17,2,1}}}
T.glyphs[39057] = {w=18, advance=16, rects={{4,4,1,3},{7,5,9,1},{1,6,2,4},{10,6,2,2},{4,7,3,1},{4,8,1,2},{8,8,7,1},{8,9,1,1},{14,9,1,7},{0,10,9,1},{11,10,1,4},{8,11,1,5},{4,12,1,3},{1,13,2,1},{1,14,1,1},{6,14,1,1},{10,14,2,2},{0,15,2,1},{4,15,3,1},{3,16,3,1},{9,16,5,1},{1,17,4,1},{8,17,2,1},{13,17,2,1},{0,18,3,1},{6,18,2,1},{14,18,2,1}}}
T.glyphs[39063] = {w=18, advance=16, rects={{1,4,6,1},{8,4,8,1},{1,5,1,2},{3,5,2,2},{6,5,1,2},{11,5,1,2},{1,7,6,1},{10,7,2,1},{1,8,1,2},{3,8,2,2},{6,8,1,2},{8,8,7,1},{8,9,2,4},{14,9,1,7},{1,10,6,1},{11,10,1,5},{1,11,1,1},{3,11,2,2},{6,11,1,1},{0,13,10,1},{3,14,2,1},{8,14,2,1},{2,15,5,1},{8,15,1,1},{10,15,3,1},{1,16,4,1},{6,16,2,1},{10,16,1,1},{12,16,2,1},{0,17,2,1},{3,17,2,1},{8,17,2,1},{13,17,2,1},{4,18,1,1},{7,18,2,1},{14,18,1,1}}}
T.glyphs[39064] = {w=18, advance=16, rects={{1,5,15,1},{1,6,1,1},{6,6,1,1},{10,6,2,2},{1,7,6,1},{1,8,1,2},{6,8,1,2},{8,8,7,1},{8,9,1,3},{13,9,2,5},{1,10,6,1},{11,10,1,3},{0,12,9,1},{4,13,1,2},{8,13,1,1},{10,13,2,1},{1,14,2,2},{10,14,3,1},{4,15,4,1},{9,15,2,1},{12,15,2,1},{1,16,4,1},{7,16,2,1},{13,16,2,1},{0,17,2,1},{3,17,2,1},{4,18,12,1}}}
T.glyphs[39068] = {w=18, advance=16, rects={{4,4,1,2},{8,5,8,1},{1,6,7,1},{11,6,1,2},{2,7,1,1},{6,7,1,1},{2,8,2,1},{5,8,2,1},{8,8,7,1},{3,9,1,1},{5,9,1,1},{8,9,2,1},{14,9,1,7},{1,10,9,1},{11,10,1,5},{1,11,1,2},{6,11,1,1},{8,11,2,2},{4,12,2,1},{1,13,3,1},{6,13,4,1},{1,14,1,3},{5,14,2,1},{8,14,2,1},{3,15,2,1},{7,15,5,1},{5,16,2,1},{10,16,4,1},{0,17,2,1},{3,17,3,1},{8,17,2,1},{13,17,2,1},{0,18,1,1},{2,18,2,1},{7,18,2,1},{14,18,2,1}}}
T.glyphs[39069] = {w=18, advance=16, rects={{3,4,1,1},{3,5,2,1},{8,5,8,1},{0,6,8,1},{11,6,1,2},{0,7,2,1},{7,7,1,1},{2,8,2,1},{8,8,7,1},{2,9,5,1},{8,9,2,4},{14,9,1,6},{1,10,2,1},{5,10,2,1},{11,10,1,5},{0,11,6,1},{3,12,4,1},{2,13,2,1},{6,13,4,1},{0,14,7,1},{8,14,2,1},{1,15,2,2},{6,15,1,2},{10,15,3,1},{10,16,4,1},{1,17,6,1},{8,17,3,1},{13,17,2,1},{1,18,2,1},{6,18,3,1},{14,18,2,1}}}
T.glyphs[39128] = {w=18, advance=16, rects={{0,4,14,1},{3,5,1,1},{5,5,1,1},{8,5,2,1},{13,5,1,1},{1,6,10,1},{12,6,2,3},{1,7,1,2},{3,7,1,2},{5,7,1,2},{7,7,4,2},{1,9,11,1},{13,9,1,4},{8,10,2,3},{11,10,1,3},{1,11,6,1},{1,13,8,1},{10,13,4,1},{2,14,1,1},{4,14,1,3},{6,14,1,2},{8,14,1,1},{10,14,1,1},{12,14,2,2},{1,15,1,1},{8,15,3,1},{15,15,1,1},{0,16,1,1},{7,16,3,1},{12,16,4,1},{2,17,3,1},{8,17,1,1},{14,17,2,1}}}
T.glyphs[39134] = {w=18, advance=16, rects={{0,5,9,1},{8,6,1,2},{13,6,1,1},{11,7,3,1},{8,8,4,1},{8,9,3,1},{8,10,4,1},{8,11,1,1},{11,11,3,1},{8,12,2,3},{13,12,2,1},{9,15,1,1},{14,15,2,2},{9,16,2,1},{10,17,5,1},{11,18,4,1}}}
T.glyphs[39135] = {w=18, advance=16, rects={{7,4,2,1},{6,5,4,1},{4,6,2,1},{7,6,1,1},{10,6,2,1},{3,7,2,1},{7,7,2,1},{11,7,3,1},{1,8,15,1},{1,9,1,1},{3,9,1,2},{11,9,2,2},{3,11,10,1},{3,12,1,1},{11,12,2,1},{3,13,10,1},{3,14,1,3},{6,14,1,1},{12,14,2,1},{6,15,7,1},{7,16,5,1},{3,17,5,1},{11,17,3,1},{3,18,2,1},{13,18,1,1}}}
T.glyphs[39281] = {w=18, advance=16, rects={{2,4,1,2},{8,4,1,1},{7,5,2,1},{1,6,5,1},{7,6,8,1},{1,7,1,1},{4,7,4,1},{13,7,2,6},{0,8,2,1},{4,8,3,1},{0,9,1,1},{2,9,10,1},{2,10,1,6},{6,10,2,2},{10,10,2,2},{6,12,6,1},{6,13,2,4},{13,13,1,1},{10,14,4,1},{15,14,1,1},{4,15,1,1},{14,15,2,2},{2,16,3,1},{2,17,1,1},{7,17,8,1}}}
T.glyphs[39286] = {w=18, advance=16, rects={{2,4,1,2},{8,4,1,2},{13,5,2,1},{1,6,5,1},{8,6,6,1},{1,7,1,1},{4,7,2,1},{7,7,4,1},{12,7,2,1},{0,8,2,1},{4,8,1,1},{6,8,2,1},{9,8,4,1},{14,8,2,2},{0,9,1,1},{2,9,3,1},{8,9,5,1},{2,10,1,5},{6,10,3,1},{12,10,3,1},{6,12,9,1},{8,13,1,2},{11,13,2,4},{14,14,2,3},{2,15,3,1},{7,15,2,1},{2,16,2,1},{7,16,1,1},{2,17,1,1},{6,17,2,1},{11,17,4,1},{5,18,1,1}}}
T.glyphs[39304] = {w=18, advance=16, rects={{2,4,1,2},{10,4,1,1},{6,5,9,1},{1,6,6,1},{10,6,1,1},{14,6,1,1},{1,7,1,2},{4,7,1,3},{6,7,9,1},{6,8,1,1},{10,8,1,2},{14,8,1,1},{0,9,2,1},{0,10,1,1},{2,10,1,6},{5,10,11,1},{6,12,9,1},{6,13,1,3},{10,13,1,2},{14,13,1,3},{4,15,1,1},{9,15,2,1},{2,16,3,1},{8,16,5,1},{2,17,2,1},{7,17,2,1},{12,17,2,1},{5,18,2,1},{14,18,1,1}}}
T.glyphs[39318] = {w=18, advance=16, rects={{4,3,2,1},{10,3,2,1},{5,4,1,1},{10,4,1,1},{0,5,16,1},{7,6,1,2},{2,8,12,1},{2,9,2,2},{12,9,2,1},{13,10,1,1},{2,11,12,1},{2,12,2,1},{13,12,1,1},{2,13,12,1},{2,14,2,2},{13,14,1,2},{2,16,12,1},{2,17,2,1},{12,17,2,1}}}
T.glyphs[39537] = {w=18, advance=16, rects={{0,5,6,1},{7,5,9,1},{4,6,2,2},{7,6,2,1},{1,7,2,1},{7,7,3,1},{13,7,1,2},{1,8,1,4},{4,8,1,4},{7,8,4,1},{7,9,2,6},{10,9,1,1},{12,9,2,1},{10,10,3,1},{11,11,2,2},{1,12,5,1},{5,13,1,1},{10,13,3,1},{3,14,3,1},{10,14,1,1},{12,14,2,1},{1,15,3,1},{5,15,1,2},{7,15,4,1},{13,15,2,2},{0,16,2,1},{7,16,3,1},{4,17,2,1},{7,17,2,1},{1,18,5,1},{7,18,9,1}}}
T.glyphs[39547] = {w=18, advance=16, rects={{10,4,1,1},{0,5,6,1},{10,5,2,1},{5,6,1,3},{11,6,1,1},{1,7,2,3},{7,7,9,1},{10,8,2,1},{4,9,2,2},{11,9,1,3},{1,10,1,1},{1,11,6,1},{5,12,10,1},{5,13,2,1},{10,13,2,1},{3,14,4,1},{11,14,1,3},{1,15,3,1},{5,15,2,2},{0,16,2,1},{5,17,11,1},{2,18,4,1}}}
T.glyphs[39564] = {w=18, advance=16, rects={{10,4,1,1},{0,5,5,1},{9,5,3,1},{4,6,1,5},{9,6,1,1},{11,6,1,1},{1,7,1,4},{8,7,2,1},{12,7,1,1},{7,8,2,1},{12,8,2,1},{6,9,2,1},{13,9,2,1},{6,10,10,1},{1,11,5,1},{4,12,2,2},{7,12,1,2},{9,12,2,1},{13,12,2,1},{10,13,1,3},{13,13,1,2},{1,14,5,1},{7,14,2,2},{0,15,2,1},{4,15,2,3},{12,15,2,1},{8,16,1,1},{12,16,1,2},{1,18,4,1},{6,18,10,1}}}
T.glyphs[39592] = {w=18, advance=16, rects={{3,4,10,1},{3,5,1,1},{12,5,1,4},{3,6,6,1},{3,7,1,2},{8,7,1,2},{1,9,14,1},{1,10,1,1},{14,10,1,1},{3,11,10,1},{3,12,1,1},{12,12,1,1},{3,13,10,1},{3,14,1,1},{12,14,1,1},{3,15,10,1},{3,16,1,3},{12,16,1,2},{9,18,4,1}}}
T.glyphs[39607] = {w=18, advance=16, rects={{1,4,6,1},{11,4,2,3},{1,5,2,1},{6,5,1,3},{1,6,4,1},{1,7,2,1},{4,7,1,1},{8,7,8,1},{0,8,8,1},{11,8,2,3},{0,9,2,1},{7,9,1,1},{2,10,5,1},{2,11,1,1},{6,11,1,1},{9,11,6,1},{2,12,5,1},{9,12,1,4},{14,12,1,4},{2,13,1,1},{6,13,1,1},{2,14,5,1},{2,15,1,3},{6,15,1,2},{9,16,6,1},{4,17,3,1},{9,17,1,1},{14,17,1,1}}}
T.glyphs[39621] = {w=18, advance=16, rects={{1,4,6,1},{11,4,1,4},{1,5,1,1},{5,5,2,3},{8,5,1,1},{13,5,2,1},{1,6,3,1},{8,6,2,1},{13,6,1,1},{1,7,1,1},{3,7,1,1},{0,8,16,1},{0,9,1,1},{6,9,1,1},{8,9,5,1},{1,10,9,1},{11,10,1,2},{13,10,2,1},{1,11,5,1},{7,11,2,1},{14,11,2,1},{1,12,2,1},{5,12,1,1},{10,12,1,1},{1,13,5,1},{7,13,9,1},{1,14,2,4},{5,14,1,3},{8,14,2,1},{12,14,2,1},{8,15,5,1},{9,16,5,1},{4,17,2,1},{7,17,3,1},{13,17,2,1}}}
T.glyphs[39640] = {w=18, advance=16, rects={{7,4,2,1},{0,5,16,1},{3,7,10,1},{3,8,1,1},{12,8,1,1},{3,9,10,1},{1,11,14,1},{1,12,2,6},{14,12,1,4},{4,13,8,1},{4,14,2,1},{10,14,2,1},{4,15,8,1},{4,16,2,1},{13,16,2,1},{11,17,4,1}}}
T.glyphs[39746] = {w=18, advance=16, rects={{9,4,1,2},{1,6,4,1},{6,6,9,1},{6,7,1,2},{10,7,1,2},{13,7,2,2},{0,9,15,1},{2,10,1,2},{6,10,1,2},{10,10,1,1},{13,10,2,2},{4,11,1,3},{9,11,2,1},{1,12,2,1},{6,12,9,1},{1,13,1,1},{9,13,2,1},{12,13,1,1},{1,14,5,1},{8,14,1,1},{10,14,4,1},{0,15,3,1},{4,15,2,1},{7,15,2,1},{10,15,6,1},{5,16,2,1},{10,16,1,1},{14,16,2,1},{4,17,2,1},{10,17,5,1}}}
T.glyphs[40644] = {w=18, advance=16, rects={{5,4,1,1},{10,4,1,1},{1,5,14,1},{5,6,1,2},{10,6,2,1},{10,7,1,1},{0,8,16,1},{7,9,2,1},{2,10,12,1},{2,11,2,1},{7,11,2,1},{12,11,2,1},{2,12,12,1},{2,13,2,1},{7,13,2,1},{12,13,2,1},{2,14,12,1},{2,15,2,1},{12,15,2,1},{5,16,1,1},{9,16,3,1},{2,17,3,1},{11,17,4,1},{1,18,2,1},{13,18,2,1}}}
T.glyphs[40657] = {w=18, advance=16, rects={{2,5,12,1},{2,6,1,3},{7,6,2,3},{13,6,1,3},{4,7,2,1},{10,7,2,1},{5,8,1,1},{10,8,1,1},{2,9,12,1},{7,10,2,1},{1,11,14,1},{7,12,2,2},{0,14,16,1},{2,16,1,1},{5,16,1,1},{9,16,1,2},{12,16,2,1},{1,17,2,1},{5,17,2,1},{13,17,2,1},{1,18,1,1},{6,18,1,1},{9,18,2,1},{14,18,1,1}}}
T.glyphs[40664] = {w=18, advance=16, rects={{11,4,1,5},{1,5,7,1},{13,5,1,1},{1,6,1,1},{4,6,1,1},{7,6,1,3},{13,6,2,1},{1,7,2,1},{4,7,2,1},{14,7,1,1},{1,8,1,1},{4,8,1,1},{1,9,15,1},{4,10,1,2},{11,10,1,1},{10,11,2,1},{1,12,7,1},{10,12,3,2},{4,13,1,1},{7,13,1,1},{0,14,8,1},{10,14,1,1},{12,14,1,1},{5,15,3,1},{9,15,2,1},{12,15,2,1},{1,16,1,2},{3,16,1,2},{5,16,1,2},{7,16,1,1},{9,16,1,1},{13,16,1,1},{8,17,2,1},{13,17,2,1},{0,18,2,1},{7,18,2,1},{14,18,1,1}}}
T.glyphs[40736] = {w=18, advance=16, rects={{4,4,3,1},{1,5,4,1},{8,5,6,1},{1,6,2,1},{12,6,2,1},{1,7,6,1},{8,7,6,1},{1,8,2,2},{12,8,2,2},{1,10,13,1},{1,12,4,1},{7,12,1,6},{9,12,1,1},{12,12,1,4},{1,13,2,1},{5,13,1,1},{10,13,1,1},{1,14,4,1},{9,14,1,1},{1,15,2,3},{5,15,1,1},{10,15,1,1},{15,15,1,1},{12,16,4,2},{4,17,2,1},{9,17,2,1},{1,18,4,1},{6,18,4,1},{13,18,3,1}}}
T.glyphs[40763] = {w=18, advance=16, rects={{7,4,1,1},{3,5,10,1},{3,6,1,1},{12,6,1,1},{3,7,10,1},{3,8,1,1},{12,8,1,1},{3,9,10,1},{2,11,12,1},{2,12,1,1},{7,12,2,1},{13,12,1,1},{2,13,12,1},{2,14,1,1},{7,14,2,1},{13,14,1,1},{0,15,16,1},{4,16,2,1},{11,16,1,3},{3,17,2,1},{1,18,3,1}}}
T.glyphs[40784] = {w=18, advance=16, rects={{7,4,1,1},{7,5,2,1},{1,6,15,1},{3,7,2,1},{11,7,2,1},{4,8,2,1},{10,8,2,1},{5,9,2,1},{8,9,3,1},{6,10,4,1},{3,11,4,1},{8,11,5,1},{1,12,3,1},{12,12,3,1},{4,13,2,2},{10,13,2,6},{4,15,1,1},{3,16,2,1},{2,17,2,1},{1,18,2,1}}}
T.glyphs[40831] = {w=18, advance=16, rects={{8,3,1,2},{3,4,1,4},{8,5,7,1},{8,6,1,2},{0,8,16,1},{2,10,1,5},{13,10,2,7},{7,11,2,2},{6,13,4,1},{4,14,3,1},{9,14,3,1},{2,15,3,1},{11,15,1,1},{2,16,1,1},{2,17,13,1},{13,18,2,1}}}
T.glyphs[40857] = {w=18, advance=16, rects={{5,4,2,3},{10,4,1,1},{10,5,2,1},{11,6,2,1},{0,7,16,1},{5,8,2,1},{8,8,2,4},{5,9,1,2},{13,9,1,1},{12,10,2,1},{4,11,2,3},{11,11,2,1},{8,12,4,1},{8,13,3,1},{14,13,2,3},{3,14,2,2},{7,14,3,1},{6,15,4,1},{2,16,2,1},{5,16,2,1},{8,16,2,1},{14,16,1,1},{1,17,2,1},{9,17,6,1},{0,18,2,1}}}
T.glyphs[65281] = {w=18, advance=16, rects={{3,5,2,8},{3,15,2,2}}}
T.glyphs[65288] = {w=18, advance=16, rects={{13,5,1,1},{12,6,2,1},{11,7,2,2},{11,9,1,1},{10,10,2,5},{11,15,1,1},{11,16,2,2},{12,18,2,1},{13,19,1,1}}}
T.glyphs[65289] = {w=18, advance=16, rects={{2,5,1,1},{2,6,2,1},{3,7,2,2},{4,9,1,1},{4,10,2,5},{4,15,1,1},{3,16,2,2},{2,18,2,1},{2,19,1,1}}}
T.glyphs[65292] = {w=18, advance=16, rects={{3,15,2,1},{3,16,1,2},{2,18,2,1}}}
T.glyphs[65306] = {w=18, advance=16, rects={{3,8,2,2},{3,15,2,2}}}
T.glyphs[65307] = {w=18, advance=16, rects={{3,8,2,2},{3,15,2,1},{3,16,1,2},{2,18,2,1}}}
T.glyphs[65311] = {w=18, advance=16, rects={{2,5,4,1},{1,6,2,1},{4,6,3,1},{6,7,2,2},{5,9,2,1},{4,10,2,1},{3,11,2,2},{3,13,1,1},{3,15,2,2}}}
return T

end)()

__modules['default_import_file/workspace/sans-fight/lua/config'] = (function()
-- config.lua —— 与「当前千星工程」绑定的环境配置（模板索引 / 图片资产 / 更新回调 / 设备分流）。
--
-- 改动本文件后必须重建存档才会进到脚本里：  node tools/build-save.mjs
--
-- 注意：模板索引**不是跨工程通用的**。新建/换一个工程、或重新排布客户端控件之后，
-- 都要对着编辑器里的实际索引重填一遍。默认值写在 lua/main.lua 的 G / G_REAL / IMAGE_ID，
-- 这里留 nil 就沿用默认值（默认已经把「用户确认的模板索引」和「交接包实测索引」两套都列进候选）。
local C = {}

-- 更新回调：官方推荐 'level' —— 只走 OnLevelUpdate，和「关卡暂停」一致。
-- 只有当外部宿主**只**调用 OnUpdate（不调 OnLevelUpdate）时才改成 'ui'，否则战斗完全不推进。
-- 注意：两个回调都推进是错的，会让每帧跑两遍（速度翻倍、双倍伤害）。
C.updateCallback = 'level'

-- 设备分流：'auto' 读 game.GetDevice()；'keyboard' / 'touch' 可强制某一分支（真机调试用）。
C.device = 'auto'

-- 键位诊断（默认关）：true 时把 Enum.KeyEventType 里所有事件都挂上「按到就打印」的监听。
-- 真机上不确定某个物理键对应哪个事件名时打开它：按一下键，日志里会打 main: [keyDiag] <事件名>。
-- 查完记得改回 false（只用于诊断，会额外挂一百多个监听）。
C.keyDiag = false

-- 文字渲染方式：
--   'art'     = 用 lua/textart.lua 的矩形字形自绘（**默认**；原生文本框在真机渲染不出字形，
--               写入/尺寸/对齐都验证过是对的，所以绕开它）
--   'control' = 强行用原生文本框（只有想在模拟器里对照时才切）
C.textMode = 'art'

-- 结算 / 计时相关信号（服务端节点图用）
--   C.startSignal      ：进入战斗时客户端广播的信号名 —— 服务端收到它就开始计 120 秒
--   （ESC 不发任何信号：时间未到自行退出 = 系统的"未完成"，由系统记录，不需要客户端处理）
-- 开局信号：进入关卡（脚本 OnStart）时**只发一次**，之后重开 / 重选难度 / 换回合都不再发。
-- 留空字符串 = 不发送；想换名字就改这里的字符串（服务端「信号配置」里要同名声明）。
C.startSignal = 'SansFightStart'

-- 服务端变量探针（诊断用）：客户端每 2 秒读一次这些 **Level 自定义变量**，
-- 值一变就打一行日志 —— 用来判断"你的服务端节点图跑到了哪一步"。
--   例：[var] SettleReady=false → true（= 计时器跑完了）
--       [var] SansSettled=true（= 收到结算信号并去重了）
--   打不出来 / 打 ? → 变量没声明或名字不对 → 节点图没跑到那一步
-- 【2026-10-09 用户口径】加上你自己建的自定义变量 'test'（你的节点图触发时才会写出来）：
--   日志里出现 main: [var] test = xxx  ⇒ 你的图跑到了写它的那一步；
--   一直是 ?（读不到/未声明） ⇒ 要么变量没声明成 Level，要么那一步没执行。
C.probeVars = { 'test', 'SettleReady', 'SansSettled' }

-- Sans 水平修正（世界像素，正数 = 右移）：真机截图量出整只 Sans 比屏幕中轴偏左约 26px，
-- 这里补回来。若以后觉得过头/不够，直接改这个数（0 = 不修正）。
C.sansXOffset = 26

-- 文本渲染「隔离探针」（默认关）：true 时**不画战斗内容**，只画
--   ① 白色参照矩形  ② 画布里手放的文本框 TextProbe（脚本一个字都不写）  ③ 脚本实例化+写入的 4 个文本框。
-- 用来回答"这台机器到底能不能渲染原生文本框"，排除战斗/池清理/黑底/闪层的干扰。查完记得改回 false。
C.textProbe = false

-- 模板试错顺序：'sim' = 先试模拟器模板（离线自测/模拟器试玩页命中；真机对这些索引返回 nil，
-- 会自动接着试真机索引）；'real' = 先试真机模板。
C.templatesFirst = 'sim'
-- 是否允许回退到模拟器 GUID。模拟器/离线自测需要 true；纯真机工程可以改 false。
C.legacyTemplateFallback = true

-- 覆盖单个图元的模板索引（留 nil = 用 lua/main.lua 里的候选列表）。
-- 例子：C.templates = { rect = 1073741865, circle = 1073741871, ring = 1073741875,
--                      rot = 1073741877, rtri = 1073741879, text = 1073741867,
--                      cursor = 1073741860, baked = 1073741862, bakedC = 1073741862,
--                      bakedRoot = 1073741862 }
C.templates = nil

-- 图片资产 ID：留 nil / 0 = **沿用模板自带的图片**（真机推荐）。
-- 只有确认了当前工程里真实存在的图片资产 ID，才在这里填正整数；模拟器的 100001..100006
-- 是**内置图元编号**，真机没有对应资产，填进去会把图元刷成空白。
-- 例子：C.images = { rect = 100001, circle = 100002, ring = 100006, rot = 100001, rtri = 100003 }
C.images = nil

return C


end)()

__modules['default_import_file/workspace/sans-fight/lua/main'] = (function()
-- main.lua —— 「审判者战」千星客户端控件 + Lua 适配层
--
-- 职责边界：
--   * 本文件负责「渲染适配 + 输入 + 生命周期」：把逻辑层输出的实体列表画成客户端控件。
--   * 逻辑层在 lua/core.lua（纯 Lua，无模拟器 API）；本文件通过 require 加载，缺失时退回内置演示。
--
-- 坐标系：逻辑层与世界一律用原作 640×480、Y 向下；本层按画布尺寸等比居中放大。
-- 图元：模拟器提供 6 种图元（100001 rect / 100002 circle / 100003 triangle /
--       100004 fourstar / 100005 fivestar / 100006 ring），骨头/龙骨炮/灵魂/战斗框全部由它们拼出。
--       本项目实际只取用 rect / circle / triangle / ring 四种（fourstar 没用到，故不留模板）。
--
-- 模板池 guid（见 tools/build-save.mjs 与 docs/prefab-pool.md，共 7 个）：
--   rect 1073743001  circle 1073743002  text 1073743004  ring 1073743006
--   rot  1073743007  rtri   1073743008  cursor 1073743009
--
-- 本文件是模块：由挂载脚本 lua/boot.lua 通过 require 加载并转发生命周期函数。

local M = {}

-- 构建标记：每次改动本层就换一个，日志里一眼能看出试玩跑的是不是最新代码
-- （踩过：改了 main.lua、重建存档、重新 load，但试玩 Worker 仍在跑上一版，白查半天）
local BUILD = '2026-10-11-bone-knob'   -- 心形重画/按钮框恢复(帧末置顶)/stopAttack幂等/确认键去抖/lifecycle+变量探针   -- 等距选项UI / 三项结局(含重选难度) / 橙骨 / 开局信号 / ESC请求结算 / result=Bool

-- 【2026-10-13 用户口径】选项上那颗灵魂（心）相对按钮中线的**下移量**（px）：
--   选中标记原版贴在按钮内左侧 16px、垂直居中；这里整体下移几像素，视觉上更贴文字基线。
M.MENU_HEART_DY = 3

local G = {
  -- 模拟器内部模板 GUID
  rect = 1073743001, circle = 1073743002, text = 1073743004,
  ring = 1073743006, rot = 1073743007, rtri = 1073743008,
  cursor = 1073743009, baked = 1073743100, bakedC = 1073743101, bakedRoot = 1073743102,
}

-- 真机（千星编辑器）模板：**每个工程的索引都不一样**，所以放「候选列表」逐个试，
-- 拿到 nil（模板池里没有这个索引）就试下一个。容器节点永远垫底 —— 拿到容器再钻进去找叶子。
--   候选 1 = 用户在编辑器里确认的「客户端控件模板」索引
--            （矩形 1865 / 圆形 1871 / 圆环 1875 / 旋转图元 1877 / 旋转三角形 1879
--              / 文本框 1867 / 光标 1860 / 容器节点 1862）
--   候选 2 = 交接包 BadTime-Miliastra-Handoff 实测可用的「挂载后实例」索引
--            （1887 / 1889 / 1890 / 1891 / 1888 / 1886 / 1885 / 容器 1884）
-- 想固定成一套：在 lua/config.lua 的 C.templates 里写死（改完要重建存档）。
local G_REAL = {
  rect = { 1073741865, 1073741887 }, circle = { 1073741871, 1073741889 },
  ring = { 1073741875, 1073741890 }, rot = { 1073741877, 1073741891 },
  rtri = { 1073741879, 1073741888 }, text = { 1073741867, 1073741886 },
  cursor = { 1073741860, 1073741885 },
  baked = { 1073741862, 1073741884 }, bakedC = { 1073741862, 1073741884 },
  bakedRoot = { 1073741862, 1073741884 },
  bakedFallback = { 1073741862, 1073741884 },
}

-- 图片资产 ID：**0 = 沿用模板自带的图片**。真机的图元模板本来就带图案，模拟器模板池里也写了
-- imageId；交接包在真机上写死 100001 是**模拟器的内置图元编号**，真机没有这个资产 → 会把图元
-- 刷成空白。所以默认 0、不调 SetImage；只有确认了当前工程真实的图片资产 ID 才在 config.lua 里填。
local IMAGE_ID = { rect = 0, circle = 0, ring = 0, rot = 0, rtri = 0, text = 0 }

-- 环境配置：模板索引 / 图片资产 / 更新回调 / 设备。优先读 lua/config.lua（交接包里叫 C），
-- 读不到就用下面的默认值 —— 模拟器与离线自测的行为因此完全不变。
G_REAL.cfg = {
  updateCallback = 'level',        -- 官方推荐 'level'（OnLevelUpdate）；外部宿主只调 OnUpdate 时改 'ui'
  templatesFirst = 'sim',          -- 先试模拟器模板；真机模板探测失败的工程可改 'real'
  legacyTemplateFallback = true,   -- 是否允许回退到模拟器 GUID
  templates = nil, images = nil,
}
do
  local ok, mod = pcall(require, 'default_import_file/workspace/sans-fight/lua/config')
  if not (ok and type(mod) == 'table') then ok, mod = pcall(require, 'lua' .. '.config') end
  if ok and type(mod) == 'table' then
    for k, v in pairs(mod) do G_REAL.cfg[k] = v end
  end
  if type(G_REAL.cfg.templates) == 'table' then
    for k, v in pairs(G_REAL.cfg.templates) do G_REAL[k] = v end
  end
  if type(G_REAL.cfg.images) == 'table' then
    for k, v in pairs(G_REAL.cfg.images) do IMAGE_ID[k] = v end
  end
end

-- 枚举取值：真机的 AddKeyEventListener / AddCursorEventListener / horizontalAlignment 都要求
-- **枚举项**（KeyEventType / CursorEventType / TextHorizontalAlignment），不吃字符串；
-- 而模拟器与离线测试台吃字符串（试玩页注入的也是字符串）。所以统一走「先字符串、抛错再枚举」。
function G_REAL.enumValue(group, name)
  if name == nil then return nil end
  local ok, v = pcall(function() return Enum[group][name] end)
  if ok and v ~= nil then return v end
  return nil
end

-- 颜色统一走 Color(r,g,b,a)：真机要求 ColorValue（整数直接写 imageColor/fontColor 不生效），
-- 模拟器的 Color 返回同一个 ARGB 打包整数（语义一致），宿主没有 Color 时原样返回整数（离线自测）。
G_REAL.colorCache = {}
function G_REAL.apiColor(v)
  if type(v) ~= 'number' then return v end
  local hit = G_REAL.colorCache[v]
  if hit ~= nil then return hit end
  local a = math.floor(v / 16777216) % 256
  local r = math.floor(v / 65536) % 256
  local g = math.floor(v / 256) % 256
  local b = v % 256
  local ok, c = pcall(Color, r, g, b, a)
  if not ok or c == nil then G_REAL.colorCache[v] = v; return v end
  G_REAL.colorCache[v] = c
  return c
end

function G_REAL.activate(c)
  if c == nil then return end
  pcall(function() c:SetActive(true) end)
  pcall(function() c:SetVisible(true) end)
end

-- 原件配色：白 0 / 蓝 1 / 橙 2（与 BTS 攻击脚本 Color 字段一致）
local BONE_COLORS = { 0xFFFFFFFF, 0xFF2F6BFF, 0xFFFF7A18 }
local C_WHITE, C_RED, C_BLUE, C_DIM = 0xFFFFFFFF, 0xFFFF2B2B, 0xFF63B0FF, 0xFFB9C6D8
local C_BOX, C_HP = 0xFFFFFFFF, 0xFFFFD200

-- 骷髅炮 / 审判者（sans 本人）的配色：两者都是「用图元拼出来的复合外观」，见下面 drawBlaster / drawSans。
-- 取值口径：颅骨与光束纯白（原作就是白），外套取偏蓝的深灰（原作 sans 的连帽衫），
-- 眼窝近黑、BlueEye 亮蓝 + 更暗的半透明外圈，汗滴浅蓝。
-- 【2026-10-06 清理】旧参数化 Sans / 6 矩形龙骨炮的配色常量已随旧模型一起删除；
-- 现在龙骨炮与 Sans 本体都走 lua/fitdata.lua 的 exact 逐像素烘焙容器，自带原图颜色。
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

-- 控件池预算（OnStart 预热，保证 z 序稳定；不足时按需追加）。
--
-- 测量方法（快测版）：`node tools/run-lua.mjs lua/_probe_pool2.lua` —— _pool.lua 的单场景加速版，
-- 只跑 PC/original 一趟、逐帧统计「帧末可见控件数」，并**排除烘焙容器子控件**（它们直接挂在容器下，
-- 不占池槽位）。O(1) 可见计数器替代原版的每帧全表扫描，整趟从 ~40min 降到 ~3min。
--
-- 【2026-10-06 全流程龙骨炮烘焙（fitdata.blaster_block2）后实测】
--     kind     峰值    出现在                                            本预算
--     rot      1221    round23 final 阶段④ 旋转光束（9 发同屏 × 129 件）   1350
--     circle    164    round9 platforms4hard（骨头两端骨球）               443
--     rect       48    round0 sans_intro                                 200
--     rtri 4 / ring 0（PC 场景，触摸另有 1）/ text 12 / cursor 1
--
--   ★ 关键结论：像素烘焙龙骨炮走 main.rrect() → **rot 池**，不是 rect 池。
--     每发 = block2 的 112~126 个 rrect + 光束 2 + 炮口亮块 1 ≈ 129 件；
--     所以「全流程烘焙」（见面杀 + 22 个回合 + 终盘）后的 rot 峰值分布是：
--       见面杀 4 发 ≈ 517 / 普通回合 multi2 4 发 ≈ 516 / 终盘阶段④ 9 发 ≈ 1221。
--     历史遗留：上一轮把预算加在 rect 上（误以为烘焙走 rect 池），实测 rect 峰值只有 48，
--     这一轮把那 440 个多余槽位还给了真正吃紧的 rot。
--
--   为什么必须 ≥ 峰值：take() 取不到时会**当场实例化**一个新控件，而新控件按创建顺序排在
--   闪层**之后** → 它会画在全屏闪层之上（终盘阶段③的黑屏闪正好紧挨阶段④的旋转光束），
--   且整场会多出上千次运行期实例化。
local BUDGET = { rect = 200, circle = 443, rot = 1350, rtri = 4, ring = 2, text = 15, cursor = 1 }

local W, H = 640, 480          -- 逻辑世界尺寸
local root, flash, bgPanel, bgOver, bakedRoot = nil, nil, nil, nil, nil
local CW, CH, S, OX, OY = 1280, 720, 1.5, 160, 0

local pool, used, memo = {}, {}, {}
-- 沙箱生命周期簿记：自建控件与监听器都要留引用，OnDestroy 才能干净卸载（宿主 root 不销毁）。
-- holds：确认/取消是**多来源**动作，按来源记按住状态再聚合（见 bindKeys）。
local owned = { controls = {}, keys = {}, cursors = {}, started = false, enabled = true,
                holds = { confirm = {}, cancel = {} } }
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
local fit = nil                    -- lua/fitdata.lua：exact 逐像素烘焙表（缺失时走参数化回退）
local textart = nil                -- lua/textart.lua：矩形字形配方（原生文本框在真机渲不出字时用它）
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

-- 【2026-10-11 用户口径·固定摇杆】吸附区围绕**固定中心**（JOY_HOME = 原神预设位置）：
--   手指落在中心附近就抓住摇杆（不必精确点中圆），中心本身**永远不动**；可点 UI 仍然优先。
-- PC 分支根本不调用这个函数（鼠标不起摇杆，见 bindPointer）。
local function inJoyZone(wx, wy)
  return math.abs(wx - JOY_HOME_X) <= 120
     and math.abs((wy or JOY_HOME_Y) - JOY_HOME_Y) <= 150
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
  local ok, v = pcall(function() return game.GetGlobalCustomVariableValue('Level', 'SansRound') end)
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
  -- 调试用强制分支：config.lua 里 C.device = 'keyboard' / 'touch'（默认 'auto' 读设备）。
  local force = G_REAL.cfg.device
  if force == 'keyboard' then deviceName = 'forced-keyboard'; return false end
  if force == 'touch' then deviceName = 'forced-touch'; return true end
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
  local bw = cmd.w or 110
  local bh = cmd.h or 36
  -- 【方案 A2】core 给了显式 x 表（原版非等距 32/184/344/496）就用它，绘制/命中/触屏同一套公式
  if type(cmd.xs) == 'table' and cmd.xs[i] ~= nil then
    return cmd.xs[i], cmd.y, bw, bh
  end
  local gap = cmd.gap or 10
  return cmd.x + (i - 1) * (bw + gap), cmd.y, bw, bh
end

-- 【方案 A3】选中红心画在**按钮内部左侧 16px**、垂直居中（原版按钮贴图的 Heart 图像点 = 0.145455×110 ≈ 16px）
local function menuHeartRect(cmd, i)
  local bx, y, _, bh = menuButtonRect(cmd, i)
  -- 【2026-10-13】跟随 M.MENU_HEART_DY 下移，保证"点红心"仍然命中
  return bx + 7, y + bh / 2 - 9 + (M.MENU_HEART_DY or 0), 20, 18
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

-- 键盘监听：字符串键名先试（模拟器 / 离线测试台），真机会抛
--   bad argument #2 to 'AddKeyEventListener' (KeyEventType expected, got string)
-- → 再换成 Enum.KeyEventType.<name>。返回**真正生效的那个键**（供 RemoveKeyEventListener 用）。
function G_REAL.addKeyEvent(c, name, cb)
  if c == nil then return nil end
  if pcall(function() c:AddKeyEventListener(name, cb) end) then return name end
  local ev = G_REAL.enumValue('KeyEventType', name)
  if ev ~= nil and pcall(function() c:AddKeyEventListener(ev, cb) end) then return ev end
  return nil
end

-- 游标监听：同上（真机要 Enum.CursorEventType.*）
function G_REAL.addCursorEvent(c, name, cb)
  if c == nil then return nil end
  if pcall(function() c:AddCursorEventListener(name, cb) end) then return name end
  local ev = G_REAL.enumValue('CursorEventType', name)
  if ev ~= nil and pcall(function() c:AddCursorEventListener(ev, cb) end) then return ev end
  return nil
end

-- 水平对齐：真机要 Enum.TextHorizontalAlignment.*（写字符串会抛
--   bad argument #2 to 'horizontalAlignment' (TextHorizontalAlignment expected, got string)）。
-- 只在**第一次**探测一次，之后按结果固定走一条（避免每帧都在 pcall 里白抛一次）。
function G_REAL.setAlign(c, align)
  if c == nil or align == nil then return end
  if G_REAL.alignMode ~= 'enum' then
    if pcall(function() c.horizontalAlignment = align end) then
      G_REAL.alignMode = 'string'
      return
    end
    G_REAL.alignMode = 'enum'
  end
  local ev = G_REAL.enumValue('TextHorizontalAlignment', align)
  if ev ~= nil then pcall(function() c.horizontalAlignment = ev end) end
end

function G_REAL.isKindControl(c, kind)
  if not c then return false end
  -- 【真机修正】**不能**用 c.prefabIndex == 模板索引 判类型：模板本身可能是「容器 + 叶子」包装，
  -- 父层与叶子的 prefabIndex 都是那个索引 —— 用它短路，unwrapTemplate 就永远钻不进叶子，
  -- 真机上只能拿到空容器（表现：屏幕全黑 / 只有一张空图）。类型只认叶子接口。
  local n = G_REAL.controlName(c)
  if kind == 'rect' then
    return G_REAL.nameHasAny(n, '矩形') or c.SetImage ~= nil
  elseif kind == 'circle' then
    return G_REAL.nameHasAny(n, '圆形') or c.SetImage ~= nil
  elseif kind == 'ring' then
    return G_REAL.nameHasAny(n, '圆环') or c.SetImage ~= nil
  elseif kind == 'rot' then
    return G_REAL.nameHasAny(n, '旋转图元', '旋转矩形') or c.SetImage ~= nil
  elseif kind == 'rtri' then
    return G_REAL.nameHasAny(n, '旋转三角形', '三角形') or c.SetImage ~= nil
  elseif kind == 'text' then
    return G_REAL.nameHasAny(n, '文本') or c.text ~= nil
  elseif kind == 'cursor' then
    return G_REAL.nameHasAny(n, '光标') or c.AddCursorEventListener ~= nil
  end
  return false
end

function G_REAL.findKindChild(c, kind)
  local ok, children = pcall(function() return c:GetChildren() end)
  if not ok or type(children) ~= 'table' then return nil end
  for _, child in ipairs(children) do
    if G_REAL.isKindControl(child, kind) then return child end
    local nested = G_REAL.findKindChild(child, kind)
    if nested ~= nil then return nested end
  end
  return nil
end

-- 包装层拉伸归一化：真机模板的父容器默认可能是零尺寸/贴着角，不拉伸会把叶子裁没。
function G_REAL.stretchWrapper(c)
  if not c then return end
  pcall(function() c:SetAnchorMin(0, 0) end)
  pcall(function() c:SetAnchorMax(1, 1) end)
  pcall(function() c:SetPivot(0, 0) end)
  pcall(function() c:SetSizeDelta(0, 0) end)
  pcall(function() c:SetAnchoredPosition(0, 0) end)
  G_REAL.activate(c)
end

-- 控件属性调用统一包一层：**失败要出声**（之前全是静默 pcall，真机上锚点没生效也看不出来）。
function G_REAL.trySet(c, what, fn)
  local ok, err = pcall(fn)
  if not ok and not G_REAL.setFailLogged then
    G_REAL.setFailLogged = true
    print('main: 【警告】写 ' .. tostring(what) .. ' 失败 :: ' .. tostring(err)
      .. '  ← 把这条发给开发者（说明该属性在当前宿主不支持/名字不同）')
  end
  return ok
end

-- 几何回读（诊断用）：把宿主自己记的 anchor/pivot/pos/size 打一行。真机上属性是否真的写进去了，
-- 一眼就能看出来（读不到就打 ?）。
function G_REAL.dumpGeom(c, tag)
  if c == nil then print('main: geom[' .. tostring(tag) .. '] = nil') return end
  local function g(k)
    local ok, v = pcall(function() return c[k] end)
    if ok and v ~= nil then return tostring(v) end
    return '?'
  end
  print(string.format('main: geom[%s] anchor=(%s,%s)-(%s,%s) pivot=(%s,%s) pos=(%s,%s) size=(%s,%s)',
    tostring(tag), g('anchorMinX'), g('anchorMinY'), g('anchorMaxX'), g('anchorMaxY'),
    g('pivotX'), g('pivotY'), g('anchoredPositionX'), g('anchoredPositionY'),
    g('sizeDeltaX'), g('sizeDeltaY')))
end

-- 全屏件归一化：锚点 (0,0)-(1,1)、pivot 中心、尺寸差 0、位置 0（吃满父容器）。
function G_REAL.stretchFull(c)
  if c == nil then return nil end
  G_REAL.trySet(c, 'SetAnchorMin', function() c:SetAnchorMin(0, 0) end)
  G_REAL.trySet(c, 'SetAnchorMax', function() c:SetAnchorMax(1, 1) end)
  G_REAL.trySet(c, 'SetPivot', function() c:SetPivot(0.5, 0.5) end)
  G_REAL.trySet(c, 'SetSizeDelta', function() c:SetSizeDelta(0, 0) end)
  G_REAL.trySet(c, 'SetAnchoredPosition', function() c:SetAnchoredPosition(0, 0) end)
  return c
end

-- 叶子归一化：把模板自己的锚点/中心**强制**成我们绘制用的口径 —— 轴对齐件左下 (0,0)、
-- 旋转件与中心容器 (0.5,0.5)、全屏件（光标区/烘焙根）拉伸铺满。
--
-- 【2026-10-08 真机实证】必须**无条件**调用（不能只在「容器包装」分支里调用）：
-- 真机模板的 RectTransform 默认是 Unity 的「锚点=中心、pivot=0.5」，而 put()/putRot() 里
-- SetAnchoredPosition 用的是「锚点 + 左下角」语义。不归一化的后果（用户实测）：
--   * 黑底背景（3 倍画布、位置 (-CW,-CH)）被当成「中心在左下」→ 只有屏幕左下角一块是黑的；
--   * 所有以画布左下角为原点摆的图元整体偏移 → 看起来「原点跑到了屏幕中心」。
-- 交接包 another/lua/main.lua 的 instantiateTemplate 同样是无条件设 anchorMin/Max/Pivot/AnchoredPosition。
function G_REAL.normalizeLeaf(c, kind)
  if c == nil then return nil end
  -- 全屏件：光标检测区（吃满画布才有指针事件）、烘焙根（装绝对坐标子控件）
  if kind == 'cursor' or kind == 'bakedRoot' then return G_REAL.stretchFull(c) end
  local a = (kind == 'rot' or kind == 'rtri' or kind == 'bakedC') and 0.5 or 0
  G_REAL.trySet(c, 'SetAnchorMin', function() c:SetAnchorMin(a, a) end)
  G_REAL.trySet(c, 'SetAnchorMax', function() c:SetAnchorMax(a, a) end)
  G_REAL.trySet(c, 'SetPivot', function() c:SetPivot(a, a) end)
  G_REAL.trySet(c, 'SetAnchoredPosition', function() c:SetAnchoredPosition(0, 0) end)
  return c
end

-- 图片叶子：清掉羽化/遮罩/填充裁切。真机模板若开着这些，拉伸到全屏的「黑底」会被裁成一小块
-- 或边缘发虚（交接包文档明确要求：图片用基础完整显示、无软边、无遮罩、不使用填充裁切）。
function G_REAL.plainImage(c)
  if c == nil then return nil end
  -- 只写**官方可写字段**（模拟器 scene.js 的 KIND_RW.image）：
  --   imageColor / enableMask / enableSoftEdge / softEdge* / fill*（fillType 那一组）/ reverseMaskArea
  -- 注意 enableFill 与 imageType **不在**表里（真机写会报 cannot set），所以这里不碰。
  G_REAL.trySet(c, 'enableMask=false', function() c.enableMask = false end)
  G_REAL.trySet(c, 'enableSoftEdge=false', function() c.enableSoftEdge = false end)
  return c
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
        G_REAL.activate(child)
        if child ~= keep then G_REAL.stretchWrapper(child) end
      elseif child ~= keep then
        pcall(function() child:SetVisible(false) end)
      end
    end
    return containsKeep
  end
  visit(root)
end

local function unwrapTemplate(c, kind)
  if not c then return nil end
  if kind == 'baked' or kind == 'bakedC' or kind == 'bakedRoot' then return c end
  if G_REAL.isKindControl(c, kind) then return c end
  local child = G_REAL.findKindChild(c, kind)
  if child ~= nil then
    G_REAL.wrapperMode = true          -- 真机包装模板：启动预热要改按需创建，否则实例数爆炸
    G_REAL.isolateChild(c, child)
    G_REAL.stretchWrapper(c)
    return G_REAL.normalizeLeaf(child, kind)
  end
  -- 兼容旧编辑器：模板不报类型时退回第一个子控件（**只取不做包装判定**，避免误判真机模式）。
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
    local src = G_REAL.enumValue('ImageSource', 'StaticReference')
    if src == nil then pcall(function() src = Enum.ImageSource.StaticReference end) end
    local ok = pcall(function() c:SetImage(src, id) end)
    if not ok then pcall(function() c:SetImage(id) end) end
  end
  return c
end

-- 候选索引序列（去重、扁平化）。真机/模拟器两套索引都可能在，逐个试错 —— 不认识的索引
-- 只会让 InstantiateClientUIControl 返回 nil，不会污染结果。
function G_REAL.templateList(kind)
  local out, seen = {}, {}
  local function push(v)
    if v == nil then return end
    if type(v) == 'table' then for _, x in ipairs(v) do push(x) end return end
    if type(v) == 'number' and not seen[v] then seen[v] = true; out[#out + 1] = v end
  end
  local sim, real = G[kind], G_REAL[kind]
  if G_REAL.cfg.templatesFirst == 'real' then push(real); push(sim) else push(sim); push(real) end
  if G_REAL.cfg.legacyTemplateFallback == false then
    local only = {}
    for _, v in ipairs(out) do if v ~= sim then only[#only + 1] = v end end
    out = only
  end
  if kind ~= 'baked' and kind ~= 'bakedC' and kind ~= 'bakedRoot' then push(G_REAL.bakedFallback) end
  return out
end

local function instantiateTemplate(kind, parent)
  for _, guid in ipairs(G_REAL.templateList(kind)) do
    local ok, c = pcall(function() return game.InstantiateClientUIControl(guid, parent) end)
    if ok and c ~= nil then
      owned.controls[#owned.controls + 1] = c
      G_REAL.activate(c)                      -- 包装模板的父层也必须激活
      if guid ~= G[kind] then G_REAL.realTemplateMode = true end
      local outer = c
      c = unwrapTemplate(c, kind)
      if c ~= outer then G_REAL.stretchWrapper(outer) end
      G_REAL.activate(c)
      c = applyImageKind(c, kind)
      -- 【必须】无条件归一化锚点/pivot：真机的「直接模板」也要（不能只在容器包装分支里做）。
      c = G_REAL.normalizeLeaf(c, kind)
      if kind == 'rect' or kind == 'circle' or kind == 'ring' or kind == 'rot' or kind == 'rtri' then
        G_REAL.plainImage(c)
      end
      if kind == 'cursor' then
        G_REAL.stretchFull(c)                      -- 指针区必须吃满画布
        pcall(function() c.raycastTarget = true end)
      end
      if kind == 'text' then
        -- 文本框：底色透明 + 固定字号（不自动压缩字号）+ 顶对齐。
        -- 交接包文档要求「背景完全透明、固定字号、不启用自动压缩字号、无外框」——
        -- 真机上模板若开着自动压缩，长句会被压成小字/挤在一起，看起来就是「文本框不正常显示」。
        G_REAL.trySet(c, 'bgColor=透明', function() c.bgColor = G_REAL.apiColor(0x00000000) end)
        -- 【2026-10-08 按官方实现文档改】建议文本框开启自适应字号（配一个最小字号）：
        --   studio/docs/control-support.md 与 05-lua-implementation.md 都写明"建议 adaptiveFontSize = true，
        --   按可读性设置最小字号"。之前我们强制关掉，可能与引擎的排版裁剪路径不符（真机上一个字都不显示）。
        G_REAL.trySet(c, 'adaptiveFontSize=true', function() c.adaptiveFontSize = true end)
        local v = G_REAL.enumValue('TextVerticalAlignment', 'Top')
        if v ~= nil then G_REAL.trySet(c, 'verticalAlignment', function() c.verticalAlignment = v end) end
      end
      return c, nil
    end
  end
  return nil, '客户端模板缺失：' .. tostring(kind) .. ' 候选 ' ..
    table.concat(G_REAL.templateList(kind), '/') .. '；请核对 lua/config.lua 与客户端模板'
end

local instNILLogged = false     -- 模板缺失只打一次完整诊断，避免刷屏
G_REAL.wrapperMode = false          -- 真机使用容器包装模板时开启；避免启动批量预热造成卡死
G_REAL.realTemplateMode = false     -- 真机使用真实模板 GUID 时开启；真机不做 2015 控件预热

-- memo 的键用**控件对象本身**，不用 c.Id：真机控件的运行期身份是小写 id，c.Id 可能是 nil，
-- 用 nil 当键会让所有控件共用同一份 memo（尺寸/颜色互相串台）。
local function st(c)
  local m = memo[c]
  if not m then m = {}; memo[c] = m end
  return m
end

local function spawn(kind)
  local c, err = instantiateTemplate(kind, root)
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
  local list = poolOf(kind)
  local i = (used[kind] or 0) + 1
  used[kind] = i
  local c = list[i]
  if not c then
    c = spawn(kind)
    if not c then return nil end
    list[i] = c
  end
  local m = st(c)
  if m.vis ~= true then c:SetVisible(true); m.vis = true end
  return c
end

local function prewarm()
  for kind, n in pairs(BUDGET) do
    local list = poolOf(kind)
    for i = 1, n do
      list[i] = spawn(kind)
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
  local cv = G_REAL.apiColor(color)      -- 真机要 ColorValue；模拟器/离线自测原样返回整数
  if m.c ~= cv then c.imageColor = cv; m.c = cv end
end

local function spin(c, deg)
  local m = st(c)
  -- 【2026-10-05 修】运行时的签名是 SetLocalRotation(x, y, z)：只传一个参数会把角度写进 X 轴，
  -- Z（2D 真正用的那个）保持 0 → 旋转件其实**从来没转**过。斜/竖的龙骨炮光束因此被画成横的、
  -- 直接飞出画面（用户看到的「上下的龙骨炮丢失发射动画」）。
  if m.r ~= deg then c:SetLocalRotation(0, 0, deg); m.r = deg end
end

-- ---------------------------------------------------------------- 烘焙贴图（exact 逐像素）
-- 数据来自 lua/fitdata.lua（tools/fit-sprites.py 生成）：每个素材一个容器，
-- 子控件用**比例锚点**（anchorMin/Max = 矩形占比、sizeDelta=0）→ 父容器 SetSizeDelta
-- 就能整体缩放（不用真机未验证的 SetLocalScale）。容器在 bakedRoot 下，
-- bakedRoot 在 prewarm 之前创建 → 烘焙层天然在黑底之上、池控件之下。
local baked = {}                       -- key -> { name, spec, center, mirror, insts = { {c,vis,used,kids}, ... } }
local BAKED_MAX_INSTS = 12             -- 同一素材同时在场上限（龙骨炮实测峰值约 7-9 发）
local fitWarned = false

local function newBakedInstance(rec)
  local parent = rec.layer or bakedRoot or root
  local c, instErr = instantiateTemplate(rec.center and 'bakedC' or 'baked', parent)
  local ok = (c ~= nil)
  if not ok or c == nil then
    if not instNILLogged then instNILLogged = true; print('main: baked 容器缺失 :: ' .. tostring(instErr)) end
    return nil
  end
  madeTotal = madeTotal + 1
  c:SetVisible(false)
  local spec, mirror = rec.spec, rec.mirror
  local K = rec.k or (SANS_BAKE_SCALE * S)     -- 画布 px / 素材 px
  local kids, firstKid = 0, nil
  for i = 1, #spec.rects do
    local r = spec.rects[i]
    local k = instantiateTemplate('rect', c)
    if k then
      -- 【2026-10-08 真机第三轮】子块改用**绝对几何**：左下锚点 + pivot 0 + 绝对位置 + 绝对尺寸。
      -- 为什么不用「比例锚点 + sizeDelta 0」：真机对这个组合的支持不可靠（实测模型散成一堆细条），
      -- 而「锚点/pivot + SetAnchoredPosition + SetSizeDelta」正是画战斗框/HUD 用的同一套 API，
      -- 真机已证明可用。镜像也在这里一次算完（x 取反）。
      local bx = (mirror and (spec.w - r.x - r.w) or r.x) * K
      local by = (spec.h - r.y - r.h) * K
      G_REAL.trySet(k, 'child.SetAnchorMin', function() k:SetAnchorMin(0, 0) end)
      G_REAL.trySet(k, 'child.SetAnchorMax', function() k:SetAnchorMax(0, 0) end)
      G_REAL.trySet(k, 'child.SetPivot', function() k:SetPivot(0, 0) end)
      G_REAL.trySet(k, 'child.SetAnchoredPosition', function() k:SetAnchoredPosition(bx, by) end)
      G_REAL.trySet(k, 'child.SetSizeDelta', function() k:SetSizeDelta(r.w * K, r.h * K) end)
      k.imageColor = G_REAL.apiColor(r.c)
      k:SetVisible(true)
      kids = kids + 1
      if firstKid == nil then firstKid = k end
    end
  end
  local inst = { c = c, vis = false, used = -1, kids = kids }
  st(c).vis = false
  if #rec.insts == 0 then        -- 每种素材只在第一次创建时回读一次几何，真机排查用
    G_REAL.dumpGeom(c, 'baked:' .. tostring(rec.name))
    G_REAL.dumpGeom(firstKid, 'baked-child:' .. tostring(rec.name))
  end
  return inst
end

-- 取一个本帧还没用过的实例；没有就新建（每个实例一套独立子控件 → 可同时画多发龙骨炮）
local function bakeInstance(name, center, mirror, k, layer)
  if not fit or type(fit[name]) ~= 'table' then return nil end
  k = k or (SANS_BAKE_SCALE * S)
  -- 缓存键带上缩放与层：子块按绝对几何烤进去，换缩放/换层必须另烤一份
  local key = (mirror and (name .. '#m') or name) .. '@' .. string.format('%.4f', k)
    .. '@' .. tostring(layer == nil and '-' or 'L')
  local rec = baked[key]
  if not rec then
    rec = { name = name, spec = fit[name], center = center and true or false,
            mirror = mirror and true or false, k = k, layer = layer, insts = {} }
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
local function useBakedCorner(name, x, y, w, h, mirror, layer)
  local spec = fit and fit[name]
  local b = bakeInstance(name, false, mirror, spec and (w * S) / spec.w or nil, layer)
  if not b then return nil end
  b.used = frame
  if not b.vis then b.c:SetVisible(true); b.vis = true end
  put(b.c, wx(x), wyBottom(y + h), w * S, h * S)
  return b
end

-- 中心锚点：world 中心 (cx,cy)、宽高 w,h、旋转 deg
local function useBakedCenter(name, cx, cy, w, h, deg)
  local spec = fit and fit[name]
  local b = bakeInstance(name, true, false, spec and (w * S) / spec.w or nil)
  if not b then return nil end
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

-- UTF-8 逐码点拆分（不依赖 utf8 库：客户端沙箱不一定有）。非法序列按 '?' 处理。
local function utf8Codepoints(str)
  local out = {}
  local i, n = 1, #str
  while i <= n do
    local b = str:byte(i)
    local len = 1
    if b >= 0xF0 then len = 4 elseif b >= 0xE0 then len = 3 elseif b >= 0xC0 then len = 2 end
    local cp, ok = b, true
    if len == 1 then
      ok = (b < 0x80); cp = ok and b or 63
    else
      local mask = (len == 2) and 0x1F or ((len == 3) and 0x0F or 0x07)
      cp = b % (mask + 1)
      for k = 1, len - 1 do
        local nb = str:byte(i + k)
        if nb == nil or nb < 0x80 or nb > 0xBF then ok = false; break end
        cp = cp * 64 + (nb % 64)
      end
    end
    out[#out + 1] = ok and cp or 63
    i = i + len
  end
  return out
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
  if fs and m.fs ~= fs then
    c.fontSize = fs
    -- 自适应字号开启时，最小字号决定"缩到多小为止"：与目标字号同值 = 不缩，但走自适应排版路径
    pcall(function() c.minimumFontSize = fs end)
    m.fs = fs
  end
  if color then
    local fc = G_REAL.apiColor(color)
    if m.fc ~= fc then c.fontColor = fc; m.fc = fc end
  end
  if align and m.al ~= align then G_REAL.setAlign(c, align); m.al = align end
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
  -- 【CodeArt 文字 · 默认路径】原生文本框在真机上渲染不出字形（写入/几何都对，见
  -- docs/device-setup.md 与 Sans_Fight_文本框渲染_问题与方案.md），改用矩形字形：
  -- 每个字从 lua/textart.lua 取配方 → 注册成一张 fit 配方（按 码点+颜色 缓存）→ 用 useBakedCorner
  -- 烘成容器画出来（与 Sans/龙骨炮同一条烘焙路径）。字号基准 = textart 的 16px。
  if textart ~= nil and type(textart.glyphs) == 'table' and fit ~= nil
     and G_REAL.cfg.textMode ~= 'control' then
    local codes = utf8Codepoints(safeUtf8(tostring(s)))
    local chars, advance = {}, 0
    for ci = 1, #codes do
      local gl = textart.glyphs[codes[ci]] or textart.glyphs[63]
      if gl == nil then gl = { w = 8, advance = 8, rects = {} } end   -- 字库缺字：留空位不崩
      chars[#chars + 1] = { code = codes[ci], glyph = gl }
      advance = advance + (gl.advance or gl.w or 0)
    end
    local scale = size / 16
    if advance * scale > w and advance > 0 then scale = w / advance end
    local tx = x
    local al = tostring(align or 'Left')
    if al == 'Middle' or al == 'middle' then tx = x + (w - advance * scale) / 2
    elseif al == 'Right' or al == 'right' then tx = x + w - advance * scale end
    for ci = 1, #chars do
      local cd, gl = chars[ci].code, chars[ci].glyph
      if gl ~= nil and gl.rects ~= nil and #gl.rects > 0 then
        local name = 'glyph:' .. tostring(cd) .. ':' .. tostring(color)
        if fit[name] == nil then
          local spec = { w = gl.w, h = textart.height, rects = {} }
          for ri = 1, #gl.rects do
            local r = gl.rects[ri]
            spec.rects[#spec.rects + 1] = { x = r[1], y = r[2], w = r[3], h = r[4], c = color }
          end
          fit[name] = spec
        end
        -- 字形画进**独立的顶层容器**（见 OnStart 的 glyphLayer 与 draw() 末尾的置顶）：
        -- 否则字形烘在 bakedRoot（OnStart 最先建）里，会被后来按需创建的池矩形整体盖住 ——
        -- 真机上「子面板文字发灰、像叠在一起」就是这个原因。
        useBakedCorner(name, tx, y, gl.w * scale, textart.height * scale, false, G_REAL.glyphLayer)
      end
      tx = tx + (gl and (gl.advance or gl.w) or 0) * scale
    end
    if not G_REAL.artDiag then
      G_REAL.artDiag = true
      print('main: [diag] 文字走 CodeArt 矩形字形（textart height=' .. tostring(textart.height)
        .. '，字号基准 16）首帧样例="' .. safeUtf8(tostring(s)) .. '" size=' .. tostring(size) .. ' align=' .. al)
    end
    return
  end
  local c = take('text'); if not c then return nil end
  -- 【诊断】只在第一个文本框上打「写前 / 写后 / 期望」三行 —— 用来区分
  --   「属性写入没生效」和「写进去了但引擎渲染不出字形」。注意必须在 put/label **之后**再读，
  --   否则读到的是模板默认值（text=""、fontSize=20、align=Left、size=100x40）。
  local diag = false
  if not G_REAL.textDiag then G_REAL.textDiag = true; diag = true end
  local function rd(k)
    local ok, v = pcall(function() return c[k] end)
    if ok and v ~= nil then return tostring(v) end
    return '?'
  end
  if diag then
    print('main: [diag] 文本框写前 text="' .. rd('text') .. '" fontSize=' .. rd('fontSize')
      .. ' align=' .. rd('horizontalAlignment') .. ' size=' .. rd('sizeDeltaX') .. 'x' .. rd('sizeDeltaY'))
  end
  put(c, wx(x), wyBottom(y + size * 1.4), w * S, size * 1.4 * S)
  label(c, s, size * S, color, align or 'Left')
  if diag then
    print('main: [diag] 文本框写后 text="' .. rd('text') .. '" fontSize=' .. rd('fontSize')
      .. ' fontColor=' .. rd('fontColor') .. ' align=' .. rd('horizontalAlignment')
      .. ' size=' .. rd('sizeDeltaX') .. 'x' .. rd('sizeDeltaY')
      .. ' pos=' .. rd('anchoredPositionX') .. ',' .. rd('anchoredPositionY')
      .. ' visible=' .. rd('visible') .. ' active=' .. rd('active'))
    print('main: [diag] 文本框期望 text="' .. safeUtf8(s) .. '" fontSize=' .. tostring(math.floor(size * S + 0.5))
      .. ' align=' .. tostring(align or 'Left') .. ' size=' .. tostring(w * S) .. 'x' .. tostring(size * 1.4 * S))
    -- 【研究用】把文本框上**所有能读到的字段**列出来：找找引擎里有没有我们没写的"字体/字形/排版"类字段
    -- （真机读不到的字段返回 nil，所以这行会自然只列出真实存在的字段）。
    local FIELDS = {
      'name', 'Id', 'prefabIndex', 'typeofName', 'active', 'visible', 'activeInHierarchy', 'alive',
      'sizeDeltaX', 'sizeDeltaY', 'anchoredPositionX', 'anchoredPositionY',
      'anchorMinX', 'anchorMinY', 'anchorMaxX', 'anchorMaxY', 'pivotX', 'pivotY',
      'localScaleX', 'localScaleY', 'localScaleZ', 'localRotationX', 'localRotationY', 'localRotationZ',
      'text', 'fontSize', 'minimumFontSize', 'adaptiveFontSize', 'fontColor', 'bgColor',
      'enableOutline', 'outlineColor', 'horizontalAlignment', 'verticalAlignment',
      'raycastTarget', 'interactable', 'imageId', 'imageColor', 'visibleInHierarchy',
      -- 下面这些是"猜测名"：真机若存在会打出来，不存在则为 nil（不影响）
      'font', 'fontId', 'fontName', 'fontAsset', 'fontResource', 'textStyle', 'textStyleId',
      'glyphSet', 'spriteFont', 'richText', 'lineSpacing', 'textAlign', 'textVerticalAlign',
      'horizontalOverflow', 'verticalOverflow', 'wrapping', 'overflow', 'backgroundColor', 'color',
    }
    local parts = {}
    for _, k in ipairs(FIELDS) do
      local ok, v = pcall(function() return c[k] end)
      if ok and v ~= nil then parts[#parts + 1] = k .. '=' .. tostring(v) end
    end
    print('main: [diag] 文本框字段: ' .. table.concat(parts, ' '))
  end
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
  -- 【诊断】橙骨（color=2）生成时打一行（最多打 8 条，够看 ROUND22/23 那两段）——
  -- 用来确认"橙骨到底有没有出现在场上"，以及它的实际位置/尺寸。
  if (cmd.color or 0) == 2 then
    G_REAL.orangeSeen = (G_REAL.orangeSeen or 0) + 1
    if G_REAL.orangeSeen <= 8 then
      print(string.format('main: [橙骨] #%d x=%.0f y=%.0f w=%.0f h=%.0f vertical=%s',
        G_REAL.orangeSeen, x, y, w, h, tostring(cmd.vertical)))
    end
  end
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
  local ks = G_REAL.boneKnobs
  if vertical then
    rect(x + (w - k) / 2, y + k / 3, k, math.max(1, h - 2 * k / 3), col)
    if ks then ks[#ks + 1] = circle(x, y, k, col) end
    if ks then ks[#ks + 1] = circle(x + w - k, y, k, col) end
    if ks then ks[#ks + 1] = circle(x, y + h - k, k, col) end
    if ks then ks[#ks + 1] = circle(x + w - k, y + h - k, k, col) end
  else
    rect(x + k / 3, y + (h - k) / 2, math.max(1, w - 2 * k / 3), k, col)
    if ks then ks[#ks + 1] = circle(x, y, k, col) end
    if ks then ks[#ks + 1] = circle(x + w - k, y, k, col) end
    if ks then ks[#ks + 1] = circle(x, y + h - k, k, col) end
    if ks then ks[#ks + 1] = circle(x + w - k, y + h - k, k, col) end
  end
end

-- [2026-10-11 用户口径 v2] 骨头观感通用画法（骨刺小骨 / sin 型长骨都用它）。
--   v1 写的是「满尺寸矩形 + 四颗同色圆」——圆的并集被矩形完全包含，屏幕上仍旧是纯矩形
--   （真机实测：开局杀的骨头看不出骨头形状）。v2 改为和脚本骨 drawBone 同一套几何：
--     k = 0.6×短边 = 骨球直径；骨干宽/高收窄到 k；两端各两颗骨球（原版 BoneV 贴图的两瓣端头）。
--   四颗骨球仍落在**原判定矩形的外接框** x..x+w / y..y+h 内 ⇒ 纯装饰：
--   不增加碰撞体积，core 的命中盒与视觉外接框都不变。
--   骨球登记到 G_REAL.boneKnobs，由 draw() 帧末统一置顶（否则会被后画的骨干矩形盖住）。
function G_REAL.drawBoneLook(x, y, w, h, vertical, col)
  if w == nil or h == nil or w <= 0 or h <= 0 then return end
  if vertical == nil then vertical = (h >= w) end
  local k = math.min(w, h) * 0.6
  if k < 4 then k = 4 end
  if k > w then k = w end
  if k > h then k = h end
  local ks = G_REAL.boneKnobs
  if vertical then
    rect(x + (w - k) / 2, y + k / 3, k, math.max(1, h - 2 * k / 3), col)
    if ks then
      ks[#ks + 1] = circle(x, y, k, col)
      ks[#ks + 1] = circle(x + w - k, y, k, col)
      ks[#ks + 1] = circle(x, y + h - k, k, col)
      ks[#ks + 1] = circle(x + w - k, y + h - k, k, col)
    end
  else
    rect(x + k / 3, y + (h - k) / 2, math.max(1, w - 2 * k / 3), k, col)
    if ks then
      ks[#ks + 1] = circle(x, y, k, col)
      ks[#ks + 1] = circle(x + w - k, y, k, col)
      ks[#ks + 1] = circle(x, y + h - k, k, col)
      ks[#ks + 1] = circle(x + w - k, y + h - k, k, col)
    end
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


-- 龙骨炮：exact 逐像素烘焙（reference/sprites 57×44，Default + 3 个开火帧）。
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

  -- ② 骷髅：exact 逐像素烘焙（reference/sprites 57×44，Default + 3 个开火帧）。
  --    fire 0→1 映射到 3 帧（<0.334 / <0.667 / 满）；每个实例独立容器，可同时画多发。
  do
    local name = nil
    if fit and fit.blaster_keys then
      local keys = fit.blaster_keys
      if fire > 0 then
        local i = 1
        if fire >= 0.667 then i = 3 elseif fire >= 0.334 then i = 2 end
        name = keys.fire[i]
      else
        name = keys.default
      end
    end
    -- 【口径】所有龙骨炮（含旋转段）统一走 block2（2×2 精度）；block3 的 3×3 粗 LOD 已废弃。
    -- 两条路径都仍是 fit 像素烘焙，不会回退旧参数化外观。
    -- 【2026-10-08 用户口径】所有龙骨炮统一走 block2（原 2×2 精度），
    -- 不再按 cmd.lod 切 block3（3×3 粗 LOD 看着像糊/发射异常）。cmd.lod 仍保留但不生效。
    local block = fit and fit.blaster_block2
    if cmd.bake and block then
      local key = 'Default'
      if fire > 0 then key = (fire >= 0.5) and 'fire_2' or 'fire_0' end
      local rects = block[key] or block.Default
      if rects and not G_REAL.blasterDiag then
        G_REAL.blasterDiag = true
        print(string.format('main: [diag] blaster bake=%s block=%s rects=%d sc=%.3f deg=%.1f size=%s w=%s lod=%s',
          tostring(cmd.bake), tostring(block ~= nil), #rects, sc, deg, tostring(cmd.size), tostring(cmd.w), tostring(cmd.lod)))
      end
      if rects then
        for i = 1, #rects do
          local r = rects[i]
          local u = (r.x + r.w / 2 - 28.5) * sc
          local v = (r.y + r.h / 2 - 22) * sc
          local px, py = P(u, v)
          rrect(px, py, r.w * sc, r.h * sc, deg, shade(r.c, a))
        end
      end
    else
    do
      local rgb = bone or 0xFFFFFFFF      local rgb = bone or 0xFFFFFFFF
      local dark = shade(rgb, 0.12)
      local lit  = rgb
      -- 后颅（高）
      local hx, hy = P(-12 * sc, 0);      rrect(hx, hy, 30 * sc, 42 * sc, deg, rgb)
      -- 上颌（向后上方延伸）
      local ux2, uy2 = P(-4 * sc, -14 * sc); rrect(ux2, uy2, 30 * sc, 16 * sc, deg, rgb)
      -- 吻部（前伸的窄长条）
      local sx2, sy2 = P(14 * sc, -2 * sc); rrect(sx2, sy2, 30 * sc, 18 * sc, deg, rgb)
      -- 下颌（前伸略低，形成开口）
      local jx, jy = P(12 * sc, 13 * sc);  rrect(jx, jy, 26 * sc, 9 * sc, deg, shade(rgb, 0.75))
      -- 2 个眼窝
      local e1x, e1y = P(-6 * sc, -2 * sc);  rrect(e1x, e1y, 10 * sc, 12 * sc, deg, dark)
      local e2x, e2y = P(6 * sc, -2 * sc);   rrect(e2x, e2y, 10 * sc, 12 * sc, deg, dark)
      -- 2 点眼火花（开火时更亮）
      local k1x, k1y = P(-4 * sc, 2 * sc);   rrect(k1x, k1y, 4 * sc, 4 * sc, deg, shade(0xFFFFD200, (fire > 0) and 1 or 0.55))
      local k2x, k2y = P(8 * sc, 2 * sc);    rrect(k2x, k2y, 4 * sc, 4 * sc, deg, shade(C_HP, (fire > 0) and a or 0.55 * a))
      -- 上排 4 颗牙（压在吻部前缘）
      for i = 0, 3 do
        local tx, ty = P((2 + i * 6) * sc, 6 * sc)
        rrect(tx, ty, 4 * sc, 5 * sc, deg, lit)
      end
      -- 颈部（连到炮座）
      local nx2, ny2 = P(-4 * sc, 20 * sc);  rrect(nx2, ny2, 14 * sc, 12 * sc, deg, shade(rgb, 0.6))
    end
    end
  end

  -- ③ 炮口亮块（画在最上面）：开火时压在吻部前端
  if fire > 0 then
    local mx, my = P(u0, 0)
    local mw = math.max(10, bw * 0.9)
    rrect(mx, my, mw, mw, deg, shade(C_BEAM_WHITE, a * fire))
  end
end
-- 审判者「sans 本人」：exact 逐像素烘焙（reference/sprites SansBody + SansHead）。
--   身体 = fit.sans_body_*，头 = fit.sans_head_default / sans_head_blue；头按原工程 C2 image point
--   （SansHead 原点(0.5,1) 放到 SansBody 的 Head 点）合成，所以头在身体上方。
--   Left 姿势水平镜像；其余表情统一回退 Default；汗滴用参数化圆点。
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
  x = x + (G_REAL.cfg.sansXOffset or 0)            -- 【可调】Sans 水平修正（真机实测偏左，见 config.lua 注释）
  local head = cmd.head or 'Default'
  local body = cmd.body
  local sweat = tonumber(cmd.sweat) or 0
  if sweat < 0 then sweat = 0 elseif sweat > 3 then sweat = 3 end

  -- 只使用 exact 逐像素烘焙模型；fitdata 缺失时**不再回退旧参数化模型**（避免新旧两套外观并存）。
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
  local bspec = pose and fit[pose.body]
  local hkey = (head == 'BlueEye') and fit.sans_head_blue_key or fit.sans_head_default_key
  local hspec = hkey and fit[hkey]
  if not (pose and bspec and hspec) then return end

  local K = SANS_BAKE_SCALE
  local kx, ky = K, K
  local bw, bh = bspec.w * kx, bspec.h * ky
  local feet = y + SANS_H
  local bx = x - bw / 2
  local by = feet - bh
  local mir = pose.mirror and true or false
  useBakedCorner(pose.body, bx, by, bw, bh, mir)
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
  -- 【2026-10-05 修】心整体**以 (x,y) 为中心**、外接半径 ≈8（= SOUL_R / HEART_HIT 同一口径）。
  -- 旧画法整体偏到右下（圆心在 x+3.5、底尖到 y+13），贴框时红心会露到框外，
  -- 而碰撞/钳位用的是中心 ±8 —— 现在视觉、碰撞、钳位三者同一个尺寸。
  -- 圆瓣的 (cx,cy) 是**左上角**：想让它**中心**落在 (x∓3.5, y-2.5)，左上角还要各减半径 4.5。
  -- 旧写法把中心当左上角 → 两个瓣整体右下偏 (4.5,4.5)，心形变成歪的一坨（红蓝同款错）。
  -- 【2026-10-06 用户口径】蓝心**随 Sans 拖拽旋转**：尖朝向 = 当前重力方向 cmd.dir（0东/1南/2西/3北）。
  -- 【2026-10-06 用户口径】蓝心随 Sans 拖拽旋转：尖朝向 = 当前重力方向 cmd.dir（0东/1南/2西/3北）。
  --   几何照抄原来 dir=1（尖朝下）那一份再整体旋转：
  --     两瓣中心 = 心中心 − 重力方向*2.5 ± 垂直方向*3.5（直径 9）
  --     三角中心 = 心中心 + 重力方向*3.5，15×9，尖朝重力方向
  --   （上一版 back/lobe 取 4.5、三角放大到 18×14，左右方向就歪了。）
  local sdir = (cmd.mode == 'blue') and (cmd.dir or 1) or 1  -- 红心恒为初始尖朝下，不能沿用上次蓝心方向
  local AXD = { [0] = 1, [1] = 0, [2] = -1, [3] = 0 }
  local AYD = { [0] = 0, [1] = 1, [2] = 0,  [3] = -1 }
  local sax, say = AXD[sdir] or 0, AYD[sdir] or 1
  local spx, spy = -say, sax
  local lbx, lby = x - sax * 2.5, y - say * 2.5
  circle(lbx + spx * 3.5 - 4.5, lby + spy * 3.5 - 4.5, 9, col)
  circle(lbx - spx * 3.5 - 4.5, lby - spy * 3.5 - 4.5, 9, col)
  -- 【2026-10-06 用户口径】三角角度装反了 180°。引擎 SetLocalRotation 的约定：
  --   0°=尖朝上、90°=朝左、180°=尖朝下、270°(= -90°)=尖朝右
  --   （对照 drawStab：左边框的骨刺用 deg=90 朝左 ✓）。所以 dir=0(东/朝右) 要用 -90、dir=2(西) 用 90。
  local TIPANG = { [0] = -90, [1] = 180, [2] = 90, [3] = 0 }
  rtri(x + sax * 3.5, y + say * 3.5, 15, 9, TIPANG[sdir] or 180, col)
  return
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
  rect(cmd.x, cmd.y, cmd.w, cmd.h, cmd.color or C_WHITE)
  circle(cmd.x + 3, cmd.y + cmd.h - 3, 7, cmd.color or C_WHITE)
  circle(cmd.x + cmd.w - 10, cmd.y + cmd.h - 3, 7, cmd.color or C_WHITE)
end

-- 红心标记（菜单选中项用），与原作一致：心停在选中按钮左侧
local function heart(cx, cy, col, r)
  -- 【2026-10-13 用户口径】菜单栏 / 选项栏的红心**直接用战斗里那颗心的模型**（drawSoul 的几何逐字照抄）：
  --   两瓣：直径 9，瓣中心 = 心中心 − 重力方向*2.5 ± 垂直方向*3.5；尖：15×9 三角，尖朝重力方向
  --   菜单里的心恒为初始朝向 dir=1（尖朝下）；外接半径 ≈8 = SOUL_R ⇒ 与战斗中的心**同尺寸同形状**。
  --   （旧实现在这里是另一套"2r×r 的小几何"（r=7/6），所以菜单/选项的心与战斗的心看着不一样。）
  --   r 参数保留签名但**不再参与几何** —— 尺寸一律按战斗模型，杜绝两处不一致。
  local sax, say = 0, 1
  local spx, spy = -say, sax
  local lbx, lby = cx - sax * 2.5, cy - say * 2.5
  local a = circle(lbx + spx * 3.5 - 4.5, lby + spy * 3.5 - 4.5, 9, col)
  local b = circle(lbx - spx * 3.5 - 4.5, lby - spy * 3.5 - 4.5, 9, col)
  local t = rtri(cx + sax * 3.5, cy + say * 3.5, 15, 9, 180, col)
  -- 记录本帧用到的红心控件：帧末统一置顶，避免被按钮黑底（rect 池）之类按创建顺序盖住
  local hs = G_REAL.hearts
  if hs ~= nil then
    if a ~= nil then hs[#hs + 1] = a end
    if b ~= nil then hs[#hs + 1] = b end
    if t ~= nil then hs[#hs + 1] = t end
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
  local bh = cmd.h or 36
  local fs = 22                                   -- 标签字号（世界单位）
  local ty = y + (bh - fs * 1.4) / 2              -- 文字盒顶部：让标签在按钮矩形内垂直居中
  for i, it in ipairs(items) do
    local bx, by, bw = menuButtonRect(cmd, i)
    local selected = menuItemSelected(cmd, i)
    -- 【方案 B】按钮底：黑底 + 1px 白描边（对应原版 Default 贴图的"黑底 + 描边"，选中只换文字颜色）
    --   注意：黑底来自 rect 池，红心来自 circle/rtri 池 —— 层级按控件创建顺序定，
    --   所以红心在**帧末统一置顶**（见 draw() 末尾的 G_REAL.hearts 处理），才不会被黑底盖住。
    local edge = C_WHITE
    rect(bx, by, bw, bh, 0xE6000000)
    rect(bx, by, bw, 1, edge); rect(bx, by + bh - 1, bw, 1, edge)
    rect(bx, by, 1, bh, edge); rect(bx + bw - 1, by, 1, bh, edge)
    -- 【方案 A3】红心在按钮内左 16px、垂直居中（原版 Heart 图像点）
    -- 【2026-10-13】灵魂（心）整体下移 M.MENU_HEART_DY 像素（原来是 by+bh/2 正中）
    if selected then heart(bx + 16, by + bh / 2 + (M.MENU_HEART_DY or 0), C_RED, 7) end
    -- 【方案 A4】标签让出左侧心位：从 bx+26 起、宽 bw-32，仍居中（中文 2 字 ≈44px 不会压到心）
    text(it, bx + 26, ty, bw - 32, fs, selected and C_HP or C_WHITE, 'Middle')
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

local function drawHud(cmd)
  local a = ALIGN[cmd.align or 'Left'] or 'Left'
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
-- 【2026-10-08 用户口径】骨刺只用**细骨**表示：删掉原来贴在骨尖上的三角形图元（rtri）。
--   依据交接包文档："骨刺使用细骨排列"，rtri 只留给其它三角图元（心尖等仍然用它）。
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

local function drawStab(cmd)
  local x, y, w, h = cmd.x, cmd.y, cmd.w, cmd.h
  if w <= 0 or h <= 0 then return end
  local peek = (cmd.phase == 'peek')
  local alpha = peek and 0.45 or (cmd.alpha or 1)
  local col = ((math.floor(255 * alpha)) << 24) | 0xFFFFFF
  -- 【2026-10-11 用户口径】把"一条平行于边的骨刺"画成**一排垂直于边的小骨**：
  --   沿边间距 13px、单根厚 10px ⇒ 缝 3px < 灵魂判定盒 4px ⇒ 钻不过去；
  --   判定仍用整条边（core.World:stabRect 不变）⇒ 视觉有缝、实际无缝。
  local SP, BW = 13, 10
  local alongX = (w >= h)                    -- 横条（上/下边刺出）沿 x 排；竖条（左/右边刺出）沿 y 排
  if alongX then
    local n = math.max(1, math.ceil(w / SP))
    for i = 0, n - 1 do
      local bx = x + i * SP
      if bx < x + w then
        local bw2 = math.min(BW, x + w - bx)
        G_REAL.drawBoneLook(bx, y, bw2, h, (h >= bw2), col)
      end
    end
  else
    local n = math.max(1, math.ceil(h / SP))
    for i = 0, n - 1 do
      local by = y + i * SP
      if by < y + h then
        local bh2 = math.min(BW, y + h - by)
        G_REAL.drawBoneLook(x, by, w, bh2, (bh2 >= w), col)
      end
    end
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
      if b and b.w > 0 and b.h > 0 then
        G_REAL.drawBoneLook(b.x, b.y, b.w, b.h, (b.h >= b.w), C_WHITE)
      end
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
  rect(x, y, w, h, 0xE6000000)
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
      -- 字号按行高定，但字形（CodeArt 16px 基准）比原来的原生字体"墨迹更满"，
      -- 取 0.58×行高（上限 15）才不会相邻两行视觉粘连。
      local fs = math.min(15, math.max(11, (cmd.rowH or 26) * 0.58))
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
}

local function frameBegin()
  G_REAL.hearts = {}          -- 本帧用到的红心控件（帧末置顶用）
  G_REAL.boneKnobs = {}       -- 本帧用到的骨球控件（帧末置顶用：否则被骨干矩形盖住）
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
  -- 战斗框平滑过渡：逻辑层每帧给目标，直接重设会像瞬移/乱跳；这里按帧插值收敛（约 0.12s）
  if boxTarget then
    local k = 0.35
    curBox.x = curBox.x + (boxTarget.x - curBox.x) * k
    curBox.y = curBox.y + (boxTarget.y - curBox.y) * k
    curBox.w = curBox.w + (boxTarget.w - curBox.w) * k
    curBox.h = curBox.h + (boxTarget.h - curBox.h) * k
    if math.abs(curBox.x - boxTarget.x) < 0.4 and math.abs(curBox.y - boxTarget.y) < 0.4
        and math.abs(curBox.w - boxTarget.w) < 0.4 and math.abs(curBox.h - boxTarget.h) < 0.4 then
      curBox.x, curBox.y, curBox.w, curBox.h = boxTarget.x, boxTarget.y, boxTarget.w, boxTarget.h
    end
  end
  -- 标题页提示行（core 只发标题 + 四张难度卡与注释，操作提示由本层补；两平台给不同的提示）
  local titleNow = (state ~= nil and state.state == 'title')
  if titleNow then
    if isTouch then
      if pendingSel and pendingSel.kind == 'title' then
        text('再 点 一 次 开 始    ·    点其它难度卡可改选', 0, 296, W, 16, C_HP, 'Middle')
      else
        text('点难度卡选中    ·    再点一次开始', 0, 296, W, 16, C_DIM, 'Middle')
      end
    else
      text('← → 选难度    ·    点难度卡 或 按 Enter 开局', 0, 296, W, 16, C_DIM, 'Middle')
    end
  end
  -- 本帧真正画出去的命令种类（回归用：标题页必须没有 box）
  drawnKinds = {}
  for i = 1, #cmds do
    local cmd = cmds[i]
    if DRAW[cmd.kind] then
      -- 标题页**不画战斗框**：core 在 title 态也会推一条 box（战斗态复用同一位置），
      -- 但它会把白框横穿四张难度卡 —— 直接跳过绘制，其它状态照旧。
      local skip = (cmd.kind == 'box' and titleNow)
      if not skip then
        if cmd.kind == 'box' then drawnBox = true end
        drawnKinds[#drawnKinds + 1] = cmd.kind
        DRAW[cmd.kind](cmd)
      end
    end
  end
  -- 两平台各自的常驻操作提示（PC = 键位；触摸 = 两段式点按）
  if not titleNow then
    if isTouch then
      text('左半屏拖动移动    ·    点击选项选中，再次点击确认', 0, 44, W - 20, 10, C_DIM, 'Right')
    else
      text('WASD 移动    ·    Enter 确认', 0, 44, W - 20, 10, C_DIM, 'Right')
    end
  end
  drawPendingHint()      -- 触摸端「再点一次确认」提示（画在选中项旁边）

  -- 【z 序 · 2026-10-08】把本帧用到的文本框提到最上层。
  -- 为什么必须显式提：真机**按控件创建顺序**定兄弟序，而真机上我们不做批量预热、控件是按需创建的 ——
  -- 后面新建的 rect/circle（骨头、HP 条底、战斗框边、黑底……）会盖在**先前建的文本框**上面，
  -- 表现为"文字一个都不显示"。模拟器因为一次性把全部控件预热好、顺序固定，所以复现不出来。
  -- 每帧最多 15 次调用，成本可忽略；比依赖创建顺序可靠。
  -- ① 字形层（CodeArt 文字全在这里）置顶 —— 它烘在独立容器里，不置顶就会被池矩形（面板底板/边框）盖住；
  -- ② 原生文本框控件（textMode='control' 时才用）同样置顶；
  -- ③ 闪层最后（结局白闪要盖住包括文字在内的一切）。
  if G_REAL.glyphLayer ~= nil then pcall(function() G_REAL.glyphLayer:SetAsLastSibling() end) end
  -- 红心（圆瓣 + 三角来自 circle/rtri 池）同样要置顶：否则会被按钮黑底（rect 池）按创建顺序盖住
  if type(G_REAL.boneKnobs) == 'table' then
    for ki = 1, #G_REAL.boneKnobs do
      local kc = G_REAL.boneKnobs[ki]
      if kc ~= nil then pcall(function() kc:SetAsLastSibling() end) end
    end
  end
  if type(G_REAL.hearts) == 'table' then
    for hi = 1, #G_REAL.hearts do
      local hc = G_REAL.hearts[hi]
      if hc ~= nil then pcall(function() hc:SetAsLastSibling() end) end
    end
  end
  local tpool = pool.text
  if tpool ~= nil then
    for ti = 1, (used.text or 0) do
      local tc = tpool[ti]
      if tc ~= nil then pcall(function() tc:SetAsLastSibling() end) end
    end
  end
  if flash ~= nil then pcall(function() flash:SetAsLastSibling() end) end
  frameEnd()
end

-- ---------------------------------------------------------------- 输入

-- 按键诊断（**只打第一条**）：试玩页那一层负责把物理键（WASD/方向键/Enter…）翻成引擎语义键
-- （`KeyboardMoveForwardKeyDown` 等，见 studio/play/browser-session.js 的 SEMANTIC_KEY_CODES），
-- 插件试玩页加载的是 dsh-plugin/dist/play-renderer.js 里打包的同一张表。
-- 如果用户按了 WASD 却**从未**看到这行，就说明按键在试玩页那一层就被丢了（映射缺失/页面没转发），
-- 而不是游戏逻辑没响应；看到这行则说明事件已到达 Lua，问题在别处。
local keyDiagLogged = false
-- bind(name, fn[, optional])：optional = 这一路键在真机枚举里可能不存在（如 KeyboardMenuConfirmKey），
-- 失败时只提示「跳过可选键」，不当成错误。
local function bind(name, fn, optional)
  if not root then return end
  -- 回调必须留引用：RemoveKeyEventListener(name, fn) 要的是**同一个函数对象**，
  -- 注册完就丢引用的话 OnDestroy 里根本卸不掉（真机换关/重开的残留监听就是这么来的）。
  local cb = function()
    if not keyDiagLogged then
      keyDiagLogged = true
      print(string.format('main: 收到按键事件 %s（若你按了 WASD 却从未出现这行，说明试玩页那层没转发按键）', name))
    end
    fn()
  end
  -- 真机要 Enum.KeyEventType（字符串会抛 "KeyEventType expected, got string"，见 2026-10-08 真机日志）
  local used = G_REAL.addKeyEvent(root, name, cb)
  if used ~= nil then owned.keys[#owned.keys + 1] = { name = used, cb = cb }
  elseif optional then print('main: 跳过可选键 ' .. name .. '（本宿主不认字符串键名，枚举里也没有这一项）')
  else print('main: bind fail ' .. name .. '（宿主既不吃字符串键名，也没有 Enum.KeyEventType.' .. name .. '）') end
end

-- 键盘**四向表**（**只在 PC 分支注册**：bindKeys 只被 PC 分支调用，触摸分支不绑、不响应任何键盘事件）：
-- 一个方向一条，每条给出「按下 / 抬起」两个事件名（引擎里成对存在）
-- 与它驱动的方向位。四向各自独立（不是互斥的"当前方向"），所以同时按 W+A 天然得到左上对角。
--
-- 键名出处（两个来源都能在源码里查到，不凭猜；名字就用这一套，不引入其它拼写）：
--   ① 引擎侧的按键事件名 = `Keyboard<Enum.KeyboardKeyCode 的项名><Down|Up>`。
--      worker.js 里 KeyboardKeyCode（压缩名 hl）是：
--        [...43×CraftspersonKey,"MoveForwardKey","MoveBackwardKey","MoveLeftKey","MoveRightKey",
--         "SwitchToWalkOrRunKey","SprintKey","JumpKey","DropKey","OpenShortcutWheelKey",
--         "InteractKey","NormalAttackKey","CharacterSkill1Key"…"CharacterSkill4Key","None"]
--      紧接着的 pl() 对每个项名拼出 `Keyboard${name}${Down|Up}` 与 `Controller${name}${Down|Up}`
--      → 就是 Enum.KeyEventType。所以下面这 8 个移动键名是**枚举里确实存在**的。
--      注意：键盘枚举里**没有** MenuConfirmKey / MenuBackKey（只有手柄项 ml 里有
--      ControllerMenuConfirmKey…），所以 KeyboardMenuConfirmKeyDown 只存在于下面②这一层。
--   ② 试玩页把物理键翻成上面的语义键：模拟器仓库 studio/play/browser-session.js:7-16
--      （构建产物见 web/public/play-renderer.js 里的 KE=new Map([...])）：
--        KeyW / ArrowUp    → MoveForwardKey      KeyS / ArrowDown  → MoveBackwardKey
--        KeyA / ArrowLeft  → MoveLeftKey         KeyD / ArrowRight → MoveRightKey
--        Enter / NumpadEnter / Space / KeyZ → MenuConfirmKey     Escape / KeyX → MenuBackKey
--        ShiftLeft/Right → SprintKey             KeyJ → NormalAttackKey   KeyF / KeyE → InteractKey
--      → W/↑ = 上、S/↓ = 下、A/← = 左、D/→ = 右**四个方向各一对**，正是下面这张表。
--        Enter、小键盘回车、Z、空格在这一层**都归到同一个 KeyboardMenuConfirmKeyDown**，
--        所以绑它一个就同时覆盖这四种确认方式；再补 KeyboardNormalAttackKeyDown（J）作为备用确认。
--        ⚠ 插件 2.0.8 自带的试玩页（dsh-plugin/dist/play-renderer.js）**还是只转发数字键**，
--          没带上②这张表 —— 所以在插件试玩页里按 WASD 不会有任何事件（要在插件侧补映射，见
--          docs/plugin-keymap.md）。本层只能保证：事件一旦按这些名字派发，游戏一定收得到。
--   ③ 前提（worker.js Control.injectKey）：从所有根控件递归找**精确同名**的监听，
--      要求该控件 alive 且 activeInHierarchy（我们挂在 n1 容器上，存档里 active=true）。
--      **不需要** SetControllerFocus / canControllerFocus（那是手柄导航用的），
--      **不需要** disableKeyEventPassthrough=false（injectKey 根本不读它），
--      AddKeyEventListener 在公共方法表 al 里 → 挂在根容器和挂在 cursor 控件上等价。
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
  -- 方向：键盘语义键名（试玩页注入的字符串）优先，真机上同一个名字换成 Enum.KeyEventType.*
  -- （bind → G_REAL.addKeyEvent 内部「先字符串、抛错再枚举」，两条路径都能落地）
  for _, k in ipairs(KEY_DIRS) do
    local dir = k.dir
    bind(k.down, function() setDir(dir, true) end)
    bind(k.up, function() setDir(dir, false) end)
  end
  -- 确认 / 取消：**多来源聚合**。
  --   ① 真机枚举里**没有** KeyboardMenuConfirmKey / KeyboardMenuBackKey（只有 ControllerMenuConfirmKey /
  --      ControllerMenuBackKey，见 worker.js 的 pl()：键盘表里就没有 MenuConfirm/MenuBack 这两项）；
  --   ② 同一个「确认」在千星有多种可用来源（Enter/空格/Z、Jump 键、J、F/E、控制器 MenuConfirm）。
  --   所以按来源分别记状态、任一按住即算按住 —— 一个来源的「抬起」绝不能顶掉另一个还按着的来源
  --   （蓝心跳跃靠**按住时长**决定高度，这个状态必须准）。
  local HOLD = owned.holds
  local function anyHold(t)
    for _, v in pairs(t) do if v then return true end end
    return false
  end
  local function bindConfirm(name)
    bind(name .. 'Down', function()
      -- 【修复：空格反复触发攻击/闪避】只认"从抬起到按下"的那一次 —— 长按或
      -- 手柄/键盘的自动重复（连续 Down 但中间没有 Up）不再产生新的确认边沿。
      local was = HOLD.confirm[name]
      HOLD.confirm[name] = true
      if not was then edgeConfirm = true end
      confirmHeld = anyHold(HOLD.confirm)
    end, true)
    bind(name .. 'Up', function()
      HOLD.confirm[name] = false; confirmHeld = anyHold(HOLD.confirm)
    end, true)
  end
  local function bindCancel(name)
    bind(name .. 'Down', function()
      HOLD.cancel[name] = true
      edgeCancel = true
      -- 【诊断】记下"玩家按了 ESC/返回键"的帧号：OnDisable/OnDestroy 时用它区分
      --   「玩家强制退出」和「服务端结算结束关卡」。
      G_REAL.escFrame = frame
      print('main: [input] 按下返回键（ESC/X）→ 若随后立刻出现 OnDisable/OnDestroy，那就是玩家强退')
    end, true)
    bind(name .. 'Up', function() HOLD.cancel[name] = false end, true)
  end
  -- 确认：Enter / 小键盘回车 / Z / 空格（试玩页都归到 KeyboardMenuConfirmKey）
  --       控制器 MenuConfirm、Jump 键、J（NormalAttack）、F/E（Interact）兜底
  for _, n in ipairs({ 'KeyboardMenuConfirmKey', 'ControllerMenuConfirmKey', 'KeyboardJumpKey',
                       'KeyboardNormalAttackKey', 'KeyboardInteractKey' }) do bindConfirm(n) end
  -- 取消：Esc / X（KeyboardMenuBackKey）、控制器 MenuBack、Drop 键
  for _, n in ipairs({ 'KeyboardMenuBackKey', 'ControllerMenuBackKey', 'KeyboardDropKey' }) do bindCancel(n) end

  -- 【键位诊断，默认关】lua/config.lua 里 C.keyDiag = true 时，把 Enum.KeyEventType 里**所有**事件
  -- 都挂一个「按到就打印」的监听。真机上不确定某个物理键对应哪个事件名时打开它：
  -- 进入关卡后按一下想用的键，日志会打 main: [keyDiag] <事件名>，据此把确认键配准。
  if G_REAL.cfg.keyDiag then
    local okLib, lib = pcall(function() return Enum.KeyEventType end)
    if okLib and type(lib) == 'table' then
      local count = 0
      for name, ev in pairs(lib) do
        local cb = function() print('main: [keyDiag] ' .. tostring(name)) end
        if pcall(function() root:AddKeyEventListener(ev, cb) end) then
          owned.keys[#owned.keys + 1] = { name = ev, cb = cb }
          count = count + 1
        end
      end
      print('main: [keyDiag] 已挂 ' .. count .. ' 个按键监听（随便按键，看日志打出的事件名）')
    else
      print('main: [keyDiag] 本宿主没有可枚举的 Enum.KeyEventType，配不了键位')
    end
  end
end

local function consumeEdges()
  local c, x = edgeConfirm, edgeCancel
  edgeConfirm, edgeCancel = false, false
  -- 【修复：空格反复触发攻击/闪避】去抖：相邻 3 帧（≈0.1s）内只接受一次确认边沿。
  -- 攻击条 / 菜单 / 结局页都靠这个边沿推进，连按会在同一状态里重复触发（闪避动画会反复重放）。
  if c then
    if G_REAL.lastConfirmFrame ~= nil and (frame - G_REAL.lastConfirmFrame) < 3 then
      c = false
    else
      G_REAL.lastConfirmFrame = frame
    end
  end
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
  -- 游标回调同样要留引用（OnDestroy 里逐个 RemoveCursorEventListener / 最后 RemoveAll 兜底）。
  -- 真机要 Enum.CursorEventType.*（字符串同样会抛 "CursorEventType expected, got string"）
  local function onCursor(name, fn)
    local used = G_REAL.addCursorEvent(cursorArea, name, fn)
    if used ~= nil then owned.cursors[#owned.cursors + 1] = { name = used, cb = fn, c = cursorArea }
    else print('main: 游标监听注册失败 ' .. name .. '（宿主既不吃字符串，也没有 Enum.CursorEventType.' .. name .. '）') end
  end
  local ok, err = pcall(function()
    onCursor('CursorDown', function(e)
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
        if state and state.state == 'enemy' and inJoyZone(twx, twy) and not uiHit(twx, twy) then
          joy.active = true
          -- 【2026-10-11 用户口径·固定摇杆】基准点**固定**在 HOME（原神预设位），不再跟随按下点
          joy.bx, joy.by = JOY_HOME_X, JOY_HOME_Y
          joy.kx, joy.ky, joy.dx, joy.dy = 0, 0, 0, 0
        end
      end
      -- PC 分支：这里**什么都不做** —— 鼠标只在 UI 上起作用，拖动不产生任何移动、也不画摇杆
      onPointer(e, false, 'CursorDown')
    end)
    onCursor('CursorDrag', function(e)
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
    onCursor('CursorUp', function(e)
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
    onCursor('CursorClick', function(e)
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
    elseif hit == 3 then
      -- 【2026-10-09】第三项：重开并**重选难度**（回标题页）
      pcall(function() core.retitle(state) end)
      print('main: 点按 → 重选难度（回标题页）')
    else
      -- hit==2 或点空白：保持旧的“点结局页重开”手感。
      pcall(function() core.requestRestart(state) end)
      print('main: 点按 → 重开（需再确认一次）')
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
  if isTouch and joy.active then
    local d = joyDirs(joy.dx, joy.dy)
    input.left, input.right, input.up, input.down = d.left, d.right, d.up, d.down
  elseif ptr.wasJoy then
    input.left, input.right, input.up, input.down = false, false, false, false
    diagSoul = nil
  end
  ptr.wasJoy = joy.active
  return false
end

-- 摇杆几何（**绘制与判定同源**，回归可直接断言）：底座圆心 = 基准点 (bx,by)，
-- 杆头中心 = 基准点 + (kx,ky) —— kx/ky 就是上面 CursorDrag 里由原始偏移算出的那一份
-- （同一份 dx/dy 归一化后的向量，方向位也由它派生）。两者都走 wx()/wyBottom() 换算到画布坐标
-- （千星画布原点在左下、Y 向上，wyBottom(y) = OY + (H-y)*S 已经翻过一次），
-- 所以往上拖（世界 ky<0）杆头画在圈心**上方**，不会出现"拖上去、圈画在下面"。
local function joystickGeom()
  -- 【2026-10-11】固定摇杆：触摸分支下**常显**（未按住画淡底盘，让玩家知道摇杆固定在哪）
  if not isTouch then return nil end
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
  local alpha = joy.active and 0.8 or 0.28
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

local function tryLoadTextArt()
  local ok, m = pcall(require, 'default_import_file/workspace/sans-fight/lua/textart')
  if ok and type(m) == 'table' and type(m.glyphs) == 'table' then return m end
  local ok2, m2 = pcall(require, 'lua' .. '.textart')
  if ok2 and type(m2) == 'table' and type(m2.glyphs) == 'table' then return m2 end
  print('main: textart 未加载（文字回退到原生文本框）:: ' .. tostring(m))
  return nil
end

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
  local ok, v = pcall(function() return game.GetGlobalCustomVariableValue('Level', 'SansDifficulty') end)
  if ok and type(v) == 'string' and v ~= '' then return v end
  return 'normal'
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
  -- 官方**同时**提供 OnUpdate 与 OnLevelUpdate；两个都推进 = 每帧跑两遍（速度翻倍、双倍伤害）。
  -- 默认只让 OnLevelUpdate 推进（与关卡暂停一致）；只有确认外部宿主**只**调 OnUpdate 时，
  -- 才在 lua/config.lua 里把 C.updateCallback 改成 'ui'。
  if G_REAL.cfg.updateCallback == 'ui' then return M.OnLevelUpdate(dt, true) end
end

function M.OnStart()
  if owned.started then return end        -- 宿主可能重复触发 OnStart（容器重建/重进），防重入
  if not root then M.OnInit() end
  if not root then error('找不到脚本宿主容器：请把 main.lua 挂在客户端画布的根容器节点上') end
  owned.started = true
  -- 【真机】事件透传开关：不打开 key/cursor 透传，子控件的监听收不到事件；
  -- showCursor 必须开在**祖先容器**上（worker 的 cursorEventsEnabled 逐级往上找 kind=='container' 且 showCursor）。
  pcall(function() script:EnableUpdate(true) end)
  pcall(function() root.disableKeyEventPassthrough = true end)
  pcall(function() root.disableCursorEventPassthrough = true end)
  pcall(function() root.showCursor = true end)
  -- 【官方文档要求】Root 必须覆盖整个画布：锚点 (0,0)-(1,1)、位置与尺寸差都为 0。
  -- 编辑器里没配的话，子控件的绝对坐标就会相对一个「小盒子」定位 —— 整幅画面缩在左下角。
  G_REAL.stretchFull(root)
  layout()
  isTouch = detectDevice()      -- 平台分流：只认 Mobile / MobileController，其余（含读不到）按 PC
  -- 纯黑背景板：**在所有控件之前**创建 → 兄弟序天然在最底层（新实例默认置顶，先建的在下面）。
  -- 模拟器试玩页/截图里的舞台底色是宿主画的渐变，真机底色也不可控 → 背景必须由 Lua 自己糊一层。
  --
  -- 【2026-10-08 真机第二轮】铺**两层**，两层都不依赖 pivot 的绝对摆放：
  --   ① bgPanel：stretch 锚点 (0,0)-(1,1)、尺寸差 0 → 精确铺满 Root（Root 已拉成铺满画布）＝ 铺满画布；
  --   ② bgOver ：同样 stretch，但尺寸差 +2CW/+2CH（居中向四周各扩 CW/CH）→ 画布外一圈也是黑的，
  --              宽屏/超宽/画布比逻辑画布大时不会露出宿主场景。
  -- 只用 ① 时若宿主把子控件裁到画布，就铺不满某些比例；只用 ② 时若宿主对 stretch 的解释不同，
  -- 也可能只盖住一块 —— 两层叠加后，最坏情况仍有一层是满的。
  bgPanel = spawn('rect')
  if bgPanel then
    G_REAL.stretchFull(bgPanel)
    tint(bgPanel, 0xFF000000)
    bgPanel:SetVisible(true)
    st(bgPanel).vis = true
  end
  bgOver = spawn('rect')
  if bgOver then
    G_REAL.stretchFull(bgOver)
    pcall(function() bgOver:SetSizeDelta(CW * 2, CH * 2) end)   -- 相对父层四周各外扩 1 倍画布
    tint(bgOver, 0xFF000000)
    bgOver:SetVisible(true)
    st(bgOver).vis = true
  end
  G_REAL.dumpGeom(root, 'root')
  G_REAL.dumpGeom(bgPanel, 'bg1-stretch')
  G_REAL.dumpGeom(bgOver, 'bg2-overscan')
  -- 字形层：**独立于 bakedRoot**（bakedRoot 在池控件之下，字形必须在其上），每帧在 draw() 末尾置顶。
  G_REAL.glyphLayer = spawn('bakedRoot')
  if G_REAL.glyphLayer then
    G_REAL.stretchFull(G_REAL.glyphLayer)
    G_REAL.activate(G_REAL.glyphLayer)
  end
  -- 烘焙容器根：必须在 prewarm 之前创建 → 烘焙层在黑底之上、池控件之下。
  bakedRoot = spawn('bakedRoot')
  if bakedRoot then
    put(bakedRoot, 0, 0, 0, 0)
    bakedRoot:SetVisible(true)
    st(bakedRoot).vis = true
  end
  fit = tryLoadFit()
  textart = tryLoadTextArt()
  prewarm()
  cursorArea = take('cursor')
  pool.cursor = nil        -- 游标区不参与每帧显隐管理，始终铺满画布接收指针
  if cursorArea then cursorArea:SetVisible(true) end
  flash = spawn('rect')
  core = tryLoadCore()
  music = tryLoadMusic()
  if core then
    local ok, s = pcall(function()
      return core.newTitle({ difficulty = difficulty(), scripts = attacks, hp = 92,
                             startRound = bootRound() })
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
    print('main: 平台 = 触摸分支（不注册键盘监听；左半屏摇杆 + 点按二次确认）')
  else
    bindKeys()
    print('main: 平台 = PC 分支（键盘移动/确认；指针只点 UI，无摇杆）')
  end
  bindPointer()
  -- 显式层序（防「真机同级层叠顺序与模拟器相反」这类差异，见 6nimmt 的 AGENTS.md）：
  -- 背景钉最底、闪层钉最上；池内控件的相对顺序仍由创建顺序决定（后取的压在上面）。
  if bgOver then pcall(function() bgOver:SetAsFirstSibling() end) end
  if bgPanel then pcall(function() bgPanel:SetAsFirstSibling() end) end
  if flash then pcall(function() flash:SetAsLastSibling() end) end
  -- 进入游戏：**只发一次**的开局信号（服务端据此起 120 秒计时器；重开/重选难度不再发）
  G_REAL.sendStartSignal()
  print(string.format('main start: build=%s device=%s touch=%s mode=%s pool=%d flash=%s cursor=%s',
    BUILD, deviceName, tostring(isTouch), mode, madeTotal, tostring(flash ~= nil), tostring(cursorArea ~= nil)))
end

-- 【2026-10-09 用户口径】把"发信号"拆出来，供两处复用：
--   唯一触发点：结局页点「结 算」（ESC 不发信号）。
-- 注意：这里**不改 state.result** —— 时间是否够、要不要弹提示、是否真结算，全部由服务端节点图按它自己的计时器决定。
function G_REAL.sendSettleSignal(resultBool, why)
  if type(game.ServerSignal) ~= 'function' then
    print('main: 结算信号不可用（当前宿主没有 game.ServerSignal）')
    return
  end
  local ok, err = pcall(function()
    local sig = game.ServerSignal('SansFightSettle')
    -- 【2026-10-09 用户口径】result 改为**布尔**：胜利 = true(1) / 失败 = false(0)。
    -- 真机实测（日志）：AddBool **只接受一个参数（值本身）**——
    --   传 (名字, 值) 会报 bad argument count to 'AddBool' (2 expected, got 3)。
    -- 所以这里「先试带名字，失败就退回只传值」；参数顺序仍按信号配置的声明顺序：result → hp → kr → round。
    local function addBool(v)
      if not pcall(function() sig:AddBool('result', v) end) then sig:AddBool(v) end
    end
    local function addInt(name, v)
      if not pcall(function() sig:AddInt(name, v) end) then sig:AddInt(v) end
    end
    addBool(resultBool and true or false)
    addInt('hp', math.floor((state and state.hp) or 0))
    addInt('kr', math.floor((state and state.kr) or 0))
    addInt('round', math.floor(((state and state.round) or 0) + 1))
    sig:SendSignal()
  end)
  if ok then
    print('main: 已发送结算信号 SansFightSettle' .. tostring(why or ''))
  else
    print('main: 结算信号发送失败 :: ' .. tostring(err))
  end
end

-- 进入战斗时广播开局信号（服务端收到 → 起 120 秒计时器）
function G_REAL.sendStartSignal()
  -- 【2026-10-09 用户口径】整个会话**只发一次**：脚本挂载进入时就发，之后重开/重选难度/换回合都不再发。
  if G_REAL.startSignalSent then return end
  G_REAL.startSignalSent = true
  if (G_REAL.cfg.startSignal or '') == '' then return end     -- 留空 = 不发（用户已改用界面控件组触发）
  if type(game.ServerSignal) ~= 'function' then return end
  local name = G_REAL.cfg.startSignal or 'SansFightStart'
  local ok, err = pcall(function()
    local sig = game.ServerSignal(name)
    sig:SendSignal()
  end)
  if ok then
    print('main: 已发送开局信号 ' .. tostring(name) .. '（服务端可据此起计时器）')
  else
    print('main: 开局信号发送失败 :: ' .. tostring(err))
  end
end

local function requestSettlement()
  if not (state and state.settleRequested) then return end
  state.settleRequested = false
  if music then music.stop() end      -- 循环到结算为止
  -- 结局页：kill / spare / victory 等非 fail 的结局都算「胜利」→ true；fail → false
  local win = ((state and state.result) ~= 'fail')
  G_REAL.sendSettleSignal(win, string.format('（结局页结算 · result=%s → %s）',
    tostring(state and state.result), win and 'true/1' or 'false/0'))
end

-- ---------------------------------------------------------------- 文本渲染「隔离探针」
-- 【用途】回答"这台机器到底能不能渲染原生文本框"。按交接项目建议的做法：**另开一层独立容器**，
-- 只画三样东西，不挂战斗内容、不受池清理/黑底/闪层影响：
--   ① 白色参照矩形（证明 rect 路径正常）
--   ② 画布里**手放**的文本框 TextProbe（如果存在）—— 我们**一个字都不写**，完全保持编辑器里的状态
--   ③ 我们脚本实例化 + 写入的文本框（ASCII 与中文各一，外加对齐/自适应对照）
-- 开启方式：lua/config.lua 里 C.textProbe = true（改完重建存档）。
local function textProbeFrame()
  frameBegin()
  G_REAL.probeLayer = G_REAL.probeLayer or spawn('bakedRoot')
  local layer = G_REAL.probeLayer
  if layer ~= nil then
    G_REAL.stretchFull(layer)
    G_REAL.activate(layer)
    -- 父链置顶：不只是把叶子提到最后，而是把承载它的**整层容器**提到同级最后
    pcall(function() layer:SetAsLastSibling() end)
  end
  local function putText(c, txt, wx0, wy0, ww, size, col, align, minSize)
    if c == nil then return end
    put(c, wx(wx0), wyBottom(wy0 + size * 1.4), ww * S, size * 1.4 * S)
    G_REAL.trySet(c, 'fontSize', function() c.fontSize = math.floor(size * S + 0.5) end)
    if minSize then G_REAL.trySet(c, 'minimumFontSize', function() c.minimumFontSize = minSize end) end
    G_REAL.trySet(c, 'fontColor', function() c.fontColor = G_REAL.apiColor(col) end)
    G_REAL.trySet(c, 'bgColor', function() c.bgColor = G_REAL.apiColor(0x00000000) end)
    G_REAL.trySet(c, 'text', function() c.text = safeUtf8(txt) end)
    G_REAL.setAlign(c, align)
    pcall(function() c:SetAsLastSibling() end)
  end
  -- ① 白矩形参照
  rect(80, 60, 480, 26, C_WHITE)
  -- ② 画布内手放、**不做任何写入**的文本框
  if not G_REAL.probeLooked then
    G_REAL.probeLooked = true
    local ok, ch = pcall(function() return root:GetChild('TextProbe') end)
    print('main: [probe] 画布内手放文本框 TextProbe = ' ..
      ((ok and ch ~= nil) and '找到（脚本不会碰它，只观察它是否显示）' or '未找到（可在界面画布里放一个文本框并命名为 TextProbe）'))
  end
  -- ③ 脚本实例化 + 写入的文本框（四种对照）
  local base = G_REAL.probePool or {}
  G_REAL.probePool = base
  local cases = {
    { 'ABC123 脚本写入 / 左对齐 / 不缩', 80, 100, 480, 16, C_WHITE, 'Left', 16 },
    { 'ABC123 脚本写入 / 居中 / 不缩', 80, 140, 480, 16, C_WHITE, 'Middle', 16 },
    { '测试ABC123 中文', 80, 180, 480, 16, C_WHITE, 'Left', 16 },
    { 'ABC123 大字号 40', 80, 240, 480, 40, C_WHITE, 'Left', 40 },
  }
  for i = 1, #cases do
    local c = base[i]
    if c == nil then c = take('text'); base[i] = c end
    if c ~= nil then
      local k = cases[i]
      putText(c, k[1], k[2], k[3], k[4], k[5], k[6], k[7], k[8])
    end
  end
  if not G_REAL.probeLogged then
    G_REAL.probeLogged = true
    local c = base[1]
    if c ~= nil then
      local function rd(kk) local ok, v = pcall(function() return c[kk] end); if ok and v ~= nil then return tostring(v) end return '?' end
      print('main: [probe] 实例文本框回读 text="' .. rd('text') .. '" fontSize=' .. rd('fontSize')
        .. ' min=' .. rd('minimumFontSize') .. ' adaptive=' .. rd('adaptiveFontSize')
        .. ' align=' .. rd('horizontalAlignment') .. ' vAlign=' .. rd('verticalAlignment')
        .. ' fontColor=' .. rd('fontColor') .. ' bgColor=' .. rd('bgColor'))
      G_REAL.dumpGeom(c, 'probe-text')
    end
  end
  frameEnd()
end

function M.OnLevelUpdate(dt, fromUI)
  frame = frame + 1
  if G_REAL.cfg.textProbe then return textProbeFrame() end
  local cmds
  if mode == 'core' and state then
    -- 相位一变，触摸端的「待确认选中」就作废（否则跨状态会把不相干的项当成已选中过）
    if state.state ~= pendingPhase then
      pendingPhase = state.state
      clearPending()
    end
    local c, x = consumeEdges()
    if applyPointer() then c = false end     -- 点击已被界面消费时不再另外发确认
    input.confirm, input.cancel = c, x
    -- 【2026-10-09 用户口径】ESC **不发任何信号**（时间未到自行退出 = 系统的"未完成"，不需要处理）。
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
    -- 蓝魂回合（R6 / 最终回合第一段：pattern='blue_soul'，core 把 soul.mode 设成 'blue'）：
    -- core 的语义是「蓝魂只读左右移动，跳跃归确认键」（Game:applyInput：e.confirm + mode=='blue' → jump）。
    -- 这里在**适配层**补两件事，core 一行都不改：
    --   ① 「上」的**按下沿** → core.jump(g)（core 导出了 M.jump）。于是摇杆上推 / W 都能跳，
    --      且只有边沿触发一次 —— 按住不会连跳（core.jump 自己也要求 grounded）。
    --   ② 交给 core 的 up/down 掩掉：core 的移动段对 up/down 一样吃（Game:update 里 vy），
    --      不掩的话蓝魂按住上会"飘"，与「只读左右」的语义不符。
    -- 红魂（red）完全不走这一支：「上」照旧是正常上移，W 不会触发跳跃。
    local blue = (state.state == 'enemy') and state.soul ~= nil and state.soul.mode == 'blue'
    local coreInput = input
    if blue then
      -- 【2026-10-06 依据 blue_soul.lua / 原作 PlayerMovement】
      --   ① 跳跃键 = **与重力反向的那个键**（dir=1南→上；dir=0东→左；dir=2西→右；dir=3北→下）
      --   ② 反重力方向给 180px/s 冲量（core 的 Game:jump 里做）
      --   ③ 上/下键**必须透传**给 core —— 竖直重力下它们是跳跃键（core 的横向只读左右，不会误用），
      --      水平重力下它们就是**横向移动键**（旧实现把 up/down 掩成 false →
      --      终盘蓝心向右坠落时上下键完全没反应，用户报的「横向没法移动」就是这个）。
      local JKEY = { [0] = 'left', [1] = 'up', [2] = 'right', [3] = 'down' }
      local jk = JKEY[state.soul.dir or 1] or 'up'
      local jNow = input[jk] and true or false
      if jNow and not prevJumpKey then
        pcall(function() core.jump(state) end)
        print('main: 蓝魂跳跃（' .. jk .. ' 按下沿 → core.jump，dir=' .. tostring(state.soul.dir) .. '）')
      end
      prevJumpKey = jNow
      coreInput = { left = input.left, right = input.right, up = input.up, down = input.down,
                    -- 【J5】确认键也算「按住跳跃」：只给按下沿会被同帧物理剪断（灵魂原地落回）
                    jumpHeld = (jNow or confirmHeld),
                    confirm = input.confirm, cancel = input.cancel }
    end
    local ok, out = pcall(function() return core.update(state, coreInput, dt) end)
    requestSettlement()
    -- 战斗 BGM：core 在 Game:start()（开局 / 重开）里把 runSeq +1 → 这里从头播。
    -- 整场循环由 music 模块内部完成；结算在 requestSettlement() 里停。
    if state.runSeq ~= lastRunSeq then
      lastRunSeq = state.runSeq
      if music then music.start() end
    end
    -- 【诊断】服务端变量探针：每 2 秒读一次 Level 自定义变量，值一变就打一行 ——
    -- 用来从**客户端日志**判断服务端节点图跑到了哪一步（计时器 / SettleReady / 去重标记）。
    -- 打不出或打出 '?（读不到/未声明）' ⇒ 变量没声明或名字不对 ⇒ 节点图那一步没跑。
    G_REAL.varProbeT = (G_REAL.varProbeT or 0) + dt
    if G_REAL.varProbeT >= 2 then
      G_REAL.varProbeT = 0
      local vars = G_REAL.cfg.probeVars
      if type(vars) == 'table' then
        G_REAL.varSeen = G_REAL.varSeen or {}
        for _, vn in ipairs(vars) do
          local okV, val = pcall(function() return game.GetGlobalCustomVariableValue('Level', vn) end)
          val = okV and tostring(val) or '?（读不到/未声明）'
          if G_REAL.varSeen[vn] ~= val then
            G_REAL.varSeen[vn] = val
            print(string.format('main: [var] %s = %s', tostring(vn), val))
          end
        end
      end
    end
    if music then music.update(dt) end
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

-- ---------------------------------------------------------------- 沙箱生命周期（清理）
-- 输入状态复位：OnDisable / OnDestroy / 重新启用时都要清 —— 残留的"按住"会让灵魂一直朝一个方向走。
function M.clearInput()
  input.left, input.right, input.up, input.down = false, false, false, false
  input.confirm, input.cancel = false, false
  edgeConfirm, edgeCancel = false, false
  confirmHeld = false
  titlePrevL, titlePrevR = false, false
  prevJumpKey = false
  joy.active, joy.dx, joy.dy, joy.kx, joy.ky = false, 0, 0, 0, 0
  owned.holds.confirm, owned.holds.cancel = {}, {}
  ptr.down, ptr.moved, ptr.tapPending = false, false, false
  clearPending()
  -- core 靠 prevKeys 判按下沿；清空等价于"全没按"，不会误触发跳跃（见 Game:applyInput）。
  if state then state.keys, state.prevKeys = {}, {} end
end

function M.OnDisable()
  -- 【诊断】关卡被暂停/结束（服务端执行"结算关卡"或玩家离开时，客户端脚本会被暂停/销毁）
  local sinceEsc = (frame or 0) - (G_REAL.escFrame or -99999)
  print('main: [lifecycle] OnDisable' .. (sinceEsc <= 60
    and '（疑似【玩家 ESC 强退】—— 不能当作服务端结算的证据）'
    or '（关卡暂停或结束）'))
  owned.enabled = false
  M.clearInput()
  if music then pcall(function() music.stop(); music.stopEffects() end) end
end

function M.OnEnable()
  owned.enabled = true
  if owned.started then M.clearInput() end
end

-- 卸载：摘掉键盘/游标监听 + 销毁**自建**控件；宿主 root 不是我们建的，绝不能销毁。
function M.OnDestroy()
  -- 【诊断】脚本被销毁 —— 症状解读：
  --   点「结 算」后出现这行 ⇒ 服务端**确实执行了结算/结束关卡**（节点图在跑）
  --   一直没有这行 ⇒ 服务端没有结算（信号没收到 / 图没跑到"结算关卡"）
  local sinceEsc2 = (frame or 0) - (G_REAL.escFrame or -99999)
  print('main: [lifecycle] OnDestroy' .. (sinceEsc2 <= 60
    and '（疑似【玩家 ESC 强退】—— 不能当作服务端结算的证据）'
    or '（若紧跟在点「结 算」之后，才是服务端结算/结束关卡）'))
  M.OnDisable()
  if root then
    for _, l in ipairs(owned.keys) do
      pcall(function() root:RemoveKeyEventListener(l.name, l.cb) end)
    end
  end
  for _, l in ipairs(owned.cursors) do
    pcall(function() (l.c or cursorArea):RemoveCursorEventListener(l.name, l.cb) end)
  end
  if cursorArea then pcall(function() cursorArea:RemoveAllCursorEventListeners() end) end
  -- 【真机日志 2026-10-08】销毁阶段**不能**再调 DestroyClientUIControl：
  --   「客户端控件生命周期处于创建或销毁时，无法调用 DestroyClientUIControl」
  -- 我们建的控件都挂在宿主 root 下，容器销毁时引擎会一并回收 → 这里只清引用，不主动销毁。
  owned.controls, owned.keys, owned.cursors = {}, {}, {}
  owned.started = false
  pool, memo = {}, {}
  state = nil
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
  if M and type(M[name]) == 'function' then
    local ok, err = pcall(M[name], ...)
    if not ok then print('boot: ' .. name .. ' 出错 :: ' .. tostring(err)) end
  end
end
function OnInit() call('OnInit') end
function OnEnable() call('OnEnable') end
function OnStart() call('OnStart') end
function OnUpdate(dt) call('OnUpdate', dt) end
function OnLevelUpdate(dt) call('OnLevelUpdate', dt) end
function OnDisable() call('OnDisable') end
function OnDestroy() call('OnDestroy') end
