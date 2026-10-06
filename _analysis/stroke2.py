import numpy as np, os, math
from PIL import Image, ImageDraw
from skimage.morphology import skeletonize
from scipy.ndimage import distance_transform_edt
base=r"D:\stars\workspace\sans-fight\reference\sprites"
outd=r"D:\stars\_analysis\stroke"; os.makedirs(outd,exist_ok=True)

def load_mask(rel):
    im=Image.open(os.path.join(base,rel)).convert("RGBA"); w,h=im.size; px=im.load()
    has_alpha=any(px[x,y][3]<255 for y in range(h) for x in range(w))
    m=np.zeros((h,w),bool)
    for y in range(h):
        for x in range(w):
            r,g,b,a=px[x,y]
            if has_alpha:
                if a>=128 and (r+g+b)>300: m[y,x]=True
            else:
                if (r+g+b)>300: m[y,x]=True
    return m

def neighbors(y,x,h,w):
    for dy in (-1,0,1):
        for dx in (-1,0,1):
            if dy==0 and dx==0: continue
            yy,xx=y+dy,x+dx
            if 0<=yy<h and 0<=xx<w: yield yy,xx

def trace(skel):
    h,w=skel.shape; pts=set(map(tuple,np.argwhere(skel)))
    def deg(p):
        y,x=p; return sum(1 for q in neighbors(y,x,h,w) if q in pts)
    nodes={p for p in pts if deg(p)!=2}; visited=set(); segs=[]
    for s in nodes:
        for n in neighbors(s[0],s[1],h,w):
            if n not in pts or (s,n) in visited: continue
            path=[s,n]; visited.add((s,n)); visited.add((n,s)); prev,cur=s,n
            while cur not in nodes:
                nxt=[q for q in neighbors(cur[0],cur[1],h,w) if q in pts and q!=prev]
                if len(nxt)!=1: break
                nxt=nxt[0]
                if (cur,nxt) in visited: break
                visited.add((cur,nxt)); visited.add((nxt,cur)); path.append(nxt); prev,cur=cur,nxt
            segs.append(path)
    for s in list(pts):
        if s in nodes: continue
        for n in neighbors(s[0],s[1],h,w):
            if n not in pts or (s,n) in visited: continue
            path=[]; prev,cur=None,s
            while True:
                path.append(cur)
                nxt=[q for q in neighbors(cur[0],cur[1],h,w) if q in pts and q!=prev and (cur,q) not in visited]
                if not nxt: break
                nxt=nxt[0]; visited.add((cur,nxt)); visited.add((nxt,cur)); prev,cur=cur,nxt
                if cur==s: path.append(cur); break
            if len(path)>2: segs.append(path)
    return segs

def rdp(points,eps):
    if len(points)<3: return points
    p0=np.array(points[0],float); p1=np.array(points[-1],float); d=p1-p0; L=np.hypot(*d)
    dists=[np.hypot(*(np.array(p,float)-p0)) for p in points] if L==0 else [abs(d[0]*(p0[1]-p[1])-d[1]*(p0[0]-p[0]))/L for p in points]
    i=int(np.argmax(dists))
    if dists[i]>eps:
        return rdp(points[:i+1],eps)[:-1]+rdp(points[i:],eps)
    return [points[0],points[-1]]

def fit(rel,eps=1.2):
    m=load_mask(rel); h,w=m.shape; dist=distance_transform_edt(m); sk=skeletonize(m); segs=trace(sk)
    rects=[]
    for path in segs:
        if len(path)<2: continue
        simp=rdp(path,eps)
        for a,b in zip(simp[:-1],simp[1:]):
            y0,x0=a; y1,x1=b; L=math.hypot(x1-x0,y1-y0)
            if L<1.2: continue
            t=max(1.0,2*dist[int(round((y0+y1)/2)),int(round((x0+x1)/2))])
            ang=math.atan2(-(y1-y0),(x1-x0))
            rects.append(((x0+x1)/2,(y0+y1)/2,L+t,t,ang))
    return m,rects

def draw_rect(dr,cx,cy,L,t,ang,col=(255,255,255,255)):
    ux,uy=math.cos(ang),-math.sin(ang); vx,vy=math.sin(ang),math.cos(ang)
    pts=[]
    for s in (-L/2,L/2):
        for q in (-t/2,t/2):
            pts.append((cx+ux*s+vx*q, cy+uy*s+vy*q))
    dr.polygon(pts,fill=col)

for name,rel in [("SansBody_HandDown","animations/SansBody/HandDown/000.png"),
                 ("SansBody_HandUp","animations/SansBody/HandUp/000.png"),
                 ("SansBody_HandLeft","animations/SansBody/HandLeft/000.png")]:
    m,rects=fit(rel); h,w=m.shape
    orig=Image.open(os.path.join(base,rel)).convert("RGBA")
    canvas=Image.new("RGBA",(w*3+24,h),(0,0,0,255))
    canvas.alpha_composite(orig,(0,0))
    recon=Image.new("RGBA",(w,h),(0,0,0,255)); dr=ImageDraw.Draw(recon)
    for r in rects: draw_rect(dr,*r)
    canvas.alpha_composite(recon,(w+12,0))
    # overlay: original white in red, recon in green
    ov=Image.new("RGBA",(w,h),(0,0,0,255)); dr=ImageDraw.Draw(ov)
    src=np.array(orig.convert("RGB")).sum(2)>300
    for y in range(h):
        for x in range(w):
            if src[y,x]: dr.point((x,y),fill=(255,60,60,255))
    rec=np.zeros((h,w),bool); im2=np.array(recon.convert("RGB")).sum(2)>300; rec=im2
    for y in range(h):
        for x in range(w):
            if rec[y,x]:
                cur=ov.getpixel((x,y))
                if src[y,x]: dr.point((x,y),fill=(255,255,60,255))
                else: dr.point((x,y),fill=(60,255,60,255))
    canvas.alpha_composite(ov,(w*2+24,0))
    canvas.resize((canvas.width*5,canvas.height*5),Image.NEAREST).save(os.path.join(outd,name+"_compare.png"))
    inter=(src&rec).sum(); union=(src|rec).sum()
    print(f"{name}: rects={len(rects)} IoU={inter/union:.3f} cov={inter/src.sum():.3f} fp={(rec&~src).sum()}")
