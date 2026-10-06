# -*- coding: utf-8 -*-
import io
p=r"D:\stars\workspace\sans-fight\tools\build-save.mjs"
s=io.open(p,encoding="utf8").read()
s=s.replace("""function mkContainer({ id, guid, name }) {
  const n = clone(baseContainer);
  n.id = id; n.guid = guid; n.name = name; n.kind = 'container';
  n.children = []; n.scriptMappingIds = []; n.giaRelatedGuids = [];
  n.active = true; n.visible = true; n.canControllerFocus = false; n.syncAllDevices = true;
  n.showCursor = false;
  n.transformByPlatform = tfCornerBase();
  return n;
}""","""function tfCenterBase() {
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
function mkContainer({ id, guid, name, center = false }) {
  const n = clone(baseContainer);
  n.id = id; n.guid = guid; n.name = name; n.kind = 'container';
  n.children = []; n.scriptMappingIds = []; n.giaRelatedGuids = [];
  n.active = true; n.visible = true; n.canControllerFocus = false; n.syncAllDevices = true;
  n.showCursor = false;
  n.transformByPlatform = center ? tfCenterBase() : tfCornerBase();
  return n;
}""",1)
s=s.replace("""  mkContainer({ id: 'tBaked', guid: 1073743100, name: '烘焙容器' }),
];""","""  mkContainer({ id: 'tBaked', guid: 1073743100, name: '烘焙容器·左下' }),
  mkContainer({ id: 'tBakedC', guid: 1073743101, name: '烘焙容器·中心', center: true }),
];""",1)
io.open(p,"w",encoding="utf8",newline="").write(s)
# verify-client-pool: add center entry
v=r"D:\stars\workspace\sans-fight\tools\verify-client-pool.mjs"
t=io.open(v,encoding="utf8").read()
t=t.replace("""  { guid: 1073743100, name: '烘焙容器', kind: 'container', imageId: null, anchor: 'corner' },
];""","""  { guid: 1073743100, name: '烘焙容器·左下', kind: 'container', imageId: null, anchor: 'corner' },
  { guid: 1073743101, name: '烘焙容器·中心', kind: 'container', imageId: null, anchor: 'center' },
];""",1)
t=t.replace("""  baked: 1073743100 };""","""  baked: 1073743100, bakedC: 1073743101 };""",1)
io.open(v,"w",encoding="utf8",newline="").write(t)
print("patched 2 templates")
