local ADDON, NS = ...
local SOUL_SHARD_ID = 6265

-- SavedVariables declared in TOC
ShardKeeperDB = ShardKeeperDB or {}

-- Defaults
local defaults = {
  cap = 5,
  paused = false,
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

-- Only one deletion may be outstanding. Bag/loot events can arrive before
-- GetItemCount and container slots reflect the previous deletion.
local pendingDeletion, deleting
local function DeleteExtraShards()
  if deleting or ShardKeeperDB.paused or GetCursorInfo() then return 0 end
  local cap = ShardKeeperDB.cap or defaults.cap
  local count, candidate = 0, nil
  for bag = NUM_BAG_SLOTS, 0, -1 do
    for slot = GetContainerNumSlots(bag), 1, -1 do
      if GetContainerItemID(bag, slot) == SOUL_SHARD_ID then
        local _, quantity, locked = GetContainerItemInfo(bag, slot)
        if type(quantity) ~= "number" or quantity < 1 then return 0 end
        count = count + quantity
        if not candidate and not locked then
          candidate = {bag=bag, slot=slot, quantity=quantity}
        end
      end
    end
  end
  -- Never act on inconsistent cached totals and slot data.
  if count ~= GetShardCount() then return 0 end
  if pendingDeletion then
    local slotID = GetContainerItemID(pendingDeletion.bag, pendingDeletion.slot)
    local _, slotCount, slotLocked = GetContainerItemInfo(pendingDeletion.bag, pendingDeletion.slot)
    local slotChanged = not slotLocked and (slotID ~= SOUL_SHARD_ID
      or (type(slotCount) == "number" and slotCount < pendingDeletion.quantity))
    -- A new shard may offset the deleted one in the total. Confirm the actual
    -- source slot as well, so simultaneous gains cannot leave cleanup stuck.
    if count > pendingDeletion.expected and not slotChanged then return 0 end
    pendingDeletion = nil
  end
  if count <= cap or not candidate then return 0 end
  -- Never destroy a whole stack that would cross the target.
  if candidate.quantity > count - cap then return 0 end

  deleting = true
  pendingDeletion = {expected=count-candidate.quantity, bag=candidate.bag,
    slot=candidate.slot, quantity=candidate.quantity}
  PickupContainerItem(candidate.bag, candidate.slot)
  local kind, cursorID = GetCursorInfo()
  if kind ~= "item" or cursorID ~= SOUL_SHARD_ID then
    deleting = false
    return 0
  end
  DeleteCursorItem()
  deleting = false
  -- Leave the pending guard in place until a later event confirms the drop.
  return 0
end

-- Recheck after inventory events have settled, even when the last bag event
-- arrived before the client cache updated. Bounded retries never bypass the
-- confirmation guard. The worker sleeps completely when it has no work.
local cleanupWorker = CreateFrame("Frame")
local cleanupElapsed, cleanupRetries = 0, 0
local function CleanupTick(self, elapsed)
  cleanupElapsed = cleanupElapsed + elapsed
  if cleanupElapsed < 0.2 then return end
  cleanupElapsed = 0
  cleanupRetries = cleanupRetries - 1
  DeleteExtraShards()
  if NS.GUI then NS.GUI:UpdateReadouts() end
  if cleanupRetries <= 0 or ShardKeeperDB.paused
    or (not pendingDeletion and GetShardCount() <= (ShardKeeperDB.cap or defaults.cap)) then
    self:SetScript("OnUpdate", nil)
  end
end
local function RequestCleanup()
  cleanupElapsed, cleanupRetries = 0, 25
  cleanupWorker:SetScript("OnUpdate", CleanupTick)
  DeleteExtraShards()
end

-- ========= GUI helpers =========
NS.GUI = {}

function NS.GUI:RequestCleanup()
  RequestCleanup()
end

function NS.GUI:UpdateReadouts()
  if ShardKeeperMinimapButtonIcon then
    local state = ShardKeeperDB.paused and "paused" or "active"
    ShardKeeperMinimapButtonIcon:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Textures\\Minimap-" .. state)
  end
  if NS.GUI.Refresh then NS.GUI:Refresh() end
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
  value = math.floor(math.max(0, math.min(32, value))) -- WotLK limit
  ShardKeeperDB.cap = value
  ShardKeeperCapInput:SetText(tostring(value))
  ShardKeeperCapInput:ClearFocus()

  RequestCleanup()
  NS.GUI:UpdateReadouts()
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(string.format(
      "|cff33ff99ShardKeeper|r: Target set to %d. %s", value,
      ShardKeeperDB.paused and "Cleanup paused." or "Excess shards will be removed as bag updates confirm each deletion."
    ))
  end
end

-- ========= Minimap Button =========
local dragging = false

-- Quadrants follow the GetMinimapShape convention used by LibDBIcon:
-- bottom-right, bottom-left, top-right, top-left; true means rounded.
local minimapShapes = {
  ROUND = {true, true, true, true},
  SQUARE = {false, false, false, false},
  ["CORNER-TOPLEFT"] = {true, false, false, false},
  ["CORNER-TOPRIGHT"] = {false, false, true, false},
  ["CORNER-BOTTOMLEFT"] = {false, true, false, false},
  ["CORNER-BOTTOMRIGHT"] = {false, false, false, true},
  ["SIDE-LEFT"] = {true, true, false, false},
  ["SIDE-RIGHT"] = {false, false, true, true},
  ["SIDE-TOP"] = {true, false, true, false},
  ["SIDE-BOTTOM"] = {false, true, false, true},
  ["TRICORNER-TOPLEFT"] = {true, true, true, false},
  ["TRICORNER-TOPRIGHT"] = {true, false, true, true},
  ["TRICORNER-BOTTOMLEFT"] = {true, true, false, true},
  ["TRICORNER-BOTTOMRIGHT"] = {false, true, true, true},
}

local function PositionMinimapButton()
  local angle = ShardKeeperDB.minimap.angle or defaults.minimap.angle
  local rad = math.rad(angle)
  local x, y = math.cos(rad), math.sin(rad)
  local width, height = Minimap:GetWidth(), Minimap:GetHeight()
  -- Keep square edges inset like the surrounding minimap buttons. Round
  -- quadrants retain the usual outside radius used by native round minimaps.
  local halfWidth = width and width > 0 and width / 2 or 70
  local halfHeight = height and height > 0 and height / 2 or 70
  local rx, ry = halfWidth + 10, halfHeight + 10
  local quadrant = 1
  if x < 0 then quadrant = quadrant + 1 end
  if y > 0 then quadrant = quadrant + 2 end
  local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
  local rounded = minimapShapes[shape] or minimapShapes.ROUND
  if rounded[quadrant] then
    x, y = x * rx, y * ry
  else
    -- Inset the button center from the rectangular edge.
    rx, ry = math.max(1, halfWidth - 7), math.max(1, halfHeight - 7)
    local distance = 1 / math.max(math.abs(x) / rx, math.abs(y) / ry)
    x, y = x * distance, y * distance
  end
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
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("BAG_UPDATE")
f:RegisterEvent("CHAT_MSG_LOOT")

f:SetScript("OnEvent", function(self, event, ...)
  if event == "PLAYER_LOGIN" then
    -- Only activate if player is a Warlock
    local _, class = UnitClass("player")
    if class ~= "WARLOCK" then
      if ShardKeeperMinimapButton then ShardKeeperMinimapButton:Hide() end
      self:UnregisterAllEvents()
      return
    end

    applyDefaults(ShardKeeperDB, defaults)
    if ShardKeeperMinimapButtonIcon then
      ShardKeeperMinimapButtonIcon:ClearAllPoints()
      ShardKeeperMinimapButtonIcon:SetPoint("CENTER", ShardKeeperMinimapButton, "CENTER", 1.5, 0.5)
      ShardKeeperMinimapButtonIcon:SetSize(26, 26)
      ShardKeeperMinimapButtonIcon:SetTexCoord(0, 1, 0, 1)
    end
    NS.GUI:ApplySkin()
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
          NS.GUI:TogglePause()
        end
      end
    end)

    ShardKeeperMinimapButton:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:AddLine("ShardKeeper", 1, 1, 1)
      GameTooltip:AddLine(ShardKeeperDB.paused and "Cleanup paused" or "Cleanup active", 0.8, 0.8, 0.8)
      GameTooltip:AddLine("Left Click: Open settings", 0.8, 0.8, 0.8)
      GameTooltip:AddLine("Right Click: Pause / resume cleanup", 0.8, 0.8, 0.8)
      GameTooltip:AddLine("Shift + Drag: Move", 0.8, 0.8, 0.8)
      GameTooltip:AddLine(("Cap: %d  |  Shards: %d"):format(ShardKeeperDB.cap or defaults.cap, GetShardCount()), 0.2, 1, 0.2)
      GameTooltip:Show()
    end)
    ShardKeeperMinimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    NS.GUI:UpdateReadouts()

  elseif event == "PLAYER_ENTERING_WORLD" then
    PositionMinimapButton()

  elseif event == "CHAT_MSG_LOOT" then
    local msg = ...
    local item = string.match(msg or "", "|Hitem:(%d+):")
    if tonumber(item) == SOUL_SHARD_ID then
      RequestCleanup()
      NS.GUI:UpdateReadouts()
    end

  elseif event == "BAG_UPDATE" then
    RequestCleanup()
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
