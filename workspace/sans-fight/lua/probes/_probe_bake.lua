--[[ ==========================================================================
  _probe_bake.lua —— 「全流程龙骨炮烘焙」的编排核对探针（纯离线，不进存档）
  ---------------------------------------------------------------------------
  回答两个问题：
    A. 每个回合最多同时几发龙骨炮、是不是都带 bake=true（= 走 fitdata.block2 像素烘焙）。
    B. 龙骨炮「在场」的时间窗——平衡难度会整体挪动这一段（终盘 final 尤其明显），
       截图/试玩验收时按这个表对准时刻，不然很容易拍到空档。

  为什么需要：见 main.lua 的 BUDGET 注释 —— 烘焙龙骨炮走 rrect() → **rot 池**，
  每发 ≈ 129 件（block2 112~126 + 光束 2 + 炮口 1），9 发同屏就是 1161 件。
  这个探针给出「峰值出现在哪个回合、哪段时间」，BUDGET.rot 按它定档。

  用法：node tools/run-lua.mjs lua/_probe_bake.lua
  ========================================================================== ]]
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local core = require('lua' .. '.core')
local atk  = require('lua' .. '.attacks')
local DT = core.DT
local IDLE = { left=false,right=false,up=false,down=false,confirm=false,cancel=false }
local LAST_ROUND = core.TOTAL_ROUNDS and (core.TOTAL_ROUNDS - 1) or 23
local function pad(s, n) s = tostring(s); while #s < n do s = s .. ' ' end; return s end

local function census(n, diff)
  local g = core.newGame({ scripts = atk, hp = 1000000, difficulty = diff or 'original' })
  g:startEnemy(n)
  local t, maxN, maxB, firstT, lastT = 0, 0, 0, nil, nil
  while g.state == 'enemy' and t < 400 do
    core.update(g, IDLE, DT); t = t + DT
    local cmds = core.render(g)
    local c, b = 0, 0
    for _, k in ipairs(cmds) do
      if k.kind == 'blaster' then c = c + 1; if k.bake then b = b + 1 end end
    end
    if c > 0 then if not firstT then firstT = t end; lastT = t end
    if c > maxN then maxN = c end
    if b > maxB then maxB = b end
  end
  return { script = g.roundScript, dur = t, maxN = maxN, maxB = maxB, firstT = firstT, lastT = lastT }
end

print('=== A. 每回合同屏龙骨炮峰值（difficulty=original；bake 必须 == 总数）===')
print(pad('round', 7) .. pad('script', 22) .. pad('maxN', 6) .. pad('maxBake', 9) .. pad('rotRects~', 11) .. 'window(s)')
local worst = { n = 0, script = '', r = 0 }
for n = 0, LAST_ROUND do
  local r = census(n)
  local rects = r.maxB * 129
  print(pad('r' .. n, 7) .. pad(r.script or '-', 22) .. pad(r.maxN, 6) .. pad(r.maxB, 9) .. pad(rects, 11)
    .. (r.firstT and string.format('%.2f..%.2f', r.firstT, r.lastT) or '-'))
  if rects > worst.r then worst = { n = r.maxN, script = r.script, r = rects, round = n } end
end
print('')
print(string.format('峰值：round %d（%s）同屏 %d 发 → rot 池约 %d 件/帧（BUDGET.rot = 1350）',
  worst.round, worst.script, worst.n, worst.r))

print('')
print('=== B. 终盘 final 的龙骨炮时间窗随难度整体平移（截图/验收对准用）===')
for _, diff in ipairs({ 'easy', 'normal', 'hard', 'original' }) do
  local r = census(LAST_ROUND, diff)
  print(string.format('  %-9s 窗口 %6s..%-6s 同屏峰值 %d 发（%.1fs）',
    diff,
    r.firstT and string.format('%.2f', r.firstT) or '-',
    r.lastT and string.format('%.2f', r.lastT) or '-', r.maxN, r.dur))
end
