-- Config.lua
-- Configuration constants for PetStableManagement

_G.PSM = _G.PSM or {}

-- ============================================================
-- UI Dimensions
-- ============================================================
PSM.Config = {
    -- List View
    ROW_HEIGHT        = 130,
    ICON_SIZE         = 60,
    TEXT_WIDTH        = 250,
    ABILITIES_WIDTH   = 200,
    MODEL_SIZE        = 110,

    -- Grid View
    GRID_ROW_HEIGHT   = 215,
    GRID_MODEL_SIZE   = 215,

    -- Buttons
    BUTTON_WIDTH        = 80,
    BUTTON_HEIGHT       = 22,
    PANEL_BUTTON_WIDTH  = 70,
    PANEL_BUTTON_HEIGHT = 25,

    -- Dropdowns
    DROPDOWN_WIDTH   = 90,
    DROPDOWN_SPACING = 118,
    DROPDOWN_ROW_Y   = -110,

    -- Panel
    DEFAULT_PANEL_WIDTH  = 550,
    DEFAULT_PANEL_HEIGHT = 640,
    DEFAULT_ROW_WIDTH    = 400,
    MIN_PANEL_WIDTH      = 500,
    MIN_PANEL_HEIGHT     = 300,

    -- Layout
    CONTENT_PADDING    = 6,
    SCROLL_BAR_WIDTH   = 20,
    COLUMN_SPACING     = 6,
    RESIZE_HANDLE_SIZE = 20,

-- ============================================================
-- Font Sizes
-- ============================================================
    FONT_SIZES = {
        TITLE             = 12,
        STATS             = 11,
        PET_TEXT          = 10,
        ABILITIES_HEADER  = 10,
        ABILITIES_TEXT    = 10,
        ABILITY_CATEGORY  = 11,  -- category headers in ability browser
        ABILITY_PILL      = 10,  -- pill labels in ability browser
    },

-- ============================================================
-- Timing (seconds)
-- ============================================================
    UPDATE_DELAY   = 0.3,
    SEARCH_DELAY   = 0.3,
    SNAPSHOT_DELAY = 0.3,
    RENDER_DELAY   = 0.01,

-- ============================================================
-- Pet Stable
-- ============================================================
    MAX_STABLE_SLOTS    = 205,
    ACTIVE_PET_SLOTS    = 5,
    COMPANION_SLOT      = 6,
    MAX_SEARCH_RESULTS  = 205,
    MIN_SEARCH_LENGTH   = 1,
    FORCE_GC_ON_CLEAR   = false,

-- ============================================================
-- Display Settings
-- ============================================================
    -- Opacity
    DEFAULT_OPACITY    = 0.8,
    MIN_TRANSPARENCY   = 0.1,
    MAX_TRANSPARENCY   = 1.0,

    -- Model zoom
    DEFAULT_MODEL_ZOOM = 1.0,
    MIN_MODEL_ZOOM     = 0.5,
    MAX_MODEL_ZOOM     = 2.0,

    -- Model rotation
    DEFAULT_MODEL_VIEW_ANGLE = 0,
    MIN_MODEL_VIEW_ANGLE     = -180,
    MAX_MODEL_VIEW_ANGLE     = 180,

    -- Model position
    DEFAULT_MODEL_VERTICAL_POSITION   = 0.0,
    MIN_MODEL_VERTICAL_POSITION       = -1.0,
    MAX_MODEL_VERTICAL_POSITION       = 1.0,
    DEFAULT_MODEL_HORIZONTAL_POSITION = 0.0,
    MIN_MODEL_HORIZONTAL_POSITION     = -1.0,
    MAX_MODEL_HORIZONTAL_POSITION     = 1.0,

    -- Animation
    DEFAULT_STOP_ANIMATION = false,

    -- Open with Stable window
    DEFAULT_OPEN_WITH_STABLE = true,

    -- Pets per column
    DEFAULT_PETS_PER_COLUMN = 5,
    MIN_PETS_PER_COLUMN     = 2,
    MAX_PETS_PER_COLUMN     = 10,

    -- Background type
    DEFAULT_BACKGROUND_TYPE = "simple",
    BACKGROUND_TYPES = {
        "simple",       -- Simple (tooltip background, not spec-based)
        "stablemaster", -- Stable Master (spec-based atlas backgrounds)
        "custom",       -- Custom (spec-based media file backgrounds)
    },

    SPEC_BACKGROUND_ATLAS = {
        Ferocity = "hunter-stable-bg-art_ferocity",
        Tenacity = "hunter-stable-bg-art_tenacity",
        Cunning  = "hunter-stable-bg-art_cunning",
    },

    SPEC_BACKGROUND_CUSTOM = {
        Ferocity = "Interface\\AddOns\\PetStableManagement\\Media\\bg_ferocity",
        Tenacity = "Interface\\AddOns\\PetStableManagement\\Media\\bg_tenacity",
        Cunning  = "Interface\\AddOns\\PetStableManagement\\Media\\bg_cunning",
    },

    -- Family specs for Models Browser (grouped by spec for easier maintenance)
    FAMILY_SPECS = {
        Ferocity = {
            "Wolf", "Cat", "Spider", "Crocolisk", "Carrion Bird", "Gorilla", "Tallstrider", "Scorpid", "Bat", "Wind Serpent",
            "Ravager", "Ray", "Chimaera", "Devilsaur", "Clefthoof", "Wasp", "Core Hound", "Scalehide", "Courser", "Lesser Dragonkin", "Whiptail"
        },
        Tenacity = {
            "Bear", "Crab", "Turtle", "Dragonhawk", "Worm", "Spirit Beast", "Beetle", "Hydra", "Waterfowl", "Stone Hound",
            "Direhorn", "Riverbeast", "Stag", "Oxen", "Feathermane", "Lizard", "Hopper", "Carapid", "Blood Beast", "Mammoth"
        },
        Cunning = {
            "Boar", "Raptor", "Hyena", "Bird of Prey", "Warp Stalker", "Sporebat", "Serpent", "Moth", "Aqiri", "Fox",
            "Monkey", "Hound", "Shale Beast", "Water Strider", "Rodent", "Gruffhorn", "Basilisk", "Mechanical", "Pterrordax", "Camel"
        },
    },

    -- Family to spec mapping (populated below)
    FAMILY_TO_SPEC = {},

-- ============================================================
-- Colors
-- ============================================================
    COLORS = {
        PRIMARY                       = { 1,    0.82, 0    },
        SECONDARY                     = { 0.7,  0.7,  1    },
        ERROR                         = { 1,    0.2,  0.2  },
        WARNING                       = { 1,    0.8,  0.2  },
        SUCCESS                       = { 0.2,  1,    0.2  },
        DUPLICATE                     = { 1,    0.6,  0.6  },
        BORDER                        = { 0.5,  0.5,  0.5  },
        BORDER_DUPLICATE            = { 1,   0.2, 0.2, 1 },
        BORDER_DUPLICATE_CROSS_CHAR = { 1,   1,   0.2, 1 },
        BORDER_OWNED_SINGLE         = { 0.2, 1,   0.2, 1 },
        HIGHLIGHT_BORDER              = { 0.5,  0.7,  1    },
        DROP_TARGET_BORDER            = { 0.2,  0.8,  0.2  },
        HIGHLIGHT                     = { 0.3,  0.5,  0.8,  0.8 },
        BACKGROUND                    = { 0.1,  0.1,  0.1,  0.5 },
        BACKGROUND_DUPLICATE          = { 0.35, 0,    0,    0.6 },
        BACKGROUND_DUPLICATE_CROSS_CHAR = { 0.35, 0.35, 0,  0.6 },
        BACKGROUND_OWNED_SINGLE       = { 0,    0.35, 0,    0.6 },

        -- Ability Browser specific
        ABILITY_CHECKMARK             = { 0.3,  0.6,  1,   1 },
        ABILITY_HIGHLIGHT             = { 0.15, 0.15, 0.2,  0.3 },
        ABILITY_SELECTION_NOTE        = { 0.65, 0.65, 0.65, 1 },
        ABILITY_CATEGORY_LABEL        = { 0.75, 0.75, 0.75, 1 },
    },

    -- Unified tab/pill styling for both AbilityBrowser and ModelsBrowser
    TAB = {
        ACTIVE_BG         = { 0.4,  0.35, 0.2,  1   },  -- dark golden/greyish
        INACTIVE_BG       = { 0.15, 0.15, 0.18, 0.6 },
        ACTIVE_TEXT       = { 1,    1,    1,    1   },
        INACTIVE_TEXT     = { 1,    0.82, 0,    1   },  -- gold
        ACTIVE_BORDER     = { 1,    0.82, 0,    1   },  -- gold lines
    },

-- ============================================================
-- Exclusion Filters
-- ============================================================
    -- Display IDs whose models don't render correctly
    EXCLUDED_DISPLAY_IDS = {
        -- [12345] = true,
    },

    -- NPC IDs that should never appear in listings
    EXCLUDED_NPC_IDS = {
        -- [12345] = true,
    },

-- ============================================================
-- Messages
-- ============================================================
    MESSAGES = {
        STABLE_FRAME_NOT_FOUND  = "|cFFFF0000StableFrame not found!|r",
        PANEL_CREATION_FAILED   = "|cFFFF0000Panel creation failed!|r",
        PANEL_SHOW_FAILED       = "|cFFFF0000Panel failed to show!|r",
        STABLE_MUST_BE_OPEN     = "|cFFFF0000Stable must be open to %s!|r",
        NO_AVAILABLE_SLOTS      = "|cFFFF0000No available slots to displace pet from slot 1!|r",
        NO_STABLE_SLOTS         = "|cFFFF0000No available stable slots found! (Max 205 slots)|r",
        SNAPSHOT_CREATED        = "|cFF00FF00Pet data snapshot created: %d pets saved.|r",
        NO_SNAPSHOT             = "|cFFFF8800No snapshot available. Please visit a Stable Master to collect your owned pets data.|r",
        ADDON_LOADED            = "|cFF00FF00Pet Stable Management loaded. Use /psm or /petstable or click the minimap button to toggle the panel.|r",
    },
}

-- ============================================================
-- Methods
-- ============================================================

function PSM.Config:GetOpacity()
    return PetStableManagementDB.settings.opacity or self.DEFAULT_OPACITY
end

function PSM.Config:UpdateColors()
    local a = self:GetOpacity()
    self.COLORS.BACKGROUND       = { 0.1,  0.1, 0.1, a }
    self.COLORS.BACKGROUND_DUPLICATE       = { 0.35, 0,   0,   a }
    self.COLORS.BACKGROUND_OWNED_SINGLE    = { 0,    0.35, 0,  a }
end

-- Populate FAMILY_TO_SPEC mapping
for spec, families in pairs(PSM.Config.FAMILY_SPECS) do
    for _, family in ipairs(families) do
        PSM.Config.FAMILY_TO_SPEC[family] = spec
    end
end