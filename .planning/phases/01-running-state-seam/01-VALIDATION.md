---
phase: 1
slug: running-state-seam
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-12
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

- **After every task commit:** Run `bash tests/stail-test-6.sh && bash tests/stail-test-2.sh`
- **After every plan wave:** Run `bash tests/run-all.sh` (with `STAIL_BIN` pointed at the edited tree — see RESEARCH.md Pitfall 1)
- **Before `/gsd-verify-work`:** Full suite green against the LIVE deployed path after merge
- **Max feedback latency:** ~60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| *(filled by planner — map below is the requirement-level contract from RESEARCH.md)* | | | | | | | | | |
| — | — | — | SEAM-01 | — | `list`/`list --json` running flags derive from run markers (live PID fixtures); valid JSON; display names intact | unit (state fixtures) | `bash tests/stail-test-6.sh` | ❌ W0 | ⬜ pending |
| — | — | — | SEAM-01 | — | `active`/`active --json` derive from `$STATE/active` + liveness cross-check; off-board/missing ⇒ null + exit 1 | unit (state fixtures) | `bash tests/stail-test-6.sh` | ❌ W0 | ⬜ pending |
| — | — | — | SEAM-01 | — | Dead-PID markers reaped on read; start-time mismatch counts as dead | unit | `bash tests/stail-test-6.sh` | ❌ W0 | ⬜ pending |
| — | — | — | SEAM-02 | — | `cmd_list`/`cmd_active` succeed with kdotool absent; `cmd_switch` still requires it | unit | `bash tests/stail-test-6.sh` | ❌ W0 | ⬜ pending |
| — | — | — | SEAM-02 | — | trunk already-up warning keyed off state, not kdotool | unit | `bash tests/stail-test-4.sh` (rewritten #10) | ✅ needs edit | ⬜ pending |
| — | — | — | SEAM-01/02 | — | Rewritten exchange-union, switch-decision, dup-warning behavior vs new source | unit | `bash tests/stail-test-2.sh`, `tests/stail-test-3.sh` (B1–B5 / R2 rewritten) | ✅ needs edit | ⬜ pending |
| — | — | — | Criterion 4 | — | Full baseline green at ≥ prior breadth (test-6 added to run-all loop) | integration | `bash tests/run-all.sh` | ✅ add test-6 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/stail-test-6.sh` — SEAM-01/SEAM-02 state-seam assertions (marker write/reap, list/active from state, kdotool-absence proof, marker-write-failure never kills the pane)
- [ ] `STAIL_BIN` parametrization across `tests/stail-test-{1..5}.sh` + `run-all.sh` (currently hardcode `~/.local/bin/stail`) — prerequisite for honest worktree testing
- [ ] Live-smoke checklist (or `checkpoint:human-verify`) for A2/A3: relaunch one board post-deploy, verify list/active/widget against reality

*Test fixtures: isolated `STATE=/tmp/…` per test-1 §6's pattern; "live" markers use background `sleep` helper PIDs with real `/proc` start times — unique per run, no fixed sleeps for window-dependent parts.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Widget shows correct running state with zero widget changes | Criterion 3 | Plasma rendering not automatable here | Visual: panel heading + popup vs real boards; `journalctl --user -u plasma-plasmashell` clean |
| Pane-exit ⇒ marker dead; focus loss to non-kitty app clears active | A2/A3 | Needs live kitty + KWin focus events | Scripted live check on one relaunched board, or checkpoint:human-verify |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
