#!/usr/bin/env bash
# Regression tests for the review-driven fixes R2/R3/R4 against the REAL stail functions.
set -uo pipefail
STAIL_BIN="${STAIL_BIN:-$HOME/.local/bin/stail}"
pass=0; fail=0
ok(){ printf '  ✓ %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  ✗ %s\n' "$1"; fail=$((fail+1)); }

cp "$STAIL_BIN" /tmp/stail-fns.sh || { echo "FATAL: cannot copy stail under test: $STAIL_BIN" >&2; exit 1; }
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
out="$(command "$STAIL_BIN" switch '../../evil' 2>&1)"; rc=$?
echo "  switch ../../evil -> rc=$rc: $out"
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'invalid lab name' && ok "switch rejects traversal (exit 2, no launch)" || no "switch didn't reject traversal"
out="$(command "$STAIL_BIN" line '../../evil' /tmp 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'invalid lab name' && ok "line rejects traversal (exit 2, no claude)" || no "line did not reject traversal"

# Live-marker fixtures for the R2 switch-DECISION tests: a "live" marker is backed by a
# real background sleep helper with its real /proc start time (the writer's exact format).
# The decision reads $STATE/run; the RAISE stays kdotool (activate-log stubs as before).
proc_start(){ local s; s="$(cat "/proc/$1/stat" 2>/dev/null)" || return 1; s="${s##*) }"; awk '{print $20}' <<<"$s"; }
HELPERS=(); R2DIRS=()
mk_marker(){ # $1=lab $2=board -> write one LIVE marker for lab; echoes the helper pid
  sleep 60 >/dev/null 2>&1 & local hp=$!
  HELPERS+=("$hp")
  mkdir -p "$STATE/run/$1"
  printf 'start=%s\nboard=%s\nkind=claude\nsid=\n' "$(proc_start "$hp")" "$2" > "$STATE/run/$1/$hp"
  printf '%s' "$hp"
}
r2_state(){ STATE="$(mktemp -d)/state"; R2DIRS+=("$(dirname "$STATE")"); }

echo "== R2: _lab_in_exchange reads LIVE board=exchange markers =="
r2_state
mk_marker agent exchange >/dev/null
mk_marker proton proton >/dev/null
_lab_in_exchange agent && ok "live exchange line -> in exchange" || no "live exchange marker missed"
_lab_in_exchange proton && no "standalone marker counted as an exchange line" || ok "standalone (board=proton) marker is NOT an exchange line"
dead="$(mk_marker zombie exchange)"; kill "$dead" 2>/dev/null; wait "$dead" 2>/dev/null
_lab_in_exchange zombie && no "DEAD exchange marker counted live" || ok "dead exchange marker -> not in exchange (live accuracy)"
_lab_in_exchange nope_not_a_lab && no "matched a lab with no markers" || ok "no markers at all -> not in exchange"

echo "== R2: cmd_switch raises the exchange when a lab is live only inside it =="
r2_state
mk_marker agent exchange >/dev/null     # agent lives ONLY as a line in the exchange board
: > /tmp/r2-activate.log
# stub kdotool: agent has NO standalone window; the exchange window IS up (raise stays kdotool).
kdotool() {
  case "$*" in
    "search --class ^switchtail-agent$")    : ;;                              # no standalone agent window
    "search --class ^switchtail-exchange$") printf '%s\n' '{exchange-win}' ;; # exchange is up
    windowactivate\ *)                      shift; echo "$*" >>/tmp/r2-activate.log ;;
    *) : ;;
  esac
}
warn="$(cmd_switch agent 2>&1 >/dev/null)"; act="$(cat /tmp/r2-activate.log)"
echo "  activated: $act ; warn: $warn"
[ "$act" = '{exchange-win}' ] && ok "raises the exchange window (no duplicate launch)" || no "did not raise exchange: '$act'"
echo "$warn" | grep -q 'exchange' && ok "explains it is raising the exchange" || no "no exchange note"

echo "== R2: a standalone window still wins over the exchange =="
: > /tmp/r2-activate.log
# same STATE — agent STILL has a live exchange marker, but a standalone window exists too
kdotool() {
  case "$*" in
    "search --class ^switchtail-agent$")    printf '%s\n' '{standalone-agent}' ;;
    "search --class ^switchtail-exchange$") printf '%s\n' '{exchange-win}' ;;
    windowactivate\ *)                      shift; echo "$*" >>/tmp/r2-activate.log ;;
    *) : ;;
  esac
}
cmd_switch agent >/dev/null 2>&1; act="$(cat /tmp/r2-activate.log)"
[ "$act" = '{standalone-agent}' ] && ok "standalone agent window raised (not the exchange)" || no "raised wrong window: '$act'"

echo "== R2: no LIVE marker (only a dead exchange line) -> launches (no false raise) =="
r2_state
dead="$(mk_marker proton exchange)"; kill "$dead" 2>/dev/null; wait "$dead" 2>/dev/null
: > /tmp/r2-launch.log
kdotool() { case "$*" in "search --class ^switchtail-"*) : ;; *) : ;; esac; }   # nothing is up
_launch_detached() { echo "LAUNCH: $*" >>/tmp/r2-launch.log; }               # stub the launch
# proton's exchange line already DIED (OQ-2 live truth: NOT running) -> must launch fresh
cmd_switch proton >/dev/null 2>&1; launched="$(cat /tmp/r2-launch.log)"
echo "  $launched"
echo "$launched" | grep -q 'proton.kitty-session' && ok "launches the session when nothing is live" || no "did not launch: '$launched'"

echo; echo "RESULT: $pass passed, $fail failed"
for hp in "${HELPERS[@]:-}"; do kill "$hp" 2>/dev/null; wait "$hp" 2>/dev/null; done
rm -rf "$ws" "${R2DIRS[@]:-}" /tmp/r3warn /tmp/r2-activate.log /tmp/r2-launch.log
[ "$fail" -eq 0 ]
