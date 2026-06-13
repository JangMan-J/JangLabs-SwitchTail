# Roadmap: SwitchTail

## Milestones

- ✅ **v0.1 Switchboard Groundwork** — Phases 1–4 (shipped 2026-06-13) ·
  archived: [`milestones/v0.1-ROADMAP.md`](milestones/v0.1-ROADMAP.md)
- 🚧 **v0.2 Composing the Exchange** — Phases 1–3 (numbering reset; v0.1 phase
  dirs archived to `milestones/v0.1-phases/`)

## Phases

<details>
<summary>✅ v0.1 Switchboard Groundwork (Phases 1–4) — SHIPPED 2026-06-13</summary>

- [x] Phase 1: Core Model — completed 2026-06-12
- [x] Phase 2: Plugin Adapter — completed 2026-06-12
- [x] Phase 3: Pipes & Protocol — completed 2026-06-12
- [x] Phase 4: Operator Polish & E2E — completed 2026-06-13 (UAT 9/9, gap-closure 04-05/04-06)

Full detail: [`milestones/v0.1-ROADMAP.md`](milestones/v0.1-ROADMAP.md) ·
requirements: [`milestones/v0.1-REQUIREMENTS.md`](milestones/v0.1-REQUIREMENTS.md)

</details>

### 🚧 v0.2 Composing the Exchange

Numbering reset to Phase 1 (owner directive; v0.1 archived).

- [ ] **Phase 1: Composition Core + Single-Line Spawn** - Mid-bind compose
  sub-state, default-agent `claude` line spawn (N=1), digit/deck-key collision
  gate, exit-127 surfaced no-kill.
- [ ] **Phase 2: Board Spawn** - `OpenBoard` intent + native
  `open_command_pane_in_new_tab` adapter arm; spawn one board carrying one line.
- [ ] **Phase 3: Multi-Spawn (N>1) + Deck-Cap Guardrail** - Count fan-out for
  lines and boards (verb + digit 1–9), deck-exhaustion warning, selection-drift
  regression under N sequential reconciliations.

## Phase Details

### Phase 1: Composition Core + Single-Line Spawn
**Goal**: The operator can press one compose verb and immediately get a new line
on the current board running the default agent (`claude`) — building the
exchange by hand with the "press → it happens" feel, with the mid-bind grammar
visible and abortable, and a failed command surfaced rather than swept away.
**Depends on**: Nothing (first v0.2 phase; builds on the shipped v0.1 core)
**Requirements**: COMP-01, COMP-02, COMP-06, COMP-07, COMP-08, COMP-10
**Success Criteria** (what must be TRUE):
  1. The operator presses the line compose verb and exactly one new line appears
     on the current board, gets the next deck key, and runs `claude` by default.
  2. The operator can configure a different command (including bare shell as the
     explicit opt-out) and the spawned line runs that instead of `claude`.
  3. After pressing the compose verb the operator is in a count-entry sub-state
     where digit keys accumulate a count instead of jumping to a deck line, and
     pressing Esc returns to normal mode without spawning anything.
  4. While in count-entry the operator sees a CB-safe indication (blue↔amber +
     text label, never red↔green) of the pending verb, so the mid-bind state is
     never invisible.
  5. A spawned line whose command exits immediately (e.g. `claude` not on PATH,
     exit 127) shows as a call-log entry and stays in the directory; the plugin
     never closes or kills the pane (no-kill discipline preserved).
**Plans**: TBD

### Phase 2: Board Spawn
**Goal**: The operator can press one compose verb and immediately get a new
board (tab) that already carries one line running the default agent — growing
the exchange a board at a time, the way Zellij itself opens a tab.
**Depends on**: Phase 1 (reuses the compose sub-state, `agent_command`
resolution, and exit-127 surfacing established there)
**Requirements**: COMP-04
**Success Criteria** (what must be TRUE):
  1. The operator presses the board compose verb and exactly one new board
     appears, becomes focused, and carries one line running `claude` by default.
  2. The new board's line is surfaced as a call-log entry and shows in the
     directory once its `TabUpdate`/`PaneUpdate` arrives — the operator sees the
     board land, not a silent no-op.
  3. The board verb behaves identically to the line verb's mid-bind grammar: a
     bare press spawns one board, and Esc during count-entry aborts cleanly.
**Plans**: TBD

### Phase 3: Multi-Spawn (N>1) + Deck-Cap Guardrail
**Goal**: The operator can fill the exchange in one gesture — verb followed by a
digit 1–9 spawns that many lines (or boards) at once — and is never surprised:
spawns past the deck's key capacity still happen but are flagged, and the
selection never wanders during the spawn burst.
**Depends on**: Phase 1 (compose sub-state, line spawn) and Phase 2 (board spawn)
**Requirements**: COMP-03, COMP-05, COMP-09
**Success Criteria** (what must be TRUE):
  1. The operator presses the line verb then a digit 1–9 and that many lines
     appear on the current board in one gesture (a trunk of N parallel lines).
  2. The operator presses the board verb then a digit 1–9 and that many boards
     appear, each staffed with one line running the default agent.
  3. When a spawn would exceed the deck's finite key capacity the line(s) still
     spawn, but the operator gets a CB-safe call-log warning (amber + text) that
     the overflow line(s) have no deck key — never a silent drop or cap.
  4. If a line was selected before the gesture, it stays selected on the same
     identity throughout the N sequential reconciliations — the cursor does not
     drift to another row during the spawn burst.
**Plans**: TBD

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Core Model | v0.1 | — | Complete | 2026-06-12 |
| 2. Plugin Adapter | v0.1 | — | Complete | 2026-06-12 |
| 3. Pipes & Protocol | v0.1 | — | Complete | 2026-06-12 |
| 4. Operator Polish & E2E | v0.1 | — | Complete | 2026-06-13 |
| 1. Composition Core + Single-Line Spawn | v0.2 | 0/0 | Not started | - |
| 2. Board Spawn | v0.2 | 0/0 | Not started | - |
| 3. Multi-Spawn + Deck-Cap Guardrail | v0.2 | 0/0 | Not started | - |
