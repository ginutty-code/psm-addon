-- OwnedPets/DragDrop.lua
-- Drag and drop functionality for reordering pets in the Owned Pets panel

local addonName = "PetStableManagement"

_G.PSM = _G.PSM or {}
local PSM = _G.PSM
PSM.DragDrop = PSM.DragDrop or {}

local DD = PSM.DragDrop

-- Colors
local COLOR = {
    SOURCE  = {0.2, 0.6, 1.0, 0.4},
    TARGET  = {0.2, 1.0, 0.2, 0.4},
    INVALID = {1.0, 0.2, 0.2, 0.4},
}

local ICON_SIZE = 55

DD.state = {
    isDragging             = false,
    sourceRow              = nil,
    sourcePet              = nil,
    sourceGroupId          = nil,
    sourceAllowOutsideStable = nil,
    targetRow              = nil,
    targetPet              = nil,
    dragFrame              = nil,
    originalBackdrop       = nil,
    lastFocus              = nil,
}

DD.teamState = {
    isDragging    = false,
    sourceSlot    = nil,
    sourceTeamId  = nil,
    sourceRow     = nil,
    dragFrame     = nil,
}

------------------------------------------------
-- HELPERS
------------------------------------------------

local function SetRowColor(row, color)
    if not row or not row.SetBackdropColor then return end
    if row.isGroupHeader then
        row:SetBackdropBorderColor(color[1], color[2], color[3], color[4] or 1)
    else
        row:SetBackdropColor(unpack(color))
    end
end

local function ResetRowColor(row, savedBackdrop)
    if not row or not row.SetBackdropColor then return end
    if row.isGroupHeader then
        row:SetBackdropColor(0.15, 0.15, 0.15, 1)
        row:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    elseif savedBackdrop then
        row:SetBackdropColor(unpack(savedBackdrop))
    end
end

local function SetDropIndicator(row, show)
    -- Only show drop indicator in grouped view (where allowOutsideStable is true)
    if PSM.state.panelViewMode ~= "grouped" then return end
    if not row then return end
    if show then
        if not row._dropIndicator then
            local t = row:CreateTexture(nil, "OVERLAY")
            t:SetWidth(3)
            t:SetPoint("TOPLEFT",    row, "TOPLEFT",    0, 0)
            t:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
            t:SetColorTexture(0.2, 1.0, 0.2, 1)
            row._dropIndicator = t
        end
        row._dropIndicator:Show()
    else
        if row._dropIndicator then
            row._dropIndicator:Hide()
            row._dropIndicator:ClearAllPoints()
            row._dropIndicator = nil
        end
    end
end

local function GetDragFrame()
    if DD.state.dragFrame then return DD.state.dragFrame end

    local f = CreateFrame("Frame", "PSMDragFrame", UIParent, "BackdropTemplate")
    f:SetSize(80, 80)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(100)
    f:Hide()

    f.model = CreateFrame("PlayerModel", nil, f)
    f.model:SetAllPoints()
    f.model:SetRotation(math.pi * 2)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:Hide()

    f:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
    f:SetBackdropBorderColor(1, 1, 0, 1)

    f.slotText = f:CreateFontString(nil, "OVERLAY")
    f.slotText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    f.slotText:SetPoint("BOTTOM", f, "BOTTOM", 0, 2)
    f.slotText:SetTextColor(1, 1, 0)

    DD.state.dragFrame = f
    return f
end

local function GetTeamDragFrame()
    if DD.teamState.dragFrame then return DD.teamState.dragFrame end

    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(ICON_SIZE + 45, ICON_SIZE + 45)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(1000)
    f:Hide()
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)

    local portrait = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    portrait:SetSize(ICON_SIZE, ICON_SIZE)
    portrait:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.portrait = portrait

    local mask = f:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask",
        "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetSize(ICON_SIZE, ICON_SIZE)
    mask:SetPoint("CENTER", f, "CENTER", 0, 0)
    portrait:AddMaskTexture(mask)
    f.mask = mask

    local border = f:CreateTexture(nil, "BORDER")
    border:SetAtlas("footer_inactive-ring")
    border:SetAllPoints(f)
    f.border = border

    DD.teamState.dragFrame = f
    return f
end

------------------------------------------------
-- PET ROW DRAG & DROP
------------------------------------------------

function DD:StartDrag(row, pet, allowOutsideStable)
    if not row or not pet then return end
    if not PSM.state.isStableOpen and not allowOutsideStable then
        print("|cFFFF0000Must be at stable master to reorder pets|r")
        return false
    end

    local s = DD.state
    s.isDragging               = true
    s.sourceRow                = row
    s.sourcePet                = pet
    s.sourceAllowOutsideStable = allowOutsideStable
    s.sourceGroupId            = row.groupId

    -- Capture the source group's pet order at drag start for position fallback
    if row.groupId and PSM.PetGroups then
        local group = PSM.PetGroups:GetGroupById(row.groupId)
        if group and group.pets then
            s.sourceGroupPetOrder = {}
            for _, guid in ipairs(group.pets) do
                table.insert(s.sourceGroupPetOrder, guid)
            end
        end
    end

    if row.GetBackdropColor then
        s.originalBackdrop = {row:GetBackdropColor()}
    end
    SetRowColor(row, COLOR.SOURCE)

    local df = GetDragFrame()
    if pet.displayID and pet.displayID > 0 then
        df.model:SetDisplayInfo(pet.displayID)
        df.model:Show(); df.icon:Hide()
    elseif pet.icon then
        df.icon:SetTexture(pet.icon)
        df.icon:Show(); df.model:Hide()
    end
    df.slotText:SetText("Slot " .. (pet.slotID or "?"))
    df:Show()
    self:UpdateDragFramePosition()

    local interceptor = self:GetDragInterceptor()
    if interceptor then interceptor:Show() end

    return true
end

function DD:UpdateDragFramePosition()
    local df = DD.state.dragFrame
    if not df or not df:IsShown() then return end
    local scale = UIParent:GetEffectiveScale()
    local x, y  = GetCursorPosition()
    df:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
end

function DD:OnEnterTarget(row, pet)
    local s = DD.state
    if not s.isDragging or not row or row == s.sourceRow then return end
    s.targetRow = row
    s.targetPet = pet

    -- Save this row's own color before overwriting it (only if not already saved)
    if row.GetBackdropColor and not row.isGroupHeader and not row._savedBackdrop then
        row._savedBackdrop = {row:GetBackdropColor()}
    end

    local isValid
    if s.sourceAllowOutsideStable then
        local tgtGroup  = row.groupId
        local sameGroup = tgtGroup and (tgtGroup == s.sourceGroupId)
        isValid = tgtGroup ~= nil or row.isGroupHeader == true or sameGroup
    else
        isValid = PSM.state.isStableOpen and pet and pet.slotID
    end

    SetRowColor(row, isValid and COLOR.TARGET or COLOR.INVALID)
    if isValid and not row.isGroupHeader then SetDropIndicator(row, true) end
end

function DD:OnLeaveTarget(row)
    local s = DD.state
    if not s.isDragging or not row then return end
    ResetRowColor(row, row._savedBackdrop)
    SetDropIndicator(row, false)
    row._savedBackdrop = nil
    if s.targetRow == row then s.targetRow = nil end
end

function DD:EndDrag()
    local s = DD.state
    if s.dragFrame then s.dragFrame:Hide() end
    ResetRowColor(s.sourceRow, s.originalBackdrop)
    if s.targetRow then
        ResetRowColor(s.targetRow, s.targetRow._savedBackdrop)
        SetDropIndicator(s.targetRow, false)
        s.targetRow._savedBackdrop = nil
    end

    s.isDragging               = false
    s.sourceRow                = nil
    s.sourcePet                = nil
    s.sourceGroupId            = nil
    s.sourceAllowOutsideStable = nil
    s.sourceGroupPetOrder      = nil
    s.targetRow                = nil
    s.targetPet                = nil
    s.originalBackdrop         = nil
    s.lastFocus                = nil

    if self._interceptor then self._interceptor:Hide() end
end

function DD:CompleteDrop(targetRow, targetPet)
    local s = DD.state
    if not s.isDragging or not s.sourcePet then
        self:EndDrag(); return false
    end

    -- Group / outside-stable path
    if s.sourceAllowOutsideStable then
        local srcGUID   = s.sourcePet.guid
        local tgtGroup  = targetRow and targetRow.groupId
        local sameGroup = tgtGroup and (tgtGroup == s.sourceGroupId)

        if not srcGUID or not tgtGroup then self:EndDrag(); return false end

        local petGroups = PSM.PetGroups

        if sameGroup then
            local tgtGUID = s.targetPet and s.targetPet.guid
            if not tgtGUID then self:EndDrag(); return false end

            -- Get current storage for this group
            local group = petGroups:GetGroupById(tgtGroup)
            local storedPets = group and group.pets or {}

            -- Build a lookup of what's already tracked
            local tracked = {}
            for _, guid in ipairs(storedPets) do tracked[guid] = true end

            -- Seed only untracked visible pets in one batch (avoids per-pet Save() calls)
            if PSM.state.groupedViewRows then
                local toSeed = {}
                for _, r in ipairs(PSM.state.groupedViewRows) do
                    if r:IsShown() and r.groupId == tgtGroup
                            and r.dragDropPet and r.dragDropPet.guid
                            and not tracked[r.dragDropPet.guid] then
                        table.insert(toSeed, r.dragDropPet.guid)
                    end
                end
                if #toSeed > 0 then
                    petGroups:SeedUngroupedPets(toSeed)
                    -- Refresh after seeding
                    group = petGroups:GetGroupById(tgtGroup)
                    storedPets = group and group.pets or {}
                    for _, guid in ipairs(storedPets) do tracked[guid] = true end
                end
            end

            -- Find target position in (now seeded) storage
            local tgtPos = nil
            for i, guid in ipairs(storedPets) do
                if guid == tgtGUID then tgtPos = i; break end
            end

            -- Find source position to calculate adjustment
            local srcPos = nil
            for i, guid in ipairs(storedPets) do
                if guid == srcGUID then srcPos = i; break end
            end

            -- tgtPos was found before source removal; if source is before target,
            -- removal shifts target left by one, so adjust to land before target.
            local adjPos = tgtPos
            if srcPos and srcPos < tgtPos then adjPos = tgtPos - 1 end
            if adjPos < 1 then adjPos = 1 end

            petGroups:ReorderPetInGroup(tgtGroup, srcGUID, adjPos)
        else
            petGroups:MovePetToGroup(srcGUID, tgtGroup, nil)
        end

        self:EndDrag()
        PSM._renderCache = nil

        local scrollFrame = PSM.state.scrollFrame
        local scrollBar   = scrollFrame and scrollFrame.ScrollBar
        local content     = PSM.state.content
        local pct         = 0
        if scrollBar and content then
            local maxScroll = math.max(0, content:GetHeight() - scrollFrame:GetHeight())
            if maxScroll > 0 then pct = scrollBar:GetValue() / maxScroll end
        end

        PSM.C_Timer.After(0.1, function()
            if PSM.UI.RenderPanel then
                PSM.UI:RenderPanel(true)
            elseif PSM.UI._RenderPanelImmediate then
                PSM.UI:_RenderPanelImmediate(true)
            end
            if scrollBar and content and scrollFrame then
                PSM.C_Timer.After(0.05, function()
                    local maxScroll = math.max(0, content:GetHeight() - scrollFrame:GetHeight())
                    if maxScroll > 0 then scrollBar:SetValue(maxScroll * pct) end
                end)
            end
        end)
        return true
    end

    -- Stable swap path
    if not targetPet or s.sourcePet.slotID == targetPet.slotID then
        self:EndDrag(); return false
    end

    local success = PSM.Reorder:SwapPetSlots(s.sourcePet.slotID, targetPet.slotID, true)
    self:EndDrag()

    PSM._scrollLockCount = (PSM._scrollLockCount or 0) + 1
    PSM._scrollLock = true

    PSM.C_Timer.After(0.35, function()
        if PSM.state.isStableOpen then PSM.Data:CollectStablePets() end
        PSM._renderCache = nil
        if PSM._renderDebounceTimer then
            PSM._renderDebounceTimer:Cancel()
            PSM._renderDebounceTimer = nil
        end
        if PSM.UI and PSM.UI._RenderPanelImmediate then
            PSM.UI:_RenderPanelImmediate(true)
        end
        PSM.C_Timer.After(2.0, function()
            PSM._scrollLockCount = PSM._scrollLockCount - 1
            if PSM._scrollLockCount <= 0 then
                PSM._scrollLockCount = 0
                PSM._scrollLock = false
            end
        end)
    end)

    return success
end

function DD:SetupRowDragDrop(row, pet, allowOutsideStable)
    if not row then return end
    row.dragDropPet = pet
    if allowOutsideStable == nil then
        row.__allowDragOutsideStable = row.__allowDragOutsideStable or false
    else
        row.__allowDragOutsideStable = allowOutsideStable
    end
    row:EnableMouse(true)

    row:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local allowOutside = self.__allowDragOutsideStable
        if not PSM.state.isStableOpen and not allowOutside then return end
        if not IsShiftKeyDown() and not IsControlKeyDown() then return end
        local focus = GetMouseFocus and GetMouseFocus()
        if focus and focus ~= self and focus:GetParent() == self
                and focus:GetObjectType() == "Button" then return end
        PSM.DragDrop:StartDrag(self, self.dragDropPet, allowOutside)
    end)

    row:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        if PSM.DragDrop.state.isDragging then
            if PSM.DragDrop.state.sourceAllowOutsideStable then
                local tgt    = PSM.DragDrop.state.targetRow
                local tgtPet = tgt and tgt.dragDropPet or nil
                PSM.DragDrop:CompleteDrop(tgt, tgtPet)
            else
                if PSM.DragDrop.state.targetRow and PSM.DragDrop.state.targetRow.dragDropPet then
                    PSM.DragDrop:CompleteDrop(PSM.DragDrop.state.targetRow, PSM.DragDrop.state.targetRow.dragDropPet)
                else
                    PSM.DragDrop:EndDrag()
                end
            end
        end
    end)

    row:SetScript("OnEnter", function(self)
        if PSM.DragDrop.state.isDragging then
            PSM.DragDrop:OnEnterTarget(self, self.dragDropPet)
        end
    end)

    row:SetScript("OnLeave", function(self)
        if PSM.DragDrop.state.isDragging then
            PSM.DragDrop:OnLeaveTarget(self)
        end
    end)
end

function DD:SetupModelDragDrop(model, pet, parentRow, allowOutsideStable)
    if not model then return end
    model.dragDropPet       = pet
    model.dragDropParentRow = parentRow
    if allowOutsideStable == nil then
        model.__allowDragOutsideStable = model.__allowDragOutsideStable
            or (parentRow and parentRow.__allowDragOutsideStable) or false
    else
        model.__allowDragOutsideStable = allowOutsideStable
    end

    local orig = {
        OnMouseDown = model:GetScript("OnMouseDown"),
        OnMouseUp   = model:GetScript("OnMouseUp"),
        OnEnter     = model:GetScript("OnEnter"),
        OnLeave     = model:GetScript("OnLeave"),
    }

    model:SetScript("OnMouseDown", function(self, button)
        local allowOutside = self.__allowDragOutsideStable
        if button == "LeftButton" and (PSM.state.isStableOpen or allowOutside)
                and (IsShiftKeyDown() or IsControlKeyDown()) and self.dragDropPet then
            if PSM.DragDrop:StartDrag(self.dragDropParentRow or self:GetParent(),
                    self.dragDropPet, allowOutside) then
                return
            end
        end
        if orig.OnMouseDown then orig.OnMouseDown(self, button) end
    end)

    model:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and PSM.DragDrop.state.isDragging then
            if PSM.DragDrop.state.sourceAllowOutsideStable then
                local tgt    = PSM.DragDrop.state.targetRow
                local tgtPet = tgt and tgt.dragDropPet or nil
                PSM.DragDrop:CompleteDrop(tgt, tgtPet)
            else
                if PSM.DragDrop.state.targetRow and PSM.DragDrop.state.targetRow.dragDropPet then
                    PSM.DragDrop:CompleteDrop(PSM.DragDrop.state.targetRow, PSM.DragDrop.state.targetRow.dragDropPet)
                else
                    PSM.DragDrop:EndDrag()
                end
            end
            return
        end
        if orig.OnMouseUp then orig.OnMouseUp(self, button) end
    end)

    model:SetScript("OnEnter", function(self)
        if PSM.DragDrop.state.isDragging then
            PSM.DragDrop:OnEnterTarget(self.dragDropParentRow or self:GetParent(), self.dragDropPet)
        end
        if orig.OnEnter then orig.OnEnter(self) end
    end)

    model:SetScript("OnLeave", function(self)
        if PSM.DragDrop.state.isDragging then
            PSM.DragDrop:OnLeaveTarget(self.dragDropParentRow or self:GetParent())
        end
        if orig.OnLeave then orig.OnLeave(self) end
    end)
end

-- Per-frame position update & mouse-release detection
local updateFrame = CreateFrame("Frame")
updateFrame:SetScript("OnUpdate", function()
    if not DD.state.isDragging then return end

    DD:UpdateDragFramePosition()

    local focus = GetMouseFoci and GetMouseFoci() or GetMouseFocus and GetMouseFocus()
    if type(focus) == "table" then focus = focus[1] end

    if focus and focus ~= DD.state.lastFocus then
        -- Clean up previous target before switching to new one
        local prevTarget = DD.state.targetRow
        if prevTarget then
            ResetRowColor(prevTarget, prevTarget._savedBackdrop)
            SetDropIndicator(prevTarget, false)
            prevTarget._savedBackdrop = nil
        end

        local targetRow = nil
        if focus.groupId or focus.isGroupHeader then
            targetRow = focus
        elseif focus.GetParent and focus:GetParent()
                and (focus:GetParent().groupId or focus:GetParent().isGroupHeader) then
            targetRow = focus:GetParent()
        elseif focus.dragDropPet then
            targetRow = focus
        elseif focus.GetParent and focus:GetParent() and focus:GetParent().dragDropPet then
            targetRow = focus:GetParent()
        end

        DD.state.targetRow = targetRow
        DD.state.targetPet = targetRow and targetRow.dragDropPet or nil
        if targetRow then
            if DD.state.sourceAllowOutsideStable then
                local tgtGroup  = targetRow.groupId
                local sameGroup = tgtGroup and (tgtGroup == DD.state.sourceGroupId)
                if targetRow.GetBackdropColor and not targetRow.isGroupHeader and not targetRow._savedBackdrop then
                    targetRow._savedBackdrop = {targetRow:GetBackdropColor()}
                end
                local isValid   = tgtGroup ~= nil or targetRow.isGroupHeader == true or sameGroup
                SetRowColor(targetRow, isValid and COLOR.TARGET or COLOR.INVALID)
                if isValid and not targetRow.isGroupHeader then SetDropIndicator(targetRow, true) end
            else
                if targetRow.dragDropPet then
                    DD:OnEnterTarget(targetRow, targetRow.dragDropPet)
                end
            end
        end
        DD.state.lastFocus = focus
    end

    if not IsMouseButtonDown("LeftButton") then
        local tgt    = DD.state.targetRow
        local tgtPet = tgt and tgt.dragDropPet or nil
        DD:CompleteDrop(tgt, tgtPet)
    end
end)

function DD:GetDragInterceptor()
    if self._interceptor then return self._interceptor end
    local f = CreateFrame("Frame", "PSMDragInterceptor", UIParent)
    f:SetAllPoints(UIParent)
    f:EnableMouse(false)
    f:SetFrameStrata("BACKGROUND")
    f:Hide()
    self._interceptor = f
    return f
end

------------------------------------------------
-- TEAM SLOT DRAG & DROP
------------------------------------------------

function DD:SetupTeamSlotDragDrop(modelFrame, slotNum, teamId, teamData)
    if not teamData.slots[slotNum] then return end
    modelFrame:EnableMouse(true)

    modelFrame:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end

        local ts        = DD.teamState
        ts.isDragging   = true
        ts.sourceSlot   = slotNum
        ts.sourceTeamId = teamId
        ts.sourceRow    = self:GetParent():GetParent()

        local df  = GetTeamDragFrame()
        local pet = teamData.slots[slotNum]
        if pet.displayID and pet.displayID > 0 then
            SetPortraitTextureFromCreatureDisplayID(df.portrait, pet.displayID)
            df.portrait:SetTexCoord(1, 0, 0, 1)
            df.portrait:AddMaskTexture(df.mask)
            df.portrait:Show()
        else
            df.portrait:Hide()
        end

        df:ClearAllPoints()
        df:SetPoint("CENTER", self, "CENTER", 0, 0)
        df:StartMoving()
        df:Show()

        DD:HighlightTeamDropTargets(teamId, slotNum)
        self:SetAlpha(0.3)
    end)

    modelFrame:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" or not DD.teamState.isDragging then return end
        local dropTarget = DD:GetTeamDropTargetAtCursor()
        if dropTarget then
            DD:SwapTeamSlots(teamId, DD.teamState.sourceSlot, dropTarget.slotNum)
        end
        DD:CancelTeamDrag()
    end)
end

function DD:HighlightTeamDropTargets(teamId, excludeSlot)
    local row = self:_GetTeamRow(teamId)
    if not row then return end
    for slot = 1, 6 do
        if slot ~= excludeSlot and row.petBorders[slot] then
            row.petBorders[slot]:SetVertexColor(unpack(PSM.Config.COLORS.DROP_TARGET_BORDER))
        end
    end
end

function DD:ClearTeamDropTargetHighlights()
    local panel = PSM.state.teamsPanel
    if not panel or not panel.teamRows then return end
    for _, row in ipairs(panel.teamRows) do
        if row and row:IsShown() and row.petBorders then
            for slot = 1, 6 do
                if row.petBorders[slot] then
                    row.petBorders[slot]:SetVertexColor(1, 1, 1)
                end
            end
        end
    end
end

function DD:GetTeamDropTargetAtCursor()
    local ts = DD.teamState
    if not ts.sourceTeamId then return nil end
    local row = self:_GetTeamRow(ts.sourceTeamId)
    if not row or not row.petIconContainers then return nil end
    for slot = 1, 6 do
        if slot ~= ts.sourceSlot then
            local container = row.petIconContainers[slot]
            if container and container:IsMouseOver() then
                return { slotNum = slot, teamId = ts.sourceTeamId }
            end
        end
    end
    return nil
end

function DD:CancelTeamDrag()
    local ts = DD.teamState
    if ts.dragFrame then
        ts.dragFrame:Hide()
        ts.dragFrame:StopMovingOrSizing()
    end

    local row = self:_GetTeamRow(ts.sourceTeamId)
    if row and row.petIconContainers and ts.sourceSlot then
        local c = row.petIconContainers[ts.sourceSlot]
        if c then c:SetAlpha(1) end
    end

    DD:ClearTeamDropTargetHighlights()

    ts.isDragging   = false
    ts.sourceSlot   = nil
    ts.sourceTeamId = nil
    ts.sourceRow    = nil
end

function DD:SwapTeamSlots(teamId, slot1, slot2)
    if not teamId or not slot1 or not slot2 or slot1 == slot2 then return false end
    local team = PSM.Teams:GetTeamById(teamId)
    if not team then return false end
    team.slots[slot1], team.slots[slot2] = team.slots[slot2], team.slots[slot1]
    team.modifiedAt = time()
    PSM.TeamsPanel:RefreshTeamsList()
    return true
end

function DD:_GetTeamRow(teamId)
    local panel = PSM.state.teamsPanel
    if not panel or not panel.teamRows then return nil end
    local teams = PSM.Teams:GetTeams()
    for i, team in ipairs(teams) do
        if team.id == teamId then return panel.teamRows[i] end
    end
    return nil
end