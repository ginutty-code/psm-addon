-- ModelsBrowser/ModelRow.lua
-- Model row creation and management for Pet Models Browser

local addonName = "PetStableManagement"
_G.PSM = _G.PSM or {}
local PSM = _G.PSM
PSM.ModelRow = PSM.ModelRow or {}

-- Deliberately NOT captured at file scope. PSM.Config and PSM.RowManager belong to
-- the *core* addon, and this file is in the browser addon, so a file-scope capture
-- reads whatever happens to exist at parse time and fails much later with a
-- misleading stack. That is the exact shape of the ModelRow.lua bug from the
-- LoadOnDemand work. Read them inside the function that needs them.

-- Returns the current scaling factor based on petsPerColumn setting
local function scalingFactor()
    local ppc = PetStableManagementDB.settings.petsPerColumn or PSM.Config.DEFAULT_PETS_PER_COLUMN
    return 5 / ppc
end

-- Creates and returns a font string anchored relative to an anchor frame
local function addFontString(parent, size, color, w)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont("Fonts\\FRIZQT__.TTF", size)
    fs:SetJustifyH("LEFT")
    if color then fs:SetTextColor(unpack(color)) end
    if w then fs:SetWidth(w) end
    return fs
end

--------------------------------------------------------------------------------

function PSM.ModelRow:CreateModelRow(parent)
    local sf = scalingFactor()
    local mcfg = PSM.ModelsPanel.MODELS_CONFIG
    local textW = PSM.Config.TEXT_WIDTH / sf

    local row = PSM.RowManager:CreateBaseRow(parent, {
        useBackdropTemplate = true,
        width  = 432,
        height = mcfg.ROW_HEIGHT,
        modelSize = mcfg.MODEL_SIZE,
    })

    row.model:ClearAllPoints()
    row.model:SetPoint("LEFT", 20, 0)
    row.model:SetWidth(mcfg.MODEL_SIZE)
    row.model:SetHeight(mcfg.MODEL_SIZE)

    row.customElements = {}

    row.nameText = addFontString(row, 10, nil, textW)
    row.nameText:SetPoint("LEFT", row.model, "RIGHT", 15, 15)
    row.nameText:SetWordWrap(true)

    row.infoText = addFontString(row, 8, {0.7, 0.7, 0.7})
    row.infoText:SetPoint("LEFT", row.nameText, "RIGHT", 10, 0)

    -- Note indicator (small dot next to name)
    row.noteIndicator = row:CreateTexture(nil, "OVERLAY")
    row.noteIndicator:SetSize(8, 8)
    row.noteIndicator:SetPoint("LEFT", row.nameText, "RIGHT", 5, 2)
    row.noteIndicator:SetTexture("Interface\\Common\\Icon-NoTick")
    row.noteIndicator:SetVertexColor(0.5, 1, 0.5)
    row.noteIndicator:Hide()

    row.npcTexts = {}
    for i = 1, 4 do
        local npc = addFontString(row, 9, {0.8, 0.8, 0.8}, textW)
        npc:SetWordWrap(true)
        npc:SetPoint("LEFT", row.model, "RIGHT", 15, 10 - i * 12 * sf)
        npc:Hide()
        table.insert(row.customElements, npc)
        table.insert(row.npcTexts, npc)
    end

    table.insert(row.customElements, row.favoriteButton)

    row:SetScript("OnEnter", function(self)
        if not self.displayId then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Display ID: " .. self.displayId)
        if self.familyName then
            GameTooltip:AddLine("Family: " .. self.familyName)
        end
        GameTooltip:Show()
    end)

    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return row
end

--------------------------------------------------------------------------------

-- Builds a display ID's ownership string across characters
local function buildOwnershipData(displayId)
    local seen   = {}  -- [tamer][petKey] dedup
    local counts = {}  -- [tamer] -> count

    for _, pet in ipairs(PSM.state.stablePets) do
        if tonumber(pet.displayID) == displayId then
            local tamer  = pet.tamer or "Unknown"
            local petKey = (pet.petNumber and pet.petNumber ~= 0)
                and tostring(pet.petNumber)
                or  (pet.name or "") .. "_" .. (pet.slotID or "") .. "_" .. (pet.displayID or "")

            seen[tamer] = seen[tamer] or {}
            if not seen[tamer][petKey] then
                seen[tamer][petKey] = true
                counts[tamer] = (counts[tamer] or 0) + 1
            end
        end
    end

    local total, parts = 0, {}
    for tamer, count in pairs(counts) do
        total = total + count
        table.insert(parts, string.format("%d owned by %s", count, tamer))
    end

    return total, table.concat(parts, "; ")
end

--------------------------------------------------------------------------------

function PSM.ModelRow:UpdateItemRow(row, item, index, scale)
    if not item then
        row:Hide()
        return
    end

    scale = scale or scalingFactor()

    local mcfg = PSM.ModelsPanel.MODELS_CONFIG
    row:SetHeight(mcfg.ROW_HEIGHT)
    if row.model then
        row.model:SetWidth(mcfg.MODEL_SIZE)
        row.model:SetHeight(mcfg.MODEL_SIZE)
    end

    if item.itemType ~= "display_with_npcs" then return end

    local displayId   = item.displayId
    local totalOwned, ownershipStr = buildOwnershipData(displayId)
    local npcs        = item.npcs or {}

    PSM.RowManager:UpdateModelDisplay(row, displayId, nil)
    local specName = item.familyName and PSM.Config.FAMILY_TO_SPEC[item.familyName]
    PSM.RowManager:UpdateBackgroundColor(row, false, false, totalOwned > 0, specName)
    PSM.RowManager:UpdateFavoriteButton(row, displayId)

    -- Check if any NPCs for this display have user notes
    local hasUserNote = false
    if npcs and #npcs > 0 then
        for _, npc in ipairs(npcs) do
            local npcId = _G.ModelsData.NpcId[npc]
            if npcId and PSM_UserNotes and PSM_UserNotes[npcId] and PSM_UserNotes[npcId] ~= "" then
                hasUserNote = true
                break
            end
        end
    end
    if hasUserNote and row.noteIndicator then
        row.noteIndicator:Show()
    elseif row.noteIndicator then
        row.noteIndicator:Hide()
    end

    -- Name text
    local nameStr = string.format("Display ID: %d", displayId)
    if totalOwned > 0 then
        nameStr = nameStr .. string.format(" (%s)", ownershipStr)
    end
    row.nameText:SetWidth(PSM.Config.TEXT_WIDTH / scale)
    row.nameText:SetText(nameStr)
    row.nameText:SetTextColor(totalOwned > 0 and 0 or 1, totalOwned > 0 and 1 or 1, totalOwned > 0 and 0 or 1)
    row.nameText:Show()

    if row.infoText then
        row.infoText:Show()
        row.infoText:SetText("")
    end

    -- First NPC line (detailed) + "and N more..." if applicable
    for i = 1, 4 do row.npcTexts[i]:Hide() end

    local totalNpcs = #npcs
    if npcs[1] then
        local first = row.npcTexts[1]
        first:SetText(_G.PSM._modelsDescriptionCache and _G.PSM._modelsDescriptionCache[npcs[1]])
        first:ClearAllPoints()
        first:SetPoint("TOPLEFT", row.nameText, "BOTTOMLEFT", 0, -5)
        first:Show()

        if totalNpcs > 1 then
            local more = row.npcTexts[2]
            more:SetText(string.format("and %d more...", totalNpcs - 1))
            more:ClearAllPoints()
            more:SetPoint("TOPLEFT", first, "BOTTOMLEFT", 0, -5)
            more:Show()
        end
    end

    if row.npcText then row.npcText:Hide() end  -- legacy cleanup

    -- Tooltip
    row.displayId = displayId
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(nameStr)
        GameTooltip:AddLine("Family: " .. (item.familyName or "Unknown"))
        if totalNpcs > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("NPCs:")
            for _, npc in ipairs(npcs) do
                local npcId = _G.ModelsData.NpcId[npc]
                local desc = _G.PSM._modelsDescriptionCache and _G.PSM._modelsDescriptionCache[npc]
                local npcLine = "  " .. (desc or "")
                if npcId and PSM_UserNotes and PSM_UserNotes[npcId] and PSM_UserNotes[npcId] ~= "" then
                    npcLine = npcLine .. " |cff00ff00\226\151\143|r"
                end
                GameTooltip:AddLine(npcLine, 0.8, 0.8, 0.8, true)
            end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff00ff00Click magnifier button for further details.|r", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)

    row:Show()
end

