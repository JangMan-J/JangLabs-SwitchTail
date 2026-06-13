---
status: resolved
phase: 04-operator-polish-e2e
source: ROADMAP.md success criteria + STATE.md live-verification concerns (no per-phase SUMMARY.md — v0.1 built in one autonomous session)
started: 2026-06-12T12:43:48-07:00
updated: 2026-06-13T00:00:00-07:00
resolution: "Both gaps (tests 4, 6) closed in 04-05 + 04-06 and re-verified live 2026-06-13. UAT now 9/9."
---

## Current Test

[testing complete]

## Tests

### 1. Cold Start — launch the switchboard
expected: In a live zellij session, press Alt+s. First launch shows zellij's one-time permission prompt; after approval the SwitchTail board opens as a floating pane showing the directory view, no panics (zellij.log clean).
result: pass

### 2. Directory mirrors live panes
expected: The board lists the session's panes as lines with their names. Opening a new line (`n` key, or a normal zellij new pane) makes it appear in the directory; the listed set matches the real pane set.
result: pass

### 3. Deck jump
expected: Pressing `1`–`9`/`0` focuses the corresponding deck line in one press — focus lands on the right pane every time. `j`/`k` + Enter focuses lines beyond the deck.
result: pass

### 4. Seat mark + swap (live semantics check)
expected: "`m` marks the selected line as the seat. Selecting another line and pressing `s` swaps it into the seat position. The displaced line stays alive and is recoverable via focus (shipped with suppress=true). NOTE: true positional-swap semantics were never confirmed live — observe exactly where both panes end up."
result: pass
resolved: "Fixed in 04-06 (composed 3-call positional exchange). Live-verified 2026-06-13: panes trade places exactly, layout unchanged, no residue, repeatable, log clean. Seat marker follows the position."

### 5. Patch a message to a line
expected: "`i` opens the message prompt; typing text and pressing Enter delivers it into the target line's terminal (visible as typed input there)."
result: pass

### 6. Ring surface is CB-safe; answer/park clears it
expected: "`R` rings the selected line: the target pane gets an amber tint + highlight (blue↔amber semantics, no red/green meaning). `a` (answer) or `p` (park) clears the ring surface."
result: pass
resolved: "Fixed in 04-05 (identity-anchored selection). Live-verified 2026-06-13: R lands amber on the operator's selected line, cursor stays glued through the RingingFirst re-sort, a clears it to zero ringing lines. Pipe ring/list round-trip confirmed."

### 7. Call log + sort cycling
expected: "`Tab` toggles directory ⇄ call log; events from the session (rings, status changes, says) appear in the log with triage states. `o` cycles sort: deck · ringing-first · board."
result: pass

### 8. Pipe queries return live JSON
expected: From a shell inside the session, `zellij pipe -n switchtail -- '{"op":"list"}'` prints JSON that parses and matches the live pane set; `'{"op":"log","n":50}'` returns call-log entries as JSON.
result: pass
note: Verified both in-session and cross-session via the global `--session` flag (`zellij --session <name> pipe ...`). Output showed stray ringing:true on lines 0 and 2 — corroborating evidence for the test-6 ring mistargeting gap.

### 9. Pipe mutations drive the board; malformed payload never panics
expected: "`say` delivers text to the line, `focus` switches focus, `ring` surfaces amber on the target, `status`/`register` update the line's metadata in the directory. Piping a malformed payload (e.g. `'garbage'`) is logged as a call — the plugin keeps running, no panic in zellij.log."
result: pass

## Summary

total: 9
passed: 9
issues: 0
pending: 0
skipped: 0
note: "Initial UAT 2026-06-12 found 7 pass + 2 major gaps (tests 4, 6).
Both diagnosed to a shared root cause (drifting selection index) and fixed
in 04-05 + 04-06; re-verified live 2026-06-13 — all 9 pass."

## Gaps

```yaml
- truth: "Seat swap is a true positional exchange: the two panes trade places precisely, overall layout unchanged"
  status: resolved
  resolved_in: 04-06
  resolved_date: "2026-06-13"
  reason: "User reported: the swap should case both windows to exchange their positions precisely so that the layout remains the same but the terminals have traded places"
  severity: major
  test: 4
  root_cause: "Swap dispatches one replace_pane_with_existing_pane(seat, line, suppress=true) call, but that zellij primitive is a one-way 'bring that pane here' (built for pane pickers): host extracts the line (slot collapses, possible auto-relayout), places it in the seat's geometry, and hides the seat in suppressed_panes — the seat is never placed into the line's old slot. No swap_panes(a,b) primitive exists in the plugin API (exhaustive PluginCommand scan, zellij-utils 0.44.3 + host commit e9173cb)."
  artifacts:
    - path: "crates/switchtail-plugin/src/main.rs:127"
      issue: "SwapIntoSeat maps to a single replace_pane_with_existing_pane call — primitive cannot express a positional exchange"
    - path: "crates/switchtail-core/src/intent.rs:14"
      issue: "SwapIntoSeat intent doc encodes the one-way 'replace' semantics into the contract"
    - path: "docs/DESIGN.md"
      issue: "capability 3 documents the call as 'seat swap' — propagates the false assumption (also docs/zellij-api-notes.md:48)"
  missing:
    - "Compose the exchange: (1) open_terminal_pane_in_place_of_pane_id pins the line's slot with placeholder P (close_replaced_pane=false), (2) replace_pane_with_existing_pane(seat, line, true), (3) replace_pane_with_existing_pane(P, seat, false) — seat lands in line's original slot, placeholder closes (owner must bless the suppress=false close vs no-kill discipline)"
    - "Cheap common case: adjacent panes — move_pane_with_pane_id_in_direction IS a documented true positional swap"
    - "Must be E2E-verified live: FIFO ordering + suppressed-restore edge when P closes"
  debug_session: .planning/debug/seat-swap-not-positional.md
- truth: "Ring (`R`) surfaces the amber tint + highlight on the line the operator actually selected, consistently"
  status: resolved
  resolved_in: 04-05
  resolved_date: "2026-06-13"
  reason: "User reported: it is not consistently selecting the correct window/terminal for this feature, perhaps related to the swap function issue from earlier in my testing session"
  severity: major
  test: 6
  root_cause: "Selection is a bare row index (Exchange.selected: usize) into a re-sortable view, never re-anchored when order changes. Worst case is self-inflicted: in RingingFirst sort, R rings the correct line but refresh_ring_flags() re-sorts it to the top while `selected` keeps its value — the cursor silently lands on a different line, so follow-up a/p settles the wrong line and a retry rings a second one. Live list dump (lines 0+2 ringing, RingingFirst order) matches the reconstruction exactly. Pipe ops and ingest_panes() removals shift indices the same way; clamp_selection() only clamps length. Adapter is exonerated (id-based dispatch)."
  artifacts:
    - path: "crates/switchtail-core/src/exchange.rs"
      issue: "selected: usize index into sorted_lines()/log_view_calls(); R/settle_selected mutate ring flags that re-sort the view under the unchanged index; clamp_selection() clamps length only; log view shares the bug class"
    - path: "crates/switchtail-core/src/view.rs"
      issue: "renders cursor at raw index; renders only take(body_rows) while clamp allows off-screen selection (minor aggravator)"
  missing:
    - "Re-anchor selection by stable identity: Option<LineId> (directory) / Option<u64> call-seq (log), resolved to a row at render/navigation time"
    - "Or recompute the index against the new ordering after every reordering mutation (key handlers, pipe ops, ingest_panes)"
    - "Consider: ringing-first ordering should not re-sort as a side effect of the operator's own action"
  debug_session: .planning/debug/ring-targets-wrong-line.md
```

Note: shared root cause component — `s` (swap) resolves its target through the same drifting index, so the selection re-anchor fix also hardens swap targeting.
