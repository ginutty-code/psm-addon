# Proportional column resize (NPC view, Models Browser)

## Context

In the NPC view of the Pet Models Browser, each column boundary has a drag handle
(`NPCRow.lua`'s `ResizeDriver`/`CreateResizeHandle`). Today, dragging a column wider
only ever shrinks the **Display IDs** column — the flex column that absorbs whatever
width the fixed columns don't use (`FLEX_COLUMN = "displayIds"`). Every other column to
the right keeps its stored width untouched, so widening an early column (e.g. "Family")
does nothing to "Classification"/"Zone"/etc. sitting between it and Display IDs — all
the give comes out of Display IDs alone, which can make that column collapse fast.

The user wants standard proportional-resize behavior: widening column K should shrink
**every** column to K's right — including Display IDs — proportionally to their current
width, the same way spreadsheet/browser table resizes typically work. Confirmed with the
user: no special-casing for the flex column: "all should have the same behaviour."

Columns to the *left* of the dragged handle are unaffected — only the ones to the right
give up space, matching "shrink the remaining columns to its right."

## Design

The key trick: **keep the existing "Display IDs = leftover" invariant** rather than
giving it a real stored width. `RecomputeColumnLayout` already computes
`displayIds.width = totalWidth - (everything else)`. Because total table width is fixed
during a drag, conservation of width means: if we explicitly shrink the *other* right-side
columns by their proportional share of the requested delta, Display IDs automatically
absorbs exactly its own proportional share as the remainder — with zero code change to
`RecomputeColumnLayout` itself.

Concretely, when column `K` requests a stored-width delta of `d` (already computed by the
existing drag handler):

1. Take every visible column strictly to the right of `K` (this always ends with
   `displayIds`), weight each by its **last-drawn display width** (read from
   `panel.npcColumnLayout`, refreshed every reflow).
2. For every one of those columns *except* the flex column, shrink (or grow, if `d` is
   negative) its stored width by `d * (thatColumn'sWidth / rightTotal)`, floored at
   `MIN_COLUMN_WIDTH`.
3. Do nothing explicit for the flex column — its leftover-derived width in the next
   `RecomputeColumnLayout` pass will automatically equal its own proportional share,
   by conservation.

This means when `K` is the last non-flex column (e.g. "Note", immediately left of
Display IDs), there are no other right columns to shrink, and behavior is unchanged from
today (100% of the delta flows to Display IDs) — a natural backward-compatible special
case, not a separate code path.

### `MaxWidthForColumn` needs updating too

Today it caps `K`'s max width by claiming the **full current width** of every other
non-flex column, assuming none of them can give. Since right-side columns can now shrink
down to their own floor to make room, the cap must only claim `MIN_COLUMN_WIDTH` for
columns to the right of `K` (they can give), while still claiming the **full** width for
columns to the left of `K` (untouched by this drag, so still fully reserved). This lets
`K` grow considerably further than before, since the whole right-side pool can now
contribute, not just Display IDs.

## Implementation — `psm-addon/PetStableManagement_ModelsBrowser/ModelsBrowser/NPCRow.lua`

**1. Rewrite `MaxWidthForColumn`** (around line 297) to distinguish left-of-`key` (full
claim) from right-of-`key` (floor-only claim):

```lua
function PSM.NPCRow:MaxWidthForColumn(panel, key)
    if not panel or not panel.petsFrame then return nil end
    if key == FLEX_COLUMN then return nil end

    local visible   = VisibleColumns(self, panel)
    local hasFlex   = false
    local claimed   = 0
    local passedKey = false
    for _, col in ipairs(visible) do
        if col.key == FLEX_COLUMN then
            hasFlex = true
        elseif col.key == key then
            passedKey = true
        elseif passedKey then
            -- Right of the dragged column: it can now shrink toward its own
            -- floor to make room, so only the floor is claimed here.
            claimed = claimed + MIN_COLUMN_WIDTH
        else
            -- Left of the dragged column: untouched by this drag, still fully claimed.
            claimed = claimed + StoredWidth(panel, col)
        end
    end
    if not hasFlex then return nil end

    local budget = TableWidth(panel) - (COLUMN_GAP * (#visible - 1)) - MIN_FLEX_WIDTH
    return math.max(MIN_COLUMN_WIDTH, budget - claimed)
end
```

**2. Add a new helper right after it**, `ShrinkColumnsRightOf`, doing the proportional
redistribution described above:

```lua
-- Distributes `displayDelta` px of shrink (positive) or growth (negative), caused by
-- dragging `key` wider/narrower, across every visible column to key's right --
-- weighted by each one's last-drawn display width -- and writes the result back as
-- *stored* width (dividing by the scale factor, same conversion the dragged column's
-- own delta already uses). The flex column is deliberately left untouched: it has no
-- stored width of its own, so its share flows through automatically as whatever
-- RecomputeColumnLayout leaves over once the others claim theirs (conservation of the
-- fixed total table width).
function PSM.NPCRow:ShrinkColumnsRightOf(panel, key, displayDelta)
    if displayDelta == 0 then return end
    local layout = panel.npcColumnLayout
    if not layout then return end

    local layoutByKey = {}
    for _, l in ipairs(layout) do layoutByKey[l.key] = l end

    local passedKey, rightCols, rightTotal = false, {}, 0
    for _, col in ipairs(VisibleColumns(self, panel)) do
        if col.key == key then
            passedKey = true
        elseif passedKey then
            local w = (layoutByKey[col.key] and layoutByKey[col.key].width) or StoredWidth(panel, col)
            table.insert(rightCols, { col = col, width = w })
            rightTotal = rightTotal + w
        end
    end
    if rightTotal <= 0 then return end

    local f = panel._npcColumnScale or 1
    for _, entry in ipairs(rightCols) do
        if entry.col.key ~= FLEX_COLUMN then
            local share      = entry.width / rightTotal
            local newDisplay = math.max(MIN_COLUMN_WIDTH, entry.width - displayDelta * share)
            panel.npcColumnWidths[entry.col.key] = newDisplay / f
        end
    end
end
```

**3. Wire it into the drag handler** (`ResizeDriver:SetScript("OnUpdate", ...)`, around
line 386-389) — insert the call between computing the clamped `wanted` and writing it:

```lua
            local maxWidth = PSM.NPCRow:MaxWidthForColumn(panel, handle.columnKey)
            if maxWidth then wanted = math.min(wanted, math.max(maxWidth, current)) end

            -- Whatever K actually gains/loses has to come from the columns to its
            -- right, proportionally -- see ShrinkColumnsRightOf.
            PSM.NPCRow:ShrinkColumnsRightOf(panel, handle.columnKey, (wanted - current) * f)

            panel.npcColumnWidths[handle.columnKey] = wanted
            PSM.NPCRow:ReflowVisibleRows(panel)
```

No changes needed to `RecomputeColumnLayout`, `UpdateItemRow`, `UpdateHeaderRow`, or the
persistence in `StopResize` — all of them already read/write through
`panel.npcColumnWidths` generically, so the newly-written right-column widths persist to
`PetStableManagementDB.settings.npcViewColumnWidths` on mouse-up exactly like today.

### Known simplification (documented in a comment, not hidden)

The proportional split is a single pass, not an iterative re-pool like
`RecomputeColumnLayout`'s global `_npcColumnScale` (which excludes already-pinned columns
from the pool before dividing). If a right-side column is already at `MIN_COLUMN_WIDTH`
when the drag starts, it's floored immediately and simply contributes less than its
"fair" share — the shortfall silently flows to Display IDs via the same leftover
mechanism, not lost. This mirrors the tolerance the existing `MaxWidthForColumn` comment
already documents ("only approximate... self-limiting"), so it's consistent with this
file's existing precision bar rather than a new gap.

## Verification

No existing test coverage touches `NPCRow.lua`'s column math (checked: no spec file
references `RecomputeColumnLayout`/`MaxWidthForColumn`/`npcColumnWidths`), and this is a
live mouse-drag interaction, so per the project's established workflow this goes to the
user for in-game testing before any commit:

- Open the Models Browser, switch to NPC view.
- Drag an early column's right-edge handle (e.g. "Family") wider and confirm every
  column to its right — including Display IDs — visibly narrows together, proportional
  to their sizes, rather than only Display IDs collapsing.
- Drag it back narrower and confirm the same columns grow back proportionally.
- Toggle on an optional column (e.g. "Continent") to create a pinned/near-floor column
  among the shrink pool, then drag a column to its left wider — confirm it doesn't error
  and Display IDs still absorbs whatever the floored column can't give up.
- Resize the whole panel narrower (triggering `_npcColumnScale < 1`) and confirm column
  dragging still tracks the cursor correctly (no drift), matching pre-existing behavior.
- Run luacheck (`"C:\Users\Gi\Dev\tools\luacheck.exe" PetStableManagement PetStableManagement_ModelsBrowser Tests`) to confirm the baseline (9 warnings / 0 errors) is unchanged.

After the user confirms in-game, commit with a message describing the behavior change,
and consider a short addition to `docs/Backlog.md` near the existing "Resolved by
proportional scaling" section, since this directly extends that feature.
