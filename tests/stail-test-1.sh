#!/usr/bin/env bash
# Non-window verification of stail's pure logic, exercising the REAL functions from
# ~/.local/bin/stail (dispatch tail stripped so sourcing doesn't exec a subcommand).
set -uo pipefail
pass=0; fail=0
ok(){ printf '  ✓ %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  ✗ %s\n' "$1"; fail=$((fail+1)); }

cp ~/.local/bin/stail /tmp/stail-fns.sh
sed -i '/^# ---------- dispatch ----------/,$d' /tmp/stail-fns.sh
# shellcheck disable=SC1091
source /tmp/stail-fns.sh

echo "== 1. real generate (5 labs, no warnings expected) =="
stail() { command ~/.local/bin/stail "$@"; }
out="$(command ~/.local/bin/stail generate 2>&1)"; echo "  $out"
echo "$out" | grep -q 'agent claude jangsjedi jangsjyro proton' && ok "generate lists the 5 labs" || no "generate lab set unexpected"

echo "== 2. name validation (#6/#7): isolated SWITCHTAIL_DIR workspace =="
ws=/tmp/stail-test-ws; rm -rf "$ws"; mkdir -p "$ws"
mkdir -p "$ws/good" && : > "$ws/good/.git"
mkdir -p "$ws/dot.ok" && : > "$ws/dot.ok/.git"
mkdir -p "$ws/bad name" && : > "$ws/bad name/.git"
mkdir -p "$ws/build" && : > "$ws/build/.git"
mkdir -p "$ws/exchange" && : > "$ws/exchange/.git"
mkdir -p "$ws/notrepo"                       # no .git -> not a lab
WORKSPACE="$ws"
disc="$(_discover_labs 2>/tmp/stail-disc-warn)"; warn="$(cat /tmp/stail-disc-warn)"
echo "  discovered: [$(echo "$disc" | tr '\n' ' ')]"
echo "  warnings:   $warn"
[ "$disc" = "$(printf 'dot.ok\ngood')" ] && ok "keeps good + dot.ok, drops 'bad name'/build/exchange/notrepo" || no "discovery set wrong: [$disc]"
echo "$warn" | grep -q "skipping lab 'bad name'" && ok "warns on the space-containing name" || no "no warning for 'bad name'"

echo "== 3. _class_re (#5): anchored + metachar-escaped =="
[ "$(_class_re good)"      = '^switchtail-good$' ]     && ok "plain name -> ^switchtail-good\$" || no "plain: $(_class_re good)"
[ "$(_class_re dot.ok)"    = '^switchtail-dot\.ok$' ]  && ok "dot escaped -> ^switchtail-dot\\.ok\$" || no "dot: $(_class_re dot.ok)"
[ "$(_class_re 'a+b')"     = '^switchtail-a\+b$' ]     && ok "plus escaped" || no "plus: $(_class_re 'a+b')"
[ "$(_class_re jangsjyro)" = '^switchtail-jangsjyro$' ] && ok "real lab name clean" || no "jangsjyro: $(_class_re jangsjyro)"

echo "== 3b. _display_name: PascalCase, explicit inner-cap overrides, Titlecase fallback =="
[ "$(_display_name agent)"     = "Agent" ]     && ok "agent -> Agent" || no "agent: $(_display_name agent)"
[ "$(_display_name claude)"    = "Claude" ]    && ok "claude -> Claude" || no "claude: $(_display_name claude)"
[ "$(_display_name proton)"    = "Proton" ]    && ok "proton -> Proton" || no "proton: $(_display_name proton)"
[ "$(_display_name jangsjedi)" = "JangsJedi" ] && ok "jangsjedi -> JangsJedi (explicit inner cap)" || no "jangsjedi: $(_display_name jangsjedi)"
[ "$(_display_name jangsjyro)" = "JangsJyro" ] && ok "jangsjyro -> JangsJyro (explicit inner cap)" || no "jangsjyro: $(_display_name jangsjyro)"
[ "$(_display_name exchange)"  = "Exchange" ]  && ok "exchange -> Exchange" || no "exchange: $(_display_name exchange)"
[ "$(_display_name my-app)"    = "My-app" ]    && ok "unknown -> Titlecase fallback" || no "fallback: $(_display_name my-app)"

echo "== 4. aggregate-union parse (#2): pull labs from real switchtail-exchange session =="
af="$HOME/.config/kitty/sessions/labs/switchtail-exchange.kitty-session"
if [ -f "$af" ]; then
  labs="$(grep -oE -- '--var lab=[A-Za-z0-9._-]+' "$af" | cut -d= -f2 | tr '\n' ' ')"
  echo "  aggregate panes: $labs"
  echo "$labs" | grep -q 'agent' && echo "$labs" | grep -q 'proton' && ok "union parses each pane's lab" || no "union parse missing labs"
else
  no "no switchtail-exchange session file"
fi

echo; echo "RESULT: $pass passed, $fail failed"
rm -rf "$ws" /tmp/stail-disc-warn
[ "$fail" -eq 0 ]
