import numpy as np, os, math
from PIL import Image, ImageDraw
from skimage.morphology import skeletonize, binary_erosion, binary_closing, disk
from scipy.ndimage import distance_transform_edt, binary_fill_holes
base=r"D:\stars\workspace\sans-fight\reference\sprites"
outd=r"D:\stars\_analysis\outline"; os.makedirs(outd,exist_ok=True)

def load_w(rel):
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
    return segs

def rdp(points,eps):
    if len(points)<3: return points
    p0=np.array(points[0],float); p1=np.array(points[-1],float); d=p1-p0; L=np.hypot(*d)
    dists=[np.hypot(*(np.array(p,float)-p0)) for p in points] if L==0 else [abs(d[0]*(p0[1]-p[1])-d[1]*(p0[0]-p[0]))/L for p in points]
    i=int(np.argmax(dists))
    if dists[i]>eps: return rdp(points[:i+1],eps)[:-1]+rdp(points[i:],eps)
    return [points[0],points[-1]]

def draw_rect(dr,cx,cy,L,t,ang,col=(255,255,255,255)):
    ux,uy=math.cos(ang),-math.sin(ang); vx,vy=math.sin(ang),math.cos(ang)
    pts=[(cx+ux*s+vx*q, cy+uy*s+vy*q) for s in (-L/2,L/2) for q in (-t/2,t/2)]
    dr.polygon(pts,fill=col)

for name,rel in [("HandDown","animations/SansBody/HandDown/000.png"),
                 ("HandUp","animations/SansBody/HandUp/000.png"),
                 ("HandLeft","animations/SansBody/HandLeft/000.png")]:
    W=load_w(rel); h,w=W.shape
    F=binary_fill_holes(B=W) if False else binary_fill_holes(W)
    F=binary_closing(F,disk(1))
    core=binary_erosion(F,disk(2))
    outline=F&~core
    sk=skeletonize(outline)
    dist=distance_transform_edt(outline)
    segs=trace(sk); rects=[]
    for path in segs:
        if len(path)<2: continue
        simp=rdp(path,2.0)
        for a,b in zip(simp[:-1],simp[1:]):
            y0,x0=a; y1,x1=b; L=math.hypot(x1-x0,y1-y0)
            if L<2: continue
            t=max(2.5,2*dist[int(round((y0+y1)/2)),int(round((x0+x1)/2))])
            ang=math.atan2(-(y1-y0),(x1-x0)); rects.append(((x0+x1)/2,(y0+y1)/2,L,t,ang))
    # render fill F white as target reference shape (silhouette)
    ref=F
    recon=Image.new("RGBA",(w,h),(0,0,0,0)); dr=ImageDraw.Draw(recon)
    for r in rects: draw_rect(dr,*r)
    rec=np.array(recon)[:,:,3]>0
    inter=(ref&rec).sum(); union=(ref|rec).sum()
    print(f"{name}: F={F.sum()} outline_px={outline.sum()} rects={len(rects)} IoU_fill={inter/union:.3f}")
    canvas=Image.new("RGBA",(w,h*2+8),(0,0,0,255))
    refim=Image.fromarray(np.dstack([ref*255]*3+[ref*255]).astype(np.uint8))
    canvas.alpha_composite(refim,(0,0)); canvas.alpha_composite(recon,(0,h+8))
    canvas.resize((w*6,(h*2+8)*6),Image.NEAREST).save(os.path.join(outd,name+".png"))
