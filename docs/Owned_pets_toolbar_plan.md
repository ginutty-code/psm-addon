# Owned Pets top-chrome redesign (psm-backlog issue #17)

## Context

[Issue #17](https://github.com/ginutty-code/psm-backlog/issues/17) is the prerequisite
`docs/Random_team_plan.md` itself names: the Owned Pets panel's action row (Export ·
Pet Teams | List · Grid · Grouped · Maximize · Close) is already at its limit at the
panel's real minimum width (500px) — the right-hand cluster alone (Close + Maximize +
three view buttons) is 362px, leaving only 138px for everything on the left. Adding
Random Team as a fourth 80px button breaks the row even at the *default* width (570px),
not just the floor.

**The shape below was arrived at through a live, pixel-accurate mockup**
(`Owned Pets Toolbar`, published as a Claude artifact during planning — not checked into
the repo), not chosen up front. Four directions were on the table
(overflow menu, icon buttons, filter popover, left rail); the rail won, and three rounds
of refinement on top of it changed the shape enough that it's worth recording *why*,
not just *what*:

- A left rail exists already — `PetStableManagement_ModelsBrowser/ModelsBrowser/ModelsPanel.lua`'s
  `panel.toolsFrame` / `panel.showOnlyFrame` / `panel.unifiedFilterFrame` stack, at a
  flat 210px width, anchored at `Theme.CHROME.TITLE_Y`. That works there because the
  Models Browser panel is a fixed 1100px wide.
- Owned Pets is 500–570px. Copying the 210px rail verbatim draws the (centered)
  search box **overlapping the rail's border** at every width Owned Pets actually
  uses — confirmed by measuring, not eyeballing: -10px clearance at 570px, -45px at
  500px.
- The fix isn't a narrower search box, it's a narrower rail: sized to *its own
  content* (a 90px dropdown, the widest checkbox/button label) instead of an assumed
  210px. That alone reclears the search box with 45-80px to spare across the whole
  width range, **and** gives the pet list more room than the 210px version did (416px
  vs 315px at 570px wide).
- Once Export / Pet Teams / the Random Team button move into their own **Tools** box
  in that rail, the action-row squeeze that started this issue doesn't get patched —
  it disappears. The row goes back to being exactly what ships today
  (List/Grid/Grouped/Maximize/Close), with no icon buttons, no shortened labels, no
  margin to re-verify in-game.

**Repo/branch:** `psm-addon`, on `main`. Nothing in `psm-data` changes.

---

## What already exists (reuse, don't rebuild)

| Need | Already there |
| --- | --- |
| A left-rail panel to copy the *idea* from, not the numbers | `PetStableManagement_ModelsBrowser/ModelsBrowser/ModelsPanel.lua`'s `toolsFrame`/`showOnlyFrame` construction (`AddModelsBrowserElements`) and `ModelsFilters.lua`'s `CreateToolsBox`/`CreateFavoritesToggle`/`BuildUnifiedFilterSystem`. |
| The box look (dark fill, silver border, gold section band) | `Widgets.Frame` with `backdrop = "TOOLTIP"`, `borderColor = Theme.COLOR.SILVER`, plus `Widgets.SectionHeader` — both used verbatim by Models Browser's three boxes. `SectionHeader` already left-aligns its label (`justify = "LEFT"`, 5px inset) — no override needed. |
| Tri-state filter checkbox | `CreateFilterCheckbox` (`OwnedPets/Filters.lua`) — the exact factory Exotic/Duplicates already use. Favorites reuses it as-is. |
| The filter-pass branch shape | `ns.UI:_CalculateRenderData` (`Shared/UI.lua:284`) — a flat `if/elseif` per filter, each just `ns.state.xFilter == true/"inverted" and not pet.xField`. Favorites is one more branch of the same shape. |
| Favorite data on an owned pet | `pet.isFavorite`, already on every processed pet record (`Shared/Data.lua:748`, from Blizzard's native per-pet favorite). Nothing today reads it as an Owned Pets filter — this is genuinely new logic, not a relocation. |
| Tri-state filter persistence | `Shared/Data.lua`'s `FILTER_KEYS` / `NIL_FILTER_KEYS` / `LoadFilterSettings`, and the hand-built `char.settings` table in `ns.Data:SaveSettings` (`Data.lua:242-253`) — `exoticFilter`/`duplicatesOnlyFilter` both go through the identical four touchpoints Favorites needs. |
| Runtime state defaults | `ns.state` in `Core.lua` (~line 125) already declares `exoticFilter`/`duplicatesOnlyFilter`; add `favoritesOnlyFilter` beside them. **Verify, don't blindly mirror**, whether the *separate* `PetStableManagementDB.settings.exoticFilter`/`duplicatesOnlyFilter` (`Core.lua:40-41`, a different table from the per-character `char.settings` Data.lua actually saves to) are live or dead — they look like they predate the per-character path and may be vestigial. |
| "Favorites" as a label | Check `Shared/Locale.lua` for an existing `ns.L("Favorites")` before adding a new one — Models Browser's own Show Only toggle almost certainly already registered it. |

**The key insight that keeps the risk contained:** every dropdown/checkbox keeps its
existing `panel.xxxDrop` / `panel.xxxCheck` field name. `ReinitializeTamerDropdown`,
`UpdateFilterUI`, `SetStableTamerSelection`, and the Reset Filters handler all read
those fields off `panel` by name, never by parent — reparenting `panel.familyDrop`
from `panel` directly into `panel.filtersFrame` changes *where it's anchored*, not
*what anything else calls it*. Nothing downstream needs to change.

---

## Design

### 1. `ns.PanelManager:CreateRailBox(panel, opts)` (new, `Shared/PanelManager.lua`)

The one new shared factory. Models Browser hand-rolls this shape twice already
(`toolsFrame`, `showOnlyFrame`) with no extraction; Owned Pets needing the same shape
a third time is exactly the "counting record builders" signal this codebase already
treats as a cheap audit worth acting on. Models Browser is **not** touched by this
issue — adopting the factory there is a separate, optional cleanup, not a dependency.

```lua
-- ns.PanelManager:CreateRailBox(panel, opts) -> box, contentTop
--   opts = { point = {x, y}, width, contentHeight, headerText }
--   box         : the Widgets.Frame (backdrop TOOLTIP, borderColor SILVER)
--   contentTop  : y-offset (from panel TOP) where this box's own content starts,
--                 i.e. below the SectionHeader band
```

Internally: one `Widgets.Frame` sized `{width, SECTION_HEADER + contentHeight + pad}`,
one `Widgets.SectionHeader` at its top. Nothing pet-specific — same reason
`CreateSearchBox`/`CreateViewButton` live here instead of in `Filters.lua`.

### 2. Rail width: measured, not a literal (`OwnedPets/Filters.lua`, new local)

The mockup used a canvas-measured ~124px against a substitute web font; the real
number depends on `Theme.FONT` (Friz Quadrata) at `Theme.SIZE.SMALL`, so it must be
computed against the client's own font, not hardcoded from the mockup.

```lua
-- Local to Filters.lua. A scratch FontString (created once, reused), measuring the
-- actual candidate strings at their actual in-game fonts:
--   checkbox candidates: Favorites / Exotic / Duplicates, at Theme.SIZE.SMALL
--   button candidates:   Export / Pet Teams / Team Roulette, at GameFontNormalSmall
-- railWidth = max(Config.DROPDOWN_WIDTH, widest checkbox need, widest button need) + padding
```

Expect it to land in the same 115-130px neighborhood the mockup found — confirm the
literal number in-game rather than trusting the mockup's substitute-font measurement.

### 3. `ns.UI:BuildFilters(panel)` (`OwnedPets/Filters.lua`) — full rewrite of its body

Same public entry point (`Panel.lua` still calls it the same way), completely
different interior: three stacked `CreateRailBox` calls instead of the 2×2 dropdown
grid.

- **Tools** (`panel.toolsFrame`) — built and populated by `Panel.lua` (§4), not here:
  Filters.lua doesn't own Export/Pet Teams' click handlers today and shouldn't start.
- **Show Only** (`panel.showOnlyFrame`) — three `CreateFilterCheckbox` calls, stacked:
  `panel.favoritesCheck` (new), `panel.exoticCheck`, `panel.duplicatesCheck`. Labels
  drop "Only": `L("Favorites")`, `L("Exotic")`, `L("Duplicates")`. Behavior is
  unchanged for the two that exist — `InitFamilyDropdown(panel)` still gets called
  from Exotic's `onChanged`, same as today.
- **Filters** (`panel.filtersFrame`) — four dropdowns only, no checkboxes, in the
  order **Hunters, Specs, Families, Abilities**: `panel.tamerDrop`, `panel.specDrop`,
  `panel.familyDrop`, `panel.abilityDrop`. Same `Dropdown(name, point)` local, same
  `InitXDropdown` calls, just re-anchored top-to-bottom in one column instead of a
  2×2 grid.

`FamilyAllLabel()`, `InitFamilyDropdown`, `InitMultiDropdown`, `InitAbilityDropdown` —
none of these change. They don't know or care where their dropdown is anchored.

### 4. `ns.UI:AddOwnedPetsElements` (`OwnedPets/Panel.lua`)

- Remove `panel.exportButton`/`panel.teamsButton`'s `PanelButton()` calls from the
  action row.
- Build `panel.toolsFrame` via `CreateRailBox` (§1), at `{"TOPLEFT", 10, Theme.CHROME.TITLE_Y}`
  — same starting height as Models Browser's own `toolsFrame`, which is safe here
  *because* the rail is narrow enough to clear the centered search box (§ Context).
- Inside it, three stacked `Widgets.Button`s at `Theme.CONTROL.BUTTON_W.M` (100, not
  the row's old S/80 — confirmed by measuring that "Team Roulette" clips at 80):
  `panel.exportButton` (`ns.Export:ShowExportDialog()`), `panel.teamsButton`
  (`ns.TeamsPanel:Show()`, keeps its existing `ns.Teams:ButtonTooltipSpec()`
  tooltip), and the future Random Team / Team Roulette button (built by that
  feature's own work — this issue just provisions the box and the anchor point it
  lands in; see the cross-plan note below).
- Action row (`y = -5`) keeps only `List`/`Grid`/`Grouped`/`Maximize`/`Close` —
  unchanged anchors, unchanged widths. This is what ships today; nothing here
  actually changes.
- Scroll frame (`panel.scrollFrame`) and its decorative `rowsFrame` border move from
  `{"TOPLEFT", 10, FILTER_TOP - 69}` to `{"TOPLEFT", <rail right edge> + gap, <new Y>}`,
  where `<rail right edge>` comes from the box built in §3 and `<new Y>` sits below
  the search/reset row (mockup used ~90-122; tune in-game — this is the "easiest part
  to true up after" per your own call). `Theme.CHROME.FILTER_TOP` itself is untouched:
  Ability Browser and Special Tames' pill bars (`CreatePillBar`) still read it for
  their own `TOP_BAR` layout, and Models Browser's rail never used it either.
- `content:SetWidth(scrollFrame:GetWidth())` and the resize handler
  (`CreateScrollPreservingResizeHandler`) need no change — they already derive width
  from `scrollFrame`'s actual width, not a literal.

### 5. Sort by: unchanged anchor, new position

`panel.sortDrop` keeps its real anchor (`{"TOPRIGHT", -17, <new Y>}`, relative to
`panel`, not to the rail or the list) — it isn't a filter, it doesn't belong in the
Filters box, and it keeps its existing rich tooltip untouched. `<new Y>` just moves
down from `row2Y` to roughly level with where the list now starts (same tuning note
as §4).

### 6. Favorites filter (new, small, cross-cutting)

- `ns.state.favoritesOnlyFilter` — new tri-state (nil/true/"inverted"), declared
  beside `exoticFilter`/`duplicatesOnlyFilter` in `Core.lua`'s `ns.state` block.
- `Shared/UI.lua:_CalculateRenderData` — one more `elseif` in the filter pass:
  `ns.state.favoritesOnlyFilter == true and not pet.isFavorite then skip = true`
  (and the `"inverted"` mirror), same shape as the Exotic/Duplicates branches right
  above it.
- `Shared/Data.lua` — add `"favoritesOnlyFilter"` to `FILTER_KEYS` and
  `NIL_FILTER_KEYS`, and `favoritesOnlyFilter = ns.state.favoritesOnlyFilter or false`
  to the `char.settings` block in `SaveSettings` (`Data.lua:244-245`'s exact pattern).
- `ns.UI:UpdateFilterUI` (`Filters.lua`) — one more `SetTriState` line for
  `panel.favoritesCheck`.
- `BuildSortButtons`'s Reset Filters handler — clear `favoritesOnlyFilter` and
  `panel.favoritesCheck:SetTriState(nil)` alongside the other two.

### 7. Exotic's now-invisible coupling — a one-line mitigation

Exotic still rebuilds `InitFamilyDropdown` on click; that's not visible any more from
the checkbox's position (Show Only, not directly above Families in Filters). Give
`panel.exoticCheck` a `tooltip` — `CreateFilterCheckbox`'s underlying
`Widgets.CheckBox` already accepts one (`OPTIONS.CheckBox.tooltip = true`), so this
is a passed option, not new plumbing. One line: something like *"Also narrows the
Families list below to exotic-only."*

### 8. Locale

- New: `L("Tools")`, `L("Show Only")`, `L("Filters")` (box headers), `L("Exotic")`,
  `L("Duplicates")`, `L("Favorites")` (check for an existing registration first —
  see the reuse table above).
- Removed (if genuinely unused elsewhere after the rename):  `L("Exotic Only")`,
  `L("Duplicates Only")`. `Tests/spec/locale_spec.lua` fails the build on an unused
  declaration, so this isn't optional cleanup — it's required for the suite to pass.
- `FamilyAllLabel()`'s "All Exotic Families" / "All Non-Exotic Families" /
  "All Families" strings are untouched — those are the dropdown's own labels, not
  the checkbox's, and nothing here changes them.

### 9. Cross-plan note: `docs/Random_team_plan.md`

That plan's §4 ("The button (`OwnedPets/Panel.lua`)") describes adding a fourth
action-row `PanelButton`. That's superseded by this issue: the button's home is now
`panel.toolsFrame` (§4 above), built as one more `Widgets.Button` alongside Export
and Pet Teams, at `Theme.CONTROL.BUTTON_W.M`. Also rename its user-facing label from
"Random Team" to **"Team Roulette"** (pairs with the existing `PetRoulette.lua`
naming) — a locale-string change only. Internal identifiers stay as that plan
already wrote them: `OwnedPets/RandomTeam.lua`, `ns.RandomTeam`, `ShowRandomTeamDialog`,
`settings.randomTeam`, `Tests/spec/randomteam_spec.lua`. Renaming code identifiers to
match is possible (nothing's built yet) but not recommended here — it would make this
chrome-only issue touch a second feature's naming for no functional reason.

---

## Files

| File | Change |
| --- | --- |
| `PetStableManagement/Shared/PanelManager.lua` | new `CreateRailBox` |
| `PetStableManagement/OwnedPets/Filters.lua` | `BuildFilters` rewritten (Show Only + Filters boxes, reordered dropdowns, renamed checkboxes, new Favorites checkbox); rail-width measurement; `UpdateFilterUI` and the Reset Filters handler gain Favorites |
| `PetStableManagement/OwnedPets/Panel.lua` | Tools box + its three buttons; action row loses Export/Pet Teams; scroll frame / rowsFrame re-anchored around the rail |
| `PetStableManagement/Shared/UI.lua` | `_CalculateRenderData` gains the Favorites branch |
| `PetStableManagement/Shared/Data.lua` | Favorites added to `FILTER_KEYS`/`NIL_FILTER_KEYS`/`SaveSettings` |
| `PetStableManagement/Core.lua` | `favoritesOnlyFilter` default in `ns.state`; verify the vestigial-looking top-level `settings.exoticFilter`/`duplicatesOnlyFilter` while in the area |
| `PetStableManagement/Shared/Locale.lua` | new/removed keys per §8 |
| `docs/Random_team_plan.md` | §4 updated: button lives in Tools, labeled "Team Roulette" |

No `.toc` change (no new files), no `Config.lua` change (`DEFAULT_PANEL_WIDTH`/
`MIN_PANEL_WIDTH` stay exactly as they are — the whole point of sizing the rail to
its own content was not needing to touch these), no `Shared/PublicAPI.lua` change.

---

## Verification

**Headless:**

```bash
lua.exe Tests/run.lua
```

`_CalculateRenderData`'s Favorites branch and `FILTER_KEYS`/`NIL_FILTER_KEYS` are
plain data/logic — worth a couple of cases in whichever spec already exercises
`_CalculateRenderData` if one does, otherwise this is in-game-verified territory like
`exoticFilter`/`duplicatesOnlyFilter` are today. If `CreateRailBox`'s width
computation is written as a standalone pure function, that's cheaply headless-testable
against a few candidate-string sets.

**Lint:**

```bash
"C:\Users\Gi\Dev\tools\luacheck.exe" PetStableManagement PetStableManagement_ModelsBrowser Tests
```

Expect **10 warnings / 0 errors** unchanged.

**In-game** (yours, per `CLAUDE.md`):

1. At the panel's default size: confirm Tools/Show Only/Filters render left-aligned
   headers, correct box order, no clipped labels ("Team Roulette", "Duplicates").
2. Resize down to `MIN_PANEL_WIDTH` (500): confirm the search box clears the rail
   (no visual overlap), the action row has no crowding, and the pet list is still
   usable width.
3. Shrink the panel's height toward its minimum: confirm the rail's three boxes
   don't run past the panel's bottom edge — this is the tightest measurement from
   planning (as little as ~17px spare in the mockup) and is the one number most
   worth an actual look rather than trusting the plan.
4. Click Exotic / Duplicates / Favorites through their tri-state cycle; confirm the
   pet list filters correctly and Reset Filters clears all three.
5. Hover Exotic; confirm the new tooltip explains the Family-list side effect.
6. Confirm Export and Pet Teams still work unchanged from their new home, and Pet
   Teams' existing tooltip still shows.
7. Toggle List/Grid/Grouped; confirm the action row behaves exactly as it does on
   `main` today (this issue shouldn't change that at all).

**Regression:** open the Models Browser and confirm its `toolsFrame`/`showOnlyFrame`
render unchanged — this issue doesn't touch `PetStableManagement_ModelsBrowser` at all,
so this is a should-be-a-no-op check, not a real risk.

---

## Suggested commit sequence

1. `Add PanelManager:CreateRailBox` (new shared factory, no behavior change anywhere
   yet).
2. `Rebuild Owned Pets filter chrome as a Tools/Show Only/Filters rail` (the bulk of
   the work: Filters.lua rewrite, Panel.lua's box + re-anchors, locale keys).
3. `Add the Favorites filter` (state, render-pipeline branch, persistence, checkbox) —
   its own commit since it's genuinely new logic, not layout.
4. `Update Random_team_plan.md for the Tools box and Team Roulette naming.`
