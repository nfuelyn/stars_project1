const fs=require('fs');
// 1) core：标题页加"PC 端空格确认 / 鼠标无法选定"提示 + 重开二次确认
let c=fs.readFileSync('lua/core.lua','utf8');
const titleAnchor="      push(cmds, { kind = 'hudText', text = D.note, x = 32 + i * 145 + 65, y = 262, size = 12,\n                   color = sel and '#c9b26a' or '#666666', align = 'center' })\n    end\n    return cmds\n  end";
const titleNew="      push(cmds, { kind = 'hudText', text = D.note, x = 32 + i * 145 + 65, y = 262, size = 12,\n                   color = sel and '#c9b26a' or '#666666', align = 'center' })\n    end\n    -- 【2026-10-11 用户口径】PC 端提示：用**空格**确认开局；鼠标无法选定\n    push(cmds, { kind = 'hudText', text = 'PC：按 空格 确认开局　·　鼠标无法选定', x = VW / 2, y = 300, size = 14,\n                 color = '#c9b26a', align = 'center' })\n    return cmds\n  end";
if(!c.includes(titleAnchor)) throw new Error('标题锚点未找到');
c=c.replace(titleAnchor,titleNew);
// 重开二次确认 API（放在 restart 定义之后）
const restartAnchor="function Game:restart()";
const i=c.indexOf(restartAnchor);
if(i<0) throw new Error('restart 未找到');
const endOfRestart=c.indexOf('\nend\n', i)+5;
const requestApi=`
-- 【2026-10-11 用户口径·重开二次确认（PC 也要）】第一次调用只"上膛"并提示，再确认一次才真的重开。
function Game:requestRestart()
  if self.restartArmed then
    self.restartArmed = false
    self:restart()
    return
  end
  self.restartArmed = true
  self:say('再按一次确认重开　（结算 = 结束本局）')
  self:log('restart_armed')
end
`;
c=c.slice(0,endOfRestart)+requestApi+c.slice(endOfRestart);
// result 态的确认键走二次确认
const resAnchor="  if self.state == 'result' then\n    if e.confirm then self:restart() end";
const resNew="  if self.state == 'result' then\n    -- 【2026-10-11】重开要二次确认（键盘/鼠标同口径）\n    if e.confirm then self:requestRestart() end";
if(c.includes(resAnchor)) c=c.replace(resAnchor,resNew); else console.log('（未找到 result 分支，稍后人工核对）');
// 导出
c=c.replace("function M.restart(g) g:restart() end","function M.restart(g) g:restart() end\nfunction M.requestRestart(g) g:requestRestart() end");
fs.writeFileSync('lua/core.lua',c.replace(/\s+$/,'')+'\n','utf8');
// 2) main：结局页点击（重开）走 requestRestart
let m=fs.readFileSync('lua/main.lua','utf8');
m=m.replace("      pcall(function() core.restart(state) end)\n      print('main: 点按 → 重开')","      pcall(function() core.requestRestart(state) end)\n      print('main: 点按 → 重开（需再确认一次）')");
fs.writeFileSync('lua/main.lua',m.replace(/\s+$/,'')+'\n','utf8');
console.log('core/main 已改');
