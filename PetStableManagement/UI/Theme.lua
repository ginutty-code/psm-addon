-- UI/Theme.lua
-- Visual tokens: fonts, text colours, backdrop presets.
--
-- This file creates nothing and knows nothing about pets. It is the bottom of the
-- UI layer: Skin, Widgets and Tooltip all read from here, and nothing here reads
-- from them.
--
-- Relationship to PSM.Config: Config owns *semantic* colours that other systems
-- also care about (COLORS.PRIMARY, the duplicate/owned row backgrounds, TAB) and
-- the layout constants. Theme owns the raw presentation values that were
-- previously typed out inline at every call site -- the font path, the size ramp,
-- the grey ramp, and the four backdrop shapes. Don't duplicate Config here.

_G.PSM = _G.PSM or {}
local PSM = _G.PSM

PSM.Theme = PSM.Theme or {}
local Theme = PSM.Theme

--------------------------------------------------------------------------------
-- FONT
--------------------------------------------------------------------------------

Theme.FONT = "Fonts\\FRIZQT__.TTF"

-- The sizes actually in use, named. Derived by counting every
-- SetFont("Fonts\\FRIZQT__.TTF", n) in the addon -- these are not aspirational.
Theme.SIZE = {
    TINY    = 9,
    SMALL   = 10,
    BODY    = 11,
    LABEL   = 12,
    HEADING = 14,
    TITLE   = 16,
}

--------------------------------------------------------------------------------
-- TEXT COLOUR
--------------------------------------------------------------------------------

-- The grey ramp and accents that appear as bare SetTextColor(...) literals.
-- GOLD is the same value as PSM.Config.COLORS.PRIMARY; it is repeated here
-- because text styling should not have to reach into Config, and because the two
-- have different reasons to change (Config.PRIMARY is the addon's accent colour,
-- Theme.GOLD is "the colour WoW titles are").
Theme.COLOR = {
    GOLD   = { 1,    0.82, 0    },
    WHITE  = { 1,    1,    1    },
    MUTED  = { 0.8,  0.8,  0.8  },
    DIM    = { 0.7,  0.7,  0.7  },
    GREY   = { 0.6,  0.6,  0.6  },
    FAINT  = { 0.5,  0.5,  0.5  },
    GREEN  = { 0,    1,    0    },
    RED    = { 1,    0,    0    },
    ORANGE = { 1,    0.5,  0    },
}

--------------------------------------------------------------------------------
-- BACKDROP PRESETS
--------------------------------------------------------------------------------

-- Every backdrop in the addon is one of these four shapes. They differ only in
-- edge/tile size, so they are kept distinct rather than collapsed -- the goal of
-- the UI kit is to stop people *retyping* backdrops, not to restyle the addon.
-- PSM.Widgets.Backdrop() accepts overrides for the rare one-off.
--
-- These tables are read by SetBackdrop and never retained by the client, so
-- sharing one table across every frame is safe. Do not mutate them; pass
-- overrides instead.

local TOOLTIP_BG   = "Interface\\Tooltips\\UI-Tooltip-Background"
local TOOLTIP_EDGE = "Interface\\Tooltips\\UI-Tooltip-Border"
local WHITE        = "Interface\\Buttons\\WHITE8X8"

Theme.BACKDROP = {
    -- The default: panels, dialogs, popups. 12 call sites.
    TOOLTIP = {
        bgFile = TOOLTIP_BG, edgeFile = TOOLTIP_EDGE,
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    },
    -- Small popups (coords, note editor) -- a slightly tighter border.
    TOOLTIP_SMALL = {
        bgFile = TOOLTIP_BG, edgeFile = TOOLTIP_EDGE,
        tile = true, tileSize = 14, edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    },
    -- The model popup's own border: a wide tile with a hairline edge, so the
    -- spec background artwork behind it stays visible.
    TOOLTIP_HAIRLINE = {
        bgFile = TOOLTIP_BG, edgeFile = TOOLTIP_EDGE,
        tile = true, tileSize = 30, edgeSize = 5,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    },
    -- Flat fill, no border: list rows and inset blocks that draw their own lines.
    SOLID = {
        bgFile = WHITE,
    },
}

-- Fill colours that go with the presets above, so a row's dark slate fill is
-- named once instead of being four repeated float literals.
Theme.FILL = {
    ROW      = { 0.08, 0.08, 0.12, 0.85 },  -- NPC rows, taming block
    POPUP    = { 0,    0,    0,    0.9  },  -- URL / coords popups
    SEPARATOR = { 0.25, 0.25, 0.30, 1   },  -- 1px row divider
    HAIRLINE = { 1,    1,    1,    0.08 },  -- faint in-row rule
}
