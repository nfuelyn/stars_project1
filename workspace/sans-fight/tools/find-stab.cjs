const fs = require('fs');
const p = 'lua/core_selftest.lua';
let s = fs.readFileSync(p, 'utf8');
const hits = [...s.matchAll(/sans_bonestab3[^\n]*/g)].map(m => m[0]);
console.log('含 bonestab3 的行：'); hits.forEach(h => console.log('  ' + h.trim()));
