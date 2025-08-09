local AddonName, PR = ...

---@class Player
---@field playerId string The player's name.
---@field createdAt number Unix epoch (server time) when this record was created.
---@field comments Comment[] List of comments.
---@field fingerprint string Computed fingerprint for the battle.net account.
---@field sightings table[] Last 5 times this player was seen in your group. Each entry is a table { ts = number, zone = string }.
local Player = {}
Player.__index = Player

---Create a new Player.
---@param playerId string
---@param fingerprint string
---@return Player
function Player:New(playerId, fingerprint)
  local self = setmetatable({}, Player)
  self.playerId = playerId or ""
  self.createdAt = GetServerTime and GetServerTime() or time()
  self.comments = {}
  self.fingerprint = fingerprint or ""
  self.sightings = {}
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

---Add a sighting (time seen in a group). Keeps only the last 5.
---@param ts number Unix epoch timestamp
---@param zone string|nil Zone name where the sighting happened
function Player:AddSighting(ts, zone)
  ts = ts or (GetServerTime and GetServerTime() or time())
  zone = tostring(zone or "")
  table.insert(self.sightings, { ts = ts, zone = zone })
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
