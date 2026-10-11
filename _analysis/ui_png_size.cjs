const fs=require('fs'),path=require('path');
const base='D:/c2-sans-fight-src/Animations';
for(const obj of ['UIFight','UIAct','UIItem','UIMercy']){
  for(const anim of ['Default','Highlight']){
    const p=path.join(base,obj,anim,'000.png');
    const b=fs.readFileSync(p);
    const w=b.readUInt32BE(16), h=b.readUInt32BE(20);
    console.log(obj+'/'+anim+'  '+w+'×'+h);
  }
}
