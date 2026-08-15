-- TeamsData.lua
-- Pet Teams data management for PetStableManagement
-- Handles CRUD operations for pet team configurations

local _, ns = ...
ns.Teams = ns.Teams or {}

-- Apply retry constants
local APPLY_RETRY_MAX_ATTEMPTS = 3
local APPLY_RETRY_DELAY        = 0.5

----------------------------------------------------------------------------------------------------------------
-- LOCAL HELPERS
----------------------------------------------------------------------------------------------------------------

local function GetCurrentCharacterKey()
    return UnitName("player") .. "-" .. GetRealmName()
end

local function GenerateTeamId()
    return GetCurrentCharacterKey() .. "-" .. time() .. "-" .. math.random(1000, 9999)
end


-- Ensure DB structure exists and return the character-scoped data table
local function CharData()
    PetStableManagementDB = PetStableManagementDB or {}
    PetStableManagementDB.characters = PetStableManagementDB.characters or {}
    local key = GetCurrentCharacterKey()
    local chars = PetStableManagementDB.characters
    chars[key] = chars[key] or {}
    chars[key].petTeams = chars[key].petTeams or {}
    return chars[key]
end

-- Convenience: return the petTeams array directly
local function TeamsArray()
    return CharData().petTeams
end

local function SortTeamsAlphabetically()
    table.sort(TeamsArray(), function(a, b)
        return (a.name or ""):lower() < (b.name or ""):lower()
    end)
end

-- Return (index, team) for a given teamId, or (nil, nil)
local function FindTeam(teamId)
    if not teamId then return nil, nil end
    for i, team in ipairs(TeamsArray()) do
        if team.id == teamId then return i, team end
    end
    return nil, nil
end

-- Shared: build a new team table, insert, and sort
local function InsertTeam(name, slots)
    local now  = time()
    local team = {
        id         = GenerateTeamId(),
        name       = name,
        createdAt  = now,
        modifiedAt = now,
        slots      = ns.Utils.DeepCopy(slots),
    }
    table.insert(TeamsArray(), team)
    SortTeamsAlphabetically()
    return team
end

-- Shared: print a colour-formatted addon message
local function Msg(colour, text)
    print(("|c%sPetStableManagement: %s|r"):format(colour, text))
end
local function MsgOK(text)  Msg("FF00FF00", text) end
local function MsgWarn(text) Msg("FFFF8800", text) end
local function MsgErr(text)  Msg("FFFF0000", text) end

----------------------------------------------------------------------------------------------------------------
-- SLOT CAPTURE AND COMPARISON
----------------------------------------------------------------------------------------------------------------

-- The one definition of what a team slot stores.
--
-- A slot is a *snapshot*, not a reference: teams are saved independently of the live
-- stable, so a pet can sit in a team while stabled on another character, or while gone
-- entirely. That is why the fields are copied out rather than looked up on display.
--
-- There were three hand-written copies of this list -- one building from Blizzard's raw
-- record, two copying from an already-processed pet -- and all three had settled on the
-- same nine fields, omitting `level` and `tamer`. The two copying from a processed pet
-- were discarding values they already had. The teams tooltip then looked thinner than
-- the owned-pets one for no reason a reader could see.
--
-- Accepts either shape: a live `C_StableInfo` record or a processed PSM pet.
function ns.Teams:SlotRecord(pet)
    if not pet or not pet.name then return nil end
    return {
        petNumber  = pet.petNumber,
        name       = pet.name,
        displayID  = pet.displayID or 0,
        icon       = pet.icon,
        level      = pet.level or 0,
        familyName = pet.familyName or (pet.family and pet.family.name),
        specName   = pet.specName or pet.specialization,
        specID     = pet.specID or pet.specId,
        isExotic   = pet.isExotic or false,
        -- Only the current character can capture their own slots, so an absent tamer
        -- means "captured now" rather than "unknown".
        tamer      = pet.tamer or ns.GetCharacterKey(),
        abilities  = pet.abilities or ns.Data:ExtractPetAbilities(pet),
    }
end

function ns.Teams:GetCurrentSlots()
    if not ns.state.isStableOpen then
        return nil, "Stable must be open to capture pet slots"
    end
    if not (C_StableInfo and C_StableInfo.GetStablePetInfo) then
        return nil, "C_StableInfo API not available"
    end

    local slots = {}
    for slot = 1, 6 do
        local info = C_StableInfo.GetStablePetInfo(slot)
        slots[slot] = self:SlotRecord(info)
    end
    return slots, nil
end

function ns.Teams:CompareWithTeam(teamId)
    local _, team = FindTeam(teamId)
    if not team then return false, "Team not found" end

    local current, err = self:GetCurrentSlots()
    if not current then return false, err end

    for slot = 1, 6 do
        local c, s = current[slot], team.slots[slot]
        if     not c and not s         then -- both empty, ok
        elseif c and not s or not c and s then return false, "Slot " .. slot .. " differs"
        elseif c.petNumber ~= s.petNumber then return false, "Slot " .. slot .. " has different pet"
        elseif c.specName  ~= s.specName  then return false, "Slot " .. slot .. " has different spec"
        end
    end
    return true, nil
end

----------------------------------------------------------------------------------------------------------------
-- CRUD OPERATIONS
----------------------------------------------------------------------------------------------------------------

function ns.Teams:GetTeams()      return TeamsArray()       end
function ns.Teams:GetTeamCount()  return #TeamsArray()      end

-- The tooltip every "open the teams panel" button shows. A function spec, so the count
-- is read at hover time -- these buttons outlive any particular number of saved teams.
--
-- One definition because there are three such buttons (the Owned Pets panel, the
-- floating menu, the stable frame), and the count line has already been got wrong once
-- by a caller that passed it as a fixed string built when the panel was created.
function ns.Teams:ButtonTooltipSpec()
    return function()
        return {
            anchor = "ANCHOR_BOTTOM",
            title  = "View and manage saved pet teams",
            lines  = {{
                text  = "You have " .. (ns.Teams:GetTeamCount() or 0) .. " saved team(s)",
                color = ns.Theme.COLOR.WHITE,
            }},
        }
    end
end

function ns.Teams:GetTeamById(teamId)
    local _, team = FindTeam(teamId)
    return team
end

function ns.Teams:SaveTeam(name, slots)
    if not name or name == "" then return nil, "Team name is required" end

    if not slots then
        local err
        slots, err = self:GetCurrentSlots()
        if not slots then return nil, err end
    end

    local hasPet = false
    for slot = 1, 6 do
        if slots[slot] then hasPet = true; break end
    end
    if not hasPet then return nil, "Cannot save empty team - at least one pet required" end

    local team    = InsertTeam(name, slots)
    local charData = CharData()
    charData.activeTeamId = team.id

    MsgOK("Team '" .. name .. "' saved successfully.")
    return team.id, nil
end

function ns.Teams:UpdateTeam(teamId, slots)
    if not teamId then return false, "Team ID is required" end

    local index, team = FindTeam(teamId)
    if not index then return false, "Team not found" end

    if not slots then
        local err
        slots, err = self:GetCurrentSlots()
        if not slots then return false, err end
    end

    local teams = TeamsArray()
    teams[index].slots      = ns.Utils.DeepCopy(slots)
    teams[index].modifiedAt = time()

    MsgOK("Team '" .. team.name .. "' updated.")
    return true, nil
end

function ns.Teams:DeleteTeam(teamId)
    if not teamId then return false, "Team ID is required" end

    local index, team = FindTeam(teamId)
    if not index then return false, "Team not found" end

    table.remove(TeamsArray(), index)

    local charData = CharData()
    if charData.activeTeamId == teamId then charData.activeTeamId = nil end

    MsgOK("Team '" .. team.name .. "' deleted.")
    return true, nil
end

function ns.Teams:RenameTeam(teamId, newName)
    if not teamId              then return false, "Team ID is required"  end
    if not newName or newName == "" then return false, "New name is required" end

    local index, team = FindTeam(teamId)
    if not index then return false, "Team not found" end

    local oldName = team.name
    local teams   = TeamsArray()
    teams[index].name       = newName
    teams[index].modifiedAt = time()
    SortTeamsAlphabetically()

    MsgOK("Team renamed from '" .. oldName .. "' to '" .. newName .. "'.")
    return true, nil
end

function ns.Teams:DuplicateTeam(teamId, newName)
    if not teamId then return nil, "Team ID is required" end

    local _, source = FindTeam(teamId)
    if not source then return nil, "Source team not found" end

    newName = (newName and newName ~= "") and newName or (source.name .. " (Copy)")
    local team = InsertTeam(newName, source.slots)

    MsgOK("Team '" .. source.name .. "' duplicated as '" .. newName .. "'.")
    return team.id, nil
end

----------------------------------------------------------------------------------------------------------------
-- APPLY TEAM
----------------------------------------------------------------------------------------------------------------

function ns.Teams:ApplyTeam(teamId, retryCount)
    retryCount = retryCount or 0

    if not ns.state.isStableOpen then
        return false, "Stable must be open to apply a team"
    end
    if not (C_StableInfo and C_StableInfo.SetPetSlot) then
        return false, "C_StableInfo.SetPetSlot not available"
    end

    local _, team = FindTeam(teamId)
    if not team then return false, "Team not found" end

    local currentSlots, err = self:GetCurrentSlots()
    if not currentSlots then return false, err end

    -- Build petNumber -> current slotID map
    local petLocationMap = {}
    for _, pet in ipairs(ns.state.stablePets) do
        if pet.petNumber then petLocationMap[pet.petNumber] = pet.slotID end
    end

    local moveOps, clearOps = {}, {}

    for targetSlot = 1, 6 do
        local teamPet    = team.slots[targetSlot]
        local currentPet = currentSlots[targetSlot]

        if not teamPet and currentPet then
            -- Slot should be empty but has a pet — clear it
            table.insert(clearOps, {
                petNumber = currentPet.petNumber,
                petName   = currentPet.name,
                fromSlot  = targetSlot,
            })
        elseif teamPet and teamPet.petNumber then
            local loc = petLocationMap[teamPet.petNumber]
            if not loc then
                MsgWarn("Pet '" .. (teamPet.name or "Unknown") .. "' not found in stable")
            elseif loc ~= targetSlot then
                table.insert(moveOps, {
                    petNumber = teamPet.petNumber,
                    petName   = teamPet.name,
                    fromSlot  = loc,
                    toSlot    = targetSlot,
                })
            end
        end
    end

    if #moveOps > 0 or #clearOps > 0 then
        self:ExecuteClearOperations(clearOps, 1, function()
            self:ExecuteSlotOperations(moveOps, 1, function()
                self:ValidateAndRetryApply(teamId, retryCount)
            end)
        end)
    else
        self:ValidateAndRetryApply(teamId, retryCount)
    end

    return true, nil
end

function ns.Teams:ValidateAndRetryApply(teamId, retryCount)
    local _, team = FindTeam(teamId)
    if not team then return end

    ns.C_Timer.After(APPLY_RETRY_DELAY, function()
        if ns.Data and ns.Data.CollectStablePets then
            ns.Data:CollectStablePets()
        end

        local currentSlots = self:GetCurrentSlots()
        if not currentSlots then
            if retryCount < APPLY_RETRY_MAX_ATTEMPTS then
                self:ApplyTeam(teamId, retryCount + 1)
            else
                self:OnTeamApplied(teamId)
            end
            return
        end

        local positionsMatch = true
        for slot = 1, 6 do
            local c, s = currentSlots[slot], team.slots[slot]
            if (not c and s) or (c and not s) or (c and s and c.petNumber ~= s.petNumber) then
                positionsMatch = false
                break
            end
        end

        if positionsMatch or retryCount >= APPLY_RETRY_MAX_ATTEMPTS then
            self:OnTeamApplied(teamId)
        else
            self:ApplyTeam(teamId, retryCount + 1)
        end
    end)
end

function ns.Teams:OnTeamApplied(teamId)
    local _, team = FindTeam(teamId)
    if not team then return end

    self:RestorePetSpecializations(team)

    CharData().activeTeamId = teamId

    -- Verify specs then finalise UI
    local MAX_VERIFY = 5
    local VERIFY_DELAY = 0.3

    local function verifyAndFinalize(attempt)
        local allMatch = true
        for slot = 1, 6 do
            local teamPet = team.slots[slot]
            if teamPet and teamPet.specName then
                local info = C_StableInfo.GetStablePetInfo(slot)
                if info and info.name then
                    local currentSpec = info.specName or info.specialization or "Unknown"
                    if currentSpec ~= teamPet.specName then allMatch = false; break end
                end
            end
        end

        if allMatch or attempt >= MAX_VERIFY then
            MsgOK("Team '" .. team.name .. "' applied successfully.")
            if ns.TeamsPanel and ns.TeamsPanel.RefreshTeamsList then
                ns.TeamsPanel:RefreshTeamsList()
            end
            if ns.UI and ns.UI.UpdatePanel then
                ns.UI:UpdatePanel()
            end
        else
            ns.C_Timer.After(VERIFY_DELAY, function() verifyAndFinalize(attempt + 1) end)
        end
    end

    ns.C_Timer.After(0.5, function() verifyAndFinalize(1) end)
end

function ns.Teams:RestorePetSpecializations(team)
    if not (team and team.slots)                              then return end
    if not (C_StableInfo and C_StableInfo.GetStablePetInfo)  then return end

    -- Build specName -> specIndex map, preferring live API data
    local specNameToIndex = { Ferocity = 1, Tenacity = 2, Cunning = 3 }
    local available = C_StableInfo.GetAvailablePetSpecInfos and C_StableInfo.GetAvailablePetSpecInfos() or {}
    for _, spec in ipairs(available) do
        if spec.specializationName and spec.specIndex then
            specNameToIndex[spec.specializationName] = spec.specIndex
        end
    end

    local remaining = {}

    for slot = 1, 6 do
        local teamPet = team.slots[slot]
        if teamPet and teamPet.specName then
            local info = C_StableInfo.GetStablePetInfo(slot)
            if info and info.name then
                local currentSpec = info.specName or info.specialization or "Unknown"
                if currentSpec ~= teamPet.specName then
                    local specIndex = specNameToIndex[teamPet.specName]
                    if specIndex and C_SpecializationInfo and C_SpecializationInfo.SetPetSpecialization then
                        local ok = pcall(C_SpecializationInfo.SetPetSpecialization, specIndex, info.petNumber)
                        if ok then
                            MsgOK("Changed '" .. (teamPet.name or "Unknown") ..
                                  "' spec from " .. currentSpec .. " to " .. teamPet.specName .. ".")
                        else
                            table.insert(remaining, { slot = slot, petName = teamPet.name,
                                                      oldSpec = currentSpec, newSpec = teamPet.specName })
                        end
                    else
                        table.insert(remaining, { slot = slot, petName = teamPet.name,
                                                  oldSpec = currentSpec, newSpec = teamPet.specName })
                    end
                end
            end
        end
    end

    if #remaining > 0 then
        MsgWarn("The following pets need spec changes to match the saved team:")
        for _, c in ipairs(remaining) do
            MsgWarn("  - '" .. (c.petName or "Unknown") ..
                    "' (slot " .. c.slot .. "): " .. c.oldSpec .. " -> " .. c.newSpec)
        end
        MsgWarn("Summon the pet(s) that need spec change and click Apply again.")
    end
end

----------------------------------------------------------------------------------------------------------------
-- SLOT OPERATION EXECUTION
----------------------------------------------------------------------------------------------------------------

function ns.Teams:ExecuteClearOperations(operations, index, callback, usedSlots)
    if index > #operations then if callback then callback() end; return end

    usedSlots = usedSlots or {}
    local op        = operations[index]
    local stableSlot = self:FindEmptyStableSlotExcluding(usedSlots)

    if stableSlot then
        usedSlots[stableSlot] = true
        C_StableInfo.SetPetSlot(op.fromSlot, stableSlot)
        ns.C_Timer.After(0.25, function()
            self:ExecuteClearOperations(operations, index + 1, callback, usedSlots)
        end)
    else
        MsgErr("No available stable slot to move pet '" .. (op.petName or "Unknown") .. "'!")
        self:ExecuteClearOperations(operations, index + 1, callback, usedSlots)
    end
end

function ns.Teams:FindEmptyStableSlotExcluding(usedSlots)
    if not (C_StableInfo and C_StableInfo.GetStablePetInfo) then return nil end
    usedSlots = usedSlots or {}
    for slot = 7, 205 do
        if not usedSlots[slot] then
            local info = C_StableInfo.GetStablePetInfo(slot)
            if not info or not info.name then return slot end
        end
    end
    return nil
end

function ns.Teams:ExecuteSlotOperations(operations, index, callback)
    if index > #operations then if callback then callback() end; return end

    local op = operations[index]

    -- Check if the target slot holds a pet that also needs to move later
    local targetOccupied = false
    for i = index + 1, #operations do
        if operations[i].fromSlot == op.toSlot then targetOccupied = true; break end
    end

    if targetOccupied then
        local tempSlot = self:FindEmptyStableSlotExcluding({})
        if tempSlot then
            C_StableInfo.SetPetSlot(op.toSlot, tempSlot)
            -- Redirect the later operation that was reading from op.toSlot
            for i = index + 1, #operations do
                if operations[i].fromSlot == op.toSlot then
                    operations[i].fromSlot = tempSlot; break
                end
            end
            ns.C_Timer.After(0.2, function()
                C_StableInfo.SetPetSlot(op.fromSlot, op.toSlot)
                ns.C_Timer.After(0.2, function()
                    self:ExecuteSlotOperations(operations, index + 1, callback)
                end)
            end)
        else
            MsgErr("No available slot for pet swap!")
            self:ExecuteSlotOperations(operations, index + 1, callback)
        end
    else
        C_StableInfo.SetPetSlot(op.fromSlot, op.toSlot)
        ns.C_Timer.After(0.2, function()
            self:ExecuteSlotOperations(operations, index + 1, callback)
        end)
    end
end

----------------------------------------------------------------------------------------------------------------
-- ACTIVE TEAM TRACKING
----------------------------------------------------------------------------------------------------------------

function ns.Teams:GetActiveTeamId()   return CharData().activeTeamId     end

function ns.Teams:HasActiveTeamChanged()
    local id = self:GetActiveTeamId()
    if not id then return false, "No active team" end
    return not self:CompareWithTeam(id), nil
end

----------------------------------------------------------------------------------------------------------------
-- UTILITY
----------------------------------------------------------------------------------------------------------------

function ns.Teams:FormatTimestamp(ts)
    return ts and date("%Y-%m-%d %H:%M", ts) or "Unknown"
end

