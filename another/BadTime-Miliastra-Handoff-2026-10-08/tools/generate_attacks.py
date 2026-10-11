"""Use the public BTS CSVs verbatim; only their module names are aliased."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
aliases = {
    'sans_final': 'final', 'sans_multi1': 'multi1', 'sans_multi2': 'multi2',
    'sans_multi3': 'multi3', 'sans_randomblaster1': 'randomblaster1',
    'sans_randomblaster2': 'randomblaster2',
}
parts = ['-- 数据来源：https://github.com/Jcw87/c2-sans-fight/tree/master/Files\n',
         '-- CSV 保持下载时的原文；无中轴销毁、加宽光束或额外停留时间。\nlocal M = {\n']
files = sorted((ROOT / 'reference' / 'upstream').glob('*.csv'))
assert len(files) == 24
for path in files:
    name = aliases.get(path.stem, path.stem.removeprefix('sans_')
                       if path.stem.startswith('sans_platform') else path.stem)
    csv = path.read_text(encoding='utf-8-sig')
    assert ']==]' not in csv
    parts.append(f'  {{ name = "{name}", csv = [==[\n{csv}\n]==] }},\n')
parts.append('}\nreturn M\n')
(ROOT / 'lua' / 'attacks.lua').write_text(''.join(parts), encoding='utf-8')
print('Generated 24 upstream attacks')
