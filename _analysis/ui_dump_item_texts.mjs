import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
const SIM='D:\\miliastra-beyond-simulator', PROJ='D:\\stars\\workspace\\sans-fight';
const { createStudio } = await import(pathToFileURL(path.join(SIM,'studio','index.js')).href);
const raw=JSON.parse(fs.readFileSync(path.join(PROJ,'sans-fight.save.json'),'utf8'));
const studio=createStudio(1,{workspacePath:path.dirname(path.dirname(PROJ))});
studio.importData('json',Buffer.from(JSON.stringify(raw),'utf8').toString('base64'),'sans-fight.save.json');
studio.playStart({canvasId:'pc-16-9'});
const DT=1/30, init=studio.playGet({inspect:false});
const S=init.canvasHeight/480, OX=(init.canvasWidth-640*S)/2;
const w2c=(x,y)=>({x:OX+x*S,y:(480-y)*S});
const steps=n=>{for(let i=0;i<n;i++)studio.playStep(DT,{observe:false});};
const key=(k,n=2)=>{studio.playKey(k+'Down');steps(n);studio.playKey(k+'Up');steps(n);};
const texts=(node,out=[],d=0)=>{if(!node||d>9||typeof node!=='object')return out;for(const [k,v] of Object.entries(node)){if(typeof v==='string'&&v.length<=40)out.push(k+'='+v);else if(typeof v==='object')texts(v,out,d+1);}return out;};
const hasMenu=()=>texts(studio.playGet({view:true}).scene).some(s=>s.includes('攻')||s.includes('仁'));
const DIFF=w2c(97,230),TAP=w2c(140,437);
for(let i=0;i<50;i++){ if(i===30)studio.playPointer('click',DIFF.x,DIFF.y,{observe:false}); if(i===44)studio.playPointer('click',TAP.x,TAP.y,{observe:false}); studio.playStep(DT,{observe:false}); }
let t=0; while(t<30 && !hasMenu()){steps(15);t+=0.5;}
key('KeyboardMoveRightKey'); key('KeyboardMoveRightKey'); key('KeyboardMenuConfirmKey'); steps(6);
const list=texts(studio.playGet({view:true}).scene).filter(s=>/^text=/.test(s)||/x\d|回|道|包|派|面|排|雄/.test(s));
console.log(list.join('\n'));
