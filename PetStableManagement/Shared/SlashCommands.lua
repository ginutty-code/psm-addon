-- SlashCommands.lua
-- Slash command registration for PetStableManagement

local _, ns = ...

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
        ns.Minimap:Show()
        print("|cFF00FF00Pet Stable Management: Minimap button shown.|r")
    end,

    hide = function()
        ns.Minimap:Hide()
        print("|cFFFFAA00Pet Stable Management: Minimap button hidden. Use /psm show to show it again.|r")
    end,

    menu = function()
        ns.Menu:Toggle()
    end,

    models = function()
        if InCombat() then return end
        if ns.Loader:EnsureBrowser() and ns.ModelsPanel then
            ns.ModelsPanel:Toggle()
        end
    end,

    options = function()
        if ns.state.optionsPanel and InterfaceOptionsFrame_OpenToCategory then
            InterfaceOptionsFrame_OpenToCategory(ns.state.optionsPanel)
            InterfaceOptionsFrame_OpenToCategory(ns.state.optionsPanel)  -- called twice intentionally (Blizzard quirk)
        elseif ns.state.optionsCategoryId then
            Settings.OpenToCategory(ns.state.optionsCategoryId)
        end
    end,

    roulette = function()
        if ns.Loader:EnsureBrowser() and ns.PetRoulette then
            ns.PetRoulette:SelectPetRouletteFromCommand()
        end
    end,

    teams = function()
        ns.Broker:TogglePetTeamsPanel()
    end,
}

SlashCmdList["PETSTABLE"] = function(msg)
    local cmd = msg:lower():trim()
    local handler = PETSTABLE_COMMANDS[cmd]

    if handler then
        handler()
    else
        if InCombat() then return end
        ns.Minimap:TogglePanel()
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
    return (ns.Config and ns.Config.MAX_STABLE_SLOTS) or 205
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

    if not ns.state.isStableOpen then
        print("|cFFFF0000You must be at a stable master to change pet slots.|r")
        return
    end

    if not C_StableInfo.GetStablePetInfo(startSlot) then
        print(string.format("|cFFFF0000No pet found in slot %d.|r", startSlot))
        return
    end

    if not ns.Reorder:SwapPetSlots(startSlot, destSlot) then
        print("|cFFFF0000Failed to move pet.|r")
    end
end