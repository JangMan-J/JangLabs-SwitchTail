---
phase: 01-running-state-seam
plan: 04
subsystem: cli-state
tags: [bash, stail, run-markers, proc, state-seam, kdotool]

# Dependency graph
requires:
  - "01-02: kitty/state.py focus watcher contract ($STATE/active first line = board name)"
  - "01-03: _run_mark/_pane_alive helpers + $STATE/run/<lab>/<pid> markers written by stail line"
provides:
  - "marker-scan _running_labs (lazy reap, ^[0-9]+$ filename gate, live exchange union per OQ-2, explicit return 0)"
  - "state-sourced cmd_active ($STATE/active + charset gate + _running_labs staleness cross-check; frozen --json shape)"
  - "ungated cmd_list (no _need_kdotool; frozen --json shape)"
  - "_lab_in_exchange (live board=exchange marker check) driving cmd_switch's exchange fallback"
  - "marker-keyed cmd_trunk already-up warning"
  - "post-seam docs: bin/stail header + CLAUDE.md contract point 5 + state-dir contract (stail/hold.py/state.py co-owners)"
  - "suite green at 208 assertions (new verification-gate baseline)"
affects: [01-05]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "detection from state, raise via kdotool: every running decision reads $STATE/run; kdotool survives only inside _win_ids/_need_kdotool/cmd_switch"
    - "pipefail-safe scan functions: explicit return 0 so `fn | grep -q` callers never see a leaked && tail status"
    - "live-marker test fixtures: background sleep helpers (stdout redirected away from command substitution) with real /proc start times"

key-files:
  created: []
  modified:
    - bin/stail
    - tests/stail-test-2.sh
    - tests/stail-test-3.sh
    - tests/stail-test-4.sh
    - tests/stail-test-6.sh
    - CLAUDE.md

key-decisions:
  - "_running_labs ends with explicit `return 0`: under `set -o pipefail` the trailing `[ saw_exchange ] && printf` returned 1 with no exchange up, failing every `_running_labs | grep -q` caller even on a match"
  - "Exchange-union live accuracy (OQ-2) encoded with inverse cases: a dead exchange line neither lists its lab running (test-2 B1) nor triggers switch's exchange raise (test-3) — it launches fresh"
  - "test-4 STATE made hermetic from §4 on: cmd_trunk's new marker scan would otherwise read AND lazily reap the operator's live state dir from inside the test suite"

patterns-established:
  - "reap centralization: _running_labs is the only reaper; _lab_in_exchange is a pure read (same gates, no rm)"
  - "no-kdotool-consult proof: a logging fail-stub kdotool + empty-log assertion is the literal SEAM-01 regression lock (test-6 §6)"

requirements-completed: [SEAM-01, SEAM-02]

# Metrics
duration: 9min
completed: 2026-06-12
---

# Phase 01 Plan 04: Reader Flip — Detection from Stail-Owned State Summary

**list/active/--json now report from $STATE/run markers and $STATE/active with kdotool provably never consulted (logging-stub proof), switch's exchange fallback decides from live markers, the dead session-file-grep helpers are deleted, and the repo docs describe only the post-seam world — full suite green at 208 assertions (new baseline)**

## Performance

- **Duration:** ~9 min
- **Started:** 2026-06-12T09:10:32Z
- **Completed:** 2026-06-12T09:19:30Z
- **Tasks:** 3
- **Files modified:** 6

## Accomplishments

- `_running_labs` rewritten as a `$STATE/run` marker scan: nullglob iteration, `^[0-9]+$` filename gate before any `/proc` or `rm` use (T-01-R1), `_pane_alive` start-time liveness (T-01-R4), lazy reap of dead markers (`rm -f`, race-idempotent, T-01-R5 accepted), `exchange` emitted once iff any live marker carries `board=exchange` (OQ-2 live accuracy — the old `_aggregate_labs` file-grep over-report is retired). Output contract unchanged (one lab per line, `exchange` when up).
- `cmd_active` re-sourced from `$STATE/active`: `head -n1` + charset gate `^[A-Za-z0-9._-]+$` before any JSON emission (T-01-R2) + `_running_labs` cross-check so a stale file naming a dead board reports off-board (T-01-R3); missing file = the same off-board degraded mode (correct before the watcher deploys). Emission block and exit codes byte-identical — `{"lab":"zlab","display":"Zlab","exchange":false}` / `{"lab":null,"display":null,"exchange":false}` byte-matched in test-6.
- `cmd_list` and `cmd_active` kdotool gates removed; `cmd_trunk`'s already-up warning re-keyed to `_running_labs` (warning text preserved); `cmd_switch`'s exchange-fallback decision moved to the new `_lab_in_exchange` (live `board=exchange` marker, reap-free read) while `_need_kdotool switch` and both `kdotool windowactivate` calls stay — removing kdotool now degrades raising only (SEAM-02).
- `_aggregate_labs`/`_lab_in_aggregate` and their banner deleted after grep-proving zero remaining callers.
- Tests rewritten at greater breadth, every behavioral assertion preserved against the new source: test-2 B1-B5 on live-marker STATE fixtures incl. the inverse dead-exchange-line case (16 passed, was 14; B6 raise stubs untouched); test-3 R2 on marker fixtures incl. dead-exchange-marker cases for both `_lab_in_exchange` and the launch fall-through (16, was 15); test-4 #10 on a live marker (26, unchanged); test-6 +12 reader assertions — §5 reap + hostile-filename non-handling, §6 the SEAM-01 no-kdotool-consult proof (logging fail-stub stays empty across all four list/active invocations) + switch-gate survival, §7 active staleness/missing-file cross-check (30, was 18).
- Post-seam docs: `bin/stail` header names `$STATE/run` + `$STATE/active` and restricts kdotool to switch; `_need_kdotool` message and `cmd_list` section comment updated; CLAUDE.md contract point 5 rewritten to the marker source, point 6 notes the unchanged JSON shape over marker-derived data, the state-dir 2-way contract extended to `run/` + `active` with `bin/stail`/`hold.py`/`state.py` as co-owners, the kitty/ surface enumeration gains the state watcher, and the verification-gate baseline is updated 147 → 208.
- Full suite: **ALL SUITES PASSED, 208 total passes, 0 failures** (test-1 25, test-2 16, test-3 16, test-4 26, test-5 39, test-6 30, kitten 27, tail 18, state 11) — >= 160 required; prior baseline was 193.

## Task Commits

Each task was committed atomically:

1. **Task 1: Re-source list/active + rewrite test-2 B1-B5 + extend test-6 (reader side)** - `b9db6e6` (feat)
2. **Task 2: Re-key trunk warning + switch exchange decision; delete dead grep helpers; rewrite test-3 R2 + test-4 #10** - `190aa88` (feat)
3. **Task 3: Post-seam docs (stail header + CLAUDE.md) + full-suite breadth gate** - `96b22d5` (docs)

## Files Created/Modified

- `bin/stail` - `_running_labs` marker scan + `_lab_in_exchange`; `cmd_active` state-sourced; `cmd_list` ungated; `cmd_trunk` warning marker-keyed; `cmd_switch` decision via `_lab_in_exchange`; `_aggregate_labs`/`_lab_in_aggregate` deleted; header/comments post-seam
- `tests/stail-test-2.sh` - B1-B5 on live-marker STATE fixtures (new exchange truth + inverse case); B6 raise stub kept
- `tests/stail-test-3.sh` - R2 sections on marker fixtures (`_lab_in_exchange` unit cases; exchange-raise/standalone-wins/dead-line-launches decision set)
- `tests/stail-test-4.sh` - #10 on a live marker; STATE hermetic from §4 (trunk's scan never touches the live state dir)
- `tests/stail-test-6.sh` - reader-side §5 (reap + hostile filename), §6 (no-kdotool-consult proof + switch gate), §7 (active staleness)
- `CLAUDE.md` - contract point 5/6 post-seam; state-dir contract extended (3 co-owners); kitty/ enumeration + 208-assertion gate

## Decisions Made

- **`return 0` appended to `_running_labs`:** the RESEARCH.md draft body ends `[ saw_exchange ] && printf 'exchange\n'`, which returns 1 when no exchange is up; with `set -o pipefail` live, every `_running_labs | grep -qxF` caller (active cross-check, trunk warning) then failed even on a match. Surfaced by test-2 B5 on first run; one-line fix, commented at the site.
- **Inverse cases encode OQ-2 in two places:** listing (test-2 B1: killed exchange helper ⇒ lab absent) and switching (test-3: dead exchange marker ⇒ launch fresh, no false raise) — the new truth is regression-locked from both consumer directions.
- **test-4 hermetic STATE from §4:** with cmd_trunk now scanning `$STATE/run`, the pre-existing sections 4-9 would have read (and lazily reaped dead markers in) the operator's real state dir mid-suite; redirected to a tempdir at the stubbing point.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `_running_labs` leaked a non-zero status under pipefail, breaking the active cross-check**
- **Found during:** Task 1 (test-2 B5 first run: on-board fixture returned the null shape)
- **Issue:** The plan's verified draft ends with `[ "$saw_exchange" = 1 ] && printf 'exchange\n'` — return 1 when no exchange marker exists. Under `set -o pipefail`, `_running_labs | grep -qxF -- "$lab"` evaluated false even when grep matched, so `cmd_active` emptied a perfectly live lab.
- **Fix:** explicit `return 0` tail with a comment naming the pipefail hazard.
- **Files modified:** bin/stail
- **Verification:** test-2 B5 green; test-6 §6/§7 assert both directions of the cross-check
- **Commit:** b9db6e6

**2. [Rule 2 - Missing critical functionality] test-4 sections 4-9 would scan (and reap inside) the live state dir**
- **Found during:** Task 2 (test-4 rewrite)
- **Issue:** The plan only re-fixtures #10, but once `cmd_trunk` reads `$STATE/run`, every pre-existing `cmd_trunk` invocation in sections 4-9 scans the operator's real `~/.local/state/switchtail/run` — including the lazy reap's `rm -f` against real (dead) markers, from inside a test suite.
- **Fix:** `STATE` redirected to a tempdir at the §4 stubbing point (where `_launch_detached` is already stubbed), so the whole stubbed half of the suite is hermetic.
- **Files modified:** tests/stail-test-4.sh
- **Verification:** test-4 26 passed, 0 failed (breadth unchanged)
- **Commit:** 190aa88

---

**Total deviations:** 2 auto-fixed (1 bug, 1 missing-safety)
**Impact on plan:** None on scope or interfaces; both strengthen the planned behavior (frozen shapes hold under pipefail; the suite never mutates live operator state).

## Verification Results

- `STAIL_BIN=$PWD/bin/stail bash tests/run-all.sh` → **ALL SUITES PASSED**, 208 total passes, 0 failures in every suite (>= 160 required).
- kdotool in non-comment `bin/stail` lines appears ONLY inside `_win_ids`, `_need_kdotool`, and `cmd_switch` (audited via `grep -v '^\s*#' | grep -n kdotool`).
- Static gates: `_running_labs`/`cmd_list`/`cmd_active` bodies contain 0 non-comment kdotool references; `_aggregate_labs|_lab_in_aggregate` non-comment count = 0; `cmd_switch` body has exactly 1 `_need_kdotool switch` + 2 `windowactivate`; `cmd_trunk` body has 0 non-comment kdotool and keeps "already up"; exactly one `^_lab_in_exchange()`.
- `--json` byte-shapes locked by equality assertions: `[{"lab":"zlab","display":"Zlab","running":true}]`, `{"lab":"zlab","display":"Zlab","exchange":false}`, `{"lab":null,"display":null,"exchange":false}` with exit 0/1 (test-6 §6/§7).
- Docs gates: `grep -c 'introspect the live windows via kdotool' bin/stail` = 0; `grep -c 'greps that class for running detection' CLAUDE.md` = 0; `grep -q 'run/<lab>' CLAUDE.md` passes.

## Known Stubs

None — no placeholder values, empty data sources, or unwired components were introduced; every reader consumes the live marker/active files.

## Threat Flags

None — no new security surface beyond the plan's threat model; all four `mitigate` dispositions are implemented and regression-locked (T-01-R1 test-6 §5, T-01-R2 charset gate + byte-shape asserts, T-01-R3 test-6 §7, T-01-R4 dead-helper cases in test-2/test-3).

## Issues Encountered

None beyond the documented deviations. Note for deploy (plan 01-05, unchanged from 01-03's reminder): pre-seam boards already running wrote no markers and now read as DOWN until relaunched — the deployed `~/.local/bin/stail` is a symlink into this checkout, so this reader flip is live on the daily driver as of these commits; `$STATE/active` stays empty (off-board, the correct degraded mode) until state.py is deployed and boards relaunch.

## User Setup Required

None for this plan (the 01-05 deploy plan covers state.py symlinks, kitty.conf include, regen, and board relaunch).

## Next Phase Readiness

- SEAM-01 and SEAM-02 are complete in code: detection is kdotool-free (provably — the §6 consult log), raise is kdotool-only, docs match the implementation.
- Plan 01-05 (deploy + live verification) has its precondition: a green 208-assertion suite against this tree and the documented deploy order (symlink state.py/state.conf → include → generate → relaunch boards).

## Self-Check: PASSED

- bin/stail — FOUND, contains `_lab_in_exchange`
- tests/stail-test-2.sh — FOUND
- tests/stail-test-3.sh — FOUND
- tests/stail-test-4.sh — FOUND
- tests/stail-test-6.sh — FOUND
- CLAUDE.md — FOUND, contains `run/<lab>`
- Commit b9db6e6 — FOUND
- Commit 190aa88 — FOUND
- Commit 96b22d5 — FOUND

---
*Phase: 01-running-state-seam*
*Completed: 2026-06-12*
