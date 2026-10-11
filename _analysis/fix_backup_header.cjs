const fs=require('fs');
const p='D:/stars/main_备份_2026-10-11.lua';
let s=fs.readFileSync(p,'utf8');
const map=[
 ['--       · bindPointer()            ~L2109  （注册 CursorDown/Drag/Up/Click，PC/触摸都走这里）','--       · bindPointer()            L2136  （注册 CursorDown/Drag/Up/Click，PC/触摸都走这里；原文 L2109，备份整体 +27 行）'],
 ['--       · onPointer()              ~L2093  （isClick=true 时调 handleClick(x,y)）','--       · onPointer()              L2120  （isClick=true 时调 handleClick(x,y)）'],
 ['--       · handleClick()            ~L2211  （标题卡/子面板/菜单行/攻击条 的坐标命中）','--       · handleClick()            L2238  （标题卡/子面板/菜单行/攻击条 的坐标命中）'],
 ['--       · menuHitTest/menuButtonRect ~L409-435（菜单行命中矩形，与绘制同源）','--       · menuHitTest/menuButtonRect L436/427（菜单行命中矩形，与绘制同源）'],
 ['--       · M.OnLevelUpdate 的 confirm 回退 ~L2772（点击被界面消费时不另行发确认）','--       · M.OnLevelUpdate 的 confirm 回退 L2799（点击被界面消费时不另行发确认）'],
 ['--       · 设备分流 detectDevice()  ~L333-341 / bindKeys+bindPointer ~L2611-2618','--       · 设备分流 detectDevice() L359 / bindKeys(2018)+bindPointer(2136)'],
 ['--       · joy 表与 joyVector()/inJoyZone()  ~L240-290','--       · joy 表 L273 / joyVector() L295 / inJoyZone() L307'],
 ['--       · CursorDown 里起摇杆（左半屏按下即出现 = 浮动摇杆） ~L2129-2139','--       · CursorDown 里起摇杆（左半屏按下即出现 = 浮动摇杆） L2156-2166'],
 ['--       · applyPointer()（把摇杆向量喂给 core） ~L2356-2380','--       · applyPointer() L2383 / joyDirs() L285 / DEAD=0.22 L279'],
 ['--       · main 只负责画：drawStab()  ~L1035-1055（kind=\'stab\' 的矩形 + 三角）','--       · main 只负责画：drawStab() L1603（kind=\'stab\' 的矩形 + 三角）'],
];
let n=0;
for(const [a,b] of map){ if(s.includes(a)){ s=s.replace(a,b); n++; } else console.log('未找到:', a.slice(0,40)); }
fs.writeFileSync(p,s,'utf8');
console.log('表头已校准 '+n+'/'+map.length);
