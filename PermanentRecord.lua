local AddonName, _ = ...
PermanentRecord = LibStub("AceAddon-3.0"):NewAddon("PermanentRecord", "AceConsole-3.0", "AceEvent-3.0")

--- Represents a comment on a player or guild.
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

--- Represents a player record.
---@class Player
---@field playerId string The player's name.
---@field comments Comment[] List of comments.
---@field fingerprint string Computed fingerprint for the battle.net account.
local Player = {}
Player.__index = Player

---Create a new Player.
---@param playerId string
---@param fingerprint string
---@return Player
function Player:New(playerId, fingerprint)
  local self = setmetatable({}, Player)
  self.playerId = playerId or ""
  self.comments = {}
  self.fingerprint = fingerprint or ""
  return self
end

---Add a comment to the player.
---@param comment Comment
function Player:AddComment(comment)
  table.insert(self.comments, comment)
end

--- Represents a guild record.
---@class Guild
---@field guildId string The guild's name.
---@field comments Comment[] List of comments.
local Guild = {}
Guild.__index = Guild

---Create a new Guild.
---@param guildId string
---@return Guild
function Guild:New(guildId)
  local self = setmetatable({}, Guild)
  self.guildId = guildId or ""
  self.comments = {}
  return self
end

---Add a comment to the guild.
---@param comment Comment
function Guild:AddComment(comment)
  table.insert(self.comments, comment)
end

-- Export classes for use by other modules
PermanentRecord.Player = Player
PermanentRecord.Guild = Guild
PermanentRecord.Comment = Comment

local defaults = {
  profile = {
    debug = true, -- enable debug output
    players = {},
    guilds = {},
  },
}

-- Utility: count keys in a map-like table
local function CountMapKeys(t)
  local c = 0
  if t then for _ in pairs(t) do c = c + 1 end end
  return c
end

-- playerId
-- history
-- sightings
-- message history

function PermanentRecord:DebugLog(...)
  if self.db.profile.debug then
    print("["..AddonName.."]", ...)
  end
end

function PermanentRecord:Error(...)
  print("|cffaa0000["..AddonName.."]", ...)
end

function PermanentRecord:OnInitialize()
  self.db = LibStub("AceDB-3.0"):New(AddonName.."DB", defaults, true)
  self.core = PermanentRecord.Core:New(self.db)
  PermanentRecord:RegisterChatCommand("pr", "HandleSlashCmd")
  self:DebugLog(AddonName.." enabled")
end

function PermanentRecord:HandleGroupEvent(event, ...)
  self:DebugLog(event)
  C_Timer.After(2, function()
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
      self.core:ProcessGroupRoster()
    elseif event == "GROUP_JOINED" then
      self:DebugLog("Group joined")
    elseif event == "GROUP_LEFT" then
      self:DebugLog("Group left")
    end
  end)
end

PermanentRecord:RegisterEvent("GROUP_ROSTER_UPDATE", "HandleGroupEvent")
PermanentRecord:RegisterEvent("GROUP_JOINED", "HandleGroupEvent")
PermanentRecord:RegisterEvent("GROUP_LEFT", "HandleGroupEvent")
PermanentRecord:RegisterEvent("PLAYER_ENTERING_WORLD", "HandleGroupEvent")

function PermanentRecord:HandleSlashCmd(input)
  local args = strsplittable(' ', input)
  local command = args[1] or ""

  if #args == 3 then
    if command == "get" or command == "g" then
      self:SlashGet(args)
      return
    elseif command == "add" or command == "a" then
      self:SlashAdd(args)
      return
    elseif command == "remove" or command == "rm" then
      self:SlashRemove(args)
      return
    end
  elseif command == "debug" then
    self.db.profile.debug = not self.db.profile.debug
    print("Debug mode is now", self.db.profile.debug and "enabled" or "disabled")
    return
  elseif command == "st" or command == "status" then
    print("PermanentRecord status:")
    print("  Profile:", self.db.keys.profile)
    print("  Debug mode:", self.db.profile.debug and "enabled" or "disabled")
    return
  end

  print("Available commands:")
  print("  pr get <player> - Get the record for a player")
  print("  pr add <player> - Add a player ")
  print("  pr help - Show this help message")
end

function PermanentRecord:SlashGet(args)
  local type = args[2] and args[2]:lower() or ""
  local value = args[3]

  local result = nil
  if type == "p" or type == "player" then
    result = self.core:GetPlayer(value)
  elseif type == "g" or type == "guild" then
    result = self.core:GetGuild(value)
  end

  if result then
    print("Record found:")
    print("  Type:", result.playerId and "Player" or "Guild")
    print("  ID:", result.playerId or result.guildId)
    if result.playerId and result.fingerprint and result.fingerprint ~= "" then
      print("  Fingerprint:", result.fingerprint)
    end
    print("  Comments:", #result.comments)
    for _, comment in ipairs(result.comments) do
      print("    -", comment.datetime, comment.zone, comment.text)
    end
    local pc = CountMapKeys(self.db.profile.players)
    local gc = CountMapKeys(self.db.profile.guilds)
    print("Totals:", "players="..pc..", guilds="..gc)
  else
    self:Error("No record found for", type, value)
  end
end

function PermanentRecord:SlashAdd(args)
  local type = args[2] and args[2]:lower() or ""
  local value = args[3]
  local success = false
  local rec = nil
  if type == "p" or type == "player" then
     rec, success = self.core:AddPlayer(value)
  elseif type == "g" or type == "guild" then
     rec, success = self.core:AddGuild(value)
  end
  if success then
    print("Added record for", type, value)
    print("  ID:", (rec and (rec.playerId or rec.guildId)) or value)
  else
    self:Error("Failed to add record for", type, value, "It may already exist or the name is invalid.")
    if rec then
      print("Existing ID:", rec.playerId or rec.guildId)
    end
  end
  local pc = CountMapKeys(self.db.profile.players)
  local gc = CountMapKeys(self.db.profile.guilds)
  print("Totals:", "players="..pc..", guilds="..gc)
end

function PermanentRecord:SlashRemove(args)
  local type = args[2] and args[2]:lower() or ""
  local value = args[3]
  local removed = false
  if type == "p" or type == "player" then
    removed = self.core:RemovePlayer(value)
  elseif type == "g" or type == "guild" then
    removed = self.core:RemoveGuild(value)
  end

  if removed then
    print("Removed record for", type, value)
  else
    self:Error("No record found for", type, value)
  end
  local pc = CountMapKeys(self.db.profile.players)
  local gc = CountMapKeys(self.db.profile.guilds)
  print("Totals:", "players="..pc..", guilds="..gc)
end
