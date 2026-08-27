-- Export.lua
-- Export functionality for PetStableManagement

local _, ns = ...

ns.Export = {}

-- Single source of truth for all exportable columns.
-- GenerateCSV and ShowExportDialog both reference this table.
local ALL_COLUMNS = {
    {key = "slotID",          label = "Slot"},
    {key = "name",            label = "Name"},
    {key = "displayID",       label = "Display ID"},
    {key = "petNumber",       label = "Pet Number"},
    {key = "level",           label = "Level"},
    {key = "familyName",      label = "Family"},
    {key = "specName",        label = "Specialization"},
    {key = "specID",          label = "Spec ID"},
    {key = "isExotic",        label = "Is Exotic"},
    {key = "isActive",        label = "Is Active (slots 1-5)"},
    {key = "tamer",           label = "Tamer"},
    {key = "specAbilities",   label = "Spec Abilities"},
    {key = "petAbilities",    label = "Pet Abilities"},
}

-- Keys that map to grouped ability buckets rather than raw pet fields.
local ABILITY_KEYS = {
    specAbilities = "spec",
    petAbilities  = "pet",
}

-- ─── Helpers ──────────────────────────────────────────────────────────────────

function ns.Export:EscapeCSVField(field)
    if not field then return "" end
    local str = tostring(field)
    if str:find('[,"\n]') then
        str = '"' .. str:gsub('"', '""') .. '"'
    end
    return str
end

-- Returns a table of grouped ability strings for a single pet.
-- Keys: spec, family, pet, unknown — each a semicolon-joined string (or "").
local function ExtractAbilities(pet)
    local groups = {spec = "", family = "", pet = "", unknown = ""}
    if type(pet.abilities) ~= "table" then return groups end

    if pet.abilities.spec or pet.abilities.family or pet.abilities.pet or pet.abilities.unknown then
        -- Already grouped
        for bucket in pairs(groups) do
            if pet.abilities[bucket] then
                groups[bucket] = table.concat(pet.abilities[bucket], "; ")
            end
        end
    else
        -- Flat list — put everything in "pet"
        local names = {}
        for _, ability in ipairs(pet.abilities) do
            table.insert(names, type(ability) == "table" and ability.name or tostring(ability))
        end
        groups.pet = table.concat(names, "; ")
    end

    return groups
end

-- Counts newline-delimited lines in a string.
local function CountLines(str)
    local n = 0
    for _ in str:gmatch("[^\n]+") do n = n + 1 end
    return n
end

-- ─── CSV generation ───────────────────────────────────────────────────────────

function ns.Export:GenerateCSV(selectedColumns)
    local lines = {}

    -- Header
    local header = {}
    for _, col in ipairs(ALL_COLUMNS) do
        if selectedColumns[col.key] then
            table.insert(header, col.label)
        end
    end
    table.insert(lines, table.concat(header, ","))

    -- Sort pets by slot
    local sorted = {unpack(ns.state.stablePets)}
    table.sort(sorted, function(a, b)
        return (a.slotID or 999) < (b.slotID or 999)
    end)

    -- Data rows
    for _, pet in ipairs(sorted) do
        local abilities = ExtractAbilities(pet)
        local row = {}

        for _, col in ipairs(ALL_COLUMNS) do
            if selectedColumns[col.key] then
                local value

                if col.key == "isExotic" then
                    value = pet.isExotic and "Yes" or "No"
                elseif col.key == "isActive" then
                    value = (pet.slotID and pet.slotID <= 5) and "Active" or "Stabled"
                elseif ABILITY_KEYS[col.key] then
                    value = abilities[ABILITY_KEYS[col.key]]
                else
                    value = pet[col.key] or ""
                end

                table.insert(row, self:EscapeCSVField(value))
            end
        end

        table.insert(lines, table.concat(row, ","))
    end

    return table.concat(lines, "\n")
end

-- ─── Export dialog ────────────────────────────────────────────────────────────

-- Updates editBox text and the pet-count label from freshly generated CSV.
local function RefreshExportContent(frame)
    local csv = ns.Export:GenerateCSV(frame.selectedColumns)
    frame.editBox:SetText(csv)
    frame.editBox:SetCursorPosition(0)

    local lines = CountLines(csv)
    frame.petCount:SetText(ns.L("Exporting %d pets (%d total lines including header)",
        lines - 1, lines))
end

local COLUMN_PITCH  = 110
local COLUMNS_PER_ROW = 5

local function CreateCheckboxSection(frame)
    frame.checkboxes = {}
    frame.selectedColumns = ns.Export:GetDefaultSelectedColumns()

    local y, x, col = -50, 20, 0
    for _, def in ipairs(ALL_COLUMNS) do
        table.insert(frame.checkboxes, ns.Widgets.CheckBox(frame, {
            point           = { "TOPLEFT", x, y },
            checked         = frame.selectedColumns[def.key],
            label           = def.label,
            labelFontSize   = ns.Theme.SIZE.TINY,
            labelColor      = { 0.9, 0.9, 0.9 },
            onClick         = function(self)
                frame.selectedColumns[def.key] = self:GetChecked()
                RefreshExportContent(frame)
            end,
        }))

        col = col + 1
        if col >= COLUMNS_PER_ROW then
            col, y, x = 0, y - ns.Theme.CONTROL.CHECKBOX_ROW, 20
        else
            x = x + COLUMN_PITCH
        end
    end

    -- Return the Y offset after the last checkbox row
    return y
end

local function CreateEditBoxSection(frame, topY)
    local Widgets = ns.Widgets

    local scrollFrame = Widgets.Frame(frame, {
        frameType = "ScrollFrame",
        template  = "UIPanelScrollFrameTemplate",
        skin      = "scrollframe",
        point     = {
            { "TOPLEFT",      20, topY - 20 },
            { "BOTTOMRIGHT", -40, 80 },
        },
    })
    ns.Skin.Apply(scrollFrame.ScrollBar, "scrollbar")

    local editBox = Widgets.EditBox(scrollFrame, {
        multiline  = true,
        fontObject = "GameFontHighlightSmall",
        width      = scrollFrame:GetWidth() - 20,
        closes     = frame,
    })
    editBox:SetMaxLetters(0)
    scrollFrame:SetScrollChild(editBox)

    -- Background behind edit box
    frame.editBg = Widgets.Frame(scrollFrame, {
        backdrop    = "TOOLTIP",
        color       = { 0.1, 0.1, 0.1, ns.Config:GetOpacity() },
        borderColor = { 0.4, 0.4, 0.4, 1 },
        level       = scrollFrame:GetFrameLevel() - 1,
        point       = {
            { "TOPLEFT",     scrollFrame, "TOPLEFT",     -5,  5 },
            { "BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT",  5, -5 },
        },
    })

    frame.editBox = editBox
end

local function CreateBottomBar(frame)
    local Widgets = ns.Widgets

    frame.petCount = Widgets.Label(frame, {
        fontSize = ns.Theme.SIZE.BODY,
        color    = { 0.7, 0.9, 1 },
        point    = { "BOTTOM", 0, 50 },
    })

    Widgets.Button(frame, {
        width   = ns.Theme.CONTROL.BUTTON_W.M,
        point   = { "BOTTOM", -55, 15 },
        text    = ns.L("Select All"),
        onClick = function()
            frame.editBox:SetFocus()
            frame.editBox:HighlightText()
        end,
    })

    Widgets.Button(frame, {
        width   = ns.Theme.CONTROL.BUTTON_W.M,
        point   = { "BOTTOM", 55, 15 },
        text    = ns.L("How to Copy"),
        onClick = function()
            print(ns.L("To copy the CSV data:"))
            print(ns.L("1. Click 'Select All' button"))
            print(ns.L("2. Press Ctrl+C (Cmd+C on Mac) to copy"))
            print(ns.L("3. Paste into Excel, Google Sheets, or a text editor"))
            print(ns.L("4. Save as .csv file if needed"))
        end,
    })
end

function ns.Export:ShowExportDialog()
    if ns.PanelManager:CombatBlocked(ns.L("Export Pet Data")) then return end

    -- Reuse existing frame if already open
    if ns.state.exportFrame then
        local f = ns.state.exportFrame
        RefreshExportContent(f)
        f:Show()
        f:Raise()
        return
    end

    local Widgets = ns.Widgets

    local frame = Widgets.MovableFrame(UIParent, {
        name   = "PetStableExportFrame",
        size   = { 600, 600 },
        point  = { "CENTER" },
        strata = "DIALOG",
        level  = 100,
        skin   = "frame",
    })
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)

    -- Own translucent backdrop on a separate, unskinned child -- same split as
    -- PanelManager's panel.border and Menu.lua's window.border. ElvUI's "frame" skin
    -- above re-templates whatever frame it's given, so a backdrop set directly on the
    -- skinned frame gets fought by it and stops tracking the opacity slider; every
    -- other panel avoids that by keeping the addon-colored backdrop off the skinned
    -- frame entirely.
    frame.border = Widgets.Frame(frame, {
        allPoints = true,
        backdrop  = "TOOLTIP",
        -- Wider tile than the default preset: this dialog is 600px of flat
        -- background and a 16px tile visibly repeats across it.
        backdropOverrides = { tileSize = 32 },
        color             = { 0, 0, 0, ns.Config:GetOpacity() },
        level             = frame:GetFrameLevel() - 1,
    })

    -- Was EnableKeyboard(true) plus a bare OnKeyDown, with no
    -- SetPropagateKeyboardInput -- which meant this dialog swallowed *every*
    -- keypress while open, not just Escape, leaving the player's keybinds dead.
    -- CloseOnEscape propagates everything except Escape.
    Widgets.CloseOnEscape(frame)

    Widgets.CloseButton(frame, { point = { "TOPRIGHT", -5, -5 } })

    local title = Widgets.Label(frame, {
        fontSize = ns.Theme.SIZE.HEADING,
        outline  = true,
        color    = ns.Theme.COLOR.GOLD,
        point    = { "TOP", 0, -15 },
        text     = ns.L("Export Pet Data (CSV)"),
    })

    Widgets.Label(frame, {
        fontSize = ns.Theme.SIZE.SMALL,
        color    = ns.Theme.COLOR.MUTED,
        point    = { "TOP", title, "BOTTOM", 0, -10 },
        text     = ns.L("Select the columns to export, then copy the text below and paste it into a .csv file or spreadsheet"),
    })

    local checkboxBottomY = CreateCheckboxSection(frame)
    CreateEditBoxSection(frame, checkboxBottomY)
    CreateBottomBar(frame)

    table.insert(UISpecialFrames, "PetStableExportFrame")
    ns.state.exportFrame = frame

    RefreshExportContent(frame)
    frame:Show()
end

function ns.Export:GetDefaultSelectedColumns()
    local selected = {}
    for _, col in ipairs(ALL_COLUMNS) do
        selected[col.key] = true
    end
    return selected
end