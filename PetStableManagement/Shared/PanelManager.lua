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

-- Tells the player *why* a panel needed the clamp-inset workaround above, rather than
-- leaving them to guess after finding a panel bigger than their screen. Fires on every
-- show while oversized, not just the first -- a one-time-per-session version missed a
-- player who didn't catch it the first time and had no way to see it again. Same
-- reasoning as `GroupedView.lua`'s `ReportGroupFailure`: a message that only goes to
-- chat is easy to miss with a large panel covering the chat frame, so this uses
-- UIErrorsFrame too -- it renders in front of whatever's on screen, chat keeps the
-- permanent record.
local function WarnIfOversized(panel, title)
    local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
    local pw, ph = panel:GetWidth(), panel:GetHeight()
    if pw <= uw and ph <= uh then return end
    local message = ns.L("%s is larger than your screen at the current UI scale (%dx%d needed, %dx%d available). You can drag it from any blank area to bring different parts into view, but it may not all fit on screen at once. Lowering your UI scale in the game's Options avoids this entirely.",
        title or "This panel", math.floor(pw), math.floor(ph), math.floor(uw), math.floor(uh))
    if UIErrorsFrame then UIErrorsFrame:AddMessage(message, 1, 0.53, 0) end
    print("|cffff8800" .. message .. "|r")
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
    -- SetClampRectInsets widens (or narrows) the clamp rect per edge, and the sign
    -- convention is NOT symmetric -- confirmed against Wowpedia's own example
    -- (`SetClampRectInsets(42, -42, -42, 42)`, permitting overhang on every edge):
    -- left/bottom need *positive* values to permit overhang, right/top need
    -- *negative* values. Getting this backwards on left/bottom doesn't just fail to
    -- help -- it actively enforces a *minimum* distance from those edges, which is
    -- how the first version of this fix pinned a panel with its top permanently
    -- off-screen and no drag direction that could bring it back.
    --
    -- Symmetric on all four edges, not pinning top/right on-screen. Pinning them was
    -- tried and reverted: if the panel's height alone exceeds the screen (the actual
    -- reported case -- 1099x820 needed, 1307x679 available, width was never the
    -- problem), a pinned top makes the cut-off bottom *permanently* unreachable by any
    -- drag, since the top can't move and the height doesn't change. Letting every edge
    -- move means the player can trade which part is visible by dragging -- not see the
    -- whole thing at once, but reach every part of it. Dragging works from anywhere on
    -- the panel's blank area, not just the title bar -- Widgets.MovableFrame enables
    -- mouse and registers drag on the whole frame, and the border/background child
    -- doesn't claim its own mouse, so it doesn't block that.
    panel:SetClampRectInsets(400, -400, -400, 400)

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

    -- Title. Always at Theme.CHROME.TITLE_Y -- no per-panel override. This used to
    -- read `config.title == "Pet Model Browser" and -20 or -35`, then later a
    -- `config.titleOffset` escape hatch (Models Browser's only user, at -20), which
    -- silently moved everything anchored off the title (CreateSearchBox always
    -- anchors to panel.title). A13 removed the escape hatch: a panel that needs more
    -- room below the toolbar moves *its own* chrome, not the title every panel shares.
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
    -- **A programmatic clear still notifies, and that is the whole point of NotifyNow.**
    -- `ShowPlaceholder` goes through SetText, which fires OnTextChanged with
    -- `userInput = false` -- correctly ignored by the handler above, since that is how the
    -- placeholder used to erase itself. The consequence was that clearing the box changed
    -- what the user sees and told nobody. Every caller papered over it by following
    -- ClearSearch with an explicit reload, so it never showed; the moment a *store* reads
    -- the box, an unannounced clear becomes silent staleness on Reset All Filters.
    --
    -- Guarded on an actual change, so clearing an already-empty box stays quiet.
    function searchBox:ClearSearch()
        local hadText = self:GetSearchText() ~= ""
        self:ClearFocus()
        ShowPlaceholder(self)
        if hadText then NotifyNow("") end
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

        -- The browser's own caches, released by the browser. This used to be four
        -- assignments into another addon's internals -- which put four names on the
        -- cross-addon surface, and dropped two live C_Timer handles without cancelling
        -- them, so a pending render could fire straight afterwards and refill what had
        -- just been cleared.
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

function ns.PanelManager:TogglePanel(panelName, createFunc)
    if not ns.state[panelName] then createFunc() end
    local p = ns.state[panelName]
    if p:IsVisible() then p:Hide() else p:Show(); p:Raise() end
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
    if ef and ef.SetBackdropColor then ef:SetBackdropColor(0, 0, 0, alpha) end
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

-- **No cache invalidation here any more, and no parameter for one.** It used to end with
-- `if invalidateCacheCallback then ... else ns._renderCache = nil end` -- but neither of the
-- two callers ever passed the callback, so the fallback always ran, and for the Teams panel
-- that meant clearing the *Owned Pets* render cache, which is not its cache.
--
-- Unnecessary now regardless: the width this handler changes is `panelWidth`, a store slice,
-- so the render selector sees the resize on its own. The `renderCallback` below is what
-- makes that happen.
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