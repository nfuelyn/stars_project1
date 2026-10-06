from PIL import Image, ImageDraw
import os
base=r"D:\stars\workspace\sans-fight\reference\sprites"
out=r"D:\stars\workspace\sans-fight\reference\sprites\fit\bone_param_preview.png"
def render(w,h,vertical=True):
    im=Image.new("RGBA",(w,h),(0,0,0,0)); dr=ImageDraw.Draw(im)
    k=min(w,h)*0.6
    if vertical:
        stemW=k; sx=(w-stemW)/2; sy=k/3; sh=h-2*k/3
        dr.rectangle([sx,sy,sx+stemW-1,sy+sh-1],fill=(255,255,255,255))
        for cx,cy in [(0,0),(w-k,0),(0,h-k),(w-k,h-k)]:
            dr.ellipse([cx,cy,cx+k-1,cy+k-1],fill=(255,255,255,255))
    else:
        stemH=k; sy=(h-stemH)/2; sx=k/3; sw=w-2*k/3
        dr.rectangle([sx,sy,sx+sw-1,sy+stemH-1],fill=(255,255,255,255))
        for cx,cy in [(0,0),(w-k,0),(0,h-k),(w-k,h-k)]:
            dr.ellipse([cx,cy,cx+k-1,cy+k-1],fill=(255,255,255,255))
    return im
pairs=[("bone_BoneV",10,24,True),("bone_BoneH",24,10,False),("bone_BoneStabV",12,24,True),("bone_BoneStabH",24,12,False)]
SC=10; tiles=[]
for name,w,h,vert in pairs:
    orig=Image.open(os.path.join(base,"textures",name.split("_",1)[1]+".png")).convert("RGBA")
    fit=render(w,h,vert)
    canvas=Image.new("RGBA",(w*3+16,max(h,24)),(0,0,0,255))
    canvas.alpha_composite(orig,(0,0)); canvas.alpha_composite(fit,(w+8,0))
    tiles.append(canvas.resize((canvas.width*SC,canvas.height*SC),Image.NEAREST))
W=max(t.width for t in tiles); H=sum(t.height+10 for t in tiles)
outim=Image.new("RGBA",(W,H),(25,25,30,255)); y=0
for t in tiles: outim.alpha_composite(t,(0,y)); y+=t.height+10
outim.save(out); print(out, outim.size)
