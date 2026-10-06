# -*- coding: utf-8 -*-
import io
p=r"D:\stars\workspace\sans-fight\lua\main.lua"
s=io.open(p,encoding="utf8").read()
# remove leftover mixCol body
start=s.find("  if t >= 1 then return c2 end\n  local a1, a2 =")
end=s.index("\nend\n", start)+len("\nend\n")
assert start>=0 and end>start
s=s[:start]+s[end:]
# remove SANS_SX/SY decls
s=s.replace("local SANS_SX = 1.15\nlocal SANS_SY = 0.95\n","",1)
# tidy the stale comment block about SX/SY scaling
s=s.replace("""-- **缩放**：横向 SANS_SX、纵向 SANS_SY **分别**作用（用户要求「扩大一点」+「纵向缩小」）；锚点取**脚底**，
-- 所以横向变宽不会挪位置、纵向变矮只是头顶下移。`cmd.y` 语义仍是「参考身高 148 的头顶 y」。
local SANS_H = 148""","""-- **锚点**：脚底锚定（feet = cmd.y + SANS_H）。`cmd.y` 语义仍是「参考身高 148 的头顶 y」。
local SANS_H = 148""",1)
io.open(p,"w",encoding="utf8",newline="").write(s)
print("fixed")
