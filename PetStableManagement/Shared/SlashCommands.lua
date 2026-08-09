-- SlashCommands.lua
-- Slash command registration for PetStableManagement

_G.PSM = _G.PSM or {}

-- ============================================================
-- Helpers
-- ============================================================

local function InCombat()
    if UnitAffectingCombat("player") then
        print("|cFFFF0000Pet Stable Management: Cannot open panel during combat.|r")
        return true
    end
end

local function ModulesMissing()
    print("|cFFFF8800PetStableManagement: Models Browser module is not loaded. Enable 'Pet Stable Management: Models Browser' in your addon list.|r")
end

-- ============================================================
-- /psm  /petstable
-- ============================================================

SLASH_PETSTABLE1 = "/psm"
SLASH_PETSTABLE2 = "/petstable"

local PETSTABLE_COMMANDS = {
    show = function()
        PSM.Minimap:Show()
        print("|cFF00FF00Pet Stable Management: Minimap button shown.|r")
    end,

    hide = function()
        PSM.Minimap:Hide()
        print("|cFFFFAA00Pet Stable Management: Minimap button hidden. Use /psm show to show it again.|r")
    end,

    menu = function()
        PSM.Menu:Toggle()
    end,

    models = function()
        if InCombat() then return end
        if PSM.ModelsPanel and PSM.ModelsPanel.Toggle then
            PSM.ModelsPanel:Toggle()
        else
            ModulesMissing()
        end
    end,

    options = function()
        if PSM.state.optionsPanel and InterfaceOptionsFrame_OpenToCategory then
            InterfaceOptionsFrame_OpenToCategory(PSM.state.optionsPanel)
            InterfaceOptionsFrame_OpenToCategory(PSM.state.optionsPanel)  -- called twice intentionally (Blizzard quirk)
        elseif PSM.state.optionsCategoryId then
            Settings.OpenToCategory(PSM.state.optionsCategoryId)
        end
    end,

    roulette = function()
        if PSM.PetRoulette and PSM.PetRoulette.SelectPetRouletteFromCommand then
            PSM.PetRoulette:SelectPetRouletteFromCommand()
        else
            ModulesMissing()
        end
    end,

    teams = function()
        PSM.Broker:TogglePetTeamsPanel()
    end,
}

SlashCmdList["PETSTABLE"] = function(msg)
    local cmd = msg:lower():trim()
    local handler = PETSTABLE_COMMANDS[cmd]

    if handler then
        handler()
    else
        if InCombat() then return end
        PSM.Minimap:TogglePanel()
    end
end

-- ============================================================
-- /petswap
-- ============================================================

SLASH_PETSWAP1 = "/petswap"

local PETSWAP_MAX_SLOT = PSM.Config and PSM.Config.MAX_STABLE_SLOTS or 205

SlashCmdList["PETSWAP"] = function(msg)
    local a, b = msg:match("^(%S+)%s+(%S+)$")
    local startSlot, destSlot = tonumber(a), tonumber(b)

    if not startSlot or not destSlot then
        print("|cFFFF0000Usage: /petswap [starting slot] [destination slot]|r")
        print("|cFFFFAA00Example: /petswap 5 10|r")
        return
    end

    local function validSlot(n)
        return n >= 1 and n <= PETSWAP_MAX_SLOT
    end

    if not validSlot(startSlot) or not validSlot(destSlot) then
        print(string.format("|cFFFF0000Slot numbers must be between 1 and %d.|r", PETSWAP_MAX_SLOT))
        return
    end

    if startSlot == destSlot then
        print("|cFFFFAA00Source and destination slots are the same.|r")
        return
    end

    if not PSM.state.isStableOpen then
        print("|cFFFF0000You must be at a stable master to change pet slots.|r")
        return
    end

    if not C_StableInfo.GetStablePetInfo(startSlot) then
        print(string.format("|cFFFF0000No pet found in slot %d.|r", startSlot))
        return
    end

    if not PSM.Reorder:SwapPetSlots(startSlot, destSlot) then
        print("|cFFFF0000Failed to move pet.|r")
    end
end