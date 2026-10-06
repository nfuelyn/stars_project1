# -*- coding: utf-8 -*-
import io
p=r"D:\stars\workspace\sans-fight\lua\_geometry.lua"
s=io.open(p,encoding="utf8").read()
old = """-- drawBone 的骨干矩形（画布上真正那一块）
local function shaftOf(x, y, w, h, vertical)
  if vertical then
    if h - 12 <= 0 then return nil end
    local stemW = math.max(2, math.min(7, w / 2))
    return expRect(x + (w - stemW) / 2, y + 6, stemW, h - 12, PRIM_RECT)
  end
  if w - 12 <= 0 then return nil end
  local stemH = math.max(2, math.min(7, h / 2))
  return expRect(x + 6, y + (h - stemH) / 2, w - 12, stemH, PRIM_RECT)
end
"""
new = """-- drawBone 的骨干矩形（画布上真正那一块）
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
    local sh = h - 2 * k / 3
    if sh <= 0 then return nil end
    return expRect(x + (w - k) / 2, y + k / 3, k, sh, PRIM_RECT)
  end
  local sw = w - 2 * k / 3
  if sw <= 0 then return nil end
  return expRect(x + k / 3, y + (h - k) / 2, sw, k, PRIM_RECT)
end
"""
assert old in s, "old shaftOf not found"
s=s.replace(old,new,1)
io.open(p,"w",encoding="utf8",newline="").write(s)
print("patched geometry test")
