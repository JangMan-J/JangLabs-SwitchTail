# SwitchTail state watcher — a kitty GLOBAL watcher (loaded via `watcher state.py`
# in kitty.conf, included from state.conf). It maintains the focused-board record that gives
# `stail active` its kdotool-free data source: on focus gain by a stail board pane (tagged
# --var board=<name> by stail's session emitter), it writes that board's name to
# $XDG_STATE_HOME/switchtail/active; on focus loss it clears the file — but only if the file
# still names the board losing focus (compare-and-clear), so a gain event from the newly
# focused board that lands first is never clobbered by the loser's late loss event.
#
# SAFETY (the parallel of tail.py's documented send-text-only property):
#   * This watcher performs filesystem writes to $STATE/active ONLY. There is deliberately
#     NO boss/window mutation anywhere in this file — no send_text, no close/destroy verbs,
#     no remote-control calls — so it structurally cannot type into, close, or otherwise
#     hurt a pane. Its entire safety audit fits one screen: grep for filesystem calls.
#   * It is a SEPARATE file from tail.py on purpose: tail.py's audited "send-text only"
#     property stays clean (one verb class per watcher file, each one-screen verifiable).
#   * It acts ONLY on windows carrying a `board` user_var that passes the same
#     [A-Za-z0-9._-]+ charset the CLI enforces. Non-stail kitty windows and hand-rolled
#     junk values never touch the file — and the value is written as file CONTENT only,
#     never interpolated into a path.
#   * The whole hook body is wrapped in a blanket try/except: a watcher exception must
#     never propagate into kitty (kitty would print it, but the pane must stay fine).
#
# Atomicity: gain writes go tmp + os.replace — the Python mirror of stail's `mv -f`
# primitive — so a reader (cmd_active, the widget's poll) never sees a partial write.
#
# API: on_focus_change(boss, window, data) with data={'focused': bool}, verified against
# the installed kitty 0.47.1 source (window.py:1412, launch.py:551) and the documented
# watcher surface (https://sw.kovidgoyal.net/kitty/launch/#watchers).

import os
import re
from typing import Any

from kitty.boss import Boss
from kitty.window import Window

# The same charset the CLI enforces (_require_valid_lab) and hold.py re-validates.
_BOARD_RE = re.compile(r'[A-Za-z0-9._-]+')


def _active_path() -> str:
    """Path of the focused-board record, creating the state dir if needed."""
    state = os.path.join(
        os.environ.get('XDG_STATE_HOME', os.path.expanduser('~/.local/state')),
        'switchtail')
    os.makedirs(state, exist_ok=True)
    return os.path.join(state, 'active')


def on_focus_change(boss: Boss, window: Window, data: dict[str, Any]) -> None:
    try:
        board = (window.user_vars or {}).get('board')
        if not board or not _BOARD_RE.fullmatch(board):
            return                              # not a stail board pane — never touch the file
        path = _active_path()
        if data.get('focused'):
            # Gain: atomic write (tmp + rename), PID-suffixed tmp so concurrent kitty
            # processes never collide on the temp name.
            tmp = f'{path}.{os.getpid()}.tmp'
            with open(tmp, 'w') as f:
                f.write(board + '\n')
            os.replace(tmp, path)               # atomic
        else:
            # Loss: compare-and-clear — unlink ONLY if the file still names OUR board,
            # so a newer gain (written first by the newly focused board) is not clobbered.
            try:
                with open(path) as f:
                    if f.read().strip() == board:
                        os.unlink(path)
            except FileNotFoundError:
                pass
    except Exception:
        pass                                    # a watcher exception must never hurt the pane
