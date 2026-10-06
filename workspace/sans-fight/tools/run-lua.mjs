#!/usr/bin/env node
/* ============================================================================
 * run-lua.mjs —— 用 fengari（Lua 5.3 语义）跑 sans-fight/lua 下的自测
 * ---------------------------------------------------------------------------
 * 用法：node D:\stars\workspace\sans-fight\tools\run-lua.mjs [脚本相对路径]
 *   默认脚本：lua/core_selftest.lua
 *
 * 为什么需要它：core.lua 的目标语义是 Lua 5.3（fengari），而本机只有
 * D:\5.1\lua.exe（Lua 5.1）。core.lua 里做了位运算 / math.atan 的兼容层，
 * 所以两个运行时都能跑；本启动器用于验证"目标运行时"。
 *
 * fengari 位于 D:\my-dsh\profiles\web\node_modules（本机唯一安装点），
 * 用 createRequire 从那里解析，不污染项目依赖。
 * ========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..');
const FENGARI_HOME = process.env.FENGARI_HOME || 'D:\\my-dsh\\profiles\\web';

const require = createRequire(path.join(FENGARI_HOME, 'noop.js'));
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');

const rel = process.argv[2] || 'lua/core_selftest.lua';
const target = path.resolve(ROOT, rel);
if (!fs.existsSync(target)) {
  console.error('找不到脚本：' + target);
  process.exit(2);
}

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
/* 只放行项目根作为 require 的搜索路径（自测需要 require('core') / require('attacks')）。
   这里**不改写脚本里的 require 字面量**——改 package.path 更安全，
   而且 Windows 路径里的 ':' 不会污染 LUA_PATH 的分隔符解析。
   注入后这些写法都能解析：
     require('core')            （lua/ 在 path 里，配合脚本自己补的路径）
     require('lua' .. '.core')
     require('lua/core') */
lua.lua_pushstring(L, to_luastring(ROOT));
lua.lua_setglobal(L, to_luastring('LUA_ROOT'));
lauxlib.luaL_dostring(L, to_luastring(
  `package.path = LUA_ROOT .. '/?.lua;' .. LUA_ROOT .. '/?/init.lua;' .. LUA_ROOT .. '/lua/?.lua;' .. package.path`));

const src = fs.readFileSync(target, 'utf8').replace(/^\uFEFF/, '');

const status = lauxlib.luaL_dostring(L, to_luastring(src));
if (status !== lua.LUA_OK) {
  const msg = lua.lua_tostring(L, -1);
  if (!msg) {
    console.error('LUA ERROR: (non-string error)');
  } else {
    // 错误信息里可能带非法 UTF-8（例如 Lua 侧拼了被按字节切断的中文），
    // to_jsstring 会直接抛 RangeError 把真正的 Lua 错误盖掉 —— 这里自己转，坏字节换成 \xNN。
    let text = '';
    try {
      text = to_jsstring(msg);
    } catch (_e) {
      for (let i = 0; i < msg.length; i++) {
        const b = msg[i];
        text += b < 0x80
          ? String.fromCharCode(b)
          : '\\x' + b.toString(16).padStart(2, '0');
      }
      text += '   ←（含非法 UTF-8 字节，已转义；很可能是中文被按字节切断）';
    }
    console.error('LUA ERROR: ' + text);
  }
  process.exit(1);
}
