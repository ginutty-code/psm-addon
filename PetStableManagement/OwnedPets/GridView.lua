-- OwnedPets/GridView.lua
-- Alternative grid view for Owned Pets panel (3D models with tooltip on mouseover)

local addonName = "PetStableManagement"

_G.PSM = _G.PSM or {}
local PSM = _G.PSM

PSM.UI.GridView = {}
local GV = PSM.UI.GridView  -- local alias to avoid repeated global lookups

-- Constants (reference Config for consistency)
GV.GRID_VIEW_ROW_HEIGHT = PSM.Config.GRID_ROW_HEIGHT
GV.GRID_VIEW_MODEL_SIZE = PSM.Config.GRID_MODEL_SIZE

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
-- Row creation
------------------------------------------------------------------------

function GV:CreateModelRow(parent)
    local row = PSM.RowManager:CreateBaseRow(parent, {
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

    -- Shared show/hide logic for overlay buttons
    local function ShowButtons(model)
        HideIfExists(model.resetButton)  -- intentional: show via :Show() below
        if model.resetButton  then model.resetButton:Show()  end
        if model.magnifyButton then model.magnifyButton:Show() end
        if model.isOwnedByPlayer then
            if model.addToTeamButton    then model.addToTeamButton:Show()    end
            if model.removeFromTeamButton then model.removeFromTeamButton:Show() end
        end
    end

    local function HideButtons(model)
        local btns = { model.resetButton, model.magnifyButton,
                       model.addToTeamButton, model.removeFromTeamButton }
        for _, btn in ipairs(btns) do
            if btn and not btn:IsMouseOver() then btn:Hide() end
        end
    end

    m:SetScript("OnEnter", function(self)
        ShowButtons(self)
        if row.petData then GV:ShowPetTooltip(row, row.petData) end
    end)

    m:SetScript("OnLeave", function(self)
        HideButtons(self)
        GameTooltip:Hide()
    end)

    row:SetScript("OnEnter", function(self)
        if row.petData then GV:ShowPetTooltip(row, row.petData) end
    end)

    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return row
end

------------------------------------------------------------------------
-- Tooltip
------------------------------------------------------------------------

local ABILITY_TAGS = {
    spec    = "|cFFFFD700[Spec]|r ",
    family  = "|cFF40FF40[Family]|r ",
    pet     = "|cFF40FFFF[Pet]|r ",
    unknown = "|cFFAAAAAA[Other]|r ",
}
local ABILITY_COLORS = {
    spec    = { 1,   1,   1   },
    family  = { 0.8, 1,   0.8 },
    pet     = { 0.8, 1,   1   },
    unknown = { 0.7, 0.7, 0.7 },
}

function GV:ShowPetTooltip(row, pet)
    if not pet then return end

    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")

    local exotic = pet.isExotic and " |cffff8800[Exotic]|r" or ""
    GameTooltip:SetText(("Slot %d: %s%s"):format(pet.slotID or 0, pet.name or "?", exotic), 1, 1, 1)
    GameTooltip:AddLine(("DisplayID: %d"):format(pet.displayID or 0), 0.8, 0.8, 0.8)

    if pet.familyName then GameTooltip:AddLine("Family: " .. pet.familyName, 1, 1, 1) end
    if pet.specName   then GameTooltip:AddLine("Spec: "   .. pet.specName,   0.8, 0.8, 0.8) end
    if pet.tamer      then GameTooltip:AddLine("Owned by: " .. pet.tamer,    0.7, 0.7, 0.7) end

    if pet.level and pet.level > 0 then
        local lvlColor = pet.level >= 25 and "|cFF00FF00" or (pet.level >= 1 and "|cFFFFFF00" or "|cFF888888")
        GameTooltip:AddLine(("Level: %d%s"):format(pet.level, lvlColor), 1, 1, 1)
    end

    -- Abilities
    local abilities   = type(pet.abilities) == "table" and pet.abilities or {}
    local hasAbilities = false
    local isGrouped   = abilities.family or abilities.spec or abilities.pet or abilities.unknown

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cFFFFD700Abilities:|r", 1, 1, 1)

    if isGrouped then
        for _, key in ipairs({ "spec", "family", "pet", "unknown" }) do
            local group = abilities[key]
            if group and #group > 0 then
                local c = ABILITY_COLORS[key]
                for _, ability in ipairs(group) do
                    GameTooltip:AddLine("  " .. ABILITY_TAGS[key] .. ability, c[1], c[2], c[3])
                end
                hasAbilities = true
            end
        end
    else
        for _, ability in ipairs(abilities) do
            local name = type(ability) == "table" and ability.name or tostring(ability)
            GameTooltip:AddLine("  • " .. name, 1, 1, 1)
            hasAbilities = true
        end
    end

    if not hasAbilities then
        GameTooltip:AddLine("|cFFAAAAAA(No abilities available)", 0.7, 0.7, 0.7)
    end

    -- Interaction hints
    local hint = "Left-click and drag to rotate\nRight-click and drag to move (left/right, up/down)\nScroll to zoom"
    if PSM.state and PSM.state.isStableOpen and pet.slotID then
        hint = hint .. "\nShift/Ctrl + drag to reorder slot"
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(hint, 0.7, 0.7, 0.7)

    GameTooltip:Show()
end

------------------------------------------------------------------------
-- Row update / hide
------------------------------------------------------------------------

function GV:UpdateRow(row, pet)
    if not row or not pet then return end

    row.petData = pet

    if row.model and pet.displayID then
        PSM.RowManager:UpdateModelDisplay(row, pet.displayID, pet.icon, pet)
    end

    local isSame, isCross = PSM.RowManager:CheckDuplicates(pet, PSM.state.allGroups)
    local specName = pet.specName
    if not specName and pet.specID then
        local specInfo = C_SpecializationInfo.GetPetSpecialization(pet.specID)
        specName = specInfo and specInfo.name
    end
    
    PSM.RowManager:UpdateBackgroundColor(row, isSame, isCross, false, pet.specName)
        
    -- Hide unused OwnedPets elements
    local unused = {
        row.abilitiesHeader, row.abilitiesList, row.makeActive,
        row.companion, row.stable, row.release, row.moveUp, row.moveDown,
    }
    for _, el in ipairs(unused) do HideIfExists(el) end

    PSM.RowManager:HideFavoriteButton(row)

    if PSM.DragDrop then
        PSM.DragDrop:SetupRowDragDrop(row, pet)
        PSM.DragDrop:SetupModelDragDrop(row.model, pet, row)
    end

    row:Show()
end

function GV:HideRow(i)
    local row = PSM.state.modelViewRows and PSM.state.modelViewRows[i]
    if not row then return end
    PSM.RowManager:HideRow(row)
    row.petData = nil
end

------------------------------------------------------------------------
-- Visible rows update
------------------------------------------------------------------------

function GV:UpdateVisibleRows()
    local renderData = PSM.state.currentRenderData
    if not renderData or not PSM.state.panel then return end

    local content = PSM.state.content
    if not content then return end

    -- Lazily populate row pool
    local pool = PSM.state.modelViewRows
    if not pool then
        pool = {}
        PSM.state.modelViewRows = pool
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
    local pad        = PSM.Config.COLUMN_SPACING
    local colWidth   = modelSize + 2 * pad
    local colCount   = math.max(1, math.floor(contentWidth / colWidth))
    local margin     = (contentWidth - colCount * colWidth) / 2
    local rowTotal   = math.ceil(totalItems / colCount)
    local rowHeight  = PSM.Config.GRID_ROW_HEIGHT

    -- Set content height and update scrollbar range
    content:SetHeight(math.max(rowTotal * rowHeight + rowHeight * 0.5, 100))
    if PSM.state.scrollFrame.UpdateScrollChildRect then
        PSM.state.scrollFrame:UpdateScrollChildRect()
    end

    local scrollFrameHeight = PSM.state.scrollFrame:GetHeight() or 500
    local visibleRowCount   = math.ceil(scrollFrameHeight / rowHeight) + 3

    -- Grow pool if needed
    if visibleRowCount > #pool then
        for i = #pool + 1, visibleRowCount do
            local r = GV:CreateModelRow(content)
            r:Hide()
            pool[i] = r
        end
    end

    local startRow   = math.max(1, PSM.state.panel.gridScrollOffset + 1)
    local endRow     = math.min(rowTotal, startRow + visibleRowCount - 1)
    local startIndex = (startRow - 1) * colCount + 1
    local endIndex   = math.min(totalItems, endRow * colCount)

    for _, r in ipairs(pool) do r:Hide() end

    local rowIndex = 1
    PSM.state.allGroups = renderData.allGroups  -- set once, not per-pet

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
    PSM._renderCache = nil
    PSM.C_Timer.After(0.01, function()
        if PSM.UI and PSM.UI.RenderPanel then PSM.UI:RenderPanel() end
    end)
end

function GV:Enable()
    PSM.state.panelViewMode = "grid"

    local panel = PSM.state.panel
    panel.gridScrollOffset = 0
    if panel.scrollFrame then panel.scrollFrame:SetVerticalScroll(0) end

    if PSM.state.rows then
        for _, r in ipairs(PSM.state.rows) do HideIfExists(r) end
    end

    HideGroupedView(panel)
    ScheduleRerender()
end

function GV:Disable()
    PSM.state.panelViewMode = "list"

    local panel = PSM.state.panel
    panel.scrollOffset = 0
    if panel.scrollFrame then panel.scrollFrame:SetVerticalScroll(0) end

    if PSM.state.modelViewRows then
        for _, row in ipairs(PSM.state.modelViewRows) do
            if row then
                row:Hide()
                row.petData = nil
                local m = row.model
                if m then
                    m:Hide()
                    m:ClearModel()
                    m.isRotating = false
                    if PSM.RotationFrame and PSM.RotationFrame.activeModels then
                        PSM.RotationFrame.activeModels[m] = nil
                    end
                end
            end
        end
    end

    HideGroupedView(panel)
    ScheduleRerender()
end

function GV:Toggle()
    if PSM.state.panelViewMode == "grid" then self:Disable() else self:Enable() end
end

function GV:IsEnabled()
    return PSM.state.panelViewMode == "grid"
end