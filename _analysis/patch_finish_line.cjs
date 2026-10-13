const fs=require('fs');
let c=fs.readFileSync('lua/core.lua','utf8');
// 结局（spare/kill）时说原版那句 "alright, i guess you win."
const anchor='function Game:finish(outcome, reason)';
const i=c.indexOf(anchor);
if(i<0) throw new Error('finish 未找到');
const nl=c.indexOf('\n', i)+1;
const insert=`  -- 【2026-10-13 用户口径】原版结局台词（Battle.xml L1483 "alright, i guess you win."）：
  --   只在**饶恕/击倒**（即"赢了"）时说；fail（玩家阵亡）不说。
  if (outcome == 'spare' or outcome == 'kill') and LINES.win ~= '' then self:say(LINES.win) end
`;
c = c.slice(0,nl) + insert + c.slice(nl);
fs.writeFileSync('lua/core.lua', c.replace(/\s+$/,'')+'\n','utf8');
console.log('finish 钩子已加');
