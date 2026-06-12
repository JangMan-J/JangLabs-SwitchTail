---
phase: 1
slug: running-state-seam
status: planned
nyquist_compliant: true
wave_0_complete: false
created: 2026-06-12
planned: 2026-06-12
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hand-rolled bash assertion scripts (ok/no counters) + python3 scripts, orchestrated by `tests/run-all.sh` |
| **Config file** | none — scripts are self-contained; they source REAL stail functions with the dispatch tail stripped and stub `kdotool`/`_launch_detached` |
| **Quick run command** | `bash tests/stail-test-6.sh && bash tests/stail-test-2.sh` |
| **Full suite command** | `bash tests/run-all.sh` (147-assertion baseline; all suites must report 0 failures) |
| **Estimated runtime** | ~10s quick / ~60s full |

---

## Sampling Rate

- **After every task commit:** Run `STAIL_BIN=$PWD/bin/stail bash tests/stail-test-6.sh && STAIL_BIN=$PWD/bin/stail bash tests/stail-test-2.sh` (test-6 exists from 01-03-T3 onward)
- **After every plan wave:** Run `STAIL_BIN=$PWD/bin/stail bash tests/run-all.sh` (pointed at the edited tree — RESEARCH.md Pitfall 1)
- **Before `/gsd-verify-work`:** Full suite green against the LIVE deployed path after merge (no STAIL_BIN — 01-05-T1)
- **Max feedback latency:** ~60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 01-01-T1 | 01-01 | 1 | SEAM-01/02 (harness prereq, OQ-4) | — | suite honestly tests the edited tree via STAIL_BIN | meta/regression | `bash tests/stail-test-{1..5}.sh` (default + override + bogus-path modes) | ✅ edit | ⬜ pending |
| 01-01-T2 | 01-01 | 1 | SEAM-01/02 (harness prereq) | — | run-all surfaces the stail under test | meta | `bash tests/run-all.sh` (both modes) | ✅ edit | ⬜ pending |
| 01-02-T1 | 01-02 | 1 | SEAM-01 (active source) | T-01-W1/W2/W3 | watcher is filesystem-only; charset fullmatch; blanket exception guard | static | `python3 -c "import ast; ast.parse(...)"` + grep gates (no send_text/close/destroy) | NEW kitty/state.py | ⬜ pending |
| 01-02-T2 | 01-02 | 1 | SEAM-01 (active source) | T-01-W1/W3 | gain/loss/compare-and-clear/junk-board/exception paths | unit (kitty-stubbed) | `python3 tests/state-test.py` | NEW tests/state-test.py | ⬜ pending |
| 01-03-T1 | 01-03 | 2 | SEAM-01 (marker write/liveness) | T-01-M2/M3/M4 | comm-safe start parse both sides; never-fail write discipline | static | `bash -n bin/stail` + grep gates | — | ⬜ pending |
| 01-03-T2 | 01-03 | 2 | SEAM-01 (board identity, OQ-3 all kinds) | T-01-M1/M3 | marker pre-exec for every kind; unwritable STATE never kills the pane | e2e | `XDG_STATE_HOME=<tmp> bash bin/stail line zlab /tmp 'cmd:true' zboard` + emitter fixture grep | — | ⬜ pending |
| 01-03-T3 | 01-03 | 2 | SEAM-01 | T-01-M2/M3 | marker write/liveness/reap-eligibility/never-fail regression-locked | unit (state fixtures) | `STAIL_BIN=$PWD/bin/stail bash tests/stail-test-6.sh` | NEW tests/stail-test-6.sh (Wave 0 item) | ⬜ pending |
| 01-04-T1 | 01-04 | 3 | SEAM-01, SEAM-02 | T-01-R1/R2/R3/R4 | list/active from state; kdotool-consult log provably empty; charset gates; reap; staleness cross-check; NEW exchange truth (OQ-2) | unit | `STAIL_BIN=$PWD/bin/stail bash tests/stail-test-2.sh && STAIL_BIN=$PWD/bin/stail bash tests/stail-test-6.sh` | ✅ edit (test-2) + extend (test-6) | ⬜ pending |
| 01-04-T2 | 01-04 | 3 | SEAM-02 | T-01-R1/R4 | trunk warning + switch exchange decision from markers; raise stays kdotool; dead grep helpers deleted | unit | `STAIL_BIN=$PWD/bin/stail bash tests/stail-test-3.sh && STAIL_BIN=$PWD/bin/stail bash tests/stail-test-4.sh` | ✅ edit | ⬜ pending |
| 01-04-T3 | 01-04 | 3 | Criterion 4 (breadth) | — | full baseline + state-seam assertions green, >= 160 total passes | integration | `STAIL_BIN=$PWD/bin/stail bash tests/run-all.sh` | ✅ (test-6 + state-test in loop) | ⬜ pending |
| 01-05-T1 | 01-05 | 4 | SEAM-01/02 + Criterion 4 (live) | T-01-D1/D3 | merge-gated deploy; relative symlinks; single include; board-stamped regen; live-path suite green | integration | `bash tests/run-all.sh` (no STAIL_BIN) + readlink/grep gates | — | ⬜ pending |
| 01-05-T2 | 01-05 | 4 | Criterion 3 + A2/A3 | T-01-D2 | widget zero-change; focus gain/loss; pane-exit reap; clean plasmashell journal | manual (checkpoint:human-verify) | — (justified: Plasma rendering / KWin focus / live pane exit not automatable) | — | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `STAIL_BIN` parametrization across `tests/stail-test-{1..5}.sh` + `run-all.sh` → **01-01 (wave 1)** — prerequisite for honest worktree testing
- [ ] `tests/stail-test-6.sh` — SEAM-01/SEAM-02 state-seam assertions → created writer-side in **01-03-T3 (wave 2)**, extended reader-side in **01-04-T1 (wave 3)**; each lands in the same plan as the code it asserts, so no plan ends red
- [ ] Live-smoke checklist for A2/A3 → **01-05-T2** `checkpoint:human-verify`

*Test fixtures: isolated `STATE=/tmp/…` per test-1 §6's pattern; "live" markers use background `sleep` helper PIDs with real `/proc` start times — unique per run, no fixed sleeps for window-dependent parts.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Widget shows correct running state with zero widget changes | Criterion 3 | Plasma rendering not automatable here | 01-05-T2 steps 6: panel heading + popup vs real boards; `journalctl --user -u plasma-plasmashell` clean |
| Pane-exit ⇒ marker dead; focus loss to non-kitty app clears active | A2/A3 | Needs live kitty + KWin focus events | 01-05-T2 steps 1-5 on one relaunched board |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies (01-05-T2's manual-only status is justified above)
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (test-6 created before/with its first asserting code; STAIL_BIN lands in wave 1)
- [x] No watch-mode flags
- [x] Feedback latency < 60s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** planner sign-off 2026-06-12 (execution statuses to be filled by execute-phase)
