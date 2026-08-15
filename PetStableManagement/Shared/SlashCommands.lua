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

-- Models Browser and its data are LoadOnDemand; PSM.Loader pulls them in on first
-- use and reports a precise reason (disabled / missing / in combat) if it can't,
-- so callers below don't print a "module not loaded" message of their own.

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
        if PSM.Loader:EnsureBrowser() and PSM.ModelsPanel then
            PSM.ModelsPanel:Toggle()
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
        if PSM.Loader:EnsureBrowser() and PSM.PetRoulette then
            PSM.PetRoulette:SelectPetRouletteFromCommand()
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

-- Read at call time, not captured at file scope.
--
-- This was `local PETSWAP_MAX_SLOT = PSM.Config and PSM.Config.MAX_STABLE_SLOTS or 205`,
-- which works today only because Config is TOC line 18 and this file is 33. It is the
-- same snapshot-not-reference pattern that `ModelRow.lua` was fixed for, with one extra
-- hazard: the `and`/`or` guard means a load-order change would not error, it would
-- silently freeze the limit at 205 and reject valid slots with a confident message
-- quoting the wrong number. **A guarded capture fails more quietly than an unguarded
-- one, which makes it worse, not safer.**
local function MaxStableSlot()
    return (PSM.Config and PSM.Config.MAX_STABLE_SLOTS) or 205
end

SlashCmdList["PETSWAP"] = function(msg)
    local a, b = msg:match("^(%S+)%s+(%S+)$")
    local startSlot, destSlot = tonumber(a), tonumber(b)

    if not startSlot or not destSlot then
        print("|cFFFF0000Usage: /petswap [starting slot] [destination slot]|r")
        print("|cFFFFAA00Example: /petswap 5 10|r")
        return
    end

    local maxSlot = MaxStableSlot()
    local function validSlot(n)
        return n >= 1 and n <= maxSlot
    end

    if not validSlot(startSlot) or not validSlot(destSlot) then
        print(string.format("|cFFFF0000Slot numbers must be between 1 and %d.|r", maxSlot))
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