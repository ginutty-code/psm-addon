-- ModelsBrowser/ModelsDataLoader.lua
-- Data loading, caching, and processing for Pet Models Browser

local addonName = "PetStableManagement"

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
-- **`:Cancel()` is the point of this, not `= nil`.** A C_Timer handle is owned by the
-- timer system, not by the field holding it: clearing the field drops the reference and
-- the timer still fires. `LoadModelsForSelectedFamilies` below has always cancelled
-- before re-arming, but the four hand-written "clear the caches" blocks that used to
-- exist -- here, in NPCDataLoader, in PetRoulette, and in core's PanelManager -- all
-- nilled without cancelling. So closing the browser inside the debounce window left a
-- timer that fired into the panel just torn down, recomputing the whole model list and
-- **repopulating the cache the teardown had cleared**. `PSM.state.modelsPanel` is never
-- set to nil, so the guard at the top of `_LoadModelsImmediate` did not stop it.
function PSM.ModelsDataLoader:ReleaseCache()
    if PSM._modelsDebounceTimer then PSM._modelsDebounceTimer:Cancel() end
    PSM._modelsRenderCache   = nil
    PSM._modelsDebounceTimer = nil
end

-- Reset for a freshly built panel: the cache, plus the layout sizes that only mean
-- anything relative to the panel that has just been replaced.
function PSM.ModelsDataLoader:CreateRenderCache()
    self:ReleaseCache()
    PSM._lastModelsLayoutWidth  = nil
    PSM._lastModelsLayoutHeight = nil
end

--------------------------------------------------------------------------------
-- CACHE KEY HELPERS
--------------------------------------------------------------------------------

-- Build a canonical string from a selected-values table (key=name, value=bool).
local function SelectedMapKey(map)
    if not map or not next(map) then return "none," end
    local parts = {}
    for k, v in pairs(map) do if v then table.insert(parts, k) end end
    table.sort(parts)
    return table.concat(parts, ",") .. ","
end

-- Build the portion of any cache key that describes active panel filters.
local function PanelFilterFragment(panel)
    local zoneKey = ""
    if panel and PSM.FilterState:Get("showPetsInMyZone") and panel.currentPlayerZone then
        zoneKey = panel.currentPlayerZone .. (PSM.FilterState:Get("showPetsInMyZone") == "inverted" and "_inv," or ",")
    end

    local raresKey = ""
    if panel and PSM.FilterState:Get("showRares") then
        raresKey = (PSM.FilterState:Get("showRares") == "inverted" and "not_rares," or "rares,")
    end

    local nameKeepersKey = ""
    if panel and PSM.FilterState:Get("showNameKeepers") then
        nameKeepersKey = (PSM.FilterState:Get("showNameKeepers") == "inverted" and "not_namekeepers," or "namekeepers,")
    end

    return zoneKey, raresKey, nameKeepersKey
end

function PSM.ModelsDataLoader:GenerateCacheKey()
    local panel = PSM.state.modelsPanel
    if not panel then return "" end

    local searchText = panel.searchBox:GetSearchText() or ""
    local searchLower = searchText ~= "" and searchText:lower() or ""
    local zoneKey, raresKey, nameKeepersKey = PanelFilterFragment(panel)

    local favoritesKey = SelectedMapKey(PSM.state.favoriteModels)

    local modeKey = PSM.FilterState:Get("showFavorites") == true and "favorites"
               or (PSM.FilterState:Get("showFavorites") == "inverted" and "not_favorites" or "browse")

    local tamingKey = ""
    local selRules = PSM.state.selectedTamingRules
    if selRules and next(selRules) then
        local rParts = {}
        for k, v in pairs(selRules) do table.insert(rParts, k .. "=" .. tostring(v)) end
        table.sort(rParts)
        tamingKey = table.concat(rParts, ",") .. ","
    end

    local condKey = SelectedMapKey(PSM.state.selectedConditions)
    local ownedKey = tostring(PSM.FilterState:Get("showHideOwned") or "none")

    return string.format("%s_%s_%s_%s_%s_%s_%s_%s_%s_%s_%s_%s_%s",
        modeKey,
        searchLower,
        SelectedMapKey(PSM.state.selectedExpansions),
        SelectedMapKey(PSM.state.selectedLocations),
        zoneKey,
        SelectedMapKey(PSM.state.selectedModelsFamilies),
        favoritesKey,
        raresKey,
        nameKeepersKey,
        tamingKey,
        condKey,
        ownedKey,
        #PSM.state.stablePets
    )
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

    -- Taming rules filter (OR logic: show models requiring ANY of the selected rules)
    local selRules = PSM.state.selectedTamingRules
    if selRules and next(selRules) then
        local tamingSet = {}
        if displayData.taming then
            for _, rule in ipairs(displayData.taming) do tamingSet[rule] = true end
        end

        local hasActive, matchActive = false, false
        for rKey, state in pairs(selRules) do
            if state == true then
                hasActive = true
                
                -- Check model-level taming rules
                local isMatch = tamingSet[rKey]
                
                -- Special Case: Nlyeth (Look at NPC-level ConditionsData instead of model-level)
                if not isMatch and rKey == "Sliver of N'Zoth" and displayData.npcs then
                    for _, npc in ipairs(displayData.npcs) do
                        local condList = PSM.ConditionsData and PSM.ConditionsData.Get(_G.ModelsData.NpcId[npc])
                        if condList then
                            for _, cName in ipairs(condList) do
                                if cName == "Sliver of N'Zoth" then isMatch = true; break end
                            end
                        end
                        if isMatch then break end
                    end
                end

                if isMatch then
                    local fSel, dSel = selRules["Florafaun"] == true, selRules["Direhorn"] == true
                    if not (tamingSet["Florafaun"] and tamingSet["Direhorn"] and ((fSel and not dSel) or (dSel and not fSel))) then
                        matchActive = true
                    end
                end
            elseif state == "inverted" then
                if tamingSet[rKey] then return false end -- Disqualified
            end
        end
        if hasActive and not matchActive then return false end
    end

    -- Conditions filter (NPC level data from ConditionsData.lua)
    local selectedConds = PSM.state.selectedConditions
    if selectedConds and next(selectedConds) then
        local userHasActive = false
        for _, state in pairs(selectedConds) do
            if state == true then userHasActive = true; break end
        end

        local atLeastOneNpcPasses = false
        if displayData.npcs then
            for _, npc in ipairs(displayData.npcs) do
                local npcID = _G.ModelsData.NpcId[npc]
                if npcID then
                    local condList = PSM.ConditionsData and PSM.ConditionsData.Get(npcID)
                    local npcDisqualified = false
                    local npcMatchedActive = false

                    if condList then
                        for _, cName in ipairs(condList) do
                            local state = selectedConds[cName]
                            if state == "inverted" then npcDisqualified = true; break end
                            if state == true then npcMatchedActive = true end
                        end
                    end

                    if not npcDisqualified and (not userHasActive or npcMatchedActive) then
                        atLeastOneNpcPasses = true
                        break
                    end
                end
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
            for uiMapId, mapData in pairs(_G.CoordsData) do
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

    -- Fallback: legacy zone name match if playerMapId happens to be string
    if type(playerMapId) == "string" then
        -- NpcLocation() always returns a string ("Unknown" when absent), so
        -- this loop is safe unguarded.
        for loc in string.gmatch(PSM.PetModels.NpcLocation(npc), "[^|]+") do
            if strtrim(loc) == playerMapId then return true end
        end
        local uiMapName = uiMapId and _G.ModelsData.UiMapNames[uiMapId]
        if uiMapName and uiMapName == playerMapId then
            return true
        end
    end

    return false
end

-- Two-state: selectedLocations[name] is true (show) or absent (hide). The "inverted"
-- third state is gone -- with locations seeded all-true it always produced the same
-- outcome as absent, and ModelsFilters folds any saved value into nil on load, so nothing
-- can reach here with one.
--
-- Passes if there is no active selection at all, or if the location matches one.
function PSM.ModelsDataLoader:_IsLocationSelected(locationString, selectedLocations)
    if not locationString or not selectedLocations then return true end
    if type(selectedLocations) == "table" and not selectedLocations[1] then
        if not next(selectedLocations) then return true end

        local userHasActive = false
        for _, state in pairs(selectedLocations) do
            if state == true then userHasActive = true; break end
        end
        if not userHasActive then return true end

        for loc in string.gmatch(locationString, "[^|]+") do
            if selectedLocations[strtrim(loc)] == true then return true end
        end
        return false
    end
    if #selectedLocations == 0 then return true end
    for loc in string.gmatch(locationString, "[^|]+") do
        loc = strtrim(loc)
        for _, sel in ipairs(selectedLocations) do
            if sel == loc then return true end
        end
    end
    return false
end

function PSM.ModelsDataLoader:_IsExpansionSelected(expansion, selectedExpansions)
    if not expansion or not selectedExpansions then return true end
    if type(selectedExpansions) == "table" and not selectedExpansions[1] then
        if not next(selectedExpansions) then return true end
        return selectedExpansions[expansion] == true
    end
    if #selectedExpansions == 0 then return true end
    for _, sel in ipairs(selectedExpansions) do
        if sel == expansion then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- LOADING PIPELINE
--------------------------------------------------------------------------------

function PSM.ModelsDataLoader:LoadModelsForSelectedFamilies()
    if not PSM.state.modelsPanel or not PSM.PetModels then return end
    if PSM._modelsDebounceTimer then PSM._modelsDebounceTimer:Cancel() end
    PSM._modelsRenderCache = nil
    -- Shared with NPCDataLoader, which is the point -- see the comment there for how the
    -- two drifted apart while both were hardcoded.
    PSM._modelsDebounceTimer = C_Timer.NewTimer(PSM.Config.RENDER_DELAY, function()
        PSM.ModelsDataLoader:_LoadModelsImmediate()
    end)
end

function PSM.ModelsDataLoader:_LoadModelsImmediate()
    local panel = PSM.state.modelsPanel
    if not panel then return end

    local cacheKey = self:GenerateCacheKey()
    if PSM._modelsRenderCache and PSM._modelsRenderCache.key == cacheKey then
        if GetTime() - PSM._modelsRenderCache.timestamp < 0.2 then
            self:_ApplyCachedModelsData(PSM._modelsRenderCache.data)
            return
        end
    end

    local modelsData = self:_CalculateModelsData()

    -- Store in cache (was missing in original)
    PSM._modelsRenderCache = { key = cacheKey, timestamp = GetTime(), data = modelsData }

    self:_ApplyCachedModelsData(modelsData)

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

    -- Expansion filter
    if PSM.state.selectedExpansions then
        local hasSelection = next(PSM.state.selectedExpansions) ~= nil
        local filtered = {}
        for _, item in ipairs(allItems) do
            local match = false
            if item.npcs then
                for _, npc in ipairs(item.npcs) do
                    local expansion = PSM.PetModels.NpcExpansion(npc)
                    if hasSelection then
                        if expansion and PSM.state.selectedExpansions[expansion] then
                            match = true; break
                        end
                    else
                        -- "none selected" means exclude items that have expansion data
                        if not expansion then match = true; break end
                    end
                end
            end
            if match then table.insert(filtered, item) end
        end
        allItems = filtered
    end

    -- Location filter (two-state: true = show, absent = hide). Third copy of this rule --
    -- see also _IsLocationSelected above and NPCDataLoader's IsLocationSelected -- kept
    -- separate because this one walks an item's NPC list rather than a single string.
    if PSM.state.selectedLocations then
        local hasSelection = next(PSM.state.selectedLocations) ~= nil
        local userHasActive = false
        if hasSelection then
            for _, state in pairs(PSM.state.selectedLocations) do
                if state == true then userHasActive = true; break end
            end
        end

        local filtered = {}
        for _, item in ipairs(allItems) do
            local match = false
            if item.npcs then
                for _, npc in ipairs(item.npcs) do
                    if hasSelection then
                        local npcMatchedActive = false
                        -- NpcLocation() always returns a string ("Unknown" fallback),
                        -- so no nil guard needed.
                        for loc in string.gmatch(PSM.PetModels.NpcLocation(npc), "[^|]+") do
                            if PSM.state.selectedLocations[strtrim(loc)] == true then
                                npcMatchedActive = true; break
                            end
                        end
                        if not userHasActive or npcMatchedActive then
                            match = true; break
                        end
                    end
                    -- else: selectedLocations is present but empty ("Select None" was
                    -- clicked) -- every NPC always resolves to a location string (even
                    -- "Unknown" is a real, selectable filter value), so nothing should
                    -- match; match stays false.
                end
            end
            if match then table.insert(filtered, item) end
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
-- `selectedModelsFamilies`. That is why `families` is absent from the dependency list on the
-- selector below, and why the selector is worth having -- ticking a family box cannot change
-- this answer, but under one shared cache key it rescanned all 61 families anyway.
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
                                        for loc in string.gmatch(PSM.PetModels.NpcLocation(npc), "[^|]+") do
                                            loc = strtrim(loc)
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
        panel.infoText:SetText("No matching display IDs | 0 pages")
        panel.pageText:SetText("Page 0 of 0")
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

    panel.infoText:SetText(string.format("%d display IDs | %d owned",
        #panel.allModels, modelsData.ownedCount))

    -- Call UpdateModelsPanelLayout to refresh the view
    PSM.ModelsPanel:UpdateModelsPanelLayout()
end