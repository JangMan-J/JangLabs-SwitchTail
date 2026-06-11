# SwitchTail

SwitchTail is a one-handed agent switchboard for kitty terminal sessions.

It routes focus, commands, and attention across many agent CLI sessions using
kitty layouts, tabs, stacked panes, watcher injections, and operator keybinds.

> SwitchTail — route, watch, and coordinate agent CLI sessions in kitty.

SwitchTail is independent software built for use with the kitty terminal
emulator. It is not affiliated with, endorsed by, or maintained by the kitty
project.

## What it does

SwitchTail coordinates kitty terminal layouts and Claude Code agent sessions
across the labs of a multi-repo workspace (one cockpit window per lab). Five
surfaces stay in lockstep:

| Surface | Where | Role |
|---|---|---|
| `bin/stail` | CLI (`~/.local/bin/stail`) | Discover labs, generate kitty sessions + `.desktop` launchers, launch/raise/list cockpits (`generate` / `cockpit` / `fleet` / `build` / `active` / `list` / `switch`) |
| `kitty/*.py` | kitty kittens + watcher | `cockpit_park` (close ⇒ resume marker), `cockpit_bounce` (shell/cmd panes), `cockpit_monitor` (auto `/rename` + `/color` on claude pane boot) |
| `kitty/*.conf` | kitty config includes | Cockpit/deck keybindings and the monitor watcher hookup |
| `plasmoid/org.switchtail.board` | Plasma 6 panel widget | List labs with running state, multi-select a cart, set per-row pane counts, open one tabbed cockpit |
| `systemd/switchtail-sessions.*` | systemd user units | Watch `~/JangLabs/.gitmodules` / `.git/config`; regenerate sessions when labs change |

## Quick start

```bash
stail list            # every lab + running state
stail switch claude   # raise the claude cockpit (or launch it)
stail fleet agent 3   # one window, 3 claude panes for the agent lab
stail build lab=claude*2 lab=agent dir=/srv/work/app*2   # tabbed multi-lab cockpit
```

The Plasma widget drives the same `stail` commands from the panel.

## Runtime placement (hybrid, intentional)

- `bin/` and `kitty/` are **symlinked** into `~/.local/bin` / `~/.config/kitty`
  (relative links — survive a repo move).
- `plasmoid/` is **copied** to `~/.local/share/plasma/plasmoids/` (Plasma loads
  by real path, not through symlinks).
- `systemd/` units are **copied** to `~/.config/systemd/user/` (enabling creates
  `.wants` symlinks; don't double-symlink).
- State lives in `~/.local/state/switchtail/` (`<lab>.resume` markers).

Anything that calls `stail` from a non-login environment (the Plasma widget,
systemd units) must use the absolute path `~/.local/bin/stail` — GUI shells and
user units do not have `~/.local/bin` on `PATH`.

## Tests

```bash
tests/run-all.sh
```

Covers slug derivation, collision suffixing, tab packing, window-class rules,
the park/resume contract, and monitor idempotency.

## Environment

| Variable | Default | Meaning |
|---|---|---|
| `SWITCHTAIL_DIR` | `~/JangLabs` | The labs workspace to scan |
| `SWITCHTAIL_LAYOUT` | — | Cockpit tab layout override |
| `SWITCHTAIL_INCLUDE_SHELL` | `0` | Offer a shell pane per cockpit |
| `SWITCHTAIL_FLEET_MAX` | `12` | Max panes per fleet op |
| `SWITCHTAIL_TAB_SIZE` | `5` | Panes packed per cockpit tab |
