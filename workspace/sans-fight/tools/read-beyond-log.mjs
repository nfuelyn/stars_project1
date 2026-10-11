#!/usr/bin/env node
/* ===========================================================================
 * read-beyond-log.mjs —— 从「原神·千星」客户端调试日志（.gia）里抽脚本日志行
 * ---------------------------------------------------------------------------
 * 背景：游戏把客户端脚本日志按会话写进
 *   C:\Users\<你>\AppData\LocalLow\miHoYo\原神\BeyondLocal\<uid>\Beyond_Debug_Log\<日期>_<时间>_<序号>_<uid>.gia
 * 这是 protobuf 容器（带二进制字段头），但**日志正文是明文**，所以可以直接扫出来。
 *
 * 用法：
 *   node tools/read-beyond-log.mjs                  # 读最新的一次会话
 *   node tools/read-beyond-log.mjs --list           # 列出最近的日志文件
 *   node tools/read-beyond-log.mjs --file <路径>
 *   node tools/read-beyond-log.mjs --grep 'diag|geom|警告|ERR'   # 只看匹配行
 *   node tools/read-beyond-log.mjs --all            # 不过滤，全部正文行
 * =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';

const UID = process.env.BEYOND_UID || '248255821';
const DIR = process.env.BEYOND_LOG_DIR ||
  path.join(process.env.USERPROFILE || 'C:/Users/19637', 'AppData/LocalLow/miHoYo/原神/BeyondLocal', UID, 'Beyond_Debug_Log');

const argv = process.argv.slice(2);
const argOf = (k, d) => { const i = argv.indexOf(k); return i >= 0 && argv[i + 1] ? argv[i + 1] : d; };

if (!fs.existsSync(DIR)) { console.error('找不到日志目录：' + DIR); process.exit(2); }
const files = fs.readdirSync(DIR).filter((f) => f.endsWith('.gia'))
  .map((f) => ({ f, p: path.join(DIR, f), m: fs.statSync(path.join(DIR, f)).mtimeMs }))
  .sort((a, b) => b.m - a.m);

if (argv.includes('--list')) {
  console.log('日志目录：' + DIR);
  for (const x of files.slice(0, 15)) {
    console.log(`  ${new Date(x.m).toLocaleString()}  ${(fs.statSync(x.p).size / 1024).toFixed(1)} KB  ${x.f}`);
  }
  process.exit(0);
}

const target = argOf('--file', '') || (files[0] && files[0].p);
if (!target) { console.error('目录里没有 .gia 日志'); process.exit(2); }

// 正文行：从 'main: ' / 'music: ' / 'boot: ' / '警告' 等开头，读到下一个控制字符为止
const buf = fs.readFileSync(target);
const text = buf.toString('latin1');           // 1 字节 = 1 字符，避免 UTF-8 截断报错
const re = /(main: |music: |boot: |main init: )[^\x00-\x08\x0B\x0C\x0E-\x1F]{0,400}/g;
const lines = [];
let m;
while ((m = re.exec(text)) !== null) {
  // 把 latin1 还原成 UTF-8 文本
  const raw = Buffer.from(m[0], 'latin1').toString('utf8');
  lines.push(raw.replace(/\uFFFD+$/, ''));
}
const grep = argOf('--grep', '');
const showAll = argv.includes('--all');
const out = lines.filter((l) => {
  if (showAll) return true;
  if (grep) return new RegExp(grep).test(l);
  return true;
});

console.log(`日志文件：${path.basename(target)}  (${(buf.length / 1024).toFixed(1)} KB)`);
console.log(`抽出 ${lines.length} 行脚本日志${grep ? `，匹配 ${out.length} 行` : ''}：\n`);
for (const l of out) console.log(l);
