#!/usr/bin/env bash
# Live, in-kitty end-to-end test of the park kitten (#3 / R1) via kitty remote control.
set -uo pipefail
SOCK=unix:@stailparktest
ST="${XDG_STATE_HOME:-$HOME/.local/state}/switchtail"
Q(){ kitty @ --to "$SOCK" "$@" 2>/dev/null; }
pass=0; fail=0
ok(){ printf '  ✓ %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  ✗ %s\n' "$1"; fail=$((fail+1)); }

rm -f "$ST/zztest.resume"
cat > /tmp/park-test.session <<'EOF'
os_window_class switchtail-zztest
launch --title CLAUDE --var lab=zztest --var cockpit=claude sh
launch --title SHELL sh
EOF
setsid kitty -o allow_remote_control=yes --listen-on "$SOCK" -o confirm_os_window_close=0 \
  --session /tmp/park-test.session >/dev/null 2>&1 &
sleep 3

echo "== panes at start =="
Q ls | python3 /tmp/park_q.py list
claude_id="$(Q ls | python3 /tmp/park_q.py idof CLAUDE)"
shell_id="$(Q ls | python3 /tmp/park_q.py idof SHELL)"
echo "  claude_id=$claude_id shell_id=$shell_id"
[ -n "$claude_id" ] && [ -n "$shell_id" ] && ok "two tagged panes present" || no "panes missing"

echo "== Test A: park the UNTAGGED SHELL pane -> must NOT close, NO marker =="
Q focus-window --match "id:$shell_id" >/dev/null
Q action kitten cockpit_park.py >/dev/null
sleep 1
still="$(Q ls | python3 /tmp/park_q.py hasid "$shell_id")"
[ "$still" = YES ] && ok "untagged SHELL pane survived (not closed)" || no "untagged pane was closed!"
[ ! -f "$ST/zztest.resume" ] && ok "no resume marker written for untagged pane" || no "marker wrongly written"

echo "== Test B: park the TAGGED CLAUDE pane -> marker armed THEN pane closed =="
Q focus-window --match "id:$claude_id" >/dev/null
Q action kitten cockpit_park.py >/dev/null
sleep 1
gone="$(Q ls | python3 /tmp/park_q.py hasid "$claude_id")"
[ "$gone" = NO ] && ok "tagged CLAUDE pane was closed" || no "tagged pane NOT closed"
[ -f "$ST/zztest.resume" ] && ok "resume marker armed for lab 'zztest'" || no "marker NOT written"

echo "== cleanup =="
rm -f "$ST/zztest.resume"
Q quit >/dev/null 2>&1 || true
kdotool search --class '^switchtail-zztest$' windowclose >/dev/null 2>&1 || true
sleep 0.5
echo; echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
