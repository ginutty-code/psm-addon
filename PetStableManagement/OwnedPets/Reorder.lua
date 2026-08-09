-- Reorder.lua
-- Pet reordering logic for PetStableManagement

local addonName = "PetStableManagement"

-- Initialize global namespace
_G.PSM = _G.PSM or {}
local PSM = _G.PSM

PSM.Reorder = PSM.Reorder or {}

local MAX_STABLE_SLOT = 205

-- Counter for scroll lock management (handles rapid clicks)
PSM._scrollLockCount = PSM._scrollLockCount or 0

local function AcquireScrollLock()
    PSM._scrollLockCount = PSM._scrollLockCount + 1
    PSM._scrollLock = true
end

local function ReleaseScrollLock()
    PSM._scrollLockCount = PSM._scrollLockCount - 1
    if PSM._scrollLockCount <= 0 then
        PSM._scrollLockCount = 0
        PSM._scrollLock = false
    end
end

function PSM.Reorder:CanReorderPets()
    return PSM.state.isStableOpen
end

function PSM.Reorder:SwapPetSlots(slot1, slot2, skipUpdate)
    if not PSM.Reorder:CanReorderPets() then
        print("|cFFFF0000Must be at stable master to reorder pets|r")
        return false
    end

    if not C_StableInfo or not C_StableInfo.SetPetSlot then
        print("|cFFFF0000SetPetSlot API not available|r")
        return false
    end

    if not slot1 or not slot2 or slot1 == slot2 then
        print("|cFFFF0000Invalid slot numbers|r")
        return false
    end

    if slot1 < 1 or slot1 > MAX_STABLE_SLOT or slot2 < 1 or slot2 > MAX_STABLE_SLOT then
        print("|cFFFF0000Slots must be between 1 and " .. MAX_STABLE_SLOT .. "|r")
        return false
    end

    local pet1 = C_StableInfo.GetStablePetInfo(slot1)
    if not pet1 then
        print("|cFFFF0000No pet in slot " .. slot1 .. "|r")
        return false
    end

    -- SetPetSlot handles both move (empty target) and swap (occupied target)
    print("|cFFFFAA00Moving pet from slot " .. slot1 .. " to slot " .. slot2 .. "...|r")
    PSM.Utils.SafeCall(C_StableInfo.SetPetSlot, slot1, slot2)

    if not skipUpdate then
        PSM.C_Timer.After(0.3, function()
            PSM.UI:UpdatePanel()
        end)
    end

    return true
end

-- Moves a pet by a signed slot offset (negative = up, positive = down)
function PSM.Reorder:MovePet(pet, offset)
    if not pet or not pet.slotID then return false end

    local currentSlot = pet.slotID
    local targetSlot = currentSlot + offset

    if targetSlot < 1 then
        print("|cFFFFAA00Pet is already in slot 1 (top position)|r")
        return false
    end

    if targetSlot > MAX_STABLE_SLOT then
        print("|cFFFFAA00Pet is already in slot " .. MAX_STABLE_SLOT .. " (bottom position)|r")
        return false
    end

    AcquireScrollLock()
    local success = self:SwapPetSlots(currentSlot, targetSlot)

    if not success then
        ReleaseScrollLock()
    else
        PSM.C_Timer.After(2.0, ReleaseScrollLock)
    end

    return success
end

function PSM.Reorder:MovePetUp(pet)
    return self:MovePet(pet, -1)
end

function PSM.Reorder:MovePetDown(pet)
    return self:MovePet(pet, 1)
end