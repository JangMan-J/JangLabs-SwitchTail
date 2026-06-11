# SwitchTail board: "hold the focused claude line for resume".
# Mapped to a key in hold.conf. For a properly tagged board claude line it writes a
# one-shot .hold marker for that lab (so `stail line <lab>` does `claude --continue` on
# the next launch) and THEN closes the pane it acted on. The close is gated on the marker:
# the kitten owns it (hold.conf no longer chains an unconditional close_window), so a
# manually-split/restored pane with no --var lab/kind is never closed out from under you.
# The lab var is re-validated to the same [A-Za-z0-9._-] charset the CLI enforces, so a
# hand-rolled `--var lab=../x` tag can't steer the marker path outside the state dir.
import os
import re

from kittens.tui.handler import result_handler

_LAB_RE = re.compile(r'[A-Za-z0-9._-]+')


def main(args):
    pass


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    w = boss.window_id_map.get(target_window_id)
    uv = (getattr(w, 'user_vars', {}) or {}) if w else {}
    lab = uv.get('lab')
    if uv.get('kind') == 'claude' and lab and _LAB_RE.fullmatch(lab):
        try:
            state = os.path.join(
                os.environ.get('XDG_STATE_HOME', os.path.expanduser('~/.local/state')),
                'switchtail')
            os.makedirs(state, exist_ok=True)
            with open(os.path.join(state, lab + '.hold'), 'w'):
                pass
        except Exception:
            # Marker write failed -> do NOT close; the session would not resume.
            boss.show_error('stail hold', 'Could not arm the hold marker; pane left open.')
            return
        # Marker armed -> now (and only now) close the pane we acted on.
        boss.mark_window_for_close(target_window_id)
    else:
        # Not a valid tagged board claude line (manual split, side shell, restored window,
        # or an out-of-charset lab): never close it blindly. Make the no-op visible.
        boss.show_error(
            'stail hold',
            'Not a valid board claude line (need --var kind=claude + a [A-Za-z0-9._-] lab) '
            '— nothing held or closed.')
