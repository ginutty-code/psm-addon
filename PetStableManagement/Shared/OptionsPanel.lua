-- OptionsPanel.lua
-- Options panel integration for PetStableManagement

_G.PSM = _G.PSM or {}
local PSM = _G.PSM

local addonName = "Pet Stable Management"

-- Layout constants
local CHECKBOX_INDENT_X         = 0
local SLIDER_WIDTH_OFFSET       = 48
local CHECKBOX_INDENT_Y         = -14
local SECTION_SPACING           = -18
local SLIDER_TITLE_SPACING      = -8
local SLIDER_SLIDER_SPACING     = -36
local DIVIDER_SPACING           = 36
local DROPDOWN_OFFSET_X         = -20
local DROPDOWN_OFFSET_Y         = -8
local DROPDOWN_WIDTH            = 100
local CHECKBOX_DROPDOWN_OFFSET  = -4  -- centres a checkbox against a dropdown's height
local RESET_BUTTON_WIDTH        = 100
local RESET_BUTTON_HEIGHT       = 22
local RESET_BUTTON_MARGIN       = 16

local function SetCamDistanceScaleIfChanged(model, scale)
    if model.lastCamDistanceScale ~= scale then
        model.lastCamDistanceScale = scale
        model:SetCamDistanceScale(scale)
    end
end

-------------------------------------------------------------------------------
-- Model iteration
-------------------------------------------------------------------------------

local function IterateAllVisibleModels(callback)
    if PSM.state.panel and PSM.state.panel:IsVisible() then
        for _, row in ipairs(PSM.state.rows) do
            if row and row.model and row.model:IsVisible() then
                callback(row.model)
            end
        end
    end

    for _, stateKey in ipairs({ "modelViewRows", "groupedViewRows" }) do
        if PSM.state[stateKey] then
            for _, row in ipairs(PSM.state[stateKey]) do
                if row and row.model and row.model:IsVisible() then
                    callback(row.model)
                end
            end
        end
    end

    if PSM.state.modelsPanel and PSM.state.modelsPanel:IsVisible() then
        for _, row in ipairs(PSM.state.modelsPanel.modelRows or {}) do
            if row and row.model and row.model:IsVisible() then
                callback(row.model)
            end
        end
    end

    for _, popupKey in ipairs({ "petRoulettePopup", "modelMagnificationPopup" }) do
        local popup = PSM.state[popupKey]
        if popup and popup:IsVisible() and popup.modelFrame then
            callback(popup.modelFrame)
        end
    end
end

-------------------------------------------------------------------------------
-- Per-model applicators
-------------------------------------------------------------------------------

local function ApplyAnimationStateToModel(model, stopAnimation)
    if stopAnimation then
        model:FreezeAnimation(0, 0, 0)
    else
        model:SetAnimation(0)
    end
end

local function ApplyAllSettingsToModel(model, zoom, angle, vertical, horizontal, stopAnim)
    model.zoom     = zoom
    model.rotation = angle
    SetCamDistanceScaleIfChanged(model, 1.0 / zoom)
    model:SetRotation(angle)
    model:SetPosition(0, horizontal * 2.0, vertical * 2.0)
    ApplyAnimationStateToModel(model, stopAnim)
end

local function ApplyCurrentGlobalsToAllModels()
    local s   = PetStableManagementDB.settings
    local cfg = PSM.Config
    IterateAllVisibleModels(function(model)
        ApplyAllSettingsToModel(
            model,
            s.modelZoom               or cfg.DEFAULT_MODEL_ZOOM,
            math.rad(s.modelViewAngle or cfg.DEFAULT_MODEL_VIEW_ANGLE),
            s.modelVerticalPosition   or cfg.DEFAULT_MODEL_VERTICAL_POSITION,
            s.modelHorizontalPosition or cfg.DEFAULT_MODEL_HORIZONTAL_POSITION,
            s.stopAnimation           or cfg.DEFAULT_STOP_ANIMATION
        )
    end)
end

-------------------------------------------------------------------------------
-- Panel refresh
-------------------------------------------------------------------------------

-- Both popups redraw their background from the same three fields. This was written
-- out four times: twice in the background-type dropdown and twice again in Reset.
local function RefreshPopupBackgrounds()
    for _, key in ipairs({ "modelMagnificationPopup", "petRoulettePopup" }) do
        local popup = PSM.state[key]
        if popup and popup:IsVisible() then
            PSM.PopUpManager:UpdatePopupBackground(popup, popup.currentDisplayId, popup.currentPetData)
        end
    end
end

-- Repaint whatever is on screen after a settings change. Three call sites used to
-- each carry their own copy of this list, and they had already drifted apart -- only
-- one of them refreshed the teams panel, and only one rebuilt the models grid.
--
--   relayout -- the models browser's grid must be rebuilt, not just repainted
--               (the column count changed). Done whether or not it is visible, so a
--               panel opened later is already correct.
--   popups   -- the magnification and roulette popups redraw their backgrounds.
--   opacity  -- the teams panel repaints at the new opacity. Every other panel here
--               picks opacity up from PanelManager:UpdatePanelBackgrounds(), which
--               is also what covers the Ability Browser and Special Tames.
local function RefreshOpenPanels(opts)
    opts = opts or {}
    local state = PSM.state

    if state.panel and state.panel:IsVisible() then PSM.UI:RenderPanel() end

    if state.modelsPanel and PSM.ModelsPanel then
        if opts.relayout then
            PSM.ModelsPanel:UpdateModelsPanelLayout()
            PSM.ModelsPanel:UpdateVisibleRows()
        elseif state.modelsPanel:IsVisible() then
            PSM.ModelsPanel:UpdateVisibleRows()
        end
    end

    if state.ownedPetsPanel and state.ownedPetsPanel:IsVisible() then
        PSM.OwnedPets:UpdatePanel()
    end

    if opts.opacity and state.teamsPanel and state.teamsPanel:IsVisible() then
        PSM.TeamsPanel:UpdateOpacity()
    end

    if opts.popups then RefreshPopupBackgrounds() end
end

-------------------------------------------------------------------------------
-- Panel definition
-------------------------------------------------------------------------------

local panel = PSM.Widgets.Frame(nil)
panel.name = addonName
panel:Hide()

panel:SetScript("OnShow", function(self)
    -- Clear the script immediately so widget creation only ever runs once,
    -- even if an error occurs partway through.
    self:SetScript("OnShow", nil)

    local Widgets = PSM.Widgets
    local cfg     = PSM.Config

    -- A title above the slider, then the slider under it. The title carries the
    -- anchor because the vertical rhythm of this panel is measured title-to-title.
    local function LabelledSlider(anchorWidget, anchorOffset, titleText, opts)
        local title = Widgets.Label(panel, {
            fontObject = "GameFontNormal",
            text       = titleText,
            point      = { "TOPLEFT", anchorWidget, "BOTTOMLEFT", 0, anchorOffset },
        })
        opts.point = { "TOPLEFT", title, "BOTTOMLEFT", 0, SLIDER_TITLE_SPACING }
        opts.width = panel:GetWidth() - SLIDER_WIDTH_OFFSET
        return Widgets.Slider(panel, opts), title
    end

    local function Dropdown(name, point)
        local d = Widgets.Frame(panel, {
            name     = addonName .. name,
            template = "UIDropDownMenuTemplate",
            skin     = "dropdown",
            point    = point,
        })
        UIDropDownMenu_SetWidth(d, DROPDOWN_WIDTH)
        return d
    end

    -- Title
    local title = Widgets.Label(panel, {
        fontObject = "GameFontNormalLarge",
        text       = addonName,
        point      = { "TOPLEFT", RESET_BUTTON_MARGIN, -RESET_BUTTON_MARGIN },
    })

    -- ── Minimap checkbox ────────────────────────────────────────────────────
    local showMinimapCheckbox = Widgets.CheckBox(panel, {
        name    = addonName .. "ShowMinimapCheckbox",
        label   = "Show minimap button",
        checked = not PetStableManagementDB.settings.minimapButton.hide,
        point   = { "TOPLEFT", title, "BOTTOMLEFT", CHECKBOX_INDENT_X, CHECKBOX_INDENT_Y },
        onClick = function(cb)
            local checked = cb:GetChecked()
            PetStableManagementDB.settings.minimapButton.hide = not checked
            if checked then PSM.Minimap:Show() else PSM.Minimap:Hide() end
        end,
    })

    -- ── Open with Stable checkbox (to the right of minimap checkbox) ─────────
    local openWithStableCheckbox = Widgets.CheckBox(panel, {
        name    = addonName .. "OpenWithStableCheckbox",
        label   = "Open with the Stable window",
        checked = PetStableManagementDB.settings.openWithStable ~= false,
        point   = { "TOPLEFT", showMinimapCheckbox, "TOPRIGHT", 150, 0 },
        onClick = function(cb)
            PetStableManagementDB.settings.openWithStable = cb:GetChecked() or false
        end,
    })

    -- ── Opacity slider ──────────────────────────────────────────────────────
    local opacitySlider = LabelledSlider(showMinimapCheckbox, SECTION_SPACING, "UI Opacity:", {
        name      = addonName .. "OpacitySlider",
        min       = cfg.MIN_TRANSPARENCY,
        max       = cfg.MAX_TRANSPARENCY,
        step      = 0.01,
        value     = cfg:GetOpacity(),
        lowLabel  = "10%",
        highLabel = "100%",
        format    = function(v) return "Opacity: " .. math.floor(v * 100) .. "%" end,
        onChange  = function(value)
            local v = math.floor(value * 100) / 100
            PetStableManagementDB.settings.opacity = v
            PSM.Config:UpdateColors()
            -- Covers every panel that draws its own backdrop, the Ability Browser and
            -- Special Tames included. Only the teams panel needs telling separately.
            PSM.PanelManager:UpdatePanelBackgrounds()
            RefreshOpenPanels({ opacity = true })
        end,
    })

    -- ── Divider ─────────────────────────────────────────────────────────────
    local divider = Widgets.Line(panel, {
        layer = "BORDER",
        point = {
            { "TOPLEFT",  opacitySlider, "BOTTOMLEFT",  0, -DIVIDER_SPACING },
            { "TOPRIGHT", opacitySlider, "BOTTOMRIGHT", 0, -DIVIDER_SPACING },
        },
    })

    local petModelTitle = Widgets.Label(panel, {
        fontObject = "GameFontNormal",
        text       = "Pet Model Settings",
        point      = { "TOPLEFT", divider, "BOTTOMLEFT", 0, SECTION_SPACING },
    })

    -- ── Model sliders ───────────────────────────────────────────────────────
    -- All four write one setting, discard the cached model views and re-apply the
    -- new globals to whatever is on screen.
    local function ApplyModelSetting(key, value)
        PetStableManagementDB.settings[key] = value
        PSM.state.modelViews = {}
        ApplyCurrentGlobalsToAllModels()
    end

    local zoomSlider = LabelledSlider(petModelTitle, SECTION_SPACING, "Zoom:", {
        name      = addonName .. "ZoomSlider",
        min       = cfg.MIN_MODEL_ZOOM,
        max       = cfg.MAX_MODEL_ZOOM,
        step      = 0.01,
        value     = PetStableManagementDB.settings.modelZoom or cfg.DEFAULT_MODEL_ZOOM,
        lowLabel  = "50%",
        highLabel = "200%",
        format    = function(v) return "Zoom: " .. math.floor(v * 100) .. "%" end,
        onChange  = function(value)
            ApplyModelSetting("modelZoom", math.floor(value * 100) / 100)
        end,
    })

    local viewAngleSlider = LabelledSlider(zoomSlider, SLIDER_SLIDER_SPACING, "View Angle:", {
        name      = addonName .. "ViewAngleSlider",
        min       = cfg.MIN_MODEL_VIEW_ANGLE,
        max       = cfg.MAX_MODEL_VIEW_ANGLE,
        step      = 1,
        value     = PetStableManagementDB.settings.modelViewAngle or cfg.DEFAULT_MODEL_VIEW_ANGLE,
        lowLabel  = "-180°",
        highLabel = "180°",
        format    = function(v) return "View Angle: " .. math.floor(v) .. "°" end,
        onChange  = function(value)
            ApplyModelSetting("modelViewAngle", math.floor(value))
        end,
    })

    local verticalPositionSlider = LabelledSlider(viewAngleSlider, SLIDER_SLIDER_SPACING,
        "Vertical Positioning (Z-axis):", {
        name      = addonName .. "VerticalPositionSlider",
        min       = cfg.MIN_MODEL_VERTICAL_POSITION,
        max       = cfg.MAX_MODEL_VERTICAL_POSITION,
        step      = 0.01,
        value     = PetStableManagementDB.settings.modelVerticalPosition or cfg.DEFAULT_MODEL_VERTICAL_POSITION,
        lowLabel  = "-100%",
        highLabel = "100%",
        format    = function(v) return "Vertical Position: " .. math.floor(v * 100) .. "%" end,
        onChange  = function(value)
            ApplyModelSetting("modelVerticalPosition", math.floor(value * 100) / 100)
        end,
    })

    local horizontalPositionSlider = LabelledSlider(verticalPositionSlider, SLIDER_SLIDER_SPACING,
        "Horizontal Positioning (Y-axis):", {
        name      = addonName .. "HorizontalPositionSlider",
        min       = cfg.MIN_MODEL_HORIZONTAL_POSITION,
        max       = cfg.MAX_MODEL_HORIZONTAL_POSITION,
        step      = 0.01,
        value     = PetStableManagementDB.settings.modelHorizontalPosition or cfg.DEFAULT_MODEL_HORIZONTAL_POSITION,
        lowLabel  = "-100%",
        highLabel = "100%",
        format    = function(v) return "Horizontal Position: " .. math.floor(v * 100) .. "%" end,
        onChange  = function(value)
            ApplyModelSetting("modelHorizontalPosition", math.floor(value * 100) / 100)
        end,
    })

    -- ── Pets-per-column dropdown ────────────────────────────────────────────
    local petsPerColumnTitle = Widgets.Label(panel, {
        fontObject = "GameFontNormal",
        text       = "Pets Per Column in Browser:",
        point      = { "TOPLEFT", horizontalPositionSlider, "BOTTOMLEFT", 0, SLIDER_SLIDER_SPACING },
    })

    local petsPerColumnDropdown = Dropdown("PetsPerColumnDropdown",
        { "TOPLEFT", petsPerColumnTitle, "BOTTOMLEFT", DROPDOWN_OFFSET_X, DROPDOWN_OFFSET_Y })
    UIDropDownMenu_SetText(petsPerColumnDropdown,
        PetStableManagementDB.settings.petsPerColumn or cfg.DEFAULT_PETS_PER_COLUMN)

    UIDropDownMenu_Initialize(petsPerColumnDropdown, function()
        local current = PetStableManagementDB.settings.petsPerColumn or cfg.DEFAULT_PETS_PER_COLUMN
        local info = UIDropDownMenu_CreateInfo()
        for i = cfg.MIN_PETS_PER_COLUMN, cfg.MAX_PETS_PER_COLUMN do
            info.text    = "  " .. i
            info.value   = i
            info.checked = (current == i)
            info.func    = function(btn)
                PetStableManagementDB.settings.petsPerColumn = btn.value
                UIDropDownMenu_SetText(petsPerColumnDropdown, btn.value)
                -- Column count only affects the browser's grid; nothing else repaints.
                if PSM.state.modelsPanel and PSM.ModelsPanel then
                    PSM.ModelsPanel:UpdateModelsPanelLayout()
                    PSM.ModelsPanel:UpdateVisibleRows()
                end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    -- ── Background type dropdown ────────────────────────────────────────────
    local backgroundTypeTitle = Widgets.Label(panel, {
        fontObject = "GameFontNormal",
        text       = "Pet Model Background:",
        point      = { "TOPLEFT", petsPerColumnTitle, "TOPRIGHT", 20, 0 },
    })

    local backgroundTypeDropdown = Dropdown("BackgroundTypeDropdown",
        { "TOPLEFT", backgroundTypeTitle, "BOTTOMLEFT", DROPDOWN_OFFSET_X, DROPDOWN_OFFSET_Y })

    local backgroundTypeLabels = {
        simple = "  Simple",
        stablemaster = "  Stable Master",
        custom = "  Custom",
    }

    local currentBgType = PetStableManagementDB.settings.backgroundType or cfg.DEFAULT_BACKGROUND_TYPE
    UIDropDownMenu_SetText(backgroundTypeDropdown,
        backgroundTypeLabels[currentBgType] or backgroundTypeLabels[cfg.DEFAULT_BACKGROUND_TYPE])

    UIDropDownMenu_Initialize(backgroundTypeDropdown, function()
        local current = PetStableManagementDB.settings.backgroundType or cfg.DEFAULT_BACKGROUND_TYPE
        local info = UIDropDownMenu_CreateInfo()
        for _, bgType in ipairs(cfg.BACKGROUND_TYPES) do
            info.text = backgroundTypeLabels[bgType]
            info.value = bgType
            info.checked = (current == bgType)
            info.func = function(btn)
                PetStableManagementDB.settings.backgroundType = btn.value
                UIDropDownMenu_SetText(backgroundTypeDropdown, backgroundTypeLabels[btn.value])
                RefreshOpenPanels({ popups = true })
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    -- ── Stop-animation checkbox ─────────────────────────────────────────────
    local stopAnimCheckbox = Widgets.CheckBox(panel, {
        name    = addonName .. "StopAnimCheckbox",
        label   = "Stop pet animations",
        checked = PetStableManagementDB.settings.stopAnimation or cfg.DEFAULT_STOP_ANIMATION,
        point   = { "TOPLEFT", backgroundTypeDropdown, "TOPRIGHT", 40, CHECKBOX_DROPDOWN_OFFSET },
        onClick = function(cb)
            local checked = cb:GetChecked()
            PetStableManagementDB.settings.stopAnimation = checked
            IterateAllVisibleModels(function(model)
                ApplyAnimationStateToModel(model, checked)
            end)
        end,
    })

    -- ── Reset button ────────────────────────────────────────────────────────
    Widgets.Button(panel, {
        name  = addonName .. "ResetButton",
        text  = "Reset All Settings",
        size  = { RESET_BUTTON_WIDTH, RESET_BUTTON_HEIGHT },
        point = { "BOTTOMRIGHT", panel, "BOTTOMRIGHT", -RESET_BUTTON_MARGIN, RESET_BUTTON_MARGIN },
        onClick = function()
            -- Write defaults to DB
            PetStableManagementDB.settings.opacity                 = cfg.DEFAULT_OPACITY
            PetStableManagementDB.settings.modelZoom               = cfg.DEFAULT_MODEL_ZOOM
            PetStableManagementDB.settings.modelViewAngle          = cfg.DEFAULT_MODEL_VIEW_ANGLE
            PetStableManagementDB.settings.modelVerticalPosition   = cfg.DEFAULT_MODEL_VERTICAL_POSITION
            PetStableManagementDB.settings.modelHorizontalPosition = cfg.DEFAULT_MODEL_HORIZONTAL_POSITION
            PetStableManagementDB.settings.stopAnimation           = cfg.DEFAULT_STOP_ANIMATION
            PetStableManagementDB.settings.openWithStable          = cfg.DEFAULT_OPEN_WITH_STABLE
            PetStableManagementDB.settings.petsPerColumn           = cfg.DEFAULT_PETS_PER_COLUMN
            PetStableManagementDB.settings.backgroundType          = cfg.DEFAULT_BACKGROUND_TYPE

            if PetStableManagementDB.filters then
                PetStableManagementDB.filters.selectedTamingRules = nil
                PetStableManagementDB.filters.selectedConditions = nil
                PetStableManagementDB.filters.familiesAppliedFromAbilities = nil
                PetStableManagementDB.filters.selectedFamiliesFromAbilities = nil
                PetStableManagementDB.filters.selectedModelsFamilies = nil
                PetStableManagementDB.filters.selectedExpansions = nil
                PetStableManagementDB.filters.selectedLocations = nil
            end
            PSM.state.selectedTamingRules = nil
            PSM.state.familiesAppliedFromAbilities = nil
            PSM.state.abilitiesFamilySet = nil
            PSM.state.selectedModelsFamilies = {}
            PSM.state.modelViews = {}

            -- Move the controls to match the values just written. Silently, or each
            -- slider would re-write the setting we already wrote and rebuild every
            -- visible model on the way past -- five times over. The value captions
            -- still repaint; that is the slider's job, not this handler's.
            opacitySlider:SetValueSilently(cfg.DEFAULT_OPACITY)
            zoomSlider:SetValueSilently(cfg.DEFAULT_MODEL_ZOOM)
            viewAngleSlider:SetValueSilently(cfg.DEFAULT_MODEL_VIEW_ANGLE)
            verticalPositionSlider:SetValueSilently(cfg.DEFAULT_MODEL_VERTICAL_POSITION)
            horizontalPositionSlider:SetValueSilently(cfg.DEFAULT_MODEL_HORIZONTAL_POSITION)

            stopAnimCheckbox:SetChecked(cfg.DEFAULT_STOP_ANIMATION)
            openWithStableCheckbox:SetChecked(cfg.DEFAULT_OPEN_WITH_STABLE)
            UIDropDownMenu_SetText(petsPerColumnDropdown, cfg.DEFAULT_PETS_PER_COLUMN)
            UIDropDownMenu_SetText(backgroundTypeDropdown, backgroundTypeLabels[cfg.DEFAULT_BACKGROUND_TYPE])

            -- Applying the default opacity is this handler's job precisely because the
            -- silent SetValue above skipped the slider's own handler. Reset used to
            -- write the default opacity to the DB and repaint nothing with it, so the
            -- UI kept the old opacity until something unrelated forced a redraw.
            PSM.Config:UpdateColors()
            PSM.PanelManager:UpdatePanelBackgrounds()

            ApplyCurrentGlobalsToAllModels()
            RefreshOpenPanels({ relayout = true, popups = true, opacity = true })
        end,
    })
end)

-------------------------------------------------------------------------------
-- Register with the game's settings system
-------------------------------------------------------------------------------

local categoryId = nil
if InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
elseif Settings and Settings.RegisterAddOnCategory and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    categoryId = category.ID
    Settings.RegisterAddOnCategory(category)
end

PSM.state.optionsPanel      = panel
PSM.state.optionsCategoryId = categoryId
