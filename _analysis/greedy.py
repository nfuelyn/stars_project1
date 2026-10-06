import numpy as np, os
from PIL import Image
from scipy.ndimage import binary_fill_holes
base=r"D:\stars\workspace\sans-fight\reference\sprites"

def masks(rel):
    im=Image.open(os.path.join(base,rel)).convert("RGBA"); w,h=im.size; px=im.load()
    W=np.zeros((h,w),bool); B=np.zeros((h,w),bool); A=np.zeros((h,w),bool)
    for y in range(h):
        for x in range(w):
            r,g,b,a=px[x,y]
            if a>=128:
                A[y,x]=True
                if r+g+b>300: W[y,x]=True
                else: B[y,x]=True
    return W,B,A

def largest_rect(mask):
    h,w=mask.shape; heights=np.zeros(w,int); best=(0,0,0,0,0)
    for y in range(h):
        heights = np.where(mask[y], heights+1, 0)
        stack=[]  # (start, height)
        for i in range(w+1):
            cur = heights[i] if i<w else 0
            start=i
            while stack and stack[-1][1] > cur:
                s,hh=stack.pop()
                area=hh*(i-s)
                if area>best[0]: best=(area,s,y-hh+1,i-s,hh)
                start=s
            if not stack or stack[-1][1]<cur:
                stack.append((start,cur))
    return best

def greedy(mask, maxn=500):
    m=mask.copy(); rects=[]
    while m.any() and len(rects)<maxn:
        area,x,y,rw,rh=largest_rect(m)
        if area==0: break
        m[y:y+rh,x:x+rw]=False
        rects.append((x,y,rw,rh))
    return rects

for name,rel in [("Blaster/Default","animations/GasterBlaster/Default/000.png"),
                 ("Blaster/Fire004","animations/GasterBlaster/Fire/004.png"),
                 ("SansHead/Default","animations/SansHead/Default/000.png"),
                 ("SansTorso/Default","animations/SansTorso/Default/000.png"),
                 ("SansLegs/Standing","animations/SansLegs/Standing/000.png")]:
    W,B,A=masks(rel)
    Wf=binary_fill_holes(W)
    rW=greedy(W); rWf=greedy(Wf); rB=greedy(B)
    print(f"{name:20s} W={W.sum():4d} B={B.sum():4d}  rects(W)={len(rW):3d}  rects(fillW)={len(rWf):3d}  rects(B)={len(rB):3d}")
