-- ModelsBrowser/NPCDataLoader.lua
-- Data loading and filtering for the NPC view of the Pet Models Browser.
-- Reads the flat ModelsData[npcId] table directly, so this is a plain text
-- pipeline (no model/display data joins) -- deliberately lighter than
-- ModelsDataLoader's display-ID pipeline.

local addonName = "PetStableManagement"

_G.PSM = _G.PSM or {}
local PSM = _G.PSM

PSM.NPCDataLoader = PSM.NPCDataLoader or {}

--------------------------------------------------------------------------------
-- FILTER HELPERS
--------------------------------------------------------------------------------

-- Evaluate a tristate filter value (true / "inverted" / falsy) against a bool.
local function TristateMatch(filterValue, matches)
    if not filterValue then return true end
    if filterValue == true then return matches end
    return not matches  -- "inverted"
end

local function IsAnyDisplayIdFavorite(displayIds)
    if not displayIds or not PSM.state.favoriteModels then return false end
    for _, id in ipairs(displayIds) do
        if PSM.state.favoriteModels[id] then return true end
    end
    return false
end

-- ownedSet is built once per pass (below), not once per NPC -- 
local function IsAnyDisplayIdOwned(displayIds, ownedSet)
    if not displayIds or not ownedSet then return false end
    for _, id in ipairs(displayIds) do
        if ownedSet[id] then return true end
    end
    return false
end

-- Tristate-aware single-zone match, mirroring ModelsDataLoader:_IsLocationSelected
local function IsLocationSelected(uiMapName, selectedLocations)
    if not selectedLocations or not next(selectedLocations) then return true end

    local userHasActive = false
    for _, state in pairs(selectedLocations) do
        if state == true then userHasActive = true; break end
    end

    if not uiMapName then return not userHasActive end

    local state = selectedLocations[uiMapName]
    if state == "inverted" then return false end
    if userHasActive then return state == true end
    return true
end

--------------------------------------------------------------------------------
-- LOADING PIPELINE
--------------------------------------------------------------------------------

function PSM.NPCDataLoader:LoadNPCsForSelectedFamilies()
    if not PSM.state.modelsPanel then return end
    if PSM._npcDebounceTimer then PSM._npcDebounceTimer:Cancel() end
    PSM._npcDebounceTimer = PSM.C_Timer.NewTimer(0.01, function()
        PSM.NPCDataLoader:_LoadNPCsImmediate()
    end)
end

function PSM.NPCDataLoader:_LoadNPCsImmediate()
    local panel = PSM.state.modelsPanel
    if not panel then return end

    self:_ApplyNPCData(self:_CalculateNPCData())

    if PSM.ModelsFilters then
        if PSM.ModelsFilters.UpdateFilterSummary  then PSM.ModelsFilters:UpdateFilterSummary()  end
        if PSM.ModelsFilters.UpdateDynamicFilters then PSM.ModelsFilters:UpdateDynamicFilters() end
    end
end

function PSM.NPCDataLoader:_CalculateNPCData()
    local panel = PSM.state.modelsPanel
    if not _G.ModelsData or type(_G.ModelsData) ~= "table" then return {} end

    if PSM.state.isStableOpen then
        if #PSM.state.stablePets == 0 then PSM.Data:CollectStablePets() end
    else
        if #PSM.state.stablePets == 0 then PSM.Data:LoadPersistentDataForDisplay() end
    end

    -- Same "nothing selected = nothing shown" convention as the display-ID view.
    local selectedFamilies = PSM.state.selectedModelsFamilies
    if not selectedFamilies or not next(selectedFamilies) then return {} end

    local searchText  = panel.searchBox and panel.searchBox:GetText() or ""
    local searchLower = searchText ~= "" and searchText:lower() or ""

    -- Built once per reload, only when the Hide Owned filter is active.
    local ownedSet = nil
    if panel.showHideOwned then
        ownedSet = {}
        for _, pet in ipairs(PSM.state.stablePets) do
            if pet.displayID then ownedSet[tonumber(pet.displayID)] = true end
        end
    end

    -- Iterate only selected families via the shared family index instead of
    -- scanning all ~7700 ModelsData entries and rejecting non-matches.
    local byFamily = PSM.PetModels:GetModelsDataByFamilyIndex()

    local items = {}
    for familyName, isSelected in pairs(selectedFamilies) do
        if isSelected and byFamily[familyName] then
            for _, entry in ipairs(byFamily[familyName]) do
                local npcId, npcData = entry.npcIdKey, entry.npcData
                local displayIds = npcData.displayIds or {}

                local matchesSearch = true
                if searchLower ~= "" then
                    matchesSearch =
                        (npcData.name and npcData.name:lower():find(searchLower, 1, true))
                        or tostring(npcId):find(searchLower, 1, true)
                        or (npcData.family and npcData.family:lower():find(searchLower, 1, true))
                        or (npcData.uiMapName and npcData.uiMapName:lower():find(searchLower, 1, true))
                        or (npcData.expansion and npcData.expansion:lower():find(searchLower, 1, true))
                        or false
                    if not matchesSearch then
                        for _, id in ipairs(displayIds) do
                            if tostring(id):find(searchLower, 1, true) then matchesSearch = true; break end
                        end
                    end
                end

                local isRare = npcData.classification == "Rare" or npcData.classification == "Rare Elite"

                if matchesSearch
                   and TristateMatch(panel.showRares, isRare)
                   and TristateMatch(panel.showNameKeepers, npcData.nameKeeper or false)
                   and TristateMatch(panel.showFavorites, IsAnyDisplayIdFavorite(displayIds))
                   and TristateMatch(panel.showHideOwned, not IsAnyDisplayIdOwned(displayIds, ownedSet))
                   and (not PSM.state.selectedExpansions or not next(PSM.state.selectedExpansions)
                        or PSM.state.selectedExpansions[npcData.expansion])
                   and IsLocationSelected(npcData.uiMapName, PSM.state.selectedLocations)
                then
                    local zoneOk = true
                    if panel.showPetsInMyZone and panel.currentPlayerZone then
                        local zoneMatch = PSM.ModelsDataLoader:_IsZoneMatch(
                            { uiMapId = npcData.uiMapId, npcId = npcId, uiMapName = npcData.uiMapName },
                            panel.currentPlayerZone)
                        zoneOk = TristateMatch(panel.showPetsInMyZone, zoneMatch)
                    end

                    if zoneOk then
                        table.insert(items, {
                            npcId          = tonumber(npcId) or npcId,
                            name           = npcData.name or ("NPC " .. tostring(npcId)),
                            family         = npcData.family,
                            classification = npcData.classification or "Normal",
                            nameKeeper     = npcData.nameKeeper or false,
                            uiMapId        = npcData.uiMapId,
                            uiMapName      = npcData.uiMapName or "Unknown",
                            expansion      = npcData.expansion or "Unknown",
                            react          = npcData.react,
                            displayIds     = displayIds,
                            itemType       = "npc",
                        })
                    end
                end
            end
        end
    end

    return items
end

function PSM.NPCDataLoader:_ApplyNPCData(items)
    local panel = PSM.state.modelsPanel
    if not panel then return end

    panel.allNPCs = items

    if #items == 0 then
        if panel.infoText then panel.infoText:SetText("No matching NPCs | 0 pages") end
        if panel.pageText then panel.pageText:SetText("Page 0 of 0") end
        PSM.ModelsPanel:UpdateVisibleRows()
        return
    end

    if panel.infoText then
        -- "Show only owned" (showHideOwned == "inverted") matches an NPC if ANY
        -- of its display IDs is owned, so a single owned display ID shared by
        -- many NPCs inflates the NPC count well past what was actually tamed.
        -- Report the distinct owned-display-ID count alongside it in that case.
        if panel.showHideOwned == "inverted" then
            local ownedIds = {}
            for _, pet in ipairs(PSM.state.stablePets) do
                if pet.displayID then ownedIds[tonumber(pet.displayID)] = true end
            end
            local relevantOwned, distinctCount = {}, 0
            for _, item in ipairs(items) do
                for _, id in ipairs(item.displayIds or {}) do
                    if ownedIds[id] and not relevantOwned[id] then
                        relevantOwned[id] = true
                        distinctCount = distinctCount + 1
                    end
                end
            end
            panel.infoText:SetText(string.format("%d Display IDs owned, corresponding to %d NPCs", distinctCount, #items))
        else
            panel.infoText:SetText(string.format("%d NPCs found", #items))
        end
    end

    PSM.ModelsPanel:UpdateVisibleRows()
end
