const fs=require('fs'),crypto=require('crypto');
const h=s=>crypto.createHash('md5').update(s).digest('hex');
const MP='D:/stars/workspace/sans-fight/lua/main.lua', CP='D:/stars/workspace/sans-fight/lua/core.lua';
let core=fs.readFileSync(CP,'utf8');
console.log('沙箱 core.lua 含「空格」提示：'+core.includes('空格')+'   含「标题页」相关：'+core.includes("state == 'title'"));
// 若标题提示缺失 → 补回（在标题分支的 return cmds 之前插一行 hudText）
if(!core.includes('鼠标无法选定')){
  const idx=core.indexOf("if g.state == 'title' then");
  const ret=core.indexOf('    return cmds', idx);
  if(idx>0 && ret>idx){
    const ins="    -- 【2026-10-13 用户口径】标题页提示：PC 用空格确认、鼠标无法选定\n    push(cmds, { kind = 'hudText', text = 'PC：按 空格 确认开局　·　鼠标无法选定', x = VW / 2, y = 300,\n                 size = 14, color = '#c9b26a', align = 'center' })\n";
    core = core.slice(0,ret) + ins + core.slice(ret);
    fs.writeFileSync(CP, core.replace(/\s+$/,'')+'\n','utf8');
    console.log('✅ 已把标题页提示补回 core.lua（在 title 分支的 return 之前）');
  } else console.log('❌ 未找到 title 分支的 return，需人工处理');
} else console.log('✅ core.lua 已有标题页提示');
// 刷新备份（2026-10-13）
const main=fs.readFileSync(MP,'utf8');
const header=[
'-- ============================================================================',
'-- 【备份·全量同步版】沙箱 main 文件 —— '+MP.replace('D:/stars/workspace/sans-fight/lua/',''),
'--   同步时间：2026-10-13（除本注释块外与沙箱 main.lua **逐字节一致**）',
'--   同目录 core.lua 里另有：标题页提示 / 重开二次确认 requestRestart / Sans 原版两句发言+头顶位置；',
'--   prototype/attacks/*.csv 里另有：骨刺加厚 13.5、阶段③黑屏 2.2。整包同步请带 core.lua 或直接导入 sans-fight.save.json。',
'-- ============================================================================',
'',
].join('\n');
fs.writeFileSync('D:/stars/main_备份_2026-10-13.lua', header+main, 'utf8');
const bak=fs.readFileSync('D:/stars/main_备份_2026-10-13.lua','utf8');
console.log('---- 同步核对 ----');
console.log('沙箱 main.lua md5='+h(main));
console.log('备份 2026-10-13 以沙箱 main 结尾：'+(bak.endsWith(main)?'是 ✅':'否 ❌'));
console.log('沙箱 core.lua md5='+h(core)+'  现含标题提示：'+core.includes('鼠标无法选定'));
