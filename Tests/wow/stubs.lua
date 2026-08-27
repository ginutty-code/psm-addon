-- Tests/wow/stubs.lua
-- Stand-ins for the WoW client API, enough for frame-free addon code to load and
-- run outside the game.
--
-- Rule for adding to this file: a stub must behave the way the real API does for
-- the cases under test, or not exist at all. A stub that quietly returns nil (or
-- a no-op frame that swallows every call) turns a real bug into a passing test,
-- which is worse than no coverage. If faithful behaviour is impractical, leave it
-- out and keep that code untestable until the layering work (A3-A6) separates it.

local S = {}

-- The subset needed by the frame-free code currently under test.
function S.install()
    -- Blizzard's strtrim removes leading/trailing whitespace.
    _G.strtrim = _G.strtrim or function(s)
        s = tostring(s)
        return (s:gsub("^%s+", ""):gsub("%s+$", ""))
    end

    _G.strsplit = _G.strsplit or function(sep, str)
        local out = {}
        for piece in tostring(str):gmatch("([^" .. sep .. "]+)") do
            out[#out + 1] = piece
        end
        return unpack(out)
    end

    -- Monotonic seconds. Real GetTime is client uptime; only ordering and
    -- differences are ever relied on, both of which os.clock preserves.
    _G.GetTime = _G.GetTime or function() return os.clock() end

    _G.date = _G.date or os.date
    _G.time = _G.time or os.time
end

-- Resets globals this file installed. Call between specs that need isolation.
function S.uninstall()
    for _, k in ipairs({ "strtrim", "strsplit", "GetTime" }) do
        _G[k] = nil
    end
end

return S
