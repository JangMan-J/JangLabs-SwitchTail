# Stack Research — SwitchTail v0.2 (in-plugin composition)

**Domain:** Zellij plugin (Rust → wasm32-wasip1) — tab and pane creation API
**Researched:** 2026-06-13
**Confidence:** HIGH (all signatures read from vendored source; no training-data assertions)

**Source of truth:** `~/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/zellij-tile-0.44.3/src/shim.rs` and `zellij-utils-0.44.3/src/data.rs`. Every claim below includes a file:line citation.

---

## Core Finding: The Two Paths to "Spawn a Board"

There are two distinct API surfaces for creating a new tab (board) from a plugin. They differ in whether the pane to show in the new tab already exists or needs to be created simultaneously.

### Path A — `new_tab`: create an empty tab, then open panes into it

```rust
// shim.rs:949–962
pub fn new_tab<S: AsRef<str>>(name: Option<S>, cwd: Option<S>) -> Option<usize>
where S: ToString
```

- Returns `Option<usize>` — the tab index of the newly created tab, or `None` on failure.
- The new tab opens with the session's default layout (typically one empty tiled pane, same as the user pressing `Alt+t`).
- **Does not take a `CommandToRun`.** The tab opens with whatever the default layout spawns; you cannot specify a command here.
- After calling `new_tab`, the newly created tab becomes focused. Subsequent `open_command_pane` / `open_terminal` calls open panes on the **currently focused tab**, which will be this new tab — so a `new_tab` call followed immediately by `open_command_pane` reliably places the pane on the new board, provided no intervening tab-focus change occurs.
- `data.rs:3365–3368` shows the `PluginCommand::NewTab { name: Option<String>, cwd: Option<String> }` variant.

### Path B — `open_command_pane_in_new_tab`: create a tab + first pane atomically

```rust
// shim.rs:966–979
pub fn open_command_pane_in_new_tab(
    command_to_run: CommandToRun,
    context: BTreeMap<String, String>,
) -> (Option<usize>, Option<PaneId>)
```

- Returns `(tab_id, pane_id)` — both the new tab index and the new pane's `PaneId`.
- This is the **recommended primitive for board creation in v0.2**: one call atomically creates the board and its first line (running `claude` or the configured command). The return values let the core immediately register both the board and the line without waiting for `TabUpdate`/`PaneUpdate`.
- `data.rs:3583` confirms `OpenCommandPaneInNewTab(CommandToRun, Context)` in the `PluginCommand` enum.
- `data.rs:3617–3620`: `OpenPaneInNewTabResponse { tab_id: Option<usize>, pane_id: Option<PaneId> }` is the response type.

There is **no** `open_terminal_in_new_tab` shim function. The terminal-in-new-tab path does not exist as a dedicated call. If a bare shell is needed on a new board, use `open_command_pane_in_new_tab` with `CommandToRun::new(shell_path)` or call `new_tab` followed by `open_terminal`.

---

## Opening Multiple Panes Programmatically

### On the current (focused) board

The existing `HostIntent::OpenLine` already handles this via `open_command_pane` / `open_terminal` (shim.rs:591–603 / shim.rs:491–501). Calling it N times in a loop is supported. Each call invokes `host_run_plugin_command()` synchronously from the plugin's perspective — the host queues the commands FIFO and processes them in order.

### On a specific board by index (not the focused one)

There is no "open a pane on tab N" primitive that takes a tab index. The API surface for this is:

1. **`break_panes_to_new_tab`** (shim.rs:2352–2368) — moves existing panes (by `PaneId`) into a new tab. Not useful for creation.
2. **`break_panes_to_tab_with_index`** (shim.rs:2372–2389) — moves existing panes to an existing tab by index. Again, moves existing panes only.

**Implication for N-line board spawning:** To open N lines on a new board, the pattern is:

```
open_command_pane_in_new_tab(cmd, ctx)  // → (tab_id, first_pane_id), new tab now focused
open_command_pane(cmd, ctx)             // opens on focused tab (the new board)  ×(N-1)
```

This is the only viable sequence. It relies on the new tab remaining focused for the duration of the dispatch loop.

---

## Async/Ordering Caveats

**Plugin commands are synchronous from the plugin's side.** Each shim call serializes to stdout, calls `host_run_plugin_command()`, and (for commands that return a value) reads back a response via `bytes_from_stdin()` before returning. The host processes them in the order received. Commands that do not return a value (like `open_terminal`, which does in 0.44.3 actually return `Option<PaneId>`) are still awaited before the next shim call executes.

**State update events (`TabUpdate`, `PaneUpdate`) arrive asynchronously** and are delivered to `update()` in a later turn. The plugin's dispatch loop for a single key-press runs to completion before any `TabUpdate` can arrive. This means:

- If v0.2's "spawn N lines on a new board" is implemented as a single `dispatch(intents)` call emitting `[SpawnBoard, OpenLine, OpenLine, ...]` in one Vec, the pane opens happen within the same dispatch turn and the new-tab focus is maintained throughout.
- The plugin will not have seen a `TabUpdate` confirming the new board before the subsequent `OpenLine` intents run. This is fine — the host's FIFO ordering guarantees the panes land on the correct tab regardless of whether the plugin has observed the `TabUpdate` yet.
- **Do not** try to read back `get_focused_pane_info()` or similar between spawns in the same dispatch turn to verify tab focus — this adds synchronous round-trips and is unnecessary given FIFO ordering.

**Ordering within a loop:** Calling `open_command_pane_in_new_tab` once, then `open_command_pane` N-1 times in the same dispatch iteration is deterministically correct. The host processes commands in dispatch order (FIFO), so the new tab will be focused before the subsequent pane-open commands arrive.

---

## Permission Story

**Current declared permissions** (main.rs:25–31):
```
ReadApplicationState, ChangeApplicationState, OpenTerminalsOrPlugins, WriteToStdin, ReadCliPipes
```

**Required permissions for v0.2 board+line creation** — CORRECTED 2026-06-13
against Zellij's official command reference
(https://zellij.dev/documentation/plugin-api-commands.html), which is the
authoritative per-command permission map. The vendored zellij-tile/utils
source on disk does NOT contain the host-side `PluginCommand → PermissionType`
mapping (that lives in `zellij-server`, not a build-dep of the plugin), so the
permission column could only be settled from the docs. The earlier conclusion
in this file ("OpenTerminalsOrPlugins covers open_command_pane") was WRONG —
the doc-string overlap between `ChangeApplicationState` ("…and run commands")
and `RunCommands` is a red herring.

| Operation | Required Permission (official docs) | Declared in v0.1? |
|-----------|--------------------------------------|--------------------|
| `new_tab(...)` | `ChangeApplicationState` | YES |
| `open_command_pane_in_new_tab(...)` | **`ChangeApplicationState`** | YES |
| `open_command_pane(...)` on existing board | **`RunCommands`** | **NO — withheld** |
| `open_command_pane_near_plugin(...)` | **`RunCommands`** | **NO — withheld** |
| `open_terminal(...)` on existing board | `OpenTerminalsOrPlugins` | YES |

**The crux:** spawning a **board** running `claude` is permission-clean today
(`open_command_pane_in_new_tab` needs only `ChangeApplicationState`). Spawning a
**line** running `claude` on an *existing* board needs `open_command_pane` →
**`RunCommands`**, which v0.1 deliberately withheld. v0.1's `n` key never hit
this because it defaulted to an empty command (→ `open_terminal`, permitted).

**OWNER DECISION (2026-06-13): DECLARE `RunCommands`.** v0.2 adds
`RunCommands` to the declared permission set, enabling native
`open_command_pane` for command-running lines (proper command panes with
re-run + exit-status UI — valuable for restartable agent sessions). This is a
deliberate, traceable revision of v0.1's "withhold RunCommands" minimal-surface
stance. Cost accepted: wider permission surface + a one-time re-prompt on first
launch after the change. The `open_terminal`+`write_chars` workaround was
considered and rejected in favor of native command panes.

---

## Recommended Primitives for v0.2

### New HostIntent variants to add

```rust
// Spawn a new board with one line already running `command`.
// Returns (board_tab_id, first_line_pane_id) from open_command_pane_in_new_tab.
SpawnBoard { command: Vec<String> }

// Open N additional lines on the currently-focused board (existing OpenLine covers 1).
// For N>1, core emits N OpenLine intents in sequence; adapter dispatches them.
// No new intent shape needed — reuse OpenLine N times.
```

Or, more precisely: `SpawnBoard` is the new intent; the adapter dispatches it as `open_command_pane_in_new_tab`. For N lines on the new board, core emits `SpawnBoard` + `(N-1)` × `OpenLine` in a single returned `Vec<HostIntent>`. The adapter's FIFO dispatch order guarantees they all land on the new board.

For lines on the **current** board, the existing `OpenLine` intent + `open_command_pane` / `open_terminal` shim (already dispatched) is sufficient for the N=1 case and for N>1 by emitting N `OpenLine` intents.

### Shim calls summary (exact signatures, file:line)

```rust
// shim.rs:949  — create an empty new tab, returns tab index
fn new_tab<S: AsRef<str>>(name: Option<S>, cwd: Option<S>) -> Option<usize>

// shim.rs:966  — create new tab + command pane atomically; RECOMMENDED for SpawnBoard
fn open_command_pane_in_new_tab(
    command_to_run: CommandToRun,
    context: BTreeMap<String, String>,
) -> (Option<usize>, Option<PaneId>)

// shim.rs:591  — open command pane on focused tab (existing, used by OpenLine)
fn open_command_pane(
    command_to_run: CommandToRun,
    context: BTreeMap<String, String>,
) -> Option<PaneId>

// shim.rs:491  — open shell terminal on focused tab (existing, used by OpenLine)
fn open_terminal<P: AsRef<Path>>(path: P) -> Option<PaneId>

// shim.rs:1345 — focus or create a tab by name; returns tab index
fn focus_or_create_tab(tab_name: &str) -> Option<usize>

// shim.rs:1441 — rename a tab by position (u32)
fn rename_tab<S: AsRef<str>>(tab_position: u32, new_name: S)

// shim.rs:1452 — rename a tab by stable id (u64)
fn rename_tab_with_id<S: AsRef<str>>(tab_id: u64, new_name: S)
```

---

## What NOT to Use

| Avoid | Why |
|-------|-----|
| `new_tabs_with_layout(layout: &str)` (shim.rs:927) | Takes a KDL layout string; overkill for simple board+line creation; requires layout serialization. Use `open_command_pane_in_new_tab` instead. |
| `new_tabs_with_layout_info(layout_info: L)` (shim.rs:938) | Same concern; `LayoutInfo` struct adds complexity with no benefit for N-line creation. |
| `break_panes_to_new_tab` (shim.rs:2352) | Moves *existing* panes into a new tab; not a creation primitive. |
| Reading `TabUpdate` between spawns | `TabUpdate` arrives asynchronously in a later `update()` turn; the dispatch loop completes before any event arrives. FIFO ordering makes mid-loop state-checks unnecessary and wasteful. |
| `open_terminal_in_new_tab` | Does not exist in shim.rs 0.44.3. Use `open_command_pane_in_new_tab` with a shell path instead. |

---

## Alternatives Considered

| Recommended | Alternative | Why Not |
|-------------|-------------|---------|
| `open_command_pane_in_new_tab` for SpawnBoard | `new_tab` + `open_command_pane` (two calls) | Two-call sequence works but the single-call version atomically returns both tab_id and pane_id, which the core needs to register the board and first line immediately. |
| `open_command_pane` × N for N lines on current board | `open_command_pane_in_new_tab` × N | Only the first call should create a new board; subsequent line opens go on the already-focused board via `open_command_pane`. |

---

## Sources

- `~/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/zellij-tile-0.44.3/src/shim.rs` — all shim function signatures (HIGH confidence; vendored source)
- `~/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/zellij-utils-0.44.3/src/data.rs` — `PluginCommand` enum, `PermissionType` enum and display names, response type aliases (HIGH confidence; vendored source)
- `docs/zellij-api-notes.md` — empirically verified FIFO ordering, `replace_pane_with_existing_pane` semantics, existing permission declarations (HIGH confidence; project-verified)
- `crates/switchtail-plugin/src/main.rs` — existing declared permissions (HIGH confidence; live code)

---
*Stack research for: SwitchTail v0.2 — in-plugin board+line composition*
*Researched: 2026-06-13*
