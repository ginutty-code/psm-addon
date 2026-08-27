-- Shared/Broker.lua
-- Broker integration and panel toggle API for PetStableManagement

local _, ns = ...

ns.Broker = ns.Broker or {}
local broker = ns.Broker

--------------------------------------------------------------------------------
-- PANEL TOGGLE API
-- Called by Menu, slash commands, and the LDB launcher below.
--------------------------------------------------------------------------------

function broker:ToggleOwnedPetsPanel()
    if ns.state and ns.state.panel then
        if ns.state.panel:IsVisible() then
            ns.state.panel:Hide()
            return
        end
    end
    if ns.UI and ns.UI.UpdatePanel then
        ns.UI:UpdatePanel(true)
    end
end

-- PSM.Loader pulls the LoadOnDemand browser in on first use and reports a precise
-- reason if it can't, so these no longer print a "module not loaded" message.
function broker:ToggleModelsBrowserPanel()
    if ns.Loader:EnsureBrowser() and ns.Browser.ModelsPanel then
        ns.Browser.ModelsPanel:Toggle()
    end
end

function broker:TogglePetRoulette()
    -- Hiding an open popup must not force a load, so check that before ensuring.
    local popup = ns.state and ns.state.petRoulettePopup
    if popup and popup:IsVisible() then
        popup:Hide()
        return
    end
    if ns.Loader:EnsureBrowser() and ns.Browser.PetRoulette then
        ns.Browser.PetRoulette:SelectPetRouletteFromCommand()
    end
end

function broker:TogglePetTeamsPanel()
    ns.TeamsPanel:Toggle()
end

function broker:ToggleOptionsPanel()
    if not (ns.state and ns.state.optionsPanel) then return end

    -- Close if already open (check both legacy and modern UI)
    if InterfaceOptionsFrame and InterfaceOptionsFrame:IsVisible() then
        HideUIPanel(InterfaceOptionsFrame)
        return
    end
    if SettingsPanel and SettingsPanel:IsVisible() then
        HideUIPanel(SettingsPanel)
        return
    end

    -- Open
    if ns.PanelManager:CombatBlocked(ns.L("Options")) then return end
    if InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(ns.state.optionsPanel)
        InterfaceOptionsFrame_OpenToCategory(ns.state.optionsPanel)  -- called twice intentionally (Blizzard bug workaround)
    elseif ns.state.optionsCategoryId then
        Settings.OpenToCategory(ns.state.optionsCategoryId)
    end
end

function broker:CloseAllPanels()
    local function safeHide(obj) if obj then obj:Hide() end end

    safeHide(ns.state.panel)
    safeHide(ns.state.modelsPanel)
    safeHide(ns.state.abilityBrowser)
    safeHide(ns.state.specialTames)
    safeHide(ns.state.petRoulettePopup)
    safeHide(ns.state.teamsPanel)
    safeHide(ns.state.modelMagnificationPopup)
    safeHide(ns.state.exportFrame)

    -- The settings window counts as one of our panels: our options live inside it as a
    -- category, so "Close All Panels" leaving it open reads as the button not working.
    --
    -- It must be closed through HideUIPanel, never a raw :Hide(). SettingsPanel is
    -- registered with Blizzard's UIPanel system, which tracks which of its slots are
    -- occupied; hiding the frame behind the system's back leaves a slot marked in use
    -- forever, which breaks ESC and NPC gossip until a /reload.
    if InterfaceOptionsFrame and InterfaceOptionsFrame:IsVisible() then
        HideUIPanel(InterfaceOptionsFrame)
    end
    if SettingsPanel and SettingsPanel:IsVisible() then
        HideUIPanel(SettingsPanel)
    end
end

--------------------------------------------------------------------------------
-- LDB BROKER REGISTRATION
--------------------------------------------------------------------------------

function broker:Initialize()
    ns.state = ns.state or {}

    if not LibStub then return end
    local LDB = LibStub:GetLibrary("LibDataBroker-1.1", true)
    if not LDB then return end

    ns.Broker.dataobj = LDB:NewDataObject("PetStableManagement", {
        type = "launcher",
        text = "PSM",
        icon = "Interface\\Icons\\Ability_Mount_Raptor",

        OnClick = function(self, button)
            if IsShiftKeyDown() then
                if button == "LeftButton" then
                    ns.Menu:Toggle()
                elseif button == "RightButton" then
                    ns.Broker:ToggleOptionsPanel()
                end
            else
                if button == "LeftButton" then
                    ns.Broker:ToggleOwnedPetsPanel()
                elseif button == "RightButton" then
                    ns.Broker:ToggleModelsBrowserPanel()
                end
            end
        end,

        -- Same tooltip as the minimap icon, from one definition in Minimap.lua --
        -- LibDBIcon builds that icon from this very data object, so listing different
        -- clicks in the two would be a contradiction.
        OnEnter = function(self)
            ns.Tooltip.Show(self, ns.Minimap.TooltipSpec)
        end,

        OnLeave = function()
            ns.Tooltip.Hide()
        end,
    })
end

broker:Initialize()