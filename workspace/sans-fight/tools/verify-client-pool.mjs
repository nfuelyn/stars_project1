// verify-client-pool.mjs -- 校验存档里的「客户端控件组」是否满足运行时契约。
//
// 为什么要这个：`game.InstantiateClientUIControl(prefabIndex, parent)` 的首参就是模板节点的 **guid**，
// 锚点/pivot 又决定了 `SetAnchoredPosition` 的语义。任何一项对不上，表现是「实例化返回 nil → 屏幕全空」
// 或「整体画歪」，而在 Lua 侧只会看到一句 `inst NIL xxx`。所以把契约写成可复跑的断言。
//
// 用法：node tools/verify-client-pool.mjs [sans-fight.save.json]
import fs from 'node:fs';
import path from 'node:path';

const file = process.argv[2] || 'sans-fight.save.json';
const save = JSON.parse(fs.readFileSync(file, 'utf8'));

// 契约：guid -> { kind, imageId(可选), 锚点档位, 说明 }
// 锚点档位：corner = 锚点/中心都在左下 (0,0)（画布坐标即 SetAnchoredPosition 的参数）；
//          center = 都在中心 (0.5,0.5)（旋转件用，旋转绕自身中心）；
//          stretch = 锚点 (0,0)-(1,1) 拉伸铺满父容器（全屏光标区用；适配层不写它的尺寸/位置）。
// **条数必须与 tools/build-save.mjs 的 TEMPLATES 完全一致**（多一个少一个都 FAIL）：
// 只登记真的会被 main.lua `take()` 取用的图元；fourstar（100004）与左下锚点三角（100003）
// 已按「整场 0 次取用」的实测删除（见 lua/_pool.lua 的 C 节）。
const EXPECT = [
  { guid: 1073743001, name: '矩形图元', kind: 'image', imageId: 100001, anchor: 'corner' },
  { guid: 1073743002, name: '圆形图元', kind: 'image', imageId: 100002, anchor: 'corner' },
  { guid: 1073743004, name: '文本图元', kind: 'textbox', imageId: null, anchor: 'corner' },
  { guid: 1073743006, name: '圆环图元', kind: 'image', imageId: 100006, anchor: 'corner' },
  { guid: 1073743007, name: '旋转图元', kind: 'image', imageId: 100001, anchor: 'center' },
  { guid: 1073743008, name: '旋转三角图元', kind: 'image', imageId: 100003, anchor: 'center' },
  { guid: 1073743009, name: '全屏光标区', kind: 'cursor', imageId: null, anchor: 'stretch' },
  { guid: 1073743100, name: '烘焙容器·左下', kind: 'container', imageId: null, anchor: 'corner' },
  { guid: 1073743101, name: '烘焙容器·中心', kind: 'container', imageId: null, anchor: 'center' },
  { guid: 1073743102, name: '烘焙容器根', kind: 'container', imageId: null, anchor: 'stretch' },
];

// 主脚本里写死的 guid 表也要与上面一致
const MAIN_LUA = path.join('lua', 'main.lua');
const mainSrc = fs.existsSync(MAIN_LUA) ? fs.readFileSync(MAIN_LUA, 'utf8') : '';
const G_IN_MAIN = { rect: 1073743001, circle: 1073743002, text: 1073743004,
  ring: 1073743006, rot: 1073743007, rtri: 1073743008, cursor: 1073743009,
  baked: 1073743100, bakedC: 1073743101, bakedRoot: 1073743102 };

const fails = [];
const rows = [];
const clientRoot = save?.assets?.client?.root;
if (!clientRoot) fails.push('存档里没有 assets.client.root（客户端控件组缺失）');
const kids = clientRoot?.children || [];
const byGuid = new Map(kids.map((k) => [k.guid, k]));

for (const e of EXPECT) {
  const n = byGuid.get(e.guid);
  if (!n) { fails.push(`缺模板 guid=${e.guid}（${e.name}）—— 实例化会返回 nil`); continue; }
  if (n.kind !== e.kind) fails.push(`guid=${e.guid} kind=${n.kind}，应为 ${e.kind}`);
  const img = n.imageId ?? null;
  if (img !== e.imageId) fails.push(`guid=${e.guid} imageId=${img}，应为 ${e.imageId}`);
  const t = n.transformByPlatform || {};
  const bad = [];
  for (const [plat, tf] of Object.entries(t)) {
    if (e.anchor === 'stretch') {
      if (tf.anchorMin?.x !== 0 || tf.anchorMin?.y !== 0) bad.push(`${plat}.anchorMin`);
      if (tf.anchorMax?.x !== 1 || tf.anchorMax?.y !== 1) bad.push(`${plat}.anchorMax`);
    } else {
      const want = e.anchor === 'corner' ? 0 : 0.5;
      if (tf.anchorMin?.x !== want || tf.anchorMin?.y !== want) bad.push(`${plat}.anchorMin`);
      if (tf.anchorMax?.x !== want || tf.anchorMax?.y !== want) bad.push(`${plat}.anchorMax`);
      if (tf.pivot?.x !== want || tf.pivot?.y !== want) bad.push(`${plat}.pivot`);
    }
  }
  const wantText = e.anchor === 'corner' ? '应左下(0,0)' : (e.anchor === 'center' ? '应中心(0.5,0.5)' : '应拉伸(0,0)-(1,1)');
  if (bad.length) fails.push(`guid=${e.guid} 锚点/中心不符（${wantText}）：${bad.slice(0, 4).join(', ')}`);
  const label = e.anchor === 'corner' ? '左下(0,0)' : (e.anchor === 'center' ? '中心(.5,.5)' : '拉伸铺满');
  rows.push({ guid: e.guid, name: n.name, kind: n.kind, imageId: img ?? '-', 锚点: label, 平台: Object.keys(t).length });
}

// 主脚本 guid 表一致性
for (const [k, v] of Object.entries(G_IN_MAIN)) {
  if (!mainSrc.includes(String(v))) fails.push(`lua/main.lua 的 G.${k}=${v} 在存档模板池里找不到`);
}
// 多余模板（不一定是错，只提示）
const extra = kids.filter((k) => !EXPECT.some((e) => e.guid === k.guid));
// 模板数必须与契约表逐条对应：多一个（多余模板）就说明契约表没跟上，少一个下面按 guid 报缺失。
// 这条让「模板数随实际模板数变化」不再靠人肉同步（build-save.mjs 与 EXPECT 两边一起改）。
if (kids.length !== EXPECT.length) {
  fails.push(`模板数 ${kids.length} ≠ 契约表 ${EXPECT.length} 条`
    + (extra.length ? `（多余：${extra.map((e) => `${e.guid}/${e.name}`).join(', ')}）` : ''));
}
// 光标区必须唯一：多份会互相抢事件
const cursors = kids.filter((k) => k.kind === 'cursor');
if (cursors.length !== 1) fails.push(`cursor 模板应有且仅有 1 个，实为 ${cursors.length}`);

console.log(`存档：${file}`);
console.log(`客户端资产名：${save?.assets?.client?.meta?.name || save?.assets?.client?.name || '(空)'}  根 ${clientRoot?.id}@${clientRoot?.guid}`);
console.log(`模板数：${kids.length}（契约 ${EXPECT.length}）  多余：${extra.map((e) => e.guid).join(',') || '无'}`);
console.log('');
for (const r of rows) {
  console.log(`  ${String(r.guid).padEnd(11)} ${String(r.name).padEnd(12)} ${r.kind.padEnd(8)} imageId=${String(r.imageId).padEnd(7)} 锚点=${r.锚点} 平台槽=${r.平台}`);
}
console.log('');
if (fails.length === 0) {
  console.log(`客户端控件组校验：PASS（${EXPECT.length} 项契约全部满足）`);
} else {
  console.log(`客户端控件组校验：FAIL ${fails.length} 项`);
  for (const f of fails) console.log('  - ' + f);
  process.exitCode = 1;
}
