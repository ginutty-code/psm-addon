-- Loader.lua
-- On-demand loading of the optional Models Browser.
--
-- The browser is ## LoadOnDemand: 1, so it is not parsed at login and the
-- always-paid memory floor is this core addon alone. It carries its generated data
-- tables in its own Data/ subfolder, so loading it brings the data with it.

local _, ns = ...

ns.Loader = {}

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
    DISABLED     = ns.L("It is disabled in the AddOns list (Esc > AddOns)."),
    DEP_DISABLED = ns.L("A module it needs is disabled in the AddOns list (Esc > AddOns)."),
    MISSING      = ns.L("Its folder is missing from Interface/AddOns."),
    DEP_MISSING  = ns.L("A module it needs is missing from Interface/AddOns."),
}

-- Announcing is controlled by the caller's `silent` flag, not by a once-per-session
-- latch. Passive callers (row rendering) already pass silent = true and are the only
-- spam risk; everything else is an explicit user action, where swallowing the answer
-- makes the command look broken.
local function Announce(reason)
    local hint = FAILURE_HINT[reason] or ns.L("Reason: %s.", tostring(reason))
    ns.Utils:Msg("WARNING", ns.L("Could not load the Models Browser. %s", hint))
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function ns.Loader:IsBrowserLoaded()
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
-- Two client facts, verified by macro, that make this harder than it looks:
--
--   1. `loadable` does NOT mean "can be loaded". A LoadOnDemand addon that is present
--      and enabled but not yet parsed reports loadable = false -- the dormant state,
--      which is the *normal* state at login.
--   2. `reason` does not distinguish enabled from disabled: a LoadOnDemand addon
--      reports "DEMAND_LOADED" either way.
--
-- So enable state is the only thing that separates "dormant" from "switched off", and
-- it lives in its own call: GetAddOnInfo lost its `enabled` field in 8.0.
function ns.Loader:IsBrowserAvailable()
    return self:UnavailableReason() == nil
end

-- Why the browser cannot be used right now, as a sentence to show a player, or nil when
-- it is fine. `IsBrowserAvailable` is defined as "no reason", so the predicate and the
-- explanation can never disagree -- they are one evaluation.
--
-- This exists because callers kept writing their own version of the explanation. PSM.Menu
-- hardcoded "Enable 'Pet Stable Management: Models Browser' in your addon list" for every
-- case, which is wrong when the folder is missing or a dependency is off, and which
-- duplicated FAILURE_HINT badly. Anything that has to tell the user why should read it
-- from here; the chat message in Announce reads the same table.
function ns.Loader:UnavailableReason()
    if self:IsBrowserLoaded() then return nil end

    if GetEnableStateFn then
        local ok, state = pcall(GetEnableStateFn, BROWSER_ADDON, UnitName("player"))
        if ok and state == ENABLE_NONE then return FAILURE_HINT.DISABLED end
    end

    local _, _, _, loadable, reason = GetAddOnInfoFn(BROWSER_ADDON)
    if loadable then return nil end

    -- Enabled and demand-loaded: dormant, and offering it is correct. Any other reason
    -- (MISSING, DEP_MISSING, CORRUPT, INCOMPATIBLE) is a real absence.
    if reason == "DEMAND_LOADED" then return nil end

    return FAILURE_HINT[reason] or ns.L("Reason: %s.", tostring(reason))
end

-- Loads the Models Browser and its data tables. Returns true when it is available
-- for use. Pass silent=true from passive callers (row rendering, anything that can
-- fire repeatedly) so a disabled module cannot spam chat.
function ns.Loader:EnsureBrowser(silent)
    if self:IsBrowserLoaded() then return true end

    -- Parsing several MB of Lua mid-fight is a visible frame hitch, and the browser
    -- also builds frames. Panels are already combat-blocked, so the callers that
    -- realistically land here in combat are passive ones, which degrade quietly.
    if InCombatLockdown and InCombatLockdown() then
        if not silent then
            ns.Utils:Msg("WARNING", ns.L("Can't load additional modules during combat."))
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
