-- OwnedPets/Panel.lua
-- Main panel creation for PetStableManagement

local addonName = "PetStableManagement"

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
        escKeyframe  = "PetStableManagementPanel",

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
    -- Search box ----------------------------------------------------------
    PSM.PanelManager:CreateSearchBox(panel, function(searchText)
        PSM.UI:UpdatePanel()
    end, {
        placeholder = "Search pets...",
    })

    -- Filters & sort buttons ----------------------------------------------
    PSM.UI:BuildFilters(panel)
    PSM.UI:BuildSortButtons(panel)

    -- Scroll frame --------------------------------------------------------
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     10,  -145)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30,   35)

    -- Decorative border behind the rows
    local rowsFrame = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    rowsFrame:SetPoint("TOPLEFT",     scrollFrame, "TOPLEFT",     -5,  5)
    rowsFrame:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT",  5, -5)
    rowsFrame:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left=4, right=4, top=4, bottom=4 },
    })
    rowsFrame:SetBackdropColor(unpack(PSM.Config.COLORS.BACKGROUND))
    rowsFrame:SetFrameLevel(panel:GetFrameLevel() - 1)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(scrollFrame:GetWidth() - 10, 500)
    scrollFrame:SetScrollChild(content)

    -- Ensure the scrollbar always occupies its reserved space
    if scrollFrame.ScrollBar then
        scrollFrame.ScrollBar:SetAlpha(1)
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
    panel.statsText = panel:CreateFontString(nil, "OVERLAY")
    panel.statsText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    panel.statsText:SetPoint("BOTTOM", 0, 15)
    panel.statsText:SetText("Showing: 0 pets  |  Duplicates: 0 pets (0 groups)")
    panel.statsText:SetTextColor(1, 0.82, 0)

    -- Resize handler (scroll-position-preserving) -------------------------
    PSM.PanelManager:CreateScrollPreservingResizeHandler(
        panel, scrollFrame, content,
        function(preserveScroll) PSM.UI:RenderPanel(preserveScroll) end
    )

    PSM.C_Timer.After(0.01, function()
        content:SetWidth(scrollFrame:GetWidth())
    end)

    -- Buttons (bottom-left) -----------------------------------------------
    local function MakeButton(text, parent, anchor, onClick, tooltip)
        local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        btn:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 5, 0)
        btn:SetSize(PSM.Config.PANEL_BUTTON_WIDTH, PSM.Config.PANEL_BUTTON_HEIGHT)
        btn:SetText(text)
        btn:SetNormalFontObject("GameFontNormalSmall")
        btn:SetScript("OnClick", onClick)
        if tooltip then
            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                GameTooltip:SetText(tooltip.title)
                if tooltip.body then GameTooltip:AddLine(tooltip.body, 1, 1, 1) end
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        PSM.UI:ApplyElvUISkin(btn, "button")
        return btn
    end

    -- Export (leftmost; anchors to panel edge instead of a sibling)
    panel.exportButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.exportButton:SetPoint("TOPLEFT", 10, -5)
    panel.exportButton:SetSize(PSM.Config.PANEL_BUTTON_WIDTH, PSM.Config.PANEL_BUTTON_HEIGHT)
    panel.exportButton:SetText("Export")
    panel.exportButton:SetNormalFontObject("GameFontNormalSmall")
    panel.exportButton:SetScript("OnClick", function()
        PSM.Export:ShowExportDialog()
    end)
    PSM.UI:ApplyElvUISkin(panel.exportButton, "button")

    panel.teamsButton = MakeButton("Pet Teams", panel, panel.exportButton,
        function() PSM.TeamsPanel:Show() end,
        {
            title = "View and manage saved pet teams",
            body  = function()
                return "You have " .. (PSM.Teams:GetTeamCount() or 0) .. " saved team(s)"
            end,
        }
    )

    -- View-mode buttons (right side, created right-to-left) ---------------
    local function MakeViewButton(text, mode, rightAnchor)
        local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        btn:SetPoint("TOPRIGHT", rightAnchor, "TOPLEFT", -5, 0)
        btn:SetSize(PSM.Config.PANEL_BUTTON_WIDTH, PSM.Config.PANEL_BUTTON_HEIGHT)
        btn:SetText(text)
        btn:SetNormalFontObject("GameFontNormalSmall")
        btn:SetScript("OnClick", function()
            ApplyViewMode(panel, mode)
            PetStableManagementDB.settings.panelViewMode = mode
        end)
        PSM.UI:ApplyElvUISkin(btn, "button")
        return btn
    end

    panel.groupedButton = MakeViewButton("Grouped", "grouped", panel.maximizeButton)
    panel.gridButton    = MakeViewButton("Grid",    "grid",    panel.groupedButton)
    panel.listButton    = MakeViewButton("List",    "list",    panel.gridButton)

    -- Disable the button matching the initial view mode
    ApplyViewMode(panel, PSM.state.panelViewMode or PetStableManagementDB.settings.panelViewMode)

    -- Store shared references ---------------------------------------------
    PSM.state.scrollFrame = scrollFrame
    PSM.state.content     = content
    panel.scrollFrame     = scrollFrame
    panel.content         = content
    panel.rowsFrame       = rowsFrame

    if scrollFrame.ScrollBar then
        PSM.UI:ApplyElvUISkin(scrollFrame.ScrollBar, "scrollbar")
    end
end