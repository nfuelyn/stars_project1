from PIL import Image
from collections import Counter
import os, sys

base = r"D:\stars\workspace\sans-fight\reference\sprites"

def load_effective(rel):
    im = Image.open(os.path.join(base, rel)).convert("RGBA")
    w,h = im.size
    px = im.load()
    has_alpha = any(px[x,y][3] < 255 for y in range(h) for x in range(w))
    grid = [[None]*w for _ in range(h)]
    if has_alpha:
        for y in range(h):
            for x in range(w):
                r,g,b,a = px[x,y]
                if a >= 128:
                    grid[y][x] = (r,g,b)
    else:
        # flood fill black from border = background
        bg = [[False]*w for _ in range(h)]
        stack=[]
        for x in range(w):
            for y in (0,h-1):
                if px[x,y][:3]==(0,0,0): stack.append((x,y))
        for y in range(h):
            for x in (0,w-1):
                if px[x,y][:3]==(0,0,0): stack.append((x,y))
        while stack:
            x,y=stack.pop()
            if x<0 or y<0 or x>=w or y>=h or bg[y][x]: continue
            if px[x,y][:3]!=(0,0,0): continue
            bg[y][x]=True
            stack += [(x+1,y),(x-1,y),(x,y+1),(x,y-1)]
        for y in range(h):
            for x in range(w):
                if not bg[y][x]:
                    grid[y][x]=px[x,y][:3]
    return grid

def rle_rects(grid, w, h):
    rects=[]
    for y in range(h):
        x=0
        while x<w:
            c=grid[y][x]
            if c is None: x+=1; continue
            x2=x
            while x2+1<w and grid[y][x2+1]==c: x2+=1
            rects.append([x,y,x2-x+1,1,c])
            x=x2+1
    # merge vertically identical x/w/color
    merged=[]
    for r in rects:
        x,y,rw,rh,c=r
        if merged:
            px_,py_,pw,ph,pc=merged[-1]
            if px_==x and pw==rw and pc==c and py_+ph==y:
                merged[-1][3]+=1
                continue
        merged.append(list(r))
    return merged

def greedy_rects(grid,w,h):
    rects=[]
    # work per color
    colors=set()
    for y in range(h):
        for x in range(w):
            if grid[y][x] is not None: colors.add(grid[y][x])
    for col in colors:
        # binary mask
        m=[[1 if grid[y][x]==col else 0 for x in range(w)] for y in range(h)]
        while True:
            # max rectangle in binary matrix (histogram)
            heights=[0]*w
            best=(0,0,0,0,0) # area,x,y,rw,rh
            for y in range(h):
                for x in range(w):
                    heights[x]=heights[x]+1 if m[y][x] else 0
                # largest rectangle in histogram
                stack=[]
                xs=list(range(w+1))
                for i in xs:
                    cur=heights[i] if i<w else 0
                    start=i
                    while stack and stack[-1][1]>cur:
                        sx,sh=stack.pop()
                        area=sh*(i-sx)
                        if area>best[0]:
                            best=(area,sx,y-sh+1,i-sx,sh)
                        start=sx
                    if not stack or stack[-1][1]<cur:
                        stack.append((start,cur))
            if best[0]==0: break
            area,x,y,rw,rh=best
            for yy in range(y,y+rh):
                for xx in range(x,x+rw):
                    m[yy][xx]=0
            rects.append([x,y,rw,rh,col])
    return rects

def render(grid,w,h,rects):
    im=Image.new("RGBA",(w,h),(0,0,0,0))
    px=im.load()
    for x,y,rw,rh,c in rects:
        for yy in range(y,y+rh):
            for xx in range(x,x+rw):
                px[xx,yy]=(c[0],c[1],c[2],255)
    return im

targets = [
 ("SansBody/HandDown/000","animations/SansBody/HandDown/000.png"),
 ("SansBody/HandUp/000","animations/SansBody/HandUp/000.png"),
 ("SansBody/HandLeft/000","animations/SansBody/HandLeft/000.png"),
 ("SansHead/Default/000","animations/SansHead/Default/000.png"),
 ("Blaster/Default/000","animations/GasterBlaster/Default/000.png"),
 ("Blaster/Fire/004","animations/GasterBlaster/Fire/004.png"),
 ("BoneV","textures/BoneV.png"),
 ("BoneH","textures/BoneH.png"),
 ("BoneStabV","textures/BoneStabV.png"),
 ("BoneStabH","textures/BoneStabH.png"),
]
outdir=r"D:\stars\_analysis\fit"
os.makedirs(outdir,exist_ok=True)
for name,rel in targets:
    grid=load_effective(rel)
    h=len(grid); w=len(grid[0])
    r1=rle_rects(grid,w,h)
    r2=greedy_rects(grid,w,h)
    print(f"{name:26s} {w}x{h}  RLE={len(r1):4d}  greedy={len(r2):4d}")
    for tag,rects in (("rle",r1),("greedy",r2)):
        im=render(grid,w,h,rects)
        im.resize((w*8,h*8),Image.NEAREST).save(os.path.join(outdir,f"{name.replace('/','_')}_{tag}.png"))
