// 生成一份"20 件物品"的存档副本（不改工作区），用于可视检查滚动栏
const fs = require('fs');
const path = 'D:/stars/workspace/sans-fight/sans-fight.save.json';
const j = JSON.parse(fs.readFileSync(path, 'utf8'));
const src = j.assets.scripts[0].source;
const i = src.indexOf('  self.items = {');
if (i < 0) { console.log('MISS items 表'); process.exit(1); }
const end = src.indexOf('\n  }\n', i);
if (end < 0) { console.log('MISS items 结束'); process.exit(1); }
const lines = ['  self.items = {', "    { id = 'legend_bread', name = '传奇面包', short = '传奇面包', desc = '回复 45 HP', heal = 45, count = 20 },"];
for (let k = 1; k <= 19; k++) lines.push("    { id = 'food" + k + "', name = '食物" + k + "', short = 'F" + k + "', desc = '回复 " + (10 + k) + " HP', heal = " + (10 + k) + ", count = 1 },");
lines.push('  }');
j.assets.scripts[0].source = src.slice(0, i) + lines.join('\n') + src.slice(end);
fs.writeFileSync('D:/stars/_analysis/save-20items.json', JSON.stringify(j), 'utf8');
console.log('已生成 20 件物品的存档副本');
