const fs=require('fs');
let m=fs.readFileSync('lua/main.lua','utf8');
// ① 顶部加一个可调常量（用 M 的字段，避免新增 chunk 级 local —— 主 chunk 已接近 200 上限）
if(!m.includes('M.MENU_HEART_DY')){
  m=m.replace("local G = {\n  -- 模拟器内部模板 GUID","-- 【2026-10-13 用户口径】选项上那颗灵魂（心）相对按钮中线的**下移量**（px）：\n--   选中标记原版贴在按钮内左侧 16px、垂直居中；这里整体下移几像素，视觉上更贴文字基线。\nM.MENU_HEART_DY = 3\n\nlocal G = {\n  -- 模拟器内部模板 GUID");
}
// ② 绘制：菜单行的选中红心 y 加偏移
const o1='    if selected then heart(bx + 16, by + bh / 2, C_RED, 7) end';
const n1='    -- 【2026-10-13】灵魂（心）整体下移 M.MENU_HEART_DY 像素（原来是 by+bh/2 正中）\n    if selected then heart(bx + 16, by + bh / 2 + (M.MENU_HEART_DY or 0), C_RED, 7) end';
if(m.includes(o1)) m=m.replace(o1,n1); else console.log('（绘制行未找到）');
// ③ 命中矩形跟着下移（绘制与判定同源）
const o2='  return bx + 7, y + bh / 2 - 9, 20, 18';
const n2='  -- 【2026-10-13】跟随 M.MENU_HEART_DY 下移，保证"点红心"仍然命中\n  return bx + 7, y + bh / 2 - 9 + (M.MENU_HEART_DY or 0), 20, 18';
if(m.includes(o2)) m=m.replace(o2,n2); else console.log('（命中矩形未找到）');
fs.writeFileSync('lua/main.lua', m.replace(/\s+$/,'')+'\n','utf8');
console.log('main 已改：灵魂下移 ' + 3 + 'px（绘制+命中同步）');
