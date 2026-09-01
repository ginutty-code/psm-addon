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

**5a. Migrate the rail frames onto `CreateRailBox`** (behaviour-neutral, its own
PR, worth doing regardless of collapse — satisfies the A6 "everything through the
shared factory" direction and removes a known drift risk).

**Decided during implementation: two of the three boxes, not three.**
`toolsFrame` and `showOnlyFrame` migrate; `unifiedFilterFrame` (the Families/
Expansions/Locations box) deliberately does not, this PR. It already has its own
title-equivalent — the tab row — and `CreateRailBox`'s gold section band stacked on
top of that read as "too much gold in one place" plus an open question about
redesigning the tab/pill look, which is a separate decision from this migration and
was not litigated here. Splitting it out kept this PR behaviour-neutral in fact, not
just in name — bolting a header onto a box that never had one is a visible change
`CreateRailBox` cannot currently opt out of (no "headerless" mode).

This costs nothing at the 5b stage: `rail:AddBox(box)` only re-anchors a frame and
toggles `:SetShown()` — it has no dependency on the box being a `CreateRailBox`
product. Bringing `unifiedFilterFrame` into the rail in 5b is just reparenting it to
`panel.rail` and dropping its explicit `point`, the same amount of work either way.
If the tab/header redesign happens first, revisit giving it a `CreateRailBox` shape
then; otherwise 5b adds it via `AddBox` headerless, same as the other two.

- Replaced the two `Widgets.Frame { backdrop = "TOOLTIP", … }` + `SectionHeader`
  blocks (`ModelsPanel.lua:430`/`445`) with two `CreateRailBox` calls, `width = 210`.
- Translated the literal heights to `contentHeight` (`CreateRailBox` adds
  `5 + SECTION_HEADER(22) + 6 + … + 8 = 41`): `{210,125} → contentHeight 84`,
  `{210,160} → 119`. `unifiedFilterFrame` stays `{210,440}` flat, unchanged.
- `showOnlyFrame`'s y is derived from `toolsFrame:GetHeight()`, not a second hardcoded
  literal, so the two can't drift out of sync if a `contentHeight` changes later.
  `unifiedFilterFrame` still anchors to `showOnlyFrame`'s `BOTTOMLEFT` by frame
  reference (unchanged), so it needed no equivalent math.
- `CreateToolsBox` and the toggle rows anchor their contents to `panel.toolsFrame` /
  `showOnlyFrame` by field name — `CreateRailBox` returns the same kind of `Frame`,
  so those line up unchanged. Kept the field names.
- `petsFrame`'s anchor to `showOnlyFrame` `TOPRIGHT` still resolves.

**5b. Collapse wiring — implemented as follows.**

- `panel.rail = PanelManager:CreateRail(panel, { point = {10, Theme.CHROME.TITLE_Y},
  width = 210, savedKey = "modelsRailCollapsed", onToggle = function()
  PSM.ModelsPanel:ReflowContent(panel) end })`, built first in
  `AddModelsBrowserElements`, before `toolsFrame`/`showOnlyFrame`.
- `toolsFrame`/`showOnlyFrame` pass `rail = panel.rail` instead of a flat `point`
  (dropping the 5a `GetHeight()`-derived offset — the rail's own stacking replaces
  it). `unifiedFilterFrame` (still a hand-rolled frame, see 5a) is parented to
  `panel.rail` and handed to `panel.rail:AddBox(panel.unifiedFilterFrame)` right
  after construction, with no explicit `point` — `AddBox` only re-anchors and
  toggles `:SetShown()`, so this costs nothing extra as anticipated in 5a.
- `petsFrame` point 1 re-anchored from `showOnlyFrame` `TOPRIGHT` to `panel.rail`
  `TOPRIGHT`. `PETS_FRAME_TOP_LIFT` became **`-80`** (was `+50`) — the rail's
  `TOPRIGHT` is level with `toolsFrame`'s top (well above where `showOnlyFrame`'s
  `TOPRIGHT` used to sit, by `toolsFrame`'s height + the 5px stack gap, i.e. 130px),
  so `50 - 130 = -80` keeps the *expanded*-state pixel position unchanged. X needed
  no change: the rail and every box in it share the same 210px width and left edge,
  so the rail's `TOPRIGHT` X already equals `showOnlyFrame`'s.
- **The rail lives in the *panel's* own width, same model as Owned Pets** —
  corrected after in-game testing, see 5d. The first pass here left the panel at a
  fixed `MODELS_CONFIG.PANEL_WIDTH` and let `petsFrame` absorb the freed column
  instead (reasoning: `resizable = false`, so no drag-resize to preserve); in-game
  that grew the model grid uncomfortably wide and didn't match what the user
  actually wanted, which was the panel itself shrinking down to the content plus a
  slim left margin, matching Owned Pets' collapsed look. `resizable = false` only
  disables the user's drag handle — `panel:SetWidth()` from code is unaffected — so
  `PanelManager:SetWidthAnchored` works here exactly as it does for Owned Pets.
  `onToggle` now does `SetWidthAnchored(panel, panel:GetWidth() -/+ RAIL_WIDTH)` then
  the reflow. No `SetMinWidth` call, unlike Owned Pets: that guards a resize grip's
  drag floor, and this panel has none.
- **`MODELS_CONFIG.PANEL_WIDTH` (1100) is the *expanded* baseline, not the collapsed
  one** — the opposite of Owned Pets' `DEFAULT_PANEL_WIDTH` convention. Deliberate:
  1100 already existed as this panel's size before the rail-collapse feature, so
  keeping it as the expanded default means nobody who has never touched the toggle
  sees any size change. `panel._railShrunk` is the restore-tracking bit (`onShow`
  subtracts `RAIL_WIDTH` once for a saved-collapsed panel, since construction always
  starts at the expanded 1100) — the same role as Owned Pets' `panel._railWidened`,
  just measured from the opposite baseline.

**`onToggle` calls `PSM.ModelsPanel:ReflowContent(panel)` — the panel's one
content-reflow entrypoint, per the strategic-direction constraint at the top of this
doc**, so a future `OnSizeChanged` width-resize handler can call the exact same
function rather than growing a second path. Its body is one line:
`GoToPage(panel, panel.currentPage or 1)`. That is sufficient, not a shortcut —
`GoToPage` already dispatches on `panel.modelsViewMode`
(`UpdateModelsPanelLayout` for the grid / `UpdateNPCPanelLayout` for the NPC table),
and both of those already re-derive their column geometry from
`petsFrame:GetWidth()` on every call — `UpdateModelsPanelLayout` recomputes
`columnWidth` directly; `UpdateNPCPanelLayout` calls `NPCRow:UpdateHeaderRow`, which
calls `NPCRow:RecomputeColumnLayout`, which reads `TableWidth(panel)` (itself
`petsFrame:GetWidth()`-derived). Re-rendering the *same* page is exactly
"recompute and redraw in place." **The pagination footer needed no explicit
reposition call**: every footer control (`firstButton`, `pageText`,
`pageJumpFrame`, …) is anchored directly to `petsFrame` (not to `panel` with a
hardcoded offset), so WoW's own anchor system moves them automatically the instant
`petsFrame` resizes — confirmed by reading every footer anchor in
`AddModelsBrowserElements` before writing `ReflowContent`, not assumed.
`GoToPage` is idempotent (re-clamps to the same page, re-persists the same value) and
cheap, so calling it repeatedly — including from a future mid-drag handler — is safe.

**Rail-state restore lives in `onShow`, mirroring Owned Pets' split**: `panel.rail:
ApplyInitialState()` (box visibility + rail position + toggle glyph, no `onToggle`),
then the same `_railShrunk`-guarded `SetWidthAnchored` the `onToggle` closure does
(construction always starts at the expanded width, so a saved-collapsed panel needs
one shrink applied here), then an explicit `PSM.ModelsPanel:ReflowContent(panel)`
call — needed because NPC view's `UpdateItemRow` reads a *cached*
`panel.npcColumnLayout` rather than recomputing it, so a saved-collapsed rail
restored without a following reflow would render the NPC table's columns at the
wrong (pre-restore) width until the next unrelated layout pass.

`settings.modelsRailCollapsed`, default `false`, documented at `Core.lua:51` beside
`modelsViewMode`.

### 5d. In-game fixes from the first 5b pass

Two bugs surfaced testing the above in-game, both fixed:

- **Show Only's five toggles (Rares/Favorites/Owned/Name Keepers/Pets in My Zone)
  rendered behind `showOnlyFrame`'s backdrop, and stayed on screen — outside the
  panel — when the rail collapsed.** Root cause: `ModelsFilters.lua`'s
  `CreateTristateCheckbox` built every checkbox with `panel` as its true parent
  (`Widgets.CheckBox(parent, ...)`, where `parent` is always the root panel at every
  call site), merely *anchored* near `showOnlyFrame`/the previous checkbox. Before
  5b this happened to look fine — `showOnlyFrame` was also a direct child of
  `panel`, so both sat at the same frame level. Once `showOnlyFrame` became a
  `CreateRailBox` product nested inside `panel.rail` (two levels deep instead of
  one), its backdrop's frame level rose above the checkboxes', drawing over them —
  and because a checkbox was never a true *child* of `showOnlyFrame`, hiding the box
  on collapse (`SetShown(false)`) didn't cascade to hide the checkbox, which kept
  tracking the box's (now off-panel) anchor position and rendered outside the
  panel. Fix: parent the checkbox to `parent.showOnlyFrame` instead of `parent`
  (`ModelsFilters.lua`'s `CreateTristateCheckbox`) — now a true child, so frame
  level and visibility both follow the box correctly. **General lesson for any
  future rail box**: content built *into* a rail box must be parented to the box
  itself, not to `panel` with a same-looking anchor — `toolsFrame`'s buttons and
  `unifiedFilterFrame`'s tabs/buttons/scrollframe were already correct (parented to
  their own box), which is why only Show Only showed this bug.
- **The rail-lives-in-content-area model was the wrong choice** — see the `onToggle`
  bullet above. Switched to the rail-lives-in-panel-width model instead, on
  explicit user direction after seeing the first version in-game.

### 5e. Left/right padding parity between the two panels

After 5b/5d shipped, side-by-side screenshots showed the two panels' rails with
opposite padding imbalances — a real, code-confirmed mismatch, not a perception
difference:

| | Left gap (panel edge → rail) | Right gap (rail → content) |
| --- | --- | --- |
| Owned Pets (before) | 28px | 14px |
| Models Browser (before) | 10px | 25px |

Two unrelated causes, both traced in code:

- **Models Browser's 25px right gap is scrollbar clearance, not arbitrary.**
  `unifiedFilterFrame`'s `filterScrollFrame` sits flush with the box's own right
  edge, and Blizzard's `UIPanelScrollFrameTemplate` anchors its `ScrollBar` ~4px
  outside the scroll frame's right edge plus the bar's own ~20px width — roughly
  24px of protrusion the 25px gap to `petsFrame` was sized to clear.
- **Owned Pets' 28px left gap was sized for the *collapsed* toggle, not the
  expanded view.** The toggle icon/word render at a small fixed offset from the
  panel's edge regardless of the rail's own inset (that part *is* identical shared
  code between the panels). What the inset actually controls is where the
  *collapsed* content border lands — 28 was picked so the rotated "Expand" word
  (~20px) doesn't crowd against it once collapsed.

User's call, after being shown this breakdown: **make both symmetrical at 25px on
both sides on both panels**, judging 25 (down from 28) still safe for Owned Pets'
collapsed-toggle clearance.

- `OwnedPets/Filters.lua` — `CreateRail`'s `point` x: `28 → 25`.
- `OwnedPets/Panel.lua` — `scrollFrame`'s rail→list gap: `14 → 25`.
  **Compensated**, on reconsideration: the first pass here left this uncompensated
  (net +8px of gap narrowing the pet list, reasoning that `DEFAULT_PANEL_WIDTH` is
  shared with `TeamsPanel`'s fallback width so growing it reaches outside this
  feature's scope). User's call after seeing it in-game: don't let the list absorb
  it, raise the floor instead — the repo already has precedent for growing this
  exact shared constant when a real layout need requires it (`DEFAULT_PANEL_WIDTH`
  went `550 → 570` before this project existed, for the same reason, and
  `TeamsPanel` riding along was called out as *intended*, not a side effect to
  avoid). `Shared/Config.lua`'s `DEFAULT_PANEL_WIDTH` / `MIN_OWNED_PETS_WIDTH`:
  `570 → 578` (both, kept equal on purpose per their existing comment). The math:
  scroll frame width = `panel:GetWidth() - railW - (leftInset + gap) - 30`
  (BOTTOMRIGHT's own -30) — before: `- (28+14) = -42`; after: `-(25+25) = -50`, an
  8px bigger subtraction exactly offset by `panel:GetWidth()` being 8px bigger, so
  the list's rendered width is unchanged in both rail states, verified algebraically
  for both expanded and collapsed. `TeamsPanel`'s fallback width grows by the same
  8px until a player resizes it, matching the existing 550→570 precedent exactly.
- `ModelsBrowser/ModelsPanel.lua` — `CreateRail`'s `point` x: `10 → 25` (right gap
  was already 25, unchanged). **Compensated** this time: `MODELS_CONFIG.PANEL_WIDTH`
  `1100 → 1115`, the exact +15px the left inset grew by, so `petsFrame`'s rendered
  size is unchanged from before this parity pass, in both rail states. Compensating
  here (unlike Owned Pets) was safe because `PANEL_WIDTH` is local to this one
  panel, and consistent because "petsFrame stays a constant size" was the explicit
  promise 5d had just established the session before.
- `NPCRow.lua`'s column-width comment updated — it asserted "the panel is a fixed
  1100 wide and not resizable," both halves stale after 5b/5d (width is now 1115
  baseline and does change via `SetWidthAnchored`). Not a functional dependency —
  `RecomputeColumnLayout` already reads `petsFrame:GetWidth()` live — just a doc
  fix so the comment doesn't mislead the next reader.

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

  **Now live for Models Browser too, as of 5b/5d** — this note originally said it
  didn't apply (`resizable = false` meant the panel's width never changed at all).
  That stopped being true once 5b's `onToggle` started calling `SetWidthAnchored`
  directly (`resizable = false` only ever disabled the user's drag handle, not
  programmatic `SetWidth` — see AddModelsBrowserElements). The clamp is inherited
  for free, no Models-Browser-specific code needed: `SetWidthAnchored` reads
  `panel._resizeConfig.maxWidth`, which `CreateBasePanel` sets unconditionally
  (line 132) regardless of `resizable`, so it falls back to
  `UIParent:GetWidth() - 16` here exactly as it does for Owned Pets. A panel sitting
  near the screen's right edge when the rail expands is clamped at that bound
  instead of growing off-screen, same guarantee, same code, no separate fix
  required.

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
| `PetStableManagement_ModelsBrowser/ModelsBrowser/ModelsPanel.lua` | 5a: `toolsFrame`/`showOnlyFrame` → `CreateRailBox` (`unifiedFilterFrame` deliberately left as-is, see 5a). 5b: `panel.rail`; `petsFrame` re-anchor; `onToggle` reflow wiring |
| `PetStableManagement_ModelsBrowser/ModelsBrowser/ModelsFilters.lua` | 5a: comment only, documenting why `unifiedFilterFrame` stays a plain frame. 5b: reparent it to `panel.rail` via `AddBox` |
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

Expect **9 warnings / 0 errors** unchanged (the documented `CLAUDE.md` baseline).

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
   position, size and content, in both `displayId` and `npc` view — including
   `unifiedFilterFrame`, which is untouched code but worth confirming nothing in
   `toolsFrame`/`showOnlyFrame`'s new construction path shifted its anchor.
9. After 5b: toggle collapse at the default 1100px width — Tools/Show Only/Filters
   hide as one unit, `petsFrame` widens to fill the freed column, and the grid
   re-columns (`ReflowContent` → `GoToPage` → `UpdateModelsPanelLayout`). Toggle
   button and tooltip behave as in items 1-2. Switch to NPC view and repeat: the
   column header/cells re-flow to the wider table and the pagination footer stays
   glued to `petsFrame`'s edges with no manual reposition. Collapse, `/reload`,
   reopen: comes back collapsed in both view modes, columns already at the
   restored width (not stale) on first paint. Confirm the rail's toggle icon/word
   don't collide with anything near the title bar at `TITLE_Y + 20`.

---

## Suggested sequence

1. ✅ **`Add PanelManager:CreateRail + rail-aware CreateRailBox`** — shared primitive,
   no call sites yet, no behaviour change.
2. ✅ **`Make the Owned Pets left rail collapsible`** — `BuildFilters` builds the rail,
   `scrollFrame` re-anchor, `onShow` restore, settings default, locale. The
   shippable unit. Shipped with two post-ship fixes, §5c.
3. ✅ **`Migrate the Models Browser rail frames to CreateRailBox`** — 5a, scoped down
   during implementation to `toolsFrame`/`showOnlyFrame` only (`unifiedFilterFrame`
   stays a plain frame; see 5a's "two of the three boxes" note). Confirmed unchanged
   in-game.
4. ✅ **`Make the Models Browser left rail collapsible`** — 5b: `panel.rail`, all
   three boxes (including the still-headerless `unifiedFilterFrame`, via `AddBox`),
   `petsFrame` re-anchor + `PETS_FRAME_TOP_LIFT` retune, `ReflowContent` as the
   reflow entrypoint, `onShow` restore, plus the two in-game fixes in 5d (Show Only
   checkbox parenting, rail-in-panel-width model). **Confirmed working in-game.**
5. ✅ **Owned Pets rail visual parity — reviewed, no code change.** Compared
   screenshots of both panels side by side. The toggle icon/word (rotation, nudge
   offsets, arrow-to-word spacing) and the rail box shape (fill, border, section
   band) are already pixel-identical by construction — both panels build them
   through the same shared `CreateRail`/`CreateRailBox` code in
   `Shared/PanelManager.lua`, with no per-panel styling hook to have drifted. The
   one real difference is the rail's *vertical start*: Owned Pets begins at
   `y = -123` (below its search/reset/sort row), Models Browser at `y = -35`
   (title level). Confirmed deliberate, not a bug: Owned Pets is a narrow 570px
   panel whose title dynamically grows to
   `"Pet Stable Management (using data from <timestamp>)"` — long enough to collide
   with the rail at title height — while Models Browser is 1100px wide, so its
   (much shorter) title never gets near the 210px rail column even at the same y.
   Raising Owned Pets' rail partway (to just below the search/sort row, ~y=-95,
   the slack the `LIST_TOP` comment already flags as an eyeballed margin) was
   offered and declined — placement stays as-is. Rail *width* differs between the
   panels for the same non-bug reason as always: each is sized to its own content
   (`RailWidth()`'s dropdown/button measurement vs. Models Browser's flat 210px),
   not a shared constant.
6. ✅ **Left/right padding parity, §5e — this one *did* need code.** The vertical
   review above wasn't the whole story: side-by-side screenshots also showed the
   two panels' rails with *opposite* left/right padding imbalances (Owned Pets
   28px-left/14px-right, Models Browser 10px-left/25px-right) — traced to two
   unrelated real causes (Owned Pets' 28 sized for collapsed-toggle clearance,
   Models Browser's 25 sized for `unifiedFilterFrame`'s scrollbar protrusion), not
   arbitrary drift. User's call: symmetrical 25px on all four sides. Both panels'
   rail insets now match; `MODELS_CONFIG.PANEL_WIDTH` (`1100 → 1115`) and
   `Config.DEFAULT_PANEL_WIDTH`/`MIN_OWNED_PETS_WIDTH` (`570 → 578`) absorb the
   resulting shift so neither panel's content area (`petsFrame` / the pet list)
   changed size as a side effect — confirmed algebraically for Owned Pets, by
   construction for Models Browser. **Confirmed working in-game.**
