// 找场景树里的文本，便于脚本判定"菜单是否出现"（只读）
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
function collectTexts(node, out, depth) {
  if (!node || depth > 8) return out;
  if (typeof node === 'object') {
    for (const [k, v] of Object.entries(node)) {
      if (typeof v === 'string' && /[\u4e00-\u9fff]/.test(v) && v.length <= 40) out.push(k + '=' + v);
      else if (typeof v === 'object') collectTexts(v, out, depth + 1);
    }
  }
  return out;
}
for (const t of [3, 4, 5, 6, 8, 10, 12]) {
  steps(Math.round((t - (t === 3 ? 0 : 1)) * (1 / DT)) * 0 + Math.round(1 / DT) * (t === 3 ? 0 : 1));
  if (t === 3) steps(Math.round(3 / DT));
  const s = studio.playGet({ view: true });
  const texts = [...new Set(collectTexts(s.scene, [], 0))].slice(0, 14);
  console.log('t=' + t + 's  ', JSON.stringify(texts));
}
