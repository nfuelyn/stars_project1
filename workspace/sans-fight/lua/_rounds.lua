-- _rounds.lua —— 20 回合结构 / 随机抽模板 / 螺旋档 / 回合结束清场 的回归测试
--   node tools/run-lua.mjs lua/_rounds.lua
-- 期望：全部 PASS（0 FAIL）。任何一条挂了都说明回合调度或清场逻辑回归。
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local core = require('lua' .. '.core')
local atk = require('lua' .. '.attacks')

local pass, fail = 0, 0
local function ck(cond, name, extra)
  if cond then pass = pass + 1; print('PASS ' .. name)
  else fail = fail + 1; print('FAIL ' .. name .. (extra and ('  ' .. tostring(extra)) or '')) end
end
local IDLE = { left = false, right = false, up = false, down = false, confirm = false, cancel = false }

-- ---------------------------------------------------------------- 1. 常量与规划
ck(core.TOTAL_ROUNDS == 24, '总回合数 = 24（差距文档 §1：23 个攻击回合 + 终盘）')
ck(core.LAST_ROUND == 23, '最后一回合内部号 = 23（原作 ≥23 = sans_final）')
ck(core.SPIRAL_FROM == 17, '螺旋档从内部号 17 开始')
ck(core.INTERLUDE_ROUND == 13, '中场落在内部号 13（= 原作 HitAttempts==13 的 sans_spare）')
ck(#core.SPIRAL_SCRIPTS == 3, '螺旋档 3 个脚本')

-- 抽签函数：0 固定见面杀，17/18/19 固定螺旋，其余必须落在对应档位的模板集合里
do
  local g = core.newGame({ difficulty = 'normal', scripts = atk })
  ck(core.scriptForRound(g, 0) == 'sans_intro', '回合 0 = 见面杀 sans_intro（固定）')
  ck(core.scriptForRound(g, 17) == 'sans_bonestab1', '回合 17 = sans_bonestab1（固定表）')
  ck(core.scriptForRound(g, 18) == 'sans_bonestab2', '回合 18 = sans_bonestab2（固定表）')
  ck(core.scriptForRound(g, 19) == 'randomblaster2', '回合 19 = randomblaster2（固定表）')
  -- 【P-02】已改为原作固定编排：只要每个脚本都能在 attacks.lua 里找到即可
  local names = {}
  for _, sc in ipairs(atk) do names[sc.name] = true end
  local bad = nil
  for n = 0, 22 do
    local s = core.scriptForRound(g, n)
    if not s or not names[s] then bad = n .. ':' .. tostring(s) end
  end
  ck(bad == nil, '固定序列表里的脚本都能在 attacks.lua 找到（原版即固定编排）', bad)
  -- 见面杀与螺旋档不参与抽签：随机回合里不允许出现它们
  local leaked = false
  for n = 1, 16 do
    for _ = 1, 50 do
      local s = core.scriptForRound(g, n)
      if s == 'sans_intro' or s == 'spiral1' or s == 'spiral2' or s == 'spiral3' then leaked = true end
    end
  end
  ck(not leaked, '随机回合不会抽到见面杀/螺旋脚本')
end

-- ---------------------------------------------------------------- 2. 走完整场 20 回合
-- 不走真实弹幕时间（每回合直接 endEnemy），只验证**状态机推进**：
-- 回合号必须一路走到 19，然后最后一回合打完给结局，绝不允许停在 6。
local function walk(seedDiff)
  local g = core.newGame({ difficulty = seedDiff, scripts = atk, hp = 100000 })
  local seq, guard = {}, 0
  while guard < 600 do
    guard = guard + 1
    if g.state == 'enemy' then
      seq[#seq + 1] = { round = g.round, script = g.roundScript }
      g:endEnemy()
    elseif g.state == 'menu' then
      g:menuChoose(0)                          -- 选「攻击」
    elseif g.state == 'sub' then
      g:subBack()
    elseif g.state == 'attack' then
      g:stopAttack()
      for _ = 1, 200 do
        core.update(g, IDLE, core.DT)
        if g.state ~= 'attack' then break end
      end
    elseif g.state == 'result' then
      return seq, g.result, g
    else
      core.update(g, IDLE, core.DT)
    end
  end
  return seq, 'stuck', g
end

for _, diff in ipairs({ 'easy', 'normal', 'hard', 'original' }) do
  local seq, result = walk(diff)
  local rounds, scripts = {}, {}
  for _, s in ipairs(seq) do rounds[#rounds + 1] = s.round; scripts[#scripts + 1] = s.script end
  ck(#seq == 24, diff .. '：整场正好 24 回合', '#seq=' .. #seq)
  ck(rounds[1] == 0 and rounds[#rounds] == 23, diff .. '：回合号 0 → 23 全程走完',
    table.concat(rounds, ','))
  ck(scripts[1] == 'sans_intro', diff .. '：第 1 回合是见面杀')
  ck(#scripts == 24, diff .. '：整场 24 回合（固定序列表）', table.concat(scripts, ','))
  local dup = nil
  for i = 2, #scripts do if scripts[i] == scripts[i - 1] then dup = i .. ':' .. scripts[i] end end
  ck(dup == nil, diff .. '：相邻两回合不重复同一个脚本', dup)
  ck(result == 'kill' or result == 'spare', diff .. '：走完最后一回合能到结局（不是卡住）',
    tostring(result))
end

-- ---------------------------------------------------------------- 3. 抽签可复现（固定 seed）
do
  local function drawSeq()
    local g = core.newGame({ difficulty = 'normal', scripts = atk })
    local out = {}
    for n = 1, 16 do out[#out + 1] = core.scriptForRound(g, n) end
    return table.concat(out, ',')
  end
  ck(drawSeq() == drawSeq(), '同一 seed 下抽签序列可复现')
end

-- ---------------------------------------------------------------- 4. 回合结束必须清场
do
  local g = core.newGame({ difficulty = 'normal', scripts = atk, hp = 100000 })
  local cleared, leftovers = true, nil
  for n = 0, 19 do
    g:startEnemy(n)
    for _ = 1, 240 do core.update(g, IDLE, core.DT) end   -- 跑 4 秒，让实体生成出来
    local before = #(g.walls or {}) + #(g.platforms or {}) + #(g.sine or {})
    if g.world then before = before + #g.world.bones + #g.world.blasters + #g.world.sine end
    g:endEnemy()
    local after = #(g.walls or {}) + #(g.platforms or {}) + #(g.sine or {})
    if g.world then after = after + #g.world.bones + #g.world.blasters + #g.world.sine end
    -- 渲染层面：菜单态不允许再出现任何场地实体命令
    local kinds = {}
    for _, c in ipairs(core.render(g)) do
      if c.kind == 'bone' or c.kind == 'blaster' or c.kind == 'wall'
         or c.kind == 'platform' or c.kind == 'sine' or c.kind == 'stab' then
        kinds[c.kind] = (kinds[c.kind] or 0) + 1
      end
    end
    local n2 = 0
    for _, v in pairs(kinds) do n2 = n2 + v end
    if after ~= 0 or n2 ~= 0 then
      cleared = false
      leftovers = string.format('round=%d 清场后实体=%d 菜单态仍渲染=%d', n, after, n2)
      break
    end
    -- 顺带记录：这一回合确实生成了东西（否则"清场"是空验证）
    if before == 0 and n > 0 then leftovers = 'round=' .. n .. ' 这一回合没有任何实体生成（测试无效）' end
  end
  ck(cleared, '每回合结束时场地实体全部清空，且菜单态不再渲染它们', leftovers)
end

-- ---------------------------------------------------------------- 5. 清场后状态字段干净
do
  local g = core.newGame({ difficulty = 'normal', scripts = atk, hp = 100000 })
  g:startEnemy(0)
  for _ = 1, 120 do core.update(g, IDLE, core.DT) end
  g:endEnemy()
  ck(g.world == nil, 'endEnemy 后 world = nil')
  ck(type(g.walls) == 'table' and #g.walls == 0, 'endEnemy 后 walls = {}')
  ck(type(g.platforms) == 'table' and #g.platforms == 0, 'endEnemy 后 platforms = {}（不是 nil）')
  ck(next(g.wavesAlive) == nil, 'endEnemy 后 wavesAlive = {}')
  ck(g.whiteT == nil and g.floorLock == 0, 'endEnemy 后 whiteT/floorLock 归零')
end

-- ---------------------------------------------------------------- 6. HUD 回合显示
do
  local g = core.newGame({ difficulty = 'normal', scripts = atk, hp = 100000 })
  g:startEnemy(0)
  local txt = nil
  for _, c in ipairs(core.render(g)) do
    if c.kind == 'hudText' and type(c.text) == 'string' and c.text:find('ROUND') then txt = c.text end
  end
  ck(txt == 'ROUND 1 / 24', 'HUD 显示 ROUND 1 / 24（见面杀 = 第 1 回合）', tostring(txt))
  g:startEnemy(23)
  for _, c in ipairs(core.render(g)) do
    if c.kind == 'hudText' and type(c.text) == 'string' and c.text:find('ROUND') then txt = c.text end
  end
  ck(txt == 'ROUND 24 / 24', 'HUD 显示 ROUND 24 / 24（内部号 23 + 1）', tostring(txt))
end

-- ---------------------------------------------------------------- 7. sans 渲染命令
do
  local g = core.newGame({ difficulty = 'normal', scripts = atk, hp = 100000 })
  g:startEnemy(0)
  local s = nil
  for _, c in ipairs(core.render(g)) do if c.kind == 'sans' then s = c end end
  ck(s ~= nil, '战斗态输出 kind=sans 命令')
  local boxTop = g.box.y + core.BOX_OFF_Y
  ck(s and s.x == 320 and s.y == boxTop - 16 - core.SANS_H, 'sans 站位 = (320, 站在框上方 16px)',
    s and (s.x .. ',' .. s.y))
  ck(s and type(s.head) == 'string', 'sans 带 head 状态字段', s and tostring(s.head))
  -- 菜单态也要有站姿
  g:endEnemy()
  local s2 = nil
  for _, c in ipairs(core.render(g)) do if c.kind == 'sans' then s2 = c end end
  ck(s2 ~= nil and s2.body == nil, '菜单态 sans 仍在场且回到默认姿势（body=nil）',
    s2 and tostring(s2.body))
  -- 标题/结局态不画他
  g.state = 'title'
  local any = false
  for _, c in ipairs(core.render(g)) do if c.kind == 'sans' then any = true end end
  ck(not any, '标题页不画 sans')
end

-- ---------------------------------------------------------------- 8. 螺旋档 = 原版阶段④（逐字）
-- 用户验收要求「最后几回合和原版一样使用高强度螺旋龙骨炮」——这里把"一样"钉成可验证的断言：
-- spiral3 的旋转光束几何必须与原版 sans_final.csv 阶段④（final 脚本第 140..152 行）逐字相同。
do
  local function codeOf(name)
    for _, s in ipairs(atk) do
      if s.name == name then
        local out = {}
        for line in tostring(s.csv):gmatch('[^\n]+') do
          local t = line:match('^%s*(.-)%s*$')
          if t ~= '' and t:sub(1, 1) ~= '#' then out[#out + 1] = t end
        end
        return out
      end
    end
  end
  local fin, sp3 = codeOf('final'), codeOf('spiral3')
  ck(fin ~= nil and sp3 ~= nil, 'final 与 spiral3 都在 attacks.lua 里')
  local missing = nil
  for i = 140, 152 do                       -- MUL Ang … GasterBlaster（13 行几何）
    local g = fin[i]
    local found = false
    -- spiral3 这一行末尾多了本项目的扩展参数（HoldTime / ExtraWidth），比对时剥掉
    for _, l0 in ipairs(sp3) do
      local l = l0:gsub(',0,5$', '')
      if l == g then found = true break end
    end
    if not found then missing = i .. ': ' .. tostring(g) end
  end
  ck(missing == nil, 'spiral3 的 13 行旋转光束几何与原版阶段④逐字一致', missing)
  local joined = table.concat(sp3, '\n')
  ck(joined:find('GasterBlaster,0,$X,$Y,$EndX,$EndY,$Ang,0.5,0', 1, true) ~= nil,
    'spiral3 每发参数 = Size0 / SpinTime 0.5 / BlastTime 0（原作值）')
  ck(joined:find('$gin,1.7', 1, true) ~= nil and joined:find('$gt,190', 1, true) ~= nil,
    'spiral3 强度上限 = gin 1.7 / gt 190（原作值）')
  -- 三档必须真的递增（轻 → 中 → 强），否则"最后几回合越来越狠"就是空话
  local function limitOf(name, pat)
    for _, s in ipairs(atk) do
      if s.name == name then return tonumber(tostring(s.csv):match(pat)) end
    end
  end
  local g1 = limitOf('spiral1', 'JMPL,Loop,%$gt,(%d+)')
  local g2 = limitOf('spiral2', 'JMPL,Loop,%$gt,(%d+)')
  local g3 = limitOf('spiral3', 'JMPL,Loop,%$gt,(%d+)')
  ck(g1 and g2 and g3 and g1 < g2 and g2 < g3,
    string.format('三档强度递增 gt: %s < %s < %s', tostring(g1), tostring(g2), tostring(g3)))
end

-- ---------------------------------------------------------------- 全流程龙骨炮烘焙
-- 用户口径（2026-10-06）：见面杀之后的所有龙骨炮与见面杀同款 = fitdata.blaster_block2 像素烘焙。
-- 有两条产出路径，两条都要查：
--   ① 脚本 CMD.GasterBlaster（见面杀 / multi2 / randomblaster / 终盘阶段④ …）
--   ② 内置 blaster 模式的 Game:spawnBlaster —— 它绕过 CMD 直接 push，
--      历史上就是这里漏了 bake，才会在第 5 回合（platforms1）混进旧的 12 件参数化骷髅。
do
  local probes = {
    { 0,  "见面杀（脚本路径）" },
    { 4,  "platforms1 内置 blaster 模式（spawnBlaster 路径）" },
    { 16, "multi2 四发同屏（脚本路径）" },
  }
  local total, baked, firstBad = 0, 0, nil
  for _, pr in ipairs(probes) do
    local n = pr[1]
    local g = core.newGame({ scripts = atk, hp = 1000000, difficulty = "original" })
    g:startEnemy(n)
    local t, roundN = 0, 0
    while g.state == "enemy" and t < 120 do
      core.update(g, IDLE, core.DT); t = t + core.DT
      for _, c in ipairs(core.render(g)) do
        if c.kind == "blaster" then
          total = total + 1; roundN = roundN + 1
          if c.bake then baked = baked + 1
          elseif not firstBad then
            firstBad = string.format("round %d (%s) script=%s", n, pr[2], tostring(g.roundScript))
          end
        end
      end
    end
    ck(roundN > 0, string.format("回合 %d 确实会产生龙骨炮命令（%s）", n, pr[2]), "n=" .. roundN)
  end
  ck(firstBad == nil, "全流程龙骨炮 100% 走 fitdata.blaster_block2 烘焙（bake=true）",
    firstBad and (firstBad .. " —— 未烘焙 " .. (total - baked) .. "/" .. total) or nil)
end


-- ---------------------------------------------------------------- 终盘旋转龙骨炮：红心复位
-- 用户口径（2026-10-07）：旋转龙骨炮阶段必须是红心模式。
-- 这里不只看脚本里有没有 HeartMode 0，而是跑到第一发 persistent 光束出现时，
-- 同时核对逻辑态与 render 出来的 soul command，防止“逻辑红、画面/运动仍像蓝”的回归。
do
  local g = core.newGame({ scripts = atk, hp = 1000000, difficulty = "original" })
  g:startEnemy(23)
  local t, seen, persistentCount, modeAtStart, renderMode = 0, false, 0, nil, nil
  while g.state == "enemy" and t < 45 do
    core.update(g, IDLE, core.DT); t = t + core.DT
    persistentCount = 0
    if g.world then
      for _, b in ipairs(g.world.blasters) do
        if b.persistent then persistentCount = persistentCount + 1 end
      end
    end
    if persistentCount > 0 then
      seen = true
      modeAtStart = g.soul.mode
      for _, c in ipairs(core.render(g)) do
        if c.kind == "soul" then renderMode = c.mode end
      end
      break
    end
  end
  ck(seen, "终盘确实进入旋转龙骨炮阶段", string.format("t=%.2fs persistent=%d", t, persistentCount))
  ck(modeAtStart == "red", "旋转龙骨炮阶段 soul.mode = red", tostring(modeAtStart))
  ck(renderMode == "red", "旋转龙骨炮阶段 render(soul).mode = red", tostring(renderMode))
end


-- ---------------------------------------------------------------- 初见杀四发组合：3×3 LOD
do
  local g = core.newGame({ scripts = atk, hp = 1000000, difficulty = "original" })
  g:startEnemy(0)
  local t, sawSize1, sawSize2, badSize1 = 0, false, false, nil
  while g.state == "enemy" and t < 15 do
    core.update(g, IDLE, core.DT); t = t + core.DT
    for _, c in ipairs(core.render(g)) do
      if c.kind == "blaster" then
        if c.size == 1 then
          if c.lod == "block3" then sawSize1 = true else badSize1 = c.lod or "nil" end
        elseif c.size == 2 and c.lod == nil then
          sawSize2 = true
        end
      end
    end
  end
  ck(sawSize1 and badSize1 == nil, "初见杀四发组合（Size1）全部走 3×3", tostring(badSize1))
  ck(sawSize2, "初见杀最后两发 Size2 仍保持 2×2")
end


-- ---------------------------------------------------------------- 骨攻微调文档（2026-10-07）
do
  local function codeOf(name)
    for _, sc in ipairs(atk) do
      if sc.name == name then
        local out = {}
        for line in tostring(sc.csv):gmatch('[^\n]+') do
          if line:sub(1, 1) ~= '#' then out[#out + 1] = line end
        end
        return table.concat(out, '\n')
      end
    end
    return ''
  end
  local checks = {
    { 'sans_bonegap1',     'BoneVRepeat,128,257,58,0,180,8,120,1', 'HUD2 左上骨厚度 32→58' },
    { 'sans_bonegap1',     'BoneVRepeat,503,257,58,2,180,8,120,1', 'HUD2 右上骨厚度 32→58' },
    { 'sans_bonegap1fast', 'BoneVRepeat,128,257,58,0,210,8,133,1', 'HUD11 左上骨厚度 32→58' },
    { 'sans_bonegap1fast', 'BoneVRepeat,503,257,58,2,210,8,133,1', 'HUD11 右上骨厚度 32→58' },
    { 'sans_boneslideh',   'BoneVRepeat,513,257,58,2,120,8,76',    'HUD12 上骨厚度 32→58' },
    { 'sans_bonegap2',     'SUB,HeightT,111,$HeightB',             'HUD4/13 上骨（高骨）抬起 7px → 缝 18px（=HUD15）' },
    { 'multi3',            'BoneVRepeat,121,354,37,2,0,20,20',     'HUD22 底边骨带 10×40→20×20' },
    { 'final',             'BoneStab,0,38.4,1.9,1',                'HUD24 阶段③右框骨刺 厚度48→38.4、预警1.4→1.9（方案A）' },
    { 'final',             'BoneStab,1,38.4,1.9,1',                'HUD24 阶段③下框骨刺 厚度48→38.4、预警1.4→1.9（方案A）' },
    { 'final',             'BoneStab,2,38.4,1.1,1',                'HUD24 阶段③单发骨刺 厚度48→38.4、预警0.6→1.1（方案A）' },
  }
  for _, t in ipairs(checks) do
    ck(codeOf(t[1]):find(t[2], 1, true) ~= nil, t[3], t[2])
  end
  ck(codeOf('final'):find('BoneStab,$Direction,23.2,1.0,0', 1, true) ~= nil,
     'HUD24 开场骨刺：厚度 29→23.2、预警 0.4→1.0')
end

print(string.format('---- _rounds.lua: %d PASS / %d FAIL ----', pass, fail))
if fail > 0 then os.exit(1) end
