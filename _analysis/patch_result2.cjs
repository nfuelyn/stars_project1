const fs=require('fs');
let c=fs.readFileSync('lua/core.lua','utf8');
const o="    if e.confirm then\n      local ri = self.resultIndex or 1\n      if ri == 0 then self:settle()\n      elseif ri == 1 then self:restart()\n      else self:retitle() end\n    end";
const n="    -- 【2026-10-11 用户口径】结局页「重开」要二次确认（键盘与鼠标同口径）；换项即撤销\n    if e.left or e.right then self.restartArmed = false end\n    if e.confirm then\n      local ri = self.resultIndex or 1\n      if ri == 0 then self:settle()\n      elseif ri == 1 then self:requestRestart()\n      else self:retitle() end\n    end";
if(!c.includes(o)) throw new Error('result 确认分支未找到');
c=c.replace(o,n);
fs.writeFileSync('lua/core.lua',c.replace(/\s+$/,'')+'\n','utf8');
console.log('core result 分支已改');
