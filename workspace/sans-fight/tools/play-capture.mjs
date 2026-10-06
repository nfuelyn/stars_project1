#!/usr/bin/env node
/* ===========================================================================
 * play-capture.mjs —— 用模拟器 Studio 的**无头试玩**跑 sans-fight 存档并截图
 * ---------------------------------------------------------------------------
 * 为什么需要它：正式的 `qxqy_studio_play` 工具只在装了 dsh-plugin 的 DSH 会话里可见，
 * 离线/CI 时没法用。而 `studio/index.js` 的 createStudio 在同一进程里就能
 * start/step/pointer/get，`studio/host-png.js` 能把 Runtime 场景树画成 PNG。
 * 本脚本把两者接起来：加载存档 → 试玩 → 按整场用例的时序点按 → 定时截图 → 汇总日志。
 *
 * 用法：
 *   node tools/play-headless.mjs --seconds 60 --shots 0,1,12,30,60
 *   node tools/play-headless.mjs --seconds 360 --shots 0,1,120,240,330,355   # 整场
 *   node tools/play-headless.mjs --canvas pc-16-9 --seconds 30
 * 产物：records/play-headless/<canvas>-t<秒>.png 与 run.json（日志/错误/时间线）
 * =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const PROJ = path.resolve(HERE, '..');
const SIM = process.env.SIM_ROOT || 'D:\\miliastra-beyond-simulator';
const OUTROOT = path.join(PROJ, 'records', 'play-headless');

const argv = process.argv.slice(2);
const argOf = (k, d) => { const i = argv.indexOf(k); return i >= 0 && argv[i + 1] !== undefined ? argv[i + 1] : d; };
const CANVAS = argOf('--canvas', 'mobile-16-9');
const SECONDS = Number(argOf('--seconds', 30));
const DT = Number(argOf('--dt', 1 / 30));
const SHOTS = String(argOf('--shots', '0,1,5')).split(',').map(Number).filter((n) => Number.isFinite(n));
const DRIVE = argOf('--drive', 'auto');
const STOP_ON = argOf('--stop-on', '');           // auto = 点难度卡 + 菜单攻击；none = 只 step
const SAVE = argOf('--save', path.join(PROJ, 'sans-fight.save.json'));
const ROUND = Number(argOf('--round', 0)) || 0;   // 调试钩子：Level.SansRound（内部回合号，1..19）
const OUTDIR = argOf('--outdir', OUTROOT);

const { createStudio } = await import(pathToFileURL(path.join(SIM, 'studio', 'index.js')).href);
const { renderScenePng } = await import(pathToFileURL(path.join(SIM, 'studio', 'host-png.js')).href);

fs.mkdirSync(OUTDIR, { recursive: true });

const raw = JSON.parse(fs.readFileSync(SAVE, 'utf8'));
const studio = createStudio(1, { workspacePath: path.dirname(PROJ) });   // 工作区 = D:\stars
studio.importData('json', Buffer.from(JSON.stringify(raw), 'utf8').toString('base64'), path.basename(SAVE));

studio.playStart({ canvasId: CANVAS });
if (ROUND > 0) {
  try { studio.playServerSet('Level', 'SansRound', ROUND); console.log('[play-capture] 已设 Level.SansRound =', ROUND); }
  catch (e) { errors.push('serverSet SansRound: ' + e.message); }
}
let snap = studio.playGet({ inspect: true });

const shots = new Set(SHOTS);
const frames = Math.round(SECONDS / DT);
const t0 = Date.now();
const errors = [];
const timeline = [];
const milestones = [];

function shootAt(t) {
  const s = studio.playGet({ view: true });
  const png = renderScenePng(s.scene, s.canvasWidth, s.canvasHeight).data;
  const name = `${CANVAS}-t${String(t.toFixed(2)).replace('.', '_')}.png`;
  fs.writeFileSync(path.join(OUTDIR, name), png);
  return name;
}

// 点按计划：标题页点第 1 张难度卡；敌方阶段/菜单里每 2 秒点攻击按钮的三个候选落点。
// 坐标从「世界 640x480」换算到当前画布，换画布不用改常量：
//   S = 画布高/480，OX = (画布宽 - 640*S)/2（等比缩放、水平居中），
//   canvas_x = OX + world_x*S，canvas_y = (480 - world_y)*S（画布 Y 从底边向上）。
const _init = studio.playGet({ inspect: false });
const _S = _init.canvasHeight / 480;
const _OX = (_init.canvasWidth - 640 * _S) / 2;
const w2c = (wx, wy) => ({ x: _OX + wx * _S, y: (480 - wy) * _S });
const DIFFICULTY_CARD = w2c(97, 230);
const TAP_YS = [w2c(140, 421).y, w2c(140, 437).y, w2c(140, 452).y];
const TAP_X = w2c(140, 421).x;
function driveClicks(t) {
  if (DRIVE === 'none') return [];
  const out = [];
  if (t < 2 && t + DT >= 1) out.push(DIFFICULTY_CARD);            // t≈1s 选难度
  if (t >= 4 && Math.abs(t % 2) < DT / 2) {
    for (const y of TAP_YS) out.push({ x: TAP_X, y });
  }
  return out;
}

const startedAt = new Date().toISOString();
for (let i = 0; i <= frames; i++) {
  const t = i * DT;
  if (SHOTS.some((v) => Math.abs(t - v) < DT / 2)) {
    try { timeline.push({ t, shot: shootAt(t) }); } catch (e) { errors.push(`shot t=${t}: ${e.message}`); }
  }
  if (STOP_ON && i % 30 === 0 && i > 0) {
    try {
      const st = studio.playGet({ inspect: false });
      const hit = (st.logs || []).some((l) => new RegExp(STOP_ON).test(typeof l === 'string' ? l : (l.text || '')));
      if (hit) {
        try { timeline.push({ t, shot: shootAt(t), stopOn: STOP_ON }); } catch (e) { errors.push('stopshot t=' + t + ': ' + e.message); }
        console.log('[play-headless] 命中停止条件 ' + STOP_ON + ' @ t=' + t.toFixed(2) + 's');
        break;
      }
    } catch (e) { errors.push('check t=' + t + ': ' + e.message); }
  }
  const clicks = driveClicks(t);
  for (const c of clicks) {
    try { studio.playPointer('click', c.x, c.y, { observe: false }); } catch (e) { errors.push(`click t=${t}: ${e.message}`); }
  }
  if (i < frames) {
    try { studio.playStep(DT, { observe: false }); } catch (e) { errors.push(`step t=${t}: ${e.message}`); if (errors.length > 5) break; }
  }
  if (i % 300 === 0) {
    try {
      const st = studio.playGet({ inspect: false });
      milestones.push({ t, time: st.time, frame: st.frame });
    } catch (e) { errors.push(`status t=${t}: ${e.message}`); }
  }
}
const wall = ((Date.now() - t0) / 1000).toFixed(1);

const final = studio.playGet({ inspect: true, view: true });
const logs = (final.logs || []).map((l) => (typeof l === 'string' ? l : (l.text || l.message || JSON.stringify(l))));
const interesting = logs.filter((l) => /main |game_start|round_|hit |kr_|result|pool=|phase|kill|fail|ERR|NIL|胜利|结局/.test(String(l)));
const report = {
  canvas: CANVAS, seconds: SECONDS, dt: DT, frames, wallSeconds: Number(wall),
  startedAt, finishedAt: new Date().toISOString(),
  final: {
    time: final.time, frame: final.frame, running: final.running,
    keys: Object.keys(final), treeNodes: (final.tree || []).length, sceneNodes: (final.scene?.nodes || []).length, paintItems: (final.paint || []).length,
    canvasWidth: final.canvasWidth, canvasHeight: final.canvasHeight, canvasId: final.canvasId,
  },
  errorCount: errors.length, errors: errors.slice(0, 20),
  interestingLogs: interesting.slice(-120),
  logCount: logs.length,
  milestones, timeline,
};
fs.writeFileSync(path.join(OUTDIR, 'run.json'), JSON.stringify(report, null, 2));
fs.writeFileSync(path.join(OUTDIR, 'logs.txt'), logs.join('\n'), 'utf8');

console.log(`[play-headless] ${CANVAS} ${SECONDS}s（${frames} 帧）→ ${wall}s 墙钟`);
console.log(`[play-headless] 最终 t=${final.time?.toFixed?.(2)} frame=${final.frame} 树节点=${report.final.treeNodes} 日志=${logs.length} 错误=${errors.length}`);
for (const e of errors.slice(0, 5)) console.log('  ERR ' + e);
console.log('[play-headless] 关键日志（末尾 25 条）：');
for (const l of interesting.slice(-25)) console.log('  ' + l);
console.log(`[play-headless] 截图：${timeline.map((x) => x.shot).join(', ') || '（无）'}`);
studio.playStop();

