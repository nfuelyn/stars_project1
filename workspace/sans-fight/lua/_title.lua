-- _title.lua -- title page (difficulty select) regression.
-- ASCII ONLY (the fengari harness truncates Lua source lines by bytes when printing tracebacks).
-- Checks: game boots into `title`; core emits 4 difficulty cards; titleMove changes selection;
-- titleChoose starts round 0 with the chosen difficulty; taps route through the adapter.
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path

local core = require('lua' .. '.core')
local attacks = require('lua' .. '.attacks')
package.loaded['default_import_file/workspace/sans-fight/lua/core'] = core
package.loaded['default_import_file/workspace/sans-fight/lua/attacks'] = attacks
-- 离线单测固定走参数化回退：烘焙容器需要 SetAnchorMin/Max，mock 引擎不实现。
package.loaded['default_import_file/workspace/sans-fight/lua/fitdata'] = {}

local nextId = 1
local function mkControl(kind)
  local c = { Id = nextId, kind = kind, visible = true, prefabIndex = 0 }
  nextId = nextId + 1
  return setmetatable(c, {
    __index = function(_, k)
      local m = {
        SetVisible = 1, SetActive = 1, SetImage = 1, SetSiblingIndex = 1, SetSizeDelta = 1,
        SetAnchoredPosition = 1, SetLocalRotation = 1, AddKeyEventListener = 1,
        AddCursorEventListener = 1, GetChildren = 1, GetChild = 1, FindChild = 1,
      }
      if m[k] then return function() end end
      return nil
    end,
  })
end
local rootCtrl = mkControl('container')
game = {
  GetUICanvasSize = function() return 1280, 720 end,
  GetClientUIControl = function(id) if id == 1 then return rootCtrl end return nil end,
  InstantiateClientUIControl = function() return mkControl('inst') end,
  GetGlobalCustomVariableValue = function() error('none') end,
  PrintClientUITree = function() end,
}

local CW, CH = game.GetUICanvasSize()
local S = math.min(CW / 640, CH / 480)
local OX, OY = (CW - 640 * S) / 2, (CH - 480 * S) / 2

local main = require('lua' .. '.main')
main.OnInit()
main.OnStart()

local fails, oks = {}, 0
local function eq(name, got, want)
  local okv
  if type(got) == 'number' and type(want) == 'number' then okv = math.abs(got - want) <= 0.01
  else okv = (got == want) end
  if okv then oks = oks + 1
  else fails[#fails + 1] = string.format('%s: got %s want %s', name, tostring(got), tostring(want)) end
end

local st = main.state()
eq('boots-into-title', st and st.state, 'title')
-- difficulty() 读不到 Level.SansDifficulty 时返回 'normal' → 标题页预选「普通」= DIFF_ORDER 的第 2 项 = 索引 1
eq('title-index-preselect-normal', core.titleIndex(st), 1)

-- one frame: title must render 4 cards and NOT be pushed below the box
local okF = pcall(main.OnLevelUpdate, 1.0 / 30.0)
eq('frame-ok', okF, true)
local cmds = core.render(main.state())
local cards, boxCmd = {}, nil
for _, c in ipairs(cmds) do
  if c.kind == 'menu' then cards[#cards + 1] = c end
  if c.kind == 'box' then boxCmd = c end
end
eq('four-cards', #cards, 4)
eq('card-y-kept', cards[1] and cards[1].y, 210)
eq('cards-separate-x', cards[2] and cards[2].x, 32 + 145)
eq('box-present', boxCmd ~= nil, true)

-- 标题页**不画战斗框**：core 仍然会推一条 box（战斗态复用同一位置），但适配层必须跳过它的绘制，
-- 否则白框会横穿四张难度卡（用户报的「卡片压在框的边框上」）。
eq('title-platform-pc', main.isTouch(), false)
eq('title-box-not-drawn', main.drawnBoxVisible(), false)
do
  local hasBox, kinds = false, main.drawnKinds()
  for _, k in ipairs(kinds) do if k == 'box' then hasBox = true end end
  eq('title-draw-has-no-box', hasBox, false)
  eq('title-draw-has-cards', (function()
    local n = 0
    for _, k in ipairs(kinds) do if k == 'menu' then n = n + 1 end end
    return n
  end)(), 4)
  eq('title-draw-has-text', (function()
    for _, k in ipairs(kinds) do if k == 'hudText' then return true end end
    return false
  end)(), true)
end

-- 四张难度卡各自独立、不得互相压叠：按**绘制用的按钮矩形**（menuRowRect）检查横向互斥
do
  local rects = {}
  for i = 1, #cards do
    local x, y, w, h = main.menuRowRect(cards[i], 1)
    rects[i] = { x = x, y = y, w = w, h = h }
  end
  local overlap = false
  for i = 1, #rects do
    for j = i + 1, #rects do
      local a, b = rects[i], rects[j]
      if a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h then
        overlap = true
      end
      -- 按钮矩形（不含左侧红心）之间必须完全分开：后一张卡要完全在前一张右边
      if not (b.x >= a.x + a.w) then overlap = true end
    end
  end
  eq('cards-no-overlap', overlap, false)
  eq('card1-rect-x', rects[1].x, 32)
  eq('card1-rect-right', rects[1].x + rects[1].w <= rects[2].x, true)
end

-- selection moves
core.titleMove(main.state(), 2)
eq('title-index-moved', core.titleIndex(main.state()), 3)
core.titleMove(main.state(), -5)
eq('title-index-clamped', core.titleIndex(main.state()), 0)

-- tap card 3 (index 2) through the real adapter click path: card x = 32+2*145 = 322, y = 210, w130 h40
-- (canvas is bottom-left/Y-up, so a world point converts with y_canvas = OY + (480 - y_world) * S)
local function tap(wx, wy) return main.click(OX + wx * S, OY + (480 - wy) * S) end
pcall(main.OnLevelUpdate, 1.0 / 30.0)          -- refresh titleCards
local consumed = tap(322 + 65, 210 + 20)
eq('tap-consumed', consumed, true)
eq('title-exited', main.state().state ~= 'title', true)
eq('chosen-difficulty', main.state().diffKey, core.DIFF_ORDER[3])

-- 菜单选中判定（纯函数）：踩过两次的 bug 类，单独钉住
do
  local row = { items = { 'a', 'b', 'c', 'd' }, index = 1 }        -- 0 基 → 第 2 项
  eq('row-sel-1', main.menuItemSelected(row, 1), false)
  eq('row-sel-2', main.menuItemSelected(row, 2), true)
  eq('row-sel-4', main.menuItemSelected(row, 4), false)
  eq('row-index-nil', main.menuItemSelected({ items = row.items }, 1), true)  -- 缺省 = 第 1 项
  -- 标题页难度卡：一卡一条命令、index 恒为 0，必须由布尔 selected 决定（否则四张卡全亮）
  eq('card-true', main.menuItemSelected({ items = { 'x' }, index = 0, selected = true }, 1), true)
  eq('card-false', main.menuItemSelected({ items = { 'x' }, index = 0, selected = false }, 1), false)
  eq('bool-wins', main.menuItemSelected({ items = { 'a', 'b' }, index = 1, selected = false }, 2), false)
end

-- 结局闪层门控：结局态只允许闪前 15 帧（否则全屏白闪永久盖住结局文字与重开项）
do
  eq('flash-normal', main.flashDrawable('enemy', 1), true)
  eq('flash-normal-late', main.flashDrawable('enemy', 9999), true)
  eq('flash-result-early', main.flashDrawable('result', 1), true)
  eq('flash-result-edge', main.flashDrawable('result', 15), true)
  eq('flash-result-off', main.flashDrawable('result', 16), false)
  eq('flash-result-late', main.flashDrawable('result', 120), false)
end

print(string.format('title regression: %d pass / %d fail', oks, #fails))
for _, f in ipairs(fails) do print('  FAIL ' .. f) end
