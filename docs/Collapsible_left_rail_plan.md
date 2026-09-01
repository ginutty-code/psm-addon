# Collapsible left rail (Owned Pets, then Models Browser)

## Context

Both panels carry a vertical filter rail down their left edge:

- **Owned Pets** — three `PanelManager:CreateRailBox` frames (`toolsFrame`,
  `showOnlyFrame`, `filtersFrame`), built in `ns.UI:BuildFilters`
  (`OwnedPets/Filters.lua`), width measured to their own content (~115–130px). The
  pet list's `scrollFrame` anchors its `TOPLEFT` to `panel.toolsFrame`'s `TOPRIGHT`
  (`OwnedPets/Panel.lua:164`), and `rowsFrame` (the decorative border) follows
  `scrollFrame`. Panel is **resizable**, 500–570px in normal use, and already has a
  battle-tested width-change reflow path
  (`PanelManager:CreateScrollPreservingResizeHandler` → `ns.UI:RenderPanel(true)`).
- **Models Browser** — `toolsFrame` / `showOnlyFrame` / `unifiedFilterFrame`,
  hand-rolled `Widgets.Frame` at a flat `size = {210, N}`
  (`ModelsBrowser/ModelsPanel.lua:430`, `ModelsFilters.lua:634`). `petsFrame` anchors
  its `TOPLEFT` to `panel.showOnlyFrame`'s `TOPRIGHT`. Panel is **`resizable =
  false`** (`ModelsPanel.lua:186`), fixed 1100px, uses **pagination**
  (`GoToPage` / column width from `panel.petsFrame:GetWidth()`,
  `ModelsPanel.lua:122`), and has **no `OnSizeChanged` reflow path at all**.

**Goal:** one shared "collapse the whole rail as a unit" primitive in `PanelManager`.
When collapsed the rail hides and the content area (list / pets grid) reclaims its
width; the state persists. Per-section accordion behaviour was considered and set
aside — see the design discussion in chat; this plan is the single-unit collapse
only.

**The two panels are not symmetric.** Owned Pets gets the primitive plus the wiring,
leaning on machinery that already exists, and delivers a large proportional gain
(≈416px list → ≈530px at the 570px default). Models Browser needs (a) a prerequisite
migration of its three rail frames onto `CreateRailBox`, and (b) genuinely new
"reflow on demand" wiring, since nothing there reflows on a geometry change today.
**Ship Owned Pets first and complete; Models Browser is a real follow-up, not the
same change.**

### Strategic direction — this is groundwork for a width-resizable Models Browser

Making the Models Browser panel **resizable, primarily on width** is a standing
goal. It is hard — a recent attempt was discarded for want of care and prerequisites
— and it is not in scope here. But it is the destination every step in this area is
walking toward: the rail-box standardization, this rail collapse, and the shared
`PanelManager` primitives all exist to get the browser to the point where a resize
handler can be added safely.

**Constraint on every decision from here on: nothing may conflict with that goal.**
Concretely for this plan:

- The collapse's reflow callback (`onToggle`, §5) is built as **the panel's one
  content-reflow entrypoint** — the same function a future `OnSizeChanged` handler
  will call. Rail collapse is simply its first caller. Do not write it as a
  collapse-only special case.
- `CreateRail` gives the browser one frame whose right edge the pets area keys off.
  That is exactly the seam a resize handler needs, so the collapse work leaves the
  browser closer to resizable, not further.
- `resizable = false` is treated as a **current state, not a fixed constraint.**

**Repo/branch:** `psm-addon`, on `main`. Nothing in `psm-data` changes.

---

## What already exists (reuse, don't rebuild)

| Need | Already there |
| --- | --- |
| The rail-box shape (dark fill, silver border, gold section band) | `PanelManager:CreateRailBox` (`Shared/PanelManager.lua:452`) — Owned Pets uses it three times; Models Browser hand-rolls the identical shape three times. |
| A collapse toggle affordance | `Widgets.IconButton` with `skin = "collapsebutton"` and `UI-PlusButton` textures — the exact pattern `GroupedView.lua:374` uses for per-group collapse. |
| Collapse-state persistence pattern | `PetStableManagementDB.settings.panelViewMode` — a plain layout preference, read with `... or <default>` at `Panel.lua:12/77/282`, written directly on the control's click (`Panel.lua:268`). **No `FILTER_KEYS` machinery** — that is for filters, and a collapsed rail is not a filter. `PetStableManagementDB.collapsedGroups` (`GroupedView.lua:22`) is the same idea for a bool map. |
| Width-change reflow (Owned Pets only) | `PanelManager:CreateScrollPreservingResizeHandler` + `ns.UI:RenderPanel(true)`. All three view modes (list/grid/grouped) share `scrollFrame`/`content` and recompute from `scrollFrame:GetWidth()`, so grid re-columns for free. |
| Content-area width tracking the rail (Owned Pets) | `scrollFrame` point 1 is anchored to the rail's first box, not to a literal x. Move what that anchor points at and the list edge follows with no scroll-frame code change. |
| "What's hidden is still visible" | `panel.filterSummaryText` — the faint "Filters: …" line under the search box (`Filters.lua:613`, `GenerateFilterSummary`). It is panel-anchored, not rail-anchored, so it stays put when the rail collapses and keeps active filters legible. This is why no extra "you have hidden filters" badge is needed. |
| Independent top controls | Search box, Reset Filters button, and `panel.sortDrop` are all anchored to `panel` (`Filters.lua:499`, `BuildSortButtons`), never to the rail. They do not move when the rail collapses. |

---

## Design

### 1. `PanelManager:CreateRail(panel, opts)` — new shared container (`Shared/PanelManager.lua`)

An invisible container frame that owns the rail column, so "the rail" is one frame to
hide/move rather than a list of boxes each panel tracks by hand. This is the
"centralize the rail code in PanelManager" half.

```lua
-- PanelManager:CreateRail(panel, opts) -> rail
--   opts = {
--     point       = { x, y },   -- TOPLEFT offset from panel TOPLEFT (rail top)
--     width       = <number>,   -- measured rail width
--     bottomInset = <number>,   -- gap from panel BOTTOM (defaults to footer room)
--     savedKey    = "ownedRailCollapsed",  -- PetStableManagementDB.settings key
--     collapsedGap = 8,         -- px the content edge sits from panel-left when collapsed
--     onToggle    = function(collapsed) ... end,  -- panel-specific refresh
--   }
--
-- rail fields/methods:
--   rail.boxes              -- array, in stack order (filled by CreateRailBox)
--   rail:AddBox(box)        -- append + stack under the previous box
--   rail:IsCollapsed()      -- reads the saved bool
--   rail:SetCollapsed(bool) -- hide/show boxes, move the rail, persist, call onToggle
--   rail:ToggleCollapsed()
```

- `rail` is a bare `Widgets.Frame` (no backdrop), parented to `panel`, sized
  `{width, panelHeight - top - bottomInset}`, anchored `TOPLEFT` at `opts.point`.
- **Collapse mechanic — move the rail off the left edge, don't zero its width.**
  `SetCollapsed(true)` hides every box in `rail.boxes` and re-anchors the rail to
  `{ "TOPRIGHT", panel, "TOPLEFT", opts.collapsedGap, y }` — the whole container
  slides off-panel so its *right* edge sits `collapsedGap` px inside the panel's left
  border. `SetCollapsed(false)` restores `{ "TOPLEFT", panel, "TOPLEFT", x, y }` and
  shows the boxes. A zero-width frame was rejected: WoW clamps tiny frame sizes and
  `Relayout` (§3) calls `scrollFrame:SetWidth` on a settle, so a width-based collapse
  invites a fight; a position-based one does not.
- Because the content area anchors to `rail`'s `TOPRIGHT` (§3/§5), moving the rail
  drags the content edge with it — the helper needs **zero** knowledge of the
  scroll frame or the pets grid.
- The **toggle button is parented to `panel`, not `rail`** (so it survives the hide):
  a `Widgets.IconButton { skin = "collapsebutton" }`, ~16px, anchored top-left near
  the rail's top corner (roughly `{ "TOPLEFT", panel, "TOPLEFT", 6, opts.point[2] }`),
  left/right chevron texture (or the `UI-PlusButton` +/- pair `GroupedView` uses),
  tooltip "Collapse tools and filters" / "Expand tools and filters". Created inside `CreateRail` and
  stored as `rail.toggleButton`.
- `CreateRail` reads `PetStableManagementDB.settings[savedKey]` at build time and
  applies the initial state after the boxes are added (a `C_Timer.After(0, …)` or an
  explicit `rail:ApplyInitialState()` the caller invokes once its boxes exist).

### 2. `CreateRailBox` gains rail-awareness (`Shared/PanelManager.lua:452`)

Small extension, backward-compatible:

- Accept `opts.rail` (the `CreateRail` container) as an alternative to the current
  `panel` parent. When given, parent the box to `rail`, append it to `rail.boxes`,
  and stack it: first box at the rail's top, each subsequent box
  `{ "TOPLEFT", <prev box>, "BOTTOMLEFT", 0, -5 }`. This replaces the hand-rolled
  `showOnlyY = toolsY - toolsBox:GetHeight() - 5` arithmetic at the Owned Pets call
  sites and the `{ "TOPLEFT", prevBox, "BOTTOMLEFT", 0, -5 }` chains in Models
  Browser — both panels stack identically.
- The `point`/`contentTop` return contract is unchanged for existing callers that
  still pass `panel` + `{x, y}`.

### 3. Owned Pets wiring (`OwnedPets/Panel.lua`, `OwnedPets/Filters.lua`)

- **`BuildFilters`** — build `panel.rail = PanelManager:CreateRail(panel, { point =
  {10, railTop}, width = RailWidth(), savedKey = "ownedRailCollapsed", onToggle =
  <refresh>, … })`, then create the three boxes with `rail = panel.rail` instead of
  `panel` + computed `{x, y}`. `panel.toolsFrame` / `showOnlyFrame` / `filtersFrame`
  keep their field names (Panel.lua's Tools buttons, `UpdateFilterUI`, the Reset
  handler all read those by name — unchanged).
- **`onToggle`** — one `C_Timer.After(0.01, function() ns.UI:RenderPanel(true) end)`.
  This is the same call the existing `onResize` path makes; the collapse is just
  another reason to run it.
- **`AddOwnedPetsElements`** — change `scrollFrame` point 1 from
  `{ "TOPLEFT", panel.toolsFrame, "TOPRIGHT", 14, -ROW_BORDER_INSET }` to
  `{ "TOPLEFT", panel.rail, "TOPRIGHT", 14, -ROW_BORDER_INSET }`. `rowsFrame` already
  follows `scrollFrame`; `sortDrop`, the search box, the filter summary and Reset are
  all panel-anchored and untouched.
- **`onShow`** — after the panel is built, call `panel.rail:ApplyInitialState()` so a
  saved collapsed rail comes back collapsed. (Or fold this into `CreateRail` via a
  deferred timer — decide during implementation; `onShow` is explicit and matches how
  `panelViewMode` is restored at `Panel.lua:77`.)
- **`Relayout` interaction (verify in-game).** `CreateScrollPreservingResizeHandler`'s
  `Relayout` does `scrollFrame:SetWidth(panel:GetWidth() - 40)` on every settle. The
  scroll frame has *both* a `TOPLEFT` (→ rail) and a `BOTTOMRIGHT` (→ panel) anchor,
  so the dual anchor should win and that `SetWidth` should be inert. Confirm that;
  if it actually overrides, change that line to derive width from
  `scrollFrame:GetLeft()` / the rail's right edge, or skip it while collapsed.

### 4. Persistence

- `PetStableManagementDB.settings.ownedRailCollapsed` — bool, default `false`.
- Add it to the documented defaults block at `Core.lua:36` (alongside
  `panelViewMode`), read everywhere with `... or false`, written only by
  `rail:SetCollapsed`.
- No `ns.state` entry (it is a persisted layout pref, not runtime filter state), no
  `FILTER_KEYS` / `NIL_FILTER_KEYS` / `SaveSettings` touchpoints.

### 5. Models Browser — prerequisite migration, then the same wiring (follow-up)

**5a. Migrate the three rail frames onto `CreateRailBox`** (behaviour-neutral, its own
PR, worth doing regardless of collapse — satisfies the A6 "everything through the
shared factory" direction and removes a known drift risk).

- Replace the three `Widgets.Frame { backdrop = "TOOLTIP", … }` + `SectionHeader`
  blocks (`ModelsPanel.lua:430`/`445`, `ModelsFilters.lua:634`) with three
  `CreateRailBox` calls, `width = 210`.
- Translate the literal heights to `contentHeight` (`CreateRailBox` adds
  `5 + SECTION_HEADER(22) + 6 + … + 8 = 41`): `{210,125} → contentHeight 84`,
  `{210,160} → 119`, `{210,440} → 399`. Re-tune in-game if the band height differs
  (it should not — same `SectionHeader` widget).
- `CreateToolsBox`, the toggle rows, and `BuildUnifiedFilterSystem` anchor their
  contents to `panel.toolsFrame` / `showOnlyFrame` / `unifiedFilterFrame` by field
  name and to `.sectionHeader` — `CreateRailBox` sets `box.sectionHeader`, so those
  line up. Keep the field names.
- `petsFrame`'s anchor to `showOnlyFrame` `TOPRIGHT` still resolves.

**5b. Collapse wiring** — build `panel.rail = PanelManager:CreateRail(panel, { …,
savedKey = "modelsRailCollapsed", onToggle = … })`, add the three boxes into it,
re-anchor `petsFrame` point 1 from `showOnlyFrame` `TOPRIGHT` to `panel.rail`
`TOPRIGHT` (re-tune the `PETS_FRAME_TOP_LIFT = 50` vertical fudge — its reference
frame changes).

**`onToggle` here is new wiring, not a reuse — and it is the seam width-resizability
will need.** Nothing in the Models Browser reflows on a geometry change today. Build
it as a named `panel:ReflowContent()` (or `PSM.ModelsPanel:ReflowContent(panel)`),
not an inline closure, so a future `OnSizeChanged` handler calls the same function.
It must:

- call `GoToPage(panel, panel.currentPage)` so `ReflowCards` recomputes column width
  from the new `petsFrame:GetWidth()`;
- re-lay-out the **NPC-view** column grid (its own row/column code) and reposition
  the **pagination footer**;
- handle both `panel.modelsViewMode` values;
- assume it may be called repeatedly and mid-drag later — keep it idempotent and
  cheap, mirroring `CreateScrollPreservingResizeHandler`'s settle-timer discipline.

`settings.modelsRailCollapsed`, default `false`, documented at `Core.lua:53` beside
`modelsViewMode`.

### 5c. Post-ship fixes from the Owned Pets rollout (carry forward to 5b)

Two bugs surfaced after Owned Pets shipped, both fixed in `Shared/PanelManager.lua`
and both relevant here:

- **Toggle icon direction.** The `RAIL_ICONS.npe` atlas mapping had `expand`/
  `collapse` swapped (arrow pointed the wrong way for what the click was about to
  do). Fixed in the shared `RAIL_ICONS` table in `CreateRail`, so **no action needed
  for Models Browser** — 5b inherits the corrected mapping automatically.
- **`SetWidthAnchored` can push a maximized panel off-screen.** Owned Pets' rail
  lives in the panel's own width (expand adds `railW` to the panel, keeping the pet
  list the same size either way — see §3). When the panel was already maximized
  (`width == UIParent:GetWidth() - 16`, the same bound `ApplyResizeBounds` enforces),
  expanding the rail added `railW` on top of that and the right edge went past the
  screen edge. Fixed by clamping `SetWidthAnchored`'s target width to
  `panel._resizeConfig.maxWidth` (or the same `UIParent:GetWidth() - 16` fallback) —
  at that bound the panel stops growing and the content anchored to the rail's
  moving edge narrows instead of overflowing.

  **Doesn't bite Models Browser today** (`resizable = false`, `showMaximizeButton =
  false` — `ModelsPanel.lua:186/188` — so its width never changes at all, maximized
  or not). It becomes live the moment the Models Browser width-resizability goal is
  implemented (`docs/architecture.html` / long-standing goal captured in project
  memory) and that panel gets a rail whose expand adds to panel width — at that
  point re-check this clamp still does the right thing rather than re-deriving it.

### 6. Non-goals (explicit)

- **`MIN_PANEL_WIDTH` is not lowered when collapsed** *in this change*. Collapse
  already gives more list room at any given width, and dynamically varying the
  minimum interacts with the maximize/restore geometry round-trip
  (`docs/Backlog.md:93`). This is deferred, not foreclosed — a collapse-aware
  minimum is a plausible part of the later resizability work.
- **No slide animation** for v1 — instant hide/show. An OnUpdate width tween is a
  later polish item.
- **No per-section accordion** — this plan is the single-unit collapse only.

---

## Files

**Owned Pets (the shippable change):**

| File | Change |
| --- | --- |
| `PetStableManagement/Shared/PanelManager.lua` | new `CreateRail`; `CreateRailBox` gains optional `rail` parent + auto-stacking |
| `PetStableManagement/OwnedPets/Filters.lua` | `BuildFilters` builds `panel.rail` and creates the three boxes into it; defines `onToggle` |
| `PetStableManagement/OwnedPets/Panel.lua` | `scrollFrame` point 1 anchors to `panel.rail`; `onShow` applies the saved collapse state |
| `PetStableManagement/Core.lua` | `ownedRailCollapsed = false` in the settings defaults block |
| `PetStableManagement/Shared/Locale.lua` | `L("Collapse tools and filters")`, `L("Expand tools and filters")` (tooltip) |

**Models Browser (follow-up, two PRs):**

| File | Change |
| --- | --- |
| `PetStableManagement_ModelsBrowser/ModelsBrowser/ModelsPanel.lua` | 5a: `toolsFrame`/`showOnlyFrame` → `CreateRailBox`. 5b: `panel.rail`; `petsFrame` re-anchor; `onToggle` reflow wiring |
| `PetStableManagement_ModelsBrowser/ModelsBrowser/ModelsFilters.lua` | 5a: `unifiedFilterFrame` → `CreateRailBox` |
| `PetStableManagement/Core.lua` | `modelsRailCollapsed = false` |

No `.toc` change (no new files). No `Shared/PublicAPI.lua` change — `PanelManager` is
already reachable from the browser (`ModelsPanel.lua:182` calls
`PSM.PanelManager:CreateBasePanel`), so adding methods to it exposes nothing new.
No `.luacheckrc` change — `ownedRailCollapsed` / `modelsRailCollapsed` are
`PetStableManagementDB.settings` keys, not globals.

---

## Verification

**Headless:**

```bash
lua.exe Tests/run.lua
```

The collapse is frame construction — no direct headless coverage, same as
`panelViewMode`. If the "collapsed anchor offset" / rail-width math ends up as a pure
function, add a case or two to `utils_spec` for it; otherwise this is in-game
territory.

**Lint:**

```bash
"C:\Users\Gi\Dev\tools\luacheck.exe" PetStableManagement PetStableManagement_ModelsBrowser Tests
```

Expect **10 warnings / 0 errors** unchanged.

**In-game (Owned Pets):**

1. Toggle collapse at the default panel size: rail hides, pet list widens to fill the
   freed column, toggle button stays visible and its tooltip flips.
2. Expand again: the three boxes return in the right order, list returns to its
   previous width, no visual gap or overlap at the rail's border.
3. Collapse, `/reload`, reopen the panel: it comes back collapsed.
4. Collapse, then resize the panel down to `MIN_PANEL_WIDTH` (500) and back up:
   the list tracks the width with no rail artifact; confirm `Relayout`'s `SetWidth`
   doesn't override the anchor (§3).
5. Collapsed, switch List / Grid / Grouped: each reflows to the wider content area
   (grid re-columns).
6. Collapsed, confirm the "Filters: …" summary line still shows active filters, and
   the search box / Reset / Sort by are where they were.
7. Expanded, confirm every dropdown and the three Show Only checkboxes still behave
   exactly as on `main`.

**In-game (Models Browser, follow-up):**

8. After 5a alone (no collapse yet): all three rail boxes render unchanged in
   position, size and content, in both `displayId` and `npc` view.
9. After 5b: collapse widens the pets grid; `ReflowCards` re-columns; NPC-view
   columns and the pagination footer reposition; state survives `/reload`.

---

## Suggested sequence

1. **`Add PanelManager:CreateRail + rail-aware CreateRailBox`** — shared primitive,
   no call sites yet, no behaviour change.
2. **`Make the Owned Pets left rail collapsible`** — `BuildFilters` builds the rail,
   `scrollFrame` re-anchor, `onShow` restore, settings default, locale. The
   shippable unit.
3. *(follow-up PR)* **`Migrate the Models Browser rail frames to CreateRailBox`** —
   behaviour-neutral 5a.
4. *(follow-up PR)* **`Make the Models Browser left rail collapsible`** — 5b, incl.
   the new reflow-on-toggle wiring.
