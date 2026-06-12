---
phase: 01-running-state-seam
plan: 01
subsystem: testing
tags: [bash, regression-suite, test-harness, stail]

# Dependency graph
requires: []
provides:
  - STAIL_BIN-parametrized regression harness (all five bash suites + run-all.sh)
  - "stail under test:" diagnostic line in every run-all.sh log (Pitfall-1 visibility)
  - cp guard that makes a bogus STAIL_BIN fail loudly instead of sourcing a stale /tmp copy
affects: [01-02, 01-03, 01-04, 01-05]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "STAIL_BIN=${STAIL_BIN:-$HOME/.local/bin/stail} shell-parameter default for dev-vs-live suite targeting"

key-files:
  created: []
  modified:
    - tests/stail-test-1.sh
    - tests/stail-test-2.sh
    - tests/stail-test-3.sh
    - tests/stail-test-4.sh
    - tests/stail-test-5.sh
    - tests/run-all.sh

key-decisions:
  - "Guarded the cp of the stail-under-test with a FATAL exit so a bogus STAIL_BIN cannot silently source a stale /tmp/stail-fns.sh (Rule 2)"
  - "Pre-existing workspace-drift test failures (labs claude/jangsjedi renamed/removed 2026-06-11) logged to deferred-items.md, NOT fixed — out of scope per executor scope boundary and the plan's 'mechanical substitution ONLY' directive"

patterns-established:
  - "STAIL_BIN: every suite sources and invokes stail exclusively through $STAIL_BIN; default preserves deployed-symlink behavior"

requirements-completed: [SEAM-01, SEAM-02]

# Metrics
duration: 13min
completed: 2026-06-12
---

# Phase 01 Plan 01: STAIL_BIN Harness Parametrization Summary

**All five bash regression suites plus run-all.sh now target the stail named by STAIL_BIN (default: deployed ~/.local/bin/stail), with a fail-loud cp guard and a per-run "stail under test:" diagnostic line**

## Performance

- **Duration:** ~13 min
- **Started:** 2026-06-12T08:34:33Z
- **Completed:** 2026-06-12T08:47:00Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- The suite can honestly test an edited checkout (`STAIL_BIN=$PWD/bin/stail bash tests/run-all.sh`) instead of silently re-testing the deployed live symlink (RESEARCH.md Pitfall 1) — the Wave-0 prerequisite for plans 01-03/01-04.
- Default invocation is behavior-identical: with STAIL_BIN unset, every suite reports byte-identical pass/fail counts to the pre-edit baseline.
- A bogus override fails loudly: `STAIL_BIN=/nonexistent bash tests/stail-test-2.sh` exits 1 with `FATAL: cannot copy stail under test: /nonexistent`.
- run-all.sh documents the override in its header and echoes `stail under test: <path>` at the top of every suite log.

## Task Commits

Each task was committed atomically:

1. **Task 1: Parametrize STAIL_BIN across the five bash suites** - `a0a965e` (test)
2. **Task 2: run-all.sh documents and surfaces the stail under test** - `76468ee` (test)

## Files Created/Modified

- `tests/stail-test-1.sh` - STAIL_BIN param + cp guard; `stail()` wrapper and direct `generate` invocation routed through `$STAIL_BIN`; header comment updated
- `tests/stail-test-2.sh` - STAIL_BIN param + guarded cp source
- `tests/stail-test-3.sh` - STAIL_BIN param + guarded cp; direct `switch`/`line` end-to-end invocations routed through `$STAIL_BIN`
- `tests/stail-test-4.sh` - STAIL_BIN param + guarded cp source
- `tests/stail-test-5.sh` - STAIL_BIN param + guarded cp; `sh -c` round-trip string uses `$STAIL_BIN` (path space-free; `/tmp/t5bin` PATH-prepend stub still works)
- `tests/run-all.sh` - header documents the override; diagnostic echo added; suite loop untouched

## Decisions Made

- Added a `|| { echo FATAL...; exit 1; }` guard on every `cp "$STAIL_BIN" /tmp/stail-fns.sh`. Without it, a failed cp leaves a stale `/tmp/stail-fns.sh` from a prior run to be sourced silently — exactly the dishonest-verification failure mode this plan exists to eliminate, and the acceptance criterion "a bogus override makes the suite fail" would only hold on a freshly booted /tmp.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Fail-loud guard on the stail-under-test copy**
- **Found during:** Task 1 (STAIL_BIN parametrization)
- **Issue:** With `set -uo pipefail` (no `-e`), a failed `cp "$STAIL_BIN" ...` does not stop the suite; it then sources whatever stale `/tmp/stail-fns.sh` a previous run left behind, silently testing the wrong binary — defeating the parameter and making the bogus-override acceptance check nondeterministic.
- **Fix:** `cp "$STAIL_BIN" /tmp/stail-fns.sh || { echo "FATAL: cannot copy stail under test: $STAIL_BIN" >&2; exit 1; }` in all five suites. No assertion/fixture changes.
- **Files modified:** tests/stail-test-{1..5}.sh
- **Verification:** `STAIL_BIN=/nonexistent bash tests/stail-test-2.sh` → exit 1 with the FATAL line, even with a stale /tmp copy present.
- **Committed in:** a0a965e (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 missing critical)
**Impact on plan:** Necessary for the parameter to be trustworthy; no scope creep.

## Issues Encountered

**Pre-existing baseline is RED (workspace drift — NOT caused by this plan).** While recording the pre-edit baseline, the suites showed 35 pre-existing failures: the fixtures hardcode the labs `claude` and `jangsjedi`, but the live workspace changed on 2026-06-11 (`claude` lab renamed to `synapse`; `jangsjedi` removed). Current `_discover_labs`: `agent jangsjyro proton switchtail synapse`.

- Baseline (identical before and after this plan's edits, in both default and override modes):
  - stail-test-1.sh: 24 passed, 1 failed
  - stail-test-2.sh: 13 passed, 3 failed
  - stail-test-3.sh: 15 passed, 0 failed
  - stail-test-4.sh: 18 passed, 8 failed
  - stail-test-5.sh: 16 passed, 23 failed
  - stail-kitten-test.py: 27 passed, 0 failed
  - tail-test.py: 18 passed, 0 failed
- Consequence: the plan's "ALL SUITES PASSED / 147-assertion baseline green" verification gate is unattainable for ANY plan until the fixtures are re-pointed at the current lab set. This plan's operative criterion — counts unchanged pre/post edit in both modes — is verified and holds exactly.
- Handling: logged with full analysis to `.planning/phases/01-running-state-seam/deferred-items.md` (kind-vs-lab distinction noted: `kind=claude` rows are still valid — only `lab=` names drifted); recorded as a STATE.md blocker. Fixing fixtures was out of scope (executor scope boundary; plan action text says "Mechanical substitution ONLY — no assertion, fixture, or behavior changes").

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- STAIL_BIN seam is in place: plans 01-02..01-05 can verify edits against the checkout (`STAIL_BIN=$PWD/bin/stail`) honestly.
- **Blocker for 01-03/01-04 verification gates:** the pre-existing lab-rename fixture drift (35 failures) must be resolved — by a fixture-refresh task before or within 01-03's test work — for any "suite green" gate to be meaningful. See deferred-items.md.
- Note: `~/.local/bin/stail` is currently a relative symlink INTO this checkout (`../../JangLabs/switchtail/bin/stail`), so default and `STAIL_BIN=$PWD/bin/stail` modes presently resolve to the same file; the seam matters once work happens on a branch/worktree whose bin/stail differs from the deployed target.

## Self-Check: PASSED

- tests/stail-test-1.sh — FOUND, contains STAIL_BIN
- tests/stail-test-5.sh — FOUND, contains STAIL_BIN
- tests/run-all.sh — FOUND, contains STAIL_BIN
- Commit a0a965e — FOUND
- Commit 76468ee — FOUND

---
*Phase: 01-running-state-seam*
*Completed: 2026-06-12*
