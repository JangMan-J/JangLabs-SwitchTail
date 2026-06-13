---
gsd_state_version: 1.0
milestone: v0.2
milestone_name: Composing the Exchange
status: executing
last_updated: "2026-06-13T18:27:46.249Z"
last_activity: 2026-06-13 -- Plan 01-02 complete
progress:
  total_phases: 3
  completed_phases: 0
  total_plans: 3
  completed_plans: 2
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (created 2026-06-12, fresh-slate restart)

**Core value:** one-handed fleet control without losing the overview.
**Current focus:** Phase 01 — board-foundation
corrected board-of-agents model (3 phases, numbering reset to 1). The unit of
composition is a **board of agent lines** (default 5 `claude`), so a board of N
is foundational, not deferred. Next: plan Phase 1.

## Current Position

Phase: 01 (board-foundation) — EXECUTING
Plan: 3 of 3
Status: Ready to execute
Last activity: 2026-06-13 -- Plan 01-02 complete (SpawnBoard intent, agent config, fan-out, deck-cap, note_command_exit, no-drift test)

Progress: [..........................] 0% (0/3 phases)

## v0.2 Phase Map

| Phase | Goal | Requirements |
|-------|------|--------------|
| 1. Board Foundation — Spawn One Board of Agents | Press the board verb → one default-size board (5 `claude` lines), focused; modifier-aware key model + config; async board-fill reconciled (no drift); deck-cap warning; exit-127 surfaced no-kill | COMP-01, 02, 03, 09, 10, 11, 12 |
| 2. Count Grammar — N Boards in One Gesture | Board verb + digit 1–9 → N boards of 5; count-entry sub-state (digit fires, Esc aborts, no deck collision); CB-safe status-line indicator; bare verb = 1 board | COMP-04, 06, 07, 08 |
| 3. Line Verb — Top Up the Current Board | Second line verb adds `claude` lines to the current board (bare = 1, verb + count = N), reusing the Phase 2 count grammar | COMP-05 |

Coverage: 12/12 v0.2 requirements mapped (each to exactly one phase).

## Accumulated Context

### Decisions

- **CORRECTED MODEL (2026-06-13): the unit of composition is a board of agent
  lines, NOT a single line.** A bare board verb spawns 1 board of the default
  size (5 `claude` lines); the count multiplies BOARDS (verb+3 → 3 boards of 5).
  A second LINE verb adds individual lines to the current board. The prior
  single-line-first roadmap (board carrying ONE line; board-of-5 deferred) was
  built against superseded requirements and has been replaced.

- **Board-of-N is foundational, so async board-fill is in scope from Phase 1.**
  Spawning a board of 5 = `open_command_pane_in_new_tab` (line 1, creates +
  focuses the board) then `open_command_pane` ×4 in the SAME dispatch Vec; the
  host processes FIFO so all 4 land on the new board before any TabUpdate
  arrives. The tab + lines then reconcile via later TabUpdate/PaneUpdate without
  drifting a pre-existing selection (identity anchor from v0.1).

- **v0.2 declares the `RunCommands` permission** (owner decision, 2026-06-13) —
  a deliberate addition to the v0.1 minimal set. Enables native
  `open_command_pane` so the board-fill lines (lines 2–N on a new board, and the
  Phase 3 line verb) can run `claude` as the default agent.
  `open_command_pane_in_new_tab` (the first line of each board) needs only the
  already-declared `ChangeApplicationState`; `open_command_pane` on an existing
  focused board needs `RunCommands`. The `open_terminal` + `write_chars`
  workaround was evaluated and rejected. Re-grant required: clear
  `XDG_CACHE_HOME/zellij/permissions.kdl` and the e2e isolated cache when the
  permission is added.

- **Modifier-carrying key model is foundational (Phase 1).** v0.1's bare
  `Char(c)` cannot express Shift/Super; the core `KeyInput` model + adapter key
  mapping must carry modifier info so verb bindings can be configurable Shift/
  Super defaults (off Zellij's Ctrl/Alt). Needed before any verb is bound.

- **Compose grammar is pure core** (mirrors the v0.1 `Prompt` sub-state): a
  `Compose`/`ComposeVerb` count-entry state in exchange.rs, gated at the TOP of
  `key()` before deck dispatch so digits 1–9 accumulate a count instead of
  deck-jumping. Esc aborts. Default-command resolution and the count fan-out
  (N intents in one returned Vec, NOT a batched intent) live in core; the
  adapter stays dumb (new capability = new intent + one dispatcher arm).

- **Default-command resolution lives in CORE.** Default agent = `claude`,
  default board size = 5 (both configurable). Core emits fully-resolved
  `OpenLine`/`SpawnBoard` intents; the adapter never re-derives the command.

- Fresh slate executed: kitty era archived (tag `kitty-era-final`,
  `~/JangLabs/.archive/switchtail-kitty-era/` incl. RESTORE.md). v0.1 phase
  dirs archived to `.planning/milestones/v0.1-phases/`; numbering reset to 1.

- zellij-tile pinned 0.44.3 against host zellij 0.45.0; API source-verified
  (docs/zellij-api-notes.md). Web/docs summaries were wrong on signatures —
  always verify from vendored source. Verify the exact
  `open_command_pane_in_new_tab` signature during Phase 1 planning.

- Core/adapter split with HostIntent seam (docs/DESIGN.md). One intent = one
  shim call (SwapPanes composed transaction is the sole exception). Every
  phase's core logic must be unit-testable without a Zellij host.

- Vocabulary seeded as domain language per owner mid-task directive
  (board = tab, line = pane, deck, trunk, exchange, operator).

- **Exchange::Default is explicit (not derived)** (2026-06-13): `agent_command` needs `vec!["claude"]` which cannot come from `#[derive(Default)]` on a Vec field. Explicit `Default` impl sets all fields.

- **deck_overflow_warning counts occupied slots as lines-with-a-deck-key** (2026-06-13): counts via `lines.keys().filter(|id| deck.key_for(**id).is_some())` — avoids adding public Deck API just for a count.

- **note_command_exit surfaces any exit status** (2026-06-13): fires a LineExited entry for ANY status (0, 127, None); only the 127 wording is special. Line is RETAINED, no kill intent. Modelled on note_cwd_change.

### Blockers/Concerns

- **Default-agent PATH risk (Phase 1)**: `claude` may not be on the spawned
  pane's PATH (Zellij #3856/#3924 — no env field on `CommandToRun`, PATH not
  guaranteed inherited). A bare `claude` can exit 127. Surface as a
  `LineExited` call-log entry; never close the pane. Document that
  `agent_command` should be an absolute path or a guaranteed-PATH wrapper.

- **Selection drift under board-fill / N-spawn**: spawning a board of 5 (Phase 1)
  and N boards (Phase 2) emits many sequential PaneUpdate/TabUpdate events, each
  re-ingesting/re-ranking. Selection is already identity-anchored
  (`selected_line_id`) from v0.1 — confirm no regression with a
  `spawn_board_fill_selection_does_not_drift` test in Phase 1 and extend for
  N boards in Phase 2.

- **Deck-cap matters from Phase 1**: the deck has 10 keys. One board of 5 uses 5
  (within capacity), but 2 boards already = 10 and 3 = 15 (Phase 2 exceeds it).
  Build the CB-safe deck-cap warning (amber + text, never red) in core in Phase 1
  so it is fully exercised in Phase 2 — spawn past capacity but never silently
  drop or cap.

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
Last session: 2026-06-13T18:27:46.245Z
model (3 phases, numbering reset). The previous single-line-first roadmap was
superseded.
Next: `/gsd-plan-phase 1` to plan Board Foundation — Spawn One Board of Agents.

## Operator Next Steps

- Plan Phase 1 with `/gsd-plan-phase 1`.
