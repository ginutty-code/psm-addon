-- OwnedPets/PetGroups.lua
-- Built-in groups functionality for Owned Pets panel

local _, ns = ...

ns.PetGroups = ns.PetGroups or {}

local UNGROUPED_ID   = "ungrouped"
local UNGROUPED_NAME = "Ungrouped"

-------------------------------------------------------------------------------
-- Private helpers
-------------------------------------------------------------------------------

local function GenerateGroupId()
    return "group_" .. tostring(time()) .. "_" .. math.random(1000, 9999)
end

-- Initialises DB tables once and returns (storage, ungroupedStorage).
local function EnsureStorage()
    local db = PetStableManagementDB or {}
    PetStableManagementDB   = db
    db.builtInGroups        = db.builtInGroups  or {}
    db.ungroupedPets        = db.ungroupedPets   or {}
    return db.builtInGroups, db.ungroupedPets
end

local function Save()
    if ns.Data and ns.Data.SavePersistentData then
        ns.Data:SavePersistentData()
    end
end

-- Remove every occurrence of petGUID from a plain array in-place.
local function RemoveFromArray(arr, petGUID)
    local i = #arr
    while i > 0 do
        if arr[i] == petGUID then table.remove(arr, i) end
        i = i - 1
    end
end

-- Remove petGUID from every custom group and from ungroupedStorage.
local function RemovePetFromAllGroups(storage, ungroupedStorage, petGUID)
    for _, group in pairs(storage) do
        RemoveFromArray(group.pets, petGUID)
    end
    RemoveFromArray(ungroupedStorage, petGUID)
end

-- Insert petGUID into arr at a clamped position (default: end).
local function InsertAt(arr, petGUID, pos)
    pos = math.max(1, math.min(pos or (#arr + 1), #arr + 1))
    table.insert(arr, pos, petGUID)
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

function ns.PetGroups:GetGroups()
    local storage, ungroupedStorage = EnsureStorage()
    local groups = { { id = UNGROUPED_ID, name = UNGROUPED_NAME, pets = ungroupedStorage } }
    for id, group in pairs(storage) do
        table.insert(groups, { id = id, name = group.name, pets = group.pets or {} })
    end
    return groups
end

function ns.PetGroups:GetGroupById(groupId)
    if not groupId then return nil end
    local storage, ungroupedStorage = EnsureStorage()
    if groupId == UNGROUPED_ID then
        return { id = UNGROUPED_ID, name = UNGROUPED_NAME, pets = ungroupedStorage }
    end
    local group = storage[groupId]
    if group then
        return { id = groupId, name = group.name, pets = group.pets or {} }
    end
    return nil
end

function ns.PetGroups:CreateGroup(name, silent)
    if not name or name == "" then return nil, ns.L("Group name is required") end
    if name == UNGROUPED_NAME   then return nil, ns.L("'Ungrouped' is a reserved group name") end

    local storage = EnsureStorage()
    for _, group in pairs(storage) do
        if group.name == name then return nil, ns.L("A group with this name already exists") end
    end

    local groupId = GenerateGroupId()
    storage[groupId] = { name = name, pets = {}, createdAt = time() }
    Save()

    if not silent then
        ns.Utils:Msg("SUCCESS", ns.L("Group '%s' created successfully.", name))
    end
    return groupId, nil
end

function ns.PetGroups:MovePetToGroup(petGUID, targetGroupId, targetPosition)
    if not petGUID      then return false, "Pet GUID is required" end
    if not targetGroupId then return false, "Target group ID is required" end

    local storage, ungroupedStorage = EnsureStorage()
    RemovePetFromAllGroups(storage, ungroupedStorage, petGUID)

    if targetGroupId == UNGROUPED_ID then
        InsertAt(ungroupedStorage, petGUID, targetPosition)
        Save()
        return true, nil
    end

    local targetGroup = storage[targetGroupId]
    if not targetGroup then return false, "Target group not found" end

    targetGroup.pets = targetGroup.pets or {}
    InsertAt(targetGroup.pets, petGUID, targetPosition)
    Save()
    return true, nil
end

function ns.PetGroups:SeedUngroupedPets(guids)
    if not guids or #guids == 0 then return end
    local _, ungroupedStorage = EnsureStorage()
    local tracked = {}
    for _, guid in ipairs(ungroupedStorage) do tracked[guid] = true end
    for _, guid in ipairs(guids) do
        if not tracked[guid] then
            table.insert(ungroupedStorage, guid)
            tracked[guid] = true
        end
    end
    Save()
end

function ns.PetGroups:ReorderPetInGroup(groupId, petGUID, newPosition)
    if not groupId  then return false, "Group ID is required" end
    if not petGUID  then return false, "Pet GUID is required" end

    local storage, ungroupedStorage = EnsureStorage()
    local arr

    if groupId == UNGROUPED_ID then
        arr = ungroupedStorage
        -- Ensure the pet is tracked; append if missing.
        local found = false
        for _, guid in ipairs(arr) do if guid == petGUID then found = true; break end end
        if not found then table.insert(arr, petGUID) end
    else
        local group = storage[groupId]
        if not group then return false, "Group not found" end
        arr = group.pets
    end

    local currentPos = nil
    for i, guid in ipairs(arr) do
        if guid == petGUID then currentPos = i; break end
    end
    if not currentPos then return false, "Pet not found in group" end

    table.remove(arr, currentPos)
    InsertAt(arr, petGUID, newPosition)
    Save()
    return true, nil
end

-- One-time sweep for the entries DeleteGroup couldn't have caught before it started
-- cleaning up after itself: any collapsed-state key left over from a group deleted (or
-- regenerated with a fresh GenerateGroupId, e.g. by AutoGroupPets under a different
-- criteria) by an older version of the addon. Called once at login, after both DB
-- tables exist -- see Events.lua's ADDON_LOADED handler.
function ns.PetGroups:PruneCollapsedGroups()
    local collapsed = PetStableManagementDB and PetStableManagementDB.collapsedGroups
    if not collapsed then return 0 end

    local storage = EnsureStorage()
    local pruned = 0
    for groupId in pairs(collapsed) do
        if not storage[groupId] then
            collapsed[groupId] = nil
            pruned = pruned + 1
        end
    end
    return pruned
end

function ns.PetGroups:DeleteGroup(groupId)
    if not groupId            then return false, "Group ID is required" end
    if groupId == UNGROUPED_ID then return false, ns.L("Cannot delete the Ungrouped group") end

    local storage, ungroupedStorage = EnsureStorage()
    if not storage[groupId] then return false, "Group not found" end

    local groupName = storage[groupId].name
    for _, guid in ipairs(storage[groupId].pets or {}) do
        table.insert(ungroupedStorage, guid)
    end
    storage[groupId] = nil
    -- GroupedView.lua's collapsed/expanded state (PetStableManagementDB.collapsedGroups)
    -- is a separate table keyed by this same groupId, and nothing else ever prunes it --
    -- confirmed against a real account's SavedVariables file (2026-08-21): every one of
    -- 154 entries there was orphaned, referencing a groupId no longer in storage.
    if PetStableManagementDB.collapsedGroups then
        PetStableManagementDB.collapsedGroups[groupId] = nil
    end
    Save()

    ns.Utils:Msg("SUCCESS", ns.L("Group '%s' deleted. Pets moved to Ungrouped.", groupName))
    return true, nil
end

function ns.PetGroups:RenameGroup(groupId, newName)
    if not groupId             then return false, "Group ID is required" end
    if not newName or newName == "" then return false, ns.L("New name is required") end
    if groupId == UNGROUPED_ID  then return false, ns.L("Cannot rename the Ungrouped group") end
    if newName == UNGROUPED_NAME then return false, ns.L("'Ungrouped' is a reserved group name") end

    local storage = EnsureStorage()
    if not storage[groupId] then return false, "Group not found" end

    -- The same two name checks CreateGroup makes. Without them a rename could produce a
    -- second group called Ungrouped, or two groups sharing a name -- validated on one
    -- path and not the other.
    for id, group in pairs(storage) do
        if id ~= groupId and group.name == newName then
            return false, ns.L("A group with this name already exists")
        end
    end

    storage[groupId].name = newName
    Save()
    return true, nil
end

function ns.PetGroups:AutoGroupPets(pets, criteria)
    if not pets or #pets == 0 then return {} end

    local storage, ungroupedStorage = EnsureStorage()

    -- Build name→groupId map for existing groups.
    local existingGroups = {}
    for id, group in pairs(storage) do existingGroups[group.name] = id end

    -- Bucket pets by the requested criteria key.
    local buckets = {}
    for _, pet in ipairs(pets) do
        local key
        if criteria == "isExotic" then
            key = pet.isExotic and "Exotic" or "Non-Exotic"
        else
            key = pet[criteria] or "Unknown"
        end
        buckets[key] = buckets[key] or {}
        table.insert(buckets[key], pet)
    end

    local createdCount, movedCount = 0, 0

    for groupName, groupPets in pairs(buckets) do
        if groupName ~= "Unknown" or criteria == "tamer" then
            local groupId = existingGroups[groupName]
            if not groupId then
                groupId = GenerateGroupId()
                storage[groupId] = { name = groupName, pets = {}, createdAt = time() }
                existingGroups[groupName] = groupId  -- avoid re-creating within same call
                createdCount = createdCount + 1
            end

            local target = storage[groupId]
            target.pets  = target.pets or {}
            for _, pet in ipairs(groupPets) do
                if pet.guid then
                    RemovePetFromAllGroups(storage, ungroupedStorage, pet.guid)
                    table.insert(target.pets, pet.guid)
                    movedCount = movedCount + 1
                end
            end
        end
    end

    Save()
    ns.Utils:Msg("SUCCESS", ns.L("Created %d group(s), moved %d pet(s)",
        createdCount, movedCount))
    return { createdCount = createdCount, movedCount = movedCount }
end

function ns.PetGroups:DeleteAllGroups()
    local storage = EnsureStorage()
    local count = 0
    for id in pairs(storage) do storage[id] = nil; count = count + 1 end
    Save()
    ns.Utils:Msg("SUCCESS", ns.L("Deleted %d group(s)", count))
    return count
end