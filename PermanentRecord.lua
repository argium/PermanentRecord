local addonName = ...
PermanentRecord = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0")

local comment = {
  datetime = "",
  zone = "",
  text = "",
}

local record = {
  playerId = "", -- player name
  flag = 0,      -- flag color
  comments = {}, -- list of comments
  fingerprint = "" -- computed finger for the battle.net account
}

local defaults = {
  profile = {
    debug = true, -- enable debug output
    loaded = addonName,
    records = {},
  },
}

-- playerId
-- flag
-- history


function PR_LOG_INFO(...)
  if PermanentRecord.db.profile.debug then
    print("[PermanentRecord]", ...)
  end
end

function PR_LOG_WARN(...)
  if PermanentRecord.db.profile.debug then
    print("[PermanentRecord]", ...)
  end
end

function PR_LOG_ERROR(...)
  if PermanentRecord.db.profile.debug then
    print("[PermanentRecord]", ...)
  end
end

function PermanentRecord:OnInitialize()
  self.db = LibStub("AceDB-3.0"):New(addonName.."DB", defaults, true)
  self.core = PermanentRecord.Core:New(self.db)
  PermanentRecord:RegisterChatCommand("pr", "HandleSlashCmd")
end

function PermanentRecord:HandleGroupEvent(event, ...)
  PR_LOG_INFO(event)
  C_Timer.After(2, function()
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
      self.core:ProcessGroupRoster()
    elseif event == "GROUP_JOINED" then
      PR_LOG_INFO("Group joined")
    elseif event == "GROUP_LEFT" then
      PR_LOG_INFO("Group left")
    end
  end)
end

PermanentRecord:RegisterEvent("GROUP_ROSTER_UPDATE", "HandleGroupEvent")
PermanentRecord:RegisterEvent("GROUP_JOINED", "HandleGroupEvent")
PermanentRecord:RegisterEvent("GROUP_LEFT", "HandleGroupEvent")
PermanentRecord:RegisterEvent("PLAYER_ENTERING_WORLD", "HandleGroupEvent")

function PermanentRecord:HandleSlashCmd(input)
  local parts = strsplittable(' ', input)
  local command = parts[1] or ""
  print("Input", input)
  print("Command '".. command .."'")
  print("parts2 '".. parts[2] .."'")

  if command == "get" then
    self:SlashGet(parts[2] or "")
  elseif command == "add" then
    self:SlashAdd(parts[2] or "")
  elseif command == "debug" then
    self.db.profile.debug = not self.db.profile.debug
  elseif command == "help" or command == "" then
    print("Available commands:")
    print("  pr get <player> - Get the record for a player")
    print("  pr add <player> [flag] - Add a player with an optional flag (default is yellow)")
    print("  pr help - Show this help message")
  else
    print("Unknown command. Type 'pr help' for available commands.")
  end
end

function PermanentRecord:SlashGet(value)
  local record = self.core:GetRecord(value)
  if record then
    print("Record for", value, "exists with flag:", record.flag)
  else
    print("No record found for", value)
  end
end

function PermanentRecord:SlashAdd(player, flag)
  flag = flag or PermanentRecord.Core.FLAG.Yellow
  if player == "" then
    print("Please provide a player name.")
    return
  end
  self.core:AddRecord(player, flag)
end

function PermanentRecord:SlashRemove(player)
  local result = self.core:RemoveRecord(player)
  if result then
    print("Removed record for", player)
  else
    print("No record found for", player)
  end
end



-- function PR_IterateRoster(maxGroup,index)
-- 	index = (index or 0) + 1
-- 	maxGroup = maxGroup or 8

-- 	if IsInRaid() then
-- 		if index > GetNumGroupMembers() then
-- 			return
-- 		end
-- 		local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML, combatRole = GetRaidRosterInfo(index)
-- 		if subgroup > maxGroup then
-- 			return ExRT.F.IterateRoster(maxGroup,index)
-- 		end
-- 		local guid = UnitGUID(name or "raid"..index)
-- 		name = name or ""
-- 		return index, name, subgroup, fileName, guid, rank, level, online, isDead, combatRole
-- 	else
-- 		local name, rank, subgroup, level, class, fileName, online, isDead, combatRole, _

-- 		local unit = index == 1 and "player" or "party"..(index-1)

-- 		local guid = UnitGUID(unit)
-- 		if not guid then
-- 			return
-- 		end

-- 		subgroup = 1
-- 		name, _ = UnitName(unit)
-- 		name = name or ""
-- 		if _ then
-- 			name = name .. "-" .. _
-- 		end
-- 		class, fileName = UnitClass(unit)

-- 		if UnitIsGroupLeader(unit) then
-- 			rank = 2
-- 		else
-- 			rank = 1
-- 		end

-- 		level = UnitLevel(unit)

-- 		if UnitIsConnected(unit) then
-- 			online = true
-- 		end

-- 		if UnitIsDeadOrGhost(unit) then
-- 			isDead = true
-- 		end

-- 		combatRole = UnitGroupRolesAssigned(unit)

-- 		return index, name, subgroup, fileName, guid, rank, level, online, isDead, combatRole
-- 	end
-- end
