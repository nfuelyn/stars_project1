# -*- coding: utf-8 -*-
import io
src=r"D:\stars\workspace\sans-fight\lua\_tap.lua"
dst=r"D:\stars\workspace\sans-fight\lua\_baked_smoke.lua"
s=io.open(src,encoding="utf8").read()
s=s.replace("-- 离线单测固定走参数化回退：烘焙容器需要 SetAnchorMin/Max，mock 引擎不实现。\npackage.loaded['default_import_file/workspace/sans-fight/lua/fitdata'] = {}\n","")
s=s.replace("""        SetVisible = 1, SetActive = 1, SetImage = 1, SetSiblingIndex = 1, SetSizeDelta = 1,
        SetAnchoredPosition = 1, SetLocalRotation = 1,""","""        SetVisible = 1, SetActive = 1, SetImage = 1, SetSiblingIndex = 1, SetSizeDelta = 1,
        SetAnchoredPosition = 1, SetLocalRotation = 1,
        SetAnchorMin = 1, SetAnchorMax = 1, SetPivot = 1,""",1)
io.open(dst,"w",encoding="utf8",newline="").write(s)
print("smoke written")
