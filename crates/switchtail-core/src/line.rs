use serde::{Deserialize, Serialize};

/// A line is one terminal pane on the exchange. Plugin panes are never lines.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct LineId(pub u32);

/// What an agent on a line last reported about itself (via the pipe protocol).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AgentState {
    #[default]
    Unknown,
    Working,
    Blocked,
    Done,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Line {
    pub id: LineId,
    pub title: String,
    /// The command running on the line, if the host knows it.
    pub command: Option<String>,
    /// Tab position of the board this line lives on.
    pub board: usize,
    pub focused: bool,
    pub exited: bool,
    pub exit_status: Option<i32>,
    pub floating: bool,
    pub suppressed: bool,
    /// Operator/agent-supplied label (e.g. a lab name). Pipe `register`.
    pub label: Option<String>,
    /// Agent kind (e.g. "claude"). Pipe `register`.
    pub kind: Option<String>,
    pub agent_state: AgentState,
    /// True while this line has unanswered ringing calls.
    pub ringing: bool,
}

impl Line {
    /// Display name: label wins over title, title over command, then the id.
    pub fn display_name(&self) -> String {
        if let Some(label) = &self.label {
            label.clone()
        } else if !self.title.is_empty() {
            self.title.clone()
        } else if let Some(cmd) = &self.command {
            cmd.clone()
        } else {
            format!("line {}", self.id.0)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn line(id: u32) -> Line {
        Line {
            id: LineId(id),
            title: String::new(),
            command: None,
            board: 0,
            focused: false,
            exited: false,
            exit_status: None,
            floating: false,
            suppressed: false,
            label: None,
            kind: None,
            agent_state: AgentState::Unknown,
            ringing: false,
        }
    }

    #[test]
    fn display_name_prefers_label_then_title_then_command() {
        let mut l = line(7);
        assert_eq!(l.display_name(), "line 7");
        l.command = Some("claude".into());
        assert_eq!(l.display_name(), "claude");
        l.title = "synapse work".into();
        assert_eq!(l.display_name(), "synapse work");
        l.label = Some("synapse".into());
        assert_eq!(l.display_name(), "synapse");
    }
}
