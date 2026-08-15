-- Shared/Menu.lua
-- Floating menu window for PetStableManagement

local _, ns = ...

ns.Menu = ns.Menu or {}
local menu = ns.Menu

--------------------------------------------------------------------------------
-- WINDOW CREATION
--------------------------------------------------------------------------------

function menu:Create()
    if ns.state.menu then return ns.state.menu end

    local Widgets = ns.Widgets
    local pos     = PetStableManagementDB.settings.menuPosition

    local window = Widgets.MovableFrame(UIParent, {
        name   = "PSMMenu",
        size   = { 200, 300 },
        strata = "HIGH",
        level  = 100,
        skin   = "frame",
        point  = { "CENTER", UIParent, "CENTER", pos and pos.x or 0, pos and pos.y or 0 },
    })
    window:SetToplevel(true)
    window:SetClampedToScreen(true)

    -- MovableFrame's own OnDragStop only stops the drag; this one also persists where
    -- the user left it.
    window:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local _, _, _, x, y = self:GetPoint()
        PetStableManagementDB.settings.menuPosition = { x = x, y = y }
    end)

    -- Background and border. Same shape as PanelManager's panel.border: the hairline
    -- preset, the shared background colour, one level below its owner.
    window.border = Widgets.Frame(window, {
        allPoints = true,
        backdrop  = "TOOLTIP_HAIRLINE",
        color     = ns.Config.COLORS.BACKGROUND,
        level     = window:GetFrameLevel() - 1,
    })

    window.title = Widgets.Label(window.border, {
        fontSize = ns.Theme.SIZE.HEADING,
        outline  = true,
        color    = ns.Theme.COLOR.GOLD,
        text     = "PSM Menu",
        point    = { "TOP", 0, -10 },
    })

    window.closeButton = Widgets.CloseButton(window, {
        size    = { 20, 20 },
        onClick = function()
            window:Hide()
            PetStableManagementDB.settings.showFloatingMenu = false
        end,
    })

    -- Buttons. XL because the longest label is "Toggle Models Browser"; the menu window
    -- is 200 wide, so 180 still leaves a margin either side.
    local buttonWidth, buttonSpacing = ns.Theme.CONTROL.BUTTON_W.XL, 10

    -- Browser-dependent buttons are never disabled, and that is deliberate.
    --
    -- A disabled Blizzard button does not fire OnEnter, so it cannot carry a tooltip --
    -- which is the whole reason a transparent mouse-catching overlay used to be pinned
    -- over these two. That overlay then had to be shown and hidden in step with a state
    -- nothing reliably re-evaluated, and when it fell out of step it silently ate the
    -- click on a button that had become perfectly usable.
    --
    -- Leaving the button enabled removes the entire problem: OnEnter fires, so the
    -- tooltip re-reads availability on every hover, exactly as the minimap does. Nothing
    -- persistent has to be kept in sync, because nothing persistent encodes the state.
    -- Clicking while unavailable is already handled -- Broker routes through
    -- Loader:EnsureBrowser, which prints the same explanation to chat.
    local gatedButtons = {}

    -- Evaluated per hover. Returning nil suppresses the tooltip entirely, so a working
    -- button says nothing, and the dimming is corrected on the way past.
    local function BrowserGateTooltip(self)
        local why = ns.Loader:UnavailableReason()
        self:SetAlpha(why and 0.5 or 1)
        if not why then return nil end
        return {
            anchor = "ANCHOR_BOTTOM",
            title  = "Models Browser not available",
            lines  = {{ text = why, color = ns.Theme.COLOR.WHITE, wrap = true }},
        }
    end

    local function AddButton(anchorTo, label, onClick, requiresBrowser, tooltip)
        local btn = Widgets.Button(window, {
            width   = buttonWidth,
            text    = label,
            onClick = onClick,
            tooltip = tooltip or (requiresBrowser and BrowserGateTooltip) or nil,
            point   = anchorTo
                and { "TOP", anchorTo,     "BOTTOM", 0, -buttonSpacing }
                 or { "TOP", window.title, "BOTTOM", 0, -20 },
        })
        if requiresBrowser then table.insert(gatedButtons, btn) end
        return btn
    end

    window.ownedButton    = AddButton(nil,                   "Toggle Owned Pets",     function() ns.Broker:ToggleOwnedPetsPanel() end)
    window.modelsButton   = AddButton(window.ownedButton,    "Toggle Models Browser", function() ns.Broker:ToggleModelsBrowserPanel() end, true)
    window.rouletteButton = AddButton(window.modelsButton,   "Toggle Pet Roulette",   function() ns.Broker:TogglePetRoulette() end,        true)
    window.teamsButton    = AddButton(window.rouletteButton, "Toggle Pet Teams",      function() ns.Broker:TogglePetTeamsPanel() end, false, ns.Teams:ButtonTooltipSpec())
    window.optionsButton  = AddButton(window.teamsButton,    "Toggle Options",        function() ns.Broker:ToggleOptionsPanel() end)
    window.closeAllButton = AddButton(window.optionsButton,  "Close All Panels",      function() ns.Broker:CloseAllPanels() end)

    -- The dimming is only a hint, and the tooltip corrects it on hover — but reopening
    -- the menu is the other moment the answer can have changed, so refresh it there too.
    -- Availability changes without a reload: ticking the module in the AddOns list takes
    -- effect immediately.
    local function RefreshDimming()
        local available = ns.Loader:IsBrowserAvailable()
        for _, btn in ipairs(gatedButtons) do
            btn:SetAlpha(available and 1 or 0.5)
        end
    end

    window:SetScript("OnShow", RefreshDimming)
    RefreshDimming()

    ns.state.menu = window
    window:Hide()
    return window
end

--------------------------------------------------------------------------------
-- TOGGLE
--------------------------------------------------------------------------------

function menu:Toggle()
    if not ns.state.menu then menu:Create() end

    if ns.state.menu:IsVisible() then
        ns.state.menu:Hide()
        PetStableManagementDB.settings.showFloatingMenu = false
    else
        ns.state.menu:Show()
        ns.state.menu:Raise()
        PetStableManagementDB.settings.showFloatingMenu = true
    end
end

-- `menu:Initialize()` used to live here, building a full-screen click catcher that
-- dismissed "any open context menus on outside click". It never ran: the frame was
-- created hidden and nothing anywhere showed it, `PSM.state.menuClickCatcher` was
-- written and never read, and the `PSM.state.contextMenus` list its handler iterated is
-- never populated in either addon — so even if shown it would have closed nothing.
--
-- Context menus are dismissed by `CloseDropDownMenus()` in PanelManager's OnHide, and
-- they are built by the single `PSM.Utils:ShowContextMenu`. This was a second,
-- vestigial mechanism for a job already owned elsewhere. Removed.