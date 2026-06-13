---
phase: "01"
plan: "02"
subsystem: core/intent-model + core/exchange
tags: [spawn-board, fan-out, deck-cap, no-kill, tdd, comp-01, comp-02, comp-03, comp-10, comp-11, comp-12]
dependency_graph:
  requires:
    - switchtail_core::KeyInput (BareKey + shift/super_ flags, from 01-01)
    - Exchange::compose_board_key (configurable binding placeholder, from 01-01)
  provides:
    - HostIntent::SpawnBoard { command: Vec<String> }
    - Exchange::agent_command (default ["claude"])
    - Exchange::lines_per_board (default 5)
    - Exchange::deck_overflow_warning (CB-safe deck-cap advisory)
    - Exchange::note_command_exit (COMP-11 core half)
  affects:
    - crates/switchtail-core/src/intent.rs (SpawnBoard variant added)
    - crates/switchtail-core/src/exchange.rs (config fields, fan-out branch, helpers, tests)
    - crates/switchtail-plugin/src/main.rs (SpawnBoard stub arm for build exhaustiveness)
tech_stack:
  added: []
  patterns:
    - TDD RED/GREEN per task (3 RED commits → 2 GREEN feat commits + 1 Rule 3 fix)
    - Explicit Default impl for Exchange (non-empty Vec default requires it; derive insufficient)
    - deck_overflow_warning: counts occupied slots via lines×deck.key_for() — no new Deck API needed
    - note_command_exit modelled on note_cwd_change (known-line-only guard, log-and-return pattern)
key_files:
  created: []
  modified:
    - crates/switchtail-core/src/intent.rs
    - crates/switchtail-core/src/exchange.rs
    - crates/switchtail-plugin/src/main.rs
decisions:
  - Exchange::Default is explicit (not derived): agent_command needs vec!["claude".to_string()] which cannot come from #[derive(Default)] on a Vec.
  - deck_overflow_warning counts occupied slots as lines-with-a-deck-key, not via a new Deck method: avoids adding public API surface just for a count; sufficient for correctness.
  - deck_overflow_warning is CB-safe Info (non-ringing): operator-ambient, never red/green; fires before the fan-out is returned, advisory only.
  - note_command_exit returns attention_intents (LineExited rings via CallKind::rings()): consistent with existing exit path so the ring surface is uniform; never contains close/kill.
  - COMP-12 regression test required no new ingest_panes logic: the existing identity anchor (selected_line_id is re-seated only when the anchored line is gone) already guarantees no-drift; the test documents and locks this property.
  - SpawnBoard stub arm in adapter (Rule 3): adding the intent variant broke the adapter's exhaustive match on HostIntent; the stub no-op arm keeps the WASM build green until 01-03 wires the real shim.
metrics:
  duration_seconds: 319
  completed_date: "2026-06-13"
  tasks_completed: 3
  tasks_total: 3
  files_changed: 3
---

# Phase 01 Plan 02: Board-spawn machinery (core) Summary

SpawnBoard intent, agent_command/lines_per_board config, compose-verb fan-out [SpawnBoard + OpenLine×(N-1)], CB-safe deck-cap warning, and note_command_exit — all pure core, fully TDD'd.

## What Was Built

### Task 1 — SpawnBoard intent + config fields + compose-verb fan-out (intent.rs, exchange.rs)

Added `HostIntent::SpawnBoard { command: Vec<String> }` to `intent.rs` with a doc comment clarifying it is a normal one-intent-one-shim effect (NOT a composed transaction, NOT close/kill) — the adapter maps it to `open_command_pane_in_new_tab`.

Replaced `#[derive(Default)]` on `Exchange` with an explicit `Default` impl that sets:
- `agent_command: vec!["claude".to_string()]` — default agent, distinct from `line_command` (the bare-shell `n` opt-out)
- `lines_per_board: 5` — default board size

Filled in the compose-verb branch in `key()`: when the key matches `compose_board_key`, calls `deck_overflow_warning(lines_per_board)` then builds and returns `[SpawnBoard { agent_command }, OpenLine { agent_command } × (lines_per_board - 1)]`. Command and count are resolved entirely in core; the adapter never re-derives them.

Tests (all TDD GREEN): `compose_verb_emits_spawnboard_plus_openlines_default`, `compose_verb_uses_configured_agent_command_and_lines_per_board`, `compose_verb_lines_per_board_1_yields_only_spawnboard`, `n_key_still_opens_line_with_line_command_unchanged`, `exchange_default_agent_command_and_lines_per_board`.

Commits: `6f5b414` (RED), `fac0de0` (GREEN)

### Task 2 — CB-safe deck-cap warning (exchange.rs)

Added `deck_overflow_warning(&mut self, spawn_count: usize)` private helper:
- Counts occupied deck slots as the number of known lines with a `deck.key_for()` result
- Computes `remaining = DECK_KEYS.len() - used`
- When `spawn_count > remaining`: places ONE `CallKind::Info` entry (non-ringing, amber/neutral wording) naming the overflow count and deck capacity
- Never drops a line, never prevents the fan-out

The helper was co-implemented in the Task 1 GREEN commit (needed at compile time to call from the compose branch). Task 2 RED added tests that confirmed the pre-existing implementation was already correct.

Tests: `deck_cap_warning_absent_when_spawn_within_capacity`, `deck_cap_warning_fires_once_on_overflow`, `deck_cap_warning_is_info_not_ringing`.

Commits: `6ba7274` (combined RED+GREEN; implementation was in `fac0de0`)

### Task 3 — note_command_exit + COMP-12 no-drift regression test (exchange.rs)

**COMP-11 (core half):** Added `pub fn note_command_exit(&mut self, line: LineId, status: Option<i32>) -> Vec<HostIntent>`, modelled on `note_cwd_change`:
- If `self.lines.contains_key(&line)`: places ONE `CallKind::LineExited` entry; status=127 gets the special hint "exit 127 — command not found?"; all other statuses (including 0 and None) get a plain note; the line is RETAINED (no removal, no deck release)
- Calls `refresh_ring_flags()` and returns `attention_intents()` — LineExited rings, so the operator is notified; the returned Vec never contains a close/kill intent
- Unknown line → returns `vec![]` (no-op)

**COMP-12:** Wrote `spawn_board_fill_selection_does_not_drift` — starts with 2 lines on board 0, selects line 2 by identity, then simulates 5 sequential `ingest_panes` calls each adding 1-2 new lines on board 1 (the new board). Asserts `selected_line() == Some(LineId(2))` after EACH ingest AND that the 5 new lines carry `board == 1`. No new `ingest_panes` logic was required — the existing identity anchor (re-seats only when anchored line is gone) already guarantees it.

Tests: `note_command_exit_exit127_…`, `note_command_exit_status0_…`, `note_command_exit_none_status_…`, `note_command_exit_unknown_line_is_noop`, `spawn_board_fill_selection_does_not_drift`.

Commits: `af1c88f` (RED), `35c7816` (GREEN)

## Verification Results

```
tools/dev.sh test: 53 tests passed (53 core + 1 no_kill_guard) — 0 failed
tools/dev.sh build: wasm32-wasip1 debug artifact produced
no_kill_guard.rs: green (no new close_*/kill_* call sites; SpawnBoard arm is a stub no-op)
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] deck_overflow_warning co-implemented with Task 1 GREEN**

- **Found during:** Task 1 GREEN — the compose-verb branch calls `deck_overflow_warning` at compile time
- **Issue:** Task 1's branch was required to call the helper before returning the fan-out (per the plan), but the helper was planned for Task 2. Without it, Task 1 GREEN would not compile.
- **Fix:** Implemented `deck_overflow_warning` in the Task 1 GREEN commit (`fac0de0`). Task 2 RED added the behavior tests; all passed immediately since the implementation was already correct.
- **Files modified:** `crates/switchtail-core/src/exchange.rs`
- **Impact:** Task 2 has no separate GREEN commit (the implementation was already done). Documented in Task 2 commit message.

**2. [Rule 3 - Blocking] SpawnBoard variant broke adapter's exhaustive match**

- **Found during:** `tools/dev.sh build` after Task 1 GREEN
- **Issue:** Adding `HostIntent::SpawnBoard` caused the adapter's `dispatch` match to fail the Rust exhaustiveness check, preventing the WASM build.
- **Fix:** Added a stub no-op arm with a comment pointing to 01-03: `HostIntent::SpawnBoard { .. } => { /* 01-03 wires open_command_pane_in_new_tab */ }`.
- **Files modified:** `crates/switchtail-plugin/src/main.rs`
- **Commit:** `95838d2`

## Threat Model Coverage

| Threat | Status | Where |
|--------|--------|-------|
| T-01-04: agent_command → SpawnBoard/OpenLine → host command | MITIGATED | Core passes argv verbatim (NOT via shell). agent_command is operator config, not remote input. Note in field doc: use absolute path or PATH-safe wrapper (exit-127 PATH risk). |
| T-01-05: DoS via large deck fan-out | MITIGATED | Phase 1 spawns 5 (within deck capacity); deck-cap warning fires on overflow without dropping. Hard cap re-evaluated in Phase 2. |
| T-01-06: Destruction via no-kill | MITIGATED | note_command_exit logs LineExited, retains line, returns no close/kill. no_kill_guard.rs green. |
| T-01-07: Repudiation | ACCEPTED | Board-fill lines recorded as LineOpened on ingest (existing path). Audit surface unchanged. |
| T-01-SC: Package installs | N/A | No new dependencies. |

## Known Stubs

**SpawnBoard arm in adapter dispatch — no-op placeholder**

- File: `crates/switchtail-plugin/src/main.rs`, `dispatch()` match arm
- The `HostIntent::SpawnBoard { .. }` arm is a compilation stub (no-op) until 01-03 wires `open_command_pane_in_new_tab`
- Reason: 01-03 owns the adapter shim dispatch for SpawnBoard (plan split by ownership)
- Tracked: comment in the stub arm referencing 01-03

## TDD Gate Compliance

All three RED/GREEN gate sequences are present:

| Task | RED commit | GREEN commit |
|------|-----------|-------------|
| 1 (fan-out) | `6f5b414` | `fac0de0` |
| 2 (deck-cap) | `6ba7274` | `fac0de0` (co-impl) |
| 3 (note_command_exit + no-drift) | `af1c88f` | `35c7816` |

## Self-Check: PASSED

All key files exist on disk:
- FOUND: crates/switchtail-core/src/intent.rs
- FOUND: crates/switchtail-core/src/exchange.rs
- FOUND: crates/switchtail-plugin/src/main.rs
- FOUND: .planning/phases/01-board-foundation/01-02-SUMMARY.md

All commits exist in git log:
- FOUND: 6f5b414 (RED Task 1)
- FOUND: fac0de0 (GREEN Task 1 + Task 2 co-impl)
- FOUND: 6ba7274 (Task 2 tests)
- FOUND: af1c88f (RED Task 3)
- FOUND: 35c7816 (GREEN Task 3)
- FOUND: 95838d2 (Rule 3 fix: adapter stub arm)
