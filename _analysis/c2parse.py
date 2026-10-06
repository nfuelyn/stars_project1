# -*- coding: utf-8 -*-
import xml.etree.ElementTree as ET
p=r"D:\c2-sans-fight-src\Bad Time Simulator (Sans Fight).caproj"
tree=ET.parse(p); root=tree.getroot()
for ot in root.iter("object-type"):
    name=ot.get("name")
    if name not in ("SansBody","SansHead","SansTorso","SansLegs","SansSweat","GasterBlaster","BoneV","BoneH"): continue
    print("="*70); print("OBJECT",name)
    for anim in ot.iter("animation"):
        print("  anim",anim.get("name"),"frames",anim.get("framecount"),"speed",anim.get("speed"),"loop",anim.get("loop"))
        for i,fr in enumerate(anim.findall("frame")):
            pts=[(ip.get("name"),ip.get("x"),ip.get("y")) for ip in fr.findall("image-point")]
            cp=fr.find("collision-poly")
            print(f"    f{i} hotspot=({fr.get('hotspotX')},{fr.get('hotspotY')}) pts={pts}" + (" collision" if cp is not None else ""))
