local addonName = ...
PermanentRecord = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0")

local comment = {
  datetime = "",
  zone = "",
  text = "",
}

local player = {
  playerId = "",   -- player name
  flag = 0,        -- flag color
  comments = {},   -- list of comments
  fingerprint = "" -- computed finger for the battle.net account
}

local guild = {
  guildId = "",  -- guild name
  flag = 0,      -- flag color
  comments = {}, -- list of comments
}

local defaults = {
  profile = {
    debug = true, -- enable debug output
    players = {},
    guilds = {},
  },
}

-- playerId
-- flag
-- history


function PR_LOG_TRACE(...)
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
  print("[PermanentRecord]", ...)
end

function PermanentRecord:OnEnable()
  self.db = LibStub("AceDB-3.0"):New(addonName .. "DB", defaults, true)
  self.core = PermanentRecord.Core:New(self.db)
  PermanentRecord:RegisterChatCommand("pr", "HandleSlashCmd")
  PR_LOG_TRACE("PermanentRecord enabled")
end

function PermanentRecord:HandleGroupEvent(event, ...)
  PR_LOG_TRACE(event)
  C_Timer.After(2, function()
    if self.core == nil then
      PR_LOG_ERROR("Core is not initialized, cannot handle group event:", event)
      return
    end
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
      self.core:ProcessGroupRoster()
    elseif event == "GROUP_JOINED" then
      PR_LOG_TRACE("Group joined")
    elseif event == "GROUP_LEFT" then
      PR_LOG_TRACE("Group left")
    end
  end)
end

PermanentRecord:RegisterEvent("GROUP_ROSTER_UPDATE", "HandleGroupEvent")
PermanentRecord:RegisterEvent("GROUP_JOINED", "HandleGroupEvent")
PermanentRecord:RegisterEvent("GROUP_LEFT", "HandleGroupEvent")
PermanentRecord:RegisterEvent("PLAYER_ENTERING_WORLD", "HandleGroupEvent")

function PermanentRecord:HandleSlashCmd(input)
  local args = strsplittable(' ', input)
  local command = args[1] or ""

  if #args == 3 then
    if command == "get" then
      self:SlashGet(args)
      return
    elseif command == "add" then
      self:SlashAdd(args)
      return
    elseif command == "remove" then
      self:SlashRemove(args)
      return
    end
  elseif command == "debug" then
    self.db.profile.debug = not self.db.profile.debug
    print("Debug mode is now", self.db.profile.debug and "enabled" or "disabled")
    return
  elseif command == "st" or command == "status" then
    print("PermanentRecord status:")
    print("  Profile:", self.db.keys.profile)
    print("  Debug mode:", self.db.profile.debug and "enabled" or "disabled")
    print("  Loaded players:", #self.db.profile.players)
    print("  Loaded guilds:", #self.db.profile.guilds)
    return
  end

  print("Available commands:")
  print("  pr get <player> - Get the record for a player")
  print("  pr add <player> [flag] - Add a player with an optional flag (default is yellow)")
  print("  pr help - Show this help message")
end

function PermanentRecord:SlashGet(args)
  local type = args[2] and args[2]:lower() or ""
  local value = args[3]

  if not type or type == "" then
    PR_LOG_ERROR("Please specify 'p' for player or 'g' for guild.")
    return
  end
  if not value or value == "" then
    PR_LOG_ERROR("Please provide a name.")
    return
  end

  if type == "p" or type == "player" then
    self.core:GetPlayer(value)
  elseif type == "g" or type == "guild" then
    self.core:GetGuild(value)
  end
end

function PermanentRecord:SlashAdd(args, flag)
  local type = args[2] and args[2]:lower() or ""
  local value = args[3]
  flag = flag or PermanentRecord.Core.FLAG.Yellow

  if not type or type == "" then
    PR_LOG_ERROR("Please specify 'p' for player or 'g' for guild.")
    return
  end
  if not value or value == "" then
    PR_LOG_ERROR("Please provide a name.")
    return
  end

  if type == "p" or type == "player" then
    self.core:AddPlayer(value, flag)
  elseif type == "g" or type == "guild" then
    self.core:AddGuild(value, flag)
  end
end

function PermanentRecord:SlashRemove(args)
  local type = args[2] and args[2]:lower() or ""
  local value = args[3]

  if not type or type == "" then
    PR_LOG_ERROR("Please specify 'p' for player or 'g' for guild.")
    return
  end

  if type == "p" or type == "player" then
    self.core:RemovePlayer(value)
  elseif type == "g" or type == "guild" then
    self.core:RemoveGuild(value)
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
