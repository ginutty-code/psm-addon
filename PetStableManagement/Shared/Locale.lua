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

    -- Dialogs: teams, groups, slot pickers
    ["OK"]     = "OK",
    ["Cancel"] = "Cancel",
    ["Close"]  = "Close",

    ["Delete Team"]       = "Delete Team",
    ["Apply Team"]        = "Apply Team",
    ["Delete Group"]      = "Delete Group",
    ["Delete All Groups"] = "Delete All Groups",
    ["Save New Team"]     = "Save New Team",
    ["Update Team"]       = "Update Team",
    ["Save as New Team"]  = "Save as New Team",
    ["Create New Team"]   = "Create New Team",
    ["New Team Name"]     = "New Team Name",

    ["Enter a name for your pet team:"] = "Enter a name for your pet team:",
    ["Enter a name for the new team:"]  = "Enter a name for the new team:",
    ["Enter a name for your new team:"] = "Enter a name for your new team:",
    ["Select a team to add this pet to:"] = "Select a team to add this pet to:",
    ["Select a slot to add this pet to:"] = "Select a slot to add this pet to:",
    ["This pet is not in any of your saved teams."] = "This pet is not in any of your saved teams.",
    ["You don't have any saved teams yet.\nCreate a new team with this pet:"] =
        "You don't have any saved teams yet.\nCreate a new team with this pet:",
    ["This pet is in %s team(s).\nSelect a team to remove from:"] =
        "This pet is in %s team(s).\nSelect a team to remove from:",
    ["Current slots differ from team '%s'.\nWhat would you like to do?"] =
        "Current slots differ from team '%s'.\nWhat would you like to do?",
    ["'%s' is already in team '%s'\nat slot %s.\n\nEach pet can only appear once per team."] =
        "'%s' is already in team '%s'\nat slot %s.\n\nEach pet can only appear once per team.",

    -- Filled with a name that may be absent, hence the fallbacks below.
    ["Pet: %s"]  = "Pet: %s",
    ["Team: %s"] = "Team: %s",
    ["Slot %s"]  = "Slot %s",
    ["Slot %s (Occupied)"]  = "Slot %s (Occupied)",
    ["Slot %s (Available)"] = "Slot %s (Available)",
    ["Unknown"] = "Unknown",
    ["pet"]     = "pet",

    ["Failed to save team"]            = "Failed to save team",
    ["Failed to add pet to team"]      = "Failed to add pet to team",
    ["Failed to remove pet from team"] = "Failed to remove pet from team",

    ["Cannot add duplicate pet '%s' to team '%s'. Pet already exists at slot %s."] =
        "|cFFFF0000PetStableManagement: Cannot add duplicate pet '%s' to team '%s'. Pet already exists at slot %s.|r",
    ["Added '%s' to team '%s' at slot %s."] =
        "|cFF00FF00PetStableManagement: Added '%s' to team '%s' at slot %s.|r",
    ["Removed %s from team '%s'."] =
        "|cFF00FF00PetStableManagement: Removed %s from team '%s'.|r",
})
