-- Shared/PublicAPI.lua
-- What the Models Browser addon may consume from core, and the code that publishes it.
--
-- Loaded last on purpose: publishing has to happen after every core file has attached
-- itself to `ns`, so this is the final entry in the .toc. Nothing else belongs here.
--
-- The two addons cannot share a namespace -- `local addonName, ns = ...` gives each
-- *addon* its own private table -- so `_G.PSM` is the bridge between them, and this file
-- decides how narrow it is. Of core's ~38 members these fifteen are the only ones the
-- browser may read; `Tests/spec/boundary_spec.lua` parses the list out of this file and
-- fails the build if a browser file reaches for anything outside it.
--
-- Adding a name is a real decision: it is one more thing that can never change without
-- touching two addons. Prefer giving the browser a *service* over exposing an internal --
-- RowManager:ReleaseModel is what that looks like in practice. Core's WoW API aliases
-- (C_Timer, CreateFrame) stay private: they exist so the headless tests can stub them,
-- and the browser calls the globals directly.

local _, ns = ...

local PUBLIC_API = {
    "Config",        -- constants: colours and sizes (its MESSAGES moved to Locale.lua)
    "Data",          -- SavedVariables access
    "FilterState",   -- the Models Browser's five tristate toggles, and their only accessor
    "L",             -- string lookup: L("Reset Filters"), plus L.missing for /dump
    "PanelManager",  -- panel chrome: CreateBasePanel, TogglePanel, search boxes
    "PopUpManager",  -- shared popups, incl. ShowURLPopup for Wowhead links
    "RowManager",    -- model rotation/zoom hover controls, ReleaseModel
    "Selections",    -- the five multi-select filter sets; the only writer of ns.state.selected*
    "Skin",          -- ElvUI skinning (the only file allowed to see the ElvUI global)
    "Store",         -- slice versions and pull-based selectors
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

-- An `__index` that errored on every miss would be wrong: under LoadOnDemand the browser
-- is legitimately absent, so `if PSM.ModelsPanel then` reading nil is the mechanism, not
-- a mistake. The trap fires on one case only -- a name core owns and did not publish --
-- turning a silent nil into a stack trace naming the key.
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
