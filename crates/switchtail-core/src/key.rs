//! The core's own key vocabulary. The adapter maps host key events into
//! these; the core never sees host key types.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KeyInput {
    Char(char),
    Enter,
    Esc,
    Up,
    Down,
    Tab,
    Backspace,
}
