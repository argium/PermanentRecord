local AddonName, NS = ...
PermanentRecord = LibStub("AceAddon-3.0"):NewAddon("PermanentRecord", "AceConsole-3.0", "AceEvent-3.0")

-- Map model classes from the shared addon table to the global addon object
PermanentRecord.Player = NS and NS.Player or PermanentRecord.Player
PermanentRecord.Guild = NS and NS.Guild or PermanentRecord.Guild
PermanentRecord.Comment = NS and NS.Comment or PermanentRecord.Comment

local defaults = {
  profile = {
    debug = false,
    players = {},
    guilds = {},
  },
}

function PermanentRecord:DebugLog(...)
  if self.db.profile.debug then
    print("[" .. AddonName .. "]", ...)
  end
end

function PermanentRecord:Error(...)
  print("|cffdd4444[" .. AddonName .. "]", ...)
end

function PermanentRecord:OnInitialize()
  self.db = LibStub("AceDB-3.0"):New(AddonName .. "DB", defaults, true)
  self.core = PermanentRecord.Core:New(self.db)
  PermanentRecord:RegisterChatCommand("pr", "HandleSlashCmd")
  self:DebugLog(AddonName .. " enabled")
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

-- Helper to add a formatted grouped line for a sighting to the tooltip
local function AddGroupedLine(tooltip, label, sighting)
  if not tooltip or not label or type(sighting) ~= "table" then return end
  local ts = tonumber(sighting.ts)
  local seenBy = sighting.seenBy
  if not ts or ts <= 0 then return end
  local ago = PermanentRecord.Core:FormatTimeAgo(ts)
  local suffix = ""
  if type(seenBy) == "string" and seenBy ~= "" then
    local nameOnly = seenBy:match("^([^%-]+)") or seenBy
    suffix = " on " .. nameOnly
  end
  tooltip:AddLine("|cff875cff" .. label .. ": " .. ago .. suffix)
end

local function UpdateTooltip(tooltip, data)
  if not tooltip then return end
  assert(PermanentRecord.core, "PermanentRecord core is not initialized")

  -- Don't add tooltip info while in combat
  if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
    return
  end

  local name, unit = tooltip:GetUnit()
  if not UnitIsPlayer(unit) then return end
  PermanentRecord:DebugLog("OnTooltipSetItem for unit:", name, unit)

  -- Use name with realm for lookup; core will normalize
  local fullName = GetUnitName(unit, true) or name
  if not fullName or fullName == "" then return end
  PermanentRecord:DebugLog("Looking up player:", fullName)

  local rec = PermanentRecord.Core.GetPlayer(PermanentRecord.core, fullName)
  if not rec then return end

  local firstSighting = rec.firstSighting
  AddGroupedLine(tooltip, "First grouped", firstSighting)

  -- Only show "Last grouped" if it differs from first (prevents duplicate line when first seen now)
  local lastSighting = rec.sightings and rec.sightings[#rec.sightings]
  if type(lastSighting) == "table" then
    local firstTs = type(firstSighting) == "table" and tonumber(firstSighting.ts) or nil
    local lastTs = tonumber(lastSighting.ts)
    if lastTs and (not firstTs or lastTs ~= firstTs) then
      AddGroupedLine(tooltip, "Last grouped", lastSighting)
    end
  end

  -- Most recent note
  local lastComment = rec.comments and rec.comments[#rec.comments]
  local note = lastComment and lastComment.text or nil
  if note and note ~= "" then
    tooltip:AddLine("|cff875cffNote: " .. note)
  end

  tooltip:Show()
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, UpdateTooltip);

---------------------------------------------------------------------------------------------
--  CONTEXT MENU: VIEW / ADD COMMENTS
---------------------------------------------------------------------------------------------

-- Lazy UI container
PermanentRecord.UI = PermanentRecord.UI or {}

local function GetSelectedPlayerName(contextData)
  if not contextData then return nil end
  -- Dragonflight style contextData often contains these keys
  if contextData.name and type(contextData.name) == "string" then
    return contextData.name
  end
  if contextData.unit and UnitExists and UnitExists(contextData.unit) then
    return GetUnitName(contextData.unit, true)
  end
  return nil
end

-- Ensure a player record exists and return it
local function EnsurePlayerRecord(fullName, unit)
  if not fullName or fullName == "" then return nil end
  local rec = PermanentRecord.Core.GetPlayer(PermanentRecord.core, fullName)
  if not rec and PermanentRecord.core then
    rec = PermanentRecord.Core.AddPlayer(PermanentRecord.core, fullName, unit)
  elseif rec and unit and rec.UpdateFromUnit then
    -- Refresh class/spec if we have a unit
    rec:UpdateFromUnit(unit)
  end
  return rec
end

---------------------------------------------------------------------------------------------
--  ADD COMMENT DIALOG
---------------------------------------------------------------------------------------------
local function CreateAddCommentFrame()
  local f = CreateFrame("Frame", "PermanentRecordAddCommentFrame", UIParent, "BackdropTemplate")
  f:SetSize(350, 180)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  f:SetBackdropColor(0, 0, 0, 0.8)

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  f.title:SetPoint("TOP", 0, -10)
  f.title:SetText("Add Comment")

  f.playerLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.playerLabel:SetPoint("TOPLEFT", 15, -40)
  f.playerLabel:SetText("")

  local eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  f.editBox = eb
  eb:SetMultiLine(true)
  eb:SetMaxLetters(500)
  eb:SetSize(320, 60)
  eb:SetPoint("TOPLEFT", f.playerLabel, "BOTTOMLEFT", 0, -8)
  eb:SetAutoFocus(true)
  eb:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)

  local scrollBG = f:CreateTexture(nil, "BACKGROUND")
  scrollBG:SetColorTexture(0,0,0,0.25)
  scrollBG:SetPoint("TOPLEFT", eb, -5, 5)
  scrollBG:SetPoint("BOTTOMRIGHT", eb, 5, -5)

  f.saveBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.saveBtn:SetSize(90, 22)
  f.saveBtn:SetPoint("BOTTOMRIGHT", -15, 15)
  f.saveBtn:SetText("Save")

  f.cancelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.cancelBtn:SetSize(70, 22)
  f.cancelBtn:SetPoint("RIGHT", f.saveBtn, "LEFT", -10, 0)
  f.cancelBtn:SetText("Cancel")
  f.cancelBtn:SetScript("OnClick", function() f:Hide() end)

  f:SetScript("OnShow", function()
    f.editBox:SetFocus()
  end)

  f:Hide()
  return f
end

local function ShowAddCommentDialog(playerName, unit)
  if InCombatLockdown and InCombatLockdown() then return end
  local frame = PermanentRecord.UI.addCommentFrame
  if not frame then
    frame = CreateAddCommentFrame()
    PermanentRecord.UI.addCommentFrame = frame
    frame.saveBtn:SetScript("OnClick", function()
      local text = frame.editBox:GetText() or ""
      local pn = frame.playerName
      local unitToken = frame.unitToken
      if pn and text:match("%S") then
        local rec = EnsurePlayerRecord(pn, unitToken)
        if rec then
          local ts = GetServerTime and GetServerTime() or time()
          local dt = date("%Y-%m-%d %H:%M", ts)
          local zone = (GetRealZoneText and GetRealZoneText()) or ""
          local comment = PermanentRecord.Comment:New(dt, zone, text)
          rec:AddComment(comment)
          -- Make an additional attempt to refresh class/spec if possible
          if unitToken and rec.UpdateFromUnit then
            rec:UpdateFromUnit(unitToken)
          end
          PermanentRecord:DebugLog("Added comment for", pn)
          if PermanentRecord.UI.viewCommentsFrame and PermanentRecord.UI.viewCommentsFrame:IsShown() and PermanentRecord.UI.viewCommentsFrame.playerName == pn then
            -- refresh comments view if open
            PermanentRecord.UI.viewCommentsFrame:Refresh()
          end
        end
      end
      frame:Hide()
    end)
  end
  frame.playerName = playerName
  frame.unitToken = unit
  frame.playerLabel:SetText("Player: |cffaaffff" .. (playerName or "") .. "|r")
  frame.editBox:SetText("")
  frame:Show()
end

---------------------------------------------------------------------------------------------
--  VIEW COMMENTS FRAME
---------------------------------------------------------------------------------------------
local function CreateViewCommentsFrame()
  local f = CreateFrame("Frame", "PermanentRecordViewCommentsFrame", UIParent, "BackdropTemplate")
  f:SetSize(420, 360)
  f:SetPoint("CENTER", 40, 20)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  f:SetBackdropColor(0, 0, 0, 0.9)

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  f.title:SetPoint("TOP", 0, -10)
  f.title:SetText("Player Comments")

  f.playerSummary = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.playerSummary:SetPoint("TOPLEFT", 15, -40)
  f.playerSummary:SetWidth(390)
  f.playerSummary:SetJustifyH("LEFT")

  -- ScrollFrame
  local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  f.scrollFrame = scrollFrame
  scrollFrame:SetPoint("TOPLEFT", f.playerSummary, "BOTTOMLEFT", 0, -8)
  scrollFrame:SetPoint("BOTTOMRIGHT", -30, 45)

  local content = CreateFrame("Frame", nil, scrollFrame)
  f.content = content
  content:SetSize(360, 200)
  scrollFrame:SetScrollChild(content)

  f.closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.closeBtn:SetSize(80, 22)
  f.closeBtn:SetPoint("BOTTOMRIGHT", -15, 15)
  f.closeBtn:SetText("Close")
  f.closeBtn:SetScript("OnClick", function() f:Hide() end)

  f.addBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.addBtn:SetSize(110, 22)
  f.addBtn:SetPoint("RIGHT", f.closeBtn, "LEFT", -10, 0)
  f.addBtn:SetText("Add Comment")
  f.addBtn:SetScript("OnClick", function()
    if f.playerName then
      ShowAddCommentDialog(f.playerName)
    end
  end)

  function f:Refresh()
    local pn = self.playerName
    if not pn then return end
    local rec = PermanentRecord.Core.GetPlayer(PermanentRecord.core, pn)
    if not rec then return end
    local class = rec.classFile or ""
  local raidColors = rawget(_G, "RAID_CLASS_COLORS")
  local classColor = raidColors and raidColors[class] or { r = 0.8, g = 0.8, b = 0.8 }
    local colorCode = string.format("|cff%02x%02x%02x", classColor.r * 255, classColor.g * 255, classColor.b * 255)
    local lastSight = rec.sightings and rec.sightings[#rec.sightings]
    local lastSeenTxt = lastSight and PermanentRecord.Core:FormatTimeAgo(lastSight.ts) or "never"
    local total = #rec.comments
    self.playerSummary:SetText(string.format("%s%s|r\nClass: %s\nLast grouped: %s\nComments: %d", colorCode, pn, rec.className or "?", lastSeenTxt, total))

    -- Clear previous comment fontstrings
    for _, child in ipairs(self.commentLines or {}) do
      child:Hide()
    end
    self.commentLines = self.commentLines or {}

    local y = -2
    local idx = 1
    local width = self.scrollFrame:GetWidth() - 25
    for i = total, 1, -1 do -- newest first
      local c = rec.comments[i]
      if type(c) == "table" then
        local fs = self.commentLines[idx]
        if not fs then
          fs = self.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
          self.commentLines[idx] = fs
          fs:SetWidth(width)
          fs:SetJustifyH("LEFT")
        end
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", 0, y)
        local line = string.format("|cff9d7dff%s|r |cffaaaaaa[%s]|r\n%s", c.zone ~= "" and c.zone or "?", c.datetime or "", c.text or "")
        fs:SetText(line)
        fs:Show()
        y = y - fs:GetStringHeight() - 10
        idx = idx + 1
      end
    end
    self.content:SetHeight(-y + 10)
  end

  f:SetScript("OnShow", function(self) self:Refresh() end)
  f:Hide()
  return f
end

local function ShowViewComments(playerName)
  if InCombatLockdown and InCombatLockdown() then return end
  local frame = PermanentRecord.UI.viewCommentsFrame
  if not frame then
    frame = CreateViewCommentsFrame()
    PermanentRecord.UI.viewCommentsFrame = frame
  end
  frame.playerName = playerName
  frame:Show()
  frame:Refresh()
end

---------------------------------------------------------------------------------------------
--  MENU INJECTION
---------------------------------------------------------------------------------------------
local unitMenus = {
  "MENU_UNIT_PLAYER",      -- original
  "MENU_UNIT_PARTY",
  "MENU_UNIT_RAID",
  "MENU_UNIT_RAID_PLAYER",
  "MENU_UNIT_FOCUS",
  "MENU_UNIT_TARGET",
  "MENU_UNIT_ARENAENEMY",
  "MENU_UNIT_ENEMY_PLAYER",
}

for _, menuName in ipairs(unitMenus) do
  Menu.ModifyMenu(menuName, function(owner, rootDescription, contextData)
    local fullName = GetSelectedPlayerName(contextData)
    local unit = contextData and contextData.unit or nil
    if not fullName or fullName == UnitName("player") then return end
    rootDescription:CreateDivider()
    rootDescription:CreateTitle("PermanentRecord")
    rootDescription:CreateButton("View Comments", function() ShowViewComments(fullName) end)
    rootDescription:CreateButton("Add Comment", function() ShowAddCommentDialog(fullName, unit) end)
  end)
end
