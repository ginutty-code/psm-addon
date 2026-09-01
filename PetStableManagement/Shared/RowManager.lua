-- Core/RowManager.lua
-- Unified row creation and management for PetStableManagement
-- Provides a common foundation for both OwnedPets and ModelsBrowser

local _, ns = ...

ns.RowManager = {}

-- What the mouse can do to a 3D model. Every view that shows one repeats this, so it
-- lives with the code that installs the handlers it describes -- if the interaction
-- changes, the text sitting next to it is hard to miss.
ns.RowManager.MODEL_HINTS =
    ns.L("Left-click and drag to rotate") .. "\n" ..
    ns.L("Right-click and drag to move (left/right, up/down)") .. "\n" ..
    ns.L("Scroll to zoom")

-- ─── Shared update frames ────────────────────────────────────────────────────

-- An invisible, parentless ticker: nothing to draw, so not a widget. ns.CreateFrame
-- is Core.lua's alias, which is what the headless tests can stub. The memo is keyed on
-- the namespace with bracket syntax, so a dot-syntax grep for `ns.` will not find it.
local function EnsureUpdateFrame(key, onUpdate)
    if ns[key] then return ns[key] end
    local f = ns.CreateFrame("Frame")
    f.activeModels = {}
    f:SetScript("OnUpdate", onUpdate)
    ns[key] = f
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
-- Clearing only RotationFrame leaves a model released mid-right-drag in
-- MovementFrame.activeModels for the rest of the session, iterated on every OnUpdate and
-- never collected -- which is why both are cleared here rather than at each call site.
--
-- Public because the Models Browser needs it, as a service rather than exposing
-- RotationFrame.activeModels on the cross-addon surface.
function ns.RowManager:ReleaseModel(model)
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
    return GetSettings().modelZoom or ns.Config.DEFAULT_MODEL_ZOOM
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
    if model.displayId and ns.Data and ns.Data.SaveSettings then
        ns.Data:SaveSettings()
    end
end

local function PersistView(model, patch)
    if not model.displayId then return end
    local vk = ViewKey(model)
    ns.state.modelViews[vk] = ns.state.modelViews[vk] or {}
    for k, v in pairs(patch) do
        ns.state.modelViews[vk][k] = v
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
                and ns.DragDrop and ns.DragDrop.StartDrag then
                ns.DragDrop:StartDrag(self.petData, self)
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
        if ns.DragDrop and ns.DragDrop.dragging then
            ns.DragDrop:EndDrag()
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
    ns.Tooltip.Attach(model,
        function(self)
            local tip = ns.RowManager.MODEL_HINTS
            if ns.state and ns.state.isStableOpen
                and self.petData and self.petData.slotID then
                tip = tip .. "\n" .. ns.L("Shift/Ctrl + drag to reorder slot")
            end
            return { title = tip }
        end,
        {
            onEnter = function(self) ns.RowManager:ShowHoverButtons(self) end,
            onLeave = function(self) ns.RowManager:HideHoverButtons(self) end,
        }
    )
end

-- ─── Hover buttons ───────────────────────────────────────────────────────────
--
-- The overlay buttons fade in together on hover. Views that want their own model
-- tooltip have to re-attach OnEnter/OnLeave, which drops the pair installed above,
-- so both halves are public: a view supplies the tooltip and reuses these rather than
-- hardcoding the button list, which would leave a new overlay button out of some views.

function ns.RowManager:ShowHoverButtons(model)
    for _, b in ipairs(model.hoverButtons or {}) do
        -- Team buttons only show for player-owned pets.
        local teamButton = b == model.addToTeamButton or b == model.removeFromTeamButton
        if not teamButton or model.isOwnedByPlayer then b:Show() end
    end
end

-- Keep a button visible if the mouse moved directly onto it from the model.
function ns.RowManager:HideHoverButtons(model)
    for _, b in ipairs(model.hoverButtons or {}) do
        if not b:IsMouseOver() then b:Hide() end
    end
end

-- ─── Button factory ───────────────────────────────────────────────────────────

-- The small affordances that fade in over a model on hover: reset view, magnify,
-- add/remove from team. Deliberately not skinned -- ElvUI's HandleButton strips
-- exactly the textures these are made of.
local OVERLAY_ALPHA, OVERLAY_ALPHA_HOVER = 0.7, 1.0

local function MakeOverlayButton(parent, model, opts)
    local btn = ns.Widgets.IconButton(parent, {
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
    ns.Tooltip.Attach(btn, opts.tooltip, {
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
        tooltip   = ns.L("Reset View"),
    })

    btn:SetScript("OnClick", function()
        local s = GetSettings()
        local gz   = s.modelZoom             or ns.Config.DEFAULT_MODEL_ZOOM
        local va   = s.modelViewAngle        or ns.Config.DEFAULT_MODEL_VIEW_ANGLE
        local vp   = s.modelVerticalPosition or ns.Config.DEFAULT_MODEL_VERTICAL_POSITION
        local hp   = s.modelHorizontalPosition or ns.Config.DEFAULT_MODEL_HORIZONTAL_POSITION

        model.rotation = math.rad(va)
        model.zoom     = 1.0
        model:SetRotation(model.rotation)
        model:SetPosition(0, hp * 2.0, vp * 2.0)
        SetCamDistanceScaleIfChanged(model, 1.0 / gz)
        ns.RowManager:ReleaseModel(model)

        if model.displayId then
            ns.state.modelViews[ViewKey(model)] = {
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
        tooltip = ns.L("Magnify Model"),
    })

    btn:SetScript("OnClick", function()
        if ns.PopUpManager and ns.PopUpManager.ShowMagnificationPopup then
            ns.PopUpManager:ShowMagnificationPopup(model.displayId, model.petData)
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
        tooltip   = ns.L("Add to Team"),
    })

    btn:SetScript("OnClick", function()
        if model.petData then ns.Dialogs:ShowAddToTeamDialog(model.petData) end
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
        tooltip   = ns.L("Remove from Team"),
    })

    btn:SetScript("OnClick", function()
        if model.petData then ns.Dialogs:ShowRemoveFromTeamDialog(model.petData) end
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
    ns.Widgets.Backdrop(row, "TOOLTIP", {
        color       = ns.Config.COLORS.BACKGROUND,
        borderColor = ROW_RULE,
    })
end

local function CreateSeparator(row)
    return ns.Widgets.Line(row, {
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
    row.specBg = ns.Widgets.Texture(row, {
        layer     = "BACKGROUND",
        sublayer  = -1,
        allPoints = true,
        hidden    = true,
    })
end

function ns.RowManager:CreateBaseRow(parent, config)
    config = config or {}
    local useBackdrop   = config.useBackdropTemplate or false
    local showMagnify   = config.showMagnifyButton ~= false
    local showTeamBtns  = config.showTeamButtons or false

    local Widgets = ns.Widgets

    local row = Widgets.Frame(parent, {
        template = useBackdrop and "BackdropTemplate" or nil,
        size     = {
            config.width  or ns.Config.DEFAULT_ROW_WIDTH,
            config.height or ns.Config.ROW_HEIGHT,
        },
    })

    CreateBackground(row, useBackdrop)
    CreateSeparator(row)

    -- Model
    local modelSize  = config.modelSize or ns.Config.MODEL_SIZE
    -- How far the model card sits from the row's left edge. Defaults to 2 (flush against
    -- the row border); the list view passes 4 so its favorite star clears the duplicate
    -- border. The favorite/icon anchor to row.model, so they follow this offset.
    local modelInset = config.modelInset or 2
    row.model = Widgets.Frame(row, {
        frameType = "PlayerModel",
        size      = { modelSize, modelSize },
        point     = { "LEFT", row, "LEFT", modelInset, 0 },
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
        tooltip   = ns.L("Favorite/Unfavorite"),
    })

    local function SetFavTexCoords(isFav)
        local u = isFav and 0 or 0.5
        favBtn:GetNormalTexture():SetTexCoord(u, u + 0.5, 0, 0.5)
        favBtn:GetHighlightTexture():SetTexCoord(u, u + 0.5, 0, 0.5)
    end

    favBtn:SetScript("OnClick", function()
        if not row.displayId then return end
        local isFav = not ns.state.favoriteModels[row.displayId]
        ns.state.favoriteModels[row.displayId] = isFav
        SetFavTexCoords(isFav)
        if ns.Data and ns.Data.SaveSettings then ns.Data:SaveSettings() end
        -- Favorite is a model-level concept: every pet sharing this displayId
        -- stays in lockstep, so this pushes the SAME new value onto every live
        -- pet the current character owns of it -- unconditionally, both
        -- directions. There is deliberately no per-pet favorite distinct from
        -- this shared flag.
        if ns.Data and ns.Data.PushFavoriteToOwnedPets then
            ns.Data:PushFavoriteToOwnedPets(row.displayId, isFav)
        end
        -- Redraws every currently-visible row on both panels, not just this
        -- one -- a sibling pet sharing this displayId (Owned Pets) or an
        -- already-open Browser row for this model is showing a now-stale
        -- texture otherwise, since favoriteModels changed but nothing
        -- repainted the button that was already built.
        if ns.Data and ns.Data.RefreshFavoriteDisplays then ns.Data:RefreshFavoriteDisplays() end
        local panel = ns.state.modelsPanel
        if panel and ns.FilterState:Get("showFavorites") then
            ns.Browser.ModelsDataLoader:LoadModelsForSelectedFamilies()
        end
    end)
    row.favoriteButton  = favBtn
    row._setFavTexCoords = SetFavTexCoords  -- expose for UpdateFavoriteButton

    -- Icon fallback -- shares the model's inset so it lands where the model would
    row.icon = Widgets.Texture(row, {
        layer  = "ARTWORK",
        size   = { ns.Config.ICON_SIZE, ns.Config.ICON_SIZE },
        point  = { "LEFT", row, "LEFT", modelInset, 0 },
        hidden = true,
    })

    -- Label
    row.text = Widgets.Label(row, {
        fontSize = ns.Theme.SIZE.SMALL,
        justify  = "LEFT",
        justifyV = "MIDDLE",
        width    = ns.Config.TEXT_WIDTH,
        point    = { "LEFT", row.model, "RIGHT", 6, 0 },
    })

    row.config = config
    return row
end

-- ─── Public update helpers ────────────────────────────────────────────────────

function ns.RowManager:UpdateModelDisplay(row, displayID, icon, petData)
    if displayID and displayID > 0 then
        row.model:SetDisplayInfo(displayID)
        row.model.displayId = displayID
        row.model.petData   = petData
        row.model:Show()
        row.icon:Hide()

        local currentCharKey = ns.GetCharacterKey()
        row.model.isOwnedByPlayer = petData and petData.tamer == currentCharKey

        if GetSettings().stopAnimation then
            row.model:FreezeAnimation(0, 0, 0)
        else
            row.model:SetAnimation(0)
        end
        row.model:SetCamera(0)

    local vk   = ViewKey(row.model)
    local view = ns.state.modelViews and ns.state.modelViews[vk]
    local gz   = GetGlobalZoom()
    local s    = GetSettings()
    local vp   = s.modelVerticalPosition    or ns.Config.DEFAULT_MODEL_VERTICAL_POSITION
    local hp   = s.modelHorizontalPosition  or ns.Config.DEFAULT_MODEL_HORIZONTAL_POSITION
    local va   = s.modelViewAngle           or ns.Config.DEFAULT_MODEL_VIEW_ANGLE

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

function ns.RowManager:UpdateBackgroundColor(row, isSameCharDup, isCrossCharDup, isOwned, specialization, backgroundType)
    backgroundType = backgroundType or GetSettings().backgroundType or ns.Config.DEFAULT_BACKGROUND_TYPE

    -- Clear any color overlay
    if row.bg then
        row.bg:SetColorTexture(0, 0, 0, 0)  -- fully transparent
    elseif row.SetBackdropColor then
        row:SetBackdropColor(0, 0, 0, 0)    -- fully transparent
    end

    -- Background handling
    if row.specBg then
        if backgroundType == "stablemaster" and specialization then
            row.specBg:SetAtlas(ns.Config.SPEC_BACKGROUND_ATLAS[specialization] or ns.Config.SPEC_BACKGROUND_ATLAS.Ferocity)
            row.specBg:SetVertexColor(1, 1, 1, 1)  -- Reset vertex color
            row.specBg:Show()
            if row.SetBackdrop then row:SetBackdrop(nil) end  -- Hide backdrop for spec bg
        elseif backgroundType == "custom" and specialization then
            row.specBg:SetTexture(ns.Config.SPEC_BACKGROUND_CUSTOM[specialization] or ns.Config.SPEC_BACKGROUND_CUSTOM.Ferocity)
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
        row.dupBorder = ns.Widgets.Frame(row, {
            backdrop  = "BORDER_ONLY",
            allPoints = true,
            level     = row:GetFrameLevel() + 2,
        })
    end

    if isSameCharDup then
        row.dupBorder:SetBackdropBorderColor(unpack(ns.Config.COLORS.BORDER_DUPLICATE))
        row.dupBorder:Show()
    elseif isCrossCharDup then
        row.dupBorder:SetBackdropBorderColor(unpack(ns.Config.COLORS.BORDER_DUPLICATE_CROSS_CHAR))
        row.dupBorder:Show()
    elseif isOwned then
        row.dupBorder:SetBackdropBorderColor(unpack(ns.Config.COLORS.BORDER_OWNED_SINGLE))
        row.dupBorder:Show()
    else
        row.dupBorder:Hide()
    end
end

function ns.RowManager:EnsureRow(i, parent, config)
    if not i or i < 1 then return nil end
    ns.state.rows = ns.state.rows or {}
    if ns.state.rows[i] then return ns.state.rows[i] end
    if not parent then
        ns.Utils:Msg("ERROR", ns.L("Panel creation failed!"))
        return nil
    end
    local row = self:CreateBaseRow(parent, config)
    ns.state.rows[i] = row
    return row
end

function ns.RowManager:UpdateFavoriteButton(row, displayId)
    if not row or not row.favoriteButton then return end
    row.displayId = displayId
    row.favoriteButton:Show()
    row._setFavTexCoords(ns.state.favoriteModels[displayId])
end

-- Account-wide, independent of who is currently logged in: a pet is a
-- "same-char" duplicate if its OWNING character (pet.tamer) has 2+ copies of
-- this model, and a "cross-char" duplicate if the model also exists on a
-- different character. Previously this compared against the logged-in
-- character instead of the row's own owner, so duplicates only ever showed up
-- while playing a character that itself owned copies.
function ns.RowManager:CheckDuplicates(pet, allGroups)
    local key = ns.Utils:GetPetDuplicateKey(pet)
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