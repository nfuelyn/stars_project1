// 只读截图：进战斗菜单 → 点「行动」/「道具」，抓子面板（不修改工作区）
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
const SIM = 'D:\\miliastra-beyond-simulator';
const PROJ = 'D:\\stars\\workspace\\sans-fight';
const OUTDIR = 'D:\\stars\\_analysis\\ui-shots';
const { createStudio } = await import(pathToFileURL(path.join(SIM, 'studio', 'index.js')).href);
const { renderScenePng } = await import(pathToFileURL(path.join(SIM, 'studio', 'host-png.js')).href);
fs.mkdirSync(OUTDIR, { recursive: true });
const raw = JSON.parse(fs.readFileSync(path.join(PROJ, 'sans-fight.save.json'), 'utf8'));
const studio = createStudio(1, { workspacePath: path.dirname(path.dirname(PROJ)) });
studio.importData('json', Buffer.from(JSON.stringify(raw), 'utf8').toString('base64'), 'sans-fight.save.json');
studio.playStart({ canvasId: 'pc-16-9' });
const DT = 1 / 30;
const init = studio.playGet({ inspect: false });
const S = init.canvasHeight / 480, OX = (init.canvasWidth - 640 * S) / 2;
const w2c = (wx, wy) => ({ x: OX + wx * S, y: (480 - wy) * S });
let shotN = 0;
function shot(tag) {
  const s = studio.playGet({ view: true });
  const png = renderScenePng(s.scene, s.canvasWidth, s.canvasHeight).data;
  fs.writeFileSync(path.join(OUTDIR, tag + '.png'), png);
  console.log('shot', tag);
}
const steps = (n) => { for (let i = 0; i < n; i++) studio.playStep(DT, { observe: false }); };
const DIFF = w2c(97, 230), TAP = w2c(140, 437);
for (let i = 0; i < 50; i++) {
  if (i === 30) studio.playPointer('click', DIFF.x, DIFF.y, { observe: false });
  if (i === 44) studio.playPointer('click', TAP.x, TAP.y, { observe: false });
  studio.playStep(DT, { observe: false });
}
// 等第一段结束、菜单出现（见面杀 2.8s + 余量）
steps(Math.round(5.0 / DT));
shot('menu-00');
// 菜单按钮：MENU.y=400、bh=42、4 个 110 宽、gap 10 → 居中；依次点 行动(2) / 道具(3)
const BTN = (i) => w2c(85 + (i - 1) * 120 + 55, 421);
studio.playPointer('click', BTN(2).x, BTN(2).y, { observe: false });
steps(4);
shot('sub-act');
studio.playKey('KeyboardMenuCancelKeyDown'); steps(2); studio.playKey('KeyboardMenuCancelKeyUp'); steps(3);
studio.playPointer('click', BTN(3).x, BTN(3).y, { observe: false });
steps(4);
shot('sub-item');
console.log('done ->', OUTDIR);
