---
phase: "01"
plan: "01"
subsystem: core/key-model + plugin/adapter
tags: [key-model, modifier, refactor, tdd, comp-09]
dependency_graph:
  requires: []
  provides:
    - switchtail_core::BareKey
    - switchtail_core::KeyInput (struct with shift/super_ flags)
    - switchtail_core::KeyBinding + matches() predicate
    - Exchange::compose_board_key (configurable Shift/Super binding)
  affects:
    - crates/switchtail-core/src/exchange.rs (all dispatch arms ported)
    - crates/switchtail-plugin/src/main.rs (key_input() + load())
tech_stack:
  added:
    - BareKey enum (inner key vocabulary; mirrors zellij-tile's naming)
    - KeyBinding struct (configured compose-verb binding with required-modifier predicate)
  patterns:
    - TDD RED/GREEN on key.rs; mechanical port + extension on exchange.rs; adapter rewrite on main.rs
    - CoreBareKey alias to disambiguate switchtail_core::BareKey from zellij_tile::prelude::BareKey in the adapter
    - Total config parse (parse_compose_binding returns None on bad input — no panic)
key_files:
  created: []
  modified:
    - crates/switchtail-core/src/key.rs
    - crates/switchtail-core/src/lib.rs
    - crates/switchtail-core/src/exchange.rs
    - crates/switchtail-core/src/view.rs
    - crates/switchtail-plugin/src/main.rs
decisions:
  - Default compose binding is Shift+b: 'b' for board, Shift keeps it off deck digits and letter verbs; zellij-utils-0.44.3 data.rs:298 confirms KeyModifier::Shift exists.
  - CoreBareKey alias in main.rs: zellij_tile::prelude::BareKey and switchtail_core::BareKey share the same names but are distinct types; aliasing avoids the compiler conflict without changing public API.
  - parse_compose_binding format: "Sb" = Shift+b, "Qb" = Super+b, "SQb" = Shift+Super+b. Simple, total, minimal.
  - Compose check fires BEFORE deck dispatch in key(): prevents any Shift/Super key from accidentally double-firing as a deck jump.
  - prompt_key() swallows all chars regardless of modifiers (matches v0.1 behavior where the prompt captured all printable input including digits).
metrics:
  duration_seconds: 472
  completed_date: "2026-06-13"
  tasks_completed: 3
  tasks_total: 3
  files_changed: 5
---

# Phase 01 Plan 01: KeyInput modifier model + compose binding Summary

Modifier-aware KeyInput struct (BareKey + Shift/Super flags) with KeyBinding-match predicate and configurable compose_board_key on Exchange; adapter key_input() carries Shift/Super, rejects Ctrl/Alt.

## What Was Built

### Task 1 — Modifier-carrying KeyInput model (key.rs, lib.rs, view.rs)

Replaced the v0.1 flat `enum KeyInput` with:
- `enum BareKey { Char(char), Enter, Esc, Up, Down, Tab, Backspace }` — the seven bare alternatives
- `struct KeyInput { pub bare: BareKey, pub shift: bool, pub super_: bool }` — modifier-carrying wrapper
- Three ergonomic constructors: `KeyInput::ch(c)` (unmodified char), `KeyInput::key(bare)` (unmodified bare), `KeyInput::new(bare, shift, super_)` (modified)
- `struct KeyBinding { pub ch: char, pub shift: bool, pub super_: bool }` with `Default` impl (Shift+b) and `KeyInput::matches(&self, b: &KeyBinding) -> bool` exact-modifier predicate
- All three types exported from lib.rs; view.rs tests ported to new constructors

Key security property of `matches()`: an incoming key carrying an extra modifier the binding did not require does NOT match — this is the anti-collision guarantee (T-01-01 mitigation).

Commits: `8b97475` (RED), `5017e3d` (GREEN)

### Task 2 — Mechanical port of exchange.rs dispatch + compose_board_key field

Rewrote all ~30 match arms in `key()` and `prompt_key()` to use `key.bare` + modifier guards:
- Deck jump: `if let BareKey::Char(c) = key.bare { if !key.shift && !key.super_ { deck.line_for(c) } }` — unmodified-only, collision-safe
- Letter verbs (j/k/m/s/i/a/p/R/o/n): matched on `BareKey::Char('x') if !key.shift && !key.super_`
- Bare keys (Tab/Enter/Esc/Up/Down/Backspace): matched on `key.bare` directly
- prompt_key() swallows all Char variants regardless of modifiers (v0.1 behavior preserved)

Added `compose_board_key: KeyBinding` field to `Exchange` (derives via `KeyBinding::default()` = Shift+b). Compose check fires at the TOP of `key()` before deck dispatch — matching key returns `vec![]` (no-op placeholder; SpawnBoard intent wired in 01-03).

Ported the entire v0.1 test suite (exchange.rs + view.rs) to the new constructors. Added `compose_board_key_recognized_and_bare_char_is_not` test verifying the compose/bare distinction and that deck digits still work normally.

Total: 40 tests pass (including all ported v0.1 suite + new compose test + no_kill_guard).

Commit: `679f6ec`

### Task 3 — Adapter key_input() + load() config (main.rs)

Rewrote `key_input(key: &KeyWithModifier) -> Option<KeyInput>`:
- Rejects Ctrl/Alt-modified keys (return None; T-01-01 Tampering mitigation)
- Extracts `shift = key_modifiers.contains(Shift)`, `super_ = key_modifiers.contains(Super)`
- Maps zellij `BareKey` → core `CoreBareKey` (alias to avoid type collision with same-named zellij type)
- Builds `KeyInput::new(bare, shift, super_)` — deck digits stay unmodified-only because their KeyInput has shift=false, super_=false

Added `parse_compose_binding(raw: &str) -> Option<KeyBinding>` for config parsing. Format: optional `S` (Shift) / `Q` (Super) prefix flags + single char (`"Sb"` = Shift+b, `"Qb"` = Super+b, `"SQb"` = Shift+Super+b). Returns None on malformed input — total parse, never panics (T-01-02 DoS mitigation).

Updated `load()` to read `compose_board_key` from plugin configuration and set `self.exchange.compose_board_key` if valid; silently uses Exchange default if absent or unparseable.

VERIFIED CITATION: `KeyModifier::Super` exists at zellij-utils-0.44.3/src/data.rs:298 (enum is `{ Ctrl, Alt, Shift, Super }`).

Commit: `17a4227`

## Verification Results

```
tools/dev.sh test: 40 tests passed (core + adapter units + no_kill_guard)
tools/dev.sh build: wasm32-wasip1 debug artifact produced
grep close_*/kill_* crates/switchtail-plugin/src/: no new call sites (no-kill guard green)
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Task 1 GREEN required exchange.rs + view.rs port to compile**

- **Found during:** Task 1 GREEN implementation
- **Issue:** Changing `enum KeyInput` to `struct KeyInput` broke all call sites in exchange.rs and view.rs, making `tools/dev.sh test` fail to compile. Task 1's done criterion requires green tests; exchange.rs port was planned for Task 2.
- **Fix:** Included the mechanical exchange.rs port and view.rs update within the Task 1+2 implementation sequence. Task 1 commit covers key.rs + lib.rs + view.rs; Task 2 commit covers exchange.rs. Both are green before their respective commits.
- **Files modified:** `crates/switchtail-core/src/exchange.rs`, `crates/switchtail-core/src/view.rs`
- **Impact:** Zero behavioral change; mechanical translation only.

**2. [Rule 3 - Blocking] BareKey name collision between switchtail_core and zellij_tile**

- **Found during:** Task 3 wasm build
- **Issue:** Both `switchtail_core::BareKey` and `zellij_tile::prelude::BareKey` are in scope in main.rs; the compiler rejects unqualified match patterns (mismatched types error).
- **Fix:** Introduced `use switchtail_core::BareKey as CoreBareKey` alias in main.rs. Match patterns use the unqualified `BareKey` (= zellij's type, from the glob import); core constructors use `CoreBareKey`. No API change.
- **Files modified:** `crates/switchtail-plugin/src/main.rs`

## Threat Model Coverage

All T-01-0x threats from the plan's register were addressed:

| Threat | Status | Where |
|--------|--------|-------|
| T-01-01: Tampering via extra-modifier key | MITIGATED | `KeyInput::matches()` exact-modifier predicate; `key_input()` rejects Ctrl/Alt |
| T-01-02: DoS via unparseable config | MITIGATED | `parse_compose_binding()` is total; returns None on bad input |
| T-01-03: Privilege escalation via new permission | ACCEPTED (no change) | No new permissions in 01-01; RunCommands deferred to 01-03 |
| T-01-SC: Malicious cargo installs | N/A | No new dependencies |

## Known Stubs

**compose_board_key match branch in Exchange::key() — no-op placeholder**

- File: `crates/switchtail-core/src/exchange.rs`, `key()` method compose-verb branch
- The branch returns `vec![]` instead of `vec![SpawnBoard, OpenLine×(N-1)]`
- Reason: intentional placeholder; the `SpawnBoard` intent is defined in plan 01-02 and the spawn behavior is wired in plan 01-03
- Tracked: `// 01-02 returns the [SpawnBoard, OpenLine×(N-1)] fan-out here.` comment in place

## Self-Check: PASSED

All key files exist on disk:
- FOUND: crates/switchtail-core/src/key.rs
- FOUND: crates/switchtail-core/src/exchange.rs
- FOUND: crates/switchtail-plugin/src/main.rs
- FOUND: .planning/phases/01-board-foundation/01-01-SUMMARY.md

All commits exist in git log:
- FOUND: 8b97475 (RED: failing tests for new KeyInput model)
- FOUND: 5017e3d (GREEN Task 1: introduce modifier-carrying KeyInput model)
- FOUND: 679f6ec (GREEN Task 2: port key() dispatch; add compose_board_key)
- FOUND: 17a4227 (GREEN Task 3: adapter Shift/Super mapping + config)
