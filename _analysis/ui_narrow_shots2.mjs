// 窄框（内部 22 = bonestab3 → 框 165 宽）下的 行动/道具 子面板截图（只读）
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
const S = init.canvasHeight / 480, OX = (init.canvasWidth - 640 * S) / 2, CH = init.canvasHeight;
const w2c = (wx, wy) => ({ x: OX + wx * S, y: (480 - wy) * S });
const BTN = (i) => ({ x: OX + (85 + (i - 1) * 120 + 55) * S, y: CH - 55 });   // 菜单按钮行贴屏幕底
const steps = (n) => { for (let i = 0; i < n; i++) studio.playStep(DT, { observe: false }); };
const shot = (tag) => { const s = studio.playGet({ view: true }); fs.writeFileSync(path.join(OUTDIR, tag + '.png'), renderScenePng(s.scene, s.canvasWidth, s.canvasHeight).data); console.log('shot ' + tag); };
const textsOf = (node, out = new Set(), d = 0) => { if (!node || d > 8 || typeof node !== 'object') return out; for (const v of Object.values(node)) { if (typeof v === 'string' && v.length <= 40) out.add(v); else if (typeof v === 'object') textsOf(v, out, d + 1); } return out; };
const cjk = () => [...textsOf(studio.playGet({ view: true }).scene)].filter((s) => /[\u4e00-\u9fff]/.test(s));
const DIFF = w2c(97, 230), TAP = w2c(140, 437);
for (let i = 0; i < 50; i++) {
  if (i === 30) studio.playPointer('click', DIFF.x, DIFF.y, { observe: false });
  if (i === 40) { try { studio.playServerSet('Level', 'SansRound', 22); } catch (e) {} }
  if (i === 44) studio.playPointer('click', TAP.x, TAP.y, { observe: false });
  studio.playStep(DT, { observe: false });
}
let t = 0;
while (t < 30 && !cjk().some((s) => s.includes('攻') || s.includes('仁'))) { steps(15); t += 0.5; }
console.log('菜单 t≈' + t.toFixed(1) + 's ；点击 行动 @', JSON.stringify(BTN(2)));
studio.playPointer('click', BTN(2).x, BTN(2).y, { observe: false });
steps(6);
console.log('点后文本:', JSON.stringify(cjk().slice(0, 12)));
shot('narrow2-sub-act');
studio.playKey('KeyboardMenuCancelKeyDown'); steps(2); studio.playKey('KeyboardMenuCancelKeyUp'); steps(6);
studio.playPointer('click', BTN(3).x, BTN(3).y, { observe: false });
steps(6);
console.log('点道具后文本:', JSON.stringify(cjk().slice(0, 12)));
shot('narrow2-sub-item');
console.log('done');
