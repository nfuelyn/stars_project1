/* ============================================================================
 * Sans 弹幕审判 —— 核心逻辑（无 DOM 依赖，可在 node 中运行 selftest）
 * slug: sans-fight  步骤 3 HTML 效果展示
 *
 * 坐标：设计画布 1280×720，原点左上、Y 向下（HTML 习惯）。
 *       千星侧为原点左下、Y 向上 —— 换算集中在 qxqyY() 一处，禁止把这里的像素直接搬进 Lua。
 * 时间：所有运动显式消费 dt；随机由 seed 决定（mulberry32），保证 C10 确定性。
 * ========================================================================== */
(function (global) {
  'use strict';

  var DESIGN_W = 1280, DESIGN_H = 720;
  var BOX_CX = 640, BOX_CY = 366;
  var DT = 1 / 60;

  /* ---------------------------------------------------------------- 工具 */
  function mulberry32(a) {
    return function () {
      a |= 0; a = a + 0x6D2B79F5 | 0;
      var t = Math.imul(a ^ a >>> 15, 1 | a);
      t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
      return ((t ^ t >>> 14) >>> 0) / 4294967296;
    };
  }
  /** 千星坐标换算点：HTML(Y向下) → 千星(Y向上)。仅用于将来对接 Lua 时参考。 */
  function qxqyY(y) { return DESIGN_H - y; }
  function clamp(v, a, b) { return v < a ? a : (v > b ? b : v); }
  function rectHit(cx, cy, r, rc) {
    var nx = clamp(cx, rc.x, rc.x + rc.w), ny = clamp(cy, rc.y, rc.y + rc.h);
    var dx = cx - nx, dy = cy - ny;
    return dx * dx + dy * dy <= r * r;
  }

  /* ------------------------------------------------------- 回合脚本（GDD §5） */
  /* v2 调参（用户反馈：攻击太快、第 2 回合全饱和）：
     - 所有间隔 ×DIFF.interval、所有速度 ×DIFF.speed、冲击波预警 ×DIFF.warn
     - 第 2 回合骨墙：缺口 3→4 格、速度 150→110、间隔 1.6→2.2，且上一道墙走过中线才会刷新（不再叠墙饱和） */
  var ROUNDS = [
    { n: 1, bw: 420, bh: 260, dur: 9,  pattern: 'bone_floor', p: { interval: 1.35 } },
    { n: 2, bw: 420, bh: 260, dur: 10, pattern: 'bone_wall',  p: { speed: 110, gap: 4, interval: 2.20 } },
    { n: 3, bw: 420, bh: 260, dur: 10, pattern: 'blue_bone',  p: { blue: 1.80, white: 2.60 } },
    { n: 4, bw: 420, bh: 260, dur: 10, pattern: 'blaster',    p: { interval: 2.20, warn: 0.90 } },
    { n: 5, bw: 360, bh: 240, dur: 11, pattern: 'mixed',      p: { interval: 1.15, wallSpeed: 130, wallInterval: 2.40 } },
    { n: 6, bw: 660, bh: 400, dur: 12, pattern: 'blue_soul',  p: { gravity: 820, jump: -560, boneInterval: 1.60 } }
  ];
  function roundDef(n) { if (n === 0) return SURPRISE; return ROUNDS[clamp(n, 1, ROUNDS.length) - 1]; }

  var DIFFS = {
    easy:     { key: 'easy',     label: '简单', speed: 0.60, interval: 1.60, warn: 1.45, invuln: 1.00, note: '慢速 · 间隔大 · 预警长' },
    normal:   { key: 'normal',   label: '普通', speed: 0.78, interval: 1.35, warn: 1.20, invuln: 0.80, note: '推荐' },
    hard:     { key: 'hard',     label: '困难', speed: 1.00, interval: 1.00, warn: 1.00, invuln: 0.55, note: '基准速度' },
    /* 原作档：Sans 的攻击**没有无敌帧**（"ignore invincibility"），这里压到 0.15s，
       保留一点点是为了避免同一帧多重判定造成的瞬间融化。 */
    original: { key: 'original', label: '原作', speed: 1.25, interval: 1.00, warn: 1.00, invuln: 0.15, note: '无无敌帧 · 逐击扣血' }
  };
  var DIFF_ORDER = ['easy', 'normal', 'hard', 'original'];

  /* 回合 0：原作的「不意打ち」——开局先制偷袭（骨波 + 一发光束）。
     冒头预警仍是统一的 0.5s：偷袭体现在"没有招呼、立刻开始"，不靠砍预警时间。 */
  var SURPRISE = { n: 0, bw: 420, bh: 260, dur: 2.8, pattern: 'surprise', p: { interval: 1.4 } };

  var ACT_OPTIONS = [
    { id: 'inspect', name: '检查',   hint: '看他的数据（结束回合）',       effect: 'end',
      result: '审判者　ATK 1　DEF 1 —— 他只有 1 点 HP，但他从不站着让你打。' },
    { id: 'taunt',   name: '挑衅',   hint: '下一回合他更快（结束回合）',   effect: 'taunt',
      result: '（他眯起眼睛）好啊。那我再快一点。' },
    { id: 'beg',     name: '求饶',   hint: '立刻清空 KR（结束回合）',       effect: 'beg',
      result: '（他叹了口气）……你身上的紫气淡了一点。' },
    { id: 'wait',    name: '沉默',   hint: '什么都不做（不结束回合）',       effect: 'wait',
      result: '（你什么也没做。他也什么都没做。）' }
  ];
  var SUB_TITLE = { act: '行动', item: '道具', mercy: '仁慈' };

  var SOUL_R = 8, SOUL_SPEED = 260, INVULN = 0.8;
  var KR_PER_HIT = 4, KR_TICK = 0.5;
  var MAX_HP = 20;

  /* 地面骨头的四段生命：冒头(预示,非致命) → 伸出 → 保持 → 收回。
     冒头间隔固定 0.5s（用户指定），不随难度缩放，保证"看得懂"这条底线。 */
  var PEEK = 0.5, EXTEND = 0.15, HOLD = 0.55, RETRACT = 0.20, TIP_H = 16;

  var LINES = {
    surprise: '（他没有打招呼，先动手了。）',
    r1:      '站住别动，让我看看你躲得怎么样。',
    r2:      '骨头是会走路的东西，别被它撞上。',
    r3:      '蓝色的骨头：别动。你动一下，它就咬你。',
    r4:      '抬头看看，朋友。',
    r5:      '你还没死？那我再认真一点。',
    r6:      '……你已经撑过六回合了。',
    dodge:   '（他侧身闪开了）',
    refuse:  '（他摇了摇头）',
    flee:    '（他摇了摇头）你逃不掉的。',
    final:   '好吧。轮到你了。'
  };

  /* ================================================================= Game */
  function Game(opts) {
    opts = opts || {};
    this.bootSeed = (opts.seed == null) ? 20260927 : opts.seed;
    this.bootHP = (opts.hp == null) ? MAX_HP : opts.hp;
    this.bootRound = (opts.startRound == null) ? 1 : opts.startRound;
    this.testAimWave1 = !!opts.aimWave1;   // 测试入口：第 1 波不留出生点安全位
    this.testNoSpawn = !!opts.noSpawn;     // 测试入口：不生成弹幕（隔离 KR / 生命规则）
    this.testHitsAt = (opts.hitsAt || []).slice();  // 测试入口：在指定秒数强制命中（走同一条 hurt 路径）
    this.titleIndex = DIFF_ORDER.indexOf(opts.diff) >= 0 ? DIFF_ORDER.indexOf(opts.diff) : 1;
    this.diffKey = DIFF_ORDER[this.titleIndex];
    this.logs = [];
    this.resetRun();
    this.state = 'title';
  }

  Game.prototype.setDiff = function (i) {
    this.titleIndex = clamp(i, 0, DIFF_ORDER.length - 1);
    this.diffKey = DIFF_ORDER[this.titleIndex];
    return this.diffKey;
  };
  Game.prototype.sp = function (v) { return v * this.tune.speed; };      // 速度缩放
  Game.prototype.it = function (v) { return v * this.tune.interval; };   // 间隔缩放

  /* ------------------------------------------------------------ 生命周期 */
  Game.prototype.log = function (s) {
    this.logs.push(s);
    if (typeof console !== 'undefined' && console.log) console.log('[qxqy] ' + s);
  };
  Game.prototype.hasLog = function (s) {
    for (var i = 0; i < this.logs.length; i++) if (this.logs[i].indexOf(s) >= 0) return true;
    return false;
  };
  Game.prototype.logsFrom = function (n) { return this.logs.slice(n); };

  Game.prototype.resetRun = function () {
    this.hp = this.bootHP;
    this.kr = 0;
    this.items = [
      { id: 'fries', name: '雪镇薯条', desc: '回复 8 HP',  heal: 8,  count: 1 },
      { id: 'cat',   name: '热猫',     desc: '回复 12 HP', heal: 12, count: 1 }
    ];
    this.taunt = 0;
    this.talk = [];
    this.round = this.bootRound;
    this.invuln = 0;
    this.flash = 0;
    this.krFloorLogged = false;
    this.krActive = false;
    this.krT = 0;
    this.final = false;
    this.result = null;
    this.failReason = null;
    this.interlude = false;
    this.menuIndex = 0;
    this.attackCursor = 0;
    this.attackDir = 1;
    this.attackResult = null;
    this.attackHold = 0;
    this.sansDodge = 0;
    this.line = '';
    this.lineShown = 0;
    this.lineT = 0;
    this.rng = mulberry32(this.bootSeed);
    this.box = { x: BOX_CX - 210, y: BOX_CY - 130, w: 420, h: 260 };
    this.soul = { x: BOX_CX, y: BOX_CY, vx: 0, vy: 0, mode: 'red', grounded: false };
    this.bones = [];
    this.walls = [];
    this.blasters = [];
    this.platforms = [];
    this.wave = 0;
    this.wavesAlive = {};
  };

  /** 标题页 → 开局。日志 game_start。 */
  Game.prototype.start = function () {
    this.tune = DIFFS[this.diffKey] || DIFFS.normal;
    this.resetRun();
    this.log('game_start hp=' + this.hp + ' kr=' + this.kr + ' round=' + this.round + ' seed=' + this.bootSeed + ' diff=' + this.tune.key);
    this.startEnemy(this.bootRound > 1 ? this.bootRound : 0);   // 默认从回合 0（不意打ち）开始
  };

  Game.prototype.restart = function () {
    this.log('restart');
    this.start();
  };

  Game.prototype.startEnemy = function (n) {
    var d = roundDef(n);
    this.round = n;
    this.state = 'enemy';
    this.enemyT = 0;
    this.enemyDur = d.dur;
    this.spawnT = this.it((d.pattern === 'bone_wall' || d.pattern === 'mixed') ? 0.9 : 0.8);
    this.wallT = this.it(1.6);
    this.warn = (d.p.warn || 0.6) * this.tune.warn;   // 冲击波预警时长（难度可调）
    this.warnWall = 0.75 * this.tune.warn;            // 骨墙缺口预警时长
    if (n === 2) this.firstBarrierDone = false;
    this.spd = 1 + 0.10 * (this.taunt || 0);          // 挑衅代价：之后每回合再快 10%
    this.wave = 0;
    this.wavesAlive = {};
    this.floorLock = 0;
    this.colorFlip = false;
    this.bones = []; this.walls = []; this.blasters = []; this.platforms = [];
    this.box = { x: BOX_CX - d.bw / 2, y: BOX_CY - d.bh / 2, w: d.bw, h: d.bh };
    this.soul.mode = (d.pattern === 'blue_soul') ? 'blue' : 'red';
    this.soul.vx = 0; this.soul.vy = 0;
    this.soul.x = BOX_CX;
    this.soul.y = (d.pattern === 'blue_soul') ? this.box.y + this.box.h - 40 : BOX_CY;
    this.prevX = this.soul.x; this.prevY = this.soul.y;
    if (d.pattern === 'blue_soul') this.buildPlatforms();
    this.log('round_start round=' + n);
    if (d.pattern === 'surprise') {                       // 不意打ち：开局立刻偷袭
      this.spawnFloor(d.p.peek);
      this.spawnBlaster(1);
      this.spawnT = this.it(d.p.interval);
    }
    this.say(n === 0 ? LINES.surprise : (n === 1 ? LINES.r1 : (n === 2 ? LINES.r2 : (n === 3 ? LINES.r3 : (n === 4 ? LINES.r4 : (n === 5 ? LINES.r5 : LINES.r6))))));
  };

  Game.prototype.endEnemy = function () {
    this.log('round_clear round=' + this.round);
    this.bones = []; this.walls = []; this.blasters = [];
    this.state = 'menu';
    this.menuIndex = 0;
    this.final = (this.round >= ROUNDS.length);
    /* 原作第 12 次攻击后是「中场」：Sans 停手，直到玩家主动攻击——官方给的补给窗口。
       在这个窗口选仁慈 = 立即死亡（原作行为），所以它是一个真正的抉择。 */
    if (this.round === 3) {
      this.interlude = true;
      this.log('interlude');
      this.say('……中场。他停手了。');
      return;
    }
    if (this.final) this.say(LINES.final);
  };

  /** 结局。outcome: 'kill' | 'spare' | 'fail'；reason 用于区分失败原因 */
  Game.prototype.finish = function (outcome, reason) {
    this.result = outcome;
    this.failReason = reason || null;
    this.state = 'result';
    if (outcome === 'fail') this.log('fail ' + (reason || 'hp_zero'));
    else this.log('win outcome=' + outcome);
  };

  /* ------------------------------------------------------------- 台词打字 */
  Game.prototype.say = function (t) { this.line = t; this.lineShown = 0; this.lineT = 0; };

  /* ------------------------------------------------------------- 玩家输入 */
  Game.prototype.move = function (dx, dy) {
    if (this.state !== 'enemy') return;
    this.soul.x = clamp(this.soul.x + dx, this.box.x + SOUL_R, this.box.x + this.box.w - SOUL_R);
    this.soul.y = clamp(this.soul.y + dy, this.box.y + SOUL_R, this.box.y + this.box.h - SOUL_R);
  };
  Game.prototype.jump = function () {
    if (this.state !== 'enemy' || this.soul.mode !== 'blue') return;
    if (this.soul.grounded) { this.soul.vy = roundDef(6).p.jump; this.soul.grounded = false; }
  };
  Game.prototype.press = function (k, down) {
    this.keys = this.keys || {};
    this.keys[k] = down;
  };
  Game.prototype.menuMove = function (d) {
    if (this.state !== 'menu') return;
    this.menuIndex = (this.menuIndex + d + 4) % 4;
  };
  Game.prototype.menuChoose = function (i) {
    if (this.state !== 'menu') return;
    if (i != null) this.menuIndex = i;
    var idx = this.menuIndex;
    /* 中场：可以反复用道具 / 行动回血，只有「攻击」才会推进回合；
       在这里选「仁慈」= 立即死亡（原作：みのがすと即死）。 */
    if (this.interlude) {
      if (idx === 3) { this.log('fail spared_midpoint'); this.say('（他把手放下了。你没能再站起来。）'); this.finish('fail', 'spared_midpoint'); return; }
      if (idx === 1) { this.log('menu_act'); this.subOpen('act'); return; }
      if (idx === 2) {
        this.log('menu_item');
        if (this.itemCount() > 0) this.subOpen('item'); else { this.log('item_empty'); this.say('（背包是空的）'); }
        return;
      }
      this.interlude = false;
    }
    if (idx === 0) {
      this.log('menu_attack final=' + (this.final ? 1 : 0));
      this.state = 'attack'; this.attackCursor = 0; this.attackDir = 1; this.attackResult = null;
    } else if (idx === 1) { this.log('menu_act'); this.subOpen('act'); }
    else if (idx === 2) {
      this.log('menu_item');
      if (this.itemCount() > 0) this.subOpen('item');
      else { this.log('item_empty'); this.say('（背包是空的）'); }
    } else { this.log('menu_mercy'); this.subOpen('mercy'); }
  };

  /* ------------------------------------------------ 子菜单（行动/道具/仁慈） */
  Game.prototype.itemCount = function () {
    var n = 0;
    for (var i = 0; i < this.items.length; i++) n += this.items[i].count;
    return n;
  };
  Game.prototype.itemList = function () {
    var out = [];
    for (var i = 0; i < this.items.length; i++) if (this.items[i].count > 0) out.push(this.items[i]);
    return out;
  };
  Game.prototype.subOpen = function (kind) {
    this.sub = kind; this.subIndex = 0; this.state = 'sub';
    this.log('sub_open kind=' + kind);
  };
  Game.prototype.subRows = function () {
    if (this.sub === 'act') { var a = []; for (var i = 0; i < ACT_OPTIONS.length; i++) a.push(ACT_OPTIONS[i].name); return a; }
    if (this.sub === 'item') { var l = this.itemList(), b = []; for (var j = 0; j < l.length; j++) b.push(l[j].name); return b; }
    if (this.sub === 'mercy') return ['饶恕', '逃跑'];
    return [];
  };
  /** 行右侧的副文本（数量 / 提示） */
  Game.prototype.subRowNote = function (idx) {
    if (this.sub === 'item') { var l = this.itemList(); return l[idx] ? ('x' + l[idx].count) : ''; }
    if (this.sub === 'act') return ACT_OPTIONS[idx] ? (ACT_OPTIONS[idx].effect === 'wait' ? '不结束回合' : '结束回合') : '';
    if (this.sub === 'mercy') return idx === 0 ? '撑过 6 回合后才有效' : '他不让你走';
    return '';
  };
  /** 底部描述行 */
  Game.prototype.subDesc = function () {
    var i = this.subIndex;
    if (this.sub === 'act') return ACT_OPTIONS[i] ? ACT_OPTIONS[i].hint : '';
    if (this.sub === 'item') { var l = this.itemList(); return l[i] ? l[i].desc : ''; }
    if (this.sub === 'mercy') return i === 0 ? '放过他，结束这场审判' : '转身离开（大概不会成功）';
    return '';
  };
  Game.prototype.subMove = function (d) {
    if (this.state !== 'sub') return;
    var n = this.subRows().length;
    if (!n) return;
    this.subIndex = (this.subIndex + d + n) % n;
  };
  Game.prototype.subBack = function () {
    if (this.state !== 'sub') return;
    this.log('sub_back kind=' + this.sub);
    this.sub = null; this.state = 'menu';
  };
  Game.prototype.subConfirm = function () {
    if (this.state !== 'sub') return;
    var rows = this.subRows();
    if (!rows.length) { this.subBack(); return; }
    var i = clamp(this.subIndex, 0, rows.length - 1);
    if (this.sub === 'act') {
      var o = ACT_OPTIONS[i];
      this.log('act_result id=' + o.id);
      this.say(o.result);
      if (o.effect === 'wait') { this.subBack(); return; }           // 沉默：免费，不结束回合
      if (o.effect === 'taunt') { this.taunt += 1; this.log('act_taunt level=' + this.taunt); }
      if (o.effect === 'beg' && this.kr > 0) { this.kr = 0; this.krT = 0; this.log('kr_cleared by=beg'); }
      this.sub = null; this.afterPlayerTurn(); return;
    }
    if (this.sub === 'item') {
      var it = this.itemList()[i];
      it.count -= 1;
      this.hp = Math.min(MAX_HP, this.hp + it.heal);
      this.log('item_used id=' + it.id + ' hp=' + this.hp + ' left=' + this.itemCount());
      this.sub = null; this.afterPlayerTurn(); return;
    }
    if (this.sub === 'mercy') {
      if (i === 0) {
        if (this.final) { this.sub = null; this.say('（他放下了手）'); this.finish('spare'); }
        else { this.log('mercy_refused'); this.say(LINES.refuse); this.sub = null; this.afterPlayerTurn(); }
      } else { this.log('flee_refused'); this.say(LINES.flee); this.sub = null; this.afterPlayerTurn(); }
      return;
    }
  };
  Game.prototype.afterPlayerTurn = function () {
    if (this.state === 'result') return;
    if (this.interlude) { this.state = 'menu'; return; }      // 中场：他不动，你可以继续回血 / 行动
    if (this.round >= ROUNDS.length) { this.state = 'menu'; return; }
    this.startEnemy(this.round + 1);
  };

  /* --------------------------------------------------------------- 结算条 */
  Game.prototype.stopAttack = function () {
    if (this.state !== 'attack') return;
    var acc = 1 - Math.abs(this.attackCursor - 0.5) * 2;
    if (this.final) { this.attackResult = 'hit'; this.attackHold = 1.2; this.log('sans_hit final=1'); this.say('（他没能闪开）'); }
    else {
      this.attackResult = (acc > 0.92) ? 'perfect' : 'miss';
      this.attackHold = 1.0;
      this.log('sans_dodge acc=' + acc.toFixed(2));
      this.sansDodge = 1;
      this.say(LINES.dodge);
    }
  };

  /* ------------------------------------------------------------ 伤害与 KR */
  Game.prototype.hurt = function (kind) {
    if (this.state !== 'enemy' || this.invuln > 0) return false;
    var hpBefore = this.hp;
    this.hp -= 1;
    /* C2：KR 上限 = 命中前 HP-1，保证 KR 消耗完也不会把人烧死 */
    this.kr = Math.min(this.kr + KR_PER_HIT, Math.max(0, hpBefore - 1));
    this.krActive = this.kr > 0;
    this.krFloorLogged = false;
    this.invuln = this.tune.invuln;              // 原作没有无敌帧 → 原作档只有 0.15s
    this.flash = 0.12;
    if (kind === 'blue') this.log('hit_blue hp=' + this.hp + ' kr=' + this.kr);
    else if (kind === 'orange') this.log('hit_orange hp=' + this.hp + ' kr=' + this.kr);
    else this.log('hit hp=' + this.hp + ' kr=' + this.kr);
    if (this.hp <= 0) { this.hp = 0; this.finish('fail'); }
    return true;
  };
  /** 测试入口：直接走同一条伤害路径（不复制算法）。 */
  Game.prototype.debugHurt = function (kind) { this.invuln = 0; return this.hurt(kind || 'hit'); };

  /** C3：KR 每 0.5s 结算 1 点（KR-1 且 HP-1），HP 不低于 1；KR 不致死，也不能把 HP 变成小数。 */
  Game.prototype.updateKR = function (dt) {
    if (this.kr <= 0) { this.kr = 0; return; }
    this.krT = (this.krT || 0) + dt;
    while (this.krT >= KR_TICK && this.kr > 0) {
      this.krT -= KR_TICK;
      this.kr -= 1;
      if (this.hp > 1) { this.hp -= 1; }
      else if (!this.krFloorLogged) { this.krFloorLogged = true; this.log('kr_floor hp=' + this.hp); }
      if (this.kr <= 0) { this.kr = 0; this.krActive = false; this.log('kr_done hp=' + this.hp + ' kr=0'); }
    }
  };

  /* ------------------------------------------------------------- 弹幕生成 */
  Game.prototype.buildPlatforms = function () {
    var b = this.box, H = b.h;
    this.platforms = [
      { x: b.x + 0.06 * b.w, y: b.y + H - 48,  w: 0.30 * b.w, h: 12 },
      { x: b.x + 0.40 * b.w, y: b.y + H - 120, w: 0.30 * b.w, h: 12 },
      { x: b.x + 0.12 * b.w, y: b.y + H - 192, w: 0.60 * b.w, h: 12 }
    ];
  };

  Game.prototype.spawnFloor = function (peekSec) {
    var b = this.box, laneW = 60, lanes = Math.max(4, Math.floor(b.w / laneW));
    laneW = b.w / lanes;
    var peek = (peekSec == null) ? PEEK : peekSec;
    var safe = [];
    if ((this.round === 1 || this.round === 0) && this.wave === 0 && !this.testAimWave1) {
      safe = [Math.floor(lanes / 2)];                 // 第 1 回合第 1 波：出生点必留安全位（上手保证）
    } else if (this.testAimWave1 && this.wave === 0) {
      var cur = Math.floor((this.soul.x - b.x) / laneW);
      safe = [clamp(cur - 1, 0, lanes - 1), clamp(cur + 1, 0, lanes - 1)];
      if (safe[0] === safe[1]) safe = [clamp(cur + 1, 0, lanes - 1)];
    } else {
      var n = 1 + Math.floor(this.rng() * 2);
      for (var i = 0; i < n; i++) safe.push(Math.floor(this.rng() * lanes));
    }
    var wave = ++this.wave;
    var self = this;
    for (var L = 0; L < lanes; L++) {
      if (safe.indexOf(L) >= 0) continue;
      this.bones.push({
        kind: 'floor', wave: wave, x: b.x + laneW * (L + 0.5), w: laneW - 6,
        y: b.y + b.h, targetH: b.h, h: TIP_H, t: 0, phase: 'peek', peekDur: peek, lethal: false, color: 'white'
      });
    }
    /* 致命窗口不重叠：下一波要等这一波的"保持"结束（冒头可与此前的收回重叠） */
    this.floorLock = peek + EXTEND + HOLD;
    this.log('wave_peek wave=' + wave + ' lanes=' + (lanes - safe.length) + ' hp=' + this.hp);
  };

  /* 骨墙 = 原地升降的整高屏障，缺口固定在场地里（不是平移的墙）。
     平移墙会让玩家必须"追着缺口跑"，那正是「第二轮全饱和」的手感来源。 */
  Game.prototype.spawnWall = function (gapW) {
    var b = this.box, lanes = 9, laneW = b.w / lanes;
    if (this.walls.length > 0) return;                     // 反饱和：同一时刻只有一道屏障
    var gapStart;
    if (this.round === 2 && !this.firstBarrierDone && !this.testAimWave1) gapStart = 3;  // 第 1 道缺口居中（上手保证）
    else gapStart = Math.floor(this.rng() * (lanes - gapW + 1));
    if (this.round === 2) this.firstBarrierDone = true;
    this.walls.push({ t: 0, phase: 'warn', lanes: lanes, laneW: laneW, gapStart: gapStart, gapW: gapW, h: 0 });
  };

  /* 颜色骨（原作 Color：0 白 / 1 蓝 / 2 橙）——蓝：静止才安全；橙：必须移动才安全 */
  Game.prototype.spawnBlue = function (fromBottom, color) {
    var b = this.box;
    this.bones.push({
      kind: 'blue', x: b.x, w: b.w, h: 22,
      y: fromBottom ? b.y + b.h + 24 : b.y - 24,
      vy: (fromBottom ? -150 : 150) * this.tune.speed * this.spd,
      lethal: true, color: color || 'blue', passed: false
    });
  };
  Game.prototype.spawnWhiteSlide = function () {
    var b = this.box, fromLeft = this.rng() < 0.5;
    this.bones.push({
      kind: 'slide', x: fromLeft ? b.x - 30 : b.x + b.w + 30, w: 22, h: 90,
      y: b.y + 40 + this.rng() * (b.h - 130),
      vx: (fromLeft ? 210 : -210) * this.tune.speed * this.spd, lethal: true, color: 'white'
    });
  };
  Game.prototype.spawnBlaster = function (count) {
    var b = this.box;
    for (var i = 0; i < count; i++) {
      var vertical = this.rng() < 0.5;
      var pos = vertical ? (b.x + b.w * (0.2 + 0.6 * this.rng())) : (b.y + b.h * (0.2 + 0.6 * this.rng()));
      /* 回合 0（不意打ち）把光束放到离灵魂最远的一侧：开局偷袭必须"站着不动也活得了" */
      if (this.round === 0) {
        var avoid = vertical ? this.soul.x : this.soul.y;
        var lo = (vertical ? b.x : b.y) + 30, hi = (vertical ? b.x + b.w : b.y + b.h) - 30;
        pos = (avoid - lo > hi - avoid) ? lo : hi;
      }
      this.blasters.push({
        axis: vertical ? 'v' : 'h',
        pos: pos, side: this.rng() < 0.5 ? -1 : 1,   // 头骨挂在哪一侧的边缘
        t: 0, state: 'charge', band: 92, x: b.x, y: b.y, w: b.w, h: b.h
      });
    }
  };

  /* ----------------------------------------------------------------- 更新 */
  Game.prototype.update = function (dt) {
    if (this.state === 'title' || this.state === 'result') return;
    this.flash = Math.max(0, this.flash - dt);
    if (this.lineShown < this.line.length) { this.lineT += dt; this.lineShown = Math.min(this.line.length, Math.floor(this.lineT / 0.028)); }
    this.sansDodge = Math.max(0, this.sansDodge - dt * 2.2);

    if (this.state === 'attack') {
      this.attackCursor += this.attackDir * dt * 1.2;
      if (this.attackCursor > 1) { this.attackCursor = 1; this.attackDir = -1; }
      if (this.attackCursor < 0) { this.attackCursor = 0; this.attackDir = 1; }
      if (this.attackResult) {
        this.attackHold -= dt;
        if (this.attackHold <= 0) {
          if (this.final) this.finish('kill');
          else { this.attackResult = null; if (this.round < ROUNDS.length) this.startEnemy(this.round + 1); else this.state = 'menu'; }
        }
      }
      return;
    }
    if (this.state === 'menu' || this.state === 'sub') { this.updateKR(dt); return; }
    if (this.state !== 'enemy') return;

    this.updateKR(dt);
    if (this.state !== 'enemy') return;   // KR 不可能致死，但留出安全边界

    /* 灵魂移动（键盘） */
    var k = this.keys || {}, vx = 0, vy = 0;
    if (k.left) vx -= 1; if (k.right) vx += 1;
    if (k.up) vy -= 1; if (k.down) vy += 1;
    if (vx || vy) {
      var len = Math.hypot(vx, vy) || 1;
      this.soul.x += vx / len * SOUL_SPEED * dt;
      this.soul.y += vy / len * SOUL_SPEED * dt;
    }
    var d = roundDef(this.round);
    if (this.soul.mode === 'blue') {
      this.soul.vy += d.p.gravity * dt;
      this.soul.y += this.soul.vy * dt;
      this.soul.grounded = false;
      var floorY = this.box.y + this.box.h - SOUL_R;
      if (this.soul.y >= floorY) { this.soul.y = floorY; this.soul.vy = 0; this.soul.grounded = true; }
      for (var pi = 0; pi < this.platforms.length; pi++) {
        var pf = this.platforms[pi];
        if (this.soul.vy > 0 && this.prevY + SOUL_R <= pf.y + 2 &&
            this.soul.y + SOUL_R >= pf.y &&
            this.soul.x >= pf.x - 4 && this.soul.x <= pf.x + pf.w + 4) {
          this.soul.y = pf.y - SOUL_R; this.soul.vy = 0; this.soul.grounded = true;
        }
      }
    } else { this.soul.y = clamp(this.soul.y, this.box.y + SOUL_R, this.box.y + this.box.h - SOUL_R); }
    this.soul.x = clamp(this.soul.x, this.box.x + SOUL_R, this.box.x + this.box.w - SOUL_R);
    var moved = Math.hypot(this.soul.x - this.prevX, this.soul.y - this.prevY) > 0.7;

    /* 回合计时与生成 */
    this.enemyT += dt;
    this.spawnT -= dt;
    if (this.testHitsAt.length) {
      this.hitT = (this.hitT || 0) + dt;
      while (this.testHitsAt.length && this.hitT >= this.testHitsAt[0]) {
        this.testHitsAt.shift();
        this.hurt('hit');                       // 不重置无敌帧：让测试走真实的 i-frame 判定
        if (this.state !== 'enemy') return;
      }
    }
    if (this.floorLock > 0) this.floorLock -= dt;
    if (this.spawnT <= 0 && !this.testNoSpawn) {
      if (d.pattern === 'bone_floor' || d.pattern === 'mixed' || d.pattern === 'surprise') {
        if (this.floorLock <= 0) { this.spawnFloor(d.p.peek); this.spawnT = this.it(d.p.interval); }
        else this.spawnT = 0;                                // 等这一波的致命窗口结束
      }
      else if (d.pattern === 'bone_wall') { this.spawnWall(d.p.gap); this.spawnT = this.it(d.p.interval); }
      else if (d.pattern === 'blue_bone') {
        this.colorFlip = !this.colorFlip;                    // 蓝/橙交替：一静一动，逼玩家读颜色
        this.spawnBlue(this.rng() < 0.5, this.colorFlip ? 'blue' : 'orange');
        this.spawnT = this.it(d.p.blue);
      }
      else if (d.pattern === 'blaster') { this.spawnBlaster(this.enemyT > this.it(4) ? 2 : 1); this.spawnT = this.it(d.p.interval); }
      else if (d.pattern === 'blue_soul') { this.spawnFloorBoneBlue(); this.spawnT = this.it(d.p.boneInterval); }
    }
    if (d.pattern === 'blue_bone') {
      this.whiteT = (this.whiteT || 0) - dt;
      if (this.whiteT <= 0) { this.spawnWhiteSlide(); this.whiteT = this.it(d.p.white); }
    }
    if (d.pattern === 'mixed') {
      this.wallT -= dt;
      if (this.wallT <= 0) { this.spawnWall(4); this.wallT = this.it(d.p.wallInterval); }
    }

    /* 骨头更新 */
    var aliveWaves = {}, i, bn;
    for (i = this.bones.length - 1; i >= 0; i--) {
      bn = this.bones[i];
      bn.t += dt;
      if (bn.kind === 'floor') {
        if (bn.phase === 'peek') {
          bn.h = TIP_H; bn.lethal = false;                    // 预示：只冒头，不致命
          if (bn.t >= (bn.peekDur || PEEK)) { bn.phase = 'extend'; bn.t = 0; }
        } else if (bn.phase === 'extend') {
          bn.h = TIP_H + (bn.targetH - TIP_H) * Math.min(1, bn.t / EXTEND);
          bn.lethal = bn.h > 24;
          if (bn.t >= EXTEND) { bn.phase = 'hold'; bn.t = 0; bn.h = bn.targetH; }
        } else if (bn.phase === 'hold') {
          bn.h = bn.targetH; bn.lethal = true;
          if (bn.t >= HOLD) { bn.phase = 'retract'; bn.t = 0; }
        } else {
          bn.h = bn.targetH * Math.max(0, 1 - bn.t / RETRACT);
          bn.lethal = bn.h > 24;                              // 与视觉一致：还看得见骨头就还咬人
          if (bn.t >= RETRACT) { this.bones.splice(i, 1); continue; }
        }
      } else if (bn.kind === 'blue') {
        bn.y += bn.vy * dt;
        if (bn.y + bn.h < this.box.y - 60 || bn.y > this.box.y + this.box.h + 60) {
          if (!bn.passed && !bn.hitDone) { this.log('blue_pass_clean hp=' + this.hp); }
          this.bones.splice(i, 1); continue;
        }
      } else if (bn.kind === 'slide') {
        bn.x += bn.vx * dt;
        if (bn.x + bn.w < this.box.x - 60 || bn.x > this.box.x + this.box.w + 60) { this.bones.splice(i, 1); continue; }
      } else { continue; }
      if (bn.wave != null) aliveWaves[bn.wave] = true;
    }
    /* 波次清理日志 */
    for (var w in this.wavesAlive) if (!aliveWaves[w]) { this.log('wave_clear wave=' + w + ' hp=' + this.hp); delete this.wavesAlive[w]; }
    for (var w2 in aliveWaves) this.wavesAlive[w2] = true;

    /* 骨墙（原地升降） */
    for (i = this.walls.length - 1; i >= 0; i--) {
      var wl = this.walls[i];
      wl.t += dt;
      if (wl.phase === 'warn') { if (wl.t >= this.warnWall) { wl.phase = 'rise'; wl.t = 0; } }
      else if (wl.phase === 'rise') {
        wl.h = this.box.h * Math.min(1, wl.t / 0.25);
        if (wl.t >= 0.25) { wl.phase = 'hold'; wl.t = 0; wl.h = this.box.h; }
      } else if (wl.phase === 'hold') { if (wl.t >= 0.55) { wl.phase = 'retract'; wl.t = 0; } }
      else { wl.h = this.box.h * Math.max(0, 1 - wl.t / 0.25); if (wl.t >= 0.25) this.walls.splice(i, 1); }
    }

    /* 冲击波 */
    for (i = this.blasters.length - 1; i >= 0; i--) {
      var bl = this.blasters[i];
      bl.t += dt;
      if (bl.state === 'charge' && bl.t >= this.warn) { bl.state = 'fire'; bl.t = 0; }
      else if (bl.state === 'fire' && bl.t >= 0.35) { bl.state = 'fade'; bl.t = 0; }
      else if (bl.state === 'fade' && bl.t >= 0.3) { this.blasters.splice(i, 1); }
    }

    /* 碰撞 */
    for (i = 0; i < this.bones.length; i++) {
      bn = this.bones[i];
      if (!bn.lethal) continue;
      if (bn.kind === 'blue') {
        var orange = (bn.color === 'orange');
        /* C6/C19：蓝骨只惩罚「移动」，橙骨只惩罚「静止」 */
        if (orange ? moved : !moved) continue;
        if (rectHit(this.soul.x, this.soul.y, SOUL_R, { x: bn.x, y: bn.y, w: bn.w, h: bn.h })) {
          if (this.hurt(orange ? 'orange' : 'blue')) bn.hitDone = true;
        }
      } else {
        var rc = (bn.kind === 'floor') ? { x: bn.x - bn.w / 2, y: bn.y - bn.h, w: bn.w, h: bn.h } : { x: bn.x, y: bn.y, w: bn.w, h: bn.h };
        if (rectHit(this.soul.x, this.soul.y, SOUL_R, rc)) this.hurt('hit');
      }
    }
    for (i = 0; i < this.walls.length; i++) {
      var W = this.walls[i];
      if (W.phase === 'warn' || W.phase === 'retract' && W.h < 24) continue;
      for (var L = 0; L < W.lanes; L++) {
        if (L >= W.gapStart && L < W.gapStart + W.gapW) continue;
        if (rectHit(this.soul.x, this.soul.y, SOUL_R,
            { x: this.box.x + L * W.laneW, y: this.box.y + this.box.h - W.h, w: W.laneW, h: W.h })) this.hurt('hit');
      }
    }
    for (i = 0; i < this.blasters.length; i++) {
      var B = this.blasters[i];
      if (B.state !== 'fire') continue;
      var band = (B.axis === 'v') ? { x: B.pos - B.band / 2, y: this.box.y, w: B.band, h: this.box.h }
                                  : { x: this.box.x, y: B.pos - B.band / 2, w: this.box.w, h: B.band };
      if (rectHit(this.soul.x, this.soul.y, SOUL_R, band)) this.hurt('hit');
    }

    this.prevX = this.soul.x; this.prevY = this.soul.y;
    this.invuln = Math.max(0, this.invuln - dt);

    if (this.enemyT >= this.enemyDur) this.endEnemy();
  };

  /** 重力回合：底部横向滑动的骨头 */
  Game.prototype.spawnFloorBoneBlue = function () {
    var b = this.box, fromLeft = this.rng() < 0.5;
    this.bones.push({
      kind: 'slide', x: fromLeft ? b.x - 30 : b.x + b.w + 30, w: 26, h: 58,
      y: b.y + b.h - 58, vx: (fromLeft ? 230 : -230) * this.tune.speed * this.spd, lethal: true, color: 'white'
    });
  };

  /* ------------------------------------------------------ 供断言用的快照 */
  Game.prototype.snapshot = function () {
    return {
      state: this.state, hp: this.hp, kr: Math.round(this.kr * 100) / 100,
      round: this.round, final: this.final, result: this.result, diff: this.diffKey,
      sub: this.sub, subIndex: this.subIndex, items: this.itemCount(),
      soul: { x: Math.round(this.soul.x), y: Math.round(this.soul.y), mode: this.soul.mode },
      bones: this.bones.length, logs: this.logs.slice()
    };
  };

  /* ================================================ UI 几何（渲染与点击共用一套） */
  var DIFF_CARD = { w: 170, h: 76, gap: 24, y: 420 };
  var MENU_RECT = { bw: 220, bh: 72, gap: 20, y: 600 };
  var SUB_RECT = { w: 620, h: 340, y: 250 };
  Game.prototype.diffCardRect = function (i) {
    var total = DIFF_CARD.w * DIFF_ORDER.length + DIFF_CARD.gap * (DIFF_ORDER.length - 1);
    return { x: (DESIGN_W - total) / 2 + i * (DIFF_CARD.w + DIFF_CARD.gap), y: DIFF_CARD.y, w: DIFF_CARD.w, h: DIFF_CARD.h };
  };
  Game.prototype.menuRect = function (i) {
    var total = MENU_RECT.bw * 4 + MENU_RECT.gap * 3;
    return { x: (DESIGN_W - total) / 2 + i * (MENU_RECT.bw + MENU_RECT.gap), y: MENU_RECT.y, w: MENU_RECT.bw, h: MENU_RECT.bh };
  };
  Game.prototype.restartRect = function () { return { x: DESIGN_W / 2 - 130, y: 440, w: 260, h: 72 }; };
  Game.prototype.subPanelRect = function () { return { x: (DESIGN_W - SUB_RECT.w) / 2, y: SUB_RECT.y, w: SUB_RECT.w, h: SUB_RECT.h }; };
  Game.prototype.subRowRect = function (i) { var p = this.subPanelRect(); return { x: p.x + 20, y: p.y + 70 + i * 56, w: p.w - 40, h: 50 }; };

  /* ============================================================== 渲染 */
  function render(ctx, g) {
    ctx.save();
    ctx.fillStyle = '#000';
    ctx.fillRect(0, 0, DESIGN_W, DESIGN_H);

    /* 全屏受伤红闪 */
    if (g.flash > 0) { ctx.fillStyle = 'rgba(255,0,0,' + (0.35 * g.flash / 0.12) + ')'; ctx.fillRect(0, 0, DESIGN_W, DESIGN_H); }

    if (g.state === 'title') {
      ctx.fillStyle = '#fff'; ctx.textAlign = 'center';
      ctx.font = 'bold 56px sans-serif'; ctx.fillText('弹 幕 审 判', DESIGN_W / 2, 250);
      ctx.font = '22px sans-serif'; ctx.fillStyle = '#bbb';
      ctx.fillText('移动灵魂躲开弹幕　·　撑过 6 个回合　·　键盘 WASD/方向键，触屏在框内拖动', DESIGN_W / 2, 300);
      ctx.font = 'bold 26px sans-serif'; ctx.fillStyle = '#ffcc33';
      ctx.fillText('选择难度', DESIGN_W / 2, 390);
      for (var di = 0; di < DIFF_ORDER.length; di++) {
        var dc = g.diffCardRect(di), D = DIFFS[DIFF_ORDER[di]], selD = (di === g.titleIndex);
        ctx.fillStyle = selD ? '#2a2a12' : '#111';
        ctx.fillRect(dc.x, dc.y, dc.w, dc.h);
        ctx.strokeStyle = selD ? '#ffcc33' : '#555'; ctx.lineWidth = 3;
        ctx.strokeRect(dc.x, dc.y, dc.w, dc.h);
        ctx.fillStyle = selD ? '#fff' : '#999'; ctx.font = 'bold 28px sans-serif';
        ctx.fillText(D.label, dc.x + dc.w / 2, dc.y + 36);
        ctx.font = '13px sans-serif'; ctx.fillStyle = selD ? '#c9b26a' : '#666';
        ctx.fillText(D.note, dc.x + dc.w / 2, dc.y + 60);
      }
      ctx.font = 'bold 24px sans-serif'; ctx.fillStyle = '#ffcc33';
      ctx.fillText('点击难度开始（或按 1 / 2 / 3 / 4）', DESIGN_W / 2, 570);
      ctx.restore(); return;
    }

    /* Sans（自绘几何占位，不使用任何原作素材） */
    var sx = DESIGN_W / 2 + g.sansDodge * 70, sy = 76;
    ctx.save();
    ctx.fillStyle = '#f2f2f2';
    ctx.beginPath(); ctx.ellipse(sx, sy, 46, 38, 0, 0, Math.PI * 2); ctx.fill();
    ctx.fillRect(sx - 34, sy + 26, 68, 14);
    ctx.fillStyle = '#111';
    ctx.beginPath(); ctx.ellipse(sx - 16, sy - 6, 10, 12, 0, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.ellipse(sx + 16, sy - 6, 10, 12, 0, 0, Math.PI * 2); ctx.fill();
    if (g.state === 'enemy' || g.state === 'attack') {
      ctx.fillStyle = '#4ad9ff';
      ctx.beginPath(); ctx.ellipse(sx - 16, sy - 6, 4, 5, 0, 0, Math.PI * 2); ctx.fill();
      ctx.beginPath(); ctx.ellipse(sx + 16, sy - 6, 4, 5, 0, 0, Math.PI * 2); ctx.fill();
    }
    ctx.restore();

    /* 台词（打字机） */
    ctx.textAlign = 'center'; ctx.font = 'bold 24px sans-serif';
    ctx.fillStyle = '#fff';
    ctx.fillText(g.line.slice(0, g.lineShown), DESIGN_W / 2, 172);

    /* 战斗框 */
    ctx.save();
    ctx.strokeStyle = '#fff'; ctx.lineWidth = 4;
    ctx.strokeRect(g.box.x, g.box.y, g.box.w, g.box.h);
    ctx.restore();

    /* 平台 */
    for (var i = 0; i < g.platforms.length; i++) {
      var pf = g.platforms[i];
      ctx.fillStyle = '#8a8a8a'; ctx.fillRect(pf.x, pf.y, pf.w, pf.h);
    }

    /* 骨墙（原地升降 + 缺口预警） */
    for (i = 0; i < g.walls.length; i++) {
      var W = g.walls[i], gy = g.box.y + g.box.h;
      if (W.phase === 'warn') {
        ctx.fillStyle = 'rgba(120,255,120,0.16)';
        ctx.fillRect(g.box.x + W.gapStart * W.laneW, g.box.y, W.gapW * W.laneW, g.box.h);
        ctx.strokeStyle = 'rgba(150,255,150,0.7)'; ctx.lineWidth = 2;
        ctx.strokeRect(g.box.x + W.gapStart * W.laneW, g.box.y, W.gapW * W.laneW, g.box.h);
        ctx.textAlign = 'center'; ctx.font = 'bold 16px sans-serif'; ctx.fillStyle = '#9f9';
        ctx.fillText('缺口', g.box.x + (W.gapStart + W.gapW / 2) * W.laneW, gy - 10);
        continue;
      }
      for (var L = 0; L < W.lanes; L++) {
        if (L >= W.gapStart && L < W.gapStart + W.gapW) continue;
        ctx.fillStyle = '#f5f5f5';
        ctx.fillRect(g.box.x + L * W.laneW + 3, gy - W.h, W.laneW - 6, W.h);
      }
    }

    /* 骨头（实体化外观：骨干 + 两端各两颗骨球） */
    for (i = 0; i < g.bones.length; i++) {
      var bn = g.bones[i];
      if (bn.kind === 'floor') {
        if (bn.phase === 'peek') {
          /* 预示：先画出这一格的纵向占位与边框，玩家能提前知道骨头将从哪里伸出来 */
          ctx.fillStyle = 'rgba(255,255,255,0.09)';
          ctx.fillRect(bn.x - bn.w / 2, bn.y - bn.targetH, bn.w, bn.targetH);
          ctx.strokeStyle = 'rgba(255,214,102,0.55)'; ctx.lineWidth = 2;
          ctx.strokeRect(bn.x - bn.w / 2, bn.y - bn.targetH, bn.w, bn.targetH);
        }
        drawBone(ctx, bn.x, bn.y - bn.h / 2, bn.h, bn.w, false, '#f2f2f2', bn.phase === 'peek' ? 0.9 : 1);
      } else {
        var col = (bn.color === 'blue') ? '#5adcff' : ((bn.color === 'orange') ? '#ff9a3c' : '#f2f2f2');
        drawBone(ctx, bn.x + bn.w / 2, bn.y + bn.h / 2, bn.w, bn.h, bn.kind === 'blue', col, 1);
      }
    }
    /* 颜色骨图例（原作用颜色区分规则，不给文字玩家会误判） */
    if (g.bones.some(function (b) { return b.kind === 'blue'; })) {
      ctx.textAlign = 'center'; ctx.font = 'bold 18px sans-serif';
      ctx.fillStyle = '#9fdcff'; ctx.fillText('蓝 = 别动', g.box.x + g.box.w * 0.26, g.box.y - 12);
      ctx.fillStyle = '#ffc48a'; ctx.fillText('橙 = 快动', g.box.x + g.box.w * 0.74, g.box.y - 12);
    }

    /* 龙骨炮（全部由细实线构建的新实体） */
    for (i = 0; i < g.blasters.length; i++) drawBlaster(ctx, g.blasters[i]);

    /* 灵魂 */
    var invBlink = (g.invuln > 0) && (Math.floor(g.invuln * 20) % 2 === 0);
    if (!invBlink) {
      ctx.fillStyle = (g.soul.mode === 'blue') ? '#4ad9ff' : '#ff2d2d';
      heart(ctx, g.soul.x, g.soul.y, SOUL_R + 2);
    }

    /* HUD */
    ctx.textAlign = 'left';
    ctx.font = 'bold 20px sans-serif'; ctx.fillStyle = '#fff';
    ctx.fillText('LV 19', 40, 44);
    ctx.fillStyle = '#7a1010'; ctx.fillRect(110, 26, 200, 18);
    ctx.fillStyle = '#ffd400'; ctx.fillRect(110, 26, 200 * (g.hp / MAX_HP), 18);
    ctx.fillStyle = '#fff'; ctx.font = 'bold 16px sans-serif';
    ctx.fillText('HP ' + g.hp + '/' + MAX_HP, 320, 42);
    ctx.fillStyle = '#2a0a3a'; ctx.fillRect(110, 52, 200, 12);
    ctx.fillStyle = '#c04dff'; ctx.fillRect(110, 52, 200 * clamp(g.kr / 19, 0, 1), 12);
    ctx.fillStyle = '#e0b3ff'; ctx.fillText('KR ' + Math.round(g.kr), 320, 63);
    ctx.fillStyle = '#fff'; ctx.font = 'bold 16px sans-serif';
    ctx.fillText('ITEM x' + g.itemCount(), 40, 80);
    ctx.font = '13px sans-serif'; ctx.fillStyle = '#8a8a8a';
    ctx.fillText('难度 ' + (g.tune ? g.tune.label : '普通') + (g.taunt ? '　挑衅 x' + g.taunt : ''), 40, 100);

    ctx.textAlign = 'right'; ctx.font = 'bold 22px sans-serif'; ctx.fillStyle = '#fff';
    ctx.fillText('ROUND ' + g.round + ' / 6', DESIGN_W - 40, 46);
    ctx.font = '16px sans-serif'; ctx.fillStyle = '#bbb';
    ctx.fillText(g.state === 'enemy' ? 'SANS 的回合' : (g.state === 'menu' ? '你的回合' : (g.state === 'attack' ? '空格停下' : '')), DESIGN_W - 40, 74);

    /* 菜单（sub 状态下保留在底层，子面板覆盖其上） */
    if (g.state === 'menu' || g.state === 'attack' || g.state === 'sub') {
      var labels = ['攻击', '行动', '道具', '仁慈'];
      for (var mi = 0; mi < 4; mi++) {
        var mr = g.menuRect(mi);
        var active = (g.state === 'menu');
        var sel = (mi === g.menuIndex);
        ctx.fillStyle = !active ? '#1a1a1a' : (sel ? '#3a3a3a' : '#141414');
        ctx.fillRect(mr.x, mr.y, mr.w, mr.h);
        ctx.strokeStyle = (sel && active) ? '#ffcc33' : (g.state === 'sub' && mi === (g.sub === 'act' ? 1 : (g.sub === 'item' ? 2 : 3)) ? '#8a7a3a' : '#555');
        ctx.lineWidth = 3; ctx.strokeRect(mr.x, mr.y, mr.w, mr.h);
        ctx.fillStyle = active ? '#fff' : (g.state === 'sub' ? '#777' : '#666');
        ctx.textAlign = 'center'; ctx.font = 'bold 26px sans-serif';
        ctx.fillText(labels[mi], mr.x + mr.w / 2, mr.y + 46);
        ctx.font = '14px sans-serif'; ctx.fillStyle = '#888';
        ctx.fillText(String(mi + 1), mr.x + 20, mr.y + 20);
      }

      /* 中场提示（原作：Sans 停手，直到玩家主动攻击） */
      if (g.interlude && g.state === 'menu') {
        ctx.textAlign = 'center'; ctx.font = 'bold 22px sans-serif'; ctx.fillStyle = '#8fd68f';
        ctx.fillText('* 中场：他停手了 —— 要回血就现在（选仁慈会死）', DESIGN_W / 2, 578);
      }

      /* 攻击：时机条 */
      if (g.state === 'attack') {
        var ax = g.box.x, ay = g.box.y + g.box.h / 2, aw = g.box.w, ah = 44;
        ctx.textAlign = 'left'; ctx.font = 'bold 22px sans-serif'; ctx.fillStyle = '#ffcc33';
        ctx.fillText('* 攻击', ax, ay - ah / 2 - 18);
        ctx.textAlign = 'right'; ctx.font = '16px sans-serif'; ctx.fillStyle = '#bbb';
        ctx.fillText('伤害 1　·　空格停下', ax + aw, ay - ah / 2 - 18);
        ctx.fillStyle = '#111'; ctx.fillRect(ax, ay - ah / 2, aw, ah);
        ctx.fillStyle = 'rgba(255,204,51,0.18)';
        ctx.fillRect(ax + aw * 0.44, ay - ah / 2, aw * 0.12, ah);
        ctx.strokeStyle = '#666'; ctx.lineWidth = 2; ctx.strokeRect(ax, ay - ah / 2, aw, ah);
        ctx.strokeStyle = '#ffcc33'; ctx.lineWidth = 3;
        ctx.beginPath(); ctx.moveTo(ax + aw / 2, ay - ah / 2); ctx.lineTo(ax + aw / 2, ay + ah / 2); ctx.stroke();
        ctx.fillStyle = '#4ad9ff';
        var cxp = ax + aw * g.attackCursor;
        ctx.fillRect(cxp - 3, ay - ah / 2 - 6, 6, ah + 12);
        if (g.attackResult) {
          ctx.textAlign = 'center'; ctx.font = 'bold 30px sans-serif';
          ctx.fillStyle = g.attackResult === 'hit' ? '#ff5e41' : '#fff';
          ctx.fillText(g.attackResult === 'hit' ? 'HIT!' : (g.attackResult === 'perfect' ? 'PERFECT —— 但他还是闪开了' : '他闪开了'),
            DESIGN_W / 2, ay - 44);
        }
      }

      /* 子菜单面板：行动 / 道具 / 仁慈 */
      if (g.state === 'sub') {
        var pr = g.subPanelRect();
        ctx.fillStyle = 'rgba(6,6,6,0.95)'; ctx.fillRect(pr.x, pr.y, pr.w, pr.h);
        ctx.strokeStyle = '#ffcc33'; ctx.lineWidth = 3; ctx.strokeRect(pr.x, pr.y, pr.w, pr.h);
        ctx.textAlign = 'left'; ctx.font = 'bold 26px sans-serif'; ctx.fillStyle = '#ffcc33';
        ctx.fillText('* ' + (SUB_TITLE[g.sub] || ''), pr.x + 28, pr.y + 44);
        ctx.textAlign = 'right'; ctx.font = '15px sans-serif'; ctx.fillStyle = '#888';
        ctx.fillText('↑↓ 选择　回车确认　Esc 返回', pr.x + pr.w - 24, pr.y + 40);
        var rows = g.subRows();
        for (var si = 0; si < rows.length; si++) {
          var rr = g.subRowRect(si), selR = (si === g.subIndex);
          if (selR) {
            ctx.fillStyle = '#2a2a12'; ctx.fillRect(rr.x, rr.y, rr.w, rr.h);
            ctx.strokeStyle = '#ffcc33'; ctx.lineWidth = 2; ctx.strokeRect(rr.x, rr.y, rr.w, rr.h);
          }
          ctx.textAlign = 'left'; ctx.fillStyle = selR ? '#fff' : '#aaa'; ctx.font = 'bold 24px sans-serif';
          ctx.fillText(rows[si], rr.x + 24, rr.y + 34);
          ctx.textAlign = 'right'; ctx.font = '16px sans-serif'; ctx.fillStyle = selR ? '#c9b26a' : '#666';
          ctx.fillText(g.subRowNote(si), rr.x + rr.w - 20, rr.y + 33);
        }
        ctx.textAlign = 'left'; ctx.font = '17px sans-serif'; ctx.fillStyle = '#8fd68f';
        ctx.fillText(g.subDesc(), pr.x + 28, pr.y + pr.h - 20);
      }
    }

    /* 结算 */
    if (g.state === 'result') {
      ctx.fillStyle = 'rgba(0,0,0,0.86)'; ctx.fillRect(0, 0, DESIGN_W, DESIGN_H);
      ctx.textAlign = 'center';
      if (g.result === 'fail') {
        ctx.fillStyle = '#ff2d2d'; ctx.font = 'bold 72px sans-serif'; ctx.fillText('GAME OVER', DESIGN_W / 2, 300);
        ctx.fillStyle = '#bbb'; ctx.font = '24px sans-serif';
        ctx.fillText(g.failReason === 'spared_midpoint' ? '中场你选择了仁慈 —— 他没有停手。'
                                                         : '你没能撑过第 ' + g.round + ' 回合', DESIGN_W / 2, 356);
      } else if (g.result === 'spare') {
        ctx.fillStyle = '#ffcc33'; ctx.font = 'bold 64px sans-serif'; ctx.fillText('饶 恕 结 局', DESIGN_W / 2, 290);
        ctx.fillStyle = '#ddd'; ctx.font = '24px sans-serif'; ctx.fillText('你撑过了六回合，然后放下了刀。', DESIGN_W / 2, 350);
      } else {
        ctx.fillStyle = '#fff'; ctx.font = 'bold 64px sans-serif'; ctx.fillText('击 倒 结 局', DESIGN_W / 2, 290);
        ctx.fillStyle = '#ddd'; ctx.font = '24px sans-serif'; ctx.fillText('你撑过了六回合，然后完成了最后一击。', DESIGN_W / 2, 350);
      }
      var rb = g.restartRect();
      ctx.fillStyle = '#141414'; ctx.fillRect(rb.x, rb.y, rb.w, rb.h);
      ctx.strokeStyle = '#ffcc33'; ctx.lineWidth = 3; ctx.strokeRect(rb.x, rb.y, rb.w, rb.h);
      ctx.fillStyle = '#fff'; ctx.font = 'bold 28px sans-serif'; ctx.fillText('重 开', DESIGN_W / 2, rb.y + 46);
    }

    /* 日志（L 键） */
    if (g.showLog) {
      ctx.textAlign = 'left'; ctx.font = '15px monospace'; ctx.fillStyle = 'rgba(0,0,0,0.7)';
      ctx.fillRect(DESIGN_W - 420, DESIGN_H - 300, 400, 280);
      ctx.fillStyle = '#8f8'; var lines = g.logs.slice(-17);
      for (var li = 0; li < lines.length; li++) ctx.fillText(lines[li].slice(0, 46), DESIGN_W - 410, DESIGN_H - 278 + li * 16);
    }
    ctx.restore();
  }

  /* 骨头外观：骨干 + 两端各两颗骨球（带深色描边，做出实体的体积感） */
  function drawBone(ctx, cx, cy, along, across, horiz, color, alpha) {
    if (along <= 0 || across <= 0) return;
    var r = Math.max(3.5, across * 0.30);
    var sw = Math.max(5, across * 0.52);
    var off = across * 0.24;
    var half = along / 2;
    ctx.save();
    ctx.globalAlpha = (alpha == null) ? 1 : alpha;
    ctx.fillStyle = color;
    ctx.strokeStyle = 'rgba(0,0,0,0.6)';
    ctx.lineWidth = 2;
    function knob(x, y) { ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fill(); ctx.stroke(); }
    var shaft = Math.max(1, along - r * 1.8);
    if (!horiz) {
      ctx.beginPath(); ctx.rect(cx - sw / 2, cy - half + r * 0.9, sw, shaft); ctx.fill(); ctx.stroke();
      knob(cx - off, cy - half + r); knob(cx + off, cy - half + r);
      knob(cx - off, cy + half - r); knob(cx + off, cy + half - r);
    } else {
      ctx.beginPath(); ctx.rect(cx - half + r * 0.9, cy - sw / 2, shaft, sw); ctx.fill(); ctx.stroke();
      knob(cx - half + r, cy - off); knob(cx - half + r, cy + off);
      knob(cx + half - r, cy - off); knob(cx + half - r, cy + off);
    }
    ctx.restore();
  }

  /* 龙骨炮：头骨与光束全部由「细实线」构建的新实体（不使用实心填充） */
  function drawBlaster(ctx, B) {
    var vert = (B.axis === 'v');
    var half = B.band / 2;
    var a = (B.state === 'fire') ? 1 : (B.state === 'charge' ? 0.55 : 0.3);
    var hx = vert ? B.pos : (B.side < 0 ? B.x - 52 : B.x + B.w + 52);
    var hy = vert ? (B.side < 0 ? B.y - 52 : B.y + B.h + 52) : B.pos;
    ctx.save();
    ctx.lineJoin = 'round';
    /* 头骨：折线轮廓 + 眼窝 + 下颚线 */
    ctx.strokeStyle = 'rgba(242,242,242,' + (B.state === 'charge' ? 0.6 : 1) + ')';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(hx - 34, hy - 26); ctx.lineTo(hx + 34, hy - 26);
    ctx.lineTo(hx + 26, hy + 12); ctx.lineTo(hx, hy + 34);
    ctx.lineTo(hx - 26, hy + 12); ctx.closePath(); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(hx - 20, hy - 10); ctx.lineTo(hx - 5, hy + 2); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(hx + 20, hy - 10); ctx.lineTo(hx + 5, hy + 2); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(hx - 8, hy + 20); ctx.lineTo(hx + 8, hy + 20); ctx.stroke();
    /* 光束 */
    if (B.state === 'charge') {
      ctx.strokeStyle = 'rgba(255,255,255,0.5)'; ctx.lineWidth = 2;      // 蓄力：一条细实线预警
      ctx.beginPath();
      if (vert) { ctx.moveTo(B.pos, B.y); ctx.lineTo(B.pos, B.y + B.h); }
      else { ctx.moveTo(B.x, B.pos); ctx.lineTo(B.x + B.w, B.pos); }
      ctx.stroke();
    } else {
      var lines = 5;
      for (var k = 0; k < lines; k++) {
        var off = -half + B.band * (k / (lines - 1));
        var edge = (k === 0 || k === lines - 1);
        ctx.strokeStyle = 'rgba(255,255,255,' + (a * (edge ? 1 : 0.7)) + ')';
        ctx.lineWidth = edge ? 3 : 1.5;
        ctx.beginPath();
        if (vert) { ctx.moveTo(B.pos + off, B.y); ctx.lineTo(B.pos + off, B.y + B.h); }
        else { ctx.moveTo(B.x, B.pos + off); ctx.lineTo(B.x + B.w, B.pos + off); }
        ctx.stroke();
      }
      ctx.lineWidth = 1.5;
      ctx.strokeStyle = 'rgba(255,255,255,' + (a * 0.42) + ')';
      for (var s = 0; s <= 8; s++) {
        var p = s / 8;
        ctx.beginPath();
        if (vert) { var yy = B.y + B.h * p; ctx.moveTo(B.pos - half, yy); ctx.lineTo(B.pos + half, yy); }
        else { var xx = B.x + B.w * p; ctx.moveTo(xx, B.pos - half); ctx.lineTo(xx, B.pos + half); }
        ctx.stroke();
      }
    }
    ctx.restore();
  }

  function heart(ctx, x, y, r) {
    ctx.beginPath();
    ctx.moveTo(x, y + r);
    ctx.bezierCurveTo(x - r * 1.6, y - r * 0.4, x - r * 0.7, y - r * 1.5, x, y - r * 0.6);
    ctx.bezierCurveTo(x + r * 0.7, y - r * 1.5, x + r * 1.6, y - r * 0.4, x, y + r);
    ctx.closePath(); ctx.fill();
  }

  var api = { Game: Game, render: render, ROUNDS: ROUNDS, DIFFS: DIFFS, DIFF_ORDER: DIFF_ORDER, mulberry32: mulberry32, qxqyY: qxqyY, DT: DT, DESIGN_W: DESIGN_W, DESIGN_H: DESIGN_H };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  global.QXQY = api;
})(typeof window !== 'undefined' ? window : globalThis);
