const fs=require('fs');
const src=fs.readFileSync('D:/stars/workspace/sans-fight/lua/main.lua','utf8');
const lines=src.split('\n');
// 动态找锚点行号（找不到就标 ?）
const anchors=[
  ['问题1 bindPointer()','local function bindPointer'],
  ['问题1 onPointer()','local function onPointer'],
  ['问题1 handleClick()','handleClick = function'],
  ['问题1 menuButtonRect()','local function menuButtonRect'],
  ['问题1 menuHitTest()','local function menuHitTest'],
  ['问题2 joy 表','local joy ='],
  ['问题2 joyVector()','local function joyVector'],
  ['问题2 inJoyZone()','local function inJoyZone'],
  ['问题2 CursorDown 起摇杆','joy.bx, joy.by = JOY_HOME_X'],
  ['问题2 joystickGeom()','local function joystickGeom'],
  ['问题2 drawJoystick()','local function drawJoystick'],
  ['问题3 drawStab()','local function drawStab'],
  ['问题3 drawBar()','local function drawBar'],
  ['设备分流 detectDevice()','local function detectDevice'],
  ['结局页点击（重开二次确认）','if st == \'result\' then'],
];
const rows=anchors.map(([name,pat])=>{
  const i=lines.findIndex(l=>l.includes(pat));
  return '--       · '+name.padEnd(30,' ')+' L'+(i>=0?(i+1):'?');
});
const header=[
'-- ============================================================================',
'-- 【备份·刷新版】沙箱 main 文件 —— D:\\stars\\workspace\\sans-fight\\lua\\main.lua',
'--   刷新时间：2026-10-11（**已包含当日全部更新**；除本注释块外与沙箱原文件逐字节一致）',
'--',
'--   本备份包含的当日改动：',
'--     ① 移动端**固定摇杆**：基准点固定 JOY_HOME(84,392)、吸附区 ±120/±150、常显淡底盘',
'--     ② 骨刺**一排骨刺**渲染（drawStab：间距 13 / 厚 10 ⇒ 缝 3px < 判定 4px；判定仍整条边）',
'--     ③ 标题页提示：PC 按空格确认、鼠标无法选定（文案在 core.lua）',
'--     ④ 重开二次确认（core.requestRestart；本文件的结局页点击已改走它）',
'--     ⑤ 修复主 chunk 局部变量超限（drawStab 移到 drawBar 之后、摇杆常量内联）',
'--',
'--   【重点标注 · 三个问题的相关位置（本文件行号）】',
...rows,
'--   （行号随每次刷新重新计算；备份不含 core.lua，判定相关在 core 的 World:stabRect / bn.stab 分支）',
'-- ============================================================================',
'',
].join('\n');
fs.writeFileSync('D:/stars/main_备份_2026-10-11.lua', header+src, 'utf8');
console.log('已刷新备份（含当日更新），行数='+lines.length);
console.log(rows.join('\n'));
