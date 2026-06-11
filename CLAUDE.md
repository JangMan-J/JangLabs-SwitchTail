# switchtail — agent conventions

> **Lab scope — `switchtail/`** · nested repo [`JangLabs-SwitchTail`](https://github.com/JangMan-J/JangLabs-SwitchTail). This file is the authority for work *inside this lab* and **overrides** the workspace root [`../CLAUDE.md`](../CLAUDE.md). Stay in this lab — don't reach into or edit sibling labs from here.

## What lives here

SwitchTail: a one-handed agent switchboard for kitty terminal sessions (see
`README.md`). Five surfaces — CLI (`bin/stail`), kitty kittens + confs
(`kitty/`: hold, swap, tail watcher, keys), a Plasma 6 widget
(`plasmoid/org.switchtail.board`), systemd user units (`systemd/`), and the
regression suite (`tests/`). Vocabulary is retro telephony: board (a lab's
window), line (one agent pane), trunk (N lines, one lab), patch (assemble a
board), hold (close-for-resume), exchange (the all-labs board).

## The window-class contract (highest-risk invariant)

Six points must stay in lockstep or switch/hold/list silently degrade:

1. CLI emits class `switchtail-<lab>` (exchange: `switchtail-exchange`).
2. Generated sessions set `os_window_class switchtail-<lab>`.
3. Generated `.desktop` files set `StartupWMClass=switchtail-<lab>`.
4. Kittens read the `--var kind=<kind>` / `--var lab=<lab>` user-vars the CLI passes.
5. `kdotool` greps that class for running detection (`_running_labs` in `bin/stail`).
6. The widget keys running state off the same class via `stail list --json`.

A second 2-way contract: the hold kitten writes
`~/.local/state/switchtail/<lab>.hold`; `stail line` reads it to decide
fresh start vs `claude --continue`. Change the state-dir name in both places or
not at all.

## Runtime placement rules

- `bin/`, `kitty/`, `tests/` → **relative symlinks** from their live locations
  into this repo. Edits here are live immediately (kitty picks them up on next
  launch).
- `plasmoid/` → **copied** to `~/.local/share/plasma/plasmoids/` — Plasma loads
  by real path. After editing QML here, re-copy and restart plasmashell
  (`systemctl --user restart plasma-plasmashell.service`).
- `systemd/` → **copied** to `~/.config/systemd/user/`. On a unit rename, do the
  disable → replace files → `daemon-reload` → enable dance; never just `mv`.

## PATH discipline (hard-won)

plasmashell, systemd user units, and other GUI-spawned processes do **not**
have `~/.local/bin` on PATH. Anything they invoke must use the absolute path
(`$HOME/.local/bin/stail`); a bare-name `exec stail` in a shim dies silently.
Diagnose "works in my shell, fails from the widget" by replaying the command
under the spawner's env from `/proc/<pid>/environ`.

## Verification gate

`tests/run-all.sh` (147 assertions) is the functional ground truth — run it
green before any commit that touches `bin/stail`, the kittens, or the tests.
QML changes are verified by redeploy + plasmashell restart + a clean
`journalctl --user -u plasma-plasmashell` (no errors naming the applet).

## Branch model

`main` is stable/release; the long-lived `versioning` branch carries all WIP
and session checkpoints. Work on `versioning`, merge to `main` when stable.
