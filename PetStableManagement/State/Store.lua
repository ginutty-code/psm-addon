-- State/Store.lua
-- Slice versions, and pull-based selectors that recompute only when a dependency moved.
--
-- **A5.1 step 2.** The win this exists for is *leave-one-out*: the dynamic filter lists
-- deliberately exclude their own dimension -- `availableFamilies` answers "what families are
-- still reachable given the **other** filters" -- so ticking one family cannot change it.
-- Under one monolithic cache key it recomputed anyway, rescanning 61 families and their
-- display IDs and NPCs to produce a list that could not have moved. Splitting the
-- dependency set is the whole point; how each slice reports change is a separate question,
-- answered per slice below.
--
-- **Two kinds of slice, and the difference is evidence, not taste.**
--
--   * *Counted* -- every write goes through a funnel, so a counter is trustworthy. Only
--     claimed for slices where a spec enforces the funnel: `Tests/spec/selections_spec.lua`
--     for the five selection sets, `filterstate_spec` for the toggles.
--   * *Fingerprinted* -- writes are not funnelled, so change is derived from the value.
--     Costs a pass over the data per read, and cannot go stale.
--
-- That split is what step 1 was for. The plan's own warning is the reason it matters: a
-- string cache key degrades to over-caching when an input is unmodelled, a version counter
-- goes permanently stale. So a counter is only claimed where "did we catch every write?" has
-- a machine-checked answer, and everything else fingerprints until it earns one.
--
-- **An unknown slice is always dirty.** A selector depending on one recomputes every time,
-- exactly as today. That makes the migration safe in the direction that matters: an
-- unregistered dependency costs speed, never correctness.

local _, ns = ...

ns.Store = {}
local Store = ns.Store

local counter     = {}   -- slice -> integer, for counted slices
local fingerprint = {}   -- slice -> function returning a string, for the rest
local counted     = {}   -- slice -> true

-- `fn` nil declares a counted slice; passing one declares a fingerprinted slice. Declaring
-- is deliberate: an undeclared slice is always dirty, so forgetting to register loses a
-- speedup rather than producing a wrong answer.
function Store:Declare(slice, fn)
    if fn then
        fingerprint[slice] = fn
    else
        counted[slice] = true
        counter[slice] = counter[slice] or 0
    end
end

function Store:Bump(slice)
    if not counted[slice] then
        error(("PSM.Store: '%s' is not a counted slice, so it cannot be bumped")
            :format(tostring(slice)), 2)
    end
    counter[slice] = counter[slice] + 1
end

-- A string that changes exactly when the slice does, or nil when nothing is known about it.
-- Prefixed so a counter and a fingerprint can never collide into the same key.
function Store:Version(slice)
    if counted[slice] then return "c" .. counter[slice] end
    local fn = fingerprint[slice]
    if fn then return "f" .. fn() end
    return nil
end

-- A memoised, pull-based read. `deps` is the slice list; `compute` returns the value.
--
-- **`compute` takes no arguments, on purpose.** An argument would be part of the answer but
-- not part of the cache key, which is the classic way a memo starts returning one caller's
-- result to another. Selectors read shared state, and shared state is what slices describe.
--
-- The value is returned by reference and callers must treat it as read-only -- it is the
-- same table until a dependency moves. The one consumer today (`PopulateUnifiedFilterCheckboxes`)
-- only iterates it.
function Store:Selector(deps, compute)
    local cachedKey, cachedValue

    return function()
        local parts = {}
        for i = 1, #deps do
            local version = Store:Version(deps[i])
            -- Unknown slice: recompute, and do not cache -- caching against a partial key
            -- would be exactly the permanent staleness this design avoids.
            if version == nil then return compute() end
            parts[i] = version
        end

        local key = table.concat(parts, "|")
        if key ~= cachedKey then
            cachedKey  = key
            cachedValue = compute()
        end
        return cachedValue
    end
end

--------------------------------------------------------------------------------
-- Core's slices
--------------------------------------------------------------------------------

-- Funnelled and enforced -- see Selections.lua and Filters.lua, which bump these.
Store:Declare("families")
Store:Declare("expansions")
Store:Declare("locations")
Store:Declare("tamingRules")
Store:Declare("conditions")
Store:Declare("toggles")

-- Ownership, modelled by **content rather than count**.
--
-- This is A5.2, and it is fixed here rather than deferred because the fingerprint had to
-- decide something. `GenerateCacheKey` uses `#PSM.state.stablePets` as its ownership proxy,
-- so releasing one pet and taming another leaves the key identical while the display-ID set
-- changes -- and "Hide Owned" keeps showing the old answer. Narrow (it needs the browser
-- open across a stable transaction) and partly masked by the 0.2s expiry, but real.
Store:Declare("pets", function()
    local ids = {}
    for _, pet in ipairs(ns.state.stablePets or {}) do
        ids[#ids + 1] = tostring(pet.displayID or 0)
    end
    table.sort(ids)
    return table.concat(ids, ",")
end)

Store:Declare("favorites", function()
    local ids = {}
    for id, on in pairs(ns.state.favoriteModels or {}) do
        if on then ids[#ids + 1] = tostring(id) end
    end
    table.sort(ids)
    return table.concat(ids, ",")
end)
