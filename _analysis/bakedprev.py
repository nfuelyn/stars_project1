# -*- coding: utf-8 -*-
from PIL import Image, ImageDraw
import os
base=r"D:\stars\workspace\sans-fight\reference\sprites"
out=r"D:\stars\workspace\sans-fight\reference\sprites\fit\baked_preview.png"
def load(rel): return Image.open(os.path.join(base,rel)).convert("RGBA")
poses=[("default","animations/SansBody/HandRight/000.png",15,6),
       ("up","animations/SansBody/HandUp/004.png",12,28),
       ("down","animations/SansBody/HandDown/003.png",11,31),
       ("left","animations/SansBody/HandLeft/000.png",15,6),
       ("right","animations/SansBody/HandRight/004.png",15,6)]
head_def=load("animations/SansHead/Default/000.png")
head_blue=load("animations/SansHead/BlueEye/000.png")
tiles=[]
SC=4
for name,rel,hx,hy in poses:
    body=load(rel)
    c=Image.new("RGBA",body.size,(0,0,0,255)); c.alpha_composite(body,(0,0)); c.alpha_composite(head_def,(hx,hy))
    tiles.append((f"Sans/{name}",c))
c=Image.new("RGBA",tiles[0][1].size,(0,0,0,255))
c.alpha_composite(load("animations/SansBody/HandRight/000.png"),(0,0)); c.alpha_composite(head_blue,(15,6))
tiles.append(("Sans/审判眼",c))
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
    big=im.resize((im.width*SC,im.height*SC),Image.NEAREST)
    canvas.paste(big,(ox,oy),big)
canvas.save(out); print(out,canvas.size)
