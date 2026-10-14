-- _probe_tutorial_main.lua —— **main 层**探针：二选一入口 + 蓝心教程跳跃
--   为什么单独要有它：core 层探针走不到 main.lua 的适配层分支 ——
--   而"蓝心教程跳跃幅度极小"的根因正是 main.lua 里 `local blue = (state.state == 'enemy')`：
--   教程态被挡在外面 ⇒ 方向键跳跃失效 + core 的 jumpHeld 只有一帧为真 ⇒ 下一帧被"松键截断"剪成极小跳。
-- 用法：node tools/run-lua.mjs lua/probes/_probe_tutorial_main.lua
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local core = require('lua' .. '.core')
local attacks = require('lua' .. '.attacks')
package.loaded['default_import_file/workspace/sans-fight/lua/core'] = core
package.loaded['default_import_file/workspace/sans-fight/lua/attacks'] = attacks
package.loaded['default_import_file/workspace/sans-fight/lua/fitdata'] = {}
package.loaded['default_import_file/workspace/sans-fight/lua/textart'] = { glyphs = {} }
-- ★ 本探针就要测教程：配置里把 tutorial 打开
package.loaded['default_import_file/workspace/sans-fight/lua/config'] =
  { updateCallback = 'level', templatesFirst = 'sim', legacyTemplateFallback = true,
    textMode = 'control', device = 'keyboard', tutorial = true }

local key, cursor = {}, {}
local nextId = 1
local function mkControl(kind)
  local c = { Id = nextId, kind = kind, visible = true, prefabIndex = 0 }
  nextId = nextId + 1
  local store = {}
  return setmetatable(c, {
    __index = function(_, k)
      if k == 'AddKeyEventListener' then return function(_, n, fn) key[n] = fn end end
      if k == 'AddCursorEventListener' then return function(_, n, fn) cursor[n] = fn end end
      local m = { SetVisible = 1, SetActive = 1, SetImage = 1, SetSiblingIndex = 1, SetSizeDelta = 1,
                  SetAnchoredPosition = 1, SetLocalRotation = 1, GetChildren = 1, GetChild = 1,
                  FindChild = 1, SetAsFirstSibling = 1, SetAsLastSibling = 1, SetAnchorMin = 1,
                  SetAnchorMax = 1, SetPivot = 1 }
      if m[k] then return function() end end
      return store[k]
    end,
    __newindex = function(_, k, v)
      if k == 'fontSize' and not (math.type(v) == 'integer') then error('fontSize 必须是整数', 2) end
      store[k] = v
    end,
  })
end
local rootCtrl = mkControl('container')
game = {
  GetUICanvasSize = function() return 1600, 900 end,
  GetClientUIControl = function(id) if id == 1 then return rootCtrl end return nil end,
  InstantiateClientUIControl = function() return mkControl('inst') end,
  GetGlobalCustomVariableValue = function() error('none') end,
  PrintClientUITree = function() end,
  GetDevice = function() return 'KeyboardAndMouse' end,
}
script = { object = rootCtrl, EnableUpdate = function() end }

local realPrint = print
local main = require('lua' .. '.main')
print = function() end                      -- 静音 main 的日志
main.OnInit(); main.OnStart()
print = realPrint

local pass, fail = 0, 0
local function ok(c, m)
  if c then pass = pass + 1; print('  PASS ' .. m) else fail = fail + 1; print('  FAIL ' .. m) end
end
local DT = 1 / 30
local function frame() pcall(main.OnLevelUpdate, DT) end
local function press(n) local f = key[n]; if f then f() end end
local function release(n) local f = key[n]; if f then f() end end
local function tap(n) press(n); frame(); release(n) end

print('=== main 层教程探针 ===')
local st = main.state()
ok(st ~= nil and st.state == 'tut_ask', '启动即停在二选一（实际 ' .. tostring(st and st.state) .. '）')

-- 二选一：键盘确认 = 进入引导（默认索引 0）
tap('KeyboardMenuConfirmKeyDown')
st = main.state()
ok(st.state == 'tutorial', '键盘确认 → 进入教程（实际 ' .. tostring(st.state) .. '）')

-- 推到第 3 节（蓝心移动）：第 1/2 节靠 45s 兜底放过
local guard = 0
while st.state == 'tutorial' and (st.tutIdx or 1) < 3 and guard < 12000 do
  frame(); st = main.state(); guard = guard + 1
end
ok(st.state == 'tutorial' and st.tutIdx == 3, '到达第 3 节（蓝心移动）（实际 idx=' .. tostring(st.tutIdx) .. '）')

-- 等它落到底（验证「全程重力」）
local g = main.state()
local ySpawn = g.soul.y
for _ = 1, 90 do frame() end
g = main.state()
ok(g.soul.y > ySpawn + 5, string.format('蓝心全程受重力（y %.1f → %.1f）', ySpawn, g.soul.y))

-- 按住「与重力反向的方向键」（dir=1 南 → up = KeyboardMoveForward）→ 正常幅度的跳跃
local yGround = g.soul.y
local peak = yGround
press('KeyboardMoveForwardKeyDown')
for _ = 1, 60 do frame(); local s = main.state().soul; if s.y < peak then peak = s.y end end
release('KeyboardMoveForwardKeyDown')
for _ = 1, 60 do frame(); local s = main.state().soul; if s.y < peak then peak = s.y end end
local rise = yGround - peak
ok(rise > 40, string.format('方向键跳跃幅度正常（%.1f px；修前教程态被截断成极小跳）', rise))

print('')
print(string.format('PASS %d / FAIL %d', pass, fail))
if fail > 0 then os.exit(1) end