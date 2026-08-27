-- OwnedPets/GridView.lua
-- Alternative grid view for Owned Pets panel (3D models with tooltip on mouseover)

local _, ns = ...

ns.UI.GridView = {}
local GV = ns.UI.GridView  -- local alias to avoid repeated global lookups

-- Constants (reference Config for consistency)
GV.GRID_VIEW_ROW_HEIGHT = ns.Config.GRID_ROW_HEIGHT
GV.GRID_VIEW_MODEL_SIZE = ns.Config.GRID_MODEL_SIZE

-- Button layout constants
local BTN_OFFSET_X  = 0
local BTN_OFFSET_Y  = -15
local BTN_SPACING   = 20
local ROWS_PER_PAGE = 50

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local function HideIfExists(frame)
    if frame then frame:Hide() end
end

-- Anchor a button relative to the model frame
local function AnchorButton(btn, model, corner, xOff, yOff)
    if not btn then return end
    btn:ClearAllPoints()
    btn:SetPoint(corner, model, corner, xOff, yOff)
end

------------------------------------------------------------------------
-- Tooltip
------------------------------------------------------------------------

-- Grid view has no reordering of its own to explain, so its hints are the model
-- interaction plus the stable-slot case RowManager already words.
local function GridHints(pet)
    local hints = ns.RowManager.MODEL_HINTS
    if ns.state and ns.state.isStableOpen and pet.slotID then
        hints = hints .. "\n" .. ns.L("Shift/Ctrl + drag to reorder slot")
    end
    return hints
end

function GV:PetTooltipSpec(pet)
    if not pet then return nil end
    return ns.PetTooltip.Spec(pet, { hints = GridHints(pet) })
end

------------------------------------------------------------------------
-- Row creation
------------------------------------------------------------------------

function GV:CreateModelRow(parent)
    local row = ns.RowManager:CreateBaseRow(parent, {
        useBackdropTemplate = true,
        height      = GV.GRID_VIEW_ROW_HEIGHT,
        modelSize   = GV.GRID_VIEW_MODEL_SIZE,
        showMagnifyButton = true,
        showTeamButtons   = true,
    })

    HideIfExists(row.text)

    -- Reposition overlay buttons
    local m = row.model
    AnchorButton(m.resetButton,        m, "TOPRIGHT",    BTN_OFFSET_X,               BTN_OFFSET_Y)
    AnchorButton(m.magnifyButton,      m, "TOPRIGHT",    BTN_OFFSET_X - BTN_SPACING, BTN_OFFSET_Y)
    AnchorButton(m.addToTeamButton,    m, "BOTTOMRIGHT", BTN_OFFSET_X,              -BTN_OFFSET_Y)
    AnchorButton(m.removeFromTeamButton, m, "BOTTOMRIGHT", BTN_OFFSET_X - BTN_SPACING, -BTN_OFFSET_Y)

    m:ClearAllPoints()
    m:SetPoint("CENTER", row, "CENTER")

    row.viewType = "grid"
    row.petData  = nil

    -- The model and the row show the same tooltip, each anchored to itself, so it
    -- lands beside whichever the mouse actually entered. Attaching to the model
    -- deliberately replaces RowManager's rotate/zoom tooltip -- those hints are
    -- already this tooltip's last section -- and that is why the hover buttons have
    -- to come along: re-attaching OnEnter/OnLeave drops RowManager's pair with it.
    local function TooltipForRow() return GV:PetTooltipSpec(row.petData) end

    ns.Tooltip.Attach(m, TooltipForRow, {
        onEnter = function(self) ns.RowManager:ShowHoverButtons(self) end,
        onLeave = function(self) ns.RowManager:HideHoverButtons(self) end,
    })
    ns.Tooltip.Attach(row, TooltipForRow)

    return row
end

------------------------------------------------------------------------
-- Row update / hide
------------------------------------------------------------------------

function GV:UpdateRow(row, pet)
    if not row or not pet then return end

    row.petData = pet

    if row.model and pet.displayID then
        ns.RowManager:UpdateModelDisplay(row, pet.displayID, pet.icon, pet)
    end

    local isSame, isCross = ns.RowManager:CheckDuplicates(pet, ns.state.allGroups)
    ns.RowManager:UpdateBackgroundColor(row, isSame, isCross, false, pet.specName)
        
    -- Hide unused OwnedPets elements
    local unused = {
        row.abilitiesHeader, row.abilitiesList, row.makeActive,
        row.companion, row.stable, row.release, row.moveUp, row.moveDown,
    }
    for _, el in ipairs(unused) do HideIfExists(el) end

    ns.RowManager:UpdateFavoriteButton(row, pet.displayID)

    if ns.DragDrop then
        ns.DragDrop:SetupRowDragDrop(row, pet)
        ns.DragDrop:SetupModelDragDrop(row.model, pet, row)
    end

    row:Show()
end

------------------------------------------------------------------------
-- Visible rows update
------------------------------------------------------------------------

function GV:UpdateVisibleRows()
    local renderData = ns.state.currentRenderData
    if not renderData or not ns.state.panel then return end

    local content = ns.state.content
    if not content then return end

    -- Lazily populate row pool
    local pool = ns.state.modelViewRows
    if not pool then
        pool = {}
        ns.state.modelViewRows = pool
        for i = 1, ROWS_PER_PAGE do
            local r = GV:CreateModelRow(content)
            r:Hide()
            pool[i] = r
        end
    end

    local totalItems = renderData.filteredCount
    if totalItems == 0 then
        for _, r in ipairs(pool) do r:Hide() end
        return
    end

    local contentWidth = content:GetWidth()
    if not contentWidth or contentWidth <= 0 then contentWidth = 500 end

    local modelSize  = GV.GRID_VIEW_MODEL_SIZE
    local pad        = ns.Config.COLUMN_SPACING
    local colWidth   = modelSize + 2 * pad
    local colCount   = math.max(1, math.floor(contentWidth / colWidth))
    local margin     = (contentWidth - colCount * colWidth) / 2
    local rowTotal   = math.ceil(totalItems / colCount)
    local rowHeight  = ns.Config.GRID_ROW_HEIGHT

    -- Set content height and update scrollbar range
    content:SetHeight(math.max(rowTotal * rowHeight + rowHeight * 0.5, 100))
    if ns.state.scrollFrame.UpdateScrollChildRect then
        ns.state.scrollFrame:UpdateScrollChildRect()
    end
    -- Before deriving the row offset below, not after: the offset must come from a
    -- scroll position that is actually in range.
    ns.UI:ClampScrollIntoRange(ns.state.scrollFrame, content)

    local scrollFrameHeight = ns.state.scrollFrame:GetHeight() or 500
    local visibleRowCount   = math.ceil(scrollFrameHeight / rowHeight) + 3

    -- Grow pool if needed
    if visibleRowCount > #pool then
        for i = #pool + 1, visibleRowCount do
            local r = GV:CreateModelRow(content)
            r:Hide()
            pool[i] = r
        end
    end

    -- Grid columns are one model wide, so the column count changes every ~120px of
    -- panel width — this view crosses the blind spot far more often than list view
    -- does. See PSM.UI:GetScrollRowOffset.
    ns.state.panel.gridScrollOffset = ns.UI:GetScrollRowOffset(rowHeight, rowTotal)

    local startRow   = math.max(1, ns.state.panel.gridScrollOffset + 1)
    local endRow     = math.min(rowTotal, startRow + visibleRowCount - 1)
    local startIndex = (startRow - 1) * colCount + 1
    local endIndex   = math.min(totalItems, endRow * colCount)

    for _, r in ipairs(pool) do r:Hide() end

    local rowIndex = 1
    ns.state.allGroups = renderData.allGroups  -- set once, not per-pet

    for dataIndex = startIndex, endIndex do
        if rowIndex > #pool then break end

        local pet = renderData.filteredPets[dataIndex]
        local row = pool[rowIndex]

        if pet and row then
            local col    = (dataIndex - 1) % colCount
            local rowIdx = math.floor((dataIndex - 1) / colCount) + 1

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT",
                margin + col * colWidth,
                -(rowIdx - 1) * rowHeight)
            row:SetWidth(colWidth)
            row:SetHeight(rowHeight)

            GV:UpdateRow(row, pet)
            row:Show()
            rowIndex = rowIndex + 1
        end
    end
end

------------------------------------------------------------------------
-- View switching
------------------------------------------------------------------------

local function HideGroupedView(panel)
    if panel.groupedViewSections then
        for _, sec in ipairs(panel.groupedViewSections) do HideIfExists(sec) end
    end
    HideIfExists(panel.groupedViewEmptyText)
end

local function ScheduleRerender()
    ns.C_Timer.After(0.01, function()
        if ns.UI and ns.UI.RenderPanel then ns.UI:RenderPanel() end
    end)
end

function GV:Enable()
    ns.state.panelViewMode = "grid"

    local panel = ns.state.panel
    panel.gridScrollOffset = 0
    if panel.scrollFrame then panel.scrollFrame:SetVerticalScroll(0) end

    if ns.state.rows then
        for _, r in ipairs(ns.state.rows) do HideIfExists(r) end
    end

    HideGroupedView(panel)
    ScheduleRerender()
end

function GV:Disable()
    ns.state.panelViewMode = "list"

    local panel = ns.state.panel
    panel.scrollOffset = 0
    if panel.scrollFrame then panel.scrollFrame:SetVerticalScroll(0) end

    if ns.state.modelViewRows then
        for _, row in ipairs(ns.state.modelViewRows) do
            if row then
                row:Hide()
                row.petData = nil
                local m = row.model
                if m then
                    m:Hide()
                    m:ClearModel()
                    m.isRotating = false
                    ns.RowManager:ReleaseModel(m)
                end
            end
        end
    end

    HideGroupedView(panel)
    ScheduleRerender()
end
