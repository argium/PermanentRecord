local AddonName, PR = ...

---@class Comment
---@field datetime string The date and time of the comment.
---@field zone string The zone where the comment was made.
---@field text string The comment text.
---@field author string The author (Name-Realm) of the comment.
local Comment = {}
Comment.__index = Comment

---Create a new Comment.
---@param datetime string
---@param zone string
---@param text string
---@param author string|nil
---@return Comment
function Comment:New(datetime, zone, text, author)
  local self = setmetatable({}, Comment)
  local trim = _G.strtrim or function(s) return (s or ""):gsub("^%s+", ""):gsub("%s+$", "") end
  self.datetime = trim(tostring(datetime or ""))
  self.zone = trim(tostring(zone or ""))
  self.text = trim(tostring(text or ""))
  if not author or author == "" then
    author = (GetUnitName and GetUnitName("player", true)) or (UnitName and UnitName("player")) or ""
  end
  self.author = trim(tostring(author or ""))
  return self
end

-- Export class on the shared addon table
PR.Comment = Comment
