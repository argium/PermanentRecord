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

  -- Normalize existing player records
  for name, rec in pairs(self.db.profile.players) do
    if type(rec) ~= "table" then
      -- Convert primitive to structured record
      self.db.profile.players[name] = PermanentRecord.Player:New(name)
    else
      if type(rec.comments) ~= "table" then rec.comments = {} end
      if not rec.playerId or rec.playerId == "" then rec.playerId = name end
      if rec.fingerprint == nil then rec.fingerprint = "" end
      if rec.createdAt == nil then rec.createdAt = (GetServerTime and GetServerTime() or time()) end
      if type(rec.sightings) ~= "table" then rec.sightings = {} end
      -- trim sightings to last 5 and ensure numeric
      local cleaned = {}
      for _, ts in ipairs(rec.sightings) do
        if type(ts) == "number" then table.insert(cleaned, ts) end
      end
      -- keep only last 5
      local keepFrom = math.max(1, #cleaned - 4)
      rec.sightings = {}
      for i = keepFrom, #cleaned do table.insert(rec.sightings, cleaned[i]) end
    end
  end

  -- Normalize existing guild records
  for name, rec in pairs(self.db.profile.guilds) do
    if type(rec) ~= "table" then
      -- Convert primitive to structured record
      self.db.profile.guilds[name] = PermanentRecord.Guild:New(name)
    else
      if type(rec.comments) ~= "table" then rec.comments = {} end
      if not rec.guildId or rec.guildId == "" then rec.guildId = name end
      if rec.createdAt == nil then rec.createdAt = (GetServerTime and GetServerTime() or time()) end
    end
  end

  -- runtime state
  self._inGroup = IsInGroup() or false
  self._groupSessionId = 0
  self._seenThisGroup = {}
  self._lastRoster = {}

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

local function fmtDate(ts)
  if not ts or ts == 0 then return "" end
  return date("%Y-%m-%d %H:%M", ts)
end

local function tableKeysSorted(t)
  local out = {}
  for k in pairs(t or {}) do table.insert(out, k) end
  table.sort(out)
  return out
end

function PermanentRecord.Core:AnnounceSeen(playerName, lastSeenTs)
  if lastSeenTs and lastSeenTs > 0 then
    print("["..AddonName.."]", "Seen", playerName, "before. Last seen:", fmtDate(lastSeenTs))
  else
    print("["..AddonName.."]", "Seen", playerName, "before.")
  end
end

--- Processes group roster change events to check if any players have records.
---@param onJoin boolean|nil If true, treat all current members as newly joined for announcements
function PermanentRecord.Core:ProcessGroupRoster(onJoin)
  -- Coalesce concurrent/rapid calls; only final state matters
  if self._rosterProcessing then
    self._rosterPending = true
    self:DebugLog("Roster processing already running, merging request.")
    return
  end

  self._rosterProcessing = true
  repeat
    self._rosterPending = false

    local inGroup = IsInGroup()
    if not inGroup then
      if self._inGroup then
        self:OnGroupLeft()
      end
      self:DebugLog("Not in a group, skipping roster processing.")
    else
      -- entering a group session if previously not in group
      if not self._inGroup then
        self._inGroup = true
        self._groupSessionId = (self._groupSessionId or 0) + 1
        self._seenThisGroup = {}
        self._lastRoster = {}
        self:DebugLog("Starting group session", self._groupSessionId)
      end

      self:DebugLog("Processing group roster update")

      local prefix  = IsInRaid() and "raid" or "party"
      local currentRoster = {}

      local selfNameRealm = GetNormalisedNameAndRealm(GetUnitName("player", true))
      for i = 1, GetNumGroupMembers() do
        local unit = prefix..i
        local playerNameRealm = GetUnitName(unit, true)
        if playerNameRealm then
          local normName = GetNormalisedNameAndRealm(playerNameRealm)
          if normName and normName ~= selfNameRealm then
            currentRoster[normName] = true

            local rec, added = self:AddPlayer(normName)
            -- Announce if appropriate
            local lastSeenTs = nil
            if rec and type(rec.sightings) == "table" and #rec.sightings > 0 then
              lastSeenTs = rec.sightings[#rec.sightings]
            end

            local isNewToRoster = onJoin or (self._lastRoster and not self._lastRoster[normName])
            if isNewToRoster and not added and lastSeenTs then
              self:AnnounceSeen(normName, lastSeenTs)
            end

            -- Record a sighting once per group session
            if rec and not self._seenThisGroup[normName] then
              rec:AddSighting(GetServerTime and GetServerTime() or time())
              self._seenThisGroup[normName] = self._groupSessionId
            end
          end
        end
      end

      -- update last roster set
      self._lastRoster = currentRoster
    end
  until not self._rosterPending
  self._rosterProcessing = false
end

function PermanentRecord.Core:OnGroupLeft()
  self:DebugLog("Group left; clearing session state")
  self._inGroup = false
  self._seenThisGroup = {}
  self._lastRoster = {}
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

function PermanentRecord.Core:ListPlayers()
  return tableKeysSorted(self.db.profile.players or {})
end

function PermanentRecord.Core:ListGuilds()
  return tableKeysSorted(self.db.profile.guilds or {})
end

function PermanentRecord.Core:ClearPlayers()
  local count = 0
  for _ in pairs(self.db.profile.players or {}) do count = count + 1 end
  self.db.profile.players = {}
  return count
end

function PermanentRecord.Core:ClearGuilds()
  local count = 0
  for _ in pairs(self.db.profile.guilds or {}) do count = count + 1 end
  self.db.profile.guilds = {}
  return count
end
