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

-- Create Save Team button on Blizzard's stable frame
function PSM:CreateSaveTeamButtonOnStable()
    if not StableFrame then return end
    
    -- Find Blizzard's "Put in Stable" button (PetSelectButton in modern WoW)
    local putInStableButton = StableFrame.PetSelectButton or StableFrame.SetPetButton or StableFrame.PutInStableButton
    
    if not putInStableButton then
        -- Try to find any button in the bottom right area
        for _, child in ipairs({StableFrame:GetChildren()}) do
            if child and child:GetObjectType() == "Button" then
                local text = child:GetText()
                if text and (text:find("Put") or text:find("Stable") or text:find("Select")) then
                    putInStableButton = child
                    break
                end
            end
        end
    end
    
    if not putInStableButton then return end
    
    -- Get button size and add 3px to height
    local buttonWidth = putInStableButton:GetWidth() or 80
    local buttonHeight = (putInStableButton:GetHeight() or 25) + 3
    local buttonSpacing = 5  -- Spacing between buttons
    
    -- Create Teams List button (positioned above Save Team button)
    local teamsListButton = CreateFrame("Button", "PSM_TeamsListButton", StableFrame, "UIPanelButtonTemplate")
    teamsListButton:SetSize(buttonWidth, buttonHeight)
    teamsListButton:SetText("Teams List")
    teamsListButton:SetNormalFontObject("GameFontNormal")
    
    -- Set higher frame strata to appear above model scene
    teamsListButton:SetFrameStrata("HIGH")
    teamsListButton:SetFrameLevel(10)
    
    -- Position above the Put in Stable button (with spacing for Save Team button below)
    teamsListButton:ClearAllPoints()
    teamsListButton:SetPoint("BOTTOM", putInStableButton, "TOP", 0, 15 + buttonHeight + buttonSpacing)
    
    -- Store reference to the underlying button for positioning updates
    teamsListButton.underlyingButton = putInStableButton
    
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
    saveButton:SetSize(buttonWidth, buttonHeight)
    saveButton:SetText("Save Team")
    saveButton:SetNormalFontObject("GameFontNormal")
    
    -- Set higher frame strata to appear above model scene
    saveButton:SetFrameStrata("HIGH")
    saveButton:SetFrameLevel(10)
    
    -- Position above the Put in Stable button
    saveButton:ClearAllPoints()
    saveButton:SetPoint("BOTTOM", putInStableButton, "TOP", 0, 10)
    
    -- Store reference to the underlying button for positioning updates
    saveButton.underlyingButton = putInStableButton
    
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
    
    -- Update initial state
    if PSM.state.isStableOpen then
        saveButton:Enable()
        saveButton:SetAlpha(1.0)
        teamsListButton:Enable()
        teamsListButton:SetAlpha(1.0)
    else
        saveButton:Disable()
        saveButton:SetAlpha(0.5)
        teamsListButton:Enable()
        teamsListButton:SetAlpha(1.0)
    end
    
    -- Hook into PET_STABLE_CLOSED to hide/disable the buttons
    StableFrame:HookScript("OnHide", function()
        if saveButton then
            saveButton:Hide()
        end
        if teamsListButton then
            teamsListButton:Hide()
        end
    end)
    
    -- Show the buttons
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