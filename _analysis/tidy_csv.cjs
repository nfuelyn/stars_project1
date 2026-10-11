const fs=require('fs');
for (const f of ['prototype/attacks/multi3.csv','prototype/attacks/sans_bonestab3.csv']) {
  let s=fs.readFileSync(f,'utf8');
  s=s.replace(/\n{3,}/g,'\n\n').replace(/[ \t]+\n/g,'\n').replace(/\s+$/,'')+'\n';
  fs.writeFileSync(f,s,'utf8');
}
console.log('空行已清理');
