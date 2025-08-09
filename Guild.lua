local AddonName, PR = ...

---@class Guild
---@field guildId string The guild's name.
---@field createdAt number Unix epoch (server time) when this record was created.
---@field comments Comment[] List of comments.
local Guild = {}
Guild.__index = Guild

---Create a new Guild.
---@param guildId string
---@return Guild
function Guild:New(guildId)
  local self = setmetatable({}, Guild)
  self.guildId = guildId or ""
  self.createdAt = GetServerTime and GetServerTime() or time()
  self.comments = {}
  return self
end

---@param comment Comment
function Guild:AddComment(comment)
  table.insert(self.comments, comment)
end

-- Export class on the shared addon table
PR.Guild = Guild
