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

-- Body text inside a dialog: the message/description lines every dialog has one or
-- two of. Centralised here rather than repeated per dialog, so they can't drift.
local function CreateDialogText(parent, opts)
    return PSM.Widgets.Label(parent, {
        fontSize = opts.fontSize or PSM.Theme.SIZE.BODY,
        color    = opts.color or PSM.Theme.COLOR.WHITE,
        justify  = opts.justify,
        width    = opts.width,
        point    = opts.point,
        text     = opts.text,
    })
end

-- Creates a styled dialog frame. Pass resizable=true for a resize handle.
local function CreateBaseDialog(name, width, height, title, resizable)
    if PSM.TeamDialogs.activeDialog then
        PSM.TeamDialogs.activeDialog:Hide()
    end

    local Theme, Widgets = PSM.Theme, PSM.Widgets

    local d = Widgets.MovableFrame(UIParent, {
        name        = name,
        size        = { width or 350, height or 150 },
        point       = { "CENTER", UIParent, "CENTER", 0, 100 },
        strata      = "DIALOG",
        level       = 100,
        backdrop    = "TOOLTIP",
        color       = { 0.1, 0.1, 0.1, 0.95 },
        borderColor = { 0.6, 0.6, 0.6, 1    },
        -- No `skin` here on purpose: ElvUI's HandleFrame strips textures, and the
        -- original applied it *after* the title/close/grip existed. Skinning at
        -- construction would change what is in scope when it runs, so the call is
        -- kept at the bottom of this function where it has always been.
    })
    d:SetToplevel(true)
    d:SetClampedToScreen(true)
    d:SetResizable(resizable or false)

    d.title = Widgets.Label(d, {
        fontSize = Theme.SIZE.HEADING,
        outline  = true,
        color    = Theme.COLOR.GOLD,
        point    = { "TOP", 0, -15 },
        text     = title or "Dialog",
    })

    -- Closing a dialog by any route is a cancellation, and callers are waiting on
    -- the answer -- so the X, Escape and the Cancel buttons all report it.
    local function Cancel()
        if d.onCancel then d.onCancel() end
    end

    d.closeButton = Widgets.CloseButton(d, {
        point   = { "TOPRIGHT", -2, -2 },
        size    = { 24, 24 },
        onClick = function() d:Hide(); Cancel() end,
    })

    if resizable then
        d.resizeHandle = Widgets.ResizeGrip(d)
    end

    Widgets.CloseOnEscape(d, Cancel)

    PSM.Skin.Apply(d, "frame")

    PSM.TeamDialogs.activeDialog = d
    d:SetScript("OnHide", function(self)
        if PSM.TeamDialogs.activeDialog == self then
            PSM.TeamDialogs.activeDialog = nil
        end
    end)

    return d
end

-- `width` is a Theme.CONTROL.BUTTON_W tier; omit it for M, which is what every
-- OK/Cancel/Yes/No in this file wants. Height comes from the factory.
local function CreateDialogButton(parent, text, width)
    return PSM.Widgets.Button(parent, {
        width      = width,
        text       = text,
        fontObject = "GameFontNormal",
    })
end

-- 24, down from 50: team and group names are displayed *inside buttons* -- the team
-- picker rows below, at 180 and 200 wide -- and a 50-character name overran those by
-- 116px and 137px respectively (measured via PSM.Widgets.truncatedLabels). 24 fits both,
-- with the narrower one losing about nine characters to its " (Slot N)" suffix.
--
-- This caps *input*, not display: names already saved at up to 50 stay as they are and
-- clip in those rows, which is the correct outcome -- silently rewriting someone's saved
-- team name would be worse than a shortened label.
local function CreateDialogEditBox(parent, width, height)
    local e = PSM.Widgets.EditBox(parent, {
        size = { width or 250, height or 25 },
    })
    e:SetMaxLetters(24)
    return e
end

--------------------------------------------------------------------------------
-- NAME INPUT DIALOG  (used by several callers)
--------------------------------------------------------------------------------

function PSM.TeamDialogs:ShowNameInputDialog(options)
    options = options or {}

    local d = CreateBaseDialog("PSMTeamNameDialog", 350, 140, options.title or "Enter Team Name")

    d.description = CreateDialogText(d, {
        point = { "TOP", d.title, "BOTTOM", 0, -10 },
        text  = options.description or "Enter a name for your pet team:",
    })

    d.editBox = CreateDialogEditBox(d, 140, 25)
    d.editBox:SetPoint("TOP", d.description, "BOTTOM", 0, -10)
    d.editBox:SetText(options.defaultText or "")
    d.editBox:SetFocus()
    if options.highlightText then d.editBox:HighlightText() end

    local bc = PSM.Widgets.Frame(d, { size = { 220, 30 }, point = { "BOTTOM", 0, 15 } })

    d.confirmButton = CreateDialogButton(bc, options.confirmText or "Save")
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

    d.cancelButton = CreateDialogButton(bc, "Cancel")
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

    d.message = CreateDialogText(d, {
        point   = { "TOP", d.title, "BOTTOM", 0, -15 },
        width   = 300,
        justify = "CENTER",
        text    = options.message or "Are you sure?",
    })

    local bc = PSM.Widgets.Frame(d, { size = { 220, 30 }, point = { "BOTTOM", 0, 5 } })

    d.confirmButton = CreateDialogButton(bc, options.confirmText or "Yes")
    d.confirmButton:SetPoint("LEFT", 0, 0)
    d.confirmButton:SetScript("OnClick", function()
        d:Hide()
        if options.onConfirm then options.onConfirm() end
    end)

    d.cancelButton = CreateDialogButton(bc, options.cancelText or "No")
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

    d.message = CreateDialogText(d, {
        point   = { "TOP", d.title, "BOTTOM", 0, -10 },
        width   = 340,
        justify = "CENTER",
        text    = "Current slots differ from team '" .. options.existingTeamName .. "'.\nWhat would you like to do?",
    })

    local bc = PSM.Widgets.Frame(d, { size = { 350, 70 }, point = { "BOTTOM", 0, 25 } })

    -- "Update Team", not "Update '<name>'": the team name is user-typed and unbounded, so
    -- it was the one push-button label no fixed width could hold. The message above
    -- already names the team, so the button was repeating it.
    d.updateButton = CreateDialogButton(bc, "Update Team", PSM.Theme.CONTROL.BUTTON_W.L)
    d.updateButton:SetPoint("TOP", 0, 0)
    d.updateButton:SetScript("OnClick", function()
        d:Hide()
        if options.onUpdate then options.onUpdate() end
    end)

    d.saveNewButton = CreateDialogButton(bc, "Save as New Team", PSM.Theme.CONTROL.BUTTON_W.L)
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

    d.cancelButton = CreateDialogButton(bc, "Cancel")
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

--------------------------------------------------------------------------------
-- ADD TO TEAM DIALOG
--------------------------------------------------------------------------------

-- Shared handler for "Create New Team" button (avoids duplication between
-- the empty-teams branch and the has-teams branch).
local function CreateNewTeamFromPet(petData)
    local slots = {}
    slots[1] = PSM.Teams:SlotRecord(petData)
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

    d.petInfoText = CreateDialogText(d, {
        fontSize = PSM.Theme.SIZE.LABEL,
        color    = PSM.Theme.COLOR.GOLD,
        point    = { "TOP", d.title, "BOTTOM", 0, -10 },
        text     = "Pet: " .. (petData.name or "Unknown"),
    })

    d.description = CreateDialogText(d, {
        point = { "TOP", d.petInfoText, "BOTTOM", 0, -5 },
    })

    -- Bottom button area (shared by both branches)
    local bottom = PSM.Widgets.Frame(d, {
        size  = { dialogW - 40, 60 },
        point = { "BOTTOM", d, "BOTTOM", 0, 10 },
    })

    d.createNewButton = CreateDialogButton(bottom, "Create New Team", PSM.Theme.CONTROL.BUTTON_W.L)
    d.createNewButton:SetScript("OnClick", function()
        d:Hide()
        CreateNewTeamFromPet(petData)
    end)

    d.cancelButton = CreateDialogButton(bottom, "Cancel")
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
                local col = (i-1) % cols
                local row = math.floor((i-1) / cols)

                local btn = PSM.Widgets.Button(container, {
                    size       = { btnW, btnH },
                    text       = team.name,
                    fontObject = "GameFontNormalSmall",
                    point      = { "TOPLEFT", 5 + col*(btnW+spacing), -row*(btnH+spacing) },
                    onClick    = function()
                        d:Hide()
                        PSM.TeamDialogs:ShowSelectSlotDialog(team, petData)
                    end,
                })
                table.insert(d.teamButtons, btn)
            end
        end

        if needsScroll then
            local sf = PSM.Widgets.Frame(d, {
                frameType = "ScrollFrame",
                template  = "UIPanelScrollFrameTemplate",
                skin      = "scrollframe",
                point     = {
                    { "TOPLEFT",  d, "TOPLEFT",   20, -headerH },
                    { "TOPRIGHT", d, "TOPRIGHT", -40, -headerH },
                    { "BOTTOM",   d, "BOTTOM",     0, footerH + 10 },
                },
            })

            local content = PSM.Widgets.Frame(sf, {
                size = { sf:GetWidth() - 20, numRows * btnH + (numRows-1) * spacing },
            })
            sf:SetScrollChild(content)
            PlaceTeamButtons(content)
        else
            local frame = PSM.Widgets.Frame(d, {
                size  = { dialogW - 40, btnAreaH },
                point = { "TOP", d.description, "BOTTOM", 0, -10 },
            })
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
                d.message = CreateDialogText(d, {
                    point   = { "TOP", d.title, "BOTTOM", 0, -15 },
                    width   = 340,
                    justify = "CENTER",
                    text    = "'" .. (petData.name or "Unknown") .. "' is already in team '" .. team.name ..
                        "'\nat slot " .. slot .. ".\n\nEach pet can only appear once per team.",
                })

                local ok = CreateDialogButton(d, "OK")
                ok:SetPoint("BOTTOM", d, "BOTTOM", 0, 15)
                ok:SetScript("OnClick", function() d:Hide() end)
                d:Show()
                return d
            end
        end
    end

    local d = CreateBaseDialog("PSMSelectSlotDialog", 420, 280, "Select Slot", true)

    d.teamInfoText = CreateDialogText(d, {
        fontSize = PSM.Theme.SIZE.LABEL,
        color    = PSM.Theme.COLOR.GOLD,
        point    = { "TOP", d.title, "BOTTOM", 0, -10 },
        text     = "Team: " .. team.name,
    })

    d.petInfoText = CreateDialogText(d, {
        point = { "TOP", d.teamInfoText, "BOTTOM", 0, -5 },
        text  = "Pet: " .. (petData.name or "Unknown"),
    })

    d.description = CreateDialogText(d, {
        color = PSM.Theme.COLOR.MUTED,
        point = { "TOP", d.petInfoText, "BOTTOM", 0, -5 },
        text  = "Select a slot to add this pet to:",
    })

    local btnSize = 55
    local gap     = 10
    local cols    = 3
    local totalW  = cols * btnSize + (cols-1) * gap
    local startX  = (420 - totalW) / 2
    local startY  = -95

    d.slotButtons = {}
    for slot = 1, 6 do
        local row = math.floor((slot-1) / cols)
        local col = (slot-1) % cols
        local isOccupied = team.slots and team.slots[slot] ~= nil

        local btn = PSM.Widgets.Frame(d, {
            frameType = "Button",
            size      = { btnSize, btnSize },
            point     = { "TOPLEFT", d, "TOPLEFT",
                          startX + col*(btnSize+gap), startY - row*(btnSize+gap) },
            backdrop  = "TOOLTIP",
            backdropOverrides = {
                tileSize = 8, edgeSize = 8,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            },
            color       = PSM.Config.COLORS.BACKGROUND,
            borderColor = isOccupied and { 0.3, 0.3, 0.3, 1 } or { 0.3, 0.5, 0.3, 1 },
        })

        PSM.Widgets.Label(btn, {
            fontSize = PSM.Theme.SIZE.BODY,
            color    = isOccupied and { 0.8, 0.8, 0.8 } or { 0.5, 1.0, 0.5 },
            point    = { "CENTER" },
            text     = "Slot " .. slot,
        })

        btn:SetScript("OnClick", function()
            d:Hide()
            PSM.TeamDialogs:ConfirmAddToTeam(team, petData, slot)
        end)

        PSM.Tooltip.Attach(btn, isOccupied
            and {
                title      = "Slot " .. slot .. " (Occupied)",
                titleColor = PSM.Theme.COLOR.GOLD,
                lines      = { { text = team.slots[slot].name or "Unknown Pet",
                                 color = PSM.Theme.COLOR.WHITE } },
            }
            or {
                title      = "Slot " .. slot .. " (Available)",
                titleColor = { 0.5, 1, 0.5 },
            })

        table.insert(d.slotButtons, btn)
    end

    d.cancelButton = CreateDialogButton(d, "Cancel")
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
    slots[slot] = PSM.Teams:SlotRecord(petData)

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

    d.petInfoText = CreateDialogText(d, {
        fontSize = PSM.Theme.SIZE.LABEL,
        color    = PSM.Theme.COLOR.GOLD,
        point    = { "TOP", d.title, "BOTTOM", 0, -10 },
        text     = "Pet: " .. (petData.name or "Unknown"),
    })

    d.description = CreateDialogText(d, {
        point = { "TOP", d.petInfoText, "BOTTOM", 0, -5 },
    })

    if count == 0 then
        d.description:SetText("This pet is not in any of your saved teams.")
        local ok = CreateDialogButton(d, "Close")
        ok:SetPoint("BOTTOM", d, "BOTTOM", 0, 15)
        ok:SetScript("OnClick", function() d:Hide() end)
    else
        d.description:SetText("This pet is in " .. count .. " team(s).\nSelect a team to remove from:")

        d.teamButtons = {}
        local btnW, btnH = 200, 28
        for i, match in ipairs(matches) do
            local btn = PSM.Widgets.Button(d, {
                size       = { btnW, btnH },
                text       = match.team.name .. " (Slot " .. match.slot .. ")",
                fontObject = "GameFontNormalSmall",
                point      = { "TOP", d, "TOP", 0, -100 - (i-1)*(btnH+5) },
                onClick    = function()
                    d:Hide()
                    PSM.TeamDialogs:ConfirmRemoveFromTeam(match.team, match.slot, petData.name)
                end,
            })
            table.insert(d.teamButtons, btn)
        end

        d.cancelButton = CreateDialogButton(d, "Cancel")
        d.cancelButton:SetPoint("BOTTOM", d, "BOTTOM", 0, 15)
        d.cancelButton:SetScript("OnClick", function() d:Hide() end)
    end

    d:Show()
    return d
end
