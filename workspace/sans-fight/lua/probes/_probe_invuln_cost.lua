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
local cnt = { vis = 0, pos = 0, size = 0, rot = 0, img = 0 }   -- 真实 API 调用计数
local controls, nextId = {}, 1
local function mkControl(kind)
  local rec = { id = nextId, kind = kind, vis = false }
  nextId = nextId + 1
  controls[#controls + 1] = rec
  local store = {}
  return setmetatable(rec, {
    __index = function(_, k)
      if k == 'SetVisible' then return function(_, v) cnt.vis = cnt.vis + 1; rec.vis = v and true or false end end
      if k == 'SetSizeDelta' then return function(_, w, h) cnt.size = cnt.size + 1; rec.w, rec.h = w, h end end
      if k == 'SetAnchoredPosition' then return function(_, x, y) cnt.pos = cnt.pos + 1; rec.cx, rec.cy = x, y end end
      if k == 'SetLocalRotation' then return function(_, x, y, z) cnt.rot = cnt.rot + 1; rec.rot = z end end
      if k == 'AddKeyEventListener' then return function() end end
      if k == 'AddCursorEventListener' then return function() end end
      local plain = { SetActive = 1, SetImage = 1, SetSiblingIndex = 1, SetAnchorMin = 1, SetAnchorMax = 1,
                      SetPivot = 1, GetChildren = 1, GetChild = 1, FindChild = 1,
                      SetAsFirstSibling = 1, SetAsLastSibling = 1 }
      if plain[k] then return function() end end
      return store[k]
    end,
    __newindex = function(_, k, v) if k == 'imageColor' then cnt.img = cnt.img + 1 end; store[k] = v end,
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
-- 量「无敌帧闪烁红心」的每帧代价：真实 API 调用计数 + 每帧耗时
--   替身里每个控件的 SetVisible / SetAnchoredPosition / SetSizeDelta / SetLocalRotation /
--   imageColor 写入都被真实计数（SetPos ≈ 本帧画了多少个控件，是平台侧代价的最好代理）。
--   测法：冻在一个"有骨头"的敌人回合里，对比
--     ① 完全不无敌（基线）  ② 无敌窗口内 · 画心帧  ③ 无敌窗口内 · 闪烁暗帧
-- 用法：node tools/run-lua.mjs lua/probes/_probe_invuln_cost.lua
-- ============================================================================
local DT = 1 / 30
local st = main.state()
pcall(function() core.titleChoose(st, nil) end)

-- ---- 预热：推进到"场上骨头 >= 25"的敌人回合 ----
local function drive()
  st = main.state()
  if not st then return end
  if st.state == 'menu' then pcall(function() core.menuChoose(st, 0) end)
  elseif st.state == 'attack' then pcall(function() core.stopAttack(st) end)
  elseif st.state == 'sub' then pcall(function() core.subConfirm(st) end)
  end
end
local ready = false
for i = 1, 4000 do
  pcall(main.OnLevelUpdate, DT)
  drive()
  st = main.state()
  if st and st.state == 'enemy' and st.world and #st.world.bones >= 25 then ready = true break end
end
if not ready then
  print('预热失败：没等到"骨头 >= 25"的敌人回合')
  st = main.state()
  print('  state=' .. tostring(st and st.state) .. ' round=' .. tostring(st and st.round))
end

local function frameStats(mode)
  -- mode: 'none' 不无敌 / 'blink' 持续无敌（自然衰减 → 真实闪烁）
  if mode == 'blink' and (st.invuln or 0) <= 0 then st.invuln = 0.5 end
  if mode == 'none' then st.invuln = 0 end
  st.hp, st.maxHP = 999999, 999999      -- 别死
  st.enemyDur = 1e9                     -- 别换回合
  cnt.vis, cnt.pos, cnt.size, cnt.rot, cnt.img = 0, 0, 0, 0, 0
  local t0 = os.clock()
  local ok = pcall(main.OnLevelUpdate, DT)
  local ms = (os.clock() - t0) * 1000
  local visSoul, invuln, soulAlpha = nil, false, 1
  local okR, cmds = pcall(function() return core.render(st) end)
  if okR and type(cmds) == 'table' then
    for _, c in ipairs(cmds) do
      if c.kind == 'soul' then
        visSoul = c.visible; invuln = c.invuln and true or false
        soulAlpha = c.alpha; if soulAlpha == nil then soulAlpha = 1 end
      end
    end
  end
  return { ms = ms, vis = cnt.vis, pos = cnt.pos, size = cnt.size, img = cnt.img,
           drawn = visSoul, alpha = soulAlpha, invuln = invuln,
           bones = (st.world and #st.world.bones) or 0, ok = ok }
end

local N = 400
local base, invOn, invOff, pattern = {}, {}, {}, {}
for i = 1, N do base[#base + 1] = frameStats('none') end
for i = 1, N do
  local f = frameStats('blink')
  if f.invuln and f.alpha < 1 then invOff[#invOff + 1] = f else invOn[#invOn + 1] = f end
  if i <= 60 then pattern[#pattern + 1] = (f.invuln and f.alpha < 1) and '.' or '#' end
end

local function agg(name, t)
  if #t == 0 then print(string.format('  %-20s (0 帧)', name)) return 0 end
  local sm, sv, sp, ss, si, sb = 0, 0, 0, 0, 0, 0
  for _, f in ipairs(t) do sm = sm + f.ms; sv = sv + f.vis; sp = sp + f.pos; ss = ss + f.size; si = si + f.img; sb = sb + f.bones end
  local n = #t
  print(string.format('  %-20s 帧数=%4d 每帧 %6.3f ms | 画控件(SetPos)=%7.1f SetVisible=%6.1f SetSize=%6.1f imageColor=%7.1f | 场上骨头=%5.1f',
    name, n, sm / n, sp / n, sv / n, ss / n, si / n, sb / n))
  return sm / n
end

print('')
print('=== 每帧代价对比（30fps 固定步；SetPos ≈ 本帧绘制的控件数） ===')
local b = agg('① 普通帧(不无敌)', base)
local a1 = agg('② 无敌·不淡帧', invOn)
local a2 = agg('③ 无敌·淡出帧', invOff)
print('')
print('=== 真实闪烁节奏（前 60 帧；# = 不透明  . = 淡出） ===')
print('  ' .. table.concat(pattern))
print('')
print(string.format('画心帧 − 暗帧 = %.3f ms/帧     普通帧 − 暗帧 = %.3f ms/帧', a1 - a2, b - a2))
print('（方案 A 后：淡出帧同样画心，只是 alpha=0.30，控件数应当与不淡帧相同）')
