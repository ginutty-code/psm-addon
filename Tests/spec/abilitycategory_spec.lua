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

describe("GetAbilityIcon", function()
    it("returns the icon AbilitiesData carries", function()
        _G.AbilitiesData = {
            [1] = { name = "Wolf", ranks = { ["Special Ability"] = {
                [111] = { name = "Furious Howl", icon = "ability_hunter_pet_wolf" },
            } } },
        }
        local Data = freshData()
        eq(Data:GetAbilityIcon("Furious Howl"), "ability_hunter_pet_wolf", "known ability")
    end)

    it("returns nil for a name AbilitiesData doesn't carry", function()
        _G.AbilitiesData = nil
        local Data = freshData()
        eq(Data:GetAbilityIcon("Anything"), nil, "no data loaded")
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
