--=============================================================================
-- bone_battle_demo.lua  --  bone_battle.lua 的可运行演示 / 自检
--   运行(在 D:\stars 下):  D:\5.1\lua.exe bone_battle_demo.lua
--   需要源码目录: D:\c2-sans-fight-src\Files\*.csv
--=============================================================================
local BoneBattle = dofile("bone_battle.lua")
local BlueSoul   = dofile("blue_soul.lua")

local DATA_DIR = "D:/c2-sans-fight-src/Files"
local DT = 1.0 / 60.0

print("================================================================")
print(" Sans 战斗 · 骨头攻击回合表（round 号）")
print("================================================================")
print(BoneBattle.roundTableText())
print("")

-------------------------------------------------------------------------------
-- 1) 单个骨头回合：sans_bluebone (round 3)，打印每根骨头的参数
-------------------------------------------------------------------------------
print("=== round 3 / sans_bluebone：逐根骨头生成日志 ===")
local bb = BoneBattle.new{ dataDir = DATA_DIR, heart = { x = 320, y = 376, w = 16, h = 16 } }
local frames = 0
bb.onBoneSpawn = function(_, b)
    print(string.format("  f%-4d spawn %s  x=%-6.1f y=%-6.1f  %s=%-5.1f dir=%d speed=%.0f  (Damage=%d Karma=%d)",
        frames, b.kind, b.x, b.y, (b.kind == "H") and "w" or "h",
        (b.kind == "H") and b.w or b.h, b.dir, b.speed, b.damage, b.karma))
end
bb:startRound(3)
for i = 1, math.floor(2.5 / DT) do
    bb:update(DT); frames = frames + 1
end
print(string.format("  2.5s 后：活动骨头 %d 根", #bb.bones))
print("")

-------------------------------------------------------------------------------
-- 2) BoneStab 回合：sans_bonestab1 (round 19)，打印警告->出刺时序
-------------------------------------------------------------------------------
print("=== round 19 / sans_bonestab1：BoneStab 警告 -> 出刺 ===")
local bb2 = BoneBattle.new{ dataDir = DATA_DIR, heart = { x = 40, y = 304, w = 16, h = 16 } }
local t = 0
bb2.onEvent = function(_, kind, data)
    if kind == "warn" then
        print(string.format("  t=%5.3f  警告 dir=%d distance=%d", t, data.dir, data.distance))
    elseif kind == "stab" then
        print(string.format("  t=%5.3f  出刺 dir=%d distance=%d", t, data.dir, data.distance))
    elseif kind == "end_attack" then
        print(string.format("  t=%5.3f  EndAttack", t))
    end
end
bb2:startRound(19)
for i = 1, math.floor(12 / DT) do
    bb2:update(DT); t = t + DT
    if bb2.attackDone then break end
end
print("")

-------------------------------------------------------------------------------
-- 3) 骨头 + 蓝心联动：round 2 骨墙，灵魂用 blue_soul.lua 真实物理受击
-------------------------------------------------------------------------------
print("=== round 2 / sans_bonegap1：blue_soul 蓝心实测受击 ===")
local world = BlueSoul.newWorld{ left = 133, top = 251, right = 508, bottom = 391 }
local soul  = BlueSoul.new{ x = 320, y = 376, angle = 90, mode = BlueSoul.MODE_BLUE }
local bb3   = BoneBattle.new{ dataDir = DATA_DIR, hitCooldown = 0.5 }  -- 演示用 0.5s 无敌
bb3.heart = { x = soul.x, y = soul.y, w = 16, h = 16, mode = 1 }
local dmg = 0
bb3.onDamage = function() dmg = dmg + 1 end
bb3:startRound(2)

-- 一个简单的 AI：周期性起跳
local function ai(t)
    local phase = t % 1.6
    return { up = (phase < 0.20) }
end

local t3, lastLog = 0, -1
for i = 1, math.floor(5 / DT) do
    local input = ai(t3)
    soul:update(DT, input, world)
    bb3.heart.x, bb3.heart.y = soul.x, soul.y
    bb3:update(DT)
    if math.floor(t3) > lastLog then
        print(string.format("  t=%4.1fs  灵魂(%6.1f,%6.1f) 活动骨=%2d  累计受击=%d",
            t3, soul.x, soul.y, #bb3.bones, dmg))
        lastLog = math.floor(t3)
    end
    t3 = t3 + DT
end
print("")

-------------------------------------------------------------------------------
-- 4) 战斗模板用法：按 round 顺序连续跑三个骨头回合
-------------------------------------------------------------------------------
print("=== 战斗模板：连续回合 2 -> 3 -> 4（每回合 2s，静置心脏）===")
local seq = BoneBattle.new{ dataDir = DATA_DIR, heart = { x = 320, y = 376, w = 16, h = 16 } }
for _, rn in ipairs({ 2, 3, 4 }) do
    local info = seq:roundInfo(rn)
    local spawned = 0
    seq.onBoneSpawn = function() spawned = spawned + 1 end
    seq:runAttack(info.attack)
    for i = 1, math.floor(2 / DT) do
        seq:update(DT)
        if seq.attackDone then break end
    end
    print(string.format("  round %-2s %-18s 本回合生成 %2d 根骨，activeBones=%d",
        tostring(rn), info.attack, spawned, #seq.bones))
end

print("")
print("demo 结束。")