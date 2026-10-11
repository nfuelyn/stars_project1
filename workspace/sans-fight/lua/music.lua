-- ============================================================================
-- music.lua —— 战斗 BGM：用千星「音效」逐音符拟合播放（客户端侧，无需服务端节点图）
-- ----------------------------------------------------------------------------
-- 数据来源：music1.mp3 自动扒谱 v1
--   速度 156.25 BPM（4/4），八分音符网格 STEP = 0.192s，共 743 格 ≈ 142.66s，整场循环
--   原曲时长 158.57s —— 本谱只覆盖前 142.66s（约 90%），末尾收尾段没扒；要整首得补谱
-- 版权：本文件只有「音符时间轴 + 平台音效 ID」，不含任何原曲录音；音效全部来自千星音效库。
-- ----------------------------------------------------------------------------
-- 宿主接法（lua/main.lua）：
--   music:start()     开战 / 重开战斗 → 从头播
--   music:update(dt)  每帧推进（OnLevelUpdate 里调）
--   music:stop()      结算 / 退出奇域 → 停
-- ============================================================================

local M = {}

-- ----------------------------------------------------------------------------
-- ① 音效绑定 —— ★ 唯一需要你手工填的地方
--    把千星编辑器「音效库」里的音频资源 ID 填到下面（0 = 未绑定）。
--    查找顺序：精确音名 → 同音级其它八度 → 音级兜底 → M.FALLBACK
--    ① 只填 12 个音级（M.SFX_PC）就能让整条旋律出声，只是跨八度会变成同一个音高
--    ② 想更像原曲再逐个补 M.SFX 里的精确音名
--    没绑定的音会被跳过：不报错、不卡住，只是那一下听不见。
-- ----------------------------------------------------------------------------
M.SFX = {
  ['C5'] = 0, ['C6'] = 0, ['C#4'] = 0, ['C#5'] = 0, ['C#6'] = 0, ['D4'] = 0,
  ['D5'] = 0, ['D6'] = 0, ['D#4'] = 0, ['D#5'] = 0, ['D#6'] = 0, ['E5'] = 0,
  ['E6'] = 0, ['F4'] = 0, ['F5'] = 0, ['F#3'] = 0, ['F#4'] = 0, ['F#5'] = 0,
  ['G3'] = 0, ['G4'] = 0, ['G5'] = 0, ['G#3'] = 0, ['G#4'] = 0, ['G#5'] = 0,
  ['A3'] = 0, ['A4'] = 0, ['A5'] = 0, ['A#3'] = 0, ['A#4'] = 0, ['A#5'] = 0,
  ['B3'] = 0, ['B4'] = 0, ['B5'] = 0,
}
M.SFX_PC = {
  ['C'] = 0, ['C#'] = 0, ['D'] = 0, ['D#'] = 0, ['E'] = 0, ['F'] = 0,
  ['F#'] = 0, ['G'] = 0, ['G#'] = 0, ['A'] = 0, ['A#'] = 0, ['B'] = 0,
}
M.FALLBACK = 0

-- ----------------------------------------------------------------------------
-- ② 音符时间轴（自动扒谱 v1，勿手改；换谱只改这一段 + STEP）
--    记号：音名（C4 = 中央 C）；'-' = 休止（v1 里没有休止）
-- ----------------------------------------------------------------------------
M.STEP = 0.192        -- 八分音符间隔（156.25 BPM）
M.RETRIG = 4          -- 同一个音连续超过 4 格（≈0.77s）就重触发一次，避免糊成一条长音

M.SCORE = [[
  B5 D#6 D#6 A4 A4 E5 E5 D#5 D#5 F5 F5 F5 C5 A5 E5 A5 E5 C#6 F5 F5
  F5 F5 F5 A5 E5 E5 D#5 D#5 F5 F5 F5 D#6 D#6 A5 E5 E5 E5 F5 F5 F5
  F5 A5 E5 A5 E5 A#5 F5 F5 F5 F5 F5 A5 E5 E5 D#5 D#5 F5 F5 F5 C5
  A5 E5 E5 D#5 D#5 F5 F5 F5 F5 F5 D#6 A5 E5 E5 F5 F5 F5 F5 F5 F5
  D6 A5 A5 G#5 G#5 F5 F5 F5 E6 A5 A5 A5 G#5 G#5 F5 F5 F5 F5 D6 A5
  A5 G#5 G#5 G#5 F5 F5 F5 F5 D6 A5 A5 G#5 G#5 F5 F5 F5 F5 F5 D6 A5
  G#5 G#5 G#5 F5 F5 F5 E6 D6 A5 A5 G#5 G#5 F5 F5 F5 D6 A5 A5 A5 A5
  F5 F5 F5 F5 F5 F5 A#5 A5 G#5 G#5 E6 F5 F5 F5 F5 F5 F5 F5 F5 F5
  D5 D5 D5 F5 F5 F5 G5 G#5 G#5 G#5 G5 F5 F5 F5 F5 G5 G#5 A5 C6 A5
  A5 A5 D6 D6 D6 D6 C6 C6 C6 C6 C6 C6 F5 F5 F5 F5 G5 F5 D5 D5
  D5 F5 A5 A5 G5 G5 F5 F5 A5 A5 A5 A5 E5 E5 F5 G5 G5 G5 F5 A#4
  A#4 D5 F5 F5 E5 E5 C6 C6 C6 E5 C6 F5 F5 F5 F5 F5 G#5 G#5 F5 F5
  G5 G5 E6 E6 E6 G#5 G#5 A5 A5 A5 G#5 F5 F5 F5 E6 C6 C#6 C6 G#5 G#5
  G#5 G5 G5 G5 F5 F5 F5 F5 F5 F5 F5 E6 E6 E6 E6 E5 E6 E6 F5 F5
  C6 G5 C6 E6 E6 A5 A5 A5 A5 A5 G#5 G#5 F#5 D#5 C#5 C#5 C#5 C#5 D#5 D#5
  D#5 D#5 D#5 F5 F5 F5 F5 F5 F5 F5 F5 F5 F5 F5 F5 F5 E6 E6 E6 E6
  E6 A5 A5 A5 A5 G#5 F5 F5 F5 E6 C6 C#6 C6 G#5 G#5 G#5 G5 G5 G5 F5
  F5 F5 F5 F5 F5 F5 E6 E6 E6 E6 E5 E6 E6 F5 F5 G5 G5 G5 E6 E6
  E6 A5 A5 A5 A5 G#5 G#5 F#5 D#5 C#5 C#5 C#5 C#5 C#5 D#5 D#5 D#5 D#5 D#5 D#5
  D#5 A#4 A#4 A#4 A#3 A#3 F4 C5 C5 B4 B4 B4 B4 B4 A4 A4 A4 A4 C#5 F5
  F5 C5 C5 C5 C5 C5 C5 C5 C5 C5 C5 F5 F5 C5 F#4 F#4 F#4 A#5 A#5 A#5
  A#4 A#4 A#3 A#3 C5 C5 B4 B4 B4 B4 B4 B4 A4 A4 A4 A4 A4 A4 A3 A3
  G#4 G#4 G#4 F#3 F#3 D#4 D#4 C#4 C#4 G#3 F#3 F#3 A3 D4 D4 D#4 A#4 A#4 D#5 F5
  F5 F5 C5 C5 B4 B4 B4 B4 B4 A4 A4 A4 A4 G4 B5 C5 F5 C5 F5 C5
  F5 C5 C5 C5 C5 E6 E6 E6 C5 C5 C5 D5 D#4 D5 D#5 A#5 D#5 E6 F5 F5
  F5 B4 B4 B4 B4 B4 B4 A4 F5 A4 F5 A4 A4 G#4 A3 G#4 E6 E6 G5 G5
  F5 F5 E6 E6 E6 D6 E6 F5 F5 F5 E6 E6 F5 F5 F5 F5 A#5 A#5 A#5 D#6
  F#5 G3 G3 D#6 D#6 C#6 C#6 B5 F5 F5 F5 F5 F5 B3 G#3 B3 D#6 D#6 D#6 D#6
  F5 E6 E6 E6 B3 E6 F5 F5 F5 F5 F5 F5 E6 D#6 D#6 A#5 A#5 F5 F5 F5
  D#6 D#6 D#6 D#6 F5 D#6 E6 C#6 F#5 F#5 F#5 F#5 F#3 F#3 A3 E6 E6 E6 F#5 F#5
  F#5 F#3 F#3 A3 C#6 C#6 F#5 F#5 F#5 F5 C#6 E6 D#6 D#6 D#6 D#6 D#6 D#6 B5 B5
  D#6 D#6 D#6 C#6 A3 A3 A3 F5 F5 A#5 A#5 A#5 F#5 F#5 G#5 G#5 F#4 B3 F#4 B5
  E6 E6 C#6 F#5 F#5 F5 F5 F5 F5 C#6 F5 C6 D#6 F#5 A#4 A#4 F5 F5 F5 F#5
  F#5 E5 D#4 D#5 D#5 F5 F5 F5 F5 F5 F5 C#6 C#6 C#6 F5 F5 F5 F5 F5 D#6
  A5 E5 D#5 D#5 F5 F5 F5 C5 A5 E5 A5 E5 C#6 F5 F5 F5 F5 F5 A5 E5
  E5 D#5 D#5 F5 F5 F5 C5 A5 E5 E5 E5 E5 F5 F5 F5 F5 D#6 A5 E5 E5
  E5 B5 F5 F5 F5 G4 G4 E5 E5 D#5 D#5 F5 F5 F5 C5 G4 G4 G4 G4 G4
  G4 B5 D#6
]]

-- ----------------------------------------------------------------------------
-- ③ 播放逻辑
-- ----------------------------------------------------------------------------
local tokens = nil
local function score()
  if not tokens then
    tokens = {}
    for s in string.gmatch(M.SCORE, '%S+') do tokens[#tokens + 1] = s end
  end
  return tokens
end

local function hasSink()
  return (type(game) == 'table') and (type(game.PlayAudio2D) == 'function')
end

local function pitchClass(name)
  local i = 1
  while i <= #name and not name:find('%d', i) do i = i + 1 end
  return name:sub(1, i - 1)
end

local idCache = {}
local function idOf(name)
  local v = idCache[name]
  if v ~= nil then return v end
  v = M.SFX[name]
  if (v == nil or v == 0) and M.SFX_PC then
    -- 同音级其它八度（先降八度再升八度，够用即可）
    local pc = pitchClass(name)
    local oct = tonumber(name:sub(#pc + 1)) or 4
    for _, o in ipairs({ oct - 1, oct + 1, oct - 2, oct + 2 }) do
      local alt = pc .. tostring(o)
      local a = M.SFX[alt]
      if a and a ~= 0 then v = a; break end
    end
    if v == nil or v == 0 then v = M.SFX_PC[pc] end
  end
  if v == nil or v == 0 then v = M.FALLBACK end
  if v == nil then v = 0 end
  idCache[name] = v
  return v
end

local function stopVoice()
  if not M.voice then return end
  local h = M.voice
  M.voice = nil
  if hasSink() then pcall(function() game.StopAudio(h) end) end
end

local function fire(name)
  stopVoice()
  local id = idOf(name)
  if id == 0 or not hasSink() then return end
  local ok, h = pcall(function() return game.PlayAudio2D(id) end)
  if ok then M.voice = h end
end

M.playing = false
M.i, M.t = 1, 0
M.voice = nil
M.lastName, M.lastIndex = nil, 0
M.starts, M.triggers, M.dropped = 0, 0, 0

local function boundCount()
  local c = 0
  for _, v in pairs(M.SFX) do if v and v ~= 0 then c = c + 1 end end
  for _, v in pairs(M.SFX_PC) do if v and v ~= 0 then c = c + 1 end end
  if M.FALLBACK and M.FALLBACK ~= 0 then c = c + 1 end
  return c
end

function M.start()
  stopVoice()
  M.playing = true
  M.i, M.t = 1, 0
  M.lastName, M.lastIndex = nil, 0
  M.starts = M.starts + 1
  print(string.format('music: start #%d (score=%d 格 %.2fs, 音效绑定 %d 项)',
    M.starts, #score(), #score() * M.STEP, boundCount()))
end

function M.stop()
  M.playing = false
  M.i, M.t = 1, 0
  M.lastName, M.lastIndex = nil, 0
  stopVoice()
end

function M.update(dt)
  if not M.playing then return end
  local tk = score()
  local n = #tk
  if n == 0 then M.playing = false return end
  M.t = M.t + (dt or 0)
  local guard = 0
  while M.playing and guard < 256 do
    guard = guard + 1
    local due = (M.i - 1) * M.STEP
    if M.t < due then break end
    local name = tk[M.i]
    if name == '-' then
      if M.voice then stopVoice() end
      M.lastName = nil
    elseif name ~= M.lastName or (M.i - M.lastIndex) >= M.RETRIG then
      if idOf(name) == 0 then M.dropped = M.dropped + 1 end
      fire(name)
      M.triggers = M.triggers + 1
      M.lastName, M.lastIndex = name, M.i
    end
    M.i = M.i + 1
    if M.i > n then
      M.i = 1
      M.t = M.t - n * M.STEP      -- 整场循环：相位不跳，接缝不断拍
      M.lastName = nil
    end
  end
end

function M.reset() M.start() end            -- 语义别名
function M.info() return M.i, M.t, M.playing, M.triggers end

return M
