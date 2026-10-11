-- CodeArt: 几何配方生成像素矩形；不读取 PNG、SVG 或外部纹理。
-- 接口 {w,h,rects={{x,y,w,h,c},...}}；Y 向下，颜色 0xAARRGGBB。
-- 自包含，可直接由 tools/build.py 打包；纯色矩形仍使用平台的预设图元。
local M = {}
local WHITE,BLACK,RED,BLUE,ORANGE = 0xFFFFFFFF,0xFF000000,0xFFFF2B2B,0xFF63B0FF,0xFFFF7A18
local CYAN,GREEN,YELLOW,PURPLE = 0xFF00D9FF,0xFF00FF00,0xFFFFD200,0xFF9B5CFF
local function clamp(v,l,h) return math.max(l,math.min(h,v)) end
local function alpha(c,a) return (math.floor(((c>>24)&255)*clamp(a,0,1)+.5)<<24)|(c&0xFFFFFF) end
local function spec(w,h) return {w=w,h=h,rects={}} end
local function rect(s,x,y,w,h,c)
  if w>0 and h>0 and ((c>>24)&255)>0 then s.rects[#s.rects+1]={x=x,y=y,w=w,h=h,c=c} end
end
local function append(s,child,x,y,sx,sy)
  sx,sy=sx or 1,sy or sx or 1
  for _,r in ipairs(child.rects) do rect(s,x+r.x*sx,y+r.y*sy,r.w*sx,r.h*sy,r.c) end
end
-- 配方加载时使用的小画布；战斗帧不逐像素扫描。
local function canvas(w,h) return {w=w,h=h,pixels={}} end
local function fill(p,x,y,w,h,c)
  for yy=math.max(0,math.floor(y)),math.min(p.h-1,math.ceil(y+h)-1) do
    for xx=math.max(0,math.floor(x)),math.min(p.w-1,math.ceil(x+w)-1) do p.pixels[yy*p.w+xx+1]=c end
  end
end
local function polygon(p,points,c)
  for y=0,p.h-1 do
    local scan,crossings,previous=y+.5,{},points[#points]
    for _,current in ipairs(points) do
      local ax,ay,bx,by=previous[1],previous[2],current[1],current[2]
      if (ay<=scan and by>scan) or (by<=scan and ay>scan) then crossings[#crossings+1]=ax+(scan-ay)*(bx-ax)/(by-ay) end
      previous=current
    end
    table.sort(crossings)
    for i=1,#crossings-1,2 do
      local l,r=math.ceil(crossings[i]-.5),math.ceil(crossings[i+1]-.5);fill(p,l,y,r-l,1,c)
    end
  end
end
local function disk(p,cx,cy,rx,ry,c)
  for y=math.max(0,math.floor(cy-ry)),math.min(p.h-1,math.ceil(cy+ry)-1) do
    local dy=(y+.5-cy)/ry
    if math.abs(dy)<=1 then
      local span=rx*math.sqrt(math.max(0,1-dy*dy))
      local l,r=math.ceil(cx-span-.5),math.ceil(cx+span-.5);fill(p,l,y,r-l,1,c)
    end
  end
end
-- 水平游程 + 跨行合并，保留透明孔洞，减少纯色矩形控件。
local function finish(p)
  local s,active=spec(p.w,p.h),{}
  for y=0,p.h-1 do
    local nextActive,x={},0
    while x<p.w do
      local c,l=p.pixels[y*p.w+x+1] or 0,x
      repeat x=x+1 until x==p.w or (p.pixels[y*p.w+x+1] or 0)~=c
      if ((c>>24)&255)>0 then
        local key=l..':'..(x-l)..':'..c;local old=active[key]
        if old then old.h=old.h+1;nextActive[key]=old
        else local r={x=l,y=y,w=x-l,h=1,c=c};s.rects[#s.rects+1],nextActive[key]=r,r end
      end
    end
    active=nextActive
  end
  return s
end
local function rotate90(s,turns)
  for _=1,turns%4 do
    local n=spec(s.h,s.w)
    for _,r in ipairs(s.rects) do rect(n,s.h-r.y-r.h,r.x,r.h,r.w,r.c) end
    s=n
  end
  return s
end
-- 宽颅骨、双眼窝、鼻孔和逐颗牙。状态只改五官。
local function sansHead(expression)
  local p=canvas(32,30)
  polygon(p,{{8,1},{24,1},{28,3},{30,7},{31,17},{29,22},{26,26},{22,29},{10,29},{6,26},{3,22},{1,17},{2,7},{4,3}},WHITE)
  fill(p,5,11,8,7,BLACK);fill(p,19,11,8,7,BLACK)
  if expression=='ClosedEyes' then
    fill(p,5,11,8,7,WHITE);fill(p,19,11,8,7,WHITE);fill(p,5,14,8,2,BLACK);fill(p,19,14,8,2,BLACK)
  elseif expression=='Tired1' or expression=='Tired2' or expression=='Sweat' then
    local lid=expression=='Tired2' and 5 or 3
    fill(p,5,11,8,lid,WHITE);fill(p,19,11,8,lid,WHITE);fill(p,9,16,2,1,WHITE);fill(p,21,16,2,1,WHITE)
  elseif expression=='BlueEye' then
    fill(p,8,13,2,3,WHITE);fill(p,21,12,4,5,CYAN);fill(p,22,13,2,3,WHITE)
  elseif expression~='NoEyes' then fill(p,8,13,2,3,WHITE);fill(p,22,13,2,3,WHITE) end
  fill(p,14,17,2,2,BLACK);fill(p,17,17,2,2,BLACK)
  polygon(p,{{5,19},{8,21},{24,21},{27,19},{27,24},{24,26},{8,26},{5,24}},BLACK)
  fill(p,7,22,18,2,WHITE);for x=10,22,4 do fill(p,x,22,1,2,BLACK) end
  if expression=='Tired2' then fill(p,7,24,17,1,WHITE) end
  return finish(p)
end
-- 身体包含外套、T 恤、短裤、腿、拖鞋。抬手与伸手保持脚底锚定。
local function sansBody(pose,tired)
  local side,up=pose=='right' or pose=='left',pose=='up'
  local w,h=side and 96 or 64,up and 94 or 70;local p=canvas(w,h)
  local ox,oy=(w-64)/2,up and 24 or 0;local slouch=tired and 2 or 0
  local function F(x,y,rw,rh,c) fill(p,ox+x,oy+y,rw,rh,c) end
  local function P(points,c) local pts={};for i,v in ipairs(points) do pts[i]={ox+v[1],oy+v[2]} end;polygon(p,pts,c) end
  if up then
    P({{42,10},{46,-15},{50,-18},{55,-12},{51,13}},WHITE);P({{45,10},{49,-13},{52,-12},{48,13}},BLACK)
    F(48,-23,8,9,WHITE);F(52,-24,3,5,WHITE);F(50,-19,1,4,BLACK)
  elseif side then
    P({{45,9},{75,9},{77,14},{68,20},{45,23}},WHITE);P({{48,12},{70,12},{71,14},{67,17},{48,20}},BLACK)
    F(73,8,7,10,WHITE);F(78,9,2,5,WHITE);F(74,12,1,4,BLACK)
  elseif pose=='down' then
    P({{44,9},{53,11},{55,39},{50,44},{44,36}},WHITE);P({{47,12},{51,13},{52,37},{49,39},{47,35}},BLACK)
    F(47,39,9,10,WHITE);F(49,42,1,5,BLACK);F(53,42,1,5,BLACK)
  end
  P({{20,slouch},{44,slouch},{50,5+slouch},{53,28+slouch},{45,38},{19,38},{11,28+slouch},{14,5+slouch}},WHITE)
  P({{20,3+slouch},{44,3+slouch},{47,8+slouch},{49,27+slouch},{43,35},{21,35},{15,27+slouch},{17,8+slouch}},BLACK)
  F(26,5+slouch,12,26-slouch,WHITE);F(29,5+slouch,6,3,BLACK);F(31,10+slouch,2,21-slouch,BLACK)
  F(21,18+slouch,2,12,WHITE);F(41,18+slouch,2,12,WHITE);F(18,28+slouch,6,2,WHITE);F(40,28+slouch,6,2,WHITE)
  F(15,14+slouch,3,11,WHITE)
  if pose=='default' or tired then
    F(17,24+slouch,7,6,WHITE);F(40,24+slouch,7,6,WHITE);F(20,26+slouch,1,3,BLACK);F(43,26+slouch,1,3,BLACK)
  end
  F(19,36,26,16,WHITE);F(21,38,22,12,BLACK);F(30,44,4,9,0)
  F(23,51,7,10,WHITE);F(35,51,7,10,WHITE)
  F(14,62,18,6,WHITE);F(17,60,13,3,WHITE);F(34,62,18,6,WHITE);F(35,60,13,3,WHITE)
  F(14,67,18,2,BLACK);F(34,67,18,2,BLACK)
  return finish(p),{hx=ox+16,hy=oy-24}
end
-- 长吻、双眼窝、后脑双角、双排骨齿。张嘴用下颌位移生成。
local function blaster(open)
  local p,jaw=canvas(57,44),math.floor(open*10+.5)
  polygon(p,{{3,17},{7,8},{14,4},{18,1},{24,1},{23,5},{31,6},{35,2},{39,4},{40,9},{46,12},{52,16},{57,18},{57,22},{49,23},{40,23},{34,27},{20,28},{8,26},{3,22}},WHITE)
  polygon(p,{{9,10},{13,8},{22,9},{26,14},{21,18},{13,17},{9,14}},BLACK)
  polygon(p,{{28,10},{32,9},{39,11},{42,15},{37,18},{30,16}},BLACK)
  fill(p,14,11,3,4,WHITE);fill(p,33,11,3,4,WHITE);polygon(p,{{46,16},{50,17},{53,20},{48,20}},BLACK)
  polygon(p,{{18,22},{33,23},{47,21},{56,21},{56,25+jaw},{42,26+jaw},{31,28+jaw},{17,27}},BLACK)
  polygon(p,{{7,25},{18,26},{30,29+jaw},{45,27+jaw},{56,25+jaw},{55,29+jaw},{44,32+jaw},{28,34+jaw},{14,30},{8,29}},WHITE)
  for x=26,49,6 do fill(p,x,22,3,3,WHITE);fill(p,x,28+jaw,3,3,WHITE) end
  fill(p,9,19,5,2,BLACK);return finish(p)
end
-- 同一配方的多数票采样 LOD；非透明和白骨在同票时优先。
local function lod(s,cell)
  local p=canvas(s.w,s.h);for _,r in ipairs(s.rects) do fill(p,r.x,r.y,r.w,r.h,r.c) end
  local q=canvas(math.ceil(s.w/cell),math.ceil(s.h/cell))
  for y=0,q.h-1 do for x=0,q.w-1 do
    local counts,best,count={},0,0
    for dy=0,cell-1 do for dx=0,cell-1 do
      local px,py=x*cell+dx,y*cell+dy
      if px<s.w and py<s.h then
        local c=p.pixels[py*p.w+px+1] or 0;counts[c]=(counts[c] or 0)+1
        if counts[c]>count or (counts[c]==count and c>best) then best,count=c,counts[c] end
      end
    end end
    fill(q,x,y,1,1,best)
  end end
  local out={}
  for _,r in ipairs(finish(q).rects) do out[#out+1]={x=r.x*cell,y=r.y*cell,w=math.min(r.w*cell,s.w-r.x*cell),h=math.min(r.h*cell,s.h-r.y*cell),c=r.c} end
  return out
end
M.meta={source='codeart geometric recipes',fit='procedural-rects-v1',externalTextures=false,logicalSize={640,480},colorFormat='0xAARRGGBB'}
M.sans_poses,M.sans_body_variants,M.sans_head_keys={},{},{}
for _,pose in ipairs({'default','up','down','left','right'}) do
  local key='sans_body_'..pose;local body,offset=sansBody(pose,false);M[key]=body
  M.sans_poses[pose]={body=key,hx=offset.hx,hy=offset.hy,mirror=pose=='left'}
  M.sans_body_variants[pose..'_tired']=key..'_tired';M[key..'_tired']=sansBody(pose,true)
end
for _,name in ipairs({'Default','BlueEye','ClosedEyes','NoEyes','Tired1','Tired2','Sweat'}) do
  local key='sans_head_'..name:lower();M[key],M.sans_head_keys[name]=sansHead(name),key
end
M.sans_head_default_key='sans_head_default';M.sans_head_blue_key='sans_head_blue';M.sans_head_blue=M.sans_head_blueeye
-- 可单独组合的躯干、腿和汗滴；完整身体仍是旧渲染契约的默认入口。
local function crop(s,x,y,w,h)
  local n=spec(w,h)
  for _,r in ipairs(s.rects) do
    local l,t,rr,b=math.max(x,r.x),math.max(y,r.y),math.min(x+w,r.x+r.w),math.min(y+h,r.y+r.h)
    rect(n,l-x,t-y,rr-l,b-t,r.c)
  end
  return n
end
M.sans_torso_default=crop(M.sans_body_default,0,0,64,36)
M.sans_torso_tired=crop(M.sans_body_default_tired,0,0,64,36)
M.sans_legs_default=crop(M.sans_body_default,0,36,64,34)
do
  local p=canvas(6,10);polygon(p,{{3,0},{6,6},{5,9},{1,9},{0,6}},0xFF8FD8FF);M.sans_sweat=finish(p)
end
M.blaster_default=blaster(0);M.blaster_fire_0=blaster(.3);M.blaster_fire_2=blaster(.65);M.blaster_fire_4=blaster(1)
M.blaster_keys={default='blaster_default',fire={'blaster_fire_0','blaster_fire_2','blaster_fire_4'}}
M.blaster_block2,M.blaster_block3={},{}
for label,key in pairs({Default='blaster_default',fire_0='blaster_fire_0',fire_2='blaster_fire_2',fire_4='blaster_fire_4'}) do M.blaster_block2[label]=lod(M[key],2);M.blaster_block3[label]=lod(M[key],3) end

-- 其余元素的独立配方。返回绘图矩形，不修改碰撞、触摸点击区或玩法。
local A={palette={white=WHITE,black=BLACK,red=RED,blue=BLUE,boneBlue=0xFF2F6BFF,orange=ORANGE,cyan=CYAN,green=GREEN,yellow=YELLOW,purple=PURPLE}};M.codeart=A
function A.heart(c,dir)
  local p=canvas(16,16);polygon(p,{{1,2},{5,2},{8,5},{11,2},{15,2},{16,6},{15,9},{8,16},{1,9},{0,6}},c or RED)
  return rotate90(finish(p),((dir or 1)-1)%4)
end
function A.brokenHeart(c)
  local p=canvas(18,18);for _,r in ipairs(A.heart(c or RED).rects) do fill(p,r.x+1,r.y+1,r.w,r.h,r.c) end
  polygon(p,{{8,1},{10,1},{9,6},{11,8},{8,11},{9,17},{7,17},{6,11},{9,8},{7,6}},0);return finish(p)
end
function A.bone(w,h,c,vertical)
  w,h=math.max(1,math.floor(w)),math.max(1,math.floor(h));c=c or WHITE;if vertical==nil then vertical=h>=w end
  local p,k=canvas(w,h),math.min(w,h)*.6
  if vertical then
    fill(p,(w-k)/2,k/3,k,h-2*k/3,c)
    disk(p,k/2,k/2,k/2,k/2,c);disk(p,w-k/2,k/2,k/2,k/2,c);disk(p,k/2,h-k/2,k/2,k/2,c);disk(p,w-k/2,h-k/2,k/2,k/2,c)
  else
    fill(p,k/3,(h-k)/2,w-2*k/3,k,c)
    disk(p,k/2,k/2,k/2,k/2,c);disk(p,k/2,h-k/2,k/2,k/2,c);disk(p,w-k/2,k/2,k/2,k/2,c);disk(p,w-k/2,h-k/2,k/2,k/2,c)
  end
  return finish(p)
end
function A.warning(w,h,on)
  local s=spec(w,h);if on~=false then for x=0,w-1,12 do rect(s,x,0,math.min(7,w-x),h,alpha(YELLOW,.65)) end end;return s
end
function A.stab(w,h,dir,peek)
  local p=canvas(math.max(1,math.floor(w)),math.max(1,math.floor(h)));local c=peek and alpha(WHITE,.45) or WHITE
  for _,r in ipairs(A.bone(p.w,p.h,c).rects) do fill(p,r.x,r.y,r.w,r.h,r.c) end
  local d=math.min(9,math.max(p.w,p.h))
  if dir==0 then polygon(p,{{p.w-d,0},{p.w,p.h/2},{p.w-d,p.h}},c)
  elseif dir==1 then polygon(p,{{0,p.h-d},{p.w/2,p.h},{p.w,p.h-d}},c)
  elseif dir==2 then polygon(p,{{d,0},{0,p.h/2},{d,p.h}},c)
  else polygon(p,{{0,d},{p.w/2,0},{p.w,d}},c) end
  return finish(p)
end
function A.platform(w,h,c) local s=spec(w,h);rect(s,0,0,w,h,c or GREEN);return s end
function A.frame(w,h,t,c)
  local s=spec(w,h);t=clamp(t or 4,1,math.min(w,h)/2);c=c or WHITE
  rect(s,0,0,w,t,c);rect(s,0,h-t,w,t,c);rect(s,0,t,t,h-2*t,c);rect(s,w-t,t,t,h-2*t,c);return s
end
function A.menuButton(w,h,selected)
  local s=A.frame(w,h,2,selected and YELLOW or ORANGE);if selected then append(s,A.heart(RED),7,(h-16)/2) end
  s.textBox={x=selected and 27 or 7,y=3,w=w-(selected and 34 or 14),h=h-6};return s
end
function A.attackBar(w,h,progress)
  local s=spec(w,h);rect(s,16,h/2-2,w-32,4,WHITE);rect(s,w/2-7,h/2-7,14,14,alpha(GREEN,.75))
  local x=16+clamp(progress or .5,0,1)*(w-32);rect(s,x-3,0,6,h,RED);return s
end
function A.hudBar(w,h,hp,kr,maximum)
  local s=spec(w,h);maximum=math.max(1,maximum or 92);hp=clamp(hp or maximum,0,maximum);kr=clamp(kr or 0,0,math.max(0,hp-1))
  rect(s,0,0,w,h,0xFF2A2A33);rect(s,0,0,w*hp/maximum,h,YELLOW);rect(s,w*(hp-kr)/maximum,0,w*kr/maximum,h,PURPLE);return s
end
function A.flash(w,h,c,a) local s=spec(w,h);rect(s,0,0,w,h,alpha(c or WHITE,a or 1));return s end
function A.beam(w,h,intensity)
  local s=spec(w,h);intensity=intensity or 1
  rect(s,0,0,w,h,alpha(WHITE,intensity*.78));rect(s,0,h*.3,w,h*.4,alpha(WHITE,intensity));return s
end
function A.joystick(radius,dx,dy)
  radius=math.max(8,math.floor(radius or 32));local p=canvas(radius*2,radius*2)
  disk(p,radius,radius,radius,radius,0x66FFFFFF);disk(p,radius,radius,radius-2,radius-2,0x66000000)
  local length=math.sqrt((dx or 0)^2+(dy or 0)^2);local k=length>1 and 1/length or 1
  disk(p,radius+(dx or 0)*k*radius*.55,radius+(dy or 0)*k*radius*.55,radius*.3,radius*.3,0xAAFFFFFF);return finish(p)
end
-- 5×7 英文/数字像素字。中文剧情仍由平台文本框显示。
local FONT={
 B={'11110','10001','10001','11110','10001','10001','11110'},D={'11110','10001','10001','10001','10001','10001','11110'},
 J={'00111','00010','00010','00010','00010','10010','01100'},N={'10001','11001','11001','10101','10011','10011','10001'},
 Q={'01110','10001','10001','10001','10101','10010','01101'},U={'10001','10001','10001','10001','10001','10001','01110'},
 W={'10001','10001','10001','10101','10101','10101','01010'},X={'10001','10001','01010','00100','01010','10001','10001'},
 Z={'11111','00001','00010','00100','01000','10000','11111'},
 A={'01110','10001','10001','11111','10001','10001','10001'},C={'01111','10000','10000','10000','10000','10000','01111'},
 E={'11111','10000','10000','11110','10000','10000','11111'},F={'11111','10000','10000','11110','10000','10000','10000'},
 G={'01111','10000','10000','10111','10001','10001','01111'},H={'10001','10001','10001','11111','10001','10001','10001'},
 I={'11111','00100','00100','00100','00100','00100','11111'},K={'10001','10010','10100','11000','10100','10010','10001'},
 L={'10000','10000','10000','10000','10000','10000','11111'},M={'10001','11011','10101','10101','10001','10001','10001'},
 O={'01110','10001','10001','10001','10001','10001','01110'},P={'11110','10001','10001','11110','10000','10000','10000'},
 R={'11110','10001','10001','11110','10100','10010','10001'},S={'01111','10000','10000','01110','00001','00001','11110'},
 T={'11111','00100','00100','00100','00100','00100','00100'},V={'10001','10001','10001','10001','10001','01010','00100'},
 Y={'10001','10001','01010','00100','00100','00100','00100'},
 ['0']={'01110','10001','10011','10101','11001','10001','01110'},['1']={'00100','01100','00100','00100','00100','00100','01110'},
 ['2']={'01110','10001','00001','00010','00100','01000','11111'},['3']={'11110','00001','00001','01110','00001','00001','11110'},
 ['4']={'00010','00110','01010','10010','11111','00010','00010'},['5']={'11111','10000','10000','11110','00001','00001','11110'},
 ['6']={'01110','10000','10000','11110','10001','10001','01110'},['7']={'11111','00001','00010','00100','01000','01000','01000'},
 ['8']={'01110','10001','10001','01110','10001','10001','01110'},['9']={'01110','10001','10001','01111','00001','00001','01110'},
 ['?']={'01110','10001','00001','00010','00100','00000','00100'},['/']={'00001','00001','00010','00100','01000','10000','10000'},
 ['!']={'00100','00100','00100','00100','00100','00000','00100'},['-']={'00000','00000','00000','11111','00000','00000','00000'},
 [':']={'00000','00100','00100','00000','00100','00100','00000'},['.']={'00000','00000','00000','00000','00000','00100','00100'},
}
function A.pixelText(value,c)
  value=tostring(value):upper();local p=canvas(math.max(1,#value*6-1),7)
  for i=1,#value do
    local ch=value:sub(i,i);local glyph=FONT[ch] or (ch~=' ' and FONT['?'])
    if glyph then for y,row in ipairs(glyph) do for x=1,5 do if row:sub(x,x)=='1' then fill(p,(i-1)*6+x-1,y-1,1,1,c or WHITE) end end end end
  end
  return finish(p)
end
function A.result(outcome)
  local s=spec(640,480);rect(s,0,0,640,480,BLACK)
  local failed=outcome=='fail';local title=failed and 'GAME OVER' or (outcome=='spare' and 'MERCY' or ((outcome=='kill' or outcome=='killed') and 'KILLED' or 'VICTORY'))
  local heading=A.pixelText(title,failed and RED or YELLOW);append(s,heading,(640-heading.w*4)/2,150,4)
  append(s,failed and A.brokenHeart() or A.heart(outcome=='spare' and GREEN or RED),296,226,3)
  s.textBox={x=120,y=310,w=400,h=36};return s
end
M.soul_red=A.heart(RED);M.soul_blue=A.heart(BLUE)
for name,dir in pairs({right=0,down=1,left=2,up=3}) do M['soul_blue_'..name]=A.heart(BLUE,dir) end
M.soul_broken=A.brokenHeart()
for name,c in pairs({white=WHITE,blue=0xFF2F6BFF,orange=ORANGE}) do M['bone_'..name..'_v']=A.bone(10,40,c,true);M['bone_'..name..'_h']=A.bone(40,10,c,false) end
M.bone_warning=A.warning(120,5);M.bone_stab=A.stab(10,64,3,false);M.platform_green=A.platform(72,5)
M.battle_frame=A.frame(165,165);M.menu_button=A.menuButton(140,36,false);M.menu_button_selected=A.menuButton(140,36,true)
M.attack_bar=A.attackBar(280,28,.35);M.hp_kr_bar=A.hudBar(92,18,64,18,92)
M.flash_white=A.flash(640,480,WHITE);M.flash_black=A.flash(640,480,BLACK)
M.blaster_beam=A.beam(280,20,1)
M.joystick_idle=A.joystick(28,0,0);M.joystick_move=A.joystick(28,.6,-.5)
M.result_fail=A.result('fail');M.result_victory=A.result('victory');M.result_spare=A.result('spare')
M.result_killed=A.result('killed')
M.result_kill=M.result_killed
return M
