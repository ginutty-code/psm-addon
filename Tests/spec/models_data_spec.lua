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

dofile("PetStableManagement_ModelsBrowser/Data/ModelsData.lua")
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

    -- The one number in this file that has to be re-pointed after a data refresh, and
    -- deliberately so: it is the only guard against generation being cut short, and a
    -- truncated run is otherwise perfectly self-consistent. When it fails, *read the
    -- numbers before bumping them* -- tens is a normal Wowhead refresh, thousands is a
    -- generator regression. Nothing else here is allowed to churn, so this stays the
    -- single deliberate human checkpoint rather than one of a crowd of literals.
    it("holds 7856 records", function()
        eq(#M.NpcId, 7856, "#NpcId")
        -- Not compared against the literal too: "exact inverses" below proves Index and
        -- NpcId are a bijection, so a second literal would restate that, not test it.
        eq(count(M.Index), #M.NpcId, "Index entry count")
    end)

    it("Index and NpcId are exact inverses", function()
        for i = 1, #M.NpcId do
            eq(M.Index[M.NpcId[i]], i, "Index[NpcId[" .. i .. "]]")
        end
        for npcId, i in pairs(M.Index) do
            eq(M.NpcId[i], npcId, "NpcId[Index[" .. npcId .. "]]")
        end
    end)

    -- Kept exact for the same reason as the record count: each guards against a lookup
    -- table *losing* entries, which would render blank cells in-game rather than error.
    -- Families/Expansions/Classifications are game facts and barely move; the zone count
    -- tracks the data and will need re-pointing alongside the record count.
    it("has the expected distinct lookup counts", function()
        eq(count(M.Families), 61, "distinct families")
        eq(count(M.Expansions), 12, "distinct expansions")
        eq(count(M.Classifications), 4, "distinct classifications")
        eq(count(M.UiMapNames), 400, "distinct zone names")
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
    -- `displayId` may be a single number or a list: roughly a quarter of records have
    -- several display IDs (2149 of 7856 at the time of writing), and that has always
    -- been true -- every case here happened to be single-valued until the tail record
    -- changed, so the shape went uncovered. Written as a list, compared elementwise.
    local function eqDisplayIds(actual, expected, label)
        if type(expected) == "table" then
            isType(actual, "table", label .. " (expected a list)")
            eq(#actual, #expected, label .. " count")
            for k = 1, #expected do
                eq(actual[k], expected[k], ("%s[%d]"):format(label, k))
            end
        else
            eq(actual, expected, label)
        end
    end

    -- The exact NPCs spot-checked by hand during T3.
    --
    -- Keyed by npcId and asserting only fields, never the dense index the npcId resolves
    -- to. That index shifts on every refresh that inserts an earlier record -- it is a
    -- position, not a fact about the pet -- so asserting it produced five guaranteed
    -- failures per refresh that taught nothing except the habit of bumping numbers.
    -- What is worth pinning is that 265254 is still a Warp Stalker in Naigtal.
    local CASES = {
        { npc = 30,     name = "Forest Spider",        family = "Spider",       expansion = "Vanilla",  classification = "Normal", zone = "Elwynn Forest", displayId = 366,    reactA = -1, reactH = -1 },
        { npc = 43,     name = "Mine Spider",          family = "Spider",       expansion = "Vanilla",  classification = "Normal", zone = "Elwynn Forest", displayId = 368,    reactA = -1, reactH = -1 },
        { npc = 113,    name = "Stonetusk Boar",       family = "Boar",         expansion = "Vanilla",  classification = "Normal", zone = "Elwynn Forest", displayId = 503,    reactA = 0,  reactH = 0  },
        { npc = 118,    name = "Prowler",              family = "Wolf",         expansion = "Vanilla",  classification = "Normal", zone = "Elwynn Forest", displayId = 11415,  reactA = -1, reactH = -1 },
        { npc = 265254, name = "Hal'hadar Leystalker", family = "Warp Stalker", expansion = "Midnight", classification = "Normal", zone = "Naigtal",       displayId = 141335, reactA = -1, reactH = -1 },
        -- Multi-valued by chance, and the only coverage this spec has of that shape.
        { npc = 273290, name = "Writhing Coiler",      family = "Serpent",      expansion = "Midnight", classification = "Normal", zone = "Vaults of Atal'Utek", displayId = { 137231, 142379 }, reactA = 0, reactH = 0 },
    }

    for _, c in ipairs(CASES) do
        it(("npc %d resolves to %s"):format(c.npc, c.name), function()
            local i = M.Index[c.npc]
            truthy(i, ("npc %d is present in Index"):format(c.npc))
            eq(M.Name[i], c.name, "name")
            eq(M.Families[M.FamilyId[i]], c.family, "family")
            eq(M.Expansions[M.ExpansionId[i]], c.expansion, "expansion")
            eq(M.Classifications[M.ClassificationId[i]], c.classification, "classification")
            eq(M.UiMapNames[M.UiMapId[i]], c.zone, "zone")
            eqDisplayIds(M.DisplayIds[i], c.displayId, "displayId")
            eq(M.ReactA[i], c.reactA, "reactA")
            eq(M.ReactH[i], c.reactH, "reactH")
        end)
    end
end)
