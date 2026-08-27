-- Reorder.lua
-- Pet reordering logic for PetStableManagement


-- Initialize global namespace
local _, ns = ...

ns.Reorder = ns.Reorder or {}

local MAX_STABLE_SLOT = 205

-- Counter for scroll lock management (handles rapid clicks)
ns._scrollLockCount = ns._scrollLockCount or 0

local function AcquireScrollLock()
    ns._scrollLockCount = ns._scrollLockCount + 1
    ns._scrollLock = true
end

local function ReleaseScrollLock()
    ns._scrollLockCount = ns._scrollLockCount - 1
    if ns._scrollLockCount <= 0 then
        ns._scrollLockCount = 0
        ns._scrollLock = false
    end
end

function ns.Reorder:CanReorderPets()
    return ns.state.isStableOpen
end

function ns.Reorder:SwapPetSlots(slot1, slot2, skipUpdate)
    if not ns.Reorder:CanReorderPets() then
        ns.Utils:Msg("ERROR", ns.L("Must be at stable master to reorder pets"))
        return false
    end

    if not C_StableInfo or not C_StableInfo.SetPetSlot then
        ns.Utils:Msg("ERROR", "SetPetSlot API not available")
        return false
    end

    if not slot1 or not slot2 or slot1 == slot2 then
        ns.Utils:Msg("ERROR", ns.L("Invalid slot numbers"))
        return false
    end

    if slot1 < 1 or slot1 > MAX_STABLE_SLOT or slot2 < 1 or slot2 > MAX_STABLE_SLOT then
        ns.Utils:Msg("ERROR", ns.L("Slots must be between 1 and %s", MAX_STABLE_SLOT))
        return false
    end

    local pet1 = C_StableInfo.GetStablePetInfo(slot1)
    if not pet1 then
        ns.Utils:Msg("ERROR", ns.L("No pet in slot %s", slot1))
        return false
    end

    -- SetPetSlot handles both move (empty target) and swap (occupied target)
    ns.Utils:Msg("WARNING", ns.L("Moving pet from slot %s to slot %s...", slot1, slot2))
    ns.Utils.SafeCall(C_StableInfo.SetPetSlot, slot1, slot2)

    -- `skipUpdate` means the caller owns the whole post-swap refresh, data included --
    -- drag-and-drop passes it because it has its own scroll-lock and render timing.
    --
    -- Re-read from the game before rendering: `SetPetSlot` changes the client's stable
    -- order, and `EnsurePetData` collects only when the list is *empty*, so `UpdatePanel`
    -- does not force one. Not an exception to the stable-master-only rule --
    -- `CanReorderPets` already requires `isStableOpen`.
    if not skipUpdate then
        ns.C_Timer.After(0.3, function()
            ns.Data:CollectStablePets()
            ns.UI:UpdatePanel()
        end)
    end

    return true
end

-- Moves a pet by a signed slot offset (negative = up, positive = down)
function ns.Reorder:MovePet(pet, offset)
    if not pet or not pet.slotID then return false end

    local currentSlot = pet.slotID
    local targetSlot = currentSlot + offset

    if targetSlot < 1 then
        ns.Utils:Msg("WARNING", ns.L("Pet is already in slot 1 (top position)"))
        return false
    end

    if targetSlot > MAX_STABLE_SLOT then
        ns.Utils:Msg("WARNING", ns.L("Pet is already in slot %s (bottom position)", MAX_STABLE_SLOT))
        return false
    end

    AcquireScrollLock()
    local success = self:SwapPetSlots(currentSlot, targetSlot)

    if not success then
        ReleaseScrollLock()
    else
        ns.C_Timer.After(2.0, ReleaseScrollLock)
    end

    return success
end

function ns.Reorder:MovePetUp(pet)
    return self:MovePet(pet, -1)
end

function ns.Reorder:MovePetDown(pet)
    return self:MovePet(pet, 1)
end