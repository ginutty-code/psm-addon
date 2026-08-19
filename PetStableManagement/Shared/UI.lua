-- UI.lua
-- Optimized UI components for PetStableManagement with performance improvements

local _, ns = ...

ns.UI = ns.UI or {}

-- The `PSM.UI:ApplyElvUISkin` / `PSM.UI.ElvUITexture` shims are gone. They forwarded to
-- PSM.Skin so pre-kit call sites kept working during A6; the last of the 86 migrated with
-- OwnedPets/Row.lua. Skinning is PSM.Skin.Apply, and almost always PSM.Widgets doing it
-- for you.

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

-- Core.lua (loaded first) already builds the authoritative PSM.state with the full field
-- set. This used to unconditionally create its own narrower table and reassign PSM.state
-- to it, silently dropping fields Core.lua had that this list didn't (e.g.
-- selectedExpansions/selectedLocations ended up nil, crashing BuildUnifiedFilterSystem on
-- a fresh character). Only fall back to this literal if PSM.state doesn't exist yet.
ns.state = ns.state or {
    panel = nil, scrollFrame = nil, content = nil,
    rows = {}, stablePets = {}, stablePetsSnapshot = {},
    sortBy = nil,
    exoticFilter = false, duplicatesOnlyFilter = false,
    selectedSpecs = {}, selectedFamilies = {}, selectedModelsFamilies = {},
    favoriteModels = {}, favoriteModelsLoaded = false, specList = {}, familyList = {},
    isStableOpen = false, minimapButton = nil, exportFrame = nil,
}
ns.UI.state = ns.state  -- backward-compat alias

--------------------------------------------------------------------------------
-- SLOT HELPERS
--------------------------------------------------------------------------------

-- Scan a range of slot numbers and return the first unoccupied one.
local function FindFreeSlot(fromSlot, toSlot)
    local occupied = {}
    for _, p in ipairs(ns.state.stablePets) do occupied[p.slotID] = true end
    for slot = fromSlot, toSlot do
        if not occupied[slot] then return slot end
    end
end

function ns.UI:FindDisplacementSlot()
    return FindFreeSlot(2, 5) or FindFreeSlot(7, 205)
end

function ns.UI:FindAvailableStableSlot()
    return FindFreeSlot(7, 205)
end

--------------------------------------------------------------------------------
-- ROW BUTTONS
--------------------------------------------------------------------------------

function ns.UI:SetupRowButtons(row, pet)
    if not row or not pet or not pet.slotID or pet.slotID <= 0 then
        if row then
            row.makeActive:Hide(); row.companion:Hide()
            row.stable:Hide();     row.release:Hide()
        end
        return
    end

    local isStableOpen = ns.state.isStableOpen

    -- Make Active
    row.makeActive:SetScript("OnClick", function()
        if not C_StableInfo or not C_StableInfo.SetPetSlot then
            print(ns.L("C_StableInfo.SetPetSlot not available."))
            return
        end
        ns.Utils.SafeCall(function()
            local slot1Pet = nil
            for _, p in ipairs(ns.state.stablePets) do
                if p.slotID == 1 then slot1Pet = p; break end
            end
            if slot1Pet then
                local dispSlot = self:FindDisplacementSlot()
                if dispSlot then
                    C_StableInfo.SetPetSlot(1, dispSlot)
                    ns.C_Timer.After(0.1, function()
                        C_StableInfo.SetPetSlot(pet.slotID, 1)
                        ns.C_Timer.After(0.2, function() ns.UI:UpdatePanel() end)
                    end)
                else
                    print(ns.L("No available slots to displace pet from slot 1!"))
                end
            else
                C_StableInfo.SetPetSlot(pet.slotID, 1)
                ns.C_Timer.After(0.2, function() ns.UI:UpdatePanel() end)
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
        if C_StableInfo and C_StableInfo.SetPetSlot then
            C_StableInfo.SetPetSlot(pet.slotID, 6)
            ns.C_Timer.After(0.2, function() ns.UI:UpdatePanel() end)
        end
    end)
    if not ns.Utils:HasAnimalCompanionTalent() or not isStableOpen or pet.slotID == 6 then
        row.companion:Hide()
    else
        row.companion:Show()
    end

    -- Stable
    row.stable:SetScript("OnClick", function()
        if C_StableInfo and C_StableInfo.SetPetSlot then
            local targetSlot = self:FindAvailableStableSlot()
            if targetSlot then
                C_StableInfo.SetPetSlot(pet.slotID, targetSlot)
                ns.C_Timer.After(0.2, function() ns.UI:UpdatePanel() end)
            else
                print(ns.L("No available stable slots found! (Max 205 slots)"))
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
                ns.Utils.SafeCall(onClick, StableFrame.ReleasePetButton)
                for i = #ns.state.stablePets, 1, -1 do
                    if ns.state.stablePets[i].slotID == pet.slotID then
                        table.remove(ns.state.stablePets, i); break
                    end
                end
                ns.UI:UpdatePanel()
            end
        end

        if pet.slotID >= 1 and pet.slotID <= 5 then
            if C_StableInfo and C_StableInfo.GetStablePetInfo then
                local info = C_StableInfo.GetStablePetInfo(pet.slotID)
                if info then
                    StableFrame:OnPetSelected(info)
                    ns.C_Timer.After(0.05, doRelease)
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
                        ns.C_Timer.After(0.05, doRelease)
                    end
                end
            end
        end
    end)
    if isStableOpen then row.release:Show() else row.release:Hide() end

    -- Move Up / Down
    if isStableOpen and pet.slotID and pet.slotID >= 1 and pet.slotID <= 205 then
        -- Re-attached on every row update, because the target slot is part of the text
        -- and rows are recycled across pets. PSM.Tooltip.Attach replaces both scripts, so
        -- re-attaching is how it is meant to be used -- unlike the raw pair, which left a
        -- stale OnLeave behind if only OnEnter was reassigned.
        local function setupMoveButton(btn, label, targetSlot, action)
            btn:SetScript("OnClick", action)
            ns.Tooltip.Attach(btn, {
                anchor = "ANCHOR_RIGHT",
                title  = label .. " (to slot " .. targetSlot .. ")",
            })
        end

        setupMoveButton(row.moveUp,   ns.L("Move Up"),   pet.slotID - 1, function() ns.Reorder:MovePetUp(pet)   end)
        setupMoveButton(row.moveDown, ns.L("Move Down"), pet.slotID + 1, function() ns.Reorder:MovePetDown(pet) end)

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

-- Every input to `_CalculateRenderData`, derived by reading that function rather than by
-- trusting the cache key it replaces -- which is how `panelWidth` was found missing.
local RENDER_SLICES = {
    "ownedPets", "ownedSearch", "ownedSpecs", "ownedFamilies", "ownedTamers",
    "ownedExotic", "ownedDuplicates", "ownedSort", "panelWidth",
}

local renderResults   -- the selector; built on first use, dropped by CreateRenderCache

-- Drops the computed render data and stops any pending render.
--
-- **`:Cancel()` is the point, not `= nil`** -- the same defect `ModelsDataLoader:ReleaseCache`
-- was fixed for, in core rather than the browser. A C_Timer handle belongs to the timer
-- system, so clearing the field drops the reference and the timer still fires: closing the
-- panel inside the debounce window left a render scheduled into the panel just torn down,
-- recomputing and repopulating the cache the teardown had just cleared.
function ns.UI:CreateRenderCache()
    if ns._renderDebounceTimer then ns._renderDebounceTimer:Cancel() end
    ns._renderDebounceTimer = nil
    renderResults          = nil
end

--------------------------------------------------------------------------------
-- RENDERING
--------------------------------------------------------------------------------

function ns.UI:RenderPanel(preserveScroll)
    if not ns.state.panel or not ns.state.content then
        print(ns.L("Panel failed to show!"))
        return
    end
    if ns._renderDebounceTimer then ns._renderDebounceTimer:Cancel() end
    ns._renderDebounceTimer = ns.C_Timer.NewTimer(ns.Config.RENDER_DELAY or 0.01, function()
        self:_RenderPanelImmediate(preserveScroll)
    end)
end

function ns.UI:_RenderPanelImmediate(preserveScroll)
    if not ns.state.panel or not ns.state.content then return end

    -- **The 0.1s expiry goes with the key, and the plan's corollary is why it could.** It
    -- bounded staleness from inputs the key did not model; `panelWidth` was the last of
    -- those, so there is nothing left for a timeout to catch.
    --
    -- `_ApplyCachedRender` runs on every call, hit or miss. That matters: view mode, pet
    -- groups and collapse state are read *there* and in UpdateVisibleRows, never in
    -- `_CalculateRenderData` -- which is why the eight hand-written `_renderCache = nil`
    -- calls in GroupedView and GridView were never necessary. They forced a recompute of
    -- data that could not have changed.
    renderResults = renderResults or ns.Store:Selector(RENDER_SLICES, function()
        return ns.UI:_CalculateRenderData()
    end)

    self:_ApplyCachedRender(renderResults(), preserveScroll)
end

function ns.UI:_CalculateRenderData()
    local searchText  = ns.state.panel.searchBox:GetSearchText() or ""
    local searchLower = searchText ~= "" and ns.Utils:NormalizeSearchText(searchText) or ""

    -- Duplicate groups across ALL pets, account-wide (every character's tamer)
    local allGroups = {}
    for _, pet in ipairs(ns.state.stablePets) do
        local key = ns.Utils:GetPetDuplicateKey(pet)
        allGroups[key] = allGroups[key] or {}
        table.insert(allGroups[key], pet)
    end

    -- Filter flags
    local hasSpecsFilter  = next(ns.state.selectedSpecs)    ~= nil
    local hasFamilyFilter = next(ns.state.selectedFamilies) ~= nil
    local hasTamerFilter  = next(ns.state.selectedTamers)   ~= nil
    local hasSearch       = searchLower ~= ""
    local needsDupes      = ns.state.duplicatesOnlyFilter == true
    local needsNoDupes    = ns.state.duplicatesOnlyFilter == "inverted"

    local duplicateKeys = {}
    if needsDupes or needsNoDupes then
        for key, group in pairs(allGroups) do
            if #group > 1 then duplicateKeys[key] = true end
        end
    end

    -- Filter pass
    local filteredPets  = {}
    local filteredCount = 0
    for _, pet in ipairs(ns.state.stablePets) do
        local skip = false

        if     ns.state.exoticFilter == true     and not pet.isExotic                       then skip = true
        elseif ns.state.exoticFilter == "inverted" and pet.isExotic                          then skip = true
        elseif hasSpecsFilter  and not ns.state.selectedSpecs[pet.specName]                 then skip = true
        elseif hasFamilyFilter and not ns.state.selectedFamilies[pet.familyName]            then skip = true
        elseif hasTamerFilter  and not ns.state.selectedTamers[pet.tamer]                   then skip = true
        elseif needsDupes      and not duplicateKeys[ns.Utils:GetPetDuplicateKey(pet)]      then skip = true
        elseif needsNoDupes    and     duplicateKeys[ns.Utils:GetPetDuplicateKey(pet)]      then skip = true
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
    if ns.state.sortBy == "model" then
        table.sort(filteredPets, function(a,b) return (a.displayID or 0) < (b.displayID or 0) end)
    elseif ns.state.sortBy == "slot" then
        table.sort(filteredPets, function(a,b) return (a.slotID or 0) < (b.slotID or 0) end)
    elseif ns.state.sortBy == "family" then
        table.sort(filteredPets, function(a,b)
            local af = a.familyName or ""
            local bf = b.familyName or ""
            if af == bf then
                return (a.displayID or 0) < (b.displayID or 0)
            end
            return af < bf
        end)
    elseif ns.state.sortBy == "spec" then
        table.sort(filteredPets, function(a,b)
            local as = a.specName or ""
            local bs = b.specName or ""
            if as == bs then
                return (a.displayID or 0) < (b.displayID or 0)
            end
            return as < bs
        end)
    elseif ns.state.sortBy == "tamer" then
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
        local key = ns.Utils:GetPetDuplicateKey(pet)
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
    local contentWidth = ns.state.content:GetWidth()
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

function ns.UI:_ApplyCachedRender(renderData, preserveScroll)
    if ns._scrollLock then preserveScroll = true end
    ns.state.currentRenderData = renderData

    -- Stats text
    local statsText = ns.L("Showing: %d pets", renderData.filteredCount)
    local parts = {}
    if renderData.sameCharDuplicatePets  > 0 then table.insert(parts, ns.L("Same-char: %d models (%d pets)",  renderData.sameCharDuplicateGroups,  renderData.sameCharDuplicatePets))  end
    if renderData.crossCharDuplicatePets > 0 then table.insert(parts, ns.L("Cross-char: %d models (%d pets)", renderData.crossCharDuplicateGroups, renderData.crossCharDuplicatePets)) end
    if #parts > 0 then statsText = statsText .. " | Duplicates: " .. table.concat(parts, "; ") end
    ns.state.panel.statsText:SetText(statsText)

    -- Content height
    local rowHeight = (ns.state.panelViewMode == "grid") and ns.Config.GRID_ROW_HEIGHT or ns.Config.ROW_HEIGHT
    ns.state.content:SetHeight(math.max(renderData.rowTotal * rowHeight + 10, 100))

    if not preserveScroll and ns.state.panelViewMode == "grid" then
        ns.state.panel.gridScrollOffset = 0
    end

    if ns.state.scrollFrame.UpdateScrollChildRect then
        ns.state.scrollFrame:UpdateScrollChildRect()
    end
    if not preserveScroll and ns.state.scrollFrame.ScrollBar then
        ns.state.scrollFrame.ScrollBar:SetValue(0)
    end
    -- The content just changed height; a scroll left past the new end shows nothing.
    self:ClampScrollIntoRange(ns.state.scrollFrame, ns.state.content)

    self:UpdateVisibleRows()
end

-- Keep the scroll frame inside the range its content can actually fill.
--
-- Content height shrinks on almost every resize, because the column count is derived
-- from panel width and fewer rows are needed to hold the same pets. A frame left
-- scrolled past the new end then displays the region *below* the last row: every row
-- renders, in the right place, and not one of them is in view. The panel looks
-- completely empty.
--
-- This is the resize blind spot, and it is why it survives in all three views. It is not
-- a per-view indexing bug — GroupedView shares none of the other views' offset
-- bookkeeping and blanks identically. It is the one scroll frame they share being left
-- outside its own range.
--
-- The resize handler restored the scrollbar only `if maxScroll > 0`, which is backwards:
-- `maxScroll == 0` means the content now fits, and that is exactly the case that must
-- force the scroll back to the top. Nothing else corrects it, which is why the panel
-- stayed blank until scrolled by hand — and why it only ever happened away from the top,
-- the one position that is already in range.
--
-- Call this after any content:SetHeight. Returns the (possibly corrected) scroll.
function ns.UI:ClampScrollIntoRange(scrollFrame, content)
    if not scrollFrame or not content then return 0 end

    local maxScroll = math.max(0, (content:GetHeight() or 0) - (scrollFrame:GetHeight() or 0))
    local current   = scrollFrame:GetVerticalScroll() or 0
    local target    = math.max(0, math.min(current, maxScroll))

    -- Only act on a real discrepancy: SetValue re-enters through the scrollbar hook,
    -- and sub-pixel churn there would schedule a render on every frame of a drag.
    if math.abs(target - current) > 0.5 then
        scrollFrame:SetVerticalScroll(target)
        if scrollFrame.ScrollBar then scrollFrame.ScrollBar:SetValue(target) end
    end
    return target
end

-- Which row sits at the top of the scroll window, derived from where the frame is
-- *actually* scrolled to, then clamped to a list that may just have got shorter.
--
-- `panel.scrollOffset` and `panel.gridScrollOffset` are caches, written only by the
-- scrollbar's OnValueChanged hook. A resize can leave either one describing a scroll
-- position the frame no longer has: the column count is derived from panel width, so
-- content height changes under it, and the resize handler restores the scrollbar only
-- when `maxScroll > 0`. Two distinct failures follow, and the resize blind spot has
-- been both of them at different times:
--
--   * offset past the end of a shortened list -> startIndex > endIndex, the render loop
--     never executes, every row stays hidden;
--   * offset merely *disagreeing* with the frame -> rows render for the cached window
--     and are positioned at absolute content coordinates outside the displayed one. The
--     loop reports drawing them and the panel looks completely empty.
--
-- The second is why clamping alone was not enough, and why the top of the list is
-- immune either way: at offset 0 the cached and displayed windows always agree.
--
-- GroupedView has always read GetVerticalScroll() directly and is the one view never
-- reported blank. This makes list and grid agree with it: the displayed position is the
-- single source of truth, and the cached field is a consequence of it, not an input.
--
-- Floor, not round, in both views: this answers "which row is at the top of the window",
-- and grid's own snap-to-row logic settles the scrollbar on an exact multiple anyway.
function ns.UI:GetScrollRowOffset(rowHeight, rowTotal)
    local scrollFrame = ns.state.scrollFrame
    local scroll      = scrollFrame and scrollFrame:GetVerticalScroll() or 0
    local offset      = math.floor((scroll or 0) / math.max(1, rowHeight or 1))
    return math.max(0, math.min(offset, math.max(0, (rowTotal or 0) - 1)))
end

function ns.UI:UpdateVisibleRows()
    local renderData = ns.state.currentRenderData
    if not renderData or not ns.state.panel then return end

    if ns.state.panelViewMode == "grid" then
        if ns.UI.GridView then ns.UI.GridView:UpdateVisibleRows() end
        return
    end
    if ns.state.panelViewMode == "grouped" then
        if ns.UI.GroupedView then ns.UI.GroupedView:UpdateVisibleRows() end
        return
    end

    -- List view
    local panel = ns.state.panel
    if not panel.modelRows then
        panel.modelRows = {}
        for i = 1, 50 do
            local row = ns.RowManager:EnsureRow(i, ns.state.content, {
                useBackdropTemplate = true,
                width     = ns.Config.DEFAULT_ROW_WIDTH,
                height    = ns.Config.ROW_HEIGHT,
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

    -- Reuse layout values already computed in renderData
    local colCount   = renderData.colCount
    local colWidth   = renderData.colWidth
    local colSpacing = 2
    local rowTotal   = renderData.rowTotal

    local sfHeight       = ns.state.scrollFrame:GetHeight() or 500
    local visibleRows    = math.ceil(sfHeight / ns.Config.ROW_HEIGHT) + 2
    panel.scrollOffset   = self:GetScrollRowOffset(ns.Config.ROW_HEIGHT, rowTotal)
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
            row:SetPoint("TOPLEFT", ns.state.content, "TOPLEFT",
                4 + col * (colWidth + colSpacing),
                -(rowIdx - 1) * ns.Config.ROW_HEIGHT)
            row:SetWidth(colWidth)

            local leftW   = math.floor(colWidth / 2)
            local rightW  = colWidth - leftW
            local btnSpace= ns.Theme.CONTROL.BUTTON_W.M + 20
            local fixedSp = 2 + ns.Config.MODEL_SIZE + 6

            if row.text then row.text:SetWidth(leftW - fixedSp) end
            if row.abilitiesHeader then
                row.abilitiesHeader:SetWidth(rightW - btnSpace)
                if colCount > 1 then
                    row.abilitiesHeader:ClearAllPoints()
                    row.abilitiesHeader:SetPoint("TOPLEFT", row.text, "TOPRIGHT", 5, 10)
                end
            end
            if row.abilitiesList then row.abilitiesList:SetWidth(rightW - btnSpace) end

ns.state.allGroups = renderData.allGroups

            ns.UI.Row:UpdateRow(row, pet, renderData.allGroups)
             
            if row.separator then row.separator:Show() end
            row:Show()
            rowIndex = rowIndex + 1
        end
    end
end

--------------------------------------------------------------------------------
-- PANEL MANAGEMENT
--------------------------------------------------------------------------------

-- Shared data-loading logic for UpdatePanel
local function EnsurePetData(collectSnapshot)
    if ns.state.isStableOpen then
        if collectSnapshot then
            ns.Data:ClearMemory()
            ns.Data:CollectStablePets()
            ns.Data:CreateSnapshot()
        elseif #ns.state.stablePets == 0 then
            ns.Data:CollectStablePets()
        end
        return true
    else
        if #ns.state.stablePets == 0 then
            return ns.Data:LoadPersistentDataForDisplay()
        end
        return true
    end
end

function ns.UI:UpdatePanel(showIfHidden)
    if not ns.state.panel then self:BuildPanel() end

    if not EnsurePetData(false) then
        print(ns.L("No owned pets data available! Please visit a Stable Master."))
        return
    end

    self:RenderPanel()
    self:UpdatePanelTitle()

    if ns.state.panel and (showIfHidden == true or ns.state.panel:IsVisible()) then
        ns.state.panel:Show()
    end
end

function ns.UI:UpdatePanelTitle()
    if not ns.state.panel or not ns.state.panel.title then return end

    if ns.state.isStableOpen then
        ns.state.panel.title:SetText(ns.L("Pet Stable Management (Live)"))
        ns.state.panel.title:SetTextColor(unpack(ns.Config.COLORS.PRIMARY))
        return
    end

    local text, color = ns.L("Pet Stable Management"), {0.6, 0.8, 1}
    if #ns.state.stablePets > 0 or
       (PetStableManagementDB and PetStableManagementDB.snapshotData and #PetStableManagementDB.snapshotData > 0) then
        local formatted = ns.Data:GetFormattedTimestamp()
        local suffix = formatted ~= "Never"
            and (" (using data from " .. formatted .. ")")
            or  " (using preserved data)"
        text = text .. suffix
    else
        text  = text .. " (no saved data available)"
        color = {1, 0.7, 0.7}
    end
    ns.state.panel.title:SetText(text)
    ns.state.panel.title:SetTextColor(unpack(color))
end

ns.UI:CreateRenderCache()

--------------------------------------------------------------------------------
-- PET TEAMS INTEGRATION
--------------------------------------------------------------------------------

local function RefreshTeamsPanel()
    if ns.TeamsPanel and ns.TeamsPanel.RefreshTeamsList then
        ns.TeamsPanel:RefreshTeamsList()
    end
end

function ns.UI:HandleSaveTeamClick()
    if not ns.state.isStableOpen then
        print(ns.L("You must be at a Stable Master to save a team."))
        return
    end

    local currentSlots, err = ns.Teams:GetCurrentSlots()
    if not currentSlots then
        print("|cFFFF0000PetStableManagement: " .. (err or ns.L("Failed to capture current slots")) .. "|r")
        return
    end

    local hasPet = false
    for slot = 1, 6 do if currentSlots[slot] then hasPet = true; break end end
    if not hasPet then
        print(ns.L("No pets in slots 1-6 to save."))
        return
    end

    local activeTeamId = ns.Teams:GetActiveTeamId()
    local activeTeam   = activeTeamId and ns.Teams:GetTeamById(activeTeamId)

    if activeTeam then
        if ns.Teams:HasActiveTeamChanged() then
            ns.Dialogs:ShowSaveTeamDialog({
                existingTeamId   = activeTeamId,
                existingTeamName = activeTeam.name,
                onUpdate = function()
                    local ok, updateErr = ns.Teams:UpdateTeam(activeTeamId)
                    if ok then RefreshTeamsPanel()
                    else print("|cFFFF0000PetStableManagement: " .. (updateErr or ns.L("Failed to update team")) .. "|r") end
                end,
                onSaveNew = function(name)
                    local tid, saveErr = ns.Teams:SaveTeam(name)
                    if tid then RefreshTeamsPanel()
                    else print("|cFFFF0000PetStableManagement: " .. (saveErr or ns.L("Failed to save team")) .. "|r") end
                end,
            })
        else
            print(ns.L("Team '%s' is already up to date.", activeTeam.name))
        end
    else
        ns.Dialogs:ShowNameInputDialog({
            title       = ns.L("Save New Team"),
            description = ns.L("Enter a name for your pet team:"),
            onConfirm   = function(name)
                local tid, saveErr = ns.Teams:SaveTeam(name)
                if tid then RefreshTeamsPanel()
                else print("|cFFFF0000PetStableManagement: " .. (saveErr or ns.L("Failed to save team")) .. "|r") end
            end,
        })
    end
end

