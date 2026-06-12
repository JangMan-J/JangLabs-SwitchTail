//! The exchange: root model and the only mutation surface. Every operation
//! returns the [`HostIntent`]s the adapter must dispatch.

use crate::deck::Deck;
use crate::intent::HostIntent;
use crate::key::KeyInput;
use crate::line::{AgentState, Line, LineId};
use crate::log::{CallKind, CallLog, Triage};
use crate::protocol::{self, PipeOp};
use crate::snapshot::{BoardSnapshot, PaneSnapshot};
use std::collections::BTreeMap;

/// CB-safe attention tint (amber). Never pair meaning across red/green.
pub const RING_FG: &str = "#d79921";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum View {
    #[default]
    Directory,
    Log,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum SortMode {
    #[default]
    Deck,
    RingingFirst,
    Board,
}

impl SortMode {
    pub fn next(self) -> Self {
        match self {
            SortMode::Deck => SortMode::RingingFirst,
            SortMode::RingingFirst => SortMode::Board,
            SortMode::Board => SortMode::Deck,
        }
    }
    pub fn name(self) -> &'static str {
        match self {
            SortMode::Deck => "deck",
            SortMode::RingingFirst => "ringing-first",
            SortMode::Board => "board",
        }
    }
}

/// Operator prompt state (the `i` patch-through input).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Prompt {
    pub line: LineId,
    pub buffer: String,
}

#[derive(Debug, Clone, Default)]
pub struct Exchange {
    lines: BTreeMap<LineId, Line>,
    boards: Vec<BoardSnapshot>,
    pub deck: Deck,
    pub log: CallLog,
    pub seat: Option<LineId>,
    pub view: View,
    pub sort: SortMode,
    pub selected: usize,
    pub prompt: Option<Prompt>,
    /// Lines currently host-highlighted/tinted as ringing (for diffing).
    lit: Vec<LineId>,
    /// Command used by the `n` (new line) key; empty = default shell.
    pub line_command: Vec<String>,
}

impl Exchange {
    // ---------- ingest (host → model) ----------

    /// Ingest a fresh pane snapshot. Detects opens/closes/changes, maintains
    /// the deck and the log, and returns attention-surface intents.
    pub fn ingest_panes(&mut self, panes: Vec<PaneSnapshot>) -> Vec<HostIntent> {
        let mut seen: Vec<LineId> = Vec::new();
        for p in panes {
            if p.is_plugin || !p.is_selectable {
                continue;
            }
            let id = LineId(p.id);
            seen.push(id);
            match self.lines.get_mut(&id) {
                None => {
                    self.deck.assign(id);
                    self.log.place(
                        Some(id),
                        CallKind::LineOpened,
                        format!("line {} opened: {}", id.0, &p.title),
                    );
                    self.lines.insert(
                        id,
                        Line {
                            id,
                            title: p.title,
                            command: p.command,
                            board: p.board,
                            focused: p.is_focused,
                            exited: p.exited,
                            exit_status: p.exit_status,
                            floating: p.is_floating,
                            suppressed: p.is_suppressed,
                            label: None,
                            kind: None,
                            agent_state: AgentState::Unknown,
                            ringing: false,
                        },
                    );
                }
                Some(line) => {
                    if !line.exited && p.exited {
                        self.log.place(
                            Some(id),
                            CallKind::LineExited,
                            format!(
                                "line {} exited ({})",
                                id.0,
                                p.exit_status.map_or("?".into(), |s| s.to_string())
                            ),
                        );
                    }
                    if line.command != p.command && p.command.is_some() {
                        self.log.place(
                            Some(id),
                            CallKind::CommandChanged,
                            format!(
                                "line {} command: {}",
                                id.0,
                                p.command.clone().unwrap_or_default()
                            ),
                        );
                    }
                    line.title = p.title;
                    line.command = p.command;
                    line.board = p.board;
                    line.focused = p.is_focused;
                    line.exited = p.exited;
                    line.exit_status = p.exit_status;
                    line.floating = p.is_floating;
                    line.suppressed = p.is_suppressed;
                }
            }
        }
        // Lines gone from the snapshot are closed.
        let gone: Vec<LineId> = self
            .lines
            .keys()
            .copied()
            .filter(|id| !seen.contains(id))
            .collect();
        for id in gone {
            self.deck.release(id);
            self.lines.remove(&id);
            if self.seat == Some(id) {
                self.seat = None;
            }
            // A closed line can't ring anymore; settle its calls.
            self.log.settle_line(id, Triage::Parked);
            self.log
                .place(Some(id), CallKind::LineClosed, format!("line {} closed", id.0));
        }
        self.clamp_selection();
        self.refresh_ring_flags();
        self.attention_intents()
    }

    pub fn ingest_boards(&mut self, boards: Vec<BoardSnapshot>) {
        self.boards = boards;
    }

    // ---------- operator keys (plugin UI → model) ----------

    pub fn key(&mut self, key: KeyInput) -> Vec<HostIntent> {
        if self.prompt.is_some() {
            return self.prompt_key(key);
        }
        match key {
            KeyInput::Char(c) if self.deck.line_for(c).is_some() => {
                let line = self.deck.line_for(c).unwrap();
                vec![HostIntent::FocusLine(line)]
            }
            KeyInput::Tab => {
                self.view = match self.view {
                    View::Directory => View::Log,
                    View::Log => View::Directory,
                };
                self.selected = 0;
                vec![]
            }
            KeyInput::Up | KeyInput::Char('k') => {
                self.selected = self.selected.saturating_sub(1);
                vec![]
            }
            KeyInput::Down | KeyInput::Char('j') => {
                self.selected += 1;
                self.clamp_selection();
                vec![]
            }
            KeyInput::Enter => match self.view {
                View::Directory => self
                    .selected_line()
                    .map(|l| vec![HostIntent::FocusLine(l)])
                    .unwrap_or_default(),
                View::Log => {
                    // Answer the selected call and jump to its line.
                    let target = self.selected_call_seq().and_then(|seq| {
                        self.log.set_triage(seq, Triage::Answered);
                        self.log.get_mut(seq).and_then(|c| c.line)
                    });
                    self.refresh_ring_flags();
                    let mut intents = self.attention_intents();
                    if let Some(line) = target {
                        intents.push(HostIntent::FocusLine(line));
                    }
                    intents
                }
            },
            KeyInput::Char('m') => {
                if let Some(line) = self.selected_line() {
                    self.seat = Some(line);
                    self.log
                        .place(Some(line), CallKind::Info, format!("line {} is the seat", line.0));
                }
                vec![]
            }
            KeyInput::Char('s') => match (self.seat, self.selected_line()) {
                (Some(seat), Some(line)) if seat != line => {
                    vec![HostIntent::SwapIntoSeat { seat, line }]
                }
                (None, _) => {
                    self.log
                        .place(None, CallKind::Info, "no seat marked — press m on a line first");
                    vec![]
                }
                _ => vec![],
            },
            KeyInput::Char('i') => {
                if let Some(line) = self.selected_line() {
                    self.prompt = Some(Prompt {
                        line,
                        buffer: String::new(),
                    });
                }
                vec![]
            }
            KeyInput::Char('a') => self.settle_selected(Triage::Answered),
            KeyInput::Char('p') => self.settle_selected(Triage::Parked),
            KeyInput::Char('R') => {
                if let Some(line) = self.selected_line() {
                    self.log
                        .place(Some(line), CallKind::Ring, format!("operator ring on line {}", line.0));
                    self.refresh_ring_flags();
                    return self.attention_intents();
                }
                vec![]
            }
            KeyInput::Char('o') => {
                self.sort = self.sort.next();
                self.selected = 0;
                vec![]
            }
            KeyInput::Char('n') => vec![HostIntent::OpenLine {
                command: self.line_command.clone(),
                cwd: None,
            }],
            KeyInput::Esc => vec![HostIntent::HideSelf],
            _ => vec![],
        }
    }

    fn prompt_key(&mut self, key: KeyInput) -> Vec<HostIntent> {
        let prompt = self.prompt.as_mut().expect("prompt_key without prompt");
        match key {
            KeyInput::Char(c) => {
                prompt.buffer.push(c);
                vec![]
            }
            KeyInput::Backspace => {
                prompt.buffer.pop();
                vec![]
            }
            KeyInput::Esc => {
                self.prompt = None;
                vec![]
            }
            KeyInput::Enter => {
                let Prompt { line, buffer } = self.prompt.take().expect("checked above");
                if buffer.is_empty() {
                    return vec![];
                }
                self.log.place(
                    Some(line),
                    CallKind::Info,
                    format!("patched through to line {}: {}", line.0, &buffer),
                );
                vec![HostIntent::Say {
                    line,
                    text: format!("{buffer}\r"),
                }]
            }
            _ => vec![],
        }
    }

    fn settle_selected(&mut self, triage: Triage) -> Vec<HostIntent> {
        match self.view {
            View::Directory => {
                if let Some(line) = self.selected_line() {
                    self.log.settle_line(line, triage);
                }
            }
            View::Log => {
                if let Some(seq) = self.selected_call_seq() {
                    self.log.set_triage(seq, triage);
                }
            }
        }
        self.refresh_ring_flags();
        self.attention_intents()
    }

    // ---------- pipe ops (external world → model) ----------

    pub fn pipe_op(&mut self, payload: &str, reply_pipe: Option<String>) -> Vec<HostIntent> {
        let op = match protocol::parse(payload) {
            Ok(op) => op,
            Err(e) => {
                self.log
                    .place(None, CallKind::ProtocolError, format!("bad pipe payload: {e}"));
                return vec![];
            }
        };
        match op {
            PipeOp::Say { line, text } => match self.resolve_known(&line) {
                Some(id) => vec![HostIntent::Say { line: id, text }],
                None => self.unknown_line_call(),
            },
            PipeOp::Focus { line } => match self.resolve_known(&line) {
                Some(id) => vec![HostIntent::FocusLine(id)],
                None => self.unknown_line_call(),
            },
            PipeOp::Ring { line, note } => match self.resolve_known(&line) {
                Some(id) => {
                    self.log.place(
                        Some(id),
                        CallKind::Ring,
                        note.unwrap_or_else(|| format!("line {} is ringing", id.0)),
                    );
                    self.refresh_ring_flags();
                    self.attention_intents()
                }
                None => self.unknown_line_call(),
            },
            PipeOp::Status { line, state, note } => match self.resolve_known(&line) {
                Some(id) => {
                    if let Some(l) = self.lines.get_mut(&id) {
                        l.agent_state = state;
                    }
                    self.log.place(
                        Some(id),
                        CallKind::StatusReport,
                        note.unwrap_or_else(|| format!("line {} reports {state:?}", id.0)),
                    );
                    self.refresh_ring_flags();
                    self.attention_intents()
                }
                None => self.unknown_line_call(),
            },
            PipeOp::Register { line, label, kind } => match self.resolve_known(&line) {
                Some(id) => {
                    if let Some(l) = self.lines.get_mut(&id) {
                        if label.is_some() {
                            l.label = label;
                        }
                        if kind.is_some() {
                            l.kind = kind;
                        }
                        self.log.place(
                            Some(id),
                            CallKind::Info,
                            format!("line {} registered as {}", id.0, l.display_name()),
                        );
                    }
                    vec![]
                }
                None => self.unknown_line_call(),
            },
            PipeOp::List => {
                let lines = self.sorted_lines();
                let body = protocol::directory_json(&lines, |id| self.deck.key_for(id));
                reply_pipe
                    .map(|pipe| vec![HostIntent::PipeReply { pipe, body }])
                    .unwrap_or_default()
            }
            PipeOp::Log { n } => {
                let calls = self.log.calls();
                let tail = &calls[calls.len().saturating_sub(n.unwrap_or(100))..];
                let body = protocol::log_json(tail);
                reply_pipe
                    .map(|pipe| vec![HostIntent::PipeReply { pipe, body }])
                    .unwrap_or_default()
            }
        }
    }

    fn unknown_line_call(&mut self) -> Vec<HostIntent> {
        self.log
            .place(None, CallKind::ProtocolError, "pipe op for unknown line");
        vec![]
    }

    fn resolve_known(&self, r: &protocol::LineRef) -> Option<LineId> {
        r.resolve().filter(|id| self.lines.contains_key(id))
    }

    // ---------- views & selection ----------

    pub fn sorted_lines(&self) -> Vec<&Line> {
        let mut v: Vec<&Line> = self.lines.values().collect();
        match self.sort {
            SortMode::Deck => v.sort_by_key(|l| (self.deck.key_for(l.id).is_none(), self.deck_rank(l.id), l.id)),
            SortMode::RingingFirst => v.sort_by_key(|l| (!l.ringing, self.deck_rank(l.id), l.id)),
            SortMode::Board => v.sort_by_key(|l| (l.board, l.id)),
        }
        v
    }

    fn deck_rank(&self, id: LineId) -> u8 {
        self.deck
            .key_for(id)
            .and_then(|k| crate::deck::DECK_KEYS.iter().position(|d| *d == k))
            .map(|p| p as u8)
            .unwrap_or(u8::MAX)
    }

    pub fn selected_line(&self) -> Option<LineId> {
        match self.view {
            View::Directory => self.sorted_lines().get(self.selected).map(|l| l.id),
            View::Log => self
                .selected_call_seq()
                .and_then(|seq| self.log.calls().iter().find(|c| c.seq == seq))
                .and_then(|c| c.line),
        }
    }

    /// Log view shows newest first; selection indexes that ordering.
    pub fn log_view_calls(&self) -> Vec<&crate::log::Call> {
        let mut v: Vec<&crate::log::Call> = self.log.calls().iter().collect();
        v.reverse();
        if self.sort == SortMode::RingingFirst {
            v.sort_by_key(|c| c.triage != Triage::Ringing);
        }
        v
    }

    fn selected_call_seq(&self) -> Option<u64> {
        self.log_view_calls().get(self.selected).map(|c| c.seq)
    }

    fn clamp_selection(&mut self) {
        let len = match self.view {
            View::Directory => self.lines.len(),
            View::Log => self.log.calls().len(),
        };
        if len == 0 {
            self.selected = 0;
        } else if self.selected >= len {
            self.selected = len - 1;
        }
    }

    pub fn lines(&self) -> impl Iterator<Item = &Line> {
        self.lines.values()
    }

    pub fn boards(&self) -> &[BoardSnapshot] {
        &self.boards
    }

    // ---------- attention surface ----------

    fn refresh_ring_flags(&mut self) {
        let ringing = self.log.ringing_lines();
        for (id, line) in self.lines.iter_mut() {
            line.ringing = ringing.contains(id);
        }
    }

    /// Diff the ringing set against what the host currently shows and emit
    /// tint/highlight intents for the delta.
    fn attention_intents(&mut self) -> Vec<HostIntent> {
        let now: Vec<LineId> = self
            .lines
            .values()
            .filter(|l| l.ringing)
            .map(|l| l.id)
            .collect();
        if now == self.lit {
            return vec![];
        }
        let on: Vec<LineId> = now.iter().copied().filter(|id| !self.lit.contains(id)).collect();
        let off: Vec<LineId> = self.lit.iter().copied().filter(|id| !now.contains(id)).collect();
        let mut intents = Vec::new();
        for id in &on {
            intents.push(HostIntent::TintLine {
                line: *id,
                fg: Some(RING_FG.to_string()),
                bg: None,
            });
        }
        for id in &off {
            intents.push(HostIntent::TintLine {
                line: *id,
                fg: None,
                bg: None,
            });
        }
        intents.push(HostIntent::HighlightLines { on, off });
        self.lit = now;
        intents
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pane(id: u32, title: &str) -> PaneSnapshot {
        PaneSnapshot {
            id,
            title: title.into(),
            is_selectable: true,
            ..Default::default()
        }
    }

    fn exchange_with(panes: Vec<PaneSnapshot>) -> Exchange {
        let mut ex = Exchange::default();
        ex.ingest_panes(panes);
        ex
    }

    #[test]
    fn ingest_registers_lines_and_assigns_deck_keys() {
        let ex = exchange_with(vec![pane(10, "alpha"), pane(20, "beta")]);
        assert_eq!(ex.lines().count(), 2);
        assert_eq!(ex.deck.key_for(LineId(10)), Some('1'));
        assert_eq!(ex.deck.key_for(LineId(20)), Some('2'));
    }

    #[test]
    fn plugin_and_unselectable_panes_are_not_lines() {
        let mut p = pane(1, "ui");
        p.is_plugin = true;
        let mut q = pane(2, "chrome");
        q.is_selectable = false;
        let ex = exchange_with(vec![p, q]);
        assert_eq!(ex.lines().count(), 0);
    }

    #[test]
    fn exit_places_a_ringing_call_and_close_releases_everything() {
        let mut ex = exchange_with(vec![pane(1, "a"), pane(2, "b")]);
        let mut exited = pane(1, "a");
        exited.exited = true;
        exited.exit_status = Some(0);
        ex.ingest_panes(vec![exited, pane(2, "b")]);
        assert!(ex.log.line_is_ringing(LineId(1)));
        // now the pane disappears entirely
        ex.ingest_panes(vec![pane(2, "b")]);
        assert_eq!(ex.lines().count(), 1);
        assert!(!ex.log.line_is_ringing(LineId(1)));
        assert_eq!(ex.deck.key_for(LineId(1)), None);
        // freed key reused
        ex.ingest_panes(vec![pane(2, "b"), pane(9, "c")]);
        assert_eq!(ex.deck.key_for(LineId(9)), Some('1'));
    }

    #[test]
    fn deck_key_focuses_line_one_press() {
        let mut ex = exchange_with(vec![pane(5, "a")]);
        assert_eq!(
            ex.key(KeyInput::Char('1')),
            vec![HostIntent::FocusLine(LineId(5))]
        );
    }

    #[test]
    fn seat_swap_flow() {
        let mut ex = exchange_with(vec![pane(1, "a"), pane(2, "b")]);
        // no seat yet: s logs info, no intent
        assert!(ex.key(KeyInput::Char('s')).is_empty());
        // mark selected (first) as seat, select second, swap
        ex.key(KeyInput::Char('m'));
        ex.key(KeyInput::Down);
        assert_eq!(
            ex.key(KeyInput::Char('s')),
            vec![HostIntent::SwapIntoSeat {
                seat: LineId(1),
                line: LineId(2)
            }]
        );
        // closing the seat clears it
        ex.ingest_panes(vec![pane(2, "b")]);
        assert_eq!(ex.seat, None);
    }

    #[test]
    fn prompt_types_and_sends_with_cr() {
        let mut ex = exchange_with(vec![pane(3, "a")]);
        ex.key(KeyInput::Char('i'));
        assert!(ex.prompt.is_some());
        for c in "hi".chars() {
            ex.key(KeyInput::Char(c));
        }
        // deck digits must go into the buffer, not jump
        ex.key(KeyInput::Char('1'));
        ex.key(KeyInput::Backspace);
        let intents = ex.key(KeyInput::Enter);
        assert_eq!(
            intents,
            vec![HostIntent::Say {
                line: LineId(3),
                text: "hi\r".into()
            }]
        );
        assert!(ex.prompt.is_none());
    }

    #[test]
    fn ring_pipe_op_lights_the_line_and_answer_clears_it() {
        let mut ex = exchange_with(vec![pane(4, "a")]);
        let intents = ex.pipe_op(r#"{"op":"ring","line":4,"note":"review me"}"#, None);
        assert!(intents.contains(&HostIntent::TintLine {
            line: LineId(4),
            fg: Some(RING_FG.into()),
            bg: None
        }));
        assert!(ex.lines().next().unwrap().ringing);
        // answer from directory view ('a' on selected line)
        let intents = ex.key(KeyInput::Char('a'));
        assert!(intents.contains(&HostIntent::TintLine {
            line: LineId(4),
            fg: None,
            bg: None
        }));
        assert!(!ex.lines().next().unwrap().ringing);
    }

    #[test]
    fn status_and_register_attach_metadata() {
        let mut ex = exchange_with(vec![pane(4, "a")]);
        ex.pipe_op(r#"{"op":"register","line":4,"label":"synapse","kind":"claude"}"#, None);
        ex.pipe_op(r#"{"op":"status","line":4,"state":"blocked"}"#, None);
        let l = ex.lines().next().unwrap();
        assert_eq!(l.label.as_deref(), Some("synapse"));
        assert_eq!(l.kind.as_deref(), Some("claude"));
        assert_eq!(l.agent_state, AgentState::Blocked);
        assert!(l.ringing); // status reports ring
    }

    #[test]
    fn list_replies_on_the_cli_pipe_with_parseable_json() {
        let mut ex = exchange_with(vec![pane(1, "a")]);
        let intents = ex.pipe_op(r#"{"op":"list"}"#, Some("pipe-1".into()));
        match &intents[..] {
            [HostIntent::PipeReply { pipe, body }] => {
                assert_eq!(pipe, "pipe-1");
                let v: serde_json::Value = serde_json::from_str(body).unwrap();
                assert_eq!(v["lines"][0]["line"], 1);
                assert_eq!(v["lines"][0]["deck_key"], "1");
            }
            other => panic!("expected one PipeReply, got {other:?}"),
        }
    }

    #[test]
    fn malformed_and_unknown_line_payloads_become_protocol_error_calls() {
        let mut ex = exchange_with(vec![pane(1, "a")]);
        assert!(ex.pipe_op("garbage", None).is_empty());
        assert!(ex.pipe_op(r#"{"op":"say","line":99,"text":"x"}"#, None).is_empty());
        let kinds: Vec<_> = ex.log.calls().iter().map(|c| c.kind).collect();
        assert_eq!(
            kinds
                .iter()
                .filter(|k| matches!(k, CallKind::ProtocolError))
                .count(),
            2
        );
    }

    #[test]
    fn sort_modes_cycle_and_ringing_first_floats_ringers() {
        let mut ex = exchange_with(vec![pane(1, "a"), pane(2, "b"), pane(3, "c")]);
        ex.pipe_op(r#"{"op":"ring","line":3}"#, None);
        ex.key(KeyInput::Char('o')); // deck -> ringing-first
        assert_eq!(ex.sort, SortMode::RingingFirst);
        assert_eq!(ex.sorted_lines()[0].id, LineId(3));
        ex.key(KeyInput::Char('o'));
        ex.key(KeyInput::Char('o'));
        assert_eq!(ex.sort, SortMode::Deck);
        assert_eq!(ex.sorted_lines()[0].id, LineId(1));
    }

    #[test]
    fn tab_switches_views_and_esc_hides() {
        let mut ex = exchange_with(vec![pane(1, "a")]);
        ex.key(KeyInput::Tab);
        assert_eq!(ex.view, View::Log);
        assert_eq!(ex.key(KeyInput::Esc), vec![HostIntent::HideSelf]);
    }
}
