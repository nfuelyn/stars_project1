# -*- coding: utf-8 -*-
import io
p=r"D:\stars\workspace\sans-fight\lua\main.lua"
s=io.open(p,encoding="utf8").read()

# ---- 1) replace baked system with multi-instance version ----
start=s.index("local baked = {}")
end=s.index("local function hideBaked()")
end2=s.index("\n\n-- 逻辑层可能给出被按字节截断的中文", end)
new_baked='''local baked = {}                       -- key -> { name, spec, center, mirror, insts = { {c,vis,used,kids}, ... } }
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
end'''
s=s[:start]+new_baked+s[end2:]
io.open(p,"w",encoding="utf8",newline="").write(s)
print("baked system replaced")
