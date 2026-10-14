// tools/bake-textart.mjs —— 复刻 another/BadTime-.../tools/generate_textart.py 的算法，
//   用 @napi-rs/canvas (Skia) 取代 PIL：字体同为 msyh.ttc(微软雅黑) 16px / consola.ttf 16px，
//   同样按「阈值 96、逐行游程合并」编码成 T.glyphs[码点] = {w, advance, rects}。
//
// 为什么需要它：textart.lua 是**离线烘焙**的字形库，运行时没有字体。
//   文案一旦用到库里没有的字，main.lua 会回退成 '?'（codepoint 63）—— 就是"问号"的来源。
//   生成器的字符集 = lua/*.lua 里出现的全部非 ASCII 字符，所以补字只要重跑一次。
//
// 用法：
//   node tools/bake-textart.mjs --check 心 移 骨      # 与现有条目比对（不改文件）
//   node tools/bake-textart.mjs --missing            # 列出「库里缺、但被用到」的字
//   node tools/bake-textart.mjs --write              # 只补缺失字形（已有条目原样保留）
import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';

const HERE = path.dirname(url.fileURLToPath(import.meta.url));
const PROJ = path.dirname(HERE);
const TEXTART = path.join(PROJ, 'lua', 'textart.lua');
const CANVAS_LIB = 'D:/miliastra-beyond-simulator/node_modules/@napi-rs/canvas/index.js';
const { createCanvas, GlobalFonts } = await import('file:///' + CANVAS_LIB);

GlobalFonts.registerFromPath(process.env.CJK_FONT || 'C:/Windows/Fonts/msyh.ttc', 'MSYH');
GlobalFonts.registerFromPath('C:/Windows/Fonts/consola.ttf', 'CONS');

const H = 20, THRESH = 96, DY = 0;         // DY 由 --check 标定
const canvas = createCanvas(64, H);
const ctx = canvas.getContext('2d');

function bake(ch, dy = DY) {
  const cp = ch.codePointAt(0);
  const isAscii = cp < 127;
  const font = isAscii ? '16px CONS' : '16px MSYH';
  ctx.font = font;
  const adv = Math.max(1, Math.round(ctx.measureText(ch).width));
  const W = adv + 2;
  canvas.width = W; canvas.height = H;      // 改尺寸会清空画布
  ctx.font = font;
  ctx.textBaseline = 'top';
  ctx.fillStyle = '#fff';
  ctx.fillText(ch, 0, dy);
  const d = ctx.getImageData(0, 0, W, H).data;
  const rects = [];
  let previous = new Map();
  for (let y = 0; y < H; y++) {
    const runs = new Map();
    let x = 0;
    while (x < W) {
      const k = (y * W + x) * 4;
      if (d[k] < THRESH) { x++; continue; }
      const start = x;
      while (x < W && d[(y * W + x) * 4] >= THRESH) x++;
      const key = start + ':' + (x - start);
      if (previous.has(key)) rects[previous.get(key)][3]++;
      else { runs.set(key, rects.length); rects.push([start, y, x - start, 1]); }
      runs.set(key, rects.length - 1);
    }
    previous = runs;
  }
  return { w: W, advance: adv, rects };
}

// ---- 读现有库（一行一个字形；rects 里是嵌套花括号，用行尾贪婪解析）----
const src = fs.readFileSync(TEXTART, 'utf8');
const EOL = src.includes('\r\n') ? '\r\n' : '\n';       // 仓库 checkout 可能是 CRLF，别把它吃掉
const lines = src.split(/\r?\n/);
const existing = new Map();
for (const line of lines) {
  const m = /^T\.glyphs\[(\d+)\] = \{w=(\d+), advance=(\d+), rects=\{(.*)\}\}$/.exec(line);
  if (!m) continue;
  const rects = [...m[4].matchAll(/\{(-?\d+),(-?\d+),(-?\d+),(-?\d+)\}/g)].map(r => [+r[1], +r[2], +r[3], +r[4]]);
  existing.set(+m[1], { w: +m[2], advance: +m[3], rects });
}
console.log('现有字形 ' + existing.size + ' 个');

function bits(g) {
  const b = new Set();
  for (const [x, y, w, h] of g.rects) for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) b.add((x + i) + ',' + (y + j));
  return b;
}
function iou(a, b) { let inter = 0; for (const k of a) if (b.has(k)) inter++; return inter / (a.size + b.size - inter); }

// ---- 收集 lua/*.lua 里用到的全部字符（与 Python 生成器同一规则）----
function usedChars() {
  const set = new Set();
  for (let i = 32; i < 127; i++) set.add(String.fromCharCode(i));
  for (const f of fs.readdirSync(path.join(PROJ, 'lua'))) {
    if (!f.endsWith('.lua') || f === 'textart.lua') continue;
    const t = fs.readFileSync(path.join(PROJ, 'lua', f), 'utf8');
    for (const ch of t) if (ch.codePointAt(0) > 127) set.add(ch);
  }
  return set;
}
function toLine(cp, g) {
  const enc = g.rects.map(r => '{' + r.join(',') + '}').join(',');
  return 'T.glyphs[' + cp + '] = {w=' + g.w + ', advance=' + g.advance + ', rects={' + enc + '}}';
}

const mode = process.argv[2] || '--check';
if (mode === '--check') {
  for (const ch of process.argv.slice(3)) {
    const cp = ch.codePointAt(0), ex = existing.get(cp);
    if (!ex) { console.log(ch + '(' + cp + '): 库里没有'); continue; }
    let best = null;
    for (const dy of [-3, -2, -1, 0, 1]) {
      const g = bake(ch, dy);
      if (g.w !== ex.w) { if (!best) best = { dy, s: -1 }; continue; }
      const s = iou(bits(g), bits(ex));
      if (!best || s > best.s) best = { dy, s, n: g.rects.length };
    }
    console.log(ch + '(' + cp + '): 现有 w=' + ex.w + ' rects=' + ex.rects.length +
      ' → 最佳 dy=' + best.dy + (best.s >= 0 ? ' IoU=' + best.s.toFixed(3) + ' rects=' + best.n : ' 尺寸不符'));
  }
} else if (mode === '--show') {
  // 把「现有字形」与「本地重烘」的位图并排打出来，肉眼比对风格是否一致
  for (const ch of process.argv.slice(3)) {
    const ex = existing.get(ch.codePointAt(0));
    const g = bake(ch, DY);
    const render = (gg) => {
      const W = Math.max(gg.w, 1), rows = [];
      const b = bits(gg);
      for (let y = 0; y < H; y++) { let r = ''; for (let x = 0; x < W; x++) r += b.has(x + ',' + y) ? '#' : '.'; rows.push(r); }
      return rows;
    };
    console.log('===== ' + ch + ' (w现有=' + (ex && ex.w) + ' 新=' + g.w + ') =====');
    if (!ex) { console.log(render(g).join('\n')); continue; }
    const a = render(ex), c = render(g);
    for (let y = 0; y < H; y++) console.log((a[y] || '') + '   |   ' + (c[y] || ''));
  }
} else if (mode === '--missing') {
  const miss = [...usedChars()].filter(ch => !existing.has(ch.codePointAt(0)));
  console.log('库里缺、但被 lua/*.lua 用到的字符 ' + miss.length + ' 个: ' + miss.join(' '));
// 注：'只扫会真正上屏的文案' 的检查已改由 Lua 探针
//   lua/probes/_probe_textart_coverage.lua 承担（驱动各状态后逐字比对 render 命令，零误报）。
} else if (mode === '--write') {
  const miss = [...usedChars()].filter(ch => !existing.has(ch.codePointAt(0))).sort((a, b) => a.codePointAt(0) - b.codePointAt(0));
  if (!miss.length) { console.log('没有缺字，无需改动'); process.exit(0); }
  const out = [];
  for (const line of lines) {
    const m = /^T\.glyphs\[(\d+)\] = /.exec(line);
    if (m) for (const ch of miss.slice()) {
      if (ch.codePointAt(0) < +m[1]) { out.push(toLine(ch.codePointAt(0), bake(ch))); miss.splice(miss.indexOf(ch), 1); }
    }
    out.push(line);
  }
  for (const ch of miss) out.push(toLine(ch.codePointAt(0), bake(ch)));
  fs.writeFileSync(TEXTART, out.join(EOL), 'utf8');
  console.log('已补 ' + (miss.length + 0) + ' 个字形（其余条目原样保留）');
}