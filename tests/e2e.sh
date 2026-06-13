#!/usr/bin/env bash
# SwitchTail headless E2E smoke. Boots a real zellij session inside a pty
# (via `script`), loads the plugin, drives it over the switchtail pipe, and
# asserts on the JSON answers.
#
# Headless trick: zellij plugins need interactive permission approval on
# first load, which would hang a headless run. We point the session at an
# ISOLATED cache (XDG_CACHE_HOME) pre-seeded with the grant — the cache key
# is the bare wasm path (RunPluginLocation::File Display, zellij-utils
# 0.44.3). The user's real ~/.cache/zellij is never touched.
#
# Best-effort: needs zellij + script(1); skips cleanly where impossible.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WASM="$REPO/target/wasm32-wasip1/debug/switchtail.wasm"
SESSION="st-e2e-$$"
SANDBOX="$(mktemp -d /tmp/switchtail-e2e.XXXXXX)"
PASS=0 FAIL=0

say()  { printf '%s\n' "$*"; }
ok()   { PASS=$((PASS + 1)); say "ok   - $*"; }
bad()  { FAIL=$((FAIL + 1)); say "FAIL - $*"; }
skip() { say "SKIP - $*"; exit 0; }

command -v zellij >/dev/null || skip "zellij not installed"
command -v script >/dev/null || skip "script(1) not available (util-linux)"
[ -f "$WASM" ] || CARGO_BUILD_JOBS=4 cargo build -p switchtail --target wasm32-wasip1 || skip "wasm build failed"

# Isolated cache, pre-seeded with the plugin's permission grant.
export XDG_CACHE_HOME="$SANDBOX/cache"
mkdir -p "$XDG_CACHE_HOME/zellij"
cat > "$XDG_CACHE_HOME/zellij/permissions.kdl" <<EOF
# v0.2: RunCommands added (enables open_command_pane for lines 2..N on a new board).
# The user's real ~/.cache/zellij/permissions.kdl will re-prompt once on first
# interactive launch after this change — the operator must approve the expanded grant.
"$WASM" {
    ReadApplicationState
    ChangeApplicationState
    OpenTerminalsOrPlugins
    WriteToStdin
    ReadCliPipes
    RunCommands
}
"file:$WASM" {
    ReadApplicationState
    ChangeApplicationState
    OpenTerminalsOrPlugins
    WriteToStdin
    ReadCliPipes
    RunCommands
}
EOF

cleanup() {
    timeout 10 zellij kill-session "$SESSION" >/dev/null 2>&1
    timeout 10 zellij delete-session "$SESSION" --force >/dev/null 2>&1
    [ -n "${SCRIPT_PID:-}" ] && kill "$SCRIPT_PID" >/dev/null 2>&1
    rm -rf "$SANDBOX"
    true
}
trap cleanup EXIT

# 1. Boot a real session inside a pty so zellij has a terminal.
script -qec "stty cols 140 rows 40; zellij --session $SESSION" /dev/null \
    >/dev/null 2>&1 &
SCRIPT_PID=$!

booted=""
for _ in $(seq 1 50); do
    if timeout 5 zellij list-sessions 2>/dev/null | grep -q "$SESSION"; then
        booted=1
        break
    fi
    sleep 0.2
done
[ -n "$booted" ] || skip "session failed to boot in a pty"
ok "session $SESSION booted headlessly"

ZA() { timeout 15 zellij --session "$SESSION" action "$@"; }
ZPIPE() { timeout 15 zellij --session "$SESSION" pipe --name switchtail -- "$1" 2>/dev/null; }

# 2. Load the plugin (floating pane; pipes don't need focus).
if ZA launch-plugin --floating "file:$WASM" >/dev/null 2>&1; then
    ok "plugin launched"
else
    bad "plugin launch errored"
fi
sleep 1

# 3. Open an extra terminal line and capture its pane id.
NEW_ID=$(ZA new-pane 2>/dev/null | grep -oE 'terminal_[0-9]+' | head -1)
if [ -n "$NEW_ID" ]; then ok "opened line $NEW_ID"; else bad "could not open a new line"; fi
sleep 1

# 4. Pipe: list — expect JSON naming our line.
LIST=$(ZPIPE '{"op":"list"}')
if printf '%s' "$LIST" | grep -q '"lines"'; then
    ok "list answered with a directory"
else
    bad "list gave no JSON directory (got: ${LIST:-<empty/timeout>})"
fi
if [ -n "${NEW_ID:-}" ] && printf '%s' "$LIST" | grep -q "\"line\":${NEW_ID#terminal_}\b"; then
    ok "directory contains $NEW_ID"
else
    bad "directory missing $NEW_ID (got: ${LIST:-<empty>})"
fi

# 5. Pipe: ring + log — expect the ring call on the log, triaged ringing.
ZPIPE "{\"op\":\"ring\",\"line\":\"$NEW_ID\",\"note\":\"e2e ring\"}" >/dev/null
LOG=$(ZPIPE '{"op":"log","n":10}')
if printf '%s' "$LOG" | grep -q 'e2e ring'; then
    ok "ring landed on the call log"
else
    bad "ring not found on the log (got: ${LOG:-<empty/timeout>})"
fi
if printf '%s' "$LOG" | grep -q '"triage":"ringing"'; then
    ok "ring is triaged as ringing"
else
    bad "ringing triage missing"
fi

# 6. Pipe: say — text must arrive in the target pane. (zellij 0.45:
# dump-screen prints to the client's stdout; -p targets a pane by id.)
ZPIPE "{\"op\":\"say\",\"line\":\"$NEW_ID\",\"text\":\"echo switchtail-e2e-marker\"}" >/dev/null
sleep 1
SCREEN=$(ZA dump-screen -p "$NEW_ID" 2>/dev/null || true)
if printf '%s' "$SCREEN" | grep -q 'switchtail-e2e-marker'; then
    ok "say patched text through to $NEW_ID"
else
    bad "say marker not visible in $NEW_ID (got: $(printf '%s' "$SCREEN" | tail -c 120))"
fi

say "---"
say "e2e: $PASS ok, $FAIL failed"
[ "$FAIL" -eq 0 ]
