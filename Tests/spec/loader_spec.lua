-- Tests/spec/loader_spec.lua
-- PSM.Loader:IsBrowserAvailable — "offer this action?" under LoadOnDemand.
--
-- This exists because the distinction it draws is one WoW's API actively obscures.
-- GetAddOnInfo's `loadable` is false for a LoadOnDemand addon that is present and
-- enabled but not yet parsed; it reports reason = "DEMAND_LOADED". Reading `loadable`
-- alone answers "not available" for the entire normal case, and every affordance gated
-- on it hides until something else loads the browser -- which is how the minimap
-- tooltip came to list three clicks instead of four, and PSM.Menu to hide its browser
-- entries, on every fresh login.
--
-- The stubs below return exactly what the client returns for each state. That is the
-- rule for this repo's stubs: faithful for the cases under test, or absent.

local T = ...
local describe, it, eq = T.describe, T.it, T.eq

-- Loaded with the client's calling convention rather than dofile -- see Tests/wow/addon.lua.
local Addon = dofile("Tests/wow/addon.lua")

-- One row per state the AddOns list can put the browser in. `loadable`/`reason` mirror
-- GetAddOnInfo's 4th and 5th returns; `enable` mirrors GetAddOnEnableState (0/1/2).
--
-- The critical row is `disabled`. An earlier version of this file guessed it reported
-- reason = "DISABLED" and passed, which made a wrong implementation look verified. The
-- client actually returns **DEMAND_LOADED for a disabled LoadOnDemand addon too** --
-- measured with the module unticked and the UI reloaded. `reason` therefore cannot tell
-- dormant from switched-off, and only the enable state can.
local STATES = {
    dormant      = { loaded = false, loadable = false, reason = "DEMAND_LOADED", enable = 2 },
    loaded       = { loaded = true,  loadable = false, reason = "DEMAND_LOADED", enable = 2 },
    disabled     = { loaded = false, loadable = false, reason = "DEMAND_LOADED", enable = 0 },
    -- Enabled for some characters but not others still counts as available here: the
    -- query is per-character, so 1 means this character can load it.
    someChars    = { loaded = false, loadable = false, reason = "DEMAND_LOADED", enable = 1 },
    missing      = { loaded = false, loadable = false, reason = "MISSING",       enable = 2 },
    depMissing   = { loaded = false, loadable = false, reason = "DEP_MISSING",   enable = 2 },
    -- A non-LoadOnDemand addon that is simply enabled reports loadable = true.
    plainEnabled = { loaded = false, loadable = true,  reason = nil,             enable = 2 },
}

-- Loads a fresh copy of Loader.lua against `state`. Fresh because Loader memoises
-- "loaded" in a file-local, and because it captures the C_AddOns functions at file
-- scope -- so the stubs have to be in place before it is parsed, and a second test
-- must not inherit the first one's memo.
local function loaderFor(state)
    _G.PSM = {}
    _G.UnitName = function() return "Tester" end
    _G.C_AddOns = {
        IsAddOnLoaded = function() return state.loaded end,
        LoadAddOn     = function() return state.loaded end,
        GetAddOnInfo  = function(name)
            return name, name, "", state.loadable, state.reason
        end,
        -- Signature is (addOnName, characterName); returning by addon only, since the
        -- spec has one addon. A wrong argument order in the caller would show up as
        -- this stub receiving the character name first.
        GetAddOnEnableState = function(addon, character)
            if addon ~= "PetStableManagement_ModelsBrowser" then
                error("GetAddOnEnableState called with arguments reversed: got addon="
                      .. tostring(addon) .. ", character=" .. tostring(character), 0)
            end
            return state.enable
        end,
    }
    -- Read off the namespace, not _G.PSM: Loader.lua is A3-converted and attaches
    -- itself to `ns`. In the game PublicAPI.lua republishes it; here the spec has the
    -- namespace in hand, which is the more direct assertion anyway.
    -- Locale first, into the same namespace: Loader builds its failure hints at file
    -- scope through ns.L, so loading it alone leaves L nil.
    local ns = Addon.namespace()
    Addon.load("PetStableManagement/Shared/Locale.lua", ns)
    return Addon.load("PetStableManagement/Shared/Loader.lua", ns).Loader
end

describe("Loader:IsBrowserAvailable", function()
    -- The regression this file was written for.
    it("offers the browser while it is dormant (enabled, not yet parsed)", function()
        eq(loaderFor(STATES.dormant):IsBrowserAvailable(), true, "dormant")
    end)

    it("offers the browser once it is loaded", function()
        eq(loaderFor(STATES.loaded):IsBrowserAvailable(), true, "loaded")
    end)

    it("offers a plain enabled addon that reports loadable", function()
        eq(loaderFor(STATES.plainEnabled):IsBrowserAvailable(), true, "plain enabled")
    end)

    it("offers the browser when enabled for only some characters", function()
        eq(loaderFor(STATES.someChars):IsBrowserAvailable(), true, "some characters")
    end)

    -- The regression this file was rewritten for. `disabled` and `dormant` are
    -- indistinguishable by GetAddOnInfo -- same loadable, same reason -- so this is the
    -- pair that proves the enable-state check is doing the work.
    it("hides the browser when it is switched off in the AddOns list", function()
        eq(loaderFor(STATES.disabled):IsBrowserAvailable(), false, "disabled")
    end)

    it("tells disabled from dormant, which report identical GetAddOnInfo returns", function()
        eq(STATES.disabled.reason, STATES.dormant.reason, "fixture: same reason")
        eq(STATES.disabled.loadable, STATES.dormant.loadable, "fixture: same loadable")
        eq(loaderFor(STATES.dormant):IsBrowserAvailable(),  true,  "dormant is available")
        eq(loaderFor(STATES.disabled):IsBrowserAvailable(), false, "disabled is not")
    end)

    it("hides the browser when its folder or a dependency is gone", function()
        eq(loaderFor(STATES.missing):IsBrowserAvailable(),    false, "missing")
        eq(loaderFor(STATES.depMissing):IsBrowserAvailable(), false, "dep missing")
    end)
end)

describe("Loader:UnavailableReason", function()
    -- IsBrowserAvailable is defined as "UnavailableReason() == nil", so the two can never
    -- disagree by construction. This block guards the other half: that the reason is
    -- specific enough to show a player. PSM.Menu used to hardcode "enable it in your
    -- addon list" for every case, which is simply wrong when the folder is missing.
    it("gives no reason when the browser is usable", function()
        eq(loaderFor(STATES.dormant):UnavailableReason(),      nil, "dormant")
        eq(loaderFor(STATES.loaded):UnavailableReason(),       nil, "loaded")
        eq(loaderFor(STATES.plainEnabled):UnavailableReason(), nil, "plain enabled")
        eq(loaderFor(STATES.someChars):UnavailableReason(),    nil, "some characters")
    end)

    it("blames the AddOns list when it is switched off", function()
        local why = loaderFor(STATES.disabled):UnavailableReason()
        eq(type(why), "string", "disabled gives a reason")
        eq(why:find("AddOns list", 1, true) ~= nil, true, "mentions the AddOns list")
    end)

    -- The distinction the old hardcoded string could not draw: telling someone to enable
    -- an addon whose folder is not installed sends them looking for a tickbox that is
    -- not there.
    it("distinguishes a missing folder from a disabled addon", function()
        local missing  = loaderFor(STATES.missing):UnavailableReason()
        local disabled = loaderFor(STATES.disabled):UnavailableReason()
        eq(type(missing), "string", "missing gives a reason")
        eq(missing ~= disabled, true, "missing reads differently from disabled")
        eq(missing:find("Interface/AddOns", 1, true) ~= nil, true, "points at the folder")
    end)

    it("has a reason wherever IsBrowserAvailable says no", function()
        for name, state in pairs(STATES) do
            local L = loaderFor(state)
            eq(L:IsBrowserAvailable(), L:UnavailableReason() == nil, name)
        end
    end)
end)

describe("Loader:IsBrowserLoaded", function()
    -- The narrower question, and the one UI must NOT ask: dormant is the normal state
    -- at login, so gating an affordance on this disables it until first use.
    it("is false while dormant, unlike IsBrowserAvailable", function()
        local L = loaderFor(STATES.dormant)
        eq(L:IsBrowserLoaded(), false, "dormant is not loaded")
        eq(L:IsBrowserAvailable(), true, "but it is available")
    end)

    it("is true once the addon is loaded", function()
        eq(loaderFor(STATES.loaded):IsBrowserLoaded(), true, "loaded")
    end)
end)
