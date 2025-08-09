local AddonName, _ = ...
PermanentRecord.Core = {}

function PermanentRecord.Core:DebugLog(...)
  if self.debug then
    print("[PR_TRACE]", ...)
  end
end

---@class PermanentRecord.Core
---@field db AceDB-3.0
---@field debug boolean
---@return PermanentRecord.Core
function PermanentRecord.Core:New(db, debug)
  self.db = db
  self.debug = debug or false
  self.db.global.addonVersion = C_AddOns.GetAddOnMetadata(AddonName, 'Version')
  if not self.db.global.dbVersion then
    self.db.global.dbVersion = 1 -- Initial version
  end
  -- Ensure profile tables exist
  self.db.profile.players = self.db.profile.players or {}
  self.db.profile.guilds = self.db.profile.guilds or {}
  return self
end

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

---@param name string Guild name
---@return string|nil guildName Normalised guild name or nil if empty
local function GetNormalisedGuildName(name)
  if not name or name == "" then
    return nil
  end
  return string.lower(name)
end

--- Processes group roster change events to check if any players have records.
function PermanentRecord.Core:ProcessGroupRoster()
  -- Coalesce concurrent/rapid calls; only final state matters
  if self._rosterProcessing then
    self._rosterPending = true
    self:DebugLog("Roster processing already running, merging request.")
    return
  end

  self._rosterProcessing = true
  repeat
    self._rosterPending = false

    if not IsInGroup() then
      self:DebugLog("Not in a group, skipping roster processing.")
    else
      self:DebugLog("Processing group roster update")

      -- todo: add some locking mechanism to protect against race conditions

      local prefix  = IsInRaid() and "raid" or "party"

      local selfNameRealm = GetNormalisedNameAndRealm(GetUnitName("player", true))
      for i = 1, GetNumGroupMembers() do
        local playerNameRealm = GetUnitName(prefix..i, true)
        if self:GetPlayer(playerNameRealm) then
          self:DebugLog("I have seen this player before:", playerNameRealm)
        elseif playerNameRealm ~= selfNameRealm then
          self:AddPlayer(playerNameRealm)
          self:DebugLog("Adding new record for player:", playerNameRealm)
        end
      end
    end
  until not self._rosterPending
  self._rosterProcessing = false
end

---@param name string Player name, assumed to be the player's realm if not provided.
---@return Player|nil player The Player instance if added or already exists, or nil if invalid name
---@return boolean added True if player was added, false if already exists or invalid
function PermanentRecord.Core:AddPlayer(name)
  -- TODO: name doesn't include the home realm so the addon won't work across realms
  if not name or name == "" then
    return nil, false
  end
  name = GetNormalisedNameAndRealm(name)
  if not name then
    return nil, false
  end
  local existing = self.db.profile.players[name]
  if existing then
    return existing, false
  end
  local player = PermanentRecord.Player:New(name)
  self.db.profile.players[name] = player
  return player, true
end

---@param name string Player name, assumed to be the player's realm if not provided.
---@return Player|nil record Record for the player, or nil if not found
function PermanentRecord.Core:GetPlayer(name)
  if not name or name == "" then
    return nil
  end
  name = GetNormalisedNameAndRealm(name)
  self:DebugLog("Getting record for player:", name)
  return self.db.profile.players[name]
end

---@param name string Player name, assumed to be the player's realm if not provided.
---@return boolean removed True if record was removed, false if no record found
function PermanentRecord.Core:RemovePlayer(name)
  if not name or name == "" then
    return false
  end
  name = GetNormalisedNameAndRealm(name)
  if self.db.profile.players[name] then
    self.db.profile.players[name] = nil
    self:DebugLog("Removed record for player:", name)
    return true
  else
    return false
  end
end

---@param name string Guild name
---@return Guild|nil guild The Guild instance if added or already exists, or nil if invalid
---@return boolean added True if guild was added, false if already exists or invalid
function PermanentRecord.Core:AddGuild(name)
  local guildName = GetNormalisedGuildName(name)
  if not guildName then
    return nil, false
  end
  local existing = self.db.profile.guilds[guildName]
  if existing then
    return existing, false
  end
  local guild = PermanentRecord.Guild:New(guildName)
  self.db.profile.guilds[guildName] = guild
  return guild, true
end

---@param name string Guild name
---@return Guild|nil record Record for the guild, or nil if not found
function PermanentRecord.Core:GetGuild(name)
  local guildName = GetNormalisedGuildName(name)
  if not guildName then
    return nil
  end
  self:DebugLog("Getting record for guild:", guildName)
  return self.db.profile.guilds[guildName]
end

---@param name string Guild name
---@return boolean removed True if record was removed, false if no record found
function PermanentRecord.Core:RemoveGuild(name)
  local guildName = GetNormalisedGuildName(name)
  if not guildName then
    return false
  end
  if self.db.profile.guilds[guildName] then
    self.db.profile.guilds[guildName] = nil
    self:DebugLog("Removed record for guild:", guildName)
    return true
  else
    return false
  end
end
