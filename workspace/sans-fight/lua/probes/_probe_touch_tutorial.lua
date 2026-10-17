-- _probe_touch_tutorial.lua —— **手机（触摸）端**探针
--   2026-10-17 回归：教程复用 enemy 的物理，但 main 里摇杆的激活条件只写了 'enemy'
--   → 手机端教程里摇杆起不来，表现为"固定摇杆拖不动 / 触摸像没穿透进来"。
--   本探针走真实路径：触摸模式启动 → 二选一点按 → 教程 → 摇杆 Down + Drag → 灵魂真的移动。
-- 用法：node tools/run-lua.mjs lua/probes/_probe_touch_tutorial.lua
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local core = require('lua' .. '.core')
local attacks = require('lua' .. '.attacks')
package.loaded['default_import_file/workspace/sans-fight/lua/core'] = core
package.loaded['default_import_file/workspace/sans-fight/lua/attacks'] = attacks
package.loaded['default_import_file/workspace/sans-fight/lua/fitdata'] = {}
package.loaded['default_import_file/workspace/sans-fight/lua/textart'] = { glyphs = {} }
package.loaded['default_import_file/workspace/sans-fight/lua/config'] =
  { updateCallback = 'level', templatesFirst = 'sim', legacyTemplateFallback = true,
    textMode = 'control', device = 'auto', tutorial = true }

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
  GetUICanvasSize = function() return 1280, 720 end,
  GetClientUIControl = function(id) if id == 1 then return rootCtrl end return nil end,
  InstantiateClientUIControl = function() return mkControl('inst') end,
  GetGlobalCustomVariableValue = function() error('none') end,
  PrintClientUITree = function() end,
  GetDevice = function() return { Name = 'Mobile', FullName = 'Enum.Device.Mobile', EnumType = 'Device' } end,
}
script = { object = rootCtrl, EnableUpdate = function() end }

local realPrint = print
local main = require('lua' .. '.main')
main.OnInit(); main.OnStart()
local CW, CH = 1280, 720
local S = math.min(CW / 640, CH / 480)
local OX, OY = (CW - 640 * S) / 2, (CH - 480 * S) / 2
local function fireCursor(name, wx, wy)
  local fn = cursor[name]
  if fn then fn({ x = OX + wx * S, y = OY + (480 - wy) * S }) end
end
local function tap(wx, wy) fireCursor('CursorDown', wx, wy); fireCursor('CursorUp', wx, wy) end

local pass, fail = 0, 0
local function ok(c, m)
  if c then pass = pass + 1; print('  PASS ' .. m) else fail = fail + 1; print('  FAIL ' .. m) end
end
local DT = 1 / 30
local function frames(n) for _ = 1, (n or 1) do pcall(main.OnLevelUpdate, DT) end end

print('=== 手机（触摸）端教程探针 ===')
print = realPrint
ok(main.isTouch(), '设备识别为触摸（Mobile）')
local st = main.state()
ok(st and st.state == 'tut_ask', '启动停在二选一（实际 ' .. tostring(st and st.state) .. '）')
-- 先跑两帧：适配层用 pendingPhase 初始化"当前相位"，第一帧会清一次待确认项；
-- 真实游玩时玩家不可能在第一帧就点，所以这里先稳定两帧再点（不是放宽断言）。
frames(2)

-- 二选一：点第一张卡 → 选中；再点一次 → 进入教程（触摸端二段确认）
local card = nil
for _, c in ipairs(core.render(st)) do if c.kind == 'menu' then card = c break end end
ok(card ~= nil, '二选一下发了菜单卡')
if card then
  local cxx, cyy = card.x + card.w / 2, card.y + card.h / 2
  tap(cxx, cyy); frames(1)
  st = main.state()
  ok(main.pending() ~= nil, '第一次点按只选中（待确认）')
  tap(cxx, cyy); frames(1)
  st = main.state()
  ok(st.state == 'tutorial', '第二次点按 → 进入教程（实际 ' .. tostring(st.state) .. '）')
end

-- 摇杆：在固定 HOME（世界 84,392）按下 → 应激活；向上拖 → 灵魂上移（第 1 节是红心，无重力）
local before = main.soul()
ok(before ~= nil, '灵魂坐标已知')
fireCursor('CursorDown', 84, 392)
local _, joy = main.pointer()
ok(joy.active == true, '教程里按下固定摇杆区 → 摇杆激活（修前为 false）')
fireCursor('CursorDrag', 84, 340)
frames(20)
local after = main.soul()
ok(after and before and (before.y - after.y) > 3,
   string.format('向上拖 → 红心上移（%.1f → %.1f，修前完全不动）', before and before.y or -1, after and after.y or -1))
fireCursor('CursorUp', 84, 340)
frames(2)
local _, joy2 = main.pointer()
ok(joy2.active == false, '松手 → 摇杆关闭')

-- ===== 左上角退出图标（2026-10-17 用户口径）=====
--   进入关卡 1 分钟后出现；点它 = 发服务端信号（客户端没有退出 API）。
--   这里把 ServerSignal 换成记录器，验证"1 分钟前不发 / 之后点了就发"。
local sent = {}
game.ServerSignal = function(name) return { SendSignal = function() sent[#sent + 1] = name end } end
fireCursor('CursorDown', 25, 25); fireCursor('CursorUp', 25, 25)
ok(#sent == 0, '1 分钟前点左上角不会发退出信号（实际 ' .. #sent .. ' 条）')
-- 快进：DT=1/30 → 1900 帧 ≈ 63.3s（退出图标默认 60s 出现）
for _ = 1, 1900 do pcall(main.OnLevelUpdate, DT) end
fireCursor('CursorDown', 25, 25); fireCursor('CursorUp', 25, 25)
ok(sent[1] == 'SansFightExit', '1 分钟后点左上角 → 发出 SansFightExit（实际 ' .. tostring(sent[1]) .. '）')

print('')
print(string.format('PASS %d / FAIL %d', pass, fail))
if fail > 0 then os.exit(1) end