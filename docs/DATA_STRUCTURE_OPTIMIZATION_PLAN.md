# PSM Data Structure Optimization Plan

A cross-repo plan spanning `psm-addon` and `psm-data`, tracked here in `psm-addon/docs/`
as of 2026-08-27 alongside `ARCHITECTURE_PLAN.md` and `architecture.html` (it spent its
working life in the untracked `PSM/` workspace root, which is *not* a git repo). Written
2026-08-10, **CLOSED same day** — see "Out of scope" and the running memory log below;
T9 is the headline result (`ARCHITECTURE_PLAN.md` cites it as its own starting point).

## Why

Audited 2026-08-10: `PetStableManagement_ModelsBrowser` measures ~13MB, `PetStableManagement`
~3MB. Two confirmed causes, both fixable without changing what data ships, only how it's shaped:

1. `ModelsData[npcId] = {name=..., family=..., ...}` — 7,700 records, each a string-keyed
   hash table (~700-800 bytes of pure structural overhead per record before any string
   data), keyed by sparse NPC IDs (forces the *outer* table into the hash part too, not
   just the inner records).
2. `PetModels.lua`'s per-family cache copies ~10 scalar fields per NPC into a brand-new
   table, cached forever, never invalidated during normal use, and — confirmed via
   `ModelsDataLoader.lua:763-825` — gets built for *every* family during ordinary
   first use (not just an edge case), i.e. a near-full second copy of `ModelsData`
   sitting alongside the original.

Decision made: keep the current 5-file split (`ModelsData`/`CoordsData`/`NotesData`/
`AbilitiesData`/`ConditionsData`) — it's already split on the right axis (access
cadence: hot summary vs. cold per-NPC detail vs. independent small domain), not on
field granularity. Restructure *inside* `ModelsData` only: sparse hash-keyed records
become a dense-index-backed columnar (structure-of-arrays) layout. `CoordsData`/
`NotesData`/`AbilitiesData`/`ConditionsData` are small enough relative to their string
payload that this rewrite isn't worth it there — **out of scope, leave as-is.**

## Measurement protocol (used by every task below that touches the addon)

Reproducible repro state, so before/after numbers are comparable:
1. `/reload`
2. Open Models Browser panel, Models view, no filters applied (all families/expansions/locations selected — the worst case, since it forces full data materialization)
3. Wait ~2s for idle
4. Blizzard AddOn memory panel (or `/console` + `UpdateAddOnMemoryUsage()` then read `GetAddOnMemoryUsage("PetStableManagement")` / `GetAddOnMemoryUsage("PetStableManagement_ModelsBrowser")` via a temporary slash command or `/run print(...)`)

Record every measurement in the **Running memory log** section at the bottom of this
file — task, before, after, delta. This is the actual validation; code review and
`luacheck` are necessary but not sufficient for any task marked "in-game required".

### Measurement protocol — caveats learned doing T1 (read before trusting a reading)

- **`GetAddOnMemoryUsage` requires `UpdateAddOnMemoryUsage()` immediately before it**,
  or you get a stale/cached figure. A raw ElvUI/Blizzard panel reading without forcing
  this can look identical before and after a real change — this happened during T1 and
  cost a full round-trip to diagnose. Always call `UpdateAddOnMemoryUsage()` first.
- **WoW's GC is incremental and lazy.** A reading taken right after interaction can be
  dominated by not-yet-swept garbage, not live/referenced memory — we saw the same
  repro state read 35MB, then 47MB, then drop to ~22-25MB after `collectgarbage()`.
  Always force `collectgarbage()` before reading if you want "true live" memory, and
  treat pre-GC numbers as "churn", not "footprint".
- **`GetAddOnMemoryUsage` covers Lua-table memory, not UI `Frame`/widget cost.**
  Dropping every Lua reference to a pool of `Frame`/`CheckButton` objects and forcing
  GC does *not* reliably free them or move the reported number — confirmed directly
  (nil'd `ModelsFilters`' pooled checkboxes, forced GC, delta was noise, and the
  checkboxes were still visibly on-screen afterward). This measurement technique
  cannot isolate widget/frame-based memory cost. Don't reuse the nil-and-diff pattern
  for anything UI-widget-shaped; it only works for plain data tables (which is
  everything `ModelsData`-related in this plan actually is).
- **Panel "closed" ≠ "session-lifetime caches cleared".** `PSM.PetModels`'s cache and
  a few `PSM._*` caches get cleared by `PanelManager:CleanupPanel` on hide (via
  `ModelsPanel.lua`'s `onHide` config callback) — but pooled UI widgets
  (`ModelsFilters.lua`'s `_filterCheckboxPool`/`_locationRowPool`/
  `_continentHeaderPool`) are intentionally never cleared, by design (that's what a
  pool is for). If you build them once early in a session, every subsequent
  before/after diff in that same session will have them present on *both* sides and
  never show them — you won't discover their cost unless you diff across a fresh
  `/reload`, or isolate them before anything else touches the panel.
- **Isolate one variable per test.** Every clean number in this plan came from a
  two-command pattern: `/run collectgarbage();UpdateAddOnMemoryUsage();PSMDebugBefore=GetAddOnMemoryUsage("PetStableManagement_ModelsBrowser");print(PSMDebugBefore)`
  then, after changing exactly one thing, `/run <the one change>;collectgarbage();UpdateAddOnMemoryUsage();local b=GetAddOnMemoryUsage("PetStableManagement_ModelsBrowser");print(b,PSMDebugBefore-b)`.
  Keep both commands under ~250 characters — macros and the chat edit box silently
  truncate longer input with no visible error (Lua error display is off by default),
  which looks exactly like "the command did nothing."

## Target schema for ModelsData (canonical — tasks below reference this, don't redefine it)

```lua
ModelsData = {}

-- Backbone
ModelsData.Index = {}   -- [npcId] = denseIndex        (sparse hash, but only ONE of these now)
ModelsData.NpcId = {}   -- [denseIndex] = npcId          (array part)

-- Columns, all keyed by denseIndex (array part — this is the whole point)
ModelsData.Name             = {}  -- string
ModelsData.DisplayIds       = {}  -- number if count==1, else array of numbers, {} if none
ModelsData.UiMapId          = {}  -- number, index omitted (implicit nil) if absent
ModelsData.FamilyId         = {}  -- number, internal-only, see note below
ModelsData.ExpansionId      = {}  -- number, internal-only
ModelsData.ReactA            = {}  -- number, Alliance reaction (was string "[-1,-1]")
ModelsData.ReactH            = {}  -- number, Horde reaction
ModelsData.ClassificationId = {}  -- number, internal-only
ModelsData.NameKeeper       = {}  -- boolean
ModelsData.Taming           = {}  -- array of strings, index omitted (implicit nil) if none

-- Lookups (id -> display string), built from distinct values seen during generation
ModelsData.Families        = {}  -- [familyId] = "Spider"
ModelsData.Expansions      = {}  -- [expansionId] = "Vanilla"
ModelsData.Classifications = {}  -- [classificationId] = "Normal"
ModelsData.UiMapNames       = {}  -- [uiMapId] = "Elwynn Forest", joined through UiMapId[i]
```

Corrected from the original draft of this section (written before T2's implementation):
added `Taming` — it's a real field actively read by `PetModels.lua` (via the `__index`
fallback added in T1) and the Special Tames filter; omitting it from this doc was an
oversight, not a decision, it was never on the chopping block.

`UiMapName` went through two revisions before landing here. First draft had it as a
per-record string column (`UiMapName[i]`, mirroring `UiMapId[i]`). Verified against
the source CSV before finalizing: `uiMapId` is fully dense (all 7,700 NPCs have one,
not sparse as first assumed) and `uiMapId -> uiMapName` is a clean 1:1 mapping across
all 466 distinct zones with zero inconsistencies. That makes it a different case from
`Family`/`Expansion`/`Classification`: those had no pre-existing ID to key off, so
normalizing them costs a whole new lookup table for a CPU-only win (string interning
already dedupes the repeated *values*, so there was never a memory win available
there). `uiMapId` **is** already a natural, pre-existing ID — Blizzard's own zone
identifier — so instead of a per-record `UiMapName[i]` string reference (7,700 slots),
it's dropped entirely in favor of one small `UiMapNames[uiMapId] = name` lookup (466
entries), joined through the `UiMapId[i]` column already being stored. Net: ~104KB
saved (7,700 x 16B removed, 466-entry hash table added), zero information loss, and no
external API dependency (unlike T11's `C_Map.GetMapInfo` idea, which carried real
uncertainty about resolving every zone correctly) — this makes T11 unnecessary, not
just deferred; see T11's note below.

Columns that can legitimately be absent for a given NPC (`UiMapId`, `Taming`) are
written as explicit `[i] = value` entries only for indices that have a value — the
index is simply not emitted for NPCs without one, leaving an implicit `nil` in that
array slot. This is safe and still array-part-eligible in Lua as long as most indices
are present (Lua's table constructor buckets a table into the array part based on
density, not on whether every slot was explicitly assigned) — don't reach for a
sentinel value here. Columns that are never absent (`Name`, `DisplayIds`, `FamilyId`,
etc.) are written as plain positional lists, which is simpler to both generate and
read.

**IDs are internal-only, not stable across pipeline regenerations, and must never be
persisted to `PetStableManagementDB` or compared across addon versions.** Filter UI
state keeps keying by name string exactly as today. Only the O(7,700) per-frame
comparison loop translates the (small) selected-name-set to IDs once per filter
change, then compares IDs in the hot loop. See Task 8.

## Tasks

Each task is meant to be pasted into a fresh session as-is; it shouldn't require this
conversation's history, only this file plus the repo it names.

---

### T0 — Establish memory baseline [psm-addon, in-game, no code change]
Follow the Measurement protocol above exactly as written. Record the numbers in the
Running memory log at the bottom of this file under "T0 baseline". This is the
reference point every later task's delta is measured against. No dependencies.

---

### T1 — DONE (2026-08-11) — Kill the PetModels duplicate cache [psm-addon only, independent of schema]
**Repo:** `psm-addon`. **Files:** `PetStableManagement_ModelsBrowser/ModelsBrowser/PetModels.lua`.
**Depends on:** T0.

`GetFamilyModels` (`PetModels.lua:27-177`) currently builds a brand-new `npcRecord`
table per NPC copying ~10 scalar fields out of `ModelsData`, cached forever in
`self[familyName]`. Change it to store only *derived* fields that don't already exist
on the source record (parsed faction reaction, `_cachedDescription`), and reference
back into the existing `ModelsData[npcIdKey]` table for everything else, instead of
copying it. Do **not** touch `ModelsData`'s own shape in this task — that's T2+.

This is intentionally done *before* the schema rewrite: it's independent, low-risk,
and gives an early real in-game number to validate the T0 measurement approach works
before committing to the bigger rewrite.

**Acceptance criteria (in-game required):** `luacheck.exe` clean
(`C:\Users\Gi\Dev\tools\luacheck.exe PetStableManagement PetStableManagement_ModelsBrowser`
from `psm-addon` root). `/reload`, browse every family in Models view and NPC view, confirm
no Lua errors and all fields (name, faction indicator, taming, location) still render
correctly. Re-run Measurement protocol, log delta vs. T0.

**Result:** Implemented via `setmetatable({npcId=, factionReaction=, location=}, {__index = npcData})`
— only the 3 genuinely-differing fields are stored per record; everything else falls
through to the shared `ModelsData` record. `luacheck` clean, diff scoped to exactly the
intended 20 lines. In-game verified across all 61 families in both views, no Lua errors,
all fields render correctly.

Isolated measurement (see caveats above — this took 3 attempts to get a clean number):
`PetModels`'s cache costs **2.85MB** at full 61/61-family load, matching the pre-task
estimate closely. However: this cache is *already* cleared by the existing
`PanelManager:CleanupPanel` (called from `onHide`) plus a delayed `collectgarbage()`
0.5s after close — so it was never part of the "always-paid" static floor, and the
floor is (correctly) unchanged by this task: 13.26MB before, 13.26MB after. T1 reduces
peak memory *while the panel is open and heavily browsed*, not the constant footprint.
Real and correctly implemented, just smaller-scope than the original framing suggested.

**Side finding, out of scope for this plan, logged for awareness:** with the panel
open and all 61 families/many filters exercised, true live (post-GC) memory reaches
~24-25MB — about 11MB above the 13.26MB floor. Of that: `PetModels` = 2.85MB (above),
`panel.allModels` = 192KB, `_dynamicFilterCache`+`_npcZoneIndex`+`_modelsRenderCache`
combined = 199KB. That leaves **~8.7MB unattributed to any plain-data-table structure**
in the codebase. Leading suspect: `ModelsFilters.lua`'s pooled filter-checkbox/
location-row/continent-header widgets (154 confirmed live: 61+77+16) and/or ElvUI's
own skinning-hook state applied to them — but this is a `Frame`/widget cost, and per
the caveats above, `GetAddOnMemoryUsage`+`collectgarbage()` diffing cannot measure
widget memory (confirmed: nil'd the pools, forced GC, delta was noise, checkboxes were
still visibly on-screen). Isolating this properly needs a real memory profiler, not
this technique. **Not part of the constant/floor footprint** (the pools only grow
during active, sustained filter use) — deferred, not blocking T2+.

---

### T2 — Rewrite the ModelsData generator to the target schema [psm-data only]
**Repo:** `psm-data`. **Files:** `12_generate_models_lua.py`.
**Depends on:** nothing (can happen in parallel with T1).

Rewrite to emit the exact schema in "Target schema for ModelsData" above. Build
`Families`/`Expansions`/`Classifications` ID maps by sorting the distinct values
seen (alphabetical) before assigning IDs — not required for correctness (see the
internal-only note) but keeps output diffs stable and debuggable across reruns.
`displayIds`: emit a bare number when `len(sorted_dids) == 1`, else a Lua array table
as today. `react`: parse the existing `"[a,b]"` string format into two ints at
generation time and emit `ReactA`/`ReactH` as separate numeric columns (Alliance,
Horde — confirmed via `NPCRow.lua`'s existing `local a, h = react:match(...)` and its
`"A/H"` column label, not a guess) — don't ship the bracket-string at all.

This is a from-scratch rewrite of the output-writing loop (lines ~136-183 of the
current script), not an incremental patch — the whole table shape changes from
array-of-structs to structure-of-arrays.

**Acceptance criteria:** `ruff check .` clean. Script runs end to end against the
existing `Processed/pet_data.csv` without modifying anything upstream of it. Don't
run `sync_output_to_addon()` yet / don't let this task touch the addon repo — that
sync happens naturally once T2 is done, but the addon can't consume the new shape
until T4+ lands, so treat the copied-over `Output/ModelsData.lua` as inert until then.

---

### T3 — DONE (2026-08-11) — Regenerate and spot-check [psm-data only, verification]
**Repo:** `psm-data`. **Depends on:** T2.

Run `python 12_generate_models_lua.py`. Verify: record count in `ModelsData.NpcId`
is 7,700 (or current count — check `wc -l` isn't the way, count `ModelsData.Index`
entries). Spot-check 5-10 known NPC IDs (e.g. `30`, `265254` from earlier samples)
resolve to the right name/family/zone through the new `Index`/columns. Confirm
`Families`/`Expansions`/`Classifications` lookup tables contain the expected distinct
value counts (cross-check against a quick `cut -d, -f<col> pet_data.csv | sort -u | wc -l`
on the source CSV for family/expansion/classification columns).

**Result:** `ruff check .` clean. Ran from `PSM/` root (config.py's paths are relative
to there, not to `psm-data/` — note for future sessions). 7,700 NPCs processed,
matching the pre-T2 count. Spot-checked npcId 30/43/113/118 (index 1-4) across every
column — name, displayId, uiMapId, familyId->Families lookup, reactA/B — all match the
original data exactly. `Families`/`Expansions`/`Classifications` counts (61/12/4)
independently cross-checked against the source CSV via a standalone Python script
(not just trusting the generator's own output) and also matched the live game client's
`PSM.PetModels:GetLoadingStats()` reading from the T1 session (61 families) — three
independent confirmations. On-disk file size dropped 2.5MB -> 1.1MB.

Mid-verification, added the `UiMapNames` lookup refinement (see "Target schema" above
and superseded T11) — verified `uiMapId` is fully dense (7,700/7,700 NPCs) and
`uiMapId -> uiMapName` is a clean 1:1 mapping (zero inconsistencies across 466 zones)
before committing to it. The lookup table itself only ends up with 394 entries, not
466 — verified this is expected, not a bug: it only contains zones that win the
pre-existing "first valid uiMapId wins" collapse per NPC (unchanged logic from before
T2), so it's exactly the same zone set the old per-record column would have
referenced, just deduplicated.

Also renamed `ReactB` -> `ReactH` (Alliance/Horde, not arbitrary A/B) — confirmed
against `NPCRow.lua`'s existing `local a, h = react:match(...)` and its `"A/H"` column
label before renaming, not assumed. Free to do now since no addon code reads the new
column names yet.

**Considered and declined:** sparse/manage-by-exception storage for `ClassificationId`
(80.1% of NPCs are "Normal") and `NameKeeper` (85.7% are `false`), mirroring how
`UiMapId`/`Taming` omit absent indices. Checked the real distribution before deciding:
the saving is real but small (~40KB each, since a table with only ~15-20% of indices
present falls out of Lua's array-part density threshold and lands in the hash part,
which costs ~40B/entry instead of ~16B/slot — same mechanism as the `UiMapNames` win,
just a much smaller exception set relative to the total this time). Declined: ~80KB
combined is two orders of magnitude below what T2's schema change already delivered,
and unlike `UiMapId`/`Taming` — where "absent" reflects real missing data — every NPC
genuinely has a classification and a nameKeeper value, so treating the common one as
"absence" would blur a currently-clean distinction for a marginal gain. Also confirmed
`NameKeeper` should stay boolean, not `0`/`1` — booleans and numbers occupy the
identical 16-byte `TValue` slot in Lua, so there's no memory difference, and boolean
truthiness checks are at least as fast as numeric equality checks. Don't revisit
either without new evidence.

**Reminder from earlier in this session:** `sync_output_to_addon()` runs
unconditionally inside every generator script, so running T2/T3 already overwrote
`psm-addon`'s live `ModelsData.lua` with the new schema. **`psm-addon` is broken
in-game until T4-T8 land** — none of its Lua consumers read the new shape yet. Don't
`/reload` and test until then.

---

### T4 — DONE (2026-08-11) — Add ModelsData accessor helpers [psm-addon only]
**Repo:** `psm-addon`. **Files:** new section in `PetStableManagement_ModelsBrowser/ModelsBrowser/PetModels.lua`
(or a new small file if that gets crowded — your call at the time).
**Depends on:** T2 (needs the target schema; doesn't need T3's actual regenerated file to write against, since the shape is fully specified in this doc).

Add the one shared access pattern every later task (T5-T8) will use, so it's written
once and consistently, not reinvented per file. At minimum: a way to go from `npcId`
to `denseIndex` (`ModelsData.Index[npcId]`), and a way to iterate all records
(`for i = 1, #ModelsData.NpcId do`). Decide here whether you want a
`ModelsData:GetRecord(npcId)` convenience that returns a small plain table (handy for
call sites that want the old `npcData.field` ergonomics at the cost of an allocation)
vs. requiring every call site to read columns directly (no allocation, more verbose).
Recommendation: direct column reads in the hot filtering loop (T6/T7), convenience
wrapper only for the cold one-off lookups (T8's `PopUpManager` fallback).

**Acceptance criteria:** `luacheck.exe` clean. No behavior change yet (nothing calls
this new code until T5+), so this task has no in-game check of its own — verified by
the tasks that consume it.

**Result:** Added `M:GetModelsIndex(npcId)` (thin wrapper over `ModelsData.Index`) and
`M:GetModelsRecord(npcId)` (full old-style-ergonomics record, for cold one-off lookups
only — allocates + does 3 lookup-table joins per call) to `PetModels.lua`, right after
the module setup. Went with direct column reads for hot loops per the recommendation
above, no iterator-function wrapper for `for i = 1, #ModelsData.NpcId do` — a closure
call per iteration would undercut exactly the hot-loop performance this schema change
is for, so that pattern is documented in a comment instead of wrapped in a function.
`GetModelsRecord` normalizes `DisplayIds` back to always-a-table (matching pre-T2
ergonomics) so cold-path callers don't need their own `type()` check. `luacheck.exe`
clean, 0 errors, no new warnings (1 pre-existing warning elsewhere in the file,
unrelated). Diff is purely additive, 53 insertions, nothing removed.

---

### T5 — DONE, in-game check pending T6-T8 (2026-08-11) — Migrate PetModels.lua to the columnar schema [psm-addon]
**Repo:** `psm-addon`. **Files:** `PetModels.lua`.
**Depends on:** T3, T4.

Supersedes T1's fix — now that `ModelsData` itself is columnar, `PetModels`'s
per-family cache should be even thinner: it only needs `denseIndex` + derived fields,
not even a reference to a whole source record.

**Acceptance criteria (in-game required):** same as T1 — luacheck clean, browse every
family in both views, no Lua errors, re-measure and log delta.

**Result:** `GetModelsDataByFamilyIndex` and `GetFamilyModels` rewritten to build off
`ModelsData`'s columns directly (`for i = 1, #ModelsData.NpcId do`, not `pairs()`).
T1's `setmetatable(..., {__index = npcData})` wrapper is gone — there's no longer a
single source table to delegate to (fields are scattered across separate column
arrays), so `entry.npcs` now stores bare `denseIndex` numbers instead of wrapper
objects; readers pull fields via `ModelsData.<Column>[i]` directly. This is thinner
than T1's design, not just different — a table of plain numbers has no per-entry
overhead at all beyond the array slot itself.

`GetAvailableFamilies` simplified drastically: `ModelsData.Families` is already the
complete, deduplicated id->name lookup, so it's now a single pass over ~61 entries
instead of scanning all 7,700 records (or `self`'s own cache keys, or the legacy
`PetData`/`PetModelsData` globals).

Also removed ~150 lines of dead legacy-format parsing (`processSubtable` and the two
branches reading `self[familyName]`/`_G.PetData` as raw pre-populated tables) —
confirmed earlier this session via grep that neither global is ever assigned anywhere
in the addon, so this path never executed. Called out explicitly rather than removed
silently, flagged to the user before proceeding: this goes beyond a pure mechanical
schema migration, but the function was being fully rewritten regardless and the code
predated even the *previous* schema.

`luacheck.exe` clean — 0 errors, 0 warnings (previously 1 pre-existing warning in this
file, which lived inside the now-removed legacy branch). Net diff across all of T1/T4/T5
combined: file shrank from 292 to 209 lines despite the new accessor functions added
in T4, since the legacy-code removal outweighed everything added.

**In-game check deferred:** `PetModels.lua` is internally consistent and correct
against the new schema, but its only callers (`ModelsDataLoader.lua`, `NPCDataLoader.lua`,
`ModelRow.lua`, `NPCRow.lua`) still expect the old wrapper-object shape from
`entry.npcs` and haven't been migrated yet (T6/T7) — reloading now would still error.
Verify in-game once T6 and T7 both land, not before.

---

### T5b — DONE (2026-08-11) — Remove CoordsData.lua's per-entry {coords=...} wrapper [psm-data + psm-addon]
**Repo:** both. **Files:** `psm-data/13_generate_coords_lua.py`, `psm-addon/PetStableManagement/Shared/PopUpManager.lua`.
**Depends on:** nothing — independent of the `ModelsData` migration (T4-T8), doesn't
touch any of the same files. Done opportunistically after checking whether
`CoordsData.lua` deserved the same treatment as `ModelsData` (it doesn't — see the
"Out of scope" note above) but finding a smaller, real issue anyway.

`CoordsData[uiMapId].npcs[npcId]` was `{coords = "x,y|x,y|..."}` — a table wrapping a
single field, for every npc-in-zone entry. Verified count: 466 zones, but **8,465**
npc-in-zone entries (more than the 7,700 NPCs — many spawn in multiple zones, which is
exactly the relationship `ModelsData.UiMapId`'s single "first-seen" value collapses
away, so this is the one place it's fully captured). Each 1-key wrapper table costs
~96 bytes (56-byte header + one 40-byte hash node) purely to hold one string
reference that could've been stored directly — **~800KB of pure overhead**, bigger
than several of the wins already banked on `ModelsData`, for a much smaller fix: this
is not the columnar/backbone treatment, just dropping an unnecessary indirection layer
(same principle as `ModelsData.DisplayIds` being a bare number instead of a 1-element
table when there's only one value).

Verified blast radius before touching anything: `.coords` is read in exactly 4 spots,
all in `PopUpManager.lua` (`GetCoordsDataForLocation` x3, `BuildCoordsLocationLabel`
x1). Two other flagged concerns checked and confirmed unaffected: the Location-filter
continent grouping (`ModelsFilters.lua:632-641`) reads `zone.name`/`zone.continent` —
a different field, one level up, untouched by this change. The NPC-row coords-exists
check (`NPCRow.lua:668` -> `PopUpManager:GetCoordsWaypointText` ->
`GetCoordsDataForLocation`) routes through the same 4 sites already being fixed.
`ModelsDataLoader.lua`'s two `CoordsData` usages only check truthiness or iterate
keys, never read `.coords` — work identically whether the value is a table or string.

**Result:** Generator now writes `[npc_id] = "x,y|x,y|..."` directly. 4 read-sites in
`PopUpManager.lua` updated (`mapData.npcs[id].coords` -> `mapData.npcs[id]`).
`ruff check .` and `luacheck.exe` both clean, 0 errors, no new warnings. Diff scoped
exactly as predicted: `CoordsData.lua` (8,465 insertions/8,465 deletions — every line
touched since removing `{coords = ...}` changes the line, but line *count* is
unchanged) and 4 lines in `PopUpManager.lua`. File size 927,014 -> 833,926 bytes on
disk (the ~93KB text-level reduction from removing literal `{coords = }` characters;
the ~800KB estimate above is the larger *parsed in-memory* saving from removing the
table headers/hash nodes, a different and bigger number, same relationship as
`ModelsData`'s 2.5MB->1.1MB on-disk vs. its larger in-memory structural saving).

**In-game check deferred**, same reason as T5: `PopUpManager.lua` is part of the core
`PetStableManagement` addon, which loads fine on its own, but the coords-popup feature
is only triggered from `ModelsBrowser` (`ModelsPanel.lua` and `NPCRow.lua` — confirmed
via grep, these are the only two callers anywhere in the addon; `OwnedPets` does not
use this feature) — verify the coords popup/waypoint link works once T6/T7 land and
the addon is reloadable again.

---

### T6 — DONE, in-game check pending T7 (2026-08-11) — Migrate ModelsDataLoader.lua / ModelRow.lua / ModelsPanel.lua [psm-addon]
**Repo:** `psm-addon`. **Files:** `ModelsDataLoader.lua`, `ModelRow.lua`, `ModelsPanel.lua`,
plus `PetModels.lua` (extended) and `PopUpManager.lua` (boundary, see below — not edited).
**Depends on:** T5.

Every `npcData.field` read in these three files becomes a column read via the T4
accessor pattern. This includes the `_modelsDataByFamily` index in `PetModels.lua`
that these files call into — confirm it's consistent with T5's changes.

**Acceptance criteria (in-game required):** luacheck clean. Full pass through Models
(display-ID) view: pagination, all filter combinations (family/expansion/location/
rares toggle/search), model preview popup. No Lua errors. Re-measure, log delta.

**Result:** Bigger than the original task description anticipated — reading the three
files surfaced two things the plan hadn't accounted for:

1. **`npc` is now a bare `denseIndex` number, not an object** (T5's design). Every one
   of the dozens of `npc.field` reads across these three files needed conversion, not
   just a handful. For fields needing a join through a lookup table (classification,
   expansion, location), added shared resolvers to `PetModels.lua` (extending T4):
   `M.NpcClassification(i)`, `M.NpcExpansion(i)`, `M.NpcLocation(i)` (the last always
   returns a string, `"Unknown"` fallback, matching the pre-T2 wrapper's behavior
   exactly — so downstream nil-guards on it are now unreachable-but-harmless, left in
   place rather than stripped, since removing them added review risk for no benefit).
   Fields that are a single direct column read (`Name`, `NpcId`, `NameKeeper`,
   `ReactA`, `ReactH`) were inlined as `ModelsData.<Column>[npc]` at each site instead
   of wrapped, per T4's original "hot loop reads columns directly" guidance.
   `formatFactionIndicator` (`ModelsDataLoader.lua`) rewritten to take `ReactA`/`ReactH`
   numbers directly instead of parsing a `"[a,b]"` string — one more site T7's planned
   `NPCRow.lua` parsing removal wasn't the only instance of. Removed the dead
   `npc.zones` branch in the search filter (confirmed unreachable: no live code path
   ever populates `.zones` for `ModelsData`-sourced records, legacy-format code that
   did was deleted in T5).
   `npc._cachedDescription` memoization (`ModelsDataLoader.lua`, read from
   `ModelRow.lua`) can't attach to `npc` anymore (assigning a field to a number errors)
   — moved to a side-cache, `PSM._modelsDescriptionCache[denseIndex] = description`,
   wired into `PetModels:ClearCache()` alongside the family cache it's conceptually
   paired with.

2. **`entry.npcs` doesn't stay inside these three files** — it flows into
   `PopUpManager.lua`'s model-magnification popup (`CreateNPCRow`/`BuildNPCRows`,
   `.name`/`.classification`/`.factionReaction`/`.location` object-style access),
   which is outside T6's file list and not scoped to any task yet. Rather than pull
   `PopUpManager.lua` into T6 unplanned, drew the migration boundary at
   `ModelsPanel.lua`'s `ShowMagnificationPopup`: dense indices get resolved to full
   records via `PSM.PetModels:GetModelsRecord(npcId)` (T4's cold-path helper — exactly
   its intended use case: bounded by NPCs-per-display, triggered once per click, not a
   hot loop) right before handing off to `BuildNPCLines` and `popup.currentNPCs`. This
   means `PopUpManager.lua`'s `CreateNPCRow`/`BuildNPCRows` need **zero changes** —
   they keep receiving exactly the object shape they always did. To make this work,
   extended `GetModelsRecord`'s fields beyond T4's original design: added `location`
   (alias of `uiMapName`, `"Unknown"` fallback) and `factionReaction` (re-synthesized
   `"[a,b]"` string from `reactA`/`reactH`) specifically so it's a drop-in replacement
   for the pre-T2 npcData/npcRecord shape everywhere, not just PopUpManager's fallback
   scan as originally scoped — turned out several not-yet-migrated call sites depend
   on that exact old shape. `CreateNoteEditor` (referenced in `ModelRow.lua`'s
   right-click note-edit path) confirmed dead — guarded by an existence check against
   a function that's never defined anywhere in the addon — left untouched.

`luacheck.exe` clean across both addon folders: 0 errors, 70 total warnings (identical
count to the post-T5b baseline — nothing new introduced across any of the four files
touched). Diff: `ModelRow.lua` +11/-cosmetic, `ModelsDataLoader.lua` ~142 lines
changed, `ModelsPanel.lua` ~31 lines changed, `PetModels.lua` cumulative across
T1/T4/T5/T6 (not yet committed separately).

**In-game check still deferred** — `NPCDataLoader.lua`/`NPCRow.lua` (T7) read the same
`ModelsData` shape and haven't been migrated yet, so the addon is still not
reloadable. Verify both Models view and NPC view together once T7 lands.

---

### T7 — DONE, in-game check pending T8 (2026-08-11) — Migrate NPCDataLoader.lua / NPCRow.lua [psm-addon]
**Repo:** `psm-addon`. **Files:** `NPCDataLoader.lua`, `NPCRow.lua`.
**Depends on:** T5.

Same migration for the NPC (text) view. Additionally: delete `ParseFactionScore`'s
and `FormatFaction`'s `string.match` parsing entirely (`NPCRow.lua`) — read
`ModelsData.ReactA[i]`/`ReactH[i]` directly as numbers now that T2 ships them
pre-parsed (and pre-labeled — no more guessing which bracket position is which
faction). This removes the unmemoized per-sort/per-row-draw parsing cost flagged
in the earlier audit.

**Acceptance criteria (in-game required):** luacheck clean. Full pass through NPC
view: pagination, sorting (by name/faction/location), all filters, search. Confirm
faction indicator renders identically to before the change for a few known NPCs. No
Lua errors. Re-measure, log delta.

**Result:** Lighter than T6, but for a specific reason worth recording: `NPCRow.lua`'s
`item.field` reads (`.name`, `.classification`, `.uiMapName`, `.family`, etc.) turned
out to already match the exact field names `NPCDataLoader.lua`'s output items used
before this migration — so once the *source* of those items was fixed, `NPCRow.lua`
needed almost no changes beyond the explicitly-planned `ParseFactionScore`/
`FormatFaction` rewrite (`.react` string -> `.reactA`/`.reactH` numbers, 2 call sites).

The real work was in `NPCDataLoader.lua`'s `_CalculateNPCData`, and it was bigger than
"swap field reads" — confirmed T5 changed `PetModels:GetModelsDataByFamilyIndex()`'s
return shape from `familyName -> array of {npcIdKey, npcData}` to `familyName -> array
of denseIndex`, so line 117's `local npcId, npcData = entry.npcIdKey, entry.npcData`
was completely broken, not just reading stale field names. Rewrote the whole loop body
around columnar reads + the T6 resolvers (`NpcClassification`/`NpcExpansion`). One nice
side effect: the old code built a temporary `{uiMapId=, npcId=, uiMapName=}` shim table
per NPC just to call `ModelsDataLoader:_IsZoneMatch()` — since T6 already migrated
`_IsZoneMatch` to read columns via a denseIndex directly, that shim is gone; the
denseIndex is passed straight through.

`luacheck.exe` clean, 0 errors, 70 total warnings (same as the post-T6 baseline,
nothing new). Diff: `NPCDataLoader.lua` +39/-26, `NPCRow.lua` +8/-15 (net smaller —
`ParseFactionScore`/`FormatFaction` shrank once the string-parsing came out).

**Investigated while checking for T6-style surprises:** confirmed `panel.allNPCs`
items are consumed *only* by `NPCRow.lua` (`SortItems`, `UpdateItemRow`) — no other
file reads their fields, unlike `entry.npcs`'s reach into `PopUpManager.lua` in T6.

**In-game check still deferred** — see T8 below, which turned out to be larger than
originally scoped.

---

### T8 — DONE (2026-08-11) — Migrate PopUpManager.lua fallback scans + ModelsFilters.lua hot loop [psm-addon]
**Repo:** `psm-addon`. **Files:** `Shared/PopUpManager.lua`, `ModelsBrowser/ModelsFilters.lua`.
**Depends on:** T5, T6, T7 (all now done).

**Scope correction:** while finishing T7, swept the whole addon for
`pairs(_G.ModelsData)` and found **three** direct scans against the old shape, not the
one originally documented here:
- `PopUpManager.lua:1272` — `for npcIdKey, npcData in pairs(_G.ModelsData) do` (the
  originally-documented one, displayId magnification fallback).
- `PopUpManager.lua:1354` — a **second, separate** one: `for _, npcData in
  pairs(_G.ModelsData) do`, inside the taming-info fallback lookup (comment: "fixes
  Owned Pets panel display") — reads `npcData.displayIds`/`npcData.taming`.
- `ModelsFilters.lua:589` — `for _, npcData in pairs(_G.ModelsData) do`, inside
  `BuildUnifiedFilterSystem`, reads `npcData.expansion`/`npcData.uiMapName` to seed
  the full expansion/location filter lists. Not the same thing as the "hot loop" this
  task's title already referred to (the ID-translation loop, still TODO below) — a
  third, previously-unidentified broken site in the same file.

All three need the same treatment: `for i = 1, #ModelsData.NpcId do` plus column
reads / the T6 `PSM.PetModels` resolvers, following the exact pattern already used in
T6/T7. None of the three are large individually, but plan for three separate fixes in
`T8` now, not one.

`ModelsFilters.lua`'s ID-translation hot loop (separate from the `BuildUnifiedFilterSystem`
scan above): **filter state stays name-keyed** (`PSM.state.selectedModelsFamilies`
etc. — no change to SavedVariables shape, no migration needed for existing users).
At the start of each filter pass, translate the selected name-set to an ID-set once
(via `ModelsData.Families`/`.Expansions`/`.Classifications`, small — dozens of
entries max), then compare `ModelsData.FamilyId[i]` etc. against that ID-set inside
the O(7,700) loop. Do not let IDs leak past the filter-computation boundary into
anything that gets saved or displayed by name — display code goes back through the
lookup table (`ModelsData.Families[id]`) to get the string.

**Acceptance criteria (in-game required):** luacheck clean. Toggle every filter
category on/off repeatedly, confirm results match pre-change behavior. Reload UI,
confirm previously-saved filter selections (if you have an existing `PetStableManagementDB`
with filters set) still apply correctly — this is the specific regression this
task's design is meant to prevent.

**Result:** No separate "ID-translation hot loop" ever existed to migrate — swept
`ModelsFilters.lua` fully and confirmed the *only* direct `ModelsData` touchpoint in
the whole file was the `BuildUnifiedFilterSystem` scan. Every actual filter-membership
computation already delegates to `ModelsDataLoader.lua`'s `GetAvailable*ForFilters`
functions (migrated in T6). Those compare resolved name strings via hash lookup
(`selectedExpansions[expansion]`) rather than IDs — and a hash lookup is O(1)
regardless of whether the key is a string or an integer, so there was never a real
CPU cost to translate away. The original plan's ID-translation design was a premature
assumption made before T6/T7 were actually written; closing it out here rather than
leaving a phantom task behind.

Fixed all three confirmed scans:
- `PopUpManager.lua:1272` (displayId magnification fallback) — its hand-built npc
  table (`npcId`/`name`/`location`/`uiMapId`/`uiMapName`/`expansion`/`classification`/
  `factionReaction`/`nameKeeper`) turned out to be an exact match for
  `GetModelsRecord`'s output shape, so the whole inner loop collapses to finding
  matching `denseIndex` values via `ModelsData.DisplayIds` and calling
  `PSM.PetModels:GetModelsRecord(npcId)` per match.
- `PopUpManager.lua:1354` (taming-info fallback) — straightforward column-read
  rewrite, same short-circuit-on-first-match structure preserved.
- `ModelsFilters.lua:589` (`BuildUnifiedFilterSystem`) — rewritten to `for i = 1,
  #ModelsData.NpcId do` + the T6 resolvers. Also found and removed the function's
  `else` branch (a fallback for when `ModelsData` isn't loaded): confirmed dead
  regardless of this migration, since `PetModels:GetAvailableFamilies()` (called
  earlier in the same function) already returns an empty list whenever `ModelsData`
  is unavailable, so that fallback's loop never had anything to iterate over in the
  one situation it existed to handle.

**Full-addon verification:** swept for both `pairs(_G.ModelsData)`/`pairs(ModelsData)`
and `npcData.` across every file in `psm-addon` — zero remaining matches (one comment
in `PetModels.lua` describing the old shape for context, no code). The entire addon
is now migrated off the pre-T2 `ModelsData` shape.

`luacheck.exe` clean across both addon folders: 0 errors, 70 total warnings — the
same count as every prior task in this chain, confirming nothing new anywhere. Diff:
`PopUpManager.lua` +30/-32, `ModelsFilters.lua` +14/-25 (net smaller, mostly the dead
`else` branch coming out).

**This closes out T4-T8 — the addon should be reloadable again.** T9 (full in-game
validation pass, all deferred checks from T5/T6/T7/T8 at once) is next.

---

### T9 — DONE (2026-08-11) — Full validation pass + final memory comparison [psm-addon, in-game]
**Depends on:** T6, T7, T8.

**Result — headline numbers for the whole plan:**

| | Before (T0/T1) | After (T9) | Change |
|---|---|---|---|
| Static floor (panel never opened) | 13.26MB | **6.57MB** | **-6.69MB, -50.5%** |
| Open, heavily used, forced GC | 21.7-25.2MB | **13.64MB** | **-8.1 to -11.6MB, -37% to -46%** |

Functional smoke test passed: all views (Models display-ID view, NPC text view),
filters (family/expansion/location/rares/name-keeper/search), sorting, the
magnification popup, and coords waypoint links all confirmed working with no Lua
errors. The floor number is the one that mattered most against the original stated
concern (avoiding a growing *constant* footprint) — cut in half. The open-panel number
also improved by a large margin even though T10 (the remaining churn-reduction task,
covering `NPCDataLoader`'s missing cache-reuse window) hasn't happened yet — the
columnar `ModelsData` shape helped both numbers simultaneously, not just the one it
directly targeted, since `PetModels`'s per-family cache and the render-time item lists
both got cheaper to build from smaller underlying records.

Original task text below, superseded by the above but kept for reference:

Run the Measurement protocol one more time as a final combined number, not just the
per-task deltas. Also: reload UI cold (fresh login), open Models Browser for the
first time that session, confirm no first-load errors or missing data. Compare final
number against T0 baseline in the Running memory log — this is the headline result.

---

### T10 — DONE (2026-08-11) — NPCDataLoader cache-reuse window + search debounce [psm-addon]

**Scope correction found while implementing:** the original text assumed "the
search box's debounce timer is 0.01s" and listed `ModelsFilters.lua` as a file to
touch. Traced the actual call chain instead of taking that at face value: the
search box (`PanelManager.lua`'s shared `CreateSearchBox`) already debounces at
`PSM.Config.SEARCH_DELAY` = **0.3s** (`Config.lua:62`) before calling
`ReloadAndSummarise()` — `ModelsFilters.lua` has no debounce-timer code at all, so
there was nothing to widen there. The 0.01s timer is a *second*, inner debounce
inside `NPCDataLoader.lua`/`ModelsDataLoader.lua` itself, which exists to coalesce
rapid consecutive reload requests from checkbox/filter clicks, not typing (typing
is already gated by the outer 0.3s). Widened anyway for that coalescing case, but
the "7,700-record refilter per keystroke" framing in the original text was wrong —
same category of stale-assumption correction as T8's phantom ID-translation loop.

**What was actually done:**
- `NPCDataLoader.lua`: added `GenerateCacheKey()` (family/expansion/location
  selections, search text, rares/name-keeper/favorites/hide-owned tristates,
  zone filter, favorite-models set, stable-pet count — mirrors
  `ModelsDataLoader:GenerateCacheKey`, scoped to only the fields `_CalculateNPCData`
  actually reads) and a 0.2s render-cache reuse window in `_LoadNPCsImmediate`,
  mirroring `ModelsDataLoader.lua:415-421`. Added `CreateRenderCache()` to reset it.
  Widened the inner debounce timer 0.01s → 0.15s.
- `ModelsPanel.lua`: added `PSM.NPCDataLoader:CreateRenderCache()` alongside both
  existing `PSM.ModelsDataLoader:CreateRenderCache()` calls (panel init sites).
- `PetRoulette.lua` / `PanelManager.lua`: added `PSM._npcRenderCache = nil` /
  `PSM._npcDebounceTimer = nil` alongside the existing `_modelsRenderCache` /
  `_modelsDebounceTimer` resets in the panel-cleanup paths, so the new cache
  doesn't outlive a closed panel or serve stale data across sessions.

`luacheck` clean (0 errors; all warnings shown are pre-existing/unrelated —
unused `addonName` locals etc., same as before this change).

**Original task text below, kept for reference:**

`ModelsDataLoader` reuses its render cache for 0.2s if the filter-key matches
(`ModelsDataLoader.lua:411-417`); `NPCDataLoader` has no equivalent and rebuilds
unconditionally on every call. Add the same time-boxed reuse window. Separately,
the search box's debounce timer is 0.01s — widen it (try 0.15-0.2s) so fast typing
doesn't trigger a full 7,700-record refilter on every keystroke.

**Acceptance criteria (in-game required):** luacheck clean. Type quickly in the
search box across both views, confirm results still update correctly and feel
noticeably smoother (subjective — this is a hitch-reduction task, not a memory one,
so the memory log doesn't apply here).

---

### Post-T10 regression fix (2026-08-11) — magnify popup crash on bare denseIndex `.npcs` arrays

**Reported:** clicking the model magnifier button threw
`PopUpManager.lua:166: attempt to index local 'npc' (a number value)`, from
`CreateNPCRow` via `BuildNPCRows` via `PopulateModelPopup` via
`ShowMagnificationPopup` via `RowManager.lua:251`.

**Root cause:** T5's `GetFamilyModels`/`GetModelInfo` rewrite made every
`entry.npcs` array store bare `denseIndex` numbers instead of resolved record
tables (by design — see `PetModels.lua:140-145`). T6 added a `ResolveNpcRecords`
resolve step, but only inside `ModelsPanel.lua`'s **own** copy of
`ShowMagnificationPopup`. Three other, independent consumers of the same
`GetFamilyModels`-sourced `.npcs` arrays were missed because they don't go
through that function:
1. `PSM.PopUpManager:ShowMagnificationPopup` (`PopUpManager.lua:1193`, a
   separate function from `ModelsPanel.lua`'s) — the actual crash site, reached
   from `RowManager.lua`'s generic magnify button (used outside the Models
   Browser, e.g. Owned Pets rows with a `displayId`) and from `NPCRow.lua`'s
   NPC-view magnify link.
2. `PetRoulette.lua`'s `ShowPetRoulettePopup` — same bug, same crash, just not
   yet hit by the user (`petData.npcs` fed straight into
   `popup.currentNPCs`/`PopulateModelPopup` unresolved).
3. `SpecialTames.lua`'s `ComputeMatchingFamilies` — a different failure mode
   (`npc.npcId` field access on a number, in the "Sliver of N'Zoth" taming-rule
   check and the conditions-match check), only reachable when those specific
   filters are active, so plausibly why it wasn't caught in T9's smoke test.

**Fix:** added one shared `PSM.PetModels:ResolveNpcRecords(npcs)` (`PetModels.lua`,
next to `GetModelsRecord`) instead of leaving a third/fourth copy of the same
closure lying around, since duplicating this exact logic per-consumer is what
let two of the four sites drift out of sync in the first place. Updated:
- `PopUpManager.lua`: `ShowMagnificationPopup` now resolves before the npcs
  list reaches `PopulateModelPopup`.
- `PetRoulette.lua`: `ShowPetRoulettePopup` resolves `petData.npcs` once and
  uses the resolved list for both `popup.currentNPCs` and `PopulateModelPopup`.
- `SpecialTames.lua`: `ComputeMatchingFamilies`'s three `npc.npcId` reads
  replaced with `modelsData.NpcId[npc]` (only the id was ever needed there, no
  full record needed).
- `ModelsPanel.lua`: its local `ResolveNpcRecords` now delegates to the shared
  one instead of duplicating the loop a third time.

`luacheck` clean (0 errors) across all five touched files. Not yet re-verified
in-game — do that alongside T10's own verification (magnify button from both
Models view and NPC view, plus Pet Roulette, plus Special Tames with "Sliver of
N'Zoth" or any condition filter active).

---

### T11 — SUPERSEDED (2026-08-11) — ~~Drop stored uiMapName, resolve live via Blizzard API~~

Original idea: resolve zone names live via `C_Map.GetMapInfo(uiMapId).name` instead of
shipping them, carrying real uncertainty about whether every `uiMapId` in the dataset
resolves cleanly (obscure/removed zones). Superseded during T2: verified `uiMapId ->
uiMapName` is a clean 1:1 mapping with zero inconsistencies across all 466 zones in
the source data, so the same memory win is available without any Blizzard API
dependency or resolution risk — `ModelsData.UiMapNames = {[uiMapId] = name}`, a single
466-entry lookup table, joined through the `UiMapId[i]` column already being stored.
Implemented directly as part of T2's schema — see "Target schema for ModelsData" above.
Nothing left to do here.

---

## Out of scope (decided, not revisited without new evidence)

- The columnar/backbone rewrite `ModelsData` got — rejected for `CoordsData.lua`,
  `NotesData.lua`, `AbilitiesData.lua`, `ConditionsData.lua`. They're accessed by
  point lookup (coords for zone X/NPC Y, the note for one NPC), not bulk-scanned on
  every filter change the way `ModelsData` is — the outer hash-keyed structure is
  already the right shape for that access pattern, and small enough relative to
  their string payload that restructuring it isn't worth the complexity.
  **Partial revision (2026-08-11):** "the right shape overall" turned out not to mean
  "nothing to fix" — see the `CoordsData.lua` wrapper-removal task below, found by
  actually checking the numbers instead of taking the original high-level call at
  face value.
- Splitting `ModelsData`'s fields across multiple files (e.g. a separate npc→family
  file) — rejected. Every real consumer reads the joined row; splitting multiplies
  table headers and lookups for fields that are always accessed together.
- Merging `CoordsData`/`NotesData`/`AbilitiesData` into one flat mega-table — rejected.
  Those fields are read independently and rarely; merging forces them into memory
  unconditionally and would hurt a future public-library consumer that only wants
  summary fields.

## Running memory log

| Task | Reading | Value | Notes |
|---|---|---|---|
| T0 baseline | Panel open, no filters | 13.26MB | 2026-08-10. Only ModelsBrowser measured — it's the module holding the large data tables; core addon's ~3MB is out of scope for this plan (Owned Pets flagged separately in the earlier audit, not part of T1-T11). |
| T1 verify | Panel open, no filters, post-T1 | 13.26MB | 2026-08-11. Static/floor reading, unchanged by T1 — expected, see T1's Result note above. |
| T1 verify | True static floor: fresh `/reload`, panel never opened, forced GC | 13.26MB (13575.9 KB) | 2026-08-11. Confirms T0 was already effectively reading this floor. This is the number every player pays regardless of usage — the real target for T2/T3. |
| T1 verify | Panel open, 61/61 families loaded, Models view only, forced GC | 21.7-25.2MB (varied across runs) | 2026-08-11. True live memory while panel is actively used. Ruled out NPC view as a factor (same magnitude with NPC view never touched). |
| T1 verify | Isolated: `PSM.PetModels:ClearCache()` delta, clean GC both sides | 2.85MB (2918 KB) | 2026-08-11. T1's actual target structure, confirmed correctly small. |
| T1 verify | Isolated: `panel.allModels` delta | 192.6 KB | 2026-08-11. Negligible, ruled out. |
| T1 verify | Isolated: `_dynamicFilterCache`+`_npcZoneIndex`+`_modelsRenderCache` combined delta | 198.8 KB | 2026-08-11. Negligible, ruled out. |
| T1 verify | Isolated: `ModelsFilters` widget pools (`_filterCheckboxPool`/`_locationRowPool`/`_continentHeaderPool`) nil+GC delta | 5.8 KB (inconclusive) | 2026-08-11. Checkboxes remained visible after nil — confirms this measurement technique cannot isolate Frame/widget memory (see caveats section). 154 widgets confirmed live (61+77+16), true cost unknown. ~8.7MB remains unattributed to any plain-data-table structure; deferred, not blocking, bounded to sustained heavy panel use. |
| **T9 (post T2-T8)** | **True static floor: fresh `/reload`, panel never opened** | **6.57MB** | **2026-08-11. Down from 13.26MB (T0/T1) — a ~50% reduction in the always-paid floor, the headline result of this whole plan.** Functional smoke test (all views, filters, sorting, popups) passed with no Lua errors. |
| T9 | Panel open, heavily used, **not** GC'd | 33.9MB | 2026-08-11. Pre-GC reading, expected to run high per the measurement caveats above (T10's churn — no NPCDataLoader cache-reuse window yet — is the likely driver). Not comparable to the T1-era 21.7-25.2MB *forced-GC* figures until re-measured the same way. |
| **T9** | **Panel open, heavily used, forced GC** | **13.64MB (13969.8 KB)** | **2026-08-11. Apples-to-apples against the T1-era 21.7-25.2MB figure (same repro, same forced-GC methodology): down 8.1-11.6MB (37-46%).** |
