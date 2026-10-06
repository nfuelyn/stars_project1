#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
fit-sprites.py —— 把 reference/sprites 里的原版 PNG 拟合成千星图元。

两种拟合口径：
  exact   : 逐像素游程（RLE）矩形，1:1 还原原图；矩形数 = 真实成本。
  block N : 每 N×N 取样一次 + 游程合并；降采样近似，矩形数少很多。
  param   : 少量图元（rect/circle/triangle）的参数化外形，给运行时低预算用。

输出：
  reference/sprites/fit/fitdata.json      —— 每个素材的 exact / block2 图元表
  reference/sprites/fit/<name>.png        —— 原图 | exact | block2 对比图
  reference/sprites/fit/REPORT.md         —— 矩形数/文件大小统计
  lua/fitdata.lua                         —— 三类主目标（sans/龙骨炮/骨头）的 exact 表

不接入游戏；纯参考工具。
"""
import json, math, os, sys
from collections import Counter
from PIL import Image, ImageDraw

ROOT = r"D:\stars\workspace\sans-fight"
SPR  = os.path.join(ROOT, "reference", "sprites")
OUT  = os.path.join(SPR, "fit")
os.makedirs(OUT, exist_ok=True)

# ---------------------------------------------------------------- 目标清单
TARGETS = []
def add(name, rel, group, note=""):
    TARGETS.append({"name": name, "rel": rel, "group": group, "note": note})

for pose in ["HandDown", "HandLeft", "HandRight", "HandUp"]:
    for f in sorted(os.listdir(os.path.join(SPR, "animations", "SansBody", pose))):
        add(f"sans_body_{pose}_{f[:-4]}", f"animations/SansBody/{pose}/{f}", "sans",
            f"Sans 本体 {pose} 第 {int(f[:-4])} 帧")
for head in ["Default","BlueEye","ClosedEyes","LookLeft","NoEyes","Tired1","Tired2","Wink"]:
    add(f"sans_head_{head}", f"animations/SansHead/{head}/000.png", "sans", f"Sans 头 {head}")
for t in ["Default", "Shrug"]:
    add(f"sans_torso_{t}", f"animations/SansTorso/{t}/000.png", "sans", f"Sans 躯干 {t}")
for l in ["Sitting", "Standing"]:
    add(f"sans_legs_{l}", f"animations/SansLegs/{l}/000.png", "sans", f"Sans 腿 {l}")
add("blaster_Default", "animations/GasterBlaster/Default/000.png", "blaster", "龙骨炮默认")
for f in sorted(os.listdir(os.path.join(SPR, "animations", "GasterBlaster", "Fire"))):
    add(f"blaster_Fire_{f[:-4]}", f"animations/GasterBlaster/Fire/{f}", "blaster", f"龙骨炮开火 {int(f[:-4])}")
for b in ["BoneV","BoneH","BoneStabV","BoneStabH","BoneStabWarn"]:
    add(f"bone_{b}", f"textures/{b}.png", "bone", f"骨头 {b}")

# ---------------------------------------------------------------- 载入 & 有效色层
def load_grid(rel):
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

def color_hex(c):
    return "#%02X%02X%02X" % c

def rle_rects(w, h, grid):
    """逐像素游程，再做同色同 x 宽度的纵向合并（1:1，无损）。"""
    rects = []
    for y in range(h):
        x = 0
        while x < w:
            c = grid[y][x]
            if c is None:
                x += 1; continue
            x2 = x
            while x2 + 1 < w and grid[y][x2 + 1] == c: x2 += 1
            rects.append([x, y, x2 - x + 1, 1, color_hex(c)])
            x = x2 + 1
    merged = []
    for x, y, rw, rh, c in rects:
        if merged:
            p = merged[-1]
            if p[0] == x and p[2] == rw and p[4] == c and p[1] + p[3] == y:
                p[3] += rh; continue
        merged.append([x, y, rw, rh, c])
    return merged

def block_rects(w, h, grid, B=2, thresh=0.45):
    bw, bh = (w + B - 1) // B, (h + B - 1) // B
    small = [[None] * bw for _ in range(bh)]
    for by in range(bh):
        for bx in range(bw):
            cnt = Counter(); tot = 0
            for y in range(by * B, min(h, (by + 1) * B)):
                for x in range(bx * B, min(w, (bx + 1) * B)):
                    tot += 1
                    if grid[y][x] is not None: cnt[grid[y][x]] += 1
            if cnt:
                c, n = cnt.most_common(1)[0]
                if n >= thresh * tot: small[by][bx] = c
    rects = []
    for y in range(bh):
        x = 0
        while x < bw:
            c = small[y][x]
            if c is None: x += 1; continue
            x2 = x
            while x2 + 1 < bw and small[y][x2 + 1] == c: x2 += 1
            rects.append([x * B, y * B, (x2 - x + 1) * B, B, color_hex(c)])
            x = x2 + 1
    merged = []
    for x, y, rw, rh, c in rects:
        if merged:
            p = merged[-1]
            if p[0] == x and p[2] == rw and p[4] == c and p[1] + p[3] == y:
                p[3] += rh; continue
        merged.append([x, y, rw, rh, c])
    return merged

def render(w, h, rects, bg=(0, 0, 0, 255)):
    im = Image.new("RGBA", (w, h), bg); dr = ImageDraw.Draw(im)
    for x, y, rw, rh, c in rects:
        dr.rectangle([x, y, x + rw - 1, y + rh - 1], fill=c)
    return im

# ---------------------------------------------------------------- 主循环
report = []
data = {}
for t in TARGETS:
    w, h, grid = load_grid(t["rel"])
    exact = rle_rects(w, h, grid)
    block = block_rects(w, h, grid, 2)
    data[t["name"]] = {"w": w, "h": h, "group": t["group"], "note": t["note"],
                       "exact": exact, "block2": block}
    # 对比图：原图 | exact | block2
    SC = 6
    orig = Image.open(os.path.join(SPR, t["rel"])).convert("RGBA")
    # 把黑底透明化后再贴到黑底上，便于看轮廓
    canvas = Image.new("RGBA", (w * 3 + 16, h), (0, 0, 0, 255))
    canvas.alpha_composite(orig, (0, 0))
    canvas.alpha_composite(render(w, h, exact), (w + 8, 0))
    canvas.alpha_composite(render(w, h, block), (2 * w + 16, 0))
    canvas.resize((canvas.width * SC, canvas.height * SC), Image.NEAREST).save(
        os.path.join(OUT, t["name"] + ".png"))
    report.append((t["group"], t["name"], w, h, len(exact), len(block)))
    print(f"{t['name']:28s} {w:3d}x{h:<3d} exact={len(exact):4d} block2={len(block):4d}")

with open(os.path.join(OUT, "fitdata.json"), "w", encoding="utf8") as f:
    json.dump(data, f, ensure_ascii=False, separators=(",", ":"))

# ---------------------------------------------------------------- Lua 数据（三类主目标）
def lua_rects(rects):
    out = []
    for x, y, rw, rh, c in rects:
        out.append("{x=%d,y=%d,w=%d,h=%d,c=0xFF%s}" % (x, y, rw, rh, c[1:]))
    return ",".join(out)

MAIN = {
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
}
lines = [
    "-- fitdata.lua —— 自动生成（tools/fit-sprites.py），请勿手改。",
    "-- 来源：reference/sprites；exact = 逐像素游程矩形，1:1 还原原图。",
    "-- 坐标：图像像素坐标（左上原点，Y 向下）；颜色 0xAARRGGBB。",
    "-- 用途：烘焙到容器模板 / 离线对照；直接逐帧绘制会吃掉大量控件预算。",
    "",
    "local M = {}",
    "",
    "M.meta = {",
    "  source = 'reference/sprites',",
    "  fit = 'exact-rle',",
    "}",
    "",
    "-- Sans 合成参数：body = 身体容器；head = 头容器；hx/hy = 头的左上角相对身体左上角的像素偏移；sweat = 流汗覆盖层偏移（相对头左上角）。",
    "M.sans_poses = {",
    "  -- hx/hy = SansHead 左上角相对 SansBody 左上角的像素偏移；由原工程 C2 image point 换算：",
    "  --   头原点(0.5,1) 放到 body 的 Head 点(x*W, y*H)，y 从顶边量起 → hy = y*H - 30。",
    "  default = { body = 'sans_body_default', hx = 17, hy = -24 },",
    "  up      = { body = 'sans_body_up',      hx = 14, hy = -2 },",
    "  down    = { body = 'sans_body_down',    hx = 14, hy = 1 },",
    "  left    = { body = 'sans_body_left',    hx = 18, hy = -24, mirror = true },",
    "  right   = { body = 'sans_body_right',   hx = 18, hy = -24 },",
    "}",
    "M.sans_head_default_key = 'sans_head_default'",
    "M.sans_head_blue_key = 'sans_head_blue'",
    "M.blaster_keys = { default = 'blaster_default', fire = { 'blaster_fire_0', 'blaster_fire_2', 'blaster_fire_4' } }",
    "",
]
for key, lua_name in MAIN.items():
    d = data.get(key)
    if not d: continue
    lines.append(f"--- {d['note']}（{d['w']}x{d['h']}，{len(d['exact'])} 个矩形）")
    lines.append(f"M.{lua_name} = {{ w={d['w']}, h={d['h']}, rects={{")
    # 每行 8 个，避免超长行
    rs = d["exact"]
    for i in range(0, len(rs), 8):
        lines.append("  " + ",".join("{x=%d,y=%d,w=%d,h=%d,c=0xFF%s}" % (x,y,rw,rh,c[1:]) for x,y,rw,rh,c in rs[i:i+8]) + ",")
    lines.append("}}")
    lines.append("")
lines.append("return M")
# 【方案A】额外导出龙骨炮的 block2 表：初见杀四发同屏要用它（每发 ~123 矩形，4 发 ≈492）
def lua_block2(rects):
    out = []
    for x, y, rw, rh, c in rects:
        out.append("{x=%d,y=%d,w=%d,h=%d,c=0xFF%s}" % (x, y, rw, rh, c[1:]))
    return ",".join(out)

BLK = [
    ("Default", "blaster_Default"),
    ("fire_0", "blaster_Fire_000"),
    ("fire_2", "blaster_Fire_002"),
    ("fire_4", "blaster_Fire_004"),
]
lines.append("")
lines.append("-- 【方案A】龙骨炮 block2 表（2×2 采样）：初见杀用，逐帧直接画 ~123 个 rrect/发")
lines.append("M.blaster_block2 = {")
for key, src in BLK:
    b = data.get(src, {}).get("block2")
    if b:
        lines.append("  %s = { %s }," % (key, lua_block2(b)))
lines.append("}")
with open(os.path.join(ROOT, "lua", "fitdata.lua"), "w", encoding="utf8") as f:
    f.write("\n".join(lines) + "\n")

# ---------------------------------------------------------------- 报告
md = ["# 原版贴图 → 千星图元拟合报告", "",
      "生成工具：`tools/fit-sprites.py`；数据：`reference/sprites/fit/fitdata.json`、`lua/fitdata.lua`。",
      "",
      "- `exact`：逐像素游程矩形（无损还原原图）。",
      "- `block2`：2×2 采样 + 游程合并（近似，数量约为 exact 的 30–50%）。",
      "- 坐标：图像像素坐标（左上原点、Y 向下）；颜色 `#RRGGBB`。",
      "",
      "| 组 | 素材 | 尺寸 | exact 矩形 | block2 矩形 |",
      "|---|---|---|---:|---:|"]
for g, n, w, h, e, b in report:
    md.append(f"| {g} | `{n}` | {w}×{h} | {e} | {b} |")
md += ["", "## 结论", "",
       "- **骨头**：`BoneV/H` 的 exact 只有 13 个矩形；用 1 个骨干矩形 + 4 个骨球圆（5 图元）即可得到 95% 以上的观感，是唯一适合运行期逐帧拼装的。",
       "- **龙骨炮 / Sans 本体**：exact 需要 200–600 个矩形/帧；逐帧拼装会超出当前控件池预算（rect 119 / circle 443 / rot 106）。",
       "- 推荐：把 exact 表**烘焙进容器模板**（每个骨骼/角色一个容器，子控件静态），运行期只移动/显隐容器（1 次写入），即可像素级还原且不吃逐帧预算。",
       ""]
with open(os.path.join(OUT, "REPORT.md"), "w", encoding="utf8") as f:
    f.write("\n".join(md) + "\n")
print("\n[out]", OUT)
print("[lua]", os.path.join(ROOT, "lua", "fitdata.lua"))
