"""Build the only script that should be imported into the official client."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PREFIX = 'default_import_file/workspace/sans-fight/lua/'
parts = [
    '-- 自动生成：修改 lua/*.lua 后运行 python tools/build.py。\n',
    '-- 配置位于脚本开头的 config 模块；无需 require 或外部文件。\n',
    'local __modules = {}\n',
    'local function require(p) return __modules[p] end\n\n',
]
for name in ('config', 'core', 'attacks', 'fitdata', 'textart', 'music', 'main'):
    parts.append(f"__modules['{PREFIX}{name}'] = (function()\n")
    parts.append((ROOT / 'lua' / f'{name}.lua').read_text(encoding='utf-8'))
    parts.append('\nend)()\n\n')
parts.append(f"local M = __modules['{PREFIX}main']\n")
parts.append('local function call(name, ...)\n  if M and M[name] then return M[name](...) end\nend\n')
for name in ('OnInit', 'OnEnable', 'OnStart', 'OnUpdate', 'OnLevelUpdate', 'OnDisable', 'OnDestroy'):
    args = 'dt' if name in ('OnUpdate', 'OnLevelUpdate') else ''
    tail = ', dt' if args else ''
    parts.append(f"function {name}({args}) return call('{name}'{tail}) end\n")
(ROOT / 'main.lua').write_text(''.join(parts), encoding='utf-8')
print('Built main.lua')
