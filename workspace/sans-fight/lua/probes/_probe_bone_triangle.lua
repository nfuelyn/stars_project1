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

local function boneList(st)
  local out = {}
  local function add(list)
    if type(list) ~= 'table' then return end
    for _, b in ipairs(list) do
      if type(b) == 'table' and b.x and b.w and b.h and b.w > 0 and b.h > 0 then
        out[#out + 1] = { x = b.x, y = b.y or 0, w = b.w, h = b.h, stab = b.stab }
      end
    end
  end
  if st.world then add(st.world.bones) end
  add(st.bones)
  return out
end
-- 骨头矩形（世界）→ 画布
local function toCanvas(r) return OX + r.x * S, OY + (480 - (r.y + r.h)) * S, r.w * S, r.h * S end

local triCtrls = {}
local rounds = tonumber(os.getenv('ROUNDS') or '') or 24
local HIT = {}
for round = 1, rounds do
  local st = main.state()
  if st == nil then break end
  pcall(function() st:startEnemy(round) end)
  local firstHit = nil
  local hitFrames, maxBones, maxTris = 0, 0, 0
  for f = 1, 360 do
    local ok = pcall(main.OnLevelUpdate, 1 / 30)
    if not ok then break end
    local bones = boneList(st)
    if #bones > maxBones then maxBones = #bones end
    if #triCtrls == 0 or (f % 60 == 0) then            -- 三角形控件很少（池里 4 个），只维护这个小表
      triCtrls = {}
      for _, c in ipairs(controls) do if c.kind == 'rtri' then triCtrls[#triCtrls + 1] = c end end
    end
    local ntri = 0
    for _, c in ipairs(triCtrls) do if c.vis and c.w then ntri = ntri + 1 end end
    if ntri > maxTris then maxTris = ntri end
    for _, c in ipairs(triCtrls) do
      if c.vis and c.w and c.cx then
        -- rtri 是**中心锚点**：putRot 写的是「相对画布中心」的偏移 → 画布中心 + 偏移 = 控件中心
        local tw, th = c.w, c.h
        local rot = tonumber(c.rot) or 0
        if math.abs(rot) % 180 == 90 then tw, th = c.h, c.w end
        local tx = CW / 2 + c.cx - tw / 2
        local ty = CH / 2 + c.cy - th / 2
        local tx, ty, tw, th = tx, ty, tw, th
        for _, b in ipairs(bones) do
          local bx, by, bw, bh = toCanvas(b)
          local ox = math.max(0, math.min(tx + tw, bx + bw) - math.max(tx, bx))
          local oy = math.max(0, math.min(ty + th, by + bh) - math.max(ty, by))
          if ox > 0 and oy > 0 then
            -- 三角中心落在骨头「中段」（长轴 20%~80% 之间）算命中
            local ccx, ccy = tx + tw / 2, ty + th / 2
            local horiz = bw >= bh
            local rel = horiz and ((ccx - bx) / bw) or ((ccy - by) / bh)
            if rel > 0.2 and rel < 0.8 then
              hitFrames = hitFrames + 1
              if firstHit == nil then
                firstHit = string.format('frame=%d 三角=(%.1f,%.1f %.1fx%.1f rot=%s) 骨=(%.1f,%.1f %.1fx%.1f)%s 长轴位置=%.2f',
                  f, tx, ty, tw, th, tostring(c.rot), bx, by, bw, bh, b.stab and '[stab]' or '', rel)
              end
            end
          end
        end
      end
    end
  end
  local name = (st.world and st.world.scriptName) or st.scriptName or (st.round and ('round' .. tostring(st.round))) or '?'
  HIT[#HIT + 1] = { round = round, name = name, frames = hitFrames, sample = firstHit,
                    bones = maxBones, tris = maxTris }
end

print('=== 扫描结果：三角形压在骨头中段 ===')
print('回合(内部)  脚本名                 命中帧数  说明')
for _, h in ipairs(HIT) do
  print(string.format('%-10d  %-22s  %-8d  骨头峰值=%d 三角峰值=%d  %s',
    h.round, tostring(h.name), h.frames, h.bones or 0, h.tris or 0, h.sample or '(无)'))
end
local bad = 0
for _, h in ipairs(HIT) do if h.frames > 0 then bad = bad + 1 end end
print(string.format('\n共 %d 个回合扫描完成，其中 %d 个回合出现「三角形压骨头中段」。', #HIT, bad))
