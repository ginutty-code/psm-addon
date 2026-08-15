-- UI/Tooltip.lua
-- Declarative GameTooltip helper.
--
-- Roughly thirty places in this addon spell out the same five lines: SetOwner,
-- SetText, some AddLines, Show, and an OnLeave that hides. The interesting part of
-- a tooltip is its text; everything else is ceremony, and ceremony repeated thirty
-- times is thirty chances to forget the Hide.
--
-- A tooltip is described by a spec table:
--
--   {
--     anchor = "ANCHOR_RIGHT",        -- default ANCHOR_RIGHT
--     x = 0, y = 0,                   -- optional SetOwner offsets
--     point = { "TOPLEFT", "BOTTOMLEFT", 0, 0 },  -- place it yourself; see below
--     title = "Reset View",           -- optional
--     titleColor = PSM.Theme.COLOR.GOLD,
--     lines = {                       -- optional; strings or {text=, color=, wrap=}
--       "plain white line",
--       { text = "muted", color = PSM.Theme.COLOR.MUTED },
--       { text = "long explanation", color = PSM.Theme.COLOR.WHITE, wrap = true },
--     },
--     hyperlink = "item:12345",       -- mutually exclusive with title/lines
--     spellId   = 883,                -- ditto: Blizzard's own spell tooltip
--     toplevel = true,                -- for tooltips over TOOLTIP-strata popups
--   }
--
-- Anywhere a spec is accepted you may pass a function(frame) returning a spec
-- instead, for tooltips whose contents depend on live state. Returning nil from
-- that function suppresses the tooltip entirely.

_G.PSM = _G.PSM or {}
local PSM = _G.PSM

PSM.Tooltip = PSM.Tooltip or {}
local Tooltip = PSM.Tooltip

--------------------------------------------------------------------------------
-- SHOW / HIDE
--------------------------------------------------------------------------------

local function Resolve(spec, frame)
    if type(spec) == "function" then return spec(frame) end
    if type(spec) == "string"   then return { title = spec } end
    return spec
end

-- The `lines` format, in one place, because two callers need it: Tooltip.Show
-- building a tooltip from scratch, and Tooltip.AddLines appending to one that is
-- already on screen.
local function AddLines(tooltip, lines)
    for _, line in ipairs(lines or {}) do
        if type(line) == "string" then
            tooltip:AddLine(line)
        elseif line.text then
            local c = line.color
            if c then
                tooltip:AddLine(line.text, c[1], c[2], c[3], line.wrap)
            else
                tooltip:AddLine(line.text, nil, nil, nil, line.wrap)
            end
        end
    end
end

-- Build and show GameTooltip anchored to `owner`. Returns true if it was shown.
function Tooltip.Show(owner, spec)
    spec = Resolve(spec, owner)
    if not spec then return false end

    -- `point` places the tooltip against the owner instead of using one of Blizzard's
    -- ANCHOR_* positions, for the launcher buttons that want it hanging directly below
    -- them. The frame is always the owner, so the spec stays a plain table -- writing
    -- the anchor out in full would force every caller to be a function just to name a
    -- frame the tooltip already knows.
    if spec.point then
        local myPoint, relPoint, x, y = unpack(spec.point)
        GameTooltip:SetOwner(owner, "ANCHOR_NONE")
        GameTooltip:SetPoint(myPoint, owner, relPoint, x or 0, y or 0)
    else
        GameTooltip:SetOwner(owner, spec.anchor or "ANCHOR_RIGHT", spec.x, spec.y)
    end

    if spec.hyperlink then
        GameTooltip:SetHyperlink(spec.hyperlink)
    elseif spec.spellId then
        -- Blizzard fills the tooltip itself, possibly asynchronously the first time a
        -- spell is seen. Anything added here would be discarded when the data arrives
        -- and the tooltip is rebuilt -- see Tooltip.AddLines.
        GameTooltip:SetSpellByID(spec.spellId)
    else
        if spec.title then
            local c = spec.titleColor
            if c then
                GameTooltip:SetText(spec.title, c[1], c[2], c[3])
            else
                GameTooltip:SetText(spec.title)
            end
        end
        AddLines(GameTooltip, spec.lines)
    end

    -- A tooltip owned by a frame in the TOOLTIP strata would otherwise render
    -- behind it. Only the popups that live up there need this.
    if spec.toplevel then
        GameTooltip:SetFrameLevel(owner:GetFrameLevel() + 100)
        GameTooltip:SetToplevel(true)
    end

    GameTooltip:Show()
    return true
end

function Tooltip.Hide()
    GameTooltip:Hide()
end

-- Append lines to a tooltip that is already built, and re-show it so it resizes.
--
-- This exists for Blizzard's TooltipDataProcessor post-calls. When a data-driven
-- tooltip (a spell, an item) resolves asynchronously, retail rebuilds the tooltip's
-- lines internally, wiping out anything appended right after the Set* call. A
-- post-call runs on every rebuild, including that late one, so extra lines survive.
-- Same `lines` format as a spec, so a post-call and a spec describe theirs alike.
function Tooltip.AddLines(lines, tooltip)
    tooltip = tooltip or GameTooltip
    AddLines(tooltip, lines)
    tooltip:Show()
end

--------------------------------------------------------------------------------
-- ATTACH
--------------------------------------------------------------------------------

-- Wire OnEnter/OnLeave on `frame` so it shows `spec` while hovered.
--
-- `extra` may carry onEnter/onLeave callbacks for frames that do something else on
-- hover as well (the model reset button fades in, for instance). They run around
-- the tooltip, so the tooltip can never be left on screen by an early return in
-- caller code -- which is exactly what hand-written versions of this get wrong.
function Tooltip.Attach(frame, spec, extra)
    extra = extra or {}
    frame:SetScript("OnEnter", function(self, ...)
        if extra.onEnter then extra.onEnter(self, ...) end
        Tooltip.Show(self, spec)
    end)
    frame:SetScript("OnLeave", function(self, ...)
        Tooltip.Hide()
        if extra.onLeave then extra.onLeave(self, ...) end
    end)
    return frame
end
