local AddonName, PR = ...
PermanentRecord = LibStub("AceAddon-3.0"):NewAddon("PermanentRecord", "AceConsole-3.0", "AceEvent-3.0")

-- Map model classes from the shared addon table to the global addon object
PermanentRecord.Player = PR and PR.Player or PermanentRecord.Player
PermanentRecord.Guild = PR and PR.Guild or PermanentRecord.Guild
PermanentRecord.Comment = PR and PR.Comment or PermanentRecord.Comment

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
      PermanentRecord.Core.ProcessGroupRoster(self.core)
    elseif event == "GROUP_JOINED" then
      self:DebugLog("Group joined")
      PermanentRecord.Core.ProcessGroupRoster(self.core, true) -- flag that this is on join
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

-- Helpers to normalize type tokens and dispatch to core methods
local TYPE_ALIASES = {
  p = "player", player = "player", players = "player",
  g = "guild",  guild  = "guild",  guilds  = "guild",
}

local CORE_METHODS = {
  player = { get = "GetPlayer",  add = "AddPlayer",  remove = "RemovePlayer",  list = "ListPlayers",  clear = "ClearPlayers" },
  guild  = { get = "GetGuild",   add = "AddGuild",   remove = "RemoveGuild",   list = "ListGuilds",   clear = "ClearGuilds"  },
}

local function normalizeType(tok)
  return TYPE_ALIASES[(tok or ""):lower()]
end

local function coreCall(self, kind, action, ...)
  local methods = CORE_METHODS[kind]
  if not methods then return nil end
  local m = methods[action]
  local core = self and self.core
  if not (core and m and core[m]) then return nil end
  return core[m](core, ...)
end

-- Robust parser for "command type value with spaces". Always returns 3 strings.
local function parseSlash(input)
  input = tostring(input or "")
  local cmd, typ, rest = input:match("^%s*(%S+)%s*(%S*)%s*(.-)%s*$")
  return { cmd or "", typ or "", rest or "" }
end

function PermanentRecord:HandleSlashCmd(input)
  local args = parseSlash(input)
  local command = args[1] or ""

  if (command == "get" or command == "g") then
    if (args[2] ~= "" and args[3] ~= "") then
      self:SlashGet(args)
    else
      self:Error("Usage: pr get <player|guild> <name>")
    end
    return
  elseif (command == "add" or command == "a") then
    if (args[2] ~= "" and args[3] ~= "") then
      self:SlashAdd(args)
    else
      self:Error("Usage: pr add <player|guild> <name>")
    end
    return
  elseif (command == "remove" or command == "rm") then
    if (args[2] ~= "" and args[3] ~= "") then
      self:SlashRemove(args)
    else
      self:Error("Usage: pr remove <player|guild> <name>")
    end
    return
  elseif (command == "list" or command == "ls") then
    if (args[2] ~= "") then
      self:SlashList(args)
    else
      self:Error("Usage: pr list <player|guild>")
    end
    return
  elseif (command == "clear" or command == "cl") then
    if (args[2] ~= "") then
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
  local kind = normalizeType(args[2])
  local value = args[3]
  if not kind or value == "" then
    self:Error("Usage: pr get <player|guild> <name>")
    return
  end

  local result = coreCall(self, kind, "get", value)

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
      for i, s in ipairs(sightings) do
        if type(s) == "table" then
          print("    -", fmtDate(s.ts), s.zone or "")
        else
          print("    -", fmtDate(s))
        end
      end
    end
  else
    self:Error("No record found for", kind, value)
  end
end

function PermanentRecord:SlashAdd(args)
  local kind = normalizeType(args[2])
  local value = args[3]
  if not kind or value == "" then
    self:Error("Usage: pr add <player|guild> <name>")
    return
  end

  local rec, success = coreCall(self, kind, "add", value)

  if success then
    print("Added record for", kind, value)
    print("  ID:", (rec and (rec.playerId or rec.guildId)) or value)
  else
    self:Error("Failed to add record for", kind, value, "It may already exist or the name is invalid.")
    if rec then
      print("Existing ID:", rec.playerId or rec.guildId)
    end
  end
end

function PermanentRecord:SlashRemove(args)
  local kind = normalizeType(args[2])
  local value = args[3]
  if not kind or value == "" then
    self:Error("Usage: pr remove <player|guild> <name>")
    return
  end

  local removed = coreCall(self, kind, "remove", value) or false

  if removed then
    print("Removed record for", kind, value)
  else
    self:Error("No record found for", kind, value)
  end
end

function PermanentRecord:SlashList(args)
  local kind = normalizeType(args[2])
  if not kind then
    self:Error("Usage: pr list <player|guild>")
    return
  end

  local names = coreCall(self, kind, "list") or {}
  local label = (kind == "player") and "Players" or "Guilds"
  print(label.." ("..#names.."):")
  for _, n in ipairs(names) do print("  -", n) end
end

function PermanentRecord:SlashClear(args)
  local kind = normalizeType(args[2])
  if not kind then
    self:Error("Usage: pr clear <player|guild>")
    return
  end

  local count = coreCall(self, kind, "clear") or 0
  if kind == "player" then
    print("Cleared", count, "player records")
  else
    print("Cleared", count, "guild records")
  end
end
