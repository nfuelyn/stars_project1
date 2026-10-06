-- _box.lua —— 逐帧记录战斗框命令，找出「到处移动」的来源
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local core = require('lua' .. '.core')
local atk = require('lua' .. '.attacks')

local g = core.newGame({ difficulty = 'normal', scripts = atk, hp = 92 })
local last, jumps, samples = nil, 0, 0
local t0 = os and os.clock and os.clock() or 0
for i = 1, 1800 do
  -- 每 0.5s 按一次确认：让流程能走过菜单（否则会一直停在菜单）
  local input = {}
  if i % 15 == 0 then input.confirm = true end
  core.update(g, input, core.DT)
  local cmds = core.render(g)
  for _, c in ipairs(cmds) do
    if c.kind == 'box' then
      local key = string.format('%.1f,%.1f,%.1f,%.1f', c.x, c.y, c.w, c.h)
      if key ~= last then
        if last then
          jumps = jumps + 1
          if jumps <= 40 then
            print(string.format('t=%6.2f %-7s box=(%s)   ← 变化 #%d', i * core.DT, tostring(g.state), key, jumps))
          end
        else
          print(string.format('t=%6.2f %-7s box=(%s)   ← 初值', i * core.DT, tostring(g.state), key))
        end
        last = key
      end
      samples = samples + 1
    end
  end
  if g.state == 'result' then break end
end
print(string.format('共 %d 帧带 box 命令，box 变化 %d 次', samples, jumps))
