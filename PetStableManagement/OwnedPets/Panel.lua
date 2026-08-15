-- OwnedPets/Panel.lua
-- Main panel creation for PetStableManagement

_G.PSM = _G.PSM or {}
local PSM = _G.PSM

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Apply a saved or explicit view mode, updating all button states.
local function ApplyViewMode(panel, mode)
    mode = mode or PSM.state.panelViewMode or PetStableManagementDB.settings.panelViewMode or "list"

    local isGrid    = (mode == "grid")
    local isGrouped = (mode == "grouped")

    if PSM.UI.GridView then
        if isGrid then PSM.UI.GridView:Enable() else PSM.UI.GridView:Disable() end
    end
    if PSM.UI.GroupedView then
        if isGrouped then PSM.UI.GroupedView:Enable() else PSM.UI.GroupedView:Disable() end
    end

    -- Reset all three buttons, then disable the active one
    panel.listButton:Enable()
    panel.gridButton:Enable()
    panel.groupedButton:Enable()
    if mode == "list" then
        panel.listButton:Disable()
    elseif mode == "grid" then
        panel.gridButton:Disable()
    else
        panel.groupedButton:Disable()
    end

    PSM.state.panelViewMode = mode
end

-- ---------------------------------------------------------------------------
-- Panel construction
-- ---------------------------------------------------------------------------

function PSM.UI:BuildPanel()
    if PSM.state.panel then return end
    self:CreateOwnedPetsPanel()
end

function PSM.UI:CreateOwnedPetsPanel()
    local config = {
        width        = PSM.Config.DEFAULT_PANEL_WIDTH,
        height       = PSM.Config.DEFAULT_PANEL_HEIGHT,
        minWidth     = PSM.Config.MIN_PANEL_WIDTH,
        minHeight    = PSM.Config.MIN_PANEL_HEIGHT,
        position     = {
            point         = "TOPLEFT",
            relativeTo    = "StableFrame",
            relativePoint = "TOPRIGHT",
            x = 0, y = 0,
        },
        title        = "Pet Stable Management",

        onHide = function(panel)
            PSM.PanelManager:CleanupPanel(panel)
            -- Stable-pet data is intentionally kept; other panels (e.g. Pet Groups) rely on it.
        end,

        onShow = function(panel)
            if #PSM.state.stablePets == 0 then
                PSM.Data:LoadPersistentDataForDisplay(false)
            end
            PSM.UI:RenderPanel()

            PSM.C_Timer.After(0.05, function() PSM.UI:UpdateFilterUI() end)

            -- Restore the saved view mode slightly later so buttons exist
            PSM.C_Timer.After(0.1, function()
                ApplyViewMode(panel, PetStableManagementDB.settings.panelViewMode)
            end)
        end,

        onResize = function(panel)
            PSM.C_Timer.After(0.01, function()
                PSM.UI:RenderPanel(true)  -- true = preserve scroll position
            end)
        end,
    }

    local panel = PSM.PanelManager:CreateBasePanel("panel", config)
    self:AddOwnedPetsElements(panel)
    return panel
end

-- ---------------------------------------------------------------------------
-- OwnedPets-specific UI elements
-- ---------------------------------------------------------------------------

function PSM.UI:AddOwnedPetsElements(panel)
    local Widgets = PSM.Widgets
    local Theme   = PSM.Theme

    -- Search box ----------------------------------------------------------
    PSM.PanelManager:CreateSearchBox(panel, function()
        PSM.UI:UpdatePanel()
    end, {
        placeholder = "Search pets...",
    })

    -- Filters & sort buttons ----------------------------------------------
    PSM.UI:BuildFilters(panel)
    PSM.UI:BuildSortButtons(panel)

    -- Scroll frame --------------------------------------------------------
    local scrollFrame = Widgets.Frame(panel, {
        frameType = "ScrollFrame",
        template  = "UIPanelScrollFrameTemplate",
        skin      = "scrollframe",
        point     = {
            { "TOPLEFT",      10, -145 },
            { "BOTTOMRIGHT", -30,   35 },
        },
    })

    -- Decorative border behind the rows
    local rowsFrame = Widgets.Frame(panel, {
        backdrop = "TOOLTIP",
        color    = PSM.Config.COLORS.BACKGROUND,
        level    = panel:GetFrameLevel() - 1,
        point    = {
            { "TOPLEFT",     scrollFrame, "TOPLEFT",     -5,  5 },
            { "BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT",  5, -5 },
        },
    })

    local content = Widgets.Frame(scrollFrame, {
        size = { scrollFrame:GetWidth() - 10, 500 },
    })
    scrollFrame:SetScrollChild(content)

    -- Ensure the scrollbar always occupies its reserved space
    if scrollFrame.ScrollBar then
        scrollFrame.ScrollBar:SetAlpha(1)
        PSM.Skin.Apply(scrollFrame.ScrollBar, "scrollbar")
    end

    panel.scrollOffset     = 0
    panel.gridScrollOffset = 0
    panel.gridScrollSnapping = false
    panel.isResizing         = false

    -- Virtual-scroll hook -------------------------------------------------
    if scrollFrame.ScrollBar then
        scrollFrame.ScrollBar:HookScript("OnValueChanged", function(self, value)
            local mode = PSM.state.panelViewMode

            if mode == "grid" then
                local rowH      = PSM.Config.GRID_ROW_HEIGHT
                local newOffset = math.floor(value / rowH + 0.5)

                if newOffset ~= panel.gridScrollOffset then
                    panel.gridScrollOffset = newOffset
                    PSM.C_Timer.After(0.01, function() PSM.UI:UpdateVisibleRows() end)
                end

                -- Snap to row boundary
                if not panel.gridScrollSnapping then
                    local snapped = newOffset * rowH
                    if math.abs(value - snapped) > 1 then
                        panel.gridScrollSnapping = true
                        self:SetValue(snapped)
                        panel.gridScrollSnapping = false
                    end
                end

            elseif mode == "grouped" then
                PSM.C_Timer.After(0.01, function() PSM.UI:UpdateVisibleRows() end)

            else -- list
                local rowH      = PSM.Config.ROW_HEIGHT
                local newOffset = math.floor(value / rowH)
                if newOffset ~= panel.scrollOffset then
                    panel.scrollOffset = newOffset
                    PSM.C_Timer.After(0.01, function() PSM.UI:UpdateVisibleRows() end)
                end
            end
        end)
    end

    -- Stats label ---------------------------------------------------------
    panel.statsText = Widgets.Label(panel, {
        fontSize = Theme.SIZE.SMALL,
        outline  = true,
        color    = Theme.COLOR.GOLD,
        point    = { "BOTTOM", 0, 15 },
        text     = "Showing: 0 pets  |  Duplicates: 0 pets (0 groups)",
    })

    -- Resize handler (scroll-position-preserving) -------------------------
    PSM.PanelManager:CreateScrollPreservingResizeHandler(
        panel, scrollFrame, content,
        function(preserveScroll) PSM.UI:RenderPanel(preserveScroll) end
    )

    PSM.C_Timer.After(0.01, function()
        content:SetWidth(scrollFrame:GetWidth())
    end)

    -- Buttons -------------------------------------------------------------
    -- Every button on this panel is the same shape. Three builders used to exist for
    -- it: MakeButton, MakeViewButton, and Export written out by hand -- differing only
    -- in where they anchor and what they do on click.
    local function PanelButton(opts)
        return Widgets.Button(panel, {
            point      = opts.point,
            size       = { PSM.Config.PANEL_BUTTON_WIDTH, PSM.Config.PANEL_BUTTON_HEIGHT },
            text       = opts.text,
            fontObject = "GameFontNormalSmall",
            onClick    = opts.onClick,
            tooltip    = opts.tooltip,
        })
    end

    -- Export (leftmost; anchors to the panel edge instead of a sibling)
    panel.exportButton = PanelButton({
        text    = "Export",
        point   = { "TOPLEFT", 10, -5 },
        onClick = function() PSM.Export:ShowExportDialog() end,
    })

    panel.teamsButton = PanelButton({
        text    = "Pet Teams",
        point   = { "TOPLEFT", panel.exportButton, "TOPRIGHT", 5, 0 },
        onClick = function() PSM.TeamsPanel:Show() end,
        tooltip = PSM.Teams:ButtonTooltipSpec(),
    })

    -- View-mode buttons (right side, created right-to-left) ---------------
    local function ViewButton(text, mode, rightAnchor)
        return PanelButton({
            text    = text,
            point   = { "TOPRIGHT", rightAnchor, "TOPLEFT", -5, 0 },
            onClick = function()
                ApplyViewMode(panel, mode)
                PetStableManagementDB.settings.panelViewMode = mode
            end,
        })
    end

    -- The maximize button is optional (PanelManager skips it for
    -- showMaximizeButton = false), and a nil anchor is not an error -- SetPoint would
    -- quietly fall back to the parent and put this row against the panel's left edge.
    -- The close button is the one control every panel is guaranteed.
    panel.groupedButton = ViewButton("Grouped", "grouped", panel.maximizeButton or panel.closeButton)
    panel.gridButton    = ViewButton("Grid",    "grid",    panel.groupedButton)
    panel.listButton    = ViewButton("List",    "list",    panel.gridButton)

    -- Disable the button matching the initial view mode
    ApplyViewMode(panel, PSM.state.panelViewMode or PetStableManagementDB.settings.panelViewMode)

    -- Store shared references ---------------------------------------------
    PSM.state.scrollFrame = scrollFrame
    PSM.state.content     = content
    panel.scrollFrame     = scrollFrame
    panel.content         = content
    panel.rowsFrame       = rowsFrame
end