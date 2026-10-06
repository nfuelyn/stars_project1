from PIL import Image, ImageDraw
import os
base=r"D:\stars\workspace\sans-fight\reference\sprites"
fd=r"D:\stars\_analysis\fit2"
items=[("SansBody_HandDown","animations/SansBody/HandDown/000.png"),
       ("SansBody_HandUp","animations/SansBody/HandUp/000.png"),
       ("SansBody_HandLeft","animations/SansBody/HandLeft/000.png"),
       ("SansHead_Default","animations/SansHead/Default/000.png"),
       ("Blaster_Default","animations/GasterBlaster/Default/000.png"),
       ("Blaster_Fire004","animations/GasterBlaster/Fire/004.png")]
SC=3; PAD=6; LAB=14
cols=4
maxw=max(Image.open(os.path.join(base,rel)).width for _,rel in items)
maxh=max(Image.open(os.path.join(base,rel)).height for _,rel in items)
cw=maxw*SC+PAD*2; ch=maxh*SC+PAD*2+LAB
canvas=Image.new("RGB",(cw*cols,ch*len(items)),(35,35,40)); d=ImageDraw.Draw(canvas)
for r,(name,rel) in enumerate(items):
    orig=Image.open(os.path.join(base,rel)).convert("RGBA")
    ims=[("orig",orig)]+[(f"B{B}",Image.open(os.path.join(fd,f"{name}_B{B}.png")).convert("RGBA")) for B in (2,3,4)]
    for c,(tag,im) in enumerate(ims):
        ox=c*cw+PAD; oy=r*ch+PAD+LAB
        # checker
        for yy in range(0,orig.height*SC,12):
            for xx in range(0,orig.width*SC,12):
                if ((xx//12)+(yy//12))%2==0:
                    d.rectangle([ox+xx,oy+yy,ox+xx+11,oy+yy+11],fill=(55,55,62))
        if im.width!=orig.width*SC:
            im=im.resize((orig.width*SC,orig.height*SC),Image.NEAREST)
        canvas.paste(im,(ox,oy),im)
        d.text((c*cw+PAD,r*ch+2),f"{name} {tag}",fill=(255,230,150))
out=r"D:\stars\_analysis\fit2_compare.png"
canvas.save(out); print(out,canvas.size)
