-- Minimap.lua
-- Minimap button for PetStableManagement

_G.PSM = _G.PSM or {}

PSM.Minimap = {}

-- ============================================================
-- Constants
-- ============================================================

local rad, cos, sin, sqrt, max, min = math.rad, math.cos, math.sin, math.sqrt, math.max, math.min

-- Maps minimap shape names to per-quadrant "use circular radius" flags
local MINIMAP_SHAPES = {
    ["ROUND"]                  = { true,  true,  true,  true  },
    ["SQUARE"]                 = { false, false, false, false },
    ["CORNER-TOPLEFT"]         = { false, false, false, true  },
    ["CORNER-TOPRIGHT"]        = { false, false, true,  false },
    ["CORNER-BOTTOMLEFT"]      = { false, true,  false, false },
    ["CORNER-BOTTOMRIGHT"]     = { true,  false, false, false },
    ["SIDE-LEFT"]              = { false, true,  false, true  },
    ["SIDE-RIGHT"]             = { true,  false, true,  false },
    ["SIDE-TOP"]               = { false, false, true,  true  },
    ["SIDE-BOTTOM"]            = { true,  true,  false, false },
    ["TRICORNER-TOPLEFT"]      = { false, true,  true,  true  },
    ["TRICORNER-TOPRIGHT"]     = { true,  false, true,  true  },
    ["TRICORNER-BOTTOMLEFT"]   = { true,  true,  false, true  },
    ["TRICORNER-BOTTOMRIGHT"]  = { true,  true,  true,  false },
}

-- ============================================================
-- Position
-- ============================================================

function PSM.Minimap:UpdatePosition()
    local button = PSM.state.minimapButton
    if not button or PSM.state.usingLibDBIcon then return end

    local angle       = rad(PetStableManagementDB.settings.minimapButton.minimapPos or 225)
    local x, y       = cos(angle), sin(angle)
    local quadrant    = 1 + (x < 0 and 1 or 0) + (y > 0 and 2 or 0)

    local shape       = GetMinimapShape and GetMinimapShape() or "ROUND"
    local quadTable   = MINIMAP_SHAPES[shape]
    local RADIUS      = 5
    local w           = Minimap:GetWidth()  / 2 + RADIUS
    local h           = Minimap:GetHeight() / 2 + RADIUS

    if quadTable[quadrant] then
        x, y = x * w, y * h
    else
        x = max(-w, min(x * (sqrt(2 * w ^ 2) - 10), w))
        y = max(-h, min(y * (sqrt(2 * h ^ 2) - 10), h))
    end

    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- ============================================================
-- Button Creation
-- ============================================================

function PSM.Minimap:CreateButton()
    if PSM.state.minimapButton then return end

    -- Try to use LibDBIcon if available
    if LibStub then
        local ldbi = LibStub:GetLibrary("LibDBIcon-1.0", true)
        if ldbi and PSM.Broker.dataobj then
            ldbi:Register("PetStableManagement", PSM.Broker.dataobj, PetStableManagementDB.settings.minimapButton)
            PSM.state.minimapButton = ldbi:GetMinimapButton("PetStableManagement")
            PSM.state.usingLibDBIcon = true
            if PetStableManagementDB.settings.minimapButton.hide then
                ldbi:Hide("PetStableManagement")
            else
                ldbi:Show("PetStableManagement")
            end
            return
        end
    end

    -- Fallback to custom button
    local button = CreateFrame("Button", "PetStableManagementMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    button:RegisterForDrag("LeftButton")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetTexture("Interface\\Icons\\Ability_Mount_Raptor")
    icon:SetPoint("CENTER", 0, 1)
    button.icon = icon

    button:SetScript("OnClick",     function(self, btn) PSM.Minimap:OnClick(btn) end)
    button:SetScript("OnDragStart", function(self)      PSM.Minimap:OnDragStart(self) end)
    button:SetScript("OnDragStop",  function(self)      PSM.Minimap:OnDragStop(self) end)
    button:SetScript("OnEnter",     function(self)      PSM.Minimap:OnEnter(self) end)
    button:SetScript("OnLeave",     function()          GameTooltip:Hide() end)

    PSM.state.minimapButton = button
    PSM.state.usingLibDBIcon = false
    PSM.Minimap:UpdatePosition()

    if PetStableManagementDB.settings.minimapButton.hide then
        button:Hide()
    else
        button:Show()
    end
end

-- ============================================================
-- Event Handlers
-- ============================================================

function PSM.Minimap:OnClick(btn)
    if IsShiftKeyDown() then
        if btn == "LeftButton"  then PSM.Menu:Toggle() end
        if btn == "RightButton" then PSM.Broker:ToggleOptionsPanel() end
    else
        if btn == "LeftButton"  then PSM.Broker:ToggleOwnedPetsPanel() end
        if btn == "RightButton" then PSM.Broker:ToggleModelsBrowserPanel() end
    end
end

function PSM.Minimap:OnDragStart(button)
    if PSM.state.usingLibDBIcon then return end
    button:LockHighlight()
    button.isMoving = true
    button:SetScript("OnUpdate", PSM.Minimap.OnUpdate)
end

function PSM.Minimap:OnDragStop(button)
    if PSM.state.usingLibDBIcon then return end
    button:UnlockHighlight()
    button.isMoving = false
    button:SetScript("OnUpdate", nil)
end

function PSM.Minimap:OnUpdate()
    local button = PSM.state.minimapButton
    if not button or PSM.state.usingLibDBIcon or not button.isMoving then return end

    local scale   = Minimap:GetEffectiveScale()
    local mx, my  = Minimap:GetCenter()
    local px, py  = GetCursorPosition()
    px, py        = px / scale, py / scale

    PetStableManagementDB.settings.minimapButton.minimapPos = math.deg(math.atan2(py - my, px - mx)) % 360
    PSM.Minimap:UpdatePosition()
end

function PSM.Minimap:OnEnter(button)
    GameTooltip:SetOwner(button, "ANCHOR_NONE")
    GameTooltip:SetPoint("TOPLEFT", button, "BOTTOMLEFT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine("Pet Stable Management")
    GameTooltip:AddLine("Left-click: Toggle Owned Pets Panel",      0.7, 0.7, 1)
    if PSM.ModelsPanel and PSM.ModelsPanel.Toggle then
        GameTooltip:AddLine("Right-click: Toggle Pet Models Browser",   0.7, 0.7, 1)
    end
    GameTooltip:AddLine("Shift+Left-click: Toggle Menu",            0.7, 0.7, 1)
    GameTooltip:AddLine("Shift+Right-click: Toggle Options Panel",  0.7, 0.7, 1)
    GameTooltip:Show()
end

-- ============================================================
-- Panel Toggle
-- ============================================================

function PSM.Minimap:TogglePanel()
    if UnitAffectingCombat("player") then
        print("|cFFFF0000Pet Stable Management: Cannot open panel during combat.|r")
        return
    end

    PSM.state.isStableOpen = StableFrame and StableFrame:IsVisible() or false

    -- Lazy-build the panel on first use
    if not PSM.state.panel then
        PSM.UI:BuildPanel()
        if not PSM.state.panel then
            print("|cFFFF0000Failed to create panel.|r")
            return
        end
    end

    -- Hide if already visible
    if PSM.state.panel:IsVisible() then
        PSM.state.panel:Hide()
        if not PSM.state.isStableOpen then PSM.Data:ClearMemory() end
        return
    end

    PSM.state.panel:Show()
    PSM.state.panel:Raise()

    -- Populate with fresh or persistent data
    if PSM.state.isStableOpen then
        PSM.Data:CollectStablePets()
    elseif not PSM.Data:LoadPersistentDataForDisplay() then
        print(PSM.Config.MESSAGES.NO_SNAPSHOT)
        return
    end

    PSM.UI:RenderPanel()
    PSM.UI:UpdatePanelTitle()
    PSM.UI:UpdateSortButtonTexts()
end

-- ============================================================
-- Show / Hide
-- ============================================================

function PSM.Minimap:Show()
    if PSM.state.usingLibDBIcon then
        if LibStub then
            local ldbi = LibStub:GetLibrary("LibDBIcon-1.0", true)
            if ldbi then ldbi:Show("PetStableManagement") end
        end
    elseif PSM.state.minimapButton then
        PSM.state.minimapButton:Show()
    end
    PetStableManagementDB.settings.minimapButton.hide = false
end

function PSM.Minimap:Hide()
    if PSM.state.usingLibDBIcon then
        if LibStub then
            local ldbi = LibStub:GetLibrary("LibDBIcon-1.0", true)
            if ldbi then ldbi:Hide("PetStableManagement") end
        end
    elseif PSM.state.minimapButton then
        PSM.state.minimapButton:Hide()
    end
    PetStableManagementDB.settings.minimapButton.hide = true
end

-- ============================================================
-- Context Menu
-- ============================================================

function PSM.Minimap:ShowContextMenu()
    local menu = CreateFrame("Frame", "PetStableManagementMinimapMenu", UIParent, "UIDropDownMenuTemplate")

    local MENU_ITEMS = {
        { text = "Pet Stable Management", isTitle = true, notCheckable = true },
        {
            text = "Load Pet Model Browser", notCheckable = true,
            func = function()
                if PSM.ModelsPanel and PSM.ModelsPanel.Toggle then
                    PSM.ModelsPanel:Toggle()
                else
                    print("|cFFFF8800PetStableManagement: Models Browser module is not loaded.|r")
                end
            end,
        },
        {
            text = "Pet Roulette", notCheckable = true,
            func = function()
                if PSM.PetRoulette and PSM.PetRoulette.SelectPetRouletteFromCommand then
                    PSM.PetRoulette:SelectPetRouletteFromCommand()
                else
                    print("|cFFFF8800PetStableManagement: Models Browser module is not loaded.|r")
                end
            end,
        },
        {
            text = "Hide Minimap Button", notCheckable = true,
            func = function()
                PSM.Minimap:Hide()
                print("|cFFFFAA00Pet Stable Management: Minimap button hidden. Use /psm show to show it again.|r")
            end,
        },
        { text = "Cancel", notCheckable = true, func = function() end },
    }

    PSM.UIDropDownMenu_Initialize(menu, function()
        for _, item in ipairs(MENU_ITEMS) do
            local info = PSM.UIDropDownMenu_CreateInfo()
            info.text         = item.text
            info.isTitle      = item.isTitle
            info.notCheckable = item.notCheckable
            info.func         = item.func
            PSM.UIDropDownMenu_AddButton(info)
        end
    end)

    PSM.ToggleDropDownMenu(1, nil, menu, "cursor", 0, 0, "MENU")
end