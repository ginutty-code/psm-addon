-- ModelsBrowser/SpecialTames.lua
-- Special Tames panel — shows taming requirements with status indicators and filtering

local addonName = "PetStableManagement"
_G.PSM = _G.PSM or {}
local PSM = _G.PSM
PSM.SpecialTames = PSM.SpecialTames or {}

local ST = PSM.SpecialTames

-- ─────────────────────────────────────────────
-- Constants
-- ─────────────────────────────────────────────

local CFG = {
    PANEL_WIDTH    = 800,
    PANEL_HEIGHT   = 600,
    ROW_HEIGHT     = 22,
    CHECKBOX_SIZE  = 16,
    STATUS_SIZE    = 16,
    BUTTON_HEIGHT  = 25,
    BUTTON_WIDTH   = 100,
    PADDING        = 10,
    CARD_PADDING   = 8,
    HEADER_H       = 22,
    SEP_H          = 1,
    MORE_H         = 16,
    PARTIAL_ROWS   = 4,
    EXPANDED_ROWS  = 10,

    -- Grid layout for cards
    CARD_GAP       = 8,
    GRID_COLS      = 3,
    GRID_SPACING   = 8,
}

-- ─────────────────────────────────────────────
-- Derived card height helper
-- ─────────────────────────────────────────────

local function CardHeight(numRows)
    local rowSpacing  = 2
    local rowH        = CFG.ROW_HEIGHT + rowSpacing
    local contentPad  = CFG.CARD_PADDING * 2
    local headerBlock = CFG.HEADER_H + CFG.SEP_H
    -- Subtract one rowSpacing: no trailing gap after the last row
    return headerBlock + contentPad + (numRows * rowH) - rowSpacing + CFG.MORE_H
end

-- ─────────────────────────────────────────────
-- State management
-- ─────────────────────────────────────────────

local selectedRules      = {}
local selectedConditions = {}

-- Forward declarations
local UpdateSelectionNote
local UpdateSelectAllButton
local RepopulateRows

-- ─────────────────────────────────────────────
-- UI Helpers
-- ─────────────────────────────────────────────

local function CreateStatusIcon(parent, status)
    local icon = CreateFrame("Frame", nil, parent)
    icon:SetSize(CFG.STATUS_SIZE, CFG.STATUS_SIZE)

    local texture = icon:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints()
    texture:SetTexture("Interface\\RAIDFRAME\\ReadyCheck")

    if status == "met" then
        texture:SetTexCoord(0, 0.5, 0, 0.5)
    else
        texture:SetTexCoord(0.5, 1, 0.5, 1)
    end

    icon.texture = texture
    return icon
end

local function UpdateCardHeaderVisual(card)
    if not card.rows or #card.rows == 0 then return end
    local allSel, allInv, anyAct = true, true, false

    for _, row in ipairs(card.rows) do
        local state = selectedConditions[row.conditionName]
        if state ~= true      then allSel = false end
        if state ~= "inverted" then allInv = false end
        if state ~= nil        then anyAct = true  end
    end

    if allSel then
        card.catLabel:SetTextColor(0, 1, 0)
        if card.headerInvIcon then card.headerInvIcon:Hide() end
    elseif allInv then
        card.catLabel:SetTextColor(1, 0, 0)
        if not card.headerInvIcon then
            card.headerInvIcon = card.header:CreateTexture(nil, "OVERLAY")
            card.headerInvIcon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
            card.headerInvIcon:SetSize(14, 14)
            card.headerInvIcon:SetPoint("LEFT", card.catLabel, "RIGHT", 5, 0)
        end
        card.headerInvIcon:Show()
    elseif anyAct then
        card.catLabel:SetTextColor(1, 1, 1)
        if card.headerInvIcon then card.headerInvIcon:Hide() end
    else
        card.catLabel:SetTextColor(0.6, 0.6, 0.6)
        if card.headerInvIcon then card.headerInvIcon:Hide() end
    end
end

local function CreateCategoryCard(parent, groupName, cardW)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetWidth(cardW)
    card:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    card:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    card:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

    local header = CreateFrame("Button", nil, card)
    header:SetPoint("TOPLEFT",  card, "TOPLEFT",  0, 0)
    header:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
    header:SetHeight(CFG.HEADER_H)

    local hbg = header:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints()
    hbg:SetColorTexture(0.12, 0.12, 0.12, 1)

    local catLabel = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    catLabel:SetPoint("LEFT", header, "LEFT", CFG.CARD_PADDING, 0)
    catLabel:SetText(groupName)

    card.header    = header
    card.catLabel  = catLabel
    card.rows      = {}
    card.visibleRows = {}
    card.groupName = groupName

    return card
end

local function CreateRuleRow(parent, ruleKey, ruleData, yOffset)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetSize(CFG.PANEL_WIDTH - 2 * CFG.PADDING - 50, CFG.ROW_HEIGHT + CFG.CARD_PADDING * 2)
    row:EnableMouse(true)

    row:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    row:SetBackdropColor(0.08, 0.08, 0.08, 0.85)
    row:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)

    local P = CFG.CARD_PADDING

    local status     = PSM.TamingChecker.GetRuleStatus(ruleKey)
    local statusIcon = CreateStatusIcon(row, status)
    statusIcon:SetPoint("LEFT", row, "LEFT", P, 0)

    local checkbox = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    checkbox:SetSize(CFG.CHECKBOX_SIZE, CFG.CHECKBOX_SIZE)
    checkbox:SetPoint("LEFT", statusIcon, "RIGHT", 10, 0)

    row.UpdateVisual = function()
        local state = selectedRules[ruleKey]
        local check = checkbox:GetCheckedTexture()
        if state == nil then
            checkbox:SetChecked(false)
            check:SetAlpha(1)
            if checkbox.invertedTexture then checkbox.invertedTexture:Hide() end
        elseif state == true then
            checkbox:SetChecked(true)
            check:SetAlpha(1)
            if checkbox.invertedTexture then checkbox.invertedTexture:Hide() end
        elseif state == "inverted" then
            checkbox:SetChecked(true)
            check:SetAlpha(0)
            if not checkbox.invertedTexture then
                checkbox.invertedTexture = checkbox:CreateTexture(nil, "OVERLAY")
                checkbox.invertedTexture:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
                checkbox.invertedTexture:SetSize(CFG.CHECKBOX_SIZE, CFG.CHECKBOX_SIZE)
                checkbox.invertedTexture:SetPoint("CENTER", checkbox, "CENTER", 0, 0)
            end
            checkbox.invertedTexture:Show()
        end
    end

    row.UpdateVisual()

    checkbox:SetScript("OnClick", function(self)
        local state = selectedRules[ruleKey]
        if state == nil then
            selectedRules[ruleKey] = true
        elseif state == true then
            selectedRules[ruleKey] = "inverted"
        else
            selectedRules[ruleKey] = nil
        end
        row.UpdateVisual()
        UpdateSelectionNote(row:GetParent():GetParent():GetParent())
        UpdateSelectAllButton(row:GetParent():GetParent():GetParent())
    end)

    local parts = {}
    parts[#parts + 1] = ruleData.label

    if ruleData.hint then
        if ruleData.hint.plain then
            parts[#parts + 1] = " (" .. ruleData.hint.plain .. ")"
        else
            local mainParts = {}
            local suffixPart = nil

            if ruleData.hint.autoRace then
                mainParts[#mainParts + 1] = ruleData.hint.autoRace .. " (auto)"
            end
            if ruleData.hint.itemID then
                mainParts[#mainParts + 1] = string.format(
                    "|cff0070dd|Hpsmtaming:%s|h%s|h|r",
                    ruleKey,
                    ruleData.hint.itemName or ("Item #" .. ruleData.hint.itemID))
            end
            if ruleData.hint.questID then
                mainParts[#mainParts + 1] = string.format(
                    "|cff0070dd|Hpsmtaming:%s|h%s|h|r",
                    ruleKey,
                    ruleData.hint.questName or ("Quest #" .. ruleData.hint.questID))
            end

            if ruleData.hint.suffix then
                suffixPart = ruleData.hint.suffix
            end

            local hintStr = ""
            if #mainParts > 0 then
                hintStr = table.concat(mainParts, " or ")
            end
            if suffixPart then
                hintStr = hintStr ~= "" and (hintStr .. " " .. suffixPart) or suffixPart
            end
            if hintStr ~= "" then
                parts[#parts + 1] = " (" .. hintStr .. ")"
            end
        end
    end

    local color = (status == "met") and "|cff00ff00" or "|cffff4444"
    parts[1] = color .. parts[1] .. "|r"
    local fullText = table.concat(parts, "")

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT",  checkbox, "RIGHT",  10, 0)
    label:SetPoint("RIGHT", row,      "RIGHT",  -P, 0)
    label:SetJustifyH("LEFT")
    label:SetText(fullText)
    label:SetWordWrap(false)

    row:SetHyperlinksEnabled(true)
    row:SetScript("OnHyperlinkEnter", function(self, link)
        local rk   = link:match("psmtaming:(.+)")
        if not rk then return end
        local rule = PSM.TamingRules and PSM.TamingRules[rk]
        if rule and rule.hint then
            if rule.hint.itemID then
                GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                GameTooltip:SetHyperlink("item:" .. rule.hint.itemID)
                GameTooltip:Show()
            elseif rule.hint.questID then
                GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                GameTooltip:SetHyperlink("quest:" .. rule.hint.questID)
                GameTooltip:Show()
            end
        end
    end)
    row:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnHyperlinkClick", function(self, link, text, button)
        local rk   = link:match("psmtaming:(.+)")
        if not rk then return end
        local rule = PSM.TamingRules and PSM.TamingRules[rk]
        if rule and button == "LeftButton" then
            if rule.itemID then
                PSM.PopUpManager:ShowURLPopup("https://www.wowhead.com/item=" .. rule.itemID)
            elseif rule.hint and rule.hint.questID then
                PSM.PopUpManager:ShowURLPopup("https://www.wowhead.com/quest=" .. rule.hint.questID)
            end
        end
    end)

    row:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(ruleData.label, 1, 1, 1)
        GameTooltip:AddLine(ruleData.desc, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
        GameTooltip:Hide()
    end)
    row:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and self.checkbox then
            self.checkbox:Click()
        end
    end)

    row.checkbox   = checkbox
    row.statusIcon = statusIcon
    row.label      = label

    return row
end

local function CreateConditionRow(parent, conditionName, width, card)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetSize(width, CFG.ROW_HEIGHT)
    row:EnableMouse(true)

    row:SetBackdrop({ bgFile = nil, edgeFile = nil })
    row:SetBackdropColor(0.08, 0.08, 0.08, 0.85)
    row:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)

    local P = CFG.CARD_PADDING

    local checkbox = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    checkbox:SetSize(CFG.CHECKBOX_SIZE, CFG.CHECKBOX_SIZE)
    checkbox:SetPoint("LEFT", row, "LEFT", P, 0)

    row.UpdateVisual = function()
        local state = selectedConditions[conditionName]
        local check = checkbox:GetCheckedTexture()
        if state == nil then
            checkbox:SetChecked(false)
            check:SetAlpha(1)
            if checkbox.invertedTexture then checkbox.invertedTexture:Hide() end
        elseif state == true then
            checkbox:SetChecked(true)
            check:SetAlpha(1)
            if checkbox.invertedTexture then checkbox.invertedTexture:Hide() end
        elseif state == "inverted" then
            checkbox:SetChecked(true)
            check:SetAlpha(0)
            if not checkbox.invertedTexture then
                checkbox.invertedTexture = checkbox:CreateTexture(nil, "OVERLAY")
                checkbox.invertedTexture:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
                checkbox.invertedTexture:SetSize(CFG.CHECKBOX_SIZE, CFG.CHECKBOX_SIZE)
                checkbox.invertedTexture:SetPoint("CENTER", checkbox, "CENTER", 0, 0)
            end
            checkbox.invertedTexture:Show()
        end
    end

    row.UpdateVisual()

    checkbox:SetScript("OnClick", function(self)
        local state = selectedConditions[conditionName]
        if state == nil then
            selectedConditions[conditionName] = true
        elseif state == true then
            selectedConditions[conditionName] = "inverted"
        else
            selectedConditions[conditionName] = nil
        end
        row.UpdateVisual()

        if card then UpdateCardHeaderVisual(card) end
        local panel = PSM.state.specialTames
        if panel then
            UpdateSelectionNote(panel)
            UpdateSelectAllButton(panel)
        end
    end)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT",  checkbox, "RIGHT",  10, 0)
    label:SetPoint("RIGHT", row,      "RIGHT",  -P, 0)
    label:SetJustifyH("LEFT")
    label:SetText("|cffffffff" .. conditionName .. "|r")
    label:SetWordWrap(false)

    row:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    end)
    row:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    end)
    row:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and self.checkbox then
            self.checkbox:Click()
        end
    end)

    row.checkbox      = checkbox
    row.isCondition   = true
    row.conditionName = conditionName

    return row
end

-- ─────────────────────────────────────────────
-- Search filtering
-- ─────────────────────────────────────────────

local function RowMatchesTag(ruleKey, activeTag)
    if not activeTag or activeTag == "All Skills" or activeTag == "Conditions" then return true end
    local status = PSM.TamingChecker.GetRuleStatus(ruleKey)
    if activeTag == "Unlocked Skills" then return status == "met"     end
    if activeTag == "Locked Skills"   then return status == "not_met" end
    return true
end

local function RowMatchesQuery(ruleKey, ruleData, query)
    if query == "" then return true end
    if ruleData.label and ruleData.label:lower():find(query, 1, true) then return true end
    if ruleData.desc  and ruleData.desc:lower():find(query, 1, true)  then return true end
    if ruleKey:lower():find(query, 1, true) then return true end
    if ruleData.hint then
        if ruleData.hint.plain     and ruleData.hint.plain:lower():find(query, 1, true)     then return true end
        if ruleData.hint.itemName  and ruleData.hint.itemName:lower():find(query, 1, true)  then return true end
        if ruleData.hint.questName and ruleData.hint.questName:lower():find(query, 1, true) then return true end
        if ruleData.hint.autoRace  and ruleData.hint.autoRace:lower():find(query, 1, true)  then return true end
        if ruleData.hint.suffix    and ruleData.hint.suffix:lower():find(query, 1, true)    then return true end
    end
    return false
end

local function RowMatchesQueryCondition(conditionName, query)
    if query == "" then return true end
    if conditionName:lower():find(query, 1, true) then return true end
    return false
end

-- ─────────────────────────────────────────────
-- Update select all button
-- ─────────────────────────────────────────────

UpdateSelectAllButton = function(panel)
    if not panel.selectAllBtn then return end
    local hasIgnored, hasActive, hasInverted = false, false, false

    for _, row in ipairs(panel.ruleRows or {}) do
        local stateMap = row.isCondition and selectedConditions or selectedRules
        local state    = stateMap[row.ruleKey]
        if state == true        then hasActive   = true
        elseif state == "inverted" then hasInverted = true
        else                         hasIgnored  = true end
    end

    local btnText = "Select All"
    if hasIgnored then
        btnText = "Select All"
    elseif hasActive then
        btnText = "Invert All"
    elseif hasInverted then
        btnText = "Unselect All"
    end

    panel.selectAllBtn:SetText(btnText)
end

-- ─────────────────────────────────────────────
-- ReflowCards: column-fill layout (variable height)
-- Cards fill each column top-to-bottom before moving to the next,
-- so expanding a card only pushes cards in the same column downward.
-- ─────────────────────────────────────────────

function ST:ReflowCards(panel, cardList, scrollW, cardW, gap, cols)
    -- Track the Y cursor (negative = downward) for each column
    local colY = {}
    for c = 1, cols do
        colY[c] = -gap
    end

    for idx, card in ipairs(cardList) do
        -- Find the column whose cursor is closest to the top (least negative)
        local col = 1
        for c = 2, cols do
            if colY[c] > colY[col] then col = c end
        end

        local xOff = gap + (col - 1) * (cardW + gap)
        local h    = card.isExpanded and card.expandedHeight or card.partialHeight

        card:SetWidth(cardW)
        card:SetHeight(h)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", panel.scrollChild, "TOPLEFT", xOff, colY[col])

        colY[col] = colY[col] - h - gap
    end

    -- Scroll child height = absolute value of the deepest column bottom
    local minY = 0
    for c = 1, cols do
        if colY[c] < minY then minY = colY[c] end
    end
    panel.scrollChild:SetHeight(math.abs(minY) + gap)
end

-- ─────────────────────────────────────────────
-- Repopulate scroll content (search-aware)
-- ─────────────────────────────────────────────

RepopulateRows = function(panel, query, activeTag)
    query     = (query or ""):lower()
    activeTag = activeTag or panel.activeTag or "All Skills"

    -- Destroy existing rows
    for _, row in ipairs(panel.ruleRows or {}) do
        row:Hide()
        row:SetParent(nil)
    end
    panel.ruleRows = {}

    -- Destroy existing cards
    for _, card in ipairs(panel.categoryCards or {}) do
        card:Hide()
        card:SetParent(nil)
    end
    panel.categoryCards = {}

    local scrollChild = panel.scrollChild
    local yOffset     = 8
    local ruleCount   = 0

    if activeTag == "Conditions" then
        local numCols    = CFG.GRID_COLS
        local colSpacing = CFG.GRID_SPACING
        local scrollW    = CFG.PANEL_WIDTH - 50
        local colWidth   = math.floor((scrollW - colSpacing * (numCols + 1)) / numCols)
        local rowSpacing = 2

        local cardList   = {}
        local groupNames = {}
        for gName in pairs(PSM.ConditionGroups or {}) do
            table.insert(groupNames, gName)
        end
        table.sort(groupNames, function(a, b)
            local countA = #PSM.ConditionGroups[a]
            local countB = #PSM.ConditionGroups[b]
            if countA ~= countB then return countA < countB end
            return a < b
        end)

        for _, gName in ipairs(groupNames) do
            local members     = PSM.ConditionGroups[gName]
            local matches     = {}
            local groupMatches = RowMatchesQueryCondition(gName, query)

            for _, cName in ipairs(members) do
                if groupMatches or RowMatchesQueryCondition(cName, query) then
                    table.insert(matches, cName)
                end
            end

            if #matches > 0 then
                local card = CreateCategoryCard(scrollChild, gName, colWidth)

                -- Dynamic heights derived from actual row count
                local visiblePartial    = math.min(CFG.PARTIAL_ROWS, #matches)
                card.partialHeight      = CardHeight(visiblePartial)
                card.expandedHeight     = CardHeight(#matches)
                card.isExpanded         = false
                card:SetHeight(card.partialHeight)

                local currentContentY = CFG.HEADER_H + CFG.SEP_H + CFG.CARD_PADDING

                for idx, cName in ipairs(matches) do
                    local row = CreateConditionRow(card, cName, colWidth, card)
                    row:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -currentContentY)
                    row.ruleKey      = cName
                    row.isCondition  = true
                    table.insert(card.rows, row)
                    table.insert(panel.ruleRows, row)

                    currentContentY = currentContentY + CFG.ROW_HEIGHT + rowSpacing

                    row:SetShown(idx <= CFG.PARTIAL_ROWS)
                end

                -- "and X more" / "Show less" button
                local moreBtn = CreateFrame("Button", nil, card)
                moreBtn:SetSize(colWidth - 2 * CFG.CARD_PADDING, CFG.MORE_H)
                moreBtn:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", CFG.CARD_PADDING, CFG.CARD_PADDING)
                card.moreBtn = moreBtn

                local moreLabel = moreBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                moreLabel:SetPoint("CENTER")
                moreLabel:SetTextColor(unpack(PSM.Config.COLORS.PRIMARY))
                moreBtn.label = moreLabel

                if #matches > CFG.PARTIAL_ROWS then
                    moreBtn:Show()
                    moreLabel:SetText("and " .. (#matches - CFG.PARTIAL_ROWS) .. " more...")
                    moreBtn:SetScript("OnClick", function()
                        card.isExpanded = not card.isExpanded
                        card:SetHeight(card.isExpanded and card.expandedHeight or card.partialHeight)
                        moreLabel:SetText(
                            card.isExpanded
                            and "Show less"
                            or  ("and " .. (#matches - CFG.PARTIAL_ROWS) .. " more...")
                        )
                        for idx2, row in ipairs(card.rows) do
                            row:SetShown(card.isExpanded or idx2 <= CFG.PARTIAL_ROWS)
                        end
                        -- Reflow all cards so the column adjusts to the new height
                        ST:ReflowCards(panel, cardList, scrollW, colWidth, colSpacing, numCols)
                    end)
                else
                    moreBtn:Hide()
                end

                card.header:SetScript("OnClick", function()
                    local hasUnselected, hasTrue = false, false
                    for _, r in ipairs(card.rows) do
                        local st = selectedConditions[r.conditionName]
                        if st == nil  then hasUnselected = true end
                        if st == true then hasTrue = true end
                    end

                    local nextState
                    if hasUnselected then
                        nextState = true
                    elseif hasTrue then
                        nextState = "inverted"
                    else
                        nextState = nil
                    end

                    for _, r in ipairs(card.rows) do
                        selectedConditions[r.conditionName] = nextState
                        r.UpdateVisual()
                    end
                    UpdateCardHeaderVisual(card)
                    UpdateSelectionNote(panel)
                    UpdateSelectAllButton(panel)
                end)

                card.header:SetScript("OnEnter", function()
                    card:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
                    card.catLabel:SetTextColor(unpack(PSM.Config.COLORS.PRIMARY))
                end)
                card.header:SetScript("OnLeave", function()
                    card:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
                    UpdateCardHeaderVisual(card)
                end)

                UpdateCardHeaderVisual(card)
                table.insert(cardList, card)
                table.insert(panel.categoryCards, card)
            end
        end

        ST:ReflowCards(panel, cardList, scrollW, colWidth, colSpacing, numCols)

        ruleCount = #panel.ruleRows
    else
        for ruleKey, ruleData in pairs(PSM.TamingRules) do
            if ruleKey ~= "Sliver of N'Zoth" then
                if RowMatchesQuery(ruleKey, ruleData, query) and RowMatchesTag(ruleKey, activeTag) then
                    ruleCount = ruleCount + 1
                    local rowH = CFG.ROW_HEIGHT + CFG.CARD_PADDING * 2
                    local row  = CreateRuleRow(scrollChild, ruleKey, ruleData, yOffset)
                    row.ruleKey = ruleKey
                    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
                    panel.ruleRows[ruleCount] = row
                    yOffset = yOffset + rowH + 4
                end
            end
        end
    end

    scrollChild:SetHeight(math.max(yOffset + 8, 100))
    panel.scrollFrame:SetVerticalScroll(0)

    if panel.selectionNote then
        local n = 0
        for _, state in pairs(selectedRules)      do if state ~= nil then n = n + 1 end end
        for _, state in pairs(selectedConditions) do if state ~= nil then n = n + 1 end end
        panel.selectionNote:SetText(n .. " " .. (n == 1 and "item" or "items") .. " selected")
    end
    UpdateSelectAllButton(panel)
end

-- ─────────────────────────────────────────────
-- Pill bar (All | Unlocked | Locked | Conditions)
-- ─────────────────────────────────────────────

local PILL_TAGS = { "All Skills", "Unlocked Skills", "Locked Skills", "Conditions" }

local function CreatePillBar(panel)
    local pillBar = CreateFrame("Frame", nil, panel)
    pillBar:SetHeight(24)
    pillBar:SetPoint("TOPLEFT",  panel, "TOPLEFT",  20, -90)
    pillBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -20, -90)

    local pills = {}
    local xOff  = 0

    local function SetActive(activeIdx)
        for i, pill in ipairs(pills) do
            local active = (i == activeIdx)
            pill.tex:SetColorTexture(unpack(active and PSM.Config.TAB.ACTIVE_BG or PSM.Config.TAB.INACTIVE_BG))
            pill.label:SetTextColor(unpack(active and PSM.Config.TAB.ACTIVE_TEXT or PSM.Config.TAB.INACTIVE_TEXT))
            if pill.topLine    then pill.topLine:SetShown(active)    end
            if pill.bottomLine then pill.bottomLine:SetShown(active) end
        end
    end

    for idx, tagName in ipairs(PILL_TAGS) do
        local pill   = CreateFrame("Button", nil, pillBar)
        local labelW = #tagName * 7 + 16
        pill:SetSize(labelW, 20)
        pill:SetPoint("LEFT", pillBar, "LEFT", xOff, 0)

        local tex = pill:CreateTexture(nil, "BACKGROUND")
        tex:SetAllPoints()
        tex:SetColorTexture(unpack(PSM.Config.TAB.INACTIVE_BG))
        pill.tex = tex

        local label = pill:CreateFontString(nil, "OVERLAY")
        label:SetFont("Fonts\\FRIZQT__.TTF", PSM.Config.FONT_SIZES.ABILITY_PILL)
        label:SetPoint("CENTER")
        label:SetText(tagName)
        label:SetTextColor(unpack(PSM.Config.TAB.INACTIVE_TEXT))
        pill.label = label

        local topLine = pill:CreateTexture(nil, "BORDER")
        topLine:SetPoint("TOPLEFT",  pill, "TOPLEFT",  2, 0)
        topLine:SetPoint("TOPRIGHT", pill, "TOPRIGHT", -2, 0)
        topLine:SetHeight(1)
        topLine:SetColorTexture(unpack(PSM.Config.TAB.ACTIVE_BORDER))
        topLine:Hide()
        pill.topLine = topLine

        local bottomLine = pill:CreateTexture(nil, "BORDER")
        bottomLine:SetPoint("BOTTOMLEFT",  pill, "BOTTOMLEFT",  2, 0)
        bottomLine:SetPoint("BOTTOMRIGHT", pill, "BOTTOMRIGHT", -2, 0)
        bottomLine:SetHeight(1)
        bottomLine:SetColorTexture(unpack(PSM.Config.TAB.ACTIVE_BORDER))
        bottomLine:Hide()
        pill.bottomLine = bottomLine

        do
            local currentTag = tagName
            local currentIdx = idx
            pill:SetScript("OnClick", function()
                SetActive(currentIdx)
                panel.activeTag = currentTag
                RepopulateRows(panel, panel.searchBox:GetText(), currentTag)
            end)
        end

        xOff = xOff + labelW + 6
        pills[idx] = pill
    end

    SetActive(1)
    panel.pills = pills
    return pillBar
end

-- ─────────────────────────────────────────────
-- Status refresh
-- ─────────────────────────────────────────────

local function UpdateAllStatuses(panel)
    for _, row in ipairs(panel.ruleRows or {}) do
        if row.ruleKey and not row.isCondition then
            local status = PSM.TamingChecker.GetRuleStatus(row.ruleKey)
            if status == "met" then
                row.statusIcon.texture:SetTexCoord(0, 0.5, 0, 0.5)
            else
                row.statusIcon.texture:SetTexCoord(0.5, 1, 0.5, 1)
            end
        end
    end
end

-- ─────────────────────────────────────────────
-- Selection note helper
-- ─────────────────────────────────────────────

UpdateSelectionNote = function(panel)
    if not panel.selectionNote then return end
    local n = 0
    for _, state in pairs(selectedRules)      do if state ~= nil then n = n + 1 end end
    for _, state in pairs(selectedConditions) do if state ~= nil then n = n + 1 end end
    panel.selectionNote:SetText(n .. " " .. (n == 1 and "item" or "items") .. " selected")
end

-- ─────────────────────────────────────────────
-- Button handlers
-- ─────────────────────────────────────────────

local function OnSelectAllClick(panel)
    local hasIgnored, hasActive = false, false
    for _, row in ipairs(panel.ruleRows or {}) do
        local stateMap = row.isCondition and selectedConditions or selectedRules
        local state    = stateMap[row.ruleKey]
        if state == nil  then hasIgnored = true end
        if state == true then hasActive  = true end
    end

    local newState
    if hasIgnored    then newState = true
    elseif hasActive then newState = "inverted"
    else                  newState = nil end

    for _, row in ipairs(panel.ruleRows or {}) do
        if row.ruleKey then
            local stateMap = row.isCondition and selectedConditions or selectedRules
            stateMap[row.ruleKey] = newState
            if row.UpdateVisual then row.UpdateVisual() end
        end
    end

    if panel.categoryCards then
        for _, card in ipairs(panel.categoryCards) do
            UpdateCardHeaderVisual(card)
        end
    end

    UpdateSelectionNote(panel)
    UpdateSelectAllButton(panel)
end

-- Returns the set of families with at least one display matching the given taming rules /
-- conditions, or nil if neither is active. Pulled out of OnApplyClick so
-- RecomputeSmartFamilySelection can call it fresh on every Apply, including a cleared one.
function ST:ComputeMatchingFamilies(selectedRuleMap, selectedConditionNames)
    if not PSM.PetModels then return nil end

    local hasRules = next(selectedRuleMap)       ~= nil
    local hasConds = next(selectedConditionNames) ~= nil
    if not (hasRules or hasConds) then return nil end

    local relevantFamilies = {}
    for _, familyName in ipairs(PSM.PetModels:GetAvailableFamilies()) do
        local familyData = PSM.PetModels:GetFamilyModels(familyName)
        if familyData and familyData.displayIds then
            for _, displayData in ipairs(familyData.displayIds) do
                local match = false

                local passRules = not hasRules
                if hasRules then
                    local tamingSet = {}
                    if displayData.taming then
                        for _, r in ipairs(displayData.taming) do tamingSet[r] = true end
                    end

                    local hasActiveRules, matchActive = false, false
                    local forbiddenMatch = false
                    for rKey, state in pairs(selectedRuleMap) do
                        if state == true then
                            hasActiveRules = true

                            local isMatch = tamingSet[rKey]

                            if not isMatch and rKey == "Sliver of N'Zoth" and displayData.npcs then
                                for _, npc in ipairs(displayData.npcs) do
                                    local npcID   = tonumber(npc.npcId)
                                    local condList = PSM.ConditionsData and PSM.ConditionsData.Get(npcID)
                                    if condList then
                                        for _, cName in ipairs(condList) do
                                            if cName == "Sliver of N'Zoth" then
                                                isMatch = true; break
                                            end
                                        end
                                    end
                                    if isMatch then break end
                                end
                            end

                            if isMatch then
                                local fSel = selectedRuleMap["Florafaun"] == true
                                local dSel = selectedRuleMap["Direhorn"]  == true
                                if not (tamingSet["Florafaun"] and tamingSet["Direhorn"]
                                        and ((fSel and not dSel) or (dSel and not fSel))) then
                                    matchActive = true
                                end
                            end
                        elseif state == "inverted" then
                            local isForbidden = tamingSet[rKey]

                            if not isForbidden and rKey == "Sliver of N'Zoth" and displayData.npcs then
                                for _, npc in ipairs(displayData.npcs) do
                                    local npcID   = tonumber(npc.npcId)
                                    local condList = PSM.ConditionsData and PSM.ConditionsData.Get(npcID)
                                    if condList then
                                        for _, cName in ipairs(condList) do
                                            if cName == "Sliver of N'Zoth" then
                                                isForbidden = true; break
                                            end
                                        end
                                    end
                                    if isForbidden then break end
                                end
                            end
                            if isForbidden then forbiddenMatch = true; break end
                        end
                    end
                    passRules = (not hasActiveRules or matchActive) and not forbiddenMatch
                end
                if passRules and hasRules then match = true end

                if not match and hasConds and displayData.npcs then
                    local userHasActiveConds = false
                    for _, state in pairs(selectedConditionNames) do
                        if state == true then userHasActiveConds = true; break end
                    end

                    local atLeastOneNpcPasses = false
                    for _, npc in ipairs(displayData.npcs) do
                        local npcID   = tonumber(npc.npcId)
                        local condList = PSM.ConditionsData and PSM.ConditionsData.Get(npcID)
                        local npcDisqualified  = false
                        local npcMatchedActive = false

                        if condList then
                            for _, cName in ipairs(condList) do
                                local state = selectedConditionNames[cName]
                                if state == "inverted" then npcDisqualified  = true; break end
                                if state == true       then npcMatchedActive = true  end
                            end
                        end
                        if not npcDisqualified and (not userHasActiveConds or npcMatchedActive) then
                            atLeastOneNpcPasses = true
                            break
                        end
                    end
                    if atLeastOneNpcPasses then match = true end
                end

                if match then
                    relevantFamilies[familyName] = true
                    break
                end
            end
        end
    end

    return relevantFamilies
end

local function OnApplyClick(panel)
    local selectedRuleMap = {}
    for ruleKey, state in pairs(selectedRules) do
        if state ~= nil then selectedRuleMap[ruleKey] = state end
    end
    PSM.state.selectedTamingRules = selectedRuleMap

    local selectedConditionNames = {}
    for cond, state in pairs(selectedConditions) do
        if state ~= nil then selectedConditionNames[cond] = state end
    end
    PSM.state.selectedConditions = selectedConditionNames

    PetStableManagementDB = PetStableManagementDB or {}
    PetStableManagementDB.filters = PetStableManagementDB.filters or {}
    PetStableManagementDB.filters.selectedTamingRules  = selectedRuleMap
    PetStableManagementDB.filters.selectedConditions   = selectedConditionNames

    -- Always recompute, even when cleared, so the family selection widens back out.
    if PSM.ModelsFilters and PSM.ModelsFilters.RecomputeSmartFamilySelection then
        PSM.ModelsFilters:RecomputeSmartFamilySelection()
    end

    if PSM.ModelsFilters and PSM.ModelsFilters.ReloadAndSummarise then
        PSM.ModelsFilters:ReloadAndSummarise()
    end

    local stParts = {}
    if next(selectedRuleMap) then
        local rCount = 0
        local lastRuleKey, lastRuleState
        for k, v in pairs(selectedRuleMap) do
            rCount = rCount + 1
            lastRuleKey, lastRuleState = k, v
        end
        if rCount == 1 then
            local rule  = PSM.TamingRules and PSM.TamingRules[lastRuleKey]
            local lbl   = rule and rule.label or lastRuleKey
            if lastRuleState == "inverted" then lbl = "Not " .. lbl end
            table.insert(stParts, lbl)
        else
            table.insert(stParts, "Multiple Multiple Skills")
        end
    end

    if next(selectedConditionNames) then
        local cCount = 0
        local lastCondKey, lastCondState
        for k, v in pairs(selectedConditionNames) do
            cCount = cCount + 1
            lastCondKey, lastCondState = k, v
        end
        if cCount == 1 then
            local lbl = lastCondKey
            if lastCondState == "inverted" then lbl = "Not " .. lbl end
            table.insert(stParts, lbl)
        else
            table.insert(stParts, "Multiple Multiple Conditions")
        end
    end

    local filterDesc = #stParts > 0 and table.concat(stParts, "; ") or "None"
    print(PSM.Utils:FormatColorText(
        "PetStableManagement: Special Tames filter applied (" .. filterDesc .. ").",
        PSM.Config.COLORS.SUCCESS
    ))

    panel:Hide()
end

-- ─────────────────────────────────────────────
-- Footer
-- ─────────────────────────────────────────────

local function CreateFooter(panel)
    local footer = CreateFrame("Frame", nil, panel)
    footer:SetHeight(36)
    footer:SetPoint("BOTTOMLEFT",  panel, "BOTTOMLEFT",  20, 10)
    footer:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -20, 10)

    local sep = footer:CreateTexture(nil, "BACKGROUND")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT",  footer, "TOPLEFT",  0, 0)
    sep:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)
    sep:SetColorTexture(1, 1, 1, 0.08)

    local note = footer:CreateFontString(nil, "OVERLAY")
    note:SetFont("Fonts\\FRIZQT__.TTF", PSM.Config.FONT_SIZES.STATS)
    note:SetTextColor(unpack(PSM.Config.COLORS.ABILITY_SELECTION_NOTE))
    note:SetPoint("LEFT", footer, "LEFT", 0, -8)
    note:SetText("0 items selected")
    panel.selectionNote = note

    local applyButton = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
    applyButton:SetSize(PSM.Config.BUTTON_WIDTH, PSM.Config.BUTTON_HEIGHT)
    applyButton:SetPoint("RIGHT", footer, "RIGHT", 0, -8)
    applyButton:SetText("Apply Filters")
    applyButton:SetNormalFontObject("GameFontNormalSmall")
    applyButton:SetScript("OnClick", function() OnApplyClick(panel) end)
    PSM.UI:ApplyElvUISkin(applyButton, "button")

    local selectAllButton = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
    selectAllButton:SetSize(PSM.Config.BUTTON_WIDTH, PSM.Config.BUTTON_HEIGHT)
    selectAllButton:SetPoint("RIGHT", applyButton, "LEFT", -8, 0)
    selectAllButton:SetText("Select All")
    selectAllButton:SetNormalFontObject("GameFontNormalSmall")
    selectAllButton:SetScript("OnClick", function() OnSelectAllClick(panel) end)
    PSM.UI:ApplyElvUISkin(selectAllButton, "button")
    panel.selectAllBtn = selectAllButton
end

-- ─────────────────────────────────────────────
-- Public: reset internal state
-- ─────────────────────────────────────────────

function ST:ResetInternalState()
    selectedRules      = {}
    selectedConditions = {}

    local panel = PSM.state.specialTames
    if panel then
        if panel.searchBox then panel.searchBox:SetText("") end
        RepopulateRows(panel, "", panel.activeTag or "All")
    end
end

-- ─────────────────────────────────────────────
-- Load saved filters from SavedVariables
-- ─────────────────────────────────────────────

-- Restores both PSM.state.selectedTamingRules/selectedConditions (what actually gets
-- filtered by) and this file's own selectedRules/selectedConditions locals (what
-- RepopulateRows reads for checkbox state) -- without the latter, reopening this panel
-- after a reload showed everything unticked even though the filter was still active.
local function LoadSavedFilters()
    PSM.state.selectedTamingRules = PSM.state.selectedTamingRules or {}
    local savedRules = PetStableManagementDB
        and PetStableManagementDB.filters
        and PetStableManagementDB.filters.selectedTamingRules
    if savedRules then
        for ruleKey, val in pairs(savedRules) do
            PSM.state.selectedTamingRules[ruleKey] = val
            selectedRules[ruleKey] = val
        end
    end

    PSM.state.selectedConditions = PSM.state.selectedConditions or {}
    local savedConditions = PetStableManagementDB
        and PetStableManagementDB.filters
        and PetStableManagementDB.filters.selectedConditions
    if savedConditions then
        for cond, val in pairs(savedConditions) do
            PSM.state.selectedConditions[cond] = val
            selectedConditions[cond] = val
        end
    end
end

-- ─────────────────────────────────────────────
-- Panel creation
-- ─────────────────────────────────────────────

function ST:Toggle()
    if UnitAffectingCombat("player") then
        print("|cFFFF0000Special Tames: Cannot open during combat.|r")
        return
    end
    PSM.PanelManager:TogglePanel("specialTames", function() self:CreateSpecialTamesPanel() end)
end

function ST:CreateSpecialTamesPanel()
    if PSM.state.specialTames then return end
    LoadSavedFilters()

    local panel = PSM.PanelManager:CreateBasePanel("specialTames", {
        width              = CFG.PANEL_WIDTH,
        height             = CFG.PANEL_HEIGHT,
        title              = "Special Tames",
        escKeyframe        = "PetStableManagementSpecialTames",
        resizable          = true,
        showResizeHandle   = true,
        showMaximizeButton = false,

        onShow = function(p)
            UpdateAllStatuses(p)
        end,
    })

    local searchBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    searchBox:SetPoint("TOP", panel.title, "BOTTOM", 0, -10)
    searchBox:SetSize(150, 20)
    searchBox:SetAutoFocus(false)
    searchBox:SetText("")
    searchBox:SetScript("OnTextChanged", function(self)
        RepopulateRows(panel, self:GetText(), panel.activeTag)
    end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    PSM.UI:ApplyElvUISkin(searchBox, "editbox")
    panel.searchBox = searchBox

    panel.activeTag = "All Skills"
    panel.pillBar   = CreatePillBar(panel)

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     panel, "TOPLEFT",     20, -120)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30,  56)
    PSM.UI:ApplyElvUISkin(scrollFrame, "scrollframe")
    PSM.UI:ApplyElvUISkin(scrollFrame.ScrollBar, "scrollbar")

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(CFG.PANEL_WIDTH - 50, 400)
    scrollFrame:SetScrollChild(scrollChild)

    panel.scrollFrame = scrollFrame
    panel.scrollChild = scrollChild
    panel.ruleRows    = {}

    CreateFooter(panel)

    RepopulateRows(panel, "")
    UpdateSelectionNote(panel)
    UpdateSelectAllButton(panel)

    return panel
end