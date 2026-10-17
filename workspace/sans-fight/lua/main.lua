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
local BUILD = '2026-10-17-joy-left'   -- 心形重画/按钮框恢复(帧末置顶)/stopAttack幂等/确认键去抖/lifecycle+变量探针   -- 等距选项UI / 三项结局(含重选难度) / 橙骨 / 开局信号 / ESC请求结算 / result=Bool

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
-- 【2026-10-17 用户口径】固定摇杆**左移一个半径**：84 - JOY_R(46) = 38。
--   可用 C.joyHomeX / C.joyHomeY 覆盖（OnStart 里读；留 nil 就用这里的默认值）。
local JOY_HOME_X, JOY_HOME_Y = 38, 392      -- 世界坐标（默认位置）
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
  -- 【2026-10-14 用户口径 · 方案 A】闪烁改成透明度淡出：心**始终画**，只用 core 给的 alpha 调透明。
  --   删掉旧的 `frame % 8 < 4 → 染成 40% 白` —— 那是按**渲染帧**算的第二套相位，会和 core
  --   按秒算的相位拍频（闪得没规律），而且帧率一变闪烁速度就跟着变。
  local sa = cmd.alpha
  if sa ~= nil and sa < 1 then col = shade(col, sa) end
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
      if state and (state.state == 'title' or state.state == 'tut_ask') then
        -- 标题页 / 教程二选一：每张卡各是一条 menu 命令，画在原位（core 给的 y=210），**不**挪到框下。
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
  local askNow = (state ~= nil and state.state == 'tut_ask')      -- 【2026-10-14】教程二选一页
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
      local skip = (cmd.kind == 'box' and (titleNow or askNow))
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
        -- 只在**会读方向输入的状态**起摇杆：敌人回合 + 教程（2026-10-17 修）。
        --   ⚠ 教程复用 enemy 的物理/碰撞，但状态名是 'tutorial' —— 原来这里只写 'enemy'，
        --     导致手机端**教程里摇杆根本起不来**（表现为"固定摇杆拖不动 / 触摸像没穿透进来"）。
        -- 其它状态（菜单/子面板/攻击条/结局）仍不起摇杆：core 不读方向输入，
        -- 起了只会把点按吞掉（实测：攻击条阶段点左半屏本来该结算，却因为摇杆消费了 CursorUp 而没反应）。
        local twx, twy = toWorld(x, y)
        local canJoy = state and (state.state == 'enemy' or state.state == 'tutorial')
        if canJoy and inJoyZone(twx, twy) and not uiHit(twx, twy) then
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

-- 左上角退出：点击 → 发服务端信号（客户端没有退出 API）。
--   名字取 C.exitSignal；若填成 'SansFightSettle' 则复用现有结算节点（参数一并带上）。
function G_REAL.requestExitKick()
  local name = G_REAL.cfg.exitSignal
  if name == nil or name == '' then name = 'SansFightExit' end
  if name == 'SansFightSettle' then
    if G_REAL.sendSettleSignal then G_REAL.sendSettleSignal(true, '（左上角退出键）') end
    return
  end
  if type(game.ServerSignal) ~= 'function' then
    print('main: 退出信号不可用（当前宿主没有 game.ServerSignal）')
    return
  end
  local ok, err = pcall(function()
    local sig = game.ServerSignal(name)
    sig:SendSignal()
  end)
  if ok then print('main: 已发送退出信号 ' .. tostring(name)) else print('main: 退出信号发送失败 :: ' .. tostring(err)) end
end

-- 点按处理：同步执行（Web 端试玩 Worker 只在被轮询时推进，不能等下一帧）。
-- 返回 true 表示这次点按已被界面消费。
handleClick = function(px, py)
  if not core or not state then return false end
  local twx, twy = toWorld(px, py)
  -- 【2026-10-17 用户口径】左上角退出图标：1 分钟后出现，点它 = 发退出信号。
  --   判定用**世界坐标**，与绘制同源；触摸多给一圈容差（手指比鼠标粗）。
  -- 【2026-10-17 用户口径】图标默认**只是位置提示**（C.exitIconClickSignal = false）：
  --   点这个位置应当穿透到原生退出键，而不是被我们吞掉发信号。只有宿主版本拿不到原生键时，
  --   才把 C.exitIconClickSignal 打开当兜底。
  if G_REAL.cfg.exitIconClickSignal == true and G_REAL.exitIconShown() then
    local ex, ey, esz = G_REAL.exitIconRect()
    local pad = isTouch and 10 or 0
    if twx >= ex - pad and twx <= ex + esz + pad and twy >= ey - pad and twy <= ey + esz + pad then
      G_REAL.requestExitKick()
      return true
    end
  end
  local st = state.state
  -- 【2026-10-14】新手教程二选一：与标题页共用卡片，只是动作换成 tutChoose（触摸同样二段确认）
  if st == 'tut_ask' then
    for i = 1, #titleCards do
      local card = titleCards[i]
      if inRect(twx, twy, card.x - 8, card.y - 8, card.w + 16, card.h + 16) then
        if isTouch and not samePending('tut', i - 1) then
          local cur = state.tutAskIndex or 0
          if i - 1 ~= cur then pcall(function() core.tutAskMove(state, (i - 1) - cur) end) end
          markPending('tut', i - 1)
          print(string.format('main: 触摸点按教程选项 %d → 选中（再点一次确认）', i))
          return true
        end
        clearPending()
        pcall(function() core.tutChoose(state, i - 1) end)
        print(string.format('main: 点按教程选项 %d', i))
        return true
      end
    end
    if not isTouch then
      pcall(function() core.tutChoose(state, state.tutAskIndex or 0) end)
      print('main: 点按教程页空白 → 用当前选项')
    end
    return true
  end
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
-- 摇杆**只在会读方向输入的状态才 active**（CursorDown 里判 enemy / tutorial），
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

-- ---------------------------------------------------------------- 左上角退出图标（2026-10-17）
-- 千星原生退出键被我们的全屏 cursorArea 盖住/抢走点按 → 这里在**同一位置**画一个等效图标。
-- 客户端没有退出 API，所以点击只是**发服务端信号**（节点图「结算关卡」收尾）。
function G_REAL.exitIconShown()
  if G_REAL.cfg.exitIcon == false then return false end
  return (G_REAL.exitT or 0) >= (G_REAL.cfg.exitDelay or 60)
end
function G_REAL.exitIconRect()
  return G_REAL.cfg.exitIconX or 8, G_REAL.cfg.exitIconY or 8, G_REAL.cfg.exitIconSize or 34
end

function G_REAL.drawExitIcon()
  if not G_REAL.exitIconShown() then return end
  local x, y, sz = G_REAL.exitIconRect()
  local cx, cy = x + sz / 2, y + sz / 2
  -- 半透明底：亮背景（白框/白字）上也能看清
  local bg = circle(x, y, sz, 0x88000000)
  if bg then pcall(function() bg:SetAsLastSibling() end) end
  local rc = take('ring')
  if rc then
    put(rc, wx(x), wyBottom(y + sz), sz * S, sz * S)
    tint(rc, 0xE6FFFFFF)
    pcall(function() rc:SetAsLastSibling() end)
  end
  local barT = math.max(2, sz * 0.09)
  local a = rrect(cx, cy, sz * 0.52, barT, 45, C_WHITE)
  if a then pcall(function() a:SetAsLastSibling() end) end
  local b = rrect(cx, cy, sz * 0.52, barT, -45, C_WHITE)
  if b then pcall(function() b:SetAsLastSibling() end) end
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
  -- 【2026-10-17】按 docs/device-setup.md：两个「屏蔽穿透」必须是 **false**（允许穿透）。
  --   原来硬编码 true，会把编辑器的设置覆盖掉 → 原生退出键点不到、按键也可能收不到。
  pcall(function() root.disableKeyEventPassthrough = G_REAL.cfg.blockKeyPassthrough == true end)
  pcall(function() root.disableCursorEventPassthrough = G_REAL.cfg.blockCursorPassthrough == true end)
  pcall(function() root.showCursor = true end)
  -- 【官方文档要求】Root 必须覆盖整个画布：锚点 (0,0)-(1,1)、位置与尺寸差都为 0。
  -- 编辑器里没配的话，子控件的绝对坐标就会相对一个「小盒子」定位 —— 整幅画面缩在左下角。
  G_REAL.stretchFull(root)
  layout()
  isTouch = detectDevice()      -- 平台分流：只认 Mobile / MobileController，其余（含读不到）按 PC
  -- 【2026-10-17】固定摇杆基准点可配（真机上按手感微调，不用改代码）
  if type(G_REAL.cfg.joyHomeX) == 'number' then JOY_HOME_X = G_REAL.cfg.joyHomeX end
  if type(G_REAL.cfg.joyHomeY) == 'number' then JOY_HOME_Y = G_REAL.cfg.joyHomeY end
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
  -- 【2026-10-17 用户口径】全屏 cursorArea 会把千星原生退出键（左上角）的点按抢走。
  --   这里在光标区**顶部让出一条带**（C.cursorTopInset 世界像素）：那条带里没有光标区，
  --   点按会继续往下传 → 落到原生退出键上。左上角图标只是给玩家指位置。
  do
    local inset = G_REAL.cfg.cursorTopInset or 0
    if inset > 0 and cursorArea ~= nil then
      local padPx = inset * S
      pcall(function() cursorArea:SetAnchorMin(0, 0) end)
      pcall(function() cursorArea:SetAnchorMax(1, math.max(0, 1 - padPx / CH)) end)
      pcall(function() cursorArea:SetPivot(0.5, 0.5) end)
      pcall(function() cursorArea:SetSizeDelta(0, 0) end)
      pcall(function() cursorArea:SetAnchoredPosition(0, 0) end)
      print(string.format('main: 光标区顶部让出 %.0f 世界px → 原生退出键可点', inset))
    end
  end
  flash = spawn('rect')
  core = tryLoadCore()
  music = tryLoadMusic()
  if core then
    local ok, s = pcall(function()
      -- 【2026-10-14】新手教程：默认开启（C.tutorial = false 可跳过，排查问题时用）。
      --   **只有这里传 tutorial** —— core_selftest / _rounds / _tap 等测试自己 newGame 时不传，
      --   所以它们仍然从 title 开始，700+ 条既有断言不受影响（见实施文档 §5.3）。
      local tutOn = (G_REAL.cfg == nil) or (G_REAL.cfg.tutorial ~= false)
      return core.newTitle({ difficulty = difficulty(), scripts = attacks, hp = 92,
                             startRound = bootRound(), tutorial = tutOn })
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
  -- 【2026-10-14 用户口径】开局信号已删除：服务端不再依赖客户端发信号起计时器（服务器端已另行解决）。
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

-- 【2026-10-14 用户口径】G_REAL.sendStartSignal 已整体删除（服务器端不再依赖开局信号）。
--   保留这条注释是为了让后来的人知道「这里曾经有过一个开局信号」：
--   如果哪天又要恢复，见 git log 里 BUILD=2026-10-14-invuln-alpha 之前的版本。

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
  -- 【2026-10-17】左上角退出图标的计时：从进入关卡（OnStart 之后）开始累计。
  G_REAL.exitT = (G_REAL.exitT or 0) + (dt or 0)
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
    -- 【2026-10-14】新手教程二选一：左右选择 + 确认（复用同一对边沿变量，防连滚）
    if state.state == 'tut_ask' then
      local l, r = input.left, input.right
      if l and not titlePrevL then pcall(core.tutAskMove, state, -1) end
      if r and not titlePrevR then pcall(core.tutAskMove, state, 1) end
      titlePrevL, titlePrevR = l, r
      if c then pcall(core.tutChoose, state, state.tutAskIndex or 0) end
    end
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
    -- 【2026-10-14 修复】原来这里写死 'enemy' → **教程的蓝心小节整条适配都走不到**，后果两条：
    --   ① 「与重力反向的方向键」跳不起来（教程提示却写着要按方向键）；
    --   ② coreInput 退化成原始 input ⇒ core 的 jumpHeld 只在按下沿那一帧为真
    --      ⇒ 下一帧就被"松键截断"剪掉 ⇒ **跳跃幅度极小**（用户报的正是这条）。
    --   教程和敌人回合本来就共用同一套蓝魂物理，所以把 tutorial 一起纳入。
    local blue = (state.state == 'enemy' or state.state == 'tutorial')
                 and state.soul ~= nil and state.soul.mode == 'blue'
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
  pcall(G_REAL.drawExitIcon)   -- 左上角退出图标（进入关卡 1 分钟后出现；手机/PC 都画）
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
function M.exitIconShown() return G_REAL.exitIconShown() end   -- 退出提示图标是否已出现（回归用）
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
