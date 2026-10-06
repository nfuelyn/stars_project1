-- 千星客户端脚本 API 探针（单问题探针，用于解除「官方文档缺失」的阻塞）
-- 用法：在模拟器里挂到客户端控件上运行，读日志里的 "=== PROBE ===" 段。
-- 它只做反射输出，不改任何状态。

local function dump(t, name)
  local out, n = {}, 0
  for k, v in pairs(t) do
    n = n + 1
    out[#out + 1] = tostring(k) .. ':' .. type(v)
  end
  table.sort(out)
  print(name .. ' count=' .. n)
  print(name .. ' = ' .. table.concat(out, ','))
end

print('=== PROBE START ===')
print('_VERSION = ' .. tostring(_VERSION))
pcall(function() dump(_G, 'GLOBAL') end)
pcall(function()
  if type(game) == 'table' then dump(game, 'game') else print('game missing type=' .. type(game)) end
end)
for _, nm in ipairs({ 'PlayerSelf', 'Level', 'AvatarSelf', 'AllPlayers' }) do
  local v = rawget(_G, nm)
  print('global ' .. nm .. ' type=' .. type(v))
end
pcall(function()
  if type(game) == 'table' and type(game.GetUICanvasSize) == 'function' then
    local w, h = game.GetUICanvasSize()
    print('canvas = ' .. tostring(w) .. 'x' .. tostring(h))
  end
end)
print('=== PROBE END ===')
