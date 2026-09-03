# Replace "Pets Per Column" with a "Browser Model Size" slider

## Context

The Options panel has a dropdown **"Pets Per Column in Browser:"** (`petsPerColumn`,
integer 2–10, default 5). It was designed when the Models Browser was a fixed size, so
one number sensibly meant both "how big each 3D pet card is" and "how many rows fit".

Since the Models Browser became width + height resizable (2026-09-02, `4f7baa6` /
`6f10375`), the two meanings split:

- **Rows per page** is now derived from `petsFrame:GetHeight()` in `GetPageLayout`
  ([ModelsPanel.lua:103-113](PetStableManagement_ModelsBrowser/ModelsBrowser/ModelsPanel.lua:103)).
  It only *coincidentally* equals the setting's value at the default 820px height.
- **Model card size** is the one thing the setting still really controls, via
  `scale = 5 / petsPerColumn` → `MODEL_SIZE = 100·scale`, `ROW_HEIGHT = 120·scale`.

So the label now misleads: resize the panel taller and you see 8 per column with the
setting on 5. This was flagged as pending polish in
[models-browser-resizable-goal memory] ("let `petsPerColumn` just mean model size,
rename the option").

**Outcome:** the control becomes an honest **model-size** slider — 5 stops,
Small ↔ Large — while the underlying render math is left byte-for-byte unchanged. Row
count keeps tracking panel height; column count stays 2 (out of scope).

### Decisions (settled with the user)

| Question | Choice |
|---|---|
| Direction | Rename to a model-size control with 5 named sizes |
| Control type | **Slider** (X-Small ↔ X-Large), joining the four existing model sliders |
| Scale steps | **Reuse** the existing divisors, ascending with the slider: stops 1–5 = `{10, 7, 5, 3, 2}`, so `scale = 5/divisor` = `{0.5, 0.714, 1.0, 1.667, 2.5}` (XS…XL). Default = stop 3 = divisor 5 = scale 1.0, identical to today's default. The thumb snaps to the five stops (one tick drawn under each), so a drag between stops can't reflow the browser for a size that doesn't exist. |

Migration: an existing saved `petsPerColumn` is snapped to the nearest divisor's stop
and the dead key is dropped.

## Key idea

Introduce **one resolver**, `PSM.ModelsPanel:ModelSizeDivisor()`, returning the
effective pets-per-column divisor for the current slider stop. Every existing formula
(`GetPageLayout`, `UpdateModelsPanelLayout`, `scalingFactor`, `TextSuppressed`) keeps
consuming that single number exactly as it consumed `petsPerColumn`. Nothing about
card geometry, text wrap, NPC-line spacing, pagination, or text suppression changes
behaviour — only the source of the number and its UI.

## Changes

### 1. `PetStableManagement/Shared/Config.lua:132-135`

Replace the three `*_PETS_PER_COLUMN` constants:

```lua
-- Browser Model Size: a 1..5 slider stop. Maps onto the pets-per-column divisors the
-- old "Pets Per Column" dropdown used, so scale = 5/divisor is unchanged per stop:
-- stop 1 = X-Small card (0.5x) .. stop 5 = X-Large (2.5x); stop 3 = Medium (1.0x).
BROWSER_MODEL_SIZE_DIVISORS = { 10, 7, 5, 3, 2 },
DEFAULT_BROWSER_MODEL_SIZE  = 3,
MIN_BROWSER_MODEL_SIZE      = 1,
MAX_BROWSER_MODEL_SIZE      = 5,
-- Max card-rows a tall panel renders per column (also the model-row pool multiplier).
-- Was MAX_PETS_PER_COLUMN; its own constant now that size and row-count are decoupled.
MAX_BROWSER_CARD_ROWS       = 10,
```

### 2. `PetStableManagement_ModelsBrowser/ModelsBrowser/ModelsPanel.lua`

- **New resolver**, next to the other internal helpers (above `GetPageLayout`, ~line 79):

  ```lua
  function PSM.ModelsPanel:ModelSizeDivisor()
      local d = PSM.Config.BROWSER_MODEL_SIZE_DIVISORS
      local stop = PetStableManagementDB.settings.browserModelSize
                   or PSM.Config.DEFAULT_BROWSER_MODEL_SIZE
      return d[stop] or d[PSM.Config.DEFAULT_BROWSER_MODEL_SIZE]
  end
  ```

- `GetPageLayout` (:103): `local ppc = PSM.ModelsPanel:ModelSizeDivisor()`.
  Clamp (:111): `PSM.Config.MAX_BROWSER_CARD_ROWS`. Update the :80-84 doc comment
  ("the Browser Model Size stop's divisor", not "the raw petsPerColumn setting").
- `UpdateModelsPanelLayout`: `MAX_ROWS` (:204) → `PSM.Config.MAX_BROWSER_CARD_ROWS * 2`.
  Rename the diagnostic mirror `MODELS_CONFIG.PETS_PER_COLUMN` → `SIZE_DIVISOR` at its
  two write sites (:34 default table, :196) — nothing reads it. Leave `PETS_PER_PAGE`
  (read by `ModelsDataLoader.lua:757`).
- Lazy-init block (:676-679) → **migration**:

  ```lua
  if PetStableManagementDB.settings.browserModelSize == nil then
      local old = PetStableManagementDB.settings.petsPerColumn
      if type(old) == "number" then
          local d, best, bestErr = PSM.Config.BROWSER_MODEL_SIZE_DIVISORS,
                                    PSM.Config.DEFAULT_BROWSER_MODEL_SIZE, math.huge
          for stop = 1, #d do
              local err = math.abs(d[stop] - old)
              if err < bestErr then best, bestErr = stop, err end
          end
          PetStableManagementDB.settings.browserModelSize = best
      else
          PetStableManagementDB.settings.browserModelSize = PSM.Config.DEFAULT_BROWSER_MODEL_SIZE
      end
      PetStableManagementDB.settings.petsPerColumn = nil
  end
  ```

### 3. `PetStableManagement_ModelsBrowser/ModelsBrowser/ModelRow.lua`

- `scalingFactor()` (:15-18): `return 5 / PSM.ModelsPanel:ModelSizeDivisor()`. Fix the
  :14 comment.
- `TextSuppressed()` (:31-34):

  ```lua
  return (PetStableManagementDB.settings.browserModelSize
          or PSM.Config.DEFAULT_BROWSER_MODEL_SIZE) >= PSM.Config.MAX_BROWSER_MODEL_SIZE
  ```

  Stop 5 (X-Large card) == old `petsPerColumn == 2`, so suppression fires on exactly
  the same case. Update the :27-30 and :246 comments ("at the X-Large size", not
  "petsPerColumn == 2").

### 4. `PetStableManagement/Shared/OptionsPanel.lua`

- Replace the `PetsPerColumnDropdown` spec (:304-326) with a slider spec shaped like
  its four siblings (`modelZoom` etc.):

  ```lua
  {
      kind      = "slider",
      name      = "BrowserModelSizeSlider",
      key       = "browserModelSize",
      title     = ns.L("Browser Model Size:"),
      default   = cfg.DEFAULT_BROWSER_MODEL_SIZE,
      min       = cfg.MIN_BROWSER_MODEL_SIZE,
      max       = cfg.MAX_BROWSER_MODEL_SIZE,
      step      = 1,
      round     = 0,
      snap      = true,   -- a stop is a state, not a position: thumb snaps stop-to-stop
      ticks     = #cfg.BROWSER_MODEL_SIZE_DIVISORS, -- one tick drawn per stop
      -- The middle stops carry one-letter labels (S/M/L, same font as the XS/XL
      -- end captions); X-Small/X-Large are already named by those end captions.
      tickLabels = { [2] = ns.L("S"), [3] = ns.L("M"), [4] = ns.L("L") },
      lowLabel  = ns.L("XS"),
      highLabel = ns.L("XL"),
      format    = function(v)
          local names = { ns.L("X-Small"), ns.L("Small"), ns.L("Medium"),
                          ns.L("Large"), ns.L("X-Large") }
          return ns.L("Model Size: %s", names[v] or names[cfg.DEFAULT_BROWSER_MODEL_SIZE])
      end,
      apply = function()
          if ns.state.modelsPanel and ns.Browser.ModelsPanel then
              ns.Browser.ModelsPanel:ReflowContent()   -- geometry + re-render + page clamp
          end
      end,
  },
  ```

  (`ReflowContent` is the blessed entrypoint and also clamps the page — a bigger card
  means fewer rows/page; the old `UpdateModelsPanelLayout` + `UpdateVisibleRows` pair
  skipped that.)

- Layout (:529-537): drop the `petsPerColumnTitle` label + dropdown `BuildOption`;
  the slider carries its own title via `LabelledSlider`:

  ```lua
  local browserModelSizeSlider = BuildOption(byKey.browserModelSize, {
      anchorWidget = horizontalPositionSlider, anchorOffset = SLIDER_SLIDER_SPACING,
  })
  ```

- Re-anchor `backgroundTypeTitle` (:543): was beside the dropdown
  (`{ "TOPLEFT", petsPerColumnTitle, "TOPRIGHT", 20, 0 }`); now stacks under the
  full-width slider — `{ "TOPLEFT", browserModelSizeSlider, "BOTTOMLEFT", 0, SLIDER_SLIDER_SPACING }`.
- `TextForChoice` comment (:363-367): delete the `petsPerColumn` / `displayText`
  sentence — it no longer has a dropdown.
- Slider reset already handled generically (`:SetValueSilently(spec.default)`, :579-580).

### 5. `PetStableManagement/Shared/Locale.lua:538`

Remove `["Pets Per Column in Browser:"]`. Add enUS self-map entries, matching the
file's existing pattern: `["Browser Model Size:"]`, `["Model Size: %s"]`,
`["X-Small"]`, `["Small"]`, `["Medium"]`, `["Large"]`, `["X-Large"]`, `["XS"]`,
`["XL"]`. (None of these keys exist yet.)

### 6. `README.md:72` and `README.md:138`

Rewrite both bullets as plain present-tense current behaviour (per the "README is a
feature list" rule):

- :72 → describe the resizable Models Browser with an adjustable model-preview size.
- :138 → `**Browser Model Size**: pet-preview size in the Models Browser (X-Small to X-Large)`.

`docs/ARCHITECTURE_PLAN.md` mentions of `petsPerColumn` are historical record — leave.

## Out of scope (leave as-is)

- Column count stays hardcoded at 2 (`(petsFrame:GetWidth() - 30) / 2` etc.).
- Text suppression stays tied to the largest size rather than becoming width-aware.
- `MODELS_CONFIG.PANEL_HEIGHT = 820` "floors to exactly N rows" comment stays valid —
  divisors are unchanged, so Medium at 820px still yields exactly 5 card rows.
- **X-Large fills the column (follow-up).** At stop 5 the square card spans the
  column width (`columnWidth − MODEL_INSET − RIGHT_PAD`) instead of `100·scale`,
  and the row pitch grows with it (`fill + 8`) so the taller card fits and
  rows-per-page re-derives. All other stops keep `MODEL_SIZE = 100·scale`,
  `ROW_HEIGHT = 120·scale`. `ComputeCardGeometry` is the single source, consumed by
  both `GetPageLayout` and `UpdateModelsPanelLayout`, so card size, row pitch and
  rows-per-page can never disagree.

## Verification

1. **Headless tests** — from repo root:
   ```bash
   lua.exe Tests/run.lua
   ```
   Expect all pass unchanged (no spec references this setting).
2. **Lint** — expect the 9/0 baseline unchanged (no new globals; `browserModelSize` is
   a table field; confirm no dangling `*_PETS_PER_COLUMN` refs after the edits):
   ```bash
   "C:\Users\Gi\Dev\tools\luacheck.exe" PetStableManagement PetStableManagement_ModelsBrowser Tests
   ```
3. **In-game (user)** after `/reload`:
   - Options → *Pet Model Settings* shows a **Browser Model Size** slider as the 5th
     slider, 5 stops, caption "Model Size: Medium" at default; Background dropdown now
     sits below it.
   - Drag the slider → the thumb snaps to the five stops (one tick under each), the
     caption labels the size you land on, and the browser only reflows when the stop
     actually changes. X-Large hides row text (as the old `ppc == 2` did); X-Small
     shows the most.
   - A character whose SavedVariables had `petsPerColumn = 8` → slider opens on **Small**
     (stop 2); after a save, `petsPerColumn` is gone from the file, `browserModelSize = 2`.
   - Resize the panel taller/shorter → rows-per-page still tracks height at any slider
     stop.
   - *Reset All Settings* → slider returns to Medium.
