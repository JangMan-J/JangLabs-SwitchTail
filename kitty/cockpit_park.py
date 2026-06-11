# SwitchTail cockpit: "park the focused claude session for resume".
# Mapped to a key in cockpit.conf. For a properly tagged cockpit claude pane it writes a
# one-shot .resume marker for that lab (so `stail cockpit <lab>` does `claude --continue` on
# the next launch) and THEN closes the pane it acted on. The close is gated on the marker:
# the kitten owns it (cockpit.conf no longer chains an unconditional close_window), so a
# manually-split/restored pane with no --var lab/cockpit is never closed out from under you.
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
    if uv.get('cockpit') == 'claude' and lab and _LAB_RE.fullmatch(lab):
        try:
            state = os.path.join(
                os.environ.get('XDG_STATE_HOME', os.path.expanduser('~/.local/state')),
                'switchtail')
            os.makedirs(state, exist_ok=True)
            with open(os.path.join(state, lab + '.resume'), 'w'):
                pass
        except Exception:
            # Marker write failed -> do NOT close; the session would not resume.
            boss.show_error('stail park', 'Could not arm the resume marker; pane left open.')
            return
        # Marker armed -> now (and only now) close the pane we acted on.
        boss.mark_window_for_close(target_window_id)
    else:
        # Not a valid tagged cockpit claude pane (manual split, side shell, restored window,
        # or an out-of-charset lab): never close it blindly. Make the no-op visible.
        boss.show_error(
            'stail park',
            'Not a valid cockpit claude pane (need --var cockpit=claude + a [A-Za-z0-9._-] lab) '
            '— nothing parked or closed.')
