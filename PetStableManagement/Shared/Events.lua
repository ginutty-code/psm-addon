-- Events.lua
-- Event handling for PetStableManagement

local addonName = "PetStableManagement"

_G.PSM = _G.PSM or {}
local PSM = _G.PSM

--------------------------------------------------------------------------------
-- DEBOUNCED UPDATE
--------------------------------------------------------------------------------

local updateTimer = nil
local _lastScheduledCollectedCount = nil

-- Blizzard's on-screen "X/Y" pet-count label -- more reliable than
-- dataProvider:GetSize(). Used as a fast-path signal below, with the
-- stability check as fallback if it's ever missing/unparseable.
local function GetListCounterText()
    local counter = PSM.StableFrame and PSM.StableFrame.StabledPetList
                 and PSM.StableFrame.StabledPetList.ListCounter
                 and PSM.StableFrame.StabledPetList.ListCounter.Count
    if counter and counter.GetText then
        local ok, text = pcall(counter.GetText, counter)
        if ok then return text end
    end
    return nil
end

local function ParseListCounterCount(text)
    if not text then return nil end
    local n = text:match("^(%d+)")
    return n and tonumber(n)
end

local function ScheduleUpdateWithRetry(retryCount)
    retryCount = retryCount or 0

    local collectedCount, expectedCount = PSM.Data:CollectStablePets()
    collectedCount = collectedCount or 0
    expectedCount  = expectedCount  or 0
    local listCounterCount = ParseListCounterCount(GetListCounterText())

    -- expectedCount isn't trustworthy (see CollectAndRender below); a match
    -- against the on-screen counter is treated as immediate proof of
    -- completeness, with two consecutive identical readings as the fallback.
    local isAtCap = collectedCount >= PSM.Config.MAX_STABLE_SLOTS
    local matchesListCounter = listCounterCount ~= nil and collectedCount == listCounterCount
    local isStable = isAtCap or matchesListCounter
        or (retryCount > 0 and _lastScheduledCollectedCount == collectedCount)
    _lastScheduledCollectedCount = collectedCount

    if not isStable and retryCount < 6 then
        PSM.C_Timer.After(0.15, function() ScheduleUpdateWithRetry(retryCount + 1) end)
        return
    end
    _lastScheduledCollectedCount = nil

    PSM.UI:RenderPanel()
    PSM.UI:UpdatePanelTitle()
    PSM.UI:UpdateSortButtonTexts()
end

local function ScheduleUpdate()
    if updateTimer then updateTimer:Cancel() end
    updateTimer = PSM.C_Timer.NewTimer(PSM.Config.UPDATE_DELAY, function()
        if PSM.state.panel and PSM.state.panel:IsVisible() and PSM.state.isStableOpen then
            ScheduleUpdateWithRetry(0)
        end
        updateTimer = nil
    end)
end

local function CancelPendingUpdate()
    if updateTimer then
        updateTimer:Cancel()
        updateTimer = nil
    end
end

--------------------------------------------------------------------------------
-- PET_STABLE_SHOW: collect and render with retry
--------------------------------------------------------------------------------

local _lastShowCollectedCount = nil

local function CollectAndRender(retryCount)
    retryCount = retryCount or 0

    -- Check if data provider is ready (needed for stabled pets)
    local dataProviderReady = false
    if PSM.StableFrame and PSM.StableFrame.StabledPetList and PSM.StableFrame.StabledPetList.ScrollBox then
        local scrollBox = PSM.StableFrame.StabledPetList.ScrollBox
        local dp = scrollBox:GetDataProvider()
        dataProviderReady = dp and true or false
    end

    local collectedCount, expectedCount = PSM.Data:CollectStablePets()
    collectedCount = collectedCount or 0
    expectedCount  = expectedCount  or 0
    local listCounterCount = ParseListCounterCount(GetListCounterText())

    -- dataProvider:GetSize() is not trustworthy -- measured it stuck at a
    -- wrong value across every retry, and separately reporting too-low right
    -- after opening a large stable. A match against the on-screen counter is
    -- treated as immediate proof of completeness; two consecutive identical
    -- readings is the fallback, and hitting the pet cap is proof on its own.
    local isAtCap = collectedCount >= PSM.Config.MAX_STABLE_SLOTS
    local matchesListCounter = listCounterCount ~= nil and collectedCount == listCounterCount
    local isStable = isAtCap or matchesListCounter
        or (retryCount > 0 and _lastShowCollectedCount == collectedCount)
    _lastShowCollectedCount = collectedCount

    if (#PSM.state.stablePets == 0 or not isStable or not dataProviderReady) and retryCount < 8 then
        PSM.C_Timer.After(0.15, function() CollectAndRender(retryCount + 1) end)
        return
    end
    _lastShowCollectedCount = nil

     if #PSM.state.stablePets > 0 and PSM.state.panel then
         PSM.UI:ReinitializeTamerDropdown()
         PSM.UI:SetStableTamerSelection()
         PSM.UI:RenderPanel()
         PSM.UI:UpdatePanelTitle()
         PSM.UI:UpdateSortButtonTexts()
         if PetStableManagementDB.settings.openWithStable ~= false then
             PSM.state.panel:Show()
             PSM.state.panel:Raise()
         end
     end

    if StableFrame then
        if StableFrame.ReleasePetButton and not StableFrame.ReleasePetButton.psm_hooked then
            StableFrame.ReleasePetButton.psm_hooked = true
            hooksecurefunc(StableFrame.ReleasePetButton, "Click", ScheduleUpdate)
        end
        PSM:CreateSaveTeamButtonOnStable()
        PSM:UpdateSaveTeamButtonState()
    end

    if PSM.state.teamsPanel and PSM.state.teamsPanel:IsVisible() then
        PSM.TeamsPanel:RefreshTeamsList()
    end
end

--------------------------------------------------------------------------------
-- EVENT HANDLER
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PET_STABLE_SHOW")
eventFrame:RegisterEvent("PET_STABLE_UPDATE")
eventFrame:RegisterEvent("PET_STABLE_CLOSED")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    PSM.Utils.SafeCall(function()

        if event == "ADDON_LOADED" and arg1 == addonName then
            PSM.Data:LoadSettingsOnly()

             if not PetStableManagementDB.settings.minimapButton then
                 PetStableManagementDB.settings.minimapButton = {
                     hide = false,
                     minimapPos = 220,
                     lock = false,
                 }
             end

             if PetStableManagementDB.settings.openWithStable == nil then
                 PetStableManagementDB.settings.openWithStable = true
             end

             PSM.Minimap:CreateButton()

            if PetStableManagementDB.settings.showFloatingMenu then
                PSM.Menu:Toggle()
            end

            PSM:InitializeOpacity()
            print(PSM.Config.MESSAGES.ADDON_LOADED)

        elseif event == "PET_STABLE_SHOW" then
            PSM.state.isStableOpen = true
            _lastShowCollectedCount = nil

            if not PSM.state.panel then
                PSM.UI:BuildPanel()
            end

            PSM.C_Timer.After(0.1, function() CollectAndRender(0) end)

        elseif event == "PET_STABLE_UPDATE" then
            if PSM.state.isStableOpen then
                ScheduleUpdate()
            end

        elseif event == "PET_STABLE_CLOSED" then
            CancelPendingUpdate()

            if StableFrame then
                if StableFrame.PSM_SaveTeamButton  then StableFrame.PSM_SaveTeamButton:Hide()  end
                if StableFrame.PSM_TeamsListButton then StableFrame.PSM_TeamsListButton:Hide() end
            end

            if PSM.state.panel and PSM.state.panel:IsVisible() then
                PSM.state.panel:Hide()
            end

            -- Snapshot must happen BEFORE isStableOpen is cleared and memory wiped
            if #PSM.state.stablePets > 0 then
                PSM.Data:CreateSnapshot()
            end

            PSM.Data:ClearMemory()
            PSM.Data:ClearUIRows()
            PSM.state.isStableOpen = false
            PSM.state.wasStableSession = true  -- signals next panel open to reset tamer filter

            if PSM.state.teamsPanel and PSM.state.teamsPanel:IsVisible() then
                PSM.TeamsPanel:RefreshTeamsList()
            end

            if PSM.state.teamsPanel and PSM.state.teamsPanel:IsVisible() then
                PSM.TeamsPanel:RefreshTeamsList()
            end

        elseif event == "PLAYER_LOGOUT" then
            CancelPendingUpdate()

            if #PSM.state.stablePets > 0 then
                PSM.Data:SavePersistentData()
            end
            PSM.Data:ClearMemory()
            PSM.Data:ClearUIRows()

        elseif event == "PLAYER_REGEN_DISABLED" then
            -- Hide all open panels on combat entry to avoid protected function calls.
            -- NOTE: CloseAllPanels intentionally skips SettingsPanel (see Broker.lua).
            PSM.Broker:CloseAllPanels()
        end

    end)
end)