local AddonName, PR = ...

---@class Comment
---@field datetime string The date and time of the comment.
---@field zone string The zone where the comment was made.
---@field text string The comment text.
local Comment = {}
Comment.__index = Comment

---Create a new Comment.
---@param datetime string
---@param zone string
---@param text string
---@return Comment
function Comment:New(datetime, zone, text)
  local self = setmetatable({}, Comment)
  self.datetime = datetime or ""
  self.zone = zone or ""
  self.text = text or ""
  return self
end

-- Export class on the shared addon table
PR.Comment = Comment
