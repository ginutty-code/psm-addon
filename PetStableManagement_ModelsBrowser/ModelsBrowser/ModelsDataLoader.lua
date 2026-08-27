-- ModelsBrowser/ModelsDataLoader.lua
-- Data loading, caching, and processing for Pet Models Browser


_G.PSM = _G.PSM or {}
local PSM = _G.PSM

PSM.ModelsDataLoader = PSM.ModelsDataLoader or {}

--------------------------------------------------------------------------------
-- STORE SLICES OWNED BY THIS ADDON
--------------------------------------------------------------------------------

-- Registered here rather than in core's Store.lua because both live on this addon's panel
-- frame, and core reaching across to read `ns.state.modelsPanel.currentPlayerZone` is the
-- cross-addon field access the boundary work has been removing everywhere else.
--
-- `zone` fingerprints rather than counts: `currentPlayerZone` is a plain frame field written
-- from three places, so there is no funnel to hook and no spec proving one. It is a single
-- string, so the fingerprint is free.
--
-- `panel` is counted, and covers `panel.familiesList` -- the universe of families the
-- dynamic-filter selectors iterate. It moves only when the filter system is rebuilt.
PSM.Store:Declare("zone", function()
    local panel = PSM.state.modelsPanel
    return tostring(panel and panel.currentPlayerZone or "")
end)

PSM.Store:Declare("panel")

-- Fingerprinted rather than counted because the home is a widget: a search box's writes
-- come from Blizzard's OnTextChanged, so they cannot be funnelled or spec-enforced.
-- Reading the box at flush time cannot go stale. The cost is that it cannot announce
-- itself, which is what `Store:Touch()` is for; a missed Touch is a late refresh, never a
-- wrong one.
PSM.Store:Declare("search", function()
    local panel = PSM.state.modelsPanel
    local box   = panel and panel.searchBox
    return box and box:GetSearchText() or ""
end)

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------

local EXPANSION_ORDER = {
    ["Vanilla"] = 1, ["The Burning Crusade"] = 2, ["Wrath of the Lich King"] = 3,
    ["Cataclysm"] = 4, ["Mists of Pandaria"] = 5, ["Warlords of Draenor"] = 6,
    ["Legion"] = 7, ["Battle for Azeroth"] = 8, ["Shadowlands"] = 9,
    ["Dragonflight"] = 10, ["The War Within"] = 11, ["Midnight"] = 12, ["The Last Titan"] = 13,
}
PSM.ModelsDataLoader._EXPANSION_ORDER = EXPANSION_ORDER

local function SortExpansions(list)
    table.sort(list, function(a, b)
        return (EXPANSION_ORDER[a] or 999) < (EXPANSION_ORDER[b] or 999)
    end)
end

--------------------------------------------------------------------------------
-- CACHE
--------------------------------------------------------------------------------

-- Drop the models render cache and stop any pending render.
--
-- `:Cancel()` is the point of this, not `= nil`: a C_Timer handle is owned by the timer
-- system, so clearing the field drops the reference and the timer still fires -- into the
-- panel just torn down, refilling the cache the teardown cleared. `PSM.state.modelsPanel`
-- is never set to nil, so `_LoadModelsImmediate`'s own guard does not stop it.
-- Every input to `_CalculateModelsData`, which is why there is no expiry. `panel` is in
-- the list because a rebuilt filter system is a different panel with a different search
-- box, so a result computed against the old one must not survive.
local MODELS_RESULT_SLICES = {
    "families", "expansions", "locations", "tamingRules", "conditions",
    "toggles", "favorites", "pets", "zone", "search", "panel",
}

local modelsResults   -- the selector; built on first use, dropped by ReleaseCache

function PSM.ModelsDataLoader:ReleaseCache()
    if PSM._modelsDebounceTimer then PSM._modelsDebounceTimer:Cancel() end
    PSM._modelsDebounceTimer = nil
    -- Dropping the selector, not just a table: it holds the computed item list, which is
    -- the ~7000-entry allocation this function exists to release. Rebuilt on next use.
    modelsResults = nil
end

--------------------------------------------------------------------------------
-- FILTER HELPERS
--------------------------------------------------------------------------------

-- Evaluate a tristate filter value (true / "inverted" / falsy) against a bool.
local function TristateMatch(filterValue, matches)
    if not filterValue then return true end
    if filterValue == true then return matches end
    return not matches  -- "inverted"
end

-- Builds a displayId -> true set once per caller pass, only when Hide Owned
-- is active -- avoids the same O(displayIds x stablePets) trap NPCDataLoader had.
local function BuildOwnedDisplaySet()
    if not PSM.FilterState:Get("showHideOwned") then return nil end
    local set = {}
    for _, pet in ipairs(PSM.state.stablePets) do
        if pet.displayID then set[tonumber(pet.displayID)] = true end
    end
    return set
end

-- Check whether a display entry passes the current favorites + rares + ownership filters.
local function DisplayPassesFilters(displayData, ownedSet)
    local favOk = TristateMatch(PSM.FilterState:Get("showFavorites"),
        PSM.state.favoriteModels and PSM.state.favoriteModels[displayData.displayId] or false)
    if not favOk then return false end

    local isRare = false
    if displayData.npcs then
        for _, npc in ipairs(displayData.npcs) do
            local classification = PSM.PetModels.NpcClassification(npc)
            if classification == "Rare" or classification == "Rare Elite" then
                isRare = true; break
            end
        end
    end
    if not TristateMatch(PSM.FilterState:Get("showRares"), isRare) then return false end

    -- Name Keepers filter
    local isNameKeeper = false
    if displayData.npcs then
        for _, npc in ipairs(displayData.npcs) do
            if _G.ModelsData.NameKeeper[npc] then
                isNameKeeper = true; break
            end
        end
    end
    if not TristateMatch(PSM.FilterState:Get("showNameKeepers"), isNameKeeper) then return false end

    -- Ownership filter: check if display is owned
    local isOwned = ownedSet and ownedSet[displayData.displayId] or false
    -- For "Hide Owned": true means hide owned (show not owned), inverted means show only owned
    local ownedMatch = not isOwned
    if not TristateMatch(PSM.FilterState:Get("showHideOwned"), ownedMatch) then return false end

    -- Taming rules: a display-level fact, so the aggregated set GetFamilyModels built.
    --
    local tamingSet = PSM.PetModels.TamingSet(displayData.taming)
    if not PSM.PetModels.TamingSetPasses(tamingSet, PSM.state.selectedTamingRules) then
        return false
    end

    -- Conditions are an NPC-level fact, so a display qualifies when **any** of its NPCs
    -- does -- the display is what is on screen, and one taming target is enough to want it.
    -- The NPC view asks the same question of a single NPC, which is why the per-NPC half
    -- is shared and this loop is not.
    local selectedConds = PSM.state.selectedConditions
    if selectedConds and next(selectedConds) then
        local userHasActive = PSM.PetModels.ConditionsHaveActive(selectedConds)
        local atLeastOneNpcPasses = false
        for _, npc in ipairs(displayData.npcs or {}) do
            if PSM.PetModels.NpcPassesConditions(_G.ModelsData.NpcId[npc], selectedConds, userHasActive) then
                atLeastOneNpcPasses = true
                break
            end
        end
        if not atLeastOneNpcPasses then return false end
    end

    return true
end

function PSM.ModelsDataLoader:GetNpcZoneNames(npcId)
    local id = tonumber(npcId)
    if not id then return nil end

    if not PSM._npcZoneIndex then
        local index = {}
        if _G.CoordsData then
            for _, mapData in pairs(_G.CoordsData) do
                if type(mapData) == "table" and mapData.name and mapData.npcs then
                    local zoneName = mapData.name
                    for nId in pairs(mapData.npcs) do
                        local numId = tonumber(nId) or nId
                        index[numId] = index[numId] or {}
                        index[numId][zoneName] = true
                    end
                end
            end
        end
        PSM._npcZoneIndex = index
    end

    return PSM._npcZoneIndex[id]
end

function PSM.ModelsDataLoader:_IsZoneMatch(npc, playerMapId)
    if not npc or not playerMapId then return false end

    local uiMapId = _G.ModelsData.UiMapId[npc]

    -- 1. Direct uiMapId match from metadata
    if uiMapId and tonumber(uiMapId) == tonumber(playerMapId) then
        return true
    end

    -- 2. Lookup in CoordsData by map ID
    local numMapId = tonumber(playerMapId)
    local numNpcId = _G.ModelsData.NpcId[npc]
    if numMapId and numNpcId and _G.CoordsData and _G.CoordsData[numMapId] then
        local mapData = _G.CoordsData[numMapId]
        if type(mapData) == "table" and mapData.npcs then
            if mapData.npcs[numNpcId] or mapData.npcs[tostring(numNpcId)] then
                return true
            end
        end
    end

    -- Fallback: legacy zone name match if playerMapId happens to be a string.
    --
    -- An NPC carries a single `UiMapId`, so its location is one name -- no splitting, and
    -- no separate `UiMapNames[uiMapId]` comparison, which resolves to the same value.
    if type(playerMapId) == "string" then
        if PSM.PetModels.NpcLocation(npc) == playerMapId then return true end
    end

    return false
end

-- Two-state: selectedLocations[name] is true (show) or absent (hide). The "inverted"
-- third state is gone -- with locations seeded all-true it always produced the same
-- outcome as absent, and ModelsFilters folds any saved value into nil on load, so nothing
-- can reach here with one.
--
-- Thin wrappers over the shared rule in PetModels, kept as methods because the dynamic
-- filter selectors call them as `ML:_IsLocationSelected(...)`.
function PSM.ModelsDataLoader:_IsLocationSelected(locationString, selectedLocations)
    return PSM.PetModels.SelectionAllows(selectedLocations, locationString)
end

function PSM.ModelsDataLoader:_IsExpansionSelected(expansion, selectedExpansions)
    return PSM.PetModels.SelectionAllows(selectedExpansions, expansion)
end

--------------------------------------------------------------------------------
-- LOADING PIPELINE
--------------------------------------------------------------------------------

function PSM.ModelsDataLoader:LoadModelsForSelectedFamilies()
    if not PSM.state.modelsPanel or not PSM.PetModels then return end
    if PSM._modelsDebounceTimer then PSM._modelsDebounceTimer:Cancel() end
    -- Deliberately no `modelsResults = nil` here: deciding what is stale is the selector's
    -- job, and discarding on the way in would switch the cache off for the main reload path.
    -- The delay is shared with NPCDataLoader, which is the point.
    PSM._modelsDebounceTimer = C_Timer.NewTimer(PSM.Config.RENDER_DELAY, function()
        PSM.ModelsDataLoader:_LoadModelsImmediate()
    end)
end

function PSM.ModelsDataLoader:_LoadModelsImmediate()
    local panel = PSM.state.modelsPanel
    if not panel then return end

    -- **The 0.2s expiry is gone with the cache key, and that is one change, not two.**
    -- Built on first use rather than at file scope: `PSM.Store` belongs to core, and this
    -- is a LoadOnDemand file that must not capture another module's table at parse time.
    modelsResults = modelsResults or PSM.Store:Selector(MODELS_RESULT_SLICES, function()
        return PSM.ModelsDataLoader:_CalculateModelsData()
    end)

    self:_ApplyCachedModelsData(modelsResults())

    -- Now runs on a reuse too. The early return this replaces skipped both updates when
    -- the cache hit, which is precisely why nine call sites had to re-issue them by hand.
    if PSM.ModelsFilters then
        if PSM.ModelsFilters.UpdateFilterSummary  then PSM.ModelsFilters:UpdateFilterSummary()  end
        if PSM.ModelsFilters.UpdateDynamicFilters then PSM.ModelsFilters:UpdateDynamicFilters() end
    end
end

--------------------------------------------------------------------------------
-- DATA CALCULATION
--------------------------------------------------------------------------------

-- Returns colored faction indicators from ReactA/ReactH -- ModelsData ships
-- these pre-parsed as numbers, no string.match needed.
local function formatFactionIndicator(allianceReact, hordeReact)
    local result = ""
    if allianceReact then
        local color = allianceReact == -1 and {1,0,0} or allianceReact == 0 and {1,1,0} or {0,1,0}
        result = result .. "|cff" .. string.format("%02x%02x%02x", color[1]*255, color[2]*255, color[3]*255) .. "A|r"
    end
    if hordeReact then
        local color = hordeReact == -1 and {1,0,0} or hordeReact == 0 and {1,1,0} or {0,1,0}
        result = result .. "|cff" .. string.format("%02x%02x%02x", color[1]*255, color[2]*255, color[3]*255) .. "H|r"
    end
    return result ~= "" and " " .. result or ""
end

-- Formats an NPC descriptor string for tooltip / row display. npc is a
-- denseIndex into ModelsData (see PetModels.lua's GetFamilyModels).
local function npcDescription(npc)
    local modelsData = _G.ModelsData
    local classificationName = PSM.PetModels.NpcClassification(npc)
    local classification = (classificationName and classificationName ~= "Normal")
        and string.format("%s, ", classificationName)
        or  ""
    local factionStr = formatFactionIndicator(modelsData.ReactA[npc], modelsData.ReactH[npc])
    local factionPart = factionStr ~= "" and ", " .. factionStr or ""
    return string.format("%s: %s%s, %s, %s%s",
        modelsData.Name[npc],
        classification,
        modelsData.NpcId[npc] or "?",
        PSM.PetModels.NpcLocation(npc),
        PSM.PetModels.NpcExpansion(npc) or "Unknown",
        factionPart)
end

function PSM.ModelsDataLoader:_CalculateModelsData()
    local panel = PSM.state.modelsPanel

    -- Ensure pet data is loaded
    if PSM.state.isStableOpen then
        if #PSM.state.stablePets == 0 then PSM.Data:CollectStablePets() end
    else
        if #PSM.state.stablePets == 0 then PSM.Data:LoadPersistentDataForDisplay() end
    end

    -- Collect selected families
    local selectedFamilies = {}
    for familyName, selected in pairs(PSM.state.selectedModelsFamilies) do
        if selected then table.insert(selectedFamilies, familyName) end
    end

    if #selectedFamilies == 0 then
        return { allItems = {}, ownedCount = 0, totalCount = 0 }
    end

    local searchText  = panel.searchBox:GetSearchText() or ""
    local searchLower = searchText ~= "" and searchText:lower() or ""

    -- Build flat item list, applying favorites + rares filters early
    local ownedSet = BuildOwnedDisplaySet()
    local allItems = {}
    for _, familyName in ipairs(selectedFamilies) do
        local familyData = PSM.PetModels:GetFamilyModels(familyName)
        if familyData and familyData.displayIds then
            for _, displayData in ipairs(familyData.displayIds) do
                if not PSM.Config.EXCLUDED_DISPLAY_IDS[displayData.displayId]
                   and DisplayPassesFilters(displayData, ownedSet) then
                     
                     -- Cache NPC descriptions in a side-table keyed by denseIndex (npc is
                     -- a bare index, not an object, so it can't hold its own field) so
                     -- this string is only built once per NPC ever, not once per render/
                     -- filter pass.
                     local nameSeen, nameList = {}, {}
                     if displayData.npcs then
                         _G.PSM._modelsDescriptionCache = _G.PSM._modelsDescriptionCache or {}
                         local descCache = _G.PSM._modelsDescriptionCache
                         for _, npc in ipairs(displayData.npcs) do
                             descCache[npc] = descCache[npc] or npcDescription(npc)
                             local npcName = _G.ModelsData.Name[npc]
                             if npcName and not nameSeen[npcName] then
                                 nameSeen[npcName] = true
                                 table.insert(nameList, npcName)
                             end
                         end
                     end

                     table.insert(allItems, {
                         displayId         = displayData.displayId,
                         npcs              = displayData.npcs,
                         taming            = displayData.taming,
                         familyName        = familyName,
                         allNpcNamesString = table.concat(nameList, ", "),
                         itemType          = "display_with_npcs",
                     })
                end
            end
        end
    end

    if #allItems == 0 then
        return { allItems = {}, ownedCount = 0, totalCount = 0 }
    end

    -- Search filter
    if searchLower ~= "" then
        local filtered = {}
        for _, item in ipairs(allItems) do
            local found = tostring(item.displayId):lower():find(searchLower, 1, true)
                       or (item.familyName and item.familyName:lower():find(searchLower, 1, true))
                       or (item.allNpcNamesString and item.allNpcNamesString:lower():find(searchLower, 1, true))
            if not found and item.npcs then
                local modelsData = _G.ModelsData
                for _, npc in ipairs(item.npcs) do
                    local npcName = modelsData.Name[npc]
                    local npcId = modelsData.NpcId[npc]
                    local classification = PSM.PetModels.NpcClassification(npc)
                    if (npcName and npcName:lower():find(searchLower, 1, true))
                    or tostring(npcId):lower():find(searchLower, 1, true)
                    or PSM.PetModels.NpcLocation(npc):lower():find(searchLower, 1, true)
                    or (PSM.PetModels.NpcExpansion(npc) or ""):lower():find(searchLower, 1, true)
                    or (classification and classification:lower():find(searchLower, 1, true)) then
                        found = true; break
                    end
                    if not found and npcId then
                        local zoneSet = self:GetNpcZoneNames(npcId)
                        if zoneSet then
                            for zoneName in pairs(zoneSet) do
                                if zoneName:lower():find(searchLower, 1, true) then
                                    found = true; break
                                end
                            end
                        end
                    end
                    if found then break end
                end
            end
            if found then table.insert(filtered, item) end
        end
        allItems = filtered
    end

    -- Expansion and location filters. Both ask the same question of every NPC behind a
    -- display -- "does any one of them qualify?" -- so they are one loop over one shared
    -- rule rather than two near-copies that drifted. `SelectionMode` is resolved once per
    -- filter rather than per NPC: this runs over every display of every selected family.
    local PetModels     = PSM.PetModels
    local selExpansions = PSM.state.selectedExpansions
    local selLocations  = PSM.state.selectedLocations
    local expansionMode = PetModels.SelectionMode(selExpansions)
    local locationMode  = PetModels.SelectionMode(selLocations)

    if selExpansions or selLocations then
        local filtered = {}
        for _, item in ipairs(allItems) do
            local expansionOk = selExpansions == nil
            local locationOk  = selLocations  == nil

            for _, npc in ipairs(item.npcs or {}) do
                if not expansionOk then
                    local expansion = PetModels.NpcExpansion(npc)
                    expansionOk = PetModels.SelectionAllows(selExpansions, expansion, expansionMode)
                end
                -- NpcLocation() always returns a string ("Unknown" fallback), so an empty
                -- location selection excludes every NPC -- there is no nil to survive it.
                if not locationOk then
                    local location = PetModels.NpcLocation(npc)
                    locationOk = PetModels.SelectionAllows(selLocations, location, locationMode)
                end
                if expansionOk and locationOk then break end
            end

            if expansionOk and locationOk then table.insert(filtered, item) end
        end
        allItems = filtered
    end

    -- Zone filter
    if PSM.FilterState:Get("showPetsInMyZone") and panel.currentPlayerZone then
        local filtered = {}
        for _, item in ipairs(allItems) do
            local zoneMatch = false
            if item.npcs then
                for _, npc in ipairs(item.npcs) do
                    if self:_IsZoneMatch(npc, panel.currentPlayerZone) then
                        zoneMatch = true; break
                    end
                end
            end
            if TristateMatch(PSM.FilterState:Get("showPetsInMyZone"), zoneMatch) then
                table.insert(filtered, item)
            end
        end
        allItems = filtered
    end

    -- Ownership count
    local ownedIds = {}
    for _, pet in ipairs(PSM.state.stablePets) do
        if pet.displayID then ownedIds[tonumber(pet.displayID)] = true end
    end
    local ownedCount = 0
    for _, item in ipairs(allItems) do
        if ownedIds[item.displayId] then ownedCount = ownedCount + 1 end
    end

    return { allItems = allItems, ownedCount = ownedCount, totalCount = #allItems }
end

--------------------------------------------------------------------------------
-- DYNAMIC FILTER QUERIES
--------------------------------------------------------------------------------

-- Iterate NPCs of a display entry, calling fn(npc) until it returns true.



-- The families still reachable given every filter **except** the family selection.
--
-- Deliberately leave-one-out: it loops `panel.familiesList`, the full list, and never reads
-- `selectedModelsFamilies`, which is why `families` is absent from the selector's
-- dependency list below.
local function ComputeAvailableFamilies()
    local panel = PSM.state.modelsPanel
    if not panel then return {} end

    local selectedExpansions = PSM.state.selectedExpansions or {}
    local selectedLocations  = PSM.state.selectedLocations or {}

    local hasExpFilter = false
    for _, s in pairs(selectedExpansions) do if s then hasExpFilter = true; break end end

    local hasLocFilter = false
    for _, s in pairs(selectedLocations) do if s then hasLocFilter = true; break end end

    local hasOtherFilters = hasExpFilter or hasLocFilter
                         or PSM.FilterState:Get("showRares") ~= nil or PSM.FilterState:Get("showFavorites") ~= nil
                         or PSM.FilterState:Get("showNameKeepers") ~= nil or PSM.FilterState:Get("showHideOwned") ~= nil
                         or (PSM.FilterState:Get("showPetsInMyZone") and panel.currentPlayerZone)
                         or (PSM.state.selectedTamingRules and next(PSM.state.selectedTamingRules))
                         or (PSM.state.selectedConditions and next(PSM.state.selectedConditions))

    if not hasOtherFilters then return panel.familiesList or {} end

    local ownedSet = BuildOwnedDisplaySet()
    local result, seen = {}, {}
    for _, familyName in ipairs(panel.familiesList or {}) do
        local fd = PSM.PetModels:GetFamilyModels(familyName)
        if fd and fd.displayIds then
            local matched = false
            for _, displayData in ipairs(fd.displayIds) do
                if not PSM.Config.EXCLUDED_DISPLAY_IDS[displayData.displayId]
                   and DisplayPassesFilters(displayData, ownedSet) then
                    if displayData.npcs then
                        for _, npc in ipairs(displayData.npcs) do
                            local ML = PSM.ModelsDataLoader
                            local expOk = not hasExpFilter or ML:_IsExpansionSelected(PSM.PetModels.NpcExpansion(npc), selectedExpansions)
                            local locOk = not hasLocFilter or ML:_IsLocationSelected(PSM.PetModels.NpcLocation(npc), selectedLocations)
                            local zoneOk = not (PSM.FilterState:Get("showPetsInMyZone") and panel.currentPlayerZone)
                                        or TristateMatch(PSM.FilterState:Get("showPetsInMyZone"), ML:_IsZoneMatch(npc, panel.currentPlayerZone))
                            if expOk and locOk and zoneOk then matched = true; break end
                        end
                    end
                end
                if matched then break end
            end
            if matched and not seen[familyName] then
                seen[familyName] = true
                table.insert(result, familyName)
            end
        end
    end
    table.sort(result)
    return result
end

-- Built on first use, not at file scope: `PSM.Store` belongs to core, which is loaded by
-- then, but this file is parsed as part of a LoadOnDemand addon and must not capture
-- another module's table at parse time. That is the cross-addon snapshot trap ModelRow.lua
-- was fixed for.
--
-- `families` is absent from the dependency list, and that absence is the entire feature.
-- `panel` covers `panel.familiesList`, the universe this iterates, which only changes when
-- the filter system is rebuilt.
local availableFamilies

function PSM.ModelsDataLoader:GetAvailableFamiliesForFilters()
    availableFamilies = availableFamilies or PSM.Store:Selector({
        "expansions", "locations", "toggles", "tamingRules", "conditions",
        "favorites", "pets", "zone", "panel",
    }, ComputeAvailableFamilies)
    return availableFamilies()
end

-- The expansions still reachable given every filter **except** the expansion selection.
-- Same leave-one-out shape as ComputeAvailableFamilies: it walks `panel.expansionList` and
-- never reads `selectedExpansions`, so `expansions` is absent from the dependency list below.
local function ComputeAvailableExpansions()
    local ML = PSM.ModelsDataLoader
    local panel = PSM.state.modelsPanel
    if not panel then return {} end

    local selectedFamilies  = PSM.state.selectedModelsFamilies or {}
    local selectedLocations = PSM.state.selectedLocations or {}

    local hasFamFilter = false
    for _, s in pairs(selectedFamilies) do if s then hasFamFilter = true; break end end

    local hasLocFilter = false
    for _, s in pairs(selectedLocations) do if s then hasLocFilter = true; break end end

    local hasOtherFilters = hasFamFilter or hasLocFilter
                         or PSM.FilterState:Get("showRares") ~= nil or PSM.FilterState:Get("showFavorites") ~= nil
                         or PSM.FilterState:Get("showNameKeepers") ~= nil or PSM.FilterState:Get("showHideOwned") ~= nil
                         or (PSM.FilterState:Get("showPetsInMyZone") and panel.currentPlayerZone)
                         or (PSM.state.selectedTamingRules and next(PSM.state.selectedTamingRules))
                         or (PSM.state.selectedConditions and next(PSM.state.selectedConditions))

    if not hasOtherFilters then
        local result = {}
        for _, e in ipairs(panel.expansionList or {}) do table.insert(result, e) end
        SortExpansions(result)
        return result
    end

    local ownedSet = BuildOwnedDisplaySet()
    local result, seen = {}, {}
    for _, familyName in ipairs(panel.familiesList or {}) do
        if not hasFamFilter or PSM.state.selectedModelsFamilies[familyName] then
            local fd = PSM.PetModels:GetFamilyModels(familyName)
            if fd and fd.displayIds then
                for _, displayData in ipairs(fd.displayIds) do
                    if not PSM.Config.EXCLUDED_DISPLAY_IDS[displayData.displayId]
                       and DisplayPassesFilters(displayData, ownedSet) then
                        if displayData.npcs then
                            for _, npc in ipairs(displayData.npcs) do
                                local locOk = not hasLocFilter or ML:_IsLocationSelected(PSM.PetModels.NpcLocation(npc), selectedLocations)
                                local zoneOk = not (PSM.FilterState:Get("showPetsInMyZone") and panel.currentPlayerZone)
                                            or TristateMatch(PSM.FilterState:Get("showPetsInMyZone"), ML:_IsZoneMatch(npc, panel.currentPlayerZone))
                                local expansion = PSM.PetModels.NpcExpansion(npc)
                                if locOk and zoneOk and expansion and not seen[expansion] then
                                    seen[expansion] = true
                                    table.insert(result, expansion)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    SortExpansions(result)
    return result
end

local availableExpansions

function PSM.ModelsDataLoader:GetAvailableExpansionsForFilters()
    availableExpansions = availableExpansions or PSM.Store:Selector({
        "families", "locations", "toggles", "tamingRules", "conditions",
        "favorites", "pets", "zone", "panel",
    }, ComputeAvailableExpansions)
    return availableExpansions()
end

-- The locations still reachable given every filter **except** the location selection.
local function ComputeAvailableLocations()
    local ML = PSM.ModelsDataLoader
    local panel = PSM.state.modelsPanel
    if not panel then return {} end

    local selectedFamilies   = PSM.state.selectedModelsFamilies or {}
    local selectedExpansions = PSM.state.selectedExpansions or {}

    local hasFamFilter = false
    for _, s in pairs(selectedFamilies) do if s then hasFamFilter = true; break end end

    local hasExpFilter = false
    for _, s in pairs(selectedExpansions) do if s then hasExpFilter = true; break end end

    local hasOtherFilters = hasFamFilter or hasExpFilter
                         or PSM.FilterState:Get("showRares") ~= nil or PSM.FilterState:Get("showFavorites") ~= nil
                         or PSM.FilterState:Get("showNameKeepers") ~= nil or PSM.FilterState:Get("showHideOwned") ~= nil
                         or (PSM.FilterState:Get("showPetsInMyZone") and panel.currentPlayerZone)
                         or (PSM.state.selectedTamingRules and next(PSM.state.selectedTamingRules))
                         or (PSM.state.selectedConditions and next(PSM.state.selectedConditions))

    if not hasOtherFilters then
        local result = {}
        for _, l in ipairs(panel.locationList or {}) do table.insert(result, l) end
        table.sort(result)
        return result
    end

    local ownedSet = BuildOwnedDisplaySet()
    local result, seen = {}, {}
    for _, familyName in ipairs(panel.familiesList or {}) do
        if not hasFamFilter or PSM.state.selectedModelsFamilies[familyName] then
            local fd = PSM.PetModels:GetFamilyModels(familyName)
            if fd and fd.displayIds then
                for _, displayData in ipairs(fd.displayIds) do
                    if not PSM.Config.EXCLUDED_DISPLAY_IDS[displayData.displayId]
                       and DisplayPassesFilters(displayData, ownedSet) then
                        if displayData.npcs then
                            for _, npc in ipairs(displayData.npcs) do
                                local expOk = not hasExpFilter or ML:_IsExpansionSelected(PSM.PetModels.NpcExpansion(npc), selectedExpansions)
                                local inMyZone = PSM.FilterState:Get("showPetsInMyZone") and panel.currentPlayerZone
                                              and ML:_IsZoneMatch(npc, panel.currentPlayerZone)
                                local zoneOk = not (PSM.FilterState:Get("showPetsInMyZone") and panel.currentPlayerZone)
                                            or TristateMatch(PSM.FilterState:Get("showPetsInMyZone"), inMyZone)
                                if expOk and zoneOk then
                                    if PSM.FilterState:Get("showPetsInMyZone") == true and inMyZone then
                                        -- _IsZoneMatch also matches via CoordsData (an NPC can
                                        -- spawn in more zones than the single one ModelsData
                                        -- recorded for it) â€” attribute the player's own zone
                                        -- here rather than npc.location, or NPCs that also
                                        -- spawn elsewhere leak their other zone into the list.
                                        local zone = _G.CoordsData and _G.CoordsData[tonumber(panel.currentPlayerZone)]
                                        local zoneName = zone and zone.name
                                        if zoneName and not seen[zoneName] then
                                            seen[zoneName] = true
                                            table.insert(result, zoneName)
                                        end
                                    else
                                        local loc = PSM.PetModels.NpcLocation(npc)
                                        if not seen[loc] then
                                            seen[loc] = true
                                            table.insert(result, loc)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(result)
    return result
end

local availableLocations

function PSM.ModelsDataLoader:GetAvailableLocationsForFilters()
    availableLocations = availableLocations or PSM.Store:Selector({
        "families", "expansions", "toggles", "tamingRules", "conditions",
        "favorites", "pets", "zone", "panel",
    }, ComputeAvailableLocations)
    return availableLocations()
end

----------------------------------------------------------------------------------------------------------------
-- APPLY TO UI
--------------------------------------------------------------------------------

function PSM.ModelsDataLoader:_ApplyCachedModelsData(modelsData)
    local panel = PSM.state.modelsPanel
    if not panel then return end

    if modelsData.totalCount == 0 then
        panel.allModels = {}
        panel.infoText:SetText(PSM.L("No matching display IDs | 0 pages"))
        panel.pageText:SetText(PSM.L("Page %d of %d", 0, 0))
        -- Still need to hide rows cleanly:
        PSM.ModelsPanel:UpdateVisibleRows()
        return
    end

    panel.allModels = {}
    for _, item in ipairs(modelsData.allItems) do
        if item.itemType == "display_with_npcs" then
            table.insert(panel.allModels, item)
        end
    end

    local totalPages = math.ceil(#panel.allModels /
        PSM.ModelsPanel.MODELS_CONFIG.PETS_PER_PAGE)
    local savedPage = PSM.state.modelsPanelCurrentPage or 1
    panel.currentPage = (savedPage >= 1 and savedPage <= totalPages)
        and savedPage or 1

    panel.infoText:SetText(PSM.L("%d display IDs | %d owned",
        #panel.allModels, modelsData.ownedCount))

    -- Call UpdateModelsPanelLayout to refresh the view
    PSM.ModelsPanel:UpdateModelsPanelLayout()
end