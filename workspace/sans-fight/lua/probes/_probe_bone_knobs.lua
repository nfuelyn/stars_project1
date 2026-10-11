-- _probe_bone_triangle.lua —— 扫描「三角形图元压在骨头中段」的帧，按回合汇总（只读，不改任何逻辑）
-- 用法：node tools/run-lua.mjs lua/probes/_probe_bone_triangle.lua [--all-rounds]
-- 输出：每个回合一行：是否命中 / 命中帧数 / 首个命中帧的几何（三角 vs 骨头）
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local core = require('lua' .. '.core')
local attacks = require('lua' .. '.attacks')
package.loaded['default_import_file/workspace/sans-fight/lua/core'] = core
package.loaded['default_import_file/workspace/sans-fight/lua/attacks'] = attacks
package.loaded['default_import_file/workspace/sans-fight/lua/fitdata'] = {}
package.loaded['default_import_file/workspace/sans-fight/lua/textart'] = { glyphs = {} }

local CW, CH = 1280, 720
local S = math.min(CW / 640, CH / 480)
local OX, OY = (CW - 640 * S) / 2, (CH - 480 * S) / 2
local G_KIND = {
  [1073743001] = 'rect', [1073743002] = 'circle', [1073743004] = 'text',
  [1073743006] = 'ring', [1073743007] = 'rot', [1073743008] = 'rtri', [1073743009] = 'cursor',
  [1073743100] = 'baked', [1073743101] = 'bakedC', [1073743102] = 'bakedRoot',
}
local controls, nextId = {}, 1
local function mkControl(kind)
  local rec = { id = nextId, kind = kind, vis = false }
  nextId = nextId + 1
  controls[#controls + 1] = rec
  local store = {}
  return setmetatable(rec, {
    __index = function(_, k)
      if k == 'SetVisible' then return function(_, v) rec.vis = v and true or false end end
      if k == 'SetSizeDelta' then return function(_, w, h) rec.w, rec.h = w, h end end
      if k == 'SetAnchoredPosition' then return function(_, x, y) rec.cx, rec.cy = x, y end end
      if k == 'SetLocalRotation' then return function(_, x, y, z) rec.rot = z end end
      if k == 'AddKeyEventListener' then return function() end end
      if k == 'AddCursorEventListener' then return function() end end
      local plain = { SetActive = 1, SetImage = 1, SetSiblingIndex = 1, SetAnchorMin = 1, SetAnchorMax = 1,
                      SetPivot = 1, GetChildren = 1, GetChild = 1, FindChild = 1,
                      SetAsFirstSibling = 1, SetAsLastSibling = 1 }
      if plain[k] then return function() end end
      return store[k]
    end,
    __newindex = function(_, k, v) store[k] = v end,
  })
end
local rootCtrl = mkControl('container')
game = {
  GetUICanvasSize = function() return CW, CH end,
  GetClientUIControl = function(id) if id == 1 then return rootCtrl end return nil end,
  InstantiateClientUIControl = function(idx) local k = G_KIND[idx]; if not k then return nil end return mkControl(k) end,
  GetGlobalCustomVariableValue = function() error('none') end,
  PrintClientUITree = function() end,
}
script = { object = rootCtrl, EnableUpdate = function() end }
package.loaded['lua' .. '.main'] = nil
local main = require('lua' .. '.main')
-- 静音 main 的日志，只保留本探针输出
local realPrint = print
print = function() end
main.OnInit(); main.OnStart()
print = realPrint
-- ============================================================================
-- 验证：stab 命令（开局杀 / 骨刺）在屏幕上画成「骨头」而不是纯矩形
--   期望每根小骨 = 1 根收窄骨干(rect) + 4 颗骨球(circle)，骨球落在该骨 bbox 的四角。
--   和 _geometry.lua shaftOf() 同式、和 main.lua drawBone 同式。
-- 用法：node tools/run-lua.mjs lua/probes/_probe_bone_knobs.lua
--   环境变量 FRAMES=3600 控制模拟帧数（默认 3600 = 120 秒，够跑完前几回合）
-- ============================================================================
local FRAMES = tonumber(os.getenv('FRAMES') or '') or 3600
local function toCanvas(x, y, w, h) return OX + x * S, OY + (480 - (y + h)) * S, w * S, h * S end

local function knobK(w, h)
  local k = math.min(w, h) * 0.6
  if k < 4 then k = 4 end
  if k > w then k = w end
  if k > h then k = h end
  return k
end

local function nearVisible(prim, cx, cy, w, h)
  for _, c in ipairs(controls) do
    if c.kind == prim and c.vis and c.cx and c.cy and c.w then
      local d = math.max(math.abs(c.cx - cx), math.abs(c.cy - cy), math.abs(c.w - w), math.abs((c.h or w) - h))
      if d <= 1.2 then return true end
    end
  end
  return false
end

local function bonesOfStab(cmd)
  local out = {}
  local x, y, w, h = cmd.x, cmd.y, cmd.w, cmd.h
  if w == nil or h == nil or w <= 0 or h <= 0 then return out end
  local SP, BW = 13, 10
  if w >= h then
    for i = 0, math.max(1, math.ceil(w / SP)) - 1 do
      local bx = x + i * SP
      if bx < x + w then
        local bw = math.min(BW, x + w - bx)
        out[#out + 1] = { x = bx, y = y, w = bw, h = h, vertical = (h >= bw) }
      end
    end
  else
    for i = 0, math.max(1, math.ceil(h / SP)) - 1 do
      local by = y + i * SP
      if by < y + h then
        local bh = math.min(BW, y + h - by)
        out[#out + 1] = { x = x, y = by, w = w, h = bh, vertical = (bh >= w) }
      end
    end
  end
  return out
end

print('=== 骨头观感探针：stab 命令 -> 骨干 + 四骨球 ===')
local st = main.state()
pcall(function() core.titleChoose(st, nil) end)
local kindHist, stabFrames, nBones, nShaft, nKnob = {}, 0, 0, 0, 0
local shown, samples = 0, {}
local lastState = nil
for f = 1, FRAMES do
  local ok = pcall(main.OnLevelUpdate, 1.0 / 30.0)
  if not ok then print('OnLevelUpdate 出错于 frame=' .. f) break end
  st = main.state()
  if st and st.state ~= lastState then
    if st.state == 'menu' then pcall(function() core.menuChoose(st, 0) end)
    elseif st.state == 'attack' then pcall(function() core.stopAttack(st) end)
    elseif st.state == 'sub' then pcall(function() core.subConfirm(st) end) end
    lastState = st.state
  end
  local okR, cmds = pcall(function() return core.render(st) end)
  if okR and type(cmds) == 'table' then
    local sawStab = false
    for _, cmd in ipairs(cmds) do
      kindHist[cmd.kind] = (kindHist[cmd.kind] or 0) + 1
      if cmd.kind == 'stab' then
        local bs = bonesOfStab(cmd)
        if #bs > 0 then
          sawStab = true
          if shown < 6 then
            shown = shown + 1
            samples[#samples + 1] = string.format(
              '  frame=%d phase=%s 骨刺条 x=%.0f y=%.0f w=%.0f h=%.0f -> 拆成 %d 根小骨',
              f, tostring(cmd.phase), cmd.x, cmd.y, cmd.w, cmd.h, #bs)
          end
          for _, b in ipairs(bs) do
            nBones = nBones + 1
            local k = knobK(b.w, b.h)
            local sx, sy, sw, sh
            if b.vertical then
              sx, sy, sw, sh = b.x + (b.w - k) / 2, b.y + k / 3, k, math.max(1, b.h - 2 * k / 3)
            else
              sx, sy, sw, sh = b.x + k / 3, b.y + (b.h - k) / 2, math.max(1, b.w - 2 * k / 3), k
            end
            local cx, cy, cw, ch = toCanvas(sx, sy, sw, sh)
            if nearVisible('rect', cx, cy, cw, ch) then nShaft = nShaft + 1 end
            local all4 = true
            local kn = { { b.x, b.y }, { b.x + b.w - k, b.y },
                         { b.x, b.y + b.h - k }, { b.x + b.w - k, b.y + b.h - k } }
            for i = 1, 4 do
              local kx, ky, kw, kh = toCanvas(kn[i][1], kn[i][2], k, k)
              if not nearVisible('circle', kx, ky, kw, kh) then all4 = false end
            end
            if all4 then nKnob = nKnob + 1 end
          end
        end
      end
    end
    if sawStab then stabFrames = stabFrames + 1 end
  end
end

print('命令种类直方图：')
local ks = {}
for k, v in pairs(kindHist) do ks[#ks + 1] = k end
table.sort(ks)
for _, k in ipairs(ks) do print(string.format('  %-12s %d', k, kindHist[k])) end
print('')
for _, s in ipairs(samples) do print(s) end
print('')
print(string.format('stab 帧数 %d，小骨合计 %d，骨干命中 %d，四骨球就位 %d', stabFrames, nBones, nShaft, nKnob))
local pct = 0
if nBones > 0 then pct = 100 * nKnob / nBones end
print(string.format('骨球拟合率 %.1f pct', pct))
if nBones > 0 and nKnob == nBones and nShaft == nBones then print('PASS') else print('FAIL') end
