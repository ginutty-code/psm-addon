-- Tests/spec/models_data_spec.lua
-- Golden tests for the generated ModelsData table.
--
-- This is the check the DATA_STRUCTURE_OPTIMIZATION_PLAN's T3 performed by hand,
-- made permanent. Its job is to fail loudly when psm-data regenerates ModelsData
-- into a shape the addon no longer understands -- the exact failure mode that made
-- psm-addon unloadable between T2 and T8, discovered only by launching the game.

local T = ...
local describe, it, eq, truthy, isType, count =
      T.describe, T.it, T.eq, T.truthy, T.isType, T.count

dofile("PetStableManagement_Data/ModelsData.lua")
local M = _G.ModelsData

-- Every per-record column, i.e. those keyed by denseIndex.
local DENSE_COLUMNS = {
    "NpcId", "Name", "DisplayIds", "UiMapId", "FamilyId",
    "ExpansionId", "ReactA", "ReactH", "ClassificationId", "NameKeeper", "Taming",
}

-- Columns present for every record. UiMapId and Taming are legitimately sparse:
-- absent indices are left as implicit nils (see the plan's target schema).
local REQUIRED_COLUMNS = {
    "Name", "DisplayIds", "FamilyId", "ExpansionId",
    "ReactA", "ReactH", "ClassificationId", "NameKeeper",
}

describe("ModelsData structure", function()
    it("loads and defines the backbone", function()
        isType(M, "table", "ModelsData")
        isType(M.Index, "table", "ModelsData.Index")
        isType(M.NpcId, "table", "ModelsData.NpcId")
    end)

    it("defines every documented column", function()
        for _, name in ipairs(DENSE_COLUMNS) do
            isType(M[name], "table", "column " .. name)
        end
        for _, name in ipairs({ "Families", "Expansions", "Classifications", "UiMapNames" }) do
            isType(M[name], "table", "lookup " .. name)
        end
    end)

    it("holds 7700 records, consistently across Index and NpcId", function()
        eq(#M.NpcId, 7700, "#NpcId")
        eq(count(M.Index), 7700, "Index entry count")
    end)

    it("Index and NpcId are exact inverses", function()
        for i = 1, #M.NpcId do
            eq(M.Index[M.NpcId[i]], i, "Index[NpcId[" .. i .. "]]")
        end
        for npcId, i in pairs(M.Index) do
            eq(M.NpcId[i], npcId, "NpcId[Index[" .. npcId .. "]]")
        end
    end)

    it("has the expected distinct lookup counts", function()
        eq(count(M.Families), 61, "distinct families")
        eq(count(M.Expansions), 12, "distinct expansions")
        eq(count(M.Classifications), 4, "distinct classifications")
        eq(count(M.UiMapNames), 394, "distinct zone names")
    end)
end)

describe("ModelsData per-record invariants", function()
    it("never leaves a required column empty", function()
        for i = 1, #M.NpcId do
            for _, name in ipairs(REQUIRED_COLUMNS) do
                if M[name][i] == nil then
                    error(("column %s missing at index %d (npcId %s)")
                        :format(name, i, tostring(M.NpcId[i])), 0)
                end
            end
        end
    end)

    it("resolves every FamilyId/ExpansionId/ClassificationId through its lookup", function()
        -- A dangling ID renders as a blank cell in-game rather than erroring, so
        -- this sweep is the only thing that would catch a generator regression.
        for i = 1, #M.NpcId do
            truthy(M.Families[M.FamilyId[i]], "Families[FamilyId[" .. i .. "]]")
            truthy(M.Expansions[M.ExpansionId[i]], "Expansions[ExpansionId[" .. i .. "]]")
            truthy(M.Classifications[M.ClassificationId[i]], "Classifications[" .. i .. "]")
        end
    end)

    it("resolves every present UiMapId to a zone name", function()
        for i = 1, #M.NpcId do
            local mapId = M.UiMapId[i]
            if mapId ~= nil then
                truthy(M.UiMapNames[mapId], "UiMapNames[" .. tostring(mapId) .. "] (index " .. i .. ")")
            end
        end
    end)

    it("stores DisplayIds as a bare number or a table, never a string", function()
        for i = 1, #M.NpcId do
            local d = M.DisplayIds[i]
            local t = type(d)
            if t ~= "number" and t ~= "table" then
                error(("DisplayIds[%d] is %s (%s)"):format(i, t, tostring(d)), 0)
            end
        end
    end)

    it("stores reactions as pre-parsed numbers, not '[a,b]' strings", function()
        -- T2 split the bracket-string into two numeric columns; a regression here
        -- would silently break the faction indicator in both views.
        for i = 1, #M.NpcId do
            isType(M.ReactA[i], "number", "ReactA[" .. i .. "]")
            isType(M.ReactH[i], "number", "ReactH[" .. i .. "]")
        end
    end)

    it("stores NameKeeper as a boolean", function()
        for i = 1, #M.NpcId do
            isType(M.NameKeeper[i], "boolean", "NameKeeper[" .. i .. "]")
        end
    end)

    it("stores Taming as an array of strings where present", function()
        for i = 1, #M.NpcId do
            local taming = M.Taming[i]
            if taming ~= nil then
                isType(taming, "table", "Taming[" .. i .. "]")
                for j, rule in ipairs(taming) do
                    isType(rule, "string", ("Taming[%d][%d]"):format(i, j))
                end
            end
        end
    end)
end)

describe("ModelsData known records", function()
    -- The exact NPCs spot-checked by hand during T3, plus the last dense index as
    -- a canary for truncated generation.
    local CASES = {
        { npc = 30,     index = 1,    name = "Forest Spider",        family = "Spider",       expansion = "Vanilla",  classification = "Normal", zone = "Elwynn Forest", displayId = 366,    reactA = -1, reactH = -1 },
        { npc = 43,     index = 2,    name = "Mine Spider",          family = "Spider",       expansion = "Vanilla",  classification = "Normal", zone = "Elwynn Forest", displayId = 368,    reactA = -1, reactH = -1 },
        { npc = 113,    index = 3,    name = "Stonetusk Boar",       family = "Boar",         expansion = "Vanilla",  classification = "Normal", zone = "Elwynn Forest", displayId = 503,    reactA = 0,  reactH = 0  },
        { npc = 118,    index = 4,    name = "Prowler",              family = "Wolf",         expansion = "Vanilla",  classification = "Normal", zone = "Elwynn Forest", displayId = 11415,  reactA = -1, reactH = -1 },
        { npc = 265254, index = 7700, name = "Hal'hadar Leystalker", family = "Warp Stalker", expansion = "Midnight", classification = "Normal", zone = "Naigtal",       displayId = 141335, reactA = -1, reactH = -1 },
    }

    for _, c in ipairs(CASES) do
        it(("npc %d resolves to %s"):format(c.npc, c.name), function()
            local i = M.Index[c.npc]
            eq(i, c.index, "dense index")
            eq(M.Name[i], c.name, "name")
            eq(M.Families[M.FamilyId[i]], c.family, "family")
            eq(M.Expansions[M.ExpansionId[i]], c.expansion, "expansion")
            eq(M.Classifications[M.ClassificationId[i]], c.classification, "classification")
            eq(M.UiMapNames[M.UiMapId[i]], c.zone, "zone")
            eq(M.DisplayIds[i], c.displayId, "displayId")
            eq(M.ReactA[i], c.reactA, "reactA")
            eq(M.ReactH[i], c.reactH, "reactH")
        end)
    end
end)
