-- Shared/Menu.lua
-- Floating menu window for PetStableManagement

local addonName = "PetStableManagement"

_G.PSM = _G.PSM or {}
local PSM = _G.PSM

PSM.Menu = PSM.Menu or {}
local menu = PSM.Menu

--------------------------------------------------------------------------------
-- WINDOW CREATION
--------------------------------------------------------------------------------

function menu:Create()
    if PSM.state.menu then return PSM.state.menu end

    local window = CreateFrame("Frame", "PSMMenu", UIParent)
    window:SetSize(200, 300)

    local xOffset = PetStableManagementDB.settings.menuPosition and PetStableManagementDB.settings.menuPosition.x or 0
    local yOffset = PetStableManagementDB.settings.menuPosition and PetStableManagementDB.settings.menuPosition.y or 0
    window:SetPoint("CENTER", UIParent, "CENTER", xOffset, yOffset)

    window:SetFrameStrata("HIGH")
    window:SetFrameLevel(100)
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function(self) self:StartMoving() end)
    window:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local _, _, _, x, y = self:GetPoint()
        PetStableManagementDB.settings.menuPosition = { x = x, y = y }
    end)

    -- Background and border
    window.border = CreateFrame("Frame", nil, window, "BackdropTemplate")
    window.border:SetAllPoints()
    window.border:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 30, edgeSize = 5,
        insets = { left=4, right=4, top=4, bottom=4 }
    })
    window.border:SetBackdropColor(unpack(PSM.Config.COLORS.BACKGROUND))
    window.border:SetFrameLevel(window:GetFrameLevel() - 1)

    -- Title
    window.title = window.border:CreateFontString(nil, "OVERLAY")
    window.title:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    window.title:SetPoint("TOP", 0, -10)
    window.title:SetText("PSM Menu")
    window.title:SetTextColor(1, 0.82, 0)

    -- Close button
    window.closeButton = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    window.closeButton:SetPoint("TOPRIGHT", -5, -5)
    window.closeButton:SetSize(20, 20)
    window.closeButton:SetScript("OnClick", function()
        window:Hide()
        PetStableManagementDB.settings.showFloatingMenu = false
    end)

    -- Buttons
    local buttonWidth, buttonHeight, buttonSpacing = 160, 30, 10

    local function AddButton(name, parent, anchorTo, label, onClick, disabledModule, disabledHint)
        local btn = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
        btn:SetSize(buttonWidth, buttonHeight)
        if anchorTo then
            btn:SetPoint("TOP", anchorTo, "BOTTOM", 0, -buttonSpacing)
        else
            btn:SetPoint("TOP", parent.title, "BOTTOM", 0, -20)
        end
        btn:SetText(label)
        btn:SetScript("OnClick", onClick)
        if disabledModule and not _G.PSM[disabledModule] then
            btn:Disable()
            btn:SetAlpha(0.5)
            PSM.Utils:CreateButtonTooltipOverlay(btn, disabledModule, disabledHint)
        end
        PSM.UI:ApplyElvUISkin(btn, "button")
        return btn
    end

    window.ownedButton   = AddButton("owned",    window, nil,                   "Toggle Owned Pets",     function() PSM.Broker:ToggleOwnedPetsPanel() end)
    window.modelsButton  = AddButton("models",   window, window.ownedButton,    "Toggle Models Browser", function() PSM.Broker:ToggleModelsBrowserPanel() end,  "ModelsPanel",  "Enable 'Pet Stable Management: Models Browser' in your addon list")
    window.rouletteButton= AddButton("roulette", window, window.modelsButton,   "Toggle Pet Roulette",   function() PSM.Broker:TogglePetRoulette() end,          "PetRoulette",  "Enable 'Pet Stable Management: Models Browser' in your addon list")
    window.teamsButton   = AddButton("teams",    window, window.rouletteButton, "Toggle Pet Teams",      function() PSM.Broker:TogglePetTeamsPanel() end)
    window.optionsButton = AddButton("options",  window, window.teamsButton,    "Toggle Options",        function() PSM.Broker:ToggleOptionsPanel() end)
    window.closeAllButton= AddButton("closeAll", window, window.optionsButton,  "Close All Panels",      function() PSM.Broker:CloseAllPanels() end)

    PSM.UI:ApplyElvUISkin(window, "frame")
    PSM.UI:ApplyElvUISkin(window.closeButton, "closebutton")

    PSM.state.menu = window
    window:Hide()
    return window
end

--------------------------------------------------------------------------------
-- TOGGLE
--------------------------------------------------------------------------------

function menu:Toggle()
    if not PSM.state.menu then menu:Create() end

    if PSM.state.menu:IsVisible() then
        PSM.state.menu:Hide()
        PetStableManagementDB.settings.showFloatingMenu = false
    else
        PSM.state.menu:Show()
        PSM.state.menu:Raise()
        PetStableManagementDB.settings.showFloatingMenu = true
    end
end

--------------------------------------------------------------------------------
-- INIT
--------------------------------------------------------------------------------

function menu:Initialize()
    PSM.state = PSM.state or {}

    -- Click catcher to dismiss any open context menus on outside click
    local clickCatcher = CreateFrame("Frame")
    clickCatcher:SetFrameStrata("FULLSCREEN")
    clickCatcher:SetFrameLevel(199)
    clickCatcher:SetAllPoints(UIParent)
    clickCatcher:EnableMouse(true)
    clickCatcher:Hide()
    clickCatcher:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" or button == "RightButton" then
            for _, ctxMenu in ipairs(PSM.state.contextMenus or {}) do
                if ctxMenu and ctxMenu.Hide then ctxMenu:Hide() end
            end
            PSM.state.contextMenus = {}
            self:Hide()
        end
    end)
    PSM.state.menuClickCatcher = clickCatcher
end

menu:Initialize()