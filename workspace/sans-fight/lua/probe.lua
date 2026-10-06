-- probe.lua —— 管线探针：验证「客户端控件模板池」实例化 + 图元 + 文本 + 旋转 + 世界→画布映射
-- 只在 OnStart 之后实例化（runtime.instantiate 在 OnInit/OnDestroy 一律返回 nil）
--
-- ⚠ 历史文件：本探针**不进存档、不参与构建**（build-save.mjs 只收 boot/main/core/attacks）。
--    下面 G 表里的 `tri = 1073743003` 与 `star = 1073743005` 已在优化轮从模板池删除
--    （整场 0 次取用），所以直接跑本文件时这两个索引会打印 `probe inst NIL` —— 属预期现象，
--    其余图元仍可用。此处只作历史记录保留、逻辑一行未改（三角件现用中心锚点的 rtri 1073743008）。
local G = {
  rect   = 1073743001,
  circle = 1073743002,
  tri    = 1073743003,
  text   = 1073743004,
  star   = 1073743005,
  ring   = 1073743006,
  rot    = 1073743007, -- 中心锚点，供旋转件用
}

local S  = 1.5   -- 640x480 世界 → 1280x720 画布
local OX = 160   -- 居中偏移
local CW, CH = 1280, 720

local root = nil
local made = 0
local frame = 0
local flash, bone1, soul = nil, nil, nil

local function inst(idx)
  local ok, c = pcall(function() return game.InstantiateClientUIControl(idx, root) end)
  if not ok then print('probe inst ERR idx=' .. tostring(idx) .. ' :: ' .. tostring(c)) return nil end
  if c == nil then print('probe inst NIL idx=' .. tostring(idx)) return nil end
  made = made + 1
  return c
end

-- 模板锚点/pivot = 左下角 (0,0)：世界 y 是「顶边」，转成画布底边
local function place(c, x, y, w, h)
  c:SetSizeDelta(w * S, h * S)
  c:SetAnchoredPosition(OX + x * S, CH - (y + h) * S)
end

-- 中心锚点模板：传世界中心
local function placeC(c, cx, cy, w, h)
  c:SetSizeDelta(w * S, h * S)
  c:SetAnchoredPosition(OX + cx * S - CW / 2, CH - cy * S - CH / 2)
end

local function rect(x, y, w, h, color)
  local c = inst(G.rect); if not c then return nil end
  place(c, x, y, w, h); c.imageColor = color; return c
end
local function circ(x, y, d, color)
  local c = inst(G.circle); if not c then return nil end
  place(c, x, y, d, d); c.imageColor = color; return c
end
local function tri(x, y, w, h, color)
  local c = inst(G.tri); if not c then return nil end
  place(c, x, y, w, h); c.imageColor = color; return c
end
local function tick(txt, x, y, w, size, color, align)
  local c = inst(G.text); if not c then return nil end
  place(c, x, y, w, size + 8)
  c.text = txt
  c.fontSize = size
  c.fontColor = color
  c.horizontalAlignment = align or 'Left'
  return c
end
local function rotRect(cx, cy, w, h, deg, color)
  local c = inst(G.rot); if not c then return nil end
  placeC(c, cx, cy, w, h); c.imageColor = color
  c:SetLocalRotation(deg)
  return c
end

-- 骨头：骨干 + 两端各两颗骨球（竖骨 w=19）
local function bone(x, y, len, color)
  rect(x + 6, y + 7, 7, len - 14, color)
  circ(x, y, 12, color)
  circ(x + 7, y, 12, color)
  circ(x, y + len - 12, 12, color)
  circ(x + 7, y + len - 12, 12, color)
end

-- 灵魂（红心近似：双圆瓣 + 倒三角尖）
local function heart(x, y, color)
  circ(x + 1, y, 9, color)
  circ(x + 9, y, 9, color)
  tri(x + 2, y + 8, 15, 11, color)
end

-- 龙骨炮：方形炮身 + 5 条细实线光束（原作无实心填充）
local function blaster(cx, cy, deg, len, color)
  rotRect(cx, cy, 22, 22, deg, color)
  for i = -2, 2 do
    rotRect(cx + i * 4, cy + 3, 2, len, deg, color)
  end
end

local function scene()
  -- 战斗框（4 条边）
  local bx, by, bw, bh = 200, 280, 240, 140
  rect(bx, by, bw, 4, 0xFFFFFFFF)
  rect(bx, by + bh - 4, bw, 4, 0xFFFFFFFF)
  rect(bx, by, 4, bh, 0xFFFFFFFF)
  rect(bx + bw - 4, by, 4, bh, 0xFFFFFFFF)

  -- 三根骨头（白/蓝/橙）
  bone(214, 300, 80, 0xFFFFFFFF)
  bone(264, 300, 80, 0xFF2F6BFF)
  bone(314, 300, 80, 0xFFFF7A18)

  -- 灵魂 + 龙骨炮（旋转件）
  heart(392, 350, 0xFFFF2B2B)
  blaster(560, 120, 90, 160, 0xFFFFFFFF)

  -- 预告：远方一根半透明的骨（peek）
  local pk = circ(150, 120, 12, 0x66FFFFFF)
  if pk then pk.sizeDeltaX = 12 * S end

  -- HUD（文本框：用属性写入，模拟器没有 SetText）
  tick('HP 92/92   KR 0', 176, 16, 300, 28, 0xFFFFFFFF, 'Left')
  tick('审判者', 176, 52, 300, 22, 0xFFB9C6D8, 'Left')
  tick('* 你感觉骨头在生长。', 200, 440, 420, 22, 0xFFFFFFFF, 'Left')

  -- 全屏闪白层（ARGB alpha）
  flash = rect(-OX / S, 0, CW / S, CH / S, 0x00000000)
  if flash then flash:SetSiblingIndex(0) end
end

function OnInit()
  print('probe init: pool 未实例化（OnInit 不允许实例化）')
end

function OnStart()
  root = game.GetClientUIControl(1)
  print('probe OnStart root=' .. tostring(root ~= nil))
  scene()
  print('probe scene made=' .. tostring(made))
  local c = game.GetClientUIControl(1)
  print('probe pool probe: root children=' .. tostring(c and #c:GetChildren() or -1))
  print('probe canvas=' .. tostring(select(1, game.GetUICanvasSize())) .. 'x' .. tostring(select(2, game.GetUICanvasSize())))
  print('probe done')
end

function OnLevelUpdate(dt)
  frame = frame + 1
  if frame % 30 == 0 then
    local a = (frame / 30) % 2
    print('probe alive frame=' .. frame .. ' t=' .. string.format('%.2f', frame * dt) .. ' phase=' .. tostring(a))
  end
end
