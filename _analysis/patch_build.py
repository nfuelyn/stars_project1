# -*- coding: utf-8 -*-
import io
p=r"D:\stars\workspace\sans-fight\tools\build-save.mjs"
s=io.open(p,encoding="utf8").read()
# 1) add mkContainer after mkText
anchor = """// ---- 模板池：一套图元即可拼出骨头 / 灵魂 / 龙骨炮 / 战斗框 / 平台 / 文字 ----"""
add = """// 烘焙容器（左下锚点、零尺寸）：运行期 Lua 往里实例化逐像素矩形子控件，
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
function mkContainer({ id, guid, name }) {
  const n = clone(baseContainer);
  n.id = id; n.guid = guid; n.name = name; n.kind = 'container';
  n.children = []; n.scriptMappingIds = []; n.giaRelatedGuids = [];
  n.active = true; n.visible = true; n.canControllerFocus = false; n.syncAllDevices = true;
  n.showCursor = false;
  n.transformByPlatform = tfCornerBase();
  return n;
}

""" + anchor
assert anchor in s
s=s.replace(anchor,add,1)
# 2) add template
old_t = """  mkCursor({ id: 'tCursor', guid: 1073743009, name: '全屏光标区' }),
];"""
new_t = """  mkCursor({ id: 'tCursor', guid: 1073743009, name: '全屏光标区' }),
  mkContainer({ id: 'tBaked', guid: 1073743100, name: '烘焙容器' }),
];"""
assert old_t in s
s=s.replace(old_t,new_t,1)
# 3) inline fitdata module before main
old_m = """    `__modules['${MOD}main'] = (function()`,
    readLua('lua/main.lua'),
    'end)()',"""
new_m = """    `__modules['${MOD}fitdata'] = (function()`,
    readLua('lua/fitdata.lua'),
    'end)()',
    '',
    `__modules['${MOD}main'] = (function()`,
    readLua('lua/main.lua'),
    'end)()',"""
assert old_m in s
s=s.replace(old_m,new_m,1)
io.open(p,"w",encoding="utf8",newline="").write(s)
print("patched build-save")
