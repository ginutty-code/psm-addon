-- PetModels.lua

_G.PSM = _G.PSM or {}
local M = _G.PSM.PetModels or {}
_G.PSM.PetModels = M

-- ─── ModelsData accessors (structure-of-arrays schema) ─────────────────────
-- Shared access pattern for the columnar ModelsData shape -- see
-- ../../../DATA_STRUCTURE_OPTIMIZATION_PLAN.md, "Target schema for ModelsData".
-- Hot loops (filtering/sorting across all records) should read columns
-- directly -- e.g. ModelsData.Name[i] -- and iterate via
-- `for i = 1, #ModelsData.NpcId do`, not pairs(), and not through
-- GetModelsRecord below. GetModelsRecord is for cold, one-off lookups only;
-- it allocates a new table and does several lookup-table joins per call.

-- ─── Selection filters (locations, expansions) ────────────────────────────
-- Locations and expansions are the same shape, so the rule is one function -- both views
-- and both tabs must answer it identically. An NPC carries a single `UiMapId`, so
-- `NpcLocation` resolves exactly one name and there is nothing to split on "|".
--
-- The three answers are distinct, and conflating any two is the bug:
--
--   nil table   -- the filter was never initialised. Nothing is being asked; everything
--                  passes.
--   no `true`   -- the player chose "None". Only a value the data does not have passes,
--                  which is how an NPC with no expansion recorded survives an empty
--                  expansion selection.
--   otherwise   -- the value must be actively selected.
--
-- `false` counts as absent, and that is load-bearing: expansions go through
-- `checkbox:GetChecked()`, which writes `false` on uncheck, while locations write `nil`.
-- "Every box unticked" must mean the same thing for both.
--
-- `mode` is optional and exists for the hot loops: callers filtering thousands of rows
-- resolve it once with `SelectionMode` rather than rescanning the selection per row.

function M.SelectionMode(selection)
    if not selection then return "all" end
    for _, state in pairs(selection) do
        if state == true then return "match" end
    end
    return "none"
end

function M.SelectionAllows(selection, value, mode)
    mode = mode or M.SelectionMode(selection)
    if mode == "all"  then return true end
    if mode == "none" then return value == nil end
    return value ~= nil and selection[value] == true
end

-- ─── Special Tames predicates ─────────────────────────────────────────────
-- The taming-rule and condition tests, in one place so both views and SpecialTames' own
-- family computation answer them identically by construction.
--
-- The granularities are not interchangeable: taming skills attach to a *display*,
-- conditions attach to an *NPC*. A family is neither -- `ComputeMatchingFamilies` returns
-- families with at least one matching display, which is a seeding aid, never a filter.

-- Does a display's set of required taming skills satisfy the current selection?
-- `tamingSet` is a set of rule names; `selRules` is the tristate selection map.
--
-- The Florafaun/Direhorn clause is the one piece of real logic here: a display needing
-- *both* must not count as a match when the player selected only one of them, because
-- one skill alone will not tame it.
function M.TamingSetPasses(tamingSet, selRules)
    if not selRules or not next(selRules) then return true end

    local hasActive, matchActive = false, false
    for rKey, state in pairs(selRules) do
        if state == true then
            hasActive = true
            if tamingSet[rKey] then
                local fSel, dSel = selRules["Florafaun"] == true, selRules["Direhorn"] == true
                if not (tamingSet["Florafaun"] and tamingSet["Direhorn"]
                        and ((fSel and not dSel) or (dSel and not fSel))) then
                    matchActive = true
                end
            end
        elseif state == "inverted" then
            if tamingSet[rKey] then return false end
        end
    end
    return not hasActive or matchActive
end

-- Build the set form `TamingSetPasses` expects from a raw ModelsData.Taming array.
function M.TamingSet(list)
    local set = {}
    if list then
        for _, rule in ipairs(list) do set[rule] = true end
    end
    return set
end

-- Whether any condition is *actively* selected, as opposed to only excluded. Hoisted out
-- of the per-NPC test because callers run it inside loops over thousands of rows.
function M.ConditionsHaveActive(selConds)
    for _, state in pairs(selConds or {}) do
        if state == true then return true end
    end
    return false
end

-- Does one NPC satisfy the condition selection? An "inverted" condition disqualifies it
-- outright; with anything actively selected it must carry at least one of those.
-- `npcId` is coerced here rather than by the caller: the two previous copies of this test
-- disagreed about it (one passed the raw column, the other tonumber'd it), which is the
-- kind of difference that decides whether a lookup hits.
function M.NpcPassesConditions(npcId, selConds, userHasActive)
    local id = tonumber(npcId)
    if not id then return false end
    local condList = _G.PSM.ConditionsData and _G.PSM.ConditionsData.Get(id)
    if not condList then return not userHasActive end

    local matchedActive = false
    for _, cName in ipairs(condList) do
        local state = selConds[cName]
        if state == "inverted" then return false end
        if state == true then matchedActive = true end
    end
    return not userHasActive or matchedActive
end

-- Per-field resolvers for the columns that need a join through a lookup
-- table (classification/expansion/location). Shared by ModelsDataLoader.lua
-- and NPCDataLoader.lua so both views resolve these identically. Fields that
-- are a single direct column read (Name, NpcId, NameKeeper, UiMapId, ReactA,
-- ReactH) don't need a wrapper -- read ModelsData.<Column>[i] straight.
function M.NpcClassification(i)
    local modelsData = _G.ModelsData
    return modelsData.Classifications[modelsData.ClassificationId[i]]
end

function M.NpcExpansion(i)
    local modelsData = _G.ModelsData
    return modelsData.Expansions[modelsData.ExpansionId[i]]
end

function M.NpcLocation(i)
    local modelsData = _G.ModelsData
    local uiMapId = modelsData.UiMapId[i]
    return uiMapId and modelsData.UiMapNames[uiMapId] or "Unknown"
end

-- Resolves one full record by npcId into a small plain table, for call sites
-- that want npcData.field-style ergonomics (e.g. PopUpManager's fallback
-- lookup). location/factionReaction are kept as aliases of uiMapName/
-- reactA+reactH for consumers still on that older field naming. Returns nil
-- if npcId isn't in ModelsData. Don't call this from a per-record hot loop --
-- read columns directly instead.
function M:GetModelsRecord(npcId)
    local modelsData = _G.ModelsData
    if not modelsData then return nil end
    local i = modelsData.Index[npcId]
    if not i then return nil end

    local rawDisplayIds = modelsData.DisplayIds[i]
    local uiMapId = modelsData.UiMapId[i]
    local uiMapName = uiMapId and modelsData.UiMapNames[uiMapId]
    local reactA, reactH = modelsData.ReactA[i], modelsData.ReactH[i]

    return {
        npcId           = npcId,
        name            = modelsData.Name[i],
        displayIds      = type(rawDisplayIds) == "table" and rawDisplayIds or { rawDisplayIds },
        uiMapId         = uiMapId,
        uiMapName       = uiMapName,
        location        = uiMapName or "Unknown",
        family          = modelsData.Families[modelsData.FamilyId[i]],
        expansion       = modelsData.Expansions[modelsData.ExpansionId[i]],
        reactA          = reactA,
        reactH          = reactH,
        factionReaction = string.format("[%s,%s]", reactA, reactH),
        classification  = modelsData.Classifications[modelsData.ClassificationId[i]],
        nameKeeper      = modelsData.NameKeeper[i],
        taming          = modelsData.Taming[i],
    }
end

-- Resolves an array of denseIndex values (the shape GetFamilyModels' .npcs arrays store)
-- to full records, for UI code expecting object-style npc.name/npc.classification access.
function M:ResolveNpcRecords(npcs)
    local resolved = {}
    local modelsData = _G.ModelsData
    if not npcs or not modelsData then return resolved end
    for _, npc in ipairs(npcs) do
        local npcId = modelsData.NpcId[npc]
        local record = npcId and self:GetModelsRecord(npcId)
        if record then table.insert(resolved, record) end
    end
    return resolved
end

-- Family -> array of denseIndex, built once and shared with NPCDataLoader so
-- ModelsData is only scanned once per session. Numeric for-loop over the
-- dense NpcId/FamilyId columns instead of pairs() -- faster, and matches
-- ModelsData's own iteration convention.
function M:GetModelsDataByFamilyIndex()
    if not self._modelsDataByFamily and _G.ModelsData then
        local modelsData = _G.ModelsData
        local index = {}
        for i = 1, #modelsData.NpcId do
            local familyName = modelsData.Families[modelsData.FamilyId[i]]
            if familyName then
                index[familyName] = index[familyName] or {}
                table.insert(index[familyName], i)
            end
        end
        self._modelsDataByFamily = index
    end
    return self._modelsDataByFamily or {}
end

-- Returns processed family data, or nil if not found
function M:GetFamilyModels(familyName)
    if not familyName then return nil end

    -- Return cached result
    if self[familyName] and self[familyName].displayIds then
        return self[familyName]
    end

    local modelsData = _G.ModelsData
    local displayIdMap = {}

    local famIndices = self:GetModelsDataByFamilyIndex()[familyName]
    if famIndices and modelsData then
        for _, i in ipairs(famIndices) do
            local rawDisplayIds = modelsData.DisplayIds[i]
            -- DisplayIds[i] is a bare number when there's exactly one, else a
            -- table -- normalize to always-a-table for the loop below.
            local dids = type(rawDisplayIds) == "table" and rawDisplayIds or { rawDisplayIds }

            for _, did in ipairs(dids) do
                local id = tonumber(did) or did
                local entry = displayIdMap[id] or { displayId = id, npcs = {} }
                displayIdMap[id] = entry

                -- Aggregate taming at display entry level
                local npcTaming = modelsData.Taming[i]
                if npcTaming then
                    entry.taming = entry.taming or {}
                    local existingSet = {}
                    for _, t in ipairs(entry.taming) do existingSet[t] = true end
                    for _, t in ipairs(npcTaming) do
                        if not existingSet[t] then
                            existingSet[t] = true
                            table.insert(entry.taming, t)
                        end
                    end
                end

                -- Store the bare denseIndex, not a wrapper object -- readers
                -- pull fields straight from ModelsData.<Column>[i].
                table.insert(entry.npcs, i)
            end
        end
    end

    -- Flatten and sort displayIds
    local displayIds = {}
    for _, v in pairs(displayIdMap) do
        table.insert(displayIds, v)
    end
    table.sort(displayIds, function(a, b) return a.displayId < b.displayId end)

    self[familyName] = { displayIds = displayIds }
    return self[familyName]
end

-- Returns the sorted list of all known family names.
-- Memoized: the family universe is static for the session; only ClearCache() invalidates it.
function M:GetAvailableFamilies()
    if self._availableFamiliesCache then return self._availableFamiliesCache end

    -- ModelsData.Families is already the complete, deduplicated id->name
    -- lookup -- no need to scan all 7,700 records (or self's own cache, or
    -- the legacy PetData/PetModelsData globals, which are never populated).
    local result = {}
    local modelsData = _G.ModelsData
    if modelsData and modelsData.Families then
        for _, name in pairs(modelsData.Families) do
            table.insert(result, name)
        end
    end
    table.sort(result)
    self._availableFamiliesCache = result
    return result
end

-- Evicts all cached family data
function M:ClearCache()
    self._modelsDataByFamily = nil
    for _, name in ipairs(self:GetAvailableFamilies()) do
        self[name] = nil
    end
    self._availableFamiliesCache = nil
    -- Description strings memoized in ModelsDataLoader.lua's _CalculateModelsData
    -- (keyed by denseIndex, since indices can't hold fields the way the old
    -- npcRecord wrapper objects could) -- kept alongside the family cache.
    _G.PSM._modelsDescriptionCache = nil
end
