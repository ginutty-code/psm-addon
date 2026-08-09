-- Export.lua
-- Export functionality for PetStableManagement

local addonName = "PetStableManagement"

_G.PSM = _G.PSM or {}
local PSM = _G.PSM

PSM.Export = {}

-- Single source of truth for all exportable columns.
-- GenerateCSV and ShowExportDialog both reference this table.
local ALL_COLUMNS = {
    {key = "slotID",          label = "Slot"},
    {key = "name",            label = "Name"},
    {key = "displayID",       label = "Display ID"},
    {key = "petNumber",       label = "Pet Number"},
    {key = "petLevel",        label = "Level"},
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

function PSM.Export:EscapeCSVField(field)
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

function PSM.Export:GenerateCSV(selectedColumns)
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
    local sorted = {unpack(PSM.state.stablePets)}
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
    local csv = PSM.Export:GenerateCSV(frame.selectedColumns)
    frame.editBox:SetText(csv)
    frame.editBox:SetCursorPosition(0)

    local lines = CountLines(csv)
    frame.petCount:SetText(string.format(
        "Exporting %d pets (%d total lines including header)", lines - 1, lines
    ))
end

local function CreateCheckboxSection(frame)
    frame.checkboxes = {}
    frame.selectedColumns = PSM.Export:GetDefaultSelectedColumns()

    local y, x, col = -50, 20, 0
    for i, def in ipairs(ALL_COLUMNS) do
        local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", x, y)
        cb:SetChecked(frame.selectedColumns[def.key])
        cb:SetScript("OnClick", function(self)
            frame.selectedColumns[def.key] = self:GetChecked()
            RefreshExportContent(frame)
        end)

        local lbl = cb:CreateFontString(nil, "OVERLAY")
        lbl:SetFont("Fonts\\FRIZQT__.TTF", 9)
        lbl:SetPoint("LEFT", cb, "RIGHT", 5, 0)
        lbl:SetText(def.label)
        lbl:SetTextColor(0.9, 0.9, 0.9)

        table.insert(frame.checkboxes, cb)

        col = col + 1
        if col >= 5 then
            col, y, x = 0, y - 20, 20
        else
            x = x + 110
        end
    end

    -- Return the Y offset after the last checkbox row
    return y
end

local function CreateEditBoxSection(frame, topY)
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 20, topY - 20)
    scrollFrame:SetPoint("BOTTOMRIGHT", -40, 80)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetMaxLetters(0)
    editBox:SetFontObject(GameFontHighlightSmall)
    editBox:SetWidth(scrollFrame:GetWidth() - 20)
    editBox:SetAutoFocus(false)
    editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
    scrollFrame:SetScrollChild(editBox)
    PSM.UI:ApplyElvUISkin(editBox, "editbox")
    PSM.UI:ApplyElvUISkin(scrollFrame.ScrollBar, "scrollbar")

    -- Background behind edit box
    local bg = CreateFrame("Frame", nil, scrollFrame, "BackdropTemplate")
    bg:SetPoint("TOPLEFT",     scrollFrame, "TOPLEFT",     -5,  5)
    bg:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT",  5, -5)
    bg:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = {left=4, right=4, top=4, bottom=4}
    })
    bg:SetBackdropColor(0.1, 0.1, 0.1, PSM.Config:GetOpacity())
    bg:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    bg:SetFrameLevel(scrollFrame:GetFrameLevel() - 1)

    frame.editBox = editBox
end

local function CreateBottomBar(frame)
    local petCount = frame:CreateFontString(nil, "OVERLAY")
    petCount:SetFont("Fonts\\FRIZQT__.TTF", 11)
    petCount:SetPoint("BOTTOM", 0, 50)
    petCount:SetTextColor(0.7, 0.9, 1)
    frame.petCount = petCount

    local selectAllBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    selectAllBtn:SetSize(100, 25)
    selectAllBtn:SetPoint("BOTTOM", -55, 15)
    selectAllBtn:SetText("Select All")
    selectAllBtn:SetScript("OnClick", function()
        frame.editBox:SetFocus()
        frame.editBox:HighlightText()
    end)
    PSM.UI:ApplyElvUISkin(selectAllBtn, "button")

    local helpBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    helpBtn:SetSize(100, 25)
    helpBtn:SetPoint("BOTTOM", 55, 15)
    helpBtn:SetText("How to Copy")
    helpBtn:SetScript("OnClick", function()
        print("|cFFFFD700Pet Stable Management:|r To copy the CSV data:")
        print("|cFF00FF001.|r Click 'Select All' button")
        print("|cFF00FF002.|r Press Ctrl+C (Cmd+C on Mac) to copy")
        print("|cFF00FF003.|r Paste into Excel, Google Sheets, or a text editor")
        print("|cFF00FF004.|r Save as .csv file if needed")
    end)
    PSM.UI:ApplyElvUISkin(helpBtn, "button")
end

function PSM.Export:ShowExportDialog()
    -- Reuse existing frame if already open
    if PSM.state.exportFrame then
        local f = PSM.state.exportFrame
        RefreshExportContent(f)
        f:Show()
        f:Raise()
        return
    end

    local frame = CreateFrame("Frame", "PetStableExportFrame", UIParent, "BackdropTemplate")
    frame:SetSize(600, 600)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(100)
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then self:Hide() end
    end)
    frame:EnableKeyboard(true)

    frame:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = {left=4, right=4, top=4, bottom=4}
    })
    frame:SetBackdropColor(0, 0, 0, PSM.Config:GetOpacity())
    PSM.UI:ApplyElvUISkin(frame, "frame")

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -5, -5)
    closeButton:SetScript("OnClick", function() frame:Hide() end)
    PSM.UI:ApplyElvUISkin(closeButton, "closebutton")

    local title = frame:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Export Pet Data (CSV)")
    title:SetTextColor(1, 0.82, 0)

    local instructions = frame:CreateFontString(nil, "OVERLAY")
    instructions:SetFont("Fonts\\FRIZQT__.TTF", 10)
    instructions:SetPoint("TOP", title, "BOTTOM", 0, -10)
    instructions:SetText("Select the columns to export, then copy the text below and paste it into a .csv file or spreadsheet")
    instructions:SetTextColor(0.8, 0.8, 0.8)

    local checkboxBottomY = CreateCheckboxSection(frame)
    CreateEditBoxSection(frame, checkboxBottomY)
    CreateBottomBar(frame)

    table.insert(UISpecialFrames, "PetStableExportFrame")
    PSM.state.exportFrame = frame

    RefreshExportContent(frame)
    frame:Show()
end

function PSM.Export:GetDefaultSelectedColumns()
    local selected = {}
    for _, col in ipairs(ALL_COLUMNS) do
        selected[col.key] = true
    end
    return selected
end