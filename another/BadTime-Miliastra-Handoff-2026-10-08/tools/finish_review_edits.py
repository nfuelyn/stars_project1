"""Guarded structural edits to the recovered monolithic modules."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
def replace_between(s, start, end, new):
    a = s.index(start)
    b = s.index(end, a)
    return s[:a] + new + s[b:]

p = ROOT / 'lua/core.lua'
s = p.read_text(encoding='utf-8')
# Attack scripts end on their own EndAttack; dry-running them at each transition
# creates a noticeable client hitch and is no longer needed as a timeout oracle.
s = replace_between(s, '    local need = self.world:scriptLength()', '\n  end\n\n  -- 【第三轮 N8】',
                    '    -- 有脚本时以 EndAttack 为准；enemyDur 只供无脚本的练习生成器使用。\n')
# World:update already advances these objects. This second loop doubled their age.
s = replace_between(s, '  -- 冲击波（内置模式）\n', '  -- 碰撞（world 实体', '')
# A jump may clear a slam only after a legitimate solid-ground jump is accepted.
s = s.replace('  self:endSlam()      -- 起跳即脱离甩击，并把重力方向还原（含 world 侧）\n', '')
s = s.replace("  if onSolid or coyote then\n    self:emit('jump')", "  if onSolid or coyote then\n    self:endSlam()\n    self:emit('jump')")
s = s.replace("text = ((g.resultIndex or 1) == 0) and '确认键：结算并退出奇域' or '确认键：重新开始',",
"text = g.settleStatus == 'sent' and '已请求结算，等待服务器结束关卡'\n                   or (g.settleStatus == 'failed' and '结算发送失败：选择结算可重试')\n                   or (((g.resultIndex or 1) == 0) and '确认键：请求结算' or '确认键：重新开始'),")
p.write_text(s, encoding='utf-8')

p = ROOT / 'lua/main.lua'
s = p.read_text(encoding='utf-8')
s = replace_between(s, '  -- 战斗框平滑过渡：', '  -- 标题页提示行',
'''  -- 脚本核心已经逐帧插值战斗框；再平滑一次会让显示边界落后于碰撞边界。
  if boxTarget then
    curBox.x, curBox.y, curBox.w, curBox.h = boxTarget.x, boxTarget.y, boxTarget.w, boxTarget.h
  end
''')
s = replace_between(s, 'local function bindKeys()\n', 'local function consumeEdges()\n',
'''local function bindKeys()
  local dirs = {
    up = { 'KeyboardMoveForwardKey', 'KeyboardCraftspersonKey36', 'ControllerCharacterSkill3Key' },
    down = { 'KeyboardMoveBackwardKey', 'KeyboardCraftspersonKey37', 'ControllerCraftspersonKey2' },
    left = { 'KeyboardMoveLeftKey', 'KeyboardCraftspersonKey38', 'ControllerCraftspersonKey1' },
    right = { 'KeyboardMoveRightKey', 'KeyboardCraftspersonKey39', 'ControllerCharacterSkill4Key' },
  }
  for dir, names in pairs(dirs) do
    local d = dir
    heldDirections[d] = {}
    for _, name in ipairs(names) do
      local n = name
      local function change(value)
        heldDirections[d][n] = value
        local active = false
        for _, v in pairs(heldDirections[d]) do if v then active = true end end
        setDir(d, active)
      end
      bind(n .. 'Down', function() change(true) end)
      bind(n .. 'Up', function() change(false) end)
    end
  end
  local function bindAction(names, held, confirm)
    for _, name in ipairs(names) do
      local n = name
      local function change(value)
        local before = false
        for _, v in pairs(held) do if v then before = true end end
        held[n] = value
        local active = false
        for _, v in pairs(held) do if v then active = true end end
        if confirm then
          if active and not before then edgeConfirm = true end
          confirmHeld = active
        else
          if active and not before then edgeCancel = true end
          cancelHeld = active
        end
      end
      bind(n .. 'Down', function() change(true) end)
      bind(n .. 'Up', function() change(false) end)
    end
  end
  bindAction({ 'KeyboardCraftspersonKey12', 'KeyboardCraftspersonKey19',
    'KeyboardJumpKey', 'ControllerJumpKey', 'ControllerMenuConfirmKey',
    'KeyboardMenuConfirmKey' }, heldConfirm, true)
  bindAction({ 'KeyboardDropKey', 'KeyboardCraftspersonKey42',
    'ControllerNormalAttackKey', 'ControllerMenuBackKey',
    'KeyboardMenuBackKey' }, heldCancel, false)
end

''')
for event in ('CursorDown', 'CursorDrag', 'CursorUp', 'CursorClick'):
    s = s.replace(f"AddCursorEventListener('{event}',", f"AddCursorEventListener(enumValue('CursorEventType', '{event}') or '{event}',")
# CursorUp is emitted on release before CursorClick. Its existing tapPending
# gate prevents dispatching the same menu action twice.
s = replace_between(s, 'local function requestSettlement()\n', '\nfunction M.OnLevelUpdate(dt)\n',
'''local function requestSettlement(dt)
  if not (state and state.settleRequested) then return end
  state.settleRetryT = math.max(0, (state.settleRetryT or 0) - dt)
  if state.settleRetryT > 0 then return end
  local cfg = config.settlement or {}
  state.settleAttempts = (state.settleAttempts or 0) + 1
  local ok, err = pcall(function()
    local sig = game.ServerSignal(cfg.signal or 'SansFightSettle')
    -- 官方 API 按参数次序传值，不能把字段名当作第一个实参。
    sig:AddString(tostring(state.result or 'fail'))
    sig:AddInt(math.floor(state.hp or 0))
    sig:AddInt(math.floor(state.kr or 0))
    sig:AddInt(math.floor(state.fightCount or 0))
    sig:AddFloat(state.elapsed or 0)
    sig:AddInt(math.floor(state.hits or 0))
    sig:AddString(tostring(state.diffKey or 'original'))
    sig:SendSignal()
  end)
  if ok then
    state.settleRequested, state.settleStatus = false, 'sent'
    if music then music.stop() end
    print('main: 已发送 SansFightSettle，等待服务器结算（本地发送成功不代表服务器已结算）')
  elseif state.settleAttempts >= (cfg.maxAttempts or 3) then
    state.settleRequested, state.settleStatus = false, 'failed'
    print('main: 结算发送失败，可再次选择结算 :: ' .. tostring(err))
  else
    state.settleRetryT = cfg.retryDelay or 1
  end
end
''')
s = s.replace('function M.OnLevelUpdate(dt)\n  frame = frame + 1',
'''function M.OnLevelUpdate(dt, fromUI)
  if not started or not enabled then return end
  if config.updateCallback == 'ui' and not fromUI then return end
  if type(dt) ~= 'number' or dt ~= dt or dt < 0 or dt == math.huge then dt = 0 end
  dt = math.min(dt, 0.25)
  layout()
  if bgPanel then put(bgPanel, 0, 0, CW, CH) end
  if bakedRoot then put(bakedRoot, 0, 0, CW, CH) end
  frame = frame + 1''')
s = s.replace('input.confirm, input.cancel = c, x', 'input.confirm, input.cancel = c, (cancelHeld or x)')
s = replace_between(s, '    -- 蓝魂回合（R6 / 最终回合第一段', '    local ok, out = pcall(function() return core.update',
'''    -- 跳跃按下沿统一由核心消费；按住状态独立传入用于变高跳。
    local coreInput = { left = input.left, right = input.right, up = input.up, down = input.down,
      confirm = input.confirm, cancel = input.cancel, jumpHeld = confirmHeld }
''')
s = s.replace('    requestSettlement()','    requestSettlement(dt)')
s = s.replace('    if music then music.update(dt) end',
'''    if music then
      if state.state == 'result' or state.interlude then music.stop()
      elseif state.state ~= 'title' then
        if not music.playing then music.start() end
        music.update(dt)
      end
      for _, event in ipairs(state.audioEvents or {}) do music.effect(event) end
    end
    state.audioEvents = {}
    if state.world then state.world.audioEvents = state.audioEvents end
    if not ok and not M.updateErrorLogged then
      M.updateErrorLogged = true
      print('main: core.update ERR :: ' .. tostring(out))
    end''')
# Touch users also get the documented physical controller bindings.
s = s.replace("    bindKeys()\n    print('main: 平台 = PC", "    print('main: 平台 = PC")
s = s.replace('  bindPointer()\n', '  bindKeys()\n  bindPointer()\n')
# Remove listeners by exact callback reference, and destroy only owned instances.
idx = s.index('-- 测试钩子：无头测试台')
s = s[:idx] + '''local function clearInput()
  input = { left = false, right = false, up = false, down = false, confirm = false, cancel = false }
  heldConfirm, heldCancel, heldDirections = {}, {}, {}
  for _, d in ipairs({ 'left', 'right', 'up', 'down' }) do heldDirections[d] = {} end
  edgeConfirm, edgeCancel, confirmHeld, cancelHeld = false, false, false, false
  joy.active, ptr.down, ptr.wasJoy = false, false, false
  clearPending()
  if state then state.keys, state.prevKeys = {}, {} end
end

function M.OnDisable()
  enabled = false
  clearInput()
  if music then music.stop(); music.stopEffects() end
end

function M.OnEnable()
  enabled = true
  if started then clearInput() end
end

function M.OnDestroy()
  M.OnDisable()
  if root then
    for _, listener in ipairs(keyListeners) do
      pcall(function() root:RemoveKeyEventListener(listener[1], listener[2]) end)
    end
  end
  if cursorArea then pcall(function() cursorArea:RemoveAllCursorEventListeners() end) end
  for i = #ownedControls, 1, -1 do
    local c = ownedControls[i]
    pcall(function() if c.alive ~= false then game.DestroyClientUIControl(c) end end)
  end
  ownedControls, keyListeners, pool, memo, baked = {}, {}, {}, {}, {}
  state, started = nil, false
end

''' + s[idx:]
p.write_text(s, encoding='utf-8')
print('Structural edits applied')
