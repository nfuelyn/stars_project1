const fs = require('fs');
const src = fs.readFileSync('lua/attacks.lua','utf8');
const parts = src.split(/\{ name = "/).slice(1);
const HUD = { sans_intro:1, sans_bonegap1:2, sans_bluebone:3, sans_bonegap2:4, platforms1:5, platforms2:6,
  platforms3:7, platforms4:8, platformblaster:9, platforms4hard:10, sans_bonegap1fast:11, sans_boneslideh:12,
  sans_bonegap2b:0, sans_spare:14, multi1:15, randomblaster1:16, multi2:17, sans_bonestab1:18,
  sans_bonestab2:19, randomblaster2:20, sans_boneslidev:21, multi3:22, sans_bonestab3:23, final:24 };
console.log('脚本'.padEnd(20) + 'HUD'.padEnd(6) + '行内序号'.padEnd(10) + 'dir'.padEnd(8) + 'dist(粗细)'.padEnd(12) + 'warn(预警)'.padEnd(12) + 'stay(停留)'.padEnd(12) + '其它');
for (const p of parts) {
  const name = p.slice(0, p.indexOf('"'));
  const body = p.slice(0, p.indexOf(']==]'));
  const lines = body.split('\n');
  let idx = 0;
  lines.forEach((l, k) => {
    const t = l.trim();
    if (!t.startsWith('#') && t.includes(',BoneStab,')) {
      idx++;
      const cells = t.split(',');
      const after = cells.slice(cells.indexOf('BoneStab') + 1);
      console.log(String(name).padEnd(20) + String(HUD[name] || '?').padEnd(6) + String('#'.padEnd(0) + idx).padEnd(10)
        + String(after[0]).padEnd(8) + String(after[1]).padEnd(12) + String(after[2]).padEnd(12) + String(after[3]).padEnd(12)
        + (after.slice(4).join(',') || ''));
    }
  });
}
