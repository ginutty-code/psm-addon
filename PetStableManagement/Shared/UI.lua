-- UI.lua
-- Optimized UI components for PetStableManagement with performance improvements

local addonName = "PetStableManagement"

_G.PSM = _G.PSM or {}
local PSM = _G.PSM

PSM.UI = PSM.UI or {}

--------------------------------------------------------------------------------
-- ELVUI COMPATIBILITY
--------------------------------------------------------------------------------

function PSM.UI.ElvUITexture(name)
    local media = ElvUI and ElvUI[1] and ElvUI[1].Media and ElvUI[1].Media.Textures
    return (media and media[name])
        or (name == "PlusButton"  and "Interface\\Buttons\\UI-PlusButton-Up")
        or (name == "MinusButton" and "Interface\\Buttons\\UI-MinusButton-Up")
end

function PSM.UI:ApplyElvUISkin(frame, skinType)
    if not ElvUI or not ElvUI[1] or not ElvUI[1]:GetModule("Skins") then return end
    local S = ElvUI[1]:GetModule("Skins")
    if     skinType == "frame"        then S:HandleFrame(frame, true)
    elseif skinType == "button"
        or skinType == "collapsebutton" then S:HandleButton(frame)
    elseif skinType == "editbox"      then S:HandleEditBox(frame)
    elseif skinType == "closebutton"  then S:HandleCloseButton(frame)
    elseif skinType == "dropdown"     then S:HandleDropDownBox(frame)
    elseif skinType == "checkbox"     then S:HandleCheckBox(frame)
    elseif skinType == "scrollbar"    then S:HandleScrollBar(frame)
    elseif skinType == "resizegrip"   then
        frame:StripTextures()
        frame:SetTemplate()
        frame:SetNormalTexture(ElvUI[1].Media.Textures.ArrowUp or "Interface\\Buttons\\UI-PlusButton-Up")
        frame:GetNormalTexture():SetRotation(-2.35)
    end
end

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

-- Core.lua (loaded first) already builds the authoritative PSM.state with the full field
-- set. This used to unconditionally create its own narrower table and reassign PSM.state
-- to it, silently dropping fields Core.lua had that this list didn't (e.g.
-- selectedExpansions/selectedLocations ended up nil, crashing BuildUnifiedFilterSystem on
-- a fresh character). Only fall back to this literal if PSM.state doesn't exist yet.
PSM.state = PSM.state or {
    panel = nil, scrollFrame = nil, content = nil,
    rows = {}, stablePets = {}, stablePetsSnapshot = {},
    sortBy = nil,
    exoticFilter = false, duplicatesOnlyFilter = false,
    selectedSpecs = {}, selectedFamilies = {}, selectedModelsFamilies = {},
    favoriteModels = {}, favoriteModelsLoaded = false, specList = {}, familyList = {},
    isStableOpen = false, minimapButton = nil, exportFrame = nil,
}
PSM.UI.state = PSM.state  -- backward-compat alias

--------------------------------------------------------------------------------
-- SLOT HELPERS
--------------------------------------------------------------------------------

-- Scan a range of slot numbers and return the first unoccupied one.
local function FindFreeSlot(fromSlot, toSlot)
    local occupied = {}
    for _, p in ipairs(PSM.state.stablePets) do occupied[p.slotID] = true end
    for slot = fromSlot, toSlot do
        if not occupied[slot] then return slot end
    end
end

function PSM.UI:FindDisplacementSlot()
    return FindFreeSlot(2, 5) or FindFreeSlot(7, 205)
end

function PSM.UI:FindAvailableStableSlot()
    return FindFreeSlot(7, 205)
end

--------------------------------------------------------------------------------
-- ROW BUTTONS
--------------------------------------------------------------------------------

function PSM.UI:SetupRowButtons(row, pet)
    if not row or not pet or not pet.slotID or pet.slotID <= 0 then
        if row then
            row.makeActive:Hide(); row.companion:Hide()
            row.stable:Hide();     row.release:Hide()
        end
        return
    end

    local isStableOpen = PSM.state.isStableOpen

    -- Make Active
    row.makeActive:SetScript("OnClick", function()
        if not isStableOpen then
            print(string.format(PSM.Config.MESSAGES.STABLE_MUST_BE_OPEN, "make a pet active"))
            return
        end
        if not C_StableInfo or not C_StableInfo.SetPetSlot then
            print("|cFFFF0000C_StableInfo.SetPetSlot not available.|r")
            return
        end
        PSM.Utils.SafeCall(function()
            local slot1Pet = nil
            for _, p in ipairs(PSM.state.stablePets) do
                if p.slotID == 1 then slot1Pet = p; break end
            end
            if slot1Pet then
                local dispSlot = self:FindDisplacementSlot()
                if dispSlot then
                    C_StableInfo.SetPetSlot(1, dispSlot)
                    PSM.C_Timer.After(0.1, function()
                        C_StableInfo.SetPetSlot(pet.slotID, 1)
                        PSM.C_Timer.After(0.2, function() PSM.UI:UpdatePanel() end)
                    end)
                else
                    print(PSM.Config.MESSAGES.NO_AVAILABLE_SLOTS)
                end
            else
                C_StableInfo.SetPetSlot(pet.slotID, 1)
                PSM.C_Timer.After(0.2, function() PSM.UI:UpdatePanel() end)
            end
        end)
    end)
    if not isStableOpen or (pet.slotID >= 1 and pet.slotID <= 5) then
        row.makeActive:Hide()
    else
        row.makeActive:Show()
    end

    -- Companion
    row.companion:SetScript("OnClick", function()
        if not isStableOpen then
            print(string.format(PSM.Config.MESSAGES.STABLE_MUST_BE_OPEN, "set a pet as companion"))
            return
        end
        if C_StableInfo and C_StableInfo.SetPetSlot then
            C_StableInfo.SetPetSlot(pet.slotID, 6)
            PSM.C_Timer.After(0.2, function() PSM.UI:UpdatePanel() end)
        end
    end)
    if not PSM.Utils:HasAnimalCompanionTalent() or not isStableOpen or pet.slotID == 6 then
        row.companion:Hide()
    else
        row.companion:Show()
    end

    -- Stable
    row.stable:SetScript("OnClick", function()
        if not isStableOpen then
            print(string.format(PSM.Config.MESSAGES.STABLE_MUST_BE_OPEN, "stable a pet"))
            return
        end
        if C_StableInfo and C_StableInfo.SetPetSlot then
            local targetSlot = self:FindAvailableStableSlot()
            if targetSlot then
                C_StableInfo.SetPetSlot(pet.slotID, targetSlot)
                PSM.C_Timer.After(0.2, function() PSM.UI:UpdatePanel() end)
            else
                print(PSM.Config.MESSAGES.NO_STABLE_SLOTS)
            end
        end
    end)
    if isStableOpen and (pet.slotID >= 1 and pet.slotID <= 5) then
        row.stable:Show()
    else
        row.stable:Hide()
    end

    -- Release
    row.release:SetScript("OnClick", function()
        if not (StableFrame and StableFrame.OnPetSelected and StableFrame.ReleasePetButton) then return end

        local function doRelease()
            local onClick = StableFrame.ReleasePetButton:GetScript("OnClick")
            if onClick then
                PSM.Utils.SafeCall(onClick, StableFrame.ReleasePetButton)
                for i = #PSM.state.stablePets, 1, -1 do
                    if PSM.state.stablePets[i].slotID == pet.slotID then
                        table.remove(PSM.state.stablePets, i); break
                    end
                end
                PSM.UI:UpdatePanel()
            end
        end

        if pet.slotID >= 1 and pet.slotID <= 5 then
            if C_StableInfo and C_StableInfo.GetStablePetInfo then
                local info = C_StableInfo.GetStablePetInfo(pet.slotID)
                if info then
                    StableFrame:OnPetSelected(info)
                    PSM.C_Timer.After(0.05, doRelease)
                end
            end
        else
            local list = StableFrame.StabledPetList
            if list and list.ScrollBox then
                local dp = list.ScrollBox:GetDataProvider()
                if dp then
                    local found = nil
                    dp:ForEach(function(node)
                        if found then return end
                        local bp = node:GetData()
                        if bp and (
                            (bp.petNumber and bp.petNumber == pet.petNumber) or
                            (bp.name == pet.name and bp.icon == pet.icon and bp.displayID == pet.displayID)
                        ) then found = bp end
                    end, false)
                    if found then
                        StableFrame:OnPetSelected(found)
                        PSM.C_Timer.After(0.05, doRelease)
                    end
                end
            end
        end
    end)
    if isStableOpen then row.release:Show() else row.release:Hide() end

    -- Move Up / Down
    if isStableOpen and pet.slotID and pet.slotID >= 1 and pet.slotID <= 205 then
        local function setupMoveButton(btn, label, targetSlot, action)
            btn:SetScript("OnClick", action)
            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(label .. " (to slot " .. targetSlot .. ")")
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end

        setupMoveButton(row.moveUp,   "Move Up",   pet.slotID - 1, function() PSM.Reorder:MovePetUp(pet)   end)
        setupMoveButton(row.moveDown, "Move Down", pet.slotID + 1, function() PSM.Reorder:MovePetDown(pet) end)

        if pet.slotID > 1   then row.moveUp:Show()   else row.moveUp:Hide()   end
        if pet.slotID < 205 then row.moveDown:Show() else row.moveDown:Hide() end
    else
        row.moveUp:Hide(); row.moveDown:Hide()
    end

    -- Stack visible action buttons vertically
    local yOffset = -30
    for _, btn in ipairs({row.makeActive, row.companion, row.stable, row.release}) do
        if btn:IsShown() then
            btn:ClearAllPoints()
            btn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, yOffset)
            yOffset = yOffset - 25
        end
    end
end

--------------------------------------------------------------------------------
-- RENDER CACHE
--------------------------------------------------------------------------------

function PSM.UI:CreateRenderCache()
    PSM._renderCache        = nil
    PSM._renderDebounceTimer= nil
    PSM._lastLayoutWidth    = nil
    PSM._lastLayoutHeight   = nil
end

function PSM.UI:GenerateCacheKey()
    local searchText  = PSM.state.panel and PSM.state.panel.searchBox:GetText() or ""
    local searchLower = searchText ~= "" and PSM.Utils:NormalizeSearchText(searchText) or ""
    return string.format("%d_%s_%s_%s_%s_%s_%s_%s",
        #PSM.state.stablePets,
        searchLower,
        tostring(PSM.state.exoticFilter),
        tostring(PSM.state.duplicatesOnlyFilter),
        PSM.Utils:GetTableHash(PSM.state.selectedSpecs),
        PSM.Utils:GetTableHash(PSM.state.selectedFamilies),
        PSM.Utils:GetTableHash(PSM.state.selectedTamers),
        tostring(PSM.state.sortBy)
    )
end

--------------------------------------------------------------------------------
-- RENDERING
--------------------------------------------------------------------------------

function PSM.UI:RenderPanel(preserveScroll)
    if not PSM.state.panel or not PSM.state.content then
        print(PSM.Config.MESSAGES.PANEL_SHOW_FAILED)
        return
    end
    if PSM._renderDebounceTimer then PSM._renderDebounceTimer:Cancel() end
    PSM._renderDebounceTimer = PSM.C_Timer.NewTimer(PSM.Config.RENDER_DELAY or 0.01, function()
        self:_RenderPanelImmediate(preserveScroll)
    end)
end

function PSM.UI:_RenderPanelImmediate(preserveScroll)
    if not PSM.state.panel or not PSM.state.content then return end

    local cacheKey = self:GenerateCacheKey()
    if PSM._renderCache and PSM._renderCache.key == cacheKey and PSM._renderCache.timestamp then
        if GetTime() - PSM._renderCache.timestamp < 0.1 then
            self:_ApplyCachedRender(PSM._renderCache.data, preserveScroll)
            return
        end
    end

    local renderData = self:_CalculateRenderData()
    PSM._renderCache = { key = cacheKey, timestamp = GetTime(), data = renderData }
    self:_ApplyCachedRender(renderData, preserveScroll)
end

function PSM.UI:_CalculateRenderData()
    local searchText  = PSM.state.panel.searchBox:GetText() or ""
    local searchLower = searchText ~= "" and PSM.Utils:NormalizeSearchText(searchText) or ""

    -- Duplicate groups across ALL pets, account-wide (every character's tamer)
    local allGroups = {}
    for _, pet in ipairs(PSM.state.stablePets) do
        local key = PSM.Utils:GetPetDuplicateKey(pet)
        allGroups[key] = allGroups[key] or {}
        table.insert(allGroups[key], pet)
    end

    -- Filter flags
    local hasSpecsFilter  = next(PSM.state.selectedSpecs)    ~= nil
    local hasFamilyFilter = next(PSM.state.selectedFamilies) ~= nil
    local hasTamerFilter  = next(PSM.state.selectedTamers)   ~= nil
    local hasSearch       = searchLower ~= ""
    local needsDupes      = PSM.state.duplicatesOnlyFilter == true
    local needsNoDupes    = PSM.state.duplicatesOnlyFilter == "inverted"

    local duplicateKeys = {}
    if needsDupes or needsNoDupes then
        for key, group in pairs(allGroups) do
            if #group > 1 then duplicateKeys[key] = true end
        end
    end

    -- Filter pass
    local filteredPets  = {}
    local filteredCount = 0
    for _, pet in ipairs(PSM.state.stablePets) do
        local skip = false

        if     PSM.state.exoticFilter == true     and not pet.isExotic                       then skip = true
        elseif PSM.state.exoticFilter == "inverted" and pet.isExotic                          then skip = true
        elseif hasSpecsFilter  and not PSM.state.selectedSpecs[pet.specName]                 then skip = true
        elseif hasFamilyFilter and not PSM.state.selectedFamilies[pet.familyName]            then skip = true
        elseif hasTamerFilter  and not PSM.state.selectedTamers[pet.tamer]                   then skip = true
        elseif needsDupes      and not duplicateKeys[PSM.Utils:GetPetDuplicateKey(pet)]      then skip = true
        elseif needsNoDupes    and     duplicateKeys[PSM.Utils:GetPetDuplicateKey(pet)]      then skip = true
        end

        if not skip and hasSearch then
            local match = false
            for _, field in ipairs({pet.name, pet.familyName, pet.specName, tostring(pet.displayID or ""), pet.tamer}) do
                if field and tostring(field):lower():find(searchLower, 1, true) then match = true; break end
            end
            if not match and pet.abilities then
                local abs = pet.abilities
                if abs.family or abs.spec or abs.pet or abs.unknown then
                    for _, cat in ipairs({"family", "spec", "pet", "unknown"}) do
                        if abs[cat] then
                            for _, ability in ipairs(abs[cat]) do
                                if tostring(ability):lower():find(searchLower, 1, true) then match = true; break end
                            end
                        end
                        if match then break end
                    end
                else
                    for _, ability in ipairs(abs) do
                        if tostring(ability):lower():find(searchLower, 1, true) then match = true; break end
                    end
                end
            end
            if not match then skip = true end
        end

        if not skip then
            filteredCount = filteredCount + 1
            filteredPets[filteredCount] = pet
        end
    end

    -- Sort
    if PSM.state.sortBy == "model" then
        table.sort(filteredPets, function(a,b) return (a.displayID or 0) < (b.displayID or 0) end)
    elseif PSM.state.sortBy == "slot" then
        table.sort(filteredPets, function(a,b) return (a.slotID or 0) < (b.slotID or 0) end)
    elseif PSM.state.sortBy == "family" then
        table.sort(filteredPets, function(a,b)
            local af = a.familyName or ""
            local bf = b.familyName or ""
            if af == bf then
                return (a.displayID or 0) < (b.displayID or 0)
            end
            return af < bf
        end)
    elseif PSM.state.sortBy == "spec" then
        table.sort(filteredPets, function(a,b)
            local as = a.specName or ""
            local bs = b.specName or ""
            if as == bs then
                return (a.displayID or 0) < (b.displayID or 0)
            end
            return as < bs
        end)
    elseif PSM.state.sortBy == "tamer" then
        table.sort(filteredPets, function(a,b)
            local at = a.tamer or ""
            local bt = b.tamer or ""
            if at == bt then
                return (a.displayID or 0) < (b.displayID or 0)
            end
            return at < bt
        end)
    end

    -- Duplicate stats from filtered set
    local filteredGroups = {}
    for _, pet in ipairs(filteredPets) do
        local key = PSM.Utils:GetPetDuplicateKey(pet)
        filteredGroups[key] = filteredGroups[key] or {}
        table.insert(filteredGroups[key], pet)
    end

    -- Account-wide: a model is a "same-char" duplicate if any single tamer owns
    -- 2+ copies of it, and a "cross-char" duplicate if 2+ different tamers own
    -- it at all -- independent of which character is currently viewing the panel.
    local sameCharPets, sameCharGroups   = 0, 0
    local crossCharPets, crossCharGroups = 0, 0
    for _, group in pairs(filteredGroups) do
        if #group > 1 then
            local perTamer, tamerCount, hasSameCharDup = {}, 0, false
            for _, pet in ipairs(group) do
                local count = (perTamer[pet.tamer] or 0) + 1
                perTamer[pet.tamer] = count
                if count == 1 then tamerCount = tamerCount + 1 end
                if count > 1  then hasSameCharDup = true end
            end
            if hasSameCharDup then
                sameCharGroups = sameCharGroups + 1
                sameCharPets   = sameCharPets   + #group
            end
            if tamerCount > 1 then
                crossCharGroups = crossCharGroups + 1
                crossCharPets   = crossCharPets   + #group
            end
        end
    end

    -- Layout
    local contentWidth = PSM.state.content:GetWidth()
    if not contentWidth or contentWidth <= 0 then contentWidth = 500 end
    local colSpacing = 2
    local colCount   = math.max(1, math.floor((contentWidth + colSpacing) / (500 + colSpacing)))
    local colWidth   = math.max(500, math.floor((contentWidth - colSpacing * (colCount-1)) / colCount))

    return {
        filteredPets          = filteredPets,
        filteredCount         = filteredCount,
        duplicatePets         = sameCharPets + crossCharPets,
        duplicateGroups       = sameCharGroups + crossCharGroups,
        sameCharDuplicatePets = sameCharPets,
        sameCharDuplicateGroups = sameCharGroups,
        crossCharDuplicatePets  = crossCharPets,
        crossCharDuplicateGroups= crossCharGroups,
        colCount  = colCount,
        colWidth  = colWidth,
        rowTotal  = math.ceil(filteredCount / colCount),
        allGroups = allGroups,
    }
end

function PSM.UI:_ApplyCachedRender(renderData, preserveScroll)
    if PSM._scrollLock then preserveScroll = true end
    PSM.state.currentRenderData = renderData

    -- Stats text
    local statsText = string.format("Showing: %d pets", renderData.filteredCount)
    local parts = {}
    if renderData.sameCharDuplicatePets  > 0 then table.insert(parts, string.format("Same-char: %d models (%d pets)",  renderData.sameCharDuplicateGroups,  renderData.sameCharDuplicatePets))  end
    if renderData.crossCharDuplicatePets > 0 then table.insert(parts, string.format("Cross-char: %d models (%d pets)", renderData.crossCharDuplicateGroups, renderData.crossCharDuplicatePets)) end
    if #parts > 0 then statsText = statsText .. " | Duplicates: " .. table.concat(parts, "; ") end
    PSM.state.panel.statsText:SetText(statsText)

    -- Content height
    local rowHeight = (PSM.state.panelViewMode == "grid") and PSM.Config.GRID_ROW_HEIGHT or PSM.Config.ROW_HEIGHT
    PSM.state.content:SetHeight(math.max(renderData.rowTotal * rowHeight + 10, 100))

    if not preserveScroll and PSM.state.panelViewMode == "grid" then
        PSM.state.panel.gridScrollOffset = 0
    end

    if PSM.state.scrollFrame.UpdateScrollChildRect then
        PSM.state.scrollFrame:UpdateScrollChildRect()
    end
    if not preserveScroll and PSM.state.scrollFrame.ScrollBar then
        PSM.state.scrollFrame.ScrollBar:SetValue(0)
    end

    self:UpdateVisibleRows()
end

function PSM.UI:UpdateVisibleRows()
    local renderData = PSM.state.currentRenderData
    if not renderData or not PSM.state.panel then return end

    if PSM.state.panelViewMode == "grid" then
        if PSM.UI.GridView then PSM.UI.GridView:UpdateVisibleRows() end
        return
    end
    if PSM.state.panelViewMode == "grouped" then
        if PSM.UI.GroupedView then PSM.UI.GroupedView:UpdateVisibleRows() end
        return
    end

    -- List view
    local panel = PSM.state.panel
    if not panel.modelRows then
        panel.modelRows = {}
        for i = 1, 50 do
            local row = PSM.RowManager:EnsureRow(i, PSM.state.content, {
                useBackdropTemplate = true,
                width     = PSM.Config.DEFAULT_ROW_WIDTH,
                height    = PSM.Config.ROW_HEIGHT,
                modelSize = 110,
                showMagnifyButton = true,
                showTeamButtons   = true,
            })
            if row then table.insert(panel.modelRows, row); row:Hide() end
        end
    end

    if renderData.filteredCount == 0 then
        for _, row in ipairs(panel.modelRows) do row:Hide() end
        return
    end

    local contentWidth = PSM.state.content:GetWidth()
    if not contentWidth or contentWidth <= 0 then contentWidth = 500 end
    -- Reuse layout values already computed in renderData
    local colCount   = renderData.colCount
    local colWidth   = renderData.colWidth
    local colSpacing = 2
    local rowTotal   = renderData.rowTotal

    local sfHeight       = PSM.state.scrollFrame:GetHeight() or 500
    local visibleRows    = math.ceil(sfHeight / PSM.Config.ROW_HEIGHT) + 2
    local startRow       = math.max(1, panel.scrollOffset + 1)
    local endRow         = math.min(rowTotal, startRow + visibleRows - 1)
    local startIndex     = (startRow - 1) * colCount + 1
    local endIndex       = math.min(renderData.filteredCount, endRow * colCount)

    for _, row in ipairs(panel.modelRows) do row:Hide() end

    local rowIndex = 1
    for dataIndex = startIndex, endIndex do
        if rowIndex > #panel.modelRows then break end
        local pet = renderData.filteredPets[dataIndex]
        local row = panel.modelRows[rowIndex]
        if pet and row then
            local col    = (dataIndex - 1) % colCount
            local rowIdx = math.floor((dataIndex - 1) / colCount) + 1

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", PSM.state.content, "TOPLEFT",
                4 + col * (colWidth + colSpacing),
                -(rowIdx - 1) * PSM.Config.ROW_HEIGHT)
            row:SetWidth(colWidth)

            local leftW   = math.floor(colWidth / 2)
            local rightW  = colWidth - leftW
            local btnSpace= PSM.Config.BUTTON_WIDTH + 20
            local fixedSp = 2 + PSM.Config.MODEL_SIZE + 6

            if row.text then row.text:SetWidth(leftW - fixedSp) end
            if row.abilitiesHeader then
                row.abilitiesHeader:SetWidth(rightW - btnSpace)
                if colCount > 1 then
                    row.abilitiesHeader:ClearAllPoints()
                    row.abilitiesHeader:SetPoint("TOPLEFT", row.text, "TOPRIGHT", 5, 10)
                end
            end
            if row.abilitiesList then row.abilitiesList:SetWidth(rightW - btnSpace) end

PSM.state.allGroups = renderData.allGroups

            PSM.UI.Row:UpdateRow(row, pet, renderData.allGroups)
             
            if row.separator then row.separator:Show() end
            row:Show()
            rowIndex = rowIndex + 1
        end
    end
end

--------------------------------------------------------------------------------
-- PANEL MANAGEMENT
--------------------------------------------------------------------------------

-- Shared data-loading logic for UpdatePanel / UpdatePanelWithSnapshot
local function EnsurePetData(collectSnapshot)
    if PSM.state.isStableOpen then
        if collectSnapshot then
            PSM.Data:ClearMemory()
            PSM.Data:CollectStablePets()
            PSM.Data:CreateSnapshot()
        elseif #PSM.state.stablePets == 0 then
            PSM.Data:CollectStablePets()
        end
        return true
    else
        if #PSM.state.stablePets == 0 then
            return PSM.Data:LoadPersistentDataForDisplay()
        end
        return true
    end
end

function PSM.UI:UpdatePanel(showIfHidden)
    if not PSM.state.panel then self:BuildPanel() end

    if not EnsurePetData(false) then
        print("|cFFFF0000No owned pets data available! Please visit a Stable Master.|r")
        return
    end

    self:RenderPanel()
    self:UpdatePanelTitle()

    if PSM.state.panel and (showIfHidden == true or PSM.state.panel:IsVisible()) then
        PSM.state.panel:Show()
    end
end

function PSM.UI:UpdatePanelWithSnapshot()
    if not PSM.state.panel then self:BuildPanel() end

    if not EnsurePetData(true) then
        print(PSM.Config.MESSAGES.NO_SNAPSHOT)
        return
    end

    self:RenderPanel()
    self:UpdatePanelTitle()

    if PSM.state.panel then PSM.state.panel:Show() end
end

function PSM.UI:UpdatePanelTitle()
    if not PSM.state.panel or not PSM.state.panel.title then return end

    if PSM.state.isStableOpen then
        PSM.state.panel.title:SetText("Pet Stable Management (Live)")
        PSM.state.panel.title:SetTextColor(unpack(PSM.Config.COLORS.PRIMARY))
        return
    end

    local text, color = "Pet Stable Management", {0.6, 0.8, 1}
    if #PSM.state.stablePets > 0 or
       (PetStableManagementDB and PetStableManagementDB.snapshotData and #PetStableManagementDB.snapshotData > 0) then
        local formatted = PSM.Data:GetFormattedTimestamp()
        local suffix = formatted ~= "Never"
            and (" (using data from " .. formatted .. ")")
            or  " (using preserved data)"
        text = text .. suffix
    else
        text  = text .. " (no saved data available)"
        color = {1, 0.7, 0.7}
    end
    PSM.state.panel.title:SetText(text)
    PSM.state.panel.title:SetTextColor(unpack(color))
end

function PSM.UI:CreateOptimizedSizeChangedHandler()
    if not PSM.state.panel then return end
    PSM.state.panel:SetScript("OnSizeChanged", function(self, width, height)
        local wDiff = math.abs((PSM._lastLayoutWidth  or 0) - width)
        local hDiff = math.abs((PSM._lastLayoutHeight or 0) - height)
        if wDiff < 10 and hDiff < 10 then return end

        PSM._lastLayoutWidth  = width
        PSM._lastLayoutHeight = height
        if not PSM.state.scrollFrame or not PSM.state.content then return end

        PSM.state.scrollFrame:SetWidth(width - 40)
        PSM.state.content:SetWidth(PSM.state.scrollFrame:GetWidth())
        PSM.state.content:ClearAllPoints()
        PSM.state.content:SetPoint("TOPLEFT")
        PSM.state.content:SetPoint("TOPRIGHT")

        PSM._renderCache = nil
        PSM.state.panel.isResizing = true
        PSM.C_Timer.After(0.05, function()
            PSM.state.panel.isResizing = false
            if PSM.UI and PSM.UI.RenderPanel then PSM.UI:RenderPanel(true) end
        end)
    end)
end

PSM.UI:CreateRenderCache()

--------------------------------------------------------------------------------
-- PET TEAMS INTEGRATION
--------------------------------------------------------------------------------

local function RefreshTeamsPanel()
    if PSM.TeamsPanel and PSM.TeamsPanel.RefreshTeamsList then
        PSM.TeamsPanel:RefreshTeamsList()
    end
end

function PSM.UI:HandleSaveTeamClick()
    if not PSM.state.isStableOpen then
        print("|cFFFF8800PetStableManagement: You must be at a Stable Master to save a team.|r")
        return
    end

    local currentSlots, err = PSM.Teams:GetCurrentSlots()
    if not currentSlots then
        print("|cFFFF0000PetStableManagement: " .. (err or "Failed to capture current slots") .. "|r")
        return
    end

    local hasPet = false
    for slot = 1, 6 do if currentSlots[slot] then hasPet = true; break end end
    if not hasPet then
        print("|cFFFF8800PetStableManagement: No pets in slots 1-6 to save.|r")
        return
    end

    local activeTeamId = PSM.Teams:GetActiveTeamId()
    local activeTeam   = activeTeamId and PSM.Teams:GetTeamById(activeTeamId)

    if activeTeam then
        if PSM.Teams:HasActiveTeamChanged() then
            PSM.TeamDialogs:ShowSaveTeamDialog({
                existingTeamId   = activeTeamId,
                existingTeamName = activeTeam.name,
                onUpdate = function()
                    local ok, updateErr = PSM.Teams:UpdateTeam(activeTeamId)
                    if ok then RefreshTeamsPanel()
                    else print("|cFFFF0000PetStableManagement: " .. (updateErr or "Failed to update team") .. "|r") end
                end,
                onSaveNew = function(name)
                    local tid, saveErr = PSM.Teams:SaveTeam(name)
                    if tid then RefreshTeamsPanel()
                    else print("|cFFFF0000PetStableManagement: " .. (saveErr or "Failed to save team") .. "|r") end
                end,
            })
        else
            print("|cFF00FF00PetStableManagement: Team '" .. activeTeam.name .. "' is already up to date.|r")
        end
    else
        PSM.TeamDialogs:ShowNameInputDialog({
            title       = "Save New Team",
            description = "Enter a name for your pet team:",
            onConfirm   = function(name)
                local tid, saveErr = PSM.Teams:SaveTeam(name)
                if tid then RefreshTeamsPanel()
                else print("|cFFFF0000PetStableManagement: " .. (saveErr or "Failed to save team") .. "|r") end
            end,
        })
    end
end

function PSM.UI:UpdateSortButtonTexts()
    local panel = PSM.state.panel
    if not panel or not panel.sortDrop then return end

    -- Update sort dropdown text based on current sort state
    local sortLabels = {
        slot   = "Sorted by Slot",
        model  = "Sorted by Model",
        family = "Sorted by Family",
        spec   = "Sorted by Spec",
        tamer  = "Sorted by Tamer",
    }
    local sortText = sortLabels[PSM.state.sortBy] or "Sort by"
    UIDropDownMenu_SetText(panel.sortDrop, sortText)
end

function PSM.UI:UpdateSaveTeamButtonState()
    if not PSM.state.panel or not PSM.state.panel.saveTeamButton then return end
    local btn = PSM.state.panel.saveTeamButton
    if PSM.state.isStableOpen then btn:Enable(); btn:SetAlpha(1.0)
    else btn:Disable(); btn:SetAlpha(0.5) end
end