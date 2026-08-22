-- SlashCommands.lua
-- Slash command registration for PetStableManagement

local _, ns = ...

-- ============================================================
-- Helpers
-- ============================================================

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
        ns.Utils:Msg("SUCCESS", ns.L("Minimap button shown."))
    end,

    hide = function()
        ns.Minimap:Hide()
        ns.Utils:Msg("WARNING", ns.L("Minimap button hidden. Use /psm show to show it again."))
    end,

    menu = function()
        ns.Menu:Toggle()
    end,

    models = function()
        if ns.Loader:EnsureBrowser() and ns.Browser.ModelsPanel then
            ns.Browser.ModelsPanel:Toggle()
        end
    end,

    options = function()
        ns.Broker:ToggleOptionsPanel()
    end,

    roulette = function()
        if ns.Loader:EnsureBrowser() and ns.Browser.PetRoulette then
            ns.Browser.PetRoulette:SelectPetRouletteFromCommand()
        end
    end,

    teams = function()
        ns.Broker:TogglePetTeamsPanel()
    end,

    debug = function()
        ns.Log:Dump()
    end,

    -- Descriptions reuse the exact "Toggle X" strings the PSM Menu already shows on
    -- its own buttons for these same actions (Menu.lua), and "Show minimap button"
    -- from the Options panel checkbox -- one label per action instead of the help
    -- list inventing its own wording and drifting from the surfaces it describes.
    help = function()
        ns.Utils:Msg("SUCCESS", ns.L("Available commands:"))
        for _, line in ipairs({
            { "/psm",                 ns.L("Toggle Owned Pets") },
            { "/psm show",            ns.L("Show minimap button") },
            { "/psm hide",            ns.L("Hide minimap button") },
            { "/psm menu",            ns.L("Toggle Menu") },
            { "/psm models",          ns.L("Toggle Models Browser") },
            { "/psm options",         ns.L("Toggle Options") },
            { "/psm roulette",        ns.L("Toggle Pet Roulette") },
            { "/psm teams",           ns.L("Toggle Pet Teams") },
            { "/psm debug",           ns.L("Show recent errors") },
            { "/psm help",            ns.L("Show this list of commands") },
            { "/petswap [from] [to]", ns.L("Swap two stable pet slots") },
        }) do
            print(("|cFFFFD700%s|r - %s"):format(line[1], line[2]))
        end
    end,
}

SlashCmdList["PETSTABLE"] = function(msg)
    ns.Utils.SafeCall(function()
        local cmd = msg:lower():trim()
        local handler = PETSTABLE_COMMANDS[cmd]

        if handler then
            handler()
        else
            ns.Minimap:TogglePanel()
        end
    end)
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
    ns.Utils.SafeCall(function()
        local a, b = msg:match("^(%S+)%s+(%S+)$")
        local startSlot, destSlot = tonumber(a), tonumber(b)

        if not startSlot or not destSlot then
            ns.Utils:Msg("ERROR", ns.L("Usage: /petswap [starting slot] [destination slot]"))
            ns.Utils:Msg("WARNING", ns.L("Example: /petswap 5 10"))
            return
        end

        local maxSlot = MaxStableSlot()
        local function validSlot(n)
            return n >= 1 and n <= maxSlot
        end

        if not validSlot(startSlot) or not validSlot(destSlot) then
            ns.Utils:Msg("ERROR", ns.L("Slot numbers must be between 1 and %d.", maxSlot))
            return
        end

        if startSlot == destSlot then
            ns.Utils:Msg("WARNING", ns.L("Source and destination slots are the same."))
            return
        end

        if not ns.state.isStableOpen then
            ns.Utils:Msg("ERROR", ns.L("You must be at a stable master to change pet slots."))
            return
        end

        if not C_StableInfo.GetStablePetInfo(startSlot) then
            ns.Utils:Msg("ERROR", ns.L("No pet found in slot %d.", startSlot))
            return
        end

        if not ns.Reorder:SwapPetSlots(startSlot, destSlot) then
            ns.Utils:Msg("ERROR", ns.L("Failed to move pet."))
        end
    end)
end