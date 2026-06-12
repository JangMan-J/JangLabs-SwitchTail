#!/usr/bin/env bash
# State-seam verification (writer side) against the REAL stail functions: run-marker
# write atomicity + content (_run_mark), the /proc start-time liveness predicate with
# its PID-reuse guard (_pane_alive), the never-fail discipline (a marker failure must
# degrade listing, never kill a pane), and the e2e `stail line` lifecycle. Live markers
# use background `sleep` helper PIDs with real /proc start times — no fixed sleeps as
# synchronization. Reader-side sections (§5-§7): lazy reap + hostile-filename gate,
# the SEAM-01 no-kdotool-consult proof for list/active, and the active-file staleness
# cross-check. Set STAIL_BIN=<path> to test a checkout instead of the deployed default.
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

echo "== 5. reader: lazy reap + hostile-filename gate (_running_labs) =="
r5="$(mktemp -d)"; STATE="$r5/state"
sleep 60 >/dev/null 2>&1 & h5=$!
ds="$(proc_start "$h5")"
kill "$h5" 2>/dev/null; wait "$h5" 2>/dev/null
mkdir -p "$STATE/run/deadlab"
printf 'start=%s\nboard=deadlab\nkind=claude\nsid=\n' "$ds" > "$STATE/run/deadlab/$h5"   # dead: real format, helper killed
hostile="$STATE/run/deadlab/not-a-pid;x"
printf 'start=1\nboard=deadlab\nkind=claude\nsid=\n' > "$hostile"                        # hostile: must never reach /proc or rm
out5="$(_running_labs)"
[ ! -e "$STATE/run/deadlab/$h5" ] && ok "dead marker REMOVED by one _running_labs call (lazy reap)" || no "dead marker not reaped"
[ -e "$hostile" ] && ok "hostile filename ignored AND left untouched" || no "hostile filename was removed"
printf '%s\n' "$out5" | grep -qxF deadlab && no "lab with only-dead markers reported running" || ok "only-dead lab absent from the running set"

echo "== 6. SEAM-01 proof: list/active never consult kdotool (logging fail-stub) =="
r6="$(mktemp -d)"; STATE="$r6/state"
ws6="$r6/ws"; mkdir -p "$ws6/zlab"; : > "$ws6/zlab/.git"; WORKSPACE="$ws6"   # one-lab workspace fixture
klog="$r6/kdotool-consult.log"; : > "$klog"
kdotool(){ echo "CONSULTED: $*" >>"$klog"; return 1; }
sleep 60 >/dev/null 2>&1 & h6=$!
mkdir -p "$STATE/run/zlab"
printf 'start=%s\nboard=zlab\nkind=claude\nsid=\n' "$(proc_start "$h6")" > "$STATE/run/zlab/$h6"
printf 'zlab\n' > "$STATE/active"
out="$(cmd_list)"
echo "$out" | grep -q 'zlab.*running' && ok "cmd_list reports the marker-backed lab running" || no "cmd_list text wrong: [$out]"
j="$(cmd_list --json)"
[ "$j" = '[{"lab":"zlab","display":"Zlab","running":true}]' ] && ok "cmd_list --json byte-shape held" || no "cmd_list --json wrong: [$j]"
a="$(cmd_active)"; rc=$?
[ "$a" = "zlab" ] && [ "$rc" -eq 0 ] && ok "cmd_active prints the active board, exit 0" || no "cmd_active wrong: [$a] rc=$rc"
aj="$(cmd_active --json)"; rc=$?
[ "$aj" = '{"lab":"zlab","display":"Zlab","exchange":false}' ] && [ "$rc" -eq 0 ] && ok "cmd_active --json on-board byte-shape held" || no "cmd_active --json wrong: [$aj] rc=$rc"
[ ! -s "$klog" ] && ok "kdotool consult log EMPTY after all four list/active calls (SEAM-01)" || no "detection consulted kdotool: $(cat "$klog")"
sed -n '/^cmd_switch()/,/^}/p' /tmp/stail-fns6.sh | grep -q '_need_kdotool switch' \
  && ok "cmd_switch still gates on _need_kdotool (raise path kept)" || no "switch kdotool gate missing"
kill "$h6" 2>/dev/null; wait "$h6" 2>/dev/null
unset -f kdotool

echo "== 7. active staleness cross-check: dead board / missing file -> off-board =="
r7="$(mktemp -d)"; STATE="$r7/state"; mkdir -p "$STATE"
printf 'ghostlab\n' > "$STATE/active"      # stale: names a board with NO live marker
a="$(cmd_active)"; rc=$?
[ -z "$a" ] && [ "$rc" -eq 1 ] && ok "stale active (no live marker) -> prints nothing, exit 1" || no "stale active leaked: [$a] rc=$rc"
j="$(cmd_active --json)"; rc=$?
[ "$j" = '{"lab":null,"display":null,"exchange":false}' ] && [ "$rc" -eq 1 ] && ok "stale active --json -> null shape byte-match + exit 1" || no "stale json wrong: [$j] rc=$rc"
rm -f "$STATE/active"                      # watcher not loaded yet / cleared
j="$(cmd_active --json)"; rc=$?
[ "$j" = '{"lab":null,"display":null,"exchange":false}' ] && [ "$rc" -eq 1 ] && ok "missing active file -> same off-board degraded mode" || no "missing-file json wrong: [$j] rc=$rc"

echo; echo "RESULT: $pass passed, $fail failed"
rm -rf "$root" "$xs" "$r5" "$r6" "$r7"; chmod 755 "$ro" 2>/dev/null; rm -rf "$ro"
[ "$fail" -eq 0 ]
