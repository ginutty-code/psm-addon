-- Tests/spec/filterstate_spec.lua
-- PSM.FilterState -- the one home for the Models Browser's five tristate toggles.
--
-- Worth testing headlessly out of proportion to its size, because it is the seam A5's
-- version-counter store slots into. Every write to a filter toggle goes through `Set`, and
-- a store can only invalidate what it sees; if a write path ever bypasses this again -- as
-- the old `panel.show*` fields did -- selectors go stale on the interaction players perform
-- most, and it presents as a caching bug rather than a state-ownership one.
--
-- The module has no frames and no client API beyond the SavedVariables global, so the whole
-- surface is reachable here.

local T = ...
local describe, it, eq, truthy = T.describe, T.it, T.eq, T.truthy

local Addon = dofile("Tests/wow/addon.lua")

local NAMES = { "showRares", "showFavorites", "showHideOwned",
                "showNameKeepers", "showPetsInMyZone" }

-- Fresh module against a fresh database. Loaded per test rather than once, because the
-- module deliberately holds no state of its own -- proving that is part of the point, and
-- a shared instance would hide a cache if one were ever added.
local function freshFilterState(saved)
    _G.PetStableManagementDB = saved
    return Addon.load("PetStableManagement/State/Filters.lua").FilterState
end

describe("FilterState reading", function()
    it("reads a value written by a previous session", function()
        local FS = freshFilterState({ filters = { showRares = true, showHideOwned = "inverted" } })
        eq(FS:Get("showRares"), true, "showRares")
        eq(FS:Get("showHideOwned"), "inverted", "showHideOwned")
    end)

    it("reads nil for a toggle never set", function()
        local FS = freshFilterState({ filters = {} })
        for _, name in ipairs(NAMES) do
            eq(FS:Get(name), nil, name)
        end
    end)

    -- A database saved before this change can hold `false`: ResetAllFilters wrote false to
    -- the frame and nil to SavedVariables, and the two drifted. No reader ever told them
    -- apart -- they all test `== true` or `== "inverted"` -- so "off" is normalised to one
    -- spelling here rather than left for each caller to get right.
    it("normalises a legacy false to nil", function()
        local FS = freshFilterState({ filters = { showRares = false } })
        eq(FS:Get("showRares"), nil, "false reads as nil")
    end)

    -- The module loads before ADDON_LOADED in the real client, so it must not assume the
    -- database exists, and an older database may have no `filters` table at all.
    it("survives a missing database", function()
        local FS = freshFilterState(nil)
        eq(FS:Get("showRares"), nil, "no DB at all")

        FS = freshFilterState({})
        eq(FS:Get("showRares"), nil, "DB with no filters table")
    end)
end)

describe("FilterState writing", function()
    it("writes through to SavedVariables, which is the only home", function()
        local db = { filters = {} }
        local FS = freshFilterState(db)
        FS:Set("showFavorites", "inverted")
        -- Asserted against the database directly, not via Get: the point of this module is
        -- that the persisted copy *is* the value, so a Get-only check could pass against a
        -- cache that never reached disk.
        eq(db.filters.showFavorites, "inverted", "persisted")
        eq(FS:Get("showFavorites"), "inverted", "and reads back")
    end)

    it("creates the filters table when an older database lacks it", function()
        local db = {}
        local FS = freshFilterState(db)
        FS:Set("showRares", true)
        truthy(db.filters, "filters table created")
        eq(db.filters.showRares, true, "value stored")
    end)

    it("stores nil rather than false when switched off", function()
        local db = { filters = {} }
        local FS = freshFilterState(db)
        FS:Set("showRares", false)
        eq(db.filters.showRares, nil, "false is normalised away on write too")
    end)

    it("does not disturb its siblings", function()
        local db = { filters = {} }
        local FS = freshFilterState(db)
        FS:Set("showRares", true)
        FS:Set("showNameKeepers", "inverted")
        eq(db.filters.showRares, true, "showRares kept")
        eq(db.filters.showNameKeepers, "inverted", "showNameKeepers kept")
        eq(db.filters.showFavorites, nil, "showFavorites untouched")
    end)
end)

describe("FilterState:Reset", function()
    it("clears every toggle", function()
        local db = { filters = {} }
        local FS = freshFilterState(db)
        for _, name in ipairs(NAMES) do FS:Set(name, true) end
        FS:Reset()
        for _, name in ipairs(NAMES) do
            eq(FS:Get(name), nil, name .. " cleared")
        end
    end)

    -- Reset used to be two hand-kept lists -- five frame fields and five database keys --
    -- sitting inside a function that also cleared taming rules, conditions and ability
    -- selections. It must still clear only what it owns.
    it("leaves neighbouring saved filters alone", function()
        local db = { filters = { showRares = true, selectedTamingRules = { a = true },
                                 selectedModelsFamilies = { Wolf = true } } }
        local FS = freshFilterState(db)
        FS:Reset()
        eq(FS:Get("showRares"), nil, "toggle cleared")
        truthy(db.filters.selectedTamingRules, "taming rules untouched")
        truthy(db.filters.selectedModelsFamilies, "family selection untouched")
    end)
end)

describe("FilterState vocabulary", function()
    -- The reason this errors rather than returning nil: nil is a *legal* value meaning
    -- "filter off", so a typo'd name would read as a permanently disabled filter and the
    -- feature would simply never apply, with nothing logged. That is the failure mode this
    -- codebase keeps meeting from other directions.
    it("raises on an unknown name rather than reading as off", function()
        local FS = freshFilterState({ filters = {} })
        local ok, err = pcall(function() return FS:Get("showRaers") end)
        eq(ok, false, "Get raises")
        truthy(tostring(err):find("showRaers", 1, true), "the error names the typo")
    end)

    it("raises on an unknown name when writing", function()
        local FS = freshFilterState({ filters = {} })
        eq(pcall(function() FS:Set("showWhatever", true) end), false, "Set raises")
    end)

    it("declares exactly the five toggles", function()
        local FS = freshFilterState({ filters = {} })
        local count = 0
        for name in pairs(FS.TOGGLES) do
            count = count + 1
            truthy(FS:Get(name) == nil, name .. " is readable")
        end
        eq(count, #NAMES, "toggle count")
    end)
end)
