#!/usr/bin/env bash
# Window-path verification. Part A: a real two-window spawn proving the chained kdotool
# primitive returns one class PER window. Part B: a deterministic kdotool stub exercising
# stail's consumption logic (running-set, JSON, switch id-reuse + dup-warn) with no focus theft.
set -uo pipefail
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

echo "== B. stubbed-kdotool logic =="
cp ~/.local/bin/stail /tmp/stail-fns.sh
sed -i '/^# ---------- dispatch ----------/,$d' /tmp/stail-fns.sh
# shellcheck disable=SC1091
source /tmp/stail-fns.sh

# deterministic kdotool stub: dispatch on the joined argument string
STUB_CLASSES=(); STUB_ACTIVE=""; STUB_IDS=(); : > /tmp/stail-activate.log
kdotool() {
  case "$*" in
    "search --class switchtail- getwindowclassname %@") printf '%s\n' "${STUB_CLASSES[@]:-}" ;;
    "getactivewindow getwindowclassname")            printf '%s\n' "$STUB_ACTIVE" ;;
    "search --class ^switchtail-agent$")                printf '%s\n' "${STUB_IDS[@]:-}" ;;
    windowactivate\ *)                               shift; echo "$*" >>/tmp/stail-activate.log ;;
    *) : ;;
  esac
}

echo "-- B1. running-set: standalone agent + aggregate all --"
STUB_CLASSES=(switchtail-agent switchtail-all)
run="$(_running_labs | sort -u | tr '\n' ' ')"
echo "  running set: $run"
for l in agent all claude jangsjedi jangsjyro proton; do
  echo "$run" | grep -qw "$l" || { no "running set missing $l"; }; done
echo "$run" | grep -qw proton && echo "$run" | grep -qw all && ok "all-union expands aggregate to every pane (#2)" || no "all-union failed"

echo "-- B2. list --json with 'all' up: every lab running, valid JSON --"
j="$(cmd_list --json)"; echo "  $j"
jsonok "$j" && ok "list --json is valid JSON" || no "list --json invalid"
echo "$j" | grep -q '"lab":"agent","display":"Agent","running":true' && ok "agent shows running under all" || no "agent not running under all"

echo "-- B3. list --json nothing up: all running=false --"
STUB_CLASSES=()
j="$(cmd_list --json)"; jsonok "$j" && ok "empty-state list --json valid" || no "empty list invalid"
echo "$j" | grep -q '"running":true' && no "something shows running with no windows" || ok "all labs down when nothing up"

echo "-- B4. list --json one standalone (claude), no all: only claude up --"
STUB_CLASSES=(switchtail-claude)
j="$(cmd_list --json)"
echo "$j" | grep -q '"lab":"claude","display":"Claude","running":true' && ok "claude running" || no "claude not running"
echo "$j" | grep -q '"lab":"proton","display":"Proton","running":false' && ok "proton correctly down (no false all-union)" || no "proton wrongly running"

echo "-- B5. active --json on a cockpit + off it --"
STUB_ACTIVE="switchtail-jangsjyro"
j="$(cmd_active --json)"; rc=$?
echo "  $j (exit $rc)"
jsonok "$j" && [ "$rc" -eq 0 ] && echo "$j" | grep -q '"lab":"jangsjyro"' && ok "active --json on cockpit, exit 0" || no "active on cockpit wrong"
STUB_ACTIVE="switchtail-all"
[ "$(cmd_active)" = all ] && ok "active text prints 'all' for aggregate" || no "active all wrong"
STUB_ACTIVE="kitty"
j="$(cmd_active --json)"; rc=$?
jsonok "$j" && [ "$rc" -eq 1 ] && echo "$j" | grep -q '"lab":null' && ok "active --json off cockpit -> null + exit 1" || no "active off-cockpit wrong (exit $rc)"

echo "-- B6. switch id-reuse + duplicate warning (#9) --"
STUB_IDS=('{id-one}' '{id-two}')
warn="$(cmd_switch agent 2>&1 >/dev/null)"; act="$(cat /tmp/stail-activate.log)"
echo "  activated: $act ; warn: $warn"
[ "$act" = '{id-one}' ] && ok "raises the FIRST reused id (no re-search)" || no "activated wrong id: $act"
echo "$warn" | grep -q 'multiple' && ok "warns on duplicate cockpits" || no "no duplicate warning"
: > /tmp/stail-activate.log
STUB_IDS=('{only}')
cmd_switch agent >/dev/null 2>&1; act="$(cat /tmp/stail-activate.log)"
[ "$act" = '{only}' ] && ok "single cockpit raised by its id" || no "single raise wrong: $act"

echo; echo "RESULT: $pass passed, $fail failed"
rm -f /tmp/stail-activate.log
[ "$fail" -eq 0 ]
