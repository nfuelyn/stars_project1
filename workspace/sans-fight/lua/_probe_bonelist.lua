package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
print('=== multi1 / multi3 里所有会「生成骨头」的命令（原样打印，便于指认）===')
for _, want in ipairs({ 'multi1', 'multi3' }) do
  for _, sc in ipairs(A) do
    if sc.name == want then
      print('')
      print('--- ' .. want .. ' ---')
      local i = 0
      for line in tostring(sc.csv):gmatch('[^\n]+') do
        i = i + 1
        local t = line:match('^%s*(.-)%s*$')
        if t:sub(1,1) ~= '#' and t:find('Bone', 1, true) then
          print(string.format('  L%-3d  %s', i, t))
        end
      end
    end
  end
end
