const fs=require('fs');
const p='lua/main.lua';
let s=fs.readFileSync(p,'utf8');

// 1) inJoyZone 内联常量（省掉 2 个 chunk 级 local —— Lua 主 chunk 已到 200 上限）
s = s.replace(
/-- 【2026-10-11 用户口径·固定摇杆】吸附区围绕\*\*固定中心\*\*（JOY_HOME = 原神预设位置）：[\s\S]*?local JOY_ZONE_DX, JOY_ZONE_DY = 120, 150      -- 中心左右 \/ 上下各允许的吸附范围（世界 px）\nlocal function inJoyZone\(wx, wy\)\n  return math\.abs\(wx - JOY_HOME_X\) <= JOY_ZONE_DX\n     and math\.abs\(\(wy or JOY_HOME_Y\) - JOY_HOME_Y\) <= JOY_ZONE_DY\nend/,
`-- 【2026-10-11 用户口径·固定摇杆】吸附区围绕**固定中心**（JOY_HOME = 原神预设位置）：
--   手指落在中心附近就抓住摇杆（不必精确点中圆），中心本身**永远不动**；可点 UI 仍然优先。
-- PC 分支根本不调用这个函数（鼠标不起摇杆，见 bindPointer）。
local function inJoyZone(wx, wy)
  return math.abs(wx - JOY_HOME_X) <= 120
     and math.abs((wy or JOY_HOME_Y) - JOY_HOME_Y) <= 150
end`);

// 2) 取出 drawStab 块（含我加的 local drawBar 前置声明），挪到 drawBar 定义之后
const startMark='local drawBar                                  -- 前置声明（定义在下面；drawStab 要用它画一排小骨）';
const si=s.indexOf(startMark);
if(si<0) throw new Error('找不到 drawStab 块起点');
const stabEndMark='\nend\n';
const sEnd=s.indexOf(stabEndMark, si);
const stabBlock=s.slice(si, sEnd+stabEndMark.length);
s = s.slice(0,si) + s.slice(sEnd+stabEndMark.length).replace(/^\n+/,'');
// 把 drawBar 的赋值写法还原成 local function（保持原有作用域写法）
s = s.replace('drawBar = function(x, y, w, h, color)', 'local function drawBar(x, y, w, h, color)');
// 3) 在 drawBar 定义结束之后插入 drawStab
const barStart=s.indexOf('local function drawBar(x, y, w, h, color)');
const barEnd=s.indexOf('\nend\n', barStart);
const insertAt=barEnd+5;
const stabText=stabBlock.replace(startMark+'\n','').replace(/^local function drawStab/,'local function drawStab');
s = s.slice(0,insertAt) + '\n' + stabText + s.slice(insertAt);
fs.writeFileSync(p, s.replace(/\s+$/,'')+'\n','utf8');
console.log('已重排：drawStab 移到 drawBar 之后，去掉 2+1 个 chunk 级 local');
