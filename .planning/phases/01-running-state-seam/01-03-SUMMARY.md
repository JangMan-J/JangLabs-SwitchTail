---
phase: 01-running-state-seam
plan: 03
subsystem: cli-state
tags: [bash, stail, run-markers, proc, state-seam]

# Dependency graph
requires:
  - "01-01: STAIL_BIN-parametrized harness (suite honestly tests this checkout)"
  - "01-02: tests/state-test.py (wired into run-all.sh by this plan — single-owner rule)"
provides:
  - "_run_mark + _pane_alive helpers with the run-marker 2-way contract banner in bin/stail"
  - "$STATE/run/<lab>/<pid> marker written pre-exec by stail line for EVERY pane kind (claude, shell, cmd:)"
  - "board identity stamped once in _emit_session: --var board= + stail line 4th argv on every launch line"
  - "tests/stail-test-6.sh writer-side state-seam suite (18 assertions)"
  - "run-all.sh running 9 suites (6 bash + 3 python), 193 total passes"
affects: [01-04, 01-05]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "PID-named run markers: filename = writer PID (single-writer by construction), tmp + mv -f atomic write"
    - "comm-safe /proc stat parse: rest=\"${stat##*) }\" then awk field 20 — identical on write and read sides"
    - "never-fail pre-exec discipline: || return 0 on every fallible step, unconditional return 0 tail"

key-files:
  created:
    - tests/stail-test-6.sh
  modified:
    - bin/stail
    - tests/run-all.sh
    - tests/stail-test-4.sh
    - tests/stail-test-5.sh

key-decisions:
  - "Run marker written ONCE pre-dispatch in cmd_line with sid= empty (not per-branch after sid resolution): minimizes new code between the cd guard and exec, and no Phase-1 reader consumes sid (contract declares sid informational/optional)"
  - "4 pre-existing launch-line shape assertions in test-4/test-5 updated to the board-stamped shape (Rule 3): tag adjacency and line-end anchors broke by design; behavioral intent preserved and strengthened (board var now asserted too)"

patterns-established:
  - "run-marker contract: $STATE/run/<lab>/<pid> with start=/board=/kind=/sid= lines; live iff /proc/<pid>/stat exists AND start matches; readers rm -f dead markers (lazy reap)"
  - "board transport: derived once from $cls in the single emitter, carried by --var board= (for watchers) + 4th argv (for cmd_line)"

requirements-completed: [SEAM-01]

# Metrics
duration: 8min
completed: 2026-06-12
---

# Phase 01 Plan 03: Run-Marker Write Side Summary

**PID-keyed run markers with a /proc start-time PID-reuse guard, written pre-exec by stail line for every pane kind, with board identity stamped once by the single session emitter — writers only, no reader touched, live system behavior unchanged**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-06-12T08:57:29Z
- **Completed:** 2026-06-12T09:05:00Z
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments

- `bin/stail` gained the run-marker shared section (banner documents the new 2-way contract in hold-banner prose style): `_run_mark` writes `$STATE/run/<lab>/<pid>` atomically (tmp + `mv -f`) with `start=`/`board=`/`kind=`/`sid=` content lines and returns 0 unconditionally; `_pane_alive` decides liveness by `/proc/<pid>/stat` existence + start-time equality (PID-reuse guard). Both sides use the identical comm-safe stat parse (`${stat##*) }` then field 20 — never `awk '{print $22}'` on the raw line).
- `_emit_session` derives `board="${cls#switchtail-}"` once and stamps every launch line with `--var board=` plus the board as `stail line`'s 4th argv — every session shape (per-lab file, exchange, transient trunk, transient patch) inherits it through the single emitter.
- `cmd_line` defaults `board="${4:-$lab}"` (pre-regen 3-arg session files keep working), re-validates the charset with degrade-to-lab fallback, and calls `_run_mark` at ONE pre-dispatch call site so claude, shell, AND cmd: panes all write markers (OQ-3: parity with class-based counting). All three usage surfaces advertise `stail line <lab> [dir] [kind] [board]`.
- Never-fail proven e2e: `stail line` with an unwritable state dir still boots the pane (exit 0) — a marker failure degrades listing, never kills an agent pane (threat T-01-M3).
- `tests/stail-test-6.sh`: 18 writer-side assertions (marker write atomicity/content/own-PID filename, liveness + PID-reuse guard via live `sleep` helper PIDs with real /proc start times, never-fail under chmod-555 STATE, full `stail line` e2e lifecycle ending reap-eligible). Uses a unique `/tmp/stail-fns6.sh` copy and isolated STATE tempdirs.
- `run-all.sh` now runs 9 suites: stail-test-6.sh added to the bash loop, state-test.py (from plan 01-02) added beside the other python suites. Full suite: **193 passed, 0 failed** (baseline 164 + 18 test-6 + 11 state-test).

## Task Commits

Each task was committed atomically:

1. **Task 1: _run_mark + _pane_alive helpers with the run-marker contract banner** - `87c7801` (feat)
2. **Task 2: Board stamping in _emit_session + marker write in cmd_line** - `a6a5139` (feat)
3. **Task 3: tests/stail-test-6.sh (writer-side sections) + run-all.sh wiring** - `07f4986` (test)

## Files Created/Modified

- `bin/stail` - new run-marker shared section (banner + `_run_mark` + `_pane_alive`); `_emit_session` board derivation + launch-line extension; `cmd_line` board default/validation + single pre-dispatch `_run_mark` call; 3 usage surfaces updated. NO reader changed (`_running_labs`, `cmd_list`, `cmd_active`, `cmd_trunk`, `cmd_switch` byte-identical — plan 01-04's territory).
- `tests/stail-test-6.sh` - NEW writer-side state-seam suite, 18 assertions, house harness with unique fns copy
- `tests/run-all.sh` - suite loop includes stail-test-6.sh; state-test.py invocation added
- `tests/stail-test-4.sh` - §1 hold-tags assertion updated to the board-stamped adjacency (deviation, see below)
- `tests/stail-test-5.sh` - §5 pane-shape + shell/cmd line-end assertions updated to the board-stamped shape (deviation, see below)

## Decisions Made

- **Marker written pre-dispatch with `sid=` empty** (documented in a code comment at the call site): a per-branch write after sid resolution would put more fallible code between the cd guard and the exec (Pitfall 2 territory) for zero Phase-1 benefit — no reader consumes sid, and the Task-1 contract banner declares it optional.
- **Compatibility note (no code):** old 3-arg session files default board to lab; new 4-arg files are harmless to a pre-seam stail (a 4th argv is simply ignored) — regen order at deploy is not load-bearing.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] 4 launch-line shape assertions in test-4/test-5 updated to the new emitter shape**
- **Found during:** Task 2 (full-suite gate)
- **Issue:** The plan asserted "existing 147 assertions untouched by the writer-only changes", but 4 existing assertions hardcode the OLD launch-line shape: test-4 §1 greps the adjacency `--var lab=synapse --var kind=claude` (board now sits between), test-5 §5 greps the same adjacency plus flags, and test-5 §9's shell/cmd assertions anchor the line END at `"shell"$` / `"cmd:git status"$` (the board argv now follows). All four fail by design once the emitter stamps board.
- **Fix:** Updated each assertion to the new shape, preserving and strengthening the behavioral intent — the adjacency greps now also assert `--var board=<class-derived>` (synapse for the trunk emit, multi for the patch emit), and the line-end anchors assert the trailing board argv (`"shell" multi$`, `"cmd:git status" multi$`).
- **Files modified:** tests/stail-test-4.sh, tests/stail-test-5.sh
- **Verification:** `STAIL_BIN=$PWD/bin/stail bash tests/run-all.sh` → ALL SUITES PASSED, breadth preserved (164 pre-existing assertions still reported, 0 failed)
- **Committed in:** a6a5139 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Required for the plan's own "ALL SUITES PASSED" gate; assertion breadth unchanged, coverage strengthened. Note for plan 01-04: these 4 assertions are in files 01-04 also rewrites — no conflict, the edits are in different sections than 01-04's B1-B5/R2/#10 targets (except test-4, where only §1 line 24 was touched, not #10).

## Verification Results

- `STAIL_BIN=$PWD/bin/stail bash tests/run-all.sh` → **ALL SUITES PASSED**, 193 total passes, 0 failures anywhere (>= 157 required): test-1 25, test-2 14, test-3 15, test-4 26, test-5 39, test-6 18, kitten 27, tail 18, state 11.
- E2E: `stail line zlab /tmp 'cmd:true' zboard` exits 0 and leaves exactly one marker with numeric-PID filename, numeric `start=`, `board=zboard`, `kind=cmd:true`, `sid=` lines; with a read-only XDG_STATE_HOME the pane still boots (exit 0).
- Emitter fixture: launch line carries `--var board=zlab` and ends `stail line zlab "/tmp" "claude" zlab`.
- `git diff 54b03e8..HEAD -- bin/stail` hunks touch only the header comment, usage() heredoc, the new shared section, `_emit_session`, and `cmd_line` — no reader function modified.
- Static gates: `bash -n` clean; exactly one `_run_mark()` and one `_pane_alive()`; zero non-comment `print $22`; >= 3 `return 0` in `_run_mark`; >= 2 comm-strip parses.

## Known Stubs

None — markers are written but deliberately not yet consumed (readers move in plan 01-04, per the plan's objective); detection still runs on the kdotool path, so the live system's behavior is unchanged.

## Issues Encountered

None beyond the documented deviation. Note: test-1 §1 runs a real `stail generate` against the live OUTDIR, so the deployed session files now carry the board-stamped 4-arg launch lines — harmless per the compatibility note (the deployed `~/.local/bin/stail` is a symlink into this checkout and already understands the 4th argv; a pre-seam stail would ignore it).

## User Setup Required

None.

## Next Phase Readiness

- Plan 01-04 (readers) has everything it needs: `_run_mark`/`_pane_alive` in place, markers carrying `board=` for the exchange-union rewrite, test-6 ready for reader-side sections, run-all.sh already running 9 suites.
- Reminder for 01-05 deploy: pre-seam boards already running have no markers and will read as DOWN until relaunched (RESEARCH.md Runtime State Inventory) — unchanged by this plan since no reader consumes markers yet.

## Self-Check: PASSED

- bin/stail — FOUND, contains `_run_mark`
- tests/stail-test-6.sh — FOUND
- tests/run-all.sh — FOUND, contains stail-test-6.sh + state-test.py
- Commit 87c7801 — FOUND
- Commit a6a5139 — FOUND
- Commit 07f4986 — FOUND

---
*Phase: 01-running-state-seam*
*Completed: 2026-06-12*
