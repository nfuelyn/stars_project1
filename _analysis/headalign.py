from PIL import Image
import numpy as np, os
from scipy.signal import fftconvolve
base=r"D:\stars\workspace\sans-fight\reference\sprites"
def wmask(rel):
    im=Image.open(os.path.join(base,rel)).convert("RGBA"); w,h=im.size; px=im.load()
    m=np.zeros((h,w),bool)
    for y in range(h):
        for x in range(w):
            r,g,b,a=px[x,y]
            if a>=128 and r+g+b>300: m[y,x]=True
    return m
body=wmask("animations/SansBody/HandDown/000.png")
head=wmask("animations/SansHead/Default/000.png")
H,W=body.shape; hh,hw=head.shape
best=[]
for dy in range(0,H-hh+1):
    for dx in range(0,W-hw+1):
        reg=body[dy:dy+hh,dx:dx+hw]
        score=(reg&head).sum() - 0.5*((~reg)&head).sum()
        best.append((score,dx,dy,(reg&head).sum()))
best.sort(reverse=True)
print("top alignments (score,dx,dy,overlap):")
for b in best[:10]: print(b)
