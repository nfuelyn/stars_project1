-- _sine.lua —— 打印 core 发出的 sine 命令真实字段（本地 fengari，不经过模拟器）
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local core = require('lua' .. '.core')
local atk = require('lua' .. '.attacks')

local g = core.newGame({ difficulty = 'normal', scripts = atk, hp = 92 })
local shown = 0
for i = 1, 240 do
  core.update(g, {}, core.DT)
  local cmds = core.render(g)
  for _, c in ipairs(cmds) do
    if c.kind == 'sine' and shown < 3 then
      shown = shown + 1
      print(string.format('t=%.2f state=%s box=(%.0f,%.0f,%.0f,%.0f)',
        i * core.DT, tostring(g.state), g.box.x, g.box.y, g.box.w, g.box.h))
      print(string.format('  sine x=%.1f y=%.1f w=%.1f h=%.1f centerY=%s gap=%s amp=%s',
        c.x, c.y, c.w, c.h, tostring(c.centerY), tostring(c.gap), tostring(c.amp)))
      -- 适配层的自校正：centerY 落在框外、回退 BOX_OFF_Y 后落回框内 → 用回退值
      local bx, by, bh
      for _, q in ipairs(cmds) do
        if q.kind == 'box' then bx, by, bh = q.x, q.y, q.h end
      end
      local cy = c.centerY
      local dy = 0
      if bx and cy and (cy < by - 1 or cy > by + bh + 1) then
        local cy1 = cy - 226
        if cy1 >= by - 1 and cy1 <= by + bh + 1 then dy = -226 end
      end
      print(string.format('  box=(%.0f,%.0f,%.0f,%.0f) → 适配层 cy=%.1f dy=%d  上骨高=%.1f 下骨高=%.1f',
        bx or -1, by or -1, 0, bh or -1, (cy or 0) + dy, dy,
        ((cy or 0) + dy - (c.gap or 25) / 2) - (by or 0),
        ((by or 0) + (bh or 0)) - ((cy or 0) + dy + (c.gap or 25) / 2)))
      local b = c.bars or {}
      for j = 1, 2 do
        local q = b[j]
        if q then
          print(string.format('  bar%d = (%.1f, %.1f) %sx%s', j, q.x, q.y, tostring(q.w), tostring(q.h)))
        else
          print('  bar' .. j .. ' = nil')
        end
      end
      break
    end
  end
  if shown >= 3 then break end
end

-- 顺便确认 box 契约：整轮里所有 box 命令都落在 0..640 / 0..480 内
local bad = 0
local g2 = core.newGame({ difficulty = 'normal', scripts = atk, hp = 92 })
for i = 1, 1200 do
  core.update(g2, {}, core.DT)
  for _, c in ipairs(core.render(g2)) do
    if c.kind == 'box' then
      if c.x < 0 or c.y < 0 or c.x + c.w > 640.5 or c.y + c.h > 480.5 then
        bad = bad + 1
        if bad <= 3 then
          print(string.format('  box 越界 t=%.2f (%.0f,%.0f,%.0f,%.0f)', i * core.DT, c.x, c.y, c.w, c.h))
        end
      end
    end
  end
end
print('1200 帧内 box 越界次数 = ' .. bad)
