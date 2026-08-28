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
-- `parent` is the frame it is anchored in (a rail box now, not `panel`); its
-- own field name on `panel` is set by the caller, unchanged.
local function CreateFilterCheckbox(parent, opts)
    local cb = ns.Widgets.CheckBox(parent, {
        point         = opts.point,
        label         = opts.label,
        labelFontSize = ns.Theme.SIZE.SMALL,
        tooltip       = opts.tooltip,
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

-- ─── Ability dropdown (two-level: category, then abilities within it) ─────────
-- A flat list of every ability the account's pets carry got unwieldy fast with no
-- way to know which one does what (the case that started this: "which of my pets
-- can slow?"). AbilitiesData's `category` field answers that directly (e.g. "Enemy
-- movement reduction"), so it's the one grouping level -- the coarser `tag` field
-- (Control/Damage/...) was tried first and dropped: Tag -> Category -> Ability would
-- be a real third click for no benefit here, since this list only ever holds
-- categories actually present on the account's pets, not the whole game's catalog
-- tag exists to keep browsable in the Ability Browser.

-- The distinct categories among `abilities` (an array of ability names), sorted.
local function AbilityCategories(abilities)
    local seen, list = {}, {}
    for _, name in ipairs(abilities) do
        local category = ns.Data:GetAbilityCategory(name)
        if not seen[category] then
            seen[category] = true
            list[#list + 1] = category
        end
    end
    table.sort(list)
    return list
end

-- The ability names under one category, sorted. Filters ns.state.abilityList fresh
-- rather than caching, on the same reasoning as InitMultiDropdown's getItems/
-- getStateTable functions: a stale copy would survive past ClearMemory/reload.
local function AbilitiesInCategory(category)
    local list = {}
    for _, name in ipairs(ns.state.abilityList) do
        if ns.Data:GetAbilityCategory(name) == category then
            list[#list + 1] = name
        end
    end
    table.sort(list)
    return list
end

local function InitAbilityDropdown(panel)
    local dropdown = panel.abilityDrop
    local allLabel = ns.L("All Abilities")

    -- allOn, noneOn for a category's abilities against the given selection set.
    -- Read fresh at call time rather than cached, so a click that fires it gets the
    -- true current state even if the submenu was fiddled with since level 1 was drawn.
    local function CategorySelectionState(category, selected)
        local allOn, noneOn = true, true
        for _, name in ipairs(AbilitiesInCategory(category)) do
            if selected[name] then noneOn = false else allOn = false end
        end
        return allOn, noneOn
    end

    -- Same "all/some/none selected" idiom AbilityBrowser's own category-card headers
    -- use (Theme.SelectionStateColor's doc comment names it as shared with them).
    local function CategoryColor(category)
        local allOn, noneOn = CategorySelectionState(category, ns.state.selectedAbilities)
        return ns.Theme.SelectionStateColor(allOn, not noneOn)
    end

    UIDropDownMenu_Initialize(dropdown, function(_, level)
        level = level or 1
        local selected = ns.state.selectedAbilities

        if level == 1 then
            local info = UIDropDownMenu_CreateInfo()
            info.text    = "  " .. allLabel
            info.value   = "ALL"
            info.checked = false
            info.func = function()
                ns.Utils:ClearTable(selected)
                UIDropDownMenu_SetText(dropdown, allLabel)
                ns.C_Timer.After(0.1, function() ns.UI:UpdatePanel() end)
            end
            UIDropDownMenu_AddButton(info, level)

            for _, category in ipairs(AbilityCategories(ns.state.abilityList)) do
                local r, g, b = unpack(CategoryColor(category))
                info = UIDropDownMenu_CreateInfo()
                -- +0.5 before the implicit truncation string.format("%x", ...) does on a
                -- float (Lua 5.1: a C-style (int) cast, not a rounding one) -- without it,
                -- a channel like Theme.COLOR.GREY's 0.6 (not exactly representable in
                -- binary float) can land a shade off.
                info.text         = ("|cff%02x%02x%02x%s|r"):format(
                    math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), category)
                info.value        = category
                info.hasArrow     = true
                info.notCheckable = true
                -- Clicking the row itself (not just opening its arrow submenu) selects
                -- every ability in the category in one step -- ticking each individually
                -- was the friction this category grouping exists to remove. Toggles: a
                -- category already fully selected clicks back to none.
                --
                -- Deliberately NOT keepShownOnClick: this row's own colour is baked into
                -- `info.text` above, computed once when level 1 was drawn, and closing
                -- rather than staying open is what guarantees the next open recomputes it
                -- (and, if a submenu is open, its checkmarks) from the real state instead
                -- of leaving the just-clicked row showing its pre-click colour until
                -- something else forces a redraw.
                info.func = function()
                    local allOn = CategorySelectionState(category, selected)
                    for _, name in ipairs(AbilitiesInCategory(category)) do
                        selected[name] = (not allOn) or nil
                    end
                    UIDropDownMenu_SetText(dropdown, DropdownText(selected, allLabel))
                    ns.C_Timer.After(0.1, function() ns.UI:UpdatePanel() end)
                end
                UIDropDownMenu_AddButton(info, level)
            end
        elseif level == 2 then
            local category = UIDROPDOWNMENU_MENU_VALUE
            for _, name in ipairs(AbilitiesInCategory(category)) do
                local info = UIDropDownMenu_CreateInfo()
                info.text             = "  " .. name
                info.value            = name
                info.checked          = selected[name] or false
                info.keepShownOnClick = true
                info.isNotRadio       = true
                info.icon             = ns.Data:GetAbilityIcon(name)
                info.tooltipTitle     = name
                info.tooltipText      = category
                info.tooltipOnButton  = true
                info.func = function(_, _, _, checked)
                    selected[name] = checked or nil
                    UIDropDownMenu_SetText(dropdown, DropdownText(selected, allLabel))
                    ns.C_Timer.After(0.1, function() ns.UI:UpdatePanel() end)
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end
    end)
    UIDropDownMenu_SetText(dropdown, DropdownText(ns.state.selectedAbilities, allLabel))
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

-- ─── Rail width ───────────────────────────────────────────────────────────────

-- The Owned Pets left rail is sized to its own content, not to Models Browser's
-- flat 210px -- that panel is a fixed 1100px wide, this one is 500-570, and a
-- 210px rail here would draw the centered search box straight through the rail's
-- border. Every term is measured against the real in-game widget rather than the
-- planning mockup's substitute-web-font guess. Computed once, memoised.
local railWidth
local function RailWidth()
    if railWidth then return railWidth end

    -- Checkbox labels, at their actual font (Friz Quadrata at Theme.SIZE.SMALL).
    local scratch = UIParent:CreateFontString(nil, "ARTWORK")
    scratch:SetFont(ns.Theme.FONT, ns.Theme.SIZE.SMALL, "")
    local widestLabel = 0
    for _, s in ipairs({ ns.L("Favorites"), ns.L("Exotic"), ns.L("Duplicates") }) do
        scratch:SetText(s)
        widestLabel = math.max(widestLabel, scratch:GetStringWidth() or 0)
    end

    -- Config.DROPDOWN_WIDTH is only the inner text width; UIDropDownMenu_SetWidth
    -- pads the frame by a client-version-dependent amount (25 or 50) for the side
    -- textures and the arrow button, and that padded frame is what has to fit the
    -- rail box. Probe the real frame once rather than guessing the pad.
    local probe = ns.CreateFrame("Frame", "PSMOwnedRailProbe", UIParent, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(probe, ns.Config.DROPDOWN_WIDTH)
    local dropdownW = probe:GetWidth()
    probe:Hide()

    -- Widest of: the dropdown frame (less the ~8px it hangs invisibly past the
    -- box's left edge -- see Dropdown's anchor); checkbox glyph + 4px gap + label;
    -- the Tools buttons' fixed M tier ("Team Roulette" clips at S/80, fits M/100).
    -- +16 keeps ~8px inside each vertical rail-box edge. Confirm the number in-game.
    railWidth = math.ceil(math.max(
        dropdownW - 8,
        ns.Theme.CONTROL.CHECKBOX + 4 + widestLabel,
        ns.Theme.CONTROL.BUTTON_W.M
    ) + 16)
    return railWidth
end

-- ─── Public API ───────────────────────────────────────────────────────────────

-- `railTop` is the panel-TOP-relative y where the rail's first box starts; it is
-- shared with Panel.lua so the rail and the pet list line up on the same top edge.
function ns.UI:BuildFilters(panel, railTop)
    local debouncedUpdate = ns.Utils:Debounce(function()
        ns.UI:UpdatePanel()
    end, ns.Config.UPDATE_DELAY)

    local Widgets = ns.Widgets
    local Theme   = ns.Theme
    local cfg     = ns.Config
    local PM      = ns.PanelManager
    local railW   = RailWidth()

    -- The filter chrome is three stacked rail boxes down the panel's left edge,
    -- top-aligned with the pet list rather than with the title -- the space beside
    -- the centered title/search box stays clear. Tools is created here as an empty
    -- box and populated with its buttons by Panel.lua (which owns Export/Pet
    -- Teams' click handlers); Show Only and Filters are built and filled here.
    local toolsY = railTop or Theme.CHROME.TITLE_Y
    local toolsBox = PM:CreateRailBox(panel, {
        point         = { 10, toolsY },
        width         = railW,
        contentHeight = Theme.CONTROL.BUTTON * 3 + 10,   -- 3 stacked buttons, 5px gaps
        headerText    = ns.L("Tools"),
    })
    panel.toolsFrame = toolsBox

    -- ── Show Only: tri-state checkboxes ────────────────────────────────────────
    -- Sized for three rows now; only the filtering logic behind Favorites lands in
    -- a later commit, so the box height and the stack order are already final.
    local showOnlyY = toolsY - toolsBox:GetHeight() - 5
    local showOnlyBox = PM:CreateRailBox(panel, {
        point         = { 10, showOnlyY },
        width         = railW,
        contentHeight = Theme.CONTROL.CHECKBOX_ROW * 3,
        headerText    = ns.L("Show Only"),
    })
    panel.showOnlyFrame = showOnlyBox

    local CHECK_GAP = Theme.CONTROL.CHECKBOX_ROW - Theme.CONTROL.CHECKBOX

    panel.favoritesCheck = CreateFilterCheckbox(showOnlyBox, {
        point         = { "TOPLEFT", showOnlyBox.sectionHeader, "BOTTOMLEFT", 3, -6 },
        label         = ns.L("Favorites"),
        labelHitWidth = railW,
        initialState  = ns.state.favoritesOnlyFilter,
        -- The render-pipeline branch, persistence and Reset wiring for this state
        -- arrive with the Favorites commit; the control itself is layout.
        onChanged = function(state)
            ns.state.favoritesOnlyFilter = state
            debouncedUpdate()
        end,
    })

    panel.exoticCheck = CreateFilterCheckbox(showOnlyBox, {
        point         = { "TOPLEFT", panel.favoritesCheck, "BOTTOMLEFT", 0, -CHECK_GAP },
        label         = ns.L("Exotic"),
        labelHitWidth = railW,
        initialState  = ns.state.exoticFilter,
        -- Clicking this rebuilds the Families dropdown's own contents
        -- (InitFamilyDropdown) -- a coupling that used to be obvious from the
        -- checkbox sitting directly above Families and no longer is.
        tooltip = {
            title = ns.L("Exotic"),
            lines = { { text  = ns.L("Also narrows the Families list below to exotic-only."),
                        color = Theme.COLOR.DIM } },
        },
        onChanged = function(state)
            ns.state.exoticFilter = state
            ns.Utils:ClearTable(ns.state.selectedFamilies)
            InitFamilyDropdown(panel)
            debouncedUpdate()
        end,
    })

    panel.duplicatesCheck = CreateFilterCheckbox(showOnlyBox, {
        point         = { "TOPLEFT", panel.exoticCheck, "BOTTOMLEFT", 0, -CHECK_GAP },
        label         = ns.L("Duplicates"),
        labelHitWidth = railW,
        initialState  = ns.state.duplicatesOnlyFilter,
        onChanged = function(state)
            ns.state.duplicatesOnlyFilter = state
            debouncedUpdate()
        end,
    })

    -- ── Filters: four multi-select dropdowns in one column ────────────────────
    -- Order: Hunters, Specs, Families, Abilities. Same panel.xxxDrop field names
    -- and same Init* calls as the old 2x2 grid -- only the anchoring changed, and
    -- nothing downstream anchors to these.
    local DROP_H = 34   -- one UIDropDownMenuTemplate (32) plus a 2px gap
    local filtersY = showOnlyY - showOnlyBox:GetHeight() - 5
    local filtersBox = PM:CreateRailBox(panel, {
        point         = { 10, filtersY },
        width         = railW,
        contentHeight = DROP_H * 4,
        headerText    = ns.L("Filters"),
    })
    panel.filtersFrame = filtersBox

    -- UIDropDownMenuTemplate carries ~16px of invisible frame on its left (the
    -- "dropdown" skin re-anchors its visible backdrop to f+16). The section band
    -- sits at box x=5, so -13 from it lands the visible edge ~8px inside the box.
    -- Tune in-game.
    local function Dropdown(name, i)
        local d = Widgets.Frame(filtersBox, {
            name     = name,
            template = "UIDropDownMenuTemplate",
            skin     = "dropdown",
            point    = { "TOPLEFT", filtersBox.sectionHeader, "BOTTOMLEFT",
                         -13, -6 - (i - 1) * DROP_H },
        })
        UIDropDownMenu_SetWidth(d, cfg.DROPDOWN_WIDTH)
        return d
    end

    panel.tamerDrop = Dropdown("PetDupTamerDrop", 1)
    self:ReinitializeTamerDropdown()

    panel.specDrop = Dropdown("PetDupSpecDrop", 2)
    InitMultiDropdown(function() return ns.state.specList end,
                      function() return ns.state.selectedSpecs end,
                      panel.specDrop, ns.L("All Specs"))

    panel.familyDrop = Dropdown("PetDupFamilyDrop", 3)
    InitFamilyDropdown(panel)

    panel.abilityDrop = Dropdown("PetDupAbilityDrop", 4)
    InitAbilityDropdown(panel)

    -- ── Sort by: not a filter, so it stays panel-anchored top-right ───────────
    -- Dropped down from the old filter grid to sit just above the pet list's top
    -- edge (Panel.lua's LIST_TOP, -128; this stays above it). Keeps its tooltip.
    panel.sortDrop = Widgets.Frame(panel, {
        name     = "PetDupSortDrop",
        template = "UIDropDownMenuTemplate",
        skin     = "dropdown",
        point    = { "TOPRIGHT", panel, "TOPRIGHT", -17, -92 },
    })
    UIDropDownMenu_SetWidth(panel.sortDrop, cfg.DROPDOWN_WIDTH)
    InitSortDropdown(panel)

    local DIM, GOLD = Theme.COLOR.DIM, Theme.COLOR.GOLD
    ns.Tooltip.Attach(panel.sortDrop, {
        anchor     = "ANCHOR_BOTTOMLEFT",
        x          = 17,
        y          = 0,
        title      = ns.L("Sort by"),
        titleColor = Theme.COLOR.WHITE,
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
    if panel.favoritesCheck  then panel.favoritesCheck:SetTriState(ns.state.favoritesOnlyFilter)    end
    if panel.exoticCheck     then panel.exoticCheck:SetTriState(ns.state.exoticFilter)              end
    if panel.duplicatesCheck then panel.duplicatesCheck:SetTriState(ns.state.duplicatesOnlyFilter)  end

    if panel.specDrop    then UIDropDownMenu_SetText(panel.specDrop,    DropdownText(ns.state.selectedSpecs,   ns.L("All Specs")))       end
    if panel.familyDrop  then UIDropDownMenu_SetText(panel.familyDrop,  DropdownText(ns.state.selectedFamilies, FamilyAllLabel())) end
    if panel.tamerDrop   then UIDropDownMenu_SetText(panel.tamerDrop,   DropdownText(ns.state.selectedTamers,  ns.L("All Hunters")))     end
    if panel.abilityDrop then UIDropDownMenu_SetText(panel.abilityDrop, DropdownText(ns.state.selectedAbilities, ns.L("All Abilities"))) end
    if panel.sortDrop    then UIDropDownMenu_SetText(panel.sortDrop,    SortDropLabel())                                            end
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
                ns.L("All Abilities selected"),
                ns.L("Favorites: OFF"), ns.L("Exotic Only: OFF"), ns.L("Duplicates Only: OFF"),
                ns.L("Clear search box"),
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
            ns.Utils:ClearTable(ns.state.selectedAbilities)
            UIDropDownMenu_SetText(panel.specDrop,    ns.L("All Specs"))
            UIDropDownMenu_SetText(panel.familyDrop,  ns.L("All Families"))
            UIDropDownMenu_SetText(panel.abilityDrop, ns.L("All Abilities"))

            -- When stable is open, keep tamer locked to current hunter
            if not ns.state.isStableOpen then
                ns.Utils:ClearTable(ns.state.selectedTamers)
                UIDropDownMenu_SetText(panel.tamerDrop, ns.L("All Hunters"))
            end

            ns.state.exoticFilter         = nil
            ns.state.duplicatesOnlyFilter = nil
            ns.state.favoritesOnlyFilter  = nil
            panel.favoritesCheck:SetTriState(nil)
            panel.exoticCheck:SetTriState(nil)
            panel.duplicatesCheck:SetTriState(nil)

            ns.state.sortBy = nil
            UIDropDownMenu_SetText(panel.sortDrop, ns.L("Sort by"))

            ns.UI:UpdatePanel()
        end,
    })
end


