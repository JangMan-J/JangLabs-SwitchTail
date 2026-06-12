//! switchtail-core — the pure switchboard model.
//!
//! The metaphor is the architecture: an `Exchange` (session) holds `Line`s
//! (terminal panes) organized on `Board`s (tabs), with a `Deck` of one-press
//! keys, a `seat` (the main working position), and a `CallLog` of triageable
//! `Call`s. Host effects never happen here — operations return
//! [`HostIntent`]s for the plugin adapter to dispatch. This crate must never
//! depend on zellij.

pub mod deck;
pub mod exchange;
pub mod intent;
pub mod key;
pub mod line;
pub mod log;
pub mod protocol;
pub mod snapshot;
pub mod view;

pub use deck::{DECK_KEYS, Deck};
pub use exchange::{Exchange, SortMode, View};
pub use intent::HostIntent;
pub use key::KeyInput;
pub use line::{AgentState, Line, LineId};
pub use log::{Call, CallKind, CallLog, Triage};
pub use protocol::PipeOp;
pub use snapshot::{BoardSnapshot, PaneSnapshot};
