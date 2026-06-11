#!/usr/bin/env bash
# Regression suite for the stail cockpit (CLI + kittens). Re-run after editing
# ~/.local/bin/stail or ~/.config/kitty/cockpit_*.py. All suites must report 0 failures.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
rc=0
for t in stail-test-1.sh stail-test-2.sh stail-test-3.sh stail-test-4.sh stail-test-5.sh; do
  echo "######## $t ########"; bash "$here/$t" || rc=1; echo
done
echo "######## stail-kitten-test.py ########"; python3 "$here/stail-kitten-test.py" || rc=1
echo; echo "######## cockpit-monitor-test.py ########"; python3 "$here/cockpit-monitor-test.py" || rc=1
echo; [ "$rc" -eq 0 ] && echo "ALL SUITES PASSED" || echo "SOME SUITES FAILED"
exit "$rc"
