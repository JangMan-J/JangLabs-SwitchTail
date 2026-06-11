#!/usr/bin/env python3
"""Faithful unit tests for the REAL cockpit kittens (no kitty runtime).

We stub only `kittens.tui.handler.result_handler` (a pass-through decorator) and model
kitty's window API exactly as the installed 0.47.1 source behaves:
  WindowList.move_window_group(by=d): target=(ai+d)%n; swap groups[ai],groups[target];
  active index FOLLOWS to target  (window_list.py:503).
Then we import ~/.config/kitty/cockpit_{bounce,park}.py unmodified and exercise them.
"""
import importlib.util
import os
import sys
import tempfile
import types

# ---- stub the kitty kitten import shim ----
for name in ('kittens', 'kittens.tui', 'kittens.tui.handler'):
    sys.modules[name] = types.ModuleType(name)
def _result_handler(*a, **k):
    def deco(fn): return fn
    return deco
sys.modules['kittens.tui.handler'].result_handler = _result_handler

def load(modname, path):
    spec = importlib.util.spec_from_file_location(modname, os.path.expanduser(path))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

bounce = load('cockpit_bounce', '~/.config/kitty/cockpit_bounce.py')
park = load('cockpit_park', '~/.config/kitty/cockpit_park.py')

PASS = {'n': 0, 'f': 0}
def check(cond, msg):
    print(('  ✓ ' if cond else '  ✗ ') + msg)
    PASS['n' if cond else 'f'] += 0 if False else 0
    if cond: PASS['n'] += 1
    else: PASS['f'] += 1

# ================= faithful kitty fakes (bounce) =================
class Group:
    def __init__(self, gid): self.id = gid
class WindowList:
    def __init__(self, ids, ai):
        self.groups = [Group(i) for i in ids]
        self.active_group_idx = ai
class Tab:
    def __init__(self, ids, ai, tid=1):
        self.id = tid
        self.windows = WindowList(ids, ai)
    def move_window(self, delta):
        wl = self.windows; n = len(wl.groups)
        if n < 2 or not delta: return
        ai = wl.active_group_idx
        target = (ai + delta) % n
        if target == ai: return
        wl.groups[ai], wl.groups[target] = wl.groups[target], wl.groups[ai]
        wl.active_group_idx = target
class Boss:
    def __init__(self, tab, tabs=None):
        self.active_tab = tab
        self._tabs = tabs if tabs is not None else [tab]
    @property
    def all_tabs(self): return iter(self._tabs)

def order(t): return [g.id for g in t.windows.groups]
def active_id(t): return t.windows.groups[t.windows.active_group_idx].id
def focus(t, gid): t.windows.active_group_idx = next(i for i, g in enumerate(t.windows.groups) if g.id == gid)
def press(boss, t): bounce.handle_result(None, None, None, boss)
def rec(boss, t): return getattr(boss, '_cockpit_bounce', {}).get(t.id)

print("== BOUNCE (#1): involution + identity guard ==")

# S1: basic yank + flingback restores exactly (involution)
t = Tab([10, 11, 12, 13], 0); b = Boss(t); focus(t, 12)       # focus C (idx2)
press(b, t)
check(order(t) == [12, 11, 10, 13] and active_id(t) == 12, "yank C->master gives [C,B,A,D], C active")
press(b, t)
check(order(t) == [10, 11, 12, 13] and active_id(t) == 12, "2nd press flings C home -> [A,B,C,D], C active (involution)")
check(rec(b, t) is None, "record cleared after flingback")

# S2: adjacent involution (idx1)
t = Tab([10, 11, 12, 13], 0); b = Boss(t); focus(t, 11); press(b, t); press(b, t)
check(order(t) == [10, 11, 12, 13] and active_id(t) == 11, "adjacent yank+flingback restores [A,B,C,D]")

# S3: THE #1 FIX — reorder so a DIFFERENT window is in master, then press must NOT wrong-swap
t = Tab([10, 11, 12, 13], 0); b = Boss(t); focus(t, 12); press(b, t)   # record yanked=12 partner=10
# simulate the user shuffling B(11) into the hot seat (deck MOVE dpad) and focusing it there:
t.windows.groups = [Group(11), Group(12), Group(10), Group(13)]; t.windows.active_group_idx = 0
before = order(t)
press(b, t)
check(order(t) == before, "press with a non-yanked window in master is a NO-OP (no wrong-swap of innocent master)")
check(rec(b, t) is None, "stale record dropped on that no-op")

# S4: navigate-between-presses never strands a pane (all windows always present)
t = Tab([10, 11, 12, 13], 0); b = Boss(t); focus(t, 12); press(b, t)   # yank C
focus(t, 11)                                                            # navigate to B
press(b, t)                                                             # fresh yank of B
check(sorted(order(t)) == [10, 11, 12, 13], "all 4 panes still present after navigate+press (no strand)")
check(active_id(t) == 11 and order(t)[0] == 11, "B is now in the hot seat (fresh yank)")
press(b, t)                                                             # B in master -> flingback
check(sorted(order(t)) == [10, 11, 12, 13] and active_id(t) == 11, "B flings back, still no pane lost")

# S5: flingback partner gone (closed) -> graceful no-op
t = Tab([10, 11, 12, 13], 0); b = Boss(t); focus(t, 12); press(b, t)   # yank C, partner A(10)
t.windows.groups = [Group(12), Group(11), Group(13)]; t.windows.active_group_idx = 0  # A closed
before = order(t); press(b, t)
check(order(t) == before and rec(b, t) is None, "partner-closed flingback is a clean no-op")

# S6: <2 groups -> no-op / no crash
t = Tab([10], 0); b = Boss(t); press(b, t)
check(order(t) == [10], "single window press is a safe no-op")

# S7: per-tab isolation via stable tab.id
ta = Tab([10, 11], 0, tid=1); tb = Tab([20, 21], 0, tid=2)
ba = Boss(ta, tabs=[ta, tb]); focus(ta, 11); press(ba, ta)            # yank in tab 1
# a press dispatched to tab 2 (same boss store, different tab.id) must not see tab1's record
ba.active_tab = tb; focus(tb, 21); press(ba, tb)
check(order(tb) == [21, 20] and rec(ba, tb) is not None, "tab 2 yank independent of tab 1 (keyed by tab.id)")

# S8 (R5): a yanked-then-closed tab's record is pruned on the next press elsewhere
ta = Tab([10, 11], 0, tid=1); tb = Tab([20, 21], 0, tid=2)
bz = Boss(ta, tabs=[ta, tb]); focus(ta, 11); press(bz, ta)           # yank in tab 1 -> store[1]
check(rec(bz, ta) is not None, "record present after yank in tab 1")
bz._tabs = [tb]                                                       # tab 1 closed
bz.active_tab = tb; focus(tb, 21); press(bz, tb)                      # press in tab 2 -> prune
check(1 not in getattr(bz, '_cockpit_bounce', {}), "closed tab's record pruned on next press (R5)")

# ================= park kitten (#3) =================
print("== PARK (#3): close gated on a successful marker write ==")
class FakeWindow:
    def __init__(self, uv): self.user_vars = uv
class ParkBoss:
    def __init__(self, wmap):
        self.window_id_map = wmap; self.closed = []; self.errors = []
    def mark_window_for_close(self, q): self.closed.append(q)
    def show_error(self, title, msg): self.errors.append((title, msg))

def run_park(state_home, wmap, target):
    os.environ['XDG_STATE_HOME'] = state_home
    b = ParkBoss(wmap)
    park.handle_result(None, None, target, b)
    return b

# C1: tagged cockpit claude pane -> marker armed THEN close
sh = tempfile.mkdtemp()
b = run_park(sh, {1: FakeWindow({'cockpit': 'claude', 'lab': 'zzt'})}, 1)
marker = os.path.join(sh, 'switchtail', 'zzt.resume')
check(os.path.exists(marker), "tagged pane: resume marker written")
check(b.closed == [1] and not b.errors, "tagged pane: window 1 closed, no error shown")

# C2: untagged pane -> never closed, visible warning
b = run_park(tempfile.mkdtemp(), {2: FakeWindow({})}, 2)
check(b.closed == [] and len(b.errors) == 1, "untagged pane: NOT closed, warning shown")

# C3: side shell (cockpit=shell, no lab) -> never closed
b = run_park(tempfile.mkdtemp(), {3: FakeWindow({'cockpit': 'shell'})}, 3)
check(b.closed == [] and len(b.errors) == 1, "side shell: NOT closed, warning shown")

# C4: marker write FAILS (state path is a file) -> do NOT close, warn
badfile = os.path.join(tempfile.mkdtemp(), 'statefile'); open(badfile, 'w').close()
b = run_park(badfile, {4: FakeWindow({'cockpit': 'claude', 'lab': 'zzt'})}, 4)
check(b.closed == [] and len(b.errors) == 1, "marker write failure: pane left OPEN, warning shown")

# C5 (R1): a traversal lab var is rejected before the marker path is built
base = tempfile.mkdtemp(); deep = os.path.join(base, 'a', 'b'); os.makedirs(deep)
b = run_park(deep, {5: FakeWindow({'cockpit': 'claude', 'lab': '../../evil'})}, 5)
check(b.closed == [] and len(b.errors) == 1, "traversal lab: NOT closed, warning shown (R1)")
evil = os.path.normpath(os.path.join(deep, 'switchtail', '../../evil.resume'))
check(not os.path.exists(evil), "traversal lab: no marker written outside state dir (R1)")

print(f"\nRESULT: {PASS['n']} passed, {PASS['f']} failed")
sys.exit(1 if PASS['f'] else 0)
