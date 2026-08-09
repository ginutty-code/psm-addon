-- TamingChecker.lua
-- Defines all special taming rules and evaluates the current character against them.
-- Dependencies: none (standalone, read by UI layer)
-- Usage: PSM.TamingChecker.GetNPCStatus(npcData) --> array of {label, status} per rule

PSM.TamingChecker = {}

-- ---------------------------------------------------------------------------
-- Race ID reference (from UnitRaceByID / select(3, UnitRace("player")))
-- ---------------------------------------------------------------------------
local RACE_IDS = {
    Undead           = 5,
    Gnome            = 7,
    Goblin           = 9,
    Pandaren         = 24,  -- neutral
    PandarenAlliance = 25,
    PandarenHorde    = 26,
    ZandalariTroll   = 31,
    Mechagnome       = 37,
}

-- ---------------------------------------------------------------------------
-- Taming rules
-- Each rule key matches the string used in ModelsData.lua taming={} fields.
-- check fields:
--   spec      (number)  : required specialization ID
--   level     (number)  : required player level
--   autoRaces (table)   : race IDs that automatically qualify (OR logic)
--   spellID   (number)  : spell taught by the unlock item
--   questID   (number)  : account-wide quest/flag completion fallback
--   toyID     (number)  : required toy item ID
-- ---------------------------------------------------------------------------
PSM.TamingRules = {
    ["Exotic"] = {
        label       = "Exotic Family",
        desc        = "Beast Mastery hunters that have reached level 10.",
        hint        = { plain = "Beast Mastery, level 10" },
        accountWide = false,
        check = {
            spec  = 253,
            level = 10,
        },
    },

    ["Undead"] = {
        label       = "Undead Taming",
        desc        = "Forsaken hunters know this automatically. Others learn from Simple Tome of Bone-Binding. Account-wide.",
        hint        = { autoRace = "Undead", itemID = 183124, itemName = "Simple Tome of Bone-Binding" },
        itemID      = 183124,
        accountWide = true,
        check = {
            autoRaces = { RACE_IDS.Undead },
            spellID   = 340825,
            questID   = 62255,
        },
    },

    ["Blood Beast"] = {
        label       = "Blood Beast Taming",
        desc        = "Learned from Blood-Soaked Tome of Dark Whispers (Zul, Uldir Normal+). Account-wide.",
        hint        = { itemID = 166502, itemName = "Blood-Soaked Tome of Dark Whispers" },
        itemID      = 166502,
        accountWide = true,
        check = {
            spellID = 288956,
            questID = 54753,
        },
    },

    ["Florafaun"] = {
        label       = "Florafaun Taming",
        desc        = "Learned from Trials of the Florafaun Hunter (Harandar florafaun rares). Requires level 80. Account-wide.",
        hint        = { itemID = 264895, itemName = "Trials of the Florafaun Hunter" },
        itemID      = 264895,
        accountWide = true,
        check = {
            spellID = 1272785,
            questID = 87421,
        },
    },

    ["Direhorn"] = {
        label       = "Direhorn Taming",
        desc        = "Zandalari hunters know this automatically. Others learn from Ancient Tome of Dinomancy. NOT Account-wide.",
        hint        = { autoRace = "Zandalari Troll", itemID = 94232, itemName = "Ancient Tome of Dinomancy" },
        itemID      = 94232,
        accountWide = false,
        check = {
            autoRaces = { RACE_IDS.ZandalariTroll },
            spellID   = 138430,
        },
    },

    ["Feathermane"] = {
        label       = "Feathermane Taming",
        desc        = "Learned from Tome of the Hybrid Beast. NOT Account-wide.",
        hint        = { itemID = 147580, itemName = "Tome of the Hybrid Beast" },
        itemID      = 147580,
        accountWide = false,
        check = {
            spellID = 242155,
        },
    },

    ["Lesser Dragonkin"] = {
        label       = "Lesser Dragonkin Taming",
        desc        = "Learned from How to Train a Dragonkin (Valdrakken Accord Renown 23, Warband-wide). Account-wide.",
        hint        = { itemID = 201791, itemName = "How to Train a Dragonkin" },
        itemID      = 201791,
        accountWide = true,
        check = {
            spellID = 394788,
            questID = 72094,
        },
    },

    ["Cloud Serpent"] = {
        label       = "Cloud Serpent Taming",
        desc        = "Pandaren hunters know this automatically. Others learn from How to School Your Serpent (Exalted, Order of the Cloud Serpent). Account-wide.",
        hint        = { autoRace = "Pandaren", itemID = 183123, itemName = "How to School Your Serpent" },
        itemID      = 183123,
        accountWide = true,
        check = {
            autoRaces = { RACE_IDS.Pandaren, RACE_IDS.PandarenAlliance, RACE_IDS.PandarenHorde },
            spellID   = 340826,
            questID   = 62254,
        },
    },

    ["Mechanical"] = {
        label       = "Mechanical Taming",
        desc        = "Gnome, Goblin and Mechagnome hunters know this automatically. Others acquire Mecha-Bond Imprint Matrix. NOT Account-wide.",
        hint        = { autoRace = "Gnome/Goblin/Mechagnome", itemID = 134125, itemName = "Mecha-Bond Imprint Matrix" },
        itemID      = 134125,
        accountWide = false,
        check = {
            autoRaces = { RACE_IDS.Gnome, RACE_IDS.Goblin, RACE_IDS.Mechagnome },
            spellID   = 205154,
        },
    },

    ["Ottuk"] = {
        label       = "Ottuk Taming",
        desc        = "Account-wide. Earned via Iskaara Tuskarr Renown 11 quest chain (any character). Account-wide.",
        hint        = { questID = 66444, questName = "While the Iron Is Hot", suffix = "(Iskaara Tuskarr Renown 11)" },
        accountWide = true,
        check = {
            spellID = 390631,
            questID = 71184,
        },
    },

    ["Gargon"] = {
        label       = "Gargon Taming",
        desc        = "Learned from Gargon Training Manual (Huntmaster Petrus, Revendreth). Requires level 60. Account-wide.",
        hint        = { itemID = 180705, itemName = "Gargon Training Manual" },
        itemID      = 180705,
        accountWide = true,
        check = {
            spellID = 334850,
            questID = 61160,
        },
    },

    ["Sliver of N'Zoth"] = {
        label       = "N'lyeth, Sliver of N'Zoth",
        desc        = "Allows taming of specific friendly/neutral NPCs. Requires the toy N'lyeth, Sliver of N'Zoth used while in War Mode. Account-wide.",
        hint        = { itemID = 173951, itemName = "N'lyeth, Sliver of N'Zoth", suffix = "+ War Mode" },
        isCondition = true,
        itemID      = 173951,
        accountWide = true,
        check = {
            toyID = 173951,
        },
    },

    ["Fire Owl"] = {
        label       = "Fire Owl Taming",
        desc        = "Account-wide. Earned via Cinder of Companionship, awarded when learning Reins of Anu'relos, Flame's Guidance (Mythic Fyrakk, Amirdrassil). Account-wide.",
        hint        = { itemID = 211314, itemName = "Cinder of Companionship" },
        itemID      = 211314,
        accountWide = true,
        check = {
            spellID = 428736,
            questID = 78842,
        },
    },
}

-- ---------------------------------------------------------------------------
-- Internal: evaluate a single rule against the current character
-- Returns "met" or "not_met"
-- ---------------------------------------------------------------------------
local function EvaluateRule(rule)
    local c = rule.check

    -- Spec + level check (Exotic Family)
    if c.spec then
        local specID = GetSpecializationInfo(GetSpecialization())
        local level  = UnitLevel("player")
        if specID == c.spec and level >= c.level then
            return "met"
        end
        return "not_met"
    end

    -- Toy check (Friendly Taming)
    if c.toyID then
        return PlayerHasToy(c.toyID) and "met" or "not_met"
    end

    -- Auto-race short-circuit (OR among listed race IDs)
    if c.autoRaces then
        local _, _, playerRaceID = UnitRace("player")
        for _, raceID in ipairs(c.autoRaces) do
            if playerRaceID == raceID then
                return "met"
            end
        end
    end

    -- Spell check
    if c.spellID and IsPlayerSpell(c.spellID) then
        return "met"
    end

    -- Quest flag fallback (account-wide unlocks only)
    if c.questID and C_QuestLog.IsQuestFlaggedCompleted(c.questID) then
        return "met"
    end

    return "not_met"
end

-- ---------------------------------------------------------------------------
-- Cache: avoid re-evaluating rules every frame
-- Cleared on PLAYER_SPECIALIZATION_CHANGED and SPELLS_CHANGED
-- ---------------------------------------------------------------------------
local statusCache = {}

local cacheFrame = CreateFrame("Frame")
cacheFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
cacheFrame:RegisterEvent("SPELLS_CHANGED")
cacheFrame:SetScript("OnEvent", function()
    statusCache = {}
end)

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- Returns the evaluated status for a single rule key, with caching.
-- @param ruleKey string  : e.g. "Florafaun Taming"
-- @return "met" | "not_met" | "unknown" (if rule key not found)
function PSM.TamingChecker.GetRuleStatus(ruleKey)
    if statusCache[ruleKey] ~= nil then
        return statusCache[ruleKey]
    end
    local rule = PSM.TamingRules[ruleKey]
    if not rule then
        return "unknown"
    end
    local status = EvaluateRule(rule)
    statusCache[ruleKey] = status
    return status
end

-- Returns an array of {label, desc, itemID, status} for all taming requirements
-- on a model record. Pass the model's data record (expected to have .taming = {...}).
-- Returns an empty table if the model has no special taming requirements.
-- @param modelData table : record with optional modelData.taming = { "Direhorn", ... }
-- @return table          : array of { label, desc, itemID, status }
function PSM.TamingChecker.GetModelStatus(modelData)
    local result = {}
    if not modelData or not modelData.taming then return result end
    for _, ruleKey in ipairs(modelData.taming) do
        local rule   = PSM.TamingRules[ruleKey]
        local status = PSM.TamingChecker.GetRuleStatus(ruleKey)
        result[#result + 1] = {
            label  = rule and rule.label  or ruleKey,
            desc   = rule and rule.desc   or "",
            itemID = rule and rule.itemID or nil,
            status = status,
        }
    end
    return result
end