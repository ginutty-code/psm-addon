-- Shared/PopUpManager.lua
-- Pop-up management for PetStableManagement

local addonName = "PetStableManagement"
local _, ns = ...
ns.PopUpManager = ns.PopUpManager or {}

-- ============================================================
-- Helpers
-- ============================================================

local NPC_ROW_PADDING   = 6
local NPC_ROW_MIN_H     = 32
local NPC_ROW_SPACING   = 4  -- gap between rows

local TAMING_ROW_PADDING = 10  -- inset inside tamingFrame (matches TOPLEFT/BOTTOM padding)

local function GetDB() return PetStableManagementDB.settings end

local function SetCamDistanceScaleIfChanged(modelFrame, scale)
    if modelFrame.lastCamDistanceScale ~= scale then
        modelFrame.lastCamDistanceScale = scale
        modelFrame:SetCamDistanceScale(scale)
    end
end

local function GetViewKey(popup)
    if popup.currentPetData and popup.currentPetData.guid then
        return "pet_" .. popup.currentPetData.guid
    end
    return popup.currentDisplayId
end

local function SaveView(popup, updates)
    local key = GetViewKey(popup)
    if not key then return end
    ns.state.modelViews[key] = ns.state.modelViews[key] or {}
    for k, v in pairs(updates) do
        ns.state.modelViews[key][k] = v
    end
    if ns.Data and ns.Data.SaveSettings then
        ns.Data:SaveSettings()
    end
end

local function ApplyModelView(modelFrame, view)
    local db = GetDB()
    local globalZoom = db.modelZoom or ns.Config.DEFAULT_MODEL_ZOOM
    modelFrame.rotation = view.rotation or math.rad(db.modelViewAngle or ns.Config.DEFAULT_MODEL_VIEW_ANGLE)
    modelFrame.zoom     = view.zoom or 1.0
    modelFrame:SetRotation(modelFrame.rotation)
    SetCamDistanceScaleIfChanged(modelFrame, modelFrame.zoom / globalZoom)
    modelFrame:SetPosition(unpack(view.position or {0, 0, 0}))
    modelFrame.isRotating = false
end

local function GetPopupSpecialization(displayId, petData)
    if petData then
        if petData.specName and petData.specName ~= "" then
            return petData.specName
        end
        if petData.familyName then
            local spec = ns.Config.FAMILY_TO_SPEC[petData.familyName]
            if spec then return spec end
        end
    end

    if displayId then
        if ns.state.stablePets then
            for _, pet in ipairs(ns.state.stablePets) do
                if tonumber(pet.displayID) == tonumber(displayId) then
                    if pet.specName and pet.specName ~= "" then
                        return pet.specName
                    end
                    if pet.familyName then
                        local spec = ns.Config.FAMILY_TO_SPEC[pet.familyName]
                        if spec then return spec end
                    end
                end
            end
        end

        if ns.state.modelsPanel and ns.state.modelsPanel.allModels then
            for _, model in ipairs(ns.state.modelsPanel.allModels) do
                if model.displayId == displayId then
                    local spec = ns.Config.FAMILY_TO_SPEC[model.familyName]
                    if spec then return spec end
                end
            end
        end

        if ns.Browser.PetModels then
            for _, familyName in ipairs(ns.Browser.PetModels:GetAvailableFamilies()) do
                local info = ns.Browser.PetModels:GetModelInfo(familyName, displayId)
                if info then
                    local spec = ns.Config.FAMILY_TO_SPEC[familyName]
                    if spec then return spec end
                end
            end
        end
    end

    return nil
end

-- Parses faction reaction string and returns colored faction indicators
local function formatFactionIndicator(factionReaction)
    if not factionReaction then return "" end
    local alliance, horde = factionReaction:match("%[([^,]*),([^%]]*)%]")
    if not alliance or not horde then return "" end
    alliance = alliance ~= "null" and tonumber(alliance)
    horde    = horde    ~= "null" and tonumber(horde)
    local result = ""
    if alliance then
        local color = alliance == -1 and "ff0000" or alliance == 0 and "ffff00" or "00ff00"
        result = result .. "|cff" .. color .. "A|r"
    end
    if horde then
        local color = horde == -1 and "ff0000" or horde == 0 and "ffff00" or "00ff00"
        result = result .. "|cff" .. color .. "H|r"
    end
    return result ~= "" and " " .. result or ""
end

-- Returns the note icon for an NPC line, colored by note state.
-- golden = user note exists grey = no notes
local function BuildNoteLink(npcId)
    local id = tonumber(npcId)
    if not id then return "" end
    local hasSeed = ns.Browser.NotesData and ns.Browser.NotesData[id]
    local hasUser = PSM_UserNotes and PSM_UserNotes[id] and PSM_UserNotes[id] ~= ""
    local texture
    if hasUser then
        texture = "Interface\\Buttons\\ui-guildbutton-officernote-up"  -- has user note
    elseif hasSeed then
        texture = "Interface\\Buttons\\ui-guildbutton-officernote-up"  -- has seed note
    else
        texture = "Interface\\Buttons\\ui-guildbutton-officernote-disabled"  -- no note
    end
    return string.format("|Hpsmnote:%d|h|T%s:14:14:0:0|t|h", npcId, texture)
end

local function CreateNPCRow(parent, npc, rowWidth)
    local Theme, Widgets = ns.Theme, ns.Widgets

    local row = Widgets.Frame(parent, {
        width    = rowWidth,
        backdrop = "SOLID",
        color    = Theme.FILL.ROW,
    })

    -- Bottom border line
    Widgets.Line(row, {
        point = {
            { "BOTTOMLEFT",  row, "BOTTOMLEFT",  0, 0 },
            { "BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0 },
        },
    })

    -- NPC name (left, gold)
    local nameText = Widgets.Label(row, {
        fontSize = Theme.SIZE.LABEL,
        outline  = true,
        color    = Theme.COLOR.GOLD,
        justify  = "LEFT",
        point    = { "TOPLEFT", row, "TOPLEFT", NPC_ROW_PADDING, -NPC_ROW_PADDING },
    })

    local nameStr = npc.name or "Unknown"
    if npc.classification and npc.classification ~= "Normal" then
        nameStr = nameStr .. " |cffaaaaaa(" .. npc.classification .. ")|r"
    end
    nameText:SetText(nameStr)

    local nameKeeper = npc.nameKeeper or npc.namekeeper
    if nameKeeper then
        -- Add "keeps name" text indicator
        local keepNameText = Widgets.Label(row, {
            fontSize = Theme.SIZE.LABEL,
            outline  = true,
            color    = Theme.COLOR.GREY,
            justify  = "LEFT",
            point    = { "LEFT", nameText, "RIGHT", 4, 0 },
            text     = "(keeps name)",
        })

        local maxNameW = rowWidth - (NPC_ROW_PADDING * 2) - keepNameText:GetStringWidth() - 8
        nameText:SetWidth(math.min(nameText:GetStringWidth(), maxNameW))
    else
        nameText:SetWidth(rowWidth - (NPC_ROW_PADDING * 2))
    end

    -- Metadata separator
    local sep = "  |cff666666•|r  "

    -- Condition hint
    local npcID = tonumber(npc.npcId)
    local condList = npcID and ns.Browser.ConditionsData and ns.Browser.ConditionsData.Get(npcID)
    local conditionHint = ""
    if condList and #condList > 0 then
        conditionHint = " |cffff8800|Hpsmcond:" .. npcID .. "|h[*]|h|r"
    end

    -- Subtle separator line between name and details
    local line = Widgets.Line(row, {
        layer = "ARTWORK",
        color = Theme.FILL.HAIRLINE,
        point = {
            { "TOPLEFT",  nameText, "BOTTOMLEFT",  0, -2 },
            { "TOPRIGHT", nameText, "BOTTOMRIGHT", 0, -2 },
        },
    })

    -- Detail line (location, expansion, faction, NPC ID link)
    local detailText = Widgets.Frame(row, {
        frameType = "SimpleHTML",
        width     = rowWidth - (NPC_ROW_PADDING * 2),
        point     = { "TOPLEFT", line, "BOTTOMLEFT", 0, -3 },
    })
    detailText:SetFont("p", Theme.FONT, Theme.SIZE.BODY, "")
    detailText:SetHyperlinksEnabled(true)

    local id         = npc.npcId or "?"
    local locLabel   = ns.PopUpManager:BuildCoordsLocationLabel(npc.npcId, npc.location) or "Unknown"
    local expansion  = npc.expansion or "Unknown"
    local factionStr = formatFactionIndicator(npc.factionReaction)
    local noteLink   = npc.npcId and BuildNoteLink(npc.npcId) or ""

    local detailLine = string.format("|Hnpc:%s|h|cff00ff00NPC ID: %s|h|r%s", id, id, conditionHint)
    detailLine = detailLine .. sep .. locLabel
    detailLine = detailLine .. sep .. "|cffaaaaaa" .. expansion .. "|r"
    if factionStr ~= "" then detailLine = detailLine .. sep .. factionStr end
    if noteLink ~= "" then detailLine = detailLine .. sep .. noteLink end

    local html = "<html><body><p>" .. detailLine .. "</p></body></html>"
    detailText:SetText(html)

    -- Wire up hyperlink handlers
    -- Tooltip contents per hyperlink type. Returns a PSM.Tooltip spec; the
    -- deliberately empty spec for a condition link with no conditions preserves the
    -- previous behaviour of anchoring an empty tooltip rather than showing nothing.
    local function DetailLinkTooltip(linkType, data)
        local id2 = tonumber(data)

        if linkType == "psmcoords" then
            return { title = "Click to view waypoints" }
        end

        if linkType == "psmcond" then
            local conds = id2 and ns.Browser.ConditionsData and ns.Browser.ConditionsData.Get(id2)
            if not (conds and #conds > 0) then return {} end
            local lines = {}
            for _, c in ipairs(conds) do
                lines[#lines + 1] = { text = c, color = Theme.COLOR.WHITE }
            end
            return { title = "Special Conditions", lines = lines }
        end

        if linkType == "psmnote" then
            local userNote = id2 and PSM_UserNotes and PSM_UserNotes[id2]
            if userNote and userNote ~= "" then
                return {
                    title = "Edit note",
                    lines = { { text = userNote, color = { 1, 1, 0 }, wrap = true } },
                }
            end
            local seedNote = id2 and ns.Browser.NotesData and ns.Browser.NotesData[id2]
            if seedNote then
                return {
                    title = "Add your own note",
                    lines = { { text = seedNote, color = Theme.COLOR.MUTED, wrap = true } },
                }
            end
            return { title = "Add a note for this NPC" }
        end

        return { title = "Click to copy Wowhead URL" }
    end

    detailText:SetScript("OnHyperlinkEnter", function(_, link)
        local linkType, data = strsplit(":", link, 2)
        local spec = DetailLinkTooltip(linkType, data)
        spec.anchor = "ANCHOR_CURSOR"
        ns.Tooltip.Show(detailText, spec)
    end)
    detailText:SetScript("OnHyperlinkLeave", ns.Tooltip.Hide)
    detailText:SetScript("OnHyperlinkClick", function(_, link)
        local linkType, data = strsplit(":", link, 2)
        if linkType == "npc" then
            ns.PopUpManager:ShowURLPopup("https://www.wowhead.com/npc=" .. data)
        elseif linkType == "psmnote" then
            local id2 = tonumber(data)
            if id2 then
                ns.PopUpManager:ShowNoteEditor(id2, npc.name or "NPC", row._parentPopup)
            end
        elseif linkType == "psmcoords" then
            local npcId2, locationOrMapId = strsplit(";", data, 2)
            if npcId2 and locationOrMapId then
                local waypoints = ns.PopUpManager:GetCoordsWaypointText(tonumber(npcId2), locationOrMapId, npc.name)
                if waypoints then
                    local locName = locationOrMapId
                    local numMapId = tonumber(locationOrMapId)
                    if numMapId and CoordsData and CoordsData[numMapId] then
                        locName = CoordsData[numMapId].name or locationOrMapId
                    end
                    local displayId = row._parentPopup and row._parentPopup.currentDisplayId
                    ns.PopUpManager:ShowCoordsPopup(waypoints, npc.name, locName, displayId)
                end
            end
        end
    end)

    -- Size the row once SimpleHTML content height is known
    ns.C_Timer.After(0.01, function()
        local dh = detailText:GetContentHeight()
        detailText:SetHeight(math.max(dh, 14))
        local totalH = NPC_ROW_PADDING + nameText:GetStringHeight() + 2 + math.max(dh, 14) + NPC_ROW_PADDING
        row:SetHeight(math.max(totalH, NPC_ROW_MIN_H))
    end)

    return row
end

-- Re-flow taming requirements text and resize the frame (mirrors CreateNPCRow sizing)
local function UpdateTamingLayout(popup)
    local tf, html = popup.tamingFrame, popup.tamingHTML
    if not tf or not html or not tf:IsShown() or not popup.tamingHTMLContent then return end

    local textW = tf:GetWidth() - (TAMING_ROW_PADDING * 2)
    if textW <= 0 then textW = (popup:GetWidth() or 500) - 50 - (TAMING_ROW_PADDING * 2) end

    popup.tamingTitle:SetWidth(textW)
    html:SetWidth(textW)
    html:SetText(popup.tamingHTMLContent)

    ns.C_Timer.After(0.01, function()
        if not tf or not tf:IsShown() then return end
        local titleH = popup.tamingTitle:GetStringHeight() or 14
        local dh = html:GetContentHeight()
        html:SetHeight(math.max(dh, 14))
        local totalH = 5 + titleH + 6 + math.max(dh, 14) + 8
        tf:SetHeight(math.max(20, totalH))
    end)
end

local function UpdateScrollBarVisibility(p)
    if not p.npcsScrollFrame or not p.npcsScrollBar or not p.npcsContainer then return end
    local totalH = p.npcsContainer:GetHeight() or 0
    local sfH = p.npcsScrollFrame:GetHeight() or 1
    local maxScroll = math.max(0, totalH - sfH)
    
    p.npcsScrollBar:SetMinMaxValues(0, maxScroll)
    p.npcsScrollBar:Show()
    if maxScroll > 0 then
        p.npcsScrollBar:Enable()
        p.npcsScrollBar:SetAlpha(1.0)
    else
        p.npcsScrollBar:Disable()
        p.npcsScrollBar:SetAlpha(0.3)
        p.npcsScrollBar:SetValue(0)
    end
end

local function BuildNPCRows(popup, npcs)
    -- Tear down previous rows
    if popup.npcRows then
        for _, r in ipairs(popup.npcRows) do r:Hide(); r:SetParent(nil) end
    end
    popup.npcRows = {}

    if not npcs or #npcs == 0 then
        popup.npcsScrollFrame:Hide()
        popup.npcsScrollBar:Hide() -- Hide scrollbar if no NPCs
        return
    end

    local container = popup.npcsContainer
    local scrollW = popup.npcsScrollFrame:GetWidth()
    if not scrollW or scrollW <= 0 then scrollW = (popup:GetWidth() or 500) - 50 end

    -- Record the width these rows were built for, so a layout pass right
    -- after this call doesn't see a width "change" and redundantly rebuild
    -- again (BuildNPCRows can be called directly, outside UpdateModelFrameLayout).
    popup._lastBuildW = popup:GetWidth() or scrollW

    local rowWidth = scrollW - 22
    container:SetWidth(rowWidth)

    -- Initial estimate to keep the scrollframe functional while dynamic heights calculate
    container:SetHeight(math.max(1, #npcs * (NPC_ROW_MIN_H + NPC_ROW_SPACING)))

    local prevRow = nil
    for _, npc in ipairs(npcs) do
        local row = CreateNPCRow(container, npc, rowWidth)
        row._parentPopup = popup
        
        if not prevRow then
            row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
        else
            row:SetPoint("TOPLEFT", prevRow, "BOTTOMLEFT", 0, -NPC_ROW_SPACING)
        end
        
        prevRow = row
        popup.npcRows[#popup.npcRows + 1] = row
    end

    -- Update container height after rows have calculated their dynamic sizes
    ns.C_Timer.After(0.05, function()
        local totalH, autoSizeH = 0, 0
        for i, r in ipairs(popup.npcRows) do
            local h = (r:GetHeight() or NPC_ROW_MIN_H) + NPC_ROW_SPACING
            totalH = totalH + h
            if i <= 2 then
                autoSizeH = autoSizeH + h
            end
        end
        container:SetHeight(math.max(1, totalH))
        UpdateScrollBarVisibility(popup)

        -- Store prioritized height (up to 2 NPCs) for layout calculations (used by OnSizeChanged)
        popup.lastCalculatedRowsH = autoSizeH

        -- Auto-expand window height based on content when data is attached
        if popup.needsAutoSizing then
            popup.needsAutoSizing = false
            -- Calculate dynamic offsets
            local tamingH = (popup.tamingFrame and popup.tamingFrame:IsShown()) and (popup.tamingFrame:GetHeight() or 0) or 0
            local staticOffsets = 150 + tamingH
            local targetH = 300 + staticOffsets + math.min(autoSizeH, 350)
            popup:SetHeight(math.min(targetH, UIParent:GetHeight() * 0.85))
            -- SetHeight only fires OnSizeChanged (and thus relayouts the model
            -- frame) if the height actually changed; call directly too so a
            -- same-height populate still gets a correctly sized model frame.
            if popup.UpdateModelFrameLayout then popup.UpdateModelFrameLayout() end
        elseif popup.UpdateModelFrameLayout then
            -- Not the initial populate (e.g. rows were re-flowed after a manual
            -- width resize) - resync the model frame to the freshly measured
            -- row heights instead of leaving it sized for the old ones.
            popup.UpdateModelFrameLayout()
        end
    end)

    popup.npcsScrollFrame:Show()
end

function ns.PopUpManager:UpdatePopupBackground(popup, displayId, petData)
    if not popup or not popup.border or not popup.border.specBg then return end

    local specialization = GetPopupSpecialization(displayId, petData)
    local backgroundType = GetDB().backgroundType or ns.Config.DEFAULT_BACKGROUND_TYPE

    if backgroundType == "stablemaster" and specialization then
        popup.border.specBg:SetAtlas(ns.Config.SPEC_BACKGROUND_ATLAS[specialization] or ns.Config.SPEC_BACKGROUND_ATLAS.Ferocity)
        popup.border.specBg:SetVertexColor(1, 1, 1, 1)
        popup.border.specBg:Show()
        popup.border:SetBackdropColor(0, 0, 0, 0)
    elseif backgroundType == "custom" and specialization then
        popup.border.specBg:SetTexture(ns.Config.SPEC_BACKGROUND_CUSTOM[specialization] or ns.Config.SPEC_BACKGROUND_CUSTOM.Ferocity)
        popup.border.specBg:SetVertexColor(1, 1, 1, 1)
        popup.border.specBg:Show()
        popup.border:SetBackdropColor(0, 0, 0, 0)
    else
        popup.border.specBg:Hide()
        popup.border:SetBackdropColor(0, 0, 0, ns.Config:GetOpacity())
    end
end

-- ============================================================
-- CreateModelPopup
-- ============================================================

-- Where a user-chosen popup size is kept, keyed by popupName so the magnifier and the
-- roulette remember their own. Created on demand rather than assumed present: Core seeds
-- it for new installs, and this covers profiles saved before it existed.
local function PopupSizeStore()
    if not PetStableManagementDB then return nil end
    PetStableManagementDB.settings = PetStableManagementDB.settings or {}
    PetStableManagementDB.settings.popupSizes = PetStableManagementDB.settings.popupSizes or {}
    return PetStableManagementDB.settings.popupSizes
end

function ns.PopUpManager:CreateModelPopup(config)
    config = config or {}
    local title     = config.title     or "Model Viewer"
    local width     = config.width     or 500
    local height    = config.height    or 560
    local modelSize = config.modelSize or math.min(width - 40, height - 220)
    local resizable = config.resizable or false
    local popupName = config.popupName or "PetStableManagementModelPopup"

    local Theme, Widgets = ns.Theme, ns.Widgets

    -- Root frame
    local popup = Widgets.MovableFrame(UIParent, {
        name   = popupName,
        size   = { width, height },
        point  = { "CENTER" },
        strata = "DIALOG",
        level  = 1000,
    })
    popup:SetToplevel(true)
    popup:SetClampedToScreen(true)
    popup:SetClipsChildren(true)

    -- Kept so Reset can put the popup back. Auto-sizing cannot do it: it only ever
    -- recomputes *height*, which is why a dragged width survived every populate and would
    -- have survived Reset too.
    popup.defaultWidth  = width
    popup.defaultHeight = height

    -- Resize handle. Finishing a drag marks the popup as user-sized, which switches
    -- auto-sizing off (see PopulateModelPopup) and records the size to SavedVariables.
    if resizable then
        Widgets.ResizeGrip(popup, {
            point  = { "BOTTOMRIGHT", -5, 5 },
            onStop = function(f)
                f.userSized = true
                local store = PopupSizeStore()
                if store then
                    store[popupName] = {
                        w = math.floor(f:GetWidth()  + 0.5),
                        h = math.floor(f:GetHeight() + 0.5),
                    }
                end
            end,
        })

        -- Restore a size chosen in an earlier session, and adopt the user-sized state with
        -- it -- otherwise the first populate would auto-size straight over the restore.
        --
        -- Clamped to the current screen. These popups set no resize bounds, so a size
        -- saved on a larger monitor would otherwise come back bigger than the display with
        -- no way to grab the grip.
        local store = PopupSizeStore()
        local saved = store and store[popupName]
        if saved and saved.w and saved.h then
            popup:SetSize(
                math.max(200, math.min(saved.w, UIParent:GetWidth())),
                math.max(200, math.min(saved.h, UIParent:GetHeight())))
            popup.userSized = true
        end
    end

    -- Background / border
    popup.border = Widgets.Frame(popup, {
        allPoints = true,
        backdrop  = "TOOLTIP_HAIRLINE",
        color     = { 0, 0, 0, ns.Config:GetOpacity() },
        level     = popup:GetFrameLevel() - 1,
    })

    -- Sublayer -1 so the spec artwork sits behind the backdrop's own background rather
    -- than over it; both are BACKGROUND-layer on the same frame.
    popup.border.specBg = Widgets.Texture(popup.border, {
        layer     = "BACKGROUND",
        sublayer  = -1,
        allPoints = true,
        hidden    = true,
    })

    -- Optional: Pet Models back button
    if config.showPetModelsButton then
        popup.modelsButton = Widgets.Button(popup, {
            point      = { "TOPLEFT", 20, -10 },
            width      = ns.Theme.CONTROL.BUTTON_W.S,
            text       = "< Pet Models",
            fontObject = "GameFontNormalSmall",
            onClick = function()
                popup:Hide()
                if ns.state.modelsPanel and ns.state.modelsPanel:IsVisible() then
                    ns.state.modelsPanel:Raise()
                elseif not ns.Loader:EnsureBrowser() then
                    return  -- Loader has already reported why
                elseif ns.PanelManager and ns.PanelManager.TogglePanel then
                    ns.PanelManager:TogglePanel("modelsPanel", function()
                        if ns.Browser.ModelsPanel and ns.Browser.ModelsPanel.CreateModelsPanel then
                            ns.Browser.ModelsPanel:CreateModelsPanel()
                        end
                    end)
                elseif ns.state.modelsPanel then
                    ns.state.modelsPanel:Show()
                    ns.state.modelsPanel:Raise()
                end
            end,
        })
    end

    -- Title
    popup.title = Widgets.Label(popup, {
        fontSize = Theme.SIZE.TITLE,
        outline  = true,
        color    = Theme.COLOR.GOLD,
        point    = { "TOP", 0, -15 },
        text     = title,
    })

    -- 3D model frame
    local mf = Widgets.Frame(popup, {
        frameType = "PlayerModel",
        size      = { modelSize - 10, modelSize - 10 },
        point     = { "TOP", popup.title, "BOTTOM", 0, -15 },
        level     = popup:GetFrameLevel() + 1,
    })
    mf.rotation            = math.pi * 2
    mf.zoom                = 1.0
    mf.lastCamDistanceScale = 1.0
    mf:SetRotation(mf.rotation)
    SetCamDistanceScaleIfChanged(mf, mf.lastCamDistanceScale)
    mf.isRotating = false
    popup.modelFrame = mf

    -- Reset view button (top-right of model)
    popup.modelReset = Widgets.IconButton(popup, {
        size      = { 20, 20 },
        point     = { "TOPRIGHT", mf, "TOPRIGHT", -2, -2 },
        level     = mf:GetFrameLevel() + 2,
        texture   = "Interface\\Buttons\\UI-RefreshButton",
        highlight = "Interface\\Buttons\\UI-RefreshButton",
        alpha     = 0.7,
        hidden    = true,
    })
    popup.modelReset:SetScript("OnClick", function()
        local db = GetDB()
        local hPos = (db.modelHorizontalPosition or ns.Config.DEFAULT_MODEL_HORIZONTAL_POSITION) * 2.0
        local vPos = (db.modelVerticalPosition    or ns.Config.DEFAULT_MODEL_VERTICAL_POSITION)    * 2.0
        ApplyModelView(mf, {
            rotation = math.rad(db.modelViewAngle or ns.Config.DEFAULT_MODEL_VIEW_ANGLE),
            zoom     = 1.0,
            position = {0, hPos, vPos},
        })
        SetCamDistanceScaleIfChanged(mf, 1.0 / (db.modelZoom or ns.Config.DEFAULT_MODEL_ZOOM))
        mf.isMoving = false
        ns.RowManager:ReleaseModel(mf)
        SaveView(popup, { rotation = mf.rotation, zoom = mf.zoom, position = {0, hPos, vPos} })
    end)
    ns.Tooltip.Attach(popup.modelReset, { title = "Reset View" }, {
        onEnter = function(self) self:SetAlpha(1.0) end,
        onLeave = function(self) self:SetAlpha(0.7) end,
    })

    -- Model mouse interaction
    mf:EnableMouse(true)
    mf:EnableMouseWheel(true)

    mf:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self.isRotating = true
            self.lastX = GetCursorPosition()
            if ns.RotationFrame then ns.RotationFrame.activeModels[self] = true end
        elseif button == "RightButton" then
            self.isMoving = true
            self.movementMode = "YZ"
            local scale = UIParent:GetEffectiveScale()
            self.lastX, self.lastY = GetCursorPosition()
            self.lastX, self.lastY = self.lastX / scale, self.lastY / scale
            self.posX, self.posY, self.posZ = self:GetPosition()
            if not self.posX then self.posX, self.posY, self.posZ = 0, 0, 0 end
            if ns.MovementFrame then ns.MovementFrame.activeModels[self] = true end
        end
    end)

    mf:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            self.isRotating = false
            if ns.RotationFrame then ns.RotationFrame.activeModels[self] = nil end
            ns.state.globalModelRotation = self.rotation
            if ns.Data and ns.Data.SaveSettings then ns.Data:SaveSettings() end
        elseif button == "RightButton" then
            self.isMoving = false
            if ns.MovementFrame then ns.MovementFrame.activeModels[self] = nil end
            SaveView(popup, { position = {self:GetPosition()} })
        end
    end)

    mf:SetScript("OnMouseWheel", function(self, delta)
        local db = GetDB()
        self.zoom = math.max(0.1, math.min(2.0, (self.zoom or 1.0) - delta * 0.05))
        SetCamDistanceScaleIfChanged(self, self.zoom / (db.modelZoom or ns.Config.DEFAULT_MODEL_ZOOM))
        SaveView(popup, { zoom = self.zoom })
    end)

    ns.Tooltip.Attach(mf, {
        title = ns.RowManager.MODEL_HINTS,
    }, {
        onEnter = function() popup.modelReset:Show() end,
        onLeave = function()
            if not popup.modelReset:IsMouseOver() then popup.modelReset:Hide() end
        end,
    })

    -- Favorites button (top-left of model)
    popup.favoritesButton = Widgets.IconButton(popup, {
        size      = { 20, 20 },
        point     = { "TOPLEFT", mf, "TOPLEFT", 2, -2 },
        level     = mf:GetFrameLevel() + 2,
        texture   = "Interface\\Common\\ReputationStar",
        highlight = "Interface\\Common\\ReputationStar",
        tooltip   = { title = "Add to Favorites", anchor = "ANCHOR_LEFT" },
    })
    local function SetFavTexCoord(btn, isFav)
        local coord = isFav and {0, 0.5, 0, 0.5} or {0.5, 1, 0, 0.5}
        btn:GetNormalTexture():SetTexCoord(unpack(coord))
        btn:GetHighlightTexture():SetTexCoord(unpack(coord))
    end
    popup.favoritesButton:SetScript("OnClick", function(self)
        local id = popup.currentDisplayId or (popup.currentPetData and popup.currentPetData.displayId)
        if not id then return end
        ns.state.favoriteModels[id] = not ns.state.favoriteModels[id]
        SetFavTexCoord(self, ns.state.favoriteModels[id])
        if ns.Data and ns.Data.SaveSettings then ns.Data:SaveSettings() end
        local panel = ns.state.modelsPanel
        if panel and ns.FilterState:Get("showFavorites") and ns.Browser.ModelsDataLoader then
            ns.Browser.ModelsDataLoader:LoadModelsForSelectedFamilies()
        end
    end)
    popup.SetFavTexCoord = SetFavTexCoord

    -- Info text (anchored to bottom of model frame)
    popup.infoText = Widgets.Label(popup, {
        fontSize = Theme.SIZE.LABEL,
        point    = {
            { "TOPLEFT",  mf,    "BOTTOMLEFT", 0,   -20 },
            { "TOPRIGHT", popup, "TOPRIGHT",   -25, -20 },
        },
    })

    -- Taming requirements area
    local tf = Widgets.Frame(popup, {
        backdrop = "SOLID",
        color    = Theme.FILL.ROW,
        point    = {
            { "TOPLEFT",  popup.infoText, "BOTTOMLEFT",  0, -10 },
            { "TOPRIGHT", popup.infoText, "BOTTOMRIGHT", 0, -10 },
        },
    })
    popup.tamingFrame = tf

    popup.tamingTitle = Widgets.Label(tf, {
        fontSize = Theme.SIZE.LABEL,
        outline  = true,
        color    = Theme.COLOR.GOLD,
        justify  = "CENTER",
        point    = { "TOPLEFT", tf, "TOPLEFT", TAMING_ROW_PADDING, -6 },
        text     = "Taming Skills Required",
    })

    Widgets.Line(tf, {
        height = 2,
        color  = { 0.44, 0.44, 0.50, 1 },
        point  = {
            { "BOTTOMLEFT",  0, 0 },
            { "BOTTOMRIGHT", 0, 0 },
        },
    })

    popup.tamingHTML = Widgets.Frame(tf, {
        frameType = "SimpleHTML",
        point     = { "TOPLEFT", popup.tamingTitle, "BOTTOMLEFT", 0, -6 },
    })
    popup.tamingHTML:SetFont("p", Theme.FONT, Theme.SIZE.BODY, "")
    popup.tamingHTML:SetHyperlinksEnabled(true)
    tf:Hide()

    popup.tamingHTML:SetScript("OnHyperlinkEnter", function(_, link)
        local linkType, data = strsplit(":", link, 2)
        if linkType ~= "psmtaming" then return end
        local rule = ns.Browser.TamingRules and ns.Browser.TamingRules[data]
        if not rule or not rule.hint then return end

        local hyperlink
        if rule.hint.itemID then
            hyperlink = "item:" .. rule.hint.itemID
        elseif rule.hint.questID then
            hyperlink = "quest:" .. rule.hint.questID
        end
        ns.Tooltip.Show(popup.tamingHTML, { anchor = "ANCHOR_CURSOR", hyperlink = hyperlink })
    end)

    popup.tamingHTML:SetScript("OnHyperlinkLeave", ns.Tooltip.Hide)

    popup.tamingHTML:SetScript("OnHyperlinkClick", function(_, link, _, button)
        local linkType, data = strsplit(":", link, 2)
        if linkType ~= "psmtaming" then return end
        local rule = ns.Browser.TamingRules and ns.Browser.TamingRules[data]
        if rule then
            if button == "LeftButton" then
                if rule.itemID then
                    ns.PopUpManager:ShowURLPopup("https://www.wowhead.com/item=" .. rule.itemID)
                elseif rule.hint and rule.hint.questID then
                    ns.PopUpManager:ShowURLPopup("https://www.wowhead.com/quest=" .. rule.hint.questID)
                end
            end
        end
    end)

    -- NPC scroll area
    popup.npcsScrollFrame = Widgets.Frame(popup, {
        frameType = "ScrollFrame",
        point = {
            { "TOPLEFT",  tf,    "BOTTOMLEFT",  0, -8 },
            { "TOPRIGHT", tf,    "BOTTOMRIGHT", 0, -8 },
            { "BOTTOM",   popup, "BOTTOM",      0, 45 },
        },
    })
    popup.npcsScrollFrame:EnableMouse(true)

    popup.npcsContainer = Widgets.Frame(popup.npcsScrollFrame, {
        size  = { width - 0, 120 },
        point = { "TOPLEFT", 22, 0 },  -- Leave space for scrollbar on left
    })
    popup.npcsScrollFrame:SetScrollChild(popup.npcsContainer)

    local scrollBar = Widgets.Frame(popup, {
        frameType = "Slider",
        template  = "UIPanelScrollBarTemplate",
        skin      = "scrollbar",
        point = {
            { "TOPRIGHT",    popup.npcsScrollFrame, "TOPRIGHT",    0, -16 },
            { "BOTTOMRIGHT", popup.npcsScrollFrame, "BOTTOMRIGHT", 0,  16 },
        },
    })
    scrollBar:SetMinMaxValues(0, 0)
    scrollBar:SetValueStep(1)
    scrollBar.scrollStep = 1
    scrollBar:SetScript("OnValueChanged", function(_, v) popup.npcsScrollFrame:SetVerticalScroll(v) end)
    popup.npcsScrollBar = scrollBar

    popup.npcsScrollFrame:SetScript("OnMouseWheel", function(_, delta)
        local cur = scrollBar:GetValue()
        local mn, mx = scrollBar:GetMinMaxValues()
        scrollBar:SetValue(math.max(mn, math.min(mx, cur - delta * 20)))
    end)

    -- Optional: Try Again button
    if config.showTryAgainButton then
        popup.tryAgainButton = Widgets.Button(popup, {
            width      = ns.Theme.CONTROL.BUTTON_W.S,
            text       = "Try Again",
            fontObject = "GameFontNormalSmall",
            strata     = "TOOLTIP",
            point      = { "TOPRIGHT", popup.npcsScrollFrame, "BOTTOMRIGHT", -20, -10 },
            onClick    = function()
                if config.onTryAgain then config.onTryAgain() end
            end,
        })
    end

    -- Close button
    popup.closeButton = Widgets.CloseButton(popup, {
        size  = { 20, 20 },
        level = popup:GetFrameLevel() + 10,
    })

    Widgets.CloseOnEscape(popup)

    -- Layout: the taming/NPC block at the bottom keeps a stable height, and the
    -- model frame above it absorbs all resize- and content-driven size changes.
    -- This single function is the only place that computes the model frame's
    -- size, so the window-drag path, the initial layout, and content updates
    -- (taming box shown/hidden, NPC rows rebuilt) can never disagree and snap
    -- to two different sizes.
    if resizable then
        local function UpdateModelFrameLayout()
            local w = popup:GetWidth() or width
            local h = popup:GetHeight() or height

            -- We treat the list content height as a fixed offset from the bottom.
            -- This ensures extra window height from manual resizing goes to the model area.
            local tamingH = (popup.tamingFrame and popup.tamingFrame:IsShown()) and (popup.tamingFrame:GetHeight() or 0) or 0
            local staticOffsets = 150 + tamingH
            local rowsH = math.min(popup.lastCalculatedRowsH or 100, 350)

            local mw = math.max(200, w - 50)
            local mh = math.max(200, h - staticOffsets - rowsH)

            mf:SetSize(mw - 10, mh - 10)
            if popup.infoText then
                popup.infoText:SetWidth(w - 50)
            end
            if popup.tamingFrame then
                UpdateTamingLayout(popup)
            end
            -- Dynamically adjust NPC area anchors if taming frame is hidden
            if popup.tamingFrame and not popup.tamingFrame:IsShown() then
                popup.npcsScrollFrame:SetPoint("TOPLEFT", popup.infoText, "BOTTOMLEFT", 0, -8)
                popup.npcsScrollFrame:SetPoint("TOPRIGHT", popup.infoText, "BOTTOMRIGHT", 0, -8)
            else
                popup.npcsScrollFrame:SetPoint("TOPLEFT", popup.tamingFrame, "BOTTOMLEFT", 0, -8)
                popup.npcsScrollFrame:SetPoint("TOPRIGHT", popup.tamingFrame, "BOTTOMRIGHT", 0, -8)
            end
            if popup.npcsContainer then
                popup.npcsContainer:SetWidth(math.max(200, popup.npcsScrollFrame:GetWidth() - 0))

                -- Re-flow rows if width changed significantly (handles text wrapping)
                local wDiff = math.abs((popup._lastBuildW or 0) - w)
                if wDiff > 10 and popup.currentNPCs then
                    popup._lastBuildW = w
                    BuildNPCRows(popup, popup.currentNPCs)
                end
            end
            UpdateScrollBarVisibility(popup)
        end
        popup.UpdateModelFrameLayout = UpdateModelFrameLayout

        popup:SetScript("OnSizeChanged", function(self)
            if self._inLayout then return end
            self._inLayout = true
            UpdateModelFrameLayout()
            self._inLayout = nil
        end)

        -- Run one layout pass now that every element (taming box, NPC scroll
        -- area, etc.) exists, so the model frame starts at its correct size
        -- instead of snapping to it on the first resize or populate.
        UpdateModelFrameLayout()
    end

    -- OnHide cleanup
    popup:SetScript("OnHide", function(self)
        if config.cleanupFunction then
            config.cleanupFunction()
        else
            if self.infoText then self.infoText:SetText("") end
            if self.npcRows then
                for _, r in ipairs(self.npcRows) do r:Hide(); r:SetParent(nil) end
                self.npcRows = nil
            end
            self.currentPetData   = nil
            self.currentDisplayId = nil
        end
    end)

    return popup
end

-- ============================================================
-- ShowURLPopup
-- ============================================================

function ns.PopUpManager:ShowURLPopup(url)
    if not self.urlPopup then
        local Theme, Widgets = ns.Theme, ns.Widgets

        local f = Widgets.MovableFrame(UIParent, {
            name     = "PSMURLPopup",
            size     = { 300, 100 },
            point    = { "CENTER" },
            strata   = "TOOLTIP",
            backdrop = "TOOLTIP",
            color    = Theme.FILL.POPUP,
        })
        f:SetToplevel(true)

        f.title = Widgets.Label(f, {
            fontSize = Theme.SIZE.HEADING,
            outline  = true,
            color    = Theme.COLOR.GOLD,
            point    = { "TOP", 0, -10 },
            text     = "Wowhead URL",
        })

        f.editBox = Widgets.EditBox(f, {
            point     = { "TOP", f.title, "BOTTOM", 0, -10 },
            size      = { 260, 20 },
            autoFocus = true,
            closes    = f,
        })

        f.closeButton = Widgets.CloseButton(f)

        self.urlPopup = f
    end
    self.urlPopup.editBox:SetText(url)
    self.urlPopup.editBox:HighlightText()
    self.urlPopup:Show()
end

-- ============================================================
-- Coords helpers
-- ============================================================

function ns.PopUpManager:GetCoordsDataForLocation(npcId, location)
    local id = tonumber(npcId)
    if not id then return nil end

    -- CoordsData ships with the LoadOnDemand browser. Silent because this is also
    -- called once per row while rendering the browser's NPC table, where the addon is
    -- already up and this collapses to a memoised boolean.
    ns.Loader:EnsureBrowser(true)
    if not CoordsData then return nil end

    -- 1. Direct lookup if location is a numeric uiMapId
    local numMapId = tonumber(location)
    if numMapId and CoordsData[numMapId] then
        local mapData = CoordsData[numMapId]
        if type(mapData) == "table" and mapData.npcs and mapData.npcs[id] then
            return {
                uiMapId  = numMapId,
                zoneName = mapData.name or ("Map " .. numMapId),
                coords   = mapData.npcs[id] or "",
            }
        end
    end

    local searchLoc = location and strtrim(tostring(location)):lower() or ""

    -- 2. Try matching location (zone name) in CoordsData
    if searchLoc ~= "" then
        for uiMapId, mapData in pairs(CoordsData) do
            if type(mapData) == "table" and mapData.npcs and mapData.npcs[id] then
                local zName = mapData.name or ""
                if zName:lower() == searchLoc or zName:lower():find(searchLoc, 1, true) or searchLoc:find(zName:lower(), 1, true) then
                    return {
                        uiMapId  = uiMapId,
                        zoneName = zName,
                        coords   = mapData.npcs[id] or "",
                    }
                end
            end
        end
    end

    -- 3. Fallback: return first matching zone entry for this npcId
    for uiMapId, mapData in pairs(CoordsData) do
        if type(mapData) == "table" and mapData.npcs and mapData.npcs[id] then
            return {
                uiMapId  = uiMapId,
                zoneName = mapData.name or ("Map " .. uiMapId),
                coords   = mapData.npcs[id] or "",
            }
        end
    end

    return nil
end

function ns.PopUpManager:BuildCoordsLocationLabel(npcId, fallbackLocation)
    local id = tonumber(npcId)
    if not id or not CoordsData then
        return fallbackLocation and ("|cff888888" .. fallbackLocation .. "|r") or "|cff888888Unknown|r"
    end

    local parts = {}
    local seen = {}

    for uiMapId, mapData in pairs(CoordsData) do
        if type(mapData) == "table" and mapData.npcs and mapData.npcs[id] then
            local zName = mapData.name or ("Map " .. uiMapId)
            local coords = mapData.npcs[id]
            local hasCoords = coords and strtrim(coords) ~= "" and coords ~= "[]"

            local key = uiMapId
            if not seen[key] then
                seen[key] = true
                if hasCoords then
                    -- Green clickable link with uiMapId passed directly
                    parts[#parts + 1] = string.format("|cff00ff00|Hpsmcoords:%d;%d|h%s|h|r", id, uiMapId, zName)
                else
                    -- Grey text when no coordinates are stored
                    parts[#parts + 1] = string.format("|cff888888%s|r", zName)
                end
            end
        end
    end

    if #parts > 0 then
        table.sort(parts)
        return table.concat(parts, " or ")
    end

    if fallbackLocation and fallbackLocation ~= "" then
        return "|cff888888" .. fallbackLocation .. "|r"
    end

    return "|cff888888Unknown|r"
end

function ns.PopUpManager:GetCoordsWaypointText(npcId, location, npcName)
    local data = self:GetCoordsDataForLocation(npcId, location)
    if not data or not data.coords or data.coords == "" or data.coords == "[]" then return nil end
    local lines = {}
    for coord in string.gmatch(data.coords, "[^|]+") do
        local x, y = coord:match("^%s*([0-9%.]+),%s*([0-9%.]+)%s*$")
        if x and y then
            lines[#lines + 1] = string.format("/way #%s %s %s %s", data.uiMapId, x, y, npcName or "")
        end
    end
    if #lines == 0 then return nil end
    return table.concat(lines, "\n")
end

-- ============================================================
-- ShowCoordsPopup
-- ============================================================

function ns.PopUpManager:ShowCoordsPopup(text, npcName, location, displayId)
    if not self.coordsPopup then
        local Theme, Widgets = ns.Theme, ns.Widgets

        local f = Widgets.MovableFrame(UIParent, {
            name     = "PSMCoordsPopup",
            size     = { 300, 200 },
            point    = { "CENTER" },
            strata   = "TOOLTIP",
            level    = 1010,
            backdrop = "TOOLTIP_SMALL",
            color    = Theme.FILL.POPUP,
        })
        f:SetToplevel(true)
        f:SetResizable(true)
        f:SetResizeBounds(300, 150, 800, 800)

        f.title = Widgets.Label(f, {
            fontSize = Theme.SIZE.LABEL,
            outline  = true,
            color    = Theme.COLOR.GOLD,
            point    = { "TOP", 0, -10 },
        })

        f.pasteButton = Widgets.Button(f, {
            point = { "BOTTOM", f, "BOTTOM", 0, 10 },
            width = ns.Theme.CONTROL.BUTTON_W.L,
            text  = "Create Waypoints",
            tooltip = {
                anchor   = "ANCHOR_BOTTOMRIGHT",
                title    = "Adds a waypoint pin on the map",
                toplevel = true,
                lines    = {{
                    text  = "Install TomTom for portrait icons, multiple waypoints, and navigation.",
                    color = Theme.COLOR.WHITE,
                    wrap  = true,
                }},
            },
            onClick = function()
                local t = f.editBox:GetText()
                if not t or t == "" then return end
                local lines = { strsplit("\n", t) }
                local hasTomTom = _G.TomTom ~= nil

                local waypointCount, firstMapId = 0, nil
                local firstCoord = nil -- only used when TomTom is absent

                for _, line in ipairs(lines) do
                    if strtrim(line) ~= "" then
                        local uiMapId, x, y, name = line:match("/way #(%d+) ([0-9%.]+) ([0-9%.]+) (.+)")
                        if uiMapId and x and y then
                            uiMapId = tonumber(uiMapId)
                            if hasTomTom then
                                _G.TomTom:AddWaypoint(uiMapId, tonumber(x)/100, tonumber(y)/100, {
                                    title = name or "",
                                    worldmap_displayID = f.displayId,
                                    minimap_displayID = f.displayId,
                                })
                            elseif not firstCoord then
                                firstCoord = { uiMapId = uiMapId, x = tonumber(x)/100, y = tonumber(y)/100 }
                            end
                            waypointCount = waypointCount + 1
                            if not firstMapId then firstMapId = uiMapId end
                        end
                    end
                end

                if not hasTomTom and firstCoord then
                    -- No TomTom: Blizzard's native waypoint only ever shows a single
                    -- plain pin (no custom icon, no multi-point support). Full
                    -- multi-pin coverage with portrait icons requires TomTom.
                    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(firstCoord.uiMapId, firstCoord.x, firstCoord.y))
                    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
                end

                if waypointCount > 0 and f.npcName and f.location then
                    print("|cff00ff00" .. waypointCount .. " waypoint(s) added on " .. f.location .. " map for " .. f.npcName .. "|r")
                    if not hasTomTom then
                        print("|cffffff00PSM:|r Only the first location was marked. Install |cff3fc7ebTomTom|r for all waypoints, portrait icons, and navigation.")
                    end
                end
                if firstMapId then
                    f:Hide() -- popup is TOOLTIP-strata, above the map; get it out of the way first
                    -- OpenWorldMap (not SetMapID+ShowUIPanel) matters: WorldMapFrame's OnShow
                    -- always resets to the player's current zone, so the map ID has to be set
                    -- *after* showing, which is what OpenWorldMap does for us.
                    OpenWorldMap(firstMapId)
                end
            end,
        })

        f.contentScroll = Widgets.Frame(f, {
            name      = "PSMCoordsPopupScrollFrame",
            frameType = "ScrollFrame",
            template  = "UIPanelScrollFrameTemplate",
            skin      = "scrollframe",
            point = {
                { "TOP",         f.title, "BOTTOM",      0,   -10 },
                { "BOTTOMRIGHT", f,       "BOTTOMRIGHT", -40,  40 },
            },
        })
        ns.Skin.Apply(f.contentScroll.ScrollBar, "scrollbar")

        f.editBox = Widgets.EditBox(f.contentScroll, {
            name      = "PSMCoordsEditBox",
            multiline = true,
            width     = f.contentScroll:GetWidth(),
            height    = f.contentScroll:GetHeight(),
            textColor = Theme.COLOR.WHITE,
            closes    = f,
        })
        f.contentScroll:SetScrollChild(f.editBox)

        f:SetScript("OnSizeChanged", function()
            f.editBox:SetWidth(f.contentScroll:GetWidth())
            f.editBox:SetHeight(f.contentScroll:GetHeight())
        end)

        f.closeButton = Widgets.CloseButton(f, { level = f:GetFrameLevel() + 10 })

        Widgets.ResizeGrip(f)
        Widgets.CloseOnEscape(f)

        self.coordsPopup = f
    end

    self.coordsPopup.title:SetText(string.format("Waypoints for \n %s \n(%s)", npcName or "NPC", location or "Unknown"))
    self.coordsPopup.npcName   = npcName
    self.coordsPopup.location  = location
    self.coordsPopup.displayId = tonumber(displayId)
    self.coordsPopup.editBox:SetText(text or "")
    self.coordsPopup:Show()
    self.coordsPopup:Raise()

    ns.C_Timer.After(0.01, function()
        if self.coordsPopup and self.coordsPopup.contentScroll then
            self.coordsPopup.contentScroll:SetVerticalScroll(0)
        end
    end)
end

-- ============================================================
-- ShowMagnificationPopup
-- ============================================================

function ns.PopUpManager:ShowMagnificationPopup(displayId, petData)
    if not displayId then return end

    displayId = tonumber(displayId)

    -- The magnifier renders taming rules, Petopia notes, conditions and coordinates,
    -- which need the generated tables *and* the browser's own resolvers
    -- (PSM.PetModels, PSM.TamingChecker). Opened from Owned Pets, this may well be
    -- the first thing that loads the browser. Deliberately not bailing on failure:
    -- the 3D model itself needs none of it, so a magnifier without the optional
    -- module still works, just without the extra detail -- exactly as it does today
    -- when the module is disabled.
    ns.Loader:EnsureBrowser()

    if not ns.state.modelMagnificationPopup then
        ns.state.modelMagnificationPopup = self:CreateModelPopup({
            title     = "Model Magnifier",
            width     = 500,
            height    = 500,
            resizable = true,
            popupName = "PetStableManagementMagnificationPopup",
            cleanupFunction = function()
                local p = ns.state.modelMagnificationPopup
                if p then p.currentPetData = nil; p.currentDisplayId = nil end
            end,
        })
        ns.state.modelMagnificationPopup:Hide()
    end

    local popup = ns.state.modelMagnificationPopup
    popup.currentDisplayId   = displayId
    popup.currentPetData     = petData
    popup.modelFrame.petData = petData or {}
    self:UpdatePopupBackground(popup, displayId, petData)

    ns.C_Timer.After(0.1, function()
        local mf = popup.modelFrame
        mf:SetDisplayInfo(displayId)
        SetCamDistanceScaleIfChanged(mf, 1.0)
        if GetDB().stopAnimation then
            mf:FreezeAnimation(0, 0, 0)
        else
            mf:SetAnimation(0)
        end
        local view = ns.state.modelViews and ns.state.modelViews[GetViewKey(popup)]
        ApplyModelView(mf, view or {})
    end)

    popup.SetFavTexCoord(popup.favoritesButton, ns.state.favoriteModels[displayId])

    -- Gather model data
    local familyName = "Unknown"
    local npcs = {}

    if petData and petData.familyName then
        familyName = petData.familyName
    end

    if petData and petData.npcs and type(petData.npcs) == "table" and #petData.npcs > 0 then
        npcs = petData.npcs
    elseif ns.state.modelsPanel and ns.state.modelsPanel.allModels then
        -- Fallback: Search the browser cache if module is loaded and has data
        -- tonumber() handles cases where displayId might be a string from certain data sources
        for _, m in ipairs(ns.state.modelsPanel.allModels) do
            if tonumber(m.displayId) == displayId then
                familyName = m.familyName or familyName
                npcs = m.npcs or npcs
                break
            end
        end
    end

    -- Fallback: Search via PetModels API (Part of ModelsBrowser module)
    if #npcs == 0 and ns.Browser.PetModels then
        for _, fam in ipairs(ns.Browser.PetModels:GetAvailableFamilies()) do
            local info = ns.Browser.PetModels:GetModelInfo(fam, displayId)
            if info then
                familyName = fam
                npcs = (info.npcs and #info.npcs > 0) and info.npcs or npcs
                break
            end
        end
    end

    -- The three branches above all source from GetFamilyModels/GetModelInfo
    -- (or a petData built from the same), whose .npcs arrays are bare
    -- denseIndex numbers -- resolve to full records here so BuildNPCRows/
    -- CreateNPCRow (expect npc.name etc.) still work.
    if #npcs > 0 and type(npcs[1]) == "number" and ns.Browser.PetModels then
        npcs = ns.Browser.PetModels:ResolveNpcRecords(npcs)
    end

    -- 4. Final Fallback: Direct lookup in ModelsData (crucial for magnification from Owned Pets panel)
    if #npcs == 0 and displayId and _G.ModelsData then
        local targetDisplayId = tonumber(displayId)
        if targetDisplayId then
            local modelsData = _G.ModelsData
            for i = 1, #modelsData.NpcId do
                local rawDisplayIds = modelsData.DisplayIds[i]
                local dids = type(rawDisplayIds) == "table" and rawDisplayIds or { rawDisplayIds }
                local matched = false
                for _, did in ipairs(dids) do
                    if tonumber(did) == targetDisplayId then matched = true; break end
                end
                if matched then
                    -- GetModelsRecord's shape already matches what this fallback used to
                    -- build by hand (npcId/name/location/uiMapId/uiMapName/expansion/
                    -- classification/factionReaction/nameKeeper), plus a few extra fields.
                    local record = ns.Browser.PetModels:GetModelsRecord(modelsData.NpcId[i])
                    if record then
                        if record.family then familyName = record.family end
                        table.insert(npcs, record)
                    end
                end
            end
            table.sort(npcs, function(a, b)
                return tonumber(a.npcId or 0) < tonumber(b.npcId or 0)
            end)
        end
    end

    popup.resolvedFamily = familyName

    self:PopulateModelPopup(popup, displayId, petData, npcs)

    popup:Show()
    popup:Raise()
end

-- ============================================================
-- PopulateModelPopup
-- ============================================================

function ns.PopUpManager:PopulateModelPopup(popup, displayId, petData, npcs)
    -- Auto-size only until the user picks a size. This was unconditional, so every
    -- populate recomputed an *absolute* target height and applied it -- resize the popup
    -- larger, click another Display ID, and it kept your width but snapped back to a
    -- shorter height. Width survived only because nothing recomputes it.
    --
    -- Gated here rather than at the two auto-size sites: both already branch on
    -- needsAutoSizing, so this is the one place that decides, and the rule is visible next
    -- to the flag rather than duplicated where it is consumed.
    --
    -- Session-scoped by design. The popup frame is created once and reused, so the choice
    -- survives closing and reopening, but nothing in the addon persists popup geometry to
    -- SavedVariables and this does not start.
    popup.needsAutoSizing = not popup.userSized
    popup.currentDisplayId = tonumber(displayId)
    popup.currentPetData = petData
    popup.currentNPCs = npcs or {}

    -- Info text
    local familyName = "Unknown"
    if petData and petData.familyName and petData.familyName ~= "" then
        familyName = petData.familyName
    elseif popup.resolvedFamily then
        familyName = popup.resolvedFamily
    elseif ns.state.modelsPanel and ns.state.modelsPanel.allModels then
        for _, m in ipairs(ns.state.modelsPanel.allModels) do
            if tonumber(m.displayId) == tonumber(displayId) then
                familyName = m.familyName or familyName
                break
            end
        end
    end
    popup.infoText:SetText(string.format("%s - Display ID: %d", familyName, displayId))

    -- Taming requirements
    local tamingData = nil
    if petData and petData.taming then
        tamingData = petData.taming
    elseif ns.state.modelsPanel and ns.state.modelsPanel.allModels and type(ns.state.modelsPanel.allModels) == "table" then
        for _, m in ipairs(ns.state.modelsPanel.allModels) do
            if tonumber(m.displayId) == tonumber(displayId) and m.taming then
                tamingData = m.taming
                break
            end
        end
    end

    -- Fallback to raw data for taming info (fixes Owned Pets panel display)
    if not tamingData and _G.ModelsData then
        local targetDisplayId = tonumber(displayId)
        if targetDisplayId then
            local modelsData = _G.ModelsData
            for i = 1, #modelsData.NpcId do
                local taming = modelsData.Taming[i]
                if taming then
                    local rawDisplayIds = modelsData.DisplayIds[i]
                    local dids = type(rawDisplayIds) == "table" and rawDisplayIds or { rawDisplayIds }
                    for _, did in ipairs(dids) do
                        if tonumber(did) == targetDisplayId then
                            tamingData = taming
                            break
                        end
                    end
                end
                if tamingData then break end
            end
        end
    end

    if tamingData and ns.Browser.TamingChecker then
        local parts = {}
        for _, ruleKey in ipairs(tamingData) do
            local rule = ns.Browser.TamingRules and ns.Browser.TamingRules[ruleKey]
            
            -- Only display formal taming unlocks at the model level; skip situational conditions
            if rule and not rule.isCondition then
                local status = ns.Browser.TamingChecker.GetRuleStatus(ruleKey)
                local label  = rule and rule.label or ruleKey
                local hint   = rule and rule.hint
                local color  = status == "met" and "ff00ff00" or "ffff4444"

                -- Build hint string with proper joining logic
                local hintStr = ""
                if hint then
                    if hint.plain then
                        hintStr = " (" .. hint.plain .. ")"
                    else
                        local mainParts = {}
                        local suffixPart = nil

                        -- Collect main alternatives (race or item or quest)
                        if hint.autoRace then
                            mainParts[#mainParts + 1] = hint.autoRace .. " (auto)"
                        end
                        if hint.itemID then
                            mainParts[#mainParts + 1] = string.format(
                                "|cff0070dd|Hpsmtaming:%s|h%s|h|r",
                                ruleKey,
                                hint.itemName or ("Item #" .. hint.itemID))
                        end
                        if hint.questID then
                            mainParts[#mainParts + 1] = string.format(
                                "|cff0070dd|Hpsmtaming:%s|h%s|h|r",
                                ruleKey,
                                hint.questName or ("Quest #" .. hint.questID))
                        end

                        -- Suffix is separate (not an alternative)
                        if hint.suffix then
                            suffixPart = hint.suffix
                        end

                        -- Build the hint string
                        if #mainParts > 0 then
                            hintStr = table.concat(mainParts, " or ")
                        end
                        if suffixPart then
                            if hintStr ~= "" then
                                hintStr = hintStr .. " " .. suffixPart
                            else
                                hintStr = suffixPart
                            end
                        end
                        if hintStr ~= "" then
                            hintStr = " (" .. hintStr .. ")"
                        end
                    end
                end

                parts[#parts + 1] = string.format("|c%s%s|r%s",
                    color,
                    label,
                    hintStr)
            end
        end
        local bodyContent
        if #parts >= 1 then
            local lines = {}
            
            for i, part in ipairs(parts) do
                if #parts > 1 then
                    -- Use bullet point for multiple requirements
                    lines[#lines + 1] = string.format("<p align='center'>• %s</p>", part)
                else
                    -- No number/bullet for single requirement
                    lines[#lines + 1] = string.format("<p align='center'>%s</p>", part)
                end
            end
            bodyContent = table.concat(lines, "")
        else
            bodyContent = ""
        end
        popup.tamingHTMLContent = "<html><body>" .. bodyContent .. "</body></html>"
        popup.tamingFrame:Show()
        UpdateTamingLayout(popup)
    else
        popup.tamingHTMLContent = nil
        popup.tamingFrame:Hide()
    end

    if npcs and #npcs > 0 then
        BuildNPCRows(popup, npcs)
    else
        popup.npcsScrollFrame:Hide()
        popup.npcsScrollBar:Hide()
        popup.lastCalculatedRowsH = 0

        -- Mirrors BuildNPCRows' auto-sizing: with no NPC rows, wait for the
        -- taming box's async height (if any) to settle, then size the window
        -- and resync the model frame so it doesn't keep a stale size left
        -- over from a previously viewed pet.
        if popup.needsAutoSizing then
            popup.needsAutoSizing = false
            ns.C_Timer.After(0.05, function()
                local tamingH = (popup.tamingFrame and popup.tamingFrame:IsShown()) and (popup.tamingFrame:GetHeight() or 0) or 0
                local targetH = 300 + 150 + tamingH
                popup:SetHeight(math.min(targetH, UIParent:GetHeight() * 0.85))
                if popup.UpdateModelFrameLayout then popup.UpdateModelFrameLayout() end
            end)
        end
    end
end

-- ============================================================
-- Note editor
-- ============================================================

-- Creates the note editor frame (once) and shows it for the given npcId.
-- parentPopup is passed so we can refresh the NPC text after saving; onSaved
-- is an optional extra callback for callers (e.g. the NPC Browser list) that
-- aren't backed by a popup's currentNPCs/BuildNPCRows refresh path.
function ns.PopUpManager:ShowNoteEditor(npcId, npcName, parentPopup, onSaved)
    -- Seed notes (PSM.NotesData) ship with the browser; the user's own notes live in
    -- PSM_UserNotes, a core SavedVariable, so the editor still works if this fails.
    ns.Loader:EnsureBrowser()

    if not self.noteEditor then
        local Theme, Widgets = ns.Theme, ns.Widgets

        local f = Widgets.MovableFrame(UIParent, {
            name     = "PSMNoteEditor",
            size     = { 450, 350 },
            point    = { "CENTER" },
            strata   = "TOOLTIP",
            level    = 1020,
            backdrop = "TOOLTIP_SMALL",
            color    = Theme.FILL.POPUP,
        })
        f:SetToplevel(true)
        f:SetResizable(true)
        f:SetResizeBounds(350, 250, 800, 800)

        -- Title
        f.title = Widgets.Label(f, {
            fontSize = Theme.SIZE.HEADING,
            outline  = true,
            color    = Theme.COLOR.GOLD,
            point    = { "TOP", 0, -10 },
        })

        -- Seed note label (shown only when a seed note exists)
        f.seedLabel = Widgets.Label(f, {
            fontSize = Theme.SIZE.SMALL,
            outline  = true,
            color    = Theme.COLOR.GREY,
            point    = { "TOPLEFT", f, "TOPLEFT", 20, -35 },
            text     = "Info note (read-only):",
        })

        -- Seed note text (read-only FontString)
        f.seedText = Widgets.Label(f, {
            fontSize = Theme.SIZE.BODY,
            color    = { 0.75, 0.75, 0.75 },
            justify  = "LEFT",
            point    = {
                { "TOPLEFT", f.seedLabel, "BOTTOMLEFT", 0,   -4 },
                { "RIGHT",   f,           "RIGHT",      -20,  0 },
            },
        })
        f.seedText:SetNonSpaceWrap(true)
        f.seedText:SetWordWrap(true)

        -- User note label
        f.userLabel = Widgets.Label(f, {
            fontSize = Theme.SIZE.SMALL,
            outline  = true,
            color    = Theme.COLOR.GREY,
            text     = "My note:",
        })

        -- Scroll frame + edit box for user note
        f.scrollFrame = Widgets.Frame(f, {
            frameType = "ScrollFrame",
            template  = "UIPanelScrollFrameTemplate",
            skin      = "scrollframe",
            point     = { "BOTTOMRIGHT", f, "BOTTOMRIGHT", -50, 45 },
        })
        ns.Skin.Apply(f.scrollFrame.ScrollBar, "scrollbar")

        f.editBox = Widgets.EditBox(f.scrollFrame, {
            multiline  = true,
            fontObject = "ChatFontNormal",
            textColor  = Theme.COLOR.WHITE,
            -- Escape here clears focus rather than closing: the frame's own
            -- OnKeyDown handles the second Escape and closes the editor.
            onEscape   = function(self) self:ClearFocus() end,
        })
        f.scrollFrame:SetScrollChild(f.editBox)

        -- Save button (its OnClick is wired per-call, below)
        f.saveButton = Widgets.Button(f, {
            width = ns.Theme.CONTROL.BUTTON_W.S,
            point = { "BOTTOMRIGHT", f, "BOTTOM", -5, 12 },
            text  = "Save",
        })

        -- Clear button
        f.clearButton = Widgets.Button(f, {
            width   = ns.Theme.CONTROL.BUTTON_W.S,
            point   = { "BOTTOMLEFT", f, "BOTTOM", 5, 12 },
            text    = "Clear",
            onClick = function()
                f.editBox:SetText("")
                f.editBox:SetFocus()
            end,
        })

        f.closeButton = Widgets.CloseButton(f, { level = f:GetFrameLevel() + 10 })

        Widgets.ResizeGrip(f)

        -- ESC clears focus first, second ESC closes
        Widgets.CloseOnEscape(f)

        f:SetScript("OnSizeChanged", function()
            f.editBox:SetWidth(f.scrollFrame:GetWidth())
        end)

        self.noteEditor = f
    end

    local f = self.noteEditor

    -- Populate seed note section
    local seedNote = ns.Browser.NotesData and ns.Browser.NotesData[npcId]
    if seedNote then
        f.seedLabel:Show()
        f.seedText:Show()
        f.seedText:SetText(seedNote)
        -- Anchor user label below seed text with a small gap
        f.userLabel:SetPoint("TOPLEFT", f.seedText, "BOTTOMLEFT", 0, -8)
    else
        f.seedLabel:Hide()
        f.seedText:Hide()
        -- No seed note: anchor user label near top
        f.userLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -35)
    end

    -- Anchor scroll frame below user label
    f.scrollFrame:SetPoint("TOPLEFT", f.userLabel, "BOTTOMLEFT", 0, -4)

    -- Populate user note edit box
    local userNote = (PSM_UserNotes and PSM_UserNotes[npcId]) or ""
    f.editBox:SetText(userNote)
    f.editBox:SetWidth(f.scrollFrame:GetWidth())

    -- Title
    f.title:SetText(string.format("Notes: %s", npcName or ("NPC " .. npcId)))

    -- Save wires up per-call npcId and refreshes the parent popup's NPC text
    f.saveButton:SetScript("OnClick", function()
        local text = f.editBox:GetText()
        ns.Browser.NotesData.SetUserNote(npcId, text)
        f:Hide()
        if parentPopup and parentPopup.currentNPCs then
            BuildNPCRows(parentPopup, parentPopup.currentNPCs)
        end
        if onSaved then onSaved() end
    end)

    f:Show()
    f:Raise()
    f.editBox:SetFocus()
end
