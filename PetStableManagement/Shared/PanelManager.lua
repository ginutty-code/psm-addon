-- Shared/PanelManager.lua
-- Unified panel management system for PetStableManagement
-- Handles creation and management of both OwnedPets and ModelsBrowser panels

local _, ns = ...

ns.PanelManager = ns.PanelManager or {}

-- ─── Helpers ──────────────────────────────────────────────────────────────────

-- Set backdrop color on a child frame if it exists
local function SetBg(parent, childKey, ...)
    local f = parent and parent[childKey]
    if f and f.SetBackdropColor then f:SetBackdropColor(...) end
end

-- Returns true when no PSM panel is currently visible
local function IsLastPanel()
    for _, key in ipairs({ "panel", "modelsPanel", "teamsPanel" }) do
        if ns.state[key] and ns.state[key]:IsVisible() then return false end
    end
    return true
end

-- ─── Combat guard ─────────────────────────────────────────────────────────────

-- The one check every PSM window makes before it opens, called from the one real "open"
-- verb per window rather than from every click handler that can reach it.
function ns.PanelManager:CombatBlocked(label)
    if not UnitAffectingCombat("player") then return false end
    ns.Utils:Msg("ERROR", ns.L("%s cannot open during combat.", label))
    return true
end

-- Tells the player *why* a panel is bigger than their screen. Fires on every show while
-- oversized, not just the first, and goes to UIErrorsFrame as well as chat -- a large
-- panel covers the chat frame, so chat alone is easy to miss.
local function WarnIfOversized(panel, title)
    local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
    local pw, ph = panel:GetWidth(), panel:GetHeight()
    if pw <= uw and ph <= uh then return end
    local message = ns.L("%s is larger than your screen at the current UI scale (%dx%d needed, %dx%d available). You can drag it from any blank area to bring different parts into view, but it may not all fit on screen at once. Lowering your UI scale in the game's Options avoids this entirely.",
        title or "This panel", math.floor(pw), math.floor(ph), math.floor(uw), math.floor(uh))
    if UIErrorsFrame then UIErrorsFrame:AddMessage(message, 1, 0.53, 0) end
    ns.Utils:Msg("WARNING", message)
end

-- ─── CreateBasePanel ─────────────────────────────────────────────────────────

function ns.PanelManager:CreateBasePanel(name, config)
    if ns.state[name] then return ns.state[name] end

    local Widgets = ns.Widgets
    local p = config.position

    local panel = Widgets.MovableFrame(UIParent, {
        name   = name,
        size   = { config.width  or ns.Config.DEFAULT_PANEL_WIDTH,
                   config.height or ns.Config.DEFAULT_PANEL_HEIGHT },
        point  = p and { p.point, p.relativeTo, p.relativePoint, p.x or 0, p.y or 0 }
                   or { "CENTER" },
        strata = config.strata    or "HIGH",
        level  = config.frameLevel or 50,
        skin   = "frame",
    })
    panel:SetToplevel(true)
    panel:SetClampedToScreen(true)

    -- At high enough Blizzard UI scale, a fixed-point panel (Models Browser is
    -- 1100x820) can exceed UIParent's shrunken effective size. Plain clamping is
    -- correct for a panel that fits -- it stops one being lost off-screen -- but for
    -- one that doesn't, it pins the oversized frame so the far edge can never be
    -- dragged back into reach.
    --
    -- SetClampRectInsets widens the clamp rect per edge, and the sign convention is NOT
    -- symmetric: left/bottom need *positive* values to permit overhang, right/top need
    -- *negative* ones. Backwards on left/bottom enforces a *minimum* distance from those
    -- edges instead, pinning the panel's top permanently off-screen.
    --
    -- Symmetric on all four edges, deliberately not pinning top/right: when the panel's
    -- height alone exceeds the screen, a pinned top makes the cut-off bottom unreachable
    -- by any drag. Letting every edge move lets the player trade which part is visible.
    panel:SetClampRectInsets(400, -400, -400, 400)

    -- ESC is the kit's job, not UISpecialFrames': these panels are created as "panel",
    -- "teamsPanel", "modelsPanel"..., so _G[name] is nil and Blizzard's path closes
    -- nothing. CloseOnEscape sets propagation *before* hiding -- doing it afterwards
    -- swallows the first key pressed after a panel opens. Non-ESCAPE keys propagate, so
    -- keybinds keep working while a panel is up.
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
        color     = ns.Config.COLORS.BACKGROUND,
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
    panel:SetScript("OnShow", function(self)
        WarnIfOversized(self, config.title)
        if config.onShow then config.onShow(self) end
    end)

    -- Maximize button
    if config.showMaximizeButton ~= false then
        panel.isMaximized = false
        local maxBtn = Widgets.Button(panel, {
            point      = { "TOPRIGHT", panel.closeButton, "TOPLEFT", -2, 0 },
            width      = ns.Theme.CONTROL.BUTTON_W.S,
            text       = ns.L("Maximize"),
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
                maxBtn:SetText(ns.L("Maximize"))
            else
                -- Save position relative to UIParent before maximizing
                local x, y = panel:GetLeft(), panel:GetTop()
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
                maxBtn:SetText(ns.L("Restore"))
            end
            if config.onResize then config.onResize(panel) end
        end)
        panel.maximizeButton = maxBtn
    end

    -- Title. Always at Theme.CHROME.TITLE_Y -- no per-panel override: CreateSearchBox
    -- anchors to panel.title, so moving it moves everything below it. A panel that needs
    -- more room below the toolbar moves *its own* chrome.
    if config.title then
        panel.title = Widgets.Label(panel, {
            fontSize = 14,
            outline  = true,
            text     = config.title,
            color    = ns.Theme.COLOR.GOLD,
            point    = { "TOP", 0, ns.Theme.CHROME.TITLE_Y },
        })
    end

    ns.state[name] = panel
    panel:Hide()
    return panel
end

-- ─── CreateSearchBox ─────────────────────────────────────────────────────────

function ns.PanelManager:CreateSearchBox(panel, onTextChanged, config)
    config = config or {}

    local Widgets = ns.Widgets

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
    searchBox.placeholderText = config.placeholder or ns.L("Search...")

    local function ShowPlaceholder(self)
        self:SetTextColor(unpack(ns.Theme.COLOR.FAINT))
        self:SetText(self.placeholderText)
    end
    local function ClearPlaceholder(self)
        if self:GetText() == self.placeholderText then
            self:SetText("")
            self:SetTextColor(unpack(ns.Theme.COLOR.WHITE))
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

    -- Deliver at once, cancelling any pending typing debounce. A programmatic change is a
    -- discrete event, not typing, so there is nothing to coalesce and nothing to wait for.
    local function NotifyNow(text)
        if debounceTimer then debounceTimer:Cancel(); debounceTimer = nil end
        if onTextChanged then onTextChanged(text) end
    end

    searchBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        ClearPlaceholder(self)
        -- GetSearchText, so the callback can never receive the placeholder either.
        local text = self:GetSearchText()
        if debounceTimer then debounceTimer:Cancel() end
        debounceTimer = C_Timer.NewTimer(ns.Config.SEARCH_DELAY or 0.3, function()
            if onTextChanged then onTextChanged(text) end
            debounceTimer = nil
        end)
    end)

    -- The query, as opposed to the raw contents: empty while the placeholder is on
    -- screen. Read this, never GetText -- treating the placeholder as input opens every
    -- panel filtered to a string the user never typed.
    function searchBox:GetSearchText()
        local text = self:GetText()
        if text == self.placeholderText then return "" end
        return text
    end

    -- Back to the idle state, placeholder and all. SetText("") alone leaves the box
    -- blank, since the placeholder is otherwise only restored when focus is lost.
    --
    -- A programmatic clear still notifies, which is what NotifyNow is for: ShowPlaceholder
    -- goes through SetText, whose OnTextChanged carries `userInput = false` and is ignored
    -- by the handler above, so without this a clear would change the screen and tell no
    -- one. Guarded on an actual change, so clearing an already-empty box stays quiet.
    function searchBox:ClearSearch()
        local hadText = self:GetSearchText() ~= ""
        self:ClearFocus()
        ShowPlaceholder(self)
        if hadText then NotifyNow("") end
    end

    -- Retarget the placeholder without disturbing what the user typed. Assigning
    -- placeholderText and calling SetText directly fires the handler above and clears it.
    function searchBox:SetPlaceholder(text)
        local showing = self:GetText() == self.placeholderText or self:GetText() == ""
        self.placeholderText = text
        if showing and not self:HasFocus() then ShowPlaceholder(self) end
    end

    ShowPlaceholder(searchBox)
    panel.searchBox = searchBox
    return searchBox
end

-- ─── CreatePillBar ───────────────────────────────────────────────────────────

-- The TOP_BAR filter-bar variant, built from a flat list of tag names. Lifted out of
-- Ability Browser and Special Tames, which each hand-rolled an identical copy --
-- same anchor, same tab sizing, same active-state tracking, differing only in what
-- `onSelect` did with the clicked tag. That difference stays at the call site;
-- `panel.activeTag` is never set here, since the two callers disagree on what "All"
-- means (Ability Browser maps it to `""`, Special Tames keeps the literal tag name).
function ns.PanelManager:CreatePillBar(panel, tags, onSelect)
    local Widgets = ns.Widgets

    local pillBar = Widgets.Frame(panel, {
        height = 24,
        point  = {
            { "TOPLEFT",  panel, "TOPLEFT",   20, ns.Theme.CHROME.FILTER_TOP },
            { "TOPRIGHT", panel, "TOPRIGHT", -20, ns.Theme.CHROME.FILTER_TOP },
        },
    })

    local pills = {}
    local xOff  = 0

    local function SetActive(activeIdx)
        for i, pill in ipairs(pills) do
            pill:SetActive(i == activeIdx)
        end
    end

    for idx, tagName in ipairs(tags) do
        local labelW = #tagName * 7 + 16

        local pill = Widgets.Tab(pillBar, {
            frameType = "Button",
            size      = { labelW, 20 },
            point     = { "LEFT", pillBar, "LEFT", xOff, 0 },
            fontSize  = ns.Config.FONT_SIZES.ABILITY_PILL,
            text      = tagName,
        })

        pill:SetScript("OnClick", function()
            SetActive(idx)
            if onSelect then onSelect(tagName, idx) end
        end)

        xOff = xOff + labelW + 6
        pills[idx] = pill
    end

    SetActive(1)
    panel.pills   = pills
    panel.pillBar = pillBar
    return pillBar
end

-- ─── CreateFooterLabel ───────────────────────────────────────────────────────

-- The one footer contract: a bare label, no border, no hairline. `statsText` on
-- Owned Pets/Teams already looked like this; Ability Browser/Special Tames' bordered
-- `CreateFooter` (hairline + frame) is what changed to match, not the other way
-- around -- see A13.
function ns.PanelManager:CreateFooterLabel(panel, opts)
    opts = opts or {}
    return ns.Widgets.Label(panel, {
        fontSize = opts.fontSize or ns.Theme.SIZE.SMALL,
        outline  = opts.outline,
        color    = opts.color or ns.Theme.COLOR.GOLD,
        point    = opts.point or { "BOTTOM", 0, ns.Theme.CHROME.FOOTER_Y },
        text     = opts.text,
    })
end

-- ─── CreateViewButton ────────────────────────────────────────────────────────

-- The "Views" contract slot: title-bar strip, right-to-left, chained off the
-- previous view button or (for the first one) off Maximize/Close. Owned Pets'
-- List/Grid/Grouped buttons and Models Browser's Models/NPC toggle both go through
-- this instead of each re-anchoring the same row by hand.
function ns.PanelManager:CreateViewButton(panel, opts)
    return ns.Widgets.Button(panel, {
        point      = { "TOPRIGHT", opts.rightAnchor or panel.maximizeButton or panel.closeButton, "TOPLEFT", -5, 0 },
        width      = opts.width or ns.Theme.CONTROL.BUTTON_W.S,
        text       = opts.text,
        fontObject = "GameFontNormalSmall",
        onClick    = opts.onClick,
        tooltip    = opts.tooltip,
    })
end

-- ─── CleanupPanel ────────────────────────────────────────────────────────────

function ns.PanelManager:CleanupPanel(panel)
    if ns.Data and ns.Data.SaveSettings then ns.Data:SaveSettings() end

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
                ns.RowManager:ReleaseModel(row.model)
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
        -- CreateRenderCache rather than clearing a field: the computed render data lives in
        -- the selector's closure now, so dropping it is the only way to release it.
        ns.UI:CreateRenderCache()
        ns._debounceTimer = nil

        -- The browser's own caches, released by the browser: reaching in and nil-ing them
        -- from here would drop its live C_Timer handles without cancelling them, letting
        -- a pending render refill what was just cleared.
        local browserPanel = ns.Browser.ModelsPanel
        if browserPanel and browserPanel.ReleaseCaches then
            browserPanel:ReleaseCaches()
        end

        if ns.Browser.PetModels and ns.Browser.PetModels.ClearCache then
            ns.Browser.PetModels:ClearCache()
        end
        if ns.Data and ns.Data.ClearUIRows then
            ns.Data:ClearUIRows()
        end
        if ns.Data and ns.Data.ClearMemory and not ns.state.isStableOpen then
            ns.Data:ClearMemory()
        end
    end
end

-- ─── Misc public helpers ──────────────────────────────────────────────────────

function ns.PanelManager:Initialize()
    ns.state = ns.state or {}
end

-- `label` is what CombatBlocked prints -- the panel's own title text. Hiding an
-- open panel never needs the guard, only showing one does, so a panel already open
-- when combat starts can still be closed by the same button that opens it.
function ns.PanelManager:TogglePanel(panelName, createFunc, label)
    local existing = ns.state[panelName]
    if existing and existing:IsVisible() then
        existing:Hide()
        return
    end
    if self:CombatBlocked(label) then return end
    if not existing then createFunc() end
    local p = ns.state[panelName]
    p:Show()
    p:Raise()
end

function ns.PanelManager:UpdatePanelBackgrounds()
    local alpha = ns.Config:GetOpacity()
    local bg    = ns.Config.COLORS.BACKGROUND

    -- Panels with a .border child
    for _, key in ipairs({ "panel", "modelsPanel", "teamsPanel", "abilityBrowser", "specialTames",
                           "menu", "petRoulettePopup", "modelMagnificationPopup" }) do
        SetBg(ns.state[key], "border", unpack(
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
        SetBg(ns.state[entry[1]], entry[2], unpack(bg))
    end

    -- Export frame
    local ef = ns.state.exportFrame
    SetBg(ef, "border", 0, 0, 0, alpha)
    SetBg(ef, "editBg", 0.1, 0.1, 0.1, alpha)

    -- Dropdown backdrops
    local p = ns.state.panel
    for _, dropKey in ipairs({ "specDrop", "familyDrop" }) do
        SetBg(p and p[dropKey], "backdrop", 0.1, 0.1, 0.1, alpha)
    end

    -- Teams panel opacity
    if ns.state.teamsPanel then
        ns.TeamsPanel:UpdateOpacity()
    end
end

-- No cache invalidation here, and no parameter for one: the width this handler changes is
-- `panelWidth`, a store slice, so the render selector sees the resize on its own via the
-- `renderCallback` below.
function ns.PanelManager:CreateScrollPreservingResizeHandler(panel, scrollFrame, content, renderCallback)
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

        ns.C_Timer.After(0.05, function()
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
                if ns.UI and ns.UI.ClampScrollIntoRange then
                    ns.UI:ClampScrollIntoRange(scrollFrame, content)
                end
            end

            -- PlayerModel widgets can repaint blank after their clipped ancestor
            -- (scrollFrame/content/row) is resized. A second, immediate
            -- UpdateVisibleRows pass forces them to redraw, mirroring what a
            -- manual scroll already does to "fix" the same symptom.
            ns.C_Timer.After(0, function()
                if ns.UI and ns.UI.UpdateVisibleRows then ns.UI:UpdateVisibleRows() end
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
        panel._resizeSettleTimer = ns.C_Timer.NewTimer(0.15, function()
            panel._resizeSettleTimer = nil
            Relayout(panel:GetWidth(), panel:GetHeight())
        end)

        if math.abs((panel._resizeLastWidth  or 0) - width)  < 10
        and math.abs((panel._resizeLastHeight or 0) - height) < 10 then return end

        Relayout(width, height)
    end)
end

ns.PanelManager:Initialize()