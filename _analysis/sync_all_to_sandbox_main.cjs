const fs=require('fs'),crypto=require('crypto');
const h=s=>crypto.createHash('md5').update(s).digest('hex');
const main=fs.readFileSync('D:/stars/workspace/sans-fight/lua/main.lua','utf8');
const core=fs.readFileSync('D:/stars/workspace/sans-fight/lua/core.lua','utf8');
const save=fs.readFileSync('D:/stars/workspace/sans-fight/sans-fight.save.json','utf8');

// 改动清单：落在哪个文件
const checks=[
 ['① 固定摇杆（基准固定 HOME + 吸附区 + 常显底盘）','main',['JOY_HOME_X, JOY_HOME_Y','JOY_ZONE','joystickGeom']],
 ['② 骨刺一排骨（drawStab 间距13/厚10）','main',['SP, BW = 13, 10']],
 ['③ 灵魂（心）下移 3px（绘制+命中同源）','main',['M.MENU_HEART_DY = 3','+ (M.MENU_HEART_DY or 0)']],
 ['④ 结局页点击走重开二次确认','main',['core.requestRestart']],
 ['⑤ 标题页提示（PC 空格 / 鼠标无法选定）','core',['鼠标无法选定']],
 ['⑥ 重开二次确认本体 requestRestart','core',['function Game:requestRestart','restart_armed']],
 ['⑦ Sans 发言=原版两句（huff/win）','core',["tired = '呼","win   = '好吧","extraText"]],
 ['⑧ 台词画在 Sans 头顶上方 / 空串不画','core',['lineY','- 16 - SANS_H) - 30']],
 ['⑨ 骨刺加厚（bonestab dist 13.5）','save',['BoneStab,$Direction,13.5']],
 ['⑩ 阶段③黑屏 2.2（骨刺真的伸出）','save',['2.2,BlackScreen,1']],
];
console.log('沙箱 main.lua md5='+h(main)+'  行='+main.split('\n').length);
console.log('沙箱 core.lua md5='+h(core)+'  行='+core.split('\n').length);
console.log('存档 md5='+h(save)+'  字节='+save.length);
console.log('---- 改动落位核对 ----');
for(const [name,where,keys] of checks){
  const src = where==='main'?main:(where==='core'?core:save);
  const miss = keys.filter(k=>!src.includes(k));
  console.log((miss.length===0?'✅':'❌')+' '+name+'  → '+where+(miss.length?('  缺: '+miss.join(' | ')):''));
}
// 刷新备份（含当日全部更新）
const header = [
'-- ============================================================================',
'-- 【备份·全量同步版】沙箱 main 文件 —— D:\\stars\\workspace\\sans-fight\\lua\\main.lua',
'--   同步时间：2026-10-13（**含全部改动**；除本注释块外与沙箱 main.lua 逐字节一致）',
'--',
'--   注意：有几处改动在**同目录的 core.lua**（本备份不含它）：',
'--     · 标题页提示「PC：按 空格 确认开局 · 鼠标无法选定」',
'--     · 重开二次确认本体 Game:requestRestart（结局页点击由 main 调它）',
'--     · Sans 发言改为原版两句（huff... puff... / alright, i guess you win.）+ 台词画在 Sans 头顶上方',
'--     · 骨刺加厚（sans_bonestab{1,2,3} dist 9→13.5，在 prototype/attacks/*.csv）',
'--   要"整包同步"，除了本文件还要带 core.lua + prototype/attacks/*.csv，或直接导入 sans-fight.save.json。',
'-- ============================================================================',
'',
].join('\n');
fs.writeFileSync('D:/stars/main_备份_2026-10-13.lua', header+main, 'utf8');
const bak=fs.readFileSync('D:/stars/main_备份_2026-10-13.lua','utf8');
const body=bak.slice(bak.lastIndexOf('-- ============================================================================\n')+'-- ============================================================================\n'.length, -0);
console.log('---- 备份刷新 ----');
console.log('D:\\stars\\main_备份_2026-10-13.lua  body md5='+h(body.replace(/\n$/,'')+'\n')+'（与沙箱 main 一致应为 '+h(main)+'）');
