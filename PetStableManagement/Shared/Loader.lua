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
local IsAddOnLoadedFn = C_AddOns.IsAddOnLoaded
local LoadAddOnFn     = C_AddOns.LoadAddOn
local GetAddOnInfoFn  = C_AddOns.GetAddOnInfo

-- Memoised: passive callers hit this on every popup open, and once the addon is up
-- the answer can never change back within a session.
local loaded = false

local FAILURE_HINT = {
    DISABLED     = "It is disabled in the AddOns list (Esc \226\134\146 AddOns).",
    DEP_DISABLED = "A module it needs is disabled in the AddOns list (Esc \226\134\146 AddOns).",
    MISSING      = "Its folder is missing from Interface/AddOns.",
    DEP_MISSING  = "A module it needs is missing from Interface/AddOns.",
}

-- Reported once per session: a failed load is a persistent condition (disabled,
-- missing), so repeating it on every subsequent click is pure spam.
local announced = false

local function Announce(reason)
    if announced then return end
    announced = true
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
-- GetAddOnInfo's `loadable` reports false for an already-loaded addon, hence the or.
function PSM.Loader:IsBrowserAvailable()
    if self:IsBrowserLoaded() then return true end
    local _, _, _, loadable = GetAddOnInfoFn(BROWSER_ADDON)
    return loadable and true or false
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
