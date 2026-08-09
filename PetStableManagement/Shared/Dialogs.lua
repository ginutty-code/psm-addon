-- Dialogs.lua
-- Reusable dialog windows for PetStableManagement

local addonName = "PetStableManagement"

_G.PSM = _G.PSM or {}
local PSM = _G.PSM

PSM.TeamDialogs = PSM.TeamDialogs or {}
PSM.TeamDialogs.activeDialog = nil

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------



--------------------------------------------------------------------------------
-- BASE DIALOG CREATION
--------------------------------------------------------------------------------

-- Creates a styled dialog frame. Pass resizable=true for a resize handle.
local function CreateBaseDialog(name, width, height, title, resizable)
    if PSM.TeamDialogs.activeDialog then
        PSM.TeamDialogs.activeDialog:Hide()
    end

    local d = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    d:SetSize(width or 350, height or 150)
    d:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    d:SetFrameStrata("DIALOG")
    d:SetFrameLevel(100)
    d:SetToplevel(true)
    d:SetClampedToScreen(true)
    d:SetMovable(true)
    d:SetResizable(resizable or false)
    d:EnableMouse(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving)
    d:SetScript("OnDragStop",  d.StopMovingOrSizing)

    d:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = {left=4, right=4, top=4, bottom=4},
    })
    d:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    d:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

    d.title = d:CreateFontString(nil, "OVERLAY")
    d.title:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    d.title:SetPoint("TOP", 0, -15)
    d.title:SetText(title or "Dialog")
    d.title:SetTextColor(1, 0.82, 0)

    d.closeButton = CreateFrame("Button", nil, d, "UIPanelCloseButton")
    d.closeButton:SetPoint("TOPRIGHT", -2, -2)
    d.closeButton:SetSize(24, 24)
    d.closeButton:SetScript("OnClick", function()
        d:Hide()
        if d.onCancel then d.onCancel() end
    end)

    if resizable then
        local rh = CreateFrame("Button", nil, d)
        rh:SetSize(16, 16)
        rh:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -4, 4)
        rh:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        rh:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        rh:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
        rh:EnableMouse(true)
        rh:SetScript("OnMouseDown", function(_, btn) if btn == "LeftButton" then d:StartSizing() end end)
        rh:SetScript("OnMouseUp",   d.StopMovingOrSizing)
        d.resizeHandle = rh
    end

    d:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:Hide()
            if self.onCancel then self.onCancel() end
            self:SetPropagateKeyboardInput(false)
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    d:EnableKeyboard(true)

    PSM.UI:ApplyElvUISkin(d, "frame")
    PSM.UI:ApplyElvUISkin(d.closeButton, "closebutton")

    PSM.TeamDialogs.activeDialog = d
    d:SetScript("OnHide", function(self)
        if PSM.TeamDialogs.activeDialog == self then
            PSM.TeamDialogs.activeDialog = nil
        end
    end)

    return d
end

local function CreateDialogButton(parent, text, width, height)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 100, height or 25)
    b:SetText(text)
    b:SetNormalFontObject("GameFontNormal")
    PSM.UI:ApplyElvUISkin(b, "button")
    return b
end

local function CreateDialogEditBox(parent, width, height)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(width or 250, height or 25)
    e:SetAutoFocus(false)
    e:SetMaxLetters(50)
    PSM.UI:ApplyElvUISkin(e, "editbox")
    return e
end

--------------------------------------------------------------------------------
-- NAME INPUT DIALOG  (used by several callers)
--------------------------------------------------------------------------------

function PSM.TeamDialogs:ShowNameInputDialog(options)
    options = options or {}

    local d = CreateBaseDialog("PSMTeamNameDialog", 350, 140, options.title or "Enter Team Name")

    d.description = d:CreateFontString(nil, "OVERLAY")
    d.description:SetFont("Fonts\\FRIZQT__.TTF", 11)
    d.description:SetPoint("TOP", d.title, "BOTTOM", 0, -10)
    d.description:SetText(options.description or "Enter a name for your pet team:")
    d.description:SetTextColor(1, 1, 1)

    d.editBox = CreateDialogEditBox(d, 140, 25)
    d.editBox:SetPoint("TOP", d.description, "BOTTOM", 0, -10)
    d.editBox:SetText(options.defaultText or "")
    d.editBox:SetFocus()
    if options.highlightText then d.editBox:HighlightText() end

    local bc = CreateFrame("Frame", nil, d)
    bc:SetSize(220, 30)
    bc:SetPoint("BOTTOM", 0, 15)

    d.confirmButton = CreateDialogButton(bc, options.confirmText or "Save", 100, 25)
    d.confirmButton:SetPoint("LEFT", 0, 0)
    d.confirmButton:SetScript("OnClick", function()
        local name = d.editBox:GetText()
        if name and name ~= "" then
            d:Hide()
            if options.onConfirm then options.onConfirm(name) end
        else
            d.editBox:SetFocus()
        end
    end)

    d.cancelButton = CreateDialogButton(bc, "Cancel", 100, 25)
    d.cancelButton:SetPoint("LEFT", d.confirmButton, "RIGHT", 10, 0)
    d.cancelButton:SetScript("OnClick", function()
        d:Hide()
        if options.onCancel then options.onCancel() end
    end)

    d.onCancel = options.onCancel
    d.editBox:SetScript("OnEnterPressed", function() d.confirmButton:Click() end)
    d.editBox:SetScript("OnEscapePressed", function() d.cancelButton:Click() end)

    d:Show()
    return d
end

--------------------------------------------------------------------------------
-- GROUP NAME DIALOG  (create / rename share the same UI, differ only in labels)
--------------------------------------------------------------------------------

-- @param options.mode  "create" | "rename"  (default "create")
-- @param options.currentName  pre-filled text  (for rename)
-- @param options.suggestedName  pre-filled text (for create)
-- @param options.onConfirm  function(name)
-- @param options.onCancel   function()
function PSM.TeamDialogs:ShowGroupNameDialog(options)
    options = options or {}
    local isRename = options.mode == "rename"

    return self:ShowNameInputDialog({
        title       = isRename and "Rename Group"   or "Create New Group",
        description = isRename and "Enter a new name for the group:" or "Enter a name for the new group:",
        defaultText = isRename and (options.currentName or "") or (options.suggestedName or "New Group"),
        confirmText = isRename and "Rename" or "Create",
        highlightText = true,
        onConfirm   = options.onConfirm,
        onCancel    = options.onCancel,
    })
end

-- Convenience shims kept for callers that use the old names
function PSM.TeamDialogs:ShowCreateGroupDialog(options)
    options = options or {}
    options.mode = "create"
    return self:ShowGroupNameDialog(options)
end

function PSM.TeamDialogs:ShowRenameGroupDialog(options)
    options = options or {}
    options.mode = "rename"
    return self:ShowGroupNameDialog(options)
end

--------------------------------------------------------------------------------
-- CONFIRMATION DIALOG
--------------------------------------------------------------------------------

function PSM.TeamDialogs:ShowConfirmDialog(options)
    options = options or {}

    local d = CreateBaseDialog("PSMTeamConfirmDialog", 350, 130, options.title or "Confirm")

    d.message = d:CreateFontString(nil, "OVERLAY")
    d.message:SetFont("Fonts\\FRIZQT__.TTF", 11)
    d.message:SetPoint("TOP", d.title, "BOTTOM", 0, -15)
    d.message:SetWidth(300)
    d.message:SetText(options.message or "Are you sure?")
    d.message:SetTextColor(1, 1, 1)
    d.message:SetJustifyH("CENTER")

    local bc = CreateFrame("Frame", nil, d)
    bc:SetSize(220, 30)
    bc:SetPoint("BOTTOM", 0, 5)

    d.confirmButton = CreateDialogButton(bc, options.confirmText or "Yes", 100, 25)
    d.confirmButton:SetPoint("LEFT", 0, 0)
    d.confirmButton:SetScript("OnClick", function()
        d:Hide()
        if options.onConfirm then options.onConfirm() end
    end)

    d.cancelButton = CreateDialogButton(bc, options.cancelText or "No", 100, 25)
    d.cancelButton:SetPoint("LEFT", d.confirmButton, "RIGHT", 10, 0)
    d.cancelButton:SetScript("OnClick", function()
        d:Hide()
        if options.onCancel then options.onCancel() end
    end)

    d.onCancel = options.onCancel
    d:Show()
    return d
end

-- Confirm-dialog convenience wrappers
function PSM.TeamDialogs:ShowDeleteConfirmDialog(teamName, onConfirm, onCancel)
    return self:ShowConfirmDialog({
        title       = "Delete Team",
        message     = "Are you sure you want to delete the team\n'" .. (teamName or "Unknown") .. "'?\n\nThis action cannot be undone.",
        confirmText = "Delete", cancelText = "Cancel",
        onConfirm = onConfirm, onCancel = onCancel,
    })
end

function PSM.TeamDialogs:ShowApplyConfirmDialog(teamName, onConfirm, onCancel)
    return self:ShowConfirmDialog({
        title       = "Apply Team",
        message     = "Apply team '" .. (teamName or "Unknown") .. "' to your active pet slots?\n\nThis will rearrange your pets in slots 1-6.",
        confirmText = "Apply", cancelText = "Cancel",
        onConfirm = onConfirm, onCancel = onCancel,
    })
end

function PSM.TeamDialogs:ShowDeleteGroupConfirmDialog(groupName, onConfirm, onCancel)
    return self:ShowConfirmDialog({
        title       = "Delete Group",
        message     = "Are you sure you want to delete the group\n'" .. (groupName or "Unknown") .. "'?\n\nAll pets in this group will be moved to Ungrouped.",
        confirmText = "Delete", cancelText = "Cancel",
        onConfirm = onConfirm, onCancel = onCancel,
    })
end

function PSM.TeamDialogs:ShowDeleteAllGroupsConfirmDialog(onConfirm, onCancel)
    return self:ShowConfirmDialog({
        title       = "Delete All Groups",
        message     = "Are you sure you want to delete ALL groups?\n\nAll pets will be moved to Ungrouped.\nThis action cannot be undone.",
        confirmText = "Delete All", cancelText = "Cancel",
        onConfirm = onConfirm, onCancel = onCancel,
    })
end

--------------------------------------------------------------------------------
-- SAVE TEAM DIALOG
--------------------------------------------------------------------------------

function PSM.TeamDialogs:ShowSaveTeamDialog(options)
    options = options or {}

    local hasExisting = options.existingTeamId and options.existingTeamName
    if not hasExisting then
        return self:ShowNameInputDialog({
            title       = "Save New Team",
            description = "Enter a name for your pet team:",
            onConfirm   = options.onSaveNew,
            onCancel    = options.onCancel,
        })
    end

    local d = CreateBaseDialog("PSMTeamSaveDialog", 380, 180, "Save Pet Team")

    d.message = d:CreateFontString(nil, "OVERLAY")
    d.message:SetFont("Fonts\\FRIZQT__.TTF", 11)
    d.message:SetPoint("TOP", d.title, "BOTTOM", 0, -10)
    d.message:SetWidth(340)
    d.message:SetText("Current slots differ from team '" .. options.existingTeamName .. "'.\nWhat would you like to do?")
    d.message:SetTextColor(1, 1, 1)
    d.message:SetJustifyH("CENTER")

    local bc = CreateFrame("Frame", nil, d)
    bc:SetSize(350, 70)
    bc:SetPoint("BOTTOM", 0, 25)

    d.updateButton = CreateDialogButton(bc, "Update '" .. options.existingTeamName .. "'", 160, 25)
    d.updateButton:SetPoint("TOP", 0, 0)
    d.updateButton:SetScript("OnClick", function()
        d:Hide()
        if options.onUpdate then options.onUpdate() end
    end)

    d.saveNewButton = CreateDialogButton(bc, "Save as New Team", 160, 25)
    d.saveNewButton:SetPoint("TOP", d.updateButton, "BOTTOM", 0, -5)
    d.saveNewButton:SetScript("OnClick", function()
        d:Hide()
        self:ShowNameInputDialog({
            title       = "New Team Name",
            description = "Enter a name for the new team:",
            onConfirm   = options.onSaveNew,
            onCancel    = options.onCancel,
        })
    end)

    d.cancelButton = CreateDialogButton(bc, "Cancel", 100, 25)
    d.cancelButton:SetPoint("TOP", d.saveNewButton, "BOTTOM", 0, -5)
    d.cancelButton:SetScript("OnClick", function()
        d:Hide()
        if options.onCancel then options.onCancel() end
    end)

    d.onCancel = options.onCancel
    d:Show()
    return d
end

--------------------------------------------------------------------------------
-- UTILITY
--------------------------------------------------------------------------------

function PSM.TeamDialogs:CloseActiveDialog()
    if self.activeDialog then
        self.activeDialog:Hide()
        self.activeDialog = nil
    end
end

function PSM.TeamDialogs:IsDialogOpen()
    return self.activeDialog ~= nil and self.activeDialog:IsVisible()
end

--------------------------------------------------------------------------------
-- ADD TO TEAM DIALOG
--------------------------------------------------------------------------------

-- Shared handler for "Create New Team" button (avoids duplication between
-- the empty-teams branch and the has-teams branch).
local function CreateNewTeamFromPet(petData)
    local slots = {}
    slots[1] = {
        petNumber = petData.petNumber,
        name      = petData.name,
        displayID = petData.displayID or 0,
        icon      = petData.icon,
        familyName = petData.familyName,
        specName  = petData.specName,
        specID    = petData.specID,
        isExotic  = petData.isExotic,
        abilities = petData.abilities,
    }
    PSM.TeamDialogs:ShowNameInputDialog({
        title       = "New Team Name",
        description = "Enter a name for your new team:",
        onConfirm   = function(teamName)
            local teamId, err = PSM.Teams:SaveTeam(teamName, slots)
            if teamId and PSM.TeamsPanel then
                PSM.TeamsPanel:RefreshTeamsList()
            else
                print("|cFFFF0000PetStableManagement: " .. (err or "Failed to save team") .. "|r")
            end
        end,
    })
end

function PSM.TeamDialogs:ShowAddToTeamDialog(petData)
    if not petData then return end

    local teams = PSM.Teams:GetTeams()
    table.sort(teams, function(a, b)
        return string.lower(a.name or "") < string.lower(b.name or "")
    end)

    local teamCount   = #teams
    local btnW, btnH  = 180, 25
    local spacing     = 5
    local cols        = 2
    local numRows     = math.ceil(teamCount / cols)
    local btnAreaH    = math.max(numRows * btnH + math.max(numRows-1,0) * spacing, 40)
    local maxBtnAreaH = 250
    local needsScroll = btnAreaH > maxBtnAreaH
    local dialogW     = 420
    local headerH     = 80
    local footerH     = 70

    local d = CreateBaseDialog("PSMAddToTeamDialog", dialogW,
        headerH + (needsScroll and maxBtnAreaH or btnAreaH) + footerH, "Add Pet to Team", true)

    d.petInfoText = d:CreateFontString(nil, "OVERLAY")
    d.petInfoText:SetFont("Fonts\\FRIZQT__.TTF", 12)
    d.petInfoText:SetPoint("TOP", d.title, "BOTTOM", 0, -10)
    d.petInfoText:SetTextColor(1, 0.82, 0)
    d.petInfoText:SetText("Pet: " .. (petData.name or "Unknown"))

    d.description = d:CreateFontString(nil, "OVERLAY")
    d.description:SetFont("Fonts\\FRIZQT__.TTF", 11)
    d.description:SetPoint("TOP", d.petInfoText, "BOTTOM", 0, -5)
    d.description:SetTextColor(1, 1, 1)

    -- Bottom button area (shared by both branches)
    local bottom = CreateFrame("Frame", nil, d)
    bottom:SetSize(dialogW - 40, 60)
    bottom:SetPoint("BOTTOM", d, "BOTTOM", 0, 10)

    d.createNewButton = CreateDialogButton(bottom, "Create New Team", 180, 25)
    d.createNewButton:SetScript("OnClick", function()
        d:Hide()
        CreateNewTeamFromPet(petData)
    end)

    d.cancelButton = CreateDialogButton(bottom, "Cancel", 100, 25)
    d.cancelButton:SetScript("OnClick", function() d:Hide() end)

    if teamCount == 0 then
        d.description:SetText("You don't have any saved teams yet.\nCreate a new team with this pet:")
        d.createNewButton:SetPoint("CENTER", bottom, "CENTER", 0, 10)
        d.cancelButton:SetPoint("TOP",    d.createNewButton, "BOTTOM", 0, -5)
    else
        d.description:SetText("Select a team to add this pet to:")
        d.createNewButton:SetPoint("TOP", bottom, "TOP", 0, -5)
        d.cancelButton:SetPoint("TOP",    d.createNewButton, "BOTTOM", 0, -5)

        -- Build the team button grid inside a scroll frame or plain frame
        local function PlaceTeamButtons(container)
            d.teamButtons = {}
            for i, team in ipairs(teams) do
                local btn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
                btn:SetSize(btnW, btnH)
                btn:SetText(team.name)
                btn:SetNormalFontObject("GameFontNormalSmall")
                PSM.UI:ApplyElvUISkin(btn, "button")

                local col = (i-1) % cols
                local row = math.floor((i-1) / cols)
                btn:SetPoint("TOPLEFT", 5 + col*(btnW+spacing), -row*(btnH+spacing))

                btn:SetScript("OnClick", function()
                    d:Hide()
                    PSM.TeamDialogs:ShowSelectSlotDialog(team, petData)
                end)
                table.insert(d.teamButtons, btn)
            end
        end

        if needsScroll then
            local sf = CreateFrame("ScrollFrame", nil, d, "UIPanelScrollFrameTemplate")
            sf:SetPoint("TOPLEFT",  d, "TOPLEFT",  20, -headerH)
            sf:SetPoint("TOPRIGHT", d, "TOPRIGHT", -40, -headerH)
            sf:SetPoint("BOTTOM",   d, "BOTTOM",    0, footerH + 10)

            local content = CreateFrame("Frame", nil, sf)
            content:SetSize(sf:GetWidth() - 20, numRows * btnH + (numRows-1) * spacing)
            sf:SetScrollChild(content)
            PlaceTeamButtons(content)
        else
            local frame = CreateFrame("Frame", nil, d)
            frame:SetSize(dialogW - 40, btnAreaH)
            frame:SetPoint("TOP", d.description, "BOTTOM", 0, -10)
            PlaceTeamButtons(frame)
        end
    end

    d:Show()
    return d
end

--------------------------------------------------------------------------------
-- SELECT SLOT DIALOG
--------------------------------------------------------------------------------

function PSM.TeamDialogs:ShowSelectSlotDialog(team, petData)
    if not team or not petData then return end

    -- Duplicate-pet guard
    if team.slots then
        for slot = 1, 6 do
            if team.slots[slot] and team.slots[slot].petNumber == petData.petNumber then
                local d = CreateBaseDialog("PSMDuplicatePetWarning", 380, 150, "Duplicate Pet")
                d.message = d:CreateFontString(nil, "OVERLAY")
                d.message:SetFont("Fonts\\FRIZQT__.TTF", 11)
                d.message:SetPoint("TOP", d.title, "BOTTOM", 0, -15)
                d.message:SetWidth(340)
                d.message:SetText("'" .. (petData.name or "Unknown") .. "' is already in team '" .. team.name ..
                    "'\nat slot " .. slot .. ".\n\nEach pet can only appear once per team.")
                d.message:SetTextColor(1, 1, 1)
                d.message:SetJustifyH("CENTER")

                local ok = CreateDialogButton(d, "OK", 100, 25)
                ok:SetPoint("BOTTOM", d, "BOTTOM", 0, 15)
                ok:SetScript("OnClick", function() d:Hide() end)
                d:Show()
                return d
            end
        end
    end

    local d = CreateBaseDialog("PSMSelectSlotDialog", 420, 280, "Select Slot", true)

    d.teamInfoText = d:CreateFontString(nil, "OVERLAY")
    d.teamInfoText:SetFont("Fonts\\FRIZQT__.TTF", 12)
    d.teamInfoText:SetPoint("TOP", d.title, "BOTTOM", 0, -10)
    d.teamInfoText:SetTextColor(1, 0.82, 0)
    d.teamInfoText:SetText("Team: " .. team.name)

    d.petInfoText = d:CreateFontString(nil, "OVERLAY")
    d.petInfoText:SetFont("Fonts\\FRIZQT__.TTF", 11)
    d.petInfoText:SetPoint("TOP", d.teamInfoText, "BOTTOM", 0, -5)
    d.petInfoText:SetTextColor(1, 1, 1)
    d.petInfoText:SetText("Pet: " .. (petData.name or "Unknown"))

    d.description = d:CreateFontString(nil, "OVERLAY")
    d.description:SetFont("Fonts\\FRIZQT__.TTF", 11)
    d.description:SetPoint("TOP", d.petInfoText, "BOTTOM", 0, -5)
    d.description:SetText("Select a slot to add this pet to:")
    d.description:SetTextColor(0.8, 0.8, 0.8)

    local btnSize = 55
    local gap     = 10
    local cols    = 3
    local totalW  = cols * btnSize + (cols-1) * gap
    local startX  = (420 - totalW) / 2
    local startY  = -95

    d.slotButtons = {}
    for slot = 1, 6 do
        local btn = CreateFrame("Button", nil, d, "BackdropTemplate")
        btn:SetSize(btnSize, btnSize)

        local row = math.floor((slot-1) / cols)
        local col = (slot-1) % cols
        btn:SetPoint("TOPLEFT", d, "TOPLEFT", startX + col*(btnSize+gap), startY - row*(btnSize+gap))

        btn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile=true, tileSize=8, edgeSize=8,
            insets={left=2, right=2, top=2, bottom=2},
        })
        btn:SetBackdropColor(unpack(PSM.Config.COLORS.BACKGROUND))

        local isOccupied = team.slots and team.slots[slot] ~= nil
        btn:SetBackdropBorderColor(isOccupied and 0.3 or 0.3, isOccupied and 0.3 or 0.5, isOccupied and 0.3 or 0.3, 1)

        local label = btn:CreateFontString(nil, "OVERLAY")
        label:SetFont("Fonts\\FRIZQT__.TTF", 11)
        label:SetPoint("CENTER")
        label:SetText("Slot " .. slot)
        label:SetTextColor(isOccupied and 0.8 or 0.5, isOccupied and 0.8 or 1.0, isOccupied and 0.8 or 0.5)

        btn:SetScript("OnClick", function()
            d:Hide()
            PSM.TeamDialogs:ConfirmAddToTeam(team, petData, slot)
        end)
        btn:SetScript("OnEnter", function()
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            if isOccupied then
                GameTooltip:SetText("Slot " .. slot .. " (Occupied)", 1, 0.82, 0)
                GameTooltip:AddLine((team.slots[slot].name or "Unknown Pet"), 1, 1, 1)
            else
                GameTooltip:SetText("Slot " .. slot .. " (Available)", 0.5, 1, 0.5)
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        table.insert(d.slotButtons, btn)
    end

    d.cancelButton = CreateDialogButton(d, "Cancel", 100, 25)
    d.cancelButton:SetPoint("BOTTOM", d, "BOTTOM", 0, 15)
    d.cancelButton:SetScript("OnClick", function()
        d:Hide()
        PSM.TeamDialogs:ShowAddToTeamDialog(petData)
    end)

    d:Show()
    return d
end

--------------------------------------------------------------------------------
-- CONFIRM ADD / REMOVE
--------------------------------------------------------------------------------

function PSM.TeamDialogs:ConfirmAddToTeam(team, petData, slot)
    if not team or not petData or not slot then return end

    -- Duplicate guard
    if team.slots then
        for i = 1, 6 do
            if team.slots[i] and team.slots[i].petNumber == petData.petNumber then
                print("|cFFFF0000PetStableManagement: Cannot add duplicate pet '" .. (petData.name or "Unknown") ..
                    "' to team '" .. team.name .. "'. Pet already exists at slot " .. i .. ".|r")
                return
            end
        end
    end

    local slots = {}
    for i = 1, 6 do
        if team.slots and team.slots[i] then slots[i] = PSM.Utils.DeepCopy(team.slots[i]) end
    end
    slots[slot] = {
        petNumber  = petData.petNumber,
        name       = petData.name,
        displayID  = petData.displayID or 0,
        icon       = petData.icon,
        familyName = petData.familyName,
        specName   = petData.specName,
        specID     = petData.specID,
        isExotic   = petData.isExotic,
        abilities  = petData.abilities,
    }

    local ok, err = PSM.Teams:UpdateTeam(team.id, slots)
    if ok then
        if PSM.TeamsPanel then PSM.TeamsPanel:RefreshTeamsList() end
        print("|cFF00FF00PetStableManagement: Added '" .. (petData.name or "Unknown") ..
            "' to team '" .. team.name .. "' at slot " .. slot .. ".|r")
    else
        print("|cFFFF0000PetStableManagement: " .. (err or "Failed to add pet to team") .. "|r")
    end
end

function PSM.TeamDialogs:ConfirmRemoveFromTeam(team, slot, petName)
    if not team or not slot then return end

    local slots = {}
    for i = 1, 6 do
        if team.slots and team.slots[i] and i ~= slot then
            slots[i] = PSM.Utils.DeepCopy(team.slots[i])
        end
    end

    local ok, err = PSM.Teams:UpdateTeam(team.id, slots)
    if ok then
        if PSM.TeamsPanel then PSM.TeamsPanel:RefreshTeamsList() end
        print("|cFF00FF00PetStableManagement: Removed pet from team '" .. team.name .. "'.|r")
    else
        print("|cFFFF0000PetStableManagement: " .. (err or "Failed to remove pet from team") .. "|r")
    end
end

--------------------------------------------------------------------------------
-- REMOVE FROM TEAM DIALOG
--------------------------------------------------------------------------------

function PSM.TeamDialogs:ShowRemoveFromTeamDialog(petData)
    if not petData then return end

    local teams = PSM.Teams:GetTeams()
    local matches = {}
    for _, team in ipairs(teams) do
        for slot = 1, 6 do
            if team.slots and team.slots[slot] and team.slots[slot].petNumber == petData.petNumber then
                table.insert(matches, {team=team, slot=slot})
                break
            end
        end
    end

    local count   = #matches
    local dialogH = 180 + (count > 0 and count * 35 or 0)
    local d = CreateBaseDialog("PSMRemoveFromTeamDialog", 420, dialogH, "Remove from Team", true)

    d.petInfoText = d:CreateFontString(nil, "OVERLAY")
    d.petInfoText:SetFont("Fonts\\FRIZQT__.TTF", 12)
    d.petInfoText:SetPoint("TOP", d.title, "BOTTOM", 0, -10)
    d.petInfoText:SetTextColor(1, 0.82, 0)
    d.petInfoText:SetText("Pet: " .. (petData.name or "Unknown"))

    d.description = d:CreateFontString(nil, "OVERLAY")
    d.description:SetFont("Fonts\\FRIZQT__.TTF", 11)
    d.description:SetPoint("TOP", d.petInfoText, "BOTTOM", 0, -5)
    d.description:SetTextColor(1, 1, 1)

    if count == 0 then
        d.description:SetText("This pet is not in any of your saved teams.")
        local ok = CreateDialogButton(d, "Close", 100, 25)
        ok:SetPoint("BOTTOM", d, "BOTTOM", 0, 15)
        ok:SetScript("OnClick", function() d:Hide() end)
    else
        d.description:SetText("This pet is in " .. count .. " team(s).\nSelect a team to remove from:")

        d.teamButtons = {}
        local btnW, btnH = 200, 28
        for i, match in ipairs(matches) do
            local btn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
            btn:SetSize(btnW, btnH)
            btn:SetText(match.team.name .. " (Slot " .. match.slot .. ")")
            btn:SetNormalFontObject("GameFontNormalSmall")
            btn:SetPoint("TOP", d, "TOP", 0, -100 - (i-1)*(btnH+5))
            btn:SetScript("OnClick", function()
                d:Hide()
                PSM.TeamDialogs:ConfirmRemoveFromTeam(match.team, match.slot, petData.name)
            end)
            table.insert(d.teamButtons, btn)
        end

        d.cancelButton = CreateDialogButton(d, "Cancel", 100, 25)
        d.cancelButton:SetPoint("BOTTOM", d, "BOTTOM", 0, 15)
        d.cancelButton:SetScript("OnClick", function() d:Hide() end)
    end

    d:Show()
    return d
end
