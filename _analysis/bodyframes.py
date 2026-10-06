from PIL import Image, ImageDraw
import os
base=r"D:\stars\workspace\sans-fight\reference\sprites\animations\SansBody"
out=r"D:\stars\_analysis\body_frames.png"
poses=["HandDown","HandLeft","HandRight","HandUp"]
SC=4; PAD=6; LAB=14
cells=[]
for p in poses:
    for f in sorted(os.listdir(os.path.join(base,p))):
        im=Image.open(os.path.join(base,p,f)).convert("RGBA")
        cells.append((f"{p}/{f[:-4]}",im))
cols=5
cw=max(im.width for _,im in cells)*SC+PAD*2
ch=max(im.height for _,im in cells)*SC+PAD*2+LAB
rows=(len(cells)+cols-1)//cols
canvas=Image.new("RGB",(cw*cols,ch*rows),(30,30,34)); d=ImageDraw.Draw(canvas)
for i,(name,im) in enumerate(cells):
    r,c=divmod(i,cols); ox=c*cw+PAD; oy=r*ch+PAD+LAB
    d.text((c*cw+PAD+2,r*ch+2),name,fill=(255,230,120))
    big=im.resize((im.width*SC,im.height*SC),Image.NEAREST)
    canvas.paste(big,(ox,oy),big)
canvas.save(out); print(out,canvas.size)
