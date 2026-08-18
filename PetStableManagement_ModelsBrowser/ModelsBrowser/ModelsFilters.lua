-- ModelsBrowser/ModelsFilters.lua
-- Filtering system for the Pet Models Browser


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

-- Create a tristate CheckButton. Cycles: nil â†’ true â†’ "inverted" â†’ nil.
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

    PSM.Selections:Clear("families")
    for _, familyName in ipairs(PSM.PetModels:GetAvailableFamilies()) do
        local passAbilities    = not abilitiesSet    or abilitiesSet[familyName]
        local passSpecialTames = not specialTamesSet or specialTamesSet[familyName]
        if passAbilities and passSpecialTames then
            PSM.Selections:Set("families", familyName, true)
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
-- THE FILTER-CHANGE SUBSCRIPTION
--------------------------------------------------------------------------------

-- **A5.1 step 4.** This replaces nine hand-written
-- `ReloadAndSummarise() + UpdateDynamicFilters()` pairs. They were not two steps that both
-- had to happen: `ReloadAndSummarise` arms a debounce timer and returns, and the timer's
-- callback ends by calling `UpdateDynamicFilters` itself. The hand-written second half ran
-- *first*, synchronously, so the pill list narrowed on the click instead of 10-150ms later.
-- Preserved here, in one place, rather than retyped at every write site -- which is the
-- point, because a refresh a call site has to remember is one a call site can forget.
--
-- Three of those sites also called `PopulateUnifiedFilterCheckboxes(panel)` immediately
-- before `UpdateDynamicFilters()`, which is that same function behind a nil-panel guard.
-- Each rebuilt the entire checkbox list twice per click. They go with the rest.
--
-- **`panel` is deliberately not watched.** It bumps when the filter system is rebuilt, and
-- a rebuild already populates; watching it would turn construction into a reload.
--
-- `search` is fingerprinted off the search box, so it needs `Store:Touch()` to wake a
-- flush -- see CreateSearchBox below.
local FILTER_SLICES = {
    "families", "expansions", "locations", "tamingRules", "conditions",
    "toggles", "favorites", "pets", "zone", "search",
}

local watching = false

local function WatchFilterState()
    -- BuildUnifiedFilterSystem runs again whenever the panel is rebuilt, and a second
    -- watcher would mean a second reload per change.
    if watching then return end
    watching = true

    PSM.Store:Watch(FILTER_SLICES, function()
        ReloadAndSummarise()
        PSM.ModelsFilters:UpdateDynamicFilters()
    end)
end

--------------------------------------------------------------------------------
-- TRISTATE TOGGLES
--------------------------------------------------------------------------------

-- The three plain toggles differ only in their name, label and anchor, so they are one
-- function called three times rather than three near-copies of the same eight lines. The
-- two below this are genuinely different -- one inverts its meaning for display, the other
-- has to resolve the player's zone -- and stay separate for that reason, not by accident.
local function CreatePlainToggle(panel, key, label, anchorTo)
    local toggle = CreateTristateCheckbox(panel, anchorTo, label, function(state)
        PSM.FilterState:Set(key, state)
    end)
    InitTristateCheckboxFromState(toggle, PSM.FilterState:Get(key))
    return toggle
end

function PSM.ModelsFilters:CreateRaresToggle(panel)
    panel.raresToggle = CreatePlainToggle(panel, "showRares", PSM.L("Rares"), panel.showOnlyFrame)
end

function PSM.ModelsFilters:CreateFavoritesToggle(panel)
    panel.favoritesToggle = CreatePlainToggle(panel, "showFavorites", PSM.L("Favorites"), panel.raresToggle)
end

function PSM.ModelsFilters:CreateHideOwnedToggle(panel)
    -- The checkbox and the filter mean opposite things here: a ticked box reads as "show
    -- only owned" to the player, and is stored as "inverted". The mapping is applied in
    -- both directions -- on change below, and on load when seeding the checkbox.
    local function ToStored(state)
        if state == true then return "inverted" end
        if state == "inverted" then return true end
        return nil
    end

    panel.hideOwnedToggle = CreateTristateCheckbox(panel, panel.favoritesToggle, PSM.L("Owned"), function(state)
        PSM.FilterState:Set("showHideOwned", ToStored(state))
    end)
    -- ToStored is its own inverse (true <-> "inverted", nil -> nil), so it serves both ways.
    InitTristateCheckboxFromState(panel.hideOwnedToggle, ToStored(PSM.FilterState:Get("showHideOwned")))
end

function PSM.ModelsFilters:CreateNameKeepersToggle(panel)
    panel.nameKeepersToggle = CreatePlainToggle(panel, "showNameKeepers", PSM.L("Name Keepers"), panel.hideOwnedToggle)
end

function PSM.ModelsFilters:CreatePetsInMyZoneToggle(panel)
    -- A persisted "on" state needs currentPlayerZone resolved now too, or the zone check is
    -- silently a no-op (showPetsInMyZone true, currentPlayerZone nil) until the toggle is
    -- clicked again this session.
    local saved = PSM.FilterState:Get("showPetsInMyZone")
    panel.currentPlayerZone = (saved ~= nil) and PSM.ModelsFilters:GetPlayerZone() or nil

    panel.petsInMyZoneToggle = CreateTristateCheckbox(panel, panel.nameKeepersToggle, PSM.L("Pets in My Zone"), function(state)
        -- The zone is resolved *before* the toggle is stored, so the flush the store
        -- schedules off that write already sees the new `zone` fingerprint.
        panel.currentPlayerZone = (state ~= nil) and PSM.ModelsFilters:GetPlayerZone() or nil
        PSM.FilterState:Set("showPetsInMyZone", state)
    end)
    InitTristateCheckboxFromState(panel.petsInMyZoneToggle, saved)
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
    return (zone and zone ~= "") and zone or PSM.L("Current Zone")
end

--------------------------------------------------------------------------------
-- SEARCH BOX
--------------------------------------------------------------------------------

-- The last hand-written refresh pair, and it goes the same way as the other nine -- except
-- that a widget cannot bump a slice, so it asks the store to re-read instead.
--
-- **The text is not passed on, deliberately.** The `search` slice fingerprints the box
-- directly, so handing the value to a setter here would create a second copy that could
-- disagree with the widget -- which is the shape of every bug this section of the plan has
-- been unwinding. `Touch` says only "look again"; the store finds the text itself.
function PSM.ModelsFilters:CreateSearchBox(panel)
    PSM.PanelManager:CreateSearchBox(panel, function()
        PSM.Store:Touch()
    end, {
        placeholder = PSM.L("Search models..."),
    })
end

--------------------------------------------------------------------------------
-- AUXILIARY BUTTONS
--------------------------------------------------------------------------------

function PSM.ModelsFilters:CreatePetRouletteButton(panel)
    panel.petRouletteButton = PSM.Widgets.Button(panel, {
        point      = { "TOPRIGHT", panel.searchBox, "TOPLEFT", -10, 0 },
        width      = PSM.Theme.CONTROL.BUTTON_W.M,
        text       = PSM.L("Pet Roulette"),
        fontObject = "GameFontNormalSmall",
        onClick    = function() PSM.PetRoulette:SelectPetRoulette() end,
    })
end

function PSM.ModelsFilters:CreateSpecialTamesButton(panel)
    panel.specialTamesButton = PSM.Widgets.Button(panel, {
        point      = { "BOTTOMLEFT", panel.showOnlyFrame, "TOPLEFT", 0, 5 },
        width      = PSM.Theme.CONTROL.BUTTON_W.M,
        text       = PSM.L("Special Tames"),
        fontObject = "GameFontNormalSmall",
        onClick    = function()
            if PSM.SpecialTames then PSM.SpecialTames:Toggle() end
        end,
    })
end

function PSM.ModelsFilters:CreateAbilityBrowserButton(panel)
    panel.abilityBrowserButton = PSM.Widgets.Button(panel, {
        point      = { "BOTTOMRIGHT", panel.showOnlyFrame, "TOPRIGHT", 0, 5 },
        width      = PSM.Theme.CONTROL.BUTTON_W.M,
        text       = PSM.L("Ability Browser"),
        fontObject = "GameFontNormalSmall",
        onClick    = function()
            if PSM.AbilityBrowser then PSM.AbilityBrowser:Toggle() end
        end,
    })
end

local RESET_FILTERS_EFFECTS = {
    PSM.L("All Families selected"), PSM.L("All Expansions selected"),
    PSM.L("All Locations selected"),
    PSM.L("Rares: OFF"), PSM.L("Favorites: OFF"), PSM.L("Pets in My Zone: OFF"),
    PSM.L("Owned: OFF"),
    PSM.L("Clear search box"), PSM.L("Return to first page"),
}

function PSM.ModelsFilters:CreateResetFiltersButton(panel)
    local lines = {}
    for _, text in ipairs(RESET_FILTERS_EFFECTS) do
        lines[#lines + 1] = { text = text, color = PSM.Theme.COLOR.FAINT }
    end

    panel.resetFiltersButton = PSM.Widgets.Button(panel, {
        point      = { "TOPLEFT", panel.searchBox, "TOPRIGHT", 10, 0 },
        width      = PSM.Theme.CONTROL.BUTTON_W.M,
        text       = PSM.L("Reset Filters"),
        fontObject = "GameFontNormalSmall",
        tooltip    = {
            anchor     = "ANCHOR_BOTTOMRIGHT",
            title      = PSM.L("Reset all filters"),
            titleColor = PSM.Theme.COLOR.WHITE,
            lines      = lines,
        },
        onClick    = function() PSM.ModelsFilters:ResetAllFilters(panel) end,
    })
end

--------------------------------------------------------------------------------
-- RESET ALL FILTERS
--------------------------------------------------------------------------------

-- Select every entry in `list`, discarding whatever was selected before.
--
-- Takes a slice *name* rather than the table. Taking the table is what made this function
-- invisible: it wrote `stateMap[k]`, so no search for `selectedModelsFamilies` ever found
-- the three call sites below, and the write could not be counted, let alone funnelled.
local function SelectAll(slice, list)
    PSM.Selections:Clear(slice)
    PSM.Selections:SetAll(slice, list, true)
end

function PSM.ModelsFilters:ResetAllFilters(panel)
    -- One call clears all five, and it clears them where they live. This used to set five
    -- fields on the frame to `false` and the same five in SavedVariables to `nil` -- two
    -- lists, kept in step by hand, that had to agree because both were read.
    PSM.FilterState:Reset()
    panel.currentPlayerZone = nil

    -- Reset state variables. Cleared rather than set to nil: every reader tests
    -- `next(...)`, so an empty table and an absent one are indistinguishable to them, and
    -- keeping one table identity for the session means an alias taken elsewhere cannot be
    -- silently detached.
    PSM.Selections:Clear("tamingRules")
    PSM.Selections:Clear("conditions")
    PSM.state.familiesAppliedFromAbilities = nil
    PSM.state.abilitiesFamilySet = nil

    -- Persist resets to SavedVariables
    if PetStableManagementDB and PetStableManagementDB.filters then
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

    if panel.familiesList  then SelectAll("families",   panel.familiesList)  end
    if panel.expansionList then SelectAll("expansions", panel.expansionList) end
    if panel.locationList  then SelectAll("locations",  panel.locationList)  end

    -- **One rebuild, not four.** All three tabs share one `filterContent`, one
    -- `filterCheckboxes` list and one `filterHeaders` list, and
    -- `PopulateUnifiedFilterCheckboxes` opens by hiding whatever they hold -- so rebuilding
    -- each tab in turn only ever leaves the last. `OnTabClick` rebuilds on every switch, so
    -- there is nothing to pre-build.
    self:PopulateUnifiedFilterCheckboxes(panel)
    -- **A re-check, not a reload.** Everything above either bumps a slice or moves a
    -- fingerprint, so asking the store to look again is strictly better than calling the
    -- loader by hand: it cannot miss an input the watcher covers, and -- unlike the
    -- unconditional reload that used to sit here -- it does no work at all when Reset is
    -- pressed on filters that were already at their defaults.
    PSM.Store:Touch()

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
        text     = PSM.L("Loading..."),
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
-- LOCATION CONTINENT GROUPS â€” collapse state
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
        { text = PSM.L("Locations"), isTitle = true, notCheckable = true },
        {
            text = PSM.L("Expand All Continents"), notCheckable = true,
            func = function()
                SetAllContinentsCollapsed(panel, false)
                PSM.ModelsFilters:PopulateUnifiedFilterCheckboxes(panel)
            end,
        },
        {
            text = PSM.L("Collapse All Continents"), notCheckable = true,
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
local function InitStateIfEmpty(slice, list, filtersKey)
    if next(PSM.Selections:Get(slice)) then return end

    local saved = filtersKey and PetStableManagementDB and PetStableManagementDB.filters
        and PetStableManagementDB.filters[filtersKey]
    if saved and next(saved) then
        PSM.Selections:Replace(slice, saved)
        return
    end

    PSM.Selections:SetAll(slice, list, true)
end

function PSM.ModelsFilters:BuildUnifiedFilterSystem(panel)
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

    -- Build sorted lists â€” reuse EXPANSION_ORDER from ModelsDataLoader
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

    -- Initialise state (only if empty â€” preserves saved selections)
    InitStateIfEmpty("families",   families,      "selectedModelsFamilies")
    InitStateIfEmpty("expansions", expansionList, "selectedExpansions")
    InitStateIfEmpty("locations",  locationList,  "selectedLocations")

    -- The dynamic-filter selectors iterate panel.familiesList, set below. This is the only
    -- place it changes, so it is the only place the slice needs bumping.
    PSM.Store:Bump("panel")

    -- Registered *after* the InitStateIfEmpty writes above, not before: Watch records the
    -- current version as its baseline, so registering here means seeding a fresh panel's
    -- selections does not read as a filter change and trigger a reload on construction.
    WatchFilterState()

    -- Locations are two-state now. A saved "inverted" from the old three-state cycle
    -- already meant the same thing as unselected -- both excluded the location -- so fold
    -- it in rather than leaving a value the UI can render but no longer produce. Setting an
    -- existing key to nil during pairs() is defined behaviour; adding one is not.
    for loc, state in pairs(PSM.Selections:Get("locations")) do
        if state == "inverted" then PSM.Selections:Set("locations", loc, nil) end
    end

    -- Store for use by other functions
    panel.familiesList        = families
    panel.expansionList       = expansionList
    panel.locationList        = locationList
    panel.locationContinents  = locationContinents

        ---------- Filter frame ----------
    panel.unifiedFilterFrame = PSM.Widgets.Frame(panel, {
        point       = { "TOPLEFT", panel.showOnlyFrame, "BOTTOMLEFT", 0, -5 },
        size        = { 210, 505 },
        backdrop    = "TOOLTIP",
        color       = PSM.Config.COLORS.BACKGROUND,
        borderColor = { 0.75, 0.75, 0.75, 1 },  -- silver
    })

    ---------- Tab buttons ----------
    local tabFrame = PSM.Widgets.Frame(panel.unifiedFilterFrame, {
        point = { "TOPLEFT", panel.unifiedFilterFrame, "TOPLEFT", 5, -5 },
        size  = { 200, 20 },
    })

    local tabDefs = {
        { key="families",   label=PSM.L("Families")   },
        { key="expansions", label=PSM.L("Expansions") },
        { key="locations",  label=PSM.L("Locations")  },
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
        -- One rebuild, not two: UpdateDynamicFilters *is* PopulateUnifiedFilterCheckboxes
        -- with a nil-panel guard, so calling both rebuilt the whole checkbox list twice on
        -- every tab click.
        PSM.ModelsFilters:UpdateDynamicFilters()
        if hideExotic then selectExoticBtn:Hide() else selectExoticBtn:Show() end
    end

    for _, def in ipairs(tabDefs) do
        local t = PSM.Widgets.Tab(tabFrame, {
            size       = { 60, 20 },
            fontObject = "GameFontHighlightSmall",
            text       = def.label,
            point      = prevTab
                and { "LEFT", prevTab,  "RIGHT", 10, 0 }
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
    local function MakeFilterButton(label, anchor, onClick, width)
        return PSM.Widgets.Button(panel.unifiedFilterFrame, {
            point      = { "LEFT", anchor, "RIGHT", 5, 0 },
            width      = width or PSM.Theme.CONTROL.BUTTON_W.XS,
            text       = label,
            fontObject = "GameFontNormalSmall",
            onClick    = onClick,
        })
    end

    local selectAllBtn = PSM.Widgets.Button(panel.unifiedFilterFrame, {
        point      = { "TOPLEFT", tabFrame, "BOTTOMLEFT", 5, -5 },
        width      = PSM.Theme.CONTROL.BUTTON_W.XS,
        text       = "All",
        fontObject = "GameFontNormalSmall",
        onClick    = function()
            if     panel.currentFilterType == "families"   then SelectAll("families",   families)
            elseif panel.currentFilterType == "expansions" then SelectAll("expansions", expansionList)
            elseif panel.currentFilterType == "locations"  then SelectAll("locations",  locationList)
            end
        end,
    })

    local selectNoneBtn = MakeFilterButton("None", selectAllBtn, function()
        if     panel.currentFilterType == "families"   then PSM.Selections:Clear("families")
        elseif panel.currentFilterType == "expansions" then PSM.Selections:Clear("expansions")
        elseif panel.currentFilterType == "locations"  then PSM.Selections:Clear("locations")
        end
    end)

    -- S rather than XS: this button relabels itself to the longer "!Exotic", and at XS
    -- that cleared the tier by about a pixel. The truncation audit cannot vouch for it
    -- either way -- it only ever measures the label a button was *built* with, never
    -- what SetText puts there later -- so the button is given room instead of a margin.
    -- The widened 210 frame pays for it: 10 + 50 + 5 + 50 + 5 + 80 = 200.
    selectExoticBtn = MakeFilterButton("Exotic", selectNoneBtn, function() end,
                                       PSM.Theme.CONTROL.BUTTON_W.S)
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
                    PSM.Selections:Set("families", n, not PSM.ModelsFilters:IsFamilyExotic(n))
                end
                selectExoticBtn.isExoticOnly = false
                selectExoticBtn:SetText("!Exotic")
            else
                for _, n in ipairs(families) do
                    PSM.Selections:Set("families", n, PSM.ModelsFilters:IsFamilyExotic(n))
                end
                selectExoticBtn.isExoticOnly = true
                selectExoticBtn:SetText("Exotic")
            end
        end
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
    -- The active tab only; `OnTabClick` builds the others when they are first shown.
    PSM.ModelsFilters:PopulateUnifiedFilterCheckboxes(panel)
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
            if     panel.currentFilterType == "families"   then PSM.Selections:Set("families",   item, self:GetChecked())
            elseif panel.currentFilterType == "expansions" then PSM.Selections:Set("expansions", item, self:GetChecked())
            end
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

-- Plain two-state checkbox: checked = show this location, unchecked = don't.
--
-- Locations used to cycle nil -> true -> "inverted" -> nil like the Families and
-- Expansions filters. The third state bought the user nothing here, because locations are
-- seeded all-true (see InitStateIfEmpty): with an active selection always present, an
-- unchecked location already fails the include test, and "inverted" reached the same
-- outcome through the exclude path. Two ways to spell "hidden", and a click to cycle past
-- the one that looked different but was not.
local function CreateLocationRow(panel, index, item, yOffset)
    local cb = GetPooledLocationRow(panel, index)
    cb:ClearAllPoints()
    cb:SetPoint("TOPLEFT", 14, -yOffset)
    cb.text:SetText(item)

    local function UpdateVisual()
        cb:SetChecked(PSM.state.selectedLocations[item] == true)
        cb:GetCheckedTexture():SetAlpha(1)
    end
    UpdateVisual()

    cb:SetScript("OnClick", function()
        local selected = PSM.Selections:Get("locations")[item] == true
        PSM.Selections:Set("locations", item, (not selected) or nil)
        UpdateVisual()
    end)

    cb:Show()
    local lines = math.max(1, math.ceil(string.len(item) / 36))
    return cb, 25 * lines
end

-- Pooled like the rows above
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

        panel._continentHeaderPool[index] = header
    end
    return header
end

-- Header row for one continent group: dark bg + state-colored label (SpecialTames style),
-- left-click selects or clears the whole group, +/- icon toggles collapse
-- for just this continent, right-click opens the Expand All/Collapse All menu.
local function CreateContinentHeader(panel, index, continentName, locs, yOffset)
    local header = GetPooledContinentHeader(panel, index)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT",  panel.filterContent, "TOPLEFT",  0, -yOffset)
    header:SetPoint("TOPRIGHT", panel.filterContent, "TOPRIGHT", 0, -yOffset)
    header.bg:SetColorTexture(0.12, 0.12, 0.12, 1)

    local collapsed = IsContinentCollapsed(continentName)
    local tex = collapsed and PSM.Skin.Texture("PlusButton") or PSM.Skin.Texture("MinusButton")
    header.expandBtn:SetNormalTexture(tex)
    header.expandBtn:SetPushedTexture(tex)
    header.expandBtn:SetScript("OnClick", function()
        ToggleContinentCollapsed(continentName)
        PSM.ModelsFilters:PopulateUnifiedFilterCheckboxes(panel)
    end)

    header.label:SetText(continentName)

    -- Aggregate visual across this continent's currently-visible locations: all on, some
    -- on, or none.
    local allSel, anySel = true, false
    for _, loc in ipairs(locs) do
        if PSM.state.selectedLocations[loc] == true then anySel = true else allSel = false end
    end
    if allSel then
        header.label:SetTextColor(0, 1, 0)
    elseif anySel then
        header.label:SetTextColor(1, 1, 1)
    else
        header.label:SetTextColor(0.6, 0.6, 0.6)
    end

    header:SetScript("OnEnter", function() header.bg:SetColorTexture(0.2, 0.2, 0.2, 1) end)
    header:SetScript("OnLeave", function() header.bg:SetColorTexture(0.12, 0.12, 0.12, 1) end)

    header:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            -- Select-all / deselect-all for the continent: if anything under it is
            -- unselected, turn the whole group on; otherwise turn it all off.
            local hasUnselected = false
            for _, loc in ipairs(locs) do
                if PSM.state.selectedLocations[loc] ~= true then hasUnselected = true break end
            end
            local nextState = hasUnselected or nil
            -- One write per location, so this bumps `locations` up to fifteen times for one
            -- click. The store coalesces them into a single flush; that is why the watcher
            -- is scheduled rather than called from Bump.
            PSM.Selections:SetAll("locations", locs, nextState)
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
            if   exoticOnly    and selected > 0 then table.insert(filters, PSM.L("Families (Exotic only)"))
            elseif nonExoticOnly and selected > 0 then table.insert(filters, PSM.L("Families (not Exotic)"))
            else                                       table.insert(filters, PSM.L("Families")) end
        end
    end

    -- Expansions
    if panel.expansionList then
        local expCount = 0
        for _, on in pairs(PSM.state.selectedExpansions) do if on then expCount = expCount + 1 end end
        if expCount ~= #panel.expansionList then table.insert(filters, PSM.L("Expansions")) end
    end

    -- Locations (tristate: active whenever anything deviates from the default "all true")
    if panel.locationList then
        local allDefaultTrue = true
        for _, l in ipairs(panel.locationList) do
            if PSM.state.selectedLocations[l] ~= true then allDefaultTrue = false; break end
        end
        if not allDefaultTrue then table.insert(filters, PSM.L("Locations")) end
    end

        -- Tristate toggles
    if PSM.FilterState:Get("showRares") == true then table.insert(filters, PSM.L("Rares"))
    elseif PSM.FilterState:Get("showRares") == "inverted" then table.insert(filters, PSM.L("Not Rares")) end

    if PSM.FilterState:Get("showFavorites") == true then table.insert(filters, PSM.L("Favorites"))
    elseif PSM.FilterState:Get("showFavorites") == "inverted" then table.insert(filters, PSM.L("Not Favorites")) end

    if PSM.FilterState:Get("showNameKeepers") == true then table.insert(filters, PSM.L("Name Keepers"))
    elseif PSM.FilterState:Get("showNameKeepers") == "inverted" then table.insert(filters, PSM.L("Not Name Keepers")) end

    if PSM.FilterState:Get("showPetsInMyZone") and panel.currentPlayerZone then
        local zoneName = self:GetPlayerZoneName(panel.currentPlayerZone)
        table.insert(filters, PSM.FilterState:Get("showPetsInMyZone") == "inverted"
            and PSM.L("Not My Zone (%s)", zoneName) or PSM.L("My Zone (%s)", zoneName))
    end

    if PSM.FilterState:Get("showHideOwned") == "inverted" then table.insert(filters, PSM.L("Owned"))
    elseif PSM.FilterState:Get("showHideOwned") == true then table.insert(filters, PSM.L("Not Owned")) end

    -- Search
    if (panel.searchBox:GetSearchText() or "") ~= "" then table.insert(filters, PSM.L("Search")) end

    -- Abilities (from Ability Browser)
    if hasAbilities then
        local selectedCount = 0
        for _, on in pairs(PSM.state.selectedModelsFamilies) do
            if on then selectedCount = selectedCount + 1 end
        end
        if selectedCount > 0 then
            table.insert(filters, PSM.L("Abilities (%d families)", selectedCount))
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
                if lastRuleState == "inverted" then label = PSM.L("Not %s", label) end
                table.insert(stParts, label)
            else
                table.insert(stParts, PSM.L("Multiple Skills"))
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
                if lastCondState == "inverted" then label = PSM.L("Not %s", label) end
                table.insert(stParts, label)
            else
                table.insert(stParts, PSM.L("Multiple Conditions"))
            end
        end

        table.insert(filters, PSM.L("Special Tames - %s", table.concat(stParts, "; ")))
    end

    return #filters > 0 and PSM.L("Filters: %s", table.concat(filters, ", ")) or ""
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
