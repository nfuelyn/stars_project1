# -*- coding: utf-8 -*-
import io
# 1) fit tool: left pose mirror
p=r"D:\stars\workspace\sans-fight\tools\fit-sprites.py"
s=io.open(p,encoding="utf8").read()
s=s.replace('"  left    = { body = \'sans_body_left\',    hx = 15, hy = 6 },",',
            '"  left    = { body = \'sans_body_left\',    hx = 15, hy = 6, mirror = true },",',1)
io.open(p,"w",encoding="utf8",newline="").write(s)
# 2) main.lua: mirror support
m=r"D:\stars\workspace\sans-fight\lua\main.lua"
x=io.open(m,encoding="utf8").read()
old="""local baked = {}                       -- name -> { c, spec, center, vis, used, kids }
local function bakeSprite(name, center)
  local rec = baked[name]
  if rec then return rec end
  if not fit or type(fit[name]) ~= 'table' then return nil end
  local spec = fit[name]"""
new="""local baked = {}                       -- key -> { c, spec, center, mirror, vis, used, kids }
local function bakeSprite(name, center, mirror)
  local key = mirror and (name .. '#m') or name
  local rec = baked[key]
  if rec then return rec end
  if not fit or type(fit[name]) ~= 'table' then return nil end
  local spec = fit[name]"""
assert old in x; x=x.replace(old,new,1)
old="""    if k then
      k:SetAnchorMin(r.x / spec.w, 1 - (r.y + r.h) / spec.h)
      k:SetAnchorMax((r.x + r.w) / spec.w, 1 - r.y / spec.h)"""
new="""    if k then
      local ax0, ax1
      if mirror then
        ax0 = 1 - (r.x + r.w) / spec.w
        ax1 = 1 - r.x / spec.w
      else
        ax0 = r.x / spec.w
        ax1 = (r.x + r.w) / spec.w
      end
      k:SetAnchorMin(ax0, 1 - (r.y + r.h) / spec.h)
      k:SetAnchorMax(ax1, 1 - r.y / spec.h)"""
assert old in x; x=x.replace(old,new,1)
x=x.replace("""  rec = { c = c, spec = spec, center = center and true or false, vis = false, used = -1, kids = kids }
  baked[name] = rec""","""  rec = { c = c, spec = spec, center = center and true or false, mirror = mirror and true or false,
          vis = false, used = -1, kids = kids }
  baked[key] = rec""",1)
old="""local function useBakedCorner(name, x, y, w, h)
  local b = bakeSprite(name, false); if not b then return nil end"""
new="""local function useBakedCorner(name, x, y, w, h, mirror)
  local b = bakeSprite(name, false, mirror); if not b then return nil end"""
assert old in x; x=x.replace(old,new,1)
old="""      useBakedCorner(pose.body, bx, by, bw, bh)
      local hx = bx + (pose.hx or 0) * kx
      local hy = by + (pose.hy or 0) * ky
      useBakedCorner(hkey, hx, hy, hspec.w * kx, hspec.h * ky)"""
new="""      local mir = pose.mirror and true or false
      useBakedCorner(pose.body, bx, by, bw, bh, mir)
      local offx = pose.hx or 0
      if mir then offx = bspec.w - offx - hspec.w end
      local hx = bx + offx * kx
      local hy = by + (pose.hy or 0) * ky
      useBakedCorner(hkey, hx, hy, hspec.w * kx, hspec.h * ky, mir)"""
assert old in x; x=x.replace(old,new,1)
io.open(m,"w",encoding="utf8",newline="").write(x)
print("patched mirror")
