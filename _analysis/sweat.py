from PIL import Image
import numpy as np, os
base=r"D:\stars\workspace\sans-fight\reference\sprites"
def mask(rel):
    im=Image.open(os.path.join(base,rel)).convert("RGBA"); w,h=im.size; px=im.load()
    m=np.zeros((h,w),bool)
    for y in range(h):
        for x in range(w):
            r,g,b,a=px[x,y]
            if a>=128 and r+g+b>300: m[y,x]=True
    return m
def show(m):
    for row in m:
        print("".join("#" if v else "." for v in row))
for n in ["Sweat1","Sweat2","Sweat3"]:
    m=mask(f"animations/SansSweat/{n}/000.png")
    print("="*20,n,m.shape,m.sum()); show(m)
