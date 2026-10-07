-- 探针：HUD15(multi1) / HUD22(multi3) 的 Attack0 / Attack1 —— 侧骨是否越过中轴、是否碰到"停在中线贴地"的灵魂
-- 用**真实脚本数据**（lua/attacks.lua 里 multi1/multi3 的 CSV 全文），跳到真实标签行执行，不改任何数值。
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = M.DT
local SOUL_R = M.SOUL_R

local function csvOf(n)
  for _, s in ipairs(A) do if s.name == n then return s.csv end end
end

local function analyze(name, label, seconds)
  local compiled = M.compile(M.parseCSV(csvOf(name)))
  local L = compiled.labels[label]
  assert(L, name .. ' 无标签 ' .. label)
  local w = M.newWorld({ seed = 20260927, compiled = compiled })
  w.pc = L; w.wait = 0
  local stat, t = {}, 0
  local zone0 = nil
  local soulX, soulY = 0, 0
  for i = 1, math.floor(60 * seconds) do
    w:update(DT); t = t + DT
    if not zone0 then zone0 = { l = w.zone.l, t = w.zone.t, r = w.zone.r, b = w.zone.b } end
    if not w.soulPosFixed and (w.heart.x or 0) > 0 then
      -- 灵魂在脚本坐标里的"贴地"静止位：框底 - SOUL_CLAMP，x = 框水平中心
      soulX = (zone0.l + zone0.r) / 2
      soulY = zone0.b - M.SOUL_CLAMP
      w.soulPosFixed = true
    end
    local live = {}
    for _, b in ipairs(w.bones) do
      live[b] = true
      local st = stat[b]
      if not st then
        st = { h = b.h, w = b.w or 10, vx = b.vx, y = b.y, color = b.color,
               x0 = b.x, t0 = t, maxx = b.x, minx = b.x, hit = false }
        stat[b] = st
      end
      st.minx = math.min(st.minx, b.x); st.maxx = math.max(st.maxx, b.x)
      if soulX + SOUL_R > b.x and soulX - SOUL_R < b.x + (b.w or 10)
         and soulY + SOUL_R > b.y and soulY - SOUL_R < b.y + (b.h or 10) then st.hit = true end
    end
    for b, st in pairs(stat) do if st.t1 == nil and live[b] == nil then st.t1 = t; st.x1 = b.x end end
  end
  local z = zone0
  local cx = (z.l + z.r) / 2
  print(string.format('\n===== %s : %s =====', name, label))
  print(string.format('战斗框 x %d..%d  y %d..%d   中轴 x=%.1f   灵魂静止位 (%.1f, %.1f)',
        z.l, z.r, z.t, z.b, cx, soulX, soulY))
  print(string.format('%-26s %-6s %-5s %-5s %-6s %-10s %-8s %-7s %s',
        '骨(高/颜色/速度)', '生成x', '高', '颜色', '存活s', 'x范围', '死亡x', '过中轴', '碰到静止灵魂'))
  local ids = {}; for b in pairs(stat) do ids[#ids+1] = b end
  table.sort(ids, function(a, c) return (stat[a].t0 or 0) < (stat[c].t0 or 0) end)
  for _, b in ipairs(ids) do
    local st = stat[b]
    local arrow = (st.vx or 0) > 0 and '东→' or ((st.vx or 0) < 0 and '←西' or '·')
    local cross
    if (st.vx or 0) > 0 then cross = (st.maxx + st.w >= cx)
    elseif (st.vx or 0) < 0 then cross = (st.minx <= cx) else cross = false end
    print(string.format('%-26s %-6.0f %-5.0f %-5d %-6s %-10s %-8s %-7s %s',
      string.format('h=%.0f %s v=%.0f', st.h, arrow, math.abs(st.vx or 0)),
      st.x0, st.h, st.color or 0,
      st.t1 and string.format('%.2f', st.t1 - st.t0) or '-',
      string.format('%.0f..%.0f', st.minx, st.maxx),
      st.x1 and string.format('%.0f', st.x1) or '-',
      cross and '★是' or '否', st.hit and '★是' or '否'))
  end
  return cx
end

analyze('multi1', 'Attack0', 3)
analyze('multi1', 'Attack1', 3)
analyze('multi3', 'Attack0', 3)
analyze('multi3', 'Attack1', 3)
