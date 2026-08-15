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
    -- Keybind/click hints. The one non-grey in the ramp, because the launcher tooltip
    -- lists four click actions and they read as instructions rather than prose.
    HINT   = { 0.7,  0.7,  1    },
    GREEN  = { 0,    1,    0    },
    RED    = { 1,    0,    0    },
    ORANGE = { 1,    0.5,  0    },
}

--------------------------------------------------------------------------------
-- CONTROL SIZES
--------------------------------------------------------------------------------

-- Canonical sizes for controls that have exactly one right size, so the widget
-- factories can *default* to them. A factory that takes size at every call site
-- lets consistency drift; a factory with a default makes matching the rest of the
-- addon the path of least resistance, and differing a deliberate act.
--
-- CHECKBOX is 20 because that is what most of the addon already used (Owned Pets
-- filters, and all three Models Browser filter lists); SpecialTames' 16 was the
-- outlier and read as visibly smaller once both were skinned the same way.
Theme.CONTROL = {
    CHECKBOX      = 20,
    CHECKBOX_MARK = 16,  -- the loot-pass glyph drawn over a checkbox when inverted
    -- Vertical pitch for a stacked list of checkboxes: the box plus breathing room.
    -- Kept next to CHECKBOX because the two must move together -- the NPC column
    -- picker had a 16px box on an 18px pitch, and the pitch was not touched when the
    -- box grew.
    CHECKBOX_ROW  = 22,

    -- The panel resize grip. Named here because the row arrows below are sized against
    -- it -- that comparison is the whole reason they have the values they do.
    RESIZE_GRIP   = 16,

    -- Owned Pets reorder arrows. They borrow the dropdown arrow's texture (see Row.lua),
    -- so they take its size too and end up indistinguishable from it.
    --
    -- **One value, deliberately.** Measured with the Owned Pets panel open:
    --     /dump PetDupSpecDrop.Button:GetSize()
    -- a dropdown's arrow button is 24 on the default UI and 18 under ElvUI -- and the
    -- addon sets neither. It sets nothing at all: 24 is Blizzard's template, and 18 is
    -- ElvUI's HandleNextPrevButton resizing it, which is the same call the `reorderup` /
    -- `reorderdown` skins make. Give these buttons 24 and the skin lands them on 18 by
    -- itself, exactly as it does for every dropdown.
    --
    -- This briefly had a second `ROW_ARROW_SKINNED = 18` selected by PSM.Skin.IsActive(),
    -- which hand-computed a number the skin layer was already producing -- a call site
    -- reaching into territory Skin.lua owns. **If a difference is a skin difference, the
    -- skin owns it.** Widgets applies `size` before `PSM.Skin.Apply`, so the ordering
    -- that makes this work is guaranteed by the factory, not by luck.
    ROW_ARROW = 24,
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
    -- List rows inside a panel: full tile, thin edge, tight insets. Used by the
    -- Teams rows and the Grouped View rows.
    TOOLTIP_ROW = {
        bgFile = TOOLTIP_BG, edgeFile = TOOLTIP_EDGE,
        tile = true, tileSize = 16, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
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
    -- No textures at all. A frame that needs BackdropTemplate so something can call
    -- SetBackdropBorderColor on it later, but draws nothing of its own.
    NONE = {},
    -- Border with no fill: an overlay that rings a row without obscuring what is
    -- already drawn there. The duplicate/owned row indicator and the drag-drop
    -- target outline; the latter wants overrides = { edgeSize = 12 }.
    BORDER_ONLY = {
        edgeFile = TOOLTIP_EDGE, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    },
    -- Flat fill with a hairline border: cards and selectable rows, where the border
    -- is recoloured on hover. Set both colours -- the border defaults to white.
    SOLID_BORDERED = {
        bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
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
