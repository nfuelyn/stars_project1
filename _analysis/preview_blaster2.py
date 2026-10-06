from PIL import Image, ImageDraw
import math, os
base=r"D:\stars\workspace\sans-fight\reference\sprites"
outd=r"D:\stars\_analysis\spec"; os.makedirs(outd,exist_ok=True)
def poly(cx,cy,w,h,rot=0):
    a=math.radians(rot); ux,uy=math.cos(a),-math.sin(a); vx,vy=math.sin(a),math.cos(a)
    return [(cx+ux*s+vx*q,cy+uy*s+vy*q) for s in (-w/2,w/2) for q in (-h/2,h/2)]
def P(dr,k,x,y,w,h,col,rot=0):
    if k=='rect': dr.polygon(poly(x,y,w,h,rot),fill=col)
    elif k=='ellipse': dr.ellipse([x-w/2,y-h/2,x+w/2,y+h/2],fill=col)
    elif k=='ring':
        dr.ellipse([x-w/2,y-h/2,x+w/2,y+h/2],outline=col,width=max(1,int(h/4)))
def blaster():
    W,H=57,44; im=Image.new("RGBA",(W,H),(0,0,0,0)); dr=ImageDraw.Draw(im)
    Wc=(255,255,255,255); K=(12,16,22,255)
    # cranium: big rounded mass left
    P(dr,'ellipse',18,22,37,42,Wc)
    # snout
    P(dr,'rect',40,22,32,19,Wc)
    # black slot between
    P(dr,'rect',10.5,22,3,20,K)
    # mouth band
    P(dr,'rect',30,22,36,4,K)
    # eye sockets (black ovals) + white ring inside
    for cy in (12.5,31.5):
        P(dr,'ellipse',28,cy,11,9,K)
        P(dr,'ellipse',28,cy,4,4,Wc)
        P(dr,'ellipse',28,cy,2,2,K)
    # prongs top/bottom right
    P(dr,'rect',35,4.5,5,8,Wc)
    P(dr,'rect',35,39.5,5,8,Wc)
    # teeth
    for tx in (23,30,37,44):
        P(dr,'rect',tx,22,4,4,Wc)
    return im
orig=Image.open(os.path.join(base,"animations/GasterBlaster/Default/000.png")).convert("RGBA")
fit=blaster()
canvas=Image.new("RGBA",(57*3+16,44),(0,0,0,255))
canvas.alpha_composite(orig,(0,0)); canvas.alpha_composite(fit,(65,0))
# overlay original white=red, fit green/yellow
ov=Image.new("RGBA",(57,44),(0,0,0,255)); dr=ImageDraw.Draw(ov)
src=orig; fitp=fit
for y in range(44):
    for x in range(57):
        a=src.getpixel((x,y))[3]>128 and sum(src.getpixel((x,y))[:3])>300
        b=fitp.getpixel((x,y))[3]>128 and sum(fitp.getpixel((x,y))[:3])>300
        if a and b: dr.point((x,y),fill=(255,255,0,255))
        elif a: dr.point((x,y),fill=(255,60,60,255))
        elif b: dr.point((x,y),fill=(60,255,60,255))
canvas.alpha_composite(ov,(130,0))
canvas.resize((canvas.width*8,canvas.height*8),Image.NEAREST).save(os.path.join(outd,"blaster_spec2.png"))
print("ok")
