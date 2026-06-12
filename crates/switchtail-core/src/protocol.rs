//! The wire protocol: JSON ops arriving on the `switchtail` pipe, and the
//! JSON answers the switchboard gives back. External scripts and agent hooks
//! bind to THIS, not to internals.

use crate::line::{AgentState, Line, LineId};
use crate::log::Call;
use serde::Deserialize;

pub const PIPE_NAME: &str = "switchtail";

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(tag = "op", rename_all = "lowercase")]
pub enum PipeOp {
    /// Type text into a line.
    Say { line: LineRef, text: String },
    /// Focus a line.
    Focus { line: LineRef },
    /// Flag a line as ringing.
    Ring {
        line: LineRef,
        #[serde(default)]
        note: Option<String>,
    },
    /// Agent status report.
    Status {
        line: LineRef,
        state: AgentState,
        #[serde(default)]
        note: Option<String>,
    },
    /// Attach label/kind metadata to a line.
    Register {
        line: LineRef,
        #[serde(default)]
        label: Option<String>,
        #[serde(default)]
        kind: Option<String>,
    },
    /// Ask for the directory as JSON (answered on the CLI pipe).
    List,
    /// Ask for the call log tail as JSON (answered on the CLI pipe).
    Log {
        #[serde(default)]
        n: Option<usize>,
    },
}

/// A line reference as it appears on the wire: `3`, `"3"`, or `"terminal_3"`.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(untagged)]
pub enum LineRef {
    Num(u32),
    Str(String),
}

impl LineRef {
    pub fn resolve(&self) -> Option<LineId> {
        match self {
            LineRef::Num(n) => Some(LineId(*n)),
            LineRef::Str(s) => {
                let s = s.strip_prefix("terminal_").unwrap_or(s);
                s.parse::<u32>().ok().map(LineId)
            }
        }
    }
}

pub fn parse(payload: &str) -> Result<PipeOp, String> {
    serde_json::from_str(payload).map_err(|e| e.to_string())
}

pub fn directory_json(lines: &[&Line], deck_key: impl Fn(LineId) -> Option<char>) -> String {
    let entries: Vec<serde_json::Value> = lines
        .iter()
        .map(|l| {
            serde_json::json!({
                "line": l.id.0,
                "name": l.display_name(),
                "title": l.title,
                "command": l.command,
                "board": l.board,
                "deck_key": deck_key(l.id).map(|c| c.to_string()),
                "focused": l.focused,
                "exited": l.exited,
                "exit_status": l.exit_status,
                "label": l.label,
                "kind": l.kind,
                "agent_state": l.agent_state,
                "ringing": l.ringing,
            })
        })
        .collect();
    serde_json::json!({ "lines": entries }).to_string()
}

pub fn log_json(calls: &[Call]) -> String {
    serde_json::json!({ "calls": calls }).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_say_with_all_line_ref_shapes() {
        for (raw, want) in [
            (r#"{"op":"say","line":3,"text":"hi"}"#, 3),
            (r#"{"op":"say","line":"7","text":"hi"}"#, 7),
            (r#"{"op":"say","line":"terminal_12","text":"hi"}"#, 12),
        ] {
            match parse(raw).unwrap() {
                PipeOp::Say { line, text } => {
                    assert_eq!(line.resolve(), Some(LineId(want)));
                    assert_eq!(text, "hi");
                }
                other => panic!("wrong op: {other:?}"),
            }
        }
    }

    #[test]
    fn parses_status_and_register_and_queries() {
        assert!(matches!(
            parse(r#"{"op":"status","line":1,"state":"blocked","note":"awaiting review"}"#),
            Ok(PipeOp::Status { .. })
        ));
        assert!(matches!(
            parse(r#"{"op":"register","line":1,"label":"synapse","kind":"claude"}"#),
            Ok(PipeOp::Register { .. })
        ));
        assert!(matches!(parse(r#"{"op":"list"}"#), Ok(PipeOp::List)));
        assert!(matches!(
            parse(r#"{"op":"log","n":50}"#),
            Ok(PipeOp::Log { n: Some(50) })
        ));
    }

    #[test]
    fn malformed_payloads_error_without_panicking() {
        assert!(parse("not json").is_err());
        assert!(parse(r#"{"op":"unknown"}"#).is_err());
        assert!(parse(r#"{"op":"say","line":"terminal_x","text":"hi"}"#)
            .map(|op| matches!(op, PipeOp::Say { ref line, .. } if line.resolve().is_none()))
            .unwrap_or(false));
    }
}
