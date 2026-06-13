# SwitchTail

## What This Is

SwitchTail is the operator's switchboard for agentic terminals: a Zellij
plugin (Rust → `wasm32-wasip1`, zellij-tile) that gives one-press,
window-manager-grade control over a fleet of agent CLI sessions — jump to any
line by ID, swap any line into the seat, patch messages to/from any line, and
watch the whole fleet on a live, triageable call log.

This is a **fresh project** (2026-06-12, owner directive). The kitty-based
SwitchTail v1 and its incremental-parity milestone are retired and preserved
at git tag `kitty-era-final` and `~/JangLabs/.archive/switchtail-kitty-era/`.
Distilled carry-over knowledge lives in `docs/legacy-learnings.md`; the
telephony vocabulary survives as the project's core domain language
(`docs/DESIGN.md`).

## Core Value

The operator can route, watch, and command a fleet of agentic terminal
sessions one-handed, without ever losing the overview.

## Current State

**Shipped: v0.1 Switchboard Groundwork** (2026-06-13) — a pure-core /
thin-adapter Zellij plugin with a live pane directory, one-press deck
navigation, true positional seat swap, per-line patch-through messaging, a
triageable call log, and a JSON pipe protocol, all behind the `HostIntent`
seam. 34 core tests + no-kill guard green; UAT 9/9 (live-verified). Full
archive: `milestones/v0.1-ROADMAP.md`.

## Current Milestone: v0.2 Composing the Exchange

**Goal:** Turn the read-only switchboard into a live composition surface — the
operator builds the exchange by hand from inside the plugin, the way Zellij
itself grows a layout. The unit of composition is a **board of agents**.

**Target features:**
- A **board verb** (primary) that spawns a board of `claude` lines: bare = 1
  board of the default size (5 lines); count multiplies boards (verb+3 → 3
  boards of 5). Live and immediate — press → it happens, no builder mode.
- A **line verb** that adds individual `claude` line(s) to the current board:
  bare = 1 line; verb + count = N lines.
- **Parameterizable increment**: a bare verb acts in unit; a two-press bind
  (verb → digit) acts in quantity. Single digit 1–9; Esc aborts.
- **Default agent `claude`**; **default board size 5**; **verb bindings** all
  configurable (defaults, not baked in — Shift/Super space, off Zellij's
  Ctrl/Alt). The core key model and adapter carry modifier info.

**Out of scope (v0.2):** working directory / cwd per line (deferred — likely
rides with agent-session wiring); per-board line-count in the gesture (count
multiplies boards at the default size); auto-spawn on plugin load (composition
stays operator-driven); interactive builder/preview; saved layouts.

**Deferred to a later milestone:** wiring the hosted agent sessions so they push
ring/status into the board themselves (mechanism deliberately open — NOT assumed
to be Claude Code hooks). See `seeds/agent-session-wiring.md`.

## Context

- Host: single CachyOS / KDE Plasma 6 / Wayland box; zellij 0.45.0 installed.
- SDK facts are pinned and source-verified in `docs/zellij-api-notes.md`
  (zellij-tile 0.44.3) — do not trust training-data API names.
- Nearly all "window manager" primitives needed are native Zellij plugin API:
  focus by PaneId, replace-pane (seat swap), write-to-pane, pane
  rename/recolor, pipes, pane grouping/highlighting. The plugin's job is the
  *model* (directory, deck, triage, protocol) and the operator UX.
- Owner is colorblind (daltonized theme): UI must never encode meaning on
  red↔green; use blue↔amber + lightness + redundant text/shape cues.

## Constraints

- **Tech stack**: Rust → `wasm32-wasip1` Zellij plugin, zellij-tile 0.44.x —
  owner decision (LOCKED 2026-06-12).
- **Architecture**: `switchtail-core` (pure model, no zellij deps, unit
  tested) + `switchtail` plugin (thin adapter); host effects flow through a
  `HostIntent` seam — the expandability contract.
- **Safety**: minimal declared permissions; no `RunCommands`/`WebAccess`/
  `InterceptInput`; no `close_*` call sites in the adapter (test-enforced).
- **Build hygiene**: this box runs many concurrent sessions — builds use
  `CARGO_BUILD_JOBS=4` (tools/dev.sh) and `debug=0`; never spawn parallel
  build trees.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| LOCKED (owner, 2026-06-12): fresh slate — retire kitty era entirely, rebuild as a Zellij plugin, window-manager groundwork first | Owner directive; incremental parity migration abandoned in favor of plugin-first groundwork | Done — purge commit `8199c94` |
| LOCKED (owner, 2026-06-12): retro telephony vocabulary is the project's domain language, seeded into types/keys/docs | Owner directive ("seed it strongly") | Active |
| Core/adapter split with `HostIntent` seam | Expandability + testability without a running Zellij | Active |
| Pin zellij-tile 0.44.3, verify API from vendored source | docs.rs/web summaries proved unreliable; binary is 0.45.0 (compatible direction) | ✓ Good (v0.1) |
| Minimal permission set, withhold RunCommands et al. | Convert kitty-era discipline-only safety into structural surface reduction | Active |
| Selection anchored by stable identity, not row index | Row-index selection drifted under view re-sort (UAT gaps 4+6) | ✓ Good (v0.1, 04-05) |
| Seat swap composed as a 3-call placeholder exchange | `replace_pane_with_existing_pane` is one-way, not a swap (proven at host commit e9173cb); no single swap primitive exists | ✓ Good (v0.1, 04-06) |
| v0.2: live in-plugin composition (verb+count), not an up-front spec | Zellij-native press-and-it-happens feel; keeps v0.1's pure-core grain | Pending (v0.2) |
| v0.2: unit of composition is a **board of agents** (default 5 lines); count multiplies boards | Operator thinks in boards-of-agents, not single lines; bare verb = 1 board of 5 | Pending (v0.2) |
| v0.2: default agent `claude`; default board size + verb bindings configurable; cwd out of scope | Tool exists to bring up agents; bindings are defaults not contracts (Shift/Super, off Zellij Ctrl/Alt); cwd separable | Pending (v0.2) |
| v0.2: declare `RunCommands` permission | Native command panes (re-run + exit-status UI) for restartable agent sessions; verified open_command_pane requires it. Deliberate revision of v0.1's withhold stance | Pending (v0.2) |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-06-13 after v0.1 milestone (v0.2 Composing the Exchange started)*
