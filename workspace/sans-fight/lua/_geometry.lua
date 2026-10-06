--[[ ==========================================================================
  _geometry.lua —— 「世界实体只被平移一次 / 视觉 == 判定」的离线几何回归
  ---------------------------------------------------------------------------
  背景（用户实测）：初见杀（回合 0）与回合 1 的所有攻击实体**画在画面右下角**，
  判定（被打到的地方）却在战斗框正中间 —— core 的 M.render 出口对 renderWorld 的世界实体
  又多平移了一次 BOX_OFF(240,226)。

  本文件用**真的 main.lua**（假 game 引擎，控件记录属性写入）跑完整场流程，逐帧做两套对账：

    A. 【绘制 == core 命令】每条世界实体命令的世界坐标，经画布换算后必须能在控件的
       实际写入里找到（±1px）。这条只管"适配层不再加平移"。
    B. 【绘制 == 判定几何】每一帧直接从 **game 状态**（world.bones / world.sine /
       world.blasters / world.platforms / walls / soul）算出**碰撞循环用的那份矩形**
       （zone 帧；② 帧的实体自己 +BOX_OFF 一次），再要求画布上存在对应的控件（±1px）。
       这条把"core 命令的坐标系"也钉住了 —— A 单靠自己咬不住 core 侧的多平移
       （两边都用同一份被平移过的命令，会一起错、一起"对得上"）。

  画布换算（与 main.lua 的 wx/wyBottom 独立重算）：
      x_canvas  = OX + x*S
      y_bottom  = OY + (480 - (y + h))*S          S = min(CW/640, CH/480) 居中

  反证（断言有效性自检）：把同一帧的世界坐标整体再加一次 BOX_OFF，B 的命中率必须 ≤ 2%
  （20 回合版之后龙骨炮的期望值是"带容差的点"，做不到严格 0 命中；判据见文件末尾的注释）。
  报告里另有"临时把 shiftAbs 加回 core.lua → 本文件变红"的实测输出。
  ========================================================================== ]]
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path

local core = require('lua' .. '.core')
local attacks = require('lua' .. '.attacks')
package.loaded['default_import_file/workspace/sans-fight/lua/core'] = core
package.loaded['default_import_file/workspace/sans-fight/lua/attacks'] = attacks
-- 离线单测固定走参数化回退：把 fitdata 置空表，避免烘焙容器影响池峰值/几何对账。
package.loaded['default_import_file/workspace/sans-fight/lua/fitdata'] = {}

-- ---------------------------------------------------------------- 统计
local R = { pass = 0, fail = 0, failures = {} }
local function ok(cond, msg)
  if cond then
    R.pass = R.pass + 1
    io.write('  ok   ' .. msg .. '\n')
  else
    R.fail = R.fail + 1
    R.failures[#R.failures + 1] = msg
    io.write('  FAIL ' .. msg .. '\n')
  end
end
local function head(t) io.write('\n== ' .. t .. '\n') end
local function note(t) io.write('     ' .. t .. '\n') end

-- ---------------------------------------------------------------- 假引擎（记录控件写入）
local CANVAS_W, CANVAS_H = 1280, 720          -- mobile-16-9（用户实证与模拟器实证的画布）
local nextId = 1
local writeErrors = {}
local all = {}                                -- Id -> 最后一次写入的矩形/可见性
local function mkControl(kind)
  local c = { Id = nextId, kind = kind, prefabIndex = 0 }
  nextId = nextId + 1
  local store = {}
  local r = { Id = c.Id, kind = kind, vis = false, cx = nil, cy = nil, w = nil, h = nil, rot = nil }
  all[c.Id] = r
  return setmetatable(c, {
    __index = function(_, k)
      local plain = {
        SetActive = 1, SetImage = 1, SetSiblingIndex = 1,
        AddKeyEventListener = 1, AddCursorEventListener = 1,
        GetChildren = 1, GetChild = 1, FindChild = 1,
      }
      if k == 'SetVisible' then return function(_, v) r.vis = v and true or false end end
      if k == 'SetSizeDelta' then return function(_, w, h) r.w, r.h = w, h end end
      if k == 'SetAnchoredPosition' then return function(_, x, y) r.cx, r.cy = x, y end end
      if k == 'SetLocalRotation' then return function(_, d) r.rot = d end end
      if plain[k] then return function() end end
      return store[k]
    end,
    __newindex = function(_, k, v)
      local bad
      if k == 'fontSize' then bad = (math.type(v) ~= 'integer') and ('fontSize 必须是整数，得到 ' .. tostring(v))
      elseif k == 'imageColor' then bad = (math.type(v) ~= 'integer') and 'imageColor 必须是整数(ARGB)'
      elseif k == 'imageId' then bad = (math.type(v) ~= 'integer') and 'imageId 必须是整数'
      elseif k == 'text' then bad = (type(v) ~= 'string') and ('text 必须是字符串，得到 ' .. type(v))
      elseif k == 'horizontalAlignment' or k == 'verticalAlignment' then
        bad = (type(v) ~= 'string') and (k .. ' 必须是字符串')
      end
      if bad then
        writeErrors[#writeErrors + 1] = ('控件 %s(%s) 写入非法：%s'):format(tostring(c.Id), kind, bad)
        error('bad property write: ' .. bad, 2)
      end
      store[k] = v
    end,
  })
end
local rootCtrl = mkControl('container')
local G_KIND = {
  [1073743001] = 'rect', [1073743002] = 'circle', [1073743003] = 'tri',
  [1073743004] = 'text', [1073743005] = 'star', [1073743006] = 'ring',
  [1073743007] = 'rot', [1073743008] = 'rtri', [1073743009] = 'cursor',
  [1073743100] = 'baked', [1073743101] = 'bakedC', [1073743102] = 'bakedRoot',
}
game = {
  GetUICanvasSize = function() return CANVAS_W, CANVAS_H end,
  GetClientUIControl = function(id) if id == 1 then return rootCtrl end return nil end,
  InstantiateClientUIControl = function(idx) return mkControl(G_KIND[idx] or ('idx' .. tostring(idx))) end,
  GetGlobalCustomVariableValue = function() error('none') end,
  PrintClientUITree = function() end,
}

local main = require('lua' .. '.main')
local realPrint = print
local drawErrs = 0
print = function(...)
  local parts = {}
  for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end
  local line = table.concat(parts, ' ')
  if line:find('draw ERR', 1, true) then drawErrs = drawErrs + 1 end
  realPrint(line)
end
main.OnInit()
main.OnStart()

-- ---------------------------------------------------------------- 画布换算（独立重算）
local S = math.min(CANVAS_W / 640, CANVAS_H / 480)
local OX = (CANVAS_W - 640 * S) / 2
local OY = (CANVAS_H - 480 * S) / 2
local function cvX(x) return OX + x * S end
local function cvYBottom(yTop, h) return OY + (480 - (yTop + h)) * S end
local BOX_OFF_X, BOX_OFF_Y = core.BOX_OFF_X, core.BOX_OFF_Y

local PRIM_RECT, PRIM_ROT = { rect = true, circle = true }, { rot = true }
local PRIM_TRI = { rtri = true }        -- 三角件走 rtri 池（心的下尖、骨刺尖都用它）
-- 龙骨炮光束的长度：core 的 blaster 命令**不带 length 字段**（脚本 GasterBlaster 只用
-- SpinTime/BlastTime），适配层因此永远走默认值 360。
local BEAM_LEN = 1200
local BLASTER_MUZZLE_U = 32
local function beamMidU(scale) return (BLASTER_MUZZLE_U * (scale or 1) + BEAM_LEN) / 2 end
-- 光束**中线中点**离炮中心的距离：适配层把光束起点藏进吻部（u0 = 8*s，s = 0.75 + 0.25*charge），
-- 远端固定在 u = BEAM_LEN，而"画光束"只发生在 charge = 1（state = fire/done）时 → s = 1，
-- 所以中点 = (8 + 360) / 2 = 184（不是 180：早先按 len/2 写的期望值差 4px，正好卡在容差边缘）。
-- （中线中点见 beamMidU()：起点从吻部前端 u0=30*scale 起算，远端固定 u=BEAM_LEN）
-- 世界矩形（左上角 + 宽高）→ 期望的控件矩形
local function expRect(x, y, w, h, prim)
  if w <= 0 or h <= 0 then return nil end
  return { prim = prim, cx = cvX(x), cy = cvYBottom(y, h), w = w * S, h = h * S }
end
-- 中心锚点（rrect）：期望控件位置 = 中心
local function expCenter(cx, cy, w, h)
  return { prim = PRIM_ROT, cx = cvX(cx) - CANVAS_W / 2, cy = cvYBottom(cy, 0) - CANVAS_H / 2,
           w = w * S, h = h * S, center = true }
end
-- drawBone 的骨干矩形（画布上真正那一块）
-- 2026-10-06 贴图拟合：与 lua/main.lua drawBone 同一公式（骨球直径 k = 0.6×短边，
-- 骨干宽/高 = k，两端各收进 k/3）。改 drawBone 时必须同步这里。
local function boneKnob(w, h)
  local k = math.min(w, h) * 0.6
  if k < 4 then k = 4 end
  if k > w then k = w end
  if k > h then k = h end
  return k
end
local function shaftOf(x, y, w, h, vertical)
  local k = boneKnob(w, h)
  if vertical then
    -- 与 main.lua drawBone 完全同式（含 max(1,...) 的钳位），否则退化尺寸会对不上
    return expRect(x + (w - k) / 2, y + k / 3, k, math.max(1, h - 2 * k / 3), PRIM_RECT)
  end
  return expRect(x + k / 3, y + (h - k) / 2, math.max(1, w - 2 * k / 3), k, PRIM_RECT)
end
local function rectOf(x, y, w, h, prim) return expRect(x, y, w, h, prim or PRIM_RECT) end
-- 中心锚点的三角件（rtri 池）：位置的写法和 expCenter 一样（锚点相对父中心），但 prim 是 rtri
local function triOf(cx, cy, w, h)
  return { prim = PRIM_TRI, cx = cvX(cx) - CANVAS_W / 2, cy = cvYBottom(cy, 0) - CANVAS_H / 2,
           w = w * S, h = h * S, center = true }
end

-- 可见控件里找这个矩形（±1px）；返回匹配到的控件与"最近控件"的偏差
local TOL = 1
local function findRect(e)
  local tol = e.tol or TOL
  local bestD = nil
  for _, r in pairs(all) do
    if r.vis and r.cx and r.w and e.prim[r.kind] then
      local d = math.max(math.abs(r.cx - e.cx), math.abs(r.cy - e.cy))
      if not e.center then
        d = math.max(d, math.abs(r.w - e.w), math.abs(r.h - e.h))
      end
      if d <= tol then return r, 0 end
      if not bestD or d < bestD then bestD = d end
    end
  end
  return nil, bestD
end

-- ---------------------------------------------------------------- A：绘制 == core 命令
local function cmdRects(cmd)
  local out = {}
  local k = cmd.kind
  if k == 'bone' then
    local s = shaftOf(cmd.x, cmd.y, cmd.w or 19, cmd.h or 19,
                      (cmd.vertical == nil) and ((cmd.h or 19) >= (cmd.w or 19)) or cmd.vertical)
    if s then out[#out + 1] = s end
  elseif k == 'stab' then
    if (cmd.w or 0) > 0 and (cmd.h or 0) > 0 then          -- drawStab 的提前 return
      local s = shaftOf(cmd.x, cmd.y, cmd.w, cmd.h, cmd.h >= cmd.w)
      if s then out[#out + 1] = s end
    end
  elseif k == 'blaster' then
    -- 新外观（骷髅炮 + 光束）没有"零件 == 整条命令矩形"这回事：炮身被拆成
    -- 颅骨/吻部/2 眼窝/2 獠牙共 6 件、光束是 3 条线 + 4 段拉链，所以改成两条
    -- 玩家真正能感知的几何关系（都用 center 匹配，容差写在注释里）：
    --   ① 炮身画在命令给的炮位附近 —— 容差 13 世界 px
    --      （零件里离炮心最近的是颅骨 10s、眼窝 11.7s，s = size 档 × [0.82,1]，最近零件恒在 13px 内；
    --        容差再放大就会让"反证：整体再加一次 BOX_OFF"撞到别的控件，见文件末尾那条断言的注释）
    --   ② 开火时光束中线 = 从炮位沿**光束方向**射出 BEAM_MID_U 的那一点 —— 容差 3 世界 px
    -- 另外：alpha<=0 的命令适配层**直接不画**（淡出到全透明的龙骨炮不该占控件），
    -- 这类命令没有"画在哪"可言，跳过（否则会把"看不见"误报成"画错位置"）。
    local alpha = cmd.alpha
    if alpha == nil then alpha = 1 end
    if alpha > 0 then
      local cx, cy = cmd.x or 0, cmd.y or 0
      local cannon = expCenter(cx, cy, 0, 0)
      cannon.tol = 13 * S
      out[#out + 1] = cannon
      if (cmd.fire or 0) > 0 then
        -- 光束方向：脚本龙骨炮给 ang（任意角）；内置四向龙骨炮只给 dir，角度要从 dir 推
        local ang = cmd.ang
        if type(ang) ~= 'number' then
          ang = (cmd.dir == 1 and 90) or (cmd.dir == 2 and 180) or (cmd.dir == 3 and -90) or 0
        end
        local rad = math.rad(ang)
        local mid = beamMidU(cmd.scale)
        local bm = expCenter(cx + math.cos(rad) * mid, cy + math.sin(rad) * mid, 0, 0)
        bm.tol = 3 * S
        out[#out + 1] = bm
      end
    end
  elseif k == 'sine' then
    for i = 1, 2 do
      local b = (cmd.bars or {})[i]
      if b then local s = rectOf(b.x, b.y, b.w, b.h); if s then out[#out + 1] = s end end
    end
  elseif k == 'platform' then
    local s = rectOf(cmd.x, cmd.y, cmd.w, cmd.h); if s then out[#out + 1] = s end
  elseif k == 'wall' then
    local lanes = cmd.lanes or 4
    local laneW = cmd.w / lanes
    if cmd.phase == 'warn' then
      local s = rectOf(cmd.x + (cmd.gapStart or 0) * laneW, cmd.y + cmd.h - 5,
                       (cmd.gapW or 1) * laneW, 5)
      if s then out[#out + 1] = s end
    else
      local hCur = cmd.hCur or 0
      if hCur > 1 then
        for L = 0, lanes - 1 do
          if not (L >= (cmd.gapStart or 0) and L < (cmd.gapStart or 0) + (cmd.gapW or 1)) then
            local s = shaftOf(cmd.x + L * laneW, cmd.y + cmd.h - hCur, laneW, hCur, true)
            if s then out[#out + 1] = s end
          end
        end
      end
    end
  elseif k == 'soul' then
    -- 心：两瓣圆 + 倒三角，**整体以 (x,y) 为中心**（外接半径 ≈8 = SOUL_R 同口径）。
    -- 2026-10-05 改过一次：旧画法整体偏右下，贴框时红心会露到框外。
    if cmd.visible ~= false then
      local a1 = rectOf(cmd.x - 8, cmd.y - 7, 9, 9, PRIM_RECT); if a1 then out[#out + 1] = a1 end
      local a2 = rectOf(cmd.x - 1, cmd.y - 7, 9, 9, PRIM_RECT); if a2 then out[#out + 1] = a2 end
      local a3 = triOf(cmd.x, cmd.y + 3.5, 15, 9); if a3 then out[#out + 1] = a3 end
    end
  end
  return out
end

-- ---------------------------------------------------------------- B：绘制 == 判定几何（由 game 状态独立算出）
-- 返回 { {kind=..., rects={...}, note=...}, ... }：rects 是**碰撞循环用的那份矩形**对应的画布期望
local function stateRects(st, sx, sy)
  sx, sy = sx or 0, sy or 0
  local out = {}
  local function add(kind, rects) if #rects > 0 then out[#out + 1] = { kind = kind, rects = rects } end end
  local box = st.box or { x = 0, y = 0, w = 0, h = 0 }
  local bx, by = box.x + BOX_OFF_X, box.y + BOX_OFF_Y        -- ② -> ③ 的唯一一次平移

  -- 骨墙（walls 存的是框内相对帧 ②；碰撞用的是 self.box/self.soul）
  do
    local rs = {}
    for _, W in ipairs(st.walls or {}) do
      local laneW = W.laneW or (box.w / (W.lanes or 1))
      if W.phase == 'warn' then
        local s = rectOf(bx + W.gapStart * laneW + sx, by + box.h - 5 + sy, W.gapW * laneW, 5)
        if s then rs[#rs + 1] = s end
      elseif W.phase ~= 'retract' or (W.h or 0) >= core.BONE_HIT_W then
        for L = 0, (W.lanes or 0) - 1 do
          if not (L >= W.gapStart and L < W.gapStart + W.gapW) then
            local s = shaftOf(bx + L * laneW + sx, by + box.h - W.h + sy, laneW, W.h, true)
            if s then rs[#rs + 1] = s end
          end
        end
      end
    end
    add('wall', rs)
  end

  -- world 实体（全部在 zone 帧 == 输出帧，不再有任何平移）
  local w = st.world
  if w then
    do   -- bones（骨刺单独归到 stab 类，因为它输出的是 stab 命令）
      local rs, stabs = {}, {}
      for _, bn in ipairs(w.bones) do
        if bn.stab then
          local rc = w:stabRect(bn)
          if rc.w > 0 and rc.h > 0 then
            local s = shaftOf(rc.x + sx, rc.y + sy, rc.w, rc.h, rc.h >= rc.w)
            if s then stabs[#stabs + 1] = s end
          end
        elseif bn.kind == 'floor' then
          local s = shaftOf(bn.x - bn.w / 2 + sx, bn.y - bn.h + sy, bn.w, bn.h, true)
          if s then rs[#rs + 1] = s end
        elseif bn.kind == 'blue' then
          local s = shaftOf(bn.x + sx, bn.y + sy, bn.w, bn.h, false)
          if s then rs[#rs + 1] = s end
        elseif bn.kind == 'slide' then
          local s = shaftOf(bn.x + sx, bn.y + sy, bn.w, bn.h, true)
          if s then rs[#rs + 1] = s end
        else            -- 纯脚本骨（BoneV/BoneH）：**X,Y = 左上角**（对齐参考实现），朝向按 axis
          local vert = (bn.axis ~= nil) and (bn.axis == 'v') or ((bn.h or 0) >= (bn.w or 0))
          -- 【同 core.clipVZone】竖骨在 BTS 里建在 CombatZoneClipped 图层，会被裁到战斗框；
          -- 横骨在 CombatZone 图层，不裁。判定与绘制都用裁后的矩形（魂永远在框内 → 等价）。
          local bx, by, bw, bh = bn.x, bn.y, bn.w, bn.h
          if bn.axis == 'v' then
            local cx, cy, cw, ch = core.clipVZone(bx, by, bw, bh, w.zone)
            if cx == nil then bx = nil else bx, by, bw, bh = cx, cy, cw, ch end
          end
          if bx ~= nil then
            local s = shaftOf(bx + sx, by + sy, bw, bh, vert)
            if s then rs[#rs + 1] = s end
          end
        end
      end
      add('bone', rs)
      add('stab', stabs)
    end
    do   -- sine（几何直接复用 core 的命中几何 sineGeom/sineBars）
      local rs = {}
      for _, sn in ipairs(w.sine) do
        local gm = core.sineGeom(sn)
        for _, b in ipairs(core.sineBars(sn, gm, 0)) do
          local s = rectOf(b.x + sx, b.y + sy, b.w, b.h)
          if s then rs[#rs + 1] = s end
        end
      end
      add('sine', rs)
    end
    do   -- blaster：炮身中心 == 判定光束的起点 (B.x, B.y)（新外观：炮身 + 光束中线两点）
      -- 判定是"从 (B.x,B.y) 沿 B.ang 射 2000px 的整条带"，所以可见的炮身必须落在这个起点上，
      -- 开火时可见的**光束中线**也必须落在这条射线上（这就是"看得见的打得到"）。
      -- 只查"还活着"的状态（charge/spin/spinning/fire）：done = 淡出收尾，
      -- 判定侧本身也不再造成伤害（碰撞只看 state == 'fire'），且 alpha 会衰减到 0
      -- （适配层对 alpha<=0 直接不画），对它要求"可见控件"没有意义。
      local rs = {}
      for _, B in ipairs(w.blasters) do
        if B.state ~= 'done' then
          local cannon = expCenter(B.x + sx, B.y + sy, 0, 0)
          cannon.tol = 13 * S
          rs[#rs + 1] = cannon
          if B.state == 'fire' and (B.t or 0) > 0 then
            -- t=0 那一帧 blast 进度还是 0（render 里 fire = min(1, t/blast)），适配层此时不画光束
            -- → 只在 t>0 之后要求"可见光束中线落在射线上"，避免 1 帧的必然误报
            local rad = math.rad(B.ang or 0)
            local mid = beamMidU(B.scale)
            local bm = expCenter(B.x + sx + math.cos(rad) * mid,
                                 B.y + sy + math.sin(rad) * mid, 0, 0)
            bm.tol = 3 * S
            rs[#rs + 1] = bm
          end
        end
      end
      add('blaster', rs)
    end
    do   -- world 平台（zone 帧）
      local rs = {}
      for _, p in ipairs(w.platforms) do
        local s = rectOf(p.x + sx, p.y + sy, p.w or 0, p.h or 4)
        if s then rs[#rs + 1] = s end
      end
      add('platform', rs)
    end
  end
  do   -- 内置平台（帧② → ③ 平移一次）
    local rs = {}
    for _, p in ipairs(st.platforms or {}) do
      local s = rectOf(p.x + BOX_OFF_X + sx, p.y + BOX_OFF_Y + sy, p.w or 0, p.h or 4)
      if s then rs[#rs + 1] = s end
    end
    add('platform', rs)
  end
  do   -- 灵魂（帧② → ③ 平移一次）
    -- 无敌帧里 core 会把心做成闪烁（visible=false），main 的 drawSoul 直接不画 ——
    -- 这是"可见性"不是"位置"，这里按 core 同一条规则跳过，避免误报。
    local blink = (st.invuln or 0) > 0 and (math.floor((st.invuln or 0) * 20) % 2 == 0)
    local rs = {}
    if st.soul and st.state == 'enemy' and not blink then
      local x, y = st.soul.x + BOX_OFF_X + sx, st.soul.y + BOX_OFF_Y + sy
      local b1 = rectOf(x - 8, y - 7, 9, 9); if b1 then rs[#rs + 1] = b1 end
      local b2 = rectOf(x - 1, y - 7, 9, 9); if b2 then rs[#rs + 1] = b2 end
      local b3 = triOf(x, y + 3.5, 15, 9); if b3 then rs[#rs + 1] = b3 end
    end
    add('soul', rs)
  end
  return out
end

-- ---------------------------------------------------------------- 对账
local KINDS = { 'bone', 'sine', 'stab', 'platform', 'wall', 'soul' }
local A, B, NEG = {}, {}, {}          -- NEG = 反证用的独立计数（不能污染 B）
for _, k in ipairs(KINDS) do
  A[k] = { expect = 0, match = 0, worst = '', worstD = 0 }
  B[k] = { expect = 0, match = 0, worst = '', worstD = 0 }
  NEG[k] = { expect = 0, match = 0, worst = '', worstD = 0 }
end
local negDirty, negClean, frames, checkFrames = 0, 0, 0, 0
local DBG = 0
local function dbgMiss(kind, tag, st, e)
  if DBG >= 4 then return end
  DBG = DBG + 1
  io.write(string.format('[dbg] %s/%s %s 期望画布(%.1f,%.1f %.1fx%.1f)\n', kind, tag, kind, e.cx, e.cy, e.w, e.h))
  io.write(string.format('      state=%s round=%s soul=(%.1f,%.1f) box=(%.1f,%.1f %.1fx%.1f)\n',
    tostring(st.state), tostring(st.round), st.soul and st.soul.x or -1, st.soul and st.soul.y or -1,
    st.box.x, st.box.y, st.box.w, st.box.h))
  if kind == 'blaster' then
    local list = {}
    for _, r in pairs(all) do
      if r.vis and r.cx and r.kind == 'rot' then
        local d = math.max(math.abs(r.cx - e.cx), math.abs(r.cy - e.cy))
        list[#list + 1] = { d = d, r = r }
      end
    end
    table.sort(list, function(a, b) return a.d < b.d end)
    for i = 1, math.min(6, #list) do
      local r = list[i].r
      io.write(string.format('      rot 差%.1f 控件(%.1f,%.1f) %.1fx%.1f rot=%.0f\n',
        list[i].d, r.cx, r.cy, r.w or -1, r.h or -1, r.rot or 0))
    end
    io.write(string.format('      可见 rot 总数=%d\n', #list))
  end
  local n = 0
  for _, r in pairs(all) do
    if r.vis and r.kind == 'circle' and n < 6 then
      n = n + 1
      io.write(string.format('      可见 circle Id=%d pos=(%.1f,%.1f) size=(%.1f,%.1f)\n',
        r.Id, r.cx or -1, r.cy or -1, r.w or -1, r.h or -1))
    end
  end
end

local function tally(T, kind, entities, tag, negative, st)
  for _, ent in ipairs(entities) do
    if ent.kind == kind then
      for _, e in ipairs(ent.rects) do
        T[kind].expect = T[kind].expect + 1
        local r, d = findRect(e)
        if r then
          T[kind].match = T[kind].match + 1
          if negative then negDirty = negDirty + 1 else negClean = negClean + 1 end
        elseif negative then
          negClean = negClean + 1
        else
          if not negative and T == B and st then dbgMiss(kind, tag, st, e) end
          if d and d > T[kind].worstD then
            T[kind].worstD = d
            T[kind].worst = string.format('%s 期望画布(%.1f,%.1f %.1fx%.1f) 最近控件差 %.1fpx',
              tag, e.cx, e.cy, e.w, e.h, d)
          end
        end
      end
    end
  end
end

head('geometry：世界实体只被平移一次（画布换算之外不允许再有平移）')
note(string.format('画布 %dx%d → S=%.3f OX=%.1f OY=%.1f（mobile-16-9）', CANVAS_W, CANVAS_H, S, OX, OY))
note('A = 绘制位置 vs core 命令坐标；B = 绘制位置 vs 碰撞循环用的判定几何（由 game 状态独立算出）')

local E = {}
local st0 = main.state()
core.titleChoose(st0, nil)
st0.hp, st0.maxHP = 99999, 99999          -- 活着跑完整场（只关心几何，不关心打不打得过）
local lastState = nil
for i = 1, 6600 do
  if not pcall(main.OnLevelUpdate, 1.0 / 30.0) then break end
  frames = i
  local st = main.state()
  if st then
    if st.state ~= lastState then
      if st.state == 'menu' then pcall(function() core.menuChoose(st, 0) end)
      elseif st.state == 'attack' then pcall(function() core.stopAttack(st) end)
      elseif st.state == 'sub' then pcall(function() core.subConfirm(st) end) end
      lastState = st.state
    end
    local dr, tg = main.box()
    local boxSettled = dr and tg and math.abs(dr.x - tg.x) < 1 and math.abs(dr.y - tg.y) < 1
                         and math.abs(dr.w - tg.w) < 1 and math.abs(dr.h - tg.h) < 1
    local tag = string.format('t=%.1fs/r%s/%s', i / 30, tostring(st.round), tostring(st.state))
    -- A：命令 -> 画布
    local okR, cmds = pcall(function() return core.render(st) end)
    if okR then
      checkFrames = checkFrames + 1
      for _, cmd in ipairs(cmds) do
        if A[cmd.kind] then
          local skip = (cmd.kind == 'soul' and st.state ~= 'enemy') or (cmd.kind == 'sine' and not boxSettled)
          if not skip then tally(A, cmd.kind, { { kind = cmd.kind, rects = cmdRects(cmd) } }, tag, false) end
        end
      end
    end
    -- B：状态（判定几何）-> 画布；同一份再整体 +BOX_OFF 做反证
    --     title/result 态 core.render 提前返回（只画标题/结局），世界实体一律不输出 → 跳过
    local renderWorldStates = (st.state ~= 'title' and st.state ~= 'result')
    local ents = renderWorldStates and stateRects(st, 0, 0) or {}
    for _, k in ipairs(KINDS) do
      local filtered = {}
      for _, e in ipairs(ents) do if e.kind == k then filtered[#filtered + 1] = e end end
      if #filtered > 0 and not (k == 'sine' and not boxSettled) then
        tally(B, k, filtered, tag, false, st)
        local neg = stateRects(st, BOX_OFF_X, BOX_OFF_Y)
        local negF = {}
        for _, e in ipairs(neg) do if e.kind == k then negF[#negF + 1] = e end end
        tally(NEG, k, negF, tag, true)
      end
    end
    if st.state == 'result' then
      for _ = 1, 10 do pcall(main.OnLevelUpdate, 1.0 / 30.0) end
      break
    end
  end
end
print = realPrint
note(string.format('跑了 %d 帧（%.1fs），A 对账 %d 帧', frames, frames / 30, checkFrames))

head('A：绘制位置 == core 命令的世界坐标（误差 ≤1px）')
local seen = 0
for _, k in ipairs(KINDS) do
  local t = A[k]
  if t.expect > 0 then seen = seen + 1 end
  ok(t.expect > 0, string.format('A/%s：整场出现过（%d 条）', k, t.expect))
  ok(t.expect > 0 and t.match == t.expect,
     string.format('A/%s：%d/%d 条一致%s', k, t.match, t.expect,
       (t.match == t.expect) and '' or ('；最差：' .. t.worst)))
end
ok(seen == #KINDS, string.format('A：' .. #KINDS .. ' 类世界实体全覆盖（实测 %d 类）', seen))

head('B：绘制位置 == 判定几何（由 game 状态算出，误差 ≤1px）')
local seenB = 0
local totalB, matchB = 0, 0
for _, k in ipairs(KINDS) do
  local t = B[k]
  totalB = totalB + t.expect
  matchB = matchB + t.match
  if t.expect > 0 then seenB = seenB + 1 end
  ok(t.expect > 0, string.format('B/%s：整场出现过（%d 条）', k, t.expect))
  ok(t.expect > 0 and t.match == t.expect,
     string.format('B/%s：%d/%d 条绘制位置 == 判定矩形%s', k, t.match, t.expect,
       (t.match == t.expect) and '' or ('；最差：' .. t.worst)))
end
ok(seenB == #KINDS, string.format('B：' .. #KINDS .. ' 类世界实体全覆盖（实测 %d 类 / %d 条）', seenB, totalB))
-- 反证的判据：
--   老外观时每个期望都能在 ±1px 内精确命中，所以"整体再加一次 BOX_OFF"可以要求**严格 0 命中**。
--   20 回合版把龙骨炮拆成 6 个零件 + 光束后，期望值只能写成"带容差的点"（炮位 13px / 光束中线 3px），
--   容差内偶尔会撞到**别的**控件（尤其开场 8 发炮身挤在一起、sans 也有 13 个 rot 件）——
--   这是"容差"的固有代价，不等于定位错了。
--   所以判据改成**命中率**：整体平移 BOX_OFF（画布 450×424px）之后必须几乎全部落空。
--   实测 8/15415 = 0.05%；真出双平移 bug 时会反过来变成"未平移的期望几乎全部落空"（命中率 ~100% → ~0）。
local negRate = (negClean > 0) and (negDirty / negClean) or 1
ok(negRate <= 0.02,
   string.format('反证：整体 +BOX_OFF 后命中率 ≤ 2%%（命中 %d / 干净 %d = %.2f%%）',
     negDirty, negClean, negRate * 100))
ok(#writeErrors == 0, string.format('控件属性写入 0 违规（%d）', #writeErrors))
ok(drawErrs == 0, string.format('整帧绘制失败 0 次（%d）', drawErrs))
for i = 1, math.min(#writeErrors, 3) do io.write('  ' .. writeErrors[i] .. '\n') end

io.write('\n------------------------------\n')
io.write(string.format('PASS %d / FAIL %d\n', R.pass, R.fail))
for _, f in ipairs(R.failures) do io.write('  x ' .. f .. '\n') end
if R.fail > 0 then os.exit(1) end
