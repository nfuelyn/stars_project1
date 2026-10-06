-- _adapter.lua —— 用假的 game API 无头运行 main.lua，抓适配层的运行期错误
-- 用途：模拟器里「命中后卡死」多半是 OnLevelUpdate 每帧抛错（boot 的 pcall 吞掉后画面就不再更新）。
-- 这里把 core/attacks 通过 package.loaded 预置成 require 能拿到的模块，从而跑真正的 core 模式。
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path

local core = require('lua' .. '.core')
local attacks = require('lua' .. '.attacks')
package.loaded['default_import_file/workspace/sans-fight/lua/core'] = core
package.loaded['default_import_file/workspace/sans-fight/lua/attacks'] = attacks

-- ---- 假 game API -----------------------------------------------------------
local nextId = 1
local function mkControl(kind)
  local c = { Id = nextId, kind = kind, visible = true, prefabIndex = 0 }
  nextId = nextId + 1
  return setmetatable(c, {
    __index = function(t, k)
      local methods = {
        SetVisible = 1, SetActive = 1, SetImage = 1, SetSiblingIndex = 1,
        SetSizeDelta = 1, SetAnchoredPosition = 1, SetLocalRotation = 1,
        AddKeyEventListener = 1, AddCursorEventListener = 1,
        GetChildren = 1, GetChild = 1, FindChild = 1,
      }
      if methods[k] then return function() end end
      return nil
    end,
  })
end

local rootCtrl = mkControl('container')
local instCount = 0
game = {
  GetUICanvasSize = function() return 1280, 720 end,
  GetClientUIControl = function(id) if id == 1 then return rootCtrl end return nil end,
  InstantiateClientUIControl = function(idx, parent)
    instCount = instCount + 1
    return mkControl('inst')
  end,
  GetGlobalCustomVariableValue = function() error('no such variable') end,
  PrintClientUITree = function() end,
}

-- ---- 跑 main.lua -----------------------------------------------------------
local main = require('lua' .. '.main')
local okI, errI = pcall(main.OnInit)
print('OnInit  ' .. tostring(okI) .. ' ' .. tostring(errI))
local okS, errS = pcall(main.OnStart)
print('OnStart ' .. tostring(okS) .. ' ' .. tostring(errS))
print('实例化控件数 = ' .. instCount)

local errors, firstErrFrame, hits = {}, nil, 0
local lastHP
for i = 1, 1800 do
  local ok, err = pcall(main.OnLevelUpdate, 1.0 / 30.0)
  if not ok then
    if not firstErrFrame then firstErrFrame = i end
    if #errors < 6 then errors[#errors + 1] = string.format('frame %d: %s', i, tostring(err)) end
  end
  -- 直接读 state 观察 HP 变化（命中）
  local st = main.state()
  if st and st.hp then
    if lastHP and st.hp < lastHP then
      hits = hits + 1
      print(string.format('  命中 #%d frame=%d hp=%s->%s state=%s', hits, i, tostring(lastHP), tostring(st.hp), tostring(st.state)))
    end
    lastHP = st.hp
  end
end
print('--- 结果 ---')
print('错误帧数 = ' .. tostring(firstErrFrame and (1800 - firstErrFrame + 1) or 0) .. '（首错 frame=' .. tostring(firstErrFrame) .. '）')
for _, e in ipairs(errors) do print('  ' .. e) end
