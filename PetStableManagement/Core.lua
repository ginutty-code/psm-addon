-- Core.lua
-- Core initialization and global setup for PetStableManagement

-- The client hands every file of an addon its folder name and a table private to
-- that addon. A3 is moving core onto `ns`; `_G.PSM` stays as the bridge to the
-- Models Browser, which is a separate addon and so gets a different `ns`.
local _, ns = ...

-- TRANSITIONAL (A3) -- undone in step 3g, with PublicAPI.lua's PUBLISH_EVERYTHING.
--
-- While core is half converted it needs to work in both directions: a converted file
-- writes `ns.Theme` where an unconverted one reads `PSM.Theme`, and vice versa. Making
-- them **the same table** does that completely, and does it at the moment of the write
-- rather than at the end of load.
--
-- The alternative -- an `__index` fallback each way -- was tried first and is wrong twice
-- over. It publishes only when PublicAPI.lua runs *last*, so it misses the handful of
-- file-scope reads that execute during load (`OptionsPanel.lua` calls PSM.Widgets.Frame,
-- `GridView.lua` reads PSM.UI.GridView, `DragDrop`/`Events` call PSM.CreateFrame). And
-- fallbacks in both directions form an `__index` cycle, which Lua does not resolve to nil
-- -- it raises "'__index' chain too long" -- so every `if PSM.ModelsPanel then` browser
-- gate in the addon would start erroring instead of testing.
--
-- One table has neither problem. There is no encapsulation during the transition, which
-- is exactly the status quo; the boundary spec still enforces the browser's side
-- statically, and 3g is where the split becomes real.
--
-- Core.lua is first in the .toc, so this covers every later file.
_G.PSM = ns

-- Initialize persistent data storage
PetStableManagementDB = PetStableManagementDB or {
    version = "3.0.0",
    lastUpdated = nil,
    characters = {},
    accountWide = {
        favoriteModels = {},
        modelViews = {},
        petGroups = {}, -- Account-wide pet groups
        ungroupedOrder = {} -- Account-wide ungrouped pets order
    },
    settings = {
        enabled = true,
        sortByDisplayID = false,
        sortBySlot = false,
        exoticFilter = false,
        duplicatesOnlyFilter = false,
        opacity = 0.8, -- Default opacity value
        modelZoom = 1.0, -- Default model zoom (100%)
        modelViewAngle = 0, -- Default model view angle (0 degrees)
         minimapButton = {
             hide = false,
             minimapPos = 220,
             lock = false
         },
         openWithStable = true, -- Open Owned Pets panel automatically when Stable window opens
         showFloatingMenu = false, -- Default unticked
         panelViewMode = "list", -- Default view mode for Owned Pets panel
         modelsViewMode = "displayId", -- Default view mode for the Models Browser panel (displayId | npc)
         -- Popup sizes the user chose by dragging a resize grip, keyed by popup name.
         -- Present means "stop auto-sizing this one" -- see PopUpManager.
         popupSizes = {}
     },
    filters = {
        selectedModelsFamilies = {},
        selectedExpansions = {},
        selectedLocations = {},
        showRares = nil,
        showFavorites = nil,
        showPetsInMyZone = nil
    },
    modelsPanelCurrentPage = 1
}

--------------------------------------------------------------------------------
-- WOW API REFERENCES
--------------------------------------------------------------------------------
--
-- These are aliases, and an alias taken at file scope is a **snapshot, not a
-- reference**: whatever the global held when this file loaded is what it holds
-- forever. That is fine for the base API, which is up before any addon runs. It is a
-- bug for anything that can appear later.
--
-- Removed from this block for that reason:
--
--   StableFrame               Blizzard_StableUI is load-on-demand, so this captured
--                             nil on any session where the stable had not been opened,
--                             and CollectStablePets then failed for the whole session.
--                             Resolved in Events.lua:CollectAndRender instead, where
--                             the frame is guaranteed to be up.
--   UIDropDownMenu_*          Blizzard_UIDropDownMenu is a separate addon and need not
--   ToggleDropDownMenu        load before us. Called through the globals now, which is
--   EasyMenu                  what the rest of the addon already did -- three of these
--                             aliases had no callers at all.
--
-- Before adding one: is the global guaranteed to exist when this file runs? If not,
-- call it through the global at the point of use.
--
-- PSM.GetSpellInfo is *expected* to be nil on modern clients -- it is the legacy half
-- of Utils:GetSpellNameCompat, which prefers C_Spell.GetSpellName and falls back only
-- if the old global is there. Nil is the answer, not a missing capture.

-- Blizzard's stable frame, looked up on every call rather than aliased. There is no
-- PSM.StableFrame field on purpose: a field would be a snapshot again, and there are
-- eight entry points into pet collection, so no single handler can be trusted to have
-- refreshed it first.
function ns.GetStableFrame()
    return StableFrame
end

ns.CreateFrame = CreateFrame
ns.C_Timer = C_Timer
ns.hooksecurefunc = hooksecurefunc
ns.C_StableInfo = C_StableInfo
ns.C_Spell = C_Spell
ns.GetSpellInfo = GetSpellInfo
ns.UIParent = UIParent
ns.GameTooltip = GameTooltip
ns.GetCursorPosition = GetCursorPosition
ns.GetCharacterKey = function() return UnitName("player") .. "-" .. GetRealmName() end

-- Check if current character is a hunter
ns.IsCurrentCharacterHunter = function()
    local _, class = UnitClass("player")
    return class and string.upper(class) == "HUNTER"
end

--------------------------------------------------------------------------------
-- STATE MANAGEMENT
--------------------------------------------------------------------------------
ns.state = {
    panel = nil,
    scrollFrame = nil,
    content = nil,
    rows = {},
    stablePets = {},
    stablePetsSnapshot = {},
    favoriteModels = {},
    favoriteModelsLoaded = false, -- guards SaveSettings from writing favoriteModels before it's loaded
    modelViews = {},
    popupZoom = 0.5,
    sortByDisplayID = false,
    sortBySlot = false,
    exoticFilter = false,
    duplicatesOnlyFilter = false,
    selectedSpecs = {},
    selectedFamilies = {},
    selectedTamers = {},
    selectedModelsFamilies = {},
    selectedExpansions = {},
    selectedLocations = {},
    showRares = nil,
    showFavorites = nil,
    showPetsInMyZone = nil,
    modelsPanelCurrentPage = 1, -- Default to page 1, will be loaded from SavedVariables later
    specList = {},
    familyList = {},
    tamerList = {},
    isStableOpen = false,
    minimapButton = nil,
    exportFrame = nil,
    tamerSelectionInitialized = false, -- Track if tamer selection has been explicitly set
    panelViewMode = "list", -- Default to list view mode for Owned Pets panel
    modelsViewMode = "displayId", -- Default to display-ID view mode for the Models Browser panel
}

-- Initialize transparency settings when addon loads
function PSM:InitializeOpacity()
    if not PetStableManagementDB.settings.opacity then
        PetStableManagementDB.settings.opacity = 0.8 -- Default opacity
    end
    -- Update colors with current opacity
    ns.Config:UpdateColors()
    -- Refresh all panel backgrounds with current opacity
    ns.PanelManager:UpdatePanelBackgrounds()
end

-- ─── Stable-frame buttons ────────────────────────────────────────────────────
--
-- These anchor to Blizzard's "Put in Stable" button, which is **not reliably present
-- when PET_STABLE_SHOW fires**. It has been observed missing while our own buttons
-- were already on screen, so it is created lazily or conditionally by Blizzard rather
-- than existing for the life of the frame.
--
-- This used to be a hard requirement guarded by a bare `return`. Losing that race took
-- both buttons away for the rest of the session, logged nothing, and survived a
-- /reload -- because the next show lost the race too. A silent early return in code
-- that runs on an event is indistinguishable from the feature not existing.
--
-- So the anchor is optional now, and position is recomputed on every show rather than
-- fixed at creation: a late-appearing anchor is picked up without the buttons ever
-- having to vanish to wait for it.

local STABLE_BUTTON_SPACING = 5

local function FindPutInStableButton()
    local direct = StableFrame.PetSelectButton or StableFrame.SetPetButton
                   or StableFrame.PutInStableButton
    if direct then return direct end

    for _, child in ipairs({ StableFrame:GetChildren() }) do
        if child and child:GetObjectType() == "Button" then
            local text = child:GetText()
            if text and (text:find("Put") or text:find("Stable") or text:find("Select")) then
                return child
            end
        end
    end
    return nil
end

-- Anchored to Blizzard's button when there is one, and to the frame's bottom-right
-- corner when there is not, which is about where that button sits anyway.
local function PositionStableButtons(teamsListButton, saveButton)
    local anchor = FindPutInStableButton()
    local width  = (anchor and anchor:GetWidth())  or ns.Theme.CONTROL.BUTTON_W.S
    local height = ((anchor and anchor:GetHeight()) or ns.Theme.CONTROL.BUTTON) + 3

    for _, btn in ipairs({ teamsListButton, saveButton }) do
        btn:SetSize(width, height)
        btn:ClearAllPoints()
        btn.underlyingButton = anchor
    end

    if anchor then
        saveButton:SetPoint("BOTTOM", anchor, "TOP", 0, 10)
        teamsListButton:SetPoint("BOTTOM", anchor, "TOP", 0,
            15 + height + STABLE_BUTTON_SPACING)
    else
        saveButton:SetPoint("BOTTOMRIGHT", StableFrame, "BOTTOMRIGHT", -20,
            20 + height + STABLE_BUTTON_SPACING)
        teamsListButton:SetPoint("BOTTOM", saveButton, "TOP", 0, STABLE_BUTTON_SPACING)
    end
end

-- Create Save Team button on Blizzard's stable frame
function PSM:CreateSaveTeamButtonOnStable()
    if not StableFrame then return end

    -- Reuse what is already there. This used to build two new frames on every show,
    -- each with the same global name, and add another OnHide hook that could never be
    -- removed -- so the leak grew for as long as the session did.
    if StableFrame.PSM_TeamsListButton and StableFrame.PSM_SaveTeamButton then
        PositionStableButtons(StableFrame.PSM_TeamsListButton, StableFrame.PSM_SaveTeamButton)
        PSM:UpdateSaveTeamButtonState()
        StableFrame.PSM_TeamsListButton:Show()
        StableFrame.PSM_SaveTeamButton:Show()
        return
    end

    -- Read here, not at file scope: this file loads before UI/Theme.lua and
    -- UI/Widgets.lua, so at parse time neither exists. By the time a stable opens they
    -- do. Same rule the browser addon follows for core tables.
    local Widgets = ns.Widgets
    local Theme   = ns.Theme

    -- Anchored below the button because these sit near the bottom of the stable frame,
    -- where a tooltip to the right would run off the model scene.
    local ANCHOR = "ANCHOR_BOTTOM"

    local teamsListButton = Widgets.Button(StableFrame, {
        name       = "PSM_TeamsListButton",
        text       = "Teams List",
        fontObject = "GameFontNormal",
        strata     = "HIGH",   -- above the stable's model scene
        level      = 10,
        onClick    = function() ns.TeamsPanel:Toggle() end,
        -- A function spec: the team count changes while the button exists.
        tooltip    = function()
            return {
                anchor = ANCHOR,
                title  = "View and manage saved pet teams",
                lines  = {
                    { text  = ("You have %d saved team(s)"):format(ns.Teams:GetTeamCount() or 0),
                      color = Theme.COLOR.WHITE },
                },
            }
        end,
    })
    StableFrame.PSM_TeamsListButton = teamsListButton

    -- SAVING A TEAM IS NOT STABLE-ONLY. This button is a convenience for players who
    -- arrange their pets in Blizzard's own stable UI and want to keep that arrangement,
    -- so it captures the *live* slot layout -- and that is the only reason it needs the
    -- stable open. It calls Teams:SaveTeam/UpdateTeam without a `slots` argument, and
    -- those fall back to Teams:GetCurrentSlots(), which reads C_StableInfo.
    --
    -- Every other route passes `slots` explicitly (built by Teams:SlotRecord) and has no
    -- stable requirement at all: the Teams panel and the dialogs in Shared/Dialogs.lua
    -- create and edit teams anywhere, any time. Persistence is
    -- PetStableManagementDB.characters[<char>].teams, reached through CharData() in
    -- TeamsData.lua and mutated in place -- there is no separate "write" step, which is
    -- why nothing outside the stable needs a Save button.
    --
    -- Only *applying* a team requires a stable visit.
    --
    -- Deliberately no disabled state and no "visit a stable master" tooltip: this button
    -- is parented to StableFrame and hidden on PET_STABLE_CLOSED, so it is never visible
    -- while the stable is shut. Both used to exist, and both taught the reader that
    -- teams can only be saved at a stable, which is false.
    local saveButton = Widgets.Button(StableFrame, {
        name       = "PSM_SaveTeamButton",
        text       = "Save Team",
        fontObject = "GameFontNormal",
        strata     = "HIGH",
        level      = 10,
        onClick    = function()
            -- Kept as a guard, not as UI: if this button's visibility ever changes,
            -- capturing slots without a stable would silently save an empty team.
            if not ns.state.isStableOpen then
                print("|cFFFF8800PetStableManagement: You must be at a Stable Master to save a team.|r")
                return
            end
            ns.UI:HandleSaveTeamClick()
        end,
        tooltip    = { anchor = ANCHOR, title = "Save current pets in slots 1-6 as a team" },
    })
    StableFrame.PSM_SaveTeamButton = saveButton

    -- Hooked once, on the pass that creates the buttons. HookScript cannot be undone,
    -- so doing this per show accumulated a closure for every stable visit.
    StableFrame:HookScript("OnHide", function()
        saveButton:Hide()
        teamsListButton:Hide()
    end)

    PositionStableButtons(teamsListButton, saveButton)
    -- The enable/disable rules live in UpdateSaveTeamButtonState. This used to restate
    -- them here, which is how two copies of one rule start drifting.
    PSM:UpdateSaveTeamButtonState()

    saveButton:Show()
    teamsListButton:Show()
end

-- Both stable-frame buttons are usable whenever they are visible, and they are only
-- ever visible during a stable visit -- so there is no per-show state left to compute.
-- This stays as the one place that would own such a rule if one is ever needed again;
-- what it must not grow back is a "disabled outside the stable" branch, which described
-- a state that cannot happen and implied teams can only be saved at a stable.
function PSM:UpdateSaveTeamButtonState()
    for _, name in ipairs({ "PSM_SaveTeamButton", "PSM_TeamsListButton" }) do
        local button = StableFrame and StableFrame[name]
        if button then
            button:Enable()
            button:SetAlpha(1.0)
        end
    end
end