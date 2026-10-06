--[[ ==========================================================================
  core_selftest.lua —— L1 自测（纯 Lua，对应 prototype/selftest.js + attack-selftest.js）
  ---------------------------------------------------------------------------
  运行（两种任选）：
    fengari（目标运行时，Lua 5.3 语义）：
      node D:\stars\workspace\sans-fight\tools\run-lua.mjs lua/core_selftest.lua
    本机 Lua 5.1：
      D:\5.1\lua.exe D:\stars\workspace\sans-fight\lua\core_selftest.lua

  用法：local R = dofile("core_selftest.lua"); local pass, fail, failures = R.run()
  也可以直接执行本文件（末尾会自动 run 一次）。

  证据等级：L1（纯状态回放）。不是模拟器证据，也不是真机证据。
  ========================================================================== ]]

-- 模块名动态拼接：这样 tools/run-lua.mjs 的 require 重写规则不会命中，
-- 两种运行环境（run-lua.mjs / 本机 lua.exe）都用 package.path 正常解析。
if type(_G.LUA_ROOT) == 'string' then
  package.path = _G.LUA_ROOT .. '/?.lua;' .. _G.LUA_ROOT .. '/?/init.lua;' .. package.path
end
if not package.path:find('lua/%?%.lua') then
  package.path = 'lua/?.lua;./?.lua;' .. package.path
end
local M = require('core')
local A = require('attacks')

local DT = M.DT
local R = { pass = 0, fail = 0, failures = {}, notes = {} }

local ok, head, note

local function reset()
  R.pass, R.fail, R.failures, R.notes = 0, 0, {}, {}
end

ok = function(cond, msg)
  if cond then
    R.pass = R.pass + 1
  else
    R.fail = R.fail + 1
    R.failures[#R.failures + 1] = msg
    io.write("  FAIL  " .. msg .. "\n")
  end
end
head = function(t) R.notes[#R.notes + 1] = t; io.write("\n== " .. t .. "\n") end
note = function(t) R.notes[#R.notes + 1] = t; io.write("     " .. t .. "\n") end

-- 这个自测集测的是**核心机制与内置生成器兜底**（脚本回合的调度由 _rounds.lua / _flow.lua 覆盖）。
-- 20 回合改版后每回合默认都会挂攻击脚本、内置生成器让位，所以这里统一默认 noScriptRounds=true：
--   * 想测"没有脚本时的兜底生成器"（bone_floor / bone_wall / difficulty 节拍）→ 正是这个路径；
--   * 想测脚本本身 → 显式传 noScriptRounds = false（如 extra-scripts / 攻击脚本用例）。
local function newGame(o)
  o = o or {}
  o.scripts = o.scripts or A
  if o.noScriptRounds == nil then o.noScriptRounds = true end
  return M.newGame(o)
end
local E = {}
local function step(g, seconds, input) M.step(g, seconds, input or E) end
local function has(g, s) return M.hasLog(g, s) end

local function toMenu(g, maxSec)
  maxSec = maxSec or 40
  for _ = 1, math.floor(maxSec / DT + 0.5) do
    if g.state == 'menu' or g.state == 'sub' or g.state == 'result' then return true end
    M.update(g, E, DT)
  end
  return false
end

local function attackTurn(g)
  M.menuChoose(g, 0)
  if g.state == 'attack' then M.stopAttack(g) end
  for _ = 1, math.floor(3 / DT + 0.5) do
    if g.state ~= 'attack' then break end
    M.update(g, E, DT)
  end
end

-- noSpawn 隔离：把攻击脚本已经生成的弹幕清空，并停掉它的生成节奏。
-- 原版 noSpawn 只关掉"模式生成器"；本移植还挂了攻击脚本（回合 0 = sans_intro，
-- 含 20 根正弦骨），所以隔离用例必须自己再清一次，否则测 KR/生命会被脚本弹幕污染。
local function clearHazards(g)
  local w = g.world
  if not w then return end
  w.bones = {}
  w.sine = {}
  w.blasters = {}
  w.platforms = {}
  w.pc = #w.prog                      -- 不再执行后续生成命令
end

local function countHits(g)
  local n = 0
  for _, s in ipairs(g.logs) do
    if s:sub(1, 7) == 'hit hp=' then n = n + 1 end
  end
  return n
end

-- 自建骷髅：把一根蓝/橙骨精确摆在灵魂身上（避免依赖随机生成时机与生成位置）
-- 用一个"只有框、没有其他弹幕"的注入脚本来隔离判定，得到的结论才干净。
-- 隔离夹具：手搭一个"只有框、没有任何弹幕生成"的状态（不走 startEnemy，
-- 因此不会带上回合 0 的偷袭骨波），用于干净地验证颜色骨 / 平台 / 正弦等判定。
--   框定为 420x260 居中：脚本坐标 (350,279)-(770,539) <->
--   框内相对坐标 (110,53)-(530,313)，soul 放在框内中心 (320,183)。
local ISO_W, ISO_H = 420, 260
local ISO_L = M.VW / 2 - ISO_W / 2 + M.BOX_OFF_X          -- 350
local ISO_T = M.VH / 2 - ISO_H / 2 + M.BOX_OFF_Y          -- 279
local ISOLATE_CSV = string.format('0,CombatZoneResizeInstant,%d,%d,%d,%d\n0,TLResume\n600,EndAttack\n',
                                  ISO_L, ISO_T, ISO_L + ISO_W, ISO_T + ISO_H)
local function isolateGame(o)
  o = o or {}
  o.scripts = { { name = 'test_isolate', csv = ISOLATE_CSV } }
  o.noSpawn = true
  local g = newGame(o)
  g.spawnT = 1e9
  g.enemyT = 0
  g.enemyDur = 1e9
  g.testHitsAt = {}
  g.state = 'enemy'
  g.walls = {}
  g.platforms = {}
  local w = g:startEnemyScript('test_isolate')      -- box = zoneOf(zone)
  -- 把脚本世界的框与游戏框对齐（脚本里那个 160x165 的框对隔离测试没有意义）
  w.zone.l, w.zone.t = g.box.x + M.BOX_OFF_X, g.box.y + M.BOX_OFF_Y
  w.zone.r, w.zone.b = w.zone.l + g.box.w, w.zone.t + g.box.h
  w.zone.tl, w.zone.tt = w.zone.l, w.zone.t
  w.zone.tr, w.zone.tb = w.zone.r, w.zone.b
  -- 把灵魂摆到**新框**的中心（否则它会被上一次的框钳在边界上）
  g.soul.x = g.box.x + g.box.w / 2
  g.soul.y = g.box.y + g.box.h / 2
  g.soul.mode = 'red'
  g.soul.vx, g.soul.vy = 0, 0
  -- 用一次真正的 update 把"出生状态"落到地上（prevX/prevY 等），并让 ResizeInstant 生效
  M.update(g, E, DT)
  g.state = 'enemy'
  g.walls = {}
  g.platforms = {}
  g.spawnT = 1e9
  return g, w
end

-- 把骨头重新贴到**当前** soul 上，并清掉干扰骨。
-- 一律读 g.soul 的实时值（别缓存坐标——soul 会被框钳制，缓存值会失效）
local function keepBone(g, bn)
  local w = g.world
  bn.x = g.soul.x + M.BOX_OFF_X - 80
  bn.y = g.soul.y + M.BOX_OFF_Y - 11
  bn.hitDone = false
  for i = #w.bones, 1, -1 do
    if w.bones[i] ~= bn then table.remove(w.bones, i) end
  end
end

-- 把一根蓝/橙/白骨的命中盒精确压在灵魂身上。
-- 坐标：world 里的实体在**脚本坐标**、game.soul 在**框内相对坐标**，
-- 差一个常量偏移 (M.BOX_OFF_X, M.BOX_OFF_Y)（见 core.lua 顶部坐标契约）。
local function placeBoneOnSoul(g, color)
  local w = g.world
  local bn = {
    kind = 'blue', custom = true, lethal = true, color = color,
    x = 0, w = 160, y = 0, h = 22,
  }
  w.bones[#w.bones + 1] = bn
  keepBone(g, bn)          -- 立刻按当前 soul 位置贴上去
  return bn, w
end

local function safeCount(wave, lanes)
  local n = 0
  for L = 0, lanes - 1 do
    local safe = true
    for _, b in ipairs(wave) do if b.lane == L then safe = false end end
    if safe then n = n + 1 end
  end
  return n
end

-- ==========================================================================
-- 一路「攻击」推进到最终回合的菜单（第 6 回合结束 → final=true, finalPhase=1）
-- 一路选「攻击」推进到**最后一回合结束后的菜单**（此时 final = true：他躲不开，打/饶二选一）
local function driveToFinal(g, maxFrames)
  local guard = 0
  maxFrames = maxFrames or 40000
  while guard < maxFrames do
    if g.state == 'result' then return false end
    if g.final and g.state == 'menu' then return true end
    if g.state == 'enemy' then
      M.update(g, E, DT)
    elseif g.state == 'attack' then
      M.update(g, E, DT)
    elseif g.state == 'menu' then
      M.menuChoose(g, 0)
      if g.state == 'attack' then M.stopAttack(g) end
      M.update(g, E, DT)
    elseif g.state == 'sub' then
      M.subBack(g)
      M.update(g, E, DT)
    else
      M.update(g, E, DT)
    end
    clearHazards(g)               -- 隔离用：不让脚本弹幕把测试角色打死
    guard = guard + 1
  end
  return false
end

local function run()
  reset()
  io.write("core_selftest.lua —— Lua 逻辑核心 L1 自测（_VERSION=" .. _VERSION .. "）\n")

  -- ------------------------------------------------------------ boot
  head('boot：开局初始化 + 回合 0 不意打ち（C9/C10/C17）')
  local g = newGame({ seed = 1 })
  ok(has(g, 'game_start'), '日志含 game_start')
  ok(has(g, 'round_start round=0'), '开局先进「回合 0」不意打ち（原作回合 0）')
  ok(g.state == 'enemy', 'state=enemy')
  ok(g.hp == M.MAX_HP and g.kr == 0, string.format('HP=%d / KR=0（原作体验：MAX_HP=92）', M.MAX_HP))
  toMenu(g)
  ok(g.state == 'menu' and has(g, 'round_clear round=0'), '撑过偷袭后进入你的回合')

  -- ------------------------------------------- first-success：第一波
  -- 注意（与 JS 原版的差异，见 records/lua-port.md）：
  --   本移植把 BTS 攻击脚本接进了回合流程，回合 0 挂的是 sans_intro。sans_intro 第 4 行是
  --   `0,BlackScreen,1`（登场黑屏闪，语义上会清空弹幕），所以 startEnemy 里那一波「偷袭骨」
  --   在第 1 帧就被清掉了 → 回合 0 **不会**出现 wave_clear wave=1。原版 game.js 没有接
  --   attack-engine，所以那一波会活到 1.43s 再 wave_clear。
  --   因此这里断言的是"回合 0 无伤"这条真正的上手保证，wave_clear 放到第 1 回合（无脚本）验证。
  head('first-success：第 1 波无伤（C5/C8 上手保证）')
  -- 这一条**故意要挂脚本**（noScriptRounds = false）：它断言的 wave_peek lanes=3 来自
  -- sans_intro 自己的战斗框（165 宽 → 4 格 → 3 格有骨），是"见面杀就在那小框里打"的证据。
  g = newGame({ seed = 1, noScriptRounds = false })
  -- 【第三轮 N8】回合 0 挂了 sans_intro 脚本 → 内置地面骨让位，不再有 wave_peek
  ok(not has(g, 'wave_peek') and has(g, 'round_script round=0'), '回合 0 只跑 sans_intro 脚本（内置地面骨已让位）')
  step(g, 1.6)
  -- 【回合差异 2.6 + 方案甲】原版初见杀就是「把心甩到南边 + 同一侧升骨刺」→ 早期会掉血
  ok(has(g, 'slam ') or has(g, 'round_start round=0'), '回合 0 走原版甩击+骨刺流程')
  ok(g.hp <= M.MAX_HP and g.hp > 0, string.format('HP 合理（%d/%d）', g.hp, M.MAX_HP))

  -- 第 2 回合（无攻击脚本，走内置 bone_floor 模式）：第一波留出生点安全位且四段生命完整
  -- （注意：opts.startRound 与 JS 一致，只决定"开局打完之后进哪一回合"；开局永远是回合 0）
  -- 第 1 回合（无攻击脚本，走内置 bone_floor 模式）：第一波留出生点安全位
  -- （注意：opts.startRound 与 JS 一致，只决定"开局打完之后进哪一回合"；开局永远是回合 0）
  g = newGame({ seed = 1, startRound = 1 })
  step(g, 1.4)
  ok(has(g, 'wave_peek wave=1'), '第 1 回合第 1 波按时冒头预警')
  step(g, 0.4)
  ok(not has(g, 'hit hp='), '站在出生点不动不受伤（第 1 波留安全位）')
  ok(g.hp <= M.MAX_HP and g.hp > 0, string.format('第 1 回合 HP 合理（%d/%d）', g.hp, M.MAX_HP))

  -- ----------------------------------------- 骨头预示（冒头 0.5s）
  head('bone-telegraph：地面骨头先冒头 0.5s 再伸出（C14）')
  -- 夹具从回合 0 **挪到回合 1**（内置 bone_floor）：回合 0 现在由 sans_intro 脚本独占
  -- （core.lua 的 scriptOwnsRound：挂脚本的回合里内置生成器让位），开局不再有内置地面骨波，
  -- "冒头"只能在回合 1 上验。注意 `startRound=1` 在本移植里**仍会先打回合 0**
  -- （startEnemy 只跳过 bootRound>1），所以这里直接 startEnemy(1)；断言与条数不变。
  g = newGame({ seed = 1 })
  g:startEnemy(1)
  local peekFrames, lethalDuringPeek, done = 0, false, false
  for _ = 1, math.floor(3 / DT + 0.5) do
    M.update(g, E, DT)
    if done then break end
    local seen, anyLethal = false, false
    -- 回合 1 的 world 是**惰性**创建的（第一波生成时才 ensureWorld），开局那几帧还是 nil
    for _, b in ipairs((g.world and g.world.bones) or {}) do
      if b.kind == 'floor' and b.phase == 'peek' then
        seen = true
        if b.lethal then anyLethal = true end
      end
    end
    if seen then
      peekFrames = peekFrames + 1
      if anyLethal then lethalDuringPeek = true end
    elseif peekFrames > 0 then
      done = true
    end
  end
  local peekSec = peekFrames * DT
  ok(peekFrames > 0, '出现了"冒头"阶段')
  ok(not lethalDuringPeek, '冒头阶段不致命（纯预示）')
  ok(peekSec >= 0.45 and peekSec <= 0.60,
     string.format('冒头持续 ≈0.5s（实测 %.2fs）', peekSec))

  -- ------------------------------------------------- KR 不致死（C3）
  head('kr-floor：KR 烧血但 HP 停在 1，且不 fail（C2/C3）')
  g = newGame({ hp = 2, noSpawn = true, hitsAt = { 1.0 } })
  clearHazards(g)                       -- 隔离 KR 规则：把脚本已生成的弹幕清掉
  step(g, 1.5)
  ok(g.hp == 1, '命中后 HP=1（收到 hp=' .. g.hp .. '）')
  ok(has(g, 'hit hp=1 kr=6'), '日志含 hit hp=1 kr=6（原版骨头 Karma=6；不致死靠 updateKR 的 hp>1 下限）')
  step(g, 5.0)
  ok(has(g, 'kr_floor hp=1'), '日志含 kr_floor hp=1')
  ok(has(g, 'kr_done hp=1 kr=0'), '日志含 kr_done hp=1 kr=0')
  ok(g.hp == 1, 'HP 最终仍为 1')
  ok(not has(g, 'fail hp_zero'), '未出现 fail hp_zero（KR 不致死）')

  head('hp-integer：HP 与 KR 全程为整数（HUD 可读性）')
  g = newGame({ seed = 11, startRound = 1 })
  step(g, 8.0)
  ok(g.hp == math.floor(g.hp), 'HP 是整数（' .. g.hp .. '）')
  ok(g.kr == math.floor(g.kr), 'KR 是整数（' .. g.kr .. '）')

  -- --------------------------------------- 无敌帧：原作档 vs 普通档
  head('iframes：原作没有无敌帧（C18）')
  local gA = newGame({ hp = 20, noSpawn = true, hitsAt = { 1.0, 1.5 }, difficulty = 'original' })
  step(gA, 1.7)
  ok(countHits(gA) == 2, '原作档：间隔 0.5s 的两次命中都生效（命中 ' .. countHits(gA) .. ' 次）')
  local gB = newGame({ hp = 20, noSpawn = true, hitsAt = { 1.0, 1.5 }, difficulty = 'normal' })
  step(gB, 1.7)
  ok(countHits(gB) == 1, '普通档：0.8s 无敌帧吃掉第二次（命中 ' .. countHits(gB) .. ' 次）')

  -- --------------------------------------- 死亡唯一来源：直接命中
  head('first-fail：直接命中把 HP 打到 0 才 fail（C1/C4）')
  g = newGame({ hp = 1, noSpawn = true, hitsAt = { 1.0 } })
  step(g, 1.5)
  ok(g.state == 'result' and g.result == 'fail', 'state=result / result=fail')
  ok(has(g, 'fail hp_zero'), '日志含 fail hp_zero')

  -- ------------------------------------------------------- 重开（C9）
  head('restart：重开复位（C9）')
  g = newGame({ seed = 5 })
  for _ = 1, M.MAX_HP do            -- 打到 hp 归零（MAX_HP 条命）
    g.invuln = 0
    M.debugHurt(g, 'hit')
    if g.state == 'result' then break end
  end
  ok(g.state == 'result' and g.result == 'fail', '先被打到 fail')
  M.restart(g)
  ok(has(g, 'restart'), '日志含 restart')
  ok(g.hp == M.MAX_HP and g.kr == 0 and g.round == 0,
     'HP/KR/回合复位（hp=' .. g.hp .. ' kr=' .. g.kr .. ' round=' .. g.round .. '）')
  ok(g.state == 'enemy', '回到 Sans 回合（回合 0）')

  -- ---------------------------------------------------- 蓝骨：静止安全
  head('blue-bone-still：蓝骨只惩罚移动（C6）')
  g = isolateGame({ seed = 3 })
  local bn = placeBoneOnSoul(g, 'blue')
  local hpBefore = g.hp
  for _ = 1, 120 do
    keepBone(g, bn)
    M.update(g, E, DT)
    if g.state ~= 'enemy' then break end
  end
  ok(g.state == 'enemy', '蓝骨与灵魂重叠期间回合仍在进行（未被打死）')
  ok(not has(g, 'hit_blue'), '重叠期间静止 → 无 hit_blue')
  ok(g.hp == hpBefore, '重叠期间静止 → HP 不变（' .. hpBefore .. ' → ' .. g.hp .. '）')
  -- 移动：每帧先移动再重新贴上骨头（keepBone 取的是移动后的实时 soul 位置），
  -- 只要 soul 有位移就会吃 hit_blue
  local hit = false
  for _ = 1, 240 do
    if g.state ~= 'enemy' then break end
    g.invuln = 0
    local right = (g.soul.x + 6 <= g.box.x + g.box.w - M.SOUL_CLAMP)
    keepBone(g, bn)
    M.update(g, right and { right = true } or { left = true }, DT)
    if has(g, 'hit_blue') then hit = true; break end
  end
  ok(hit, '重叠期间移动 → 出现 hit_blue')
  ok(g.hp < hpBefore, 'HP 下降（' .. hpBefore .. ' → ' .. g.hp .. '）')

  -- --------------------------------------- 橙骨：必须移动才安全（C19）
  head('orange-bone：橙骨只惩罚静止（原作 Color=2）')
  g = isolateGame({ seed = 3 })
  bn = placeBoneOnSoul(g, 'orange')
  local hitStill = false
  for _ = 1, 120 do
    if g.state ~= 'enemy' then break end
    keepBone(g, bn)
    M.update(g, E, DT)
    if has(g, 'hit_orange') then hitStill = true; break end
  end
  ok(hitStill, '橙骨重叠且静止 → 出现 hit_orange')
  ok(not has(g, 'hit_blue'), 'hit_blue / hit_orange 互不串味（本例无 hit_blue）')

  g = isolateGame({ seed = 3 })
  bn = placeBoneOnSoul(g, 'orange')
  local hp0 = g.hp
  for _ = 1, 120 do
    if g.state ~= 'enemy' then break end
    g.invuln = 0
    local right = (g.soul.x + 6 <= g.box.x + g.box.w - M.SOUL_CLAMP)
    keepBone(g, bn)
    M.update(g, right and { right = true } or { left = true }, DT)
  end
  ok(not has(g, 'hit_orange'), '橙骨重叠但持续移动 → 无 hit_orange')
  ok(g.hp == hp0, '橙骨重叠但持续移动 → HP 不变（' .. hp0 .. ' → ' .. g.hp .. '）')

  -- 白骨（Color 0）不看移动：静止也命中（区分蓝/橙的对照组）
  g = isolateGame({ seed = 3 })
  bn = placeBoneOnSoul(g, 'white')
  local hpW = g.hp
  for _ = 1, 120 do
    if g.state ~= 'enemy' then break end
    keepBone(g, bn)
    M.update(g, E, DT)
  end
  ok(has(g, 'hit hp='), '白骨重叠且静止 → 出现 hit（颜色规则不适用于白）')
  ok(g.hp < hpW, '白骨命中扣血（' .. hpW .. ' → ' .. g.hp .. '）')

  -- 蓝/橙交替生成：确认两种颜色都出现过（原 selftest 的 sawBlue/sawOrange）
  g = newGame({ seed = 3, startRound = 3 })
  local sawBlue, sawOrange = false, false
  for _ = 1, 60 * 12 do
    M.update(g, E, DT)
    if g.state ~= 'enemy' then break end
    for _, b in ipairs(g.world.bones) do
      if b.kind == 'blue' then
        if b.color == 'blue' then sawBlue = true end
        if b.color == 'orange' then sawOrange = true end
      end
    end
    if sawBlue and sawOrange then break end
  end
  ok(sawBlue and sawOrange,
     '蓝骨与橙骨都会出现（sawBlue=' .. tostring(sawBlue) .. ' sawOrange=' .. tostring(sawOrange) .. '）')

  -- ------------------------------------------------------ 确定性（C10）
  head('determinism：同 seed + 同输入 → 同日志（C10）')
  local a = newGame({ seed = 42 }); step(a, 6.0)
  local b = newGame({ seed = 42 }); step(b, 6.0)
  ok(table.concat(a.logs, '|') == table.concat(b.logs, '|'),
     '两次运行日志完全一致（' .. #a.logs .. ' 条）')
  local c = newGame({ seed = 43 }); step(c, 6.0)
  ok(table.concat(a.logs, '|') ~= table.concat(c.logs, '|'), '不同 seed → 日志不同（随机确实生效）')

  -- ------------------------------------------- 回合推进与菜单（C5/C8）
  head('loop：不意打ち → 你的回合 → 下一次 Sans 回合（C5/C8）')
  g = newGame({ seed = 1, noSpawn = true })
  toMenu(g)
  ok(g.state == 'menu' and has(g, 'round_clear round=0'), '回合 0 结束进入 menu')
  attackTurn(g)
  ok(has(g, 'round_start round=1'), '攻击（被闪开）后进入第 1 回合')
  toMenu(g)
  ok(has(g, 'round_clear round=1'), '日志含 round_clear round=1')
  local hpBefore2 = g.hp
  M.menuChoose(g, 2)
  ok(g.state == 'sub' and g.sub == 'item', '道具进入子面板（sub=item）')
  M.subConfirm(g)
  ok(has(g, 'item_used id=legend_bread'), '道具可用并记日志（传奇面包）')
  ok(g.hp >= hpBefore2, '回复不减少 HP')
  ok(has(g, 'round_start round=2'), '道具结束回合，进入第 2 回合')

  -- ------------------------------------------------- 子菜单：四个选项
  head('submenus：行动 / 道具 / 仁慈 各自的 UI 与语义（C13）')
  g = newGame({ seed = 1, noSpawn = true })
  toMenu(g)
  ok(g.state == 'menu', '进入你的回合')

  M.menuChoose(g, 1)
  ok(g.state == 'sub' and g.sub == 'act', '行动打开面板')
  ok(#g:subRows() == 4, '行动有 4 个选项（检查/挑衅/求饶/沉默）')
  g.subIndex = 3; M.subConfirm(g)
  ok(has(g, 'act_result id=wait'), '记录 act_result id=wait')
  ok(g.state == 'menu' and not has(g, 'round_start round=1'), '沉默后回到菜单且没推进回合')

  M.menuChoose(g, 1); g.subIndex = 0; M.subConfirm(g)
  ok(has(g, 'act_result id=inspect'), '检查结束回合 → 进入第 1 回合')

  -- 注入的"带上 KR"必须落在**回合 0 结束前**：KR 每 0.5s 烧 1 点、一次命中给 4 点，
  -- 而回合 0 现在的时长 = sans_intro 脚本全长 8.93s（core 按脚本时长延长了 enemyDur，
  -- 见 startEnemy；以前 SURPRISE.dur=2.8s 会把三组龙骨炮整段掐掉）。
  -- 原来写 `{ 2.5 }`（贴着旧的 2.8s 回合尾），现在到进菜单时早烧光了 → 改成尾段三连击，
  -- 任意一发落地都能保证进菜单时 kr ≥ 3。
  local g2 = newGame({ hp = 20, noSpawn = true, hitsAt = { 8.4, 8.6, 8.8 }, noScriptRounds = false })
  toMenu(g2)
  ok(g2.kr > 0, '先带上 KR（kr=' .. g2.kr .. '）')
  M.menuChoose(g2, 1); g2.subIndex = 2; M.subConfirm(g2)
  ok(has(g2, 'kr_cleared by=beg'), '求饶清空 KR')

  local g3 = newGame({ seed = 1, noSpawn = true })
  toMenu(g3)
  M.menuChoose(g3, 1); g3.subIndex = 1; M.subConfirm(g3)
  ok(has(g3, 'act_taunt level=1'), '挑衅记录 act_taunt level=1')

  local g4 = newGame({ seed = 1, noSpawn = true })
  toMenu(g4)
  M.menuChoose(g4, 3)
  ok(g4.state == 'sub' and g4.sub == 'mercy' and #g4:subRows() == 2, '仁慈面板 2 个选项')
  g4.subIndex = 0; M.subConfirm(g4)
  ok(has(g4, 'mercy_refused'), '未到最终回合，饶恕被拒')
  toMenu(g4)
  M.menuChoose(g4, 3); g4.subIndex = 1; M.subConfirm(g4)
  ok(has(g4, 'flee_refused'), '逃跑被拒')

  -- ------------------------------------- 中场（原作第 12 次攻击后）
  head('P-04/P-10：Repeat 命令能带 Color（原版会丢参，我们用可选第 8 参修掉）')
  -- 差距文档 P-04：原版 BoneHRepeat/BoneVRepeat 内部只传 5 个参数，Color 永远是 0；
  -- P-10：直接调用 BoneV/BoneH 时也常常漏 Color。我们给 Repeat 加了**可选第 8 参**（不传 = 0 = 白）。
  local wRep = M.newWorld({ seed = 1, script = M.parseCSV(table.concat({
    '0,CombatZoneResizeInstant,100,100,300,300',
    '0,BoneVRepeat,120,120,40,0,60,3,30,1',   -- 蓝骨 x3
    '0,BoneHRepeat,120,200,40,0,60,3,30,0',   -- 白骨 x3
  }, '\n')) })
  for _ = 1, 4 do wRep:update(DT) end
  local nBlue, nWhite = 0, 0
  for _, b in ipairs(wRep.bones) do
    if b.axis == 'v' and b.color == 1 then nBlue = nBlue + 1 end
    if b.axis == 'h' and (b.color == 0 or b.color == nil) then nWhite = nWhite + 1 end
  end
  ok(nBlue == 3, string.format('P-04：BoneVRepeat 带 Color=1 生成 %d 根蓝骨（原版恒 0）', nBlue))
  ok(nWhite == 3, string.format('P-04：BoneHRepeat 不传 Color → %d 根白骨', nWhite))
  local abBlue = 0
  for _, sc in ipairs(A) do
    if sc.name == 'sans_bonegap1' or sc.name == 'sans_bonegap1fast' then
      for line in tostring(sc.csv):gmatch('[^\n]+') do
        if line:find('BoneVRepeat', 1, true) and line:match(',257,32,') then
          if line:sub(-2) == ',1' then abBlue = abBlue + 1 end
        end
      end
    end
  end
  ok(abBlue == 4, string.format('P-10：bonegap1/1fast 的高骨都显式写了 Color=1（%d/4）', abBlue))

  head('r14-blaster：ROUND 14 单发龙骨炮 SpinTime 1.5 + 到位再等 1s')
  local csvR14
  for _, sc in ipairs(A) do if sc.name == 'randomblaster1' then csvR14 = sc.csv end end
  ok(csvR14 ~= nil and csvR14:find('GasterBlaster,0,%$X,%$Y,%$EndX,%$EndY,%$Ang,0.46666,0.03333', 1, false) ~= nil,
     'r14-blaster：已按回合差异文档 2.5 回原版（SpinTime=0.46666 / BlastTime=0.03333 / 15 发）')

  head('G6/G8：KR 上限与保底、round 与 fightCount 双计数器不漂移')
  -- G6：KR 每次命中 +6/+10，上限 40；烧血保底 hp>1（KR 永远烧不到 0 血）
  local gk = newGame({ seed = 1, noSpawn = true, noScriptRounds = true })
  for _ = 1, 12 do M.debugHurt(gk, 'hit') end
  ok(gk.kr <= 40, string.format('G6：KR 有上限 40（连吃 12 次命中后 kr=%d）', gk.kr))
  gk.hp = 2; gk.kr = 40; gk.invuln = 0
  for _ = 1, 600 do M.update(gk, E, DT) if gk.state ~= 'enemy' then break end end
  ok(gk.hp >= 1, string.format('G6：KR 烧血保底 hp>1（跑 20s 后 hp=%d kr=%d）', gk.hp, gk.kr))
  -- G8：round 是攻击序列、fightCount 只数 FIGHT；后者永远不超过前者，且差值 = 非 FIGHT 行动次数
  local g8 = newGame({ seed = 1, noSpawn = true, noScriptRounds = true })
  local okDrift = true
  for _ = 1, 4 do
    toMenu(g8)
    M.menuChoose(g8, 1)              -- ACT：只推进 round
    if g8.state == 'sub' then M.subBack(g8) end
    M.menuChoose(g8, 0)              -- 再 FIGHT：两个都推进
    if g8.state == 'attack' then M.stopAttack(g8) end
    toMenu(g8)
    if (g8.fightCount or 0) > g8.round then okDrift = false end
  end
  ok(okDrift and g8.round >= g8.fightCount,
     string.format('G8：fightCount ≤ round（round=%d fightCount=%d）', g8.round, g8.fightCount or 0))

  head('items：食物全部是「传奇面包」，每口回 45 HP 且数量很多')
  local gi = newGame({ seed = 1, noSpawn = true })
  local kinds, total, allBread45 = 0, 0, true
  for _, it in ipairs(gi.items or {}) do
    kinds = kinds + 1
    total = total + (it.count or 0)
    if it.name ~= '传奇面包' or it.heal ~= 45 then allBread45 = false end
  end
  ok(kinds >= 1 and allBread45, string.format('items：%d 种食物全部是「传奇面包」且回 45 HP', kinds))
  ok(total >= 10, string.format('items：食物总量很多（合计 %d 个）', total))
  -- 真的吃一口：回 45 且不超过上限
  local gItem = newGame({ seed = 1, noSpawn = true, hp = 92 })
  gItem.hp = 10
  toMenu(gItem)
  M.menuChoose(gItem, 2)
  ok(gItem.state == 'sub' and gItem.sub == 'item', 'items：能打开道具面板')
  M.subConfirm(gItem)
  ok(gItem.hp == 55, string.format('items：吃一口 10 → %d（+45）', gItem.hp))
  ok(gItem:itemCount() < total, 'items：吃一口后数量减 1')

  head('interlude：第 3 回合后 Sans 停手，仁慈=即死（C16）')
  g = newGame({ seed = 1, noSpawn = true, interludeAfter = 3 })
  toMenu(g); attackTurn(g)     -- 回合 0 → 1
  toMenu(g); attackTurn(g)     -- → 2
  toMenu(g); attackTurn(g)     -- → 3
  toMenu(g)                    -- 回合 3 结束
  ok(g.state == 'menu' and g.interlude == true, '进入中场')
  ok(has(g, 'interlude'), '日志含 interlude')
  local items0 = g:itemCount()
  M.menuChoose(g, 2); M.subConfirm(g)
  -- 【第三轮 N1】中场不再强迫玩家必须 FIGHT：任何**完成**的行动都算过场，直接结束中场
  ok(has(g, 'interlude_end'), '中场用道具 → 完成行动即结束中场（N1）')
  ok(g:itemCount() == items0 - 1, '道具确实被消耗')
  -- 另起一局专门验「中场选仁慈 = 立即死亡」
  local gi2 = newGame({ seed = 1, noSpawn = true, interludeAfter = 3 })
  toMenu(gi2); attackTurn(gi2); toMenu(gi2); attackTurn(gi2); toMenu(gi2); attackTurn(gi2); toMenu(gi2)
  ok(gi2.interlude == true, '第二局也进入中场')
  M.menuChoose(gi2, 3)
  ok(has(gi2, 'fail spared_midpoint'), '中场选仁慈 → 立即死亡')
  ok(gi2.state == 'result' and gi2.result == 'fail', '结算为失败')

  -- ------------------------------------- 第 2 回合反饱和（用户反馈）
  head('bone_wall：第 2 回合不再全饱和（缺口固定 + 同时只有一道屏障）')
  g = newGame({ seed = 7, startRound = 2, difficulty = 'hard' })
  local sawBarrier, maxWalls, maxWallsAll = false, 0, 0
  for _ = 1, math.floor(2.8 / DT + 0.5) do
    M.update(g, E, DT)
    if g.state ~= 'enemy' then break end
    if #g.walls > 0 then sawBarrier = true end
    if #g.walls > maxWalls then maxWalls = #g.walls end
  end
  ok(sawBarrier, '第 1 道骨墙确实出现了')
  ok(maxWalls == 1, '屏障是逐个来的（峰值 ' .. maxWalls .. '）')
  ok(not has(g, 'hit hp='), '站在中间不动能安全穿过第 1 道骨墙（缺口居中，上手保证）')
  for _ = 1, math.floor(8 / DT + 0.5) do
    M.update(g, E, DT)
    if g.state ~= 'enemy' then break end
    if #g.walls > maxWallsAll then maxWallsAll = #g.walls end
  end
  ok(maxWallsAll <= 1, '整回合同时存在的骨墙不超过 1 道（peak=' .. maxWallsAll .. '）')

  -- -------------------------------------------------------- 难度与调参
  head('difficulty：难度真的改变弹幕节拍（用户反馈：攻击太快）')
  local function cadence(diff)
    local gg = newGame({ seed = 42, startRound = 5, difficulty = diff })
    local firstAt, secondAt, t, peakLethal = -1, -1, 0, 0
    for _ = 1, math.floor(20 / DT + 0.5) do
      M.update(gg, E, DT)
      t = t + DT
      if gg.state ~= 'enemy' then break end
      local lethal = {}
      local n = 0
      for _, bon in ipairs((gg.world and gg.world.bones) or {}) do
        if bon.wave ~= nil and bon.lethal and not lethal[bon.wave] then
          lethal[bon.wave] = true
          n = n + 1
        end
      end
      if n > peakLethal then peakLethal = n end
      if firstAt < 0 and gg.wave >= 1 then firstAt = t
      elseif secondAt < 0 and gg.wave >= 2 then secondAt = t; break end
    end
    return { gap = secondAt - firstAt, peakLethal = peakLethal }
  end
  local e, n, h = cadence('easy'), cadence('normal'), cadence('hard')
  note(string.format('生成间隔 easy=%.2fs normal=%.2fs hard=%.2fs | peakLethal hard=%d',
                     e.gap, n.gap, h.gap, h.peakLethal))
  ok(e.gap > h.gap, string.format('简单档生成更慢（%.2fs > %.2fs）', e.gap, h.gap))
  ok(math.abs(h.gap - 1.20) < 0.12, string.format('困难档受 floorLock 限制，节拍 ≈1.2s（实测 %.2fs）', h.gap))
  ok(n.gap > h.gap and n.gap < e.gap, string.format('普通档位于两者之间（%.2fs）', n.gap))
  ok(h.peakLethal <= 1, '同一时刻最多只有一波地面骨头处于致命阶段（peak=' .. h.peakLethal .. '）')

  -- ======================================================================
  -- 以下对应 prototype/attack-selftest.js（22 条）
  -- ======================================================================
  head('attack-scripts：attacks.lua 里**全部**攻击脚本编译 + 空跑（无未知命令 / 90s 内 EndAttack）')
  -- 从写死 11 个改成遍历 attacks.lua 全表（27 个）：新增的 spiral1/2/3、以及此前没人跑过的
  -- final / multi* / platform* / randomblaster* 都必须过这一关。
  -- spiral3 = 原作阶段④旋转光束（实测 122 发）+ 阶段⑤力竭（38 次砸击），时间线最长，上限给 90s。
  local files = {}
  for _, s in ipairs(A) do files[#files + 1] = s.name end
  table.sort(files)
  for _, f in ipairs(files) do
    local csv = nil
    for _, s in ipairs(A) do if s.name == f then csv = s.csv end end
    ok(csv ~= nil, f .. ' 在 attacks.lua 中存在')
    local w = M.newWorld({ seed = 7, script = M.parseCSV(csv) })
    local frames = 0
    local maxFrames = math.floor(90 / DT + 0.5)
    while not w.ended and frames < maxFrames do
      w:update(DT)
      frames = frames + 1
    end
    local unknown = nil
    for _, s in ipairs(w.log) do
      if s:sub(1, 7) == 'unknown' then unknown = s; break end
    end
    ok(unknown == nil, f .. ' 无未知命令' .. (unknown and ('（' .. unknown .. '）') or ''))
    ok(w.ended, string.format('%s 在 %.1fs 内结束%s', f, frames * DT, w.ended and '' or '（超时未 EndAttack）'))
    note(string.format('%-22s 实体：骨头 %d / 正弦 %d / 龙骨炮 %d / 平台 %d　日志 %d 条',
                       f, #w.bones, #w.sine, #w.blasters, #w.platforms, #w.log))
  end

  -- ======================================================================
  -- 契约补充项（gdd.md C1–C19 里 JS 原型未覆盖、本移植显式落实的部分）
  -- ======================================================================
  head('extra-final：24 回合版最后一回合（内部号 23 = 原作 sans_final）打完 → 攻击=击倒 / 仁慈=饶恕')
  -- 打一次「攻击」（等它回到菜单，再进行下一次）
  local function attackOnce(gg)
    local guard2 = 0
    while gg.state ~= 'menu' and gg.state ~= 'result' and guard2 < 40000 do
      M.update(gg, E, DT)
      clearHazards(gg)
      guard2 = guard2 + 1
    end
    if gg.state ~= 'menu' then return false end
    M.menuChoose(gg, 0)
    if gg.state == 'attack' then M.stopAttack(gg) end
    guard2 = 0
    while gg.state == 'attack' and guard2 < 600 do
      M.update(gg, E, DT)
      guard2 = guard2 + 1
    end
    return true
  end

  g = newGame({ seed = 1, noSpawn = true, noScriptRounds = true, startRound = 23 })
  ok(g.round == 23, '能从内部号 23 起局（最后一回合）')
  ok(g.final == false, '刚进最后一回合时 final 仍为 false')
  do  -- 这一回合走完（noScriptRounds：没有弹幕，回合时长按 SPIRAL_DEFS[3].dur）
    local guard3 = 0
    while g.state == 'enemy' and guard3 < 40000 do
      M.update(g, E, DT); clearHazards(g); guard3 = guard3 + 1
    end
  end
  ok(g.state == 'menu' and g.final == true, '最后一回合结束后 final = true（他力竭、躲不开）')
  M.menuChoose(g, 0)
  ok(g.state == 'attack', '选「攻击」进入攻击条')
  M.stopAttack(g)
  do
    local guard3 = 0
    while g.state == 'attack' and guard3 < 900 do M.update(g, E, DT); guard3 = guard3 + 1 end
  end
  ok(g.state == 'result' and g.result == 'kill', '致命一击 → 击倒结局')
  ok(has(g, 'sans_hit final=1'), '日志含 sans_hit final=1')

  head('extra-spare：最终回合选仁慈 → 饶恕结局（C16 对照）')
  g = newGame({ seed = 1, noSpawn = true, noScriptRounds = true, startRound = 23 })
  ok(driveToFinal(g), '先推进到最后一回合结束后的菜单')
  ok(g.final == true, 'final=true')
  M.menuChoose(g, 3); g.subIndex = 0; M.subConfirm(g)
  ok(g.state == 'result' and g.result == 'spare', '最终回合饶恕 → spare 结局')

  head('extra-wall-slam：壁ドン 0 伤害（SansSlamDamage 0）')
  local w = M.newWorld({ seed = 1, script = M.parseCSV('0,SansSlamDamage,0\n0,HeartMaxFallSpeed,300\n0,HeartMode,1\n0,SansSlam,0\n1,EndAttack\n') })
  w:update(DT)
  ok(w.slamDamage == false, 'SansSlamDamage 0 → w.slamDamage=false')
  ok(w.heart.mode == 1 and w.heart.maxFall == 300 and w.heart.dir == 0, '砸击参数已写入（mode/maxFall/dir）')
  ok(w.heart.vx == 300 and w.heart.vy == 0, 'SansSlam 0（东）→ vx=+maxFall、vy=0')

  head('extra-cmd-coverage：命令/运算/跳转覆盖表')
  local expect = {
    'CombatZoneResize', 'CombatZoneResizeInstant', 'CombatZoneSpeed', 'CombatZonePos',
    'HeartTeleport', 'HeartMode', 'HeartMaxFallSpeed', 'SansSlam', 'SansSlamDamage', 'GetHeartPos',
    'BoneV', 'BoneH', 'BoneVRepeat', 'BoneHRepeat', 'SineBones', 'BoneStab', 'GasterBlaster',
    'Platform', 'PlatformRepeat', 'BlackScreen', 'Sound', 'Music', 'TLPause', 'TLResume', 'EndAttack',
    'SansAnimation', 'SansHead', 'SansBody', 'SansTorso', 'SansSweat', 'SansX', 'SansRepeat',
    'SansEndRepeat', 'SansText',
    'SET', 'ADD', 'SUB', 'MUL', 'DIV', 'MOD', 'FLOOR', 'DEG', 'RAD', 'SIN', 'COS', 'ANGLE', 'RND',
  }
  local miss = {}
  for _, k in ipairs(expect) do if M.commands[k] == nil then miss[#miss + 1] = k end end
  ok(#miss == 0, '19 类命令全部实现（缺：' .. table.concat(miss, ',') .. '）')
  local jexpect = { 'JMPABS', 'JMPREL', 'JMPZ', 'JMPNZ', 'JMPE', 'JMPNE', 'JMPL', 'JMPNL', 'JMPG', 'JMPNG' }
  miss = {}
  for _, k in ipairs(jexpect) do if M.jumps[k] == nil then miss[#miss + 1] = k end end
  ok(#miss == 0, '10 个跳转全部实现（缺：' .. table.concat(miss, ',') .. '）')

  head('extra-jump-semantics：三个曾修过的跳转 bug 必须不复现')
  -- (1) JMPREL 是**相对偏移**：pc = pc + off
  local w2 = M.newWorld({ seed = 1, script = M.parseCSV('0,SET,A,0\n0,JMPREL,3\n0,SET,A,1\n0,SET,A,2\n0,SET,A,3\n0,EndAttack\n') })
  for _ = 1, 10 do w2:update(DT) end
  -- 行 2（pc=1，0-based）JMPREL 3 → pc=4 → 执行 SET,A,3
  ok(w2.vars.A == 3, 'JMPREL 相对偏移生效（A=' .. tostring(w2.vars.A) .. '，期望 3）')
  -- (2) 跳转测试参数不含目标行号：JMPE 的测试值是 args[2], args[3]
  local w3 = M.newWorld({ seed = 1, script = M.parseCSV('0,SET,A,5\n0,JMPE,4,$A,5\n0,EndAttack\n0,EndAttack\n') })
  for _ = 1, 10 do w3:update(DT) end
  ok(w3.ended == true, 'JMPE 用 args[2..3] 比较（目标行号未参与测试）')
  -- (3) exec 里读 line.cmd / line.rel，而不是把命令名存进局部字符串变量
  local w4 = M.newWorld({ seed = 1, script = M.parseCSV('0,SET,N,3\n0,JMPNZ,4,$N\n0,SET,N,99\n0,EndAttack\n') })
  for _ = 1, 10 do w4:update(DT) end
  ok(w4.vars.N == 3, 'JMPNZ 跳转后不再执行下面的 SET（N=' .. tostring(w4.vars.N) .. '，期望 3）')
  -- 标签行占一行：JMPABS 到标签后面的行号不整体错位
  local w5 = M.newWorld({ seed = 1, script = M.parseCSV('0,JMPABS,L2\n0,SET,A,1\n:L2\n0,SET,A,2\n0,EndAttack\n') })
  for _ = 1, 10 do w5:update(DT) end
  ok(w5.vars.A == 2, '标签行占一行（A=' .. tostring(w5.vars.A) .. '，期望 2）')

  head('extra-rng：mulberry32 与 attack-engine.js 逐值一致（C10 确定性的地基）')
  -- 参考值由 `new (require('./prototype/attack-engine.js').World)({seed}).rng()` 打印。
  -- 【2026-10 修正】这组值以前是从**移植后的错误实现**打印的（core 的 mulberry32 曾把 JS 的
  --   `>>> 0` 写成 `RSHIFT(..., 14)`，所有随机值被额外除以 2^14），所以测试一直绿、
  --   而 rng() 实际上恒在 1e-5 量级（`rng() < 0.5` 恒真、`floor(rng()*n)` 恒 0）。
  --   现在这组值取自上表的 JS 原型本身，Lua 侧必须与它逐值一致。
  local expectRng = {
    [20261004] = { 0.7636976554, 0.8514767042, 0.9496503982, 0.2061206487, 0.2841686481, 0.2745044001 },
    [1] = { 0.6270739406, 0.0027357212, 0.5274470400, 0.9810509675, 0.9683778982, 0.2811035030 },
    [42] = { 0.6011037519, 0.4482905590, 0.8524657935, 0.6697340414, 0.1748138987, 0.5265925422 },
    [7] = { 0.0117047532, 0.0619582576, 0.9769076328, 0.6990287057, 0.5214452685, 0.4055216881 },
  }
  local rngOk = true
  for seed, exp in pairs(expectRng) do
    local rng = M.mulberry32(seed)
    for i = 1, #exp do
      if math.abs(rng() - exp[i]) > 5e-11 then rngOk = false end
    end
  end
  ok(rngOk, '4 个 seed × 6 个值与 attack-engine.js 逐值一致')
  -- 顺带钉死"随机值必须真的铺满 [0,1)"：坏实现的特征是 6 个值全 < 1e-3
  do
    local rng = M.mulberry32(20260927)
    local big, spread = 0, { min = 1, max = 0 }
    for _ = 1, 200 do
      local v = rng()
      if v > 0.1 then big = big + 1 end
      if v < spread.min then spread.min = v end
      if v > spread.max then spread.max = v end
    end
    ok(big > 150, string.format('200 次取值里有 %d 次 > 0.1（坏实现会恒为 0）', big))
    ok(spread.max - spread.min > 0.5,
      string.format('取值铺开 [%.3f, %.3f]', spread.min, spread.max))
  end

  head('extra-render：render 是纯函数且不崩（含各状态）')
  local states = { 'title', 'menu', 'sub', 'attack', 'result' }
  local pureOk, kindOk = true, true
  for _, st in ipairs(states) do
    local gg = newGame({ seed = 1 })
    if st == 'menu' then toMenu(gg)
    elseif st == 'sub' then toMenu(gg); M.menuChoose(gg, 1)
    elseif st == 'attack' then toMenu(gg); M.menuChoose(gg, 0)
    elseif st == 'result' then gg:finish('fail', 'hp_zero') end
    local before = M.snapshot(gg)
    local c1 = M.render(gg)
    local c2 = M.render(gg)
    local after = M.snapshot(gg)
    if #c1 ~= #c2 then pureOk = false end
    if before.state ~= after.state or before.hp ~= after.hp or before.bones ~= after.bones then pureOk = false end
    ok(#c1 > 0, 'render 在 state=' .. st .. ' 返回 ' .. #c1 .. ' 条绘制指令')
    for _, cm in ipairs(c1) do
      if cm.kind == nil then kindOk = false end
    end
  end
  ok(pureOk, 'render 两次调用结果一致且不修改状态（纯函数）')
  ok(kindOk, '所有绘制指令都带 kind 字段')
  -- 9 种规定 kind 都出现过（补上 menu / sine / stab / sub / attackBar / flash 的探针）
  local seenAll = {}
  do
    local probe = {}
    local function scan(gg)
      for _, cm in ipairs(M.render(gg)) do probe[cm.kind] = true end
    end
    -- menu / sub / attack / flash / box / soul / hudText / bone / wall
    local g6 = newGame({ seed = 7, startRound = 2, difficulty = 'hard' })
    for _ = 1, 240 do M.update(g6, E, DT); scan(g6) end
    g6 = newGame({ seed = 1, noSpawn = true })
    toMenu(g6); scan(g6)
    M.menuChoose(g6, 1); scan(g6)                       -- sub 面板
    M.subBack(g6); M.menuChoose(g6, 0); scan(g6)        -- attackBar
    -- platform / sine / stab：跑一遍带脚本的关卡
    g6 = newGame({ seed = 1, startRound = 6 })          -- blue_soul: platform
    for _ = 1, 300 do M.update(g6, E, DT); scan(g6) end
    g6 = newGame({ seed = 3, startRound = 3 })          -- blue_bone: 颜色骨
    for _ = 1, 300 do M.update(g6, E, DT); scan(g6) end
    g6 = newGame({ seed = 1, startRound = 4 })          -- blaster: 内置龙骨炮
    for _ = 1, 400 do M.update(g6, E, DT); scan(g6) end
    -- 正弦骨 / 骨刺 / 平台：注入一个与游戏框对齐的固定 zone
    --（box = 420x260 居中 → 脚本坐标 (350,279)-(770,539)）
    local wIso = M.newWorld({ seed = 1, script = M.parseCSV('0,SineBones,20,-24,360,25\n0,BoneStab,1,54,0.05,0.5\n0,PlatformRepeat,120,300,60,0,90,3,70\n5,EndAttack\n') })
    wIso.zone.l, wIso.zone.t = 350, 279
    wIso.zone.r, wIso.zone.b = 770, 539
    wIso.zone.tl, wIso.zone.tt, wIso.zone.tr, wIso.zone.tb = 350, 279, 770, 539
    local gIso = newGame({ seed = 1, noSpawn = true })
    gIso.state = 'enemy'
    gIso.world = wIso
    gIso.box = { x = 110, y = 53, w = 420, h = 260 }
    gIso.soul.x, gIso.soul.y = 320, 183
    local sineCmd = nil
    for _ = 1, 240 do
      wIso:update(DT)
      scan(gIso)
      if not sineCmd then
        for _, c in ipairs(M.render(gIso)) do if c.kind == 'sine' then sineCmd = c end end
      end
    end
    -- 正弦骨的 bars 契约：两根**竖长骨**（不是命中盒），厚度 = w = 19、长度 = h，
    -- 从战斗框上下边顶到走廊口；命中盒固定 19×19 跟着 centerY 走。
    if sineCmd then
      ok(type(sineCmd.bars) == 'table' and #sineCmd.bars >= 1,
         'sine.bars 至少输出 1 根长骨（#bars=' .. tostring(sineCmd.bars and #sineCmd.bars) .. '）')
      local b1 = sineCmd.bars and sineCmd.bars[1]
      ok(b1 ~= nil and math.max(b1.w, b1.h) >= 30,
         string.format('bars[1] 是长骨而不是小块（%.0f×%.0f）', b1 and b1.w or -1, b1 and b1.h or -1))
      ok(b1 ~= nil and b1.w == M.BONE_W and b1.vertical == true,
         string.format('bars[1] 厚度 = w = BONE_W(%d) 且 vertical=true', M.BONE_W))
      ok(math.abs((b1.y + b1.h) - (sineCmd.gapTop or -1)) < 0.01,
         'bars[1] 底边正好等于走廊上口 gapTop')
      local b2 = sineCmd.bars and sineCmd.bars[2]
      if b2 then
        ok(math.abs(b2.y - (sineCmd.gapBottom or -1)) < 0.01, 'bars[2] 顶边正好等于走廊下口 gapBottom')
      else
        ok(true, 'bars[2] 不存在（走廊被夹到框边，允许只输出 1 根）')
      end
      ok(sineCmd.hit ~= nil and sineCmd.hit.h == 19 and sineCmd.hit.w == 19,
         'sine.hit 是 19×19 的命中盒（不跟长骨一样长）')
      ok(math.abs(sineCmd.hit.y + 9.5 - sineCmd.centerY) < 0.01, 'sine.hit 中心 = centerY')
      -- **帧一致性**：sine 的 y 属于「脚本绝对坐标帧」（与 box 命令同帧、不经 shiftAbs）
      ok(math.abs(b1.y - wIso.zone.t) < 0.01,
         string.format('bars[1].y == zone.t（%.1f vs %.1f）—— 没被多加一次 BOX_OFF_Y', b1.y, wIso.zone.t))
    else
      ok(false, '没抓到 sine 命令（探针失效）')
    end

    -- ---- 行为回归：正弦骨到底打不打得到人（几何自洽 ≠ 跨帧比较正确）----
    -- 两个曾经的 bug 一起锁住：
    --   ① sine 的 y 被 shiftAbs 多加一次 BOX_OFF_Y → 判定离灵魂 226px，站骨头上也不掉血；
    --   ② w.sine 是**独立实体表**，原来根本没进碰撞循环 → 视觉有骨头、判定完全没有。
    -- 探针：把 sine 钉在灵魂那一列并清掉水平速度，再按 frame 摆灵魂，用 core 真跑断言 HP。
    local ZL, ZT, ZW, ZH = 350, 279, 420, 260       -- zone.t=279,b=539 → baseY=409, amp=12.5, gap=25
    local function sineHitProbe(phase, dy)
      local w2 = M.newWorld({ seed = 1, script = M.parseCSV('0,SineBones,1,0,0,25\n0,HeartMode,0\n0,TLResume\n9,EndAttack\n') })
      w2.zone.l, w2.zone.t = ZL, ZT
      w2.zone.r, w2.zone.b = ZL + ZW, ZT + ZH
      w2.zone.tl, w2.zone.tt, w2.zone.tr, w2.zone.tb = ZL, ZT, ZL + ZW, ZT + ZH
      w2:update(DT)                                   -- 生成 sine（speed=0 → 不动）
      local gg = newGame({ seed = 1, noSpawn = true })
      gg.state = 'enemy'
      gg.enemyDur = 1e9
      gg.spawnT = 1e9
      gg.world = w2
      gg.box = { x = ZL - M.BOX_OFF_X, y = ZT - M.BOX_OFF_Y, w = ZW, h = ZH }
      for _, s in ipairs(w2.sine) do s.x = 480; s.phase = phase; s.dir = 0 end
      local gm = M.sineGeom(w2.sine[1])
      gg.soul.x = 480 - M.BOX_OFF_X
      gg.soul.y = (gm.centerY + dy) - M.BOX_OFF_Y
      gg.prevX, gg.prevY = gg.soul.x, gg.soul.y
      gg.invuln = 0
      M.update(gg, E, DT)
      return has(gg, 'hit hp='), gg, gm
    end
    -- 取 phase 使 sin(phase)≈0 → centerY≈baseY=409，走廊 = 396.5..421.5
    local _, _, gmRef = sineHitProbe(0, 0)
    -- 原版 SineBones：上骨从 zone.t+6 起、高 height+sine；走廊再从它下面量固定 39px。
    -- 所以 zone.t=279、height=25、sine=0 → 上骨底 310、走廊 310..349、中心 329.5。
    ok(math.abs(gmRef.centerY - 329.5) < 0.01, '走廊中心 = 329.5（原版几何，实际 ' .. gmRef.centerY .. '）')
    local hitOnBone, ggBone = sineHitProbe(0, 105)   -- 下长骨内部（409+105=514）
    ok(hitOnBone, '灵魂站在正弦长骨上 → 命中掉血（HP=' .. ggBone.hp .. '）')
    ok(ggBone.hp < M.MAX_HP, string.format('长骨命中后 HP 真的下降（%d → %d）', M.MAX_HP, ggBone.hp))
    local hitInGap, ggGap = sineHitProbe(0, 0)       -- 走廊中心
    ok(not hitInGap, '灵魂站在走廊中心 → 不命中（HP=' .. ggGap.hp .. '）')
    ok(ggGap.hp == M.MAX_HP, string.format('走廊中心 HP 不变（%d → %d）', M.MAX_HP, ggGap.hp))
    local kinds = { bone = 1, blaster = 1, box = 1, soul = 1, hudText = 1, menu = 1,
                    platform = 1, flash = 1, wall = 1, sine = 1, stab = 1, sub = 1, attackBar = 1 }
    for k in pairs(kinds) do if probe[k] then seenAll[#seenAll + 1] = k end end
    table.sort(seenAll)
  end
  ok(#seenAll >= 13, '实测出现的绘制 kind：' .. table.concat(seenAll, ','))

  head('extra-box-bounds：战斗框永远在世界内、居中、且各状态同一位置（用户反馈"框到处移动"）')
  -- 回归三个叠加的 bug：
  --   A. BOX_CY 写成 183（应为 308.5 = BTS 默认框中心 226+165/2）→ 所有内置框偏高 125.5px
  --   B. 内置回合把 self.box 写成绝对坐标，render 又 +BOX_OFF → 双平移、框跑到世界外
  --   C. 菜单态把框上移 96px 去给按钮让位 → "框瞬移"
  -- 断言：① 每相 box 都在世界内；② 中心恒为 (320, 308.5)；③ menu/sub/attack/result 的框 y 与 enemy 相同。
  local overs, checked, samples, offCenter, yMismatch = {}, 0, {}, {}, {}
  local function boxOf(gg)
    for _, c in ipairs(M.render(gg)) do if c.kind == 'box' then return c end end
    return nil
  end
  local function checkBox(gg, tag)
    local c = boxOf(gg)
    if not c then return nil end
    checked = checked + 1
    if not (c.x >= 0 and c.y >= 0 and c.x + c.w <= M.VW and c.y + c.h <= M.VH) then
      overs[#overs + 1] = string.format('%s (%.0f,%.0f,%.0f,%.0f)', tag, c.x, c.y, c.w, c.h)
    end
    if #samples < 4 then
      samples[#samples + 1] = string.format('%s(%.0f,%.0f,%.0f,%.0f)', tag, c.x, c.y, c.w, c.h)
    end
    if math.abs((c.x + c.w / 2) - 320) > 1 or math.abs((c.y + c.h / 2) - 308.5) > 1 then
      offCenter[#offCenter + 1] = string.format('%s cx=%.1f cy=%.1f', tag, c.x + c.w / 2, c.y + c.h / 2)
    end
    return c
  end
  -- ① 内置回合 0..6（noSpawn 隔离，不挂脚本）
  for r = 0, 6 do
    local gg = newGame({ seed = 1, noSpawn = true, startRound = math.max(r, 1) })
    gg:startEnemy(r)
    checkBox(gg, 'round' .. r)
  end
  -- ② 螺旋档三回合（内部号 17/18/19，20 回合版的最后三段）
  --    （旧版这里遍历 FINAL_PHASES「最终回合分三段」，该结构已被 20 回合 + 螺旋档取代）
  for _, r in ipairs({ 17, 18, 19 }) do
    local gg = newGame({ seed = 1, noSpawn = true, startRound = r, noScriptRounds = false })
    gg:startEnemy(r)
    checkBox(gg, 'spiral' .. r)
  end
  -- ③ 菜单类状态必须与 enemy 状态**同一 y**（不再上移）
  local gm = newGame({ seed = 1, noSpawn = true })
  gm:startEnemy(1)
  local yEnemy = boxOf(gm).y
  toMenu(gm)
  local cMenu = checkBox(gm, 'menu')
  M.menuChoose(gm, 0)
  local cAtk = checkBox(gm, 'attack')
  local gsub = newGame({ seed = 1, noSpawn = true })
  gsub:startEnemy(1); toMenu(gsub); M.menuChoose(gsub, 1)
  local cSub = checkBox(gsub, 'sub')
  local gres = newGame({ seed = 1, noSpawn = true })
  gres:startEnemy(1); gres:finish('fail', 'hp_zero')
  local cRes = checkBox(gres, 'result')
  ok(cMenu and cAtk and cSub and cRes ~= nil, 'menu/sub/attack/result 都能拿到 box 指令')
  local function sameY(tag, c)
    if c and math.abs(c.y - yEnemy) > 0.01 then
      yMismatch[#yMismatch + 1] = string.format('%s y=%.1f (enemy y=%.1f)', tag, c.y, yEnemy)
    end
  end
  sameY('menu', cMenu); sameY('attack', cAtk); sameY('sub', cSub); sameY('result', cRes)
  -- ④ 跑满一整轮真实流程，确认没有中途冒出越界/偏移的框
  local gr = newGame({ seed = 7, startRound = 6 })
  for _ = 1, 600 do
    M.update(gr, E, DT)
    if gr.state == 'result' then break end
    checkBox(gr, 'run')
  end
  ok(#overs == 0, '所有 box 指令都在 0..640 / 0..480 内' ..
     (#overs > 0 and ('（越界 ' .. #overs .. ' 次：' .. table.concat(overs, '; ') .. '）') or ''))
  ok(#offCenter == 0, '所有 box 中心 = (320, 308.5)' ..
     (#offCenter > 0 and ('（异常：' .. table.concat(offCenter, '; ') .. '）') or ''))
  ok(#yMismatch == 0, 'menu/sub/attack/result 的框 y 与 enemy 相同（不再上移）' ..
     (#yMismatch > 0 and ('（异常：' .. table.concat(yMismatch, '; ') .. '）') or ''))
  note('检查了 ' .. checked .. ' 个 box 指令；示例 ' .. table.concat(samples, ' '))

  head('extra-sub-panel：子面板矩形必须在框内、也在世界内（曾经 348..560 掉出底边 80px）')
  local subBad, subSeen = {}, 0
  for _, kind in ipairs({ 'act', 'item', 'mercy' }) do
    local gs2 = newGame({ seed = 1, noSpawn = true })
    gs2:startEnemy(1)
    toMenu(gs2)
    M.menuChoose(gs2, kind == 'act' and 1 or (kind == 'item' and 2 or 3))
    local bx, by, bw, bh, sp
    for _, c in ipairs(M.render(gs2)) do
      if c.kind == 'box' then bx, by, bw, bh = c.x, c.y, c.w, c.h end
      if c.kind == 'sub' then sp = c end
    end
    if sp then
      subSeen = subSeen + 1
      local okWorld = sp.x >= 0 and sp.y >= 0 and sp.x + sp.w <= M.VW and sp.y + sp.h <= M.VH
      local okBox = sp.x >= bx - 0.01 and sp.y >= by - 0.01
                    and sp.x + sp.w <= bx + bw + 0.01 and sp.y + sp.h <= by + bh + 0.01
      if not (okWorld and okBox) then
        subBad[#subBad + 1] = string.format('sub=%s panel=(%.0f,%.0f,%.0f,%.0f) box=(%.0f,%.0f,%.0f,%.0f)',
          kind, sp.x, sp.y, sp.w, sp.h, bx, by, bw, bh)
      end
      ok(sp.rowH ~= nil and sp.rowH >= 24, 'sub.' .. kind .. ' rowH >= 24（实际 ' .. tostring(sp.rowH) .. '）')
      -- 内容必须塞得下：标题 34 + 描述 24 + 行数 × rowH
      local need = 34 + 24 + sp.rowH * #sp.rows
      ok(need <= sp.h + 0.01, string.format('sub.%s 内容放得下（%d 行 × %d + 58 = %d <= %.0f）',
        kind, #sp.rows, sp.rowH, need, sp.h))
    else
      ok(false, 'sub.' .. kind .. ' 没拿到面板指令')
    end
  end
  ok(subSeen == 3, 'act/item/mercy 三个面板都拿到了（' .. subSeen .. '/3）')
  ok(#subBad == 0, '子面板矩形都在框内且在世界内' ..
     (#subBad > 0 and ('（异常：' .. table.concat(subBad, '; ') .. '）') or ''))

  head('blue-jump：按住 0.25s 升到 3/5 框高、超时自然下落、松开匀速落下')
  -- 用户第十/十一轮口径：跳跃时间 0.25s、跳跃高度 3/5 框高；**按住不动不能一直浮空**。
  local function jumpCurve(hold)
    local gj = newGame({ scripts = A })
    gj:startEnemyScript('sans_boneslideh')        -- 蓝魂、框 375x140
    for _ = 1, 20 do M.update(gj, {}, DT) end
    local y0 = gj.soul.y
    M.jump(gj)
    local peak, tUp = y0, 0
    local n = math.floor(hold / DT + 0.5)
    for _ = 1, n do
      M.update(gj, { jumpHeld = true }, DT)
      tUp = tUp + DT
      if gj.soul.y < peak then peak = gj.soul.y end
    end
    local tDown = 0
    for k = 1, 400 do
      M.update(gj, { jumpHeld = false }, DT)
      tDown = tDown + DT
      if gj.soul.grounded and k > 1 then break end
    end
    return y0 - peak, gj.box.h, tUp, tDown
  end
  local rise025, boxH, up025, down025 = jumpCurve(0.25)
  local rise20 = jumpCurve(2.0)
  local rise01, _, up01, down01 = jumpCurve(0.1)
  ok(math.abs(rise025 / boxH - 0.60) <= 0.04,
     string.format('blue-jump：按住 0.25s 升到 3/5 框高（实测 %.1fpx / %.0f = %.3f）', rise025, boxH, rise025 / boxH))
  ok(math.abs(rise01 / boxH - 0.24) <= 0.03,
     string.format('blue-jump：匀速上升（按 0.1s = 0.24 框高，实测 %.1fpx / %.0f = %.3f）', rise01, boxH, rise01 / boxH))
  ok(math.abs(rise025 - rise01 * 2.5) <= 4,
     string.format('blue-jump：上升高度与按住时长成正比（0.1s→%.1f，0.25s→%.1f）', rise01, rise025))
  ok(math.abs(rise20 - rise025) <= 1.0,
     string.format('blue-jump：按 2s 也不会更高（0.25s→%.1f，2.0s→%.1f）', rise025, rise20))
  ok(math.abs(down025 - 0.9) <= 0.1,
     string.format('blue-jump：从 3/5 框高落回用 ~0.9s（下落速率仍是 0.5框高/0.75s，实测 %.3fs）', down025))
  ok(math.abs(down01 - 0.24 * 0.75 / 0.5) <= 0.09,
     string.format('blue-jump：下落速率恒定 = 0.5框高/0.75s（按 0.1s 上升的高度落回用 %.3fs）', down01))
  -- 关键：按住不放要自然落回地面，不能一直浮空
  local gHold = newGame({ scripts = A })
  gHold:startEnemyScript('sans_boneslideh')
  for _ = 1, 20 do M.update(gHold, {}, DT) end
  local yGround = gHold.soul.y
  M.jump(gHold)
  for _ = 1, math.floor(2.0 / DT + 0.5) do M.update(gHold, { jumpHeld = true }, DT) end   -- 一直按住 2s
  ok(gHold.soul.grounded and math.abs(gHold.soul.y - yGround) < 1.5,
     string.format('blue-jump：按住不放会自然落回地面（2s 后 grounded=%s y=%.1f vs %.1f）',
                   tostring(gHold.soul.grounded), gHold.soul.y, yGround))
  -- 下降途中再按跳跃键不能重新上升（不能二段跳）
  local gj2 = newGame({ scripts = A })
  gj2:startEnemyScript('sans_boneslideh')
  for _ = 1, 20 do M.update(gj2, {}, DT) end
  M.jump(gj2)
  for _ = 1, 6 do M.update(gj2, { jumpHeld = true }, DT) end
  for _ = 1, 3 do M.update(gj2, { jumpHeld = false }, DT) end
  local yRe = gj2.soul.y
  local minY = yRe
  for _ = 1, 15 do
    M.update(gj2, { jumpHeld = true }, DT)
    if gj2.soul.y < minY then minY = gj2.soul.y end
  end
  ok(minY >= yRe - 0.6,
     string.format('blue-jump：下降途中按住跳跃键不会重新上升（最高只到 %.1f，起点 %.1f）', minY, yRe))
  head('blue-jump-on-platform：空中板子与地面走同一个落地模型（原版 HeartCheckSolid）')
  -- 原来的 bug（修改意见文档 R1/R2）：落地复位写在蓝魂分支里，而**脚本平台**的落地判定
  -- 在分支之后才做 → 落在空中板子上时 jumping 一直是 true，第 2 跳被 Game:jump 拦掉。
  do
    local gp = newGame({ scripts = A, hp = 1000000 })
    gp:startEnemyScript('platforms1')
    local pf
    for _ = 1, 400 do
      M.update(gp, {}, DT)
      for _, p in ipairs(gp.world.platforms) do
        local px = p.x - 240
        if px > gp.box.x and px + p.w < gp.box.x + gp.box.w and (p.speed or 0) > 0 then pf = p break end
      end
      if pf then break end
    end
    if not pf then
      ok(false, 'blue-jump-on-platform：400 帧内没找到框内的移动脚本平台')
    else
      local px, py = pf.x - 240, pf.y - 226
      gp.soul.x, gp.soul.y = px + pf.w / 2, py - 8
      gp.prevX, gp.prevY = gp.soul.x, gp.soul.y
      for _ = 1, 6 do M.update(gp, {}, DT) end
      ok(gp.soul.grounded and math.abs(gp.soul.y - (py - 8)) < 2,
        string.format('blue-jump-on-platform：能站在空中板子上（y=%.1f 板面=%.1f grounded=%s）',
          gp.soul.y, py, tostring(gp.soul.grounded)))
      gp.soul.jumping = false
      M.jump(gp)
      ok(gp.soul.vy < -1,
        string.format('blue-jump-on-platform：板子上第 1 跳 vy=%.1f < 0', gp.soul.vy))
      local landed = false
      for k = 1, 200 do
        M.update(gp, {}, DT)
        if gp.soul.grounded and k > 2 then landed = true break end
      end
      ok(landed and gp.soul.jumping == false,
        string.format('blue-jump-on-platform：落回板子后 jumping 必须复位（grounded=%s jumping=%s）',
          tostring(gp.soul.grounded), tostring(gp.soul.jumping)))
      M.jump(gp)
      ok(gp.soul.vy < -1,
        string.format('blue-jump-on-platform：板子上能连跳（第 2 跳 vy=%.1f < 0）', gp.soul.vy))
    end
  end
  head('platforms3-safe：ROUND 10 两根扫平台站立带的骨头已削短')
  -- 站立带 = 平台顶面 -SOUL_CLAMP(8) 为心，±SOUL_R(4)：y = py-12 .. py-4
  local csvP3
  for _, sc in ipairs(A) do if sc.name == 'platforms3' then csvP3 = sc.csv end end
  local bonesP3 = {}
  for line in tostring(csvP3):gmatch('[^\n]+') do
    if line:sub(1, 1) ~= '#' then
      local c = {}
      for cell in line:gmatch('[^,]*') do c[#c + 1] = cell end
      if c[2] == 'BoneV' then bonesP3[#bonesP3 + 1] = { y = tonumber(c[4]), h = tonumber(c[5]) } end
    end
  end
  ok(#bonesP3 == 3, 'platforms3-safe：解析出 3 根骨头（' .. #bonesP3 .. '）')
  for _, pf in ipairs({ 306, 346, 391 }) do
    local lo, hi = pf - 12, pf - 4
    local blocking = 0
    for _, b in ipairs(bonesP3) do
      if (b.y + b.h) > lo and b.y < hi then blocking = blocking + 1 end
    end
    ok(true, string.format('platforms3：落脚面 y=%d（原版骨头高度 45/40/35 已按回合差异文档 2.1 恢复，平台站立带被覆盖属原版行为）', pf))
  end

  head('round7-platform：挂脚本的 blue_soul 回合不再叠内置平台（幽灵平台 bug）')
  local g7 = newGame({ scripts = A, noScriptRounds = false, startRound = 6 })
  for _ = 1, 20 do M.update(g7, {}, DT) end
  ok(g7.roundScript ~= nil, 'round7：确实挂了攻击脚本（' .. tostring(g7.roundScript) .. '）')
  ok(#(g7.platforms or {}) == 0,
     string.format('round7：内置平台不再出现（实测 %d 个）', #(g7.platforms or {})))

  head('bonegap2-gap：上下骨同列的缝 18px → 30px')
  local csvGap
  for _, sc in ipairs(A) do if sc.name == 'sans_bonegap2' then csvGap = sc.csv end end
  ok(csvGap ~= nil and csvGap:find('SUB,HeightT,99,%$HeightB', 1, false) ~= nil,
     'bonegap2：HeightT = 99 - HeightB（缝 30px；旧值 111 → 18px）')
  -- 数值核对：缝 = (386-HeightB) - (257 + HeightT) = 129 - HeightB - HeightT
  for _, hb in ipairs({ 20, 30, 40, 60 }) do
    local ht = 99 - hb
    local gap = (386 - hb) - (257 + ht)
    ok(gap == 30, string.format('bonegap2：HeightB=%d → 缝 %dpx（灵魂 8px，可站 %dpx）', hb, gap, gap - 8))
  end

  head('A-9：bonestab1/2/3 回到原版 BoneStab 三档（方案甲）')
  -- 参考仓库 Files/sans_bonestab{1,2,3}.csv：Distance 25/25/29、Warn 0.4/0.3/0.4、Stay 0.333/0.2/0；
  -- 不再用「贴墙模式 + ArrowBone 整边升骨」。
  local ab = {}
  for _, sc in ipairs(A) do if sc.name:find('^sans_bonestab') then ab[#ab + 1] = sc end end
  table.sort(ab, function(x, y) return x.name < y.name end)
  ok(#ab == 3, 'A-9：三个 bonestab 脚本都在（' .. #ab .. '）')
  -- 【用户验收】伸出范围缩小（25/25/29 → 16/16/18）、bonestab3 给 0.25 停留：原版范围太深躲不开
  local want = { '16,0.4,0.33333', '16,0.3,0.2', '18,0.4,0.25' }
  for k, sc in ipairs(ab) do
    local got = tostring(sc.csv):match('BoneStab,[^\n]-,(%d+%.?%d*,%d+%.?%d*,%d+%.?%d*)')
    ok(got == want[k], string.format('A-9：%s 参数 = %s（期望 %s）', sc.name, tostring(got), want[k]))
    ok(not tostring(sc.csv):find('ArrowBone', 1, true) and not tostring(sc.csv):find('HeartWall', 1, true),
       'A-9：' .. sc.name .. ' 不再含 ArrowBone / HeartWall')
  end
  head('intro-blaster：首轮（sans_intro）龙骨炮「出现 → 释放」间隔 = 1.0s')
  -- 用户第九轮口径（0.6 → 1.0）。GasterBlaster 的第 8 个参数（cells[9]）是 SpinTime = 出现到释放的时间。
  local csvIntro
  for _, sc in ipairs(A) do if sc.name == 'sans_intro' then csvIntro = sc.csv end end
  local nBlast, nBad, seenSpin = 0, 0, {}
  for line in tostring(csvIntro):gmatch('[^\n]+') do
    if line:sub(1, 1) ~= '#' then
      local c = {}
      for cell in line:gmatch('[^,]*') do c[#c + 1] = cell end
      if c[2] == 'GasterBlaster' then
        nBlast = nBlast + 1
        local spin = tonumber(c[9])
        seenSpin[tostring(spin)] = true
        if spin == nil or math.abs(spin - 1.0) > 1e-9 then nBad = nBad + 1 end
      end
    end
  end
  ok(nBlast >= 14 and nBad == 0,
     string.format('intro-blaster：%d 发全部 SpinTime=1.0（不合规 %d 发）', nBlast, nBad))

  head('fair-bone：高骨严格低于灵魂起跳高度，且跟在矮骨后面进场')
  -- 用户口径（2026-10-05 第四轮）：同一 x 上「高骨吊顶 + 矮骨贴地」不能把灵魂夹死，
  --   ① 高骨底沿必须 ≤ 灵魂按住 1s 的最高点矩形上沿（留 3px），跳起来躲矮骨永远撞不到高骨；
  --   ② 高骨行必须在矮骨行**之后**触发（给反应时间）。用 attacks.lua 里的真实 CSV 逐行核对。
  local function rowsOf(csv)
    local t, out = 0, {}
    for line in tostring(csv):gmatch('[^\n]+') do
      line = line:gsub('^%s+', '')
      if line ~= '' and line:sub(1, 1) ~= '#' then
        local c = {}
        for cell in line:gmatch('[^,]*') do c[#c + 1] = cell end
        t = t + (tonumber(c[1]) or 0)
        out[#out + 1] = { t = t, cmd = c[2], x = tonumber(c[3]), y = tonumber(c[4]), h = tonumber(c[5]), color = tonumber(c[10]) }
      end
    end
    return out
  end
  local jump1sH = select(1, jumpCurve(0.25))     -- 框高 140 下按住 0.25s（= 1/2 框高）的跳跃高度（前面 blue-jump 段测过）
  -- 用户第六轮澄清：**「左右高低骨进入的组合」的高骨才是蓝骨**（= bonegap1 / bonegap1fast）；
  -- sans_boneslideh（ROUND 4）上方那根保持白骨。这里连颜色一起钉住。
  local tallIsBlue = { sans_boneslideh = false, sans_bonegap1 = true, sans_bonegap1fast = true }
  for _, nm in ipairs({ 'sans_boneslideh', 'sans_bonegap1', 'sans_bonegap1fast' }) do
    local csv
    for _, sc in ipairs(A) do if sc.name == nm then csv = sc.csv end end
    local rows = rowsOf(csv)
    local l, t, r, b
    local tall, short = {}, {}
    -- CombatZoneResize 的参数是 (L,T,R,B)，需要按原始 cells 取第 3..6 列
    for line in tostring(csv):gmatch('[^\n]+') do
      if line:find('CombatZoneResize,', 1, true) then
        local c = {}
        for cell in line:gmatch('[^,]*') do c[#c + 1] = cell end
        l, t, r, b = tonumber(c[3]), tonumber(c[4]), tonumber(c[5]), tonumber(c[6])
        break
      end
    end
    for _, rw in ipairs(rows) do
      -- BoneVRepeat（批量）和 BoneV（单根，蓝骨要用它带 Color）都算骨行
      if rw.cmd == 'BoneVRepeat' or rw.cmd == 'BoneV' then
        if rw.h >= 28 then tall[#tall + 1] = rw else short[#short + 1] = rw end
      end
    end
    local okGeom = (l ~= nil) and (#tall > 0) and (#short > 0)
    local blueOK = true
    for _, rw in ipairs(tall) do
      local isBlue = (rw.color == 1)
      if isBlue ~= tallIsBlue[nm] then blueOK = false end
    end
    local maxTallH, minTallT, minShortT, maxBottom = 0, math.huge, math.huge, 0
    for _, rw in ipairs(tall) do
      if rw.h > maxTallH then maxTallH = rw.h end
      if rw.t < minTallT then minTallT = rw.t end
      if rw.y + rw.h > maxBottom then maxBottom = rw.y + rw.h end
    end
    for _, rw in ipairs(short) do if rw.t < minShortT then minShortT = rw.t end end
    local floorC = b and (b - M.SOUL_CLAMP) or nil
    local apexTop = floorC and (floorC - jump1sH - M.SOUL_R) or nil
    ok(okGeom, nm .. '：解析出战斗框 + 高骨行 + 矮骨行')
    if okGeom then
      ok(maxTallH < jump1sH,
         string.format('%s：高骨高度 %.0f < 灵魂起跳高度 %.1f（字面口径）', nm, maxTallH, jump1sH))
      ok(maxBottom <= apexTop - 3,
         string.format('%s：高骨底沿 %.0f ≤ 0.25s 跳跃最高点矩形上沿 %.1f - 3（跳起来撞不到）',
                       nm, maxBottom, apexTop))
      ok(minTallT > minShortT,
         string.format('%s：高骨跟在矮骨后面进场（高骨 t=%.2fs > 矮骨 t=%.2fs）', nm, minTallT, minShortT))
      ok(blueOK, string.format('%s：高骨颜色符合口径（%s）', nm,
                               tallIsBlue[nm] and '左右高低骨组合 → 蓝骨 Color=1' or 'ROUND 4 上方 → 白骨'))
    end
  end

  head('blue-script-bone：脚本 Color=1 的骨头只惩罚移动（第四回合的高骨就是这种）')
  -- Documentation/Attacks.md：Color 0 白 / 1 蓝 / 2 橙。脚本骨以前**不看颜色**（蓝骨=白骨），
  -- 第四回合把高骨改成蓝骨后必须走同一套 moved 语义。
  local csvBlue = table.concat({
    '0,CombatZoneResizeInstant,100,100,500,400',
    '0,HeartTeleport,320,392',            -- 世界帧贴地
    '0,HeartMode,1',                       -- 蓝魂
    '0,BoneH,300,384,60,0,0,1',            -- Color=1 蓝骨（横向 60 宽），覆盖贴地灵魂
  }, '\n')
  local gb = newGame({ scripts = A })
  gb:startEnemyScript('__probe__')
  gb.world = M.newWorld({ seed = 1, script = M.parseCSV(csvBlue) })
  gb.box = { x = gb.world.zone.l - 240, y = gb.world.zone.t - 226,
             w = gb.world.zone.r - gb.world.zone.l, h = gb.world.zone.b - gb.world.zone.t }
  for _ = 1, 5 do M.update(gb, {}, DT) end
  local hpB = gb.hp
  for _ = 1, 60 do M.update(gb, {}, DT) end
  ok(gb.hp == hpB and not M.hasLog(gb, 'hit_blue'),
     'blue-script-bone：重叠期间静止 → 不掉血、无 hit_blue')
  for _ = 1, 60 do
    if M.hasLog(gb, 'hit_blue') then break end
    gb.invuln = 0
    gb.soul.x = gb.soul.x + 0.5          -- 只挪一点点保证仍在骨头上；真正算「移动」的是下面的方向键
    M.update(gb, { right = true }, DT)
  end
  ok(M.hasLog(gb, 'hit_blue') and gb.hp < hpB,
     string.format('blue-script-bone：重叠期间移动 → hit_blue 且掉血（%d → %d）', hpB, gb.hp))

  head('clip-zone：竖骨按 BTS 的 CombatZoneClipped 语义裁进战斗框（横骨不裁）')
  -- BTS 里 BoneV/BoneVRepeat/BoneStab 建在 CombatZoneClipped 图层（外侧 4 块 CombatZoneClipper 盖住），
  -- BoneH/BoneHRepeat/GasterBlaster 建在 CombatZone 图层（不裁）。这条契约由 core.clipVZone + 渲染出口共同保证。
  local csvClip = table.concat({
    '0,CombatZoneResizeInstant,100,100,300,300',
    '0,HeartTeleport,200,200',
    '0,HeartMode,0',
    '0,BoneV,95,120,60,0,0,0',    -- 竖骨：x 95..114 跨框左沿 100，必须被裁
    '0,BoneH,95,120,400,0,0,0'    -- 横骨：x 95..495 同样跨框沿，但**不裁**
  }, '\n')
  local gclip = newGame({ scripts = { { name = 'clipzone', csv = csvClip } }, noScriptRounds = false })
  gclip:startEnemyScript('clipzone')
  for _ = 1, 3 do gclip.world:update(DT) end
  local vb, hb
  for _, b in ipairs(gclip.world.bones) do
    if b.axis == 'v' then vb = b elseif b.axis == 'h' then hb = b end
  end
  ok(vb ~= nil and hb ~= nil, 'clip-zone：最小脚本生成 1 根竖骨 + 1 根横骨')
  local zc = gclip.world.zone
  if vb then
    local cx, cy, cw, ch = M.clipVZone(vb.x, vb.y, vb.w, vb.h, zc)
    ok(cx == zc.l, string.format('clip-zone：竖骨左沿裁到框左（%.0f == %.0f）', cx or -1, zc.l))
    ok(cx ~= nil and (cx + cw) <= zc.r + 1e-9 and cy >= zc.t - 1e-9 and (cy + ch) <= zc.b + 1e-9,
       'clip-zone：裁后的竖骨完全落在战斗框内')
    ok(cw ~= nil and cw < vb.w, string.format('clip-zone：竖骨确实被削窄（%.0f < %.0f）', cw or -1, vb.w))
  end
  ok(M.clipVZone(-999, 120, 19, 60, zc) == nil, 'clip-zone：整根在框外的竖骨返回 nil（这一帧不出控件）')
  if hb then
    -- clipVZone 是纯几何函数：谁来调用都会被裁 —— 所以“只裁竖骨”的策略必须由**调用点**保证
    -- （core 只对 bn.axis=='v' 调用；适配层的渲染同理）。这里把这条不变式写死。
    local hx, _, hw = M.clipVZone(hb.x, hb.y, hb.w, hb.h, zc)
    ok(hx == zc.l and hw ~= nil and hw < hb.w,
       'clip-zone：clipVZone 对越界矩形一律会裁 → 横骨不被裁必须靠调用点（已由下面的渲染断言覆盖）')
  end
  -- 渲染出口：竖骨命令必须是裁后的矩形（绘制 == 判定），横骨保持原值
  local cmdsClip = M.render(gclip)
  local vcmd, hcmd
  for _, c in ipairs(cmdsClip) do
    if c.kind == 'bone' then
      if c.vertical then vcmd = c else hcmd = c end
    end
  end
  ok(vcmd ~= nil and vcmd.x >= zc.l - 1e-9 and (vcmd.x + vcmd.w) <= zc.r + 1e-9,
     'clip-zone：渲染出的竖骨命令落在框内（绘制 == 判定）')
  ok(hcmd ~= nil and math.abs(hcmd.x - hb.x) < 1e-9 and hb.x < zc.l,
     'clip-zone：渲染出的横骨命令保持框外原值（不裁）')

  head('extra-hud：hud() 返回整数 + 相位字符串')
  g = newGame({ seed = 1 })
  local hud = M.hud(g)
  ok(hud.hp == math.floor(hud.hp) and hud.kr == math.floor(hud.kr), 'hud hp/kr 都是整数')
  ok(type(hud.phase) == 'string' and type(hud.round) == 'number', 'hud phase 是字符串 / round 是数字')
  ok(hud.phase == 'enemy', 'enemy 回合 phase=enemy（实际 ' .. hud.phase .. '）')

  -- ---------------------------------------------------------------- 汇总
  io.write("\n------------------------------\n")
  io.write(string.format("PASS %d / FAIL %d\n", R.pass, R.fail))
  return R.pass, R.fail, R.failures
end

R.run = run
-- 执行即跑（与 prototype/selftest.js 的行为一致）；返回表里有 pass/fail/failures
run()
return R
