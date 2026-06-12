//! switchtail — the Zellij plugin adapter. Thin by contract: zellij Events
//! map into switchtail-core mutations, returned [`HostIntent`]s map 1:1 onto
//! shim calls, and render just prints the core's rows. No business logic
//! here, and **no close/kill call sites** (test-enforced; see CLAUDE.md).

use std::collections::BTreeMap;

use switchtail_core::{
    BoardSnapshot, Exchange, HostIntent, KeyInput, LineId, PaneSnapshot, protocol,
};
use zellij_tile::prelude::*;

#[derive(Default)]
struct State {
    exchange: Exchange,
}

register_plugin!(State);

impl ZellijPlugin for State {
    fn load(&mut self, configuration: BTreeMap<String, String>) {
        if let Some(cmd) = configuration.get("line_command") {
            self.exchange.line_command = cmd
                .split_whitespace()
                .map(|s| s.to_string())
                .collect();
        }
        request_permission(&[
            PermissionType::ReadApplicationState,
            PermissionType::ChangeApplicationState,
            PermissionType::OpenTerminalsOrPlugins,
            PermissionType::WriteToStdin,
            PermissionType::ReadCliPipes,
        ]);
        subscribe(&[
            EventType::PaneUpdate,
            EventType::TabUpdate,
            EventType::Key,
            EventType::PermissionRequestResult,
        ]);
        set_selectable(true);
    }

    fn update(&mut self, event: Event) -> bool {
        match event {
            Event::PaneUpdate(manifest) => {
                let panes = pane_snapshots(&manifest);
                let intents = self.exchange.ingest_panes(panes);
                self.dispatch(intents);
                true
            }
            Event::TabUpdate(tabs) => {
                self.exchange.ingest_boards(
                    tabs.iter()
                        .map(|t| BoardSnapshot {
                            position: t.position,
                            name: t.name.clone(),
                            active: t.active,
                        })
                        .collect(),
                );
                true
            }
            Event::Key(key) => match key_input(&key) {
                Some(k) => {
                    let intents = self.exchange.key(k);
                    self.dispatch(intents);
                    true
                }
                None => false,
            },
            Event::PermissionRequestResult(_) => true,
            _ => false,
        }
    }

    fn pipe(&mut self, message: PipeMessage) -> bool {
        if message.name != protocol::PIPE_NAME {
            return false;
        }
        let reply_pipe = match &message.source {
            PipeSource::Cli(_) => Some(message.name.clone()),
            _ => None,
        };
        let mut render = false;
        if let Some(payload) = &message.payload {
            for line in payload.lines().filter(|l| !l.trim().is_empty()) {
                let intents = self.exchange.pipe_op(line, reply_pipe.clone());
                self.dispatch(intents);
                render = true;
            }
        }
        if let PipeSource::Cli(_) = &message.source {
            // Single-shot CLI ops: never leave the caller's pipe blocked.
            unblock_cli_pipe_input(&message.name);
        }
        render
    }

    fn render(&mut self, rows: usize, cols: usize) {
        let lines = switchtail_core::view::render(&self.exchange, rows, cols);
        print!("{}", lines.join("\n"));
    }
}

impl State {
    /// The intent dispatcher: each arm is exactly one host effect.
    fn dispatch(&mut self, intents: Vec<HostIntent>) {
        for intent in intents {
            match intent {
                HostIntent::FocusLine(line) => {
                    // Jump means: get the switchboard out of the way too.
                    focus_pane_with_id(term(line), true, false);
                    hide_self();
                }
                HostIntent::SwapIntoSeat { seat, line } => {
                    // suppress=true keeps the displaced pane alive & recoverable
                    // (focus_pane_with_id unsuppresses). True positional swap is
                    // a post-v0.1 refinement pending empirical E2E.
                    replace_pane_with_existing_pane(term(seat), term(line), true);
                }
                HostIntent::Say { line, text } => {
                    write_chars_to_pane_id(&text, term(line));
                }
                HostIntent::RenameLine { line, name } => {
                    rename_pane_with_id(term(line), name);
                }
                HostIntent::TintLine { line, fg, bg } => {
                    set_pane_color(term(line), fg, bg);
                }
                HostIntent::HighlightLines { on, off } => {
                    highlight_and_unhighlight_panes(
                        on.into_iter().map(term).collect(),
                        off.into_iter().map(term).collect(),
                    );
                }
                HostIntent::OpenLine { command, cwd } => {
                    let cwd = cwd.map(std::path::PathBuf::from);
                    if command.is_empty() {
                        open_terminal(cwd.unwrap_or_else(|| ".".into()));
                    } else {
                        let mut cmd = CommandToRun::new_with_args(&command[0], command[1..].to_vec());
                        cmd.cwd = cwd;
                        open_command_pane(cmd, BTreeMap::new());
                    }
                }
                HostIntent::PipeReply { pipe, body } => {
                    cli_pipe_output(&pipe, &body);
                }
                HostIntent::HideSelf => {
                    hide_self();
                }
            }
        }
    }
}

fn term(line: LineId) -> PaneId {
    PaneId::Terminal(line.0)
}

fn pane_snapshots(manifest: &PaneManifest) -> Vec<PaneSnapshot> {
    let mut out = Vec::new();
    for (tab_position, panes) in &manifest.panes {
        for p in panes {
            out.push(PaneSnapshot {
                id: p.id,
                is_plugin: p.is_plugin,
                title: p.title.clone(),
                command: p.terminal_command.clone(),
                board: *tab_position,
                is_focused: p.is_focused,
                exited: p.exited,
                exit_status: p.exit_status,
                is_floating: p.is_floating,
                is_suppressed: p.is_suppressed,
                is_selectable: p.is_selectable,
            });
        }
    }
    out
}

fn key_input(key: &KeyWithModifier) -> Option<KeyInput> {
    if !key.key_modifiers.is_empty()
        && !(key.key_modifiers.len() == 1 && key.key_modifiers.contains(&KeyModifier::Shift))
    {
        return None;
    }
    match key.bare_key {
        BareKey::Char(c) => Some(KeyInput::Char(c)),
        BareKey::Enter => Some(KeyInput::Enter),
        BareKey::Esc => Some(KeyInput::Esc),
        BareKey::Up => Some(KeyInput::Up),
        BareKey::Down => Some(KeyInput::Down),
        BareKey::Tab => Some(KeyInput::Tab),
        BareKey::Backspace => Some(KeyInput::Backspace),
        _ => None,
    }
}
