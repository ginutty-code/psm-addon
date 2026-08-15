-- OwnedPets/Filters.lua
-- Filter controls for PetStableManagement

local addonName = "PetStableManagement"

_G.PSM = _G.PSM or {}
local PSM = _G.PSM

-- ─── Helpers ──────────────────────────────────────────────────────────────────

local function IsFamilyExotic(name) return PSM.Data.IsExoticFamily(name) end

-- Returns the joined text for a key→bool table, or fallback if empty.
local function DropdownText(tbl, fallback)
    if not next(tbl) then return fallback end
    local t = {}
    for k in pairs(tbl) do t[#t + 1] = k end
    return table.concat(t, ", ")
end

-- ─── Tri-state checkbox ────────────────────────────────────────────────────────

-- The order the three filter states cycle in. The *rendering* of each is
-- PSM.Widgets.CheckBox:SetTriState; what they mean and what follows what is this
-- file's business.
local function NextTriState(state)
    if state == nil  then return true      end
    if state == true then return "inverted" end
    return nil
end

-- A tri-state filter checkbox: off → include → exclude → off.
local function CreateFilterCheckbox(panel, opts)
    local cb = PSM.Widgets.CheckBox(panel, {
        point         = opts.point,
        label         = opts.label,
        labelFontSize = PSM.Theme.SIZE.SMALL,
    })

    -- Extends the clickable area rightward over the label text, so clicking the
    -- words toggles the box (a negative inset grows the hit rect).
    cb:SetHitRectInsets(0, -opts.labelHitWidth, 0, 0)

    cb:SetTriState(opts.initialState)
    cb:SetScript("OnClick", function(self)
        self:SetTriState(NextTriState(self.triState))
        opts.onChanged(self.triState)
    end)

    return cb
end

-- ─── Generic multi-select dropdown initialiser ────────────────────────────────
-- NOTE: `getItems` and `getStateTable` should be functions to avoid stale
-- references after table replacement (e.g. ClearMemory, LoadFilterSettings).
local function InitMultiDropdown(getItems, getStateTable, dropdown, allLabel, filterFn)
    UIDropDownMenu_Initialize(dropdown, function()
        local items      = type(getItems)      == "function" and getItems()      or getItems
        local stateTable = type(getStateTable) == "function" and getStateTable() or getStateTable
        local info = UIDropDownMenu_CreateInfo()
        info.text    = "  " .. allLabel
        info.value   = "ALL"
        info.checked = false
        info.func = function()
            PSM.Utils:ClearTable(getStateTable())
            UIDropDownMenu_SetText(dropdown, allLabel)
            PSM.C_Timer.After(0.1, function() PSM.UI:UpdatePanel() end)
        end
        UIDropDownMenu_AddButton(info)

        for _, item in ipairs(items) do
            if not filterFn or filterFn(item) then
                info = UIDropDownMenu_CreateInfo()  -- must reinitialize per item
                info.text             = "  " .. item
                info.value            = item
                info.checked          = stateTable[item] or false
                info.keepShownOnClick = true
                info.isNotRadio       = true
                info.func = function(_, _, _, checked)
                    local t = getStateTable()
                    t[item] = checked or nil
                    UIDropDownMenu_SetText(dropdown, DropdownText(t, allLabel))
                    PSM.C_Timer.After(0.1, function() PSM.UI:UpdatePanel() end)
                end
                UIDropDownMenu_AddButton(info)
            end
        end
    end)
    UIDropDownMenu_SetText(dropdown, DropdownText(getStateTable(), allLabel))
end

-- Returns the family dropdown's "all" label given the current exotic filter.
local function FamilyAllLabel()
    if PSM.state.exoticFilter == true then
        return "All Exotic Families"
    elseif PSM.state.exoticFilter == "inverted" then
        return "All Non-Exotic Families"
    end
    return "All Families"
end

local function InitFamilyDropdown(panel)
    local label = FamilyAllLabel()
    local filterFn
    if PSM.state.exoticFilter == true then
        filterFn = IsFamilyExotic
    elseif PSM.state.exoticFilter == "inverted" then
        filterFn = function(f) return not IsFamilyExotic(f) end
    end
    InitMultiDropdown(function() return PSM.state.familyList end,
                      function() return PSM.state.selectedFamilies end,
                      panel.familyDrop, label, filterFn)
end

-- ─── Sort dropdown ────────────────────────────────────────────────────────────

-- Maps PSM.state.sortBy → the label shown in the dropdown button.
local SORT_LABELS = {
    slot   = "Sorted by Slot",
    model  = "Sorted by Model",
    family = "Sorted by Family",
    spec   = "Sorted by Spec",
    tamer  = "Sorted by Tamer",
}

local function SortDropLabel()
    return SORT_LABELS[PSM.state.sortBy] or "Sort by"
end

local function InitSortDropdown(panel)
    local dropdown = panel.sortDrop
    UIDropDownMenu_Initialize(dropdown, function()
        local options = {
            { value = nil,     text = "Unsorted" },
            { value = "family",text = "Family"   },
            { value = "model", text = "Model"    },
            { value = "slot",  text = "Slot"     },
            { value = "spec",  text = "Spec"     },
            { value = "tamer", text = "Tamer"    },
        }
        for _, opt in ipairs(options) do
            local info      = UIDropDownMenu_CreateInfo()
            info.text       = "  " .. opt.text
            info.value      = opt.value
            info.checked    = (PSM.state.sortBy == opt.value)
            info.func       = function()
                PSM.state.sortBy = opt.value
                UIDropDownMenu_SetText(dropdown, SortDropLabel())
                -- Refresh checked state so the menu reflects the new selection
                -- if the user reopens it without closing the panel.
                UIDropDownMenu_Initialize(dropdown, dropdown.initialize, nil, 1)
                PSM.C_Timer.After(0.1, function() PSM.UI:UpdatePanel() end)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(dropdown, SortDropLabel())
end

-- ─── Public API ───────────────────────────────────────────────────────────────

function PSM.UI:BuildFilters(panel)
    local debouncedUpdate = PSM.Utils:Debounce(function()
        PSM.UI:UpdatePanel()
    end, PSM.Config.UPDATE_DELAY)

    local Widgets = PSM.Widgets
    local cfg  = PSM.Config
    local rowY = cfg.DROPDOWN_ROW_Y
    local step = cfg.DROPDOWN_SPACING

    -- All four are UIDropDownMenuTemplate frames of the same width, differing only
    -- in where they sit and how they are populated.
    local function Dropdown(name, point)
        local d = Widgets.Frame(panel, {
            name      = name,
            template  = "UIDropDownMenuTemplate",
            skin      = "dropdown",
            point     = point,
        })
        UIDropDownMenu_SetWidth(d, cfg.DROPDOWN_WIDTH)
        return d
    end

    panel.specDrop = Dropdown("PetDupSpecDrop", { "TOPLEFT", -10, rowY })
    InitMultiDropdown(function() return PSM.state.specList end,
                      function() return PSM.state.selectedSpecs end,
                      panel.specDrop, "All Specs")

    panel.familyDrop = Dropdown("PetDupFamilyDrop", { "TOPLEFT", step * 1 - 10, rowY })
    InitFamilyDropdown(panel)

    panel.tamerDrop = Dropdown("PetDupTamerDrop", { "TOPLEFT", step * 2 - 10, rowY })
    self:ReinitializeTamerDropdown()

    panel.sortDrop = Dropdown("PetDupSortDrop", { "TOPRIGHT", -17, rowY })
    InitSortDropdown(panel)

    local DIM, GOLD = PSM.Theme.COLOR.DIM, PSM.Theme.COLOR.GOLD
    PSM.Tooltip.Attach(panel.sortDrop, {
        anchor     = "ANCHOR_BOTTOMLEFT",
        x          = 17,
        y          = 0,
        title      = "Sort by",
        titleColor = PSM.Theme.COLOR.WHITE,
        lines = {
            { text = "Slot - sort by stable slot number",     color = DIM },
            { text = "Model - sort by display ID",            color = DIM },
            { text = "Family - sort alphabetically by family", color = DIM },
            { text = "Spec - sort alphabetically by spec",    color = DIM },
            { text = "Tamer - sort alphabetically by owner",  color = DIM },
            { text = "Unsorted - default order",              color = DIM },
            " ",
            { text = "Custom drag-and-drop reordering in",    color = GOLD },
            { text = "Grouped view requires Unsorted.",       color = GOLD },
        },
    })

    panel.exoticCheck = CreateFilterCheckbox(panel, {
        point         = { "BOTTOMLEFT", panel.familyDrop, "TOPLEFT", 16, 3 },
        label         = "Exotic Only",
        labelHitWidth = 100,
        initialState  = PSM.state.exoticFilter,
        onChanged = function(state)
            PSM.state.exoticFilter = state
            PSM.Utils:ClearTable(PSM.state.selectedFamilies)
            InitFamilyDropdown(panel)
            debouncedUpdate()
        end,
    })

    panel.duplicatesCheck = CreateFilterCheckbox(panel, {
        point         = { "BOTTOMLEFT", panel.tamerDrop, "TOPLEFT", 16, 3 },
        label         = "Duplicates Only",
        labelHitWidth = 120,
        initialState  = PSM.state.duplicatesOnlyFilter,
        onChanged = function(state)
            PSM.state.duplicatesOnlyFilter = state
            debouncedUpdate()
        end,
    })
end

function PSM.UI:SetDefaultTamerSelection()
    if not PSM.state.tamerList or PSM.state.tamerSelectionInitialized then return end
    if PSM.IsCurrentCharacterHunter() then
        local key = PSM.GetCharacterKey()
        for _, tamer in ipairs(PSM.state.tamerList) do
            if tamer == key then
                PSM.state.selectedTamers[tamer] = true
                break
            end
        end
    end
    PSM.state.tamerSelectionInitialized = true
end

function PSM.UI:SetStableTamerSelection()
    if not PSM.state.tamerList or not PSM.state.panel or not PSM.state.panel.tamerDrop then return end
    if not PSM.IsCurrentCharacterHunter() then return end

    local key = PSM.GetCharacterKey()
    PSM.Utils:ClearTable(PSM.state.selectedTamers)
    PSM.state.selectedTamers[key] = true
    UIDropDownMenu_SetText(PSM.state.panel.tamerDrop, key)
    self:ReinitializeTamerDropdown()
end

function PSM.UI:ReinitializeTamerDropdown()
    if not PSM.state.panel or not PSM.state.panel.tamerDrop then return end
    PSM.Data:RebuildTamerList()

    local dropdown = PSM.state.panel.tamerDrop
    local allLabel = "All Hunters"
    local function getState() return PSM.state.selectedTamers end

    UIDropDownMenu_Initialize(dropdown, function()
        local t = getState()
        local showAll = not PSM.state.isStableOpen or #PSM.state.tamerList > 1
        if showAll then
            local info   = UIDropDownMenu_CreateInfo()
            info.text    = "  " .. allLabel
            info.value   = "ALL"
            info.checked = false
            info.func = function()
                PSM.Utils:ClearTable(getState())
                PSM.state.tamerSelectionInitialized = true
                UIDropDownMenu_SetText(dropdown, allLabel)
                PSM.C_Timer.After(0.1, function() PSM.UI:UpdatePanel() end)
            end
            UIDropDownMenu_AddButton(info)
        end

        for _, tamer in ipairs(PSM.state.tamerList or {}) do
            local info            = UIDropDownMenu_CreateInfo()
            info.text             = "  " .. tamer
            info.value            = tamer
            info.checked          = t[tamer] or false
            info.keepShownOnClick = true
            info.isNotRadio       = true
            info.func = function(_, _, _, checked)
                local st = getState()
                st[tamer] = checked or nil
                PSM.state.tamerSelectionInitialized = true
                UIDropDownMenu_SetText(dropdown, DropdownText(getState(), allLabel))
                PSM.C_Timer.After(0.1, function() PSM.UI:UpdatePanel() end)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    UIDropDownMenu_Initialize(dropdown, dropdown.initialize, nil, 1)
    UIDropDownMenu_SetText(dropdown, DropdownText(getState(), allLabel))
end

function PSM.UI:UpdateFilterUI()
    local panel = PSM.state.panel
    if not panel then return end

    -- SetTriState paints the box and keeps `.triState` in sync with the saved filter,
    -- which the two hand-written versions of this had to remember separately.
    if panel.exoticCheck     then panel.exoticCheck:SetTriState(PSM.state.exoticFilter)              end
    if panel.duplicatesCheck then panel.duplicatesCheck:SetTriState(PSM.state.duplicatesOnlyFilter)  end

    if panel.specDrop   then UIDropDownMenu_SetText(panel.specDrop,   DropdownText(PSM.state.selectedSpecs,   "All Specs"))       end
    if panel.familyDrop then UIDropDownMenu_SetText(panel.familyDrop, DropdownText(PSM.state.selectedFamilies, FamilyAllLabel())) end
    if panel.tamerDrop  then UIDropDownMenu_SetText(panel.tamerDrop,  DropdownText(PSM.state.selectedTamers,  "All Hunters"))     end
    if panel.sortDrop   then UIDropDownMenu_SetText(panel.sortDrop,   SortDropLabel())                                            end
end

function PSM.UI:BuildSortButtons(panel)
    -- Reset Filters button
    panel.resetFiltersButton = PSM.Widgets.Button(panel, {
        size       = { PSM.Config.BUTTON_WIDTH, PSM.Config.BUTTON_HEIGHT },
        point      = { "TOPLEFT", panel.searchBox, "TOPRIGHT", 10, 0 },
        text       = "Reset Filters",
        fontObject = "GameFontNormalSmall",

        -- A function spec: the tamer line depends on whether the stable is open,
        -- which changes while this button exists.
        tooltip = function()
            local lines = {}
            for _, text in ipairs({
                "All Specs selected", "All Families selected",
                PSM.state.isStableOpen and "Tamer: kept on current hunter" or "All Hunters selected",
                "Exotic Only: OFF", "Duplicates Only: OFF", "Clear search box",
                "Sort by: Unsorted",
            }) do
                lines[#lines + 1] = { text = text, color = PSM.Theme.COLOR.FAINT }
            end
            return {
                anchor     = "ANCHOR_BOTTOMRIGHT",
                title      = "Reset all filters",
                titleColor = PSM.Theme.COLOR.WHITE,
                lines      = lines,
            }
        end,

        onClick = function()
            -- ClearSearch, not SetText(""): the latter leaves the box blank, because the
            -- placeholder is only restored on focus loss.
            if panel.searchBox then panel.searchBox:ClearSearch() end

            PSM.Utils:ClearTable(PSM.state.selectedSpecs)
            PSM.Utils:ClearTable(PSM.state.selectedFamilies)
            UIDropDownMenu_SetText(panel.specDrop,   "All Specs")
            UIDropDownMenu_SetText(panel.familyDrop, "All Families")

            -- When stable is open, keep tamer locked to current hunter
            if not PSM.state.isStableOpen then
                PSM.Utils:ClearTable(PSM.state.selectedTamers)
                UIDropDownMenu_SetText(panel.tamerDrop, "All Hunters")
            end

            PSM.state.exoticFilter         = nil
            PSM.state.duplicatesOnlyFilter = nil
            panel.exoticCheck:SetTriState(nil)
            panel.duplicatesCheck:SetTriState(nil)

            PSM.state.sortBy = nil
            UIDropDownMenu_SetText(panel.sortDrop, "Sort by")

            PSM.UI:UpdatePanel()
        end,
    })
end


