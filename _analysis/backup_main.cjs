const fs = require('fs');
const src = fs.readFileSync('D:/stars/workspace/sans-fight/lua/main.lua', 'utf8');
const lines = src.split('\n');
const header = [
  '-- ============================================================================',
  '-- 【备份】沙箱 main 文件 —— D:\\stars\\workspace\\sans-fight\\lua\\main.lua',
  '--   备份日期：2026-10-11（备份时刻的原文，未做任何代码改动，仅加本注释块与行内【重点】标注）',
  '--   备份原因：本轮要排查三个问题，需要一份"未改动基线"以便回滚/对照。',
  '--',
  '--   【重点标注 · 三个问题的相关位置】',
  '--   ★ 问题1 PC 鼠标点选：',
  '--       · bindPointer()            ~L2109  （注册 CursorDown/Drag/Up/Click，PC/触摸都走这里）',
  '--       · onPointer()              ~L2093  （isClick=true 时调 handleClick(x,y)）',
  '--       · handleClick()            ~L2211  （标题卡/子面板/菜单行/攻击条 的坐标命中）',
  '--       · menuHitTest/menuButtonRect ~L409-435（菜单行命中矩形，与绘制同源）',
  '--       · M.OnLevelUpdate 的 confirm 回退 ~L2772（点击被界面消费时不另行发确认）',
  '--       · 设备分流 detectDevice()  ~L333-341 / bindKeys+bindPointer ~L2611-2618',
  '--   ★ 问题2 移动端摇杆（固定/浮动）：',
  '--       · joy 表与 joyVector()/inJoyZone()  ~L240-290',
  '--       · CursorDown 里起摇杆（左半屏按下即出现 = 浮动摇杆） ~L2129-2139',
  '--       · applyPointer()（把摇杆向量喂给 core） ~L2356-2380',
  '--       · 摇杆绘制                           搜索 draw_joy / joystick / joy.',
  '--   ★ 问题3 拖拽后升起的骨头（BoneStab/升起骨）判定：',
  '--       · main 只负责画：drawStab()  ~L1035-1055（kind=\'stab\' 的矩形 + 三角）',
  '--       · 判定在 core.lua：World:stabRect() / Game:update 的 bn.stab 分支（本备份不含 core）',
  '-- ============================================================================',
  '',
].join('\n');
fs.writeFileSync('D:/stars/main_备份_2026-10-11.lua', header + src, 'utf8');
console.log('已备份 -> D:/stars/main_备份_2026-10-11.lua  行数=' + lines.length);
