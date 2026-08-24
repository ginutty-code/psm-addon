-- Data.lua
-- Data management and collection for PetStableManagement

local _, ns = ...

ns.Data = {}

local GetCharacterKey = function() return ns.GetCharacterKey() end

-- ─── Utilities ────────────────────────────────────────────────────────────────

ns.Data.DeepCopyPet = ns.Utils.DeepCopy  -- backward-compat alias

local EXOTIC_FAMILIES = {
    ["Aqiri"] = true, ["Carapid"] = true, ["Chimaera"] = true,
    ["Core Hound"] = true, ["Devilsaur"] = true, ["Pterrordax"] = true,
    ["Shale Beast"] = true, ["Spirit Beast"] = true, ["Stone Hound"] = true,
    ["Water Strider"] = true, ["Whiptail"] = true, ["Worm"] = true,
}

-- Expose for other modules
function ns.Data.IsExoticFamily(familyName)
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

-- ─── Abilities pool ───────────────────────────────────────────────────────────
-- Family-linked and spec-linked ability spell IDs are pure functions of family/spec
-- respectively -- confirmed in-game (2026-08-21): every pet sharing a family carries
-- identical petAbilities IDs, every pet sharing a spec carries identical specAbilities
-- IDs. So instead of persisting the resolved ability list on every one of up to 205
-- pets per character, this pool remembers the raw spell-ID list once per family/spec,
-- account-wide, and every pet reconstructs its own abilities from it by looking up its
-- (already-persisted) familyName/specName. isExotic can differ from its family's usual
-- value for an individual pet grandfathered before a Blizzard family-rule change (the
-- Clefthoof case), so it is NOT derived this way -- it stays persisted per pet, and
-- this pool only supplies a better-informed fallback for the rare case a record is
-- missing it entirely, never an override of a value already on disk.
--
-- Bounded and small by construction: at most ~61 families and 3 specs will ever have
-- entries. A family/spec can only be missing here if this account has never once
-- collected a pet of it -- which also means no persisted pet record could need it.
local function GetAbilitiesPool()
    local aw = GetAccountWide()
    aw.abilitiesPool = aw.abilitiesPool or {}
    local pool = aw.abilitiesPool
    pool.byFamily         = pool.byFamily         or {}
    pool.bySpec           = pool.bySpec           or {}
    pool.specIdBySpecName = pool.specIdBySpecName or {}
    pool.exoticByFamily   = pool.exoticByFamily   or {}
    return pool
end

-- Called from live collection only (CollectStabledPets/ProcessPetInfo), with the raw
-- Blizzard spell-ID arrays -- never with already-resolved ability names.
function ns.Data:RecordAbilitiesObservation(familyName, specName, specID, isExotic, petAbilities, specAbilities)
    local pool = GetAbilitiesPool()
    if familyName and type(petAbilities) == "table" and #petAbilities > 0 then
        pool.byFamily[familyName] = petAbilities
    end
    if specName and type(specAbilities) == "table" and #specAbilities > 0 then
        pool.bySpec[specName] = specAbilities
    end
    if specName and specID then
        pool.specIdBySpecName[specName] = specID
    end
    if familyName and isExotic ~= nil then
        pool.exoticByFamily[familyName] = isExotic
    end
end

function ns.Data:GetPoolSpecID(specName)
    if not specName then return nil end
    return GetAbilitiesPool().specIdBySpecName[specName]
end

-- Rebuilds the same {family={}, spec={}, pet={}, unknown={}} shape ExtractPetAbilities
-- produces live. `family`/`unknown` stay empty here on purpose: confirmed in-game that
-- modern Blizzard stable-pet records carry no generic `abilities` field at all (only
-- `specAbilities`/`petAbilities`), so those two buckets are already always empty today,
-- live or reconstructed -- this isn't a simplification, it's what the real data does.
function ns.Data:GetPoolAbilities(familyName, specName)
    local pool = GetAbilitiesPool()
    local result = { family = {}, spec = {}, pet = {}, unknown = {} }
    local seen = {}
    local function addTo(list, ability)
        local name = self:GetAbilityName(ability)
        if name and not seen[name] then
            seen[name] = true
            list[#list + 1] = name
        end
    end
    for _, id in ipairs(pool.bySpec[specName] or {}) do addTo(result.spec, id) end
    for _, id in ipairs(pool.byFamily[familyName] or {}) do addTo(result.pet, id) end
    return result
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

-- An empty table and an absent key already load identically -- see the comment in
-- LoadFilterSettings below -- so persisting {} for a filter nobody has touched is pure
-- weight: 15 characters x 5 of these keys is 75 saved tables holding nothing.
local function DeepCopyIfNonEmpty(t)
    if t and next(t) then
        return ns.Utils.DeepCopy(t)
    end
    return nil
end

local function LoadFilterSettings(src)
    if not src then return end
    for _, k in ipairs(FILTER_KEYS) do
        if TABLE_FILTER_KEYS[k] then
            -- Absent from src means "nothing saved yet", not "saved as empty" -- don't
            -- force PSM.state's existing value to {}.
            if src[k] ~= nil then
                ns.state[k] = ns.Utils.DeepCopy(src[k])
            end
        elseif NIL_FILTER_KEYS[k] then
            ns.state[k] = src[k] or nil
        else
            ns.state[k] = src[k] or false
        end
    end
end

-- ─── Persistence ──────────────────────────────────────────────────────────────

function ns.Data:SavePersistentData()
    local db    = EnsureDB()
    local key   = GetCharacterKey()
    local char  = db.characters[key] or {}
    db.characters[key] = char

    db.version     = "2.0.0"
    db.lastUpdated = date and date("%Y-%m-%d %H:%M:%S") or tostring(time())

    char.snapshotData = {}
    local count = 0
    for _, pet in ipairs(ns.state.stablePets) do
        if pet.tamer == key then
            local p = ns.Utils.DeepCopy(pet)
            -- Dropped on the way to disk, not out of the live pet: `modelSceneID` is
            -- always the constant 783, `guid` always equals `petNumber`, and `tamer` is
            -- re-derived from the character key this record is already nested under --
            -- LoadPersistentDataForDisplay overwrites all three the moment it loads a
            -- snapshot, so storing them is 205-pets-per-character of pure duplication.
            p.modelSceneID = nil
            p.guid         = nil
            p.tamer        = nil
            -- `abilities` and `specID` are reconstructed on load from the abilities
            -- pool (see GetPoolAbilities/GetPoolSpecID above) keyed by the familyName/
            -- specName this same record still carries -- confirmed in-game that both
            -- are pure functions of family/spec, identical across every pet sharing
            -- one. `isExotic`/`specName` are NOT stripped here: specName is a mutable,
            -- player-chosen fact (re-specced at the stable master) with no fixed
            -- relationship to family, and isExotic can genuinely differ from its
            -- family's current default for an individual pet grandfathered before a
            -- Blizzard family-rule change -- only the per-pet stored value protects
            -- that case, so both stay.
            p.abilities    = nil
            p.specID       = nil
            table.insert(char.snapshotData, p)
            count = count + 1
        end
    end

    self:SaveSettings()
    return count
end

function ns.Data:SaveSettings()
    local db  = EnsureDB()
    local key = GetCharacterKey()

    -- Determine page to save, preserving existing value if unavailable
    local currentPage = ns.state.modelsPanelCurrentPage
        or (ns.state.modelsPanel and ns.state.modelsPanel.currentPage)

    -- Skip during panel initialization (panel exists but isn't visible and no page yet)
    if ns.state.modelsPanel and not ns.state.modelsPanel:IsVisible() and currentPage == nil then
        return
    end

    local char = db.characters[key] or {}
    db.characters[key] = char
    local savedPage = char.settings and char.settings.modelsPanelCurrentPage

    local aw = GetAccountWide()
    -- Don't overwrite favorites until they've actually been loaded this session.
    if ns.state.favoriteModelsLoaded then
        aw.favoriteModels = ns.Utils.DeepCopy(ns.state.favoriteModels) or {}
    end
    aw.modelViews          = ns.Utils.DeepCopy(ns.state.modelViews) or {}
    aw.popupZoom           = ns.state.popupZoom or 0.25
    aw.globalModelRotation = ns.state.globalModelRotation or math.pi * 2

    char.settings = {
            sortBy                 = ns.state.sortBy or nil,
            exoticFilter           = ns.state.exoticFilter or false,
            duplicatesOnlyFilter   = ns.state.duplicatesOnlyFilter or false,
            selectedSpecs          = DeepCopyIfNonEmpty(ns.state.selectedSpecs),
            selectedFamilies       = DeepCopyIfNonEmpty(ns.state.selectedFamilies),
            selectedTamers         = DeepCopyIfNonEmpty(ns.state.selectedTamers),
            selectedTamingRules    = DeepCopyIfNonEmpty(ns.state.selectedTamingRules),
            selectedConditions     = DeepCopyIfNonEmpty(ns.state.selectedConditions),
            modelsPanelCurrentPage = currentPage or savedPage or 1,
            tamerSelectionInitialized = ns.state.tamerSelectionInitialized or false,
            -- No per-character minimapButton: every reader uses the account-wide
            -- PetStableManagementDB.settings.minimapButton (see Events.lua's
            -- ADDON_LOADED handler). This used to write a same-session copy of it here
            -- on every save, on every one of up to 15 characters, that nothing read.
        }
end

function ns.Data:LoadPersistentDataForDisplay(preserveCurrentData)
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
        ns.state.stablePets = {}
        self:ClearMemory(false)

        -- Always load current character first, then load from other characters
        local currentKey = GetCharacterKey()
        local currentCharData = db.characters[currentKey]
        if type(currentCharData) == "table" and type(currentCharData.snapshotData) == "table" then
            for _, pet in ipairs(currentCharData.snapshotData) do
                if type(pet) == "table" and pet.name and pet.icon then
                    local p = ns.Utils.DeepCopy(pet)
                    p.tamer = currentKey
                    p.guid  = p.guid or p.petNumber
                    self:NormalizePetData(p)
                    table.insert(ns.state.stablePets, p)
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
                        local p = ns.Utils.DeepCopy(pet)
                        p.tamer = charKey
                        p.guid  = p.guid or p.petNumber
                        self:NormalizePetData(p)
                        table.insert(ns.state.stablePets, p)
                    end
                end
                loaded = loaded + 1
            end
        end

        if #ns.state.stablePets == 0 then return false end
    end

    self:RebuildSpecAndFamilyLists()
    self:RebuildTamerList()

    local key = GetCharacterKey()
    local src = (db.characters[key] or {}).settings or db.settings
    LoadFilterSettings(src)

    -- Clear tamer selection only if we're coming from a stable session
    if not ns.state.isStableOpen and ns.state.wasStableSession then
        ns.Utils:ClearTable(ns.state.selectedTamers)
        ns.state.tamerSelectionInitialized = true
        ns.state.wasStableSession = false
    elseif ns.state.isStableOpen and not next(ns.state.selectedTamers) then
        if ns.UI and ns.UI.SetDefaultTamerSelection then
            ns.UI:SetDefaultTamerSelection()
        end
    end

    self:MigrateCharacterFavoritesToAccountWide()

    local aw = GetAccountWide()
    ns.state.favoriteModels = ns.Utils.DeepCopy(aw.favoriteModels) or {}
    ns.state.favoriteModelsLoaded = true

    return true
end

function ns.Data:LoadSettingsOnly()
    local db  = PetStableManagementDB
    local key = GetCharacterKey()
    local src = db and db.characters and (db.characters[key] or {}).settings
             or db and db.settings

    LoadFilterSettings(src)

    if src then
        ns.state.tamerSelectionInitialized = src.tamerSelectionInitialized or false
        if src.modelsPanelCurrentPage ~= nil then
            ns.state.modelsPanelCurrentPage = src.modelsPanelCurrentPage
        end
    end

    if ns.UI and ns.UI.SetDefaultTamerSelection then
        ns.UI:SetDefaultTamerSelection()
    end

    -- Global override from saved variable (non-zero takes precedence)
    if _G.PSM_modelsPanelCurrentPage and _G.PSM_modelsPanelCurrentPage ~= 0 then
        ns.state.modelsPanelCurrentPage = _G.PSM_modelsPanelCurrentPage
    else
        ns.state.modelsPanelCurrentPage = ns.state.modelsPanelCurrentPage or 1
    end

    self:MigrateCharacterFavoritesToAccountWide()

    local aw = GetAccountWide()
    ns.state.favoriteModels      = ns.Utils.DeepCopy(aw.favoriteModels) or {}
    ns.state.favoriteModelsLoaded = true
    ns.state.modelViews          = ns.Utils.DeepCopy(aw.modelViews) or {}
    ns.state.popupZoom           = aw.popupZoom or 0.25
    ns.state.globalModelRotation = aw.globalModelRotation or math.pi * 2
end

-- ─── Snapshots & migration ────────────────────────────────────────────────────

function ns.Data:CreateSnapshot()
    local count = self:SavePersistentData()
    if count > 0 then
        ns.Utils:Msg("SUCCESS", ns.L("Pet data snapshot created: %d pets saved.", count))
    end
end

function ns.Data:GetFormattedTimestamp()
    local db = PetStableManagementDB
    if not db or not db.lastUpdated then return "Never" end
    local ts = db.lastUpdated
    return type(ts) == "number" and date("%Y-%m-%d %H:%M:%S", ts) or tostring(ts)
end

function ns.Data:MigrateCharacterFavoritesToAccountWide()
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

function ns.Data:CollectStablePets()
    if not ns.state.isStableOpen then
        print("|cFFFF0000ERROR: CollectStablePets called when stable is NOT open!|r")
        return 0
    end

    ns.state.stablePets = {}
    self:ClearMemory(true)

    if not ns.GetStableFrame() then
        ns.Utils:Msg("ERROR", ns.L("StableFrame not found!"))
        return 0
    end

    ns.Utils.SafeCall(function()
        self:CollectActivePets()
        self:CollectStabledPets()
        self:RebuildSpecAndFamilyLists()
        self:ValidateCollectedData()
    end)

    -- Now that ns.state.stablePets is fully rebuilt (not partway through, as
    -- it was while SyncFavoriteFromNative was noticing changes above), act on
    -- everything it queued: broadcast each changed model to every owned pet,
    -- save once, and repaint both panels once, instead of doing all of that
    -- against an incomplete list on every single pet that changed.
    if ns.state.pendingFavoriteBroadcast and next(ns.state.pendingFavoriteBroadcast) then
        local pending = ns.state.pendingFavoriteBroadcast
        ns.state.pendingFavoriteBroadcast = {}
        for displayID, isFav in pairs(pending) do
            self:PushFavoriteToOwnedPets(displayID, isFav)
        end
        self:SaveSettings()
        self:RefreshFavoriteDisplays()
        local panel = ns.state.modelsPanel
        if panel and ns.FilterState:Get("showFavorites") then
            ns.Browser.ModelsDataLoader:LoadModelsForSelectedFamilies()
        end
    end

    return #ns.state.stablePets
end

function ns.Data:CollectActivePets()
    if not ns.C_StableInfo or not ns.C_StableInfo.GetStablePetInfo then return end
    for slot = 1, ns.Config.ACTIVE_PET_SLOTS do
        local petInfo = ns.Utils.SafeCall(ns.C_StableInfo.GetStablePetInfo, slot)
        if petInfo and petInfo.name and petInfo.icon then
            local pet = self:ProcessPetInfo(petInfo, slot, true)
            if pet then table.insert(ns.state.stablePets, pet) end
        end
    end
end

-- ─── Derived-field cache ──────────────────────────────────────────────────────
-- Abilities/exotic-status/family/spec are expensive to derive but pure
-- functions of level+species+spec, so they're cached by identity + a
-- fingerprint of those inputs. Never caches identity/position fields
-- (slotID, isActive, name, etc.) -- those always come fresh from the live
-- API, so stale/duplicate records can't happen.
ns._petDerivedCache = ns._petDerivedCache or {}

local function PetFingerprint(info)
    return tostring(info.level or 0) .. "|" .. tostring(info.speciesID or info.displayID or 0)
        .. "|" .. tostring(info.specID or info.specId or 0)
end

function ns.Data:GetCachedDerivedFields(petKey, fingerprint)
    local entry = ns._petDerivedCache[petKey]
    if entry and entry.fingerprint == fingerprint then
        return entry.abilities, entry.isExotic, entry.familyName, entry.specName
    end
    return nil
end

function ns.Data:SetCachedDerivedFields(petKey, fingerprint, abilities, isExotic, familyName, specName)
    ns._petDerivedCache[petKey] = {
        fingerprint = fingerprint,
        abilities   = abilities,
        isExotic    = isExotic,
        familyName  = familyName,
        specName    = specName,
    }
end

-- ─── Favorites: one flag per model, in lockstep with every owned pet ───────────
-- Favorite is a model-level concept (ns.state.favoriteModels, keyed by
-- displayID) -- there is no separate "this one specific pet" favorite. Both
-- of the two ways a favorite can change -- a click anywhere in PSM (Browser
-- row, popup, or an owned pet's own row, which all share the same handler),
-- or a direct click on Blizzard's own native star in the default Stable UI,
-- entirely outside PSM -- broadcast the new value onto every live pet the
-- current character owns of that model, so Blizzard's own native star and
-- the Browser always agree regardless of which one the click happened on.
--
-- Earlier attempts tried to let a specific owned pet disagree with its model
-- (its own native flag distinct from the aggregate) and reconcile the two
-- after the fact, several different ways. All of them either let a still-true
-- sibling silently re-favorite a pet that had just been explicitly turned
-- off, or left the Browser's flag hostage to stale data from an offline
-- character's snapshot. Collapsing to one flag removes the reconciliation
-- step entirely, rather than fixing it -- there is nothing left to reconcile.

-- Notices a pet's native favorite changing since we last saw it -- whether
-- that's Blizzard's own stable star clicked directly (PSM's own buttons only
-- ever fire from a PSM click, so that's otherwise invisible to us), or one of
-- PSM's own pushes catching up on a pet whose row wasn't visible when it
-- happened. Either way it's treated as "favorite this model now": the
-- aggregate is set to match, and every other owned pet of the same model gets
-- broadcast the same value, same as clicking PSM's own star would. The very
-- first time a given pet is ever seen this session there's nothing to compare
-- against, so that read only *seeds* favoriteModels if it's still untouched --
-- it doesn't broadcast, since arriving at the stable isn't a user action.
local function SyncFavoriteFromNative(pet)
    if not pet.petNumber or pet.petNumber == 0 then return end
    if not pet.displayID or pet.displayID == 0 then return end
    if not ns.state.favoriteModelsLoaded then return end

    ns.state.lastKnownNativeFavorite = ns.state.lastKnownNativeFavorite or {}
    local last = ns.state.lastKnownNativeFavorite[pet.petNumber]
    ns.state.lastKnownNativeFavorite[pet.petNumber] = pet.isFavorite

    if last == nil then
        if pet.isFavorite and ns.state.favoriteModels[pet.displayID] == nil then
            ns.state.favoriteModels[pet.displayID] = true
        end
        return
    end

    if last ~= pet.isFavorite then
        ns.state.favoriteModels[pet.displayID] = pet.isFavorite
        -- Deferred to once collection fully finishes (see CollectStablePets)
        -- rather than acted on here: ns.state.stablePets is only partially
        -- rebuilt at this point in the pass (cleared, then refilled pet by
        -- pet), so broadcasting to siblings or repainting from it right now
        -- would scan an incomplete list -- which is what caused a Browser
        -- row's ownership border to flash correct and then go wrong.
        ns.state.pendingFavoriteBroadcast = ns.state.pendingFavoriteBroadcast or {}
        ns.state.pendingFavoriteBroadcast[pet.displayID] = pet.isFavorite
    end
end

-- Repaints already-visible favorite stars on both panels. Neither Owned Pets
-- rows (which read a specific pet's own isFavorite) nor Browser rows (which
-- read the shared aggregate) repaint themselves just because the underlying
-- table changed elsewhere -- this is the one place both get told to. Cheap:
-- both are pure "redraw what's already built from current state", not a
-- refetch or refilter.
function ns.Data:RefreshFavoriteDisplays()
    if ns.UI and ns.UI.UpdateVisibleRows then ns.UI:UpdateVisibleRows() end
    if ns.Browser.ModelsPanel and ns.Browser.ModelsPanel.UpdateVisibleRows then
        ns.Browser.ModelsPanel:UpdateVisibleRows()
    end
end

-- Pushes isFav onto one specific live pet's native favorite flag. Only ever
-- called for the current character's own live pet at an open stable -- slotID
-- is stale/meaningless otherwise, and every other C_StableInfo write in this
-- codebase is scoped the same way (see Reorder.lua). When it can't act
-- immediately (away from the stable, or slotID not yet known), the intent is
-- queued by petNumber and applied next time this exact pet is collected live.
function ns.Data:PushNativeFavorite(petData, isFav)
    if not petData or petData.tamer ~= ns.GetCharacterKey() then return end
    if not (ns.C_StableInfo and ns.C_StableInfo.SetPetFavorite) then return end
    if not ns.state.isStableOpen or not petData.slotID then
        if petData.petNumber then
            ns.state.pendingNativeFavorite = ns.state.pendingNativeFavorite or {}
            ns.state.pendingNativeFavorite[petData.petNumber] = isFav
        end
        return
    end
    ns.Utils.SafeCall(ns.C_StableInfo.SetPetFavorite, petData.slotID, isFav)
end

-- Catches up a native push queued while away from the stable, keyed by
-- petNumber so it only ever applies to the exact pet that was clicked.
local function ApplyPendingNativeFavorite(pet)
    local pending = pet.petNumber and ns.state.pendingNativeFavorite
                    and ns.state.pendingNativeFavorite[pet.petNumber]
    if pending ~= nil and pet.slotID then
        ns.Data:PushNativeFavorite(pet, pending)
        ns.state.pendingNativeFavorite[pet.petNumber] = nil
    end
end

-- The broadcast side of the lockstep: every live pet the current character
-- owns of this model gets pushed to the same new value, unconditionally.
function ns.Data:PushFavoriteToOwnedPets(displayID, isFav)
    local currentKey = ns.GetCharacterKey()
    for _, pet in ipairs(ns.state.stablePets) do
        if pet.tamer == currentKey and pet.displayID == displayID then
            self:PushNativeFavorite(pet, isFav)
        end
    end
end

-- Appends to ns.state.stablePets; returns nothing. It used to return
-- (collected, expected) and nothing ever read either value.
function ns.Data:CollectStabledPets()
    local stableFrame    = ns.GetStableFrame()
    local stabledPetList = stableFrame and stableFrame.StabledPetList
    local scrollBox = stabledPetList and stabledPetList.ScrollBox
    local dataProvider = scrollBox and scrollBox:GetDataProvider()
    if not dataProvider then return end

    -- `expectedCount` is internal and load-bearing despite not being returned: it decides
    -- whether the C_StableInfo fallback runs below when ForEach under-collects.
    local collected, collectedKeys = {}, {}
    local expectedCount = ns.Utils.SafeCall(dataProvider.GetSize, dataProvider, false) or 0

    local function processPet(petData)
        if not petData or not petData.icon then return end
        local key = tostring(petData.petNumber or petData.guid
                    or (petData.name .. "_" .. tostring(petData.displayID)))
        if collectedKeys[key] then return end
        collectedKeys[key] = true

        local p = ns.Utils.DeepCopy(petData)
        p.isActive    = false
        p.guid        = p.guid or p.petNumber
        p.modelSceneID = p.modelSceneID or 783
        p.tamer       = ns.GetCharacterKey()
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
            -- p.specID/p.petAbilities/p.specAbilities survive the deep copy above
            -- untouched (Blizzard's own record), unlike ProcessPetInfo's active-pet
            -- path, which builds a fresh table and must read them off petInfo instead.
            self:RecordAbilitiesObservation(p.familyName, p.specName, p.specID,
                p.isExotic, p.petAbilities, p.specAbilities)
            self:SetCachedDerivedFields(key, fingerprint, p.abilities, p.isExotic, p.familyName, p.specName)
        end

        -- Confirmed in-game (2026-08-21): the deep copy above carries Blizzard's raw
        -- record wholesale, including these six fields nothing ever reads once the
        -- block above has consumed them -- caught because they were still showing up
        -- in the real SavedVariables file, on all 204 stabled pets, after they should
        -- have been made redundant by the abilities pool. `specialization`/`type`
        -- duplicate `specName`/`familyName` exactly; `petAbilities`/`specAbilities` are
        -- the raw arrays RecordAbilitiesObservation just consumed, now fully captured
        -- account-wide; `uiModelSceneID`/`creatureID` have no reader anywhere in either
        -- addon today. Cleared here, not just on the way to disk, so the live in-memory
        -- record is the same shape ProcessPetInfo's active-pet path already produces.
        p.specialization = nil
        p.petAbilities   = nil
        p.specAbilities  = nil
        p.type           = nil
        p.uiModelSceneID = nil
        p.creatureID     = nil

        SyncFavoriteFromNative(p)
        ApplyPendingNativeFavorite(p)

        if p.name then table.insert(collected, p) end
    end

    -- Primary: ForEach. One SafeCall per node, so a single malformed record can't
    -- take the rest of the stable down with it -- the boundary in CollectStablePets
    -- only covers a total failure of this function, not a per-item one.
    dataProvider:ForEach(function(node)
        ns.Utils.SafeCall(processPet, node:GetData())
    end, false)

    -- Fallback: C_StableInfo API
    if #collected == 0 or (expectedCount > 0 and #collected < expectedCount) then
        if C_StableInfo and C_StableInfo.GetStablePetInfo then
            for slot = 7, ns.Config.MAX_STABLE_SLOTS do
                ns.Utils.SafeCall(function()
                    local petInfo = C_StableInfo.GetStablePetInfo(slot)
                    if petInfo and petInfo.name and petInfo.icon then
                        processPet(petInfo)
                    end
                end)
            end
        end
    end

    for _, pet in ipairs(collected) do
        table.insert(ns.state.stablePets, pet)
    end
end

-- ─── Pet data helpers ─────────────────────────────────────────────────────────

function ns.Data:ProcessPetInfo(petInfo, slotID, isActive)
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
        self:RecordAbilitiesObservation(familyName, specName, petInfo.specID or petInfo.specId,
            isExotic, petInfo.petAbilities, petInfo.specAbilities)
        self:SetCachedDerivedFields(petKey, fingerprint, abilities, isExotic, familyName, specName)
    end

    local pet = {
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
        isFavorite = petInfo.isFavorite,
        abilities  = abilities,
        modelSceneID = 783,
        tamer      = ns.GetCharacterKey(),
    }
    SyncFavoriteFromNative(pet)
    ApplyPendingNativeFavorite(pet)
    return pet
end

function ns.Data:GetPetSpecName(pet)
    if not pet then return nil end
    return pet.specName or pet.specialization or nil
end

function ns.Data:GetPetFamilyName(pet)
    if not pet then return nil end
    if pet.familyName and pet.familyName ~= "" then return pet.familyName end
    if pet.family and pet.family.name and pet.family.name ~= "" then return pet.family.name end
    return "Unknown"
end

function ns.Data:GetPetExoticStatus(petInfo)
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
    -- Pool first (live-observed, self-updating as Blizzard changes a family's rule),
    -- static table as the last resort for a family this account has truly never
    -- collected. Explicit nil-check, not `or` -- a pool value of exactly `false` must
    -- not fall through to the static table.
    local familyName = self:GetPetFamilyName(petInfo)
    local pooled = GetAbilitiesPool().exoticByFamily[familyName]
    if pooled ~= nil then return pooled end
    return EXOTIC_FAMILIES[familyName] or false
end

function ns.Data:NormalizePetData(pet)
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
    -- Offline reconstruction, same closure argument as GetPetExoticStatus's pool
    -- fallback: a pet can only have been persisted via a live collection that already
    -- seeded these pool entries for its family/spec, so a genuinely missing entry only
    -- happens for a family/spec this account has never collected at all -- which also
    -- means no persisted pet could be waiting to need it.
    if pet.specID == nil then
        pet.specID = self:GetPoolSpecID(pet.specName)
    end
    if pet.abilities == nil then
        pet.abilities = self:GetPoolAbilities(pet.familyName, pet.specName)
    end
end

function ns.Data:ValidateCollectedData()
    local valid = {}
    for _, pet in ipairs(ns.state.stablePets) do
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
    ns.state.stablePets = valid
end

function ns.Data:ExtractPetAbilities(petInfo)
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

function ns.Data:GetAbilityName(ability)
    if type(ability) == "number"  then return ns.Utils:GetSpellNameCompat(ability) end
    if type(ability) == "string"  then return ability end
    if type(ability) == "table"   then return ability.name or ability.Name end
    return nil
end

-- ─── List rebuilding ──────────────────────────────────────────────────────────

function ns.Data:RebuildSpecAndFamilyLists()
    local specSet, familySet = {}, {}
    ns.state.specList, ns.state.familyList = {}, {}

    for _, pet in ipairs(ns.state.stablePets) do
        local spec   = self:GetPetSpecName(pet)
        local family = self:GetPetFamilyName(pet)
        if spec   and not specSet[spec]     then specSet[spec]     = true; ns.state.specList[#ns.state.specList + 1]     = spec   end
        if family and not familySet[family] then familySet[family] = true; ns.state.familyList[#ns.state.familyList + 1] = family end
    end

    table.sort(ns.state.specList)
    table.sort(ns.state.familyList)
end

function ns.Data:RebuildTamerList()
    local seen = {}
    ns.state.tamerList = {}
    for _, pet in ipairs(ns.state.stablePets) do
        local t = pet.tamer
        if t and not seen[t] then
            seen[t] = true
            ns.state.tamerList[#ns.state.tamerList + 1] = t
        end
    end
    table.sort(ns.state.tamerList)
end

-- ─── Memory management ────────────────────────────────────────────────────────

function ns.Data:ClearMemory(preserveFilters)
    if not preserveFilters then
        ns.state.stablePets = {}
    else
        ns.state.stablePets = ns.state.stablePets or {}
    end

    ns.state.stablePetsSnapshot = {}
    ns.state.specList   = {}
    ns.state.familyList = {}

    if ns.state.tamerList then
        ns.state.tamerList = {}
    end

    if not preserveFilters then
        ns.state.selectedSpecs    = {}
        ns.state.selectedFamilies = {}
        ns.state.selectedTamers   = {}
        ns.Selections:Clear("tamingRules")
        ns.Selections:Clear("conditions")
    end
end

function ns.Data:ClearUIRows()
    local function clearModel(m)
        if not m then return end
        m:Hide(); m:ClearModel()
        m.isRotating = false
        ns.RowManager:ReleaseModel(m)
    end

    -- List view
    for _, row in ipairs(ns.state.rows or {}) do
        if row then
            clearModel(row.model)
            if row.text          then row.text:SetText("") end
            if row.abilitiesList then row.abilitiesList:SetText("") end
            row:Hide()
        end
    end

    -- Grid view
    for _, row in ipairs(ns.state.modelViewRows or {}) do
        if row then
            clearModel(row.model)
            row.petData = nil
            row:Hide()
        end
    end

    -- Grouped view rows
    for _, row in ipairs(ns.state.groupedViewRows or {}) do
        if row then
            clearModel(row.model)
            row.petData, row.groupId, row.groupIndex, row.contextMenuPet = nil, nil, nil, nil
            if row.model then row.model.contextMenuPet = nil end
            row:Hide()
        end
    end

    -- Grouped view headers
    for _, header in ipairs(ns.state.groupedViewHeaders or {}) do
        if header then
            header:Hide()
            header.groupId, header.groupName = nil, nil
            header:SetScript("OnEnter",    nil)
            header:SetScript("OnLeave",    nil)
            header:SetScript("OnMouseDown", nil)
        end
    end

    if ns.UI and ns.UI.GroupedView and ns.UI.GroupedView.ClearLayout then
        ns.UI.GroupedView:ClearLayout()
    end
end

-- ─── Teams panel settings ─────────────────────────────────────────────────────

function ns.Data:GetTeamsPanelWidth()    return GetCharacterSettings().teamsPanelWidth  end
function ns.Data:GetTeamsPanelHeight()   return GetCharacterSettings().teamsPanelHeight end
function ns.Data:GetTeamsPanelPosition() return GetCharacterSettings().teamsPanelPosition end

function ns.Data:SetTeamsPanelSize(width, height)
    local s = GetCharacterSettings()
    s.teamsPanelWidth, s.teamsPanelHeight = width, height
    self:SaveSettings()
end

function ns.Data:SetTeamsPanelPosition(point, relativeTo, relativePoint, x, y)
    GetCharacterSettings().teamsPanelPosition = {
        point = point, relativeTo = relativeTo,
        relativePoint = relativePoint, x = x, y = y,
    }
    self:SaveSettings()
end
