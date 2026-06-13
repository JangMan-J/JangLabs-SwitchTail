//! The core's own key vocabulary. The adapter maps host key events into
//! these; the core never sees host key types.
//!
//! ## Shape (v0.2, COMP-09)
//!
//! `BareKey` carries the seven alternatives from v0.1 (Char, Enter, Esc, Up,
//! Down, Tab, Backspace). `KeyInput` wraps a `BareKey` with `shift` and
//! `super_` flags so compose verbs can bind on Shift/Super without colliding
//! with Zellij's Ctrl/Alt space. `KeyBinding` records a configured compose
//! binding (char + required Shift/Super); `KeyInput::matches` performs the
//! EXACT-modifier predicate (extra modifiers on the incoming key never match).

/// The bare (modifier-free) key alternatives.
///
/// Mirrors the seven variants from the v0.1 flat `enum KeyInput`; named
/// `BareKey` to match zellij-tile's own naming convention in `Key::bare_key`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BareKey {
    Char(char),
    Enter,
    Esc,
    Up,
    Down,
    Tab,
    Backspace,
}

/// A modifier-carrying key event from the operator.
///
/// Carries `shift` and `super_` flags; Ctrl/Alt are deliberately NOT modeled
/// here — Zellij owns that space (see COMP-09 / 01-CONTEXT.md).
///
/// ## Constructors
///
/// - `KeyInput::ch('c')` — unmodified char key
/// - `KeyInput::key(BareKey::Tab)` — unmodified bare key
/// - `KeyInput::new(bare, shift, super_)` — modified key
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct KeyInput {
    pub bare: BareKey,
    pub shift: bool,
    pub super_: bool,
}

impl KeyInput {
    /// An unmodified character key (shift=false, super_=false).
    pub fn ch(c: char) -> Self {
        Self {
            bare: BareKey::Char(c),
            shift: false,
            super_: false,
        }
    }

    /// An unmodified bare key (non-char, e.g. Tab / Enter / Esc).
    pub fn key(bare: BareKey) -> Self {
        Self {
            bare,
            shift: false,
            super_: false,
        }
    }

    /// A key with explicit Shift and/or Super modifiers.
    pub fn new(bare: BareKey, shift: bool, super_: bool) -> Self {
        Self { bare, shift, super_ }
    }

    /// Whether this incoming key matches a configured `KeyBinding`.
    ///
    /// Returns `true` iff the bare char AND the required modifier set match
    /// EXACTLY. An incoming key carrying an EXTRA modifier the binding did not
    /// require does NOT match — this is the anti-collision guarantee that keeps
    /// deck digits and letter verbs safe from compose-verb capture.
    pub fn matches(&self, b: &KeyBinding) -> bool {
        self.bare == BareKey::Char(b.ch) && self.shift == b.shift && self.super_ == b.super_
    }
}

/// A configured compose-verb binding: char + required Shift/Super modifiers.
///
/// Read from plugin config in `load()` (see `main.rs`); stored on `Exchange`
/// as `compose_board_key`. The default (Shift+b) is chosen to be off Zellij's
/// Ctrl/Alt space and unlikely to collide with deck digits or letter verbs.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct KeyBinding {
    pub ch: char,
    pub shift: bool,
    pub super_: bool,
}

impl Default for KeyBinding {
    /// Default compose binding: Shift+b.
    ///
    /// Choice rationale: `b` for "board"; Shift prefix keeps it off deck
    /// digits (1-9 0) and existing letter verbs (all unmodified); Shift is
    /// modeled in zellij-utils-0.44.3/src/data.rs:298 (enum Ctrl, Alt, Shift,
    /// Super). Config-overridable via `compose_board_key = "Sb"` in KDL.
    fn default() -> Self {
        Self {
            ch: 'b',
            shift: true,
            super_: false,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plain_char_equals_same_plain_char() {
        assert_eq!(KeyInput::ch('j'), KeyInput::ch('j'));
    }

    #[test]
    fn shift_char_is_distinct_from_bare_char() {
        let shifted = KeyInput::new(BareKey::Char('b'), true, false);
        let bare = KeyInput::ch('b');
        assert_ne!(shifted, bare);
    }

    #[test]
    fn super_char_is_distinct_from_bare_and_shift() {
        let super_key = KeyInput::new(BareKey::Char('b'), false, true);
        let bare = KeyInput::ch('b');
        let shifted = KeyInput::new(BareKey::Char('b'), true, false);
        assert_ne!(super_key, bare);
        assert_ne!(super_key, shifted);
    }

    #[test]
    fn bare_key_round_trip() {
        let enter = KeyInput::key(BareKey::Enter);
        assert_eq!(enter.bare, BareKey::Enter);
        assert!(!enter.shift);
        assert!(!enter.super_);

        let esc = KeyInput::key(BareKey::Esc);
        assert_eq!(esc.bare, BareKey::Esc);

        let tab = KeyInput::key(BareKey::Tab);
        assert_eq!(tab.bare, BareKey::Tab);

        let up = KeyInput::key(BareKey::Up);
        assert_eq!(up.bare, BareKey::Up);

        let down = KeyInput::key(BareKey::Down);
        assert_eq!(down.bare, BareKey::Down);

        let backspace = KeyInput::key(BareKey::Backspace);
        assert_eq!(backspace.bare, BareKey::Backspace);
    }

    #[test]
    fn key_binding_matches_exact_modifiers_only() {
        // Shift+b binding (the default compose_board_key)
        let binding = KeyBinding {
            ch: 'b',
            shift: true,
            super_: false,
        };

        // Exact match: Shift+b
        let shift_b = KeyInput::new(BareKey::Char('b'), true, false);
        assert!(shift_b.matches(&binding), "Shift+b must match Shift+b binding");

        // Non-match: bare 'b' (no modifier)
        let bare_b = KeyInput::ch('b');
        assert!(!bare_b.matches(&binding), "bare 'b' must not match Shift+b binding");

        // Non-match: Super+b (different modifier)
        let super_b = KeyInput::new(BareKey::Char('b'), false, true);
        assert!(!super_b.matches(&binding), "Super+b must not match Shift+b binding");

        // Non-match: Shift+Super+b — EXTRA modifier must NOT match
        let shift_super_b = KeyInput::new(BareKey::Char('b'), true, true);
        assert!(
            !shift_super_b.matches(&binding),
            "Shift+Super+b must NOT match a Shift-only binding (extra-modifier non-match)"
        );

        // Non-match: different char
        let shift_c = KeyInput::new(BareKey::Char('c'), true, false);
        assert!(!shift_c.matches(&binding), "Shift+c must not match Shift+b binding");
    }
}
