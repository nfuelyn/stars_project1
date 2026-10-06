/* ============================================================================
 * 攻击脚本冒烟测试（node）：把每个 CSV 编译并空跑，检查
 *   1) 没有 unknown 命令（说明命令集覆盖完整）
 *   2) 短攻击都能在合理时间内 EndAttack（说明循环/跳转没有死循环或走飞）
 * 运行：node prototype/attack-selftest.js
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const BTS = require('./attack-engine.js');
const { parseCSV } = require('./attack-loader.js');

const DIR = path.join(__dirname, 'attacks');
const DT = 1 / 60;
let pass = 0, fail = 0;
const ok = (c, m) => { if (c) { pass++; console.log('  PASS  ' + m); } else { fail++; console.log('  FAIL  ' + m); } };

const files = fs.readdirSync(DIR).filter(f => f.endsWith('.csv')).sort();
console.log('发现 ' + files.length + ' 个攻击脚本\n');

for (const f of files) {
  const rows = parseCSV(fs.readFileSync(path.join(DIR, f), 'utf8'));
  const w = new BTS.World({ seed: 7, script: rows });
  let unknown = null, frames = 0;
  const maxFrames = Math.round(60 / DT);            // 最多空跑 60 秒
  while (!w.ended && frames < maxFrames) { w.update(DT); frames++; }
  const unk = w.log.filter(s => s.indexOf('unknown') === 0);
  if (unk.length) unknown = unk[0];
  ok(!unknown, f + ' 无未知命令' + (unknown ? '（' + unknown + '）' : ''));
  ok(w.ended, f + ' 在 ' + (frames * DT).toFixed(1) + 's 内结束' + (w.ended ? '' : '（超时未 EndAttack）'));
  console.log('        实体：骨头 ' + w.bones.length + ' / 正弦 ' + w.sine.length +
              ' / 龙骨炮 ' + w.blasters.length + ' / 平台 ' + w.platforms.length +
              '　日志 ' + w.log.length + ' 条');
}

console.log('\n------------------------------');
console.log('PASS ' + pass + ' / FAIL ' + fail);
process.exit(fail === 0 ? 0 : 1);
