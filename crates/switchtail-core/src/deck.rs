//! The deck: stable one-press jump keys for lines. Digits only in v0.1 —
//! ten slots, numpad-friendly; lines beyond the deck are reached by
//! selection. Assignments are sticky: a line keeps its key for life, freed
//! keys are reused lowest-first.

use crate::line::LineId;
use std::collections::BTreeMap;

pub const DECK_KEYS: [char; 10] = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];

#[derive(Debug, Clone, Default)]
pub struct Deck {
    slots: BTreeMap<u8, LineId>, // slot index -> line
}

impl Deck {
    /// Assign the lowest free slot to `line` if it has none. Returns its key.
    pub fn assign(&mut self, line: LineId) -> Option<char> {
        if let Some(key) = self.key_for(line) {
            return Some(key);
        }
        for (i, key) in DECK_KEYS.iter().enumerate() {
            let i = i as u8;
            if !self.slots.contains_key(&i) {
                self.slots.insert(i, line);
                return Some(*key);
            }
        }
        None // deck full — line reachable via selection only
    }

    /// Free the slot held by `line` (line closed).
    pub fn release(&mut self, line: LineId) {
        self.slots.retain(|_, l| *l != line);
    }

    pub fn key_for(&self, line: LineId) -> Option<char> {
        self.slots
            .iter()
            .find(|(_, l)| **l == line)
            .map(|(i, _)| DECK_KEYS[*i as usize])
    }

    pub fn line_for(&self, key: char) -> Option<LineId> {
        let idx = DECK_KEYS.iter().position(|k| *k == key)? as u8;
        self.slots.get(&idx).copied()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn assigns_lowest_free_slot_and_is_sticky() {
        let mut d = Deck::default();
        assert_eq!(d.assign(LineId(10)), Some('1'));
        assert_eq!(d.assign(LineId(20)), Some('2'));
        // re-assign is a no-op returning the existing key
        assert_eq!(d.assign(LineId(10)), Some('1'));
        assert_eq!(d.line_for('2'), Some(LineId(20)));
    }

    #[test]
    fn released_slots_are_reused_lowest_first() {
        let mut d = Deck::default();
        for n in 0..5 {
            d.assign(LineId(n));
        }
        d.release(LineId(1)); // frees slot '2'
        d.release(LineId(3)); // frees slot '4'
        assert_eq!(d.assign(LineId(99)), Some('2'));
        assert_eq!(d.assign(LineId(100)), Some('4'));
    }

    #[test]
    fn deck_overflow_returns_none() {
        let mut d = Deck::default();
        for n in 0..10 {
            assert!(d.assign(LineId(n)).is_some());
        }
        assert_eq!(d.assign(LineId(999)), None);
        d.release(LineId(0));
        assert_eq!(d.assign(LineId(999)), Some('1'));
    }
}
