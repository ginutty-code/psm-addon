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

-- The NPC view's inputs. `tamingRules` and `conditions` joined this list at the same time
-- as the filtering that reads them -- never before, since declaring a dependency the
-- compute ignores buys cache misses for nothing.
--
-- Until then this view applied neither, and Special Tames reached it only as the family
-- narrowing `RecomputeSmartFamilySelection` performs on Apply. That is a **superset**:
-- `ComputeMatchingFamilies` returns families with *at least one* matching display, and
-- families are mixed, so filtering for Ottuk taming kept the whole Rodent family --
-- including every Rodent needing no special taming at all.
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

function PSM.NPCDataLoader:CreateRenderCache()
    self:ReleaseCache()
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

-- Locations and expansions are `PetModels.SelectionAllows*` now. These were two local
-- copies, and their "absent vs empty" bug is the one that reached players: both returned
-- true for an empty selection, so "None" on the Locations or Expansions tab emptied the
-- Models view and left the NPC list untouched.

--------------------------------------------------------------------------------
-- LOADING PIPELINE
--------------------------------------------------------------------------------

-- **The same delay as the models loader, read from the same place.** These were 0.01 and
-- 0.15, and the gap was visible: switching into the NPC view paints `panel.allNPCs` --
-- last load's list -- synchronously, so for 150ms the panel showed rows the current filter
-- excludes. The models view has the identical window at 0.01s and nobody can see it.
--
-- The 0.15 was raised from 0.01 in 069c646 to absorb bursts of this call, back when one
-- continent click meant fifteen of them. `PSM.Store`'s flush coalesces those upstream now,
-- and search has always been debounced separately (`SEARCH_DELAY`, in the search box
-- itself), so nothing is left for the longer window to absorb. Two literals that had to
-- agree and silently stopped agreeing is what `Config.RENDER_DELAY` is for.
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

                -- **Special Tames, at the granularity the data actually has.**
                --
                -- Taming skills are a display-level fact and `ModelsData.Taming` records
                -- them per NPC; checked across the whole dataset, no display has two NPCs
                -- that disagree (7031 shared-display comparisons, zero conflicts), so
                -- reading this NPC's own column is equivalent to the display aggregate
                -- `GetFamilyModels` builds for the Models view -- and needs no lookup.
                --
                -- Conditions are an NPC-level fact, so this is the *simpler* case here
                -- than in the Models view: one NPC, one answer, no "does any NPC of this
                -- display qualify" loop.
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

    -- **This hands the selector's cached table to the panel, and `UpdateNPCPanelLayout`
    -- sorts it in place.** A deliberate exception to Store's "treat a selector's value as
    -- read-only" rule, kept because the mutation is a *reorder of the same elements* -- it
    -- cannot change which NPCs matched, only the order they are listed in, which is the
    -- panel's business anyway. Sort field and direction are not slices; sorting is applied
    -- at render, not at compute.
    --
    -- It also makes `_npcSortCache`'s identity check (`sortCache.items ~= items`) sharper
    -- than before rather than weaker: the selector returns the *same* table until a
    -- dependency moves, so an unchanged list is recognised as already sorted, and a changed
    -- one is a new table and re-sorts. Copying here would restore the contract and defeat
    -- that check, re-sorting ~7000 entries on every reload to avoid a reordering nobody
    -- can observe.
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
