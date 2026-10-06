# -*- coding: utf-8 -*-
import io
p=r"D:\stars\workspace\sans-fight\tools\verify-client-pool.mjs"
s=io.open(p,encoding="utf8").read()
s=s.replace("""  { guid: 1073743009, name: '全屏光标区', kind: 'cursor', imageId: null, anchor: 'stretch' },
];""","""  { guid: 1073743009, name: '全屏光标区', kind: 'cursor', imageId: null, anchor: 'stretch' },
  { guid: 1073743100, name: '烘焙容器', kind: 'container', imageId: null, anchor: 'corner' },
];""",1)
s=s.replace("""const G_IN_MAIN = { rect: 1073743001, circle: 1073743002, text: 1073743004,
  ring: 1073743006, rot: 1073743007, rtri: 1073743008, cursor: 1073743009 };""",
"""const G_IN_MAIN = { rect: 1073743001, circle: 1073743002, text: 1073743004,
  ring: 1073743006, rot: 1073743007, rtri: 1073743008, cursor: 1073743009,
  baked: 1073743100 };""",1)
io.open(p,"w",encoding="utf8",newline="").write(s)
print("patched verify-client-pool")
