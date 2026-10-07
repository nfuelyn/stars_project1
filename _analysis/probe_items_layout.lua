-- 探针：item 面板在「面包 + 原版 4 件」= 5 行时能否排下（不改工作区）
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local g = M.newGame({ scripts = A, noSpawn = true, hp = 92 })
g.items = {
  { id = 'legend_bread', name = '传奇面包',   desc = '回复 45 HP', heal = 45, count = 20 },
  { id = 'pie',          name = '奶油糖派',   desc = '回复 99 HP', heal = 99, count = 1 },
  { id = 'noodles',      name = '速食泡面',   desc = '回复 90 HP', heal = 90, count = 1 },
  { id = 'steak',        name = '脸排',       desc = '回复 60 HP', heal = 60, count = 1 },
  { id = 'lhero',        name = '传说英雄',   desc = '回复 40 HP', heal = 40, count = 1 },
}
g.state = 'menu'; g.menuIndex = 2
M.menuChoose(g, 2)
print('state=' .. tostring(g.state) .. ' sub=' .. tostring(g.sub) .. ' rows=' .. #g:subRows())
for _, c in ipairs(M.render(g)) do
  if c.kind == 'sub' then
    local rowsBottom = c.y + 34 + #c.rows * c.rowH
    print(string.format('面板 y=%.0f h=%.0f  rowH=%.0f  行数=%d  行底=%.0f  面板底=%.0f  溢出=%.0f',
      c.y, c.h, c.rowH, #c.rows, rowsBottom, c.y + c.h, math.max(0, rowsBottom - (c.y + c.h))))
    print('说明行 y = ' .. string.format('%.0f', c.y + c.h - 28))
  end
end
-- 顺手验证吃「奶油糖派」：HP 92→? 与面包是否仍 +45
local g2 = M.newGame({ scripts = A, noSpawn = true, hp = 92 })
g2.items = g.items; g2.hp = 10
g2.state = 'menu'; g2.menuIndex = 2; M.menuChoose(g2, 2)
M.subMove(g2, 1)      -- 选到第 2 件（奶油糖派）
M.subConfirm(g2)
print(string.format('吃奶油糖派：hp 10 → %d（期望 92 上限钳制）；剩余总数 %d', g2.hp, g2:itemCount()))
