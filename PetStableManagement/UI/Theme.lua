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

local _, ns = ...

ns.Theme = ns.Theme or {}
local Theme = ns.Theme

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
    -- The panel-chrome box border (Tools/Show Only/Unified Filters/petsFrame/NPC
    -- column header). Not folded into DIM: this one is specifically a border tint,
    -- those are text.
    SILVER = { 0.75, 0.75, 0.75 },
    DIM    = { 0.7,  0.7,  0.7  },
    GREY   = { 0.6,  0.6,  0.6  },
    FAINT  = { 0.5,  0.5,  0.5  },
    -- Keybind/click hints. The one non-grey in the ramp, because the launcher tooltip
    -- lists four click actions and they read as instructions rather than prose.
    HINT   = { 0.7,  0.7,  1    },
    GREEN  = { 0,    1,    0    },
    RED    = { 1,    0,    0    },
    ORANGE = { 1,    0.5,  0    },
    -- Warm-tinted grey (a hair less blue than FAINT). The NPC-view id column.
    SLATE  = { 0.5,  0.5,  0.47 },
}

-- Selection-state header color: the "all/some/none selected" 3-state idiom used by
-- both continent headers (ModelsFilters) and category-card headers (AbilityBrowser,
-- SpecialTames) -- previously three independent copies of the same if/elseif chain.
function Theme.SelectionStateColor(allSelected, someSelected)
    if allSelected then return Theme.COLOR.GREEN end
    if someSelected then return Theme.COLOR.WHITE end
    return Theme.COLOR.GREY
end

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

    -- Push button height. **One value, everywhere.** The addon previously ran six --
    -- 18, 20, 22, 25, 28 and 30 -- split across two Config constants (BUTTON_HEIGHT 22,
    -- PANEL_BUTTON_HEIGHT 25) and two dozen literals that ignored both.
    --
    -- Checked before collapsing it, because a split that tracks something real is a role
    -- and not drift: the 22/25 divide does *not* follow font size. GameFontNormalSmall
    -- appears on both sides and several 25s set no font at all. There was no rule.
    --
    -- 25 rather than 22 because it was already the majority (~28 buttons to 10), so this
    -- moves ten buttons and leaves the rest exactly where they were.
    BUTTON = 25,

    -- Push button widths: a named ladder, chosen at the call site.
    --
    -- **Fixed tiers, not fit-to-text**, and the reason is buttons that relabel themselves
    -- at runtime -- Maximize/Restore, Select All/Unselect All, Exotic/!Exotic, NPC view/
    -- Models view. Measuring at construction sizes for whichever label happens to be
    -- first (and ModelsPanel's view toggle is built with no text at all, so it would
    -- measure zero); re-measuring on every SetText makes a button change width when you
    -- click it. A fixed width survives both, and keeps rows of buttons aligned.
    --
    -- Overflow is handled instead by clipping the label -- see Widgets.Button.
    -- Tiers were picked from the labels, not from the old widths: switching clipping on
    -- turns a button that was already overflowing into one that visibly truncates, so
    -- preserving a too-narrow width would have *created* the regression. "Ability
    -- Browser", "Unselect All" and "Create Waypoints" all move up a tier for that reason.
    BUTTON_W = {
        XS =  50,
        S  =  80,
        M  = 100,
        L  = 140,
        XL = 180,
    },

    -- The gold-on-dark section header band (Widgets.SectionHeader) -- Tools, Show
    -- Only, and the NPC table's column header. Three call sites ran two heights (20
    -- and 22) and two different label fonts, which is the drift the kit exists to
    -- remove. 22 rather than 20 because the NPC column header is the one that has to
    -- fit a sort arrow beside its label, and 20 clipped the descenders at BODY.
    -- Both boxes that grow by 2px have 3px of clearance above their first control.
    SECTION_HEADER = 22,
}

--------------------------------------------------------------------------------
-- PANEL CHROME
--------------------------------------------------------------------------------

-- The vertical position of every shared panel region, read by PanelManager and by
-- panels building their own filter bar/rail, so a panel's chrome comes from one
-- place instead of being re-derived as an independent pixel guess per panel. See
-- A13 in ../../ARCHITECTURE_PLAN.md for the survey of what these numbers replace.
Theme.CHROME = {
    TITLE_Y    = -35,  -- title, from panel TOP. No per-panel override -- that
                        -- escape hatch (Models Browser's old -20) is what let its
                        -- search box silently drift.
    FILTER_TOP = -100,  -- TOP_BAR filter row / LEFT_RAIL top, from panel TOP.
                         -- Collapses three independent guesses (-110/-100/-90).
    FOOTER_Y   = 15,     -- bare-label footer, from panel BOTTOM.
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
