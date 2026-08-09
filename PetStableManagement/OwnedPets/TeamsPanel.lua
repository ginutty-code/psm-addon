-- TeamsPanel.lua
-- Teams panel UI for viewing and managing saved pet teams

local addonName = "PetStableManagement"

_G.PSM = _G.PSM or {}
local PSM = _G.PSM
PSM.TeamsPanel = PSM.TeamsPanel or {}

-- Layout constants
local ROW_HEIGHT      = 140
local ICON_SIZE       = 55
local MIN_ROW_WIDTH   = 485
local COLUMN_SPACING  = 2
local ROW_SPACING     = 2

-- Progressive rendering
local renderQueue          = {}
local isRendering          = false
local refreshDebounceTimer = nil
local TEAMS_PER_FRAME      = 10
local RENDER_DELAY         = 0.01

----------------------------------------------------------------------------------------------------------------
-- LOCAL HELPERS
----------------------------------------------------------------------------------------------------------------


local function CreateActionButton(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width, height)
    btn:SetText(text)
    btn:SetNormalFontObject("GameFontNormalSmall")
    PSM.UI:ApplyElvUISkin(btn, "button")
    return btn
end

-- Tooltip helpers
local function ShowTooltip(owner, anchor, text, xOff, yOff)
    GameTooltip:SetOwner(owner, anchor, xOff, yOff)
    GameTooltip:SetText(text)
    GameTooltip:Show()
end

local function HideTooltip()
    GameTooltip:Hide()
end

-- Slot X position (accounts for extra gap before slot 6)
local function SlotXPos(i, slotSize, slotSpacing, slot5to6Spacing)
    if i <= 5 then
        return (i - 1) * (slotSize + slotSpacing)
    else
        return 5 * (slotSize + slotSpacing) + slot5to6Spacing
    end
end

-- Ensure panel exists, create if needed
local function EnsurePanel()
    if not PSM.state.teamsPanel then
        PSM.TeamsPanel:CreateTeamsPanel()
    end
    return PSM.state.teamsPanel
end

----------------------------------------------------------------------------------------------------------------
-- PET SLOT INTERACTIONS
----------------------------------------------------------------------------------------------------------------

local function CreateRemoveFromSlotButton(parent, container, slotNum, teamId)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(16, 16)
    btn:SetPoint("TOPRIGHT", container, "TOPRIGHT", -20, -10)
    btn:SetFrameLevel(container:GetFrameLevel() + 2)
    btn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    btn:SetHighlightTexture("Interface\\Buttons\\UI-StopButton")
    btn:SetPushedTexture("Interface\\Buttons\\UI-StopButton")
    btn:SetAlpha(0.7)
    btn:Hide()

    btn.teamId  = teamId
    btn.slotNum = slotNum

    btn:SetScript("OnClick", function(self)
        local team = PSM.Teams:GetTeamById(self.teamId)
        if team and team.slots[self.slotNum] then
            team.slots[self.slotNum] = nil
            team.modifiedAt = time()
            PSM.TeamsPanel:RefreshTeamsList()
        end
    end)
    btn:SetScript("OnEnter", function(self)
        self:SetAlpha(1.0)
        ShowTooltip(self, "ANCHOR_RIGHT", "Remove from Team")
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetAlpha(0.7)
        HideTooltip()
    end)

    return btn
end

local function SetupPetSlotInteraction(container, petData, slot, team)
    container:SetScript("OnEnter", function(self)
        PSM.TeamsPanel:ShowPetTooltip(self, petData, slot)
        if container.removeButton then container.removeButton:Show() end
    end)
    container:SetScript("OnLeave", function()
        HideTooltip()
        if container.removeButton and not container.removeButton:IsMouseOver() then
            container.removeButton:Hide()
        end
    end)
    container:EnableMouse(true)

    if container.removeButton then
        container.removeButton.teamId  = team.id
        container.removeButton.slotNum = slot
    end

    PSM.DragDrop:SetupTeamSlotDragDrop(container, slot, team.id, team)
end

----------------------------------------------------------------------------------------------------------------
-- PANEL CREATION
----------------------------------------------------------------------------------------------------------------

function PSM.TeamsPanel:CreateTeamsPanel()
    if PSM.state.teamsPanel then return PSM.state.teamsPanel end

    local savedPosition = PSM.Data:GetTeamsPanelPosition() or {
        point = "TOPLEFT", relativeTo = "StableFrame",
        relativePoint = "TOPRIGHT", x = 0, y = 0
    }

    local config = {
        width    = PSM.Data:GetTeamsPanelWidth()  or PSM.Config.DEFAULT_PANEL_WIDTH,
        height   = PSM.Data:GetTeamsPanelHeight() or PSM.Config.DEFAULT_PANEL_HEIGHT,
        position = savedPosition,
        title    = "Pet Teams",
        escKeyframe = "PSMTeamsPanel",
        minWidth  = PSM.Config.MIN_PANEL_WIDTH,
        minHeight = PSM.Config.MIN_PANEL_HEIGHT,
        onHide   = function(p) PSM.PanelManager:CleanupPanel(p) end,
        onShow   = function(p)
            if p._initialized then
                if PSM.state.isStableOpen and #PSM.state.stablePets == 0 then
                    PSM.Data:CollectStablePets()
                end
                PSM.TeamsPanel:RefreshTeamsList()
            end
        end,
        onResize = function(p)
            PSM.Data:SetTeamsPanelSize(p:GetWidth(), p:GetHeight())
            if p._initialized and p:IsVisible() then
                PSM.TeamsPanel:RefreshTeamsList()
            end
        end,
    }

    local panel = PSM.PanelManager:CreateBasePanel("teamsPanel", config)
    panel._initialized = false
    self:AddTeamsPanelElements(panel)

    if panel.scrollFrame and panel.content then
        panel.content:SetWidth(panel.scrollFrame:GetWidth())
    end

    panel._initialized = true

    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, relativeTo, relativePoint, x, y = self:GetPoint(1)
        PSM.Data:SetTeamsPanelPosition(point, relativeTo or "UIParent", relativePoint, x, y)
    end)

    return panel
end

function PSM.TeamsPanel:AddTeamsPanelElements(panel)
    -- Info text
    panel.infoText = panel:CreateFontString(nil, "OVERLAY")
    panel.infoText:SetFont("Fonts\\FRIZQT__.TTF", 10)
    panel.infoText:SetPoint("TOP", panel.title, "BOTTOM", 0, -5)
    panel.infoText:SetTextColor(0.8, 0.8, 0.8)

    -- Search box
    PSM.PanelManager:CreateSearchBox(panel, function(searchText)
        PSM.TeamsPanel:FilterTeams(searchText)
    end, {
        placeholder = "Search teams...",
    })

    -- Scroll frame + content
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -110)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 35)

    local teamsFrame = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    teamsFrame:SetPoint("TOPLEFT",     scrollFrame, "TOPLEFT",     -5,  5)
    teamsFrame:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT",  5, -5)
    teamsFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    teamsFrame:SetBackdropColor(unpack(PSM.Config.COLORS.BACKGROUND))
    teamsFrame:SetFrameLevel(panel:GetFrameLevel() - 1)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(scrollFrame:GetWidth() - 10, 100)
    scrollFrame:SetScrollChild(content)

    if scrollFrame.ScrollBar then
        scrollFrame.ScrollBar:SetAlpha(1)
        PSM.UI:ApplyElvUISkin(scrollFrame.ScrollBar, "scrollbar")
    end

    panel.scrollFrame = scrollFrame
    panel.content     = content
    panel.teamsFrame  = teamsFrame
    panel.teamRows    = {}

    PSM.PanelManager:CreateScrollPreservingResizeHandler(panel, scrollFrame, content, function()
        PSM.TeamsPanel:RefreshTeamsList()
    end)

    -- Stats text
    panel.statsText = panel:CreateFontString(nil, "OVERLAY")
    panel.statsText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    panel.statsText:SetPoint("BOTTOM", 0, 15)
    panel.statsText:SetTextColor(1, 0.82, 0)
    panel.statsText:SetText("0 teams saved")

    -- Empty state message
    panel.emptyText = panel:CreateFontString(nil, "OVERLAY")
    panel.emptyText:SetFont("Fonts\\FRIZQT__.TTF", 12)
    panel.emptyText:SetPoint("CENTER", content, "CENTER", 0, 0)
    panel.emptyText:SetTextColor(0.6, 0.6, 0.6)
    panel.emptyText:SetText("No teams saved yet.\nCreate your teams at the Stable Master \nor by adding pets from the Owned Pets panel.")
    panel.emptyText:Hide()
end

----------------------------------------------------------------------------------------------------------------
-- TEAM ROW CREATION
----------------------------------------------------------------------------------------------------------------

function PSM.TeamsPanel:CreateTeamRow(parent)
    local slotSize       = ICON_SIZE + 45
    local slotSpacing    = -35
    local slot5to6Gap    = 30
    local buttonWidth    = 55
    local buttonHeight   = 18
    local buttonSpacing  = 5

    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetSize(parent:GetWidth() - 10, ROW_HEIGHT)
    row:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 8,
        insets = {left = 2, right = 2, top = 2, bottom = 2}
    })
    row:SetBackdropColor(unpack(PSM.Config.COLORS.BACKGROUND))

    row.nameText = row:CreateFontString(nil, "OVERLAY")
    row.nameText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    row.nameText:SetPoint("TOPLEFT", 10, -8)
    row.nameText:SetTextColor(1, 0.82, 0)
    row.nameText:SetText("Team Name")

    row.infoText = row:CreateFontString(nil, "OVERLAY")
    row.infoText:SetFont("Fonts\\FRIZQT__.TTF", 9)
    row.infoText:SetPoint("TOPLEFT", row.nameText, "BOTTOMLEFT", 0, -2)
    row.infoText:SetTextColor(0.7, 0.7, 0.7)

    -- Icons frame
    local iconsWidth = 6 * slotSize + 4 * slotSpacing + slot5to6Gap
    row.iconsFrame = CreateFrame("Frame", nil, row)
    row.iconsFrame:SetSize(iconsWidth, slotSize)
    row.iconsFrame:SetPoint("BOTTOMLEFT", 0, 5)

    -- Divider between slots 5 and 6
    local slot5Right = (5 - 1) * (slotSize + slotSpacing) + slotSize
    local slot6Left  = 5 * (slotSize + slotSpacing) + slot5to6Gap
    local divider = row.iconsFrame:CreateTexture(nil, "OVERLAY")
    divider:SetTexture("Interface\\Buttons\\WHITE8X8")
    divider:SetSize(slot5to6Gap - 4, 2)
    divider:SetPoint("CENTER", row.iconsFrame, "LEFT", (slot5Right + slot6Left) / 2, 0)
    divider:SetVertexColor(1, 0.82, 0)
    row.dividerLine = divider

    -- Pet icon slots
    row.petIcons          = {}
    row.petIconContainers = {}
    row.petMasks          = {}
    row.petBorders        = {}

    for i = 1, 6 do
        local container = CreateFrame("Button", nil, row.iconsFrame)
        container:SetSize(slotSize, slotSize)
        container:SetPoint("LEFT", SlotXPos(i, slotSize, slotSpacing, slot5to6Gap), 0)

        local tex = container:CreateTexture(nil, "BACKGROUND", nil, 1)
        tex:SetSize(ICON_SIZE, ICON_SIZE)
        tex:SetPoint("CENTER")
        tex:Hide()

        local mask = container:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask",
            "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetSize(ICON_SIZE, ICON_SIZE)
        mask:SetPoint("CENTER")
        tex:AddMaskTexture(mask)

        local border = container:CreateTexture(nil, "BORDER")
        border:SetAtlas("footer_inactive-ring")
        border:SetAllPoints(container)

        container:EnableMouse(true)
        container.displayId    = nil
        container.removeButton = CreateRemoveFromSlotButton(row.iconsFrame, container, i, nil)

        row.petIcons[i]          = tex
        row.petIconContainers[i] = container
        row.petMasks[i]          = mask
        row.petBorders[i]        = border
    end

    -- Action buttons
    row.buttonsFrame = CreateFrame("Frame", nil, row)
    row.buttonsFrame:SetSize(buttonWidth, 4 * buttonHeight + 3 * buttonSpacing)
    row.buttonsFrame:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -25)

    local prevBtn
    for _, spec in ipairs({
        { key = "applyButton",     label = "Apply"  },
        { key = "duplicateButton", label = "Copy"   },
        { key = "renameButton",    label = "Rename" },
        { key = "deleteButton",    label = "Delete" },
    }) do
        local btn = CreateActionButton(row.buttonsFrame, spec.label, buttonWidth, buttonHeight)
        if prevBtn then
            btn:SetPoint("TOP", prevBtn, "BOTTOM", 0, -buttonSpacing)
        else
            btn:SetPoint("TOP", row.buttonsFrame, "TOP", 0, 0)
        end
        row[spec.key] = btn
        prevBtn = btn
    end

    return row
end

----------------------------------------------------------------------------------------------------------------
-- UPDATE TEAM ROW
----------------------------------------------------------------------------------------------------------------

function PSM.TeamsPanel:UpdateTeamRow(row, team)
    if not row or not team then return end

    local alpha = PSM.Config:GetOpacity()

    -- Name
    row.nameText:SetText(team.name or "Unnamed Team")

    -- Info text
    local petCount = 0
    for slot = 1, 6 do
        if team.slots[slot] then petCount = petCount + 1 end
    end
    row.infoText:SetText(petCount .. "/6 pets • Modified: " .. PSM.Teams:FormatTimestamp(team.modifiedAt))

    -- Pet icons
    for slot = 1, 6 do
        local tex       = row.petIcons[slot]
        local container = row.petIconContainers[slot]
        local petData   = team.slots[slot]

        if petData and petData.displayID and petData.displayID > 0 then
            SetPortraitTextureFromCreatureDisplayID(tex, petData.displayID)
            tex:SetTexCoord(1, 0, 0, 1)
            tex:AddMaskTexture(row.petMasks[slot])
            tex:Show()
            container.displayId = petData.displayID
            SetupPetSlotInteraction(container, petData, slot, team)
        elseif petData and petData.icon then
            tex:SetTexture(petData.icon)
            tex:Show()
            container.displayId = nil
            SetupPetSlotInteraction(container, petData, slot, team)
        else
            tex:Hide()
            container.displayId = nil
            container:SetScript("OnEnter", nil)
            container:SetScript("OnLeave", nil)
            container:EnableMouse(false)
            if container.removeButton then container.removeButton:Hide() end
        end
    end

    -- Highlight based on active/match state
    local isActive      = (team.id == PSM.Teams:GetActiveTeamId())
    local matchesCurrent = false
    if PSM.state.isStableOpen then
        local cache = PSM.state.teamComparisonCache or {}
        if cache[team.id] == nil then
            cache[team.id] = select(1, PSM.Teams:CompareWithTeam(team.id))
            PSM.state.teamComparisonCache = cache
        end
        matchesCurrent = cache[team.id]
    end

    if isActive and matchesCurrent then
        row:SetBackdropColor(unpack(PSM.Config.COLORS.BACKGROUND_OWNED_SINGLE))
        row.nameText:SetTextColor(unpack(PSM.Config.COLORS.SUCCESS))
    elseif isActive then
        row:SetBackdropColor(0.4, 0.25, 0.1, alpha)
        row.nameText:SetTextColor(1, 0.5, 0)
    else
        row:SetBackdropColor(unpack(PSM.Config.COLORS.BACKGROUND))
        row.nameText:SetTextColor(unpack(PSM.Config.COLORS.PRIMARY))
    end

    -- Button callbacks
    local teamId   = team.id
    local teamName = team.name

    -- Apply
    row.applyButton:SetScript("OnClick", function()
        if not PSM.state.isStableOpen then
            print("|cFFFF8800PetStableManagement: You must be at a Stable Master to apply a team.|r")
            return
        end
        PSM.TeamDialogs:ShowApplyConfirmDialog(teamName, function()
            local ok, err = PSM.Teams:ApplyTeam(teamId)
            if ok then
                PSM.TeamsPanel:RefreshTeamsList()
            else
                print("|cFFFF0000PetStableManagement: " .. (err or "Failed to apply team") .. "|r")
            end
        end)
    end)

    -- Apply button enabled state + tooltip overlay
    local applyEnabled = PSM.state.isStableOpen
    row.applyButton:SetEnabled(applyEnabled)
    row.applyButton:SetAlpha(applyEnabled and 1 or 0.5)

    if not applyEnabled then
        if not row.applyButtonTooltipOverlay then
            local overlay = CreateFrame("Frame", nil, row.applyButton)
            overlay:SetAllPoints()
            overlay:EnableMouse(true)
            overlay:SetScript("OnEnter", function(self)
                ShowTooltip(self, "ANCHOR_BOTTOM", "Visit a Stable Master to apply teams", 1, 0.5, 0)
            end)
            overlay:SetScript("OnLeave", HideTooltip)
            row.applyButtonTooltipOverlay = overlay
        end
        row.applyButtonTooltipOverlay:Show()
    elseif row.applyButtonTooltipOverlay then
        row.applyButtonTooltipOverlay:Hide()
    end

    -- Rename
    row.renameButton:SetScript("OnClick", function()
        PSM.TeamDialogs:ShowNameInputDialog({
            title = "Rename Team",
            description = "Enter a new name for '" .. teamName .. "':",
            defaultText = teamName,
            confirmText = "Rename",
            onConfirm = function(newName)
                local ok, err = PSM.Teams:RenameTeam(teamId, newName)
                if ok then PSM.TeamsPanel:RefreshTeamsList()
                else print("|cFFFF0000PetStableManagement: " .. (err or "Failed to rename team") .. "|r") end
            end,
        })
    end)

    -- Duplicate
    row.duplicateButton:SetScript("OnClick", function()
        PSM.TeamDialogs:ShowNameInputDialog({
            title = "Duplicate Team",
            description = "Enter a name for the copy of '" .. teamName .. "':",
            defaultText = teamName .. " (Copy)",
            confirmText = "Duplicate",
            onConfirm = function(newName)
                local newId, err = PSM.Teams:DuplicateTeam(teamId, newName)
                if newId then PSM.TeamsPanel:RefreshTeamsList()
                else print("|cFFFF0000PetStableManagement: " .. (err or "Failed to duplicate team") .. "|r") end
            end,
        })
    end)

    -- Delete
    row.deleteButton:SetScript("OnClick", function()
        PSM.TeamDialogs:ShowDeleteConfirmDialog(teamName, function()
            local ok, err = PSM.Teams:DeleteTeam(teamId)
            if ok then PSM.TeamsPanel:RefreshTeamsList()
            else print("|cFFFF0000PetStableManagement: " .. (err or "Failed to delete team") .. "|r") end
        end)
    end)

    row:Show()
end

----------------------------------------------------------------------------------------------------------------
-- REFRESH / RENDER QUEUE
----------------------------------------------------------------------------------------------------------------

local function ProcessRenderQueue()
    if not PSM.state.teamsPanel or #renderQueue == 0 then
        isRendering = false
        return
    end
    for _ = 1, math.min(TEAMS_PER_FRAME, #renderQueue) do
        local item = table.remove(renderQueue, 1)
        if item and item.row and item.team then
            PSM.TeamsPanel:UpdateTeamRow(item.row, item.team)
        end
    end
    if #renderQueue > 0 then
        C_Timer.After(RENDER_DELAY, ProcessRenderQueue)
    else
        isRendering = false
    end
end

function PSM.TeamsPanel:RefreshTeamsList()
    if refreshDebounceTimer then refreshDebounceTimer:Cancel() end
    refreshDebounceTimer = C_Timer.NewTimer(0.03, function()
        PSM.TeamsPanel:DoRefreshTeamsList()
        refreshDebounceTimer = nil
    end)
end

function PSM.TeamsPanel:DoRefreshTeamsList()
    local panel = PSM.state.teamsPanel
    if not panel or not panel.content then return end

    self:ClearComparisonCache()

    local allTeams = PSM.Teams:GetTeams()
    local teams    = {}
    for _, team in ipairs(allTeams) do
        if not PSM.TeamsPanel._searchMode or self:DoesTeamMatchSearch(team) then
            table.insert(teams, team)
        end
    end

    local teamCount = #teams
    local allCount  = #allTeams

    panel.statsText:SetText(
        PSM.TeamsPanel._searchMode
        and (teamCount .. " of " .. allCount .. " team(s) match")
        or  (allCount .. " team(s) saved")
    )

    if teamCount == 0 then
        panel.emptyText:SetText(
            allCount == 0
            and "No teams saved yet.\nCreate your teams at the Stable Master \nor by adding pets from the Owned Pets panel."
            or  "No teams match your search."
        )
        panel.emptyText:Show()
        for _, row in ipairs(panel.teamRows) do row:Hide() end
        panel.content:SetHeight(100)
        return
    end
    panel.emptyText:Hide()

    while #panel.teamRows < teamCount do
        table.insert(panel.teamRows, self:CreateTeamRow(panel.content))
    end

    -- Multi-column layout
    local contentWidth = panel.content:GetWidth()
    local numColumns   = math.max(1, math.floor((contentWidth + COLUMN_SPACING) / (MIN_ROW_WIDTH + COLUMN_SPACING)))
    local rowsPerCol   = math.ceil(teamCount / numColumns)
    local colWidth     = (contentWidth - (numColumns - 1) * COLUMN_SPACING) / numColumns

    panel.content:SetHeight(math.max(rowsPerCol * (ROW_HEIGHT + ROW_SPACING) + ROW_SPACING, 100))

    renderQueue = {}
    for i, team in ipairs(teams) do
        local row     = panel.teamRows[i]
        local colIdx  = math.floor((i - 1) / rowsPerCol)
        local rowIdx  = (i - 1) % rowsPerCol
        row:ClearAllPoints()
        row:SetWidth(colWidth)
        row:SetPoint("TOPLEFT", panel.content, "TOPLEFT",
            colIdx * (colWidth + COLUMN_SPACING),
            -(rowIdx * (ROW_HEIGHT + ROW_SPACING) + ROW_SPACING))
        row.nameText:SetText(team.name or "Unnamed Team")
        table.insert(renderQueue, { row = row, team = team })
    end

    for i = teamCount + 1, #panel.teamRows do panel.teamRows[i]:Hide() end

    if not isRendering and #renderQueue > 0 then
        isRendering = true
        ProcessRenderQueue()
    end
end

----------------------------------------------------------------------------------------------------------------
-- TOGGLE / SHOW / HIDE
----------------------------------------------------------------------------------------------------------------

function PSM.TeamsPanel:Toggle()
    local panel = EnsurePanel()
    if panel:IsVisible() then panel:Hide()
    else panel:Show(); panel:Raise() end
end

function PSM.TeamsPanel:Show()
    local panel = EnsurePanel()
    panel:Show(); panel:Raise()
end

function PSM.TeamsPanel:Hide()
    if PSM.state.teamsPanel then PSM.state.teamsPanel:Hide() end
end

----------------------------------------------------------------------------------------------------------------
-- OPACITY UPDATE
----------------------------------------------------------------------------------------------------------------

function PSM.TeamsPanel:UpdateOpacity()
    -- Now handled centrally by PanelManager:UpdatePanelBackgrounds()
    -- This wrapper kept for backwards compatibility with external callers
    self:RefreshTeamsList()
end

----------------------------------------------------------------------------------------------------------------
-- SEARCH / FILTER
----------------------------------------------------------------------------------------------------------------

function PSM.TeamsPanel:FilterTeams(searchText)
    PSM.TeamsPanel._searchText = searchText:lower()
    PSM.TeamsPanel._searchMode = searchText ~= ""
    self:RefreshTeamsList()
end

function PSM.TeamsPanel:ClearComparisonCache()
    PSM.state.teamComparisonCache = {}
end

function PSM.TeamsPanel:DoesTeamMatchSearch(team)
    local search = PSM.TeamsPanel._searchText
    if not search or search == "" then return true end

    if team.name and team.name:lower():find(search, 1, true) then return true end

    if team.slots then
        for slot = 1, 6 do
            local pet = team.slots[slot]
            if pet then
                if pet.name       and pet.name:lower():find(search, 1, true)       then return true end
                if pet.familyName and pet.familyName:lower():find(search, 1, true)  then return true end
                if pet.specName   and pet.specName:lower():find(search, 1, true)    then return true end

                if pet.abilities and type(pet.abilities) == "table" then
                    for _, cat in ipairs({"family", "spec", "pet", "unknown"}) do
                        if pet.abilities[cat] then
                            for _, ability in ipairs(pet.abilities[cat]) do
                                if tostring(ability):lower():find(search, 1, true) then return true end
                            end
                        end
                    end
                end
            end
        end
    end

    return false
end

----------------------------------------------------------------------------------------------------------------
-- PET TOOLTIP
----------------------------------------------------------------------------------------------------------------

function PSM.TeamsPanel:ShowPetTooltip(container, petData, slot)
    GameTooltip:SetOwner(container, "ANCHOR_RIGHT", -20, -40)
    GameTooltip:SetText("Slot " .. slot .. (slot == 6 and " (Companion)" or " (Active)"), 1, 0.82, 0)
    GameTooltip:AddLine(petData.name or "Unknown Pet", 1, 1, 1)

    if petData.familyName then GameTooltip:AddLine("Family: " .. petData.familyName, 0.7, 0.7, 0.7) end
    if petData.specName   then GameTooltip:AddLine("Spec: "   .. petData.specName,   0.7, 0.7, 0.7) end
    if petData.isExotic   then GameTooltip:AddLine("|cffff8800Exotic|r") end

    local abilities = petData.abilities
    if abilities and type(abilities) == "table" then
        local lines = {}
        local cats  = {
            { key = "spec",    label = "|cFFFFFF00[Spec]|r"    },
            { key = "family",  label = "|cFF40FF40[Family]|r"  },
            { key = "pet",     label = " |cFF40FFFF[Pet]|r"    },
            { key = "unknown", label = "|cFFABABAB[Other]|r"   },
        }
        for _, cat in ipairs(cats) do
            if abilities[cat.key] and #abilities[cat.key] > 0 then
                table.insert(lines, cat.label)
                for _, ability in ipairs(abilities[cat.key]) do
                    table.insert(lines, "  • " .. ability)
                end
            end
        end
        if #lines > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Abilities:", 1, 0.82, 0)
            for _, line in ipairs(lines) do
                GameTooltip:AddLine(line, 0.8, 0.8, 0.8)
            end
        end
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cFFAAAAAA[Drag to rearrange]|r",   0.5, 0.5, 0.5)
    GameTooltip:AddLine("|cFFAAAAAA[Hover + X to remove]|r", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

----------------------------------------------------------------------------------------------------------------
-- ENABLE BUTTONS
----------------------------------------------------------------------------------------------------------------

local function EnableButton(btn)
    if not btn then return end
    btn:Enable()
    btn:SetAlpha(1)
    if btn.tooltipOverlay then
        btn.tooltipOverlay:Hide()
        btn.tooltipOverlay:EnableMouse(false)
    end
end

local function EnablePetTeamsButtons()
    local menu  = PSM.state and PSM.state.menu
    local panel = PSM.state and PSM.state.panel

    if menu and menu.teamsButton then
        EnableButton(menu.teamsButton)
        menu.teamsButton:SetScript("OnEnter", function(self)
            local count = PSM.Teams and PSM.Teams:GetTeamCount() or 0
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText("View and manage saved pet teams")
            GameTooltip:AddLine("You have " .. count .. " saved team(s)", 1, 1, 1)
            GameTooltip:Show()
        end)
        menu.teamsButton:SetScript("OnLeave", HideTooltip)
    end

    if panel and panel.teamsButton then
        EnableButton(panel.teamsButton)
    end

    if StableFrame and StableFrame.PSM_TeamsListButton then
        EnableButton(StableFrame.PSM_TeamsListButton)
    end
end

C_Timer.After(0.1, EnablePetTeamsButtons)
