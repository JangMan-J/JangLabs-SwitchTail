#!/usr/bin/env bash
# Window-path verification. Part A: a real two-window spawn proving the chained kdotool
# primitive returns one class PER window (the raise path's search primitive). Part B:
# state-sourced listing/active against live run-marker fixtures (real sleep-helper PIDs
# with real /proc start times — detection reads $STATE/run + $STATE/active, never
# kdotool), plus the B6 raise stub (switch id-reuse + dup-warn — raise STAYS kdotool).
set -uo pipefail
STAIL_BIN="${STAIL_BIN:-$HOME/.local/bin/stail}"
pass=0; fail=0
ok(){ printf '  ✓ %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  ✗ %s\n' "$1"; fail=$((fail+1)); }
jsonok(){ printf '%s' "$1" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' 2>/dev/null; }

echo "== A. real two-window chained getwindowclassname (#4 primitive) =="
tag="switchtail-zzt-$$"
class_a="${tag}A"
class_b="${tag}B"
setsid kitty --class "$class_a" -e sh -c 'sleep 30' >/dev/null 2>&1 &
setsid kitty --class "$class_b" -e sh -c 'sleep 30' >/dev/null 2>&1 &
cls=()
for _ in {1..30}; do
  mapfile -t cls < <(kdotool search --class "$tag" getwindowclassname '%@' 2>/dev/null | sort -u)
  [ "${#cls[@]}" -eq 2 ] && [ "${cls[0]}" = "$class_a" ] && [ "${cls[1]}" = "$class_b" ] && break
  sleep 0.2
done
echo "  classes: ${cls[*]:-<none>}"
[ "${#cls[@]}" -eq 2 ] && [ "${cls[0]}" = "$class_a" ] && [ "${cls[1]}" = "$class_b" ] \
  && ok "one class per window, both seen in a single call" || no "chained output wrong: ${cls[*]:-none}"
kdotool search --class "^${class_a}\$" windowclose >/dev/null 2>&1
kdotool search --class "^${class_b}\$" windowclose >/dev/null 2>&1
pkill -x -f 'sleep 30' 2>/dev/null
sleep 0.4

echo "== B. state-sourced listing/active + stubbed-kdotool raise =="
cp "$STAIL_BIN" /tmp/stail-fns.sh || { echo "FATAL: cannot copy stail under test: $STAIL_BIN" >&2; exit 1; }
sed -i '/^# ---------- dispatch ----------/,$d' /tmp/stail-fns.sh
# shellcheck disable=SC1091
source /tmp/stail-fns.sh

# Live-marker fixtures: a "live" marker is backed by a real background sleep helper whose
# /proc start time is recorded in the marker — exactly the writer's format. proc_start is
# the same comm-strip parse the helpers use (strip "pid (comm) ", then field 20 = overall 22).
proc_start(){ local s; s="$(cat "/proc/$1/stat" 2>/dev/null)" || return 1; s="${s##*) }"; awk '{print $20}' <<<"$s"; }
HELPERS=(); STATEDIRS=()
mk_marker(){ # $1=lab $2=board -> write one LIVE marker for lab; echoes the helper pid
  sleep 60 >/dev/null 2>&1 & local hp=$!
  HELPERS+=("$hp")
  mkdir -p "$STATE/run/$1"
  printf 'start=%s\nboard=%s\nkind=claude\nsid=\n' "$(proc_start "$hp")" "$2" > "$STATE/run/$1/$hp"
  printf '%s' "$hp"
}
state_reset(){ STATE="$(mktemp -d)/state"; STATEDIRS+=("$(dirname "$STATE")"); }

echo "-- B1. running-set: standalone agent + live exchange lines (markers) --"
state_reset
mk_marker agent agent >/dev/null
for l in jangsjyro proton switchtail synapse; do mk_marker "$l" exchange >/dev/null; done
run="$(_running_labs | sort -u | tr '\n' ' ')"
echo "  running set: $run"
for l in agent exchange jangsjyro proton switchtail synapse; do
  echo "$run" | grep -qw "$l" || { no "running set missing $l"; }; done
echo "$run" | grep -qw proton && echo "$run" | grep -qw exchange && ok "exchange-union: every lab with a LIVE exchange line counts (#2)" || no "exchange-union failed"
# inverse (new truth, OQ-2): a lab whose exchange line already DIED no longer reports running
dead="$(mk_marker zombie exchange)"
kill "$dead" 2>/dev/null; wait "$dead" 2>/dev/null
run="$(_running_labs | sort -u | tr '\n' ' ')"
echo "$run" | grep -qw zombie && no "dead exchange line still reports its lab running" || ok "closed exchange line no longer reports its lab (live accuracy)"

echo "-- B2. list --json with exchange up: marker-backed labs running, valid JSON --"
j="$(cmd_list --json)"; echo "  $j"
jsonok "$j" && ok "list --json is valid JSON" || no "list --json invalid"
echo "$j" | grep -q '"lab":"agent","display":"Agent","running":true' && ok "agent shows running (standalone marker)" || no "agent not running"
echo "$j" | grep -q '"lab":"proton","display":"Proton","running":true' && ok "proton shows running via its live exchange line" || no "proton not running via exchange"

echo "-- B3. list --json nothing up: all running=false --"
state_reset
j="$(cmd_list --json)"; jsonok "$j" && ok "empty-state list --json valid" || no "empty list invalid"
echo "$j" | grep -q '"running":true' && no "something shows running with no markers" || ok "all labs down when no markers"

echo "-- B4. list --json one standalone (synapse), no exchange: only synapse up --"
state_reset
mk_marker synapse synapse >/dev/null
j="$(cmd_list --json)"
echo "$j" | grep -q '"lab":"synapse","display":"Synapse","running":true' && ok "synapse running" || no "synapse not running"
echo "$j" | grep -q '"lab":"proton","display":"Proton","running":false' && ok "proton correctly down (no false all-union)" || no "proton wrongly running"

echo "-- B5. active --json from \$STATE/active + liveness cross-check --"
state_reset
mk_marker jangsjyro jangsjyro >/dev/null
printf 'jangsjyro\n' > "$STATE/active"
j="$(cmd_active --json)"; rc=$?
echo "  $j (exit $rc)"
jsonok "$j" && [ "$rc" -eq 0 ] && echo "$j" | grep -q '"lab":"jangsjyro"' && ok "active --json on board, exit 0" || no "active on board wrong"
for l in proton synapse; do mk_marker "$l" exchange >/dev/null; done
printf 'exchange\n' > "$STATE/active"
[ "$(cmd_active)" = exchange ] && ok "active text prints 'exchange' for aggregate" || no "active exchange wrong"
rm -f "$STATE/active"   # focus left every board (the watcher compare-and-cleared)
j="$(cmd_active --json)"; rc=$?
jsonok "$j" && [ "$rc" -eq 1 ] && echo "$j" | grep -q '"lab":null' && ok "active --json off board -> null + exit 1" || no "active off-board wrong (exit $rc)"

echo "-- B6. switch id-reuse + duplicate warning (#9) — raise stays kdotool --"
STUB_IDS=(); : > /tmp/stail-activate.log
kdotool() {
  case "$*" in
    "search --class ^switchtail-agent$") printf '%s\n' "${STUB_IDS[@]:-}" ;;
    windowactivate\ *)                   shift; echo "$*" >>/tmp/stail-activate.log ;;
    *) : ;;
  esac
}
STUB_IDS=('{id-one}' '{id-two}')
warn="$(cmd_switch agent 2>&1 >/dev/null)"; act="$(cat /tmp/stail-activate.log)"
echo "  activated: $act ; warn: $warn"
[ "$act" = '{id-one}' ] && ok "raises the FIRST reused id (no re-search)" || no "activated wrong id: $act"
echo "$warn" | grep -q 'multiple' && ok "warns on duplicate boards" || no "no duplicate warning"
: > /tmp/stail-activate.log
STUB_IDS=('{only}')
cmd_switch agent >/dev/null 2>&1; act="$(cat /tmp/stail-activate.log)"
[ "$act" = '{only}' ] && ok "single board raised by its id" || no "single raise wrong: $act"

echo; echo "RESULT: $pass passed, $fail failed"
for hp in "${HELPERS[@]:-}"; do kill "$hp" 2>/dev/null; wait "$hp" 2>/dev/null; done
rm -rf "${STATEDIRS[@]:-}" /tmp/stail-activate.log
[ "$fail" -eq 0 ]
