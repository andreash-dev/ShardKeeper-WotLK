local ADDON, NS = ...
local GUI = NS.GUI
local icon = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\Minimap-active"
local panel = CreateFrame("Frame", "ShardKeeperOptions", UIParent)
panel:SetSize(320, 284)
panel:SetPoint("CENTER")
panel:SetFrameStrata("DIALOG")
panel:SetMovable(true)
panel:SetClampedToScreen(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
panel:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true, tileSize=32, edgeSize=24, insets={left=6,right=6,top=6,bottom=6}})
panel:Hide()
tinsert(UISpecialFrames, "ShardKeeperOptions")

local function label(name, text, font, x, y)
    local f = panel:CreateFontString(name, "OVERLAY", font or "GameFontHighlight")
    f:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
    f:SetText(text)
    return f
end
local function button(name, text, x, y, width, callback)
    local b = CreateFrame("Button", name, panel, "UIPanelButtonTemplate")
    b:SetSize(width, 24)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", callback)
    return b
end
local texture = panel:CreateTexture(nil, "ARTWORK")
texture:SetSize(34,34)
texture:SetPoint("TOPLEFT", 18,-16)
texture:SetTexture(icon)
label("ShardKeeperTitle", "ShardKeeper", "GameFontNormalLarge", 62,-26)
local close = CreateFrame("Button", "ShardKeeperTitleClose", panel, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -6,-6)
local function centerLabel(name, text, font, y)
    local f=label(name,text,font,0,0)
    f:ClearAllPoints()
    f:SetPoint("TOP",panel,"TOP",0,y)
    return f
end
local status = centerLabel(nil,"", "GameFontHighlightSmall",-62)
local count = centerLabel("ShardKeeperOptionsCurrentCount","0","GameFontNormalHuge",-84)
centerLabel(nil,"Soul Shards in bags","GameFontHighlightSmall",-114)
local bar = CreateFrame("StatusBar", nil, panel)
bar:SetSize(276,6)
bar:SetPoint("TOP",0,-137)
bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
bar:SetStatusBarColor(0.62,0.35,0.9)
local background=bar:CreateTexture(nil,"BACKGROUND")
background:SetAllPoints()
background:SetTexture(0.15,0.15,0.15,0.8)
local input=CreateFrame("EditBox","ShardKeeperCapInput",panel,"InputBoxTemplate")
input:SetSize(48,24)
input:SetPoint("TOP",0,-160)
input:SetAutoFocus(false)
input:SetNumeric(true)
input:SetMaxLetters(2)
input:SetJustifyH("CENTER")
local keep=label("ShardKeeperCapLabel","Keep up to","GameFontHighlight",0,0)
keep:ClearAllPoints()
keep:SetPoint("RIGHT",input,"LEFT",-12,0)
local units=label(nil,"shards","GameFontHighlight",0,0)
units:ClearAllPoints()
units:SetPoint("LEFT",input,"RIGHT",12,0)

function GUI:CommitInput()
    local current=ShardKeeperDB.cap or 5
    local value=tonumber(input:GetText())
    -- An empty unfinished edit keeps the existing target, never cap zero.
    if not value then input:SetText(tostring(current)); input:ClearFocus(); return end
    value=math.floor(math.max(0,math.min(32,value)))
    if value~=current then
        ShardKeeper_OK()
    else
        input:SetText(tostring(value))
        input:ClearFocus()
    end
end
input:SetScript("OnEnterPressed",function() GUI:CommitInput() end)
input:SetScript("OnEscapePressed",function() panel:Hide() end)
local buttons={}
for i,value in ipairs({5,10,20,32}) do
    local n=value
    buttons[#buttons+1]=button("ShardKeeperPreset"..n,tostring(n),22+(i-1)*71,-198,63,function()
        input:SetText(tostring(n))
        GUI:CommitInput()
    end)
end
local pause=button(nil,"Pause cleanup",22,-240,134,function() GUI:TogglePause() end)
buttons[#buttons+1]=pause
local done=button("ShardKeeperClose","Close",164,-240,134,function() panel:Hide() end)
buttons[#buttons+1]=done

function GUI:Refresh()
    local cap=ShardKeeperDB.cap or 5
    local shards=GetItemCount(6265) or 0
    local paused=ShardKeeperDB.paused
    status:SetText(paused and "|cffffc45eCleanup paused|r" or "|cff78d99aAutomatic cleanup active|r")
    texture:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Textures\\Minimap-" .. (paused and "paused" or "active"))
    count:SetText(shards)
    bar:SetMinMaxValues(0,math.max(cap,1))
    bar:SetValue(math.min(shards,math.max(cap,1)))
    pause:SetText(paused and "Resume cleanup" or "Pause cleanup")
end

function GUI:TogglePause()
    ShardKeeperDB.paused=not ShardKeeperDB.paused
    -- Use the same serialized cleanup path as loot and bag events.
    if not ShardKeeperDB.paused then self:RequestCleanup() end
    self:UpdateReadouts()
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ShardKeeper|r: Cleanup "..(ShardKeeperDB.paused and "paused." or "resumed."))
    end
end
function GUI:ApplySkin()
    if self.skinApplied then return end
    local E=type(ElvUI)=="table" and ElvUI[1]
    if not E or type(E.GetModule)~="function" then return end
    local ok,S=pcall(E.GetModule,E,"Skins",true)
    if not ok or not S then return end
    if panel.SetTemplate then panel:SetTemplate("Transparent") end
    if S.HandleButton then
        for _,b in ipairs(buttons) do S:HandleButton(b) end
    end
    if S.HandleEditBox then S:HandleEditBox(input) end
    if S.HandleCloseButton then S:HandleCloseButton(close) end
    self.skinApplied=true
end
panel:SetScript("OnShow",function()
    GUI:ApplySkin()
    input:SetText(tostring(ShardKeeperDB.cap or 5))
    GUI:UpdateReadouts()
end)

-- All close paths, including the minimap toggle and UISpecialFrames Escape.
panel:SetScript("OnHide",function() GUI:CommitInput() end)
