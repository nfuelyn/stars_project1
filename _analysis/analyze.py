from PIL import Image
from collections import Counter
import os
base = r"D:\stars\workspace\sans-fight\reference\sprites"
files = [
 ("SansBody/HandDown/000", "animations/SansBody/HandDown/000.png"),
 ("SansBody/HandUp/000", "animations/SansBody/HandUp/000.png"),
 ("SansHead/Default/000", "animations/SansHead/Default/000.png"),
 ("Blaster/Default/000", "animations/GasterBlaster/Default/000.png"),
 ("Blaster/Fire/000", "animations/GasterBlaster/Fire/000.png"),
 ("Blaster/Fire/004", "animations/GasterBlaster/Fire/004.png"),
 ("BoneV", "textures/BoneV.png"),
 ("BoneH", "textures/BoneH.png"),
 ("BoneStabV", "textures/BoneStabV.png"),
 ("BoneStabH", "textures/BoneStabH.png"),
 ("BoneStabWarn", "textures/BoneStabWarn.png"),
 ("GasterBlast1", "textures/GasterBlast1.png"),
 ("GasterBlast3", "textures/GasterBlast3.png"),
 ("GasterBlastHit", "textures/GasterBlastHit.png"),
]
for name, rel in files:
    im = Image.open(os.path.join(base, rel))
    print("="*70)
    print(name, im.mode, im.size)
    im2 = im.convert("RGBA")
    px = list(im2.getdata())
    alphas = Counter(p[3] for p in px)
    print("alpha distribution (top):", alphas.most_common(6))
    opaque = [(p[0],p[1],p[2]) for p in px if p[3] > 0]
    cnt = Counter(opaque)
    print("unique opaque colors:", len(cnt), "top:", cnt.most_common(8))
    # bbox where alpha>0 and not black
    xs=[];ys=[]
    for y in range(im2.height):
        for x in range(im2.width):
            r,g,b,a=im2.getpixel((x,y))
            if a>0 and (r+g+b)>0:
                xs.append(x);ys.append(y)
    if xs: print("non-black bbox:", min(xs),min(ys),max(xs),max(ys))
