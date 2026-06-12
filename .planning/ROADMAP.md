# Roadmap: SwitchTail — v0.1 Switchboard Groundwork

## Overview

Build the groundwork of a highly-expandable Zellij plugin that extends
window-manager-style control to fleets of agentic terminals: a live pane
directory, a one-press deck, seat swapping, per-line messaging, and a
triageable call log — all behind the `HostIntent` seam that keeps the model
pure and every future capability a small follow-on. Facts in
`docs/zellij-api-notes.md` are source-verified; the design contract is
`docs/DESIGN.md`.

## Phases

- [x] **Phase 1: Core Model** - switchtail-core: directory, deck assignment, seat, call log, triage, sorting, protocol types — pure + TDD
- [x] **Phase 2: Plugin Adapter** - events→core, intents→shim, ANSI render, deck/seat/say keys; wasm loads in zellij 0.45
- [x] **Phase 3: Pipes & Protocol** - switchtail pipe ops in/out, JSON list/log dumps, register/status metadata
- [x] **Phase 4: Operator Polish & E2E** - CB-safe attention surface, launch key, dev/install tooling, headless E2E smoke, review pass

## Phase Details

### Phase 1: Core Model
**Goal**: The entire switchboard model lives in `switchtail-core`, pure and unit-tested — directory ingestion from pane snapshots, sticky deck assignment, seat tracking, call log with triage and sort, wire-protocol parse/serialize, all host effects as `HostIntent`s
**Requirements**: DIR-01, DIR-02, DIR-03, DECK-01, LOG-01, LOG-02
**Success Criteria**:
  1. `cargo test -p switchtail-core` green with meaningful coverage of assignment stickiness, triage transitions, ring-buffer capping, sort orders, and protocol round-trips
  2. The crate compiles for both host and `wasm32-wasip1` with no zellij dependency

### Phase 2: Plugin Adapter
**Goal**: The plugin builds to WASM, loads in zellij 0.45 under minimal declared permissions, renders directory+log views, and the operator can deck-jump, seat-swap, and patch text to a line
**Requirements**: DECK-02, DECK-03, DECK-04, LOG-03, SHELL-01, SHELL-02
**Success Criteria**:
  1. `tools/dev.sh build` produces `switchtail.wasm`; `start-or-reload-plugin` loads it without panics (zellij.log clean)
  2. Deck key focuses the right pane; `m`+`s` swaps a line into the seat; `i`-prompt text arrives in the target pane

### Phase 3: Pipes & Protocol
**Goal**: External processes drive and query the switchboard by line ID over `zellij pipe -n switchtail` — say/focus/ring/status/register mutate, list/log answer with JSON on the pipe
**Requirements**: PIPE-01, PIPE-02, PIPE-03
**Success Criteria**:
  1. Each op verified end-to-end via `zellij pipe`; malformed payloads are logged calls, never panics
  2. `list` output parses as JSON and matches the live pane set

### Phase 4: Operator Polish & E2E
**Goal**: Ringing lines are visibly surfaced CB-safely on the board, the dev/install story is one command each, a headless E2E smoke harness exists, and the whole diff has had a review pass
**Requirements**: LOG-04, SHELL-03, SHELL-04
**Success Criteria**:
  1. Ring → amber tint + highlight on the target pane; answer/park clears it
  2. `tests/e2e.sh` runs a scripted zellij session headlessly and asserts plugin load + pipe round-trip via dump-screen/pipe output
  3. No-kill test guards the adapter; review findings fixed or recorded

## Progress

| Phase | Status | Completed |
|-------|--------|-----------|
| 1. Core Model | Complete | 2026-06-12 |
| 2. Plugin Adapter | Complete | 2026-06-12 |
| 3. Pipes & Protocol | Complete | 2026-06-12 |
| 4. Operator Polish & E2E | Complete | 2026-06-12 |
