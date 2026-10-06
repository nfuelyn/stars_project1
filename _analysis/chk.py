import json
p=r"D:\stars\workspace\sans-fight\sans-fight.save.json"
d=json.load(open(p,encoding="utf8"))
src=d["assets"]["scripts"][0]["source"]
print("bundle KB", round(len(src.encode("utf8"))/1024,1))
print("has fitdata module:", "lua/fitdata'] = (function()" in src)
print("has baked keys:", "M.sans_poses" in src, "M.blaster_keys" in src)
print("templates:", [c["guid"] for c in d["assets"]["client"]["root"]["children"]])
