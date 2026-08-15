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

    local Widgets = PSM.Widgets
    local p = config.position

    local panel = Widgets.MovableFrame(UIParent, {
        name   = name,
        size   = { config.width  or PSM.Config.DEFAULT_PANEL_WIDTH,
                   config.height or PSM.Config.DEFAULT_PANEL_HEIGHT },
        point  = p and { p.point, p.relativeTo, p.relativePoint, p.x or 0, p.y or 0 }
                   or { "CENTER" },
        strata = config.strata    or "HIGH",
        level  = config.frameLevel or 50,
        skin   = "frame",
    })
    panel:SetToplevel(true)
    panel:SetClampedToScreen(true)

    -- ESC. This looks like it could be left to Blizzard, because every panel used to
    -- pass an `escKeyframe` for UISpecialFrames -- but those names never resolved. The
    -- frames are created as "panel", "teamsPanel", "modelsPanel"..., while the strings
    -- registered were "PetStableManagementPanel", "PSMTeamsPanel" and so on, so
    -- _G[name] was nil for every one of them and Blizzard's path closed nothing. The
    -- hand-written handler that used to sit here was the only thing that worked, and
    -- removing it in favour of the registration broke Escape on all five panels.
    --
    -- One owner, and it is the kit's: CloseOnEscape sets propagation *before* hiding,
    -- where the old hand-written version set it afterwards and only on the following
    -- keystroke -- which is why the first key pressed after opening a panel used to go
    -- missing. Non-ESCAPE keys propagate, so keybinds keep working while a panel is up.
    --
    -- `config.onEscape` is not wired through: nothing ever passed one. (The onEscape
    -- options elsewhere in the addon belong to Widgets.EditBox, a different callback on
    -- a different widget.)
    Widgets.CloseOnEscape(panel)

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

    -- Resize handle. ResizeGrip calls SetResizable itself, so it is created only when
    -- the panel is actually resizable -- a grip on a fixed panel used to be built and
    -- do nothing.
    if config.showResizeHandle ~= false and config.resizable ~= false then
        panel.resizeButton = Widgets.ResizeGrip(panel, {
            point = { "BOTTOMRIGHT", panel, "BOTTOMRIGHT", -2, 2 },
        })
    end

    -- Background / border
    panel.border = Widgets.Frame(panel, {
        allPoints = true,
        backdrop  = "TOOLTIP_HAIRLINE",
        color     = PSM.Config.COLORS.BACKGROUND,
        level     = panel:GetFrameLevel() - 1,
    })

    panel.closeButton = Widgets.CloseButton(panel, {
        point = { "TOPRIGHT", -5, -5 },
        size  = { 20, 20 },
        level = panel:GetFrameLevel() + 10,
    })

    -- Show/Hide callbacks
    panel:SetScript("OnHide", function(self)
        -- A context menu opened from this panel is parented to UIParent, so it
        -- outlives the panel unless something closes it. Blizzard's Escape path
        -- does that for UISpecialFrames, but the X button, the minimap toggle and
        -- /psm never go near it. Closing here covers every route out of a panel.
        CloseDropDownMenus()
        if config.onHide then config.onHide(self) end
    end)
    panel:SetScript("OnShow", function(self) if config.onShow then config.onShow(self) end end)

    -- Maximize button
    if config.showMaximizeButton ~= false then
        panel.isMaximized = false
        local maxBtn = Widgets.Button(panel, {
            point      = { "TOPRIGHT", panel.closeButton, "TOPLEFT", -2, 0 },
            size       = { PSM.Config.PANEL_BUTTON_WIDTH, PSM.Config.PANEL_BUTTON_HEIGHT },
            text       = "Maximize",
            fontObject = "GameFontNormalSmall",
        })

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

    -- Title. `titleOffset` is a config value rather than a test on the title text: this
    -- used to read `config.title == "Pet Model Browser" and -20 or -35`, so a shared
    -- component's layout depended on one caller's exact display string, and renaming
    -- that panel would silently have moved its title.
    if config.title then
        panel.title = Widgets.Label(panel, {
            fontSize = 14,
            outline  = true,
            text     = config.title,
            color    = PSM.Theme.COLOR.GOLD,
            point    = { "TOP", 0, config.titleOffset or -35 },
        })
    end

    PSM.state[name] = panel
    panel:Hide()
    return panel
end

-- ─── CreateSearchBox ─────────────────────────────────────────────────────────

function PSM.PanelManager:CreateSearchBox(panel, onTextChanged, config)
    config = config or {}

    local Widgets = PSM.Widgets

    local searchBox = Widgets.EditBox(panel, {
        size     = { config.width or 150, config.height or 20 },
        point    = { "TOP", panel.title, "BOTTOM", 0, config.yOffset or -10 },
        -- Both keys dismiss focus. Search is live, so there is nothing to "submit";
        -- Enter just means "done typing", and Escape must not fall through to the
        -- panel's own Escape handler and close the whole window mid-search.
        onEnter  = function(self) self:ClearFocus() end,
        onEscape = function(self) self:ClearFocus() end,
    })
    searchBox:SetMaxLetters(config.maxLetters or 50)

    -- Placeholder helpers. `placeholderText` is mutable so a view-mode toggle can
    -- retarget it; SetPlaceholder below is the supported way to do that.
    searchBox.placeholderText = config.placeholder or "Search..."

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

    -- `userInput` is the whole fix here, and it was previously ignored.
    --
    -- SetText fires OnTextChanged just as typing does. So showing the placeholder ran
    -- this handler, which saw text == placeholderText, called ClearPlaceholder, and
    -- blanked the box it had just filled -- the placeholder erased itself, and
    -- retargeting it erased whatever the user had typed. Blizzard passes userInput =
    -- false for programmatic changes precisely so a handler can tell the two apart.
    local debounceTimer
    searchBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        ClearPlaceholder(self)
        -- GetSearchText, so the callback can never receive the placeholder either.
        local text = self:GetSearchText()
        if debounceTimer then debounceTimer:Cancel() end
        debounceTimer = C_Timer.NewTimer(PSM.Config.SEARCH_DELAY or 0.3, function()
            if onTextChanged then onTextChanged(text) end
            debounceTimer = nil
        end)
    end)

    -- The query, as opposed to the raw contents: empty while the placeholder is on
    -- screen. **Read this, never GetText.** The placeholder is decoration; treating it
    -- as input makes every panel open filtered to a string the user never typed, which
    -- is exactly what happened once the placeholder started displaying reliably -- nine
    -- call sites were reading GetText and had only ever worked because the placeholder
    -- used to erase itself.
    function searchBox:GetSearchText()
        local text = self:GetText()
        if text == self.placeholderText then return "" end
        return text
    end

    -- Back to the idle state, placeholder and all. SetText("") alone leaves the box
    -- blank, since the placeholder is otherwise only restored when focus is lost.
    function searchBox:ClearSearch()
        self:ClearFocus()
        ShowPlaceholder(self)
    end

    -- Retarget the placeholder without disturbing what the user typed. Callers used to
    -- assign placeholderText and call SetText themselves, which fired the handler above
    -- and cleared the box.
    function searchBox:SetPlaceholder(text)
        local showing = self:GetText() == self.placeholderText or self:GetText() == ""
        self.placeholderText = text
        if showing and not self:HasFocus() then ShowPlaceholder(self) end
    end

    ShowPlaceholder(searchBox)
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

    local function Relayout(width, height)
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
            if content and scrollFrame then
                -- Restore the proportional position, then clamp. The old form was
                -- `if maxScroll > 0 then SetValue(...) end`, which skipped the one case
                -- that had to be handled: maxScroll == 0 means the content now fits, and
                -- a frame still scrolled to its old position shows the empty region past
                -- the last row. See PSM.UI:ClampScrollIntoRange.
                local maxScroll = math.max(0, content:GetHeight() - scrollFrame:GetHeight())
                local target    = math.min(maxScroll * scrollPercentage, maxScroll)
                scrollFrame:SetVerticalScroll(target)
                if scrollBar then scrollBar:SetValue(target) end
                if PSM.UI and PSM.UI.ClampScrollIntoRange then
                    PSM.UI:ClampScrollIntoRange(scrollFrame, content)
                end
            end

            -- PlayerModel widgets can repaint blank after their clipped ancestor
            -- (scrollFrame/content/row) is resized. A second, immediate
            -- UpdateVisibleRows pass forces them to redraw, mirroring what a
            -- manual scroll already does to "fix" the same symptom.
            PSM.C_Timer.After(0, function()
                if PSM.UI and PSM.UI.UpdateVisibleRows then PSM.UI:UpdateVisibleRows() end
            end)
        end)
    end

    panel:SetScript("OnSizeChanged", function(_, width, height)
        -- A trailing pass, always scheduled and always against the *current* size.
        --
        -- The 10px early-out below keeps the expensive relayout off most drag frames,
        -- but it is a leading filter with nothing behind it: whatever size the drag
        -- comes to rest on can be up to 10px from the last size actually laid out. Nine
        -- pixels is invisible until a column boundary falls inside them, and then the
        -- panel keeps a column count its width no longer fits, with no further event
        -- coming to correct it. That is a resize blind spot by construction, and no
        -- amount of clamping downstream can see it — the layout is self-consistent, it
        -- just describes a width the panel no longer has.
        if panel._resizeSettleTimer then panel._resizeSettleTimer:Cancel() end
        panel._resizeSettleTimer = PSM.C_Timer.NewTimer(0.15, function()
            panel._resizeSettleTimer = nil
            Relayout(panel:GetWidth(), panel:GetHeight())
        end)

        if math.abs((panel._resizeLastWidth  or 0) - width)  < 10
        and math.abs((panel._resizeLastHeight or 0) - height) < 10 then return end

        Relayout(width, height)
    end)
end

PSM.PanelManager:Initialize()