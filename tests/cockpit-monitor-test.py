#!/usr/bin/env python3
"""Unit tests for the cockpit monitor watcher (~/.config/kitty/cockpit_monitor.py), no kitty runtime.

We stub the `kitty.*` modules the watcher imports (boss, window, fast_data_types) — those resolve
only inside kitty's embedded interpreter — then import the watcher unmodified and drive its
callbacks with fake Boss/Window objects. We assert the JURISDICTION (only cockpit=claude panes get
styled), IDEMPOTENCY (a pane is never typed into twice), the exact SEND PAYLOAD (/rename + /color,
each submitted), and — most important after the close-a-live-cockpit incident — that the watcher
NEVER issues any window-close/kill remote-control verb.
"""
import importlib.util
import os
import sys
import types

# ---- stub the kitty modules the watcher imports ----
# add_timer: capture scheduled callbacks so the test can fire them deterministically (no real wait).
SCHEDULED = []  # list of (callback, delay)


def _add_timer(callback, delay, repeating):
    SCHEDULED.append((callback, delay))
    return len(SCHEDULED)  # a fake timer id


_fdt = types.ModuleType('kitty.fast_data_types')
_fdt.add_timer = _add_timer
_boss_mod = types.ModuleType('kitty.boss')
_boss_mod.Boss = object          # the watcher only type-hints against these
_win_mod = types.ModuleType('kitty.window')
_win_mod.Window = object
_kitty_pkg = types.ModuleType('kitty')
sys.modules['kitty'] = _kitty_pkg
sys.modules['kitty.boss'] = _boss_mod
sys.modules['kitty.window'] = _win_mod
sys.modules['kitty.fast_data_types'] = _fdt


def load(modname, path):
    spec = importlib.util.spec_from_file_location(modname, os.path.expanduser(path))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


mon = load('cockpit_monitor', '~/.config/kitty/cockpit_monitor.py')

PASS = {'n': 0, 'f': 0}


def check(cond, msg):
    print(('  ✓ ' if cond else '  ✗ ') + msg)
    PASS['n' if cond else 'f'] += 1


# ---- faithful-enough kitty fakes ----
class FakeWindow:
    _next = 1

    def __init__(self, cockpit=None):
        self.id = FakeWindow._next
        FakeWindow._next += 1
        self.user_vars = {}
        if cockpit is not None:
            self.user_vars['cockpit'] = cockpit

    def set_user_var(self, k, v):
        self.user_vars[k] = v


class FakeBoss:
    def __init__(self, windows):
        self.window_id_map = {w.id: w for w in windows}
        self.rc_calls = []  # captured (window_id, args_tuple)

    def call_remote_control(self, window, args):
        self.rc_calls.append((window.id, tuple(args)))


def fire_all_timers():
    """Run every scheduled callback once (simulates the delays elapsing), then clear."""
    cbs = list(SCHEDULED)
    SCHEDULED.clear()
    for cb, _delay in cbs:
        cb(None)


def reset():
    SCHEDULED.clear()


# ============================================================================
print("== 1. jurisdiction: only cockpit=claude panes get styled ==")
reset()
claude = FakeWindow(cockpit='claude')
shell = FakeWindow(cockpit='shell')
cmd = FakeWindow(cockpit='cmd')
plain = FakeWindow(cockpit=None)          # a non-stail kitty window
boss = FakeBoss([claude, shell, cmd, plain])

for w in (claude, shell, cmd, plain):
    mon.on_resize(boss, w, {'old_geometry': None, 'new_geometry': None})

check(len(SCHEDULED) == 3, "claude pane scheduled timers (shell/cmd skip scheduling); got %d" % len(SCHEDULED))
fire_all_timers()
styled_ids = {wid for (wid, _args) in boss.rc_calls}
check(styled_ids == {claude.id}, "ONLY the claude pane received remote-control; got ids %s" % styled_ids)
check(shell.user_vars.get('cockpit_styled') is None, "shell pane never marked styled")
check(cmd.user_vars.get('cockpit_styled') is None, "cmd pane never marked styled")
check(plain.user_vars.get('cockpit_styled') is None, "non-stail pane never marked styled")

print("== 2. exact payload: /rename then /color, each submitted with \\r ==")
reset()
c = FakeWindow(cockpit='claude')
b = FakeBoss([c])
mon.on_resize(b, c, {})
fire_all_timers()
check(len(b.rc_calls) == 1, "exactly one remote-control call (first attempt marks styled, rest no-op); got %d" % len(b.rc_calls))
wid, args = b.rc_calls[0]
check(args[0] == 'send-text', "verb is send-text (never a close/kill verb)")
check(args[1] == '--match=id:%d' % c.id, "scoped to THIS window id via --match=id")
payload = args[2]
check(payload == '/rename\r/color\r', "payload is '/rename\\r/color\\r' (rename first, color second, each Enter-submitted)")

print("== 3. idempotency: multiple resizes + all timers => typed exactly once ==")
reset()
c = FakeWindow(cockpit='claude')
b = FakeBoss([c])
mon.on_resize(b, c, {})          # creation resize -> schedules 3 attempts
mon.on_resize(b, c, {})          # a later resize (drag/layout) -> must NOT schedule more
mon.on_resize(b, c, {})
check(len(SCHEDULED) == 3, "repeated resizes schedule timers only once (3 attempts total); got %d" % len(SCHEDULED))
fire_all_timers()                # all 3 attempts fire; only the first should type
check(len(b.rc_calls) == 1, "despite 3 attempts firing, typed EXACTLY once; got %d" % len(b.rc_calls))
check(c.user_vars.get('cockpit_styled') == '1', "pane marked styled after firing")

print("== 4. re-resize AFTER styling (resume / re-attach) never re-types ==")
reset()
mon.on_resize(b, c, {})          # c is already styled from section 3
check(len(SCHEDULED) == 0, "an already-styled pane schedules nothing on a fresh resize")
fire_all_timers()
check(len(b.rc_calls) == 1, "still exactly one lifetime send (no re-type on resume); got %d" % len(b.rc_calls))

print("== 5. pane closed before the timer fires => no send, no crash ==")
reset()
c2 = FakeWindow(cockpit='claude')
b2 = FakeBoss([c2])
mon.on_resize(b2, c2, {})
del b2.window_id_map[c2.id]       # pane gone before attempts fire
fire_all_timers()                 # must be a clean no-op (window_id_map.get -> None)
check(len(b2.rc_calls) == 0, "closed-before-fire pane: zero remote-control calls, no exception")

print("== 6. SAFETY: across MANY panes + all timers, every RC call is send-text (never destructive) ==")
# Behavioural safety check (not a substring grep — the words 'kill'/'quit' legitimately appear in
# the source's comments/docstrings). Drive a batch of claude panes through the full lifecycle and
# assert EVERY remote-control verb the watcher ever emits is 'send-text'. A close/kill/detach verb
# would show up here as a non-send-text call.
reset()
FakeWindow._next = 1000
panes = [FakeWindow(cockpit='claude') for _ in range(6)]
bb = FakeBoss(panes)
for w in panes:
    mon.on_resize(bb, w, {})
fire_all_timers()
verbs = {args[0] for (_wid, args) in bb.rc_calls}
check(len(bb.rc_calls) == 6, "6 claude panes -> 6 sends, one each; got %d" % len(bb.rc_calls))
check(verbs == {'send-text'}, "every remote-control verb emitted is send-text; saw %s" % verbs)
# belt-and-suspenders: confirm no destructive verb appears as an actual RC argument anywhere
destructive = {'close-window', 'close-tab', 'detach-window', 'detach-tab', 'quit', 'signal-child'}
bad = [(w, a) for (w, a) in bb.rc_calls if set(a) & destructive]
check(bad == [], "no destructive verb in any emitted RC call; found %s" % bad)

print()
print("RESULT: %d passed, %d failed" % (PASS['n'], PASS['f']))
sys.exit(1 if PASS['f'] else 0)
