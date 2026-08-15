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

    -- Fallback to custom button. IconButton rather than Button: it is unskinned by
    -- design, and ElvUI's HandleButton would strip the tracking border and the icon
    -- this is entirely made of.
    local Widgets = PSM.Widgets
    local button = Widgets.IconButton(Minimap, {
        name      = "PetStableManagementMinimapButton",
        size      = { 31, 31 },
        level     = 8,
        highlight = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight",
        onClick   = function(self, btn) PSM.Minimap:OnClick(btn) end,
        tooltip   = PSM.Minimap.TooltipSpec,
    })
    button:SetFrameStrata("MEDIUM")
    button:RegisterForDrag("LeftButton")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    Widgets.Texture(button, {
        layer   = "OVERLAY",
        size    = { 53, 53 },
        texture = "Interface\\Minimap\\MiniMap-TrackingBorder",
        point   = { "TOPLEFT" },
    })

    button.icon = Widgets.Texture(button, {
        layer   = "BACKGROUND",
        size    = { 20, 20 },
        texture = "Interface\\Icons\\Ability_Mount_Raptor",
        point   = { "CENTER", 0, 1 },
    })

    -- Drag stays hand-wired: the kit builds widgets, it does not own dragging.
    button:SetScript("OnDragStart", function(self) PSM.Minimap:OnDragStart(self) end)
    button:SetScript("OnDragStop",  function(self) PSM.Minimap:OnDragStop(self) end)

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

-- The launcher tooltip, shared with the LDB feed in Broker.lua.
--
-- The minimap icon and the Broker data object are the same affordance in two hosts --
-- LibDBIcon literally builds the minimap button *from* the Broker object — so they must
-- list the same clicks. They had separate copies, and the copies had drifted: Broker
-- advertised the Models Browser unconditionally, while this one gates it. That gate is
-- the fix described below, and Broker never received it.
function PSM.Minimap.TooltipSpec()
    local lines = {
        { text = "Left-click: Toggle Owned Pets Panel", color = PSM.Theme.COLOR.HINT },
    }

    -- "Available", not "loaded": under LoadOnDemand the browser is normally unloaded
    -- until first use, so keying the hint on IsBrowserLoaded would hide a working
    -- action. This still omits it when the module is genuinely absent or disabled.
    if PSM.Loader:IsBrowserAvailable() then
        lines[#lines + 1] =
            { text = "Right-click: Toggle Pet Models Browser", color = PSM.Theme.COLOR.HINT }
    end

    lines[#lines + 1] = { text = "Shift+Left-click: Toggle Menu",           color = PSM.Theme.COLOR.HINT }
    lines[#lines + 1] = { text = "Shift+Right-click: Toggle Options Panel", color = PSM.Theme.COLOR.HINT }

    return {
        point = { "TOPLEFT", "BOTTOMLEFT" },
        title = "Pet Stable Management",
        lines = lines,
    }
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

-- There is deliberately no minimap context menu. `PSM.Minimap:ShowContextMenu` used to
-- live here with **no callers**: OnClick spends all four combinations on panels
-- (left/right, shift+left/right), so nothing could ever open it. Every entry it offered
-- is reachable anyway -- Load Pet Model Browser is right-click and `/psm models`, Pet
-- Roulette is `/psm roulette`, Hide Minimap Button is `/psm hide`.
--
-- It survived an earlier cleanup that removed two other copies of the context-menu
-- machinery, because it *looked* different: it built its own dropdown frame instead of
-- repeating the initialiser, and rebuilt that frame under a fixed global name on every
-- call. Worth remembering that unreachable code is not found by grepping for
-- duplication -- it has to be found by asking who calls it.