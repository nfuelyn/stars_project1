#!/usr/bin/env node
/* ============================================================================
 * gen-attacks.mjs —— 把 prototype/attacks/*.csv 生成 lua/attacks.lua
 * ---------------------------------------------------------------------------
 * 用法：node D:\stars\workspace\sans-fight\tools\gen-attacks.mjs
 *
 * CSV 文本一律用 **Lua 长括号字符串** [==[ ... ]==] 包裹：
 *   - 选 2 层等号：CSV 里出现的 `]]`（如 `]]` 或 `]=]`）不会截断字符串
 *   - 生成时仍做一次安全校验：若正文包含 `]==]`，就自动升到更多等号
 *   - 只做 \r\n -> \n 与剔除 BOM，其余字节原样保留（含中文注释）
 * 不手抄：数据只有一个来源，就是这些 CSV 文件。
 * ========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..');
const SRC_DIR = path.join(ROOT, 'prototype', 'attacks');
const OUT = path.join(ROOT, 'lua', 'attacks.lua');

/** 生成安全的 Lua 长括号字符串字面量 */
function longString(text) {
  let level = 2;                                   // 从 [==[ 起
  const closer = () => ']' + '='.repeat(level) + ']';
  while (text.includes(closer())) level++;
  const open = '[' + '='.repeat(level) + '[';
  return { lit: open + '\n' + text + (text.endsWith('\n') ? '' : '\n') + closer(), level };
}

const files = fs.readdirSync(SRC_DIR).filter((f) => f.endsWith('.csv')).sort();
if (!files.length) {
  console.error('没有找到 CSV：' + SRC_DIR);
  process.exit(1);
}

const entries = [];
for (const f of files) {
  const name = path.basename(f, '.csv');
  let text = fs.readFileSync(path.join(SRC_DIR, f), 'utf8');
  if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);          // 去 BOM
  text = text.replace(/\r\n?/g, '\n');
  if (!text.endsWith('\n')) text += '\n';
  entries.push({ name, text, file: f });
}

let body = '';
const usedLevels = [];
for (const e of entries) {
  const { lit, level } = longString(e.text);
  usedLevels.push(level);
  body += `  { name = ${JSON.stringify(e.name)}, csv = ${lit} },\n`;
}

const now = new Date().toISOString().slice(0, 10);
const out = `--[[ ==========================================================================
  attacks.lua —— 攻击脚本数据（**自动生成，请勿手改**）
  ---------------------------------------------------------------------------
  生成器：tools/gen-attacks.mjs
  来源：  prototype/attacks/*.csv（${entries.length} 个）
  生成日期：${now}

  每项 = { name = "sans_xxx", csv = <该 CSV 的全文> }
  core.lua 通过 M.newGame({ scripts = require("attacks") }) 注入使用；
  也接受任意同构的表（便于测试注入自制脚本）。
  长括号层级：[${'='.repeat(Math.max(...usedLevels))}[ ... ]${'='.repeat(Math.max(...usedLevels))}]
  ========================================================================== ]]

local M = {
${body}}

return M
`;

fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, out, 'utf8');

console.log(`已生成 ${OUT}`);
console.log(`脚本 ${entries.length} 个：` + entries.map((e) => e.name).join(', '));
console.log(`长括号层级：` + usedLevels.join('/'));
