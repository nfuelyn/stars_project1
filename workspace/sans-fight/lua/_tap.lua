-- _tap.lua -- tap-chain regression: canvas -> world -> UI hit test.
-- ASCII ONLY on purpose: the fengari harness truncates Lua source lines by BYTES when it
-- prints an error traceback, so any CJK in this file can break the JS print bridge.
-- Path under test (the user's "tap does nothing / frozen" report):
--   canvas mobile-16-9 = 1280x720 -> S=1.5 OX=160 OY=0; world 640x480 with Y GOING DOWN.
--   Menu row is anchored to the SCREEN CENTRE (world y 432..468 in round 0, see main.lua's
--   "按钮行定位" block) and item 1 = "fight" x 85..195 -- so every tap below is taken from the
--   row rect actually DRAWN this frame (main.lastRects + main.menuRowRect), never hard-coded.
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path

local core = require('lua' .. '.core')
local attacks = require('lua' .. '.attacks')
package.loaded['default_import_file/workspace/sans-fight/lua/core'] = core
package.loaded['default_import_file/workspace/sans-fight/lua/attacks'] = attacks
-- 离线单测固定走参数化回退：烘焙容器需要 SetAnchorMin/Max，mock 引擎不实现。
package.loaded['default_import_file/workspace/sans-fight/lua/fitdata'] = {}

local nextId = 1
local keyL, cursorL = {}, {}          -- 记录事件监听，回归里直接驱动真实回调路径
local function mkControl(kind)
  local c = { Id = nextId, kind = kind, visible = true, prefabIndex = 0 }
  nextId = nextId + 1
  -- 属性写入按引擎口径校验：fontSize 要求**整数**，写小数在真机/模拟器会抛
  --   bad argument #2 to 'fontSize' (integer expected, got number)
  -- 于是 pcall(draw) 中断整帧。这里用 __newindex 复刻该约束，任何小数都会让测试失败。
  local store = {}
  return setmetatable(c, {
    __index = function(_, k)
      if k == 'AddKeyEventListener' then return function(_, n, fn) keyL[n] = fn end end
      if k == 'AddCursorEventListener' then return function(_, n, fn) cursorL[n] = fn end end
      local m = {
        SetVisible = 1, SetActive = 1, SetImage = 1, SetSiblingIndex = 1, SetSizeDelta = 1,
        SetAnchoredPosition = 1, SetLocalRotation = 1,
        GetChildren = 1, GetChild = 1, FindChild = 1,
      }
      if m[k] then return function() end end
      return store[k]
    end,
    __newindex = function(_, k, v)
      if k == 'fontSize' and not (math.type(v) == 'integer') then
        error(string.format("bad argument #2 to 'fontSize' (integer expected, got %s=%s)",
          type(v), tostring(v)), 2)
      end
      store[k] = v
    end,
  })
end
local rootCtrl = mkControl('container')
game = {
  -- 用 PC 画布（1600×900 → S=1.875）跑：手机 S=1.5 时字号缩放恰好都是整数，
  -- 会把「字号写成小数」这类 bug 掩盖掉；PC 才会暴露（14*1.875=26.25）。
  GetUICanvasSize = function() return 1600, 900 end,
  GetClientUIControl = function(id) if id == 1 then return rootCtrl end return nil end,
  InstantiateClientUIControl = function() return mkControl('inst') end,
  GetGlobalCustomVariableValue = function() error('none') end,
  PrintClientUITree = function() end,
}

local CW, CH = game.GetUICanvasSize()
local S = math.min(CW / 640, CH / 480)
local OX, OY = (CW - 640 * S) / 2, (CH - 480 * S) / 2
print(string.format('map: canvas=%dx%d S=%.2f OX=%.1f OY=%.1f', CW, CH, S, OX, OY))

local main = require('lua' .. '.main')
main.OnInit()
main.OnStart()

-- 现在开局先停在标题页（难度选择）：先走一次真实点按把它开起来（点空白 = 用当前难度开局），
-- 标题页自身的选档/开局由 lua/_title.lua 覆盖。
pcall(main.OnLevelUpdate, 1.0 / 30.0)
do
  local _, wy0 = main.toWorld(640, 360)
  local ok0, consumed0 = pcall(function() return main.click(OX + 320 * S, OY + 240 * S) end)
  print(string.format('title start: ok=%s consumed=%s centerY=%.0f', tostring(ok0), tostring(consumed0), wy0))
end

local fails, oks = {}, 0
local function eq(name, got, want, tol)
  local okv
  if type(got) == 'number' and type(want) == 'number' then
    okv = math.abs(got - want) <= (tol or 0.01)
  else
    okv = (got == want)
  end
  if okv then oks = oks + 1
  else fails[#fails + 1] = string.format('%s: got %s want %s', name, tostring(got), tostring(want)) end
end

-- (1) pure mapping: canvas -> world. The canvas origin is BOTTOM-LEFT with Y UP
-- (KongZhong/千星 convention; the play page sends y = rect.bottom - clientY, see main.lua's
-- toWorld comment for the exact source lines), while the world is 640x480 with Y DOWN --
-- so the adapter MUST flip Y exactly once, and only once.
local wxp, wyp = main.toWorld(OX + 140 * S, OY + (480 - 421) * S)
eq('toWorld.x', wxp, 140, 0.5)
eq('toWorld.y', wyp, 421, 0.5)
local midx, midy = main.toWorld(CW / 2, CH / 2)
eq('toWorld.center.x', midx, 320, 0.5)
eq('toWorld.center.y', midy, 240, 0.5)
-- pin the direction: canvas y=0 (screen bottom in canvas coords) is world y=480 (world bottom)
do
  local _, topY = main.toWorld(CW / 2, OY)                 -- canvas bottom edge -> world bottom
  local _, botY = main.toWorld(CW / 2, OY + 480 * S)       -- canvas top edge -> world top
  eq('toWorld.canvas-bottom-is-world-bottom', topY, 480, 0.5)
  eq('toWorld.canvas-top-is-world-top', botY, 0, 0.5)
end

-- (2) run into the menu state, then tap the "fight" button. The tap point comes from the row rect
-- drawn THIS frame (screen-centre anchored, world top 432 in round 0), not from a hard-coded y --
-- hard-coded y is exactly what broke when the row moved (it used to be clamped to the box bottom).
local function clearHazards(st)
  if st and st.world then st.world.bones, st.world.sine, st.world.blasters = {}, {}, {} end
end
local reached = false
local frameErrs = 0
for _ = 1, 900 do
  local ok = pcall(main.OnLevelUpdate, 1.0 / 30.0)
  if not ok then frameErrs = frameErrs + 1 end
  local st = main.state()
  if st and st.state == 'menu' then reached = true break end
  clearHazards(main.state())
end
eq('frames-no-error', frameErrs, 0)
eq('reached-menu', reached, true)

-- tap() converts a WORLD point into the canvas coordinates the engine actually delivers:
-- canvas is bottom-left/Y-up, world is top-left/Y-down -> y_canvas = OY + (480 - y_world) * S.
local function tap(wx, wy) return main.click(OX + wx * S, OY + (480 - wy) * S) end
local lm1 = main.lastRects()
local fbx, fby, fbw, fbh = main.menuRowRect(lm1, 1)      -- item 1 = "fight"
eq('tap-row-anchored-to-centre', fby, 432)
local okCall, consumed = pcall(tap, fbx + fbw / 2, fby + fbh / 2)
eq('tap-call-ok', okCall, true)
eq('tap-consumed', consumed, true)
eq('menu-to-attack', main.state() and main.state().state, 'attack')

-- (3) attack bar: any tap inside the box resolves it (anti-freeze)
pcall(tap, 320, 309)
local res = main.state() and main.state().attackResult
eq('attack-resolved', res ~= nil, true)

-- (4) 死亡 → 结局 → 重开：把 hp 压到 0 让逻辑层自己判死，再走真实点按确认重开。
--     这条路径（result 态 + restart 回标题页）此前从未被验证过。
do
  local st = main.state()
  -- 先离开攻击条状态（结算后有 1.2s 停留，且 hurt 只在敌方阶段生效），再吃一次真实命中
  for _ = 1, 90 do
    pcall(main.OnLevelUpdate, 1.0 / 30.0)
    if main.state().state == 'enemy' then break end
  end
  eq('attack-to-enemy', main.state().state, 'enemy')
  st = main.state()
  st.hp = 1
  local okH = pcall(function() core.debugHurt(st, 'hit') end)
  eq('debugHurt-ok', okH, true)
  eq('death-to-result', main.state().state, 'result')
  local okR, consumedR = pcall(tap, 320, 320)
  eq('result-tap-ok', okR, true)
  eq('result-tap-consumed', consumedR, true)
  for _ = 1, 4 do pcall(main.OnLevelUpdate, 1.0 / 30.0) end
  -- 重开走的是 core.restart → start()：直接回到回合 0 的敌方阶段（原作也是"继续打"，不回标题页）
  eq('restart-to-round0', main.state().state, 'enemy')
  eq('restart-round-reset', main.state().round, 0)
  eq('restart-restores-hp', main.state().hp > 0, true)
end

print(string.format('tap regression: %d pass / %d fail', oks, #fails))
for _, f in ipairs(fails) do print('  FAIL ' .. f) end

-- ============================================================================
-- (5) PC platform split: the pointer must NOT act as a joystick (no movement on drag),
--     and a single click on a menu button must select + confirm (hit rect = drawn row).
--     The fake game has no GetDevice() at all -> the adapter must fall back to PC.
-- ============================================================================
eq('pc-device-fallback', main.isTouch(), false)
eq('pc-keyboard-bound', keyL['KeyboardMoveForwardKeyDown'] ~= nil, true)
eq('pc-confirm-bound', keyL['KeyboardMenuConfirmKeyDown'] ~= nil, true)

local function fireCursor(name, wx, wy)
  local fn = cursorL[name]
  if fn then fn({ x = OX + wx * S, y = OY + (480 - wy) * S }) end
end

do
  -- 保证在敌方阶段（只有这一阶段灵魂会动），并清掉危险实体免得中途死亡
  for _ = 1, 600 do
    local st = main.state()
    if st.state == 'enemy' then break end
    clearHazards(st)
    pcall(main.OnLevelUpdate, 1.0 / 30.0)
  end
  eq('pc-drag-enemy', main.state().state, 'enemy')
  pcall(main.OnLevelUpdate, 1.0 / 30.0)
  local before = main.soul()
  eq('pc-drag-soul-known', type(before) == 'table' and type(before.y) == 'number', true)
  -- 左半屏按住 + 拖动（旧实现会在这里起摇杆、还按反方向移动灵魂）
  fireCursor('CursorDown', 100, 300)
  fireCursor('CursorDrag', 100, 180)
  for _ = 1, 10 do pcall(main.OnLevelUpdate, 1.0 / 30.0) end
  local afterUp = main.soul()
  eq('pc-drag-joystick-off', (select(2, main.pointer())).active, false)
  eq('pc-drag-no-move-up', afterUp.x, before.x, 0.001)   -- 竖向拖拽只可能改 y；蓝心会自然下落，所以这里查 x 不变
  fireCursor('CursorDrag', 100, 430)
  for _ = 1, 10 do pcall(main.OnLevelUpdate, 1.0 / 30.0) end
  eq('pc-drag-no-move-down', main.soul().x, before.x, 0.001)
  fireCursor('CursorUp', 100, 430)
  pcall(main.OnLevelUpdate, 1.0 / 30.0)
  eq('pc-drag-no-move-after-up', main.soul().x, before.x, 0.001)
  eq('pc-drag-no-pending', main.pending(), nil)
end

do
  -- 走到菜单行，按**本帧实际绘制的按钮矩形**点第 3 项（道具）：PC 上一下点按就该生效
  local reached = false
  for _ = 1, 900 do
    local st = main.state()
    if st.state == 'menu' then reached = true break end
    clearHazards(st)
    pcall(main.OnLevelUpdate, 1.0 / 30.0)
  end
  eq('pc-menu-reached', reached, true)
  pcall(main.OnLevelUpdate, 1.0 / 30.0)
  local lm = main.lastRects()
  eq('pc-menu-drawn', lm ~= nil, true)
  local bx, by, bw, bh = main.menuRowRect(lm, 3)
  eq('pc-menu-hit-center', main.menuHitTest(lm, bx + bw / 2, by + bh / 2), 3)
  eq('pc-menu-hit-below', main.menuHitTest(lm, bx + bw / 2, by + bh + 12), nil)
  local okTap, consumedTap = pcall(tap, bx + bw / 2, by + bh / 2)
  eq('pc-menu-tap-call-ok', okTap, true)
  eq('pc-menu-tap-consumed', consumedTap, true)
  eq('pc-menu-one-tap-opens-sub', main.state().state, 'sub')
  eq('pc-menu-one-tap-right-panel', main.state().sub, 'item')
  eq('pc-menu-tap-no-pending', main.pending(), nil)
end

print(string.format('pc input regression: %d pass / %d fail (cumulative)', oks, #fails))
for _, f in ipairs(fails) do print('  FAIL ' .. f) end
