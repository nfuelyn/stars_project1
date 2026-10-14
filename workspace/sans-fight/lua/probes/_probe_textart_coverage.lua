-- _probe_textart_coverage.lua —— 渲染文案用字是否都在字形库内
--   ★ 为什么需要：textart.lua 是离线烘焙的字形库，main.lua:1088 对缺字会回退成 '?'（码点 63）。
--     新写的中文一旦用到库里没有的字，屏幕上就是一个问号 —— 本项目真踩过（教/花/熟/悉）。
--   本探针**不看源码文本**，而是驱动游戏走遍各个状态、把真正下发的 hudText / menu 文案逐字比对，
--   所以零误报：报出来的字，就是玩家会看到问号的地方。
-- 用法：node tools/run-lua.mjs lua/probes/_probe_textart_coverage.lua
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local T = require('lua' .. '.textart')
local DT = M.DT

local missing, checked, samples = {}, 0, {}
local function scan(cmds, where)
  for _, c in ipairs(cmds or {}) do
    local strs = {}
    if c.kind == 'hudText' and type(c.text) == 'string' then strs[#strs + 1] = c.text end
    if c.kind == 'menu' and type(c.items) == 'table' then
      for _, s in ipairs(c.items) do if type(s) == 'string' then strs[#strs + 1] = s end end
    end
    for _, s in ipairs(strs) do
      checked = checked + 1
      for _, cp in utf8.codes(s) do
        if cp > 127 and not T.glyphs[cp] then
          if not missing[cp] then missing[cp] = where .. ' :: ' .. s end
          if #samples < 8 then samples = samples end
        end
      end
    end
  end
end

local function drive(g, frames, input)
  for _ = 1, frames do
    M.update(g, input or {}, DT)
    scan(M.render(g), tostring(g.state) .. (g.tutIdx and ('/L' .. g.tutIdx) or ''))
  end
end

-- 1) 标题页 / 二选一
local g0 = M.newTitle({ scripts = A })
scan(M.render(g0), 'title')
local gt = M.newTitle({ scripts = A, tutorial = true })
scan(M.render(gt), 'tut_ask')
M.tutChoose(gt, 0)
-- 2) 教程 6 节（每节用"超时兜底"推过去，期间把每帧文案都扫一遍）
for i = 1, 8 do
  scan(M.render(gt), 'tutorial/L' .. tostring(M.tutIndex(gt)))
  drive(gt, 200, {})
  if gt.state ~= 'tutorial' then break end
end
-- 3) 战斗：见面杀 + 菜单 + 子面板 + 攻击条
local g1 = M.newTitle({ scripts = A })
M.titleChoose(g1, 0)
drive(g1, 120, {})
drive(g1, 60, {})                      -- 敌人回合
M.menuChoose(g1, 0)                    -- 进子面板
drive(g1, 10, {})
M.subConfirm(g1, 0)
drive(g1, 10, {})
-- 4) 结局页
local gr = M.newTitle({ scripts = A, hp = 1 })
M.titleChoose(gr, 0)
gr.hp = 1
for _ = 1, 200 do M.update(gr, {}, DT); if gr.state == 'result' then break end end
scan(M.render(gr), 'result')

local list = {}
for cp, where in pairs(missing) do list[#list + 1] = string.format('U+%04X(%s)  @%s', cp, utf8.char(cp), where) end
table.sort(list)
print(string.format('扫描文案 %d 条，缺字 %d 个', checked, #list))
for _, s in ipairs(list) do print('  MISSING ' .. s) end
if #list == 0 then print('PASS 0 / FAIL 0   渲染文案用字全部在字形库内') else print('FAIL ' .. #list .. ' / 0') os.exit(1) end