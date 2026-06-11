# SwitchTail board: "hold the focused claude line for resume".
# Mapped to a key in hold.conf. For a hold-capable line (--var holdable=1, derived from
# stail's kind table) it arms a one-shot hold marker and THEN closes the pane it acted on:
#   * pane has a sid user_var (stamped by `stail line` at launch) -> per-pane marker
#     $STATE/hold/<lab>/<sid>, so `stail line` resumes that EXACT session via --resume.
#     N held panes = N markers = N panes resume (no collapse to one).
#   * no/invalid sid (older pane) -> legacy flag $STATE/<lab>.hold, consumed id-less
#     via the kind table's continue argv (most recent session for the lab dir).
# The close is gated on the marker write: the kitten owns it (hold.conf no longer chains an
# unconditional close_window), so a manually-split/restored pane with no --var lab/holdable
# is never closed out from under you. The lab var is re-validated to the same charset the
# CLI enforces, and the sid to a uuid-ish charset, so hand-rolled user_vars can't steer the
# marker path outside the state dir.
import os
import re

from kittens.tui.handler import result_handler

_LAB_RE = re.compile(r'[A-Za-z0-9._-]+')
_SID_RE = re.compile(r'[0-9a-fA-F-]{8,64}')


def main(args):
    pass


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    w = boss.window_id_map.get(target_window_id)
    uv = (getattr(w, 'user_vars', {}) or {}) if w else {}
    lab = uv.get('lab')
    sid = uv.get('sid')
    if uv.get('holdable') == '1' and lab and _LAB_RE.fullmatch(lab):
        try:
            state = os.path.join(
                os.environ.get('XDG_STATE_HOME', os.path.expanduser('~/.local/state')),
                'switchtail')
            if sid and _SID_RE.fullmatch(sid):
                # per-pane marker: filename IS the session id
                hold_dir = os.path.join(state, 'hold', lab)
                os.makedirs(hold_dir, exist_ok=True)
                with open(os.path.join(hold_dir, sid), 'w'):
                    pass
            else:
                # legacy flag marker (pane predates sid stamping)
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
        # Not a hold-capable tagged line (manual split, side shell, restored window,
        # or an out-of-charset lab): never close it blindly. Make the no-op visible.
        boss.show_error(
            'stail hold',
            'Not a hold-capable line (need --var holdable=1 + a [A-Za-z0-9._-] lab) '
            '— nothing held or closed.')
