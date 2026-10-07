const fs = require('fs');
const p = 'lua/main.lua';
let s = fs.readFileSync(p, 'utf8');
const lines = s.split('\n');
const idx = lines.findIndex((l) => l.includes('备注框原来写成'));
if (idx < 0) { console.log('MISS'); process.exit(1); }
console.log('找到坏行：', JSON.stringify(lines[idx].slice(0, 60)) + '…');
const fixed = [
  '      -- 【2026-10-07 修】备注框原来写成 x+w-20 宽 90（text() 不会像 drawHud 那样按对齐回退宽度）→ 文字被画到面板外面；',
  '      --   改为把框左边界放在 x+w-112、宽 92，右对齐后右缘正好落在面板内边距上。',
  "      if note and note ~= \"\" then text(note, x + w - 112, ry, 92, 14, C_DIM, \"Right\") end",
];
lines[idx] = fixed.join('\n');
fs.writeFileSync(p, lines.join('\n').replace(/\s+$/, '') + '\n');
console.log('已修复');
