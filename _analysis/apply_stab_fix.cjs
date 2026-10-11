const fs=require('fs');
// C1) final 阶段③ 的两处黑屏：0.9 -> 2.2（让骨刺真的伸出，补上攻击判定）
{
  const p='prototype/attacks/final.csv';
  const lines=fs.readFileSync(p,'utf8').split('\n');
  let n=0;
  [143,152].forEach((i)=>{                       // 0 基：144 / 153 行
    if (lines[i] && lines[i].trim()==='0.9,BlackScreen,1') { lines[i]='2.2,BlackScreen,1'; n++; }
  });
  fs.writeFileSync(p,lines.join('\n'));
  console.log('final 阶段③ 黑屏延后 '+n+'/2 处');
}
// C3) 非 final 的对应攻击（拖拽后升起的骨刺）—— dist 9 -> 13.5（×1.5）
for (const f of ['sans_bonestab1','sans_bonestab2','sans_bonestab3']) {
  const p='prototype/attacks/'+f+'.csv';
  let s=fs.readFileSync(p,'utf8');
  const before=s;
  s=s.replace(/BoneStab,(\$Direction|0|1|2|3),9,/, (m,dir)=>{ return 'BoneStab,'+dir+',13.5,'; });
  fs.writeFileSync(p,s);
  console.log(f+' dist 9 → 13.5 '+(s!==before?'ok':'（未改动！）'));
}
