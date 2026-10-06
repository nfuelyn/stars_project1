from PIL import Image, ImageDraw
import math, os
base=r"D:\stars\workspace\sans-fight\reference\sprites"
outd=r"D:\stars\_analysis\spec"
def poly_rect(cx,cy,w,h,rot=0):
    a=math.radians(rot); ux,uy=math.cos(a),-math.sin(a); vx,vy=math.sin(a),math.cos(a)
    return [(cx+ux*s+vx*q, cy+uy*s+vy*q) for s in (-w/2,w/2) for q in (-h/2,h/2)]
def rect(dr,cx,cy,w,h,col): dr.polygon(poly_rect(cx,cy,w,h),fill=col)

# current Lua model, local origin at sprite center (28.5,21.5), u=+x right
W,H=64,48; cx,cy=32,24
im=Image.new("RGBA",(W,H),(0,0,0,255)); dr=ImageDraw.Draw(im)
white=(255,255,255,255); dark=(16,22,31,255)
rect(dr,cx-10,cy,32,44,white)
rect(dr,cx+16,cy,34,22,white)
rect(dr,cx-6,cy+10,11,12,dark)
rect(dr,cx-6,cy-10,11,12,dark)
rect(dr,cx+22,cy,18,9,dark)
rect(dr,cx+23,cy,14,4,white)
im.save(os.path.join(outd,"blaster_current_model.png"))
canvas=Image.new("RGBA",(W*2+8,H),(0,0,0,255))
orig=Image.open(os.path.join(base,"animations/GasterBlaster/Default/000.png")).convert("RGBA")
canvas.alpha_composite(orig,(0,0)); canvas.alpha_composite(im,(W+8,0))
canvas.resize((canvas.width*8,canvas.height*8),Image.NEAREST).save(os.path.join(outd,"blaster_current_compare.png"))
print("ok")
