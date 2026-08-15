-- Data.lua
-- Data management and collection for PetStableManagement

local addonName = "PetStableManagement"

_G.PSM = _G.PSM or {}
local PSM = _G.PSM

PSM.Data = {}

local GetCharacterKey = function() return PSM.GetCharacterKey() end

-- ─── Utilities ────────────────────────────────────────────────────────────────

PSM.Data.DeepCopyPet = PSM.Utils.DeepCopy  -- backward-compat alias

local EXOTIC_FAMILIES = {
    ["Aqiri"] = true, ["Carapid"] = true, ["Chimaera"] = true,
    ["Core Hound"] = true, ["Devilsaur"] = true, ["Pterrordax"] = true,
    ["Shale Beast"] = true, ["Spirit Beast"] = true, ["Stone Hound"] = true,
    ["Water Strider"] = true, ["Whiptail"] = true, ["Worm"] = true,
}

-- Expose for other modules
function PSM.Data.IsExoticFamily(familyName)
    return EXOTIC_FAMILIES[familyName] or false
end

-- ─── DB helpers ───────────────────────────────────────────────────────────────

local function EnsureDB()
    PetStableManagementDB = PetStableManagementDB or {}
    PetStableManagementDB.characters = PetStableManagementDB.characters or {}
    PetStableManagementDB.accountWide = PetStableManagementDB.accountWide or {}
    return PetStableManagementDB
end

local function GetCharacterSettings()
    local db   = EnsureDB()
    local key  = GetCharacterKey()
    local char = db.characters[key] or {}
    db.characters[key] = char
    char.settings = char.settings or {}
    return char.settings
end

local function GetAccountWide()
    return EnsureDB().accountWide
end

-- ─── Filter settings ──────────────────────────────────────────────────────────

-- selectedModelsFamilies/selectedExpansions/selectedLocations are deliberately NOT here --
-- ModelsFilters.lua owns their persistence directly (PetStableManagementDB.filters), like
-- showRares/showFavorites/etc. Routing them through this generic pipeline meant any
-- unrelated panel closing before the Models Browser ever built its filter state would save
-- its untouched {} default as real data, permanently overriding "all selected" on next login.
local FILTER_KEYS = {
    "sortBy", "exoticFilter", "duplicatesOnlyFilter",
    "selectedSpecs", "selectedFamilies", "selectedTamers",
    "selectedTamingRules", "selectedConditions",
}

local TABLE_FILTER_KEYS = {
    selectedSpecs = true, selectedFamilies = true, selectedTamers = true,
    selectedTamingRules = true, selectedConditions = true,
}

local NIL_FILTER_KEYS = {
    sortBy = true,
    exoticFilter = true,
    duplicatesOnlyFilter = true,
}

local function LoadFilterSettings(src)
    if not src then return end
    for _, k in ipairs(FILTER_KEYS) do
        if TABLE_FILTER_KEYS[k] then
            -- Absent from src means "nothing saved yet", not "saved as empty" -- don't
            -- force PSM.state's existing value to {}.
            if src[k] ~= nil then
                PSM.state[k] = PSM.Utils.DeepCopy(src[k])
            end
        elseif NIL_FILTER_KEYS[k] then
            PSM.state[k] = src[k] or nil
        else
            PSM.state[k] = src[k] or false
        end
    end
end

-- ─── Persistence ──────────────────────────────────────────────────────────────

function PSM.Data:SavePersistentData()
    local db    = EnsureDB()
    local key   = GetCharacterKey()
    local char  = db.characters[key] or {}
    db.characters[key] = char

    db.version     = "2.0.0"
    db.lastUpdated = date and date("%Y-%m-%d %H:%M:%S") or tostring(time())

    char.snapshotData = {}
    local count = 0
    for _, pet in ipairs(PSM.state.stablePets) do
        if pet.tamer == key then
            table.insert(char.snapshotData, PSM.Utils.DeepCopy(pet))
            count = count + 1
        end
    end

    self:SaveSettings()
    collectgarbage("collect")
    return count
end

function PSM.Data:SaveSettings()
    local db  = EnsureDB()
    local key = GetCharacterKey()

    -- Determine page to save, preserving existing value if unavailable
    local currentPage = PSM.state.modelsPanelCurrentPage
        or (PSM.state.modelsPanel and PSM.state.modelsPanel.currentPage)

    -- Skip during panel initialization (panel exists but isn't visible and no page yet)
    if PSM.state.modelsPanel and not PSM.state.modelsPanel:IsVisible() and currentPage == nil then
        return
    end

    local char = db.characters[key] or {}
    db.characters[key] = char
    local savedPage = char.settings and char.settings.modelsPanelCurrentPage

    local aw = GetAccountWide()
    -- Don't overwrite favorites until they've actually been loaded this session.
    if PSM.state.favoriteModelsLoaded then
        aw.favoriteModels = PSM.Utils.DeepCopy(PSM.state.favoriteModels) or {}
    end
    aw.modelViews          = PSM.Utils.DeepCopy(PSM.state.modelViews) or {}
    aw.popupZoom           = PSM.state.popupZoom or 0.25
    aw.globalModelRotation = PSM.state.globalModelRotation or math.pi * 2

    char.settings = {
            sortBy                 = PSM.state.sortBy or nil,
            exoticFilter           = PSM.state.exoticFilter or false,
            duplicatesOnlyFilter   = PSM.state.duplicatesOnlyFilter or false,
            selectedSpecs          = PSM.Utils.DeepCopy(PSM.state.selectedSpecs) or {},
            selectedFamilies       = PSM.Utils.DeepCopy(PSM.state.selectedFamilies) or {},
            selectedTamers         = PSM.Utils.DeepCopy(PSM.state.selectedTamers) or {},
            selectedTamingRules    = PSM.Utils.DeepCopy(PSM.state.selectedTamingRules) or {},
            selectedConditions     = PSM.Utils.DeepCopy(PSM.state.selectedConditions) or {},
            modelsPanelCurrentPage = currentPage or savedPage or 1,
            tamerSelectionInitialized = PSM.state.tamerSelectionInitialized or false,
            minimapButton = (db.settings and db.settings.minimapButton) or {
                hide = false, minimapPos = 220, lock = false,
            },
        }
end

function PSM.Data:LoadPersistentDataForDisplay(preserveCurrentData)
    local db = PetStableManagementDB
    if not db then return false end

    -- Migrate legacy flat structure
    if not db.characters and db.snapshotData then
        local key = GetCharacterKey()
        db.characters = { [key] = { snapshotData = db.snapshotData, settings = db.settings or {} } }
        db.snapshotData = nil
        db.settings     = nil
    end
    if not db.characters then return false end

    if not preserveCurrentData then
        PSM.state.stablePets = {}
        self:ClearMemory(false)

        -- Always load current character first, then load from other characters
        local currentKey = GetCharacterKey()
        local currentCharData = db.characters[currentKey]
        if type(currentCharData) == "table" and type(currentCharData.snapshotData) == "table" then
            for _, pet in ipairs(currentCharData.snapshotData) do
                if type(pet) == "table" and pet.name and pet.icon then
                    local p = PSM.Utils.DeepCopy(pet)
                    p.tamer = currentKey
                    p.guid  = p.guid or p.petNumber
                    self:NormalizePetData(p)
                    table.insert(PSM.state.stablePets, p)
                end
            end
        end

        -- Load from up to 10 most-recently-updated OTHER characters
        local keys = {}
        for k in pairs(db.characters) do 
            if k ~= currentKey then
                keys[#keys + 1] = k
            end
        end
        table.sort(keys, function(a, b)
            local at = (db.characters[a] or {}).lastUpdated or 0
            local bt = (db.characters[b] or {}).lastUpdated or 0
            return at > bt
        end)

        local loaded = 0
        for _, charKey in ipairs(keys) do
            if loaded >= 10 then break end
            local charData = db.characters[charKey]
            if type(charData.snapshotData) == "table" then
                for _, pet in ipairs(charData.snapshotData) do
                    if type(pet) == "table" and pet.name and pet.icon then
                        local p = PSM.Utils.DeepCopy(pet)
                        p.tamer = charKey
                        p.guid  = p.guid or p.petNumber
                        self:NormalizePetData(p)
                        table.insert(PSM.state.stablePets, p)
                    end
                end
                loaded = loaded + 1
            end
        end

        if #PSM.state.stablePets == 0 then return false end
    end

    self:RebuildSpecAndFamilyLists()
    self:RebuildTamerList()

    local key = GetCharacterKey()
    local src = (db.characters[key] or {}).settings or db.settings
    LoadFilterSettings(src)

    -- Clear tamer selection only if we're coming from a stable session
    if not PSM.state.isStableOpen and PSM.state.wasStableSession then
        PSM.Utils:ClearTable(PSM.state.selectedTamers)
        PSM.state.tamerSelectionInitialized = true
        PSM.state.wasStableSession = false
    elseif PSM.state.isStableOpen and not next(PSM.state.selectedTamers) then
        if PSM.UI and PSM.UI.SetDefaultTamerSelection then
            PSM.UI:SetDefaultTamerSelection()
        end
    end

    self:MigrateCharacterFavoritesToAccountWide()

    local aw = GetAccountWide()
    PSM.state.favoriteModels = PSM.Utils.DeepCopy(aw.favoriteModels) or {}
    PSM.state.favoriteModelsLoaded = true

    return true
end

function PSM.Data:LoadSettingsOnly()
    local db  = PetStableManagementDB
    local key = GetCharacterKey()
    local src = db and db.characters and (db.characters[key] or {}).settings
             or db and db.settings

    LoadFilterSettings(src)

    if src then
        PSM.state.tamerSelectionInitialized = src.tamerSelectionInitialized or false
        if src.modelsPanelCurrentPage ~= nil then
            PSM.state.modelsPanelCurrentPage = src.modelsPanelCurrentPage
        end
    end

    if PSM.UI and PSM.UI.SetDefaultTamerSelection then
        PSM.UI:SetDefaultTamerSelection()
    end

    -- Global override from saved variable (non-zero takes precedence)
    if _G.PSM_modelsPanelCurrentPage and _G.PSM_modelsPanelCurrentPage ~= 0 then
        PSM.state.modelsPanelCurrentPage = _G.PSM_modelsPanelCurrentPage
    else
        PSM.state.modelsPanelCurrentPage = PSM.state.modelsPanelCurrentPage or 1
    end

    self:MigrateCharacterFavoritesToAccountWide()

    local aw = GetAccountWide()
    PSM.state.favoriteModels      = PSM.Utils.DeepCopy(aw.favoriteModels) or {}
    PSM.state.favoriteModelsLoaded = true
    PSM.state.modelViews          = PSM.Utils.DeepCopy(aw.modelViews) or {}
    PSM.state.popupZoom           = aw.popupZoom or 0.25
    PSM.state.globalModelRotation = aw.globalModelRotation or math.pi * 2
end

-- ─── Snapshots & migration ────────────────────────────────────────────────────

function PSM.Data:CreateSnapshot()
    local count = self:SavePersistentData()
    if count > 0 then
        print("|cFF00FF00PetStableManagement: Saved " .. count .. " pets to database.|r")
    end
end

function PSM.Data:GetFormattedTimestamp()
    local db = PetStableManagementDB
    if not db or not db.lastUpdated then return "Never" end
    local ts = db.lastUpdated
    return type(ts) == "number" and date("%Y-%m-%d %H:%M:%S", ts) or tostring(ts)
end

function PSM.Data:MigrateCharacterFavoritesToAccountWide()
    local db = PetStableManagementDB
    if not db or not db.characters then return end
    local aw = GetAccountWide()
    if aw.favoriteModels then return end  -- already migrated

    local merged = {}
    for _, charData in pairs(db.characters) do
        if charData.settings and charData.settings.favoriteModels then
            for displayId, isFav in pairs(charData.settings.favoriteModels) do
                if isFav then merged[displayId] = true end
            end
        end
    end
    aw.favoriteModels = merged
end

-- ─── Pet collection ───────────────────────────────────────────────────────────

function PSM.Data:CollectStablePets()
    if not PSM.state.isStableOpen then
        print("|cFFFF0000ERROR: CollectStablePets called when stable is NOT open!|r")
        return 0, 0
    end

    PSM.state.stablePets = {}
    self:ClearMemory(true)

    if not PSM.GetStableFrame() then
        print(PSM.Config.MESSAGES.STABLE_FRAME_NOT_FOUND)
        return 0, 0
    end

    self:CollectActivePets()
    local collected, expected = self:CollectStabledPets()
    self:RebuildSpecAndFamilyLists()
    self:ValidateCollectedData()

    return #PSM.state.stablePets, expected
end

function PSM.Data:CollectActivePets()
    if not PSM.C_StableInfo or not PSM.C_StableInfo.GetStablePetInfo then return end
    for slot = 1, PSM.Config.ACTIVE_PET_SLOTS do
        local petInfo = PSM.Utils.SafeCall(PSM.C_StableInfo.GetStablePetInfo, slot)
        if petInfo and petInfo.name and petInfo.icon then
            local pet = self:ProcessPetInfo(petInfo, slot, true)
            if pet then table.insert(PSM.state.stablePets, pet) end
        end
    end
end

-- ─── Derived-field cache ──────────────────────────────────────────────────────
-- Abilities/exotic-status/family/spec are expensive to derive but pure
-- functions of level+species+spec, so they're cached by identity + a
-- fingerprint of those inputs. Never caches identity/position fields
-- (slotID, isActive, name, etc.) -- those always come fresh from the live
-- API, so stale/duplicate records can't happen.
PSM._petDerivedCache = PSM._petDerivedCache or {}

local function PetFingerprint(info)
    return tostring(info.level or 0) .. "|" .. tostring(info.speciesID or info.displayID or 0)
        .. "|" .. tostring(info.specID or info.specId or 0)
end

function PSM.Data:GetCachedDerivedFields(petKey, fingerprint)
    local entry = PSM._petDerivedCache[petKey]
    if entry and entry.fingerprint == fingerprint then
        return entry.abilities, entry.isExotic, entry.familyName, entry.specName
    end
    return nil
end

function PSM.Data:SetCachedDerivedFields(petKey, fingerprint, abilities, isExotic, familyName, specName)
    PSM._petDerivedCache[petKey] = {
        fingerprint = fingerprint,
        abilities   = abilities,
        isExotic    = isExotic,
        familyName  = familyName,
        specName    = specName,
    }
end

function PSM.Data:CollectStabledPets()
    local stableFrame    = PSM.GetStableFrame()
    local stabledPetList = stableFrame and stableFrame.StabledPetList
    local scrollBox = stabledPetList and stabledPetList.ScrollBox
    local dataProvider = scrollBox and scrollBox:GetDataProvider()
    if not dataProvider then return 0, 0 end

    local collected, collectedKeys = {}, {}
    local expectedCount = 0
    pcall(function() expectedCount = dataProvider:GetSize(false) or 0 end)

    local function processPet(petData)
        if not petData or not petData.icon then return end
        local key = tostring(petData.petNumber or petData.guid
                    or (petData.name .. "_" .. tostring(petData.displayID)))
        if collectedKeys[key] then return end
        collectedKeys[key] = true

        local p = PSM.Utils.DeepCopy(petData)
        p.isActive    = false
        p.guid        = p.guid or p.petNumber
        p.modelSceneID = p.modelSceneID or 783
        p.tamer       = PSM.GetCharacterKey()
        -- Stabled pets arrive as a copy of Blizzard's record and keep whatever it has;
        -- active pets are built field by field in ProcessPetInfo. Both must end up with
        -- the same shape, or a consumer reads a key that only one path fills.
        p.level       = p.level or 0
        p._originalData = nil

        local fingerprint = PetFingerprint(p)
        local abilities, isExotic, familyName, specName = self:GetCachedDerivedFields(key, fingerprint)
        if abilities then
            p.abilities, p.isExotic, p.familyName, p.specName = abilities, isExotic, familyName, specName
        else
            self:NormalizePetData(p)
            p.abilities = self:ExtractPetAbilities(p)
            self:SetCachedDerivedFields(key, fingerprint, p.abilities, p.isExotic, p.familyName, p.specName)
        end

        if p.name then table.insert(collected, p) end
    end

    -- Primary: ForEach
    pcall(function()
        dataProvider:ForEach(function(node)
            pcall(function() processPet(node:GetData()) end)
        end, false)
    end)

    -- Fallback: C_StableInfo API
    if #collected == 0 or (expectedCount > 0 and #collected < expectedCount) then
        pcall(function()
            if C_StableInfo and C_StableInfo.GetStablePetInfo then
                for slot = 7, PSM.Config.MAX_STABLE_SLOTS do
                    pcall(function()
                        local petInfo = C_StableInfo.GetStablePetInfo(slot)
                        if petInfo and petInfo.name and petInfo.icon then
                            processPet(petInfo)
                        end
                    end)
                end
            end
        end)
    end

    for _, pet in ipairs(collected) do
        table.insert(PSM.state.stablePets, pet)
    end
    return #collected, expectedCount
end

-- ─── Pet data helpers ─────────────────────────────────────────────────────────

function PSM.Data:ProcessPetInfo(petInfo, slotID, isActive)
    if not petInfo or not petInfo.name or not petInfo.icon then return nil end

    local petKey = tostring(petInfo.petNumber or petInfo.guid
                   or (petInfo.name .. "_" .. tostring(petInfo.displayID)))
    local fingerprint = PetFingerprint(petInfo)
    local abilities, isExotic, familyName, specName = self:GetCachedDerivedFields(petKey, fingerprint)
    if not abilities then
        familyName = self:GetPetFamilyName(petInfo)
        specName   = self:GetPetSpecName(petInfo)
        isExotic   = self:GetPetExoticStatus(petInfo)
        abilities  = self:ExtractPetAbilities(petInfo)
        self:SetCachedDerivedFields(petKey, fingerprint, abilities, isExotic, familyName, specName)
    end

    return {
        slotID     = slotID,
        name       = petInfo.name,
        icon       = petInfo.icon,
        displayID  = petInfo.displayID or 0,
        petNumber  = petInfo.petNumber or 0,
        guid       = petInfo.petNumber or 0,
        level      = petInfo.level or 0,
        familyName = familyName,
        specName   = specName,
        specID     = petInfo.specID or petInfo.specId,
        isExotic   = isExotic,
        isActive   = isActive,
        abilities  = abilities,
        modelSceneID = 783,
        tamer      = PSM.GetCharacterKey(),
    }
end

function PSM.Data:GetPetSpecName(pet)
    if not pet then return nil end
    return pet.specName or pet.specialization or nil
end

function PSM.Data:GetPetFamilyName(pet)
    if not pet then return nil end
    if pet.familyName and pet.familyName ~= "" then return pet.familyName end
    if pet.family and pet.family.name and pet.family.name ~= "" then return pet.family.name end
    return "Unknown"
end

function PSM.Data:GetPetExoticStatus(petInfo)
    if not petInfo then return false end
    if petInfo.isExotic ~= nil then return petInfo.isExotic end
    if petInfo.Exotic then return true end
    if petInfo.petNumber and C_PetJournal then
        local ok, isExotic = pcall(function()
            local stats = C_PetJournal.GetPetStats(petInfo.petNumber)
            return stats and stats.isExotic
        end)
        if ok and isExotic then return true end
    end
    return EXOTIC_FAMILIES[self:GetPetFamilyName(petInfo)] or false
end

function PSM.Data:NormalizePetData(pet)
    if not pet then return end
    if not pet.familyName or pet.familyName == "" then
        pet.familyName = self:GetPetFamilyName(pet)
    end
    if not pet.specName or pet.specName == "" then
        pet.specName = self:GetPetSpecName(pet) or "Unknown"
    end
    if pet.isExotic == nil then
        pet.isExotic = self:GetPetExoticStatus(pet)
    end
end

function PSM.Data:ValidateCollectedData()
    local valid = {}
    for _, pet in ipairs(PSM.state.stablePets) do
        if type(pet) == "table" and pet.name then
            pet.icon       = (pet.icon and pet.icon ~= "") and pet.icon
                             or "Interface\\Icons\\INV_Misc_QuestionMark"
            pet.displayID  = pet.displayID or 0
            pet.familyName = (pet.familyName ~= "") and pet.familyName or "Unknown"
            pet.specName   = (pet.specName   ~= "") and pet.specName   or "Unknown"
            pet.isExotic   = pet.isExotic ~= nil and pet.isExotic or false
            valid[#valid + 1] = pet
        end
    end
    PSM.state.stablePets = valid
end

function PSM.Data:ExtractPetAbilities(petInfo)
    local abilities = { family = {}, spec = {}, pet = {}, unknown = {} }
    local seen = {}

    local function addTo(list, ability)
        local name = self:GetAbilityName(ability)
        if name and not seen[name] then
            seen[name] = true
            list[#list + 1] = name
        end
    end

    if type(petInfo.specAbilities) == "table" then
        for _, a in ipairs(petInfo.specAbilities) do addTo(abilities.spec, a) end
    end
    if type(petInfo.petAbilities) == "table" then
        for _, a in ipairs(petInfo.petAbilities) do addTo(abilities.pet, a) end
    end
    if type(petInfo.abilities) == "table" then
        local hasSpecific = #abilities.spec > 0 or #abilities.pet > 0
        for _, a in ipairs(petInfo.abilities) do
            addTo(hasSpecific and abilities.family or abilities.unknown, a)
        end
    end
    return abilities
end

function PSM.Data:GetAbilityName(ability)
    if type(ability) == "number"  then return PSM.Utils:GetSpellNameCompat(ability) end
    if type(ability) == "string"  then return ability end
    if type(ability) == "table"   then return ability.name or ability.Name end
    return nil
end

-- ─── List rebuilding ──────────────────────────────────────────────────────────

function PSM.Data:RebuildSpecAndFamilyLists()
    local specSet, familySet = {}, {}
    PSM.state.specList, PSM.state.familyList = {}, {}

    for _, pet in ipairs(PSM.state.stablePets) do
        local spec   = self:GetPetSpecName(pet)
        local family = self:GetPetFamilyName(pet)
        if spec   and not specSet[spec]     then specSet[spec]     = true; PSM.state.specList[#PSM.state.specList + 1]     = spec   end
        if family and not familySet[family] then familySet[family] = true; PSM.state.familyList[#PSM.state.familyList + 1] = family end
    end

    table.sort(PSM.state.specList)
    table.sort(PSM.state.familyList)
end

function PSM.Data:RebuildTamerList()
    local seen = {}
    PSM.state.tamerList = {}
    for _, pet in ipairs(PSM.state.stablePets) do
        local t = pet.tamer
        if t and not seen[t] then
            seen[t] = true
            PSM.state.tamerList[#PSM.state.tamerList + 1] = t
        end
    end
    table.sort(PSM.state.tamerList)
end

-- ─── Memory management ────────────────────────────────────────────────────────

function PSM.Data:ClearMemory(preserveFilters)
    if not preserveFilters then
        PSM.state.stablePets = {}
    else
        PSM.state.stablePets = PSM.state.stablePets or {}
    end

    PSM.state.stablePetsSnapshot = {}
    PSM.state.specList   = {}
    PSM.state.familyList = {}

    if PSM.state.tamerList then
        PSM.state.tamerList = {}
    end

    if not preserveFilters then
        PSM.state.selectedSpecs    = {}
        PSM.state.selectedFamilies = {}
        PSM.state.selectedTamers   = {}
        PSM.state.selectedTamingRules = {}
        PSM.state.selectedConditions  = {}
    end

    if PSM.Config.FORCE_GC_ON_CLEAR then
        collectgarbage("collect")
    end
end

function PSM.Data:ClearUIRows()
    local function clearModel(m)
        if not m then return end
        m:Hide(); m:ClearModel()
        m.isRotating = false
        PSM.RowManager:ReleaseModel(m)
    end

    -- List view
    for _, row in ipairs(PSM.state.rows or {}) do
        if row then
            clearModel(row.model)
            if row.text          then row.text:SetText("") end
            if row.abilitiesList then row.abilitiesList:SetText("") end
            row:Hide()
        end
    end

    -- Grid view
    for _, row in ipairs(PSM.state.modelViewRows or {}) do
        if row then
            clearModel(row.model)
            row.petData = nil
            row:Hide()
        end
    end

    -- Grouped view rows
    for _, row in ipairs(PSM.state.groupedViewRows or {}) do
        if row then
            clearModel(row.model)
            row.petData, row.groupId, row.groupIndex, row.contextMenuPet = nil, nil, nil, nil
            if row.model then row.model.contextMenuPet = nil end
            row:Hide()
        end
    end

    -- Grouped view headers
    for _, header in ipairs(PSM.state.groupedViewHeaders or {}) do
        if header then
            header:Hide()
            header.groupId, header.groupName = nil, nil
            header:SetScript("OnEnter",    nil)
            header:SetScript("OnLeave",    nil)
            header:SetScript("OnMouseDown", nil)
        end
    end

    if PSM.UI and PSM.UI.GroupedView and PSM.UI.GroupedView.ClearLayout then
        PSM.UI.GroupedView:ClearLayout()
    end

    if PSM.Config.FORCE_GC_ON_CLEAR then
        collectgarbage("collect")
    end
end

-- ─── Teams panel settings ─────────────────────────────────────────────────────

function PSM.Data:GetTeamsPanelWidth()    return GetCharacterSettings().teamsPanelWidth  end
function PSM.Data:GetTeamsPanelHeight()   return GetCharacterSettings().teamsPanelHeight end
function PSM.Data:GetTeamsPanelPosition() return GetCharacterSettings().teamsPanelPosition end

function PSM.Data:SetTeamsPanelSize(width, height)
    local s = GetCharacterSettings()
    s.teamsPanelWidth, s.teamsPanelHeight = width, height
    self:SaveSettings()
end

function PSM.Data:SetTeamsPanelPosition(point, relativeTo, relativePoint, x, y)
    GetCharacterSettings().teamsPanelPosition = {
        point = point, relativeTo = relativeTo,
        relativePoint = relativePoint, x = x, y = y,
    }
    self:SaveSettings()
end
