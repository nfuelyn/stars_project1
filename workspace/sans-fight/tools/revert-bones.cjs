const fs = require('fs');
let a = fs.readFileSync('lua/attacks.lua','utf8').split(/\r?\n/);
const back = [
  ['0,BoneVRepeat,128,341,22,0,240,4,32', '0,BoneVRepeat,128,341,45,0,240,4,16'],
  ['0,BoneV,64,286,50,0,240',            '0,BoneV,64,286,100,0,240'],
  ['0,BoneVRepeat,512,341,22,2,240,4,32', '0,BoneVRepeat,512,341,45,2,240,4,16'],
  ['0,BoneV,576,286,50,2,240',           '0,BoneV,576,286,100,2,240'],
  ['0,BoneVRepeat,121,364,15,2,0,25,32',  '0,BoneVRepeat,121,364,30,2,0,25,16'],
];
let cnt = {};
for (let p = 0; p < a.length; p++) {
  const t = a[p].trim();
  for (const [o, n] of back) if (t === o) { a[p] = a[p].replace(o, n); cnt[o] = (cnt[o] || 0) + 1; }
}
fs.writeFileSync('lua/attacks.lua', a.join('\r\n'));
for (const [o, n] of back) console.log('  ' + o + '  →  ' + n + '   复原 ' + (cnt[o] || 0) + ' 处');
