const fs = require('fs');
const { execFileSync } = require('child_process');
// 6cef380 = 本轮改动之前的最后一次提交（多段骨墙还是原版数值）
const old = execFileSync('git', ['-C', 'D:\\stars', 'show', '6cef380:workspace/sans-fight/lua/attacks.lua'], { maxBuffer: 1 << 28 }).toString('utf8').replace(/\r\n/g, '\n');
let cur = fs.readFileSync('lua/attacks.lua', 'utf8').replace(/\r\n/g, '\n');
function blockOf(src, name) {
  const a = src.indexOf('{ name = "' + name + '"');
  if (a < 0) return null;
  const b = src.indexOf('{ name = "', a + 10);
  return b < 0 ? src.slice(a) : src.slice(a, b);
}
const oldBlk = blockOf(old, 'multi3'), curBlk = blockOf(cur, 'multi3');
if (!oldBlk || !curBlk) { console.error('MISS multi3 block'); process.exit(1); }
cur = cur.replace(curBlk, oldBlk);
fs.writeFileSync('lua/attacks.lua', cur);
console.log('multi3 已恢复到 6cef380 的原版数值（Attack0/4/5 与段长）');
// 打印确认
for (const l of ['BoneVRepeat,128,341','BoneV,64,286','BoneVRepeat,200,331','BoneVRepeat,121,364','0.9,JMPABS,RndAttack']) {
  console.log('  含 ' + l + ' = ' + cur.includes(l));
}
