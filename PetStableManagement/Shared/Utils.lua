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

-- Channels round to the nearest byte (+0.5 before the implicit truncation
-- string.format("%x", ...) does on a float -- Lua 5.1: a C-style (int) cast, not a
-- rounding one). Without it, a channel like Theme.COLOR.GREY's 0.6 (not exactly
-- representable in binary float) can land a shade off.
function ns.Utils:FormatColorText(text, color)
    if not text or not color then return text or "" end
    return string.format("|cff%02x%02x%02x%s|r",
        math.floor((color[1] or 1) * 255 + 0.5),
        math.floor((color[2] or 1) * 255 + 0.5),
        math.floor((color[3] or 1) * 255 + 0.5),
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

-- The icon texture (a numeric fileID) for a spell ID. Prefers C_Spell.GetSpellTexture,
-- the retail API; falls back to the legacy GetSpellTexture global, which -- like
-- GetSpellInfo in GetSpellNameCompat -- is expected to be nil on modern clients.
-- Returns nil for a non-number or an unresolvable spell ID. This replaces the icon
-- name once stored per ability in Data/AbilitiesData.lua: the spell ID is the single
-- source of truth now, so a mis-scraped icon name can no longer drift from it.
function ns.Utils:GetSpellTextureCompat(spellID)
    if type(spellID) ~= "number" then return nil end
    if ns.C_Spell and ns.C_Spell.GetSpellTexture then
        local tex = ns.Utils.SafeCall(ns.C_Spell.GetSpellTexture, spellID)
        if tex then return tex end
    end
    if ns.GetSpellTexture then
        return ns.Utils.SafeCall(ns.GetSpellTexture, spellID)
    end
end

function ns.Utils:HasAnimalCompanionTalent()
    -- Animal Companion (spell 267116) is a passive talent flagged "Not In
    -- Spellbook", so IsPlayerSpell alone can report false while the talent is
    -- taken. The authoritative check is C_SpellBook.IsSpellKnown, which the wiki
    -- documents as also returning true for spells outside the spellbook (and
    -- which IsPlayerSpell itself migrated into); the remaining namespace lookup
    -- is kept as a client-difference fallback. Everything is guarded because
    -- namespaces vary between client generations.
    if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(267116) == true then return true end
    if C_Spell and C_Spell.IsSpellKnown and C_Spell.IsSpellKnown(267116) == true then return true end
    return false
end

-- Whether this hunter's current specialization is Beast Mastery (spec ID 253).
-- Unlike a talent/spell check this follows live spec switches, and it is what the
-- Team Roulette fill order (active slots 1 and 6 first) keys off.
function ns.Utils:IsBeastMastery()
    local BM_SPEC_ID = 253
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
        local index = C_SpecializationInfo.GetSpecialization()
        if index and C_SpecializationInfo.GetSpecializationInfo then
            return C_SpecializationInfo.GetSpecializationInfo(index) == BM_SPEC_ID
        end
    end
    if GetSpecialization and GetSpecializationInfo then
        local index = GetSpecialization()
        if index then
            return (select(1, GetSpecializationInfo(index))) == BM_SPEC_ID
        end
    end
    return false
end

-- Whether this hunter may summon/tame exotic pet families. Exotic Beasts
-- (spell 53270) is the Beast Mastery passive granted at level 10 and removed on
-- any other spec; knowing it is the same live check the Models Browser's Special
-- Tames "Exotic" rule evaluates (TamingChecker.lua's TamingRules table). The spec
-- identity itself is the fallback, so a client that fails to expose the passive
-- (a level < 10 hunter cannot have a spec yet, so the fallback stays level-safe).
function ns.Utils:CanTameExotic()
    if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(53270) == true then return true end
    if C_Spell and C_Spell.IsSpellKnown and C_Spell.IsSpellKnown(53270) == true then return true end
    return self:IsBeastMastery()
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