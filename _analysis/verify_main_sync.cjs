const fs=require('fs');
const sandbox=fs.readFileSync('D:/stars/workspace/sans-fight/lua/main.lua','utf8');
const bak=fs.readFileSync('D:/stars/main_备份_2026-10-11.lua','utf8');
// 备份 = 头注释块 + 原文；取原文比较
const i=bak.indexOf('-- ============================================================================\n--\n');
const body=bak.slice(bak.lastIndexOf('-- ============================================================================\n')+'-- ============================================================================\n'.length);
const crypto=require('crypto');
const h=s=>crypto.createHash('md5').update(s).digest('hex');
console.log('沙箱 main.lua      md5='+h(sandbox)+'  行='+sandbox.split('\n').length);
console.log('备份(去掉头)       md5='+h(body)+'  行='+body.split('\n').length);
console.log('是否逐字节一致： '+(h(sandbox)===h(body)?'是 ✅':'否 ❌'));
console.log('沙箱含固定摇杆： '+(sandbox.includes('JOY_HOME_X, JOY_HOME_Y')?'是':'否'));
console.log('沙箱含 requestRestart 路由： '+(sandbox.includes('core.requestRestart')?'是':'否'));
console.log('沙箱含 drawStab 一排骨刺： '+(sandbox.includes('沿边间距')||sandbox.includes('SP, BW = 13, 10')?'是':'否'));
