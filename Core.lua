local AddonName, PR = ...
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
  return s:sub(1, 1):upper() .. s:sub(2):lower()
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

-- Determine current activity priority and displayable location name
-- Priority order (high -> low): raid (6) > mythic+ (5) > arena (4) > rated BG (3) > BG (2) > dungeon (1) > other (0)
local function GetCurrentActivity()
  local zone = (GetRealZoneText and GetRealZoneText()) or ""
  local prio = 0
  local inInst, instType = false, "none"
  if IsInInstance then inInst, instType = IsInInstance() end
  if inInst then
    local instName, difficultyID
    if GetInstanceInfo then
      local a, _, _, _, _, _, _, _, _, _, k = GetInstanceInfo()
      instName, difficultyID = a, k
    end
    if instName and instName ~= "" then zone = instName end
    if instType == "raid" then
      prio = 6
    elseif instType == "party" then
      if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() then
        prio = 5
      else
        prio = 1
      end
    elseif instType == "arena" then
      prio = 4
    elseif instType == "pvp" then
      local rated = C_PvP and C_PvP.IsRatedBattleground and C_PvP.IsRatedBattleground()
      prio = rated and 3 or 2
    else
      prio = 0
    end
    -- Fallback: some clients report keystone via difficultyID
    if prio == 1 and type(difficultyID) == "number" and difficultyID == 8 then
      prio = 5
    end
  end
  return zone, prio
end

---------------------------------------------------------------------------------------------
--  MODEL CLASSES (inlined)
---------------------------------------------------------------------------------------------

---@class Comment
---@field datetime string
---@field zone string
---@field text string
---@field author string
local Comment = {}
Comment.__index = Comment

function Comment:New(datetime, zone, text, author)
  local raw = { datetime = datetime, zone = zone, text = text, author = author }
  local c = PermanentRecord and PermanentRecord.Core and PermanentRecord.Core.SanitizeComment and
  PermanentRecord.Core:SanitizeComment(raw) or raw
  return setmetatable(c, Comment)
end

---@class Guild
---@field guildId string
---@field createdAt number
---@field comments Comment[]
local Guild = {}
Guild.__index = Guild

function Guild:New(guildId)
  ---@type Guild
  local self = setmetatable({}, Guild)
  self.guildId = tostring(guildId or "")
  self.createdAt = now()
  self.comments = {}
  return self
end

function Guild:AddComment(comment)
  local c = PermanentRecord and PermanentRecord.Core and PermanentRecord.Core.SanitizeComment and
  PermanentRecord.Core:SanitizeComment(comment) or nil
  if not c then return end
  table.insert(self.comments, c)
end

---@class Player
---@field playerId string
---@field createdAt number
---@field comments Comment[]
---@field fingerprint string
---@field sightings table[]
---@field firstSighting table|nil
---@field className string|nil
---@field classFile string|nil
---@field specId number|nil
---@field specName string|nil
---@field role string|nil
local Player = {}
Player.__index = Player

function Player:New(playerId, fingerprint)
  if not playerId or playerId == "" then
    PermanentRecord:Error("Player ID cannot be empty")
  end
  ---@type Player
  local self = setmetatable({}, Player)
  self.playerId = tostring(playerId or "")
  self.createdAt = now()
  self.comments = {}
  self.fingerprint = tostring(fingerprint or "")
  self.sightings = {}
  self.firstSighting = nil
  self.className = nil
  self.classFile = nil
  self.specId = nil
  self.specName = nil
  self.role = nil
  return self
end

function Player:AddComment(comment)
  local c = PermanentRecord and PermanentRecord.Core and PermanentRecord.Core.SanitizeComment and
  PermanentRecord.Core:SanitizeComment(comment) or nil
  if not c then return end
  table.insert(self.comments, c)
end

function Player:UpdateFromUnit(unit)
  if not unit or unit == "" then return end
  if UnitClass then
    local localized, classFile = UnitClass(unit)
    if localized and classFile then
      self.className = localized
      self.classFile = classFile
    end
  end
  if UnitGroupRolesAssigned then
    local role = UnitGroupRolesAssigned(unit)
    if role and role ~= "NONE" then
      self.role = role
    end
  end
  local specId
  if UnitIsUnit and UnitIsUnit(unit, "player") and GetSpecialization and GetSpecializationInfo then
    local idx = GetSpecialization()
    if idx then
      specId, self.specName = GetSpecializationInfo(idx)
    end
  elseif GetInspectSpecialization and GetSpecializationInfoByID then
    local sid = GetInspectSpecialization(unit)
    if sid and sid > 0 then
      local _, name, _, _, role = GetSpecializationInfoByID(sid)
      specId = sid
      self.specName = name
      if role and role ~= "" then
        self.role = role
      end
    end
  end
  if specId and specId > 0 then
    self.specId = specId
  end
end

function Player:AddSighting(ts, zone, guild, seenBy)
  ts = tonumber(ts) or now()
  zone = tostring(zone or "")
  guild = tostring(guild or "")
  local me = tostring(seenBy or (GetUnitName and GetUnitName("player", true)) or "")
  if not self.firstSighting then
    self.firstSighting = { ts = ts, zone = zone, guild = guild, seenBy = me }
  end
  table.insert(self.sightings, { ts = ts, zone = zone, guild = guild, seenBy = me })
  local max = 5
  local n = #self.sightings
  if n > max then
    for _ = 1, (n - max) do
      table.remove(self.sightings, 1)
    end
  end
end

-- Export classes to the shared addon table and global addon object
PR.Player = Player
PR.Guild = Guild
PR.Comment = Comment
if PermanentRecord then
  PermanentRecord.Player = Player
  PermanentRecord.Guild = Guild
  PermanentRecord.Comment = Comment
end

-- Rehydrate helpers: SavedVariables strip metatables; restore class methods and defaults
local function RehydratePlayer(rec, name)
  if type(rec) ~= "table" then return rec end
  local PlayerClass = PermanentRecord and PermanentRecord.Player
  if PlayerClass and (getmetatable(rec) ~= PlayerClass or type(rec.AddSighting) ~= "function") then
    setmetatable(rec, PlayerClass)
  end
  if type(rec.comments) ~= "table" then rec.comments = {} end
  if type(rec.sightings) ~= "table" then rec.sightings = {} end
  -- Backfill firstSighting for older data if missing, using the earliest available structured entry
  if rec.firstSighting == nil then
    local earliestTs, earliestEntry
    for i = 1, #rec.sightings do
      local entry = rec.sightings[i]
      if type(entry) == "table" then
        local tsCandidate = tonumber(entry.ts)
        if tsCandidate and tsCandidate > 0 and (not earliestTs or tsCandidate < earliestTs) then
          earliestTs = tsCandidate
          earliestEntry = entry
        end
      end
    end
    if earliestTs then
      rec.firstSighting = {
        ts = earliestTs,
        zone = tostring(earliestEntry.zone or ""),
        guild = tostring(earliestEntry.guild or ""),
        seenBy = tostring(earliestEntry.seenBy or ""),
      }
    end
  end
  rec.playerId = tostring(rec.playerId or name or "")
  rec.fingerprint = tostring(rec.fingerprint or "")
  return rec
end

local function RehydrateGuild(rec, name)
  if type(rec) ~= "table" then return rec end
  local GuildClass = PermanentRecord and PermanentRecord.Guild
  if GuildClass and (getmetatable(rec) ~= GuildClass) then
    setmetatable(rec, GuildClass)
  end
  if type(rec.comments) ~= "table" then rec.comments = {} end
  rec.guildId = tostring(rec.guildId or name or "")
  return rec
end

function PermanentRecord.Core:DebugLog(...)
  PermanentRecord:DebugLog(...)
end

-- Public helpers to avoid duplication across files
function PermanentRecord.Core:FormatDate(ts)
  return fmtDate(ts)
end

function PermanentRecord.Core:FormatTimeAgo(ts)
  ts = tonumber(ts)
  if not ts or ts <= 0 then return "unknown" end
  local nowTs = now()
  local diff = nowTs - ts
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

-- Normalize a comment table: trim strings and fill defaults
function PermanentRecord.Core:SanitizeComment(comment)
  if type(comment) ~= "table" then return nil end
  local trim = _G and _G.strtrim or function(s)
    s = tostring(s or ""); s = s:gsub("^%s+", ""):gsub("%s+$", ""); return s
  end
  local author = comment.author
  if not author or author == "" then
    author = (GetUnitName and GetUnitName("player", true)) or (UnitName and UnitName("player")) or ""
  end
  return {
    datetime = trim(tostring(comment.datetime or "")),
    zone = trim(tostring(comment.zone or "")),
    text = trim(tostring(comment.text or "")),
    author = trim(tostring(author or "")),
  }
end

---@class PermanentRecord.Core
---@field db AceDB-3.0
---@field debug boolean
---@return PermanentRecord.Core
function PermanentRecord.Core:New(db, debug)
  self.db = db
  self.debug = debug or false
  local ver = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(AddonName, 'Version')) or nil
  if not ver and type(_G) == 'table' then
    local getMeta = rawget(_G, 'GetAddOnMetadata')
    if type(getMeta) == 'function' then
      ver = getMeta(AddonName, 'Version')
    end
  end
  ver = ver or 'dev'
  self.db.global.addonVersion = ver
  if not self.db.global.dbVersion then
    self.db.global.dbVersion = 1 -- Initial version
  end
  -- Ensure profile tables exist
  self.db.profile.players = self.db.profile.players or {}
  self.db.profile.guilds = self.db.profile.guilds or {}

  -- Rehydrate saved data: SavedVariables strip metatables; restore class methods and defaults
  if type(self.db.profile.players) == "table" then
    for name, rec in pairs(self.db.profile.players) do
      self.db.profile.players[name] = RehydratePlayer(rec, name)
    end
  end
  if type(self.db.profile.guilds) == "table" then
    for name, rec in pairs(self.db.profile.guilds) do
      self.db.profile.guilds[name] = RehydrateGuild(rec, name)
    end
  end

  -- runtime state
  self._inGroup = IsInGroup() or false
  self._groupSessionId = 0
  self._seenThisGroup = {}
  self._lastRoster = {}
  self._sessionSighting = {}

  return self
end

function PermanentRecord.Core:AnnounceSeen(playerName, lastSeenTs)
  local msg
  if lastSeenTs and lastSeenTs > 0 then
    local rel = self:FormatTimeAgo(lastSeenTs) or "unknown"
    -- Avoid double 'ago' if rel already includes it
    if rel:sub(-4) == " ago" or rel == "just now" then
      msg = string.format("Last saw %s %s", playerName, rel)
    else
      msg = string.format("Last saw %s %s ago", playerName, rel)
    end
  else
    msg = string.format("Last saw %s unknown", playerName)
  end
  print("[" .. AddonName .. "]", msg)
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
      -- If persisted session was active but we are no longer in a group, mark it inactive
      if self.db and self.db.global then
        local sess = self.db.global.session
        if type(sess) == "table" and sess.active then
          sess.active = false
        end
      end
      self:DebugLog("Not in a group, skipping roster processing.")
    else
      -- entering a group session if previously not in group
      if not self._inGroup then
        local sess
        if self.db and self.db.global then
          self.db.global.session = self.db.global.session or {}
          sess = self.db.global.session
        end
        if sess and sess.active and type(sess.id) == "number" then
          -- Resume existing session across reload/disconnect
          self._inGroup = true
          self._groupSessionId = sess.id
          self._seenThisGroup = {}
          if type(sess.seen) == "table" then
            for name, seen in pairs(sess.seen) do
              if seen then self._seenThisGroup[name] = self._groupSessionId end
            end
          end
          self._lastRoster = type(sess.roster) == "table" and sess.roster or {}
          self._sessionSighting = {}
          self:DebugLog("Resuming group session", self._groupSessionId)
        else
          -- Start a new session
          self._inGroup = true
          local lastId = (sess and type(sess.lastId) == "number" and sess.lastId) or 0
          self._groupSessionId = lastId + 1
          self._seenThisGroup = {}
          self._lastRoster = {}
          self._sessionSighting = {}
          if sess then
            sess.active = true
            sess.id = self._groupSessionId
            sess.lastId = self._groupSessionId
            sess.seen = {}
            sess.prio = {}
            sess.roster = {}
            sess.startedAt = now()
          end
          self:DebugLog("Starting group session", self._groupSessionId)
        end
      end

      self:DebugLog("Processing group roster update")

      local prefix                   = IsInRaid() and "raid" or "party"
  local currentRoster            = {}

      local selfNameRealm            = GetNormalisedNameAndRealm(GetUnitName("player", true), true)
      local currentZone, currentPrio = GetCurrentActivity()
      for i = 1, GetNumGroupMembers() do
        local unit = prefix .. i
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
                end
              end

              local isNewToRoster = onJoin or (self._lastRoster and not self._lastRoster[normName])
              -- Suppress announcement if we've already seen this player during the current group session
              local alreadySeenThisSession = (self._seenThisGroup and self._seenThisGroup[normName] == self._groupSessionId)
              if isNewToRoster and not added and lastSeenTs and not alreadySeenThisSession then
                self:AnnounceSeen(normName, lastSeenTs)
              end

              -- Record a sighting once per group session (include guild name)
              if rec and not self._seenThisGroup[normName] then
                local guildName = ""
                if GetGuildInfo then
                  local gName = GetGuildInfo(unit)
                  if gName then guildName = gName end
                end
                rec:AddSighting(now(), currentZone, guildName, selfNameRealm)
                self._seenThisGroup[normName] = self._groupSessionId
                -- Track this sighting to allow upgrading zone when activity becomes more "interesting"
                self._sessionSighting[normName] = { sessionId = self._groupSessionId, prio = currentPrio, ref = rec.sightings[#rec.sightings] }
                -- Persist seen/prio in current session
                local sess = self.db and self.db.global and self.db.global.session
                if sess then
                  sess.seen = sess.seen or {}
                  sess.prio = sess.prio or {}
                  sess.seen[normName] = true
                  sess.prio[normName] = currentPrio
                end
              elseif rec and self._seenThisGroup[normName] == self._groupSessionId then
                -- Already recorded this session; if activity priority increased, lock to the first higher-priority zone
                local s = self._sessionSighting[normName]
                if s and s.sessionId == self._groupSessionId and type(s.prio) == "number" and currentPrio > s.prio and type(s.ref) == "table" then
                  s.ref.zone = currentZone
                  -- If this was also the first-ever sighting, update that display too
                  if rec.firstSighting and tonumber(rec.firstSighting.ts) == tonumber(s.ref.ts) then
                    rec.firstSighting.zone = currentZone
                  end
                  s.prio = currentPrio
                  local sess = self.db and self.db.global and self.db.global.session
                  if sess and sess.prio then
                    sess.prio[normName] = currentPrio
                  end
                end
              end
            end
          end
        end
      end

      self._lastRoster = currentRoster
      -- Persist roster at end of processing
      local sess = self.db and self.db.global and self.db.global.session
      if sess and sess.active then
        sess.roster = currentRoster
      end
    end
  until not self._rosterPending
  self._rosterProcessing = false
end

function PermanentRecord.Core:OnGroupLeft()
  self:DebugLog("Group left; clearing session state")
  self._inGroup = false
  self._seenThisGroup = {}
  self._lastRoster = {}
  self._sessionSighting = {}
  if self.db and self.db.global then
    local sess = self.db.global.session
    if type(sess) == "table" then
      sess.active = false
      sess.roster = {}
    end
  end
end

---------------------------------------------------------------------------------------------
---  PLAYER METHODS
---------------------------------------------------------------------------------------------

---@param name string Player name, assumed to be the player's realm if not provided.
---@param unit string|nil Optional unit token to populate class/spec
---@param preserveCase boolean|nil If true, preserve input name casing (used for programmatic additions)
---@return Player|nil player The Player instance if added or already exists, or nil if invalid name
---@return boolean added True if player was added, false if already exists or invalid
function PermanentRecord.Core:AddPlayer(name, unit, preserveCase)
  if not name or name == "" then
    return nil, false
  end
  local normName = GetNormalisedNameAndRealm(name, preserveCase)
  if not normName then
    return nil, false
  end
  local existing = self.db.profile.players[normName]
  if existing ~= nil then
    if unit and existing.UpdateFromUnit then
      existing:UpdateFromUnit(unit)
    end
    return existing, false
  end
  local player = PermanentRecord.Player:New(normName, "")
  if unit and player.UpdateFromUnit then
    player:UpdateFromUnit(unit)
  end
  self.db.profile.players[normName] = player
  return player, true
end

---@param name string Player name, assumed to be the player's realm if not provided.
---@return Player|nil record Record for the player, or nil if not found
function PermanentRecord.Core:GetPlayer(name)
  if not name or name == "" then
    return nil
  end
  local normName = GetNormalisedNameAndRealm(name)
  self:DebugLog("Getting record for player:", normName)
  return normName and self.db.profile.players[normName] or nil
end

---@param name string Player name, assumed to be the player's realm if not provided.
---@return boolean removed True if record was removed, false if no record found
function PermanentRecord.Core:RemovePlayer(name)
  if not name or name == "" then
    return false
  end
  local normName = GetNormalisedNameAndRealm(name)
  local players = self.db and self.db.profile and self.db.profile.players
  if type(players) == "table" and normName and players[normName] ~= nil then
    rawset(players, normName, nil)
    self:DebugLog("Removed record for player:", normName)
    return true
  else
    return false
  end
end

--- List all players in the database.
--- @return string[] players List of player names
function PermanentRecord.Core:ListPlayers()
  return tableKeysSorted(self.db.profile.players or {})
end

--- Clear all player records.
--- @return number count Number of records cleared
function PermanentRecord.Core:ClearPlayers()
  local count = 0
  for _ in pairs(self.db.profile.players or {}) do count = count + 1 end
  self.db.profile.players = {}
  return count
end

---------------------------------------------------------------------------------------------
---  GUILD METHODS
---------------------------------------------------------------------------------------------


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

--- Clear all guild records.
--- @return number count Number of records cleared
function PermanentRecord.Core:ClearGuilds()
  local count = 0
  for _ in pairs(self.db.profile.guilds or {}) do count = count + 1 end
  self.db.profile.guilds = {}
  return count
end

--- List all guilds in the database.
--- @return string[] guilds List of guild names
function PermanentRecord.Core:ListGuilds()
  return tableKeysSorted(self.db.profile.guilds or {})
end
