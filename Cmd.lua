PermanentRecord.Cmd = {}
local addonName = ...
-- local options = {
--     name = addonName,
--     handler = PermanentRecord.Cmd,
--     type = 'group',
--     args = {
--         get = {
--             type = 'input',
--             name = "Get",
--             desc = 'Get a player\'s record, if it exists',
--             get = 'Get',
--             set = 'Get'
--         },
--         add = {
--           type = 'input',
--           name = "Add",
--           desc = 'Add a player',
--           get = 'Add',
--           set = 'Add',
--         }
--     },
-- }

function PermanentRecord.Cmd:Dispatch(core, input)
  if not core then
    PR_LOG_ERROR("Core is not initialized, cannot process command")
    return
  end

  local parts = strsplit(' ', input)
  local command = parts[1] or ""
  print("Input", input)
  print("Command", command)

  if command == "get" then
    self:Get(core, parts[2] or "")
  end

  if command == "add" then
    self:Add(core, parts[2] or "")
  end

  if command == "debug" then

  end

  -- print help
  if command == "help" or command == "" then
    print("Available commands:")
    print("  pr get <player> - Get the record for a player")
    print("  pr add <player> [flag] - Add a player with an optional flag (default is yellow)")
    print("  pr help - Show this help message")
  else
    print("Unknown command. Type 'pr help' for available commands.")
  end
end

function PermanentRecord.Cmd:Get(core, value)
  -- TODO: move this validation into core
  if not value or value == "" then
    print("Please provide a player name.")
    return
  end

  local record = self.core:GetRecord(value)
  if record then
    print("Record for", value, "exists with flag:", record.flag)
  else
    print("No record found for", value)
  end
end

function PermanentRecord.Cmd:Add(core, player, flag)
  if not player or player == "" then
    print("Please provide a player name.")
    return
  end

  flag = flag or FLAG_YELLOW
  if value == "" then
    print("Please provide a player name.")
    return
  end
  self.core:AddRecord(value, FLAG_YELLOW)
end
