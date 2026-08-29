-- Core.lua
-- Core initialization and global setup for PetStableManagement

local _, ns = ...

-- The bridge between the two addons, not core's namespace: it holds what
-- Shared/PublicAPI.lua publishes plus whatever the Models Browser attaches. Core.lua is
-- first in the .toc, so creating it here means it exists for every later file of either.
_G.PSM = _G.PSM or {}

-- ─── Reaching the Models Browser ─────────────────────────────────────────────
--
-- `ns.Browser.` in a core file means exactly one thing: this crosses into the other
-- addon. Writes forward as well as reads -- PanelManager clears four browser caches by
-- hand, and a read-only proxy would swallow those assignments silently.
--
-- Reading a name the browser has not loaded yet gives nil, which is what every
-- `if ns.Browser.ModelsPanel then` gate expects. Reading a *core* name through it raises,
-- via the trap PublicAPI.lua installs.
ns.Browser = setmetatable({}, {
    __index    = function(_, key) return _G.PSM[key] end,
    __newindex = function(_, key, value) _G.PSM[key] = value end,
})

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
-- An alias taken at file scope is a snapshot, not a reference. That is fine for the base
-- API, which is up before any addon runs, and a bug for anything that can appear later
-- (load-on-demand frames, separate Blizzard addons) -- call those through the global at
-- the point of use instead.
--
-- PSM.GetSpellInfo is *expected* to be nil on modern clients -- it is the legacy half
-- of Utils:GetSpellNameCompat. Nil is the answer, not a missing capture.

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
    pendingNativeFavorite = {}, -- petNumber -> bool, a native push queued while away from the stable
    lastKnownNativeFavorite = {}, -- petNumber -> bool, last-seen native state, to detect a direct native click
    pendingFavoriteBroadcast = {}, -- displayID -> bool, acted on once collection finishes (see CollectStablePets)
    modelViews = {},
    popupZoom = 0.5,
    exoticFilter = false,
    duplicatesOnlyFilter = false,
    favoritesOnlyFilter = false,
    selectedSpecs = {},
    selectedFamilies = {},
    selectedTamers = {},
    selectedAbilities = {},
    selectedModelsFamilies = {},
    selectedExpansions = {},
    selectedLocations = {},
    -- The five Models Browser tristate toggles (showRares, showFavorites, showHideOwned,
    -- showNameKeepers, showPetsInMyZone) were declared here and mirrored into this table
    -- on every change. Nothing ever read them: the toggles are read off the panel frame,
    -- and persisted to PetStableManagementDB.filters. Removed, along with 15 writes.
    --
    -- Two of the five were never even listed, and `= nil` in a table constructor stores no
    -- key at all -- so the declaration described neither the real shape nor a real field.
    modelsPanelCurrentPage = 1, -- Default to page 1, will be loaded from SavedVariables later
    specList = {},
    familyList = {},
    abilityList = {},
    tamerList = {},
    isStableOpen = false,
    minimapButton = nil,
    exportFrame = nil,
    tamerSelectionInitialized = false, -- Track if tamer selection has been explicitly set
    panelViewMode = "list", -- Default to list view mode for Owned Pets panel
    modelsViewMode = "displayId", -- Default to display-ID view mode for the Models Browser panel
}

-- Initialize transparency settings when addon loads
function ns:InitializeOpacity()
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
-- These anchor to Blizzard's "Put in Stable" button, which is not reliably present when
-- PET_STABLE_SHOW fires -- it is created lazily. So the anchor is optional, and position
-- is recomputed on every show rather than fixed at creation: a late-appearing anchor is
-- picked up without the buttons ever having to vanish to wait for it. Never gate their
-- creation on finding it.

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
function ns:CreateSaveTeamButtonOnStable()
    if not StableFrame then return end

    -- Reuse what is already there. This used to build two new frames on every show,
    -- each with the same global name, and add another OnHide hook that could never be
    -- removed -- so the leak grew for as long as the session did.
    if StableFrame.PSM_TeamsListButton and StableFrame.PSM_SaveTeamButton then
        PositionStableButtons(StableFrame.PSM_TeamsListButton, StableFrame.PSM_SaveTeamButton)
        ns:UpdateSaveTeamButtonState()
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
        text       = ns.L("Teams List"),
        fontObject = "GameFontNormal",
        strata     = "HIGH",   -- above the stable's model scene
        level      = 10,
        onClick    = function() ns.TeamsPanel:Toggle() end,
        -- A function spec: the team count changes while the button exists.
        tooltip    = function()
            return {
                anchor = ANCHOR,
                title  = ns.L("View and manage saved pet teams"),
                lines  = {
                    { text  = ns.L("You have %d saved team(s)", ns.Teams:GetTeamCount() or 0),
                      color = Theme.COLOR.WHITE },
                },
            }
        end,
    })
    StableFrame.PSM_TeamsListButton = teamsListButton

    -- SAVING A TEAM IS NOT STABLE-ONLY. This button captures the *live* slot layout --
    -- it calls SaveTeam/UpdateTeam without a `slots` argument, so they fall back to
    -- Teams:GetCurrentSlots() and C_StableInfo, and that is the only reason it needs the
    -- stable open. Every other route passes `slots` explicitly and works anywhere. Only
    -- *applying* a team requires a stable visit.
    --
    -- Deliberately no disabled state and no "visit a stable master" tooltip: the button
    -- is parented to StableFrame and hidden on PET_STABLE_CLOSED, so it is never visible
    -- while the stable is shut, and both taught the reader something false.
    local saveButton = Widgets.Button(StableFrame, {
        name       = "PSM_SaveTeamButton",
        text       = ns.L("Save Team"),
        fontObject = "GameFontNormal",
        strata     = "HIGH",
        level      = 10,
        onClick    = function()
            -- Kept as a guard, not as UI: if this button's visibility ever changes,
            -- capturing slots without a stable would silently save an empty team.
            if not ns.state.isStableOpen then
                ns.Utils:Msg("WARNING", ns.L("You must be at a Stable Master to save a team."))
                return
            end
            ns.UI:HandleSaveTeamClick()
        end,
        tooltip    = { anchor = ANCHOR, title = ns.L("Save current pets in slots 1-6 as a team") },
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
    ns:UpdateSaveTeamButtonState()

    saveButton:Show()
    teamsListButton:Show()
end

-- Both stable-frame buttons are usable whenever they are visible, and they are only
-- ever visible during a stable visit -- so there is no per-show state left to compute.
-- This stays as the one place that would own such a rule if one is ever needed again;
-- what it must not grow back is a "disabled outside the stable" branch, which described
-- a state that cannot happen and implied teams can only be saved at a stable.
function ns:UpdateSaveTeamButtonState()
    for _, name in ipairs({ "PSM_SaveTeamButton", "PSM_TeamsListButton" }) do
        local button = StableFrame and StableFrame[name]
        if button then
            button:Enable()
            button:SetAlpha(1.0)
        end
    end
end