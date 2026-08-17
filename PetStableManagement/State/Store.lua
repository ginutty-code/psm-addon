-- State/Store.lua
-- Slice versions, and pull-based selectors that recompute only when a dependency moved.
--
-- The win this exists for is *leave-one-out*: the dynamic filter lists deliberately exclude
-- their own dimension -- `availableFamilies` answers "what families are still reachable given
-- the **other** filters" -- so ticking one family cannot change it. A single cache key
-- recomputed it anyway. Splitting the dependency set is the point.
--
-- **Two kinds of slice, and the difference is evidence, not taste.**
--
--   * *Counted* -- every write goes through a funnel, so a counter is trustworthy. Only
--     claimed where a spec enforces the funnel: `selections_spec` for the five selection
--     sets, `filterstate_spec` for the toggles.
--   * *Fingerprinted* -- writes are not funnelled, so change is derived from the value.
--     Costs a pass over the data per read, and cannot go stale.
--
-- A counter is claimed only where "did we catch every write?" has a machine-checked answer;
-- everything else fingerprints until it earns one. A stale counter is a wrong answer, an
-- extra fingerprint pass is only slow.
--
-- **An unknown slice is always dirty**, so an unregistered dependency costs speed, never
-- correctness.

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

-- **The manual wake, for change a fingerprint can see but no funnel can announce.**
--
-- Only `Bump` schedules a flush, and fingerprinted slices have no funnel to bump from --
-- so something that changes `search` or `zone` has to say so. `Touch` is that, and it is
-- deliberately argument-free: it does not claim *what* changed, it only asks the watchers
-- to re-read their dependencies. A caller that named a slice could name the wrong one and
-- be believed; a caller that names nothing cannot be wrong, because every version is
-- recomputed from the data either way.
--
-- Cheap for the same reason: a Touch with nothing behind it costs one composite-key
-- comparison per watcher on the next frame and fires nothing.
function Store:Touch()
    NotifyWatchers()
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

-- **The Owned Pets panel needs a stricter answer than `pets`.** Two differences, both of
-- which `pets` gets deliberately right for the browser and wrong here:
--
--   * **Order matters.** `pets` sorts before hashing, because model filtering cannot care
--     what order the stable is in. This panel lists individual pets in `stablePets` order
--     when no sort column is chosen, so DragDrop reordering changes the answer.
--   * **Identity, not model.** `petNumber` is unique per pet, so releasing one pet and
--     taming another that shares a model is a real change here.
--
-- **`slotID` is in the fingerprint because array order alone is not enough.** Swapping two
-- occupied slots reorders the list, which a positional hash catches. Moving a pet into an
-- *empty* slot does not -- same pets, same sequence, one different `slotID` -- and the panel
-- displays slot numbers and can sort by them.
Store:Declare("ownedPets", function()
    local parts = {}
    for i, pet in ipairs(ns.state.stablePets or {}) do
        parts[i] = tostring(pet.petNumber or pet.displayID or 0) .. ":" .. tostring(pet.slotID or 0)
    end
    return table.concat(parts, ",")
end)

Store:Declare("favorites", function()
    local ids = {}
    for id, on in pairs(ns.state.favoriteModels or {}) do
        if on then ids[#ids + 1] = tostring(id) end
    end
    table.sort(ids)
    return table.concat(ids, ",")
end)

--------------------------------------------------------------------------------
-- The Owned Pets panel's slices
--------------------------------------------------------------------------------

-- **Fingerprinted throughout, and this panel needed no write funnel at all.** The browser
-- funnelled its selections because it wanted *counters* for hot, large sets -- 61 families,
-- 400+ locations, rescanned on every pill click. These sets are small (a handful of specs,
-- tamers, families) and `UI:GenerateCacheKey` already hashed all three on every render, so
-- fingerprinting costs exactly what the old key cost and cannot go stale.
--
-- Together with `ownedPets` above, these are the complete input set of
-- `UI:_CalculateRenderData` -- checked by reading it rather than by trusting the old cache
-- key, which turned out to be missing one (see `panelWidth`).

Store:Declare("ownedSpecs",    function() return ns.Utils:GetTableHash(ns.state.selectedSpecs) end)
Store:Declare("ownedFamilies", function() return ns.Utils:GetTableHash(ns.state.selectedFamilies) end)
Store:Declare("ownedTamers",   function() return ns.Utils:GetTableHash(ns.state.selectedTamers) end)

Store:Declare("ownedExotic",     function() return tostring(ns.state.exoticFilter) end)
Store:Declare("ownedDuplicates", function() return tostring(ns.state.duplicatesOnlyFilter) end)
Store:Declare("ownedSort",       function() return tostring(ns.state.sortBy) end)

-- The panel's own search box, on the same argument as the browser's `search`: the home is a
-- widget, and a widget's writes cannot be funnelled or spec-enforced.
Store:Declare("ownedSearch", function()
    local panel = ns.state.panel
    local box   = panel and panel.searchBox
    return box and box:GetSearchText() or ""
end)

-- **The input the old cache key never had.** `_CalculateRenderData` derives `colCount`,
-- `colWidth` and `rowTotal` from `ns.state.content:GetWidth()`, so resizing the panel
-- changes the correct answer while leaving the key identical. That is why the resize
-- handler in PanelManager had to invalidate the cache by hand -- state living in a frame is
-- invisible to invalidation, which is the case A5.0 was written about, in the file A5.0 was
-- written about.
--
-- Fingerprinted rather than bumped on resize: the width is readable at any moment, so
-- deriving it is strictly more truthful than trusting one handler to announce every change.
Store:Declare("panelWidth", function()
    local content = ns.state.content
    return tostring(content and content.GetWidth and content:GetWidth() or 0)
end)

-- The client's "next frame", which is what coalescing a burst of writes means here. Only
-- the presence of `C_Timer` is read at file scope; the global itself is resolved at call
-- time, so this is a capability check and not the file-scope snapshot trap. Absent in the
-- headless suite, which installs its own drainable queue.
if C_Timer and C_Timer.After then
    Store:SetScheduler(function(fn) C_Timer.After(0, fn) end)
end
