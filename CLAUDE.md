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

**Core is private; the global is a bridge.** Every core file opens with the client's
own calling convention and attaches itself to the addon's private namespace:

```lua
local _, ns = ...

ns.Utils = {}
```

The client hands each *addon* one table and passes it to every file in that addon, so
`ns` is shared across core and reachable from nowhere else. `PetStableManagement` and
`PetStableManagement_ModelsBrowser` are two addons and therefore get two different
namespaces — which is why `_G.PSM` still exists, and all it is now is the bridge
between them.

Three rules follow, and they are enforced by tests rather than by memory:

- **What core exports is declared, in `Shared/PublicAPI.lua`** — eleven names, loaded
  last in the `.toc` so every module has attached itself first. Everything else stays
  private. `_G.PSM` carries a trap: reading a core member that was *not* published
  raises an error naming the key, instead of returning the nil that used to be silently
  guarded away. Adding a name is a real decision — it can never change again without
  touching both addons — so prefer giving the browser a *service* (`RowManager:ReleaseModel`
  is the model) over widening the surface.
- **Core reaches the browser through `ns.Browser`**, never `ns` directly. It forwards
  reads *and writes* to `_G.PSM`, so `ns.Browser.` in a core file means exactly one
  thing: this crosses into the other addon. `ns.Browser.ModelsPanel` is nil when the
  browser has not loaded, which is what every gate expects.
- **The browser is unconverted** and still uses `_G.PSM` throughout — it is the
  consumer side of the bridge, so that is correct, not leftover.

`Tests/spec/boundary_spec.lua` enforces both directions statically (browser → core
against `PUBLIC_API`, core → browser against `ns.Browser`), and
`Tests/spec/publicapi_spec.lua` runs the real file to prove the trap raises on an
internal, stays quiet for an absent browser member, and lets writes through.

Elsewhere in this document a module is named `PSM.Widgets`, `PSM.Skin`, `PSM.state` and
so on. That is the name a *user* types (`/dump PSM.Skin.unhandled`) and the name the
browser uses; inside core the same table is `ns.Widgets`, `ns.Skin`, `ns.state`.

There is no per-component/per-view local state — filter state lives in one shared
mutable table, `ns.state` (declared in `Core.lua`, published as `PSM.state`), persisted
to `PetStableManagementDB` (SavedVariables) plus a second SavedVariable,
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
- **`Widgets.lua`** — 17 factories: `Backdrop`, `Frame`, `MovableFrame`, `Label`,
  `Button`, `IconButton`, `CloseButton`, `ResizeGrip`, `CloseOnEscape`, `EditBox`,
  `MaskTexture`, `Line`, `Texture`, `Tab`, `SectionHeader`, `CheckBox`, `Slider`. Read
  the file — each carries a comment saying what evidence justified it. `CheckBox`
  returns a box with `:SetTriState(nil | true | "inverted")`; the kit renders the three
  filter states, the caller owns their meaning and cycle order. `Slider` owns its value
  caption (via `format`) and offers `:SetValueSilently(v)` — **a WoW slider has no
  `userInput` flag**, so a programmatic `SetValue` is indistinguishable from a drag and
  every caller otherwise invents the same module-level `isResetting` guard.

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

`PSM.UI:ApplyElvUISkin` / `PSM.UI.ElvUITexture` are **gone** — they were forwarders to
`PSM.Skin` for pre-kit call sites, and the last of the 86 migrated with
`OwnedPets/Row.lua`. Call `PSM.Skin.Apply` directly, or build the widget with
`PSM.Widgets` and get it for free.

Context menus go through **`PSM.Utils:ShowContextMenu(menuList)`** — the single
implementation. Two verbatim copies used to exist alongside it.

### Shared pet content

**`PSM.PetTooltip`** (`OwnedPets/PetTooltip.lua`) owns what a pet says about itself:

- `ABILITY_BUCKETS` — the four ability groups, in display order, with their prefix and
  colour. Used by both model views, the expanded row, and the teams panel. There were
  four independent copies of this table and three had drifted (`[Spec]` gold in three
  and yellow in the fourth, `[Other]` off by a shade, one with a stray leading space).
- `IsBucketed(abilities)` — bucketed layout vs the flat list older saved data uses.
- `Spec(pet, opts)` — the whole pet tooltip as a `PSM.Tooltip` spec. **Every owned-pet
  tooltip is this one**, so a pet reads the same wherever it is looked at. Only two
  things vary: `opts.hints` (the trailing interaction block — grouped view explains
  reordering, teams explains dragging) and `opts.slotLabel` (teams slots are team
  positions, and slot 6 is the companion). Anchoring stays with the caller; the teams
  panel patches `spec.x/y` after building.

A tooltip that comes out thinner than its siblings is a **data** problem, not a
formatting one — the builder only emits a line when the field is there. Team slots were
missing `level` and `tamer` because `PSM.Teams:SlotRecord` (see below) dropped them.

**Pet records carry `level`, not `petLevel`.** There are two collection paths in
`Data.lua` and they used to produce two different shapes: `CollectStabledPets` deep-copies
Blizzard's record (which has `level`), while `ProcessPetInfo` builds active pets field by
field and renamed it to `petLevel`. Each consumer then picked whichever key worked for
the pets it happened to look at — the tooltip read `level` and so showed nothing for
slots 1-5; Export read `petLevel` and so showed nothing for stabled pets. Both paths
normalise to `level` now. **When adding a field, add it to both paths.**

**Team slots go through `PSM.Teams:SlotRecord(pet)`** — the one definition of what a
team stores. A slot is a *snapshot*, not a reference: teams save independently of the
live stable, so a pet can sit in a team while stabled on another character or gone
entirely. It accepts either a live `C_StableInfo` record or a processed PSM pet. There
were three hand-written copies of the field list (one in `TeamsData`, two in
`Dialogs`), all agreeing on the same nine fields and all omitting `level` and `tamer` —
and the two building from an already-processed pet were discarding values they held.

**`X = SomeGlobal` at file scope is a snapshot, not a reference.** Core.lua's "WOW API
REFERENCES" block is now only the globals that are guaranteed up before any addon runs.
Anything load-on-demand is called through the global at the point of use:

- **Blizzard's stable frame** — use `PSM.GetStableFrame()`. There is deliberately no
  `PSM.StableFrame` field: `Blizzard_StableUI` is load-on-demand, so a field would be a
  snapshot again, and there are eight entry points into pet collection, so no single
  handler can be trusted to refresh it first.
- **`UIDropDownMenu_*` / `ToggleDropDownMenu` / `EasyMenu`** — call the globals.
  `Blizzard_UIDropDownMenu` is a separate addon and need not load before us. Three of
  these aliases had no callers; the rest of the addon already used the globals.
- **`PSM.GetSpellInfo` is expected to be nil** on modern clients — it is the legacy half
  of `Utils:GetSpellNameCompat`, which prefers `C_Spell.GetSpellName`. Not a bug.

The stable-frame Teams buttons were the same bug from the other side: they required a
Blizzard child frame (`PetSelectButton`) that turns out to be **transient**, and a bare
`return` when it was missing removed the feature for a whole session with nothing
logged. Anchors there are optional and repositioned per show. **A silent early return in
event-driven code is indistinguishable from the feature not existing** — if a handler can
give up, it should say so.

**Counting record builders is a cheap audit.** Three separate shapes for "a pet" have
now produced three user-visible bugs in a row. If you add a field to a pet, grep for
every place a pet-shaped table is constructed.

**`PSM.RowManager.MODEL_HINTS`** is the rotate/move/zoom text, previously written out
in full in four files. **`PSM.RowManager:ShowHoverButtons(model)` /
`:HideHoverButtons(model)`** are the overlay-button fade, public because a view that
wants its own model tooltip must re-attach `OnEnter`/`OnLeave` and would otherwise drop
RowManager's pair — which is exactly what both views did, each with its own hardcoded
copy of the button list instead of walking `model.hoverButtons`.

### Migration status (A6 — complete)

**Every hand-written file in both addons builds its frames through `PSM.Widgets`.** No
raw `CreateFrame` / `CreateFontString` / `CreateTexture` / `GameTooltip:` / skin call
survives outside the kit, apart from the deliberate exceptions below.

Repo-wide: `ApplyElvUISkin` **86 → 0** (the `PSM.UI:ApplyElvUISkin` and
`PSM.UI.ElvUITexture` shims are deleted — skinning is `PSM.Skin.Apply`, and almost
always `PSM.Widgets` doing it for you), `CreateFrame` **193 → 6**.

Those six are all the same thing: an invisible, parentless frame holding `OnUpdate` or
`RegisterEvent` handlers. **That is not a widget and must not come from the kit** —
`Events.lua`'s event frame, `RowManager` and `ModelsPanel`'s timer frames,
`DragDrop`'s cursor-tracking frame, `NPCRow`'s `ResizeDriver`, `TamingChecker`'s cache
frame. In *core*, use `PSM.CreateFrame` (Core.lua's alias, which the headless tests can
stub); in the *browser*, use raw `CreateFrame` — reaching for the core alias at browser
file scope is the cross-addon capture pattern `ModelRow.lua` was fixed for.

To confirm nothing has regressed, and to see those six named:

```bash
for f in $(find PetStableManagement* -name '*.lua' -not -path '*/Data/*' | grep -v /UI/); do
  grep -Hn -F -e 'CreateFrame(' -e ':CreateFontString(' -e ':CreateTexture(' \
    -e 'GameTooltip:' -e 'ApplyElvUISkin' -e 'SetBackdrop({' $f
done
```

Two hits it reports are comments, not code — the pattern list matches prose too. Judge by
reading the line, not by the count.

**Two counting traps, both of which cost time during A6.** A density score says how much
a file does by hand, not what kind: `GridView` scored 17 and every one was `GameTooltip:`,
zero construction, because RowManager's migration had already covered its widgets. And
`SetBackdropColor` is usually a *runtime recolour* rather than construction, so counts
including it overstate the work — count `SetBackdrop({`. `PopUpManager.lua` is the
reference file for where that line falls.

The full task record — every measurement, every bug found while migrating, and the
reasoning behind each kit addition — is in `../ARCHITECTURE_PLAN.md` (outside both
repos). **Read its A6 sections before continuing the migration**; several decisions
there look arbitrary without the evidence that produced them.

## Models View / NPC View share filter state — reload through one entrypoint

The Models Browser panel has two render modes controlled by
`panel.modelsViewMode` (`"displayId"` or `"npc"`), not two separate
components. Both modes read the *same* `PSM.state.selectedModelsFamilies` /
`.selectedExpansions` / `.selectedLocations` filters.

**Writing a filter slice is enough — do not call a reload as well.** The five
selection sets and the toggles are store slices, and `ModelsFilters` holds one
`PSM.Store:Watch` subscription over them. Writing through `PSM.Selections` or
`PSM.FilterState` schedules the refresh:

```lua
PSM.Selections:Set("families", "Wolf", true)   -- that is the whole call site
```

Nine hand-written `ReloadAndSummarise() + UpdateDynamicFilters()` pairs used to sit after
writes like that one. They are gone; adding a tenth is a regression, not a precaution.
The store coalesces a burst into one flush on the next frame, so a bulk write
(`SetAll` over fifteen locations) reloads once rather than fifteen times.

**When state changes somewhere the store can see but nothing can bump, call
`PSM.Store:Touch()`.** Fingerprinted slices (`search`, `pets`, `favorites`, `zone`) have no
write funnel, so nothing announces them; `Touch` asks every watcher to re-read its
dependencies. It takes no argument on purpose — it does not claim *what* changed, so it
cannot claim wrong, and it fires nothing when nothing moved. The search box is the live
example: its home is a widget, so it fingerprints rather than counts, and its callback is
one `Touch`.

**The explicit helper is still right for a refresh that isn't driven by state at all** —
a view-mode switch, say:

```lua
PSM.ModelsFilters:ReloadAndSummarise()
```

**Don't call `PSM.ModelsDataLoader` directly** — you'll silently skip refreshing the NPC
view when it's the active mode (a real bug, fixed 2026-08-09). `ReloadAndSummarise`
branches on `panel.modelsViewMode`, calls the right loader (`ModelsDataLoader` vs
`NPCDataLoader`), then updates the filter summary and persists selections.
`AbilityBrowser.lua`'s and `SpecialTames.lua`'s "Apply" buttons still route through it.

Two things the watcher deliberately does not cover, both asserted in `store_spec`:
`panel` is not watched (it bumps when the filter system is rebuilt, and watching it would
turn construction into a reload), and **only a `Bump` or a `Touch` wakes a flush** — so
`pets` and `favorites`, which nothing Touches yet, keep their existing refresh paths.

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
  the record count, `Index`/`NpcId` inverse consistency, the distinct lookup counts,
  every ID resolving through its lookup table, and the T3 spot-check NPCs. **This is
  the guard against psm-data regenerating a shape the addon can't read** — the
  failure that made the addon unloadable mid-migration and was only found in-game.

  **After a data refresh it fails on exactly two literals, by design** — the record
  count and the distinct-zone count. Both guard against generation being cut short or a
  lookup table losing entries, which is otherwise undetectable: a truncated run is
  perfectly self-consistent. *Read the numbers before bumping them.* Movement of tens is
  a normal Wowhead refresh; thousands is a generator regression, as is any spot-check
  failing on a **name, family or zone**.

  Nothing else in that spec is allowed to churn, so those two stay a real checkpoint
  instead of one of a crowd. In particular the spot-checks assert fields only, never the
  dense index an npcId resolves to — that index is a *position*, shifted by any earlier
  insertion, and pinning it produced five guaranteed failures per refresh that taught
  nothing except the habit of bumping numbers. The counts live in the spec, not here.
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
≥2 for errors; the project carries a stable warning baseline (38), so failing on any
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

The current clean baseline is **38 warnings / 0 errors**. Treat any change in it as
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

**First ask whether it is a Blizzard API at all.** `read_globals` began with
`CHECKBOX_INDENT_X` at the top of it — not an API, but a layout constant
`OptionsPanel.lua` used and never declared. Listing it silenced the warning that was
correctly reporting a missing local, and the checkbox spent however long anchored at a
nil offset (SetPoint reads it as 0). A name that isn't `C_Something`, isn't CamelCase
Blizzard style, and appears in exactly one file is a typo or a missing `local`, not a
new API — grep for it before adding it.

Don't silence warning 113 (undefined global) wholesale — it's the main
typo-catcher for WoW API calls in this codebase. `212/self` and `432/self`
(unused/shadowed `self` in frame callbacks) and `611`/`612` (whitespace-only)
are ignored as pure noise from idiomatic WoW callback signatures.
