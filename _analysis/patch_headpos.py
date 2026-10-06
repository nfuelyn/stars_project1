# -*- coding: utf-8 -*-
import io
p=r"D:\stars\workspace\sans-fight\tools\fit-sprites.py"
s=io.open(p,encoding="utf8").read()
old="""    "M.sans_poses = {",
    "  default = { body = 'sans_body_default', hx = 15, hy = 6 },",
    "  up      = { body = 'sans_body_up',      hx = 12, hy = 28 },",
    "  down    = { body = 'sans_body_down',    hx = 11, hy = 31 },",
    "  left    = { body = 'sans_body_left',    hx = 15, hy = 6, mirror = true },",
    "  right   = { body = 'sans_body_right',   hx = 15, hy = 6 },",
    "}","""
new="""    "M.sans_poses = {",
    "  -- hx/hy = SansHead 左上角相对 SansBody 左上角的像素偏移；由原工程 C2 image point 换算：",
    "  --   头原点(0.5,1) 放到 body 的 Head 点(x*W, y*H)，y 从顶边量起 → hy = y*H - 30。",
    "  default = { body = 'sans_body_default', hx = 17, hy = -24 },",
    "  up      = { body = 'sans_body_up',      hx = 14, hy = -2 },",
    "  down    = { body = 'sans_body_down',    hx = 14, hy = 1 },",
    "  left    = { body = 'sans_body_left',    hx = 18, hy = -24, mirror = true },",
    "  right   = { body = 'sans_body_right',   hx = 18, hy = -24 },",
    "}","""
assert old in s
s=s.replace(old,new,1)
io.open(p,"w",encoding="utf8",newline="").write(s)
print("patched sans_poses offsets")
