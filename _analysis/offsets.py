from PIL import Image
import numpy as np, os
base=r"D:\stars\workspace\sans-fight\reference\sprites"
def wmask(rel):
    im=Image.open(os.path.join(base,rel)).convert("RGBA"); w,h=im.size; px=im.load()
    m=np.zeros((h,w),bool)
    for y in range(h):
        for x in range(w):
            r,g,b,a=px[x,y]
            if a>=128 and r+g+b>300: m[y,x]=True
    return m
def best(body,head):
    H,W=body.shape; hh,hw=head.shape; b=None
    for dy in range(0,H-hh+1):
        for dx in range(0,W-hw+1):
            reg=body[dy:dy+hh,dx:dx+hw]
            score=(reg&head).sum()-0.5*((~reg)&head).sum()
            if b is None or score>b[0]: b=(score,dx,dy)
    return b[1],b[2]
head=wmask("animations/SansHead/Default/000.png")
for name,rel in [("down","animations/SansBody/HandDown/003.png"),
                 ("up","animations/SansBody/HandUp/004.png"),
                 ("left","animations/SansBody/HandLeft/000.png"),
                 ("default","animations/SansBody/HandRight/000.png"),
                 ("right","animations/SansBody/HandRight/004.png")]:
    b=wmask(rel); dx,dy=best(b,head)
    print(name,rel,"size",b.shape[::-1],"head offset",dx,dy)
