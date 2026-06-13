# Zellij plugin API — pinned facts (verified 2026-06-12)

Host binary: **zellij 0.45.0** (`/usr/bin/zellij`, pacman). Plugin SDK:
**zellij-tile 0.44.3** (latest on crates.io at pin time; plugins compiled
against an older zellij-tile run on newer hosts — that is Zellij's supported
compatibility direction). Verification method: signatures read from the
**vendored crate source** (`~/.cargo/registry/src/*/zellij-tile-0.44.3/` and
`zellij-utils-0.44.3/src/data.rs`), not from docs or training data. The
0.45-binary CLI surface was dumped from `zellij action --help` locally.

Target: `wasm32-wasip1` (rustup target installed). Plugin = **bin crate**;
`register_plugin!(State)` defines `main()` itself — do not write your own.

## Trait (zellij-tile/src/lib.rs)

```rust
pub trait ZellijPlugin: Default {
    fn load(&mut self, configuration: BTreeMap<String, String>) {}
    fn update(&mut self, event: Event) -> bool { false }   // true ⇒ render
    fn pipe(&mut self, pipe_message: PipeMessage) -> bool { false } // true ⇒ render
    fn render(&mut self, rows: usize, cols: usize) {}
}
```

## Events we rely on (zellij-utils data.rs `Event`, 0.44.3)

- `PaneUpdate(PaneManifest)` — `panes: HashMap<usize /*tab position*/, Vec<PaneInfo>>`
- `TabUpdate(Vec<TabInfo>)`
- `Key(KeyWithModifier)` — `{ bare_key: BareKey, key_modifiers: BTreeSet<KeyModifier> }`;
  `BareKey::Char(char)`, `Enter`, `Esc`, `Up`, `Down`, `Tab`, …
- `PermissionRequestResult(PermissionStatus)`
- `CommandPaneOpened(u32, Context)` / `CommandPaneExited(u32, Option<i32>, Context)`
- `PaneClosed(PaneId)`
- `CwdChanged(PaneId, PathBuf, Vec<ClientId>)`, `CommandChanged(PaneId, Vec<String>, bool, Vec<ClientId>)`
- `Timer(f64)` (armed via `set_timeout(secs: f64)`)
- `CustomMessage(String, String)` (from workers), `BeforeClose`, `Visible(bool)`

`PaneInfo` highlights: `id: u32`, `is_plugin`, `is_focused`, `is_fullscreen`,
`is_floating`, `is_suppressed`, `title: String`, `exited: bool`,
`exit_status: Option<i32>`, `terminal_command: Option<String>`,
`is_selectable`, `default_fg/bg: Option<String>`, geometry fields.

## Commands we rely on (zellij-tile shim, exact 0.44.3 signatures)

```rust
subscribe(event_types: &[EventType]); request_permission(permissions: &[PermissionType]);
focus_pane_with_id(pane_id: PaneId, should_float_if_hidden: bool, should_be_in_place_if_hidden: bool);
replace_pane_with_existing_pane(pane_id_to_replace: PaneId, existing_pane_id: PaneId, suppress_replaced_pane: bool); // one-way "bring pane here" (pane-picker primitive), NOT a swap; suppress=false CLOSES the replaced pane
open_terminal_pane_in_place_of_pane_id<P: AsRef<Path>>(pane_id: PaneId, cwd: P, close_replaced_pane: bool) -> Option<PaneId>; // close_replaced_pane=false ⇒ replaced pane suppressed, restored when the new pane closes
move_pane_with_pane_id_in_direction(pane_id: PaneId, direction: Direction); // TRUE positional swap, adjacent pane in a direction only (deferred shortcut)
write_chars_to_pane_id(chars: &str, pane_id: PaneId);   write_to_pane_id(bytes: Vec<u8>, pane_id: PaneId);
open_command_pane(cmd: CommandToRun, ctx: BTreeMap<String,String>) -> Option<PaneId>; // + _background / _floating / _near_plugin variants, same shape
open_terminal<P: AsRef<Path>>(path: P) -> Option<PaneId>;
rename_pane_with_id<S: AsRef<str>>(pane_id: PaneId, new_name: S);
set_pane_color(pane_id: PaneId, fg: Option<String>, bg: Option<String>); // String = color, e.g. "#rrggbb"
highlight_and_unhighlight_panes(to_highlight: Vec<PaneId>, to_unhighlight: Vec<PaneId>);
group_and_ungroup_panes(to_group: Vec<PaneId>, to_ungroup: Vec<PaneId>, for_all_clients: bool);
stack_panes(pane_ids: Vec<PaneId>); toggle_pane_id_fullscreen(pane_id: PaneId);
hide_self(); show_self(should_float_if_hidden: bool); set_selectable(bool);
cli_pipe_output(pipe_name: &str, output: &str); block_cli_pipe_input(pipe_name: &str); unblock_cli_pipe_input(pipe_name: &str);
pipe_message_to_plugin(message_to_plugin: MessageToPlugin);
get_plugin_ids() -> PluginIds; get_zellij_version() -> String;
set_timeout(secs: f64); report_panic(info: &std::panic::PanicHookInfo);
```

`CommandToRun { path: PathBuf, args: Vec<String>, cwd: Option<PathBuf> }`
(+ `::new(path)`, `::new_with_args(path, args)`).
`PaneId::{Terminal(u32), Plugin(u32)}`; `FromStr` accepts `terminal_<n>`,
`plugin_<n>`, or bare `<n>` (= terminal).

`PipeMessage { source: PipeSource, name: String, payload: Option<String>,
args: BTreeMap<String,String>, is_private: bool }`;
`PipeSource::{Cli(String /*pipe_id*/), Plugin(u32), Keybind}`.

## Permissions (0.44.3 `PermissionType`, non_exhaustive)

ReadApplicationState · ChangeApplicationState · OpenFiles · RunCommands ·
OpenTerminalsOrPlugins · WriteToStdin · WebAccess · ReadCliPipes ·
MessageAndLaunchOtherPlugins · Reconfigure · FullHdAccess · StartWebServer ·
InterceptInput · ReadPaneContents · RunActionsAsUser · WriteToClipboard ·
ReadSessionEnvironmentVariables

SwitchTail v0.1 declares ONLY: `ReadApplicationState`,
`ChangeApplicationState`, `OpenTerminalsOrPlugins`, `WriteToStdin`,
`ReadCliPipes`. Deliberately absent: `RunCommands`, `WebAccess`,
`FullHdAccess`, `InterceptInput`, `RunActionsAsUser`.

## Host-side CLI (zellij 0.45.0, dumped locally)

- `zellij action focus-pane-id <terminal_N|plugin_N|N>` · `write-chars -p <id>` ·
  `stack-panes` · `set-pane-color` · `rename-pane` · `list-panes` · `list-clients` ·
  `dump-screen [--full]` · `dump-layout` · `start-or-reload-plugin <url>` ·
  `launch-or-focus-plugin <url>` (returns `plugin_<id>`)
- `zellij pipe --name <pipe> [--plugin <url>] -- <payload>` (stdin/stdout piping
  supported; payload lines stream to the plugin's `pipe()` hook)

## Dev loop

```bash
CARGO_BUILD_JOBS=4 cargo build -p switchtail --target wasm32-wasip1
zellij action start-or-reload-plugin "file:$PWD/target/wasm32-wasip1/debug/switchtail.wasm"
```

Keybind (user config, `~/.config/zellij/config.kdl`):

```kdl
keybinds {
    shared_except "locked" {
        bind "Alt s" {
            LaunchOrFocusPlugin "file:~/.local/share/zellij/plugins/switchtail.wasm" {
                floating true
                move_to_focused_tab true
            }
        }
    }
}
```

Plugin panics land in zellij's log dir
(`/tmp/zellij-<uid>/zellij-log/zellij.log`) — as does plugin `eprintln!`
output (handy tracing channel).

## Empirically verified facts (cost a debug loop each — trust these)

- **CLI pipe replies route by pipe-ID, not name.** `PipeSource::Cli(pipe_id)`
  carries a per-invocation UUID; `cli_pipe_output(pipe_id, …)` and
  `unblock_cli_pipe_input(pipe_id)` must target that id. Passing the pipe
  *name* silently drops the output (no error), and a never-unblocked CLI
  pipe hangs the `zellij pipe` caller forever.
- **First plugin load requires interactive permission approval**, which hangs
  headless sessions. The grant cache is `<cache>/zellij/permissions.kdl`
  (KDL: quoted-plugin-key node + permission-name children). The cache key for
  `file:` plugins is the **bare absolute wasm path** (`RunPluginLocation::File`
  Display). Headless/E2E runs pre-seed an isolated cache via
  `XDG_CACHE_HOME` (see `tests/e2e.sh`).
- **`dump-screen` (0.45) prints to the client's stdout** and takes
  `-p/--pane-id`; it no longer takes a file path argument (0.44-era docs say
  otherwise). A file argument fails with exit 2.
- Headless boot works fine via `script -qec "stty cols 140 rows 40; zellij
  --session <name>" /dev/null &`, then `zellij --session <name> action …`
  from outside the pty.
- **`replace_pane_with_existing_pane` is one-way, NOT a swap** (proven at host
  commit e9173cb: screen.rs:4486, tab/mod.rs:4069 `extract_pane`,
  tab/mod.rs:2337 `suppress_pane_and_replace_with_other_pane`). It is the
  pane-picker primitive: the host extracts `existing_pane_id`, places it in
  `pane_id_to_replace`'s geometry, and either suppresses the replaced pane
  (`suppress=true`, recoverable via `focus_pane_with_id`) or **closes** it
  (`suppress=false`). The replaced pane is never placed into the existing
  pane's old slot — there is no positional exchange.
- **No `swap_panes(a,b)` primitive exists** anywhere in the plugin API
  (exhaustive PluginCommand scan, zellij-utils 0.44.3 + host commit e9173cb).
- **Composed positional exchange (the seat-swap recipe)** — to make panes A
  and B trade slots with the layout otherwise unchanged:
  1. `open_terminal_pane_in_place_of_pane_id(B, ".", false)` → placeholder P
     pins B's slot (B becomes suppressed but stays pid-addressable; the host
     `extract_pane` has a suppressed-pane branch).
  2. `replace_pane_with_existing_pane(A, B, true)` → B takes A's slot, A
     suppressed (still addressable).
  3. `replace_pane_with_existing_pane(P, A, false)` → A takes P's slot
     (= B's original slot); plugin-owned P closes.
  The three plugin commands process in dispatch order (FIFO). [Live FIFO +
  suppressed-restore findings to be appended after 04-06 Task 4.]
- **`move_pane_with_pane_id_in_direction(pane_id, direction)` IS a true
  positional swap**, but only with the adjacent pane in the given direction —
  a cheaper shortcut for the adjacent common case (deferred; needs geometry
  in PaneSnapshot + adjacency math in core).
