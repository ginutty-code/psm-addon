-- State/Filters.lua
-- The Models Browser's five tristate filter toggles, and the only way to read or write them.
--
-- **A5.0: one home.** These used to live in three places at once -- the panel frame, this
-- addon's SavedVariables, and a `PSM.state.show*` mirror -- with every toggle handler
-- writing the same fact to all three by hand. The mirror turned out to be written fifteen
-- times and read never, so it was simply deleted. This file removes the second copy: the
-- frame no longer holds filter state, and SavedVariables is the single home.
--
-- SavedVariables, rather than a table here, on purpose. It is the copy that always had to
-- be correct -- it survives a reload, and every toggle already wrote through to it -- so
-- making it *the* value means there is no cache to go stale, no load step to sequence, and
-- no way for a panel rebuild to disagree with what the player saved. A third table would
-- have been a third thing to keep in sync, which is the problem, not the fix.
--
-- **Why this matters beyond tidiness.** A5's version-counter store can only invalidate
-- what it sees, and it sees writes that go through a setter. State sitting on a frame is
-- invisible to it: a selector would go stale on exactly the interaction the player performs
-- most, and it would look like a caching bug rather than a state-ownership one. `Set` below
-- is the single write funnel that makes the store possible.
--
-- Filter state stays name-keyed in SavedVariables. No user migration -- an existing saved
-- layout keeps applying, which is a hard requirement.

local _, ns = ...

ns.FilterState = {}
local FilterState = ns.FilterState

-- The vocabulary, declared rather than inferred. A typo'd name is a silent "off" forever
-- otherwise: `panel.showRaers` reads nil, which is a legal value meaning the filter is
-- disabled, so the filter simply never applies and nothing says why.
--
-- Values are tristate: nil (off), true (matching), "inverted" (non-matching). `false` was
-- also reachable -- ResetAllFilters wrote it while writing nil to SavedVariables -- but no
-- reader ever distinguished it from nil, since they all test `== true` or `== "inverted"`.
-- Normalised to nil here so "off" has one spelling.
local TOGGLES = {
    showRares        = true,
    showFavorites    = true,
    showHideOwned    = true,
    showNameKeepers  = true,
    showPetsInMyZone = true,
}

FilterState.TOGGLES = TOGGLES

local function Assert(name)
    if not TOGGLES[name] then
        error(("PSM.FilterState: unknown filter toggle '%s'"):format(tostring(name)), 3)
    end
end

-- The saved table, created on demand. Core.lua seeds `filters` for a fresh install, but a
-- database saved by an older version may not have it, so every write path checks.
local function Saved()
    if not PetStableManagementDB then return nil end
    PetStableManagementDB.filters = PetStableManagementDB.filters or {}
    return PetStableManagementDB.filters
end

-- nil / true / "inverted".
function FilterState:Get(name)
    Assert(name)
    local saved = PetStableManagementDB and PetStableManagementDB.filters
    local value = saved and saved[name]
    if value == false then return nil end
    return value
end

function FilterState:Set(name, value)
    Assert(name)
    if value == false then value = nil end
    local saved = Saved()
    if not saved or saved[name] == value then return end
    saved[name] = value
    -- A no-op write does not bump; see Selections.lua for why that matters.
    if ns.Store then ns.Store:Bump("toggles") end
end

-- Every toggle off. Callers that also reset selections and widgets do that themselves;
-- this owns the five toggles and nothing else.
function FilterState:Reset()
    for name in pairs(TOGGLES) do self:Set(name, nil) end
end

-- There is deliberately no `AnyActive()` here. Three sites in ModelsDataLoader build an
-- "are any other filters active" test over these toggles, and it looked like the obvious
-- fourth method -- but all three pair showPetsInMyZone with `panel.currentPlayerZone`,
-- because an active zone filter with no zone resolved matches nothing. A blanket helper
-- would answer true where those sites answer false, and it would be *reused*, which is
-- how a subtly wrong helper does more damage than three honest copies.
--
-- Those three copies are a real duplicate -- they are the dependency set for
-- `availableFamilies` written out by hand three times, which is exactly the shape A5.1
-- turns into a slice. Left for A5.1, where the zone condition can be modelled rather
-- than flattened.
