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
local COLLECT_MAX_RETRIES = 2  -- 1 initial + 2 retries = 3 total attempts

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

-- Same completeness check as CollectAndRender: on-screen counter is the
-- source of truth, cap is a fallback. No "consecutive identical" heuristic --
-- a stuck API should surface, not be hidden.
local function ScheduleUpdateWithRetry(retryCount)
    retryCount = retryCount or 0

    local collectedCount = ns.Data:CollectStablePets() or 0
    local listCounterCount = ParseListCounterCount(GetListCounterText())

    local isComplete = (listCounterCount ~= nil and collectedCount == listCounterCount)
                       or collectedCount >= ns.Config.MAX_STABLE_SLOTS

    -- Retry only if the counter disagrees with what we collected; if the
    -- counter can't be read but we have pets, trust the C_StableInfo sweep.
    if not isComplete and retryCount < COLLECT_MAX_RETRIES
        and not (listCounterCount == nil and collectedCount > 0) then
        ns.C_Timer.After(0.15, function() ScheduleUpdateWithRetry(retryCount + 1) end)
        return
    end

    -- No warning here: this path fires on every PET_STABLE_UPDATE, and a warning
    -- on each would be noisy. The initial open (CollectAndRender) is where the
    -- user needs to know.
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

local function CollectAndRender(retryCount)
    retryCount = retryCount or 0

    local collectedCount = ns.Data:CollectStablePets() or 0
    local listCounterCount = ParseListCounterCount(GetListCounterText())

    -- The on-screen counter is the source of truth: if it says we should have N
    -- pets and we have N, we're done. Hitting the cap is also proof of
    -- completeness. No "consecutive identical" fallback -- if the API is stuck
    -- returning 1-2 pets, we want to notice that, not paper over it.
    local isComplete = (listCounterCount ~= nil and collectedCount == listCounterCount)
                       or collectedCount >= ns.Config.MAX_STABLE_SLOTS

    -- Retry only if the counter disagrees with what we collected; if the counter
    -- can't be read but we have pets, trust the C_StableInfo sweep and proceed.
    if not isComplete and retryCount < COLLECT_MAX_RETRIES
        and not (listCounterCount == nil and collectedCount > 0) then
        ns.C_Timer.After(0.15, function() CollectAndRender(retryCount + 1) end)
        return
    end

    -- After all retries, if we still don't match the on-screen counter, warn in
    -- chat rather than silently rendering a partial stable.
    if listCounterCount and collectedCount < listCounterCount then
        ns.Utils:Msg("WARNING", ns.L(
            "Unsuccessful pet data collection: collected %d pets data instead of %d. The API was lazy this time - try talking to the Stable Master again.",
            collectedCount, listCounterCount))
    end

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
            ns.Utils:Msg("SUCCESS", ns.L("Loaded. Use /psm or /petstable or click the minimap button to toggle the panel."))

        elseif event == "PET_STABLE_SHOW" then
            ns.state.isStableOpen = true

            if not ns.state.panel then
                ns.UI:BuildPanel()
            end

            -- Clear Blizzard's stable frame search box. A stale search string
            -- from a previous session is the most likely cause of "only 1-2 pets
            -- collected": it filters both the ScrollBox data provider AND the
            -- on-screen counter, so the collection thinks it's complete against
            -- a filtered total. PSM's own panel filters are separate and handled
            -- by their own dropdowns.
            local stableFrame = ns.GetStableFrame()
            if stableFrame and stableFrame.StabledPetList then
                local searchBox = stableFrame.StabledPetList.SearchBox
                if searchBox then
                    ns.Utils.SafeCall(function()
                        if searchBox.SetText then
                            searchBox:SetText("")
                        elseif searchBox.EditBox and searchBox.EditBox.SetText then
                            searchBox.EditBox:SetText("")
                        end
                    end)
                end
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