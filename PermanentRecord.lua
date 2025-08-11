local AddonName, PR = ...
PermanentRecord = LibStub("AceAddon-3.0"):NewAddon("PermanentRecord", "AceConsole-3.0", "AceEvent-3.0")

-- Map model classes from the shared addon table to the global addon object
PermanentRecord.Player = PR and PR.Player or PermanentRecord.Player
PermanentRecord.Guild = PR and PR.Guild or PermanentRecord.Guild
PermanentRecord.Comment = PR and PR.Comment or PermanentRecord.Comment

local defaults = {
  profile = {
    debug = false,
    players = {},
    guilds = {},
  },
}

function PermanentRecord:DebugLog(...)
  if self.db.profile.debug then
    print("[" .. AddonName .. "]", ...)
  end
end

function PermanentRecord:Error(...)
  print("|cffdd4444[" .. AddonName .. "]", ...)
end

function PermanentRecord:OnInitialize()
  self.db = LibStub("AceDB-3.0"):New(AddonName .. "DB", defaults, true)
  self.core = PermanentRecord.Core:New(self.db)
  PermanentRecord:RegisterChatCommand("pr", "HandleSlashCmd")
  self:DebugLog(AddonName .. " enabled")
end

function PermanentRecord:HandleGroupEvent(event, ...)
  self:DebugLog(event)
  C_Timer.After(2, function()
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
      PermanentRecord.Core.ProcessGroupRoster(self.core)
    elseif event == "GROUP_JOINED" then
      self:DebugLog("Group joined")
      PermanentRecord.Core.ProcessGroupRoster(self.core, true) -- flag that this is on join
    elseif event == "GROUP_LEFT" then
      self:DebugLog("Group left")
    end
  end)
end

PermanentRecord:RegisterEvent("GROUP_ROSTER_UPDATE", "HandleGroupEvent")
PermanentRecord:RegisterEvent("GROUP_JOINED", "HandleGroupEvent")
PermanentRecord:RegisterEvent("GROUP_LEFT", "HandleGroupEvent")
-- PermanentRecord:RegisterEvent("PLAYER_ENTERING_WORLD", "HandleGroupEvent")

local function OnTooltipSetItem(tooltip, data)
  if not tooltip then return end
  assert(PermanentRecord.core, "PermanentRecord core is not initialized")

  local name, unit = tooltip:GetUnit()
  if not UnitIsPlayer(unit) then return end
  PermanentRecord:DebugLog("OnTooltipSetItem for unit:", name, unit)

  -- Use name with realm for lookup; core will normalize
  local fullName = GetUnitName(unit, true) or name
  if not fullName or fullName == "" then return end
  PermanentRecord:DebugLog("Looking up player:", fullName)

  local rec = PermanentRecord.core:GetPlayer(fullName)
  if not rec then return end
  PermanentRecord:DebugLog("Found record for player:", fullName)

  -- Helper: return a friendly relative time string like "3 days ago"
  local function FormatTimeAgo(ts)
    if not ts then return "unknown" end
    ts = tonumber(ts)
    if not ts or ts <= 0 then return "unknown" end
    local now = time()
    local diff = now - ts
    if diff < 0 then diff = 0 end

    local minute = 60
    local hour = 60 * minute
    local day = 24 * hour
    local month = 30 * day
    local year = 365 * day

    if diff < 45 then
      return "just now"
    elseif diff < 90 then
      return "1 minute ago"
    elseif diff < hour then
      return string.format("%d minutes ago", math.floor(diff / minute))
    elseif diff < 2 * hour then
      return "1 hour ago"
    elseif diff < day then
      return string.format("%d hours ago", math.floor(diff / hour))
    elseif diff < 2 * day then
      return "1 day ago"
    elseif diff < month then
      return string.format("%d days ago", math.floor(diff / day))
    elseif diff < 2 * month then
      return "1 month ago"
    elseif diff < year then
      return string.format("%d months ago", math.floor(diff / month))
    elseif diff < 2 * year then
      return "1 year ago"
    else
      return string.format("%d years ago", math.floor(diff / year))
    end
  end

  PermanentRecord:DebugLog("Created:", rec.createdAt)
  PermanentRecord:DebugLog("Created:", FormatTimeAgo(rec.createdAt))

  -- tooltip:AddLine("|cff875cffRecord created: |cffffffff" .. FormatTimeAgo(rec.createdAt))

  -- Last grouped (supports both legacy numeric and new {ts=...} entry formats)
  local lastSighting = rec.sightings and rec.sightings[#rec.sightings]
  local ts = nil
  if type(lastSighting) == "table" then
    ts = tonumber(lastSighting.ts)
  else
    ts = tonumber(lastSighting)
  end
  if ts and ts > 0 then
    tooltip:AddLine("|cff875cffLast grouped: |cffffffff" .. FormatTimeAgo(ts))
  end

  -- Most recent note
  local lastComment = rec.comments and rec.comments[#rec.comments]
  local note = lastComment and lastComment.text or nil
  if note and note ~= "" then
    tooltip:AddLine("|cff875cffNote: |cffffffff" .. note)
  end

  tooltip:Show()
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnTooltipSetItem);

-- Static popup to capture a note for a player
-- StaticPopupDialogs = StaticPopupDialogs or {}
-- StaticPopupDialogs["PERMANENTRECORD_ADD_NOTE"] = {
--   text = "Add note for %s",
--   button1 = SAVE or "Save",
--   button2 = "Discard",
--   hasEditBox = true,
--   editBoxWidth = 280,
--   maxLetters = 1000,
--   timeout = 0,
--   whileDead = true,
--   hideOnEscape = true,
--   preferredIndex = 3,
--   OnShow = function(self)
--     if self.editBox then
--       self.editBox:SetAutoFocus(true)
--       self.editBox:SetText("")
--       self.editBox:HighlightText()
--     end
--   end,
--   EditBoxOnEnterPressed = function(self)
--     local parent = self:GetParent()
--     if parent and parent.button1 then parent.button1:Click() end
--   end,
--   OnAccept = function(self, data)
--     local text = self.editBox and self.editBox:GetText() or ""
--     local trim = _G.strtrim or function(s) return (s or ""):gsub("^%s+", ""):gsub("%s+$", "") end
--     local note = trim(text)
--     if note == "" then return end
--     if not PermanentRecord or not PermanentRecord.core then return end

--     local fullName = data and data.fullName or nil
--     local unit = data and data.unit or nil
--     if not fullName or fullName == "" then return end

--     local player = PermanentRecord.core:AddPlayer(fullName, unit, true)
--     if not player then return end

--     local nowTs = (GetServerTime and GetServerTime() or time())
--     local dt = date("%Y-%m-%d %H:%M", nowTs)
--     local zone = (GetRealZoneText and GetRealZoneText()) or ""
--     local comment = PermanentRecord.Comment:New(dt, zone, note)
--     player:AddComment(comment)
--     PermanentRecord:DebugLog("Saved note for", fullName)
--   end,
-- }

-- -- Helper to add the "Add note" entry to a Unit menu when it refers to a player
-- local function PR_AddNoteMenuEntry(ownerRegion, rootDescription, contextData, assumePlayer)
--   -- Try to discover the unit token
--   local unit = contextData and contextData.unit or (ownerRegion and ownerRegion.unit) or nil
--   local isPlayerUnit = unit and UnitIsPlayer and UnitIsPlayer(unit)
--   if not isPlayerUnit and not assumePlayer then return end

--   -- Determine display and full names
--   local fullName = (unit and GetUnitName and GetUnitName(unit, true)) or (contextData and contextData.name) or nil
--   local displayName = (unit and GetUnitName and GetUnitName(unit, false)) or fullName or "player"
--   if not fullName or fullName == "" then return end

--   rootDescription:CreateButton("Add note", function()
--     StaticPopup_Show("PERMANENTRECORD_ADD_NOTE", displayName, nil, { unit = unit, fullName = fullName })
--   end)
-- end

-- -- Show for other player units
-- Menu.ModifyMenu("MENU_UNIT_PLAYER", function(ownerRegion, rootDescription, contextData)
--   PR_AddNoteMenuEntry(ownerRegion, rootDescription, contextData, true)
-- end)
