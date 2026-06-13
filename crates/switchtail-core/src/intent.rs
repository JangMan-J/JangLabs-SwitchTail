//! Host effects the core wants performed. Each intent is exactly one host
//! EFFECT; the adapter dispatches it as one shim call — except `SwapPanes`,
//! the one sanctioned composed transaction (3 calls: pin placeholder, replace
//! seat, release placeholder). The placeholder PaneId is host-allocated
//! mid-sequence and never crosses the core/adapter seam, so per-call intents
//! are impossible without corrupting the seam. The business decision ("exchange
//! these two lines") stays in core; the 3-call mechanics are host-API plumbing.
//!
//! Deliberately absent, forever-by-default: any close/kill intent. The
//! placeholder close in SwapPanes is a parameter of `replace_pane_with_
//! existing_pane(suppress=false)` scoped to plugin-owned scaffolding, per
//! owner decision (04-06 Task 1).
//!
//! `SpawnBoard` is a normal one-intent-one-shim effect (NOT a composed
//! transaction, NOT a close/kill). The adapter maps it to
//! `open_command_pane_in_new_tab`, which atomically creates a new board
//! (tab) AND the board's first line (command pane). No close/kill semantics —
//! it is a pure creation intent.

use crate::line::LineId;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HostIntent {
    /// Focus a line (any board; unsuppress/float if hidden).
    FocusLine(LineId),
    /// True positional exchange: seat pane and line trade slots, layout
    /// otherwise unchanged, nothing left suppressed. Dispatched by the adapter
    /// as the composed 3-call placeholder transaction because the host has no
    /// single swap primitive and the placeholder id is host-allocated.
    SwapPanes { seat: LineId, line: LineId },
    /// Type text into a line.
    Say { line: LineId, text: String },
    /// Retitle a line (native rename — no typing into the pane).
    RenameLine { line: LineId, name: String },
    /// Tint a line's default colors (CB-safe palette only). `None` = reset.
    TintLine {
        line: LineId,
        fg: Option<String>,
        bg: Option<String>,
    },
    /// Set the host-side highlight set (ringing lines).
    HighlightLines { on: Vec<LineId>, off: Vec<LineId> },
    /// Open a new line. `command` empty = default shell terminal.
    OpenLine {
        command: Vec<String>,
        cwd: Option<String>,
    },
    /// Spawn a new board (tab) with its first line running `command`.
    /// The adapter maps this to `open_command_pane_in_new_tab`. One intent =
    /// one shim call. For a board of N lines, core emits this followed by
    /// (N-1) `OpenLine` intents; the adapter's FIFO dispatch order ensures
    /// all lines land on the newly-focused board before any TabUpdate arrives.
    SpawnBoard { command: Vec<String> },
    /// Answer a CLI pipe (cli_pipe_output) with a JSON body.
    PipeReply { pipe: String, body: String },
    /// Hide the plugin pane (operator dismissed the switchboard).
    HideSelf,
}
