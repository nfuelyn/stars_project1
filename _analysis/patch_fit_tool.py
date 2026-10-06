# -*- coding: utf-8 -*-
import io
p=r"D:\stars\workspace\sans-fight\tools\fit-sprites.py"
s=io.open(p,encoding="utf8").read()
old_main = s[s.index("MAIN = {"):s.index("}\nlines = [")]
new_main = '''MAIN = {
    # 龙骨炮：Default + 3 个开火帧（000 起 / 002 中 / 004 满）
    "blaster_Default": "blaster_default",
    "blaster_Fire_000": "blaster_fire_0",
    "blaster_Fire_002": "blaster_fire_2",
    "blaster_Fire_004": "blaster_fire_4",
    # Sans 身体：默认站姿 + 4 套姿势各一帧（帧号取该姿势的方向极值）
    "sans_body_HandRight_000": "sans_body_default",
    "sans_body_HandUp_004": "sans_body_up",
    "sans_body_HandDown_003": "sans_body_down",
    "sans_body_HandLeft_000": "sans_body_left",
    "sans_body_HandRight_004": "sans_body_right",
    # Sans 头：只保留 Default 与审判眼（BlueEye）；流汗走 SansSweat（按需再烘焙）
    "sans_head_Default": "sans_head_default",
    "sans_head_BlueEye": "sans_head_blue",
    # 骨头
    "bone_BoneV": "bone_vertical",
    "bone_BoneH": "bone_horizontal",
    "bone_BoneStabV": "bone_stab_vertical",
    "bone_BoneStabH": "bone_stab_horizontal",
    "bone_BoneStabWarn": "bone_warn",
}
'''
s=s.replace(old_main,new_main,1)
# 在 M.meta 之后追加 sans_poses 表
anchor = '''    "  fit = 'exact-rle',",
    "}",
    "",
]'''
add = '''    "  fit = 'exact-rle',",
    "}",
    "",
    "-- Sans 合成参数：body = 身体容器；head = 头容器；hx/hy = 头的左上角相对身体左上角的像素偏移；sweat = 流汗覆盖层偏移（相对头左上角）。",
    "M.sans_poses = {",
    "  default = { body = 'sans_body_default', hx = 15, hy = 6 },",
    "  up      = { body = 'sans_body_up',      hx = 12, hy = 28 },",
    "  down    = { body = 'sans_body_down',    hx = 11, hy = 31 },",
    "  left    = { body = 'sans_body_left',    hx = 15, hy = 6 },",
    "  right   = { body = 'sans_body_right',   hx = 15, hy = 6 },",
    "}",
    "M.sans_head_default_key = 'sans_head_default'",
    "M.sans_head_blue_key = 'sans_head_blue'",
    "M.blaster_keys = { default = 'blaster_default', fire = { 'blaster_fire_0', 'blaster_fire_2', 'blaster_fire_4' } }",
    "",
]'''
assert anchor in s
s=s.replace(anchor,add,1)
io.open(p,"w",encoding="utf8",newline="").write(s)
print("patched fit tool")
