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

-- Helper to add a formatted grouped line for a sighting to the tooltip
local function AddGroupedLine(tooltip, label, sighting)
  if not tooltip or not label or type(sighting) ~= "table" then return end
  local ts = tonumber(sighting.ts)
  local seenBy = sighting.seenBy
  if not ts or ts <= 0 then return end
  local ago = PermanentRecord.Core:FormatTimeAgo(ts)
  local suffix = ""
  if type(seenBy) == "string" and seenBy ~= "" then
    local nameOnly = seenBy:match("^([^%-]+)") or seenBy
    suffix = " on " .. nameOnly
  end
  tooltip:AddLine("|cff875cff" .. label .. ": " .. ago .. suffix)
end

local function OnTooltipSetItem(tooltip, data)
  if not tooltip then return end
  assert(PermanentRecord.core, "PermanentRecord core is not initialized")

  -- Don't add tooltip info while in combat
  if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
    return
  end

  local name, unit = tooltip:GetUnit()
  if not UnitIsPlayer(unit) then return end
  PermanentRecord:DebugLog("OnTooltipSetItem for unit:", name, unit)

  -- Use name with realm for lookup; core will normalize
  local fullName = GetUnitName(unit, true) or name
  if not fullName or fullName == "" then return end
  PermanentRecord:DebugLog("Looking up player:", fullName)

  local rec = PermanentRecord.Core.GetPlayer(PermanentRecord.core, fullName)
  if not rec then return end

  AddGroupedLine(tooltip, "First grouped", rec.firstSighting)
  local lastSighting = rec.sightings and rec.sightings[#rec.sightings]
  AddGroupedLine(tooltip, "Last grouped", lastSighting)

  -- Most recent note
  local lastComment = rec.comments and rec.comments[#rec.comments]
  local note = lastComment and lastComment.text or nil
  if note and note ~= "" then
    tooltip:AddLine("|cff875cffNote: " .. note)
  end

  tooltip:Show()
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnTooltipSetItem);
