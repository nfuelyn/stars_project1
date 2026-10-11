#!/usr/bin/env node
// tools/sync-sandbox.mjs —— 把存档里内嵌的「自足包」写到千星客户端的 external_lua_file/main.lua
//
// 背景：千星试玩读的是客户端脚本目录下的 main.lua，内容 = 当前存档
//       assets.scripts[0].source（build-save.mjs 生成的自足包：main + core + attacks + textart）。
//       手工复制容易漏（历史事故：改了 lua/*.lua 却没重建/没覆盖 → 试玩里还是旧包）。
//
// 用法：
//   node tools/build-save.mjs && node tools/sync-sandbox.mjs
//   自定义目标：SANDBOX_MAIN="D:/tmp/main.lua" node tools/sync-sandbox.mjs
//
// 退出码：0 = 已写入且校验通过；1 = 存档缺失/自足包异常；2 = 目标目录不存在（只提示，不算错）

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import url from 'node:url';

const HERE = path.dirname(url.fileURLToPath(import.meta.url));
const PROJ = path.dirname(HERE);
const SAVE = path.join(PROJ, 'sans-fight.save.json');

const DEFAULT_SANDBOX =
  'C:/Users/19637/AppData/LocalLow/miHoYo/原神/BeyondLocal/248255821/' +
  'Beyond_Local_Save_Level/1073741827/external_lua_file/main.lua';
const TARGET = process.env.SANDBOX_MAIN || DEFAULT_SANDBOX;

const sha = (s) => crypto.createHash('sha256').update(s, 'utf8').digest('hex');

if (!fs.existsSync(SAVE)) {
  console.error(`[sync] 找不到存档 ${SAVE} —— 先跑 node tools/build-save.mjs`);
  process.exit(1);
}

const save = JSON.parse(fs.readFileSync(SAVE, 'utf8'));
const scripts = (save.assets && save.assets.scripts) || [];
let best = null;
for (const s of scripts) {
  if (typeof s.source === 'string' && (!best || s.source.length > best.source.length)) best = s;
}
if (!best) {
  console.error('[sync] 存档里没有可用的脚本自足包');
  process.exit(1);
}

const src = best.source;
const build = (src.match(/local BUILD = '([^']+)'/) || [])[1] || '(未找到 BUILD 标记)';
if (!/function\s+[A-Za-z_.:]*OnStart/.test(src)) {
  console.warn('[sync] 警告：自足包里没找到 OnStart，可能不是适配层入口');
}

const target = path.resolve(TARGET);
const dir = path.dirname(target);
if (!fs.existsSync(dir)) {
  console.error(`[sync] 目标目录不存在：${dir}`);
  console.error('[sync] 请确认千星客户端脚本目录（见 workspace/sans-fight/docs/device-setup.md 5.4）');
  process.exit(2);
}

let before = null;
if (fs.existsSync(target)) {
  const old = fs.readFileSync(target, 'utf8');
  before = { len: old.length, sha: sha(old), build: (old.match(/local BUILD = '([^']+)'/) || [])[1] || null };
}

fs.writeFileSync(target, src, 'utf8');
const after = fs.readFileSync(target, 'utf8');

console.log(`[sync] 存档自足包  id=${best.id} guid=${best.guid}`);
console.log(`[sync]   chars=${src.length}  sha256=${sha(src)}`);
console.log(`[sync]   BUILD=${build}`);
if (before) {
  console.log(`[sync] 覆盖前      chars=${before.len}  sha256=${before.sha}  BUILD=${before.build}`);
  console.log(`[sync] 变化        ${before.sha === sha(src) ? '无（内容一致）' : '已更新'}`);
} else {
  console.log('[sync] 覆盖前      目标不存在（新建）');
}
if (after !== src) {
  console.error('[sync] 写入后回读不一致，请检查磁盘');
  process.exit(1);
}
console.log(`[sync] 已写入 ${target}`);
console.log('[sync] 千星里请「完全退出试玩再重进」；日志首行应为 main start: build=' + build);