-- Tests/spec/store_spec.lua
-- PSM.Store: slice versions, and selectors that skip work only when it is safe to.
--
-- Four of these are the plan's own acceptance criteria for A5, and two of them cannot be
-- established any other way -- "selecting a family does not invalidate availableFamilies"
-- and "swapping a pet at equal count does invalidate ownership" are both statements about
-- work *not* done or *newly* done, invisible from the outside.

local T = ...
local describe, it, eq, truthy = T.describe, T.it, T.eq, T.truthy

local Addon = dofile("Tests/wow/addon.lua")

-- Store, Selections and FilterState share one namespace here, as they do in the client:
-- Selections bumps `ns.Store`, so loading them apart would silently exercise the branch
-- where the store is absent and prove nothing about the wiring.
local function freshStore()
    _G.PetStableManagementDB = { filters = {} }
    local ns = Addon.namespace()
    ns.state = { stablePets = {}, favoriteModels = {} }
    Addon.load("PetStableManagement/State/Store.lua", ns)
    Addon.load("PetStableManagement/State/Filters.lua", ns)
    Addon.load("PetStableManagement/State/Selections.lua", ns)
    return ns.Store, ns.Selections, ns.FilterState, ns
end

describe("Store versions", function()
    it("gives nil for a slice nobody declared", function()
        local Store = freshStore()
        eq(Store:Version("nosuchthing"), nil, "undeclared")
    end)

    it("moves a counted slice when a real write happens", function()
        local Store, Selections = freshStore()
        local before = Store:Version("families")
        Selections:Set("families", "Wolf", true)
        truthy(Store:Version("families") ~= before, "version moved")
    end)

    -- Acceptance criterion (a). A repopulate rewrites every checkbox's current value, so
    -- counting those as changes would invalidate on every redraw and the cache would exist
    -- without ever hitting.
    it("does not move on a no-op write", function()
        local Store, Selections = freshStore()
        Selections:Set("families", "Wolf", true)
        local before = Store:Version("families")
        Selections:Set("families", "Wolf", true)
        eq(Store:Version("families"), before, "writing the same value again")
    end)

    it("does not move when clearing an already-empty slice", function()
        local Store, Selections = freshStore()
        local before = Store:Version("locations")
        Selections:Clear("locations")
        eq(Store:Version("locations"), before, "clear of an empty set")
    end)

    it("moves the toggles slice on a real toggle change, not a repeat", function()
        local Store, _, FilterState = freshStore()
        local before = Store:Version("toggles")
        FilterState:Set("showRares", true)
        local afterReal = Store:Version("toggles")
        truthy(afterReal ~= before, "real change moved it")
        FilterState:Set("showRares", true)
        eq(Store:Version("toggles"), afterReal, "repeat did not")
    end)

    -- Every mutator, checked individually. Replace shipped with a hole: it copied straight
    -- into the table instead of going through the same write path, and since Clear does not
    -- bump an already-empty slice, replacing onto an empty one bumped nothing at all. That
    -- is SpecialTames' Apply on a fresh session -- the exact case a store must not miss.
    it("moves the version from every mutator", function()
        for _, case in ipairs({
            { name = "Set",         run = function(S) S:Set("families", "Wolf", true) end },
            { name = "SetAll",      run = function(S) S:SetAll("families", { "Bear" }, true) end },
            { name = "Replace",     run = function(S) S:Replace("families", { Cat = true }) end },
            { name = "FillIfEmpty", run = function(S) S:FillIfEmpty("families", { "Boar" }, true) end },
            { name = "Clear",       run = function(S)
                S:Set("families", "Seed", true)
                S:Clear("families")
            end },
        }) do
            local Store, Selections = freshStore()
            local before = Store:Version("families")
            case.run(Selections)
            truthy(Store:Version("families") ~= before, case.name .. " bumped the version")
        end
    end)

    it("refuses to bump a fingerprinted slice", function()
        local Store = freshStore()
        eq(pcall(function() Store:Bump("pets") end), false, "pets is fingerprinted")
    end)
end)

describe("Store ownership fingerprint", function()
    -- Acceptance criterion (d), and the A5.2 bug. GenerateCacheKey used #stablePets as its
    -- ownership proxy, so releasing one pet and taming another left the key identical while
    -- the display-ID set changed, and Hide Owned kept showing the old answer.
    it("changes when a pet is swapped for another at equal count", function()
        local Store, _, _, ns = freshStore()
        ns.state.stablePets = { { displayID = 111 }, { displayID = 222 } }
        local before = Store:Version("pets")

        ns.state.stablePets = { { displayID = 111 }, { displayID = 333 } }
        eq(#ns.state.stablePets, 2, "fixture: the count is unchanged")
        truthy(Store:Version("pets") ~= before, "but the version moved")
    end)

    it("is stable when the same pets are listed in a different order", function()
        local Store, _, _, ns = freshStore()
        ns.state.stablePets = { { displayID = 222 }, { displayID = 111 } }
        local a = Store:Version("pets")
        ns.state.stablePets = { { displayID = 111 }, { displayID = 222 } }
        eq(Store:Version("pets"), a, "order does not matter")
    end)

    it("counts duplicates, since two pets sharing a model are two pets", function()
        local Store, _, _, ns = freshStore()
        ns.state.stablePets = { { displayID = 111 } }
        local one = Store:Version("pets")
        ns.state.stablePets = { { displayID = 111 }, { displayID = 111 } }
        truthy(Store:Version("pets") ~= one, "a second copy is a change")
    end)
end)

describe("Store selectors", function()
    it("computes once and reuses while nothing moves", function()
        local Store = freshStore()
        local calls = 0
        local sel = Store:Selector({ "families" }, function()
            calls = calls + 1
            return { calls }
        end)
        sel(); sel(); sel()
        eq(calls, 1, "computed once")
    end)

    it("recomputes after a dependency moves", function()
        local Store, Selections = freshStore()
        local calls = 0
        local sel = Store:Selector({ "families" }, function() calls = calls + 1 return calls end)
        sel()
        Selections:Set("families", "Wolf", true)
        sel()
        eq(calls, 2, "recomputed")
    end)

    -- **Acceptance criterion (c), and the reason the whole design exists.** The dynamic
    -- filter lists are leave-one-out: availableFamilies answers "what is reachable given the
    -- *other* filters", so the family selection cannot change it. Under one shared cache key
    -- it recomputed anyway -- a full rescan of 61 families to produce an identical list.
    it("does not recompute when a slice it does not depend on moves", function()
        local Store, Selections = freshStore()
        local calls = 0
        local availableFamilies = Store:Selector(
            { "expansions", "locations", "toggles" },
            function() calls = calls + 1 return calls end)

        availableFamilies()
        eq(calls, 1, "first read computes")

        Selections:Set("families", "Wolf", true)
        Selections:Set("families", "Bear", true)
        availableFamilies()
        eq(calls, 1, "ticking families did not invalidate it")

        Selections:Set("expansions", "Classic", true)
        availableFamilies()
        eq(calls, 2, "but an expansion did")
    end)

    -- The safety property that makes partial migration sound: an unregistered dependency
    -- costs speed, never correctness.
    it("always recomputes when any dependency is unknown", function()
        local Store = freshStore()
        local calls = 0
        local sel = Store:Selector({ "families", "somethingNobodyDeclared" },
            function() calls = calls + 1 return calls end)
        sel(); sel(); sel()
        eq(calls, 3, "no caching against a partial key")
    end)

    it("keeps a counter and a fingerprint from colliding", function()
        -- Both produce strings; without the prefix a counter reading "3" and a fingerprint
        -- reading "3" would be indistinguishable, and a selector could miss a change.
        local Store = freshStore()
        truthy(Store:Version("families"):sub(1, 1) == "c", "counted slices prefix c")
        truthy(Store:Version("pets"):sub(1, 1) == "f", "fingerprinted slices prefix f")
    end)
end)

-- A5.1 step 4. The watcher is what let the eleven hand-written refresh pairs go, so the
-- properties that make it a safe replacement have to be established, not assumed.
describe("Store watchers", function()
    -- Stands in for C_Timer.After(0, ...). Holding the callbacks rather than running them
    -- is what makes coalescing observable: the count of queued flushes *is* the assertion.
    local function withScheduler()
        local Store, Selections, FilterState, ns = freshStore()
        local queue = {}
        Store:SetScheduler(function(fn) queue[#queue + 1] = fn end)
        -- **Emptied in place, never rebound.** `queue` is handed back by reference, so
        -- `queue = {}` here would leave every caller measuring a table this stopped writing
        -- to -- which is exactly how the re-entrancy test below first passed against code
        -- that was broken. Same identity-preserving reason as Selections:Clear.
        local function drain()
            local pending = {}
            for i = 1, #queue do pending[i] = queue[i]; queue[i] = nil end
            for _, fn in ipairs(pending) do fn() end
        end
        return Store, Selections, FilterState, ns, queue, drain
    end

    it("refuses to register without a scheduler", function()
        local Store = freshStore()
        local ok = pcall(function() Store:Watch({ "families" }, function() end) end)
        eq(ok, false, "a watcher with no scheduler would never fire, so registering fails")
    end)

    it("does not fire on registration", function()
        local Store, _, _, _, _, drain = withScheduler()
        local fired = 0
        Store:Watch({ "families" }, function() fired = fired + 1 end)
        drain()
        eq(fired, 0, "arriving is not a change")
    end)

    it("fires once after a dependency moves", function()
        local Store, Selections, _, _, _, drain = withScheduler()
        local fired = 0
        Store:Watch({ "families" }, function() fired = fired + 1 end)
        Selections:Set("families", "Wolf", true)
        drain()
        eq(fired, 1, "fired")
        drain()
        eq(fired, 1, "and not again while nothing moves")
    end)

    -- **The reason the watcher is scheduled rather than called straight from Bump.**
    -- Selections:SetAll writes one key at a time, so selecting a continent bumps `locations`
    -- once per location. Firing per bump would reload the whole model list fifteen times for
    -- a single click -- worse than the hand-written pairs it replaces.
    it("coalesces a burst of writes into one flush", function()
        local Store, Selections, _, _, queue, drain = withScheduler()
        local fired = 0
        Store:Watch({ "locations" }, function() fired = fired + 1 end)

        local locs = {}
        for i = 1, 15 do locs[i] = "Zone" .. i end
        Selections:SetAll("locations", locs, true)

        eq(#queue, 1, "fifteen bumps queued one flush")
        drain()
        eq(fired, 1, "and the watcher ran once")
    end)

    it("does not fire for a slice outside its dependency list", function()
        local Store, Selections, _, _, _, drain = withScheduler()
        local fired = 0
        Store:Watch({ "expansions" }, function() fired = fired + 1 end)
        Selections:Set("families", "Wolf", true)
        drain()
        eq(fired, 0, "families is not watched")
    end)

    it("does not fire for a no-op write", function()
        local Store, Selections, _, _, _, drain = withScheduler()
        Selections:Set("families", "Wolf", true)
        local fired = 0
        Store:Watch({ "families" }, function() fired = fired + 1 end)
        Selections:Set("families", "Wolf", true)
        drain()
        eq(fired, 0, "writing the same value again is not a change")
    end)

    -- A fingerprinted dependency is compared at flush time like any other, so once a flush
    -- happens the swapped pet is seen. What wakes the flush is the separate question below.
    it("sees a fingerprinted dependency change once a flush happens", function()
        local Store, Selections, _, ns, _, drain = withScheduler()
        ns.state.stablePets = { { displayID = 111 } }
        local fired = 0
        Store:Watch({ "pets", "families" }, function() fired = fired + 1 end)

        ns.state.stablePets = { { displayID = 222 } }
        Selections:Set("families", "Wolf", true)   -- the bump that wakes the flush
        drain()
        eq(fired, 1, "the pets change was picked up at flush time")
    end)

    -- **The known gap, asserted rather than left to be discovered.** Only a Bump schedules a
    -- flush, and fingerprinted slices have no write funnel to bump from -- so a pet tamed
    -- with nothing else touched does not wake a watcher by itself. Those slices keep their
    -- own refresh paths (stable events, the favourite click), so nothing regressed; this
    -- test exists so the limit is visible and a future funnel has something to flip.
    it("is not woken by a fingerprinted slice on its own", function()
        local Store, _, _, ns, queue = withScheduler()
        local fired = 0
        Store:Watch({ "pets" }, function() fired = fired + 1 end)
        ns.state.stablePets = { { displayID = 999 } }
        eq(#queue, 0, "no flush was scheduled")
        eq(fired, 0, "so the watcher did not fire")
    end)

    it("lets a callback's own write schedule the next flush", function()
        -- Flush clears the queued flag before running callbacks. If it cleared it after, a
        -- bump made *by* a callback would be swallowed and that change would never refresh.
        local Store, Selections, _, _, queue, drain = withScheduler()
        local fired = 0
        Store:Watch({ "families" }, function()
            fired = fired + 1
            if fired == 1 then Selections:Set("expansions", "Classic", true) end
        end)
        Store:Watch({ "expansions" }, function() fired = fired + 100 end)

        Selections:Set("families", "Wolf", true)
        drain()
        eq(#queue, 1, "the callback's write queued another flush")
        drain()
        eq(fired, 101, "and the second watcher ran on it")
    end)
end)
