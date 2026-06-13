---
gsd_state_version: 1.0
milestone: v0.2
milestone_name: Composing the Exchange
status: planning
last_updated: "2026-06-13T13:47:11.143Z"
last_activity: 2026-06-13
progress:
  total_phases: 3
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (created 2026-06-12, fresh-slate restart)

**Core value:** one-handed fleet control without losing the overview.
**Current focus:** v0.2 Composing the Exchange — roadmap set (3 phases,
numbering reset to 1). Next: plan Phase 1.

## Current Position

Phase: 1 — Composition Core + Single-Line Spawn (not started)
Plan: —
Status: Roadmap created; ready to plan Phase 1
Last activity: 2026-06-13 — v0.2 roadmap created (Phases 1–3, numbering reset)

Progress: [..........................] 0% (0/3 phases)

## v0.2 Phase Map

| Phase | Goal | Requirements |
|-------|------|--------------|
| 1. Composition Core + Single-Line Spawn | Press a verb → one `claude` line on the current board; mid-bind grammar visible/abortable; exit-127 surfaced no-kill | COMP-01, 02, 06, 07, 08, 10 |
| 2. Board Spawn | Press a verb → one new board carrying one default-agent line, via native `open_command_pane_in_new_tab` | COMP-04 |
| 3. Multi-Spawn (N>1) + Deck-Cap Guardrail | Verb + digit 1–9 → N lines or N boards; deck-cap warning; no selection drift | COMP-03, 05, 09 |

Coverage: 10/10 v0.2 requirements mapped (each to exactly one phase).

## Accumulated Context

### Decisions

- **v0.2 declares the `RunCommands` permission** (owner decision, 2026-06-13) —
  a deliberate addition to the v0.1 minimal set. Enables native
  `open_command_pane` so composed lines can run `claude` as the default agent.
  The `open_terminal` + `write_chars` workaround was evaluated and rejected.
  Re-grant required: clear `XDG_CACHE_HOME/zellij/permissions.kdl` and the e2e
  isolated cache when the permission is added.

- **v0.2 build order = research-recommended slices**: Phase 1 (compose
  sub-state + single line, N=1, all the collision/exit-127 risk) → Phase 2
  (board spawn, orthogonal) → Phase 3 (count fan-out, async-reconciliation
  risk). Single-spawn phases carry no async race; N-spawn is layered last.

- **Compose is pure core** (mirrors the v0.1 `Prompt` sub-state): a
  `Compose`/`ComposeVerb` state in exchange.rs, gated at the TOP of `key()`
  before deck dispatch so digits 1–9 accumulate a count instead of jumping.
  Default-command resolution and the count fan-out (N intents in one returned
  Vec, NOT a batched intent) live in core; the adapter stays dumb.

- New board intent: `HostIntent::OpenBoard`; adapter arm uses
  `open_command_pane_in_new_tab` (returns `(tab_id, pane_id)`, requires the
  already-declared `ChangeApplicationState`). Verify the exact shim signature
  from vendored `zellij-tile-0.44.3` source during Phase 2 planning.

- Fresh slate executed: kitty era archived (tag `kitty-era-final`,
  `~/JangLabs/.archive/switchtail-kitty-era/` incl. RESTORE.md). v0.1 phase
  dirs archived to `.planning/milestones/v0.1-phases/`; numbering reset to 1.

- zellij-tile pinned 0.44.3 against host zellij 0.45.0; API source-verified
  (docs/zellij-api-notes.md). Web/docs summaries were wrong on signatures —
  always verify from vendored source.

- Core/adapter split with HostIntent seam (docs/DESIGN.md). One intent = one
  shim call (SwapPanes composed transaction is the sole exception).

- Vocabulary seeded as domain language per owner mid-task directive.

### Blockers/Concerns

- **Default-agent PATH risk (Phase 1)**: `claude` may not be on the spawned
  pane's PATH (Zellij #3856/#3924 — no env field on `CommandToRun`, PATH not
  guaranteed inherited). A bare `claude` can exit 127. Surface as a
  `LineExited` call-log entry; never close the pane. Document that
  `agent_command` should be an absolute path or a guaranteed-PATH wrapper.

- **Selection drift under N-spawn (Phase 3)**: N panes = N sequential
  `PaneUpdate` events, each re-ingesting/re-ranking. Selection is already
  identity-anchored (`selected_line_id`) from v0.1 — confirm no regression with
  a `spawn_n_panes_selection_does_not_drift` test.

- Release wasm builds (lto=true) SIGSEGV rustc on this box under load — deploy
  the DEBUG wasm via `tools/dev.sh reload`; never `cargo build --release` here.
  Build only via tools/dev.sh (CARGO_BUILD_JOBS=4, serial); never parallel cargo.

- This terminal was OOM-killed once mid-run; keep builds capped and avoid
  parallel heavy processes.

- Context7 monthly quota exhausted (2026-06-12) — `ctx7 login` for higher
  limits; using vendored source + upstream docs instead.

- Seat swap: RESOLVED (04-06, live-verified 2026-06-13).
  `replace_pane_with_existing_pane` is a one-way "bring pane here" primitive
  (NOT a swap) — proven at host commit e9173cb. True positional exchange now
  composed as a 3-call placeholder transaction (SwapPanes intent).

## Session Continuity

Branch model: trunk-based on `main` (fresh project; no phase branches).
Last session: 2026-06-13 — v0.2 roadmap created (3 phases, numbering reset).
Next: `/gsd-plan-phase 1` to plan Composition Core + Single-Line Spawn.

## Operator Next Steps

- Plan Phase 1 with `/gsd-plan-phase 1`.
