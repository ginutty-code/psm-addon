-- OwnedPets/GroupedView.lua
-- Grouped view for Owned Pets panel - lightweight, GridView-based grouping

local _, ns = ...

ns.UI.GroupedView = {}

ns.UI.GroupedView.GRID_VIEW_ROW_HEIGHT = ns.Config.GRID_ROW_HEIGHT
ns.UI.GroupedView.GRID_VIEW_MODEL_SIZE = ns.Config.GRID_MODEL_SIZE

local HEADER_HEIGHT  = 30
local HEADER_SPACING = 8

local groupedLayout = { sections = {}, contentHeight = 0 }

--------------------------------------------------------------------------------
-- COLLAPSED STATE
--------------------------------------------------------------------------------

local function GetCollapsedState()
    if not PetStableManagementDB then PetStableManagementDB = {} end
    if not PetStableManagementDB.collapsedGroups then PetStableManagementDB.collapsedGroups = {} end
    return PetStableManagementDB.collapsedGroups
end

local function IsGroupCollapsed(groupId)
    return groupId and GetCollapsedState()[groupId] == true
end

local function SetGroupCollapsed(groupId, collapsed)
    if groupId then GetCollapsedState()[groupId] = collapsed or nil end
end

local function ToggleGroupCollapsed(groupId)
    if not groupId then return end
    local next = not IsGroupCollapsed(groupId)
    SetGroupCollapsed(groupId, next)
    return next
end

-- Collapse/expand every group at once
local function SetAllGroupsCollapsed(collapsed)
    for _, group in ipairs(ns.PetGroups:GetGroups()) do
        SetGroupCollapsed(group.id, collapsed)
    end
    if ns.UI and ns.UI.RenderPanel then ns.UI:RenderPanel(true) end
end

--------------------------------------------------------------------------------
-- SHARED UI REFRESH
--------------------------------------------------------------------------------

local function RefreshUI()
    if ns.UI and ns.UI.RenderPanel then ns.UI:RenderPanel(true) end
end

--------------------------------------------------------------------------------
-- PET TOOLTIP
--------------------------------------------------------------------------------

-- Grouped view is the only place a pet can be reordered or moved between groups, so
-- it has the most to explain -- and the explanation depends on the active sort, which
-- disables reordering entirely.
local function GroupedHints(pet)
    local hints = ns.RowManager.MODEL_HINTS
    if ns.state.sortBy then
        hints = hints .. "\n" .. ns.L("Reordering disabled while sorting is active.")
            .. "\n" .. ns.L("Set Sort by to Unsorted to re-enable.")
    else
        hints = hints .. "\n" .. ns.L("Shift/Ctrl + drag to reorder within group (works outside stable)")
    end
    hints = hints .. "\n" .. ns.L("Shift/Ctrl + Right-click to move to a specific group")
    if ns.state and ns.state.isStableOpen and pet.slotID then
        hints = hints .. "\n" .. ns.L("Shift/Ctrl + drag to swap stable slots")
    end
    return hints
end

local function PetTooltipSpec(pet)
    if not pet then return nil end
    return ns.PetTooltip.Spec(pet, { hints = GroupedHints(pet) })
end

function ns.UI.GroupedView:ShowPetTooltip(row, pet)
    ns.Tooltip.Show(row, PetTooltipSpec(pet))
end

--------------------------------------------------------------------------------
-- ROW CREATION / UPDATE
--------------------------------------------------------------------------------

function ns.UI.GroupedView:CreateModelRow(parent)
    local row = ns.RowManager:CreateBaseRow(parent, {
        useBackdropTemplate = true,
        height              = self.GRID_VIEW_ROW_HEIGHT,
        modelSize           = self.GRID_VIEW_MODEL_SIZE,
        showMagnifyButton   = true,
        showTeamButtons     = true,
    })

    if row.text then row.text:Hide() end

    local offX, offY, spacing = 0, -15, 20
    if row.model.resetButton      then row.model.resetButton:SetPoint("TOPRIGHT",    row.model, "TOPRIGHT",    offX,          offY)  end
    if row.model.magnifyButton    then row.model.magnifyButton:SetPoint("TOPRIGHT",  row.model, "TOPRIGHT",    offX-spacing,  offY)  end
    if row.model.addToTeamButton  then row.model.addToTeamButton:SetPoint("BOTTOMRIGHT", row.model, "BOTTOMRIGHT", offX,     -offY) end
    if row.model.removeFromTeamButton then row.model.removeFromTeamButton:SetPoint("BOTTOMRIGHT", row.model, "BOTTOMRIGHT", offX-spacing, -offY) end

    row.model:ClearAllPoints()
    row.model:SetPoint("CENTER", row, "CENTER", 0, 0)
    row.viewType = "grouped"
    row.petData  = nil

    -- The model and the row show the same tooltip, each anchored to itself, so it
    -- lands beside whichever the mouse actually entered. Attaching to the model
    -- deliberately replaces RowManager's rotate/zoom tooltip -- those hints are
    -- already this tooltip's last section -- and that is why the hover buttons have
    -- to come along: re-attaching OnEnter/OnLeave drops RowManager's pair with it.
    local function TooltipForRow() return PetTooltipSpec(row.petData) end

    ns.Tooltip.Attach(row.model, TooltipForRow, {
        onEnter = function(self) ns.RowManager:ShowHoverButtons(self) end,
        onLeave = function(self) ns.RowManager:HideHoverButtons(self) end,
    })
    ns.Tooltip.Attach(row, TooltipForRow)

    return row
end

function ns.UI.GroupedView:UpdateRow(row, pet)
    if not row or not pet then return end
    row.petData = pet
    if row.model and pet.displayID then
        ns.RowManager:UpdateModelDisplay(row, pet.displayID, pet.icon, pet)
    end
    local isSame, isCross = ns.RowManager:CheckDuplicates(pet, ns.state.allGroups)
    ns.RowManager:UpdateBackgroundColor(row, isSame, isCross, false, pet.specName)
    ns.RowManager:HideFavoriteButton(row)
    if ns.DragDrop then
        ns.DragDrop:SetupRowDragDrop(row, pet, true)
        ns.DragDrop:SetupModelDragDrop(row.model, pet, row, true)
    end

    row.contextMenuPet       = pet
    row.model.contextMenuPet = pet

    local origOnMouseDown = row.model:GetScript("OnMouseDown")
    row.model:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" and (IsShiftKeyDown() or IsControlKeyDown()) then
            ns.UI.GroupedView:ShowPetGroupContextMenu(self.contextMenuPet)
            return
        end
        if origOnMouseDown then origOnMouseDown(self, button) end
    end)

    row:Show()
end

--------------------------------------------------------------------------------
-- CONTEXT MENUS
--------------------------------------------------------------------------------

-- Build the "Expand/Collapse All" + "Delete All" tail shared by several menus
local function AppendBulkGroupMenuItems(menuList)
    table.insert(menuList, { text = " ", isTitle = true, notCheckable = true })
    table.insert(menuList, {
        text = ns.L("Expand All Groups"), notCheckable = true,
        func = function() SetAllGroupsCollapsed(false) end,
    })
    table.insert(menuList, {
        text = ns.L("Collapse All Groups"), notCheckable = true,
        func = function() SetAllGroupsCollapsed(true) end,
    })
    table.insert(menuList, { text = " ", isTitle = true, notCheckable = true })
    table.insert(menuList, {
        text = ns.L("Delete All Groups"), notCheckable = true,
        func = function() ns.UI.GroupedView:ConfirmDeleteAllGroups() end,
    })
end

-- Ctrl/Shift + right-click on a pet model
function ns.UI.GroupedView:ShowPetGroupContextMenu(pet)
    if not pet or not pet.guid then return end

    local groups = ns.PetGroups:GetGroups()

    -- Find pet's current group
    local currentGroupId = nil
    for _, group in ipairs(groups) do
        if group.id ~= "ungrouped" then
            for _, guid in ipairs(group.pets or {}) do
                if guid == pet.guid then currentGroupId = group.id; break end
            end
        end
        if currentGroupId then break end
    end
    -- Pets not in any named group are considered "ungrouped"
    -- currentGroupId == nil means the pet is currently ungrouped

    local menuList = {
        { text = ns.L("Move pet to group:"), isTitle = true, notCheckable = true },
    }

    -- "Ungrouped" option — only shown when the pet is NOT already ungrouped
    if currentGroupId ~= nil then
        table.insert(menuList, {
            text = ns.L("Ungrouped"), notCheckable = true,
            func = function()
                ns.PetGroups:MovePetToGroup(pet.guid, "ungrouped")
                RefreshUI()
            end,
        })
    end

    -- Named groups, sorted alphabetically, excluding the current one
    local sortedGroups = {}
    for _, group in ipairs(groups) do
        if group.id ~= "ungrouped" then table.insert(sortedGroups, group) end
    end
    table.sort(sortedGroups, function(a, b)
        return (a.name or ""):lower() < (b.name or ""):lower()
    end)

    for _, group in ipairs(sortedGroups) do
        if group.id ~= currentGroupId then
            table.insert(menuList, {
                text = group.name, notCheckable = true,
                func = function()
                    ns.PetGroups:MovePetToGroup(pet.guid, group.id)
                    RefreshUI()
                end,
            })
        end
    end

    table.insert(menuList, { text = " ", isTitle = true, notCheckable = true })
    table.insert(menuList, {
        text = ns.L("Create New Group..."), notCheckable = true,
        func = function() ns.UI.GroupedView:ShowCreateGroupForPetDialog(pet) end,
    })

    ns.Utils:ShowContextMenu(menuList)
end

-- Right-click on a named group header
function ns.UI.GroupedView:ShowGroupContextMenu(groupId, groupName)
    if not groupId or groupId == "ungrouped" then return end

    local menuList = {
        { text = groupName or ns.L("Group"), isTitle = true, notCheckable = true },
        {
            text = ns.L("Rename Group"), notCheckable = true,
            func = function() ns.UI.GroupedView:ShowRenameDialog(groupId, groupName) end,
        },
        {
            text = ns.L("Delete Group"), notCheckable = true,
            func = function() ns.UI.GroupedView:ConfirmDeleteGroup(groupId, groupName) end,
        },
    }
    AppendBulkGroupMenuItems(menuList)
    ns.Utils:ShowContextMenu(menuList)
end

-- Right-click on the "Ungrouped" header
function ns.UI.GroupedView:ShowAutoGroupContextMenu(pets)
    if not pets or #pets == 0 then return end

    local function autoGroup(criteria)
        ns.PetGroups:AutoGroupPets(pets, criteria)
        RefreshUI()
    end

    local menuList = {
        { text = ns.L("Auto-create groups by:"), isTitle = true, notCheckable = true },
        { text = ns.L("Family"),       notCheckable = true, func = function() autoGroup("familyName") end },
        { text = ns.L("Spec"),         notCheckable = true, func = function() autoGroup("specName")   end },
        { text = ns.L("Exotic"),       notCheckable = true, func = function() autoGroup("isExotic")   end },
        { text = ns.L("Owner (Tamer)"),notCheckable = true, func = function() autoGroup("tamer")      end },
    }
    AppendBulkGroupMenuItems(menuList)
    ns.Utils:ShowContextMenu(menuList)
end

--------------------------------------------------------------------------------
-- GROUP CRUD DIALOGS
--------------------------------------------------------------------------------

-- A rejection reported only in chat is missed with a maximized panel open, which is
-- exactly how "A group with this name already exists" looked like the pet silently
-- failing to move. UIErrorsFrame is where the client puts "you cannot do that", so it
-- lands in front of the eyes already on the screen. Chat keeps the record.
local function ReportGroupFailure(message)
    if UIErrorsFrame then UIErrorsFrame:AddMessage(message, 1, 0.2, 0.2) end
    print("|cFFFF0000PetStableManagement: " .. message .. "|r")
end

function ns.UI.GroupedView:ShowCreateGroupForPetDialog(pet)
    if not pet then return end
    ns.Dialogs:ShowCreateGroupDialog({
        suggestedName = pet.familyName or pet.name or ns.L("New Group"),
        onConfirm = function(groupName)
            local groupId, err = ns.PetGroups:CreateGroup(groupName)
            if groupId then
                -- The move was already intended here and its result was discarded, so a
                -- failure left the new group empty with nothing said. CreateGroup's error
                -- is reported two lines down; this one was not.
                local moved, moveErr = ns.PetGroups:MovePetToGroup(pet.guid, groupId)
                if not moved then
                    print("|cFFFF0000PetStableManagement: " ..
                        (moveErr or ns.L("Failed to move pet to group")) .. "|r")
                end
                ns.C_Timer.After(0.05, function()
                    if ns.UI and ns.UI.RenderPanel then ns.UI:RenderPanel(true) end
                end)
            else
                ReportGroupFailure(err or ns.L("Failed to create group"))
            end
        end,
    })
end

function ns.UI.GroupedView:ShowRenameDialog(groupId, currentName)
    if not groupId then return end
    ns.Dialogs:ShowRenameGroupDialog({
        currentName = currentName,
        onConfirm = function(newName)
            local ok, err = ns.PetGroups:RenameGroup(groupId, newName)
            if ok then RefreshUI()
            else ReportGroupFailure(err or ns.L("Failed to rename group")) end
        end,
    })
end

function ns.UI.GroupedView:ConfirmDeleteGroup(groupId, groupName)
    if not groupId then return end
    ns.Dialogs:ShowDeleteGroupConfirmDialog(groupName, function()
        local ok, err = ns.PetGroups:DeleteGroup(groupId)
        if ok then RefreshUI()
        else print("|cFFFF0000PetStableManagement: " .. (err or ns.L("Failed to delete group")) .. "|r") end
    end)
end

function ns.UI.GroupedView:ConfirmDeleteAllGroups()
    ns.Dialogs:ShowDeleteAllGroupsConfirmDialog(function()
        ns.PetGroups:DeleteAllGroups()
        RefreshUI()
    end)
end

-- Kept for any external callers; now just delegate to SetAllGroupsCollapsed
function ns.UI.GroupedView:ExpandAllGroups()  SetAllGroupsCollapsed(false) end
function ns.UI.GroupedView:CollapseAllGroups() SetAllGroupsCollapsed(true)  end

function ns.UI.GroupedView:AutoCreateGroupsByCriteria(pets, criteria)
    if not pets or #pets == 0 then return end
    ns.PetGroups:AutoGroupPets(pets, criteria)
    RefreshUI()
end

--------------------------------------------------------------------------------
-- GROUP HEADER WIDGET
--------------------------------------------------------------------------------

-- "(3 pets)" / "(1 pet)"
local function PetCountLabel(petCount)
    petCount = petCount or 0
    -- Two whole sentences rather than stitching an "s" on: plural is not a suffix
    -- in every language.
    if petCount == 1 then return ns.L("(%d pet)", petCount) end
    return ns.L("(%d pets)", petCount)
end

local EXPAND_BUTTON_ANCHOR = { "LEFT", 4, 0 }

function ns.UI.GroupedView:CreateGroupHeader(parent, groupName, petCount)
    local Widgets = ns.Widgets

    local header = Widgets.Frame(parent, {
        height      = HEADER_HEIGHT,
        backdrop    = "TOOLTIP_ROW",
        color       = { 0.15, 0.15, 0.15 },
        borderColor = { 0.5,  0.5,  0.5  },
    })

    local expandButton = Widgets.IconButton(header, {
        size  = { 16, 16 },
        point = { EXPAND_BUTTON_ANCHOR[1], header, EXPAND_BUTTON_ANCHOR[1],
                  EXPAND_BUTTON_ANCHOR[2], EXPAND_BUTTON_ANCHOR[3] },
        skin  = "collapsebutton",
    })

    -- Textures and geometry are applied *after* skinning, not before: ElvUI's
    -- HandleButton strips textures and resets size/point, so anything set first is
    -- discarded. The original re-stated size and point here for exactly this reason;
    -- IconButton applies `skin` last, so this ordering still holds.
    local minus = ns.Skin.Texture("MinusButton")
    expandButton:SetNormalTexture(minus)
    expandButton:SetPushedTexture(minus)
    expandButton:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    expandButton:SetSize(16, 16)
    expandButton:ClearAllPoints()
    expandButton:SetPoint(EXPAND_BUTTON_ANCHOR[1], header, EXPAND_BUTTON_ANCHOR[1],
                          EXPAND_BUTTON_ANCHOR[2], EXPAND_BUTTON_ANCHOR[3])
    -- OnClick is set in UpdateVisibleRows so it has access to the current section
    header.expandButton = expandButton

    header.nameText = Widgets.Label(header, {
        fontSize = ns.Theme.SIZE.LABEL,
        outline  = true,
        color    = ns.Theme.COLOR.GOLD,
        point    = { "LEFT", expandButton, "RIGHT", 4, 0 },
        text     = groupName or ns.L("Group"),
    })

    header.countText = Widgets.Label(header, {
        fontSize = ns.Theme.SIZE.SMALL,
        color    = ns.Theme.COLOR.DIM,
        point    = { "LEFT", header.nameText, "RIGHT", 8, 0 },
        text     = PetCountLabel(petCount),
    })

    header:EnableMouse(true)
    return header
end

--------------------------------------------------------------------------------
-- LAYOUT
--------------------------------------------------------------------------------

function ns.UI.GroupedView:BuildGroupedLayout(renderData, contentWidth)
    groupedLayout.sections      = {}
    groupedLayout.contentHeight = 0
    if not renderData or not renderData.filteredPets then return end

    local modelSize = self.GRID_VIEW_MODEL_SIZE
    local pad       = ns.Config.COLUMN_SPACING or 8
    local colWidth  = modelSize + 2 * pad
    local colCount  = math.max(1, math.floor(contentWidth / colWidth))

    groupedLayout.colCount = colCount
    groupedLayout.colWidth = colWidth

    local petGroups     = ns.PetGroups
    local groups        = petGroups:GetGroups()
    local petToGroup    = {}
    local groupNameMap  = {}
    local groupPetsOrder= {}

    for _, group in ipairs(groups) do
        groupNameMap[group.id]   = group.name
        groupPetsOrder[group.id] = group.pets or {}
        if group.id ~= "ungrouped" then
            for _, guid in ipairs(group.pets or {}) do
                petToGroup[guid] = group.id
            end
        end
    end

    local byGroup = {}
    local order   = {}
    for _, pet in ipairs(renderData.filteredPets) do
        local gid = (pet.guid and petToGroup[pet.guid]) or "ungrouped"
        if not byGroup[gid] then byGroup[gid] = {}; table.insert(order, gid) end
        table.insert(byGroup[gid], pet)
    end

    for gid, petList in pairs(byGroup) do
        if ns.state.sortBy == "model" then
            table.sort(petList, function(a,b) return (a.displayID or 0) < (b.displayID or 0) end)
        elseif ns.state.sortBy == "slot" then
            table.sort(petList, function(a,b) return (a.slotID or 0) < (b.slotID or 0) end)
        elseif ns.state.sortBy == "family" then
            table.sort(petList, function(a,b)
                local af = a.familyName or ""
                local bf = b.familyName or ""
                if af == bf then
                    return (a.displayID or 0) < (b.displayID or 0)
                end
                return af < bf
            end)
        elseif ns.state.sortBy == "spec" then
            table.sort(petList, function(a,b)
                local as = a.specName or ""
                local bs = b.specName or ""
                if as == bs then
                    return (a.displayID or 0) < (b.displayID or 0)
                end
                return as < bs
            end)
        elseif ns.state.sortBy == "tamer" then
            table.sort(petList, function(a,b)
                local at = a.tamer or ""
                local bt = b.tamer or ""
                if at == bt then
                    return (a.displayID or 0) < (b.displayID or 0)
                end
                return at < bt
            end)
        else
            local stored = groupPetsOrder[gid]
            if stored and #stored > 0 then
                local pos = {}
                for i, guid in ipairs(stored) do pos[guid] = i end
                table.sort(petList, function(a,b)
                    return (pos[a.guid] or 99999) < (pos[b.guid] or 99999)
                end)
            end
        end
    end

    table.sort(order, function(a, b)
        if a == "ungrouped" then return true end
        if b == "ungrouped" then return false end
        return (groupNameMap[a] or a):lower() < (groupNameMap[b] or b):lower()
    end)

    local y = 0
    for _, gid in ipairs(order) do
        local list = byGroup[gid]
        if list and #list > 0 then
            local isCollapsed = IsGroupCollapsed(gid)
            local rows        = math.ceil(#list / colCount)
            local sectionH    = HEADER_HEIGHT + HEADER_SPACING
            if not isCollapsed then
                sectionH = sectionH + rows * self.GRID_VIEW_ROW_HEIGHT
            end
            local groupName = gid == "ungrouped" and ns.L("Ungrouped") or (groupNameMap[gid] or gid)
            table.insert(groupedLayout.sections, {
                gid       = gid,
                name      = groupName,
                pets      = list,
                y         = y,
                h         = sectionH,
                collapsed = isCollapsed,
            })
            y = y + sectionH + HEADER_SPACING
        end
    end
    groupedLayout.contentHeight = y
end

--------------------------------------------------------------------------------
-- RENDER
--------------------------------------------------------------------------------

function ns.UI.GroupedView:UpdateVisibleRows()
    local renderData = ns.state.currentRenderData
    if not renderData or not ns.state.panel then return end
    local content = ns.state.content
    if not content then return end

    if not ns.state.groupedViewRows then
        ns.state.groupedViewRows = {}
        ns.state.groupedViewHeaders = {}
        for _ = 1, 50 do
            local r = ns.UI.GroupedView:CreateModelRow(content); r:Hide()
            table.insert(ns.state.groupedViewRows, r)
        end
    end

    if renderData.filteredCount == 0 then
        for _, r in ipairs(ns.state.groupedViewRows) do r:Hide() end
        for _, h in ipairs(ns.state.groupedViewHeaders or {}) do h:Hide() end
        return
    end

    local contentWidth = content:GetWidth() or 500
    self:BuildGroupedLayout(renderData, contentWidth)
    content:SetHeight(math.max(groupedLayout.contentHeight, 100))
    if ns.state.scrollFrame.UpdateScrollChildRect then ns.state.scrollFrame:UpdateScrollChildRect() end
    -- Before reading the scroll below: this view's visibility test is purely geometric,
    -- so a scroll past the end of the content silently matches no section at all.
    ns.UI:ClampScrollIntoRange(ns.state.scrollFrame, content)

    local scrollH = ns.state.scrollFrame:GetHeight() or 500
    local scrollV = ns.state.scrollFrame:GetVerticalScroll() or 0
    local visibleTop = scrollV
    local visibleBottom = scrollV + scrollH

    for _, r in ipairs(ns.state.groupedViewRows) do r:Hide() end
    for _, h in ipairs(ns.state.groupedViewHeaders or {}) do h:Hide() end

    local colCount = groupedLayout.colCount
    local colWidth = groupedLayout.colWidth
    local margin = (contentWidth - colCount * colWidth) / 2

    local rowsNeeded = 0
    for _, section in ipairs(groupedLayout.sections) do
        if section.y + section.h >= visibleTop and section.y <= visibleBottom and not section.collapsed then
            rowsNeeded = rowsNeeded + math.ceil(#section.pets / colCount)
        end
    end
    if rowsNeeded > #ns.state.groupedViewRows then
        for _ = 1, rowsNeeded - #ns.state.groupedViewRows do
            local r = ns.UI.GroupedView:CreateModelRow(content); r:Hide()
            table.insert(ns.state.groupedViewRows, r)
        end
    end

    local visibleSectionCount = 0
    for _, section in ipairs(groupedLayout.sections) do
        if section.y + section.h >= visibleTop and section.y <= visibleBottom then
            visibleSectionCount = visibleSectionCount + 1
        end
    end
    if visibleSectionCount > #ns.state.groupedViewHeaders then
        for _ = #ns.state.groupedViewHeaders + 1, visibleSectionCount do
            local h = ns.UI.GroupedView:CreateGroupHeader(content, "", 0); h:Hide()
            table.insert(ns.state.groupedViewHeaders, h)
        end
    end

    local rowPoolIndex = 1
    for _, section in ipairs(groupedLayout.sections) do
        if section.y + section.h >= visibleTop and section.y <= visibleBottom then
            local header = table.remove(ns.state.groupedViewHeaders, 1)
                        or ns.UI.GroupedView:CreateGroupHeader(content, section.name, #section.pets)
            header:ClearAllPoints()
            header:SetWidth(contentWidth - 10)
            header:SetPoint("TOPLEFT", content, "TOPLEFT", 5, -section.y)
            header.groupId = section.gid
            header.isGroupHeader = true
            if header.nameText then header.nameText:SetText(section.name or ns.L("Group")) end
            if header.countText then header.countText:SetText(PetCountLabel(#section.pets)) end
            if header.expandButton then
                local tex = ns.Skin.Texture(section.collapsed and "PlusButton" or "MinusButton")
                header.expandButton:SetNormalTexture(tex)
                header.expandButton:SetPushedTexture(tex)
                header.expandButton:SetScript("OnClick", function(self, button)
                    if button == "LeftButton" and header.groupId then
                        ToggleGroupCollapsed(header.groupId)
                        if ns.UI and ns.UI.RenderPanel then ns.UI:RenderPanel(true) end
                    end
                end)
            end
            header:Show()
            header:EnableMouse(true)
            header:SetScript("OnEnter", function(self)
                if ns.DragDrop and ns.DragDrop.state.isDragging then
                    ns.DragDrop:OnEnterTarget(self, nil)
                end
            end)
            header:SetScript("OnLeave", function(self)
                if ns.DragDrop and ns.DragDrop.state.isDragging then
                    ns.DragDrop:OnLeaveTarget(self)
                end
            end)
            -- Store section name for context menu (must be before OnMouseDown)
            header.groupName = section.name
            -- Use header upvalue (not self) to match original behaviour
            header:SetScript("OnMouseDown", function(self, button)
                if button == "LeftButton" and header.groupId then
                    ToggleGroupCollapsed(header.groupId)
                    if ns.UI and ns.UI.RenderPanel then ns.UI:RenderPanel(true) end
                elseif button == "RightButton" then
                    if header.groupId == "ungrouped" then
                        ns.UI.GroupedView:ShowAutoGroupContextMenu(section.pets)
                    elseif header.groupId then
                        ns.UI.GroupedView:ShowGroupContextMenu(header.groupId, header.groupName)
                    end
                end
            end)
            table.insert(ns.state.groupedViewHeaders, header)

            if not section.collapsed then
                for i, pet in ipairs(section.pets) do
                    local col  = (i-1) % colCount
                    local rIdx = math.floor((i-1) / colCount)
                    local rowY = section.y + HEADER_HEIGHT + HEADER_SPACING + rIdx * ns.UI.GroupedView.GRID_VIEW_ROW_HEIGHT
                    local rowBottomY = rowY + ns.UI.GroupedView.GRID_VIEW_ROW_HEIGHT
                    if rowBottomY >= visibleTop and rowY <= visibleBottom then
                        if rowPoolIndex > #ns.state.groupedViewRows then break end
                        local row = ns.state.groupedViewRows[rowPoolIndex]
                        row:ClearAllPoints()
                        row:SetPoint("TOPLEFT", content, "TOPLEFT", margin + col * colWidth, -rowY)
                        row:SetWidth(colWidth)
                        row:SetHeight(ns.UI.GroupedView.GRID_VIEW_ROW_HEIGHT)
                        ns.state.allGroups = renderData.allGroups
                        row.groupId         = section.gid
                        row.groupIndex      = i
                        ns.UI.GroupedView:UpdateRow(row, pet)
                        row:Show()
                        rowPoolIndex = rowPoolIndex + 1
                    end
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- ENABLE / DISABLE / TOGGLE
--------------------------------------------------------------------------------

function ns.UI.GroupedView:Enable()
    ns.state.panelViewMode = "grouped"
    ns.state.panel.scrollOffset = 0
    if ns.state.panel.scrollFrame then ns.state.panel.scrollFrame:SetVerticalScroll(0) end
    if ns.state.rows           then for _, r in ipairs(ns.state.rows)           do if r then r:Hide() end end end
    if ns.state.modelViewRows  then for _, r in ipairs(ns.state.modelViewRows)  do if r then r:Hide() end end end
    ns.C_Timer.After(0.01, function() if ns.UI and ns.UI.RenderPanel then ns.UI:RenderPanel() end end)
end

function ns.UI.GroupedView:Disable()
    ns.state.panelViewMode = "list"
    ns.state.panel.scrollOffset = 0
    if ns.state.panel.scrollFrame then ns.state.panel.scrollFrame:SetVerticalScroll(0) end

    if ns.state.groupedViewRows then
        for _, r in ipairs(ns.state.groupedViewRows) do
            if r then
                r:Hide()
                r.petData = nil; r.groupId = nil; r.groupIndex = nil; r.contextMenuPet = nil
                if r.model then
                    r.model:Hide(); r.model:ClearModel()
                    r.model.contextMenuPet = nil
                    r.model.isRotating = false
                    ns.RowManager:ReleaseModel(r.model)
                end
            end
        end
    end

    if ns.state.groupedViewHeaders then
        for _, h in ipairs(ns.state.groupedViewHeaders) do
            if h then
                h:Hide(); h.groupId = nil; h.groupName = nil
                h:SetScript("OnEnter", nil); h:SetScript("OnLeave", nil); h:SetScript("OnMouseDown", nil)
            end
        end
    end

    self:ClearLayout()
    ns.C_Timer.After(0.01, function() if ns.UI and ns.UI.RenderPanel then ns.UI:RenderPanel() end end)
end

function ns.UI.GroupedView:ClearLayout()
    groupedLayout.sections      = {}
    groupedLayout.contentHeight = 0
end

function ns.UI.GroupedView:Toggle()
    if ns.state.panelViewMode == "grouped" then self:Disable() else self:Enable() end
end

function ns.UI.GroupedView:IsEnabled()
    return ns.state.panelViewMode == "grouped"
end