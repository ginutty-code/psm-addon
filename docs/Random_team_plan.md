# Random Team generation for the Owned Pets panel (psm-addon issue #3)

## Context

[Issue #3](https://github.com/ginutty-code/psm-addon/issues/3) (Dashifen — Aerie Peak) asks for
a **"generate random team" action on the Owned Pets panel**, driven by the current filter:
"if I filter by pet family, I'd love to just select five at random to fill my current team."
It is an aesthetics/variety feature — the reporter currently generates five random letters on a
website and picks pets by name, which drags them out of the game.

You added a requirement on top: **the team's specs must be controllable** — either by drawing
from a spec-filtered list, or by assigning a spec to a *slot* and retuning whatever pet lands
there to fit. The chosen shape (confirmed) is:

- The user picks a spec per slot (Any / Ferocity / Tenacity / Cunning) in the roll dialog.
- The draw **prefers pets that already have that spec**, and only **coerces** (calls
  `SetPetSpecialization`) when it runs out of matching pets — so no pet's spec is rewritten
  gratuitously, and a slot requirement is always satisfiable.
- A roll is **previewed** before anything is committed: Re-roll, then *Apply now* (at a Stable
  Master) and/or *Save as team…*.
- The draw pool is **this character's pets only**, because a team can only be applied with pets
  this hunter owns.

Outcome: one button on the Owned Pets panel turns the existing filter state into a playable
team, with per-slot spec control, reusing the Teams engine rather than growing a second one.

**Repo/branch:** all of this is in `psm-addon`, on `main` (issue #17's chrome rework, which
§4 depends on, has landed there). Nothing in `psm-data` changes — no generated table's shape
moves, so `SCHEMA_VERSION` stays put.

---

## What already exists (reuse, don't rebuild)

| Need | Already there |
| --- | --- |
| The filtered pet list | `renderData.filteredPets`, computed in `ns.UI:_CalculateRenderData` and stashed as `ns.state.currentRenderData` (`Shared/UI.lua:293`, `:460`). This is literally "the current filter" — spec, family, tamer, ability, exotic, duplicates and search all applied. |
| Spec-filtered draw ("from a filtered list") | **Free.** The panel's Spec dropdown already filters on `pet.specName` (`Shared/UI.lua:329`); anything drawn from `filteredPets` inherits it. |
| A team's on-disk shape | `ns.Teams:SlotRecord(pet)` — the *one* definition of a slot (`OwnedPets/TeamsData.lua:94`). |
| Moving pets into slots 1–6 | `ns.Teams:ApplyTeam` + `ExecuteClearOperations` / `ExecuteSlotOperations` / `ValidateAndRetryApply` (`TeamsData.lua:270-533`). Handles displacement to stable slots, swap-through-temp, and up to 3 retries. |
| **Changing a pet's spec** | `ns.Teams:RestorePetSpecializations` (`TeamsData.lua:410`) — already maps spec name → index (live via `C_StableInfo.GetAvailablePetSpecInfos()`, falling back to `{Ferocity=1, Tenacity=2, Cunning=3}`), calls `C_SpecializationInfo.SetPetSpecialization` under `pcall`, and reports the ones it couldn't retune. |
| Saving a team from an explicit slot table | `ns.Teams:SaveTeam(name, slots)` (`TeamsData.lua:178`) — already takes `slots`. |
| Dialog chrome, buttons, slot grid | `Shared/Dialogs.lua` — `CreateBaseDialog`, `CreateDialogText`, `CreateDialogButton`, and `ShowSelectSlotDialog`'s 6-cell grid (`:488`) as the layout precedent. |
| "Roll again" UX precedent | `PetRoulette`'s `onTryAgain` (`ModelsBrowser/PetRoulette.lua:217`). *Note: PetRoulette is about **untamed models** and lives in the LoadOnDemand browser — this feature is about **owned pets** and must live in core.* |
| Companion slot | `ns.Utils:HasAnimalCompanionTalent()` (`Shared/Utils.lua:146`) — the existing gate for slot 6. |
| Panel buttons | The `ToolButton` local in `OwnedPets/Panel.lua:128` — Export and Pet Teams are already built with it, inside the left rail's Tools box. |

**The key insight that keeps this small:** `RestorePetSpecializations` coerces a pet's spec by
comparing the live pet against `slot.specName` and calling `SetPetSpecialization` on any
mismatch. So a coerced slot needs **no new spec-setting code at all** — the roll just writes
the *required* spec into the slot record it builds, and the existing apply path does the rest.

---

## Design

### 1. `PetStableManagement/OwnedPets/RandomTeam.lua` (new, core)

Holds the draw. Frame-free and dependency-light so the headless suite can exercise it.

```lua
-- ns.RandomTeam.Roll(pets, opts) -> slots, report
--   pets   : array of processed PSM pets (already filtered, already this character's)
--   opts   : { slotCount = 5|6,
--              template  = { [slot] = "Ferocity"|"Tenacity"|"Cunning"|nil },  -- nil = Any
--              locked    = { [slot] = slotRecord },   -- kept across a re-roll
--              random    = math.random }              -- injectable for the spec
--   slots  : { [1..slotCount] = ns.Teams:SlotRecord(pet) }
--   report : { filled = n, short = n, coerced = { {name=, from=, to=} } }
```

Draw order — **most constrained first**, so a templated slot never loses its only candidate to
an "Any" slot:

1. Build the pool: dedupe by `petNumber`, drop anything already `locked`.
2. **Pass 1 (match)** — for each templated slot, pick at random from pool entries whose
   `specName` equals the requirement; remove the pick from the pool.
3. **Pass 2 (coerce)** — for each templated slot still empty, pick at random from the whole
   remaining pool, build its `SlotRecord`, then **overwrite `specName` with the requirement**
   and record `{name, from, to}` in `report.coerced`.
4. **Pass 3 (any)** — fill the untemplated slots from what's left.
5. Slots that ran out of pool stay `nil`; `report.short` counts them.

Also here: the entry point the button calls.

```lua
function ns.RandomTeam:Show()          -- guard, gather pool, roll, open the dialog
```

Pool gathering, in `Show`:

- `ns.state.currentRenderData.filteredPets` when the panel has rendered; otherwise
  `ns.UI:UpdatePanel()` first (same `EnsurePetData` path every other entry point uses).
- Restrict to `pet.tamer == ns.GetCharacterKey()`.
- Empty pool → `ns.Utils:Msg("WARNING", ns.L("No pets match the current filters."))` and stop,
  mirroring `PetRoulette:SelectPetRoulette`'s guard. Do not open an empty dialog.
- `slotCount = ns.Utils:HasAnimalCompanionTalent() and 6 or 5`.

The spec template persists across sessions in
`PetStableManagementDB.settings.randomTeam = { template = {...} }`, defaulted alongside the
other settings in `Core.lua:50`.

### 2. `ns.Teams:ApplySlots(...)` — extract the engine (`OwnedPets/TeamsData.lua`)

A roll must be appliable **without** first being saved, or every re-roll litters the team list.
`ApplyTeam(teamId)` already does exactly the right work; it just insists on a saved team.

- Move the body of `ApplyTeam` into `ns.Teams:ApplySlots(slots, label, opts, retryCount)`,
  where `opts.teamId` is optional and used only for the `CharData().activeTeamId` bookkeeping
  in `OnTeamApplied`. `label` is what the chat messages name (a team's name, or
  `L("Team Roulette")`).
- `ApplyTeam(teamId, retryCount)` becomes a thin resolve-then-delegate wrapper. Its two callers
  (`TeamsPanel.lua:439`, and its own retry) keep working unchanged.
- Carry `slots`/`label` through `ValidateAndRetryApply` and `OnTeamApplied` instead of
  re-resolving by `teamId` on each retry.
- Change `RestorePetSpecializations(team)` to take `slots` directly (its only read is
  `team.slots`), and update its one caller. Passing `{ slots = slots }` would work and would be
  a lie about what the function needs.
- Hoist the spec-name → index map out of `RestorePetSpecializations` into
  `ns.Teams:SpecIndexByName()` so the template UI and the coercion path agree on the spec list
  by construction, rather than by two literals staying in sync.

This is the one refactor in the plan. It's mechanical, but it touches a retry-recursive
function — do it as its own commit, with the existing Apply flow re-tested in-game before the
new feature is layered on.

### 3. `ns.Dialogs:ShowRandomTeamDialog(state)` (`Shared/Dialogs.lua`)

Dialogs live in `Dialogs.lua`; the roll logic stays in `RandomTeam.lua`. Layout, top to bottom:

- **Title** `L("Team Roulette")`, plus a line naming the pool size
  (`L("Drawing from %d filtered pets", n)`).
- **Slot row** — `slotCount` cells, laid out like `ShowSelectSlotDialog`'s grid
  (`Dialogs.lua:533-585`), slot 6 visually separated the way `TeamsPanel`'s divider separates
  the companion. Each cell shows the rolled pet's portrait
  (`SetPortraitTextureFromCreatureDisplayID`, as `TeamsPanel:UpdateTeamRow` does), name, family
  and spec. A coerced slot shows its spec as `Cunning → Ferocity` in
  `Theme.COLOR.ORANGE`, so nothing about a spec change is a surprise. Hovering a cell reuses
  `ns.PetTooltip.Spec(petData, {slotLabel = ...})` — the same tooltip every other owned-pet
  view shows.
- **Spec template** — under each cell, a small `Widgets.Button` whose label cycles
  `Any → Ferocity → Tenacity → Cunning → Any`, coloured per spec. Cycling shape follows
  `Filters.lua`'s `NextTriState` precedent: the kit renders, the caller owns the cycle order.
  (Six dropdowns would be wider than the dialog; a cycling button is one click.) Changing a
  spec re-rolls only the slots that aren't locked.
- **Lock toggle** per cell (a small padlock `IconButton`) — keeps that pet across a re-roll.
  Cheap once `locked` is a parameter, and it's what makes re-rolling usable.
- **Buttons**: `Re-roll` · `Apply now` · `Save as team…` · `Cancel`.
  - *Apply now* → `ns.Teams:ApplySlots(slots, ns.L("Team Roulette"))`. Disabled with a live
    tooltip when `not ns.state.isStableOpen`, exactly as `TeamsPanel`'s apply button is
    (`TeamsPanel.lua:449-474`) — but use the **enabled-button-with-live-tooltip** form the
    codebase moved to, not another overlay.
  - *Save as team…* → `ns.Dialogs:ShowNameInputDialog{...}` → `ns.Teams:SaveTeam(name, slots)`
    → `ns.TeamsPanel:RefreshTeamsList()`. Works away from a Stable Master.
- **Warning line** when `report.short > 0`:
  `L("Only %d of %d slots could be filled from the current filters.", ...)`.

### 4. The button (`OwnedPets/Panel.lua`)

**The action-row plan below is superseded** by [psm-backlog issue #17](https://github.com/ginutty-code/psm-backlog/issues/17)
(`docs/Owned_pets_toolbar_plan.md`), which has landed on `main`. Export and Pet Teams are no
longer on the action row at all — they are `Widgets.Button`s stacked in the left rail's
**Tools** box, and this feature's button goes there beside them.

- Build it with Panel.lua's `ToolButton` local (`Panel.lua:128`), **not** a `PanelButton`:
  `ToolButton(ns.L("Team Roulette"), panel.teamsButton, function() ns.RandomTeam:Show() end, <tooltip spec>)`.
  `ToolButton` anchors `TOPLEFT → anchorTo BOTTOMLEFT` and applies
  `Theme.CONTROL.BUTTON_W.M` itself, so the call carries no geometry. The tooltip is still a
  function spec naming the current filtered count.
- **The label is "Team Roulette", not "Random Team"** — it pairs with the existing
  `ModelsBrowser/PetRoulette.lua` naming. This is a locale-string change only: every internal
  identifier in this plan (`OwnedPets/RandomTeam.lua`, `ns.RandomTeam`, `ShowRandomTeamDialog`,
  `settings.randomTeam`, `Tests/spec/randomteam_spec.lua`) stays exactly as written.
- **Nothing to re-measure.** The Tools box already reserves height for three stacked buttons
  (`Theme.CONTROL.BUTTON * 3 + 10`, `Filters.lua:364`), and the rail's measured width already
  includes `BUTTON_W.M` — chosen *because* "Team Roulette" clips at the old S/80 tier
  (`RailWidth`, `Filters.lua:305`). The old worry about three left buttons colliding with the
  view buttons at `MIN_PANEL_WIDTH` is gone with the action row's squeeze; the row now carries
  only List/Grid/Grouped/Maximize/Close.

The issue says "List View", but the filters are panel-wide and view-independent, so the button
belongs on the panel chrome and works in all three view modes.

### 5. Locale, TOC, lint

- Every new string gets an `L.Register` entry in `Shared/Locale.lua`. `Tests/spec/locale_spec.lua`
  fails the build in **both** directions — an undeclared key *and* an unused declaration.
- The button, the dialog title and the label `ApplySlots` reports in chat are all
  `L("Team Roulette")` — `L("Random Team")` is never registered (see §4).
- Add `OwnedPets/RandomTeam.lua` to `PetStableManagement.toc`, after `OwnedPets/TeamsData.lua`.
- Nothing new goes in `Shared/PublicAPI.lua` — the browser has no use for this, and the bridge
  stays at fifteen names.
- No new globals: `C_StableInfo`, `C_SpecializationInfo` and `IsPlayerSpell` are already in
  `.luacheckrc`. The baseline stays **10 warnings / 0 errors**.

---

## Known limitation to state in the UI, not engineer around

`SetPetSpecialization` does not reliably retune a pet that isn't currently out — which is why
`RestorePetSpecializations` already ends with "Summon the pet(s) that need spec change and click
Apply again" (`TeamsData.lua:457`). Coerced slots inherit that. Reuse that exact reporting path;
do **not** add a second spec-setting mechanism. The dialog's `→` markers set the expectation up
front, and a partially-coerced apply reports itself the way applying a saved team already does.

---

## Files

| File | Change |
| --- | --- |
| `PetStableManagement/OwnedPets/RandomTeam.lua` | **new** — `Roll` (pure) + `Show` (guards, pool, dialog) |
| `PetStableManagement/OwnedPets/TeamsData.lua` | extract `ApplySlots`; `ApplyTeam` becomes a wrapper; `RestorePetSpecializations(slots)`; new `SpecIndexByName` |
| `PetStableManagement/Shared/Dialogs.lua` | `ShowRandomTeamDialog` |
| `PetStableManagement/OwnedPets/Panel.lua` | the "Team Roulette" button — a third `ToolButton` in the rail's Tools box |
| `PetStableManagement/Shared/Locale.lua` | new enUS keys |
| `PetStableManagement/Core.lua` | `settings.randomTeam` default |
| `PetStableManagement/PetStableManagement.toc` | list the new file |
| `Tests/spec/randomteam_spec.lua` | **new** |
| `Tests/suite.lua` | append the spec to `SPECS` |
| `README.md` | one present-tense bullet (a feature list, not a changelog) |

Optional, if you want it: `/psm randomteam` in `Shared/SlashCommands.lua`'s
`PETSTABLE_COMMANDS` — one line, alongside the existing `roulette` and `teams` entries.

---

## Verification

**Headless** (from the `psm-addon` repo root):

```bash
lua5.1 Tests/run.lua                      # or: uv run --with lupa python Tests/run.py
```

`Tests/spec/randomteam_spec.lua` covers the draw with an injected `random` (so it's
deterministic) and a hand-built pet list:

- a templated slot takes a pet that **already** has that spec when one is available;
- coercion happens **only** when no matching pet is left, and the emitted slot record carries the
  *required* spec plus a `report.coerced` entry;
- no `petNumber` appears twice in one roll;
- a pool smaller than `slotCount` fills what it can and sets `report.short`;
- `locked` slots survive a re-roll and their pets are excluded from the new draw;
- `slotCount` 5 vs 6.

**Lint** (luacheck is off PATH — full path is in the untracked `CLAUDE.local.md`):

```bash
luacheck PetStableManagement PetStableManagement_ModelsBrowser Tests
```

Expect **10 warnings / 0 errors**. Any change is something this work introduced.

**In-game** (yours, per CLAUDE.md — Claude doesn't reload-UI or read Lua errors):

1. *Away from a stable*, Owned Pets → Tools → Team Roulette. Roll should populate from cached data; *Apply
   now* disabled with its tooltip; *Save as team…* works and the team appears in Pet Teams.
2. *At a Stable Master*: filter to one family, roll, Apply — slots 1–5 become those pets, and
   displaced pets land in free stable slots.
3. Set slot 1 to Ferocity with a Ferocity pet available → it should be **picked**, with no spec
   change reported. Then filter down so no Ferocity pet is in the pool → the slot should show
   `X → Ferocity` and the apply should report the spec change (or the "summon it and Apply
   again" fallback).
4. With Animal Companion talented, confirm slot 6 appears and fills; untalented, confirm it
   doesn't.
5. Lock two slots, re-roll, confirm they hold and the other three change.
6. Resize the Owned Pets panel to `MIN_PANEL_WIDTH` and to its minimum height, and confirm
   the Tools box holds all three buttons with "Team Roulette" unclipped and the rail still
   clear of the panel's bottom edge.

**Regression** (the `ApplySlots` extraction): apply an existing saved team from the Pet Teams
panel and confirm moves, retries, the active-team highlight, and the spec-restore messages are
unchanged.

---

## Suggested commit sequence

1. `Extract Teams:ApplySlots from ApplyTeam` (refactor only, no behaviour change).
2. `Add RandomTeam:Roll and its spec` (pure logic + headless test).
3. `Add the Team Roulette dialog and Tools box button` (UI, locale, TOC, settings default).
4. `README bullet.`
