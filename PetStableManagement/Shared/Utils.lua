-- Utils.lua
-- Utility functions for PetStableManagement

local _, ns = ...

ns.Utils = {}

--------------------------------------------------------------------------------
-- SAFE CALL / ERROR HANDLING
--------------------------------------------------------------------------------

-- The addon's one error boundary. `xpcall`'s message handler runs while the stack is
-- still live, which `pcall` cannot give us -- that's the only reason this isn't just
-- pcall with a log call bolted on. Lua 5.1's xpcall takes no arguments beyond the
-- handler, so `func`'s own varargs are captured and applied inside the protected
-- closure instead.
function ns.Utils.SafeCall(func, ...)
    if type(func) ~= "function" then return nil end
    local n, args = select("#", ...), { ... }
    local result
    local ok, err = xpcall(function()
        result = func(unpack(args, 1, n))
    end, function(e)
        ns.Log:Record(e, debug.traceback("", 2))
        return e
    end)
    if ok then return result end
    ns.Utils:Msg("ERROR", ns.L("Error: %s Type /psm debug for details.", tostring(err)))
end

--------------------------------------------------------------------------------
-- CHAT MESSAGES
--------------------------------------------------------------------------------

-- The one place a confirmation, warning, or failure reaches the chat frame -- never
-- print() directly. `kind` is one of Config.COLORS' ERROR / WARNING / SUCCESS keys, so
-- the message colours and every other semantic use of them share one definition.
local MSG_PREFIX = "Pet Stable Management: "

function ns.Utils:Msg(kind, text)
    local color = ns.Config.COLORS[kind]
    if not color then
        error(("ns.Utils:Msg: unknown kind %q"):format(tostring(kind)), 2)
    end
    print(ns.Utils:FormatColorText(MSG_PREFIX .. text, color))
end

--------------------------------------------------------------------------------
-- STRING UTILITIES
--------------------------------------------------------------------------------

function ns.Utils:NormalizeSearchText(text)
    if type(text) ~= "string" then return "" end
    return strtrim(text):lower()
end

function ns.Utils:FormatColorText(text, color)
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

function ns.Utils.DeepCopy(original)
    if type(original) ~= "table" then return original end
    local copy = {}
    for k, v in pairs(original) do
        copy[k] = type(v) == "table" and ns.Utils.DeepCopy(v) or v
    end
    return copy
end

function ns.Utils:ClearTable(tbl)
    if type(tbl) == "table" then
        for k in pairs(tbl) do tbl[k] = nil end
    end
end

-- Note: iteration order in Lua is not guaranteed, so this hash is only reliable
-- for same-session comparisons (e.g. render cache keys), not persistent storage.
function ns.Utils:GetTableHash(tbl)
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
function ns.Utils:GetPetDuplicateKey(pet)
    if pet.displayID and pet.displayID > 0 then
        return "d:" .. tostring(pet.displayID)
    end
    return "i:" .. tostring(pet.icon or 0)
end

--------------------------------------------------------------------------------
-- DEBOUNCE
--------------------------------------------------------------------------------

function ns.Utils:Debounce(func, delay)
    if type(func) ~= "function" then return function() end end
    local timer
    delay = delay or ns.Config.UPDATE_DELAY
    return function(...)
        local args = {...}
        if timer then timer:Cancel() end
        timer = ns.C_Timer.NewTimer(delay, function()
            ns.Utils.SafeCall(func, unpack(args))
        end)
    end
end

--------------------------------------------------------------------------------
-- SPELL / TALENT HELPERS
--------------------------------------------------------------------------------

function ns.Utils:GetSpellNameCompat(spellID)
    if type(spellID) ~= "number" then return nil end
    if ns.C_Spell and ns.C_Spell.GetSpellName then
        local name = ns.Utils.SafeCall(ns.C_Spell.GetSpellName, spellID)
        if name then return name end
    end
    if ns.GetSpellInfo then
        return ns.Utils.SafeCall(ns.GetSpellInfo, spellID)
    end
end

function ns.Utils:HasAnimalCompanionTalent()
    return IsPlayerSpell(267116) == true
end

--------------------------------------------------------------------------------
-- UI HELPERS
--------------------------------------------------------------------------------

-- No tooltip overlay for disabled buttons: leave the button *enabled* and give it an
-- ordinary live tooltip instead. See Menu.lua's gated buttons.

-- Shows a context menu at the cursor using WoW's UIDropDownMenu system.
-- menuList: array of { text, func, notCheckable, isTitle }
function ns.Utils:ShowContextMenu(menuList)
    ns.state = ns.state or {}

    if not ns.state.contextDropDown then
        -- Deliberately unskinned, unlike every other UIDropDownMenuTemplate frame in the
        -- addon. This one is never displayed: it is the host ToggleDropDownMenu anchors
        -- the popup to, and it stays hidden for its whole life. Skinning it would restyle
        -- nothing, so `skin = "dropdown"` here would read as working and do nothing.
        ns.state.contextDropDown = ns.Widgets.Frame(UIParent, {
            name     = "PSMContextMenuDropDown",
            template = "UIDropDownMenuTemplate",
            hidden   = true,
        })
    end

    UIDropDownMenu_Initialize(ns.state.contextDropDown, function(self, level)
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

    ToggleDropDownMenu(1, nil, ns.state.contextDropDown, "cursor", 0, 0)
end