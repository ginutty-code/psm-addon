# PSM Backlog (archive)

Cross-repo in scope (`psm-addon` and `psm-data` both), and tracked here in `psm-addon/docs/`
alongside `architecture.html` and `ARCHITECTURE_PLAN.md`, same reasoning as those two.

**Open ideas and fixes are now tracked as issues in the `psm-backlog` GitHub repo, not
here.** This file is kept only as a historical record of findings that surfaced while
working the numbered tasks in `ARCHITECTURE_PLAN.md` and have since been resolved.
Each entry was originally logged inline in `ARCHITECTURE_PLAN.md`'s running log at the
point it was found; that document's chronological narrative around each entry (which
task was in progress, what testing surfaced it) was left in place there.

---

## The resize blind spot (partially fixed; residual tracked as [psm-backlog#1](https://github.com/ginutty-code/psm-backlog/issues/1))

**Symptom.** Resize the Owned Pets panel while scrolled somewhere in the middle of the
list and it goes *completely* empty — no rows, no models — and stays that way until
scrolled by hand. Pre-existing, long before A6. After the three fixes below it is much
rarer but **not gone**; deeper investigation deferred.

### Three mechanisms found and fixed

1. **Unclamped row offset.** Column count derives from panel width, so widening halves
   `rowTotal` while `scrollOffset` still describes the old width. `startIndex` came out
   greater than `endIndex`, the render loop never ran, every row stayed hidden.
   → `PSM.UI:GetScrollRowOffset` derives the offset from `GetVerticalScroll()` and clamps
   it. List and grid now agree with GroupedView, which had always read the live scroll.
2. **A throttle with no trailing pass.** The resize handler skipped its relayout for
   movements under 10px — a leading filter with nothing behind it, so the size a drag
   *ends* on could be up to 10px from the last size laid out. Invisible until a column
   boundary fell inside those pixels, and then nothing came to correct it.
   → A debounced trailing relayout, always against the current size.
3. **`if maxScroll > 0 then scrollBar:SetValue(...) end`** — backwards. `maxScroll == 0`
   means the content now fits the frame, and that is exactly when a frame still scrolled
   to its old position displays the empty region past the last row. Every row renders
   correctly and none is in view.
   → `PSM.UI:ClampScrollIntoRange`, called from the resize handler, `_ApplyCachedRender`,
   and all three views — every path that changes content height.

### What the evidence ruled out, and how

Each user observation eliminated a class of cause, and none of them could have been
derived by reading:

- *"Completely empty, not partial"* → not a pool-exhaustion or per-row failure.
- *"Never at the top"* → offset 0 is the one scroll position always in range, so the
  fault is in scroll/offset agreement rather than in filtering or data.
- *"All three views"* → **decisive**. GroupedView shares none of the others' offset
  bookkeeping (no `scrollOffset`, purely geometric visibility). A per-view indexing bug
  cannot explain it; the fault had to be in the one scroll frame they share.

### Process note

Three attempts, and the first two were presented with more confidence than the evidence
carried. Each mechanism was real and each explained *a* blank panel — but explaining the
symptom is not the same as explaining the reported case, and I did not check the
difference until the user's observations forced it. **Ask what the report rules out
before building a theory that fits it.**

---

## Panels can exceed the screen at high UI scale

Found by the user while testing the `uiScale` deletion (2026-08-17). At maximum Blizzard UI
scale on a laptop, the Models Browser does not fit on one screen, and its buttons go out of
reach.

**Why it happens.** Nothing in the addon calls `:SetScale()`, so every frame inherits
UIParent's effective scale. Panel sizes are fixed point values (`DEFAULT_PANEL_WIDTH = 550`,
`DEFAULT_PANEL_HEIGHT = 640`, and the browser's own larger fixed size). Raising the UI scale
shrinks UIParent's extent *in points*, so a fixed-point panel occupies more of the screen and
eventually exceeds it.

**Why it cannot be dragged back into reach.** `PanelManager.lua:44` calls
`panel:SetClampedToScreen(true)` for every panel it builds. Clamping is correct for a panel
that fits -- it is what stops one being lost off-screen -- but for a panel *larger* than the
screen it does the opposite of its purpose: it pins the oversized frame so the far edge can
never be brought inward. Six frames set this, all with the same unconditional `true`.

**Three shapes for a fix, in increasing cost.**

1. `SetClampRectInsets` -- permit controlled overhang while keeping the title bar on screen.
   The idiomatic answer to "let it hang off but stay grabbable", and it does not need the
   panel to know its own size.
2. Clamp *conditionally*: keep `SetClampedToScreen(true)` while the panel fits within
   UIParent and drop it when it does not. Cheap, but the panel has to re-evaluate on scale
   and resolution changes, not only at construction.
3. Size the panel to fit -- `math.min(desired, UIParent:GetWidth() - margin)`. The real fix,
   and it needs the content to reflow, so it is the **Models Browser resizability** item
   wearing a different hat. The user has that one deferred to last.

**A dependency worth recording, because it points backwards at a deletion.** A fourth option
-- solve it with `panel:SetScale()` -- would break something A6 relied on.
`PanelManager`'s maximize/restore round trip saves `panel:GetLeft()` / `GetTop()` and restores
via `SetPoint` offsets against UIParent, which is exact **only while panel and UIParent share
an effective scale**. That is true today precisely because nothing calls `SetScale`, and it is
the reason the write-only `uiScale` local could be deleted rather than wired up. Introduce a
per-panel scale and that local becomes necessary again. Whoever takes option 4 has to fix the
geometry round trip in the same change.

**Shipped (2026-08-21): option 1, `SetClampRectInsets`, as a stopgap** — landed at
`panel:SetClampRectInsets(400, -400, -400, 400)` in `PanelManager.lua:CreateBasePanel`
(every edge can overhang symmetrically, so the player trades which part is visible by
dragging), plus a warning message (`WarnIfOversized`) that fires on every `OnShow` while
oversized. Scoped to `PanelManager.lua`'s seven chrome panels only. Does **not** make an
oversized panel fully visible at once — that's still option 3 below, considered and set
aside for this stopgap: shrink-only resizing would still need the rail's fixed-size boxes
(Tools/Show Only/Unified Filters, literal `size = {210, N}`) to reflow, which is the real,
deferred work.

**Still open: option 3, auto-fit height, following native Blizzard panel behavior.**
Tracked as [psm-backlog#2](https://github.com/ginutty-code/psm-backlog/issues/2).

---

## Taming-requirement popups show the family default, not the per-NPC exception

**Fixed and pushed (2026-08-22).** `psm-data` `d445459`, `psm-addon` `5d6bcb5`,
`feat/load-on-demand` both repos.

Raised by the user while confirming A14's structural tier, while looking at the
Clefthoof-style grandfathered-exotic case from a different angle. The addon side
turned out to be innocent: `TamingChecker.lua`'s `"Exotic"` rule already evaluates
against `ModelsData`'s per-NPC `taming` field, and that field already varies within a
family — confirmed empirically (Clefthoof, Worm, Devilsaur, Cloud Serpent and others
all had NPCs disagreeing with their own family's default before this fix). The
worry that it "only ever inherits the family's classifier" was the wrong theory.

**The real bug was in psm-data's Wowhead/Petopia merge (`11_combine_data.py`).**
`Manual/taming_updates.csv` — the hand-curated per-NPC override file — is only
applied at step 03, and only to NPCs Petopia's own scrape produced a row for. An
override for an NPC Petopia never carried (i.e. most of a family, scraped from a
per-NPC page Petopia never wrote) was silently dropped: three Clefthoof NPCs (Trained
Clefthoof, Thunderhoof, Grom'kar Warbeast) had exactly this — someone had already
tried to record "Exotic" for them, and it never took effect. 31 NPCs total were
affected across several families. Fixed by adding `load_taming_additions()` to
`11_combine_data.py`, mirroring the existing `load_note_additions()` fallback built
for the identical gap in the notes pipeline.

**A second, related gap surfaced immediately after**, from the user's own next
request: `Manual/taming_updates.csv` had no way to *clear* a family's default for a
genuine exception (Bulvinkel, npc 111463 — a Spirit Beast that, unlike the rest of
its family, doesn't require Beast Mastery). A blank `taming_requirements` cell was
treated as "no row" by `load_taming_updates()` in `03_clean_petopia_data.py`, not as
an explicit override to nothing. Fixed so a present-but-blank row wins outright.

Regenerated and synced `ModelsData.lua`; one incidental NPC (Fledgling Corpseburster)
from an already-committed, not-yet-synced psm-data refresh came along in the same
sync, with the user's explicit OK. Golden record count in
`Tests/spec/models_data_spec.lua` bumped 7852 → 7853 accordingly. `luacheck`/`ruff`
clean, addon test suite 193/193.

---

## Not every panel is protected against combat entry

Found while confirming A9's error-boundary work in-game (2026-08-20): no deliberate
error could be forced to verify `/psm debug`'s stack-trace surfacing, but testing
surfaced this instead. It's a `Broker:CloseAllPanels()` coverage gap — missing
`abilityBrowser` / `specialTames` — unrelated to the error-boundary mechanism A9
itself built.

**Fixed and confirmed in-game (2026-08-21), three rounds — exit side, entry side,
then two bugs the user's in-game pass across all 9 windows caught in the entry-side
fix. Committed and pushed (`e88f9c4`, `feat/load-on-demand`).**

Round 1 — exit side only: checked every panel registered through
`PanelManager:CreateBasePanel` (`panel`, `modelsPanel`, `abilityBrowser`,
`teamsPanel`, `specialTames`) plus the two model popups built via
`PopUpManager:CreateModelPopup` (`petRoulettePopup`, `modelMagnificationPopup`) —
those two were already covered, so `abilityBrowser` and `specialTames` were the only
gap in `Broker:CloseAllPanels()`.

Round 2 — the entry side. The user's follow-up test found the other half broken:
several panels could still be *opened* mid-combat, immediately producing the
protected-call errors this was meant to prevent. Auditing every one of the 9
windows' real "open" verb found guards in three different states: three panels
(Ability Browser, Special Tames, Models Browser) each hand-rolled their own
`UnitAffectingCombat` check, with three slightly different messages; the other six
(Owned Pets, Teams, Export, Options, Pet Roulette, Model Magnifier) had no check at
all — whichever entry point you happened to use (LDB icon vs. minimap icon vs.
`/psm` vs. a Menu button) decided whether you were protected, since some of those
entry points duplicated panel-open logic independently rather than sharing it.

Fixed by centralizing: `ns.PanelManager:CombatBlocked(label)` (`PanelManager.lua`)
is the one check now, and `PanelManager:TogglePanel` — already the shared open/show/
hide function for Models Browser, Ability Browser and Special Tames — calls it
before showing (never before hiding; closing a panel is always safe). The other six
windows don't share a toggle function, so each got the same guard added at its own
single real "open" verb instead of at every click handler that can reach it:
`UI:UpdatePanel` (Owned Pets), `TeamsPanel:Toggle`/`:Show`, `Export:ShowExportDialog`,
`Broker:ToggleOptionsPanel`, `PetRoulette:ShowPetRoulettePopup`,
`PopUpManager:ShowMagnificationPopup`. `Minimap:TogglePanel` had its own independent
Owned-Pets-opening code path (separate from `UI:UpdatePanel`) and now calls the same
shared guard rather than a fourth hand-rolled copy.

`Loader:EnsureBrowser`'s own `InCombatLockdown` check is intentionally untouched —
different concern (avoiding a multi-MB Lua parse mid-fight when the Models Browser
module isn't loaded yet), not panel-open safety.

Round 3 — two bugs the user's in-game pass across all 9 windows caught in round 2.
(1) Pet Roulette printed its green "you rolled X" confirmation even when
`ShowPetRoulettePopup` had just refused to open the popup for being in combat —
`SelectPetRoulette`/`SelectPetRouletteFromCommand` called `PrintRoulette(pet)`
unconditionally right after `ShowPetRoulettePopup(pet)`, not knowing whether it had
actually shown anything. Fixed by having `ShowPetRoulettePopup` return whether it
opened, and only printing the confirmation when it did — kept local to Pet
Roulette rather than pushed down into `PopUpManager`, since Model Magnifier has no
analogous post-open message for the return value to gate. (2) The nine messages
lacked a shared identity — most read "`<Window>`: Cannot open during combat." but
Options read just "Options: Cannot open during combat.", with no addon branding at
all, the odd one out next to messages that all began "Pet Stable Management" or
"Pet Model Browser" etc. User was offered three shapes (fully generic; a short
"PSM -" tag per window; the addon's own existing "Pet Stable Management: `<detail>`"
convention, already used by "Minimap button shown." and others) and chose the third.
The one locale template is now `"Pet Stable Management: %s cannot open during
combat."`; the Owned Pets window's label changed from "Pet Stable Management" (which
would have doubled up against the new prefix) to "Owned Pets", a new key.

---

## `petTeams` still persists a redundant `specID` per slot

Found by the user reading the real SavedVariables file (2026-08-21). Tracked as
[psm-backlog#3](https://github.com/ginutty-code/psm-backlog/issues/3).

---

## Printed messages now go through one factory

**Table item 13. Fixed and confirmed in-game 2026-08-22, pushed (`954a119`).**

The survey found three prefixes in use — `"PetStableManagement:"`, `"Pet Stable
Management:"`, and *no prefix at all* on the largest group — plus two warning
oranges (`FF8800` and `FFAA00`) used interchangeably, and two confirmations printed
with no colour. Every `print()` built its own, so nothing made the divergence visible.

`ns.Utils:Msg(kind, text)` is the one path to the chat frame now. `kind` is an
ERROR/WARNING/SUCCESS key into `Config.COLORS`, so the three message colours and
every other semantic use of the same colour come from one definition. Locale values
are consequently plain text — colour and prefix used to be baked into each entry, one
escape-code spelling per author.

**Left alone deliberately**, so a future pass doesn't "finish" the job wrongly: the
CSV-export instruction block (its own numbered convention), tooltip/row text that
never reaches chat, `/psm debug`'s per-entry lines (list items under an
already-prefixed header), and two internal assertions no player can trigger.

---

## NPC table geometry, and SectionHeader as a real shared widget

**Table item 1. Fixed and confirmed in-game 2026-08-22, pushed (`05db2f8`).**

**The band was drawn over petsFrame's silver border because band *and* rows were both
flush with the frame** — there was nowhere for the border to show. The fix is one
shared `NPCRow.TABLE_INSET` (5, matching what Tools/Show Only already used inside an
identical TOOLTIP-backdrop frame) applied to the header frame *and*, in
`ModelsPanel`, to every row.

**Both have to move together, and that is the part worth remembering.** Column x
positions come from a single `RecomputeColumnLayout`, but the header's buttons anchor
to the header frame while cells anchor to their row frame. Insetting one alone slides
the header's columns off the cells beneath them — which is exactly what one failed
attempt did. Insetting only the band's *texture* (another failed attempt) just ate
into the band, since the band is the thing being kept whole.

**Process note.** Three wrong attempts before this, each a pixel guess presented as a
fix, and the user's "I think we need to position the NPC row area lower" is what
redirected it to the structural answer. Two of my own bugs were caught by writing the
arithmetic out and running it rather than reasoning in prose — a dropped
`ReflowVisibleRows`, and a clamp that snapped columns smaller. **When the change is
geometry you cannot see, compute it.**

### SectionHeader

Three call sites had drifted to two heights (20/22), two label fonts and two text
colours — the `CheckBox` 16-vs-20 lesson again, relocated from `CreateFrame` blocks
into options tables. Height now comes from `Theme.CONTROL.SECTION_HEADER`; the label
is `palette.ACTIVE_TEXT` (white), which is what the factory's own comment always
claimed ("visually an active `Widgets.Tab`") while it actually defaulted to gold, so a
header and a selected tab on the same panel never matched. `fontSize`/`fontObject`/
`color` are **removed from its `OPTIONS` vocabulary**, so re-introducing the drift
surfaces in `Widgets.unknownOptions` instead of passing silently.

### Display IDs column

Two separate causes, both fixed: the drag had no upper bound, and the shipped defaults
were over budget *before anyone dragged*. `NPCRow:MaxWidthForColumn` bounds a drag by
`max(cap, current)` — an over-budget layout can still be dragged smaller (the way out)
but never larger; a bare `min()` snapped the grabbed column down on the first pixel.
The panel is a fixed 1100 wide, so defaults are now sized against the known 815px
table: Display IDs gets 106px with every column shown, 204px at the default set,
against a floor of 90 (set by the header — `"Display IDs"` plus the `" ^"`/`" v"` sort
marker runs ~81px, below which the marker clips first).

**Still open:** stored column widths mask the new defaults for existing characters —
no reset path. Tracked as [psm-backlog#4](https://github.com/ginutty-code/psm-backlog/issues/4).

**Proportional column scaling was considered and declined** (2026-08-22), then
  **implemented** (2026-09-02) once the panel became width-resizable. The 2026-08-22
  objection stands — displayed width stops matching stored width, so a naive drag
  jumps the column back — and is handled: `RecomputeColumnLayout` computes one shared
  `panel._npcColumnScale` (`= 1` at or above the ~815px design width, `< 1` below it),
  scales the shrinkable non-flex columns by it (columns already at `MIN_COLUMN_WIDTH`
  are held out and subtracted from the budget first, so the flex column doesn't eat
  their shortfall and overflow), and the `ResizeDriver` drag handler divides the
  cursor delta by that factor so the grabbed boundary tracks the cursor in *displayed*
  space while `npcColumnWidths` stays in stored space. `MaxWidthForColumn` stays a
  stored-space cap — approximate while scaled, but self-limiting via each column's
  `MIN_COLUMN_WIDTH`. A sorted column scaled toward `MIN_COLUMN_WIDTH` (30) clips its
  sort marker — the same trade `MIN_FLEX_WIDTH` already documents. The fixed-defaults
  work above is unchanged: it is still what a column layout starts from, and `factor`
  only ever shrinks that to fit a narrower panel.

---

## Newly logged backlog items (2026-08-21)

Short, unelaborated notes handed off by the user in one batch. The still-open ones were
migrated to [psm-backlog issues](https://github.com/ginutty-code/psm-backlog/issues)
2026-08-22; only the ones already fixed at the time stay recorded here.

| # | Item |
|---|------|
| 1 | **NPC view golden title border.** Fixed and confirmed in-game 2026-08-22. Header band *and* rows are now inset by a shared `NPCRow.TABLE_INSET` (5 — the same inset Tools/Show Only already used inside an identical TOOLTIP-backdrop frame); both must share it, since the header's column buttons and the row cells anchor to different frames but read one `RecomputeColumnLayout`. Also centralized `Widgets.SectionHeader` (one height via `Theme.CONTROL.SECTION_HEADER`, white `ACTIVE_TEXT` label, style keys removed from its `OPTIONS`) and fixed the Display IDs flex column overflowing the panel. Committed and pushed (`05db2f8`, `feat/load-on-demand`). See "NPC table geometry" below. |
| 2 | **Ability Browser lacking combat protection.** Fixed and confirmed in-game 2026-08-21, three rounds — see "Not every panel is protected against combat entry" above. Combat-entry guard, centralized as `PanelManager:CombatBlocked()`, now covers open *and* close for all 9 windows. Pushed. |
| 4 | **`/psm help` slash command.** Fixed and confirmed in-game 2026-08-22. Added `help` to `PETSTABLE_COMMANDS` in `SlashCommands.lua`, listing every `/psm` subcommand and `/petswap` with a one-line description; documented in `README.md`'s Commands section. Descriptions reuse the exact "Toggle X" / "Show minimap button" strings the PSM Menu and Options panel already declare for the same actions, rather than the help list inventing its own wording, after the user flagged inconsistent capitalization in a first draft. Committed and pushed (`de5db32`, `feat/load-on-demand`). |
| 10 | **Pet Roulette broken in NPC view.** Fixed and confirmed in-game 2026-08-21. `PetRoulette:SelectPetRoulette` only ever read `panel.allModels`, which the display-ID view populates; the NPC view populates `panel.allNPCs` instead, so switching views left the roulette pool empty. Fixed by building the pool from the filtered NPC list (via `PSM.PetModels:GetFamilyModels`) when `panel.modelsViewMode == "npc"`. Committed and pushed (`1af6800`, `feat/load-on-demand`). |
| 11 | **Opacity setting not applied everywhere.** Fixed and confirmed in-game 2026-08-21, two rounds. First pass (edit-box background not stored on `frame.editBg`) missed the real cause, per the user's follow-up that the *whole* export dialog wasn't tracking opacity. Root cause: `Export.lua` was the only place in the codebase applying ElvUI's `skin = "frame"` to the same frame that also carried the addon's own `backdrop`/`color` — every other panel (`PanelManager.lua`'s `CreateBasePanel`, `Menu.lua`) keeps those on two frames, an outer ElvUI-skinned frame plus a separate unskinned `.border` child carrying the translucent, opacity-tracking color, specifically because ElvUI's `HandleFrame` re-templates whatever it's given and fights a backdrop color set on the same frame. Fixed by splitting Export's dialog the same way (`frame.border` child) and pointing `PanelManager:UpdatePanelBackgrounds()` at `ef.border` instead of `ef` directly. The Options panel itself has no addon-drawn backdrop (it's embedded in Blizzard's Settings frame) — nothing to wire up there. Pushed. |
| 13 | **Standardize printed message styling.** Fixed and confirmed in-game 2026-08-22. Every chat message now goes through one factory, `ns.Utils:Msg(kind, text)`, which applies the single prefix and one of `Config.COLORS`' ERROR/WARNING/SUCCESS. Committed and pushed (`954a119`, `feat/load-on-demand`). See "Printed messages" below. |
