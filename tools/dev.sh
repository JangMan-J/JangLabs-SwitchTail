#!/usr/bin/env bash
# SwitchTail dev loop. Memory discipline: this box runs many concurrent
# sessions — builds are always capped (CARGO_BUILD_JOBS) and debuginfo is off
# (workspace profile). Usage: tools/dev.sh {test|build|reload|install}
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-4}"
WASM_DEBUG="$REPO/target/wasm32-wasip1/debug/switchtail.wasm"
WASM_RELEASE="$REPO/target/wasm32-wasip1/release/switchtail.wasm"
PLUGIN_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/zellij/plugins"

case "${1:-build}" in
    test)
        cargo test --workspace --exclude switchtail
        ;;
    build)
        cargo build -p switchtail --target wasm32-wasip1
        echo "built: $WASM_DEBUG"
        ;;
    reload)
        cargo build -p switchtail --target wasm32-wasip1
        # Reload into the current/most-recent zellij session.
        zellij action start-or-reload-plugin "file:$WASM_DEBUG"
        echo "reloaded: $WASM_DEBUG"
        ;;
    install)
        cargo build -p switchtail --target wasm32-wasip1 --release
        mkdir -p "$PLUGIN_DIR"
        cp "$WASM_RELEASE" "$PLUGIN_DIR/switchtail.wasm"
        echo "installed: $PLUGIN_DIR/switchtail.wasm"
        echo "bind it (config.kdl):"
        echo '  bind "Alt s" { LaunchOrFocusPlugin "file:~/.local/share/zellij/plugins/switchtail.wasm" { floating true; move_to_focused_tab true; } }'
        ;;
    *)
        echo "usage: tools/dev.sh {test|build|reload|install}" >&2
        exit 2
        ;;
esac
