local ADDON, NS = ...
local SOUL_SHARD_ID = 6265

-- SavedVariables declared in TOC
ShardKeeperDB = ShardKeeperDB or {}

-- Defaults
local defaults = {
  cap = 20,
  minimap = { angle = 220 }, -- degrees (around the Minimap)
}

-- ========= Utils =========
local function applyDefaults(db, defs)
  for k, v in pairs(defs) do
    if type(v) == "table" then
      db[k] = db[k] or {}
      applyDefaults(db[k], v)
    else
      if db[k] == nil then db[k] = v end
    end
  end
end

local function GetShardCount()
  return GetItemCount(SOUL_SHARD_ID) or 0
end

-- Delete extras; returns how many removed
local function DeleteExtraShards()
  local cap   = ShardKeeperDB.cap or defaults.cap
  local count = GetShardCount()
  if count <= cap then return 0 end

  local need    = count - cap
  local removed = 0

  -- Scan from last bag/slot (often newest shards end up later)
  for _ = 1, need do
    local deleted = false
    for bag = NUM_BAG_SLOTS, 0, -1 do
      local slots = GetContainerNumSlots(bag)
      for slot = slots, 1, -1 do
        local itemID = GetContainerItemID(bag, slot)
        if itemID == SOUL_SHARD_ID then
          PickupContainerItem(bag, slot)
          DeleteCursorItem()
          removed = removed + 1
          deleted = true
          break
        end
      end
      if deleted then break end
    end
    if not deleted then break end
  end

  return removed
end

-- ========= GUI helpers =========
NS.GUI = {}

function NS.GUI:UpdateReadouts()
  if ShardKeeperOptions and ShardKeeperOptions:IsShown() then
    if ShardKeeperOptionsCurrentCount then
      ShardKeeperOptionsCurrentCount:SetText(GetShardCount())
    end
  end
end

-- Called from XML OnShow
function ShardKeeper_OnShow()
  -- Ensure texts (3.3.5-safe)
  if ShardKeeperOK and ShardKeeperOK.SetText then ShardKeeperOK:SetText("OK") end
  if ShardKeeperClose and ShardKeeperClose.SetText then ShardKeeperClose:SetText("Close") end
  if ShardKeeperCapLabel and ShardKeeperCapLabel.SetText then ShardKeeperCapLabel:SetText("Set soul shard cap:") end
  if ShardKeeperCurrentLabel and ShardKeeperCurrentLabel.SetText then ShardKeeperCurrentLabel:SetText("Current soul shards:") end

  if ShardKeeperCapInput and ShardKeeperDB then
    ShardKeeperCapInput:SetText(tostring(ShardKeeperDB.cap or defaults.cap))
  end
  NS.GUI:UpdateReadouts()
end

-- Global OK handler (called by OK button)
function ShardKeeper_OK()
  local text  = ShardKeeperCapInput and ShardKeeperCapInput:GetText() or ""
  local value = tonumber(text) or ShardKeeperDB.cap or defaults.cap
  value = math.floor(math.max(0, math.min(64, value))) -- clamp 0–64
  ShardKeeperDB.cap = value

  -- Ta ett initialt count före rensning
  local before = GetShardCount()
  local removed = DeleteExtraShards()
  local after = math.max(before - removed, 0)  -- robust slutvärde

  NS.GUI:UpdateReadouts()

  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(string.format(
      "|cff33ff99ShardKeeper|r: Cap set to %d. Removed %d extra shard(s). Now at %d.",
      value, removed, after
    ))
  end
end

-- ========= Minimap Button =========
local dragging = false

local function PositionMinimapButton()
  local angle = ShardKeeperDB.minimap.angle or defaults.minimap.angle
  local radius = 80
  local rad = math.rad(angle)
  local x = math.cos(rad) * radius
  local y = math.sin(rad) * radius
  ShardKeeperMinimapButton:ClearAllPoints()
  ShardKeeperMinimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function OnUpdate_MinimapButton(self)
  if dragging then
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    local angle = math.deg(math.atan2(cy - my, cx - mx))
    if angle < 0 then angle = angle + 360 end
    ShardKeeperDB.minimap.angle = angle
    PositionMinimapButton()
  end
end

-- ========= Events =========
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("BAG_UPDATE")
f:RegisterEvent("CHAT_MSG_LOOT")

f:SetScript("OnEvent", function(self, event, ...)
  if event == "PLAYER_LOGIN" then
    applyDefaults(ShardKeeperDB, defaults)
    PositionMinimapButton()

    -- Minimap button handlers
    ShardKeeperMinimapButton:SetScript("OnMouseDown", function(self, button)
      if button == "LeftButton" and IsShiftKeyDown() then
        dragging = true
        self:SetScript("OnUpdate", OnUpdate_MinimapButton)
      end
    end)

    ShardKeeperMinimapButton:SetScript("OnMouseUp", function(self, button)
      if dragging then
        dragging = false
        self:SetScript("OnUpdate", nil)
      else
        if button == "LeftButton" then
          if ShardKeeperOptions:IsShown() then
            ShardKeeperOptions:Hide()
          else
            ShardKeeperOptions:Show()
          end
        elseif button == "RightButton" then
          -- Quick toggle 0 <-> default
          if (ShardKeeperDB.cap or 0) == 0 then
            ShardKeeperDB.cap = defaults.cap
          else
            ShardKeeperDB.cap = 0
          end
          local removed = DeleteExtraShards()
          NS.GUI:UpdateReadouts()
          if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
              "|cff33ff99ShardKeeper|r: Cap now %d (quick toggle). Removed %d. Now at %d.",
              ShardKeeperDB.cap, removed, GetShardCount()
            ))
          end
        end
      end
    end)

    ShardKeeperMinimapButton:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:AddLine("ShardKeeper", 1, 1, 1)
      GameTooltip:AddLine("Left Click: Open settings", 0.8, 0.8, 0.8)
      GameTooltip:AddLine("Right Click: Quick-toggle cap (0/Default)", 0.8, 0.8, 0.8)
      GameTooltip:AddLine("Shift + Drag: Move", 0.8, 0.8, 0.8)
      GameTooltip:AddLine(("Cap: %d  |  Shards: %d"):format(ShardKeeperDB.cap or defaults.cap, GetShardCount()), 0.2, 1, 0.2)
      GameTooltip:Show()
    end)
    ShardKeeperMinimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    NS.GUI:UpdateReadouts()

  elseif event == "CHAT_MSG_LOOT" then
    local msg = ...
    local item = string.match(msg or "", "|Hitem:(%d+):")
    if tonumber(item) == SOUL_SHARD_ID then
      DeleteExtraShards()
      NS.GUI:UpdateReadouts()
    end

  elseif event == "BAG_UPDATE" then
    DeleteExtraShards()
    NS.GUI:UpdateReadouts()
  end
end)

-- Slash
SLASH_SHARDKEEPER1 = "/shardkeeper"
SLASH_SHARDKEEPER2 = "/sk"
SlashCmdList.SHARDKEEPER = function()
  if ShardKeeperOptions:IsShown() then
    ShardKeeperOptions:Hide()
  else
    ShardKeeperOptions:Show()
  end
end
