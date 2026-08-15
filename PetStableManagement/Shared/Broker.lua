-- Shared/Broker.lua
-- Broker integration and panel toggle API for PetStableManagement

local addonName = "PetStableManagement"

_G.PSM = _G.PSM or {}
local PSM = _G.PSM

PSM.Broker = PSM.Broker or {}
local broker = PSM.Broker

--------------------------------------------------------------------------------
-- PANEL TOGGLE API
-- Called by Menu, slash commands, and the LDB launcher below.
--------------------------------------------------------------------------------

function broker:ToggleOwnedPetsPanel()
    if PSM.state and PSM.state.panel then
        if PSM.state.panel:IsVisible() then
            PSM.state.panel:Hide()
            return
        end
    end
    if PSM.UI and PSM.UI.UpdatePanel then
        PSM.UI:UpdatePanel(true)
    end
end

-- PSM.Loader pulls the LoadOnDemand browser in on first use and reports a precise
-- reason if it can't, so these no longer print a "module not loaded" message.
function broker:ToggleModelsBrowserPanel()
    if PSM.Loader:EnsureBrowser() and PSM.ModelsPanel then
        PSM.ModelsPanel:Toggle()
    end
end

function broker:TogglePetRoulette()
    -- Hiding an open popup must not force a load, so check that before ensuring.
    local popup = PSM.state and PSM.state.petRoulettePopup
    if popup and popup:IsVisible() then
        popup:Hide()
        return
    end
    if PSM.Loader:EnsureBrowser() and PSM.PetRoulette then
        PSM.PetRoulette:SelectPetRouletteFromCommand()
    end
end

function broker:TogglePetTeamsPanel()
    PSM.TeamsPanel:Toggle()
end

function broker:ToggleOptionsPanel()
    if not (PSM.state and PSM.state.optionsPanel) then return end

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
    if InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(PSM.state.optionsPanel)
        InterfaceOptionsFrame_OpenToCategory(PSM.state.optionsPanel)  -- called twice intentionally (Blizzard bug workaround)
    elseif PSM.state.optionsCategoryId then
        Settings.OpenToCategory(PSM.state.optionsCategoryId)
    end
end

function broker:CloseAllPanels()
    local function safeHide(obj) if obj then obj:Hide() end end

    safeHide(PSM.state.panel)
    safeHide(PSM.state.modelsPanel)
    safeHide(PSM.state.petRoulettePopup)
    safeHide(PSM.state.teamsPanel)
    safeHide(PSM.state.modelMagnificationPopup)
    safeHide(PSM.state.exportFrame)

    -- The settings window counts as one of our panels: our options live inside it as a
    -- category, so "Close All Panels" leaving it open reads as the button not working.
    --
    -- It must be closed through HideUIPanel, never a raw :Hide(). SettingsPanel is
    -- registered with Blizzard's UIPanel system, which tracks which of its slots are
    -- occupied; hiding the frame behind the system's back leaves a slot marked in use
    -- forever, and that is what breaks ESC and NPC gossip until a /reload. The note
    -- that used to sit here recorded the breakage but blamed closing the panel at all,
    -- so this stayed open while ToggleOptionsPanel closed it anyway with the very
    -- :Hide() the note warned about -- one path forbidding what the other did.
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
    PSM.state = PSM.state or {}

    if not LibStub then return end
    local LDB = LibStub:GetLibrary("LibDataBroker-1.1", true)
    if not LDB then return end

    PSM.Broker.dataobj = LDB:NewDataObject("PetStableManagement", {
        type = "launcher",
        text = "PSM",
        icon = "Interface\\Icons\\Ability_Mount_Raptor",

        OnClick = function(self, button)
            if IsShiftKeyDown() then
                if button == "LeftButton" then
                    PSM.Menu:Toggle()
                elseif button == "RightButton" then
                    PSM.Broker:ToggleOptionsPanel()
                end
            else
                if button == "LeftButton" then
                    PSM.Broker:ToggleOwnedPetsPanel()
                elseif button == "RightButton" then
                    PSM.Broker:ToggleModelsBrowserPanel()
                end
            end
        end,

        -- Same tooltip as the minimap icon, from one definition in Minimap.lua --
        -- LibDBIcon builds that icon from this very data object, so listing different
        -- clicks in the two would be a contradiction. This copy used to advertise the
        -- Models Browser unconditionally, which the minimap side had already been fixed
        -- not to do: under LoadOnDemand a disabled or absent module must not be offered.
        OnEnter = function(self)
            PSM.Tooltip.Show(self, PSM.Minimap.TooltipSpec)
        end,

        OnLeave = function()
            PSM.Tooltip.Hide()
        end,
    })
end

broker:Initialize()