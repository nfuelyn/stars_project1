#!/usr/bin/env node
// build-save.mjs —— 生成 qxqy-simulator-save 存档
//
// 用途：把「客户端控件模板池」写进存档。模拟器的模板池来自
//   assets.client.root.children[].guid  (runtime: registerTemplate(prefabIndex = node.guid, spec))
// Lua 侧在 OnStart 之后用 game.InstantiateClientUIControl(guid, parent) 实例化。
//
// 节点结构（transformByPlatform / giaRaw / 业务字段）从模拟器自身导出的 patch 快照克隆，
// 避免手写不完整字段被严格校验拒绝。
//
// 用法： node tools/build-save.mjs [--spill <patch快照路径>] [--script <主脚本.lua>]

import fs from 'node:fs';
import path from 'node:path';

const ROOT = 'D:\\stars';
const PROJ = path.join(ROOT, 'workspace', 'sans-fight');
const OUT = path.join(PROJ, 'sans-fight.save.json');
const TEMP = process.env.TEMP || 'C:\\Users\\19637\\AppData\\Local\\Temp';

const argv = process.argv.slice(2);
const argOf = (k, d) => {
  const i = argv.indexOf(k);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : d;
};

// 快照里必须真的含 image/textbox/container/cursor 基准节点。
// 坑：会话初始状态是插件的**演示模板**（「Lua实例化面板」），那时抓的 patch 快照没有我们的图元节点，
// 而它按时间戳可能是"最新"的 —— 直接用它会在下面抛「快照缺少基准节点」。所以这里按内容筛。
function spillHasBases(file) {
  try {
    const d = JSON.parse(fs.readFileSync(file, 'utf8'));
    if (!d.root) return false;
    const has = { image: false, textbox: false, container: false, cursor: false };
    (function walk(n) {
      if (!n) return;
      if (has[n.kind] !== undefined) has[n.kind] = true;
      for (const c of n.children || []) walk(c);
    })(d.root);
    return has.image && has.textbox && has.container && has.cursor;
  } catch { return false; }
}

function newestSpill() {
  const hits = [];
  for (const d of fs.readdirSync(TEMP)) {
    if (!d.startsWith('dsh-spill-')) continue;
    const p1 = path.join(TEMP, d);
    if (!fs.statSync(p1).isDirectory()) continue;
    for (const s of fs.readdirSync(p1)) {
      const p2 = path.join(p1, s);
      if (!fs.statSync(p2).isDirectory()) continue;
      for (const f of fs.readdirSync(p2)) {
        if (f.endsWith('-qxqy_studio_patch.txt')) hits.push(path.join(p2, f));
      }
    }
  }
  hits.sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);
  for (const h of hits) if (spillHasBases(h)) return h;
  return hits[0];
}

const spill = argOf('--spill', newestSpill());
const dump = JSON.parse(fs.readFileSync(spill, 'utf8'));
if (!dump.root) throw new Error(`快照里没有 root：${spill}`);

const PLATFORMS = ['KEYBOARD', 'TOUCHSCREEN', 'CONTROLLER_CONSOLE', 'CONTROLLER_MOBILE'];
const clone = (o) => JSON.parse(JSON.stringify(o));
const walk = (n, fn) => { fn(n); for (const c of n.children || []) walk(c, fn); };
const findByKind = (n, kind) => { let hit = null; walk(n, (x) => { if (!hit && x.kind === kind) hit = x; }); return hit; };

const srcRoot = dump.root;
const baseImage = findByKind(srcRoot, 'image');
const baseText = findByKind(srcRoot, 'textbox');
const baseContainer = findByKind(srcRoot, 'container');
const baseCursor = findByKind(srcRoot, 'cursor');
if (!baseImage || !baseText || !baseContainer || !baseCursor) throw new Error('快照缺少 image/textbox/container/cursor 基准节点');

// 左下图元（轴对齐）：anchor/pivot 都在左下角，运行时 anchoredPosition 即画布坐标
function tfCorner(w, h) {
  const o = {};
  for (const p of PLATFORMS) {
    o[p] = {
      scale: { x: 1, y: 1, z: 1 }, rotation: { x: 0, y: 0, z: 0 },
      anchorMin: { x: 0, y: 0 }, anchorMax: { x: 0, y: 0 },
      offset: { x: 0, y: 0 }, size: { x: w, y: h }, pivot: { x: 0, y: 0 },
    };
  }
  return o;
}
// 中心锚点（旋转件用）：anchor/pivot 都在中心
function tfCenter(w, h) {
  const o = {};
  for (const p of PLATFORMS) {
    o[p] = {
      scale: { x: 1, y: 1, z: 1 }, rotation: { x: 0, y: 0, z: 0 },
      anchorMin: { x: 0.5, y: 0.5 }, anchorMax: { x: 0.5, y: 0.5 },
      offset: { x: 0, y: 0 }, size: { x: w, y: h }, pivot: { x: 0.5, y: 0.5 },
    };
  }
  return o;
}
// 拉伸（容器用）
function tfStretch() {
  const o = {};
  for (const p of PLATFORMS) {
    o[p] = {
      scale: { x: 1, y: 1, z: 1 }, rotation: { x: 0, y: 0, z: 0 },
      anchorMin: { x: 0, y: 0 }, anchorMax: { x: 1, y: 1 },
      offset: { x: 0, y: 0 }, size: { x: 0, y: 0 }, pivot: { x: 0.5, y: 0.5 },
    };
  }
  return o;
}

// 光标检测区域（全屏铺满）：只做指针/触摸命中，不做外观。
// 客户端 Lua 里 AddCursorEventListener 只存在于 cursor / button 两类控件上（公共方法表里没有），
// 所以指针输入必须靠它；祖先容器还要 showCursor = true 才会派发（worker.js 的 cursorEventsEnabled）。
function mkCursor({ id, guid, name }) {
  const n = clone(baseCursor);
  n.id = id; n.guid = guid; n.name = name; n.kind = 'cursor';
  n.children = []; n.scriptMappingIds = []; n.giaRelatedGuids = [];
  n.active = true; n.visible = true; n.canControllerFocus = false; n.syncAllDevices = true;
  n.raycastTarget = true;
  n.transformByPlatform = tfStretch();
  return n;
}

function mkImage({ id, guid, name, imageId, w, h, center = false }) {
  const n = clone(baseImage);
  n.id = id; n.guid = guid; n.name = name; n.kind = 'image';
  n.children = []; n.scriptMappingIds = []; n.giaRelatedGuids = [];
  n.active = true; n.visible = true; n.canControllerFocus = false; n.syncAllDevices = true;
  n.imageSource = 'StaticReference';
  n.imageId = imageId;
  n.imageColor = 4294967295;
  n.enableMask = false;
  n.enableSoftEdge = false;
  n.softEdgeMode = 'Percentage';
  n.softEdgeWidthX = 8; n.softEdgeWidthY = 8;
  n.horizontalSoftRange = 85; n.verticalSoftRange = 85;
  n.enableFill = false;
  n.fillType = 'Horizontal'; n.fillHorizontalType = 'Left'; n.fillVerticalType = 'Bottom';
  n.fillRadial90Type = 'BottomLeft'; n.fillRadialType = 'Bottom'; n.fillAmount = 1;
  n.reverseMaskArea = false;
  n.transformByPlatform = center ? tfCenter(w, h) : tfCorner(w, h);
  return n;
}

function mkText({ id, guid, name, text, w, h, fontSize }) {
  const n = clone(baseText);
  n.id = id; n.guid = guid; n.name = name; n.kind = 'textbox';
  n.children = []; n.scriptMappingIds = []; n.giaRelatedGuids = [];
  n.active = true; n.visible = true; n.canControllerFocus = false; n.syncAllDevices = true;
  n.text = text; n.fontSize = fontSize;
  n.fontColor = 4294967295; n.bgColor = 16777215;
  n.enableOutline = true; n.outlineColor = 858993459;
  n.horizontalAlignment = 'Left'; n.verticalAlignment = 'Top';
  if ('adaptiveFontSize' in n) n.adaptiveFontSize = false;
  if ('minimumFontSize' in n) n.minimumFontSize = fontSize;
  n.transformByPlatform = tfCorner(w, h);
  return n;
}

// 烘焙容器（左下锚点、零尺寸）：运行期 Lua 往里实例化逐像素矩形子控件，
// 再用 SetSizeDelta 缩放整个容器（子控件用比例锚点，随父尺寸缩放）。
function tfCornerBase() {
  const o = {};
  for (const p of PLATFORMS) {
    o[p] = {
      scale: { x: 1, y: 1, z: 1 }, rotation: { x: 0, y: 0, z: 0 },
      anchorMin: { x: 0, y: 0 }, anchorMax: { x: 0, y: 0 },
      offset: { x: 0, y: 0 }, size: { x: 0, y: 0 }, pivot: { x: 0, y: 0 },
    };
  }
  return o;
}
function tfCenterBase() {
  const o = {};
  for (const p of PLATFORMS) {
    o[p] = {
      scale: { x: 1, y: 1, z: 1 }, rotation: { x: 0, y: 0, z: 0 },
      anchorMin: { x: 0.5, y: 0.5 }, anchorMax: { x: 0.5, y: 0.5 },
      offset: { x: 0, y: 0 }, size: { x: 0, y: 0 }, pivot: { x: 0.5, y: 0.5 },
    };
  }
  return o;
}
function tfStretchBase() {
  const o = {};
  for (const p of PLATFORMS) {
    o[p] = {
      scale: { x: 1, y: 1, z: 1 }, rotation: { x: 0, y: 0, z: 0 },
      anchorMin: { x: 0, y: 0 }, anchorMax: { x: 1, y: 1 },
      offset: { x: 0, y: 0 }, size: { x: 0, y: 0 }, pivot: { x: 0.5, y: 0.5 },
    };
  }
  return o;
}
function mkContainer({ id, guid, name, center = false, stretch = false }) {
  const n = clone(baseContainer);
  n.id = id; n.guid = guid; n.name = name; n.kind = 'container';
  n.children = []; n.scriptMappingIds = []; n.giaRelatedGuids = [];
  n.active = true; n.visible = true; n.canControllerFocus = false; n.syncAllDevices = true;
  n.showCursor = false;
  n.transformByPlatform = stretch ? tfStretchBase() : (center ? tfCenterBase() : tfCornerBase());
  return n;
}

// ---- 模板池：一套图元即可拼出骨头 / 灵魂 / 龙骨炮 / 战斗框 / 平台 / 文字 ----
// 只放**真的会被 take() 取用**的图元。判定依据（两处都必须为空才算没用）：
//   ① lua/main.lua 里没有 `take('<kind>')`；② 整场对局里该 guid 的实例化次数为 0
//      （`node tools/run-lua.mjs lua/_pool.lua` 的 C 节逐 guid 统计）。
// 已按此删除：100004 fourstar（guid 1073743005，从未被取用）与
//             100003 的左下锚点三角（guid 1073743003，三角只用中心锚点的 rtri 1073743008）。
// 保留说明：ring 虚拟摇杆在用；rot/rtri 旋转件在用；text 文本在用；cursor 是全屏输入面。
const TEMPLATES = [
  mkImage({ id: 'tRect', guid: 1073743001, name: '矩形图元', imageId: 100001, w: 8, h: 8 }),
  mkImage({ id: 'tCircle', guid: 1073743002, name: '圆形图元', imageId: 100002, w: 8, h: 8 }),
  mkText({ id: 'tText', guid: 1073743004, name: '文本图元', text: '', w: 200, h: 40, fontSize: 28 }),
  mkImage({ id: 'tRing', guid: 1073743006, name: '圆环图元', imageId: 100006, w: 8, h: 8 }),
  mkImage({ id: 'tRot', guid: 1073743007, name: '旋转图元', imageId: 100001, w: 8, h: 8, center: true }),
  mkImage({ id: 'tRotTri', guid: 1073743008, name: '旋转三角图元', imageId: 100003, w: 8, h: 8, center: true }),
  mkCursor({ id: 'tCursor', guid: 1073743009, name: '全屏光标区' }),
  mkContainer({ id: 'tBaked', guid: 1073743100, name: '烘焙容器·左下' }),
  mkContainer({ id: 'tBakedC', guid: 1073743101, name: '烘焙容器·中心', center: true }),
  mkContainer({ id: 'tBakedRoot', guid: 1073743102, name: '烘焙容器根', stretch: true }),
];

// ---- 客户端资产：root.children 即模板池 ----
// 资产名会显示在编辑器的「界面控件组管理」里，别用插件的演示名（Lua实例化面板），否则和真机对照时容易认错。
const CLIENT_ASSET_NAME = `审判者战 · 图元池（${TEMPLATES.length} 图元）`;
const clientRoot = clone(srcRoot);
clientRoot.id = 'c1'; clientRoot.guid = 1073742999; clientRoot.name = CLIENT_ASSET_NAME;
clientRoot.scriptMappingIds = [];
clientRoot.transformByPlatform = tfStretch();
clientRoot.children = TEMPLATES;

const clientProject = {
  version: 1,
  layoutSchemaVersion: dump.layoutSchemaVersion ?? 2,
  meta: { name: CLIENT_ASSET_NAME, assetType: 'client-control-template', sourceFormat: 'authoring', sourceFile: '' },
  canvasId: 'mobile-16-9',
  selectedId: 'c1',
  root: clientRoot,
};

// ---- 服务端资产：只留脚本挂载容器（外观全部由实例化模板承担） ----
const mount = clone(baseContainer);
mount.id = 'n1'; mount.guid = 1073741851; mount.name = '容器节点';
mount.children = []; mount.scriptMappingIds = [1073742105];
mount.transformByPlatform = tfStretch();
// 指针/触摸事件需要祖先容器打开 showCursor（worker.js cursorEventsEnabled 的判定）
mount.showCursor = true;

const serverRoot = clone(srcRoot);
serverRoot.id = 'sc1'; serverRoot.guid = 1073741850; serverRoot.name = '客户端控件容器';
serverRoot.scriptMappingIds = [];
serverRoot.children = [mount];

const serverProject = {
  version: 1,
  layoutSchemaVersion: dump.layoutSchemaVersion ?? 2,
  meta: { name: '审判者战 · UI', assetType: 'server-control-template', sourceFormat: 'authoring', sourceFile: '' },
  canvasId: 'mobile-16-9',
  selectedId: 'n1',
  root: serverRoot,
};

// ---- 脚本：**自足单文件**（模块垫片 + 内联 core/attacks/main） ----
// 依据 nightingale-0/millastra-6nimmt 的 AGENTS.md：官方客户端 Lua 沙箱**没有 require 全局**，
// 跨脚本 require 在真机不保证解析得到。所以挂载脚本自带一个 local require 垫片，把 core/attacks/main
// 原样内联进来 —— 真机/模拟器都只依赖这一条脚本。
// `--script <file>` 仍可整体替换（调试用）。
const MOD = 'default_import_file/workspace/sans-fight/lua/';
const readLua = (rel) => fs.readFileSync(path.join(PROJ, rel), 'utf8');
const rawOverride = argOf('--script', '');
let bundle;
if (rawOverride) {
  bundle = fs.readFileSync(rawOverride, 'utf8');
} else {
  bundle = [
    '-- 自动生成（tools/build-save.mjs）—— 请勿手改；改逻辑请改 lua/*.lua 后重建存档。',
    '-- 千星客户端 Lua 沙箱没有 require：这里自带模块垫片，把 core/attacks/main 内联成一个自足脚本。',
    'local __modules = {}',
    'local function require(p) return __modules[p] end',
    '',
    `__modules['${MOD}core'] = (function()`,
    readLua('lua/core.lua'),
    'end)()',
    '',
    `__modules['${MOD}attacks'] = (function()`,
    readLua('lua/attacks.lua'),
    'end)()',
    '',
    `__modules['${MOD}fitdata'] = (function()`,
    readLua('lua/fitdata.lua'),
    'end)()',
    '',
    `__modules['${MOD}main'] = (function()`,
    readLua('lua/main.lua'),
    'end)()',
    '',
    `local M = __modules['${MOD}main']`,
    'local function call(name, ...)',
    '  if M and type(M[name]) == \'function\' then',
    '    local ok, err = pcall(M[name], ...)',
    '    if not ok then print(\'boot: \' .. name .. \' 出错 :: \' .. tostring(err)) end',
    '  end',
    'end',
    'function OnInit() call(\'OnInit\') end',
    'function OnEnable() call(\'OnEnable\') end',
    'function OnStart() call(\'OnStart\') end',
    'function OnUpdate(dt) call(\'OnUpdate\', dt) end',
    'function OnLevelUpdate(dt) call(\'OnLevelUpdate\', dt) end',
    'function OnDisable() call(\'OnDisable\') end',
    'function OnDestroy() call(\'OnDestroy\') end',
    '',
  ].join('\n');
}
const scripts = [{
  id: '1073742105', guid: 1073742105, path: '',
  source: bundle,
  controlId: 'n1', controlAsset: 'server-control-template',
}];
const save = {
  format: 'qxqy-simulator-save',
  version: 4,
  meta: { name: '审判者战 · sans-fight' },
  activeAssetType: 'server-control-template',
  serverLogic: { version: 1, rules: [] },
  assets: { server: serverProject, client: clientProject, scripts },
};

fs.writeFileSync(OUT, JSON.stringify(save, null, 2) + '\n', 'utf8');
const bytes = fs.statSync(OUT).size;
console.log(`[build-save] 快照 ${path.basename(spill)}`);
console.log(`[build-save] 主脚本 = 内联包（core+attacks+main 共 ${(bundle.length/1024).toFixed(1)} KB）` + (rawOverride ? ' [--script 覆盖]' : ''));
console.log(`[build-save] 模板池 ${TEMPLATES.length} 个：` + TEMPLATES.map((t) => `${t.name}(${t.guid})`).join(', '));
console.log(`[build-save] 脚本 ${scripts.length} 条` + scripts.map((s) => ` ${s.id}${s.controlId ? '@' + s.controlId : '(module)'}`).join(''));
console.log(`[build-save] 写出 ${OUT} (${bytes} bytes)`);
