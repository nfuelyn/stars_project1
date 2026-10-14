-- _probe_tutorial.lua —— 新手教程阶段流程探针（只读，不改任何逻辑）
-- 用法：node tools/run-lua.mjs lua/probes/_probe_tutorial.lua
package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. package.path
local M = require('lua' .. '.core')
local A = require('lua' .. '.attacks')
local DT = M.DT
local pass, fail = 0, 0
local function ok(c, m) if c then pass = pass + 1; print('  PASS ' .. m) else fail = fail + 1; print('  FAIL ' .. m) end end

print('=== 新手教程阶段探针 ===')
local g = M.newTitle({ scripts = A, hp = 92, tutorial = true })
ok(g.state == 'tut_ask', 'newTitle({tutorial=true}) → state=tut_ask（实际 ' .. tostring(g.state) .. '）')

-- 默认态不受影响（既有测试口径）
local g0 = M.newTitle({ scripts = A, hp = 92 })
ok(g0.state == 'title', 'newTitle()（不传 tutorial）→ state=title（实际 ' .. tostring(g0.state) .. '）')

-- 二选一：左右切换
M.tutAskMove(g, 1); ok(g.tutAskIndex == 1, '右移 → 索引 1（直接开始）')
M.tutAskMove(g, 1); ok(g.tutAskIndex == 0, '再右移 → 环回索引 0（进入教程）')
M.tutAskMove(g, -1); ok(g.tutAskIndex == 1, '左移 → 索引 1')

-- 选「直接开始」
local gs = M.newTitle({ scripts = A, hp = 92, tutorial = true })
M.tutChoose(gs, 1)
ok(gs.state == 'title', '选「直接开始」→ 回到开始菜单（实际 ' .. tostring(gs.state) .. '）')

-- 选「进入教程」
M.tutChoose(g, 0)
ok(g.state == 'tutorial' and M.tutIndex(g) == 1, '选「进入教程」→ tutorial / 第 1 节（' ..
   tostring(g.state) .. ' idx=' .. tostring(M.tutIndex(g)) .. '）')
ok(M.tutLessonKey(g) == 'redmove', '第 1 节 = redmove（实际 ' .. tostring(M.tutLessonKey(g)) .. '）')

local cmds = M.render(g)
local kinds = {}
for _, c in ipairs(cmds) do kinds[c.kind] = true end
ok(kinds.box and kinds.soul and kinds.hudText,
   '教程态渲染含 box/soul/hudText（box=' .. tostring(kinds.box) .. ' soul=' .. tostring(kinds.soul) .. '）')

local function step(inp, n) for _ = 1, (n or 1) do M.update(g, inp, DT) end end
local function lesson() return M.tutLessonKey(g) end

-- 第 1 节：四向各走 ≥40px（红心速度 150px/s → 40px ≈ 16 帧）
step({ right = true }, 40)
step({ left = true }, 80)
step({ down = true }, 60)
step({ up = true }, 120)
ok(lesson() == 'bone', '第 1 节（红心移动）完成 → 第 2 节 bone（实际 ' .. tostring(lesson()) .. '）')

-- 第 2 节：站着不动撑 7 秒（会被滑骨打到 → 重来；这里只验证"能推进"）
local guard = 0
while lesson() == 'bone' and guard < 3600 do step({}, 30); guard = guard + 30 end
ok(lesson() == 'bluemove', '第 2 节（骨头攻击）结束 → 第 3 节 bluemove（实际 ' .. tostring(lesson()) .. '，用了 ' .. guard .. ' 帧）')

-- 第 3 节：蓝心左右各 40px
step({ right = true }, 40)
step({ left = true }, 80)
guard = 0
while lesson() == 'bluemove' and guard < 3600 do step({}, 30); guard = guard + 30 end
ok(lesson() == 'bluejump', '第 3 节（蓝心移动）完成 → 第 4 节 bluejump（实际 ' .. tostring(lesson()) .. '）')

-- 第 4 节：四向各起跳一次（重力每 2.6s 转一次；每隔几帧给一次确认脉冲）
guard = 0
while lesson() == 'bluejump' and guard < 3600 do
  step({ confirm = true }, 1)
  step({}, 5)
  guard = guard + 6
end
ok(lesson() == 'bluebone', '第 4 节（蓝心四向跳跃）完成 → 第 5 节 bluebone（实际 ' .. tostring(lesson()) .. '，用了 ' .. guard .. ' 帧）')

-- 第 5 节：蓝骨 —— 不动就不会被打
guard = 0
while lesson() == 'bluebone' and guard < 3600 do step({}, 30); guard = guard + 30 end
ok(lesson() == 'orangebone', '第 5 节（蓝骨机制）结束 → 第 6 节 orangebone（实际 ' .. tostring(lesson()) .. '）')

-- 第 6 节：橙骨 —— 必须一直动
guard = 0
while lesson() == 'orangebone' and guard < 3600 do
  step({ right = true }, 20); step({ left = true }, 20)
  guard = guard + 40
end
ok(g.state == 'title', '第 6 节结束 → 回到开始菜单 title（实际 ' .. tostring(g.state) .. '）')

-- 教程态被打到不会 result
local gh = M.newTitle({ scripts = A, hp = 3, tutorial = true })
M.tutChoose(gh, 0)
for _ = 1, 40 do M.update(gh, {}, DT) end
gh.invuln = 0
M.debugHurt(gh, 'hit')
ok(gh.state == 'tutorial' and gh.hp >= 2, '教程内被打：state 仍为 tutorial、HP 有下限（state=' ..
   tostring(gh.state) .. ' hp=' .. tostring(gh.hp) .. '）')

-- 取消键退出教程
M.update(gh, { cancel = true }, DT)
ok(gh.state == 'title', '取消键 → 退出教程回开始菜单（实际 ' .. tostring(gh.state) .. '）')

print('')
print(string.format('PASS %d / FAIL %d', pass, fail))
if fail > 0 then os.exit(1) end