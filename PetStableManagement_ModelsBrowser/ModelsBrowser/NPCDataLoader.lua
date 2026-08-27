-- ModelsBrowser/NPCDataLoader.lua
-- Data loading and filtering for the NPC view of the Pet Models Browser.
-- Reads ModelsData's columns directly (via PetModels.lua's shared family
-- index), so this is a plain text pipeline (no model/display data joins) --
-- deliberately lighter than ModelsDataLoader's display-ID pipeline.


_G.PSM = _G.PSM or {}
local PSM = _G.PSM

PSM.NPCDataLoader = PSM.NPCDataLoader or {}

--------------------------------------------------------------------------------
-- CACHE
--------------------------------------------------------------------------------

-- The NPC view's inputs. A slice belongs here only once the compute reads it -- declaring a
-- dependency it ignores buys cache misses for nothing. Enforced by `loaderinputs_spec`.
local NPC_RESULT_SLICES = {
    "families", "expansions", "locations", "tamingRules", "conditions",
    "toggles", "favorites", "pets", "zone", "search", "panel",
}

local npcResults   -- the selector; built on first use, dropped by ReleaseCache

-- The NPC half of the pair; see ModelsDataLoader:ReleaseCache for why this cancels
-- rather than only clearing.
function PSM.NPCDataLoader:ReleaseCache()
    if PSM._npcDebounceTimer then PSM._npcDebounceTimer:Cancel() end
    PSM._npcDebounceTimer = nil
    npcResults = nil
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
-- Ownership is only knowable per display ID: Blizzard's stable API does not report the
-- creature a pet was tamed from, so "do I own this NPC" has no answer.
--
-- Both numbers walk the stable, not the NPC list -- walking the NPC list counts one pet
-- once per NPC sharing its model, which turns a stable of 207 into 414 owned. `unique`
-- answers "how many different pets is that"; `total` is the one that reconciles with the
-- Owned Pets panel's own count.
--
-- A pet whose display ID is in no NPC record is in neither figure, so an unfiltered list
-- can read slightly under the stable total. That is honest, not an off-by-one.
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

-- Locations and expansions are `PetModels.SelectionAllows*` now. These were two local
-- copies, and their "absent vs empty" bug is the one that reached players: both returned
-- true for an empty selection, so "None" on the Locations or Expansions tab emptied the
-- Models view and left the NPC list untouched.

--------------------------------------------------------------------------------
-- LOADING PIPELINE
--------------------------------------------------------------------------------

-- The same delay as the models loader, from the same constant. Switching into the NPC view
-- paints last load's list synchronously, so a longer window here means visibly stale rows.
-- Nothing is left for one to absorb: `PSM.Store`'s flush coalesces bursts upstream and the
-- search box debounces separately (`SEARCH_DELAY`).
function PSM.NPCDataLoader:LoadNPCsForSelectedFamilies()
    if not PSM.state.modelsPanel then return end
    if PSM._npcDebounceTimer then PSM._npcDebounceTimer:Cancel() end
    PSM._npcDebounceTimer = C_Timer.NewTimer(PSM.Config.RENDER_DELAY, function()
        PSM.NPCDataLoader:_LoadNPCsImmediate()
    end)
end

function PSM.NPCDataLoader:_LoadNPCsImmediate()
    local panel = PSM.state.modelsPanel
    if not panel then return end

    -- Reuse is the selector's job now, and it is exact rather than time-bounded -- see
    -- ModelsDataLoader:_LoadModelsImmediate for why the 0.2s expiry went with the key.
    npcResults = npcResults or PSM.Store:Selector(NPC_RESULT_SLICES, function()
        return PSM.NPCDataLoader:_CalculateNPCData()
    end)

    self:_ApplyNPCData(npcResults())

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

    -- Special Tames, hoisted out of the row loop: `next()` and the active-conditions scan
    -- are constant per pass, and this loop runs over thousands of rows.
    local selRules  = PSM.state.selectedTamingRules
    local selConds  = PSM.state.selectedConditions
    local hasRules  = selRules and next(selRules) ~= nil
    local hasConds  = selConds and next(selConds) ~= nil
    local condsHaveActive = hasConds and PSM.PetModels.ConditionsHaveActive(selConds)

    -- Same reason: resolving the selection mode is a scan of the selection table, and this
    -- loop runs over every NPC of every selected family.
    local selExpansions = PSM.state.selectedExpansions
    local selLocations  = PSM.state.selectedLocations
    local expansionMode = PSM.PetModels.SelectionMode(selExpansions)
    local locationMode  = PSM.PetModels.SelectionMode(selLocations)

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

                -- Taming skills are a display-level fact recorded per NPC, and no display
                -- has two NPCs that disagree, so this NPC's own column equals the display
                -- aggregate the Models view builds. Conditions are per NPC, so no "does any
                -- NPC of this display qualify" loop is needed here.
                local tamingOk = not hasRules
                    or PetModels.TamingSetPasses(PetModels.TamingSet(modelsData.Taming[i]), selRules)
                local condsOk = not hasConds
                    or PetModels.NpcPassesConditions(npcId, selConds, condsHaveActive)

                if matchesSearch and tamingOk and condsOk
                   and TristateMatch(PSM.FilterState:Get("showRares"), isRare)
                   and TristateMatch(PSM.FilterState:Get("showNameKeepers"), nameKeeper or false)
                   and TristateMatch(PSM.FilterState:Get("showFavorites"), IsAnyDisplayIdFavorite(displayIds))
                   and TristateMatch(PSM.FilterState:Get("showHideOwned"), not IsAnyDisplayIdOwned(displayIds, ownedSet))
                   and PetModels.SelectionAllows(selExpansions, expansion, expansionMode)
                   and PetModels.SelectionAllows(selLocations, uiMapName, locationMode)
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
                            name           = name or PSM.L("NPC %s", tostring(npcId)),
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

    -- This hands the selector's cached table to the panel, and `UpdateNPCPanelLayout` sorts
    -- it in place -- a deliberate exception to Store's read-only rule, because a reorder
    -- cannot change which NPCs matched. It is also what makes `_npcSortCache`'s identity
    -- check work: the selector returns the same table until a dependency moves, so copying
    -- here would re-sort ~7000 entries on every reload.
    panel.allNPCs = items

    if #items == 0 then
        if panel.infoText then panel.infoText:SetText(PSM.L("No matching NPCs | 0 pages")) end
        if panel.pageText then panel.pageText:SetText(PSM.L("Page %d of %d", 0, 0)) end
        PSM.ModelsPanel:UpdateVisibleRows()
        return
    end

    if panel.infoText then
        -- One caption in every filter state, matching the Models view's
        -- "N display IDs | M owned". The bracket appears only when there are duplicates
        -- to note: no bracket means every owned pet here is a different model.
        local unique, total = OwnedPetCounts(items)
        if total > unique then
            panel.infoText:SetText(PSM.L("%d NPCs found | %d owned (%d including duplicates)",
                #items, unique, total))
        else
            panel.infoText:SetText(PSM.L("%d NPCs found | %d owned", #items, unique))
        end
    end

    PSM.ModelsPanel:UpdateVisibleRows()
end
