# Requirements — v0.2 Composing the Exchange

Milestone goal: turn the read-only switchboard into a live composition surface.
The operator builds the exchange by hand — spawning boards and lines from inside
the plugin the way Zellij itself grows a layout — with a parameterizable
increment (a bare verb = 1; a two-press bind verb+count = N). Default spawned
agent is `claude`. Working directory is out of scope.

Domain vocabulary: **exchange** (the switchboard/session) · **board** (tab) ·
**line** (pane) · **deck** (one-press key map) · **trunk** (N parallel lines) ·
**operator** (the human).

REQ-ID prefix `COMP-` (composition); numbering is fresh for this milestone.

---

## v0.2 Requirements

### Composition — lines

- [ ] **COMP-01**: The operator can spawn one line on the current board with a single compose verb keypress; it appears in the directory and is assigned the next deck key.
- [ ] **COMP-02**: A spawned line runs the configured default agent (`claude`) unless a different command is configured; bare-shell spawning is available as an explicit opt-out.
- [ ] **COMP-03**: The operator can spawn N lines on the current board in one gesture by following the line verb with a count (single digit 1–9).

### Composition — boards

- [ ] **COMP-04**: The operator can spawn one board (a new tab) with a single compose verb keypress; the new board carries one line running the default agent.
- [ ] **COMP-05**: The operator can spawn N boards in one gesture by following the board verb with a count (single digit 1–9), each board staffed with one line running the default agent.

### The increment grammar (mid-bind sub-state)

- [ ] **COMP-06**: After a compose verb, the plugin enters a count-entry sub-state where digit keys accumulate a count instead of acting as deck-jump shortcuts; the operator confirms (the count fires) or aborts (Esc) without mutating the exchange.
- [ ] **COMP-07**: While in count-entry, the operator sees a visible indication of the pending verb and count (CB-safe: blue↔amber + text, never red↔green), so the mid-bind state is never invisible.
- [ ] **COMP-08**: A bare compose verb with no following count acts in unit (spawns exactly 1), matching the "press and it happens" feel.

### Guardrails

- [ ] **COMP-09**: When a spawn would exceed the deck's finite key capacity, the plugin still spawns the line(s) but records a CB-safe call-log warning that the new line(s) have no deck key; it never silently drops or caps without surfacing it.
- [ ] **COMP-10**: A spawned line whose command exits immediately (e.g. command not found) is surfaced as a call-log entry and reflected in the directory; the plugin never closes or kills any pane in response (no-kill discipline preserved).

---

## Future Requirements (deferred)

- **Single-gesture board + N-lines**: spawn a board AND fill it with N lines in
  one composite gesture. Deferred — needs async TabUpdate reconciliation before
  the pane-fill; v0.2 scopes board-spawn to "board with one line," and lines are
  added to the (now-focused) board as a separate gesture.
- **Per-line / per-board working directory**: where a spawned agent works.
  Deferred (likely rides with agent-session wiring). v0.2 spawns in the plugin's
  cwd.
- **Multi-digit counts (≥10)**: single-digit (1–9) is the v0.2 ceiling; a
  larger count would need a commit/terminator step that breaks the live feel.
  Repeat the verb for more.
- **Agent-session wiring**: hosted agents push ring/status into the board
  themselves. Deferred to a later milestone; mechanism deliberately open (NOT
  assumed to be Claude Code hooks). See `seeds/agent-session-wiring.md`.

---

## Out of Scope (explicit exclusions)

- **Saved / named layouts**: "boot my standard 3×6." Requires a persistence
  layer (config round-trip, layout KDL, a picker UI) the project doesn't have.
  Excluded from v0.2 — composition is live and ephemeral.
- **Interactive builder / preview mode**: a pending-plan view you compose then
  fire. Explicitly rejected in exploration — v0.2 is incremental/live (press →
  it happens), no commit step.
- **Up-front dimension spec** (a `3×6` string parsed at load): superseded by the
  live-composition model; the dimension is the running tally of what you press.

---

## Traceability

| REQ-ID | Phase | Status |
|--------|-------|--------|
| COMP-01 | Phase 1 | pending |
| COMP-02 | Phase 1 | pending |
| COMP-03 | Phase 3 | pending |
| COMP-04 | Phase 2 | pending |
| COMP-05 | Phase 3 | pending |
| COMP-06 | Phase 1 | pending |
| COMP-07 | Phase 1 | pending |
| COMP-08 | Phase 1 | pending |
| COMP-09 | Phase 3 | pending |
| COMP-10 | Phase 1 | pending |

*(Phase column filled by the roadmapper. Coverage: 10/10 v0.2 requirements
mapped, each to exactly one phase.)*
