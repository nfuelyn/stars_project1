const fs=require('fs'),crypto=require('crypto');
const DIR='C:/Users/19637/AppData/LocalLow/miHoYo/原神/BeyondLocal/248255821/Beyond_Local_Save_Level/1073741827/external_lua_file';
const TARGET=DIR+'/main.lua';
const save=JSON.parse(fs.readFileSync('D:/stars/workspace/sans-fight/sans-fight.save.json','utf8'));
const bundle=save.assets.scripts[0].source;
const old=fs.readFileSync(TARGET);
// ① 先备份旧文件（同目录 + 带日期）
const stamp=new Date().toISOString().slice(0,10);
const bak=TARGET+'.bak-'+stamp;
fs.writeFileSync(bak, old);
console.log('① 旧文件已备份 → '+bak+'  ('+old.length+' 字节)');
// ② 写新 bundle（UTF-8，无 BOM）
fs.writeFileSync(TARGET, Buffer.from(bundle,'utf8'));
const now=fs.readFileSync(TARGET);
const h=s=>crypto.createHash('md5').update(s).digest('hex');
const checks=[
 ['灵魂下移 M.MENU_HEART_DY','M.MENU_HEART_DY = 3'],
 ['固定摇杆（基准固定 HOME）','joy.bx, joy.by = JOY_HOME_X, JOY_HOME_Y'],
 ['骨刺一排骨 SP, BW = 13, 10','SP, BW = 13, 10'],
 ['结局页走 requestRestart','core.requestRestart'],
 ['重开二次确认本体','function Game:requestRestart'],
 ['Sans 原版两句','呼……呼……'],
 ['Sans 胜利句','好吧。算你赢了。'],
 ['台词画头顶（lineY）','local lineY = (boxAbs.y - 16 - SANS_H) - 30'],
 ['骨刺 dist 13.5','BoneStab,$Direction,13.5'],
 ['阶段③黑屏 2.2','2.2,BlackScreen,1'],
];
const txt=now.toString('utf8');
console.log('② 已写入新 main.lua：'+now.length+' 字节   md5='+h(now));
console.log('---- 新版内容核对（部署文件里逐项查）----');
for(const [name,key] of checks) console.log((txt.includes(key)?'✅':'❌')+' '+name);
console.log('---- 旧 vs 新 ----');
console.log('旧: '+old.length+' 字节  md5='+h(old));
console.log('备份文件是否与旧一致：'+(h(fs.readFileSync(bak))===h(old)?'是 ✅':'否'));
