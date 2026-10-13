const fs=require('fs');
const CP='lua/core.lua';
let c=fs.readFileSync(CP,'utf8');
const dup="    -- 【2026-10-13 用户口径】标题页提示：PC 用空格确认、鼠标无法选定\n    push(cmds, { kind = 'hudText', text = 'PC：按 空格 确认开局　·　鼠标无法选定', x = VW / 2, y = 300,\n                 size = 14, color = '#c9b26a', align = 'center' })\n";
if(c.includes(dup)){ c=c.replace(dup,''); fs.writeFileSync(CP,c.replace(/\s+$/,'')+'\n','utf8'); console.log('✅ 已删除我误加的重复提示（沙箱原本已有 L3239 那条）'); }
else console.log('（没找到重复块）');
console.log('现在含「空格 确认开局」的行数 = ' + (c.match(/空格 确认开局|空格 确认/g)||[]).length);
