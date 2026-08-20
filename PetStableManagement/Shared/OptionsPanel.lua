-- OptionsPanel.lua
-- Options panel integration for PetStableManagement

local _, ns = ...

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
    if ns.state.panel and ns.state.panel:IsVisible() then
        for _, row in ipairs(ns.state.rows) do
            if row and row.model and row.model:IsVisible() then
                callback(row.model)
            end
        end
    end

    for _, stateKey in ipairs({ "modelViewRows", "groupedViewRows" }) do
        if ns.state[stateKey] then
            for _, row in ipairs(ns.state[stateKey]) do
                if row and row.model and row.model:IsVisible() then
                    callback(row.model)
                end
            end
        end
    end

    if ns.state.modelsPanel and ns.state.modelsPanel:IsVisible() then
        for _, row in ipairs(ns.state.modelsPanel.modelRows or {}) do
            if row and row.model and row.model:IsVisible() then
                callback(row.model)
            end
        end
    end

    for _, popupKey in ipairs({ "petRoulettePopup", "modelMagnificationPopup" }) do
        local popup = ns.state[popupKey]
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
    local cfg = ns.Config
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
        local popup = ns.state[key]
        if popup and popup:IsVisible() then
            ns.PopUpManager:UpdatePopupBackground(popup, popup.currentDisplayId, popup.currentPetData)
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
    local state = ns.state

    if state.panel and state.panel:IsVisible() then ns.UI:RenderPanel() end

    if state.modelsPanel and ns.Browser.ModelsPanel then
        if opts.relayout then
            ns.Browser.ModelsPanel:UpdateModelsPanelLayout()
            ns.Browser.ModelsPanel:UpdateVisibleRows()
        elseif state.modelsPanel:IsVisible() then
            ns.Browser.ModelsPanel:UpdateVisibleRows()
        end
    end

    if state.ownedPetsPanel and state.ownedPetsPanel:IsVisible() then
        ns.OwnedPets:UpdatePanel()
    end

    if opts.opacity and state.teamsPanel and state.teamsPanel:IsVisible() then
        ns.TeamsPanel:UpdateOpacity()
    end

    if opts.popups then RefreshPopupBackgrounds() end
end

-------------------------------------------------------------------------------
-- Option definitions
--
-- Each option knows its own persistence (a plain `settings[key]`, or a `get`/`set`
-- pair for the rare one that isn't -- see the minimap checkbox) and its own side
-- effects beyond that write (`apply`). BuildOption is the one place that reads and
-- writes them, and Reset All Settings walks this same list, so a 12th option is one
-- row here rather than a hand-built widget, a hand-written onClick, and a third copy
-- in the reset handler that has to be remembered separately.
--
-- `apply` always re-reads from PetStableManagementDB rather than taking the new
-- value as an argument -- the write has already landed by the time it runs, so
-- there is one source of truth for "what is the setting right now" instead of two
-- (the argument and the DB) that could disagree.
-------------------------------------------------------------------------------

local function ApplyModelReapply()
    ns.state.modelViews = {}
    ApplyCurrentGlobalsToAllModels()
end

-- Value currently in effect: `get()` if the option supplies one, else
-- `settings[key]` falling back to `default` -- nil-coalescing, not `or`, because a
-- boolean option whose default is `true` (openWithStable) must still let an explicit
-- `false` stick; `or` would silently flip it back.
local function OptionValue(spec)
    if spec.get then return spec.get() end
    local v = PetStableManagementDB.settings[spec.key]
    if v == nil then return spec.default end
    return v
end

local function WriteOption(spec, value)
    if spec.set then
        spec.set(value)
        return
    end
    PetStableManagementDB.settings[spec.key] = value
    if spec.apply then spec.apply() end
end

-- Built inside OnShow, not at file scope: every value below reads `ns.Config`, and
-- capturing another module's table into a file-scope local is the snapshot-not-
-- reference trap this codebase specifically avoids (see CLAUDE.md).
local function BuildOptions(cfg)
    return {
        {
            kind    = "checkbox",
            name    = "ShowMinimapCheckbox",
            label   = ns.L("Show minimap button"),
            -- Shown by default -- matches the `hide = false` Events.lua seeds into a
            -- fresh PetStableManagementDB on first ADDON_LOADED.
            default = true,
            get     = function() return not PetStableManagementDB.settings.minimapButton.hide end,
            set     = function(checked)
                PetStableManagementDB.settings.minimapButton.hide = not checked
                if checked then ns.Minimap:Show() else ns.Minimap:Hide() end
            end,
        },
        {
            kind    = "checkbox",
            name    = "OpenWithStableCheckbox",
            key     = "openWithStable",
            label   = ns.L("Open with the Stable window"),
            default = cfg.DEFAULT_OPEN_WITH_STABLE,
        },
        {
            kind      = "slider",
            name      = "OpacitySlider",
            key       = "opacity",
            title     = ns.L("UI Opacity:"),
            default   = cfg.DEFAULT_OPACITY,
            min       = cfg.MIN_TRANSPARENCY,
            max       = cfg.MAX_TRANSPARENCY,
            step      = 0.01,
            round     = 2,
            lowLabel  = "10%",
            highLabel = "100%",
            format    = function(v) return ns.L("Opacity: %d%%", math.floor(v * 100)) end,
            apply     = function()
                -- Covers every panel that draws its own backdrop, the Ability Browser
                -- and Special Tames included. Only the teams panel needs telling
                -- separately, hence `opacity = true` below.
                ns.Config:UpdateColors()
                ns.PanelManager:UpdatePanelBackgrounds()
                RefreshOpenPanels({ opacity = true })
            end,
        },
        {
            kind      = "slider",
            name      = "ZoomSlider",
            key       = "modelZoom",
            title     = ns.L("Zoom:"),
            default   = cfg.DEFAULT_MODEL_ZOOM,
            min       = cfg.MIN_MODEL_ZOOM,
            max       = cfg.MAX_MODEL_ZOOM,
            step      = 0.01,
            round     = 2,
            lowLabel  = "50%",
            highLabel = "200%",
            format    = function(v) return ns.L("Zoom: %d%%", math.floor(v * 100)) end,
            apply     = ApplyModelReapply,
        },
        {
            kind      = "slider",
            name      = "ViewAngleSlider",
            key       = "modelViewAngle",
            title     = ns.L("View Angle:"),
            default   = cfg.DEFAULT_MODEL_VIEW_ANGLE,
            min       = cfg.MIN_MODEL_VIEW_ANGLE,
            max       = cfg.MAX_MODEL_VIEW_ANGLE,
            step      = 1,
            round     = 0,
            lowLabel  = "-180°",
            highLabel = "180°",
            format    = function(v) return ns.L("View Angle: %d°", math.floor(v)) end,
            apply     = ApplyModelReapply,
        },
        {
            kind      = "slider",
            name      = "VerticalPositionSlider",
            key       = "modelVerticalPosition",
            title     = ns.L("Vertical Positioning (Z-axis):"),
            default   = cfg.DEFAULT_MODEL_VERTICAL_POSITION,
            min       = cfg.MIN_MODEL_VERTICAL_POSITION,
            max       = cfg.MAX_MODEL_VERTICAL_POSITION,
            step      = 0.01,
            round     = 2,
            lowLabel  = "-100%",
            highLabel = "100%",
            format    = function(v) return ns.L("Vertical Position: %d%%", math.floor(v * 100)) end,
            apply     = ApplyModelReapply,
        },
        {
            kind      = "slider",
            name      = "HorizontalPositionSlider",
            key       = "modelHorizontalPosition",
            title     = ns.L("Horizontal Positioning (Y-axis):"),
            default   = cfg.DEFAULT_MODEL_HORIZONTAL_POSITION,
            min       = cfg.MIN_MODEL_HORIZONTAL_POSITION,
            max       = cfg.MAX_MODEL_HORIZONTAL_POSITION,
            step      = 0.01,
            round     = 2,
            lowLabel  = "-100%",
            highLabel = "100%",
            format    = function(v) return ns.L("Horizontal Position: %d%%", math.floor(v * 100)) end,
            apply     = ApplyModelReapply,
        },
        {
            kind    = "dropdown",
            name    = "PetsPerColumnDropdown",
            key     = "petsPerColumn",
            title   = ns.L("Pets Per Column in Browser:"),
            default = cfg.DEFAULT_PETS_PER_COLUMN,
            choices = (function()
                local list = {}
                for i = cfg.MIN_PETS_PER_COLUMN, cfg.MAX_PETS_PER_COLUMN do
                    list[#list + 1] = { value = i, text = "  " .. i }
                end
                return list
            end)(),
            -- No displayText override: unified with backgroundType below, both now
            -- show their list text (padded) as the current-selection text too.
            apply = function()
                -- Column count only affects the browser's grid; nothing else repaints.
                if ns.state.modelsPanel and ns.Browser.ModelsPanel then
                    ns.Browser.ModelsPanel:UpdateModelsPanelLayout()
                    ns.Browser.ModelsPanel:UpdateVisibleRows()
                end
            end,
        },
        {
            kind    = "dropdown",
            name    = "BackgroundTypeDropdown",
            key     = "backgroundType",
            title   = ns.L("Pet Model Background:"),
            default = cfg.DEFAULT_BACKGROUND_TYPE,
            choices = (function()
                local labels = {
                    simple       = "  " .. ns.L("Simple"),
                    stablemaster = "  " .. ns.L("Stable Master"),
                    custom       = "  " .. ns.L("Custom"),
                }
                local list = {}
                for _, bgType in ipairs(cfg.BACKGROUND_TYPES) do
                    list[#list + 1] = { value = bgType, text = labels[bgType] }
                end
                return list
            end)(),
            apply = function() RefreshOpenPanels({ popups = true }) end,
        },
        {
            kind    = "checkbox",
            name    = "StopAnimCheckbox",
            key     = "stopAnimation",
            label   = ns.L("Stop pet animations"),
            default = cfg.DEFAULT_STOP_ANIMATION,
            apply   = function()
                local checked = PetStableManagementDB.settings.stopAnimation
                IterateAllVisibleModels(function(model)
                    ApplyAnimationStateToModel(model, checked)
                end)
            end,
        },
    }
end

-- A dropdown's display text for a given value, found by scanning its own `choices`
-- -- the default, since `choices` already carries the labels and a second copy
-- would only be one more thing to keep in sync with it. `petsPerColumn` overrides
-- via `displayText` instead (see BuildOptions): its display text has never matched
-- its list text (no leading-space indent).
local function TextForChoice(spec, value)
    for _, choice in ipairs(spec.choices) do
        if choice.value == value then return choice.text end
    end
end

local function DisplayText(spec, value)
    if spec.displayText then return spec.displayText(value) end
    return TextForChoice(spec, value)
end

-------------------------------------------------------------------------------
-- Panel definition
-------------------------------------------------------------------------------

local panel = ns.Widgets.Frame(nil)
panel.name = addonName
panel:Hide()

panel:SetScript("OnShow", function(self)
    -- Clear the script immediately so widget creation only ever runs once,
    -- even if an error occurs partway through.
    self:SetScript("OnShow", nil)

    local Widgets = ns.Widgets
    local cfg     = ns.Config
    local OPTIONS = BuildOptions(cfg)

    local byKey = {}
    for _, spec in ipairs(OPTIONS) do
        byKey[spec.key or spec.name] = spec
    end

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

    -- Builds the widget for one spec and wires its persistence/apply through
    -- WriteOption. Layout is still the caller's job -- `point` (checkbox/dropdown)
    -- or `anchorWidget`/`anchorOffset` (slider, via LabelledSlider) -- since where a
    -- control sits is a real per-panel decision, not something a generic builder
    -- should be guessing at.
    local function BuildOption(spec, layout)
        local widget, title
        if spec.kind == "checkbox" then
            widget = Widgets.CheckBox(panel, {
                name    = addonName .. spec.name,
                label   = spec.label,
                checked = OptionValue(spec),
                point   = layout.point,
                onClick = function(cb) WriteOption(spec, cb:GetChecked() or false) end,
            })
        elseif spec.kind == "slider" then
            widget, title = LabelledSlider(layout.anchorWidget, layout.anchorOffset, spec.title, {
                name      = addonName .. spec.name,
                min       = spec.min,
                max       = spec.max,
                step      = spec.step,
                value     = OptionValue(spec),
                lowLabel  = spec.lowLabel,
                highLabel = spec.highLabel,
                format    = spec.format,
                onChange  = function(value)
                    local scale = 10 ^ spec.round
                    WriteOption(spec, math.floor(value * scale) / scale)
                end,
            })
        elseif spec.kind == "dropdown" then
            widget = Dropdown(spec.name, layout.point)
            local current = OptionValue(spec)
            UIDropDownMenu_SetText(widget, DisplayText(spec, current))
            UIDropDownMenu_Initialize(widget, function()
                local selected = OptionValue(spec)
                for _, choice in ipairs(spec.choices) do
                    local info = UIDropDownMenu_CreateInfo()
                    info.text    = choice.text
                    info.value   = choice.value
                    info.checked = (selected == choice.value)
                    info.func    = function(btn)
                        WriteOption(spec, btn.value)
                        UIDropDownMenu_SetText(widget, DisplayText(spec, btn.value))
                    end
                    UIDropDownMenu_AddButton(info)
                end
            end)
        end
        spec.widget = widget
        return widget, title
    end

    -- Title
    local title = Widgets.Label(panel, {
        fontObject = "GameFontNormalLarge",
        text       = addonName,
        point      = { "TOPLEFT", RESET_BUTTON_MARGIN, -RESET_BUTTON_MARGIN },
    })

    -- ── Minimap checkbox ────────────────────────────────────────────────────
    local showMinimapCheckbox = BuildOption(byKey.ShowMinimapCheckbox, {
        point = { "TOPLEFT", title, "BOTTOMLEFT", CHECKBOX_INDENT_X, CHECKBOX_INDENT_Y },
    })

    -- ── Open with Stable checkbox (to the right of minimap checkbox) ─────────
    BuildOption(byKey.openWithStable, {
        point = { "TOPLEFT", showMinimapCheckbox, "TOPRIGHT", 150, 0 },
    })

    -- ── Opacity slider ──────────────────────────────────────────────────────
    local opacitySlider = BuildOption(byKey.opacity, {
        anchorWidget = showMinimapCheckbox, anchorOffset = SECTION_SPACING,
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
        text       = ns.L("Pet Model Settings"),
        point      = { "TOPLEFT", divider, "BOTTOMLEFT", 0, SECTION_SPACING },
    })

    -- ── Model sliders ───────────────────────────────────────────────────────
    local zoomSlider = BuildOption(byKey.modelZoom, {
        anchorWidget = petModelTitle, anchorOffset = SECTION_SPACING,
    })
    local viewAngleSlider = BuildOption(byKey.modelViewAngle, {
        anchorWidget = zoomSlider, anchorOffset = SLIDER_SLIDER_SPACING,
    })
    local verticalPositionSlider = BuildOption(byKey.modelVerticalPosition, {
        anchorWidget = viewAngleSlider, anchorOffset = SLIDER_SLIDER_SPACING,
    })
    local horizontalPositionSlider = BuildOption(byKey.modelHorizontalPosition, {
        anchorWidget = verticalPositionSlider, anchorOffset = SLIDER_SLIDER_SPACING,
    })

    -- ── Pets-per-column dropdown ────────────────────────────────────────────
    local petsPerColumnTitle = Widgets.Label(panel, {
        fontObject = "GameFontNormal",
        text       = byKey.petsPerColumn.title,
        point      = { "TOPLEFT", horizontalPositionSlider, "BOTTOMLEFT", 0, SLIDER_SLIDER_SPACING },
    })
    BuildOption(byKey.petsPerColumn, {
        point = { "TOPLEFT", petsPerColumnTitle, "BOTTOMLEFT", DROPDOWN_OFFSET_X, DROPDOWN_OFFSET_Y },
    })

    -- ── Background type dropdown ────────────────────────────────────────────
    local backgroundTypeTitle = Widgets.Label(panel, {
        fontObject = "GameFontNormal",
        text       = byKey.backgroundType.title,
        point      = { "TOPLEFT", petsPerColumnTitle, "TOPRIGHT", 20, 0 },
    })
    local backgroundTypeDropdown = BuildOption(byKey.backgroundType, {
        point = { "TOPLEFT", backgroundTypeTitle, "BOTTOMLEFT", DROPDOWN_OFFSET_X, DROPDOWN_OFFSET_Y },
    })

    -- ── Stop-animation checkbox ─────────────────────────────────────────────
    BuildOption(byKey.stopAnimation, {
        point = { "TOPLEFT", backgroundTypeDropdown, "TOPRIGHT", 40, CHECKBOX_DROPDOWN_OFFSET },
    })

    -- ── Reset button ────────────────────────────────────────────────────────
    Widgets.Button(panel, {
        name  = addonName .. "ResetButton",
        text  = ns.L("Reset All Settings"),
        width = ns.Theme.CONTROL.BUTTON_W.L,
        point = { "BOTTOMRIGHT", panel, "BOTTOMRIGHT", -RESET_BUTTON_MARGIN, RESET_BUTTON_MARGIN },
        onClick = function()
            -- Write every resettable option's default to DB, then move its widget to
            -- match -- silently, or each control would re-write the value we just
            -- wrote and re-run its own `apply` on the way past (five times over for
            -- the model sliders alone). `apply` still runs once, below, after every
            -- default has landed -- except the minimap checkbox, whose `set` is a
            -- single cheap Show()/Hide() rather than a batched reapply, so there's
            -- nothing to gain by deferring it.
            for _, spec in ipairs(OPTIONS) do
                if spec.resettable ~= false then
                    if spec.set then
                        spec.set(spec.default)
                    else
                        PetStableManagementDB.settings[spec.key] = spec.default
                    end

                    local w = spec.widget
                    if spec.kind == "checkbox" then
                        w:SetChecked(spec.default)
                    elseif spec.kind == "slider" then
                        w:SetValueSilently(spec.default)
                    elseif spec.kind == "dropdown" then
                        UIDropDownMenu_SetText(w, DisplayText(spec, spec.default))
                    end
                end
            end

            -- Chosen popup sizes are a setting too, so Reset returns them to auto-sizing.
            --
            -- Clearing `userSized` is not enough on its own: auto-sizing only ever
            -- recomputes height, so a dragged *width* would survive Reset untouched. The
            -- popup is put back to the size it was created at, and auto-sizing takes the
            -- height from there on the next populate.
            PetStableManagementDB.settings.popupSizes = {}
            for _, key in ipairs({ "modelMagnificationPopup", "petRoulettePopup" }) do
                local popup = ns.state[key]
                if popup then
                    popup.userSized = nil
                    if popup.defaultWidth and popup.defaultHeight then
                        popup:SetSize(popup.defaultWidth, popup.defaultHeight)
                    end
                end
            end

            if PetStableManagementDB.filters then
                PetStableManagementDB.filters.selectedTamingRules = nil
                PetStableManagementDB.filters.selectedConditions = nil
                PetStableManagementDB.filters.familiesAppliedFromAbilities = nil
                PetStableManagementDB.filters.selectedFamiliesFromAbilities = nil
                PetStableManagementDB.filters.selectedModelsFamilies = nil
                PetStableManagementDB.filters.selectedExpansions = nil
                PetStableManagementDB.filters.selectedLocations = nil
            end
            ns.Selections:Clear("tamingRules")
            ns.state.familiesAppliedFromAbilities = nil
            ns.state.abilitiesFamilySet = nil
            ns.state.modelViews = {}

            -- Families/expansions/locations default to *all selected*, not none. Clearing
            -- the tables to {} left every checkbox unticked, which is the one state the
            -- browser treats as "hide everything" -- and it stuck, because the all-true
            -- seeding only runs when the panel is first built.
            --
            -- The browser's own Reset Filters button already does this correctly, so call
            -- that rather than keeping a second, worse copy here. Guarded on the module
            -- being *loaded* rather than available: if it was never loaded there is no
            -- panel to fix, and an empty table is exactly what the seeding wants to see.
            if ns.Browser.ModelsFilters and ns.state.modelsPanel then
                ns.Browser.ModelsFilters:ResetAllFilters(ns.state.modelsPanel)
            else
                ns.Selections:Clear("families")
                ns.Selections:Clear("expansions")
                ns.Selections:Clear("locations")
            end

            -- Applying the default opacity is this handler's job precisely because the
            -- silent SetValue above skipped the slider's own handler. Reset used to
            -- write the default opacity to the DB and repaint nothing with it, so the
            -- UI kept the old opacity until something unrelated forced a redraw.
            ns.Config:UpdateColors()
            ns.PanelManager:UpdatePanelBackgrounds()

            ApplyCurrentGlobalsToAllModels()
            RefreshOpenPanels({ relayout = true, popups = true, opacity = true })
        end,
    })
end)

-------------------------------------------------------------------------------
-- Register with the game's settings system
-------------------------------------------------------------------------------

-- `InterfaceOptions_AddCategory` predates Dragonflight's Settings API and does not
-- exist on this addon's target Interface versions (120007, 121000); the branch that
-- used to test for it first was unreachable dead weight, not a real fallback.
local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
local categoryId = category.ID
Settings.RegisterAddOnCategory(category)

ns.state.optionsPanel      = panel
ns.state.optionsCategoryId = categoryId
