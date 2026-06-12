---
phase: 01-running-state-seam
plan: 05
subsystem: deployment
tags: [deploy, kitty, symlinks, kitty-conf, sessions, live-verification, plasma-widget]

# Dependency graph
requires:
  - "01-02: kitty/state.py + state.conf (the watcher files this plan symlinks live)"
  - "01-03: _emit_session board stamping (what `stail generate` writes into session files)"
  - "01-04: reader flip + 208-assertion suite green (the merge-gate precondition)"
provides:
  - "~/.config/kitty/state.py -> ../../JangLabs/switchtail/kitty/state.py (live relative symlink)"
  - "~/.config/kitty/state.conf -> ../../JangLabs/switchtail/kitty/state.conf (live relative symlink)"
  - "`include state.conf` in ~/.config/kitty/kitty.conf (single line, adjacent to include tail.conf)"
  - "regenerated ~/.config/kitty/sessions/labs/*.kitty-session, every launch line board-stamped"
  - "live-path suite green: 208 passes, 0 failures, no STAIL_BIN override"
  - "operator-verified live semantics: A2 (pane-exit reap), A3 (focus gain/loss), widget zero-change, raise path intact"
affects: [phase-02]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "deploy order per RESEARCH Pitfall 5: symlinks -> kitty.conf include -> stail generate -> operator relaunch"
    - "merge gate before deploy: grep the live symlink target for the phase symbol (_run_mark) before touching live config"

key-files:
  created: []
  modified:
    - .planning/STATE.md
decisions: []

requirements-completed: [SEAM-01, SEAM-02]

# Metrics
duration: 22min (incl. checkpoint wait; ~5min active)
completed: 2026-06-12
---

# Phase 01 Plan 05: Live Deploy + Human Verification Summary

**Seam deployed to the daily driver — state.py/state.conf live via relative symlinks + one kitty.conf include, sessions regenerated board-stamped, full suite green at 208 on the live path with no STAIL_BIN, and the operator verified all live semantics (relaunch, list truth, active gain/loss, pane-exit reap, widget zero-change, raise) — phase complete**

## Performance

- **Duration:** ~22 min wall clock (deploy ~5 min; remainder was the human-verify checkpoint wait)
- **Started:** 2026-06-12T09:22:55Z
- **Completed:** 2026-06-12T09:45:18Z
- **Tasks:** 2 (1 auto + 1 human-verify checkpoint)
- **Files modified:** 4 live-config surfaces outside the repo + .planning/STATE.md in-repo

## Accomplishments

- **Merge gate passed before any deploy step (T-01-D1):** `grep -c '_run_mark' "$HOME/.local/bin/stail"` = 4 — the live symlink target (this checkout, phase branch on the main working tree) already carried the full seam, so the widget never polled a broken intermediate state.
- **Watcher wired live in the exact tail.py form (T-01-D3):** `~/.config/kitty/state.py -> ../../JangLabs/switchtail/kitty/state.py` and `~/.config/kitty/state.conf -> ../../JangLabs/switchtail/kitty/state.conf`, RELATIVE links created from inside `~/.config/kitty/`, byte-identical in form to the verified tail.py/tail.conf precedent (CLAUDE.md runtime placement rules).
- **Single include line:** `include state.conf` added to `~/.config/kitty/kitty.conf` directly under `include tail.conf` (line 3210); `grep -c '^include state.conf'` = 1 — present, not duplicated, nothing else touched in the daily driver's config.
- **Sessions regenerated board-stamped:** `$HOME/.local/bin/stail generate` (absolute path per PATH discipline) rewrote 5 lab session files + the exchange file; `grep -L -- '--var board='` over `~/.config/kitty/sessions/labs/*.kitty-session` returns nothing (0 unstamped files of 6).
- **Live-path suite green (criterion 4):** `bash tests/run-all.sh` with NO STAIL_BIN override — **ALL SUITES PASSED, 208 total passes, 0 failures** (test-1 25, test-2 16, test-3 16, test-4 26, test-5 39, test-6 30, kitten 27, tail 18, state 11; ≥160 required).
- **Operator verified the live halves (Task 2 checkpoint, "approved" 2026-06-12):** all seven steps held — see Checkpoint Verification below. Assumptions A2/A3 discharged; roadmap criteria 1–4 all met; phase complete.

## Task Commits

1. **Task 1: Merge-gate, deploy wiring, regen, live suite** - `ff90cf1` (docs — STATE.md checkpoint-position marker; the deploy itself modifies only live config outside this repo, so there is no code diff to commit)
2. **Task 2: Live verification checkpoint** - no commit (human verification, no file edits by design)

## Files Created/Modified

All deploy surfaces live outside the repo (the repo files state.py/state.conf landed in plan 01-02):

- `~/.config/kitty/state.py` - NEW relative symlink into this repo (watcher now loads into every newly launched kitty board)
- `~/.config/kitty/state.conf` - NEW relative symlink into this repo (`watcher state.py` registration)
- `~/.config/kitty/kitty.conf` - one line added: `include state.conf` (adjacent to `include tail.conf`)
- `~/.config/kitty/sessions/labs/*.kitty-session` - regenerated (6 files), every launch line carries `--var board=` + the board 4th argv
- `.planning/STATE.md` - checkpoint position marker (ff90cf1)

## Checkpoint Verification (operator-approved)

The Task 2 `checkpoint:human-verify` gate was returned with full instructions; the operator performed the pass and replied **"approved"** — all of steps 2–7 observed as described:

| Step | Check | Discharges | Result |
|------|-------|------------|--------|
| 1 | One-time relaunch of pre-seam boards (no markers/watcher until relaunch — RESEARCH Runtime State Inventory) | deploy precondition | done |
| 2 | `stail list` / `--json` match reality exactly (relaunched boards running, closed boards `-`/false) | SEAM-01 live | held |
| 3 | Focus board → `stail active --json` names it, exit 0 | A3 gain | held |
| 4 | Focus non-kitty window → `stail active` empty/exit 1, `--json` null shape | A3 loss | held |
| 5 | Pane exit → lab reads down on next `stail list` (marker reaped on read) | A2 | held |
| 6 | Plasma panel heading + popup flags correct with ZERO widget changes; plasmashell journal clean | roadmap criterion 3 | held |
| 7 | `stail switch <lab>` still raises the running board via kdotool | SEAM-02 raise path | held |

No mismatches, no panes dying at boot — none of the blocker conditions occurred.

## Decisions Made

None — the deploy followed the plan's prescribed order (Pitfall 5: symlinks → include → regen → operator relaunch) exactly.

## Deviations from Plan

None - plan executed exactly as written. (The merge-gate's "integrate into versioning" contingency never fired: the main checkout sits on the phase branch, so the live symlink target already carried `_run_mark`.)

## Known Stubs

None — the deploy wired the real watcher and the real regenerated sessions; nothing is placeholder.

## Threat Flags

None — all three `mitigate` dispositions in the plan's threat model were executed: T-01-D1 (merge gate before deploy, single idempotent include line), T-01-D2 (watcher exception-guarded and unit-proven pre-deploy; operator confirmed zero boot-time pane deaths), T-01-D3 (exact relative readlink targets asserted). No new security surface.

## Issues Encountered

None. The reader-flip gap noted in 01-04 (live `stail list` reading DOWN for pre-seam boards, `active` empty) closed as designed: the deploy plus the operator's one-time relaunch restored full truth.

## User Setup Required

None remaining — the one-time board relaunch was performed as checkpoint step 1.

## Next Phase Readiness

- Phase 01 is complete: SEAM-01 and SEAM-02 delivered end-to-end (code in 01-02..01-04, live deployment + verification here); roadmap success criteria 1–4 all verified.
- The running-state seam is mux-agnostic by construction: Zellij panes in Phase 3 can run the same `stail line` and write the same `$STATE/run` markers — exactly the foundation the ingest prescribed before any Zellij work.
- New verification-gate baseline for future phases: 208 assertions, green on the live path.

## Self-Check: PASSED

- ~/.config/kitty/state.py — FOUND (symlink, correct relative target)
- ~/.config/kitty/state.conf — FOUND (symlink, correct relative target)
- `include state.conf` in kitty.conf — FOUND (count = 1)
- Unstamped session files — 0
- Commit ff90cf1 — FOUND

---
*Phase: 01-running-state-seam*
*Completed: 2026-06-12*
