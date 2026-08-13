-- OwnedPets/PetTooltip.lua
-- What a pet says about itself: the ability vocabulary, and the tooltip the two
-- model views show on hover.
--
-- This exists because the same content was written four times. The ability buckets
-- had four definitions (grid view, grouped view, the expanded row, the teams panel)
-- and three of them had already drifted apart -- [Spec] was gold in three places and
-- yellow in the fourth, [Other] was AAAAAA in three and ABABAB in the fourth, and one
-- carried a stray leading space that indented [Pet] and nothing else. Nobody chose
-- any of that; it is just what four copies of a table become.
--
-- The tooltip itself had two copies, grid and grouped, alike apart from the hint
-- block at the bottom -- which is the one part that genuinely differs per view. So
-- the spec takes its hints as an argument and owns everything above them.

_G.PSM = _G.PSM or {}
local PSM = _G.PSM

PSM.PetTooltip = {}
local PetTooltip = PSM.PetTooltip

--------------------------------------------------------------------------------
-- ABILITY BUCKETS
--------------------------------------------------------------------------------

-- Display order, and it is deliberate: a hunter picks a pet for its spec first and
-- its family second, so those lead. `prefix` carries its own inline colour and ends
-- with |r; `color` is the ability name that follows it.
PetTooltip.ABILITY_BUCKETS = {
    { key = "spec",    label = "[Spec]",   prefix = "|cFFFFD700[Spec]|r",   color = { 1,   1,   1   } },
    { key = "family",  label = "[Family]", prefix = "|cFF40FF40[Family]|r", color = { 0.8, 1,   0.8 } },
    { key = "pet",     label = "[Pet]",    prefix = "|cFF40FFFF[Pet]|r",    color = { 0.8, 1,   1   } },
    { key = "unknown", label = "[Other]",  prefix = "|cFFAAAAAA[Other]|r",  color = { 0.7, 0.7, 0.7 } },
}

-- True when `abilities` uses the per-bucket layout rather than a flat array. Saved
-- data written before the buckets existed is still a plain list of names.
function PetTooltip.IsBucketed(abilities)
    return (abilities.spec or abilities.family or abilities.pet or abilities.unknown) ~= nil
end

--------------------------------------------------------------------------------
-- TOOLTIP SPEC
--------------------------------------------------------------------------------

-- Colour thresholds for the level line. Anything below 1 is unknown rather than low.
local function LevelColor(level)
    if level >= 25 then return "|cFF00FF00" end
    if level >= 1  then return "|cFFFFFF00" end
    return "|cFF888888"
end

-- Everything a pet tooltip says, as a PSM.Tooltip spec. Every owned-pet tooltip in
-- the addon is this one, so a pet reads the same wherever it is looked at. Only two
-- things vary, and both are the caller's business:
--
--   opts.hints      trailing interaction text. The grouped view has sort-dependent
--                   reordering to explain, the grid view does not, the teams panel
--                   explains dragging and removal.
--   opts.slotLabel  overrides "Slot N" in the title, for the teams panel, where the
--                   slot is a team position and slot 6 is the companion.
--
-- Built per hover rather than per render, because both the hints and the stable
-- state they describe change while a row exists.
function PetTooltip.Spec(pet, opts)
    if not pet then return nil end
    opts = opts or {}

    local Theme = PSM.Theme
    local lines = {}
    local function Add(text, color) lines[#lines + 1] = { text = text, color = color } end

    Add(string.format("DisplayID: %d", pet.displayID or 0), Theme.COLOR.MUTED)
    if pet.familyName then Add("Family: " .. pet.familyName, Theme.COLOR.WHITE) end
    if pet.specName   then Add("Spec: "   .. pet.specName,   Theme.COLOR.MUTED) end
    if pet.tamer      then Add("Owned by: " .. pet.tamer,    Theme.COLOR.DIM)   end

    if pet.level and pet.level > 0 then
        -- The colour wraps the number. Both older copies appended the escape after it,
        -- where it coloured nothing and left |r unclosed.
        Add(string.format("Level: %s%d|r", LevelColor(pet.level), pet.level), Theme.COLOR.WHITE)
    end

    local abilities    = type(pet.abilities) == "table" and pet.abilities or {}
    local hasAbilities = false

    Add(" ")
    Add("|cFFFFD700Abilities:|r", Theme.COLOR.WHITE)

    if PetTooltip.IsBucketed(abilities) then
        for _, bucket in ipairs(PetTooltip.ABILITY_BUCKETS) do
            local list = abilities[bucket.key]
            if list and #list > 0 then
                for _, ability in ipairs(list) do
                    Add(string.format("  %s %s", bucket.prefix, ability), bucket.color)
                end
                hasAbilities = true
            end
        end
    else
        for _, ability in ipairs(abilities) do
            Add("  \226\128\162 " .. (type(ability) == "table" and ability.name or tostring(ability)),
                Theme.COLOR.WHITE)
            hasAbilities = true
        end
    end

    if not hasAbilities then
        Add("|cFFAAAAAA(No abilities available)|r", Theme.COLOR.DIM)
    end

    if opts.hints then
        Add(" ")
        Add(opts.hints, Theme.COLOR.DIM)
    end

    local exoticLabel = pet.isExotic and " |cffff8800[Exotic]|r" or ""
    local slotLabel   = opts.slotLabel or string.format("Slot %d", pet.slotID or 0)
    return {
        title      = string.format("%s: %s%s", slotLabel, pet.name or "?", exoticLabel),
        titleColor = Theme.COLOR.WHITE,
        lines      = lines,
    }
end
