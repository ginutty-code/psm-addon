-- OwnedPets/GroupedView.lua
-- Grouped view for Owned Pets panel - lightweight, GridView-based grouping

local addonName = "PetStableManagement"

_G.PSM = _G.PSM or {}
local PSM = _G.PSM

PSM.UI.GroupedView = {}

PSM.UI.GroupedView.GRID_VIEW_ROW_HEIGHT = PSM.Config.GRID_ROW_HEIGHT
PSM.UI.GroupedView.GRID_VIEW_MODEL_SIZE = PSM.Config.GRID_MODEL_SIZE

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
    for _, group in ipairs(PSM.PetGroups:GetGroups()) do
        SetGroupCollapsed(group.id, collapsed)
    end
    PSM._renderCache = nil
    if PSM.UI and PSM.UI.RenderPanel then PSM.UI:RenderPanel(true) end
end

--------------------------------------------------------------------------------
-- SHARED UI REFRESH
--------------------------------------------------------------------------------

local function RefreshUI()
    PSM._renderCache = nil
    if PSM.UI and PSM.UI.RenderPanel then PSM.UI:RenderPanel(true) end
end

--------------------------------------------------------------------------------
-- PET TOOLTIP
--------------------------------------------------------------------------------

-- The ability list colour per bucket. The bracketed prefixes carry their own inline
-- colour codes; these are the colours of the ability names that follow them.
local ABILITY_BUCKETS = {
    { key = "spec",    prefix = "|cFFFFD700[Spec]|r",   color = { 1,   1, 1   } },
    { key = "family",  prefix = "|cFF40FF40[Family]|r", color = { 0.8, 1, 0.8 } },
    { key = "pet",     prefix = "|cFF40FFFF[Pet]|r",    color = { 0.8, 1, 1   } },
    { key = "unknown", prefix = "|cFFAAAAAA[Other]|r",  color = { 0.7, 0.7, 0.7 } },
}

-- Everything a grouped-view pet tooltip says, as a spec. Built per hover rather than
-- per render: the interaction hints at the bottom depend on the active sort and on
-- whether the stable is open, both of which change while a row exists.
local function PetTooltipSpec(pet)
    if not pet then return nil end

    local Theme = PSM.Theme
    local lines = {}
    local function Add(text, color) lines[#lines + 1] = { text = text, color = color } end

    Add(string.format("DisplayID: %d", pet.displayID or 0), Theme.COLOR.MUTED)
    if pet.familyName then Add("Family: " .. pet.familyName, Theme.COLOR.WHITE) end
    if pet.specName   then Add("Spec: "   .. pet.specName,   Theme.COLOR.MUTED) end
    if pet.tamer      then Add("Owned by: " .. pet.tamer,    Theme.COLOR.DIM)   end

    if pet.level and pet.level > 0 then
        local levelColor = pet.level >= 25 and " |cFF00FF00" or (pet.level >= 1 and " |cFFFFFF00" or " |cFF888888")
        Add(string.format("Level: %d%s", pet.level, levelColor), Theme.COLOR.WHITE)
    end

    local abilities    = type(pet.abilities) == "table" and pet.abilities or {}
    local hasAbilities = false

    if abilities.family or abilities.spec or abilities.pet or abilities.unknown then
        Add(" ")
        Add("|cFFFFD700Abilities:|r", Theme.COLOR.WHITE)
        for _, bucket in ipairs(ABILITY_BUCKETS) do
            local list = abilities[bucket.key]
            if list and #list > 0 then
                for _, ability in ipairs(list) do
                    Add(string.format("  %s %s", bucket.prefix, ability), bucket.color)
                end
                hasAbilities = true
            end
        end
    else
        -- Flat list: older saved data that predates the grouped buckets.
        for _, ability in ipairs(abilities) do
            Add("  \226\128\162 " .. (type(ability) == "table" and ability.name or tostring(ability)),
                Theme.COLOR.WHITE)
            hasAbilities = true
        end
    end

    if not hasAbilities then
        Add(" ")
        Add("|cFFAAAAAA(No abilities available)", Theme.COLOR.DIM)
    end

    local hints = "Left-click and drag to rotate\nRight-click and drag to move (left/right, up/down)\nScroll to zoom"
    if PSM.state.sortBy then
        hints = hints .. "\n|cFFFF8800Reordering disabled while sorting is active.|r"
            .. "\n|cFFFF8800Set Sort by to Unsorted to re-enable.|r"
    else
        hints = hints .. "\nShift/Ctrl + drag to reorder within group (works outside stable)"
    end
    hints = hints .. "\nShift/Ctrl + Right-click to move to a specific group"
    if PSM.state and PSM.state.isStableOpen and pet.slotID then
        hints = hints .. "\nShift/Ctrl + drag to swap stable slots"
    end
    Add(" ")
    Add(hints, Theme.COLOR.DIM)

    local exoticLabel = pet.isExotic and " |cffff8800[Exotic]|r" or ""
    return {
        title      = string.format("Slot %d: %s%s", pet.slotID or 0, pet.name or "?", exoticLabel),
        titleColor = Theme.COLOR.WHITE,
        lines      = lines,
    }
end

function PSM.UI.GroupedView:ShowPetTooltip(row, pet)
    PSM.Tooltip.Show(row, PetTooltipSpec(pet))
end

--------------------------------------------------------------------------------
-- ROW CREATION / UPDATE
--------------------------------------------------------------------------------

function PSM.UI.GroupedView:CreateModelRow(parent)
    local row = PSM.RowManager:CreateBaseRow(parent, {
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

    local function showButtons(self)
        if self.resetButton   then self.resetButton:Show() end
        if self.magnifyButton then self.magnifyButton:Show() end
        if self.addToTeamButton      and self.isOwnedByPlayer then self.addToTeamButton:Show()      end
        if self.removeFromTeamButton and self.isOwnedByPlayer then self.removeFromTeamButton:Show() end
    end
    local function hideButtons(self)
        if self.resetButton          and not self.resetButton:IsMouseOver()          then self.resetButton:Hide() end
        if self.magnifyButton        and not self.magnifyButton:IsMouseOver()        then self.magnifyButton:Hide() end
        if self.addToTeamButton      and not self.addToTeamButton:IsMouseOver()      then self.addToTeamButton:Hide() end
        if self.removeFromTeamButton and not self.removeFromTeamButton:IsMouseOver() then self.removeFromTeamButton:Hide() end
    end

    -- Anchored to `row`, not to the model, so the tooltip sits beside the whole cell
    -- however the mouse arrived. Both the model and the row show the same thing;
    -- entering the model deliberately replaces RowManager's rotate/zoom tooltip,
    -- because these hints are already the last section of the pet tooltip.
    local function TooltipForRow() return PetTooltipSpec(row.petData) end

    PSM.Tooltip.Attach(row.model, TooltipForRow, { onEnter = showButtons, onLeave = hideButtons })
    PSM.Tooltip.Attach(row,       TooltipForRow)

    return row
end

function PSM.UI.GroupedView:UpdateRow(row, pet)
    if not row or not pet then return end
    row.petData = pet
    if row.model and pet.displayID then
        PSM.RowManager:UpdateModelDisplay(row, pet.displayID, pet.icon, pet)
    end
    local isSame, isCross = PSM.RowManager:CheckDuplicates(pet, PSM.state.allGroups)
    PSM.RowManager:UpdateBackgroundColor(row, isSame, isCross, false, pet.specName)
    PSM.RowManager:HideFavoriteButton(row)
    if PSM.DragDrop then
        PSM.DragDrop:SetupRowDragDrop(row, pet, true)
        PSM.DragDrop:SetupModelDragDrop(row.model, pet, row, true)
    end

    row.contextMenuPet       = pet
    row.model.contextMenuPet = pet

    local origOnMouseDown = row.model:GetScript("OnMouseDown")
    row.model:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" and (IsShiftKeyDown() or IsControlKeyDown()) then
            PSM.UI.GroupedView:ShowPetGroupContextMenu(self.contextMenuPet)
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
        text = "Expand All Groups", notCheckable = true,
        func = function() SetAllGroupsCollapsed(false) end,
    })
    table.insert(menuList, {
        text = "Collapse All Groups", notCheckable = true,
        func = function() SetAllGroupsCollapsed(true) end,
    })
    table.insert(menuList, { text = " ", isTitle = true, notCheckable = true })
    table.insert(menuList, {
        text = "Delete All Groups", notCheckable = true,
        func = function() PSM.UI.GroupedView:ConfirmDeleteAllGroups() end,
    })
end

-- Ctrl/Shift + right-click on a pet model
function PSM.UI.GroupedView:ShowPetGroupContextMenu(pet)
    if not pet or not pet.guid then return end

    local groups = PSM.PetGroups:GetGroups()

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
        { text = "Move pet to group:", isTitle = true, notCheckable = true },
    }

    -- "Ungrouped" option — only shown when the pet is NOT already ungrouped
    if currentGroupId ~= nil then
        table.insert(menuList, {
            text = "Ungrouped", notCheckable = true,
            func = function()
                PSM.PetGroups:MovePetToGroup(pet.guid, "ungrouped")
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
                    PSM.PetGroups:MovePetToGroup(pet.guid, group.id)
                    RefreshUI()
                end,
            })
        end
    end

    table.insert(menuList, { text = " ", isTitle = true, notCheckable = true })
    table.insert(menuList, {
        text = "Create New Group...", notCheckable = true,
        func = function() PSM.UI.GroupedView:ShowCreateGroupForPetDialog(pet) end,
    })

    PSM.Utils:ShowContextMenu(menuList)
end

-- Right-click on a named group header
function PSM.UI.GroupedView:ShowGroupContextMenu(groupId, groupName)
    if not groupId or groupId == "ungrouped" then return end

    local menuList = {
        { text = groupName or "Group", isTitle = true, notCheckable = true },
        {
            text = "Rename Group", notCheckable = true,
            func = function() PSM.UI.GroupedView:ShowRenameDialog(groupId, groupName) end,
        },
        {
            text = "Delete Group", notCheckable = true,
            func = function() PSM.UI.GroupedView:ConfirmDeleteGroup(groupId, groupName) end,
        },
    }
    AppendBulkGroupMenuItems(menuList)
    PSM.Utils:ShowContextMenu(menuList)
end

-- Right-click on the "Ungrouped" header
function PSM.UI.GroupedView:ShowAutoGroupContextMenu(pets)
    if not pets or #pets == 0 then return end

    local function autoGroup(criteria)
        PSM.PetGroups:AutoGroupPets(pets, criteria)
        RefreshUI()
    end

    local menuList = {
        { text = "Auto-create groups by:", isTitle = true, notCheckable = true },
        { text = "Family",       notCheckable = true, func = function() autoGroup("familyName") end },
        { text = "Spec",         notCheckable = true, func = function() autoGroup("specName")   end },
        { text = "Exotic",       notCheckable = true, func = function() autoGroup("isExotic")   end },
        { text = "Owner (Tamer)",notCheckable = true, func = function() autoGroup("tamer")      end },
    }
    AppendBulkGroupMenuItems(menuList)
    PSM.Utils:ShowContextMenu(menuList)
end

--------------------------------------------------------------------------------
-- GROUP CRUD DIALOGS
--------------------------------------------------------------------------------

function PSM.UI.GroupedView:ShowCreateGroupForPetDialog(pet)
    if not pet then return end
    PSM.TeamDialogs:ShowCreateGroupDialog({
        suggestedName = pet.familyName or pet.name or "New Group",
        onConfirm = function(groupName)
            local groupId, err = PSM.PetGroups:CreateGroup(groupName)
            if groupId then
                PSM.PetGroups:MovePetToGroup(pet.guid, groupId)
                PSM._renderCache = nil
                PSM.C_Timer.After(0.05, function()
                    if PSM.UI and PSM.UI.RenderPanel then PSM.UI:RenderPanel(true) end
                end)
            else
                print("|cFFFF0000PetStableManagement: " .. (err or "Failed to create group") .. "|r")
            end
        end,
    })
end

function PSM.UI.GroupedView:ShowRenameDialog(groupId, currentName)
    if not groupId then return end
    PSM.TeamDialogs:ShowRenameGroupDialog({
        currentName = currentName,
        onConfirm = function(newName)
            local ok, err = PSM.PetGroups:RenameGroup(groupId, newName)
            if ok then RefreshUI()
            else print("|cFFFF0000PetStableManagement: " .. (err or "Failed to rename group") .. "|r") end
        end,
    })
end

function PSM.UI.GroupedView:ConfirmDeleteGroup(groupId, groupName)
    if not groupId then return end
    PSM.TeamDialogs:ShowDeleteGroupConfirmDialog(groupName, function()
        local ok, err = PSM.PetGroups:DeleteGroup(groupId)
        if ok then RefreshUI()
        else print("|cFFFF0000PetStableManagement: " .. (err or "Failed to delete group") .. "|r") end
    end)
end

function PSM.UI.GroupedView:ConfirmDeleteAllGroups()
    PSM.TeamDialogs:ShowDeleteAllGroupsConfirmDialog(function()
        PSM.PetGroups:DeleteAllGroups()
        RefreshUI()
    end)
end

-- Kept for any external callers; now just delegate to SetAllGroupsCollapsed
function PSM.UI.GroupedView:ExpandAllGroups()  SetAllGroupsCollapsed(false) end
function PSM.UI.GroupedView:CollapseAllGroups() SetAllGroupsCollapsed(true)  end

function PSM.UI.GroupedView:AutoCreateGroupsByCriteria(pets, criteria)
    if not pets or #pets == 0 then return end
    PSM.PetGroups:AutoGroupPets(pets, criteria)
    RefreshUI()
end

--------------------------------------------------------------------------------
-- GROUP HEADER WIDGET
--------------------------------------------------------------------------------

-- "(3 pets)" / "(1 pet)"
local function PetCountLabel(petCount)
    petCount = petCount or 0
    return "(" .. petCount .. " pet" .. (petCount ~= 1 and "s" or "") .. ")"
end

local EXPAND_BUTTON_ANCHOR = { "LEFT", 4, 0 }

function PSM.UI.GroupedView:CreateGroupHeader(parent, groupName, petCount)
    local Widgets = PSM.Widgets

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
    local minus = PSM.Skin.Texture("MinusButton")
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
        fontSize = PSM.Theme.SIZE.LABEL,
        outline  = true,
        color    = PSM.Theme.COLOR.GOLD,
        point    = { "LEFT", expandButton, "RIGHT", 4, 0 },
        text     = groupName or "Group",
    })

    header.countText = Widgets.Label(header, {
        fontSize = PSM.Theme.SIZE.SMALL,
        color    = PSM.Theme.COLOR.DIM,
        point    = { "LEFT", header.nameText, "RIGHT", 8, 0 },
        text     = PetCountLabel(petCount),
    })

    header:EnableMouse(true)
    return header
end

--------------------------------------------------------------------------------
-- LAYOUT
--------------------------------------------------------------------------------

function PSM.UI.GroupedView:BuildGroupedLayout(renderData, contentWidth)
    groupedLayout.sections      = {}
    groupedLayout.contentHeight = 0
    if not renderData or not renderData.filteredPets then return end

    local modelSize = self.GRID_VIEW_MODEL_SIZE
    local pad       = PSM.Config.COLUMN_SPACING or 8
    local colWidth  = modelSize + 2 * pad
    local colCount  = math.max(1, math.floor(contentWidth / colWidth))

    groupedLayout.colCount = colCount
    groupedLayout.colWidth = colWidth

    local petGroups     = PSM.PetGroups
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
        if PSM.state.sortBy == "model" then
            table.sort(petList, function(a,b) return (a.displayID or 0) < (b.displayID or 0) end)
        elseif PSM.state.sortBy == "slot" then
            table.sort(petList, function(a,b) return (a.slotID or 0) < (b.slotID or 0) end)
        elseif PSM.state.sortBy == "family" then
            table.sort(petList, function(a,b)
                local af = a.familyName or ""
                local bf = b.familyName or ""
                if af == bf then
                    return (a.displayID or 0) < (b.displayID or 0)
                end
                return af < bf
            end)
        elseif PSM.state.sortBy == "spec" then
            table.sort(petList, function(a,b)
                local as = a.specName or ""
                local bs = b.specName or ""
                if as == bs then
                    return (a.displayID or 0) < (b.displayID or 0)
                end
                return as < bs
            end)
        elseif PSM.state.sortBy == "tamer" then
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
            local groupName = gid == "ungrouped" and "Ungrouped" or (groupNameMap[gid] or gid)
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

function PSM.UI.GroupedView:UpdateVisibleRows()
    local renderData = PSM.state.currentRenderData
    if not renderData or not PSM.state.panel then return end
    local content = PSM.state.content
    if not content then return end

    if not PSM.state.groupedViewRows then
        PSM.state.groupedViewRows = {}
        PSM.state.groupedViewHeaders = {}
        for i = 1, 50 do
            local r = PSM.UI.GroupedView:CreateModelRow(content); r:Hide()
            table.insert(PSM.state.groupedViewRows, r)
        end
    end

    if renderData.filteredCount == 0 then
        for _, r in ipairs(PSM.state.groupedViewRows) do r:Hide() end
        for _, h in ipairs(PSM.state.groupedViewHeaders or {}) do h:Hide() end
        return
    end

    local contentWidth = content:GetWidth() or 500
    self:BuildGroupedLayout(renderData, contentWidth)
    content:SetHeight(math.max(groupedLayout.contentHeight, 100))
    if PSM.state.scrollFrame.UpdateScrollChildRect then PSM.state.scrollFrame:UpdateScrollChildRect() end

    local scrollH = PSM.state.scrollFrame:GetHeight() or 500
    local scrollV = PSM.state.scrollFrame:GetVerticalScroll() or 0
    local visibleTop = scrollV
    local visibleBottom = scrollV + scrollH

    for _, r in ipairs(PSM.state.groupedViewRows) do r:Hide() end
    for _, h in ipairs(PSM.state.groupedViewHeaders or {}) do h:Hide() end

    local colCount = groupedLayout.colCount
    local colWidth = groupedLayout.colWidth
    local margin = (contentWidth - colCount * colWidth) / 2

    local rowsNeeded = 0
    for _, section in ipairs(groupedLayout.sections) do
        if section.y + section.h >= visibleTop and section.y <= visibleBottom and not section.collapsed then
            rowsNeeded = rowsNeeded + math.ceil(#section.pets / colCount)
        end
    end
    if rowsNeeded > #PSM.state.groupedViewRows then
        for i = 1, rowsNeeded - #PSM.state.groupedViewRows do
            local r = PSM.UI.GroupedView:CreateModelRow(content); r:Hide()
            table.insert(PSM.state.groupedViewRows, r)
        end
    end

    local visibleSectionCount = 0
    for _, section in ipairs(groupedLayout.sections) do
        if section.y + section.h >= visibleTop and section.y <= visibleBottom then
            visibleSectionCount = visibleSectionCount + 1
        end
    end
    if visibleSectionCount > #PSM.state.groupedViewHeaders then
        for i = #PSM.state.groupedViewHeaders + 1, visibleSectionCount do
            local h = PSM.UI.GroupedView:CreateGroupHeader(content, "", 0); h:Hide()
            table.insert(PSM.state.groupedViewHeaders, h)
        end
    end

    local rowPoolIndex = 1
    for _, section in ipairs(groupedLayout.sections) do
        if section.y + section.h >= visibleTop and section.y <= visibleBottom then
            local header = table.remove(PSM.state.groupedViewHeaders, 1)
                        or PSM.UI.GroupedView:CreateGroupHeader(content, section.name, #section.pets)
            header:ClearAllPoints()
            header:SetWidth(contentWidth - 10)
            header:SetPoint("TOPLEFT", content, "TOPLEFT", 5, -section.y)
            header.groupId = section.gid
            header.isGroupHeader = true
            if header.nameText then header.nameText:SetText(section.name or "Group") end
            if header.countText then header.countText:SetText(PetCountLabel(#section.pets)) end
            if header.expandButton then
                local tex = PSM.Skin.Texture(section.collapsed and "PlusButton" or "MinusButton")
                header.expandButton:SetNormalTexture(tex)
                header.expandButton:SetPushedTexture(tex)
                header.expandButton:SetScript("OnClick", function(self, button)
                    if button == "LeftButton" and header.groupId then
                        ToggleGroupCollapsed(header.groupId)
                        PSM._renderCache = nil
                        if PSM.UI and PSM.UI.RenderPanel then PSM.UI:RenderPanel(true) end
                    end
                end)
            end
            header:Show()
            header:EnableMouse(true)
            header:SetScript("OnEnter", function(self)
                if PSM.DragDrop and PSM.DragDrop.state.isDragging then
                    PSM.DragDrop:OnEnterTarget(self, nil)
                end
            end)
            header:SetScript("OnLeave", function(self)
                if PSM.DragDrop and PSM.DragDrop.state.isDragging then
                    PSM.DragDrop:OnLeaveTarget(self)
                end
            end)
            -- Store section name for context menu (must be before OnMouseDown)
            header.groupName = section.name
            -- Use header upvalue (not self) to match original behaviour
            header:SetScript("OnMouseDown", function(self, button)
                if button == "LeftButton" and header.groupId then
                    ToggleGroupCollapsed(header.groupId)
                    PSM._renderCache = nil
                    if PSM.UI and PSM.UI.RenderPanel then PSM.UI:RenderPanel(true) end
                elseif button == "RightButton" then
                    if header.groupId == "ungrouped" then
                        PSM.UI.GroupedView:ShowAutoGroupContextMenu(section.pets)
                    elseif header.groupId then
                        PSM.UI.GroupedView:ShowGroupContextMenu(header.groupId, header.groupName)
                    end
                end
            end)
            table.insert(PSM.state.groupedViewHeaders, header)

            if not section.collapsed then
                for i, pet in ipairs(section.pets) do
                    local col  = (i-1) % colCount
                    local rIdx = math.floor((i-1) / colCount)
                    local rowY = section.y + HEADER_HEIGHT + HEADER_SPACING + rIdx * PSM.UI.GroupedView.GRID_VIEW_ROW_HEIGHT
                    local rowBottomY = rowY + PSM.UI.GroupedView.GRID_VIEW_ROW_HEIGHT
                    if rowBottomY >= visibleTop and rowY <= visibleBottom then
                        if rowPoolIndex > #PSM.state.groupedViewRows then break end
                        local row = PSM.state.groupedViewRows[rowPoolIndex]
                        row:ClearAllPoints()
                        row:SetPoint("TOPLEFT", content, "TOPLEFT", margin + col * colWidth, -rowY)
                        row:SetWidth(colWidth)
                        row:SetHeight(PSM.UI.GroupedView.GRID_VIEW_ROW_HEIGHT)
                        PSM.state.allGroups = renderData.allGroups
                        row.groupId         = section.gid
                        row.groupIndex      = i
                        PSM.UI.GroupedView:UpdateRow(row, pet)
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

function PSM.UI.GroupedView:Enable()
    PSM.state.panelViewMode = "grouped"
    PSM.state.panel.scrollOffset = 0
    if PSM.state.panel.scrollFrame then PSM.state.panel.scrollFrame:SetVerticalScroll(0) end
    if PSM.state.rows           then for _, r in ipairs(PSM.state.rows)           do if r then r:Hide() end end end
    if PSM.state.modelViewRows  then for _, r in ipairs(PSM.state.modelViewRows)  do if r then r:Hide() end end end
    PSM._renderCache = nil
    PSM.C_Timer.After(0.01, function() if PSM.UI and PSM.UI.RenderPanel then PSM.UI:RenderPanel() end end)
end

function PSM.UI.GroupedView:Disable()
    PSM.state.panelViewMode = "list"
    PSM.state.panel.scrollOffset = 0
    if PSM.state.panel.scrollFrame then PSM.state.panel.scrollFrame:SetVerticalScroll(0) end

    if PSM.state.groupedViewRows then
        for _, r in ipairs(PSM.state.groupedViewRows) do
            if r then
                r:Hide()
                r.petData = nil; r.groupId = nil; r.groupIndex = nil; r.contextMenuPet = nil
                if r.model then
                    r.model:Hide(); r.model:ClearModel()
                    r.model.contextMenuPet = nil
                    r.model.isRotating = false
                    if PSM.RotationFrame and PSM.RotationFrame.activeModels then
                        PSM.RotationFrame.activeModels[r.model] = nil
                    end
                end
            end
        end
    end

    if PSM.state.groupedViewHeaders then
        for _, h in ipairs(PSM.state.groupedViewHeaders) do
            if h then
                h:Hide(); h.groupId = nil; h.groupName = nil
                h:SetScript("OnEnter", nil); h:SetScript("OnLeave", nil); h:SetScript("OnMouseDown", nil)
            end
        end
    end

    self:ClearLayout()
    PSM._renderCache = nil
    PSM.C_Timer.After(0.01, function() if PSM.UI and PSM.UI.RenderPanel then PSM.UI:RenderPanel() end end)
end

function PSM.UI.GroupedView:ClearLayout()
    groupedLayout.sections      = {}
    groupedLayout.contentHeight = 0
end

function PSM.UI.GroupedView:Toggle()
    if PSM.state.panelViewMode == "grouped" then self:Disable() else self:Enable() end
end

function PSM.UI.GroupedView:IsEnabled()
    return PSM.state.panelViewMode == "grouped"
end