-- OwnedPets/PetGroups.lua
-- Built-in groups functionality for Owned Pets panel

local addonName = "PetStableManagement"

_G.PSM = _G.PSM or {}
local PSM = _G.PSM

PSM.PetGroups = PSM.PetGroups or {}

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
    if PSM.Data and PSM.Data.SavePersistentData then
        PSM.Data:SavePersistentData()
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

function PSM.PetGroups:GetGroups()
    local storage, ungroupedStorage = EnsureStorage()
    local groups = { { id = UNGROUPED_ID, name = UNGROUPED_NAME, pets = ungroupedStorage } }
    for id, group in pairs(storage) do
        table.insert(groups, { id = id, name = group.name, pets = group.pets or {} })
    end
    return groups
end

function PSM.PetGroups:GetGroupCount()
    local storage = EnsureStorage()
    local count = 0
    for _ in pairs(storage) do count = count + 1 end
    return count
end

function PSM.PetGroups:GetGroupById(groupId)
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

function PSM.PetGroups:CreateGroup(name, silent)
    if not name or name == "" then return nil, "Group name is required" end
    if name == UNGROUPED_NAME   then return nil, "Cannot create a group named 'Ungrouped'" end

    local storage = EnsureStorage()
    for _, group in pairs(storage) do
        if group.name == name then return nil, "A group with this name already exists" end
    end

    local groupId = GenerateGroupId()
    storage[groupId] = { name = name, pets = {}, createdAt = time() }
    Save()

    if not silent then
        print("|cFF00FF00PetStableManagement: Group '" .. name .. "' created successfully.|r")
    end
    return groupId, nil
end

function PSM.PetGroups:GetPetsInGroup(groupId)
    if not groupId then return {} end
    local allPets = PSM.state.stablePets or {}
    local storage, ungroupedStorage = EnsureStorage()

    -- Build GUID→pet lookup once.
    local byGUID = {}
    for _, pet in ipairs(allPets) do
        if pet.guid then byGUID[pet.guid] = pet end
    end

    if groupId == UNGROUPED_ID then
        -- Collect GUIDs belonging to custom groups.
        local inGroup = {}
        for _, group in pairs(storage) do
            for _, guid in ipairs(group.pets or {}) do inGroup[guid] = true end
        end

        local result, seen = {}, {}
        -- Respect stored ungrouped order first.
        for _, guid in ipairs(ungroupedStorage) do
            local pet = byGUID[guid]
            if pet and not inGroup[guid] then
                table.insert(result, pet)
                seen[guid] = true
            end
        end
        -- Append newly acquired pets (not yet in any list).
        for _, pet in ipairs(allPets) do
            if pet.guid and not inGroup[pet.guid] and not seen[pet.guid] then
                table.insert(result, pet)
            end
        end
        return result
    end

    local group = self:GetGroupById(groupId)
    if not group then return {} end

    local result = {}
    for _, guid in ipairs(group.pets) do
        local pet = byGUID[guid]
        if pet then table.insert(result, pet) end
    end
    return result
end

function PSM.PetGroups:MovePetToGroup(petGUID, targetGroupId, targetPosition)
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

function PSM.PetGroups:SeedUngroupedPets(guids)
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

function PSM.PetGroups:ReorderPetInGroup(groupId, petGUID, newPosition)
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

function PSM.PetGroups:DeleteGroup(groupId)
    if not groupId            then return false, "Group ID is required" end
    if groupId == UNGROUPED_ID then return false, "Cannot delete the Ungrouped group" end

    local storage, ungroupedStorage = EnsureStorage()
    if not storage[groupId] then return false, "Group not found" end

    local groupName = storage[groupId].name
    for _, guid in ipairs(storage[groupId].pets or {}) do
        table.insert(ungroupedStorage, guid)
    end
    storage[groupId] = nil
    Save()

    print("|cFF00FF00PetStableManagement: Group '" .. groupName .. "' deleted. Pets moved to Ungrouped.|r")
    return true, nil
end

function PSM.PetGroups:RenameGroup(groupId, newName)
    if not groupId             then return false, "Group ID is required" end
    if not newName or newName == "" then return false, "New name is required" end
    if groupId == UNGROUPED_ID  then return false, "Cannot rename the Ungrouped group" end

    local storage = EnsureStorage()
    if not storage[groupId] then return false, "Group not found" end

    storage[groupId].name = newName
    Save()
    return true, nil
end

function PSM.PetGroups:AutoGroupPets(pets, criteria)
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
    print(string.format("|cFF00FF00PetStableManagement: Created %d group(s), moved %d pet(s)|r",
        createdCount, movedCount))
    return { createdCount = createdCount, movedCount = movedCount }
end

function PSM.PetGroups:DeleteAllGroups()
    local storage = EnsureStorage()
    local count = 0
    for id in pairs(storage) do storage[id] = nil; count = count + 1 end
    Save()
    print(string.format("|cFF00FF00PetStableManagement: Deleted %d group(s)|r", count))
    return count
end