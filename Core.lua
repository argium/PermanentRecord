PermanentRecord.Core = {}

function PermanentRecord.Core:New(db)
  if not db then
    PR_LOG_ERROR("Database is required for initialization")
    error("Database is required for initialization")
  end
  self.db = db
  PR_LOG_INFO("Loaded with", #self.db.profile.records, "records.")
  return self
end

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

function PermanentRecord.Core:AddRecord(name, flag)
  -- TODO: name doesn't include the home realm so the addon won't work across realms
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

function PermanentRecord.Core:GetRecord(name)
  if not name:find("-") then
    local _, playerRealm = UnitFullName("player")
    if playerRealm then
      name = name .. "-" .. playerRealm
    end
  end
  PR_LOG_INFO("Getting record for player:", name)
  return self.db.profile.records[name]
end
