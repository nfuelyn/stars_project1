const fs=require('fs'), path=require('path');
// BoneV/H:x,y,size,dir,speed[,color] → color=cells[7](0基 7 = 第8格)
// BoneVRepeat/HRepeat:x,y,size,dir,speed,count,spacing[,color] → color=cells[9]
function colorOf(cells, cmd){
  const i = (cmd==='BoneV'||cmd==='BoneH') ? 7 : (cmd==='BoneVRepeat'||cmd==='BoneHRepeat') ? 9 : -1;
  if(i<0) return null;
  const v = cells[i];
  return (v===undefined||v==='') ? 0 : Number(v);
}
function scan(dir, label){
  console.log('===== '+label+' =====');
  for(const f of fs.readdirSync(dir).filter(x=>x.endsWith('.csv')).sort()){
    const lines=fs.readFileSync(path.join(dir,f),'utf8').split(/\r?\n/);
    lines.forEach((ln,idx)=>{
      if(ln.trim()===''||ln.trim().startsWith('#'))return;
      const cells=ln.split(',').map(s=>s.trim());
      const cmd=cells[1];
      const c=colorOf(cells,cmd);
      if(c===2) console.log('  [橙] '+f+':'+(idx+1)+'  '+ln.trim());
    });
  }
  // 统计蓝/橙数量
  let blue=0,orange=0;
  for(const f of fs.readdirSync(dir).filter(x=>x.endsWith('.csv'))){
    const lines=fs.readFileSync(path.join(dir,f),'utf8').split(/\r?\n/);
    for(const ln of lines){
      if(ln.trim()===''||ln.trim().startsWith('#'))continue;
      const cells=ln.split(',').map(s=>s.trim());
      const c=colorOf(cells,cells[1]);
      if(c===1)blue++; else if(c===2)orange++;
    }
  }
  console.log('  —— 全仓库统计：蓝骨行 '+blue+' / 橙骨行 '+orange);
}
scan('D:/c2-sans-fight-src/Files','原版 Files/sans_*.csv');
scan('D:/stars/workspace/sans-fight/prototype/attacks','工作区 prototype/attacks');
