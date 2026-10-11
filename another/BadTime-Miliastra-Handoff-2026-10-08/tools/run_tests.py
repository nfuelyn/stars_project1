"""Run game regression tests with Lua 5.3; no files outside this project are written."""
from pathlib import Path
import os
import sys
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
runtime = ROOT.parent / 'research' / 'runtime' / 'python'
if runtime.exists():
    sys.path.insert(0, str(runtime))
try:
    from lupa.lua53 import LuaRuntime
except ImportError:
    raise SystemExit('Install lupa into a project-local environment, then rerun this command.')

def make_lua():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('modules = {}; function require(name) return modules[name] end')
    for name in ('config', 'core', 'attacks', 'fitdata', 'textart', 'music', 'main'):
        module = lua.execute((ROOT / 'lua' / f'{name}.lua').read_text(encoding='utf-8'))
        lua.globals().modules[f'default_import_file/workspace/sans-fight/lua/{name}'] = module
        lua.globals()[name] = module
    return lua

lua = make_lua()
lua.execute((ROOT / 'tests/test_core.lua').read_text(encoding='utf-8'))
adapter_test = ROOT / 'tests/test_adapter.lua'
if adapter_test.exists():
    lua = make_lua()
    lua.execute(adapter_test.read_text(encoding='utf-8'))
    lua = make_lua()
    mock = adapter_test.read_text(encoding='utf-8').split('config.audio.bgm=501')[0]
    lua.execute(mock + '\n' + (ROOT / 'tests/test_render_flow.lua').read_text(encoding='utf-8'))
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute((ROOT / 'main.lua').read_text(encoding='utf-8'))
print('PASS generated standalone script loads in Lua 5.3')
