const fs=require('fs');
const fix=(f)=>{let s=fs.readFileSync(f,'utf8');s=s.replace(/([^\n])\n\n(\s*\n)*(0,)/g,'$1\n$3');s=s.replace(/\n{2,}/g,'\n').replace(/\s+$/,'')+'\n';fs.writeFileSync(f,s,'utf8');};
fix('prototype/attacks/multi3.csv');
fix('prototype/attacks/sans_bonestab3.csv');
console.log('空白行已清理');
