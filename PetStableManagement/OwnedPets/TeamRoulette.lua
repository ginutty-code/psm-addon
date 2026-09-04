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
--              template  = { [slot] = "Ferocity"|"Tenacity"|"Cunning"|nil },  -- nil = Any
--              locked    = { [slot] = slotRecord | "empty" },  -- kept across a re-roll
--              random    = math.random }              -- injectable for the spec
--   slots  : { [1..slotCount] = ns.Teams:SlotRecord(pet) }  (a slot may be nil if short)
--   report : { filled = n, short = n, coerced = { { slot=, name=, from=, to= } } }
--
-- Draw order is most-constrained-first, so a templated slot never loses its only
-- candidate to an "Any" slot:
--   Pass 1 (match)  -- templated slots take a pet that already has the required spec.
--   Pass 2 (coerce) -- templated slots still empty take any pet; its slot record's
--                      specName is overwritten with the requirement and a coerced entry
--                      is recorded. ns.Teams:ApplySlots' existing spec-restore path does
--                      the actual SetPetSpecialization.
--   Pass 3 (any)    -- untemplated slots take whatever is left.
function TeamRoulette.Roll(pets, opts)
    opts = opts or {}
    local slotCount = opts.slotCount or 5
    local template  = opts.template  or {}
    local locked    = opts.locked    or {}
    local random    = opts.random    or math.random

    local slots  = {}
    local report = { filled = 0, short = 0, coerced = {} }

    -- `locked[slot]` is a slot record (keep this pet), the string "empty" (keep this
    -- slot deliberately empty), or nil (free to redraw).
    local function keptEmpty(slot) return locked[slot] == "empty" end

    -- Locked slots are carried through untouched.
    for slot = 1, slotCount do
        if type(locked[slot]) == "table" then
            slots[slot]   = locked[slot]
            report.filled = report.filled + 1
        end
    end

    -- Pool: dedupe by petNumber, drop anything sitting in a locked slot. A pet with no
    -- petNumber can be neither deduped nor displaced by the apply path, so it is skipped.
    local excluded = {}
    for slot = 1, slotCount do
        local rec = slots[slot]
        if type(rec) == "table" and rec.petNumber then excluded[rec.petNumber] = true end
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

    -- Pass 1 -- match
    for slot = 1, slotCount do
        if not slots[slot] and not keptEmpty(slot) and template[slot] then
            local req = template[slot]
            local pet = Take(function(p) return SpecOf(p) == req end)
            if pet then
                slots[slot]   = ns.Teams:SlotRecord(pet)
                report.filled = report.filled + 1
            end
        end
    end

    -- Pass 2 -- coerce
    for slot = 1, slotCount do
        if not slots[slot] and not keptEmpty(slot) and template[slot] then
            local req = template[slot]
            local pet = Take(nil)
            if pet then
                local rec  = ns.Teams:SlotRecord(pet)
                local from = rec.specName
                rec.specName   = req
                slots[slot]    = rec
                report.filled  = report.filled + 1
                report.coerced[#report.coerced + 1] = { slot = slot, name = rec.name, from = from, to = req }
            end
        end
    end

    -- Pass 3 -- any
    for slot = 1, slotCount do
        if not slots[slot] and not keptEmpty(slot) and not template[slot] then
            local pet = Take(nil)
            if pet then
                slots[slot]   = ns.Teams:SlotRecord(pet)
                report.filled = report.filled + 1
            end
        end
    end

    for slot = 1, slotCount do
        if not slots[slot] and not keptEmpty(slot) then report.short = report.short + 1 end
    end

    return slots, report
end

--------------------------------------------------------------------------------
-- LIVE POOL
--------------------------------------------------------------------------------

local function SpecOf(pet) return pet.specName or pet.specialization end

-- The current draw pool: the Owned Pets panel's live filtered list, restricted to
-- pets this hunter owns (a team can only be applied with pets you own). Read fresh on
-- every roll so changing a filter on the panel is reflected without reopening the
-- dialog.
function TeamRoulette:CurrentPool()
    local rd = ns.state.currentRenderData
    local myKey = ns.GetCharacterKey()
    local pool = {}
    for _, pet in ipairs((rd and rd.filteredPets) or {}) do
        if pet.tamer == myKey then pool[#pool + 1] = pet end
    end
    return pool
end

-- petNumbers already placed in slots other than `exceptSlot`, so a per-slot redraw
-- doesn't pull in a pet that is already on the team.
local function PlacedPetNumbers(state, exceptSlot)
    local placed = {}
    for s = 1, state.slotCount do
        if s ~= exceptSlot then
            local rec = state.slots and state.slots[s]
            if rec and rec.petNumber then placed[rec.petNumber] = true end
        end
    end
    return placed
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

    local slotCount = ns.Utils:HasAnimalCompanionTalent() and 6 or 5
    local template  = TemplateStore()
    local lockedStore = LockedStore()
    local locked = RestoreLockedState(lockedStore, pool)

    local state = {
        slotCount = slotCount,
        template  = template,
        locked    = locked,
        lockedStore = lockedStore,
    }
    state.slots, state.report = TeamRoulette.Roll(pool, {
        slotCount = slotCount,
        template  = template,
        locked    = locked,
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
    })
    return state
end

-- Retune ONE slot against its spec template, without disturbing the rest of the team
-- (feedback #4). `keepPet` decides what happens on a mismatch:
--   keepPet = false (a spec-cycle click)  -- prefer a fresh pet that already has the
--             new spec; only if none is free, keep the current pet and coerce it, or
--             for an empty slot draw any pet and coerce.
--   keepPet = true  (a manual move)       -- never pull a different pet; coerce the
--             pet that is already in the slot, or leave it as-is / empty.
-- "Any" always drops the requirement and restores the pet's real spec.
function TeamRoulette:RetuneSlot(state, slot, keepPet)
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

    if rec and real == req then
        rec.specName = req
        Recount(state); return state
    end

    local placed = PlacedPetNumbers(state, slot)
    local pool   = self:CurrentPool()

    if not keepPet then
        local matches = {}
        for _, p in ipairs(pool) do
            if p.petNumber and not placed[p.petNumber] and SpecOf(p) == req then
                matches[#matches + 1] = p
            end
        end
        if #matches > 0 then
            state.slots[slot] = ns.Teams:SlotRecord(matches[math.random(1, #matches)])
            Recount(state); return state
        end
    end

    if rec then
        rec.specName = req
        table.insert(state.report.coerced, { slot = slot, name = rec.name, from = real, to = req })
    elseif not keepPet then
        local any = {}
        for _, p in ipairs(pool) do
            if p.petNumber and not placed[p.petNumber] then any[#any + 1] = p end
        end
        if #any > 0 then
            local r = ns.Teams:SlotRecord(any[math.random(1, #any)])
            table.insert(state.report.coerced, { slot = slot, name = r.name, from = r.specName, to = req })
            r.specName = req
            state.slots[slot] = r
        end
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

    self:RetuneSlot(state, a, true)
    self:RetuneSlot(state, b, true)
    return state
end
