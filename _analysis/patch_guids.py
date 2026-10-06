# -*- coding: utf-8 -*-
import io, os
p=r"D:\stars\workspace\sans-fight\lua\_pool.lua"
s=io.open(p,encoding="utf8").read()
s=s.replace("""  [1073743007] = 'rot', [1073743008] = 'rtri', [1073743009] = 'cursor',
}""","""  [1073743007] = 'rot', [1073743008] = 'rtri', [1073743009] = 'cursor',
  [1073743100] = 'baked', [1073743101] = 'bakedC', [1073743102] = 'bakedRoot',
}""",1)
s=s.replace("""local ALL_GUIDS = { 1073743001, 1073743002, 1073743004,
                    1073743006, 1073743007, 1073743008, 1073743009 }""","""local ALL_GUIDS = { 1073743001, 1073743002, 1073743004,
                    1073743006, 1073743007, 1073743008, 1073743009, 1073743102 }""",1)
io.open(p,"w",encoding="utf8",newline="").write(s)
g=r"D:\stars\workspace\sans-fight\lua\_geometry.lua"
t=io.open(g,encoding="utf8").read()
t=t.replace("""  [1073743007] = 'rot', [1073743008] = 'rtri', [1073743009] = 'cursor',
}""","""  [1073743007] = 'rot', [1073743008] = 'rtri', [1073743009] = 'cursor',
  [1073743100] = 'baked', [1073743101] = 'bakedC', [1073743102] = 'bakedRoot',
}""",1)
io.open(g,"w",encoding="utf8",newline="").write(t)
smoke=r"D:\stars\workspace\sans-fight\lua\_baked_smoke.lua"
if os.path.exists(smoke): os.remove(smoke)
print("patched test guid maps; smoke removed:", not os.path.exists(smoke))
