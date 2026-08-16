-- ModelsBrowser/NPCDataLoader.lua
-- Data loading and filtering for the NPC view of the Pet Models Browser.
-- Reads ModelsData's columns directly (via PetModels.lua's shared family
-- index), so this is a plain text pipeline (no model/display data joins) --
-- deliberately lighter than ModelsDataLoader's display-ID pipeline.

local addonName = "PetStableManagement"

_G.PSM = _G.PSM or {}
local PSM = _G.PSM

PSM.NPCDataLoader = PSM.NPCDataLoader or {}

--------------------------------------------------------------------------------
-- CACHE
--------------------------------------------------------------------------------

-- The NPC half of the pair; see ModelsDataLoader:ReleaseCache for why this cancels
-- rather than only clearing. This side has the wider window of the two -- a 0.15s
-- debounce against the models view's 0.01s -- so it is the one a player can actually
-- hit by changing a filter and closing the panel straight after.
function PSM.NPCDataLoader:ReleaseCache()
    if PSM._npcDebounceTimer then PSM._npcDebounceTimer:Cancel() end
    PSM._npcRenderCache   = nil
    PSM._npcDebounceTimer = nil
end

function PSM.NPCDataLoader:CreateRenderCache()
    self:ReleaseCache()
end

-- Build a canonical string from a selected-values table (key=name, value=bool),
-- mirroring ModelsDataLoader's SelectedMapKey.
local function SelectedMapKey(map)
    if not map or not next(map) then return "none," end
    local parts = {}
    for k, v in pairs(map) do if v then table.insert(parts, k) end end
    table.sort(parts)
    return table.concat(parts, ",") .. ","
end

function PSM.NPCDataLoader:GenerateCacheKey()
    local panel = PSM.state.modelsPanel
    if not panel then return "" end

    local searchText  = panel.searchBox and panel.searchBox:GetSearchText() or ""
    local searchLower = searchText ~= "" and searchText:lower() or ""

    local zoneKey = ""
    if PSM.FilterState:Get("showPetsInMyZone") and panel.currentPlayerZone then
        zoneKey = panel.currentPlayerZone .. (PSM.FilterState:Get("showPetsInMyZone") == "inverted" and "_inv," or ",")
    end

    return string.format("%s_%s_%s_%s_%s_%s_%s_%s_%s_%s_%d",
        searchLower,
        SelectedMapKey(PSM.state.selectedModelsFamilies),
        SelectedMapKey(PSM.state.selectedExpansions),
        SelectedMapKey(PSM.state.selectedLocations),
        zoneKey,
        tostring(PSM.FilterState:Get("showRares") or "none"),
        tostring(PSM.FilterState:Get("showNameKeepers") or "none"),
        tostring(PSM.FilterState:Get("showFavorites") or "none"),
        tostring(PSM.FilterState:Get("showHideOwned") or "none"),
        SelectedMapKey(PSM.state.favoriteModels),
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

local function IsAnyDisplayIdFavorite(displayIds)
    if not displayIds or not PSM.state.favoriteModels then return false end
    for _, id in ipairs(displayIds) do
        if PSM.state.favoriteModels[id] then return true end
    end
    return false
end

-- Every display ID the player has tamed, for the Hide Owned filter pass. Cheap -- the
-- stable holds a couple of hundred pets at most -- but it must be built once per pass
-- rather than once per NPC, which is the O(displayIds x stablePets) trap this file already
-- fell into once. Named rather than inlined for that reason, and because it is the mirror
-- of ShownDisplayIdSet below: what is in the stable, against what is on screen.
local function OwnedDisplayIdSet()
    local owned = {}
    for _, pet in ipairs(PSM.state.stablePets) do
        if pet.displayID then owned[tonumber(pet.displayID)] = true end
    end
    return owned
end

-- The set of display IDs any NPC in this list uses. The inverse direction to
-- OwnedDisplayIdSet: what is on screen, rather than what is in the stable.
local function ShownDisplayIdSet(items)
    local shown = {}
    for _, item in ipairs(items) do
        for _, id in ipairs(item.displayIds or {}) do shown[id] = true end
    end
    return shown
end

-- The player's pets represented in this list, counted two ways: `unique` collapses pets
-- that share a model, `total` counts every pet record.
--
-- **Ownership is only knowable per display ID.** Blizzard's stable API reports a pet's
-- displayID, petNumber and specID -- but not the creature it was tamed from -- so "do I own
-- this NPC" has no answer available. What the player wants to know has one: how many of
-- *their pets* are represented here.
--
-- **Both numbers come from walking the stable, not the NPC list, and that is the design.**
-- Walking the NPC list and asking "is this owned" counts one pet once per NPC sharing its
-- model, which is how a stable of 207 first reported 414 owned. Walking the stable counts
-- each pet exactly once by construction.
--
-- One record is one pet: LoadPersistentDataForDisplay appends each character's snapshot
-- whole and no pet belongs to two characters, so `petNumber` is not needed to tell them
-- apart. It would be if that loader ever merged overlapping snapshots -- and `total` is
-- what would expose that, since an unfiltered list should report the stable's own size.
--
-- Why both: `unique` is the honest answer to "how many different pets is that", and `total`
-- is the one that reconciles with the count in the Owned Pets panel. Reporting only `total`
-- produced "28 NPCs found | 33 owned", which is true and reads as nonsense.
--
-- A pet whose display ID is in no NPC record is in neither figure, so an unfiltered list
-- can read slightly under the stable total. That is the addon reporting honestly that it
-- has no NPC for that model -- a pet from a removed creature, or one tamed since the last
-- data refresh -- not an off-by-one.
local function OwnedPetCounts(items)
    local shown = ShownDisplayIdSet(items)
    local seen, unique, total = {}, 0, 0
    for _, pet in ipairs(PSM.state.stablePets) do
        local id = pet.displayID and tonumber(pet.displayID)
        if id and shown[id] then
            total = total + 1
            if not seen[id] then
                seen[id] = true
                unique = unique + 1
            end
        end
    end
    return unique, total
end

-- ownedSet is built once per pass (below), not once per NPC --
local function IsAnyDisplayIdOwned(displayIds, ownedSet)
    if not displayIds or not ownedSet then return false end
    for _, id in ipairs(displayIds) do
        if ownedSet[id] then return true end
    end
    return false
end

-- Two-state single-zone match, mirroring ModelsDataLoader:_IsLocationSelected. The
-- "inverted" third state is gone; see that function for why it never meant anything
-- distinct here.
local function IsLocationSelected(uiMapName, selectedLocations)
    if not selectedLocations or not next(selectedLocations) then return true end

    local userHasActive = false
    for _, state in pairs(selectedLocations) do
        if state == true then userHasActive = true; break end
    end
    if not userHasActive then return true end

    if not uiMapName then return false end
    return selectedLocations[uiMapName] == true
end

--------------------------------------------------------------------------------
-- LOADING PIPELINE
--------------------------------------------------------------------------------

function PSM.NPCDataLoader:LoadNPCsForSelectedFamilies()
    if not PSM.state.modelsPanel then return end
    if PSM._npcDebounceTimer then PSM._npcDebounceTimer:Cancel() end
    PSM._npcDebounceTimer = C_Timer.NewTimer(0.15, function()
        PSM.NPCDataLoader:_LoadNPCsImmediate()
    end)
end

function PSM.NPCDataLoader:_LoadNPCsImmediate()
    local panel = PSM.state.modelsPanel
    if not panel then return end

    -- Reuse the last computed item list for 0.2s if nothing filter-relevant
    -- changed, mirroring ModelsDataLoader's render cache (ModelsDataLoader.lua:415-421).
    local cacheKey = self:GenerateCacheKey()
    if PSM._npcRenderCache and PSM._npcRenderCache.key == cacheKey
       and GetTime() - PSM._npcRenderCache.timestamp < 0.2 then
        self:_ApplyNPCData(PSM._npcRenderCache.data)
    else
        local items = self:_CalculateNPCData()
        PSM._npcRenderCache = { key = cacheKey, timestamp = GetTime(), data = items }
        self:_ApplyNPCData(items)
    end

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

    local searchText  = panel.searchBox and panel.searchBox:GetSearchText() or ""
    local searchLower = searchText ~= "" and searchText:lower() or ""

    -- Built once per reload, only when the Hide Owned filter is active.
    local ownedSet = PSM.FilterState:Get("showHideOwned") and OwnedDisplayIdSet() or nil

    -- Iterate only selected families via the shared family index instead of
    -- scanning all ~7700 ModelsData entries and rejecting non-matches.
    -- byFamily[name] is an array of denseIndex values.
    local byFamily = PSM.PetModels:GetModelsDataByFamilyIndex()
    local modelsData = _G.ModelsData
    local PetModels = PSM.PetModels

    local items = {}
    for familyName, isSelected in pairs(selectedFamilies) do
        if isSelected and byFamily[familyName] then
            for _, i in ipairs(byFamily[familyName]) do
                local npcId = modelsData.NpcId[i]
                local name = modelsData.Name[i]
                local family = modelsData.Families[modelsData.FamilyId[i]]
                local classification = PetModels.NpcClassification(i)
                local nameKeeper = modelsData.NameKeeper[i]
                local uiMapId = modelsData.UiMapId[i]
                local uiMapName = uiMapId and modelsData.UiMapNames[uiMapId]
                local expansion = PetModels.NpcExpansion(i)
                local rawDisplayIds = modelsData.DisplayIds[i]
                local displayIds = type(rawDisplayIds) == "table" and rawDisplayIds or { rawDisplayIds }

                local matchesSearch = true
                if searchLower ~= "" then
                    matchesSearch =
                        (name and name:lower():find(searchLower, 1, true))
                        or tostring(npcId):find(searchLower, 1, true)
                        or (family and family:lower():find(searchLower, 1, true))
                        or (uiMapName and uiMapName:lower():find(searchLower, 1, true))
                        or (expansion and expansion:lower():find(searchLower, 1, true))
                        or false
                    if not matchesSearch then
                        for _, id in ipairs(displayIds) do
                            if tostring(id):find(searchLower, 1, true) then matchesSearch = true; break end
                        end
                    end
                end

                local isRare = classification == "Rare" or classification == "Rare Elite"

                if matchesSearch
                   and TristateMatch(PSM.FilterState:Get("showRares"), isRare)
                   and TristateMatch(PSM.FilterState:Get("showNameKeepers"), nameKeeper or false)
                   and TristateMatch(PSM.FilterState:Get("showFavorites"), IsAnyDisplayIdFavorite(displayIds))
                   and TristateMatch(PSM.FilterState:Get("showHideOwned"), not IsAnyDisplayIdOwned(displayIds, ownedSet))
                   and (not PSM.state.selectedExpansions or not next(PSM.state.selectedExpansions)
                        or PSM.state.selectedExpansions[expansion])
                   and IsLocationSelected(uiMapName, PSM.state.selectedLocations)
                then
                    local zoneOk = true
                    if PSM.FilterState:Get("showPetsInMyZone") and panel.currentPlayerZone then
                        -- _IsZoneMatch reads columns via a denseIndex directly -- no need
                        -- to build a temporary {uiMapId=, npcId=, uiMapName=} shim.
                        local zoneMatch = PSM.ModelsDataLoader:_IsZoneMatch(i, panel.currentPlayerZone)
                        zoneOk = TristateMatch(PSM.FilterState:Get("showPetsInMyZone"), zoneMatch)
                    end

                    if zoneOk then
                        table.insert(items, {
                            npcId          = npcId,
                            name           = name or ("NPC " .. tostring(npcId)),
                            family         = family,
                            classification = classification or "Normal",
                            nameKeeper     = nameKeeper or false,
                            uiMapId        = uiMapId,
                            uiMapName      = uiMapName or "Unknown",
                            expansion      = expansion or "Unknown",
                            reactA         = modelsData.ReactA[i],
                            reactH         = modelsData.ReactH[i],
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
        -- One caption in every filter state, reading the same as the Models view's
        -- "N display IDs | M owned" -- with the duplicate note appearing only when there
        -- are duplicates to note. Silence is the common case and carries information too:
        -- no bracket means every owned pet here is a different model.
        --
        -- "Show only owned" used to get its own sentence -- "N Display IDs owned,
        -- corresponding to M NPCs" -- because the count beside it was measured in the wrong
        -- unit and needed explaining. That explanation is now the bracket, and it applies
        -- in every filter state rather than one.
        local unique, total = OwnedPetCounts(items)
        if total > unique then
            panel.infoText:SetText(string.format("%d NPCs found | %d owned (%d including duplicates)",
                #items, unique, total))
        else
            panel.infoText:SetText(string.format("%d NPCs found | %d owned", #items, unique))
        end
    end

    PSM.ModelsPanel:UpdateVisibleRows()
end
