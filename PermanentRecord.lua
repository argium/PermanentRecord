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

  tooltip:AddLine("|cff875cffRecord created: |cffffffff" .. FormatTimeAgo(rec.createdAt))

  local ts = tonumber(rec.sightings[#rec.sightings])
  if ts then
    tooltip:AddLine("|cff875cffLast grouped: |cffffffff" .. FormatTimeAgo(ts))
  end

  tooltip:Show()
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnTooltipSetItem);
