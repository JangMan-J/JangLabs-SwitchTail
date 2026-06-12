//! SHELL-04: the adapter must be structurally unable to destroy a pane —
//! no close/kill shim call sites, ever. This guard fails the suite if one
//! appears. (It lives in the core crate so it runs on the host target
//! without linking the wasm bin.)

use std::path::Path;

const FORBIDDEN: &[&str] = &[
    "close_terminal_pane",
    "close_plugin_pane",
    "close_pane_with_id",
    "close_multiple_panes",
    "close_focus",
    "close_focused_tab",
    "close_tab_with_index",
    "close_tab_with_id",
    "close_self",
    "send_sigint_to_pane_id",
    "send_sigkill_to_pane_id",
    "kill_sessions",
    "quit_zellij",
];

#[test]
fn adapter_has_no_pane_destroying_call_sites() {
    let adapter = Path::new(env!("CARGO_MANIFEST_DIR")).join("../switchtail-plugin/src/main.rs");
    let src = std::fs::read_to_string(&adapter)
        .unwrap_or_else(|e| panic!("cannot read adapter source {}: {e}", adapter.display()));
    let mut hits = Vec::new();
    for needle in FORBIDDEN {
        for (i, line) in src.lines().enumerate() {
            // Allow mentions in comments; flag real call sites.
            let code = line.split("//").next().unwrap_or("");
            if code.contains(needle) {
                hits.push(format!("{}:{}: {}", adapter.display(), i + 1, line.trim()));
            }
        }
    }
    assert!(
        hits.is_empty(),
        "forbidden pane-destroying call sites in the adapter:\n{}",
        hits.join("\n")
    );
}
