/* ============================================================================
 * 原版复刻 · 攻击脚本引擎（Bad Time Simulator 兼容）
 * ---------------------------------------------------------------------------
 * 坐标系：**内部一律用原版的 640×480**，渲染时统一 ×1.5 居中到 1280×720。
 *   这样 CSV 里的所有数值可以逐字照用，不存在换算误差（这是保真的关键决定）。
 * 语义：每行 = `延时, 命令, 参数…`。**延时 = 执行该行前要等的时间**（相对上一行），
 *   所以一串 0 延时的行会在同一 tick 内连续执行；跳转回去会重新计延时 → 循环天然可用。
 * 支持：标签 `:Name`、`$变量`、JMP* 家族、SET/ADD/SUB/MUL/DIV/MOD/FLOOR/DEG/RAD/SIN/COS/ANGLE/RND。
 * 无 DOM 依赖，可在 node 里直接跑（见 selftest）。
 * ========================================================================== */
(function (global) {
  'use strict';

  var VW = 640, VH = 480;         // 原版虚拟画布
  var BONE_W = 19;                // 骨头贴图宽度（原版骨头为 19 宽，命中盒略窄）
  var BONE_HIT_W = 16;
  var HEART_HIT = 8;              // 灵魂命中盒（原版 readme 自称"命中盒不太准"，这里取 8）
  var BLASTER_BEAM_LEN = 2000;
  var BLASTER_W = [20, 36, 56];   // Size 0/1/2 的光束宽度（按原版视觉标定）
  var GRAVITY = 600;              // 蓝魂重力（px/s²）

  function mulberry32(a) {
    return function () {
      a |= 0; a = a + 0x6D2B79F5 | 0;
      var t = Math.imul(a ^ a >>> 15, 1 | a);
      t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
      return ((t ^ t >>> 14) >>> 0) / 4294967296;
    };
  }

  /* ------------------------------------------------------- 攻击脚本编译 */
  function compile(rows) {
    var prog = [], labels = {};
    for (var i = 0; i < rows.length; i++) {
      var r = rows[i];
      var delay = (typeof r[0] === 'string' && r[0].charAt(0) === '$') ? r[0] : Number(r[0]) || 0;
      var name = r[1];
      var args = r.slice(2).filter(function (a) { return a !== undefined && a !== ''; });
      if (typeof name === 'string' && name.charAt(0) === ':') {
        labels[name.slice(1)] = prog.length;
        /* 标签**占一行**（空操作）：原版的 JMPABS/JMPZ 用 1-based 物理行号，
           若把标签行丢掉，标签之后的数字行号就会整体错位。 */
        prog.push({ delay: delay, cmd: null, args: [], label: name.slice(1) });
        continue;
      }
      prog.push({ delay: delay, cmd: name, args: args });
    }
    /* 目标解析：JMPREL 是**相对偏移**；其余 JMP* 的第 1 个参数是目标（1-based 行号或标签名） */
    for (var j = 0; j < prog.length; j++) {
      var c = prog[j];
      if (/^JMP/.test(c.cmd) && c.args.length) {
        var t = c.args[0];
        if (c.cmd === 'JMPREL') { c.rel = t; }
        else if (typeof t === 'string' && labels[t] !== undefined) c.target = labels[t];
        else if (typeof t === 'string' && t.charAt(0) === '$') c.target = t;
        else c.target = Number(t) - 1;
      }
    }
    return { prog: prog, labels: labels };
  }

  /* ============================================================ 世界状态 */
  function World(opts) {
    opts = opts || {};
    this.seed = (opts.seed == null) ? 20261004 : opts.seed;
    this.reset(opts.script);
  }

  World.prototype.reset = function (script) {
    this.rng = mulberry32(this.seed);
    this.vars = {};
    this.zone = { l: 240, t: 226, r: 400, b: 391, tl: 240, tt: 226, tr: 400, tb: 391, speed: 0, resizing: false, finish: null };
    this.heart = { x: 320, y: 304, mode: 0, vx: 0, vy: 0, maxFall: 0, dir: 0 };
    this.bones = [];
    this.blasters = [];
    this.platforms = [];
    this.sine = [];
    this.flash = 0;                 // 黑屏闪白
    this.black = 0;
    this.sans = { head: 'Default', body: null, torso: 'Default', anim: 'Idle', sweat: 0, x: 320, repeat: false, text: '' };
    this.log = [];
    this.time = 0;
    this.ended = false;
    this.paused = false;
    this.pending = [];              // 同一 tick 内待执行的 0 延时行
    this.script = script ? compile(script) : null;
    this.prog = this.script ? this.script.prog : [];
    this.pc = 0;
    this.wait = 0;
    this.hitCount = 0;
    /* 延时语义 = 「执行该行前要等的时间」：首行的延时也要等（如 randomblaster1 的 0.5s 起手） */
    if (this.prog.length) {
      var d0 = this.prog[0].delay;
      this.wait = (typeof d0 === 'string') ? (this.vars[d0.slice(1)] || 0) : d0;
    }
  };

  World.prototype.say = function (s) { this.log.push(s); };

  /* ------------------------------------------------------------ 取值/运算 */
  World.prototype.val = function (v) {
    if (typeof v === 'string' && v.charAt(0) === '$') {
      var n = this.vars[v.slice(1)];
      return (n === undefined) ? 0 : n;
    }
    var f = Number(v);
    return isNaN(f) ? v : f;
  };

  /* ============================================================ 指令实现 */
  var CMD = {};
  CMD.CombatZoneResize = function (w, l, t, r, b, finish) {
    w.zone.tl = +l; w.zone.tt = +t; w.zone.tr = +r; w.zone.tb = +b;
    w.zone.resizing = true; w.zone.finish = finish || null;
    if (!w.zone.speed) w.zone.speed = 300;
  };
  CMD.CombatZoneResizeInstant = function (w, l, t, r, b) {
    w.zone.l = +l; w.zone.t = +t; w.zone.r = +r; w.zone.b = +b;
    w.zone.tl = +l; w.zone.tt = +t; w.zone.tr = +r; w.zone.tb = +b;
    w.zone.resizing = false;
  };
  CMD.CombatZoneSpeed = function (w, s) { w.zone.speed = +s; };
  CMD.HeartTeleport = function (w, x, y) { w.heart.x = +x; w.heart.y = +y; w.heart.vx = 0; w.heart.vy = 0; };
  CMD.HeartMode = function (w, m) { w.heart.mode = +m; };
  CMD.HeartMaxFallSpeed = function (w, v) { w.heart.maxFall = +v; };
  CMD.SansSlam = function (w, d) {
    /* 把灵魂朝某方向砸：0 东 / 1 南 / 2 西 / 3 北 */
    var s = w.heart.maxFall || 240;
    w.heart.dir = +d;
    w.heart.vx = (d === 0) ? s : (d === 2 ? -s : 0);
    w.heart.vy = (d === 1) ? s : (d === 3 ? -s : 0);
    w.say('slam ' + d);
  };
  CMD.SansSlamDamage = function (w, b) { w.slamDamage = !!+b; };
  CMD.GetHeartPos = function (w, xv, yv) { w.vars[xv] = w.heart.x; w.vars[yv] = w.heart.y; };

  function pushBone(w, x, y, hOrW, axis, dir, speed, color) {
    w.bones.push({
      x: +x, y: +y,
      w: (axis === 'v') ? BONE_W : +hOrW,
      h: (axis === 'v') ? +hOrW : BONE_W,
      vx: (dir === 0) ? +speed : (dir === 2 ? -+speed : 0),
      vy: (dir === 1) ? +speed : (dir === 3 ? -+speed : 0),
      color: (color === undefined ? 0 : +color)
    });
  }
  CMD.BoneV = function (w, x, y, h, dir, speed, color) { pushBone(w, x, y, h, 'v', +dir, +speed, color); };
  CMD.BoneH = function (w, x, y, wd, dir, speed, color) { pushBone(w, x, y, wd, 'h', +dir, +speed, color); };

  function repeatBones(w, axis, x, y, size, dir, speed, count, spacing, color) {
    var d = +dir, sp = +spacing, n = +count, s = +size;
    for (var i = 0; i < n; i++) {
      /* 反向飞行的骨群要从起点往"来向"排开，这样它们才会依次到达 */
      var off = (axis === 'v') ? (d === 2 ? -i * sp : i * sp) : (d === 3 ? -i * sp : i * sp);
      if (axis === 'v') pushBone(w, +x + off, y, s, 'v', d, speed, color);
      else pushBone(w, +x, +y + off, s, 'h', d, speed, color);
    }
  }
  CMD.BoneVRepeat = function (w, x, y, h, dir, speed, count, spacing) { repeatBones(w, 'v', x, y, h, dir, speed, count, spacing); };
  CMD.BoneHRepeat = function (w, x, y, wd, dir, speed, count, spacing) { repeatBones(w, 'h', x, y, wd, dir, speed, count, spacing); };

  CMD.SineBones = function (w, count, spacing, speed, height) {
    var n = +count, sp = +spacing, spd = +speed, hgt = +height;
    for (var i = 0; i < n; i++) {
      var idx = (sp < 0) ? (n - 1 - i) : i;
      var x = (+spacing < 0) ? (w.zone.r + 40 + idx * Math.abs(sp)) : (w.zone.l - 40 - idx * Math.abs(sp));
      w.sine.push({ x: x, phase: idx * 0.55, speed: spd, gap: hgt, dir: (sp < 0 ? -1 : 1) });
    }
  };

  CMD.BoneStab = function (w, dir, dist, warn, stay) {
    /* 从战斗框侧面弹出的骨刺墙：先预警 warn 秒，再伸出 dist，停留 stay 秒后收回 */
    w.bones.push({ stab: true, dir: +dir, dist: +dist, warn: +warn, stay: +stay, t: 0, phase: 'warn' });
  };

  CMD.GasterBlaster = function (w, size, sx, sy, ex, ey, endAng, spin, blast) {
    var a0 = Math.atan2(+ey - +sy, +ex - +sx) * 180 / Math.PI;
    w.blasters.push({
      size: +size, x: +sx, y: +sy, sx: +sx, sy: +sy, ex: +ex, ey: +ey,
      ang: a0, ang0: a0, endAng: +endAng, spin: +spin, blast: +blast, t: 0,
      state: (+spin > 0) ? 'spin' : 'charge'
    });
  };

  CMD.Platform = function (w, x, y, wd, dir, speed, reverse) {
    w.platforms.push({ x: +x, y: +y, w: +wd, h: 4, dir: +dir, speed: +speed, reverse: !!+reverse });
  };
  CMD.PlatformRepeat = function (w, x, y, wd, dir, speed, count, spacing) {
    for (var i = 0; i < +count; i++) {
      var off = (+dir === 2 || +dir === 3) ? -i * +spacing : i * +spacing;
      CMD.Platform(w, +x + off, y, wd, dir, speed, 0);
    }
  };

  CMD.BlackScreen = function (w, b) { w.black = +b; if (+b) { w.bones = []; w.sine = []; w.blasters = []; } };
  CMD.Sound = function (w, n) { w.say('sound ' + n); };
  CMD.Music = function (w, n) { w.say('music ' + n); };
  CMD.TLPause = function (w) { w.paused = true; };
  CMD.TLResume = function (w) { w.paused = false; };
  CMD.EndAttack = function (w) { w.ended = true; };

  CMD.SansAnimation = function (w, n) { w.sans.anim = n || 'Idle'; };
  CMD.SansHead = function (w, n) { w.sans.head = n || 'Default'; };
  CMD.SansBody = function (w, n) { w.sans.body = n || null; };
  CMD.SansTorso = function (w, n) { w.sans.torso = n || 'Default'; };
  CMD.SansSweat = function (w, n) { w.sans.sweat = +n; };
  CMD.SansX = function (w, x) { w.sans.x = +x; };
  CMD.SansRepeat = function (w) { w.sans.repeat = true; };
  CMD.SansEndRepeat = function (w) { w.sans.repeat = false; };
  CMD.SansText = function (w, t) { w.sans.text = String(t); w.say('text ' + t); };

  /* 数学 */
  CMD.SET = function (w, v, a) { w.vars[v] = w.val(a); };
  CMD.ADD = function (w, v, a, b) { w.vars[v] = w.val(a) + w.val(b); };
  CMD.SUB = function (w, v, a, b) { w.vars[v] = w.val(a) - w.val(b); };
  CMD.MUL = function (w, v, a, b) { w.vars[v] = w.val(a) * w.val(b); };
  CMD.DIV = function (w, v, a, b) { w.vars[v] = w.val(a) / w.val(b); };
  CMD.MOD = function (w, v, a, b) { w.vars[v] = w.val(a) % w.val(b); };
  CMD.FLOOR = function (w, v, a) { w.vars[v] = Math.floor(w.val(a)); };
  CMD.DEG = function (w, v, a) { w.vars[v] = w.val(a) * 180 / Math.PI; };
  CMD.RAD = function (w, v, a) { w.vars[v] = w.val(a) * Math.PI / 180; };
  CMD.SIN = function (w, v, a) { w.vars[v] = Math.sin(w.val(a) * Math.PI / 180); };
  CMD.COS = function (w, v, a) { w.vars[v] = Math.cos(w.val(a) * Math.PI / 180); };
  CMD.ANGLE = function (w, v, x1, y1, x2, y2) {
    w.vars[v] = Math.atan2(w.val(y2) - w.val(y1), w.val(x2) - w.val(x1)) * 180 / Math.PI;
  };
  CMD.RND = function (w, v, n) { w.vars[v] = Math.floor(w.rng() * w.val(n)); };

  /* 跳转 */
  var JUMPS = {
    JMPABS: function () { return true; },
    JMPREL: function () { return true; },
    JMPZ: function (w, t, a) { return w.val(a) === 0; },
    JMPNZ: function (w, t, a) { return w.val(a) !== 0; },
    JMPE: function (w, t, a, b) { return w.val(a) === w.val(b); },
    JMPNE: function (w, t, a, b) { return w.val(a) !== w.val(b); },
    JMPL: function (w, t, a, b) { return w.val(a) < w.val(b); },
    JMPNL: function (w, t, a, b) { return w.val(a) >= w.val(b); },
    JMPG: function (w, t, a, b) { return w.val(a) > w.val(b); },
    JMPNG: function (w, t, a, b) { return w.val(a) <= w.val(b); }
  };

  /* ============================================================ 主更新 */
  World.prototype.update = function (dt) {
    if (this.ended) return;
    this.time += dt;
    if (this.flash > 0) this.flash = Math.max(0, this.flash - dt);

    /* 1) 脚本推进（TLPause 时仍会推进战斗框变形，但暂停脚本本身——与原版 TLPause/TLResume 用法一致） */
    if (!this.paused) this.stepScript(dt);
    else if (this.zone.resizing) this.stepZone(dt);

    /* 2) 战斗框变形 */
    if (this.zone.resizing) this.stepZone(dt);

    /* 3) 实体运动 */
    var i, b;
    for (i = this.bones.length - 1; i >= 0; i--) {
      b = this.bones[i];
      if (b.stab) { this.stepStab(b, dt); if (b.dead) this.bones.splice(i, 1); continue; }
      b.x += b.vx * dt; b.y += b.vy * dt;
      if (b.x > VW + 400 || b.x < -400 || b.y > VH + 400 || b.y < -400) this.bones.splice(i, 1);
    }
    for (i = this.sine.length - 1; i >= 0; i--) {
      var s = this.sine[i];
      s.x += s.dir * s.speed * dt;
      if (s.x > VW + 400 || s.x < -400) this.sine.splice(i, 1);
    }
    for (i = this.blasters.length - 1; i >= 0; i--) {
      var g = this.blasters[i]; g.t += dt;
      if (g.state === 'spin') {
        var k = Math.min(1, g.t / g.spin);
        g.x = g.sx + (g.ex - g.sx) * k; g.y = g.sy + (g.ey - g.sy) * k;
        g.ang = g.ang0 + (g.endAng - g.ang0) * k;
        if (k >= 1) { g.state = 'spinning'; g.t = 0; }
      } else if (g.state === 'spinning') {
        g.ang = g.endAng;
        if (g.t >= 0.05) { g.state = 'fire'; g.t = 0; }
      } else if (g.state === 'fire' && g.t >= g.blast) { g.state = 'done'; }
      if (g.state === 'done' && g.t > g.blast + 0.15) this.blasters.splice(i, 1);
    }
    for (i = 0; i < this.platforms.length; i++) {
      var p = this.platforms[i];
      var vx = (p.dir === 0) ? p.speed : (p.dir === 2 ? -p.speed : 0);
      var vy = (p.dir === 1) ? p.speed : (p.dir === 3 ? -p.speed : 0);
      p.x += vx * dt; p.y += vy * dt;
    }

    /* 4) 灵魂物理：蓝魂受"重力方向"（默认向下，SansSlam 改方向、HeartMaxFallSpeed 定终端速度并可反号） */
    if (this.heart.mode === 1) {
      var mf = this.heart.maxFall || 240;
      var flip = (mf < 0) ? -1 : 1;
      var gx = (this.heart.dir === 0) ? 1 : (this.heart.dir === 2 ? -1 : 0);
      var gy = (this.heart.dir === 1) ? 1 : (this.heart.dir === 3 ? -1 : 0);
      if (!gx && !gy) gy = 1;                       // 未指定方向 → 默认向下
      gx *= flip; gy *= flip;
      this.heart.vx += gx * GRAVITY * dt;
      this.heart.vy += gy * GRAVITY * dt;
      var sp = Math.sqrt(this.heart.vx * this.heart.vx + this.heart.vy * this.heart.vy);
      var cap = Math.abs(mf);
      if (sp > cap && sp > 0) { this.heart.vx = this.heart.vx / sp * cap; this.heart.vy = this.heart.vy / sp * cap; }
      this.heart.x += this.heart.vx * dt;
      this.heart.y += this.heart.vy * dt;
    }
    /* 灵魂始终被限制在战斗框内 */
    this.heart.x = Math.max(this.zone.l + HEART_HIT / 2, Math.min(this.zone.r - HEART_HIT / 2, this.heart.x));
    this.heart.y = Math.max(this.zone.t + HEART_HIT / 2, Math.min(this.zone.b - HEART_HIT / 2, this.heart.y));
  };

  World.prototype.stepZone = function (dt) {
    var z = this.zone, sp = z.speed * dt, done = true;
    ['l', 't', 'r', 'b'].forEach(function (k) {
      var target = z['t' + k];
      if (Math.abs(z[k] - target) <= sp) z[k] = target; else { z[k] += (target > z[k] ? sp : -sp); done = false; }
    });
    if (done) {
      z.resizing = false;
      var f = z.finish; z.finish = null;
      if (f && CMD[f]) CMD[f](this);
    }
  };

  World.prototype.stepStab = function (b, dt) {
    b.t += dt;
    var zone = this.zone;
    if (b.phase === 'warn') { if (b.t >= b.warn) { b.phase = 'out'; b.t = 0; } return; }
    if (b.phase === 'out') {
      b.cur = Math.min(b.dist, b.dist * (b.t / 0.1));
      if (b.t >= 0.1) { b.phase = 'stay'; b.t = 0; b.cur = b.dist; }
      return;
    }
    if (b.phase === 'stay') { b.cur = b.dist; if (b.t >= b.stay) { b.phase = 'in'; b.t = 0; } return; }
    b.cur = b.dist * Math.max(0, 1 - b.t / 0.1);
    if (b.t >= 0.1) { b.cur = 0; b.dead = true; }
  };

  /* 骨刺墙的命中矩形 */
  World.prototype.stabRect = function (b) {
    var z = this.zone, d = b.cur || 0;
    if (b.dir === 0) return { x: z.l, y: z.t, w: d, h: z.b - z.t };
    if (b.dir === 2) return { x: z.r - d, y: z.t, w: d, h: z.b - z.t };
    if (b.dir === 1) return { x: z.l, y: z.t, w: z.r - z.l, h: d };
    return { x: z.l, y: z.b - d, w: z.r - z.l, h: d };
  };

  /* ------------------------------------------------------------ 脚本步进 */
  World.prototype.stepScript = function (dt) {
    if (!this.prog.length) return;
    var guard = 0;
    this.wait -= dt;
    while (!this.paused && !this.ended && this.wait <= 0 && guard++ < 5000) {
      if (this.pc >= this.prog.length) { this.pc = this.prog.length; return; }
      var line = this.prog[this.pc];
      var jumped = this.exec(line);
      if (this.ended) return;
      if (jumped === undefined) this.pc++;
      /* 下一行的延时 */
      if (this.pc >= this.prog.length) return;
      var nxt = this.prog[this.pc];
      var d = nxt.delay;
      this.wait = (typeof d === 'string') ? (this.vars[d.slice(1)] || 0) : d;
      if (this.wait > 0) return;
    }
  };

  World.prototype.exec = function (line) {
    var c = line.cmd;
    if (c === null || c === undefined) return undefined;      // 标签行：空操作
    if (JUMPS[c]) {
      /* 测试参数 = args 去掉第 1 个（目标） */
      var rest = line.args.slice(1).map(this.val.bind(this));
      var cond = JUMPS[c].apply(null, [this, line.target].concat(rest));
      if (cond) {
        if (line.cmd === 'JMPREL') {
          var off = (typeof line.rel === 'string' && line.rel.charAt(0) === '$')
                  ? (this.vars[line.rel.slice(1)] || 0) : Number(line.rel);
          this.pc = this.pc + off;
        } else {
          var t = line.target;
          this.pc = (typeof t === 'string') ? (this.vars[t.slice(1)] || 0) : (t | 0);
        }
        return true;
      }
      return undefined;
    }
    var fn = CMD[c];
    if (!fn) { this.say('unknown ' + c); return undefined; }
    var a = line.args.map(this.val.bind(this));
    fn.apply(null, [this].concat(a));
    return undefined;
  };

  var api = {
    World: World, CMD: CMD, compile: compile,
    VW: VW, VH: VH, BONE_W: BONE_W, BONE_HIT_W: BONE_HIT_W, HEART_HIT: HEART_HIT,
    BLASTER_W: BLASTER_W, BLASTER_BEAM_LEN: BLASTER_BEAM_LEN, GRAVITY: GRAVITY
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  global.BTS = api;
})(typeof window !== 'undefined' ? window : globalThis);
