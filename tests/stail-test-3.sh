#!/usr/bin/env bash
# Regression tests for the review-driven fixes R2/R3/R4 against the REAL stail functions.
set -uo pipefail
pass=0; fail=0
ok(){ printf '  ✓ %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  ✗ %s\n' "$1"; fail=$((fail+1)); }

cp ~/.local/bin/stail /tmp/stail-fns.sh
sed -i '/^# ---------- dispatch ----------/,$d' /tmp/stail-fns.sh
# shellcheck disable=SC1091
source /tmp/stail-fns.sh

echo "== R3: a 'switchtail-exchange' lab dir is reserved (won't clobber the aggregate session) =="
ws=/tmp/stail-test-ws3; rm -rf "$ws"; mkdir -p "$ws"
for n in agent switchtail-exchange exchange build good; do mkdir -p "$ws/$n" && : > "$ws/$n/.git"; done
WORKSPACE="$ws"
disc="$(_discover_labs 2>/tmp/r3warn | tr '\n' ' ')"
echo "  discovered: [$disc]"; echo "  warn: $(cat /tmp/r3warn)"
[ "$disc" = "agent good " ] && ok "switchtail-exchange/exchange/build reserved; only agent+good kept" || no "discovery wrong: [$disc]"

echo "== R4: _require_valid_lab gates argv lab names =="
( _require_valid_lab switch agent ) 2>/dev/null && ok "accepts 'agent'" || no "rejected valid 'agent'"
( _require_valid_lab switch all ) 2>/dev/null && ok "accepts 'all'" || no "rejected 'all'"
( _require_valid_lab switch '../../etc' ) 2>/dev/null && no "accepted traversal '../../etc'" || ok "rejects traversal '../../etc' (exit nonzero)"
( _require_valid_lab switch 'a b' ) 2>/dev/null && no "accepted spaced name" || ok "rejects 'a b'"
# exit code is 2
( _require_valid_lab switch '../x' ) 2>/dev/null; [ $? -eq 2 ] && ok "invalid name exits 2" || no "wrong exit code for invalid name"

echo "== R4: cmd_switch/cmd_line reject bad names end-to-end =="
WORKSPACE="$HOME/JangLabs"   # real workspace for sess paths
out="$(command ~/.local/bin/stail switch '../../evil' 2>&1)"; rc=$?
echo "  switch ../../evil -> rc=$rc: $out"
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'invalid lab name' && ok "switch rejects traversal (exit 2, no launch)" || no "switch didn't reject traversal"
out="$(command ~/.local/bin/stail line '../../evil' /tmp 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'invalid lab name' && ok "line rejects traversal (exit 2, no claude)" || no "line did not reject traversal"

echo "== R2: aggregate helpers =="
agg="$(_aggregate_labs | tr '\n' ' ')"; echo "  aggregate labs: $agg"
echo "$agg" | grep -qw agent && echo "$agg" | grep -qw proton && ok "_aggregate_labs lists the panes" || no "_aggregate_labs wrong"
_lab_in_aggregate agent && ok "_lab_in_aggregate agent = true" || no "_lab_in_aggregate agent false"
_lab_in_aggregate nope_not_a_lab && no "_lab_in_aggregate matched a non-pane" || ok "_lab_in_aggregate rejects a non-pane"

echo "== R2: cmd_switch raises the exchange when a lab is live only inside it =="
: > /tmp/r2-activate.log
# stub kdotool: agent has NO standalone window; the aggregate 'all' window IS up.
kdotool() {
  case "$*" in
    "search --class ^switchtail-agent$")  : ;;                       # no standalone agent window
    "search --class ^switchtail-exchange$")    printf '%s\n' '{exchange-win}' ;; # exchange is up
    windowactivate\ *)                 shift; echo "$*" >>/tmp/r2-activate.log ;;
    *) : ;;
  esac
}
warn="$(cmd_switch agent 2>&1 >/dev/null)"; act="$(cat /tmp/r2-activate.log)"
echo "  activated: $act ; warn: $warn"
[ "$act" = '{exchange-win}' ] && ok "raises the exchange window (no duplicate launch)" || no "did not raise exchange: '$act'"
echo "$warn" | grep -q 'exchange' && ok "explains it is raising the exchange" || no "no exchange note"

echo "== R2: a standalone window still wins over the exchange =="
: > /tmp/r2-activate.log
kdotool() {
  case "$*" in
    "search --class ^switchtail-agent$")  printf '%s\n' '{standalone-agent}' ;;
    "search --class ^switchtail-exchange$")    printf '%s\n' '{exchange-win}' ;;
    windowactivate\ *)                 shift; echo "$*" >>/tmp/r2-activate.log ;;
    *) : ;;
  esac
}
cmd_switch agent >/dev/null 2>&1; act="$(cat /tmp/r2-activate.log)"
[ "$act" = '{standalone-agent}' ] && ok "standalone agent window raised (not the exchange)" || no "raised wrong window: '$act'"

echo "== R2: lab neither standalone nor in aggregate -> launches (no false raise) =="
: > /tmp/r2-launch.log
kdotool() { case "$*" in "search --class ^switchtail-"*) : ;; *) : ;; esac; }   # nothing is up
_launch_detached() { echo "LAUNCH: $*" >>/tmp/r2-launch.log; }               # stub the launch
# 'proton' is in the aggregate set, but aggregate isn't up (kdotool returns nothing), so it must launch
cmd_switch proton >/dev/null 2>&1; launched="$(cat /tmp/r2-launch.log)"
echo "  $launched"
echo "$launched" | grep -q 'proton.kitty-session' && ok "launches the session when nothing is up" || no "did not launch: '$launched'"

echo; echo "RESULT: $pass passed, $fail failed"
rm -rf "$ws" /tmp/r3warn /tmp/r2-activate.log /tmp/r2-launch.log
[ "$fail" -eq 0 ]
