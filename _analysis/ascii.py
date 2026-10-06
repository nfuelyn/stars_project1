from PIL import Image
import os
base=r"D:\stars\workspace\sans-fight\reference\sprites"
for name,rel in [("Blaster/Default","animations/GasterBlaster/Default/000.png"),
                 ("Blaster/Fire004","animations/GasterBlaster/Fire/004.png"),
                 ("SansHead/Default","animations/SansHead/Default/000.png"),
                 ("SansTorso/Default","animations/SansTorso/Default/000.png"),
                 ("SansLegs/Standing","animations/SansLegs/Standing/000.png")]:
    im=Image.open(os.path.join(base,rel)).convert("RGBA"); w,h=im.size
    print("="*70); print(name,f"{w}x{h}")
    for y in range(h):
        line=""
        for x in range(w):
            r,g,b,a=im.getpixel((x,y))
            if a<128: line+="."
            elif (r+g+b)>300: line+="#"
            else: line+="o"
        print(line)
