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
        size   = { 200, 330 },
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
        text     = ns.L("PSM Menu"),
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

    -- Browser-dependent buttons are never disabled, and that is deliberate: a disabled
    -- Blizzard button does not fire OnEnter, so it cannot carry a tooltip. Left enabled,
    -- the tooltip re-reads availability on every hover and nothing persistent has to be
    -- kept in sync. Clicking while unavailable is already handled -- Broker routes
    -- through Loader:EnsureBrowser, which explains itself in chat.
    local gatedButtons = {}

    -- Evaluated per hover. Returning nil suppresses the tooltip entirely, so a working
    -- button says nothing, and the dimming is corrected on the way past.
    local function BrowserGateTooltip(self)
        local why = ns.Loader:UnavailableReason()
        self:SetAlpha(why and 0.5 or 1)
        if not why then return nil end
        return {
            anchor = "ANCHOR_BOTTOM",
            title  = ns.L("Models Browser not available"),
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

    window.ownedButton    = AddButton(nil,                   ns.L("Toggle Owned Pets"),     function() ns.Broker:ToggleOwnedPetsPanel() end)
    window.modelsButton   = AddButton(window.ownedButton,    ns.L("Toggle Models Browser"), function() ns.Broker:ToggleModelsBrowserPanel() end, true)
    window.abilityButton  = AddButton(window.modelsButton,   ns.L("Toggle Ability Browser"),
        function()
            if ns.Loader:EnsureBrowser() and ns.Browser.AbilityBrowser then
                ns.Browser.AbilityBrowser:Toggle()
            end
        end, true)
    window.specialButton  = AddButton(window.abilityButton,  ns.L("Toggle Special Tames"),
        function()
            if ns.Loader:EnsureBrowser() and ns.Browser.SpecialTames then
                ns.Browser.SpecialTames:Toggle()
            end
        end, true)
    window.rouletteButton = AddButton(window.specialButton,  ns.L("Toggle Pet Roulette"),     function() ns.Broker:TogglePetRoulette() end,        true)
    window.teamsButton    = AddButton(window.rouletteButton, ns.L("Toggle Pet Teams"),        function() ns.Broker:TogglePetTeamsPanel() end, false, ns.Teams:ButtonTooltipSpec())
    window.optionsButton  = AddButton(window.teamsButton,    ns.L("Toggle Options"),          function() ns.Broker:ToggleOptionsPanel() end)
    window.closeAllButton = AddButton(window.optionsButton,  ns.L("Close All Panels"),        function() ns.Broker:CloseAllPanels() end)

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

-- No click catcher here: context menus are built by `PSM.Utils:ShowContextMenu` and
-- dismissed by `CloseDropDownMenus()` in PanelManager's OnHide.