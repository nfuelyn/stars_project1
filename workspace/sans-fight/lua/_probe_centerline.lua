package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = M.DT
local csv
for _, s in ipairs(A) do if s.name == 'multi1' then csv = s.csv end end
local w = M.newWorld({ seed = 20260927, script = M.parseCSV(csv) })
local info, t = {}, 0
for i = 1, math.floor(60*30) do
  w:update(DT); t = t + DT
  local live = {}
  for _, b in ipairs(w.bones) do
    live[b] = true
    local k = string.format('h=%.0f vx=%.0f', b.h or 0, b.vx or 0)
    info[k] = info[k] or { min = b.x, max = b.x, spawn = b.x, t0 = t }
    if b.x > info[k].max then info[k].max = b.x end
    if b.x < info[k].min then info[k].min = b.x end
  end
  for k, v in pairs(info) do if v._live and live[v._b] == nil then v._live = false end end
  for _, b in ipairs(w.bones) do
    local k = string.format('h=%.0f vx=%.0f', b.h or 0, b.vx or 0)
    info[k]._live, info[k]._b = true, b
  end
end
local z = w.zone
local cx = (z.l + z.r) / 2
print(string.format('框 = (%d,%d)-(%d,%d)  中轴 x = %.1f', z.l, z.t, z.r, z.b, cx))
print('按 (高, 速度) 分组的飞行范围（脚本坐标）：')
for k, v in pairs(info) do
  local cross = (v.max > cx) and '★越过中轴' or '未过中轴'
  print(string.format('  %-14s x: %.0f → %.0f   %s', k, v.min, v.max, cross))
end
