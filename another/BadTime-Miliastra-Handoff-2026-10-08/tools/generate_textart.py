"""Bake project text into rectangle recipes; runtime needs no text/font asset."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'research/runtime/python'))
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
chars = set(chr(i) for i in range(32, 127))
for file in (ROOT / 'lua').glob('*.lua'):
    if file.name != 'textart.lua':
        chars.update(c for c in file.read_text(encoding='utf-8') if ord(c) > 127)
font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 16)
mono = ImageFont.truetype('C:/Windows/Fonts/consola.ttf', 16)
lines = ['-- Generated rectangle glyphs: no runtime font or text template required.\nlocal T = { height = 20, glyphs = {} }\n']
for char in sorted(chars):
    f = mono if ord(char) < 127 else font
    width = max(1, round(f.getlength(char)))
    im = Image.new('L', (width + 2, 20))
    ImageDraw.Draw(im).text((0, 0), char, font=f, fill=255)
    rects, previous = [], {}
    for y in range(20):
        runs, x = {}, 0
        while x < im.width:
            if im.getpixel((x, y)) < 96:
                x += 1
                continue
            start = x
            while x < im.width and im.getpixel((x, y)) >= 96:
                x += 1
            key = (start, x - start)
            if key in previous:
                idx = previous[key]
                rects[idx][3] += 1
            else:
                idx = len(rects)
                rects.append([start, y, x - start, 1])
            runs[key] = idx
        previous = runs
    encoded = ','.join('{' + ','.join(map(str, r)) + '}' for r in rects)
    lines.append(f'T.glyphs[{ord(char)}] = {{w={width+2}, advance={width}, rects={{{encoded}}}}}\n')
lines.append('return T\n')
(ROOT / 'lua/textart.lua').write_text(''.join(lines), encoding='utf-8')
print(f'Generated {len(chars)} CodeArt text glyphs')
