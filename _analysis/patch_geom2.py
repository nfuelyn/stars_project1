# -*- coding: utf-8 -*-
import io
p=r"D:\stars\workspace\sans-fight\lua\_geometry.lua"
s=io.open(p,encoding="utf8").read()
old = """local function shaftOf(x, y, w, h, vertical)
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
new = """local function shaftOf(x, y, w, h, vertical)
  local k = boneKnob(w, h)
  if vertical then
    -- 与 main.lua drawBone 完全同式（含 max(1,...) 的钳位），否则退化尺寸会对不上
    return expRect(x + (w - k) / 2, y + k / 3, k, math.max(1, h - 2 * k / 3), PRIM_RECT)
  end
  return expRect(x + k / 3, y + (h - k) / 2, math.max(1, w - 2 * k / 3), k, PRIM_RECT)
end
"""
assert old in s
s=s.replace(old,new,1)
io.open(p,"w",encoding="utf8",newline="").write(s)
print("patched")
