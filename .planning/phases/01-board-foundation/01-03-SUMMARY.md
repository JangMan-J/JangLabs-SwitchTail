---
phase: "01"
plan: "03"
subsystem: plugin/adapter
tags: [spawn-board, run-commands, command-pane-exited, no-kill, comp-01, comp-02, comp-11]
dependency_graph:
  requires:
    - HostIntent::SpawnBoard { command } (01-02)
    - Exchange::note_command_exit (01-02 core half)
    - KeyInput + compose_board_key binding (01-01)
  provides:
    - SpawnBoard adapter arm → open_command_pane_in_new_tab (return discarded)
    - PermissionType::RunCommands declared in load()
    - EventType::CommandPaneExited subscribed + Event::CommandPaneExited arm → note_command_exit
    - tests/e2e.sh isolated permission cache includes RunCommands grant
  affects:
    - crates/switchtail-plugin/src/main.rs (load/update/dispatch)
    - tests/e2e.sh (headless permission cache seed)
tech_stack:
  added: []
  patterns:
    - Return-value discard: open_command_pane_in_new_tab -> (Option<usize>, Option<PaneId>) discarded; core reconciles via async TabUpdate/PaneUpdate (mirrors OpenLine's Option<PaneId> discard)
    - FIFO dispatch ordering: SpawnBoard + OpenLine×(N-1) in one Vec guarantees lines 2..N land on the new board before any TabUpdate arrives
    - Thin adapter: SpawnBoard arm is one shim call; CommandPaneExited arm routes to core then dispatches; no business logic
key_files:
  created: []
  modified:
    - crates/switchtail-plugin/src/main.rs
    - tests/e2e.sh
decisions:
  - "SpawnBoard return discarded: (Option<usize>, Option<PaneId>) from open_command_pane_in_new_tab is let-_=-discarded; core reconciles board+lines via async events (consistent with OpenLine's Option<PaneId> discard; STACK.md §Async/Ordering)"
  - "RunCommands declared (owner decision 2026-06-13): enables open_command_pane for the fan-out's lines 2..N; open_command_pane_in_new_tab only needs ChangeApplicationState (already declared). Wider permission surface accepted; interactive grant required."
  - "CommandPaneExited arm routes to note_command_exit only (no close/kill): per COMP-11 contract. no_kill_guard.rs stays green."
  - "e2e.sh cache re-seed: both bare-path and file:-path cache keys updated with RunCommands; the user's real cache re-prompts once on first interactive launch."
metrics:
  duration_seconds: ~90
  completed_date: "2026-06-13"
  tasks_completed: 1
  tasks_total: 2
  files_changed: 2
---

# Phase 01 Plan 03: Host wiring — SpawnBoard, RunCommands, CommandPaneExited Summary

SpawnBoard dispatch arm wired to open_command_pane_in_new_tab (return discarded); RunCommands permission declared; CommandPaneExited subscribed and routed to note_command_exit — headless gate green, live human-verify pending.

## What Was Built

### Task 1 — SpawnBoard arm + RunCommands permission + CommandPaneExited routing + e2e cache re-seed

**SpawnBoard dispatcher arm (COMP-01/02):**

Replaced the no-op stub in `dispatch()` with the real implementation:
- Builds `CommandToRun::new_with_args(&command[0], command[1..].to_vec())` — verbatim argv, never a shell (T-01-09 mitigated)
- Calls `open_command_pane_in_new_tab(cmd, BTreeMap::new())`; the returned `(Option<usize>, Option<PaneId>)` is bound to `_` (discarded) — core registers the board + first line via the async TabUpdate/PaneUpdate events, exactly as the OpenLine arm discards its `Option<PaneId>`
- The subsequent OpenLine intents in the same dispatch Vec land lines 2..N on the new board via FIFO dispatch ordering (per STACK.md §Async/Ordering — no mid-loop state reads needed)
- Shim source verified: `open_command_pane_in_new_tab(CommandToRun, BTreeMap<String,String>) -> (Option<usize>, Option<PaneId>)` at shim.rs:966

**RunCommands permission (load()):**

Added `PermissionType::RunCommands` to the `request_permission` array. Enables `open_command_pane` for the fan-out's lines 2..N (and Phase 3 line verb). `open_command_pane_in_new_tab` needs only the already-declared `ChangeApplicationState`. Permission source: zellij-utils-0.44.3/src/data.rs:1067. Threat T-01-08 mitigated: deliberate owner decision, interactive grant, verbatim argv.

**CommandPaneExited subscription + arm (COMP-11 adapter half):**

- Added `EventType::CommandPaneExited` to the `subscribe` list in `load()`
- Added `Event::CommandPaneExited(pane_id, status, _ctx)` arm in `update()` that calls `self.exchange.note_command_exit(LineId(pane_id), status)`, dispatches returned intents (attention highlights for ringing — no close/kill), returns `true` to re-render
- Event shape verified: `CommandPaneExited(u32, Option<i32>, Context)` at zellij-utils-0.44.3/src/data.rs:994
- No close/kill call site introduced — no_kill_guard.rs stays green (authoritative proof: runs inside `tools/dev.sh test`)

**tests/e2e.sh permission cache re-seed:**

Both the bare-wasm-path and `file:` cache key blocks in the isolated `XDG_CACHE_HOME` now include `RunCommands`. A comment notes that the user's real `~/.cache/zellij/permissions.kdl` will re-prompt once on first interactive launch after this change — the operator must approve the expanded grant interactively.

## Verification Results

```
tools/dev.sh test: 53 tests passed + 1 no_kill_guard — 0 failed
tools/dev.sh build: wasm32-wasip1 debug artifact produced (path: target/wasm32-wasip1/debug/switchtail.wasm)
no_kill_guard.rs: AUTHORITATIVE green — SpawnBoard arm and CommandPaneExited arm add no close/kill call site
```

## Deviations from Plan

None — plan executed exactly as written. The three changes (SpawnBoard arm, RunCommands permission, CommandPaneExited subscription + arm) plus the e2e cache re-seed were the complete scope of Task 1. No auto-fix or Rule deviations triggered.

## Threat Model Coverage

| Threat | Status | Where |
|--------|--------|-------|
| T-01-08: RunCommands elevation of privilege | MITIGATED | Owner-approved deliberate addition; interactive grant; scoped to operator-configured command. Permission set still minimal (no WebAccess, no InterceptInput, no RunActionsAsUser). |
| T-01-09: CommandToRun argv injection | MITIGATED | `CommandToRun::new_with_args(path, args)` — verbatim argv, never a shell string. Source is operator config, not remote input. |
| T-01-10: Destruction of data (no-kill) | MITIGATED | SpawnBoard arm adds no close/kill shim; CommandPaneExited arm only calls note_command_exit (logs, retains). no_kill_guard.rs green — authoritative proof. |
| T-01-11: DoS via headless hang | MITIGATED | tests/e2e.sh isolated cache includes RunCommands; headless runs do not hang on permission re-prompt. Interactive re-prompt documented for operator. |

## Known Stubs

None — the SpawnBoard stub (from 01-02) is replaced with the real implementation in this plan.

## Awaiting Human Verification (Task 2 — blocking checkpoint)

Task 2 is a `checkpoint:human-verify` (gate="blocking-human") requiring a live zellij session. See checkpoint section below.

## Self-Check: PASSED

Files exist on disk:
- FOUND: crates/switchtail-plugin/src/main.rs
- FOUND: tests/e2e.sh
- FOUND: .planning/phases/01-board-foundation/01-03-SUMMARY.md

Commits exist in git log:
- FOUND: 646c25e (feat(plugin): wire SpawnBoard arm, RunCommands perm, CommandPaneExited routing)
