-- ModelsBrowser/NPCRow.lua
-- Lightweight, model-free row rendering for the NPC view of the Pet Models
-- Browser: a sortable, column-toggleable text table. No PlayerModel widgets
-- are created here on purpose -- that's the cost this view exists to avoid.

_G.PSM = _G.PSM or {}
local PSM = _G.PSM
PSM.NPCRow = PSM.NPCRow or {}

local ROW_HEIGHT    = 36
-- The band is a Widgets.SectionHeader, so its height is the kit's. Read rather than
-- repeated: this value also positions every row below it (UpdateNPCPanelLayout) and
-- feeds the rows-per-page calculation, so a second copy that drifted from the theme
-- token would misplace the whole table rather than just look wrong.
local HEADER_HEIGHT = PSM.Theme.CONTROL.SECTION_HEADER
local ID_LINE_HEIGHT = 14 -- display-id pills wrap onto a second line at this height before "+N" kicks in

-- How far the whole table -- header bar *and* every row -- sits inside petsFrame,
-- which draws the silver TOOLTIP border on its own edges. 5px is not a new guess:
-- it is the same inset the Tools and Show Only boxes already give their
-- SectionHeaders inside an identical TOOLTIP-backdrop frame (ModelsPanel.lua).
--
-- Header and rows must share this: column x positions come from one
-- RecomputeColumnLayout, but the header's buttons anchor to the header frame while cells
-- anchor to their row frame, so an inset applied to one and not the other drifts every
-- column out of step with the column under it.
local TABLE_INSET = 5

-- This view packs a lot of columns into a row, so its text runs half a point
-- smaller than PSM.Theme.SIZE.TINY. Local rather than a theme token: nothing
-- outside this table wants it, and a token used once is a token nobody can place.
local CELL_FONT_SIZE = 9.5

PSM.NPCRow.ROW_HEIGHT    = ROW_HEIGHT
PSM.NPCRow.HEADER_HEIGHT = HEADER_HEIGHT
PSM.NPCRow.TABLE_INSET   = TABLE_INSET

--------------------------------------------------------------------------------
-- COLUMN DEFINITIONS
--------------------------------------------------------------------------------

-- `width` is a *default*, overridden per character once a column is dragged
-- (npcViewColumnWidths). displayIds is the flex column -- its `width` is only a
-- placeholder, since RecomputeColumnLayout gives it whatever the others leave.
--
-- These have to add up: at the panel's original expanded width (1100, now 1115 --
-- see MODELS_CONFIG.PANEL_WIDTH) the table's usable width was a known ~815, and the
-- widths below are sized against that rather than picked per column. The left rail
-- can now collapse (docs/Collapsible_left_rail_plan.md 5b), widening the table, and
-- RecomputeColumnLayout's flex column absorbs whatever that frees -- these defaults
-- are the *narrow* baseline, not a hard requirement. As set, Display IDs keeps 106px
-- with every column shown and 204px at the default set, and the longest real values
-- still fit.
PSM.NPCRow.COLUMNS = {
    { key = "npcId",          label = PSM.L("ID"),           width = 40,  optional = true,  default = true  },
    { key = "name",           label = PSM.L("Name"),         width = 120, optional = false, default = true  },
    { key = "family",         label = PSM.L("Family"),       width = 72,  optional = true,  default = true  },
    { key = "classification", label = PSM.L("Class"),        width = 55,  optional = true,  default = true  },
    { key = "nameKeeper",     label = PSM.L("NK"),            width = 30,  optional = true,  default = true  },
    { key = "zone",           label = PSM.L("Zone"),         width = 100, optional = true,  default = true  },
    { key = "continent",      label = PSM.L("Continent"),    width = 92,  optional = true,  default = false },
    { key = "expansion",      label = PSM.L("Expansion"),    width = 80,  optional = true,  default = true  },
    { key = "faction",        label = PSM.L("A/H"),           width = 30,  optional = true,  default = true  },
    -- 30, not 28: MIN_COLUMN_WIDTH would raise it to 30 at layout time anyway, and a
    -- declared default that never renders is a number nobody can trust.
    { key = "note",           label = PSM.L("Note"),         width = 30,  optional = true,  default = true  },
    { key = "displayIds",     label = PSM.L("Display IDs"),  width = 120, optional = false, default = true  },
}

PSM.NPCRow.COLUMNS_BY_KEY = {}
for _, c in ipairs(PSM.NPCRow.COLUMNS) do
    PSM.NPCRow.COLUMNS_BY_KEY[c.key] = c
end

function PSM.NPCRow:GetDefaultVisibleColumns()
    local t = {}
    for _, col in ipairs(self.COLUMNS) do
        if col.optional then t[col.key] = col.default end
    end
    return t
end

--------------------------------------------------------------------------------
-- SORTING
--------------------------------------------------------------------------------

local CLASS_RANK  = { Normal = 1, Rare = 2, ["Rare Elite"] = 3, Elite = 4 }
local CLASS_COLOR = {
    Rare           = {0.85, 0.65, 0.13},
    ["Rare Elite"] = {0.85, 0.30, 0.30},
    Elite          = {0.85, 0.30, 0.30},
}

-- ModelsData ships ReactA/ReactH pre-parsed as numbers -- no more
-- string.match per sort pass / per row draw.
local function ParseFactionScore(allianceReact, hordeReact)
    return (allianceReact or 0) + (hordeReact or 0)
end

local function FormatFaction(allianceReact, hordeReact)
    local function seg(v, letter)
        if not v then return "" end
        local color = v == -1 and {1,0,0} or v == 0 and {1,1,0} or {0,1,0}
        return string.format("|cff%02x%02x%02x%s|r", color[1]*255, color[2]*255, color[3]*255, letter)
    end
    return seg(allianceReact, "A") .. seg(hordeReact, "H")
end

local function GetSortValue(panel, item, field)
    if field == "npcId"          then return item.npcId or 0 end
    if field == "classification" then return CLASS_RANK[item.classification] or 0 end
    if field == "nameKeeper"     then return item.nameKeeper and 1 or 0 end
    if field == "faction"        then return ParseFactionScore(item.reactA, item.reactH) end
    if field == "displayIds"     then return (item.displayIds and item.displayIds[1]) or 0 end
    if field == "note" then
        local id = item.npcId
        local hasUser = PSM_UserNotes and PSM_UserNotes[id] and PSM_UserNotes[id] ~= ""
        local hasSeed = PSM.NotesData and PSM.NotesData[id]
        return (hasUser or hasSeed) and 1 or 0
    end
    if field == "expansion" then
        local order = PSM.ModelsDataLoader and PSM.ModelsDataLoader._EXPANSION_ORDER
        return (order and order[item.expansion]) or 999
    end
    if field == "continent" then
        local cont = panel and panel.locationContinents and panel.locationContinents[item.uiMapName]
        return (cont or "\255"):lower()
    end
    local raw = item[field == "zone" and "uiMapName" or field]
    return (raw or ""):lower()
end

-- Decorate-sort-undecorate: precompute sort keys once instead of recomputing
-- them on every O(n log n) comparator call.
function PSM.NPCRow:SortItems(panel, items)
    local field = panel.npcSortField or "name"
    local asc = panel.npcSortAsc
    if asc == nil then asc = true end

    local n = #items
    local decorated = {}
    for i = 1, n do
        local item = items[i]
        decorated[i] = { item = item, key = GetSortValue(panel, item, field), nameKey = (item.name or ""):lower() }
    end

    table.sort(decorated, function(a, b)
        if a.key == b.key then
            return a.nameKey < b.nameKey
        end
        if asc then return a.key < b.key else return a.key > b.key end
    end)

    for i = 1, n do
        items[i] = decorated[i].item
    end
    return items
end

--------------------------------------------------------------------------------
-- COLUMN LAYOUT
--------------------------------------------------------------------------------

-- Padding inside the header/row frames before the first column and after the last.
local CELL_PAD         = 10
local COLUMN_GAP       = 6   -- horizontal gap between two columns
local MIN_COLUMN_WIDTH = 30
local FLEX_COLUMN      = "displayIds"

-- Width available to the columns themselves. Header and rows are both TABLE_INSET
-- narrower than petsFrame on each side and carry CELL_PAD of their own padding
-- inside that, so the columns get what is left after both. Derived rather than a
-- literal: this is what keeps the flex column inside the frame when the inset moves.
local function TableWidth(panel)
    return panel.petsFrame:GetWidth() - (TABLE_INSET * 2) - (CELL_PAD * 2)
end

-- What the flex (Display IDs) column should get once every other column sits at its
-- default width -- the point past which extra table width only inflates this one
-- column. 150 is comfortably above the ~106px it holds today with every column shown
-- (the COLUMNS comment) where "the longest real values still fit", without ballooning
-- it for the default column set (which then gets ~250px).
local FLEX_TARGET_WIDTH = 150

-- The petsFrame width past which the NPC view has no more real estate to give: every
-- non-flex column (including the optional ones) at its default `width`, every gap, the
-- flex column at FLEX_TARGET_WIDTH, plus the insets petsFrame adds around the table.
-- ModelsPanel caps the panel on this -- wider than this and the NPC view just pads
-- Display IDs while the Models view just spaces its two columns further apart, dead
-- space in both. Derived from COLUMNS so it tracks the column list.
function PSM.NPCRow:NaturalPetsFrameWidth()
    local nonFlex, count = 0, 0
    for _, col in ipairs(self.COLUMNS) do
        count = count + 1
        if col.key ~= FLEX_COLUMN then nonFlex = nonFlex + col.width end
    end
    local tableWidth = nonFlex + COLUMN_GAP * math.max(0, count - 1) + FLEX_TARGET_WIDTH
    return tableWidth + (TABLE_INSET * 2) + (CELL_PAD * 2)
end

local function VisibleColumns(self, panel)
    local visible = {}
    for _, col in ipairs(self.COLUMNS) do
        if not col.optional or (panel.npcVisibleColumns and panel.npcVisibleColumns[col.key]) then
            table.insert(visible, col)
        end
    end
    return visible
end

local function StoredWidth(panel, col)
    local widths = panel.npcColumnWidths or {}
    return math.max(MIN_COLUMN_WIDTH, widths[col.key] or col.width)
end

function PSM.NPCRow:RecomputeColumnLayout(panel)
    if not panel or not panel.petsFrame then return {} end

    local totalWidth = TableWidth(panel)
    local visible    = VisibleColumns(self, panel)

    -- The stored/default non-flex widths are sized against a known ~815px table (see
    -- the COLUMNS comment). Once the panel is resizable it can be narrower than that,
    -- and without this the rightmost columns run straight off petsFrame's edge. So
    -- when the fixed columns plus the flex floor don't fit, scale the *shrinkable*
    -- non-flex columns by one shared factor -- columns already at MIN_COLUMN_WIDTH
    -- can't give, so they're held out of the pool and their width subtracted from the
    -- room first (otherwise the flex column absorbs the shortfall and overflows).
    -- factor == 1 at or above the design width, so nothing changes for a panel that
    -- hasn't been dragged narrow. The 0.35 clamp is a backstop -- MIN_WIDTH keeps the
    -- real factor well above it. (Revisits docs/Backlog.md's "proportional scaling
    -- declined" note, which said to reconsider this if the panel ever became resizable.)
    local pinnedNeed, shrinkNeed = 0, 0
    for _, col in ipairs(visible) do
        if col.key ~= FLEX_COLUMN then
            local w = StoredWidth(panel, col)
            if w <= MIN_COLUMN_WIDTH then pinnedNeed = pinnedNeed + MIN_COLUMN_WIDTH
            else                          shrinkNeed = shrinkNeed + w end
        end
    end
    local room   = totalWidth - COLUMN_GAP * math.max(0, #visible - 1) - MIN_COLUMN_WIDTH - pinnedNeed
    local factor = (shrinkNeed > 0 and room < shrinkNeed) and math.max(0.35, room / shrinkNeed) or 1
    panel._npcColumnScale = factor

    local layout = {}
    local x = CELL_PAD
    for _, col in ipairs(visible) do
        local width
        if col.key == FLEX_COLUMN then
            -- Flex column: absorbs whatever the fixed columns leave, which is what
            -- keeps the overall table width constant while they resize. With `factor`
            -- active the fixed columns have already been squeezed to fit, so this
            -- lands at MIN_COLUMN_WIDTH.
            width = math.max(MIN_COLUMN_WIDTH, totalWidth - (x - CELL_PAD))
        else
            local w = StoredWidth(panel, col)
            width = (w <= MIN_COLUMN_WIDTH) and w
                    or math.max(MIN_COLUMN_WIDTH, math.floor(w * factor))
        end
        table.insert(layout, { key = col.key, x = x, width = width })
        x = x + width + COLUMN_GAP
    end

    panel.npcColumnLayout = layout
    return layout
end

-- How wide `key` may be dragged before the flex column would be squeezed past its
-- minimum -- i.e. before the table would run off its own right edge.
--
-- This has to live here, not in the drag handler: because Display IDs absorbs the
-- remainder, "how wide may this column be?" is a question about every *other* visible
-- column, and the handler knows only the one under the cursor.
--
-- Returns nil when there is no cap to apply (the flex column itself, or a layout with
-- no flex column visible -- Display IDs is `optional = false`, so that is defensive).
--
-- Computed in *stored* width space. When RecomputeColumnLayout is scaling columns
-- (_npcColumnScale < 1, i.e. the panel is narrower than the design width) this cap is
-- only approximate -- but every other column has its own MIN_COLUMN_WIDTH floor, so
-- the recompute is self-limiting and an over-permissive cap cannot push anything off
-- the edge, only make neighbours a little narrower.
function PSM.NPCRow:MaxWidthForColumn(panel, key)
    if not panel or not panel.petsFrame then return nil end
    if key == FLEX_COLUMN then return nil end

    local visible = VisibleColumns(self, panel)
    local hasFlex = false
    local claimed = 0
    for _, col in ipairs(visible) do
        if col.key == FLEX_COLUMN then
            hasFlex = true
        elseif col.key ~= key then
            -- Every other column (both left and right) can shrink toward MIN_COLUMN_WIDTH
            claimed = claimed + MIN_COLUMN_WIDTH
        end
    end
    if not hasFlex then return nil end

    local budget = TableWidth(panel) - (COLUMN_GAP * (#visible - 1)) - MIN_COLUMN_WIDTH
    return math.max(MIN_COLUMN_WIDTH, budget - claimed)
end

-- Distributes `displayDelta` px of shrink (positive) or growth (negative), caused by
-- dragging `key` wider/narrower, across every visible column to key's right --
-- weighted by each one's last-drawn display width -- and writes the result back as
-- *stored* width (dividing by the scale factor, same conversion the dragged column's
-- own delta already uses). The flex column is deliberately left untouched: it has no
-- stored width of its own, so its share flows through automatically as whatever
-- RecomputeColumnLayout leaves over once the others claim theirs (conservation of the
-- fixed total table width).
function PSM.NPCRow:ShrinkColumnsRightOf(panel, key, displayDelta)
    if displayDelta == 0 then return end
    local layout = panel.npcColumnLayout
    if not layout then return end

    local layoutByKey = {}
    for _, l in ipairs(layout) do layoutByKey[l.key] = l end

    local passedKey, rightCols, rightTotal = false, {}, 0
    for _, col in ipairs(VisibleColumns(self, panel)) do
        if col.key == key then
            passedKey = true
        elseif passedKey then
            local w = (layoutByKey[col.key] and layoutByKey[col.key].width) or StoredWidth(panel, col)
            table.insert(rightCols, { col = col, width = w })
            rightTotal = rightTotal + w
        end
    end
    if rightTotal <= 0 then return end

    local f = panel._npcColumnScale or 1
    for _, entry in ipairs(rightCols) do
        if entry.col.key ~= FLEX_COLUMN then
            local share      = entry.width / rightTotal
            local newDisplay = math.max(MIN_COLUMN_WIDTH, entry.width - displayDelta * share)
            panel.npcColumnWidths[entry.col.key] = newDisplay / f
        end
    end
end

--------------------------------------------------------------------------------
-- COLUMN RESIZING
--------------------------------------------------------------------------------

-- Shared OnUpdate driver for column-boundary dragging (same pattern as the
-- model rotate/move drivers in RowManager.lua). Raw CreateFrame on purpose: this
-- is an invisible ticker with no parent and nothing to draw, not a widget.
local ResizeDriver = CreateFrame("Frame")

-- The handle's rule is white and varies only in opacity: a faint tick at rest so the
-- draggable column boundary is discoverable at all, near-solid on hover, solid while
-- dragging. White rather than gold -- the header band is itself dark gold
-- (Config.TAB.ACTIVE_BG), so a gold rule blended into it and was invisible at any
-- sane resting alpha. One place to say that, instead of four copies of
-- SetColorTexture(...).
local HANDLE_REST_ALPHA = 0.28
local function SetHandleAlpha(handle, alpha)
    local c = PSM.Theme.COLOR.WHITE
    handle.tex:SetColorTexture(c[1], c[2], c[3], alpha)
end

local function StopResize(handle)
    ResizeDriver.active = nil
    if handle.tex then SetHandleAlpha(handle, HANDLE_REST_ALPHA) end
    local panel = PSM.state.modelsPanel
    if panel and panel.npcColumnWidths then
        PetStableManagementDB.settings.npcViewColumnWidths = PSM.Utils.DeepCopy(panel.npcColumnWidths)
    end
    handle.startWidths = nil
    handle.startX = nil
    handle.lastDeltaX = nil
    handle.startLayoutByKey = nil
end

ResizeDriver:SetScript("OnUpdate", function(self)
    local handle = self.active
    if not handle then return end

    -- The cursor is almost always off the (6px-wide) handle by the time the
    -- button is released, so OnMouseUp on the handle can't be relied on to
    -- end the drag -- poll button state directly instead.
    if not IsMouseButtonDown("LeftButton") then
        StopResize(handle)
        return
    end

    local scale = UIParent:GetEffectiveScale()
    local x = GetCursorPosition() / scale
    local deltaX = x - (handle.startX or x)
    if deltaX ~= (handle.lastDeltaX or 0) then
        handle.lastDeltaX = deltaX
        handle.lastX = x
        local panel = PSM.state.modelsPanel
        if panel and handle.startWidths then
            local f = panel._npcColumnScale or 1
            local totalDelta = deltaX / f

            local visible = VisibleColumns(PSM.NPCRow, panel)
            local leftCols, rightCols = {}, {}
            local passedKey = false
            for _, col in ipairs(visible) do
                if not passedKey then
                    table.insert(leftCols, col)
                    if col.key == handle.columnKey then
                        passedKey = true
                    end
                else
                    table.insert(rightCols, col)
                end
            end

            if passedKey and (#leftCols > 0) and (#rightCols > 0) then
                local startWidths = handle.startWidths
                local startLayout = handle.startLayoutByKey or {}

                -- Left partition totals
                local startLeftTotal = 0
                local leftAvailable = 0
                for _, col in ipairs(leftCols) do
                    local w = startWidths[col.key] or col.width
                    startLeftTotal = startLeftTotal + w
                    leftAvailable = leftAvailable + math.max(0, w - MIN_COLUMN_WIDTH)
                end

                -- Right partition totals
                local startRightTotal = 0
                local rightAvailable = 0
                for _, col in ipairs(rightCols) do
                    local w
                    if col.key == FLEX_COLUMN then
                        w = (startLayout[col.key] or 120) / f
                    else
                        w = startWidths[col.key] or col.width
                    end
                    startRightTotal = startRightTotal + w
                    rightAvailable = rightAvailable + math.max(0, w - MIN_COLUMN_WIDTH)
                end

                -- Clamp totalDelta to available shrink capacity in either direction
                if totalDelta < -leftAvailable then totalDelta = -leftAvailable end
                if totalDelta > rightAvailable then totalDelta = rightAvailable end

                if totalDelta < 0 then
                    -- DRAGGING LEFT: left partition shrinks, right partition grows
                    local shrinkAmount = -totalDelta
                    for _, col in ipairs(leftCols) do
                        local w = startWidths[col.key] or col.width
                        local avail = math.max(0, w - MIN_COLUMN_WIDTH)
                        local share = (leftAvailable > 0) and (avail / leftAvailable) or 0
                        panel.npcColumnWidths[col.key] = w - (shrinkAmount * share)
                    end

                    local growAmount = -totalDelta
                    if startRightTotal > 0 then
                        for _, col in ipairs(rightCols) do
                            if col.key ~= FLEX_COLUMN then
                                local w = startWidths[col.key] or col.width
                                local share = w / startRightTotal
                                panel.npcColumnWidths[col.key] = w + (growAmount * share)
                            end
                        end
                    end
                elseif totalDelta > 0 then
                    -- DRAGGING RIGHT: right partition shrinks, left partition grows
                    local shrinkAmount = totalDelta
                    for _, col in ipairs(rightCols) do
                        if col.key ~= FLEX_COLUMN then
                            local w = startWidths[col.key] or col.width
                            local avail = math.max(0, w - MIN_COLUMN_WIDTH)
                            local share = (rightAvailable > 0) and (avail / rightAvailable) or 0
                            panel.npcColumnWidths[col.key] = w - (shrinkAmount * share)
                        end
                    end

                    local growAmount = totalDelta
                    if startLeftTotal > 0 then
                        for _, col in ipairs(leftCols) do
                            local w = startWidths[col.key] or col.width
                            local share = w / startLeftTotal
                            panel.npcColumnWidths[col.key] = w + (growAmount * share)
                        end
                    end
                else
                    -- totalDelta == 0: restore start widths
                    for _, col in ipairs(leftCols) do
                        panel.npcColumnWidths[col.key] = startWidths[col.key] or col.width
                    end
                    for _, col in ipairs(rightCols) do
                        if col.key ~= FLEX_COLUMN then
                            panel.npcColumnWidths[col.key] = startWidths[col.key] or col.width
                        end
                    end
                end

                PSM.NPCRow:ReflowVisibleRows(panel)
            end
        end
    end
end)

local function CreateResizeHandle(header, columnKey)
    local Widgets = PSM.Widgets

    local handle = Widgets.Frame(header, { width = 6 })
    handle:EnableMouse(true)
    handle.columnKey = columnKey

    handle.tex = Widgets.Texture(handle, {
        layer = "OVERLAY",
        width = 2,
        point = {
            { "TOP",    handle, "TOP",    0, 0 },
            { "BOTTOM", handle, "BOTTOM", 0, 0 },
        },
    })
    SetHandleAlpha(handle, HANDLE_REST_ALPHA)

    handle:SetScript("OnEnter", function(self) SetHandleAlpha(self, 0.9) end)
    handle:SetScript("OnLeave", function(self)
        if ResizeDriver.active ~= self then SetHandleAlpha(self, HANDLE_REST_ALPHA) end
    end)
    handle:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local scale = UIParent:GetEffectiveScale()
        self.lastX = GetCursorPosition() / scale
        self.startX = self.lastX
        self.lastDeltaX = 0
        local panel = PSM.state.modelsPanel
        if panel then
            panel.npcColumnWidths = panel.npcColumnWidths or {}
            self.startWidths = {}
            for _, col in ipairs(PSM.NPCRow.COLUMNS) do
                self.startWidths[col.key] = panel.npcColumnWidths[col.key] or col.width
            end
            local startLayoutByKey = {}
            if panel.npcColumnLayout then
                for _, l in ipairs(panel.npcColumnLayout) do
                    startLayoutByKey[l.key] = l.width
                end
            end
            self.startLayoutByKey = startLayoutByKey
        end
        ResizeDriver.active = self
        SetHandleAlpha(self, 1)
    end)
    handle:SetScript("OnMouseUp", function(self)
        if ResizeDriver.active == self then StopResize(self) end
    end)

    return handle
end

--------------------------------------------------------------------------------
-- HEADER ROW
--------------------------------------------------------------------------------

function PSM.NPCRow:CreateHeaderRow(parent)
    local Widgets = PSM.Widgets

    -- The same gold-on-dark bar as the "Show Only" filter group header. `inset = 0`
    -- because this one spans the full width of the table; no `text`, because the columns
    -- below fill it themselves.
    --
    -- Positioned in by TABLE_INSET on three sides so the gold band clears petsFrame's
    -- silver border rather than being drawn on top of it, while keeping its full
    -- HEADER_HEIGHT. UpdateNPCPanelLayout insets the rows by the same amount.
    local header = Widgets.SectionHeader(parent, {
        inset  = 0,
        point  = {
            { "TOPLEFT",  parent, "TOPLEFT",   TABLE_INSET, -TABLE_INSET },
            { "TOPRIGHT", parent, "TOPRIGHT", -TABLE_INSET, -TABLE_INSET },
        },
    })
    header:SetClipsChildren(true)
    header.labelButtons = {}
    header.resizeHandles = {}

    for _, col in ipairs(self.COLUMNS) do
        local btn = Widgets.Frame(header, {
            frameType = "Button",
            height    = HEADER_HEIGHT - 2,
        })
        btn.text = Widgets.SectionHeaderLabel(btn, {
            point = { "LEFT", 4, 0 },
        })
        btn.text:SetWordWrap(false)
        btn.columnKey = col.key

        -- The sorted column carries a small arrow rather than a " ^"/" v" text
        -- marker. Interface\Buttons\ui-sortarrow is Blizzard's own column-sort
        -- glyph and points down at rest; UpdateHeaderRow flips it vertically for
        -- the ascending direction and shows it only on the active sort column.
        -- Tinted white -- the raw texture is a dim gold that disappears against
        -- the header band.
        btn.sortArrow = Widgets.Texture(btn, {
            layer       = "OVERLAY",
            texture     = "Interface\\Buttons\\ui-sortarrow",
            size        = { 8, 8 },
            point       = { "RIGHT", 0, 0 },
            vertexColor = PSM.Theme.COLOR.WHITE,
            hidden      = true,
        })

        btn:SetScript("OnClick", function()
            local panel = PSM.state.modelsPanel
            if not panel then return end
            if panel.npcSortField == col.key then
                panel.npcSortAsc = not panel.npcSortAsc
            else
                panel.npcSortField = col.key
                panel.npcSortAsc = true
            end
            PetStableManagementDB.settings.npcViewSort = { field = panel.npcSortField, asc = panel.npcSortAsc }
            PSM.NPCRow:UpdateHeaderRow(panel)
            PSM.ModelsPanel:UpdateVisibleRows()
        end)

        header.labelButtons[col.key] = btn

        if col.key ~= "displayIds" then
            header.resizeHandles[col.key] = CreateResizeHandle(header, col.key)
        end
    end

    header:Hide()
    return header
end

function PSM.NPCRow:UpdateHeaderRow(panel)
    local header = panel.npcHeaderRow
    if not header then return end

    local layout = self:RecomputeColumnLayout(panel)
    for _, btn in pairs(header.labelButtons) do btn:Hide() end
    for _, handle in pairs(header.resizeHandles) do handle:Hide() end

    for _, colLayout in ipairs(layout) do
        local col = self.COLUMNS_BY_KEY[colLayout.key]
        local btn = header.labelButtons[colLayout.key]
        if col and btn then
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", header, "TOPLEFT", colLayout.x, 0)
            btn:SetSize(colLayout.width, HEADER_HEIGHT - 2)
            btn.text:SetText(col.label)
            local isSorted = (panel.npcSortField == colLayout.key)
            if isSorted then
                -- UI-SortArrow points down; flip it vertically for ascending.
                if panel.npcSortAsc then
                    btn.sortArrow:SetTexCoord(0, 1, 1, 0)
                else
                    btn.sortArrow:SetTexCoord(0, 1, 0, 1)
                end
                btn.sortArrow:Show()
            else
                btn.sortArrow:Hide()
            end

            -- Bound the text to the column width so it never overflows, truncating
            -- with "..." if the column is too narrow. When sorted, reserve space on
            -- the right so the label never overlaps the sort arrow.
            local reservedRight = isSorted and 18 or 4
            local availWidth = math.max(1, colLayout.width - 4 - reservedRight)
            btn.text:SetWidth(availWidth)
            btn:Show()

            local handle = header.resizeHandles[colLayout.key]
            if handle then
                handle:ClearAllPoints()
                handle:SetPoint("TOP", header, "TOPLEFT", colLayout.x + colLayout.width + 3, 0)
                handle:SetHeight(HEADER_HEIGHT)
                handle:Show()
            end
        end
    end
end

--------------------------------------------------------------------------------
-- COLUMNS VISIBILITY PICKER
--------------------------------------------------------------------------------

function PSM.NPCRow:CreateColumnsPicker(panel, anchorTo)
    local optionalCols = {}
    for _, col in ipairs(self.COLUMNS) do
        if col.optional then table.insert(optionalCols, col) end
    end

    local Widgets = PSM.Widgets

    local btn = Widgets.Button(panel, {
        width      = PSM.Theme.CONTROL.BUTTON_W.S,
        point      = { "TOPRIGHT", anchorTo, "TOPLEFT", -5, 0 },
        text       = PSM.L("Columns"),
        fontObject = "GameFontNormalSmall",
    })

    local POPOUT_WIDTH = 140

    local popout = Widgets.Frame(panel, {
        size        = { POPOUT_WIDTH, 10 + PSM.Theme.CONTROL.CHECKBOX_ROW * #optionalCols },
        point       = { "TOPRIGHT", btn, "BOTTOMRIGHT", 0, -2 },
        strata      = "DIALOG",
        backdrop    = "TOOLTIP",
        color       = PSM.Config.COLORS.BACKGROUND,
        borderColor = PSM.Theme.COLOR.SILVER,
        hidden      = true,
    })

    local CHECKBOX_X = 6
    -- Extend each checkbox's clickable area rightward across its label (a negative
    -- inset expands the hit rect) so clicking the column name toggles it too. Derived
    -- from the box's right edge to the popout's inner edge rather than hard-coded, so
    -- it stays correct now that the box is 20px rather than 16.
    local hitExtend = -(POPOUT_WIDTH - CHECKBOX_X - PSM.Theme.CONTROL.CHECKBOX - CHECKBOX_X)

    local y = -6
    for _, col in ipairs(optionalCols) do
        Widgets.CheckBox(popout, {
            point           = { "TOPLEFT", CHECKBOX_X, y },
            label           = col.label,
            labelFontObject = "GameFontHighlightSmall",
            checked         = panel.npcVisibleColumns and panel.npcVisibleColumns[col.key],
            onClick         = function(self)
                panel.npcVisibleColumns[col.key] = self:GetChecked() and true or false
                PetStableManagementDB.settings.npcViewColumns = PSM.Utils.DeepCopy(panel.npcVisibleColumns)
                PSM.NPCRow:UpdateHeaderRow(panel)
                PSM.ModelsPanel:UpdateVisibleRows()
            end,
        }):SetHitRectInsets(0, hitExtend, 0, 0)
        y = y - PSM.Theme.CONTROL.CHECKBOX_ROW
    end

    btn:SetScript("OnClick", function()
        if popout:IsShown() then popout:Hide() else popout:Show() end
    end)

    -- A transient popout must not outlive its owner being hidden. Hiding the panel
    -- (Escape, or the close button) hides the popout as a child, but leaves its own
    -- shown state set -- so it came back on screen the next time the browser opened,
    -- still holding a click the user had long since moved on from. Same shape as the
    -- context menu that survived Escape on the Grouped View header.
    panel:HookScript("OnHide", function() popout:Hide() end)

    -- Close on click-away. OnUpdate only ticks while popout is shown, so this
    -- is a no-op cost otherwise; non-modal (doesn't swallow clicks) so a click
    -- on another button both closes the picker and still performs that click.
    popout:SetScript("OnUpdate", function(self)
        if (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
            and not self:IsMouseOver() and not btn:IsMouseOver() then
            self:Hide()
        end
    end)

    btn:Hide()
    panel.npcColumnsButton  = btn
    panel.npcColumnsPopout  = popout
    return btn
end

--------------------------------------------------------------------------------
-- DATA ROW
--------------------------------------------------------------------------------

local ID_LINK_COLOR        = {0.35, 0.62, 0.85} -- not owned: link blue
local ID_LINK_HOVER        = {0.55, 0.75, 0.95}
local ID_LINK_OWNED_COLOR  = {0.35, 0.9,  0.35} -- owned: green, matching ModelRow's owned convention
local ID_LINK_OWNED_HOVER  = {0.6,  1,    0.6}

-- Name opens the Wowhead NPC page, Zone opens TomTom waypoints -- both mirror
-- the exact hyperlink actions already available in the Model Magnifier. Name
-- always has an npcId to link to, so it's always styled as a link; Zone only
-- has TomTom coordinate data for some NPCs, so it's only styled as a link
-- (same blue as the Display ID pills) when that data actually exists --
-- otherwise it stays the default neutral text color, matching that it isn't
-- clickable.
local CLICKABLE_CELL_COLUMNS = { name = true, zone = true }
local CELL_NEUTRAL_COLOR = {0.79, 0.79, 0.76}

-- GameTooltip has no maximum width -- it sizes itself to its widest line. An NPC with
-- forty display IDs put them all on one line, which made the tooltip wider than the
-- screen and still clipped the end. Breaking the list into bounded lines lets it grow
-- downward instead, which is the direction a tooltip has room in.
--
-- Bounded by character count rather than pixels on purpose: a font string's width is
-- only measurable once it is realised, and these are digits and commas, where the two
-- measures track closely enough that a pixel-exact answer would buy nothing.
local ID_LIST_MAX_CHARS = 56

-- Joins `parts` into lines no longer than maxChars. `prefix` starts the first line and
-- shares its budget, so a short list still fits on one line with its label.
local function WrapJoin(prefix, parts, separator, maxChars)
    local lines   = {}
    local current = prefix or ""

    for i, part in ipairs(parts) do
        local piece = part .. (i < #parts and separator or "")
        if current ~= "" and #current + #piece > maxChars then
            lines[#lines + 1] = current
            current = piece
        else
            current = current .. piece
        end
    end

    if current ~= "" then lines[#lines + 1] = current end
    return lines
end

function PSM.NPCRow:GetOrCreateIdLink(row, index)
    if row.idLinks[index] then return row.idLinks[index] end

    local Widgets = PSM.Widgets

    local link = Widgets.Frame(row.idContainer, {
        frameType = "Button",
        height    = ID_LINE_HEIGHT,
    })
    local fs = Widgets.Label(link, {
        fontSize = CELL_FONT_SIZE,
        color    = ID_LINK_COLOR,
        justify  = "LEFT",
        point    = { "LEFT", 0, 0 },
    })
    link.text = fs
    link.baseColor, link.hoverColor = ID_LINK_COLOR, ID_LINK_HOVER

    link:SetScript("OnEnter", function(self) fs:SetTextColor(unpack(self.hoverColor)) end)
    link:SetScript("OnLeave", function(self) fs:SetTextColor(unpack(self.baseColor)) end)
    link:SetScript("OnClick", function()
        if link.displayId then PSM.PopUpManager:ShowMagnificationPopup(link.displayId) end
    end)

    row.idLinks[index] = link
    return link
end

function PSM.NPCRow:CreateNPCRow(parent)
    local Widgets = PSM.Widgets

    local row = Widgets.Frame(parent, {
        height = ROW_HEIGHT,
        point  = {
            { "LEFT",  parent, "LEFT",  0, 0 },
            { "RIGHT", parent, "RIGHT", 0, 0 },
        },
    })
    -- Clip anything (long text, many display-id links) that would otherwise
    -- bleed past the row/panel edge instead of wrapping it to a second line.
    row:SetClipsChildren(true)

    row.bg = Widgets.Texture(row, {
        layer     = "BACKGROUND",
        allPoints = true,
        color     = { 1, 1, 1, 0 },  -- alpha set per row in UpdateItemRow for striping
    })

    -- A full-height, column-wide button behind a cell, so the whole cell is the
    -- click target rather than just its glyphs.
    local function CellButton()
        return Widgets.Frame(row, { frameType = "Button", height = ROW_HEIGHT })
    end

    row.cellTexts = {}
    row.clickableCells = {}
    for _, col in ipairs(self.COLUMNS) do
        if col.key == "note" then
            local btn = CellButton()
            btn.icon = Widgets.Texture(btn, {
                layer = "OVERLAY",
                size  = { 14, 14 },
                point = { "LEFT", btn, "LEFT", 2, 0 },
            })
            row.clickableCells.note = btn
        elseif col.key ~= "displayIds" then
            local fsParent = row
            if CLICKABLE_CELL_COLUMNS[col.key] then
                local btn = CellButton()
                row.clickableCells[col.key] = btn
                fsParent = btn
            end
            row.cellTexts[col.key] = Widgets.Label(fsParent, {
                fontSize = CELL_FONT_SIZE,
                justify  = "LEFT",
                wordWrap = false,
            })
        end
    end

    row.idContainer = Widgets.Frame(row, { height = ID_LINE_HEIGHT * 2 })
    row.idLinks = {}

    row.idMoreText = Widgets.Label(row, {
        fontSize = CELL_FONT_SIZE,
        color    = { 0.55, 0.55, 0.5 },
        justify  = "LEFT",
        hidden   = true,
    })

    row:Hide()
    return row
end

function PSM.NPCRow:UpdateItemRow(row, item, index)
    if not item then row.currentItem = nil; row:Hide(); return end

    local panel = PSM.state.modelsPanel
    row.npcId = item.npcId
    row.currentItem = item
    row.lastIndex = index
    row.bg:SetColorTexture(1, 1, 1, (index % 2 == 0) and 0.025 or 0)

    local layout = (panel and panel.npcColumnLayout) or self:RecomputeColumnLayout(panel)

    for _, fs in pairs(row.cellTexts) do fs:Hide() end
    for _, link in pairs(row.idLinks) do link:Hide() end
    for _, btn in pairs(row.clickableCells) do btn:Hide() end
    row.idMoreText:Hide()

    for _, colLayout in ipairs(layout) do
        local key = colLayout.key
        if key == "note" then
            local btn = row.clickableCells.note
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", row, "TOPLEFT", colLayout.x, 0)
            btn:SetSize(colLayout.width, ROW_HEIGHT)

            local npcId = item.npcId
            local userNote = PSM_UserNotes and PSM_UserNotes[npcId]
            local hasUser = userNote and userNote ~= ""
            local seedNote = PSM.NotesData and PSM.NotesData[npcId]
            btn.icon:SetTexture((hasUser or seedNote)
                and "Interface\\Buttons\\ui-guildbutton-officernote-up"
                or  "Interface\\Buttons\\ui-guildbutton-officernote-disabled")

            btn:SetScript("OnClick", function()
                PSM.PopUpManager:ShowNoteEditor(npcId, item.name, nil, function()
                    PSM.ModelsPanel:UpdateVisibleRows()
                end)
            end)
            local noteText = hasUser and userNote or seedNote
            PSM.Tooltip.Attach(btn, {
                title = noteText and (hasUser and PSM.L("Your note:") or PSM.L("Info note:"))
                                  or PSM.L("Click to add a note"),
                lines = noteText
                    and { { text = noteText, color = PSM.Theme.COLOR.WHITE, wrap = true } }
                    or nil,
            })
            btn:Show()
        elseif key == "displayIds" then
            row.idContainer:ClearAllPoints()
            row.idContainer:SetSize(colLayout.width, ID_LINE_HEIGHT * 2)

            local ids = item.displayIds or {}
            local ownedSet = panel and panel.ownedDisplayIdSet

            -- Pass 1: decide placement (which line, x offset) without moving
            -- anything yet, so the actual number of lines used is known
            -- before we vertically center the block within the row.
            local placements = {}
            local xOff, lineNum, shown = 0, 0, 0
            for i, dispId in ipairs(ids) do
                local link = self:GetOrCreateIdLink(row, i)
                local suffix = ids[i + 1] and ", " or ""
                link.text:SetText(tostring(dispId) .. suffix)
                local linkWidth = link.text:GetStringWidth() + 2

                if xOff > 0 and xOff + linkWidth > colLayout.width then
                    if lineNum == 0 then
                        -- Overflow to a second line before falling back to "+N".
                        lineNum = 1
                        xOff = 0
                    else
                        break
                    end
                end

                table.insert(placements, { link = link, dispId = dispId, x = xOff, line = lineNum, width = linkWidth })
                xOff = xOff + linkWidth
                shown = shown + 1
            end

            local linesUsed = lineNum + 1
            local blockHeight = linesUsed * ID_LINE_HEIGHT
            local topOffset = -(ROW_HEIGHT - blockHeight) / 2
            row.idContainer:SetPoint("TOPLEFT", row, "TOPLEFT", colLayout.x, topOffset)

            -- Pass 2: apply the now-known, vertically-centered positions.
            for _, p in ipairs(placements) do
                local link = p.link
                link:ClearAllPoints()
                link:SetPoint("TOPLEFT", row.idContainer, "TOPLEFT", p.x, -(p.line * ID_LINE_HEIGHT))
                link:SetWidth(p.width)
                link.displayId = p.dispId
                if ownedSet and ownedSet[p.dispId] then
                    link.baseColor, link.hoverColor = ID_LINK_OWNED_COLOR, ID_LINK_OWNED_HOVER
                else
                    link.baseColor, link.hoverColor = ID_LINK_COLOR, ID_LINK_HOVER
                end
                link.text:SetTextColor(unpack(link.baseColor))
                link:Show()
            end

            if shown < #ids then
                row.idMoreText:ClearAllPoints()
                row.idMoreText:SetPoint("TOPLEFT", row.idContainer, "TOPLEFT", xOff, -(lineNum * ID_LINE_HEIGHT))
                row.idMoreText:SetText(string.format("+%d", #ids - shown))
                row.idMoreText:Show()
            end
        else
            local fs = row.cellTexts[key]
            if fs then
                fs:ClearAllPoints()
                fs:SetPoint("TOPLEFT", row, "TOPLEFT", colLayout.x, -(ROW_HEIGHT / 2 - 5))
                fs:SetWidth(colLayout.width)
                fs:SetTextColor(unpack(CELL_NEUTRAL_COLOR))

                local clickBtn = row.clickableCells[key]
                if clickBtn then
                    clickBtn:ClearAllPoints()
                    clickBtn:SetPoint("TOPLEFT", row, "TOPLEFT", colLayout.x, 0)
                    clickBtn:SetSize(colLayout.width, ROW_HEIGHT)
                    clickBtn:Show()
                end

                if key == "npcId" then
                    fs:SetText("#" .. tostring(item.npcId))
                    fs:SetTextColor(unpack(PSM.Theme.COLOR.SLATE))
                elseif key == "name" then
                    fs:SetText(item.name)
                    -- Always a valid link: an npcId is always available to build the Wowhead URL from.
                    fs:SetTextColor(unpack(ID_LINK_COLOR))
                    clickBtn:SetScript("OnEnter", function() fs:SetTextColor(unpack(ID_LINK_HOVER)) end)
                    clickBtn:SetScript("OnLeave", function() fs:SetTextColor(unpack(ID_LINK_COLOR)) end)
                    clickBtn:SetScript("OnClick", function()
                        if item.npcId then
                            PSM.PopUpManager:ShowURLPopup("https://www.wowhead.com/npc=" .. tostring(item.npcId))
                        end
                    end)
                elseif key == "family" then
                    fs:SetText(item.family or "")
                elseif key == "classification" then
                    fs:SetText(item.classification ~= "Normal" and item.classification or "")
                    local c = CLASS_COLOR[item.classification]
                    if c then fs:SetTextColor(c[1], c[2], c[3]) end
                elseif key == "nameKeeper" then
                    fs:SetText(item.nameKeeper and "Yes" or "")
                    fs:SetTextColor(unpack(PSM.Theme.COLOR.GOLD))
                elseif key == "zone" then
                    fs:SetText(item.uiMapName or "")
                    -- Only some NPCs have stored TomTom coordinate data; only
                    -- style/wire this as a link when a click would actually do something.
                    local waypoints = (item.npcId and item.uiMapId)
                        and PSM.PopUpManager:GetCoordsWaypointText(item.npcId, item.uiMapId, item.name)
                        or nil
                    if waypoints then
                        fs:SetTextColor(unpack(ID_LINK_COLOR))
                        clickBtn:SetScript("OnEnter", function() fs:SetTextColor(unpack(ID_LINK_HOVER)) end)
                        clickBtn:SetScript("OnLeave", function() fs:SetTextColor(unpack(ID_LINK_COLOR)) end)
                        clickBtn:SetScript("OnClick", function()
                            PSM.PopUpManager:ShowCoordsPopup(waypoints, item.name, item.uiMapName or tostring(item.uiMapId), item.displayIds and item.displayIds[1])
                        end)
                    else
                        fs:SetTextColor(unpack(CELL_NEUTRAL_COLOR))
                        clickBtn:SetScript("OnEnter", nil)
                        clickBtn:SetScript("OnLeave", nil)
                        clickBtn:SetScript("OnClick", nil)
                    end
                elseif key == "continent" then
                    local cont = panel and panel.locationContinents and panel.locationContinents[item.uiMapName]
                    fs:SetText(cont or "")
                elseif key == "expansion" then
                    fs:SetText(item.expansion or "")
                elseif key == "faction" then
                    fs:SetText(FormatFaction(item.reactA, item.reactH))
                end
                fs:Show()
            end
        end
    end

    -- Resolved per hover rather than per render: ownedDisplayIdSet is rebuilt once
    -- per render pass, and a row outlives several of those.
    PSM.Tooltip.Attach(row, function()
        local lines = {
            { text = PSM.L("NPC ID: %s", tostring(item.npcId)), color = PSM.Theme.COLOR.DIM },
            { text = PSM.L("%s - %s, %s",
                item.family or PSM.L("Unknown"), item.uiMapName or PSM.L("Unknown"),
                item.expansion or PSM.L("Unknown")), color = PSM.Theme.COLOR.DIM },
        }

        if item.displayIds and #item.displayIds > 0 then
            local ownedSet = PSM.state.modelsPanel and PSM.state.modelsPanel.ownedDisplayIdSet
            local parts = {}
            for _, id in ipairs(item.displayIds) do
                table.insert(parts, tostring(id) .. ((ownedSet and ownedSet[id]) and PSM.L(" (owned)") or ""))
            end
            for _, text in ipairs(WrapJoin(PSM.L("Display IDs: "), parts, ", ", ID_LIST_MAX_CHARS)) do
                lines[#lines + 1] = { text = text, color = ID_LINK_HOVER }
            end
        end

        return { title = item.name, lines = lines }
    end)

    row:Show()
end

-- Re-applies the current column layout to already-visible rows without
-- re-sorting or re-paginating -- used while a column resize is in progress.
function PSM.NPCRow:ReflowVisibleRows(panel)
    if not panel or not panel.npcRows then return end
    self:UpdateHeaderRow(panel)
    for _, row in ipairs(panel.npcRows) do
        if row:IsShown() and row.currentItem then
            self:UpdateItemRow(row, row.currentItem, row.lastIndex or 1)
        end
    end
end
