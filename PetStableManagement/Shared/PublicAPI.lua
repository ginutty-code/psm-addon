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
    "FilterState",   -- the Models Browser's five tristate toggles, and their only accessor
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

local published = {}
for _, name in ipairs(PUBLIC_API) do
    published[name] = true
    _G.PSM[name] = ns[name]
end

--------------------------------------------------------------------------------
-- The trap
--------------------------------------------------------------------------------

-- Everything core defined that is *not* on the list above. Computed rather than written
-- out, because a list typed here would go stale the first time a module is added.
--
-- `pairs` walks own keys only, and this runs last in the .toc, so `ns` is complete.
local internal = {}
for name in pairs(ns) do
    if not published[name] then internal[name] = true end
end

-- **An `__index` that errors on every miss would be wrong**, and the reason is the whole
-- shape of this addon: under LoadOnDemand the browser is legitimately absent, so
-- `if PSM.ModelsPanel then` reading nil is not a mistake, it is the mechanism. Erroring
-- there would break exactly the gates that make the module optional.
--
-- So the trap fires on one case only: a name core owns and did not publish. That is never
-- a legitimate read -- it is a file reaching past the boundary -- and it is the failure
-- mode this whole step introduces, since before 3g every such read quietly worked.
--
-- boundary_spec.lua already proves no browser file does this today. The trap is for the
-- edit made a year from now, and it turns a silent nil into a stack trace naming the key.
setmetatable(_G.PSM, {
    __index = function(_, key)
        if internal[key] then
            error(("PSM.%s is internal to PetStableManagement and is not part of its "
                .. "public API. See Shared/PublicAPI.lua -- either use a published "
                .. "member, or add a service there deliberately."):format(tostring(key)), 2)
        end
        return nil
    end,
})
