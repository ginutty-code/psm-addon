-- Tests/spec/log_spec.lua
-- The ring buffer behind /psm debug. Utils_spec covers that SafeCall feeds it; this
-- covers the buffer's own shape -- trimming, ordering, and the empty/non-empty dump.

local T = ...
local describe, it, eq, truthy = T.describe, T.it, T.eq, T.truthy

dofile("Tests/wow/stubs.lua").install()
local Addon = dofile("Tests/wow/addon.lua")

local function freshLog()
    -- Log:Dump prints through ns.Utils:Msg, which needs ns.Config.COLORS -- same
    -- load order as the client's .toc: Locale, Config, Log, Utils.
    local ns = Addon.load("PetStableManagement/Shared/Locale.lua")
    Addon.load("PetStableManagement/Shared/Config.lua", ns)
    Addon.load("PetStableManagement/Shared/Log.lua", ns)
    Addon.load("PetStableManagement/Shared/Utils.lua", ns)
    return ns.Log
end

describe("Log:Record / Dump", function()
    it("prints a plain message when nothing was recorded", function()
        local Log = freshLog()
        local printed = {}
        local realPrint = _G.print
        _G.print = function(msg) printed[#printed + 1] = msg end
        Log:Dump()
        _G.print = realPrint
        eq(#printed, 1, "one line")
        truthy(printed[1]:find("No errors recorded", 1, true), "says nothing recorded")
    end)

    it("dumps every recorded entry, oldest first, with its traceback", function()
        local Log = freshLog()
        Log:Record("first boom", "stack A")
        Log:Record("second boom", "stack B")

        local printed = {}
        local realPrint = _G.print
        _G.print = function(msg) printed[#printed + 1] = msg end
        Log:Dump()
        _G.print = realPrint

        -- header + (message, traceback) per entry
        eq(#printed, 5, "header plus two message/traceback pairs")
        truthy(printed[2]:find("first boom", 1, true), "first message present")
        eq(printed[3], "stack A", "first traceback present")
        truthy(printed[4]:find("second boom", 1, true), "second message present")
        eq(printed[5], "stack B", "second traceback present")
    end)

    it("keeps only the most recent entries once the ring buffer is full", function()
        local Log = freshLog()
        for i = 1, 25 do
            Log:Record("error " .. i, "stack " .. i)
        end

        local printed = {}
        local realPrint = _G.print
        _G.print = function(msg) printed[#printed + 1] = msg end
        Log:Dump()
        _G.print = realPrint

        -- header + 20 (message, traceback) pairs = 41 lines; oldest 5 dropped
        eq(#printed, 41, "capped at 20 entries")
        truthy(printed[2]:find("error 6", 1, true), "oldest surviving entry is #6")
        truthy(printed[#printed - 1]:find("error 25", 1, true), "newest entry is #25")
    end)

    it("Clear empties the buffer", function()
        local Log = freshLog()
        Log:Record("boom", "stack")
        Log:Clear()

        local printed = {}
        local realPrint = _G.print
        _G.print = function(msg) printed[#printed + 1] = msg end
        Log:Dump()
        _G.print = realPrint
        eq(#printed, 1, "back to the empty message")
    end)
end)
