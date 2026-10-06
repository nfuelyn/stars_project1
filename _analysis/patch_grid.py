# -*- coding: utf-8 -*-
import io
p=r"D:\stars\workspace\sans-fight\tools\fit-sprites.py"
s=io.open(p,encoding="utf8").read()
start=s.index('def load_grid(rel):')
end=s.index('def color_hex(c):')
new='''def load_grid(rel):
    """返回 (w,h,pixels[y][x])；pixels 为 None（透明 / 与画布边界连通的黑色底）或 (r,g,b)。

    统一口径：边界连通的黑色一律当背景去掉（SansBody 有些帧是 RGB 黑底、有些是 RGBA 不透明黑底）；
    形如眼窝/衣缝的**内部黑色**不与边界连通，保留为实体。
    """
    im = Image.open(os.path.join(SPR, rel)).convert("RGBA")
    w, h = im.size; px = im.load()
    grid = [[None] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a >= 128:
                grid[y][x] = (r, g, b)
    # 从四边洪泛黑色 → None
    stack = []
    for x in range(w):
        for y in (0, h - 1):
            if grid[y][x] == (0, 0, 0): stack.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if grid[y][x] == (0, 0, 0): stack.append((x, y))
    while stack:
        x, y = stack.pop()
        if x < 0 or y < 0 or x >= w or y >= h or grid[y][x] != (0, 0, 0): continue
        grid[y][x] = None
        stack += [(x+1, y), (x-1, y), (x, y+1), (x, y-1)]
    return w, h, grid

'''
s=s[:start]+new+s[end:]
io.open(p,"w",encoding="utf8",newline="").write(s)
print("patched load_grid")
# main.lua: uniform scale + K
m=r"D:\stars\workspace\sans-fight\lua\main.lua"
x=io.open(m,encoding="utf8").read()
x=x.replace("local SANS_BAKE_SCALE = 1.8","local SANS_BAKE_SCALE = 1.6",1)
x=x.replace("local kx, ky = K * SANS_SX, K * SANS_SY","local kx, ky = K, K   -- 原版是 1:1 像素，这里整体等比放大；不再套用参数化版的 SX/SY",1)
io.open(m,"w",encoding="utf8",newline="").write(x)
print("patched main scale")
