"""Recover editable modules from the supplied, self-contained client script."""
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
source = ROOT / 'main.lua'
(ROOT / 'reference').mkdir(exist_ok=True)
backup = ROOT / 'reference' / 'main.original.lua'
if not backup.exists():
    shutil.copy2(source, backup)
text = backup.read_text(encoding='utf-8-sig')
(ROOT / 'lua').mkdir(exist_ok=True)
pattern = r"__modules\['[^']+/([^/']+)'\] = \(function\(\)\n(.*?)\nend\)\(\)"
modules = re.findall(pattern, text, re.S)
assert len(modules) == 5, f'Expected 5 modules, got {len(modules)}'
for name, body in modules:
    (ROOT / 'lua' / f'{name}.lua').write_text(body + '\n', encoding='utf-8')
print('Recovered:', ', '.join(name for name, _ in modules))
