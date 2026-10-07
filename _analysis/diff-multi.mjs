import fs from 'node:fs';
const PORT='D:/stars/workspace/sans-fight/prototype/attacks';
const ORIG='D:/c2-sans-fight-src/Files';
const norm=t=>t.split(/\r?\n/).map(l=>l.replace(/\s+$/,'')).filter(l=>l.trim()!==''&&!l.trim().startsWith('#')).map(l=>l.replace(/,+$/,''));
for (const n of ['multi1','multi3']){
  const p=norm(fs.readFileSync(PORT+'/'+n+'.csv','utf8'));
  const o=norm(fs.readFileSync(ORIG+'/sans_'+n+'.csv','utf8'));
  console.log('\n== '+n+' : 端口 '+p.length+' 行 / 原版 '+o.length+' 行 ==');
  const max=Math.max(p.length,o.length); let shown=0;
  for(let i=0;i<max;i++){ if(p[i]!==o[i]){ console.log('  L'+(i+1)); console.log('    端口: '+p[i]); console.log('    原版: '+o[i]); shown++; if(shown>18){console.log('    ...');break;} } }
  if(shown===0) console.log('  （逐行一致）');
}
