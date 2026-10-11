const fs=require('fs'), path=require('path');
const dir='D:/c2-sans-fight-src/Files';
for(const f of fs.readdirSync(dir).filter(x=>x.endsWith('.csv')).sort()){
  const lines=fs.readFileSync(path.join(dir,f),'utf8').split(/\r?\n/);
  lines.forEach((ln,i)=>{
    if(ln.trim()===''||ln.trim().startsWith('#'))return;
    const c=ln.split(',').map(s=>s.trim());
    const cmd=c[1];
    const idx=(cmd==='BoneV'||cmd==='BoneH')?7:(cmd==='BoneVRepeat'||cmd==='BoneHRepeat')?9:-1;
    if(idx>0 && Number(c[idx])===1) console.log(f+':'+(i+1)+'  '+ln.trim());
  });
}
