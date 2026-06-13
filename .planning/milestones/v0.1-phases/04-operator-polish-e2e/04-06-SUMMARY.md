---
phase: 04-operator-polish-e2e
plan: 06
status: complete
completed: "2026-06-13"
depends_on: ["04-05"]
---

# 04-06 Summary: Composed Positional Seat Swap

## Owner decision (Task 1)

**Proceed** — bless the `suppress_replaced_pane=false` close of the
plugin-owned placeholder pane. Rationale accepted: P is plugin-owned,
lives milliseconds, never holds operator work; the mechanism is a
parameter of `replace_pane_with_existing_pane`, not a `close_*` shim, so
the no-kill guard's FORBIDDEN list is untouched and not weakened.

## Root cause (verified at host commit e9173cb)

`replace_pane_with_existing_pane` is a **one-way "bring pane here"**
primitive built for pane pickers — it extracts the existing pane, places
it in the replaced pane's geometry, and suppresses/closes the replaced
pane. It never places the replaced pane into the existing pane's old
slot. No `swap_panes(a,b)` primitive exists anywhere in the plugin API
(exhaustive PluginCommand scan). The old single-call implementation was
inherently incapable of a positional exchange.

## Final transaction shape

Core emits a single composite intent `HostIntent::SwapPanes { seat, line }`.
The adapter's one dispatcher arm executes the fixed 3-call transaction:

1. `open_terminal_pane_in_place_of_pane_id(line, ".", false)` → placeholder
   P pins the line's slot (line suppressed but pid-addressable).
   **Abort-on-pin-failure**: if the host returns `None`, the swap aborts
   with zero mutations (eprintln to zellij.log).
2. `replace_pane_with_existing_pane(seat, line, true)` → line into the
   seat's slot; seat pane suppressed (still addressable).
3. `replace_pane_with_existing_pane(placeholder, seat, false)` → seat into
   the placeholder's slot (= line's original slot); plugin-owned P closes.

The placeholder PaneId is host-allocated mid-sequence and never crosses
the core/adapter seam — this is why per-call intents are impossible and
SwapPanes is the one sanctioned composed transaction (documented in
intent.rs module doc).

**Seat follows the position**: after the swap, `ex.seat == Some(line)` —
the line now occupying the seat slot becomes the new seat occupant. A
chained swap therefore exchanges with the main position, not the old
seat pane's new location.

## Live E2E findings (Task 4, 2026-06-13)

- **Positional swap exact**: panes trade slots precisely, layout otherwise
  unchanged, both visible, no leftover placeholder, no persistent flicker.
- **FIFO ordering confirmed**: the correct end state proves the three
  plugin commands process in dispatch order.
- **Suppressed-restore edge benign**: the step-1 "restore replaced pane
  when the new pane closes" relationship does NOT yank either pane back
  out of place when P closes.
- **Repeatable**: chained swaps work with no degradation; seat marker
  tracks the position across them.
- **Ring targeting (04-05 fix) confirmed live**: R lands amber on the
  operator's selected line, cursor stays glued through the RingingFirst
  re-sort, `a` clears it to zero ringing lines; pipe ring/list round-trip
  shows exactly the targeted line ringing.
- **zellij.log clean** — no panics across all of the above.

## Deferred follow-on

`move_pane_with_pane_id_in_direction(pane_id, direction)` IS a documented
true positional swap, but only with the **adjacent** pane in a direction.
It is a cheaper shortcut for the adjacent common case, not needed for the
gap truth, and requires geometry plumbing into PaneSnapshot + adjacency
math in core. Recorded in docs/zellij-api-notes.md; not implemented here.

## Cosmetic observation

The placeholder is a real terminal pane for milliseconds. A PaneUpdate
firing mid-transaction could transiently register it as a line (spurious
opened/closed log calls, momentary deck-key churn). Not engineered around;
polish later if it proves real in practice.

## UAT gap status

- **Test 4 (seat swap)**: RESOLVED → pass
- **Test 6 (ring targeting)**: RESOLVED → pass (via 04-05)
- Phase-4 UAT now 9/9.

## Commits

1. `fix(core): SwapPanes positional-exchange intent; seat follows the position`
2. `fix(plugin): compose seat swap as a true positional exchange (pin, replace, release)`
3. `docs: correct seat-swap semantics — replace_pane is one-way; exchange is composed`
(+ live-findings doc append + this summary)
