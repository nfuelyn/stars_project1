import fs from 'node:fs';
const save = JSON.parse(fs.readFileSync('D:/stars/workspace/sans-fight/records/play-headless/sans-fight-round4.save.json','utf8'));
const src = save.assets.scripts[0].source;
for (const name of ['multi1','multi3']){
  const re = new RegExp('name = "'+name+'", csv = \\[==\\[([\\s\\S]*?)\\]==\\]');
  const m = src.match(re);
  console.log('\n===== 旧存档(2026-10-05) '+name+' 的 JMPABS/侧骨行 =====');
  if(!m){ console.log('  (未找到)'); continue; }
  const lines = m[1].split(/\r?\n/);
  lines.forEach((l,i)=>{ if(/JMPABS,RndAttack|BoneVRepeat,128,341|BoneV,128,286|BoneVRepeat,200,331/.test(l)) console.log('  L'+(i+1)+': '+l.trim()); });
}
