-- UI/Skin.lua
-- The one place that knows ElvUI exists.
--
-- Before this file, 86 call sites each remembered to call ApplyElvUISkin with the
-- right string. That is the failure mode this file exists to remove: PSM.Widgets
-- skins what it builds, so the count of hand-written skin calls only goes down.
--
-- Rules:
--   * Nothing outside this file may reference the ElvUI global.
--   * No pcall around the handlers. If ElvUI changes an API we want the error, not
--     a silently unskinned frame -- unskinned frames are invisible on a client
--     that doesn't run ElvUI, which is most of the ones we test on.

_G.PSM = _G.PSM or {}
local PSM = _G.PSM

PSM.Skin = PSM.Skin or {}
local Skin = PSM.Skin

--------------------------------------------------------------------------------
-- HANDLERS
--------------------------------------------------------------------------------

-- skinType -> function(S, frame), where S is ElvUI's Skins module.
-- `false` means "known type, deliberately nothing to do" (see SUPPORTED below).
local handlers = {
    frame          = function(S, f) S:HandleFrame(f, true) end,
    button         = function(S, f) S:HandleButton(f)      end,
    collapsebutton = function(S, f) S:HandleButton(f)      end,
    editbox        = function(S, f) S:HandleEditBox(f)     end,
    closebutton    = function(S, f) S:HandleCloseButton(f) end,
    -- Not S:HandleDropDownBox. That restyles the frame but leaves the arrow button
    -- and the text where Blizzard put them, which does not match the rest of the
    -- addon. What follows is the treatment PSM has always shipped, lifted verbatim
    -- from a local helper in OwnedPets/Filters.lua -- the last place the ElvUI global
    -- escaped this file, and the reason `dropdown` had a handler here that nothing
    -- called. Anyone who had written skin = "dropdown" would have got a look no other
    -- dropdown in the addon has.
    --
    -- Deferred a tick: ElvUI has not finished with the dropdown at construction time,
    -- so repositioning immediately is overwritten.
    dropdown = function(S, f)
        C_Timer.After(0.1, function()
            if f.Button then
                if S.HandleNextPrevButton then S:HandleNextPrevButton(f.Button, "down") end
                f.Button:ClearAllPoints()
                f.Button:SetPoint("RIGHT", f, "RIGHT", -10, 3)
            end
            for _, part in ipairs({ "Middle", "Left", "Right" }) do
                if f[part] then f[part]:SetAlpha(0) end
            end
            if not f.backdrop then
                f.backdrop = CreateFrame("Frame", nil, f, "BackdropTemplate")
                f.backdrop:SetFrameLevel(f:GetFrameLevel() - 1)
                f.backdrop:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -4)
                f.backdrop:SetPoint("BOTTOMRIGHT", f.Button, "BOTTOMRIGHT", 2, -2)
                f.backdrop:SetBackdrop(PSM.Theme.BACKDROP.TOOLTIP)
                f.backdrop:SetBackdropColor(0.1, 0.1, 0.1, PSM.Config:GetOpacity())
                f.backdrop:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
            end
            if f.Text then
                f.Text:ClearAllPoints()
                f.Text:SetPoint("LEFT",  f,        "LEFT",  22, 2)
                f.Text:SetPoint("RIGHT", f.Button, "LEFT",  -2, 2)
            end
        end)
    end,
    checkbox       = function(S, f) S:HandleCheckBox(f)    end,
    scrollbar      = function(S, f) S:HandleScrollBar(f)   end,

    resizegrip = function(_, f)
        f:StripTextures()
        f:SetTemplate()
        f:SetNormalTexture(Skin.Texture("ArrowUp"))
        f:GetNormalTexture():SetRotation(-2.35)
    end,

    -- ElvUI has no HandleScrollFrame: a scroll frame is an invisible viewport, and
    -- what needs skinning is its ScrollBar child, which callers skin separately.
    -- This entry exists so the four "scrollframe" call sites read as a decision
    -- rather than as a typo that silently did nothing for years.
    scrollframe = false,
}

-- Public so a call site can be checked against it without reaching into `handlers`.
Skin.SUPPORTED = {}
for name in pairs(handlers) do Skin.SUPPORTED[name] = true end

-- Skin types passed in that we have no entry for, i.e. typos. Counted rather than
-- printed: this is a developer signal, not something to spam a player's chat with.
-- Inspect in-game with: /dump PSM.Skin.unhandled
Skin.unhandled = {}

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

-- Resolve an ElvUI media texture by name, with a Blizzard fallback for the two
-- we rely on. Returns nil for an unknown name with no fallback.
function Skin.Texture(name)
    local media = ElvUI and ElvUI[1] and ElvUI[1].Media and ElvUI[1].Media.Textures
    return (media and media[name])
        or (name == "PlusButton"  and "Interface\\Buttons\\UI-PlusButton-Up")
        or (name == "MinusButton" and "Interface\\Buttons\\UI-MinusButton-Up")
        or (name == "ArrowUp"     and "Interface\\Buttons\\UI-PlusButton-Up")
        or nil
end

-- True when ElvUI is loaded and its Skins module is available.
function Skin.IsActive()
    return (ElvUI and ElvUI[1] and ElvUI[1]:GetModule("Skins")) and true or false
end

-- Apply an ElvUI skin to a frame. A no-op without ElvUI, which is the common case.
function Skin.Apply(frame, skinType)
    if not frame or not skinType then return frame end

    local handler = handlers[skinType]
    if handler == nil then
        Skin.unhandled[skinType] = (Skin.unhandled[skinType] or 0) + 1
        return frame
    end
    if handler == false then return frame end

    if not Skin.IsActive() then return frame end
    handler(ElvUI[1]:GetModule("Skins"), frame)
    return frame
end
