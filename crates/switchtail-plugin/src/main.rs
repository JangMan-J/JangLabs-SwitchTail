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
            self.exchange.line_command = cmd.split_whitespace().map(|s| s.to_string()).collect();
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
            EventType::CwdChanged,
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
            Event::CwdChanged(PaneId::Terminal(id), cwd, _) => {
                self.exchange
                    .note_cwd_change(LineId(id), &cwd.to_string_lossy());
                true
            }
            Event::PermissionRequestResult(_) => true,
            _ => false,
        }
    }

    fn pipe(&mut self, message: PipeMessage) -> bool {
        if message.name != protocol::PIPE_NAME {
            return false;
        }
        // CLI pipes are addressed by their per-invocation pipe id (the
        // PipeSource::Cli payload), NOT by the pipe name — replies and
        // unblocking must both target the id. (Verified empirically;
        // name-routing silently drops the output.)
        let reply_pipe = match &message.source {
            PipeSource::Cli(pipe_id) => Some(pipe_id.clone()),
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
        if let PipeSource::Cli(pipe_id) = &message.source {
            // Single-shot CLI ops: never leave the caller's pipe blocked.
            unblock_cli_pipe_input(pipe_id);
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
                HostIntent::SwapPanes { seat, line } => {
                    // Composed 3-call positional exchange (no single swap
                    // primitive exists in the plugin API):
                    // 1. Pin the line's slot with a throwaway placeholder.
                    let placeholder =
                        open_terminal_pane_in_place_of_pane_id(term(line), ".", false);
                    let Some(placeholder) = placeholder else {
                        eprintln!(
                            "switchtail: swap aborted — host refused placeholder pin \
                             (seat={}, line={})",
                            seat.0, line.0
                        );
                        continue;
                    };
                    // 2. Line takes the seat's slot; seat pane suppressed.
                    replace_pane_with_existing_pane(term(seat), term(line), true);
                    // 3. Seat takes the placeholder's slot (= line's original
                    //    slot); plugin-owned placeholder closes. Owner decision
                    //    (04-06 Task 1) blesses this scoped close. The no-kill
                    //    guard's FORBIDDEN list is untouched — suppress=false is
                    //    a parameter of replace_pane, not a close_* shim.
                    replace_pane_with_existing_pane(placeholder, term(seat), false);
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
                        let mut cmd =
                            CommandToRun::new_with_args(&command[0], command[1..].to_vec());
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
