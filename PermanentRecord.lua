print("PermanentRecord.lua loaded")

PermanentRecord = LibStub("AceAddon-3.0"):NewAddon("PermanentRecord", "AceConsole-3.0", "AceEvent-3.0")

local options = {
    name = "PermanentRecord",
    handler = PermanentRecord,
    type = 'group',
    args = {
        msg = {
            type = 'input',
            name = 'My Message',
            desc = 'The message for my addon',
            set = 'SetMyMessage',
            get = 'GetMyMessage',
        },
        records = {

        }
    },
}
local defaults = {
    profile = {
        msg = "Hello, World!",
    },
}

LibStub("AceConfig-3.0"):RegisterOptionsTable("PermanentRecord", options, {"pr"})

function PermanentRecord:GetMyMessage(info)
    return myMessageVar
end

function PermanentRecord:SetMyMessage(info, input)
    myMessageVar = input
end


function PermanentRecord:OnInitialize()
  print("PermanentRecord addon initialized")
  options.args.profile = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
  self.db = LibStub("AceDB-3.0"):New("PermanentRecordDb", defaults, true)
  self.db.profile.records = {}
  print("Database initialized:", self.db)
end


function PermanentRecord:HandleGroupEvent(event, ...)
  C_Timer.After(0.2, function()
    if event == "GROUP_ROSTER_UPDATE" then
      print("Group roster updated")
    elseif event == "GROUP_JOINED" then
      print("Group joined")
    elseif event == "GROUP_LEFT" then
      print("Group left")
    end
  end)
end
PermanentRecord:RegisterEvent("GROUP_ROSTER_UPDATE", "HandleGroupEvent")
PermanentRecord:RegisterEvent("GROUP_JOINED", "HandleGroupEvent")
PermanentRecord:RegisterEvent("GROUP_LEFT", "HandleGroupEvent")

function PermanentRecord:PLAYER_ENTERING_WORLD(event, ...)
  C_Timer.After(0.2, function()
    if event == "PLAYER_ENTERING_WORLD" then
      print("Player entering world")
    end
  end)
end
PermanentRecord:RegisterEvent("PLAYER_ENTERING_WORLD")

-- create an empty LUA class called PermanentRecord
PermanentRecordCore = {}
PermanentRecordCore.__index = PermanentRecordCore

-- playerId
-- flag
-- history
FLAG_RED = 1
FLAG_YELLOW = 2
FLAG_GREEN = 3

function PermanentRecordCore:new(config)
  local self = setmetatable({}, PermanentRecordCore)
  self.config = config or {}
  return self
end

function PermanentRecordCore:AddRecord(playerId, flag)
  if self.config.records[playerId] then
    print("Error: Player ID already exists in records")
    return
  end
  local record = {
    playerId = playerId,
    flag = flag,
    history = {}
  }
  self.config.records[playerId] = record
end
