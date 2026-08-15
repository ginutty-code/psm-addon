-- Utils.lua
-- Utility functions for PetStableManagement

local addonName = "PetStableManagement"

_G.PSM = _G.PSM or {}
local PSM = _G.PSM

PSM.Utils = {}

--------------------------------------------------------------------------------
-- SAFE CALL / ERROR HANDLING
--------------------------------------------------------------------------------

function PSM.Utils.SafeCall(func, ...)
    if type(func) ~= "function" then return nil end
    local ok, result = pcall(func, ...)
    if ok then return result end
    print(string.format("|cFFFF0000Error: %s|r", tostring(result)))
end

--------------------------------------------------------------------------------
-- STRING UTILITIES
--------------------------------------------------------------------------------

function PSM.Utils:NormalizeSearchText(text)
    if type(text) ~= "string" then return "" end
    return strtrim(text):lower()
end

function PSM.Utils:FormatColorText(text, color)
    if not text or not color then return text or "" end
    return string.format("|cff%02x%02x%02x%s|r",
        math.floor((color[1] or 1) * 255),
        math.floor((color[2] or 1) * 255),
        math.floor((color[3] or 1) * 255),
        text)
end

--------------------------------------------------------------------------------
-- TABLE UTILITIES
--------------------------------------------------------------------------------

function PSM.Utils.DeepCopy(original)
    if type(original) ~= "table" then return original end
    local copy = {}
    for k, v in pairs(original) do
        copy[k] = type(v) == "table" and PSM.Utils.DeepCopy(v) or v
    end
    return copy
end

function PSM.Utils:ClearTable(tbl)
    if type(tbl) == "table" then
        for k in pairs(tbl) do tbl[k] = nil end
    end
end

-- Note: iteration order in Lua is not guaranteed, so this hash is only reliable
-- for same-session comparisons (e.g. render cache keys), not persistent storage.
function PSM.Utils:GetTableHash(tbl)
    if not tbl or not next(tbl) then return "empty" end
    local parts = {}
    for k, v in pairs(tbl) do
        table.insert(parts, tostring(k) .. ":" .. tostring(v))
    end
    table.sort(parts)  -- sort for deterministic output
    return table.concat(parts, ",")
end

-- "Duplicate" means same visual pet model, i.e. displayID. icon is not part of
-- the identity: the stabled-pet list and C_StableInfo.GetStablePetInfo (used for
-- the active-pet slots) can report slightly different icon values for the exact
-- same model, which was causing matching duplicates to silently miss each other.
-- Only fall back to icon when displayID is unavailable, to avoid grouping
-- unrelated pets together under a shared "unknown model" key.
function PSM.Utils:GetPetDuplicateKey(pet)
    if pet.displayID and pet.displayID > 0 then
        return "d:" .. tostring(pet.displayID)
    end
    return "i:" .. tostring(pet.icon or 0)
end

--------------------------------------------------------------------------------
-- DEBOUNCE
--------------------------------------------------------------------------------

function PSM.Utils:Debounce(func, delay)
    if type(func) ~= "function" then return function() end end
    local timer
    delay = delay or PSM.Config.UPDATE_DELAY
    return function(...)
        local args = {...}
        if timer then timer:Cancel() end
        timer = PSM.C_Timer.NewTimer(delay, function()
            PSM.Utils.SafeCall(func, unpack(args))
        end)
    end
end

--------------------------------------------------------------------------------
-- SPELL / TALENT HELPERS
--------------------------------------------------------------------------------

function PSM.Utils:GetSpellNameCompat(spellID)
    if type(spellID) ~= "number" then return nil end
    if PSM.C_Spell and PSM.C_Spell.GetSpellName then
        local name = PSM.Utils.SafeCall(PSM.C_Spell.GetSpellName, spellID)
        if name then return name end
    end
    if PSM.GetSpellInfo then
        return PSM.Utils.SafeCall(PSM.GetSpellInfo, spellID)
    end
end

function PSM.Utils:HasAnimalCompanionTalent()
    return IsPlayerSpell(267116) == true
end

--------------------------------------------------------------------------------
-- UI HELPERS
--------------------------------------------------------------------------------

-- `CreateButtonTooltipOverlay` used to live here: an invisible, mouse-enabled frame
-- pinned over a disabled button so it could show a tooltip explaining why. It existed
-- purely because a disabled Blizzard button never fires OnEnter.
--
-- The overlay was the wrong end of the problem. It had to be shown and hidden in step
-- with a state nothing re-evaluated, and when it fell out of step it silently ate clicks
-- on a button that had become usable -- which two other files then worked around by
-- reaching in and tearing the overlay down by hand. Leaving the button *enabled* and
-- giving it an ordinary live tooltip removes the overlay, both workarounds, and the
-- possibility of the state going stale, because no state is stored.

-- Shows a context menu at the cursor using WoW's UIDropDownMenu system.
-- menuList: array of { text, func, notCheckable, isTitle }
function PSM.Utils:ShowContextMenu(menuList)
    PSM.state = PSM.state or {}

    if not PSM.state.contextDropDown then
        PSM.state.contextDropDown = CreateFrame("Frame", "PSMContextMenuDropDown", UIParent, "UIDropDownMenuTemplate")
        PSM.state.contextDropDown:Hide()
    end

    UIDropDownMenu_Initialize(PSM.state.contextDropDown, function(self, level)
        for _, item in ipairs(menuList) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = item.text
            info.notCheckable = item.notCheckable ~= false  -- default true
            info.isTitle = item.isTitle or false
            if item.func then
                info.func = item.func
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end, "MENU")

    ToggleDropDownMenu(1, nil, PSM.state.contextDropDown, "cursor", 0, 0)
end