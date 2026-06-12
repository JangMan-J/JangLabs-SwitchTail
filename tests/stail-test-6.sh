#!/usr/bin/env bash
# State-seam verification (writer side) against the REAL stail functions: run-marker
# write atomicity + content (_run_mark), the /proc start-time liveness predicate with
# its PID-reuse guard (_pane_alive), the never-fail discipline (a marker failure must
# degrade listing, never kill a pane), and the e2e `stail line` lifecycle. Live markers
# use background `sleep` helper PIDs with real /proc start times — no fixed sleeps as
# synchronization. Reader-side sections (list/active/reap from state) are appended by
# plan 01-04. Set STAIL_BIN=<path> to test a checkout instead of the deployed default.
set -uo pipefail
STAIL_BIN="${STAIL_BIN:-$HOME/.local/bin/stail}"
pass=0; fail=0
ok(){ printf '  ✓ %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  ✗ %s\n' "$1"; fail=$((fail+1)); }

# Unique temp copy (NOT the shared /tmp/stail-fns.sh) so a concurrently running suite
# can never clobber the functions under test mid-run.
cp "$STAIL_BIN" /tmp/stail-fns6.sh || { echo "FATAL: cannot copy stail under test: $STAIL_BIN" >&2; exit 1; }
sed -i '/^# ---------- dispatch ----------/,$d' /tmp/stail-fns6.sh
# shellcheck disable=SC1091
source /tmp/stail-fns6.sh

# The suite's own /proc start-time oracle — the SAME comm-strip parse the helpers use
# (strip through the last ') ', then field 20 of the remainder = overall stat field 22).
proc_start(){ local s; s="$(cat "/proc/$1/stat" 2>/dev/null)" || return 1; s="${s##*) }"; awk '{print $20}' <<<"$s"; }

echo "== 1. _run_mark: atomic write, content lines, own-PID filename =="
root="$(mktemp -d)"; STATE="$root/state"
_run_mark zlab zboard claude ""
m="$STATE/run/zlab/$$"
[ -f "$m" ] && ok "marker exists at \$STATE/run/<lab>/\$\$ (writer-PID filename)" || no "marker missing: $m"
want="$(proc_start $$)"
grep -q "^start=${want}\$" "$m" 2>/dev/null && ok "start= equals our own /proc start time ($want)" || no "start= wrong: [$(grep '^start=' "$m" 2>/dev/null)] want [$want]"
grep -q '^board=zboard$' "$m" 2>/dev/null && ok "board= recorded" || no "board= wrong"
grep -q '^kind=claude$' "$m" 2>/dev/null && ok "kind= recorded" || no "kind= wrong"
grep -q '^sid=$' "$m" 2>/dev/null && ok "sid= line present and empty (sid optional by contract)" || no "sid line wrong"
if compgen -G "$STATE/run/zlab/*.tmp" >/dev/null; then no "tmp file leaked beside the marker"; else ok "no .tmp leftover (tmp + mv -f write)"; fi

echo "== 2. _pane_alive: liveness + start-time PID-reuse guard =="
sleep 60 & hp=$!
hs="$(proc_start "$hp")"
[ -n "$hs" ] && ok "helper start time read from /proc ($hs)" || no "could not read helper start time"
_pane_alive "$hp" "$hs" && ok "live helper + matching start -> alive" || no "live helper read dead"
_pane_alive "$hp" "$((hs+1))" && no "start-time mismatch read alive (PID-reuse hole)" || ok "start-time mismatch -> dead (PID-reuse guard)"
kill "$hp" 2>/dev/null; wait "$hp" 2>/dev/null
_pane_alive "$hp" "$hs" && no "dead helper read alive" || ok "killed + reaped helper -> dead"

echo "== 3. never-fail: an unwritable STATE degrades listing, never the pane =="
ro="$(mktemp -d)"; chmod 555 "$ro"
STATE="$ro/state"            # mkdir -p under the 555 dir fails
_run_mark zlab zlab claude ""; rc=$?
[ "$rc" -eq 0 ] && ok "_run_mark returns 0 with an unwritable STATE" || no "_run_mark leaked failure (rc=$rc)"
XDG_STATE_HOME="$ro/xdg" bash "$STAIL_BIN" line zlab /tmp 'cmd:true' >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "e2e: stail line still boots the pane (exec true) with unwritable state dir" || no "marker failure killed the pane (rc=$rc)"

echo "== 4. e2e lifecycle: stail line writes one complete marker, then reads reap-eligible =="
xs="$(mktemp -d)"
XDG_STATE_HOME="$xs" bash "$STAIL_BIN" line zlab /tmp 'cmd:true' zboard >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "cmd:true pane boots and exits 0" || no "stail line rc=$rc"
d="$xs/switchtail/run/zlab"
n="$(ls -1 "$d" 2>/dev/null | wc -l)"
[ "$n" -eq 1 ] && ok "exactly one marker written under run/<lab>/" || no "marker count: $n"
f="$(ls -1 "$d" 2>/dev/null | head -n1)"
[[ "$f" =~ ^[0-9]+$ ]] && ok "marker filename is the pane PID (numeric)" || no "filename not numeric: [$f]"
grep -q '^board=zboard$' "$d/$f" 2>/dev/null && ok "marker carries board= from the 4th argv" || no "board content wrong"
grep -q '^kind=cmd:true$' "$d/$f" 2>/dev/null && ok "marker carries the full cmd: kind" || no "kind content wrong"
ms="$(grep -m1 '^start=' "$d/$f" 2>/dev/null | cut -d= -f2)"
_pane_alive "$f" "$ms" && no "dead pane's marker reads alive" || ok "exec'd true exited -> marker reap-eligible (_pane_alive false)"

echo; echo "RESULT: $pass passed, $fail failed"
rm -rf "$root" "$xs"; chmod 755 "$ro" 2>/dev/null; rm -rf "$ro"
[ "$fail" -eq 0 ]
