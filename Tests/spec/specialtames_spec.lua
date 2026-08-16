-- Tests/spec/specialtames_spec.lua
-- PSM.PetModels' Special Tames predicates: the taming-rule and condition tests.
--
-- These existed in two hand-written copies (DisplayPassesFilters, ComputeMatchingFamilies)
-- and were about to become three when the NPC view started filtering on them. Merging them
-- is only safe if the surviving one is right, and none of the three was ever covered --
-- which is how the two managed to disagree about whether to `tonumber` an npcId.
--
-- Worth testing here rather than only in game because these are pure functions over plain
-- tables: no frames, no client API, no ModelsData. The rest of the filtering pipeline is
-- not, which is exactly why the logic worth checking was pulled out of it.

local T = ...
local describe, it, eq = T.describe, T.it, T.eq

-- PetModels is a browser file: it attaches to _G.PSM rather than taking an `ns`.
_G.PSM = _G.PSM or {}
dofile("PetStableManagement_ModelsBrowser/ModelsBrowser/PetModels.lua")
local PetModels = _G.PSM.PetModels

local function withConditions(map)
    _G.PSM.ConditionsData = { Get = function(npcId) return map[npcId] end }
end

describe("PetModels.TamingSetPasses", function()
    local function set(...) return PetModels.TamingSet({ ... }) end

    it("passes everything when no rule is selected", function()
        eq(PetModels.TamingSetPasses(set("Ottuk"), {}), true, "empty selection")
        eq(PetModels.TamingSetPasses(set(), nil), true, "nil selection")
    end)

    it("keeps a display that requires an actively selected rule", function()
        eq(PetModels.TamingSetPasses(set("Ottuk"), { Ottuk = true }), true, "match")
    end)

    -- The Rodent case from the user report, at the level the data actually has: two
    -- displays in one family, only one of which needs the skill.
    it("drops a display that requires nothing when a rule is selected", function()
        eq(PetModels.TamingSetPasses(set(), { Ottuk = true }), false, "no taming requirement")
    end)

    it("drops a display whose requirement is a different rule", function()
        eq(PetModels.TamingSetPasses(set("Direhorn"), { Ottuk = true }), false, "wrong rule")
    end)

    it("excludes a display requiring an inverted rule", function()
        eq(PetModels.TamingSetPasses(set("Ottuk"), { Ottuk = "inverted" }), false, "excluded")
        eq(PetModels.TamingSetPasses(set("Direhorn"), { Ottuk = "inverted" }), true, "unaffected")
    end)

    it("lets an inverted rule veto a display an active rule matched", function()
        eq(PetModels.TamingSetPasses(set("Ottuk", "Direhorn"),
            { Ottuk = true, Direhorn = "inverted" }), false, "veto wins")
    end)

    -- **The one piece of real logic in here.** A display needing *both* skills is not
    -- tameable with one of them, so selecting only Florafaun must not offer it.
    it("hides a both-required display when only one of the pair is selected", function()
        local both = set("Florafaun", "Direhorn")
        eq(PetModels.TamingSetPasses(both, { Florafaun = true }), false, "Florafaun alone")
        eq(PetModels.TamingSetPasses(both, { Direhorn = true }), false, "Direhorn alone")
        eq(PetModels.TamingSetPasses(both, { Florafaun = true, Direhorn = true }), true, "both")
    end)

    it("does not apply the pair rule to a display needing only one of them", function()
        eq(PetModels.TamingSetPasses(set("Florafaun"), { Florafaun = true }), true, "one only")
    end)
end)

describe("PetModels.NpcPassesConditions", function()
    it("reports whether anything is actively selected", function()
        eq(PetModels.ConditionsHaveActive({ Delve = "inverted" }), false, "only exclusions")
        eq(PetModels.ConditionsHaveActive({ Delve = true }), true, "an active one")
        eq(PetModels.ConditionsHaveActive({}), false, "empty")
    end)

    it("keeps an NPC carrying an actively selected condition", function()
        withConditions({ [101] = { "Delve" } })
        eq(PetModels.NpcPassesConditions(101, { Delve = true }, true), true, "match")
    end)

    it("drops an NPC that carries none of the selected conditions", function()
        withConditions({ [101] = { "Raid" } })
        eq(PetModels.NpcPassesConditions(101, { Delve = true }, true), false, "no match")
    end)

    it("drops an NPC carrying an inverted condition, even if it also matches", function()
        withConditions({ [101] = { "Delve", "Raid" } })
        eq(PetModels.NpcPassesConditions(101, { Delve = true, Raid = "inverted" }, true),
            false, "exclusion wins")
    end)

    it("keeps an unlisted NPC when only exclusions are selected", function()
        withConditions({})
        eq(PetModels.NpcPassesConditions(101, { Raid = "inverted" }, false), true, "nothing to exclude")
    end)

    it("drops an unlisted NPC when something is actively selected", function()
        withConditions({})
        eq(PetModels.NpcPassesConditions(101, { Delve = true }, true), false, "cannot match")
    end)

    -- The discrepancy that made this worth centralising: one old copy passed the raw
    -- ModelsData column and the other tonumber'd it, so a string id worked in one caller
    -- and silently failed the lookup in the other.
    it("coerces a string npcId, so both callers resolve the same NPC", function()
        withConditions({ [101] = { "Delve" } })
        eq(PetModels.NpcPassesConditions("101", { Delve = true }, true), true, "string id")
    end)

    it("drops an NPC with no id at all", function()
        withConditions({ [101] = { "Delve" } })
        eq(PetModels.NpcPassesConditions(nil, { Delve = true }, true), false, "nil id")
    end)
end)
