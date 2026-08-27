# PSM Architecture Plan

A cross-repo plan spanning `psm-addon` and `psm-data`, tracked here in `psm-addon/docs/`
as of 2026-08-27 alongside `architecture.html` and
`DATA_STRUCTURE_OPTIMIZATION_PLAN.md` (all three spent their working life in the
untracked `PSM/` workspace root, which is *not* a git repo).

Written 2026-08-11, immediately after the data-structure optimization plan closed out
(T9: static floor 13.26MB -> 6.57MB). That plan fixed *what the data looks like*. This
one is about *how the code around it is organized*. **CLOSED 2026-08-27** — see the
status table under "Tasks" below.

## Scope, and what this is not

**This is not a rewrite.** `psm-addon` is ~60k lines, shipped on CurseForge, with real
users whose `PetStableManagementDB` must survive. A from-scratch rebuild would be
months of work whose best possible outcome is "the same addon again." Every task below
is a retrofit that leaves the addon shippable at the end of it, in the same style as
the T-tasks.

What this document is: a **target architecture** described precisely enough to migrate
toward incrementally, plus a ranked task list. Some tasks may never get done. That's
fine — the value of writing the target down is that each retrofit moves in a known
direction instead of a locally-convenient one.

**Non-goals:** changing what the addon does, changing the SavedVariables format
(except through explicit versioned migrations), changing the `psm-data` pipeline stages
01-15, or touching `index.html`.

---

## Verdict on `architecture.html`

**Keep. Freeze now, rewrite the addon half after, never discard.**

It is two documents in one file with opposite lifetimes:

- **Columns 1-6 + the `Manual/` rail + the `patch` edge** (psm-data pipeline) — durable.
  Unaffected by everything in this plan except one edge (see A1). It is also the only
  artifact anywhere that records which of the nine correction CSVs feeds which script,
  and that the missing Whiptail family (id 315) is a constant hardcoded inside
  `04_extract_wowhead_families.py` rather than a `Manual/` file. Neither README says this.
- **Columns 8-10** (addon module map) — a dated "as-built" snapshot. Goes stale the
  moment A3 lands.

Three actions, in order:

1. **Now (5 minutes):** add a dated banner to the header: *"Addon-side map is as-built
   as of 2026-08-11; see `ARCHITECTURE_PLAN.md` for the target."* Nothing else.
2. **During:** use the `edges` array as a **coupling checklist**. Every edge whose
   source or target is in `col 8/9/10` is a dependency this plan must either justify or
   delete. Two are already flagged as shortcuts in the file's own footer —
   `['a_mo','ml_pm']` and `['a_mo','ml_nd']`, both modules reading `_G.ModelsData`
   directly — and both collapse into a single edge into `Data/Access.lua` under the
   target architecture. **Success criterion for this plan: the redesigned diagram has
   strictly fewer addon-side edges than the current one.**
3. **After A3-A8:** rewrite `stages[6..9]` and the addon portion of `edges` in place.
   That's ~90 lines of plain JS literals. All CSS, the grid layout, the SVG connector
   drawing, and the entire psm-data half survive untouched. The psm-data half changes by
   exactly one edge: the `bridge` edge gets relabelled from an implicit side effect to
   an explicit sync step (A1).

---

## Target architecture

### 1. Three addon folders, not two

| Folder | Load | Contains | Why separate |
|---|---|---|---|
| `PSM` | always | Core + Owned Pets + Teams + Options + minimap/broker/slash | The always-paid floor. Must stay small. |
| `PSM_Browser` | **LoadOnDemand** | Models/NPC browser, Abilities, Special Tames, Roulette | Never loaded for users who don't open it |
| `PSM_Data` | **LoadOnDemand** | Only generated tables + a schema stamp | Different change cadence; sync target is one clean directory; loadable *without* the browser UI |

The `PSM_Data` split is not cosmetic. `PopUpManager.lua:1354`'s taming-info fallback
exists specifically to fix an **Owned Pets** panel display — i.e. core already needs
`ModelsData` in a case that has nothing to do with the browser UI. Today that's served
by loading 13MB of browser addon. Split, it's `LoadAddOn("PSM_Data")` and nothing else.

A fourth tier (`CoordsData` + `NotesData`, needed only when a popup opens — 834KB +
~100KB) is deliberately **not** proposed yet: more folders means more clutter in the
user's AddOns list, and the win is unmeasured. Revisit only with numbers.

### 2. Layers — and the load order *is* the dependency order

Six layers. **A file may only reference things in its own layer or lower.** The `.toc`
lists them in exactly this order, so load order enforces the rule for free at runtime,
and `.luacheckrc` enforces it statically (see §4).

```
0  Core/       pure Lua + the API shim.        No frames. No state. No domain concepts.
1  State/      the store, schema, migrations.  No frames.
2  Domain/     game concepts: pets, teams,     No frames.
                queries, groups.
3  Services/   side effects: events, session,  Frames only as invisible event sinks.
                persistence, capabilities.
4  UI/         widgets, theming, pooling,      No domain knowledge. Nothing in here
                lists, windows.                 knows what a "pet" is.
5  Features/   composition. Wires a Domain     The only layer allowed to know
                query to a UI list.             about both sides.
```

The single most valuable line in that table is layer 4's constraint. Today
`RowManager.lua` (a shared UI module) reads `model.petData.guid` and calls into
`PSM.DragDrop` — UI and domain are fused, which is why there are five near-duplicate
row implementations that can't be shared.

### 3. Folder structure

```
psm-addon/
├─ PSM/                              ← core addon, always loaded
│  ├─ PSM.toc
│  ├─ Libs/                          third-party, vendored, never edited
│  │  ├─ LibStub/  LibDataBroker-1.1/  LibDBIcon-1.0/
│  ├─ Core/
│  │  ├─ Namespace.lua               ns bootstrap, module registry, layer assert
│  │  ├─ Compat.lua                  ★ the ONLY file that touches WoW API globals
│  │  ├─ Const.lua                   pure constants (Config.lua's data half)
│  │  ├─ Lib.lua                     table/string/math helpers, zero WoW API
│  │  └─ Log.lua                     error boundary, ring buffer, /psm debug
│  ├─ State/
│  │  ├─ Schema.lua                  SavedVariables shape + defaults, single source
│  │  ├─ Migrate.lua                 versioned migrations, run once at ADDON_LOADED
│  │  ├─ Store.lua                   ★ slices, version counters, set/get/subscribe
│  │  └─ Selector.lua                ★ memoized derived values keyed on slice versions
│  ├─ Domain/
│  │  ├─ Pet.lua                     identity, duplicate key, exotic/family/spec
│  │  ├─ Stable.lua                  collect + normalize owned pets
│  │  ├─ Teams.lua                   team model + validation
│  │  ├─ Groups.lua                  pet-group model
│  │  └─ Query.lua                   ★ the one filter → sort → group pipeline
│  ├─ Services/
│  │  ├─ Events.lua                  dispatcher, combat lockdown
│  │  ├─ StableSession.lua           ★ Idle→Opening→Settling→Ready state machine
│  │  ├─ Capability.lua              ★ optional-module registry (inverts RequiredDeps)
│  │  └─ Persist.lua                 debounced save, logout flush
│  ├─ UI/
│  │  ├─ Theme.lua                   colors, fonts, opacity, backdrop specs
│  │  ├─ Skin.lua                    ★ ElvUI + default skinning, ONE place
│  │  ├─ Widgets.lua                 ★ factory: Button/CheckBox/EditBox/Label/Backdrop
│  │  ├─ Tooltip.lua                 ★ Tooltip:Attach(frame, spec)
│  │  ├─ Pools.lua                   ★ frame pools + ModelPool with a hard LRU cap
│  │  ├─ List.lua                    ★ the only list implementation (ScrollBox)
│  │  ├─ Window.lua                  base panel (was PanelManager:CreateBasePanel)
│  │  ├─ Dialog.lua                  modal / confirm / input
│  │  └─ Popup.lua                   magnifier + roulette shell
│  └─ Features/
│     ├─ OwnedPets/  init.lua Panel.lua ListView.lua GridView.lua GroupedView.lua
│     │               RowSpec.lua Actions.lua DragDrop.lua Export.lua
│     ├─ Teams/      init.lua Panel.lua RowSpec.lua
│     ├─ Options/    init.lua Panel.lua Definitions.lua
│     ├─ Minimap.lua  Broker.lua  SlashCommands.lua  FloatingMenu.lua
│
├─ PSM_Browser/                      ← LoadOnDemand
│  ├─ PSM_Browser.toc                ## RequiredDeps: PSM   ## LoadOnDemand: 1
│  ├─ Data/
│  │  ├─ Schema.lua                  ★ asserts PSM_Data's SCHEMA version, fails loud
│  │  ├─ Access.lua                  ★ the ONLY file that knows the columnar shape
│  │  └─ Lazy.lua                    LoadAddOn("PSM_Data") on first need
│  ├─ Domain/
│  │  ├─ Models.lua                  family/display grouping (was PetModels.lua)
│  │  ├─ NpcQuery.lua                filter/sort spec, shared by both views
│  │  └─ Taming.lua                  eligibility check
│  └─ Features/
│     ├─ Browser/   init.lua Panel.lua ModelsView.lua NpcView.lua
│     │              Columns.lua FilterBar.lua
│     ├─ Abilities/ SpecialTames/ Roulette/
│
├─ PSM_Data/                         ← LoadOnDemand, 100% generated
│  ├─ PSM_Data.toc                   ## LoadOnDemand: 1
│  ├─ Schema.lua                     hand-written: version stamp + generatedAt
│  └─ ModelsData.lua  AbilitiesData.lua  ConditionsData.lua
│     CoordsData.lua  NotesData.lua
│
├─ Tests/                            ← repo root, never shipped (not in any .toc)
│  ├─ wow/                           WoW API stubs
│  ├─ spec/                          busted specs
│  └─ fixtures/
├─ Tools/build.ps1                   package for CurseForge
├─ .luacheckrc                       per-directory global rules (see §4)
└─ .github/workflows/ci.yml          luacheck + busted + schema compat
```

`Tests/` and `Tools/` sit at repo root, *outside* the three addon folders, so they are
never in the symlinked live directories and never shipped. WoW only parses files listed
in a `.toc`, but keeping them out entirely avoids the question.

### 4. Global vs. local — the actual rules

**`_G` gets exactly four kinds of entry, permanently:**

| Global | Why it must be global |
|---|---|
| `PetStableManagementDB`, `PSM_UserNotes` | WoW requires SavedVariables to be globals |
| `PSM` | Public API + cross-addon bridge. ~8 entries. Nothing else. |
| `SLASH_PSM1` / `SlashCmdList` entries | WoW requires it |
| *(nothing else)* | |

Notably **`ModelsData`, `AbilitiesData`, `CoordsData`, `ConditionsData`, `NotesData`
stop being globals.** They can't be addon-private (they cross an addon boundary), so
they go through the one bridge: `PSM_Data`'s files end with
`PSM.RegisterData("Models", ModelsData)`, and `PSM_Browser` reads them via
`Capability`. Five globals become zero, and the cross-addon handshake becomes an
explicit, greppable, single-site event instead of five ambient globals.

**Everything else lives on `ns`**, the addon-private table WoW hands to every file:

```lua
local addonName, ns = ...   -- second vararg; free, idiomatic, file-scoped
```

This replaces the `_G.PSM = _G.PSM or {}` preamble in all 32 files. It is not
cosmetic: `ns` is private per *addon*, so `PSM` and `PSM_Browser` cannot accidentally
collide, and nothing outside the addon can reach in and mutate internals.

**Local hoisting is mandatory in hot files.** A global read is a hash lookup in `_ENV`;
a local is a register slot. Over `for i = 1, #ModelsData.NpcId` (7,700 iterations) that
is measurable. Every file in `Domain/` and `Data/` opens with:

```lua
local addonName, ns = ...
local ipairs, pairs, type, tonumber = ipairs, pairs, type, tonumber
local tinsert, tsort, sformat = table.insert, table.sort, string.format
local API = ns.API
```

**`Core/Compat.lua` is the only file allowed to read WoW API globals.** It exports
`ns.API.CreateFrame`, `ns.API.C_StableInfo`, etc., and is where every
version-branch lives (e.g. `C_Spell.GetSpellName` vs `GetSpellInfo`, currently
open-coded in `Utils:GetSpellNameCompat`). `Core.lua:54-71`'s
`PSM.CreateFrame = CreateFrame` block is the right instinct in the wrong place — it's
a *partial* list, parked on the global table, so it neither localizes nor centralizes.

**And this rule is machine-enforced,** which is the point. `.luacheckrc` supports
per-path config, so the current flat `read_globals` list becomes:

```lua
read_globals = { "LibStub" }              -- baseline: almost nothing

files["PSM/Core/Compat.lua"]  = { read_globals = { --[[ the full WoW API list ]] } }
files["PSM/Features/*"]       = { read_globals = { "UIParent", "GameTooltip" } }
files["PSM_Data/*"]           = { globals = { "ModelsData", "AbilitiesData", ... } }
```

Any file that reaches for a WoW global outside `Compat.lua` now fails the lint. The
layering stops being aspirational.

*(Noted while reading: `.luacheckrc` still lists `InterfaceOptions_AddCategory` and
`InterfaceOptionsFrame_OpenToCategory`, the pre-Dragonflight options API, alongside the
modern `Settings` table. Worth confirming which path `OptionsPanel.lua` actually takes
and dropping the dead one — small, independent of everything here.)*

### 5. Centralized reusable functions — the inventory

Every row below was counted in the current tree, not guessed:

| New home | Absorbs | Count today |
|---|---|---|
| `UI/Widgets.lua` | raw `CreateFrame` calls | **190** across 20 files (`PopUpManager.lua` alone: 32) |
| `UI/Widgets.lua` | `CreateFontString` + hand-set font | **63** |
| `UI/Skin.lua` | hand-placed `ApplyElvUISkin(x, "type")` | **86** |
| `UI/Tooltip.lua` | `SetOwner`/`SetText`/`AddLine`/`Show` + matching `OnLeave` | **30** |
| `UI/Theme.lua` | inline `SetBackdrop({bgFile=…, insets=…})` literals | **29** |
| `UI/List.lua` | `UpdateVisibleRows` implementations + row pools + pagination | **5 + 5** |
| `State/Store.lua` | ad-hoc `PSM._*Cache` tables | **8** |
| `State/Store.lua` | `GenerateCacheKey`-style string serializers | **3** (`UI`, `ModelsDataLoader` ×2) |
| `Core/Log.lua` | `pcall` / `SafeCall` sites | **25** (incl. triple-nested in `Data.lua:426-446`) |

The `ApplyElvUISkin` number is the clearest signal: **86 sites where a human has to
remember to call the decorator.** Every one is a chance to forget, and forgetting is
invisible until an ElvUI user reports it. A widget factory that returns
already-skinned, already-backdropped, already-tooltipped widgets makes theming a
one-file concern and deletes the failure mode.

Shape of the factory (illustrative, not prescriptive):

```lua
-- UI/Widgets.lua
function W.Button(parent, spec)
    local b = API.CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(spec.w or Theme.BUTTON_W, spec.h or Theme.BUTTON_H)
    b:SetText(spec.text)
    if spec.tooltip then ns.Tooltip:Attach(b, spec.tooltip) end
    if spec.onClick then b:SetScript("OnClick", spec.onClick) end
    ns.Skin:Apply(b, "button")          -- never called by hand again
    return b
end
```

### 6. State and invalidation

Three containers with three lifetimes, replacing the single `PSM.state` grab-bag at
`Core.lua:82-116` (which currently holds frames, domain data, user settings, and
session flags in one table):

```
PetStableManagementDB   persisted   schema-versioned, migrated once. Never holds a frame.
ns.session              session     stablePets, isStableOpen. Dies at logout.
window.view             per-panel   currentPage, sortColumn, scroll. Owned by the window.
```

**Frames never live in a state table.** That alone turns
`PanelManager:CleanupPanel` — currently 80 lines hand-nil'ing fields across four row
pools — into `window.pool:ReleaseAll()`.

Invalidation moves from string serialization to **per-slice version counters**:

```lua
-- State/Store.lua
function Store:set(slice, key, value)
    local s = self.data[slice]
    if s[key] == value then return end          -- no-op writes don't invalidate
    s[key] = value
    self.version[slice] = self.version[slice] + 1
end

-- State/Selector.lua
function Selector:get()
    for i = 1, #self.deps do
        if self.seen[i] ~= Store.version[self.deps[i]] then return self:recompute() end
    end
    return self.cached
end
```

This replaces `ModelsDataLoader:GenerateCacheKey` (a 13-part `string.format` where
several parts are a sort-and-concat of the entire filter selection, rebuilt on every
render pass) with an integer compare. Three properties the string approach can't have:
zero allocation on the hot path; impossible to forget a field when adding a filter; and
one implementation instead of the three that have already drifted apart.

It also deletes `UI.lua:300-305`'s `GetTime() - timestamp < 0.1` expiry, which is a
debounce wearing a cache's clothes.

### 7. One list pipeline

```
Domain/Query  →  Selector (memoized)  →  DataProvider  →  ScrollBox  →  rows from a pool
```

Views declare a **spec** (columns, row height, renderer), not a procedure. The last mile
uses Blizzard's own virtualized scroller — `ScrollUtil.InitScrollBoxListWithScrollBar`
plus `CreateScrollBoxListLinearView` — the same machinery already read *from*
`StableFrame` in `Data.lua:390-392`, but never used for the addon's own lists.

Deletes: five row pools, five `UpdateVisibleRows`, the entire pagination UI (page text,
jump box, first/prev/next/last), `PanelManager:CreateScrollPreservingResizeHandler`
(lines 370-415), and the `PlayerModel`-repaint-after-resize hack tacked onto its end.

The one thing that stays hand-built is `UI/Pools.lua`'s **ModelPool**: `PlayerModel` is
by far the most expensive widget in WoW, and T1's ~8.7MB unattributed finding almost
certainly lives here. Hard cap on live models (~24), LRU eviction, and generalize
`RowManager.lua:59-64`'s `SetCamDistanceScaleIfChanged` pattern to *every* setter —
never hand the GPU a value it already has.

### 8. Error policy

Replace 25 scattered `pcall`/`SafeCall` sites with **one error boundary per entry
point** (event handler, slash command, script handler), logging to a ring buffer
readable via `/psm debug`. Nothing swallowed below that line.

Today's nesting — `pcall` inside `pcall` inside `pcall` in
`Data.lua:426-446` — means "no Lua errors in-game" is a much weaker acceptance
criterion than it reads as. Errors are being caught and printed, or caught and
discarded, at three depths.

Also: **remove every `collectgarbage("collect")`.** There are calls in `Data.lua` (×2),
and `PanelManager:CleanupPanel` fires one on a 0.5s delay after *every* panel close. A
full collection is a frame stall. With real pooling and release, it isn't needed;
`Config.FORCE_GC_ON_CLEAR` is already `false`, so two of the three are the live ones.

### 9. Testability — the change that makes the rest cheap

Every task in `DATA_STRUCTURE_OPTIMIZATION_PLAN.md` ended with "in-game required," and
T5, T5b, T6 and T7 all had to *defer* verification and batch it into T9. That is not a
discipline problem, it's an architecture one: nothing below the Frame layer is
reachable without launching the game.

With layers 0-3 frame-free by construction, a WoW API stub set plus `busted` running on
LuaJIT makes all of it testable in milliseconds: data access, filters, sort, selectors,
migrations, cache invalidation, the stable-session state machine.

Concretely, T3's manual spot-check of NPC IDs 30/43/113/118 becomes a golden-file test
that runs on every commit forever, and the "70 warnings, same as baseline" ritual gets a
real companion. CI gate: `luacheck` + `busted` + a schema-compat check asserting
`PSM_Data`'s `SCHEMA` matches what `PSM_Browser/Data/Access.lua` expects.

---

## Tasks

Each task is meant to be pasted into a fresh session as-is; it should need only this
file plus the repo it names. Ordered by value ÷ cost, not by dependency — check the
`Depends on` line.

### CLOSED — 2026-08-27

**All fifteen tasks are resolved: fourteen done, one dropped.** Nothing here is
awaiting work, and this document is no longer a to-do list. It stays as the record of
*why* the code is shaped the way it is — the decisions, the measurements behind them,
and the several occasions where a measurement contradicted the plan.

| | Task | Outcome |
|---|---|---|
| A1 | psm-data → psm-addon sync contract | done 2026-08-20 (found already done) |
| A2 | LoadOnDemand for the browser | done 2026-08-11, single-addon shape |
| A3 | `_G.PSM` → `ns` | done 2026-08-20 |
| A4 | Headless tests + CI | harness 2026-08-11, CI 2026-08-15 |
| A5 | Store with version-counter invalidation | done 2026-08-16 → 08-17 (A5.0–A5.3) |
| A6 | UI kit | done 2026-08-13 |
| A7 | Virtualized list | **dropped** 2026-08-20 |
| A8 | Frame + model pools | done 2026-08-20 |
| A9 | Error boundary, GC calls deleted | done 2026-08-20 |
| A10 | Localization scaffold | done 2026-08-19 |
| A11 | `architecture.html` addon half | done 2026-08-20 |
| A12 | Declarative options | done 2026-08-20 |
| A13 | Panel chrome contract | done 2026-08-21 |
| A14 | Trim persisted Owned Pets data | done 2026-08-21, both tiers |
| A15 | Dead code sweep | done 2026-08-27 |

**Where the answers actually live.** Each task's own section holds the brief; the
closing notes are in the running log below, sometimes days later and under a different
heading. When those two disagree, the log is newer. Three headers were still marked
open on 2026-08-27 despite the work having landed — A11's said "ready to start, not
done" about a rewrite finished the same day — which is the same drift this plan kept
catching in `CLAUDE.md` and in `architecture.html`.

**What this document should be trusted for, and what it should not.** The reasoning is
durable; the file paths, line numbers and counts in it are a snapshot and several are
already wrong. Every task that began by re-reading the code rather than this plan found
something the plan had stated confidently and incorrectly — A15 found `ExpandAllGroups`
"kept for any external callers" when no external caller was reachable; A11 found
`CLAUDE.md` claiming eleven public names against the file's fifteen; A5.2 was recorded
complete and was not. **Verify against the repo before acting on anything here.**

**The one thing worth carrying forward as a rule**, because it recurred in A5, A10,
A15 and the comment trim alike: a scan that matches the syntax you expected will
report clean while missing the shape you did not think of. A10's targeted string scans
declared three files finished while they still held English; A15's public-name sweep
missed every file-local function and every name-collided method. **Two independent
passes, intersected, or the result is a lower bound wearing the clothes of an answer.**

Follow-up work now belongs in the repos' own issue trackers, not here.

---

### A1 — Make the psm-data → psm-addon sync an explicit, versioned contract — **done (2026-08-20)**
**Repo:** both. **Files:** `psm-data/config.py`, all five `1x_generate_*.py`,
new `psm-addon/PSM_Data/Schema.lua` (landed at
`PetStableManagement_ModelsBrowser/ModelsBrowser/Schema.lua` — see closing summary
below for why). **Depends on:** nothing.

Two changes, both small, both closing wounds this project already took:

1. `sync_output_to_addon()` currently runs **unconditionally inside every generator
   script**, so running any generator silently mutates the addon repo. That is exactly
   why the last plan carried the warning *"psm-addon is broken in-game until T4-T8
   land."* Make sync an explicit separate step (`python sync.py`, or a `--sync` flag
   defaulting off). Generators write to `Output/` and stop there.
2. Every generated file stamps a schema version. `PSM_Data/Schema.lua` (hand-written)
   declares `PSM_DataSchema = { version = 3, generatedAt = "..." }`; the consumer
   asserts it on load and fails with one clear line instead of a wall of nil-index
   errors.

**Acceptance:** `ruff check .` clean. Running any generator leaves `psm-addon` with
zero git diff. Running the sync step produces the same files as before plus the stamp.
Deliberately mismatching the version produces exactly one readable error in-game.

---

### A2 — LoadOnDemand for the browser and its data — **done (2026-08-11, single-addon shape)**
**Repo:** `psm-addon`. **Depends on:** nothing (A1 makes it tidier, not required).

Highest value-per-hour item in this document. Split `PetStableManagement_ModelsBrowser`
into `PSM_Browser` (UI/logic, `## LoadOnDemand: 1`) and `PSM_Data` (generated tables,
`## LoadOnDemand: 1`). Load on first `/psm models`, first browser click, and from the
existing taming-info fallback path that Owned Pets uses.

Gates to get right: never `LoadAddOn` in combat (panels are already combat-blocked);
handle load failure with a real message; every existing `if PSM.PetModels then` guard
becomes "is the capability registered", not "is the global present."

**Acceptance (in-game required):** `luacheck` clean. Measure with the T0/T9 protocol
(`collectgarbage()` then `UpdateAddOnMemoryUsage()` — see the optimization plan's
caveats, they all still apply). Expect the never-opened-browser floor to drop from
6.57MB to near zero. Then open the browser and confirm the full T9 functional smoke
test still passes. Log both numbers.

**Confirmed still current (2026-08-20), re-checked while closing out A1.** The
task's own three-addon shape (`PSM_Browser` + `PSM_Data`) is not what shipped — that
third addon was tried and reverted (see `psm-addon/CLAUDE.md`'s "Don't add a third
addon folder" rule) after every "data only" caller turned out to need the browser's
own resolvers. What's live today is the two-addon split this doc already describes
as current: `PetStableManagement_ModelsBrowser` alone carries `## LoadOnDemand: 1`
and `## RequiredDeps: PetStableManagement`, core declares nothing about it. Re-verified
the .toc wiring and `Loader:IsBrowserAvailable`/`EnsureBrowser` directly rather than
trusting the 2026-08-11 log entry on its word. Measured numbers are in the "A2
measured result" entry in the Running Log below — 8.2MB → 1.65MB at login, the
6.57MB browser floor gone until first use.

---

### A3 — Namespace conversion: `_G.PSM` → `ns` — **done (2026-08-20)**
**Repo:** `psm-addon`. **Files:** all. **Depends on:** A2 (do it once, on the final
folder split, not twice).

Mechanical but wide. Replace the `_G.PSM = _G.PSM or {}` preamble in every file with
`local addonName, ns = ...`. Keep a deliberately small `_G.PSM` public surface for
external consumers and the cross-addon data bridge. Add `Core/Compat.lua` and move
every WoW API global read into it. Rewrite `.luacheckrc` to per-path `read_globals`
so the layering is lint-enforced.

Do this as one sweep per addon folder, luacheck between each. Expect it to surface
real accidental couplings — that's the point, log them rather than papering over.

**Acceptance:** `luacheck` clean under the *new, stricter* config. Zero behavior change
intended. In-game: full smoke test, since this touches every file.

---

#### BLOCKER identified 2026-08-11, before starting: `ns` is per-*addon*, not per-repo

`local addonName, ns = ...` gives each **addon** its own private table. `PetStableManagement`
and `PetStableManagement_ModelsBrowser` are two addons, so they get two different `ns`
tables — and the browser is saturated with core references (`PSM.Config`, `PSM.Utils`,
`PSM.PanelManager`, `PSM.RowManager`, `PSM.PopUpManager`, `PSM.state`), while core
reaches back the other way (`PSM.PetModels`, `PSM.ModelsPanel`, `PSM.TamingChecker`).

**Those cross-addon references cannot become `ns.X`.** A naive sweep breaks the browser
on the first `/reload`. A3's headline benefit ("nothing outside the addon can reach in")
therefore applies only to genuinely file-local or addon-local state — a real win, but
smaller than the task text implies. **Decide the shape before touching any file:**

- **Option A — core keeps a full `_G.PSM` export, uses `ns` internally.** Smallest
  change, browser untouched. Cost: every shared table has two names, and the boundary
  stays exactly as leaky as today. Arguably not worth doing at all.
- **Option B — curated public API.** Core exposes a deliberate `_G.PSM` surface
  (Config, Utils, state, the managers the browser genuinely needs); everything else
  becomes `ns`-private. The browser is converted to consume only that surface. Much
  larger, and the only version that delivers the stated benefit. Effectively forces the
  layering work early.
- **Option C — defer A3, do A6 first.** The UI kit (`Widgets`/`Skin`/`Tooltip`/`Theme`)
  needs no namespace change, delivers visible value, and shrinks the surface A3 would
  have to negotiate — 86 `ApplyElvUISkin` call sites and 190 `CreateFrame` calls stop
  being cross-addon concerns once they route through one kit.

**Recommendation: C, then B.** Doing A6 first makes B's public surface obviously
smaller, because much of what the browser currently pulls from core is UI plumbing that
the kit would own. `Core/Compat.lua` (the WoW API shim) is independent of all this and
can land at any time as its own small task.

**Do not start A3 as originally written.**

#### DECIDED 2026-08-11: **Option B**, executed late

C is already taken (A6 shipped). **B is the chosen end state**, but it is not started
yet, and deciding it is deliberately separate from starting it: the public surface keeps
shrinking while other tasks run, so the later B begins, the less there is to negotiate.

The value of deciding now is that **every subsequent task converges on B without being
about B**. Standing rules from here:

- **When migrating a browser file, prefer consuming a core *service* over reaching into
  core internals.** `PSM.Widgets`/`PSM.Theme`/`PSM.Tooltip`/`PSM.Skin` are the model:
  four names, no back-references. Every call site that moves from `PSM.Config.COLORS`
  or an ad-hoc `CreateFrame` onto the kit is one fewer item on B's surface.
- **Log, don't fix, every core internal the browser turns out to need.** That list *is*
  B's public API, derived from evidence rather than guessed at. Keep it in this section.
- **Core must not gain new reads of browser internals.** The three that exist
  (`PSM.PetModels`, `PSM.ModelsPanel`, `PSM.TamingChecker`) are the ceiling, not a
  precedent. A fourth means B gets harder, so justify it here first.
- `Core/Compat.lua` remains independent and can land whenever.

**Candidate public surface so far** (to be confirmed, not designed up front):
`Config`, `Utils`, `state`, `Loader`, `Theme`, `Skin`, `Tooltip`, `Widgets`,
`PanelManager`, `RowManager`, `PopUpManager`, `Data`.

**Evidence log — what the browser actually reaches into core for.** Recorded per file
as it migrates, so B's surface is derived from use rather than guessed:

| Core member | Used by | Notes |
|---|---|---|
| `Theme` / `Skin` / `Tooltip` / `Widgets` | SpecialTames | the kit; clean, one-way |
| `Config.COLORS` (`PRIMARY`, `ABILITY_SELECTION_NOTE`) | SpecialTames | semantic colours |
| `Config.TAB.*` | SpecialTames | pill styling — shared with AbilityBrowser |
| `Config.FONT_SIZES` (`ABILITY_PILL`, `STATS`) | SpecialTames | overlaps `Theme.SIZE`; candidate for merge in A13 |
| `Config.BUTTON_WIDTH` / `BUTTON_HEIGHT` | SpecialTames | layout constants |
| `PanelManager` (`CreateBasePanel`, `TogglePanel`) | SpecialTames | the big one — panel chrome |
| `PopUpManager:ShowURLPopup` | SpecialTames | Wowhead links |
| `state` (`specialTames`, `selectedTamingRules`, `selectedConditions`) | SpecialTames | shared mutable state; A5's problem, not B's |
| `PetStableManagementDB` | SpecialTames | SavedVariables, a true global |

Early read: the surface is **narrower than feared** and clusters into four groups —
the UI kit, `Config` constants, `PanelManager` chrome, and `state`. Only `state` looks
genuinely hard, and it is A5's concern anyway.

---

### A4 — Headless test harness + CI — **done (harness 2026-08-11, CI 2026-08-15)**
**Repo:** `psm-addon`. **Files:** `Tests/`, `.github/workflows/ci.yml`.
**Depends on:** nothing, but pays off proportionally to A3/A5/A6.

WoW API stubs + `busted` on LuaJIT. Seed it with the tests that would have caught real
past bugs: the T3 golden-file spot-checks (NPC 30/43/113/118 resolving correctly
through `Index`/columns), a `ModelsData` record-count assertion, and a SavedVariables
migration round-trip. CI runs `luacheck` + `busted` + the A1 schema-compat check.

Start narrow. A harness that tests only `Domain/` and `Data/Access.lua` is already
worth more than one that aspires to cover frames and never ships.

**Acceptance:** `busted` green locally and in CI. At least one test that fails if the
`ModelsData` schema changes without the addon being updated.

---

### A5 — Store with version-counter invalidation — **done (A5.0-A5.3, 2026-08-16 to 2026-08-17)**
**Repo:** `psm-addon`. **Files:** new `State/`, then `ModelsFilters.lua`,
`ModelsDataLoader.lua`, `UI.lua`. **Depends on:** A4 (this is the task that most wants
tests).

> **Revised 2026-08-11 after stress-testing the design against the real Models Browser
> filter interaction.** The core idea survived; three things the first draft got wrong
> are corrected below. See "Stress test: Models Browser filter flow" after the task list
> for the full trace.

**A5.0 — Collapse filter state into one home. Do this first; nothing else works
without it.** Filter state currently lives in *three* places at once:

| Home | Holds | Example |
|---|---|---|
| `PSM.state.selected*` | multi-select tables | `selectedModelsFamilies`, `selectedExpansions`, `selectedLocations`, `selectedTamingRules`, `selectedConditions` |
| `panel.show*` (on the **frame**) | tristate scalars | `showRares`, `showFavorites`, `showHideOwned`, `showNameKeepers`, `showPetsInMyZone` |
| `panel.searchBox` (the **widget**) | search text | read live via `:GetText()` |

`CreateRaresToggle` (`ModelsFilters.lua:178-183`) writes the *same fact* to
`panel.showRares` **and** `PSM.state.showRares` while reading its initial value from
`PetStableManagementDB.filters` — three copies, hand-synced. A version-counter store
only sees writes that go through `Store:set`, so any state left on a frame or inside a
widget is **invisible to invalidation**. Ship A5 without A5.0 and selectors silently
go stale on exactly the interactions users perform most.

**A5.1 — One slice per filter *dimension*, not one "filters" slice.** The dynamic
filter functions have a deliberate **leave-one-out** dependency shape:
`GetAvailableFamiliesForFilters` reads expansions, locations and the toggles but
**not** `selectedModelsFamilies` (it answers "what families are still reachable given
the *other* filters", and loops `panel.familiesList`, not the selection). Same pattern
for expansions and locations. A single `filters` slice over-invalidates: picking a
family would rescan all 61 families × their displayIds × their NPCs to recompute a
list that cannot have changed.

```
slices:  families · expansions · locations · toggles · search · pets · viewMode

availableFamilies    ← expansions, locations, toggles, search, pets
availableExpansions  ← families,   locations, toggles, search, pets
availableLocations   ← families,   expansions, toggles, search, pets
results              ← families,   expansions, locations, toggles, search, pets, viewMode
```

**A5.2 — Model `pets` by content, not by count.** `GenerateCacheKey` uses
`#PSM.state.stablePets` as its ownership proxy (`ModelsDataLoader.lua:126`). Releasing
one pet and taming another leaves the count identical while the displayID set changes,
so "Hide Owned" can show stale results. Narrow (needs the browser open across a stable
transaction) and partly masked by the 0.1s expiry, but real — and it disappears for
free once `Stable:collect()` writes through the store and bumps a `pets` version.

**Corollary — do not delete `UI.lua:300-305`'s `GetTime() - timestamp < 0.1` expiry
early.** It reads like a redundant debounce, but it is currently *load-bearing*: it
bounds staleness from dependencies the cache key doesn't model (A5.0's frame/widget
state, A5.2's ownership set). Remove it only once the dependency set is provably
complete, i.e. after A5.0-A5.2. Removing it first would make latent staleness bugs
*more* visible, not less.

Then retire `ModelsDataLoader:GenerateCacheKey`, `_GenerateDynamicFilterCacheKey`, and
`UI:GenerateCacheKey` one at a time. Old and new systems can coexist during the
migration; that's what makes this incremental.

**Expected side effect worth checking off:** `ReloadAndSummarise()` and
`UpdateDynamicFilters()` are currently invoked **as a hand-written pair at 11 call
sites** in `ModelsFilters.lua`. They are *siblings*, not sequential — verified:
`GetAvailableFamiliesForFilters` recomputes from `PetModels:GetFamilyModels` directly,
never from the reload's output — so the enforced ordering is incidental. With pull-based
selectors both calls disappear entirely: whoever reads a selector gets a fresh value.
**If those 11 pairs don't go away, the migration isn't finished.**

Hard requirement, unchanged: **filter state stays name-keyed in SavedVariables.** No
user migration, same reasoning as T8. Version counters are session-only.

**Acceptance:** unit tests prove (a) a no-op write doesn't bump a version, (b) a real
write does, (c) selecting a family does **not** invalidate `availableFamilies`, and
(d) swapping a pet for a different one at equal count *does* invalidate ownership.
In-game: toggle every filter category repeatedly, confirm results match; `/reload` with
saved filters and confirm they still apply.

---

### A6 — UI kit: Widgets, Skin, Tooltip, Theme — **done (2026-08-13)**
**Repo:** `psm-addon`. **Files:** new `UI/`. **Depends on:** A3.

Build the factory, then migrate call sites **one file at a time, highest count first**:
`PopUpManager.lua` (32 `CreateFrame`, 20 `ApplyElvUISkin`, 11 `CreateFontString`,
6 `SetBackdrop`, 6 `SetOwner`) is both the worst offender and the best proof.

The win to measure isn't lines removed, it's that `ApplyElvUISkin` stops being
something a human has to remember 86 times.

**Acceptance:** `luacheck` clean. In-game with **and without** ElvUI loaded — this task
is the one most likely to regress skinning, and it's invisible on a non-ElvUI client.

---

### A7 — Virtualized list, starting with NPC view — **DROPPED (2026-08-20)**
**Repo:** `psm-addon`. **Files:** new `UI/List.lua`, then `NpcView.lua`.
**Depends on:** A6.

Built, in-game tested, reverted (see "Reverted: A7's virtualized NPC list" below) —
resizing wasn't landing well, NPC view diverged from grid view's pagination, and the
memory case that motivated it was never proven either way. User's call after that:
drop it rather than re-attempt with a proper controlled A/B. **A8 no longer depends
on this** — its own repro (Owned Pets Grouped View) needed nothing from here.

Do **NPC view only** first: plain text rows, no `PlayerModel`, sortable columns — the
safest place to prove the pattern. If it works, pagination disappears from that view
entirely. Only then consider the model grid, which is harder (3D widgets + the model
pool + per-model persisted view state).

**Acceptance (in-game required):** full NPC-view pass — sorting on every column,
column resize, column show/hide, search, all filters, Wowhead/TomTom links, Display ID
pills. Scroll position survives a panel resize. Compare memory against A2's number.

---

### A8 — Frame + model pools — **done (2026-08-20)**
**Repo:** `psm-addon`. **Files:** `UI/Pools.lua`, `CleanupPanel` callers.
**Depends on:** A6, ~~A7~~ (A7 dropped; turned out unneeded — see below).

`CreateFramePool` / `CreateObjectPool` with real `ReleaseAll`, plus the capped LRU
ModelPool. This is what finally makes T1's ~8.7MB side finding *measurable* — pooled
widgets currently can't be freed or diffed (confirmed in the optimization plan's
caveats), because nothing owns their lifetime.

**Acceptance (in-game required):** open the browser, exercise filters heavily, close,
force GC, measure. The number should now *move*, which it demonstrably does not today.
Log it either way — a null result here is still information.

**Repro on core, not just the browser (2026-08-20):** Owned Pets, Grouped View,
repeatedly reopened and closed without touching anything else inside it — memory
climbs on every open, never returns on close. Matches A2's own note that "core
ratchets too (1.65 → 2.97MB) from pooled widgets and caches that are never
released," now with a specific, easy repro rather than a general observation.
Grouped View specifically hasn't been checked against A6's kit-migration record for
what it pools by hand; worth a look before assuming this needs the full
`CreateObjectPool` treatment.

---

### A9 — Error boundary + delete the GC calls — **done (2026-08-20)**
**Repo:** `psm-addon`. **Files:** `Core/Log.lua`, the 25 pcall sites, 3 GC sites.
**Depends on:** A3.

One boundary per entry point. Ring buffer + `/psm debug`. Remove the nested pcalls in
`Data.lua:426-446` and the delayed `collectgarbage("collect")` in
`PanelManager:CleanupPanel`.

**Acceptance:** deliberately throw inside a row renderer and confirm it surfaces in
`/psm debug` with a stack, rather than vanishing. Frame-time spike on panel close gone.

---

### A10 — Localization scaffold — **done (2026-08-19)**
**Repo:** `psm-addon`. **Depends on:** A3.

There is currently **no** `L[]` anywhere and every user-facing string is hardcoded
English. Add `Core/Locale.lua` with enUS only. Retrofitting a locale table across 60k
lines later is genuinely miserable; doing it now while touching every file anyway
costs an afternoon.

Fold in `Config.MESSAGES` (already a partial, informal version of this).

---

### A11 — Update `architecture.html`'s addon half — **done (2026-08-20)**
**Repo:** none (lives in `PSM/`). **Depends on:** A2 (done), A3 (done), ~~A7~~ (dropped
— no longer blocks; nothing pending from it to wait for).

Rewrite `stages[6..9]` and the addon portion of `edges`. Keep all CSS, the grid layout,
the SVG connector code, and the entire psm-data half. Relabel the `bridge` edge as an
explicit sync step (A1). Verify the success criterion: **fewer addon-side edges than
the 2026-08-11 baseline.**

**Superseded — see "A11 — done (2026-08-20)" in the running log.** An earlier status
check here read "ready to start, not done"; the rewrite landed the same day. The banner
is retired and the addon-side edge count went 37 → 27.

---

### A12 — Options as declarative definitions — **done (2026-08-20)**
**Repo:** `psm-addon`. **Files:** `Shared/OptionsPanel.lua` (the task's `Features/Options/`
path predates A6's actual layout — file never moved). **Depends on:** A6 (done).

`OptionsPanel.lua` (506 lines) is mostly hand-built sliders and checkboxes that each
re-implement label/tooltip/persistence/apply. Replace with a table of option
definitions and one generic builder. Confirm which Settings API is actually in use and
drop the dead pre-Dragonflight path (see §4's note).

Lowest priority here; listed because it's the clearest remaining example of the pattern
this plan is about.

**Status check (2026-08-20): ready to start, not done, premise still accurate.** File
is 521 lines now (was 506 — grown slightly from intervening work, not shrunk). The
dead pre-Dragonflight branch is still there verbatim: `if InterfaceOptions_AddCategory
then ... elseif Settings.RegisterCanvasLayoutCategory then ...` — confirmed dead on
this addon's actual Interface versions (120007/121000, both long post-Dragonflight),
so the `Settings` branch is unconditionally the one taken and the first is unreachable
weight. Nothing about this task has been done.

---

### A13 — Panel chrome contract (visual consistency across all seven panels) — **done (2026-08-21, completed in a parallel session)**
**Repo:** `psm-addon`. **Files:** `UI/Theme.lua`, `UI/Window.lua`, every
`Features/*/Panel.lua`. **Depends on:** A6.

**A6 does not deliver this on its own.** Centralization buys *mechanical* consistency —
every button is skinned the same way because one factory skins it. It does **not** buy
*compositional* consistency: where the title sits, where search goes, which side the
filter bar is on, button order, spacing rhythm. Those are decisions, not defaults, and
they have already diverged despite a shared `CreateBasePanel`.

The proof is inside the shared code itself, `PanelManager.lua:170`:

```lua
t:SetPoint("TOP", 0, config.title == "Pet Model Browser" and -20 or -35)
```

The base panel branches on a **panel's title string** to place its own title. That is
layout divergence that got heavy enough to be special-cased in the one place that was
supposed to prevent it.

Two halves, and only the first is free from A6:

**Tokens (mostly falls out of A6, but needs a sweep).** The token tables already exist
and are routinely bypassed:
- `Config.FONT_SIZES` defines 7 named sizes; the tree contains **54 hardcoded
  `SetFont(..., N)` calls across 6 distinct sizes** (9/10/11/12/14/16).
- `Config.COLORS` defines ~25 named colors; the tree contains **57 raw `SetTextColor`
  calls across 12 distinct values** — including `SetTextColor(1, 0.82, 0)` **20 times**,
  which is character-for-character `COLORS.PRIMARY`.

So the fix isn't "add tokens", it's "make bypassing them impossible" — `Widgets.Label`
takes a *named* role (`"title"`, `"body"`, `"dim"`), never a raw size or RGB triple.
A lint rule (or a plain grep in CI) rejects new `SetFont(`/`SetTextColor(` outside
`UI/`.

**Chrome (needs an actual decision pass — this is the real work).** Write down one
contract every panel obeys, then make `Window.lua` provide it as *structure* rather
than convention, so a feature physically cannot place its search box somewhere novel:

```
┌──────────────────────────────────────────────┐
│ Title            [Maximize] [Close]          │  header — fixed height, one origin
│ [Search…]                    [mode toggles]  │  toolbar — optional, uniform height
├──────────────────────────────────────────────┤
│ filter bar (optional, uniform height/side)   │
├──────────────────────────────────────────────┤
│                                              │
│   content — the ONLY region a feature owns   │
│                                              │
├──────────────────────────────────────────────┤
│ status / summary line          [pagination]  │  footer — optional
└──────────────────────────────────────────────┘
```

Sequence this **after A6 and after A7's NPC-view proof**, not before: the contract
should be written against a panel that has already been rebuilt on the new list and
widget layers, or it'll encode today's constraints.

**Resequencing note (2026-08-20): A7 dropped, dependency is moot, not blocking.** A7's
NPC-view proof was never going to happen — pagination is the permanent shape now, not
a placeholder for a future list layer. The original worry (writing the contract against
constraints that were about to change) no longer applies, since nothing is going to
change them. If anything, this makes now a *more* settled time to write the contract
than "after A7" ever would have been. Still sequenced after A6, which is done.

**Status check (2026-08-20).** The proof example this task cites,
`PanelManager.lua:170`'s title-string branch, is **already fixed** — `titleOffset` is
now a config value, no title-string test, fixed as an unrelated side effect while
touching this function for other reasons. The token-bypass counts have also dropped
hard since the original survey: raw `SetFont(` outside `UI/` is 54 → 2; raw
`SetTextColor(` outside `UI/` is 57 → 36, and of those 36 most are already
`unpack(ns.Config.COLORS.X)` — a named constant, just not routed through
`Widgets.Label`'s role system — leaving roughly a dozen genuinely bare RGB literals
(`SetTextColor(1, 0.82, 0)` is down to **1** occurrence, from 20). **The "tokens" half
is most of the way done already, incidentally, via A6.** The actual scope left is what
the task itself calls "the real work" — the chrome contract (header/toolbar/filter-
bar/content/footer as enforced structure, not convention) — which is untouched, is a
genuine design decision rather than a mechanical sweep, and is where this task's real
size lives.

**Acceptance:** open all seven panels (Owned Pets ×3 views, Teams, Models Browser,
Abilities, Special Tames) at the same size and screenshot them. Title baseline, search
box position, filter bar width, and footer height identical across all. Zero
`SetFont`/`SetTextColor` calls outside `UI/`. `PanelManager.lua:170`'s title-string
branch deleted. Re-check with ElvUI loaded.

---

**DONE (2026-08-20).** Shipped as `psm-addon` commit `afcfb57` on `feat/load-on-demand`,
17 files, +312/-272. Verified in-game by the author across several rounds of live
feedback (not a Claude screenshot pass — this repo's convention is that in-game
verification is the user's step), which is also why the final numbers below differ
from the first cut: several were corrected against the real client, not derived from
pixel arithmetic alone.

**Two decisions the task itself flagged as needing a real design pass, settled before
implementation:**
- **Footer: bare label everywhere**, not the bordered/hairline treatment. Ability
  Browser and Special Tames each had an independently hand-rolled bordered footer
  frame (byte-for-byte identical between the two); both were torn out in favor of the
  plain `{"BOTTOM", 0, FOOTER_Y}` label Owned Pets/Teams/Models Browser already used.
- **Filter bar: two sanctioned variants, not one.** `TOP_BAR` (dropdowns/checkboxes/
  pills, anchored below the toolbar — Owned Pets, Ability Browser, Special Tames) and
  `LEFT_RAIL` (a vertical filter column beside content — Models Browser only, kept
  because its filter set is tabbed lists of dozens of checkboxes a horizontal strip
  can't hold). This is a deliberate revision of this task's original acceptance
  wording ("filter bar width ... identical across all") — width/shape is uniform
  *within* a variant, not forced to one shape addon-wide.

**The contract, as shipped** — `Theme.CHROME` (`UI/Theme.lua`):
```lua
Theme.CHROME = {
    TITLE_Y    = -35,  -- title, from panel TOP -- no per-panel override any more
    FILTER_TOP = -100, -- TOP_BAR filter row / LEFT_RAIL top, from panel TOP
    FOOTER_Y   = 15,    -- bare-label footer, from panel BOTTOM
}
```
`CreateBasePanel`'s `titleOffset` parameter — the escape hatch this task's proof
example (`PanelManager.lua:170`) was built to describe — is deleted outright, not
just fixed at one call site. `PanelManager.lua` gained three shared factories used in
place of hand-rolled per-panel copies: `CreatePillBar` (Ability Browser + Special
Tames), `CreateFooterLabel` (all five footer-having panels), `CreateViewButton` (Owned
Pets' List/Grid/Grouped row, Models Browser's Models/NPC toggle — a "Views" contract
slot, buttons not a dropdown: 3-way switching gains nothing from the extra click).

**Models Browser's rail needed real back-and-forth to get right, not a formula.**
The plan's original worry — a panel needing more vertical room than the shared
contract allows — turned out to be exactly what happened, twice:
1. First cut anchored the new "Tools" box (the three cross-panel nav buttons,
   previously a loose hand-anchored row that is why `titleOffset` existed at all) at
   `FILTER_TOP`, pushing Show Only/Unified Filters down by its own height. That
   overflowed the panel: Unified Filters had to shrink from 505 to fit.
2. Tried anchoring Tools *above* `FILTER_TOP` instead (reasoning: the rail column
   never shares horizontal space with the centered title/search box, so no
   collision) — correct about the collision, wrong about the arithmetic: `FILTER_TOP`
   is only 100px below the panel's own top edge, and Tools needs 130, so it poked
   30px past the panel's own border. Caught by the author in-game, not by anything
   computable from the anchor chain alone.
3. Settled shape: Tools anchors at `Theme.CHROME.TITLE_Y` (same height as the title —
   still zero collision, since it's a different column), Show Only and a
   **440px** Unified Filters stack below it (down from 505; it's a scrollframe, so
   the cost is more scrolling, not lost content), and `petsFrame` anchors to Show
   Only's top rather than Tools', lifted **50px** as a one-panel visual-balance
   constant (`PETS_FRAME_TOP_LIFT`, not a shared token — Models Browser is the only
   `LEFT_RAIL` panel, so there's no sibling contract this could drift out of step
   with). All four boxes (Tools/Show Only/Unified Filters/`petsFrame`) now share one
   `Theme.COLOR.SILVER` border tint, previously a literal repeated 5 times.

**Tokens: the sweep this task predicted was already mostly done via A6 is now
actually zero.** Every bare `SetTextColor`/`SetFont` outside `UI/` is gone except two
`PopUpManager.lua` `SetFont` calls on `SimpleHTML` sub-elements (already reading
`Theme.FONT`/`Theme.SIZE.BODY`, just not through `Widgets.Label`, which doesn't wrap
`SimpleHTML` and has no reason to) — a documented exception, not a miss. One new
color token, `Theme.COLOR.SILVER`; one new helper, `Theme.SelectionStateColor
(allSelected, someSelected)`, replacing the duplicated "all/some/none selected"
header-color idiom in `ModelsFilters.lua` and (partially — it has a fourth,
genuinely different "all inverted" state) `SpecialTames.lua`.

**Found outside the task's original scope, fixed because the evidence was already in
hand:** `Widgets.Button` never defaulted its font — `UIPanelButtonTemplate` supplies
its own (larger) default when `fontObject` is left unset, and a scripted check across
every `Widgets.Button` call site found **14 of 34 omitted it**, including Ability
Browser's footer buttons rendering visibly larger than Special Tames' otherwise
identical ones. Fixed at the factory (`GameFontNormalSmall` default, same rule as
`CheckBox`/`Button` width already followed), not at 14 call sites. Also, unrelated to
chrome but raised in the same review pass: Pet Roulette and Model Magnifier now share
one persisted popup size (`PopUpManager.lua`'s `PopupSizeStore`) instead of two
independent ones — a deliberate behavior change the author asked for after noticing
the two popups didn't match after resizing one.

**Acceptance, reconciled against what shipped:** all seven panels open at a consistent
title/search position (author-verified in-game, iteratively). Filter bar
width/position is uniform *within* each of the two variants, not addon-wide, per the
revised decision above. Zero bare `SetFont`/`SetTextColor` outside `UI/`, two named
exceptions. `PanelManager.lua`'s title-string/titleOffset branch is gone, not fixed in
place. ElvUI re-check not separately logged here — same in-game verification pass.

---

### A14 — Trim the persisted Owned Pets data (core's floor) — **done (2026-08-21), both tiers**
**Repo:** `psm-addon`. **Files:** `Shared/Data.lua`, later `State/Schema.lua` +
`State/Migrate.lua`. **Depends on:** free tier depends on nothing; structural tier
depends on **A4**.

After A2, core is **100% of the always-paid floor** (1.65MB), so this is what's left.
Measured against a real `PetStableManagementDB` (2026-08-11: 15 characters, 6 with
snapshots, 205 pet records, **204KB on disk**, expanding to roughly 0.4-0.8MB as live
Lua tables):

**Framing that matters: the code half is fixed, the data half grows.** 205 pets across
6 characters is a *small* case — the addon supports 205 slots per hunter, so a
collector with 5 near-cap hunters carries ~1,000 records and drifts toward 2.5-3MB.

**Free tier — write-side only, no migration, no user risk.** Stop *persisting* these;
read-side fallbacks already exist, so old SavedVariables still load and the fields
simply vanish on next save:

| Field | Evidence it's redundant |
|---|---|
| `modelSceneID` | The literal constant `783`, hardcoded at `Data.lua:408` and `:485`. 205 stored copies of a constant. |
| `guid` | Exact duplicate of `petNumber` (`p.guid = p.guid or p.petNumber`). |
| `tamer` | Pet is already nested under `characters["Name-Realm"]`, and `LoadPersistentDataForDisplay` **overwrites it with the same value on load**. Written, then re-derived. |
| per-character `minimapButton` | Written to `char.settings` at `Data.lua:154` for all 15 characters; **every reader uses `PetStableManagementDB.settings.minimapButton`**. Nothing reads the per-character copy. |
| five empty `selected*` tables | Persisted per character even when empty; 15 x 5 = 75 tables holding nothing. |

The `minimapButton` one is worth more than its ~5KB: it is the **same "two homes for
one fact" disease A5.0 documents for filter state**, sitting in a second subsystem.
Treat it as a correctness finding, not a size one.

**Structural tier — needs A4 first.**
- `abilities`: 916 stored entries across only **59 distinct** names, in 5 tables per
  pet (~1,025 tables). Already recomputed via `_petDerivedCache`, whose own comment
  calls them "pure functions of level+species+spec". **Check before removing** whether
  they are persisted precisely because an offline character's spell data can't be
  recomputed while you're logged in elsewhere — that would be a real reason to keep them.
- `isExotic` derives from `familyName` via `EXOTIC_FAMILIES`; `specID`/`specName`
  derive from each other.
- Columnar `snapshotData` — the T2 treatment applied to pets. Needs a real migration.

**Sequencing, and the honest proportion:** total available win is **~0.3-0.5MB against
A2's 6.57MB** — an order of magnitude smaller, for more risk, since SavedVariables
migration is the one change class that can destroy user data. Do the free tier
opportunistically; do the structural tier only once A4 can test a migration round-trip.

**Acceptance (free tier):** `luacheck` clean. Log in on two characters, visit a stable,
`/reload`, confirm all pets still listed with correct tamer/family/spec and the minimap
button in its saved position. Confirm the saved file shrinks and that a *pre-change*
SavedVariables file still loads without error (this is the actual regression risk).

---

### A15 — Dead code sweep — **fresh sweep done (2026-08-27)**
**Repo:** `psm-addon`. **Depends on:** nothing, but re-verify the list if A3 lands first.

**Re-verified per-name rather than assumed stale, since A3 has now landed.** Of the 21
candidates below, **20 are gone from the codebase entirely** — zero matches for even
an unconstrained substring search, not just the `:fn(` call-site pattern the original
survey used — almost certainly incidental cleanup from A5/A6/A9/A10/A14's own
refactors rather than anyone deliberately working this list. The one survivor,
`PSM.Minimap:OnUpdate`, is exactly the false-positive case the original survey
flagged and deferred: passed by reference (`SetScript("OnUpdate", ns.Minimap.OnUpdate)`),
genuinely alive, correctly never removed. **This list is closed — nothing on it needs
deleting.** A *fresh* sweep (273 public functions was the 2026-08-11 count; the real
number has moved) is a new, separate task, not a continuation of this one.

A sweep of all **273 public `PSM.*` functions** on 2026-08-11 found **21 with no call
site (~8%)**. Recorded here rather than acted on, so the list exists when there's
appetite for it.

```
PSM.ModelRow:SetupNoteEditing                       ModelsBrowser/ModelRow.lua
PSM.ModelsDataLoader:_GenerateDynamicFilterCacheKey  ModelsBrowser/ModelsDataLoader.lua
PSM.ModelsDataLoader:_IsFavoriteDisplay              ModelsBrowser/ModelsDataLoader.lua
PSM.ModelsPanel:InitializePerformanceOptimizations   ModelsBrowser/ModelsPanel.lua
PSM.TamingChecker.GetModelStatus                     ModelsBrowser/TamingChecker.lua
PSM.UI:ResetTamerSelection                           OwnedPets/Filters.lua
PSM.PetGroups:GetGroupCount                          OwnedPets/PetGroups.lua
PSM.PetGroups:GetPetsInGroup                         OwnedPets/PetGroups.lua
PSM.Teams:FindMatchingTeam                           OwnedPets/TeamsData.lua
PSM.Teams:SetActiveTeamId                            OwnedPets/TeamsData.lua
PSM.Teams:ClearActiveTeam                            OwnedPets/TeamsData.lua
PSM.Teams:GetTeamSummary                             OwnedPets/TeamsData.lua
PSM.Teams:ValidateTeam                               OwnedPets/TeamsData.lua
PSM.Teams:ExportTeamData                             OwnedPets/TeamsData.lua
PSM.TeamDialogs:CloseActiveDialog                    Shared/Dialogs.lua
PSM.TeamDialogs:IsDialogOpen                         Shared/Dialogs.lua
PSM.Minimap:OnUpdate                                 Shared/Minimap.lua
PSM.UI:UpdatePanelWithSnapshot                       Shared/UI.lua
PSM.UI:CreateOptimizedSizeChangedHandler             Shared/UI.lua
PSM.Utils:SafeStringFormat                           Shared/Utils.lua
PSM.Loader:IsDataLoaded                              Shared/Loader.lua   [already removed]
```

**This is a candidate list, not a verdict.** The sweep matches `:fn(` call syntax, so
anything passed *by reference* reads as dead but isn't — `PSM.Minimap:OnUpdate` has
exactly that shape (`SetScript("OnUpdate", ...)`) and must be checked before removal.
Same for anything invoked dynamically.

**Rules for the removal pass**, following the precedent set when T5 removed ~150 lines
of legacy parsing only after grep-confirming the globals were never assigned:
1. **Prove each one individually**, including by-reference and dynamic use.
2. **Separate commit**, never folded into a feature diff — otherwise reverting the
   feature drags the deletion with it.
3. **Record the proof** in the commit message.
4. `_G.PSM` is a *public* global, so a third-party addon or user macro could in
   principle call these. Negligible for internal helpers; don't remove anything the
   README advertises without checking.

`Utils:SafeStringFormat` is the one with known-buggy behaviour (see A4's result), which
makes it the clearest delete rather than a fix candidate.

**Acceptance:** `luacheck` still 70/0 (or lower — removals may drop unused-argument
warnings), `Tests/run.lua` green, and `utils_spec.lua`'s `SafeStringFormat` block
deleted alongside the function it pins.

---

**DONE (2026-08-11).** 19 of the 21 removed, plus cascades. **luacheck 70 → 67
warnings, 0 errors. Tests 42 → 37** (the five `SafeStringFormat` specs went with the
function). **296 deletions.** In-game smoke test still pending.

**The two survivors are exactly the class the warning above predicted:**
- `Minimap:OnUpdate` — passed *by reference* to `SetScript` at `Minimap.lua:139`.
- `Teams:GetActiveTeamId` — never a candidate, but worth recording: only the
  `SetActiveTeamId`/`ClearActiveTeam` accessors were unused, bypassed by direct
  `charData.activeTeamId` writes at lines 168/203/348. The feature is live; the
  accessors were redundant. A less careful sweep would have concluded the whole
  "active team" concept was dead.

**Cascades found by removing the 19:**
- **The dynamic-filter cache is entirely orphaned.** `CacheDynamic` had exactly one
  occurrence — its own definition — so `PSM._dynamicFilterCache` was never populated
  and `ClearDynamicFilterCache` was clearing an empty table. Left behind when T8
  rewrote the dynamic filter functions.
- `PanelFilterFragment`'s `favKey` had one consumer, the removed cache-key generator.
- `SetupNoteEditing` held the **only** references to `PSM.NPCNotes` and
  `PopUpManager:CreateNoteEditor`, neither defined anywhere in the addon — confirming
  T6's note that `CreateNoteEditor` was dead. Two phantom symbols gone.
- `AnyNPC` was **already** unused beforehand and is the only unused `local function`
  in the addon. **Sweep blind spot:** the public-function sweep only matched
  `function PSM.X:Y`, so file-local functions were invisible to it. A follow-up sweep
  for `^local function` found exactly this one, so the gap was narrow — but check
  both forms next time.

**Process finding worth keeping.** The first automated removal pass had a real bug:
it located each function's end by scanning forward for a column-0 `end`, which is
wrong for **single-line** functions (`function PSM.Teams:SetActiveTeamId(id) ... end`).
It silently swallowed everything up to the *next* function's `end` — including the
live `HasActiveTeamChanged`. Caught because the reported line count (9) was absurd for
a one-liner and a subsequent target went missing. **Reverted everything and redid it
with single-line detection.** Lesson: when scripting bulk deletions, have the script
report per-item line counts and treat any implausible number as a bug, not noise —
`luacheck` would *not* have caught this, since removing a whole function leaves
syntactically valid Lua.

**Still to do:** in-game smoke test. Every removal is provably unreachable so
behaviour should be identical; the only behaviour-adjacent edit is dropping the
`ClearDynamicFilterCache()` call from `UpdateDynamicFilters`, a no-op against a cache
nothing ever wrote to. Exercise: Owned Pets list/grid/grouped views, pet groups, teams
panel (save/rename/duplicate/delete/apply), all dialogs, and the Models Browser filter
toggles (which is what `UpdateDynamicFilters` drives).

---

**FRESH SWEEP (2026-08-27).** 23 functions removed across 9 files, plus one local
constant. **luacheck 10/0 unchanged, tests 207 green.** The sweep covered all 735
definitions — `function X:Y` / `function X.Y`, `local function`, and `X.Y = function` —
not just public `PSM.*` names, closing the file-local blind spot the 2026-08-11 pass
recorded.

**The masking bug that made the first sweep an undercount, and the fix.** A naive
"grep the name, ignore its own definition line" misses two whole classes:

- **Cross-definition masking.** `function GV:IsEnabled()` reads as a *reference* to
  `ns.UI.GroupedView:IsEnabled`, so two dead functions sharing a name vouch for each
  other. Six of the twenty-three (`IsEnabled`, `Toggle`, `ShowPetTooltip` × 2,
  `HideRow` × 2) were hidden this way.
- **Name collision across unrelated tables.** `PSM.NotesData.Get` looked live because
  `FilterState:Get` has 70+ call sites. Only receiver-aware matching finds it.

Two passes were therefore run and intersected: one masking *every* definition header
(not just the candidate's own) before searching, and one resolving each call site's
receiver through file-local aliases and comparing it against the defining table.
Neither alone is sufficient — the first misses collisions, the second produces false
positives wherever an alias line carries a trailing comment (`local GV = ns.UI.GridView
-- alias`) or a method is attached to a widget instance rather than a module. **A
single-heuristic sweep will undercount; run both and reconcile by hand.**

Removed: `GridView` and `GroupedView`'s `Toggle`/`IsEnabled`/`ShowPetTooltip`
(view mode is switched by the panel buttons calling `Enable`/`Disable` directly, and
tooltips moved to `PetTooltip`); `GroupedView`'s `ExpandAllGroups`/`CollapseAllGroups`
— whose comment claimed they were "kept for any external callers", which `PublicAPI.lua`
makes impossible: `UI` is not published, so the trap raises on any outside read —
plus `AutoCreateGroupsByCriteria`; `Row:HideRow` and `GridView:HideRow`, cascading to
`RowManager:HideRow` and `RowManager:HideFavoriteButton`; `TeamsPanel:Hide`;
`ModelsPanel:BuildPanel` cascading to `LoadSavedPage`; six `PetModels` accessors
(`GetModelsIndex`, `GetModelCount`, `GetModelInfo`, `GetAllPetsForDisplay`,
`PreloadAllFamilies`, `GetLoadingStats`) and the `addonName` local only the last used;
`PetRoulette:CleanupPetRouletteWithoutModel`.

**A latent bug found by a cascade, not by the sweep.** `ModelsPanel:BuildPanel` was
unreachable — `Toggle` calls `PanelManager:TogglePanel(..., CreateModelsPanel)` directly
— which meant `LoadSavedPage` had never run in this shape. Its work is duplicated by
core's `Data.lua`, which already restores `modelsPanelCurrentPage` into `ns.state`, so
nothing regresses; but a live-looking restore path that no longer runs is exactly what a
dead-code sweep is for.

**`Selections:Any` looks dead and was deliberately kept.** Its only references are in
`selections_spec.lua`. It is not the `SafeStringFormat` case: its own comment says it
exists to replace the hand-written `next(...) ~= nil` presence tests, and those callers
are still there (`UI.lua:306-309`, `ModelsDataLoader:558`, and four more). Removing it
would delete the correct helper and leave the subtly wrong idiom it was written to
retire. **Migrating those call sites is a behaviour change** — truthy value vs. key
presence — so it belongs in its own task, not in a deletion pass.

**Two dead functions lived in a generated file.** `PSM.NotesData.Get` and
`.GetUserNote` in `Data/NotesData.lua`: `Get` merges seed and user notes, but every
consumer indexes `PSM.NotesData[id]` and merges by hand, and nothing reads a user note
through the accessor. Fixed in `psm-data/15_generate_notes_lua.py` and regenerated
rather than hand-edited, per that repo's own rule. The regenerated file's diff was
checked to be *only* those two functions before syncing — a generator change is a data
change unless you prove otherwise. Its header comment also still claimed the file
"ships in the PetStableManagement_Data addon", a tier that was tried and reverted;
corrected in the same pass.

**Acceptance still outstanding:** in-game smoke test, same exercise list as above.

---

### Comment trim (2026-08-27) — companion to A15

Not a plan task; done alongside A15 on the standing note that comments here read like
commit messages. **1126 deletions against 387 insertions across 38 files; comment
density 16.9% → 15.2%.** No code changed — luacheck 10/0 and 207 tests before and after.

The rule applied: a comment earns its place if it stops the next editor breaking
something. What went was the *history* — "this used to be X", "three call sites had
drifted", "caught because the reported line count was absurd" — which belongs here and
in commit messages. What stayed, sometimes verbatim: client-API facts confirmed by macro
(`Loader:IsBrowserAvailable`'s two `loadable`/`reason` traps), sign conventions
(`SetClampRectInsets`), ordering constraints (`CloseOnEscape` sets propagation *before*
hiding; `Widgets` applies `size` before `Skin.Apply`), and every "deliberately not X"
where X is the obvious next edit.

**One removal was load-bearing prose masquerading as history and had to be kept as a
rule:** several blocks explained *why* a thing must not be done ("do not guard this on
`maxScroll > 0`", "read `GetSearchText`, never `GetText`") inside a narrative about the
bug that taught it. Cutting the narrative without restating the rule would have deleted
the warning. Where that happened the sentence was rewritten as an imperative rather than
dropped.

- **Full rewrite.** 60k lines, shipped, with users. Best case outcome is parity. No.
- **Ace3 / AceGUI / AceDB.** Would supply the store, options and widget layers for free
  and is the genuine industry standard. Declined because the addon's existing UI is
  heavily custom (ElvUI skinning, 3D model widgets, drag-drop, resizable popups), so
  AceGUI would be fought rather than used, and AceDB would force a SavedVariables
  migration for every existing user. **Worth reconsidering for `Options` alone** (A12),
  where AceConfig's declarative model is exactly the shape proposed anyway.
- **A fourth `PSM_Data_Detail` addon** for `CoordsData` + `NotesData`. Real but
  unmeasured win, against real AddOns-list clutter. Revisit after A2 with numbers.
- **Persisting filter state by internal ID instead of name.** Settled in T8 and still
  correct: hash lookup is O(1) for strings and integers alike, so there was never a CPU
  win, and name-keying means zero user migration. Don't revisit without new evidence.
- **A general-purpose event bus with wildcards / priorities.** `Services/Events.lua`
  should stay a thin dispatcher. This addon has ~8 events; anything more elaborate is
  architecture for its own sake.
- **Rewriting `Events.lua`'s stable-collection retry heuristics.** The logic reading
  Blizzard's on-screen `ListCounter` text as a completeness signal (because
  `dataProvider:GetSize()` is untrustworthy) is hard-won and correct. A5's
  `StableSession.lua` should **move** it into a named state machine, preserving every
  condition — not redesign it.

---

## Stress test: Models Browser filter flow (2026-08-11)

Run before committing to A5, against the most complex real interaction in the addon:
**user ticks one family checkbox in the Models Browser.** Traced through
`ModelsFilters.lua` → `ModelsDataLoader.lua` → the dynamic-filter rebuild.

**Verdict: the store/selector design holds, with three corrections — now folded into
A5.0-A5.2.** Recording the reasoning so it isn't re-derived later.

**What the trace confirmed works.** The pull-based selector model fits this flow better
than the current push model. Today every one of 11 call sites must remember to call
`ReloadAndSummarise()` *and* `UpdateDynamicFilters()`, in that order. Checked whether
the ordering is load-bearing: it isn't — `GetAvailableFamiliesForFilters` recomputes
from `PetModels:GetFamilyModels` directly rather than from `panel.allModels`, so the two
are siblings, not a sequence. Under selectors both calls vanish; whoever reads gets a
current value. That's 11 coordination sites deleted, and 11 chances to forget.

**What it broke.**

1. *Three homes for filter state* (→ A5.0). Multi-selects in `PSM.state`, tristates on
   the panel **frame**, search text inside the **EditBox widget**. Version counters see
   none of the last two. This would have shipped as "filters sometimes don't apply until
   you touch something else" — the single most user-visible failure mode available, and
   it would have looked like a caching bug rather than a state-ownership bug.
2. *Leave-one-out dependencies* (→ A5.1). The first draft said "migrate the filters
   slice first," assuming one slice. The dynamic filters deliberately exclude their own
   dimension, so one slice = correct results, wasted work — a full 61-family rescan on
   every family click. Granularity had to be decided, not defaulted.
3. *Count-as-proxy-for-set* (→ A5.2). `#PSM.state.stablePets` in the cache key is a
   pre-existing latent staleness bug, not something the redesign introduces. Found only
   because modelling the dependency explicitly forced the question "what exactly does
   ownership depend on?" — which the string key never had to answer.

**Unexpected finding, and the reason A5 now says don't-delete-the-expiry-early:**
`UI.lua:300-305`'s `GetTime() - timestamp < 0.1` window reads like dead weight, but it
is what currently bounds the blast radius of #1 and #3. It is a *staleness backstop for
unmodelled dependencies*. Delete it before the dependency set is complete and latent
bugs get worse, not better — the opposite of what "remove the redundant debounce" would
suggest.

**Meta-lesson worth keeping:** the string cache key is *tolerant of incomplete
dependency modelling* (a missing input degrades to over-caching for 0.1s, which is
usually invisible). Version counters are *not* — a missing input is permanent staleness.
The design is strictly better once the dependencies are right, and strictly worse until
then. That asymmetry is why A5.0 is a hard prerequisite rather than a cleanup.

---

## Running log

*(same convention as the optimization plan: task, before, after, delta, surprises)*

| Task | Date | Result |
|---|---|---|
| A2 | 2026-08-11 | **DONE for the floor.** Login footprint **8.2MB → 1.65MB (−80%)**; optional stack's contribution **6.57MB → 0**. luacheck 70/0, ruff clean. Open-panel number needs a controlled re-measure (below). Branch `feat/load-on-demand`, uncommitted. |

### A4 result (2026-08-11) — harness landed, CI outstanding

**42 tests passing, exit 0.** luacheck 70/0 across all four directories (`Tests/`
included, via a new per-path `files["Tests/"]` block — the first working instance of
the mechanism A3 generalises).

**Runtime decision:** the machine had *no* Lua interpreter, only `luacheck.exe` (a
standalone linter binary that can't execute code). Rather than fight LuaRocks on
Windows, the suite is pure Lua 5.1 driven by a ~130-line `Tests/framework.lua`, with
**two entry points sharing one suite definition**: `lua.exe Tests/run.lua`, and
`Tests/run.py`, which borrows lupa's bundled Lua 5.1 via `uv run --with lupa`.
lupa ships builds for 5.1/5.2/5.3/5.4/5.5/LuaJIT — **pick `lupa.lua51` explicitly**;
the default import gives 5.5, which is not the client's dialect. Net effect: the
suite runs today with nothing installed, so obtaining `lua.exe` is optional
convenience rather than a prerequisite.

**What it caught on first run** — two latent quirks in `Utils:SafeStringFormat`, both
in code that has **zero call sites**:
1. `local args = {...}` + `ipairs` silently drops `nil` arguments, so the coercion the
   function plainly intends (`tostring(arg ~= nil and arg or "nil")`) never executes,
   and it falls back to returning the raw format string. A correct version needs
   `select("#", ...)` and `unpack(args, 1, n)`.
2. That same ternary renders boolean `false` as `"nil"` — the classic Lua `and/or`
   trap, since the middle term is falsy.

Both are pinned by tests asserting **actual behaviour, not intent**, with comments
explaining the mechanism. Neither was fixed: the function is dead code, and changing
it is a separate decision from building the harness. Worth noting the harness earned
its keep inside one run, on the *least* interesting file in the suite.

**CI added (2026-08-11).** `.github/workflows/ci.yml`, two parallel jobs on push/PR:

- **lint** — installs Lua 5.1 + luacheck via luarocks, runs it over all three
  directories. **Gates on errors, not warnings**: luacheck exits 1 for warnings and
  ≥2 for errors, and the project carries a stable 70-warning baseline, so failing on
  any warning would fail every run. The count is echoed to the job log so drift stays
  visible.
- **test** — installs `lua5.1` from apt and runs `lua5.1 Tests/run.lua`, i.e. the
  *primary* entry point rather than the lupa bootstrap, so both paths stay honest.

**Verified green on first push (2026-08-11).** Both jobs passed, including the
`luarocks --lua-version=5.1 install luacheck` step flagged beforehand as the least
predictable part of the setup — it works as written, no fallback to `apt install
lua-check` needed. Only follow-up was a deprecation warning (`actions/checkout@v4`
targets Node.js 20 and was being forced onto Node 24), fixed by bumping to v5.

A1's schema-compat check is not a separate CI step because
`models_data_spec.lua` already *is* that check: it fails if psm-data emits a shape
the addon can't read. A1 would add the explicit version stamp on top.

**A4 is now complete.**

### A2 measured result (2026-08-11, in-game)

Macro used (kept under the ~250-char chat/macro truncation limit noted in the
optimization plan; prints load state as well as KB, because ElvUI's readout cannot
distinguish "loaded and small" from "not loaded"):

```
/run collectgarbage();UpdateAddOnMemoryUsage();for _,a in ipairs({"","_ModelsBrowser","_Data"})do local n="PetStableManagement"..a print(n,C_AddOns.IsAddOnLoaded(n) and "L" or "-",GetAddOnMemoryUsage(n))end
```

**1. Login, browser never opened — the number A2 targeted:**

| | Before A2 | After A2 |
|---|---|---|
| `PetStableManagement` | ~1.65MB | 1.65MB (unchanged) |
| `PetStableManagement_ModelsBrowser` | 6.57MB (T9 floor) | **0 — not loaded** |
| `PetStableManagement_Data` | — | **0 — not loaded** |
| **Total** | **~8.2MB** | **1.65MB (−80%)** |

BugSack clean at login. Chained with T1-T9, the optional-addon floor for a session
that never opens the browser went 13.26MB → 0.

**4. Magnifier on an owned pet, browser never opened** (the one genuinely new code
path): core 2.90MB, browser 2.56MB, data 6.12MB. Loads lazily, renders taming/notes/
conditions as before, no errors.

**Full lifecycle, re-measured after the two-addon merge (2026-08-11):**

| State | Core | Browser | Total |
|---|---|---|---|
| Login, nothing opened | 1.65MB | not loaded | **1.65MB** |
| Owned Pets panel open | 2.89MB | **not loaded** | **2.89MB** |
| + magnifier from Owned Pets | 2.90MB | 8.69MB | 11.58MB |
| + Models Browser open | 3.59MB | 13.61MB | 17.20MB |
| All panels closed again | 2.97MB | 6.77MB | 9.73MB |

Two confirmations and one new finding:

- **Owned Pets alone never loads the browser** — the common "just manage my stable"
  session runs at 2.89MB with the optional stack untouched. This is what A2 was for
  and it is now directly observed, not inferred.
- **The merge is memory-neutral**, as predicted: magnifier state 8.69MB vs 2.56+6.12
  = 8.68MB across separate addons; browser open 13.61MB vs 7.31+6.30 = 13.61MB, and
  T9's pre-A2 baseline was 13.64MB. Identical to three significant figures across a
  folder restructure.
- **Memory ratchets and never fully returns.** Closing every panel drops the browser
  13.61MB -> 6.77MB, but it stays *loaded* at 6.77MB for the rest of the session:
  WoW cannot unload an addon. The browser is therefore a **one-way door** — never
  touch it and pay 1.65MB; touch it once and pay ~9.7MB until `/reload`. The trigger
  is easy to hit by accident: **a single magnifier click from Owned Pets costs
  8.69MB** in a session that would otherwise stay under 3MB. Core ratchets too
  (1.65 -> 2.97MB) from pooled widgets and caches that are never released — that is
  A8's target.

**Not a reason to re-split the addon** (see the revert above; that decision stands on
its own evidence). Roughly 6MB of the 8.69MB is the data tables, which any design must
load. The real lever is A6/A7 separating the UI-free resolvers (`PetModels`,
`TamingChecker`) from panel code, so the magnifier could pull logic + data without the
UI — worth perhaps 2MB, not 8. **Recorded, not scheduled.**

Correction to a design estimate made during implementation: A2's notes argued
`EnsureBrowser()` at the magnifier costs "barely more than `EnsureData()`" because
browser logic is ~5k lines against ~39k lines of data, so maybe 10%. Measured, browser
code is **29%** of the browser+data pair (2.56MB of 8.68MB) — off by 3x. The decision
still stands (behaviour preserved, data still dominates), but line count was a poor
proxy for runtime footprint and shouldn't be used as one again.

**3. Panel open — NOT comparable, re-measure outstanding.** Reading was browser
15.47MB + data 6.30MB = 21.8MB, against T9's "open, heavily used, forced GC" figure of
13.64MB. Two reasons it can't be read as a regression yet: the T9 repro selects *all*
families/expansions/locations and waits ~2s, while this was a plain `/psm models` with
saved filters; and splitting the addons **moves memory attribution**, since
`GetAddOnMemoryUsage` credits the addon whose *code* allocated — derived structures
(per-family caches, render lists) now bill to `_ModelsBrowser` while their source
tables bill to `_Data`. Needs one controlled re-run under the T9 protocol before it
means anything. **Do not record an open-panel delta until that exists.**

### A2 notes (2026-08-11)

**Scope was larger than the task text assumed.** The plan said "add LoadOnDemand and
handle the guards"; the actual coupling surface was **49 core→browser references
across 8 core files**, and the addon had *no* `LoadAddOn`/`IsAddOnLoaded` machinery at
all — every optional-module check was "is this global present?".

Those 49 sorted into three groups, and only two needed work:

- **User-initiated entry (11 sites)** — `/psm models`, `/psm roulette`, minimap
  right-click and context menu, broker menu, floating menu, the magnifier's "open
  browser" button. All now route through `PSM.Loader:EnsureBrowser()`.
- **"Only if already open" (10 sites)** — Options panel sliders, `CleanupPanel`,
  `RowManager`'s favourites reload. Every one is already guarded on
  `PSM.state.modelsPanel` existing, which can only be true if the browser loaded.
  **Zero changes needed** — correct by construction.
- **Data reads from core (28 sites, all in `PopUpManager.lua`)** — see below.

**The finding that made this tractable:** mapping every data-read site to its
enclosing function showed all 28 live inside *popup* flows
(`ShowMagnificationPopup`, `PopulateModelPopup`, `CreateNPCRow`, `ShowNoteEditor`,
`GetCoordsDataForLocation`), **not** inside Owned Pets mouseover tooltips. So no hot
path can trigger a load, and the wiring collapsed to three entry points instead of 28.
This was the main risk going in and it evaporated on inspection — worth checking the
same way before assuming a load trigger is dangerous.

**Two loading granularities, both earning their place:**
- `EnsureData()` — `ShowNoteEditor` (needs `PSM.NotesData` only) and
  `GetCoordsDataForLocation` (needs `CoordsData` only). Silent variant for the latter
  since the browser's NPC table calls it once per row.
- `EnsureBrowser()` — the magnifier, which turned out to need the browser's *own*
  resolvers (`PSM.PetModels`, `PSM.TamingChecker`), not just the tables. Cost of
  pulling the whole optional stack there is small: the generated data is ~39k lines
  vs ~5k lines of browser logic, so data dominates the byte count either way.

**Corrections made while implementing:**
- Dropped the `_G.IsAddOnLoaded` / `LoadAddOn` / `GetAddOnInfo` fallbacks — those
  globals were removed in 11.0, well below this addon's `## Interface` floor, so the
  fallback was dead code pointing at names that no longer exist. `C_AddOns` only.
- `Menu.lua`'s `AddButton` gated its disabled-state on `_G.PSM[moduleName]`, which
  under LoadOnDemand is *always* nil at menu-build time — both browser buttons would
  have been permanently disabled. Needed a new `Loader:IsBrowserAvailable()` ("present
  and enabled", via `GetAddOnInfo`'s `loadable`) rather than "loaded". Same fix for
  the minimap tooltip's right-click hint. **This is the class of bug to watch for in
  the rest of A2-style work: under LoD, "not loaded" is the normal state, so any UI
  affordance keyed on module presence silently disappears.**
- `EnsureBrowser` loads the data addon explicitly before the browser rather than
  relying on `RequiredDeps` to resolve a *LoadOnDemand* dependency. The `.toc`
  declaration stays as source of truth; this just makes ordering deterministic.
- Removed three now-redundant "module is not loaded" messages (`SlashCommands`'s
  `ModulesMissing`, two in `Broker`) — the Loader reports a more precise reason
  (disabled / missing / in combat), once per session per addon.

**Cross-repo:** `psm-data/config.py`'s sync target moved to the new folder and the
constant was renamed `ADDON_MODELS_BROWSER_DIR` → `ADDON_DATA_DIR`. Verified it
resolves and all five files are present at the new path.

**Blocked on the user before it can be measured:** the new `PetStableManagement_Data`
folder needs a symlink into `Interface/AddOns` (creation requires elevation), and all
three addons must be enabled in the in-game AddOns list.

#### Reverted: the three-addon split, back to two (2026-08-11)

The data tables were briefly a third addon, `PetStableManagement_Data`, justified as
"core can load the tables without the browser UI, for the Owned Pets magnifier".
**That justification does not hold, and the split was reverted the same day.**

Traced every `EnsureData()` call site — there were two, `GetCoordsDataForLocation`
and `ShowNoteEditor`, and *both* are only reachable from code that has already called
`EnsureBrowser()` (the magnifier's NPC rows, `NPCRow.lua`, `ModelsPanel.lua`). The
reason was visible during implementation and not followed through: the magnifier needs
`PSM.PetModels` and `PSM.TamingChecker`, which are browser *logic*, not data — so it
loads the browser regardless, and the data-only tier is never exercised. `EnsureData`
was a memoised no-op at both sites.

Meanwhile the cost was real and user-facing, which is how it surfaced: **three entries
in the AddOns list when users only conceive of two features** (manage my pets / find my
next tame), plus a failure mode where disabling "Data" breaks the browser.

Now: two addons, with the generated tables in
`PetStableManagement_ModelsBrowser/Data/`. That keeps the one genuine benefit — a sync
target containing nothing but generated files, so it's unambiguous which Lua is
hand-written — at zero user-visible cost. **Memory is unchanged**: `LoadOnDemand` is
per-addon and the browser is still LoD, so the 1.65MB floor stands. `PSM.Loader`
collapsed to a single addon, which also deleted `IsDataLoaded` (itself dead code).

**Rule added to `CLAUDE.md`:** don't add a third addon folder without a demonstrated
need. Re-splitting is only worth revisiting if A6/A7 ever separate the browser's
UI-free resolvers from its panel code, which would make data-only loading real rather
than theoretical.

**Generalisable lesson:** the split was designed from a plausible-sounding access
story, and implementation produced the evidence against it ("turned out to need the
browser's own resolvers") without that evidence being re-checked against the original
justification. When implementation contradicts a design premise, re-derive the design,
don't just note the contradiction and continue.

#### First in-game run: `## OptionalDeps` silently defeated the whole task

First `/reload` produced three errors and a Data addon that loaded at login anyway
(5.35MB). **Single root cause, and it was a line added during this task**: core's
`.toc` had been given

```
## OptionalDeps: Blizzard_StableUI, PetStableManagement_Data, PetStableManagement_ModelsBrowser
```

on the reasoning that declaring the relationship was good hygiene. It is the opposite.
`OptionalDeps` means **"load these before me if they are enabled"**, which did two
things at once:

1. **Defeated `## LoadOnDemand`** — both optional addons loaded at login, so the
   memory floor was unchanged. The task silently did nothing.
2. **Inverted the load order** — they ran *before* core created `_G.PSM`.

Both reported errors follow from (2), and each exposed a different pre-existing
fragility:
- `ConditionsData.lua:137`, `NotesData.lua:2107` — *"indexed assignment on global
  'PSM' (a nil value)"*. Confirmed all five generated data files lack the
  `_G.PSM = _G.PSM or {}` preamble that every hand-written file carries; the two that
  assign to `PSM.*` therefore depend entirely on load order being right.
- `ModelRow.lua:33` — *"attempt to index upvalue 'cfg'"*. `ModelRow.lua:9` does
  `local cfg = PSM.Config` at **file scope**, so it captured nil and only failed much
  later, at first use. File-scope captures of another module's table turn a load-order
  bug into a delayed, misleading stack trace.

**Fixes:** reverted core's `OptionalDeps` to `Blizzard_StableUI` only (with a comment
saying why the others must never be listed), and added the `_G.PSM` preamble to
`NotesData.lua` / `ConditionsData.lua` **and to their generators**
(`15_generate_notes_lua.py`, `14_generate_conditions_lua.py`) so the next pipeline run
doesn't revert it.

**Rules worth carrying forward:**
- **Dependency direction in `.toc` files is one-way.** Optional modules declare
  `RequiredDeps` on core. Core declares *nothing* about them. Any core→optional
  declaration either breaks LoadOnDemand or inverts load order.
- **Never capture another module's table into a file-scope local** (`local cfg =
  PSM.Config`). Read it inside the function. This is a `Core/Compat.lua` + layering
  concern that A3 should sweep for repo-wide — `ModelRow.lua` is unlikely to be the
  only instance.
- Generated files need the same namespace preamble as hand-written ones, and the fix
  belongs in the generator, not the artefact.

---

### A6 result (2026-08-11) — UI kit landed, PopUpManager migrated

**Done, pending in-game verification.** New `PetStableManagement/UI/` with four
files, loaded before any frame-building code:

| File | Namespace | Contents |
|---|---|---|
| `Theme.lua` | `PSM.Theme` | `FONT`, `SIZE` ramp, `COLOR` grey ramp, 4 `BACKDROP` presets, `FILL` colours |
| `Skin.lua` | `PSM.Skin` | `Apply`, `Texture`, `IsActive`, `SUPPORTED`, `unhandled` |
| `Tooltip.lua` | `PSM.Tooltip` | `Show`, `Hide`, `Attach` — declarative specs |
| `Widgets.lua` | `PSM.Widgets` | `Frame`, `MovableFrame`, `Label`, `Button`, `IconButton`, `CloseButton`, `EditBox`, `Line`, `Backdrop`, `ResizeGrip`, `CloseOnEscape` |

**Measured on the proof file, `Shared/PopUpManager.lua`:**

| Pattern | Before | After |
|---|---|---|
| `CreateFrame(` | 32 | **0** |
| `ApplyElvUISkin` | 20 | **0** |
| `CreateFontString` | 11 | **0** |
| `SetBackdrop` | 15 | 3 |
| `GameTooltip:` | 36 | **0** |

The three surviving `SetBackdrop` calls are all `SetBackdropColor` inside
`UpdatePopupBackground` — *runtime recolours*, not construction. **That's the line to
draw when migrating the next file:** the kit owns how a widget is built, not how it
is later restyled in response to state.

Repo-wide, one file in: `ApplyElvUISkin` 86 → 67, `CreateFrame` 193 → 167,
`GameTooltip:SetOwner` 33 → 28.

**Four things worth carrying forward:**

1. **`"scrollframe"` was a silent no-op at 4 call sites.** The old
   `ApplyElvUISkin` was an if/elseif chain with no else, so an unrecognised skin type
   did nothing and said nothing. `Skin.lua` replaces the chain with a handler table
   where `false` means *known, deliberately nothing to do* (ElvUI has no
   `HandleScrollFrame`; what needs skinning is the `ScrollBar` child) and a missing
   key is counted into `PSM.Skin.unhandled`. luacheck cannot catch a bad string
   literal; a table lookup can.
2. **No pcall around skin handlers, on purpose.** Swallowing an ElvUI error would
   make skinning regressions invisible on a non-ElvUI client — which is exactly the
   client most testing happens on, and exactly the failure this task is most likely
   to cause.
3. **The luacheck baseline in `CLAUDE.md` was stale (70) — the real HEAD figure was
   67.** A15's sweep dropped it and the doc wasn't updated, so a "clean" run would
   have quietly hidden 3 new warnings. Measured before/after this time by stashing:
   67 → 65, with the −2 fully attributable to two unused `OnSizeChanged` args
   removed by `Widgets.CloseOnEscape`. **A baseline nobody re-measures is not a
   baseline.** Both docs corrected.
4. **`Widgets` skins what it builds** — that is the actual deliverable, not the line
   count. `IconButton` is the one deliberate exception: ElvUI's `HandleButton` strips
   the very textures those buttons consist of.

**Not done here:** the other 15 files still call `PSM.UI:ApplyElvUISkin`, which now
forwards to `PSM.Skin.Apply`. The shim stays until the last caller migrates. Next
highest-density targets: `SpecialTames.lua` (45), `ModelsFilters.lua` (40),
`Dialogs.lua` (40).

**Acceptance still outstanding:** in-game pass **with and without ElvUI** — model
magnifier (open/resize/rotate/zoom/reset/favourite), NPC rows and every hyperlink
tooltip, waypoints popup, note editor, URL popup.

**Bug found in first in-game test (2026-08-11), fixed:** `opts.size` meant two
different things — `{width, height}` in the shared `ApplyCommon`, but *font size* in
`Widgets.Label`. Every `Label` therefore reached `unpack(12)` and the magnifier died
on `CreateModelPopup`. An options table is a namespace, and I let one name carry two
types in it.

Three changes, in increasing order of value:

1. Label's text size is now `fontSize`; `size` means `{width, height}` everywhere in
   the kit, with no exceptions. (Button's `font` became `fontObject` in the same pass,
   to match `EditBox`.)
2. `ApplyCommon` raises a directive — *"`size` must be {width, height} — for text size
   use `fontSize`"* — instead of failing inside `unpack` with no hint of the cause.
3. **Every factory now declares the keys it accepts** (`OPTIONS` in `Widgets.lua`), and
   an undeclared key is counted in `PSM.Widgets.unknownOptions` (`/dump` it) rather
   than silently ignored. This is the general form of the bug: options tables fail
   *quietly*, so a key that is misspelled, or right for a different factory, produces a
   subtly wrong widget and no error. Same design as `PSM.Skin.unhandled`, same reason.

All existing call sites were then audited against those declarations statically, rather
than being discovered one crash at a time — clean.

**The generalisable lesson:** a shared options table needs its vocabulary pinned down
*before* the call sites multiply, because every silently-ignored key is a bug that
surfaces as "the widget looks slightly wrong" much later. Both defences here — the
declared key sets and the typed `size` check — cost about twenty lines and remove a
whole class of failure from the remaining 15 files still to migrate.

---

### A6 continued (2026-08-11) — SpecialTames migrated, kit extended

**`SpecialTames.lua`: `CreateFrame` 16 → 0, `ApplyElvUISkin` 5 → 0, `CreateFontString`
6 → 0, `CreateTexture` 9 → 0, `SetBackdrop({` 3 → 0, `GameTooltip:` 12 → 0.**
luacheck 65/0 unchanged, tests 37 passing.

Four kit additions, each counted before being written rather than anticipated:

| Addition | Justified by |
|---|---|
| `Widgets.Texture` | 53 `CreateTexture` calls repo-wide |
| `Widgets.CheckBox` | 10 `CreateFrame("CheckButton", …)` across 6 files |
| `Label`'s `fontObject` / `wordWrap` / `nonSpaceWrap` | 8 font-object font strings, 12 wrap calls |
| `Theme.BACKDROP.SOLID_BORDERED` and `.NONE` | 3 `edgeSize = 1` backdrops, 1 empty backdrop |

`Widgets.Line` was reimplemented on top of `Widgets.Texture` rather than kept as a
second texture path.

> **SUPERSEDED 2026-08-11 by in-game evidence — see the correction at the end of this
> entry. All checkboxes are now skinned. The reasoning below is kept because how it was
> wrong is the useful part.**

**The unskinned tri-state checkbox in SpecialTames is deliberate — do not "fix" it.**
`ModelsFilters.lua` and `SpecialTames.lua` build identical check buttons: both drive
`GetCheckedTexture():SetAlpha(0)` and overlay an `invertedTexture` for the "inverted"
state. `ModelsFilters` calls `ApplyElvUISkin(cb, "checkbox")`; `SpecialTames` does not.

I initially read that as an oversight. It isn't. **Author's account (2026-08-11):** the
ElvUI skin was tried and abandoned because the *inverted* state stopped being legible —
it renders as a grey tick on Blizzard's default UI, and a grey filled square under
ElvUI, neither of which reads as "excluded" at a glance. The current unskinned
treatment is a deliberate legibility choice: **gold tick = selected, loot-pass ✗ =
inverted**, chosen so the two states are impossible to confuse.

So the constraint for A13 is not "make these consistent" — it's **"whatever styling is
applied, the inverted state must stay unmistakable at a glance."** Consistency is the
cheaper goal and the wrong one to optimise for on its own. `ModelsFilters` shows the
skin doesn't *break* the alpha trick, only that it makes the result hard to read.

Left alone here regardless: `Widgets.CheckBox` skins by default (the kit's premise) and
the two SpecialTames call sites pass `skin = false` with a comment pointing at this
entry. A6's contract is mechanical consistency, not restyling.

#### CORRECTION (same day, after in-game testing): skin them all

Tested with ElvUI on: **the inverted state renders identically everywhere, skinned or
not** — the loot-pass ✗ in both cases. Only the *selected* state differed (gold tick
unskinned vs gold filled square skinned), which is cosmetic.

So the legibility problem was already solved by the ✗ overlay. Skipping the skin was
the *older half* of a two-part fix, and it stopped doing any work the moment the
overlay was added — but it stayed in the code, and both the author's recollection and
my write-up above treated it as still load-bearing.

`skin = false` was removed from `Widgets.CheckBox` entirely, along with its two call
sites. All ten checkboxes are now skinned. Removing the option rather than leaving it
unused matters twice over: it restores the kit's invariant to something absolute —
*everything `Widgets` returns is skinned, no exceptions* — and it kills a genuine trap,
because `skin` means "which skin type" on `Frame` and `IconButton` but meant "whether
to skin" here. That is the same one-name-two-meanings bug as `size`/`fontSize`, caught
this time before it cost anything.

**The generalisable lesson: a workaround that outlives the problem it solved looks
exactly like a deliberate design decision.** Both of us reasoned from the comment and
the code shape rather than from the current behaviour, and both of us got it wrong. The
thing that settled it was thirty seconds of looking at the actual pixels. When a
"deliberate exception" is found, re-verify the condition that justified it still holds —
the exception is evidence that it *once* did, not that it still does.

Also noted in passing: `CreateConditionRow`'s backdrop is `{ bgFile = nil, edgeFile =
nil }`, so its `SetBackdropColor`/`SetBackdropBorderColor` calls and its hover
recolour are all inert. Preserved verbatim (as `backdrop = "NONE"`) for the same
reason. Another one for A13.

**Not yet verified in-game.** `ModelsFilters.lua` (40) deliberately *not* started: this
pass added four new factories, and building three more files on unvalidated kit surface
is how a refactor turns into a bisect.

---

### A6 continued (2026-08-11) — ModelsFilters migrated, `Widgets.Tab` added

**`ModelsFilters.lua`: `CreateFrame` 17 → 0, `ApplyElvUISkin` 12 → 0,
`CreateFontString` 7 → 0, `CreateTexture` 8 → 0, `SetBackdrop({` 1 → 0,
`GameTooltip:` 5 → 0.** luacheck 65/0, tests 37 passing.

**Repo-wide, three files in: `ApplyElvUISkin` 86 → 50, `CreateFrame` 193 → 135.**

**`Widgets.Tab` added, and SpecialTames retrofitted onto it.** ModelsFilters' filter
tabs and SpecialTames' pill bar were independent copies of the same thing — flat
background, centred label, top/bottom accent rules shown only when active, all driven
from `Config.TAB` — *plus* two separately hand-written "make this one look active"
loops. The factory returns the frame with a `:SetActive(bool)` method, which collapsed
both loops to one line each.

Input handling deliberately stayed at the call sites: ModelsFilters uses
`OnMouseDown`, SpecialTames uses `OnClick`. Unifying those would change when the tab
responds to a press, which is a behaviour change, not a refactor.

**A constraint promoted from a comment to the factory.** `ModelsFilters` carried a
comment warning that the ElvUI checkbox skin must be applied *before* the first
tristate render, because `HandleCheckBox` swaps in its own checked texture and would
clobber an already-set alpha-0 "inverted" look. That was a rule living in one file's
comment, enforced by whoever remembered to read it. `PSM.Widgets.CheckBox` now skins
before it returns, so the ordering holds by construction, and the constraint is
documented at the factory instead of at one of its callers.

**Next consolidation, deliberately not done yet:** the "inverted state" overlay block —
`GetCheckedTexture():SetAlpha(0)` plus a lazily created loot-pass texture — now appears
**four times across two files**, alongside several near-identical visual-update
functions. The right fix is a `SetTriState(state)` method on `PSM.Widgets.CheckBox`:
the *rendering* of the three states is presentation and belongs in the kit, while the
meaning of `nil` / `true` / `"inverted"` stays with the caller. Not done in this pass
because it is new kit surface and three files of unverified changes are already
queued — same reasoning as deferring ModelsFilters last round.

---

### A6 — a correction to how this task was framed

I had been drawing the line as *"A6 is mechanical consistency, A13 owns look-and-feel"*,
and using it to defer visual differences. Making all the checkboxes skin identically
exposed the flaw: the Special Tames boxes were then obviously **smaller** (16px) than
the Families/Locations/Expansions ones (20px). Author's response, and it is correct:

> *"I thought the whole purpose of having centralized and reusable functions or widgets
> was to make all look the same."*

**A factory that takes `size` at every call site permits consistency without producing
it.** Every caller still decides, so the kit had reproduced the old problem with nicer
syntax — the divergence just moved from `CreateFrame` blocks into options tables. That
is not something to hand to A13; it is the kit failing at its own job.

**Fix:** `Theme.CONTROL` now names the canonical control sizes, and `Widgets.CheckBox`
**defaults** to `Theme.CONTROL.CHECKBOX` (20 — the majority: Owned Pets filters and all
three Models Browser filter lists; SpecialTames' 16 was the outlier). All five call
sites now pass no size at all. The inverted-state glyph is `Theme.CONTROL.CHECKBOX_MARK`
(16), previously a bare literal in four places and a `CFG.CHECKBOX_SIZE` in a fifth.

**The rule this generalises to, for the remaining files:** a widget with one obviously
correct value should **default** to it, and the call site should stay silent unless it
genuinely needs to differ. Defaults produce consistency; parameters merely allow it.
I initially wrote that this should *not* extend to `Button` sizes, on the grounds that
50×20, 80×25, 100×25 and 120×25 are different roles rather than drift. That conflated
two separate questions, and the author's split is the right one:

- **Height is drift.** 20 and 25 both appear with no reason behind the difference. One
  height everywhere.
- **Width is a role**, but "whatever number the author typed" is not a role. Either a
  named scale (`SMALL` / `MEDIUM` / `LARGE`) or fit-to-text.

Added to the backlog rather than done here — it touches every button in the addon and
wants deciding as one thing, not file by file.

---

## Backlog (raised during A6, out of scope for it)

- **Locations tri-state filter has a redundant state.** For Locations, `nil` (no
  selection) and `"inverted"` (exclude) produce the same visible result, so the third
  state buys the user nothing and costs them a click to cycle past. Decide whether
  Locations should be a plain two-state checkbox, or whether `nil` should mean
  something different there. Product decision, not a refactor — needs a call on what
  "no location selected" ought to mean before any code changes.
- ~~**`Widgets.CheckBox:SetTriState(state)`**~~ — **done 2026-08-12**, while migrating
  `OwnedPets/Filters.lua`. The count had grown from four copies to nine: five in
  `Filters.lua` alone (initial paint, click handler, two restore paths, Reset Filters)
  plus the four already known in the browser's filter panels. Rendering lives in the
  kit; the cycle order and the meaning of `nil`/`true`/`"inverted"` stayed with the
  caller, as planned. `SetTriState` also assigns `.triState`, which two of the
  hand-written copies had to remember to keep in sync separately.

- **`NPCRow.lua`'s checkbox is 16px** and will pick up the new 20px default when that
  file migrates — check its row layout at that point.
- **`PSM.TeamDialogs` is misnamed.** The file is `Dialogs.lua`, the table is
  `TeamDialogs`, and about half its contents (`ShowNameInputDialog`,
  `ShowConfirmDialog`, `ShowGroupNameDialog`) are generic dialogs with nothing to do
  with teams. Renaming touches 12 call sites across 4 files. Cheap, but it is a rename
  for its own sake — best folded into B, which will be deciding public names anyway.
- **Sweep for cross-addon file-scope captures generally.** `ModelRow.lua` was found
  and fixed during A6, but it was found by accident. `SlashCommands.lua:88` does
  `local PETSWAP_MAX_SLOT = PSM.Config and PSM.Config.MAX_STABLE_SLOTS or 205` — same
  class, guarded and with a fallback, so it degrades quietly rather than crashing,
  which is arguably worse. Worth a deliberate pass rather than another accident.
- **The Models Browser search placeholder never swaps, and blanks itself instead.**
  `ModelsPanel`'s `SetSearchPlaceholder` reassigns `searchBox.placeholderText` and then
  calls `SetText(newPlaceholder)` to refresh an idle box. That fires `PanelManager`'s
  `OnTextChanged`, whose `ClearPlaceholder` blanks any text equal to `placeholderText` --
  which the text now is, because the field was reassigned one line earlier. So an idle
  box loses its hint text entirely rather than changing it, and the re-entrant handler
  also schedules a debounced search for `""`, costing a spurious `ReloadAndSummarise()`
  per toggle. Opening straight into NPC view never calls it at all, so the box reads
  "Search models..." there until toggled. The fix belongs in `PanelManager`: expose
  `searchBox:SetPlaceholder(text)` that suppresses its own change handler while it
  writes, and have the view toggle call that. Do it when `PanelManager.lua` migrates.

- **The Model Magnifier discards a user-chosen size every time its content changes.**
  Reported 2026-08-12: resize the popup larger, click another Display ID, and it keeps
  the new width but snaps back to a shorter height. Diagnosis:
  `PopUpManager:PopulateModelPopup` sets `popup.needsAutoSizing = true` on **every**
  populate (`PopUpManager.lua:1328`), and both auto-size paths then compute an
  *absolute* target -- `300 + 150 + tamingH [+ min(rowsH, 350)]`, capped at 85% of
  screen height -- and `SetHeight` to it (`:425` and `:1486`). Width is never
  recomputed, which is exactly why width survives and height does not.

  The design gap is that auto-sizing is unconditional, so the popup cannot distinguish
  *"this is still the default size, fit it to the content"* from *"the user chose this
  size, leave it alone"*. Two candidate fixes, and this wants deciding rather than
  patching -- the author notes they have never got this popup fully right:
  (a) record a `userSized` flag when the resize grip finishes a drag, and skip
  auto-sizing once it is set (persisting the size in SavedVariables if it should
  outlive a session); or (b) let auto-size only ever *grow* the popup to fit content
  and never shrink it below the current height. (a) is more predictable; (b) needs no
  new state. Either way the rule should be written down at `needsAutoSizing`, because
  the current code reads as if auto-sizing were a one-shot on first populate.

- **`PSM.ModelsPanel:ShowMagnificationPopup` was dead code — removed 2026-08-12.**
  181 lines at `ModelsPanel.lua:694`, zero callers: both real call sites
  (`RowManager.lua:251`, `NPCRow.lua:471`) use `PSM.PopUpManager`'s version. Verified
  across both repos with no dynamic dispatch on the name. It was a drifted near-copy
  that still carried its own height arithmetic, including
  `popup:GetHeight() - extraHeight + extraHeight`, which is `popup:GetHeight()` --
  i.e. a no-op that looks like a calculation. Removed *before* investigating the height
  bug above rather than after, because it is the first thing anyone searching for "the
  models panel magnifier" would read, and it is not the code that runs. Third instance
  of this pattern after `PSM.Utils:ShowContextMenu` and the extracted-but-unadopted
  context menu fix: **an extracted or superseded helper that nothing calls does not sit
  inert — it actively misdirects the next person to look.**

- **Ability Browser rebuilds every frame on every keystroke.**
  `AB:PopulateAbilities` creates a fresh scroll child, cards and ability icons on each
  call, and the search box calls it from `OnTextChanged`. The previous child is only
  hidden — WoW frames cannot be destroyed — so each character typed leaks a full copy
  of the panel's frame tree. The fix is a reusable pool keyed by category, or at
  minimum debouncing the search (`PSM.Config.SEARCH_DELAY` already exists and is used
  elsewhere for exactly this). Pre-existing; found during the A6 migration.

- **Button sizing: one height, categorised widths.** Buttons currently run 50×20, 80×22,
  100×25 and 120×25 — `PSM.Config.BUTTON_HEIGHT` is 22 and `PANEL_BUTTON_HEIGHT` is 25,
  so it is a three-way split, not two. The **height should be uniform** — 20/22/25 is
  unexplained drift. The **width should be a named scale** (`Theme.CONTROL.BUTTON_W.SMALL`
  / `MEDIUM` / `LARGE`) or derived from the text, rather than a literal per call site.
  Same principle as the checkbox default: the factory should supply the value and the
  call site should stay silent unless it genuinely needs to differ. Do this as one
  sweep across every button once the per-file migrations are done, so the scale is
  chosen against the full set of real labels instead of guessed at from three files.

- **Combat protection doesn't cover every panel.** Reported 2026-08-20 while testing
  A9/A14 in-game. `Events.lua`'s `PLAYER_REGEN_DISABLED` handler calls
  `Broker:CloseAllPanels()`, which `safeHide`s a hardcoded list: `panel`,
  `modelsPanel`, `petRoulettePopup`, `teamsPanel`, `modelMagnificationPopup`,
  `exportFrame`, plus `SettingsPanel` via `HideUIPanel`. **`abilityBrowser` and
  `specialTames` are missing from that list** — both are built the same way as
  everything else in it (`PanelManager:CreateBasePanel`, stored at
  `ns.state.abilityBrowser` / `ns.state.specialTames`), so adding them is
  mechanical, not a design question. Worth grepping once more before fixing:
  `CreateBasePanel` calls are the authoritative list of what counts as "a panel"
  here, and `CloseAllPanels`'s hardcoded array should be checked against it rather
  than patched by memory, in case a future panel is added and forgotten the same
  way.

---

### A6 continued (2026-08-11) — Dialogs migrated, plus a pre-existing bug fixed

**`Dialogs.lua`: `CreateFrame` 15 → 0, `CreateFontString` 13 → 0, `GameTooltip:` 6 → 0,
`ApplyElvUISkin` 5 → 0, `SetBackdrop({` 2 → 0.** luacheck 65/0, tests 37 passing.

**Repo-wide, four files in: `ApplyElvUISkin` 86 → 45, `CreateFrame` 193 → 120.**

**It was expected to be the fat one; it wasn't, and the reason is instructive.**
`Dialogs.lua` already had three internal factories (`CreateBaseDialog`,
`CreateDialogButton`, `CreateDialogEditBox`), so its frame construction was already
centralised — just privately, for one file. Migration was mostly re-pointing those
three at the kit. What it *had* not centralised was **text**: 13 `CreateFontString`
calls, each respelling font, size, colour and justification per dialog. A fourth local
factory, `CreateDialogText`, now covers them.

The lesson for the remaining files: **a file that looks well-factored may only be
factored along one axis.** This one had solved frames and left text entirely alone.

#### Two corrections found while migrating

**1. `ModelRow.lua` still held cross-addon file-scope captures.**

```lua
local cfg = PSM.Config       -- core's Config, captured from inside the browser addon
local mgr = PSM.RowManager   -- ditto
```

This is the exact pattern `CLAUDE.md` forbids, and the exact line that produced the
A2 incident (`attempt to index upvalue 'cfg'`). Back then the *symptom* was fixed by
correcting load order; the capture itself was never removed, so the file has been one
`.toc` reordering away from the same crash ever since. It also breaks first under B.
Seven call sites, now read inside their functions, with a comment saying why.

**Worth generalising: fixing the trigger is not fixing the bug.** The A2 write-up
recorded the rule ("never capture another module's table at file scope") but nobody
swept for existing instances — so the rule was documented and violated in the same
file that motivated it.

**2. Escape was silently dropping cancellation.** `CreateBaseDialog`'s hand-written
Escape handler called `onCancel`; `Widgets.CloseOnEscape` did not. A straight swap
would have made Escape close dialogs *without telling the caller waiting for an
answer*. `CloseOnEscape(frame, onEscape)` now takes the callback. Closing by X, by
Escape, or by Cancel all report through one `Cancel()` local.

The original also never set `SetPropagateKeyboardInput` before the first keypress, so
the first non-Escape key pressed over a dialog was swallowed. The kit sets it up
front, which fixes that incidentally.

#### Two deliberate behaviour changes, both flagged for testing

- **Resize grips are now left-button only.** Two of the three hand-written grips
  started a resize on *any* button, right-click included. The kit's version guards on
  `LeftButton`.
- **The ElvUI `"frame"` skin call was kept at the bottom of `CreateBaseDialog`**, not
  moved into the frame constructor, because `HandleFrame` strips textures and the
  original ran it *after* the title/close/grip existed. Moving it would have changed
  what was in scope when it ran.

#### Finding for the backlog

`PSM.TeamDialogs` has **zero direct callers in the browser addon** — all 12 external
call sites are in core. The browser reaches dialogs only indirectly, via
`RowManager`'s team buttons on model rows. So Dialogs is *not* part of B's public
surface, despite the expectation that it would be. The namespace is also misnamed:
the file is `Dialogs.lua`, the table is `PSM.TeamDialogs`, and roughly half its
contents (`ShowNameInputDialog`, `ShowConfirmDialog`, `ShowGroupNameDialog`) are
generic, not team-specific.

- **BUG (recurring, pre-existing): only 1 pet collected on first stable visit.**
  Reported 2026-08-11, and a recurrence of a bug previously thought fixed.

  **Symptom:** visiting a Stable Master for the first time in a while, the Owned Pets
  panel shows **1 pet** while Blizzard's own StableFrame shows **197/205** — the
  on-screen counter we adopted as the ground-truth check last time this was chased.

  **What does *not* fix it:** Reset Filters; closing and reopening the Owned Pets
  panel. That rules out filter state and panel rebuild — the data was never collected,
  rather than collected and then hidden.

  **What does fix it:** closing the StableFrame and talking to the Stable Master
  again. So a second `PET_STABLE_SHOW` cycle collects correctly.

  **Hypothesis to test first — the retry loop gives up too early.**
  `Events.lua:ScheduleUpdateWithRetry` decides collection is complete when *any* of:

  ```lua
  local isAtCap = collectedCount >= PSM.Config.MAX_STABLE_SLOTS
  local matchesListCounter = listCounterCount ~= nil and collectedCount == listCounterCount
  local isStable = isAtCap or matchesListCounter
      or (retryCount > 0 and _lastScheduledCollectedCount == collectedCount)
  ```

  On a cold first visit the client streams stable data in slowly, so two consecutive
  reads 0.15s apart can both legitimately return **1** (the active pet only). That
  satisfies the third clause — *"two identical readings means we're done"* — and the
  loop exits after ~0.3s with one pet, even though `listCounterCount` says 197.

  The `matchesListCounter` clause exists to prevent exactly this, but it only helps
  when the counter is readable *and* already correct; on a cold visit it is probably
  neither. **Note the third clause never checks it disagrees with the counter** — a
  stable-looking count that contradicts a known-good total should not be treated as
  complete.

  **Suggested investigation:** log `collectedCount`, `expectedCount`,
  `listCounterCount` and `retryCount` on every pass of a cold first visit. If the
  hypothesis holds, the fix is to make the "two identical readings" fallback subordinate
  to the counter (never declare stable while `listCounterCount` is known and larger),
  and probably to raise the 6-retry / 0.15s budget for the first visit of a session.

  **Do not fix blind.** This bug has been "fixed" before and returned, which is itself
  evidence that the previous fix addressed a trigger rather than the mechanism —
  the same failure mode as the `ModelRow.lua` capture above. Get the logging first.

---

### Orphaned context menu on panel close — fixed 2026-08-11

**Reported:** right-clicking the Models Browser's Locations header opens a context
menu; pressing Escape closes the panel but leaves the menu on screen. Doing the same
from Owned Pets' Grouped View closes both together.

**The interesting part is that the two panels' code is identical.** Both context menus
are byte-for-byte duplicates — same frame name `PSMContextMenuDropDown`, same
`PSM.state.contextDropDown`, so at runtime they are literally *the same frame*. Both
panels are built by `PanelManager:CreateBasePanel`, both register `escKeyframe`, both
get the same custom `OnKeyDown`.

So **Grouped View was not doing it right — it was getting lucky.** Two Escape
mechanisms are wired to every panel at once:

1. `PanelManager`'s own `OnKeyDown`, which hides the panel and then calls
   `SetPropagateKeyboardInput(false)`; and
2. `UISpecialFrames`, i.e. Blizzard's `CloseAllWindows()`, which *does* call
   `CloseDropDownMenus()`.

Whichever consumes the keypress first wins, and that depends on which frame holds
keyboard focus at the moment Escape is pressed. When our handler wins, the dropdown is
orphaned. Grouped View happened to fall through to Blizzard's path; the browser did
not. The same panel could go either way depending on what was clicked last.

**Fix:** `CloseDropDownMenus()` in `CreateBasePanel`'s `OnHide`. Deliberately *not* in
the Escape handler — the X button, the minimap toggle and `/psm` all hide a panel
without going near Escape, and would have stranded the menu just as easily. Hooking
`OnHide` covers every route out of a panel, including ones nobody has tried yet.

**The pattern, again:** the reported symptom pointed at one panel, but the difference
between "works" and "doesn't" turned out to be a race rather than a design. Fixing the
panel that was reported would have left the other one silently one focus-change away
from the same bug.

`.luacheckrc` gained `CloseDropDownMenus` under `read_globals` (baseline briefly 66,
back to 65).

#### Follow-up: there were *three* copies, and the unused one was the correct one

I wrote above that `ShowContextMenu` was duplicated in two files, and that
`info.notCheckable = item.notCheckable or true` (which can never be false) was
"harmless today because nothing wants a checkable item". Challenged on that — the NPC
view's Columns picker and the Owned Pets Families/Spec/Tamer filters are both
checkable — I went and checked instead of defending it.

**The claim was right but badly scoped, and checking it found something better.**
Neither of those menus goes near `ShowContextMenu`: the Columns picker is a custom
popout containing real `CheckButton`s, and the filter dropdowns are
`UIDropDownMenu_Initialize` on their own frames setting `info.checked`. So the addon
does have checkable menus; they just use different machinery. I should have said
"nothing that calls *these*", not "nothing".

What the check turned up: **a third copy — `PSM.Utils:ShowContextMenu` — shared, with
zero callers, and already containing the corrected line.**

```lua
info.notCheckable = item.notCheckable ~= false   -- Utils: correct, never called
info.notCheckable = item.notCheckable or true    -- both local copies: the live ones
```

Someone had already extracted the shared version *and* fixed the bug in it, and
neither caller adopted it. So the fix existed and had never shipped, sitting next to
two copies that hadn't got it.

**Done:** both local copies deleted; both files now call `PSM.Utils:ShowContextMenu`
through a one-line alias so the call sites read unchanged. One frame creator remains
repo-wide. No behaviour change today — no current caller passes `notCheckable = false`
— but the next one that does will now work.

**The lesson, which is the third instance of it this session:** an extracted helper
that nothing calls is not "available for later", it is dead code that silently
diverges from the copies still in use. Extract *and* migrate the callers, or don't
extract. Same failure as the `ModelRow.lua` capture (rule written, instances left) and
the recurring stable-collection bug (trigger fixed, mechanism left).

`PSM.Widgets.ContextMenu` is no longer needed — `PSM.Utils:ShowContextMenu` is the
single implementation. Moving it into the kit is cosmetic and can wait for B.

---

### A6 continued (2026-08-11) — TeamsPanel migrated

**`TeamsPanel.lua`: `GameTooltip:` 21 → 0, `CreateFrame` 10 → 0, `CreateFontString`
5 → 0, `CreateTexture` 3 → 0, `SetBackdrop({` 2 → 0, `ApplyElvUISkin` 2 → 0.**
luacheck 65/0, tests 37 passing.

**Five files in: `ApplyElvUISkin` 86 → 43, `CreateFrame` 193 → 110.**

Kit additions, both counted first: `Widgets.MaskTexture` (2 uses — the circular pet
portrait crop, kept separate from `Texture` because `CreateMaskTexture` is its own API
and its `SetTexture` takes wrap modes) and `Theme.BACKDROP.TOOLTIP_ROW` (2 uses —
`tileSize 16 / edgeSize 8 / insets 2`, shared with `GroupedView.lua`).

#### A live bug found by migrating a tooltip

`TeamsPanel.lua` had its own local `ShowTooltip(owner, anchor, text, xOff, yOff)` —
the fourth mini tooltip abstraction in the addon. One call site passed six arguments:

```lua
ShowTooltip(self, "ANCHOR_BOTTOM", "Visit a Stable Master to apply teams", 1, 0.5, 0)
```

The trailing `1, 0.5, 0` is plainly meant to be warning orange, as in
`GameTooltip:SetText(text, r, g, b)`. Against this signature it became `xOff = 1`,
`yOff = 0.5`, and a silently dropped third argument. **That tooltip has been nudged
half a pixel instead of coloured, for as long as the helper has existed.** Now stated
as `titleColor = Theme.COLOR.ORANGE`.

Nothing would have caught it: the argument count is legal Lua, luacheck cannot know
the intent, and the visual difference is a colour nobody had a reference for. It
surfaced only because converting to a *declarative* spec forces every value to be
named — `1, 0.5, 0` has to become either `titleColor` or `x`/`y`, and the moment you
have to choose, the mistake is obvious.

**Worth generalising: positional arguments hide type errors that named ones expose.**
Three of the four hand-rolled tooltip helpers in this addon took positional
`(owner, anchor, text, ...)`, and this is the one that got mixed up with a colour
triple. The kit's spec tables are more verbose per call and that verbosity is the
point.

The local `ShowTooltip`/`HideTooltip` pair is gone; call sites use
`PSM.Tooltip.Attach` or `PSM.Tooltip.Show`.

#### And a second one, same shape, found by testing the first

Reported immediately after: the Pet Teams button shows *"You have N saved team(s)"* at
the Stable Master but not on the Owned Pets panel. **Pre-existing** — the TeamsPanel
migration only touched the menu's button.

There are three Pet Teams buttons and three different tooltip implementations:

| Where | How | Works? |
|---|---|---|
| `Core.lua` (Stable Master) | `GameTooltip` spelled out by hand | yes |
| `TeamsPanel.lua` (menu) | now `PSM.Tooltip.Attach` | yes |
| `Panel.lua` (Owned Pets) | local `MakeButton(..., tooltip)` helper | **no** |

`Panel.lua`'s caller supplies `body` as a *function*, so the count is read at hover
time rather than at build time — sensible. But `MakeButton` did:

```lua
if tooltip.body then GameTooltip:AddLine(tooltip.body, 1, 1, 1) end
```

passing the function straight to `AddLine` as though it were a string. Truthy, so the
guard passes; not a string, so nothing renders. **That line has never appeared on this
panel.** Fixed by routing through `PSM.Tooltip.Attach`, which already takes a function
spec, and resolving `body` per hover whether it is a string or a function.

**This is the fifth hand-rolled tooltip renderer found in the addon, and the second in
two hours with a contract mismatch its author could not have seen.** The pattern is
consistent: each helper invents an untyped mini-contract (`text` here, `body` there,
positional `(owner, anchor, text, xOff, yOff)` in a third), and nothing checks that
callers and renderer agree — not Lua, not luacheck, not the eye, because the failure
mode is *absence* rather than error.

**The count is the argument.** Five implementations is not five styles; it is five
chances for a caller to be silently wrong, and two of them were. The single kit
tooltip is worth more than the lines it saves.

Deliberately fixed *only* the tooltip in `Panel.lua`, not the file's `CreateFrame`
and skin calls — a half-migrated file is harder to reason about than an unmigrated
one. `Panel.lua` gets its full pass in turn.

---

### A6 continued (2026-08-12) — AbilityBrowser migrated, `Tooltip` gains a data source

**`AbilityBrowser.lua`: `GameTooltip:` 16 → 0, `CreateFrame` 15 → 0, `CreateTexture`
9 → 0, `CreateFontString` 5 → 0, `ApplyElvUISkin` 5 → 0, `SetBackdrop({` 1 → 0.**
luacheck 65/0, tests 37 passing, option audit clean.

**Six files in: `ApplyElvUISkin` 42 → 37, `CreateFrame` 102 → 87, `CreateFontString`
33 → 28, `CreateTexture` 32 → 23.** (Counts exclude `UI/` itself, which is where the
construction now lives.)

#### The third copy of the tab bar

`CreatePillBar` was a hand-written `Widgets.Tab`: the same flat background, centred
label, and top/bottom accent rules shown only when active — plus its own
`SetActive(activeIdx)` loop respelling all five colour swaps. That makes **three**
independent copies of this widget found so far (ModelsFilters' filter tabs,
SpecialTames' pill bar, and now this), each written before the others existed.

`Widgets.Tab` absorbed it with no visual change, because all three were already
reading `PSM.Config.TAB` for their palette — the duplication was in the *construction*,
not the styling. 70 lines became 12, and `SetActive` is now one line delegating to the
widget's own `:SetActive(bool)`.

**Worth noting for the remaining files:** this one was not found by grepping for a
name. All three copies use different local variable names (`tab`, `pill`), different
parents, and different input handling (`OnMouseDown` vs `OnClick`). What made them the
same widget was their *shape*, which only became visible once two of them had been
migrated. Expect the same for whatever the remaining files duplicate.

#### Kit addition: `spellId` and `Tooltip.AddLines`

The ability icons show Blizzard's own spell tooltip with three extra "Available from"
lines appended. That could not go through the kit as it stood, so `PSM.Tooltip` gained
two things:

- **`spec.spellId`** — a third mutually exclusive content source alongside
  `title`/`lines` and `hyperlink`, calling `SetSpellByID`.
- **`Tooltip.AddLines(lines, tooltip)`** — appends to a tooltip that is *already*
  built, taking the same `lines` format as a spec. This exists for Blizzard's
  `TooltipDataProcessor` post-calls: when a spell resolves asynchronously, retail
  rebuilds the tooltip's lines internally and discards anything appended right after
  `SetSpellByID`, so the extra lines must be re-added on every rebuild.

The line-rendering loop is now shared between `Show` and `AddLines`, so a spec and a
post-call describe their lines identically. That is the whole reason to put `AddLines`
in the kit rather than leave the imperative block in the feature file — the *format*
is the thing worth having in one place; the post-call itself is inherently imperative
and stays where it is.

One deliberate exception to "no raw `GameTooltip` in feature files": the post-call's
`if tooltip == GameTooltip` identity check stays. It fires for every spell tooltip in
the game, including ones other frames own, and only `GameTooltip` is ours to append
to. It is a comparison, not a construction, and it is commented as such.

#### Two small correctness improvements, both from the options table

**The Apply handler is 70 lines**, and inlining it as `onClick = function() ... end`
inside an options table would have buried the declarative part under it. Extracted as
named `ApplyAbilityFilters(panel)` / `ToggleSelectAll(panel)` above `CreateFooter`,
which also gives the select-all logic a name for the first time.

**`hoveredAbilityEntry` is now claimed only when there is a spell.** The original set
it inside the `if entry.spellId` branch; a naive move into `Tooltip.Attach`'s `onEnter`
would have set it for entries without one, leaving it live while some *other* frame
raised a spell tooltip that would then have picked up our lines. Preserved exactly:
`AB.hoveredAbilityEntry = entry.spellId and entry or nil`.

#### Colours deliberately not unified

The card greys (`0.08/0.08/0.08` fill, `0.25/0.25/0.25` border and separator) are
*near misses* for `Theme.FILL.ROW` (`0.08/0.08/0.12`) and `Theme.FILL.SEPARATOR`
(`0.25/0.25/0.30`), which are a shade bluer. Folding them in would have restyled the
panel, so they are named in a local `CARD` table with a comment saying why. **This is
exactly the kind of drift A13 should reconcile** — two greys that differ by 0.02 in one
channel are not a design decision anyone made — but reconciling it is a look-and-feel
call, not part of centralising construction.

#### Found, not fixed (added to backlog below)

`PopulateAbilities` builds a **new scroll child, and with it every card and every
ability icon, on each call** — and it is called on every `OnTextChanged` in the search
box, i.e. once per keystroke. The old child is only `Hide()`n, because WoW frames
cannot be destroyed. Typing a five-letter search creates five full copies of the panel's
frames, permanently. Pre-existing and not a migration regression, but the migration is
what made it legible: the construction is now dense enough to see in one screen.

---

### A6 continued (2026-08-12) — ModelsPanel migrated, `Widgets.SectionHeader` added

**`ModelsPanel.lua`: `ApplyElvUISkin` 7 → 0, `CreateFrame` 12 → 1, `CreateTexture`
3 → 0, `CreateFontString` 2 → 0, `SetBackdrop({` 2 → 0.** luacheck 65/0, tests 37
passing, option audit clean across 192 widget calls.

**Seven files in: `ApplyElvUISkin` 37 → 30, `CreateFrame` 87 → 76, `CreateFontString`
28 → 26, `CreateTexture` 23 → 20, `SetBackdrop({` 14 → 12.**

The one remaining `CreateFrame` is `PSM.CreateFrame("Frame")` for the zone-event
listener — a parentless, invisible frame that exists only to hold `RegisterEvent`
handlers. It is not a widget and should not come from the widget kit;
`PSM.CreateFrame` is Core.lua's alias, which is also what makes it stubbable in the
headless tests. Left deliberately.

#### Kit addition: `Widgets.SectionHeader`

The "Show Only" title pill was a fifth appearance of the flat gold-on-dark bar. Unlike
the three tab bars, **it is not a tab** — nothing selects it, it has no inactive state,
and its label is left-aligned gold rather than centred white. So it got its own factory
rather than a `Widgets.Tab` locked to active, which would have meant undoing three of
Tab's decisions at the call site.

What settles it is `NPCRow.lua:252`, whose comment reads:

> `-- Golden/dark pill styling, matching the "Show Only" filter group header.`

**The author of the second copy wrote down that they were copying the first.** That is
the clearest signal a shape wants to be shared that this codebase has produced so far —
better evidence than any similarity metric, because it records intent rather than
inferring it. `SectionHeader` takes an `inset` for how far the accent rules stop short
of each end (2 for a pill inside a panel, 0 for one spanning an edge, which is what
NPCRow needs) and an optional `text`; omitting `text` leaves the bar empty for callers
that fill it themselves, as the NPC column header does with its sort buttons.

`NPCRow.lua` adopts it when that file migrates — it is next but one in the queue.

#### One behaviour change, needs an eye in game

**`pageJumpEditBox` was never ElvUI-skinned.** Every other edit box in the addon is,
and there is no comment explaining this one, so it reads as an omission rather than a
decision — but that is exactly what was said about the checkbox skin before the author
explained the reasoning behind it. `Widgets.EditBox` always skins, so it is skinned
now. Flagged for in-game verification rather than assumed correct.

#### A restraint worth recording

`SetNumeric`, `SetMaxLetters` and `SetJustifyH` are set on the returned frame rather
than added as `EditBox` options. `SetMaxLetters` has four callers and would arguably
earn one, but `Dialogs.lua` already established the post-hoc pattern when it migrated,
and three near-identical options added for one file is how an options table turns into
a second API surface for `CreateFrame`. **The kit exists to stop repetition, not to
wrap every setter.** They earn options when a third caller wants the same combination.

---

### A6 continued (2026-08-12) — NPCRow migrated, `SectionHeader` adopted by its second caller

**`NPCRow.lua`: `GameTooltip:` 15 → 0, `CreateFrame` 12 → 1, `CreateTexture` 6 → 0,
`CreateFontString` 5 → 0, `ApplyElvUISkin` 2 → 0, `SetBackdrop({` 1 → 0.**
luacheck 65/0, tests 37 passing, option audit clean across 209 widget calls.

**Eight files in: `ApplyElvUISkin` 28, `CreateFrame` 65, `CreateFontString` 21,
`CreateTexture` 14, `SetBackdrop({` 11** — from 86 / 193 at the start of A6.

The remaining `CreateFrame` is `ResizeDriver`, the file-scope OnUpdate ticker for
column dragging. Same call as ModelsPanel's event frame and left for the same reason:
no parent, nothing drawn, not a widget. Deliberately *raw* `CreateFrame` rather than
`PSM.CreateFrame` — that alias lives in core, and capturing a core function at browser
file scope is the exact pattern `ModelRow.lua` was fixed for.

#### The checkbox default, cashed in

This was the file the backlog flagged: its Columns picker used 16px boxes with 18px
row spacing, and would inherit the kit's 20px default. Both numbers moved together —
`PICKER_ROW_HEIGHT` is now 22, and the popout's height follows from it. The picker's
boxes now match every other checkbox in the addon, which was the point of giving
`CheckBox` a default at all.

**A hard-coded number became derived.** The hit rect that makes the label clickable was
`SetHitRectInsets(0, -114, 0, 0)` — a magic constant that silently encoded "16px box at
x=6 inside a 140px popout". It is now computed from those three values, so the next
size change cannot leave it stale. That is the more useful half of this change: the
literal was not wrong, it was *unanchored*, and unanchored literals are how a 16px box
survives a 20px decision.

#### `SectionHeader`'s second caller, one commit later

`CreateHeaderRow` dropped 20 lines of texture setup for one `Widgets.SectionHeader`
call with `inset = 0`. Worth noting the sequence: the factory was designed against this
call site while migrating a *different* file, purely on the strength of the comment
saying it was a copy — and adopting it here needed no changes to the factory. Designing
a shared widget against two known call sites rather than one is what made that hold.

#### Tooltips: two more hand-written renderers gone

The note-cell tooltip collapsed from a nine-line branch into a spec, because "title
plus an optional wrapped line" is what the spec format already says. The row tooltip
became a function spec, which also fixed a smaller staleness: it now reads
`ownedDisplayIdSet` at hover time instead of closing over the value that was current
when the row was last rendered. Rows outlive several render passes, so the captured
one could be from an earlier pass.

#### One more four-copy literal

`SetColorTexture(1, 0.82, 0, x)` appeared four times in the resize handle, differing
only in alpha — invisible at rest, half-lit on hover, solid while dragging. Now one
`SetHandleAlpha(handle, alpha)` reading `Theme.COLOR.GOLD`. Small, but it is the same
shape as everything else A6 has found: **the varying part was one number, and the
repetition was everything around it.**

#### Two follow-ups from in-game testing (2026-08-12)

**Fixed: the row tooltip had no width bound.** `GameTooltip` sizes itself to its widest
line, and an NPC with forty display IDs put them all on one — wider than the screen, and
still clipped at the end. `WrapJoin` now breaks the list into lines of at most 56
characters, so it grows downward, which is the direction a tooltip has room in. The
label shares the first line's budget, so short lists still fit on one line.

Bounded by **character count rather than pixels**, deliberately: a font string's width
is only measurable once realised, and for digits and commas the two track closely
enough that a pixel-exact answer would buy nothing. The alternative was `wrap = true`
on the line — the spec format already supports it — but that hands the width decision
to Blizzard's wrapping heuristics, which cannot be verified outside the client. The
author's call was to control it here rather than depend on that.

**Fixed: the Columns popout survived the panel being hidden.** Pressing Escape closed
the whole browser (correctly), but the popout kept its own shown state, so it was back
on screen the next time the browser opened. Hiding the panel hides the popout *as a
child* without clearing that state -- which is why it looked closed and wasn't.
`panel:HookScript("OnHide", ...)` now hides it explicitly.

**This is the second instance of the same shape**, after the context menu that survived
Escape on the Grouped View header (fixed by adding `CloseDropDownMenus()` to
`CreateBasePanel`'s OnHide). Different mechanisms -- Blizzard's global dropdown registry
versus one of our own frames -- so they do not share a fix today. But if a *third*
transient popout appears, `PanelManager` should grow a `panel.transientPopups` list that
`CreateBasePanel`'s OnHide walks, rather than every popout remembering to hook. Noted
rather than built: there is exactly one of our own popouts right now.

**Deliberately not done: Escape dismissing the popout before the panel.** That is the
platform convention and the author's instinct, but it needs the popout to take keyboard
focus, and Escape routing between a panel and its own child is precisely the case the
`Widgets.CloseOnEscape` comment warns about -- get the propagation wrong and Escape
stops closing the browser at all. Not worth the risk for a popout that already closes
on any click elsewhere, and untestable outside the client. Revisit if it starts to
grate.

**Removed: `PSM.ModelsPanel:ShowMagnificationPopup`,** 181 lines with zero callers.
See the backlog entry above; it was found while diagnosing the magnifier's height
behaviour, and removed first precisely because it would have misdirected that
investigation.

---

### A6 continued (2026-08-12) — Export migrated, and a dead-keybind bug

**`Export.lua`: `CreateFrame` 8 → 0, `ApplyElvUISkin` 6 → 0, `CreateFontString` 4 → 0,
`SetBackdrop({` 2 → 0.** Tests 37 passing, option audit clean across 219 widget calls.

**luacheck 65 → 64**, fully attributed: the checkbox loop no longer needs its index
(`for i, def` → `for _, def`), which removed an unused-loop-variable warning. One
warning, one cause. Baseline updated in `CLAUDE.md` and `CLAUDE.local.md`.

**Nine files in: `ApplyElvUISkin` 22, `CreateFrame` 57, `CreateFontString` 17,
`CreateTexture` 14, `SetBackdrop({` 9** — from 86 and 193 at the start of A6.

#### The Export dialog killed every keybind while it was open

```lua
frame:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" then self:Hide() end
end)
frame:EnableKeyboard(true)
```

No `SetPropagateKeyboardInput`. A frame with `EnableKeyboard(true)` consumes keyboard
input by default, so while the Export dialog was open **every keypress went to this
handler and no further** — the player's action bars, movement keys and every other
binding were dead until they closed it. Only Escape did anything, and Escape already
worked anyway via `UISpecialFrames`.

Replaced with `Widgets.CloseOnEscape(frame)`, which propagates everything except
Escape. The kit factory carries the explanation in its own comment, which is the
point: **this is the exact failure the factory was written to prevent, found in a file
that was written before it existed.** It is also the second bug of the session whose
symptom lives entirely outside the feature that causes it — nothing about a broken
keybind points at the CSV export dialog.

#### Checkbox sizing, second cash-in

These checkboxes passed no size at all, so they took `UICheckButtonTemplate`'s default
rather than the addon's 20px. They now match everything else, and the row pitch moved
with them.

`Theme.CONTROL.CHECKBOX_ROW = 22` is new, and `NPCRow`'s `PICKER_ROW_HEIGHT` (same
value, added last commit) now points at it. Two files needed "how far apart do stacked
checkboxes go", which is one question with one answer — and the whole reason the
picker's pitch went stale in the first place was that the box size and the pitch lived
in different places. They are adjacent in `Theme.CONTROL` now, with a comment saying
they move together.

`Widgets.CheckBox` also gained `labelFontSize` / `labelColor`, so a label can be styled
the two ways `Widgets.Label` already offers rather than only by font object. Two
call sites, two different needs — the same threshold every other kit addition met.

#### Noted, not acted on

`frame.checkboxes` is written and never read. So are `panel.pills`, `card.moreBtn`,
`card.expandArea` and `card.partialArea`, found earlier in this migration. Left alone
deliberately: they are stored handles on real children, they cost nothing at runtime,
and removing one of five is worse than removing none. If a sweep is ever wanted it
should be all of them at once, deliberately, not as a side effect of a migration.

#### Considered and dropped: an Export button on the Models Browser (2026-08-12)

Raised while Export was being migrated, and **declined by the author**: the generated
data tables ship with the addon, so users already have the raw data. A CSV export would
be a lossier copy of something they can already read.

Recorded because the investigation is worth not repeating. It would have been *small*
scoped to the filtered NPC list and *unwise* scoped to everything:

- The column set already exists — `NPCRow.COLUMNS` is the same `{key, label}` shape as
  Export's `ALL_COLUMNS`, and `panel.npcVisibleColumns` already tracks the user's choice.
  The NPC view is a table already; export is its natural operation. The display-ID view
  is a grid of 3D models and has no obvious row.
- `GenerateCSV` is hardwired to owned pets three ways (reads `PSM.state.stablePets`,
  sorts by `slotID`, special-cases `isExotic`/`isActive`/ability buckets). Generalising
  to `(rows, columns, valueFor)` is contained; the escaping and the dialog are already
  source-agnostic. `PSM.state.exportFrame` caches one frame and would need parameterising.
- **The volume is the reason to scope it.** `ModelsData` holds 7,700 records; at ~105
  characters a row that is **~800 KB** into a single multiline EditBox, against ~25 KB
  for the ~205-pet owned export. `SetText` and `HighlightText` at that size are not
  something to promise.

The design note worth keeping regardless: `PSM.Export` is in **core** and
`NPCRow.COLUMNS` is in the **browser**, so any such caller must pass its own columns.
That is the correct direction anyway, and it is the shape A3's public API will want.

---

### A6 continued (2026-08-12) — Filters migrated; the ElvUI global is now contained

**`Filters.lua`: `GameTooltip:` 18 → 0, `CreateFrame` 8 → 0, `ApplyElvUISkin` 3 → 0,
`CreateFontString` 2 → 0, `CreateTexture` 2 → 0, `SetBackdrop({` 1 → 0.**
Tests 37 passing, option audit clean across 223 widget calls.

**luacheck 64 → 63**, attributed: `shadowing upvalue 'isInverted'` — luacheck was
already pointing at the duplicated tri-state block inside the old click handler, and
that block is gone. **The lint had been describing the duplication all along**, in the
only vocabulary it has.

**Ten files in: `ApplyElvUISkin` 19, `CreateFrame` 49, `CreateFontString` 15,
`CreateTexture` 12, `SetBackdrop({` 8** — from 86 and 193 at the start of A6.

#### `Skin.lua`'s central rule was false until now

`Skin.lua` opens with *"Nothing outside this file may reference the ElvUI global."*
`Filters.lua` had a local `ApplyElvUIDropdownSkin` doing exactly that, and it was the
**only** violation left in the addon. The rule is now true, and checkable in one grep.

Worse, and only visible once both were in view: `Skin.lua` already had a `dropdown`
handler — `S:HandleDropDownBox(f)` — with **zero callers**, while every real dropdown
in the addon went through the local helper instead. The two do materially different
things: `HandleDropDownBox` restyles the frame but leaves the arrow button and text in
Blizzard's positions, whereas the local one repositions both, hides the three
nine-slice segments and builds its own backdrop. **Anyone who had written
`skin = "dropdown"` in good faith would have got a dropdown that matched nothing else
in the addon.** The shipped treatment is now the handler; the local is gone.

That is the fourth extracted-but-uncalled helper this migration has turned up
(`PSM.Utils:ShowContextMenu`, the unadopted context-menu fix,
`ModelsPanel:ShowMagnificationPopup`, and now this). The pattern is stable enough to
state plainly: **in this codebase, a helper with no callers is not neutral — it is a
divergent second answer waiting for someone to trust it.**

#### `Widgets.CheckBox:SetTriState` — the backlog item, cashed

Nine open-coded copies of "paint the three filter states" collapse into one method.
Five were in this file: initial paint, the click handler (which also re-created the
overlay texture it had just created), `UpdateFilterUI`'s two restore paths, and
`resetCheck` inside Reset Filters. Only the *rendering* moved; `NextTriState` — the
cycle order — stayed local, because what the states mean is this file's business.

#### Kept as literals, deliberately

The two `SetHitRectInsets(0, -100/-120, 0, 0)` values that widen each checkbox over its
label are still hand-tuned numbers, now named `labelHitWidth` at the call site with a
comment saying what they do. Deriving them from `label:GetStringWidth()` is tempting
and would be self-maintaining, but a font string's width is unreliable before the frame
is realised, and a silent 0 would make the labels unclickable with nothing to show for
it. Not worth trading a working constant for an untestable computation.

---

### A6 continued (2026-08-12) — RowManager migrated

**`RowManager.lua`: `GameTooltip:` 12 → 0, `CreateFrame` 6 → 1, `CreateTexture` 3 → 0,
`SetBackdrop({` 3 → 0, `CreateFontString` 1 → 0.** luacheck 63/0, tests 37 passing,
option audit clean across 232 widget calls.

The surviving `CreateFrame` is the rotation/movement `OnUpdate` ticker, now
`PSM.CreateFrame` — this file is in **core**, where the alias is the right call
because the headless tests can stub it. (The browser's equivalent, `NPCRow`'s
`ResizeDriver`, deliberately stays raw: reaching for a core alias at browser file
scope is the pattern `ModelRow.lua` was fixed for.)

**Eleven files in: `ApplyElvUISkin` 19, `CreateFrame` 44, `CreateFontString` 14,
`CreateTexture` 9, `SetBackdrop({` 5** — from 86 and 193 at the start of A6.

#### Ten positional parameters became a named table

```lua
MakeOverlayButton(parent, model, 16, "TOPRIGHT", "TOPRIGHT", -2, -2, tex, tex)
```

Four of those ten are anchor components, and a reader cannot check any argument
without counting commas. This is the same class as the `size`/`fontSize` crash early in
A6 — **positional arguments hide type errors that named ones expose** — and the four
call sites now read as option tables. The tooltip text moved into the call as well: it
used to be assigned afterwards as `btn.tooltipText`, a field invented purely so a
shared `OnEnter` could read it back.

The hover-brighten and the tooltip are now attached as one behaviour via
`Tooltip.Attach`'s `extra`, rather than two `SetScript("OnEnter")` calls where the
second silently wins.

#### One definition restored to one place

`UpdateBackgroundColor` re-spelled the row's entire backdrop when switching back to the
`"simple"` background type — a verbatim copy of what `CreateBackground` applies at
construction, including the border colour. Both now call `ApplyRowBackdrop`. **A
"restore the default" path that restates the default rather than calling it is a second
definition that only diverges when someone edits the first one.**

#### Kit addition: `Theme.BACKDROP.BORDER_ONLY`

A border with no fill, so the row's own background shows through. Two uses: the
duplicate/owned row indicator here, and `DragDrop.lua`'s drop-target outline, which
wants `overrides = { edgeSize = 12 }` when that file migrates.

#### The remaining work is larger than the original list said

The "densest first" list drawn up at the start of A6 was the **top ten** files, and it
is now exhausted. A full sweep of everything still holding construction:

| marks | file |
|---|---|
| 25 | `OwnedPets/GroupedView.lua` |
| 17 | `OwnedPets/GridView.lua` |
| 16 | `ModelsBrowser/ModelRow.lua` |
| 15 | `Core.lua` |
| 14 | `Shared/Minimap.lua` |
| 13 | `Shared/PanelManager.lua` |
| 13 | `Shared/OptionsPanel.lua` |
| 12 | `OwnedPets/Panel.lua` |
| 11 | `OwnedPets/DragDrop.lua` |
| 10 | `Shared/Menu.lua`, `Shared/Broker.lua` |
| 7 | `Shared/Utils.lua` |
| 6 | `OwnedPets/Row.lua` |
| 5 | `Shared/UI.lua` |
| 1 | six files, each an intentional ticker/event frame or a comment |

**`GroupedView` and `GridView` were never on the list at all** and are denser than
anything left on it. Recording this rather than quietly extending the list: the
original ordering was drawn from a partial survey, and "nine files left" was never
true. Thirteen files hold real work; `Shared/UI.lua` is the forwarding shim, which
goes when its last caller does.

---

## Post-A6: a user manual, and the discoverability problem behind it

**Decided 2026-08-12 (option 1): write it after A6 completes**, while the migration's
inventory is still fresh. Sequenced deliberately — splitting attention mid-migration is
where this project's real bugs have come from.

The README already answers *"what does it have"*. A manual answers *"how do I do X"*,
which is a different document. `index.html` at the repo root is already a standalone,
self-contained, build-free page, so a manual page is the second instance of a pattern
that works: servable from GitHub Pages, linkable from CurseForge.

### The inventory, captured now so it need not be rediscovered

Migrating a file means reading every affordance in it. These are the features found
along the way that a user has **no way to discover**, which is the actual problem — a
manual only half-solves it, because the users who would read one are largely the users
who would have found the features anyway.

| Feature | How a user would find it today |
|---|---|
| Reset view / magnify / add- and remove-from-team buttons | Only appear **on hover** over a model |
| Left-drag rotate, right-drag move, scroll to zoom | A tooltip, which requires hovering first |
| **Shift/Ctrl + drag to reorder a stable slot** | One extra tooltip line, only at the stable master |
| Exotic Only / Duplicates Only have a **third** (exclude) state | Click twice and notice the glyph changed |
| Right-click on the Grouped View and Locations headers | Nothing hints at it |
| Display ID → magnifier, Name → Wowhead, Zone → TomTom | Colour-coded as links, never labelled |
| NPC view column resizing | The drag handle is **alpha 0** until hovered |
| Note cells are editable | Click one and find out |
| Columns picker | Button only exists in NPC view |
| Pet Roulette / Special Tames / Ability Browser | Buttons exist; what they do does not follow from the label |

### `/psm help` does not exist — a cheap standalone win

`SlashCommands.lua` defines seven subcommands (`show`, `hide`, `menu`, `models`,
`options`, `roulette`, `teams`), and the dispatcher sends **any** unrecognised argument
to `PSM.Minimap:TogglePanel()`. So `/psm help` opens the panel and lists nothing. Adding
a help handler is ~15 lines, is independent of the manual and of A6, and is the highest
ratio of discoverability to effort available. Do it whenever; it blocks nothing.

**Worth considering alongside the manual, not instead of it:** in-UI hints fix
discoverability for everyone, whereas a manual fixes it for the people who go looking.

---

### A6 continued (2026-08-12) — GroupedView migrated; half the compat shim retired

**`GroupedView.lua`: `GameTooltip:` 22 → 0, `CreateFrame` 2 → 0, `CreateFontString`
2 → 0, `ApplyElvUISkin` 1 → 0, `ElvUITexture` 3 → 0, `SetBackdrop({` 1 → 0.**
luacheck 63/0, tests 37 passing, option audit clean across 236 widget calls.

**Twelve files in: `ApplyElvUISkin` 17, `CreateFrame` 42, `CreateFontString` 12,
`CreateTexture` 9, `SetBackdrop({` 4** — from 86 and 193 at the start of A6.

**`PSM.UI.ElvUITexture` is deleted.** Its last caller was in this file, so half the
compatibility shim in `Shared/UI.lua` is gone — the first piece of the pre-kit API to
actually retire rather than merely stop growing. `ApplyElvUISkin` stays until its own
17 callers are done; the shim now says how to check.

#### A skin-ordering constraint that had to be preserved, not tidied

The group header's expand button set its size and anchor, applied the ElvUI skin, set
its textures, and **then set size and anchor again**. That reads like an accident. It
is not: ElvUI's `HandleButton` strips textures and resets geometry, so anything applied
before the skin is discarded. The repetition was the fix.

This is the opposite of the `CheckBox` case, where skinning had to happen *before* the
caller drew its tri-state overlay. Two widgets, two opposite orderings, both real:

- **CheckBox** — kit skins *before returning*, so a caller's later overlay survives.
- **collapsebutton** — kit skins *last*, so the caller's later textures survive.

`Widgets.IconButton` applies `skin` at the end, which is what this call site needs, so
the ordering still holds. The re-application is kept verbatim with a comment explaining
it — **a workaround that outlives its explanation looks exactly like dead code**, and
this one nearly went that way.

#### A vestige of an earlier finding

```lua
local function ShowContextMenu(menuList)
    PSM.Utils:ShowContextMenu(menuList)
end
```

A pure forwarder with three callers, left behind when the two verbatim context-menu
copies were deleted earlier in A6. Removed; the three call sites now name
`PSM.Utils:ShowContextMenu` directly. Harmless on its own, but it is the shape that
made the original duplication invisible — a local name that looks like a local
implementation.

#### Tooltip moved above its caller

`PetTooltipSpec` had to move *above* `CreateModelRow`, not merely be extracted:
a Lua `local` declared after a function body is not in that body's scope, so the
call would have silently resolved to a nil global at hover time. Caught by the
editor's undefined-global warning rather than by testing, which is the argument for
keeping that warning class enabled.

#### Bug found in testing: cross-group drops ignored the drop indicator

Reported 2026-08-12: dragging a pet into a *different* group highlights the pet you are
hovering — a green drop indicator down its left edge — but the pet always lands at the
**end** of the destination group. Changing the sort to Unsorted made no difference,
correctly ruling out sorting.

`DragDrop:CompleteDrop` had two paths:

```lua
if sameGroup then
    ...compute tgtPos from the highlighted pet, adjust, reorder...
else
    petGroups:MovePetToGroup(srcGUID, tgtGroup, nil)   -- <- position
end
```

**`MovePetToGroup(petGUID, targetGroupId, targetPosition)` has always taken a
position**, and `InsertAt` already clamps it and treats nil as append. The cross-group
path passed an explicit `nil` and never computed one — the same-group path did all that
work and the other branch simply never borrowed it.

The explicit `nil` is the tell. **A parameter passed as a literal nil is a capability
someone knew about and declined to use** — it reads as deliberate, so nobody revisits it.

Fixed by computing the position once, above the branch, and giving it to both:

- **Drop on a pet** → insert at that pet's index. Cross-group needs no index
  adjustment, because removing the source from a *different* group does not shift this
  group's positions; the same-group path still adjusts.
- **Drop on a group header** → no target pet, so the position stays nil and the pet
  appends. That is now a coherent distinction rather than an accident: the header
  highlights as a whole, and appending is what a whole-group highlight should mean.

Both branches now share `StoredOrderForGroup`, which seeds visible-but-untracked pets
before measuring. Worth recording *why* that seeding exists: a pet is implicitly
ungrouped until something files it, so the ungrouped list can be missing pets that are
plainly on screen — and an index measured against a partial list lands in the wrong
place. Named groups always track their members, so the pass finds nothing there.

**A latent crash went with it.** The old same-group guard checked only that a target
*pet* existed, not that it was in storage. A target that was somehow untracked gave
`tgtPos = nil` and then evaluated `srcPos < nil` — an error, not a failed drop. The
guard now checks the position it is about to use.

#### Follow-up: the group-header highlight was nearly invisible

Reported immediately after the fix above: dropping onto a group header worked, but the
target was so faint the author first assumed there was no highlight at all.

`SetRowColor` had a header branch that set **only the border colour**, and passed the
fill's alpha into it -- so the entire feedback for "this whole group is the target" was
a 0.4-alpha green wash over an 8px tooltip edge. Pet rows, by contrast, tint their whole
fill *and* get a solid 3px indicator bar.

The header now takes the tint on its **fill** at the shared 0.4 alpha, and its border at
**full opacity** to outline the target. That makes it read as at least as strong as a
row highlight, which is right -- it is the larger, coarser target of the two.

Two things fell out while fixing it:

- **`ResetRowColor` hard-coded GroupedView's header palette** (`0.15/0.15/0.15` fill,
  `0.5/0.5/0.5` border) -- a copy of literals living in another file, in another module,
  with nothing keeping the two in step. Headers now save and restore their own colours
  through the same path every other row uses.
- Adding the border to the saved set meant finding **three** hand-written
  restore-and-clear sites. They are one `RestoreRowColors` helper now, so the next
  addition to the saved set is one edit rather than three.

---

### A6 continued (2026-08-13) — GridView, and four copies of the same pet

`GridView.lua` scored 17 on the density survey and was next in line. The survey
metric turned out to be hiding the shape of the file: **all 17 were `GameTooltip:`
and none were construction.** RowManager's migration had already taken care of its
widgets, so the remaining work was the other half of the kit, `PSM.Tooltip`.

That is worth keeping in mind for the files still on the list — the score says *how
much a file does by hand*, not *what kind of thing it does by hand*. Read before
planning.

#### The actual finding: the pet tooltip existed four times

Chasing GridView's tooltip turned up the same content spread across four files, all
written independently, all drifted:

| Copy | Buckets | Tooltip |
|---|---|---|
| `OwnedPets/GridView.lua` | `ABILITY_TAGS` + `ABILITY_COLORS` (two parallel tables) | hand-written, 58 lines |
| `OwnedPets/GroupedView.lua` | `ABILITY_BUCKETS` | migrated last session, 66 lines |
| `OwnedPets/Row.lua` | `ABILITY_GROUPS` | renders inline text, not a tooltip |
| `OwnedPets/TeamsPanel.lua` | `cats` | already on `PSM.Tooltip`, own spec |

The four bucket tables were meant to be the same four rows of data. They were not:

- `[Spec]` was `FFD700` gold in three copies and `FFFF00` yellow in the fourth
- `[Other]` was `AAAAAA` in three and `ABABAB` in the fourth
- one copy carried a **stray leading space** that indented `[Pet]` and nothing else

Nobody decided any of that. It is just what four copies of a table become, and it is
the clearest example yet of the pattern this migration keeps finding: *duplication
does not stay duplicated — it becomes divergence, and then the divergence looks
deliberate.* A reader seeing yellow `[Spec]` in the teams panel has no way to know it
was a typo rather than a choice.

**New file `OwnedPets/PetTooltip.lua`** (TOC before `Panel.lua`) now owns
`ABILITY_BUCKETS`, `IsBucketed`, and `Spec(pet, hints)`. The `hints` argument is the
one part that genuinely differs per view — grouped view has sort-dependent reordering
to explain, grid view does not — so it is a parameter and everything above it is
shared. All four call sites use it.

#### A real bug the copies were hiding

Both tooltip copies wrote the level line as:

```lua
Add(string.format("Level: %d%s", pet.level, levelColor), Theme.COLOR.WHITE)
```

The colour escape lands **after** the number, where it colours nothing and leaves `|r`
unclosed. Level colouring has therefore never worked in either view. The shared
version wraps the number — `Level: |cFF00FF0025|r` — so levels are now green/yellow/grey
as intended. **User-visible change, flagged for testing.**

#### GridView was silently discarding RowManager's model handlers

`RowManager.SetupModelInteraction` attaches a tooltip *and* a hover-button pair to
every model. GridView then called `m:SetScript("OnEnter", ...)`, which replaces both.
Replacing the tooltip is deliberate and correct — the rotate/zoom hints are already the
last section of the pet tooltip — but the button half was collateral, so GridView
re-implemented it, and so did GroupedView.

Both hand-written copies **hardcoded the four button fields** instead of walking
`model.hoverButtons`, which RowManager populates. A fifth overlay button would have
appeared in some views and not others, and nothing would have said why.

`ShowHoverButtons` / `HideHoverButtons` are public on RowManager now, used by
RowManager itself and by both views. One definition, and `hoverButtons` is the only
list.

#### Two more single-definition wins

- **`RowManager.MODEL_HINTS`** — "Left-click and drag to rotate…" was written out in
  full **four** times (RowManager, GroupedView, GridView, PopUpManager). It lives with
  the code that installs the handlers it describes, so changing the interaction puts
  the text in front of you.
- **A dead hide-then-show** in GridView's button code:
  ```lua
  HideIfExists(model.resetButton)  -- intentional: show via :Show() below
  if model.resetButton then model.resetButton:Show() end
  ```
  Nothing hooks the button's `OnHide`, so this was a no-op. The comment is the tell —
  it does not explain a reason, it reassures the reader that the odd thing is fine.
  *A comment that defends code instead of explaining it is usually guarding a leftover.*

#### Result

`GridView.lua`: `GameTooltip:` 17 → 0, and 58 lines of tooltip became 3.
`GroupedView.lua` lost a further 66 lines to the shared spec.
Net across the change: **−181 lines, +118** (the new shared module).

Repo-wide: `ApplyElvUISkin` **17** call sites, `CreateFrame` **42** (excluding the kit).
luacheck **63 / 0**, tests **37 passing**, option audit clean across **211** call sites.

#### The option audit was wrong before it was right (again)

Rebuilt from scratch this session, it reported seven unknown options in
`PopUpManager.lua` — on lines that were **prose comments**. For a
`Widgets.CloseButton(parent)` with no option table, it took `src.find("{", ...)` and
found the next brace *hundreds of lines later*, then read that unrelated table's keys.
Now bounded to the call's own parentheses.

Second time a fresh scanner has produced confident false positives (the first was
`local` declarations inside inline `function` bodies). Standing lesson: **when a static
check reports a surprise, check the checker before the code.** Both times the code was
fine and the tool was wrong.

The count also moved 236 → 211 with no calls removed: the earlier figure included
**25 internal calls inside `Widgets.lua` itself**, which are the factories' own use of
each other, not call sites to audit. 236 − 25 = 211 exactly.

#### Follow-up: one tooltip for every owned pet, and the level field split in two

Two requests after testing the above. The first was consistency: the teams-panel
tooltip looked different from the owned-pets ones in many ways, and it should differ
only in the trailing instructions.

It now doesn't. `PetTooltip.Spec` took an `opts` table in place of the bare `hints`
argument, gaining `opts.slotLabel` so the teams panel can keep its own framing (a team
position, with 6 as the companion) while everything above the hints comes from one
builder. Verified through lupa that the line bodies are **byte-identical** across grid,
grouped and teams for the same pet, differing only in the title's slot label and the
tail. The teams panel also picked up DisplayID, level and owner lines it never had, and
lost a gold title and a separate `Exotic` line that nothing else used.

Anchoring stayed with the caller — the teams panel patches `spec.x/y` after building —
because the shared module is about *content*, and where a tooltip sits is a property of
the frame it hangs off.

##### The level field was two fields

The second report: the level line was missing for active slots 1-5. Worth stating what
the investigation actually found, because the first read was wrong.

Initial grep said `pet.level` is **never written anywhere** — only `petLevel` is, in
`ProcessPetInfo`. That implied the line had never rendered for anybody, which
contradicted the report. It was contradicted because there are **two collection paths
building two different record shapes**:

| Path | How the record is built | Has `level` | Has `petLevel` |
|---|---|---|---|
| `CollectStabledPets` | `DeepCopy` of Blizzard's record | yes (passthrough) | no |
| `ProcessPetInfo` (active 1-5) | built field by field, whitelist | no (renamed) | yes |

Each consumer had then quietly picked the key that worked for the pets it usually saw:

- the **tooltip** read `level` → worked for stabled pets, blank for slots 1-5 (reported)
- **Export** read `petLevel` → worked for slots 1-5, **blank for every stabled pet**

The second one had not been noticed and would have been read as missing data rather than
a bug. Both paths normalise to `level` now; Export's column key changed with them, and
its CSV header is unaffected because the header writes `col.label`, not the key.

*The lesson is not about levels.* Two constructors for one record type is the actual
defect — a whitelist build and a deep copy, with nothing asserting they agree. The
rename was invisible precisely because each consumer was only ever tested against the
half of the data that worked. Noted in CLAUDE.md: **when adding a field, add it to both
paths.**

##### On dropping the feature instead

The author asked whether to give up pet level altogether, expecting a can of worms. It
wasn't one — the data was already collected correctly on both paths and the only defect
was the name it was stored under. Dropping the feature would have removed a working
column from Export as well, to avoid a one-word fix. Worth remembering as a general
shape: *"this is broken in a way that suggests deeper trouble" is a hypothesis, and it
is cheap to check before acting on it.*

##### Third instance: the team slot record

Reported next: the teams tooltip still started thinner than the owned-pets one — slot,
name, display ID, family, spec, and then straight to abilities. No "Owned by", no level.

Both tooltips now come from the same builder, so this could not be a formatting
difference. `PetTooltip.Spec` only emits a line when the field is present, which made
the report a **data** finding rather than a display one: team slots genuinely do not
carry `tamer` or `level`.

They don't because a team slot is written by a **third** hand-written whitelist:

| Site | Builds from |
|---|---|
| `TeamsData.lua:98` | a live `C_StableInfo` record |
| `Dialogs.lua:346` | an already-processed PSM pet |
| `Dialogs.lua:616` | an already-processed PSM pet |

All three had independently settled on the same nine fields, and all three omitted
`level` and `tamer`. The two in `Dialogs` were copying *from a complete pet record* and
dropping two fields they already held — nothing was unavailable, the list simply never
mentioned them.

`PSM.Teams:SlotRecord(pet)` is the single definition now, accepting either input shape
(`pet.familyName or pet.family.name`, `pet.abilities or ExtractPetAbilities(pet)`). A
pet added to a team from another character keeps its own `tamer`; capturing your own
slots fills it with the current character, since only that character can capture them.

**Three different shapes for "a pet" have now produced three user-visible bugs in a
row** — the level rename, the Export blank column, and this. Each was invisible because
each consumer was only ever exercised against the subset of data that happened to work.
The general form: *when the same concept has more than one constructor, the constructors
do not diverge loudly — they diverge as absent fields, and an absent field reads as
"this pet doesn't have one" rather than "this code forgot".*

Recorded in CLAUDE.md as a standing check: counting record builders is cheap, and adding
a field to a pet means grepping for every place a pet-shaped table is constructed.

**Note for testing:** teams saved before this change still lack the two fields, so their
tooltips stay thin until the team is re-captured or the pet re-added. The tooltip
degrades line by line rather than erroring, so nothing breaks in the meantime.

#### The stable-frame Teams buttons vanished — a silent early return

Reported mid-session: the Save Team / Teams List buttons on Blizzard's stable frame were
gone. They came back after a relog, but **survived a /reload while broken**, which is
the detail that matters.

The first two hypotheses were both wrong, and worth recording because the diagnostic
that settled it cost one line:

1. *A render error skipping the creation call.* `CreateSaveTeamButtonOnStable` runs 14
   lines after `PSM.UI:RenderPanel()` in the same handler, so a throw would skip it.
2. *Blizzard renamed the anchor button in a patch.*

An in-game macro reporting three facts at once — frame present, anchor present, our
button present — returned:

```
StableFrame OK    ANCHOR MISSING    our button exists
```

Which fits **neither** hypothesis, and is more informative than either: the anchor
(`StableFrame.PetSelectButton`) is *transient*. It was absent at that moment while our
buttons, created earlier, were on screen. So it is created lazily or conditionally by
Blizzard rather than living for the life of the frame.

The code treated it as a hard requirement:

```lua
if not putInStableButton then return end   -- no message, no log, nothing
```

Lose that race on `PET_STABLE_SHOW` and both buttons never exist for the rest of the
session — and a `/reload` does not help, because the next show loses it too. **A silent
early return in event-driven code is indistinguishable from the feature not existing.**

Three fixes, one bug:

- **The anchor is optional.** Buttons anchor to it when present and to the frame's
  bottom-right corner when not, which is roughly where it sits anyway.
- **Position is recomputed on every show** rather than fixed at creation, so a
  late-appearing anchor is picked up without the buttons vanishing to wait for it.
- **Creation is idempotent.** It previously built two new frames *per stable visit*,
  each reusing the same global name, and added another `HookScript("OnHide")` that can
  never be removed — a leak that grew with session length. Now it reuses what is there.

A fourth thing fell out: the creation path restated the enable/disable rules that
`UpdateSaveTeamButtonState` already owns. Two copies of one rule; it calls the function
now.

##### The same bug class, one file over

`PSM.StableFrame` is captured at Core.lua **file scope**, in a "WOW API REFERENCES"
block, and never re-resolved. `Blizzard_StableUI` is load-on-demand, so on a session
where it had not loaded by the time Core.lua ran, that snapshot is `nil` **forever** —
and `CollectStablePets` bails with "stable frame not found" every time.

It works today only because the frame happens to exist at load in this client. It is a
reference captured once, at a moment when the thing it names may not exist yet — exactly
the shape of the bug above, and a plausible contributor to a "one-off manifestation"
that a relog clears. Now re-resolved at the top of `CollectAndRender`, where the frame
is guaranteed to be up.

**Standing lesson: `X = SomeGlobal` at file scope is a snapshot, not a reference.** For
anything load-on-demand it is a bug waiting for the right login order. Worth a deliberate
sweep — this is the second capture-at-load defect found this session, after the
cross-addon file-scope captures already on the backlog.

### Capture sweep (2026-08-13) — every `X = SomeGlobal` at file scope

Prompted by the stable-button bug, which was one instance of a class. Scanned both
addons for file-scope assignments whose right-hand side is a bare identifier or dotted
path: **82 matches**, of which almost all are benign — `local PSM = _G.PSM`, or a file
aliasing a table it created two lines earlier, or a module publishing its own constants
onto a PSM table (an export, not a capture).

The real surface was one block: Core.lua's **WOW API REFERENCES**, 17 aliases.

The distinction that matters is not "is this a global" but **"can this global appear
after Core.lua runs?"** For the base API the answer is no, and an alias is harmless. For
anything shipped by a load-on-demand Blizzard addon the answer is yes, and the alias
freezes the answer at the least reliable moment of the session.

| Alias | Source | Verdict |
|---|---|---|
| `StableFrame` | `Blizzard_StableUI` (LoD) | **removed** — the bug already found |
| `UIDropDownMenu_Initialize/AddButton/CreateInfo`, `ToggleDropDownMenu` | `Blizzard_UIDropDownMenu` (separate addon) | **removed** — 4 call sites, all in Minimap |
| `UIDropDownMenu_SetWidth`, `UIDropDownMenu_SetText`, `EasyMenu` | same | **removed** — *zero callers* |
| `CreateFrame`, `C_Timer`, `C_StableInfo`, `C_Spell`, `UIParent`, `GameTooltip`, `GetCursorPosition`, `hooksecurefunc` | base API | kept |
| `GetSpellInfo` | legacy base API | kept — see below |

Three of the seventeen had **no callers at all**, which is the usual sign: an
indirection layer that was started and never finished. Counting told the story — for
nearly every name, both forms were in use (`GameTooltip` 1 via `PSM.` against 72 raw;
`StableFrame` 14 against 52). The aliases were never the convention, only an option, and
the option was the fragile one.

**`PSM.StableFrame` became `PSM.GetStableFrame()`.** The first fix put a re-resolve at
the top of `CollectAndRender`, which was wrong: there turned out to be **eight** entry
points into pet collection (DragDrop, TeamsData, TeamsPanel, Minimap, UI ×2, Events ×2),
so no single handler can be trusted to have refreshed a cached field first. A function
that looks the global up on every call has no such ordering requirement. *When a fix
depends on "this runs first", check how many callers there actually are.*

**`PSM.GetSpellInfo` stays, and stays nil.** The editor flags it as an undefined global,
which looked like another instance — but it is the legacy half of
`Utils:GetSpellNameCompat`, which prefers `C_Spell.GetSpellName` and falls back only if
the old global exists. Nil is the correct answer on a modern client, and unlike an LoD
addon this global never appears later. Commented in place, because it looks exactly like
a bug to anyone who greps for it. *A deliberate nil needs a note, or someone will fix it.*

Post-sweep scan: **no file-scope captures of non-base globals remain in either addon.**
The cross-addon capture item from the backlog is also confirmed clean — no browser file
aliases `PSM.Widgets`/`Tooltip`/`Theme`/`Skin`/`Config`/`Utils` at file scope.

### A6 continued (2026-08-13) — ModelRow, and a tooltip rebuilt per row per render

`ModelRow.lua` scored 16, of which **14 were `GameTooltip:`** — the same shape as
GridView, and confirmation that the density metric measures volume of hand-rolling
rather than kind. One `CreateFontString`, one `CreateTexture`, no `CreateFrame`.

Two structural findings, both invisible in the score:

**The row had two OnEnter handlers, and one was dead.** `CreateModelRow` installed a
thin tooltip (display ID, family) and `UpdateItemRow` installed the real one — which
*replaced* it. Since every visible row is updated, the placeholder never ran except on a
row that had no `displayId`, where its first line was `if not self.displayId then
return end`. So its entire observable behaviour was "do nothing", written as fifteen
lines that look like a feature. A reader has no way to tell which of the two tooltips is
the real one without tracing call order.

**The real tooltip was rebuilt on every row update.** `row:SetScript("OnEnter",
function(self) ... end)` inside `UpdateItemRow` allocates a fresh closure capturing
`nameStr`, `item`, `npcs` and `totalNpcs` — per row, per render, for the life of the
browser. Same family as the AbilityBrowser per-keystroke rebuild already on the backlog.

Both fixed by the same change, which is the point: the tooltip is attached **once** in
`CreateModelRow` as a function spec that reads `row.tooltipData`, and `UpdateItemRow`
refreshes that table instead of rewiring the handler. The nil-return for an unfilled row
now suppresses the tooltip through the kit, which is exactly what the dead placeholder
was hand-writing.

Verified through lupa against three shapes — unfilled row (suppressed), two NPCs with a
user note on the second (marker on the right one, both lines wrapped), and no NPCs (the
section skipped entirely, "Family: Unknown" fallback). Output matches the old handler
line for line.

Result: `ModelRow.lua` at zero across all six patterns. **Fourteen files migrated.**
Repo-wide `ApplyElvUISkin` 17, `CreateFrame` 42 (excluding the kit); luacheck 63/0,
37 tests, option audit clean across 215 call sites.

*Standing note reinforced:* a handler installed in an update function is a handler
installed N times. If the data changes but the behaviour does not, put the data on the
frame and attach once.

### A6 continued (2026-08-13) — Core.lua, and three places that lied about teams

`Core.lua` scored 15 and **every one was the stable-frame button code** — the same code
rewritten two passes earlier for the vanishing-buttons bug, kept surgical then so it
could be reviewed against a defect that could not be reproduced on demand. This is the
other half.

Both buttons come from `Widgets.Button` now, which covers template, text, font object,
strata, level, click handler, tooltip *and* skin, so 2 `CreateFrame`, 11 `GameTooltip:`
and both `ApplyElvUISkin` calls go at once.

**The ordering trap this file sets.** Core.lua is TOC line 15; `UI/Theme.lua` is 23 and
`UI/Widgets.lua` is 26, so `PSM.Widgets` and `PSM.Theme` **do not exist when this file
parses**. They are read inside `CreateSaveTeamButtonOnStable`, which runs when a stable
opens. This is the first *core* file where the browser addon's read-inside-the-function
rule actually bites, and it argues for the rule being universal: the correct habit should
not depend on knowing the TOC line number of the file you are editing.

#### The author's objection, and what it uncovered

Review feedback on the migrated tooltip: *"someone in the future may interpret that the
team can only be saved at the stable, because only there we have the explicit button,
and if you add a branch for making it inactive outside the stable, they will lean more
towards believing that — which is not true."*

That is a sharper standard than "is this branch reachable". A dead branch is not merely
waste; **it is documentation, and this one documented something false.** Three things
were teaching it:

| Where | What it claimed |
|---|---|
| Save Team tooltip else-branch | "Visit a Stable Master to save teams" |
| `PSM:UpdateSaveTeamButtonState` | disabled + 50% alpha outside the stable |
| `PSM.UI:UpdateSaveTeamButtonState` | same rule, for a panel button |

The third is the find. It disabled `PSM.state.panel.saveTeamButton` — **a field created
nowhere in the codebase**. Never called, guarding a button that does not exist, left over
from a panel affordance that was removed. Deleted.

The first two are unreachable for a concrete reason: `PET_STABLE_CLOSED` hides both
buttons *before* clearing `isStableOpen`, and the buttons are created on
`PET_STABLE_SHOW` when it is already true. The button is never visible while the flag is
false. Tooltip branch removed; the disable branch removed with a note saying what must
not grow back.

The `onClick` guard was **kept**, and relabelled as a guard rather than UI: if the
button's visibility ever changes, capturing slots without a stable would silently save an
empty team. Cheap insurance is not the same as a second answer.

#### What is actually true about saving teams

Worth recording, because the code implied the opposite and the author had to say it out
loud:

- `Teams:SaveTeam(name, slots)` / `Teams:UpdateTeam(id, slots)` fall back to
  `GetCurrentSlots()` **only when `slots` is nil**. That fallback reads `C_StableInfo`,
  which is the entire stable requirement.
- The stable-frame button omits `slots` deliberately — its whole purpose is capturing the
  live layout for players who arrange pets in Blizzard's own UI.
- Every other route (Teams panel, `Shared/Dialogs.lua`) passes `slots` explicitly, built
  by `Teams:SlotRecord`, and works anywhere.
- Persistence is `PetStableManagementDB.characters[<char>].teams` via `CharData()`,
  **mutated in place**. There is no write step, which is why nothing outside the stable
  needs a Save button at all.
- Only *applying* a team requires a stable visit.

*Lesson:* an unreachable branch that renders text is worse than dead code, because a
reader treats shipped strings as evidence of real states. Reachability is the minimum
test; "would a stranger infer something false from this" is the real one.

Result: **fifteen files migrated**, Core.lua at zero across all six patterns.

### A6 continued (2026-08-13) — Minimap and Broker, and a LoadOnDemand gate that never opened

`Minimap.lua` scored 14: a button, two textures, and a tooltip. The tooltip was the
part that mattered.

**Broker carried the same tooltip with a real bug.** LibDBIcon builds the minimap button
*from* the Broker data object, so they are one affordance in two hosts and must list the
same clicks. Two copies existed, and they had drifted: Broker advertised the Models
Browser unconditionally while Minimap gated it on `IsBrowserAvailable()` — the documented
LoadOnDemand fix, which Broker never received. One spec now, in Minimap.lua.

**A third context-menu implementation.** `PSM.Utils:ShowContextMenu` was introduced as
the single implementation and two verbatim copies were removed at the time.
`Minimap:ShowContextMenu` survived because it *looked* different: it built its own
dropdown frame rather than repeating the initialiser, and rebuilt that frame under a
fixed global name on every call.

It also had **zero callers** — `OnClick` spends all four combinations on panels, so
nothing could open it — and every entry was reachable anyway (`/psm models`,
`/psm roulette`, `/psm hide`, plus right-click). Deleted. Notably it was found only when
the author corrected a wrong test instruction; a duplication scan had slid past it twice.
*Unreachable code is not found by grepping for duplication. It is found by asking who
calls it.*

Kit additions, both justified by two callers rather than one: `Tooltip` gained
`point = { "TOPLEFT", "BOTTOMLEFT" }` (the frame is always the owner, so specs stay plain
tables), and `Theme.COLOR.HINT` gave the launcher tooltip's hint blue a home instead of a
literal in two files.

#### The LoadOnDemand gate that answered "no" to everything

Reported while testing: the minimap tooltip offered three clicks on a fresh login and
four only after the browser had been opened once.

`IsBrowserAvailable()` is documented as "present and enabled", not "loaded" — precisely
the distinction needed. It was implemented as `GetAddOnInfo(...)` → `loadable`, and
**`loadable` does not mean "can be loaded"**. For a LoadOnDemand addon that is present
and enabled but not yet parsed, the client returns `loadable = false` with
`reason = "DEMAND_LOADED"` — the dormant state, not a failure.

So the function answered "not available" for the entire normal case. Every affordance
gated on it hid itself until something *else* had loaded the browser: the minimap
tooltip, and `PSM.Menu`'s browser entries. The check now tests `reason == "DEMAND_LOADED"`
explicitly — the same token vocabulary `FAILURE_HINT` in that file was already keyed on,
so the answer was sitting three lines above the bug.

*Lesson:* a boolean from someone else's API is worth reading the docs for even when its
name reads like a plain English answer. `loadable` is a status field, not a predicate.

**Pinned with `Tests/spec/loader_spec.lua`** — the states the AddOns list can produce
(dormant, loaded, disabled, missing, dep-disabled, dep-missing, plain-enabled), each with
the exact `GetAddOnInfo` returns the client gives. Verified it catches the original bug:
restoring the old logic turns exactly the two right tests red. 46 passing, up from 38.

### A6 continued (2026-08-13) — PanelManager, and three regressions I caused

`PanelManager.lua` scored 13 and reached zero, but the migration itself was the small
part. Three bugs came out of it, two of them mine, and the pattern connecting them is
worth more than the file.

#### The Escape regression: verifying presence instead of effect

Every panel passed an `escKeyframe` for `UISpecialFrames`, *and* had a hand-written
`EnableKeyboard(true)` + `OnKeyDown`. Two owners for one key. I removed the hand-written
half on the reasoning that Blizzard's registration already covered it — having checked
that all five panels set `escKeyframe`, and nothing else.

The names never resolved:

| Frame's actual global name | Registered in UISpecialFrames |
|---|---|
| `panel` | `PetStableManagementPanel` |
| `teamsPanel` | `PSMTeamsPanel` |
| `modelsPanel` | `PetStableManagementModelsPanel` |
| `abilityBrowser` | `PetStableManagementAbilityBrowser` |
| `specialTames` | `PetStableManagementSpecialTames` |

`_G[name]` was nil for all five. **UISpecialFrames had never worked**; the hand-written
handler was the only thing closing any panel. I deleted the working mechanism and kept
five dead strings, which broke Escape everywhere.

Now `Widgets.CloseOnEscape(panel)` — one owner, the kit's. It sets propagation *before*
hiding, where the old version set it afterwards and only on the following keystroke,
which is why the first key pressed after opening a panel used to vanish. The dead
`escKeyframe` config is gone from all five callers.

*This is the second time in one session I confirmed a mechanism was **present** rather
than that it **worked*** — the first was `IsBrowserAvailable` reading a status field
whose name sounded like a predicate. Both times the check passed and the feature didn't.

#### The search box: one bug hiding behind another

`OnTextChanged` ignored Blizzard's `userInput` flag. `SetText` fires that handler exactly
as typing does, so showing the placeholder ran the handler, which saw
`text == placeholderText`, cleared it, and blanked the box it had just filled. The
placeholder erased itself.

Fixing that exposed **nine call sites reading `searchBox:GetText()` directly**. They had
only ever worked because the box really was empty; with the placeholder displaying, every
panel opened filtered to a string the user never typed. The filter summary said so
plainly — "Search" was listed as an active filter.

The box answers the question callers actually have now: `GetSearchText()` (empty while
the placeholder shows), `ClearSearch()` (reset to idle — `SetText("")` leaves it blank,
since the placeholder only returns on focus loss), `SetPlaceholder()` (retarget without
disturbing typed text). No raw `searchBox:GetText()` remains in either addon.

*Same shape as the pet `level` field: one concept, several readers, each quietly
compensating for a bug elsewhere. Fixing the bug exposes every compensation at once.*

#### The extras had a different search box entirely

Reported as *"the search box doesn't look the same on these 2 extras"* — which was the
diagnosis. Ability Browser and Special Tames each hand-rolled a `Widgets.EditBox`: no
placeholder, and **no debounce**, so both repopulated their entire list on every
keystroke. That was the backlogged "Ability Browser rebuilds per keystroke" item.

My mechanical replacement of the nine `GetText()` sites hit two of theirs, and since
`GetSearchText` only exists on boxes from `CreateSearchBox`, every pill click threw
`attempt to call a nil value`. Both panels use the shared factory now, which fixes the
look, the crash and the debounce together. `panel.searchBox` is assigned in exactly one
place in the codebase.

*Lesson:* a find-and-replace whose replacement count matches expectations confirms only
that the edit landed where intended — not that the objects involved support the new
call. Check what builds the thing before changing how it is read.

#### Two smaller wins

- The title offset read `config.title == "Pet Model Browser" and -20 or -35`: a shared
  component's layout keyed on one caller's display string, so renaming that panel would
  silently have moved its title. Now `config.titleOffset`.
- A resize grip was built for panels that were not resizable, where it did nothing.

Result: **eighteen files migrated.** luacheck 63/0, 47 tests, option audit clean.

### Deferred: layout standardisation (post-A6)

Raised during testing: title text and search boxes sit at different heights across
panels, a consequence of the addon growing feature by feature. Deliberately **not**
folded into A6:

- it needs *chosen* values, which is a design decision, not a mechanical one
- mixing pixel shifts into a refactor makes regressions hide in the noise, and this
  round proved how much that matters

The migration is what makes it cheap: once every panel is built through the kit, this
becomes a Theme/config change instead of a twenty-file change. `titleOffset` is the
first instance. Fold in the existing backlog item on button heights (20/22/25 across the
addon) and treat it as one pass, starting from an inventory rather than a survey.

---

## A6 — `Shared/OptionsPanel.lua` (13 → 0)

Nineteenth file. luacheck **61**/0 (down 2, accounted for below), 47 tests, option audit
clean. Tested in-game: *"everything looks and behaves as it should."*

### `CHECKBOX_INDENT_X` was in the WoW API list

The file's minimap checkbox anchored at `CHECKBOX_INDENT_X`, a constant it never
declared — sitting instead at the very top of `read_globals` in `.luacheckrc`, first in
the alphabetical list of Blizzard APIs. Someone hit warning 113, followed this project's
own written instruction ("add to `read_globals`, don't disable W113") and applied it to a
name that was never an API. `SetPoint` reads the resulting nil as 0, so nothing visibly
broke and nothing ever will — which is why it survived.

Declared as `0` (preserving the behaviour), removed from `.luacheckrc`, and CLAUDE.md's
linting section now says to ask *whether it is a Blizzard API at all* before listing it:
a name that isn't `C_Something`, isn't Blizzard CamelCase, and appears in exactly one
file is a missing `local`.

*This is the third instance this cycle of a check confirming a mechanism is present
rather than working.* The lint config is itself code, and an entry added to it is an
assertion — here, "this is an API the client provides," which was false.

### Reset All Settings never applied the opacity it reset

`isResetting` was a module-level flag guarding five `SetValue` calls, so Reset wouldn't
re-write the settings it had just written and rebuild every visible model five times.
Correct as far as it went — but the opacity slider's handler is also the only thing that
calls `Config:UpdateColors()` and `PanelManager:UpdatePanelBackgrounds()`. Reset wrote
`DEFAULT_OPACITY` to the DB and repainted nothing with it; the UI kept the old opacity
until something unrelated forced a redraw.

A suppression flag suppresses *everything*, including the one effect that was load-bearing.
Reset now applies opacity explicitly, with a comment saying why it cannot rely on the
slider to do it.

### `Widgets.Slider` — the seventeenth factory

**A WoW slider has no `userInput` flag.** EditBox has one; sliders do not. A programmatic
`SetValue` is indistinguishable from a drag, so every caller eventually invents the same
module-level `isResetting`. The kit owns it once as `:SetValueSilently(v)` — moves the
slider, repaints the caption, skips `onChange`.

It also owns the value caption via `format(value)`. Each of the five sliders spelled its
format string out three times: at construction, in `OnValueChanged`, and again in Reset —
and that third copy existed *only because the second had been suppressed*. Remove the need
for the guard at the call site and the third copy has nothing to justify it.

Same shape as the PanelManager round: the fix is not "handle the flag correctly at nine
call sites", it is "the widget knows, the callers don't have to."

A `slider` skin handler came with it, guarded on `S.HandleSliderFrame` exactly as the
dropdown handler guards `HandleNextPrevButton` — the two ElvUI helpers PSM calls that
aren't part of its long-stable core. A missing handler costs a skin; an error mid-build
costs the whole settings page.

### Three copies of "refresh what's on screen"

The opacity handler, the background-type dropdown and Reset each carried their own list of
panels to repaint, and they had already drifted: only one refreshed the teams panel, only
one rebuilt the models grid, and the popup-background block was written out **four** times
across two of them. Now `RefreshOpenPanels{ relayout, popups, opacity }` and
`RefreshPopupBackgrounds()`, with the three flags documented as what actually differs.

The two comment-only `if` branches for the Ability Browser and Special Tames — shipped
code that read as a decision and did nothing — are gone; that behaviour is
`PanelManager:UpdatePanelBackgrounds()`, said once in a comment. **Those two are the
luacheck drop: 63 → 61, both "empty if branch".**

### Deliberate visual changes (flagged before testing, confirmed after)

- checkboxes 32px → 20px (`Theme.CONTROL.CHECKBOX`) — this panel held the last 32px boxes
  in the addon; "Stop pet animations" nudged to stay centred on its dropdown
- divider 2px translucent grey → 1px `Theme.FILL.SEPARATOR`
- both dropdowns now carry the `dropdown` skin the Owned Pets filters have always had

### Remaining

`OwnedPets/Panel.lua` (12), `OwnedPets/DragDrop.lua` (11), `Shared/Menu.lua` (10),
`Shared/Utils.lua` (7), `OwnedPets/Row.lua` (6) — and those three of them hold all eight
surviving `ApplyElvUISkin` callers, so `Shared/UI.lua` goes when they do. Everything else
in the addon measures 1, each a deliberate survivor (event/timer frames, one `GameTooltip:`
inside a comment, PopUpManager's sublayer `CreateTexture`).

---

## A6 — `OwnedPets/Panel.lua` (12 → 0)

Twentieth file. luacheck **59**/0 (down 2: an unused `searchText` callback parameter and
a dead `addonName` local). Tested in-game.

### Three builders for one button

`MakeButton`, `MakeViewButton`, and the Export button written out longhand — same size,
same `GameFontNormalSmall`, same skin call, differing only in anchor and click handler.
One local `PanelButton` now.

That collapsed the `body may be a string or a function` indirection with it. It was a
generic mechanism serving exactly one caller (Pet Teams, whose saved-team count must be
read at hover time), added last round to fix a tooltip that rendered nothing. The button
passes a function spec straight to `PSM.Tooltip.Attach`, which has always accepted one.

*A wrapper generalising over one call site is worth deleting the moment the call site can
express itself directly.*

### A nil anchor is not an error

`MakeViewButton("Grouped", "grouped", panel.maximizeButton)` — and `maximizeButton` is
conditional on `config.showMaximizeButton ~= false`. Nothing has broken, because the
Owned Pets panel has always had one. But `SetPoint` with a nil `relativeTo` silently
falls back to the parent, so flipping that config would slide all three view buttons to
the panel's left edge with no error and no clue why. Now
`panel.maximizeButton or panel.closeButton`; the close button is unconditional.

*Same family as the stable-frame anchor bug: the failure mode of an optional anchor is
not a stack trace, it is a layout that looks like someone designed it that way.*

### The scroll block was TeamsPanel's twin

Scroll frame, rows backdrop, content frame — the same three frames at the same offsets as
`TeamsPanel.lua`, one migrated and one not. The hand-written backdrop matched
`Theme.BACKDROP.TOOLTIP` field for field. Both files now read identically.

### Backlogged during testing: the resize blind spot

Reported while testing this file, **pre-existing and unrelated to the migration**: while
dragging a resize, there is a band where the panel goes blank — no rows, no models — and
stopping the drag inside it leaves it blank. See the investigation entry below.

---

**Backlog: the resize blind spot (partially fixed, residual remains)** — moved to
`Backlog.md` (2026-08-21), still open.

---

## A6 — `OwnedPets/DragDrop.lua` (11 → 0)

Twenty-first file. luacheck **58**/0 (down 1: a dead `addonName` local), 47 tests, option
audit clean. Tested in-game across grouped reordering, stable reordering, team-slot
drags and cancel-over-nothing.

### A frame that could not do what it was named for

`DD:GetDragInterceptor()` built a full-screen frame, showed it for the duration of every
drag and hid it afterwards. It was created with `EnableMouse(false)`, no textures, and
`BACKGROUND` strata — it could not intercept input and could not draw. Removed with both
call sites. A mouse-disabled frame is also absent from `GetMouseFoci`, so it was not
influencing focus resolution either; this was checked, not assumed.

Third instance of the same shape in A6, after the resize grip on non-resizable panels and
the two comment-only `if` branches in OptionsPanel. **Named infrastructure is trusted on
sight far more than plain code is** — nobody re-derives whether the thing called
"interceptor" intercepts. The tell each time was construction that contradicted the name.

### Smaller

- The drag frame's backdrop turned out to be exactly the case CLAUDE.md already
  anticipated for `BORDER_ONLY` with `overrides = { edgeSize = 12 }` — the note predicted
  the call site before the call site was migrated.
- Its ring colour and slot caption were two copies of one yellow, now `DRAG_HIGHLIGHT`,
  annotated as deliberately *not* `Theme.COLOR.GOLD` so it does not get "corrected" into
  the text accent later.
- `updateFrame` stays a raw frame — a parentless `OnUpdate` holder, not a widget — but
  moved to `PSM.CreateFrame`, Core's stubbable alias.

### Remaining

`Shared/Menu.lua` (10), `Shared/Utils.lua` (7), `OwnedPets/Row.lua` (6). Those three hold
all four surviving `ApplyElvUISkin` callers, so `Shared/UI.lua` — the shim — goes when
they do. Then the deferred `.gitattributes` (`* text=auto eol=lf`; the index is already
100% LF, so it produces no diff in history) and the layout-standardisation pass.

---

## A6 — `Shared/Menu.lua` (10 → 0), and the end of the tooltip overlay

Twenty-second file. luacheck **56**/0, **51** tests (four new), audit clean.

### The migration

Straightforward: `MovableFrame` (with its own `OnDragStop` to persist position),
`TOOLTIP_HAIRLINE` border matching PanelManager's, `Widgets.Label`, `Widgets.CloseButton`,
`Widgets.Button`. Two identical browser-hint strings collapsed; `AddButton` lost two
parameters it never read.

### Fifth dead mechanism: `menu:Initialize()`

A full-screen click catcher "to dismiss any open context menus on outside click". It
never ran, on three independent counts: created hidden with nothing anywhere showing it,
`PSM.state.menuClickCatcher` written and never read, and the `PSM.state.contextMenus`
list its handler iterated is never populated in either addon. Dismissal is owned by
`CloseDropDownMenus()` in PanelManager's OnHide; construction is owned by the single
`PSM.Utils:ShowContextMenu`.

### The overlay, and why it took three tries to see

Reported: browser buttons stayed greyed with a click-eating overlay after enabling the
module mid-session. Two failed attempts first — re-evaluating on `OnShow`, then also on
build — both of which just moved *when* a cached answer was taken.

The user asked the question that resolved it: *can we remove the overlay with just a
mouse-over trigger?* **No — and that is the whole answer.** A disabled Blizzard button
never fires `OnEnter`, so it cannot carry a tooltip; the overlay was a transparent
mouse-catcher invented to receive the hover the button could not. The overlay existed
*because of* the disable.

Stop disabling and it all dissolves: button stays enabled, tooltip is a function
evaluated per hover (nil when fine), dimming corrected on the way past, click already
explained itself through `EnsureBrowser` → `Announce`. **Nothing persistent encodes the
state, so nothing can go stale.**

Two workarounds fell out with it — both were the same bug, already known and already
patched around:

- `PetRoulette.lua` reached into `PSM.state.menu` on load to re-enable those buttons and
  tear the overlay down. That was the visible "wake up" after clicking the minimap.
- `TeamsPanel.lua` did the same for three Pet Teams buttons, 0.1s after load, racing the
  login sequence for frames that usually did not exist yet.

*A module patching its parent's widgets on load is a sign the parent is storing state it
should be deriving.*

`TeamsPanel`'s version hid one piece of real work: the saved-team-count tooltip on the
menu button, landing only when it won the race. Now `PSM.Teams:ButtonTooltipSpec()`, one
definition shared with the Owned Pets panel, attached at build time.

### `Loader:UnavailableReason`

`Menu.lua` hardcoded "Enable ... in your addon list" for every case, while the Loader
already had `FAILURE_HINT` distinguishing disabled / dep-disabled / folder-missing. The
menu was carrying a *less accurate* duplicate — telling someone to tick a box for an
addon that is not installed sends them hunting for a control that does not exist.

`IsBrowserAvailable()` is now defined as `UnavailableReason() == nil`: one evaluation, so
predicate and explanation cannot drift apart. Four new spec cases, including a loop
asserting they agree across every fixture state.

### Also: `HideUIPanel`, and a note that blamed the wrong thing

`CloseAllPanels` carried "do NOT hide SettingsPanel — it breaks ESC and NPC interactions
until /reload", while `ToggleOptionsPanel` twelve lines above called `SettingsPanel:Hide()`
anyway. The breakage was real; the diagnosis was not. `SettingsPanel` is registered with
Blizzard's UIPanel system, which tracks occupied slots — a raw `:Hide()` hides the frame
behind the system's back and leaves a slot marked in use forever. `HideUIPanel` releases
it. Both call sites use it now, and "Close All Panels" closes the settings window.

*A comment recording a real symptom can still be wrong about the cause, and then it
protects the bug.*

### Remaining

`Shared/Utils.lua` (7) and `OwnedPets/Row.lua` (6) — Row holds the last surviving
`ApplyElvUISkin` call in the codebase, so `Shared/UI.lua` goes with it.

---

## A6 — COMPLETE

`Shared/Utils.lua` (7 → 0), `OwnedPets/Row.lua` (6 → 0), and the shim deleted.
luacheck **54**/0, **51** tests, audit clean.

**Every hand-written file in both addons builds its frames through `PSM.Widgets`.**

| | start | end |
|---|---|---|
| `ApplyElvUISkin` | 86 | **0** |
| `CreateFrame` | 193 | **6** |

The six are all one thing: an invisible parentless frame holding `OnUpdate` or
`RegisterEvent` handlers, which is not a widget. Named individually in CLAUDE.md so
nobody has to re-derive whether each is a mistake.

`PSM.UI:ApplyElvUISkin` and `PSM.UI.ElvUITexture` are gone — the shims that carried
pre-kit call sites through the migration have no callers left.

### The last two files

`Utils.lua` was already at 1 after the overlay deletion; its context-menu dropdown host is
deliberately unskinned, since it is never displayed and `skin = "dropdown"` there would
read as working and do nothing. It is also the first migrated file where the load-order
rule is load-bearing: Utils is TOC 19, the kit is TOC 26, so it only works because
`ShowContextMenu` reads `PSM.Widgets` at call time.

`Row.lua` held the last `ApplyElvUISkin`. Kit additions to finish it: `Label.justifyV`
(three call sites, one already reaching around the factory) and `IconButton.texCoord`,
applied to every texture state that exists — a mirrored icon whose highlight still points
the original way is worse than no highlight.

### The reorder arrows: four attempts, and a lesson I got backwards

Prompted by the user: *why not use ElvUI's drag-handle texture, rotated?* Right instinct,
and `resizegrip` already does exactly that. But rotating media by hand only restyles the
normal state, and these have three; `S:HandleNextPrevButton` is ElvUI's own function for
directional arrow buttons and handles all of them. New `reorderup` / `reorderdown` skins.

Then the sizing, which took four goes:

1. **24, Blizzard scrollbar-button art.** Inherited, never chosen.
2. **16 to match the resize grip.** Balanced under ElvUI, illegible without — the art is a
   scrollbar *button*, mostly bevel and frame around a small glyph.
3. **Branch on the skin: 24 unskinned, 16 skinned.** Worked, and I wrote a maxim next to
   it: *a control with two right sizes is nearly always a control with the wrong texture.*
4. The user found `UI-MicroStream-Yellow` on wago.tools — a bare triangle, legible at 16,
   which collapsed the branch and proved the maxim. Then noticed it looked *almost* like
   the dropdown arrow, and asked what that one was called.

`Interface\ChatFrame\UI-ChatIcon-ScrollDown-Up` is the dropdown's own arrow, so the
buttons now use the same asset rather than a lookalike — which also answers the size
question, because they should be whatever a dropdown arrow is.

**Then the maxim failed.** Measured with `/dump PetDupSpecDrop.Button:GetSize()`: a
dropdown arrow is 24 on the default UI and 18 under ElvUI. Matching it apparently needed
two numbers after all, so I reinstated the branch and rewrote the note to say the maxim
only applies when the branch compensates for art that will not shrink.

**Then the user dissolved it entirely:** *we don't do that with the dropdown — the skin
changes it.* The 24→18 IS `HandleNextPrevButton`, the same call `reorderup`/`reorderdown`
make. Set 24 and the skin lands on 18 by itself. Verified in-game: dropdown and arrow now
measure identically on both clients.

*Lessons, in order of value:*

- **If a difference is a skin difference, the skin owns it.** My branch had a call site
  hand-computing a result `Skin.lua` already produced — a violation of the exact boundary
  the kit exists to enforce, which I should have caught and did not.
- When a control looks *almost* like an existing one, make it the existing one rather
  than tuning the resemblance. Same shape as the four ability-bucket tables.
- A maxim written from one instance ("two sizes means wrong texture") survives exactly
  until the second instance. It was true of case 3 and false of case 4; the honest version
  names the distinction rather than the rule.

### What is left

- `.gitattributes` (`* text=auto eol=lf`) — deferred to here. The index is already 100%
  LF, so it produces no diff in history; the worktree is 47 CRLF / 18 LF and drifting.
- The layout-standardisation pass: title heights, search-box heights, button heights
  (20/22/25). Now the Theme-level change the migration was meant to make it, with
  `Theme.CONTROL` as the place decisions land.
- The resize blind spot, still rare — top candidate is `content:ClearAllPoints()` on a
  scroll child.
- A3 Option B: a curated `_G.PSM` public API.

---

## Backlog reconciliation (post-A6) + two small fixes

Before picking new work, checked the backlog against the code. **A6 had silently closed
several entries** — worth doing before starting anything, since three of these would have
been re-implemented from scratch.

| backlog entry | status |
|---|---|
| `NPCRow.lua`'s checkbox is 16px, check row layout when it migrates | **closed** — uses `Theme.CONTROL.CHECKBOX` (20) and `CHECKBOX_ROW` (22) |
| Models Browser placeholder never *swaps*, blanks itself | **closed** — goes through `searchBox:SetPlaceholder` |
| Ability Browser rebuilds on every keystroke | **half closed** — debounced via the shared `CreateSearchBox`; the frame-tree leak per call remains |
| Placeholder wrong when opening *straight into* NPC view | fixed below |
| Cross-addon file-scope capture sweep | done below |

*Deferred items carry a trigger ("do this when X migrates"), and nothing fires when the
trigger passes. Re-read the backlog at the end of the work that unblocks it, not when
someone next happens to look.*

### The capture sweep

One real hit across both addons: `SlashCommands.lua:88`,
`local PETSWAP_MAX_SLOT = PSM.Config and PSM.Config.MAX_STABLE_SLOTS or 205`. Now read at
call time.

**The guard made it worse, not safer.** An unguarded capture of a not-yet-loaded table
gives `nil` and a stack trace. This one would silently freeze the limit at 205 and then
reject valid slots with a confident message quoting the wrong number. It reads as
defensive and is the opposite — a bug with a fallback is a bug you cannot see.

The other fifteen matches are self-aliases (`local DD = PSM.DragDrop` immediately after
`PSM.DragDrop = PSM.DragDrop or {}`), which is the documented idiom and safe. `PetModels`'
`local M = _G.PSM.PetModels or {}` assigns back on the next line — also fine.

### The view-mode presentation split

The Models Browser's initial build carried its own copy of `ApplyModelsViewMode`'s branch,
and the copy had drifted: it showed and hid the same two frames but never set the search
placeholder and never hid the columns popout. A panel restored into NPC view opened
reading "Search models..." and stayed wrong until toggled by hand.

`ApplyViewModePresentation(mode)` is now the one definition of what a mode looks like;
both the toggle and the initial build call it. Page reset and data loading stay in
`ApplyModelsViewMode`, because the build path must not trigger a load.

*Same shape as most of A6: one concept, two implementations, the quieter one incomplete.*

---

## Ability Browser: frame pooling (the leak, finally closed)

luacheck **54**/0, 51 tests. Steady-state frame allocation per search: **zero**.

`AB:PopulateAbilities` built a fresh scroll child, a fresh card per category and a fresh
icon per ability on every call, and the search box calls it per keystroke. WoW frames
cannot be destroyed, so the previous set was only hidden — each search leaked a complete
copy of the panel's frame tree. Debouncing (added when the extras adopted the shared
search box) slowed it; it did not stop it.

### The leak was a closure problem, not a pooling problem

`CreateAbilityIcon` closed over `entry` in three places — the tooltip spec, `onEnter`, and
`OnClick`. `CreateCard` closed over `entries`, `hasMore` and `hiddenCount`. **With the data
baked into the handlers, building a fresh frame per populate was the only correct option.**
Pooling was impossible until the capture was removed, which is why the obvious fix had
never been applied.

Every handler now reads a field (`btn.entry`, `card.entries`, `card.hiddenCount`) and
`BindAbilityIcon` / `BindCard` reassign them.

*Same lesson as the file-scope capture sweep, one scope down: a snapshot inside a closure
forces you to rebuild whatever holds it. Reuse is unreachable until the data is a field.*

Three pools, keyed so nothing is reparented or orphaned:

- **scroll child** — created once
- **cards** — keyed by category (small, stable set); hidden when a search filters one out
- **icons** — owned by each card's partial/expanded area; surplus hidden, never dangling

### Two behaviours that changed because reuse demanded it

- The expand handler is **always attached and guarded on `card.hiddenCount`**, where it
  used to be attached only when there was something to expand. "Has more" is a property of
  a card's *current contents*, not of the card.
- `BindCard` **collapses on every rebind**. A pooled card keeping `isExpanded` would open
  at expanded height showing a grid built for a different category.

### And one capture removed pre-emptively

The expand handler took `scrollW` / `cardW` / `gap` / `cols` as upvalues from the populate
that created its card — which, with pooling, is the *first* populate forever. They are
CFG-derived constants today, so it is currently harmless, and that is exactly what would
make it invisible if the panel ever became resizable. Published as `panel.layout` and read
per call instead.

---

## Magnifier sizing + Locations two-state (both backlog items closed)

luacheck **54**/0, 51 tests. Both tested in-game.

### Magnifier: `userSized`, persisted

Auto-sizing was unconditional, so every populate recomputed an *absolute* target height and
applied it — resize larger, click another Display ID, and the width survived while the
height snapped back. Option (a) from the backlog: a flag set when the resize grip finishes
a drag.

- `Widgets.ResizeGrip` gained `onStop`. The distinction had to come from the kit:
  `OnSizeChanged` cannot tell a drag from a programmatic `SetHeight`, which is precisely
  why the popup could not tell "still default, fit to content" from "the user chose this".
- Gated at the single `popup.needsAutoSizing = not popup.userSized` in `PopulateModelPopup`
  rather than at the two auto-size sites, both of which already branch on the flag.
- Persisted to `settings.popupSizes`, **keyed by `popupName`** so the magnifier and the
  roulette remember their own. Restore also sets `userSized`, or the first populate would
  auto-size over the restore and the setting would look like it had not saved. Clamped to
  the current screen: these popups set no resize bounds, so a size saved on a larger
  monitor would come back with the grip off-screen.

**Reset needed two fixes that only showed under testing.**

1. *Width could not reset.* Clearing `userSized` re-enables auto-sizing, and **auto-sizing
   only ever recomputes height** — the same fact that caused the original bug. Popups now
   record `defaultWidth`/`defaultHeight` at creation and Reset restores them explicitly.
   This was written down in the original diagnosis and I still built a reset that relied on
   auto-sizing to undo something it does not touch.
2. *Reset cleared every family checkbox.* Pre-existing, from the initial commit:
   `PSM.state.selectedModelsFamilies = {}` — but empty means "hide everything", and the
   all-true seeding only runs when the panel is *built*, so an open browser stayed blank.
   **`PSM.ModelsFilters:ResetAllFilters(panel)` already did this correctly** — it is what
   the browser's own Reset Filters button calls. The Options reset was a second, worse copy.
   Sixth duplicate-with-drift of the session, and the first where the better copy already
   existed and simply was not called.

### Locations: two states

Verified rather than assumed: `InitStateIfEmpty` seeds every location `true`, so
`userHasActive` is always set — an unchecked location fails the include test and
`"inverted"` hits the disqualify path. **Both hide it, by different routes.** The third
state cost a click and bought nothing.

Now a plain checkbox. It rippled further than the UI, which is the point worth keeping:
there were **three separate implementations of the location rule** —
`ModelsDataLoader:_IsLocationSelected`, `NPCDataLoader:IsLocationSelected`, and a third
inline copy in `GetAvailableFamiliesForFilters` found only because a leftover grep caught
it. All three simplified; the continent-header exclude icon deleted with them.

Saved `"inverted"` values fold to `nil` on load — they already meant the same thing, and
leaving them would render a state the UI can no longer produce.

*Counting implementations is still the cheapest audit in this codebase.*

---

## Data refresh (2026-08-15) — and what the golden spec is actually for

`psm-data` regenerated the four browser tables. **7800 → 7852 records** (+52), with
`ConditionsData` +10 entries and `NotesData` +4. `ModelsData.lua` shows a 14k-line diff
for a net +162 lines, which is expected and not a red flag: new NPCs insert into a
sorted list, so every dense index after the first insertion shifts, renumbering `Index`
and the key column of every parallel table. Judge the refresh by the *net*, not the churn.

`models_data_spec.lua` failed in three places, all hard-coded numbers. **That is the
design, not a defect** — the count and the spot-check dense indices exist so a human has
to look at what moved. The distinction worth keeping:

- **Index moved, everything else identical** → normal refresh, re-point the literals.
  All five spot-checks landed here; `265254` went 7786 → 7831 and kept its name, family,
  expansion, classification, zone, displayId and both reactions.
- **Name, family, or count moved by thousands** → generator regression, stop and look.

The truncation canary survived intact: `273290` is *still* the tail record, still
multi-valued, so the multi-displayId coverage the spec's comment calls "by chance" did
not silently lapse. Distinct lookups unchanged at 61/12/4/400.

### Two false alarms, both mine, both from guessing a shape

Ran a cross-table integrity sweep, since only `ModelsData` has a spec:

1. *"450 CoordsData entries not in ModelsData."* **CoordsData is keyed by `uiMapId`**,
   not by npcId — the first three lines of the file say so. I matched zone IDs against
   NPC IDs and reported the mismatch as a finding. Re-run against the real shape:
   472 zones, **7852 distinct NPCs, zero orphans**, full coverage.
2. *"456 malformed coordinate pairs."* All empty strings, and **448 of them were already
   in HEAD** — checking against the committed file before reporting would have shown
   that in one command. They are also harmless *by design*: no consumer parses the
   coordinate values. `_IsZoneMatch` and `GetNpcZoneNames` test `mapData.npcs[npcId]` for
   presence only, and an empty string is truthy in Lua, so `""` correctly means "in this
   zone, coordinates unknown."

`ConditionsData` and `NotesData` resolve completely — 1369 and 2138 entries, zero
orphans, zero dangling `conditions[n]` references.

**The lesson is the session's own, arriving from a new direction:** I twice confirmed a
mechanism was *present* (an integer key, a `|`-joined string) rather than checking what
it *meant*. Both times a three-line read of the generated file's header, or one `git show
HEAD:` comparison, would have pre-empted the report. Against generated data, diff the new
against the committed before calling anything a finding — the baseline is free.

### The golden spec's maintenance cost, reduced to one deliberate checkpoint

The refresh prompted the right question: *does this have to be re-pointed every time?*
Worth separating two things that both looked like "the index":

- **`ModelsData.Index` is generated.** `12_generate_models_lua.py` rebuilds it every run.
  Zero manual work, and never a candidate for redesign.
- **The literals in `models_data_spec.lua` were manual** — three of them, plus a comment.

Auditing what each literal bought:

| Assertion | Value | Churned |
|---|---|---|
| `eq(#M.NpcId, 7852)` | the only truncation guard | yes |
| `eq(count(M.Index), 7852)` | none — "exact inverses" already proves the bijection | yes |
| `eq(i, c.index)` × 5 | none — asserts a *position* that growth guarantees to move | yes |

So five sixths of the churn was testing nothing. The spot-checks' worth is that npc
265254 is a Warp Stalker in Naigtal; the dense index it happens to occupy is not a fact
about the pet. Removed the index field entirely and replaced the assertion with a
presence check; the redundant count now compares to `#M.NpcId` rather than to a literal.

**The count literal stays exact, on purpose.** A truncated generation is *perfectly
self-consistent* — inverse checks, column sweeps and lookup resolution all pass on a
half-written file — so nothing but an absolute number catches it. One number that forces
a human look per refresh is worth having.

The real argument for cutting the rest is subtler than saving two minutes: **a ritual of
bumping numbers trains you to bump numbers.** Five guaranteed failures per refresh, all
of them meaningless, are exactly the conditioning under which someone re-points a
truncated `4000` without blinking. Keeping one literal keeps it loud.

### What was *not* changed, and why

The 14k-line diff per refresh is the deliberate, already-paid cost of the dense columnar
layout (`DATA_STRUCTURE_OPTIMIZATION_PLAN`: ModelsData 2.5MB → 1.1MB on disk, ~800KB
parsed). Insertions shift every later dense index, so the churn is structural.
Re-keying by npcId would flatten the diffs and undo the whole optimisation for the sake
of readable diffs on a generated file no one reviews by eye. Declined; noted here so the
question doesn't get re-opened without that context.

---

## Layout standardisation: button sizing (backlog item closed)

luacheck **54**/0, 51 tests. `Theme.CONTROL` gains `BUTTON = 25` and
`BUTTON_W = { XS 50, S 80, M 100, L 140, XL 180 }`; `Config`'s four button constants are
deleted. 20 files.

### The inventory found six heights, not three

The backlog recorded 20/22/25. The actual spread was **18, 20, 22, 25, 28, 30**, across two
Config constants (`BUTTON_HEIGHT` 22, `PANEL_BUTTON_HEIGHT` 25) and ~24 literals ignoring
both. *Starting from an inventory rather than a survey was the right call and the plan said
so; the survey undercounted by half.*

Before collapsing it, checked whether the 22/25 split tracked font size, which would have
made it a role rather than drift. It does not: `GameFontNormalSmall` appears on both sides
and several 25s set no font at all. **25 won on weight** -- already the majority, so ten
buttons move and two dozen stay put.

### Fixed tiers beat fit-to-text, for a reason measurement can't fix

The author's first instinct was a named scale; mine was snap-to-tier (measure the label,
round up). The deciding evidence came from asking *which labels are not literals*:

| Button | relabels to |
|---|---|
| `PanelManager` | "Maximize" / "Restore" |
| `AbilityBrowser` | "Select All" / "Unselect All" |
| `ModelsFilters` | "Exotic" / "!Exotic" |
| `ModelsPanel` view toggle | "NPC view" / "Models view" |

Measure-at-construction sizes for whichever label happens to be first, and the view toggle
is **built with no text at all** -- it would have measured zero. Re-measuring on every
`SetText` makes a button change width when you click it. **A fixed width survives both.**

Overflow is handled instead by clipping: the label gets an explicit width and
`SetWordWrap(false)`, so it ellipsises inside the button rather than drawing past it (WoW
does not clip child regions). That is what makes a fixed tier safe against the two things
that cannot be known at build time -- a later longer label, and ElvUI restyling the font
after we finish. **Neither has to be predicted, because neither can overflow.**

### The audit, and its blind spot

Clipping is silent -- a chopped word looks like a short word -- so clipped labels are
recorded in `PSM.Widgets.truncatedLabels`, alongside `unknownOptions` and
`Skin.unhandled`. One in-game dump found four:

- **"Make Active"** over S by 4px -> M.
- **"Exotic"** at exactly 0px -> the boundary case.
- **"Rename"** over the teams column by 6px -- **pre-existing**, revealed rather than caused.
- Two 50-character team names, over by 116px and 137px.

`SetMaxLetters` 50 -> **24** followed from the last of those: team names render *inside
buttons* (the picker rows at 180 and 200), and the second loses ~9 characters to
" (Slot N)". It caps input, not display -- names already saved stay and clip, because
silently rewriting a saved team name is worse than a shortened label.

**The blind spot is exactly the case that motivated fixed tiers.** The audit only ever
measures the label a button is *built* with, so it reported nothing for the view toggle --
which was visibly truncated -- because that button is built empty. The author's eye caught
what the instrumentation is structurally unable to see. Two buttons are permanently
unvouchable this way (view toggle, "!Exotic"); both are given a tier with room rather than
a margin.

### Turning clipping on exposes existing overflow

The trap worth recording: **preserving a too-narrow width would have created a regression.**
Buttons already overflowing rendered fine (text simply drew outside the art); with clipping
they visibly truncate. So tiers were chosen from the *labels*, not from the old widths --
"Ability Browser", "Unselect All", "Create Waypoints" and "Reset All Settings" all move up.

### One overlap, self-inflicted and arithmetic

Moving Special Tames and Ability Browser 80 -> 100 put two 100px buttons on opposite
corners of a **180px** frame. Fixed by widening the whole left column 180 -> **210** (four
coupled widths: the frame, its header, the filter frame, the tab strip), which also bought
pill spacing (55/3 -> 60/10) and let Exotic sit at S. `petsFrame` anchors to the column's
right edge, so the grid gives up 30px.

*Two 100s do not fit 180. Check the arithmetic of a container before widening what sits in
it -- the inventory covered buttons and never asked what held them.*

### Exceptions, all commented in place

`TeamsPanel`'s four-button stack keeps an explicit size: its column height is computed from
the button height, so the standard 25 would add 28px to every team row. `Dialogs`' two team
pickers stay explicit -- they are selectable rows, not push buttons. `Core.lua`'s stable
pair copy Blizzard's own button and must keep doing so.

`Widgets.Tab` has **no clipping and no audit** -- the pills can still overflow silently.
Noted, not fixed.

---

## A3 Option B, step 1: the boundary, measured and enforced (2026-08-16)

luacheck **54**/0, tests **51 -> 55**. Step 1 of the agreed three (declare + enforce, then
the `TeamDialogs` rename, then the `ns` sweep).

### What measurement changed about the plan

The plan's candidate surface was twelve names, guessed. Measured against what the browser
actually references, it is **eleven**, and the differences all mattered:

- **`Loader` is not used by the browser** and never was -- sensibly, since Loader is what
  *loads* the browser. It was on the list because nobody had checked.
- **`C_Timer` and `CreateFrame` *were* being used and should not have been.** Core's WoW
  API aliases exist so core's headless tests can stub them; the browser calls the globals,
  as `ModelRow.lua` was already fixed to do. Five call sites, now gone -- so the surface
  is 11 rather than 13.

Two premises in the plan turned out to be wrong, and both are worth correcting in place:

1. **"The three core reads of browser internals are the ceiling."** It is **seven**
   members across **46 references in 7 files** -- `PetModels`, `ModelsPanel`,
   `TamingChecker` plus `TamingRules`, `ModelsDataLoader`, `ModelsFilters`, `PetRoulette`.
   That direction cannot be fixed by `ns` at all (it is per-addon), so it stays on
   `_G.PSM` whatever B does. B is a one-directional fix and the plan reads as if it were
   both.
2. **`PSM.state` is 218 of the browser's ~437 core references -- over half.** B curates a
   surface whose largest member A5 owns and B may not touch. Worth saying plainly: after
   the `ns` sweep, `_G.PSM` shrinks 38 -> 11, but the 11 that remain include `state` and
   `Config`, the two most worth protecting. B encapsulates the *majority* of core, not the
   *sensitive* part of it.

### Why a test rather than luacheck

The plan wanted per-path `read_globals` to lint-enforce the layering. **That cannot work:**
luacheck sees one global named `PSM`, never its fields. `Tests/spec/boundary_spec.lua` does
it exactly instead -- parses `PUBLIC_API` out of Core.lua, derives what the browser owns,
and fails on anything else. File list comes from the `.toc`, so a new browser file is
covered the moment it ships.

It is also the safety net for the `ns` sweep: a missed reference goes from "silently nil in
whichever rare panel exercises it" to "named before the game is opened".

### It found a real bug on its first run, and I nearly misreported it

Flagged `PSM.RotationFrame` in `PetRoulette.lua`. My first read was "never assigned --
dead code", because the definition scan only sees dot syntax and `EnsureUpdateFrame` does
`PSM[key] = f`. **Checking before reporting was the whole difference:** the frame is real
and works.

But it is a core internal, and following it found **eight hand-written copies of "stop
tracking this model", five of which cleared only `RotationFrame` and never
`MovementFrame`.** A model released mid-right-drag stayed in `MovementFrame.activeModels`
for the session, iterated every `OnUpdate`. Guards had drifted too: three tested
`PSM.RotationFrame and PSM.RotationFrame.activeModels`, one tested nothing.

Now `PSM.RowManager:ReleaseModel(model)`. **Seventh duplicate-with-drift of this project**,
and the first found by a machine rather than by reading. It also resolved the boundary
violation the right way -- a service, not a wider surface.

### Verify the guard, not its presence

Three injections, because a checker that cannot fail is worse than none:

| injected | result |
|---|---|
| `PSM.Events` / `PSM.Broker` in a browser file | caught, correct file:line |
| the same names inside a comment | **not** caught |
| `Loader` added to `PUBLIC_API` | caught as an export with no consumer |

The middle row is the one that needed fixing: the spec's first run flagged
`PSM.CreateFrame` from the comment explaining why that file deliberately does *not* call
it. **A checker that flags the note warning against the thing is worse than no checker,
because the obvious fix is to delete the explanation.**

### Step 2: the `PSM.TeamDialogs` rename

`PSM.TeamDialogs` -> **`PSM.Dialogs`**, 40 references across 5 files. The backlog entry's
reasoning held: of the module's 15 functions, **seven have nothing to do with teams** --
`ShowNameInputDialog`, `ShowConfirmDialog`, the three group-name dialogs and two
group-delete confirms. Groups are a separate concept from teams, so the old name was
actively misleading for half the file.

It does **not** touch the public surface -- the browser has zero references to it -- which
is what made it safe to fold in here rather than treat as its own risk.

**Correction to this plan's own inventory (line ~866):** it lists
`PSM.TeamDialogs:CloseActiveDialog` and `:IsDialogOpen`. Neither is defined *or* called
anywhere in either addon. The inventory was never updated when they went. *Same failure
mode as the deferred backlog items: a record that nothing re-reads goes stale silently.*

### Step 3b/3c: the transition mechanism, and a design I got wrong

luacheck **54 -> 53** (Core.lua's pre-existing unused `addonName` became `_`), tests 55.
Converted: `Config`, `Theme`, `Skin`, `Tooltip`, `Loader`, `PetTooltip` -- 24 references.

**First the harness, before any conversion.** The client calls every .toc file with
`(addonName, ns)`; `dofile` passes nothing, so a converted file loaded by the old harness
dies on `ns.Foo = ...` before an assertion runs. `Tests/wow/addon.lua` uses `loadfile` and
calls the chunk properly. Verified both ways -- a scratch file written the A3 way loads
through it and fails exactly that way under `dofile`.

#### The bridge design was wrong twice, and a check caught it before it shipped

I proposed `__index` fallbacks in both directions plus an end-of-load publish, and told the
author conversion order would not matter. **Both claims were wrong:**

1. **A final-file publish misses file-scope reads.** `OptionsPanel.lua:161` calls
   `PSM.Widgets.Frame(...)`, `GridView.lua:10` reads `PSM.UI.GridView`, `DragDrop` and
   `Events` call `PSM.CreateFrame` -- all at column 0, so all during load, before
   PublicAPI.lua could publish anything. Stage 3d would have broken at login.
2. **Fallbacks both ways form an `__index` cycle**, and Lua does not resolve those to nil
   -- it raises *"'__index' chain too long"*. Every `if PSM.ModelsPanel then` browser gate
   would have started erroring instead of testing.

Replaced with **`_G.PSM = ns`**: one table, two names. Converted and unconverted files see
each other's writes at the moment of the write. No publish, no metatable, no cycle.
`PublicAPI.lua`'s publish is a documented no-op until 3g.

*The check that found this was one grep for column-0 reads of `PSM.` -- run because the
claim "order does not matter" was load-order reasoning I had not actually tested. The
lesson is the session's own, arriving again: I had confirmed the mechanism existed, not
that it covered the cases.*

There is no encapsulation during the transition, which is exactly the status quo. The
boundary spec still enforces the browser's side statically, and 3g is where the split
becomes real -- which is also where the remaining risk sits, not in the conversions.

### Step 3d: Utils, Widgets, Core, Menu, SlashCommands, PetGroups, Reorder, Row, Export

214 references. luacheck **53 -> 51**, both accounted: `Export.lua` and `PetGroups.lua`
each carried an unused `local addonName = "PetStableManagement"` that the new preamble
replaced. Confirmed by diffing luacheck output across the change, not by assuming.

**The 3c converter had a gap: it skipped comments but not strings.** `Widgets.lua` raises
four errors of the form `error("PSM.Widgets: ...")`, and those messages name the public
API a user reads in their chat frame. Rewriting them to `ns.Widgets` would have been wrong
*and* invisible until someone hit the error. The converter now masks string literals before
substituting -- which also stops a `--` inside a string being read as a comment.

*Two conversion passes, two classes of false rewrite: comments in 3c, strings in 3d. Both
were caught by looking at what the tool would change before letting it, rather than by
reading the diff afterwards.*

### Step 3e: Broker, TeamsData, OptionsPanel, Panel, GridView, Events, Minimap, PanelManager

438 references; core now 23 of 32 files. luacheck **51 -> 47**.

**The four-warning drop was hiding a new one, and it was a silent addon-breaker.**
Diffing the warning *text* rather than the count showed
`Events.lua:163: accessing undefined variable 'addonName'`. The preamble replacement had
deleted `local addonName = "PetStableManagement"`, and Events.lua uses it:

```lua
if event == "ADDON_LOADED" and arg1 == addonName then
    ns.Data:LoadSettingsOnly()
```

Nil never matches, so the addon would have loaded and **never initialised** -- no settings,
no minimap button, no saved state, and no error. Fixed by taking the name from the client's
varargs, which is strictly better than the hardcoded string: it cannot drift from the .toc.

The converter now checks whether a file uses `addonName` before dropping the binding.

**Three passes, three classes of false rewrite:** comments (3c), string literals (3d),
deleted bindings (3e). Each needed a different check, and this one was caught *only*
because the repo's rule is to account for every baseline movement rather than accept a
drop as good news. A falling warning count is as much a claim as a rising one.

### Step 3f: Dialogs, DragDrop, RowManager, Filters, TeamsPanel, Data, PopUpManager, GroupedView, UI

1130 references. **Core is now 33 of 33 files on `ns`** -- zero `PSM.` code references
remain; every surviving hit is a comment or one of Widgets.lua's four
`error("PSM.Widgets: ...")` strings, both deliberate.

luacheck **47 -> 40**. All seven removals are the same warning text
(`unused variable 'addonName'`) and *nothing appeared on the other side* -- which is the
check that caught the 3e breakage, since a file that used the name would show a new
undefined-variable warning here. Tests 55, unchanged.

**The sweep found three sites the converter structurally could not see, and all three
would have failed only at 3g.** The tool rewrites `PSM.`; these are not dot syntax:

```lua
-- RowManager.lua, memoising the shared tickers
if PSM[key] then return PSM[key] end     -- bracket syntax
...
function PSM:UpdateSaveTeamButtonState()  -- Core.lua, colon syntax
PSM:CreateSaveTeamButtonOnStable()        -- Events.lua, calling it
```

The Core.lua and Events.lua sites are **leftovers from 3d and 3e** -- files marked
converted that were not. They work today only because `_G.PSM = ns` aliases one table
under two names, and luacheck cannot see them at all because `PSM` is a *declared global*
in `.luacheckrc`. So the lint baseline was never going to report them, in any pass.

RowManager's pair is the more interesting failure: it is a memo. Once 3g separates the
tables, `ns[key]` would read empty on every check and the addon would build a **second,
unreferenced ticker** on each load -- the original still running, nothing pointing at it.
Not a crash. Just two OnUpdate handlers where one was intended.

*This is the same lesson as `PSM.RotationFrame` in step 2, which a dot-syntax scan also
missed and which I nearly reported as dead code: **the tool's blind spot and the reader's
are the same blind spot**, because both are looking for the same shape. Finding these
needed a search for the thing the converter does not match, run deliberately after it --
not a re-read of its output.*

### Step 3g: the split becomes real

Core.lua stops aliasing `_G.PSM = ns`. PublicAPI.lua publishes its eleven names and
installs the trap. luacheck **40, unchanged**; tests **55 -> 65**.

**The step was specified wrong, and the error was one of direction.** `PublicAPI.lua`
governs browser -> core. *Nothing governed core -> browser*, and it never needed to while
one table wore two names: the browser's `PSM.ModelsPanel = {}` landed in core's namespace,
so core's `ns.ModelsPanel` found it. Separating the tables made **58 reads across 7 core
files** nil -- the minimap's Toggle Models Browser, the options panel's re-render, every
model and taming-rule lookup in the popups.

Every one of them is guarded. So nothing would have errored: the browser would load and
the feature would quietly not be there. That is the failure mode CLAUDE.md already names
-- *a silent early return is indistinguishable from the feature not existing* -- arrived at
from a new direction, and the reason this landed as its own step rather than a flag flip.

Core now reaches the browser through `ns.Browser`, defined once. **Writes forward as well
as reads**, which is not decoration: PanelManager clears four browser caches by hand, and a
read-only bridge would have left those four assignments in an empty table -- caches never
cleared, no error, memory held for the session. Those four are a real layering violation
and are the next change; forwarding them is what kept 3g behaviour-preserving.

**The trap cannot error on every miss**, which is how it was originally described. Under
LoadOnDemand `if PSM.ModelsPanel then` reads an absent key *on purpose*, so a blanket
`__index` error would break exactly the gates that make the module optional -- at login,
on the minimap, for every user. It fires on one case: a name core owns and did not
publish. The internal set is computed from `pairs(ns)` rather than typed, which also
covers members stored as `ns[key] = f`.

**Three tools, three different blind spots, and each was caught by the next.**

| Found by | Missed | Why |
|---|---|---|
| the `PSM.` converter | `PSM[key]`, `function PSM:x` | matches dot syntax only |
| the crossref script | `ns.NotesData`, `ns.ConditionsData` (11 sites) | skipped `Data/` when collecting *definitions* |
| the new spec | -- | reads the `.toc`, so it sees generated files too |

The middle one is the instructive one. I skipped `Data/` because generated files are
exempt from *violations* -- which is true, and which boundary_spec.lua does deliberately.
But I applied that rule to the scan collecting **what the browser owns**, where it is
simply wrong: the generated tables define `PSM.NotesData` and `PSM.ConditionsData`, and
core reads both. A correct rule, applied one step to the left, under-reported the surface
by 11 sites -- and the only reason it surfaced is that the spec was written to derive the
same set independently rather than trust the script that did the edit.

*Verified by injection, both ways: a real `ns.ModelsPanel` in Broker.lua is reported with
file:line; the same names in a comment are not.*

### The cache service: a layering fix that turned out to be a bug fix

`PanelManager` cleared four of the browser's cache and timer fields by hand. Replaced with
`ModelsPanel:ReleaseCaches()`, owned by the addon that owns the fields. Tests **65 -> 66**,
luacheck **40** unchanged.

**The reach-in was hiding a real defect, and it is the eighth instance of the same
pattern.** There were *four* hand-written copies of "clear the browser's caches" --
PanelManager, PetRoulette's `ClearGlobalCaches`, and one half each in ModelsDataLoader and
NPCDataLoader. All four assigned nil. **None of them cancelled the timers.**

A `C_Timer` handle is owned by the timer system, not by the field holding it, so clearing
the field drops the reference and the timer fires anyway. `LoadModelsForSelectedFamilies`
had always known this -- it calls `:Cancel()` before re-arming -- but none of the teardown
paths did. And `PSM.state.modelsPanel` is *never set to nil anywhere in the codebase*, so
the `if not panel then return end` guard at the top of `_LoadModelsImmediate` did not stop
the late timer either.

So closing the browser inside the debounce window fired a render into the panel that had
just been torn down: a full recompute of the model list, applied to hidden rows, which
**repopulated the cache the teardown had just cleared**. The NPC side has a 0.15s window,
which is comfortably reachable -- change a filter, close the panel.

*The duplication and the defect are the same fact.* Four copies of an operation is four
chances to forget what the operation actually entails, and every copy forgot the same
half. Consolidating did not "also" fix the timer; there was nowhere left for the knowledge
to live except next to the field.

The surface shrank as intended: **13 browser names reachable from core -> 9**, and every
survivor is a module rather than a private field. `boundary_spec` now enforces that
directly -- core may cross into the browser, but never touch a `_`-prefixed field --
injection-verified.

### A5.0 (part 2): the accessor

`PSM.FilterState` (`State/Filters.lua`, the seed of A5's `State/`) owns the five tristate
toggles. 66 reads and 17 writes migrated off the panel frame. Tests **66 -> 82**, luacheck
**40** unchanged.

**The home is SavedVariables itself, not a new table.** It is the copy that always had to
be correct -- it survives a reload, and every toggle already wrote through to it -- so
making it *the* value means there is no cache to go stale, no load step to sequence, and no
way for a panel rebuild to disagree with the player's saved layout. A third table would
have been a third thing to keep in sync, which is the problem rather than the fix.

`Set` is now the single write funnel, which is the whole point: A5's store can only
invalidate what it sees.

**Deliberately not added: `FilterState:AnyActive()`.** Three sites in ModelsDataLoader
build an "are any other filters active" test over these toggles and it looked like the
obvious fourth method -- but all three pair `showPetsInMyZone` with
`panel.currentPlayerZone`, since an active zone filter with no zone resolved matches
nothing. A blanket helper answers true where those answer false, *and would be reused* --
a subtly wrong helper does more damage than three honest copies. Those three copies are the
`availableFamilies` dependency set written by hand, i.e. exactly what A5.1 turns into a
slice; left for there, where the zone condition can be modelled rather than flattened.

**A BOM shipped, and every check missed it.** Two files were rewritten with PowerShell's
`Set-Content -Encoding utf8`, which on 5.1 emits a UTF-8 BOM. One reached `c8bd262`.

| Check | Result |
|---|---|
| luacheck | parses it, count unchanged |
| WoW client | loads it -- the in-game test came back clean |
| `git diff` | shows nothing; the change is 3 bytes before line 1 |
| Lua 5.1 `loadfile` | **rejects it outright** -- the harness cannot load the file |

So it is invisible to everything that was running and fatal to the one thing that would
have caught it. Found only because an unrelated injection test happened to rewrite a file
the harness loads -- i.e. by luck, not by any check.

`Tests/spec/encoding_spec.lua` now walks both `.toc` files and asserts no BOM *and* that
every shipped file compiles, injection-verified. The second assertion is the one that
matters: the byte check states the rule, the compile check states the consequence, and a
future encoding problem that isn't a BOM still fails.

*The lesson is not "avoid PowerShell". It is that a tool I reached for casually had a side
effect on a dimension no check covered -- and the reason no check covered it is that every
existing check reads the file as text, where the BOM is invisible.*

### Aside: the NPC view's owned count (found during A5.0 testing)

The NPC view reported how many NPCs were found but not how many the player had. Adding it
took four attempts, and every wrong one was *arithmetically correct* -- the bug each time
was the **unit**.

| Attempt | Number shown | Why it was wrong |
|---|---|---|
| owned NPCs | 414 | larger than the player's entire 207-pet stable |
| owned models | 188 | correct, but reconciles with nothing the player can see |
| owned pets | 33 beside "28 NPCs found" | true, and reads as "33 of 28" |
| unique + total | `29 owned (33 including duplicates)` | -- |

**The first was not a smaller error than the others; it was the only one that was actually
false.** As a count of things owned, 414 is wrong -- many NPCs share one model, so matching
NPCs counts a single pet once per NPC that looks like it. The user's reaction ("I have a
moment") was the correct reading of a wrong number, not fussiness about presentation.

Two things worth keeping:

*A number is only checkable if it reconciles with another number the reader already has.*
188 was right and unverifiable; 207 is right and matches the Owned Pets panel, so the user
can confirm it at a glance. That is why the final caption reports both.

*Ownership is knowable only per display ID.* `C_StableInfo` gives a pet's displayID,
petNumber and specID but not the creature it was tamed from, so "do I own this NPC" has no
answer. Worth writing down because the obvious feature request -- match by npcId -- cannot
be built, and the next person to want it will need to know that before designing around it.

The user proposed a dedup step that turned out unnecessary in the direction they meant
(walking pets counts each once by construction) but necessary in another they then found:
their own duplicate pets. The final count does both in one pass, and the bracket doubles as
a diagnostic -- an unfiltered list should report the stable's own size, so a figure above it
would expose duplicate records in `stablePets`, which nothing currently checks.

### A5.0 status: complete, and two of the three "homes" were not what the table said

Re-measured against the code rather than the plan's table, written 2026-08-11:

| Home | Reality |
|---|---|
| `panel.show*` tristates | **The real problem.** Three copies hand-synced, one of them dead. Fixed. |
| `PSM.state.selected*` multi-selects | Already single-homed. Nothing to collapse. |
| `panel.searchBox` search text | The widget genuinely *owns* the text -- a store copy would be a mirror |

**Only the toggles were a multi-home problem.** The multi-selects live in exactly one
place already and are persisted from it; adding a setter would buy nothing until a store
exists to listen, and would be the speculative infrastructure that `AnyActive` was rejected
for. The search text is the same trap from the other side: an EditBox *is* where its
characters live, and mirroring them into a store recreates the write-only duplicate that
step one of A5.0 deleted.

**So search's problem is observability, not ownership, and it is precise:**

```lua
searchBox:SetScript("OnTextChanged", function(self, userInput)
    if not userInput then return end        -- programmatic changes stop here
```

`ClearSearch()` sets the text programmatically, so it does **not** notify. Today that is
invisible, because every caller follows it with an explicit reload -- `ResetAllFilters`
calls `ReloadAndSummarise()`, `ResetInternalState` calls `RepopulateRows`. Under a
version-counter store those explicit calls go away and the missing notification becomes
silent staleness: clear the search, and results keep the old query until something else
happens to invalidate.

*That is the same asymmetry the stress test recorded -- a string cache key tolerates an
unmodelled input by over-caching for 0.1s, a version counter turns it into permanent
staleness -- arrived at from a different direction. Recorded rather than fixed: a
notification with no listener cannot be verified, so it belongs in A5.1 with the store that
consumes it.*

Also noted for A5.1: the five search boxes use **two different callback styles**. Teams,
Abilities and Special Tames take the text as a parameter (push); Owned Pets and the Models
Browser ignore it and re-read the widget (pull) -- `ModelsFilters:CreateSearchBox` even
declares `searchText` and never uses it, which is one of the standing luacheck warnings.
Pull is the style that has to go: it is what makes the widget a state source.

**Fixed in passing:** `SpecialTames:ResetInternalState` cleared its box with `SetText("")`
rather than `ClearSearch()`, so Reset All Filters left the placeholder missing until the
box was focused and blurred. `CreateSearchBox`'s own comment warns against exactly this,
and `ModelsFilters:ResetAllFilters` already did it correctly -- one implementation, one
call site not using it.

### A5.1 step 1: funnel the writes

`PSM.Selections` (`State/Selections.lua`) is now the only writer of the five
`ns.state.selected*` tables. ~35 write sites across five files. Tests **82 -> 93**,
luacheck **39** unchanged.

**Chosen over going straight to version counters because the writes could not be proven
complete.** The plan's own reasoning made that the deciding question -- a string cache key
degrades to over-caching when an input is unmodelled, a version counter goes permanently
stale -- and the code could not answer it:

```lua
local function SelectAll(stateMap, list)          -- writes stateMap[k] inside
SelectAll(PSM.state.selectedModelsFamilies, list) -- the write is invisible here
```

No search for `selectedModelsFamilies` finds that write. So the write count was a lower
bound with no way to become an upper bound, and "we caught them all" was an assertion.

`Tests/spec/selections_spec.lua` turns it into a fact, with two rules:

1. **No direct assignment** to `state.selected*` outside the module.
2. **No passing** one to a function outside an explicit `READ_ONLY_CALLEES` allowlist.

*The allowlist is the mechanism, not a loophole.* Nothing static can tell a read-only
callee from a mutating one, so the only real question is which callees someone has checked.
Naming them means a **new** way of passing a table fails the build and has to be justified,
while the audited ones stay quiet.

**Injection found the check half-blind, and it was the same blind spot as step 3f.** The
first version matched `state.x = ` and `state.x[key] = ` but not `state.x.key = `:

```lua
PSM.state.selectedLocations.Durotar = true   -- sailed straight through
```

Dot versus bracket, again -- the pair that hid RowManager's tickers from the `ns`
conversion, met from the other side. **A checker written by the person who just did the
migration inherits that person's blind spot**, which is why it has to be attacked with
injection rather than review. All four shapes are now caught, verified by injecting each.

Also fixed by the check on its first run: `ModelsPanel:CreateModelsPanel` still reassigned
`selectedModelsFamilies`, which the by-hand conversion had missed.

**One correction the check needed:** it first flagged eleven `PetStableManagementDB.filters.selected*`
saves. Those are the *persisted* copy and are written freely -- only the session tables are
owned here. A rule that reports correct code as a violation teaches the reader it is noise,
so it is now anchored on `state.`.

**Next:** with writes funnelled and enforced, the counters question becomes answerable by
evidence. `Selections:Set/SetAll/Clear/Replace` and `FilterState:Set` are the two funnels a
version counter would hook.

### A5.1 step 2: the store, and one selector

`PSM.Store` (`State/Store.lua`) with slice versions and pull-based selectors.
`GetAvailableFamiliesForFilters` migrated. Tests **93 -> 108**, luacheck **39** unchanged.

**Two kinds of slice, and the split is evidence rather than taste:**

| Kind | Slices | Why |
|---|---|---|
| counted | families, expansions, locations, tamingRules, conditions, toggles, panel | writes funnelled *and spec-enforced* |
| fingerprinted | pets, favorites, zone | no funnel, so change is derived from the value |
| unknown | anything else | always dirty -- costs speed, never correctness |

That last row is what makes partial migration sound, and it inverts the plan's stated risk:
instead of "a missed input is permanent staleness", an unregistered slice is "no speedup
yet". A counter is claimed only where step 1's spec answers *did we catch every write*.

**A5.2 fixed on the way past.** `pets` fingerprints by content, not count, so releasing one
pet and taming another moves the version -- the staleness `#PSM.state.stablePets` could not
see. It cost nothing extra: the fingerprint had to decide something, and count was simply
the wrong thing to decide it on.

**The store shipped with a hole in the one function whose job is to have none.**
`Selections:Replace` copied straight into the table rather than through the shared write
path. `Clear` does not bump an already-empty slice, so **Replace onto an empty slice bumped
nothing at all** -- which is SpecialTames' Apply on a fresh session, i.e. the first thing a
user would do.

Found by writing the test as a loop over *every* mutator rather than testing the ones that
looked interesting. Set, SetAll and Clear were the obvious three; Replace and FillIfEmpty
were added for completeness and one of them failed immediately. *Enumerating the surface
found what choosing examples from it would not have* -- and re-injecting the original line
confirms the test fails without the fix.

**Also deliberate:** `zone` and `panel` are declared by the *browser*, not core, because both
live on the browser's panel frame. Core's Store.lua reaching across for
`ns.state.modelsPanel.currentPlayerZone` would be exactly the cross-addon field read the
boundary work has been removing.

**Not yet done:** the other two dynamic-filter selectors, the 11 `ReloadAndSummarise()` +
`UpdateDynamicFilters()` pairs, and retiring `GenerateCacheKey`. The expiry stays until the
dependency set is provably complete, per the plan's corollary -- `search` is still unmodelled.

### A5.1 step 3 — the other two dynamic-filter selectors

`GetAvailableExpansionsForFilters` and `GetAvailableLocationsForFilters` now go through
`PSM.Store:Selector`, same shape as families. Each body moved to a file-local
`ComputeAvailable*`, and `self:` became a local `ML = PSM.ModelsDataLoader` — the compute
is no longer a method, so `self` had nothing to bind to.

The dependency lists are leave-one-out, each omitting its own slice:

| selector | omits | reads |
|---|---|---|
| availableFamilies   | `families`   | expansions, locations, toggles, tamingRules, conditions, favorites, pets, zone, panel |
| availableExpansions | `expansions` | families, locations, ... (same tail) |
| availableLocations  | `locations`  | families, expansions, ... (same tail) |

That is the whole point of three separate selectors rather than one cache: ticking a
location cannot change which locations are reachable, so the location list must not
recompute when `locations` moves. Under the single shared cache key all three rebuilt on
every click.

**Checked before caching, because the shape changed.** These used to return a fresh table
per call, so a caller mutating the result was harmless; now the table is the cache. Both
call sites (`PopulateUnifiedFilterCheckboxes`, `PopulateLocationCheckboxes`) only iterate —
the locations one builds its own `groups`/`order` tables and sorts *those*. No caller
mutates a returned list.

Baselines unmoved: 39 warnings, 108 tests. Nothing new to assert — `store_spec` already
proves the mechanism, and these add no behaviour of their own.

### Two findings from reading the refresh call sites

**`OnTabClick` rebuilt the checkbox list twice.** It called
`PopulateUnifiedFilterCheckboxes(panel)` and then `UpdateDynamicFilters()`, which is that
same function behind a nil-panel guard, two lines apart. Removed; this is exactly the
category the 11-pairs item exists to eliminate.

**`RepopulateAllTabs` does four rebuilds where one would do — not fixed, recorded.** It
loops families/expansions/locations setting `panel.currentFilterType` and populating each,
then restores the saved type and populates once more. But `PopulateUnifiedFilterCheckboxes`
*replaces* `panel.filterCheckboxes` and `panel.filterHeaders` every call and hides the
previous set, so the first three iterations are discarded wholesale by the fourth. The
function is behaviourally equal to a single `PopulateUnifiedFilterCheckboxes(panel)`.

The one thing it does that the single call does not is warm the checkbox pool to the
largest of the three lists — and since `GetPooledFilterCheckbox` pools by index, the
longest list warms it on its own anyway. Left alone for now because it sits on the reset
path and this session's change is meant to be testable in isolation; it belongs with the
11-pairs work.

### The 11 pairs — a design fork, not a mechanical edit

The remaining item reads "remove the 11 hand-written `ReloadAndSummarise()` +
`UpdateDynamicFilters()` pairs", and it is worth being precise about *why* they must go:
a refresh written by hand at each write site is manual invalidation, which is the thing
the store replaces. A twelfth filter write that forgets the pair goes silently stale.

Two ways to finish it, and they are not the same design:

**A. One helper.** `ModelsFilters:ApplyFilterChange()` calls both; the 11 sites call it.
Removes the drift (some sites already call only one — line 402 legitimately, because
`RepopulateAllTabs` covers the other half) and is a small diff. But a new write site can
still forget to call it, so the invariant is still enforced by memory.

**B. Store-driven.** The filter slices notify, `ModelsFilters` subscribes, and the refresh
happens because state changed rather than because a call site remembered. The 11 pairs then
genuinely disappear — nothing calls them. This is what "the store drives the UI" means, and
it is the only version where the invariant is structural.

B costs a second mechanism: `Store` is pull-only today (`Version`/`Selector`), and adding
push makes it both. There is a middle road that keeps it pull — one idempotent
`Refresh()` that asks the store whether any relevant slice moved and returns immediately
when nothing did, called from one place instead of eleven — but "one place" then has to be
a tick or a frame boundary, which is its own decision.

Left for the user to choose. A is an hour; B changes what `Store` is.

### A5.1 step 4 — the 11 pairs, design B (store-driven)

User chose B. Reading the call sites first changed the shape of it, and for the better.

**The pairs were not two steps.** `ReloadAndSummarise()` arms a debounce timer (0.01s
models, 0.15s NPC) and returns; the timer's callback ends by calling
`UpdateDynamicFilters()` itself. So the hand-written second half ran *first* and
synchronously — its actual job was to narrow the pill list on the click instead of
10–150ms later. That is worth keeping, and it is now kept in one place.

Three of the sites (`All`, `None`, `Exotic`) also called
`PopulateUnifiedFilterCheckboxes(panel)` immediately before `UpdateDynamicFilters()`,
which is that same function behind a nil-panel guard — a full checkbox rebuild twice per
click, the same defect as the `OnTabClick` one found in step 3. Four instances total.

**What was built.** `Store:Watch(deps, fn)` / `Store:Flush()` / `Store:SetScheduler(fn)`,
reusing `CompositeKey` — extracted from `Selector`, which now shares it. That sharing is
the point: a push channel that could disagree with the pull channel would be worse than no
push channel. A watcher is a selector compared for effect rather than for a value.

**Coalescing is load-bearing, not tidiness.** `Selections:SetAll` writes one key at a
time, so a continent header bumps `locations` once per location. Firing straight from
`Bump` would reload the whole model list fifteen times for one click — worse than the
pairs it replaces. So `Bump` sets a flag and schedules one flush; the spec asserts
15 bumps → 1 queued flush → 1 callback.

**The scheduler is injected because core cannot pick it.** `C_Timer.After` is the client's
and the headless suite has no frames, so a Store that scheduled its own flush would be
untestable exactly where the coalescing lives. Store.lua installs the `C_Timer` one at the
bottom guarded on presence; the spec installs a drainable queue.

**Result: 9 pairs removed, 1 kept.** The survivor is `CreateSearchBox` — `search` is not a
slice, which is the same unmodelled input that keeps the 0.2s expiry alive.
`ResetAllFilters` also keeps its lone reload, because it clears the search box; commented
so the next reader does not delete it as leftover. `OnTabClick` keeps its single
`UpdateDynamicFilters` because a tab switch is a view change, not a state change.

#### Registration order matters, and it is one line of defence

`Watch` records the current composite key as its baseline, so arriving never reads as a
change. `WatchFilterState()` is therefore called *after* the `InitStateIfEmpty` writes in
`BuildUnifiedFilterSystem` — before them, seeding a fresh panel's selections would look
like a filter change and reload on construction. Registration is guarded by a module-local
flag because `BuildUnifiedFilterSystem` runs again on every panel rebuild, and a second
watcher means a second reload per change.

#### The known gap, asserted rather than left to be found

Only a `Bump` schedules a flush, and fingerprinted slices have no funnel to bump from — so
a pet tamed with nothing else touched does not wake a watcher. `pets`, `favorites` and
`zone` keep their existing refresh paths, so nothing regressed, but it is not automated.
There is a test named for this (`is not woken by a fingerprinted slice on its own`) so the
limit is visible and the standing "funnel the six stablePets writes" item has something to
flip. The alternative — polling fingerprints every frame — is out: `pets` sorts the whole
stable.

#### A test that passed against broken code

The re-entrancy guard (`Flush` clears `flushQueued` *before* running callbacks, so a bump
made by a callback schedules the next flush rather than being swallowed) was injected and
**the test passed anyway**. The fault was in the spec's own helper: `drain()` did
`queue = {}`, rebinding the upvalue, while the test held the reference `withScheduler`
had already returned — so `#queue` measured a table nothing was writing to any more.
Fixed by emptying in place, which is the same identity-preserving argument as
`Selections:Clear`, arrived at from the opposite direction. With the helper fixed the
injection failed the run, and only then was the code restored.

Two of the three new guards were injection-tested; the third (coalescing) caught its
injection with the exact count, 15 against 1.

Tests 108 → 117, luacheck 39 unchanged. `CLAUDE.md`'s "reload through one entrypoint"
section rewritten — its old rule ("whenever you change filter state, call the shared
helper") is now precisely the regression to avoid.

### Bug found during A5.1 step 4 testing — "None" did nothing in the NPC view

User report: on the NPC view, clicking **None** on the Locations pill left the list
unchanged, while the Models view correctly emptied. Selecting a specific location worked
in both. Pre-existing, not caused by the watcher — and the watcher firing is *why* it was
visible, since the Models view emptied on the same click.

**Absent and empty were the same answer.** `NPCDataLoader.IsLocationSelected` opened with:

```lua
if not selectedLocations or not next(selectedLocations) then return true end
```

A nil table means the filter was never initialised — nothing is being asked, show
everything. An **empty** table means the player clicked None — a filter that matches
nothing. Collapsing the two makes "select nothing" indistinguishable from "no filter",
which is the most user-visible way to get it wrong. `_CalculateModelsData` reads the same
state the other way (`hasSelection` false leaves `match` false), which is why the two
views disagreed.

**The same defect was one filter over.** Expansions had it written inline at the filter
site, `not next(selectedExpansions) or ...`, so **None on the Expansions tab had the
identical bug** in the NPC view — unreported, presumably just not tried. Fixed together:
fixing only locations would have left the NPC view inconsistent with itself, which is
worse than being consistently wrong. Extracted as `IsExpansionSelected`, mirroring
`_CalculateModelsData`'s rule that with nothing selected only entries carrying no
expansion data qualify.

This is the **duplicate-implementations-with-drift** pattern again, and the file even says
so: ModelsDataLoader's location block is commented *"Third copy of this rule -- see also
_IsLocationSelected above and NPCDataLoader's IsLocationSelected"*. Three copies, and the
comment on the NPC one claims it mirrors `_IsLocationSelected` — which it did. The one it
had to agree with was the *fourth* rule, the inline block in `_CalculateModelsData` that
the Models view actually uses. Naming the duplication did not stop it drifting.

**No test guards this**, and that should be stated rather than implied. Both predicates are
file-local to a browser addon that the headless suite cannot load, so the empty-vs-absent
distinction has no regression guard. Making them testable means either exporting them or
collapsing the four copies into one shared rule — the latter is the real fix and belongs
on the backlog, not in a bug fix.

`selections_spec` did fire, though, on the *new* call: passing `PSM.state.selectedExpansions`
to `IsExpansionSelected` failed the build until the callee was added to
`READ_ONLY_CALLEES`. That is the allowlist working as intended — a new way of passing a
selection table has to be justified before it is allowed through.

**Backlog:** collapse the four copies of the location/expansion selection rule into one.

### Standardising the reload debounce (from a user observation)

User observed: with **None** selected on Locations/Expansions in the Models view, switching
to the NPC view briefly paints rows before emptying. Their read — *"probably because we
have different data loaders"* — was right, and their proposed fix was better than mine.

**Cause.** `ApplyModelsViewMode` calls `UpdateNPCPanelLayout()`, which paints synchronously
from `panel.allNPCs` — the list from the *last* NPC load, i.e. before the None click — and
only then arms the debounced load that replaces it. The Models view has the identical
window; at 0.01s against the NPC loader's 0.15s it is simply below perception. One
behaviour at two speeds, not two behaviours.

**I proposed loading immediately on a view switch; the user proposed matching the delays
instead, on the grounds that the models path already works.** Theirs is right. Mine special-
cased one call site and left the two loaders asymmetric — the actual defect — while theirs
removes the asymmetry and the symptom together.

**Two facts made it safe, and neither was obvious without looking:**

* The 0.15 never protected search typing. The search box debounces at `SEARCH_DELAY`
  (0.3s) in `PanelManager:CreateSearchBox`, so `onTextChanged` fires once per pause. The
  loader's window never sees a keystroke.
* It was **0.01 originally**, raised in `069c646` (the columnar-schema commit), uncommented
  and unmentioned in the message. What it absorbed was bursts of
  `LoadNPCsForSelectedFamilies` — back when one continent click meant fifteen calls. A5.1
  step 4's flush coalescing removes that upstream, so nothing is left for the longer window
  to absorb. **This was not safe to change last week; the store commit is what made it so.**

**Fixed by name, not by value.** `Config.RENDER_DELAY = 0.01` already existed and neither
loader read it — which is the whole explanation for the drift: a named constant nobody
used, so tuning one copy could not move the other. Both now read it, making them
structurally equal rather than coincidentally equal.

A third copy remains: `TeamsPanel.lua:19` declares its own `local RENDER_DELAY = 0.01`.
Equal today, unrelated to this path, and folding it in would mean retesting a panel this
change does not otherwise touch. **Backlog**, with the same argument as the four
location-rule copies.

The general shape, now seen twice in two days: *a constant that must agree across call
sites will stop agreeing unless agreement is structural.* The location/expansion rule
drifted in four copies; this delay drifted in two, past a named constant that already
existed to prevent exactly that.

**TeamsPanel folded in the same session, at the user's call** — *"cheaper now and eliminates
the risk of forgetting about it"*, which is the right instinct: a backlog item whose whole
content is "these two numbers must agree" is one nobody will pick up until they disagree.
`TeamsPanel.lua`'s `local RENDER_DELAY = 0.01` is gone; `ProcessRenderQueue` reads
`ns.Config.RENDER_DELAY` inside the function, not at file scope.

**A fourth timer surfaced one line below, and was deliberately left alone.**
`RefreshTeamsList` debounces at a bare `0.03` — cancel-and-rearm, coalesce, then render:
structurally the same shape as the two loaders, and uncommented in the same way the NPC
0.15 was. But `0.03 ~= 0.01`, and that distinction is the whole decision:

* `TeamsPanel`'s `RENDER_DELAY` was a **duplicate of a constant** — same name, same value,
  same meaning. Removing it cannot change behaviour, only prevent divergence.
* The `0.03` is **not a duplicate of anything**. Folding it into `RENDER_DELAY` would
  retune the Teams panel from 30ms to 10ms — a behaviour change, in a panel this work does
  not otherwise touch, with no evidence either way about why 0.03 was chosen.

Deduplicating and retuning look alike at the diff level and are completely different
risks. Doing the second while claiming the first is how a "cleanup" commit becomes the one
git-bisect stops at. If `0.03` should be a named thing, it wants its own name and its own
testing, not absorption into a constant it never equalled.

**Backlog — does TeamsPanel's `0.03` refresh debounce earn its place at all?** User's read,
and worth keeping because it frames the investigation: the Teams panel does not have the
*volume* the model/NPC lists do, but it does have a more complex row structure than a flat
list, so it is not obvious a priori whether the coalescing is buying anything. The question
to answer is not "should it be 0.01" but "is it doing any work" — if the panel never
receives bursts of `RefreshTeamsList`, the timer is latency with no benefit and should go
rather than be renamed. Deliberately deferred, not settled.

**Residual, accepted.** With the delays matched, the view-switch flash is much shorter but
not gone — `UpdateNPCPanelLayout` still paints `panel.allNPCs` before the load replaces it,
so 10ms of stale rows remain. User: *"now I know why and I don't want to chase this any
further."* Recorded so the next person meeting it finds the cause rather than re-deriving
it; the real fix is not painting a list the panel is about to discard, which is a change to
the switch path rather than to a timer.

## A5, remaining: what a survey of the four cache keys actually found

Before starting the "retire `GenerateCacheKey`" item, the four keys were read rather than
assumed. The plan listed three; there are four, one is already gone, and one is a much
bigger job than its one-line mention suggests.

**1. `_GenerateDynamicFilterCacheKey` — already retired.** Steps 2 and 3 replaced it with
the three `Store:Selector`s. Nothing references it. One of the three listed items is done
as a side effect, which is what "old and new systems can coexist" was supposed to buy.

**2 and 3. `ModelsDataLoader:GenerateCacheKey` and `NPCDataLoader:GenerateCacheKey`** (the
NPC one is not in the plan's list — it was added by `069c646` alongside the render cache).
Every component of both is already a slice — expansions, locations, taming rules,
conditions, favourites, toggles, zone, ownership — **except `search`**. So these two are
blocked on exactly one thing, and it is the thing the plan has flagged as unmodelled since
A5.1 was written.

**4. `UI:GenerateCacheKey` is not a follow-on; it is a second A5.0.** It belongs to the
Owned Pets panel in *core*, and its inputs are a completely separate filter subsystem —
`exoticFilter`, `duplicatesOnlyFilter`, `selectedSpecs`, `selectedFamilies`,
`selectedTamers`, `sortBy` — of which **zero** are slices. Retiring it means doing for
Owned Pets what A5.0/A5.1 did for the browser: find the homes, funnel the writes, enforce
the funnel. That is its own task with its own testing, not a third bullet.

### A real bug found while surveying: A5.2 is only half fixed

`UI:GenerateCacheKey` opens with `#ns.state.stablePets` — **the identical count-as-proxy
defect A5.2 was written for**, in a second panel. A5.2 fixed the browser's copy by making
`pets` a content fingerprint; core's Owned Pets panel still keys its render cache on the
count, so releasing one pet and taming another leaves the key unchanged while the pet set
differs, and the panel re-applies a stale render. Same narrowness as the original (needs
the panel open across a stable transaction), same masking by the `0.1s` expiry, same
realness.

Worth stating plainly: **A5.2 was recorded as complete and was not.** The plan named the
symptom by file and line (`ModelsDataLoader.lua:126`), the fix addressed that line, and the
second instance was never looked for. Naming a defect by location rather than by shape is
how the other copy survives — the same lesson the four location-rule copies just taught,
arriving from a different direction.

Not fixed here: it belongs with item 4, because `pets` is core-side already (the fingerprint
lives in `Store.lua`) but the rest of that key is not, and half-migrating one cache key
gains nothing. **Recorded as the first concrete task of the Owned Pets work.**

### So the next step is `search`, and it is the only thing on the critical path

It unblocks items 2 and 3, it is the last surviving hand-written refresh pair, and it is
the last unmodelled input keeping the `0.2s`/`0.1s` expiry load-bearing.

### Hard constraint on all ownership work: pet data is collected at the stable master only

Raised by the user in response to the A5.2-in-Owned-Pets finding above, and it constrains
the fix rather than the diagnosis.

**Pet records can only be built at the stable master.** This is a deliberate, long-standing
decision, and it is why the addon shows **no Release button** even though releasing in the
wild is technically possible: the action succeeds but the stored record is neither properly
deleted nor updated. Taming is the harder half and the reason the approach is closed rather
than merely awkward — **the NPC ID is lost once the tame completes, and displayID is not
exposed on a wild or active pet**, so the record cannot be healed afterwards by looking the
pet up in `ModelsData.lua`. A fix for the release half would stop dead at the tame half.

**What this forbids.** The tempting reading of "ownership can go stale" is *collect more
often* — on more events, on zone change, on pet summon. That trades a display-freshness
problem for **corrupt records**, which is strictly worse and much harder to notice. Every
ownership fix in this plan must be an **invalidation** fix: the data is collected when it
can be collected correctly, and the cache is told that it moved. `pets` as a content
fingerprint is exactly the right shape for that reason — it observes whatever the last
legitimate collection produced and never asks for a fresh one.

**What it means for the Owned Pets task.** `#ns.state.stablePets` becomes a content
fingerprint like the browser's, and nothing else changes. The stale window is only
reachable across a stable-master visit, so in practice today the `0.1s` expiry already
covers it — the reason to fix it is that the expiry is scheduled for removal, and removing
it is what turns a masked latent bug into a live one. Order matters: **fingerprint first,
expiry second.**

The user is open to revisiting the wild-collection design, but as its own discussion. Not
folded into this work.

### A5.1 step 5 — `search` becomes a slice, and the last pair goes

**Fingerprinted, not counted, and the reason is the home.** Search is the one filter input
whose state lives in a *frame* rather than a table: five panels each own a box, seven sites
read `searchBox:GetSearchText()` directly. A counted slice needs every write funnelled and
a spec enforcing it, and **a widget's writes cannot be enforced** — Blizzard fires
`OnTextChanged`, not us. Fingerprinting the box sidesteps the whole question: the
fingerprint *is* the truth, so it cannot go stale regardless of who typed what.

The cost is that a fingerprint cannot announce itself, which needed one new primitive.

**`Store:Touch()` — the manual wake.** Argument-free on purpose: it does not claim *what*
changed, so it cannot claim wrong. Watchers re-read their dependencies and fire only if a
composite key actually moved, which makes a Touch with nothing behind it free — asserted,
because the failure mode of getting this wrong is a "reload button wearing a store's
clothes" that every caller reaches for instead of modelling their input.

It also closes the gap documented in step 4 in the general case: any fingerprinted slice
now has a way to be noticed.

**The `ClearSearch` trap, fixed while it was still harmless.** `ShowPlaceholder` goes
through `SetText`, which fires `OnTextChanged` with `userInput = false` — correctly ignored,
since that is how the placeholder used to erase itself. So clearing the box changed what
the user sees and told nobody. All three callers papered over it with an explicit reload
immediately after, which is why it never showed. The moment a store reads the box, an
unannounced clear becomes silent staleness *on Reset All Filters* — the worst case. Now
`ClearSearch` notifies through a `NotifyNow` that cancels the typing debounce, guarded on
an actual change so clearing an empty box stays quiet. All three call sites were read
first; each already re-reads the box or passes `""`, so the extra notify is redundant
rather than harmful.

**`ResetAllFilters` reloads no more.** Its explicit `ReloadAndSummarise()` existed only
because search was unmodelled; it is now `Store:Touch()`. Strictly better: it cannot miss
an input the watcher covers, and it does **no work at all** when Reset is pressed on
filters already at their defaults — which the unconditional reload could not tell.

#### luacheck 39 → 38, and the vanished warning was evidence

Diffed by text rather than trusted. Three warnings only shifted line numbers; exactly one
disappeared: `ModelsFilters.lua:299:54: unused argument 'searchText'`. The search callback
had been *declaring* it received the text and then ignoring it, pulling from the widget
instead — the push/pull inconsistency this step exists to remove, which luacheck had been
pointing at the whole time. Nobody read it as a design signal because "unused argument" reads
like tidiness.

Tests 117 → 120.

**What this unblocks.** Every component of `ModelsDataLoader:GenerateCacheKey` and
`NPCDataLoader:GenerateCacheKey` is now a slice. Both can become selectors — the next step,
and the last before the `0.2s` expiry stops being load-bearing for the browser.

### A5.1 step 6 — both loader cache keys become selectors, and the expiry goes

`ModelsDataLoader:GenerateCacheKey`, `NPCDataLoader:GenerateCacheKey`, both
`SelectedMapKey` copies, `PanelFilterFragment`, and both `_*RenderCache` tables are gone.
Net −80 lines. **A5's "retire the cache keys" item is complete for the browser.**

**Removing the expiry was one change with the keys, not a step after them.** A selector has
no timestamp — it recomputes exactly when a dependency moves. The plan's corollary said keep
the expiry "until the dependency set is provably complete", and step 5 closed the last gap,
so the two had to move together. Flagged to the user before starting rather than discovered
mid-edit.

**The dependency lists were derived, not guessed.** Each is the old cache key read component
by component, with `#stablePets` becoming the `pets` fingerprint:

* Models: families, expansions, locations, tamingRules, conditions, toggles, favorites,
  pets, zone, search, panel — the same ten the watcher covers, plus `panel`.
* NPC: the same **minus `tamingRules` and `conditions`**, because that view does not filter
  on them and `_CalculateNPCData` reads neither. The old key omitted them too. Special
  Tames still reaches the NPC view, but via `families`, which
  `RecomputeSmartFamilySelection` narrows on its behalf.

`panel` is included in both: a rebuilt filter system is a different panel with a different
search box, so a result computed against the old one must not survive.

#### Three things found by reading rather than by testing

**1. `_ApplyNPCData` hands the cached table straight to the panel, and the panel sorts it in
place.** With a 0.2s cache this was invisible; with a selector the table persists, so
`NPCRow:SortItems` now mutates cached state — a direct violation of Store's "treat a
selector's value as read-only" contract. Kept as a **documented exception** rather than
copied, because the mutation is a *reorder of the same elements*: it cannot change which
NPCs matched, and sort field/direction are not slices. It also makes `_npcSortCache`'s
identity check sharper rather than weaker — the selector returns the same table until a
dependency moves, so an unchanged list is recognised as already sorted. Copying would
restore the contract and re-sort ~7000 entries per reload to prevent a reordering nobody can
observe. An exception with a stated reason beats a rule quietly weakened to fit.

**2. `LoadModelsForSelectedFamilies` was switching its own cache off.** It opened with
`PSM._modelsRenderCache = nil`, so the models view's 0.2s window only ever helped calls
arriving by some other route — the main reload path always recomputed. Deliberately *not*
carried over as `modelsResults = nil`. Deciding what is stale is the selector's job now, and
reproducing that line would disable the cache for the same path all over again.

**3. `ReleaseCache` had to drop the selector, not a table.** The selector closes over the
computed item list, which is the ~7000-entry allocation the function exists to release, so
`modelsResults = nil` / `npcResults = nil` is the real teardown. Missing this would have
turned a memory-release function into a no-op that still looked right.

#### The apply/update asymmetry that created the eleven pairs, finally named

Both `_Load*Immediate` functions used to `return` early on a cache hit, **skipping
`UpdateFilterSummary` and `UpdateDynamicFilters`** — those only ran on a miss. That is the
mechanical origin of the hand-written pairs: call sites re-issued the updates because a cache
hit swallowed them. With a selector there is no early return and both always run, so the
reason the pairs existed is gone as well as the pairs.

`SelectedMapKey` also came out of `selections_spec`'s `READ_ONLY_CALLEES`. The allowlist is
an audit record, and an entry for a function nobody calls is a claim about code that no
longer exists.

Tests 120, luacheck 38, both unchanged — no new behaviour to assert that `store_spec` does
not already cover, and no new globals.

#### Correction: the NPC view does not filter Special Tames "via families"

The step 6 note above claimed the NPC selector could safely omit `tamingRules` and
`conditions` because "Special Tames still reaches this view, but through `families`, which
`RecomputeSmartFamilySelection` narrows on its behalf." **User challenged it; it is wrong,
and the code is unambiguous about why.**

The granularities, both confirmed by reading:

* **Taming skills are per displayID** — `displayData.taming`, checked in
  `DisplayPassesFilters`.
* **Conditions are per NPC ID** — `PSM.ConditionsData.Get(npcID)`, checked in the same
  function against each of a display's NPCs.

The Models view applies both at those granularities. `NPCDataLoader` reads **neither** —
zero occurrences of either state field in the whole file. So the NPC view does not filter
on Special Tames at all.

What does reach it is `RecomputeSmartFamilySelection`'s family narrowing, and
`ComputeMatchingFamilies` describes itself exactly: *"the set of families with **at least
one** display matching the given taming rules / conditions."* An any-match superset. Since
families are mixed, it over-shows — the user's example: one Rodent requiring Ottuk taming
pulls in the entire Rodent family, including every Rodent needing no special taming.

**So family narrowing is selection-seeding on Apply, not filtering, and calling it the
latter was my error.** Nobody decided this; the NPC view was simply built without those two
filters and the omission was never named.

**What was and was not affected.** The code is untouched by the correction — step 6
preserved existing behaviour exactly, and the old cache key omitted both fields for the same
reason. Only the justification was wrong. But a wrong justification in a comment is worse
than none: it tells the next reader the gap is closed.

**The lesson, and it is the session's recurring one from yet another angle.** The claim came
from reading `RecomputeSmartFamilySelection`, seeing it consume taming rules and write
families, and inferring that the path was equivalent. It is a *lossy* path, and the function
that makes it lossy says so on its own first line. Tracing a data path is not the same as
checking what survives it.

**Backlog — make the NPC view filter Special Tames properly.** Two halves with very
different costs:

* *Conditions* is direct: `_CalculateNPCData` already resolves `npcId` per row, and
  `ConditionsData.Get(npcID)` takes exactly that. Near-mechanical.
* *Taming rules* needs a displayID-to-taming lookup this file does not have. It works from
  `modelsData.DisplayIds[i]` (raw IDs), while `.taming` hangs off the `displayData` objects
  behind `PetModels:GetFamilyModels`. Either a resolver or an index.

Both slices go into `NPC_RESULT_SLICES` **at the same time as the filtering**, never before:
declaring a dependency the compute does not read means invalidating on a change the list
does not act on — cache misses bought for nothing.

### The NPC view now filters Special Tames — and the user's memory removed the hard part

The gap recorded above is closed. But the shape of the work changed twice before any code
was written, both times because the user knew something the code did not say.

#### "Sliver of N'Zoth moved to Special Conditions" — the special case was dead three times over

Mid-investigation the user asked whether any leftover code still treats Sliver of N'Zoth as
a *taming skill*, having moved it to Special Conditions long ago. Both existing copies of
the taming predicate carried a special case for it: when that rule was selected, fall back
to an NPC-level `ConditionsData` lookup. It could not fire, for three independent reasons:

1. `SpecialTames.lua:685` filters the key out of the taming-rule list, so it is never
   selectable.
2. `ModelsData.lua` contains no "Sliver" anywhere, so `tamingSet["Sliver of N'Zoth"]` is
   never true.
3. The fallback compares `cName == "Sliver of N'Zoth"` while the condition is actually named
   **"N'lyeth, Sliver of N'Zoth"** — so it would not match even if reached.

Any one would have made it dead. Removing it is what made the predicate small enough to
share. **Worth noting the direction of the help: this was institutional memory, not
something the code could be read to discover** — three consistent-looking mechanisms, none
of which announced that the feature had moved.

#### "Taming by displayID, not by family" — checked against the data rather than argued

The user's other correction was that taming skills are per displayID and conditions per NPC
ID, so family-level extrapolation is wrong in both directions (Rodent has pets needing Ottuk
taming and pets needing nothing).

The open question for the NPC view was whether it needed a displayID→taming lookup, since
`ModelsData.Taming` is a *per-NPC* column that `GetFamilyModels` aggregates up to displays.
Answered empirically rather than by reasoning: across all 7852 rows, **7031 shared-display
comparisons produced zero disagreements** — no display has two NPCs with different taming
requirements. So the per-NPC column is equivalent to the display aggregate, and the NPC view
reads `modelsData.Taming[i]` directly. The half estimated as "needs a resolver or an index"
needed neither.

#### Three copies became one, in `PetModels`

`DisplayPassesFilters` and `ComputeMatchingFamilies` each carried a full copy; the NPC view
would have been the third. Now `PetModels.TamingSetPasses`, `TamingSet`,
`ConditionsHaveActive` and `NpcPassesConditions`, in the file whose stated job is that both
views "resolve these identically".

The two copies had already drifted in a way that matters: **one passed the raw
`ModelsData.NpcId` column to `ConditionsData.Get` and the other `tonumber`'d it first.**
Coercion now happens inside the shared function, so both callers resolve the same NPC.

What is deliberately *not* shared is the combination: `DisplayPassesFilters` ANDs rules with
conditions, `ComputeMatchingFamilies` ORs them (it seeds a family selection, so it wants
breadth). Only the predicates were duplicated; the difference was real and is preserved.

#### First test coverage these rules have ever had

`Tests/spec/specialtames_spec.lua`, 16 tests. Possible only because the logic is now pure
functions over plain tables — no frames, no client API, no ModelsData. That is a second
argument for extracting it, independent of the duplication: **the reason this was untestable
was that it was embedded in a pipeline that isn't.**

The Florafaun/Direhorn clause is the one piece of real logic (a display needing *both* must
not match when only one is selected) and had no test in any of its three homes. Injection-
tested: removing the clause fails `hides a both-required display when only one of the pair
is selected` on the exact case.

`selections_spec` fired again on the three new predicates receiving selection tables, and
once more on a **multi-line call** — its scan is per-line, so the callee name was not
visible and it failed closed, reporting "unaudited" rather than silently passing. Failing
closed is the right direction for that guard; the call was put on one line.

Tests 120 → 136, luacheck 38 unchanged.

### Backlog closed: the six copies of the location/expansion rule

Recorded as four; it was six. Locations had three (`_IsLocationSelected`, the inline block
in `_CalculateModelsData`, NPCDataLoader's local) and expansions had the same three. All are
now `PetModels.SelectionMode` / `SelectionAllows` / `SelectionAllowsLocation`.

**They disagreed on the case that matters, and one disagreement had already shipped** — the
"None does nothing in the NPC view" bug fixed earlier today. The rule has three answers and
the copies conflated pairs of them in different directions:

    nil table   the filter was never initialised -- everything passes
    no `true`   the player chose "None" -- only a value the data lacks passes
    otherwise   the value must be actively selected

**`false` counts as absent, and that turned out to be load-bearing rather than defensive.**
The two slices store differently, which the merge exposed: expansions go through
`checkbox:GetChecked()`, which writes **`false`** on uncheck, while locations write `nil`
(`(not selected) or nil`). So "untick every box" produces an all-false table for one slice
and an empty one for the other. Any unified rule that treated `false` as a value rather than
as absent would have made "None" behave differently per tab -- a regression invisible in
review and reachable by ordinary clicking.

The middle answer is why `SelectionAllows` returns `value == nil` rather than plain `false`
for "None": an NPC with no expansion recorded survives an empty expansion selection, which
is the existing behaviour of the inline block. Locations cannot reach it -- `NpcLocation`
always returns a string, "Unknown" as the fallback -- so for them "None" excludes everything.

One deliberate casualty: locations' legacy *only-`"inverted"`-values* case used to pass
everything and now passes nothing. Unreachable -- the three-state cycle is gone and
`BuildUnifiedFilterSystem` folds any saved `"inverted"` to nil on load.

`mode` is an optional third argument purely for the hot loops, which resolve it once instead
of rescanning the selection per row. The two inline blocks also collapsed into a single pass
over each item's NPC list rather than two consecutive filtering passes.

Eight tests added, and the injection is the honest one: making "None" pass everything --
the original bug -- fails two of them by name.

### Backlog closed: TeamsPanel's `0.03`, and it is not what it looks like

The question was whether it earns its place. **It does, but not as the debounce its shape
suggests, and not for any reason the number hints at.**

As a coalescer it buys nothing: all ~15 call sites fire once per user action or per event,
and the only back-to-back pair in the codebase was **a duplicated block in `Events.lua`** --
the same `IsVisible()` test and `RefreshTeamsList()` call written twice in succession, now
removed. Nothing bursts.

What the delay actually does is get `DoRefreshTeamsList` **out of the caller's call stack**.
It rebuilds and re-lays out every team row, and several callers are mid-operation on those
rows when they ask: `DragDrop:SwapTeamSlots` refreshes and then returns `true` to a handler
still holding a row, and the dialog paths refresh from inside a confirm handler. Synchronous,
it would tear down frames underneath their own callbacks.

So it stays, renamed `REFRESH_DEFER` with the reasoning attached, and **deliberately not
folded into `RENDER_DELAY`**: that is a progressive-render tick, this is a reentrancy guard,
and the two agreeing at a value would be coincidence rather than shared meaning. The earlier
instinct to delete it was right about the stated reason and wrong about the real one --
which is the argument for tracing callers before removing a timer, not after.

luacheck touched 40 briefly and was diffed rather than accepted: both new warnings were a
pointless two-step assignment in the new spec, fixed rather than absorbed. Back to 38.
Tests 136 → 144.

#### Follow-up: the piped location string was a leftover, and the user spotted it

On reviewing the merged rule the user asked whether `|`-splitting locations was left over
from the free-text era, given the move to matching by `uiMapId`. It was, and the answer
also confirmed there is **no drift between the views**: `PetModels.NpcLocation(i)` resolves
`UiMapNames[UiMapId[i]]`, which is exactly what NPCDataLoader does inline. Both views read
the same column through the same lookup; only the splitting was stale.

Checked rather than assumed, same as the taming question: **0 of 400 `UiMapNames` values
contain a pipe, and 0 of 7852 rows have a table-valued `UiMapId`.** An NPC carries one map
id, so its location is one name. The splitting had nothing to split.

Three sites went:

* `SelectionAllowsLocation` **deleted entirely** -- locations are not a special shape, so
  they use `SelectionAllows` like expansions. The rule is now genuinely one function, not
  two that agree.
* `_IsZoneMatch`'s legacy fallback split `NpcLocation` and then *separately* compared
  `UiMapNames[uiMapId]` -- the same value `NpcLocation` resolves, so the two comparisons
  were one comparison written twice.
* `ComputeAvailableLocations` split a single name to insert one entry.

**The pattern worth naming.** The pipe was doing no harm and produced correct results, so
nothing would ever have failed to reveal it. What it did was make locations *look* like a
different kind of value from expansions, which is why they had separate implementations to
begin with -- the dead syntax was carrying a false claim about the data, and the false claim
was the thing that cost. A leftover that still works is not free; it is a lie about the
domain that future code will believe.

Tests 144 → 143 (the two piped-string cases became one about resolved map names), luacheck
38 unchanged.

## Owned Pets panel: the survey, and why the task is not what the plan said

Same discipline as the browser -- read the state before designing. The plan called this
"a second A5.0". **It is not, and the difference matters for how to sequence it.**

**There is nothing to funnel.** All eight inputs to `UI:GenerateCacheKey` are cheaply
fingerprintable, and `Utils:GetTableHash` already fingerprints three of them -- the current
key pays exactly that cost on every render. The browser needed a write funnel because it
wanted *counters* for hot, large slices (61 families, 400+ locations, recomputed per pill
click). Owned Pets' sets are small and already hashed. Write counts bear this out: 1-2 per
field, against the browser's dozens.

**But the key is missing an input outright.** `_CalculateRenderData` reads
`ns.state.content:GetWidth()` and derives `colCount`, `colWidth` and `rowTotal` from it.
Resizing the panel changes the correct answer and not the key -- the A5.0 "state living in a
frame is invisible to invalidation" case, in the file A5.0 was written about.

**And `pets` is the wrong fingerprint here**, for two reasons that the browser gets
deliberately right:

* It **sorts** before hashing, because model filtering cannot care about stable order. This
  panel lists individual pets and, with no sort column chosen, renders them in `stablePets`
  order -- so DragDrop reordering changes the answer invisibly.
* It hashes **displayID**, i.e. model ownership. This panel shows individual pets, so
  releasing one and taming another that shares its model is a real change.

**Eleven hand-written `ns._renderCache = nil` calls** across DragDrop, GridView,
GroupedView and PanelManager are the compensation for those two gaps. They are the exact
shape of the browser's eleven pairs, and like those they are not redundancy -- each one is
a call site that knows something the key does not.

### What was done now: A5.2's second instance, closed

`Store:Declare("ownedPets", ...)` -- order-sensitive, keyed on `petNumber` -- and
`UI:GenerateCacheKey` consumes it via `Store:Version("ownedPets")` in place of
`#ns.state.stablePets`. The old and new systems coexist exactly as the plan intended: the
string key survives, one of its components is now a slice.

This closes the defect recorded earlier today as "A5.2 was recorded as complete and was
not". Both the swap-at-equal-count case and the reorder case now move the key.

Two tests, and the pairing is the point: each asserts that `ownedPets` moves **and** that
`pets` does not, because the two slices answering differently is the design rather than an
inconsistency.

### Sequencing for the rest, which needs a decision rather than a default

The remaining work is not "convert the key to a selector". It is: **model the two inputs the
key never had**, and only then can the eleven manual invalidations and the 0.1s expiry go.

1. `content:GetWidth()` -- a frame dimension. Either a fingerprinted `panelWidth` slice, or
   the resize path bumps a counted one. The resize path already calls an
   `invalidateCacheCallback`, so a bump has an obvious home.
2. Whatever the GroupedView/GridView nils are compensating for -- collapse state and view
   mode are the candidates, and neither has been traced yet.

Doing the selector conversion before those two would remove the 0.1s expiry while the
dependency set is still incomplete, which is precisely the failure the plan's own corollary
warns about: *"Removing it first would make latent staleness bugs more visible, not less."*
The eleven manual nils are load-bearing until 1 and 2 are modelled.

### Owned Pets: the migration, and the eleven nils accounted for individually

The two untraced inputs from the survey are resolved, and the answer was not the one the
count of manual invalidations suggested.

**Only one input was genuinely missing.** `_CalculateRenderData` reads no `panelViewMode`,
no `PetGroups`, no collapse state -- those are read in `_ApplyCachedRender` and
`UpdateVisibleRows`, both of which run on **every** render, cache hit or miss. So the eight
`ns._renderCache = nil` calls in GroupedView and GridView were forcing a recompute of data
that could not have changed. They were never necessary.

Accounting for all eleven:

| site | verdict |
|---|---|
| `PanelManager:444` (resize) | load-bearing -- `content:GetWidth()` was a real, unmodelled input |
| `PanelManager:341` (teardown) | legitimate, but a *release* rather than an invalidation |
| `DragDrop` x2 (reorder) | made redundant by `ownedPets` earlier today |
| `GroupedView` x6, `GridView` x1 | never necessary |

Ten deleted; the teardown became `ns.UI:CreateRenderCache()`, which is now the only thing
that can release the render data since it lives in the selector's closure.

**Two bugs fell out of tracing them.**

`CreateScrollPreservingResizeHandler` took an `invalidateCacheCallback` that **neither of
its two callers ever passed**, so the `else ns._renderCache = nil` fallback always ran --
and for the Teams panel that cleared the *Owned Pets* render cache, a panel it has nothing
to do with. Parameter and fallback both gone; `panelWidth` makes the invalidation
unnecessary anyway.

`CreateRenderCache` nilled `ns._renderDebounceTimer` **without cancelling it** -- the exact
defect `ModelsDataLoader:ReleaseCache` was fixed for in the browser, sitting unnoticed in
core. Closing the panel inside the debounce window left a render scheduled into the panel
just torn down, which would recompute and repopulate the cache the teardown had cleared.
Same class, same file kind, found the same way: by reading a teardown path rather than by
observing a failure.

**`GenerateCacheKey` and the 0.1s expiry are gone.** The dependency set is nine slices, and
`panelWidth` is the one the old key never had. A5's "retire the cache keys" item is now
complete for **both** panels; nothing in the addon keys a cache on a hand-built string.

#### The claim that justified deleting ten lines is now enforced

`Tests/spec/renderinputs_spec.lua` parses `_CalculateRenderData` and fails the build on any
`ns.state.<field>` read that has no slice behind it, naming the field and the three places
to fix it. A second test pins the negative directly -- view mode, pet groups and collapse
state must never appear in that function, because ten deletions depend on it.

This is the guard the browser's loaders never got, and they should have it too: their
dependency lists were derived by reading, and nothing re-checks them. **Backlog: extend the
same static audit to `_CalculateModelsData` and `_CalculateNPCData`.**

Injection-tested with the precise regression it exists to catch -- one line reading
`ns.state.panelViewMode` inside the function fails both tests by name.

Tests 145 -> 149, luacheck 38 unchanged.

#### Arrow reordering never refreshed the panel, and the store only made it visible

User report during testing: moving a pet up or down with the arrow buttons at the stable
master prints the move to chat but leaves the panel showing the old order, while drag-and-
drop reordering updates correctly.

**The two are unrelated operations, which is why only one broke.** Drag-and-drop in the
grouped view reorders *pet groups* (`ReorderPetInGroup` / `MovePetToGroup`) -- PSM's own
data, changed in place. The arrows call `C_StableInfo.SetPetSlot`, which changes the
**game's** stable order and nothing of PSM's.

**Root cause is a missing collection, not a cache.** `SwapPetSlots` waited 0.3s and called
`UI:UpdatePanel`, which calls `EnsurePetData(false)` -- and that collects only when
`#stablePets == 0`. With pets already loaded it does nothing, so the panel re-rendered from
the pre-swap copy. The addon had not re-read what it had just asked the game to change.

This predates the store work; removing the 0.1s expiry did not cause it and would not have
masked it either, since recomputing from stale input yields the same stale answer. What the
migration did was remove the last reason to *think* it might right itself.

Fixed by collecting before rendering. **Explicitly not an exception to the stable-master
rule** -- `CanReorderPets` already requires `isStableOpen`, so reordering is only reachable
at the one place a complete record can be built. Worth stating in the comment, because a
future reader who knows the rule will flinch at seeing a collection call.

**And it exposed a real gap in `ownedPets`.** The fingerprint hashed `petNumber` positionally,
which catches a swap of two occupied slots (the collected order changes) but **not a move
into an empty slot** -- same pets, same sequence, one different `slotID`. The panel displays
slot numbers and can sort by them, so that is a visible change the cache must see. `slotID`
is now part of the fingerprint.

That gap was invisible while the collection bug existed, because nothing ever refreshed
`stablePets` for either case. Fixing the outer bug is what made the inner one reachable --
the usual shape: a defect can hide behind another defect on the same path, and only shows
when the first is removed.

Tests 149 -> 150.

##### Correction: there are two slot-reordering paths, not one

I described the working case as "drag-and-drop reorders pet groups". User corrected it:
there are **two distinct drag-and-drop features**, and I had read only one branch of
DragDrop.lua and described the file from it.

* **List/Grid drag-and-drop** -- changes *stable slots*, stable-master only. Same operation
  as the arrows.
* **Grouped-view drag-and-drop** -- custom ordering inside PSM's pet groups. Never touches a
  slot.

So the real account is better than my guess, and confirms the fix rather than contradicting
it. **Both slot paths go through `Reorder:SwapPetSlots`.** List/Grid passes
`skipUpdate = true` because it owns its scroll-lock and render timing, and its own
post-swap block **includes `ns.Data:CollectStablePets()`** (DragDrop.lua:428). The arrow
path used `SwapPetSlots`'s built-in update, which rendered without collecting. One
implementation had learned something the other had not, and the drift was a single line.

**The duplication is kept, deliberately.** Merging the collect into `SwapPetSlots` for all
callers means either collecting before `SetPetSlot` has settled -- it is asynchronous, which
is what both delays are for -- or splitting collection and render across two timers whose
relative order then has to be maintained by hand. That trades one duplicated line for a pair
of constants that must agree, which yesterday's `RENDER_DELAY` work is a standing argument
against. Both sites now say so, and `skipUpdate` is documented as "the caller owns the whole
post-swap refresh, data included" rather than the "skip the render" it reads as.

**The method note.** This is the second time in two days that reading one branch and
describing the enclosing thing produced a confident wrong statement -- the first being
"Special Tames reaches the NPC view via families". Both times the code sampled was real and
the generalisation was not, and both times the user had the map. Reading one path proves
what that path does, and nothing about its siblings.

---

### A5.3 -- the browser loaders get the audit the render already had

Backlog item carried out of A5.2, named in that commit message: "the browser's loaders
deserve the same audit and do not have it yet." Both `_CalculateModelsData` and
`_CalculateNPCData` dropped their 0.2s expiry alongside the Owned Pets render, so all three
share the same failure mode -- an unmodelled input is now **permanent** staleness rather
than a slow refresh -- and only one of the three had a machine re-deriving its dependency
list. The other two had lists I wrote by reading the files, which is exactly the kind of
claim this plan keeps finding to be wrong.

`Tests/spec/loaderinputs_spec.lua`, table-driven over both loaders.

#### The difference that made it real work: it has to be transitive

`renderinputs_spec` scans one function body, and for `_CalculateRenderData` that is the
complete answer -- it reads `ns.state` inline. Both loaders instead **delegate**, and the
delegation is where the interesting reads live:

    _CalculateModelsData -> BuildOwnedDisplaySet   (showHideOwned, stablePets)
                         -> DisplayPassesFilters   (favoriteModels, selectedTamingRules,
                                                    selectedConditions, four toggles)

None of those appear in the caller. **Copying the per-function scan across would have
reported "fully covered" while three of the eleven slices had no visible justification at
all** -- a green test proving nothing, which is worse than no test, because it also stops
anyone else from writing the real one. The walk follows file-local callees by bare name, so
`self:_IsZoneMatch`, `Loader:_IsZoneMatch` and a plain `DisplayPassesFilters(...)` all
resolve the same way; it reaches 8 functions for the Models view and 5 for the NPC view.

Matching by bare name over-matches in principle -- a same-named function in another module
would be followed as though it were this one. That is the safe direction on purpose: it can
only pull in *more* reads and demand *more* justification. Under-matching is what passes
silently.

#### Three kinds of input, because the loaders have three

A scan for `PSM.state` alone under-reports here, and the two it misses are the two that
have already caused bugs in this plan:

* `PSM.FilterState:Get("x")` -- the toggles never touch `PSM.state` at a call site.
* `panel.searchBox` / `panel.currentPlayerZone` -- state living **in a frame**, which is
  precisely the case that cost the Owned Pets render its `panelWidth` slice in A5.2.

#### The reverse direction is also checked

A slice declared but never read is a cache miss bought for no correctness -- and this is not
hypothetical, it is what NPCDataLoader's own comment describes from before `tamingRules` and
`conditions` were actually applied there. Both directions now fail loudly. Both lists come
out exactly justified: 11 slices, 12 inputs, nothing spare either way.

#### `isStableOpen` is the one row that needed reasoning rather than a mapping

It is not a filter. It chooses between `CollectStablePets` and
`LoadPersistentDataForDisplay`, and both write `stablePets` -- so the answer varies with
`stablePets`, which `pets` fingerprints, not with the flag, and the branch only fires when
the list is empty anyway. Mapped to `pets`, and deliberately **not** given a slice: one here
would recompute the entire model list every time the player walked up to a stable master,
for an answer that cannot have changed. Written into the spec rather than into this file,
where the next person to see the row will be.

#### The premise, pinned as a property

The walk stops at the file boundary, and both computations call across it
(`PetModels.SelectionAllows`, `TamingSetPasses`, `NpcPassesConditions`, `NpcExpansion`,
`NpcLocation`). That is only sound while those are pure readers of the generated tables --
which today they are: `PetModels.lua` contains no `PSM.state` read at all.

Asserted as **that property**, not as an allowlist of callee names. The roster changes with
every refactor while the property is what actually has to hold; an allowlist would need
editing constantly and would say nothing when it mattered. If a resolver ever grows a
filter-dependent branch, the audit goes partial *silently* -- so that is the thing the test
watches.

#### Injection-tested, five ways

Per the standing rule that a guard must be proven to fire, not assumed to:

1. state read added inside `DisplayPassesFilters` (the helper -- the case a per-function
   scan misses) -> caught, named the field
2. `conditions` removed from `MODELS_RESULT_SLICES` -> caught
3. `ownedSort` added to it -> caught as unjustified
4. `PSM.state` read added to `PetModels.lua` -> premise test caught it
5. the transitive walk stubbed to stop at the entry function -> "reached 1" caught it

Injection 1 also exposed a defect in the *spec*: two later tests crashed on the nil mapping
instead of failing cleanly, burying the real message under a stack trace from the wrong
test. They skip unmapped inputs now -- the first test owns that failure and names the field.
Same lesson as the `drain()` bug in A5.1: injecting does not only test the code, it tests
the test.

The IDE's own diagnostic caught a third: `local body, reached = byName and TransitiveBody(...)`
truncates a multiple return to one value, so `reached` would have been nil however many
helpers the walk visited -- and the "follows the helpers" test would have passed by
measuring nothing. A vacuous guard on the guard.

Tests 150 -> 161. luacheck 38, unchanged.

**Backlog closed:** "extend the static audit to `_CalculateModelsData` and
`_CalculateNPCData`". All three no-expiry selectors in the addon now have their dependency
sets machine-checked.

---

### Backlog: `RepopulateAllTabs` did four rebuilds where one would do

The backlog entry said "behaviourally equal to a single `PopulateUnifiedFilterCheckboxes`".
Verified rather than assumed, since that is exactly the claim this plan keeps finding wrong.

    local function RepopulateAllTabs(panel)
        local saved = panel.currentFilterType
        for _, t in ipairs({"families", "expansions", "locations"}) do
            panel.currentFilterType = t
            PopulateUnifiedFilterCheckboxes(panel)
        end
        panel.currentFilterType = saved
        PopulateUnifiedFilterCheckboxes(panel)
    end

**The name described an architecture this file does not have.** There is one
`panel.filterContent`, one `panel.filterCheckboxes` and one `panel.filterHeaders`, shared by
all three tabs, and `PopulateUnifiedFilterCheckboxes` opens by hiding everything those lists
hold and resetting them to `{}`. So each pass **discarded** the pass before it and only the
fourth survived. The first three built frames that were hidden again before the function
returned.

Nor could anything else consume them: `OnTabClick` sets `currentFilterType` and repopulates,
so a tab switch rebuilds from scratch regardless. There is no per-tab retention to warm.

Both call sites (`ResetAllFilters`, and the initial population in the panel constructor)
become one direct call, and the function is deleted -- keeping it would keep the false claim
its name makes.

**The same defect was already fixed twenty lines away.** `OnTabClick` carries a comment
reading "One rebuild, not two: UpdateDynamicFilters *is* PopulateUnifiedFilterCheckboxes
with a nil-panel guard, so calling both rebuilt the whole checkbox list twice on every tab
click." That is this bug, smaller. It survived here because it was **named for a place
rather than for its shape** -- "repopulate all tabs" reads like a description of intent, so
nobody re-derived whether the intent was achievable. Third instance of that pattern in the
plan, after the six copies of the selection rule and the two copies of the render delay.

**The one real behavioural difference is timing, not output.** The discarded passes warmed
`_filterCheckboxPool`, `_locationRowPool` and `_continentHeaderPool`, and the three dynamic
filter selectors. Those pools now fill on first use of each tab instead of at panel
construction -- moving a few dozen row creations *out* of the panel-open frame, which is
already the expensive one. Checked that nothing else depended on the ordering:
`panel.locationContinents`, the only per-panel table the locations path reads, is built at
line 650, long before population.

luacheck 38 unchanged, tests 161 unchanged (frame construction is not reachable headless --
this one is for the user to confirm in game).

---

### Backlog: the write-only layout fields, and what was resting on them

Four fields, all assigned only `nil` and never read:

    ns._lastLayoutWidth / _lastLayoutHeight               (core, UI.lua)
    PSM._lastModelsLayoutWidth / _lastModelsLayoutHeight  (browser, ModelsDataLoader.lua)

**The two pairs have different histories, and the difference is the interesting part.**

The *core* pair was real once. At the initial commit it backed a resize-threshold check --
`math.abs((PSM._lastLayoutWidth or 0) - width)` against a tolerance, with the fields written
after each layout. `fd5a549` ("Remove dead code: 19 unused functions and their orphaned
machinery") deleted the function holding both the reads and the writes, and left the two
`= nil` lines behind. Orphaned machinery, in the commit named for removing orphaned
machinery -- the residue is always in the *other* file from the thing deleted.

The *browser* pair was never anything. `git log -S` reports one commit touching either name,
and at that commit the file contains only the two `= nil` lines. No read, no non-nil write,
in any file, in any revision. It is the core pattern copied to a place where the check it
belonged to was never built -- the familiar duplicate-with-drift shape, except this copy was
born empty.

#### The deletion was bigger than the fields, because something was resting on them

In the browser those two fields were the **entire stated justification** for a whole
function. `ModelsDataLoader:CreateRenderCache` was `ReleaseCache()` plus the two nils, and
the call site said so in as many words:

    -- CreateRenderCache rather than ReleaseCaches: a freshly built panel also invalidates
    -- the remembered layout sizes, which are measured against the panel being replaced.

Remove the fields and the wrapper has no behaviour of its own at all.
`NPCDataLoader:CreateRenderCache` was *already* a bare forwarder, existing only to mirror
its sibling. So deleting only the fields would have left two pointless indirections and a
comment whose honest form is "this forwards for no reason" -- strictly worse than either
finishing or not starting. Both wrappers go; `ModelsPanel` calls `ReleaseCache` directly,
which is what the code already did.

Core's `ns.UI:CreateRenderCache` stays: it cancels the debounce timer and drops the selector,
so it has content the name is doing real work for.

**A dead field can hold up a live abstraction.** The usual reason to leave a write-only field
alone is that it costs nothing -- but this one was paying for a function's existence, and the
comment above the call site was propagating the claim to every future reader. That is the
same shape as the pipe-splitting in locations and as `RepopulateAllTabs`: a leftover that
still works is a lie about the domain, and the cost is what people build on top of it.

Net -9 lines. Tests 161 and luacheck 38 both unchanged.

---

### Backlog: Widgets.Tab had no label clipping and no audit

**WoW does not clip child regions.** A FontString wider than the frame it sits in is drawn
straight past it, over whatever is alongside. `Widgets.Button` has guarded that since it was
written: explicit width, no wrapping, and the overshoot recorded in
`Widgets.truncatedLabels`, because a chopped word looks exactly like a short word and the
tier chosen too small has to be findable. `Widgets.Tab` had none of it, and its pills sit
10px apart -- an overflowing label lands on the next pill's text.

**Why it went unnoticed is the useful part.** A button owns a font string reachable through
`GetFontString()`; a tab is a plain Frame with a separate `.label`. Same defect, different
accessors, so nothing connected them -- and `ClampLabel` was written against a Button's API,
which quietly made it unshareable. Generalised to `ClampFontString(frame, fs, text, padding)`
with `ClampLabel` and `ClampTabLabel` as the two thin adapters.

#### Padding zero, deliberately

Button pads 12 (6px each side) to clear a Blizzard bevel. Copying that to Tab would have
**regressed** the look: ModelsFilters' three tabs are a fixed 60px and "Expansions" very
nearly fills it, so 12px of padding would ellipsise a label that fits today. Zero clips at
the tab's own edge, so the only text this touches is text already drawn onto its neighbour --
which is the defect and nothing more. Padding a pill for looks stays the call site's job,
and both pill bars already do it.

Font metrics cannot be measured headlessly, so picking a padding I could not verify would
have been a guess dressed as a fix. Zero is the one value that cannot regress.

#### One thing the clamp changes on its own

Giving a centred font string a width makes justification **observable for the first time**.
While it had none it was exactly as wide as its text, so a font object defaulting to LEFT
looked centred; with a width it would shift every short label off centre. `justify = "CENTER"`
is now explicit, and pinned by a test, because it is invisible until someone changes the font
object and then looks like a layout bug with no cause.

#### The audit: `Tests/spec/widgetlabels_spec.lua`

Every factory that draws text has to appear in `TEXT_FACTORIES` with an answer -- `true` for
"clamps", or a string saying why not. Both directions are checked, so an exemption cannot
quietly acquire a clamp and keep its stale reason. Seven entries: Button and Tab clamp;
Label (the primitive -- clamping it would clamp everything else from underneath), CheckBox
(label anchored *outside* the frame, so frame width is not its bound), EditBox (owns and
scrolls its own text region), and Slider (Blizzard's `$parentLow/High/Text`, positioned by
the template) are exempt with reasons verified by reading each one.

**`SectionHeader` is recorded as a known GAP rather than fixed.** It has the same unclamped
`.label`, but left-anchored at a caller-controlled `labelInset` -- so "available width" is a
different subtraction, and guessing it is exactly how Tab's padding would have truncated
labels that fit. Recorded so it is a decision someone took rather than a thing nobody
noticed. Candidate for the sweep.

Injection-tested four ways, each producing exactly one failure: Tab's clamp removed;
SectionHeader given a clamp; a new text-drawing factory added; Tab's `justify` removed.

Tests 161 -> 166. luacheck 38, unchanged.

#### Method note: `git checkout <path>` is not "undo my injection"

The first injection run reported a cascade -- injections 2, 3 and 4 each failing three tests
instead of one -- and the reflex reading was that the new spec was fragile. It was not.
`git checkout PetStableManagement/UI/Widgets.lua` reverts to **HEAD**, and the file held the
uncommitted implementation being tested, so injection 1's revert deleted the clamp and the
justify along with the injection. Everything after ran against code that no longer had the
feature, and the "extra" failures were the missing implementation reporting itself correctly.

The earlier `loaderinputs_spec` injections were sound by luck rather than judgement: those
targeted files that had no uncommitted edits.

**Revert an injection from a copy of the file taken immediately before it, not from version
control**, whenever the file also carries uncommitted work. And the tell was there in the
output -- injection 4 reported "Updated 0 paths from the index" while claiming to have
changed the file, which is version control saying the edit never applied. A contradiction in
the evidence is worth chasing before the conclusion it seems to support.

---

**Backlog: panels can exceed the screen at high UI scale** — moved to `Backlog.md`
(2026-08-21). The stopgap (`SetClampRectInsets`) shipped 2026-08-21; the real fix
(auto-fit height / Models Browser resizability) is still open there.

---

### psm-data sweep

`ruff check .` passes clean, so nothing here came from a linter. All of it came from reading.

#### Fixed: the sync path was documented wrong in two files

`config.py` writes the five generated tables to
`psm-addon/PetStableManagement_ModelsBrowser/Data/` (`ADDON_DATA_DIR`). Both `CLAUDE.md` and
the **public** `README.md` claimed `.../PetStableManagement_ModelsBrowser/ModelsBrowser/`.
Verified against the filesystem: all five files are in `Data/`, none in `ModelsBrowser/`. The
docs are stale from before the generated/hand-written split, which the *addon's* CLAUDE.md
records correctly -- so the two repos disagreed about where the bridge lands.

The README carried a second stale claim in the same paragraph: it named the constant
`ADDON_MODELS_BROWSER_DIR`, which does not exist in `config.py` and never appears anywhere in
the repo. Both corrected.

#### Fixed: a backoff cap that capped nothing

`MAX_BACKOFF_SECONDS = 600`, never read. The comment beside `COOLDOWN_SECONDS` asserted the
mechanism it belonged to: *"Initial penalty; if we still get rate-limited after this, we
exponentially increase the backoff time up to MAX_BACKOFF_SECONDS seconds."* The only
assignment in the file is `global_backoff_until = time.time() + COOLDOWN_SECONDS` -- flat 120
seconds, no escalation, no cap.

Exactly the `_renderGeneration` shape: a constant plus a comment jointly describing a policy
the code never implemented, in the file whose whole job is not getting blocked. User confirmed
the flat cooldown is what they want, so the constant is gone and the comment now says what
happens.

#### Decided, not yet implemented: skip-list semantics

`Manual/skip_npc_ids.csv` (`npc_id, zone_id, layer, reason`) is read by three scripts with
three different meanings. `09` treats a row carrying a `zone_id` as zone-scoped and keeps the
NPC globally; `02` and `03` ignore the column and skip the NPC everywhere.

Measured: **61 NPCs** have a zone-scoped row and no global row, **47 of them present in
`Extracted/petopia_npcs.csv`** -- so the Petopia path drops 47 NPCs the Wowhead path keeps.
Reasons: `incorrect zone_id` (40), `redundant info` (20), `cannot be tamed` (1). The
divergence runs both ways: that single `cannot be tamed` row carries a `zone_id`, so `09`
under-skips a genuinely untameable NPC while `02`/`03` exclude it correctly by accident.

**The user's account of how it got there, and the target design.** The file began as a plain
skip-by-npc_id list and was later extended to scope skips to a zone or a layer. The readers
were written at different times against different versions of that intent, which is why the
oldest two never learned about the new columns.

Target, in the user's words: **skips should not be applied during extraction at all -- they
belong in the cleaning stage.** Then:

* **Petopia** rarely needs an NPC skipped, and when it does the skip is total -- but *only*
  when `reason` is `"cannot be tamed"`.
* **Wowhead NPCs** must differentiate by `zone_id` and `layer` whenever those are present.

Note this makes `reason` load-bearing for the Petopia path, which is a change in kind: it is
currently a free-text curation note, and the new rule gives one exact string semantic weight.
Worth deciding whether that string becomes a controlled vocabulary before it is depended on --
a typo in a curation note would silently stop skipping an untameable NPC.

Deferred by the user until the safe fixes landed.

#### Still open

* `DEFAULT_GROUP = "Miscellaneous"` in `14_generate_conditions_lua.py`, never read; grouping
  comes entirely from splitting `"Category: Value"`. Need to check what happens to a condition
  with no colon before deleting it -- this may be a fallback that was meant to catch exactly
  that case.
* `load_csv` exists as **three byte-identical copies** (06, 12, 13). `fetch_page`,
  `get_session`, `load_npcs`, `load_skip_display_ids` and `ask_refresh` exist 2-3 times each,
  diverged. `config.py` is the natural home, though these are deliberately standalone scripts.

#### Verified accurate, left alone

Every network-resilience claim in `CLAUDE.md` matches the code: `09` has lock/backoff/
stop_event/Retry, `02` ports all four, `07` has backoff only and no cross-thread coordination,
`01`/`04`/`05` have none. `--delay` is `default=None` in both `07` and `09`. The Whiptail 315
constant is hardcoded in `04` as documented. Checking the claims that turn out to be true is
most of the work of finding the one that is not.

---

### psm-data: skips move from extraction to cleaning

#### What the survey actually found

Not "this needs building" -- `10_clean_wowhead_data.py` **already implemented the full
design**, with a docstring spelling out the hierarchy: bare `npc_id` = global, `+ zone_id` =
zone-scoped, `+ layer` = layer-scoped. The problem was three *other* readers of the same file
disagreeing with it and with each other:

* `02` (extract, Petopia) -- matched on `npc_id` alone, so zone-scoped rows (statements about
  one Wowhead zone) removed NPCs from Petopia entirely.
* `03` (clean, Petopia) -- defined `load_skip_npc_ids` and **never called it**. Dead loader;
  the import of `SKIP_NPC_IDS_CSV` had been dropped with it, which is how ruff caught the
  wiring the moment it was used.
* `09` (extract, Wowhead) -- global tier only, provably the same set as `10`'s global tier.

So the Wowhead side had the rule twice and agreed with itself; the Petopia side had it in the
wrong stage and got it wrong.

#### The rule, after the user reconsidered it

First proposal was to gate the Petopia skip on `reason == "cannot be tamed"`. The user
replaced it with a **structural** rule: a row with only an `npc_id` is a global skip that
Petopia honours; a row carrying a `zone_id` is not Petopia's business.

Better for a reason worth recording. The reason-gate made a free-text curation note
load-bearing -- a typo would silently stop skipping an untameable NPC, with no error and no
symptom until bad data reached the addon. The structural rule depends on a column's
*presence*, which cannot be misspelled, and `reason` stays a note that nothing reads.

It also makes Petopia's skip set **exactly** `10`'s global tier by construction rather than by
convention. Verified against the real file: both produce 3405 ids, sets identical.

#### The Wowhead cost, raised and overruled

Removing `09`'s extraction skip means scraping 3374 more NPCs per full run -- **3.7 to 9.4
hours** at the 4-10s delay range. Raised it with numbers, since `09`'s skip was redundant but
*correct*, so the deletion bought tidiness and cost hours.

The user reaffirmed: extraction should not load a skip list, regardless of impact. That is the
right call on a principle the measurement does not touch -- a skip applied at extraction
cannot be undone without re-scraping, so a curation mistake becomes hours of lost data rather
than a re-run of a cleaning step. The runtime is paid once per refresh; the coupling was paid
on every curation change.

#### Changes

* `02` -- skip filter, loader and import removed; extraction just scrapes.
* `03` -- `load_global_skip_npc_ids`, applied after dedupe. Named for the rule rather than
  keeping `load_skip_npc_ids`, since the generic name is exactly what let three scripts mean
  three things by it.
* `09` -- loader, `filter_skipped_npcs`, both call sites, the import, and the end-of-run
  summary lines removed. The **module docstring** said "except the npcs in skip_npcs.csv" and
  now says extraction applies no skip list and why -- the docstring was the most visible copy
  of the claim being deleted.
* `10` -- untouched. It was already right.

ruff clean, all scripts parse. **Output-changing**, unlike everything before it in this sweep:
Petopia should *gain* roughly 56 NPCs after `02` and `03` are re-run, and Wowhead extraction
will cover 3374 more.

---

### A10 — scoped, not started (2026-08-17)

Measured before writing anything, since A10's cost is entirely in the retrofit rather than
the scaffold.

**The surface**, across both addons excluding `Data/`:

    print(                       84
    SetText(                    138
    text = "..." in opts        109
    label/title/head/sub = "..."  98
    tooltip lines = { }          23

Roughly 450 sites before subtracting the ones that are not user-facing (debug prints,
`/dump` output, slash-command names). `Config.MESSAGES` is 11 strings with 10 consumers --
the existing informal version, and the natural first slice because it is complete and
testable on its own.

#### Three decisions to make before any code

**1. A10 collides with the A3 boundary, and this is the real first decision.** `L` cannot
simply be `ns.L`: the Models Browser is a *separate addon* with its own namespace, so it
would reach `L` through `_G.PSM` -- which means **`L` joins the eleven-name public API**.
That surface was deliberately kept minimal on the grounds that a name on it "can never change
again without touching both addons". So the opening question is a boundary question, not a
string question. Alternatives worth weighing: give the browser its own locale table, or hand
it a *service* (`PSM.L(key)`) rather than the table, which is the pattern
`RowManager:ReleaseModel` established.

**2. Missing-key behaviour.** `L["Typo"]` returning nil renders as a blank label -- silent,
and the same failure class this codebase already has three named defences against. Match
them: return the key itself so the UI degrades to English, and record the miss in `L.missing`
for `/dump`, alongside `Widgets.unknownOptions` and `Skin.unhandled`.

**3. Key style.** English-as-key (`L["Release Pet"]`) reads naturally at the call site and
makes an untranslated locale fall back for free; symbolic keys (`L.RELEASE_PET`) survive copy
edits without touching translations. For enUS-only, English-as-key is the cheaper bet.

#### Suggested increments

1. `Core/Locale.lua` + resolve the `PublicAPI` question above.
2. Fold `Config.MESSAGES` -- 11 strings, 10 consumers, a complete slice.
3. A spec pinning the missing-key behaviour, so the retrofit has a net under it.
4. Then the retrofit, file by file, with the spec catching typos as they are introduced.

**Why it was not started here.** This is the one task in the plan where a mistake is
*invisible* -- a wrong `L` key is a blank label, not an error -- and it is the task most
likely to be replicated across a hundred call sites before anyone notices. Step 3 exists so
that stops being true, and steps 1-3 want a fresh session rather than the tail of a long one.

### A10 — steps 1-3 done (2026-08-18)

Decisions taken: `L` published as a **callable table** (a bare function cannot carry
`L.missing`), call syntax `L("...")`; **English-as-key**; missing key returns the key and
is counted in `L.missing`.

`Shared/Locale.lua`, not `Core/Locale.lua` as scoped -- a `Core/` directory beside the
existing `Core.lua` file reads as a mistake.

**English-as-key removed the hazard this task was flagged for.** The plan said "a wrong key
is a blank label, not an error". That is true of symbolic keys only; with English keys a
typo renders as the typo'd English, which is visible. `locale_spec.lua` then moves it from
"visible to whoever opens that panel" to "named at build time", and was verified by
injection: two typos, one per addon, both reported with file, line and key, while an
undeclared key sitting in a comment was correctly ignored.

`boundary_spec` refused `L` until a browser file used it -- exports must have a live
consumer -- so the first browser slice (the shared strings) shipped in the same increment.
That is the right constraint: it makes every future public name prove itself.

Fragment insertion removed: `"Stable must be open to %s!"` became three whole sentences.
A clause slotted into a sentence cannot be reordered by a translator.

#### Two bugs the fold surfaced, deliberately left unfixed here

Both are the "leftover with something built on the claim it makes" shape, and both were
carried across unchanged so the fold stayed mechanical:

1. `SNAPSHOT_CREATED` was never dead. `Data:CreateSnapshot` prints its own inline copy --
   "PetStableManagement: Saved N pets to database." -- while the constant says "Pet data
   snapshot created: N pets saved." A duplicate that drifted, and the constant lost.
2. `PANEL_CREATION_FAILED` is unreferenced because `RowManager:EnsureRow` reports a missing
   `parent` -- a creation failure -- with `PANEL_SHOW_FAILED`.

#### Remaining

Step 4, the retrofit: ~302 prose strings in core, ~152 in the browser, minus the
non-user-facing ones. Far smaller than the 450 scoped -- most `SetText(` calls pass a
variable, not a literal; only 46 of 138 carry one.

Open wrinkle: colour markup lives inside the locale *values* (`|cFFFF0000...|r`), so a
translator can break it. Kept there to avoid restructuring call sites during a mechanical
fold; worth revisiting if a second locale ever lands.

### A10 — correction, and the guards deleted (2026-08-18)

I claimed the three "Stable must be open to ..." guards protected a real case -- stable
closes, buttons still visible, stale closure lets the click through -- and recommended
fixing them rather than deleting. **That was wrong, and in-game testing disproved it.**
`PET_STABLE_HIDE` hides the panel and calls `ClearUIRows` in the same handler, before
`isStableOpen` is cleared, so the window I described does not exist. Closing the stable
master closes our panel too, by design.

The messages were redundant, as first suspected. Deleted, with their guards.

Worth keeping: the reasoning that produced the wrong answer was reading the closure in
isolation. The closure *is* a stale snapshot; what makes it harmless is a fact in a
different file. Static reading found the shape and got the consequence backwards.

`locale_spec` gained the reverse check -- a registered string with no call site fails the
build -- which mirrors `boundary_spec`'s rule for exports and would have found these
three without the discussion. Both directions verified by injection.

### A10 — step 4 in progress (2026-08-18)

Slices done: Dialogs (47 sites), PopUpManager (36), Filters + Export (51). Locale at 126
strings. Remaining in slice 2: GroupedView, TeamsPanel. Then the browser, TamingChecker,
and Shared's remainder.

**Computed keys are the one real hazard, and it bit twice.** `ns.L(SORT_LABELS[sortBy])`
reads better than localizing the table's values, and is worse: a key built at runtime is
invisible to *both* directions of `locale_spec`, so it can neither be checked as declared
nor distinguished from an orphan. Five sort labels shipped undeclared and were found by a
`/dump PSM.L.missing` in game -- precisely the failure the spec was written to prevent.

Rule for the rest of the retrofit: **every L() argument is a literal.** Localize the table
of strings, never the lookup into it.

**The export columns are a genuine design question, not a mechanical one.** `col.label` is
both the checkbox text and the CSV header row. Localizing it makes the exported file's
headers change with the client's language, which breaks anything machine-read. Left
English for now; the fix when wanted is a separate field for the UI label. `Yes`/`No`/
`Active`/`Stabled` are CSV *data* and stay English regardless.

**Not a bug, recorded so it is not re-investigated:** the sort dropdown's list appears far
from its button when the panel sits against the right screen edge. `sortDrop` is anchored
`TOPRIGHT, -17`, so it is the rightmost element; Blizzard's `ToggleDropDownMenu` finds no
room and shifts `DropDownList1` left to keep it on screen, landing it near the leftmost
dropdown. Standard clamping. Same root cause as the open backlog item about panels fitting
the screen at high UI scale, and not separately fixable without hand-rolling the menu.

Also fixed while testing this slice: waypoint count reported coordinates *found* rather
than placed (wrong without TomTom, and contradicted the hint printed straight after), and
"< Pet Models" sat at BUTTON_W.S and clipped -- the fourth button to need the tier bump
Theme.lua already documents for three others.

### A10 — step 4, what the final scan found (2026-08-19)

Locale at 300 strings after eight slices. A wide scan across *every* file in both .toc
files -- not just the ones a slice had touched -- shows A10 is roughly two thirds done,
not finished: about 130 user-facing sites remain across 15 files nobody had opened.

Untouched and still English: `Core.lua` (the two stable-frame buttons), `Loader.lua`
(why the browser failed to load), `Minimap.lua` (tooltip), `OptionsPanel.lua` (~18
settings labels), `PanelManager.lua`, `Menu.lua`, `Panel.lua`, `Row.lua`, `PetTooltip.lua`,
`PetGroups.lua` and `TeamsData.lua` (their returned `err` strings, which are printed),
`SpecialTames.lua`, `PetRoulette.lua`, the two data loaders, `ModelRow.lua`.

**The scan is the only thing that can say a file is done.** An empty `PSM.L.missing`
proves every key that *is* called was declared; unconverted text never calls L, so it is
invisible there. Three separate times a file was reported finished and was not.

**Three checks, three different failure modes, and they do not overlap:**
- `locale_spec` direction 1: a call site whose key nobody declared.
- `locale_spec` direction 2: a declaration no call site asks for.
- **luacheck**: a key declared *twice* -- invisible to both directions, since both copies
  have live call sites. It caught `["Reset View"]`.

**Two bugs the scan surfaced, unfixed so far:**
1. `SpecialTames.lua` prints "Multiple **Multiple** Skills" / "Multiple **Multiple**
   Conditions". A plain typo, user-visible in chat after applying the filter.
2. That block is a near-duplicate of `ModelsFilters`' summary builder, which words it
   correctly -- the drifted-copy shape again, and the reason the typo could exist in one
   place while the other was right.

**Open decision: `TamingChecker`.** Its `TAMING_RULES` is reference text about game
content, not UI chrome. `itemName`/`questName`/`autoRace` are real WoW entity names the
client localizes itself and must stay English; `label` and `desc` are our own prose. Since
the whole pet dataset is English, a translated `desc` would sit among English family, zone
and item names. **Decided (2026-08-19): left as is.** The boundary stands -- **A10 localizes the
chrome, not the game-content reference text.**

### A10 — done (2026-08-19)

433 strings. Every user-facing string in both addons resolves through `L`. `Core/Locale.lua`
became `Shared/Locale.lua`; `L` is a callable table published as the fifteenth public name;
keys are English.

**What actually made this task hard was not the strings.** It was knowing when a file was
finished. Each scan I wrote matched the syntax I expected — `text = "..."`, then positional
arguments, then colour-prefixed literals, then bare `or "..."` fallbacks — so each missed a
shape I had not thought of, and **three files were reported complete while still holding
English**. The exhaustive scan, which listed every literal and subtracted a denylist, found
four times what the targeted ones had.

`PSM.L.missing` being empty proves every key that *is* called was declared. Unconverted text
never calls L, so it can never appear there. Only a source scan can say a file is done.

**Four checks, four distinct failure modes, no overlap:**
1. `locale_spec` — a call site whose key nobody declared.
2. `locale_spec` — a declaration no call site asks for.
3. `locale_spec` — `L(` with its key on the next line, invisible to a line-based scan.
4. **luacheck** — a key declared twice; invisible to 1 and 2 because both copies have live
   call sites.

**Rules that emerged, worth keeping for any similar retrofit:**
- **Every `L()` argument is a literal.** Localize a table of strings, never the lookup into
  it: a computed key is invisible to checks 1 and 2.
- **Plural is not a suffix.** Four sites stitched an "s" on; each became two whole strings.
- **A clause slotted into a sentence cannot be reordered by a translator.** Fragment
  insertions became whole sentences wherever the fragment was ours.
- **Punctuation joins stay hardcoded; word joins do not.** `", "` and `"; "` are literal;
  `" or "` is a key.
- **A string that is also a comparison key or a stored value must stay English** — it is
  data wearing a label's clothes. `PILL_TAGS`, `"Other"`, `"Exotic"`/`"Non-Exotic"`,
  `pet.specName`'s `"Unknown"`.
- **Localize errors a player can act on; leave preconditions they cannot.**

**Five drifted duplicates surfaced**, each a copy that had diverged from its twin: the
snapshot message, `SORT_LABELS`, the Special Tames summary ("Multiple **Multiple** Skills"),
Core's team tooltip vs TeamsData's, and the reorder drag hint.

**Bugs fixed along the way, none of them localization:** waypoint count reporting pins never
placed; `< Pet Models` clipped at `BUTTON_W.S`; `SNAPSHOT_CREATED` superseded by a drifted
inline copy; `PANEL_CREATION_FAILED` never wired; a duplicate-group-name rejection invisible
in chat; and `RenameGroup` skipping both name checks `CreateGroup` makes.

**Not done, deliberately:** `TamingChecker`'s reference text, and the export column labels,
which are the CSV header as well as the checkbox text.

---

#### Reverted: A7's virtualized NPC list, back to pagination (2026-08-20)

Built `UI/List.lua` (Blizzard's `ScrollBox` + `CreateScrollBoxListLinearView`) and a
new `NpcView.lua` adapter reusing `NPCRow.lua`'s row-building code unchanged, plus
made the Models Browser panel resizable (previously `resizable = false`) since A7's
own acceptance criterion ("scroll position survives a panel resize") requires
resizing to exist in the first place. No Lua errors on first load — the unverified
Blizzard API surface (`SetElementInitializer`, `ForEachFrame`,
`SetDataProvider`) worked as guessed, first try.

**Reverted anyway, on the user's in-game read, for three separate reasons:**

1. **Resizing itself.** "Not looking good, for many reasons" — not diagnosed in
   detail. Resizing was the one part of this task built from nothing (`CreateBasePanel`
   already supported it via `resizable`/`minWidth`/`minHeight`/`showResizeHandle`;
   this panel had simply never opted in), and it's the piece dropped first, cleanly,
   with no follow-on issue in the rest of the panel.
2. **View inconsistency.** Checking an older commit confirmed NPC view had always
   had pagination, matching grid view. Making only NPC view scroll left the two
   modes of the same panel behaving differently — a real, immediately-visible
   regression, independent of resizing.
3. **A memory comparison that didn't hold up, and the reason is worth keeping.**
   First read: fresh login (browser unloaded) → open straight into NPC view → 19.7MB,
   against A2's 13.6MB "Models Browser open" figure. Read as a regression at the
   time. It probably wasn't a clean one: a same-session **later** re-test, on the
   already-*reverted* (original pagination) code — open Models view, then switch to
   NPC view without touching anything else — showed the identical shape, 13.8MB →
   22.3MB, from the view switch alone. That matches A2's own documented "memory
   ratchets and never fully returns" behaviour, not anything specific to `ScrollBox`
   vs. pagination: both approaches call the same
   `NPCDataLoader:_CalculateNPCData()` over ~7000 records, and that allocation was
   always going to happen exactly once per session, the first time NPC view is
   touched, regardless of how the rows are then displayed. **The memory case against
   A7 should be read as unproven, not disproven** — a real controlled A/B (same
   build, same fresh-login state, only the rendering swapped) was never actually run.

Reasons 1 and 2 stand on their own regardless of 3. The working tree was never
committed, so the revert was a clean `git checkout` of six files plus deleting the
two new ones — confirmed with an empty `git status` and a green test run afterward.

**Net technical finding, independent of the revert:** there was never a *structural*
memory case for virtualizing NPC view specifically. The pre-A7 row pool already
recycled a bounded, viewport-sized set of plain-text frames rather than building one
per NPC — the same shape `ScrollBox` provides, just hand-rolled. A7's real
justification elsewhere in this plan was deleting duplicated pagination machinery
and resize-safety, not memory; folding both into one acceptance criterion is what
made the memory number look like it was answering a question it wasn't built to
answer.

**For anyone revisiting this:** A8 ("Depends on: A6, A7") still nominally depends on
a task that is now un-done. If A8 is picked up before A7 is re-attempted, read this
note first — A8's own scope (`PlayerModel` pooling for the grid view) doesn't
actually need NPC view's list mechanism, so the dependency may be looser than
written. If NPC-view virtualization is re-attempted: run a controlled memory A/B
*before* building the rest, not after, and drop the resize scope entirely unless a
future request specifically asks for it again.

---

#### A8 — done (2026-08-20): the Grouped View ratchet wasn't a pooling gap

Followed this doc's own advice above and looked at what Grouped View pools by hand
before reaching for `CreateObjectPool`. Found the actual mechanism: `DragDrop.lua`'s
`SetupModelDragDrop` — called from `Row.lua`, `GridView.lua`, *and* `GroupedView.lua`
on every `UpdateRow`, i.e. every render of every visible row — read the model's
*current* `OnMouseDown`/`OnMouseUp`/`OnEnter`/`OnLeave` via `GetScript` and wrapped it
in a fresh closure each time. Rows are pooled and never destroyed, so every render
added one more layer to the chain, permanently, on frames that live for the session.
`GroupedView.lua:147` did the identical thing again by hand for its context-menu
check, stacking a second unbounded chain on the same models. Neither wrap needed to
re-read anything: both handlers already pull pet/context data live off `self`.

Fixed by wiring each chain once per model (`model.__dragDropWired` /
`model.__groupContextMenuWired` guards) instead of on every render. luacheck
10/0 unchanged, 176/176 tests still pass.

**Why this matters for A8's scope:** the leak was closure accumulation from
re-wiring event handlers, not un-freed frames — the row/model pools themselves were
already correctly bounded and reused. `UI/Pools.lua` and a capped LRU `ModelPool`
were the task's original proposed fix, aimed at the wrong layer — nothing here
needed a new pooling infrastructure, so neither was built.

#### A8, verified in-game (2026-08-20): the acceptance criterion, run against the browser

`GetAddOnMemoryUsage` before/after forced GC, both addons, across one full
open → engage Model view → engage NPC view → close cycle:

| step | `PetStableManagement` | `_ModelsBrowser` |
|---|---|---|
| before load | 3045.4 KB | — |
| loaded | 3177.1 → 3179.5 KB | 6947.9 → 6958.0 KB |
| Model view engaged | 4016.3 KB | 13540.1 KB |
| NPC view engaged | 4017.8 → 4017.7 KB | 21042.9 → 21043.1 KB |
| **closed + forced GC** | **3180.3 KB** | **6961.3 KB** |

Both peaks (~13.5MB with Model view's ~7000-record set loaded, ~21MB with NPC
view's added on top — the two loaders keep separate result tables, so visiting
both in one session holds both until release) collapse back to within ~15KB of
the post-load baseline once the panel closes. No ratchet across this cycle,
core or browser. This also validates a fix that landed during A5.1 step 6
(`ModelsDataLoader:ReleaseCache` dropping the selector closure itself, not a
table field it closed over) — without that fix specifically, this is the exact
number that would have stuck at ~21MB instead of releasing.

**Acceptance criterion met**, on the browser rather than the Owned Pets repro that
opened this task — the number *does* move now, on both sides. A8, closed.

---

#### A9 — done (2026-08-20): `Shared/Log.lua`, `/psm debug`, and the GC calls deleted

**The counts in the task text were stale, same pattern as A10's and A13's.** A real
grep found **10 `pcall`s, not 25**, and **6 `collectgarbage("collect")` calls, not
3** — five tasks' worth of intervening work (A5-A8, A10) had already touched most of
this file. Verified against the file rather than the plan before touching anything.

**`Shared/Log.lua`**, loaded right after `Config.lua` (before `Utils.lua`, which now
depends on it): a 20-entry ring buffer, `Log:Record(message, traceback)` /
`Log:Dump()` / `Log:Clear()`. `/psm debug` (added to `SlashCommands.lua`'s
`PETSTABLE_COMMANDS`) prints the buffer, oldest first, each entry's traceback on its
own line underneath.

**`Utils.SafeCall` is the one boundary, not a new one alongside it.** It already
existed — `Events.lua`'s `OnEvent` handler was already routing through it — and
already had the right shape (swallow, print to chat, return nil), it just used `pcall`
and threw the failure away unlogged. Rebuilt on `xpcall` + `debug.traceback("", 2)`
so the message handler runs while the stack is still live (a `pcall` catch site
cannot reconstruct it after the fact), recording both into `Log` before falling
back to the same short chat print, now pointed at `/psm debug`. Lua 5.1's `xpcall`
takes no arguments past the handler — unlike `pcall` — so the call's varargs are
captured and applied inside the protected closure instead of passed to `xpcall`
itself. Single-return contract preserved (`local result = func(...)`, matching
what every existing call site already assumed); nothing needed a second value.

**Entry points actually wrapped**, chosen for where an error was verified to vanish
completely rather than by sweeping every `OnClick` in the tree (that would be a
different, much larger task — see "not done" below):

- `SlashCmdList["PETSTABLE"]` / `["PETSWAP"]` — unwrapped before this; a throw inside
  either handler had no boundary at all.
- `UI.lua`'s `RenderPanel` debounce timer, the thing that actually calls
  `_RenderPanelImmediate` → row rendering. This is the acceptance criterion's "row
  renderer": a throw inside `UpdateRow` used to propagate straight out of the
  `C_Timer` callback with nothing catching it.
- `Data:CollectStablePets` — not named in the task, found by tracing callers of the
  function the nested pcalls were protecting. It has **ten call sites** across
  `DragDrop`, `Reorder`, `TeamsData`, `TeamsPanel`, `Minimap`, `UI.lua` (×2), and
  three browser loaders, none of which wrapped it themselves. Wrapping the one
  function they all funnel through covers all ten for free — the same "centralize
  once" shape as `Skin.Apply`/`Tooltip.Attach` elsewhere in this codebase, applied to
  error handling instead of rendering.

**The nested pcalls in `CollectStabledPets` were nested for a reason, so "remove"
meant "un-nest," not "delete."** Nested pairs are pcall(*ForEach*) wrapping
pcall(*one node*), and pcall(*the whole fallback loop*) wrapping pcall(*one slot*).
The **outer** half of each pair was pure redundancy once `CollectStablePets` has its
own boundary — it caught nothing the new outer wrap doesn't already catch, and
today it caught it *silently*: `ok` was never checked, so a `ForEach` failure had
zero trace anywhere, not even the chat print `SafeCall` already gave every other
site. Deleted both outer wraps. The **inner** half — one `SafeCall` per node, one per
slot (up to 205 in the fallback path) — earns its place: a single malformed pet
record aborting collection for the other 204 is a real regression a top-level-only
boundary would introduce, so per-item isolation stayed, just swapped from a
silent `pcall` to `SafeCall` so a bad record now shows up in `/psm debug` instead of
vanishing a second way. The lone non-nested pcall (`dataProvider:GetSize`) became a
`SafeCall` too, for the same silent-swallow reason, not because it was nested.

**GC calls, all six, gone**, not three: `Data.lua`'s `CreateSnapshot` (unconditional,
ran on every stable-close snapshot save — the likelier source of the task's "frame-time
spike on panel close" than `PanelManager`'s, since it fires every close, not just
cleanup), the delayed one in `PanelManager:CleanupPanel` (the one the task named),
two in `Data.lua` gated behind `Config.FORCE_GC_ON_CLEAR` (default `false`, no options
UI ever exposed it, so dead weight either way — the flag itself is deleted, not just
its call sites), and two in the browser's `PetRoulette.lua` `Cleanup*` functions —
not in the task's file list (browser, and the browser's own `Cleanup` functions
didn't exist when the task was written), same copy-pasted anti-pattern as
`PanelManager`'s, same fix.

**Not done, deliberately:** a sweep of every `OnClick`/`OnEvent`/timer callback in
both addons to wrap each individually. `SafeCall` is now the reusable primitive for
that if it's ever wanted, but doing it everywhere is a different-sized task than "the
25 pcall sites, 3 GC sites" ever described, and the browser (still unconverted,
still on raw `_G.PSM`) was left untouched beyond its two GC calls — consistent with
A3's standing rule that core doesn't reach further into the browser than it already
does.

**Verified:** `luacheck` 10/0, unchanged from baseline. Test suite 182/182 (was 176;
added `Tests/spec/log_spec.lua` plus three `SafeCall` cases to `utils_spec.lua`,
including one asserting the recorded traceback names the failing call site). The
in-game half of the acceptance criterion — throw inside a row renderer, confirm it
surfaces in `/psm debug` with a stack, confirm the panel-close frame-time spike is
gone — needs the user's client, not this shell.

#### Follow-up, in-game (2026-08-20): the deleted GC calls looked like a leak, and weren't

First read after the GC deletion landed: `GetAddOnMemoryUsage` climbing from 1.7MB at
fresh login to "always above 3.3MB, slightly growing with GC or largely growing
without GC" after opening/closing the Owned Pets panel. Read at first as A9 having
uncovered or caused a leak.

**The control that settled it: `collectgarbage()` is a full collection, so if memory
doesn't return to baseline after one, it isn't garbage — it's live.** That single fact
means the deleted `collectgarbage("collect")` calls could never have been fixing
whatever this was; a forced collect reclaims exactly what an eventual incidental one
would, just sooner. At most they were trimming the ordinary incidental-GC backlog
sitting on top of a real number, which is a cosmetic effect, not a fix.

Ruled out by reading rather than guessing, before asking for more data: `GridView`'s
row/model pool builds once (`if not pool then ... end`) and is reused, not rebuilt,
on every open; `ns._petDerivedCache` is keyed per pet, bounded by pet count rather
than render count; `Store:Watch` has exactly one call site (`ModelsFilters`, browser
side) and never touches Owned Pets; A8's `__dragDropWired` / `__groupContextMenuWired`
guards (same session, same day) were confirmed already in place for grid view too.

**Instrumented rather than continued guessing**, since this shell can't drive the
client: a 189-character `/run` one-liner logging `GetAddOnMemoryUsage` alongside
`#PSM.state.rows` / `.modelViewRows` / `.groupedViewRows`, run after forced GC at
fresh login, after first opening each view, and across repeated open/close/sort
cycles. The result: two step changes, each landing exactly on a row count going from
0 to 50 for that view (1787KB → 3057KB when list+grid's pools first build, 3057KB →
3369KB when grouped's pool first builds) — the one-time cost of constructing ~150
pooled `PlayerModel` frames, textures, buttons, and tooltip/drag-drop wiring across
the three views. After both jumps, ~15 further cycles (open, close, sort, repeat)
held in a fixed oscillating band (3412KB / 3368KB, alternating), never trending
upward. **No leak.** The elevated resting size is the intended cost of building each
view's pool once and reusing it forever, and the flicker-once-then-smooth UX the user
separately noticed is that same construction cost made visible on first render per
view.

Net effect on this task: none — the GC deletion stands, and this is recorded so a
future session doesn't re-open A9 chasing the same phantom, or re-add the calls on
the strength of an untested first read.

---

#### A14, free tier — done (2026-08-20): the five redundant fields, none of them measured

**Scope: free tier only, as sequenced.** The structural tier (`abilities`,
`isExotic`/`specID`/`specName` derivation, columnar `snapshotData`) still needs A4 to
prove a migration round-trip, not just exist — A4 landed a test *harness*, not a
migration test, so that precondition isn't met yet. Untouched.

**`SavePersistentData`'s per-pet strip** — `modelSceneID`, `guid`, `tamer` set to
`nil` on the *deep-copied* record before it goes into `char.snapshotData`, never on
the live `ns.state.stablePets` entry the rest of the session still reads. Checked
what reads `modelSceneID` back before deleting it, since the task flagged it as "the
literal constant 783" without checking whether anything downstream expected a live
value: **nothing does, anywhere in either addon** — it is written in two places
(`CollectStabledPets`, `ProcessPetInfo`) and read in zero. `guid` and `tamer` are
actively re-derived by `LoadPersistentDataForDisplay` regardless of what's stored
(`p.guid = p.guid or p.petNumber`, `p.tamer = currentKey`/`charKey`, unconditional),
which is what makes dropping them from disk safe for pre-change SavedVariables too —
an old file's copies get overwritten the same way a new file's absence does.

**`SaveSettings`'s five `selected*` filters** — swapped `ns.Utils.DeepCopy(x) or {}`
for a new `DeepCopyIfNonEmpty(x)` (returns the copy only when `next(t)` is true, `nil`
otherwise) on all five. Safe by an invariant the loader already documented, not a new
one: `LoadFilterSettings`'s comment says an absent key already means "nothing saved
yet" and deliberately leaves `ns.state[k]` alone rather than forcing it to `{}` — so a
saved `{}` and an absent key were already indistinguishable in their effect on load.
Persisting the distinction was pure weight: up to 15 characters x 5 keys.

**Hit `selections_spec`'s static audit** ("never passes a selection table to an
unaudited function," the check that caught `SelectAll`'s three uncounted call sites
during A5) on `selectedTamingRules`/`selectedConditions`, both `PSM.Selections`-owned
slices — the original code passed them straight to `ns.Utils.DeepCopy`, an audited
callee, but the new helper is a different, unaudited one even though it only reads.
Added `DeepCopyIfNonEmpty` to `Tests/spec/selections_spec.lua`'s `READ_ONLY_CALLEES`
table alongside `DeepCopy` itself, the fix the check's own error message asks for.

**Per-character `minimapButton`, deleted rather than trimmed** — the whole
`minimapButton = (db.settings and db.settings.minimapButton) or {...}` field, not
narrowed. Confirmed first: every read anywhere in the addon (`Minimap.lua` x6,
`OptionsPanel.lua` x2) goes through the account-wide
`PetStableManagementDB.settings.minimapButton`; grepped for `char.settings.minimapButton`
or `.characters[...].settings.minimapButton` and found nothing. This one was flagged
by the task as a correctness finding as much as a size one (A5.0's "two homes for one
fact" pattern) — it wasn't just unread, it was a second copy that could have drifted.

**Verified:** `luacheck` 10/0. Test suite 182/182. No new spec for `Data.lua`'s
persistence functions themselves — they need `PetStableManagementDB`,
`ns.GetCharacterKey`, and a populated `ns.state` all stubbed together, which no
existing spec does for this file, and the acceptance criterion is explicitly an
in-game one. **Needs the user's client**: log in on two characters, visit a stable,
`/reload`, confirm pets still list with correct tamer/family/spec and the minimap
button in its saved position, confirm the saved file shrinks, and confirm a
*pre-change* SavedVariables file still loads without error.

#### A14, free tier — confirmed in-game (2026-08-20)

Two characters, pets/order/tamer/spec/minimap button all correct after `/reload`.
SavedVariables file shrank (~300KB → ~185KB, though not a clean A/B — compared
against an older addon version on a different machine, so the ratio isn't load-
bearing, just directionally right). Closed.

#### A14, structural tier — implemented (2026-08-21), in-game confirmation pending

**Shipped a different design than this section originally proposed**, arrived at by
verifying every assumption against real in-game data (`/run` dumps of a stabled and an
active pet's raw Blizzard record) rather than trusting what the old code implied:

- `abilities`/`specID` are dropped from `char.snapshotData`. `isExotic`/`specName`
  **stay persisted per pet, unchanged** — the original task's "check before removing"
  resolved to "don't," for two different reasons. `abilities` cannot be recomputed for
  an offline character's pet by any means the addon has (confirmed: multiple
  cross-character consumers, including `TeamsData:SlotRecord`'s unsafe
  `pet.abilities or ExtractPetAbilities(pet)` fallback, which would silently produce an
  empty table for an offline pet). `isExotic` can differ from its family's current
  default for an individual pet grandfathered before a Blizzard family-rule change (the
  user's Clefthoof example — Blizzard flipped that family non-exotic years ago, but
  pets tamed before the change are still exotic) — a per-family derivation would
  silently "fix" that pet's flag on next load, so only the per-pet stored value can
  protect it.
- **No relocation of `AbilitiesData.lua`, no cross-repo work, no schema/migration
  machinery.** The original plan (and this session's own first draft) assumed
  reconstructing `abilities` required sourcing psm-data's generated ability data into
  core, which would have meant either forcing the whole LoadOnDemand Models Browser to
  load (the exact "data-only loading" idea `psm-addon/CLAUDE.md` already records as
  tried and reverted) or relocating a generated file across two repos. Verified in-game
  instead that `petAbilities`/`specAbilities` are **pure functions of family/spec**
  respectively (two different Devilsaur pets carry byte-identical spell-ID arrays), so
  the addon now just remembers what it already sees live: a small account-wide
  "abilities pool" (`PetStableManagementDB.accountWide.abilitiesPool`,
  `Shared/Data.lua:48-117`) records raw spell-ID arrays keyed by familyName/specName
  during `CollectStabledPets`/`ProcessPetInfo`, and `NormalizePetData` reconstructs a
  pet's `abilities`/`specID` from it on load, resolving spell IDs to names via the
  already-existing `GetAbilityName`/`GetSpellNameCompat` path. Self-updating (tracks
  whatever Blizzard's current rule actually is, no generator regeneration needed) and
  provably gap-free: a pet can only ever be persisted via a live collection that
  already seeded the pool for its own family/spec, so there is no offline-character
  bootstrapping case this can miss.
- `isExotic`'s fallback source (used only when a record is missing the field entirely,
  never as an override) changed from the static `EXOTIC_FAMILIES` table to a
  pool-first, static-table-second chain (`exoticByFamily`, same self-updating
  philosophy) — with an explicit nil-check rather than `or`-chaining, since a pool
  value of exactly `false` must not fall through to the static table (the exact Lua
  `and/or` trap A4's own `SafeStringFormat` finding already flagged in this codebase).
- **New, unrelated-but-adjacent addition**: `isFavorite` is now captured and persisted
  per pet (`ProcessPetInfo` explicitly; `CollectStabledPets` already carried it through
  via its existing full-record deep copy, confirmed via the same in-game dump). Prep
  work for a future feature merging the stable master's native favorite flag with the
  addon's own separate Models Browser favorites list — not itself part of this task,
  the user asked to start collecting it now so historical data exists once that gets
  designed.

**Byte savings are now concentrated almost entirely in `abilities`** (the ~1,025
nested per-pet tables the original estimate was mostly about) — `specID`/`isFavorite`
are a few bytes either way, and `isExotic`/`specName` contribute nothing since both
stay. No columnar/structure-of-arrays rewrite of `char.snapshotData` was pursued
(discussed and explicitly descoped): with `abilities` gone, the remaining per-pet
scalar fields are cheap enough that restructuring them for a small additional saving
wasn't worth the complexity this task's own framing warned about.

**Verified:** `luacheck` 10/0 (unchanged baseline). Test suite 182 → 193 (new
`Tests/spec/abilitiespool_spec.lua`, 11 cases covering pool record/reconstruct,
cross-pet sharing, same-name dedup across buckets, the empty/nil-observation-doesn't-
clear-a-real-one guard, specID round-trip, and `NormalizePetData`'s pool-vs-static
`isExotic` precedence). **Needs the user's client, same shape as the free tier's own
acceptance**: log in on two characters, visit a stable on each, `/reload`, and
specifically check the *other* character's pets — not just the current one — show
correct family/spec/exotic status/abilities in the tooltip, filters, sort, and CSV
export. Confirm the saved file shrank further from the free tier's ~185KB result.
Confirm a pre-change SavedVariables file still loads without error. Confirm the Models
Browser's Ability Browser is unaffected (it was never touched — this task ended up
entirely inside `PetStableManagement/Shared/Data.lua`, no `AbilitiesData.lua` or
`.toc` changes of any kind).

#### A14, structural tier — confirmed in-game (2026-08-21)

Three hunters, existing pet data intact and new collection seamless after `/reload`.
SavedVariables **~185KB → 138KB** (a real further drop, not the free tier's rough
directional comparison — same account, same session). Addon memory footprint at fresh
login: **1.56MB**, down from A2's 1.65MB floor — modest on this account's collection
size, expected to matter more for a larger one, per this section's own original
framing. Export still carries the `specID` column; noted as possibly not worth keeping
but not removed here — the user's call, not made yet. One pool entry
(`byFamily.Crocolisk`) came back with a duplicate spell ID in its raw array — harmless,
`GetPoolAbilities`'s existing name-level dedup already collapses it on reconstruction;
Blizzard's own live data carries the duplicate, not a bug introduced here. Closed.

#### A14, structural tier — correction found reading the real file (2026-08-21)

The user asked to read the actual `PetStableManagement.lua` SavedVariables file rather
than trust the in-game acceptance check alone — good call, it caught a real gap this
task's own implementation left behind. `CollectStabledPets`'s `processPet` deep-copies
Blizzard's raw stable-pet record wholesale (`local p = ns.Utils.DeepCopy(petData)`);
the abilities-pool work stripped the addon's own *computed* fields (`abilities`,
`specID`) but never stripped the **raw source fields those are computed from**, which
survive the deep copy untouched. Confirmed present on all 204 stabled pets in the real
file: `specialization` (exact duplicate of `specName`), `type` (exact duplicate of
`familyName`), `petAbilities`/`specAbilities` (the raw spell-ID arrays
`RecordAbilitiesObservation` already consumes into the pool — persisting them per-pet
too defeated a good chunk of the point), and `uiModelSceneID`/`creatureID` (no reader
anywhere in either addon). `button`/`categoryInfo` — also present on the live raw
record per the in-game dump earlier in this task — confirmed **absent** from the saved
file (0 occurrences); WoW's serializer silently drops the non-serializable frame
reference rather than erroring, so no action needed there.

Fixed by nil-ing all six in `CollectStabledPets` itself, right after the
abilities/pool processing, rather than deferring to `SavePersistentData`'s per-pet
strip — matches this function's existing precedent (`p._originalData = nil` was
already stripped at collection time, not save time) and means the live in-memory
record is the same shape `ProcessPetInfo`'s active-pet path already produced (that
path builds a fresh table field-by-field and never had this leak). Verified no other
reader exists for any of the six (`TeamsData.lua`'s `pet.specName or pet.specialization`
fallback remains correct for its documented *other* input case — a raw, unprocessed
Blizzard record handed to `SlotRecord` directly — and was already unreachable for any
addon-processed pet, since `specName` is unconditionally set before this strip runs).
`luacheck` 10/0, suite still 193/193.

**Confirmed in-game (2026-08-21): 138KB → 94KB**, a 44KB drop, in line with the
~40-50KB estimate from the raw-text math above. `/dump`ed the pool contents directly
against the same account: `specIdBySpecName` came back `{Ferocity=74, Tenacity=81,
Cunning=79}`, an exact match for the values the user separately recalled from the
codebase's respec logic — strong independent confirmation the pool is capturing real
values, not coincidentally-plausible ones. `exoticByFamily` correctly reflects the
account's actual exotic families. `bySpec` holds exactly 3 entries (2 spell IDs each),
matching the earlier live-data finding that every spec's ability count is fixed at 2.

**Total SavedVariables reduction across all of A14, this account, both tiers:**
roughly 300KB (pre-A14) → 185KB (free tier) → 138KB (structural tier, first pass) →
**94KB** (after the raw-field-leak fix) — about a 69% reduction overall. A14 closed.

**Backlog: taming-requirement popups show the family default, not the per-NPC
exception** — raised while confirming A14's structural tier; moved to `Backlog.md`
(2026-08-21), still open.

#### A9 — the in-game half, partially confirmed

No deliberate error was forced (no easy way to throw one on purpose from outside
the code), so `/psm debug` surfacing a stack trace is unverified — left to happen
naturally rather than staged. One real gap surfaced instead, while testing: **not
every panel is protected against combat entry.** It's a `Broker:CloseAllPanels()`
coverage gap (missing `abilityBrowser` / `specialTames`), unrelated to the
error-boundary mechanism A9 built — tracked in `Backlog.md` (2026-08-21), still open.
The panel-close frame-time question (the GC deletion's own acceptance criterion)
folded into the memory investigation below and came out answered: no hitch, no leak.

#### Follow-up, in-game (2026-08-20): the deleted GC calls looked like a leak, and weren't

First read after the GC deletion landed: `GetAddOnMemoryUsage` climbing from 1.7MB at
fresh login to "always above 3.3MB, slightly growing with GC or largely growing
without GC" after opening/closing the Owned Pets panel. Read at first as A9 having
uncovered or caused a leak.

**The control that settled it: `collectgarbage()` is a full collection, so if memory
doesn't return to baseline after one, it isn't garbage — it's live.** That single fact
means the deleted `collectgarbage("collect")` calls could never have been fixing
whatever this was; a forced collect reclaims exactly what an eventual incidental one
would, just sooner. At most they were trimming the ordinary incidental-GC backlog
sitting on top of a real number, which is a cosmetic effect, not a fix.

Ruled out by reading rather than guessing, before asking for more data: `GridView`'s
row/model pool builds once (`if not pool then ... end`) and is reused, not rebuilt,
on every open; `ns._petDerivedCache` is keyed per pet, bounded by pet count rather
than render count; `Store:Watch` has exactly one call site (`ModelsFilters`, browser
side) and never touches Owned Pets; A8's `__dragDropWired` / `__groupContextMenuWired`
guards (same session, same day) were confirmed already in place for grid view too.

**Instrumented rather than continued guessing**, since this shell can't drive the
client: a 189-character `/run` one-liner logging `GetAddOnMemoryUsage` alongside
`#PSM.state.rows` / `.modelViewRows` / `.groupedViewRows`, run after forced GC at
fresh login, after first opening each view, and across repeated open/close/sort
cycles. The result: two step changes, each landing exactly on a row count going from
0 to 50 for that view (1787KB → 3057KB when list+grid's pools first build, 3057KB →
3369KB when grouped's pool first builds) — the one-time cost of constructing ~150
pooled `PlayerModel` frames, textures, buttons, and tooltip/drag-drop wiring across
the three views. After both jumps, ~15 further cycles (open, close, sort, repeat)
held in a fixed oscillating band (3412KB / 3368KB, alternating), never trending
upward. **No leak.** The elevated resting size is the intended cost of building each
view's pool once and reusing it forever, and the flicker-once-then-smooth UX the user
separately noticed is that same construction cost made visible on first render per
view.

Net effect on this task: none — the GC deletion stands, and this is recorded so a
future session doesn't re-open A9 chasing the same phantom, or re-add the calls on
the strength of an untested first read.

#### A3 — closing summary (2026-08-20): functionally complete, no dedicated pass needed

Never landed as its own discrete step, unlike every other lettered task in this
document — Option B's plan was to let the public surface narrow as other tasks
touched files (A5, A6, A9, A10 all did), and that is what happened. Checked rather
than assumed before writing this: every hand-written file in `PetStableManagement/`
opens with `local _, ns = ...` or `local addonName, ns = ...` — zero files remain on
the pre-A3 `_G.PSM = _G.PSM or {}` pattern (grepped for the inverse, found nothing).
`Shared/PublicAPI.lua` publishes a curated eleven-name surface, loaded last in the
`.toc` so every module has attached itself first; `Tests/spec/boundary_spec.lua` and
`publicapi_spec.lua` enforce both the browser→core direction (against `PUBLIC_API`)
and core→browser (against `ns.Browser`) statically, and `Core/Compat.lua` — the one
piece explicitly deferred as independent of the rest — was never built, because
nothing in the eventual work needed it; the WoW API surface stayed accessed at point
of use throughout, per the standing "no file-scope capture" rule. **A3, closed**;
`CLAUDE.md`'s "Global architecture" section is the living description of the result,
not this task text.

#### A7 — dropped (2026-08-20)

User's call, after the revert above: not worth resuming, controlled A/B or not. No
outstanding code — the revert already left the tree clean. A8 was re-checked against
losing this dependency and needed nothing from it (see A8 above).

#### A1 — closing summary (2026-08-20): already done, third task this session to turn out that way

Checked before writing any code, per this doc's own standing rule — and both halves
already exist:

**Explicit sync.** `psm-data/sync.py` calls `config.sync_output_to_addon()` as its
whole body; `grep`ing all fifteen numbered scripts plus `06_generate_abilities_lua.py`
for `sync_output_to_addon` finds it nowhere outside `config.py` (the definition) and
`sync.py` (the one caller). None of the five generators reference `ADDON_DATA_DIR`
either, so there's no path back into `psm-addon` from a generator run at all — running
one is structurally incapable of touching the addon repo, which is the acceptance
criterion without needing an actual multi-hour scrape to prove it.

**Schema version.** `config.py`'s `SCHEMA_VERSION = 1`, stamped into every generated
file's output as `PSM_DataSchemaVersion` by all five generators (`06`, `12`-`15`,
grepped individually). `PetStableManagement_ModelsBrowser/ModelsBrowser/Schema.lua`
asserts it on load — nil version or a mismatched one both `error()` with one readable
line naming `psm-data/sync.py` as the fix, rather than a wall of nil-index errors from
every consumer separately. Wired into the browser's `.toc`, ahead of nothing that reads
`ModelsData` before it does.

Both halves are cited by name in `psm-data/CLAUDE.md`'s "Crossing into psm-addon"
section as the current, standing mechanism — not written up here as a discovery so
much as confirmed against the actual files rather than taken on the doc's word. `ruff
check .` clean, addon test suite 182/182 (unaffected — `schema_spec.lua` already
covered `Schema.lua`, this task added no new code to test). **A1, closed.**

Two structural notes for anyone who revisits this: the original task text names
`psm-addon/PSM_Data/Schema.lua` as the target file, from when a third `PSM_Data`
addon existed. That split was tried and reverted (see `psm-addon/CLAUDE.md`'s "Don't
add a third addon folder" rule) before this landed, so `Schema.lua` lives inside
`PetStableManagement_ModelsBrowser/ModelsBrowser/` instead — same mechanism, different
address, not a deviation from the task. And `SCHEMA_VERSION`/`EXPECTED_SCHEMA_VERSION`
are two independent constants (Python side, Lua side) that must be bumped together by
hand — nothing enforces that today beyond the comment saying to; a drift there would
show up the same way a real data-shape mismatch would, since the check can't tell the
difference between "the schema changed" and "someone forgot to bump one side."

---

#### A12 — done (2026-08-20): one spec table, one builder, Reset down from 20 hand-written lines to a loop

**Every one of the panel's nine settings-backed controls now goes through one
`OPTIONS` list and one `BuildOption(spec, layout)`.** Each spec carries its own
`key` (a plain `settings[key]` field), `default`, and an `apply()` re-reading from
`PetStableManagementDB` for side effects beyond the write (live model reapply,
panel relayout, popup repaint) — `apply` takes no argument by design, so there is
one source of truth for "what is the setting right now" rather than the argument
and the DB potentially disagreeing. The one control that isn't a plain field —
the minimap checkbox, which writes a nested, inverted path
(`settings.minimapButton.hide = not checked`) and also toggles the minimap live —
gets a `get`/`set` pair instead.

**Follow-up, same day, in-game:** first landed with the minimap checkbox marked
`resettable = false`, preserving the original handler's behavior exactly (it never
wrote `minimapButton.hide`, checked against the actual field list rather than
assumed). User's call after testing: **standardize it in** — Reset All Settings
now includes it, default `true` (shown), matching the `hide = false` Events.lua
already seeds on first `ADDON_LOADED`. This is the one option that reaches Reset's
loop through `spec.set` rather than a plain `settings[key]` write — the branch for
that was in the first version, found unreachable given minimap was the only
`get`/`set` option and it was excluded, and was deliberately deleted rather than
kept "for the shape" (matching this project's stated preference for exercised code
over speculative generality). Restored once the exclusion that made it dead was
itself reversed — same reasoning, opposite direction: don't keep code no path can
reach, but don't be afraid to bring it back when a path to it appears for a real
reason.

**Reset went from ~20 hand-written lines (5 `SetValueSilently` + 2 `SetChecked` + 2
`UIDropDownMenu_SetText`, each naming its own default constant a second time) to one
loop over `OPTIONS`.** A 10th option is one table entry now, not a creation site, an
`onChange`/`onClick`, and a fourth hand-written reset line that's easy to forget —
which is exactly the shape the original file was in: `openWithStable` and
`stopAnimation` used two different boolean-default idioms (`~= false` vs. `or
default`) that happen to agree for their two *current* default values but aren't
the same rule, so a nil-coalescing `OptionValue` replaces both to make the actual
rule ("explicit value wins, nil falls back to default") a real invariant instead of
two liberally-tested constants.

**One real behavioral asymmetry, first preserved, then unified on request.**
`petsPerColumn`'s dropdown had never displayed its list padding
(`UIDropDownMenu_SetText` always got the bare number, not `"  " .. n`), while
`backgroundType`'s always displays its padded label. First landed with the
difference modeled explicitly (`displayText = tostring` on `petsPerColumn`,
defaulting to "look it up in `choices`" for `backgroundType`) rather than
silently picking one and changing the other. **Follow-up, same day, in-game:**
user's call — standardize on `backgroundType`'s behavior. Deleting the
`displayText` override was the whole fix; `DisplayText`'s existing fallback
(`TextForChoice`, scanning `choices`) picks it up unchanged, so `petsPerColumn`'s
current-selection text now carries the same padding its list entries always had.

**Dead pre-Dragonflight branch removed**, per the task: `InterfaceOptions_AddCategory`
predates the Settings API and doesn't exist on this addon's Interface versions
(120007, 121000), so the `elseif Settings.RegisterCanvasLayoutCategory` branch was
unconditionally the one taken. Went further than the task's literal ask and also
dropped the *existence checks* on `Settings.RegisterAddOnCategory`/
`RegisterCanvasLayoutCategory` themselves, not just the dead first branch — both are
core Settings API since Dragonflight, `Settings` itself is already a stable
`.luacheckrc` global, and per this session's A9 work, a real future removal should
surface as a loud load-time error rather than a silently-unregistered options panel.

**Verified:** `luacheck` 10/0 unchanged, addon test suite 182/182 unchanged (no new
spec — same reasoning as the file had none before: this is frame construction,
unreachable headless, the acceptance criterion is explicitly in-game). **Needs the
user's client**: open Settings → AddOns → Pet Stable Management, exercise every
control (both checkboxes, all five sliders, both dropdowns), confirm each persists
across `/reload`, confirm `Reset All Settings` returns every control to its default
*and* leaves the minimap checkbox alone, confirm live model reapply still fires for
the four model sliders and the stop-animation checkbox while a pet is on screen.

**Follow-up, same day, in-game — both points above addressed:** minimap checkbox
folded into Reset (defaults to shown), pets-per-column dropdown's display text
unified with background-type's (both padded now). See `OptionsPanel.lua`'s `default
= true` / removed `displayText` override.

---

#### Committed and pushed (2026-08-20)

User confirmed all in-game tests passed for A9, A14 (free tier), and A12 (including
both follow-ups). Two commits on `feat/load-on-demand`, split so Data.lua's A9 and
A14 changes didn't need hand-splitting into one commit each — they share the file
closely enough (both persistence-adjacent, both tested together this session) that
forcing them apart risked more than it bought:

- `0f70b0f` — A9 + A14 free tier (`Log.lua`, `Utils.SafeCall`, `Data.lua`,
  `SlashCommands.lua`, `UI.lua`, `PanelManager.lua`, `Config.lua`, `Locale.lua`,
  `PetRoulette.lua`, the `.toc`, and the three touched/added test files).
- `61d29ab` — A12 (`OptionsPanel.lua` alone, cleanly disjoint from the other two).

Pushed to `origin/feat/load-on-demand`. `main` is not caught up — this branch is
where all of this session's work has landed, same as A2's original entry noted back
on 2026-08-11; nothing here has been merged to `main` yet.

---

#### A11 — done (2026-08-20): the addon half rewritten, banner retired

Picked up with A7 dropped and A2/A3/A6/A10 done — decided not worth waiting on A8,
since A8 turned out not to need A7 either (see its closing note above). Rewrote
`stages[6..9]`'s addon columns and the addon portion of `edges`/the legend/the
footer prose; left the psm-data half, the grid CSS, and the SVG connector code
untouched, per the task's own scope.

**Ground truth came from the live repo, not this document** — an Explore pass read
both `.toc` files, `PublicAPI.lua`, `Core.lua`'s `ns.Browser`, `State/*.lua`, and
grepped every current `PanelManager`/`RowManager`/`PopUpManager`/`ns.Browser`/
`PSM.Data`/`PSM.Store` call site fresh, rather than trusting this plan's own prose —
which was a good instinct: `CLAUDE.md` still says "eleven names" for `PUBLIC_API`
in one place; the file itself has fifteen (confirmed against A10's own closing note,
"published as the fifteenth public name"). Even this document drifts.

**What changed, structurally, since the 2026-08-11 snapshot:** `Shared/Locale.lua`,
`Shared/Loader.lua`, `Shared/Log.lua`, `Shared/PublicAPI.lua`, and
`ModelsBrowser/Schema.lua` all exist now and none were in the old diagram. `State`
went from one compact node to a real three-file split (`Store`/`Filters`/
`Selections`). `OwnedPets/PetTooltip.lua` was missing entirely (confirmed
self-contained — zero external callers — so it gets a node but no edges).
`ModelsBrowser/Schema.lua` likewise gets a node with no edges: nothing calls it,
it's a load-order guard.

**The bigger change was what got *removed*.** The old diagram drew 14 precise
"Core fans out to every `Shared/` module" edges, and its own comment already
admitted they were decorative — "namespace availability, not a call graph." Every
hand-written file sharing `ns` isn't a dependency; it's just what a `.toc` load
order is. Cut all 14, replaced with nothing — the existing column grouping already
says "these files are core," and inventing a line to also say it was the exact
kind of coupling-that-isn't A6/A3 spent this whole plan trying to get rid of. That
one cut, alone, would have satisfied the success criterion.

**What got added back deliberately, at real cost against that same budget:** one
edge, `core → api` (`PublicAPI.lua`), styled with the same dashed-amber `bridge`
class as `sync.py` — reused on purpose, not by coincidence. Both are the same
shape: a narrow, curated, versioned/whitelisted crossing between two things that
otherwise can't see each other directly. `psm-data → psm-addon` has `sync.py` and a
schema stamp; core `ns → _G.PSM` has `PublicAPI.lua`'s fifteen-name whitelist and a
metatable trap. Drawing them identically is the actual insight this task produced,
more than any individual node or edge. `Store` also got two new edges
(`ModelsDataLoader`/`NPCDataLoader` both consuming `Store:Selector`) — infrastructure
that didn't exist in the old snapshot and is genuinely load-bearing (it's what makes
A8's memory numbers hold, per that task's own closing note).

**Success criterion, checked by counting the literal arrays rather than eyeballing
the render:** baseline (2026-08-11) = 14 fan-out + 23 "confirmed reuse" = 37
addon-side precise edges. New = 27 (1 boundary + 26 curated real-call-site edges,
same restraint level the original used, just extended to cover `Store`/`PublicAPI`
and updated node IDs). **37 → 27, a real cut, not a rounding trick** — achieved by
removing decorative edges wholesale rather than by under-covering real ones; the
new diagram actually names *more* real infrastructure (26 modules across cols 8-10
now vs. the original's ~28, but every one backed by a fresh grep) while drawing
fewer lines to do it.

**One honest gap:** no automated check keeps this diagram in sync with the code —
the same risk that made the 2026-08-11 snapshot stale within days of A2 landing.
Nothing in this task tried to fix that; it is a plain HTML file with a hand-written
data model, and staying current depends on the next person who moves a file
remembering this document exists. Worth a line in `CLAUDE.md` if that becomes a
recurring problem, not before.
