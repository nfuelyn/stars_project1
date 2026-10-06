# -*- coding: utf-8 -*-
import io
# 1) _geometry.lua: drop obsolete blaster primitive check
p=r"D:\stars\workspace\sans-fight\lua\_geometry.lua"
s=io.open(p,encoding="utf8").read()
s=s.replace("local KINDS = { 'bone', 'blaster', 'sine', 'stab', 'platform', 'wall', 'soul' }",
            "local KINDS = { 'bone', 'sine', 'stab', 'platform', 'wall', 'soul' }",1)
s=s.replace("string.format('A：7 类世界实体全覆盖（实测 %d 类）', seen)",
            "string.format('A：' .. #KINDS .. ' 类世界实体全覆盖（实测 %d 类）', seen)",1)
s=s.replace("string.format('B：7 类世界实体全覆盖（实测 %d 类 / %d 条）', seenB, totalB)",
            "string.format('B：' .. #KINDS .. ' 类世界实体全覆盖（实测 %d 类 / %d 条）', seenB, totalB)",1)
io.open(p,"w",encoding="utf8",newline="").write(s)
print("geometry KINDS patched")

# 2) fit tool: only canonical baked keys go into lua/fitdata.lua
q=r"D:\stars\workspace\sans-fight\tools\fit-sprites.py"
t=io.open(q,encoding="utf8").read()
a=t.index("MAIN = {")
b=t.index("}\nlines = [", a)
new='''MAIN = {
    # 只输出运行时真正用到的 11 个烘焙素材；其余（其它表情/帧/躯干/腿/骨头 exact 表）
    # 仍保留在 reference/sprites/fit/fitdata.json 与 REPORT.md 里做参考，不进 lua/fitdata.lua。
    "blaster_Default": "blaster_default",
    "blaster_Fire_000": "blaster_fire_0",
    "blaster_Fire_002": "blaster_fire_2",
    "blaster_Fire_004": "blaster_fire_4",
    "sans_body_HandRight_000": "sans_body_default",
    "sans_body_HandUp_004": "sans_body_up",
    "sans_body_HandDown_003": "sans_body_down",
    "sans_body_HandLeft_000": "sans_body_left",
    "sans_body_HandRight_004": "sans_body_right",
    "sans_head_Default": "sans_head_default",
    "sans_head_BlueEye": "sans_head_blue",
'''
t=t[:a]+new+t[b:]
io.open(q,"w",encoding="utf8",newline="").write(t)
print("fit tool MAIN trimmed")
