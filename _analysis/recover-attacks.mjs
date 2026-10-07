import fs from 'node:fs';
import path from 'node:path';
const save = JSON.parse(fs.readFileSync('D:/stars/workspace/sans-fight/sans-fight.save.json','utf8'));
const src = save.assets.scripts[0].source;
const outDir = 'D:/stars/_analysis/recovered';
fs.mkdirSync(outDir, {recursive:true});
const re = /name = "([^"]+)", csv = \[==\[([\s\S]*?)\]==\]/g;
let m, names=[];
while ((m = re.exec(src))){
  const name = m[1], csv = m[2].replace(/^\r?\n/,'').replace(/\s+$/,'') + '\n';
  fs.writeFileSync(path.join(outDir, name + '.csv'), csv, 'utf8');
  names.push(name);
}
console.log('从存档提取脚本数：' + names.length);
const portDir = 'D:/stars/workspace/sans-fight/prototype/attacks';
function norm(t){ return t.split(/\r?\n/).map(l=>l.replace(/\s+$/,'')).filter(l=>l.trim()!==''); }
let changed=[];
for (const n of names){
  const cur = path.join(portDir, n + '.csv');
  if (!fs.existsSync(cur)) { console.log('  [新增] ' + n); changed.push(n); continue; }
  const a = norm(fs.readFileSync(cur,'utf8')), b = norm(fs.readFileSync(path.join(outDir,n+'.csv'),'utf8'));
  if (a.join('\n') !== b.join('\n')){
    changed.push(n);
    console.log('\n== 被覆盖的脚本: ' + n + ' ==');
    const max = Math.max(a.length,b.length);
    for(let i=0;i<max;i++){ if(a[i]!==b[i]){ console.log('   CSV(当前): '+String(a[i])); console.log('   存档(正确): '+String(b[i])); } }
  }
}
console.log('\n共 ' + changed.length + ' 个脚本与存档不一致：' + changed.join(', '));
