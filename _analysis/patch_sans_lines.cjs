const fs=require('fs');
let c=fs.readFileSync('lua/core.lua','utf8');

// ① LINES 换成"原版口径"（Sans 战斗里只说两句）+ 旧文本收进同一个表（不新增 chunk 级 local）
const oldStart=c.indexOf('local LINES = {');
const oldEnd=c.indexOf('\n}\n', oldStart)+3;
if(oldStart<0||oldEnd<3) throw new Error('LINES 未找到');
const oldBlock=c.slice(oldStart, oldEnd);
const newBlock = `local LINES = {
  -- 【2026-10-13 用户口径】"研究原版仓库内 sans 的发言，全面替换" ——
  --   原版 BTS（D:\\c2-sans-fight-src\\Event sheets\\Battle.xml）里，Sans 在战斗中**只有两句**：
  --     L1416（SansTired 之后，函数 Win1）："huff... puff..."
  --     L1483（紧接着，函数 Win2）       ："alright, i guess you win."
  --   其余所有时机（第 1~5 回合、中场、螺旋档…）**原版一个字都没有**（Sans 全程沉默）。
  --   因此这里照原版办理：对不上的键一律空串，渲染层遇到空串就不画（见 renderWorld 的台词守卫）。
  tired = '呼……呼……',                  -- 原版 "huff... puff..."
  win   = '好吧。算你赢了。',            -- 原版 "alright, i guess you win."
  -- 以下时机原版没有台词（全面替换口径下 = 不说话）
  surprise = '', r1 = '', r2 = '', r3 = '', r4 = '', r5 = '', r6 = '',
  mid = '', late = '', spiral1 = '', spiral2 = '', spiral3 = '', final = '',
  midpoint = '', dodge = '', refuse = '', flee = '',
  -- 旧口径（每回合都说话的版本）原样收在同一张表里：把 extra 改成 true 即可回退
  extra = false,
  extraText = {
    surprise = '（他没有打招呼，先动手了。）',
    r1 = '站住别动，让我看看你躲得怎么样。',
    r2 = '骨头是会走路的东西，别被它撞上。',
    r3 = '蓝色的骨头：别动。你动一下，它就咬你。',
    r4 = '抬头看看，朋友。',
    r5 = '你还没死？那我再认真一点。',
    r6 = '……你已经撑过六回合了。',
    mid = '撑过一半了？那我换个打法。',
    late = '你还在动。越来越有意思了。',
    spiral1 = '站好，抬头看。',
    spiral2 = '别眨眼。',
    spiral3 = '——好吧。轮到你了。',
    dodge = '（他侧身闪开了）',
    refuse = '（他摇了摇头）',
    flee = '（他摇了摇头）你逃不掉的。',
    final = '好吧。轮到你了。',
    midpoint = '……中场。他停手了。',
  },
}
if LINES.extra then for k, v in pairs(LINES.extraText) do LINES[k] = v end end
`;
c = c.slice(0, oldStart) + newBlock + c.slice(oldEnd);

// ② 力竭（Tired）时说 huff... puff...：在 Game:update 里盯 world.sans.anim（只一次）
const anchor = "  -- 碰撞（world 实体在脚本坐标；soul/walls 在框内相对坐标；统一换算到脚本坐标比对）";
const hook = `  -- 【2026-10-13 用户口径】原版在 SansTired 之后说 "huff... puff..."（Battle.xml Win1）
  do
    local sw = self.world
    if sw and sw.sans and sw.sans.anim == 'Tired' and not self.tiredSaid then
      self.tiredSaid = true
      self:say(LINES.tired)
    end
  end
` + anchor;
if(c.includes(anchor)) c=c.replace(anchor, hook); else console.log('（Tired 钩子锚点未找到）');

// ③ 结局时说 alright, i guess you win.（finish 里）
const fin = "function Game:finish(kind, why)";
const fi = c.indexOf(fin);
if(fi>0){
  const nl = c.indexOf('\n', fi)+1;
  c = c.slice(0,nl) + "  -- 【2026-10-13 用户口径】原版结局台词（Battle.xml Win2）\n  if LINES.win ~= '' then self:say(LINES.win) end\n" + c.slice(nl);
} else console.log('（finish 未找到）');

// ④ 渲染：空台词不画；有台词画在 Sans 头顶上方（不再与 Sans 重合）
const renderOld = "  push(cmds, { kind = 'hudText', text = utf8sub(g.line, g.lineShown), x = VW / 2, y = 86, size = 14, color = '#ffffff', align = 'center' })";
const renderNew = `  -- 【2026-10-13 用户口径】台词改画在 **Sans 头顶上方**（原版是头顶的 SpeechBubble），
  --   并且**空台词不画**（全面替换口径下多数时机不说话）。算式与 sans 命令的 y 同源。
  if g.line and g.line ~= '' then
    local lineY = (boxAbs.y - 16 - SANS_H) - 30
    if lineY < 2 then lineY = 2 end
    push(cmds, { kind = 'hudText', text = utf8sub(g.line, g.lineShown), x = VW / 2, y = lineY, size = 14,
                 color = '#ffffff', align = 'center' })
  end`;
if(c.includes(renderOld)) c=c.replace(renderOld, renderNew); else console.log('（渲染锚点未找到）');
fs.writeFileSync('lua/core.lua', c.replace(/\s+$/,'')+'\n','utf8');
console.log('core 已改：LINES 原版口径 + Tired/结局钩子 + 台词改画头顶/空串不画');
