# SwitchTail v0.1 — the operator's switchboard (design)

## The metaphor IS the architecture

SwitchTail models a manual telephone exchange. The vocabulary is not flavor —
it names every type, module, and key in the system:

| Term | Meaning | In code |
|---|---|---|
| **Exchange** | The Zellij session — everything the operator can reach | `Exchange` (root model in `switchtail-core`) |
| **Board** | A tab full of lines | `Board` (tab position + name) |
| **Line** | One terminal pane, usually an agent CLI session | `Line` (registry entry keyed by `LineId`) |
| **Seat** | The main working position on a board | `seat: Option<LineId>` |
| **Deck** | The one-press key→line map (digits first, then home row) | `Deck` |
| **Patch** | Connecting things: focus a line, swap it into the seat, route text to it | `patch_*` operations |
| **Trunk** | N parallel lines launched for one purpose | `trunk` launch op (post-v0.1) |
| **Call log** | The live event feed of everything the fleet does | `CallLog` (ring buffer) |
| **Call** | One event on the log | `Call { line, kind, note, triage }` |
| **Ringing** | A line/call needing operator attention | `Triage::Ringing` |
| **Answered** | Seen by the operator | `Triage::Answered` |
| **Parked** | Acknowledged & muted | `Triage::Parked` |
| **Operator** | You | — |

## Crates

- **`switchtail-core`** — pure Rust, zero Zellij deps, fully unit-tested. Owns
  the model: directory of lines, deck assignment, seat, call log, triage,
  sorting/filtering, and the wire protocol (pipe ops). Everything decidable
  without a host is decided here.
- **`switchtail`** (plugin, `wasm32-wasip1` bin) — thin adapter: maps zellij
  `Event`s into core mutations, maps core *intents* into shim calls, renders
  the core's view model as ANSI rows. No business logic.

The adapter emits **intents** (`enum HostIntent { FocusLine(LineId),
SwapIntoSeat{..}, Say{..}, Ring{..}, … }`) returned by core operations, so the
core stays host-free and the shim layer stays a dumb dispatcher — this is the
expandability seam: new capability = new intent + one dispatcher arm.

## v0.1 capabilities (groundwork)

1. **Directory** — live registry of every terminal pane (line) in the
   exchange, fed by `PaneUpdate`/`TabUpdate`; tracks title, command, exited,
   focus, board, floating/suppressed. Plugin/UI panes are not lines.
2. **Deck (one-press switch)** — stable quick keys `1-9 0 q w e r t y …`
   assigned per line; sticky across updates; freed slots are reused lowest
   first. Pressing the key patches focus through:
   `focus_pane_with_id(line, true, false)`.
3. **Seat swap (hot-seat)** — `m` marks the selected line as the seat;
   pressing `s` on a selection swaps it into the seat via
   `replace_pane_with_existing_pane(seat, selected, false)`.
4. **Patch-through messaging** —
   - *Inbound to a line:* select + `i` opens an input prompt in the plugin;
     Enter sends via `write_chars_to_pane_id` (with `\r` termination optional
     via `Alt+Enter` = without).
   - *External, by ID:* `zellij pipe -n switchtail -- '<op>'` with a small
     JSON protocol (below). The plugin answers queries on the same pipe via
     `cli_pipe_output` — the `stail --json` contract spirit, reborn.
5. **Call log** — capped ring (512) of calls: line opened / exited / closed /
   command changed / cwd changed / status reports / rings. Triage keys:
   `a` answer · `p` park · `R` ring (manual flag). Views: Directory ⇄ Log
   (`Tab`), sort cycle `o`: ringing-first / newest / by-line.
6. **Attention surface** — ringing lines get a CB-safe amber tint
   (`set_pane_color`) and `highlight_and_unhighlight_panes`; cleared when
   answered/parked. **Never encode meaning red↔green** (operator runs a
   daltonized theme): states use blue↔amber + lightness + a text/shape cue.
7. **Launch** — `n` opens a new line in the current board's cwd
   (`open_command_pane_background`, command from plugin config
   `line_command`, default `$SHELL`). Trunks and kind tables come later.

## Wire protocol (pipe `switchtail`)

One JSON object per payload line; `line` accepts `terminal_N` / `N`:

```json
{"op":"say","line":"terminal_3","text":"hello\r"}
{"op":"focus","line":"3"}
{"op":"ring","line":"3","note":"needs review"}
{"op":"status","line":"3","state":"working|blocked|done","note":"…"}
{"op":"register","line":"3","label":"synapse","kind":"claude"}
{"op":"list"}                     → cli_pipe_output: JSON directory dump
{"op":"log","n":50}               → cli_pipe_output: JSON call log tail
```

`status`/`ring` from an agent hook is the intended fleet integration: a
Claude Code Stop/Notification hook pipes `{"op":"ring",…}` and the board
lights up. (Hook wiring itself is post-v0.1.)

## Permissions (structural safety)

Declared: `ReadApplicationState`, `ChangeApplicationState`,
`OpenTerminalsOrPlugins`, `WriteToStdin`, `ReadCliPipes`.
Withheld: `RunCommands`, `WebAccess`, `FullHdAccess`, `InterceptInput`,
`RunActionsAsUser`. Honesty note: `ChangeApplicationState` could close panes;
SwitchTail's no-kill property at this layer is *code discipline* (no
`close_*` call sites — enforced by a unit test grepping the shim-adapter) +
the withheld permissions. The kitty era had discipline only; this is
discipline + a smaller blast radius.

## Out of scope for v0.1 (deliberately)

Hold/resume markers, agent-kind table, trunks/cart patching, in-plugin
launcher-introspector browsing labs, auto-title/color watcher behavior,
`stail` CLI rebuild. The groundwork (registry + deck + seat + pipes + call
log + intents seam) is what makes each of these a small follow-on.
