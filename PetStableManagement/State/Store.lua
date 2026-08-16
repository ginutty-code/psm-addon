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

local NotifyWatchers   -- defined with the watcher machinery below

function Store:Bump(slice)
    if not counted[slice] then
        error(("PSM.Store: '%s' is not a counted slice, so it cannot be bumped")
            :format(tostring(slice)), 2)
    end
    counter[slice] = counter[slice] + 1
    NotifyWatchers()
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
-- One string for a whole dependency set, or **nil when any slice is unknown** -- the
-- caller's cue to treat the set as permanently dirty rather than cache against a partial
-- key, which would be exactly the staleness this design avoids.
local function CompositeKey(deps)
    local parts = {}
    for i = 1, #deps do
        local version = Store:Version(deps[i])
        if version == nil then return nil end
        parts[i] = version
    end
    return table.concat(parts, "|")
end

function Store:Selector(deps, compute)
    local cachedKey, cachedValue

    return function()
        local key = CompositeKey(deps)
        if key == nil then return compute() end
        if key ~= cachedKey then
            cachedKey   = key
            cachedValue = compute()
        end
        return cachedValue
    end
end

--------------------------------------------------------------------------------
-- WATCHERS
--------------------------------------------------------------------------------

-- **A5.1 step 4: the same comparison, run for effect instead of for a value.** A selector
-- answers "has this changed?" when someone asks; a watcher asks on the caller's behalf and
-- runs a callback when the answer is yes. That is the whole difference, and it is why this
-- reuses `CompositeKey` rather than introducing a second notion of change -- a push channel
-- that could disagree with the pull channel would be worse than no push channel at all.
--
-- It exists to delete the eleven hand-written `ReloadAndSummarise()` +
-- `UpdateDynamicFilters()` pairs in ModelsFilters. Those refresh because a *call site*
-- remembered to, so a twelfth filter write that forgets one goes silently stale. A watcher
-- refreshes because state moved.
--
-- **Known gap, stated rather than papered over: only a `Bump` wakes this.** Fingerprinted
-- slices (`pets`, `favorites`, `zone`) change without one, so a watcher will not notice a
-- pet being tamed on its own -- it notices at the next flush, which the next bump triggers.
-- Those slices already have their own refresh paths (the stable events, the favourite
-- click), so nothing regresses; it is simply not automated here. Making it so means either
-- polling the fingerprints every frame -- `pets` sorts the whole stable, so no -- or
-- funnelling their writes, which is the standing optional item that would turn `pets` into
-- a counter.
local watchers    = {}
local schedule                     -- how the host spells "soon"
local flushQueued = false

-- **Core cannot pick this itself.** `C_Timer.After` is the client's, and the headless suite
-- has no frames -- a Store that scheduled its own flush would be untestable at exactly the
-- point the coalescing lives. Installed with the client's timer at the bottom of this file
-- when one exists; the specs install a drainable queue instead.
function Store:SetScheduler(fn)
    schedule = fn
end

-- Fires changed watchers. Public because the scheduler calls it, and because a spec that
-- cannot drive a real frame needs a way to say "the next frame happened".
function Store:Flush()
    -- Cleared *before* the callbacks, so a bump made by one of them queues a fresh flush
    -- rather than being swallowed by the flush already in progress.
    flushQueued = false

    for i = 1, #watchers do
        local w = watchers[i]
        local key = CompositeKey(w.deps)
        if key == nil or key ~= w.key then
            w.key = key
            w.fn()
        end
    end
end

NotifyWatchers = function()
    if flushQueued or not schedule or #watchers == 0 then return end
    flushQueued = true
    -- Coalesced, and that is load-bearing rather than tidy: `Selections:SetAll` writes one
    -- key at a time, so selecting a continent bumps `locations` once per location. Firing
    -- per bump would reload the whole model list fifteen times for one click.
    schedule(function() Store:Flush() end)
end

-- `fn` runs when the composite version of `deps` moves -- never on registration, which
-- records the current key so that arriving does not read as a change.
function Store:Watch(deps, fn)
    if not schedule then
        error("PSM.Store: SetScheduler must be called before Watch, or the watcher would "
            .. "register successfully and then never fire", 2)
    end
    local w = { deps = deps, fn = fn, key = CompositeKey(deps) }
    watchers[#watchers + 1] = w
    return w
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

-- The client's "next frame", which is what coalescing a burst of writes means here. Only
-- the presence of `C_Timer` is read at file scope; the global itself is resolved at call
-- time, so this is a capability check and not the file-scope snapshot trap. Absent in the
-- headless suite, which installs its own drainable queue.
if C_Timer and C_Timer.After then
    Store:SetScheduler(function(fn) C_Timer.After(0, fn) end)
end
