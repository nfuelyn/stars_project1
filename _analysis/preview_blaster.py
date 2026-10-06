from PIL import Image, ImageDraw
import math, os
base=r"D:\stars\workspace\sans-fight\reference\sprites"
outd=r"D:\stars\_analysis\spec"; os.makedirs(outd,exist_ok=True)

def poly_rect(cx,cy,w,h,rot=0):
    a=math.radians(rot); ux,uy=math.cos(a),-math.sin(a); vx,vy=math.sin(a),math.cos(a)
    return [(cx+ux*s+vx*q, cy+uy*s+vy*q) for s in (-w/2,w/2) for q in (-h/2,h/2)]
def draw_prim(dr,kind,cx,cy,w,h,rot=0,color=(255,255,255,255)):
    if kind=='rect': dr.polygon(poly_rect(cx,cy,w,h,rot),fill=color)
    elif kind=='ellipse': dr.ellipse([cx-w/2,cy-h/2,cx+w/2,cy+h/2],fill=color)
    elif kind=='triangle':
        # isoceles triangle pointing +u
        pts=[( w/2,0),(-w/2,-h/2),(-w/2,h/2)]
        a=math.radians(rot); ux,uy=math.cos(a),-math.sin(a); vx,vy=math.sin(a),math.cos(a)
        dr.polygon([(cx+ux*x+vx*y, cy+uy*x+vy*y) for x,y in pts],fill=color)

def render_blaster(path, fire=0):
    W,H=57,44; im=Image.new("RGBA",(W,H),(0,0,0,0)); dr=ImageDraw.Draw(im)
    white=(255,255,255,255); black=(10,14,20,255)
    # cranium ellipse
    draw_prim(dr,'ellipse', 20,22, 38,42,0,white)
    # snout
    draw_prim(dr,'rect', 42,22, 30,20,0,white)
    # black slot between cranium and snout
    draw_prim(dr,'rect', 11.5,22, 4,18,0,black)
    # mouth band
    draw_prim(dr,'rect', 34,22, 38,5,0,black)
    # eye sockets
    draw_prim(dr,'ellipse', 26,12.5, 13,9,0,black)
    draw_prim(dr,'ellipse', 26,31.5, 13,9,0,black)
    # prongs (teeth/horns)
    draw_prim(dr,'rect', 35.5,5.5, 6,9,0,white)
    draw_prim(dr,'rect', 35.5,38.5, 6,9,0,white)
    # teeth row (white) in mouth band
    for tx in (24,30,36,42):
        draw_prim(dr,'rect', tx,22, 4,4,0,white)
    return im

orig=Image.open(os.path.join(base,"animations/GasterBlaster/Default/000.png")).convert("RGBA")
fit=render_blaster(orig)
canvas=Image.new("RGBA",(57*2+8,44),(0,0,0,255))
canvas.alpha_composite(orig,(0,0)); canvas.alpha_composite(fit,(65,0))
canvas.resize((canvas.width*8,canvas.height*8),Image.NEAREST).save(os.path.join(outd,"blaster_spec.png"))
print("saved")
