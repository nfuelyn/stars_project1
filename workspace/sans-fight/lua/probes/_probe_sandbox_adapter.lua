--[[ ==========================================================================
  _probe_sandbox_adapter.lua —— 「沙箱接轨层」确定性探针（纯离线，不进存档）
  ---------------------------------------------------------------------------
  模拟**真机形态**：客户端模板是「容器 + 叶子」包装（父层是容器节点、叶子才是图元），
  宿主就是脚本挂载对象 script.object。核对 lua/main.lua 的接轨部分：

    A. 候选索引：模拟器 GUID 在真机上返回 nil，要能自动落到真机索引。
    B. 包装解开：拿到容器要**钻进叶子**（老实现用 prefabIndex 短路 → 永远钻不进去，只剩空容器）；
       叶子归一化到左下/中心锚点，包装层拉伸；父子都 SetActive/SetVisible(true)。
    C. 颜色/字号/文本：写错类型直接抛（真机的 imageColor/fontColor/bgColor 要 ColorValue）。
    D. images = 0 语义：默认**不调** SetImage（真机 100001 不是有效资产，调了会刷空白）。
    E. 真机不做大批量预热（每个实例带子控件，预热 ~2000 份 = 卡死），改按需创建。
    F. 生命周期：OnStart 幂等；OnDestroy 摘监听 + 销毁自建控件，但**不销毁宿主 root**。
    G. 更新回调：默认只走 OnLevelUpdate；config.updateCallback='ui' 时 OnUpdate 才转发。

  用法：node tools/run-lua.mjs lua/probes/_probe_sandbox_adapter.lua
  ========================================================================== ]]
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. LUA_ROOT .. '/lua/?.lua;' .. package.path
-- main.lua 里 tryLoadCore 走的是完整模块名，离线台要先把 core/attacks 预置进 package.loaded
local core = require('lua' .. '.core')
local attacks = require('lua' .. '.attacks')
package.loaded['default_import_file/workspace/sans-fight/lua/core'] = core
package.loaded['default_import_file/workspace/sans-fight/lua/attacks'] = attacks

local R = { pass = 0, fail = 0 }
local function ok(name, cond)
  if cond then R.pass = R.pass + 1; io.write('  PASS ' .. name .. '\n')
  else R.fail = R.fail + 1; io.write('  FAIL ' .. name .. '\n') end
end
local function eq(name, got, want)
  ok(name .. ' (' .. tostring(got) .. ' == ' .. tostring(want) .. ')', got == want)
end
local function head(t) io.write('\n== ' .. t .. '\n') end

-- 真机模板索引（用户确认的那一套；容器节点 1862，备用 1884）
local REAL = {
  rect = 1073741865, circle = 1073741871, ring = 1073741875,
  rot = 1073741877, rtri = 1073741879, text = 1073741867,
  cursor = 1073741860, baked = 1073741862,
}
-- 模拟器模板池索引（存档 tools/build-save.mjs 写进去的那一套）
local SIM = {
  rect = 1073743001, circle = 1073743002, text = 1073743004, ring = 1073743006,
  rot = 1073743007, rtri = 1073743008, cursor = 1073743009,
  baked = 1073743100, bakedC = 1073743101, bakedRoot = 1073743102,
}
local LEAF_NAME = {
  rect = '矩形图元', circle = '圆形图元', ring = '圆环图元', rot = '旋转图元',
  rtri = '旋转三角形图元', text = '文本框', cursor = '光标检测区域', baked = '烘焙容器根',
}
local CONTAINER_KIND = { baked = true }

local function guidKind(map, guid)
  for k, v in pairs(map) do if v == guid then return k end end
  return nil
end

-- ---------------------------------------------------------------- 假真机引擎
-- mode = 'real-wrapper'：模板是「容器 + 叶子」包装，模拟器索引一律返回 nil
-- mode = 'sim-direct'  ：模拟器形态，模板直接就是叶子
-- 假枚举库：真机上 Enum.KeyEventType / CursorEventType / TextHorizontalAlignment / ImageSource 是枚举项
-- （Lua 侧是 userdata，这里用带 __kind 的表等价模拟），字符串写进去会抛类型错误。
local function mkEnumLib()
  local function item(group, name) return { __kind = 'EnumItem', Name = name, EnumType = group } end
  local out = {}
  for _, g in ipairs({ 'KeyEventType', 'CursorEventType', 'TextHorizontalAlignment', 'ImageSource' }) do out[g] = {} end
  -- 方向键：键盘表里有（KeyboardKeyCode 的 MoveForward/Backward/Left/Right）
  for _, n in ipairs({ 'KeyboardMoveForwardKeyDown', 'KeyboardMoveForwardKeyUp', 'KeyboardMoveBackwardKeyDown',
      'KeyboardMoveBackwardKeyUp', 'KeyboardMoveLeftKeyDown', 'KeyboardMoveLeftKeyUp', 'KeyboardMoveRightKeyDown',
      'KeyboardMoveRightKeyUp', 'KeyboardJumpKeyDown', 'KeyboardJumpKeyUp', 'KeyboardDropKeyDown', 'KeyboardDropKeyUp',
      'KeyboardInteractKeyDown', 'KeyboardInteractKeyUp', 'KeyboardNormalAttackKeyDown', 'KeyboardNormalAttackKeyUp',
      -- ★ 键盘表里**没有** MenuConfirmKey / MenuBackKey，它们只存在于控制器表（与 worker.js 的 pl() 一致）
      'ControllerMenuConfirmKeyDown', 'ControllerMenuConfirmKeyUp',
      'ControllerMenuBackKeyDown', 'ControllerMenuBackKeyUp' }) do
    out.KeyEventType[n] = item('KeyEventType', n)
  end
  for _, n in ipairs({ 'CursorDown', 'CursorDrag', 'CursorUp', 'CursorClick' }) do
    out.CursorEventType[n] = item('CursorEventType', n)
  end
  for _, n in ipairs({ 'Left', 'Middle', 'Right' }) do out.TextHorizontalAlignment[n] = item('TextHorizontalAlignment', n) end
  out.ImageSource.StaticReference = item('ImageSource', 'StaticReference')
  return out
end

local function makeEnv(mode, cfgOverride, opts)
  opts = opts or {}
  local STRICT = opts.strict == true
  Enum = opts.withEnum and mkEnumLib() or nil
  local function keyName(n) return (type(n) == 'table') and (n.Name or '?') or tostring(n) end
  local function keyKind(n) return (type(n) == 'table') and 'enum' or 'string' end
  local E = {
    made = {}, madeByGuid = {}, destroyed = {}, rootDestroyed = false, leafOf = {}, parentOf = {}, kindOf = {},
    keyDown = {}, keyRemoved = {}, keyKind = {},
    cursorOn = {}, cursorOff = {}, cursorKind = {}, cursorAllOff = 0,
    rootProps = {}, writeErr = {}, imageCalls = 0, unknownGuid = 0, alignWritten = {},
  }

  local function mkLeaf(kind)
    local store = {}
    if opts.unityDefault then      -- 真机模板默认：锚点=中心、pivot=0.5（Unity RectTransform 默认）
      store.amin, store.amax, store.pivot = { 0.5, 0.5 }, { 0.5, 0.5 }, { 0.5, 0.5 }
    end
    local c = setmetatable({ kind = 'leaf', name = LEAF_NAME[kind] or 'leaf', alive = true }, {
      __index = function(_, k)
        if k == 'SetVisible' then return function(_, v) store.vis = v and true or false end end
        if k == 'SetActive' then return function(_, v) store.act = v and true or false end end
        if k == 'SetSizeDelta' then return function(_, w, h) store.w, store.h = w, h end end
        if k == 'SetAnchoredPosition' then return function(_, x, y) store.cx, store.cy = x, y end end
        if k == 'SetLocalRotation' then return function(_, x, y, z) store.rot = z end end
        if k == 'SetAnchorMin' then return function(_, x, y) store.amin = { x, y } end end
        if k == 'SetAnchorMax' then return function(_, x, y) store.amax = { x, y } end end
        if k == 'SetPivot' then return function(_, x, y) store.pivot = { x, y } end end
        if k == 'SetAsFirstSibling' then return function() end end
        if k == 'SetAsLastSibling' then return function() E.raised = (E.raised or 0) + 1 end end
        if k == 'SetImage' then return function(_, src, id)
          E.imageCalls = E.imageCalls + 1; store.src, store.img = src, id
        end end
        if k == 'AddKeyEventListener' then return function(_, n, fn)
          if STRICT and type(n) ~= 'table' then
            error("bad argument #2 to 'AddKeyEventListener' (KeyEventType expected, got " .. type(n) .. ")", 2)
          end
          E.keyDown[keyName(n)] = fn; E.keyKind[keyName(n)] = keyKind(n)
        end end
        if k == 'AddCursorEventListener' then return function(_, n, fn)
          if STRICT and type(n) ~= 'table' then
            error("bad argument #2 to 'AddCursorEventListener' (CursorEventType expected, got " .. type(n) .. ")", 2)
          end
          E.cursorOn[keyName(n)] = fn; E.cursorKind[keyName(n)] = keyKind(n)
        end end
        if k == 'RemoveCursorEventListener' then return function(_, n, fn)
          if E.cursorOn[keyName(n)] == fn and E.cursorKind[keyName(n)] == keyKind(n) then
            E.cursorOn[keyName(n)] = nil; E.cursorOff[keyName(n)] = true
          end
        end end
        if k == 'RemoveAllCursorEventListeners' then return function() E.cursorAllOff = E.cursorAllOff + 1 end end
        if k == 'GetChildren' then return function() return {} end end
        if k == 'GetChild' then return function() return nil end end
        return store[k]
      end,
      __newindex = function(_, k, v)
        if k == 'imageColor' or k == 'fontColor' or k == 'bgColor' or k == 'imageId' then
          if math.type(v) ~= 'integer' then
            E.writeErr[#E.writeErr + 1] = k .. '=' .. tostring(v) .. '(' .. type(v) .. ')'
            error('bad ' .. k, 2)
          end
        elseif k == 'fontSize' then
          if math.type(v) ~= 'integer' then E.writeErr[#E.writeErr + 1] = 'fontSize'; error('bad fontSize', 2) end
        elseif k == 'text' then
          if type(v) ~= 'string' then E.writeErr[#E.writeErr + 1] = 'text'; error('bad text', 2) end
        elseif k == 'horizontalAlignment' then
          -- 真机：字符串会抛 "TextHorizontalAlignment expected, got string"
          if STRICT and type(v) ~= 'table' then
            E.writeErr[#E.writeErr + 1] = 'horizontalAlignment=' .. tostring(v)
            error("bad argument #2 to 'horizontalAlignment' (TextHorizontalAlignment expected, got " .. type(v) .. ")", 2)
          end
          E.alignWritten[#E.alignWritten + 1] = keyKind(v)
        end
        store[k] = v
      end,
    })
    return c
  end

  -- 包装容器：**故意带上 prefabIndex = 模板索引**，用来证明「靠 prefabIndex 短路」的老实现是错的。
  local function mkWrapper(guid, kind)
    local leaf = mkLeaf(kind)
    local kids = { leaf }
    local store = {}
    local w = setmetatable({ kind = 'container', name = '容器节点', alive = true, prefabIndex = guid }, {
      __index = function(_, k)
        if k == 'SetVisible' then return function(_, v) store.vis = v and true or false end end
        if k == 'SetActive' then return function(_, v) store.act = v and true or false end end
        if k == 'SetAnchorMin' then return function(_, x, y) store.amin = { x, y } end end
        if k == 'SetAnchorMax' then return function(_, x, y) store.amax = { x, y } end end
        if k == 'SetPivot' then return function(_, x, y) store.pivot = { x, y } end end
        if k == 'SetSizeDelta' then return function(_, a, b) store.w, store.h = a, b end end
        if k == 'SetAnchoredPosition' then return function(_, x, y) store.cx, store.cy = x, y end end
        if k == 'GetChildren' then return function() return kids end end
        if k == 'GetChild' then return function(_, i) return kids[i] end end
        if k == 'SetAsFirstSibling' then return function() end end
        if k == 'SetAsLastSibling' then return function() E.raised = (E.raised or 0) + 1 end end
        return store[k]   -- 注意：SetImage / text / AddCursorEventListener 一概没有
      end,
      __newindex = function(_, k, v) store[k] = v end,
    })
    return w, leaf
  end

  local rootStore = {}
  local rootCtrl = setmetatable({ kind = 'container', name = 'SansFightRoot', alive = true }, {
    __index = function(_, k)
      if k == 'AddKeyEventListener' then return function(_, n, fn)
        if STRICT and type(n) ~= 'table' then
          error("bad argument #2 to 'AddKeyEventListener' (KeyEventType expected, got " .. type(n) .. ")", 2)
        end
        E.keyDown[keyName(n)] = fn; E.keyKind[keyName(n)] = keyKind(n)
      end end
      if k == 'RemoveKeyEventListener' then return function(_, n, fn)
        -- 注册用什么形态的键，就必须用什么形态摘 —— 形态不一致要能在这里被发现
        if E.keyDown[keyName(n)] == fn and E.keyKind[keyName(n)] == keyKind(n) then
          E.keyDown[keyName(n)] = nil; E.keyRemoved[keyName(n)] = true
        end
      end end
      if k == 'GetChildren' then return function() return {} end end
      if k == 'SetAsFirstSibling' or k == 'SetAsLastSibling' then return function() end end
      return rootStore[k]
    end,
    __newindex = function(_, k, v) rootStore[k] = v; E.rootProps[k] = v end,
  })
  E.root = rootCtrl

  package.loaded['default_import_file/workspace/sans-fight/lua/config'] =
    cfgOverride or { updateCallback = 'level', templatesFirst = 'sim', legacyTemplateFallback = true, textMode = 'control' }
  -- 离线台把 fitdata 置空（走参数化回退）；textart 也置成"没有 glyphs"的空表 →
  -- 让文字走原生文本框路径，这样本探针才能继续断言"文本框写入/置顶"这些控件层行为。
  package.loaded['default_import_file/workspace/sans-fight/lua/fitdata'] = {}
  package.loaded['default_import_file/workspace/sans-fight/lua/textart'] = { glyphs = {} }

  game = {
    GetUICanvasSize = function() return 1280, 720 end,
    GetClientUIControl = function(id) if id == 1 then return rootCtrl end return nil end,
    InstantiateClientUIControl = function(guid, parent)
      local rkind, skind = guidKind(REAL, guid), guidKind(SIM, guid)
      if mode == 'real-wrapper' or mode == 'real-direct' then
        -- 真机：模拟器索引是「不认识的模板」→ nil；真机索引才有效
        if not rkind then E.unknownGuid = E.unknownGuid + 1; return nil end
        local c, leaf
        if mode == 'real-direct' or CONTAINER_KIND[rkind] then c = mkLeaf(rkind) else c, leaf = mkWrapper(guid, rkind) end
        E.made[#E.made + 1] = c
        E.madeByGuid[guid] = (E.madeByGuid[guid] or 0) + 1
        E.leafOf[c] = leaf
        E.parentOf[c] = parent
        E.kindOf[c] = rkind
        return c
      end
      -- 模拟器：模板直接就是叶子
      if not skind then E.unknownGuid = E.unknownGuid + 1; return nil end
      local c = mkLeaf(skind)
      E.made[#E.made + 1] = c
      E.madeByGuid[guid] = (E.madeByGuid[guid] or 0) + 1
      E.leafOf[c] = c
      E.parentOf[c] = parent
      E.kindOf[c] = skind
      return c
    end,
    DestroyClientUIControl = function(c)
      if c == rootCtrl then E.rootDestroyed = true end
      E.destroyed[#E.destroyed + 1] = c
    end,
    GetGlobalCustomVariableValue = function() error('none') end,
    PrintClientUITree = function() end,
  }
  script = { object = rootCtrl, EnableUpdate = function() end }

  package.loaded['lua' .. '.main'] = nil
  E.main = require('lua' .. '.main')
  return E
end

local function boot(E)
  local okI, errI = pcall(E.main.OnInit)
  ok('OnInit 不报错 (' .. tostring(errI) .. ')', okI)
  local okS, errS = pcall(E.main.OnStart)
  ok('OnStart 不报错 (' .. tostring(errS) .. ')', okS)
end

-- ================================================================ A/B/C/D/E
head('真机形态：容器包装模板 + script.object 宿主')
local E = makeEnv('real-wrapper')
boot(E)
eq('OnStart 之后拿到真机模板（模拟器索引全部被拒）', E.madeByGuid[REAL.rect] ~= nil, true)
ok('模拟器索引在真机上返回 nil 且未污染主流程', E.unknownGuid > 0)
ok('真机不做大批量预热（实例数远小于 2000）', #E.made < 200)
eq('root.showCursor 打开', E.rootProps.showCursor, true)
eq('root.disableKeyEventPassthrough 打开', E.rootProps.disableKeyEventPassthrough, true)
eq('root.disableCursorEventPassthrough 打开', E.rootProps.disableCursorEventPassthrough, true)

local wrapped, anchored, stretched = 0, 0, 0
for _, c in ipairs(E.made) do
  local leaf = E.leafOf[c]
  if leaf and leaf ~= c then
    wrapped = wrapped + 1
    if leaf.amin and leaf.amax and leaf.pivot then anchored = anchored + 1 end
    if c.amax and c.amax[1] == 1 and c.amax[2] == 1 then stretched = stretched + 1 end
  end
end
ok('拿到的是「容器 + 叶子」包装模板', wrapped > 0)
ok('叶子被归一化（anchorMin/anchorMax/pivot 都写过）', anchored > 0)
ok('包装层被拉伸铺满父容器', stretched > 0)

local frameErr
for _ = 1, 60 do
  local okf, errf = pcall(E.main.OnLevelUpdate, 1 / 30)
  if not okf and frameErr == nil then frameErr = errf end
end
ok('60 帧 OnLevelUpdate 不报错 (' .. tostring(frameErr) .. ')', frameErr == nil)
eq('颜色/字号/文本类型全部合法', #E.writeErr, 0)
eq('images = 0 → 不调 SetImage（沿用模板自带图片）', E.imageCalls, 0)
ok('注册了键盘监听', next(E.keyDown) ~= nil)
ok('文本框每帧被提到最上层（走 SetAsLastSibling，' .. tostring(E.raised or 0) .. ' 次）', (E.raised or 0) > 0)
ok('注册了游标监听', next(E.cursorOn) ~= nil)

-- 控件是否真的被驱动（叶子被 SetSizeDelta/SetVisible 写过 = 绘制链路接通）
local driven = 0
for _, c in ipairs(E.made) do
  local leaf = E.leafOf[c] or c
  if leaf.w and leaf.vis ~= nil then driven = driven + 1 end
end
ok('真有控件被写入尺寸/可见性（绘制链路接通）', driven > 0)

local madeBefore = #E.made
pcall(E.main.OnStart)
eq('OnStart 幂等（重复调用不再实例化）', #E.made, madeBefore)

-- ================================================================ F
head('生命周期：OnDestroy 摘监听 + 销毁自建控件，不销毁 root')
pcall(E.main.OnDestroy)
ok('root 上的按键监听全部摘掉', next(E.keyDown) == nil)
ok('游标监听全部摘掉', next(E.cursorOn) == nil)
ok('root 自己没有被销毁（不是我们建的）', E.rootDestroyed == false)
-- 真机/模拟器都禁止在「创建或销毁阶段」调 DestroyClientUIControl
--   （警告原文：客户端控件生命周期处于创建或销毁时，无法调用 DestroyClientUIControl）
-- 我们建的控件挂在宿主 root 下，容器销毁时引擎会一并回收 → OnDestroy 只清引用。
eq('OnDestroy 不再主动 DestroyClientUIControl', #E.destroyed, 0)

-- ================================================ H：真机「只吃枚举项」形态
head('真机枚举形态：KeyEventType / CursorEventType / TextHorizontalAlignment')
local ES = makeEnv('real-wrapper', nil, { strict = true, withEnum = true })
boot(ES)
ok('方向键用 Enum.KeyEventType 注册成功（不再是 bind fail）',
   ES.keyDown['KeyboardMoveForwardKeyDown'] ~= nil and ES.keyKind['KeyboardMoveForwardKeyDown'] == 'enum')
ok('确认键注册成功：真机枚举里没有 KeyboardMenuConfirm，走 ControllerMenuConfirmKey',
   ES.keyDown['ControllerMenuConfirmKeyDown'] ~= nil and ES.keyKind['ControllerMenuConfirmKeyDown'] == 'enum')
ok('确认键还有兜底来源（Jump / NormalAttack / Interact）',
   ES.keyDown['KeyboardJumpKeyDown'] ~= nil and ES.keyDown['KeyboardNormalAttackKeyDown'] ~= nil and
   ES.keyDown['KeyboardInteractKeyDown'] ~= nil)
ok('取消键走 ControllerMenuBackKey（键盘表里没有 KeyboardMenuBack）',
   ES.keyDown['ControllerMenuBackKeyDown'] ~= nil and ES.keyKind['ControllerMenuBackKeyDown'] == 'enum')
ok('真机上**没有**注册进 KeyboardMenuConfirmKey（枚举不存在时不留假绑定）',
   ES.keyDown['KeyboardMenuConfirmKeyDown'] == nil)
eq('游标监听 4 个全部注册（Enum.CursorEventType）',
   ES.cursorOn.CursorDown ~= nil and ES.cursorOn.CursorDrag ~= nil and
   ES.cursorOn.CursorUp ~= nil and ES.cursorOn.CursorClick ~= nil, true)
eq('游标监听用的是枚举形态', ES.cursorKind.CursorDown, 'enum')
-- 画 30 帧（标题页有文字）之后再看对齐到底写成什么形态
local drawErr = 0
local realPrint = print
print = function(...)
  local parts = {}
  for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end
  if table.concat(parts, ' '):find('draw ERR', 1, true) then drawErr = drawErr + 1 end
  return realPrint(...)
end
for _ = 1, 30 do pcall(ES.main.OnLevelUpdate, 1 / 30) end
print = realPrint
eq('枚举形态下 30 帧绘制无报错', drawErr, 0)
local enumAlign, strAlign = 0, 0
for _, k in ipairs(ES.alignWritten) do
  if k == 'enum' then enumAlign = enumAlign + 1 elseif k == 'string' then strAlign = strAlign + 1 end
end
ok('horizontalAlignment 写成枚举（真机只吃 TextHorizontalAlignment）', enumAlign > 0)
eq('字符串形式一个都没写进去（全被真机拒绝）', strAlign, 0)
eq('对齐形态只探测一次（writeErr 只有第一次探测的 1 条）', #ES.writeErr, 1)
eq('枚举形态下标题页还在', (ES.main.state() or {}).state, 'title')
ES.keyDown['ControllerMenuConfirmKeyDown']()      -- 按「控制器确认」
ES.keyDown['ControllerMenuConfirmKeyUp']()
for _ = 1, 5 do pcall(ES.main.OnLevelUpdate, 1 / 30) end
ok('按 ControllerMenuConfirm 能真的开局（枚举监听链路通）', (ES.main.state() or {}).state ~= 'title')
pcall(ES.main.OnDestroy)
ok('OnDestroy 用**同形态**的键摘掉键盘监听', next(ES.keyDown) == nil)
ok('OnDestroy 不销毁 root', ES.rootDestroyed == false)

-- ================================================ J：黑底两层 + 锚点归一化
head('真机直接模板（Unity 默认锚点=中心）+ 黑底铺满')
local EA = makeEnv('real-direct', nil, { unityDefault = true })
local capturedA = {}
local realPrintA = print
print = function(...)
  local parts = {}
  for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end
  capturedA[#capturedA + 1] = table.concat(parts, ' ')
  return realPrintA(...)
end
boot(EA)
print = realPrintA

-- OnStart 里最先创建的两个控件就是两层黑底
local b1, b2 = EA.made[1], EA.made[2]
ok('黑底①（stretch）锚点铺满 (0,0)-(1,1)',
   b1 ~= nil and b1.amin and b1.amin[1] == 0 and b1.amax and b1.amax[1] == 1)
ok('黑底①（stretch）尺寸差 0（不靠大尺寸，靠拉伸铺满 Root）', b1 ~= nil and b1.w == 0 and b1.h == 0)
ok('黑底②（外扩）尺寸差 = 2 倍画布（四周各外扩 1 倍）', b2 ~= nil and b2.w == 2560 and b2.h == 1440)
ok('两层黑底都用居中 pivot（不依赖 pivot 的绝对摆放）',
   b1 ~= nil and b1.pivot and b1.pivot[1] == 0.5 and b2 ~= nil and b2.pivot and b2.pivot[1] == 0.5)

local corner, centerPiv, stretchedFull = 0, 0, 0
for _, c in ipairs(EA.made) do
  local leaf = EA.leafOf[c] or c
  local p = leaf.pivot
  if p then
    if p[1] == 0 and p[2] == 0 then corner = corner + 1
    elseif p[1] == 0.5 and p[2] == 0.5 then centerPiv = centerPiv + 1 end
  end
  if leaf.amax and leaf.amax[1] == 1 and leaf.amax[2] == 1 then stretchedFull = stretchedFull + 1 end
end
ok('真机直接模板也被归一化成左下锚点（不只是容器包装分支）', corner > 0)
ok('旋转件仍是中心锚点', centerPiv > 0)
ok('光标区/烘焙根/黑底被拉伸铺满（anchorMax=1,1）', stretchedFull >= 3)

local sawGeom = false
for _, line in ipairs(capturedA) do
  if line:find('geom[bg1-stretch]', 1, true) then sawGeom = true end
end
ok('打印了几何回读诊断（geom[root] / geom[bg1-stretch] / geom[bg2-overscan]）', sawGeom)

-- ================================================ K：烘焙（CodeArt）子控件的锚点口径
head('CodeArt 烘焙：子块必须 pivot 0.5 + 位置 0（龙骨炮/Sans 模型的像素块）')
local EB = makeEnv('real-direct', nil, { unityDefault = true })
-- 给一个最小 fitdata：让 sans 一进场就走烘焙容器（子块走比例锚点）
package.loaded['default_import_file/workspace/sans-fight/lua/fitdata'] = {
  sans_poses = { default = { body = 'sans_body_default' } },      -- drawSans 的入口表
  sans_head_default_key = 'sans_head_default',
  sans_head_blue_key = 'sans_head_blue',
  sans_body_default = { w = 4, h = 4, rects = { { x = 0, y = 0, w = 2, h = 2, c = 0xFFFFFFFF },
                                               { x = 2, y = 2, w = 2, h = 2, c = 0xFF000000 } } },
  sans_head_default = { w = 4, h = 4, rects = { { x = 0, y = 0, w = 4, h = 4, c = 0xFFFFFFFF } } },
}
boot(EB)
local fireConfirm = EB.keyDown['ControllerMenuConfirmKeyDown'] or EB.keyDown['KeyboardMenuConfirmKeyDown']
  or EB.keyDown['KeyboardNormalAttackKeyDown']
if fireConfirm then fireConfirm() end
for _ = 1, 180 do pcall(EB.main.OnLevelUpdate, 1 / 30) end

-- 【2026-10-08 第三轮】子块改成**绝对几何**：左下锚点 + pivot 0 + 绝对位置 + 绝对尺寸。
-- （原来用「比例锚点 + sizeDelta 0」在真机上不可靠：模型散成细条。）
local kids, kidAnchorOK, kidPivotOK, kidSizeOK, kidMoved = 0, 0, 0, 0, 0
for _, c in ipairs(EB.made) do
  local pk = EB.kindOf[EB.parentOf[c]]
  if pk == 'baked' or pk == 'bakedC' then
    kids = kids + 1
    if c.amin and c.amax and c.amin[1] == 0 and c.amax[1] == 0 then kidAnchorOK = kidAnchorOK + 1 end
    if c.pivot and c.pivot[1] == 0 and c.pivot[2] == 0 then kidPivotOK = kidPivotOK + 1 end
    if c.w and c.h and c.w > 0 and c.h > 0 then kidSizeOK = kidSizeOK + 1 end
    if c.cx and (c.cx ~= 0 or c.cy ~= 0) then kidMoved = kidMoved + 1 end
  end
end
ok('CodeArt 子块存在（' .. kids .. ' 个）', kids > 0)
eq('子块锚点=左下 (0,0)', kidAnchorOK, kids)
eq('子块 pivot=(0,0)', kidPivotOK, kids)
eq('子块用绝对尺寸（>0，不靠 sizeDelta=0 的 stretch）', kidSizeOK, kids)
ok('子块位置按像素坐标摆放（至少一个非 0）', kidMoved > 0)

-- ================================================ I：键位诊断开关
head('键位诊断 C.keyDiag（默认关，排查真机物理键用）')
local ED = makeEnv('sim-direct', { keyDiag = true, updateCallback = 'level', textMode = 'control',
                                    templatesFirst = 'sim', legacyTemplateFallback = true }, { withEnum = true })
local captured = {}
local realPrint2 = print
print = function(...)
  local parts = {}
  for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end
  captured[#captured + 1] = table.concat(parts, ' ')
  return realPrint2(...)
end
pcall(ED.main.OnInit); pcall(ED.main.OnStart)
print = realPrint2
local sawDiag = false
for _, line in ipairs(captured) do
  if line:find('[keyDiag] 已挂', 1, true) then sawDiag = true end
end
ok('C.keyDiag = true 时挂了全量按键诊断监听', sawDiag)
local nKeys = 0
for _ in pairs(ED.keyDown) do nKeys = nKeys + 1 end
ok('诊断监听覆盖全量事件（>= 10 个键名）', nKeys >= 10)

-- ================================================================ G
head('更新回调：默认 level；config.updateCallback = ui 时才由 OnUpdate 转发')
local E2 = makeEnv('sim-direct')
boot(E2)
local s2 = E2.main.state()
eq('默认 level：从 title 开始', s2 and s2.state, 'title')
if E2.keyDown['KeyboardMenuConfirmKeyDown'] then E2.keyDown['KeyboardMenuConfirmKeyDown']() end
pcall(E2.main.OnUpdate, 1 / 30)
local after = E2.main.state()
eq('默认 level：OnUpdate 是空实现（仍在 title）', after and after.state, 'title')
pcall(E2.main.OnLevelUpdate, 1 / 30)
after = E2.main.state()
ok('默认 level：OnLevelUpdate 推进了标题页', after and after.state ~= 'title')
eq('默认 level：不调用 SetImage（images=0）', E2.imageCalls, 0)

local E3 = makeEnv('sim-direct', { updateCallback = 'ui', templatesFirst = 'sim', legacyTemplateFallback = true, textMode = 'control' })
boot(E3)
if E3.keyDown['KeyboardMenuConfirmKeyDown'] then E3.keyDown['KeyboardMenuConfirmKeyDown']() end
pcall(E3.main.OnUpdate, 1 / 30)
local s3 = E3.main.state()
ok('ui 模式：OnUpdate 转发了战斗推进', s3 and s3.state ~= 'title')

io.write(string.format('\n==== 沙箱接轨探针：PASS %d / FAIL %d ====\n', R.pass, R.fail))
if R.fail > 0 then os.exit(1) end


