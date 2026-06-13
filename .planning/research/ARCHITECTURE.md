# Architecture Research

**Domain:** v0.2 live composition integration — SwitchTail Zellij plugin
**Researched:** 2026-06-13
**Confidence:** HIGH (grounded entirely in actual source files; no training-data API assumptions)

---

## Standard Architecture

### System Overview

```
┌───────────────────────────────────────────────────────────┐
│              switchtail-plugin  (WASM adapter)             │
│  ZellijPlugin::update()   ZellijPlugin::pipe()            │
│   Event::Key → key_input() → exchange.key(k)             │
│   Event::PaneUpdate → exchange.ingest_panes()             │
│   Event::TabUpdate  → exchange.ingest_boards()            │
├───────────────────────────────────────────────────────────┤
│              HostIntent seam  (intent.rs)                  │
│   Vec<HostIntent> flows UP from core to adapter           │
│   Adapter's dispatch() loop: one arm = one shim call      │
├───────────────────────────────────────────────────────────┤
│              switchtail-core  (pure model, no zellij dep)  │
│   Exchange { lines, boards, deck, log, seat, view, sort,  │
│              selected_line_id, selected_seq_id,            │
│              prompt: Option<Prompt>,                       │
│              line_command, lit }                           │
│   key()        → routes to sub-handlers (prompt_key, …)   │
│   ingest_*()   → maintains directory, deck, log           │
│   pipe_op()    → external protocol                        │
└───────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | v0.2 change? |
|-----------|----------------|-------------|
| `exchange.rs` | Root model; all mutations; key routing | **Add `compose` sub-state field and `compose_key()` handler** |
| `intent.rs` | `HostIntent` enum — every host effect | **Add `OpenBoard` variant** |
| `main.rs` dispatcher | One arm per `HostIntent` | **Add `OpenBoard` arm** |
| `main.rs` load() | Config loading | **Add `agent_command` config key** |
| `key.rs` `KeyInput` | Core's key vocabulary | No change needed |

---

## Architectural Patterns

### Pattern 1: Mid-Bind Sub-State Machine (the Prompt Analog)

**What:** When a verb key opens a pending-count input phase, `Exchange` stores a `Compose` struct in an `Option<Compose>` field. Subsequent key calls route to `compose_key()` instead of the main `key()` dispatch table. On termination the state is consumed and the intents are emitted. This is identical in structure to the existing `Option<Prompt>` / `prompt_key()` pattern.

**When to use:** Any two-press (or multi-press) interaction where the first press is an intent to act and subsequent presses are parameters.

**How it routes in `key()`:**

```rust
// exchange.rs  key()  — add at the TOP, before the existing `prompt` check
pub fn key(&mut self, key: KeyInput) -> Vec<HostIntent> {
    if self.compose.is_some() {
        return self.compose_key(key);
    }
    if self.prompt.is_some() {
        return self.prompt_key(key);
    }
    // … existing match …
}
```

Compose check gates before prompt check because both cannot be active simultaneously, but a compose could be entered from any non-prompt state. If they need independent priority order, compose first is the correct default: compose is lighter (one character input) and closes faster.

**The `Compose` struct:**

```rust
/// Mid-bind composition state: a verb has been pressed and the core is
/// awaiting an optional count digit. Esc cancels; a digit sets count and
/// executes immediately; Enter/any-non-digit executes with count = 1 and
/// re-routes the unrecognised key back into normal key().
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Compose {
    pub verb: ComposeVerb,
    pub count: Option<u8>,   // digit pressed so far; None = not yet given = 1
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ComposeVerb {
    AddLine,
    AddBoard,
}
```

**`compose_key()` handler:**

```rust
fn compose_key(&mut self, key: KeyInput) -> Vec<HostIntent> {
    let compose = self.compose.take().expect("compose_key without compose");
    match key {
        KeyInput::Esc => {
            // cancelled — state already taken/dropped
            vec![]
        }
        KeyInput::Char(c) if c.is_ascii_digit() => {
            let n = c.to_digit(10).unwrap() as u8;
            let count = n.max(1);  // '0' treated as 1
            self.execute_compose(compose.verb, count)
        }
        _ => {
            // No count given — act with count=1, then re-route the key
            // (handles Enter, deck keys, j/k, etc. falling through naturally)
            let mut intents = self.execute_compose(compose.verb, 1);
            intents.extend(self.key(key));   // recurse once; compose is gone
            intents
        }
    }
}
```

**`execute_compose()` — intent fan-out:**

```rust
fn execute_compose(&mut self, verb: ComposeVerb, count: u8) -> Vec<HostIntent> {
    let count = count.max(1) as usize;
    match verb {
        ComposeVerb::AddLine => {
            let cmd = self.agent_command.clone();
            (0..count)
                .map(|_| HostIntent::OpenLine { command: cmd.clone(), cwd: None })
                .collect()
        }
        ComposeVerb::AddBoard => {
            (0..count)
                .map(|_| HostIntent::OpenBoard { command: self.agent_command.clone() })
                .collect()
        }
    }
}
```

**Trade-offs:**
- Pure core, fully unit-testable: `exchange.key(KeyInput::Char('N'))` → compose entered; `exchange.key(KeyInput::Char('3'))` → three intents out. No Zellij needed.
- Count is single-digit (1–9). Multi-digit counts (e.g. "12 lines") require accumulation state and are explicitly deferred; current design terminates on any digit.
- Re-routing non-digit keys through `key()` is safe because `self.compose` has already been `take()`n before recursion; no infinite loop risk.

---

### Pattern 2: Intent Fan-Out (N `OpenLine` intents, not one batched intent)

**What:** When the count is N > 1, `execute_compose` emits a `Vec<HostIntent>` with N `OpenLine` (or `OpenBoard`) items. The adapter's `dispatch()` loop iterates all intents and calls the shim once per intent. No "batch" intent variant is needed.

**Rationale:** The adapter's dispatch loop already iterates a `Vec<HostIntent>` (see `main.rs` line 115: `for intent in intents`). Each `OpenLine` results in one `open_command_pane()` or `open_terminal()` call. This keeps the adapter dumb: it sees one standard intent per desired effect, not a count field it must unroll. The core's `execute_compose` is the only place the count logic lives.

**Contrast with SwapPanes:** `SwapPanes` is the one sanctioned composed transaction because the placeholder PaneId is host-allocated mid-sequence and cannot cross the seam (documented in `intent.rs` lines 3–12). Fan-out does not have this constraint: each `OpenLine` is independent and carries no reference to previously allocated IDs.

---

### Pattern 3: Default-Command Resolution Lives in Core

**What:** `Exchange` gains an `agent_command: Vec<String>` field alongside the existing `line_command: Vec<String>`. Core resolves the default: if the operator has not specified a command, the emitted `OpenLine { command: agent_command.clone(), … }` already carries `["claude"]`. The adapter sees a fully-resolved command and calls `open_command_pane` with it. No command-resolution logic in `main.rs`.

**Why core, not adapter:**
- Testable: a unit test can assert that `exchange.key('N')` (or the compose path) emits `OpenLine { command: vec!["claude".into()], cwd: None }` without Zellij.
- Consistent: the same field can be tested for `line_command` precedence, override logic, fallback to `$SHELL` for a "bare line" variant, etc.
- The adapter already follows this pattern: `line_command` is loaded into core at `load()` and the adapter never re-derives it.

**New config key and Exchange field:**

```rust
// exchange.rs Exchange struct — new field
pub agent_command: Vec<String>,   // default: vec!["claude".into()]

// exchange.rs  Exchange::default() or new()
agent_command: vec!["claude".into()],
```

```rust
// main.rs  load()
if let Some(cmd) = configuration.get("agent_command") {
    self.exchange.agent_command = cmd.split_whitespace().map(|s| s.to_string()).collect();
}
```

The `line_command` field (default shell, keyed to `n`) and `agent_command` (default `claude`, keyed to compose verbs) remain separate: the operator may legitimately want `n` to open a shell and compose verbs to open `claude`.

---

### Pattern 4: OpenBoard Intent and Adapter Arm

**What:** One new `HostIntent` variant covers "open a new tab." The adapter arm calls the appropriate Zellij shim (to be verified against vendored source before implementation — see Gap below).

**New variant:**

```rust
// intent.rs
/// Open a new board (tab). Lines spawned on that board run `command`
/// (empty = default shell). Core emits this before any OpenLine intents
/// that target the new board; adapter dispatches sequentially.
OpenBoard {
    command: Vec<String>,
}
```

**Adapter arm (sketch — verify shim name before coding):**

```rust
HostIntent::OpenBoard { command } => {
    // new_tab_with_layout / open_tab / new_tab — verify from vendored source
    // before writing this arm.  The permission OpenTerminalsOrPlugins covers
    // tab creation (verify that assumption too).
    new_tab();  // placeholder — see Gap: OpenBoard shim
}
```

**Intent ordering for "spawn a board then put N lines on it":** the core emits `OpenBoard` first, then N `OpenLine` intents. The adapter's sequential dispatch loop fires the shim calls in that order. Zellij processes plugin commands FIFO (empirically verified for the SwapPanes 3-call sequence, documented in `zellij-api-notes.md`). The new board will be the active tab by the time the `OpenLine` calls execute, so the lines will open on it.

---

## Data Flow

### Compose Key Flow

```
Operator presses compose verb key (e.g. 'N' for new line, 'B' for new board)
    ↓
exchange.key(KeyInput::Char('N'))
    compose is None, prompt is None → falls to match arm
    → self.compose = Some(Compose { verb: AddLine, count: None })
    → return vec![]   (no intents yet; UI renders "mid-bind" indicator)
    ↓
Operator presses digit '3'
    ↓
exchange.key(KeyInput::Char('3'))
    compose is Some → route to compose_key()
    → compose.take(), match KeyInput::Char('3') with is_ascii_digit
    → execute_compose(AddLine, 3)
    → return vec![OpenLine{…}, OpenLine{…}, OpenLine{…}]
    ↓
adapter.dispatch(intents)
    → for each OpenLine: open_command_pane("claude", …)
    ↓
Zellij fires PaneUpdate (asynchronously, next event cycle)
    ↓
exchange.ingest_panes(…) — new lines appear, deck assigns them keys, log records opens
```

### Async Board + Line Reconciliation

The core does NOT need "pending board" state. Here is why and how:

1. `execute_compose(AddBoard, N)` emits N `OpenBoard` intents (one per board).
2. If the operator also wants lines on those boards, they compose separately for lines after the boards appear in the next `TabUpdate` / `PaneUpdate` cycle.
3. The "spawn a board then put N lines on it" as a single atomic action is out of scope for v0.2 (the design note in `v0.2-composing-the-exchange.md` specifies "bare verb = 1; verb + digit = N" — both target the current board for lines). Line-targeting is on the current board; board-creation is its own verb.

This means the async problem is simpler than it first appears: there is no "open board, then open lines on it" in a single gesture. The operator opens boards, Zellij updates `ingest_boards()`, the plugin renders the new board count, then the operator opens lines (which land on whatever tab is active at the time). State in the core (`boards: Vec<BoardSnapshot>`) is updated by `TabUpdate` exactly as it is today.

If a future phase adds "spawn a board with N lines in one command," the cleanest mechanism is a `OpenBoardWithLines { count: usize, command: Vec<String> }` intent and a single adapter arm that (a) opens the tab, then (b) in the *next* event tick (via `set_timeout(0.0)` deferred intent queue or by emitting a follow-up intent on the next `TabUpdate`) opens the lines. That is a deliberate non-scope for v0.2: do not implement speculative async tracking now.

---

## Key Binding Assignment

The compose verb keys are deliberately left to the plan-phase author (noted as deferred in the design note). The architecture supports any `KeyInput::Char(c)` not currently consumed by the main match. Existing taken chars: deck keys (digits + `qwertyuiopasdfghjklzxcvbnm` subset), `m`, `s`, `i`, `a`, `p`, `R`, `o`. Reasonable candidates: `N` (capital, shift-modified) for new line, `B` for new board — but these are naming/UX decisions, not architectural ones. The `key_input()` function in `main.rs` already passes through Shift-modified chars (line 211: `is_empty() && !(len==1 && contains(Shift))`), so capital letters work without KeyInput changes.

---

## Integration Points

### Modified Files (v0.2)

| File | Change | Nature |
|------|--------|--------|
| `crates/switchtail-core/src/exchange.rs` | Add `compose: Option<Compose>` field; `agent_command: Vec<String>` field; `compose_key()` method; `execute_compose()` method; verb key arms in `key()` | **Modified** |
| `crates/switchtail-core/src/intent.rs` | Add `OpenBoard { command: Vec<String> }` variant | **Modified** |
| `crates/switchtail-plugin/src/main.rs` | Add `OpenBoard` dispatch arm; add `agent_command` config key in `load()` | **Modified** |

### New Types (v0.2, in exchange.rs or a new compose.rs)

| Type | Location | Purpose |
|------|----------|---------|
| `Compose` struct | `exchange.rs` or `compose.rs` | Mid-bind sub-state |
| `ComposeVerb` enum | same file | Verb discriminant |

These can live in `exchange.rs` alongside `Prompt` (the exact same structural role) or be extracted to `compose.rs` if the file grows. Inline first; extract if warranted.

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| core `key()` → compose sub-state | `self.compose: Option<Compose>` field on Exchange | Identical seam to `self.prompt: Option<Prompt>` |
| core → adapter | `Vec<HostIntent>` returned from `key()` | Unchanged seam; new variants added |
| adapter `load()` → core | `exchange.agent_command = …` | Identical to existing `exchange.line_command = …` |
| `OpenBoard` shim | `new_tab()` or equivalent | **Must verify from vendored zellij-tile source before coding** |

---

## Anti-Patterns

### Anti-Pattern 1: Putting Count Logic or Default-Command Resolution in the Adapter

**What people do:** The adapter sees a "spawn N" intent with a count field, loops N times calling `open_command_pane`, and fills in `"claude"` as the command string.

**Why it's wrong:** The adapter becomes a logic layer. The architecture invariant states "No business logic in the adapter." Count resolution and command defaulting are business decisions testable in pure Rust — they should be in core where they can be unit-tested without Zellij.

**Do this instead:** Core's `execute_compose()` does the loop and fills the command; the adapter sees N flat `OpenLine` intents with fully resolved commands.

---

### Anti-Pattern 2: A Batched Spawn Intent (e.g. `SpawnLines { count, command }`)

**What people do:** Add `HostIntent::SpawnLines { count: usize, command: Vec<String> }` and have the adapter loop internally.

**Why it's wrong:** Pushing the fan-out into the adapter breaks the one-intent-one-effect discipline. Now the adapter contains iteration logic. It is harder to test (requires a mock Zellij shim to count calls). The existing `Vec<HostIntent>` return type already supports fan-out cleanly.

**Do this instead:** `execute_compose` returns `count` copies of `OpenLine`. The adapter's existing `for intent in intents` loop handles this with zero new code.

---

### Anti-Pattern 3: Tracking "Pending Board" State Across Async Gaps

**What people do:** After emitting `OpenBoard`, the core sets `pending_board: true` and waits for a `TabUpdate` to emit follow-up `OpenLine` intents.

**Why it's wrong:** It introduces hidden cross-event state that complicates testing (tests must simulate two event cycles) and creates race conditions if multiple boards are opened. The v0.2 design does not require single-gesture "board + lines" composition.

**Do this instead:** Board creation and line creation are separate operator gestures, each a compose verb. The async `TabUpdate` naturally updates `self.boards` and the operator composes lines afterward. No pending state needed.

---

### Anti-Pattern 4: Accumulating Multi-Digit Counts in v0.2

**What people do:** Allow "12" (two keypresses of '1' then '2') to mean count=12, requiring `Compose.count` to accumulate digits and terminate on a non-digit.

**Why it's wrong for v0.2:** Adds state complexity (when does accumulation end?), makes the UX less predictable (operator can't tell if a digit will be treated as a count or as a deck key), and the design note specifies "verb + count → N" as a two-press bind. Single-digit (1–9) satisfies the "one pane or a hundred" feel up to 9 per compose; operator presses the verb again for more.

**Do this instead:** Single digit terminates immediately. Defer multi-digit to a later phase if the 1–9 ceiling proves insufficient in practice.

---

## Build Order (Incremental, Pure-Core-Testable)

### Slice 1 — Bare Verb: Add One Line (no count yet)

**Goal:** `exchange.key(verb_key)` immediately emits one `OpenLine { command: agent_command }` with no sub-state entered. Equivalent to the existing `'n'` key but using `agent_command` instead of `line_command`.

**Changes:**
- Add `agent_command: Vec<String>` field to `Exchange`, default `vec!["claude".into()]`.
- Add `agent_command` config key in `load()`.
- Pick a compose verb key (e.g. `'N'`) and add it to `key()` match: emit one `OpenLine`.
- Unit tests: key emits `OpenLine` with resolved command; config override works.

**No `Compose` struct needed yet.** This slice ships the default-agent capability and proves the field + config key pattern.

---

### Slice 2 — Add One Board

**Goal:** `exchange.key(board_key)` emits one `OpenBoard { command: agent_command }`. Adapter arm opens a new tab.

**Changes:**
- Add `HostIntent::OpenBoard { command: Vec<String> }` to `intent.rs`.
- Pick a board verb key (e.g. `'B'`) and add it to `key()` match.
- **Verify the tab-creation shim** from vendored `zellij-tile-0.44.3` source before writing the adapter arm. `OpenTerminalsOrPlugins` already declared — confirm it covers tab creation.
- Unit tests: key emits `OpenBoard`; adapter arm compiles against real shim.

**This slice is intentionally isolated.** Do not couple board creation with line targeting yet.

---

### Slice 3 — Compose Sub-State: Verb + Count

**Goal:** Pressing the verb key enters the `Compose` sub-state; pressing a digit 1–9 executes with that count; pressing Esc cancels; pressing any other key executes with count=1 and re-routes the key.

**Changes:**
- Add `Compose` struct and `ComposeVerb` enum (alongside `Prompt` in `exchange.rs`).
- Add `compose: Option<Compose>` field to `Exchange`.
- Replace the direct-emit arms from Slices 1 and 2 with arms that set `self.compose = Some(Compose { verb, count: None })`.
- Add `compose_key()` and `execute_compose()` methods.
- Update `key()` to gate on `self.compose.is_some()` first.
- Unit tests: entering compose, cancelling with Esc, digit-count fan-out (3 intents for '3'), non-digit pass-through with count=1.

**Pure core tests cover all paths.** No Zellij needed; the test from Slice 1 that asserted a bare key emits one intent is now updated to assert "bare key then immediate digit emits N intents."

---

### Slice 4 — UI Indicator for Mid-Bind State (adapter/render)

**Goal:** When `compose.is_some()`, the render layer shows a one-line indicator ("add line — enter count or act (Esc to cancel)"). Not business logic; a view concern.

**Changes:** `view/render` reads `exchange.compose` and shows the mode label. No new intents. No core logic change.

---

## Open Questions / Gaps

| Gap | Risk | How to Resolve Before Coding |
|-----|------|------------------------------|
| **OpenBoard shim name** — the exact function to open a new tab in `zellij-tile 0.44.3` is not in `zellij-api-notes.md`. `new_tab()` exists in some versions but its signature is unverified. | HIGH — wrong shim causes WASM compile failure | Read vendored source: `~/.cargo/registry/src/*/zellij-tile-0.44.3/src/shim.rs` or equivalent. Search for `fn new_tab` / `fn open_tab`. Verify `OpenTerminalsOrPlugins` covers it. |
| **`agent_command` config key naming** — `line_command` is the v0.1 precedent; `agent_command` follows it naturally. Confirm no collision with future features. | LOW | Naming decision; no code risk. |
| **Count > 9** — single-digit ceiling means max 9 per compose gesture. | LOW for v0.2 | Defer; operator can compose again. |
| **Lines on a specific board** — v0.2 lines always go to the currently active tab. Board-targeted line spawn (e.g. "N lines on board 2") is not designed. | OUT OF SCOPE for v0.2 | Document explicitly so no one tries to solve it during this milestone. |

---

## Sources

- `crates/switchtail-core/src/exchange.rs` — `Prompt` / `prompt_key()` analog (lines 49–53, 198–202, 313–345); `key()` dispatch table (lines 198–311); `line_command` pattern (lines 70, 304–307)
- `crates/switchtail-core/src/intent.rs` — existing `HostIntent` variants and composition rationale (all)
- `crates/switchtail-plugin/src/main.rs` — adapter dispatcher (lines 113–181); `line_command` config loading (lines 22–24); `OpenLine` arm (lines 161–170)
- `crates/switchtail-core/src/key.rs` — `KeyInput` vocabulary (all)
- `docs/zellij-api-notes.md` — FIFO dispatch order verified for 3-call SwapPanes; `OpenTerminalsOrPlugins` permission; vendored-source verification method
- `.planning/notes/v0.2-composing-the-exchange.md` — design decisions (compose is pure core; cwd out of scope; single-gesture live feel)
- `.planning/PROJECT.md` — key decisions table confirming `HostIntent` seam contract and no-kill discipline

---
*Architecture research for: SwitchTail v0.2 live composition*
*Researched: 2026-06-13*
