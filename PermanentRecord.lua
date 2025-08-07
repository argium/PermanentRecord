local addonName = ...
PermanentRecord = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0")

local comment = {
  datetime = "",
  zone = "",
  text = "",
}

local record = {
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


function PermanentRecord:PR_LOG_TRACE(...)
  if self.db.profile.debug then
    print("[PermanentRecord]", ...)
  end
end

function PermanentRecord:PR_LOG_WARN(...)
  if self.db.profile.debug then
    print("[PermanentRecord]", ...)
  end
end

function PermanentRecord:PR_LOG_ERROR(...)
  print("[PermanentRecord]", ...)
end

function PermanentRecord:OnInitialize()
  self.db = LibStub("AceDB-3.0"):New(addonName .. "DB", defaults, true)
end

function PermanentRecord:OnEnable()
  self:RegisterChatCommand("pr", "HandleSlashCmd")
  self:PR_LOG_TRACE("PermanentRecord enable. Loaded", #self.db.profile.players, "player records.")
end

function PermanentRecord:HandleGroupEvent(event, ...)
  self:PR_LOG_TRACE(event)
  C_Timer.After(2, function()
    if PermanentRecord.Core == nil then
      self:PR_LOG_ERROR("Core is not initialized, cannot handle group event:", event)
      return
    end
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
      self:ProcessGroupRoster()
    elseif event == "GROUP_JOINED" then
      self:PR_LOG_TRACE("Group joined")
    elseif event == "GROUP_LEFT" then
      self:PR_LOG_TRACE("Group left")
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
    self:PR_LOG_ERROR("Please specify 'p' for player or 'g' for guild.")
    return
  end
  if not value or value == "" then
    self:PR_LOG_ERROR("Please provide a name.")
    return
  end

  if type == "p" or type == "player" then
    self:GetPlayer(value)
  elseif type == "g" or type == "guild" then
    self:GetGuild(value)
  end
end

function PermanentRecord:SlashAdd(args, flag)
  local type = args[2] and args[2]:lower() or ""
  local value = args[3]
  flag = flag or PermanentRecord.Core.FLAG.Yellow

  if not type or type == "" then
    self:PR_LOG_ERROR("Please specify 'p' for player or 'g' for guild.")
    return
  end
  if not value or value == "" then
    self:PR_LOG_ERROR("Please provide a name.")
    return
  end

  if type == "p" or type == "player" then
    PermanentRecord:AddPlayer(value, flag)
  elseif type == "g" or type == "guild" then
    PermanentRecord:AddGuild(value, flag)
  end
end

function PermanentRecord:SlashRemove(args)
  local type = args[2] and args[2]:lower() or ""
  local value = args[3]

  if not type or type == "" then
    self:PR_LOG_ERROR("Please specify 'p' for player or 'g' for guild.")
    return
  end

  if type == "p" or type == "player" then
    PermanentRecord:RemovePlayer(value)
  elseif type == "g" or type == "guild" then
    PermanentRecord:RemoveGuild(value)
  end
end

---@enum Flag
FLAG = {
	Red = 0,
	Yellow = 2,
	Green = 4,
}

---@param name string Player name, with or without realm.
---@return string|nil name Player name with realm if not provided, nil if name is empty
local function GetNormalisedNameAndRealm(name)
  if not name or name == "" then
    return nil
  end
  if not name:find("-") then
    local _, playerRealm = UnitFullName("player")
    if playerRealm then
      name = name .. "-" .. playerRealm
    end
  end
  return string.lower(name)
end

--- Processes group roster change events to check if any players have records.
function PermanentRecord:ProcessGroupRoster()
  if not IsInGroup() then
    self:PR_LOG_TRACE("Not in a group, skipping roster processing.")
    return
  end

  self:PR_LOG_TRACE("Processing group roster update")

  -- todo: add some locking mechanism to protect against race conditions

  local prefix  = IsInRaid() and "raid" or "party"

  local selfNameRealm = GetNormalisedNameAndRealm(GetUnitName("player", true))
  for i = 1, GetNumGroupMembers() do
    local playerNameRealm = GetUnitName(prefix..i, true)
    if self:GetPlayer(playerNameRealm) then
      self:PR_LOG_TRACE("I have seen this player before:", playerNameRealm)
    elseif playerNameRealm ~= selfNameRealm then
      self:AddPlayer(playerNameRealm, FLAG.Yellow)
      self:PR_LOG_TRACE("Adding new record for player:", playerNameRealm)
    end
  end
end

---@param name string Player name, assumed to be the player's realm if not provided.
---@param flag Flag Flag color.
function PermanentRecord:AddPlayer(name, flag)
  -- TODO: name doesn't include the home realm so the addon won't work across realms
  if not name or name == "" then
    self:PR_LOG_ERROR("Player name is required to add a record")
    return
  end
  name = GetNormalisedNameAndRealm(name)
  if self.db.profile.players[name] then
    self:PR_LOG_ERROR("Error: Player ID already exists in records")
    return
  end
  local record = {
    playerId = name,
    flag = flag,
    history = {}
  }
  self.db.profile.players[name] = record
end

---@param name string Player name, assumed to be the player's realm if not provided.
---@return table|nil record Record for the player, or nil if not found
function PermanentRecord:GetPlayer(name)
  if not name or name == "" then
    self:PR_LOG_ERROR("Player name is required to get a record")
    return nil
  end
  name = GetNormalisedNameAndRealm(name)
  self:PR_LOG_TRACE("Getting record for player:", name)
  return self.db.profile.players[name]
end

---@param name string Player name, assumed to be the player's realm if not provided.
---@return boolean removed True if record was removed, false if no record found
function PermanentRecord:RemovePlayer(name)
  if not name or name == "" then
    self:PR_LOG_ERROR("Player name is required to remove a record")
    return false
  end
  name = GetNormalisedNameAndRealm(name)
  if self.db.profile.players[name] then
    self.db.profile.players[name] = nil
    self:PR_LOG_TRACE("Removed record for player:", name)
    return true
  else
    self:PR_LOG_ERROR("No record found for player:", name)
    return false
  end
end
