# SwitchTail cockpit monitor — a kitty GLOBAL watcher (loaded via `watcher cockpit_monitor.py`
# in kitty.conf). It is the persistent, in-kitty "cockpit monitor": it watches every window in
# the kitty process and acts on the ones that belong to a SwitchTail cockpit (tagged --var cockpit=…).
#
# SLICE 1 (this file): when a SwitchTail claude pane finishes booting, auto-run the client-side slash
# commands `/rename` (Claude summarizes the session into a short title) and `/color` (Claude picks
# an unused statusline color). These are CLIENT-side Claude Code commands — no `claude` CLI flag
# fires them, so the only way to trigger them is to type them into the running TUI. A watcher can,
# because it runs INSIDE kitty and drives the remote-control API in-process via
# boss.call_remote_control() — so this needs NO `allow_remote_control` / `listen_on` socket and
# opens no external attack surface.
#
# SAFETY (this watcher cost a real incident once — a stray window-close killed a live cockpit):
#   * It ONLY ever calls `send-text`. There is deliberately NO close/kill/quit path anywhere in
#     this file, so it structurally cannot destroy a pane.
#   * It acts ONLY on windows tagged `cockpit=claude` (SwitchTail agent panes). Shell panes (cockpit=
#     shell), cmd panes (cockpit=cmd), and any non-stail kitty window are ignored.
#   * It is idempotent: once it has styled a pane it sets the `cockpit_styled` user_var and never
#     touches that pane again — so a resume / re-attach / config-reload cannot re-fire it, and it
#     never re-types into a pane where you may already be working.
#
# Timing: on_load fires when the window is CREATED — too early, claude's TUI is still starting and
# keystrokes sent then are lost. So we wait, then send. To be robust against a slow boot we make a
# few spaced attempts and stop as soon as the pane is marked styled (an attempt marks it). The
# delays are deliberately short and few — this is a nudge, not a guarantee; if claude is extremely
# slow the worst case is the commands don't fire (a no-op), never a wrong action.
#
# kitty internals are not a stable API, so we lean on the documented remote-control surface
# (send-text) and the documented watcher callbacks (on_load) rather than poking boss internals.

from typing import Any

from kitty.boss import Boss
from kitty.fast_data_types import add_timer
from kitty.window import Window

# The pane kinds (the --var cockpit=<kind> a SwitchTail pane carries) this slice styles. Only claude
# panes get /rename + /color; shell/cmd panes are SwitchTail panes but are not claude sessions.
_STYLE_KINDS = ("claude",)

# Marker user_var set once a pane has been styled — the idempotency guard.
_STYLED_VAR = "cockpit_styled"

# Marker set as soon as the delayed sends are scheduled, so repeated resizes before the first
# send lands don't pile up duplicate timers.
_SCHEDULED_VAR = "cockpit_scheduled"

# When (seconds after load) to attempt the send, and how many times. A couple of spaced tries
# absorb a slow claude boot; the first successful attempt marks the pane and the rest no-op.
_ATTEMPT_DELAYS = (1.2, 2.5, 4.5)

# The client-side commands to type, in order. `\r` submits each (carriage return = Enter in the
# TUI). Sent as one send-text payload; claude processes them as two separate submissions.
_STARTUP_KEYS = "/rename\r/color\r"


def _is_cockpit_claude(window: Window) -> bool:
    """True iff this window is a stail claude agent pane we should style."""
    try:
        uv = window.user_vars or {}
    except Exception:
        return False
    return uv.get("cockpit") in _STYLE_KINDS


def _already_styled(window: Window) -> bool:
    try:
        return (window.user_vars or {}).get(_STYLED_VAR) == "1"
    except Exception:
        return False


def _send_startup_commands(boss: Boss, window: Window) -> None:
    """Type /rename + /color into the pane, once, and mark it styled. send-text only — no close."""
    if _already_styled(window):
        return
    try:
        # Mark FIRST so a slow/duplicate attempt can't double-type even if send-text below races.
        window.set_user_var(_STYLED_VAR, "1")
    except Exception:
        # If we can't mark it, bail rather than risk repeated typing on later attempts.
        return
    try:
        boss.call_remote_control(
            window,
            ("send-text", f"--match=id:{window.id}", _STARTUP_KEYS),
        )
    except Exception:
        # Never let a watcher exception escape (kitty prints it to stderr but the pane is fine).
        pass


def on_load(boss: Boss, data: dict[str, Any]) -> None:
    # Module load hook (called once). Nothing to initialize for slice 1.
    pass


# NOTE: the per-window creation hook. For a GLOBAL watcher kitty calls the lifecycle callbacks
# below with the Window the event is for. We use the first resize (which fires at creation, with a
# zeroed old_geometry) as the "window created" signal, then schedule the delayed send. We avoid
# acting on every resize via the _STYLED_VAR guard.
def _scheduled(window: Window) -> bool:
    try:
        return (window.user_vars or {}).get(_SCHEDULED_VAR) == "1"
    except Exception:
        return False


def on_resize(boss: Boss, window: Window, data: dict[str, Any]) -> None:
    # on_resize fires per-window for a global watcher, INCLUDING once at creation (kitty docs: the
    # creation resize has an all-zero old_geometry). We use it as the "window created" signal. Act
    # only for a cockpit claude pane that is neither already styled nor already scheduled — the
    # _SCHEDULED_VAR guard stops a later resize (drag, layout change) from piling up more timers
    # before the first send lands. (The send itself is also idempotent via _STYLED_VAR.)
    if not _is_cockpit_claude(window) or _already_styled(window) or _scheduled(window):
        return
    try:
        window.set_user_var(_SCHEDULED_VAR, "1")
    except Exception:
        return  # if we can't mark it scheduled, don't risk re-scheduling on every resize
    win_id = window.id

    def _attempt(timer_id: int | None = None) -> None:
        w = boss.window_id_map.get(win_id)
        if w is None:                 # pane already gone — nothing to do, definitely nothing to close
            return
        _send_startup_commands(boss, w)

    for delay in _ATTEMPT_DELAYS:
        add_timer(_attempt, delay, False)
