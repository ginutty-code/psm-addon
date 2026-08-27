-- OwnedPets/Row.lua
-- Row management for PetStableManagement

-- Initialize global namespace
local _, ns = ...

ns.UI.Row = {}

-- Ordered action buttons: { key, label }
local ACTION_BUTTONS = {
    { key = "makeActive", label = ns.L("Make Active") },
    { key = "companion",  label = ns.L("Companion")   },
    { key = "stable",     label = ns.L("Stable")      },
    { key = "release",    label = ns.L("Release")     },
}

-- Ability groups come from PSM.PetTooltip: this renders them as a block of text
-- rather than as tooltip lines, but it is the same four buckets in the same order
-- with the same colours, and they used to drift apart when both files owned a copy.

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------

local function CreateActionButton(parent, label)
    return ns.Widgets.Button(parent, {
        width      = ns.Theme.CONTROL.BUTTON_W.M,
        text       = label,
        fontObject = "GameFontNormalSmall",
        hidden     = true,
    })
end

local function BuildAbilitiesText(abilities)
    local parts = {}
    local hasAbilities = false

    if ns.PetTooltip.IsBucketed(abilities) then
        -- Grouped format
        for _, group in ipairs(ns.PetTooltip.ABILITY_BUCKETS) do
            local list = abilities[group.key]
            if list and #list > 0 then
                parts[#parts + 1] = group.prefix .. "\n"
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
    local exoticLabel = pet.isExotic and ns.L(" [Exotic]") or ""
    local familyText  = ns.L("Family: %s", pet.familyName or "?")
    local specText    = ns.L("Spec: %s", pet.specName or "?")
    local tamerText   = pet.tamer      and ("\n" .. ns.L("Owned by: %s", pet.tamer)) or ""

    return ns.L("Slot %d: %s%s\nDisplayID: %d\n%s\n%s%s",
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

function ns.UI.Row:EnsureRowElements(row)
    if not row or row._ownedPetsInitialized then return end
    row._ownedPetsInitialized = true

    row.text:SetWordWrap(true)
    row.text:SetPoint("LEFT", row.model, "RIGHT", 20, -2)

    row.customElements = row.customElements or {}

    local Widgets = ns.Widgets
    local Theme   = ns.Theme

    -- Abilities header
    row.abilitiesHeader = Widgets.Label(row, {
        fontSize = Theme.SIZE.SMALL,
        text     = ns.L("Abilities:"),
        justify  = "LEFT",
        justifyV = "MIDDLE",
        width    = ns.Config.ABILITIES_WIDTH,
        hidden   = true,
        point    = { "TOPLEFT", row.text, "TOPRIGHT", 20, 10 },
    })
    table.insert(row.customElements, row.abilitiesHeader)

    -- Abilities list
    row.abilitiesList = Widgets.Label(row, {
        fontSize     = Theme.SIZE.TINY,
        justify      = "LEFT",
        justifyV     = "TOP",
        wordWrap     = true,
        nonSpaceWrap = true,
        size         = { ns.Config.ABILITIES_WIDTH, 200 },
        hidden       = true,
        point        = { "TOPLEFT", row.abilitiesHeader, "BOTTOMLEFT", 0, -2 },
    })
    table.insert(row.customElements, row.abilitiesList)

    -- Action buttons
    for _, def in ipairs(ACTION_BUTTONS) do
        row[def.key] = CreateActionButton(row, def.label)
        table.insert(row.customElements, row[def.key])
    end

    -- Reorder arrows. IconButton rather than Button because ElvUI's HandleButton strips
    -- exactly the kind of bare texture these are made of -- which is why IconButton is the
    -- one factory that does not skin by default.
    --
    -- The `reorderup`/`reorderdown` skins are the deliberate exception: under ElvUI they
    -- hand the button to its own next/prev treatment. Without ElvUI the skin is a no-op
    -- and the texture below is what shows.
    --
    -- The dropdown arrow. Despite living under ChatFrame\, this is the texture
    -- UIDropDownMenuTemplate puts on its button, so the reorder arrows are literally the
    -- same glyph as every dropdown in the addon rather than merely a similar one.
    --
    -- It went through two worse choices first. UI-ScrollBar-ScrollUpButton/DownButton are
    -- scrollbar *buttons* -- mostly bevel and frame around a small glyph -- which needed
    -- 24px to stay readable while ElvUI's replacement art looked best at 16, so the size
    -- had to branch on the skin. UI-MicroStream-Yellow fixed the legibility and removed
    -- the branch, but was only a lookalike.
    --
    -- One texture serves both directions: it points *down*, so `flip` mirrors it
    -- vertically for the up arrow. That is the only thing separating the two -- if they
    -- ever render inverted, move that key to the other row; there is no second place to
    -- check.
    local ARROW = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-%s"
    local ARROWS = {
        { key = "moveUp",   skin = "reorderup",   flip = true },
        { key = "moveDown", skin = "reorderdown"              },
    }

    -- Blizzard's dropdown-arrow size. Under ElvUI the skin resizes these on its own, the
    -- same way it resizes every dropdown's arrow -- no branch here. See
    -- Theme.CONTROL.ROW_ARROW.
    local side = Theme.CONTROL.ROW_ARROW
    local previous
    for _, arrow in ipairs(ARROWS) do
        row[arrow.key] = Widgets.IconButton(row, {
            size      = { side, side },
            texture   = ARROW:format("Up"),
            -- Real pushed art, unlike the bare triangle this replaced: that had a single
            -- glyph, so a pushed texture would have been identical to the normal one and
            -- clicking showed no feedback at all.
            pushed    = ARROW:format("Down"),
            -- Its own texture as the highlight: SetHighlightTexture blends additively, so
            -- it brightens on hover without needing separate art.
            highlight = ARROW:format("Up"),
            texCoord  = arrow.flip and { 0, 1, 1, 0 } or nil,
            skin      = arrow.skin,
            hidden    = true,
            point     = previous
                and { "LEFT", previous, "RIGHT", 2, 0 }
                 or { "LEFT", row.text, "LEFT",  0, 0 },
        })
        table.insert(row.customElements, row[arrow.key])
        previous = row[arrow.key]
    end
end

-- ---------------------------------------------------------------------------
-- Row update / hide
-- ---------------------------------------------------------------------------

function ns.UI.Row:UpdateRow(row, pet, groups)
    if not row or not pet then return end

    self:EnsureRowElements(row)

    ns.RowManager:UpdateModelDisplay(row, pet.displayID, pet.icon, pet)
    ns.RowManager:UpdateFavoriteButton(row, pet.displayID)

    row.text:SetText(BuildPetText(pet))

    -- Duplicate highlighting
    local isSameCharDuplicate, isCrossCharDuplicate = ns.RowManager:CheckDuplicates(pet, groups)
    ns.RowManager:UpdateBackgroundColor(row, isSameCharDuplicate, isCrossCharDuplicate, false, pet.specName)

    -- Abilities
    local abilities = type(pet.abilities) == "table" and pet.abilities or {}
    local abilitiesText, hasAbilities = BuildAbilitiesText(abilities)
    row.abilitiesList:SetText(abilitiesText)
    row.abilitiesHeader:SetShown(hasAbilities)
    row.abilitiesList:SetShown(hasAbilities)

    -- Reposition move buttons
    row.moveUp:ClearAllPoints()
    row.moveUp:SetPoint("TOPLEFT", row.text, "TOPLEFT", -5, 25)

    ns.UI:SetupRowButtons(row, pet)

    if ns.DragDrop then
        ns.DragDrop:SetupRowDragDrop(row, pet)
        ns.DragDrop:SetupModelDragDrop(row.model, pet, row)
    end

    row:Show()
end