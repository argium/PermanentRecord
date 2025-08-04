PermanentRecord = LibStub("AceAddon-3.0"):NewAddon("PermanentRecord", "AceConsole-3.0", "AceEvent-3.0")

-- local options = {
--     name = "PermanentRecord",
--     handler = PermanentRecord,
--     type = 'group',
--     args = {
--         msg = {
--             type = 'input',
--             name = 'My Message',
--             desc = 'The message for my addon',
--             set = 'SetMyMessage',
--             get = 'GetMyMessage',
--         },
--         records = {

--         }
--     },
-- }
local defaults = {
    profile = {
        records = {}
    },
}

-- playerId
-- flag
-- history
FLAG_RED = 1
FLAG_YELLOW = 2
FLAG_GREEN = 3


function PermanentRecord:OnInitialize()
  self.db = LibStub("AceDB-3.0"):New("PermanentRecordDb", defaults, true)
  -- options.args.profile = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
  print("PermanentRecord loaded with", #self.db.profile.records, "records.")
end

function PermanentRecord:HandleGroupEvent(event, ...)
  print(event)
  C_Timer.After(2, function()
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
      for i=1,GetNumGroupMembers() do
        local name = GetRaidRosterInfo(i)
        if PermanentRecord:GetRecord(name) then
          print("I have seen this player before:", name)
        elseif name ~= UnitName("player") then
          PermanentRecord:AddRecord(name, FLAG_YELLOW)
          print("Adding new record for player:", name)
        end
      end
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
PermanentRecord:RegisterEvent("PLAYER_ENTERING_WORLD", "HandleGroupEvent")

function PermanentRecord:AddRecord(name, flag)
  -- TODO: name doesn't include the home realm so the addon won't work across realms
  if self.db.profile.records[name] then
    print("Error: Player ID already exists in records")
    return
  end
  local record = {
    playerId = name,
    flag = flag,
    history = {}
  }
  self.db.profile.records[name] = record
end

function PermanentRecord:GetRecord(name)
  return self.db.profile.records[name]
end


-- function PR_IterateRoster(maxGroup,index)
-- 	index = (index or 0) + 1
-- 	maxGroup = maxGroup or 8

-- 	if IsInRaid() then
-- 		if index > GetNumGroupMembers() then
-- 			return
-- 		end
-- 		local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML, combatRole = GetRaidRosterInfo(index)
-- 		if subgroup > maxGroup then
-- 			return ExRT.F.IterateRoster(maxGroup,index)
-- 		end
-- 		local guid = UnitGUID(name or "raid"..index)
-- 		name = name or ""
-- 		return index, name, subgroup, fileName, guid, rank, level, online, isDead, combatRole
-- 	else
-- 		local name, rank, subgroup, level, class, fileName, online, isDead, combatRole, _

-- 		local unit = index == 1 and "player" or "party"..(index-1)

-- 		local guid = UnitGUID(unit)
-- 		if not guid then
-- 			return
-- 		end

-- 		subgroup = 1
-- 		name, _ = UnitName(unit)
-- 		name = name or ""
-- 		if _ then
-- 			name = name .. "-" .. _
-- 		end
-- 		class, fileName = UnitClass(unit)

-- 		if UnitIsGroupLeader(unit) then
-- 			rank = 2
-- 		else
-- 			rank = 1
-- 		end

-- 		level = UnitLevel(unit)

-- 		if UnitIsConnected(unit) then
-- 			online = true
-- 		end

-- 		if UnitIsDeadOrGhost(unit) then
-- 			isDead = true
-- 		end

-- 		combatRole = UnitGroupRolesAssigned(unit)

-- 		return index, name, subgroup, fileName, guid, rank, level, online, isDead, combatRole
-- 	end
-- end
