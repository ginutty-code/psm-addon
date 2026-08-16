-- State/Selections.lua
-- The five multi-select filter sets, and the only place they may be written.
--
-- **A5.1 step 1: funnel the writes.** The plan's store invalidates on writes that go
-- through a setter, so "did we catch every write?" decides whether a version counter is
-- trustworthy or a source of permanent staleness. That question could not be answered by
-- reading the code, because the sets were mutated three ways:
--
--     PSM.state.selectedLocations[loc] = nil        -- directly
--     SelectAll(PSM.state.selectedModelsFamilies, list)   -- inside a helper, via a parameter
--     PSM.state.selectedExpansions = {}             -- reassigned wholesale
--
-- The second kind is invisible to any search for the field name, so the write count was a
-- lower bound that could not be turned into an upper bound. Routing every mutation through
-- here makes the set of writers finite and checkable -- `Tests/spec/selections_spec.lua`
-- fails the build on a direct assignment anywhere else, which is what turns "we think we
-- caught them all" into something a machine re-checks on every run.
--
-- **The values still live in `ns.state.selected*`.** Roughly a hundred read sites index
-- them directly and are untouched, because reads cannot invalidate anything and moving them
-- would be churn for its own sake. This owns writes; the store will hook them here.
--
-- Tristate, like the toggles: nil (not selected), true (selected), "inverted" (locations
-- only, and being removed there -- see ModelsFilters).

local _, ns = ...

ns.Selections = {}
local Selections = ns.Selections

-- Slice name -> the field in ns.state. The slice names are what the store's dependency
-- lists will use, so they are deliberately shorter and view-agnostic than the state keys,
-- which still carry the "selected"/"Models" prefixes from when the browser was one panel.
local SLICES = {
    families    = "selectedModelsFamilies",
    expansions  = "selectedExpansions",
    locations   = "selectedLocations",
    tamingRules = "selectedTamingRules",
    conditions  = "selectedConditions",
}

Selections.SLICES = SLICES

local function Field(slice)
    local field = SLICES[slice]
    if not field then
        error(("PSM.Selections: unknown slice '%s'"):format(tostring(slice)), 3)
    end
    return field
end

-- The live table, created if absent. Callers read and iterate through this; writing to the
-- result is the one thing the spec forbids, because it is a write that bypasses this file.
function Selections:Get(slice)
    local field = Field(slice)
    ns.state[field] = ns.state[field] or {}
    return ns.state[field]
end

-- Every mutation below routes through here, so this is the single place the store has to
-- be told. **A no-op write does not bump**: writing the value a key already holds is what
-- rebuilding a checkbox row does on every repopulate, and treating those as changes would
-- invalidate a selector on every redraw -- the cache would exist and never hit.
local function Write(slice, set, key, value)
    if set[key] == value then return end
    set[key] = value
    if ns.Store then ns.Store:Bump(slice) end
end

function Selections:Set(slice, key, value)
    if key == nil then return end
    Write(slice, self:Get(slice), key, value)
end

-- `keys` is an array of names -- a families/expansions/locations list as the panel holds
-- it. Replaces the three `SelectAll(stateMap, list)` calls, which mutated a table they
-- received as a parameter and so could not be found by searching for what they wrote.
function Selections:SetAll(slice, keys, value)
    local set = self:Get(slice)
    for _, key in ipairs(keys or {}) do
        Write(slice, set, key, value)
    end
end

-- **Empties in place; never reassigns.** Several call sites used to write
-- `ns.state.selectedExpansions = {}`, which silently detaches any alias another function is
-- still holding -- and this file exists partly because those aliases are hard to find. One
-- table identity for the session removes the question.
function Selections:Clear(slice)
    local set = self:Get(slice)
    if next(set) == nil then return end
    for key in pairs(set) do set[key] = nil end
    if ns.Store then ns.Store:Bump(slice) end
end

-- Clear, then copy `source`. Same identity-preserving reason as Clear: SpecialTames used to
-- hand its freshly built map straight to `ns.state.selectedTamingRules`, replacing the
-- table rather than its contents.
--
-- The copy goes through Write like everything else. Writing `set[key] = value` here instead
-- -- which is how this was first written -- left a hole in the one function whose job is to
-- have none: Clear does not bump an already-empty slice, so Replace onto an empty one
-- bumped nothing, and SpecialTames' Apply on a fresh session invalidated no selector.
function Selections:Replace(slice, source)
    self:Clear(slice)
    if not source then return end
    local set = self:Get(slice)
    for key, value in pairs(source) do Write(slice, set, key, value) end
end

-- Fill only if empty, for seeding a fresh panel from a full list without overwriting a
-- selection the player already made.
function Selections:FillIfEmpty(slice, keys, value)
    if next(self:Get(slice)) ~= nil then return false end
    self:SetAll(slice, keys, value)
    return true
end

-- Any key selected, in either direction. The `next(...) ~= nil` test callers wrote by hand
-- is subtly different -- it counts a key explicitly set to false or nil-ed to absent -- so
-- this checks for a truthy value rather than for presence.
function Selections:Any(slice)
    for _, value in pairs(self:Get(slice)) do
        if value then return true end
    end
    return false
end
