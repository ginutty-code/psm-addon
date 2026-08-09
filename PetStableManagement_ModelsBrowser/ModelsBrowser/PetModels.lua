-- PetModels.lua

local addonName = "PetStableManagement"

_G.PSM = _G.PSM or {}
local M = _G.PSM.PetModels or {}
_G.PSM.PetModels = M

-- Family -> array of { npcIdKey, npcData }, built once and shared with
-- NPCDataLoader so ModelsData is only scanned once per session.
function M:GetModelsDataByFamilyIndex()
    if not self._modelsDataByFamily and _G.ModelsData and type(_G.ModelsData) == "table" then
        local index = {}
        for npcIdKey, npcData in pairs(_G.ModelsData) do
            if type(npcData) == "table" and npcData.family then
                local fam = npcData.family
                index[fam] = index[fam] or {}
                table.insert(index[fam], { npcIdKey = npcIdKey, npcData = npcData })
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

    local displayIdMap = {}

    -- Helper to process a family subtable
    local function processSubtable(rawTable, exp, cont)
        for displayId, npcMap in pairs(rawTable) do
            if displayId ~= "taming" and type(npcMap) == "table" then
                local id = tonumber(displayId) or displayId
                local entry = displayIdMap[id] or { displayId = id, npcs = {} }
                displayIdMap[id] = entry

                if npcMap.taming then
                    entry.taming = npcMap.taming
                end

                for npcId, d in pairs(npcMap) do
                    if npcId ~= "taming" then
                        local npc
                        if type(d) == "table" and d[1] ~= nil then
                            -- Check if new 4-element tuple format: { name, classification, react, is_name_keeper }
                            if #d == 4 and (d[2] == "Normal" or d[2] == "Elite" or d[2] == "Rare" or d[2] == "Rare Elite") then
                                npc = {
                                    npcId           = tonumber(npcId) or npcId,
                                    name            = d[1],
                                    classification  = d[2],
                                    factionReaction = d[3],
                                    nameKeeper      = d[4] or false,
                                    expansion       = exp,
                                    location        = cont,
                                }
                            else
                                -- Legacy tuple format
                                local factionReaction, classification
                                if #d >= 4 then
                                    if type(d[4]) == "string" and d[4]:sub(1,1) == "[" then
                                        factionReaction = d[4]
                                        classification  = nil
                                    else
                                        classification = d[4]
                                        if #d >= 5 and type(d[5]) == "string" and d[5]:sub(1,1) == "[" then
                                            factionReaction = d[5]
                                        end
                                    end
                                end
                                npc = {
                                    npcId           = tonumber(npcId) or npcId,
                                    name            = d[1],
                                    location        = d[2] or cont,
                                    expansion       = d[3] or exp,
                                    classification  = classification or d[2],
                                    factionReaction = factionReaction,
                                    zones           = d.zones,
                                    nameKeeper      = d[6] or false,
                                    level           = d.level,
                                }
                            end
                        else
                            -- Legacy key-value format
                            npc = {
                                npcId           = tonumber(npcId) or npcId,
                                name            = d and d.name,
                                location        = d and (d.location or d.loc or cont),
                                expansion       = d and (d.expansion or d.exp or exp),
                                classification  = d and (d.classification or d.class),
                                zones           = d and d.zones,
                                nameKeeper      = d and (d.nameKeeper or d.name_keeper or false),
                                level           = d and d.level,
                            }
                        end
                        table.insert(entry.npcs, npc)
                    end
                end
            end
        end
    end

    -- 1. Check raw on self
    if self[familyName] and type(self[familyName]) == "table" and not self[familyName].displayIds then
        processSubtable(self[familyName], nil, nil)
    end

    -- 2. Check external PetData
    if _G.PetData and _G.PetData[familyName] and type(_G.PetData[familyName]) == "table" then
        processSubtable(_G.PetData[familyName], nil, nil)
    end

    -- 3. Check flat ModelsData[npcId] via family index
    local famEntries = self:GetModelsDataByFamilyIndex()[familyName]
    if famEntries then
        for _, item in ipairs(famEntries) do
            local npcIdKey, npcData = item.npcIdKey, item.npcData
            local numNpcId = tonumber(npcIdKey) or npcIdKey
            local dids = npcData.displayIds
            if dids and type(dids) == "table" then
                -- Built once per NPC, not per (NPC, displayId) pair -- 
                -- Safe to share since nothing mutates these records in place.
                local npcRecord = {
                    npcId           = numNpcId,
                    name            = npcData.name or ("NPC " .. tostring(numNpcId)),
                    classification  = npcData.classification or "Normal",
                    factionReaction = npcData.react,
                    nameKeeper      = npcData.nameKeeper or false,
                    expansion       = npcData.expansion or "Unknown",
                    location        = npcData.uiMapName or "Unknown",
                    uiMapId         = npcData.uiMapId,
                    uiMapName       = npcData.uiMapName,
                    taming          = npcData.taming,
                    conditions      = npcData.conditions,
                }

                for _, did in ipairs(dids) do
                    local id = tonumber(did) or did
                    local entry = displayIdMap[id] or { displayId = id, npcs = {} }
                    displayIdMap[id] = entry

                    -- Aggregate taming at display entry level
                    if npcData.taming and type(npcData.taming) == "table" then
                        entry.taming = entry.taming or {}
                        local existingSet = {}
                        for _, t in ipairs(entry.taming) do existingSet[t] = true end
                        for _, t in ipairs(npcData.taming) do
                            if not existingSet[t] then
                                existingSet[t] = true
                                table.insert(entry.taming, t)
                            end
                        end
                    end

                    table.insert(entry.npcs, npcRecord)
                end
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

    local seen = {}

    for name, v in pairs(self) do
        -- Skip internal caches (e.g. self._modelsDataByFamily) — leading underscore is this
        -- file's convention for "not a family name", and letting one through here inflates the
        -- count GenerateFilterSummary compares selections against, so "Reset Filters" can never
        -- actually match "everything selected".
        local isInternal = type(name) == "string" and name:sub(1, 1) == "_"
        if type(v) == "table" and name ~= "families" and not isInternal then
            seen[name] = true
        end
    end

    if _G.PetModelsData then
        for name, v in pairs(_G.PetModelsData) do
            if type(v) == "table" and name ~= "families" then
                seen[name] = true
            end
        end
    end

    if _G.PetData then
        for name in pairs(_G.PetData) do
            if type(_G.PetData[name]) == "table" then
                seen[name] = true
            end
        end
    end

    if _G.ModelsData then
        for _, npcData in pairs(_G.ModelsData) do
            if type(npcData) == "table" then
                if npcData.family then
                    seen[npcData.family] = true
                else
                    for cont, famTable in pairs(npcData) do
                        if type(famTable) == "table" then
                            for famName in pairs(famTable) do
                                seen[famName] = true
                            end
                        end
                    end
                end
            end
        end
    end

    local result = {}
    for name in pairs(seen) do table.insert(result, name) end
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
end
