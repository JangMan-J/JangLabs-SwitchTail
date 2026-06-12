# Requirements: SwitchTail v0.1 (Switchboard Groundwork)

**Defined:** 2026-06-12
**Core value:** one-handed fleet control without losing the overview.

## v0.1 Requirements

### Directory & Model (DIR)

- [ ] **DIR-01**: `switchtail-core` maintains a live directory of every
  terminal pane (line) from `PaneUpdate`/`TabUpdate`: title, command, board
  (tab), exited/exit-status, focused, floating/suppressed.
- [ ] **DIR-02**: The core is pure Rust (no zellij dependency) and all model
  behavior is unit-tested (`cargo test` green).
- [ ] **DIR-03**: Host effects are expressed as `HostIntent` values returned
  by core operations; the plugin adapter is the only zellij-API caller.

### Deck & Patching (DECK)

- [ ] **DECK-01**: Every line gets a stable one-press deck key (digits, then
  letters); keys are sticky across pane updates and freed slots are reused.
- [ ] **DECK-02**: Pressing a deck key focuses that line (one press, any
  board).
- [ ] **DECK-03**: The operator can mark a seat and swap any selected line
  into it (`replace_pane_with_existing_pane`).
- [ ] **DECK-04**: The operator can type a message in the plugin and patch it
  through to the selected line (`write_chars_to_pane_id`).

### Call Log & Triage (LOG)

- [ ] **LOG-01**: Line lifecycle (opened/exited/closed/command-changed/
  cwd-changed) and operator/agent reports land on a capped call log.
- [ ] **LOG-02**: Calls carry triage state Ringing/Answered/Parked; the
  operator can answer, park, and manually ring from the plugin.
- [ ] **LOG-03**: The log view supports sort modes (ringing-first, newest,
  by-line) and the directory view shows per-line ringing indicators.
- [ ] **LOG-04**: Ringing is surfaced on the board itself CB-safely (amber
  tint + highlight; no red/green semantics).

### Pipes & Protocol (PIPE)

- [ ] **PIPE-01**: `zellij pipe -n switchtail` accepts the JSON ops
  `say|focus|ring|status|register|list|log`; malformed input never panics.
- [ ] **PIPE-02**: `list`/`log` answer on the CLI pipe with JSON
  (`cli_pipe_output`) — the scripting contract.
- [ ] **PIPE-03**: `register`/`status` attach label/kind/state metadata to a
  line, visible in the directory view.

### Plugin Shell (SHELL)

- [ ] **SHELL-01**: The plugin builds to `wasm32-wasip1`, loads in zellij
  0.45, requests only the declared minimal permissions, and renders the
  directory + log views.
- [ ] **SHELL-02**: `n` launches a new line in the current cwd (configurable
  `line_command`); the launch is tracked in directory + log.
- [ ] **SHELL-03**: A dev loop script and an install/keybind recipe exist
  (`tools/dev.sh`, README); a best-effort headless E2E smoke test exists.
- [ ] **SHELL-04**: No `close_*`/kill call sites in the adapter — enforced by
  a test.

## Out of Scope (v0.1)

| Feature | Reason |
|---------|--------|
| Hold/resume markers, agent-kind table, trunks/carts | Next milestones — groundwork first |
| In-plugin launcher/introspector for labs | Needs lifecycle layer first |
| Auto `/rename`+`/color` watcher behavior | Native rename/recolor exists; agent-driven styling comes with kinds |
| `stail` CLI rebuild / systemd units / `.desktop` entries | Pipe protocol covers scripting for now |
| Claude Code hook wiring for ring/status | Protocol is ready; wiring is a follow-on |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| DIR-01..03 | 1 | Pending |
| DECK-01 (assignment) | 1 | Pending |
| DECK-02..04 | 2 | Pending |
| LOG-01..03 | 1–2 | Pending |
| LOG-04 | 4 | Pending |
| PIPE-01..03 | 3 | Pending |
| SHELL-01..02 | 2 | Pending |
| SHELL-03..04 | 4 | Pending |
