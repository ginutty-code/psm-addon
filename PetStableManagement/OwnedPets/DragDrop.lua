-- OwnedPets/DragDrop.lua
-- Drag and drop functionality for reordering pets in the Owned Pets panel

local _, ns = ...
ns.DragDrop = ns.DragDrop or {}

local DD = ns.DragDrop

-- Colors
local COLOR = {
    SOURCE  = {0.2, 0.6, 1.0, 0.4},
    TARGET  = {0.2, 1.0, 0.2, 0.4},
    INVALID = {1.0, 0.2, 0.2, 0.4},
}

local ICON_SIZE = 55

-- The drag frame's ring and its slot caption are deliberately the same yellow -- they
-- read as one object being carried. Not Theme.COLOR.GOLD, which is dimmer (1, 0.82, 0)
-- and is the addon's *text* accent; this is a full-intensity highlight.
local DRAG_HIGHLIGHT = { 1, 1, 0, 1 }

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

-- Remember a row's own colours before a highlight overwrites them, so they can be put
-- back exactly. Headers restore from this too -- they used to be reset to hard-coded
-- literals that were a copy of GroupedView's header palette, in a different file, with
-- nothing keeping the two in step.
local function SaveRowColors(row)
    if not row or not row.GetBackdropColor or row._savedBackdrop then return end
    row._savedBackdrop = { row:GetBackdropColor() }
    if row.GetBackdropBorderColor then
        row._savedBorder = { row:GetBackdropBorderColor() }
    end
end

local function SetRowColor(row, color)
    if not row or not row.SetBackdropColor then return end
    if row.isGroupHeader then
        -- A header means "this whole group", so the whole header lights up. It used to
        -- tint only the border, at the fill's 0.4 alpha -- a translucent wash over an
        -- 8px edge, which read as nothing happening at all. The fill carries the tint
        -- now and the border takes it at full opacity to outline the target.
        row:SetBackdropColor(color[1], color[2], color[3], color[4] or 1)
        row:SetBackdropBorderColor(color[1], color[2], color[3], 1)
    else
        row:SetBackdropColor(unpack(color))
    end
end

local function ResetRowColor(row, savedBackdrop)
    if not row or not row.SetBackdropColor then return end
    savedBackdrop = savedBackdrop or row._savedBackdrop
    if savedBackdrop then row:SetBackdropColor(unpack(savedBackdrop)) end
    if row._savedBorder then row:SetBackdropBorderColor(unpack(row._savedBorder)) end
end

-- Put a row back the way it was and forget it. One helper because the three cleanup
-- sites each used to restore and clear by hand, and adding the border to the saved set
-- meant finding all three again.
local function RestoreRowColors(row, savedBackdrop)
    if not row then return end
    ResetRowColor(row, savedBackdrop)
    row._savedBackdrop = nil
    row._savedBorder   = nil
end

local function SetDropIndicator(row, show)
    -- Only show drop indicator in grouped view (where allowOutsideStable is true)
    if ns.state.panelViewMode ~= "grouped" then return end
    if not row then return end
    if show then
        if not row._dropIndicator then
            row._dropIndicator = ns.Widgets.Texture(row, {
                layer = "OVERLAY",
                width = 3,
                color = { 0.2, 1.0, 0.2, 1 },
                point = {
                    { "TOPLEFT",    row, "TOPLEFT",    0, 0 },
                    { "BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0 },
                },
            })
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

    local Widgets = ns.Widgets

    -- BORDER_ONLY with a 12px edge: a ring around whatever is being dragged, with the
    -- model or icon showing through. The preset's insets are inert here because there
    -- is no bgFile to inset.
    local f = Widgets.Frame(UIParent, {
        name              = "PSMDragFrame",
        size              = { 80, 80 },
        strata            = "TOOLTIP",
        level             = 100,
        hidden            = true,
        backdrop          = "BORDER_ONLY",
        backdropOverrides = { edgeSize = 12 },
        borderColor       = DRAG_HIGHLIGHT,
    })

    f.model = Widgets.Frame(f, { frameType = "PlayerModel", allPoints = true })
    f.model:SetRotation(math.pi * 2)

    f.icon = Widgets.Texture(f, { layer = "ARTWORK", allPoints = true, hidden = true })

    f.slotText = Widgets.Label(f, {
        fontSize = ns.Theme.SIZE.LABEL,
        outline  = true,
        color    = DRAG_HIGHLIGHT,
        point    = { "BOTTOM", f, "BOTTOM", 0, 2 },
    })

    DD.state.dragFrame = f
    return f
end

local function GetTeamDragFrame()
    if DD.teamState.dragFrame then return DD.teamState.dragFrame end

    local Widgets = ns.Widgets

    local f = Widgets.Frame(UIParent, {
        size   = { ICON_SIZE + 45, ICON_SIZE + 45 },
        strata = "HIGH",
        level  = 1000,
        hidden = true,
    })
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)

    f.portrait = Widgets.Texture(f, {
        layer    = "BACKGROUND",
        sublayer = 1,
        size     = { ICON_SIZE, ICON_SIZE },
        point    = { "CENTER", f, "CENTER", 0, 0 },
    })

    f.mask = Widgets.MaskTexture(f, {
        texture = "Interface\\CharacterFrame\\TempPortraitAlphaMask",
        size    = { ICON_SIZE, ICON_SIZE },
        point   = { "CENTER", f, "CENTER", 0, 0 },
    })
    f.portrait:AddMaskTexture(f.mask)

    f.border = Widgets.Texture(f, {
        layer     = "BORDER",
        atlas     = "footer_inactive-ring",
        allPoints = true,
    })

    DD.teamState.dragFrame = f
    return f
end

------------------------------------------------
-- PET ROW DRAG & DROP
------------------------------------------------

function DD:StartDrag(row, pet, allowOutsideStable)
    if not row or not pet then return end
    if not ns.state.isStableOpen and not allowOutsideStable then
        print(ns.L("Must be at stable master to reorder pets"))
        return false
    end

    local s = DD.state
    s.isDragging               = true
    s.sourceRow                = row
    s.sourcePet                = pet
    s.sourceAllowOutsideStable = allowOutsideStable
    s.sourceGroupId            = row.groupId

    -- Capture the source group's pet order at drag start for position fallback
    if row.groupId and ns.PetGroups then
        local group = ns.PetGroups:GetGroupById(row.groupId)
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
    df.slotText:SetText(ns.L("Slot %s", pet.slotID or "?"))
    df:Show()
    self:UpdateDragFramePosition()

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

    SaveRowColors(row)

    local isValid
    if s.sourceAllowOutsideStable then
        local tgtGroup  = row.groupId
        local sameGroup = tgtGroup and (tgtGroup == s.sourceGroupId)
        isValid = tgtGroup ~= nil or row.isGroupHeader == true or sameGroup
    else
        isValid = ns.state.isStableOpen and pet and pet.slotID
    end

    SetRowColor(row, isValid and COLOR.TARGET or COLOR.INVALID)
    if isValid and not row.isGroupHeader then SetDropIndicator(row, true) end
end

function DD:OnLeaveTarget(row)
    local s = DD.state
    if not s.isDragging or not row then return end
    RestoreRowColors(row)
    SetDropIndicator(row, false)
    if s.targetRow == row then s.targetRow = nil end
end

function DD:EndDrag()
    local s = DD.state
    if s.dragFrame then s.dragFrame:Hide() end
    RestoreRowColors(s.sourceRow, s.originalBackdrop)
    if s.targetRow then
        RestoreRowColors(s.targetRow)
        SetDropIndicator(s.targetRow, false)
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
end

-- A group's stored pet order, with any visible-but-untracked pets seeded in first.
--
-- Only "ungrouped" needs the seeding: a pet is implicitly ungrouped until something
-- explicitly files it, so the stored list can be missing pets that are plainly on
-- screen -- and an insertion index computed against a partial list lands in the wrong
-- place. Named groups always track their own members, so the seed pass finds nothing
-- and costs a loop.
local function StoredOrderForGroup(groupId)
    local petGroups  = ns.PetGroups
    local group      = petGroups:GetGroupById(groupId)
    local storedPets = group and group.pets or {}

    local tracked = {}
    for _, guid in ipairs(storedPets) do tracked[guid] = true end

    if ns.state.groupedViewRows then
        local toSeed = {}
        for _, r in ipairs(ns.state.groupedViewRows) do
            if r:IsShown() and r.groupId == groupId
                    and r.dragDropPet and r.dragDropPet.guid
                    and not tracked[r.dragDropPet.guid] then
                table.insert(toSeed, r.dragDropPet.guid)
            end
        end
        if #toSeed > 0 then
            -- One batched call rather than one Save() per pet.
            petGroups:SeedUngroupedPets(toSeed)
            group      = petGroups:GetGroupById(groupId)
            storedPets = group and group.pets or {}
        end
    end

    return storedPets
end

-- Index of `guid` in `list`, or nil.
local function IndexOf(list, guid)
    for i, entry in ipairs(list) do
        if entry == guid then return i end
    end
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

        local petGroups = ns.PetGroups

        local storedPets = StoredOrderForGroup(tgtGroup)

        -- Where the drop indicator was pointing. nil when the drop landed on a group
        -- header rather than a pet, which means "append to this group".
        local tgtGUID = s.targetPet and s.targetPet.guid
        local tgtPos  = tgtGUID and IndexOf(storedPets, tgtGUID) or nil

        if sameGroup then
            -- Bails on an unknown target rather than on a missing one: the old guard
            -- checked only that a target pet existed, so a pet that was somehow not in
            -- storage produced tgtPos = nil and then compared a number against nil.
            if not tgtPos then self:EndDrag(); return false end

            -- tgtPos was measured before the source is removed; if the source sits
            -- before the target, that removal shifts the target left by one, so
            -- subtract to land *before* the target rather than after it.
            local srcPos = IndexOf(storedPets, srcGUID)
            local adjPos = tgtPos
            if srcPos and srcPos < tgtPos then adjPos = tgtPos - 1 end
            if adjPos < 1 then adjPos = 1 end

            petGroups:ReorderPetInGroup(tgtGroup, srcGUID, adjPos)
        else
            -- Insert where the indicator promised, instead of appending. No index
            -- adjustment here: the source is leaving a *different* group, so removing
            -- it does not shift this group's positions.
            --
            -- MovePetToGroup has always taken a position; this path used to pass an
            -- explicit nil, so every cross-group drop landed at the end while the
            -- highlight said otherwise.
            petGroups:MovePetToGroup(srcGUID, tgtGroup, tgtPos)
        end

        self:EndDrag()

        local scrollFrame = ns.state.scrollFrame
        local scrollBar   = scrollFrame and scrollFrame.ScrollBar
        local content     = ns.state.content
        local pct         = 0
        if scrollBar and content then
            local maxScroll = math.max(0, content:GetHeight() - scrollFrame:GetHeight())
            if maxScroll > 0 then pct = scrollBar:GetValue() / maxScroll end
        end

        ns.C_Timer.After(0.1, function()
            if ns.UI.RenderPanel then
                ns.UI:RenderPanel(true)
            elseif ns.UI._RenderPanelImmediate then
                ns.UI:_RenderPanelImmediate(true)
            end
            if scrollBar and content and scrollFrame then
                ns.C_Timer.After(0.05, function()
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

    local success = ns.Reorder:SwapPetSlots(s.sourcePet.slotID, targetPet.slotID, true)
    self:EndDrag()

    ns._scrollLockCount = (ns._scrollLockCount or 0) + 1
    ns._scrollLock = true

    -- Collect *then* render, and both here rather than in SwapPetSlots, because this path
    -- passed `skipUpdate` to own the timing. SetPetSlot is asynchronous, which is what the
    -- delay is for -- collecting immediately would read the pre-swap order.
    --
    -- The same pair lives in Reorder:SwapPetSlots for the arrow buttons. Two copies, kept
    -- deliberately: merging them means splitting collection and render across two timers
    -- whose ordering would then have to be maintained by hand -- trading a duplicate for a
    -- pair of constants that must agree, which is the worse of the two problems.
    ns.C_Timer.After(0.35, function()
        if ns.state.isStableOpen then ns.Data:CollectStablePets() end
        if ns._renderDebounceTimer then
            ns._renderDebounceTimer:Cancel()
            ns._renderDebounceTimer = nil
        end
        if ns.UI and ns.UI._RenderPanelImmediate then
            ns.UI:_RenderPanelImmediate(true)
        end
        ns.C_Timer.After(2.0, function()
            ns._scrollLockCount = ns._scrollLockCount - 1
            if ns._scrollLockCount <= 0 then
                ns._scrollLockCount = 0
                ns._scrollLock = false
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
        if not ns.state.isStableOpen and not allowOutside then return end
        if not IsShiftKeyDown() and not IsControlKeyDown() then return end
        local focus = GetMouseFoci and GetMouseFoci() or GetMouseFocus and GetMouseFocus()
        if type(focus) == "table" then focus = focus[1] end
        if focus and focus ~= self and focus:GetParent() == self
                and focus:GetObjectType() == "Button" then return end
        ns.DragDrop:StartDrag(self, self.dragDropPet, allowOutside)
    end)

    row:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        if ns.DragDrop.state.isDragging then
            if ns.DragDrop.state.sourceAllowOutsideStable then
                local tgt    = ns.DragDrop.state.targetRow
                local tgtPet = tgt and tgt.dragDropPet or nil
                ns.DragDrop:CompleteDrop(tgt, tgtPet)
            else
                if ns.DragDrop.state.targetRow and ns.DragDrop.state.targetRow.dragDropPet then
                    ns.DragDrop:CompleteDrop(ns.DragDrop.state.targetRow, ns.DragDrop.state.targetRow.dragDropPet)
                else
                    ns.DragDrop:EndDrag()
                end
            end
        end
    end)

    row:SetScript("OnEnter", function(self)
        if ns.DragDrop.state.isDragging then
            ns.DragDrop:OnEnterTarget(self, self.dragDropPet)
        end
    end)

    row:SetScript("OnLeave", function(self)
        if ns.DragDrop.state.isDragging then
            ns.DragDrop:OnLeaveTarget(self)
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

    -- Wire once: the handlers below read pet/parent live off `self`, so re-wrapping
    -- GetScript()'s current handler on every render just grew the chain forever.
    if model.__dragDropWired then return end
    model.__dragDropWired = true

    local orig = {
        OnMouseDown = model:GetScript("OnMouseDown"),
        OnMouseUp   = model:GetScript("OnMouseUp"),
        OnEnter     = model:GetScript("OnEnter"),
        OnLeave     = model:GetScript("OnLeave"),
    }

    model:SetScript("OnMouseDown", function(self, button)
        local allowOutside = self.__allowDragOutsideStable
        if button == "LeftButton" and (ns.state.isStableOpen or allowOutside)
                and (IsShiftKeyDown() or IsControlKeyDown()) and self.dragDropPet then
            if ns.DragDrop:StartDrag(self.dragDropParentRow or self:GetParent(),
                    self.dragDropPet, allowOutside) then
                return
            end
        end
        if orig.OnMouseDown then orig.OnMouseDown(self, button) end
    end)

    model:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and ns.DragDrop.state.isDragging then
            if ns.DragDrop.state.sourceAllowOutsideStable then
                local tgt    = ns.DragDrop.state.targetRow
                local tgtPet = tgt and tgt.dragDropPet or nil
                ns.DragDrop:CompleteDrop(tgt, tgtPet)
            else
                if ns.DragDrop.state.targetRow and ns.DragDrop.state.targetRow.dragDropPet then
                    ns.DragDrop:CompleteDrop(ns.DragDrop.state.targetRow, ns.DragDrop.state.targetRow.dragDropPet)
                else
                    ns.DragDrop:EndDrag()
                end
            end
            return
        end
        if orig.OnMouseUp then orig.OnMouseUp(self, button) end
    end)

    model:SetScript("OnEnter", function(self)
        if ns.DragDrop.state.isDragging then
            ns.DragDrop:OnEnterTarget(self.dragDropParentRow or self:GetParent(), self.dragDropPet)
        end
        if orig.OnEnter then orig.OnEnter(self) end
    end)

    model:SetScript("OnLeave", function(self)
        if ns.DragDrop.state.isDragging then
            ns.DragDrop:OnLeaveTarget(self.dragDropParentRow or self:GetParent())
        end
        if orig.OnLeave then orig.OnLeave(self) end
    end)
end

-- Per-frame position update & mouse-release detection. Parentless and invisible: a
-- handler holder, not a widget, so it stays out of the kit. PSM.CreateFrame is Core's
-- alias, which the headless tests can stub.
local updateFrame = ns.CreateFrame("Frame")
updateFrame:SetScript("OnUpdate", function()
    if not DD.state.isDragging then return end

    DD:UpdateDragFramePosition()

    local focus = GetMouseFoci and GetMouseFoci() or GetMouseFocus and GetMouseFocus()
    if type(focus) == "table" then focus = focus[1] end

    if focus and focus ~= DD.state.lastFocus then
        -- Clean up previous target before switching to new one
        local prevTarget = DD.state.targetRow
        if prevTarget then
            RestoreRowColors(prevTarget)
            SetDropIndicator(prevTarget, false)
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
                SaveRowColors(targetRow)
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

-- `DD:GetDragInterceptor` used to live here: a full-screen frame shown for the duration
-- of a drag and hidden after. It was created with EnableMouse(false), no textures and
-- BACKGROUND strata, so it could intercept nothing and draw nothing -- the name asserted
-- a mechanism the construction ruled out. Removed along with its two call sites.

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
            row.petBorders[slot]:SetVertexColor(unpack(ns.Config.COLORS.DROP_TARGET_BORDER))
        end
    end
end

function DD:ClearTeamDropTargetHighlights()
    local panel = ns.state.teamsPanel
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
    local team = ns.Teams:GetTeamById(teamId)
    if not team then return false end
    team.slots[slot1], team.slots[slot2] = team.slots[slot2], team.slots[slot1]
    team.modifiedAt = time()
    ns.TeamsPanel:RefreshTeamsList()
    return true
end

function DD:_GetTeamRow(teamId)
    local panel = ns.state.teamsPanel
    if not panel or not panel.teamRows then return nil end
    local teams = ns.Teams:GetTeams()
    for i, team in ipairs(teams) do
        if team.id == teamId then return panel.teamRows[i] end
    end
    return nil
end