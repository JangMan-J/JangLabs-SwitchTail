//! Host effects the core wants performed. The plugin adapter dispatches each
//! intent as exactly one zellij shim call. This seam is the expandability
//! contract: new capability = new intent + one dispatcher arm.
//!
//! Deliberately absent, forever-by-default: any close/kill intent.

use crate::line::LineId;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HostIntent {
    /// Focus a line (any board; unsuppress/float if hidden).
    FocusLine(LineId),
    /// Swap `line` into the seat position (replace seat pane with line).
    SwapIntoSeat { seat: LineId, line: LineId },
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
    /// Answer a CLI pipe (cli_pipe_output) with a JSON body.
    PipeReply { pipe: String, body: String },
    /// Hide the plugin pane (operator dismissed the switchboard).
    HideSelf,
}
