-- Tests/spec/abilitiespool_spec.lua
-- The A14 structural-tier abilities pool: family/spec ability spell-ID lists and the
-- specID->specName map are recorded once, account-wide, from live collection, and
-- reconstructed per pet on load instead of persisting a copy on every one of up to
-- 205 pets. See Shared/Data.lua's "Abilities pool" section for the closure argument
-- this whole design leans on.
--
-- GetAbilityName resolves a numeric spell ID via ns.Utils:GetSpellNameCompat, which
-- needs the real WoW C_Spell API this headless harness doesn't have -- so these specs
-- feed the pool string "ability names" directly rather than spell IDs. That's a
-- faithful test double: GetAbilityName's string branch is a straight passthrough, and
-- nothing here is testing spell-ID resolution itself (ExtractPetAbilities already
-- exercises that same shared path, untouched by this task).

local T = ...
local describe, it, eq, truthy, falsy = T.describe, T.it, T.eq, T.truthy, T.falsy

local Addon = dofile("Tests/wow/addon.lua")

local function freshData()
    _G.PetStableManagementDB = nil
    local ns = Addon.namespace()
    Addon.load("PetStableManagement/Shared/Utils.lua", ns)
    Addon.load("PetStableManagement/Shared/Data.lua", ns)
    return ns.Data, ns
end

describe("Abilities pool: record + reconstruct", function()
    it("round-trips family and spec abilities by name", function()
        local Data = freshData()
        Data:RecordAbilitiesObservation("Wolf", "Ferocity", 74, false, {"Furious Howl"}, {"Bite"})

        local abilities = Data:GetPoolAbilities("Wolf", "Ferocity")
        eq(#abilities.pet, 1, "pet bucket count")
        eq(abilities.pet[1], "Furious Howl", "pet bucket entry")
        eq(#abilities.spec, 1, "spec bucket count")
        eq(abilities.spec[1], "Bite", "spec bucket entry")
        eq(#abilities.family, 0, "family bucket stays empty")
        eq(#abilities.unknown, 0, "unknown bucket stays empty")
    end)

    it("is shared across every pet of the same family/spec", function()
        local Data = freshData()
        Data:RecordAbilitiesObservation("Devilsaur", "Tenacity", 81, true, {"Monstrous Bite", "Furious Roar"}, {"Charge"})

        local a = Data:GetPoolAbilities("Devilsaur", "Tenacity")
        local b = Data:GetPoolAbilities("Devilsaur", "Tenacity")
        eq(#a.pet, 2, "first lookup pet count")
        eq(#b.pet, 2, "second lookup pet count")
        eq(a.pet[2], "Furious Roar", "second lookup didn't just reflect the first pet's data by luck")
    end)

    it("dedups a name that appears in both buckets, keeping the first", function()
        local Data = freshData()
        Data:RecordAbilitiesObservation("Wolf", "Ferocity", 74, false, {"Shared Name"}, {"Shared Name"})
        local abilities = Data:GetPoolAbilities("Wolf", "Ferocity")
        eq(#abilities.spec, 1, "spec keeps it (spec bucket is filled first)")
        eq(#abilities.pet, 0, "pet does not duplicate it")
    end)

    it("returns empty buckets, not an error, for a family/spec never observed", function()
        local Data = freshData()
        local abilities = Data:GetPoolAbilities("Nonexistent", "Nonexistent")
        eq(#abilities.pet, 0, "pet")
        eq(#abilities.spec, 0, "spec")
    end)

    it("ignores an empty/nil observation rather than clearing a real one", function()
        local Data = freshData()
        Data:RecordAbilitiesObservation("Wolf", "Ferocity", 74, false, {"Furious Howl"}, {"Bite"})
        Data:RecordAbilitiesObservation("Wolf", "Ferocity", 74, false, {}, nil)

        local abilities = Data:GetPoolAbilities("Wolf", "Ferocity")
        eq(#abilities.pet, 1, "pet bucket survives the empty follow-up observation")
        eq(#abilities.spec, 1, "spec bucket survives the nil follow-up observation")
    end)
end)

describe("Abilities pool: specID", function()
    it("round-trips by specName", function()
        local Data = freshData()
        Data:RecordAbilitiesObservation("Wolf", "Ferocity", 74, false, {}, {})
        eq(Data:GetPoolSpecID("Ferocity"), 74, "specID")
    end)

    it("is nil for a spec never observed", function()
        local Data = freshData()
        eq(Data:GetPoolSpecID("Cunning"), nil, "unseen spec")
    end)
end)

describe("NormalizePetData: pool-backed backfill", function()
    it("backfills specID and abilities on a stripped, loaded-from-disk pet", function()
        local Data = freshData()
        Data:RecordAbilitiesObservation("Wolf", "Ferocity", 74, false, {"Furious Howl"}, {"Bite"})

        local pet = { familyName = "Wolf", specName = "Ferocity" }
        Data:NormalizePetData(pet)

        eq(pet.specID, 74, "specID backfilled")
        eq(#pet.abilities.pet, 1, "pet abilities backfilled")
        eq(#pet.abilities.spec, 1, "spec abilities backfilled")
    end)

    it("does not touch specID/abilities that are already present", function()
        local Data = freshData()
        local existing = { family = {}, spec = {}, pet = {}, unknown = {} }
        local pet = { familyName = "Wolf", specName = "Ferocity", specID = 999, abilities = existing }
        Data:NormalizePetData(pet)

        eq(pet.specID, 999, "specID left alone")
        truthy(pet.abilities == existing, "abilities table left alone (same reference)")
    end)

    it("isExotic prefers a live-observed pool value over the static family table", function()
        local Data = freshData()
        -- Devilsaur is hardcoded exotic in the static EXOTIC_FAMILIES table; the pool
        -- recording a live `false` for it must win anyway -- this is the exact
        -- Clefthoof-style case the pool exists to track (a family whose default
        -- changed, or an account that has only ever seen a non-exotic exception).
        Data:RecordAbilitiesObservation("Devilsaur", "Tenacity", 81, false, {}, {})

        local pet = { familyName = "Devilsaur", specName = "Tenacity" }
        Data:NormalizePetData(pet)
        falsy(pet.isExotic, "pool value (false) wins over the static table's true")
    end)

    it("isExotic falls back to the static table when the pool has no entry", function()
        local Data = freshData()
        local pet = { familyName = "Devilsaur", specName = "Tenacity" }
        Data:NormalizePetData(pet)
        truthy(pet.isExotic, "static EXOTIC_FAMILIES value used")
    end)
end)
