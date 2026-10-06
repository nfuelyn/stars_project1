from PIL import Image
from collections import Counter
import os
base = r"D:\stars\workspace\sans-fight\reference\sprites"
outdir=r"D:\stars\_analysis\fit2"
os.makedirs(outdir,exist_ok=True)

def load_grid(rel):
    im = Image.open(os.path.join(base, rel)).convert("RGBA")
    w,h = im.size; px=im.load()
    has_alpha = any(px[x,y][3] < 255 for y in range(h) for x in range(w))
    grid=[[None]*w for _ in range(h)]
    if has_alpha:
        for y in range(h):
            for x in range(w):
                r,g,b,a=px[x,y]
                if a>=128: grid[y][x]=(r,g,b)
    else:
        bg=[[False]*w for _ in range(h)]; stack=[]
        for x in range(w):
            if px[x,0][:3]==(0,0,0): stack.append((x,0))
            if px[x,h-1][:3]==(0,0,0): stack.append((x,h-1))
        for y in range(h):
            if px[0,y][:3]==(0,0,0): stack.append((0,y))
            if px[w-1,y][:3]==(0,0,0): stack.append((w-1,y))
        while stack:
            x,y=stack.pop()
            if x<0 or y<0 or x>=w or y>=h or bg[y][x] or px[x,y][:3]!=(0,0,0): continue
            bg[y][x]=True
            stack += [(x+1,y),(x-1,y),(x,y+1),(x,y-1)]
        for y in range(h):
            for x in range(w):
                if not bg[y][x]: grid[y][x]=px[x,y][:3]
    return grid

def blockfit(grid,w,h,B,thresh=0.45):
    bw=(w+B-1)//B; bh=(h+B-1)//B
    small=[[None]*bw for _ in range(bh)]
    for by in range(bh):
        for bx in range(bw):
            cnt=Counter(); tot=0
            for y in range(by*B,min(h,(by+1)*B)):
                for x in range(bx*B,min(w,(bx+1)*B)):
                    tot+=1
                    if grid[y][x] is not None: cnt[grid[y][x]]+=1
            if cnt:
                col,n=cnt.most_common(1)[0]
                if n>=thresh*tot: small[by][bx]=col
    # rle merge
    rects=[]
    for y in range(bh):
        x=0
        while x<bw:
            c=small[y][x]
            if c is None: x+=1; continue
            x2=x
            while x2+1<bw and small[y][x2+1]==c: x2+=1
            rects.append([x*B,y*B,(x2-x+1)*B,B,c])
            x=x2+1
    merged=[]
    for r in rects:
        x,y,rw,rh,c=r
        if merged:
            px_,py_,pw,ph,pc=merged[-1]
            if px_==x and pw==rw and pc==c and py_+ph==y:
                merged[-1][3]+=rh; continue
        merged.append(list(r))
    return small,merged

def render(small,w,h,B,rects):
    im=Image.new("RGBA",(w,h),(0,0,0,0)); pix=im.load()
    for x,y,rw,rh,c in rects:
        for yy in range(y,min(h,y+rh)):
            for xx in range(x,min(w,x+rw)):
                pix[xx,yy]=(c[0],c[1],c[2],255)
    return im

targets=[("SansBody/HandDown","animations/SansBody/HandDown/000.png"),
         ("SansBody/HandUp","animations/SansBody/HandUp/000.png"),
         ("SansBody/HandLeft","animations/SansBody/HandLeft/000.png"),
         ("SansHead/Default","animations/SansHead/Default/000.png"),
         ("Blaster/Default","animations/GasterBlaster/Default/000.png"),
         ("Blaster/Fire004","animations/GasterBlaster/Fire/004.png")]
for name,rel in targets:
    grid=load_grid(rel); h=len(grid); w=len(grid[0])
    line=f"{name:22s} {w}x{h} "
    for B in (1,2,3,4):
        sm,rects=blockfit(grid,w,h,B)
        line+=f"B{B}={len(rects):3d} "
        if B in (2,3,4):
            im=render(sm,w,h,B,rects)
            im.resize((w*6,h*6),Image.NEAREST).save(os.path.join(outdir,f"{name.replace('/','_')}_B{B}.png"))
    print(line)
