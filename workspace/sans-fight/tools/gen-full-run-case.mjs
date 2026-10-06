// gen-full-run-case.mjs -- 生成「整场跑通」试玩回放用例（qxqy-autotest v1）
//
// 为什么要它：模拟器试玩推进一整场（标题页 → 回合 0..6 → 终盘 → 结局 → 重开）需要十几轮
// "点一次攻击 + step"，既慢又会把 Agent 的上下文塞满日志。做成回放用例后，以后只要一次
// `qxqy_studio_play {action:"runCase", args:{case:<本文件内容>}}` 就能回归整场。
//
// 生成的事件刻意做冗余：每 2 秒同时点三个候选落点。
//   * 「攻击」按钮行的 y 会随战斗框变（回合 0 在画布 y≈88.5，回合 1 起被钳到 y≈42），三个都点必然命中；
//   * 点在敌方阶段/攻击条上是无害的（敌方阶段 handleClick 返回 false；攻击条阶段等于提前结算）。
// 这样不依赖精确的回合时序，用例对攻击时长变化有容忍度。
//
// ⚠ 坐标口径（2026-10-05 修正）：画布是**左下原点、Y 向上**，指针事件就是这套坐标
//   （试玩页 play-renderer.js：`hv(){y:(rect.bottom-clientY)*h/rect.height}`），
//   而世界是 640×480、Y 向下 → canvas_y = (480 - world_y) * S。旧版本用例用的是"不翻 Y"的
//   错误口径（631/678 = 世界 421/452 直接乘 S），那些点按在真机上全部落空（点按钮没反应）。
// 用法：node tools/gen-full-run-case.mjs [时长秒=220] [输出文件] [dt]
import fs from 'node:fs';

const seconds = Number(process.argv[2] || 220);
// dt 必须调粗：runCase 单次操作 8000ms 墙钟上限，按 1/30 跑 220 秒（6600 帧）必超时**且会杀掉试玩会话**；
// 0.2 秒/帧时 220 秒只有 1100 帧，能在一次调用内跑完（实测可行）。
const dt = Number(process.argv[4] || 0.2);
// 「攻击」按钮行的**世界** y = 421（回合 0，框下沿 391+12 后钳到 403 再取行中心 ~421）
// 与 452（大框态被钳到 H-46=434 后的行中心）——换算到画布就是 88.5 / 64.5 / 42。
// 只点其中一个候选会让用例永远停在菜单（点了不报错、但不会触发「点按菜单第 N 项」）。
const TAP_YS = [88.5, 64.5, 42];
const caseObj = {
  format: 'qxqy-autotest',
  version: 1,
  name: 'full-run',
  dt,
  playerCount: 1,
  events: [
    // t=1s：标题页点第 1 张难度卡「简单」（画布 1280×720：世界 (97,230) → 画布 (305.5,375)）
    { t: 1, source: 'user', kind: 'pointer', payload: { type: 'click', x: 305.5, y: 375 } },
  ],
  asserts: [
    // 断言必须带 `at`（引擎时间）：不带时 runner 会在 t=0 就求值，那时日志里还没有这些行，必失败。
    { kind: 'log', at: 10, contains: 'main: 阶段 title → enemy' },
    { kind: 'log', at: seconds, contains: '→ result' },   // 结局（击倒/饶恕/失败都算走到结局）
  ],
};

// t=4s 起每 2 秒点一次「攻击」的三个候选落点（行 y 随框下沿变，三个都点必然命中）
for (let t = 4; t <= seconds; t += 2) {
  for (const y of TAP_YS) {
    caseObj.events.push({ t: t + (TAP_YS.indexOf(y) * 0.4), source: 'user', kind: 'pointer', payload: { type: 'click', x: 370, y } });
  }
}
const out = process.argv[3];
if (out) {
  fs.writeFileSync(out, JSON.stringify(caseObj, null, 2));
  console.error(`[gen-full-run-case] 写出 ${out}：${caseObj.events.length} 个事件，覆盖 ${seconds}s 引擎时间`);
} else {
  process.stdout.write(JSON.stringify(caseObj, null, 2));
}
