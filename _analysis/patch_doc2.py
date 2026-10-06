# -*- coding: utf-8 -*-
import io
q=r"D:\stars\workspace\sans-fight\docs\sprite-fit.md"
t=io.open(q,encoding="utf8").read()
t=t.replace("""- Sans 头：只保留 `Default` 与审判眼 `BlueEye`；其余表情回退到 `Default`。""",
"""- Sans 头：只保留 `Default` 与审判眼 `BlueEye`；其余表情回退到 `Default`。
- 左右姿势：`HandLeft` 用 `mirror = true` 水平镜像（原素材两套姿势朝向相同，原作靠镜像区分左/右）。""",1)
io.open(q,"w",encoding="utf8",newline="").write(t)
print("doc updated")
