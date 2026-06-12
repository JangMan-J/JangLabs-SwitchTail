#!/usr/bin/env python3
"""Unit tests for the state watcher (kitty/state.py), no kitty runtime.

We stub the `kitty.*` modules the watcher imports (boss, window) — those resolve only
inside kitty's embedded interpreter — then load the watcher and drive on_focus_change
with fake Window objects and a tempdir XDG_STATE_HOME per case. We assert the GAIN
write (atomic, no tmp leftover), the LOSS clear, the COMPARE-AND-CLEAR ordering guard
(a loss never clobbers a newer gain from a different board), the CHARSET GATE
(no/junk/hostile board values never touch the file), and the EXCEPTION GUARD (an
unwritable state dir never raises into the caller — i.e. never into kitty).

CRITICAL: the watcher is loaded from the REPO-RELATIVE path next to this test file —
NOT from the deployed kitty config dir — so the suite always tests the edited tree
(the same honesty STAIL_BIN gives the bash suites; tail-test.py's deployed-path load
is the trap this suite deliberately does not copy).
"""
import importlib.util
import os
import shutil
import sys
import tempfile
import types

# ---- stub the kitty modules the watcher imports ----
# state.py needs no fast_data_types stub — it schedules no timers.
_boss_mod = types.ModuleType('kitty.boss')
_boss_mod.Boss = object          # the watcher only type-hints against these
_win_mod = types.ModuleType('kitty.window')
_win_mod.Window = object
_kitty_pkg = types.ModuleType('kitty')
sys.modules['kitty'] = _kitty_pkg
sys.modules['kitty.boss'] = _boss_mod
sys.modules['kitty.window'] = _win_mod


def load(modname, path):
    spec = importlib.util.spec_from_file_location(modname, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# Repo-relative load: the state.py SIBLING of this test, never the deployed copy.
mon = load('state_watcher',
           os.path.join(os.path.dirname(__file__), '..', 'kitty', 'state.py'))

PASS = {'n': 0, 'f': 0}


def check(cond, msg):
    print(('  ✓ ' if cond else '  ✗ ') + msg)
    PASS['n' if cond else 'f'] += 1


# ---- faithful-enough kitty fakes ----
class FakeWindow:
    def __init__(self, board=None):
        self.user_vars = {}
        if board is not None:
            self.user_vars['board'] = board


BOSS = object()  # state.py never touches boss — any object will do


def fresh_state():
    """Point XDG_STATE_HOME at a brand-new tempdir; return (tmpdir, active_path)."""
    d = tempfile.mkdtemp(prefix='state-test-')
    os.environ['XDG_STATE_HOME'] = d
    return d, os.path.join(d, 'switchtail', 'active')


def read(path):
    with open(path) as f:
        return f.read()


# ============================================================================
print("== 1. gain: focused board pane writes its name to $STATE/active, atomically ==")
d, active = fresh_state()
mon.on_focus_change(BOSS, FakeWindow(board='zlab'), {'focused': True})
check(os.path.isfile(active), "active file exists after gain")
check(read(active).strip() == 'zlab', "content is the board name 'zlab'")
leftovers = [f for f in os.listdir(os.path.dirname(active)) if f.endswith('.tmp')]
check(leftovers == [], "no .tmp leftover after the atomic rename; found %s" % leftovers)

print("== 2. loss: the same board losing focus removes the file ==")
mon.on_focus_change(BOSS, FakeWindow(board='zlab'), {'focused': False})
check(not os.path.exists(active), "active file removed on focus loss")
shutil.rmtree(d)

print("== 3. compare-and-clear: a loss never clobbers a DIFFERENT board's newer gain ==")
# Simulate the cross-process ordering where the newly focused board's gain lands FIRST:
# the file already names 'newboard' when 'zlab' processes its loss.
d, active = fresh_state()
mon.on_focus_change(BOSS, FakeWindow(board='newboard'), {'focused': True})
mon.on_focus_change(BOSS, FakeWindow(board='zlab'), {'focused': False})
check(os.path.isfile(active), "file survives the stale loss (compare-and-clear)")
check(read(active).strip() == 'newboard', "content still names the newer board")
shutil.rmtree(d)

print("== 4. jurisdiction: a window with NO board user-var never touches the file ==")
d, active = fresh_state()
mon.on_focus_change(BOSS, FakeWindow(), {'focused': True})
check(not os.path.exists(active), "no-board window: file never created")
shutil.rmtree(d)

print("== 5. charset gate: hostile board values never touch the file ==")
d, active = fresh_state()
for hostile in ('../evil', 'a b'):
    mon.on_focus_change(BOSS, FakeWindow(board=hostile), {'focused': True})
    check(not os.path.exists(active),
          "hostile board %r rejected by the charset gate (file never created)" % hostile)
# belt-and-suspenders: nothing at all appeared under the state home (no path escape)
created = [os.path.join(r, f) for r, _dirs, fs in os.walk(d) for f in fs]
check(created == [], "no file of any name appeared under the state home; found %s" % created)
shutil.rmtree(d)

print("== 6. exception guard: an unwritable state home never raises into kitty ==")
d = tempfile.mkdtemp(prefix='state-test-ro-')
os.environ['XDG_STATE_HOME'] = d
os.chmod(d, 0o500)  # read+exec only: makedirs/open inside it must fail
try:
    try:
        mon.on_focus_change(BOSS, FakeWindow(board='zlab'), {'focused': True})
        mon.on_focus_change(BOSS, FakeWindow(board='zlab'), {'focused': False})
        check(True, "gain+loss against a read-only state home returned without raising")
    except Exception as e:  # noqa: BLE001 — the whole point is that this never happens
        check(False, "watcher raised %r — the blanket guard is broken" % e)
finally:
    os.chmod(d, 0o700)
    shutil.rmtree(d)

print()
print("RESULT: %d passed, %d failed" % (PASS['n'], PASS['f']))
sys.exit(1 if PASS['f'] else 0)
