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

---Add a comment to the player.
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

--- Represents a guild record.
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
      self.core:ProcessGroupRoster(true) -- flag that this is on join
    elseif event == "GROUP_LEFT" then
      self:DebugLog("Group left")
    end
  end)
end

PermanentRecord:RegisterEvent("GROUP_ROSTER_UPDATE", "HandleGroupEvent")
PermanentRecord:RegisterEvent("GROUP_JOINED", "HandleGroupEvent")
PermanentRecord:RegisterEvent("GROUP_LEFT", "HandleGroupEvent")
PermanentRecord:RegisterEvent("PLAYER_ENTERING_WORLD", "HandleGroupEvent")

local function fmtDate(ts)
  if not ts or ts == 0 then return "" end
  return date("%Y-%m-%d %H:%M", ts)
end

function PermanentRecord:HandleSlashCmd(input)
  local args = strsplittable(' ', input)
  local command = args[1] or ""

  if (command == "get" or command == "g") then
    if #args == 3 then
      self:SlashGet(args)
    else
      self:Error("Usage: pr get <player|guild> <name>")
    end
    return
  elseif (command == "add" or command == "a") then
    if #args == 3 then
      self:SlashAdd(args)
    else
      self:Error("Usage: pr add <player|guild> <name>")
    end
    return
  elseif (command == "remove" or command == "rm") then
    if #args == 3 then
      self:SlashRemove(args)
    else
      self:Error("Usage: pr remove <player|guild> <name>")
    end
    return
  elseif (command == "list" or command == "ls") then
    if #args >= 2 then
      self:SlashList(args)
    else
      self:Error("Usage: pr list <player|guild>")
    end
    return
  elseif (command == "clear" or command == "cl") then
    if #args >= 2 then
      self:SlashClear(args)
    else
      self:Error("Usage: pr clear <player|guild>")
    end
    return
  elseif command == "debug" then
    self.db.profile.debug = not self.db.profile.debug
    print("Debug mode is now", self.db.profile.debug and "enabled" or "disabled")
    return
  elseif command == "st" or command == "status" then
    print("PermanentRecord status:")
    print("  Profile:", self.db.keys.profile)
    print("  Debug mode:", self.db.profile.debug and "enabled" or "disabled")
    local pc = CountMapKeys(self.db.profile.players)
    local gc = CountMapKeys(self.db.profile.guilds)
    print("  Totals:", "players="..pc..", guilds="..gc)
    return
  end

  print("Available commands:")
  print("  pr get <player|guild> <name> - Get the record")
  print("  pr add <player|guild> <name> - Add a record")
  print("  pr remove <player|guild> <name> - Remove a record")
  print("  pr list <player|guild> - List all names")
  print("  pr clear <player|guild> - Clear all records of that type")
  print("  pr help - Show this help message")
end

function PermanentRecord:SlashGet(args)
  local argType = args[2] and args[2]:lower() or ""
  local value = args[3]

  local result = nil
  if argType == "p" or argType == "player" then
    result = self.core:GetPlayer(value)
  elseif argType == "g" or argType == "guild" then
    result = self.core:GetGuild(value)
  end

  if result then
    print("Record found:")
    print("  Type:", result.playerId and "Player" or "Guild")
    print("  ID:", result.playerId or result.guildId)
    if result.createdAt then
      print("  Created:", fmtDate(result.createdAt))
    end
    if result.playerId and result.fingerprint and result.fingerprint ~= "" then
      print("  Fingerprint:", result.fingerprint)
    end
    -- Safely handle records that may not have a comments table (e.g., from older saved data)
    local comments = type(result.comments) == "table" and result.comments or {}
    print("  Comments:", #comments)
    for _, comment in ipairs(comments) do
      local dt = comment and comment.datetime or ""
      local zone = comment and comment.zone or ""
      local text = comment and comment.text or ""
      print("    -", dt, zone, text)
    end
    if result.playerId then
      local sightings = type(result.sightings) == "table" and result.sightings or {}
      print("  Sightings:", #sightings)
      for i, ts in ipairs(sightings) do
        print("    -", fmtDate(ts))
      end
    end
  else
    self:Error("No record found for", argType, value)
  end
end

function PermanentRecord:SlashAdd(args)
  local argType = args[2] and args[2]:lower() or ""
  local value = args[3]
  local success = false
  local rec = nil
  if argType == "p" or argType == "player" then
     rec, success = self.core:AddPlayer(value)
  elseif argType == "g" or argType == "guild" then
     rec, success = self.core:AddGuild(value)
  end
  if success then
    print("Added record for", argType, value)
    print("  ID:", (rec and (rec.playerId or rec.guildId)) or value)
  else
    self:Error("Failed to add record for", argType, value, "It may already exist or the name is invalid.")
    if rec then
      print("Existing ID:", rec.playerId or rec.guildId)
    end
  end
end

function PermanentRecord:SlashRemove(args)
  local argType = args[2] and args[2]:lower() or ""
  local value = args[3]
  local removed = false
  if argType == "p" or argType == "player" then
    removed = self.core:RemovePlayer(value)
  elseif argType == "g" or argType == "guild" then
    removed = self.core:RemoveGuild(value)
  end

  if removed then
    print("Removed record for", argType, value)
  else
    self:Error("No record found for", argType, value)
  end
end

function PermanentRecord:SlashList(args)
  local argType = args[2] and args[2]:lower() or ""
  if argType == "p" or argType == "player" or argType == "players" then
    local names = self.core:ListPlayers()
    print("Players ("..#names.."): ")
    for _, n in ipairs(names) do print("  -", n) end
  elseif argType == "g" or argType == "guild" or argType == "guilds" then
    local names = self.core:ListGuilds()
    print("Guilds ("..#names.."): ")
    for _, n in ipairs(names) do print("  -", n) end
  else
    self:Error("Usage: pr list <player|guild>")
  end
end

function PermanentRecord:SlashClear(args)
  local argType = args[2] and args[2]:lower() or ""
  if argType == "p" or argType == "player" or argType == "players" then
    local count = self.core:ClearPlayers()
    print("Cleared", count, "player records")
  elseif argType == "g" or argType == "guild" or argType == "guilds" then
    local count = self.core:ClearGuilds()
    print("Cleared", count, "guild records")
  else
    self:Error("Usage: pr clear <player|guild>")
  end
end
