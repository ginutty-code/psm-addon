-- ModelsBrowser/SpecialTames.lua
-- Special Tames panel — shows taming requirements with status indicators and filtering

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
    STATUS_SIZE    = 16,
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
    local Widgets = PSM.Widgets

    local icon = Widgets.Frame(parent, { size = { CFG.STATUS_SIZE, CFG.STATUS_SIZE } })

    icon.texture = Widgets.Texture(icon, {
        allPoints = true,
        texture   = "Interface\\RAIDFRAME\\ReadyCheck",
        texCoord  = (status == "met") and { 0, 0.5, 0, 0.5 } or { 0.5, 1, 0.5, 1 },
    })

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
        card.catLabel:SetTextColor(unpack(PSM.Theme.COLOR.GREEN))
        if card.headerInvIcon then card.headerInvIcon:Hide() end
    elseif allInv then
        card.catLabel:SetTextColor(unpack(PSM.Theme.COLOR.RED))
        if not card.headerInvIcon then
            card.headerInvIcon = PSM.Widgets.Texture(card.header, {
                layer   = "OVERLAY",
                texture = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
                size    = { 14, 14 },
                point   = { "LEFT", card.catLabel, "RIGHT", 5, 0 },
            })
        end
        card.headerInvIcon:Show()
    elseif anyAct then
        card.catLabel:SetTextColor(unpack(PSM.Theme.COLOR.WHITE))
        if card.headerInvIcon then card.headerInvIcon:Hide() end
    else
        card.catLabel:SetTextColor(unpack(PSM.Theme.COLOR.GREY))
        if card.headerInvIcon then card.headerInvIcon:Hide() end
    end
end

local function CreateCategoryCard(parent, groupName, cardW)
    local Widgets = PSM.Widgets

    local card = Widgets.Frame(parent, {
        width       = cardW,
        backdrop    = "SOLID_BORDERED",
        color       = { 0.05, 0.05, 0.05, 0.9 },
        borderColor = { 0.2,  0.2,  0.2,  1   },
    })

    local header = Widgets.Frame(card, {
        frameType = "Button",
        height    = CFG.HEADER_H,
        point     = {
            { "TOPLEFT",  card, "TOPLEFT",  0, 0 },
            { "TOPRIGHT", card, "TOPRIGHT", 0, 0 },
        },
    })

    Widgets.Texture(header, {
        layer     = "BACKGROUND",
        allPoints = true,
        color     = { 0.12, 0.12, 0.12, 1 },
    })

    local catLabel = Widgets.Label(header, {
        fontObject = "GameFontNormalSmall",
        point      = { "LEFT", header, "LEFT", CFG.CARD_PADDING, 0 },
        text       = groupName,
    })

    card.header    = header
    card.catLabel  = catLabel
    card.rows      = {}
    card.visibleRows = {}
    card.groupName = groupName

    return card
end

local function CreateRuleRow(parent, ruleKey, ruleData)
    local Widgets = PSM.Widgets

    local row = Widgets.Frame(parent, {
        size        = { CFG.PANEL_WIDTH - 2 * CFG.PADDING - 50, CFG.ROW_HEIGHT + CFG.CARD_PADDING * 2 },
        backdrop    = "SOLID_BORDERED",
        color       = { 0.08, 0.08, 0.08, 0.85 },
        borderColor = { 0.25, 0.25, 0.25, 1    },
    })
    row:EnableMouse(true)

    local P = CFG.CARD_PADDING

    local status     = PSM.TamingChecker.GetRuleStatus(ruleKey)
    local statusIcon = CreateStatusIcon(row, status)
    statusIcon:SetPoint("LEFT", row, "LEFT", P, 0)

    local checkbox = Widgets.CheckBox(row, {
        point = { "LEFT", statusIcon, "RIGHT", 10, 0 },
    })

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
                checkbox.invertedTexture = PSM.Widgets.Texture(checkbox, {
                    layer   = "OVERLAY",
                    texture = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
                    size    = { PSM.Theme.CONTROL.CHECKBOX_MARK, PSM.Theme.CONTROL.CHECKBOX_MARK },
                    point   = { "CENTER", checkbox, "CENTER", 0, 0 },
                })
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
                mainParts[#mainParts + 1] = PSM.L("%s (auto)", ruleData.hint.autoRace)
            end
            if ruleData.hint.itemID then
                mainParts[#mainParts + 1] = string.format(
                    "|cff0070dd|Hpsmtaming:%s|h%s|h|r",
                    ruleKey,
                    ruleData.hint.itemName or PSM.L("Item #%s", ruleData.hint.itemID))
            end
            if ruleData.hint.questID then
                mainParts[#mainParts + 1] = string.format(
                    "|cff0070dd|Hpsmtaming:%s|h%s|h|r",
                    ruleKey,
                    ruleData.hint.questName or PSM.L("Quest #%s", ruleData.hint.questID))
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

    local label = Widgets.Label(row, {
        fontObject = "GameFontNormal",
        justify    = "LEFT",
        wordWrap   = false,
        text       = fullText,
        point      = {
            { "LEFT",  checkbox, "RIGHT", 10, 0 },
            { "RIGHT", row,      "RIGHT", -P, 0 },
        },
    })

    row:SetHyperlinksEnabled(true)
    row:SetScript("OnHyperlinkEnter", function(self, link)
        local rk   = link:match("psmtaming:(.+)")
        if not rk then return end
        local rule = PSM.TamingRules and PSM.TamingRules[rk]
        if not (rule and rule.hint) then return end

        local hyperlink
        if rule.hint.itemID then
            hyperlink = "item:" .. rule.hint.itemID
        elseif rule.hint.questID then
            hyperlink = "quest:" .. rule.hint.questID
        end
        if hyperlink then
            PSM.Tooltip.Show(self, { anchor = "ANCHOR_CURSOR", hyperlink = hyperlink })
        end
    end)
    row:SetScript("OnHyperlinkLeave", PSM.Tooltip.Hide)
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

    PSM.Tooltip.Attach(row, {
        title      = ruleData.label,
        titleColor = PSM.Theme.COLOR.WHITE,
        lines      = { { text = ruleData.desc, wrap = true } },
    }, {
        onEnter = function(self) self:SetBackdropBorderColor(0.5,  0.5,  0.5,  1) end,
        onLeave = function(self) self:SetBackdropBorderColor(0.25, 0.25, 0.25, 1) end,
    })
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
    local Widgets = PSM.Widgets

    -- Backdrop NONE, exactly as before: this row has no bgFile and no edgeFile, so the
    -- colour calls below (and the hover recolour further down) have nothing to tint and
    -- are inert. Preserved verbatim rather than cleaned up -- this migration is meant to
    -- be behaviour-neutral, and the dead styling is A13's call, not this task's.
    local row = Widgets.Frame(parent, {
        size        = { width, CFG.ROW_HEIGHT },
        backdrop    = "NONE",
        color       = { 0.08, 0.08, 0.08, 0.85 },
        borderColor = { 0.25, 0.25, 0.25, 1    },
    })
    row:EnableMouse(true)

    local P = CFG.CARD_PADDING

    local checkbox = Widgets.CheckBox(row, {
        point = { "LEFT", row, "LEFT", P, 0 },
    })

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
                checkbox.invertedTexture = PSM.Widgets.Texture(checkbox, {
                    layer   = "OVERLAY",
                    texture = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
                    size    = { PSM.Theme.CONTROL.CHECKBOX_MARK, PSM.Theme.CONTROL.CHECKBOX_MARK },
                    point   = { "CENTER", checkbox, "CENTER", 0, 0 },
                })
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

    Widgets.Label(row, {
        fontObject = "GameFontNormal",
        justify    = "LEFT",
        wordWrap   = false,
        text       = "|cffffffff" .. conditionName .. "|r",
        point      = {
            { "LEFT",  checkbox, "RIGHT", 10, 0 },
            { "RIGHT", row,      "RIGHT", -P, 0 },
        },
    })

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

    local btnText = PSM.L("Select All")
    if hasIgnored then
        btnText = PSM.L("Select All")
    elseif hasActive then
        btnText = PSM.L("Invert All")
    elseif hasInverted then
        btnText = PSM.L("Unselect All")
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

    for _, card in ipairs(cardList) do
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
                local moreBtn = PSM.Widgets.Frame(card, {
                    frameType = "Button",
                    size      = { colWidth - 2 * CFG.CARD_PADDING, CFG.MORE_H },
                    point     = { "BOTTOMLEFT", card, "BOTTOMLEFT", CFG.CARD_PADDING, CFG.CARD_PADDING },
                })
                card.moreBtn = moreBtn

                local moreLabel = PSM.Widgets.Label(moreBtn, {
                    fontObject = "GameFontNormalSmall",
                    color      = PSM.Config.COLORS.PRIMARY,
                    point      = { "CENTER" },
                })
                moreBtn.label = moreLabel

                if #matches > CFG.PARTIAL_ROWS then
                    moreBtn:Show()
                    moreLabel:SetText(PSM.L("and %d more...", #matches - CFG.PARTIAL_ROWS))
                    moreBtn:SetScript("OnClick", function()
                        card.isExpanded = not card.isExpanded
                        card:SetHeight(card.isExpanded and card.expandedHeight or card.partialHeight)
                        moreLabel:SetText(
                            card.isExpanded
                            and PSM.L("Show less")
                            or  PSM.L("and %d more...", #matches - CFG.PARTIAL_ROWS)
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

    else
        for ruleKey, ruleData in pairs(PSM.TamingRules) do
            if ruleKey ~= "Sliver of N'Zoth" then
                if RowMatchesQuery(ruleKey, ruleData, query) and RowMatchesTag(ruleKey, activeTag) then
                    ruleCount = ruleCount + 1
                    local rowH = CFG.ROW_HEIGHT + CFG.CARD_PADDING * 2
                    local row  = CreateRuleRow(scrollChild, ruleKey, ruleData)
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
        panel.selectionNote:SetText(n == 1 and PSM.L("%d item selected", n)
                                    or PSM.L("%d items selected", n))
    end
    UpdateSelectAllButton(panel)
end

-- ─────────────────────────────────────────────
-- Pill bar (All | Unlocked | Locked | Conditions)
-- ─────────────────────────────────────────────

local PILL_TAGS = { "All Skills", "Unlocked Skills", "Locked Skills", "Conditions" }

-- Was a hand-rolled copy of the exact same frame Ability Browser also built
-- independently; see PanelManager:CreatePillBar (A13).
local function CreatePillBar(panel)
    return PSM.PanelManager:CreatePillBar(panel, PILL_TAGS, function(tagName)
        panel.activeTag = tagName
        RepopulateRows(panel, panel.searchBox:GetSearchText(), tagName)
    end)
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
    panel.selectionNote:SetText(n == 1 and PSM.L("%d item selected", n)
                                    or PSM.L("%d items selected", n))
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

    -- displayData.npcs (from GetFamilyModels) is a bare denseIndex array --
    -- resolve npcId via the ModelsData column, not npc.npcId.
    local modelsData = _G.ModelsData

    local relevantFamilies = {}
    for _, familyName in ipairs(PSM.PetModels:GetAvailableFamilies()) do
        local familyData = PSM.PetModels:GetFamilyModels(familyName)
        if familyData and familyData.displayIds then
            for _, displayData in ipairs(familyData.displayIds) do
                local match = false

                -- Rules and conditions are combined with OR here, unlike the AND in
                -- DisplayPassesFilters. Deliberate and unchanged: this seeds a family
                -- selection, so it wants breadth -- a family is relevant if it holds a
                -- display matching *either* criterion. The predicates themselves are now
                -- the shared ones, so only the combination differs between the two.
                if hasRules and PSM.PetModels.TamingSetPasses(
                        PSM.PetModels.TamingSet(displayData.taming), selectedRuleMap) then
                    match = true
                end

                if not match and hasConds then
                    local userHasActiveConds = PSM.PetModels.ConditionsHaveActive(selectedConditionNames)
                    for _, npc in ipairs(displayData.npcs or {}) do
                        if PSM.PetModels.NpcPassesConditions(
                                modelsData and modelsData.NpcId[npc],
                                selectedConditionNames, userHasActiveConds) then
                            match = true
                            break
                        end
                    end
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
    PSM.Selections:Replace("tamingRules", selectedRuleMap)

    local selectedConditionNames = {}
    for cond, state in pairs(selectedConditions) do
        if state ~= nil then selectedConditionNames[cond] = state end
    end
    PSM.Selections:Replace("conditions", selectedConditionNames)

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
            if lastRuleState == "inverted" then lbl = PSM.L("Not %s", lbl) end
            table.insert(stParts, lbl)
        else
            table.insert(stParts, PSM.L("Multiple Skills"))
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
            if lastCondState == "inverted" then lbl = PSM.L("Not %s", lbl) end
            table.insert(stParts, lbl)
        else
            table.insert(stParts, PSM.L("Multiple Conditions"))
        end
    end

    local filterDesc = #stParts > 0 and table.concat(stParts, "; ") or PSM.L("None")
    print(PSM.Utils:FormatColorText(
        PSM.L("Special Tames filter applied (%s).", filterDesc),
        PSM.Config.COLORS.SUCCESS
    ))

    panel:Hide()
end

-- ─────────────────────────────────────────────
-- Footer
-- ─────────────────────────────────────────────

-- Bare label, no border/hairline -- the one footer contract every panel uses (A13).
-- Was a bordered frame with its own hairline, independently duplicated in Ability
-- Browser; see PanelManager:CreateFooterLabel.
local function CreateFooter(panel)
    local Widgets = PSM.Widgets

    panel.selectionNote = PSM.PanelManager:CreateFooterLabel(panel, {
        fontSize = PSM.Config.FONT_SIZES.STATS,
        color    = PSM.Config.COLORS.ABILITY_SELECTION_NOTE,
        point    = { "BOTTOMLEFT", panel, "BOTTOMLEFT", 20, PSM.Theme.CHROME.FOOTER_Y },
        text     = PSM.L("%d items selected", 0),
    })

    local applyButton = Widgets.Button(panel, {
        width      = PSM.Theme.CONTROL.BUTTON_W.M,
        point      = { "BOTTOMRIGHT", panel, "BOTTOMRIGHT", -20, PSM.Theme.CHROME.FOOTER_Y },
        text       = PSM.L("Apply Filters"),
        fontObject = "GameFontNormalSmall",
        onClick    = function() OnApplyClick(panel) end,
    })

    panel.selectAllBtn = Widgets.Button(panel, {
        width      = PSM.Theme.CONTROL.BUTTON_W.M,
        point      = { "RIGHT", applyButton, "LEFT", -8, 0 },
        text       = PSM.L("Select All"),
        fontObject = "GameFontNormalSmall",
        onClick    = function() OnSelectAllClick(panel) end,
    })
end

-- ─────────────────────────────────────────────
-- Public: reset internal state
-- ─────────────────────────────────────────────

function ST:ResetInternalState()
    selectedRules      = {}
    selectedConditions = {}

    local panel = PSM.state.specialTames
    if panel then
        -- ClearSearch, not SetText(""): the latter empties the box but leaves it blank,
        -- because the placeholder is only restored on focus loss. So Reset All Filters
        -- left "Search tames..." missing until the user clicked into the box and out
        -- again. Same fix ModelsFilters:ResetAllFilters already carries.
        if panel.searchBox then panel.searchBox:ClearSearch() end
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
    local saved = PetStableManagementDB and PetStableManagementDB.filters

    for ruleKey, val in pairs(saved and saved.selectedTamingRules or {}) do
        PSM.Selections:Set("tamingRules", ruleKey, val)
        selectedRules[ruleKey] = val
    end

    for cond, val in pairs(saved and saved.selectedConditions or {}) do
        PSM.Selections:Set("conditions", cond, val)
        selectedConditions[cond] = val
    end
end

-- ─────────────────────────────────────────────
-- Panel creation
-- ─────────────────────────────────────────────

function ST:Toggle()
    if UnitAffectingCombat("player") then
        print(PSM.L("Special Tames: Cannot open during combat."))
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
        title              = PSM.L("Special Tames"),
        resizable          = true,
        showResizeHandle   = true,
        showMaximizeButton = false,

        onShow = function(p)
            UpdateAllStatuses(p)
        end,
    })

    local Widgets = PSM.Widgets

    -- Shared search box: see the note in AbilityBrowser. Both panels used to build
    -- their own, without a placeholder and without debouncing.
    PSM.PanelManager:CreateSearchBox(panel, function(text)
        RepopulateRows(panel, text, panel.activeTag)
    end, {
        placeholder = PSM.L("Search tames..."),
    })

    panel.activeTag = "All Skills"
    panel.pillBar   = CreatePillBar(panel)

    local scrollFrame = Widgets.Frame(panel, {
        frameType = "ScrollFrame",
        template  = "UIPanelScrollFrameTemplate",
        skin      = "scrollframe",
        point     = {
            { "TOPLEFT",     panel, "TOPLEFT",      20, -120 },
            { "BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30,   56 },
        },
    })
    PSM.Skin.Apply(scrollFrame.ScrollBar, "scrollbar")

    local scrollChild = Widgets.Frame(scrollFrame, {
        size = { CFG.PANEL_WIDTH - 50, 400 },
    })
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