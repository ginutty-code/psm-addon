-- TeamsPanel.lua
-- Teams panel UI for viewing and managing saved pet teams

local _, ns = ...
ns.TeamsPanel = ns.TeamsPanel or {}

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

----------------------------------------------------------------------------------------------------------------
-- LOCAL HELPERS
----------------------------------------------------------------------------------------------------------------


-- The one place that keeps an explicit size, rather than Theme.CONTROL.BUTTON and a
-- BUTTON_W tier: these are a stack of four in a 64px column whose height is computed
-- from them, and the standard sizes would overflow it. Adopting the standard means
-- re-laying out the teams row.
local function CreateActionButton(parent, text, width, height)
    return ns.Widgets.Button(parent, {
        size       = { width, height },
        text       = text,
        fontObject = "GameFontNormalSmall",
    })
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
    if not ns.state.teamsPanel then
        ns.TeamsPanel:CreateTeamsPanel()
    end
    return ns.state.teamsPanel
end

----------------------------------------------------------------------------------------------------------------
-- PET SLOT INTERACTIONS
----------------------------------------------------------------------------------------------------------------

local function CreateRemoveFromSlotButton(parent, container, slotNum, teamId)
    local btn = ns.Widgets.IconButton(parent, {
        size      = { 16, 16 },
        point     = { "TOPRIGHT", container, "TOPRIGHT", -20, -10 },
        level     = container:GetFrameLevel() + 2,
        texture   = "Interface\\Buttons\\UI-StopButton",
        highlight = "Interface\\Buttons\\UI-StopButton",
        pushed    = "Interface\\Buttons\\UI-StopButton",
        alpha     = 0.7,
        hidden    = true,
    })

    btn.teamId  = teamId
    btn.slotNum = slotNum

    btn:SetScript("OnClick", function(self)
        local team = ns.Teams:GetTeamById(self.teamId)
        if team and team.slots[self.slotNum] then
            team.slots[self.slotNum] = nil
            team.modifiedAt = time()
            ns.TeamsPanel:RefreshTeamsList()
        end
    end)
    ns.Tooltip.Attach(btn, { title = ns.L("Remove from Team") }, {
        onEnter = function(self) self:SetAlpha(1.0) end,
        onLeave = function(self) self:SetAlpha(0.7) end,
    })

    return btn
end

local function SetupPetSlotInteraction(container, petData, slot, team)
    container:SetScript("OnEnter", function(self)
        ns.TeamsPanel:ShowPetTooltip(self, petData, slot)
        if container.removeButton then container.removeButton:Show() end
    end)
    container:SetScript("OnLeave", function()
        ns.Tooltip.Hide()
        if container.removeButton and not container.removeButton:IsMouseOver() then
            container.removeButton:Hide()
        end
    end)
    container:EnableMouse(true)

    if container.removeButton then
        container.removeButton.teamId  = team.id
        container.removeButton.slotNum = slot
    end

    ns.DragDrop:SetupTeamSlotDragDrop(container, slot, team.id, team)
end

----------------------------------------------------------------------------------------------------------------
-- PANEL CREATION
----------------------------------------------------------------------------------------------------------------

function ns.TeamsPanel:CreateTeamsPanel()
    if ns.state.teamsPanel then return ns.state.teamsPanel end

    local savedPosition = ns.Data:GetTeamsPanelPosition() or {
        point = "TOPLEFT", relativeTo = "StableFrame",
        relativePoint = "TOPRIGHT", x = 0, y = 0
    }

    local config = {
        width    = ns.Data:GetTeamsPanelWidth()  or ns.Config.DEFAULT_PANEL_WIDTH,
        height   = ns.Data:GetTeamsPanelHeight() or ns.Config.DEFAULT_PANEL_HEIGHT,
        position = savedPosition,
        title    = ns.L("Pet Teams"),
        minWidth  = ns.Config.MIN_PANEL_WIDTH,
        minHeight = ns.Config.MIN_PANEL_HEIGHT,
        onHide   = function(p) ns.PanelManager:CleanupPanel(p) end,
        onShow   = function(p)
            if p._initialized then
                if ns.state.isStableOpen and #ns.state.stablePets == 0 then
                    ns.Data:CollectStablePets()
                end
                ns.TeamsPanel:RefreshTeamsList()
            end
        end,
        onResize = function(p)
            ns.Data:SetTeamsPanelSize(p:GetWidth(), p:GetHeight())
            if p._initialized and p:IsVisible() then
                ns.TeamsPanel:RefreshTeamsList()
            end
        end,
    }

    local panel = ns.PanelManager:CreateBasePanel("teamsPanel", config)
    panel._initialized = false
    self:AddTeamsPanelElements(panel)

    if panel.scrollFrame and panel.content then
        panel.content:SetWidth(panel.scrollFrame:GetWidth())
    end

    panel._initialized = true

    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, relativeTo, relativePoint, x, y = self:GetPoint(1)
        ns.Data:SetTeamsPanelPosition(point, relativeTo or "UIParent", relativePoint, x, y)
    end)

    return panel
end

function ns.TeamsPanel:AddTeamsPanelElements(panel)
    local Widgets = ns.Widgets

    -- Search box
    ns.PanelManager:CreateSearchBox(panel, function(searchText)
        ns.TeamsPanel:FilterTeams(searchText)
    end, {
        placeholder = ns.L("Search teams..."),
    })

    -- Scroll frame + content. No filter bar on this panel -- content starts right at
    -- FILTER_TOP, same as every TOP_BAR panel's filter row would if it had one.
    local scrollFrame = Widgets.Frame(panel, {
        frameType = "ScrollFrame",
        template  = "UIPanelScrollFrameTemplate",
        skin      = "scrollframe",
        point     = {
            { "TOPLEFT",      10, ns.Theme.CHROME.FILTER_TOP },
            { "BOTTOMRIGHT", -30,   35 },
        },
    })

    local teamsFrame = Widgets.Frame(panel, {
        backdrop = "TOOLTIP",
        color    = ns.Config.COLORS.BACKGROUND,
        level    = panel:GetFrameLevel() - 1,
        point    = {
            { "TOPLEFT",     scrollFrame, "TOPLEFT",     -5,  5 },
            { "BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT",  5, -5 },
        },
    })

    local content = Widgets.Frame(scrollFrame, {
        size = { scrollFrame:GetWidth() - 10, 100 },
    })
    scrollFrame:SetScrollChild(content)

    if scrollFrame.ScrollBar then
        scrollFrame.ScrollBar:SetAlpha(1)
        ns.Skin.Apply(scrollFrame.ScrollBar, "scrollbar")
    end

    panel.scrollFrame = scrollFrame
    panel.content     = content
    panel.teamsFrame  = teamsFrame
    panel.teamRows    = {}

    ns.PanelManager:CreateScrollPreservingResizeHandler(panel, scrollFrame, content, function()
        ns.TeamsPanel:RefreshTeamsList()
    end)

    -- Stats text
    panel.statsText = ns.PanelManager:CreateFooterLabel(panel, {
        outline = true,
        text    = ns.L("%d team(s) saved", 0),
    })

    -- Empty state message
    panel.emptyText = Widgets.Label(panel, {
        fontSize = ns.Theme.SIZE.LABEL,
        color    = ns.Theme.COLOR.GREY,
        point    = { "CENTER", content, "CENTER", 0, 0 },
        text     = ns.L("No teams saved yet.\nCreate your teams at the Stable Master \nor by adding pets from the Owned Pets panel."),
        hidden   = true,
    })
end

----------------------------------------------------------------------------------------------------------------
-- TEAM ROW CREATION
----------------------------------------------------------------------------------------------------------------

function ns.TeamsPanel:CreateTeamRow(parent)
    local slotSize       = ICON_SIZE + 45
    local slotSpacing    = -35
    local slot5to6Gap    = 30
    local buttonWidth    = 64   -- 55 clipped "Rename" by 6px; found by truncatedLabels
    local buttonHeight   = 18
    local buttonSpacing  = 5

    local Theme, Widgets = ns.Theme, ns.Widgets

    local row = Widgets.Frame(parent, {
        size     = { parent:GetWidth() - 10, ROW_HEIGHT },
        backdrop = "TOOLTIP_ROW",
        color    = ns.Config.COLORS.BACKGROUND,
    })

    row.nameText = Widgets.Label(row, {
        fontSize = Theme.SIZE.LABEL,
        outline  = true,
        color    = Theme.COLOR.GOLD,
        point    = { "TOPLEFT", 10, -8 },
        text     = ns.L("Team Name"),
    })

    row.infoText = Widgets.Label(row, {
        fontSize = Theme.SIZE.TINY,
        color    = Theme.COLOR.DIM,
        point    = { "TOPLEFT", row.nameText, "BOTTOMLEFT", 0, -2 },
    })

    -- Icons frame
    local iconsWidth = 6 * slotSize + 4 * slotSpacing + slot5to6Gap
    row.iconsFrame = Widgets.Frame(row, {
        size  = { iconsWidth, slotSize },
        point = { "BOTTOMLEFT", 0, 5 },
    })

    -- Divider between slots 5 and 6
    local slot5Right = (5 - 1) * (slotSize + slotSpacing) + slotSize
    local slot6Left  = 5 * (slotSize + slotSpacing) + slot5to6Gap
    row.dividerLine = Widgets.Texture(row.iconsFrame, {
        layer       = "OVERLAY",
        texture     = "Interface\\Buttons\\WHITE8X8",
        size        = { slot5to6Gap - 4, 2 },
        point       = { "CENTER", row.iconsFrame, "LEFT", (slot5Right + slot6Left) / 2, 0 },
        vertexColor = Theme.COLOR.GOLD,
    })

    -- Pet icon slots. The masked portrait + ring is Widgets.PetPortrait now (slotSize
    -- and ICON_SIZE are exactly its ringSize/portraitSize defaults). petIcons/petMasks/
    -- petBorders stay populated as aliases into the widget: DragDrop pokes
    -- row.petBorders for its drop-target tint and PanelManager:CleanupPanel iterates
    -- row.petIcons.
    row.petIcons          = {}
    row.petIconContainers = {}
    row.petMasks          = {}
    row.petBorders        = {}
    row.petPortraits      = {}

    for i = 1, 6 do
        local container = Widgets.Frame(row.iconsFrame, {
            frameType = "Button",
            size      = { slotSize, slotSize },
            point     = { "LEFT", SlotXPos(i, slotSize, slotSpacing, slot5to6Gap), 0 },
        })

        local pp = Widgets.PetPortrait(container)

        container:EnableMouse(true)
        container.displayId    = nil
        container.removeButton = CreateRemoveFromSlotButton(row.iconsFrame, container, i, nil)

        row.petPortraits[i]      = pp
        row.petIconContainers[i] = container
        row.petIcons[i]          = pp.portrait
        row.petMasks[i]          = pp.mask
        row.petBorders[i]        = pp.ring
    end

    -- Action buttons
    row.buttonsFrame = Widgets.Frame(row, {
        size  = { buttonWidth, 4 * buttonHeight + 3 * buttonSpacing },
        point = { "TOPRIGHT", row, "TOPRIGHT", -10, -25 },
    })

    local prevBtn
    for _, spec in ipairs({
        { key = "applyButton",     label = ns.L("Apply")  },
        { key = "duplicateButton", label = ns.L("Copy")   },
        { key = "renameButton",    label = ns.L("Rename") },
        { key = "deleteButton",    label = ns.L("Delete") },
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

function ns.TeamsPanel:UpdateTeamRow(row, team)
    if not row or not team then return end

    local alpha = ns.Config:GetOpacity()

    -- Name
    row.nameText:SetText(team.name or ns.L("Unnamed Team"))

    -- Info text
    local petCount = 0
    for slot = 1, 6 do
        if team.slots[slot] then petCount = petCount + 1 end
    end
    row.infoText:SetText(ns.L("%d/6 pets • Modified: %s", petCount, ns.Teams:FormatTimestamp(team.modifiedAt)))

    -- Pet icons
    for slot = 1, 6 do
        local container = row.petIconContainers[slot]
        local petData   = team.slots[slot]
        local hasArt     = petData and ((petData.displayID and petData.displayID > 0) or petData.icon)

        if hasArt then
            row.petPortraits[slot]:SetPet(petData)
            container.displayId = (petData.displayID and petData.displayID > 0) and petData.displayID or nil
            SetupPetSlotInteraction(container, petData, slot, team)
        else
            row.petPortraits[slot]:Clear()
            container.displayId = nil
            container:SetScript("OnEnter", nil)
            container:SetScript("OnLeave", nil)
            container:EnableMouse(false)
            if container.removeButton then container.removeButton:Hide() end
        end
    end

    -- Highlight based on active/match state
    local isActive      = (team.id == ns.Teams:GetActiveTeamId())
    local matchesCurrent = false
    if ns.state.isStableOpen then
        local cache = ns.state.teamComparisonCache or {}
        if cache[team.id] == nil then
            cache[team.id] = select(1, ns.Teams:CompareWithTeam(team.id))
            ns.state.teamComparisonCache = cache
        end
        matchesCurrent = cache[team.id]
    end

    if isActive and matchesCurrent then
        row:SetBackdropColor(unpack(ns.Config.COLORS.BACKGROUND_OWNED_SINGLE))
        row.nameText:SetTextColor(unpack(ns.Config.COLORS.SUCCESS))
    elseif isActive then
        row:SetBackdropColor(0.4, 0.25, 0.1, alpha)
        row.nameText:SetTextColor(unpack(ns.Theme.COLOR.ORANGE))
    else
        row:SetBackdropColor(unpack(ns.Config.COLORS.BACKGROUND))
        row.nameText:SetTextColor(unpack(ns.Config.COLORS.PRIMARY))
    end

    -- Button callbacks
    local teamId   = team.id
    local teamName = team.name

    -- Apply
    row.applyButton:SetScript("OnClick", function()
        if not ns.state.isStableOpen then
            ns.Utils:Msg("WARNING", ns.L("You must be at a Stable Master to apply a team."))
            return
        end
        ns.Dialogs:ShowApplyConfirmDialog(teamName, function()
            local ok, err = ns.Teams:ApplyTeam(teamId)
            if ok then
                ns.TeamsPanel:RefreshTeamsList()
            else
                ns.Utils:Msg("ERROR", err or ns.L("Failed to apply team"))
            end
        end)
    end)

    -- Apply button enabled state + tooltip overlay
    local applyEnabled = ns.state.isStableOpen
    row.applyButton:SetEnabled(applyEnabled)
    row.applyButton:SetAlpha(applyEnabled and 1 or 0.5)

    if not applyEnabled then
        if not row.applyButtonTooltipOverlay then
            local overlay = ns.Widgets.Frame(row.applyButton, { allPoints = true })
            overlay:EnableMouse(true)

            -- The old call was ShowTooltip(self, "ANCHOR_BOTTOM", text, 1, 0.5, 0)
            -- against a 5-parameter (owner, anchor, text, xOff, yOff) helper, so the
            -- intended warning-orange {1, 0.5, 0} was silently consumed as x=1,
            -- y=0.5 and a dropped third argument. The tooltip has been nudged half a
            -- pixel instead of coloured ever since. Stated as a colour now.
            ns.Tooltip.Attach(overlay, {
                anchor     = "ANCHOR_BOTTOM",
                title      = ns.L("Visit a Stable Master to apply teams"),
                titleColor = ns.Theme.COLOR.ORANGE,
            })

            row.applyButtonTooltipOverlay = overlay
        end
        row.applyButtonTooltipOverlay:Show()
    elseif row.applyButtonTooltipOverlay then
        row.applyButtonTooltipOverlay:Hide()
    end

    -- Rename
    row.renameButton:SetScript("OnClick", function()
        ns.Dialogs:ShowNameInputDialog({
            title = ns.L("Rename Team"),
            description = ns.L("Enter a new name for '%s':", teamName),
            defaultText = teamName,
            confirmText = ns.L("Rename"),
            onConfirm = function(newName)
                local ok, err = ns.Teams:RenameTeam(teamId, newName)
                if ok then ns.TeamsPanel:RefreshTeamsList()
                else ns.Utils:Msg("ERROR", err or ns.L("Failed to rename team")) end
            end,
        })
    end)

    -- Duplicate
    row.duplicateButton:SetScript("OnClick", function()
        ns.Dialogs:ShowNameInputDialog({
            title = ns.L("Duplicate Team"),
            description = ns.L("Enter a name for the copy of '%s':", teamName),
            defaultText = ns.L("%s (Copy)", teamName),
            confirmText = ns.L("Duplicate"),
            onConfirm = function(newName)
                local newId, err = ns.Teams:DuplicateTeam(teamId, newName)
                if newId then ns.TeamsPanel:RefreshTeamsList()
                else ns.Utils:Msg("ERROR", err or ns.L("Failed to duplicate team")) end
            end,
        })
    end)

    -- Delete
    row.deleteButton:SetScript("OnClick", function()
        ns.Dialogs:ShowDeleteConfirmDialog(teamName, function()
            local ok, err = ns.Teams:DeleteTeam(teamId)
            if ok then ns.TeamsPanel:RefreshTeamsList()
            else ns.Utils:Msg("ERROR", err or ns.L("Failed to delete team")) end
        end)
    end)

    row:Show()
end

----------------------------------------------------------------------------------------------------------------
-- REFRESH / RENDER QUEUE
----------------------------------------------------------------------------------------------------------------

local function ProcessRenderQueue()
    if not ns.state.teamsPanel or #renderQueue == 0 then
        isRendering = false
        return
    end
    for _ = 1, math.min(TEAMS_PER_FRAME, #renderQueue) do
        local item = table.remove(renderQueue, 1)
        if item and item.row and item.team then
            ns.TeamsPanel:UpdateTeamRow(item.row, item.team)
        end
    end
    if #renderQueue > 0 then
        C_Timer.After(ns.Config.RENDER_DELAY, ProcessRenderQueue)
    else
        isRendering = false
    end
end

-- This defers; the coalescing is a side effect. What it buys is getting
-- `DoRefreshTeamsList` out of the caller's call stack -- it rebuilds every team row, and
-- several callers are mid-operation on those very rows when they ask, so running it
-- synchronously would tear down frames underneath their own callbacks.
--
-- Not folded into `Config.RENDER_DELAY`: that is a progressive-render tick, this is a
-- reentrancy guard.
local REFRESH_DEFER = 0.03

function ns.TeamsPanel:RefreshTeamsList()
    if refreshDebounceTimer then refreshDebounceTimer:Cancel() end
    refreshDebounceTimer = C_Timer.NewTimer(REFRESH_DEFER, function()
        ns.TeamsPanel:DoRefreshTeamsList()
        refreshDebounceTimer = nil
    end)
end

function ns.TeamsPanel:DoRefreshTeamsList()
    local panel = ns.state.teamsPanel
    if not panel or not panel.content then return end

    self:ClearComparisonCache()

    local allTeams = ns.Teams:GetTeams()
    local teams    = {}
    for _, team in ipairs(allTeams) do
        if not ns.TeamsPanel._searchMode or self:DoesTeamMatchSearch(team) then
            table.insert(teams, team)
        end
    end

    local teamCount = #teams
    local allCount  = #allTeams

    panel.statsText:SetText(
        ns.TeamsPanel._searchMode
        and ns.L("%d of %d team(s) match", teamCount, allCount)
        or  ns.L("%d team(s) saved", allCount)
    )

    if teamCount == 0 then
        panel.emptyText:SetText(
            allCount == 0
            and ns.L("No teams saved yet.\nCreate your teams at the Stable Master \nor by adding pets from the Owned Pets panel.")
            or  ns.L("No teams match your search.")
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
        row.nameText:SetText(team.name or ns.L("Unnamed Team"))
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

function ns.TeamsPanel:Toggle()
    if ns.state.teamsPanel and ns.state.teamsPanel:IsVisible() then
        ns.state.teamsPanel:Hide()
        return
    end
    if ns.PanelManager:CombatBlocked(ns.L("Pet Teams")) then return end
    local panel = EnsurePanel()
    panel:Show(); panel:Raise()
end

function ns.TeamsPanel:Show()
    if ns.PanelManager:CombatBlocked(ns.L("Pet Teams")) then return end
    local panel = EnsurePanel()
    panel:Show(); panel:Raise()
end

----------------------------------------------------------------------------------------------------------------
-- OPACITY UPDATE
----------------------------------------------------------------------------------------------------------------

function ns.TeamsPanel:UpdateOpacity()
    -- Now handled centrally by PanelManager:UpdatePanelBackgrounds()
    -- This wrapper kept for backwards compatibility with external callers
    self:RefreshTeamsList()
end

----------------------------------------------------------------------------------------------------------------
-- SEARCH / FILTER
----------------------------------------------------------------------------------------------------------------

function ns.TeamsPanel:FilterTeams(searchText)
    ns.TeamsPanel._searchText = searchText:lower()
    ns.TeamsPanel._searchMode = searchText ~= ""
    self:RefreshTeamsList()
end

function ns.TeamsPanel:ClearComparisonCache()
    ns.state.teamComparisonCache = {}
end

function ns.TeamsPanel:DoesTeamMatchSearch(team)
    local search = ns.TeamsPanel._searchText
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

-- The same tooltip the owned-pets views show, so a pet reads identically wherever it
-- is looked at. Only the slot label and the trailing hints are the teams panel's own:
-- here a slot is a team position rather than a stable slot, and 6 is the companion.
function ns.TeamsPanel:ShowPetTooltip(container, petData, slot)
    local spec = ns.PetTooltip.Spec(petData, {
        slotLabel = slot == 6 and ns.L("Slot %s (Companion)", slot)
                                or ns.L("Slot %s (Active)", slot),
        hints     = ns.L("Drag to rearrange\nHover + X to remove"),
    })
    if not spec then return end

    -- Anchoring is this panel's business, not the shared content's: the team slots sit
    -- close to the right edge, so the tooltip is pulled back over them.
    spec.x, spec.y = -20, -40

    ns.Tooltip.Show(container, spec)
end

----------------------------------------------------------------------------------------------------------------
-- ENABLE BUTTONS
----------------------------------------------------------------------------------------------------------------

-- Nothing disables the Pet Teams buttons, so there is no re-enable pass here. The
-- saved-team-count tooltip comes from `PSM.Teams:ButtonTooltipSpec()` at build time,
-- attached every session rather than by a timer that has to win a race against login.
