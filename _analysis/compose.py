from PIL import Image
import numpy as np, os
base=r"D:\stars\workspace\sans-fight\reference\sprites"
out=r"D:\stars\_analysis\compose"; os.makedirs(out,exist_ok=True)
def load(rel):
    return Image.open(os.path.join(base,rel)).convert("RGBA")
def wmask(im):
    a=np.array(im); return (a[:,:,3]>=128)&(a[:,:,:3].sum(2)>300)
def best_offset(body,head):
    H,W=body.shape; hh,hw=head.shape; b=None
    for dy in range(0,H-hh+1):
        for dx in range(0,W-hw+1):
            reg=body[dy:dy+hh,dx:dx+hw]
            score=(reg&head).sum()-0.5*((~reg)&head).sum()
            if b is None or score>b[0]: b=(score,dx,dy)
    return b[1],b[2]
poses=["HandDown","HandUp","HandLeft","HandRight"]
res={}
for pose in poses:
    bimg=load(f"animations/SansBody/{pose}/000.png"); himg=load("animations/SansHead/Default/000.png")
    bm=wmask(bimg); hm=wmask(himg)
    dx,dy=best_offset(bm,hm); res[pose]=(dx,dy)
    print(pose,"head offset",dx,dy)
    canvas=Image.new("RGBA",bimg.size,(0,0,0,255)); canvas.alpha_composite(bimg,(0,0)); canvas.alpha_composite(himg,(dx,dy))
    canvas.resize((bimg.width*8,bimg.height*8),Image.NEAREST).save(os.path.join(out,pose+"_compose.png"))
# sweat visual
s=load("animations/SansSweat/Sweat1/000.png")
s.resize((s.width*10,s.height*10),Image.NEAREST).save(os.path.join(out,"sweat1.png"))
print("sweat size",s.size)
