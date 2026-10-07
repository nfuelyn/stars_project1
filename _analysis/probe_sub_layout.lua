-- 只读探针：打印 行动/道具/仁慈 三个子面板的几何（不改工作区）
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local function openSub(kind, idx)
  local g = M.newGame({ scripts = A, noSpawn = true, hp = 92 })
  g.state = 'menu'; g.menuIndex = idx
  M.menuChoose(g, idx)
  return g
end
local map = { { 'act', 1 }, { 'item', 2 }, { 'mercy', 3 } }
for _, e in ipairs(map) do
  local kind, idx = e[1], e[2]
  local g = openSub(kind, idx)
  local rows = g:subRows()
  for _, c in ipairs(M.render(g)) do
    if c.kind == 'sub' then
      local nameL, nameW = c.x + 28, c.w - 120          -- drawSub 里的名字框
      local noteR, noteW = c.x + c.w - 20, 90            -- 备注框（右对齐）
      print(string.format('【%s】sub=%s 行数=%d', kind, tostring(g.sub), #rows))
      print(string.format('  面板 x=%.0f y=%.0f w=%.0f h=%.0f  rowH=%.0f  字号=%d',
        c.x, c.y, c.w, c.h, c.rowH, math.min(18, math.max(12, c.rowH - 2))))
      print(string.format('  名字框 x=%.0f..%.0f (宽 %.0f)   备注框 x=%.0f..%.0f (宽 %d)   重叠带=%.0fpx',
        nameL, nameL + nameW, nameW, noteR - noteW, noteR, noteW, math.max(0, (nameL + nameW) - (noteR - noteW))))
      for i, r in ipairs(rows) do
        print(string.format('    行%d: 名字="%s"(%d字)  备注="%s"  说明="%s"',
          i, r, utf8len(r), tostring(g:subRowNote(i - 1)), tostring(g:subDesc()):sub(1, 0) .. (i == 1 and g:subDesc() or '')))
      end
      local bottom = c.y + 34 + #rows * c.rowH
      print(string.format('  行底=%.0f  面板底=%.0f  说明行 y=%.0f  溢出=%.0f',
        bottom, c.y + c.h, c.y + c.h - 28, math.max(0, bottom - (c.y + c.h))))
      print('')
      break
    end
  end
end
