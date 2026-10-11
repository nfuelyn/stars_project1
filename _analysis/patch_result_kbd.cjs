const fs=require('fs');
let c=fs.readFileSync('lua/core.lua','utf8');
// 找到 applyInput 里的 result 分支（写法可能是单行 if 或两行）
const pats=[
  "  if self.state == 'result' then\n    if e.confirm then self:restart() end\n  elseif",
  "  if self.state == 'result' then\n    if e.confirm then self:restart() end",
  "if self.state == 'result' then if e.confirm then self:restart() end",
];
let done=false;
for(const p of pats){ if(c.includes(p)){ c=c.replace(p, p.replace('self:restart()','self:requestRestart()')); done=true; console.log('已改: '+JSON.stringify(p.slice(0,40))); break; } }
if(!done) console.log('仍未找到 —— 打印上下文待人工处理');
fs.writeFileSync('lua/core.lua',c.replace(/\s+$/,'')+'\n','utf8');
