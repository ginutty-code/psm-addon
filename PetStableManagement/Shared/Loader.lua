-- Loader.lua
-- On-demand loading of the optional Models Browser and its generated data tables.
--
-- Both optional addons are ## LoadOnDemand: 1, so neither is parsed at login. That
-- keeps the always-paid memory floor to this core addon alone. They are pulled in
-- lazily at two different granularities:
--
--   EnsureData()    -- just the generated tables (PetStableManagement_Data).
--                      Needed by core's own popups: the Owned Pets magnifier shows
--                      taming rules, Petopia notes, conditions and coordinates, none
--                      of which require any Models Browser UI.
--   EnsureBrowser() -- the browser UI/logic. Declares the data addon as a RequiredDep,
--                      so loading it loads the tables first, automatically.

_G.PSM = _G.PSM or {}
local PSM = _G.PSM

PSM.Loader = {}

local DATA_ADDON    = "PetStableManagement_Data"
local BROWSER_ADDON = "PetStableManagement_ModelsBrowser"

-- C_AddOns only: the bare IsAddOnLoaded/LoadAddOn/GetAddOnInfo globals were removed
-- in 11.0, well below this addon's ## Interface floor, so a fallback to them would
-- be dead code pointing at names that no longer exist.
local IsAddOnLoadedFn = C_AddOns.IsAddOnLoaded
local LoadAddOnFn     = C_AddOns.LoadAddOn
local GetAddOnInfoFn  = C_AddOns.GetAddOnInfo

-- Memoised: the magnifier and tooltip paths call Ensure* on every open, and once an
-- addon is up the answer can never change back within a session.
local isLoaded = {}

local FAILURE_HINT = {
    DISABLED     = "It is disabled in the AddOns list (Esc \226\134\146 AddOns).",
    DEP_DISABLED = "A module it needs is disabled in the AddOns list (Esc \226\134\146 AddOns).",
    MISSING      = "Its folder is missing from Interface/AddOns.",
    DEP_MISSING  = "A module it needs is missing from Interface/AddOns.",
}

-- Reported once per addon per session -- a failed load is a persistent condition
-- (disabled, missing), so repeating it on every subsequent click is pure spam.
local announced = {}

local function Announce(name, reason)
    if announced[name] then return end
    announced[name] = true
    local hint = FAILURE_HINT[reason] or ("Reason: " .. tostring(reason) .. ".")
    print(string.format("|cFFFF8800Pet Stable Management: could not load %s. %s|r", name, hint))
end

-- Loads an addon once. `silent` suppresses the failure message for passive callers
-- (tooltips, row rendering) that fire constantly and must not spam chat.
local function Ensure(name, silent)
    if isLoaded[name] then return true end

    if IsAddOnLoadedFn and IsAddOnLoadedFn(name) then
        isLoaded[name] = true
        return true
    end

    -- Parsing several MB of Lua mid-fight is a visible frame hitch, and the browser
    -- additionally builds frames. Panels are already combat-blocked, so the only
    -- callers that realistically land here in combat are passive ones, which degrade
    -- quietly rather than stutter.
    if InCombatLockdown and InCombatLockdown() then
        if not silent then
            print("|cFFFF8800Pet Stable Management: can't load additional modules during combat.|r")
        end
        return false
    end

    if not LoadAddOnFn then return false end

    local ok, reason = LoadAddOnFn(name)
    if ok then
        isLoaded[name] = true
        return true
    end

    if not silent then Announce(name, reason) end
    return false
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

-- True when the generated data tables are available right now, without loading them.
-- Use this to decide whether to show already-available data; use EnsureData to
-- actually go and get it.
function PSM.Loader:IsDataLoaded()
    return isLoaded[DATA_ADDON] or (IsAddOnLoadedFn and IsAddOnLoadedFn(DATA_ADDON)) or false
end

function PSM.Loader:IsBrowserLoaded()
    return isLoaded[BROWSER_ADDON] or (IsAddOnLoadedFn and IsAddOnLoadedFn(BROWSER_ADDON)) or false
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

-- Loads the generated data tables. Passive callers (tooltips, row rendering) should
-- pass silent=true so a disabled module can't spam chat on every mouseover.
function PSM.Loader:EnsureData(silent)
    return Ensure(DATA_ADDON, silent)
end

-- Loads the Models Browser. Always user-initiated, so failures are reported.
--
-- The data addon is loaded explicitly first rather than leaning on RequiredDeps to
-- resolve a LoadOnDemand dependency. The .toc declaration stays as the source of
-- truth; this just makes the order deterministic instead of dependent on client
-- behaviour, and means a data-side failure reports itself as one.
function PSM.Loader:EnsureBrowser()
    if not Ensure(DATA_ADDON, false) then return false end
    return Ensure(BROWSER_ADDON, false)
end
