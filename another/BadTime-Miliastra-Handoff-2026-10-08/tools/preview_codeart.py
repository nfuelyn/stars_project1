"""Validate standalone Lua CodeArt recipes and render user-facing PNG previews."""
from __future__ import annotations
import json
import math
from pathlib import Path
import sys
sys.dont_write_bytecode = True
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parent / 'research' / 'runtime' / 'python'))
from lupa.lua53 import LuaRuntime

OUT = ROOT / 'docs' / 'previews'
OUT.mkdir(parents=True, exist_ok=True)
lua = LuaRuntime(unpack_returned_tuples=True)
fit = lua.execute((ROOT / 'lua' / 'fitdata.lua').read_text(encoding='utf-8'))
is_table = lua.eval('function(v) return type(v) == "table" end')
font = ImageFont.truetype('C:/Windows/Fonts/consola.ttf', 15)
small_font = ImageFont.truetype('C:/Windows/Fonts/consola.ttf', 12)

def read_spec(s):
    return {'w': s['w'], 'h': s['h'], 'rects': [dict(r.items()) for _, r in s['rects'].items()]}

assets = {k: read_spec(v) for k, v in fit.items() if is_table(v) and v['rects'] is not None}
for name, s in assets.items():
    assert s['w'] > 0 and s['h'] > 0, name
    for r in s['rects']:
        assert all(math.isfinite(r[k]) for k in ('x', 'y', 'w', 'h')), (name, r)
        assert r['w'] > 0 and r['h'] > 0, (name, r)
        assert r['x'] >= 0 and r['y'] >= 0, (name, r)
        assert r['x'] + r['w'] <= s['w'] + 1e-7, (name, r)
        assert r['y'] + r['h'] <= s['h'] + 1e-7, (name, r)
        assert isinstance(r['c'], int) and 0 < r['c'] <= 0xFFFFFFFF, (name, r)

required = ['sans_body_' + p for p in ('default', 'up', 'down', 'left', 'right')]
required += ['sans_head_default', 'sans_head_blue', 'blaster_default', 'blaster_fire_0', 'blaster_fire_2', 'blaster_fire_4']
assert all(k in assets for k in required)
assert len({json.dumps(assets[k], sort_keys=True) for k in ('blaster_default','blaster_fire_0','blaster_fire_2','blaster_fire_4')}) == 4
assert len({json.dumps(assets[fit['sans_head_keys'][k]], sort_keys=True) for k in ('Default','BlueEye','ClosedEyes','NoEyes','Tired1','Tired2')}) == 6
for letter in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789':
    assert json.dumps(read_spec(fit['codeart']['pixelText'](letter)),sort_keys=True) != json.dumps(read_spec(fit['codeart']['pixelText']('?')),sort_keys=True), letter
for pose, p in fit['sans_poses'].items():
    # Original SANS_H is 148; every pose has the same visible head-to-feet height.
    b = assets[p['body']]
    assert b['h'] - p['hy'] == 94, pose

def rgba(c):
    return ((c >> 16) & 255, (c >> 8) & 255, c & 255, (c >> 24) & 255)

def render(s, scale=1):
    img = Image.new('RGBA', (max(1, round(s['w'] * scale)), max(1, round(s['h'] * scale))), (0,0,0,0))
    d = ImageDraw.Draw(img)
    for r in s['rects']:
        x, y = round(r['x'] * scale), round(r['y'] * scale)
        x1, y1 = round((r['x']+r['w'])*scale)-1, round((r['y']+r['h'])*scale)-1
        if x1 >= x and y1 >= y:
            d.rectangle((x,y,x1,y1), fill=rgba(r['c']))
    return img

def put(img, key, x, y, scale=1):
    img.alpha_composite(render(assets[key], scale), (round(x), round(y)))

def title(d, x, y, text):
    d.text((x, y), text, fill='#A7C0E0', font=font)

def sans(img, pose, x, feet, head='Default', tired=False, scale=2, sweat=0):
    p = fit['sans_poses'][pose]
    key = fit['sans_body_variants'][pose+'_tired'] if tired else p['body']
    b = assets[key]
    hkey = fit['sans_head_keys'][head]
    h = assets[hkey]
    body_img = render(b, scale)
    head_img = render(h, scale)
    bx, by = x-b['w']*scale/2, feet-b['h']*scale
    hx = p['hx'] if not p['mirror'] else b['w']-p['hx']-h['w']
    if p['mirror']:
        body_img = body_img.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        head_img = head_img.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    img.alpha_composite(body_img, (round(bx),round(by)))
    img.alpha_composite(head_img, (round(bx+hx*scale),round(by+p['hy']*scale)))
    for i in range(sweat):
        put(img,'sans_sweat',bx+hx*scale+h['w']*scale+i*7*scale,by+p['hy']*scale+(i*6+3)*scale,scale*.6)

characters = Image.new('RGBA', (1280, 980), '#090D13')
d = ImageDraw.Draw(characters)
title(d,24,18,'CODEART / SANS: complete body, aligned feet, six face states')
for i, pose in enumerate(('default','up','down','left','right')):
    x=128+i*256
    sans(characters,pose,x,260,'BlueEye' if i>0 else 'Default',scale=2)
    title(d,x-88,280,pose+' / CodeArt')
for i,head in enumerate(('Default','BlueEye','ClosedEyes','NoEyes','Tired1','Tired2')):
    x=110+i*210
    sans(characters,'default',x,520,head,tired=i>=4,scale=1.8,sweat=2 if i>=4 else 0)
    title(d,x-75,540,head)
title(d,24,584,'GASTER BLASTER / closed + 3 jaw-open states; full detail, 2px LOD, 3px LOD')
lod_counts={}
for row, block in enumerate((None,'blaster_block2','blaster_block3')):
    for col,(label,key) in enumerate((('Default','blaster_default'),('fire_0','blaster_fire_0'),('fire_2','blaster_fire_2'),('fire_4','blaster_fire_4'))):
        if block:
            s={'w':57,'h':44,'rects':[dict(r.items()) for _,r in fit[block][label].items()]}
            lod_counts[block+'/'+label]=len(s['rects'])
            for r in s['rects']:
                assert r['x']+r['w']<=57 and r['y']+r['h']<=44
        else:
            s=assets[key]
        characters.alpha_composite(render(s,2), (78+col*314,622+row*112))
        title(d,202+col*314,647+row*112,f'{label}\n{len(s["rects"])} rects')
characters.convert('RGB').save(OUT/'codeart-characters.png')

keys = sorted(assets)
atlas = Image.new('RGBA', (1280, math.ceil(len(keys)/5)*190+44), '#090D13')
d = ImageDraw.Draw(atlas)
title(d,20,12,'CODEART / ALL RECIPE ASSETS (illustration; native Chinese labels are not pixel fonts)')
for i,key in enumerate(keys):
    s=assets[key];x=(i%5)*256;y=(i//5)*190+44
    d.rectangle((x+6,y+5,x+250,y+180),outline='#20334B')
    scale=min(3,228/s['w'],135/s['h'])
    icon=render(s,scale)
    atlas.alpha_composite(icon,(x+(256-icon.width)//2,y+12+(135-icon.height)//2))
    d.text((x+12,y+148),key,fill='#CCE3FF',font=small_font)
    d.text((x+12,y+163),f'{s["w"]} x {s["h"]} / {len(s["rects"])} rectangles',fill='#7E9CBA',font=small_font)
atlas.convert('RGB').save(OUT/'codeart-elements.png')

# A composed example using only generated rectangles. This is an illustration, not a client screenshot.
scene=Image.new('RGBA',(640,480),'black')
sans(scene,'default',320,207,'BlueEye',scale=1.6)
put(scene,'battle_frame',238,225)
put(scene,'soul_red',312,307)
put(scene,'bone_white_v',270,321)
put(scene,'bone_blue_v',374,281)
put(scene,'bone_orange_h',285,252)
put(scene,'platform_green',282,353)
for x,key in ((270,'HP'),(400,'KR')):
    scene.alpha_composite(render(read_spec(fit['codeart']['pixelText'](key)),2),(x,407))
put(scene,'hp_kr_bar',298,404)
for i,label in enumerate(('FIGHT','ACT','ITEM','MERCY')):
    box=read_spec(fit['codeart']['menuButton'](140,36,i==0))
    scene.alpha_composite(render(box),(20+i*155,437))
    text=read_spec(fit['codeart']['pixelText'](label,0xFFFFD200))
    scene.alpha_composite(render(text,2),(55+i*155,449))
scene.resize((1280,960),Image.Resampling.NEAREST).convert('RGB').save(OUT/'codeart-scene.png')

report={'validated':True,'lua':'5.3','asset_count':len(assets),'asset_rectangles':{k:len(v['rects']) for k,v in sorted(assets.items())},'blaster_lod_rectangles':lod_counts,'recipe_file_bytes':(ROOT/'lua'/'fitdata.lua').stat().st_size,'preview_images':['codeart-characters.png','codeart-elements.png','codeart-scene.png'],'preview_kind':'offline recipe render, not a game/sandbox screenshot'}
(OUT/'codeart-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report,ensure_ascii=False,indent=2))
