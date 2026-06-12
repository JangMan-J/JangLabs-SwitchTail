//! Host-agnostic input shapes. The plugin adapter converts zellij's
//! `PaneManifest`/`TabInfo` into these, keeping the core zellij-free.

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct PaneSnapshot {
    pub id: u32,
    pub is_plugin: bool,
    pub title: String,
    pub command: Option<String>,
    /// Tab position the pane lives on.
    pub board: usize,
    pub is_focused: bool,
    pub exited: bool,
    pub exit_status: Option<i32>,
    pub is_floating: bool,
    pub is_suppressed: bool,
    /// Unselectable panes (UI chrome) are not lines.
    pub is_selectable: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct BoardSnapshot {
    pub position: usize,
    pub name: String,
    pub active: bool,
}
