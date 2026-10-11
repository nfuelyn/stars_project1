-- Strict API doubles: lowercase id, EnumItem events, positional signal arguments,
-- Color values and active=false defaults follow the official API documentation.
local logs, controls, signals, audioHandles = {}, {}, {}, {}
local nextId, nextAudio = 0, 0
print = function(s) logs[#logs+1] = tostring(s) end
Enum = {}
local function item(group,name)
  Enum[group] = Enum[group] or {}
  local v = setmetatable({name=name}, {__tostring=function(t) return t.name end})
  Enum[group][name] = v
  return v
end
for _,name in ipairs({'CursorDown','CursorUp','CursorDrag','CursorClick'}) do item('CursorEventType',name) end
for _,name in ipairs({'Left','Middle','Right'}) do item('TextHorizontalAlignment',name) end
for _,name in ipairs({'StaticReference'}) do item('ImageSource',name) end
item('CustomVariableEntityType','Level')
item('Device','KeyboardAndMouse'); item('Device','Mobile')
local names = {
  'KeyboardMoveForwardKey','KeyboardMoveBackwardKey','KeyboardMoveLeftKey','KeyboardMoveRightKey',
  'KeyboardCraftspersonKey36','KeyboardCraftspersonKey37','KeyboardCraftspersonKey38','KeyboardCraftspersonKey39',
  'KeyboardCraftspersonKey12','KeyboardCraftspersonKey19','KeyboardJumpKey','KeyboardDropKey',
  'KeyboardCraftspersonKey42','ControllerJumpKey','ControllerNormalAttackKey',
  'ControllerMenuConfirmKey','ControllerMenuBackKey','ControllerCharacterSkill3Key',
  'ControllerCharacterSkill4Key','ControllerCraftspersonKey1','ControllerCraftspersonKey2',
}
for _,name in ipairs(names) do item('KeyEventType',name..'Down'); item('KeyEventType',name..'Up') end
-- Intentionally no KeyboardMenuConfirmKey or KeyboardMenuBackKey enums.
Color = function(r,g,b,a) return {r=r,g=g,b=b,a=a or 255,_color=true} end
local methods = {}
function methods:SetActive(v) self.active=v end
function methods:SetVisible(v) self.visible=v end
function methods:SetSizeDelta(w,h) self.w,self.h=w,h end
function methods:SetAnchoredPosition(x,y) self.x,self.y=x,y end
function methods:SetAnchorMin(x,y) self.ax0,self.ay0=x,y end
function methods:SetAnchorMax(x,y) self.ax1,self.ay1=x,y end
function methods:SetPivot(x,y) self.px,self.py=x,y end
function methods:SetLocalRotation(x,y,z) self.rotation=z end
function methods:SetLocalScale(x,y,z) self.scaleX,self.scaleY=x,y end
local function sibling(c,last)
  if not c.parent then return end
  local list=c.parent.children
  for i,v in ipairs(list) do if v==c then table.remove(list,i);break end end
  table.insert(list,last and (#list+1) or 1,c)
end
function methods:SetAsFirstSibling() sibling(self,false) end
function methods:SetAsLastSibling() sibling(self,true) end
function methods:GetChildren() return self.children end
function methods:SetImage(source,id)
  assert(source==Enum.ImageSource.StaticReference and type(id)=='number')
  self.imageId=id
end
function methods:AddKeyEventListener(event,cb)
  assert(type(event)=='table' and Enum.KeyEventType[event.name]==event, 'key event must be EnumItem')
  assert(not self.listeners[event.name], 'duplicate key listener')
  self.listeners[event.name]=cb
end
function methods:RemoveKeyEventListener(event,cb)
  if self.listeners[event.name]==cb then self.listeners[event.name]=nil end
end
function methods:AddCursorEventListener(event,cb)
  assert(type(event)=='table' and Enum.CursorEventType[event.name]==event, 'cursor event must be EnumItem')
  self.listeners[event.name]=cb
end
function methods:RemoveAllCursorEventListeners() self.listeners={} end
local function control(prefab,parent,kind)
  nextId=nextId+1
  local data={id=nextId,prefabIndex=prefab,parent=parent,active=false,alive=true,
    name='test',children={},listeners={},kind=kind or 'container',imageId=100001}
  if kind=='text' then data.text='' end
  if kind=='circle' then data.imageId=100002 elseif kind=='ring' then data.imageId=100006
  elseif kind=='rtri' then data.imageId=100003 end
  local c=setmetatable({}, {
    __index=function(_,k)
      if k=='SetImage' and not ({rect=true,rot=true,rtri=true,circle=true,ring=true})[data.kind] then return nil end
      if k=='AddCursorEventListener' and data.kind~='cursor' then return nil end
      return methods[k] or data[k]
    end,
    __newindex=function(_,k,v)
      if k=='raycastTarget' then assert(data.kind=='cursor','undocumented raycastTarget on non-cursor') end
      if k=='imageColor' or k=='fontColor' then assert(type(v)=='table' and v._color,'ColorValue required') end
      if k=='fontSize' then assert(v%1==0) end
      if k=='horizontalAlignment' then assert(type(v)=='table','alignment EnumItem required') end
      data[k]=v
    end,
  })
  controls[#controls+1]=c
  if parent then parent.children[#parent.children+1]=c end
  return c
end
local root=control(0,nil); root.active=true
game = {}
function game.GetUICanvasSize() return 1280,720 end
function game.GetDevice() return Enum.Device.KeyboardAndMouse end
function game.GetGlobalCustomVariableValue(entity,name)
  assert(entity==Enum.CustomVariableEntityType.Level)
  return nil
end
function game.InstantiateClientUIControl(prefab,parent)
  assert(type(prefab)=='number' and parent)
  local kind='container'
  for k,v in pairs(config.templates) do if v==prefab and not k:find('baked') then kind=k end end
  local outer=control(prefab,parent,'container')
  if kind~='container' then control(prefab,outer,kind) end
  return outer
end
function game.DestroyClientUIControl(c)
  for _,child in ipairs(c.children) do game.DestroyClientUIControl(child) end
  c.alive=false
end
function game.PlayAudio2D(id)
  assert(type(id)=='number' and id>0)
  nextAudio=nextAudio+1;audioHandles[nextAudio]={id=id,alive=true};return nextAudio
end
function game.StopAudio(h) if audioHandles[h] then audioHandles[h].alive=false end end
function game.IsAudioAlive(h) return audioHandles[h] and audioHandles[h].alive or false end
local rejectSignal=false
function game.ServerSignal(name)
  if rejectSignal then error('offline') end
  local sig={name=name,params={}}
  function sig:AddString(v, extra) assert(type(v)=='string' and extra==nil); self.params[#self.params+1]=v end
  function sig:AddInt(v, extra) assert(type(v)=='number' and v%1==0 and extra==nil); self.params[#self.params+1]=v end
  function sig:AddFloat(v, extra) assert(type(v)=='number' and extra==nil); self.params[#self.params+1]=v end
  function sig:SendSignal() signals[#signals+1]=self end
  return sig
end
script={object=root,EnableUpdate=function() end}
config.audio.bgm=501
config.audio.effects.hit=502
config.device='mobile' -- Also exercise touch while retaining the physical key bindings.
main.OnInit();main.OnStart();main.OnStart()
local function update(dt) main.OnUpdate(dt);main.OnLevelUpdate(dt) end
update(1/60)
assert(main.state().state=='title' and not main.drawnBoxVisible())
assert(root.listeners.KeyboardCraftspersonKey12Down,'official Z binding')
assert(not root.listeners.KeyboardNormalAttackKeyDown,'mouse click must not also confirm via attack key')
root.listeners.KeyboardCraftspersonKey12Down();update(1/60)
root.listeners.KeyboardCraftspersonKey12Up()
local g=main.state();g.hurt=function() return false end
local time=g.enemyT
for _=1,60 do update(1/60) end
assert(math.abs(g.enemyT-time-1)<1e-6,'OnUpdate + OnLevelUpdate doubled game time')
assert(not main.updateErrorLogged)
for _,s in ipairs(logs) do assert(not s:find(' ERR ') and not s:find('bind fail'),s) end
local b=core.render(g)[2]
local shown=main.box()
assert(shown.x==b.x and shown.y==b.y and shown.w==b.w and shown.h==b.h,'display box lags behind collision box')
local created=#controls
assert(created>10 and created<5000,'drawing did not instantiate expected controls')
for _,c in ipairs(controls) do assert(c.active,'created control left inactive') end
root.listeners.KeyboardMoveForwardKeyDown();root.listeners.KeyboardCraftspersonKey36Down()
root.listeners.KeyboardMoveForwardKeyUp();assert(main.dirs().up,'release of W must preserve held ArrowUp')
root.listeners.KeyboardCraftspersonKey36Up();assert(not main.dirs().up)
local cursor
for _,c in ipairs(controls) do if c.kind=='cursor' then cursor=c;break end end
assert(cursor)
assert(cursor.w==1280 and cursor.h==720,'cursor area must cover the full canvas')
local function pointer(id,x,y) return {touchId=id,GetUIPos=function() return x,y end} end
-- Right-top pause click freezes every simulation clock, clears movement, and resumes once.
local px,py,pw,ph=main.pauseRect()
local function pauseClick(id)
  local x=160+(px+pw/2)*1.5
  local y=720-(py+ph/2)*1.5
  cursor.listeners.CursorDown(pointer(id,x,y))
  cursor.listeners.CursorUp(pointer(id,x,y))
  cursor.listeners.CursorClick(pointer(id,x,y))
end
root.listeners.KeyboardMoveRightKeyDown()
pauseClick(90)
assert(main.runtime.paused and not main.dirs().right and not music.playing,'pause input/audio state')
local elapsed,hp,kr,sx,sy,wt=g.elapsed,g.hp,g.kr,g.soul.x,g.soul.y,g.world.t
time=g.enemyT
root.listeners.KeyboardCraftspersonKey12Down()
for _=1,90 do update(1/60) end
assert(g.elapsed==elapsed and g.enemyT==time and g.hp==hp and g.kr==kr
  and g.soul.x==sx and g.soul.y==sy and g.world.t==wt,'pause advanced combat')
pauseClick(91)
assert(not main.runtime.paused and not main.dirs().right,'resume must clear held pause inputs')
update(1/60)
assert(g.enemyT>time and music.playing,'resume must continue combat')
assert(textart.glyphs[utf8.codepoint('攻')] and textart.glyphs[utf8.codepoint('暂')],'Chinese CodeArt missing')
cursor.listeners.CursorDown(pointer(7,310,270))
cursor.listeners.CursorDown(pointer(8,450,120))
cursor.listeners.CursorUp(pointer(8,450,120))
local _,joy=main.pointer();assert(joy.active,'second touch must not steal or release joystick')
cursor.listeners.CursorDrag(pointer(7,310,330));update(1/60)
assert(main.dirs().up,'official GetUIPos Y conversion')
root.listeners.KeyboardMoveRightKeyDown()
cursor.listeners.CursorUp(pointer(7,310,330));update(1/60)
assert(not main.dirs().up and main.dirs().right,'touch release must preserve held keyboard direction')
root.listeners.KeyboardMoveRightKeyUp();update(1/60)
main.OnDisable();time=g.enemyT;update(1);assert(g.enemyT==time,'disabled update must stop')
assert(not main.dirs().up and not music.playing)
main.OnEnable();root.listeners.KeyboardCraftspersonKey12Down();root.listeners.KeyboardCraftspersonKey12Up()
assert(main.runtime.cancelHeld==false)
g:finish('fail');g:settle();rejectSignal=true
for _=1,140 do update(1/60) end
assert(g.settleStatus=='failed' and #signals==0,'retry cap / failed signal status')
rejectSignal=false;g:settle();update(1/60)
assert(#signals==1 and signals[1].params[1]=='fail' and #signals[1].params==7,'positional failure signal')
g:settle();update(1/60);assert(#signals==1,'duplicate settlement')
main.OnDestroy()
assert(root.alive and #root.listeners==0,'destroy must keep host root')
for _,c in ipairs(controls) do if c~=root then assert(not c.alive,'owned control leaked') end end
io.write('PASS strict official API, rendering, inputs, lifecycle, audio and settlement retries\n')
