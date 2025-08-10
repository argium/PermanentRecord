local AddonName, _ = ...
PermanentRecord.Core = {}

-- Unified time helper
local function now()
  return (GetServerTime and GetServerTime() or time())
end

-- Shared helper: optionally capitalize first letter and lower the rest, or preserve as-is
local function ToNormalisedCase(name, preserveCase)
  local s = tostring(name or "")
  if s == "" then return nil end
  if preserveCase then
    return s
  end
  return s:sub(1,1):upper() .. s:sub(2):lower()
end

---@param name string Player name, with or without realm.
---@param preserveCase boolean|nil If true, preserve input name casing; if false/nil, capitalize the character name
---@return string|nil name Player name with realm if not provided, nil if name is empty
local function GetNormalisedNameAndRealm(name, preserveCase)
  if not name or name == "" then
    return nil
  end
  -- Ensure realm present
  local char, realm = name:match("^([^%-]+)%-(.+)$")
  if not char then
    char = name
    local _, playerRealm = UnitFullName("player")
    if playerRealm and playerRealm ~= "" then
      realm = playerRealm
    else
      realm = ""
    end
  end
  -- Optionally capitalize character name (first letter upper, rest lower); always preserve realm casing
  char = ToNormalisedCase(char, preserveCase) or ""
  if realm ~= "" then
    return char .. "-" .. realm
  else
    return char
  end
end

---@param name string Guild name
---@param preserveCase boolean|nil If true, preserve input name casing; if false/nil, capitalize the first letter and lower the rest
---@return string|nil guildName Normalised guild name or nil if empty
local function GetNormalisedGuildName(name, preserveCase)
  return ToNormalisedCase(name, preserveCase)
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

  -- runtime state
  self._inGroup = IsInGroup() or false
  self._groupSessionId = 0
  self._seenThisGroup = {}
  self._lastRoster = {}

  return self
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

      local selfNameRealm = GetNormalisedNameAndRealm(GetUnitName("player", true), true)
      local currentZone = (GetRealZoneText and GetRealZoneText()) or ""
      for i = 1, GetNumGroupMembers() do
        local unit = prefix..i
        -- Only consider real, playable characters
        if UnitIsPlayer and UnitIsPlayer(unit) then
          local playerNameRealm = GetUnitName(unit, true)
          if playerNameRealm then
            local normName = GetNormalisedNameAndRealm(playerNameRealm, true)
            if normName and normName ~= selfNameRealm then
              currentRoster[normName] = true

              local rec, added = self:AddPlayer(normName, unit, true)
              -- Announce if appropriate
              local lastSeenTs = nil
              if rec and type(rec.sightings) == "table" and #rec.sightings > 0 then
                local last = rec.sightings[#rec.sightings]
                if type(last) == "table" then
                  lastSeenTs = tonumber(last.ts) or nil
                else
                  lastSeenTs = tonumber(last) or nil
                end
              end

              local isNewToRoster = onJoin or (self._lastRoster and not self._lastRoster[normName])
              if isNewToRoster and not added and lastSeenTs then
                self:AnnounceSeen(normName, lastSeenTs)
              end

              -- Record a sighting once per group session (include guild name)
              if rec and not self._seenThisGroup[normName] then
                local guildName = ""
                if GetGuildInfo then
                  local gName = GetGuildInfo(unit)
                  if gName then guildName = gName end
                end
                assert(type(rec.AddSighting) == "function", "PermanentRecord.Player is missing AddSighting()")
                rec:AddSighting(now(), currentZone, guildName)
                self._seenThisGroup[normName] = self._groupSessionId
              end
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
---@param unit string|nil Optional unit token to populate class/spec
---@param preserveCase boolean|nil If true, preserve input name casing (used for programmatic additions)
---@return Player|nil player The Player instance if added or already exists, or nil if invalid name
---@return boolean added True if player was added, false if already exists or invalid
function PermanentRecord.Core:AddPlayer(name, unit, preserveCase)
  if not name or name == "" then
    return nil, false
  end
  name = GetNormalisedNameAndRealm(name, preserveCase)
  if not name then
    return nil, false
  end
  local existing = self.db.profile.players[name]
  if existing ~= nil then
    if unit and existing.UpdateFromUnit then
      existing:UpdateFromUnit(unit)
    end
    return existing, false
  end
  local player = PermanentRecord.Player:New(name, "")
  if unit and player.UpdateFromUnit then
    player:UpdateFromUnit(unit)
  end
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
  local players = self.db and self.db.profile and self.db.profile.players
  if type(players) == "table" and players[name] ~= nil then
    rawset(players, name, nil)
    self:DebugLog("Removed record for player:", name)
    return true
  else
    return false
  end
end

---@param name string Guild name
---@param preserveCase boolean|nil If true, preserve input name casing (used for programmatic additions)
---@return Guild|nil guild The Guild instance if added or already exists, or nil if invalid
---@return boolean added True if guild was added, false if already exists or invalid
function PermanentRecord.Core:AddGuild(name, preserveCase)
  local guildName = GetNormalisedGuildName(name, preserveCase)
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
---@param preserveCase boolean|nil If true, preserve input name casing when looking up
---@return Guild|nil record Record for the guild, or nil if not found
function PermanentRecord.Core:GetGuild(name, preserveCase)
  local guildName = GetNormalisedGuildName(name, preserveCase)
  if not guildName then
    return nil
  end
  self:DebugLog("Getting record for guild:", guildName)
  return self.db.profile.guilds[guildName]
end

---@param name string Guild name
---@param preserveCase boolean|nil If true, preserve input name casing when removing
---@return boolean removed True if record was removed, false if no record found
function PermanentRecord.Core:RemoveGuild(name, preserveCase)
  local guildName = GetNormalisedGuildName(name, preserveCase)
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
