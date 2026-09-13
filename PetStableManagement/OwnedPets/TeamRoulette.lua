-- OwnedPets/TeamRoulette.lua
-- "Team Roulette" for owned pets: turn the current Owned Pets filter into a playable
-- team, with per-slot spec control, reusing the Teams engine (ns.Teams:ApplySlots /
-- SaveTeam) rather than growing a second one.
--
-- The draw (`Roll`) is frame-free and dependency-light so the headless suite can
-- exercise it. `Show` gathers the pool, rolls once, and hands off to the dialog in
-- Shared/Dialogs.lua -- the roll logic stays here, the chrome stays there.

local _, ns = ...

ns.TeamRoulette = ns.TeamRoulette or {}
local TeamRoulette = ns.TeamRoulette

-- The three assignable specs. "Any" is the absence of a template entry (nil), so it is
-- not in this list. Kept as data because the dialog's cycling button walks it.
TeamRoulette.SPECS = { "Ferocity", "Tenacity", "Cunning" }

--------------------------------------------------------------------------------
-- THE DRAW
--------------------------------------------------------------------------------

-- ns.TeamRoulette.Roll(pets, opts) -> slots, report
--   pets   : array of processed PSM pets (already filtered, already this character's)
--   opts   : { slotCount = 5|6,
--              template  = { [slot] = "Ferocity" | "Tenacity" | "Cunning" | nil }, -- nil = Any
--              locked    = { [slot] = slotRecord | "empty" },  -- kept across a re-roll
--              slotOrder = { 1, 6, 2, 3, 4, 5 },  -- fill order; default 1..slotCount
--              priority  = { 1, 6 },              -- these slots fill before any
--                                                 -- non-priority templated slot
--              random    = math.random }              -- injectable for the spec
--   slots  : { [1..slotCount] = ns.Teams:SlotRecord(pet) }  (a slot may be nil if short)
--   report : { filled = n, short = n, coerced = { { slot=, name=, from=, to= } } }
--
-- A spec assignment is a PREFERENCE applied during a roll, never a request to fill:
-- a kept-empty lock always wins, and no pet is ever placed outside this function
-- (see RetuneSlot). A draw serves slots in six phases, each walking `slotOrder`:
--   1. priority + templated   : MATCH  -- take a pet that already has the spec.
--   2. priority + untemplated : ANY    -- take any pet (the fighting slots win the run).
--   3. priority + templated   : COERCE -- still empty: take any pet and overwrite its
--                                        specName with the requirement; the coerced
--                                        entry is recorded and ns.Teams:ApplySlots'
--                                        spec-restore path does the actual
--                                        SetPetSpecialization.
--   4. the rest  + templated  : MATCH
--   5. the rest  + templated  : COERCE
--   6. the rest  + untemplated: ANY
-- For a 6-slot (Beast Mastery + Animal Companion) hunter, Show passes
-- priority = { 1, 6 } -- the active pet and the stabled companion -- so those two
-- fighting slots win the pool in every case, templates on 2-5 be damned.
function TeamRoulette.Roll(pets, opts)
    opts = opts or {}
    local slotCount = opts.slotCount or 5
    local template  = opts.template  or {}
    local locked    = opts.locked    or {}
    local random    = opts.random    or math.random

    local slotOrder = opts.slotOrder
    if not slotOrder then
        slotOrder = {}
        for slot = 1, slotCount do slotOrder[#slotOrder + 1] = slot end
    end

    local isPriority = {}
    for _, slot in ipairs(opts.priority or {}) do isPriority[slot] = true end

    local slots  = {}
    local report = { filled = 0, short = 0, coerced = {} }

    -- `locked[slot]` is a slot record (keep this pet), the string "empty" (keep this
    -- slot deliberately empty), or nil (free to redraw). A kept-empty lock is always
    -- honoured: assigning a spec to a slot is a preference for the next roll, not a
    -- reason to force a pet in here (which could rob the priority 1/6 slots of the pool).
    local function keptEmpty(slot) return locked[slot] == "empty" end

    -- Carried locked slots are kept untouched (and their pets excluded from the pool).
    local excluded = {}
    for slot = 1, slotCount do
        local rec = locked[slot]
        if type(rec) == "table" then
            slots[slot]   = rec
            report.filled = report.filled + 1
            if rec.petNumber then excluded[rec.petNumber] = true end
        end
    end

    local pool, seen = {}, {}
    for _, pet in ipairs(pets or {}) do
        local key = pet.petNumber
        if key ~= nil and not seen[key] and not excluded[key] then
            seen[key]      = true
            pool[#pool + 1] = pet
        end
    end

    local function SpecOf(pet) return pet.specName or pet.specialization end

    -- Remove and return a random pool entry matching `predicate` (or any, if nil).
    local function Take(predicate)
        local candidates = {}
        for i, pet in ipairs(pool) do
            if not predicate or predicate(pet) then candidates[#candidates + 1] = i end
        end
        if #candidates == 0 then return nil end
        local pick = table.remove(pool, candidates[random(1, #candidates)])
        return pick
    end

    -- Fill one slot. mode "match" takes a pet that already has the requirement,
    -- "coerce" takes any pet and rewrites its specName, "any" just takes a pet.
    local function Draw(slot, mode)
        local req = template[slot]
        local pet
        if mode == "match" then
            pet = Take(function(p) return SpecOf(p) == req end)
        else
            pet = Take(nil)
        end
        if not pet then return end
        local rec = ns.Teams:SlotRecord(pet)
        if mode == "coerce" then
            local from = rec.specName
            rec.specName   = req
            report.coerced[#report.coerced + 1] = { slot = slot, name = rec.name, from = from, to = req }
        end
        slots[slot]   = rec
        report.filled = report.filled + 1
    end

    -- One phase: slots selected by `wantPriority` / `wantTemplate`, filled by `mode`.
    local function FillPass(wantPriority, wantTemplate, mode)
        for _, slot in ipairs(slotOrder) do
            if (isPriority[slot] == true) == wantPriority
               and not slots[slot] and not keptEmpty(slot)
               and (template[slot] ~= nil) == wantTemplate then
                Draw(slot, mode)
            end
        end
    end

    -- The six phases: priority slots first (match, then any, then coerce), then the
    -- rest (match, coerce, any). Matches still beat coercion inside each tier.
    FillPass(true,  true,  "match")
    FillPass(true,  false, "any")
    FillPass(true,  true,  "coerce")
    FillPass(false, true,  "match")
    FillPass(false, true,  "coerce")
    FillPass(false, false, "any")

    for slot = 1, slotCount do
        if not slots[slot] and not keptEmpty(slot) then report.short = report.short + 1 end
    end

    return slots, report
end

--------------------------------------------------------------------------------
-- LIVE POOL
--------------------------------------------------------------------------------

-- Whether a pet belongs to an exotic family. Processed pets carry `isExotic`
-- directly; the fallback mirrors ns.Data:GetPetExoticStatus for callers holding a
-- bare pet table (the headless suite builds such pets).
local function PetIsExotic(pet)
    if pet.isExotic ~= nil then return pet.isExotic end
    if ns.Data and ns.Data.IsExoticFamily then return ns.Data.IsExoticFamily(pet.familyName) end
    return false
end

-- The current draw pool: the Owned Pets panel's live filtered list, restricted to
-- pets this hunter owns (a team can only be applied with pets you own), and -- when
-- this hunter is not on Beast Mastery -- free of exotic-family pets, which a
-- non-BM spec cannot summon (see ns.Utils:CanTameExotic). Read fresh on every roll
-- so changing a filter on the panel is reflected without reopening the dialog.
function TeamRoulette:CurrentPool()
    local rd = ns.state.currentRenderData
    local myKey = ns.GetCharacterKey()
    local canExotic = ns.Utils:CanTameExotic()
    local pool = {}
    for _, pet in ipairs((rd and rd.filteredPets) or {}) do
        if pet.tamer == myKey and (canExotic or not PetIsExotic(pet)) then
            pool[#pool + 1] = pet
        end
    end
    return pool
end

local function CoercedIndex(state, slot)
    for i, c in ipairs(state.report and state.report.coerced or {}) do
        if c.slot == slot then return i end
    end
end

local function ClearCoerced(state, slot)
    local i = CoercedIndex(state, slot)
    if i then table.remove(state.report.coerced, i) end
end

-- Recount filled/short after a per-slot edit, so the dialog's warning line stays right.
-- A kept-empty lock suppresses the shortfall: assigning a spec to it is a preference
-- applied on the next roll, not a demand to fill it.
local function Recount(state)
    local filled, short = 0, 0
    for s = 1, state.slotCount do
        if state.slots[s] then
            filled = filled + 1
        elseif state.locked[s] ~= "empty" then
            short = short + 1
        end
    end
    state.report.filled, state.report.short = filled, short
end

--------------------------------------------------------------------------------
-- ENTRY POINT
--------------------------------------------------------------------------------

-- The persisted spec template, defaulted here rather than in Core.lua's DB literal
-- because that literal only seeds a brand-new SavedVariables file.
local function TemplateStore()
    PetStableManagementDB.settings = PetStableManagementDB.settings or {}
    PetStableManagementDB.settings.teamRoulette =
        PetStableManagementDB.settings.teamRoulette or { template = {} }
    PetStableManagementDB.settings.teamRoulette.template =
        PetStableManagementDB.settings.teamRoulette.template or {}
    return PetStableManagementDB.settings.teamRoulette.template
end

-- The persisted locked state (which slots are locked/empty), stored as petNumbers
-- and "empty" strings to avoid serialization issues with full slot records.
local function LockedStore()
    PetStableManagementDB.settings = PetStableManagementDB.settings or {}
    PetStableManagementDB.settings.teamRoulette =
        PetStableManagementDB.settings.teamRoulette or { locked = {} }
    PetStableManagementDB.settings.teamRoulette.locked =
        PetStableManagementDB.settings.teamRoulette.locked or {}
    return PetStableManagementDB.settings.teamRoulette.locked
end

-- Convert persisted locked state (petNumbers) back to runtime format (slot records)
-- by looking them up in the current pool. If a locked pet isn't available, the lock
-- is dropped.
local function RestoreLockedState(lockedStore, pool)
    if not lockedStore then return {} end

    local locked = {}
    local petsByNumber = {}
    for _, pet in ipairs(pool or {}) do
        if pet.petNumber then petsByNumber[pet.petNumber] = pet end
    end

    for slot, value in pairs(lockedStore) do
        if value == "empty" then
            locked[slot] = "empty"
        elseif type(value) == "number" then
            local pet = petsByNumber[value]
            if pet then
                locked[slot] = ns.Teams:SlotRecord(pet)
            end
        end
    end

    return locked
end

function TeamRoulette:Show()
    -- The current filter is renderData.filteredPets; make sure it exists (same
    -- EnsurePetData path every other entry point uses).
    if not (ns.state.currentRenderData and ns.state.currentRenderData.filteredPets) then
        ns.UI:UpdatePanel()
    end

    local pool = self:CurrentPool()
    if #pool == 0 then
        ns.Utils:Msg("WARNING", ns.L("No pets match the current filters."))
        return
    end

    -- A six-slot team needs BOTH: the Beast Mastery spec AND the Animal Companion
    -- talent known (its spell is the live "can fight a companion" signal). Slot 6
    -- itself is always a STABLE slot -- the companion is a stabled pet fighting
    -- beside the active one -- and the team engine (GetCurrentSlots, ApplySlots)
    -- treats slots 1-6 alike, so nothing here may ever classify slot 6 as active.
    local sixSlots = ns.Utils:IsBeastMastery() and ns.Utils:HasAnimalCompanionTalent()
    local slotCount = sixSlots and 6 or 5
    -- With a companion slot, the two fighting slots -- the active pet (1) and the
    -- stabled companion (6) -- MUST win the pool in every case, even against a spec
    -- assigned to some stable-only slot 2-5. Roll fills the `priority` slots first.
    local slotOrder = sixSlots and { 1, 6, 2, 3, 4, 5 } or nil
    local priority  = sixSlots and { 1, 6 } or nil
    local template  = TemplateStore()
    local lockedStore = LockedStore()
    local locked = RestoreLockedState(lockedStore, pool)

    local state = {
        slotCount = slotCount,
        slotOrder = slotOrder,
        priority  = priority,
        template  = template,
        locked    = locked,
        lockedStore = lockedStore,
    }
    state.slots, state.report = TeamRoulette.Roll(pool, {
        slotCount = slotCount,
        template  = template,
        locked    = locked,
        slotOrder = slotOrder,
        priority  = priority,
    })

    ns.Dialogs:ShowTeamRouletteDialog(state)
end

-- Re-roll in place from the live pool: keeps the locked slots and the current
-- template, redraws every other slot.
function TeamRoulette:Reroll(state)
    state.slots, state.report = TeamRoulette.Roll(self:CurrentPool(), {
        slotCount = state.slotCount,
        template  = state.template,
        locked    = state.locked,
        slotOrder = state.slotOrder,
        priority  = state.priority,
    })
    return state
end

-- Retune ONE slot against its spec template, without disturbing the rest of the team
-- (feedback #4). Cycle-clicking a slot's spec is a PREFERENCE, not an assignment:
-- pets are only ever placed by a roll (Show/Reroll), so an empty slot stays empty
-- until the next Re-roll -- never drawing, swapping or stealing a pet here, which
-- could rob the priority 1/6 fighting slots of the pool. A pet already sitting in
-- the slot is retuned in place (its record's specName is rewritten and a coerced
-- entry recorded) so "Apply now" still reflects the chosen spec without waiting for
-- a Re-roll. "Any" drops the requirement and restores the pet's real spec.
function TeamRoulette:RetuneSlot(state, slot)
    state.report         = state.report or { coerced = {} }
    state.report.coerced = state.report.coerced or {}

    local req  = state.template[slot]
    local rec  = state.slots and state.slots[slot]
    local ci   = CoercedIndex(state, slot)
    local real = ci and state.report.coerced[ci].from or (rec and rec.specName)

    ClearCoerced(state, slot)

    if not req then
        if rec and real then rec.specName = real end
        Recount(state); return state
    end

    if rec and real ~= req then
        rec.specName = req
        table.insert(state.report.coerced, { slot = slot, name = rec.name, from = real, to = req })
    end

    Recount(state)
    return state
end

-- Clear a slot: the pet is removed and the slot is free for the next Re-roll to fill
-- (feedback #3). To keep a slot deliberately empty, lock it in the dialog -- that sets
-- locked[slot] = "empty", which Roll honours.
function TeamRoulette:RemoveSlot(state, slot)
    if state.slots then state.slots[slot] = nil end
    state.report = state.report or { coerced = {} }
    ClearCoerced(state, slot)
    Recount(state)
    return state
end

-- Move: swap the pets in two slots (feedback #3). The spec template belongs to the
-- position, not the pet, so each moved pet is reconciled against its new slot's
-- template in place -- coerced if it must be, never swapped out for a different pet.
-- Locks are also swapped by position.
function TeamRoulette:SwapSlots(state, a, b)
    if a == b then return state end
    state.slots  = state.slots or {}
    state.report = state.report or { coerced = {} }
    state.report.coerced = state.report.coerced or {}

    local ia, ib = CoercedIndex(state, a), CoercedIndex(state, b)
    local ca = ia and state.report.coerced[ia]
    local cb = ib and state.report.coerced[ib]

    local kept = {}
    for _, c in ipairs(state.report.coerced) do
        if c.slot ~= a and c.slot ~= b then kept[#kept + 1] = c end
    end
    state.report.coerced = kept

    state.slots[a], state.slots[b] = state.slots[b], state.slots[a]
    if cb then cb.slot = a; table.insert(state.report.coerced, cb) end
    if ca then ca.slot = b; table.insert(state.report.coerced, ca) end

    -- Swap locked state by position, including in the persisted store
    state.locked[a], state.locked[b] = state.locked[b], state.locked[a]
    if state.lockedStore then
        state.lockedStore[a], state.lockedStore[b] = state.lockedStore[b], state.lockedStore[a]
    end

    self:RetuneSlot(state, a)
    self:RetuneSlot(state, b)
    return state
end
