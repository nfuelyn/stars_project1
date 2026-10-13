const fs=require('fs');
let m=fs.readFileSync('lua/main.lua','utf8');
const start=m.indexOf('local function heart(cx, cy, col, r)');
const end=m.indexOf('\nend\n', start)+5;
if(start<0||end<5) throw new Error('heart 未找到');
const old=m.slice(start,end);
const neu = `local function heart(cx, cy, col, r)
  -- 【2026-10-13 用户口径】菜单栏 / 选项栏的红心**直接用战斗里那颗心的模型**（drawSoul 的几何逐字照抄）：
  --   两瓣：直径 9，瓣中心 = 心中心 − 重力方向*2.5 ± 垂直方向*3.5；尖：15×9 三角，尖朝重力方向
  --   菜单里的心恒为初始朝向 dir=1（尖朝下）；外接半径 ≈8 = SOUL_R ⇒ 与战斗中的心**同尺寸同形状**。
  --   （旧实现在这里是另一套"2r×r 的小几何"（r=7/6），所以菜单/选项的心与战斗的心看着不一样。）
  --   r 参数保留签名但**不再参与几何** —— 尺寸一律按战斗模型，杜绝两处不一致。
  local sax, say = 0, 1
  local spx, spy = -say, sax
  local lbx, lby = cx - sax * 2.5, cy - say * 2.5
  local a = circle(lbx + spx * 3.5 - 4.5, lby + spy * 3.5 - 4.5, 9, col)
  local b = circle(lbx - spx * 3.5 - 4.5, lby - spy * 3.5 - 4.5, 9, col)
  local t = rtri(cx + sax * 3.5, cy + say * 3.5, 15, 9, 180, col)
  -- 记录本帧用到的红心控件：帧末统一置顶，避免被按钮黑底（rect 池）之类按创建顺序盖住
  local hs = G_REAL.hearts
  if hs ~= nil then
    if a ~= nil then hs[#hs + 1] = a end
    if b ~= nil then hs[#hs + 1] = b end
    if t ~= nil then hs[#hs + 1] = t end
  end
end
`;
m = m.slice(0,start) + neu + m.slice(end);
fs.writeFileSync('lua/main.lua', m.replace(/\s+$/,'')+'\n','utf8');
console.log('✅ heart() 已替换为战斗红心模型（逐字照抄 drawSoul 几何，忽略旧 r）');
