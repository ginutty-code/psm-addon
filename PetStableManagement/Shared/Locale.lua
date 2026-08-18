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

    -- Popups: model viewer, notes, waypoints, taming requirements
    ["Save"]  = "Save",
    ["Clear"] = "Clear",
    ["Try Again"]   = "Try Again",
    ["Model Viewer"]    = "Model Viewer",
    ["Model Magnifier"] = "Model Magnifier",
    ["Reset View"]      = "Reset View",
    ["< Pet Models"]    = "< Pet Models",
    ["Add to Favorites"] = "Add to Favorites",
    ["Wowhead URL"]      = "Wowhead URL",
    ["Special Conditions"]     = "Special Conditions",
    ["Taming Skills Required"] = "Taming Skills Required",
    ["(keeps name)"]           = "(keeps name)",

    ["Edit note"]               = "Edit note",
    ["Add your own note"]       = "Add your own note",
    ["Add a note for this NPC"] = "Add a note for this NPC",
    ["Info note (read-only):"]  = "Info note (read-only):",
    ["My note:"]                = "My note:",
    ["Notes: %s"]               = "Notes: %s",

    ["Click to view waypoints"]    = "Click to view waypoints",
    ["Click to copy Wowhead URL"]  = "Click to copy Wowhead URL",
    ["Create Waypoints"]           = "Create Waypoints",
    ["Adds a waypoint pin on the map"] = "Adds a waypoint pin on the map",
    ["Install TomTom for portrait icons, multiple waypoints, and navigation."] =
        "Install TomTom for portrait icons, multiple waypoints, and navigation.",
    ["Waypoints for \n %s \n(%s)"] = "Waypoints for \n %s \n(%s)",
    ["%s waypoint(s) added on %s map for %s"] =
        "|cff00ff00%s waypoint(s) added on %s map for %s|r",
    ["Only the first location was marked. Install TomTom for all waypoints, portrait icons, and navigation."] =
        "|cffffff00PSM:|r Only the first location was marked. Install |cff3fc7ebTomTom|r for all waypoints, portrait icons, and navigation.",

    -- Fallbacks for data the client may not have yet.
    ["NPC"]     = "NPC",
    ["NPC %s"]  = "NPC %s",
    ["Map %s"]  = "Map %s",
    ["Item #%s"]  = "Item #%s",
    ["Quest #%s"] = "Quest #%s",
    ["%s (auto)"] = "%s (auto)",
    ["%s - Display ID: %d"] = "%s - Display ID: %d",

    -- Joins the alternative locations in a taming hint; a separator is copy too.
    [" or "] = " or ",

    -- Owned pets: filter bar, sort menu, CSV export
    ["Sort by"]  = "Sort by",
    ["Unsorted"] = "Unsorted",
    ["Family"]   = "Family",
    ["Model"]    = "Model",
    ["Slot"]     = "Slot",
    ["Spec"]     = "Spec",
    ["Tamer"]    = "Tamer",
    ["Sorted by Slot"]   = "Sorted by Slot",
    ["Sorted by Model"]  = "Sorted by Model",
    ["Sorted by Family"] = "Sorted by Family",
    ["Sorted by Spec"]   = "Sorted by Spec",
    ["Sorted by Tamer"]  = "Sorted by Tamer",
    ["Exotic Only"]     = "Exotic Only",
    ["Duplicates Only"] = "Duplicates Only",

    ["All Specs"]    = "All Specs",
    ["All Hunters"]  = "All Hunters",
    ["All Families"] = "All Families",
    ["All Exotic Families"]     = "All Exotic Families",
    ["All Non-Exotic Families"] = "All Non-Exotic Families",

    ["Slot - sort by stable slot number"]      = "Slot - sort by stable slot number",
    ["Model - sort by display ID"]             = "Model - sort by display ID",
    ["Family - sort alphabetically by family"] = "Family - sort alphabetically by family",
    ["Spec - sort alphabetically by spec"]     = "Spec - sort alphabetically by spec",
    ["Tamer - sort alphabetically by owner"]   = "Tamer - sort alphabetically by owner",
    ["Unsorted - default order"]               = "Unsorted - default order",
    ["Custom drag-and-drop reordering in"]     = "Custom drag-and-drop reordering in",
    ["Grouped view requires Unsorted."]        = "Grouped view requires Unsorted.",

    -- What the Reset Filters tooltip promises it will do.
    ["All Specs selected"]    = "All Specs selected",
    ["All Families selected"] = "All Families selected",
    ["All Hunters selected"]  = "All Hunters selected",
    ["Tamer: kept on current hunter"] = "Tamer: kept on current hunter",
    ["Exotic Only: OFF"]     = "Exotic Only: OFF",
    ["Duplicates Only: OFF"] = "Duplicates Only: OFF",
    ["Clear search box"]     = "Clear search box",
    ["Sort by: Unsorted"]    = "Sort by: Unsorted",

    ["Export Pet Data (CSV)"] = "Export Pet Data (CSV)",
    ["Select All"]  = "Select All",
    ["How to Copy"] = "How to Copy",
    ["Select the columns to export, then copy the text below and paste it into a .csv file or spreadsheet"] =
        "Select the columns to export, then copy the text below and paste it into a .csv file or spreadsheet",
    ["Exporting %d pets (%d total lines including header)"] =
        "Exporting %d pets (%d total lines including header)",
    ["To copy the CSV data:"] = "|cFFFFD700Pet Stable Management:|r To copy the CSV data:",
    ["1. Click 'Select All' button"] = "|cFF00FF001.|r Click 'Select All' button",
    ["2. Press Ctrl+C (Cmd+C on Mac) to copy"] = "|cFF00FF002.|r Press Ctrl+C (Cmd+C on Mac) to copy",
    ["3. Paste into Excel, Google Sheets, or a text editor"] =
        "|cFF00FF003.|r Paste into Excel, Google Sheets, or a text editor",
    ["4. Save as .csv file if needed"] = "|cFF00FF004.|r Save as .csv file if needed",

    -- Grouped view: group menus, headers, drag hints
    ["Group"]      = "Group",
    ["New Group"]  = "New Group",
    ["Ungrouped"]  = "Ungrouped",
    ["Expand All Groups"]   = "Expand All Groups",
    ["Collapse All Groups"] = "Collapse All Groups",
    ["Create New Group..."] = "Create New Group...",
    ["Rename Group"]        = "Rename Group",
    ["Move pet to group:"]  = "Move pet to group:",
    ["Auto-create groups by:"] = "Auto-create groups by:",
    ["Exotic"]        = "Exotic",
    ["Owner (Tamer)"] = "Owner (Tamer)",

    ["(%d pet)"]  = "(%d pet)",
    ["(%d pets)"] = "(%d pets)",

    ["Failed to create group"] = "Failed to create group",
    ["Failed to rename group"] = "Failed to rename group",
    ["Failed to delete group"] = "Failed to delete group",
    ["Failed to move pet to group"] = "Failed to move pet to group",

    ["Reordering disabled while sorting is active."] =
        "|cFFFF8800Reordering disabled while sorting is active.|r",
    ["Set Sort by to Unsorted to re-enable."] =
        "|cFFFF8800Set Sort by to Unsorted to re-enable.|r",
    ["Shift/Ctrl + drag to reorder within group (works outside stable)"] =
        "Shift/Ctrl + drag to reorder within group (works outside stable)",
    ["Shift/Ctrl + Right-click to move to a specific group"] =
        "Shift/Ctrl + Right-click to move to a specific group",
    ["Shift/Ctrl + drag to swap stable slots"] =
        "Shift/Ctrl + drag to swap stable slots",

    -- Dialog defaults and confirmations. These were missed by the first pass: a scan for
    -- `title = "..."` cannot see `options.title or "..."` or an isRename ternary.
    ["Dialog"]  = "Dialog",
    ["Confirm"] = "Confirm",
    ["Yes"]     = "Yes",
    ["Apply"]   = "Apply",
    ["Delete"]  = "Delete",
    ["Create"]  = "Create",
    ["Rename"]  = "Rename",
    ["Are you sure?"]    = "Are you sure?",
    ["Unknown Pet"]      = "Unknown Pet",
    ["Enter Team Name"]  = "Enter Team Name",
    ["Create New Group"] = "Create New Group",
    ["Enter a name for the new group:"]  = "Enter a name for the new group:",
    ["Enter a new name for the group:"]  = "Enter a new name for the group:",

    ["Are you sure you want to delete the team\n'%s'?\n\nThis action cannot be undone."] =
        "Are you sure you want to delete the team\n'%s'?\n\nThis action cannot be undone.",
    ["Are you sure you want to delete the group\n'%s'?\n\nAll pets in this group will be moved to Ungrouped."] =
        "Are you sure you want to delete the group\n'%s'?\n\nAll pets in this group will be moved to Ungrouped.",
    ["Apply team '%s' to your active pet slots?\n\nThis will rearrange your pets in slots 1-6."] =
        "Apply team '%s' to your active pet slots?\n\nThis will rearrange your pets in slots 1-6.",

    -- Teams panel
    ["Pet Teams"]        = "Pet Teams",
    ["Team Name"]        = "Team Name",
    ["Unnamed Team"]     = "Unnamed Team",
    ["Search teams..."]  = "Search teams...",
    ["Remove from Team"] = "Remove from Team",
    ["Copy"]      = "Copy",
    ["Duplicate"] = "Duplicate",
    ["Rename Team"]    = "Rename Team",
    ["Duplicate Team"] = "Duplicate Team",
    ["%s (Copy)"]      = "%s (Copy)",
    ["Enter a new name for '%s':"]         = "Enter a new name for '%s':",
    ["Enter a name for the copy of '%s':"] = "Enter a name for the copy of '%s':",

    ["%d/6 pets • Modified: %s"] = "%d/6 pets • Modified: %s",
    ["%d team(s) saved"]       = "%d team(s) saved",
    ["%d of %d team(s) match"] = "%d of %d team(s) match",
    ["No teams match your search."] = "No teams match your search.",
    ["No teams saved yet.\nCreate your teams at the Stable Master \nor by adding pets from the Owned Pets panel."] =
        "No teams saved yet.\nCreate your teams at the Stable Master \nor by adding pets from the Owned Pets panel.",

    ["Slot %s (Companion)"] = "Slot %s (Companion)",
    ["Slot %s (Active)"]    = "Slot %s (Active)",
    ["Drag to rearrange\nHover + X to remove"] = "Drag to rearrange\nHover + X to remove",

    ["Visit a Stable Master to apply teams"] = "Visit a Stable Master to apply teams",
    ["You must be at a Stable Master to apply a team."] =
        "|cFFFF8800PetStableManagement: You must be at a Stable Master to apply a team.|r",
    ["Failed to apply team"]     = "Failed to apply team",
    ["Failed to rename team"]    = "Failed to rename team",
    ["Failed to duplicate team"] = "Failed to duplicate team",
    ["Failed to delete team"]    = "Failed to delete team",

    -- Dialog titles passed positionally to CreateBaseDialog, and the delete-all prompt.
    ["Save Pet Team"]   = "Save Pet Team",
    ["Add Pet to Team"] = "Add Pet to Team",
    ["Duplicate Pet"]   = "Duplicate Pet",
    ["Select Slot"]     = "Select Slot",
    ["Delete All"]      = "Delete All",
    ["Are you sure you want to delete ALL groups?\n\nAll pets will be moved to Ungrouped.\nThis action cannot be undone."] =
        "Are you sure you want to delete ALL groups?\n\nAll pets will be moved to Ungrouped.\nThis action cannot be undone.",

    -- Models Browser: panel chrome, NPC table columns, ability browser
    ["Pet Ability Browser"] = "Pet Ability Browser",
    ["Show Only"]  = "Show Only",
    ["Previous"]   = "Previous",
    ["Next"]       = "Next",
    ["Page %d of %d"] = "Page %d of %d",
    ["Models view"] = "Models view",
    ["NPC view"]    = "NPC view",
    ["Search NPCs..."]      = "Search NPCs...",
    ["Search models..."]    = "Search models...",
    ["Search abilities..."] = "Search abilities...",

    -- NPC table column headers. Each has a fixed pixel width, so a longer translation
    -- clips; Widgets.truncatedLabels reports it rather than hiding it.
    ["ID"]          = "ID",
    ["Name"]        = "Name",
    ["Class"]       = "Class",
    ["NK"]          = "NK",
    ["Zone"]        = "Zone",
    ["Continent"]   = "Continent",
    ["Expansion"]   = "Expansion",
    ["A/H"]         = "A/H",
    ["Note"]        = "Note",
    ["Display IDs"] = "Display IDs",
    ["Columns"]     = "Columns",

    ["NPC ID: %s"]     = "NPC ID: %s",
    ["Display IDs: "]  = "Display IDs: ",
    [" (owned)"]       = " (owned)",
    ["%s - %s, %s"]    = "%s - %s, %s",
    ["Your note:"]     = "Your note:",
    ["Info note:"]     = "Info note:",
    ["Click to add a note"] = "Click to add a note",

    ["Unselect All"]     = "Unselect All",
    ["Apply Filters"]    = "Apply Filters",
    ["Available from:"]  = "Available from:",
    ["Any pet with %s spec"] = "Any pet with %s spec",
    ["Show less"]        = "Show less",
    ["and %d more..."]   = "and %d more...",
    ["%d ability selected"]   = "%d ability selected",
    ["%d abilities selected"] = "%d abilities selected",
    ["Filter applied - %d families from selected abilities."] =
        "PetStableManagement: Filter applied - %d families from selected abilities.",

    -- Models Browser filter bar and its summary line
    ["Pet Roulette"]    = "Pet Roulette",
    ["Special Tames"]   = "Special Tames",
    ["Ability Browser"] = "Ability Browser",
    ["Loading..."]      = "Loading...",
    ["Current Zone"]    = "Current Zone",
    ["Expand All Continents"]   = "Expand All Continents",
    ["Collapse All Continents"] = "Collapse All Continents",

    ["Rares"]           = "Rares",
    ["Favorites"]       = "Favorites",
    ["Name Keepers"]    = "Name Keepers",
    ["Owned"]           = "Owned",
    ["Pets in My Zone"] = "Pets in My Zone",
    ["Families"]        = "Families",
    ["Expansions"]      = "Expansions",
    ["Locations"]       = "Locations",
    ["Search"]          = "Search",

    -- Each summary entry is a whole string. The only composition left is "Not %s" over a
    -- rule or condition label that comes from the data, so its wording cannot be a key.
    ["Not %s"]              = "Not %s",
    ["Not Rares"]           = "Not Rares",
    ["Not Favorites"]       = "Not Favorites",
    ["Not Name Keepers"]    = "Not Name Keepers",
    ["Not Owned"]           = "Not Owned",
    ["My Zone (%s)"]        = "My Zone (%s)",
    ["Not My Zone (%s)"]    = "Not My Zone (%s)",
    ["Families (Exotic only)"] = "Families (Exotic only)",
    ["Families (not Exotic)"]  = "Families (not Exotic)",
    ["Abilities (%d families)"] = "Abilities (%d families)",
    ["Multiple Skills"]     = "Multiple Skills",
    ["Multiple Conditions"] = "Multiple Conditions",
    ["Special Tames - %s"]  = "Special Tames - %s",
    ["Filters: %s"]         = "Filters: %s",

    -- Reset Filters tooltip
    ["All Expansions selected"] = "All Expansions selected",
    ["All Locations selected"]  = "All Locations selected",
    ["Rares: OFF"]           = "Rares: OFF",
    ["Favorites: OFF"]       = "Favorites: OFF",
    ["Pets in My Zone: OFF"] = "Pets in My Zone: OFF",
    ["Owned: OFF"]           = "Owned: OFF",
    ["Return to first page"] = "Return to first page",
})
