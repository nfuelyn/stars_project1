#!/usr/bin/env node
/* ==========================================================================
  tools/verify-all.mjs —— 一条命令跑完「审判者战」的全部离线回归 + 重建存档 + 契约校验

  用途：把散在 docs/device-setup.md 里的 6 条命令合成一条，并自动判读每个套件的
  PASS/FAIL 汇总行，最后给一张总表。**任何一项失败就以退出码 1 结束**。

  用法：
    node tools/verify-all.mjs              # 全部（含 _geometry 约 6 分钟、_pool 约 25 分钟）
    node tools/verify-all.mjs --quick      # 跳过最慢的两个（_geometry / _pool）
    node tools/verify-all.mjs --no-build   # 不重建存档（只跑测试）

  为什么要有它：20 回合结构轮里，改动横跨 core/attacks/main/6 个测试与 5 份文档，
  手工一条条跑很容易漏（尤其 _geometry 只在"新外观"下才暴露期望值过期）。
  ========================================================================== */

import { spawnSync } from 'node:child_process';
import { existsSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const quick = args.includes('--quick');
const noBuild = args.includes('--no-build');

// name, lua 文件, 期望的正则（命中才算通过）, 备注
const SUITES = [
  ['_check',        'lua/_check.lua',        /RUN FAIL|FAIL /,                                        '语法 + 四档难度 900 帧（负向：不该出现 FAIL）'],
  ['_rounds',       'lua/_rounds.lua',       /(\d+) PASS \/ (\d+) FAIL/,                              '20 回合结构/抽签/清场/螺旋档保真'],
  ['core_selftest', 'lua/core_selftest.lua', /PASS (\d+) \/ FAIL (\d+)/,                              '逻辑层自测 + 27 个脚本空跑'],
  ['_tap',          'lua/_tap.lua',          /pc input regression: (\d+) pass \/ (\d+) fail/,         '画布→世界→UI 命中链路'],
  ['_title',        'lua/_title.lua',        /title regression: (\d+) pass \/ (\d+) fail/,            '标题页/难度选择'],
  ['_input',        'lua/_input.lua',        /input regression: (\d+) pass \/ (\d+) fail/,            '平台分流 + 四向矩阵'],
  ['_geometry',     'lua/_geometry.lua',     /PASS (\d+) \/ FAIL (\d+)/,                              '绘制 == 判定几何（慢，约 6 分钟）'],
  ['_pool',         'lua/_pool.lua',         /各类峰值之和 = (\d+)/,                                   '控件池峰值实测（最慢，约 25 分钟）'],
];

const SKIP_IN_QUICK = new Set(['_geometry', '_pool']);

function runSuite(name, file, re) {
  const t0 = Date.now();
  const r = spawnSync(process.execPath, [join('tools', 'run-lua.mjs'), file], {
    cwd: ROOT, encoding: 'utf8', maxBuffer: 1 << 28,
  });
  const out = (r.stdout || '') + (r.stderr || '');
  const dt = ((Date.now() - t0) / 1000).toFixed(1);

  if (name === '_check') {
    // _check 只在出错时打 "RUN FAIL"；没有就是通过
    const bad = /RUN FAIL|LONG RUN FAIL/.test(out);
    return { name, ok: !bad, note: bad ? '出现 RUN FAIL' : '四档难度各 900 帧无错', secs: dt, raw: out };
  }
  // 取**最后一次**匹配：套件中途可能也打印形如 "PASS n / FAIL m" 的行，汇总行在最后
  const all = [...out.matchAll(new RegExp(re.source, 'g'))];
  const m = all.length ? all[all.length - 1] : null;
  if (!m) return { name, ok: false, note: '没找到汇总行（可能崩了）', secs: dt, raw: out };
  if (name === '_pool') {
    // _pool 的判定：draw ERR=0、未注册 guid=0、运行期追加=0
    const drawErr = /draw ERR=(\d+)/.exec(out);
    const appends = /运行期追加=(\d+)/g;
    let worst = 0, mm;
    while ((mm = appends.exec(out))) worst = Math.max(worst, Number(mm[1]));
    const bad = (drawErr && Number(drawErr[1]) > 0) || worst > 0;
    return {
      name, ok: !bad, secs: dt,
      note: `峰值和=${m[1]}，最大运行期追加=${worst}${drawErr ? `，draw ERR=${drawErr[1]}` : ''}`,
      raw: out,
    };
  }
  const pass = Number(m[1]), fail = Number(m[2]);
  return { name, ok: fail === 0, note: `${pass} PASS / ${fail} FAIL`, secs: dt, raw: out };
}

function runCmd(label, argsList) {
  const t0 = Date.now();
  const r = spawnSync(process.execPath, argsList, { cwd: ROOT, encoding: 'utf8', maxBuffer: 1 << 28 });
  const out = (r.stdout || '') + (r.stderr || '');
  return { name: label, ok: r.status === 0, note: out.trim().split('\n').slice(-1)[0] || '', secs: ((Date.now() - t0) / 1000).toFixed(1), raw: out };
}

console.log('==== 审判者战 · 全量验证 ====');
console.log(`工作区：${ROOT}`);
console.log(`模式：${quick ? '--quick（跳过 _geometry/_pool）' : '全部'}${noBuild ? ' + 不重建存档' : ''}\n`);

const results = [];
for (const [name, file, re, note] of SUITES) {
  if (quick && SKIP_IN_QUICK.has(name)) { console.log(`跳过 ${name}（--quick）`); continue; }
  if (!existsSync(join(ROOT, file))) { results.push({ name, ok: false, note: '文件不存在', secs: '0' }); continue; }
  process.stdout.write(`跑 ${name} … `);
  const res = runSuite(name, file, re);
  res.what = note;
  results.push(res);
  console.log(`${res.ok ? 'OK  ' : 'FAIL'}  ${res.note}（${res.secs}s）`);
  if (!res.ok) {
    console.log('---- 失败输出（末 40 行）----');
    console.log(res.raw.split('\n').slice(-40).join('\n'));
    console.log('----');
  }
}

if (!noBuild) {
  process.stdout.write('重建存档 build-save … ');
  const b = runCmd('build-save', [join('tools', 'build-save.mjs')]);
  results.push(b);
  console.log(`${b.ok ? 'OK  ' : 'FAIL'}  ${b.note}（${b.secs}s）`);
  if (!b.ok) console.log(b.raw.split('\n').slice(-30).join('\n'));

  process.stdout.write('客户端池契约 verify-client-pool … ');
  const v = runCmd('verify-client-pool', [join('tools', 'verify-client-pool.mjs')]);
  results.push(v);
  console.log(`${v.ok ? 'OK  ' : 'FAIL'}  ${v.note}（${v.secs}s）`);
  if (!v.ok) console.log(v.raw.split('\n').slice(-30).join('\n'));

  const save = join(ROOT, 'sans-fight.save.json');
  if (existsSync(save)) console.log(`存档：${(statSync(save).size / 1024).toFixed(1)} KB`);
}

console.log('\n==== 总表 ====');
const w = Math.max(...results.map((r) => r.name.length));
for (const r of results) {
  console.log(`${r.name.padEnd(w)}  ${r.ok ? 'PASS' : 'FAIL'}  ${r.note}  [${r.secs}s]`);
}
const failed = results.filter((r) => !r.ok);
console.log(`\n结论：${results.length - failed.length} / ${results.length} 通过` +
  (failed.length ? `，失败：${failed.map((f) => f.name).join(', ')}` : ''));
process.exit(failed.length ? 1 : 0);
