//! The call log: a capped ring of everything that happens on the exchange,
//! each call triageable by the operator (ringing → answered/parked).

use crate::line::LineId;
use serde::Serialize;

pub const LOG_CAP: usize = 512;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Triage {
    /// Wants the operator's attention.
    Ringing,
    /// Seen by the operator.
    Answered,
    /// Acknowledged and muted.
    Parked,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum CallKind {
    LineOpened,
    LineExited,
    LineClosed,
    CommandChanged,
    CwdChanged,
    StatusReport,
    Ring,
    Info,
    ProtocolError,
}

impl CallKind {
    /// Which kinds start life ringing (vs already-answered ambience).
    pub fn rings(&self) -> bool {
        matches!(
            self,
            CallKind::LineExited | CallKind::Ring | CallKind::StatusReport
        )
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Call {
    pub seq: u64,
    pub line: Option<LineId>,
    pub kind: CallKind,
    pub note: String,
    pub triage: Triage,
}

#[derive(Debug, Clone, Default)]
pub struct CallLog {
    calls: Vec<Call>, // newest last; capped at LOG_CAP
    next_seq: u64,
}

impl CallLog {
    pub fn place(&mut self, line: Option<LineId>, kind: CallKind, note: impl Into<String>) -> u64 {
        let seq = self.next_seq;
        self.next_seq += 1;
        let triage = if kind.rings() {
            Triage::Ringing
        } else {
            Triage::Answered
        };
        self.calls.push(Call {
            seq,
            line,
            kind,
            note: note.into(),
            triage,
        });
        if self.calls.len() > LOG_CAP {
            let excess = self.calls.len() - LOG_CAP;
            self.calls.drain(..excess);
        }
        seq
    }

    pub fn calls(&self) -> &[Call] {
        &self.calls
    }

    pub fn get_mut(&mut self, seq: u64) -> Option<&mut Call> {
        self.calls.iter_mut().find(|c| c.seq == seq)
    }

    pub fn set_triage(&mut self, seq: u64, triage: Triage) -> bool {
        match self.get_mut(seq) {
            Some(call) => {
                call.triage = triage;
                true
            }
            None => false,
        }
    }

    /// Answer or park every ringing call on a line. Returns how many changed.
    pub fn settle_line(&mut self, line: LineId, triage: Triage) -> usize {
        let mut n = 0;
        for c in &mut self.calls {
            if c.line == Some(line) && c.triage == Triage::Ringing {
                c.triage = triage;
                n += 1;
            }
        }
        n
    }

    pub fn line_is_ringing(&self, line: LineId) -> bool {
        self.calls
            .iter()
            .any(|c| c.line == Some(line) && c.triage == Triage::Ringing)
    }

    pub fn ringing_lines(&self) -> Vec<LineId> {
        let mut v: Vec<LineId> = self
            .calls
            .iter()
            .filter(|c| c.triage == Triage::Ringing)
            .filter_map(|c| c.line)
            .collect();
        v.sort();
        v.dedup();
        v
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ring_buffer_caps_and_keeps_newest() {
        let mut log = CallLog::default();
        for i in 0..(LOG_CAP + 40) {
            log.place(None, CallKind::Info, format!("call {i}"));
        }
        assert_eq!(log.calls().len(), LOG_CAP);
        assert_eq!(
            log.calls().last().unwrap().note,
            format!("call {}", LOG_CAP + 39)
        );
        assert_eq!(log.calls().first().unwrap().note, "call 40");
    }

    #[test]
    fn exits_and_rings_start_ringing_info_does_not() {
        let mut log = CallLog::default();
        let a = log.place(Some(LineId(1)), CallKind::LineExited, "exited");
        let b = log.place(Some(LineId(1)), CallKind::Info, "opened");
        assert_eq!(log.get_mut(a).unwrap().triage, Triage::Ringing);
        assert_eq!(log.get_mut(b).unwrap().triage, Triage::Answered);
    }

    #[test]
    fn settle_line_answers_all_ringing_calls() {
        let mut log = CallLog::default();
        log.place(Some(LineId(3)), CallKind::Ring, "r1");
        log.place(Some(LineId(3)), CallKind::Ring, "r2");
        log.place(Some(LineId(4)), CallKind::Ring, "other line");
        assert!(log.line_is_ringing(LineId(3)));
        assert_eq!(log.settle_line(LineId(3), Triage::Answered), 2);
        assert!(!log.line_is_ringing(LineId(3)));
        assert!(log.line_is_ringing(LineId(4)));
        assert_eq!(log.ringing_lines(), vec![LineId(4)]);
    }
}
