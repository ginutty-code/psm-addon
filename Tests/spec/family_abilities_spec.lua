-- Tests/spec/family_abilities_spec.lua
-- ns.Data:GetFamilyAbilities / :GetSpecAbilities and the ns.Data:GetAbilityTooltip
-- factory built on top of them -- the family / spec halves of psm-backlog#9's
-- "hover a family, see its abilities". All three read the same _G.AbilitiesData
-- the detail index does, in the same single walk (BuildAbilityIndex).

local T = ...
local describe, it, eq, truthy = T.describe, T.it, T.eq, T.truthy

local Addon = dofile("Tests/wow/addon.lua")

local function freshData()
    _G.PetStableManagementDB = nil
    local ns = Addon.namespace()
    Addon.load("PetStableManagement/Shared/Utils.lua", ns)
    Addon.load("PetStableManagement/Shared/Data.lua", ns)
    return ns.Data, ns
end

-- The tooltip factory pulls in colour/locale tokens, Config's FAMILY_TO_SPEC, and
-- PetTooltip (its bucket colours, and the "pet" branch's whole implementation).
local function freshFactory()
    _G.PetStableManagementDB = nil
    local ns = Addon.namespace()
    Addon.load("PetStableManagement/Shared/Locale.lua", ns)
    Addon.load("PetStableManagement/Shared/Config.lua", ns)
    Addon.load("PetStableManagement/UI/Theme.lua", ns)
    Addon.load("PetStableManagement/Shared/Utils.lua", ns)
    Addon.load("PetStableManagement/Shared/Data.lua", ns)
    Addon.load("PetStableManagement/OwnedPets/PetTooltip.lua", ns)
    return ns.Data, ns
end

local function lineTexts(lines)
    local out = {}
    for _, l in ipairs(lines or {}) do
        local text = type(l) == "table" and l.text or l
        if text and text ~= " " then out[#out + 1] = text end
    end
    return out
end

-- A family with all four ranks, deliberately defined out of display order.
local function fixtureAllRanks()
    _G.AbilitiesData = {
        [1] = { name = "Wolf", ranks = {
            ["Exotic Passive"] = { [14] = { name = "Zed Passive" } },
            ["Bonus Ability"]  = { [12] = { name = "Mid Bonus" }, [13] = { name = "Ace Bonus" } },
            ["Special Ability"] = { [11] = { name = "Sole Special" } },
            ["Exotic Ability"] = { [15] = { name = "Exo Active" } },
        } },
        ["Spec"] = { name = "Spec abilities", ranks = {
            ["Ferocity Ability"] = { [264667] = { name = "Primal Rage" } },
            ["Ferocity Passive"] = { [264663] = { name = "Predator's Thirst" } },
            ["Cunning Ability"]  = { [272682] = { name = "Master's Call" } },
        } },
    }
end

describe("GetFamilyAbilities", function()
    it("groups a family's abilities by rank, sorted by name within a rank", function()
        fixtureAllRanks()
        local Data = freshData()
        local fam = Data:GetFamilyAbilities("Wolf")
        truthy(fam ~= nil, "Wolf is present")
        local bonus = {}
        for _, row in ipairs(fam.ranks["Bonus Ability"]) do bonus[#bonus + 1] = row.name end
        eq(table.concat(bonus, ","), "Ace Bonus,Mid Bonus", "sorted by name")
    end)

    it("carries no exotic notion of its own -- that is ns.Data.IsExoticFamily's job", function()
        fixtureAllRanks()  -- the Wolf fixture has Exotic Ability / Exotic Passive ranks
        local Data = freshData()
        eq(Data:GetFamilyAbilities("Wolf").isExotic, nil, "no isExotic field derived from ability ranks")
    end)

    it("returns nil for an unknown family and when AbilitiesData is absent", function()
        fixtureAllRanks()
        local Data = freshData()
        eq(Data:GetFamilyAbilities("Nonexistent"), nil, "unknown family")
        _G.AbilitiesData = nil
        eq(freshData():GetFamilyAbilities("Wolf"), nil, "no data loaded")
    end)
end)

describe("GetSpecAbilities", function()
    it("returns the spec's Ability and Passive rows", function()
        fixtureAllRanks()
        local Data = freshData()
        local fer = Data:GetSpecAbilities("Ferocity")
        eq(fer.ability.name, "Primal Rage", "Ferocity Ability")
        eq(fer.passive.name, "Predator's Thirst", "Ferocity Passive")
    end)

    it("tolerates a spec with only one of the two tiers", function()
        fixtureAllRanks()
        local cun = freshData():GetSpecAbilities("Cunning")
        eq(cun.ability.name, "Master's Call", "Cunning Ability present")
        eq(cun.passive, nil, "no Cunning Passive in the fixture")
    end)

    it("returns nil for an unknown spec and for a nil name", function()
        fixtureAllRanks()
        local Data = freshData()
        eq(Data:GetSpecAbilities("Tenacity"), nil, "no Tenacity rows")
        eq(Data:GetSpecAbilities(nil), nil, "nil name")
    end)
end)

describe("GetAbilityTooltip: family", function()
    it("titles with the family and lists ranks in display order, then the spec block", function()
        fixtureAllRanks()
        local Data = freshFactory()
        local spec = Data:GetAbilityTooltip("family", "Wolf")
        eq(spec.title, "Wolf", "plain family title (Wolf is not an exotic family)")
        local texts = table.concat(lineTexts(spec.lines), "|")
        -- rank headers appear Special -> Bonus -> Exotic -> Exotic Passive regardless
        -- of the fixture's definition order
        truthy(texts:find("Special Ability|.-Bonus Ability|.-Exotic Ability|.-Exotic Passive"),
            "rank headers in RANK_ORDER: " .. texts)
        truthy(texts:find("Spec: Ferocity"), "Wolf's spec sub-block")
        truthy(texts:find("Primal Rage") and texts:find("Predator's Thirst"), "spec abilities listed")
    end)

    it("appends [Exotic] only for a family on ns.Data.IsExoticFamily's roster", function()
        _G.AbilitiesData = {
            -- Chimaera IS an exotic family; Clefthoof carries an Exotic-rank ability
            -- but is NOT on the roster (grandfathered pets aside).
            [38] = { name = "Chimaera",  ranks = { ["Exotic Ability"] = { [92380]  = { name = "Froststorm Breath" } } } },
            [43] = { name = "Clefthoof", ranks = { ["Exotic Ability"] = { [280069] = { name = "Blood of the Rhino" } } } },
        }
        local Data = freshFactory()
        local chim = Data:GetAbilityTooltip("family", "Chimaera",  { noSpec = true })
        truthy(chim.title:find("Chimaera") and chim.title:find("Exotic"), "roster family: " .. chim.title)
        eq(Data:GetAbilityTooltip("family", "Clefthoof", { noSpec = true }).title, "Clefthoof",
            "has an Exotic ability but is not an exotic family")
    end)

    it("drops the spec sub-block when opts.noSpec is set", function()
        fixtureAllRanks()
        local Data = freshFactory()
        local texts = table.concat(lineTexts(Data:GetAbilityTooltip("family", "Wolf", { noSpec = true }).lines), "|")
        eq(texts:find("Spec:") ~= nil, false, "no spec block")
        eq(texts:find("Primal Rage") ~= nil, false, "no spec abilities")
    end)

    it("copies anchor/toplevel passthrough onto the spec", function()
        fixtureAllRanks()
        local Data = freshFactory()
        local spec = Data:GetAbilityTooltip("family", "Wolf", { toplevel = true, anchor = "ANCHOR_BOTTOM" })
        eq(spec.toplevel, true, "toplevel passed through")
        eq(spec.anchor, "ANCHOR_BOTTOM", "anchor passed through")
    end)

    it("returns nil for an unknown family", function()
        fixtureAllRanks()
        eq(freshFactory():GetAbilityTooltip("family", "Nonexistent"), nil, "unknown family")
    end)

    it("places the Basic Ability rank last, after the distinguishing ranks", function()
        _G.AbilitiesData = {
            [1] = { name = "Wolf", ranks = {
                ["Basic Ability"]   = { [17253] = { name = "Bite" } },
                ["Special Ability"] = { [263840] = { name = "Furious Bite" } },
            } },
        }
        local Data = freshFactory()
        local texts = table.concat(lineTexts(Data:GetAbilityTooltip("family", "Wolf", { noSpec = true }).lines), "|")
        truthy(texts:find("Special Ability|.-Basic Ability"),
            "Basic Ability after Special Ability despite the fixture order: " .. texts)
    end)

    it("still renders a rank label that is not in RANK_ORDER (sorts last)", function()
        _G.AbilitiesData = {
            [1] = { name = "Wolf", ranks = {
                ["Special Ability"] = { [11] = { name = "First" } },
                ["Mystery Rank"]    = { [99] = { name = "Last" } },
            } },
        }
        local Data = freshFactory()
        local texts = table.concat(lineTexts(Data:GetAbilityTooltip("family", "Wolf", { noSpec = true }).lines), "|")
        truthy(texts:find("Special Ability|.-Mystery Rank"), "unknown rank kept, after the known one: " .. texts)
    end)
end)

describe("GetAbilityTooltip: spec", function()
    it("titles with the spec, lists its two abilities, then the changeable-hint line", function()
        fixtureAllRanks()
        local Data = freshFactory()
        local spec = Data:GetAbilityTooltip("spec", "Ferocity")
        eq(spec.title, "Spec Abilities", "generic title -- the cursor is already on the spec name")
        local texts = lineTexts(spec.lines)
        eq(#texts, 3, "two ability lines + the hint")
        truthy(texts[1]:find("Primal Rage") and texts[2]:find("Predator's Thirst"), "both spec abilities")
        truthy(texts[3]:find("Stable Master"), "trailing where-to-change hint: " .. texts[3])
    end)

    it("returns nil for a spec with no rows", function()
        fixtureAllRanks()
        eq(freshFactory():GetAbilityTooltip("spec", "Tenacity"), nil, "no Tenacity rows")
    end)
end)

describe("GetAbilityTooltip: pet + unknown kind", function()
    it("delegates 'pet' to PetTooltip.Spec", function()
        _G.AbilitiesData = nil
        local Data = freshFactory()
        local spec = Data:GetAbilityTooltip("pet", {
            name = "Rex", slotID = 1, familyName = "Wolf", displayID = 42,
            abilities = { spec = {}, family = {}, pet = {}, unknown = {} },
        })
        truthy(spec ~= nil and spec.title:find("Rex"), "pet tooltip built via PetTooltip")
    end)

    it("returns nil for an unrecognised kind", function()
        _G.AbilitiesData = nil
        eq(freshFactory():GetAbilityTooltip("bogus", "Wolf"), nil, "unknown kind")
    end)
end)
