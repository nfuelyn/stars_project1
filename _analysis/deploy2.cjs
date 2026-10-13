const fs=require('fs'),crypto=require('crypto');
const DIR='C:/Users/19637/AppData/LocalLow/miHoYo/原神/BeyondLocal/248255821/Beyond_Local_Save_Level/1073741827/external_lua_file';
const TARGET=DIR+'/main.lua';
const save=JSON.parse(fs.readFileSync('D:/stars/workspace/sans-fight/sans-fight.save.json','utf8'));
const bundle=save.assets.scripts[0].source;
const old=fs.readFileSync(TARGET);
const h=s=>crypto.createHash('md5').update(s).digest('hex');
if(h(old)!==h(Buffer.from(bundle,'utf8'))) fs.writeFileSync(TARGET+'.bak-2026-10-13','');   // 占位（下面按需覆盖）
// 备份当前部署版（若与新版不同）
if(h(old)!==h(Buffer.from(bundle,'utf8'))){
  fs.writeFileSync(DIR+'/main.lua.bak-2026-10-13b', old);
  fs.writeFileSync(TARGET, Buffer.from(bundle,'utf8'));
  console.log('已重新部署（旧版备份 → main.lua.bak-2026-10-13b）');
} else console.log('部署文件已是最新，无需改写');
const now=fs.readFileSync(TARGET), txt=now.toString('utf8');
console.log('部署文件：'+now.length+' 字节  md5='+h(now));
for(const [n,k] of [['战斗红心模型（瓣 9/偏移 2.5,3.5）','say * 2.5'],['尖 15×9','rtri(cx + sax * 3.5, cy + say * 3.5, 15, 9, 180'],['灵魂下移','M.MENU_HEART_DY = 3'],['Sans 原版两句','呼……呼……']])
  console.log((txt.includes(k)?'✅':'❌')+' '+n);
