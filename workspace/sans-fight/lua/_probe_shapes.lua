package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local core = require('lua' .. '.core')
local atk  = require('lua' .. '.attacks')
local DT = core.DT
local IDLE = { left=false,right=false,up=false,down=false,confirm=false,cancel=false }

local function dump(n, secs, label)
  local g = core.newGame({ scripts = atk, hp = 1000000, difficulty = 'original' })
  g:startEnemy(n)
  print(string.format('=== %s : 内部 %d / HUD %d / 脚本 %s ===', label, n, n+1, tostring(g.roundScript)))
  local shapes, t = {}, 0
  while g.state == 'enemy' and t < secs do
    core.update(g, IDLE, DT); t = t + DT
    local cmds = core.render(g)
    for _, k in ipairs(cmds) do
      if k.kind == 'bone' then
        local key = string.format('bone vertical=%s w=%d h=%d', tostring(k.vertical), math.floor(k.w+0.5), math.floor(k.h+0.5))
        shapes[key] = (shapes[key] or 0) + 1
      elseif k.kind == 'stab' then
        local key = string.format('stab dir=%s phase=%s w=%d h=%d', tostring(k.dir), tostring(k.phase), math.floor(k.w+0.5), math.floor(k.h+0.5))
        shapes[key] = (shapes[key] or 0) + 1
      end
    end
  end
  local keys = {}
  for k in pairs(shapes) do keys[#keys+1] = k end
  table.sort(keys)
  -- 只显示出现次数最多的 16 条
  local shown = 0
  for _, k in ipairs(keys) do
    shown = shown + 1
    if shown <= 16 then print(string.format('   %-52s x%d', k, shapes[k])) end
  end
  print(string.format('   (distinct=%d, 帧数=%d)', #keys, math.floor(t/DT)))
  print('')
end

dump(14, 12, '14 轮（内部 14 = multi1）')
dump(21, 12, '22 轮（HUD 22 = 内部 21 = multi3）')
