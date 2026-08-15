-- Core/RowManager.lua
-- Unified row creation and management for PetStableManagement
-- Provides a common foundation for both OwnedPets and ModelsBrowser

local addonName = "PetStableManagement"

_G.PSM = _G.PSM or {}
local PSM = _G.PSM

PSM.RowManager = {}

-- What the mouse can do to a 3D model. Every view that shows one repeats this, so it
-- lives with the code that installs the handlers it describes -- if the interaction
-- changes, the text sitting next to it is hard to miss.
PSM.RowManager.MODEL_HINTS =
    "Left-click and drag to rotate\n" ..
    "Right-click and drag to move (left/right, up/down)\n" ..
    "Scroll to zoom"

-- ─── Shared update frames ────────────────────────────────────────────────────

-- An invisible, parentless ticker: nothing to draw, so not a widget. PSM.CreateFrame
-- is Core.lua's alias, which is what the headless tests can stub.
local function EnsureUpdateFrame(key, onUpdate)
    if PSM[key] then return PSM[key] end
    local f = PSM.CreateFrame("Frame")
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

-- Stop both tickers from following a model. Call before a model is hidden, pooled,
-- rebound to another pet, or otherwise stops being the thing the cursor is dragging.
--
-- **This exists because eight call sites wrote it by hand and five of them cleared only
-- RotationFrame.** A model released mid-right-drag stayed in MovementFrame.activeModels
-- for the rest of the session, iterated on every OnUpdate and never collected. The guards
-- had drifted too -- three sites tested `PSM.RotationFrame and PSM.RotationFrame.activeModels`,
-- one tested nothing, and MovementFrame was checked in two of them.
--
-- Public because the Models Browser needs it: PetRoulette was reaching straight into
-- `PSM.RotationFrame.activeModels`, which is a core internal and not on the published
-- surface. A service is the right answer to that, not a wider surface.
function PSM.RowManager:ReleaseModel(model)
    if not model then return end
    model.isRotating, model.isMoving = false, false
    RotationFrame.activeModels[model] = nil
    MovementFrame.activeModels[model] = nil
end

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

    -- A function spec: the reorder hint depends on whether the stable is open and
    -- whether this model is a slotted pet, both of which change while the row lives.
    PSM.Tooltip.Attach(model,
        function(self)
            local tip = PSM.RowManager.MODEL_HINTS
            if PSM.state and PSM.state.isStableOpen
                and self.petData and self.petData.slotID then
                tip = tip .. "\nShift/Ctrl + drag to reorder slot"
            end
            return { title = tip }
        end,
        {
            onEnter = function(self) PSM.RowManager:ShowHoverButtons(self) end,
            onLeave = function(self) PSM.RowManager:HideHoverButtons(self) end,
        }
    )
end

-- ─── Hover buttons ───────────────────────────────────────────────────────────
--
-- The overlay buttons fade in together on hover. Views that want their own model
-- tooltip have to re-attach OnEnter/OnLeave, which drops the pair installed above,
-- so both halves are public: a view supplies the tooltip and reuses these. Hand-
-- written copies in the views each hardcoded the four button fields, which meant a
-- fifth overlay button would have appeared in some views and not others.

function PSM.RowManager:ShowHoverButtons(model)
    for _, b in ipairs(model.hoverButtons or {}) do
        -- Team buttons only show for player-owned pets.
        local teamButton = b == model.addToTeamButton or b == model.removeFromTeamButton
        if not teamButton or model.isOwnedByPlayer then b:Show() end
    end
end

-- Keep a button visible if the mouse moved directly onto it from the model.
function PSM.RowManager:HideHoverButtons(model)
    for _, b in ipairs(model.hoverButtons or {}) do
        if not b:IsMouseOver() then b:Hide() end
    end
end

-- ─── Button factory ───────────────────────────────────────────────────────────

-- The small affordances that fade in over a model on hover: reset view, magnify,
-- add/remove from team. Deliberately not skinned -- ElvUI's HandleButton strips
-- exactly the textures these are made of.
--
-- Was ten positional parameters, four of which were anchor components. Named now:
-- `MakeOverlayButton(parent, model, 16, "TOPRIGHT", "TOPRIGHT", -2, -2, tex, tex)`
-- gives a reader no way to check an argument without counting commas.
local OVERLAY_ALPHA, OVERLAY_ALPHA_HOVER = 0.7, 1.0

local function MakeOverlayButton(parent, model, opts)
    local btn = PSM.Widgets.IconButton(parent, {
        size      = { opts.size, opts.size },
        point     = { opts.point, model, opts.relPoint, opts.x, opts.y },
        level     = model:GetFrameLevel() + 2,
        texture   = opts.texture,
        highlight = opts.highlight,
        pushed    = opts.pushed,
        alpha     = OVERLAY_ALPHA,
        hidden    = true,
    })

    -- The brighten and the tooltip are one hover behaviour, so they are attached
    -- together -- two separate OnEnter handlers would mean the last one wins.
    PSM.Tooltip.Attach(btn, opts.tooltip, {
        onEnter = function(self) self:SetAlpha(OVERLAY_ALPHA_HOVER) end,
        onLeave = function(self) self:SetAlpha(OVERLAY_ALPHA)       end,
    })
    return btn
end

local function RegisterHoverButton(model, btn)
    model.hoverButtons = model.hoverButtons or {}
    table.insert(model.hoverButtons, btn)
end

local function CreateResetButton(parent, model)
    local btn = MakeOverlayButton(parent, model, {
        size      = 16,
        point     = "TOPRIGHT", relPoint = "TOPRIGHT", x = -2, y = -2,
        texture   = "Interface\\Buttons\\UI-RefreshButton",
        highlight = "Interface\\Buttons\\UI-RefreshButton",
        tooltip   = "Reset View",
    })

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
        PSM.RowManager:ReleaseModel(model)

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
    local btn = MakeOverlayButton(parent, model, {
        size    = 16,
        point   = "TOPRIGHT", relPoint = "TOPRIGHT", x = -20, y = -2,
        texture = "Interface\\Icons\\INV_Misc_Spyglass_02",
        tooltip = "Magnify Model",
    })

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
    local btn = MakeOverlayButton(parent, model, {
        size      = 16,
        point     = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -2, y = 2,
        texture   = "Interface\\Buttons\\UI-PlusButton-UP",
        highlight = "Interface\\Buttons\\UI-PlusButton-Highlight",
        pushed    = "Interface\\Buttons\\UI-PlusButton-Down",
        tooltip   = "Add to Team",
    })

    btn:SetScript("OnClick", function()
        if model.petData then PSM.TeamDialogs:ShowAddToTeamDialog(model.petData) end
    end)

    model.addToTeamButton = btn
    RegisterHoverButton(model, btn)
    return btn
end

local function CreateRemoveFromTeamButton(parent, model)
    local btn = MakeOverlayButton(parent, model, {
        size      = 16,
        point     = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -20, y = 2,
        texture   = "Interface\\Buttons\\UI-MinusButton-UP",
        highlight = "Interface\\Buttons\\UI-MinusButton-Highlight",
        pushed    = "Interface\\Buttons\\UI-MinusButton-Down",
        tooltip   = "Remove from Team",
    })

    btn:SetScript("OnClick", function()
        if model.petData then PSM.TeamDialogs:ShowRemoveFromTeamDialog(model.petData) end
    end)

    model.removeFromTeamButton = btn
    RegisterHoverButton(model, btn)
    return btn
end

-- ─── Row construction ─────────────────────────────────────────────────────────

-- The row's own hairline rule and border tint, distinct from PSM.Theme.FILL.SEPARATOR
-- (which is bluer and opaque). Kept as-is so this pass does not restyle rows.
local ROW_RULE = { 0.3, 0.3, 0.3, 0.5 }

-- Applied both at construction and again by UpdateBackgroundColor, which restores it
-- after a spec-atlas background is cleared. One definition for both.
local function ApplyRowBackdrop(row)
    PSM.Widgets.Backdrop(row, "TOOLTIP", {
        color       = PSM.Config.COLORS.BACKGROUND,
        borderColor = ROW_RULE,
    })
end

local function CreateSeparator(row)
    return PSM.Widgets.Line(row, {
        layer = "BORDER",
        color = ROW_RULE,
        point = {
            { "BOTTOMLEFT",  row, "BOTTOMLEFT",  0, 0 },
            { "BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0 },
        },
    })
end

local function CreateBackground(row, useBackdrop)
    if useBackdrop then ApplyRowBackdrop(row) end

    -- Clip children to row bounds
    row:SetClipsChildren(true)

    -- Spec atlas background
    row.specBg = PSM.Widgets.Texture(row, {
        layer     = "BACKGROUND",
        sublayer  = -1,
        allPoints = true,
        hidden    = true,
    })
end

function PSM.RowManager:CreateBaseRow(parent, config)
    config = config or {}
    local useBackdrop   = config.useBackdropTemplate or false
    local showMagnify   = config.showMagnifyButton ~= false
    local showTeamBtns  = config.showTeamButtons or false

    local Widgets = PSM.Widgets

    local row = Widgets.Frame(parent, {
        template = useBackdrop and "BackdropTemplate" or nil,
        size     = {
            config.width  or PSM.Config.DEFAULT_ROW_WIDTH,
            config.height or PSM.Config.ROW_HEIGHT,
        },
    })

    CreateBackground(row, useBackdrop)
    CreateSeparator(row)

    -- Model
    local modelSize = config.modelSize or PSM.Config.MODEL_SIZE
    row.model = Widgets.Frame(row, {
        frameType = "PlayerModel",
        size      = { modelSize, modelSize },
        point     = { "LEFT", row, "LEFT", 2, 0 },
    })
    row.model.rotation   = math.pi * 2
    row.model.zoom       = 1.0
    row.model.isRotating = false
    row.model.lastCamDistanceScale = 1.0 / GetGlobalZoom()
    row.model:SetRotation(row.model.rotation)
    SetCamDistanceScaleIfChanged(row.model, row.model.lastCamDistanceScale)

    SetupModelInteraction(row.model)
    CreateResetButton(row, row.model)
    if showMagnify  then CreateMagnifyButton(row, row.model) end
    if showTeamBtns then
        CreateAddToTeamButton(row, row.model)
        CreateRemoveFromTeamButton(row, row.model)
    end

    -- Favorite button
    local favBtn = Widgets.IconButton(row, {
        size      = { 16, 16 },
        point     = { "TOPLEFT", row.model, "TOPLEFT", 0, -2 },
        level     = row.model:GetFrameLevel() + 2,
        texture   = "Interface\\Common\\ReputationStar",
        highlight = "Interface\\Common\\ReputationStar",
        hidden    = true,
        tooltip   = "Favorite/Unfavorite",
    })

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
    row.favoriteButton  = favBtn
    row._setFavTexCoords = SetFavTexCoords  -- expose for UpdateFavoriteButton

    -- Icon fallback
    row.icon = Widgets.Texture(row, {
        layer  = "ARTWORK",
        size   = { PSM.Config.ICON_SIZE, PSM.Config.ICON_SIZE },
        point  = { "LEFT", row, "LEFT", 2, 0 },
        hidden = true,
    })

    -- Label
    row.text = Widgets.Label(row, {
        fontSize = PSM.Theme.SIZE.SMALL,
        justify  = "LEFT",
        justifyV = "MIDDLE",
        width    = PSM.Config.TEXT_WIDTH,
        point    = { "LEFT", row.model, "RIGHT", 6, 0 },
    })

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
            if row.SetBackdrop then ApplyRowBackdrop(row) end  -- restore what "simple" means
        else
            row.specBg:Hide()
            if row.SetBackdrop then row:SetBackdrop(nil) end
        end
    end

    -- Duplicate border indicator
    if not row.dupBorder then
        -- Border with no fill, so the row's own background stays visible through it.
        row.dupBorder = PSM.Widgets.Frame(row, {
            backdrop  = "BORDER_ONLY",
            allPoints = true,
            level     = row:GetFrameLevel() + 2,
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
        PSM.RowManager:ReleaseModel(row.model)
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