// 扫描：什么时候战斗菜单（攻击/行动/道具/仁慈）出现（只读）
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
const SIM = 'D:\\miliastra-beyond-simulator';
const PROJ = 'D:\\stars\\workspace\\sans-fight';
const { createStudio } = await import(pathToFileURL(path.join(SIM, 'studio', 'index.js')).href);
const raw = JSON.parse(fs.readFileSync(path.join(PROJ, 'sans-fight.save.json'), 'utf8'));
const studio = createStudio(1, { workspacePath: path.dirname(path.dirname(PROJ)) });
studio.importData('json', Buffer.from(JSON.stringify(raw), 'utf8').toString('base64'), 'sans-fight.save.json');
studio.playStart({ canvasId: 'pc-16-9' });
const DT = 1 / 30;
const init = studio.playGet({ inspect: false });
const S = init.canvasHeight / 480, OX = (init.canvasWidth - 640 * S) / 2;
const w2c = (wx, wy) => ({ x: OX + wx * S, y: (480 - wy) * S });
const steps = (n) => { for (let i = 0; i < n; i++) studio.playStep(DT, { observe: false }); };
const DIFF = w2c(97, 230), TAP = w2c(140, 437);
for (let i = 0; i < 50; i++) {
  if (i === 30) studio.playPointer('click', DIFF.x, DIFF.y, { observe: false });
  if (i === 44) studio.playPointer('click', TAP.x, TAP.y, { observe: false });
  studio.playStep(DT, { observe: false });
}
const textsOf = (node, out = new Set(), d = 0) => {
  if (!node || d > 8 || typeof node !== 'object') return out;
  for (const v of Object.values(node)) {
    if (typeof v === 'string' && v.length <= 30) out.add(v);
    else if (typeof v === 'object') textsOf(v, out, d + 1);
  }
  return out;
};
let last = '';
for (let half = 0; half <= 60; half++) {
  steps(15);                                   // 0.5s
  const t = (half * 0.5).toFixed(1);
  const set = textsOf(studio.playGet({ view: true }).scene);
  const hasMenu = [...set].some((s) => s.includes('攻') || s.includes('行') || s.includes('道') || s.includes('仁'));
  const tag = hasMenu ? 'MENU' : '';
  const line = t + 's ' + tag;
  if (line !== last) { console.log(line, hasMenu ? JSON.stringify([...set].filter((s) => /[一-龥]/.test(s)).slice(0, 8)) : ''); last = line; }
  if (hasMenu && !globalThis.__found) { globalThis.__found = Number(t); }
}
console.log('菜单首次出现 ≈', globalThis.__found ?? '未出现', 's');
