-- Tests/spec/abilitycategory_spec.lua
-- ns.Data:GetAbilityCategory / :GetAbilityIcon, and the abilityList half of
-- RebuildSpecFamilyAndAbilityLists -- the pieces behind the Owned Pets ability
-- filter's category submenu. GetAbilityCategory (not GetAbilityTag -- tried first,
-- dropped: see Filters.lua's InitAbilityDropdown comment) is what groups the
-- dropdown; RebuildSpecFamilyAndAbilityLists is what populates it from the pets
-- actually on the account.

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

-- GetAbilityTooltipLines pulls in the colour/locale tokens the plain data helpers
-- don't touch.
local function freshDataWithTokens()
    _G.PetStableManagementDB = nil
    local ns = Addon.namespace()
    Addon.load("PetStableManagement/Shared/Locale.lua", ns)
    Addon.load("PetStableManagement/Shared/Config.lua", ns)
    Addon.load("PetStableManagement/UI/Theme.lua", ns)
    Addon.load("PetStableManagement/Shared/Utils.lua", ns)
    Addon.load("PetStableManagement/Shared/Data.lua", ns)
    return ns.Data, ns
end

-- Flatten a PSM.Tooltip lines array to its text, dropping blank spacers.
local function lineTexts(lines)
    local out = {}
    for _, l in ipairs(lines) do
        local text = type(l) == "table" and l.text or l
        if text and text ~= " " then out[#out + 1] = text end
    end
    return out
end

describe("GetAbilityCategory", function()
    it("returns the category AbilitiesData carries for a known ability name", function()
        _G.AbilitiesData = {
            [1] = { name = "Wolf", ranks = { ["Special Ability"] = {
                [111] = { name = "Furious Howl", category = "Enemy movement reduction" },
            } } },
        }
        local Data = freshData()
        eq(Data:GetAbilityCategory("Furious Howl"), "Enemy movement reduction", "known ability")
    end)

    it("returns Other for a name AbilitiesData doesn't carry", function()
        _G.AbilitiesData = {
            [1] = { name = "Wolf", ranks = { ["Special Ability"] = {
                [111] = { name = "Furious Howl", category = "Enemy movement reduction" },
            } } },
        }
        local Data = freshData()
        eq(Data:GetAbilityCategory("Nonexistent Ability"), "Other", "unknown ability")
    end)

    it("returns Other, not an error, when AbilitiesData is entirely absent", function()
        _G.AbilitiesData = nil
        local Data = freshData()
        eq(Data:GetAbilityCategory("Anything"), "Other", "no data loaded")
    end)

    it("falls back to Other for an entry with no category field of its own", function()
        _G.AbilitiesData = {
            [1] = { name = "Wolf", ranks = { ["Special Ability"] = {
                [111] = { name = "Uncategorized Ability" },
            } } },
        }
        local Data = freshData()
        eq(Data:GetAbilityCategory("Uncategorized Ability"), "Other", "no category on the entry itself")
    end)

    it("keeps the first category seen when two families disagree (shouldn't happen, but doesn't error)", function()
        _G.AbilitiesData = {
            [1] = { name = "Wolf", ranks = { ["Special Ability"] = {
                [111] = { name = "Shared Name", category = "Enemy movement reduction" },
            } } },
            [2] = { name = "Cat",  ranks = { ["Special Ability"] = {
                [222] = { name = "Shared Name", category = "Pet dodge" },
            } } },
        }
        local Data = freshData()
        local cat = Data:GetAbilityCategory("Shared Name")
        truthy(cat == "Enemy movement reduction" or cat == "Pet dodge",
            "one of the two, deterministically (first pairs() hit wins, not both)")
    end)
end)

describe("GetAbilitySource", function()
    it("returns the granting families, sorted and deduped", function()
        _G.AbilitiesData = {
            [2] = { name = "Cat",  ranks = { ["Special Ability"] = {
                [111] = { name = "Growl", category = "Threat" },
            } } },
            [1] = { name = "Wolf", ranks = {
                ["Special Ability"] = { [111] = { name = "Growl" } },
                ["Bonus Ability"]   = { [111] = { name = "Growl" } },  -- same family twice
            } },
        }
        local Data = freshData()
        local families, specTier, rank = Data:GetAbilitySource("Growl")
        eq(table.concat(families, ","), "Cat,Wolf", "sorted, each family once")
        eq(specTier, nil, "not a spec ability")
        eq(rank, "Special Ability", "first rank seen")
    end)

    it("reports the spec tier for a synthetic Spec-family ability", function()
        _G.AbilitiesData = {
            ["Spec"] = { name = "Spec abilities", ranks = { ["Cunning Ability"] = {
                [272682] = { name = "Master's Call", category = "Ally movement impairing removal" },
            } } },
        }
        local Data = freshData()
        local families, specTier = Data:GetAbilitySource("Master's Call")
        eq(#families, 0, "no real family")
        eq(specTier, "Cunning Ability", "the spec tier rank name")
    end)

    it("returns nil for a name AbilitiesData doesn't carry", function()
        _G.AbilitiesData = nil
        local Data = freshData()
        eq(Data:GetAbilitySource("Anything"), nil, "no data loaded")
    end)
end)

describe("GetAbilityTooltipLines", function()
    it("lists rank then the granting families", function()
        _G.AbilitiesData = {
            [1] = { name = "Wolf", ranks = { ["Special Ability"] = {
                [111] = { name = "Growl" },
            } } },
            [2] = { name = "Cat",  ranks = { ["Special Ability"] = {
                [111] = { name = "Growl" },
            } } },
        }
        local Data = freshDataWithTokens()
        local texts = lineTexts(Data:GetAbilityTooltipLines("Growl"))
        eq(table.concat(texts, "|"), "Special Ability|Available from:|Cat|Wolf",
            "rank line, header, families sorted")
    end)

    it("names the spec instead of families for a spec ability", function()
        _G.AbilitiesData = {
            ["Spec"] = { name = "Spec abilities", ranks = { ["Cunning Ability"] = {
                [272682] = { name = "Master's Call" },
            } } },
        }
        local Data = freshDataWithTokens()
        local texts = lineTexts(Data:GetAbilityTooltipLines("Master's Call"))
        eq(table.concat(texts, "|"), "Cunning Ability|Available from:|Any pet with Cunning spec",
            "spec tier stripped to the bare spec name")
    end)

    it("returns an empty table for a name AbilitiesData doesn't carry", function()
        _G.AbilitiesData = nil
        local Data = freshDataWithTokens()
        eq(#Data:GetAbilityTooltipLines("Anything"), 0, "no lines, no error")
    end)
end)

describe("GetAbilityIcon", function()
    -- AbilitiesData no longer stores an icon per ability; GetAbilityIcon derives the
    -- texture fileID from the spell ID via Utils:GetSpellTextureCompat -> C_Spell.
    -- The real API maps spellID -> numeric fileID; this stub models that with an
    -- offset so the test can assert the ID was threaded through. Core.lua (which sets
    -- the real ns.C_Spell) isn't loaded here, so the spec injects it.
    local function withSpellTexture(ns, fn)
        ns.C_Spell = { GetSpellTexture = fn }
    end

    it("derives the texture fileID from the ability's spell ID", function()
        _G.AbilitiesData = {
            [1] = { name = "Wolf", ranks = { ["Special Ability"] = {
                [111] = { name = "Furious Howl" },
            } } },
        }
        local Data, ns = freshData()
        withSpellTexture(ns, function(id) return id and 800000 + id or nil end)
        eq(Data:GetAbilityIcon("Furious Howl"), 800111, "fileID for spell 111")
    end)

    it("returns nil for a name AbilitiesData doesn't carry (no spell ID to resolve)", function()
        _G.AbilitiesData = nil
        local Data, ns = freshData()
        withSpellTexture(ns, function(id) return id and 800000 + id or nil end)
        eq(Data:GetAbilityIcon("Anything"), nil, "no data loaded")
    end)

    it("returns nil when the client can't resolve the spell ID", function()
        _G.AbilitiesData = {
            [1] = { name = "Wolf", ranks = { ["Special Ability"] = {
                [111] = { name = "Furious Howl" },
            } } },
        }
        local Data, ns = freshData()
        withSpellTexture(ns, function() return nil end)
        eq(Data:GetAbilityIcon("Furious Howl"), nil, "known ability, unresolvable texture")
    end)
end)

describe("RebuildSpecFamilyAndAbilityLists: abilityList", function()
    local function petWithAbilities(spec, family, abilities)
        return { specName = spec, familyName = family, abilities = abilities }
    end

    it("collects distinct ability names across every bucket, sorted", function()
        _G.AbilitiesData = nil
        local Data, ns = freshData()
        ns.state = { stablePets = {
            petWithAbilities("Ferocity", "Wolf", { spec = {"Bite"}, family = {"Howl"}, pet = {}, unknown = {} }),
            petWithAbilities("Cunning",  "Cat",  { spec = {"Prowl"}, family = {}, pet = {"Claw"}, unknown = {} }),
        } }

        Data:RebuildSpecFamilyAndAbilityLists()
        eq(table.concat(ns.state.abilityList, ","), "Bite,Claw,Howl,Prowl", "sorted, all buckets covered")
    end)

    it("dedups an ability name that appears on more than one pet", function()
        _G.AbilitiesData = nil
        local Data, ns = freshData()
        ns.state = { stablePets = {
            petWithAbilities("Ferocity", "Wolf", { spec = {"Bite"}, family = {}, pet = {}, unknown = {} }),
            petWithAbilities("Ferocity", "Wolf", { spec = {"Bite"}, family = {}, pet = {}, unknown = {} }),
        } }

        Data:RebuildSpecFamilyAndAbilityLists()
        eq(#ns.state.abilityList, 1, "one entry, not two")
        eq(ns.state.abilityList[1], "Bite", "the shared name")
    end)

    it("tolerates a pet with no abilities table at all", function()
        _G.AbilitiesData = nil
        local Data, ns = freshData()
        ns.state = { stablePets = { { specName = "Ferocity", familyName = "Wolf" } } }

        Data:RebuildSpecFamilyAndAbilityLists()
        eq(#ns.state.abilityList, 0, "no abilities, no error")
    end)
end)
