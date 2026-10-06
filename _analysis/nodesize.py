import json
p=r"D:\stars\workspace\sans-fight\sans-fight.save.json"
d=json.load(open(p,encoding="utf8"))
ch=d["assets"]["client"]["root"]["children"]
print("templates:",[(c["name"],c["kind"],c["guid"]) for c in ch])
for c in ch[:2]:
    s=json.dumps(c,ensure_ascii=False)
    print(c["name"],"node bytes=",len(s.encode("utf8")), "children=",len(c.get("children",[])))
