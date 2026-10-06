# -*- coding: utf-8 -*-
import io
p=r"D:\stars\workspace\sans-fight\lua\main.lua"
s=io.open(p,encoding="utf8").read()

# ---- drawBlaster: drop old 6-rect fallback, always baked ----
old_start=s.index("  -- ② 骷髅：exact 逐像素烘焙")
old_end=s.index("  -- ③ 炮口亮块", old_start)
new='''  -- ② 骷髅：exact 逐像素烘焙（reference/sprites 57×44，Default + 3 个开火帧）。
  --    fire 0→1 映射到 3 帧（<0.334 / <0.667 / 满）；每个实例独立容器，可同时画多发。
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
    elseif not fitWarned then
      fitWarned = true; print('main: fitdata 缺失，龙骨炮烘焙模型不可用')
    end
  end

'''
s=s[:old_start]+new+s[old_end:]
# remove unused bone/dark locals in drawBlaster
s=s.replace("""  local sc = (cmd.scale or 1) * (0.82 + 0.18 * charge)
  local bone = shade(C_SANS_BONE, a)
  local dark = shade(C_SKULL_EYE, a)
  local u0 = BLASTER_MUZZLE_U * sc""","""  local sc = (cmd.scale or 1) * (0.82 + 0.18 * charge)
  local u0 = BLASTER_MUZZLE_U * sc""",1)

# ---- drawSans: replace whole function with baked-only version ----
start=s.index("local SANS_BAKE_SCALE = 1.6")
end=s.index("\n\n-- 灵魂：双圆瓣", start)
new_sans='''local SANS_BAKE_SCALE = 1.6
local function drawSans(cmd)
  local x = cmd.x or 320
  local y = cmd.y or 326
  local a = cmd.alpha or 1
  if a <= 0 then return end
  local dodge = cmd.dodge or 0
  if dodge < 0 then dodge = 0 elseif dodge > 1 then dodge = 1 end
  x = x + 42 * dodge                              -- 闪身：整体侧移
  local head = cmd.head or 'Default'
  local body = cmd.body
  local sweat = tonumber(cmd.sweat) or 0
  if sweat < 0 then sweat = 0 elseif sweat > 3 then sweat = 3 end

  -- 只使用 exact 逐像素烘焙模型；fitdata 缺失时**不再回退旧参数化模型**（避免新旧两套外观并存）。
  if not (fit and fit.sans_poses) then
    if not fitWarned then fitWarned = true; print('main: fitdata 缺失，Sans 烘焙模型不可用') end
    return
  end
  local poseKey = 'default'
  if body == 'HandUp' then poseKey = 'up'
  elseif body == 'HandDown' then poseKey = 'down'
  elseif body == 'HandLeft' then poseKey = 'left'
  elseif body == 'HandRight' then poseKey = 'right' end
  local pose = fit.sans_poses[poseKey]
  local bspec = pose and fit[pose.body]
  local hkey = (head == 'BlueEye') and fit.sans_head_blue_key or fit.sans_head_default_key
  local hspec = hkey and fit[hkey]
  if not (pose and bspec and hspec) then return end

  local K = SANS_BAKE_SCALE
  local kx, ky = K, K
  local bw, bh = bspec.w * kx, bspec.h * ky
  local feet = y + SANS_H
  local bx = x - bw / 2
  local by = feet - bh
  local mir = pose.mirror and true or false
  useBakedCorner(pose.body, bx, by, bw, bh, mir)
  local offx = pose.hx or 0
  if mir then offx = bspec.w - offx - hspec.w end
  local hx = bx + offx * kx
  local hy = by + (pose.hy or 0) * ky
  useBakedCorner(hkey, hx, hy, hspec.w * kx, hspec.h * ky, mir)

  -- 砸击方向提示（保留原功能，坐标改按烘焙头/身体算）
  do
    local DIR = { HandRight = { 1, 0 }, HandDown = { 0, 1 }, HandLeft = { -1, 0 }, HandUp = { 0, -1 } }
    local d = DIR[body]
    if d then
      local L = 30
      local ax, ay = hx + hspec.w * kx + 6, hy + hspec.h * ky / 2
      local col = shade(C_HP, a)
      if d[1] ~= 0 then
        rrect(ax + d[1] * (L / 2), ay, L, 7, 0, col)
        rtri(ax + d[1] * (L + 7), ay, 14, 16, (d[1] == 1) and 270 or 90, col)
      else
        rrect(ax, ay + d[2] * (L / 2), 7, L, 0, col)
        rtri(ax, ay + d[2] * (L + 7), 16, 14, (d[2] == 1) and 180 or 0, col)
      end
    end
  end

  -- 汗滴：头右侧
  if sweat > 0 then
    local sx0 = hx + hspec.w * kx
    local sy0 = hy + 4 * ky
    for i = 1, sweat do
      circle(sx0 + (i - 1) * 5 * kx, sy0 + (i - 1) * 6 * ky, 4 * kx, shade(C_SANS_SWEAT, a))
    end
  end
end'''
s=s[:start]+new_sans+s[end:]

# ---- remove unused old-model constants + mixCol ----
old_consts='''local C_SKULL_EYE = 0xFF10161F          -- 龙骨炮眼窝（深色；蓄力时向 C_SKULL_EYE_HI 渐亮）
local C_SKULL_EYE_HI = 0xFFBCEEFF       -- 龙骨炮蓄满时的眼窝亮色
local C_BEAM_WHITE = 0xFFFFFFFF         -- 光束（3 条平行光带 + 拉链 + 炮口亮块）
local C_SANS_BONE = 0xFFFFFFFF          -- 颅骨
local C_SANS_EYE = 0xFF0D121C           -- 眼窝（近黑）
local C_SANS_EYE_BLACK = 0xFF000000     -- NoEyes：纯黑眼窝
local C_SANS_EYE_HI = 0xFF46C8FF        -- BlueEye：亮蓝左眼
local C_SANS_EYE_HALO = 0x88307FD0      -- BlueEye：外面那圈更暗的蓝（半透明光晕）
local C_SANS_COAT = 0xFF2C3950          -- 外套主体（深蓝灰）
local C_SANS_COAT_HI = 0xFF3C4C69       -- 躯干段 / 手臂（略亮一档）
local C_SANS_SHIRT = 0xFFC6D2E0         -- 内衬（浅色窄条）
local C_SANS_PANTS = 0xFF1E2634         -- 短裤 / 腿（最深）
local C_SANS_SWEAT = 0xFF8FD8FF         -- 汗滴（浅蓝）'''
new_consts='''-- 【2026-10-06 清理】旧参数化 Sans / 6 矩形龙骨炮的配色常量已随旧模型一起删除；
-- 现在龙骨炮与 Sans 本体都走 lua/fitdata.lua 的 exact 逐像素烘焙容器，自带原图颜色。
local C_BEAM_WHITE = 0xFFFFFFFF         -- 光束（仍由池内矩形绘制）
local C_SANS_SWEAT = 0xFF8FD8FF         -- 汗滴（参数化圆点）'''
assert old_consts in s
s=s.replace(old_consts,new_consts,1)
# mixCol
mc_start=s.find("-- 两色线性插值（A/R/G/B 一起插）：龙骨炮蓄力时眼窝由深色渐亮")
if mc_start>=0:
    mc_end=s.index("end\n", s.index("local function mixCol", mc_start))+4
    s=s[:mc_start]+s[mc_end:]
# SANS_SX/SY now unused
s=s.replace("""local SANS_H = 148
local SANS_SX = 1.15
local SANS_SY = 0.95
-- 烘焙 Sans：参考身体是 1:1 像素（64×70 / 96×48），这里整体放大到接近原观感。
-- 脚底锚定（feet = cmd.y + SANS_H），所以各姿势的帧高不同也不会漂。
-- 烘焙 Sans：参考身体是 1:1 像素（64×70 / 96×48），这里整体放大到接近原观感。
-- 脚底锚定（feet = cmd.y + SANS_H），所以各姿势的帧高不同也不会漂。
local SANS_BAKE_SCALE = 1.6""","""local SANS_H = 148                      -- 参考身高：脚底 = cmd.y + SANS_H（烘焙模型按脚底锚定）
local SANS_BAKE_SCALE = 1.6             -- 原版 1:1 像素 → 整体放大倍数""",1)
io.open(p,"w",encoding="utf8",newline="").write(s)
print("drawBlaster/drawSans/constants cleaned")
