-- PetRoulette.lua
-- Pet Roulette functionality for PetStableManagement

_G.PSM = _G.PSM or {}
local PSM = _G.PSM
PSM.PetRoulette = PSM.PetRoulette or {}

local PetRoulette = PSM.PetRoulette

-- ============================================================
-- Helpers
-- ============================================================

local function GetDB() return PetStableManagementDB.settings end

local function PrintRoulette(pet)
    print(string.format("|cFF00FF00Pet Roulette: %s (Display ID: %d)|r",
        pet.familyName or "Unknown", pet.displayId))
end

-- ============================================================
-- Model pool helpers
-- ============================================================

function PetRoulette:_GetAllAvailableModels()
    local allModels = {}
    for _, familyName in ipairs(PSM.PetModels:GetAvailableFamilies()) do
        local familyData = PSM.PetModels:GetFamilyModels(familyName)
        if familyData and familyData.displayIds then
            for _, d in ipairs(familyData.displayIds) do
                if not PSM.Config.EXCLUDED_DISPLAY_IDS[d.displayId] then
                    allModels[#allModels + 1] = {
                        displayId  = d.displayId,
                        npcs       = d.npcs,
                        familyName = familyName,
                        itemType   = "display_with_npcs",
                    }
                end
            end
        end
    end
    return allModels
end

function PetRoulette:_SelectRandomPet(modelsList)
    local ownedIds = {}
    for _, pet in ipairs(PSM.state.stablePets) do
        if pet.displayID then ownedIds[tonumber(pet.displayID)] = true end
    end

    local owned, unowned = {}, {}
    for _, model in ipairs(modelsList) do
        if ownedIds[model.displayId] then
            owned[#owned + 1] = model
        else
            unowned[#unowned + 1] = model
        end
    end

    local pool = (#unowned > 0 and unowned) or (#owned > 0 and owned) or modelsList
    return pool[math.random(1, #pool)]
end

-- ============================================================
-- Entry points
-- ============================================================

function PetRoulette:SelectPetRoulette()
    local panel = PSM.state.modelsPanel
    if not panel or not panel.allModels or #panel.allModels == 0 then
        print("|cFFFFAA00No pets available for Pet Roulette.|r")
        return
    end
    local pet = self:_SelectRandomPet(panel.allModels)
    self:ShowPetRoulettePopup(pet)
    PrintRoulette(pet)
end

function PetRoulette:SelectPetRouletteFromCommand()
    if PSM.state.isStableOpen then
        if #PSM.state.stablePets == 0 then PSM.Data:CollectStablePets() end
    else
        if #PSM.state.stablePets == 0 then PSM.Data:LoadPersistentDataForDisplay() end
    end

    PSM.PetModels:ClearCache()

    local allModels = self:_GetAllAvailableModels()
    if #allModels == 0 then
        print("|cFFFFAA00No pet models available for Pet Roulette.|r")
        return
    end

    local pet = self:_SelectRandomPet(allModels)
    self:ShowPetRoulettePopup(pet)
    PrintRoulette(pet)
end

-- ============================================================
-- Cleanup
-- ============================================================

local function ClearGlobalCaches()
    PSM._modelsRenderCache  = nil
    PSM._modelsDebounceTimer = nil
    PSM._npcRenderCache     = nil
    PSM._npcDebounceTimer   = nil
end

function PetRoulette:CleanupPetRoulette()
    PSM.PetModels:ClearCache()

    local popup = PSM.state.petRoulettePopup
    if popup then
        if popup.modelFrame then
            local mf = popup.modelFrame
            mf:SetDisplayInfo(0)
            mf:Hide()
            mf.isRotating = false
            PSM.RowManager:ReleaseModel(mf)
        end
        if popup.infoText then popup.infoText:SetText("") end
        if popup.npcsText  then popup.npcsText:SetText("") end
        popup.currentPetData = nil
    end

    ClearGlobalCaches()
    collectgarbage("collect")
end

-- Preserves the visible model and text (e.g. after AFK)
function PetRoulette:CleanupPetRouletteWithoutModel()
    PSM.PetModels:ClearCache()

    local popup = PSM.state.petRoulettePopup
    if popup then
        popup.currentPetData   = nil
        popup.currentDisplayId = nil
    end

    ClearGlobalCaches()
    collectgarbage("collect")
end

-- ============================================================
-- Popup
-- ============================================================



local function ApplyModelView(popup, petData)
    local db   = GetDB()
    local mf   = popup.modelFrame
    local view = PSM.state.modelViews and PSM.state.modelViews[petData.displayId]

    mf:SetDisplayInfo(petData.displayId)
    mf.zoom = (view and view.zoom) or 1.0

    local angle = db.modelViewAngle or PSM.Config.DEFAULT_MODEL_VIEW_ANGLE
    mf.rotation = (view and view.rotation) or math.rad(angle)
    mf:SetRotation(mf.rotation)
    mf:SetCamDistanceScale(mf.zoom / (db.modelZoom or PSM.Config.DEFAULT_MODEL_ZOOM))
    mf:SetPosition(unpack((view and view.position) or {0, 0, 0}))

    if db.stopAnimation then
        mf:FreezeAnimation(0, 0, 0)
    else
        mf:SetAnimation(0)
    end

    mf.isRotating = false
    mf:Show()
end

function PetRoulette:ShowPetRoulettePopup(petData)
    if not PSM.state.petRoulettePopup then
        PSM.state.petRoulettePopup = PSM.PopUpManager:CreateModelPopup({
            title               = "Pet Roulette",
            width               = 500,
            height              = 560,
            modelSize           = 300,
            showPetModelsButton = true,
            showTryAgainButton  = true,
            resizable           = true,
            popupName           = "PetStableManagementRoulettePopup",
            cleanupFunction     = function() PetRoulette:CleanupPetRoulette() end,
            onTryAgain          = function()
                PetRoulette:CleanupPetRoulette()
                local panel = PSM.state.modelsPanel
                if panel and panel.allModels and #panel.allModels > 0 then
                    PetRoulette:SelectPetRoulette()
                else
                    PetRoulette:SelectPetRouletteFromCommand()
                end
            end,
        })
        PSM.state.petRoulettePopup:Hide()
    end

    local popup = PSM.state.petRoulettePopup

    -- petData.npcs (built in _GetAllAvailableModels from GetFamilyModels) is a
    -- bare denseIndex array -- resolve to full records so BuildNPCRows/
    -- CreateNPCRow get the npc.name etc. shape they expect.
    local resolvedNpcs = PSM.PetModels:ResolveNpcRecords(petData.npcs)

    -- Pet data
    popup.currentPetData   = petData
    popup.currentDisplayId = petData.displayId
    popup.currentNPCs      = resolvedNpcs
    PSM.PopUpManager:UpdatePopupBackground(popup, petData.displayId, petData)

    -- Model (deferred)
    C_Timer.After(0.1, function() ApplyModelView(popup, petData) end)

    -- Favourites button
    popup.SetFavTexCoord(popup.favoritesButton, PSM.state.favoriteModels[petData.displayId])

    -- Populate taming and NPC info
    PSM.PopUpManager:PopulateModelPopup(popup, petData.displayId, petData, resolvedNpcs)

    popup:Show()
    popup:Raise()
end

-- A "module load: enable menu buttons" block used to sit here, reaching back into
-- PSM.state.menu to re-enable the core menu's browser buttons and tear down the tooltip
-- overlay pinned over them. That was the visible "wake up" when the browser finally
-- loaded -- and it was only needed because the menu disabled those buttons in the first
-- place, on an availability answer it had cached at construction.
--
-- The menu no longer disables them: they stay enabled and re-read availability on hover.
-- Nothing downstream has to reach up and undo a decision that was never sound. A module
-- patching its parent's widgets on load is a sign the parent is storing state it should
-- be deriving.