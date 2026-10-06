--[[ ==========================================================================
  _pool.lua —— 控件池「每类峰值用量」+「每帧控件写入」离线统计
  ---------------------------------------------------------------------------
  用途（优化工程，不加功能）：
    A. 量出 BUDGET（预分配池）该给多大：整场跑到结局，逐帧数**真正可见**的控件数
       （== main.lua 里的 used[kind]：take() 只从 1 开始顺序取，frameEnd 把 used 之后的
        全部 SetVisible(false)，所以「帧末可见数」逐类恒等于 used[kind]）。
       分 PC / 触摸两个平台各跑一遍（触摸才有摇杆的 ring），逐类取两者的较大值，
       并分别记录回合 0 / 1 / 6 / 终盘 的峰值。
    B. 量出「每帧控件写入次数」，并**独立于 main.lua 的 memo** 复算冗余写入
       （同一控件同一通道写入与上一次完全相同的值 = 无谓写入）。
    C. 顺带证明模板池里哪些 guid 从未被实例化（删除模板的依据）。

  与 _geometry.lua 同一口径：用真 main.lua + 假引擎，不注入任何 main.lua 钩子。
  闪层（rect 模板 spawn 出来的那一个）不是池成员，统计 rect 时按记录排除。
  ========================================================================== ]]
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path

local core = require('lua' .. '.core')
local attacks = require('lua' .. '.attacks')
package.loaded['default_import_file/workspace/sans-fight/lua/core'] = core
package.loaded['default_import_file/workspace/sans-fight/lua/attacks'] = attacks
-- 离线单测固定走参数化回退：把 fitdata 置空表，避免烘焙容器影响池峰值/几何对账。
-- 【_probe_pool2】保留真实 fitdata：量「全流程龙骨炮烘焙」的真实池峰值。

-- 模板池 = 7 个（优化轮删掉了整场 0 次取用的 tri 1073743003 与 star 1073743005，见 docs/prefab-pool.md）
local GUID_KIND = {
  [1073743001] = 'rect', [1073743002] = 'circle',
  [1073743004] = 'text', [1073743006] = 'ring',
  [1073743007] = 'rot', [1073743008] = 'rtri', [1073743009] = 'cursor',
  [1073743100] = 'baked', [1073743101] = 'bakedC', [1073743102] = 'bakedRoot',
}
local ALL_GUIDS = { 1073743001, 1073743002, 1073743004,
                    1073743006, 1073743007, 1073743008, 1073743009, 1073743102 }
local KINDS = { 'rect', 'circle', 'rot', 'rtri', 'ring', 'text', 'cursor' }

-- 数字 → 可比较键：%.17g 保证 double 往返唯一（避免 tostring 的 14 位有效数字把
-- 两个不同浮点看成同一个值，从而误报「冗余写入」）
local function key2(a, b) return string.format('%.17g,%.17g', a, b) end

-- ================================================================ 场景
local function scenario(mode, diff)
  local S = { mode = mode, diff = diff, recs = {}, byKind = {}, vis = {}, instByGuid = {}, instUnknown = 0,
              writes = 0, byChan = {}, red = 0, redByChan = {},
              peaks = {}, peakAt = {}, bucketPeaks = {}, bucketFrames = {},
              frames = 0, writeSeries = {}, worstFrame = 0, worstWrites = 0,
              flashFrames = 0, drawErrs = 0, cursorL = {}, keyL = {} }
  for _, k in ipairs(KINDS) do S.byKind[k] = {}; S.vis[k] = 0 end
  local nextId = 1

  local function bump(rec, chan, red)
    S.writes = S.writes + 1
    S.byChan[chan] = (S.byChan[chan] or 0) + 1
    rec.writes[chan] = (rec.writes[chan] or 0) + 1
    if red then S.red = S.red + 1; S.redByChan[chan] = (S.redByChan[chan] or 0) + 1 end
  end
  local function mark(rec, chan, v)
    local red = rec.seen[chan] and (rec.last[chan] == v)
    bump(rec, chan, red)
    rec.seen[chan] = true
    rec.last[chan] = v
  end

  local function mkControl(guid, kind, isChild)
    local rec = { id = nextId, guid = guid, kind = kind, vis = false, bakedChild = isChild and true or nil,
                  seen = {}, last = {}, writes = {} }
    nextId = nextId + 1
    S.recs[#S.recs + 1] = rec
    if S.byKind[kind] then S.byKind[kind][#S.byKind[kind] + 1] = rec end
    local store = {}
    return setmetatable({ Id = rec.id, kind = kind }, {
      __index = function(_, k)
        if k == 'SetVisible' then return function(_, v)
          v = v and true or false
          mark(rec, 'vis', v)
          if rec.vis ~= v then
            local d = v and 1 or -1
            if not rec.bakedChild then S.vis[kind] = (S.vis[kind] or 0) + d end
            if rec.bakedChild then S.visChild = (S.visChild or 0) + d end
          end
          rec.vis = v
        end end
        if k == 'SetSizeDelta' then return function(_, w, h)
          mark(rec, 'size', key2(w, h)); rec.w, rec.h = w, h
        end end
        if k == 'SetAnchoredPosition' then return function(_, x, y)
          mark(rec, 'pos', key2(x, y)); rec.cx, rec.cy = x, y
        end end
        if k == 'SetLocalRotation' then return function(_, d)
          mark(rec, 'rot', d); rec.rot = d
        end end
        if k == 'AddCursorEventListener' then return function(_, n, fn) S.cursorL[n] = fn end end
        if k == 'AddKeyEventListener' then return function(_, n, fn) S.keyL[n] = fn end end
        local plain = { SetActive = 1, SetImage = 1, SetSiblingIndex = 1,
                        GetChildren = 1, GetChild = 1, FindChild = 1,
                        SetAnchorMin = 1, SetAnchorMax = 1, SetPivot = 1, SetLocalScale = 1 }
        if plain[k] then return function() end end
        return store[k]
      end,
      __newindex = function(_, k, v)
        -- 与引擎同口径的类型校验（fontSize/imageColor/imageId 必须整数）
        local bad
        if k == 'fontSize' then bad = (math.type(v) ~= 'integer') and ('fontSize 必须是整数，得到 ' .. tostring(v))
        elseif k == 'imageColor' then bad = (math.type(v) ~= 'integer') and 'imageColor 必须是整数(ARGB)'
        elseif k == 'imageId' then bad = (math.type(v) ~= 'integer') and 'imageId 必须是整数'
        elseif k == 'text' then bad = (type(v) ~= 'string') and ('text 必须是字符串，得到 ' .. type(v)) end
        if bad then error('bad property write: ' .. bad, 2) end
        if k == 'text' or k == 'fontSize' or k == 'fontColor' or k == 'horizontalAlignment'
            or k == 'verticalAlignment' or k == 'imageColor' then
          mark(rec, k, v)
        end
        store[k] = v
      end,
    })
  end

  local rootCtrl = mkControl(0, 'container')
  game = {
    GetUICanvasSize = function() return 1280, 720 end,
    GetClientUIControl = function(id) if id == 1 then return rootCtrl end return nil end,
    InstantiateClientUIControl = function(idx, parent)
      local kind = GUID_KIND[idx]
      if not kind then S.instUnknown = S.instUnknown + 1; return nil end
      S.instByGuid[idx] = (S.instByGuid[idx] or 0) + 1
      local isChild = (parent ~= nil and parent ~= rootCtrl)
      if isChild then S.childInst = (S.childInst or 0) + 1 end
      return mkControl(idx, kind, isChild)
    end,
    GetGlobalCustomVariableValue = function()
      if diff then return diff end
      error('none')
    end,
    PrintClientUITree = function() end,
  }
  if mode == 'touch' then
    -- 设备名读法同 main.readDeviceName：'Name' 字段优先
    game.GetDevice = function() return { Name = 'Mobile', FullName = 'Enum.Device.Mobile' } end
  end

  package.loaded['lua' .. '.main'] = nil          -- 每次场景都要一份全新的 main.lua 局部状态
  local main = require('lua' .. '.main')
  local realPrint = print
  print = function(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    local msg = table.concat(parts, ' ')
    if msg:find('draw ERR', 1, true) then
      S.drawErrs = S.drawErrs + 1
      if not S.firstErr then S.firstErr = msg; realPrint('[probe2] FIRST DRAW ERR >> ' .. msg) end
    end
  end

  main.OnInit()
  local n0 = #S.recs
  main.OnStart()
  S.poolSize = #S.recs - n0
  for i = #S.recs, 1, -1 do                     -- 闪层 = OnStart 里最后实例化的 rect
    if S.recs[i].kind == 'rect' then S.flashRec = S.recs[i] break end
  end

  local function visible(kind)
    local n = S.vis[kind] or 0
    if kind == 'rect' and S.flashRec and S.flashRec.vis then n = n - 1 end
    return n
  end
  -- 诊断：可见控件里有多少是「零/负尺寸」或「全透明」的（画不出任何像素，属于可省掉的槽位）
  local function waste()
    local deg, tr = 0, 0
    for _, r in ipairs(S.recs) do
      if r.vis and r ~= S.flashRec then
        local w, h = r.w or 0, r.h or 0
        if w <= 0 or h <= 0 then deg = deg + 1 end
        local a = math.floor((r.last.imageColor or 0xFFFFFFFF) / 0x1000000) % 256
        if r.seen.imageColor and a == 0 then tr = tr + 1 end
      end
    end
    return deg, tr
  end
  -- 桶按 20 回合结构分：r0 = 见面杀、rnd = 随机抽模板的回合（1..16）、spiral = 螺旋档（17..19）
  local function bucketOf(st)
    if not st then return 'none' end
    if st.round == 0 then return 'r0' end
    if st.round >= core.SPIRAL_FROM then return 'spiral' end
    return 'rnd'
  end
  -- 画布坐标（左下原点、Y 向上）← 世界坐标（左上原点、Y 向下）
  local CW, CH = game.GetUICanvasSize()
  local SC = math.min(CW / 640, CH / 480)
  local OX, OY = (CW - 640 * SC) / 2, (CH - 480 * SC) / 2
  local function fire(name, wx, wy)
    local fn = S.cursorL[name]
    if fn then fn({ x = OX + wx * SC, y = OY + (480 - wy) * SC }) end
  end

  local st0 = main.state()
  core.titleChoose(st0, nil)
  local lastState, prevTotal, joyDown = nil, S.writes, false
  -- 16500 帧 ≈ 550s 游戏时间：20 回合整场约 250s，而离线驱动每回合的攻击条会走
  -- 6s 超时自动结算（见 _flow 的「攻击条超时」计数）→ 实测整场约 370s。
  -- 必须真的跑到 spiral 档（内部号 17..19）才量得到峰值 —— 旧版 8000 帧（266s）
  -- 只能跑到 random 档中段，spiral 桶 0 帧，量出来的预算必然漏掉最重的一段。
  for i = 1, 16500 do
    if not pcall(main.OnLevelUpdate, 1.0 / 30.0) then break end
    S.frames = i
    local st = main.state()
    if i % 1500 == 0 then
      realPrint(string.format('[probe2] frame=%d round=%s script=%s rot=%d rect=%d circle=%d',
        i, tostring(st and st.round), tostring(st and st.roundScript),
        S.vis.rot or 0, S.vis.rect or 0, S.vis.circle or 0))
    end
    if st then
      st.hp = 99999                                   -- 保住命跑完整场（不清实体，免得压低峰值）
      if st.state ~= lastState then
        if st.state == 'menu' then pcall(function() core.menuChoose(st, 0) end)
        elseif st.state == 'attack' then pcall(function() core.stopAttack(st) end)
        elseif st.state == 'sub' then pcall(function() core.subConfirm(st) end) end
        lastState = st.state
      end
      local fw = S.writes - prevTotal
      prevTotal = S.writes
      if fw > S.worstWrites then S.worstWrites, S.worstFrame = fw, i end
      S.writeSeries[#S.writeSeries + 1] = fw
      local okF, cmds = pcall(function() return core.render(st) end)
      if okF then
        for _, c in ipairs(cmds) do
          if c.kind == 'flash' and (c.alpha or 0) > 0 then S.flashFrames = S.flashFrames + 1 break end
        end
      end
      -- 触摸场景：敌方阶段一直按住左半屏拖动 => 摇杆常驻（ring + 一个 circle）
      if mode == 'touch' then
        if st.state == 'enemy' then
          if not joyDown then joyDown = true; fire('CursorDown', 120, 300) end
          fire('CursorDrag', 150, 260)
        elseif joyDown then
          joyDown = false
          fire('CursorUp', 150, 260)
        end
      end
      local b = bucketOf(st)
      S.bucketFrames[b] = (S.bucketFrames[b] or 0) + 1
      S.bucketPeaks[b] = S.bucketPeaks[b] or {}
      for _, k in ipairs(KINDS) do
        local n = visible(k)
        if n > (S.peaks[k] or 0) then
          S.peaks[k], S.peakAt[k] = n, string.format('帧%d round=%s script=%s state=%s', i, tostring(st.round),
            tostring(st.roundScript), tostring(st.state))
        end
        if n > (S.bucketPeaks[b][k] or 0) then S.bucketPeaks[b][k] = n end
      end
      local deg, tr = 0, 0  -- _probe_pool2: waste() 每帧全表扫描太慢，关闭
      if deg > (S.maxDeg or 0) then S.maxDeg = deg end
      if tr > (S.maxTr or 0) then S.maxTr = tr end
      if st.state == 'result' then
        for _ = 1, 30 do pcall(main.OnLevelUpdate, 1.0 / 30.0) end
        break
      end
    end
  end
  print = realPrint
  S.instAfterStart = 0
  for _, g in ipairs(ALL_GUIDS) do S.instAfterStart = S.instAfterStart + (S.instByGuid[g] or 0) end
  S.instAfterStart = S.instAfterStart - S.poolSize
  return S
end

-- ================================================================ 跑两个平台 × 四档难度
local SCEN = {}
SCEN[#SCEN + 1] = scenario('pc', 'original')   -- _probe_pool2: 只跑 1 个场景，快 5 倍
local PC, TC = SCEN[1], SCEN[2] or SCEN[1]        -- 写统计用「PC-normal」与「触摸-normal」

local function pct(part, all) return all > 0 and (100 * part / all) or 0 end

print('=== A. 控件池峰值（帧末可见数 == main.lua 的 used[kind]）===')
for _, Sc in ipairs(SCEN) do
  print(string.format('%-6s %-9s：%d 帧（%.1fs）draw ERR=%d 未注册 guid=%d OnStart 实例化=%d 运行期追加=%d 零尺寸峰值=%d 全透明峰值=%d',
    Sc.mode, Sc.diff, Sc.frames, Sc.frames / 30, Sc.drawErrs, Sc.instUnknown, Sc.poolSize, Sc.instAfterStart,
    Sc.maxDeg or 0, Sc.maxTr or 0))
end
print('')
print(string.format('%-8s %8s %8s %8s   %-46s %6s %6s %6s',
  'kind', 'PC峰值', '触摸峰值', '四档取大', '峰值出现处(触摸norm)', 'r0', 'rnd', 'spiral'))
local maxPeak = {}
for _, k in ipairs(KINDS) do
  local m = 0
  for _, Sc in ipairs(SCEN) do m = math.max(m, Sc.peaks[k] or 0) end
  maxPeak[k] = m
  local bp = TC.bucketPeaks
  local function bv(b) return (bp[b] and bp[b][k]) or 0 end
  print(string.format('%-8s %8d %8d %8d   %-46s %6d %6d %6d', k, PC.peaks[k] or 0, TC.peaks[k] or 0,
    m, TC.peakAt[k] or '-', bv('r0'), bv('rnd'), bv('spiral')))
end
local sum = 0
for _, k in ipairs(KINDS) do sum = sum + maxPeak[k] end
print(string.format('各类峰值之和 = %d（含四档难度取大）', sum))
local bl = {}
for _, b in ipairs({ 'r0', 'rnd', 'spiral', 'none' }) do
  bl[#bl + 1] = string.format('%s=%d帧', b, PC.bucketFrames[b] or 0)
end
print('PC 桶帧数：' .. table.concat(bl, '  '))

print('')
print('=== B. 每帧控件写入（两个场景合计）===')
local byChan, redByChan = {}, {}
for _, Sc in ipairs({ PC, TC }) do
  for c, n in pairs(Sc.byChan) do byChan[c] = (byChan[c] or 0) + n end
  for c, n in pairs(Sc.redByChan) do redByChan[c] = (redByChan[c] or 0) + n end
end
local lines = {}
for c, n in pairs(byChan) do lines[#lines + 1] = { c = c, n = n } end
table.sort(lines, function(a, b) return a.n > b.n end)
for _, l in ipairs(lines) do
  print(string.format('  %-18s %7d 次   冗余 %5d（%.2f%%）', l.c, l.n, redByChan[l.c] or 0,
    pct(redByChan[l.c] or 0, l.n)))
end
local totW = PC.writes + TC.writes
local totF = PC.frames + TC.frames
local totRed = PC.red + TC.red
local function warm(Sc)
  local t, n = 0, 0
  for i = 31, #Sc.writeSeries do t, n = t + Sc.writeSeries[i], n + 1 end
  return n > 0 and t / n or 0
end
print(string.format('  合计 %d 次 / %d 帧 = %.2f 次/帧（剔前 30 帧冷启动 %.2f 次/帧）',
  totW, totF, totW / totF, (warm(PC) + warm(TC)) / 2))
print(string.format('  冗余写入 = %d（%.2f%%）  PC 最忙帧=帧%d(%d 次) 触摸最忙帧=帧%d(%d 次)',
  totRed, pct(totRed, totW), PC.worstFrame, PC.worstWrites, TC.worstFrame, TC.worstWrites))
local tx = {}
for _, key in ipairs({ 'text', 'fontSize', 'fontColor', 'horizontalAlignment' }) do
  tx[key] = (byChan[key] or 0)
end
print(string.format('  文本类：text=%d（%.3f 次/帧） fontSize=%d fontColor=%d horizontalAlignment=%d',
  tx.text, tx.text / totF, tx.fontSize, tx.fontColor, tx.horizontalAlignment))
print(string.format('  含闪层命令的帧 = PC %d（%.1f%%）+ 触摸 %d（%.1f%%）',
  PC.flashFrames, pct(PC.flashFrames, PC.frames), TC.flashFrames, pct(TC.flashFrames, TC.frames)))

print('')
print('=== C. 模板池 guid 实际被实例化次数（0 = 该模板整场从未被取用）===')
for _, g in ipairs(ALL_GUIDS) do
  local a, b = PC.instByGuid[g] or 0, TC.instByGuid[g] or 0
  print(string.format('  %d %-7s PC=%3d 触摸=%3d', g, GUID_KIND[g], a, b))
end
local unused = {}
for _, g in ipairs(ALL_GUIDS) do
  if (PC.instByGuid[g] or 0) == 0 and (TC.instByGuid[g] or 0) == 0 then unused[#unused + 1] = GUID_KIND[g] end
end
print('整场从未被实例化的模板：' .. (#unused > 0 and table.concat(unused, ', ') or '（无）'))
print(string.format('结束：draw ERR=%d  未注册 guid 实例化=%d  冗余写入=%d',
  PC.drawErrs + TC.drawErrs, PC.instUnknown + TC.instUnknown, totRed))
