/* ============================================================================
 * L1 自测（node，无浏览器）：验证 C1–C14 里可离线判定的规则
 * 运行：node prototype/selftest.js
 * 证据等级：L1（纯状态回放）。它**不是**模拟器证据，也不是真机证据。
 *
 * 原作对照（docs/original-research.md）：
 *   - 回合 0 是「不意打ち」开局偷袭；第 12 次攻击后是「中场」（可回血，选仁慈=死）
 *   - Sans 的攻击没有无敌帧 → 「原作」档无敌帧压到 0.15s
 * ========================================================================== */
'use strict';
const Q = require('./game.js');
const DT = 1 / 60;

let pass = 0, fail = 0;
function ok(cond, msg) {
  if (cond) { pass++; console.log('  PASS  ' + msg); }
  else { fail++; console.log('  FAIL  ' + msg); }
}
function head(t) { console.log('\n== ' + t); }
function step(g, seconds) {
  const n = Math.round(seconds / DT);
  for (let i = 0; i < n; i++) { g.update(DT); if (g.state === 'result') return; }
}
/** 一直推进到「玩家回合 / 子菜单 / 结算」 */
function toMenu(g, maxSec = 40) {
  for (let i = 0; i < Math.round(maxSec / DT); i++) {
    if (g.state === 'menu' || g.state === 'sub' || g.state === 'result') return true;
    g.update(DT);
  }
  return false;
}
/** 走完一次「攻击 → Sans 闪开 → 下一回合」 */
function attackTurn(g) {
  g.menuChoose(0);
  if (g.state === 'attack') g.stopAttack();
  for (let i = 0; i < Math.round(3 / DT); i++) { if (g.state !== 'attack') break; g.update(DT); }
}
function has(g, s) { return g.hasLog(s); }

/* ---------------------------------------------------------------- boot */
head('boot：开局初始化 + 回合 0 不意打ち（C9/C10/C17）');
{
  const g = new Q.Game({ seed: 1 });
  g.start();
  ok(has(g, 'game_start'), '日志含 game_start');
  ok(has(g, 'round_start round=0'), '开局先进「回合 0」不意打ち（原作回合 0）');
  ok(g.state === 'enemy', 'state=enemy');
  ok(g.hp === 20 && g.kr === 0, 'HP=20 / KR=0');
  toMenu(g);
  ok(g.state === 'menu' && has(g, 'round_clear round=0'), '撑过偷袭后进入你的回合');
}

/* ------------------------------------------------- first-success：第一波 */
head('first-success：第 1 波无伤（C5/C8 上手保证）');
{
  const g = new Q.Game({ seed: 1 });
  g.start();
  step(g, 1.6);
  ok(has(g, 'wave_clear wave=1'), '日志含 wave_clear wave=1');
  ok(!has(g, 'hit hp='), '未出现受伤日志');
  ok(g.hp === 20, 'HP 仍为 20');
}

/* ------------------------------------------- 骨头预示（冒头 0.5s） */
head('bone-telegraph：地面骨头先冒头 0.5s 再伸出（C14）');
{
  const g = new Q.Game({ seed: 1, startRound: 1 });
  g.start();
  let peekFrames = 0, lethalDuringPeek = false, done = false;
  for (let i = 0; i < Math.round(3 / DT) && !done; i++) {
    g.update(DT);
    const peeks = g.bones.filter(b => b.kind === 'floor' && b.phase === 'peek');
    if (peeks.length) {
      peekFrames++;
      if (peeks.some(b => b.lethal)) lethalDuringPeek = true;
    } else if (peekFrames > 0) done = true;
  }
  const peekSec = peekFrames * DT;
  ok(peekFrames > 0, '出现了"冒头"阶段');
  ok(!lethalDuringPeek, '冒头阶段不致命（纯预示）');
  ok(peekSec >= 0.45 && peekSec <= 0.60, '冒头持续 ≈0.5s（实测 ' + peekSec.toFixed(2) + 's）');
}

/* ------------------------------------------------------- KR 不致死（C3） */
head('kr-floor：KR 烧血但 HP 停在 1，且不 fail（C2/C3）');
{
  const g = new Q.Game({ hp: 2, noSpawn: true, hitsAt: [1.0] });
  g.start();
  step(g, 1.5);
  ok(g.hp === 1, '命中后 HP=1（收到 hp=' + g.hp + '）');
  ok(has(g, 'hit hp=1 kr=1'), '日志含 hit hp=1 kr=1（KR 上限=命中前HP-1=1）');
  step(g, 5.0);
  ok(has(g, 'kr_floor hp=1'), '日志含 kr_floor hp=1');
  ok(has(g, 'kr_done hp=1 kr=0'), '日志含 kr_done hp=1 kr=0');
  ok(g.hp === 1, 'HP 最终仍为 1');
  ok(!has(g, 'fail hp_zero'), '未出现 fail hp_zero（KR 不致死）');
}
head('hp-integer：HP 与 KR 全程为整数（HUD 可读性）');
{
  const g = new Q.Game({ seed: 11, startRound: 1 });
  g.start();
  step(g, 8.0);
  ok(Number.isInteger(g.hp), 'HP 是整数（' + g.hp + '）');
  ok(Number.isInteger(g.kr), 'KR 是整数（' + g.kr + '）');
}

/* --------------------------------------------- 无敌帧：原作档 vs 普通档 */
head('iframes：原作没有无敌帧（C18）');
{
  const countHits = (g) => g.logs.filter(s => s.indexOf('hit hp=') === 0).length;
  const gA = new Q.Game({ hp: 20, noSpawn: true, hitsAt: [1.0, 1.5], diff: 'original' });
  gA.start(); step(gA, 1.7);
  ok(countHits(gA) === 2, '原作档：间隔 0.5s 的两次命中都生效（命中 ' + countHits(gA) + ' 次）');
  const gB = new Q.Game({ hp: 20, noSpawn: true, hitsAt: [1.0, 1.5], diff: 'normal' });
  gB.start(); step(gB, 1.7);
  ok(countHits(gB) === 1, '普通档：0.8s 无敌帧吃掉第二次（命中 ' + countHits(gB) + ' 次）');
}

/* --------------------------------------------- 死亡唯一来源：直接命中 */
head('first-fail：直接命中把 HP 打到 0 才 fail（C1/C4）');
{
  const g = new Q.Game({ hp: 1, noSpawn: true, hitsAt: [1.0] });
  g.start();
  step(g, 1.5);
  ok(g.state === 'result' && g.result === 'fail', 'state=result / result=fail');
  ok(has(g, 'fail hp_zero'), '日志含 fail hp_zero');
}

/* ------------------------------------------------------------- 重开（C9） */
head('restart：重开复位（C9）');
{
  const g = new Q.Game({ seed: 5 });
  g.start();
  for (let i = 0; i < 20; i++) { g.invuln = 0; g.debugHurt('hit'); if (g.state === 'result') break; }
  ok(g.state === 'result' && g.result === 'fail', '先被打到 fail');
  g.restart();
  ok(has(g, 'restart'), '日志含 restart');
  ok(g.hp === 20 && g.kr === 0 && g.round === 0, 'HP/KR/回合复位（hp=' + g.hp + ' kr=' + g.kr + ' round=' + g.round + '）');
  ok(g.state === 'enemy', '回到 Sans 回合（回合 0）');
}

/* ------------------------------------------------------ 蓝骨：静止安全 */
head('blue-bone-still：蓝骨只惩罚移动（C6）');
{
  const g = new Q.Game({ seed: 3, startRound: 3 });
  g.start();
  const nearBlue = () => g.bones.some(b => b.kind === 'blue' && Math.abs((b.y + b.h / 2) - g.soul.y) < 19);
  let overlapped = false;
  for (let i = 0; i < 60 * 6; i++) {
    g.update(DT);
    if (g.state !== 'enemy') break;
    if (nearBlue()) { overlapped = true; break; }
  }
  ok(overlapped, '蓝骨与灵魂发生了重叠（按真实碰撞矩形判定）');
  let hitWhileStill = false;
  for (let i = 0; i < 8; i++) { g.update(DT); if (has(g, 'hit_blue')) hitWhileStill = true; }
  ok(!hitWhileStill, '重叠期间静止 → 无 hit_blue');
  const before = g.hp;
  let hit = false;
  for (let i = 0; i < 240 && g.state === 'enemy'; i++) {
    g.invuln = 0;
    g.move(24, 0);
    g.update(DT);
    if (has(g, 'hit_blue')) { hit = true; break; }
  }
  ok(hit, '重叠期间移动 → 出现 hit_blue');
  ok(g.hp < before, 'HP 下降（' + before + ' → ' + g.hp + '）');
}

/* ------------------------------------------- 橙骨：必须移动才安全（C19） */
head('orange-bone：橙骨只惩罚静止（原作 Color=2）');
{
  const g = new Q.Game({ seed: 3, startRound: 3 });
  g.start();
  const nearColor = (c) => g.bones.some(b => b.kind === 'blue' && b.color === c &&
                                            Math.abs((b.y + b.h / 2) - g.soul.y) < 19);
  /* 蓝/橙交替生成：确认两种颜色都出现过 */
  let sawBlue = false, sawOrange = false;
  for (let i = 0; i < 60 * 12; i++) {
    g.update(DT);
    if (g.state !== 'enemy') break;
    for (const b of g.bones) {
      if (b.kind !== 'blue') continue;
      if (b.color === 'blue') sawBlue = true;
      if (b.color === 'orange') sawOrange = true;
    }
    if (sawBlue && sawOrange) break;
  }
  ok(sawBlue && sawOrange, '蓝骨与橙骨都会出现（sawBlue=' + sawBlue + ' sawOrange=' + sawOrange + '）');

  /* 橙骨重叠时静止 → 命中 */
  const g2 = new Q.Game({ seed: 3, startRound: 3 });
  g2.start();
  let sawOrange2 = false, hitWhileStill = false;
  for (let i = 0; i < 60 * 12 && g2.state === 'enemy'; i++) {
    g2.update(DT);
    const over = g2.bones.some(b => b.kind === 'blue' && b.color === 'orange' &&
                                    Math.abs((b.y + b.h / 2) - g2.soul.y) < 19);
    if (over) {
      sawOrange2 = true;
      if (has(g2, 'hit_orange')) hitWhileStill = true;
      if (hitWhileStill) break;
    }
  }
  ok(sawOrange2 && hitWhileStill, '橙骨重叠且静止 → 出现 hit_orange');
}

/* -------------------------------------------------------- 确定性（C10） */
head('determinism：同 seed + 同输入 → 同日志（C10）');
{
  const a = new Q.Game({ seed: 42 }); a.start(); step(a, 6.0);
  const b = new Q.Game({ seed: 42 }); b.start(); step(b, 6.0);
  ok(a.logs.join('|') === b.logs.join('|'), '两次运行日志完全一致（' + a.logs.length + ' 条）');
  const c = new Q.Game({ seed: 43 }); c.start(); step(c, 6.0);
  ok(a.logs.join('|') !== c.logs.join('|'), '不同 seed → 日志不同（随机确实生效）');
}

/* ------------------------------------------------- 回合推进与菜单（C5/C8） */
head('loop：不意打ち → 你的回合 → 下一次 Sans 回合（C5/C8）');
{
  const g = new Q.Game({ seed: 1, noSpawn: true });
  g.start();
  toMenu(g);
  ok(g.state === 'menu' && has(g, 'round_clear round=0'), '回合 0 结束进入 menu');
  attackTurn(g);
  ok(has(g, 'round_start round=1'), '攻击（被闪开）后进入第 1 回合');
  toMenu(g);
  ok(has(g, 'round_clear round=1'), '日志含 round_clear round=1');
  const hpBefore = g.hp;
  g.menuChoose(2);
  ok(g.state === 'sub' && g.sub === 'item', '道具进入子面板（sub=item）');
  g.subConfirm();
  ok(has(g, 'item_used id=fries'), '道具可用并记日志');
  ok(g.hp >= hpBefore, '回复不减少 HP');
  ok(has(g, 'round_start round=2'), '道具结束回合，进入第 2 回合');
}

/* ------------------------------------------------------- 子菜单：四个选项 */
head('submenus：行动 / 道具 / 仁慈 各自的 UI 与语义（C13）');
{
  const g = new Q.Game({ seed: 1, noSpawn: true });
  g.start(); toMenu(g);
  ok(g.state === 'menu', '进入你的回合');

  g.menuChoose(1);
  ok(g.state === 'sub' && g.sub === 'act', '行动打开面板');
  ok(g.subRows().length === 4, '行动有 4 个选项（检查/挑衅/求饶/沉默）');
  g.subIndex = 3; g.subConfirm();
  ok(has(g, 'act_result id=wait'), '记录 act_result id=wait');
  ok(g.state === 'menu' && !has(g, 'round_start round=1'), '沉默后回到菜单且没推进回合');

  g.menuChoose(1); g.subIndex = 0; g.subConfirm();
  ok(has(g, 'act_result id=inspect'), '检查结束回合 → 进入第 1 回合');

  const g2 = new Q.Game({ hp: 20, noSpawn: true, hitsAt: [2.5] });
  g2.start(); toMenu(g2);
  ok(g2.kr > 0, '先带上 KR（kr=' + g2.kr + '）');
  g2.menuChoose(1); g2.subIndex = 2; g2.subConfirm();
  ok(has(g2, 'kr_cleared by=beg'), '求饶清空 KR');

  const g3 = new Q.Game({ seed: 1, noSpawn: true });
  g3.start(); toMenu(g3);
  g3.menuChoose(1); g3.subIndex = 1; g3.subConfirm();
  ok(has(g3, 'act_taunt level=1'), '挑衅记录 act_taunt level=1');

  const g4 = new Q.Game({ seed: 1, noSpawn: true });
  g4.start(); toMenu(g4);
  g4.menuChoose(3);
  ok(g4.state === 'sub' && g4.sub === 'mercy' && g4.subRows().length === 2, '仁慈面板 2 个选项');
  g4.subIndex = 0; g4.subConfirm();
  ok(has(g4, 'mercy_refused'), '未到最终回合，饶恕被拒');
  toMenu(g4);                                  // 被拒会结束回合 → 进入下一次你的回合
  g4.menuChoose(3); g4.subIndex = 1; g4.subConfirm();
  ok(has(g4, 'flee_refused'), '逃跑被拒');
}

/* ------------------------------------------- 中场（原作第 12 次攻击后） */
head('interlude：第 3 回合后 Sans 停手，仁慈=即死（C16）');
{
  const g = new Q.Game({ seed: 1, noSpawn: true });
  g.start();
  toMenu(g); attackTurn(g);     // 回合 0 → 1
  toMenu(g); attackTurn(g);     // → 2
  toMenu(g); attackTurn(g);     // → 3
  toMenu(g);                    // 回合 3 结束
  ok(g.state === 'menu' && g.interlude === true, '进入中场');
  ok(has(g, 'interlude'), '日志含 interlude');
  const items0 = g.itemCount();
  g.menuChoose(2); g.subConfirm();
  ok(g.state === 'menu' && g.interlude === true, '中场用道具后仍在菜单（不推进回合）');
  ok(g.itemCount() === items0 - 1, '道具确实被消耗');
  g.menuChoose(3);
  ok(has(g, 'fail spared_midpoint'), '中场选仁慈 → 立即死亡');
  ok(g.state === 'result' && g.result === 'fail', '结算为失败');
}

/* ------------------------------------------- 第 2 回合反饱和（用户反馈） */
head('bone_wall：第 2 回合不再全饱和（缺口固定 + 同时只有一道屏障）');
{
  const g = new Q.Game({ seed: 7, startRound: 2, diff: 'hard' });
  g.start();
  let sawBarrier = false, maxWalls = 0, maxWallsAll = 0;
  for (let i = 0; i < Math.round(2.8 / DT); i++) {
    g.update(DT);
    if (g.state !== 'enemy') break;
    if (g.walls.length) sawBarrier = true;
    maxWalls = Math.max(maxWalls, g.walls.length);
  }
  ok(sawBarrier, '第 1 道骨墙确实出现了');
  ok(maxWalls === 1, '屏障是逐个来的（峰值 ' + maxWalls + '）');
  ok(!has(g, 'hit hp='), '站在中间不动能安全穿过第 1 道骨墙（缺口居中，上手保证）');
  for (let i = 0; i < Math.round(8 / DT); i++) {
    g.update(DT);
    if (g.state !== 'enemy') break;
    maxWallsAll = Math.max(maxWallsAll, g.walls.length);
  }
  ok(maxWallsAll <= 1, '整回合同时存在的骨墙不超过 1 道（peak=' + maxWallsAll + '）');
}

/* ------------------------------------------------------------ 难度与调参 */
head('difficulty：难度真的改变弹幕节拍（用户反馈：攻击太快）');
{
  /* 注意：不能用"固定时间窗内的波数"来衡量难度——难度越高你越早死，波数反而更少（幸存者偏差）。
     这里测「相邻两波的生成间隔」，它只由 tune.interval 与 floorLock 决定，与存活时间无关。 */
  const cadence = (diff) => {
    const g = new Q.Game({ seed: 42, startRound: 5, diff });
    g.start();
    let firstAt = -1, secondAt = -1, t = 0, peakLethal = 0;
    for (let i = 0; i < Math.round(20 / DT); i++) {
      g.update(DT); t += DT;
      if (g.state !== 'enemy') break;
      const lethal = new Set(g.bones.filter(b => b.wave != null && b.lethal).map(b => b.wave));
      peakLethal = Math.max(peakLethal, lethal.size);
      if (firstAt < 0 && g.wave >= 1) firstAt = t;
      else if (secondAt < 0 && g.wave >= 2) { secondAt = t; break; }
    }
    return { gap: secondAt - firstAt, peakLethal };
  };
  const e = cadence('easy'), n = cadence('normal'), h = cadence('hard');
  console.log('    生成间隔 easy=' + e.gap.toFixed(2) + 's normal=' + n.gap.toFixed(2) +
              's hard=' + h.gap.toFixed(2) + 's | peakLethal hard=' + h.peakLethal);
  ok(e.gap > h.gap, '简单档生成更慢（' + e.gap.toFixed(2) + 's > ' + h.gap.toFixed(2) + 's）');
  ok(Math.abs(h.gap - 1.20) < 0.12, '困难档受 floorLock 限制，节拍 ≈1.2s（实测 ' + h.gap.toFixed(2) + 's）');
  ok(n.gap > h.gap && n.gap < e.gap, '普通档位于两者之间（' + n.gap.toFixed(2) + 's）');
  ok(h.peakLethal <= 1, '同一时刻最多只有一波地面骨头处于致命阶段（peak=' + h.peakLethal + '）');
}

console.log('\n------------------------------');
console.log('PASS ' + pass + ' / FAIL ' + fail);
process.exit(fail === 0 ? 0 : 1);
