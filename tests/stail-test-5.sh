#!/usr/bin/env bash
# Regression tests for `stail patch` (cart of selections -> ONE tabbed board, panes packed
# 5-per-tab) against the REAL stail functions. Covers _slug_dir, _patch_resolve (parse, per-row
# count clamp to TAB_SIZE, slug collision suffixing, lab vs custom-dir, bad-spec rejection),
# _emit_patch_session (tab packing, per-tab cd/layout/focus, focus_tab 0), the window-class
# single-vs-multi rule, and an end-to-end shell round-trip of a path with a space + apostrophe.
set -uo pipefail
STAIL_BIN="${STAIL_BIN:-$HOME/.local/bin/stail}"
pass=0; fail=0
ok(){ printf '  ✓ %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  ✗ %s\n' "$1"; fail=$((fail+1)); }

cp "$STAIL_BIN" /tmp/stail-fns.sh || { echo "FATAL: cannot copy stail under test: $STAIL_BIN" >&2; exit 1; }
sed -i '/^# ---------- dispatch ----------/,$d' /tmp/stail-fns.sh
# shellcheck disable=SC1091
source /tmp/stail-fns.sh
WORKSPACE="$HOME/JangLabs"

echo "== 1. _slug_dir derives a class-safe slug from the basename =="
[ "$(_slug_dir /srv/work/my-app)" = "my-app" ] && ok "plain basename" || no "my-app: $(_slug_dir /srv/work/my-app)"
[ "$(_slug_dir "/a/b/Foo Bar!")" = "Foo-Bar" ] && ok "space + punct collapse to dash, trimmed" || no "Foo Bar!: $(_slug_dir "/a/b/Foo Bar!")"
[ "$(_slug_dir /)" = "dir" ] && ok "empty/root basename -> fallback 'dir'" || no "/: $(_slug_dir /)"
[[ "$(_slug_dir "/x/oddly@#name")" =~ ^[A-Za-z0-9._-]+$ ]] && ok "slug always matches the class charset" || no "slug escaped wrong"

# helper: resolve specs in a subshell with fresh arrays, echo "slug1 slug2 …"
slugs_of(){ ( declare -a P_DIR P_SLUG P_KIND P_TITLE; declare -A SLUGSEEN; _patch_resolve "$@" >/dev/null 2>&1 && printf '%s ' "${P_SLUG[@]}" ); }
panes_of(){ ( declare -a P_DIR P_SLUG P_KIND P_TITLE; declare -A SLUGSEEN; _patch_resolve "$@" >/dev/null 2>&1 && printf '%s' "${#P_DIR[@]}" ); }
kinds_of(){ ( declare -a P_DIR P_SLUG P_KIND P_TITLE; declare -A SLUGSEEN; _patch_resolve "$@" >/dev/null 2>&1 && printf '%s ' "${P_KIND[@]}" ); }
# emit_of CLASS SPEC...  -> resolves all the SPEC args, emits the session with window class CLASS
emit_of(){ local cls="$1"; shift; ( declare -a P_DIR P_SLUG P_KIND P_TITLE; declare -A SLUGSEEN; _patch_resolve "$@" >/dev/null 2>&1; _emit_patch_session "$cls" ); }

echo "== 2. _patch_resolve: per-row count + flat pane expansion =="
[ "$(panes_of lab=synapse*3)" = "3" ] && ok "lab=synapse*3 -> 3 panes" || no "synapse*3 panes: $(panes_of lab=synapse*3)"
[ "$(panes_of lab=synapse)" = "1" ] && ok "no count -> 1 pane" || no "default count: $(panes_of lab=synapse)"
[ "$(panes_of lab=synapse*3 lab=agent*4)" = "7" ] && ok "synapse*3 + agent*4 -> 7 panes" || no "7-pane total wrong"

echo "== 3. count clamps to SWITCHTAIL_TAB_SIZE (default 5) =="
[ "$(panes_of lab=synapse*9)" = "5" ] && ok "*9 clamps to 5" || no "clamp: $(panes_of lab=synapse*9)"
[ "$(SWITCHTAIL_TAB_SIZE=3 panes_of lab=synapse*9)" = "3" ] && ok "SWITCHTAIL_TAB_SIZE=3 clamps to 3" || no "env tab size ignored"

echo "== 4. slug collision suffixing within a cart =="
mkdir -p /tmp/stail-t5/synapse
sl="$(slugs_of lab=synapse dir=/tmp/stail-t5/synapse)"
echo "  slugs: [$sl]"
[ "$sl" = "synapse synapse-2 " ] && ok "dir basename colliding with a lab -> synapse-2" || no "collision slug wrong: [$sl]"
rm -rf /tmp/stail-t5

echo "== 5. _emit_patch_session: tab packing at 5, per-tab cd/layout/focus, focus_tab 0 =="
s="$(emit_of switchtail-multi lab=synapse*3 lab=agent*4)"
[ "$(printf '%s\n' "$s" | grep -c '^launch ')" -eq 7 ] && ok "7 launch lines" || no "launch count wrong"
[ "$(printf '%s\n' "$s" | grep -c '^new_tab ')" -eq 1 ] && ok "1 new_tab (2nd tab; first is implicit)" || no "new_tab count wrong"
[ "$(printf '%s\n' "$s" | grep -c '^focus$')" -eq 2 ] && ok "2 tab masters (one focus per tab)" || no "focus count wrong"
[ "$(printf '%s\n' "$s" | grep -c '^cd ')" -eq 2 ] && ok "each tab gets its own cd" || no "cd count wrong"
[ "$(printf '%s\n' "$s" | grep -c '^layout ')" -eq 2 ] && ok "each tab gets its own layout" || no "layout count wrong"
printf '%s\n' "$s" | tail -1 | grep -qx 'focus_tab 0' && ok "ends with focus_tab 0" || no "missing focus_tab 0"
printf '%s\n' "$s" | grep -q '^os_window_class switchtail-multi$' && ok "honors the passed window class" || no "class line wrong"
# panes carry the hold tags + an explicit dir arg
printf '%s\n' "$s" | grep -q -- '--var lab=synapse --var board=multi --var kind=claude --var holdable=1 --var stylable=1 stail line synapse ' && ok "claude panes carry board + kind + table-derived holdable/stylable flags" || no "pane launch shape wrong"
# shell/cmd panes must NOT carry the agent flags (the kind table says they are not holdable/stylable)
printf '%s\n' "$s" | grep -- '--var kind=claude' | grep -qv 'holdable=1' && no "a claude pane missing flags" || ok "every claude pane is flagged holdable"

echo "== 6. window-class rule (cmd_patch): single distinct slug vs mixed -> multi =="
# stub the launcher and capture the os_window_class the build emits
_launch_detached(){ printf '%s\n' "$*" >> /tmp/t5-launch.log; }
: > /tmp/t5-launch.log; ( cmd_patch lab=synapse*3 ) >/dev/null 2>&1
grep -q 'os_window_class switchtail-synapse' /tmp/t5-launch.log && ok "homogeneous cart -> class switchtail-<slug>" || no "single-slug class wrong"
: > /tmp/t5-launch.log; ( cmd_patch lab=synapse lab=agent ) >/dev/null 2>&1
grep -q 'os_window_class switchtail-multi' /tmp/t5-launch.log && ok "mixed cart -> class switchtail-multi" || no "multi class wrong"
# launched via the stdin-safe bash -c construction
grep -q 'bash -c' /tmp/t5-launch.log && grep -q 'kitty --session -' /tmp/t5-launch.log && ok "detached via bash -c | kitty --session -" || no "launch construction wrong"

echo "== 7. bad specs are rejected (no launch) =="
rc(){ ( cmd_patch "$@" ) >/dev/null 2>&1; echo $?; }
[ "$(rc)" = "2" ] && ok "no specs -> exit 2 (usage)" || no "empty patch didn't exit 2"
[ "$(rc synapse)" = "2" ] && ok "bare 'synapse' (no lab=/dir=) -> exit 2" || no "malformed spec not 2"
[ "$(rc foo=bar)" = "2" ] && ok "unknown kind -> exit 2" || no "unknown kind not 2"
[ "$(rc lab=../evil)" = "2" ] && ok "traversal lab name -> exit 2" || no "traversal not 2"
[ "$(rc lab=synapse*0)" = "2" ] && ok "count 0 -> exit 2" || no "zero count not 2"
[ "$(rc dir=/nonexistent/xyz)" = "1" ] && ok "missing custom dir -> exit 1" || no "missing dir not 1"

echo "== 8. end-to-end: a path with a space + apostrophe round-trips through a shell =="
# This is exactly what the widget emits: dir='…'\''…'*2 (single-quoted, apostrophe escaped).
realdir="/tmp/stail-t5q/o'brien app"; mkdir -p "$realdir"
# capture the detached launch via a fake systemd-run on PATH (so nothing real spawns)
mkdir -p /tmp/t5bin
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" >> /tmp/t5-rt.log\n' > /tmp/t5bin/systemd-run
chmod +x /tmp/t5bin/systemd-run
: > /tmp/t5-rt.log
# the literal command string the executable engine would pass to the shell:
cmdstr=$'patch lab=synapse*2 dir=\'/tmp/stail-t5q/o\'\\\'\'brien app\'*2'
PATH="/tmp/t5bin:$PATH" sh -c "$STAIL_BIN $cmdstr" >/dev/null 2>&1
got="$(grep -o "stail line [^ ]* \"/tmp/stail-t5q/o'brien app\"" /tmp/t5-rt.log | head -1)"
[ -n "$got" ] && ok "custom dir with space+apostrophe resolves correctly through the shell" || no "quoting round-trip failed"
[ "$(grep -o 'launch --title' /tmp/t5-rt.log | wc -l)" -eq 4 ] && ok "4 panes (synapse*2 + dir*2)" || no "round-trip pane count wrong"
rm -rf /tmp/stail-t5q /tmp/t5bin /tmp/t5-rt.log /tmp/t5-launch.log

echo "== 9. pane kinds: @<kind> suffix (claude|shell|cmd:<argv>) =="
# default kind is claude when no @suffix is present
[ "$(kinds_of lab=synapse*2)" = "claude claude " ] && ok "no @kind -> claude (default)" || no "default kind: [$(kinds_of lab=synapse*2)]"
# @shell / @cmd:… peel off and apply per-pane (count still expands after the kind)
[ "$(kinds_of lab=synapse@shell)" = "shell " ] && ok "lab=synapse@shell -> shell" || no "shell kind: [$(kinds_of lab=synapse@shell)]"
[ "$(kinds_of lab=synapse@shell*2)" = "shell shell " ] && ok "@shell*2 -> shell shell (kind before count)" || no "shell*2: [$(kinds_of lab=synapse@shell*2)]"
mkdir -p /tmp/stail-t5cmd
[ "$(kinds_of 'dir=/tmp/stail-t5cmd@cmd:lazygit')" = "cmd:lazygit " ] && ok "dir=…@cmd:lazygit -> cmd:lazygit" || no "cmd kind: [$(kinds_of 'dir=/tmp/stail-t5cmd@cmd:lazygit')]"
# a path that CONTAINS '@' but whose tail is not a real kind keeps the '@' (no kind eaten)
mkdir -p "/tmp/stail-t5cmd/u@host"
[ "$(kinds_of 'dir=/tmp/stail-t5cmd/u@host')" = "claude " ] && ok "dir with @host (not a kind) -> claude, '@' kept" || no "false-@ ate path: [$(kinds_of 'dir=/tmp/stail-t5cmd/u@host')]"
sl9="$(slugs_of 'dir=/tmp/stail-t5cmd/u@host')"; [ "$sl9" = "u-host " ] && ok "  and slug still derives from the full basename (u-host)" || no "false-@ slug wrong: [$sl9]"
# emit wires the kind to BOTH --var kind (cmd:* collapsed to 'cmd') AND the line argv (full)
s9="$(emit_of switchtail-multi lab=synapse@shell 'dir=/tmp/stail-t5cmd@cmd:git status')"
printf '%s\n' "$s9" | grep -q -- '--var kind=shell stail line synapse .* "shell" multi$' && ok "shell pane: --var kind=shell + line arg \"shell\" + board argv" || no "shell emit wrong"
printf '%s\n' "$s9" | grep -q -- '--var kind=cmd stail line ' && ok "cmd pane: --var kind=cmd (collapsed, space-free)" || no "cmd var not collapsed"
printf '%s\n' "$s9" | grep -q -- '"cmd:git status" multi$' && ok "cmd pane: full 'cmd:git status' passed as the line argv (board argv after)" || no "cmd full argv not passed"
rm -rf /tmp/stail-t5cmd

echo; echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
