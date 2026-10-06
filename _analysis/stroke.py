import numpy as np, os, math
from PIL import Image
from skimage.morphology import skeletonize
from scipy.ndimage import distance_transform_edt
base=r"D:\stars\workspace\sans-fight\reference\sprites"
outd=r"D:\stars\_analysis\stroke"; os.makedirs(outd,exist_ok=True)

def load_mask(rel):
    im=Image.open(os.path.join(base,rel)).convert("RGBA"); w,h=im.size; px=im.load()
    has_alpha=any(px[x,y][3]<255 for y in range(h) for x in range(w))
    m=np.zeros((h,w),bool)
    if has_alpha:
        for y in range(h):
            for x in range(w):
                r,g,b,a=px[x,y]
                if a>=128 and (r+g+b)>300: m[y,x]=True
    else:
        # black bg = transparent, white = mask
        for y in range(h):
            for x in range(w):
                r,g,b,a=px[x,y]
                if (r+g+b)>300: m[y,x]=True
    return m

def neighbors(y,x,h,w):
    for dy in (-1,0,1):
        for dx in (-1,0,1):
            if dy==0 and dx==0: continue
            yy,xx=y+dy,x+dx
            if 0<=yy<h and 0<=xx<w: yield yy,xx

def trace(skel):
    h,w=skel.shape
    pts=set(map(tuple,np.argwhere(skel)))
    def deg(p):
        y,x=p; return sum(1 for q in neighbors(y,x,h,w) if q in pts)
    nodes={p for p in pts if deg(p)!=2}
    visited=set(); segs=[]
    # start from nodes
    for s in nodes:
        for n in neighbors(s[0],s[1],h,w):
            if n not in pts: continue
            e=(s,n)
            if e in visited: continue
            path=[s,n]; visited.add(e); visited.add((n,s)); prev,cur=s,n
            while cur not in nodes:
                nxt=[q for q in neighbors(cur[0],cur[1],h,w) if q in pts and q!=prev]
                if len(nxt)!=1: break
                nxt=nxt[0]; 
                e=(cur,nxt)
                if e in visited: break
                visited.add(e); visited.add((nxt,cur)); path.append(nxt); prev,cur=cur,nxt
            segs.append(path)
    # isolate loops (all deg 2) - walk unvisited
    for s in list(pts):
        if s in nodes: continue
        for n in neighbors(s[0],s[1],h,w):
            if n not in pts: continue
            if (s,n) in visited: continue
            path=[]; prev,cur=None,s
            while True:
                path.append(cur)
                nxt=[q for q in neighbors(cur[0],cur[1],h,w) if q in pts and q!=prev]
                if not nxt: break
                nxt=[q for q in nxt if (cur,q) not in visited]
                if not nxt: break
                nxt=nxt[0]; visited.add((cur,nxt)); visited.add((nxt,cur)); prev,cur=cur,nxt
                if cur==s: path.append(cur); break
            if len(path)>2: segs.append(path)
    return segs

def rdp(points, eps):
    if len(points)<3: return points
    p0=np.array(points[0],float); p1=np.array(points[-1],float)
    d=p1-p0; L=np.hypot(*d)
    if L==0: dists=[np.hypot(*(np.array(p,float)-p0)) for p in points]
    else: dists=[abs(np.cross(d,np.array(p,float)-p0))/L for p in points]
    i=int(np.argmax(dists))
    if dists[i]>eps:
        a=rdp(points[:i+1],eps); b=rdp(points[i:],eps)
        return a[:-1]+b
    return [points[0],points[-1]]

def fit(rel, eps=1.2, thick_scale=1.0):
    m=load_mask(rel); h,w=m.shape
    dist=distance_transform_edt(m)
    sk=skeletonize(m)
    segs=trace(sk)
    rects=[]
    for path in segs:
        if len(path)<2: continue
        simp=rdp(path,eps)
        for a,b in zip(simp[:-1],simp[1:]):
            y0,x0=a; y1,x1=b
            L=math.hypot(x1-x0,y1-y0)
            if L<1.2: continue
            t=max(1.0, 2*dist[int(round((y0+y1)/2)),int(round((x0+x1)/2))]*thick_scale)
            ang=math.degrees(math.atan2(-(y1-y0),(x1-x0)))  # image y down -> math y up
            cx=(x0+x1)/2; cy=(y0+y1)/2
            rects.append((cx,cy,L+t,t,ang))
    return m,rects

def render(m,rects,path):
    h,w=m.shape
    im=Image.fromarray((m*255).astype(np.uint8)).convert("RGBA")
    bg=Image.new("RGBA",(w,h),(0,0,0,255)); bg.alpha_composite(Image.fromarray(np.dstack([m*255]*3+[m*255]).astype(np.uint8)))
    return bg

for name,rel in [("SansBody_HandDown","animations/SansBody/HandDown/000.png"),
                 ("SansBody_HandUp","animations/SansBody/HandUp/000.png"),
                 ("SansBody_HandLeft","animations/SansBody/HandLeft/000.png")]:
    m,rects=fit(rel)
    print(name, m.sum(), "rects:",len(rects))
