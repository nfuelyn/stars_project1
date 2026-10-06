-- _check.lua —— 本地 fengari 语法 + 接口 + 长时运行检查（用 tools/run-lua.mjs 跑）
-- 注意：模块名动态拼接，避免被 run-lua.mjs 的 require 路径重写规则改写。
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path

local mods = {}
for _, name in ipairs({ 'lua' .. '.core', 'lua' .. '.attacks', 'lua' .. '.main' }) do
  local ok, mod = pcall(require, name)
  if ok and type(mod) == 'table' then
    mods[name] = mod
    local n = 0
    for _ in pairs(mod) do n = n + 1 end
    print(string.format('OK   %-12s keys=%d', name, n))
  else
    print(string.format('FAIL %-12s %s', name, tostring(mod)))
  end
end

local core = mods['lua' .. '.core']
local atk = mods['lua' .. '.attacks']
local main = mods['lua' .. '.main']
if not core then print('ABORT: core 未加载'); return end

print('main: ' .. table.concat({ 'OnInit=' .. type(main and main.OnInit), 'OnStart=' .. type(main and main.OnStart),
  'OnLevelUpdate=' .. type(main and main.OnLevelUpdate) }, ' '))
print('cmdCount=' .. tostring(core.cmdCount) .. ' jumpCount=' .. tostring(core.jumpCount)
  .. ' rounds=' .. tostring(core.ROUNDS and #core.ROUNDS or 'nil') .. ' attacks=' .. tostring(#(atk or {})))

local DIFFS = { 'easy', 'normal', 'hard', 'original' }
for _, diff in ipairs(DIFFS) do
  local hist, frames, errs = {}, 0, {}
  local ok, err = pcall(function()
    local g = core.newGame({ difficulty = diff, scripts = atk, hp = 92 })
    local rngState = 12345
    local function rnd()
      rngState = (rngState * 1103515245 + 12345) % 2147483648
      return rngState / 2147483648
    end
    local dx, dy = 0, 0
    for i = 1, 900 do
      if i % 12 == 0 then
        local r = rnd()
        dx, dy = 0, 0
        if r < 0.25 then dx = -1 elseif r < 0.5 then dx = 1 elseif r < 0.75 then dy = -1 else dy = 1 end
      end
      local input = { left = dx < 0, right = dx > 0, up = dy < 0, down = dy > 0,
                      confirm = (i % 90 == 0), cancel = false }
      core.update(g, input, core.DT)
      local cmds = core.render(g)
      for _, c in ipairs(cmds) do hist[c.kind] = (hist[c.kind] or 0) + 1 end
      frames = i
      if g.state == 'result' then break end
    end
    local d = core.debug(g)
    local hud = core.hud(g)
    print(string.format('  %-9s frames=%d state=%s round=%s hp=%s kr=%s phase=%s script=%s bones=%s sine=%s blast=%s plat=%s wall=%s',
      diff, frames, tostring(d.state), tostring(d.round), tostring(d.hp), tostring(hud.kr), tostring(hud.phase),
      tostring(d.script), tostring(d.bones), tostring(d.sine), tostring(d.blasters), tostring(d.platforms), tostring(d.walls)))
  end)
  if not ok then
    print('  ' .. diff .. ' RUN FAIL ' .. tostring(err))
  else
    local parts = {}
    for k, v in pairs(hist) do parts[#parts + 1] = k .. ':' .. v end
    table.sort(parts)
    print('  ' .. diff .. ' kinds ' .. table.concat(parts, ' '))
  end
end

-- 手动跑到后续回合，确认攻击脚本轮转（等 60s 游戏时间）
local ok2, err2 = pcall(function()
  local g = core.newGame({ difficulty = 'normal', scripts = atk, hp = 92 })
  local seen = {}
  for i = 1, 1800 do
    core.update(g, { confirm = (i % 45 == 0) }, core.DT)
    local d = core.debug(g)
    if d.script then seen[d.script] = true end
    if g.state == 'result' then break end
  end
  local names = {}
  for k in pairs(seen) do names[#names + 1] = k end
  table.sort(names)
  print('60s 内出现过的攻击脚本(' .. #names .. ')：' .. table.concat(names, ', '))
end)
if not ok2 then print('LONG RUN FAIL ' .. tostring(err2)) end
