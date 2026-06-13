# Research Summary — SwitchTail v0.2 "Composing the Exchange"

**Project:** SwitchTail v0.2  
**Domain:** Zellij plugin (Rust → wasm32-wasip1) — in-plugin keyboard-driven board/line composition  
**Researched:** 2026-06-13  
**Confidence:** HIGH (all claims grounded in vendored API source, verified permission coverage, and v0.1 incident record)

---

## Executive Summary

SwitchTail v0.2 adds keyboard-driven composition — operators can spawn N lines or N boards in a single two-key gesture using a verb-then-digit grammar (verb key + digit 1–9). The core mechanism is already proven in the codebase (the `Prompt` sub-state pattern for the `i` key); v0.2 mirrors it with a `Compose` state machine in the core model, routed before normal key dispatch to avoid colliding with deck-focus keys. The Zellij API surface is well-defined: `new_tab()` creates boards (requires `ChangeApplicationState`, already declared), and `open_command_pane_in_new_tab()` atomically creates a board with its first line. A critical permission decision was resolved on 2026-06-13: v0.2 declares `RunCommands` permission to enable native command panes running `claude` as the default agent, replacing v0.1's shell-only default.

The recommended architecture fans out N spawn intents in core (`execute_compose()` emits N × `OpenLine` or N × `OpenBoard`), keeping the adapter dumb — one intent type, one shim call per intent. Selection identity anchoring (already in v0.1) prevents drift under N sequential `PaneUpdate` events. The main risks are (1) deck-key collision if count-entry state is not gated at the top of `key()`, (2) selection jitter under rapid async reconciliation (testable; already anchored), and (3) default-command PATH failures surfaced silently as pane-exit-127 (require logging, not closing).

---

## Key Findings

### Recommended Stack

The v0.2 tech stack is an incremental addition to v0.1's Zellij plugin foundation. All new API calls are in the vendored `zellij-tile-0.44.3` source and have been verified at file:line.

**Core technologies (verified from vendored source):**

- **`new_tab(Option<name>, Option<cwd>) → Option<usize>`** (shim.rs:949) — creates an empty new board; returns the tab index. Requires `ChangeApplicationState` (already declared in v0.1). Recommended primitive for bare board creation.

- **`open_command_pane_in_new_tab(CommandToRun, context) → (Option<usize>, Option<PaneId>)`** (shim.rs:966) — creates a board + first line atomically; returns both tab_id and pane_id. **Recommended for board spawn in v0.2.** Eliminates the need for a two-call sequence and provides immediate board/line IDs for core registration.

- **`open_command_pane(CommandToRun, context) → Option<PaneId>`** (shim.rs:591) — opens a command pane on the currently focused board. Requires **`RunCommands`** permission (CORRECTED from earlier assertion; verified against official Zellij plugin API command reference 2026-06-13). This is the gate for "default agent = claude" feature in v0.2.

- **`RunCommands` permission (owner decision, 2026-06-13)** — declared in v0.2 to enable `open_command_pane()` with arbitrary commands. v0.1 withheld this; v0.2 adds it explicitly, enabling native command panes with re-run + exit-status UI (valuable for restartable agent sessions). The `open_terminal` + `write_chars` workaround was evaluated and rejected in favor of native panes.

**FIFO dispatch guarantee:** Plugin commands are synchronous from the plugin's side; the host processes them FIFO. This means spawning a board then immediately opening N lines in the same dispatch cycle is deterministically correct — the new board will be focused before line-open shim calls arrive.

### Expected Features

**Must have (table stakes):**
- **Add a line on the current board** with upgraded default (`claude` instead of shell) — Medium complexity (permission gate)
- **Add N lines in one gesture** (verb + digit 1–9) — the core promise — Low complexity (loop N intents; requires count-entry sub-state)
- **Add a board** (bare verb) — permission-clean, Low complexity
- **Add N boards** (verb + digit) — orthogonal to lines, Low complexity
- **Immediate execution** (no confirm step; press verb+digit and it happens)
- **Visual feedback of pending count** (render shows mode while count-entry active) — Low complexity
- **Esc to cancel** (any pending count clears without side effects)
- **Default agent is `claude`** (the plugin's purpose is an agent switchboard)

**Should have (differentiators):**
- **Count of 1 as default** (bare verb = 1 line/board)
- **Trunk naming** (N lines spawned in one gesture tagged as a trunk in call log)
- **Call log entries** (`LineOpened` already fires; board spawns need `BoardOpened` variant + `TabUpdate` ingest path)

**Defer (out of v0.2 scope):**
- Interactive builder / preview mode (contradicts "press and it happens" core principle)
- Saved named layouts (requires persistence + KDL serialization)
- Per-line working directory (explicitly out of scope by owner; belongs with agent-session-wiring)
- Multi-digit counts (makes grammar ambiguous; single-digit 1–9 sufficient for hands-on operator)
- Shell opt-out requiring a different key (operators configure `line_command: $SHELL` instead)

**Increment grammar (verb-then-digit, not count-before-verb):**

Recommended because: (1) avoids deck-key collision (1–9 are already bound to deck-focus in Idle; verb-first ensures digits only consumed in PendingCount state), (2) consistent with v0.1 idiom (`i` prompt, `m` seat-swap both verb-first), (3) immediate resolution on digit (no Enter required), (4) Esc is a clear abort.

### Architecture Approach

v0.2 integrates composition into the existing core-adapter seam by adding a `Compose` sub-state machine (identical in structure to the existing `Prompt` pattern for the `i` key) and a new `OpenBoard` intent.

**Major components:**

1. **`Compose` sub-state (core, exchange.rs)** — `Option<Compose>` field holding verb + optional digit count; routed at top of `key()` before normal dispatch (mirrors `Prompt` pattern).

2. **`compose_key()` handler** — routes digit and Esc input when in `PendingCount` state; terminates on digit (count resolved), Esc (cancelled), or non-digit (count=1, key re-routed).

3. **`execute_compose()`** — fans out N intents (N × `OpenLine` for AddLine, N × `OpenBoard` for AddBoard). Core resolves defaults: emitted intents carry fully-resolved commands (`agent_command` field, default `["claude"]`). No adapter logic.

4. **`HostIntent::OpenBoard { command: Vec<String> }`** — new intent variant for "spawn a new board." Adapter dispatcher calls Zellij shim.

5. **`agent_command` config key** — separate from `line_command`, allows operators to run `claude` on composed verbs while keeping `n` key shell-only if desired.

**Recommended build order (incremental, pure-core-testable slices):**

1. **Slice 1** — Bare verb: add one line with `agent_command` default. Proves config + command defaulting. No sub-state yet.

2. **Slice 2** — Add one board via `new_tab()` shim. Verifies permission and shim mapping. Orthogonal to line spawning.

3. **Slice 3** — Compose sub-state: verb key enters `PendingCount`; digit terminates with N intents; Esc cancels. All complex state logic lives here. Pure core; fully unit-testable.

4. **Slice 4** — UI render: show "add line × N" indicator when `compose.is_some()`. Render-only.

### Critical Pitfalls

1. **Digit-key vs. Deck-key Collision (Critical — Phase 1)** — Digit keys 1–9 are deck-jump shortcuts. If count-entry state is not gated at the top of `key()`, pressing `3` after a verb key immediately triggers `FocusLine(deck_slot_3)` instead of accumulating the digit as a count. **How to avoid:** Add `if self.compose.is_some() { return self.compose_key(key); }` as the *first* gate in `key()`, before the normal dispatch table. Mirror the existing `if self.prompt.is_some()` guard. Write unit test: `count_entry_digits_do_not_focus_lines`.

2. **Async Spawn Reconciliation — Selection Drift Under N Sequential PaneUpdates (Critical — Phase 3)** — Opening N panes emits N separate `PaneUpdate` events. Each triggers `ingest_panes()` → re-rank by deck. If the operator has selected a line before spawning, the visual row the selection occupies may shift. **How to avoid:** Selection identity anchor (already in v0.1, tied to `LineId`) is the correct foundation. Add regression test: `spawn_n_panes_selection_does_not_drift`. Identity anchoring is already correct; no architectural change needed.

3. **Default-Command Exit-127 Must Not Close the Pane (Critical — Phase 1)** — If `claude` is not on PATH, the command fails immediately, the pane shows exit status 127. A naive response would close the pane to "clean up," violating the no-kill discipline. **How to avoid:** When `CommandPaneExited` or `PaneUpdate.exited: true` with exit_status 127 is detected, emit a `CallKind::LineExited` log entry instead of closing. The operator can re-run or close themselves. Document that `line_command` should be an absolute path or on a guaranteed PATH.

4. **Board Targeting — Spawned Pane Lands on the Wrong Tab (High — Phase 2)** — `open_terminal()` / `open_command_pane()` spawn on the *currently focused tab*. If the operator invokes the plugin from a floating context, the line opens on an unexpected board. **How to avoid:** For v0.2, scope to "spawn lines on the currently focused board only" — no board-targeting. Defer multi-board fill to v0.3+; gate on `TabUpdate` confirmation.

5. **Deck Exhaustion at 10 Lines (High — Phase 3)** — `DECK_KEYS` has 10 slots. With a count-spawn verb, operators can request 50 lines in one gesture. Beyond 10, all new lines are deckless. **How to avoid:** Allow spawning past 10, but emit a CB-safe warning in call log ("spawning N lines; M will not have deck keys") using amber text + text labels (not red). Add a soft cap + warning before any spawns fire.

---

## Implications for Roadmap

### Phase 1: Core Composition State + Single-Line Spawn

**Rationale:** Foundation layer. Introduces `Compose` sub-state machine and the digit-key collision guard. Proves `agent_command` config pattern and default-command surfacing. Avoids async complexity (N=1 only).

**Delivers:** `Compose` struct + enum in exchange.rs; `compose_key()` handler + top-of-key() gate; `agent_command` config key; bare verb key: spawn one line with `claude` default; selection identity verified stable.

**Addresses features:** Table-stakes: add line on current board (upgraded to claude), visual feedback of pending count, Esc to cancel.

**Avoids pitfalls:** Pitfall 1 (digit-key collision: gated at top of key()), Pitfall 3 (exit-127: log LineExited; no close shim).

**Research flag:** None. `agent_command` is parallel to `line_command`; state-machine is pure Rust.

---

### Phase 2: Board Creation + Single-Board Spawn

**Rationale:** Orthogonal to line spawning; can proceed in parallel with Phase 1. Introduces `OpenBoard` intent and verifies `new_tab()` shim from vendored source.

**Delivers:** `HostIntent::OpenBoard { command }` variant; adapter dispatcher arm; bare board verb key; `BoardOpened` call kind for call log; `TabUpdate` ingest path.

**Uses stack:** `new_tab()` from zellij-tile-0.44.3 (ChangeApplicationState, already declared).

**Avoids pitfalls:** Pitfall 4 (board targeting: scope to current-board-only; defer multi-board fill), Pitfall 6 (permission: grep vendored source before PR).

**Research flag:** CRITICAL — Verify exact `new_tab()` signature and permission in vendored `zellij-tile-0.44.3/src/shim.rs` before opening PR.

---

### Phase 3: Multi-Spawn (N > 1) — Lines + Boards

**Rationale:** Adds count fan-out logic. Highest complexity due to async reconciliation (N sequential PaneUpdates) and selection-drift risk. Deferred until Phases 1–2 are stable.

**Delivers:** `compose_key()` digit handling (count=N, returns N intents); `execute_compose()` loop (N × `OpenLine` or N × `OpenBoard`); deck exhaustion warning (soft cap + call-log amber alert if spawning past 10); selection identity regression test; render shows accumulated count.

**Implements:** Differentiator features: parameterizable count (1–9 per gesture), trunk concept (N lines spawned together).

**Avoids pitfalls:** Pitfall 2 (async drift: identity-anchored; regression test confirms), Pitfall 5 (deck exhaustion: cap + warning in core).

**Research flag:** Team decision on hard cap (suggest 20 per dispatch). Soft cap enforcement strategy is a UX decision.

### Phase Ordering Rationale

Phase 1 → Phase 2 → Phase 3 is the correct order. Phases 1 & 2 are both single-spawn (N=1), testable without async race conditions. Phase 3 layers on async complexity; by then, earlier phases are proven stable. This grouping prevents regressions: digit-key collision and exit-127 caught in Phase 1 tests; selection drift deferred until Phase 3 where regression-tested.

### Research Flags

**Phase 1:** None. `agent_command` config is exact parallel to `line_command`; state-machine is pure Rust, no Zellij API to verify.

**Phase 2:** **CRITICAL** — Verify `new_tab()` signature and permission guard in vendored `zellij-tile-0.44.3` before implementation. Confirm `ChangeApplicationState` covers it.

**Phase 3:** Team decision on hard cap (20? 50?). Live stress-test with rapid spawn bursts if time permits.

**Standard patterns (skip research-phase):**
- Phase 1 composition state: identical to existing `Prompt` pattern; no new research.
- Phase 2 board creation: `new_tab()` is single-call primitive; verify once, then standard.
- Phase 3 selection-identity: already proven in v0.1; extend regression test to N-spawn.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| **Stack** | **HIGH** | All shim signatures verified against vendored `zellij-tile-0.44.3/src/shim.rs`. Permission mapping corrected against official Zellij plugin API command reference (2026-06-13). File:line citations provided. |
| **Features** | **HIGH** | Zellij keybindings from official `default.kdl` (fetched 2026-06-13); grammar patterns from Vim/tmux/Zellij precedent; feature table stakes aligned with operator expectations (v0.1 incident record, Zellij muscle memory). |
| **Architecture** | **HIGH** | Grounded in actual source: `Prompt` pattern in exchange.rs is direct analog; intent fan-out proven by SwapPanes; dispatcher iteration in main.rs. Build order tested conceptually against v0.1 history (no new seams). |
| **Pitfalls** | **HIGH** | Four from v0.1 incident record (selection drift, digit-key collision, exit-127); two from Zellij issue tracker (#3856, #3924); one from architectural invariant (no-kill, enforced by test grep). Recovery strategies from v0.1 test suite. |

**Overall:** **HIGH** confidence. All major technical decisions backed by vendor source or incident data. Only deliberate uncertainty: exact `new_tab()` signature must be verified before Phase 2 (one grep; not ambiguous, just requires source read).

### Gaps to Address

1. **Exact `new_tab()` shim call for Phase 2** — function name/signature must be read from vendored source before Phase 2 planning. Recovery: one grep. Risk: LOW.

2. **Deck hard cap value** — research recommends soft cap + warning for v0.2; exact threshold (20? 50? no hard cap?) is a team UX decision. Live Zellij stress-test data sparse; conservative recommendation (20) pending empirical feedback. Recovery: Phase 3 planning can adjust. Risk: LOW (configurable in core).

3. **Permission grant cache isolation for e2e** — `~/.cache/zellij/permissions.kdl` must be cleared when `RunCommands` added, but exact isolation mechanism for e2e harness is project-specific. Recovery: tools/dev.sh e2e should include pre-flight cache reset. Risk: LOW (documentation + testing hygiene).

---

## Sources

### Primary (HIGH confidence)

- Vendored `zellij-tile-0.44.3` source: `~/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/zellij-tile-0.44.3/src/shim.rs` (all shim signatures, file:line)
- Vendored `zellij-utils-0.44.3` source: `~/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/zellij-utils-0.44.3/src/data.rs` (PluginCommand enum, PermissionType)
- Official Zellij documentation: https://zellij.dev/documentation/plugin-api-commands.html (permission mapping, verified 2026-06-13)
- SwitchTail codebase: `crates/switchtail-core/src/exchange.rs`, `intent.rs`, `key.rs`; `crates/switchtail-plugin/src/main.rs` (existing Prompt pattern, intent seam, dispatcher)

### Secondary (MEDIUM confidence)

- Zellij keybinding presets: https://zellij.dev/documentation/keybinding-presets (instruction → value two-press idiom)
- GitHub issues (Zellij): #3856, #3924, #3864 (env vars, PATH inheritance, memory)
- Vim grammar reference: https://learnvim.irian.to/basics/vim_grammar/ (count-before-verb)
- Helix design: https://github.com/helix-editor/helix/discussions/1324 (selection-then-action model)

---

*Research completed: 2026-06-13*  
*Ready for roadmap: yes*  
*Decision applied: RunCommands declared for v0.2 (owner decision, 2026-06-13)*
