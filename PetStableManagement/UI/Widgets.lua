-- UI/Widgets.lua
-- Frame factories. Every widget this file returns is already ElvUI-skinned.
--
-- The point of this file is not brevity, it's that "did someone remember to skin
-- this?" and "which font size is a body label?" stop being questions a human has
-- to answer 190 times. If you need a widget shape that isn't here, add it here.
--
-- Nothing in this file knows what a pet is. It takes a parent and a table of
-- options and returns a frame; it never reads PSM.state and never calls back into
-- a feature module.

_G.PSM = _G.PSM or {}
local PSM = _G.PSM

PSM.Widgets = PSM.Widgets or {}
local Widgets = PSM.Widgets

--------------------------------------------------------------------------------
-- SHARED OPTION HANDLING
--------------------------------------------------------------------------------

-- Options tables fail quietly: a misspelled or misplaced key is simply never read,
-- and the widget comes out subtly wrong with no error. Each factory declares the keys
-- it understands, and anything else is counted here rather than ignored.
--
-- Counted, not raised: a hard error on a stray key would take a whole panel down over
-- a typo. Inspect in-game with: /dump PSM.Widgets.unknownOptions
Widgets.unknownOptions = {}

local COMMON_KEYS = { size = true, width = true, height = true, point = true, hidden = true }

-- The keys each factory understands. Anything else is a typo or a key meant for a
-- different factory, and is recorded in Widgets.unknownOptions rather than obeyed.
local OPTIONS = {
    Frame       = { frameType = true, name = true, template = true, backdrop = true, backdropOverrides = true, color = true, borderColor = true, strata = true, level = true, allPoints = true, skin = true },
    Label       = { fontSize = true, outline = true, color = true, justify = true, layer = true, text = true },
    Button      = { name = true, template = true, text = true, fontObject = true, strata = true, level = true, onClick = true, tooltip = true, skin = true },
    IconButton  = { name = true, texture = true, highlight = true, pushed = true, alpha = true, level = true, onClick = true, tooltip = true, skin = true },
    CloseButton = { name = true, level = true, onClick = true, target = true },
    ResizeGrip  = { corner = true },
    EditBox     = { name = true, multiline = true, template = true, fontObject = true, autoFocus = true, textColor = true, text = true, onEscape = true, onEnter = true, closes = true },
    Line        = { layer = true, color = true },
}

local function CheckOptions(factory, opts, allowed)
    for key in pairs(opts) do
        if not allowed[key] and not COMMON_KEYS[key] then
            local slot = factory .. "." .. tostring(key)
            Widgets.unknownOptions[slot] = (Widgets.unknownOptions[slot] or 0) + 1
        end
    end
end

-- opts.point accepts either one anchor -- point = { "TOP", 0, -15 } -- or several:
-- point = { { "TOPLEFT", f, "TOPLEFT", 0, 0 }, { "TOPRIGHT", f, "TOPRIGHT", 0, 0 } }.
-- Both forms pass straight through to SetPoint, so every SetPoint signature works.
local function ApplyPoints(obj, point)
    if not point then return end
    if type(point[1]) == "table" then
        for _, p in ipairs(point) do obj:SetPoint(unpack(p)) end
    else
        obj:SetPoint(unpack(point))
    end
end

local function ApplyCommon(obj, opts)
    if opts.size then
        -- `size` is always {width, height}. Text size is `fontSize`, because a
        -- number here used to fail deep inside unpack() with no hint of the cause.
        if type(opts.size) ~= "table" then
            error("PSM.Widgets: `size` must be {width, height} -- for text size use `fontSize`", 3)
        end
        obj:SetSize(unpack(opts.size))
    end
    if opts.width  then obj:SetWidth(opts.width)   end
    if opts.height then obj:SetHeight(opts.height) end
    ApplyPoints(obj, opts.point)
    if opts.hidden then obj:Hide() end
end

--------------------------------------------------------------------------------
-- BACKDROP
--------------------------------------------------------------------------------

-- Apply a named PSM.Theme.BACKDROP preset, optionally with per-call overrides
-- (edgeSize, tileSize, insets...). `color` is the backdrop colour, `borderColor`
-- the edge colour; both are {r,g,b,a} tables.
--
-- The frame must already have been created with "BackdropTemplate" -- SetBackdrop
-- does not exist otherwise, and has not since 9.0.
function Widgets.Backdrop(frame, preset, opts)
    opts = opts or {}
    local base = PSM.Theme.BACKDROP[preset]
    if not base then
        error("PSM.Widgets.Backdrop: unknown preset '" .. tostring(preset) .. "'", 2)
    end

    local backdrop = base
    if opts.overrides then
        backdrop = {}
        for k, v in pairs(base) do backdrop[k] = v end
        for k, v in pairs(opts.overrides) do backdrop[k] = v end
    end

    frame:SetBackdrop(backdrop)
    if opts.color       then frame:SetBackdropColor(unpack(opts.color))        end
    if opts.borderColor then frame:SetBackdropBorderColor(unpack(opts.borderColor)) end
    return frame
end

--------------------------------------------------------------------------------
-- FRAME
--------------------------------------------------------------------------------

-- A plain frame, with an optional backdrop preset. Pass `backdrop` and you get
-- "BackdropTemplate" automatically -- forgetting that template is the single most
-- common cause of "attempt to call method 'SetBackdrop'".
function Widgets.Frame(parent, opts)
    opts = opts or {}
    CheckOptions("Frame", opts, OPTIONS.Frame)
    local template = opts.template
    if opts.backdrop and not template then template = "BackdropTemplate" end

    local f = CreateFrame(opts.frameType or "Frame", opts.name, parent, template)
    ApplyCommon(f, opts)

    if opts.backdrop then
        Widgets.Backdrop(f, opts.backdrop, {
            overrides   = opts.backdropOverrides,
            color       = opts.color,
            borderColor = opts.borderColor,
        })
    end

    if opts.strata     then f:SetFrameStrata(opts.strata)   end
    if opts.level      then f:SetFrameLevel(opts.level)     end
    if opts.allPoints  then f:SetAllPoints()                end
    if opts.skin       then PSM.Skin.Apply(f, opts.skin)    end
    return f
end

-- A frame the user can drag by its body. Used by every free-floating popup.
function Widgets.MovableFrame(parent, opts)
    local f = Widgets.Frame(parent, opts)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    return f
end

--------------------------------------------------------------------------------
-- TEXT
--------------------------------------------------------------------------------

-- A font string. Text size is `fontSize` -- pass PSM.Theme.SIZE.LABEL explicitly so
-- it stays greppable at the call site. `size`, as everywhere else in this file, is
-- the {width, height} of the region; font strings rarely need it.
function Widgets.Label(parent, opts)
    opts = opts or {}
    CheckOptions("Label", opts, OPTIONS.Label)
    local fs = parent:CreateFontString(nil, opts.layer or "OVERLAY")
    fs:SetFont(PSM.Theme.FONT, opts.fontSize or PSM.Theme.SIZE.LABEL, opts.outline and "OUTLINE" or "")
    if opts.color   then fs:SetTextColor(unpack(opts.color)) end
    if opts.justify then fs:SetJustifyH(opts.justify)        end
    ApplyCommon(fs, opts)
    if opts.text then fs:SetText(opts.text) end
    return fs
end

--------------------------------------------------------------------------------
-- BUTTONS
--------------------------------------------------------------------------------

-- The standard Blizzard push button, skinned.
function Widgets.Button(parent, opts)
    opts = opts or {}
    CheckOptions("Button", opts, OPTIONS.Button)
    local b = CreateFrame("Button", opts.name, parent, opts.template or "UIPanelButtonTemplate")
    ApplyCommon(b, opts)
    if opts.text       then b:SetText(opts.text)                   end
    if opts.fontObject then b:SetNormalFontObject(opts.fontObject) end
    if opts.strata     then b:SetFrameStrata(opts.strata)          end
    if opts.level      then b:SetFrameLevel(opts.level)            end
    if opts.onClick    then b:SetScript("OnClick", opts.onClick)   end
    if opts.tooltip    then PSM.Tooltip.Attach(b, opts.tooltip)    end
    PSM.Skin.Apply(b, opts.skin or "button")
    return b
end

-- A bare texture button (no Blizzard template): the small icon affordances such as
-- reset-view, favourite star, and the resize grip. Deliberately not skinned by
-- default -- ElvUI's HandleButton strips exactly the textures these rely on.
function Widgets.IconButton(parent, opts)
    opts = opts or {}
    CheckOptions("IconButton", opts, OPTIONS.IconButton)
    local b = CreateFrame("Button", opts.name, parent)
    ApplyCommon(b, opts)
    if opts.texture   then b:SetNormalTexture(opts.texture)                    end
    if opts.highlight then b:SetHighlightTexture(opts.highlight)               end
    if opts.pushed    then b:SetPushedTexture(opts.pushed)                     end
    if opts.alpha     then b:SetAlpha(opts.alpha)                              end
    if opts.level     then b:SetFrameLevel(opts.level)                         end
    if opts.onClick   then b:SetScript("OnClick", opts.onClick)                end
    if opts.tooltip   then PSM.Tooltip.Attach(b, opts.tooltip)                 end
    if opts.skin      then PSM.Skin.Apply(b, opts.skin)                        end
    return b
end

-- The round X in a panel's top-right. Defaults to closing `parent`.
function Widgets.CloseButton(parent, opts)
    opts = opts or {}
    CheckOptions("CloseButton", opts, OPTIONS.CloseButton)
    local b = CreateFrame("Button", opts.name, parent, "UIPanelCloseButton")
    b:SetPoint(unpack(opts.point or { "TOPRIGHT", -5, -5 }))
    if opts.size  then b:SetSize(unpack(opts.size))  end
    if opts.level then b:SetFrameLevel(opts.level)   end
    b:SetScript("OnClick", opts.onClick or function() (opts.target or parent):Hide() end)
    PSM.Skin.Apply(b, "closebutton")
    return b
end

-- The corner drag handle for a resizable frame. Calls SetResizable for you,
-- because a grip on a non-resizable frame silently does nothing.
function Widgets.ResizeGrip(frame, opts)
    opts = opts or {}
    CheckOptions("ResizeGrip", opts, OPTIONS.ResizeGrip)
    frame:SetResizable(true)

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(unpack(opts.size or { 16, 16 }))
    grip:SetPoint(unpack(opts.point or { "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4 }))
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() frame:StartSizing(opts.corner or "BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp",   function() frame:StopMovingOrSizing() end)
    PSM.Skin.Apply(grip, "resizegrip")
    return grip
end

--------------------------------------------------------------------------------
-- BEHAVIOUR
--------------------------------------------------------------------------------

-- Escape closes the frame, and every other key still reaches the game.
--
-- The propagation dance matters: a frame with EnableKeyboard(true) swallows all
-- keyboard input unless it re-propagates, which is how addons accidentally break
-- the player's keybinds while a panel is open.
function Widgets.CloseOnEscape(frame)
    frame:EnableKeyboard(true)
    frame:SetPropagateKeyboardInput(true)
    frame:SetScript("OnKeyDown", function(self, key)
        self:SetPropagateKeyboardInput(key ~= "ESCAPE")
        if key == "ESCAPE" then self:Hide() end
    end)
    return frame
end

--------------------------------------------------------------------------------
-- INPUT
--------------------------------------------------------------------------------

-- Single-line input by default; pass multiline = true for the scroll-child form
-- used by the URL and coords popups, which takes no Blizzard template.
function Widgets.EditBox(parent, opts)
    opts = opts or {}
    CheckOptions("EditBox", opts, OPTIONS.EditBox)
    local e = CreateFrame("EditBox", opts.name, parent,
        opts.multiline and nil or (opts.template or "InputBoxTemplate"))
    ApplyCommon(e, opts)

    if opts.multiline then
        e:SetMultiLine(true)
        e:SetFontObject(opts.fontObject or "GameFontNormal")
        e:EnableMouse(true)
        e:EnableKeyboard(true)
    end

    e:SetAutoFocus(opts.autoFocus == true)
    if opts.textColor then e:SetTextColor(unpack(opts.textColor)) end
    if opts.text      then e:SetText(opts.text)                   end

    -- Escape closes the owning popup unless the caller wants something else.
    local onEscape = opts.onEscape
    if onEscape == nil and opts.closes then
        onEscape = function() opts.closes:Hide() end
    end
    if onEscape then e:SetScript("OnEscapePressed", onEscape) end
    if opts.onEnter then e:SetScript("OnEnterPressed", opts.onEnter) end

    PSM.Skin.Apply(e, "editbox")
    return e
end

--------------------------------------------------------------------------------
-- DECORATION
--------------------------------------------------------------------------------

-- A one-pixel rule. Pass `point` for both ends; height defaults to 1.
function Widgets.Line(parent, opts)
    opts = opts or {}
    CheckOptions("Line", opts, OPTIONS.Line)
    local t = parent:CreateTexture(nil, opts.layer or "OVERLAY")
    t:SetHeight(opts.height or 1)
    ApplyPoints(t, opts.point)
    t:SetColorTexture(unpack(opts.color or PSM.Theme.FILL.SEPARATOR))
    return t
end
