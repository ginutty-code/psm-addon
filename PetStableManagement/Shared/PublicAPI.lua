-- Shared/PublicAPI.lua
-- What the Models Browser addon may consume from core, and the code that publishes it.
--
-- **Loaded last on purpose.** Publishing has to happen after every core file has attached
-- itself to `ns`, so this file is the final entry in the .toc. Nothing else belongs here;
-- if it needs to run before another core file, it is in the wrong file.
--
-- The two addons cannot share a namespace -- `local addonName, ns = ...` gives each
-- *addon* its own private table, and PetStableManagement and its Models Browser are two
-- addons. So `_G.PSM` survives A3 as the bridge between them, and this file decides how
-- narrow that bridge is.
--
-- Core defines ~38 members. These eleven are the only ones the browser may read;
-- everything else stays private to core. `Tests/spec/boundary_spec.lua` parses this list
-- out of this file and fails the build if a browser file reaches for anything outside it.
--
-- **Derived from measurement, not designed.** Every name was found by scanning what the
-- browser actually references, and that corrected the planned list in both directions:
-- `Loader` was on it and is *not* used by the browser (sensibly -- Loader is what loads
-- the browser), while `C_Timer` and `CreateFrame` *were* being used and should not have
-- been. Those are core's WoW API aliases, kept so the headless tests can stub them; the
-- browser calls the globals directly, as ModelRow.lua was already fixed to do.
--
-- Adding a name is a real decision: it is one more thing that can never change without
-- touching two addons. Prefer giving the browser a *service* over exposing an internal --
-- the UI kit is the model, four names with no back-references, and RowManager:ReleaseModel
-- is what that looks like in practice.

local _, ns = ...

local PUBLIC_API = {
    "Config",        -- constants: colours, sizes, strings
    "Data",          -- SavedVariables access
    "PanelManager",  -- panel chrome: CreateBasePanel, TogglePanel, search boxes
    "PopUpManager",  -- shared popups, incl. ShowURLPopup for Wowhead links
    "RowManager",    -- model rotation/zoom hover controls, ReleaseModel
    "Skin",          -- ElvUI skinning (the only file allowed to see the ElvUI global)
    "Theme",         -- fonts, colour ramp, control sizes, backdrop presets
    "Tooltip",       -- declarative tooltip attachment
    "Utils",         -- pure helpers
    "Widgets",       -- the frame factories
    "state",         -- shared mutable state -- by far the largest consumer (218 of the
                     -- browser's ~437 core references). A5 owns shrinking this; until
                     -- then it is public because it has to be, not because it should be.
}

--------------------------------------------------------------------------------
-- TRANSITIONAL -- remove when every core file has been converted (A3 step 3g)
--------------------------------------------------------------------------------

-- While core is half converted, Core.lua aliases `_G.PSM = ns` -- one table under two
-- names -- so converted and unconverted files already see each other's writes and there
-- is nothing to publish. See Core.lua for why an `__index` fallback was not enough.
--
-- Flip this to false in 3g, when Core.lua stops aliasing and `_G.PSM` becomes a separate,
-- deliberately narrow table. That is the moment nil becomes possible, so it lands with the
-- trap metatable and its own round of testing -- the conversions themselves are not where
-- the risk is.
local TRANSITIONAL = true

--------------------------------------------------------------------------------

local function Publish()
    -- Same table during the transition: every member is already reachable as PSM.x.
    if TRANSITIONAL then return end

    for _, name in ipairs(PUBLIC_API) do
        _G.PSM[name] = ns[name]
    end
end

Publish()
