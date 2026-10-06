# -*- coding: utf-8 -*-
from PIL import Image, ImageDraw
import os
base=r"D:\stars\workspace\sans-fight\reference\sprites"
out=r"D:\stars\workspace\sans-fight\reference\sprites\fit\baked_preview.png"
def load(rel): return Image.open(os.path.join(base,rel)).convert("RGBA")
poses=[("default","animations/SansBody/HandRight/000.png",17,-24,False),
       ("up","animations/SansBody/HandUp/004.png",14,-2,False),
       ("down","animations/SansBody/HandDown/003.png",14,1,False),
       ("left","animations/SansBody/HandLeft/000.png",18,-24,True),
       ("right","animations/SansBody/HandRight/004.png",18,-24,False)]
head_def=load("animations/SansHead/Default/000.png")
head_blue=load("animations/SansHead/BlueEye/000.png")
tiles=[]; SC=4
def compose(body,head,hx,hy,mir):
    W,H=body.size
    if mir:
        body=body.transpose(Image.FLIP_LEFT_RIGHT); head=head.transpose(Image.FLIP_LEFT_RIGHT)
        hx=W-hx-head.width
    minx=min(0,hx); miny=min(0,hy); maxx=max(W,hx+head.width); maxy=max(H,hy+head.height)
    c=Image.new("RGBA",(maxx-minx,maxy-miny),(0,0,0,255))
    c.alpha_composite(body,(-minx,-miny)); c.alpha_composite(head,(hx-minx,hy-miny))
    return c
for name,rel,hx,hy,mir in poses:
    tiles.append((f"Sans/{name}",compose(load(rel),head_def,hx,hy,mir)))
tiles.append(("Sans/审判眼",compose(load("animations/SansBody/HandRight/000.png"),head_blue,17,-24,False)))
for f in ["Default/000","Fire/000","Fire/002","Fire/004"]:
    tiles.append((f"龙骨炮/{f}",load(f"animations/GasterBlaster/{f}.png")))
PAD=8; LAB=14
cw=max(im.width for _,im in tiles)*SC+PAD*2
ch=max(im.height for _,im in tiles)*SC+PAD*2+LAB
cols=5; rows=(len(tiles)+cols-1)//cols
canvas=Image.new("RGB",(cw*cols,ch*rows),(28,28,32)); d=ImageDraw.Draw(canvas)
for i,(name,im) in enumerate(tiles):
    r,cc=divmod(i,cols); ox=cc*cw+PAD; oy=r*ch+PAD+LAB
    d.text((cc*cw+PAD,r*ch+2),name,fill=(255,230,120))
    big=im.resize((im.width*SC,im.height*SC),Image.NEAREST); canvas.paste(big,(ox,oy),big)
canvas.save(out); print("saved",out,canvas.size)
