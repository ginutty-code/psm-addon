-- tests/spec/teamroulette_spec.lua
-- The Team Roulette draw (ns.TeamRoulette.Roll) and its per-slot editors, with an
-- injected `random` so they are deterministic and a hand-built pet list. Only the pure
-- logic is covered here; Show builds frames and talks to the stable, so it stays in-game.

local T = ...
local describe, it, eq, truthy = T.describe, T.it, T.eq, T.truthy

dofile("tests/wow/stubs.lua").install()
local Addon = dofile("tests/wow/addon.lua")

local ns = Addon.load("PetStableManagement/Shared/Locale.lua")
Addon.load("PetStableManagement/Shared/Config.lua", ns)
Addon.load("PetStableManagement/Shared/Log.lua", ns)
Addon.load("PetStableManagement/Shared/Utils.lua", ns)
ns.GetCharacterKey = function() return "Tester-Realm" end
ns.Data  = { ExtractPetAbilities = function() return {} end }
ns.state = { currentRenderData = { filteredPets = {} } }
Addon.load("PetStableManagement/OwnedPets/TeamsData.lua", ns)
Addon.load("PetStableManagement/OwnedPets/TeamRoulette.lua", ns)

local Roll = ns.TeamRoulette.Roll

-- Point ns.TeamRoulette:CurrentPool at a fixed list.
local function setPool(pets) ns.state.currentRenderData.filteredPets = pets end

-- A deterministic stand-in for math.random(1, n): always picks the first candidate.
local function firstPick(_, _) return 1 end

local function pet(number, spec)
    return {
        petNumber  = number,
        name       = "Pet" .. number,
        specName   = spec,
        familyName = "Wolf",
        displayID  = 1000 + number,
        level      = 25,
        tamer      = "Tester-Realm",
        abilities  = {},
    }
end

describe("TeamRoulette.Roll -- basics", function()
    it("fills every slot when the pool is large enough", function()
        local pets = { pet(1, "Ferocity"), pet(2, "Tenacity"), pet(3, "Cunning"),
                       pet(4, "Ferocity"), pet(5, "Tenacity"), pet(6, "Cunning") }
        local slots, report = Roll(pets, { slotCount = 5, random = firstPick })
        eq(report.filled, 5, "five filled")
        eq(report.short, 0, "none short")
        for s = 1, 5 do truthy(slots[s], "slot " .. s .. " has a pet") end
    end)

    it("never places the same pet twice", function()
        local pets = { pet(1, "Ferocity"), pet(2, "Tenacity"), pet(3, "Cunning"),
                       pet(4, "Ferocity"), pet(5, "Tenacity") }
        local slots = Roll(pets, { slotCount = 5, random = firstPick })
        local seen = {}
        for s = 1, 5 do
            local n = slots[s].petNumber
            truthy(not seen[n], "petNumber " .. tostring(n) .. " appears once")
            seen[n] = true
        end
    end)

    it("fills what it can and reports the shortfall when the pool is too small", function()
        local pets = { pet(1, "Ferocity"), pet(2, "Tenacity") }
        local slots, report = Roll(pets, { slotCount = 5, random = firstPick })
        eq(report.filled, 2, "two filled")
        eq(report.short, 3, "three short")
        eq(slots[3], nil, "slot 3 left empty")
    end)

    it("honours slotCount 5 vs 6", function()
        local pets = {}
        for i = 1, 8 do pets[i] = pet(i, "Ferocity") end
        local _, r5 = Roll(pets, { slotCount = 5, random = firstPick })
        local _, r6 = Roll(pets, { slotCount = 6, random = firstPick })
        eq(r5.filled, 5, "5")
        eq(r6.filled, 6, "6")
    end)
end)

describe("TeamRoulette.Roll -- spec template", function()
    it("takes a pet that already has the required spec, with no coercion", function()
        local pets = { pet(1, "Cunning"), pet(2, "Tenacity"), pet(3, "Ferocity") }
        local slots, report = Roll(pets, {
            slotCount = 3,
            template  = { [1] = "Ferocity" },
            random    = firstPick,
        })
        eq(slots[1].specName, "Ferocity", "slot 1 is Ferocity")
        eq(slots[1].petNumber, 3, "and it is the pet that already had it")
        eq(#report.coerced, 0, "nothing coerced")
    end)

    it("coerces only when no matching pet is left", function()
        local pets = { pet(1, "Cunning"), pet(2, "Tenacity") }
        local slots, report = Roll(pets, {
            slotCount = 2,
            template  = { [1] = "Ferocity" },
            random    = firstPick,
        })
        eq(slots[1].specName, "Ferocity", "slot record carries the required spec")
        eq(#report.coerced, 1, "one coerced entry")
        eq(report.coerced[1].to, "Ferocity", "coerced to Ferocity")
        eq(report.coerced[1].from, "Cunning", "from the pet's real spec")
        eq(report.coerced[1].name, slots[1].name, "names the coerced pet")
    end)

    it("prefers the match pass over coercion when both are possible", function()
        -- Two templated Ferocity slots, one real Ferocity pet: slot 1 matches, slot 2
        -- coerces. Most-constrained-first must not let an Any slot steal the match.
        local pets = { pet(1, "Ferocity"), pet(2, "Cunning"), pet(3, "Tenacity") }
        local slots, report = Roll(pets, {
            slotCount = 3,
            template  = { [1] = "Ferocity", [2] = "Ferocity" },
            random    = firstPick,
        })
        eq(slots[1].petNumber, 1, "slot 1 took the real Ferocity pet")
        eq(#report.coerced, 1, "slot 2 coerced")
        eq(report.coerced[1].to, "Ferocity", "to Ferocity")
    end)
end)

describe("TeamRoulette.Roll -- locking", function()
    it("keeps locked slots and excludes their pets from the new draw", function()
        local loc = ns.Teams:SlotRecord(pet(9, "Ferocity"))
        local pets = { pet(9, "Ferocity"), pet(1, "Tenacity"), pet(2, "Cunning") }
        local slots, report = Roll(pets, {
            slotCount = 3,
            locked    = { [1] = loc },
            random    = firstPick,
        })
        eq(slots[1].petNumber, 9, "locked pet stayed in slot 1")
        for s = 2, 3 do
            truthy(slots[s].petNumber ~= 9, "pet 9 not redrawn into slot " .. s)
        end
        eq(report.filled, 3, "locked slot counts as filled")
    end)

    it("leaves a slot marked \"empty\" empty and does not count it short", function()
        local pets = { pet(1, "Ferocity"), pet(2, "Tenacity"), pet(3, "Cunning") }
        local slots, report = Roll(pets, {
            slotCount = 3,
            locked    = { [2] = "empty" },
            random    = firstPick,
        })
        eq(slots[2], nil, "slot 2 stays empty")
        eq(report.short, 0, "a deliberate empty is not a shortfall")
        truthy(slots[1] and slots[3], "the other slots still fill")
    end)
end)

describe("TeamRoulette:RetuneSlot -- per-slot spec change", function()
    local function baseState()
        return {
            slotCount = 3,
            template  = {},
            locked    = {},
            slots     = {
                [1] = ns.Teams:SlotRecord(pet(1, "Ferocity")),
                [2] = ns.Teams:SlotRecord(pet(2, "Tenacity")),
                [3] = ns.Teams:SlotRecord(pet(3, "Cunning")),
            },
            report    = { filled = 3, short = 0, coerced = {} },
        }
    end

    it("retunes the slot's own pet in place -- assignment waits for the re-roll", function()
        setPool({ pet(1, "Ferocity"), pet(2, "Tenacity"), pet(3, "Cunning"), pet(4, "Cunning") })
        local s = baseState()
        s.template[1] = "Cunning"
        ns.TeamRoulette:RetuneSlot(s, 1)
        eq(s.slots[1].petNumber, 1, "the slot's pet stays -- no fresh pet is drawn")
        eq(s.slots[1].specName, "Cunning", "its spec is retuned in place")
        eq(s.slots[2].petNumber, 2, "slot 2 untouched")
        eq(s.slots[3].petNumber, 3, "slot 3 untouched")
        eq(#s.report.coerced, 1, "one coercion recorded")
        eq(s.report.coerced[1].from, "Ferocity", "from the pet's real spec")
    end)

    it("keeps the slot's pet and coerces it when nothing in the pool matches", function()
        setPool({ pet(1, "Ferocity"), pet(2, "Tenacity"), pet(3, "Cunning") })
        local s = baseState()
        s.template[3] = "Ferocity"
        ns.TeamRoulette:RetuneSlot(s, 3)
        eq(s.slots[3].petNumber, 3, "same pet stays in slot 3")
        eq(s.slots[3].specName, "Ferocity", "its slot record carries the requirement")
        eq(#s.report.coerced, 1, "one coerced entry")
        eq(s.report.coerced[1].slot, 3, "keyed to slot 3")
        eq(s.report.coerced[1].from, "Cunning", "from its real spec")
    end)

    it("restores the real spec and clears the coercion when set back to Any", function()
        setPool({ pet(1, "Ferocity"), pet(2, "Tenacity"), pet(3, "Cunning") })
        local s = baseState()
        s.template[3] = "Ferocity"
        ns.TeamRoulette:RetuneSlot(s, 3)         -- coerce
        s.template[3] = nil
        ns.TeamRoulette:RetuneSlot(s, 3)         -- back to Any
        eq(s.slots[3].specName, "Cunning", "real spec restored")
        eq(#s.report.coerced, 0, "coercion cleared")
    end)
end)

describe("TeamRoulette:RemoveSlot / SwapSlots -- manual editing", function()
    local function baseState()
        return {
            slotCount = 3,
            template  = {},
            locked    = {},
            slots     = {
                [1] = ns.Teams:SlotRecord(pet(1, "Ferocity")),
                [2] = ns.Teams:SlotRecord(pet(2, "Tenacity")),
                [3] = ns.Teams:SlotRecord(pet(3, "Cunning")),
            },
            report    = { filled = 3, short = 0, coerced = {} },
        }
    end

    it("RemoveSlot empties the slot and counts it short", function()
        local s = baseState()
        ns.TeamRoulette:RemoveSlot(s, 2)
        eq(s.slots[2], nil, "slot 2 cleared")
        eq(s.report.short, 1, "and it is a shortfall until re-rolled")
        eq(s.report.filled, 2, "filled recomputed")
    end)

    it("SwapSlots exchanges two pets without redrawing", function()
        local s = baseState()
        ns.TeamRoulette:SwapSlots(s, 1, 3)
        eq(s.slots[1].petNumber, 3, "pet 3 moved to slot 1")
        eq(s.slots[3].petNumber, 1, "pet 1 moved to slot 3")
        eq(s.slots[2].petNumber, 2, "slot 2 untouched")
    end)

    it("SwapSlots coerces a moved pet to its new slot's template, in place", function()
        local s = baseState()
        s.template[1] = "Ferocity"           -- slot 1 wants Ferocity
        ns.TeamRoulette:SwapSlots(s, 1, 3)     -- Cunning pet 3 lands in slot 1
        eq(s.slots[1].petNumber, 3, "the move stands -- no fresh pet pulled in")
        eq(s.slots[1].specName, "Ferocity", "coerced to the slot's requirement")
        local co
        for _, c in ipairs(s.report.coerced) do if c.slot == 1 then co = c end end
        eq(co and co.from, "Cunning", "coercion recorded from its real spec")
    end)

    it("SwapSlots into an empty slot moves the pet and leaves the source empty", function()
        local s = baseState()
        s.slots[2] = nil
        ns.TeamRoulette:SwapSlots(s, 1, 2)
        eq(s.slots[2].petNumber, 1, "pet moved into the empty slot")
        eq(s.slots[1], nil, "source is now empty")
    end)

    it("SwapSlots swaps locked state by position", function()
        local s = baseState()
        local lockedStore = {}
        s.locked[1] = s.slots[1]
        s.locked[3] = "empty"
        s.lockedStore = lockedStore
        lockedStore[1] = 1
        lockedStore[3] = "empty"

        ns.TeamRoulette:SwapSlots(s, 1, 3)

        eq(s.lockedStore[1], "empty", "locked store slot 1 is now empty")
        eq(s.lockedStore[3], 1, "locked store slot 3 is now petNumber 1")
        eq(s.locked[3].petNumber, 1, "locked state slot 3 has pet 1")
    end)
end)

describe("TeamRoulette.Roll -- slotOrder (BM fills 1 then 6)", function()
    it("keeps the default 1..slotCount order when no slotOrder is given", function()
        local pets = { pet(1, "Ferocity"), pet(2, "Tenacity") }
        local slots = Roll(pets, { slotCount = 6, random = firstPick })
        truthy(slots[1] and slots[2], "slots 1 and 2 filled")
        eq(slots[6], nil, "slot 6 untouched by the default order")
    end)

    it("fills the active slots 1 and 6 first for a six-slot (BM) hunter", function()
        local pets = { pet(1, "Ferocity"), pet(2, "Tenacity") }
        local slots, report = Roll(pets, {
            slotCount = 6,
            slotOrder = { 1, 6, 2, 3, 4, 5 },
            random    = firstPick,
        })
        truthy(slots[1], "slot 1 filled")
        truthy(slots[6], "slot 6 filled")
        eq(slots[2], nil, "stable-only slot 2 left short")
        eq(report.filled, 2, "both pets placed")
    end)

    it("walks the slotOrder in every pass, so templates key off it too", function()
        -- A Ferocity pet placed into slot 6's template only happens if pass 1/2
        -- visits slot 6 before the "Any" slots eat the pool.
        local pets = { pet(1, "Cunning"), pet(2, "Ferocity") }
        local slots = Roll(pets, {
            slotCount = 6,
            slotOrder = { 1, 6, 2, 3, 4, 5 },
            template  = { [6] = "Ferocity" },
            random    = firstPick,
        })
        eq(slots[6].petNumber, 2, "the Ferocity pet landed in templated slot 6")
        eq(slots[6].specName, "Ferocity", "as its spec")
        eq(slots[1].petNumber, 1, "slot 1 took the remaining pet")
    end)

    it("priority slots win a short draw even when a slot 2-5 has a spec assigned", function()
        -- The conflict: a templated stable-only slot must not eat the pool before the
        -- fighting slots 1 and 6 get their pets.
        local pets = { pet(1, "Ferocity"), pet(2, "Tenacity") }
        local slots, report = Roll(pets, {
            slotCount = 6,
            slotOrder = { 1, 6, 2, 3, 4, 5 },
            priority  = { 1, 6 },
            template  = { [2] = "Ferocity" },
            random    = firstPick,
        })
        truthy(slots[1], "slot 1 filled first")
        truthy(slots[6], "slot 6 filled second")
        eq(slots[2], nil, "the templated slot 2 is left short, not the fighting slots")
        eq(report.filled, 2, "both pets placed")
    end)

    it("a templated priority slot still coerce-fills in a short draw", function()
        -- Inside the priority set the old rule holds: a BM's slot 1 wants Ferocity,
        -- no pet has it, and the pool is tiny -- slot 1 gets its pet coerced anyway.
        local pets = { pet(1, "Cunning"), pet(2, "Tenacity") }
        local slots, report = Roll(pets, {
            slotCount = 6,
            slotOrder = { 1, 6, 2, 3, 4, 5 },
            priority  = { 1, 6 },
            template  = { [1] = "Ferocity" },
            random    = firstPick,
        })
        truthy(slots[1], "slot 1 filled")
        eq(slots[1].specName, "Ferocity", "coerced to the requirement")
        truthy(slots[6], "slot 6 filled too")
        local co
        for _, c in ipairs(report.coerced) do if c.slot == 1 then co = c end end
        truthy(co, "the slot 1 coercion is recorded")
    end)
end)

describe("TeamRoulette.Roll -- template is a preference, not a filling request", function()
    it("a kept-empty lock always wins, even when a spec is assigned to the slot", function()
        local pets = { pet(1, "Cunning") }
        local slots, report = Roll(pets, {
            slotCount = 1,
            locked    = { [1] = "empty" },
            template  = { [1] = "Ferocity" },
            random    = firstPick,
        })
        eq(slots[1], nil, "the empty lock is honoured -- no pet is forced in")
        eq(report.short, 0, "a deliberate empty is not a shortfall")
    end)
end)

describe("TeamRoulette:CurrentPool -- exotic filtering by hunter spec", function()
    local originalCanTameExotic = ns.Utils.CanTameExotic

    local function exoticPet(number, spec)
        local p = pet(number, spec)
        p.isExotic = true
        p.familyName = "Clefthoof"
        return p
    end

    it("drops exotic-family pets when this hunter cannot tame exotics", function()
        ns.Utils.CanTameExotic = function() return false end
        setPool({ exoticPet(1, "Ferocity"), pet(2, "Tenacity"), exoticPet(3, "Cunning") })
        local pool = ns.TeamRoulette:CurrentPool()
        eq(#pool, 1, "only the non-exotic pet survives")
        eq(pool[1].petNumber, 2, "and it is pet 2")
    end)

    it("keeps exotic-family pets for a Beast Mastery hunter", function()
        ns.Utils.CanTameExotic = function() return true end
        setPool({ exoticPet(1, "Ferocity"), pet(2, "Tenacity") })
        local pool = ns.TeamRoulette:CurrentPool()
        eq(#pool, 2, "both pets survive")
    end)

    ns.Utils.CanTameExotic = originalCanTameExotic
end)

describe("TeamRoulette:RetuneSlot -- empty slots wait for the next roll", function()
    local function dryState()
        return {
            slotCount = 3,
            template  = {},
            locked    = {},
            slots     = {
                -- slot 1 empty on purpose: the spec is assigned to an empty slot.
                [2] = ns.Teams:SlotRecord(pet(2, "Tenacity")),
                [3] = ns.Teams:SlotRecord(pet(3, "Cunning")),
            },
            report    = { filled = 2, short = 1, coerced = {} },
        }
    end

    it("leaves an empty slot empty when a spec is assigned, pool pets untouched", function()
        setPool({ pet(4, "Ferocity"), pet(5, "Cunning") })
        local s = dryState()
        s.template[1] = "Ferocity"
        ns.TeamRoulette:RetuneSlot(s, 1)
        eq(s.slots[1], nil, "the empty slot stays empty -- only a roll assigns pets")
        eq(s.slots[2].petNumber, 2, "existing placements untouched")
        eq(s.slots[3].petNumber, 3, "existing placements untouched")
        eq(#s.report.coerced, 0, "no coercion")
    end)

    it("never steals from another slot when the pool is dry", function()
        setPool({})
        local s = dryState()
        s.template[1] = "Ferocity"
        ns.TeamRoulette:RetuneSlot(s, 1)
        eq(s.slots[1], nil, "the empty slot stays empty")
        eq(s.slots[2].petNumber, 2, "slot 2's pet is not stolen")
        eq(s.slots[3].petNumber, 3, "slot 3's pet is not stolen")
    end)

    it("still coerces the pet already in the slot, so Apply reflects the choice", function()
        setPool({})
        local s = dryState()
        s.template[2] = "Ferocity"
        ns.TeamRoulette:RetuneSlot(s, 2)
        eq(s.slots[2].petNumber, 2, "same pet in place")
        eq(s.slots[2].specName, "Ferocity", "retuned in place")
        eq(#s.report.coerced, 1, "one coercion recorded")
    end)
end)
