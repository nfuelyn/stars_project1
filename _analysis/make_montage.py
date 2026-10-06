from PIL import Image, ImageDraw
import os

base = r"D:\stars\workspace\sans-fight\reference\sprites"
items = []
for anim in ["HandDown","HandLeft","HandRight","HandUp"]:
    for f in sorted(os.listdir(os.path.join(base,"animations","SansBody",anim))):
        items.append((f"SansBody/{anim}/{f[:-4]}", os.path.join(base,"animations","SansBody",anim,f)))
for anim in ["Default","BlueEye","ClosedEyes","LookLeft","NoEyes","Tired1","Tired2","Wink"]:
    items.append((f"Head/{anim}", os.path.join(base,"animations","SansHead",anim,"000.png")))
for anim in ["Default","Shrug"]:
    items.append((f"Torso/{anim}", os.path.join(base,"animations","SansTorso",anim,"000.png")))
for anim in ["Sitting","Standing"]:
    items.append((f"Legs/{anim}", os.path.join(base,"animations","SansLegs",anim,"000.png")))
items.append(("Blaster/Default", os.path.join(base,"animations","GasterBlaster","Default","000.png")))
for f in sorted(os.listdir(os.path.join(base,"animations","GasterBlaster","Fire"))):
    items.append((f"Blaster/Fire/{f[:-4]}", os.path.join(base,"animations","GasterBlaster","Fire",f)))
for t in ["BoneV","BoneH","BoneStabV","BoneStabH","BoneStabWarn","GasterBlast1","GasterBlast2","GasterBlast3","GasterBlastHit"]:
    items.append((f"tex/{t}", os.path.join(base,"textures",t+".png")))
items.append(("MenuBoneLeft", os.path.join(base,"animations","MenuBoneLeft","Default","000.png")))
items.append(("MenuBoneBottom", os.path.join(base,"animations","MenuBoneBottom","Default","000.png")))

SC = 5
PAD = 8
LABEL_H = 16
cols = 8
cell_w = []
cell_h = []
imgs = []
for name, path in items:
    im = Image.open(path).convert("RGBA")
    imgs.append((name, im))
    cell_w.append(im.width*SC)
    cell_h.append(im.height*SC)

cell_w_max = max(cell_w) + PAD*2
cell_h_max = max(cell_h) + PAD*2 + LABEL_H
rows = (len(items)+cols-1)//cols
W = cell_w_max*cols
H = cell_h_max*rows
canvas = Image.new("RGB",(W,H),(40,40,46))
d = ImageDraw.Draw(canvas)
# checkerboard background
for y in range(0,H,16):
    for x in range(0,W,16):
        if ((x//16)+(y//16))%2==0:
            d.rectangle([x,y,x+15,y+15], fill=(55,55,62))
for i,(name,im) in enumerate(imgs):
    r,c = divmod(i,cols)
    ox = c*cell_w_max + PAD
    oy = r*cell_h_max + PAD + LABEL_H
    big = im.resize((im.width*SC, im.height*SC), Image.NEAREST)
    # paste with alpha
    canvas.paste(big,(ox,oy),big)
    d.text((c*cell_w_max+PAD, r*cell_h_max+2), name, fill=(255,230,150))
out = r"D:\stars\_analysis\sprite_montage.png"
os.makedirs(os.path.dirname(out), exist_ok=True)
canvas.save(out)
print(out, canvas.size, len(items))
