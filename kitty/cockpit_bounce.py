# SwitchTail cockpit: "bounce-swap".
# Yank the focused agent into the hot seat (master / first window); press again, with
# that same agent still in the hot seat, to fling it back where it came from. Built on
# kitty's swap primitive: tab.move_window(delta) swaps the active window with the one
# `delta` slots away (window_list.py). To make it reversible we remember, per tab, BOTH
# the identity of the window we yanked AND the identity of the partner it displaced, so a
# later press recognises a genuine fling-back from a fresh yank even if you navigated
# between presses. State lives on the long-lived Boss object, keyed by the stable tab.id
# (NOT id(tab), whose value is recycled when a tab object is freed).
from kittens.tui.handler import result_handler


def main(args):
    pass


def _log_exc():
    # Best-effort debug log into the cockpit state dir (NOT world-writable /tmp, which is
    # symlink-attackable). Swallow any logging failure — a bad press must never raise.
    import os
    try:
        state = os.path.join(
            os.environ.get('XDG_STATE_HOME', os.path.expanduser('~/.local/state')),
            'switchtail')
        os.makedirs(state, exist_ok=True)
        import traceback
        with open(os.path.join(state, 'bounce.log'), 'a') as f:
            f.write(traceback.format_exc() + '\n')
    except Exception:
        pass


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    try:
        tab = boss.active_tab
        if tab is None:
            return
        wl = tab.windows
        groups = list(wl.groups)
        if len(groups) < 2:
            return
        ai = wl.active_group_idx
        if ai < 0:
            return
        store = getattr(boss, '_cockpit_bounce', None)
        if store is None:
            store = {}
            boss._cockpit_bounce = store
        # Housekeeping: drop records for tabs that no longer exist (a tab yanked-then-closed
        # without a master-press would otherwise linger for the kitty process lifetime). Its
        # own try/except — tab.id is stable+non-recycled so this is never a correctness fix,
        # and a hiccup here must never break the actual bounce below.
        try:
            live = {t.id for t in boss.all_tabs}
            for dead in [k for k in store if k not in live]:
                store.pop(dead, None)
        except Exception:
            pass
        key = tab.id                       # stable per-tab id (survives object recycling)
        rec = store.get(key)               # {'yanked': gid, 'partner': gid} or None

        master_id = groups[0].id
        present = {g.id for g in groups}

        if ai == 0:
            # Focused window is in the hot seat. Fling back ONLY if it is the very window
            # we yanked here (its identity, not merely "something is at index 0") and the
            # partner it displaced is still around. Otherwise the record is stale -> drop it
            # and do nothing (can't yank the master to itself).
            if rec and rec['yanked'] == master_id and rec['partner'] in present:
                store.pop(key, None)
                idx = next((i for i, g in enumerate(groups) if g.id == rec['partner']), -1)
                if idx > 0:
                    tab.move_window(idx)   # swap master <-> partner's current slot
            else:
                store.pop(key, None)
        else:
            # Focused window is not in the hot seat: yank it to master, remembering both its
            # identity and the partner it displaces. A fresh yank always overwrites any prior
            # record, so navigating to a different agent and pressing can never strand panes.
            store[key] = {'yanked': groups[ai].id, 'partner': master_id}
            tab.move_window(-ai)           # swap active <-> master
    except Exception:
        _log_exc()
