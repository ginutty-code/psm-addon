-- OwnedPets/Filters.lua
-- Filter controls for PetStableManagement

local _, ns = ...

-- ─── Helpers ──────────────────────────────────────────────────────────────────

local function IsFamilyExotic(name) return ns.Data.IsExoticFamily(name) end

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
    local cb = ns.Widgets.CheckBox(panel, {
        point         = opts.point,
        label         = opts.label,
        labelFontSize = ns.Theme.SIZE.SMALL,
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
            ns.Utils:ClearTable(getStateTable())
            UIDropDownMenu_SetText(dropdown, allLabel)
            ns.C_Timer.After(0.1, function() ns.UI:UpdatePanel() end)
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
                    ns.C_Timer.After(0.1, function() ns.UI:UpdatePanel() end)
                end
                UIDropDownMenu_AddButton(info)
            end
        end
    end)
    UIDropDownMenu_SetText(dropdown, DropdownText(getStateTable(), allLabel))
end

-- Returns the family dropdown's "all" label given the current exotic filter.
local function FamilyAllLabel()
    if ns.state.exoticFilter == true then
        return ns.L("All Exotic Families")
    elseif ns.state.exoticFilter == "inverted" then
        return ns.L("All Non-Exotic Families")
    end
    return ns.L("All Families")
end

local function InitFamilyDropdown(panel)
    local label = FamilyAllLabel()
    local filterFn
    if ns.state.exoticFilter == true then
        filterFn = IsFamilyExotic
    elseif ns.state.exoticFilter == "inverted" then
        filterFn = function(f) return not IsFamilyExotic(f) end
    end
    InitMultiDropdown(function() return ns.state.familyList end,
                      function() return ns.state.selectedFamilies end,
                      panel.familyDrop, label, filterFn)
end

-- ─── Sort dropdown ────────────────────────────────────────────────────────────

-- Maps PSM.state.sortBy → the label shown in the dropdown button.
-- Localized here rather than at the lookup below, so every key is a literal the
-- locale spec can see. ns.L(SORT_LABELS[...]) reads better and is worse: a computed
-- key is invisible to both directions of the check, and these five went undeclared
-- until a /dump found them.
local SORT_LABELS = {
    slot   = ns.L("Sorted by Slot"),
    model  = ns.L("Sorted by Model"),
    family = ns.L("Sorted by Family"),
    spec   = ns.L("Sorted by Spec"),
    tamer  = ns.L("Sorted by Tamer"),
}

local function SortDropLabel()
    return SORT_LABELS[ns.state.sortBy] or ns.L("Sort by")
end

local function InitSortDropdown(panel)
    local dropdown = panel.sortDrop
    UIDropDownMenu_Initialize(dropdown, function()
        local options = {
            { value = nil,     text = ns.L("Unsorted") },
            { value = "family",text = ns.L("Family")   },
            { value = "model", text = ns.L("Model")    },
            { value = "slot",  text = ns.L("Slot")     },
            { value = "spec",  text = ns.L("Spec")     },
            { value = "tamer", text = ns.L("Tamer")    },
        }
        for _, opt in ipairs(options) do
            local info      = UIDropDownMenu_CreateInfo()
            info.text       = "  " .. opt.text
            info.value      = opt.value
            info.checked    = (ns.state.sortBy == opt.value)
            info.func       = function()
                ns.state.sortBy = opt.value
                UIDropDownMenu_SetText(dropdown, SortDropLabel())
                -- Refresh checked state so the menu reflects the new selection
                -- if the user reopens it without closing the panel.
                UIDropDownMenu_Initialize(dropdown, dropdown.initialize, nil, 1)
                ns.C_Timer.After(0.1, function() ns.UI:UpdatePanel() end)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(dropdown, SortDropLabel())
end

-- ─── Public API ───────────────────────────────────────────────────────────────

function ns.UI:BuildFilters(panel)
    local debouncedUpdate = ns.Utils:Debounce(function()
        ns.UI:UpdatePanel()
    end, ns.Config.UPDATE_DELAY)

    local Widgets = ns.Widgets
    local cfg  = ns.Config
    local rowY = ns.Theme.CHROME.FILTER_TOP
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
    InitMultiDropdown(function() return ns.state.specList end,
                      function() return ns.state.selectedSpecs end,
                      panel.specDrop, ns.L("All Specs"))

    panel.familyDrop = Dropdown("PetDupFamilyDrop", { "TOPLEFT", step * 1 - 10, rowY })
    InitFamilyDropdown(panel)

    panel.tamerDrop = Dropdown("PetDupTamerDrop", { "TOPLEFT", step * 2 - 10, rowY })
    self:ReinitializeTamerDropdown()

    panel.sortDrop = Dropdown("PetDupSortDrop", { "TOPRIGHT", -17, rowY })
    InitSortDropdown(panel)

    local DIM, GOLD = ns.Theme.COLOR.DIM, ns.Theme.COLOR.GOLD
    ns.Tooltip.Attach(panel.sortDrop, {
        anchor     = "ANCHOR_BOTTOMLEFT",
        x          = 17,
        y          = 0,
        title      = ns.L("Sort by"),
        titleColor = ns.Theme.COLOR.WHITE,
        lines = {
            { text = ns.L("Slot - sort by stable slot number"),     color = DIM },
            { text = ns.L("Model - sort by display ID"),            color = DIM },
            { text = ns.L("Family - sort alphabetically by family"), color = DIM },
            { text = ns.L("Spec - sort alphabetically by spec"),    color = DIM },
            { text = ns.L("Tamer - sort alphabetically by owner"),  color = DIM },
            { text = ns.L("Unsorted - default order"),              color = DIM },
            " ",
            { text = ns.L("Custom drag-and-drop reordering in"),    color = GOLD },
            { text = ns.L("Grouped view requires Unsorted."),       color = GOLD },
        },
    })

    panel.exoticCheck = CreateFilterCheckbox(panel, {
        point         = { "BOTTOMLEFT", panel.familyDrop, "TOPLEFT", 16, 3 },
        label         = ns.L("Exotic Only"),
        labelHitWidth = 100,
        initialState  = ns.state.exoticFilter,
        onChanged = function(state)
            ns.state.exoticFilter = state
            ns.Utils:ClearTable(ns.state.selectedFamilies)
            InitFamilyDropdown(panel)
            debouncedUpdate()
        end,
    })

    panel.duplicatesCheck = CreateFilterCheckbox(panel, {
        point         = { "BOTTOMLEFT", panel.tamerDrop, "TOPLEFT", 16, 3 },
        label         = ns.L("Duplicates Only"),
        labelHitWidth = 120,
        initialState  = ns.state.duplicatesOnlyFilter,
        onChanged = function(state)
            ns.state.duplicatesOnlyFilter = state
            debouncedUpdate()
        end,
    })
end

function ns.UI:SetDefaultTamerSelection()
    if not ns.state.tamerList or ns.state.tamerSelectionInitialized then return end
    if ns.IsCurrentCharacterHunter() then
        local key = ns.GetCharacterKey()
        for _, tamer in ipairs(ns.state.tamerList) do
            if tamer == key then
                ns.state.selectedTamers[tamer] = true
                break
            end
        end
    end
    ns.state.tamerSelectionInitialized = true
end

function ns.UI:SetStableTamerSelection()
    if not ns.state.tamerList or not ns.state.panel or not ns.state.panel.tamerDrop then return end
    if not ns.IsCurrentCharacterHunter() then return end

    local key = ns.GetCharacterKey()
    ns.Utils:ClearTable(ns.state.selectedTamers)
    ns.state.selectedTamers[key] = true
    UIDropDownMenu_SetText(ns.state.panel.tamerDrop, key)
    self:ReinitializeTamerDropdown()
end

function ns.UI:ReinitializeTamerDropdown()
    if not ns.state.panel or not ns.state.panel.tamerDrop then return end
    ns.Data:RebuildTamerList()

    local dropdown = ns.state.panel.tamerDrop
    local allLabel = ns.L("All Hunters")
    local function getState() return ns.state.selectedTamers end

    UIDropDownMenu_Initialize(dropdown, function()
        local t = getState()
        local showAll = not ns.state.isStableOpen or #ns.state.tamerList > 1
        if showAll then
            local info   = UIDropDownMenu_CreateInfo()
            info.text    = "  " .. allLabel
            info.value   = "ALL"
            info.checked = false
            info.func = function()
                ns.Utils:ClearTable(getState())
                ns.state.tamerSelectionInitialized = true
                UIDropDownMenu_SetText(dropdown, allLabel)
                ns.C_Timer.After(0.1, function() ns.UI:UpdatePanel() end)
            end
            UIDropDownMenu_AddButton(info)
        end

        for _, tamer in ipairs(ns.state.tamerList or {}) do
            local info            = UIDropDownMenu_CreateInfo()
            info.text             = "  " .. tamer
            info.value            = tamer
            info.checked          = t[tamer] or false
            info.keepShownOnClick = true
            info.isNotRadio       = true
            info.func = function(_, _, _, checked)
                local st = getState()
                st[tamer] = checked or nil
                ns.state.tamerSelectionInitialized = true
                UIDropDownMenu_SetText(dropdown, DropdownText(getState(), allLabel))
                ns.C_Timer.After(0.1, function() ns.UI:UpdatePanel() end)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    UIDropDownMenu_Initialize(dropdown, dropdown.initialize, nil, 1)
    UIDropDownMenu_SetText(dropdown, DropdownText(getState(), allLabel))
end

function ns.UI:UpdateFilterUI()
    local panel = ns.state.panel
    if not panel then return end

    -- SetTriState paints the box and keeps `.triState` in sync with the saved filter,
    -- which the two hand-written versions of this had to remember separately.
    if panel.exoticCheck     then panel.exoticCheck:SetTriState(ns.state.exoticFilter)              end
    if panel.duplicatesCheck then panel.duplicatesCheck:SetTriState(ns.state.duplicatesOnlyFilter)  end

    if panel.specDrop   then UIDropDownMenu_SetText(panel.specDrop,   DropdownText(ns.state.selectedSpecs,   ns.L("All Specs")))       end
    if panel.familyDrop then UIDropDownMenu_SetText(panel.familyDrop, DropdownText(ns.state.selectedFamilies, FamilyAllLabel())) end
    if panel.tamerDrop  then UIDropDownMenu_SetText(panel.tamerDrop,  DropdownText(ns.state.selectedTamers,  ns.L("All Hunters")))     end
    if panel.sortDrop   then UIDropDownMenu_SetText(panel.sortDrop,   SortDropLabel())                                            end
end

-- Lives here rather than in UI.lua, which held a byte-identical copy of SORT_LABELS to
-- do the same job. Its three callers refresh only the sort dropdown, so this cannot just
-- defer to UpdateFilterUI.
function ns.UI:UpdateSortButtonTexts()
    local panel = ns.state.panel
    if not panel or not panel.sortDrop then return end
    UIDropDownMenu_SetText(panel.sortDrop, SortDropLabel())
end

function ns.UI:BuildSortButtons(panel)
    -- Reset Filters button
    panel.resetFiltersButton = ns.Widgets.Button(panel, {
        width      = ns.Theme.CONTROL.BUTTON_W.M,
        point      = { "TOPLEFT", panel.searchBox, "TOPRIGHT", 10, 0 },
        text       = ns.L("Reset Filters"),
        fontObject = "GameFontNormalSmall",

        -- A function spec: the tamer line depends on whether the stable is open,
        -- which changes while this button exists.
        tooltip = function()
            local lines = {}
            for _, text in ipairs({
                ns.L("All Specs selected"), ns.L("All Families selected"),
                ns.state.isStableOpen and ns.L("Tamer: kept on current hunter")
                                       or ns.L("All Hunters selected"),
                ns.L("Exotic Only: OFF"), ns.L("Duplicates Only: OFF"), ns.L("Clear search box"),
                ns.L("Sort by: Unsorted"),
            }) do
                lines[#lines + 1] = { text = text, color = ns.Theme.COLOR.FAINT }
            end
            return {
                anchor     = "ANCHOR_BOTTOMRIGHT",
                title      = ns.L("Reset all filters"),
                titleColor = ns.Theme.COLOR.WHITE,
                lines      = lines,
            }
        end,

        onClick = function()
            -- ClearSearch, not SetText(""): the latter leaves the box blank, because the
            -- placeholder is only restored on focus loss.
            if panel.searchBox then panel.searchBox:ClearSearch() end

            ns.Utils:ClearTable(ns.state.selectedSpecs)
            ns.Utils:ClearTable(ns.state.selectedFamilies)
            UIDropDownMenu_SetText(panel.specDrop,   ns.L("All Specs"))
            UIDropDownMenu_SetText(panel.familyDrop, ns.L("All Families"))

            -- When stable is open, keep tamer locked to current hunter
            if not ns.state.isStableOpen then
                ns.Utils:ClearTable(ns.state.selectedTamers)
                UIDropDownMenu_SetText(panel.tamerDrop, ns.L("All Hunters"))
            end

            ns.state.exoticFilter         = nil
            ns.state.duplicatesOnlyFilter = nil
            panel.exoticCheck:SetTriState(nil)
            panel.duplicatesCheck:SetTriState(nil)

            ns.state.sortBy = nil
            UIDropDownMenu_SetText(panel.sortDrop, ns.L("Sort by"))

            ns.UI:UpdatePanel()
        end,
    })
end


