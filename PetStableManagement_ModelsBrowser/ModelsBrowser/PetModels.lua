-- PetModels.lua

local addonName = "PetStableManagement"

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

-- npcId -> denseIndex, or nil if npcId isn't in ModelsData.
function M:GetModelsIndex(npcId)
    local modelsData = _G.ModelsData
    return modelsData and modelsData.Index[npcId]
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

-- Resolves an array of denseIndex values (the shape GetFamilyModels/
-- GetModelInfo's .npcs arrays store) to an array of full records, via
-- GetModelsRecord. Shared by every consumer that hands a family's .npcs
-- list to UI code expecting object-style npc.name/npc.classification access
-- (PopUpManager's magnify popups, Pet Roulette).
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

-- Returns the number of display IDs for a family
function M:GetModelCount(familyName)
    local f = self:GetFamilyModels(familyName)
    return f and #f.displayIds or 0
end

-- Returns the displayData entry for a specific display ID, or nil
function M:GetModelInfo(familyName, displayId)
    local f = self:GetFamilyModels(familyName)
    if not f then return nil end
    local id = tostring(displayId)
    for _, d in ipairs(f.displayIds) do
        if tostring(d.displayId) == id then return d end
    end
end

-- Returns the NPC list for a specific display ID, or {}
function M:GetAllPetsForDisplay(familyName, displayId)
    local info = self:GetModelInfo(familyName, displayId)
    return info and info.npcs or {}
end

-- Processes all known families and caches them; returns count and elapsed ms
function M:PreloadAllFamilies()
    local t0, count = debugprofilestop(), 0
    for _, name in ipairs(self:GetAvailableFamilies()) do
        if self:GetFamilyModels(name) then count = count + 1 end
    end
    local elapsed = debugprofilestop() - t0
    print(string.format("[%s] Preloaded %d families in %.2fms", addonName, count, elapsed))
    return count, elapsed
end

-- Returns a snapshot of load progress
function M:GetLoadingStats()
    local families = self:GetAvailableFamilies()
    local total, loaded = #families, 0
    for _, name in ipairs(families) do
        if self[name] and self[name].displayIds then loaded = loaded + 1 end
    end
    return {
        totalFamilies   = total,
        loadedFamilies  = loaded,
        pendingFamilies = total - loaded,
        loadPercentage  = total > 0 and (loaded / total * 100) or 0,
    }
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
