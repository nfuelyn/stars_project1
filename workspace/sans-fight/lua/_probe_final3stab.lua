-- 探针：final（HUD24）阶段③末尾那两组"两边同时骨刺"到底会不会伸出来？
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = M.DT
local csv
for _, s in ipairs(A) do if s.name == 'final' then csv = s.csv end end
local prog = M.compile(M.parseCSV(csv))

local function indexOfRow(cmd, extra)
  for i, ln in ipairs(prog.prog) do
    if ln.cmd == cmd and tostring(ln.args[1]) == tostring(extra) then return i - 1 end
  end
end
-- 找阶段③最后一组「两边同时」的第一根（dir=0、warn ≥ 1.4）——改前是 48/1.4，改后是 38.4/1.9
local startIdx = nil
for i, ln in ipairs(prog.prog) do
  if ln.cmd == 'BoneStab' and tonumber(ln.args[1]) == 0 and (tonumber(ln.args[3]) or 0) >= 1.4 then
    startIdx = i - 1; break
  end
end
print('起点 pc(0-based) = ' .. tostring(startIdx))
local w = M.newWorld({ seed = 20260927, compiled = prog })
w.pc = startIdx
w.wait = 0
local prevPhase, prevN, prevBlack = {}, {}, nil
local t = 0
for i = 1, math.floor(60 * 6) do
  w:update(DT); t = t + DT
  if w.black ~= prevBlack then
    print(string.format('t=%5.2f black=%s  (骨头 %d 根)', t, tostring(w.black), #w.bones))
    prevBlack = w.black
  end
  local live = {}
  for _, b in ipairs(w.bones) do
    live[b] = true
    if prevPhase[b] == nil then
      print(string.format('t=%5.2f 生成骨刺 dir=%s dist=%s warn=%s stay=%s', t, tostring(b.dir), tostring(b.dist), tostring(b.warn), tostring(b.stay)))
    elseif prevPhase[b] ~= b.phase then
      print(string.format('t=%5.2f 骨刺(dir=%s) 相位 %s → %s  (cur=%.1f)', t, tostring(b.dir), prevPhase[b], b.phase, b.cur or 0))
    end
    prevPhase[b] = b.phase
  end
  for b, p in pairs(prevPhase) do
    if live[b] == nil then
      print(string.format('t=%5.2f 骨刺(dir=%s) 被移除，移除前相位=%s', t, tostring(b.dir), tostring(p)))
      prevPhase[b] = nil
    end
  end
end

