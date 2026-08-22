# Pet Stable Management — WoW Hunter Pet Addon
Pet Stable Management is a World of Warcraft hunter pet addon designed to give Hunters full control over their pet collection. It provides a remote stable view, advanced owned‑pet management, content‑based pet team presets, and a complete browser of all tamable creatures, including rare models and special tames.

This addon is built for Hunters who want a powerful, modern tool for organizing their stable, planning new tames, and managing pets across all types of content.

## Modular Structure

Pet Stable Management consists of two addons:

### Core Addon (Required)
- **Pet Stable Management**: Base addon with Owned Pets panel, Pet Teams functionality, and core features

### Optional Addon
- **Pet Stable Management: Models Browser**: Browse all pet models with Pet Roulette feature (requires Core Addon)

The optional addon can be enabled or disabled in the WoW addon list. When disabled, the pet models data, their coordinates and notes are not available.

## Features

### 1. Owned Pets Panel (Core Addon)

The main panel for viewing and managing your hunter's pet collection.

#### Default/List View
- **Advanced Sorting**: Sort pets by: family, model (display ID), slot, spec, tamer (owner)
- **Powerful Filtering**: Filter by exotic status, duplicates, specs, families, and tamers — ownership is tracked account-wide across all your hunters, but while the Blizzard Stable window is open, the tamer filter locks to the current hunter
- **Search Functionality**: Quickly find specific pets with real-time search by various criteria
- **Persistent Data Storage**: Your pet data is saved across sessions
- **Export Options**: Export your pet collection data as CSV with selectable columns
- **Pet Reordering**: Reorganize pets using drag-and-drop or the move up/down buttons to change stable slots (only while the Blizzard Stable window is open)
- **Detailed Abilities Display**: Search and view pet abilities by specialization, family, and pet-specific
- **Pet Management Actions**: Make pets active, set as companion (if Animal Companion talent is selected), stable, or release them (only while the Blizzard Stable window is open)
- **Team Assignment**: Add or remove pets from teams directly from the Owned Pets panel
- **Statistics Display**: Shows collection stats including duplicates

#### Grid View
- Alternative grid layout displaying larger 3D pet models with detailed tooltips on mouseover
- Easily toggle between list and grid views with a single click
- Visual overview of your entire pet collection
- **Pet Reordering**: Reorganize pets using drag-and-drop to change stable slots (only while the Blizzard Stable window is open)

#### Pet Groups
- Organize your pets into custom groups within the grid view
- Create custom groups to organize your pet collection
- Rename and delete groups as needed
- Auto-create groups based on criteria like family, spec, or exotic status
- Drag-and-drop pets between groups or rearrange within the same group, even when not at the stable

### 2. Pet Teams Panel

Save and manage pet team configurations for quick switching between different pet setups.

- Create and save multiple pet team configurations
- Assign pets to teams for specific purposes (soloing, dungeons, specific content or outfit)
- Quick switching between different pet setups
- Manage team compositions either at the stable or on the go
- Drag-and-drop to rearrange pets within teams
- Copy, rename, and delete teams

### 3. Pet Models Browser Panel (Optional Module)

A comprehensive browser for discovering all available pet models and planning your next taming adventure.

- **Complete Pet Database**: Browse all available pet models in the game (according to Wowhead data)
- **Advanced Searching and Filtering**: Search and filter pets by families, expansions, locations, name retention, and classification (Rare, Elite) with persistent selections
- **Hide Owned Toggle**: Filter out pets you already own in the Model Browser
- **Zone-Based Discovery**: Show only pets available in your current zone
- **Favorites System**: Mark and track your favorite pet models across all your hunters on the same account
- **Reset All Filters**: Quickly clear all filters and return to default "show everything" state
- **Pagination**: Efficient browsing with page navigation and jump-to-page
- **Layout Customization**: Adjustable pets per column in model browser (from 2 to 10 pets * 2 columns)
- **NPC View**: Toggle from the 3D model grid to a compact, sortable text table listing one row per NPC, letting you page through far more results at once. Click any column header to sort (ID, Name, Family, Classification, Name Keeper, Zone, Continent, Expansion, Faction, Note, Display IDs); use the Columns button to choose which optional columns are shown, and drag column edges to resize them. NPC names link to their Wowhead page, zones with known coordinates link to TomTom waypoints, and each NPC's Display IDs appear as clickable pills (shown in green if already owned) that open the Model Magnifier.
- **Detailed NPC Information**: View comprehensive NPC data including classification (Elite, Rare, Rare Elite), location (with coordinates, where available), expansion, faction reaction, special notes from Petopia, and ability to add custom notes
- **TomTom Integration**: Automatically generate waypoints for NPC locations when TomTom is installed. Click on Location in the Model Magnifier or Pet Roulette to see available coordinates and set your destination.
- **Custom NPC Notes**: Add and save your own notes for any NPC in the Model Browser. NPCs with custom notes are marked with a green indicator for easy identification.
- **Persistent Model Views**: 3D models in the browser remember custom rotation, zoom, and position settings across sessions
- **Pet Roulette**: Taming suggestions from all available models or filtered models, preferring not-yet-owned pets; includes a 'Try Again' button for quick rerolls without closing the popup
- **Ability Browser**: Browse hunter pet abilities by type and find which families to tame to cover a specific role (eg: damage reduction, crowd control, water walking, slow fall etc.)
- **Special Tames**: Panel listing exotic-family taming requirements (specialization, level, race, or unlock quest/item) with a live eligibility check against your current character, and checkbox filtering per requirement

### General Features

- **Individual Model Controls**: Fine-tune zoom, view angle, vertical and horizontal positioning for each 3D model (left-click to rotate, right-click to reposition, scroll to zoom)
- **Model Magnifier**: Click magnifying glass button on models to open resizable detail popup (available in both owned pets and model browser)
- **Floating Menu**: Optional floating menu for quick access to features
- **Broker Support**: Integration with data broker addons for panel toggling
- **Performance Optimized**: Efficient rendering, GPU-call deduplication, and memory management
- **Minimap Integration**: Uses LibDBIcon when available, falling back to custom button
- **ElvUI Support**: Optional skinning for ElvUI users
- **Resizable Popups**: Pet Roulette and Magnifier windows can be resized with dynamic model scaling
- **Selectable NPC Text**: Click NPC ID links to open a popup with the Wowhead URL for easy copying
- **Coordinates and Map Integration**: Clickable location links in Pet Roulette and Model Magnifier windows that open the destination map for NPC coordinates (with TomTom waypoint generation if TomTom is available); only ~93% of NPCs have both a map ID and coordinates; data available if the Models Browser module is loaded
- **Notes Feature**: View curated notes from Petopia and add your own custom notes for any NPC to keep track of taming strategies or personal reminders.
- **Combat Protection**: Panels automatically closing when entering combat and cannot be opened during combat to prevent errors

## Installation

### Standard Installation
1. Download the addon from CurseForge
2. Extract to your `Interface/AddOns` folder
3. Enable the addons in-game

### Module Selection
In the WoW addon list (Esc → AddOns), you can enable/disable:
- **Pet Stable Management** (required - always enable)
- **Pet Stable Management: Models Browser** (optional - enables the pet model browser)

## Usage

### Accessing the Panels
- Open your pet stable (visit a stable master)
- The Pet Stable Management - owned pets panel will appear automatically next to the default stable UI; can also be opened with a left click on the minimap button (if shown)
- Use the button at the top of the panel to access Pet Teams panel
- Use the minimap button or the slash commands for quick access to Models Browser, Floating Menu or Options panel

### Commands
- `/psm` or `/petstable`: Toggle the main panel (owned pets panel)
- `/psm models`: Toggle the pet model browser (requires Models Browser module)
- `/psm roulette`: Start pet roulette (requires Models Browser module)
- `/psm teams`: Toggle the Pet Teams panel
- `/psm options`: Toggle the options panel
- `/psm menu`: Toggle the floating menu
- `/psm show` / `/psm hide`: Show or hide the minimap button
- `/psm help`: List all available slash commands
- `/petswap [slot1] [slot2]`: Swap pets between stable slots

### Settings
Access settings through the options panel (`/psm options`) or by modifying `PetStableManagementDB` in your saved variables:
- **UI Opacity**: Adjust panel transparency (10% - 100%)
- **Minimap Button**: Show/hide the minimap icon
- **Auto-show Owned Pets Panel**: Toggle whether the Owned Pets panel automatically shows when the Stable window is open
- **Model Zoom**: Adjust default zoom level for 3D models (50% - 200%)
- **View Angle**: Set default rotation angle for models (-180° - 180°)
- **Vertical Positioning**: Adjust model height on Z-axis (-100% - 100%)
- **Horizontal Positioning**: Adjust model position on Y-axis (-100% - 100%)
- **Pets Per Column**: Set number of pets per column in the model browser (2-10)
- **Pet Model Background**: Choose from simple, stable master, or custom backgrounds for 3D pet model display (applies to both Owned Pets and Models Browser panels)
- **Stop Animations**: Disable pet model animations for performance
- **Reset All Settings**: Restore all settings to defaults

## Requirements
- World of Warcraft Retail

## Optional Dependencies
- **Blizzard_StableUI**: Enhanced integration with default stable interface

## Credits
- **Author**: Ginutty
- **Data Attribution**: Full credit for the underlying data goes to [Wowhead](https://www.wowhead.com/) and [Petopia](https://www.wow-petopia.com/) and their contributors, who have made this data publicly available.

## License

MIT License
This addon is provided as-is for personal use in World of Warcraft.

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/U7D622NM2Q)
