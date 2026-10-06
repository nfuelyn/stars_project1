# -*- coding: utf-8 -*-
import io
p=r"D:\stars\workspace\sans-fight\lua\main.lua"
s=io.open(p,encoding="utf8").read()
old = """-- 骨头：骨干 + 两端各两颗骨球（原作骨宽 19）
local function drawBone(cmd)
  local x, y, w, h = cmd.x, cmd.y, cmd.w or 19, cmd.h or 19
  local col = BONE_COLORS[(cmd.color or 0) + 1] or C_WHITE
  local a = cmd.alpha or 1
  if a < 1 then
    local rgb = col & 0xFFFFFF
    col = ((math.floor(((col >> 24) & 0xFF) * a)) << 24) | rgb
  end
  local vertical = cmd.vertical
  if vertical == nil then vertical = (h >= w) end
  -- 【2026-10-05 修】圆帽必须**正好铺满骨头的矩形**（x..x+w / y..y+h）：
  -- 旧写法两个圆整体偏出去 6.5px（19 宽的骨头视觉只有 x-6.5..x+12.5），
  -- 判定用的是 x..x+19 → 出现「擦着骨头过去却掉血 / 明明重叠却没事」的偏差。
  -- 骨头厚度可能只有 10px（原版 BoneV/BoneH 贴图），骨干/骨帽都要按当前厚度收缩，不能写死 7/13。
  if vertical then
    local stemW = math.max(2, math.min(7, w / 2))
    local k = math.min(13, w, h)
    rect(x + (w - stemW) / 2, y + 6, stemW, math.max(1, h - 12), col)
    circle(x, y, k, col)
    circle(x + w - k, y, k, col)
    circle(x, y + h - k, k, col)
    circle(x + w - k, y + h - k, k, col)
  else
    local stemH = math.max(2, math.min(7, h / 2))
    local k = math.min(13, w, h)
    rect(x + 6, y + (h - stemH) / 2, math.max(1, w - 12), stemH, col)
    circle(x, y, k, col)
    circle(x, y + h - k, k, col)
    circle(x + w - k, y, k, col)
    circle(x + w - k, y + h - k, k, col)
  end
end
"""
new = """-- 骨头：骨干 + 两端各**两颗分离骨球**（按原版贴图拟合，见 tools/fit-sprites.py）
-- 参考：Textures/BoneV.png 10×24 / BoneH.png 24×10（exact 游程 13 个矩形）。
-- 参数化拟合只用 5 个图元（1 rect + 4 circle），数量与原实现相同：
--   k = 0.6 × 短边 = 骨球直径；骨干宽/高 = k；两端各收进 k/3。
-- 端点必须画成两颗球（原为两颗重合的大圆 → 胶囊形，不是骨头）。
local function drawBone(cmd)
  local x, y, w, h = cmd.x, cmd.y, cmd.w or 10, cmd.h or 10
  local col = BONE_COLORS[(cmd.color or 0) + 1] or C_WHITE
  local a = cmd.alpha or 1
  if a < 1 then
    local rgb = col & 0xFFFFFF
    col = ((math.floor(((col >> 24) & 0xFF) * a)) << 24) | rgb
  end
  local vertical = cmd.vertical
  if vertical == nil then vertical = (h >= w) end
  -- 骨球直径：短边的 0.6（原版 10 宽 → 6px 球）。钳到 ≥4，避免细骨退化成点。
  local k = math.min(w, h) * 0.6
  if k < 4 then k = 4 end
  if k > w then k = w end
  if k > h then k = h end
  if vertical then
    rect(x + (w - k) / 2, y + k / 3, k, math.max(1, h - 2 * k / 3), col)
    circle(x, y, k, col)
    circle(x + w - k, y, k, col)
    circle(x, y + h - k, k, col)
    circle(x + w - k, y + h - k, k, col)
  else
    rect(x + k / 3, y + (h - k) / 2, math.max(1, w - 2 * k / 3), k, col)
    circle(x, y, k, col)
    circle(x + w - k, y, k, col)
    circle(x, y + h - k, k, col)
    circle(x + w - k, y + h - k, k, col)
  end
end
"""
assert old in s, "old block not found"
s=s.replace(old,new,1)
io.open(p,"w",encoding="utf8",newline="").write(s)
print("patched", len(old), "->", len(new))
