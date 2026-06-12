//! Pure rendering: the exchange → styled terminal rows. ANSI only, CB-safe
//! palette (blue ↔ amber + lightness; meaning never rides on red↔green; every
//! state also carries a text/shape cue).

use crate::exchange::{Exchange, View};
use crate::line::AgentState;
use crate::log::Triage;

const RESET: &str = "\x1b[0m";
const BOLD: &str = "\x1b[1m";
const DIM: &str = "\x1b[2m";
const INVERT: &str = "\x1b[7m";
const BLUE: &str = "\x1b[38;5;75m";
const AMBER: &str = "\x1b[38;5;214m";

fn truncate(s: &str, max: usize) -> String {
    if s.chars().count() <= max {
        s.to_string()
    } else {
        let cut: String = s.chars().take(max.saturating_sub(1)).collect();
        format!("{cut}…")
    }
}

pub fn render(ex: &Exchange, rows: usize, cols: usize) -> Vec<String> {
    let mut out = Vec::new();
    let width = cols.max(20);
    let ringing = ex.lines().filter(|l| l.ringing).count();
    let header = format!(
        "{BOLD}{BLUE} SWITCHTAIL {RESET}{DIM}·{RESET} {} {DIM}·{RESET} {} lines{}",
        match ex.view {
            View::Directory => "directory",
            View::Log => "call log",
        },
        ex.lines().count(),
        if ringing > 0 {
            format!(" {AMBER}{BOLD}· {ringing} RINGING{RESET}")
        } else {
            String::new()
        },
    );
    out.push(header);

    let body_rows = rows.saturating_sub(3).max(1);
    match ex.view {
        View::Directory => render_directory(ex, body_rows, width, &mut out),
        View::Log => render_log(ex, body_rows, width, &mut out),
    }
    while out.len() < rows.saturating_sub(1) {
        out.push(String::new());
    }
    out.truncate(rows.saturating_sub(1));

    if let Some(prompt) = &ex.prompt {
        out.push(format!(
            "{AMBER}{BOLD} say→line {}:{RESET} {}{BOLD}▏{RESET}",
            prompt.line.0, prompt.buffer
        ));
    } else {
        out.push(format!(
            "{DIM} 1-0 jump · j/k+⏎ focus · m seat · s swap · i say · a/p/R triage · o sort[{}] · ⇥ view · n new · esc{RESET}",
            ex.sort.name()
        ));
    }
    out
}

fn render_directory(ex: &Exchange, body_rows: usize, width: usize, out: &mut Vec<String>) {
    let lines = ex.sorted_lines();
    if lines.is_empty() {
        out.push(format!(
            "{DIM} no lines on the exchange — press n to open one{RESET}"
        ));
        return;
    }
    for (i, l) in lines.iter().take(body_rows).enumerate() {
        let key = ex
            .deck
            .key_for(l.id)
            .map(|k| format!("[{k}]"))
            .unwrap_or_else(|| "[ ]".into());
        let seat = if ex.seat == Some(l.id) { "⌂" } else { " " };
        let state = match (l.exited, l.ringing, l.agent_state) {
            (true, _, _) => format!("{DIM}■ exited{RESET}"),
            (_, true, _) => format!("{AMBER}{BOLD}◉ RINGING{RESET}"),
            (_, _, AgentState::Working) => format!("{BLUE}● working{RESET}"),
            (_, _, AgentState::Blocked) => format!("{AMBER}◍ blocked{RESET}"),
            (_, _, AgentState::Done) => format!("{BLUE}○ done{RESET}"),
            _ => format!("{DIM}○{RESET}"),
        };
        let kind = l.kind.as_deref().unwrap_or("");
        let focus = if l.focused {
            format!("{BLUE}▸{RESET}")
        } else {
            " ".into()
        };
        let name = truncate(&l.display_name(), width.saturating_sub(30));
        let sel = if i == ex.selected { INVERT } else { "" };
        out.push(format!(
            "{sel}{focus}{seat}{BOLD}{key}{RESET}{sel} b{} {name} {DIM}{kind}{RESET}{sel} {state}{RESET}",
            l.board
        ));
    }
}

fn render_log(ex: &Exchange, body_rows: usize, width: usize, out: &mut Vec<String>) {
    let calls = ex.log_view_calls();
    if calls.is_empty() {
        out.push(format!("{DIM} the call log is empty{RESET}"));
        return;
    }
    for (i, c) in calls.iter().take(body_rows).enumerate() {
        let (mark, style) = match c.triage {
            Triage::Ringing => ("◉ ring", AMBER),
            Triage::Answered => ("· ansd", BLUE),
            Triage::Parked => ("‥ park", DIM),
        };
        let line = c
            .line
            .map(|l| format!("L{}", l.0))
            .unwrap_or_else(|| "—".into());
        let note = truncate(&c.note, width.saturating_sub(24));
        let sel = if i == ex.selected { INVERT } else { "" };
        out.push(format!(
            "{sel}{style}{mark}{RESET}{sel} {DIM}#{}{RESET}{sel} {line:>4} {note}{RESET}",
            c.seq
        ));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::key::KeyInput;
    use crate::snapshot::PaneSnapshot;

    fn strip_ansi(s: &str) -> String {
        let mut out = String::new();
        let mut in_esc = false;
        for ch in s.chars() {
            if in_esc {
                if ch == 'm' {
                    in_esc = false;
                }
            } else if ch == '\x1b' {
                in_esc = true;
            } else {
                out.push(ch);
            }
        }
        out
    }

    fn ex_with_two_lines() -> Exchange {
        let mut ex = Exchange::default();
        ex.ingest_panes(vec![
            PaneSnapshot {
                id: 1,
                title: "synapse".into(),
                is_selectable: true,
                ..Default::default()
            },
            PaneSnapshot {
                id: 2,
                title: "proton".into(),
                is_selectable: true,
                ..Default::default()
            },
        ]);
        ex
    }

    #[test]
    fn directory_shows_deck_keys_names_and_footer() {
        let ex = ex_with_two_lines();
        let rows = render(&ex, 10, 80);
        let flat = strip_ansi(&rows.join("\n"));
        assert!(flat.contains("[1]") && flat.contains("synapse"));
        assert!(flat.contains("[2]") && flat.contains("proton"));
        assert!(flat.contains("jump"));
        assert_eq!(rows.len(), 10);
    }

    #[test]
    fn ringing_header_count_and_log_view() {
        let mut ex = ex_with_two_lines();
        ex.pipe_op(r#"{"op":"ring","line":1,"note":"check me"}"#, None);
        let flat = strip_ansi(&render(&ex, 10, 80).join("\n"));
        assert!(flat.contains("1 RINGING"));
        ex.key(KeyInput::Tab);
        let flat = strip_ansi(&render(&ex, 10, 80).join("\n"));
        assert!(flat.contains("check me"));
        assert!(flat.contains("ring"));
    }

    #[test]
    fn prompt_replaces_footer() {
        let mut ex = ex_with_two_lines();
        ex.key(KeyInput::Char('i'));
        ex.key(KeyInput::Char('h'));
        let rows = render(&ex, 10, 80);
        let flat = strip_ansi(rows.last().unwrap());
        assert!(flat.contains("say→line 1") && flat.contains('h'));
    }

    #[test]
    fn rows_never_exceed_requested_height() {
        let mut ex = Exchange::default();
        let panes: Vec<PaneSnapshot> = (0..40)
            .map(|i| PaneSnapshot {
                id: i,
                title: format!("line{i}"),
                is_selectable: true,
                ..Default::default()
            })
            .collect();
        ex.ingest_panes(panes);
        assert_eq!(render(&ex, 12, 60).len(), 12);
    }
}
