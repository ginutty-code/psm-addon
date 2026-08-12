-- Shared/PanelManager.lua
-- Unified panel management system for PetStableManagement
-- Handles creation and management of both OwnedPets and ModelsBrowser panels

local addonName = "PetStableManagement"

_G.PSM = _G.PSM or {}
local PSM = _G.PSM

PSM.PanelManager = PSM.PanelManager or {}

-- ─── Helpers ──────────────────────────────────────────────────────────────────

-- Set backdrop color on a child frame if it exists
local function SetBg(parent, childKey, ...)
    local f = parent and parent[childKey]
    if f and f.SetBackdropColor then f:SetBackdropColor(...) end
end

-- Returns true when no PSM panel is currently visible
local function IsLastPanel()
    for _, key in ipairs({ "panel", "modelsPanel", "teamsPanel" }) do
        if PSM.state[key] and PSM.state[key]:IsVisible() then return false end
    end
    return true
end

-- ─── CreateBasePanel ─────────────────────────────────────────────────────────

function PSM.PanelManager:CreateBasePanel(name, config)
    if PSM.state[name] then return PSM.state[name] end

    local panel = CreateFrame("Frame", name, UIParent)
    panel:SetSize(config.width  or PSM.Config.DEFAULT_PANEL_WIDTH,
                  config.height or PSM.Config.DEFAULT_PANEL_HEIGHT)

    if config.position then
        local p = config.position
        panel:SetPoint(p.point, p.relativeTo, p.relativePoint, p.x or 0, p.y or 0)
    else
        panel:SetPoint("CENTER")
    end

    panel:SetFrameStrata(config.strata     or "HIGH")
    panel:SetFrameLevel(config.frameLevel  or 50)
    panel:SetToplevel(true)
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function() panel:StartMoving() end)
    panel:SetScript("OnDragStop",  function() panel:StopMovingOrSizing() end)

    PSM.UI:ApplyElvUISkin(panel, "frame")

    -- ESC key
    panel:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:Hide()
            if config.onEscape then config.onEscape(self) end
            self:SetPropagateKeyboardInput(false)
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    panel:EnableKeyboard(true)
    panel:SetPropagateKeyboardInput(true)

    -- Resizable
    if config.resizable ~= false then
        panel:SetResizable(true)
        if panel.SetResizeBounds then
            panel:SetResizeBounds(
                config.minWidth  or 400,
                config.minHeight or 300,
                config.maxWidth  or (UIParent:GetWidth()  or 1920) - 16,
                config.maxHeight or (UIParent:GetHeight() or 1080) - 16)
        end
    end

    -- Resize handle
    if config.showResizeHandle ~= false then
        local grip = CreateFrame("Button", nil, panel)
        grip:SetSize(16, 16)
        grip:SetPoint("BOTTOMRIGHT", -2, 2)
        grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
        grip:SetScript("OnMouseDown", function(_, btn)
            if btn == "LeftButton" then panel:StartSizing("BOTTOMRIGHT") end
        end)
        grip:SetScript("OnMouseUp", function() panel:StopMovingOrSizing() end)
        PSM.UI:ApplyElvUISkin(grip, "resizegrip")
        panel.resizeButton = grip
    end

    -- Background / border
    panel.border = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    panel.border:SetAllPoints()
    panel.border:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 30, edgeSize = 5,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    panel.border:SetBackdropColor(unpack(PSM.Config.COLORS.BACKGROUND))
    panel.border:SetFrameLevel(panel:GetFrameLevel() - 1)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    closeBtn:SetSize(20, 20)
    closeBtn:SetFrameLevel(panel:GetFrameLevel() + 10)
    closeBtn:SetScript("OnClick", function() panel:Hide() end)
    PSM.UI:ApplyElvUISkin(closeBtn, "closebutton")
    panel.closeButton = closeBtn

    -- Show/Hide callbacks
    panel:SetScript("OnHide", function(self)
        -- A context menu opened from this panel is parented to UIParent, so it
        -- outlives the panel unless something closes it. Blizzard's Escape path
        -- (CloseAllWindows) does that for UISpecialFrames, but our own OnKeyDown
        -- above consumes ESCAPE and suppresses propagation, so it usually never
        -- runs -- and the X button, the minimap toggle and /psm never go near it
        -- at all. Closing here covers every route out of a panel.
        CloseDropDownMenus()
        if config.onHide then config.onHide(self) end
    end)
    panel:SetScript("OnShow", function(self) if config.onShow then config.onShow(self) end end)

    -- Maximize button
    if config.showMaximizeButton ~= false then
        panel.isMaximized = false
        local maxBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        maxBtn:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", -2, 0)
        maxBtn:SetSize(PSM.Config.PANEL_BUTTON_WIDTH, PSM.Config.PANEL_BUTTON_HEIGHT)
        maxBtn:SetText("Maximize")
        maxBtn:SetNormalFontObject("GameFontNormalSmall")
        PSM.UI:ApplyElvUISkin(maxBtn, "button")

        maxBtn:SetScript("OnClick", function()
            if panel.isMaximized then
                panel.isMaximized = false
                local g = panel._prevGeometry
                panel:ClearAllPoints()
                if g then
                    panel:SetSize(g.width, g.height)
                    panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", g.x, g.y)
                else
                    panel:SetPoint("TOPLEFT", StableFrame, "TOPRIGHT", 0, 0)
                end
                maxBtn:SetText("Maximize")
            else
                -- Save position relative to UIParent before maximizing
                local x, y = panel:GetLeft(), panel:GetTop()
                local uiScale = UIParent:GetEffectiveScale()
                panel._prevGeometry = {
                    width  = panel:GetWidth(),
                    height = panel:GetHeight(),
                    x      = x or 0,
                    y      = (y or UIParent:GetHeight()) - UIParent:GetHeight(),
                }
                panel.isMaximized = true
                panel:ClearAllPoints()
                panel:SetPoint("TOPLEFT",     UIParent, "TOPLEFT",     8,  -8)
                panel:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -8,  8)
                maxBtn:SetText("Restore")
            end
            if config.onResize then config.onResize(panel) end
        end)
        panel.maximizeButton = maxBtn
    end

    -- Title
    if config.title then
        local t = panel:CreateFontString(nil, "OVERLAY")
        t:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
        -- Models panel title sits higher to avoid search box overlap
        t:SetPoint("TOP", 0, config.title == "Pet Model Browser" and -20 or -35)
        t:SetText(config.title)
        t:SetTextColor(1, 0.82, 0)
        panel.title = t
    end

    if config.escKeyframe then
        table.insert(UISpecialFrames, config.escKeyframe)
    end

    PSM.state[name] = panel
    panel:Hide()
    return panel
end

-- ─── CreateSearchBox ─────────────────────────────────────────────────────────

function PSM.PanelManager:CreateSearchBox(panel, onTextChanged, config)
    config = config or {}

    local searchBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    searchBox:SetSize(config.width or 150, config.height or 20)
    searchBox:SetPoint("TOP", panel.title, "BOTTOM", 0, config.yOffset or -10)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(config.maxLetters or 50)
    -- Mutable so callers (e.g. a view-mode toggle) can retarget the placeholder text later.
    searchBox.placeholderText = config.placeholder or "Search..."

    -- Placeholder helpers
    local function ShowPlaceholder(self)
        self:SetTextColor(0.5, 0.5, 0.5)
        self:SetText(self.placeholderText)
    end
    local function ClearPlaceholder(self)
        if self:GetText() == self.placeholderText then
            self:SetText("")
            self:SetTextColor(1, 1, 1)
        end
    end

    searchBox:SetScript("OnEditFocusGained", ClearPlaceholder)
    searchBox:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then ShowPlaceholder(self) end
    end)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Debounced text changed
    local debounceTimer
    searchBox:SetScript("OnTextChanged", function(self)
        local wasPlaceholder = self:GetText() == self.placeholderText
        ClearPlaceholder(self)
        local text = self:GetText()
        if wasPlaceholder and text == "" then return end
        if debounceTimer then debounceTimer:Cancel() end
        debounceTimer = C_Timer.NewTimer(PSM.Config.SEARCH_DELAY or 0.3, function()
            if onTextChanged then onTextChanged(text) end
            debounceTimer = nil
        end)
    end)

    ShowPlaceholder(searchBox)
    PSM.UI:ApplyElvUISkin(searchBox, "editbox")
    panel.searchBox = searchBox
    return searchBox
end

-- ─── CleanupPanel ────────────────────────────────────────────────────────────

function PSM.PanelManager:CleanupPanel(panel)
    if PSM.Data and PSM.Data.SaveSettings then PSM.Data:SaveSettings() end

    panel.allModels = nil
    -- allModels' NPC-view counterpart, missing before -- also clears
    -- _npcSortCache since it holds a direct reference to the same items table.
    panel.allNPCs = nil
    panel._npcSortCache = nil
    panel.ownedDisplayIdSet = nil

    -- Clear model rows
    for _, row in ipairs(panel.modelRows or {}) do
        if row then
            for _, key in ipairs({ "npcText", "nameText", "infoText" }) do
                if row[key] then row[key]:SetText(""); row[key]:Hide() end
            end
            for _, t in ipairs(row.npcTexts or {}) do t:SetText(""); t:Hide() end
            if row.model then
                row.model:SetDisplayInfo(0)
                row.model:Hide()
                if PSM.RotationFrame then
                    PSM.RotationFrame.activeModels[row.model] = nil
                end
            end
            if row.favoriteButton then row.favoriteButton:Hide() end
            row:Hide()
        end
    end

    -- Clear NPC-view rows (drop each row's reference to its last-shown item)
    for _, row in ipairs(panel.npcRows or {}) do
        if row then
            row.currentItem = nil
            row:Hide()
        end
    end

    -- Clear team rows
    for _, row in ipairs(panel.teamRows or {}) do
        if row then
            for _, tex in ipairs(row.petIcons or {}) do
                if tex then tex:Hide() end
            end
            for _, c in ipairs(row.petIconContainers or {}) do
                if c then
                    c:SetScript("OnEnter",    nil)
                    c:SetScript("OnLeave",    nil)
                    c:SetScript("OnMouseDown",nil)
                    c:SetScript("OnMouseUp",  nil)
                end
            end
            for _, key in ipairs({ "applyButton", "renameButton", "duplicateButton", "deleteButton" }) do
                if row[key] then row[key]:SetScript("OnClick", nil) end
            end
            row:Hide()
        end
    end

    if IsLastPanel() then
        PSM._renderCache        = nil
        PSM._debounceTimer      = nil
        PSM._modelsRenderCache  = nil
        PSM._modelsDebounceTimer = nil
        PSM._npcRenderCache     = nil
        PSM._npcDebounceTimer   = nil

        if PSM.PetModels and PSM.PetModels.ClearCache then
            PSM.PetModels:ClearCache()
        end
        if PSM.Data and PSM.Data.ClearUIRows then
            PSM.Data:ClearUIRows()
        end
        if PSM.Data and PSM.Data.ClearMemory and not PSM.state.isStableOpen then
            PSM.Data:ClearMemory()
        end
    end

    C_Timer.After(0.5, function() collectgarbage("collect") end)
end

-- ─── Misc public helpers ──────────────────────────────────────────────────────

function PSM.PanelManager:Initialize()
    PSM.state = PSM.state or {}
end

function PSM.PanelManager:TogglePanel(panelName, createFunc)
    if not PSM.state[panelName] then createFunc() end
    local p = PSM.state[panelName]
    if p:IsVisible() then p:Hide() else p:Show(); p:Raise() end
end

function PSM.PanelManager:UpdatePanelBackgrounds()
    local alpha = PSM.Config:GetOpacity()
    local bg    = PSM.Config.COLORS.BACKGROUND

    -- Panels with a .border child
    for _, key in ipairs({ "panel", "modelsPanel", "teamsPanel", "abilityBrowser", "specialTames",
                           "menu", "petRoulettePopup", "modelMagnificationPopup" }) do
        SetBg(PSM.state[key], "border", unpack(
            (key == "petRoulettePopup" or key == "modelMagnificationPopup")
                and { 0, 0, 0, alpha } or bg))
    end

    -- Named sub-frames using the main bg color
    local bgFrames = {
        { "panel",       "rowsFrame"           },
        { "modelsPanel", "petsFrame"            },
        { "modelsPanel", "unifiedFilterFrame"   },
        { "teamsPanel",  "teamsFrame"           },
    }
    for _, entry in ipairs(bgFrames) do
        SetBg(PSM.state[entry[1]], entry[2], unpack(bg))
    end

    -- Export frame
    local ef = PSM.state.exportFrame
    if ef and ef.SetBackdropColor then ef:SetBackdropColor(0, 0, 0, alpha) end
    SetBg(ef, "editBg", 0.1, 0.1, 0.1, alpha)

    -- Dropdown backdrops
    local p = PSM.state.panel
    for _, dropKey in ipairs({ "specDrop", "familyDrop" }) do
        SetBg(p and p[dropKey], "backdrop", 0.1, 0.1, 0.1, alpha)
    end

    -- Teams panel opacity
    if PSM.state.teamsPanel then
        PSM.TeamsPanel:UpdateOpacity()
    end
end

function PSM.PanelManager:CreateScrollPreservingResizeHandler(panel, scrollFrame, content, renderCallback, invalidateCacheCallback)
    if not panel or not scrollFrame or not content then return end

    panel._resizeLastWidth  = nil
    panel._resizeLastHeight = nil

    panel:SetScript("OnSizeChanged", function(_, width, height)
        if math.abs((panel._resizeLastWidth  or 0) - width)  < 10
        and math.abs((panel._resizeLastHeight or 0) - height) < 10 then return end

        panel._resizeLastWidth  = width
        panel._resizeLastHeight = height

        -- Snapshot scroll position as a percentage
        local scrollPercentage = 0
        local scrollBar = scrollFrame.ScrollBar
        if scrollBar then
            local maxScroll = math.max(0, content:GetHeight() - scrollFrame:GetHeight())
            if maxScroll > 0 then scrollPercentage = scrollBar:GetValue() / maxScroll end
        end

        scrollFrame:SetWidth(width - 40)
        content:SetWidth(scrollFrame:GetWidth())
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT")
        content:SetPoint("TOPRIGHT")

        if invalidateCacheCallback then invalidateCacheCallback() else PSM._renderCache = nil end

        PSM.C_Timer.After(0.05, function()
            if renderCallback then renderCallback(true) end
            if scrollBar and content and scrollFrame then
                local maxScroll = math.max(0, content:GetHeight() - scrollFrame:GetHeight())
                if maxScroll > 0 then scrollBar:SetValue(maxScroll * scrollPercentage) end
            end

            -- PlayerModel widgets can repaint blank after their clipped ancestor
            -- (scrollFrame/content/row) is resized. A second, immediate
            -- UpdateVisibleRows pass forces them to redraw, mirroring what a
            -- manual scroll already does to "fix" the same symptom.
            PSM.C_Timer.After(0, function()
                if PSM.UI and PSM.UI.UpdateVisibleRows then PSM.UI:UpdateVisibleRows() end
            end)
        end)
    end)
end

PSM.PanelManager:Initialize()