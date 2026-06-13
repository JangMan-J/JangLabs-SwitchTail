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

// ---------- tests for the NEW modifier-carrying model (Task 1 RED) ----------
#[cfg(test)]
mod new_model_tests {
    // These tests reference types and constructors that do NOT exist yet.
    // They must FAIL to compile until Task 1 GREEN introduces the new shape.

    use crate::key::{BareKey, KeyBinding, KeyInput};

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
        // Shift+b binding
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

        // Non-match: Shift+Super+b (EXTRA modifier — must NOT match)
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
