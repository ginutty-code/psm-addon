-- OwnedPets/Panel.lua
-- Main panel creation for PetStableManagement

local _, ns = ...

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Apply a saved or explicit view mode, updating all button states.
local function ApplyViewMode(panel, mode)
    mode = mode or ns.state.panelViewMode or PetStableManagementDB.settings.panelViewMode or "list"

    local isGrid    = (mode == "grid")
    local isGrouped = (mode == "grouped")

    if ns.UI.GridView then
        if isGrid then ns.UI.GridView:Enable() else ns.UI.GridView:Disable() end
    end
    if ns.UI.GroupedView then
        if isGrouped then ns.UI.GroupedView:Enable() else ns.UI.GroupedView:Disable() end
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

    ns.state.panelViewMode = mode
end

-- ---------------------------------------------------------------------------
-- Panel construction
-- ---------------------------------------------------------------------------

function ns.UI:BuildPanel()
    if ns.state.panel then return end
    self:CreateOwnedPetsPanel()
end

function ns.UI:CreateOwnedPetsPanel()
    local config = {
        -- The collapsed-rail width. An expanded rail adds its own width on the right
        -- (onShow / BuildFilters' onToggle), so the pet list keeps its size either way.
        width        = ns.Config.DEFAULT_PANEL_WIDTH,
        height       = ns.Config.DEFAULT_PANEL_HEIGHT,
        -- Width is pinned to the default (MIN_OWNED_PETS_WIDTH == DEFAULT_PANEL_WIDTH);
        -- a hand resize only grows it. Expanded, the floor rises by the rail width
        -- (SetMinWidth in onShow / onResize / BuildFilters' onToggle).
        minWidth     = ns.Config.MIN_OWNED_PETS_WIDTH,
        minHeight    = ns.Config.MIN_OWNED_PETS_HEIGHT,
        position     = {
            point         = "TOPLEFT",
            relativeTo    = "StableFrame",
            relativePoint = "TOPRIGHT",
            x = 0, y = 0,
        },
        title        = ns.L("Pet Stable Management"),

        onHide = function(panel)
            ns.PanelManager:CleanupPanel(panel)
            -- Stable-pet data is intentionally kept; other panels (e.g. Pet Groups) rely on it.
        end,

        onShow = function(panel)
            -- Restore the saved rail state before the first render. ApplyInitialState
            -- does the visible half (boxes, position, glyph); the panel width is this
            -- panel's own concern, since only here do we know whether the current
            -- width already includes the rail strip. The panel is built at
            -- DEFAULT_PANEL_WIDTH == the *collapsed* width, so a saved-expanded rail
            -- needs +railW added once. panel._railWidened is the tracking bit,
            -- also maintained by BuildFilters' onToggle.
            if panel.rail then
                panel.rail:ApplyInitialState()
                local wantWide = not panel.rail:IsCollapsed()
                local minW = ns.Config.MIN_OWNED_PETS_WIDTH
                    + (wantWide and panel.rail.width or 0)
                -- Order matters against the pinned floor: drop the minimum before a
                -- shrink, raise it after a grow, so SetWidth is never clamped.
                if not wantWide and panel._railWidened then
                    ns.PanelManager:SetMinWidth(panel, minW)
                    ns.PanelManager:SetWidthAnchored(panel, panel:GetWidth() - panel.rail.width)
                    panel._railWidened = false
                elseif wantWide and not panel._railWidened then
                    ns.PanelManager:SetWidthAnchored(panel, panel:GetWidth() + panel.rail.width)
                    panel._railWidened = true
                end
                -- Assert every show: a rebuilt panel starts from config's minWidth
                -- (the collapsed value) regardless of the saved state.
                ns.PanelManager:SetMinWidth(panel, minW)
            end

            if #ns.state.stablePets == 0 then
                ns.Data:LoadPersistentDataForDisplay(false)
            end
            ns.UI:RenderPanel()

            ns.C_Timer.After(0.05, function() ns.UI:UpdateFilterUI() end)

            -- Restore the saved view mode slightly later so buttons exist
            ns.C_Timer.After(0.1, function()
                ApplyViewMode(panel, PetStableManagementDB.settings.panelViewMode)
            end)
        end,

        onResize = function(panel)
            -- Maximize resets bounds from config; re-assert the rail-aware minimum so
            -- a restore of an expanded panel keeps the wider floor.
            if panel.rail then
                ns.PanelManager:SetMinWidth(panel, ns.Config.MIN_OWNED_PETS_WIDTH
                    + (panel.rail:IsCollapsed() and 0 or panel.rail.width))
            end
            ns.C_Timer.After(0.01, function()
                ns.UI:RenderPanel(true)  -- true = preserve scroll position
            end)
        end,
    }

    local panel = ns.PanelManager:CreateBasePanel("panel", config)
    self:AddOwnedPetsElements(panel)
    return panel
end

-- ---------------------------------------------------------------------------
-- OwnedPets-specific UI elements
-- ---------------------------------------------------------------------------

function ns.UI:AddOwnedPetsElements(panel)
    local Widgets = ns.Widgets
    local Theme   = ns.Theme

    -- Search box ----------------------------------------------------------
    ns.PanelManager:CreateSearchBox(panel, function()
        ns.UI:UpdatePanel()
    end, {
        placeholder = ns.L("Search pets..."),
    })

    -- Filter summary ----------------------------------------------------------
    -- The faint "Filters: ..." line under the search box, mirroring the Models
    -- Browser's, so the user can see what is narrowing the list without opening
    -- each dropdown. ns.UI:UpdateFilterSummary (OwnedPets/Filters.lua) fills it;
    -- _ApplyCachedRender and UpdateFilterUI both call that.
    panel.filterSummaryText = Widgets.Label(panel, {
        fontSize = Theme.SIZE.SMALL,
        color    = Theme.COLOR.FAINT,
        point    = { "TOP", panel.searchBox, "BOTTOM", 0, -6 },
        text     = "",
    })

    -- Filters & sort buttons ----------------------------------------------
    -- LIST_TOP is where the pet list's *rows* start: below the search / reset row
    -- (bottom ~-86 at the default font) and below BuildFilters' sortDrop (y = -92)
    -- so nothing overlaps. Eyeball figure -- nudge in-game.
    local LIST_TOP = -128
    -- rowsFrame draws its silver border ROW_BORDER_INSET px outside the scroll
    -- frame on every edge, so the list's visible top is LIST_TOP + this. The rail
    -- starts there too, lining its boxes up with that border rather than with the
    -- first row inside it.
    local ROW_BORDER_INSET = 5

    -- BuildFilters creates the left rail (Tools / Show Only / Filters boxes) and
    -- leaves panel.toolsFrame empty for the Tools buttons added below.
    ns.UI:BuildFilters(panel, LIST_TOP + ROW_BORDER_INSET)
    ns.UI:BuildSortButtons(panel)

    -- Tools box contents ------------------------------------------------------
    -- Export and Pet Teams moved off the action row (it was at its width limit at
    -- MIN_PANEL_WIDTH -- see docs/Owned_pets_toolbar_plan.md) into the rail's
    -- Tools box. The box reserves a third slot; Team Roulette drops into it with
    -- the Random Team feature.
    local function ToolButton(text, anchorTo, onClick, tooltip)
        return Widgets.Button(panel.toolsFrame, {
            point      = anchorTo
                and { "TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -5 }
                or  { "TOPLEFT", panel.toolsFrame.sectionHeader, "BOTTOMLEFT", 3, -6 },
            width      = Theme.CONTROL.BUTTON_W.M,
            text       = text,
            fontObject = "GameFontNormalSmall",
            onClick    = onClick,
            tooltip    = tooltip,
        })
    end

    panel.exportButton = ToolButton(ns.L("Export"), nil,
        function() ns.Export:ShowExportDialog() end)
    panel.teamsButton  = ToolButton(ns.L("Pet Teams"), panel.exportButton,
        function() ns.TeamsPanel:Show() end, ns.Teams:ButtonTooltipSpec())
    -- Turns the current filter into a playable team; see OwnedPets/TeamRoulette.lua.
    -- Panel-wide filters, so it belongs on the chrome and works in all three views.
    panel.teamRouletteButton = ToolButton(ns.L("Team Roulette"), panel.teamsButton,
        function() ns.TeamRoulette:Show() end, function()
            -- The draw pool, not the raw filtered list: CurrentPool further restricts
            -- filteredPets to pets THIS character owns (a team can only be applied with
            -- your own pets), so the count here matches what the roll actually draws
            -- from -- filteredPets alone counts the whole account.
            return {
                anchor = "ANCHOR_BOTTOM",
                title  = ns.L("Team Roulette"),
                lines  = {{
                    text  = ns.L("Roll a random team from the %d available pets",
                                 #ns.TeamRoulette:CurrentPool()),
                    color = ns.Theme.COLOR.WHITE,
                }},
            }
        end)

    -- Scroll frame --------------------------------------------------------
    -- Left edge follows panel.rail's TOPRIGHT (the container, not a box). CreateRail
    -- anchors that edge to the same panel-x in both states -- TOPLEFT+x expanded,
    -- TOPRIGHT+x collapsed -- and BuildFilters' onToggle changes the panel width by
    -- the rail width to match, so this list is the *same width* whichever state the
    -- rail is in (only the panel's right edge moves). The rail top sits
    -- ROW_BORDER_INSET above this so it lines up with rowsFrame's border, not with
    -- the first row -- so drop the scroll frame back down by that much to keep the
    -- rows where LIST_TOP puts them.
    local scrollFrame = Widgets.Frame(panel, {
        frameType = "ScrollFrame",
        template  = "UIPanelScrollFrameTemplate",
        skin      = "scrollframe",
        point     = {
            { "TOPLEFT",     panel.rail, "TOPRIGHT", 25, -ROW_BORDER_INSET },
            { "BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 35 },
        },
    })

    -- Decorative border behind the rows. borderColor matches CreateRailBox's boxes
    -- (SILVER) -- without it the TOOLTIP edge keeps its default full-white tint and
    -- reads as visibly heavier than the rail's grey border right beside it.
    local rowsFrame = Widgets.Frame(panel, {
        backdrop    = "TOOLTIP",
        color       = ns.Config.COLORS.BACKGROUND,
        borderColor = Theme.COLOR.SILVER,
        level       = panel:GetFrameLevel() - 1,
        point    = {
            { "TOPLEFT",     scrollFrame, "TOPLEFT",     -ROW_BORDER_INSET,  ROW_BORDER_INSET },
            { "BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT",  ROW_BORDER_INSET, -ROW_BORDER_INSET },
        },
    })

    local content = Widgets.Frame(scrollFrame, {
        size = { scrollFrame:GetWidth() - 10, 500 },
    })
    scrollFrame:SetScrollChild(content)

    -- Ensure the scrollbar always occupies its reserved space
    if scrollFrame.ScrollBar then
        scrollFrame.ScrollBar:SetAlpha(1)
        ns.Skin.Apply(scrollFrame.ScrollBar, "scrollbar")
    end

    panel.scrollOffset     = 0
    panel.gridScrollOffset = 0
    panel.gridScrollSnapping = false
    panel.isResizing         = false

    -- Virtual-scroll hook -------------------------------------------------
    if scrollFrame.ScrollBar then
        scrollFrame.ScrollBar:HookScript("OnValueChanged", function(self, value)
            local mode = ns.state.panelViewMode

            if mode == "grid" then
                local rowH      = ns.Config.GRID_ROW_HEIGHT
                local newOffset = math.floor(value / rowH + 0.5)

                if newOffset ~= panel.gridScrollOffset then
                    panel.gridScrollOffset = newOffset
                    ns.C_Timer.After(0.01, function() ns.UI:UpdateVisibleRows() end)
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
                ns.C_Timer.After(0.01, function() ns.UI:UpdateVisibleRows() end)

            else -- list
                local rowH      = ns.Config.ROW_HEIGHT
                local newOffset = math.floor(value / rowH)
                if newOffset ~= panel.scrollOffset then
                    panel.scrollOffset = newOffset
                    ns.C_Timer.After(0.01, function() ns.UI:UpdateVisibleRows() end)
                end
            end
        end)
    end

    -- Stats label ---------------------------------------------------------
    panel.statsText = ns.PanelManager:CreateFooterLabel(panel, {
        outline = true,
        text    = ns.L("Showing: 0 pets  |  Duplicates: 0 pets (0 groups)"),
    })

    -- Resize handler (scroll-position-preserving) -------------------------
    ns.PanelManager:CreateScrollPreservingResizeHandler(panel, scrollFrame, content)

    ns.C_Timer.After(0.01, function()
        content:SetWidth(scrollFrame:GetWidth())
    end)

    -- Buttons -------------------------------------------------------------
    -- Export and Pet Teams are built above, in the rail's Tools box.
    --
    -- View-mode buttons (right side, created right-to-left) ---------------
    local function ViewButton(text, mode, rightAnchor)
        return ns.PanelManager:CreateViewButton(panel, {
            text        = text,
            rightAnchor = rightAnchor,
            onClick     = function()
                ApplyViewMode(panel, mode)
                PetStableManagementDB.settings.panelViewMode = mode
            end,
        })
    end

    -- The maximize button is optional (PanelManager skips it for
    -- showMaximizeButton = false), and a nil anchor is not an error -- CreateViewButton
    -- falls back to panel.maximizeButton or panel.closeButton itself when no explicit
    -- rightAnchor is given. The close button is the one control every panel is guaranteed.
    panel.groupedButton = ViewButton(ns.L("Grouped"), "grouped")
    panel.gridButton    = ViewButton(ns.L("Grid"),    "grid",    panel.groupedButton)
    panel.listButton    = ViewButton(ns.L("List"),    "list",    panel.gridButton)

    -- Disable the button matching the initial view mode
    ApplyViewMode(panel, ns.state.panelViewMode or PetStableManagementDB.settings.panelViewMode)

    -- Store shared references ---------------------------------------------
    ns.state.scrollFrame = scrollFrame
    ns.state.content     = content
    panel.scrollFrame     = scrollFrame
    panel.content         = content
    panel.rowsFrame       = rowsFrame
end