-- UI.lua - tooltip enhancements, comment dialogs, and context menu integration
local AddonName, _ = ...

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
  if not PermanentRecord.core then return end
  -- Don't add while in combat
  if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then return end

  local name, unit = tooltip:GetUnit()
  if not unit or not UnitIsPlayer(unit) then return end
  -- Use name with realm for lookup; core will normalize
  local fullName = GetUnitName(unit, true) or name
  if not fullName or fullName == "" then return end

  local rec = PermanentRecord.Core.GetPlayer(PermanentRecord.core, fullName)
  if not rec then return end

  local firstSighting = rec.firstSighting
  AddGroupedLine(tooltip, "First grouped", firstSighting)

  local lastSighting = rec.sightings and rec.sightings[#rec.sightings]
  if type(lastSighting) == "table" then
    local firstTs = type(firstSighting) == "table" and tonumber(firstSighting.ts) or nil
    local lastTs = tonumber(lastSighting.ts)
    if lastTs and (not firstTs or lastTs ~= firstTs) then
      AddGroupedLine(tooltip, "Last grouped", lastSighting)
    end
  end

  local lastComment = rec.comments and rec.comments[#rec.comments]
  local note = lastComment and lastComment.text or nil
  if note and note ~= "" then
    tooltip:AddLine("|cff875cffNote: " .. note)
  end
  tooltip:Show()
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, UpdateTooltip)

--------------------------------------------------------------------------------
--  COMMENT UI
--------------------------------------------------------------------------------
PermanentRecord.UI = PermanentRecord.UI or {}

local function GetSelectedPlayerName(contextData)
  if not contextData then return nil end
  if contextData.name and type(contextData.name) == "string" then
    return contextData.name
  end
  if contextData.unit and UnitExists and UnitExists(contextData.unit) then
    return GetUnitName(contextData.unit, true)
  end
  return nil
end

local function EnsurePlayerRecord(fullName, unit)
  if not fullName or fullName == "" then return nil end
  local rec = PermanentRecord.Core.GetPlayer(PermanentRecord.core, fullName)
  if not rec and PermanentRecord.core then
    rec = PermanentRecord.Core.AddPlayer(PermanentRecord.core, fullName, unit)
  elseif rec and unit and rec.UpdateFromUnit then
    rec:UpdateFromUnit(unit)
  end
  return rec
end

-- Add Comment dialog
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

  f:SetScript("OnShow", function() f.editBox:SetFocus() end)
  f:Hide()
  return f
end

local function ShowAddCommentDialog(playerName, unit, editIndex)
  if InCombatLockdown and InCombatLockdown() then return end
  local frame = PermanentRecord.UI.addCommentFrame
  if not frame then
    frame = CreateAddCommentFrame()
    PermanentRecord.UI.addCommentFrame = frame
    frame.saveBtn:SetScript("OnClick", function()
      local text = frame.editBox:GetText() or ""
      local pn = frame.playerName
      local unitToken = frame.unitToken
      if not (pn and text:match("%S")) then frame:Hide(); return end
      local rec = EnsurePlayerRecord(pn, unitToken)
      if rec then
        if frame.commentIndex and rec.comments[frame.commentIndex] then
          -- Edit existing comment (preserve original datetime/zone/author)
          rec.comments[frame.commentIndex].text = text
        else
          -- Create new comment
            local ts = GetServerTime and GetServerTime() or time()
            local dt = date("%Y-%m-%d %H:%M", ts)
            local zone = (GetRealZoneText and GetRealZoneText()) or ""
            local author = (GetUnitName and GetUnitName("player", true)) or (UnitName and UnitName("player")) or ""
            local comment = PermanentRecord.Comment:New(dt, zone, text, author)
            rec:AddComment(comment)
        end
        if unitToken and rec.UpdateFromUnit then rec:UpdateFromUnit(unitToken) end
        if PermanentRecord.UI.viewCommentsFrame and PermanentRecord.UI.viewCommentsFrame:IsShown() and PermanentRecord.UI.viewCommentsFrame.playerName == pn then
          PermanentRecord.UI.viewCommentsFrame:Refresh()
        end
      end
      frame:Hide()
    end)
  end
  frame.playerName = playerName
  frame.unitToken = unit
  frame.commentIndex = editIndex -- nil for add
  if editIndex then
    frame.title:SetText("Edit Comment")
    frame.saveBtn:SetText("Update")
    local rec = PermanentRecord.Core.GetPlayer(PermanentRecord.core, playerName)
    if rec and rec.comments[editIndex] then
      frame.editBox:SetText(rec.comments[editIndex].text or "")
    else
      frame.editBox:SetText("")
    end
  else
    frame.title:SetText("Add Comment")
    frame.saveBtn:SetText("Save")
    frame.editBox:SetText("")
  end
  frame.playerLabel:SetText("Player: |cffaaffff" .. (playerName or "") .. "|r")
  frame:Show()
end

-- View Comments frame
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
  f.addBtn:SetScript("OnClick", function() if f.playerName then ShowAddCommentDialog(f.playerName) end end)

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

    -- Clear existing display objects
    for _, child in ipairs(self.commentLines or {}) do child:Hide() end
    self.commentLines = self.commentLines or {}
    for _, child in ipairs(self.sightingLines or {}) do child:Hide() end
    self.sightingLines = self.sightingLines or {}

    local y = -2
    local width = self.scrollFrame:GetWidth() - 25

    -- Sightings header and lines
    local function addSighting(text)
      local idx = #self.sightingLines + 1
      local fs = self.sightingLines[idx]
      if not fs then
        fs = self.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        self.sightingLines[idx] = fs
        fs:SetWidth(width)
        fs:SetJustifyH("LEFT")
      end
      fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", 0, y)
      fs:SetText(text)
      fs:Show()
      y = y - fs:GetStringHeight() - 4
    end

    local function fmtSighting(label, s)
      local ago = s.ts and PermanentRecord.Core:FormatTimeAgo(s.ts) or "?"
      local zone = (s.zone and s.zone ~= "" and s.zone) or "?"
      local guild = (s.guild and s.guild ~= "" and (" <" .. s.guild .. ">")) or ""
      local by = (s.seenBy and s.seenBy ~= "" and (" by " .. (s.seenBy:match("^([^%-]+)") or s.seenBy))) or ""
      return string.format("|cffc8b2ff%s|r %s %s%s%s", label, ago, zone, guild, by)
    end

    local addedAnySighting = false
    if rec.firstSighting and rec.firstSighting.ts then
      addSighting("|cffa992ffSightings|r")
      addSighting(fmtSighting("First", rec.firstSighting))
      addedAnySighting = true
    end
    local firstTs = rec.firstSighting and rec.firstSighting.ts or nil
    if rec.sightings then
      for i = #rec.sightings, 1, -1 do
        local s = rec.sightings[i]
        if type(s) == "table" and s.ts and s.ts ~= firstTs then
          if not addedAnySighting then
            addSighting("|cffa992ffSightings|r")
            addedAnySighting = true
          end
          addSighting(fmtSighting("Seen", s))
        end
      end
    end
    if addedAnySighting then
      y = y - 6 -- gap before comments
    end

    -- Comments list
    local idx = 1
    for i = total, 1, -1 do
      local c = rec.comments[i]
      if type(c) == "table" then
        local row = self.commentLines[idx]
        if not row then
          row = CreateFrame("Frame", nil, self.content)
          row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
          row.text:SetJustifyH("LEFT")
          row.editBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
          row.editBtn:SetSize(40, 18); row.editBtn:SetText("Edit")
          row.delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
          row.delBtn:SetSize(50, 18); row.delBtn:SetText("Delete")
          self.commentLines[idx] = row
        end
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, y)
        row:SetWidth(width)
        local author = c.author and c.author ~= "" and (" |cff66c5ff@" .. c.author .. "|r") or ""
        local line = string.format("|cff9d7dff%s|r |cffaaaaaa[%s]%s|r\n%s", c.zone ~= "" and c.zone or "?", c.datetime or "", author, c.text or "")
        row.text:ClearAllPoints(); row.text:SetPoint("TOPLEFT", 0, 0)
        row.text:SetWidth(width - 100)
        row.text:SetText(line)
        local textHeight = row.text:GetStringHeight()
        row.editBtn:ClearAllPoints(); row.editBtn:SetPoint("TOPRIGHT", 0, 0)
        row.delBtn:ClearAllPoints(); row.delBtn:SetPoint("TOPRIGHT", row.editBtn, "BOTTOMRIGHT", 0, -2)
        row:SetHeight(textHeight + 4 + row.editBtn:GetHeight() + row.delBtn:GetHeight())
        row:Show(); row.text:Show(); row.editBtn:Show(); row.delBtn:Show()
        local commentIndex = i
        row.editBtn:SetScript("OnClick", function() ShowAddCommentDialog(pn, nil, commentIndex) end)
        row.delBtn:SetScript("OnClick", function()
          table.remove(rec.comments, commentIndex)
          self:Refresh()
        end)
        y = y - row:GetHeight() - 8
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

--------------------------------------------------------------------------------
--  CONTEXT MENU INJECTION
--------------------------------------------------------------------------------
local unitMenus = {
  "MENU_UNIT_PLAYER",
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

-- Expose dialog functions if needed elsewhere
PermanentRecord.ShowAddCommentDialog = ShowAddCommentDialog
PermanentRecord.ShowViewComments = ShowViewComments
