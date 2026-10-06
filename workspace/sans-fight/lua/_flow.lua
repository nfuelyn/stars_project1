-- _flow.lua —— 自动打多个回合，观察战斗框怎么变 + 抓运行期错误
-- 用假 game API 跑真正的 main.lua（含适配层），用 core 的公开接口替玩家操作，
-- 并清空危险实体以免中途死亡（我们关心流程与框，不关心打得过打不过）。
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path

local core = require('lua' .. '.core')
local attacks = require('lua' .. '.attacks')
package.loaded['default_import_file/workspace/sans-fight/lua/core'] = core
package.loaded['default_import_file/workspace/sans-fight/lua/attacks'] = attacks

local nextId = 1
-- 假控件按**引擎口径**校验属性写入：类型不符就 error，模拟真实运行时的抛错。
-- 这样"整帧绘制被 pcall 吞掉"的 bug（例如 fontSize 写小数）能在离线的全阶段跑批里被抓住，
-- 而不是只能靠真机/模拟器试玩才发现。
local writeErrors = {}
local sawResultText = false    -- 是否给控件写过结局文字（证明结局画面真的在渲染文字，而非只有白闪）
local function mkControl(kind)
  local c = { Id = nextId, kind = kind, visible = true, prefabIndex = 0 }
  nextId = nextId + 1
  local store = {}
  return setmetatable(c, {
    __index = function(_, k)
      local m = {
        SetVisible = 1, SetActive = 1, SetImage = 1, SetSiblingIndex = 1, SetSizeDelta = 1,
        SetAnchoredPosition = 1, SetLocalRotation = 1, AddKeyEventListener = 1,
        -- 烘焙容器（main.useBakedCorner/useBakedCenter）用到的锚点 API：
        -- 旧版白名单漏了这几项 → 每帧 draw ERR（main.lua:503 SetAnchorMin），
        -- 而整帧失败会被 main 自己的 pcall 吞掉，导致 _flow 长期误报「结局没渲染」。
        SetAnchorMin = 1, SetAnchorMax = 1, SetPivot = 1, SetLocalScale = 1,
        AddCursorEventListener = 1, GetChildren = 1, GetChild = 1, FindChild = 1,
      }
      if m[k] then return function() end end
      return store[k]
    end,
    __newindex = function(_, k, v)
      local bad
      if k == 'fontSize' then bad = (math.type(v) ~= 'integer') and ('fontSize 必须是整数，得到 ' .. tostring(v))
      elseif k == 'imageColor' then bad = (math.type(v) ~= 'integer') and ('imageColor 必须是整数(ARGB)，得到 ' .. tostring(v))
      elseif k == 'imageId' then bad = (math.type(v) ~= 'integer') and ('imageId 必须是整数，得到 ' .. tostring(v))
      elseif k == 'text' then bad = (type(v) ~= 'string') and ('text 必须是字符串，得到 ' .. type(v))
      elseif k == 'horizontalAlignment' or k == 'verticalAlignment' then
        bad = (type(v) ~= 'string') and (k .. ' 必须是字符串，得到 ' .. type(v))
      end
      if bad then
        writeErrors[#writeErrors + 1] = ('控件 %s(%s) 写入非法：%s'):format(tostring(c.Id), tostring(c.kind), bad)
        error('bad property write: ' .. bad, 2)
      end
      if k == 'text' then
        local sv = tostring(v)
        -- 结局文字是**带空格的风格字**（如「击 倒 结 局」「饶 恕 结 局」）以及英文 'GAME OVER'，
        -- 所以不能用不带空格的 '结局' 去匹配（踩过：断言恒 false，误判成"结局没渲染"）。
        if sv:find('GAME OVER', 1, true) or sv:find('结 局', 1, true) or sv:find('重 开', 1, true) then
          sawResultText = true
        end
      end
      store[k] = v
    end,
  })
end
local rootCtrl = mkControl('container')
game = {
  -- PC 画布（1600×900 → S=1.875）：字号缩放会出现小数，能覆盖「fontSize 必须整数」那条路径；
  -- 手机画布 S=1.5 时恰好都是整数，会掩盖这类问题（_tap.lua 也固定在 PC 画布）。
  GetUICanvasSize = function() return 1600, 900 end,
  GetClientUIControl = function(id) if id == 1 then return rootCtrl end return nil end,
  InstantiateClientUIControl = function() return mkControl('inst') end,
  GetGlobalCustomVariableValue = function() error('none') end,
  PrintClientUITree = function() end,
}

local main = require('lua' .. '.main')

-- main.lua 的 draw 出错是它**自己 pcall 吞掉**并 print 的，不会冒到外层循环，
-- 所以这里接管 print 做关键字统计（否则这类整帧中断的 bug 在离线跑批里会被漏掉）。
local realPrint = print
local printCounts = {}
local WATCH = { 'draw ERR', 'WARN', 'inst NIL', 'inst ERR', 'require main 失败', '攻击条超时' }
print = function(...)
  local parts = {}
  for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end
  local line = table.concat(parts, ' ')
  for _, pat in ipairs(WATCH) do
    if line:find(pat, 1, true) then printCounts[pat] = (printCounts[pat] or 0) + 1 end
  end
  realPrint(line)
end

main.OnInit()
main.OnStart()

-- 点按链路的坐标换算在 lua/_tap.lua 里单独跑（这里只做流程 + 框/灵魂几何回归）。

local lastBox, boxChanges, errors, phases = nil, 0, {}, {}
local maxDrawOvr, maxOvrAt = 0, 'none'
local maxSoulOut, soulOutAt = 0, 'none'
-- 按钮行定位（本轮新增）：把「以屏幕中心为参照、不与框重叠、留在世界内」这三条
-- 在**整场每一帧**上都验一遍，而不是只验抽样的那一帧。
--   常量出处：参考实现 data.js / BattleScreen / Buttons 图层（110×42 按钮 y=432）
--   → 行顶边 = 屏幕中心 y(240) + 192；行中心 = 240 + 213；间距 2；底部留白 3（见 lua/main.lua 注释）。
local ROW_DY_TOP, ROW_GAP, ROW_BOTTOM_MARGIN, WORLD_H = 192, 2, 3, 480
local rowFrames, overlapFrames, overlapWithRoom, rowOutOfWorld, rowConstMismatch = 0, 0, 0, 0, 0
local overlapWorst, overlapWorstAt = 0, 'none'
local lastState = nil
local function clearHazards(st)
  if st and st.world then
    st.world.bones, st.world.sine, st.world.blasters = {}, {}, {}
  end
end

for i = 1, 18000 do           -- 约 600 秒游戏时间：24 回合（见面杀 + 22 个固定脚本回合 + 终盘 final）
                              -- 实测整场约 445s（_probe_pool2 跑到 result 用 13357 帧），旧值 11000 帧
                              -- 在 24 回合结构下跑不到结局态 → 「结局文字已渲染」恒 FAIL
                              -- 实测整场约 250s，旧版 5400 帧（180s）只够跑完 6 回合那套结构
  local ok, err = pcall(main.OnLevelUpdate, 1.0 / 30.0)
  if not ok and #errors < 8 then errors[#errors + 1] = string.format('frame %d: %s', i, tostring(err)) end
  local st = main.state()
  if st then
    -- 替玩家操作：**只在进入状态的边沿调一次**（stopAttack 只设倒计时，反复调会永久重置）
    if st.state ~= lastState then
      if st.state == 'title' then
        pcall(function() core.titleChoose(st, nil) end)   -- 标题页：按当前档位开局（否则整场跑不动）
      elseif st.state == 'menu' then
        pcall(function() core.menuChoose(st, 0) end)      -- 选「攻击」
      elseif st.state == 'attack' then
        pcall(function() core.stopAttack(st) end)
      elseif st.state == 'sub' then
        pcall(function() core.subConfirm(st) end)
      end
      lastState = st.state
    end
    clearHazards(st)
    if st.state == 'result' then
      -- 必须让结局画面真的画几帧再收尾，否则"结局文字是否渲染"永远测不到
      for _ = 1, 30 do pcall(main.OnLevelUpdate, 1.0 / 30.0) end
      print(string.format('t=%.1f 结束（%s）', i / 30, tostring(st.result)))
      break
    end
    local ph = tostring(st.state) .. ':' .. tostring(st.round)
    if not phases[ph] then
      phases[ph] = true
      print(string.format('t=%6.1f 状态=%s round=%s hp=%s', i / 30, tostring(st.state), tostring(st.round), tostring(st.hp)))
    end
    -- 框变化：同时看「core 给的原始值」和「适配层真正画出来的值」
    local okR, cmds = pcall(function() return core.render(st) end)
    if okR then
      for _, c in ipairs(cmds) do
        if c.kind == 'box' then
          local key = string.format('(%.0f,%.0f) %.0fx%.0f', c.x, c.y, c.w, c.h)
          if key ~= lastBox then
            boxChanges = boxChanges + 1
            lastBox = key
            local dr, tg = main.box()
            print(string.format('t=%6.1f 框变化 #%d core=%s  绘制=(%.0f,%.0f) %.0fx%.0f  溢出 %.0f→%.0f  state=%s round=%s',
              i / 30, boxChanges, key, dr.x, dr.y, dr.w, dr.h,
              main.boxOverflow(c.x, c.y, c.w, c.h), main.boxOverflow(tg.x, tg.y, tg.w, tg.h),
              tostring(st.state), tostring(st.round)))
          end
        end
      end
    end
    -- 每帧检查：真正画出来的框绝不允许出现「双平移」量级的溢出（旧 bug 最大 379px）
    local dr, tg = main.box()
    -- 按钮行：拿**本帧实际绘制的矩形**（绘制与命中判定共用同一份，见 main.lua menuButtonRect）
    local lm9 = main.lastRects()
    if lm9 then
      local _, ry9, _, rh9 = main.menuRowRect(lm9, 1)
      rowFrames = rowFrames + 1
      local boxBottom9 = tg.y + tg.h
      if ry9 < boxBottom9 then
        overlapFrames = overlapFrames + 1
        local ov9 = boxBottom9 - ry9
        if ov9 > overlapWorst then
          overlapWorst, overlapWorstAt = ov9, string.format('t=%.1f state=%s round=%s 框底=%.1f 行顶=%.1f 框下余量=%.1f',
            i / 30, tostring(st.state), tostring(st.round), boxBottom9, ry9, WORLD_H - boxBottom9)
        end
        -- 违约：框下方明明放得下整行（+间距），却还是重叠了
        if (WORLD_H - boxBottom9) >= rh9 + ROW_GAP then overlapWithRoom = overlapWithRoom + 1 end
      end
      if ry9 < 0 or ry9 + rh9 > WORLD_H then rowOutOfWorld = rowOutOfWorld + 1 end
      -- 「行 = 屏幕中心 + 常量，必要时被框下沿/世界底边修正」这条公式逐帧复核
      local want9 = 240 + ROW_DY_TOP
      local floor9 = boxBottom9 + ROW_GAP
      if want9 < floor9 then want9 = floor9 end
      local ceil9 = WORLD_H - rh9 - ROW_BOTTOM_MARGIN
      if want9 > ceil9 then want9 = ceil9 end
      if math.abs(ry9 - want9) > 0.01 then rowConstMismatch = rowConstMismatch + 1 end
    end
    local ov = main.boxOverflow(dr.x, dr.y, dr.w, dr.h)
    if ov > maxDrawOvr then
      maxDrawOvr = ov
      maxOvrAt = string.format('t=%.1f state=%s round=%s box=(%.0f,%.0f,%.0f,%.0f)',
        i / 30, tostring(st.state), tostring(st.round), dr.x, dr.y, dr.w, dr.h)
    end
    -- 灵魂必须画在框内（框收敛后判定，避免过渡帧误报）：这才是玩家眼里的"对不对得上"
    local soulOk, soul = pcall(function() return main.soul() end)
    local boxSettled = math.abs(dr.x - tg.x) < 1 and math.abs(dr.y - tg.y) < 1
      and math.abs(dr.w - tg.w) < 1 and math.abs(dr.h - tg.h) < 1
    if soulOk and type(soul) == 'table' and (st.state == 'enemy') and boxSettled then
      local pad = 12   -- 灵魂半径 9 + 1px 容差
      local out = 0
      if soul.x < dr.x - pad then out = math.max(out, dr.x - pad - soul.x) end
      if soul.x > dr.x + dr.w + pad then out = math.max(out, soul.x - dr.x - dr.w - pad) end
      if soul.y < dr.y - pad then out = math.max(out, dr.y - pad - soul.y) end
      if soul.y > dr.y + dr.h + pad then out = math.max(out, soul.y - dr.y - dr.h - pad) end
      if out > maxSoulOut then
        maxSoulOut = out
        soulOutAt = string.format('t=%.1f round=%s 灵魂(%.0f,%.0f) 框(%.0f,%.0f,%.0f,%.0f) Δ=(%.0f,%.0f)',
          i / 30, tostring(st.round), soul.x, soul.y, dr.x, dr.y, dr.w, dr.h,
          main.boxDelta().x, main.boxDelta().y)
      end
    end
  end
end
print('--- 汇总 ---')
print('框变化次数 = ' .. boxChanges)
print(string.format('绘制框最大溢出 = %.1f px  (最差帧: %s)%s', maxDrawOvr, maxOvrAt,
  maxDrawOvr <= 60 and '  OK' or '  FAIL: 绘制框严重出界，双平移没纠正好'))
print(string.format('灵魂跑出框外最大 = %.1f px  (最差帧: %s)%s', maxSoulOut, soulOutAt,
  maxSoulOut <= 2 and '  OK' or '  FAIL: 心画到框外面了'))
-- 先取数、再恢复原始 print：否则下面这些汇总行自己也含关键字，会被计数成"1 次 draw ERR"
local drawErrN = printCounts['draw ERR'] or 0
local watchCopy = {}
for _, pat in ipairs(WATCH) do watchCopy[pat] = printCounts[pat] or 0 end
print = realPrint

print('错误数 = ' .. #errors)
print(string.format('属性写入类型违规 = %d%s', #writeErrors,
  #writeErrors == 0 and '  OK' or '  FAIL: 有非法属性写入（真机会整帧绘制中断）'))
for i = 1, math.min(#writeErrors, 5) do print('  ' .. writeErrors[i]) end
local watchLine = {}
for _, pat in ipairs(WATCH) do watchLine[#watchLine + 1] = pat .. '=' .. watchCopy[pat] end
print('日志关键字计数：' .. table.concat(watchLine, '  '))
print(string.format('整帧绘制失败(draw ERR) = %d%s', drawErrN,
  drawErrN == 0 and '  OK' or '  FAIL: 有整帧绘制失败'))
print(string.format('结局文字已渲染 = %s%s', tostring(sawResultText),
  sawResultText and '  OK（结局画面在画文字，不是只有白闪）' or '  FAIL: 结局态从未写入结局文字'))
-- 本轮新增：按钮行定位（整场逐帧）
print(string.format('按钮行帧数 = %d  与框重叠帧 = %d  行越界帧 = %d  偏离常量帧 = %d',
  rowFrames, overlapFrames, rowOutOfWorld, rowConstMismatch))
print(string.format('按钮行位置 == 屏幕中心(240) + %d，必要时被框下沿/世界底边修正 = %s',
  ROW_DY_TOP, rowConstMismatch == 0 and 'OK（整场逐帧成立）' or 'FAIL: 有帧偏离常量公式'))
print(string.format('按钮行始终落在世界 0..640/0..%d 内 = %s', WORLD_H,
  rowOutOfWorld == 0 and 'OK' or 'FAIL: 有帧越界'))
print(string.format('按钮行不与战斗框重叠 = %s（唯一允许的重叠 = 终盘超大框：框底 478.5，下方只剩 1.5px，放不下 %dpx 的行；实测最大重叠 %.1fpx @ %s）',
  overlapWithRoom == 0 and 'OK' or 'FAIL: 框下有空间却仍重叠',
  (main.lastRects() and select(4, main.menuRowRect(select(1, main.lastRects()), 1)) or 36), overlapWorst, overlapWorstAt))
for _, e in ipairs(errors) do print('  ' .. e) end
