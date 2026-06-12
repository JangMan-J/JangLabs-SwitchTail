# Requirements: SwitchTail (Zellij Foundation milestone)

**Defined:** 2026-06-11
**Core Value:** The operator can route, watch, park, and resume a fleet of Claude Code sessions one-handed — and the daily-driver cockpit never breaks while its foundation is being replaced.

## v1 Requirements

"v1" here = the current milestone (Zellij Foundation parity). The existing kitty system is the pre-GSD validated baseline, not this v1. Each requirement maps to a roadmap phase.

### Pre-Migration State Seam (SEAM)

- [ ] **SEAM-01**: `stail list` / `stail active` / `stail list --json` report board running state from stail-owned state, not from kdotool/KWin window-class search
- [ ] **SEAM-02**: kdotool usage is reduced to raise/focus only; running detection no longer depends on `os_window_class` stamping

### Zellij Plugin Foundation (PLUG)

- [ ] **PLUG-01**: A proof-of-concept SwitchTail plugin (Rust compiled to WASM) loads in Zellij, subscribes to pane lifecycle events, and renames/recolors a pane under explicitly declared minimal permissions
- [ ] **PLUG-02**: Each of kitty's four fused roles — mux/session grammar, scriptable window model, in-process watcher host, GUI host (rendering, window identity for raise/focus, launcher ownership, beyond-PATH resolution) — has a validated, recorded Zellij-era answer
- [ ] **PLUG-03**: Prior-art plugins (zellij-attention, zellaude, zellij-sessionizer/zjsh/zsm/zellij-switch, zellij-pane-picker/room) are each assessed with a build-on vs reimplement verdict

### Core Lifecycle on Zellij (LIFE)

- [ ] **LIFE-01**: Operator can launch or raise a lab's board of Claude Code lines on the Zellij backend
- [ ] **LIFE-02**: Operator can launch a single line with a minted per-pane session id and kind-table-derived argv + policy flags
- [ ] **LIFE-03**: Operator can open a trunk — N parallel lines for one lab on one board
- [ ] **LIFE-04**: Operator can patch a tabbed multi-lab board from a cart spec, including the all-labs exchange board
- [ ] **LIFE-05**: The agent-kind table remains the single source of fresh/continue argv and holdable/stylable policy on the Zellij path — no agent-kind literals in the plugin

### Hold / Resume (HOLD)

- [ ] **HOLD-01**: Holding a line writes a per-pane marker `hold/<lab>/<session-id>` and closes that line
- [ ] **HOLD-02**: A relaunched line claims a marker atomically and resumes that exact session (`claude --resume <id>`); the legacy cwd-scoped `--continue` fallback is preserved
- [ ] **HOLD-03**: Board- and fleet-level hold followed by re-patch resumes every parked line deterministically — no one-per-lab collapse, no concurrent-claim race

### Watcher / Attention (WATCH)

- [ ] **WATCH-01**: A freshly booted or resumed Claude line is auto-titled and colored per its kind, exactly once (idempotent; no boot-timing keystroke-as-prompt injection)
- [ ] **WATCH-02**: The watcher role runs under declared Zellij plugin permissions that structurally exclude destroying panes
- [ ] **WATCH-03**: A line that needs operator attention is visibly surfaced on the board

### Deck / Focus Control (DECK)

- [ ] **DECK-01**: Operator can focus any line on the active board one-handed via the numpad deck
- [ ] **DECK-02**: Operator can hot-seat swap lines (current swap-kitten behavior) on the Zellij board

### Cutover & External Surfaces (CUT)

- [ ] **CUT-01**: The Plasma 6 widget works unmodified against the Zellij backend through the same `stail --json` contract (running state, cart multi-select, per-row pane counts, patch)
- [ ] **CUT-02**: systemd user units regenerate Zellij board definitions when the workspace's lab membership changes
- [ ] **CUT-03**: Per-lab launcher entries open a lab's Zellij board, and `stail switch` raises an already-running board on Plasma/Wayland
- [ ] **CUT-04**: The regression suite covers the ported behavior set and runs green, with breadth ≥ the 147-assertion kitty baseline
- [ ] **CUT-05**: Zellij becomes the daily driver and kitty-specific surfaces are retired only after CUT-04 is green; until then the kitty system remains fully functional

## v2 Requirements

Deferred to future milestones. Tracked but not in the current roadmap.

### Zellij-Native Wins (ZNEXT)

- **ZNEXT-01**: Exploit Zellij-native detach/attach and session resurrection for logout/crash persistence beyond hold-marker parity
- **ZNEXT-02**: Foreign agent-kind rows (e.g. opencode) — added only after empirically verifying each agent's continue cwd-scoping
- **ZNEXT-03**: Spine evolution per language triggers T1–T5 (e.g. Python port of list/active on a second arbitrary-string `--json` field)
- **ZNEXT-04**: Non-KDE host support (drop the kdotool raise/focus path)

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| WezTerm / tmux-hybrid mux paths | Owner locked the Zellij pivot (2026-06-11); alternatives closed for this milestone |
| Mux-agnostic helper daemon | Report ranked last; trades the send-text-only safety property down to config policy |
| Bash spine rewrite during this milestone | Spine survives as the CLI; T1–T5 triggers noted, not preempted |
| Foreign agent kinds in this milestone | "Continue is cwd-scoped" unverifiable without running each agent; a wrong row cross-wires labs |
| Multi-box distribution / packaging | Single CachyOS/KDE box; T4 has not fired |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| SEAM-01 | Phase 1 | Pending |
| SEAM-02 | Phase 1 | Pending |
| PLUG-01 | Phase 2 | Pending |
| PLUG-02 | Phase 2 | Pending |
| PLUG-03 | Phase 2 | Pending |
| LIFE-01 | Phase 3 | Pending |
| LIFE-02 | Phase 3 | Pending |
| LIFE-03 | Phase 3 | Pending |
| LIFE-04 | Phase 3 | Pending |
| LIFE-05 | Phase 3 | Pending |
| HOLD-01 | Phase 4 | Pending |
| HOLD-02 | Phase 4 | Pending |
| HOLD-03 | Phase 4 | Pending |
| WATCH-01 | Phase 5 | Pending |
| WATCH-02 | Phase 5 | Pending |
| WATCH-03 | Phase 5 | Pending |
| DECK-01 | Phase 5 | Pending |
| DECK-02 | Phase 5 | Pending |
| CUT-01 | Phase 6 | Pending |
| CUT-02 | Phase 6 | Pending |
| CUT-03 | Phase 6 | Pending |
| CUT-04 | Phase 6 | Pending |
| CUT-05 | Phase 6 | Pending |

**Coverage:**
- v1 requirements: 23 total
- Mapped to phases: 23
- Unmapped: 0 ✓

---
*Requirements defined: 2026-06-11*
*Last updated: 2026-06-11 after roadmap creation (traceability populated)*
