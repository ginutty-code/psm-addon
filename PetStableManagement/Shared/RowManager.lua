-- Core/RowManager.lua
-- Unified row creation and management for PetStableManagement
-- Provides a common foundation for both OwnedPets and ModelsBrowser

local addonName = "PetStableManagement"

_G.PSM = _G.PSM or {}
local PSM = _G.PSM

PSM.RowManager = {}

-- ─── Shared update frames ────────────────────────────────────────────────────

local function EnsureUpdateFrame(key, onUpdate)
    if PSM[key] then return PSM[key] end
    local f = CreateFrame("Frame")
    f.activeModels = {}
    f:SetScript("OnUpdate", onUpdate)
    PSM[key] = f
    return f
end

local RotationFrame = EnsureUpdateFrame("RotationFrame", function(self)
    for model in pairs(self.activeModels) do
        if model.isRotating and model.lastX then
            local x = GetCursorPosition()
            model.rotation = model.rotation + (x - model.lastX) * 0.01
            model:SetRotation(model.rotation)
            model.lastX = x
        end
    end
end)

local MovementFrame = EnsureUpdateFrame("MovementFrame", function(self)
    for model in pairs(self.activeModels) do
        if model.isMoving and model.lastX and model.lastY then
            local scale = UIParent:GetEffectiveScale()
            local x, y = GetCursorPosition()
            x, y = x / scale, y / scale
            local s = 0.01
            model.posY = model.posY + (x - model.lastX) * s
            model.posZ = model.posZ + (y - model.lastY) * s
            model:SetPosition(model.posX, model.posY, model.posZ)
            model.lastX, model.lastY = x, y
        end
    end
end)

-- ─── Helpers ─────────────────────────────────────────────────────────────────

local function GetSettings()
    return PetStableManagementDB.settings
end

local function GetGlobalZoom()
    return GetSettings().modelZoom or PSM.Config.DEFAULT_MODEL_ZOOM
end

local function SetCamDistanceScaleIfChanged(model, scale)
    if model.lastCamDistanceScale ~= scale then
        model.lastCamDistanceScale = scale
        model:SetCamDistanceScale(scale)
    end
end

-- Returns the key used to persist per-model view state
local function ViewKey(model)
    if model.petData and model.petData.guid then
        return "pet_" .. model.petData.guid
    end
    return model.displayId
end

local function SaveViewSettings(model)
    if model.displayId and PSM.Data and PSM.Data.SaveSettings then
        PSM.Data:SaveSettings()
    end
end

local function PersistView(model, patch)
    if not model.displayId then return end
    local vk = ViewKey(model)
    PSM.state.modelViews[vk] = PSM.state.modelViews[vk] or {}
    for k, v in pairs(patch) do
        PSM.state.modelViews[vk][k] = v
    end
    SaveViewSettings(model)
end

-- ─── Model interaction ────────────────────────────────────────────────────────

local function SetupModelInteraction(model)
    model:EnableMouse(true)
    model:EnableMouseWheel(true)

    model:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            if (IsShiftKeyDown() or IsControlKeyDown())
                and PSM.DragDrop and PSM.DragDrop.StartDrag then
                PSM.DragDrop:StartDrag(self.petData, self)
                return
            end
            self.isRotating = true
            self.lastX = GetCursorPosition()
            RotationFrame.activeModels[self] = true
        elseif button == "RightButton" then
            self.isMoving = true
            local scale = UIParent:GetEffectiveScale()
            local x, y = GetCursorPosition()
            self.lastX, self.lastY = x / scale, y / scale
            self.posX, self.posY, self.posZ = self:GetPosition()
            if not self.posX then self.posX, self.posY, self.posZ = 0, 0, 0 end
            MovementFrame.activeModels[self] = true
        end
    end)

    model:SetScript("OnMouseUp", function(self, button)
        if PSM.DragDrop and PSM.DragDrop.dragging then
            PSM.DragDrop:EndDrag()
            return
        end
        if button == "LeftButton" then
            self.isRotating = false
            RotationFrame.activeModels[self] = nil
            PersistView(self, { rotation = self.rotation, zoom = self.zoom })
        elseif button == "RightButton" then
            self.isMoving = false
            MovementFrame.activeModels[self] = nil
            PersistView(self, { position = { self:GetPosition() } })
        end
    end)

    model:SetScript("OnMouseWheel", function(self, delta)
        self.zoom = math.max(0.1, math.min(2.0, (self.zoom or 1.0) + delta * 0.05))
        SetCamDistanceScaleIfChanged(self, 1.2 / self.zoom / GetGlobalZoom())
        PersistView(self, { zoom = self.zoom })
    end)

    -- Buttons to toggle on hover (populated later)
    local function refreshButtons(self, show)
        for _, b in ipairs(self.hoverButtons or {}) do
            -- Team buttons only show for player-owned pets
            if b == self.addToTeamButton or b == self.removeFromTeamButton then
                if self.isOwnedByPlayer then
                    if show then b:Show() else b:Hide() end
                end
            else
                if show then b:Show() else b:Hide() end
            end
        end
    end

    model:SetScript("OnEnter", function(self)
        refreshButtons(self, true)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local tip = "Left-click and drag to rotate\nRight-click and drag to move (left/right, up/down)\nScroll to zoom"
        if PSM.state and PSM.state.isStableOpen
            and self.petData and self.petData.slotID then
            tip = tip .. "\nShift/Ctrl + drag to reorder slot"
        end
        GameTooltip:SetText(tip)
        GameTooltip:Show()
    end)

    model:SetScript("OnLeave", function(self)
        -- Keep button visible if mouse moved directly onto it
        for _, b in ipairs(self.hoverButtons or {}) do
            if not b:IsMouseOver() then b:Hide() end
        end
        GameTooltip:Hide()
    end)
end

-- ─── Button factory ───────────────────────────────────────────────────────────

local function MakeOverlayButton(parent, model, size, anchorPoint, anchorRelPoint, offX, offY, normal, highlight, pushed)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)
    btn:SetPoint(anchorPoint, model, anchorRelPoint, offX, offY)
    btn:SetFrameLevel(model:GetFrameLevel() + 2)
    btn:SetNormalTexture(normal)
    btn:SetAlpha(0.7)
    if highlight then btn:SetHighlightTexture(highlight) end
    if pushed   then btn:SetPushedTexture(pushed) end
    btn:Hide()

    btn:SetScript("OnEnter", function(self)
        self:SetAlpha(1.0)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltipText or "")
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetAlpha(0.7)
        GameTooltip:Hide()
    end)
    return btn
end

local function RegisterHoverButton(model, btn)
    model.hoverButtons = model.hoverButtons or {}
    table.insert(model.hoverButtons, btn)
end

local function CreateResetButton(parent, model)
    local btn = MakeOverlayButton(parent, model, 16,
        "TOPRIGHT", "TOPRIGHT", -2, -2,
        "Interface\\Buttons\\UI-RefreshButton",
        "Interface\\Buttons\\UI-RefreshButton")
    btn.tooltipText = "Reset View"

    btn:SetScript("OnClick", function()
        local s = GetSettings()
        local gz   = s.modelZoom             or PSM.Config.DEFAULT_MODEL_ZOOM
        local va   = s.modelViewAngle        or PSM.Config.DEFAULT_MODEL_VIEW_ANGLE
        local vp   = s.modelVerticalPosition or PSM.Config.DEFAULT_MODEL_VERTICAL_POSITION
        local hp   = s.modelHorizontalPosition or PSM.Config.DEFAULT_MODEL_HORIZONTAL_POSITION

        model.rotation = math.rad(va)
        model.zoom     = 1.0
        model:SetRotation(model.rotation)
        model:SetPosition(0, hp * 2.0, vp * 2.0)
        SetCamDistanceScaleIfChanged(model, 1.0 / gz)
        model.isRotating, model.isMoving = false, false
        RotationFrame.activeModels[model] = nil
        MovementFrame.activeModels[model] = nil

        if model.displayId then
            PSM.state.modelViews[ViewKey(model)] = {
                rotation = model.rotation,
                zoom     = model.zoom,
                position = { 0, hp * 2.0, vp * 2.0 },
            }
            SaveViewSettings(model)
        end
    end)

    model.resetButton = btn
    RegisterHoverButton(model, btn)
    return btn
end

local function CreateMagnifyButton(parent, model)
    local btn = MakeOverlayButton(parent, model, 16,
        "TOPRIGHT", "TOPRIGHT", -20, -2,
        "Interface\\Icons\\INV_Misc_Spyglass_02")
    btn.tooltipText = "Magnify Model"

    btn:SetScript("OnClick", function()
        if PSM.PopUpManager and PSM.PopUpManager.ShowMagnificationPopup then
            PSM.PopUpManager:ShowMagnificationPopup(model.displayId, model.petData)
        end
    end)

    model.magnifyButton = btn
    RegisterHoverButton(model, btn)
    return btn
end

local function CreateAddToTeamButton(parent, model)
    local btn = MakeOverlayButton(parent, model, 16,
        "BOTTOMRIGHT", "BOTTOMRIGHT", -2, 2,
        "Interface\\Buttons\\UI-PlusButton-UP",
        "Interface\\Buttons\\UI-PlusButton-Highlight",
        "Interface\\Buttons\\UI-PlusButton-Down")
    btn.tooltipText = "Add to Team"

    btn:SetScript("OnClick", function()
        if model.petData then PSM.TeamDialogs:ShowAddToTeamDialog(model.petData) end
    end)

    model.addToTeamButton = btn
    RegisterHoverButton(model, btn)
    return btn
end

local function CreateRemoveFromTeamButton(parent, model)
    local btn = MakeOverlayButton(parent, model, 16,
        "BOTTOMRIGHT", "BOTTOMRIGHT", -20, 2,
        "Interface\\Buttons\\UI-MinusButton-UP",
        "Interface\\Buttons\\UI-MinusButton-Highlight",
        "Interface\\Buttons\\UI-MinusButton-Down")
    btn.tooltipText = "Remove from Team"

    btn:SetScript("OnClick", function()
        if model.petData then PSM.TeamDialogs:ShowRemoveFromTeamDialog(model.petData) end
    end)

    model.removeFromTeamButton = btn
    RegisterHoverButton(model, btn)
    return btn
end

-- ─── Row construction ─────────────────────────────────────────────────────────

local function CreateSeparator(row)
    local sep = row:CreateTexture(nil, "BORDER")
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT",  row, "BOTTOMLEFT",  0, 0)
    sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    sep:SetColorTexture(0.3, 0.3, 0.3, 0.5)
    return sep
end

local function CreateBackground(row, useBackdrop)
    if useBackdrop then
        row:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        row:SetBackdropColor(unpack(PSM.Config.COLORS.BACKGROUND))
        row:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)
    end

    -- Clip children to row bounds
    row:SetClipsChildren(true)

    -- Spec atlas background
    row.specBg = row:CreateTexture(nil, "BACKGROUND", nil, -1)
    row.specBg:SetAllPoints(row)
    row.specBg:Hide()
end

function PSM.RowManager:CreateBaseRow(parent, config)
    config = config or {}
    local useBackdrop   = config.useBackdropTemplate or false
    local showMagnify   = config.showMagnifyButton ~= false
    local showTeamBtns  = config.showTeamButtons or false

    local row = CreateFrame("Frame", nil, parent, useBackdrop and "BackdropTemplate" or nil)
    row:SetSize(config.width or PSM.Config.DEFAULT_ROW_WIDTH,
                config.height or PSM.Config.ROW_HEIGHT)

    CreateBackground(row, useBackdrop)
    CreateSeparator(row)

    -- Model
    local modelSize = config.modelSize or PSM.Config.MODEL_SIZE
    row.model = CreateFrame("PlayerModel", nil, row)
    row.model:SetSize(modelSize, modelSize)
    row.model:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.model.rotation   = math.pi * 2
    row.model.zoom       = 1.0
    row.model.lastCamDistanceScale = 1.0 / GetGlobalZoom()
    row.model:SetRotation(row.model.rotation)
    SetCamDistanceScaleIfChanged(row.model, row.model.lastCamDistanceScale)
    row.model.rotation   = math.pi * 2
    row.model.zoom       = 1.0
    row.model.isRotating = false

    SetupModelInteraction(row.model)
    CreateResetButton(row, row.model)
    if showMagnify  then CreateMagnifyButton(row, row.model) end
    if showTeamBtns then
        CreateAddToTeamButton(row, row.model)
        CreateRemoveFromTeamButton(row, row.model)
    end

    -- Favorite button
    local favBtn = CreateFrame("Button", nil, row)
    favBtn:SetSize(16, 16)
    favBtn:SetPoint("TOPLEFT", row.model, "TOPLEFT", 0, -2)
    favBtn:SetFrameLevel(row.model:GetFrameLevel() + 2)
    favBtn:SetNormalTexture("Interface\\Common\\ReputationStar")
    favBtn:SetHighlightTexture("Interface\\Common\\ReputationStar")
    favBtn:Hide()

    local function SetFavTexCoords(isFav)
        local u = isFav and 0 or 0.5
        favBtn:GetNormalTexture():SetTexCoord(u, u + 0.5, 0, 0.5)
        favBtn:GetHighlightTexture():SetTexCoord(u, u + 0.5, 0, 0.5)
    end

    favBtn:SetScript("OnClick", function()
        if not row.displayId then return end
        local isFav = not PSM.state.favoriteModels[row.displayId]
        PSM.state.favoriteModels[row.displayId] = isFav
        SetFavTexCoords(isFav)
        if PSM.Data and PSM.Data.SaveSettings then PSM.Data:SaveSettings() end
        local panel = PSM.state.modelsPanel
        if panel and panel.showFavorites then
            PSM.ModelsDataLoader:LoadModelsForSelectedFamilies()
        end
    end)
    favBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Favorite/Unfavorite")
        GameTooltip:Show()
    end)
    favBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.favoriteButton  = favBtn
    row._setFavTexCoords = SetFavTexCoords  -- expose for UpdateFavoriteButton

    -- Icon fallback
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(PSM.Config.ICON_SIZE, PSM.Config.ICON_SIZE)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.icon:Hide()

    -- Label
    row.text = row:CreateFontString(nil, "OVERLAY")
    row.text:SetFont("Fonts\\FRIZQT__.TTF", 10)
    row.text:SetPoint("LEFT", row.model, "RIGHT", 6, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetJustifyV("MIDDLE")
    row.text:SetWidth(PSM.Config.TEXT_WIDTH)

    row.config = config
    return row
end

-- ─── Public update helpers ────────────────────────────────────────────────────

function PSM.RowManager:UpdateModelDisplay(row, displayID, icon, petData)
    if displayID and displayID > 0 then
        row.model:SetDisplayInfo(displayID)
        row.model.displayId = displayID
        row.model.petData   = petData
        row.model:Show()
        row.icon:Hide()

        local currentCharKey = PSM.GetCharacterKey()
        row.model.isOwnedByPlayer = petData and petData.tamer == currentCharKey

        if GetSettings().stopAnimation then
            row.model:FreezeAnimation(0, 0, 0)
        else
            row.model:SetAnimation(0)
        end
        row.model:SetCamera(0)

    local vk   = ViewKey(row.model)
    local view = PSM.state.modelViews and PSM.state.modelViews[vk]
    local gz   = GetGlobalZoom()
    local s    = GetSettings()
    local vp   = s.modelVerticalPosition    or PSM.Config.DEFAULT_MODEL_VERTICAL_POSITION
    local hp   = s.modelHorizontalPosition  or PSM.Config.DEFAULT_MODEL_HORIZONTAL_POSITION
    local va   = s.modelViewAngle           or PSM.Config.DEFAULT_MODEL_VIEW_ANGLE

    if view then
        row.model.rotation = view.rotation or math.rad(va)
        row.model.zoom     = view.zoom     or 1.0
        row.model:SetRotation(row.model.rotation)
        SetCamDistanceScaleIfChanged(row.model, 1.2 / (row.model.zoom * gz))
        row.model:SetPosition(unpack(view.position or { 0, hp * 2.0, vp * 2.0 }))
    else
        row.model.rotation = math.rad(va)
        row.model.zoom     = 1.0
        row.model:SetRotation(row.model.rotation)
        row.model:SetPosition(0, hp * 2.0, vp * 2.0)
        SetCamDistanceScaleIfChanged(row.model, 1.2 / gz)
    end
    else
        row.icon:SetTexture(icon or "")
        row.icon:Show()
        row.model:Hide()
        row.model.petData         = nil
        row.model.isOwnedByPlayer = false
    end
end

function PSM.RowManager:UpdateBackgroundColor(row, isSameCharDup, isCrossCharDup, isOwned, specialization, backgroundType)
    backgroundType = backgroundType or GetSettings().backgroundType or PSM.Config.DEFAULT_BACKGROUND_TYPE

    -- Clear any color overlay
    if row.bg then
        row.bg:SetColorTexture(0, 0, 0, 0)  -- fully transparent
    elseif row.SetBackdropColor then
        row:SetBackdropColor(0, 0, 0, 0)    -- fully transparent
    end

    -- Background handling
    if row.specBg then
        if backgroundType == "stablemaster" and specialization then
            row.specBg:SetAtlas(PSM.Config.SPEC_BACKGROUND_ATLAS[specialization] or PSM.Config.SPEC_BACKGROUND_ATLAS.Ferocity)
            row.specBg:SetVertexColor(1, 1, 1, 1)  -- Reset vertex color
            row.specBg:Show()
            if row.SetBackdrop then row:SetBackdrop(nil) end  -- Hide backdrop for spec bg
        elseif backgroundType == "custom" and specialization then
            row.specBg:SetTexture(PSM.Config.SPEC_BACKGROUND_CUSTOM[specialization] or PSM.Config.SPEC_BACKGROUND_CUSTOM.Ferocity)
            row.specBg:SetVertexColor(1, 1, 1, 1)  -- Reset vertex color
            row.specBg:Show()
            if row.SetBackdrop then row:SetBackdrop(nil) end  -- Hide backdrop for spec bg
        elseif backgroundType == "simple" then
            row.specBg:Hide()
            if row.SetBackdrop then  -- Restore backdrop for simple
                row:SetBackdrop({
                    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    tile = true, tileSize = 16, edgeSize = 16,
                    insets = { left = 4, right = 4, top = 4, bottom = 4 },
                })
                row:SetBackdropColor(unpack(PSM.Config.COLORS.BACKGROUND))
                row:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)
            end
        else
            row.specBg:Hide()
            if row.SetBackdrop then row:SetBackdrop(nil) end
        end
    end

    -- Duplicate border indicator
    if not row.dupBorder then
        row.dupBorder = CreateFrame("Frame", nil, row, "BackdropTemplate")
        row.dupBorder:SetAllPoints()
        row.dupBorder:SetFrameLevel(row:GetFrameLevel() + 2)
        row.dupBorder:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 16,
            insets   = { left = 4, right = 4, top = 4, bottom = 4 },
        })
    end

    if isSameCharDup then
        row.dupBorder:SetBackdropBorderColor(unpack(PSM.Config.COLORS.BORDER_DUPLICATE))
        row.dupBorder:Show()
    elseif isCrossCharDup then
        row.dupBorder:SetBackdropBorderColor(unpack(PSM.Config.COLORS.BORDER_DUPLICATE_CROSS_CHAR))
        row.dupBorder:Show()
    elseif isOwned then
        row.dupBorder:SetBackdropBorderColor(unpack(PSM.Config.COLORS.BORDER_OWNED_SINGLE))
        row.dupBorder:Show()
    else
        row.dupBorder:Hide()
    end
end

function PSM.RowManager:HideRow(row)
    if not row then return end
    row:Hide()
    if row.model then
        row.model:SetDisplayInfo(0)
        row.model:Hide()
        row.model.isRotating = false
        RotationFrame.activeModels[row.model] = nil
    end
    for _, key in ipairs({ "icon", "abilitiesHeader", "abilitiesList", "separator" }) do
        if row[key] then
            if key == "icon" or key == "separator" then row[key]:Hide()
            elseif row[key].SetText then row[key]:Hide(); row[key]:SetText("")
            else row[key]:Hide()
            end
        end
    end
    if row.text then row.text:SetText("") end
    if row.nameText then row.nameText:SetText("") end
    if row.infoText then row.infoText:SetText("") end
    if row.npcNamesText then row.npcNamesText:SetText("") end
    if row.customElements then
        for _, el in pairs(row.customElements) do
            if el.Hide then el:Hide() end
        end
    end
    -- Hide drag drop indicator
    if row._dropIndicator then
        row._dropIndicator:Hide()
        row._dropIndicator:ClearAllPoints()
        row._dropIndicator = nil
    end
end

function PSM.RowManager:EnsureRow(i, parent, config)
    if not i or i < 1 then return nil end
    PSM.state.rows = PSM.state.rows or {}
    if PSM.state.rows[i] then return PSM.state.rows[i] end
    if not parent then
        print(PSM.Config.MESSAGES.PANEL_SHOW_FAILED)
        return nil
    end
    local row = self:CreateBaseRow(parent, config)
    PSM.state.rows[i] = row
    return row
end

function PSM.RowManager:UpdateFavoriteButton(row, displayId)
    if not row or not row.favoriteButton then return end
    row.displayId = displayId
    row.favoriteButton:Show()
    row._setFavTexCoords(PSM.state.favoriteModels[displayId])
end

function PSM.RowManager:HideFavoriteButton(row)
    if row and row.favoriteButton then row.favoriteButton:Hide() end
end

-- Account-wide, independent of who is currently logged in: a pet is a
-- "same-char" duplicate if its OWNING character (pet.tamer) has 2+ copies of
-- this model, and a "cross-char" duplicate if the model also exists on a
-- different character. Previously this compared against the logged-in
-- character instead of the row's own owner, so duplicates only ever showed up
-- while playing a character that itself owned copies.
function PSM.RowManager:CheckDuplicates(pet, allGroups)
    local key = PSM.Utils:GetPetDuplicateKey(pet)
    local group = allGroups and allGroups[key]
    if not group or #group <= 1 then return false, false end

    local sameTamerCount, hasOtherTamer = 0, false
    for _, p in ipairs(group) do
        if p.tamer == pet.tamer then sameTamerCount = sameTamerCount + 1
        else                          hasOtherTamer  = true end
    end

    if sameTamerCount > 1 then return true, false end
    if hasOtherTamer then return false, true end
    return false, false
end