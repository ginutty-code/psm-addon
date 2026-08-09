-- OwnedPets/Row.lua
-- Row management for PetStableManagement

local addonName = "PetStableManagement"

-- Initialize global namespace
_G.PSM = _G.PSM or {}
local PSM = _G.PSM

PSM.UI.Row = {}

-- Ordered action buttons: { key, label }
local ACTION_BUTTONS = {
    { key = "makeActive", label = "Make Active" },
    { key = "companion",  label = "Companion"   },
    { key = "stable",     label = "Stable"      },
    { key = "release",    label = "Release"      },
}

-- Ability groups in display order: { key, color, label }
local ABILITY_GROUPS = {
    { key = "spec",    color = "|cFFFFD700", label = "[Spec]"   },
    { key = "family",  color = "|cFF40FF40", label = "[Family]" },
    { key = "pet",     color = "|cFF40FFFF", label = "[Pet]"    },
    { key = "unknown", color = "|cFFAAAAAA", label = "[Other]"  },
}

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------

local function CreateActionButton(parent, label)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(PSM.Config.BUTTON_WIDTH, PSM.Config.BUTTON_HEIGHT)
    btn:SetText(label)
    btn:SetNormalFontObject("GameFontNormalSmall")
    btn:Hide()
    PSM.UI:ApplyElvUISkin(btn, "button")
    return btn
end

local function BuildAbilitiesText(abilities)
    local parts = {}
    local hasAbilities = false

    if abilities.family or abilities.spec or abilities.pet or abilities.unknown then
        -- Grouped format
        for _, group in ipairs(ABILITY_GROUPS) do
            local list = abilities[group.key]
            if list and #list > 0 then
                parts[#parts + 1] = group.color .. group.label .. "|r\n"
                for _, ability in ipairs(list) do
                    parts[#parts + 1] = "  • " .. ability .. "\n"
                end
                hasAbilities = true
            end
        end
    else
        -- Flat list fallback
        for _, ability in ipairs(abilities) do
            local name = type(ability) == "table" and ability.name or tostring(ability)
            parts[#parts + 1] = "• " .. name .. "\n"
            hasAbilities = true
        end
    end

    return table.concat(parts), hasAbilities
end

local function BuildPetText(pet)
    local exoticLabel = pet.isExotic and " |cffff8800[Exotic]|r" or ""
    local familyText  = pet.familyName and ("Family: " .. pet.familyName) or "Family: ?"
    local specText    = pet.specName   and ("Spec: "   .. pet.specName)   or "Spec: ?"
    local tamerText   = pet.tamer      and ("\nOwned by: " .. pet.tamer)  or ""

    return string.format(
        "Slot %d: %s%s\nDisplayID: %d\n%s\n%s%s",
        pet.slotID    or 0,
        pet.name      or "?",
        exoticLabel,
        pet.displayID or 0,
        familyText,
        specText,
        tamerText
    )
end

-- ---------------------------------------------------------------------------
-- Row element initialization
-- ---------------------------------------------------------------------------

function PSM.UI.Row:EnsureRowElements(row)
    if not row or row._ownedPetsInitialized then return end
    row._ownedPetsInitialized = true

    row.text:SetWordWrap(true)
    row.text:SetPoint("LEFT", row.model, "RIGHT", 20, -2)

    row.customElements = row.customElements or {}

    -- Abilities header
    row.abilitiesHeader = row:CreateFontString(nil, "OVERLAY")
    row.abilitiesHeader:SetFont("Fonts\\FRIZQT__.TTF", 10)
    row.abilitiesHeader:SetPoint("TOPLEFT", row.text, "TOPRIGHT", 20, 10)
    row.abilitiesHeader:SetText("|cFFFFD700Abilities:|r")
    row.abilitiesHeader:SetJustifyH("LEFT")
    row.abilitiesHeader:SetJustifyV("MIDDLE")
    row.abilitiesHeader:SetWidth(PSM.Config.ABILITIES_WIDTH)
    row.abilitiesHeader:Hide()
    table.insert(row.customElements, row.abilitiesHeader)

    -- Abilities list
    row.abilitiesList = row:CreateFontString(nil, "OVERLAY")
    row.abilitiesList:SetFont("Fonts\\FRIZQT__.TTF", 9)
    row.abilitiesList:SetPoint("TOPLEFT", row.abilitiesHeader, "BOTTOMLEFT", 0, -2)
    row.abilitiesList:SetWidth(PSM.Config.ABILITIES_WIDTH)
    row.abilitiesList:SetHeight(200)
    row.abilitiesList:SetJustifyH("LEFT")
    row.abilitiesList:SetJustifyV("TOP")
    row.abilitiesList:SetWordWrap(true)
    row.abilitiesList:SetNonSpaceWrap(true)
    row.abilitiesList:Hide()
    table.insert(row.customElements, row.abilitiesList)

    -- Action buttons
    for _, def in ipairs(ACTION_BUTTONS) do
        row[def.key] = CreateActionButton(row, def.label)
        table.insert(row.customElements, row[def.key])
    end

    -- Move Up button
    row.moveUp = CreateFrame("Button", nil, row)
    row.moveUp:SetSize(24, 24)
    row.moveUp:SetPoint("LEFT", row.text, "LEFT", 0, 0)
    row.moveUp:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
    row.moveUp:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Highlight")
    row.moveUp:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Down")
    row.moveUp:Hide()
    table.insert(row.customElements, row.moveUp)

    -- Move Down button
    row.moveDown = CreateFrame("Button", nil, row)
    row.moveDown:SetSize(24, 24)
    row.moveDown:SetPoint("LEFT", row.moveUp, "RIGHT", 2, 0)
    row.moveDown:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
    row.moveDown:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight")
    row.moveDown:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down")
    row.moveDown:Hide()
    table.insert(row.customElements, row.moveDown)
end

-- ---------------------------------------------------------------------------
-- Row update / hide
-- ---------------------------------------------------------------------------

function PSM.UI.Row:UpdateRow(row, pet, groups)
    if not row or not pet then return end

    self:EnsureRowElements(row)

    PSM.RowManager:UpdateModelDisplay(row, pet.displayID, pet.icon, pet)

    row.text:SetText(BuildPetText(pet))

    -- Duplicate highlighting
    local isSameCharDuplicate, isCrossCharDuplicate = PSM.RowManager:CheckDuplicates(pet, groups)
    PSM.RowManager:UpdateBackgroundColor(row, isSameCharDuplicate, isCrossCharDuplicate, false, pet.specName)

    -- Abilities
    local abilities = type(pet.abilities) == "table" and pet.abilities or {}
    local abilitiesText, hasAbilities = BuildAbilitiesText(abilities)
    row.abilitiesList:SetText(abilitiesText)
    row.abilitiesHeader:SetShown(hasAbilities)
    row.abilitiesList:SetShown(hasAbilities)

    -- Reposition move buttons
    row.moveUp:ClearAllPoints()
    row.moveUp:SetPoint("TOPLEFT", row.text, "TOPLEFT", -5, 25)

    PSM.UI:SetupRowButtons(row, pet)

    if PSM.DragDrop then
        PSM.DragDrop:SetupRowDragDrop(row, pet)
        PSM.DragDrop:SetupModelDragDrop(row.model, pet, row)
    end

    row:Show()
end

function PSM.UI.Row:HideRow(i)
    local row = PSM.state.rows[i]
    if not row then return end

    PSM.RowManager:HideRow(row)

    -- Hide all OwnedPets-specific elements via the registry
    if row.customElements then
        for _, el in ipairs(row.customElements) do
            el:Hide()
        end
    end

    PSM.RowManager:HideFavoriteButton(row)
end