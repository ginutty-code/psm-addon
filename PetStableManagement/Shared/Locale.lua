-- Locale.lua
-- The string lookup for both addons, and core's enUS entries.
--
-- Keys are English, so a key nobody declared degrades to readable English on screen
-- instead of a blank label. That is what lets the retrofit proceed a file at a time
-- without a broken UI in between.
--
-- The enUS entries are identity mappings and look redundant. They are the translator's
-- manifest, and they are what makes `L.missing` mean "undeclared key" -- a typo --
-- rather than "every string in the addon".

local _, ns = ...

-- key -> text. Private on purpose: consumers reach it through the call below, so the
-- Models Browser cannot overwrite a string for core.
local strings = {}

-- Keys asked for that nobody declared. Counted, matching Widgets.unknownOptions and
-- Skin.unhandled. Inspect in-game with: /dump PSM.L.missing
local missing = {}

local L = setmetatable({ missing = missing }, {
    __call = function(_, key, ...)
        local text = strings[key]
        if not text then
            missing[key] = (missing[key] or 0) + 1
            text = key
        end
        if select("#", ...) > 0 then
            return string.format(text, ...)
        end
        return text
    end,
})

-- Both addons declare their own strings through this; the Models Browser owns its 152
-- and registers them when it loads.
function L.Register(entries)
    for key, text in pairs(entries) do
        strings[key] = text
    end
end

ns.L = L

--------------------------------------------------------------------------------
-- enUS
--------------------------------------------------------------------------------

L.Register({
    -- Keys are the plain sentence; the value carries its colour. A key nobody declared
    -- therefore falls back to the same words without the markup.
    ["StableFrame not found!"]                        = "|cFFFF0000StableFrame not found!|r",
    ["Panel creation failed!"]                        = "|cFFFF0000Panel creation failed!|r",
    ["Panel failed to show!"]                         = "|cFFFF0000Panel failed to show!|r",
    ["No available slots to displace pet from slot 1!"] = "|cFFFF0000No available slots to displace pet from slot 1!|r",
    ["No available stable slots found! (Max 205 slots)"] = "|cFFFF0000No available stable slots found! (Max 205 slots)|r",

    ["Pet data snapshot created: %d pets saved."]     = "|cFF00FF00Pet data snapshot created: %d pets saved.|r",
    ["No snapshot available. Please visit a Stable Master to collect your owned pets data."] =
        "|cFFFF8800No snapshot available. Please visit a Stable Master to collect your owned pets data.|r",
    ["Pet Stable Management loaded. Use /psm or /petstable or click the minimap button to toggle the panel."] =
        "|cFF00FF00Pet Stable Management loaded. Use /psm or /petstable or click the minimap button to toggle the panel.|r",

    -- Shared with the Models Browser, which reaches them through PSM.L.
    ["Reset Filters"]     = "Reset Filters",
    ["Reset all filters"] = "Reset all filters",
    ["Pet Model Browser"] = "Pet Model Browser",
    ["Pet Model Browser: Cannot open panel during combat."] =
        "|cFFFF0000Pet Model Browser: Cannot open panel during combat.|r",
})
