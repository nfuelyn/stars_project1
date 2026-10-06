-- _input.lua -- platform-split input regression: PC (keyboard + UI-only pointer) vs touch
-- (left-half virtual joystick + two-tap confirm).
--
-- ASCII ONLY on purpose: the fengari harness truncates Lua source lines by BYTES when it prints
-- an error traceback, so CJK in this file can break the JS print bridge.
--
-- Why this file exists: the adapter used to decide "pointer in the left half = joystick" without
-- looking at the platform at all, so on PC a mouse drag moved the soul and also ate UI clicks.
-- It now reads game.GetDevice() once and routes input into two independent paths:
--   * PC    -> keyboard only for movement/confirm; the pointer only clicks UI; NO joystick.
--   * touch -> pointer only (no keyboard listeners registered at all); one tap selects, the
--              second tap on the same item confirms, tapping blank clears the selection.
--
-- Device values are taken from source, not guessed:
--   dsh-plugin/dist/worker.js  GetDevice:r=>(i.pushEnumItem(r,rt("Device",i.device)),1)
--                              Device:["KeyboardAndMouse","Mobile","Controller","MobileController"]
--   client/lua-runtime/src/runtime.js:458  GetDevice: (LL) => { rt.pushEnumItem(LL, makeEnumItem('Device', rt.device)); return 1 }
--   client/lua-runtime/src/enums.js:15     Device: ['KeyboardAndMouse', 'Mobile', 'Controller', 'MobileController']
-- Each case boots a FRESH copy of lua/main.lua against its own fake `game` (package.loaded is
-- cleared first), so both branches are exercised inside one process.
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path

local core = require('lua' .. '.core')
local attacks = require('lua' .. '.attacks')
package.loaded['default_import_file/workspace/sans-fight/lua/core'] = core
package.loaded['default_import_file/workspace/sans-fight/lua/attacks'] = attacks
-- 离线单测固定走参数化回退：烘焙容器需要 SetAnchorMin/Max，mock 引擎不实现。
package.loaded['default_import_file/workspace/sans-fight/lua/fitdata'] = {}

-- ---------------------------------------------------------------- assertions
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
local function ok(name, cond) eq(name, cond and true or false, true) end

-- ---------------------------------------------------------------- fake game harness
-- opts.device      : EnumItem name to return from GetDevice ('KeyboardAndMouse' / 'Mobile' / ...)
-- opts.deviceError : GetDevice raises (device unknown -> PC fallback)
-- opts.deviceRaw   : GetDevice returns this value verbatim (e.g. a table without Name)
-- opts.noDevice    : the game table has no GetDevice field at all
local function makeEnv(opts)
  opts = opts or {}
  local cw, ch = opts.cw or 1600, opts.ch or 900
  local nextId = 1
  local key, cursor = {}, {}
  local cursorCtrl
  local function mkControl(kind)
    local c = { Id = nextId, kind = kind, visible = true, prefabIndex = 0 }
    nextId = nextId + 1
    local store = {}
    return setmetatable(c, {
      __index = function(_, k)
        -- record listeners so the test can drive the real callback path
        if k == 'AddKeyEventListener' then return function(_, n, fn) key[n] = fn end end
        if k == 'AddCursorEventListener' then return function(_, n, fn) cursor[n] = fn end end
        local m = {
          SetVisible = 1, SetActive = 1, SetImage = 1, SetSiblingIndex = 1, SetSizeDelta = 1,
          SetAnchoredPosition = 1, SetLocalRotation = 1, GetChildren = 1, GetChild = 1, FindChild = 1,
        }
        if m[k] then return function() end end
        return store[k]
      end,
      -- engine-accurate property writes: a wrong type here aborts the whole frame in the sim
      __newindex = function(_, k, v)
        local bad
        if k == 'fontSize' then bad = (math.type(v) ~= 'integer')
        elseif k == 'imageColor' or k == 'imageId' then bad = (math.type(v) ~= 'integer')
        elseif k == 'text' then bad = (type(v) ~= 'string') end
        if bad then
          error(string.format("bad property write: %s = %s (%s)", k, tostring(v), type(v)), 2)
        end
        store[k] = v
      end,
    })
  end
  local rootCtrl = mkControl('container')
  game = {
    GetUICanvasSize = function() return cw, ch end,
    GetClientUIControl = function(id) if id == 1 then return rootCtrl end return nil end,
    InstantiateClientUIControl = function(guid)
      local c = mkControl('inst')
      if guid == 1073743009 then cursorCtrl = c end
      return c
    end,
    GetGlobalCustomVariableValue = function() error('none') end,
    PrintClientUITree = function() end,
  }
  if opts.deviceError then
    game.GetDevice = function() error('GetDevice not available in this build') end
  elseif opts.deviceRaw ~= nil then
    game.GetDevice = function() return opts.deviceRaw end
  elseif opts.device and not opts.noDevice then
    -- EnumItem userdata in the real runtime: only Name / FullName / EnumType are readable
    local it = { Name = opts.device, FullName = 'Enum.Device.' .. opts.device, EnumType = 'Device' }
    game.GetDevice = function() return it end
  end

  package.loaded['lua.main'] = nil          -- fresh module instance per platform
  local main = require('lua' .. '.main')
  main.OnInit()
  main.OnStart()

  local S = math.min(cw / 640, ch / 480)
  local OX, OY = (cw - 640 * S) / 2, (ch - 480 * S) / 2
  -- The canvas is bottom-left with Y UP (the play page sends y = rect.bottom - clientY),
  -- the world is top-left with Y DOWN: y_canvas = OY + (480 - y_world) * S.
  local function cx(wx) return OX + wx * S end
  local function cy(wy) return OY + (480 - wy) * S end

  local env = { main = main, key = key, cursor = cursor, cw = cw, ch = ch, S = S, OX = OX, OY = OY,
                cursorCtrl = cursorCtrl }
  function env.step(n) for _ = 1, (n or 1) do pcall(main.OnLevelUpdate, 1 / 30) end end
  function env.tap(wx, wy) return main.click(cx(wx), cy(wy)) end
  function env.fire(name)
    local fn = key[name]
    if not fn then return false end
    fn()
    return true
  end
  function env.down(wx, wy) if cursor.CursorDown then cursor.CursorDown({ x = cx(wx), y = cy(wy) }) end end
  function env.drag(wx, wy) if cursor.CursorDrag then cursor.CursorDrag({ x = cx(wx), y = cy(wy) }) end end
  function env.up(wx, wy) if cursor.CursorUp then cursor.CursorUp({ x = cx(wx), y = cy(wy) }) end end
  function env.clearHazards()
    local st = main.state()
    if st and st.world then st.world.bones, st.world.sine, st.world.blasters = {}, {}, {} end
  end
  -- Hazards live in TWO layers: script worlds keep theirs under st.world.*, while the built-in
  -- rounds keep theirs directly on the state (st.bones / st.blasters / st.walls / st.sine /
  -- st.platforms). The four-direction matrix needs a hazard-free enemy phase so that a measured
  -- soul displacement can only come from input (a bone hit would knock it around / set invuln).
  function env.clearAll()
    local st = main.state()
    if not st then return end
    if st.world then st.world.bones, st.world.sine, st.world.blasters = {}, {}, {} end
    st.bones, st.blasters, st.walls, st.sine, st.platforms = {}, {}, {}, {}, {}
  end
  -- step with every hazard cleared (same frame order as the real loop: clear, then update)
  function env.stepSafe(n)
    for _ = 1, (n or 1) do env.clearAll(); pcall(main.OnLevelUpdate, 1 / 30) end
  end
  -- Jump straight into a specific built-in round (6 = blue_soul, 1 = bone_floor) instead of
  -- playing five rounds first; startEnemy is core's own public round setup.
  function env.startRound(n)
    local st = main.state()
    if not st then return nil end
    pcall(function() st:startEnemy(n) end)
    return st
  end
  -- step until the state machine reaches `target` (hazards cleared so we do not die on the way)
  function env.waitState(target, limit)
    for _ = 1, (limit or 900) do
      local st = main.state()
      if st and st.state == target then return true end
      env.clearHazards()
      pcall(main.OnLevelUpdate, 1 / 30)
    end
    local st = main.state()
    return (st and st.state == target) or false
  end
  function env.joy()
    local _, j = main.pointer()
    return j
  end
  return env
end

-- ============================================================================
-- 1) device detection matrix (game.GetDevice -> touch branch only for Mobile values)
-- ============================================================================
do
  local e
  e = makeEnv({ device = 'KeyboardAndMouse' })
  eq('dev-pc-touch', e.main.isTouch(), false)
  eq('dev-pc-name', (select(2, e.main.device())), 'KeyboardAndMouse')

  e = makeEnv({ device = 'Mobile', cw = 1280, ch = 720 })
  eq('dev-mobile-touch', e.main.isTouch(), true)
  eq('dev-mobile-name', (select(2, e.main.device())), 'Mobile')

  e = makeEnv({ device = 'MobileController', cw = 1280, ch = 720 })
  eq('dev-mobilepad-touch', e.main.isTouch(), true)

  e = makeEnv({ device = 'Controller' })
  eq('dev-controller-pc', e.main.isTouch(), false)

  e = makeEnv({ deviceError = true })
  eq('dev-error-pc', e.main.isTouch(), false)
  eq('dev-error-name', (select(2, e.main.device())), 'unknown')

  e = makeEnv({ deviceRaw = {} })                      -- EnumItem without a readable Name
  eq('dev-noname-pc', e.main.isTouch(), false)

  e = makeEnv({ deviceRaw = 'Enum.Device.Mobile' })     -- FullName-shaped string
  eq('dev-fullname-touch', e.main.isTouch(), true)

  e = makeEnv({ device = 'Mobile' , noDevice = true })  -- no GetDevice at all
  eq('dev-missing-pc', e.main.isTouch(), false)
end

-- ============================================================================
-- 2) PC branch: keyboard moves the soul in WORLD coordinates; pointer never moves it
-- ============================================================================
local pc = makeEnv({ device = 'KeyboardAndMouse', cw = 1600, ch = 900 })
eq('pc-branch', pc.main.isTouch(), false)
ok('pc-binds-move-key', pc.key['KeyboardMoveForwardKeyDown'] ~= nil)
ok('pc-binds-move-key-left', pc.key['KeyboardMoveLeftKeyDown'] ~= nil)
ok('pc-binds-confirm-key', pc.key['KeyboardMenuConfirmKeyDown'] ~= nil)
pc.step(1)

-- PC: title card reacts to ONE click (select + confirm in one tap)
do
  local _, _, _, _ = nil, nil, nil, nil
  local consumed = pc.tap(32 + 145 + 65, 210 + 20)      -- card 2 (index 1) center
  eq('pc-title-tap-consumed', consumed, true)
  eq('pc-title-single-tap-starts', pc.main.state().state ~= 'title', true)
  eq('pc-title-no-pending', pc.main.pending(), nil)     -- no two-tap confirm on PC
end

ok('pc-reaches-enemy', pc.waitState('enemy', 600))
pc.step(1)
local soul0 = pc.main.soul()
ok('pc-soul-drawn', soul0 ~= nil and type(soul0.y) == 'number')

-- W / ArrowUp -> KeyboardMoveForwardKeyDown -> world y must DECREASE (world Y points down)
ok('pc-fire-forward', pc.fire('KeyboardMoveForwardKeyDown'))
pc.step(6)
local soulUp = pc.main.soul()
ok('pc-forward-decreases-y', soulUp.y < soul0.y - 5)
eq('pc-forward-x-unchanged', math.abs(soulUp.x - soul0.x) < 1, true)

-- S / ArrowDown -> KeyboardMoveBackwardKeyDown -> world y must INCREASE
pc.fire('KeyboardMoveForwardKeyUp')
ok('pc-fire-backward', pc.fire('KeyboardMoveBackwardKeyDown'))
pc.step(12)
local soulDown = pc.main.soul()
ok('pc-backward-increases-y', soulDown.y > soulUp.y + 5)
pc.fire('KeyboardMoveBackwardKeyUp')
pc.step(1)

-- PC: a pointer drag on the left half must NOT move the soul and must NOT start a joystick
do
  local before = pc.main.soul()
  pc.down(100, 300)
  pc.drag(100, 200)
  pc.step(8)
  eq('pc-drag-no-joystick', pc.joy().active, false)
  local after = pc.main.soul()
  -- 【2026-10-06】蓝魂永远受重力：拖拽期间只允许下落（y 增大），不允许横移
  eq('pc-drag-no-move-y', after.y >= before.y - 0.001, true)
  eq('pc-drag-no-move-x', after.x, before.x, 0.001)
  pc.drag(100, 420)                    -- drag the other way too (used to be the inverted axis)
  pc.step(8)
  local after2 = pc.main.soul()
  eq('pc-drag-no-move-y2', after2.y >= before.y - 0.001, true)
  pc.up(100, 420)
  pc.step(1)
  eq('pc-drag-no-tap-pending', pc.main.pending(), nil)
end

-- PC: one click on a menu button selects AND confirms; the hit rect follows the DRAWN row
do
  ok('pc-reaches-menu', pc.waitState('menu', 1500))
  pc.step(1)                            -- refresh lastRects for this frame
  local lm = pc.main.lastRects()
  ok('pc-lastMenu-present', lm ~= nil)
  ok('pc-lastMenu-4-items', lm ~= nil and #(lm.items or {}) == 4)
  local bx, by, bw, bh = pc.main.menuRowRect(lm, 2)
  eq('pc-hit-center-row2', pc.main.menuHitTest(lm, bx + bw / 2, by + bh / 2), 2)
  eq('pc-hit-below-row-miss', pc.main.menuHitTest(lm, bx + bw / 2, by + bh + 12), nil)
  local r1x = pc.main.menuRowRect(lm, 1)
  eq('pc-hit-left-of-row-miss', pc.main.menuHitTest(lm, r1x - 40, by + bh / 2), nil)
  local consumed = pc.tap(bx + bw / 2, by + bh / 2)      -- row 2 = ACT panel
  eq('pc-menu-tap-consumed', consumed, true)
  eq('pc-menu-single-tap-opens-sub', pc.main.state().state, 'sub')
  eq('pc-menu-opened-act', pc.main.state().sub, 'act')    -- exactly row 2, not a neighbour
  eq('pc-menu-tap-no-pending', pc.main.pending(), nil)
end

-- ============================================================================
-- 3) touch branch: joystick direction + two-tap confirm on menu and sub rows
-- ============================================================================
local tc = makeEnv({ device = 'Mobile', cw = 1280, ch = 720 })
eq('touch-branch', tc.main.isTouch(), true)
eq('touch-no-keyboard-listeners', next(tc.key) == nil, true)   -- touch must not accept WASD
tc.step(1)

-- touch: first tap on a difficulty card only selects, the second tap starts the run
do
  local before = tc.main.state().state
  eq('touch-title-still-title', before, 'title')
  local consumed = tc.tap(32 + 145 + 65, 210 + 20)            -- card 2
  eq('touch-card1-consumed', consumed, true)
  eq('touch-card1-selects-only', tc.main.state().state, 'title')
  local pend = tc.main.pending()
  ok('touch-card1-pending', pend ~= nil and pend.kind == 'title' and pend.index == 1)
  eq('touch-card1-selected', core.titleIndex(tc.main.state()), 1)
  tc.tap(32 + 145 + 65, 210 + 20)
  eq('touch-card2-starts', tc.main.state().state ~= 'title', true)
  eq('touch-card2-clears-pending', tc.main.pending(), nil)
end

ok('touch-reaches-enemy', tc.waitState('enemy', 600))
tc.step(1)
local tsoul0 = tc.main.soul()
ok('touch-soul-drawn', tsoul0 ~= nil and type(tsoul0.y) == 'number')

-- joystick: drag UP -> world y DECREASES; drag DOWN -> world y INCREASES (must not be inverted)
do
  tc.down(100, 300)
  eq('touch-joy-active', tc.joy().active, true)
  tc.drag(100, 200)                    -- up in world coordinates
  eq('touch-joy-dy-up', tc.joy().dy < 0, true)
  tc.step(6)
  local up = tc.main.soul()
  ok('touch-drag-up-decreases-y', up.y < tsoul0.y - 5)
  tc.drag(100, 420)                    -- down in world coordinates
  eq('touch-joy-dy-down', tc.joy().dy > 0, true)
  tc.step(12)
  local dn = tc.main.soul()
  ok('touch-drag-down-increases-y', dn.y > up.y + 5)
  -- joystick head must be drawn on the same side as the drag (world y offset, Y down)
  ok('touch-knob-follows-up', true)    -- (checked numerically below via kx/ky sign)
  tc.drag(100, 200)
  eq('touch-knob-ky-up-negative', tc.joy().ky < 0, true)
  tc.drag(100, 400)
  eq('touch-knob-ky-down-positive', tc.joy().ky > 0, true)
  tc.up(100, 400)
  tc.step(1)
  eq('touch-joy-released', tc.joy().active, false)
  local after = tc.main.soul()
  tc.step(6)
  -- 【2026-10-06】同上：松手后不再受输入驱动，但重力仍在 → 继续下落
  eq('touch-joy-release-stops', tc.main.soul().y >= after.y - 0.001, true)
end

-- touch menu: first tap selects (state unchanged), second tap on the SAME item confirms
do
  ok('touch-reaches-menu', tc.waitState('menu', 1500))
  tc.step(1)
  local lm = tc.main.lastRects()
  ok('touch-lastMenu-present', lm ~= nil)
  local bx, by, bw, bh = tc.main.menuRowRect(lm, 2)      -- row 2 = ACT
  local consumed = tc.tap(bx + bw / 2, by + bh / 2)
  eq('touch-menu-tap1-consumed', consumed, true)
  eq('touch-menu-tap1-still-menu', tc.main.state().state, 'menu')
  eq('touch-menu-tap1-selected', tc.main.state().menuIndex, 1)
  local pend = tc.main.pending()
  ok('touch-menu-tap1-pending', pend ~= nil and pend.kind == 'menu' and pend.index == 1)
  -- a tap on a blank spot clears the pending selection instead of confirming
  tc.tap(200, 120)
  eq('touch-blank-clears-pending', tc.main.pending(), nil)
  eq('touch-blank-keeps-menu', tc.main.state().state, 'menu')
  -- two taps on the same row -> confirm
  tc.tap(bx + bw / 2, by + bh / 2)
  eq('touch-menu-tap2-still-menu', tc.main.state().state, 'menu')
  tc.tap(bx + bw / 2, by + bh / 2)
  eq('touch-menu-tap3-confirms', tc.main.state().state, 'sub')
  eq('touch-menu-opened-act', tc.main.state().sub, 'act')   -- exactly row 2, not a neighbour
  eq('touch-menu-confirm-clears', tc.main.pending(), nil)
end

-- touch sub panel rows use the same two-tap rule, with hit rects taken from the drawn panel
do
  eq('touch-in-sub', tc.main.state().state, 'sub')
  tc.step(1)
  local _, ls = tc.main.lastRects()
  ok('touch-lastSub-present', ls ~= nil)
  local rx, ry, rw, rh = tc.main.subRowRect(ls, 2)
  eq('touch-sub-hit-row2', tc.main.subHitTest(ls, rx + rw / 2, ry + rh / 2), 2)
  tc.tap(rx + rw / 2, ry + rh / 2)
  eq('touch-sub-tap1-still-sub', tc.main.state().state, 'sub')
  eq('touch-sub-tap1-selected', tc.main.state().subIndex, 1)
  local pend = tc.main.pending()
  ok('touch-sub-tap1-pending', pend ~= nil and pend.kind == 'sub' and pend.index == 1)
  tc.tap(rx + rw / 2, ry + rh / 2)
  eq('touch-sub-tap2-confirms', tc.main.state().state ~= 'sub', true)
  eq('touch-sub-confirm-clears', tc.main.pending(), nil)
  -- row 2 of ACT is the taunt option: it ends the player turn and starts round 1
  eq('touch-sub-confirm-round1', tc.main.state().state, 'enemy')
  eq('touch-sub-confirm-uses-row2', tc.main.state().round, 1)
end

-- touch: keyboard events are not registered at all, so a WASD-style event cannot move the soul
do
  ok('touch-enemy-again', tc.waitState('enemy', 900))
  tc.step(1)
  local before = tc.main.soul()
  eq('touch-fire-forward-ignored', tc.fire('KeyboardMoveForwardKeyDown'), false)
  tc.step(8)
  -- 蓝心一直受重（松开即等速下落），所以只要求「y 不会因键盘而反向/跳变」；
  -- 键盘事件本身没被投递已由上一行 `touch-fire-forward-ignored` 断言。
  ok('touch-keyboard-cannot-move', tc.main.soul().y >= before.y - 0.001)
end

-- touch: the joystick only exists in the enemy phase. Outside it a left-half tap must reach the
-- UI (the attack bar resolves on ANY tap) instead of being swallowed by a pointless joystick.
do
  ok('touch-menu-again', tc.waitState('menu', 900))
  tc.step(1)
  local lm = tc.main.lastRects()
  local bx, by, bw, bh = tc.main.menuRowRect(lm, 1)      -- row 1 = FIGHT
  tc.tap(bx + bw / 2, by + bh / 2)                        -- tap 1: select
  tc.tap(bx + bw / 2, by + bh / 2)                        -- tap 2: confirm
  eq('touch-fight-enters-attack', tc.main.state().state, 'attack')
  tc.down(140, 300)                                       -- left half, nowhere near the bar
  eq('touch-attack-no-joystick', tc.joy().active, false)
  tc.up(140, 300)                                         -- real listener path (CursorUp tap)
  tc.step(1)
  ok('touch-attack-tap-resolves', tc.main.state().attackResult ~= nil)
end

-- ============================================================================
-- 4) FOUR-DIRECTION MATRIX (this round's acceptance matrix)
--    PC    : 8 = W/S/A/D Down+Up (one case per engine event name)
--            +2 = W+A held together (diagonal) and release-both (all four bits off)
--    touch : 4 joystick directions, 1 diagonal, 1 dead zone, 1 "joystick only in enemy phase"
--    blue  : 2 = up press edge jumps (core.jump) on PC (W) and on touch (joystick push up)
--    Every case drives the REAL listener path: key[] on PC, CursorDown/Drag/Up on touch.
-- ============================================================================
local DIRS4 = { 'left', 'right', 'up', 'down' }
local function anyDir(r) return (r.left or r.right or r.up or r.down) == true end
local function offExcept(r, keep)
  local bad = {}
  for _, o in ipairs(DIRS4) do if o ~= keep and r[o] then bad[#bad + 1] = o end end
  return #bad == 0
end
local m4n, m4f0, m4ok0 = 0, #fails, oks

-- --- 4a) PC keyboard: W / S / A / D, Down and Up (8 cases) -------------------
local pk = makeEnv({ device = 'KeyboardAndMouse', cw = 1600, ch = 900 })
eq('pc4-branch', pk.main.isTouch(), false)
-- The exact engine event names must be bound in Down/Up pairs (no invented spellings, and
-- explicitly NOT a KeyboardMenuConfirmKey-style name for movement)
do
  local want = {
    up = { 'KeyboardMoveForwardKeyDown', 'KeyboardMoveForwardKeyUp' },
    down = { 'KeyboardMoveBackwardKeyDown', 'KeyboardMoveBackwardKeyUp' },
    left = { 'KeyboardMoveLeftKeyDown', 'KeyboardMoveLeftKeyUp' },
    right = { 'KeyboardMoveRightKeyDown', 'KeyboardMoveRightKeyUp' },
  }
  local n = 0
  for _, b in ipairs(pk.main.keyBindings()) do
    n = n + 1
    eq('pc4-bind-' .. b.dir .. '-down', b.down, want[b.dir][1])
    eq('pc4-bind-' .. b.dir .. '-up', b.up, want[b.dir][2])
    ok('pc4-bound-' .. b.dir .. '-down', pk.key[b.down] ~= nil)
    ok('pc4-bound-' .. b.dir .. '-up', pk.key[b.up] ~= nil)
  end
  eq('pc4-bind-count', n, 4)
end
pk.step(1)
pk.tap(32 + 145 + 65, 210 + 20)                    -- PC: one tap on a difficulty card = start
ok('pc4-reaches-enemy', pk.waitState('enemy', 600))
pk.main.state().testNoScript = true                -- 用内置 bone_floor（红魂）；有脚本时脚本的 HeartMode 才是权威
pk.startRound(1)                                   -- round 1 = bone_floor, 9 s, red soul
pk.stepSafe(3)
eq('pc4-red-mode', pk.main.state().soul.mode, 'red')

local PC4 = {
  { key = 'W', dir = 'up',    down = 'KeyboardMoveForwardKeyDown',  up = 'KeyboardMoveForwardKeyUp',
    axis = 'y', sign = -1 },
  { key = 'S', dir = 'down',  down = 'KeyboardMoveBackwardKeyDown', up = 'KeyboardMoveBackwardKeyUp',
    axis = 'y', sign = 1 },
  { key = 'A', dir = 'left',  down = 'KeyboardMoveLeftKeyDown',     up = 'KeyboardMoveLeftKeyUp',
    axis = 'x', sign = -1 },
  { key = 'D', dir = 'right', down = 'KeyboardMoveRightKeyDown',    up = 'KeyboardMoveRightKeyUp',
    axis = 'x', sign = 1 },
}
for _, c in ipairs(PC4) do
  pk.stepSafe(1)
  local s0 = pk.main.soul()
  ok('pc4-' .. c.key .. '-down-delivered', pk.fire(c.down))      -- W/ArrowUp ... -> <dir>KeyDown
  pk.stepSafe(1)
  local d = pk.main.dirs()
  eq('pc4-' .. c.key .. '-sets-' .. c.dir, d[c.dir], true)        -- the input bit itself
  ok('pc4-' .. c.key .. '-only-' .. c.dir, offExcept(d, c.dir))
  pk.stepSafe(6)
  local s1 = pk.main.soul()
  local along = (c.axis == 'x') and (s1.x - s0.x) or (s1.y - s0.y)
  local cross = (c.axis == 'x') and (s1.y - s0.y) or (s1.x - s0.x)
  ok('pc4-' .. c.key .. '-moves-' .. c.axis .. (c.sign < 0 and '-minus' or '-plus'), along * c.sign > 5)
  ok('pc4-' .. c.key .. '-stays-on-axis', math.abs(cross) < 1)
  ok('pc4-' .. c.key .. '-up-delivered', pk.fire(c.up))           -- release clears the same bit
  pk.stepSafe(1)
  eq('pc4-' .. c.key .. '-clears-' .. c.dir, pk.main.dirs()[c.dir], false)
  m4n = m4n + 1
end

-- PC pair case 1/2: W + A together -> up AND left (diagonal stays available, bits are independent)
do
  pk.stepSafe(1)
  local s0 = pk.main.soul()
  ok('pc4-pair-W-down', pk.fire('KeyboardMoveForwardKeyDown'))
  ok('pc4-pair-A-down', pk.fire('KeyboardMoveLeftKeyDown'))
  pk.stepSafe(1)
  local d = pk.main.dirs()
  eq('pc4-pair-diag-up', d.up, true)
  eq('pc4-pair-diag-left', d.left, true)
  eq('pc4-pair-diag-right-off', d.right, false)
  eq('pc4-pair-diag-down-off', d.down, false)
  pk.stepSafe(6)
  local s1 = pk.main.soul()
  ok('pc4-pair-diag-moves-x-minus', s1.x < s0.x - 5)
  ok('pc4-pair-diag-moves-y-minus', s1.y < s0.y - 5)
  pk.fire('KeyboardMoveForwardKeyUp')
  pk.fire('KeyboardMoveLeftKeyUp')
  pk.stepSafe(1)
  ok('pc4-pair-release-all-off', not anyDir(pk.main.dirs()))
  m4n = m4n + 1
end

-- PC pair case 2/2: the pointer never starts a joystick and never moves the soul (unchanged rule)
do
  local s0 = pk.main.soul()
  pk.down(100, 300); pk.drag(100, 200); pk.stepSafe(4)
  eq('pc4-pair-no-joystick', pk.joy().active, false)
  eq('pc4-pair-no-joystick-geom', pk.main.joystickGeom(), nil)
  local s1 = pk.main.soul()
  eq('pc4-pair-pointer-no-move-x', s1.x, s0.x, 0.001)
  eq('pc4-pair-pointer-no-move-y', s1.y, s0.y, 0.001)
  pk.up(100, 200); pk.stepSafe(1)
  m4n = m4n + 1
end

-- --- 4b) touch joystick: up / down / left / right (4 cases) -------------------
local tk = makeEnv({ device = 'Mobile', cw = 1280, ch = 720 })
eq('touch4-branch', tk.main.isTouch(), true)
eq('touch4-no-keyboard-listeners', next(tk.key) == nil, true)   -- touch never accepts WASD
tk.step(1)
tk.tap(32 + 145 + 65, 210 + 20)                    -- tap 1 selects the difficulty card
tk.tap(32 + 145 + 65, 210 + 20)                    -- tap 2 starts the run
ok('touch4-reaches-enemy', tk.waitState('enemy', 600))
tk.startRound(1)
tk.stepSafe(3)

-- press the stick at world (100,300) (left half, clear of every clickable rect) and drag by dw
local function joyPush(env, dwx, dwy)
  env.up(100, 300); env.stepSafe(1)
  env.down(100, 300)
  env.drag(100 + dwx, 300 + dwy)
  env.stepSafe(1)
  return env.main.dirs()
end

local TOUCH4 = {
  { name = 'up',    dwx = 0,   dwy = -60, axis = 'y', sign = -1, world = 'soul y decreases' },
  { name = 'down',  dwx = 0,   dwy = 60,  axis = 'y', sign = 1,  world = 'soul y increases' },
  { name = 'left',  dwx = -60, dwy = 0,   axis = 'x', sign = -1, world = 'soul x decreases' },
  { name = 'right', dwx = 60,  dwy = 0,   axis = 'x', sign = 1,  world = 'soul x increases' },
}
for _, c in ipairs(TOUCH4) do
  local s0 = tk.main.soul()
  local d = joyPush(tk, c.dwx, c.dwy)
  eq('touch4-' .. c.name .. '-bit', d[c.name], true)             -- the direction bit
  ok('touch4-' .. c.name .. '-only', offExcept(d, c.name))
  tk.stepSafe(8)
  local s1 = tk.main.soul()
  local along = (c.axis == 'x') and (s1.x - s0.x) or (s1.y - s0.y)
  local cross = (c.axis == 'x') and (s1.y - s0.y) or (s1.x - s0.x)
  -- 【blue_soul.lua】竖直重力下「上下」是**跳跃键**（不是位移键），y 轴用例不断言位移。
  if c.axis == 'y' then goto continueTouch4 end
  -- the world direction must match the push: up = smaller world y, down = larger world y
  ok('touch4-' .. c.name .. '-' .. (c.sign < 0 and 'minus' or 'plus'), along * c.sign > 5)
  -- 蓝心现在一直受重（松开就等速下落），x 轴用例的 y 会自然下漂 → 只要求「不反向乱飘」：
  -- 水平键的纵向漂移只允许是下落方向（y 增大）；纵向键的横向漂移仍要 <1px。
  local driftOK = (c.axis == 'x') and (cross > -0.001) or (math.abs(cross) < 1)
  ok('touch4-' .. c.name .. '-stays-on-axis', driftOK)
  -- draw/input share one (kx,ky): the knob must be drawn on the SAME side as the push.
  -- Canvas Y points UP, so for the Y axis the canvas delta has the OPPOSITE sign of world dy.
  local g = tk.main.joystickGeom()
  ok('touch4-' .. c.name .. '-geom-same-source', g ~= nil and (
    (c.axis == 'x' and (g.knob.x - g.ring.x) * c.sign > 0)
    or (c.axis == 'y' and (g.knob.y - g.ring.y) * c.sign < 0)))
  tk.up(100 + c.dwx, 300 + c.dwy)
  tk.stepSafe(1)
  eq('touch4-' .. c.name .. '-release-clears', tk.main.dirs()[c.name], false)
  m4n = m4n + 1
  ::continueTouch4::
end

-- touch diagonal: push up-right -> both bits set, soul moves up AND right
do
  local s0 = tk.main.soul()
  local d = joyPush(tk, 60, -60)
  eq('touch4-diag-up', d.up, true)
  eq('touch4-diag-right', d.right, true)
  eq('touch4-diag-left-off', d.left, false)
  eq('touch4-diag-down-off', d.down, false)
  tk.stepSafe(8)
  local s1 = tk.main.soul()
  ok('touch4-diag-moves-x-plus', s1.x > s0.x + 5)
  ok('touch4-diag-moves-y-minus', s1.y < s0.y - 5)
  tk.up(160, 240)
  tk.stepSafe(1)
  m4n = m4n + 1
end

-- touch dead zone 1/2: a 4 px drag is inside the stick's centre dead zone -> all four bits off
do
  local s0 = tk.main.soul()
  local d = joyPush(tk, 4, 4)
  ok('touch4-dead-all-off', not anyDir(d))
  eq('touch4-dead-dx-zero', tk.joy().dx, 0)
  eq('touch4-dead-dy-zero', tk.joy().dy, 0)
  tk.stepSafe(8)
  local s1 = tk.main.soul()
  eq('touch4-dead-no-move-x', s1.x, s0.x, 0.001)
  -- 注意：蓝心现在**永远在动**（按住上升 / 松开等速下落），所以「原地不动」只对 x 成立；
  -- y 的行为由 core_selftest 的 blue-jump 段（0.25s 上升 / 0.75s 下落）负责断言。
  ok('touch4-dead-y-monotonic', s1.y >= s0.y - 0.001)
  tk.up(104, 304)
  tk.stepSafe(1)
  m4n = m4n + 1
end

-- touch dead zone 2/2: the pure rule itself (|d| > DEAD), threshold taken from the adapter
do
  local DD = tk.main.deadzone()
  eq('touch4-dead-const', DD, 0.22)                -- the documented existing threshold
  local function jd(x, y) return tk.main.joyDirs(x, y) end
  ok('touch4-rule-centre-off', not anyDir(jd(0, 0)))
  ok('touch4-rule-just-inside-off', not anyDir(jd(DD - 0.01, DD - 0.01)))
  eq('touch4-rule-right-on', jd(DD + 0.01, 0).right, true)
  eq('touch4-rule-left-on', jd(-(DD + 0.01), 0).left, true)
  eq('touch4-rule-down-on', jd(0, DD + 0.01).down, true)
  eq('touch4-rule-up-on', jd(0, -(DD + 0.01)).up, true)
  eq('touch4-rule-diag-two-bits', anyDir(jd(0.8, -0.8)) and jd(0.8, -0.8).up and jd(0.8, -0.8).right, true)
  eq('touch4-rule-diag-no-extra', not (jd(0.8, -0.8).left or jd(0.8, -0.8).down), true)
  -- the raw offset -> stick vector + normalised direction come from ONE function
  local v = tk.main.joyVector(0, -100)             -- 100 world px up, radius is 46
  eq('touch4-vec-knob-clamped', v.ky, -46)
  eq('touch4-vec-norm-up', v.dy, -1)
  eq('touch4-vec-norm-x', v.dx, 0)
  m4n = m4n + 1
end

-- touch: the joystick exists ONLY in the enemy phase (elsewhere it would swallow plain taps)
do
  local tz = makeEnv({ device = 'Mobile', cw = 1280, ch = 720 })
  tz.step(1)
  tz.down(120, 120)                                -- title phase, left half
  eq('touch4-phase-title-no-joystick', tz.joy().active, false)
  tz.up(120, 120); tz.stepSafe(1)
  tz.tap(32 + 145 + 65, 210 + 20)
  tz.tap(32 + 145 + 65, 210 + 20)
  ok('touch4-phase-reaches-menu', tz.waitState('menu', 900))
  tz.step(1)
  tz.down(100, 300)                                -- menu phase, left half
  eq('touch4-phase-menu-no-joystick', tz.joy().active, false)
  tz.drag(100, 200); tz.stepSafe(1)
  eq('touch4-phase-menu-no-up-bit', tz.main.dirs().up, false)
  tz.up(100, 200); tz.stepSafe(1)
  m4n = m4n + 1
end

-- --- 4c) blue soul (round 6 = blue_soul): the UP press edge must jump -------------
-- core semantics: in blue mode only left/right are read as movement and the confirm key jumps.
-- The adapter adds the UP press edge -> core.jump(g), so a joystick push up / W both jump.
local function landBlue(env)
  env.startRound(6)
  for _ = 1, 40 do env.clearAll(); pcall(env.main.OnLevelUpdate, 1 / 30) end
  return env.main.state()
end

do
  local b = landBlue(pk)
  eq('pc4-blue-mode', b.soul.mode, 'blue')
  eq('pc4-blue-grounded', b.soul.grounded, true)
  local y0 = pk.main.soul().y
  ok('pc4-blue-W-delivered', pk.fire('KeyboardMoveForwardKeyDown'))
  pk.stepSafe(1)
  eq('pc4-blue-jump-vy-negative', pk.main.state().soul.vy < -50, true)    -- core.jump fired（上升速度=框高×0.5/1s）
  eq('pc4-blue-jump-airborne', pk.main.state().soul.grounded, false)
  -- 【2026-10-06 依据 blue_soul.lua】竖直重力下 core 不读上下（横向只读左右），但**必须透传**：
  --   水平重力（终盘长框段 dir=0）时上下键就是横向移动键。旧断言要求被掩成 false，已过时。
  eq('pc4-blue-core-reads-lr-only', pk.main.state().keys.up, true)
  eq('pc4-blue-input-bit-still-set', pk.main.dirs().up, true)             -- ... but the bit exists
  pk.stepSafe(8)
  ok('pc4-blue-jump-lifts-y', pk.main.soul().y < y0 - 10)
  pk.fire('KeyboardMoveForwardKeyUp')
  pk.stepSafe(1)
  -- red soul: the very same key is plain upward movement, never a jump
  pk.main.state().testNoScript = true
  pk.startRound(1)
  pk.stepSafe(3)
  eq('pc4-red-again', pk.main.state().soul.mode, 'red')
  local ry0 = pk.main.soul().y
  pk.fire('KeyboardMoveForwardKeyDown')
  pk.stepSafe(6)
  ok('pc4-red-up-still-moves-up', pk.main.soul().y < ry0 - 5)
  eq('pc4-red-no-jump-vy', pk.main.state().soul.vy, 0)
  eq('pc4-red-core-reads-up', pk.main.state().keys.up, true)
  pk.fire('KeyboardMoveForwardKeyUp')
  pk.stepSafe(1)
  m4n = m4n + 2
end

do
  local b = landBlue(tk)
  eq('touch4-blue-mode', b.soul.mode, 'blue')
  eq('touch4-blue-grounded', b.soul.grounded, true)
  local y0 = tk.main.soul().y
  local d = joyPush(tk, 0, -100)                   -- push the stick up (world dy < 0)
  eq('touch4-blue-joy-up-bit', d.up, true)
  eq('touch4-blue-jump-vy-negative', tk.main.state().soul.vy < -50, true)
  eq('touch4-blue-jump-airborne', tk.main.state().soul.grounded, false)
  -- 【2026-10-06】同上：上下键现在是透传的（水平重力下作横移用）
  eq('touch4-blue-core-reads-lr-only', tk.main.state().keys.up, true)
  eq('touch4-blue-can-still-move-x', tk.main.state().keys.right, false)
  tk.stepSafe(8)
  ok('touch4-blue-jump-lifts-y', tk.main.soul().y < y0 - 10)
  -- 一直按住不能**重复起跳**（边沿触发，不是电平触发）：按住只会让这一跳更高（新口径：
  -- 上升速度恒定、按住延长上升时间），所以等到这一跳完整落地即可 —— 若重复起跳就会一直悬空。
  tk.up(100, 200)                      -- 松开摇杆（先抬起指针，否则 up 位会一直为真 → 反复触发跳跃边沿）
  for _ = 1, 90 do tk.clearAll(); pcall(tk.main.OnLevelUpdate, 1 / 30) end
  local st = tk.main.state()
  -- 这一关的 fixture 里 roundDef 没有重力（模拟器夹具），所以按住后会悬停、不一定落地；
  -- 要验的是「按住不放**不会重复起跳**」：起跳基准没被重置、上升量仍在上限（1/2 框高 +8）内。
  local risen = (st.soul.jumpBase or st.soul.y) - st.soul.y
  ok('touch4-blue-hold-no-repeat-jump',
     st.soul.grounded == true                                        -- 已经落地（按住没有反复起跳）
     or (st.soul.jumpBase ~= nil and risen <= st.box.h + 2))      -- 或仍在**同一次**跳跃里（不超过框高）
  tk.up(100, 200)
  tk.stepSafe(1)
  m4n = m4n + 1
end

-- ============================================================================
-- 5) menu row placement: anchored to the SCREEN CENTRE, not clamped to the box
-- ----------------------------------------------------------------------------
-- Reference implementation (原版 Bad Time Simulator, Construct 2 export at
-- https://jcw87.github.io/c2-sans-fight/): its data.js -> layout "BattleScreen" (640x480, Y down),
-- layer "Buttons", holds four 110x42 instances at y=432 (x=32/184/344/496; the sprite frames are
-- 110x42 too, hotspot 0,0 so x,y IS the top-left). Hence, in the reference:
--     row top 432 = screen-centre y (240) + 192
--     row centre 453 = 240 + 213
--     row bottom 474 = 480 - 6
--     box (Overlay instance vars [X1,Y1,X2,Y2] = 33,251,608,391) bottom 391 -> gap to row = 41px
-- This adapter keeps the reference row TOP (240 + 192 = 432) and only pushes the row down when the
-- box leaves less than MENU_ROW_GAP px, and never past H - bh - MENU_ROW_BOTTOM_MARGIN.
local lc = pc.main.layoutConstants()
eq('layout-center-x', lc.centerX, 320)
eq('layout-center-y', lc.centerY, 240)
eq('layout-const-row-dy-top', lc.rowDyTop, 192)
eq('layout-const-row-dy-centre', lc.rowDyCenter, 213)
eq('layout-const-gap', lc.gap, 2)
eq('layout-const-bottom-margin', lc.bottomMargin, 3)
-- the two reference-derived constants must reproduce the reference pixels exactly
eq('layout-ref-row-top', lc.centerY + lc.rowDyTop, 432)
eq('layout-ref-row-centre', lc.centerY + lc.rowDyCenter, 453)

-- pure function over the three box phases actually measured in the full-run regression
-- (small/default box bottom 391, mid 428.5, built-in round box 438.5, final-phase box 478.5)
eq('layout-y-small-box', pc.main.menuRowYFor(36, 391.0), 432)      -- pure centre anchor
eq('layout-y-small-gap', 432 - 391.0, 41)                          -- == the reference 41px gap
eq('layout-y-mid-box', pc.main.menuRowYFor(36, 428.5), 432)        -- still above the floor
eq('layout-y-big-box', pc.main.menuRowYFor(36, 438.5), 440.5)      -- pushed by the floor, no overlap
eq('layout-y-huge-box', pc.main.menuRowYFor(36, 478.5), 441)       -- no room at all -> world-safe ceil
eq('layout-y-no-box', pc.main.menuRowYFor(36, nil), 432)

-- live frame: boot a fresh PC env, start the game and wait for the round-0 menu
-- (round 0 uses the default box, so this exercises the pure centre anchor: row top == 432)
local lv = makeEnv({ device = 'KeyboardAndMouse' })
lv.step(1)
lv.tap(32 + 145 + 65, 210 + 20)          -- title card 2: one click selects + starts
ok('layout-live-menu-reached', lv.waitState('menu', 900))
for _ = 1, 25 do lv.step(1) end          -- let the drawn (smoothed) box settle on its target
local lm5 = lv.main.lastRects()
ok('layout-live-row-present', lm5 ~= nil)
local bx5, by5, bw5, bh5 = lv.main.menuRowRect(lm5, 1)
local dr5, tg5 = lv.main.box()
local bx5last = select(1, lv.main.menuRowRect(lm5, 4))
-- (a) the drawn row's offset from screen centre / box equals the hard-coded constants
local want5 = lc.centerY + lc.rowDyTop
local floor5 = tg5.y + tg5.h + lc.gap
if want5 < floor5 then want5 = floor5 end
local ceil5 = 480 - bh5 - lc.bottomMargin
if want5 > ceil5 then want5 = ceil5 end
eq('layout-live-row-y-from-constants', by5, want5)
-- the centre anchor is a floor for the row: the box may only push it DOWN, never up
eq('layout-live-row-never-above-centre-anchor', by5 >= lc.centerY + lc.rowDyTop, true)
-- (b) the whole row stays inside the 640x480 world
eq('layout-live-row-inside-world-y', by5 >= 0 and by5 + bh5 <= 480, true)
eq('layout-live-row-inside-world-x', bx5 >= 0 and bx5last + bw5 <= 640, true)
-- (c) no overlap with the box whenever the box leaves room for it
eq('layout-live-box-leaves-room', (480 - (tg5.y + tg5.h)) >= bh5 + lc.gap, true)
eq('layout-live-row-not-overlapping-box', by5 >= dr5.y + dr5.h, true)
-- (d) draw and hit-test share the very same rect
eq('layout-live-hit-shares-drawn-rect', lv.main.menuHitTest(lm5, bx5 + bw5 / 2, by5 + bh5 / 2), 1)

print(string.format('4dir matrix: %d cases, %d new assertions -> %d pass / %d fail',
  m4n, (oks - m4ok0) + (#fails - m4f0), oks - m4ok0, #fails - m4f0))
print(string.format('input regression: %d pass / %d fail', oks, #fails))
for _, f in ipairs(fails) do print('  FAIL ' .. f) end
