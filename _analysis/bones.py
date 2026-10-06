from PIL import Image
import os
base=r"D:\stars\workspace\sans-fight\reference\sprites"
for name,rel in [("BoneV","textures/BoneV.png"),("BoneH","textures/BoneH.png"),
                 ("BoneStabV","textures/BoneStabV.png"),("BoneStabH","textures/BoneStabH.png"),
                 ("BoneStabWarn","textures/BoneStabWarn.png")]:
    im=Image.open(os.path.join(base,rel)).convert("RGBA"); w,h=im.size
    print("="*40, name, f"{w}x{h}")
    for y in range(h):
        line=""
        for x in range(w):
            r,g,b,a=im.getpixel((x,y))
            line += "#" if a>128 and (r+g+b)>300 else ("R" if a>128 else ".")
        print(line)
