# Roadmap: SwitchTail — Zellij Foundation

## Overview

This milestone replaces SwitchTail's kitty foundation with a Zellij WASM plugin (Rust/zellij-tile) and retires the Plasma 6 widget — the plugin contains the entire system surface, absorbing the widget's launcher/introspector role as in-mux UI. The kitty system (widget included) stays the daily driver until parity. The arc follows the ingested migration prescription: first cut the running-state seam on the *current* system (decoupling from kitty's window-class stamping before, not during, the move), then prove Zellij can answer each of kitty's four fused roles — now including the no-widget desktop entry-point story — then rebuild capability by capability: lifecycle, hold/resume, the interaction layer (a paradigm rewrite, not a port, now carrying the launcher/introspector surface), and finally verify parity against the regression baseline and cut over: systemd and launchers swap, the plasmoid is uninstalled, kitty retires. No phase before Phase 6 may break the working kitty system. The `stail --json` contract survives for CLI/scripting/systemd consumers, but with the widget retired it is no longer a frozen GUI compatibility boundary. Zellij plugin API specifics are deliberately absent here — plan-phase research resolves them per phase against live docs.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

- [ ] **Phase 1: Running-State Seam** - stail owns running state on the current kitty system; kdotool shrinks to raise/focus
- [ ] **Phase 2: Zellij Plugin Feasibility** - PoC plugin proves all four kitty roles have Zellij-era answers, incl. the launcher/introspector role and no-widget entry points; prior art assessed
- [ ] **Phase 3: Core Lifecycle on Zellij** - board/line/trunk/patch/exchange with per-pane identity, driven by the kind table
- [ ] **Phase 4: Hold/Resume on Zellij** - per-pane session-ID marker protocol, atomic claim, fleet-safe park and resume
- [ ] **Phase 5: Interaction Layer** - in-plugin watcher styling, attention surface, numpad deck, hot-seat swap, launcher/introspector UI, structural pane-safety
- [ ] **Phase 6: Parity Cutover** - systemd/launchers on the Zellij backend, suite green at baseline breadth, plasmoid retired, kitty retired

## Phase Details

### Phase 1: Running-State Seam
**Goal**: Running-board state is owned by stail itself, decoupling detection from kitty's window-class stamping — the prescribed pre-migration step, done on the live kitty system without breaking it
**Depends on**: Nothing (first phase)
**Requirements**: SEAM-01, SEAM-02
**Success Criteria** (what must be TRUE):
  1. `stail list` and `stail list --json` report correct running state for every lab without consulting kdotool/KWin window-class search
  2. kdotool appears only on the raise/focus path (`stail switch`); removing it entirely would degrade raising, never listing
  3. The Plasma widget (still installed until Phase 6 cutover) shows correct running state with zero widget changes, confirming the `--json` contract held through the seam
  4. The kitty daily driver passes the full regression suite (147-assertion baseline plus new state-seam assertions)
**Plans**: TBD

### Phase 2: Zellij Plugin Feasibility
**Goal**: Confidence, backed by a running proof-of-concept, that Zellij can cover kitty's four fused roles — mux/session grammar, scriptable window model, watcher host, GUI host — plus the retired widget's launcher/introspector role, with an architecture decision on what lives in the plugin vs in stail
**Depends on**: Phase 1
**Requirements**: PLUG-01, PLUG-02, PLUG-03
**Success Criteria** (what must be TRUE):
  1. A proof-of-concept SwitchTail plugin compiles to WASM, loads in Zellij, and reacts to pane lifecycle events while declaring only the permissions it needs
  2. The plugin demonstrates the watcher role's core primitive: renaming/recoloring a pane without typing into it
  3. A written feasibility verdict exists for each of the four kitty roles, including the GUI-host answer (host terminal choice, window identity, launcher ownership) and how the plugin covers the launcher/introspector role
  4. The desktop entry-point story without a widget is decided and recorded: how launcher entries spawn Zellij boards, and what raise/focus means with no widget driving it
  5. Each prior-art plugin (zellij-attention, zellaude, sessionizers/zellij-switch, pane pickers/room) has a recorded build-on / reimplement / ignore verdict — and the kitty daily driver is untouched by this phase
**Plans**: TBD

### Phase 3: Core Lifecycle on Zellij
**Goal**: The operator can assemble and run boards of Claude Code lines on Zellij through stail — the board/line/trunk/patch/exchange grammar lives on the new foundation
**Depends on**: Phase 2
**Requirements**: LIFE-01, LIFE-02, LIFE-03, LIFE-04, LIFE-05
**Success Criteria** (what must be TRUE):
  1. The operator can launch a lab's board of Claude Code lines on Zellij, and raise it if already running
  2. `stail trunk <lab> N` yields N parallel lines for one lab on one board; a cart spec patches a tabbed multi-lab board including the all-labs exchange
  3. Every line carries queryable identity on Zellij: lab, per-pane session id, and kind-derived policy flags
  4. Line argv and holdable/stylable policy come only from the agent-kind table — the plugin contains no agent-kind literals
  5. The kitty path still works in parallel; nothing regresses on the daily driver
**Plans**: TBD

### Phase 4: Hold/Resume on Zellij
**Goal**: The park-to-resume lifecycle works on the Zellij backend with the per-pane session-ID marker protocol, deterministic under fleet operations
**Depends on**: Phase 3
**Requirements**: HOLD-01, HOLD-02, HOLD-03
**Success Criteria** (what must be TRUE):
  1. Holding a line closes it and leaves a marker `hold/<lab>/<session-id>`; the next launched line for that lab claims it atomically and resumes that exact session
  2. The legacy `--continue` fallback still works and stays cwd-scoped (never cross-wires labs)
  3. Holding an entire board (or the fleet) and re-patching resumes every parked line — no one-per-lab collapse
  4. Concurrently booting trunk lines never double-claim or orphan a marker
**Plans**: TBD

### Phase 5: Interaction Layer
**Goal**: The kittens + deck.conf paradigm is rebuilt inside the plugin — auto-labeling, attention, one-handed deck, hot-seat swap — plus the retired widget's launcher/introspector role as in-plugin UI, and the watcher becomes structurally unable to kill a pane
**Depends on**: Phase 4
**Requirements**: WATCH-01, WATCH-02, WATCH-03, DECK-01, DECK-02, DECK-03
**Success Criteria** (what must be TRUE):
  1. A freshly booted or resumed Claude line is auto-titled and colored per its kind, exactly once — no boot-timing keystrokes land as prompt input
  2. The operator can focus any line one-handed via the numpad deck and hot-seat swap lines as on the kitty deck
  3. From inside Zellij, the operator can browse labs with running state, assemble a cart with per-lab line counts, and patch a board — the widget's launcher/introspector role, in-plugin
  4. A line that needs operator attention is visibly surfaced on the board
  5. The plugin's declared permission set verifiably excludes pane destruction
**Plans**: TBD
**UI hint**: yes

### Phase 6: Parity Cutover
**Goal**: Every surviving external surface runs against the Zellij backend at verified parity; Zellij becomes the daily driver, and both kitty and the Plasma 6 plasmoid are retired
**Depends on**: Phase 5
**Requirements**: CUT-01, CUT-02, CUT-03, CUT-04, CUT-05
**Success Criteria** (what must be TRUE):
  1. The plasmoid is removed from `~/.local/share/plasma/plasmoids/` and from the panel, and plasmashell restarts with a clean journal (no errors naming the applet)
  2. Adding or removing a lab in the workspace triggers the systemd units to regenerate Zellij board definitions
  3. Per-lab launcher entries open a lab's Zellij board, and `stail switch` raises an already-running board on Plasma/Wayland
  4. The regression suite runs green covering the ported behavior set, at breadth ≥ the 147-assertion kitty baseline
  5. Zellij is the daily driver; kitty-specific surfaces and the plasmoid are retired only after criterion 4 holds — at no earlier point was the kitty system broken — and `stail --json` continues to serve its remaining CLI/scripting/systemd consumers
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Running-State Seam | 0/TBD | Not started | - |
| 2. Zellij Plugin Feasibility | 0/TBD | Not started | - |
| 3. Core Lifecycle on Zellij | 0/TBD | Not started | - |
| 4. Hold/Resume on Zellij | 0/TBD | Not started | - |
| 5. Interaction Layer | 0/TBD | Not started | - |
| 6. Parity Cutover | 0/TBD | Not started | - |
