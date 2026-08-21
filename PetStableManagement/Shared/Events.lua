-- Events.lua
-- Event handling for PetStableManagement

-- `addonName` is used below to match ADDON_LOADED's arg1. Taking it from the client's
-- varargs rather than a hardcoded string is strictly better: it is the real folder
-- name, so it cannot drift from the .toc.
local addonName, ns = ...

--------------------------------------------------------------------------------
-- DEBOUNCED UPDATE
--------------------------------------------------------------------------------

local updateTimer = nil
local _lastScheduledCollectedCount = nil

-- Blizzard's on-screen "X/Y" pet-count label -- more reliable than
-- dataProvider:GetSize(). Used as a fast-path signal below, with the
-- stability check as fallback if it's ever missing/unparseable.
local function GetListCounterText()
    local frame   = ns.GetStableFrame()
    local counter = frame and frame.StabledPetList
                 and frame.StabledPetList.ListCounter
                 and frame.StabledPetList.ListCounter.Count
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

    local collectedCount = ns.Data:CollectStablePets() or 0
    local listCounterCount = ParseListCounterCount(GetListCounterText())

    -- The stable's own expected count isn't trustworthy (see CollectAndRender below); a
    -- match against the on-screen counter is treated as immediate proof of
    -- completeness, with two consecutive identical readings as the fallback.
    local isAtCap = collectedCount >= ns.Config.MAX_STABLE_SLOTS
    local matchesListCounter = listCounterCount ~= nil and collectedCount == listCounterCount
    local isStable = isAtCap or matchesListCounter
        or (retryCount > 0 and _lastScheduledCollectedCount == collectedCount)
    _lastScheduledCollectedCount = collectedCount

    if not isStable and retryCount < 6 then
        ns.C_Timer.After(0.15, function() ScheduleUpdateWithRetry(retryCount + 1) end)
        return
    end
    _lastScheduledCollectedCount = nil

    ns.UI:RenderPanel()
    ns.UI:UpdatePanelTitle()
    ns.UI:UpdateSortButtonTexts()
end

local function ScheduleUpdate()
    if updateTimer then updateTimer:Cancel() end
    updateTimer = ns.C_Timer.NewTimer(ns.Config.UPDATE_DELAY, function()
        if ns.state.panel and ns.state.panel:IsVisible() and ns.state.isStableOpen then
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
    local stableFrame = ns.GetStableFrame()
    local dataProviderReady = false
    if stableFrame and stableFrame.StabledPetList and stableFrame.StabledPetList.ScrollBox then
        local scrollBox = stableFrame.StabledPetList.ScrollBox
        local dp = scrollBox:GetDataProvider()
        dataProviderReady = dp and true or false
    end

    local collectedCount = ns.Data:CollectStablePets() or 0
    local listCounterCount = ParseListCounterCount(GetListCounterText())

    -- dataProvider:GetSize() is not trustworthy -- measured it stuck at a
    -- wrong value across every retry, and separately reporting too-low right
    -- after opening a large stable. A match against the on-screen counter is
    -- treated as immediate proof of completeness; two consecutive identical
    -- readings is the fallback, and hitting the pet cap is proof on its own.
    local isAtCap = collectedCount >= ns.Config.MAX_STABLE_SLOTS
    local matchesListCounter = listCounterCount ~= nil and collectedCount == listCounterCount
    local isStable = isAtCap or matchesListCounter
        or (retryCount > 0 and _lastShowCollectedCount == collectedCount)
    _lastShowCollectedCount = collectedCount

    if (#ns.state.stablePets == 0 or not isStable or not dataProviderReady) and retryCount < 8 then
        ns.C_Timer.After(0.15, function() CollectAndRender(retryCount + 1) end)
        return
    end
    _lastShowCollectedCount = nil

     if #ns.state.stablePets > 0 and ns.state.panel then
         ns.UI:ReinitializeTamerDropdown()
         ns.UI:SetStableTamerSelection()
         ns.UI:RenderPanel()
         ns.UI:UpdatePanelTitle()
         ns.UI:UpdateSortButtonTexts()
         if PetStableManagementDB.settings.openWithStable ~= false then
             ns.state.panel:Show()
             ns.state.panel:Raise()
         end
     end

    if StableFrame then
        if StableFrame.ReleasePetButton and not StableFrame.ReleasePetButton.psm_hooked then
            StableFrame.ReleasePetButton.psm_hooked = true
            hooksecurefunc(StableFrame.ReleasePetButton, "Click", ScheduleUpdate)
        end
        ns:CreateSaveTeamButtonOnStable()
        ns:UpdateSaveTeamButtonState()
    end

    if ns.state.teamsPanel and ns.state.teamsPanel:IsVisible() then
        ns.TeamsPanel:RefreshTeamsList()
    end
end

--------------------------------------------------------------------------------
-- EVENT HANDLER
--------------------------------------------------------------------------------

-- A handler holder, not a widget, so it stays out of the kit -- but PSM.CreateFrame
-- rather than the raw global, which is the rule for core: it is Core.lua's alias and the
-- headless tests can stub it.
local eventFrame = ns.CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PET_STABLE_SHOW")
eventFrame:RegisterEvent("PET_STABLE_UPDATE")
eventFrame:RegisterEvent("PET_STABLE_CLOSED")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    ns.Utils.SafeCall(function()

        if event == "ADDON_LOADED" and arg1 == addonName then
            ns.Data:LoadSettingsOnly()
            ns.PetGroups:PruneCollapsedGroups()

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

             ns.Minimap:CreateButton()

            if PetStableManagementDB.settings.showFloatingMenu then
                ns.Menu:Toggle()
            end

            ns:InitializeOpacity()
            print(ns.L("Pet Stable Management loaded. Use /psm or /petstable or click the minimap button to toggle the panel."))

        elseif event == "PET_STABLE_SHOW" then
            ns.state.isStableOpen = true
            _lastShowCollectedCount = nil

            if not ns.state.panel then
                ns.UI:BuildPanel()
            end

            ns.C_Timer.After(0.1, function() CollectAndRender(0) end)

        elseif event == "PET_STABLE_UPDATE" then
            if ns.state.isStableOpen then
                ScheduleUpdate()
            end

        elseif event == "PET_STABLE_CLOSED" then
            CancelPendingUpdate()

            if StableFrame then
                if StableFrame.PSM_SaveTeamButton  then StableFrame.PSM_SaveTeamButton:Hide()  end
                if StableFrame.PSM_TeamsListButton then StableFrame.PSM_TeamsListButton:Hide() end
            end

            if ns.state.panel and ns.state.panel:IsVisible() then
                ns.state.panel:Hide()
            end

            -- Snapshot must happen BEFORE isStableOpen is cleared and memory wiped
            if #ns.state.stablePets > 0 then
                ns.Data:CreateSnapshot()
            end

            ns.Data:ClearMemory()
            ns.Data:ClearUIRows()
            ns.state.isStableOpen = false
            ns.state.wasStableSession = true  -- signals next panel open to reset tamer filter

            if ns.state.teamsPanel and ns.state.teamsPanel:IsVisible() then
                ns.TeamsPanel:RefreshTeamsList()
            end

        elseif event == "PLAYER_LOGOUT" then
            CancelPendingUpdate()

            if #ns.state.stablePets > 0 then
                ns.Data:SavePersistentData()
            end
            ns.Data:ClearMemory()
            ns.Data:ClearUIRows()

        elseif event == "PLAYER_REGEN_DISABLED" then
            -- Hide all open panels on combat entry to avoid protected function calls.
            -- NOTE: CloseAllPanels intentionally skips SettingsPanel (see Broker.lua).
            ns.Broker:CloseAllPanels()
        end

    end)
end)