# -*- coding: utf-8 -*-
import io
# 1) build-save: stretch variant + template
p=r"D:\stars\workspace\sans-fight\tools\build-save.mjs"
s=io.open(p,encoding="utf8").read()
s=s.replace("""function mkContainer({ id, guid, name, center = false }) {
  const n = clone(baseContainer);
  n.id = id; n.guid = guid; n.name = name; n.kind = 'container';
  n.children = []; n.scriptMappingIds = []; n.giaRelatedGuids = [];
  n.active = true; n.visible = true; n.canControllerFocus = false; n.syncAllDevices = true;
  n.showCursor = false;
  n.transformByPlatform = center ? tfCenterBase() : tfCornerBase();
  return n;
}""","""function tfStretchBase() {
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
}""",1)
s=s.replace("""  mkContainer({ id: 'tBakedC', guid: 1073743101, name: '烘焙容器·中心', center: true }),
];""","""  mkContainer({ id: 'tBakedC', guid: 1073743101, name: '烘焙容器·中心', center: true }),
  mkContainer({ id: 'tBakedRoot', guid: 1073743102, name: '烘焙容器根', stretch: true }),
];""",1)
io.open(p,"w",encoding="utf8",newline="").write(s)
# 2) verify entries
v=r"D:\stars\workspace\sans-fight\tools\verify-client-pool.mjs"
t=io.open(v,encoding="utf8").read()
t=t.replace("""  { guid: 1073743101, name: '烘焙容器·中心', kind: 'container', imageId: null, anchor: 'center' },
];""","""  { guid: 1073743101, name: '烘焙容器·中心', kind: 'container', imageId: null, anchor: 'center' },
  { guid: 1073743102, name: '烘焙容器根', kind: 'container', imageId: null, anchor: 'stretch' },
];""",1)
t=t.replace("""  baked: 1073743100, bakedC: 1073743101 };""","""  baked: 1073743100, bakedC: 1073743101, bakedRoot: 1073743102 };""",1)
io.open(v,"w",encoding="utf8",newline="").write(t)
# 3) main.lua: G + tryLoadFit + OnStart root kind
m=r"D:\stars\workspace\sans-fight\lua\main.lua"
x=io.open(m,encoding="utf8").read()
x=x.replace("""  cursor = 1073743009, baked = 1073743100, bakedC = 1073743101,""",
            """  cursor = 1073743009, baked = 1073743100, bakedC = 1073743101, bakedRoot = 1073743102,""",1)
x=x.replace("""local function tryLoadFit()
  local ok, m = pcall(require, 'default_import_file/workspace/sans-fight/lua/fitdata')
  if ok and type(m) == 'table' and next(m) ~= nil then return m end
  local ok2, m2 = pcall(require, 'lua' .. '.fitdata')
  if ok2 and type(m2) == 'table' and next(m2) ~= nil then return m2 end
  print('main: fitdata 未加载（用参数化外观）:: ' .. tostring(m))
  return nil
end""","""local function tryLoadFit()
  local ok, m = pcall(require, 'default_import_file/workspace/sans-fight/lua/fitdata')
  -- 主路径成功即返回（离线单测会把它 stub 成空表 → 走参数化回退）
  if ok and type(m) == 'table' then return m end
  local ok2, m2 = pcall(require, 'lua' .. '.fitdata')
  if ok2 and type(m2) == 'table' then return m2 end
  print('main: fitdata 未加载（用参数化外观）:: ' .. tostring(m))
  return nil
end""",1)
x=x.replace("""  bakedRoot = spawn('baked')
  if bakedRoot then
    put(bakedRoot, 0, 0, 0, 0)""","""  bakedRoot = spawn('bakedRoot')
  if bakedRoot then
    put(bakedRoot, 0, 0, 0, 0)""",1)
io.open(m,"w",encoding="utf8",newline="").write(x)
print("patched root/stretch + fit fallback")
