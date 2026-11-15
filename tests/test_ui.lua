-- Lua 5.1 smoke and behavior checks; client rendering still needs in-game QA.
local frames={}
local methods={}
local function frame(name)
    local f={scripts={},text="",shown=false}
    setmetatable(f,{__index=methods})
    if name then _G[name]=f end
    frames[#frames+1]=f
    return f
end
for _,method in ipairs({"SetTexCoord","SetSize","SetPoint","SetFrameStrata","SetMovable","SetClampedToScreen","EnableMouse","RegisterForDrag","SetBackdrop","SetAllPoints","SetTexture","SetAutoFocus","SetNumeric","SetMaxLetters","SetWidth","SetJustifyH","SetStatusBarTexture","SetStatusBarColor","SetMinMaxValues","SetValue","ClearFocus","RegisterEvent","UnregisterAllEvents","ClearAllPoints","SetOwner","AddLine","StartMoving","StopMovingOrSizing"}) do
    methods[method]=function() end
end
function methods:SetTexture(path) self.texture=path end
function methods:SetText(s) self.text=tostring(s) end
function methods:GetText() return self.text end
function methods:SetScript(event,fn) self.scripts[event]=fn end
function methods:IsShown() return self.shown end
function methods:Show() self.shown=true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
function methods:Hide()
    local wasShown=self.shown
    self.shown=false
    if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:CreateFontString(name) return frame(name) end
function methods:CreateTexture() return frame() end
function methods:GetWidth() return self.width or 140 end
function methods:GetHeight() return self.height or 140 end
function CreateFrame(_,name) return frame(name) end
UIParent=frame(); Minimap=frame(); ShardKeeperMinimapButton=frame()
ShardKeeperMinimapButtonIcon=frame()
UISpecialFrames={}; tinsert=table.insert; SlashCmdList={}; NUM_BAG_SLOTS=0
local count,cursor,locked=8,nil,false
function UnitClass() return "Warlock","WARLOCK" end
function GetItemCount() return count end
function GetCursorInfo() if cursor then return "item",cursor end end
function GetContainerNumSlots() return count end
function GetContainerItemID() return 6265 end
function GetContainerItemInfo() return nil,1,locked end
function PickupContainerItem() cursor=6265 end
function DeleteCursorItem() cursor=nil; count=count-1 end
local NS={}
assert(loadfile("ShardKeeper.lua"))("ShardKeeper",NS)
assert(loadfile("ShardKeeperUI.lua"))("ShardKeeper",NS)
local events
for _,f in ipairs(frames) do if f.scripts.OnEvent then events=f end end
assert(events)
events.scripts.OnEvent(events,"PLAYER_LOGIN")
assert(ShardKeeperMinimapButtonIcon.texture=="Interface\\AddOns\\ShardKeeper\\Textures\\Minimap-active")
SlashCmdList.SHARDKEEPER()
assert(ShardKeeperOptions:IsShown())
assert(ShardKeeperOptionsCurrentCount.text=="8")
NS.GUI:TogglePause()
assert(ShardKeeperMinimapButtonIcon.texture:match("Minimap%-paused$"))
ShardKeeperCapInput:SetText("5")
ShardKeeper_OK()
assert(count==8 and ShardKeeperDB.paused)
cursor=1234
ShardKeeperMinimapButton.scripts.OnMouseUp(ShardKeeperMinimapButton,"RightButton")
assert(not ShardKeeperDB.paused and ShardKeeperMinimapButtonIcon.texture:match("Minimap%-active$"))
cursor=1234
ShardKeeper_OK()
assert(count==8 and cursor==1234,"occupied cursor must remain untouched")
cursor=nil; locked=true
ShardKeeper_OK()
assert(count==8,"locked shards must be skipped")
locked=false
ShardKeeper_OK()
for i=1,5 do events.scripts.OnEvent(events,"BAG_UPDATE",0) end
assert(count==5,"cleanup must stop at saved target")
ShardKeeperCapInput:SetText("40")
ShardKeeper_OK()
assert(ShardKeeperDB.cap==32 and ShardKeeperCapInput.text=="32")
-- Exercise the installed ElvUI skin interface as well as the vanilla path.
local skinned=0
local skin={HandleButton=function() skinned=skinned+1 end,HandleEditBox=function() end,HandleCloseButton=function() end}
ElvUI={{GetModule=function() return skin end}}
ShardKeeperOptions.SetTemplate=function() end
NS.GUI:ApplySkin()
assert(skinned==6)
ShardKeeperDB.paused=true
events.scripts.OnEvent(events,"PLAYER_LOGIN")
assert(ShardKeeperMinimapButtonIcon.texture:match("Minimap%-paused$"),"login must restore paused artwork")

-- Geometry checks: the square perimeter must not collapse to a circle.
function methods:GetWidth() return self.width or 140 end
function methods:GetHeight() return self.height or 140 end
function methods:SetPoint(...) self.point={...} end
local shape="SQUARE"
function GetMinimapShape() return shape end
local function position(angle)
    ShardKeeperDB.minimap.angle=angle
    events.scripts.OnEvent(events,"PLAYER_ENTERING_WORLD")
    return ShardKeeperMinimapButton.point[4],ShardKeeperMinimapButton.point[5]
end
for _,angle in ipairs({0,45,90,135,180,225,270,315}) do
    local x,y=position(angle)
    assert(math.abs(math.max(math.abs(x),math.abs(y))-63)<0.001)
end
local x,y=position(45)
assert(math.abs(x-63)<0.001 and math.abs(y-63)<0.001)
shape="ROUND"
x,y=position(45)
assert(math.abs(x*x+y*y-80*80)<0.001)
shape="UNKNOWN"
local ux,uy=position(45)
assert(x==ux and y==uy)
shape="SQUARE"; Minimap.width=200; Minimap.height=160
x,y=position(45)
assert(math.abs(x-73)<0.001 and math.abs(y-73)<0.001)
shape="SIDE-TOP"
x,y=position(45)
assert(math.abs(x-110/math.sqrt(2))<0.001)
x,y=position(225)
assert(math.abs(y+73)<0.001)
-- Presets save immediately; closing commits a manually edited target.
ShardKeeperOptions:Show()
ShardKeeperPreset20.scripts.OnClick()
assert(ShardKeeperDB.cap==20)
ShardKeeperCapInput:SetText("12")
ShardKeeperClose.scripts.OnClick()
assert(ShardKeeperDB.cap==12 and not ShardKeeperOptions:IsShown())
ShardKeeperOptions:Show()
ShardKeeperCapInput:SetText("14")
ShardKeeperCapInput.scripts.OnEscapePressed(ShardKeeperCapInput)
assert(ShardKeeperDB.cap==14 and not ShardKeeperOptions:IsShown())
ShardKeeperOptions:Show()
ShardKeeperCapInput:SetText("16")
ShardKeeperOptions:Hide() -- same path used by the template X and global Escape
assert(ShardKeeperDB.cap==16)
ShardKeeperOptions:Show()
ShardKeeperCapInput:SetText("")
ShardKeeperOptions:Hide()
assert(ShardKeeperDB.cap==16,"empty input must not delete all shards")
ShardKeeperOptions:Show()
ShardKeeperCapInput:SetText("99")
ShardKeeperCapInput.scripts.OnEnterPressed()
assert(ShardKeeperDB.cap==32 and ShardKeeperOptions:IsShown())
assert(not ShardKeeperOK,"Apply button must be removed")
-- Regression: asynchronous inventory changes and duplicate loot/bag events.
ShardKeeperOptions:Hide()
ShardKeeperDB.cap=3; ShardKeeperDB.paused=false
count=3
-- Clear any previously confirmed pending operation.
events.scripts.OnEvent(events,"BAG_UPDATE",0)
local slots,requests=4,0
count=4
function GetContainerNumSlots() return slots end
function GetContainerItemInfo() return nil,1,false end
function DeleteCursorItem()
    requests=requests+1
    -- WoW may emit events inside item manipulation before counts settle.
    events.scripts.OnEvent(events,"BAG_UPDATE",0)
    cursor=nil
end
events.scripts.OnEvent(events,"BAG_UPDATE",0)
assert(requests==1)
for i=1,20 do
    events.scripts.OnEvent(events,"BAG_UPDATE",0)
    events.scripts.OnEvent(events,"CHAT_MSG_LOOT","|Hitem:6265:0|h[Soul Shard]|h")
end
assert(requests==1,"duplicate events with stale inventory must not delete again")
slots=3 -- slots update before GetItemCount
for i=1,10 do events.scripts.OnEvent(events,"BAG_UPDATE",0) end
assert(requests==1,"inconsistent count and slots must not trigger deletion")
count=3
events.scripts.OnEvent(events,"BAG_UPDATE",0)
assert(requests==1,"confirmed target must stop deletion")
-- Another newly acquired shard permits exactly one more deletion.
slots=4; count=4
events.scripts.OnEvent(events,"BAG_UPDATE",0)
assert(requests==2)
slots=3; count=3
events.scripts.OnEvent(events,"BAG_UPDATE",0)
assert(requests==2)
-- A custom-server stack must never be destroyed below target.
slots=1; count=4
function GetContainerItemInfo() return nil,4,false end
events.scripts.OnEvent(events,"BAG_UPDATE",0)
assert(requests==2,"whole stacks larger than excess must be preserved")
-- Burst regression: the deleted slot empties but a second gain masks the
-- total reduction. Cache settles without another BAG_UPDATE notification.
local inventory={[1]=true,[2]=true,[3]=true,[4]=true}
local pickedSlot
count=4
function GetContainerNumSlots() return 8 end
function GetContainerItemID(_,slot) return inventory[slot] and 6265 or nil end
function GetContainerItemInfo(_,slot) return nil,inventory[slot] and 1 or nil,false end
function PickupContainerItem(_,slot) pickedSlot=slot; cursor=6265 end
events.scripts.OnEvent(events,"BAG_UPDATE",0)
assert(requests==3 and pickedSlot==4)
inventory[4]=nil; inventory[5]=true -- deletion + new shard: total stays four
local worker
for _,f in ipairs(frames) do if f~=ShardKeeperMinimapButton and f.scripts.OnUpdate then worker=f end end
assert(worker,"pending cleanup must schedule a recheck")
worker.scripts.OnUpdate(worker,0.21)
assert(requests==4 and pickedSlot==5,"second excess must be removed despite unchanged total")
inventory[5]=nil; count=3
worker.scripts.OnUpdate(worker,0.21)
assert(requests==4 and not worker.scripts.OnUpdate,"worker must stop at target")
-- Stale unchanged slots never authorize a second deletion, even on timer ticks.
inventory[6]=true; count=4
events.scripts.OnEvent(events,"BAG_UPDATE",0)
assert(requests==5)
for i=1,30 do if worker.scripts.OnUpdate then worker.scripts.OnUpdate(worker,0.21) end end
assert(requests==5 and not worker.scripts.OnUpdate,"retry timeout must not bypass confirmation")
-- Resume must clean existing excess without a fresh loot/bag event.
inventory[6]=nil; count=3
events.scripts.OnEvent(events,"BAG_UPDATE",0) -- confirm previous operation
NS.GUI:TogglePause()
assert(ShardKeeperDB.paused)
inventory[4]=true; inventory[5]=true; count=5
local beforeResume=requests
events.scripts.OnEvent(events,"BAG_UPDATE",0)
assert(requests==beforeResume,"paused cleanup must preserve acquired shards")
function DeleteCursorItem()
    requests=requests+1
    inventory[pickedSlot]=nil
    count=count-1
    cursor=nil
end
NS.GUI:TogglePause()
assert(not ShardKeeperDB.paused and requests==beforeResume+1)
for i=1,5 do if worker.scripts.OnUpdate then worker.scripts.OnUpdate(worker,0.21) end end
assert(count==3 and requests==beforeResume+2,"resume must drain excess without bag events")
assert(not worker.scripts.OnUpdate)
-- Minimap right-click resumes through the identical cleanup path.
ShardKeeperMinimapButton.scripts.OnMouseUp(ShardKeeperMinimapButton,"RightButton")
inventory[4]=true; count=4
ShardKeeperMinimapButton.scripts.OnMouseUp(ShardKeeperMinimapButton,"RightButton")
assert(count==3 and not ShardKeeperDB.paused)
if worker.scripts.OnUpdate then worker.scripts.OnUpdate(worker,0.21) end
assert(not worker.scripts.OnUpdate)
print("PASS: panel and minimap resume clean existing excess without new inventory events")
print("PASS: simultaneous gains, delayed cache without extra events and bounded safe retry")
print("PASS: delayed counts, reentrant events, duplicate loot/bag events and stack safety")
print("PASS: icon state via panel/minimap and login; UI load, login, panel, pause, cursor safety, locked slots, cleanup, cap and skin callback")
