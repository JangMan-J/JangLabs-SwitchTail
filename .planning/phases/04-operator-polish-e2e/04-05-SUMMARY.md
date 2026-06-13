---
phase: 04-operator-polish-e2e
plan: 05
status: complete
completed: "2026-06-13"
---

# 04-05 Summary: Identity-Anchored Selection

## What changed

Replaced `Exchange.selected: usize` (a bare row index into re-sortable
views) with two stable identity anchors:

- `selected_line_id: Option<LineId>` — Directory view
- `selected_seq_id: Option<u64>` — Log view (call sequence number)

The row index is now derived at render/navigation time via
`selected_row() -> Option<usize>`.

## Handlers rewired

- **j/k navigation**: `navigate(delta)` maps anchor → current row → step
  → new anchor (clamped to view bounds).
- **Tab (view switch)** and **o (sort cycle)**: `seed_selection()` sets
  the anchor to the first item in the new view/sort.
- **ingest_panes**: if the anchored line was closed, falls back to the
  first remaining line. Seeds the anchor on first ingestion (None →
  first line).
- **view.rs render**: both `render_directory` and `render_log` compare
  `sel_row == Some(i)` instead of `i == ex.selected`.

## Repro tests added

- `ring_keeps_cursor_on_the_rung_line_in_ringing_first` — the primary
  UAT gap 6 repro (R in RingingFirst, cursor stays, a clears the same
  line, zero residual ringers)
- `selection_follows_line_across_pipe_ring_resort` — pipe ring on
  another line doesn't drift the cursor
- `selection_survives_line_close_index_shift` — closing a line before
  the cursor doesn't shift it; closing the cursor's own line falls back
- `log_selection_follows_call_seq_across_triage_resort` — answering a
  different call doesn't drift the log cursor
- `inverted_row_tracks_rung_line_in_ringing_first` (view.rs) — rendered
  inverted row shows the rung line after RingingFirst re-sort

## Pre-existing suite

All 29 original tests unchanged and passing (seat_swap_flow,
ring_pipe_op, sort_modes_cycle, deck_key, prompt, view tests, no-kill
guard). No `.selected` raw-index field survives anywhere in `crates/`.

## Commits

1. `test(core): reproduce ring/selection re-sort-under-cursor drift` (RED)
2. `fix(core): anchor selection by stable identity to stop ring/cursor drift` (GREEN)
3. `fix(core): render selection cursor from the resolved identity anchor` (view follow-through)
