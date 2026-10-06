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
local BUILD = '2026-10-06-fitblaster'

local G = {
  rect = 1073743001, circle = 1073743002, text = 1073743004,
  ring = 1073743006, rot = 1073743007, rtri = 1073743008,
  cursor = 1073743009, baked = 1073743100, bakedC = 1073743101, bakedRoot = 1073743102,
}

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
-- 测量方法与峰值（`node tools/run-lua.mjs lua/_pool.lua`，跑整场到结局，
-- PC + 触摸两个平台 × 四档难度各一遍，逐帧统计「帧末可见控件数」——take() 顺序取号、
-- frameEnd 把 used 之后的全部隐藏，所以这个可见数逐类恒等于 used[kind] 峰值）：
--
-- 【2026-10 第二次重测：20 回合结构 + 脚本弹幕 + 新龙骨炮/sans 外观】
--     kind    峰值（四档取大）  出现在                                  本预算（+20%）
--     rect        99           round13 platforms4hard（骨阵排布修正后整排都在场内）     119
--     circle     369           round13 platforms4hard（骨头两端骨球）                    443
--     rot         76           round19 spiral3（螺旋龙骨炮 9 件/发 + sans 13 件）        106
--     rtri         2 / ring 1 / text 12 / cursor 1
--   合计 560（四档取大）→ 690（+背景板 1 + 闪层 1 = 池总量 692）。
--   ★ 2026-10-05 玩法修正轮后重测：rect 68 / circle 245 / rot 76 / rtri 3 / ring 1 / text 12 / cursor 1
--     合计 **406**（platforms4/4hard 的底骨从 60 根横扫改成 29 根静止后峰值下降）。
--     BUDGET 仍保留 690 这一档：池是启动期预分配，只要 ≥ 峰值就不运行期追加（_pool 实测 运行期追加=0），
--     多出来的空槽不参与每帧写入，留作后续加内容的余量。
--   旧预算（rect57/circle179/rot96 = 354）在 20 回合下**不够**：rect 与 circle 的峰值
--   从 47/149 涨到 70/265（回合改成全部由脚本驱动，platforms4hard 一回合就有 60 根骨头），
--   所以那一版跑整场会出现 ~98 次运行期追加（`_flow` 日志里的 `pool=453` 就是它）。
--   峰值随时序/走位不再变化（RNG 由固定 seed=20260927 驱动）。
--
-- 为什么必须 ≥ 峰值：take() 取不到时会**当场实例化**一个新控件，而新控件按创建顺序排在
-- 闪层**之后** → 它会画在全屏闪层之上，且整场会多出几十次运行期实例化
-- （旧预算 rect=168/circle=96/rot=40 下实测：帧内追加 70~93 次）。
local BUDGET = { rect = 640, circle = 443, rot = 106, rtri = 4, ring = 2, text = 15, cursor = 1 }

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
local core, attacks, state = nil, nil, nil
local fit = nil                    -- lua/fitdata.lua：exact 逐像素烘焙表（缺失时走参数化回退）
local mode = 'demo'

local input = { left = false, right = false, up = false, down = false, confirm = false, cancel = false }
local edgeConfirm, edgeCancel = false, false

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
local prevUp = false           -- 蓝魂跳跃用：「上」的按下沿检测（见 OnLevelUpdate）
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

-- 选中标记红心画在按钮左侧：心中心 (bx-16, y+bh/2)、半径 7 → 左伸约 25px
local function menuHeartRect(cmd, i)
  local bx, y, _, bh = menuButtonRect(cmd, i)
  return bx - 26, y + bh / 2 - 9, 20, 18
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
local function subRowRect(cmd, i)
  local rh = math.max(20, math.min(cmd.rowH or 26, 40))
  return cmd.x + 6, subRowTop(cmd, i) - 2, cmd.w - 12, rh + 4
end
local function subHitTest(cmd, wx, wy)
  local rows = cmd.rows or {}
  for i = 1, #rows do
    local rx, ry, rw, rh = subRowRect(cmd, i)
    if wx >= rx and wx <= rx + rw and wy >= ry and wy <= ry + rh then return i end
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

local instNILLogged = false     -- 模板缺失只打一次完整诊断，避免刷屏

local function st(c)
  local m = memo[c.Id]
  if not m then m = {}; memo[c.Id] = m end
  return m
end

local function spawn(kind)
  local ok, c = pcall(function() return game.InstantiateClientUIControl(G[kind], root) end)
  if not ok then print('main: inst ERR ' .. kind .. ' :: ' .. tostring(c)) return nil end
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
    for i = 1, n do list[i] = spawn(kind) end
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
  if m.c ~= color then c.imageColor = color; m.c = color end
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
  local parent = bakedRoot or root
  local ok, c = pcall(function() return game.InstantiateClientUIControl(rec.center and G.bakedC or G.baked, parent) end)
  if not ok or c == nil then
    if not instNILLogged then instNILLogged = true; print('main: baked 容器缺失 :: ' .. tostring(c)) end
    return nil
  end
  madeTotal = madeTotal + 1
  c:SetVisible(false)
  local spec, mirror = rec.spec, rec.mirror
  local kids = 0
  for i = 1, #spec.rects do
    local r = spec.rects[i]
    local k = game.InstantiateClientUIControl(G.rect, c)
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
      k.imageColor = r.c
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
  if color and m.fc ~= color then c.fontColor = color; m.fc = color end
  if align and m.al ~= align then c.horizontalAlignment = align; m.al = align end
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
    -- 【方案A】初见杀（cmd.bake）走**原版 block2 烘焙**（每发 ~123 个 rrect，像素级还原）；
    -- 其余关卡仍走下面的 12 件参数化（省池）。
    if cmd.bake and fit and fit.blaster_block2 then
      local key = 'Default'
      if fire > 0 then key = (fire >= 0.5) and 'fire_2' or 'fire_0' end
      local rects = fit.blaster_block2[key] or fit.blaster_block2.Default
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

  -- 砸击方向提示（保留原功能，坐标改按烘焙头/身体算）
  do
    local DIR = { HandRight = { 1, 0 }, HandDown = { 0, 1 }, HandLeft = { -1, 0 }, HandUp = { 0, -1 } }
    local d = DIR[body]
    if d then
      local L = 30
      local ax, ay = hx + hspec.w * kx + 6, hy + hspec.h * ky / 2
      local col = shade(C_HP, a)
      if d[1] ~= 0 then
        rrect(ax + d[1] * (L / 2), ay, L, 7, 0, col)
        rtri(ax + d[1] * (L + 7), ay, 14, 16, (d[1] == 1) and 270 or 90, col)
      else
        rrect(ax, ay + d[2] * (L / 2), 7, L, 0, col)
        rtri(ax, ay + d[2] * (L + 7), 16, 14, (d[2] == 1) and 180 or 0, col)
      end
    end
  end

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
  circle(x - 8, y - 7, 9, col)
  circle(x - 1, y - 7, 9, col)
  rtri(x, y + 3.5, 15, 9, 180, col)
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
  r = r or 6
  -- 同上：circle 的 (cx,cy) 是左上角，按「中心」摆要各减半个直径；三角本来就是中心锚点
  local d = r * 0.62
  circle(cx - r * 0.7 - d / 2, cy - r * 0.5 - d / 2, d, col)
  circle(cx + r * 0.7 - d / 2, cy - r * 0.5 - d / 2, d, col)
  rtri(cx, cy - r * 0.25, r * 2.3, r * 1.5, 180, col)
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
    if selected then heart(bx - 16, y + bh / 2, C_RED, 7) end
    text(it, bx, ty, w, fs, selected and C_HP or C_WHITE, 'Middle')
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
      drawBone({ x = cmd.x + L * laneW, y = cmd.y + cmd.h - hCur, w = laneW, h = hCur,
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
  for i, r in ipairs(rows) do
    local ry = subRowTop(cmd, i)
    local sel = ((cmd.index or 0) + 1 == i)
    if sel then heart(x + 18, ry + 9, C_RED, 6) end
    text(r, x + 28, ry, w - 120, 18, sel and C_HP or C_WHITE, 'Left')
    local note = cmd.notes and cmd.notes[i]
    if note and note ~= '' then text(note, x + w - 20, ry, 90, 14, C_DIM, 'Right') end
  end
  if cmd.desc and cmd.desc ~= '' then
    text(cmd.desc, x + 14, y + h - 28, w - 28, 16, C_DIM, 'Left')
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
  local kr = math.max(0, math.min(hp, tonumber(cmd.kr) or 0))
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
  local ok, err = pcall(function()
    root:AddKeyEventListener(name, function()
      if not keyDiagLogged then
        keyDiagLogged = true
        print(string.format('main: 收到按键事件 %s（若你按了 WASD 却从未出现这行，说明试玩页那层没转发按键）', name))
      end
      fn()
    end)
  end)
  if not ok then print('main: bind fail ' .. name .. ' :: ' .. tostring(err)) end
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
  for _, k in ipairs(KEY_DIRS) do
    local dir = k.dir
    bind(k.down, function() setDir(dir, true) end)
    bind(k.up, function() setDir(dir, false) end)
  end
  bind('KeyboardMenuConfirmKeyDown', function() edgeConfirm = true end)   -- Enter / 小键盘回车 / Z / 空格
  bind('KeyboardNormalAttackKeyDown', function() edgeConfirm = true end)  -- J（备用确认）
  bind('KeyboardMenuBackKeyDown', function() edgeCancel = true end)       -- Esc / X
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
    cursorArea:AddCursorEventListener('CursorDown', function(e)
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
    cursorArea:AddCursorEventListener('CursorDrag', function(e)
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
    cursorArea:AddCursorEventListener('CursorUp', function(e)
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
    cursorArea:AddCursorEventListener('CursorClick', function(e)
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
    pcall(function() core.restart(state) end)
    print('main: 点按 → 重开')
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

local function difficulty()
  local ok, v = pcall(function() return game.GetGlobalCustomVariableValue('Level', 'SansDifficulty') end)
  if ok and type(v) == 'string' and v ~= '' then return v end
  return 'normal'
end

-- （调试钩子 bootRound() 定义在文件上方「平台分流」段，这里不再重复定义）

function M.OnInit()
  root = game.GetClientUIControl(1)
  layout()
  print(string.format('main init: root=%s canvas=%.0fx%.0f scale=%.3f ox=%.1f oy=%.1f',
    tostring(root ~= nil), CW, CH, S, OX, OY))
end

function M.OnStart()
  layout()
  isTouch = detectDevice()      -- 平台分流：只认 Mobile / MobileController，其余（含读不到）按 PC
  -- 纯黑背景板：**在所有控件之前**创建 → 兄弟序天然在最底层（新实例默认置顶，先建的在下面）。
  -- 模拟器试玩页/截图里的舞台底色是宿主画的渐变，真机底色也不可控 → 背景必须由 Lua 自己糊一层。
  -- 尺寸取 **3 倍画布**居中（宽屏/超宽也不在边上露出宿主场景 —— 做法照抄 millastra-6nimmt 的
  -- scripts/build.mjs：`rect(Background, 640,360, 3840,2160)`）。
  bgPanel = spawn('rect')
  if bgPanel then
    put(bgPanel, -CW, -CH, CW * 3, CH * 3)
    tint(bgPanel, 0xFF000000)
    bgPanel:SetVisible(true)
    st(bgPanel).vis = true
  end
  -- 烘焙容器根：必须在 prewarm 之前创建 → 烘焙层在黑底之上、池控件之下。
  bakedRoot = spawn('bakedRoot')
  if bakedRoot then
    put(bakedRoot, 0, 0, 0, 0)
    bakedRoot:SetVisible(true)
    st(bakedRoot).vis = true
  end
  fit = tryLoadFit()
  prewarm()
  cursorArea = take('cursor')
  pool.cursor = nil        -- 游标区不参与每帧显隐管理，始终铺满画布接收指针
  if cursorArea then cursorArea:SetVisible(true) end
  flash = spawn('rect')
  core = tryLoadCore()
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
  if bgPanel then pcall(function() bgPanel:SetAsFirstSibling() end) end
  if flash then pcall(function() flash:SetAsLastSibling() end) end
  print(string.format('main start: build=%s device=%s touch=%s mode=%s pool=%d flash=%s cursor=%s',
    BUILD, deviceName, tostring(isTouch), mode, madeTotal, tostring(flash ~= nil), tostring(cursorArea ~= nil)))
end

function M.OnLevelUpdate(dt)
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
    input.confirm, input.cancel = c, x
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
    local upEdge = input.up and not prevUp
    prevUp = input.up
    local coreInput = input
    if blue then
      if upEdge then
        pcall(function() core.jump(state) end)
        print('main: 蓝魂跳跃（上键按下沿 → core.jump）')
      end
      coreInput = { left = input.left, right = input.right, up = false, down = false,
                    jumpHeld = input.up,          -- 变高跳：按住时长决定跳多高（core 读这个字段）
                    confirm = input.confirm, cancel = input.cancel }
    end
    local ok, out = pcall(function() return core.update(state, coreInput, dt) end)
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

