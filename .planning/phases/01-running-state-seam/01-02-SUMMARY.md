---
phase: 01-running-state-seam
plan: 02
subsystem: kitty-watchers
tags: [kitty, watcher, on_focus_change, python, state-dir, focus-tracking]

# Dependency graph
requires: []
provides:
  - kitty/state.py — on_focus_change global watcher maintaining $STATE/active (gain -> atomic tmp+os.replace write; loss -> compare-and-clear unlink)
  - kitty/state.conf — one-line watcher registration (tail.conf analog), NOT yet deployed
  - tests/state-test.py — kitty-stubbed unit suite (11 assertions) loading state.py repo-relative
  - "$STATE/active state path: first line = focused board name, absent = off-board"
affects: [01-03, 01-04, 01-05]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "one verb class per watcher file: tail.py = send-text only, state.py = filesystem only — each safety audit fits one screen"
    - "compare-and-clear: focus-loss unlinks $STATE/active only if it still names the losing board, so a newer gain is never clobbered"
    - "repo-relative importlib load in python test suites (dirname(__file__)/../kitty), never the deployed config path"

key-files:
  created:
    - kitty/state.py
    - kitty/state.conf
    - tests/state-test.py
  modified: []

key-decisions:
  - "Test suite loads state.py from the repo tree, not the deployed path — the Pitfall-1 honesty STAIL_BIN gives the bash suites, applied to python"
  - "Mutation-verified the suite: removing the charset gate or the compare-and-clear each makes it fail (acceptance criterion proven, not assumed)"

patterns-established:
  - "Filesystem-only watcher contract: header declares it, automated grep gate (zero non-comment send_text/close/destroy/remote-control tokens) enforces it"
  - "Atomic active-file write: PID-suffixed tmp + os.replace (Python mirror of stail's mv -f primitive)"

requirements-completed: [SEAM-01]

# Metrics
duration: 4min
completed: 2026-06-12
---

# Phase 01 Plan 02: Focus Watcher (kitty/state.py) Summary

**kitty on_focus_change watcher writes the focused board's name to $STATE/active (atomic tmp+os.replace) and compare-and-clears it on loss, charset-gated and exception-proof, with an 11-assertion kitty-stubbed unit suite testing the repo tree directly**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-06-12T08:43:58Z
- **Completed:** 2026-06-12T08:46:28Z
- **Tasks:** 2
- **Files modified:** 3 (all created)

## Accomplishments

- `stail active` now has its kdotool-free data source: the watcher maintains `$STATE/active` event-driven (the `active` half of SEAM-01 per OQ-1), ready for plan 01-04's `cmd_active` rewrite and plan 01-05's deployment.
- Safety contract holds structurally, not just in prose: zero non-comment `send_text`/`close_window`/`destroy`/`call_remote_control` tokens (grep-gated), blanket `try/except Exception` around the whole hook body, `_BOARD_RE` charset gate identical to the CLI's before the value touches anything — and the board value is written as file content only, never interpolated into a path (T-01-W1/W2/W3 mitigations all landed per the plan's threat model).
- The unit suite runs without a kitty runtime (sys.modules stubs for kitty/kitty.boss/kitty.window; no fast_data_types needed — state.py schedules no timers): 11 passed, 0 failed, covering gain (+ no-tmp-leftover atomicity), loss, compare-and-clear ordering, no-board jurisdiction, hostile values (`../evil`, `a b`), and the read-only-state-home exception path.
- Mutation check confirms test honesty: stripping the charset gate fails case 5; replacing compare-and-clear with an unconditional unlink fails case 3.
- Nothing deployed: no symlinks into the live kitty config, no kitty.conf include — the daily driver is untouched (plan 01-05 owns deployment).

## Task Commits

Each task was committed atomically:

1. **Task 1: kitty/state.py focus watcher + state.conf** - `a9e6053` (feat)
2. **Task 2: tests/state-test.py kitty-stubbed unit suite** - `bdeef67` (test)

## Files Created/Modified

- `kitty/state.py` - on_focus_change global watcher: charset-gated board read, atomic gain write, compare-and-clear loss, blanket exception guard; tail.py-style safety-contract header declaring the filesystem-only property and WHY it is a separate file
- `kitty/state.conf` - single directive `watcher state.py` (tail.conf analog); included from kitty.conf only at plan 01-05 deployment
- `tests/state-test.py` - 11-assertion unit suite; loads state.py via `os.path.dirname(__file__)/../kitty/state.py` (repo-relative, never the deployed path); fresh tempdir XDG_STATE_HOME per case

## Decisions Made

- Loaded the watcher repo-relative in the test suite (per plan directive) — tail-test.py's deployed-path load is the known trap; this suite tests the edited tree.
- Added a belt-and-suspenders assertion to case 5 (no file of ANY name appears under the state home after hostile inputs) — confirms no path escape, not just "the expected file is absent". Within the planned case, not a deviation.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None. (The 35 pre-existing bash-suite baseline failures from workspace drift are documented in deferred-items.md and do not touch this plan's python suite, which is new and green.)

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 01-03 can stamp `--var board=` in `_emit_session` knowing the consumer (this watcher) exists and is unit-proven; its `stail line` panes will feed `$STATE/active` once 01-05 deploys.
- Plan 01-04's `cmd_active` rewrite has its data source defined: first line of `$STATE/active`, charset-gated on read (defense in depth), cross-checked against run markers.
- Plan 01-05 owns deployment: symlink state.py/state.conf into the live kitty config + kitty.conf include + board relaunch (RESEARCH Pitfall: already-running kitty processes never load the watcher).
- Assumption A3 (loss event fires when focus moves to a non-kitty app) remains a live-verify item for the phase smoke test — the compare-and-clear and run-marker cross-check bound the damage if it proves false.

## Self-Check: PASSED

- kitty/state.py — FOUND
- kitty/state.conf — FOUND
- tests/state-test.py — FOUND
- Commit a9e6053 — FOUND
- Commit bdeef67 — FOUND

---
*Phase: 01-running-state-seam*
*Completed: 2026-06-12*
