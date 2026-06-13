---
gsd_state_version: 1.0
milestone: v0.1
milestone_name: Switchboard Groundwork
status: milestone_complete
last_updated: "2026-06-13"
progress:
  total_phases: 4
  completed_phases: 4
---

# Project State

## Project Reference

See: .planning/PROJECT.md (created 2026-06-12, fresh-slate restart)

**Core value:** one-handed fleet control without losing the overview.
**Current focus:** v0.1 Switchboard Groundwork — autonomous build day
(owner away; directive 2026-06-12).

## Current Position

Phase: 4 of 4 — gap-closure in progress (2026-06-13 session)
Status: v0.1 Switchboard Groundwork delivered. Phase-4 UAT (2026-06-12)
found 7/9 pass + 2 major gaps (tests 4 swap, 6 ring targeting). Both gaps
diagnosed to a shared root cause and fixed in plans 04-05 + 04-06:
- 04-05 COMPLETE: selection re-anchored by stable identity (LineId /
  call seq) — ring/cursor drift fixed. 34 core tests + no-kill guard green.
- 04-06 Tasks 1-3 COMPLETE: SwapPanes composite intent (true positional
  exchange via 3-call placeholder transaction); seat follows the position;
  docs corrected. Owner blessed the placeholder close (Task 1: proceed).
  wasm builds clean. Task 4 (live human-verify) PENDING — needs operator
  in a live zellij session (`tools/dev.sh reload`, observe swap + ring).
Mode: autonomous single-session (memory-constrained box — serial builds,
CARGO_BUILD_JOBS=4, no agent fan-out, commit+push frequently)

## Accumulated Context

### Decisions

- Fresh slate executed: kitty era archived (tag `kitty-era-final`,
  `~/JangLabs/.archive/switchtail-kitty-era/` incl. RESTORE.md), live
  deployment retired, branches collapsed to `main`.
- zellij-tile pinned 0.44.3 against host zellij 0.45.0; API source-verified
  (docs/zellij-api-notes.md). Web/docs summaries were wrong on signatures —
  always verify from vendored source.
- Core/adapter split with HostIntent seam (docs/DESIGN.md).
- Vocabulary seeded as domain language per owner mid-task directive.

### Blockers/Concerns

- Context7 monthly quota exhausted (2026-06-12) — `ctx7 login` for higher
  limits; using vendored source + upstream docs instead.
- Seat swap: RESOLVED in code (04-06). `replace_pane_with_existing_pane` is
  a one-way "bring pane here" primitive (NOT a swap) — proven at host commit
  e9173cb. True positional exchange now composed as a 3-call placeholder
  transaction (SwapPanes intent). PENDING live human-verify (Task 4): FIFO
  ordering + suppressed-restore edge cannot be asserted headlessly.
- This terminal was OOM-killed once mid-run; keep builds capped and avoid
  parallel heavy processes.
- Release wasm builds (lto=true, codegen-units=1) SIGSEGV rustc on this box
  under current load (two crashes, different crates — load-related, not
  code). Deployed the debug wasm to ~/.local/share/zellij/plugins/ instead;
  retry `tools/dev.sh install` on a quiet system. Keybind Alt+s is wired in
  ~/.config/zellij/config.kdl; first launch will show zellij's one-time
  permission approval prompt.

## Session Continuity

Branch model: trunk-based on `main` (fresh project; no phase branches).
Last session: 2026-06-12 — v0.1 milestone complete. Next milestone
candidates: lifecycle layer (trunks, boards-from-carts, agent-kind table),
hold/resume markers, Claude Code hook wiring for ring/status, live-verified
seat-swap semantics, in-plugin launcher/introspector.
