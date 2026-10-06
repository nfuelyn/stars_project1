# -*- coding: utf-8 -*-
import io
p=r"D:\stars\workspace\sans-fight\lua\main.lua"
s=io.open(p,encoding="utf8").read()

# A) G table
old="""local G = {
  rect = 1073743001, circle = 1073743002, text = 1073743004,
  ring = 1073743006, rot = 1073743007, rtri = 1073743008,
  cursor = 1073743009,
}"""
new="""local G = {
  rect = 1073743001, circle = 1073743002, text = 1073743004,
  ring = 1073743006, rot = 1073743007, rtri = 1073743008,
  cursor = 1073743009, baked = 1073743100, bakedC = 1073743101,
}"""
assert old in s; s=s.replace(old,new,1)

# B) root decl + fit decl
old="local root, flash, bgPanel = nil, nil, nil"
new="local root, flash, bgPanel, bakedRoot = nil, nil, nil, nil"
assert old in s; s=s.replace(old,new,1)
old="local core, attacks, state = nil, nil, nil"
new="local core, attacks, state = nil, nil, nil\nlocal fit = nil                    -- lua/fitdata.lua：exact 逐像素烘焙表（缺失时走参数化回退）"
assert old in s; s=s.replace(old,new,1)

# C) baked system after spin()
anchor="""  if m.r ~= deg then c:SetLocalRotation(0, 0, deg); m.r = deg end
end

-- 逻辑层可能给出被按字节截断的中文"""
ins="""  if m.r ~= deg then c:SetLocalRotation(0, 0, deg); m.r = deg end
end

-- ---------------------------------------------------------------- 烘焙贴图（exact 逐像素）
-- 数据来自 lua/fitdata.lua（tools/fit-sprites.py 生成）：每个素材一个容器，
-- 子控件用**比例锚点**（anchorMin/Max = 矩形占比、sizeDelta=0）→ 父容器 SetSizeDelta
-- 就能整体缩放（不用真机未验证的 SetLocalScale）。容器在 bakedRoot 下，
-- bakedRoot 在 prewarm 之前创建 → 烘焙层天然在黑底之上、池控件之下。
local baked = {}                       -- name -> { c, spec, center, vis, used, kids }
local function bakeSprite(name, center)
  local rec = baked[name]
  if rec then return rec end
  if not fit or type(fit[name]) ~= 'table' then return nil end
  local spec = fit[name]
  local parent = bakedRoot or root
  local ok, c = pcall(function() return game.InstantiateClientUIControl(center and G.bakedC or G.baked, parent) end)
  if not ok or c == nil then
    if not instNILLogged then instNILLogged = true; print('main: baked 容器缺失 :: ' .. tostring(c)) end
    return nil
  end
  madeTotal = madeTotal + 1
  c:SetVisible(false)
  local kids = 0
  for i = 1, #spec.rects do
    local r = spec.rects[i]
    local k = game.InstantiateClientUIControl(G.rect, c)
    if k then
      k:SetAnchorMin(r.x / spec.w, 1 - (r.y + r.h) / spec.h)
      k:SetAnchorMax((r.x + r.w) / spec.w, 1 - r.y / spec.h)
      k:SetSizeDelta(0, 0)
      k.imageColor = r.c
      k:SetVisible(true)
      kids = kids + 1
    end
  end
  rec = { c = c, spec = spec, center = center and true or false, vis = false, used = -1, kids = kids }
  baked[name] = rec
  st(c).vis = false
  print(string.format('main: baked %s %dx%d rects=%d', name, spec.w, spec.h, kids))
  return rec
end

-- 左下锚点：world 左上角 (x,y)、宽高 w,h（世界 px）
local function useBakedCorner(name, x, y, w, h)
  local b = bakeSprite(name, false); if not b then return nil end
  b.used = frame
  if not b.vis then b.c:SetVisible(true); b.vis = true end
  put(b.c, wx(x), wyBottom(y + h), w * S, h * S)
  return b
end

-- 中心锚点：world 中心 (cx,cy)、宽高 w,h、旋转 deg
local function useBakedCenter(name, cx, cy, w, h, deg)
  local b = bakeSprite(name, true); if not b then return nil end
  b.used = frame
  if not b.vis then b.c:SetVisible(true); b.vis = true end
  put(b.c, wx(cx) - CW / 2, wyBottom(cy) - CH / 2, w * S, h * S)
  if deg then spin(b.c, deg) end
  return b
end

local function hideBaked()
  for _, b in pairs(baked) do
    if b.used ~= frame and b.vis then b.c:SetVisible(false); b.vis = false end
  end
end

-- 逻辑层可能给出被按字节截断的中文"""
assert anchor in s; s=s.replace(anchor,ins,1)

# D) frameEnd
old="""local function frameEnd()
  for kind, list in pairs(pool) do"""
new="""local function frameEnd()
  hideBaked()
  for kind, list in pairs(pool) do"""
assert old in s; s=s.replace(old,new,1)

# E) drawBlaster 6-part block -> baked + fallback
old="""  -- ② 骷髅 6 件：后颅（32×44）+ 吻部（34×22）+ 2 眼窝（11×12）+ 口腔（18×9）+ 牙条（14×4）
  --    剪影 = 原版长吻头骨：后颅高而宽、吻部窄而长（整体 ≈59×44，原版贴图 57×44）
  local hx, hy = P(-10 * sc, 0)
  rrect(hx, hy, 32 * sc, 44 * sc, deg, bone)                    -- 后颅（高）
  local sx2, sy2 = P(16 * sc, 0)
  rrect(sx2, sy2, 34 * sc, 22 * sc, deg, bone)                  -- 吻部（窄长，前伸）
  local e1x, e1y = P(-6 * sc, 10 * sc)
  rrect(e1x, e1y, 11 * sc, 12 * sc, deg, dark)                  -- 眼窝（上）
  local e2x, e2y = P(-6 * sc, -10 * sc)
  rrect(e2x, e2y, 11 * sc, 12 * sc, deg, dark)                  -- 眼窝（下）
  local m1x, m1y = P(22 * sc, 0)
  rrect(m1x, m1y, 18 * sc, 9 * sc, deg, dark)                   -- 口腔（暗）
  local t1x, t1y = P(23 * sc, 0)
  rrect(t1x, t1y, 14 * sc, 4 * sc, deg, bone)                   -- 牙条（白，压在口腔上）"""
new="""  -- ② 骷髅：exact 逐像素烘焙（reference/sprites 57×44，Default + 3 个开火帧）。
  --    fire 0→1 映射到 3 帧（<0.334 / <0.667 / 满）；容器中心锚点 + deg 旋转。
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
    if name and fit and fit[name] then
      useBakedCenter(name, bx, by, 57 * sc, 44 * sc, deg)
    else
      -- 回退（离线单测 / fitdata 缺失）：参数化 6 件
      local hx, hy = P(-10 * sc, 0)
      rrect(hx, hy, 32 * sc, 44 * sc, deg, bone)
      local sx2, sy2 = P(16 * sc, 0)
      rrect(sx2, sy2, 34 * sc, 22 * sc, deg, bone)
      local e1x, e1y = P(-6 * sc, 10 * sc)
      rrect(e1x, e1y, 11 * sc, 12 * sc, deg, dark)
      local e2x, e2y = P(-6 * sc, -10 * sc)
      rrect(e2x, e2y, 11 * sc, 12 * sc, deg, dark)
      local m1x, m1y = P(22 * sc, 0)
      rrect(m1x, m1y, 18 * sc, 9 * sc, deg, dark)
      local t1x, t1y = P(23 * sc, 0)
      rrect(t1x, t1y, 14 * sc, 4 * sc, deg, bone)
    end
  end"""
assert old in s; s=s.replace(old,new,1)

# F) SANS_BAKE_SCALE near SANS_SY
old="""local SANS_H = 148
local SANS_SX = 1.15
local SANS_SY = 0.95"""
new="""local SANS_H = 148
local SANS_SX = 1.15
local SANS_SY = 0.95
-- 烘焙 Sans：参考身体是 1:1 像素（64×70 / 96×48），这里整体放大到接近原观感。
-- 脚底锚定（feet = cmd.y + SANS_H），所以各姿势的帧高不同也不会漂。
local SANS_BAKE_SCALE = 1.8"""
assert old in s; s=s.replace(old,new,1)

# G) drawSans baked path after sweat clamp
old="""  local sweat = tonumber(cmd.sweat) or 0
  if sweat < 0 then sweat = 0 elseif sweat > 3 then sweat = 3 end
  local tired = (cmd.anim == 'Tired')             -- 疲劳：上身整体右移 + 下沉"""
new="""  local sweat = tonumber(cmd.sweat) or 0
  if sweat < 0 then sweat = 0 elseif sweat > 3 then sweat = 3 end
  -- 烘焙路径：exact 逐像素身体 + 头（Default / 审判眼 BlueEye）+ 参数化汗滴。
  if fit and fit.sans_poses then
    local poseKey = 'default'
    if body == 'HandUp' then poseKey = 'up'
    elseif body == 'HandDown' then poseKey = 'down'
    elseif body == 'HandLeft' then poseKey = 'left'
    elseif body == 'HandRight' then poseKey = 'right' end
    local pose = fit.sans_poses[poseKey]
    local bspec = pose and fit[pose.body]
    local hkey = (head == 'BlueEye') and fit.sans_head_blue_key or fit.sans_head_default_key
    local hspec = hkey and fit[hkey]
    if pose and bspec and hspec then
      local K = SANS_BAKE_SCALE
      local kx, ky = K * SANS_SX, K * SANS_SY
      local bw, bh = bspec.w * kx, bspec.h * ky
      local feet = y + SANS_H
      local bx = x - bw / 2
      local by = feet - bh
      useBakedCorner(pose.body, bx, by, bw, bh)
      local hx = bx + (pose.hx or 0) * kx
      local hy = by + (pose.hy or 0) * ky
      useBakedCorner(hkey, hx, hy, hspec.w * kx, hspec.h * ky)
      if sweat > 0 then
        local sx0 = hx + hspec.w * kx
        local sy0 = hy + 4 * ky
        for i = 1, sweat do
          circle(sx0 + (i - 1) * 5 * kx, sy0 + (i - 1) * 6 * ky, 4 * kx, shade(C_SANS_SWEAT, a))
        end
      end
      return
    end
  end
  local tired = (cmd.anim == 'Tired')             -- 疲劳：上身整体右移 + 下沉"""
assert old in s; s=s.replace(old,new,1)

# H) tryLoadFit near tryLoadCore
old="""local function tryLoadCore()"""
new="""local function tryLoadFit()
  local ok, m = pcall(require, 'default_import_file/workspace/sans-fight/lua/fitdata')
  if ok and type(m) == 'table' and next(m) ~= nil then return m end
  local ok2, m2 = pcall(require, 'lua' .. '.fitdata')
  if ok2 and type(m2) == 'table' and next(m2) ~= nil then return m2 end
  print('main: fitdata 未加载（用参数化外观）:: ' .. tostring(m))
  return nil
end

local function tryLoadCore()"""
assert old in s; s=s.replace(old,new,1)

# I) OnStart: bakedRoot + fit before prewarm
old="""  prewarm()
  cursorArea = take('cursor')"""
new="""  -- 烘焙容器根：必须在 prewarm 之前创建 → 烘焙层在黑底之上、池控件之下。
  bakedRoot = spawn('baked')
  if bakedRoot then
    put(bakedRoot, 0, 0, 0, 0)
    bakedRoot:SetVisible(true)
    st(bakedRoot).vis = true
  end
  fit = tryLoadFit()
  prewarm()
  cursorArea = take('cursor')"""
assert old in s; s=s.replace(old,new,1)

io.open(p,"w",encoding="utf8",newline="").write(s)
print("patched main.lua")

# tests: force fallback by stubbing fitdata as empty table
for tp in [r"D:\stars\workspace\sans-fight\lua\_pool.lua", r"D:\stars\workspace\sans-fight\lua\_geometry.lua"]:
    t=io.open(tp,encoding="utf8").read()
    key="package.loaded['default_import_file/workspace/sans-fight/lua/attacks'] = attacks"
    if key in t and 'lua/fitdata' not in t:
        t=t.replace(key, key+"\n-- 离线单测固定走参数化回退：把 fitdata 置空表，避免烘焙容器影响池峰值/几何对账。\npackage.loaded['default_import_file/workspace/sans-fight/lua/fitdata'] = {}",1)
        io.open(tp,"w",encoding="utf8",newline="").write(t)
        print("stubbed", tp)
