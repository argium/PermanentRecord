local AddonName, PR = ...

---@class Player
---@field playerId string The player's name.
---@field createdAt number Unix epoch (server time) when this record was created.
---@field comments Comment[] List of comments.
---@field fingerprint string Computed fingerprint for the battle.net account.
---@field sightings number[] Last 5 times this player was seen in your group (Unix epoch timestamps).
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
  table.insert(self.comments, comment)
end

---Add a sighting (time seen in a group). Keeps only the last 5.
---@param ts number Unix epoch timestamp
function Player:AddSighting(ts)
  ts = ts or (GetServerTime and GetServerTime() or time())
  table.insert(self.sightings, ts)
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
