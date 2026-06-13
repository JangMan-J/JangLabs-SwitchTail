# Milestones

## v0.1 Switchboard Groundwork (Shipped: 2026-06-13)

**Phases completed:** 4 phases (Core Model, Plugin Adapter, Pipes & Protocol,
Operator Polish & E2E). Built across one autonomous session (2026-06-12) plus a
gap-closure session (2026-06-13); per-phase plan/summary files exist only for
the Phase-4 gap-closure work (04-05, 04-06).

**Delivered:** The groundwork of a Zellij plugin that extends
window-manager-grade control to a set of agentic terminals — a live pane
directory, one-press deck navigation, true positional seat swap, per-line
patch-through messaging, a triageable call log, and a JSON pipe protocol — all
behind a `HostIntent` seam that keeps the core pure and host-free.

**Key accomplishments:**

- **Pure core / thin adapter architecture** — `switchtail-core` (no zellij dep,
  fully unit-tested) emits `HostIntent` values; `switchtail` plugin is a thin
  WASM adapter that dispatches them. The expandability seam: new capability =
  new intent + one dispatcher arm.
- **The switchboard model** — directory ingestion from pane snapshots, sticky
  deck-key assignment, seat tracking, a capped call log with triage
  (ringing/answered/parked) and three sort modes, all decided and tested in core.
- **Identity-anchored selection** (04-05) — selection tracks by stable identity
  (`LineId` / call seq), not a drifting row index, fixing ring/cursor
  mistargeting under re-sort. Live-verified.
- **True positional seat swap** (04-06) — composed 3-call placeholder exchange
  after proving `replace_pane_with_existing_pane` is one-way, not a swap (host
  commit e9173cb). Live-verified: panes trade slots exactly, FIFO ordering,
  benign suppressed-restore.
- **Pipe protocol** — external processes drive/query the board by line ID over
  `zellij pipe -n switchtail` (say/focus/ring/status/register mutate; list/log
  answer with JSON); malformed payloads become logged calls, never panics.
- **CB-safe operator UI + tooling** — blue↔amber attention surface (no red↔green
  meaning), one-command dev/build/reload, headless E2E smoke harness, and a
  test-enforced no-kill discipline (no close/kill call sites in the adapter).

**Quality gates at close:** 34 core unit tests + no-kill guard green; wasm
builds clean; Phase-4 UAT 9/9 (all live-verified); clippy clean.

**Known deferred:** Release wasm build (lto=true) SIGSEGVs rustc under load on
this box — debug wasm deployed instead; retry on a quiet system.

---
