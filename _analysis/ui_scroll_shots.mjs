// 用 20 件物品的存档副本：打开道具面板 → 往下选几次 → 截图（检查 ▲▼ + 滚动条）
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
const SIM='D:\\miliastra-beyond-simulator';
const SAVE='D:\\stars\\_analysis\\save-20items.json';
const OUT='D:\\stars\\_analysis\\ui-shots';
const { createStudio } = await import(pathToFileURL(path.join(SIM,'studio','index.js')).href);
const { renderScenePng } = await import(pathToFileURL(path.join(SIM,'studio','host-png.js')).href);
const raw=JSON.parse(fs.readFileSync(SAVE,'utf8'));
const studio=createStudio(1,{workspacePath:'D:\\stars\\workspace'});
studio.importData('json',Buffer.from(JSON.stringify(raw),'utf8').toString('base64'),'save-20items.json');
studio.playStart({canvasId:'pc-16-9'});
const DT=1/30, init=studio.playGet({inspect:false});
const S=init.canvasHeight/480, OX=(init.canvasWidth-640*S)/2;
const w2c=(x,y)=>({x:OX+x*S,y:(480-y)*S});
const steps=n=>{for(let i=0;i<n;i++)studio.playStep(DT,{observe:false});};
const key=(k,n=2)=>{studio.playKey(k+'Down');steps(n);studio.playKey(k+'Up');steps(n);};
const shot=t=>{const s=studio.playGet({view:true});fs.writeFileSync(path.join(OUT,t+'.png'),renderScenePng(s.scene,s.canvasWidth,s.canvasHeight).data);console.log('shot '+t);};
const texts=(n,o=[],d=0)=>{if(!n||d>9||typeof n!=='object')return o;for(const v of Object.values(n)){if(typeof v==='string'&&v.length<=40)o.push(v);else if(typeof v==='object')texts(v,o,d+1);}return o;};
const hasMenu=()=>texts(studio.playGet({view:true}).scene).some(s=>s.includes('攻')||s.includes('仁'));
const DIFF=w2c(97,230),TAP=w2c(140,437);
for(let i=0;i<50;i++){ if(i===30)studio.playPointer('click',DIFF.x,DIFF.y,{observe:false}); if(i===44)studio.playPointer('click',TAP.x,TAP.y,{observe:false}); studio.playStep(DT,{observe:false}); }
let t=0; while(t<30 && !hasMenu()){steps(15);t+=0.5;}
key('KeyboardMoveRightKey'); key('KeyboardMoveRightKey'); key('KeyboardMenuConfirmKey'); steps(6);
for (let i=0;i<8;i++) key('KeyboardMoveDownKey');
steps(4); shot('scroll-20-down8');
for (let i=0;i<10;i++) key('KeyboardMoveDownKey');
steps(4); shot('scroll-20-down18');
console.log('done');
