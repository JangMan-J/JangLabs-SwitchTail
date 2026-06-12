#!/usr/bin/env bash
# Regression suite for the stail board (CLI + kittens). Re-run after editing
# the stail under test or ~/.config/kitty/{hold,swap,tail}.py. All suites must report
# 0 failures. Set STAIL_BIN=<path> to test a checkout instead of the deployed
# ~/.local/bin/stail (the default when STAIL_BIN is unset).
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
echo "stail under test: ${STAIL_BIN:-$HOME/.local/bin/stail}"
rc=0
for t in stail-test-1.sh stail-test-2.sh stail-test-3.sh stail-test-4.sh stail-test-5.sh stail-test-6.sh; do
  echo "######## $t ########"; bash "$here/$t" || rc=1; echo
done
echo "######## stail-kitten-test.py ########"; python3 "$here/stail-kitten-test.py" || rc=1
echo; echo "######## tail-test.py ########"; python3 "$here/tail-test.py" || rc=1
echo; echo "######## state-test.py ########"; python3 "$here/state-test.py" || rc=1
echo; [ "$rc" -eq 0 ] && echo "ALL SUITES PASSED" || echo "SOME SUITES FAILED"
exit "$rc"
