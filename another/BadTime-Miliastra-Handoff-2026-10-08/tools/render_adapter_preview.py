"""Render the adapter's actual mock control tree. These are offline previews, not game screenshots."""
from pathlib import Path
import json
import math
import sys
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parent / 'research' / 'runtime' / 'python'))
from lupa.lua53 import LuaRuntime
from PIL import Image, ImageDraw, ImageFont

OUT = ROOT / 'docs' / 'previews'
OUT.mkdir(parents=True, exist_ok=True)
W, H = 1280, 720


def session(round_number=None):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('modules={}; function require(name) return modules[name] end')
    for name in ('config', 'core', 'attacks', 'fitdata', 'textart', 'music', 'main'):
        module = lua.execute((ROOT / 'lua' / f'{name}.lua').read_text(encoding='utf-8'))
        lua.globals().modules[f'default_import_file/workspace/sans-fight/lua/{name}'] = module
        lua.globals()[name] = module
    mock = (ROOT / 'tests' / 'test_adapter.lua').read_text(encoding='utf-8').split('config.audio.bgm=501')[0]
    handles = lua.execute(mock + '\nreturn {root=root,controls=controls,logs=logs}')
    lua.execute('main.OnInit(); main.OnStart(); main.OnLevelUpdate(1/60)')
    if round_number is not None:
        lua.execute(f'local g=main.state();g.bootRound={round_number};core.titleChoose(g,nil);g.hurt=function() return false end')
    return lua, handles


def render(handles, filename):
    im = Image.new('RGBA', (W, H), (0, 0, 0, 255))
    counts = {}

    def color(c):
        if c is None:
            return (255, 255, 255, 255)
        return tuple(int(c[k]) for k in ('r', 'g', 'b', 'a'))

    def visit(c, parent, is_root=False):
        if c['alive'] is False or c['active'] is False or c['visible'] is False:
            return
        px, py, pw, ph = parent
        if is_root:
            x, y, w, h = 0, 0, W, H
        else:
            aminx, aminy = c['ax0'] or 0, c['ay0'] or 0
            amaxx, amaxy = c['ax1'] or aminx, c['ay1'] or aminy
            pivotx, pivoty = c['px'] or 0, c['py'] or 0
            w = (c['w'] or 0) + pw * (amaxx - aminx)
            h = (c['h'] or 0) + ph * (amaxy - aminy)
            x = px + pw * (aminx + (amaxx - aminx) * pivotx) + (c['x'] or 0) - w * pivotx
            y = py + ph * (aminy + (amaxy - aminy) * pivoty) + (c['y'] or 0) - h * pivoty
        kind = c['kind'] or 'container'
        counts[kind] = counts.get(kind, 0) + 1
        if kind in ('rect', 'rot', 'circle', 'ring', 'rtri') and w > 0 and h > 0:
            rgba = color(c['imageColor'])
            overlay = Image.new('RGBA', im.size)
            d = ImageDraw.Draw(overlay)
            # Image controls rotate counter-clockwise in bottom-left canvas space.
            rotation = math.radians(c['rotation'] or 0)
            qx, qy = c['px'] or 0, c['py'] or 0
            ox, oy = x + qx * w, y + qy * h
            def point(lx, ly):
                dx, dy = lx - qx * w, ly - qy * h
                return (ox + dx * math.cos(rotation) - dy * math.sin(rotation),
                        H - (oy + dx * math.sin(rotation) + dy * math.cos(rotation)))
            if kind == 'rtri':
                points = [point(0, 0), point(w, 0), point(w / 2, h)]
            elif kind in ('circle', 'ring'):
                points = [point(w / 2 + w / 2 * math.cos(n * math.tau / 48),
                                h / 2 + h / 2 * math.sin(n * math.tau / 48)) for n in range(48)]
            else:
                points = [point(0, 0), point(w, 0), point(w, h), point(0, h)]
            if kind == 'ring':
                d.line(points + points[:1], fill=rgba, width=3)
            else:
                d.polygon(points, fill=rgba)
            im.alpha_composite(overlay)
        elif kind == 'text' and c['text']:
            fs = max(1, int(c['fontSize'] or 18))
            font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', fs)
            align = c['horizontalAlignment']['name'] if c['horizontalAlignment'] else 'Left'
            text = c['text']
            d = ImageDraw.Draw(im)
            length = d.textlength(text, font=font)
            tx = x + ((w - length) / 2 if align == 'Middle' else (w - length if align == 'Right' else 0))
            d.text((tx, H - y - h), text, font=font, fill=color(c['fontColor']), anchor='lt')
        for _, child in c['children'].items():
            visit(child, (x, y, w, h))

    visit(handles['root'], (0, 0, W, H), True)
    im.convert('RGB').save(OUT / filename)
    errors = [s for _, s in handles['logs'].items() if ' ERR ' in s or '监听注册失败' in s]
    assert not errors, errors
    return {'file': filename, 'visibleControls': counts, 'errors': errors}


report = []
lua, handles = session()
report.append(render(handles, 'adapter-title.png'))
lua.execute("main.setPaused(true); main.OnLevelUpdate(1/60)")
report.append(render(handles, 'adapter-paused.png'))
lua, handles = session(1)
lua.execute('for i=1,85 do core.update(main.state(),{},1/60) end; main.OnLevelUpdate(0)')
report.append(render(handles, 'adapter-opening-stab.png'))
lua.execute("main.state().state='menu';main.OnLevelUpdate(0)")
report.append(render(handles, 'adapter-menu.png'))
lua, handles = session(1)
lua.execute('for i=1,290 do core.update(main.state(),{},1/60) end; main.OnLevelUpdate(1/60)')
report.append(render(handles, 'adapter-opening.png'))
lua, handles = session(4)
lua.execute('for i=1,270 do core.update(main.state(),{},1/60) end; main.OnLevelUpdate(1/60)')
report.append(render(handles, 'adapter-platform.png'))
lua, handles = session(23)
lua.execute('''
for i=1,9000 do
  local g=main.state();core.update(g,{},1/60)
  if g.world and #g.world.blasters>=8 and g.world.blasters[1].lod=='block3' then break end
end
main.OnLevelUpdate(1/60)
''')
report.append(render(handles, 'adapter-final.png'))
lua.execute("main.state():finish('fail');main.OnLevelUpdate(1/60)")
report.append(render(handles, 'adapter-result.png'))
(OUT / 'adapter-validation.json').write_text(json.dumps({'offline': True, 'mockAPI': True, 'scenes': report}, ensure_ascii=False, indent=2), encoding='utf-8')
print('PASS actual adapter control tree: eight offline previews, no API/draw errors')
