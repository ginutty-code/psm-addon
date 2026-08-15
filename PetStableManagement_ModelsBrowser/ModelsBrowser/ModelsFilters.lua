-- ModelsBrowser/ModelsFilters.lua
-- Filtering system for the Pet Models Browser

local addonName = "PetStableManagement"

_G.PSM = _G.PSM or {}
local PSM = _G.PSM

PSM.ModelsFilters = PSM.ModelsFilters or {}

--------------------------------------------------------------------------------
-- EXOTIC FAMILIES
--------------------------------------------------------------------------------

local EXOTIC_FAMILIES = {
    ["Aqiri"] = true, ["Carapid"] = true, ["Chimaera"] = true,
    ["Core Hound"] = true, ["Devilsaur"] = true, ["Pterrordax"] = true,
    ["Shale Beast"] = true, ["Spirit Beast"] = true, ["Stone Hound"] = true,
    ["Water Strider"] = true, ["Whiptail"] = true, ["Worm"] = true,
}

function PSM.ModelsFilters:IsFamilyExotic(familyName)
    return familyName and EXOTIC_FAMILIES[familyName] or false
end

--------------------------------------------------------------------------------
-- TRISTATE CHECKBOX HELPER
--------------------------------------------------------------------------------

-- Create a tristate CheckButton. Cycles: nil → true → "inverted" → nil.
-- @param parent      parent frame
-- @param anchorTo    frame to anchor TOPLEFT/BOTTOMLEFT from (or nil for absolute)
-- @param label       text shown next to the checkbox
-- @param onChanged   function(triState) called after each state change
local function CreateTristateCheckbox(parent, anchorTo, label, onChanged)
    local Widgets = PSM.Widgets

    local point
    if anchorTo and anchorTo == parent.showOnlyFrame then
        point = { "TOPLEFT", anchorTo, "TOPLEFT", 8, -30 }
    elseif anchorTo then
        point = { "TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -5 }
    else
        point = { "TOPLEFT", 18, -19 }
    end

    local cb = Widgets.CheckBox(parent, { point = point })

    cb.text = Widgets.Label(cb, {
        fontSize = PSM.Theme.SIZE.SMALL,
        point    = { "LEFT", cb, "RIGHT", 5, 0 },
        text     = label,
    })
    cb.triState = nil
    cb:SetHitRectInsets(0, -150, 0, 0)

    cb:SetScript("OnClick", function(self)
        local check = self:GetCheckedTexture()
        if self.triState == nil then
            self.triState = true
            self:SetChecked(true)
            check:SetAlpha(1)
            if self.invertedTexture then self.invertedTexture:Hide() end
        elseif self.triState == true then
            self.triState = "inverted"
            self:SetChecked(true)
            check:SetAlpha(0)
            if not self.invertedTexture then
                self.invertedTexture = PSM.Widgets.Texture(self, {
                    layer   = "OVERLAY",
                    texture = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
                    size    = { PSM.Theme.CONTROL.CHECKBOX_MARK, PSM.Theme.CONTROL.CHECKBOX_MARK },
                    point   = { "CENTER", self, "CENTER", 0, 0 },
                })
            end
            self.invertedTexture:Show()
        else
            self.triState = nil
            self:SetChecked(false)
            check:SetAlpha(1)
            if self.invertedTexture then self.invertedTexture:Hide() end
        end
        if onChanged then onChanged(self.triState) end
    end)

    return cb
end

-- Reset a tristate checkbox to the nil (off) state without firing OnClick.
local function ResetTristateCheckbox(cb)
    if not cb then return end
    cb.triState = nil
    cb:SetChecked(false)
    cb:GetCheckedTexture():SetAlpha(1)
    if cb.invertedTexture then cb.invertedTexture:Hide() end
end

-- Initialize a tristate checkbox visual state from loaded value
local function InitTristateCheckboxFromState(checkbox, state)
    if state == nil then return end
    checkbox.triState = state
    checkbox:SetChecked(true)
    if state == "inverted" then
        checkbox:GetCheckedTexture():SetAlpha(0)
        if not checkbox.invertedTexture then
            checkbox.invertedTexture = PSM.Widgets.Texture(checkbox, {
                layer   = "OVERLAY",
                texture = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
                size    = { PSM.Theme.CONTROL.CHECKBOX_MARK, PSM.Theme.CONTROL.CHECKBOX_MARK },
                point   = { "CENTER", checkbox, "CENTER", 0, 0 },
            })
        end
        checkbox.invertedTexture:Show()
    else
        checkbox:GetCheckedTexture():SetAlpha(1)
    end
end

-- Families/Expansions/Locations persist here (PetStableManagementDB.filters), not through
-- the generic char.settings pipeline, so a save can't fire from an unrelated panel before
-- the Models Browser has built its own filter state. Public because AbilityBrowser.lua and
-- SpecialTames.lua drive selectedModelsFamilies directly via their own Apply buttons and
-- must call this too, or their narrowing won't survive a reload.
function PSM.ModelsFilters:PersistModelsFilterSelections()
    if not PetStableManagementDB then return end
    PetStableManagementDB.filters = PetStableManagementDB.filters or {}
    PetStableManagementDB.filters.selectedModelsFamilies = PSM.Utils.DeepCopy(PSM.state.selectedModelsFamilies) or {}
    PetStableManagementDB.filters.selectedExpansions     = PSM.Utils.DeepCopy(PSM.state.selectedExpansions) or {}
    PetStableManagementDB.filters.selectedLocations      = PSM.Utils.DeepCopy(PSM.state.selectedLocations) or {}
end

-- Single source of truth for selectedModelsFamilies given whichever of Abilities/Special
-- Tames are active: always fully rebuilds from the complete family list rather than
-- narrowing further from the current selection, so clearing one widens back out to just
-- the other (or everything) instead of staying stuck, and re-applying one with different
-- criteria replaces its own prior contribution instead of ANDing with it. Called only from
-- the two Apply handlers, which already own the family list when engaged; manual Families
-- tab edits outside those flows are untouched.
function PSM.ModelsFilters:RecomputeSmartFamilySelection()
    if not PSM.PetModels then return end

    local abilitiesSet = PSM.state.familiesAppliedFromAbilities and PSM.state.abilitiesFamilySet or nil

    local specialTamesSet
    if PSM.SpecialTames and PSM.SpecialTames.ComputeMatchingFamilies then
        specialTamesSet = PSM.SpecialTames:ComputeMatchingFamilies(
            PSM.state.selectedTamingRules or {}, PSM.state.selectedConditions or {})
    end

    PSM.state.selectedModelsFamilies = PSM.state.selectedModelsFamilies or {}
    for familyName in pairs(PSM.state.selectedModelsFamilies) do
        PSM.state.selectedModelsFamilies[familyName] = nil
    end

    for _, familyName in ipairs(PSM.PetModels:GetAvailableFamilies()) do
        local passAbilities    = not abilitiesSet    or abilitiesSet[familyName]
        local passSpecialTames = not specialTamesSet or specialTamesSet[familyName]
        if passAbilities and passSpecialTames then
            PSM.state.selectedModelsFamilies[familyName] = true
        end
    end
end

local function ReloadAndSummarise()
    local panel = PSM.state.modelsPanel
    if panel and panel.modelsViewMode == "npc" then
        PSM.NPCDataLoader:LoadNPCsForSelectedFamilies()
    else
        PSM.ModelsDataLoader:LoadModelsForSelectedFamilies()
    end
    PSM.ModelsFilters:UpdateFilterSummary()
    PSM.ModelsFilters:PersistModelsFilterSelections()
end

-- Exposed so other Apply flows (Abilities Browser, Special Tames) reload whichever
-- view is actually active instead of always refreshing the Models loader.
function PSM.ModelsFilters:ReloadAndSummarise()
    ReloadAndSummarise()
end

--------------------------------------------------------------------------------
-- TRISTATE TOGGLES
--------------------------------------------------------------------------------

function PSM.ModelsFilters:CreateRaresToggle(panel)
    -- Load saved state directly from SavedVariables
    local db = PetStableManagementDB and PetStableManagementDB.filters
    local savedState = db and db.showRares
    panel.showRares = savedState
    PSM.state.showRares = savedState
    panel.raresToggle = CreateTristateCheckbox(panel, panel.showOnlyFrame, "Rares", function(state)
        panel.showRares = state
        PSM.state.showRares = state
        PetStableManagementDB.filters = PetStableManagementDB.filters or {}
        PetStableManagementDB.filters.showRares = state
        ReloadAndSummarise()
        PSM.ModelsFilters:UpdateDynamicFilters()
    end)
    -- Initialize checkbox state from loaded value
    InitTristateCheckboxFromState(panel.raresToggle, panel.showRares)
end

function PSM.ModelsFilters:CreateFavoritesToggle(panel)
    -- Load saved state directly from SavedVariables
    local db = PetStableManagementDB and PetStableManagementDB.filters
    local savedState = db and db.showFavorites
    panel.showFavorites = savedState
    PSM.state.showFavorites = savedState
    panel.favoritesToggle = CreateTristateCheckbox(panel, panel.raresToggle, "Favorites", function(state)
        panel.showFavorites = state
        PSM.state.showFavorites = state
        PetStableManagementDB.filters = PetStableManagementDB.filters or {}
        PetStableManagementDB.filters.showFavorites = state
        ReloadAndSummarise()
        PSM.ModelsFilters:UpdateDynamicFilters()
    end)
    -- Initialize checkbox state from loaded value
    InitTristateCheckboxFromState(panel.favoritesToggle, panel.showFavorites)
end

function PSM.ModelsFilters:CreateHideOwnedToggle(panel)
    -- Load saved state directly from SavedVariables
    local db = PetStableManagementDB and PetStableManagementDB.filters
    local savedState = db and db.showHideOwned
    panel.showHideOwned = savedState
    PSM.state.showHideOwned = savedState
    panel.hideOwnedToggle = CreateTristateCheckbox(panel, panel.favoritesToggle, "Owned", function(state)
        -- Logic change: true = show only owned, inverted = hide owned
        if state == true then
            panel.showHideOwned = "inverted"
        elseif state == "inverted" then
            panel.showHideOwned = true
        else
            panel.showHideOwned = nil
        end
        PSM.state.showHideOwned = panel.showHideOwned
        PetStableManagementDB.filters = PetStableManagementDB.filters or {}
        PetStableManagementDB.filters.showHideOwned = panel.showHideOwned
        ReloadAndSummarise()
        PSM.ModelsFilters:UpdateDynamicFilters()
    end)
    -- Initialize checkbox state from loaded value, mapping the logic
    local mappedState
    if panel.showHideOwned == "inverted" then
        mappedState = true
    elseif panel.showHideOwned == true then
        mappedState = "inverted"
    else
        mappedState = nil
    end
    InitTristateCheckboxFromState(panel.hideOwnedToggle, mappedState)
end

function PSM.ModelsFilters:CreateNameKeepersToggle(panel)
    -- Load saved state directly from SavedVariables
    local db = PetStableManagementDB and PetStableManagementDB.filters
    local savedState = db and db.showNameKeepers
    panel.showNameKeepers = savedState
    PSM.state.showNameKeepers = savedState
    panel.nameKeepersToggle = CreateTristateCheckbox(panel, panel.hideOwnedToggle, "Name Keepers", function(state)
        panel.showNameKeepers = state
        PSM.state.showNameKeepers = state
        PetStableManagementDB.filters = PetStableManagementDB.filters or {}
        PetStableManagementDB.filters.showNameKeepers = state
        ReloadAndSummarise()
        PSM.ModelsFilters:UpdateDynamicFilters()
    end)
    -- Initialize checkbox state from loaded value
    InitTristateCheckboxFromState(panel.nameKeepersToggle, panel.showNameKeepers)
end

function PSM.ModelsFilters:CreatePetsInMyZoneToggle(panel)
    -- Load saved state directly from SavedVariables
    local db = PetStableManagementDB and PetStableManagementDB.filters
    local savedState = db and db.showPetsInMyZone
    panel.showPetsInMyZone = savedState
    PSM.state.showPetsInMyZone = savedState
    -- A persisted "on" state needs currentPlayerZone resolved now too, or the zone check is
    -- silently a no-op (showPetsInMyZone true, currentPlayerZone nil) until the toggle is
    -- clicked again this session.
    panel.currentPlayerZone = (savedState ~= nil) and PSM.ModelsFilters:GetPlayerZone() or nil
    panel.petsInMyZoneToggle = CreateTristateCheckbox(panel, panel.nameKeepersToggle, "Pets in My Zone", function(state)
        panel.currentPlayerZone = (state ~= nil) and PSM.ModelsFilters:GetPlayerZone() or nil
        panel.showPetsInMyZone  = state
        PSM.state.showPetsInMyZone = state
        PetStableManagementDB.filters = PetStableManagementDB.filters or {}
        PetStableManagementDB.filters.showPetsInMyZone = state
        ReloadAndSummarise()
        PSM.ModelsFilters:UpdateDynamicFilters()
    end)
    -- Initialize checkbox state from loaded value
    InitTristateCheckboxFromState(panel.petsInMyZoneToggle, panel.showPetsInMyZone)
end

function PSM.ModelsFilters:GetPlayerZone()
    if C_Map and C_Map.GetBestMapForUnit then
        local mapID = C_Map.GetBestMapForUnit("player")
        if mapID then return mapID end
    end
    return nil
end

function PSM.ModelsFilters:GetPlayerZoneName(uiMapId)
    if uiMapId and C_Map and C_Map.GetMapInfo then
        local info = C_Map.GetMapInfo(uiMapId)
        if info and info.name then return info.name end
    end
    local zone = GetRealZoneText()
    return (zone and zone ~= "") and zone or "Current Zone"
end

--------------------------------------------------------------------------------
-- SEARCH BOX
--------------------------------------------------------------------------------

function PSM.ModelsFilters:CreateSearchBox(panel)
    PSM.PanelManager:CreateSearchBox(panel, function(searchText)
        ReloadAndSummarise()
        PSM.ModelsFilters:UpdateDynamicFilters()
    end, {
        placeholder = "Search models...",
    })
end

--------------------------------------------------------------------------------
-- AUXILIARY BUTTONS
--------------------------------------------------------------------------------

function PSM.ModelsFilters:CreatePetRouletteButton(panel)
    panel.petRouletteButton = PSM.Widgets.Button(panel, {
        point      = { "TOPRIGHT", panel.searchBox, "TOPLEFT", -10, 0 },
        size       = { PSM.Config.BUTTON_WIDTH, PSM.Config.BUTTON_HEIGHT },
        text       = "Pet Roulette",
        fontObject = "GameFontNormalSmall",
        onClick    = function() PSM.PetRoulette:SelectPetRoulette() end,
    })
end

function PSM.ModelsFilters:CreateSpecialTamesButton(panel)
    panel.specialTamesButton = PSM.Widgets.Button(panel, {
        point      = { "BOTTOMLEFT", panel.showOnlyFrame, "TOPLEFT", 0, 5 },
        size       = { PSM.Config.BUTTON_WIDTH, PSM.Config.BUTTON_HEIGHT },
        text       = "Special Tames",
        fontObject = "GameFontNormalSmall",
        onClick    = function()
            if PSM.SpecialTames then PSM.SpecialTames:Toggle() end
        end,
    })
end

function PSM.ModelsFilters:CreateAbilityBrowserButton(panel)
    panel.abilityBrowserButton = PSM.Widgets.Button(panel, {
        point      = { "BOTTOMRIGHT", panel.showOnlyFrame, "TOPRIGHT", 0, 5 },
        size       = { PSM.Config.BUTTON_WIDTH, PSM.Config.BUTTON_HEIGHT },
        text       = "Ability Browser",
        fontObject = "GameFontNormalSmall",
        onClick    = function()
            if PSM.AbilityBrowser then PSM.AbilityBrowser:Toggle() end
        end,
    })
end

local RESET_FILTERS_EFFECTS = {
    "All Families selected", "All Expansions selected", "All Locations selected",
    "Rares: OFF", "Favorites: OFF", "Pets in My Zone: OFF", "Owned: OFF",
    "Clear search box", "Return to first page",
}

function PSM.ModelsFilters:CreateResetFiltersButton(panel)
    local lines = {}
    for _, text in ipairs(RESET_FILTERS_EFFECTS) do
        lines[#lines + 1] = { text = text, color = PSM.Theme.COLOR.FAINT }
    end

    panel.resetFiltersButton = PSM.Widgets.Button(panel, {
        point      = { "TOPLEFT", panel.searchBox, "TOPRIGHT", 10, 0 },
        size       = { PSM.Config.BUTTON_WIDTH, PSM.Config.BUTTON_HEIGHT },
        text       = "Reset Filters",
        fontObject = "GameFontNormalSmall",
        tooltip    = {
            anchor     = "ANCHOR_BOTTOMRIGHT",
            title      = "Reset all filters",
            titleColor = PSM.Theme.COLOR.WHITE,
            lines      = lines,
        },
        onClick    = function() PSM.ModelsFilters:ResetAllFilters(panel) end,
    })
end

--------------------------------------------------------------------------------
-- RESET ALL FILTERS
--------------------------------------------------------------------------------

-- Initialise (or re-initialise) a state map from a list, setting every entry true.
local function SelectAll(stateMap, list)
    for k in pairs(stateMap) do stateMap[k] = nil end
    for _, v in ipairs(list) do stateMap[v] = true end
end

-- Repopulate checkboxes for every tab, then restore the active tab.
local function RepopulateAllTabs(panel)
    local saved = panel.currentFilterType
    for _, t in ipairs({"families", "expansions", "locations"}) do
        panel.currentFilterType = t
        PSM.ModelsFilters:PopulateUnifiedFilterCheckboxes(panel)
    end
    panel.currentFilterType = saved
    PSM.ModelsFilters:PopulateUnifiedFilterCheckboxes(panel)
end

function PSM.ModelsFilters:ResetAllFilters(panel)
    panel.showRares        = false
    panel.showFavorites    = false
    panel.showNameKeepers  = false
    panel.showPetsInMyZone = false
    panel.showHideOwned    = false
    panel.currentPlayerZone= nil

    -- Reset state variables
    PSM.state.showRares = nil
    PSM.state.showFavorites = nil
    PSM.state.showNameKeepers = nil
    PSM.state.showPetsInMyZone = nil
    PSM.state.showHideOwned = nil
    PSM.state.selectedTamingRules = nil
    PSM.state.selectedConditions = nil
    PSM.state.familiesAppliedFromAbilities = nil
    PSM.state.abilitiesFamilySet = nil

    -- Persist resets to SavedVariables
    if PetStableManagementDB and PetStableManagementDB.filters then
        PetStableManagementDB.filters.showRares = nil
        PetStableManagementDB.filters.showFavorites = nil
        PetStableManagementDB.filters.showNameKeepers = nil
        PetStableManagementDB.filters.showPetsInMyZone = nil
        PetStableManagementDB.filters.showHideOwned = nil
        PetStableManagementDB.filters.selectedTamingRules = nil
        PetStableManagementDB.filters.selectedConditions = nil
        PetStableManagementDB.filters.selectedFamiliesFromAbilities = nil
        PetStableManagementDB.filters.familiesAppliedFromAbilities = nil
    end

    ResetTristateCheckbox(panel.raresToggle)
    ResetTristateCheckbox(panel.favoritesToggle)
    ResetTristateCheckbox(panel.hideOwnedToggle)
    ResetTristateCheckbox(panel.nameKeepersToggle)
    ResetTristateCheckbox(panel.petsInMyZoneToggle)
    

    -- ClearSearch, not SetText(""): the latter leaves the box blank, because the
    -- placeholder is only restored on focus loss.
    if panel.searchBox then panel.searchBox:ClearSearch() end

    if panel.familiesList  then SelectAll(PSM.state.selectedModelsFamilies, panel.familiesList)  end
    if panel.expansionList then SelectAll(PSM.state.selectedExpansions,      panel.expansionList) end
    if panel.locationList  then SelectAll(PSM.state.selectedLocations,       panel.locationList)  end

    RepopulateAllTabs(panel)
    ReloadAndSummarise()

    if PSM.SpecialTames and PSM.SpecialTames.ResetInternalState then
        PSM.SpecialTames:ResetInternalState()
    end

    if panel.currentPage and panel.currentPage ~= 1 then
        panel.currentPage = 1
        PSM.state.modelsPanelCurrentPage = 1
        _G.PSM_modelsPanelCurrentPage = 1
        if PSM.ModelsPanel and PSM.ModelsPanel.UpdateVisibleRows then
            PSM.ModelsPanel:UpdateVisibleRows()
        end
    end
end

--------------------------------------------------------------------------------
-- INFO / SUMMARY TEXT
--------------------------------------------------------------------------------

function PSM.ModelsFilters:CreateInfoText(panel)
    panel.infoText = PSM.Widgets.Label(panel, {
        fontSize = PSM.Theme.SIZE.SMALL,
        point    = { "TOP", panel.searchBox, "BOTTOM", 0, -5 },
        text     = "Loading...",
    })
end

function PSM.ModelsFilters:CreateFilterSummaryText(panel)
    panel.filterSummaryText = PSM.Widgets.Label(panel, {
        fontSize = PSM.Theme.SIZE.SMALL,
        color    = PSM.Theme.COLOR.FAINT,
        point    = { "TOP", panel.infoText, "BOTTOM", 0, -2 },
        text     = "",
    })
end

--------------------------------------------------------------------------------
-- LOCATION CONTINENT GROUPS — collapse state
--------------------------------------------------------------------------------
-- Mirrors OwnedPets/GroupedView.lua's PetStableManagementDB.collapsedGroups pattern, in its
-- own sibling table so continent names never collide with pet-group ids.

local function GetCollapsedContinentsState()
    if not PetStableManagementDB then PetStableManagementDB = {} end
    if not PetStableManagementDB.collapsedLocationContinents then
        PetStableManagementDB.collapsedLocationContinents = {}
    end
    return PetStableManagementDB.collapsedLocationContinents
end

local function IsContinentCollapsed(continentName)
    return continentName and GetCollapsedContinentsState()[continentName] == true
end

local function SetContinentCollapsed(continentName, collapsed)
    if continentName then GetCollapsedContinentsState()[continentName] = collapsed or nil end
end

local function ToggleContinentCollapsed(continentName)
    if not continentName then return end
    SetContinentCollapsed(continentName, not IsContinentCollapsed(continentName))
end

-- Collapse/expand every continent group at once; caller re-renders afterward.
local function SetAllContinentsCollapsed(panel, collapsed)
    if not panel or not panel.locationContinents then return end
    local seen = {}
    for _, continentName in pairs(panel.locationContinents) do
        if not seen[continentName] then
            seen[continentName] = true
            SetContinentCollapsed(continentName, collapsed)
        end
    end
end

--------------------------------------------------------------------------------
-- CONTEXT MENU
--------------------------------------------------------------------------------

-- Thin alias over the shared implementation, kept only so the call sites below read
-- unchanged. This file (and GroupedView.lua) each carried a verbatim copy of
-- PSM.Utils:ShowContextMenu, which had existed with zero callers the whole time --
-- and which already contained the corrected `notCheckable` line the copies got wrong.
local function ShowContextMenu(menuList)
    PSM.Utils:ShowContextMenu(menuList)
end

local function ShowContinentContextMenu(panel)
    local menuList = {
        { text = "Locations", isTitle = true, notCheckable = true },
        {
            text = "Expand All Continents", notCheckable = true,
            func = function()
                SetAllContinentsCollapsed(panel, false)
                PSM.ModelsFilters:PopulateUnifiedFilterCheckboxes(panel)
            end,
        },
        {
            text = "Collapse All Continents", notCheckable = true,
            func = function()
                SetAllContinentsCollapsed(panel, true)
                PSM.ModelsFilters:PopulateUnifiedFilterCheckboxes(panel)
            end,
        },
    }
    ShowContextMenu(menuList)
end

--------------------------------------------------------------------------------
-- UNIFIED FILTER SYSTEM
--------------------------------------------------------------------------------

-- Keep the state map if something already selected it this session (e.g. Ability Browser
-- pre-selects families before this runs), else restore the saved selection, else default
-- to everything -- the same state "Reset Filters" produces.
local function InitStateIfEmpty(stateMap, list, filtersKey)
    if next(stateMap) then return end

    local saved = filtersKey and PetStableManagementDB and PetStableManagementDB.filters
        and PetStableManagementDB.filters[filtersKey]
    if saved and next(saved) then
        for k, v in pairs(saved) do stateMap[k] = v end
        return
    end

    for _, v in ipairs(list) do stateMap[v] = true end
end

function PSM.ModelsFilters:BuildUnifiedFilterSystem(panel, modelsConfig)
    local families     = PSM.PetModels:GetAvailableFamilies()
    local allExpansions, allLocations = {}, {}

    -- The `families` list above is already empty whenever ModelsData isn't
    -- loaded (PetModels:GetAvailableFamilies), so a family-index-based
    -- fallback here would never have anything to iterate either -- just the
    -- one path, reading columns directly instead of scanning npcId-keyed
    -- records.
    if _G.ModelsData and type(_G.ModelsData) == "table" then
        local modelsData = _G.ModelsData
        for i = 1, #modelsData.NpcId do
            local expansion = PSM.PetModels.NpcExpansion(i)
            if expansion then
                allExpansions[expansion] = true
            end
            local uiMapId = modelsData.UiMapId[i]
            local uiMapName = uiMapId and modelsData.UiMapNames[uiMapId]
            if uiMapName then
                allLocations[uiMapName] = true
            end
        end
    end

    -- Build sorted lists — reuse EXPANSION_ORDER from ModelsDataLoader
    local expansionList = {}
    for e in pairs(allExpansions) do table.insert(expansionList, e) end
    table.sort(expansionList, function(a, b)
        -- Delegate to the shared constant in ModelsDataLoader
        local order = PSM.ModelsDataLoader._EXPANSION_ORDER or {}
        return (order[a] or 999) < (order[b] or 999)
    end)

    local locationList = {}
    for l in pairs(allLocations) do table.insert(locationList, l) end
    table.sort(locationList)

    -- Location name -> continent name, sourced from CoordsData.lua (zone-keyed, so continent
    -- lives once per zone there rather than repeated on every NPC in ModelsData.lua).
    local locationContinents = {}
    if _G.CoordsData and type(_G.CoordsData) == "table" then
        for _, zone in pairs(_G.CoordsData) do
            if type(zone) == "table" and zone.name then
                locationContinents[zone.name] = zone.continent or "Other"
            end
        end
    end

    -- Initialise state (only if empty — preserves saved selections)
    InitStateIfEmpty(PSM.state.selectedModelsFamilies, families,      "selectedModelsFamilies")
    InitStateIfEmpty(PSM.state.selectedExpansions,      expansionList, "selectedExpansions")
    InitStateIfEmpty(PSM.state.selectedLocations,       locationList,  "selectedLocations")

    -- Store for use by other functions
    panel.familiesList        = families
    panel.expansionList       = expansionList
    panel.locationList        = locationList
    panel.locationContinents  = locationContinents

        ---------- Filter frame ----------
    panel.unifiedFilterFrame = PSM.Widgets.Frame(panel, {
        point       = { "TOPLEFT", panel.showOnlyFrame, "BOTTOMLEFT", 0, -5 },
        size        = { 180, 505 },
        backdrop    = "TOOLTIP",
        color       = PSM.Config.COLORS.BACKGROUND,
        borderColor = { 0.75, 0.75, 0.75, 1 },  -- silver
    })

    ---------- Tab buttons ----------
    local tabFrame = PSM.Widgets.Frame(panel.unifiedFilterFrame, {
        point = { "TOPLEFT", panel.unifiedFilterFrame, "TOPLEFT", 5, -5 },
        size  = { 150, 20 },
    })

    local tabDefs = {
        { key="families",   label="Families"   },
        { key="expansions", label="Expansions" },
        { key="locations",  label="Locations"  },
    }
    local tabs = {}
    local prevTab = nil

    -- Forward-declare selectExoticBtn so OnTabClick can capture it (will be assigned later)
    local selectExoticBtn

    -- Visual update helper for tabs
    local function UpdateTabVisuals()
        for key, btn in pairs(tabs) do
            btn:SetActive(panel.currentFilterType == key)
        end
    end

    -- Tab click handler
    local function OnTabClick(key, hideExotic)
        panel.currentFilterType = key
        UpdateTabVisuals()
        PSM.ModelsFilters:PopulateUnifiedFilterCheckboxes(panel)
        PSM.ModelsFilters:UpdateDynamicFilters()
        if hideExotic then selectExoticBtn:Hide() else selectExoticBtn:Show() end
    end

    for _, def in ipairs(tabDefs) do
        local t = PSM.Widgets.Tab(tabFrame, {
            size       = { 55, 20 },
            fontObject = "GameFontHighlightSmall",
            text       = def.label,
            point      = prevTab
                and { "LEFT", prevTab,  "RIGHT", 3, 0 }
                or  { "LEFT", tabFrame, "LEFT",  0, 0 },
        })
        prevTab = t

        -- Capture values for closure to avoid loop variable reuse
        do
            local key = def.key
            local hideEx = (def.key ~= "families")
            local lbl = t.label

            -- Click handler
            t:SetScript("OnMouseDown", function(self)
                OnTabClick(key, hideEx)
            end)

            -- Hover update via mouse enter/leave
            t:SetScript("OnEnter", function(self)
                if panel.currentFilterType ~= key then
                    lbl:SetTextColor(unpack(PSM.Config.TAB.ACTIVE_TEXT))
                end
            end)
            t:SetScript("OnLeave", function(self)
                if panel.currentFilterType ~= key then
                    lbl:SetTextColor(unpack(PSM.Config.TAB.INACTIVE_TEXT))
                end
            end)
        end

        tabs[def.key] = t
    end

    panel.tabButtons = tabs

    ---------- All / None / Exotic buttons ----------
    local function MakeFilterButton(label, anchor, onClick)
        return PSM.Widgets.Button(panel.unifiedFilterFrame, {
            point      = { "LEFT", anchor, "RIGHT", 5, 0 },
            size       = { 50, 20 },
            text       = label,
            fontObject = "GameFontNormalSmall",
            onClick    = onClick,
        })
    end

    local selectAllBtn = PSM.Widgets.Button(panel.unifiedFilterFrame, {
        point      = { "TOPLEFT", tabFrame, "BOTTOMLEFT", 5, -5 },
        size       = { 50, 20 },
        text       = "All",
        fontObject = "GameFontNormalSmall",
        onClick    = function()
            if     panel.currentFilterType == "families"   then SelectAll(PSM.state.selectedModelsFamilies, families)
            elseif panel.currentFilterType == "expansions" then SelectAll(PSM.state.selectedExpansions, expansionList)
            elseif panel.currentFilterType == "locations"  then SelectAll(PSM.state.selectedLocations,  locationList)
            end
            PSM.ModelsFilters:PopulateUnifiedFilterCheckboxes(panel)
            ReloadAndSummarise()
            PSM.ModelsFilters:UpdateDynamicFilters()
        end,
    })

    local selectNoneBtn = MakeFilterButton("None", selectAllBtn, function()
        if     panel.currentFilterType == "families"   then PSM.state.selectedModelsFamilies = {}
        elseif panel.currentFilterType == "expansions" then PSM.state.selectedExpansions      = {}
        elseif panel.currentFilterType == "locations"  then PSM.state.selectedLocations       = {}
        end
        PSM.ModelsFilters:PopulateUnifiedFilterCheckboxes(panel)
        ReloadAndSummarise()
        PSM.ModelsFilters:UpdateDynamicFilters()
    end)

    selectExoticBtn = MakeFilterButton("Exotic", selectNoneBtn, function() end)
    selectExoticBtn.isExoticOnly = false
    panel.selectExoticBtn = selectExoticBtn

    -- Initialize exotic filter button state based on current family selections
    -- This detects whether exotic-only, non-exotic, or all families mode is active
    local function InitializeExoticFilterButton()
        local selected, exoticOnly, nonExoticOnly = 0, true, true
        for name, on in pairs(PSM.state.selectedModelsFamilies) do
            if on then
                selected = selected + 1
                if PSM.ModelsFilters:IsFamilyExotic(name) then
                    nonExoticOnly = false
                else
                    exoticOnly = false
                end
            end
        end
        local total = #families
        if selected ~= total then
            if exoticOnly and selected > 0 then
                -- Exotic only mode
                selectExoticBtn.isExoticOnly = true
                selectExoticBtn:SetText("Exotic")
            elseif nonExoticOnly and selected > 0 then
                -- Non-exotic (inverted) mode
                selectExoticBtn.isExoticOnly = false
                selectExoticBtn:SetText("!Exotic")
            else
                -- Mixed or default
                selectExoticBtn.isExoticOnly = false
                selectExoticBtn:SetText("Exotic")
            end
        else
            -- All families selected
            selectExoticBtn.isExoticOnly = false
            selectExoticBtn:SetText("Exotic")
        end
    end

    selectExoticBtn:SetScript("OnClick", function()
        if panel.currentFilterType == "families" then
            if selectExoticBtn.isExoticOnly then
                for _, n in ipairs(families) do
                    PSM.state.selectedModelsFamilies[n] = not PSM.ModelsFilters:IsFamilyExotic(n)
                end
                selectExoticBtn.isExoticOnly = false
                selectExoticBtn:SetText("!Exotic")
            else
                for _, n in ipairs(families) do
                    PSM.state.selectedModelsFamilies[n] = PSM.ModelsFilters:IsFamilyExotic(n)
                end
                selectExoticBtn.isExoticOnly = true
                selectExoticBtn:SetText("Exotic")
            end
        end
        PSM.ModelsFilters:PopulateUnifiedFilterCheckboxes(panel)
        ReloadAndSummarise()
        PSM.ModelsFilters:UpdateDynamicFilters()
    end)

    ---------- Scroll frame for checkboxes ----------
    local filterScrollFrame = PSM.Widgets.Frame(panel.unifiedFilterFrame, {
        frameType = "ScrollFrame",
        template  = "UIPanelScrollFrameTemplate",
        skin      = "scrollframe",
        point     = {
            { "TOPLEFT",     selectAllBtn,             "BOTTOMLEFT",  0, -5 },
            { "BOTTOMRIGHT", panel.unifiedFilterFrame, "BOTTOMRIGHT", 0,  5 },
        },
    })
    PSM.Skin.Apply(filterScrollFrame.ScrollBar, "scrollbar")

    local filterContent = PSM.Widgets.Frame(filterScrollFrame, {
        size = { filterScrollFrame:GetWidth() - 25, 100 },
    })
    filterScrollFrame:SetScrollChild(filterContent)

    panel.filterScrollFrame  = filterScrollFrame
    panel.filterContent      = filterContent
    panel.filterCheckboxes   = {}
    panel.filterHeaders      = {}
    panel.currentFilterType  = "families"


    ---------- Initial population ----------
    RepopulateAllTabs(panel)
    UpdateTabVisuals()

    -- Restore exotic filter button state based on current family selections
    InitializeExoticFilterButton()
end

--------------------------------------------------------------------------------
-- CHECKBOX POPULATION
--------------------------------------------------------------------------------

-- Pooled across refreshes -- 
local function GetPooledFilterCheckbox(panel, index)
    panel._filterCheckboxPool = panel._filterCheckboxPool or {}
    local cb = panel._filterCheckboxPool[index]
    if not cb then
        cb = PSM.Widgets.CheckBox(panel.filterContent)
        cb.text = PSM.Widgets.Label(cb, {
            fontSize = PSM.Theme.SIZE.SMALL,
            justify  = "LEFT",
            wordWrap = true,
            width    = 140,
            point    = { "LEFT", cb, "RIGHT", 5, 0 },
        })
        cb:SetHitRectInsets(0, -150, 0, 0)
        panel._filterCheckboxPool[index] = cb
    end
    return cb
end

function PSM.ModelsFilters:PopulateUnifiedFilterCheckboxes(panel)
    if not panel then return end

    for _, cb in ipairs(panel.filterCheckboxes) do cb:Hide() end
    panel.filterCheckboxes = {}
    panel.filterHeaders = panel.filterHeaders or {}
    for _, h in ipairs(panel.filterHeaders) do h:Hide() end
    panel.filterHeaders = {}

    if panel.currentFilterType == "locations" then
        self:PopulateLocationCheckboxes(panel)
        return
    end

    local items, selections
    if     panel.currentFilterType == "families"   then
        items      = PSM.ModelsDataLoader:GetAvailableFamiliesForFilters()
        selections = PSM.state.selectedModelsFamilies
    elseif panel.currentFilterType == "expansions" then
        items      = PSM.ModelsDataLoader:GetAvailableExpansionsForFilters()
        selections = PSM.state.selectedExpansions
    end

    local yOffset = 0
    for index, item in ipairs(items) do
        local cb = GetPooledFilterCheckbox(panel, index)
        cb:ClearAllPoints()
        cb:SetPoint("TOPLEFT", 0, -yOffset)

        local label = item
        if panel.currentFilterType == "families" and self:IsFamilyExotic(item) then
            label = item .. " |cffff8800[Exotic]|r"
        end
        cb.text:SetText(label)

        cb:SetChecked(selections[item] or false)
        cb:SetScript("OnClick", function(self)
            if     panel.currentFilterType == "families"   then PSM.state.selectedModelsFamilies[item] = self:GetChecked()
            elseif panel.currentFilterType == "expansions" then PSM.state.selectedExpansions[item]      = self:GetChecked()
            end
            ReloadAndSummarise()
            PSM.ModelsFilters:UpdateDynamicFilters()
        end)
        cb:Show()
        table.insert(panel.filterCheckboxes, cb)

        local lines = math.max(1, math.ceil(string.len(item) / 40))
        yOffset = yOffset + 25 * lines
    end

    panel.filterContent:SetHeight(yOffset)
end

--------------------------------------------------------------------------------
-- LOCATIONS: grouped by continent, with tristate rows and header bulk-actions
--------------------------------------------------------------------------------

local LOCATION_HEADER_H = 20
local LOCATION_GROUP_GAP = 4

-- Pooled the same way as GetPooledFilterCheckbox -- location lists can run
-- to 60+ rows, so recreating them every refresh was the bulk of the cost.
local function GetPooledLocationRow(panel, index)
    panel._locationRowPool = panel._locationRowPool or {}
    local cb = panel._locationRowPool[index]
    if not cb then
        -- PSM.Widgets.CheckBox skins before it returns, which is what this row needs:
        -- ElvUI's HandleCheckBox swaps in its own checked texture, and doing that after
        -- the first tristate render would clobber the alpha-0 + red-X "inverted" look.
        cb = PSM.Widgets.CheckBox(panel.filterContent)
        cb.text = PSM.Widgets.Label(cb, {
            fontSize = PSM.Theme.SIZE.SMALL,
            justify  = "LEFT",
            wordWrap = true,
            width    = 126,
            point    = { "LEFT", cb, "RIGHT", 5, 0 },
        })
        cb:SetHitRectInsets(0, -150, 0, 0)
        panel._locationRowPool[index] = cb
    end
    return cb
end

-- Tristate checkbox row for one location, mirroring SpecialTames.lua:CreateRuleRow's manual
-- visual/cycle pattern (nil -> true -> "inverted" -> nil).
local function CreateLocationRow(panel, index, item, yOffset)
    local cb = GetPooledLocationRow(panel, index)
    cb:ClearAllPoints()
    cb:SetPoint("TOPLEFT", 14, -yOffset)
    cb.text:SetText(item)

    local function UpdateVisual()
        local state = PSM.state.selectedLocations[item]
        local check = cb:GetCheckedTexture()
        if state == "inverted" then
            cb:SetChecked(true)
            check:SetAlpha(0)
            if not cb.invertedTexture then
                cb.invertedTexture = PSM.Widgets.Texture(cb, {
                    layer   = "OVERLAY",
                    texture = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
                    size    = { PSM.Theme.CONTROL.CHECKBOX_MARK, PSM.Theme.CONTROL.CHECKBOX_MARK },
                    point   = { "CENTER", cb, "CENTER", 0, 0 },
                })
            end
            cb.invertedTexture:Show()
        elseif state == true then
            cb:SetChecked(true)
            check:SetAlpha(1)
            if cb.invertedTexture then cb.invertedTexture:Hide() end
        else
            cb:SetChecked(false)
            check:SetAlpha(1)
            if cb.invertedTexture then cb.invertedTexture:Hide() end
        end
    end
    UpdateVisual()

    cb:SetScript("OnClick", function()
        local state = PSM.state.selectedLocations[item]
        if state == true then
            PSM.state.selectedLocations[item] = "inverted"
        elseif state == "inverted" then
            PSM.state.selectedLocations[item] = nil
        else
            PSM.state.selectedLocations[item] = true
        end
        UpdateVisual()
        ReloadAndSummarise()
        PSM.ModelsFilters:UpdateDynamicFilters()
    end)

    cb:Show()
    local lines = math.max(1, math.ceil(string.len(item) / 36))
    return cb, 25 * lines
end

-- Pooled like the rows above; invIcon is created once and toggled instead
-- of being conditionally created inline.
local function GetPooledContinentHeader(panel, index)
    panel._continentHeaderPool = panel._continentHeaderPool or {}
    local header = panel._continentHeaderPool[index]
    if not header then
        local Widgets = PSM.Widgets

        header = Widgets.Frame(panel.filterContent, { height = LOCATION_HEADER_H })
        header:EnableMouse(true)

        header.bg = Widgets.Texture(header, { layer = "BACKGROUND", allPoints = true })

        header.expandBtn = Widgets.IconButton(header, {
            size  = { 14, 14 },
            point = { "LEFT", header, "LEFT", 4, 0 },
            level = header:GetFrameLevel() + 1,
            skin  = "collapsebutton",
        })

        header.label = Widgets.Label(header, {
            fontObject = "GameFontNormalSmall",
            justify    = "LEFT",
            point      = { "LEFT", header.expandBtn, "RIGHT", 4, 0 },
        })

        header.invIcon = Widgets.Texture(header, {
            layer   = "OVERLAY",
            texture = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
            size    = { 12, 12 },
            point   = { "LEFT", header.label, "RIGHT", 4, 0 },
        })

        panel._continentHeaderPool[index] = header
    end
    return header
end

-- Header row for one continent group: dark bg + state-colored label (SpecialTames style),
-- left-click cycles select-all/exclude-all/clear-all for the group, +/- icon toggles collapse
-- for just this continent, right-click opens the Expand All/Collapse All menu.
local function CreateContinentHeader(panel, index, continentName, locs, yOffset)
    local header = GetPooledContinentHeader(panel, index)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT",  panel.filterContent, "TOPLEFT",  0, -yOffset)
    header:SetPoint("TOPRIGHT", panel.filterContent, "TOPRIGHT", 0, -yOffset)
    header.bg:SetColorTexture(0.12, 0.12, 0.12, 1)
    header.invIcon:Hide()

    local collapsed = IsContinentCollapsed(continentName)
    local tex = collapsed and PSM.Skin.Texture("PlusButton") or PSM.Skin.Texture("MinusButton")
    header.expandBtn:SetNormalTexture(tex)
    header.expandBtn:SetPushedTexture(tex)
    header.expandBtn:SetScript("OnClick", function()
        ToggleContinentCollapsed(continentName)
        PSM.ModelsFilters:PopulateUnifiedFilterCheckboxes(panel)
    end)

    header.label:SetText(continentName)

    -- Aggregate tristate visual across this continent's currently-visible locations
    local allSel, allInv, anyAct = true, true, false
    for _, loc in ipairs(locs) do
        local state = PSM.state.selectedLocations[loc]
        if state ~= true      then allSel = false end
        if state ~= "inverted" then allInv = false end
        if state == true or state == "inverted" then anyAct = true end
    end
    if allSel then
        header.label:SetTextColor(0, 1, 0)
    elseif allInv then
        header.label:SetTextColor(1, 0, 0)
        header.invIcon:Show()
    elseif anyAct then
        header.label:SetTextColor(1, 1, 1)
    else
        header.label:SetTextColor(0.6, 0.6, 0.6)
    end

    header:SetScript("OnEnter", function() header.bg:SetColorTexture(0.2, 0.2, 0.2, 1) end)
    header:SetScript("OnLeave", function() header.bg:SetColorTexture(0.12, 0.12, 0.12, 1) end)

    header:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            -- Cycle true -> inverted -> nil -> true. Checking "nil/false" first (not "~= true")
            -- matters: locations default to true, so a fully-inverted group must fall through
            -- to the else branch (nil) rather than being misread as "unselected" and bounced
            -- straight back to true.
            local hasUnselected, hasTrue = false, false
            for _, loc in ipairs(locs) do
                local st = PSM.state.selectedLocations[loc]
                if st == nil or st == false then hasUnselected = true end
                if st == true then hasTrue = true end
            end
            local nextState
            if     hasUnselected then nextState = true
            elseif hasTrue       then nextState = "inverted"
            else                      nextState = nil end
            for _, loc in ipairs(locs) do
                PSM.state.selectedLocations[loc] = nextState
            end
            ReloadAndSummarise()
            PSM.ModelsFilters:UpdateDynamicFilters()
        elseif button == "RightButton" then
            ShowContinentContextMenu(panel)
        end
    end)

    header:Show()
    return header
end

function PSM.ModelsFilters:PopulateLocationCheckboxes(panel)
    local items = PSM.ModelsDataLoader:GetAvailableLocationsForFilters()

    -- Group currently-visible locations by continent
    local groups, order = {}, {}
    for _, item in ipairs(items) do
        local continentName = (panel.locationContinents and panel.locationContinents[item]) or "Other"
        if not groups[continentName] then
            groups[continentName] = {}
            table.insert(order, continentName)
        end
        table.insert(groups[continentName], item)
    end
    for _, locs in pairs(groups) do table.sort(locs) end

    -- Alphabetical, "Other" always last
    table.sort(order, function(a, b)
        if a == "Other" then return false end
        if b == "Other" then return true end
        return a < b
    end)

    local yOffset = 0
    local headerIndex, rowIndex = 0, 0
    for _, continentName in ipairs(order) do
        local locs = groups[continentName]

        headerIndex = headerIndex + 1
        local header = CreateContinentHeader(panel, headerIndex, continentName, locs, yOffset)
        table.insert(panel.filterHeaders, header)
        yOffset = yOffset + LOCATION_HEADER_H + 2

        if not IsContinentCollapsed(continentName) then
            for _, item in ipairs(locs) do
                rowIndex = rowIndex + 1
                local cb, rowHeight = CreateLocationRow(panel, rowIndex, item, yOffset)
                table.insert(panel.filterCheckboxes, cb)
                yOffset = yOffset + rowHeight
            end
        end

        yOffset = yOffset + LOCATION_GROUP_GAP
    end

    panel.filterContent:SetHeight(yOffset)
end

--------------------------------------------------------------------------------
-- FILTER SUMMARY
--------------------------------------------------------------------------------

function PSM.ModelsFilters:GenerateFilterSummary()
    local panel = PSM.state.modelsPanel
    if not panel then return "" end

    local filters = {}
    local hasRules = PSM.state.selectedTamingRules and next(PSM.state.selectedTamingRules)
    local hasConds = PSM.state.selectedConditions and next(PSM.state.selectedConditions)
    local hasAbilities = PSM.state.familiesAppliedFromAbilities

    -- Families (Suppress family summary if Special Tames or Abilities are active, as they auto-populate the family list)
    if not (hasRules or hasConds or hasAbilities) then
        local selected, exoticOnly, nonExoticOnly = 0, true, true
        for name, on in pairs(PSM.state.selectedModelsFamilies) do
            if on then
                selected = selected + 1
                if   self:IsFamilyExotic(name) then nonExoticOnly = false
                else                                exoticOnly    = false end
            end
        end
        local total = #PSM.PetModels:GetAvailableFamilies()
        if selected ~= total then
            if   exoticOnly    and selected > 0 then table.insert(filters, "Families (Exotic only)")
            elseif nonExoticOnly and selected > 0 then table.insert(filters, "Families (not Exotic)")
            else                                       table.insert(filters, "Families") end
        end
    end

    -- Expansions
    if panel.expansionList then
        local expCount = 0
        for _, on in pairs(PSM.state.selectedExpansions) do if on then expCount = expCount + 1 end end
        if expCount ~= #panel.expansionList then table.insert(filters, "Expansions") end
    end

    -- Locations (tristate: active whenever anything deviates from the default "all true")
    if panel.locationList then
        local allDefaultTrue = true
        for _, l in ipairs(panel.locationList) do
            if PSM.state.selectedLocations[l] ~= true then allDefaultTrue = false; break end
        end
        if not allDefaultTrue then table.insert(filters, "Locations") end
    end

        -- Tristate toggles
    if panel.showRares == true then table.insert(filters, "Rares")
    elseif panel.showRares == "inverted" then table.insert(filters, "Not Rares") end

    if panel.showFavorites == true then table.insert(filters, "Favorites")
    elseif panel.showFavorites == "inverted" then table.insert(filters, "Not Favorites") end

    if panel.showNameKeepers == true then table.insert(filters, "Name Keepers")
    elseif panel.showNameKeepers == "inverted" then table.insert(filters, "Not Name Keepers") end

    if panel.showPetsInMyZone and panel.currentPlayerZone then
        local prefix = panel.showPetsInMyZone == "inverted" and "Not My Zone" or "My Zone"
        local zoneName = self:GetPlayerZoneName(panel.currentPlayerZone)
        table.insert(filters, prefix .. " (" .. zoneName .. ")")
    end

    if panel.showHideOwned == "inverted" then table.insert(filters, "Owned")
    elseif panel.showHideOwned == true then table.insert(filters, "Not Owned") end

    -- Search
    if (panel.searchBox:GetSearchText() or "") ~= "" then table.insert(filters, "Search") end

    -- Abilities (from Ability Browser)
    if hasAbilities then
        local selectedCount = 0
        for _, on in pairs(PSM.state.selectedModelsFamilies) do
            if on then selectedCount = selectedCount + 1 end
        end
        if selectedCount > 0 then
            table.insert(filters, "Abilities (" .. selectedCount .. " families)")
        end
    end

    -- Special Tames (Specific formatting for Unlocks and Conditions)
    -- Abilities and Special Tames now compose rather than being mutually exclusive, so
    -- both labels can be shown together -- this no longer clears the Abilities flag.
    if hasRules or hasConds then
        
        local stParts = {}

        if hasRules then
            local rCount = 0
            local lastRuleKey, lastRuleState
            for k, v in pairs(PSM.state.selectedTamingRules) do
                rCount = rCount + 1
                lastRuleKey, lastRuleState = k, v
            end
            if rCount == 1 then
                local rule = PSM.TamingRules and PSM.TamingRules[lastRuleKey]
                local label = rule and rule.label or lastRuleKey
                if lastRuleState == "inverted" then label = "Not " .. label end
                table.insert(stParts, label)
            else
                table.insert(stParts, "Multiple Skills")
            end
        end

        if hasConds then
            local cCount = 0
            local lastCondKey, lastCondState
            for k, v in pairs(PSM.state.selectedConditions) do
                cCount = cCount + 1
                lastCondKey, lastCondState = k, v
            end
            if cCount == 1 then
                local label = lastCondKey
                if lastCondState == "inverted" then label = "Not " .. label end
                table.insert(stParts, label)
            else
                table.insert(stParts, "Multiple Conditions")
            end
        end

        table.insert(filters, "Special Tames - " .. table.concat(stParts, "; "))
    end

    return #filters > 0 and ("Filters: " .. table.concat(filters, ", ")) or ""
end

function PSM.ModelsFilters:UpdateFilterSummary()
    local panel = PSM.state.modelsPanel
    if not panel or not panel.filterSummaryText then return end
    panel.filterSummaryText:SetText(self:GenerateFilterSummary())
end

function PSM.ModelsFilters:UpdateDynamicFilters()
    local panel = PSM.state.modelsPanel
    if not panel then return end
    PSM.ModelsFilters:PopulateUnifiedFilterCheckboxes(panel)
end