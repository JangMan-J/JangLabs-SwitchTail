# Phase 1: Board Foundation — Spawn One Board of Agents - Context

**Gathered:** 2026-06-13
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous) — grey areas resolved live with the operator
during milestone setup; decisions below are locked.

<domain>
## Phase Boundary

This phase delivers the **board verb spawning exactly one board of the default
size** (bare press → 1 board of 5 `claude` lines), plus the foundations every
later compose verb needs: a modifier-aware key model, configurable bindings, the
default-agent + board-size config, async board-fill reconciliation, the deck-cap
guardrail, and no-kill exit-127 surfacing.

IN SCOPE: COMP-01, COMP-02, COMP-03, COMP-09, COMP-10, COMP-11, COMP-12.

OUT OF SCOPE (later phases): the count grammar / N boards (Phase 2 — bare verb
only here, no count-entry sub-state yet); the line verb (Phase 3). Also out of
scope for the whole milestone: per-line cwd, multi-digit counts, auto-spawn on
load, per-board line sizing in the gesture.
</domain>

<decisions>
## Implementation Decisions

### The composition unit
- The unit of composition is a **board of agent lines**, not a single line.
- The board verb (bare) spawns **one board of the default size**; default size
  is **5** `claude` lines, configurable via plugin config.
- The board becomes focused; its lines are assigned deck keys on ingest (the
  existing deck assignment in `ingest_panes` handles this — no new deck logic).

### Default agent + config
- Default spawned command is **`claude`**, resolved IN CORE (core fills the
  command before emitting the spawn intent; the adapter stays dumb). Follow the
  existing `line_command` config-load precedent in `main.rs::load()` /
  `Exchange` — add an `agent_command` (default `["claude"]`) and a board-size
  config (default 5), both read from plugin configuration in `load()`.
- **Bare-shell opt-out** stays the existing `n` key (COMP-02) — `n` continues to
  open a plain terminal via the existing `OpenLine { command: line_command }`
  path; the new board verb is the `claude`-default path. Do not remove `n`.

### Key model (the v0.1 gap this phase closes)
- v0.1's `KeyInput` is bare `Char(c)` and the adapter's `key_input()` REJECTS
  most modified keys. This phase extends the core key model AND the adapter key
  mapping to carry **modifier information (Shift / Super)** so compose verbs can
  bind on those modifiers.
- Compose verb bindings are **configurable** (read from plugin config), with
  sensible **defaults on Shift / Super** — deliberately OFF Zellij's Ctrl/Alt
  space (Zellij owns those). Bindings are defaults, not contracts: do not bake a
  specific letter into core logic; the config supplies the binding, core matches
  against the configured verb.
- Scope the config to JUST the compose verb(s) for now — a general remappable
  keymap is a later concern.

### Async board-fill (COMP-12)
- A board of 5 is spawned as: `open_command_pane_in_new_tab(claude, ctx)` for
  the first line (creates + focuses the board), then `open_command_pane(claude,
  ctx)` ×4 in the SAME returned intent `Vec` — the host processes plugin
  commands FIFO, so all 4 land on the new (focused) board before any TabUpdate
  arrives. This is an intent FAN-OUT (N intents in one Vec), NOT a batched intent.
- The board's tab + lines arrive via later `TabUpdate` / `PaneUpdate` events and
  reconcile through the existing `ingest_panes` / `ingest_boards`. The lines must
  land on the intended board, and a pre-existing selection must NOT drift during
  the spawn burst (v0.1 already anchors selection by stable identity — extend the
  regression coverage to the N-spawn burst).

### Guardrails
- **Deck cap (COMP-10):** the deck has 10 keys (`1-9 0`). One board of 5 uses 5
  — fine. But spawning still must surface a CB-safe call-log warning when a
  spawn pushes total lines past deck capacity (matters more in Phase 2 with N
  boards, but the guardrail is built here). Lines still spawn; the overflow ones
  simply have no deck key. Never silently drop or cap.
- **No-kill exit-127 (COMP-11):** a spawned line whose command exits immediately
  (e.g. `claude` not on PATH) is surfaced as a call-log entry and stays in the
  directory as exited. The plugin NEVER closes/kills a pane in response
  (no-kill discipline; the test-enforced guard must stay green).

### Permission
- v0.2 declares the **`RunCommands`** permission (owner decision 2026-06-13) —
  required by `open_command_pane` for command-running lines. Add it to the
  `request_permission` set in `load()`. `open_command_pane_in_new_tab` needs only
  `ChangeApplicationState` (already declared). First launch after this change
  re-prompts for the grant; the e2e/permissions cache must be re-seeded.

### Architecture invariant (unchanged, sacred)
- `switchtail-core` stays zellij-free and unit-tested. New host effect = new
  `HostIntent` variant + one dispatcher arm. The composition state and the
  board/line spawn decisions live in core; the adapter just dispatches.
</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Exchange::key()` dispatch + the `prompt` / `prompt_key()` sub-state pattern
  (`exchange.rs`) — the model for any future mid-bind state (count-entry lands
  in Phase 2, not here).
- `HostIntent::OpenLine { command, cwd }` + the adapter arm in `main.rs`
  (`open_terminal` for empty command, `open_command_pane` for a command) — the
  existing single-line spawn path; reuse for the per-line fan-out.
- Deck assignment in `ingest_panes` (`deck.assign`) — new lines get deck keys
  automatically on ingest; no new deck code needed.
- `line_command` config load in `main.rs::load()` — the precedent for the new
  `agent_command` + board-size config.
- Selection is already identity-anchored (`selected_line_id` / `selected_seq_id`,
  v0.1 04-05) — the anti-drift foundation COMP-12 builds on.

### Established Patterns
- One intent = one shim call; key handlers return `Vec<HostIntent>` (fan-out is
  already idiomatic — e.g. attention intents).
- CB-safe rendering in `view.rs` (blue↔amber, INVERT for selection); the
  status-line indicator (Phase 2) extends the footer area.

### Integration Points
- New `HostIntent` variant for board spawn (carries the command + line count, or
  the core emits the fan-out directly — planner decides the cleanest shape that
  keeps the adapter dumb; note the placeholder PaneId rationale does NOT apply
  here — board spawn returns IDs the core doesn't need).
- `main.rs::load()` — add `RunCommands` permission + read `agent_command` /
  board-size config.
- `key.rs` (KeyInput) + `main.rs::key_input()` — carry Shift/Super modifiers.

### Verified shim signatures (vendored zellij-tile-0.44.3, 2026-06-13)
- `new_tab(name: Option<S>, cwd: Option<S>) -> Option<usize>` (shim.rs:949)
- `open_command_pane_in_new_tab(CommandToRun, BTreeMap) -> (Option<usize>, Option<PaneId>)` (shim.rs:966)
- `open_command_pane(CommandToRun, BTreeMap) -> Option<PaneId>` (shim.rs:591) — requires RunCommands
</code_context>

<specifics>
## Specific Ideas

- Default board size literally 5 (the operator's stated default: "1 board of 5").
- Status-line, NOT a separate view, for any pending-state indicator (the call-log
  surface is expected to fold into the main view later as a sidebar/status
  line/small pane — don't deepen the Directory-vs-Log split).
- Bindings configurable with Shift/Super defaults — exact default keys are low-
  stakes and the operator explicitly de-weighted them; pick reasonable defaults,
  keep them config-driven.
</specifics>

<deferred>
## Deferred Ideas

- The count grammar / N boards in one gesture → Phase 2 (COMP-04, 06, 07, 08).
- The line verb (add lines to current board) → Phase 3 (COMP-05).
- Per-board line sizing in the gesture, per-line cwd, multi-digit counts,
  auto-spawn on load → deferred beyond v0.2 (see REQUIREMENTS.md).
</deferred>
