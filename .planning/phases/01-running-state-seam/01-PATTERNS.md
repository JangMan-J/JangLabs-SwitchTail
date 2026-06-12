# Phase 1: Running-State Seam - Pattern Map

**Mapped:** 2026-06-12
**Files analyzed:** 9 (3 new, 6 modified)
**Analogs found:** 9 / 9 (every new/modified file has a strong in-repo analog)

All paths below are repo-relative to `/home/jangmanj/JangLabs/switchtail/`.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `bin/stail` — new `_run_mark`/`_pane_alive` + `_running_labs` rewrite | utility (state I/O helpers) | file I/O (atomic marker write, lazy-reap scan) | `_hold_claim` + `_SID_RE` in `bin/stail` lines 228–247 | exact |
| `bin/stail` — `_emit_session` board stamping | utility (emitter) | transform (arrays → session text) | `_emit_session` itself, lines 264–294 | exact (in-place extension) |
| `bin/stail` — `cmd_line` marker write | controller (subcommand) | file I/O pre-`exec` | `cmd_line` hold-claim block, lines 455–471 | exact |
| `bin/stail` — `cmd_active`/`cmd_list` rewrites | controller (subcommand) | request-response (JSON/text emit) | existing `cmd_active` 622–641 / `cmd_list` 645–666 | exact (keep byte-shape, swap source) |
| `bin/stail` — `cmd_switch` decision re-source | controller (subcommand) | request-response + side effect | existing `cmd_switch` 670–700 | exact |
| `kitty/state.py` (NEW) | event handler (kitty global watcher) | event-driven → file I/O | `kitty/hold.py` (validation + state write) + `kitty/tail.py` (global-watcher shape, safety docs) | role+flow match |
| `kitty/state.conf` (NEW) | config | — | `kitty/tail.conf` | exact |
| `tests/stail-test-6.sh` (NEW) | test | batch (assertion script) | `tests/stail-test-2.sh` Part B + `tests/stail-test-1.sh` §6 STATE fixture | exact |
| `tests/stail-test-{2,3,4}.sh`, `tests/run-all.sh` | test / test orchestrator | batch | themselves (in-place edits) | exact |

`CLAUDE.md` contract point 5 is a doc edit; no code analog needed — mirror the existing point-5 phrasing, swapped to the state dir.

## Pattern Assignments

### `bin/stail` — run-marker helpers (`_run_mark`, `_pane_alive`, new `_running_labs`)

**Analog:** the hold-marker block, `bin/stail` lines 220–247.

**Atomic marker + filename-validation pattern** (`_hold_claim`, lines 228–247) — this is the house primitive to copy: charset-gate every filename before it touches a path or argv, and use `mv` as the atomic operation:

```bash
_SID_RE='^[0-9a-fA-F-]{8,64}$'
_hold_claim() {  # $1=lab -> echo one claimed session id, if any (atomic, first-wins)
  local d="$STATE/hold/$1" f sid
  [ -d "$d" ] || return 0
  for f in "$d"/*; do
    [ -e "$f" ] || continue
    sid="$(basename "$f")"
    [[ "$sid" =~ $_SID_RE ]] || continue   # never let a stray filename reach an exec argv
    if mv "$f" "$f.claimed.$$" 2>/dev/null; then
      rm -f "$f.claimed.$$"
      printf '%s\n' "$sid"
      return 0
    fi
  done
  return 0
}
```

For run markers: same shape, but filenames are PIDs gated by `^[0-9]+$`, writes go `> "$d/$$.tmp" && mv -f "$d/$$.tmp" "$d/$$"`, and **every step ends `|| return 0`** (Pitfall 2: a marker failure must never kill the pane — contrast: `_hold_claim` may fail soft too, same discipline). RESEARCH.md "Code Examples" contains complete verified drafts of `_run_mark`, `_pane_alive`, and the new `_running_labs` — use those as the starting bodies; they are already in house style.

**Comment style:** copy the block-comment-above-function convention (see lines 220–227: a `# ---------- shared: ... ----------` banner + a paragraph explaining the contract). The run/ layout is a new 2-way contract (stail ↔ state.py readers) — document it the way the hold contract is documented at lines 220–227.

**Old `_running_labs` being replaced** (lines 139–148) — keep its output contract (one lab per line, `exchange` included when up) so `cmd_list`/`cmd_switch` callers don't change shape:

```bash
_running_labs() {  # echo each running lab (incl. "exchange" + its lines), one per line
  local cls saw_exchange=0
  while IFS= read -r cls; do
    case "$cls" in
      switchtail-exchange) printf 'exchange\n'; saw_exchange=1 ;;
      switchtail-?*)  printf '%s\n' "${cls#switchtail-}" ;;
    esac
  done < <(kdotool search --class 'switchtail-' getwindowclassname '%@' 2>/dev/null)
  [ "$saw_exchange" = 1 ] && _aggregate_labs
}
```

### `bin/stail` — `_emit_session` board stamping

**Analog:** `_emit_session` itself, lines 264–294. The single edit point is the launch line (line 284):

```bash
echo "launch --title \"${E_TITLE[$i]}\" --var lab=${E_LAB[$i]} --var kind=$cvar$flags stail line ${E_LAB[$i]} \"${E_DIR[$i]}\" \"$kind\""
```

Pattern: `flags` is built additively from the kind table (lines 281–283: `_kind_holdable "$cvar" && flags+=" --var holdable=1"`); add `--var board=` the same way (derived once from `$cls`: `board="${cls#switchtail-}"`) and append `$board` as the 4th `stail line` argv. `cmd_line` then defaults `board="${4:-$lab}"` — mirroring the existing optional-arg defaults `dir="${2:-$WORKSPACE/$lab}"` / `kind="${3:-claude}"` (lines 431–432).

### `bin/stail` — `cmd_line` marker write

**Analog:** `cmd_line`, lines 427–479. Insertion point pattern: the existing code does `mkdir -p "$STATE"` then the `cd` guard (lines 433–434):

```bash
mkdir -p "$STATE"
cd "$dir" 2>/dev/null || { echo "stail line: dir '$dir' not found — aborting (refusing to root the pane in \$HOME)" >&2; exit 1; }
```

Call `_run_mark "$lab" "$board" "$kind" "${sid:-}"` AFTER the `cd` guard succeeds and BEFORE the kind dispatch `case`. Note sid is minted later per-branch (lines 458, 473) — either write the marker without sid and accept `sid=` empty, or hoist the write into each branch after sid resolution; the never-fail rule (`_run_mark` always returns 0) is the load-bearing constraint either way.

### `bin/stail` — `cmd_active` rewrite (shape-frozen)

**Analog:** current `cmd_active`, lines 622–641. The JSON/text/exit-code emission is the contract the widget binds to — copy it verbatim, only re-source `lab`:

```bash
cmd_active() {
  _need_kdotool active                                    # ← REMOVE (state read needs no kdotool)
  local json=0 cls lab="" exchange=false
  [ "${1:-}" = "--json" ] && json=1
  cls="$(kdotool getactivewindow getwindowclassname 2>/dev/null)"   # ← REPLACE with $STATE/active read
  case "$cls" in
    switchtail-exchange) lab=exchange; exchange=true ;;
    switchtail-*)   lab="${cls#switchtail-}" ;;
  esac
  if [ "$json" = 1 ]; then
    if [ -n "$lab" ]; then
      printf '{"lab":"%s","display":"%s","exchange":%s}\n' "$lab" "$(_display_name "$lab")" "$exchange"
    else
      printf '{"lab":null,"display":null,"exchange":false}\n'
    fi
  else
    [ -n "$lab" ] && printf '%s\n' "$lab"
  fi
  [ -n "$lab" ]   # exit 0 if on a board, 1 otherwise
}
```

New source: read first line of `$STATE/active`, charset-gate `[[ "$lab" =~ ^[A-Za-z0-9._-]+$ ]] || lab=""` (mirrors `_require_valid_lab`, lines 161–165), cross-check against `_running_labs | grep -qxF -- "$lab"` (RESEARCH "cmd_active from state" example). Everything from `if [ "$json" = 1 ]` down stays byte-identical.

### `bin/stail` — `cmd_list` and `cmd_trunk` adjustments

**Analog:** `cmd_list` lines 645–666 — keep entirely; only delete line 646 `_need_kdotool list` (the new `_running_labs` makes line 650's "one kdotool snapshot" comment a "one state-dir scan"). The `grep -qxF` membership test against `$running_set` and the JSON `printf` loop are unchanged.

`cmd_trunk` already-up warning (lines 508–510) currently keys off kdotool + `_win_ids`:

```bash
if command -v kdotool >/dev/null 2>&1 && [ -n "$(_win_ids "$lab")" ]; then
  echo "stail trunk: a '$lab' board window is already up; opening a second (both share class switchtail-$lab)" >&2
fi
```

Re-key to `_running_labs | grep -qxF -- "$lab"`; drop the `command -v kdotool` guard (state needs none). Keep the warning text shape — test-4 #10 greps `already up` case-insensitively.

### `bin/stail` — `cmd_switch` decision re-source

**Analog:** current `cmd_switch`, lines 670–700. Keep `_need_kdotool switch` (line 671) and both `kdotool windowactivate` calls (681, 691). The exchange-fallback DECISION (line 687) moves off the file grep:

```bash
if [ "$lab" != "exchange" ] && _lab_in_aggregate "$lab"; then   # ← file grep, replace with
# run-marker check: lab has a live marker whose board=exchange (Pitfall 6: adopt live accuracy)
```

The fall-through-to-launch tail (lines 695–699) is the model for the new "state says running but kdotool finds nothing" case: warn + launch, never fail (Pattern 4 in RESEARCH).

### `kitty/state.py` (NEW — focus watcher)

**Analogs:** `kitty/tail.py` (global-watcher file shape) + `kitty/hold.py` (state-dir write + user-var validation).

**File-header safety contract** — copy tail.py's documented-property header style (tail.py lines 1–29). tail.py declares "ONLY ever calls send-text… structurally cannot destroy a pane"; state.py's header must declare the parallel property: **filesystem writes to `$STATE/active` only — no boss window-mutation calls anywhere in this file** (this one-screen auditability is WHY it's a separate file from tail.py).

**Imports pattern** (tail.py lines 31–34):
```python
from typing import Any
from kitty.boss import Boss
from kitty.window import Window
```

**user-var read + charset re-validation pattern** (hold.py lines 19–20, 30–33 — the kitten-side mirror of the CLI charset gate):
```python
_LAB_RE = re.compile(r'[A-Za-z0-9._-]+')
...
    uv = (getattr(w, 'user_vars', {}) or {}) if w else {}
    lab = uv.get('lab')
    if uv.get('holdable') == '1' and lab and _LAB_RE.fullmatch(lab):
```
state.py reads `(window.user_vars or {}).get('board')` and `fullmatch`es the same charset before any path use.

**State-dir path construction pattern** (hold.py lines 35–37):
```python
state = os.path.join(
    os.environ.get('XDG_STATE_HOME', os.path.expanduser('~/.local/state')),
    'switchtail')
```

**Never-let-a-watcher-exception-escape pattern** (tail.py lines 90–92 and hold.py 49–51): wrap the whole hook body in `try/except Exception: pass`.

**Atomic write:** tmp + `os.replace` (the Python mirror of stail's `mv -f` primitive). The complete verified draft of `on_focus_change` (gain → atomic write, loss → compare-and-clear) is in RESEARCH.md "Focus watcher" — use it as written; API signature `on_focus_change(boss, window, data)` with `data={'focused': bool}` is verified against installed kitty 0.47.1.

### `kitty/state.conf` (NEW)

**Analog:** `kitty/tail.conf` — the entire file is one line:
```
watcher tail.py
```
state.conf is `watcher state.py`. Deploy pattern per CLAUDE.md: relative symlinks of both files into `~/.config/kitty/`, plus an `include state.conf` line in `kitty.conf` (alongside the existing hold/keys/tail includes).

### `tests/stail-test-6.sh` (NEW)

**Analogs:** `tests/stail-test-2.sh` Part B (function-sourcing harness + JSON assertions) and `tests/stail-test-1.sh` §6 (isolated-STATE fixture).

**Harness boilerplate** (test-2 lines 1–9, 32–35) — every suite starts this way:
```bash
#!/usr/bin/env bash
set -uo pipefail
pass=0; fail=0
ok(){ printf '  ✓ %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  ✗ %s\n' "$1"; fail=$((fail+1)); }
jsonok(){ printf '%s' "$1" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' 2>/dev/null; }
...
cp ~/.local/bin/stail /tmp/stail-fns.sh
sed -i '/^# ---------- dispatch ----------/,$d' /tmp/stail-fns.sh
source /tmp/stail-fns.sh
```
Per Pitfall 1, parametrize the copy source: `cp "${STAIL_BIN:-$HOME/.local/bin/stail}" /tmp/stail-fns.sh` (apply suite-wide to test-1..5 too).

**Isolated-STATE fixture** (test-1 lines 67–77) — redirect `STATE` to a throwaway dir and seed markers, including a hostile filename to assert the charset gate:
```bash
hcs=/tmp/stail-holdclaim; rm -rf "$hcs"; STATE="$hcs"
mkdir -p "$hcs/hold/zlab"
: > "$hcs/hold/zlab/11111111-2222-3333-4444-555555555555"
: > "$hcs/hold/zlab/not a sid;rm -rf"
```
For run markers: `mkdir -p "$STATE/run/<lab>"`, create "live" markers with background `sleep 60 &` helper PIDs and their real `/proc/<pid>/stat` start times; dead markers with a recycled-looking PID + wrong start time; assert reap (`[ ! -e ... ]` after a `_running_labs` call).

**Exit/summary tail** (test-2 lines 95–97):
```bash
echo; echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
```

### `tests/stail-test-2.sh` / `-3.sh` / `-4.sh` rewrites

**Analog:** the assertions being replaced — preserve each behavioral assertion, swap the fixture from kdotool stub to STATE fixture.

- **test-2 B1–B5** (lines 38–82): the kdotool stub `STUB_CLASSES`/`STUB_ACTIVE` dispatch (lines 39–47) goes away for listing/active; replace with run-marker fixtures + an `$STATE/active` file. Keep B6 (lines 84–93) — switch raise stubs stay kdotool (`windowactivate` log via `/tmp/stail-activate.log`). **B1/B2's exchange union assertion changes meaning** (Pitfall 6): with markers, only labs with a live `board=exchange` pane report running — encode the NEW truth, don't replicate the file-grep over-report.
- **test-3 R2**: switch DECISION fixtures move to state; the raise stub (`kdotool() { ... windowactivate ... }`) pattern from test-2 B6 stays.
- **test-4 #10** (lines 87–90): replace the `kdotool(){ case "$*" in "search --class ^switchtail-claude$") echo '{existing}' ...}` stub with a live run-marker fixture for `claude`; keep the `grep -qi 'already up'` assertion.

### `tests/run-all.sh`

**Analog:** itself, line 7 — add `stail-test-6.sh` to the loop:
```bash
for t in stail-test-1.sh stail-test-2.sh stail-test-3.sh stail-test-4.sh stail-test-5.sh; do
```

## Shared Patterns

### Charset validation before path/JSON use
**Source:** `bin/stail` `_require_valid_lab` (lines 161–165), `_SID_RE` gate in `_hold_claim` (line 239), `hold.py` `_LAB_RE`/`_SID_RE` (lines 19–20, 33, 38)
**Apply to:** every new filename/file-content read — PID filenames `^[0-9]+$`, active-file content `^[A-Za-z0-9._-]+$`, `board` argv validated like `lab`, watcher user-vars `fullmatch`ed.

### Atomic write/claim via rename
**Source:** `_hold_claim` `mv` claim (bin/stail line 241); Python mirror `os.replace`.
**Apply to:** `_run_mark` (tmp + `mv -f`), `state.py` active-file write. Never flock; single-writer-per-file by PID-named construction.

### Never fail the host process
**Source:** hold.py 49–51 (marker failure ⇒ show error, do NOT close), tail.py 90–92 (`except Exception: pass`), `_launch_detached`'s `|| true` tail (bin/stail line 196).
**Apply to:** `_run_mark` (`|| return 0` everywhere — `set -uo pipefail` is active, line 28), `state.py` (blanket try/except).

### /proc stat parsing (strip comm first)
**Source:** RESEARCH.md verified pattern — `rest="${stat##*) }"` then field 20 of the remainder. Never `awk '{print $22}'` directly (comm may contain spaces/parens).
**Apply to:** `_run_mark` (write side) and `_pane_alive` (read side) — identical parse on both.

### Single-source policy via the kind table / single emitter
**Source:** kind table (bin/stail lines 199–218) + `_emit_session` (264–294, "the future multiplexer seam").
**Apply to:** board identity is computed ONCE in `_emit_session` and transported via `--var board=` + argv — never re-derived by grepping files or window classes downstream.

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| — | — | — | None. Every file has a strong in-repo analog; the one genuinely new API surface (`on_focus_change`) is covered by RESEARCH.md's verified draft against installed kitty 0.47.1. |

## Metadata

**Analog search scope:** `bin/`, `kitty/`, `tests/` (whole lab; `plasmoid/` and `systemd/` untouched this phase per RESEARCH)
**Files scanned:** bin/stail (714 lines, full), kitty/hold.py, kitty/tail.py, kitty/tail.conf, tests/stail-test-2.sh, tests/run-all.sh, targeted greps of tests/stail-test-1.sh and stail-test-4.sh
**Pattern extraction date:** 2026-06-12
