local AddonName, PR = ...

---@class Player
---@field playerId string The player's name.
---@field createdAt number Unix epoch (server time) when this record was created.
---@field comments Comment[] List of comments.
---@field fingerprint string Computed fingerprint for the battle.net account.
---@field sightings table[] Last 5 times this player was seen in your group. Each entry is a table { ts = number, zone = string, guild = string, seenBy = string } where seenBy is "Name-Realm" of your character at that time.
---@field firstSighting table|nil The first ever sighting { ts = number, zone = string, guild = string, seenBy = string }.
---@field className string|nil Localized class name (e.g., "Warrior").
---@field classFile string|nil Class file token (e.g., "WARRIOR").
---@field specId number|nil Specialization ID if known.
---@field specName string|nil Specialization name if known.
---@field role string|nil Role if known (TANK, HEALER, DAMAGER).
local Player = {}
Player.__index = Player

---Create a new Player.
---@param playerId string
---@param fingerprint string
---@return Player
function Player:New(playerId, fingerprint)
  if not playerId or playerId == "" then
    PermanentRecord:Error("Player ID cannot be empty")
  end

  local self = setmetatable({}, Player)
  self.playerId = playerId
  self.createdAt = time()
  self.comments = {}
  self.fingerprint = fingerprint or ""
  self.sightings = {}
  self.firstSighting = nil
  -- class/spec info (filled when seen in a group with a valid unit)
  self.className = nil
  self.classFile = nil
  self.specId = nil
  self.specName = nil
  self.role = nil
  return self
end

---@param comment Comment
function Player:AddComment(comment)
  if type(comment) ~= "table" then return end
  comment.datetime = tostring(comment.datetime or "")
  comment.zone = tostring(comment.zone or "")
  comment.text = tostring(comment.text or "")
  table.insert(self.comments, comment)
end

---Attempt to update class and spec information from a unit token.
---@param unit string
function Player:UpdateFromUnit(unit)
  if not unit or unit == "" then return end
  -- Class
  if UnitClass then
    local localized, classFile = UnitClass(unit)
    if localized and classFile then
      self.className = localized
      self.classFile = classFile
    end
  end
  -- Role (cheap, no inspect needed)
  if UnitGroupRolesAssigned then
    local role = UnitGroupRolesAssigned(unit)
    if role and role ~= "NONE" then
      self.role = role
    end
  end
  -- Spec (best-effort)
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

---Add a sighting (time seen in a group). Keeps only the last 5.
---@param ts number Unix epoch timestamp
---@param zone string|nil Zone name where the sighting happened
---@param guild string|nil Guild name at the time of sighting
---@param seenBy string|nil Name-Realm of your character at the time of the sighting
function Player:AddSighting(ts, zone, guild, seenBy)
  ts = ts or (GetServerTime and GetServerTime() or time())
  zone = tostring(zone or "")
  guild = tostring(guild or "")
  local me = tostring(seenBy or (GetUnitName and GetUnitName("player", true)) or "")
  -- Preserve the very first sighting forever
  if not self.firstSighting then
    self.firstSighting = { ts = ts, zone = zone, guild = guild, seenBy = me }
  end
  table.insert(self.sightings, { ts = ts, zone = zone, guild = guild, seenBy = me })
  -- trim to last 5
  local max = 5
  if #self.sightings > max then
    -- remove oldest extras
    local excess = #self.sightings - max
    for _ = 1, excess do
      table.remove(self.sightings, 1)
    end
  end
end

-- Export class on the shared addon table
PR.Player = Player
