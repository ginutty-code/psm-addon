-- Minimap.lua
-- Minimap button for PetStableManagement

local _, ns = ...

ns.Minimap = {}

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

function ns.Minimap:UpdatePosition()
    local button = ns.state.minimapButton
    if not button or ns.state.usingLibDBIcon then return end

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

function ns.Minimap:CreateButton()
    if ns.state.minimapButton then return end

    -- Try to use LibDBIcon if available
    if LibStub then
        local ldbi = LibStub:GetLibrary("LibDBIcon-1.0", true)
        if ldbi and ns.Broker.dataobj then
            ldbi:Register("PetStableManagement", ns.Broker.dataobj, PetStableManagementDB.settings.minimapButton)
            ns.state.minimapButton = ldbi:GetMinimapButton("PetStableManagement")
            ns.state.usingLibDBIcon = true
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
    local Widgets = ns.Widgets
    local button = Widgets.IconButton(Minimap, {
        name      = "PetStableManagementMinimapButton",
        size      = { 31, 31 },
        level     = 8,
        highlight = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight",
        onClick   = function(self, btn) ns.Minimap:OnClick(btn) end,
        tooltip   = ns.Minimap.TooltipSpec,
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
    button:SetScript("OnDragStart", function(self) ns.Minimap:OnDragStart(self) end)
    button:SetScript("OnDragStop",  function(self) ns.Minimap:OnDragStop(self) end)

    ns.state.minimapButton = button
    ns.state.usingLibDBIcon = false
    ns.Minimap:UpdatePosition()

    if PetStableManagementDB.settings.minimapButton.hide then
        button:Hide()
    else
        button:Show()
    end
end

-- ============================================================
-- Event Handlers
-- ============================================================

function ns.Minimap:OnClick(btn)
    if IsShiftKeyDown() then
        if btn == "LeftButton"  then ns.Menu:Toggle() end
        if btn == "RightButton" then ns.Broker:ToggleOptionsPanel() end
    else
        if btn == "LeftButton"  then ns.Broker:ToggleOwnedPetsPanel() end
        if btn == "RightButton" then ns.Broker:ToggleModelsBrowserPanel() end
    end
end

function ns.Minimap:OnDragStart(button)
    if ns.state.usingLibDBIcon then return end
    button:LockHighlight()
    button.isMoving = true
    button:SetScript("OnUpdate", ns.Minimap.OnUpdate)
end

function ns.Minimap:OnDragStop(button)
    if ns.state.usingLibDBIcon then return end
    button:UnlockHighlight()
    button.isMoving = false
    button:SetScript("OnUpdate", nil)
end

function ns.Minimap:OnUpdate()
    local button = ns.state.minimapButton
    if not button or ns.state.usingLibDBIcon or not button.isMoving then return end

    local scale   = Minimap:GetEffectiveScale()
    local mx, my  = Minimap:GetCenter()
    local px, py  = GetCursorPosition()
    px, py        = px / scale, py / scale

    PetStableManagementDB.settings.minimapButton.minimapPos = math.deg(math.atan2(py - my, px - mx)) % 360
    ns.Minimap:UpdatePosition()
end

-- The launcher tooltip, shared with the LDB feed in Broker.lua.
--
-- The minimap icon and the Broker data object are the same affordance in two hosts --
-- LibDBIcon literally builds the minimap button *from* the Broker object — so they must
-- list the same clicks. They had separate copies, and the copies had drifted: Broker
-- advertised the Models Browser unconditionally, while this one gates it. That gate is
-- the fix described below, and Broker never received it.
function ns.Minimap.TooltipSpec()
    local lines = {
        { text = ns.L("Left-click: Toggle Owned Pets Panel"), color = ns.Theme.COLOR.HINT },
    }

    -- "Available", not "loaded": under LoadOnDemand the browser is normally unloaded
    -- until first use, so keying the hint on IsBrowserLoaded would hide a working
    -- action. This still omits it when the module is genuinely absent or disabled.
    if ns.Loader:IsBrowserAvailable() then
        lines[#lines + 1] =
            { text = ns.L("Right-click: Toggle Pet Models Browser"), color = ns.Theme.COLOR.HINT }
    end

    lines[#lines + 1] = { text = ns.L("Shift+Left-click: Toggle Menu"),           color = ns.Theme.COLOR.HINT }
    lines[#lines + 1] = { text = ns.L("Shift+Right-click: Toggle Options Panel"), color = ns.Theme.COLOR.HINT }

    return {
        point = { "TOPLEFT", "BOTTOMLEFT" },
        title = ns.L("Pet Stable Management"),
        lines = lines,
    }
end


-- ============================================================
-- Panel Toggle
-- ============================================================

function ns.Minimap:TogglePanel()
    if UnitAffectingCombat("player") then
        print(ns.L("Cannot open panel during combat."))
        return
    end

    ns.state.isStableOpen = StableFrame and StableFrame:IsVisible() or false

    -- Lazy-build the panel on first use
    if not ns.state.panel then
        ns.UI:BuildPanel()
        if not ns.state.panel then
            print(ns.L("Failed to create panel."))
            return
        end
    end

    -- Hide if already visible
    if ns.state.panel:IsVisible() then
        ns.state.panel:Hide()
        if not ns.state.isStableOpen then ns.Data:ClearMemory() end
        return
    end

    ns.state.panel:Show()
    ns.state.panel:Raise()

    -- Populate with fresh or persistent data
    if ns.state.isStableOpen then
        ns.Data:CollectStablePets()
    elseif not ns.Data:LoadPersistentDataForDisplay() then
        print(ns.L("No snapshot available. Please visit a Stable Master to collect your owned pets data."))
        return
    end

    ns.UI:RenderPanel()
    ns.UI:UpdatePanelTitle()
    ns.UI:UpdateSortButtonTexts()
end

-- ============================================================
-- Show / Hide
-- ============================================================

function ns.Minimap:Show()
    if ns.state.usingLibDBIcon then
        if LibStub then
            local ldbi = LibStub:GetLibrary("LibDBIcon-1.0", true)
            if ldbi then ldbi:Show("PetStableManagement") end
        end
    elseif ns.state.minimapButton then
        ns.state.minimapButton:Show()
    end
    PetStableManagementDB.settings.minimapButton.hide = false
end

function ns.Minimap:Hide()
    if ns.state.usingLibDBIcon then
        if LibStub then
            local ldbi = LibStub:GetLibrary("LibDBIcon-1.0", true)
            if ldbi then ldbi:Hide("PetStableManagement") end
        end
    elseif ns.state.minimapButton then
        ns.state.minimapButton:Hide()
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