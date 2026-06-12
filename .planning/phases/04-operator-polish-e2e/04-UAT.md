---
status: complete
phase: 04-operator-polish-e2e
source: ROADMAP.md success criteria + STATE.md live-verification concerns (no per-phase SUMMARY.md — v0.1 built in one autonomous session)
started: 2026-06-12T12:43:48-07:00
updated: 2026-06-12T13:05:00-07:00
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
result: issue
reported: "the swap should case both windows to exchange their positions precisely so that the layout remains the same but the terminals have traded places"
severity: major

### 5. Patch a message to a line
expected: "`i` opens the message prompt; typing text and pressing Enter delivers it into the target line's terminal (visible as typed input there)."
result: pass

### 6. Ring surface is CB-safe; answer/park clears it
expected: "`R` rings the selected line: the target pane gets an amber tint + highlight (blue↔amber semantics, no red/green meaning). `a` (answer) or `p` (park) clears the ring surface."
result: issue
reported: "it is not consistently selecting the correct window/terminal for this feature, perhaps related to the swap function issue from earlier in my testing session"
severity: major

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
passed: 7
issues: 2
pending: 0
skipped: 0

## Gaps

```yaml
- truth: "Seat swap is a true positional exchange: the two panes trade places precisely, overall layout unchanged"
  status: failed
  reason: "User reported: the swap should case both windows to exchange their positions precisely so that the layout remains the same but the terminals have traded places"
  severity: major
  test: 4
  artifacts: []  # Filled by diagnosis
  missing: []    # Filled by diagnosis
- truth: "Ring (`R`) surfaces the amber tint + highlight on the line the operator actually selected, consistently"
  status: failed
  reason: "User reported: it is not consistently selecting the correct window/terminal for this feature, perhaps related to the swap function issue from earlier in my testing session"
  severity: major
  test: 6
  artifacts: []  # Filled by diagnosis
  missing: []    # Filled by diagnosis
```
