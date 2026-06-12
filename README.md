# SwitchTail

**The operator's switchboard for agentic terminals — a Zellij plugin.**

SwitchTail is a window-manager-grade control plugin for [Zellij](https://zellij.dev),
built for running fleets of agentic development terminals (Claude Code and
friends): one-press focus to any line by ID, hot-seat swap into the main seat,
per-line message send/receive, and a live call log of everything the fleet
does — monitored, triaged, categorized, sorted, without leaving the board.

Vocabulary (retro telephony — it names the types, the keys, and the docs):
the Zellij session is the **exchange**; a tab of panes is a **board**; one
terminal pane is a **line**; the main working position is the **seat**; the
one-press key map is the **deck**; connecting anything to anything is
**patch**ing; the live event feed is the **call log**; a line that wants the
operator is **ringing** until it's **answered** or **parked**.

## Build & install

```bash
tools/dev.sh test      # unit tests (pure core + guards)
tools/dev.sh build     # debug wasm (target/wasm32-wasip1/debug/switchtail.wasm)
tools/dev.sh install   # release wasm → ~/.local/share/zellij/plugins/
tests/e2e.sh           # headless smoke against a scripted zellij session
```

Bind it in `~/.config/zellij/config.kdl`:

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

Plugin configuration (optional): `line_command "claude"` — what the `n` key
launches on a new line (default: a shell).

## Operating the switchboard

| Key | Action |
|---|---|
| `1`–`9`, `0` | Jump: focus that deck line, one press |
| `j`/`k`, `↑`/`↓`, `Enter` | Select / focus beyond the deck |
| `m` | Mark the selected line as the **seat** |
| `s` | Swap the selected line into the seat |
| `i` | Patch a message through: type, `Enter` sends to the line |
| `a` / `p` / `R` | Answer / park / ring the selection |
| `Tab` | Directory ⇄ call log |
| `o` | Cycle sort: deck · ringing-first · board |
| `n` | Open a new line |
| `Esc` | Hide the switchboard |

## Scripting (the pipe contract)

External processes drive the switchboard by line ID over the `switchtail`
pipe — agent hooks report in the same way:

```bash
zellij pipe -n switchtail -- '{"op":"list"}'                  # JSON directory
zellij pipe -n switchtail -- '{"op":"log","n":50}'            # JSON call log
zellij pipe -n switchtail -- '{"op":"say","line":3,"text":"continue"}'
zellij pipe -n switchtail -- '{"op":"focus","line":"terminal_3"}'
zellij pipe -n switchtail -- '{"op":"ring","line":3,"note":"needs review"}'
zellij pipe -n switchtail -- '{"op":"status","line":3,"state":"blocked"}'
zellij pipe -n switchtail -- '{"op":"register","line":3,"label":"synapse","kind":"claude"}'
```

## Architecture

`crates/switchtail-core` is the pure switchboard model (no Zellij
dependency, fully unit-tested); `crates/switchtail-plugin` is a thin adapter
that maps Zellij events into the model and the model's `HostIntent`s onto
exactly one shim call each. The adapter declares minimal permissions and has
no pane-destroying call sites — enforced by a guard test. Design contract:
`docs/DESIGN.md`; pinned API facts: `docs/zellij-api-notes.md`.

> History: the previous kitty-based SwitchTail is retired and fully preserved
> — git tag `kitty-era-final`, archive `~/JangLabs/.archive/switchtail-kitty-era/`
> (see its `RESTORE.md`), lessons in `docs/legacy-learnings.md`.
