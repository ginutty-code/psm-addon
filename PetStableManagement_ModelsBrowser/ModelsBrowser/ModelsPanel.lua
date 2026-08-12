-- ModelsBrowser/ModelsPanel.lua
-- Performance-optimized Pet Models Browser Panel

local addonName = "PetStableManagement"

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
        local fit = MODELS_CONFIG.NPC_PETS_PER_PAGE
        if panel.petsFrame then
            -- Extra safety margin so the last row never runs into the
            -- pagination controls anchored just below petsFrame.
            local available = panel.petsFrame:GetHeight() - headerHeight - 50
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

function PSM.ModelsPanel:BuildPanel()
    if PSM.state.modelsPanel then return end
    self:LoadSavedPage()
    self:CreateModelsPanel()
end

function PSM.ModelsPanel:LoadSavedPage()
    local charKey = UnitName("player") .. "-" .. GetRealmName()
    local saved = PetStableManagementDB
        and PetStableManagementDB.characters
        and PetStableManagementDB.characters[charKey]
        and PetStableManagementDB.characters[charKey].settings
        and PetStableManagementDB.characters[charKey].settings.modelsPanelCurrentPage

    local page = saved or PSM.state.modelsPanelCurrentPage or 1
    PSM.state.modelsPanelCurrentPage = page
    _G.PSM_modelsPanelCurrentPage    = page
    return saved ~= nil
end

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
    -- Load selected taming rules from SavedVariables
    PSM.state.selectedTamingRules = PSM.state.selectedTamingRules or {}
    local savedTamingRules = PetStableManagementDB and PetStableManagementDB.filters and PetStableManagementDB.filters.selectedTamingRules
    if savedTamingRules then
        for ruleKey, val in pairs(savedTamingRules) do
            PSM.state.selectedTamingRules[ruleKey] = val
        end
    end

    -- Load selected conditions from SavedVariables
    PSM.state.selectedConditions = PSM.state.selectedConditions or {}
    local savedConditions = PetStableManagementDB and PetStableManagementDB.filters and PetStableManagementDB.filters.selectedConditions
    if savedConditions then
        for cond, val in pairs(savedConditions) do
            PSM.state.selectedConditions[cond] = val
        end
    end
end

function PSM.ModelsPanel:CreateModelsPanel()
    local panel = PSM.PanelManager:CreateBasePanel("modelsPanel", {
        width              = MODELS_CONFIG.PANEL_WIDTH,
        height             = MODELS_CONFIG.PANEL_HEIGHT,
        title              = "Pet Model Browser",
        escKeyframe        = "PetStableManagementModelsPanel",
        resizable          = false,
        showResizeHandle   = false,
        showMaximizeButton = false,

        onShow = function(p)
            p._layoutDone = false
            p._renderGeneration = 0   -- reset generation on each open
            PSM.C_Timer.After(0.01, function()
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

    local f = PSM.CreateFrame("Frame")
    f:RegisterEvent("ZONE_CHANGED")
    f:RegisterEvent("ZONE_CHANGED_INDOORS")
    f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    f:SetScript("OnEvent", function()
        if not (panel:IsVisible() and panel.showPetsInMyZone) then return end

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

    panel._renderGeneration = (panel._renderGeneration or 0) + 1
    local myGen = panel._renderGeneration

    local totalPets = #panel.allModels

    for _, row in ipairs(panel.modelRows) do
        row:Hide()
    end

    if totalPets == 0 then
        if panel.pageText then panel.pageText:SetText("Page 0 of 0") end
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
        panel.pageText:SetText(string.format("Page %d of %d", panel.currentPage, maxPages))
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
        if panel.pageText then panel.pageText:SetText("Page 0 of 0") end
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
        panel.pageText:SetText(string.format("Page %d of %d", panel.currentPage, maxPages))
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
    for i, row in ipairs(panel.npcRows) do
        local yOffset = -(headerHeight + (i - 1) * rowHeight)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",  panel.petsFrame, "TOPLEFT",  0, yOffset)
        row:SetPoint("TOPRIGHT", panel.petsFrame, "TOPRIGHT", 0, yOffset)
    end

    self:UpdateVisibleRows()
end

-- ─────────────────────────────────────────────
-- UI construction helpers
-- ─────────────────────────────────────────────

function PSM.ModelsPanel:AddModelsBrowserElements(panel)
    local Widgets = PSM.Widgets

    -- Show Only filters frame
    panel.showOnlyFrame = Widgets.Frame(panel, {
        size        = { 180, 160 },
        point       = { "TOPLEFT", 10, -100 },
        backdrop    = "TOOLTIP",
        color       = PSM.Config.COLORS.BACKGROUND,
        borderColor = { 0.75, 0.75, 0.75, 1 },  -- silver
    })

    Widgets.SectionHeader(panel.showOnlyFrame, {
        size       = { 170, 20 },
        point      = { "TOPLEFT", 5, -5 },
        text       = "Show Only",
        fontObject = "GameFontHighlightSmall",
    })

    local MF = PSM.ModelsFilters
    if MF then
        if MF.CreateRaresToggle         then MF:CreateRaresToggle(panel)         end
        if MF.CreateFavoritesToggle     then MF:CreateFavoritesToggle(panel)     end
        if MF.CreateHideOwnedToggle     then MF:CreateHideOwnedToggle(panel)     end
        if MF.CreateNameKeepersToggle  then MF:CreateNameKeepersToggle(panel)  end
        if MF.CreatePetsInMyZoneToggle  then MF:CreatePetsInMyZoneToggle(panel)  end
        if MF.CreateSearchBox           then MF:CreateSearchBox(panel)           end
        if MF.CreateSpecialTamesButton then MF:CreateSpecialTamesButton(panel) end
        if MF.CreateAbilityBrowserButton then MF:CreateAbilityBrowserButton(panel) end
        if MF.CreatePetRouletteButton   then MF:CreatePetRouletteButton(panel)   end
        if MF.CreateResetFiltersButton  then MF:CreateResetFiltersButton(panel)  end
        if MF.CreateInfoText            then MF:CreateInfoText(panel)            end
        if MF.CreateFilterSummaryText   then MF:CreateFilterSummaryText(panel)   end
        if MF.BuildUnifiedFilterSystem  then MF:BuildUnifiedFilterSystem(panel, MODELS_CONFIG) end
    end

    -- Pets frame (2-column layout)
    local petsFrame = Widgets.Frame(panel, {
        backdrop = "TOOLTIP",
        color    = PSM.Config.COLORS.BACKGROUND,
        point    = {
            { "TOPLEFT",     panel.showOnlyFrame, "TOPRIGHT", 25,  0 },
            { "BOTTOMRIGHT", -10, 50 },
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

    local viewToggleButton = Widgets.Button(panel, {
        size       = { PSM.Config.PANEL_BUTTON_WIDTH, PSM.Config.PANEL_BUTTON_HEIGHT },
        point      = { "TOPRIGHT", panel.closeButton, "TOPLEFT", -2, 0 },
        fontObject = "GameFontNormalSmall",
    })
    panel.viewToggleButton = viewToggleButton

    local npcColumnsButton = PSM.NPCRow:CreateColumnsPicker(panel, viewToggleButton)

    local function RefreshViewToggleButtonText()
        viewToggleButton:SetText(panel.modelsViewMode == "npc" and "Models view" or "NPC view")
    end

    -- Swaps the search box placeholder; refreshes the visible text immediately
    -- if the box is idle (unfocused, still showing the old placeholder).
    local function SetSearchPlaceholder(newPlaceholder)
        local box = panel.searchBox
        if not box then return end
        local old = box.placeholderText
        box.placeholderText = newPlaceholder
        if not box:HasFocus() and box:GetText() == old then
            box:SetText(newPlaceholder)
            box:SetTextColor(0.5, 0.5, 0.5)
        end
    end

    local function ApplyModelsViewMode(mode)
        panel.modelsViewMode = mode
        PetStableManagementDB.settings.modelsViewMode = mode
        RefreshViewToggleButtonText()

        panel.currentPage = 1
        PSM.state.modelsPanelCurrentPage = 1
        _G.PSM_modelsPanelCurrentPage = 1
        SaveCurrentPage(1)

        if mode == "npc" then
            for _, row in ipairs(panel.modelRows) do row:Hide() end
            panel.npcHeaderRow:Show()
            npcColumnsButton:Show()
            SetSearchPlaceholder("Search NPCs...")
            PSM.ModelsPanel:UpdateNPCPanelLayout()
            PSM.NPCDataLoader:LoadNPCsForSelectedFamilies()
        else
            for _, row in ipairs(panel.npcRows) do row:Hide() end
            panel.npcHeaderRow:Hide()
            npcColumnsButton:Hide()
            panel.npcColumnsPopout:Hide()
            SetSearchPlaceholder("Search models...")
            PSM.ModelsPanel:UpdateModelsPanelLayout()
            PSM.ModelsDataLoader:LoadModelsForSelectedFamilies()
        end
    end
    panel.ApplyModelsViewMode = ApplyModelsViewMode

    viewToggleButton:SetScript("OnClick", function()
        ApplyModelsViewMode(panel.modelsViewMode == "npc" and "displayId" or "npc")
    end)

    RefreshViewToggleButtonText()
    if panel.modelsViewMode == "npc" then
        npcColumnsButton:Show()
        panel.npcHeaderRow:Show()
    else
        panel.npcHeaderRow:Hide()
        npcColumnsButton:Hide()
    end

    -- Navigation buttons
    local firstButton = Widgets.Button(panel, {
        size    = { 50, 25 },
        point   = { "BOTTOMLEFT", petsFrame, "BOTTOMLEFT", 0, -35 },
        text    = "First",
        onClick = function() GoToPage(panel, 1) end,
    })

    local prevButton = Widgets.Button(panel, {
        size    = { 80, 25 },
        point   = { "LEFT", firstButton, "RIGHT", 5, 0 },
        text    = "Previous",
        onClick = function() GoToPage(panel, panel.currentPage - 1) end,
    })

    local lastButton = Widgets.Button(panel, {
        size    = { 50, 25 },
        point   = { "BOTTOMRIGHT", petsFrame, "BOTTOMRIGHT", 0, -35 },
        text    = "Last",
        onClick = function()
            local _, petsPerPage = GetPageLayout()
            local max = math.max(1, math.ceil(#GetActiveList(panel) / petsPerPage))
            GoToPage(panel, max)
        end,
    })

    local nextButton = Widgets.Button(panel, {
        size    = { 80, 25 },
        point   = { "RIGHT", lastButton, "LEFT", -5, 0 },
        text    = "Next",
        onClick = function() GoToPage(panel, panel.currentPage + 1) end,
    })

    local pageText = Widgets.Label(panel, {
        fontSize = PSM.Theme.SIZE.LABEL,
        point    = { "BOTTOM", petsFrame, "BOTTOM", 0, -25 },
        text     = "Page 1 of 1",
    })

    -- Page-jump controls
    local pageJumpFrame = Widgets.Frame(panel, {
        size  = { 150, 25 },
        point = { "BOTTOM", petsFrame, "BOTTOM", 0, -5 },
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
        size    = { 60, 25 },
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

    -- Initialise state tables
    PSM.state.selectedModelsFamilies = PSM.state.selectedModelsFamilies or {}
    PSM.state.favoriteModels         = PSM.state.favoriteModels         or {}

    if PSM.ModelsDataLoader and PSM.ModelsDataLoader.CreateRenderCache then
        PSM.ModelsDataLoader:CreateRenderCache()
    end
    if PSM.NPCDataLoader and PSM.NPCDataLoader.CreateRenderCache then
        PSM.NPCDataLoader:CreateRenderCache()
    end

    -- Now that pagination controls exist, position the NPC row pool if that's
    -- the persisted starting mode (UpdateNPCPanelLayout touches panel.prevButton etc).
    if panel.modelsViewMode == "npc" then
        PSM.ModelsPanel:UpdateNPCPanelLayout()
    end
end

-- ─────────────────────────────────────────────
-- Magnification popup
-- ─────────────────────────────────────────────

function PSM.ModelsPanel:ShowMagnificationPopup(displayId)
    if not displayId then return end

    if not PSM.state.modelMagnificationPopup then
        PSM.state.modelMagnificationPopup = PSM.PopUpManager:CreateModelPopup({
            title               = "Model Magnifier",
            width               = 500,
            height              = 500,
            modelSize           = nil,
            showPetModelsButton = false,
            showTryAgainButton  = false,
            resizable           = true,
            popupName           = "PetStableManagementMagnificationPopup",
            cleanupFunction     = function()
                local popup = PSM.state.modelMagnificationPopup
                if popup then
                    popup.currentPetData  = nil
                    popup.currentDisplayId = nil
                end
            end,
        })
        PSM.state.modelMagnificationPopup:Hide()
    end

    local popup = PSM.state.modelMagnificationPopup
    popup.currentDisplayId = displayId
    popup.currentNPCs    = nil

    PSM.C_Timer.After(0.1, function()
        local mf       = popup.modelFrame
        local settings = PetStableManagementDB.settings
        local views    = PSM.state.modelViews

        mf:SetDisplayInfo(displayId)
        mf:SetCamDistanceScale(1.0)

        if settings.stopAnimation then
            mf:FreezeAnimation(0, 0, 0)
        else
            mf:SetAnimation(0)
        end

        local globalZoom = settings.modelZoom or PSM.Config.DEFAULT_MODEL_ZOOM
        local savedView  = views and views[displayId]
        if savedView then
            mf.rotation = savedView.rotation or math.rad(settings.modelViewAngle or PSM.Config.DEFAULT_MODEL_VIEW_ANGLE)
            mf.zoom     = savedView.zoom or 1.0
            mf:SetRotation(mf.rotation)
            mf:SetCamDistanceScale(mf.zoom / globalZoom)
            mf:SetPosition(savedView.position and unpack(savedView.position) or 0, 0, 0)
        else
            mf.rotation = math.rad(settings.modelViewAngle or PSM.Config.DEFAULT_MODEL_VIEW_ANGLE)
            mf.zoom     = 1.0
            mf:SetRotation(mf.rotation)
            mf:SetCamDistanceScale(mf.zoom / globalZoom)
            mf:SetPosition(0, 0, 0)
        end

        mf.isRotating = false
        mf:Show()
    end)

    -- Favorites button state
    local favTex = PSM.state.favoriteModels[displayId]
        and {0, 0.5, 0, 0.5}
        or  {0.5, 1, 0, 0.5}
    popup.favoritesButton:GetNormalTexture():SetTexCoord(unpack(favTex))
    popup.favoritesButton:GetHighlightTexture():SetTexCoord(unpack(favTex))

    -- Resolve model data and family name
    local modelData, familyName

    -- 1. Models panel list
    if PSM.state.modelsPanel then
        for _, m in ipairs(PSM.state.modelsPanel.allModels or {}) do
            if m.displayId == displayId then
                modelData  = m
                familyName = m.familyName
                break
            end
        end
    end

    -- 2. Stable pets
    if not modelData then
        for _, pet in ipairs(PSM.state.stablePets or {}) do
            if pet.displayID == displayId then
                familyName = pet.familyName
                modelData  = { displayId = displayId, familyName = familyName, npcs = {} }
                break
            end
        end
    end

    -- 3. PetModels registry
    if not modelData and PSM.PetModels then
        for _, famName in ipairs(PSM.PetModels:GetAvailableFamilies()) do
            local info = PSM.PetModels:GetModelInfo(famName, displayId)
            if info then
                modelData  = info
                familyName = famName
                break
            end
        end
    end

    familyName = familyName or "Unknown"
    popup.infoText:SetText(string.format("%s - Display ID: %d", familyName, displayId))

    -- modelData.npcs / info.npcs are denseIndex values (see PetModels.lua's
    -- GetFamilyModels) -- resolve to full records before reading fields, and
    -- before handing off to popup.currentNPCs, which PopUpManager.lua's
    -- BuildNPCRows/CreateNPCRow also consume later (on resize or note-save)
    -- expecting object-style field access.

    -- Build NPC lines
    local function BuildNPCLines(npcs)
        local lines = {}
        for _, npc in ipairs(npcs) do
            local classTag = (npc.classification and npc.classification ~= "Normal")
                and string.format("%s, ", npc.classification) or ""
            lines[#lines + 1] = string.format(
                "%s (%s|Hnpc:%s|h|cff00ff00ID: %s|h|r, Location: %s, Expansion: %s)",
                npc.name,
                classTag,
                npc.npcId or "?",
                npc.npcId or "?",
                PSM.PopUpManager:BuildCoordsLocationLabel(npc.npcId, npc.location),
                npc.expansion or "Unknown")
        end
        return lines
    end

    local npcLines = {}
    if modelData and modelData.npcs and #modelData.npcs > 0 then
        local resolvedNpcs = PSM.PetModels:ResolveNpcRecords(modelData.npcs)
        npcLines = BuildNPCLines(resolvedNpcs)
        popup.currentNPCs = resolvedNpcs
    elseif PSM.PetModels then
        for _, famName in ipairs(PSM.PetModels:GetAvailableFamilies()) do
            local info = PSM.PetModels:GetModelInfo(famName, displayId)
            if info and info.npcs and #info.npcs > 0 then
                local resolvedNpcs = PSM.PetModels:ResolveNpcRecords(info.npcs)
                npcLines = BuildNPCLines(resolvedNpcs)
                popup.currentNPCs = resolvedNpcs
                break
            end
        end
    end

    if #npcLines == 0 then
        npcLines[1] = "No location data available"
    end

    local npcText = table.concat(npcLines, "\n")
    popup.currentNPCs = modelData and PSM.PetModels:ResolveNpcRecords(modelData.npcs or {}) or popup.currentNPCs or {}
    popup.npcPlainText = npcText
    popup:SetNPCText(npcText)
    popup.npcsScrollFrame:Show()
    popup.npcsScrollBar:Show()

    PSM.C_Timer.After(0.01, function()
        local extraHeight = popup.npcsText:GetContentHeight() - 7 + 20
        if extraHeight > 0 then
            local newHeight = math.max(
                popup.modelFrame:GetHeight() + 20,
                popup:GetHeight() - extraHeight + extraHeight)
            popup:SetHeight(newHeight)
        end
    end)

    popup:SetScript("OnEnter", nil)
    popup:SetScript("OnLeave", nil)
    popup:Show()
    popup:Raise()
end

-- ─────────────────────────────────────────────
-- Public toggle
-- ─────────────────────────────────────────────

function PSM.ModelsPanel:Toggle()
    if UnitAffectingCombat("player") then
        print("|cFFFF0000Pet Model Browser: Cannot open panel during combat.|r")
        return
    end
    PSM.PanelManager:TogglePanel("modelsPanel", function() self:CreateModelsPanel() end)
end