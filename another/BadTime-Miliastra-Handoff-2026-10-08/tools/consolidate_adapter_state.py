"""Keep the adapter below Lua 5.3's 200 locals per function limit."""
from pathlib import Path
import re
p = Path(__file__).resolve().parents[1] / 'lua' / 'main.lua'
s = p.read_text(encoding='utf-8')
s = s.replace("local config = require('default_import_file/workspace/sans-fight/lua/config') or {}",
              "M.config = require('default_import_file/workspace/sans-fight/lua/config') or {}")
s = s.replace('local ownedControls, keyListeners = {}, {}', 'M.runtime = {}')
s = s.replace('local started, enabled = false, true', '')
s = s.replace('local colorCache = {}', '')
s = s.replace('local heldConfirm, heldCancel, heldDirections = {}, {}, {}', '')
s = s.replace('local cancelHeld = false', '')
s = s.replace('local function enumValue(', 'function M.enumValue(')
s = s.replace('local function apiColor(', 'function M.apiColor(')
s = s.replace('local function clearInput()', 'function M.clearInput()')
for name in ('enumValue', 'apiColor', 'clearInput', 'config'):
    s = re.sub(r'(?<![.\w])' + name + r'\b', 'M.' + name, s)
s = s.replace('/M.config\'', '/config\'')
for name in ('ownedControls', 'keyListeners', 'started', 'enabled', 'colorCache',
             'heldConfirm', 'heldCancel', 'heldDirections', 'cancelHeld'):
    s = re.sub(r'(?<![.\w])' + name + r'\b', 'M.runtime.' + name, s)
s = s.replace('M.runtime = {}', '''M.runtime = {
  ownedControls = {}, keyListeners = {}, started = false, enabled = true,
  colorCache = {}, heldConfirm = {}, heldCancel = {}, heldDirections = {}, cancelHeld = false,
}''')
p.write_text(s, encoding='utf-8')
print('Consolidated adapter state')
