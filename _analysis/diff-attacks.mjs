import fs from 'node:fs';
import path from 'node:path';
const PORT = 'D:/stars/workspace/sans-fight/prototype/attacks';
const ORIG = 'D:/c2-sans-fight-src/Files';
const map = (n) => 'sans_' + n;   // 端口多数脚本去掉了 sans_ 前缀
function norm(text){
  return text.split(/\r?\n/)
    .map(l => l.replace(/\s+$/,''))
    .filter(l => l.trim() !== '' && !l.trim().startsWith('#'))
    .map(l => l.replace(/,+$/,''));
}
const files = fs.readdirSync(PORT).filter(f=>f.endsWith('.csv')).sort();
for (const f of files){
  const name = f.replace('.csv','');
  const port = norm(fs.readFileSync(path.join(PORT,f),'utf8'));
  let origPath = path.join(ORIG, map(name)+'.csv');
  if(!fs.existsSync(origPath)) origPath = path.join(ORIG, name+'.csv');
  if(!fs.existsSync(origPath)) { console.log('== '+name+' : 原版无对应文件（自制脚本）'); continue; }
  const orig = norm(fs.readFileSync(origPath,'utf8'));
  // 逐行对齐（简单 LCS 太长，这里用集合+顺序比较）
  const same = port.length===orig.length && port.every((l,i)=>l===orig[i]);
  if(same){ console.log('== '+name+' : 完全一致（'+port.length+' 行）'); continue; }
  console.log('\n== '+name+' : 有差异  端口='+port.length+' 行 / 原版='+orig.length+' 行');
  const max = Math.max(port.length, orig.length);
  let shown=0;
  for(let i=0;i<max && shown<24;i++){
    const a=port[i], b=orig[i];
    if(a!==b){
      console.log('   L'+String(i+1).padStart(3)+'  端口: '+String(a===undefined?'(无)':a));
      console.log('         原版: '+String(b===undefined?'(无)':b));
      shown++;
    }
  }
  if(shown>=24) console.log('   ... (更多差异已省略)');
}
