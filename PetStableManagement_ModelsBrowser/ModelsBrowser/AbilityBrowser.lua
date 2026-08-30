-- ModelsBrowser/AbilityBrowser.lua
-- Ability Browser panel — card grid layout (3 columns, expand-in-place)

_G.PSM = _G.PSM or {}
local PSM = _G.PSM
PSM.AbilityBrowser = PSM.AbilityBrowser or {}

local AB = PSM.AbilityBrowser

-- ─────────────────────────────────────────────
-- Constants
-- ─────────────────────────────────────────────

local CFG = {
    PANEL_WIDTH        = 800,
    PANEL_HEIGHT       = 600,
    ICON_SIZE          = 40,
    ICON_PADDING       = 6,
    CARD_COLUMNS       = 3,
    CARD_PADDING       = 8,
    CARD_GAP           = 8,
    -- Partial state: always 1 row of 5 icons + reserved label row
    PARTIAL_ICONS      = 5,
    -- Expanded state: always 2 rows tall (fills full panel width)
    EXPANDED_ROWS      = 2,
    -- Fixed row heights derived below in Layout block
}

-- The card's own greys. Deliberately kept here rather than folded into
-- PSM.Theme.FILL: the theme's ROW and SEPARATOR are a shade bluer (0.08/0.08/0.12
-- and 0.25/0.25/0.30) and swapping to them would restyle this panel, which is a
-- look-and-feel decision (A13), not part of centralising construction.
local CARD = {
    BG        = { 0.08, 0.08, 0.08, 0.85 },
    BORDER    = { 0.25, 0.25, 0.25, 1    },
    HEADER_BG = { 0.14, 0.14, 0.14, 1    },
    SEPARATOR = { 0.25, 0.25, 0.25, 1    },
    HOVER     = { 1,    1,    1,    0.12 },  -- icon hover wash
}

-- ─────────────────────────────────────────────
-- Derived layout values (computed once)
-- ─────────────────────────────────────────────
-- These are set up after CFG so they can reference it.

local CELL          = CFG.ICON_SIZE + CFG.ICON_PADDING
local HEADER_H      = 22
local SEP_H         = 1
local MORE_H        = 16    -- height reserved for "and X more" / "Show less" label
local P             = CFG.CARD_PADDING

-- Partial card: header + sep + padding + 1 icon row + padding/2 + label row + padding
local PARTIAL_CARD_H = HEADER_H + SEP_H + P + CELL + P / 2 + MORE_H + P

-- Expanded card: header + sep + padding + 2 icon rows + padding/2 + label row + padding
local EXPANDED_CARD_H = HEADER_H + SEP_H + P + (CFG.EXPANDED_ROWS * CELL) + P / 2 + MORE_H + P

-- Full-width card inner width (scrollW - 2*gap - 2*padding); computed in PopulateAbilities
-- because scrollW depends on panel width. Stored per-populate in AB.expandedInnerW.

-- ─────────────────────────────────────────────
-- Data index (built once, cached)
-- ─────────────────────────────────────────────

local function BuildAbilityIndex()
    if AB.tagGroups then return end

    local bySpell      = {}
    local allAbilities = {}

    for familyId, familyData in pairs(_G.AbilitiesData or {}) do
        if familyData.ranks then
            for rankName, rankAbilities in pairs(familyData.ranks) do
                for spellId, abilityData in pairs(rankAbilities) do
                    local entry = bySpell[spellId]
                    if not entry then
                        entry = {
                            spellId  = spellId,
                            name     = abilityData.name,
                            rank     = rankName,
                            tag      = abilityData.tag,
                            category = abilityData.category,
                            families = {},
                        }
                        bySpell[spellId] = entry
                        allAbilities[#allAbilities+1] = entry
                    end
                    if type(familyId) == "number" then
                        entry.families[#entry.families+1] = {
                            id   = familyId,
                            name = familyData.name,
                        }
                    else
                        entry.specTier = rankName
                    end
                end
            end
        end
    end

    for _, entry in pairs(bySpell) do
        table.sort(entry.families, function(a, b) return a.name < b.name end)
    end

    local tagGroups = {}
    for _, entry in pairs(bySpell) do
        local tag = entry.tag or "Other"
        local cat = entry.category or "Other"
        tagGroups[tag] = tagGroups[tag] or {}
        tagGroups[tag][cat] = tagGroups[tag][cat] or {}
        tagGroups[tag][cat][#tagGroups[tag][cat]+1] = entry
    end

    for _, catMap in pairs(tagGroups) do
        for _, abilityList in pairs(catMap) do
            table.sort(abilityList, function(a, b) return a.name < b.name end)
        end
    end

    AB.tagGroups      = tagGroups
    AB.allAbilities   = allAbilities
    AB.abilityBySpell = bySpell
end

-- ─────────────────────────────────────────────
-- Ability selection state (default: unselected)
-- ─────────────────────────────────────────────

local function EnsureAbilityState()
    if not AB.selectedAbilities then
        -- First build this session: restore last Apply's ticked spells, so reopening this
        -- panel after a reload shows the same checkboxes instead of starting blank.
        AB.selectedAbilities = {}
        local saved = PetStableManagementDB and PetStableManagementDB.filters
            and PetStableManagementDB.filters.selectedAbilitySpells
        if saved then
            for spellId, isOn in pairs(saved) do
                if isOn then AB.selectedAbilities[spellId] = true end
            end
        end
    end
    for _, entry in pairs(AB.allAbilities or {}) do
        if AB.selectedAbilities[entry.spellId] == nil then
            AB.selectedAbilities[entry.spellId] = false
        end
    end
end

-- ─────────────────────────────────────────────
-- Filtering
-- ─────────────────────────────────────────────

local function FilterTagGroups(tagGroups, query, activeTag)
    query = query and query:lower() or ""
    local result = {}
    for tag, catMap in pairs(tagGroups) do
        if activeTag == "" or activeTag == tag then
            for cat, abilityList in pairs(catMap) do
                for _, entry in ipairs(abilityList) do
                    local match = (query == "")
                    if not match then
                        if entry.name     and entry.name:lower():find(query, 1, true)     then match = true end
                        if entry.category and entry.category:lower():find(query, 1, true) then match = true end
                        if entry.tag      and entry.tag:lower():find(query, 1, true)      then match = true end
                        if entry.rank     and entry.rank:lower():find(query, 1, true)     then match = true end
                        if entry.specTier and entry.specTier:lower():find(query, 1, true) then match = true end
                        if not match then
                            for _, fam in ipairs(entry.families) do
                                if fam.name:lower():find(query, 1, true) then match = true; break end
                            end
                        end
                    end
                    if match then
                        result[tag] = result[tag] or {}
                        result[tag][cat] = result[tag][cat] or {}
                        result[tag][cat][#result[tag][cat]+1] = entry
                    end
                end
            end
        end
    end
    return result
end

-- ─────────────────────────────────────────────
-- Selection helpers
-- ─────────────────────────────────────────────

local function UpdateSelectionNote(panel)
    if not panel.selectionNote then return end
    local n = 0
    for spellId, isOn in pairs(AB.selectedAbilities or {}) do
        if isOn and panel.visibleSpells and panel.visibleSpells[spellId] then n = n + 1 end
    end
    panel.selectionNote:SetText(n == 1 and PSM.L("%d ability selected", n)
                                    or PSM.L("%d abilities selected", n))
end

local function UpdateSelectAllButton(panel)
    if not panel.selectAllBtn then return end
    local anySelected = false
    for spellId, isOn in pairs(AB.selectedAbilities or {}) do
        if isOn and panel.visibleSpells and panel.visibleSpells[spellId] then
            anySelected = true; break
        end
    end
    panel.selectAllBtn:SetText(anySelected and PSM.L("Unselect All") or PSM.L("Select All"))
end

local function SetIconAppearance(btn, selected)
    if btn and btn.iconTex then
        local v = selected and 1 or 0.4
        btn.iconTex:SetVertexColor(v, v, v)
    end
    if btn and btn.selBorder then
        if selected then btn.selBorder:Show() else btn.selBorder:Hide() end
    end
end

local function UpdateCardHeader(card)
    if not card.entries or not card.catLabel then return end
    local allSel, anySel = true, false
    for _, entry in ipairs(card.entries) do
        if AB.selectedAbilities[entry.spellId] then anySel = true
        else allSel = false end
    end
    if allSel then
        card.catLabel:SetTextColor(unpack(PSM.Theme.COLOR.WHITE))
    elseif anySel then
        card.catLabel:SetTextColor(unpack(PSM.Theme.COLOR.MUTED))
    else
        card.catLabel:SetTextColor(unpack(PSM.Config.COLORS.ABILITY_CATEGORY_LABEL))
    end
end

-- ─────────────────────────────────────────────
-- Ability icon
-- ─────────────────────────────────────────────

-- Icons are pooled and rebound, so nothing here may close over an entry: every handler
-- reads `btn.entry`, which BindAbilityIcon reassigns. Capturing it forces a fresh icon per
-- populate, and WoW frames cannot be destroyed.
local function CreateAbilityIcon(parent, panel)
    local Widgets = PSM.Widgets

    local btn = Widgets.Frame(parent, {
        frameType = "Button",
        size      = { CFG.ICON_SIZE, CFG.ICON_SIZE },
    })

    btn.iconTex = Widgets.Texture(btn, {
        layer     = "ARTWORK",
        allPoints = true,
    })

    btn.selBorder = Widgets.Texture(btn, {
        layer = "OVERLAY",
        color = PSM.Config.COLORS.ABILITY_HIGHLIGHT,
        point = {
            { "TOPLEFT",     btn, "TOPLEFT",     -1,  1 },
            { "BOTTOMRIGHT", btn, "BOTTOMRIGHT",  1, -1 },
        },
    })

    local highlight = Widgets.Texture(btn, {
        layer     = "OVERLAY",
        allPoints = true,
        color     = CARD.HOVER,
        hidden    = true,
    })

    -- The spell tooltip is Blizzard's own; the extra "Available from:" lines come from
    -- core's shared post-call, which reads the ability armed by SetHoveredAbilityTooltip.
    -- Attach runs onEnter before it builds the tooltip, so the arm lands first.
    PSM.Tooltip.Attach(btn,
        function()
            local entry = btn.entry
            if not entry then return nil end
            if entry.spellId then return { spellId = entry.spellId } end
            return {
                title      = entry.name or PSM.L("Unknown"),
                titleColor = PSM.Theme.COLOR.WHITE,
                lines      = PSM.Data:GetAbilityTooltipLines(entry.name),
            }
        end,
        {
            onEnter = function()
                -- Only armed when there is a spell to hang the post-call off, so a
                -- spell tooltip raised by anything else never picks up our lines.
                local entry = btn.entry
                PSM.Data:SetHoveredAbilityTooltip((entry and entry.spellId) and entry.name or nil)
                highlight:Show()
            end,
            onLeave = function()
                PSM.Data:SetHoveredAbilityTooltip(nil)
                highlight:Hide()
            end,
        }
    )

    btn:SetScript("OnClick", function()
        local entry = btn.entry
        if not entry then return end
        local newState = not AB.selectedAbilities[entry.spellId]
        AB.selectedAbilities[entry.spellId] = newState
        for _, iconBtn in ipairs(panel.abilityIcons or {}) do
            if iconBtn.spellId == entry.spellId then
                SetIconAppearance(iconBtn, newState)
            end
        end
        if panel.cardBySpell and panel.cardBySpell[entry.spellId] then
            UpdateCardHeader(panel.cardBySpell[entry.spellId])
        end
        UpdateSelectionNote(panel)
        UpdateSelectAllButton(panel)
    end)

    return btn
end

-- Point a pooled icon at a different ability. Everything the handlers above read comes
-- from here.
local function BindAbilityIcon(btn, entry)
    btn.entry   = entry
    btn.spellId = entry.spellId
    btn.iconTex:SetTexture(PSM.Utils:GetSpellTextureCompat(entry.spellId))
    SetIconAppearance(btn, AB.selectedAbilities[entry.spellId])
end

-- ─────────────────────────────────────────────
-- Icon grid helper
-- ─────────────────────────────────────────────

-- Places icons from entries[startIdx .. startIdx+count-1] into parent.
-- Icons flow left-to-right, iconsPerRow wide.
-- Fills `area` from the pool it owns, creating only what it has never needed before, and
-- hiding whatever a previous longer list left over. The area keeps its icons across
-- repopulations, so nothing is reparented and nothing is orphaned.
local function PlaceIconGrid(area, entries, startIdx, count, iconsPerRow, panel)
    area.icons = area.icons or {}
    local used = 0

    for i = 1, count do
        local entry = entries[startIdx + i - 1]
        if not entry then break end

        local btn = area.icons[i]
        if not btn then
            btn = CreateAbilityIcon(area, panel)
            area.icons[i] = btn
        end

        BindAbilityIcon(btn, entry)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", area, "TOPLEFT",
            ((i - 1) % iconsPerRow) * CELL,
            -math.floor((i - 1) / iconsPerRow) * CELL)
        btn:Show()

        -- Rebuilt per populate: this list is how a click on one icon updates the other
        -- copy of the same spell (an ability appears in both the partial and expanded
        -- grids), so it must contain the live icons and only those.
        panel.abilityIcons[#panel.abilityIcons + 1] = btn
        used = i
    end

    for i = used + 1, #area.icons do
        area.icons[i].entry = nil
        area.icons[i]:Hide()
    end
end

-- ─────────────────────────────────────────────
-- Card construction
-- ─────────────────────────────────────────────

-- cardW         : width used in partial state (1/3 of scroll area)
-- expandedInnerW: inner pixel width available when card is full-width
local function CreateCard(parent, panel, onToggle)
    local Widgets = PSM.Widgets

    local card = Widgets.Frame(parent, {
        height      = PARTIAL_CARD_H,   -- all partial cards identical height
        backdrop    = "SOLID_BORDERED",
        color       = CARD.BG,
        borderColor = CARD.BORDER,
    })
    card.isExpanded = false

    -- ── Header ──
    local header = Widgets.Frame(card, {
        frameType = "Button",
        height    = HEADER_H,
        point     = {
            { "TOPLEFT",  card, "TOPLEFT",  0, 0 },
            { "TOPRIGHT", card, "TOPRIGHT", 0, 0 },
        },
    })

    Widgets.Texture(header, {
        layer     = "BACKGROUND",
        allPoints = true,
        color     = CARD.HEADER_BG,
    })

    local catLabel = Widgets.Label(header, {
        fontSize = PSM.Config.FONT_SIZES.ABILITY_CATEGORY,
        color    = PSM.Config.COLORS.ABILITY_CATEGORY_LABEL,
        point    = { "LEFT", header, "LEFT", P, 0 },
    })
    card.catLabel = catLabel

    card.countLabel = Widgets.Label(header, {
        fontSize = PSM.Config.FONT_SIZES.STATS,
        color    = PSM.Theme.COLOR.FAINT,
        point    = { "RIGHT", header, "RIGHT", -P, 0 },
    })

    Widgets.Line(card, {
        layer  = "BACKGROUND",
        height = SEP_H,
        color  = CARD.SEPARATOR,
        point  = {
            { "TOPLEFT",  card, "TOPLEFT",  0, -HEADER_H },
            { "TOPRIGHT", card, "TOPRIGHT", 0, -HEADER_H },
        },
    })

    -- Both icon areas start below the header and span the card's inner width.
    local function IconArea(height)
        return Widgets.Frame(card, {
            height = height,
            point  = {
                { "TOPLEFT",  card, "TOPLEFT",   P, -(HEADER_H + SEP_H + P) },
                { "TOPRIGHT", card, "TOPRIGHT", -P, -(HEADER_H + SEP_H + P) },
            },
        })
    end

    -- ── Partial icon area (always shown, 1 row of up to 5 icons) ──
    card.partialArea = IconArea(CELL)

    -- ── Expanded icon area (hidden until expanded; contains ALL icons) ──
    -- Uses full inner width so icons spread across the whole card.
    card.expandArea = IconArea(CFG.EXPANDED_ROWS * CELL)
    card.expandArea:Hide()

    -- ── "and X more" / "Show less" label — anchored bottom-right always ──
    local moreBtn = Widgets.Frame(card, {
        frameType = "Button",
        size      = { 120, MORE_H },
        point     = { "BOTTOMRIGHT", card, "BOTTOMRIGHT", -P, P },
    })
    card.moreBtn = moreBtn

    local moreLabel = Widgets.Label(moreBtn, {
        fontSize = PSM.Config.FONT_SIZES.STATS,
        color    = PSM.Config.COLORS.PRIMARY,
        justify  = "RIGHT",
        point    = { "RIGHT", moreBtn, "RIGHT", 0, 0 },
    })
    moreBtn.label = moreLabel

    -- ── Expand / collapse ──
    -- Always attached and guarded on card.hiddenCount, rather than attached only when
    -- there is something to expand: a pooled card is rebound to categories with different
    -- entry counts, so "has more" is not a property of the card, only of its current
    -- contents.
    moreBtn:SetScript("OnClick", function()
        if (card.hiddenCount or 0) <= 0 then return end
        card.isExpanded = not card.isExpanded
        if card.isExpanded then
            card:SetHeight(EXPANDED_CARD_H)
            card.partialArea:Hide()
            card.expandArea:Show()
            moreLabel:SetText(PSM.L("Show less"))
        else
            card:SetHeight(PARTIAL_CARD_H)
            card.expandArea:Hide()
            card.partialArea:Show()
            moreLabel:SetText(PSM.L("and %d more...", card.hiddenCount))
        end
        if onToggle then onToggle(card) end
    end)

    -- ── Header: select / unselect all in card ──
    header:SetScript("OnClick", function()
        local entries = card.entries or {}
        local allSelected = true
        for _, entry in ipairs(entries) do
            if not AB.selectedAbilities[entry.spellId] then allSelected = false; break end
        end
        local newState = not allSelected
        for _, entry in ipairs(entries) do
            AB.selectedAbilities[entry.spellId] = newState
            for _, iconBtn in ipairs(panel.abilityIcons or {}) do
                if iconBtn.spellId == entry.spellId then
                    SetIconAppearance(iconBtn, newState)
                end
            end
        end
        UpdateCardHeader(card)
        UpdateSelectionNote(panel)
        UpdateSelectAllButton(panel)
    end)
    header:SetScript("OnEnter", function()
        catLabel:SetTextColor(unpack(PSM.Config.COLORS.PRIMARY))
    end)
    header:SetScript("OnLeave", function()
        UpdateCardHeader(card)
    end)

    return card
end

-- Point a pooled card at a different category. Everything the card's handlers read --
-- entries, hiddenCount, the two icon grids -- is (re)set here.
local function BindCard(card, cat, entries, cardW, expandedInnerW, panel)
    card.cat         = cat
    card.entries     = entries
    card.hiddenCount = math.max(0, #entries - CFG.PARTIAL_ICONS)

    card:SetWidth(cardW)
    card.catLabel:SetText(cat)
    card.countLabel:SetText("(" .. #entries .. ")")

    -- Collapsed on every rebind: the expanded state belonged to the previous contents,
    -- and a card silently keeping it would open at EXPANDED_CARD_H showing a grid built
    -- for a different category.
    card.isExpanded = false
    card:SetHeight(PARTIAL_CARD_H)
    card.partialArea:Show()
    card.expandArea:Hide()

    PlaceIconGrid(card.partialArea, entries, 1, CFG.PARTIAL_ICONS, CFG.PARTIAL_ICONS, panel)
    PlaceIconGrid(card.expandArea, entries, 1, #entries,
        math.max(1, math.floor(expandedInnerW / CELL)), panel)

    if card.hiddenCount > 0 then
        card.moreBtn.label:SetText(PSM.L("and %d more...", card.hiddenCount))
        card.moreBtn:Show()
    else
        card.moreBtn:Hide()
    end

    UpdateCardHeader(card)
end

-- ─────────────────────────────────────────────
-- Population
-- ─────────────────────────────────────────────

function AB:PopulateAbilities(panel, query, activeTag)
    local scrollFrame = panel.scrollFrame
    if not scrollFrame then return end

    query     = query or ""
    activeTag = activeTag or ""

    -- Built once and reused. The search box calls this per keystroke, and WoW frames
    -- cannot be destroyed, so building a fresh frame tree here leaks one per search.
    local scrollChild = panel.scrollChild
    if not scrollChild then
        scrollChild = PSM.Widgets.Frame(scrollFrame, {})
        scrollFrame:SetScrollChild(scrollChild)
        panel.scrollChild = scrollChild
    end

    panel.cardPool     = panel.cardPool or {}
    panel.abilityIcons = {}
    panel.cardBySpell  = {}

    local filtered      = FilterTagGroups(AB.tagGroups, query, activeTag)
    local catMapAll     = {}
    local visibleSpells = {}

    for _, catMap in pairs(filtered) do
        for cat, abilityList in pairs(catMap) do
            catMapAll[cat] = catMapAll[cat] or {}
            for _, entry in ipairs(abilityList) do
                table.insert(catMapAll[cat], entry)
                visibleSpells[entry.spellId] = true
            end
        end
    end

    panel.visibleSpells = visibleSpells

    local cats = {}
    for cat in pairs(catMapAll) do cats[#cats+1] = cat end
    table.sort(cats)

    local scrollW        = CFG.PANEL_WIDTH - 50
    local gap            = CFG.CARD_GAP
    local cols           = CFG.CARD_COLUMNS
    local cardW          = math.floor((scrollW - gap * (cols + 1)) / cols)
    -- Inner width available inside a full-width expanded card
    local expandedInnerW = (scrollW - gap * 2) - P * 2

    scrollChild:SetWidth(scrollW)

    -- Published rather than captured. A pooled card's expand handler outlives the populate
    -- that built it, so anything it closes over is a snapshot of that first call -- the
    -- same trap the icons and cards above were just taken out of. These four happen to be
    -- CFG-derived constants today, which is exactly what would make a future stale capture
    -- invisible if the panel ever became resizable.
    panel.layout = { scrollW = scrollW, cardW = cardW, gap = gap, cols = cols }

    local cardList = {}

    -- Pooled by category. The set of categories is small and stable across searches, so
    -- after the first populate this creates nothing at all -- a search only rebinds.
    for _, cat in ipairs(cats) do
        local entries = catMapAll[cat]
        table.sort(entries, function(a, b) return a.name < b.name end)

        local card = panel.cardPool[cat]
        if not card then
            card = CreateCard(scrollChild, panel, function()
                -- Reads panel.cardList and panel.layout, never the upvalues: this handler
                -- outlives the populate that created the card, and both are rebuilt on
                -- every search.
                local L = panel.layout
                AB:ReflowCards(panel, panel.cardList, L.scrollW, L.cardW, L.gap, L.cols)
                UpdateSelectionNote(panel)
                UpdateSelectAllButton(panel)
            end)
            panel.cardPool[cat] = card
        end

        BindCard(card, cat, entries, cardW, expandedInnerW, panel)
        card:Show()

        for _, entry in ipairs(entries) do
            panel.cardBySpell[entry.spellId] = card
        end

        cardList[#cardList+1] = card
    end

    -- Categories filtered out by this search keep their card, hidden.
    for cat, card in pairs(panel.cardPool) do
        if not catMapAll[cat] then card:Hide() end
    end

    panel.cardList = cardList
    AB:ReflowCards(panel, cardList, scrollW, cardW, gap, cols)
    UpdateSelectionNote(panel)
    UpdateSelectAllButton(panel)
end

-- ─────────────────────────────────────────────
-- Reflow
-- ─────────────────────────────────────────────

function AB:ReflowCards(panel, cardList, scrollW, cardW, gap, cols)
    local yOffset = -gap
    local i       = 1

    while i <= #cardList do
        local card = cardList[i]

        if card.isExpanded then
            card:SetWidth(scrollW - gap * 2)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", panel.scrollChild, "TOPLEFT", gap, yOffset)
            yOffset = yOffset - card:GetHeight() - gap
            i       = i + 1
        else
            -- Fill a row of up to `cols` non-expanded cards
            local rowEnd = i
            local count  = 1
            while count < cols
                  and rowEnd + 1 <= #cardList
                  and not cardList[rowEnd + 1].isExpanded do
                rowEnd = rowEnd + 1
                count  = count + 1
            end

            local maxH = 0
            for j = i, rowEnd do
                local c    = cardList[j]
                local xOff = gap + (j - i) * (cardW + gap)
                c:SetWidth(cardW)
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", panel.scrollChild, "TOPLEFT", xOff, yOffset)
                maxH = math.max(maxH, c:GetHeight())
            end

            yOffset = yOffset - maxH - gap
            i       = rowEnd + 1
        end
    end

    panel.scrollChild:SetHeight(math.abs(yOffset) + gap)
end

-- ─────────────────────────────────────────────
-- Tag pill bar
-- ─────────────────────────────────────────────

local PILL_TAGS = { "All", "Spec", "Utility", "Defense", "Damage", "Control", "Debuffs", "Fun" }

-- Was a hand-rolled copy of the exact same frame Special Tames also built
-- independently; see PanelManager:CreatePillBar (A13).
local function CreatePillBar(panel)
    return PSM.PanelManager:CreatePillBar(panel, PILL_TAGS, function(tagName)
        local activeTag = (tagName == "All") and "" or tagName
        panel.activeTag = activeTag
        AB:PopulateAbilities(panel, panel.searchBox:GetSearchText(), activeTag)
        panel.scrollFrame:SetVerticalScroll(0)
    end)
end

-- ─────────────────────────────────────────────
-- Footer
-- ─────────────────────────────────────────────

-- Apply the ticked abilities as a family filter on the Models Browser.
local function ApplyAbilityFilters(panel)
    -- Deliberately leaves selectedTamingRules/selectedConditions untouched: those are
    -- re-checked per display regardless of family selection (DisplayPassesFilters), so
    -- Abilities and Special Tames compose instead of one replacing the other.

    -- Computed into a local first: an Apply with nothing selected must clear the
    -- Abilities filter (see isActive below), not leave the old narrowing in place.
    local abilityFamilies = {}
    local appliedCount = 0
    local hasSpecAbility = false

    for spellId, isOn in pairs(AB.selectedAbilities or {}) do
        if isOn and panel.visibleSpells and panel.visibleSpells[spellId] then
            local entry = AB.abilityBySpell and AB.abilityBySpell[spellId]
            if entry then
                if entry.specTier then
                    hasSpecAbility = true
                else
                    for _, family in ipairs(entry.families or {}) do
                        if not abilityFamilies[family.name] then
                            abilityFamilies[family.name] = true
                            appliedCount = appliedCount + 1
                        end
                    end
                end
            end
        end
    end

    if hasSpecAbility then
        for familyId, familyData in pairs(_G.AbilitiesData or {}) do
            if type(familyId) == "number" and familyData and familyData.name then
                if not abilityFamilies[familyData.name] then
                    abilityFamilies[familyData.name] = true
                    appliedCount = appliedCount + 1
                end
            end
        end
    end

    local isActive = appliedCount > 0
    PSM.state.familiesAppliedFromAbilities = isActive
    -- Kept separate from selectedModelsFamilies (recompute below narrows that further
    -- by any active Special Tames rules): this pure result is what a Special Tames
    -- re-Apply intersects against, so switching rules replaces rather than ANDs.
    PSM.state.abilitiesFamilySet = isActive and abilityFamilies or nil

    PetStableManagementDB = PetStableManagementDB or {}
    PetStableManagementDB.filters = PetStableManagementDB.filters or {}
    PetStableManagementDB.filters.familiesAppliedFromAbilities  = isActive or nil
    PetStableManagementDB.filters.selectedFamiliesFromAbilities = isActive and PSM.Utils.DeepCopy(abilityFamilies) or nil

    -- Only the derived family set was saved before, so this panel's own checkboxes had
    -- no way to know which abilities had been picked. Save just the ticked spell IDs,
    -- not the whole selectedAbilities map (mostly false entries).
    local selectedSpells = {}
    for spellId, isOn in pairs(AB.selectedAbilities or {}) do
        if isOn then selectedSpells[spellId] = true end
    end
    PetStableManagementDB.filters.selectedAbilitySpells = next(selectedSpells) and selectedSpells or nil

    -- Always recompute, even when cleared, so the family selection widens back out.
    if PSM.ModelsFilters and PSM.ModelsFilters.RecomputeSmartFamilySelection then
        PSM.ModelsFilters:RecomputeSmartFamilySelection()
    end

    if PSM.ModelsFilters and PSM.ModelsFilters.ReloadAndSummarise then
        PSM.ModelsFilters:ReloadAndSummarise()
    end
    PSM.Utils:Msg("SUCCESS", PSM.L("Filter applied - %d families from selected abilities.", appliedCount))
end

-- Select or unselect every currently visible ability. "Visible" is what the search
-- box and the active tag pill leave on screen, not the whole ability list.
local function ToggleSelectAll(panel)
    local anySelected = false
    for spellId, isOn in pairs(AB.selectedAbilities or {}) do
        if isOn and panel.visibleSpells and panel.visibleSpells[spellId] then
            anySelected = true; break
        end
    end

    local newState = not anySelected
    for spellId in pairs(panel.visibleSpells or {}) do
        AB.selectedAbilities[spellId] = newState
    end
    for _, iconBtn in ipairs(panel.abilityIcons or {}) do
        if iconBtn.spellId then
            SetIconAppearance(iconBtn, newState)
        end
    end
    for _, card in ipairs(panel.cardList or {}) do
        UpdateCardHeader(card)
    end

    UpdateSelectionNote(panel)
    UpdateSelectAllButton(panel)
end

-- Bare label, no border/hairline -- the one footer contract every panel uses (A13).
-- Was a bordered frame with its own hairline, independently duplicated in Special
-- Tames; see PanelManager:CreateFooterLabel.
local function CreateFooter(panel)
    local Widgets = PSM.Widgets

    panel.selectionNote = PSM.PanelManager:CreateFooterLabel(panel, {
        fontSize = PSM.Config.FONT_SIZES.STATS,
        color    = PSM.Config.COLORS.ABILITY_SELECTION_NOTE,
        point    = { "BOTTOMLEFT", panel, "BOTTOMLEFT", 20, PSM.Theme.CHROME.FOOTER_Y },
        text     = PSM.L("%d abilities selected", 0),
    })

    local applyBtn = Widgets.Button(panel, {
        width   = PSM.Theme.CONTROL.BUTTON_W.M,
        point   = { "BOTTOMRIGHT", panel, "BOTTOMRIGHT", -20, PSM.Theme.CHROME.FOOTER_Y },
        text    = PSM.L("Apply Filters"),
        onClick = function() ApplyAbilityFilters(panel) end,
    })

    panel.selectAllBtn = Widgets.Button(panel, {
        width   = PSM.Theme.CONTROL.BUTTON_W.M,
        point   = { "RIGHT", applyBtn, "LEFT", -8, 0 },
        text    = PSM.L("Select All"),
        onClick = function() ToggleSelectAll(panel) end,
    })
end

-- ─────────────────────────────────────────────
-- Panel entry point
-- ─────────────────────────────────────────────

    -- Reset the flag when the Ability Browser is opened
    function AB:Toggle()
        PSM.state.familiesAppliedFromAbilities = false
        PSM.PanelManager:TogglePanel("abilityBrowser", function() self:CreateAbilityBrowser() end, PSM.L("Pet Ability Browser"))
    end

function AB:CreateAbilityBrowser()
    if PSM.state.abilityBrowser then return end

    BuildAbilityIndex()
    EnsureAbilityState()

    local panel = PSM.PanelManager:CreateBasePanel("abilityBrowser", {
        width              = CFG.PANEL_WIDTH,
        height             = CFG.PANEL_HEIGHT,
        maxWidth           = CFG.PANEL_WIDTH,
        minWidth           = CFG.PANEL_WIDTH,
        title              = PSM.L("Pet Ability Browser"),
        resizable          = true,
        showResizeHandle   = true,
        showMaximizeButton = false,
    })

    local Widgets = PSM.Widgets

    -- The shared search box, not a hand-rolled one. This panel and Special Tames each
    -- built their own, which is why they looked different from the three main panels
    -- (no placeholder) and behaved differently: they repopulated on every keystroke
    -- with no debounce, rebuilding the whole card list per character typed.
    PSM.PanelManager:CreateSearchBox(panel, function(text)
        AB:PopulateAbilities(panel, text, panel.activeTag or "")
        panel.scrollFrame:SetVerticalScroll(0)
    end, {
        placeholder = PSM.L("Search abilities..."),
    })

    panel.pillBar = CreatePillBar(panel)

    local scrollFrame = Widgets.Frame(panel, {
        frameType = "ScrollFrame",
        template  = "UIPanelScrollFrameTemplate",
        skin      = "scrollframe",
        point     = {
            { "TOPLEFT",     panel, "TOPLEFT",      20, -120 },
            { "BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30,   56 },
        },
    })
    PSM.Skin.Apply(scrollFrame.ScrollBar, "scrollbar")

    local scrollChild = Widgets.Frame(scrollFrame, {
        size = { CFG.PANEL_WIDTH - 50, 400 },
    })
    scrollFrame:SetScrollChild(scrollChild)

    panel.scrollFrame = scrollFrame
    panel.scrollChild = scrollChild
    panel.activeTag   = ""

    CreateFooter(panel)      -- must precede PopulateAbilities so selectAllBtn exists
    AB:PopulateAbilities(panel, "", "")

    return panel
end