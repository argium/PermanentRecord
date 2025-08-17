local AddonName, NS = ...
PermanentRecord = LibStub("AceAddon-3.0"):NewAddon("PermanentRecord", "AceConsole-3.0", "AceEvent-3.0")

-- Map model classes from the shared addon table to the global addon object
PermanentRecord.Player = NS and NS.Player or PermanentRecord.Player
PermanentRecord.Guild = NS and NS.Guild or PermanentRecord.Guild
PermanentRecord.Comment = NS and NS.Comment or PermanentRecord.Comment

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
  print("|cffdd4444[" .. AddonName .. "]|r", ...)
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

-- UI / tooltip / context menu logic moved to UI.lua
