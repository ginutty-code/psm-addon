-- Dialogs.lua
-- Reusable dialog windows for PetStableManagement

local _, ns = ...

ns.Dialogs = ns.Dialogs or {}
ns.Dialogs.activeDialog = nil

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------



--------------------------------------------------------------------------------
-- BASE DIALOG CREATION
--------------------------------------------------------------------------------

-- Body text inside a dialog: the message/description lines every dialog has one or
-- two of. Centralised here rather than repeated per dialog, so they can't drift.
local function CreateDialogText(parent, opts)
    return ns.Widgets.Label(parent, {
        fontSize = opts.fontSize or ns.Theme.SIZE.BODY,
        color    = opts.color or ns.Theme.COLOR.WHITE,
        justify  = opts.justify,
        width    = opts.width,
        point    = opts.point,
        text     = opts.text,
    })
end

-- Creates a styled dialog frame. Pass resizable=true for a resize handle.
local function CreateBaseDialog(name, width, height, title, resizable)
    if ns.Dialogs.activeDialog then
        ns.Dialogs.activeDialog:Hide()
    end

    local Theme, Widgets = ns.Theme, ns.Widgets

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
        text     = title or ns.L("Dialog"),
    })

    -- Closing a dialog by any route is a cancellation, and callers are waiting on
    -- the answer -- so the X, Escape and the Cancel buttons all report it.
    local function Cancel()
        if d.onCancel then d.onCancel() end
    end

    -- 20x20 to match every panel's close button (PanelManager:CreateBasePanel) --
    -- both go through Widgets.CloseButton, the size is the only thing that differed.
    d.closeButton = Widgets.CloseButton(d, {
        point   = { "TOPRIGHT", -2, -2 },
        size    = { 20, 20 },
        onClick = function() d:Hide(); Cancel() end,
    })

    if resizable then
        d.resizeHandle = Widgets.ResizeGrip(d)
    end

    Widgets.CloseOnEscape(d, Cancel)

    ns.Skin.Apply(d, "frame")

    ns.Dialogs.activeDialog = d
    d:SetScript("OnHide", function(self)
        if ns.Dialogs.activeDialog == self then
            ns.Dialogs.activeDialog = nil
        end
    end)

    return d
end

-- `width` is a Theme.CONTROL.BUTTON_W tier; omit it for M, which is what every
-- OK/Cancel/Yes/No in this file wants. Height comes from the factory.
local function CreateDialogButton(parent, text, width)
    return ns.Widgets.Button(parent, {
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
    local e = ns.Widgets.EditBox(parent, {
        size = { width or 250, height or 25 },
    })
    e:SetMaxLetters(24)
    return e
end

--------------------------------------------------------------------------------
-- NAME INPUT DIALOG  (used by several callers)
--------------------------------------------------------------------------------

function ns.Dialogs:ShowNameInputDialog(options)
    options = options or {}

    local d = CreateBaseDialog("PSMTeamNameDialog", 350, 140, options.title or ns.L("Enter Team Name"))

    d.description = CreateDialogText(d, {
        point = { "TOP", d.title, "BOTTOM", 0, -10 },
        text  = options.description or ns.L("Enter a name for your pet team:"),
    })

    d.editBox = CreateDialogEditBox(d, 140, 25)
    d.editBox:SetPoint("TOP", d.description, "BOTTOM", 0, -10)
    d.editBox:SetText(options.defaultText or "")
    d.editBox:SetFocus()
    if options.highlightText then d.editBox:HighlightText() end

    local bc = ns.Widgets.Frame(d, { size = { 220, 30 }, point = { "BOTTOM", 0, 15 } })

    d.confirmButton = CreateDialogButton(bc, options.confirmText or ns.L("Save"))
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

    d.cancelButton = CreateDialogButton(bc, ns.L("Cancel"))
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
function ns.Dialogs:ShowGroupNameDialog(options)
    options = options or {}
    local isRename = options.mode == "rename"

    return self:ShowNameInputDialog({
        title       = isRename and ns.L("Rename Group")   or ns.L("Create New Group"),
        description = isRename and ns.L("Enter a new name for the group:")
                               or ns.L("Enter a name for the new group:"),
        defaultText = isRename and (options.currentName or "") or (options.suggestedName or ns.L("New Group")),
        confirmText = isRename and ns.L("Rename") or ns.L("Create"),
        highlightText = true,
        onConfirm   = options.onConfirm,
        onCancel    = options.onCancel,
    })
end

-- Convenience shims kept for callers that use the old names
function ns.Dialogs:ShowCreateGroupDialog(options)
    options = options or {}
    options.mode = "create"
    return self:ShowGroupNameDialog(options)
end

function ns.Dialogs:ShowRenameGroupDialog(options)
    options = options or {}
    options.mode = "rename"
    return self:ShowGroupNameDialog(options)
end

--------------------------------------------------------------------------------
-- CONFIRMATION DIALOG
--------------------------------------------------------------------------------

function ns.Dialogs:ShowConfirmDialog(options)
    options = options or {}

    local d = CreateBaseDialog("PSMTeamConfirmDialog", 350, 130, options.title or ns.L("Confirm"))

    d.message = CreateDialogText(d, {
        point   = { "TOP", d.title, "BOTTOM", 0, -15 },
        width   = 300,
        justify = "CENTER",
        text    = options.message or ns.L("Are you sure?"),
    })

    local bc = ns.Widgets.Frame(d, { size = { 220, 30 }, point = { "BOTTOM", 0, 5 } })

    d.confirmButton = CreateDialogButton(bc, options.confirmText or ns.L("Yes"))
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
function ns.Dialogs:ShowDeleteConfirmDialog(teamName, onConfirm, onCancel)
    return self:ShowConfirmDialog({
        title       = ns.L("Delete Team"),
        message     = ns.L("Are you sure you want to delete the team\n'%s'?\n\nThis action cannot be undone.",
                           teamName or ns.L("Unknown")),
        confirmText = ns.L("Delete"), cancelText = ns.L("Cancel"),
        onConfirm = onConfirm, onCancel = onCancel,
    })
end

function ns.Dialogs:ShowApplyConfirmDialog(teamName, onConfirm, onCancel)
    return self:ShowConfirmDialog({
        title       = ns.L("Apply Team"),
        message     = ns.L("Apply team '%s' to your active pet slots?\n\nThis will rearrange your pets in slots 1-6.",
                           teamName or ns.L("Unknown")),
        confirmText = ns.L("Apply"), cancelText = ns.L("Cancel"),
        onConfirm = onConfirm, onCancel = onCancel,
    })
end

function ns.Dialogs:ShowDeleteGroupConfirmDialog(groupName, onConfirm, onCancel)
    return self:ShowConfirmDialog({
        title       = ns.L("Delete Group"),
        message     = ns.L("Are you sure you want to delete the group\n'%s'?\n\nAll pets in this group will be moved to Ungrouped.",
                           groupName or ns.L("Unknown")),
        confirmText = ns.L("Delete"), cancelText = ns.L("Cancel"),
        onConfirm = onConfirm, onCancel = onCancel,
    })
end

function ns.Dialogs:ShowDeleteAllGroupsConfirmDialog(onConfirm, onCancel)
    return self:ShowConfirmDialog({
        title       = ns.L("Delete All Groups"),
        message     = ns.L("Are you sure you want to delete ALL groups?\n\nAll pets will be moved to Ungrouped.\nThis action cannot be undone."),
        confirmText = ns.L("Delete All"), cancelText = ns.L("Cancel"),
        onConfirm = onConfirm, onCancel = onCancel,
    })
end

--------------------------------------------------------------------------------
-- SAVE TEAM DIALOG
--------------------------------------------------------------------------------

function ns.Dialogs:ShowSaveTeamDialog(options)
    options = options or {}

    local hasExisting = options.existingTeamId and options.existingTeamName
    if not hasExisting then
        return self:ShowNameInputDialog({
            title       = ns.L("Save New Team"),
            description = ns.L("Enter a name for your pet team:"),
            onConfirm   = options.onSaveNew,
            onCancel    = options.onCancel,
        })
    end

    local d = CreateBaseDialog("PSMTeamSaveDialog", 380, 180, ns.L("Save Pet Team"))

    d.message = CreateDialogText(d, {
        point   = { "TOP", d.title, "BOTTOM", 0, -10 },
        width   = 340,
        justify = "CENTER",
        text    = ns.L("Current slots differ from team '%s'.\nWhat would you like to do?", options.existingTeamName),
    })

    local bc = ns.Widgets.Frame(d, { size = { 350, 70 }, point = { "BOTTOM", 0, 25 } })

    -- "Update Team", not "Update '<name>'": the team name is user-typed and unbounded, so
    -- it was the one push-button label no fixed width could hold. The message above
    -- already names the team, so the button was repeating it.
    d.updateButton = CreateDialogButton(bc, ns.L("Update Team"), ns.Theme.CONTROL.BUTTON_W.L)
    d.updateButton:SetPoint("TOP", 0, 0)
    d.updateButton:SetScript("OnClick", function()
        d:Hide()
        if options.onUpdate then options.onUpdate() end
    end)

    d.saveNewButton = CreateDialogButton(bc, ns.L("Save as New Team"), ns.Theme.CONTROL.BUTTON_W.L)
    d.saveNewButton:SetPoint("TOP", d.updateButton, "BOTTOM", 0, -5)
    d.saveNewButton:SetScript("OnClick", function()
        d:Hide()
        self:ShowNameInputDialog({
            title       = ns.L("New Team Name"),
            description = ns.L("Enter a name for the new team:"),
            onConfirm   = options.onSaveNew,
            onCancel    = options.onCancel,
        })
    end)

    d.cancelButton = CreateDialogButton(bc, ns.L("Cancel"))
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
-- TEAM ROULETTE DIALOG
--------------------------------------------------------------------------------

-- The preview for a random roll: one cell per slot, a per-slot spec-cycle button, a
-- per-slot lock, and Re-roll / Apply now / Save as team... / Cancel. The roll itself is
-- ns.TeamRoulette (OwnedPets/TeamRoulette.lua); this file owns only the chrome.
--
-- `state` is the live table ns.TeamRoulette:Show builds: { slotCount, template,
-- locked, slots, report }. Re-roll and spec changes mutate it in place and repaint.

-- Text colour per spec on the cycle button, matching the Stable Master's own spec
-- identities: Ferocity brown, Tenacity purple, Cunning green. Plus the "Any" resting
-- colour. Local because only this button cares.
local ROULETTE_SPEC_COLOR = {
    Any      = ns.Theme.COLOR.MUTED,
    Ferocity = { 0.80, 0.52, 0.34 },
    Tenacity = { 0.72, 0.52, 0.92 },
    Cunning  = { 0.45, 0.78, 0.42 },
}

-- The per-slot lock affordance: a plain padlock icon (no button chrome -- the button
-- backdrop fought the cell), tinted by state. Swap the texture or either colour if a
-- different glyph reads better; other theme-friendly candidates:
--   Interface\Buttons\UI-Button-KeyRing-Down   Interface\TimeManager\PauseButton
--   Interface\Buttons\UI-CheckBox-Check (a green check, if "keep" reads better than "lock")
local LOCK_ICON        = "Interface\\petbattles\\petbattle-lockicon"
local LOCK_TINT_OPEN   = ns.Theme.COLOR.GOLD     -- unlocked: still in play
local LOCK_TINT_CLOSED = ns.Theme.COLOR.SILVER   -- locked: settled

-- Any → Ferocity → Tenacity → Cunning → Any. The kit renders a plain button; the
-- cycle order is this caller's, the same split Filters.lua's NextTriState uses.
local function NextRouletteSpec(spec)
    if spec == nil        then return "Ferocity" end
    if spec == "Ferocity" then return "Tenacity" end
    if spec == "Tenacity" then return "Cunning"  end
    return nil
end

function ns.Dialogs:ShowTeamRouletteDialog(state)
    if not state or not state.slotCount then return end

    local Theme, Widgets = ns.Theme, ns.Widgets

    local slotCount     = state.slotCount
    -- The cell is sized around the ringed pet portrait so the grid reads like a row of
    -- Teams-panel slots. RING is the footer_inactive-ring frame; PORTRAIT_TOP is where
    -- it hangs from the cell top; the name/family/spec stack sits under it.
    local RING          = Theme.CONTROL.PET_PORTRAIT_RING
    local PORTRAIT_TOP  = -8
    local CELL_W        = RING + 8
    local CELL_H        = 150
    local CELL_BORDER   = { 0.3, 0.3, 0.3, 1 }
    local PICK_BORDER   = { 1, 0.82, 0, 1 }   -- the "picked up, choose a slot to swap with" outline
    local CELL_GAP      = 8
    local COMPANION_GAP = 26   -- extra space before slot 6 (a touch tighter than the
                               -- Teams panel's 30, so slot 6 sits nearer slot 5)
    local DIVIDER_W     = 26   -- gold rule length, = Teams panel's slot5to6Gap - 4
    local GRID_Y        = -62
    -- -42, up from the old -24: the spec-cycle button hangs ~23px below each cell, so
    -- the old gap left the warning/hint line almost touching it.
    local warnY         = GRID_Y - CELL_H - 42
    local gridW         = slotCount * CELL_W + (slotCount - 1) * CELL_GAP
                          + (slotCount >= 6 and COMPANION_GAP or 0)
    local dialogW       = math.max(440, gridW + 40)
    local dialogH       = -warnY + 78

    local d = CreateBaseDialog("PSMTeamRouletteDialog", dialogW, dialogH, ns.L("Team Roulette"))

    d.poolText = CreateDialogText(d, {
        fontSize = Theme.SIZE.LABEL,
        color    = Theme.COLOR.GOLD,
        point    = { "TOP", d.title, "BOTTOM", 0, -8 },
        text     = "",
    })

    -- One cell per slot: portrait, name, family, spec line, lock, spec-cycle button.
    local startX = (dialogW - gridW) / 2
    d.cells = {}

    for slot = 1, slotCount do
        local x = startX + (slot - 1) * (CELL_W + CELL_GAP)
                  + (slot == 6 and COMPANION_GAP or 0)

        local cell = Widgets.Frame(d, {
            frameType   = "Button",
            size        = { CELL_W, CELL_H },
            point       = { "TOPLEFT", d, "TOPLEFT", x, GRID_Y },
            backdrop    = "TOOLTIP_ROW",
            color       = ns.Config.COLORS.BACKGROUND,
            borderColor = CELL_BORDER,
        })

        cell.portrait = Widgets.PetPortrait(cell, {
            point = { "TOP", 0, PORTRAIT_TOP },
        })

        -- +12 pulls the name up through the ring atlas's transparent lower band so it
        -- doesn't float; nudge in-game if the gap still reads wrong.
        cell.nameText = Widgets.Label(cell, {
            fontSize = Theme.SIZE.SMALL,
            color    = Theme.COLOR.WHITE,
            justify  = "CENTER",
            point    = { "TOP", cell.portrait, "BOTTOM", 0, 12 },
            width    = CELL_W - 8,
            text     = "",
        })

        cell.familyText = Widgets.Label(cell, {
            fontSize = Theme.SIZE.TINY,
            color    = Theme.COLOR.GREY,
            justify  = "CENTER",
            point    = { "TOP", cell.nameText, "BOTTOM", 0, -2 },
            width    = CELL_W - 8,
            text     = "",
        })

        cell.specText = Widgets.Label(cell, {
            fontSize = Theme.SIZE.TINY,
            color    = Theme.COLOR.MUTED,
            justify  = "CENTER",
            point    = { "TOP", cell.familyText, "BOTTOM", 0, -3 },
            width    = CELL_W - 6,
            text     = "",
        })

        -- A plain icon, not a skinned button: the button chrome fought the cell.
        -- Refresh() tints it per state (see LOCK_ICON / LOCK_TINT_* above).
        cell.lock = Widgets.IconButton(cell, {
            texture   = LOCK_ICON,
            highlight = "Interface\\Buttons\\UI-Common-MouseHilight",
            size      = { 18, 18 },
            point     = { "TOPLEFT", 4, -4 },
        })

        -- Same size and art as the Teams panel's per-slot remove button.
        cell.removeButton = Widgets.IconButton(cell, {
            texture   = "Interface\\Buttons\\UI-StopButton",
            highlight = "Interface\\Buttons\\UI-StopButton",
            size      = { 16, 16 },
            alpha     = 0.7,
            point     = { "TOPRIGHT", -3, -3 },
            hidden    = true,
        })

        d.cells[slot] = cell
    end

    -- Gold rule in the companion gap, level with the portraits -- the same divider the
    -- Teams panel draws between slots 5 and 6.
    if slotCount >= 6 then
        local slot5Right = startX + 4 * (CELL_W + CELL_GAP) + CELL_W
        d.dividerLine = Widgets.Texture(d, {
            layer       = "OVERLAY",
            texture     = "Interface\\Buttons\\WHITE8X8",
            size        = { DIVIDER_W, 2 },
            point       = { "CENTER", d, "TOPLEFT",
                            slot5Right + (CELL_GAP + COMPANION_GAP) / 2,
                            GRID_Y + PORTRAIT_TOP - RING / 2 },
            vertexColor = Theme.COLOR.GOLD,
        })
    end

    -- The spec-cycle buttons sit under the grid, aligned to their cells.
    for slot = 1, slotCount do
        local cell = d.cells[slot]
        cell.specButton = Widgets.Button(cell, {
            width      = CELL_W - 6,
            text       = "",
            fontObject = "GameFontNormalSmall",
            point      = { "TOP", cell, "BOTTOM", 0, -3 },
        })
        cell.specButton:SetHeight(20)
    end

    -- Warning line (short roll) and the button row.
    d.warnText = CreateDialogText(d, {
        fontSize = Theme.SIZE.SMALL,
        color    = Theme.COLOR.ORANGE,
        justify  = "CENTER",
        width    = dialogW - 40,
        point    = { "TOP", d, "TOP", 0, warnY },
        text     = "",
    })

    -- Width is the exact button run (M + M + L + M plus three 8px gaps) so the row
    -- centres in the dialog rather than clumping against the left edge.
    local bc = ns.Widgets.Frame(d, {
        size  = { 3 * ns.Theme.CONTROL.BUTTON_W.M + ns.Theme.CONTROL.BUTTON_W.L + 3 * 8, 30 },
        point = { "BOTTOM", 0, 14 },
    })

    d.rerollButton = CreateDialogButton(bc, ns.L("Re-roll"))
    d.rerollButton:SetPoint("LEFT", 0, 0)

    d.applyButton = CreateDialogButton(bc, ns.L("Apply now"))
    d.applyButton:SetPoint("LEFT", d.rerollButton, "RIGHT", 8, 0)

    d.saveButton = CreateDialogButton(bc, ns.L("Save as team..."), ns.Theme.CONTROL.BUTTON_W.L)
    d.saveButton:SetPoint("LEFT", d.applyButton, "RIGHT", 8, 0)

    d.cancelButton = CreateDialogButton(bc, ns.L("Cancel"))
    d.cancelButton:SetPoint("LEFT", d.saveButton, "RIGHT", 8, 0)
    d.cancelButton:SetScript("OnClick", function() d:Hide() end)

    ----------------------------------------------------------------------------
    -- Repaint from state
    ----------------------------------------------------------------------------

    local function SlotLabel(slot)
        return slot == 6 and ns.L("Slot %s (Companion)", slot) or ns.L("Slot %s", slot)
    end

    -- The pool line follows the Owned Pets panel's live filter: Shared/UI.lua calls
    -- this after every re-render while the dialog is open (feedback #2).
    function d.SyncPool()
        d.poolText:SetText(ns.L("Drawing from %d available pets", #ns.TeamRoulette:CurrentPool()))
    end

    d._pickedSlot = nil

    local function Refresh()
        d.SyncPool()
        for slot = 1, slotCount do
            local cell      = d.cells[slot]
            local rec       = state.slots and state.slots[slot]
            local req       = state.template[slot]
            local lockedVal = state.locked[slot]
            local keptEmpty = lockedVal == "empty"
            local isLocked  = lockedVal ~= nil

            -- Spec-cycle button label + colour (independent of whether a pet landed).
            cell.specButton:SetText(req or ns.L("Any"))
            local col = ROULETTE_SPEC_COLOR[req or "Any"] or Theme.COLOR.MUTED
            local fs  = cell.specButton:GetFontString()
            if fs then fs:SetTextColor(col[1], col[2], col[3]) end

            cell:SetBackdropBorderColor(unpack(slot == d._pickedSlot and PICK_BORDER or CELL_BORDER))

            -- Padlock tint by state: gold = unlocked (still in play), silver = locked.
            local lt = cell.lock:GetNormalTexture()
            if lt then
                lt:SetDesaturated(true)
                lt:SetVertexColor(unpack(isLocked and LOCK_TINT_CLOSED or LOCK_TINT_OPEN))
            end

            -- Remove is available only for an unlocked, occupied slot.
            cell.removeButton:SetShown(rec ~= nil and not isLocked)

            if rec then
                cell.portrait:SetPet(rec)
                cell.nameText:SetText(rec.name or "?")
                cell.nameText:SetTextColor(unpack(Theme.COLOR.WHITE))
                cell.familyText:SetText(rec.familyName or "")
                cell.specText:SetText(rec.specName or "")
                cell.specText:SetTextColor(unpack(Theme.COLOR.MUTED))

                cell:SetScript("OnEnter", function(self)
                    ns.Tooltip.Show(self, ns.PetTooltip.Spec(rec, { slotLabel = SlotLabel(slot) }))
                end)
                cell:SetScript("OnLeave", ns.Tooltip.Hide)
            else
                cell.portrait:Clear()
                cell.nameText:SetText(keptEmpty and ns.L("(kept empty)") or ns.L("(empty)"))
                cell.nameText:SetTextColor(unpack(keptEmpty and Theme.COLOR.ORANGE or Theme.COLOR.GREY))
                cell.familyText:SetText("")
                cell.specText:SetText("")
                cell:SetScript("OnEnter", nil)
                cell:SetScript("OnLeave", nil)
            end
        end

        local report = state.report or {}
        if (report.short or 0) > 0 then
            d.warnText:SetText(ns.L("Only %d of %d slots could be filled from the current filters.",
                report.filled or 0, slotCount))
            d.warnText:SetTextColor(unpack(Theme.COLOR.ORANGE))
        else
            d.warnText:SetText(ns.L("Click a pet then a slot to swap. Lock a slot to keep it through re-rolls."))
            d.warnText:SetTextColor(unpack(Theme.COLOR.FAINT))
        end

        -- Apply is always enabled; its tooltip explains when it will not do anything.
        d.applyButton:SetAlpha(ns.state.isStableOpen and 1 or 0.6)
    end

    ----------------------------------------------------------------------------
    -- Wiring
    ----------------------------------------------------------------------------

    -- Click a slot to pick it up, click another to swap the two; a locked slot is
    -- inert (feedback #3). Reuses ns.TeamRoulette's state mutators so this file stays
    -- purely presentational.
    local function CellClicked(slot)
        if state.locked[slot] then return end
        if d._pickedSlot == nil then
            d._pickedSlot = slot
        elseif d._pickedSlot == slot then
            d._pickedSlot = nil
        else
            ns.TeamRoulette:SwapSlots(state, d._pickedSlot, slot)
            d._pickedSlot = nil
        end
        Refresh()
    end

    for slot = 1, slotCount do
        local cell = d.cells[slot]

        cell:SetScript("OnClick", function() CellClicked(slot) end)

        -- A spec change retunes only this slot -- it draws a fresh pet for it and
        -- leaves the rest of the team alone (feedback #4).
        cell.specButton:SetScript("OnClick", function()
            state.template[slot] = NextRouletteSpec(state.template[slot])
            ns.TeamRoulette:RetuneSlot(state, slot)
            Refresh()
        end)

        cell.removeButton:SetScript("OnClick", function()
            ns.TeamRoulette:RemoveSlot(state, slot)
            if d._pickedSlot == slot then d._pickedSlot = nil end
            Refresh()
        end)
        ns.Tooltip.Attach(cell.removeButton, { title = ns.L("Remove this pet") }, {
            onEnter = function(self) self:SetAlpha(1.0) end,
            onLeave = function(self) self:SetAlpha(0.7) end,
        })

        -- Lock freezes the slot as it stands -- a pet or a deliberate empty; clicking
        -- again frees it.
        cell.lock:SetScript("OnClick", function()
            if state.locked[slot] then
                state.locked[slot] = nil
            elseif state.slots and state.slots[slot] then
                state.locked[slot] = state.slots[slot]
            else
                state.locked[slot] = "empty"
            end
            if d._pickedSlot == slot then d._pickedSlot = nil end
            Refresh()
        end)
        ns.Tooltip.Attach(cell.lock, function()
            local v = state.locked[slot]
            if v == "empty" then
                return { title = ns.L("Kept empty - click to let re-rolls fill it") }
            elseif v then
                return { title = ns.L("Locked - kept on re-roll") }
            elseif state.slots and state.slots[slot] then
                return { title = ns.L("Lock this pet in place") }
            end
            return { title = ns.L("Keep this slot empty") }
        end)
    end

    d.rerollButton:SetScript("OnClick", function()
        ns.TeamRoulette:Reroll(state)
        Refresh()
    end)

    d.applyButton:SetScript("OnClick", function()
        if not ns.state.isStableOpen then
            ns.Utils:Msg("WARNING", ns.L("You must be at a Stable Master to apply a team."))
            return
        end
        local ok, err = ns.Teams:ApplySlots(state.slots, ns.L("Team Roulette"))
        if not ok then
            ns.Utils:Msg("ERROR", err or ns.L("Failed to apply team"))
            return
        end
        d:Hide()
    end)
    ns.Tooltip.Attach(d.applyButton, function()
        if ns.state.isStableOpen then
            return { title = ns.L("Move these pets into slots 1-6 now") }
        end
        return { title = ns.L("Visit a Stable Master to apply teams"),
                 titleColor = ns.Theme.COLOR.ORANGE }
    end)

    d.saveButton:SetScript("OnClick", function()
        ns.Dialogs:ShowNameInputDialog({
            title       = ns.L("Save New Team"),
            description = ns.L("Enter a name for your pet team:"),
            onConfirm   = function(name)
                local id, err = ns.Teams:SaveTeam(name, state.slots)
                if id then
                    if ns.TeamsPanel then ns.TeamsPanel:RefreshTeamsList() end
                else
                    ns.Utils:Msg("ERROR", err or ns.L("Failed to save team"))
                end
            end,
        })
    end)

    -- Published so Shared/UI.lua can push filter changes into the open preview, and
    -- cleared on hide so that push is a no-op once the dialog is gone.
    ns.Dialogs.teamRouletteDialog = d
    d:HookScript("OnHide", function()
        if ns.Dialogs.teamRouletteDialog == d then ns.Dialogs.teamRouletteDialog = nil end
    end)

    Refresh()
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
    slots[1] = ns.Teams:SlotRecord(petData)
    ns.Dialogs:ShowNameInputDialog({
        title       = ns.L("New Team Name"),
        description = ns.L("Enter a name for your new team:"),
        onConfirm   = function(teamName)
            local teamId, err = ns.Teams:SaveTeam(teamName, slots)
            if teamId and ns.TeamsPanel then
                ns.TeamsPanel:RefreshTeamsList()
            else
                ns.Utils:Msg("ERROR", err or ns.L("Failed to save team"))
            end
        end,
    })
end

function ns.Dialogs:ShowAddToTeamDialog(petData)
    if not petData then return end

    local teams = ns.Teams:GetTeams()
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
        headerH + (needsScroll and maxBtnAreaH or btnAreaH) + footerH, ns.L("Add Pet to Team"), true)

    d.petInfoText = CreateDialogText(d, {
        fontSize = ns.Theme.SIZE.LABEL,
        color    = ns.Theme.COLOR.GOLD,
        point    = { "TOP", d.title, "BOTTOM", 0, -10 },
        text     = ns.L("Pet: %s", petData.name or ns.L("Unknown")),
    })

    d.description = CreateDialogText(d, {
        point = { "TOP", d.petInfoText, "BOTTOM", 0, -5 },
    })

    -- Bottom button area (shared by both branches)
    local bottom = ns.Widgets.Frame(d, {
        size  = { dialogW - 40, 60 },
        point = { "BOTTOM", d, "BOTTOM", 0, 10 },
    })

    d.createNewButton = CreateDialogButton(bottom, ns.L("Create New Team"), ns.Theme.CONTROL.BUTTON_W.L)
    d.createNewButton:SetScript("OnClick", function()
        d:Hide()
        CreateNewTeamFromPet(petData)
    end)

    d.cancelButton = CreateDialogButton(bottom, ns.L("Cancel"))
    d.cancelButton:SetScript("OnClick", function() d:Hide() end)

    if teamCount == 0 then
        d.description:SetText(ns.L("You don't have any saved teams yet.\nCreate a new team with this pet:"))
        d.createNewButton:SetPoint("CENTER", bottom, "CENTER", 0, 10)
        d.cancelButton:SetPoint("TOP",    d.createNewButton, "BOTTOM", 0, -5)
    else
        d.description:SetText(ns.L("Select a team to add this pet to:"))
        d.createNewButton:SetPoint("TOP", bottom, "TOP", 0, -5)
        d.cancelButton:SetPoint("TOP",    d.createNewButton, "BOTTOM", 0, -5)

        -- Build the team button grid inside a scroll frame or plain frame
        local function PlaceTeamButtons(container)
            d.teamButtons = {}
            for i, team in ipairs(teams) do
                local col = (i-1) % cols
                local row = math.floor((i-1) / cols)

                local btn = ns.Widgets.Button(container, {
                    size       = { btnW, btnH },
                    text       = team.name,
                    fontObject = "GameFontNormalSmall",
                    point      = { "TOPLEFT", 5 + col*(btnW+spacing), -row*(btnH+spacing) },
                    onClick    = function()
                        d:Hide()
                        ns.Dialogs:ShowSelectSlotDialog(team, petData)
                    end,
                })
                table.insert(d.teamButtons, btn)
            end
        end

        if needsScroll then
            local sf = ns.Widgets.Frame(d, {
                frameType = "ScrollFrame",
                template  = "UIPanelScrollFrameTemplate",
                skin      = "scrollframe",
                point     = {
                    { "TOPLEFT",  d, "TOPLEFT",   20, -headerH },
                    { "TOPRIGHT", d, "TOPRIGHT", -40, -headerH },
                    { "BOTTOM",   d, "BOTTOM",     0, footerH + 10 },
                },
            })

            local content = ns.Widgets.Frame(sf, {
                size = { sf:GetWidth() - 20, numRows * btnH + (numRows-1) * spacing },
            })
            sf:SetScrollChild(content)
            PlaceTeamButtons(content)
        else
            local frame = ns.Widgets.Frame(d, {
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

function ns.Dialogs:ShowSelectSlotDialog(team, petData)
    if not team or not petData then return end

    -- Duplicate-pet guard
    if team.slots then
        for slot = 1, 6 do
            if team.slots[slot] and team.slots[slot].petNumber == petData.petNumber then
                local d = CreateBaseDialog("PSMDuplicatePetWarning", 380, 150, ns.L("Duplicate Pet"))
                d.message = CreateDialogText(d, {
                    point   = { "TOP", d.title, "BOTTOM", 0, -15 },
                    width   = 340,
                    justify = "CENTER",
                    text    = ns.L("'%s' is already in team '%s'\nat slot %s.\n\nEach pet can only appear once per team.",
                        petData.name or ns.L("Unknown"), team.name, slot),
                })

                local ok = CreateDialogButton(d, ns.L("OK"))
                ok:SetPoint("BOTTOM", d, "BOTTOM", 0, 15)
                ok:SetScript("OnClick", function() d:Hide() end)
                d:Show()
                return d
            end
        end
    end

    local d = CreateBaseDialog("PSMSelectSlotDialog", 420, 280, ns.L("Select Slot"), true)

    d.teamInfoText = CreateDialogText(d, {
        fontSize = ns.Theme.SIZE.LABEL,
        color    = ns.Theme.COLOR.GOLD,
        point    = { "TOP", d.title, "BOTTOM", 0, -10 },
        text     = ns.L("Team: %s", team.name),
    })

    d.petInfoText = CreateDialogText(d, {
        point = { "TOP", d.teamInfoText, "BOTTOM", 0, -5 },
        text  = ns.L("Pet: %s", petData.name or ns.L("Unknown")),
    })

    d.description = CreateDialogText(d, {
        color = ns.Theme.COLOR.MUTED,
        point = { "TOP", d.petInfoText, "BOTTOM", 0, -5 },
        text  = ns.L("Select a slot to add this pet to:"),
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

        local btn = ns.Widgets.Frame(d, {
            frameType = "Button",
            size      = { btnSize, btnSize },
            point     = { "TOPLEFT", d, "TOPLEFT",
                          startX + col*(btnSize+gap), startY - row*(btnSize+gap) },
            backdrop  = "TOOLTIP",
            backdropOverrides = {
                tileSize = 8, edgeSize = 8,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            },
            color       = ns.Config.COLORS.BACKGROUND,
            borderColor = isOccupied and { 0.3, 0.3, 0.3, 1 } or { 0.3, 0.5, 0.3, 1 },
        })

        ns.Widgets.Label(btn, {
            fontSize = ns.Theme.SIZE.BODY,
            color    = isOccupied and { 0.8, 0.8, 0.8 } or { 0.5, 1.0, 0.5 },
            point    = { "CENTER" },
            text     = ns.L("Slot %s", slot),
        })

        btn:SetScript("OnClick", function()
            d:Hide()
            ns.Dialogs:ConfirmAddToTeam(team, petData, slot)
        end)

        ns.Tooltip.Attach(btn, isOccupied
            and {
                title      = ns.L("Slot %s (Occupied)", slot),
                titleColor = ns.Theme.COLOR.GOLD,
                lines      = { { text = team.slots[slot].name or ns.L("Unknown Pet"),
                                 color = ns.Theme.COLOR.WHITE } },
            }
            or {
                title      = ns.L("Slot %s (Available)", slot),
                titleColor = { 0.5, 1, 0.5 },
            })

        table.insert(d.slotButtons, btn)
    end

    d.cancelButton = CreateDialogButton(d, ns.L("Cancel"))
    d.cancelButton:SetPoint("BOTTOM", d, "BOTTOM", 0, 15)
    d.cancelButton:SetScript("OnClick", function()
        d:Hide()
        ns.Dialogs:ShowAddToTeamDialog(petData)
    end)

    d:Show()
    return d
end

--------------------------------------------------------------------------------
-- CONFIRM ADD / REMOVE
--------------------------------------------------------------------------------

function ns.Dialogs:ConfirmAddToTeam(team, petData, slot)
    if not team or not petData or not slot then return end

    -- Duplicate guard
    if team.slots then
        for i = 1, 6 do
            if team.slots[i] and team.slots[i].petNumber == petData.petNumber then
                ns.Utils:Msg("ERROR", ns.L("Cannot add duplicate pet '%s' to team '%s'. Pet already exists at slot %s.",
                    petData.name or ns.L("Unknown"), team.name, i))
                return
            end
        end
    end

    local slots = {}
    for i = 1, 6 do
        if team.slots and team.slots[i] then slots[i] = ns.Utils.DeepCopy(team.slots[i]) end
    end
    slots[slot] = ns.Teams:SlotRecord(petData)

    local ok, err = ns.Teams:UpdateTeam(team.id, slots)
    if ok then
        if ns.TeamsPanel then ns.TeamsPanel:RefreshTeamsList() end
        ns.Utils:Msg("SUCCESS", ns.L("Added '%s' to team '%s' at slot %s.",
            petData.name or ns.L("Unknown"), team.name, slot))
    else
        ns.Utils:Msg("ERROR", err or ns.L("Failed to add pet to team"))
    end
end

function ns.Dialogs:ConfirmRemoveFromTeam(team, slot, petName)
    if not team or not slot then return end

    local slots = {}
    for i = 1, 6 do
        if team.slots and team.slots[i] and i ~= slot then
            slots[i] = ns.Utils.DeepCopy(team.slots[i])
        end
    end

    local ok, err = ns.Teams:UpdateTeam(team.id, slots)
    if ok then
        if ns.TeamsPanel then ns.TeamsPanel:RefreshTeamsList() end
        ns.Utils:Msg("SUCCESS", ns.L("Removed %s from team '%s'.", petName or ns.L("pet"), team.name))
    else
        ns.Utils:Msg("ERROR", err or ns.L("Failed to remove pet from team"))
    end
end

--------------------------------------------------------------------------------
-- REMOVE FROM TEAM DIALOG
--------------------------------------------------------------------------------

function ns.Dialogs:ShowRemoveFromTeamDialog(petData)
    if not petData then return end

    local teams = ns.Teams:GetTeams()
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
    local d = CreateBaseDialog("PSMRemoveFromTeamDialog", 420, dialogH, ns.L("Remove from Team"), true)

    d.petInfoText = CreateDialogText(d, {
        fontSize = ns.Theme.SIZE.LABEL,
        color    = ns.Theme.COLOR.GOLD,
        point    = { "TOP", d.title, "BOTTOM", 0, -10 },
        text     = ns.L("Pet: %s", petData.name or ns.L("Unknown")),
    })

    d.description = CreateDialogText(d, {
        point = { "TOP", d.petInfoText, "BOTTOM", 0, -5 },
    })

    if count == 0 then
        d.description:SetText(ns.L("This pet is not in any of your saved teams."))
        local ok = CreateDialogButton(d, ns.L("Close"))
        ok:SetPoint("BOTTOM", d, "BOTTOM", 0, 15)
        ok:SetScript("OnClick", function() d:Hide() end)
    else
        d.description:SetText(ns.L("This pet is in %s team(s).\nSelect a team to remove from:", count))

        d.teamButtons = {}
        local btnW, btnH = 200, 28
        for i, match in ipairs(matches) do
            local btn = ns.Widgets.Button(d, {
                size       = { btnW, btnH },
                text       = ns.L("%s (Slot %s)", match.team.name, match.slot),
                fontObject = "GameFontNormalSmall",
                point      = { "TOP", d, "TOP", 0, -100 - (i-1)*(btnH+5) },
                onClick    = function()
                    d:Hide()
                    ns.Dialogs:ConfirmRemoveFromTeam(match.team, match.slot, petData.name)
                end,
            })
            table.insert(d.teamButtons, btn)
        end

        d.cancelButton = CreateDialogButton(d, ns.L("Cancel"))
        d.cancelButton:SetPoint("BOTTOM", d, "BOTTOM", 0, 15)
        d.cancelButton:SetScript("OnClick", function() d:Hide() end)
    end

    d:Show()
    return d
end
