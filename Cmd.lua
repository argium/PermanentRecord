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
local strsub, strsplit, strlower, strmatch, strtrim = string.sub, string.split, string.lower, string.match, string.trim
