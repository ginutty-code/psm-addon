-- State/Filters.lua
-- The Models Browser's five tristate filter toggles, and the only way to read or write them.
--
-- SavedVariables is the single home, deliberately -- not a table here and not the panel
-- frame. It is the copy that has to be correct anyway, so there is no cache to go stale,
-- no load step to sequence, and no way for a panel rebuild to disagree with what the
-- player saved.
--
-- `Set` below is the single write funnel, which is what makes the store's version
-- counters work: state sitting on a frame is invisible to them, so a selector would go
-- stale on the interaction the player performs most and look like a caching bug.
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

-- There is deliberately no `AnyActive()` here. The three sites in ModelsDataLoader that
-- test "are any other filters active" all pair showPetsInMyZone with
-- `panel.currentPlayerZone`, because an active zone filter with no zone resolved matches
-- nothing. A blanket helper would answer true where they answer false -- and be reused.
