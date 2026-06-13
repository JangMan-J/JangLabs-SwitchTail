# Requirements — v0.2 Composing the Exchange

Milestone goal: turn the read-only switchboard into a live composition surface.
The operator builds the exchange by hand from inside the plugin, the way Zellij
itself grows a layout, with a parameterizable increment (a bare verb = 1; a
two-press bind verb+count = N).

The unit of composition is a **board of agent lines**, not a single line: a bare
board verb brings up one board of the default size (5 `claude` lines), and the
count multiplies boards (verb+3 → 3 boards of 5). A second verb adds individual
lines to the current board. Default agent is `claude`; default board size and
the verb bindings are configurable. Working directory is out of scope.

Domain vocabulary: **exchange** (the switchboard/session) · **board** (tab) ·
**line** (pane) · **deck** (one-press key map) · **trunk** (N parallel lines) ·
**operator** (the human).

REQ-ID prefix `COMP-` (composition); numbering is fresh for this milestone.

---

## v0.2 Requirements

The unit of composition is a **board of agent lines** — not a single line. The
default agent is `claude`; the default board size is configurable (default 5
lines/board). There are two compose verbs (board, line); both are configurable
bindings (defaults, not baked in — Shift/Super modifier space, off Zellij's
Ctrl/Alt) and both follow the same verb + optional-count grammar.

### Composition — boards (the primary unit)

- [ ] **COMP-01**: The operator can spawn a board of `claude` lines with a single board compose verb keypress (bare = exactly 1 board of the default size); the board appears, becomes focused, and its lines are assigned deck keys.
- [ ] **COMP-02**: A spawned line runs the configured default agent (`claude`) unless a different command is configured; bare-shell spawning is available as an explicit opt-out (the existing `n` path).
- [ ] **COMP-03**: The default number of lines per board is configurable (default 5); changing it changes how many `claude` lines a freshly spawned board carries.
- [ ] **COMP-04**: The operator can spawn N boards in one gesture by following the board verb with a count (single digit 1–9), each board carrying the default number of `claude` lines.

### Composition — lines (top up a board)

- [ ] **COMP-05**: The operator can add `claude` line(s) to the current board with a line compose verb: bare adds exactly 1; verb + count (single digit 1–9) adds that many lines to the current board.

### The increment grammar (mid-bind sub-state)

- [ ] **COMP-06**: After a compose verb, the plugin enters a count-entry sub-state where digit keys accumulate a count instead of acting as deck-jump shortcuts; a digit fires the count and Esc aborts, without mutating the exchange on abort.
- [ ] **COMP-07**: While a compose verb is pending, the operator sees a status-line indication of the pending verb and count (CB-safe: blue↔amber + text, never red↔green), so the mid-bind state is never invisible. (Status-line, not a separate view — the call-log surface is expected to fold into the main view later.)
- [ ] **COMP-08**: A bare compose verb with no following count acts in unit (board verb → 1 board of default size; line verb → 1 line), matching the "press and it happens" feel.

### Configurable bindings & key model

- [ ] **COMP-09**: The compose verbs are configurable key bindings (read from plugin config, with sensible Shift/Super defaults that avoid Zellij's Ctrl/Alt); the core key model and the adapter key mapping carry modifier information (Shift/Super), not just bare characters.

### Guardrails

- [ ] **COMP-10**: When spawning a board of N lines (or adding lines) would exceed the deck's finite key capacity, the plugin still spawns the lines but records a CB-safe call-log warning that the overflow line(s) have no deck key; it never silently drops or caps without surfacing it.
- [ ] **COMP-11**: A spawned line whose command exits immediately (e.g. `claude` not on PATH, exit 127) is surfaced as a call-log entry and reflected in the directory; the plugin never closes or kills any pane in response (no-kill discipline preserved).
- [ ] **COMP-12**: Spawning a board and filling it with its default lines is reconciled correctly despite the asynchronous host model (the board's tab and its lines arrive via later TabUpdate/PaneUpdate events) — the lines land on the intended board, and a pre-existing selection never drifts during the spawn burst.

---

## Future Requirements (deferred)

- **Per-board line-count in the gesture**: sizing an individual board's line
  count at spawn time (e.g. "this board gets 3, that one 8"). v0.2's count
  multiplies *boards* at the default size; per-board sizing is a later refinement.
- **Per-line / per-board working directory**: where a spawned agent works.
  Deferred (likely rides with agent-session wiring). v0.2 spawns in the plugin's
  cwd.
- **Multi-digit counts (≥10)**: single-digit (1–9) is the v0.2 ceiling; a
  larger count would need a commit/terminator step that breaks the live feel.
  Repeat the verb for more.
- **Auto-spawn on plugin load**: bring up the default board automatically on a
  fresh session with no keypress. Deferred — v0.2 keeps spawning operator-driven
  (the bare board verb), avoiding surprise pane-creation and async-on-load.
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
| COMP-01 | — | pending |
| COMP-02 | — | pending |
| COMP-03 | — | pending |
| COMP-04 | — | pending |
| COMP-05 | — | pending |
| COMP-06 | — | pending |
| COMP-07 | — | pending |
| COMP-08 | — | pending |
| COMP-09 | — | pending |
| COMP-10 | — | pending |
| COMP-11 | — | pending |
| COMP-12 | — | pending |

*(Phase column filled by the roadmapper. Coverage: 10/10 v0.2 requirements
mapped, each to exactly one phase.)*
