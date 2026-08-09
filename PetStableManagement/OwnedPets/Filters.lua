-- OwnedPets/Filters.lua
-- Filter controls for PetStableManagement

local addonName = "PetStableManagement"

_G.PSM = _G.PSM or {}
local PSM = _G.PSM

local function ApplyElvUIDropdownSkin(dropdown)
    if not ElvUI or not ElvUI[1] or not ElvUI[1]:GetModule("Skins") then return end
    local S = ElvUI[1]:GetModule("Skins")
    C_Timer.After(0.1, function()
        if dropdown.Button then
            if S.HandleNextPrevButton then S:HandleNextPrevButton(dropdown.Button, "down") end
            dropdown.Button:ClearAllPoints()
            dropdown.Button:SetPoint("RIGHT", dropdown, "RIGHT", -10, 3)
        end
        for _, part in ipairs({ "Middle", "Left", "Right" }) do
            if dropdown[part] then dropdown[part]:SetAlpha(0) end
        end
        if not dropdown.backdrop then
            dropdown.backdrop = CreateFrame("Frame", nil, dropdown, "BackdropTemplate")
            dropdown.backdrop:SetFrameLevel(dropdown:GetFrameLevel() - 1)
            dropdown.backdrop:SetPoint("TOPLEFT", dropdown, "TOPLEFT", 16, -4)
            dropdown.backdrop:SetPoint("BOTTOMRIGHT", dropdown.Button, "BOTTOMRIGHT", 2, -2)
            dropdown.backdrop:SetBackdrop({
                bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            })
            dropdown.backdrop:SetBackdropColor(0.1, 0.1, 0.1, PSM.Config:GetOpacity())
            dropdown.backdrop:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        end
        if dropdown.Text then
            dropdown.Text:ClearAllPoints()
            dropdown.Text:SetPoint("LEFT",  dropdown,        "LEFT",  22, 2)
            dropdown.Text:SetPoint("RIGHT", dropdown.Button, "LEFT",  -2, 2)
        end
    end)
end

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
-- Cycles nil → true → "inverted" → nil, managing visual state automatically.

local function SetupTriStateCheckbox(cb, onChanged, initialState)
    cb.triState = initialState
    
    -- Set initial visual state
    local isInverted = initialState == "inverted"
    cb:SetChecked(initialState ~= nil)
    cb:GetCheckedTexture():SetAlpha(isInverted and 0 or 1)
    
    if not cb.invertedTexture then
        cb.invertedTexture = cb:CreateTexture(nil, "OVERLAY")
        cb.invertedTexture:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
        cb.invertedTexture:SetSize(16, 16)
        cb.invertedTexture:SetPoint("CENTER", cb, "CENTER", 0, 0)
    end
    cb.invertedTexture:SetShown(isInverted)
    
    cb:SetScript("OnClick", function(self)
        -- Advance state
        if     self.triState == nil      then self.triState = true
        elseif self.triState == true     then self.triState = "inverted"
        else                                  self.triState = nil
        end

        -- Visuals
        local isInverted = self.triState == "inverted"
        self:SetChecked(self.triState ~= nil)
        self:GetCheckedTexture():SetAlpha(isInverted and 0 or 1)

        if not self.invertedTexture then
            self.invertedTexture = self:CreateTexture(nil, "OVERLAY")
            self.invertedTexture:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
            self.invertedTexture:SetSize(16, 16)
            self.invertedTexture:SetPoint("CENTER", self, "CENTER", 0, 0)
        end
        self.invertedTexture:SetShown(isInverted)

        onChanged(self.triState)
    end)
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

    local cfg  = PSM.Config
    local rowY = cfg.DROPDOWN_ROW_Y
    local step = cfg.DROPDOWN_SPACING

    -- Spec dropdown
    panel.specDrop = CreateFrame("Frame", "PetDupSpecDrop", panel, "UIDropDownMenuTemplate")
    panel.specDrop:SetPoint("TOPLEFT", -10, rowY)
    UIDropDownMenu_SetWidth(panel.specDrop, cfg.DROPDOWN_WIDTH)
    ApplyElvUIDropdownSkin(panel.specDrop)
    InitMultiDropdown(function() return PSM.state.specList end,
                      function() return PSM.state.selectedSpecs end,
                      panel.specDrop, "All Specs")

    -- Family dropdown
    panel.familyDrop = CreateFrame("Frame", "PetDupFamilyDrop", panel, "UIDropDownMenuTemplate")
    panel.familyDrop:SetPoint("TOPLEFT", step * 1-10, rowY)
    UIDropDownMenu_SetWidth(panel.familyDrop, cfg.DROPDOWN_WIDTH)
    ApplyElvUIDropdownSkin(panel.familyDrop)
    InitFamilyDropdown(panel)

    -- Tamer dropdown
    panel.tamerDrop = CreateFrame("Frame", "PetDupTamerDrop", panel, "UIDropDownMenuTemplate")
    panel.tamerDrop:SetPoint("TOPLEFT", step * 2-10, rowY)
    UIDropDownMenu_SetWidth(panel.tamerDrop, cfg.DROPDOWN_WIDTH)
    ApplyElvUIDropdownSkin(panel.tamerDrop)
    self:ReinitializeTamerDropdown()

    -- Sort dropdown
    panel.sortDrop = CreateFrame("Frame", "PetDupSortDrop", panel, "UIDropDownMenuTemplate")
    panel.sortDrop:SetPoint("TOPRIGHT", -17, rowY)
    UIDropDownMenu_SetWidth(panel.sortDrop, cfg.DROPDOWN_WIDTH)
    ApplyElvUIDropdownSkin(panel.sortDrop)
    InitSortDropdown(panel)
    panel.sortDrop:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT", 17, 0)
        GameTooltip:SetText("Sort by", 1, 1, 1)
        GameTooltip:AddLine("Slot - sort by stable slot number",    0.7, 0.7, 0.7)
        GameTooltip:AddLine("Model - sort by display ID",           0.7, 0.7, 0.7)
        GameTooltip:AddLine("Family - sort alphabetically by family", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Spec - sort alphabetically by spec",   0.7, 0.7, 0.7)
        GameTooltip:AddLine("Tamer - sort alphabetically by owner", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Unsorted - default order",             0.7, 0.7, 0.7)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Custom drag-and-drop reordering in",   1, 0.82, 0)
        GameTooltip:AddLine("Grouped view requires Unsorted.",       1, 0.82, 0)
        GameTooltip:Show()
    end)
    panel.sortDrop:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Exotic checkbox
    panel.exoticCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    panel.exoticCheck:SetSize(20, 20)
    panel.exoticCheck:SetPoint("BOTTOMLEFT",panel.familyDrop, "TOPLEFT", 16, 3)
    PSM.UI:ApplyElvUISkin(panel.exoticCheck, "checkbox")
    panel.exoticCheck:SetHitRectInsets(0, -100, 0, 0)
    panel.exoticCheck.text = panel.exoticCheck:CreateFontString(nil, "OVERLAY")
    panel.exoticCheck.text:SetFont("Fonts\\FRIZQT__.TTF", 10)
    panel.exoticCheck.text:SetPoint("LEFT", panel.exoticCheck, "RIGHT", 5, 0)
    panel.exoticCheck.text:SetText("Exotic Only")
    
    SetupTriStateCheckbox(panel.exoticCheck, function(state)
        PSM.state.exoticFilter = state
        PSM.Utils:ClearTable(PSM.state.selectedFamilies)
        InitFamilyDropdown(panel)
        debouncedUpdate()
    end, PSM.state.exoticFilter)

    -- Duplicates checkbox
    panel.duplicatesCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    panel.duplicatesCheck:SetSize(20, 20)
    panel.duplicatesCheck:SetPoint("BOTTOMLEFT",panel.tamerDrop, "TOPLEFT", 16, 3)
    PSM.UI:ApplyElvUISkin(panel.duplicatesCheck, "checkbox")
    panel.duplicatesCheck:SetHitRectInsets(0, -120, 0, 0)
    panel.duplicatesCheck.text = panel.duplicatesCheck:CreateFontString(nil, "OVERLAY")
    panel.duplicatesCheck.text:SetFont("Fonts\\FRIZQT__.TTF", 10)
    panel.duplicatesCheck.text:SetPoint("LEFT", panel.duplicatesCheck, "RIGHT", 5, 0)
    panel.duplicatesCheck.text:SetText("Duplicates Only")
    
    SetupTriStateCheckbox(panel.duplicatesCheck, function(state)
        PSM.state.duplicatesOnlyFilter = state
        debouncedUpdate()
    end, PSM.state.duplicatesOnlyFilter)
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

function PSM.UI:ResetTamerSelection()
    if not PSM.state.panel or not PSM.state.panel.tamerDrop then return end
    PSM.Utils:ClearTable(PSM.state.selectedTamers)
    PSM.state.tamerSelectionInitialized = true
    UIDropDownMenu_SetText(PSM.state.panel.tamerDrop, "All Hunters")
    self:ReinitializeTamerDropdown()
    PSM.C_Timer.After(0.1, function() PSM.UI:UpdatePanel() end)
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

    if panel.exoticCheck then
        panel.exoticCheck:SetChecked(PSM.state.exoticFilter)
        -- Sync internal triState with saved filter value
        panel.exoticCheck.triState = PSM.state.exoticFilter
        local isInverted = PSM.state.exoticFilter == "inverted"
        panel.exoticCheck:GetCheckedTexture():SetAlpha(isInverted and 0 or 1)
        if panel.exoticCheck.invertedTexture then
            panel.exoticCheck.invertedTexture:SetShown(isInverted)
        end
    end
    if panel.duplicatesCheck then
        panel.duplicatesCheck:SetChecked(PSM.state.duplicatesOnlyFilter)
        -- Sync internal triState with saved filter value
        panel.duplicatesCheck.triState = PSM.state.duplicatesOnlyFilter
        local isInverted = PSM.state.duplicatesOnlyFilter == "inverted"
        panel.duplicatesCheck:GetCheckedTexture():SetAlpha(isInverted and 0 or 1)
        if panel.duplicatesCheck.invertedTexture then
            panel.duplicatesCheck.invertedTexture:SetShown(isInverted)
        end
    end

    if panel.specDrop   then UIDropDownMenu_SetText(panel.specDrop,   DropdownText(PSM.state.selectedSpecs,   "All Specs"))       end
    if panel.familyDrop then UIDropDownMenu_SetText(panel.familyDrop, DropdownText(PSM.state.selectedFamilies, FamilyAllLabel())) end
    if panel.tamerDrop  then UIDropDownMenu_SetText(panel.tamerDrop,  DropdownText(PSM.state.selectedTamers,  "All Hunters"))     end
    if panel.sortDrop   then UIDropDownMenu_SetText(panel.sortDrop,   SortDropLabel())                                            end
end

function PSM.UI:BuildSortButtons(panel)
    -- Reset Filters button
    panel.resetFiltersButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.resetFiltersButton:SetSize(PSM.Config.BUTTON_WIDTH, PSM.Config.BUTTON_HEIGHT)
    panel.resetFiltersButton:SetPoint("TOPLEFT", panel.searchBox, "TOPRIGHT", 10, 0)
    panel.resetFiltersButton:SetText("Reset Filters")
    panel.resetFiltersButton:SetNormalFontObject("GameFontNormalSmall")
    PSM.UI:ApplyElvUISkin(panel.resetFiltersButton, "button")
    panel.resetFiltersButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText("Reset all filters", 1, 1, 1)
        for _, line in ipairs({
            "All Specs selected", "All Families selected",
            PSM.state.isStableOpen and "Tamer: kept on current hunter" or "All Hunters selected",
            "Exotic Only: OFF", "Duplicates Only: OFF", "Clear search box",
            "Sort by: Unsorted",
        }) do
            GameTooltip:AddLine(line, 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    panel.resetFiltersButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.resetFiltersButton:SetScript("OnClick", function()
        if panel.searchBox then panel.searchBox:SetText("") end

        PSM.Utils:ClearTable(PSM.state.selectedSpecs)
        PSM.Utils:ClearTable(PSM.state.selectedFamilies)
        UIDropDownMenu_SetText(panel.specDrop,   "All Specs")
        UIDropDownMenu_SetText(panel.familyDrop, "All Families")

        -- When stable is open, keep tamer locked to current hunter
        if not PSM.state.isStableOpen then
            PSM.Utils:ClearTable(PSM.state.selectedTamers)
            UIDropDownMenu_SetText(panel.tamerDrop, "All Hunters")
        end

        local function resetCheck(cb, stateKey)
            PSM.state[stateKey] = nil
            cb.triState = nil
            cb:SetChecked(false)
            cb:GetCheckedTexture():SetAlpha(1)
            if cb.invertedTexture then cb.invertedTexture:Hide() end
        end
        resetCheck(panel.exoticCheck,     "exoticFilter")
        resetCheck(panel.duplicatesCheck, "duplicatesOnlyFilter")

        PSM.state.sortBy = nil
        UIDropDownMenu_SetText(panel.sortDrop, "Sort by")

        PSM.UI:UpdatePanel()
    end)
end


