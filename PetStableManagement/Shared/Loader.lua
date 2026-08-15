-- Loader.lua
-- On-demand loading of the optional Models Browser.
--
-- The browser is ## LoadOnDemand: 1, so it is not parsed at login and the
-- always-paid memory floor is this core addon alone. It carries its generated data
-- tables in its own Data/ subfolder, so loading it brings the data with it.
--
-- (An earlier revision split the data into a third addon so core could load tables
-- without the browser UI. Every caller that wanted "data only" turned out to need
-- the browser's own resolvers -- PSM.PetModels, PSM.TamingChecker -- so the tier
-- was never exercised, and it cost users a third entry in the AddOns list. Merged
-- back. Worth re-splitting only if the UI-free resolvers are ever separated from
-- the panel code, which would make data-only loading real rather than theoretical.)

_G.PSM = _G.PSM or {}
local PSM = _G.PSM

PSM.Loader = {}

local BROWSER_ADDON = "PetStableManagement_ModelsBrowser"

-- C_AddOns only: the bare IsAddOnLoaded/LoadAddOn/GetAddOnInfo globals were removed
-- in 11.0, well below this addon's ## Interface floor, so a fallback to them would
-- be dead code pointing at names that no longer exist.
local IsAddOnLoadedFn   = C_AddOns.IsAddOnLoaded
local LoadAddOnFn       = C_AddOns.LoadAddOn
local GetAddOnInfoFn    = C_AddOns.GetAddOnInfo
local GetEnableStateFn  = C_AddOns.GetAddOnEnableState

-- Enum.AddOnEnableState: 0 none, 1 some characters, 2 all.
local ENABLE_NONE = 0

-- Memoised: passive callers hit this on every popup open, and once the addon is up
-- the answer can never change back within a session.
local loaded = false

-- Plain ASCII on purpose. This text goes to the chat frame, whose font has no glyph
-- for the U+2192 arrow that used to be here -- it rendered as an empty square, which
-- looks like a broken addon rather than an instruction.
local FAILURE_HINT = {
    DISABLED     = "It is disabled in the AddOns list (Esc > AddOns).",
    DEP_DISABLED = "A module it needs is disabled in the AddOns list (Esc > AddOns).",
    MISSING      = "Its folder is missing from Interface/AddOns.",
    DEP_MISSING  = "A module it needs is missing from Interface/AddOns.",
}

-- Announcing is controlled by the caller's `silent` flag, not by a once-per-session
-- latch. There used to be one, on the reasoning that a failed load is a persistent
-- condition so repeating it is spam -- but that conflated two kinds of caller. Passive
-- ones (row rendering) already pass silent = true, and they are the only spam risk.
-- Everything else is an explicit user action: /psm models, a menu entry, a magnifier
-- click. Swallowing the answer to a direct request makes the command look broken, and
-- the latch meant the *second* thing you tried always failed in silence.
local function Announce(reason)
    local hint = FAILURE_HINT[reason] or ("Reason: " .. tostring(reason) .. ".")
    print(string.format(
        "|cFFFF8800Pet Stable Management: could not load the Models Browser. %s|r", hint))
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function PSM.Loader:IsBrowserLoaded()
    if loaded then return true end
    if IsAddOnLoadedFn(BROWSER_ADDON) then
        loaded = true
        return true
    end
    return false
end

-- True when the browser is loaded OR could be loaded on demand (present and enabled).
-- This is the question UI affordances should ask -- "offer the user this action?" --
-- since under LoadOnDemand "not loaded yet" is the normal state, not an absence.
--
-- Two client facts make this harder than it looks, both confirmed by macro rather than
-- from memory, because guessing at them produced two wrong versions of this function:
--
--   1. `loadable` does NOT mean "can be loaded". A LoadOnDemand addon that is present
--      and enabled but not yet parsed reports loadable = false -- the dormant state,
--      which is the *normal* state at login. Reading it alone answered "unavailable"
--      for every fresh session, so affordances hid until something else loaded the
--      browser: the minimap tooltip listed three clicks instead of four, and PSM.Menu
--      hid its browser entries.
--
--   2. `reason` does not distinguish enabled from disabled. A LoadOnDemand addon
--      reports "DEMAND_LOADED" *either way* -- verified with the module unticked and
--      the UI reloaded: loaded = false, loadable = false, reason = DEMAND_LOADED,
--      identical to the enabled-and-dormant case.
--
-- So enable state is the only thing that separates "dormant" from "switched off", and
-- it lives in its own call: GetAddOnInfo lost its `enabled` field in 8.0.
function PSM.Loader:IsBrowserAvailable()
    if self:IsBrowserLoaded() then return true end

    if GetEnableStateFn then
        local ok, state = pcall(GetEnableStateFn, BROWSER_ADDON, UnitName("player"))
        if ok and state == ENABLE_NONE then return false end
    end

    local _, _, _, loadable, reason = GetAddOnInfoFn(BROWSER_ADDON)
    if loadable then return true end

    -- Enabled and demand-loaded: dormant, and offering it is correct. Any other reason
    -- (MISSING, DEP_MISSING, CORRUPT, INCOMPATIBLE) is a real absence.
    return reason == "DEMAND_LOADED"
end

-- Loads the Models Browser and its data tables. Returns true when it is available
-- for use. Pass silent=true from passive callers (row rendering, anything that can
-- fire repeatedly) so a disabled module cannot spam chat.
function PSM.Loader:EnsureBrowser(silent)
    if self:IsBrowserLoaded() then return true end

    -- Parsing several MB of Lua mid-fight is a visible frame hitch, and the browser
    -- also builds frames. Panels are already combat-blocked, so the callers that
    -- realistically land here in combat are passive ones, which degrade quietly.
    if InCombatLockdown and InCombatLockdown() then
        if not silent then
            print("|cFFFF8800Pet Stable Management: can't load additional modules during combat.|r")
        end
        return false
    end

    local ok, reason = LoadAddOnFn(BROWSER_ADDON)
    if ok then
        loaded = true
        return true
    end

    if not silent then Announce(reason) end
    return false
end
