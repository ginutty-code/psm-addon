-- Core.lua
-- Core initialization and global setup for PetStableManagement

local addonName = "PetStableManagement"

-- Initialize global namespace
_G.PSM = _G.PSM or {}
local PSM = _G.PSM

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
         modelsViewMode = "displayId" -- Default view mode for the Models Browser panel (displayId | npc)
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
PSM.CreateFrame = CreateFrame
PSM.StableFrame = StableFrame
PSM.UIDropDownMenu_Initialize = UIDropDownMenu_Initialize
PSM.UIDropDownMenu_SetWidth = UIDropDownMenu_SetWidth
PSM.UIDropDownMenu_SetText = UIDropDownMenu_SetText
PSM.UIDropDownMenu_AddButton = UIDropDownMenu_AddButton
PSM.UIDropDownMenu_CreateInfo = UIDropDownMenu_CreateInfo
PSM.C_Timer = C_Timer
PSM.hooksecurefunc = hooksecurefunc
PSM.C_StableInfo = C_StableInfo
PSM.C_Spell = C_Spell
PSM.GetSpellInfo = GetSpellInfo
PSM.UIParent = UIParent
PSM.GameTooltip = GameTooltip
PSM.GetCursorPosition = GetCursorPosition
PSM.ToggleDropDownMenu = ToggleDropDownMenu
PSM.EasyMenu = EasyMenu
PSM.GetCharacterKey = function() return UnitName("player") .. "-" .. GetRealmName() end

-- Check if current character is a hunter
PSM.IsCurrentCharacterHunter = function()
    local _, class = UnitClass("player")
    return class and string.upper(class) == "HUNTER"
end

--------------------------------------------------------------------------------
-- STATE MANAGEMENT
--------------------------------------------------------------------------------
PSM.state = {
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
    PSM.Config:UpdateColors()
    -- Refresh all panel backgrounds with current opacity
    PSM.PanelManager:UpdatePanelBackgrounds()
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
    local width  = (anchor and anchor:GetWidth())  or PSM.Config.BUTTON_WIDTH
    local height = ((anchor and anchor:GetHeight()) or PSM.Config.PANEL_BUTTON_HEIGHT) + 3

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

    -- Create Teams List button (positioned above Save Team button)
    local teamsListButton = CreateFrame("Button", "PSM_TeamsListButton", StableFrame, "UIPanelButtonTemplate")
    teamsListButton:SetText("Teams List")
    teamsListButton:SetNormalFontObject("GameFontNormal")

    -- Set higher frame strata to appear above model scene
    teamsListButton:SetFrameStrata("HIGH")
    teamsListButton:SetFrameLevel(10)

    -- OnClick handler - toggle the Pet Teams panel
    teamsListButton:SetScript("OnClick", function()
        PSM.TeamsPanel:Toggle()
    end)

    -- Tooltip
    teamsListButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        local teamCount = PSM.Teams:GetTeamCount() or 0
        GameTooltip:SetText("View and manage saved pet teams")
        GameTooltip:AddLine("You have " .. teamCount .. " saved team(s)", 1, 1, 1)
        GameTooltip:Show()
    end)
    teamsListButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    PSM.UI:ApplyElvUISkin(teamsListButton, "button")
    
    -- Store reference
    StableFrame.PSM_TeamsListButton = teamsListButton
    
    -- Create Save Team button
    local saveButton = CreateFrame("Button", "PSM_SaveTeamButton", StableFrame, "UIPanelButtonTemplate")
    saveButton:SetText("Save Team")
    saveButton:SetNormalFontObject("GameFontNormal")

    -- Set higher frame strata to appear above model scene
    saveButton:SetFrameStrata("HIGH")
    saveButton:SetFrameLevel(10)

    -- OnClick handler
    saveButton:SetScript("OnClick", function()
        if not PSM.state.isStableOpen then
            print("|cFFFF8800PetStableManagement: You must be at a Stable Master to save a team.|r")
            return
        end
        PSM.UI:HandleSaveTeamClick()
    end)
    
    -- Tooltip
    saveButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        if PSM.state.isStableOpen then
            GameTooltip:SetText("Save current pets in slots 1-6 as a team")
        else
            GameTooltip:SetText("Visit a Stable Master to save teams")
            GameTooltip:AddLine("Requires stable to be open", 1, 0.5, 0)
        end
        GameTooltip:Show()
    end)
    saveButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    PSM.UI:ApplyElvUISkin(saveButton, "button")
    
    -- Store reference
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

-- Update Save Team button state
function PSM:UpdateSaveTeamButtonState()
    -- Update Save Team button (requires stable to be open)
    if StableFrame and StableFrame.PSM_SaveTeamButton then
        local button = StableFrame.PSM_SaveTeamButton
        if PSM.state.isStableOpen then
            button:Enable()
            button:SetAlpha(1.0)
        else
            button:Disable()
            button:SetAlpha(0.5)
        end
    end
    
    -- Update Teams List button (always enabled when visible)
    if StableFrame and StableFrame.PSM_TeamsListButton then
        local button = StableFrame.PSM_TeamsListButton
        button:Enable()
        button:SetAlpha(1.0)
    end
end