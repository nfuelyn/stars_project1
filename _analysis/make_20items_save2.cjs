// 更安全的做法：只在传奇面包那一行后面**追加** 19 件，不动其它结构
const fs = require('fs');
const p = 'D:/stars/workspace/sans-fight/sans-fight.save.json';
const j = JSON.parse(fs.readFileSync(p, 'utf8'));
const src = j.assets.scripts[0].source;
const anchor = "    { id = 'legend_bread'";
const i = src.indexOf(anchor);
if (i < 0) { console.log('MISS legend_bread'); process.exit(1); }
const lineEnd = src.indexOf('\n', i);
let extra = '';
for (let k = 1; k <= 19; k++) extra += "\n    { id = 'food" + k + "', name = '食物" + k + "', short = 'F" + k + "', desc = '回复 " + (10 + k) + " HP', heal = " + (10 + k) + ", count = 1 },";
j.assets.scripts[0].source = src.slice(0, lineEnd + 1) + extra.replace(/^\n/, '') + src.slice(lineEnd + 1);
fs.writeFileSync('D:/stars/_analysis/save-20items.json', JSON.stringify(j), 'utf8');
console.log('已生成（追加式）20 件物品存档副本');
