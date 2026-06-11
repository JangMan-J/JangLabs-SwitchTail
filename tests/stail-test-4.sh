#!/usr/bin/env bash
# Regression tests for `stail fleet` (N parallel claude panes in one cockpit window) against
# the REAL stail functions. Covers the session emitter (_emit_fleet_session) and the subcommand
# (cmd_fleet): count, class, per-pane park tags, master focus, count validation + clamping, the
# SWITCHTAIL_FLEET_MAX tunable, lab-name validation, missing-dir guard, and the detach construction
# (the session is rebuilt INSIDE a `bash -c` so it survives systemd-run/setsid severing stdin).
set -uo pipefail
pass=0; fail=0
ok(){ printf '  ✓ %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  ✗ %s\n' "$1"; fail=$((fail+1)); }

cp ~/.local/bin/stail /tmp/stail-fns.sh
sed -i '/^# ---------- dispatch ----------/,$d' /tmp/stail-fns.sh
# shellcheck disable=SC1091
source /tmp/stail-fns.sh

echo "== 1. _emit_fleet_session shape (count, class, tags, single focus) =="
WORKSPACE="$HOME/JangLabs"
s="$(_emit_fleet_session claude 3)"
[ "$(printf '%s\n' "$s" | grep -c '^launch ')" -eq 3 ] && ok "N=3 emits 3 launch lines" || no "wrong launch count"
[ "$(printf '%s\n' "$s" | grep -c '^focus$')" -eq 1 ] && ok "exactly one focus (the master pane)" || no "focus count wrong"
printf '%s\n' "$s" | grep -qx 'os_window_class switchtail-claude' && ok "class is switchtail-claude (contract preserved)" || no "class wrong"
[ "$(printf '%s\n' "$s" | grep -c -- '--var lab=claude --var cockpit=claude')" -eq 3 ] \
  && ok "every pane carries the park tags (--var lab/cockpit)" || no "panes missing park tags"
printf '%s\n' "$s" | grep -qx 'cd /home/jangmanj/JangLabs/claude' && ok "cd to the lab repo before the panes" || no "missing/wrong cd"
printf '%s\n' "$s" | grep -q 'Claude 1' && printf '%s\n' "$s" | grep -q 'Claude 3' && ok "panes numbered 1..N in the title" || no "pane numbering wrong"

echo "== 2. N=1 is the degenerate single-pane case =="
s1="$(_emit_fleet_session jangsjedi 1)"
[ "$(printf '%s\n' "$s1" | grep -c '^launch ')" -eq 1 ] && ok "N=1 -> exactly one launch" || no "N=1 launch count wrong"
[ "$(printf '%s\n' "$s1" | grep -c '^focus$')" -eq 1 ] && ok "N=1 still focuses its single pane" || no "N=1 focus missing"

echo "== 3. honors SWITCHTAIL_LAYOUT for the transient session =="
[ "$(SWITCHTAIL_LAYOUT=grid _emit_fleet_session claude 2 | grep '^layout ')" = 'layout grid' ] \
  && ok "layout follows SWITCHTAIL_LAYOUT" || no "layout not honored"
[ "$(_emit_fleet_session claude 2 | grep '^layout ')" = 'layout tall' ] \
  && ok "layout defaults to tall" || no "default layout wrong"

# From here, stub the launcher + kdotool so nothing real spawns.
echo "== 4. cmd_fleet launches via the stdin-safe bash -c construction =="
_launch_detached(){ printf '%s\n' "$*" >>/tmp/fleet-launch.log; }
kdotool(){ :; }   # no windows up by default
: > /tmp/fleet-launch.log
( cmd_fleet claude 2 ) >/dev/null 2>&1
grep -q 'bash -c' /tmp/fleet-launch.log && ok "detached command is a bash -c (rebuilds the pipe in-tree)" || no "not launched via bash -c"
grep -q 'kitty --session -' /tmp/fleet-launch.log && ok "kitty reads the session from STDIN (no temp file)" || no "kitty --session - missing"
grep -q 'Claude 2' /tmp/fleet-launch.log && ok "the session text reaches the launcher as an argv" || no "session not passed as argv"

echo "== 5. default count is 1 =="
: > /tmp/fleet-launch.log; ( cmd_fleet claude ) >/dev/null 2>&1
grep -q 'Claude 1' /tmp/fleet-launch.log && ! grep -q 'Claude 2' /tmp/fleet-launch.log \
  && ok "no count -> a single pane" || no "default count not 1"

echo "== 6. count clamped to SWITCHTAIL_FLEET_MAX (default 12) =="
: > /tmp/fleet-launch.log
warn="$( ( cmd_fleet claude 999 ) 2>&1 >/dev/null )"
echo "$warn" | grep -qi 'clamp' && ok "warns when clamping" || no "no clamp warning"
grep -q 'Claude 12' /tmp/fleet-launch.log && ! grep -q 'Claude 13' /tmp/fleet-launch.log \
  && ok "clamped to the default max of 12" || no "clamp to 12 failed"

echo "== 7. SWITCHTAIL_FLEET_MAX tunable honored =="
: > /tmp/fleet-launch.log
( SWITCHTAIL_FLEET_MAX=3 cmd_fleet claude 10 ) >/dev/null 2>&1
grep -q 'Claude 3' /tmp/fleet-launch.log && ! grep -q 'Claude 4' /tmp/fleet-launch.log \
  && ok "FLEET_MAX=3 clamps a request for 10 down to 3" || no "env max not honored"
# a garbage FLEET_MAX falls back to 12, never disables the clamp
: > /tmp/fleet-launch.log
( SWITCHTAIL_FLEET_MAX=banana cmd_fleet claude 999 ) >/dev/null 2>&1
grep -q 'Claude 12' /tmp/fleet-launch.log && ! grep -q 'Claude 13' /tmp/fleet-launch.log \
  && ok "non-numeric FLEET_MAX falls back to 12 (clamp never disabled)" || no "garbage FLEET_MAX broke the clamp"

echo "== 8. count validation: rejects non-integer / zero / negative =="
( cmd_fleet claude abc ) >/dev/null 2>&1; [ $? -eq 2 ] && ok "non-integer count -> exit 2" || no "non-integer not rejected"
( cmd_fleet claude 0 )   >/dev/null 2>&1; [ $? -eq 2 ] && ok "zero count -> exit 2" || no "zero not rejected"
( cmd_fleet claude -1 )  >/dev/null 2>&1; [ $? -eq 2 ] && ok "negative count -> exit 2 (not parsed as a flag)" || no "negative not rejected"

echo "== 9. lab-name validation + missing-dir guard (no launch on either) =="
: > /tmp/fleet-launch.log
( cmd_fleet '../../evil' 2 ) >/dev/null 2>&1; [ $? -eq 2 ] && ok "traversal lab name -> exit 2" || no "traversal not rejected"
[ ! -s /tmp/fleet-launch.log ] && ok "no launch attempted for the bad name" || no "launched despite bad name"
# missing dir: a syntactically valid name with no repo dir
: > /tmp/fleet-launch.log
( cmd_fleet definitelynotalab 1 ) >/dev/null 2>&1; [ $? -eq 1 ] && ok "missing lab dir -> exit 1" || no "missing dir not guarded"
[ ! -s /tmp/fleet-launch.log ] && ok "no window of broken panes opened" || no "launched into a missing dir"

echo "== 10. already-up warning (second fleet shares the class) =="
# stub kdotool so a 'claude' window appears to exist
kdotool(){ case "$*" in "search --class ^switchtail-claude$") echo '{existing}';; *) :;; esac; }
warn="$( ( cmd_fleet claude 1 ) 2>&1 >/dev/null )"
echo "$warn" | grep -qi 'already up' && ok "warns that a second same-class window is opening" || no "no already-up warning"

echo; echo "RESULT: $pass passed, $fail failed"
rm -f /tmp/fleet-launch.log
[ "$fail" -eq 0 ]
