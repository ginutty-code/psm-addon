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
    -- Keys are the plain sentence, and now so are almost all the values: colour and
    -- the addon's own name used to be baked into the value here, one escape-code
    -- spelling per author. Both are applied once now, by ns.Utils:Msg at the print()
    -- call site, so every value below that reaches chat is plain text. See Backlog.md.
    ["StableFrame not found!"]                        = "StableFrame not found!",
    ["Panel creation failed!"]                        = "Panel creation failed!",
    ["Panel failed to show!"]                         = "Panel failed to show!",
    ["No available slots to displace pet from slot 1!"] = "No available slots to displace pet from slot 1!",
    ["No available stable slots found! (Max 205 slots)"] = "No available stable slots found! (Max 205 slots)",

    ["Pet data snapshot created: %d pets saved."]     = "Pet data snapshot created: %d pets saved.",
    ["No snapshot available. Please visit a Stable Master to collect your owned pets data."] =
        "No snapshot available. Please visit a Stable Master to collect your owned pets data.",
    ["Loaded. Use /psm or /petstable or click the minimap button to toggle the panel."] =
        "Loaded. Use /psm or /petstable or click the minimap button to toggle the panel.",

    -- Shared with the Models Browser, which reaches them through PSM.L.
    ["Reset Filters"]     = "Reset Filters",
    ["Reset all filters"] = "Reset all filters",
    ["Pet Model Browser"] = "Pet Model Browser",

    -- One combat-block message for every PSM window (PanelManager:CombatBlocked),
    -- %s filled with the window's own name -- used to be four near-identical keys,
    -- one per panel, each written (and coloured) separately. See Backlog.md.
    ["%s cannot open during combat."] = "%s cannot open during combat.",

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
        "Cannot add duplicate pet '%s' to team '%s'. Pet already exists at slot %s.",
    ["Added '%s' to team '%s' at slot %s."] =
        "Added '%s' to team '%s' at slot %s.",
    ["Removed %s from team '%s'."] =
        "Removed %s from team '%s'.",

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
        "%s waypoint(s) added on %s map for %s",
    ["Only the first location was marked. Install TomTom for all waypoints, portrait icons, and navigation."] =
        "Only the first location was marked. Install TomTom for all waypoints, portrait icons, and navigation.",

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
    -- Short form, for CombatBlocked's "Pet Stable Management: %s cannot open during
    -- combat." -- the dialog title above already carries the "(CSV)" qualifier that
    -- message doesn't need.
    ["Export Pet Data"] = "Export Pet Data",
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
        "You must be at a Stable Master to apply a team.",
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
    ["Tools"]      = "Tools",
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
        "Filter applied - %d families from selected abilities.",

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

    -- Owned pets panel chrome, row controls and slash commands
    ["Pet Stable Management"]        = "Pet Stable Management",
    ["Pet Stable Management (Live)"] = "Pet Stable Management (Live)",
    ["Move Up"]   = "Move Up",
    ["Move Down"] = "Move Down",
    ["Showing: %d pets"]              = "Showing: %d pets",
    ["Same-char: %d models (%d pets)"]  = "Same-char: %d models (%d pets)",
    ["Cross-char: %d models (%d pets)"] = "Cross-char: %d models (%d pets)",

    ["Magnify Model"]       = "Magnify Model",
    ["Add to Team"]         = "Add to Team",
    ["Favorite/Unfavorite"] = "Favorite/Unfavorite",
    ["Left-click and drag to rotate"] = "Left-click and drag to rotate",
    ["Right-click and drag to move (left/right, up/down)"] =
        "Right-click and drag to move (left/right, up/down)",
    ["Scroll to zoom"] = "Scroll to zoom",

    ["Team '%s' is already up to date."] =
        "Team '%s' is already up to date.",
    ["You must be at a Stable Master to save a team."] =
        "You must be at a Stable Master to save a team.",
    ["No pets in slots 1-6 to save."] =
        "No pets in slots 1-6 to save.",
    ["No owned pets data available! Please visit a Stable Master."] =
        "No owned pets data available! Please visit a Stable Master.",
    ["C_StableInfo.SetPetSlot not available."] =
        "C_StableInfo.SetPetSlot not available.",
    ["Failed to capture current slots"] = "Failed to capture current slots",
    ["Failed to update team"]           = "Failed to update team",

    -- Slash commands. The command names inside these stay literal: /psm and /petswap are
    -- typed, not read, so translating them would break the instruction.
    ["Minimap button shown."] = "Minimap button shown.",
    ["Minimap button hidden. Use /psm show to show it again."] =
        "Minimap button hidden. Use /psm show to show it again.",
    ["Usage: /petswap [starting slot] [destination slot]"] =
        "Usage: /petswap [starting slot] [destination slot]",
    ["Example: /petswap 5 10"]  = "Example: /petswap 5 10",
    ["Slot numbers must be between 1 and %d."] =
        "Slot numbers must be between 1 and %d.",
    ["Source and destination slots are the same."] =
        "Source and destination slots are the same.",
    ["You must be at a stable master to change pet slots."] =
        "You must be at a stable master to change pet slots.",
    ["No pet found in slot %d."] = "No pet found in slot %d.",
    ["Failed to move pet."]      = "Failed to move pet.",
    ["Error: %s Type /psm debug for details."] =
        "Error: %s Type /psm debug for details.",
    ["No errors recorded this session."] = "No errors recorded this session.",
    ["Last %d error(s), oldest first:"] = "Last %d error(s), oldest first:",

    -- /psm help. Reuses the exact "Toggle X" / "Show minimap button" strings the PSM
    -- Menu and Options panel already declare for the same actions (Menu.lua,
    -- OptionsPanel.lua) rather than writing new phrasing, so the two surfaces describe
    -- the same command identically instead of drifting the way chat messages did
    -- before ns.Utils:Msg. Only the four entries below with no existing counterpart
    -- (Menu itself, and help/debug/petswap, which have no button to match) are new.
    ["Available commands:"] = "Available commands:",
    ["Hide minimap button"] = "Hide minimap button",
    ["Toggle Menu"] = "Toggle Menu",
    ["Show recent errors"] = "Show recent errors",
    ["Show this list of commands"] = "Show this list of commands",
    ["Swap two stable pet slots"] = "Swap two stable pet slots",

    -- Options panel
    ["Show minimap button"]         = "Show minimap button",
    ["Open with the Stable window"] = "Open with the Stable window",
    ["Stop pet animations"]         = "Stop pet animations",
    ["Reset All Settings"]          = "Reset All Settings",
    ["Pet Model Settings"]          = "Pet Model Settings",
    ["Pets Per Column in Browser:"] = "Pets Per Column in Browser:",
    ["Pet Model Background:"]       = "Pet Model Background:",
    ["Simple"]        = "Simple",
    ["Stable Master"] = "Stable Master",
    ["Custom"]        = "Custom",

    ["UI Opacity:"] = "UI Opacity:",
    ["View Angle:"] = "View Angle:",
    ["Vertical Positioning (Z-axis):"]   = "Vertical Positioning (Z-axis):",
    ["Horizontal Positioning (Y-axis):"] = "Horizontal Positioning (Y-axis):",
    ["Opacity: %d%%"]             = "Opacity: %d%%",
    ["Zoom: %d%%"]                = "Zoom: %d%%",
    ["Vertical Position: %d%%"]   = "Vertical Position: %d%%",
    ["Horizontal Position: %d%%"] = "Horizontal Position: %d%%",
    ["View Angle: %d°"]         = "View Angle: %d°",

    -- Menu, panel chrome, row text and pet tooltip
    ["PSM Menu"]                     = "PSM Menu",
    ["Models Browser not available"] = "Models Browser not available",
    ["Toggle Owned Pets"]     = "Toggle Owned Pets",
    -- Short form, for CombatBlocked's "Pet Stable Management: %s cannot open during
    -- combat." -- the panel's own title is "Pet Stable Management" too, which the
    -- prefix already says, so the window itself needs a distinct short name here.
    ["Owned Pets"] = "Owned Pets",
    ["Toggle Models Browser"] = "Toggle Models Browser",
    ["Toggle Pet Roulette"]   = "Toggle Pet Roulette",
    ["Toggle Pet Teams"]      = "Toggle Pet Teams",
    ["Toggle Options"]        = "Toggle Options",
    ["Close All Panels"]      = "Close All Panels",
    -- Short form, for CombatBlocked's "Pet Stable Management: %s cannot open during
    -- combat." -- every other panel's short name is already its own title; the
    -- options window's only existing strings ("Toggle Options" etc.) carry the verb,
    -- not the noun alone.
    ["Options"] = "Options",

    ["Maximize"]      = "Maximize",
    ["Search..."]     = "Search...",
    ["%s is larger than your screen at the current UI scale (%dx%d needed, %dx%d available). You can drag it from any blank area to bring different parts into view, but it may not all fit on screen at once. Lowering your UI scale in the game's Options avoids this entirely."] =
        "%s is larger than your screen at the current UI scale (%dx%d needed, %dx%d available). You can drag it from any blank area to bring different parts into view, but it may not all fit on screen at once. Lowering your UI scale in the game's Options avoids this entirely.",
    ["Search pets..."] = "Search pets...",
    ["Showing: 0 pets  |  Duplicates: 0 pets (0 groups)"] =
        "Showing: 0 pets  |  Duplicates: 0 pets (0 groups)",

    ["Make Active"] = "Make Active",
    ["Companion"]   = "Companion",
    ["Stable"]      = "Stable",
    ["Release"]     = "Release",

    ["Family: %s"]    = "Family: %s",
    ["Spec: %s"]      = "Spec: %s",
    ["Owned by: %s"]  = "Owned by: %s",
    ["DisplayID: %d"] = "DisplayID: %d",
    ["Level: %s%d|r"] = "Level: %s%d|r",
    ["%s: %s%s"]      = "%s: %s%s",
    ["Slot %d: %s%s\nDisplayID: %d\n%s\n%s%s"] =
        "Slot %d: %s%s\nDisplayID: %d\n%s\n%s%s",

    -- Group and team errors a player can act on. Precondition failures like
    -- "Group ID is required" stay English: a player cannot cause or fix them, and a
    -- translator should not be handed an assertion.
    ["Group name is required"] = "Group name is required",
    ["New name is required"]   = "New name is required",
    ["A group with this name already exists"] = "A group with this name already exists",
    ["'Ungrouped' is a reserved group name"] = "'Ungrouped' is a reserved group name",
    ["Cannot delete the Ungrouped group"] = "Cannot delete the Ungrouped group",
    ["Cannot rename the Ungrouped group"] = "Cannot rename the Ungrouped group",

    ["Team name is required"] = "Team name is required",
    ["Cannot save empty team - at least one pet required"] =
        "Cannot save empty team - at least one pet required",
    ["Stable must be open to capture pet slots"] = "Stable must be open to capture pet slots",
    ["Stable must be open to apply a team"]      = "Stable must be open to apply a team",

    -- Values here are plain: TeamsData's Msg helper adds the colour and the addon prefix.
    ["Team '%s' saved successfully."]   = "Team '%s' saved successfully.",
    ["Team '%s' updated."]              = "Team '%s' updated.",
    ["Team '%s' deleted."]              = "Team '%s' deleted.",
    ["Team '%s' applied successfully."] = "Team '%s' applied successfully.",
    ["Team renamed from '%s' to '%s'."] = "Team renamed from '%s' to '%s'.",
    ["Team '%s' duplicated as '%s'."]   = "Team '%s' duplicated as '%s'.",
    ["Pet '%s' not found in stable"]    = "Pet '%s' not found in stable",
    ["Changed '%s' spec from %s to %s."] = "Changed '%s' spec from %s to %s.",
    ["No available stable slot to move pet '%s'!"] = "No available stable slot to move pet '%s'!",
    ["No available slot for pet swap!"] = "No available slot for pet swap!",
    ["The following pets need spec changes to match the saved team:"] =
        "The following pets need spec changes to match the saved team:",
    ["Summon the pet(s) that need spec change and click Apply again."] =
        "Summon the pet(s) that need spec change and click Apply again.",

    -- Stable-frame buttons, minimap tooltip, loader failure hints, browser empty states
    ["Teams List"] = "Teams List",
    ["Save Team"]  = "Save Team",
    ["View and manage saved pet teams"] = "View and manage saved pet teams",
    ["You have %d saved team(s)"]       = "You have %d saved team(s)",
    ["Save current pets in slots 1-6 as a team"] = "Save current pets in slots 1-6 as a team",

    ["Left-click: Toggle Owned Pets Panel"]     = "Left-click: Toggle Owned Pets Panel",
    ["Right-click: Toggle Pet Models Browser"]  = "Right-click: Toggle Pet Models Browser",
    ["Shift+Left-click: Toggle Menu"]           = "Shift+Left-click: Toggle Menu",
    ["Shift+Right-click: Toggle Options Panel"] = "Shift+Right-click: Toggle Options Panel",

    -- "Esc > AddOns" and "Interface/AddOns" are literal paths the player must follow.
    ["It is disabled in the AddOns list (Esc > AddOns)."] =
        "It is disabled in the AddOns list (Esc > AddOns).",
    ["A module it needs is disabled in the AddOns list (Esc > AddOns)."] =
        "A module it needs is disabled in the AddOns list (Esc > AddOns).",
    ["Its folder is missing from Interface/AddOns."] =
        "Its folder is missing from Interface/AddOns.",
    ["A module it needs is missing from Interface/AddOns."] =
        "A module it needs is missing from Interface/AddOns.",
    ["Reason: %s."] = "Reason: %s.",

    ["Display ID: %d"] = "Display ID: %d",
    ["No matching display IDs | 0 pages"] = "No matching display IDs | 0 pages",
    ["No matching NPCs | 0 pages"]        = "No matching NPCs | 0 pages",

    -- Messages the earlier scans could not see: their literal begins with a colour escape.
    ["Could not load the Models Browser. %s"] =
        "Could not load the Models Browser. %s",
    ["Can't load additional modules during combat."] =
        "Can't load additional modules during combat.",
    ["Failed to create panel."] = "Failed to create panel.",
    ["(No abilities available)"] = "|cFFAAAAAA(No abilities available)|r",

    -- One key for what used to be two identical copies, in Reorder.lua and DragDrop.lua.
    ["Must be at stable master to reorder pets"] = "Must be at stable master to reorder pets",
    ["Invalid slot numbers"] = "Invalid slot numbers",
    ["Slots must be between 1 and %s"] = "Slots must be between 1 and %s",
    ["Moving pet from slot %s to slot %s..."] = "Moving pet from slot %s to slot %s...",
    ["Pet is already in slot 1 (top position)"] = "Pet is already in slot 1 (top position)",
    ["Group '%s' created successfully."] = "Group '%s' created successfully.",

    ["Click magnifier button for further details."] =
        "|cff00ff00Click magnifier button for further details.|r",
    ["Pet Roulette: %s (Display ID: %d)"] = "Pet Roulette: %s (Display ID: %d)",
    ["No pets available for Pet Roulette."] = "No pets available for Pet Roulette.",
    ["No pet models available for Pet Roulette."] =
        "No pet models available for Pet Roulette.",

    -- Special Tames. Its PILL_TAGS stay English: the tab label is also the activeTag
    -- compared in RowMatchesTag, exactly like AbilityBrowser's.
    ["Invert All"] = "Invert All",
    ["Search tames..."] = "Search tames...",
    ["None"] = "None",
    ["Special Tames filter applied (%s)."] =
        "Special Tames filter applied (%s).",

    -- The remainder, found by an exhaustive scan rather than a shape-guessing one.
    ["Export"]   = "Export",
    ["Grouped"]  = "Grouped",
    ["Grid"]     = "Grid",
    ["List"]     = "List",
    ["Restore"]  = "Restore",
    ["Zoom:"]    = "Zoom:",
    ["NPCs:"]    = "NPCs:",

    -- Ability category tags. The colour is applied in code so one key serves both the
    -- plain label and the coloured prefix.
    ["[Spec]"]   = "[Spec]",
    ["[Family]"] = "[Family]",
    ["[Pet]"]    = "[Pet]",
    ["[Other]"]  = "[Other]",
    ["Abilities:"]  = "|cFFFFD700Abilities:|r",
    [" [Exotic]"]   = " |cffff8800[Exotic]|r",

    ["%s (to slot %s)"]    = "%s (to slot %s)",
    ["%s (Slot %s)"]       = "%s (Slot %s)",
    [" | Duplicates: %s"]  = " | Duplicates: %s",
    [" (using data from %s)"]     = " (using data from %s)",
    [" (using preserved data)"]   = " (using preserved data)",
    [" (no saved data available)"] = " (no saved data available)",

    ["No pet in slot %s"] = "No pet in slot %s",
    ["Pet is already in slot %s (bottom position)"] = "Pet is already in slot %s (bottom position)",
    ["Group '%s' deleted. Pets moved to Ungrouped."] = "Group '%s' deleted. Pets moved to Ungrouped.",
    ["Created %d group(s), moved %d pet(s)"] = "Created %d group(s), moved %d pet(s)",
    ["Deleted %d group(s)"] = "Deleted %d group(s)",
    ["  - '%s' (slot %s): %s -> %s"] = "  - '%s' (slot %s): %s -> %s",

    ["%d item selected"]  = "%d item selected",
    ["%d items selected"] = "%d items selected",
    ["%d owned by %s"]    = "%d owned by %s",
    ["%d display IDs | %d owned"] = "%d display IDs | %d owned",
    ["%d NPCs found | %d owned"]  = "%d NPCs found | %d owned",
    ["%d NPCs found | %d owned (%d including duplicates)"] =
        "%d NPCs found | %d owned (%d including duplicates)",

    -- One key for what RowManager.lua and GridView.lua each held a copy of.
    ["Shift/Ctrl + drag to reorder slot"] = "Shift/Ctrl + drag to reorder slot",
})
