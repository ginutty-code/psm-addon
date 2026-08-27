-- ModelsBrowser/ModelsPanel.lua
-- Performance-optimized Pet Models Browser Panel


_G.PSM = _G.PSM or {}
local PSM = _G.PSM

PSM.ModelsPanel = PSM.ModelsPanel or {}

-- Panel-specific constants (base values; scaling applied dynamically)
local MODELS_CONFIG = {
    PANEL_WIDTH    = 1100,
    PANEL_HEIGHT   = 820,
    ROW_HEIGHT     = 120,
    MODEL_SIZE     = 100,
    PETS_PER_PAGE  = 10,
    PETS_PER_COLUMN = 5,
    NPC_PETS_PER_PAGE = 30, -- text-only rows are cheap, so the NPC view can page much larger
    NPC_MAX_ROWS      = 40,
}

PSM.ModelsPanel.MODELS_CONFIG = MODELS_CONFIG

-- Release both render caches and cancel both pending renders.
--
-- The service core's PanelManager calls on last-panel-close, so the underscore cache
-- fields stay this addon's business and the timers are actually cancelled.
--
-- Safe to call when the loaders have not loaded: this file is what core reaches through,
-- and it must not assume its siblings parsed first.
function PSM.ModelsPanel:ReleaseCaches()
    if PSM.ModelsDataLoader and PSM.ModelsDataLoader.ReleaseCache then
        PSM.ModelsDataLoader:ReleaseCache()
    end
    if PSM.NPCDataLoader and PSM.NPCDataLoader.ReleaseCache then
        PSM.NPCDataLoader:ReleaseCache()
    end
end

-- ─────────────────────────────────────────────
-- Internal helpers
-- ─────────────────────────────────────────────

-- Returns petsPerColumn and petsPerPage from current DB settings.
-- In NPC view (single-column text rows) petsPerPage is a flat, larger constant.
local function GetPageLayout()
    local panel = PSM.state.modelsPanel
    if panel and panel.modelsViewMode == "npc" then
        local rowHeight    = PSM.NPCRow and PSM.NPCRow.ROW_HEIGHT or 22
        local headerHeight = PSM.NPCRow and PSM.NPCRow.HEADER_HEIGHT or 20
        local inset        = (PSM.NPCRow and PSM.NPCRow.TABLE_INSET) or 0
        local fit = MODELS_CONFIG.NPC_PETS_PER_PAGE
        if panel.petsFrame then
            -- Extra safety margin so the last row never runs into the
            -- pagination controls anchored just below petsFrame. `inset` is the
            -- gap above the header (UpdateNPCPanelLayout), which is height the
            -- rows no longer have.
            local available = panel.petsFrame:GetHeight() - inset - headerHeight - 50
            fit = math.max(5, math.floor(available / rowHeight))
        end
        return 1, math.min(fit, MODELS_CONFIG.NPC_MAX_ROWS)
    end
    local ppc = PetStableManagementDB.settings.petsPerColumn or PSM.Config.DEFAULT_PETS_PER_COLUMN
    return ppc, ppc * 2
end

-- Returns the item list backing the currently active view.
local function GetActiveList(panel)
    if panel.modelsViewMode == "npc" then
        return panel.allNPCs or {}
    end
    return panel.allModels or {}
end

-- Persists the current page to character-specific SavedVariables and state.
local function SaveCurrentPage(page)
    PetStableManagementDB = PetStableManagementDB or {}
    PetStableManagementDB.characters = PetStableManagementDB.characters or {}

    local charKey = UnitName("player") .. "-" .. GetRealmName()
    local chars = PetStableManagementDB.characters
    chars[charKey] = chars[charKey] or {}
    chars[charKey].settings = chars[charKey].settings or {}
    chars[charKey].settings.modelsPanelCurrentPage = page

    PSM.state.modelsPanelCurrentPage = page
    _G.PSM_modelsPanelCurrentPage    = page
end

-- Navigates to a page, clamps to valid range, and refreshes the view.
local function GoToPage(panel, page)
    local _, petsPerPage = GetPageLayout()
    local maxPages = math.max(1, math.ceil(#GetActiveList(panel) / petsPerPage))
    panel.currentPage = math.max(1, math.min(page, maxPages))
    SaveCurrentPage(panel.currentPage)
    if panel.modelsViewMode == "npc" then
        PSM.ModelsPanel:UpdateNPCPanelLayout()
    else
        PSM.ModelsPanel:UpdateModelsPanelLayout()
    end
end

-- ─────────────────────────────────────────────
-- Layout
-- ─────────────────────────────────────────────

-- Recomputes MODELS_CONFIG scaling and repositions model rows.
function PSM.ModelsPanel:UpdateModelsPanelLayout()
    local panel = PSM.state.modelsPanel
    if not panel then return end

    local ppc, ppp = GetPageLayout()
    local scale = 5 / ppc  -- base is 5 pets per column

    MODELS_CONFIG.PETS_PER_COLUMN = ppc
    MODELS_CONFIG.PETS_PER_PAGE   = ppp
    MODELS_CONFIG.MODEL_SIZE      = 100 * scale
    MODELS_CONFIG.ROW_HEIGHT      = 120 * scale

    if not panel.petsFrame then return end

    local columnWidth = (panel.petsFrame:GetWidth() - 30) / 2
    local MAX_ROWS = PSM.Config.MAX_PETS_PER_COLUMN * 2

    -- Position and size rows, show/hide based on current ppp
    for i = 1, MAX_ROWS do
        local row = panel.modelRows[i]
        if not row then break end
        if i <= ppp then
            local col = ((i - 1) % 2) + 1
            local r = math.floor((i - 1) / 2) + 1
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",
                10 + (col - 1) * (columnWidth + 10),
                -(r - 1) * MODELS_CONFIG.ROW_HEIGHT - 10)
            row:SetWidth(columnWidth)
            if row.model then
                row.model:SetWidth(MODELS_CONFIG.MODEL_SIZE)
                row.model:SetHeight(MODELS_CONFIG.MODEL_SIZE)
            end
            -- Visibility handled in UpdateVisibleRows
        else
            row:Hide()
        end
    end

    self:UpdateVisibleRows()
end

-- ─────────────────────────────────────────────
-- Panel construction
-- ─────────────────────────────────────────────

-- Restore the "Abilities (N families)" flag and the pure Abilities family set, which a
-- Special Tames re-Apply intersects against. The current family selection itself is
-- restored separately by BuildUnifiedFilterSystem from selectedModelsFamilies.
function PSM.ModelsPanel:LoadSavedFamiliesFromAbilities()
    if not PetStableManagementDB or not PetStableManagementDB.filters then
        return
    end
    if PetStableManagementDB.filters.familiesAppliedFromAbilities then
        PSM.state.familiesAppliedFromAbilities = true
        PSM.state.abilitiesFamilySet = PSM.Utils.DeepCopy(PetStableManagementDB.filters.selectedFamiliesFromAbilities) or {}
    end
end

function PSM.ModelsPanel:LoadSavedFilters()
    local saved = PetStableManagementDB and PetStableManagementDB.filters

    -- Merged into whatever is already selected, not replacing it: these run after the panel
    -- may have been seeded from the Ability Browser, so Replace would discard that.
    for ruleKey, val in pairs(saved and saved.selectedTamingRules or {}) do
        PSM.Selections:Set("tamingRules", ruleKey, val)
    end

    for cond, val in pairs(saved and saved.selectedConditions or {}) do
        PSM.Selections:Set("conditions", cond, val)
    end
end

function PSM.ModelsPanel:CreateModelsPanel()
    local panel = PSM.PanelManager:CreateBasePanel("modelsPanel", {
        width              = MODELS_CONFIG.PANEL_WIDTH,
        height             = MODELS_CONFIG.PANEL_HEIGHT,
        title              = PSM.L("Pet Model Browser"),
        resizable          = false,
        showResizeHandle   = false,
        showMaximizeButton = false,

        onShow = function(p)
            p._layoutDone = false
            C_Timer.After(0.01, function()
                if p.showPetsInMyZone then
                    p.currentPlayerZone = PSM.ModelsFilters:GetPlayerZone()
                end
                -- Load any families that were saved from the Abilities panel
                PSM.ModelsPanel:LoadSavedFilters()
                PSM.ModelsPanel:LoadSavedFamiliesFromAbilities()
                if p.modelsViewMode == "npc" then
                    PSM.NPCDataLoader:LoadNPCsForSelectedFamilies()
                else
                    PSM.ModelsDataLoader:LoadModelsForSelectedFamilies()
                end
                p.currentPage = PSM.state.modelsPanelCurrentPage or 1
                _G.PSM_modelsPanelCurrentPage = p.currentPage
            end)
        end,

        onHide = function(p)
            SaveCurrentPage(p.currentPage or PSM.state.modelsPanelCurrentPage or 1)
            PSM.PanelManager:CleanupPanel(p)
            PSM.state.wasOwnedPetsOpen = nil
            p._layoutDone = false
        end,
    })

    self:AddModelsBrowserElements(panel)
    self:RegisterZoneEventListeners()
    return panel
end

-- ─────────────────────────────────────────────
-- Zone events
-- ─────────────────────────────────────────────

function PSM.ModelsPanel:RegisterZoneEventListeners()
    local panel = PSM.state.modelsPanel
    if not panel or panel.zoneEventFrame then return end

    -- Raw CreateFrame, not PSM.CreateFrame: the core alias exists so core's headless
    -- tests can stub it, and reaching for it from the browser is the cross-addon capture
    -- pattern ModelRow.lua was fixed for.
    local f = CreateFrame("Frame")
    f:RegisterEvent("ZONE_CHANGED")
    f:RegisterEvent("ZONE_CHANGED_INDOORS")
    f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    f:SetScript("OnEvent", function()
        if not (panel:IsVisible() and PSM.FilterState:Get("showPetsInMyZone")) then return end

        local newZone = PSM.ModelsFilters:GetPlayerZone()
        if newZone and newZone ~= panel.currentPlayerZone then
            panel.currentPlayerZone = newZone
            if panel.modelsViewMode == "npc" then
                PSM.NPCDataLoader:LoadNPCsForSelectedFamilies()
            else
                PSM.ModelsDataLoader:LoadModelsForSelectedFamilies()
            end
            PSM.ModelsFilters:UpdateFilterSummary()
            PSM.ModelsFilters:UpdateDynamicFilters()
        end
    end)
    panel.zoneEventFrame = f
end

-- ─────────────────────────────────────────────
-- Pagination / rendering
-- ─────────────────────────────────────────────

function PSM.ModelsPanel:UpdateVisibleRows()
    local panel = PSM.state.modelsPanel
    if not panel then return end

    if panel.modelsViewMode == "npc" then
        self:UpdateVisibleNPCRows()
        return
    end

    if not panel.allModels then return end

    local totalPets = #panel.allModels

    for _, row in ipairs(panel.modelRows) do
        row:Hide()
    end

    if totalPets == 0 then
        if panel.pageText then panel.pageText:SetText(PSM.L("Page %d of %d", 0, 0)) end
        return
    end

    local ppc = PetStableManagementDB.settings.petsPerColumn or PSM.Config.DEFAULT_PETS_PER_COLUMN
    local petsPerPage = ppc * 2
    local scale = 5 / ppc

    local maxPages = math.max(1, math.ceil(totalPets / petsPerPage))

    local savedPage = PSM.state.modelsPanelCurrentPage
    if savedPage and savedPage >= 1 and savedPage <= maxPages then
        panel.currentPage = savedPage
    else
        panel.currentPage = math.max(1, math.min(panel.currentPage or 1, maxPages))
    end
    _G.PSM_modelsPanelCurrentPage = panel.currentPage

    if panel.pageText then
        panel.pageText:SetText(PSM.L("Page %d of %d", panel.currentPage, maxPages))
    end
    if panel.pageJumpEditBox then
        panel.pageJumpEditBox:SetText(tostring(panel.currentPage))
    end
    panel.prevButton:SetEnabled(panel.currentPage > 1)
    panel.nextButton:SetEnabled(panel.currentPage < maxPages)
    if panel.firstButton then panel.firstButton:SetEnabled(panel.currentPage > 1) end
    if panel.lastButton  then panel.lastButton:SetEnabled(panel.currentPage < maxPages) end

    local startIndex = (panel.currentPage - 1) * petsPerPage + 1
    local rowIndex = 1
    for i = startIndex, math.min(startIndex + petsPerPage - 1, totalPets) do
        local row  = panel.modelRows[rowIndex]
        local item = panel.allModels[i]
        if item and row then
            PSM.ModelRow:UpdateItemRow(row, item, i, scale)
            row:Show()
        end
        rowIndex = rowIndex + 1
    end
end

-- ─────────────────────────────────────────────
-- NPC view: pagination / rendering / layout
-- ─────────────────────────────────────────────

function PSM.ModelsPanel:UpdateVisibleNPCRows()
    local panel = PSM.state.modelsPanel
    if not panel or not panel.npcRows then return end

    local items = panel.allNPCs or {}
    local totalItems = #items

    if totalItems == 0 then
        for _, row in ipairs(panel.npcRows) do row:Hide() end
        if panel.pageText then panel.pageText:SetText(PSM.L("Page %d of %d", 0, 0)) end
        if panel.pageJumpEditBox then panel.pageJumpEditBox:SetText("0") end
        if panel.prevButton  then panel.prevButton:SetEnabled(false)  end
        if panel.nextButton  then panel.nextButton:SetEnabled(false)  end
        if panel.firstButton then panel.firstButton:SetEnabled(false) end
        if panel.lastButton  then panel.lastButton:SetEnabled(false)  end
        return
    end

    -- Built once per render pass rather than per row/per display-id: ownership
    -- is a per-(NPC, displayId) fact, not a per-row one, so each Display ID
    -- pill checks membership in this set individually.
    local ownedSet = {}
    for _, pet in ipairs(PSM.state.stablePets) do
        if pet.displayID then ownedSet[tonumber(pet.displayID)] = true end
    end
    panel.ownedDisplayIdSet = ownedSet

    -- Skip re-sorting when the list and sort criteria haven't changed.
    local sortCache = panel._npcSortCache
    if not sortCache or sortCache.items ~= items
       or sortCache.field ~= panel.npcSortField or sortCache.asc ~= panel.npcSortAsc then
        PSM.NPCRow:SortItems(panel, items)
        panel._npcSortCache = { items = items, field = panel.npcSortField, asc = panel.npcSortAsc }
    end

    local _, petsPerPage = GetPageLayout()
    local maxPages = math.max(1, math.ceil(totalItems / petsPerPage))

    local savedPage = PSM.state.modelsPanelCurrentPage
    if savedPage and savedPage >= 1 and savedPage <= maxPages then
        panel.currentPage = savedPage
    else
        panel.currentPage = math.max(1, math.min(panel.currentPage or 1, maxPages))
    end
    _G.PSM_modelsPanelCurrentPage = panel.currentPage

    if panel.pageText then
        panel.pageText:SetText(PSM.L("Page %d of %d", panel.currentPage, maxPages))
    end
    if panel.pageJumpEditBox then
        panel.pageJumpEditBox:SetText(tostring(panel.currentPage))
    end
    panel.prevButton:SetEnabled(panel.currentPage > 1)
    panel.nextButton:SetEnabled(panel.currentPage < maxPages)
    if panel.firstButton then panel.firstButton:SetEnabled(panel.currentPage > 1) end
    if panel.lastButton  then panel.lastButton:SetEnabled(panel.currentPage < maxPages) end

    local startIndex = (panel.currentPage - 1) * petsPerPage + 1
    local rowIndex = 1
    for i = startIndex, math.min(startIndex + petsPerPage - 1, totalItems) do
        local row  = panel.npcRows[rowIndex]
        local item = items[i]
        if item and row then
            PSM.NPCRow:UpdateItemRow(row, item, rowIndex)
        end
        rowIndex = rowIndex + 1
    end
    for i = rowIndex, #panel.npcRows do
        panel.npcRows[i]:Hide()
    end
end

-- Positions the header row and the npc row pool top-to-bottom, single column.
function PSM.ModelsPanel:UpdateNPCPanelLayout()
    local panel = PSM.state.modelsPanel
    if not panel or not panel.petsFrame or not panel.npcRows then return end

    PSM.NPCRow:UpdateHeaderRow(panel)

    local headerHeight = panel.npcHeaderRow and panel.npcHeaderRow:GetHeight() or PSM.NPCRow.HEADER_HEIGHT
    local rowHeight = PSM.NPCRow.ROW_HEIGHT
    -- Same inset the header uses (NPCRow's TABLE_INSET), so the rows sit inside
    -- petsFrame's silver border and their cells stay under the header's columns --
    -- the two anchor to different frames but share one column layout.
    local inset = PSM.NPCRow.TABLE_INSET
    for i, row in ipairs(panel.npcRows) do
        local yOffset = -(inset + headerHeight + (i - 1) * rowHeight)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",  panel.petsFrame, "TOPLEFT",   inset, yOffset)
        row:SetPoint("TOPRIGHT", panel.petsFrame, "TOPRIGHT", -inset, yOffset)
    end

    self:UpdateVisibleRows()
end

-- ─────────────────────────────────────────────
-- UI construction helpers
-- ─────────────────────────────────────────────

function PSM.ModelsPanel:AddModelsBrowserElements(panel)
    local Widgets = PSM.Widgets

    -- Tools: navigation to the other browser panels. Topmost in the rail, level with
    -- the title rather than FILTER_TOP -- the rail column (x=10..220) never shares
    -- horizontal space with the centered title/search box, so it can start as high as
    -- the title itself with no collision, recovering the room Tools needs without
    -- shrinking Show Only or Unified Filters below it.
    panel.toolsFrame = Widgets.Frame(panel, {
        size        = { 210, 125 },
        point       = { "TOPLEFT", 10, PSM.Theme.CHROME.TITLE_Y },
        backdrop    = "TOOLTIP",
        color       = PSM.Config.COLORS.BACKGROUND,
        borderColor = PSM.Theme.COLOR.SILVER,
    })

    Widgets.SectionHeader(panel.toolsFrame, {
        width = 200,
        point = { "TOPLEFT", 5, -5 },
        text  = PSM.L("Tools"),
    })

    -- Show Only filters frame
    panel.showOnlyFrame = Widgets.Frame(panel, {
        size        = { 210, 160 },
        point       = { "TOPLEFT", panel.toolsFrame, "BOTTOMLEFT", 0, -5 },
        backdrop    = "TOOLTIP",
        color       = PSM.Config.COLORS.BACKGROUND,
        borderColor = PSM.Theme.COLOR.SILVER,
    })

    Widgets.SectionHeader(panel.showOnlyFrame, {
        width = 200,
        point = { "TOPLEFT", 5, -5 },
        text  = PSM.L("Show Only"),
    })

    local MF = PSM.ModelsFilters
    if MF then
        if MF.CreateToolsBox            then MF:CreateToolsBox(panel)            end
        if MF.CreateRaresToggle         then MF:CreateRaresToggle(panel)         end
        if MF.CreateFavoritesToggle     then MF:CreateFavoritesToggle(panel)     end
        if MF.CreateHideOwnedToggle     then MF:CreateHideOwnedToggle(panel)     end
        if MF.CreateNameKeepersToggle  then MF:CreateNameKeepersToggle(panel)  end
        if MF.CreatePetsInMyZoneToggle  then MF:CreatePetsInMyZoneToggle(panel)  end
        if MF.CreateSearchBox           then MF:CreateSearchBox(panel)           end
        if MF.CreateResetFiltersButton  then MF:CreateResetFiltersButton(panel)  end
        if MF.CreateInfoText            then MF:CreateInfoText(panel)            end
        if MF.CreateFilterSummaryText   then MF:CreateFilterSummaryText(panel)   end
        if MF.BuildUnifiedFilterSystem  then MF:BuildUnifiedFilterSystem(panel) end
    end

    -- Room reserved below petsFrame for the pagination footer. Named so the footer
    -- controls below can derive their position from Theme.CHROME.FOOTER_Y instead of
    -- re-guessing their own offset from petsFrame's bottom edge.
    local FOOTER_INSET = 50

    -- Pets frame (2-column layout). Anchored to Show Only's top, pulled up 30px --
    -- a visual-balance choice specific to this panel, not a shared boundary: Models
    -- Browser is the only LEFT_RAIL panel, so there's no sibling panel this could drift
    -- out of step with. Level with Show Only exactly (offset 0) read as too far below
    -- the header once Tools pushed Show Only down; this splits the difference without
    -- moving Tools any higher (it's already at TITLE_Y, the highest it can go).
    local PETS_FRAME_TOP_LIFT = 50
    local petsFrame = Widgets.Frame(panel, {
        backdrop    = "TOOLTIP",
        color       = PSM.Config.COLORS.BACKGROUND,
        borderColor = PSM.Theme.COLOR.SILVER,  -- same as Tools/Show Only/Unified Filters
        point       = {
            { "TOPLEFT",     panel.showOnlyFrame, "TOPRIGHT", 25,  PETS_FRAME_TOP_LIFT },
            { "BOTTOMRIGHT", -10, FOOTER_INSET },
        },
    })

    -- Mouse-wheel navigation
    petsFrame:EnableMouseWheel(true)
    petsFrame:SetScript("OnMouseWheel", function(_, delta)
        GoToPage(panel, panel.currentPage + (delta < 0 and 1 or -1))
    end)

    panel.petsFrame  = petsFrame
    panel.modelRows  = {}
    panel.allModels  = {}
    panel.currentPage = PSM.state.modelsPanelCurrentPage or 1
    _G.PSM_modelsPanelCurrentPage = panel.currentPage

    -- Ensure petsPerColumn setting exists
    if PetStableManagementDB.settings.petsPerColumn == nil then
        PetStableManagementDB.settings.petsPerColumn = PSM.Config.DEFAULT_PETS_PER_COLUMN
    end

    -- Build pooled model rows (max possible, hidden initially)
    local MAX_ROWS = PSM.Config.MAX_PETS_PER_COLUMN * 2
    for i = 1, MAX_ROWS do
        local petRow = PSM.ModelRow:CreateModelRow(petsFrame)
        petRow:Hide()
        panel.modelRows[i] = petRow
    end

    -- ─── NPC view: mode state, toggle button, header row, row pool ───
    if PetStableManagementDB.settings.modelsViewMode == nil then
        PetStableManagementDB.settings.modelsViewMode = "displayId"
    end
    panel.modelsViewMode = PetStableManagementDB.settings.modelsViewMode

    panel.npcVisibleColumns = PSM.Utils.DeepCopy(PetStableManagementDB.settings.npcViewColumns)
        or PSM.NPCRow:GetDefaultVisibleColumns()

    panel.npcColumnWidths = PSM.Utils.DeepCopy(PetStableManagementDB.settings.npcViewColumnWidths) or {}

    local savedSort = PetStableManagementDB.settings.npcViewSort
    panel.npcSortField = (savedSort and savedSort.field) or "name"
    panel.npcSortAsc   = (savedSort and savedSort.asc)
    if panel.npcSortAsc == nil then panel.npcSortAsc = true end

    panel.allNPCs = {}
    panel.npcHeaderRow = PSM.NPCRow:CreateHeaderRow(petsFrame)

    panel.npcRows = {}
    for i = 1, MODELS_CONFIG.NPC_MAX_ROWS do
        local npcRow = PSM.NPCRow:CreateNPCRow(petsFrame)
        panel.npcRows[i] = npcRow
    end

    -- M, not S: this button is created with no text and relabelled to "Models view" /
    -- "NPC view" later, so it is the one button the truncation audit is blind to -- it
    -- measured an empty string at build time and reported nothing.
    local viewToggleButton = PSM.PanelManager:CreateViewButton(panel, {
        width = PSM.Theme.CONTROL.BUTTON_W.M,
    })
    panel.viewToggleButton = viewToggleButton

    local npcColumnsButton = PSM.NPCRow:CreateColumnsPicker(panel, viewToggleButton)

    local function RefreshViewToggleButtonText()
        viewToggleButton:SetText(panel.modelsViewMode == "npc" and PSM.L("Models view") or PSM.L("NPC view"))
    end

    -- PanelManager owns the rules for when the visible text may be replaced -- assigning
    -- placeholderText and calling SetText directly fires OnTextChanged and blanks the box.
    local function SetSearchPlaceholder(newPlaceholder)
        local box = panel.searchBox
        if box then box:SetPlaceholder(newPlaceholder) end
    end

    -- What a view mode *looks* like: which frames are up, and what the search box says.
    -- Separate from the rest of ApplyModelsViewMode because the panel's initial build needs
    -- exactly this and none of the page reset or data loading -- and one copy, so a panel
    -- restored into NPC view cannot open with the models placeholder.
    local function ApplyViewModePresentation(mode)
        RefreshViewToggleButtonText()
        if mode == "npc" then
            for _, row in ipairs(panel.modelRows) do row:Hide() end
            panel.npcHeaderRow:Show()
            npcColumnsButton:Show()
            SetSearchPlaceholder(PSM.L("Search NPCs..."))
        else
            for _, row in ipairs(panel.npcRows) do row:Hide() end
            panel.npcHeaderRow:Hide()
            npcColumnsButton:Hide()
            panel.npcColumnsPopout:Hide()
            SetSearchPlaceholder(PSM.L("Search models..."))
        end
    end

    local function ApplyModelsViewMode(mode)
        panel.modelsViewMode = mode
        PetStableManagementDB.settings.modelsViewMode = mode

        panel.currentPage = 1
        PSM.state.modelsPanelCurrentPage = 1
        _G.PSM_modelsPanelCurrentPage = 1
        SaveCurrentPage(1)

        ApplyViewModePresentation(mode)

        if mode == "npc" then
            PSM.ModelsPanel:UpdateNPCPanelLayout()
            PSM.NPCDataLoader:LoadNPCsForSelectedFamilies()
        else
            PSM.ModelsPanel:UpdateModelsPanelLayout()
            PSM.ModelsDataLoader:LoadModelsForSelectedFamilies()
        end
    end
    panel.ApplyModelsViewMode = ApplyModelsViewMode

    viewToggleButton:SetScript("OnClick", function()
        ApplyModelsViewMode(panel.modelsViewMode == "npc" and "displayId" or "npc")
    end)

    -- The restored mode, painted through the same function the toggle uses. Presentation
    -- only: loading is left to whatever shows the panel.
    ApplyViewModePresentation(panel.modelsViewMode)

    -- Navigation buttons. X stays anchored to petsFrame's own edges (it's the region
    -- these controls page through); Y is FOOTER_Y-derived so the whole band still
    -- moves as one with Theme.CHROME.FOOTER_Y instead of re-guessing its own offset.
    local firstButton = Widgets.Button(panel, {
        width   = PSM.Theme.CONTROL.BUTTON_W.XS,
        point   = { "BOTTOMLEFT", petsFrame, "BOTTOMLEFT", 0, PSM.Theme.CHROME.FOOTER_Y - FOOTER_INSET },
        text    = "First",
        onClick = function() GoToPage(panel, 1) end,
    })

    local prevButton = Widgets.Button(panel, {
        width   = PSM.Theme.CONTROL.BUTTON_W.S,
        point   = { "LEFT", firstButton, "RIGHT", 5, 0 },
        text    = PSM.L("Previous"),
        onClick = function() GoToPage(panel, panel.currentPage - 1) end,
    })

    local lastButton = Widgets.Button(panel, {
        width   = PSM.Theme.CONTROL.BUTTON_W.XS,
        point   = { "BOTTOMRIGHT", petsFrame, "BOTTOMRIGHT", 0, PSM.Theme.CHROME.FOOTER_Y - FOOTER_INSET },
        text    = "Last",
        onClick = function()
            local _, petsPerPage = GetPageLayout()
            local max = math.max(1, math.ceil(#GetActiveList(panel) / petsPerPage))
            GoToPage(panel, max)
        end,
    })

    local nextButton = Widgets.Button(panel, {
        width   = PSM.Theme.CONTROL.BUTTON_W.S,
        point   = { "RIGHT", lastButton, "LEFT", -5, 0 },
        text    = PSM.L("Next"),
        onClick = function() GoToPage(panel, panel.currentPage + 1) end,
    })

    local pageText = Widgets.Label(panel, {
        fontSize = PSM.Theme.SIZE.LABEL,
        point    = { "BOTTOM", petsFrame, "BOTTOM", 0, PSM.Theme.CHROME.FOOTER_Y - FOOTER_INSET + 10 },
        text     = PSM.L("Page %d of %d", 1, 1),
    })

    -- Page-jump controls
    local pageJumpFrame = Widgets.Frame(panel, {
        size  = { 150, 25 },
        point = { "BOTTOM", petsFrame, "BOTTOM", 0, PSM.Theme.CHROME.FOOTER_Y - FOOTER_INSET + 30 },
    })

    local pageJumpEditBox

    local function CommitPageJump()
        local _, ppp = GetPageLayout()
        local pageNum = tonumber(pageJumpEditBox:GetText())
        if pageNum and pageNum >= 1 and pageNum <= math.ceil(#GetActiveList(panel) / ppp) then
            GoToPage(panel, pageNum)
        end
        pageJumpEditBox:ClearFocus()
    end

    pageJumpEditBox = Widgets.EditBox(pageJumpFrame, {
        size     = { 50, 25 },
        point    = { "CENTER", pageJumpFrame, "CENTER", 0, 16 },
        onEnter  = CommitPageJump,
        onEscape = function(self) self:ClearFocus() end,
    })
    -- EditBox specifics the kit has no option for. Set on the returned frame, as
    -- Dialogs.lua does with SetMaxLetters -- they earn an option once a third caller
    -- wants them, not before.
    pageJumpEditBox:SetNumeric(true)
    pageJumpEditBox:SetMaxLetters(4)
    pageJumpEditBox:SetJustifyH("CENTER")

    local pageJumpButton = Widgets.Button(pageJumpFrame, {
        width   = PSM.Theme.CONTROL.BUTTON_W.XS,
        point   = { "LEFT", pageJumpEditBox, "RIGHT", 5, 0 },
        text    = "Go",
        onClick = CommitPageJump,
    })

    panel.prevButton       = prevButton
    panel.nextButton       = nextButton
    panel.firstButton      = firstButton
    panel.lastButton       = lastButton
    panel.pageText         = pageText
    panel.pageJumpEditBox  = pageJumpEditBox
    panel.pageJumpButton   = pageJumpButton

    -- Initialise state tables. Selections:Get creates the slice if absent, which is all the
    -- `= X or {}` here ever did.
    PSM.Selections:Get("families")
    PSM.state.favoriteModels = PSM.state.favoriteModels or {}

    -- A freshly built panel invalidates both loaders' cached results, which were computed
    -- against the panel being replaced.
    if PSM.ModelsDataLoader and PSM.ModelsDataLoader.ReleaseCache then
        PSM.ModelsDataLoader:ReleaseCache()
    end
    if PSM.NPCDataLoader and PSM.NPCDataLoader.ReleaseCache then
        PSM.NPCDataLoader:ReleaseCache()
    end

    -- Now that pagination controls exist, position the NPC row pool if that's
    -- the persisted starting mode (UpdateNPCPanelLayout touches panel.prevButton etc).
    if panel.modelsViewMode == "npc" then
        PSM.ModelsPanel:UpdateNPCPanelLayout()
    end
end

-- ─────────────────────────────────────────────
-- Public toggle
-- ─────────────────────────────────────────────

function PSM.ModelsPanel:Toggle()
    PSM.PanelManager:TogglePanel("modelsPanel", function() self:CreateModelsPanel() end, PSM.L("Pet Model Browser"))
end