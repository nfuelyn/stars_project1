from PIL import Image, ImageDraw
import os
base=r"D:\stars\workspace\sans-fight\reference\sprites"
out=r"D:\stars\_analysis\c2compose"; os.makedirs(out,exist_ok=True)
def load(rel): return Image.open(os.path.join(base,rel)).convert("RGBA")
head=load("animations/SansHead/Default/000.png")
# C2-derived: head hotspot (0.5,1) placed at the body's Head image point (x*W, y*H), y from top
cases=[("HandDown_003","animations/SansBody/HandDown/003.png",0.46875,0.442857),
       ("HandUp_004","animations/SansBody/HandUp/004.png",0.46875,0.4),
       ("HandLeft_000","animations/SansBody/HandLeft/000.png",0.354167,0.125),
       ("HandRight_000","animations/SansBody/HandRight/000.png",0.34375,0.125),
       ("HandRight_004","animations/SansBody/HandRight/004.png",0.354167,0.125)]
tiles=[]
for name,rel,px,py in cases:
    b=load(rel); W,H=b.size
    hx=round(px*W-0.5*head.width); hy=round(py*H-1.0*head.height)
    print(name,"head top-left",hx,hy)
    minx=min(0,hx); miny=min(0,hy); maxx=max(W,hx+head.width); maxy=max(H,hy+head.height)
    c=Image.new("RGBA",(maxx-minx,maxy-miny),(0,0,0,255))
    c.alpha_composite(b,(-minx,-miny)); c.alpha_composite(head,(hx-minx,hy-miny))
    tiles.append((name,c))
SC=5
cw=max(im.width for _,im in tiles)*SC+12; ch=max(im.height for _,im in tiles)*SC+30
canvas=Image.new("RGB",(cw*len(tiles),ch),(30,30,34)); d=ImageDraw.Draw(canvas)
for i,(name,im) in enumerate(tiles):
    ox=i*cw+6; oy=20
    d.text((ox,4),name,fill=(255,230,120))
    big=im.resize((im.width*SC,im.height*SC),Image.NEAREST); canvas.paste(big,(ox,oy),big)
canvas.save(os.path.join(out,"c2_compose.png")); print("saved",canvas.size)
