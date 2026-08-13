# PetStableManagement (PSM)

A World of Warcraft retail addon (Interface `120007` and `121000`) for hunter pet stable
management. Two TOC-defined addons live in this one repo — and two is what the user
sees and reasons about, so keep it that way:

- **`PetStableManagement/`** — the core addon (Owned Pets panel, teams,
  filters, minimap button, options). Always loaded, and the only one that is.
- **`PetStableManagement_ModelsBrowser/`** — optional module, **`LoadOnDemand`**
  (`RequiredDeps: PetStableManagement`) adding the Models/NPC browser, Abilities
  Browser, Special Tames, and Pet Roulette. Split internally:
  - `ModelsBrowser/` — hand-written Lua.
  - `Data/` — the five generated tables (`ModelsData.lua`, `AbilitiesData.lua`,
    `CoordsData.lua`, `ConditionsData.lua`, `NotesData.lua`), and the sync target of
    `../psm-data`'s `config.sync_output_to_addon()`. **Never hand-edit these** —
    change the generator. The subfolder exists only to keep generated and
    hand-written Lua apart; it is not a separate addon.

Those five files come from a sibling repo, `../psm-data` (a Python Wowhead/Petopia
scraping pipeline).

## Loading the Models Browser

The browser is not parsed at login. `PSM.Loader` (`Shared/Loader.lua`) pulls it in:

- `PSM.Loader:EnsureBrowser(silent)` — loads it, returns true when usable. Pass
  `silent` from passive callers (row rendering, anything that can fire repeatedly)
  so a disabled module can't spam chat. Refuses during combat.
- `PSM.Loader:IsBrowserAvailable()` — *"present and enabled"*, not *"loaded"*. **UI
  affordances must use this**, never a `if PSM.ModelsPanel then` test: under
  `LoadOnDemand` the module is legitimately absent until first use, so gating a
  button or tooltip on its presence disables it permanently. This was a real bug.

Three rules that are easy to break:

- **Core's `.toc` must never list the browser in `## OptionalDeps`.** That means
  "load this before me if enabled", which both defeats `LoadOnDemand` *and* inverts
  load order so it runs before `_G.PSM` exists. Dependency direction is one-way: the
  browser declares `RequiredDeps` on core, core declares nothing about the browser.
- **Don't capture another module's table into a file-scope local** (e.g. `local cfg =
  PSM.Config` at the top of a file). If load order ever shifts you capture `nil` and
  fail much later at first use, with a misleading stack. Read it inside the function.
- **Don't add a third addon folder without a demonstrated need.** One was tried (a
  separate data addon, so core could load tables without the browser UI) and reverted:
  every "data only" caller turned out to need the browser's own resolvers
  (`PSM.PetModels`, `PSM.TamingChecker`), so the tier was never exercised and it cost
  users a third entry in the AddOns list.

## Repo layout gotcha

The directory containing this repo (referred to below as the **PSM workspace
root**) is itself **not** a git repo. `psm-addon` (this repo) and `psm-data` are
two independent sibling git repos one level down. Check `git status` before
assuming which repo you're committing to.

For the full cross-repo picture — every `psm-data` pipeline stage, which
`Manual/` CSV feeds which script, and the exact bridge point
(`config.sync_output_to_addon()`) that copies compiled `.lua` tables into
this repo — see `../architecture.html` (an interactive diagram one level up,
outside both repos; open it in a browser, or `Read` it directly since the
node/edge data is plain JS literals).

`index.html` at the repo root is a standalone feature-request form (no
build step, no server) that walks users through picking a panel/feature
area and posts the result as a pre-filled GitHub issue against
`ginutty-code/psm-addon`. It's static and self-contained — edit it directly
if the panel list in its `PANELS` array drifts from the addon's actual
panels.

## Symlinks

Both addon folders are symlinked into the live WoW retail `Interface/AddOns`
folder, already set up and working (exact local path in `CLAUDE.local.md`, which
is untracked). Editing files here is enough — no build or copy step.
**Live testing (reload UI, checking for Lua errors) is done by the user in-game,
not by Claude.** Creating a new symlink needs an elevated shell, so if a future
change adds an addon folder, hand the user the `New-Item -ItemType SymbolicLink`
command rather than trying to run it.

## Global architecture

Everything hangs off one global table, `_G.PSM`, created once in
`PetStableManagement/Core.lua`. Every module file opens with:

```lua
_G.PSM = _G.PSM or {}
local PSM = _G.PSM
```

then attaches itself as `PSM.Utils`, `PSM.ModelsFilters`, `PSM.NPCDataLoader`,
etc. There is no per-component/per-view local state — filter state lives in
one shared mutable table, `PSM.state` (declared in `Core.lua`), persisted to
`PetStableManagementDB` (SavedVariables) plus a second SavedVariable,
`PSM_UserNotes`.

## The UI kit — build frames with `PSM.Widgets`, not `CreateFrame`

`PetStableManagement/UI/` holds four files, loaded before anything that builds a
frame. They know nothing about pets; they take a parent and an options table.

- **`Theme.lua`** — the font path, the size ramp (`Theme.SIZE.BODY` etc.), the grey
  ramp (`Theme.COLOR.*`), the four backdrop presets and their fill colours. It does
  *not* duplicate `PSM.Config.COLORS`, which owns the semantic/state colours.
- **`Skin.lua`** — `PSM.Skin.Apply(frame, skinType)`. **The only file allowed to
  reference the `ElvUI` global.** Skin types live in a handler table; an unknown type
  is counted in `PSM.Skin.unhandled` (inspect with `/dump PSM.Skin.unhandled`) rather
  than silently ignored, which is how `"scrollframe"` went four call sites deep doing
  nothing. There is deliberately **no pcall** around the handlers: a swallowed ElvUI
  error is invisible on a non-ElvUI client, which is where most testing happens.
- **`Tooltip.lua`** — `PSM.Tooltip.Attach(frame, spec, extra)` wires OnEnter/OnLeave
  from a declarative spec, so a tooltip can't be left on screen by an early return.
  `spec` may be a `function(frame)` for live contents; returning nil suppresses it.
  Content comes from exactly one of `title`+`lines`, `hyperlink`, or `spellId`.
  `PSM.Tooltip.AddLines(lines, tooltip)` appends to an already-built tooltip, for
  Blizzard `TooltipDataProcessor` post-calls — a spell that resolves asynchronously is
  rebuilt internally, discarding anything added right after the `Set*` call.
  **`GameTooltip` has no maximum width**: it sizes to its widest line, so a caller
  emitting a long joined list must break it into lines itself (see `NPCRow`'s
  `WrapJoin`) or set `wrap = true`.
- **`Widgets.lua`** — 16 factories: `Backdrop`, `Frame`, `MovableFrame`, `Label`,
  `Button`, `IconButton`, `CloseButton`, `ResizeGrip`, `CloseOnEscape`, `EditBox`,
  `MaskTexture`, `Line`, `Texture`, `Tab`, `SectionHeader`, `CheckBox`. Read the file —
  each carries a comment saying what evidence justified it. `CheckBox` returns a box
  with `:SetTriState(nil | true | "inverted")`; the kit renders the three filter states,
  the caller owns their meaning and cycle order.

**Everything `PSM.Widgets` returns is already skinned.** That is the whole point: the
count of hand-written `ApplyElvUISkin` calls should only ever go down. `IconButton` is
the one exception, unskinned by default — ElvUI's `HandleButton` strips exactly the
textures those buttons are made of.

**Defaults produce consistency; parameters only allow it.** A widget with one
obviously correct value should *default* to it (`Theme.CONTROL.CHECKBOX`), and the
call site should stay silent unless it genuinely needs to differ. This was learned the
hard way: taking `size` at every `CheckBox` call site let two panels drift to 16px vs
20px, which is the same divergence the kit exists to remove, just relocated from
`CreateFrame` blocks into options tables.

**Two safety nets, both inspectable in-game rather than noisy:**
`/dump PSM.Skin.unhandled` lists skin types passed that no handler knows (typos), and
`/dump PSM.Widgets.unknownOptions` lists option keys a factory didn't understand.
Options tables fail *silently* — a misspelled key is simply never read — so each
factory declares its vocabulary in `OPTIONS` at the top of `Widgets.lua`. Add new keys
there or they will be recorded as unknown.

`PSM.UI:ApplyElvUISkin` / `PSM.UI.ElvUITexture` still exist as thin forwarders to
`PSM.Skin` for the not-yet-migrated call sites. Don't call them in new code, and
delete them when the last caller is gone.

Context menus go through **`PSM.Utils:ShowContextMenu(menuList)`** — the single
implementation. Two verbatim copies used to exist alongside it.

### Migration status (A6, ongoing)

Migrated, each with zero raw `CreateFrame` / `CreateFontString` / `CreateTexture` /
`GameTooltip:` / skin calls: `Shared/PopUpManager.lua`, `Shared/Dialogs.lua`,
`Shared/RowManager.lua`, `OwnedPets/TeamsPanel.lua`, `OwnedPets/Export.lua`,
`OwnedPets/Filters.lua`, `OwnedPets/GroupedView.lua`,
`ModelsBrowser/SpecialTames.lua`, `ModelsBrowser/ModelsFilters.lua`,
`ModelsBrowser/AbilityBrowser.lua`, `ModelsBrowser/ModelsPanel.lua`,
`ModelsBrowser/NPCRow.lua`.

Repo-wide, twelve files in: `ApplyElvUISkin` **86 → 17**, `CreateFrame` **193 → 42**.

`PopUpManager.lua` is the reference. The only `SetBackdropColor` left in it is a
*runtime recolour*, not construction — **that is the line to draw** when migrating
another file. Density counts that include `SetBackdropColor` overstate a file's real
construction work; count `SetBackdrop({` instead.

**One `CreateFrame` may legitimately survive a migration:** an invisible, parentless
frame that exists only to hold `OnUpdate` or `RegisterEvent` handlers is not a widget
and should not come from the widget kit (`ModelsPanel`'s zone listener, `NPCRow`'s
`ResizeDriver`). In *core*, prefer `PSM.CreateFrame` (Core.lua's alias, which the
headless tests can stub); in the *browser*, use raw `CreateFrame` — reaching for the
core alias at browser file scope is the cross-addon capture pattern `ModelRow.lua` was
fixed for.

Remaining, densest first — **re-measure rather than trusting this list**, the original
one was a partial survey that omitted the two densest files in the addon:

`OwnedPets/GridView.lua` (17), `ModelsBrowser/ModelRow.lua` (16), `Core.lua` (15),
`Shared/Minimap.lua` (14), `Shared/PanelManager.lua` and `Shared/OptionsPanel.lua` (13),
`OwnedPets/Panel.lua` (12), `OwnedPets/DragDrop.lua` (11), `Shared/Menu.lua` and
`Shared/Broker.lua` (10), `Shared/Utils.lua` (7), `OwnedPets/Row.lua` (6).
`Shared/UI.lua` is the `ApplyElvUISkin` shim and goes when its last caller does.

```bash
for f in $(find PetStableManagement* -name '*.lua' -not -path '*/Data/*' | grep -v /UI/); do
  n=$(( $(grep -c -F 'CreateFrame(' $f) + $(grep -c -F ':CreateFontString(' $f) \
      + $(grep -c -F ':CreateTexture(' $f) + $(grep -c -F 'GameTooltip:' $f) \
      + $(grep -c -F 'ApplyElvUISkin' $f) + $(grep -c -F 'SetBackdrop({' $f) ))
  [ "$n" -gt 2 ] && printf '%3d  %s\n' "$n" "$f"
done | sort -rn
```

The full task record — every measurement, every bug found while migrating, and the
reasoning behind each kit addition — is in `../ARCHITECTURE_PLAN.md` (outside both
repos). **Read its A6 sections before continuing the migration**; several decisions
there look arbitrary without the evidence that produced them.

## Models View / NPC View share filter state — reload through one entrypoint

The Models Browser panel has two render modes controlled by
`panel.modelsViewMode` (`"displayId"` or `"npc"`), not two separate
components. Both modes read the *same* `PSM.state.selectedModelsFamilies` /
`.selectedExpansions` / `.selectedLocations` filters.

Whenever you change filter state and need to refresh the visible list, call
the shared helper — **don't call `PSM.ModelsDataLoader` directly**, or you'll
silently skip refreshing the NPC view when it's the active mode (this was a
real bug, fixed 2026-08-09):

```lua
PSM.ModelsFilters:ReloadAndSummarise()
```

It branches on `panel.modelsViewMode`, calls the right loader
(`ModelsDataLoader` vs `NPCDataLoader`), then updates the filter summary and
persists selections. `AbilityBrowser.lua`'s and `SpecialTames.lua`'s "Apply"
buttons both route through this now.

## README.md is a feature list, not a changelog

Don't add or reword bullets to narrate what recently changed ("Enhanced X",
"Revised Y", "X now does Z", "New panel for..."). Write every bullet as a
plain present-tense description of current behavior. Version history lives
in git and in the CurseForge changelog when a new version is published —
duplicating it in the README just makes it bulkier over time.

## Tests

A headless suite runs the addon's frame-free code outside the game, in
`Tests/` (repo root, listed in no `.toc`, so never shipped). Run from the repo root:

```bash
lua.exe Tests/run.lua                        # preferred; any Lua 5.1 interpreter
uv run --with lupa python Tests/run.py       # no-install fallback, same specs
```

Both execute `Tests/suite.lua`, the single source of truth, and exit non-zero on
failure. The fallback uses lupa's bundled **Lua 5.1** — the client's own dialect,
so results match; don't let it pick up a 5.4/5.5 runtime.

- `Tests/spec/models_data_spec.lua` — golden tests for the generated `ModelsData`:
  7,700 records, `Index`/`NpcId` inverse consistency, 61/12/4/394 lookup counts,
  every ID resolving through its lookup table, and the T3 spot-check NPCs. **This is
  the guard against psm-data regenerating a shape the addon can't read** — the
  failure that made the addon unloadable mid-migration and was only found in-game.
- `Tests/spec/utils_spec.lua` — the pure helpers in `Shared/Utils.lua`.

When adding a spec, append it to `SPECS` in `Tests/suite.lua` (explicit list: Lua has
no portable directory walk, and a visible diff per spec is a feature).

`Tests/wow/stubs.lua` holds stand-ins for client APIs. **A stub must behave like the
real API for the cases under test, or not exist.** A catch-all no-op frame that
swallows every call turns real bugs into passing tests; leave such code untestable
until the layering work separates it.

## CI

`.github/workflows/ci.yml` runs on every push and PR, in two parallel jobs:
`luacheck` and the test suite (via `lua5.1 Tests/run.lua`, the primary entry point,
so it doesn't only ever exercise the lupa fallback).

The lint job **gates on errors, not warnings**. luacheck exits 1 for warnings and
≥2 for errors; the project carries a stable warning baseline (63), so failing on any
warning would fail every run. The count is printed in the job log — treat a change
in it as something you caused, and account for it.

There is no CI in `psm-data` yet. Its gate is `ruff check .`, run manually.

## Linting

`luacheck` is installed outside this repo and is **not** on PATH — invoke it by
full path, or add its folder to PATH to run it as `luacheck`. The exact local
path is in `CLAUDE.local.md` (untracked). Run from the repo root:

```bash
luacheck PetStableManagement PetStableManagement_ModelsBrowser Tests
```

The current clean baseline is **63 warnings / 0 errors**. Treat any change in it as
something you introduced, and account for it — a drop is as much a claim as a rise,
and should be attributable to a specific edit.

`.luacheckrc` lists the actual WoW API globals and project-defined globals
(`PSM`, `PetStableManagementDB`, `AbilitiesData`, `ModelsData`, `CoordsData`,
slash-command globals, etc.) this codebase references — built by running
luacheck with no globals config and collecting every "accessing/setting
undefined global" warning, not copied from a generic WoW globals list. When
a new Blizzard API shows up as undefined:

- Addon reads it but never assigns it → add to `read_globals`.
- Addon defines/assigns it (a new project-global data module, a new
  SavedVariable, a new slash command) → add to `globals`.

Don't silence warning 113 (undefined global) wholesale — it's the main
typo-catcher for WoW API calls in this codebase. `212/self` and `432/self`
(unused/shadowed `self` in frame callbacks) and `611`/`612` (whitespace-only)
are ignored as pure noise from idiomatic WoW callback signatures.
