const { execFileSync } = require('child_process');
const fs = require('fs');
const old = execFileSync('git', ['-C', 'D:\\stars', 'show', '6cef380:workspace/sans-fight/lua/attacks.lua'], { maxBuffer: 1 << 28 }).toString('utf8').replace(/\r\n/g, '\n');
const cur = fs.readFileSync('lua/attacks.lua', 'utf8').replace(/\r\n/g, '\n');
function blockOf(src, name) {
  const a = src.indexOf('{ name = "' + name + '"');
  const b = src.indexOf('{ name = "', a + 10);
  return b < 0 ? src.slice(a) : src.slice(a, b);
}
console.log('multi3 与 6cef380 逐字节一致 =', blockOf(old, 'multi3') === blockOf(cur, 'multi3'));
