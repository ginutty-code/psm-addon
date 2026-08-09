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

local function EnableMenuButton(btn)
    if not btn then return end
    btn:Enable()
    btn:SetAlpha(1)
    if btn.tooltipOverlay then
        btn.tooltipOverlay:Hide()
        btn.tooltipOverlay:EnableMouse(false)
    end
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
            if PSM.RotationFrame then PSM.RotationFrame.activeModels[mf] = nil end
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

    -- Pet data
    popup.currentPetData   = petData
    popup.currentDisplayId = petData.displayId
    popup.currentNPCs      = petData.npcs or {}
    PSM.PopUpManager:UpdatePopupBackground(popup, petData.displayId, petData)

    -- Model (deferred)
    PSM.C_Timer.After(0.1, function() ApplyModelView(popup, petData) end)

    -- Favourites button
    popup.SetFavTexCoord(popup.favoritesButton, PSM.state.favoriteModels[petData.displayId])

    -- Populate taming and NPC info
    PSM.PopUpManager:PopulateModelPopup(popup, petData.displayId, petData, petData.npcs)

    popup:Show()
    popup:Raise()
end

-- ============================================================
-- Module load: enable menu buttons
-- ============================================================

C_Timer.After(0.1, function()
    local menu = PSM.state and PSM.state.menu
    if not menu then return end
    EnableMenuButton(menu.modelsButton)
    EnableMenuButton(menu.rouletteButton)
end)