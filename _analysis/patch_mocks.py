# -*- coding: utf-8 -*-
import io
key="package.loaded['default_import_file/workspace/sans-fight/lua/attacks'] = attacks"
stub="\n-- 离线单测固定走参数化回退：烘焙容器需要 SetAnchorMin/Max，mock 引擎不实现。\npackage.loaded['default_import_file/workspace/sans-fight/lua/fitdata'] = {}"
for p in [r"D:\stars\workspace\sans-fight\lua\_tap.lua", r"D:\stars\workspace\sans-fight\lua\_input.lua", r"D:\stars\workspace\sans-fight\lua\_title.lua"]:
    s=io.open(p,encoding="utf8").read()
    if key in s and "lua/fitdata" not in s:
        s=s.replace(key, key+stub,1)
        io.open(p,"w",encoding="utf8",newline="").write(s)
        print("stubbed",p)
