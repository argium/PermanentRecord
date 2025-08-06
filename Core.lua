PermanentRecord.Core = {}

---@enum Flag
PermanentRecord.Core.FLAG = {
	Red = 0,
	Yellow = 2,
	Green = 4,
}

---@param name string Player name, with or without realm.
---@return string|nil name Player name with realm if not provided, nil if name is empty
local function ToPlayerNameWithRealm(name)
  if not name or name == "" then
    return nil
  end
  if not name:find("-") then
    local _, playerRealm = UnitFullName("player")
    if playerRealm then
      name = name .. "-" .. playerRealm
    end
  end
  return name
end

---@param db table Database object, must have a profile with records table
---@return table self The initialized Core object
function PermanentRecord.Core:New(db)
  if not db then
    PR_LOG_ERROR("Database is required for initialization")
    error("Database is required for initialization")
  end
  self.db = db
  PR_LOG_INFO("Loaded with", #self.db.profile.records, "records.")
  return self
end

--- Processes group roster change events to check if any players have records.
function PermanentRecord.Core:ProcessGroupRoster()
  if not IsInGroup() then
    PR_LOG_INFO("Not in a group, skipping roster processing.")
    return
  end

  PR_LOG_INFO("Processing group roster update")

  -- todo: add some locking mechanism to protect against race conditions

  local prefix  = IsInRaid() and "raid" or "party"

  local selfNameRealm = GetUnitName("player", true)
  for i = 1, GetNumGroupMembers() do
    local playerNameRealm = GetUnitName(prefix..i, true)
    if PermanentRecord.Core:GetRecord(playerNameRealm) then
      PR_LOG_INFO("I have seen this player before:", playerNameRealm)
    elseif playerNameRealm ~= selfNameRealm then
      PermanentRecord.Core:AddRecord(playerNameRealm, FLAG_YELLOW)
      PR_LOG_INFO("Adding new record for player:", playerNameRealm)
    end
  end
end

---@param name string Player name, assumed to be the player's realm if not provided.
---@param flag Flag Flag color.
function PermanentRecord.Core:AddRecord(name, flag)
  -- TODO: name doesn't include the home realm so the addon won't work across realms
  if not name or name == "" then
    PR_LOG_ERROR("Player name is required to add a record")
    return
  end
  name = ToPlayerNameWithRealm(name)
  if self.db.profile.records[name] then
    PR_LOG_ERROR("Error: Player ID already exists in records")
    return
  end
  local record = {
    playerId = name,
    flag = flag,
    history = {}
  }
  self.db.profile.records[name] = record
end

---@param name string Player name, assumed to be the player's realm if not provided.
---@return table|nil record Record for the player, or nil if not found
function PermanentRecord.Core:GetRecord(name)
  if not name or name == "" then
    PR_LOG_ERROR("Player name is required to get a record")
    return nil
  end
  name = ToPlayerNameWithRealm(name)
  PR_LOG_INFO("Getting record for player:", name)
  return self.db.profile.records[name]
end

---@param name string Player name, assumed to be the player's realm if not provided.
---@return boolean removed True if record was removed, false if no record found
function PermanentRecord.Core:RemoveRecord(name)
  if not name or name == "" then
    PR_LOG_ERROR("Player name is required to remove a record")
    return
  end
  name = ToPlayerNameWithRealm(name)
  if self.db.profile.records[name] then
    self.db.profile.records[name] = nil
    PR_LOG_INFO("Removed record for player:", name)
    return true
  else
    PR_LOG_ERROR("No record found for player:", name)
    return false
  end
end
