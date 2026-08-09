-- OptionsPanel.lua
-- Options panel integration for PetStableManagement

local addonName = "Pet Stable Management"

-- Layout constants
local SLIDER_WIDTH_OFFSET       = 48
local CHECKBOX_INDENT_Y         = -14
local SECTION_SPACING           = -18
local SLIDER_TITLE_SPACING      = -8
local SLIDER_SLIDER_SPACING     = -36
local DIVIDER_SPACING           = 36
local DROPDOWN_OFFSET_X         = -20
local DROPDOWN_OFFSET_Y         = -8
local RESET_BUTTON_WIDTH        = 100
local RESET_BUTTON_HEIGHT       = 22
local RESET_BUTTON_MARGIN       = 16

-- Guard flag: suppresses model/DB side-effects during programmatic SetValue calls
local isResetting = false

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
-- Widget factories
-------------------------------------------------------------------------------

local function CreateLabelledSlider(panel, anchorWidget, anchorOffset, opts)
    local title = panel:CreateFontString("ARTWORK", nil, "GameFontNormal")
    title:SetPoint("TOPLEFT", anchorWidget, "BOTTOMLEFT", 0, anchorOffset)
    title:SetText(opts.title)

    local slider = CreateFrame("Slider", addonName .. opts.name, panel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, SLIDER_TITLE_SPACING)
    slider:SetWidth(panel:GetWidth() - SLIDER_WIDTH_OFFSET)
    slider:SetMinMaxValues(opts.min, opts.max)
    slider:SetValueStep(opts.step)
    slider:SetValue(opts.value)

    _G[slider:GetName() .. "Low"]:SetText(opts.lowLabel)
    _G[slider:GetName() .. "High"]:SetText(opts.highLabel)
    _G[slider:GetName() .. "Text"]:SetText(opts.formatLabel(opts.value))

    return slider, title
end

local function CreateLabelledCheckbox(panel, anchorWidget, anchorPoint, offsetX, offsetY, name, label, checked)
    local cb = CreateFrame("CheckButton", addonName .. name, panel, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", anchorWidget, anchorPoint, offsetX, offsetY)
    cb:SetChecked(checked)
    _G[cb:GetName() .. "Text"]:SetText(label)
    return cb
end

-------------------------------------------------------------------------------
-- Panel definition
-------------------------------------------------------------------------------

local panel = CreateFrame("Frame")
panel.name = addonName
panel:Hide()

panel:SetScript("OnShow", function(self)
    -- Clear the script immediately so widget creation only ever runs once,
    -- even if an error occurs partway through.
    self:SetScript("OnShow", nil)

    -- Title
    local title = panel:CreateFontString("ARTWORK", nil, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", RESET_BUTTON_MARGIN, -RESET_BUTTON_MARGIN)
    title:SetText(addonName)

    -- ── Minimap checkbox ────────────────────────────────────────────────────
    local showMinimapCheckbox = CreateLabelledCheckbox(
        panel, title, "BOTTOMLEFT", CHECKBOX_INDENT_X, CHECKBOX_INDENT_Y,
        "ShowMinimapCheckbox", "Show minimap button",
        not PetStableManagementDB.settings.minimapButton.hide
    )
    showMinimapCheckbox:SetScript("OnClick", function(cb)
        local checked = cb:GetChecked()
        PetStableManagementDB.settings.minimapButton.hide = not checked
        if checked then PSM.Minimap:Show() else PSM.Minimap:Hide() end
    end)

    -- ── Open with Stable checkbox (to the right of minimap checkbox) ─────────
    local openWithStableCheckbox = CreateLabelledCheckbox(
        panel, showMinimapCheckbox, "TOPRIGHT", 150, 0,
        "OpenWithStableCheckbox", "Open with the Stable window",
        PetStableManagementDB.settings.openWithStable ~= false
    )
    openWithStableCheckbox:SetScript("OnClick", function(cb)
        PetStableManagementDB.settings.openWithStable = cb:GetChecked() or false
    end)

    -- ── Opacity slider ──────────────────────────────────────────────────────
    local function opacityLabel(v) return "Opacity: " .. math.floor(v * 100) .. "%" end

    local opacitySlider = CreateLabelledSlider(panel, showMinimapCheckbox, SECTION_SPACING, {
        name        = "OpacitySlider",
        title       = "UI Opacity:",
        min         = PSM.Config.MIN_TRANSPARENCY,
        max         = PSM.Config.MAX_TRANSPARENCY,
        step        = 0.01,
        value       = PSM.Config:GetOpacity(),
        lowLabel    = "10%",
        highLabel   = "100%",
        formatLabel = opacityLabel,
    })
    opacitySlider:SetScript("OnValueChanged", function(slider, value)
        if isResetting then return end
        local v = math.floor(value * 100) / 100
        PetStableManagementDB.settings.opacity = v
        _G[slider:GetName() .. "Text"]:SetText(opacityLabel(v))
        PSM.Config:UpdateColors()
        PSM.PanelManager:UpdatePanelBackgrounds()
        if PSM.state.panel and PSM.state.panel:IsVisible() then PSM.UI:RenderPanel() end
        if PSM.state.modelsPanel and PSM.state.modelsPanel:IsVisible() and PSM.ModelsPanel then
            PSM.ModelsPanel:UpdateVisibleRows()
        end
        if PSM.state.ownedPetsPanel and PSM.state.ownedPetsPanel:IsVisible() then
            PSM.OwnedPets:UpdatePanel()
        end
        if PSM.state.teamsPanel and PSM.state.teamsPanel:IsVisible() then
            PSM.TeamsPanel:UpdateOpacity()
        end
        if PSM.state.abilityBrowser and PSM.state.abilityBrowser:IsVisible() then
            -- AbilityBrowser opacity handled by PanelManager:UpdatePanelBackgrounds()
        end
        if PSM.state.specialTames and PSM.state.specialTames:IsVisible() then
            -- SpecialTames opacity handled by PanelManager:UpdatePanelBackgrounds()
        end
    end)

    -- ── Divider ─────────────────────────────────────────────────────────────
    local divider = panel:CreateTexture(nil, "BORDER")
    divider:SetHeight(2)
    divider:SetPoint("TOPLEFT",  opacitySlider, "BOTTOMLEFT",  0, -DIVIDER_SPACING)
    divider:SetPoint("TOPRIGHT", opacitySlider, "BOTTOMRIGHT", 0, -DIVIDER_SPACING)
    divider:SetColorTexture(0.3, 0.3, 0.3, 0.5)

    local petModelTitle = panel:CreateFontString("ARTWORK", nil, "GameFontNormal")
    petModelTitle:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, SECTION_SPACING)
    petModelTitle:SetText("Pet Model Settings")

    -- ── Zoom slider ─────────────────────────────────────────────────────────
    local function zoomLabel(v) return "Zoom: " .. math.floor(v * 100) .. "%" end

    local zoomSlider = CreateLabelledSlider(panel, petModelTitle, SECTION_SPACING, {
        name        = "ZoomSlider",
        title       = "Zoom:",
        min         = PSM.Config.MIN_MODEL_ZOOM,
        max         = PSM.Config.MAX_MODEL_ZOOM,
        step        = 0.01,
        value       = PetStableManagementDB.settings.modelZoom or PSM.Config.DEFAULT_MODEL_ZOOM,
        lowLabel    = "50%",
        highLabel   = "200%",
        formatLabel = zoomLabel,
    })
    zoomSlider:SetScript("OnValueChanged", function(slider, value)
        if isResetting then return end
        local v = math.floor(value * 100) / 100
        PetStableManagementDB.settings.modelZoom = v
        _G[slider:GetName() .. "Text"]:SetText(zoomLabel(v))
        PSM.state.modelViews = {}
        ApplyCurrentGlobalsToAllModels()
    end)

    -- ── View angle slider ───────────────────────────────────────────────────
    local function angleLabel(v) return "View Angle: " .. v .. "°" end

    local viewAngleSlider = CreateLabelledSlider(panel, zoomSlider, SLIDER_SLIDER_SPACING, {
        name        = "ViewAngleSlider",
        title       = "View Angle:",
        min         = PSM.Config.MIN_MODEL_VIEW_ANGLE,
        max         = PSM.Config.MAX_MODEL_VIEW_ANGLE,
        step        = 1,
        value       = PetStableManagementDB.settings.modelViewAngle or PSM.Config.DEFAULT_MODEL_VIEW_ANGLE,
        lowLabel    = "-180°",
        highLabel   = "180°",
        formatLabel = angleLabel,
    })
    viewAngleSlider:SetScript("OnValueChanged", function(slider, value)
        if isResetting then return end
        local v = math.floor(value)
        PetStableManagementDB.settings.modelViewAngle = v
        _G[slider:GetName() .. "Text"]:SetText(angleLabel(v))
        PSM.state.modelViews = {}
        ApplyCurrentGlobalsToAllModels()
    end)

    -- ── Vertical position slider ────────────────────────────────────────────
    local function vertLabel(v) return "Vertical Position: " .. math.floor(v * 100) .. "%" end

    local verticalPositionSlider = CreateLabelledSlider(panel, viewAngleSlider, SLIDER_SLIDER_SPACING, {
        name        = "VerticalPositionSlider",
        title       = "Vertical Positioning (Z-axis):",
        min         = PSM.Config.MIN_MODEL_VERTICAL_POSITION,
        max         = PSM.Config.MAX_MODEL_VERTICAL_POSITION,
        step        = 0.01,
        value       = PetStableManagementDB.settings.modelVerticalPosition or PSM.Config.DEFAULT_MODEL_VERTICAL_POSITION,
        lowLabel    = "-100%",
        highLabel   = "100%",
        formatLabel = vertLabel,
    })
    verticalPositionSlider:SetScript("OnValueChanged", function(slider, value)
        if isResetting then return end
        local v = math.floor(value * 100) / 100
        PetStableManagementDB.settings.modelVerticalPosition = v
        _G[slider:GetName() .. "Text"]:SetText(vertLabel(v))
        PSM.state.modelViews = {}
        ApplyCurrentGlobalsToAllModels()
    end)

    -- ── Horizontal position slider ──────────────────────────────────────────
    local function horizLabel(v) return "Horizontal Position: " .. math.floor(v * 100) .. "%" end

    local horizontalPositionSlider = CreateLabelledSlider(panel, verticalPositionSlider, SLIDER_SLIDER_SPACING, {
        name        = "HorizontalPositionSlider",
        title       = "Horizontal Positioning (Y-axis):",
        min         = PSM.Config.MIN_MODEL_HORIZONTAL_POSITION,
        max         = PSM.Config.MAX_MODEL_HORIZONTAL_POSITION,
        step        = 0.01,
        value       = PetStableManagementDB.settings.modelHorizontalPosition or PSM.Config.DEFAULT_MODEL_HORIZONTAL_POSITION,
        lowLabel    = "-100%",
        highLabel   = "100%",
        formatLabel = horizLabel,
    })
    horizontalPositionSlider:SetScript("OnValueChanged", function(slider, value)
        if isResetting then return end
        local v = math.floor(value * 100) / 100
        PetStableManagementDB.settings.modelHorizontalPosition = v
        _G[slider:GetName() .. "Text"]:SetText(horizLabel(v))
        PSM.state.modelViews = {}
        ApplyCurrentGlobalsToAllModels()
    end)

    -- ── Pets-per-column dropdown ────────────────────────────────────────────
    local petsPerColumnTitle = panel:CreateFontString("ARTWORK", nil, "GameFontNormal")
    petsPerColumnTitle:SetPoint("TOPLEFT", horizontalPositionSlider, "BOTTOMLEFT", 0, SLIDER_SLIDER_SPACING)
    petsPerColumnTitle:SetText("Pets Per Column in Browser:")

    local petsPerColumnDropdown = CreateFrame("Frame", addonName .. "PetsPerColumnDropdown", panel, "UIDropDownMenuTemplate")
    petsPerColumnDropdown:SetPoint("TOPLEFT", petsPerColumnTitle, "BOTTOMLEFT", DROPDOWN_OFFSET_X, DROPDOWN_OFFSET_Y)
    UIDropDownMenu_SetWidth(petsPerColumnDropdown, 100)
    UIDropDownMenu_SetText(petsPerColumnDropdown, PetStableManagementDB.settings.petsPerColumn or PSM.Config.DEFAULT_PETS_PER_COLUMN)

    UIDropDownMenu_Initialize(petsPerColumnDropdown, function(_, _, _)
        local current = PetStableManagementDB.settings.petsPerColumn or PSM.Config.DEFAULT_PETS_PER_COLUMN
        local info = UIDropDownMenu_CreateInfo()
        for i = PSM.Config.MIN_PETS_PER_COLUMN, PSM.Config.MAX_PETS_PER_COLUMN do
            info.text    = "  " .. i
            info.value   = i
            info.checked = (current == i)
            info.func    = function(btn)
                PetStableManagementDB.settings.petsPerColumn = btn.value
                UIDropDownMenu_SetText(petsPerColumnDropdown, btn.value)
                if PSM.state.modelsPanel and PSM.ModelsPanel then
                    PSM.ModelsPanel:UpdateModelsPanelLayout()
                    PSM.ModelsPanel:UpdateVisibleRows()
                end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    -- ── Background type dropdown ────────────────────────────────────────────
    local backgroundTypeTitle = panel:CreateFontString("ARTWORK", nil, "GameFontNormal")
    backgroundTypeTitle:SetPoint("TOPLEFT", petsPerColumnTitle, "TOPRIGHT", 20, 0)
    backgroundTypeTitle:SetText("Pet Model Background:")

    local backgroundTypeDropdown = CreateFrame("Frame", addonName .. "BackgroundTypeDropdown", panel, "UIDropDownMenuTemplate")
    backgroundTypeDropdown:SetPoint("TOPLEFT", backgroundTypeTitle, "BOTTOMLEFT", DROPDOWN_OFFSET_X, DROPDOWN_OFFSET_Y)
    UIDropDownMenu_SetWidth(backgroundTypeDropdown, 100)

    local backgroundTypeLabels = {
        simple = "  Simple",
        stablemaster = "  Stable Master",
        custom = "  Custom",
    }

    local currentBgType = PetStableManagementDB.settings.backgroundType or PSM.Config.DEFAULT_BACKGROUND_TYPE
    UIDropDownMenu_SetText(backgroundTypeDropdown, backgroundTypeLabels[currentBgType] or backgroundTypeLabels[PSM.Config.DEFAULT_BACKGROUND_TYPE])

    UIDropDownMenu_Initialize(backgroundTypeDropdown, function(_, _, _)
        local current = PetStableManagementDB.settings.backgroundType or PSM.Config.DEFAULT_BACKGROUND_TYPE
        local info = UIDropDownMenu_CreateInfo()
        for _, bgType in ipairs(PSM.Config.BACKGROUND_TYPES) do
            info.text = backgroundTypeLabels[bgType]
            info.value = bgType
            info.checked = (current == bgType)
            info.func = function(btn)
                PetStableManagementDB.settings.backgroundType = btn.value
                UIDropDownMenu_SetText(backgroundTypeDropdown, backgroundTypeLabels[btn.value])
                -- Refresh panels to apply new background
                if PSM.state.panel and PSM.state.panel:IsVisible() then PSM.UI:RenderPanel() end
                if PSM.state.modelsPanel and PSM.state.modelsPanel:IsVisible() and PSM.ModelsPanel then
                    PSM.ModelsPanel:UpdateVisibleRows()
                end
                if PSM.state.ownedPetsPanel and PSM.state.ownedPetsPanel:IsVisible() then
                    PSM.OwnedPets:UpdatePanel()
                end
                if PSM.state.modelMagnificationPopup and PSM.state.modelMagnificationPopup:IsVisible() then
                    PSM.PopUpManager:UpdatePopupBackground(PSM.state.modelMagnificationPopup,
                        PSM.state.modelMagnificationPopup.currentDisplayId,
                        PSM.state.modelMagnificationPopup.currentPetData)
                end
                if PSM.state.petRoulettePopup and PSM.state.petRoulettePopup:IsVisible() then
                    PSM.PopUpManager:UpdatePopupBackground(PSM.state.petRoulettePopup,
                        PSM.state.petRoulettePopup.currentDisplayId,
                        PSM.state.petRoulettePopup.currentPetData)
                end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    -- ── Stop-animation checkbox ─────────────────────────────────────────────
    local stopAnimCheckbox = CreateLabelledCheckbox(
        panel, backgroundTypeDropdown, "TOPRIGHT", 40, 2,
        "StopAnimCheckbox", "Stop pet animations",
        PetStableManagementDB.settings.stopAnimation or PSM.Config.DEFAULT_STOP_ANIMATION
    )
    stopAnimCheckbox:SetScript("OnClick", function(cb)
        local checked = cb:GetChecked()
        PetStableManagementDB.settings.stopAnimation = checked
        IterateAllVisibleModels(function(model)
            ApplyAnimationStateToModel(model, checked)
        end)
    end)

    -- ── Reset button ────────────────────────────────────────────────────────
    local resetButton = CreateFrame("Button", addonName .. "ResetButton", panel, "UIPanelButtonTemplate")
    resetButton:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -RESET_BUTTON_MARGIN, RESET_BUTTON_MARGIN)
    resetButton:SetSize(RESET_BUTTON_WIDTH, RESET_BUTTON_HEIGHT)
    resetButton:SetText("Reset All Settings")
    PSM.UI:ApplyElvUISkin(resetButton, "button")

    resetButton:SetScript("OnClick", function()
        local cfg = PSM.Config

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

        -- Suppress OnValueChanged side-effects while pushing default values
        isResetting = true
        opacitySlider:SetValue(cfg.DEFAULT_OPACITY)
        zoomSlider:SetValue(cfg.DEFAULT_MODEL_ZOOM)
        viewAngleSlider:SetValue(cfg.DEFAULT_MODEL_VIEW_ANGLE)
        verticalPositionSlider:SetValue(cfg.DEFAULT_MODEL_VERTICAL_POSITION)
        horizontalPositionSlider:SetValue(cfg.DEFAULT_MODEL_HORIZONTAL_POSITION)
        isResetting = false

        -- Sync label text
        _G[opacitySlider:GetName()            .. "Text"]:SetText(opacityLabel(cfg.DEFAULT_OPACITY))
        _G[zoomSlider:GetName()               .. "Text"]:SetText(zoomLabel(cfg.DEFAULT_MODEL_ZOOM))
        _G[viewAngleSlider:GetName()          .. "Text"]:SetText(angleLabel(cfg.DEFAULT_MODEL_VIEW_ANGLE))
        _G[verticalPositionSlider:GetName()   .. "Text"]:SetText(vertLabel(cfg.DEFAULT_MODEL_VERTICAL_POSITION))
        _G[horizontalPositionSlider:GetName() .. "Text"]:SetText(horizLabel(cfg.DEFAULT_MODEL_HORIZONTAL_POSITION))

         stopAnimCheckbox:SetChecked(cfg.DEFAULT_STOP_ANIMATION)
         openWithStableCheckbox:SetChecked(cfg.DEFAULT_OPEN_WITH_STABLE)
         UIDropDownMenu_SetText(petsPerColumnDropdown, cfg.DEFAULT_PETS_PER_COLUMN)
        UIDropDownMenu_SetText(backgroundTypeDropdown, backgroundTypeLabels[cfg.DEFAULT_BACKGROUND_TYPE])

        -- Apply all defaults to visible models
        ApplyCurrentGlobalsToAllModels()

        -- Refresh panels to apply reset settings including background
        if PSM.state.panel and PSM.state.panel:IsVisible() then PSM.UI:RenderPanel() end
        if PSM.state.modelsPanel and PSM.ModelsPanel then
            PSM.ModelsPanel:UpdateModelsPanelLayout()
            PSM.ModelsPanel:UpdateVisibleRows()
        end
        if PSM.state.ownedPetsPanel and PSM.state.ownedPetsPanel:IsVisible() then
            PSM.OwnedPets:UpdatePanel()
        end
        if PSM.state.modelMagnificationPopup and PSM.state.modelMagnificationPopup:IsVisible() then
            PSM.PopUpManager:UpdatePopupBackground(PSM.state.modelMagnificationPopup,
                PSM.state.modelMagnificationPopup.currentDisplayId,
                PSM.state.modelMagnificationPopup.currentPetData)
        end
        if PSM.state.petRoulettePopup and PSM.state.petRoulettePopup:IsVisible() then
            PSM.PopUpManager:UpdatePopupBackground(PSM.state.petRoulettePopup,
                PSM.state.petRoulettePopup.currentDisplayId,
                PSM.state.petRoulettePopup.currentPetData)
        end
        
    end)
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