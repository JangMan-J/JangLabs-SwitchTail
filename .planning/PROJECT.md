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
| Pin zellij-tile 0.44.3, verify API from vendored source | docs.rs/web summaries proved unreliable; binary is 0.45.0 (compatible direction) | Done |
| Minimal permission set, withhold RunCommands et al. | Convert kitty-era discipline-only safety into structural surface reduction | Active |
