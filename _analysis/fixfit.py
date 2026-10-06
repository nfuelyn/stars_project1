import io
p=r"D:\stars\workspace\sans-fight\tools\fit-sprites.py"
s=io.open(p,encoding="utf8").read()
s=s.replace("}\n}\nlines = [\n    \"-- fitdata.lua", "}\nlines = [\n    \"-- fitdata.lua",1)
io.open(p,"w",encoding="utf8",newline="").write(s)
print("fixed")
