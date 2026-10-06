-- boot.lua —— 挂在客户端控件 n1 上的引导脚本
-- 故意保持极小：存档回读/导出时只有这几百字节，真逻辑在 lua/main.lua 模块里。
-- 生命周期是全局函数；这里显式定义并转发，避免依赖运行时如何查找脚本函数。

local M = nil
do
  local ok, mod = pcall(require, 'default_import_file/workspace/sans-fight/lua/main')
  if ok and type(mod) == 'table' then
    M = mod
  else
    print('boot: require main 失败 :: ' .. tostring(mod))
  end
end

local function call(name, ...)
  if M and type(M[name]) == 'function' then
    local ok, err = pcall(M[name], ...)
    if not ok then print('boot: ' .. name .. ' 出错 :: ' .. tostring(err)) end
  end
end

function OnInit() call('OnInit') end
function OnEnable() call('OnEnable') end
function OnStart() call('OnStart') end
function OnUpdate(dt) call('OnUpdate', dt) end
function OnLevelUpdate(dt) call('OnLevelUpdate', dt) end
function OnDisable() call('OnDisable') end
function OnDestroy() call('OnDestroy') end
