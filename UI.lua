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
  scrollBG:SetColorTexture(0, 0, 0, 0.25)
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
    local trim = (_G and _G.strtrim) or
    function(s)
      s = tostring(s or ""); s = s:gsub("^%s+", ""); s = s:gsub("%s+$", ""); return s
    end
    local function doSave()
      local raw = frame.editBox:GetText() or ""
      local text = trim(raw)
      local pn = frame.playerName
      local unitToken = frame.unitToken
      if not (pn and text:match("%S")) then
        frame:Hide(); return
      end
      local rec = EnsurePlayerRecord(pn, unitToken)
      if rec then
        local idx = tonumber(frame.commentIndex)
        if idx and rec.comments and rec.comments[idx] then
          -- Edit existing comment (preserve original datetime/zone/author)
          rec.comments[idx].text = text
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
        -- Also refresh Browser profile pane if open on this player
        if PermanentRecord.UI.browserFrame and PermanentRecord.UI.browserFrame:IsShown() and PermanentRecord.UI.browserFrame.selectedName == pn then
          PermanentRecord.UI.browserFrame:ShowProfile(pn)
        end
      end
      frame:Hide()
    end
    frame.saveBtn:SetScript("OnClick", doSave)
    frame.editBox:SetScript("OnEnterPressed", function(box)
      if IsShiftKeyDown and IsShiftKeyDown() then
        box:Insert("\n")
        return
      end
      doSave()
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
    self.playerSummary:SetText(string.format("%s%s|r\nClass: %s\nLast grouped: %s\nComments: %d", colorCode, pn,
      rec.className or "?", lastSeenTxt, total))

    -- Clear existing display objects
    for _, child in ipairs(self.commentLines or {}) do child:Hide() end
    self.commentLines = self.commentLines or {}
    for _, child in ipairs(self.sightingLines or {}) do child:Hide() end
    self.sightingLines = self.sightingLines or {}

    local y = 10
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
        local line = string.format("|cff9d7dff%s|r |cffaaaaaa[%s]%s|r\n%s", c.zone ~= "" and c.zone or "?",
          c.datetime or "", author, c.text or "")
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

--------------------------------------------------------------------------------
---@diagnostic disable: undefined-global, undefined-field

local function ClassColorCode(classFile)
  local raidColors = rawget(_G, "RAID_CLASS_COLORS")
  local c = raidColors and raidColors[classFile or ""]
  if c then return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) end
  return "|cffffffff"
end

local function GetLastSeenTs(rec)
  if type(rec) ~= "table" then return 0 end
  local last = rec.sightings and rec.sightings[#rec.sightings]
  if type(last) == "table" and tonumber(last.ts) then return tonumber(last.ts) end
  if rec.firstSighting and tonumber(rec.firstSighting.ts) then return tonumber(rec.firstSighting.ts) end
  return tonumber(rec.createdAt or 0) or 0
end

local function GetPlayersSortedByLastSeen()
  local players = {}
  ---@diagnostic disable-next-line: undefined-field
  local map = (PermanentRecord.core and PermanentRecord.core.db and PermanentRecord.core.db.profile and PermanentRecord.core.db.profile.players) or
  {}
  for name, rec in pairs(map) do
    table.insert(players, { name = name, rec = rec, ts = GetLastSeenTs(rec) })
  end
  table.sort(players, function(a, b)
    if a.ts == b.ts then return a.name < b.name end
    return a.ts > b.ts
  end)
  return players
end

local function CreateBrowserFrame()
  local f = CreateFrame("Frame", "PermanentRecordBrowserFrame", UIParent, "BackdropTemplate")
  f:SetSize(920, 540)
  f:SetPoint("CENTER", 0, 40)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  f:SetBackdropColor(0, 0, 0, 0.9)

  -- Title / close
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  f.title:SetPoint("TOPLEFT", 15, -12)
  f.title:SetText("PermanentRecord")
  f.closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.closeBtn:SetSize(70, 22)
  f.closeBtn:SetPoint("TOPRIGHT", -12, -10)
  f.closeBtn:SetText("Close")
  f.closeBtn:SetScript("OnClick", function() f:Hide() end)

  -- Split panes (left list, right details). Right is wider
  local totalW = f:GetWidth()
  local totalH = f:GetHeight()
  local leftW = math.floor(totalW * 0.35)
  local rightW = totalW - leftW - 28 -- padding + divider

  -- Left pane (player list)
  local left = CreateFrame("Frame", nil, f, "BackdropTemplate")
  f.left = left
  left:SetPoint("TOPLEFT", 10, -40)
  left:SetSize(leftW, totalH - 60)
  left:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background" })
  left:SetBackdropColor(0, 0, 0, 0.35)

  left.header = left:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  left.header:SetPoint("TOPLEFT", 8, -8)
  left.header:SetText("Players (by last seen)")

  left.searchBox = CreateFrame("EditBox", nil, left, "InputBoxTemplate")
  left.searchBox:SetAutoFocus(false)
  left.searchBox:SetSize(leftW - 40, 22)
  left.searchBox:SetPoint("TOPLEFT", left.header, "BOTTOMLEFT", 0, -6)
  left.searchBox:SetText("")
  left.searchHint = left:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  left.searchHint:SetPoint("LEFT", left.searchBox, "RIGHT", 8, 0)
  left.searchHint:SetText("Filter…")
  left.searchBox:SetScript("OnTextChanged", function()
    f:RefreshList()
  end)
  left.searchBox:SetScript("OnEscapePressed", function(box)
    box:SetText("")
    box:ClearFocus()
    f:RefreshList()
  end)

  left.listScroll = CreateFrame("ScrollFrame", nil, left, "UIPanelScrollFrameTemplate")
  left.listScroll:SetPoint("TOPLEFT", 8, -60)
  left.listScroll:SetPoint("BOTTOMRIGHT", -28, 8)
  left.listContent = CreateFrame("Frame", nil, left.listScroll)
  left.listContent:SetSize(leftW - 50, 200)
  left.listScroll:SetScrollChild(left.listContent)

  -- Right pane (details)
  local right = CreateFrame("Frame", nil, f, "BackdropTemplate")
  f.right = right
  right:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
  right:SetPoint("BOTTOMRIGHT", -10, 10)
  right:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background" })
  right:SetBackdropColor(0, 0, 0, 0.2)

  -- Profile widgets (always visible on right)
  right.name = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
  right.name:SetPoint("TOPLEFT", 12, -10)
  right.meta = right:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  right.meta:SetPoint("TOPLEFT", right.name, "BOTTOMLEFT", 0, -8)
  right.meta:SetJustifyH("LEFT")
  right.meta:SetWidth(rightW - 24)

  right.actions = CreateFrame("Frame", nil, right)
  right.actions:SetPoint("TOPRIGHT", -10, -10)
  right.actions:SetSize(140, 24)
  right.addCommentBtn = CreateFrame("Button", nil, right.actions, "UIPanelButtonTemplate")
  right.addCommentBtn:SetSize(120, 22)
  right.addCommentBtn:SetPoint("RIGHT", 0, 0)
  right.addCommentBtn:SetText("Add Comment")

  local detailsScroll = CreateFrame("ScrollFrame", nil, right, "UIPanelScrollFrameTemplate")
  f.detailsScroll = detailsScroll
  -- Anchor below the meta block to avoid overlap regardless of meta height
  detailsScroll:SetPoint("TOPLEFT", right.meta, "BOTTOMLEFT", 0, -10)
  detailsScroll:SetPoint("BOTTOMRIGHT", -28, 10)
  local detailsContent = CreateFrame("Frame", nil, detailsScroll)
  f.detailsContent = detailsContent
  detailsContent:SetSize(300, 200)
  detailsScroll:SetScrollChild(detailsContent)

  f.listRows = {}
  f.detailLines = {}

  function f:UpdateSelectionHighlight()
    for _, row in ipairs(self.listRows) do
      if row and row.highlight then
        local isSel = (row.playerName == self.selectedName) and row:IsShown()
        row.highlight:SetShown(isSel)
      end
    end
  end

  function f:RefreshList(selectName)
    local data = GetPlayersSortedByLastSeen()
    -- filter by search text
    local filter = ""
    if self.left and self.left.searchBox then
      filter = (self.left.searchBox:GetText() or ""):lower()
    end
    if filter ~= "" then
      local filtered = {}
      for _, e in ipairs(data) do
        if tostring(e.name):lower():find(filter, 1, true) then
          table.insert(filtered, e)
        end
      end
      data = filtered
    end
    local y = -2
    local rowW = (self.left.listContent:GetWidth() or (leftW - 36))
    local function ensureRow(i)
      local row = self.listRows[i]
      if row then return row end
      row = CreateFrame("Button", nil, self.left.listContent)
      row:SetHeight(28)
      row:SetPoint("TOPLEFT", 0, 0)
      row:SetPoint("TOPRIGHT", 0, 0)
      row.bg = row:CreateTexture(nil, "BACKGROUND")
      row.bg:SetAllPoints()
      row.bg:SetColorTexture(1, 1, 1, 0.06)
      row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      row.name:SetPoint("TOPLEFT", 8, -4)
      row.info = row:CreateFontString(nil, "OVERLAY", "GameFontDisable")
      row.info:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
      row.info:SetWidth(rowW - 16)
      -- Hover overlay (shown on mouseover)
      row.hover = row:CreateTexture(nil, "HIGHLIGHT")
      row.hover:SetAllPoints()
      row.hover:SetColorTexture(1, 1, 1, 0.08)
      row.hover:Hide()
      -- Selected highlight (persistent for current row)
      row.highlight = row:CreateTexture(nil, "ARTWORK")
      row.highlight:SetAllPoints()
      row.highlight:SetColorTexture(1, 1, 1, 0.16)
      row.highlight:Hide()
      row:SetScript("OnEnter", function()
        row.hover:Show()
      end)
      row:SetScript("OnLeave", function()
        row.hover:Hide()
      end)
      self.listRows[i] = row
      return row
    end

    local selected = selectName or self.selectedName
    for i, entry in ipairs(data) do
      local row = ensureRow(i)
      row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, y); row:SetPoint("TOPRIGHT", 0, y)
      row:SetWidth(rowW)
      local rec = entry.rec
      local color = ClassColorCode(rec.classFile)
      row.name:SetText(string.format("%s%s|r", color, entry.name))
      local lastTxt = (entry.ts > 0) and PermanentRecord.Core:FormatTimeAgo(entry.ts) or "never"
      row.info:SetText(lastTxt)
      row.playerName = entry.name
      row.bg:Hide(); if (i % 2 == 0) then row.bg:Show() end
      row:SetScript("OnClick", function()
        self.selectedName = entry.name
        if PermanentRecord and PermanentRecord.db and PermanentRecord.db.profile then
          PermanentRecord.db.profile.lastSelectedPlayer = entry.name
        end
        self:ShowProfile(entry.name)
        self:UpdateSelectionHighlight()
      end)
  row.highlight:SetShown(selected == entry.name)
      row:Show()
      y = y - row:GetHeight() - 2
    end

    -- Ensure highlights are correct after (re)build
    self:UpdateSelectionHighlight()

    -- hide extra rows
    for i = #data + 1, #self.listRows do
      self.listRows[i]:Hide()
    end
    self.left.listContent:SetHeight(-y + 10)
  end

  function f:ShowProfile(name)
    local rec = name and PermanentRecord.Core.GetPlayer(PermanentRecord.core, name) or nil
    self.right.addCommentBtn:SetEnabled(rec ~= nil)
    self.right.addCommentBtn:SetScript("OnClick", function() if name then ShowAddCommentDialog(name) end end)
    if not rec then
      self.right.name:SetText("Select a player")
      self.right.meta:SetText("")
      for _, fs in ipairs(self.detailLines) do fs:Hide() end
      return
    end
    local color = ClassColorCode(rec.classFile)
    self.right.name:SetText(string.format("%s%s|r", color, name))
    local last = rec.sightings and rec.sightings[#rec.sightings]
    local lastTxt = last and PermanentRecord.Core:FormatTimeAgo(last.ts) or "never"
    local lastWhere = last and ((last.zone ~= "" and last.zone) or "?") or ""
    local firstTxt = (rec.firstSighting and rec.firstSighting.ts) and
    PermanentRecord.Core:FormatTimeAgo(rec.firstSighting.ts) or "?"
    local meta = {
      string.format("Class: %s", rec.className or "?"),
      string.format("Spec/Role: %s%s", rec.specName or "?", rec.role and (" / " .. rec.role) or ""),
      string.format("Last grouped: %s%s", lastTxt, lastWhere ~= "" and (" in " .. lastWhere) or ""),
      string.format("First grouped: %s", firstTxt),
      string.format("Comments: %d", (type(rec.comments) == "table" and #rec.comments) or 0),
    }
    self.right.meta:SetText(table.concat(meta, "\n"))

    -- Details body: list sightings (newest first)
    for _, fs in ipairs(self.detailLines) do fs:Hide() end
    local y = -2
    local function ensureLine(i)
      local fs = self.detailLines[i]
      if fs then return fs end
      fs = self.detailsContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fs:SetJustifyH("LEFT")
      self.detailLines[i] = fs
      return fs
    end
    local idx = 1
    local function addLine(text)
      local fs = ensureLine(idx)
      fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", 0, y)
      fs:SetWidth(self.right:GetWidth() - 48)
      fs:SetText(text)
      fs:Show()
      y = y - fs:GetStringHeight() - 6
      idx = idx + 1
    end
    addLine("|cffa992ffSightings|r")
    if rec.sightings then
      for i = #rec.sightings, 1, -1 do
        local s = rec.sightings[i]
        if type(s) == "table" then
          local ago = s.ts and PermanentRecord.Core:FormatTimeAgo(s.ts) or "?"
          local zone = (s.zone and s.zone ~= "" and s.zone) or "?"
          local guild = (s.guild and s.guild ~= "" and (" <" .. s.guild .. ">")) or ""
          local by = (s.seenBy and s.seenBy ~= "" and (" by " .. (s.seenBy:match("^([^%-]+)") or s.seenBy))) or ""
          addLine(string.format("Seen %s %s%s%s", ago, zone, guild, by))
        end
      end
    end
    -- Comments section
    addLine("|cffa992ffComments|r")
    if rec.comments and #rec.comments > 0 then
      for i = #rec.comments, 1, -1 do
        local c = rec.comments[i]
        if type(c) == "table" then
          local author = c.author and c.author ~= "" and (" |cff66c5ff@" .. c.author .. "|r") or ""
          local line = string.format("|cff9d7dff%s|r |cffaaaaaa[%s]%s|r\n%s", (c.zone ~= "" and c.zone) or "?",
            c.datetime or "", author, c.text or "")
          addLine(line)
        end
      end
    else
      addLine("No comments yet.")
    end
    self.detailsContent:SetHeight(-y + 10)
  end

  f:SetScript("OnShow", function(self)
    -- Load last selection from saved vars if none provided
    if not self.selectedName and PermanentRecord and PermanentRecord.db and PermanentRecord.db.profile then
      local saved = PermanentRecord.db.profile.lastSelectedPlayer
      if saved and saved ~= "" then
        -- ensure it still exists
        local exists = PermanentRecord.core and PermanentRecord.core.db and PermanentRecord.core.db.profile and
        PermanentRecord.core.db.profile.players and PermanentRecord.core.db.profile.players[saved]
        if exists then self.selectedName = saved end
      end
    end
    self:RefreshList(self.selectedName)
    if self.selectedName then self:ShowProfile(self.selectedName) end
  end)

  f:Hide()
  return f
end

function PermanentRecord.UI.ShowBrowser(selectedName)
  if InCombatLockdown and InCombatLockdown() then return end
  local frame = PermanentRecord.UI.browserFrame
  if not frame then
    frame = CreateBrowserFrame()
    PermanentRecord.UI.browserFrame = frame
  end
  -- Initialize selection: explicit > existing > saved var
  if selectedName then
    frame.selectedName = selectedName
  elseif not frame.selectedName and PermanentRecord and PermanentRecord.db and PermanentRecord.db.profile then
    local saved = PermanentRecord.db.profile.lastSelectedPlayer
    if saved and saved ~= "" then
      local exists = PermanentRecord.core and PermanentRecord.core.db and PermanentRecord.core.db.profile and
      PermanentRecord.core.db.profile.players and PermanentRecord.core.db.profile.players[saved]
      if exists then frame.selectedName = saved end
    end
  end
  frame:Show()
  frame:RefreshList(selectedName)
  if selectedName then frame:ShowProfile(selectedName) end
end

-- Optional helpers
PermanentRecord.ShowBrowser = PermanentRecord.UI.ShowBrowser
---@diagnostic enable: undefined-global
---@diagnostic enable: undefined-global
