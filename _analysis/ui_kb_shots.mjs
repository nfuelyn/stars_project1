// 用键盘（右移 → Enter）打开 行动 / 道具 子面板，窄框场景截图（只读）
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
const steps = (n) => { for (let i = 0; i < n; i++) studio.playStep(DT, { observe: false }); };
const key = (k, n = 2) => { studio.playKey(k + 'Down'); steps(n); studio.playKey(k + 'Up'); steps(n); };
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
console.log('菜单 t≈' + t.toFixed(1) + 's');
key('KeyboardMoveRightKey');            // 攻击 → 行动
console.log('右移后:', JSON.stringify(cjk().slice(0, 10)));
key('KeyboardMenuConfirmKey');          // 确认 → 打开行动面板
steps(6);
console.log('确认后:', JSON.stringify(cjk().slice(0, 12)));
shot('kb-sub-act');
key('KeyboardMenuBackKey'); steps(4);
key('KeyboardMoveRightKey');            // 行动 → 道具
key('KeyboardMenuConfirmKey'); steps(6);
console.log('道具面板:', JSON.stringify(cjk().slice(0, 12)));
shot('kb-sub-item');
console.log('done');
