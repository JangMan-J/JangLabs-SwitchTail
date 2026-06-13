# Feature Research

**Domain:** In-plugin keyboard-driven layout composition for a Zellij terminal multiplexer plugin (telephony vocabulary: board/line/exchange)
**Researched:** 2026-06-13
**Confidence:** HIGH (Zellij keybindings from official default.kdl; API permissions from vendored zellij-tile-0.44.3 source; grammar patterns from well-documented Vim/Helix/tmux precedents)

---

## Zellij's Own Interactive Board/Line Creation — What Muscle Memory Operators Bring

Understanding this is prerequisite to designing SwitchTail's compose keys, because a Zellij user's fingers already know these patterns.

### Zellij's mode-entry model (the "default" preset)

Zellij separates key contexts using **input modes**. The operator presses a chord to enter a mode; all subsequent keys are consumed by that mode until Esc/Enter returns to Normal. The status bar updates to show mode-specific options, giving constant visual feedback of the current mode.

Key mode-entry chords in Normal:
- `Ctrl p` — enter **Pane mode** (manage lines/panes)
- `Ctrl t` — enter **Tab mode** (manage boards/tabs)
- `Alt n` — **quick new pane** without entering Pane mode

**Pane mode** keybindings (after `Ctrl p`):
| Key | Action |
|-----|--------|
| `n` | New pane (splits the focused area) |
| `d` | New pane below (split down) |
| `r` | New pane to the right (split right) |
| `s` | New stacked pane |
| `x` | Close focused pane |
| `f` | Toggle fullscreen |
| `h/j/k/l` + arrows | Move focus directionally |
| `p` | Cycle focus |
| `Ctrl p` / Esc | Return to Normal |

**Tab mode** keybindings (after `Ctrl t`):
| Key | Action |
|-----|--------|
| `n` | New tab |
| `x` | Close current tab |
| `r` | Rename tab |
| `1`–`9` | Jump directly to tab by index |
| `h/k` or Left/Up | Previous tab |
| `l/j` or Right/Down | Next tab |
| `b` | Break focused pane into new tab |
| `s` | Toggle tab sync |
| `Ctrl t` / Esc | Return to Normal |

**There is no count/quantifier idiom in Zellij's default keybindings.** Every action spawns exactly one pane or one tab. There is no `3n` to open three panes, no numeric prefix that multiplies an action. This is a gap SwitchTail's compose verbs will fill — and because Zellij itself has never trained operators to expect counts, SwitchTail's grammar is additive, not contradictory.

### The Unlock-First preset (alternative keybinding scheme)

Some Zellij users run the Unlock-First preset where a "lock" chord (`Ctrl g`) must be pressed first to unlock the interface. In that preset, opening a new pane requires `Ctrl g` → `p` → `n` — a three-press chain. Operators on this preset are already fluent with multi-press sequences and will find SwitchTail's verb+count idiom familiar.

### What muscle memory operators bring to SwitchTail's compose keys

- Operators expect `n` to be "new something" — SwitchTail's `n` (new line, already wired in v0.1) is consistent.
- Operators expect a mode-like state change to be temporary and Esc-cancellable.
- Operators do NOT expect a numeric prefix to work (Zellij has no such idiom).
- Operators expect the action to be immediate — press and it happens, no commit step.
- The status bar is the canonical "what mode am I in / what can I press" surface.

---

## Feature Landscape

### Table Stakes (Operators Expect These)

Features a Zellij-native operator assumes any composition verb will have. Missing these makes the switchboard feel broken.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Add a line on the current board** | v0.1's `n` key already opens a shell line; upgrading it to spawn `claude` by default is the expected behavior for this tool's purpose | LOW | Already implemented as `HostIntent::OpenLine`; the default command value needs to change from `$SHELL` to `claude`. Permission gap: see Pitfall 1 below. |
| **Immediate execution (no confirm step)** | Zellij itself is press-and-it-happens; any "press Enter to confirm" step breaks flow | LOW | The v0.2 design note explicitly mandates this. The mid-bind count state must resolve immediately when the digit is pressed (for single-digit counts) or on a terminator key (if multi-digit is supported). |
| **Esc to cancel a pending count** | Any pending/mid-bind UI state must be clearable. Operators know Esc exits modes in Zellij. | LOW | The mid-bind count is a transient core state like the `i` prompt; Esc must drop it with no action taken. |
| **Visual feedback of pending count** | Once a count-entry state is entered, the operator must see what they have typed ("Pending: add 3 lines") before the action fires. Without feedback, the operator cannot confirm intent. | LOW | A status line in the plugin render is sufficient; the count-in-progress string is purely display. |
| **Add a board (new tab)** | If the operator can add a line, they expect to add a board. Composition without board-creation is half-capability. | LOW | `new_tab()` in zellij-tile-0.44.3 requires `ChangeApplicationState` — already declared in v0.1. Clean to implement. |
| **Default agent (`claude`) staffing spawned lines** | The tool's stated purpose is an agent switchboard. Spawning bare shells by default contradicts that. The default must be `claude`. | MEDIUM | **Critical permission gap**: `open_command_pane()` requires `RunCommands` — currently withheld. `open_terminal()` (OpenTerminalsOrPlugins, declared) opens a bare shell; it cannot exec an arbitrary command. Must resolve before any non-shell default is possible. See Pitfall 1. |
| **Count of 1 is the default (bare verb = 1)** | Operators expect a single keypress to do one thing. No prefix = 1 is the universal convention in all tools (vim: `j` = move 1; tmux: `new-window` = 1 window). | LOW | Trivially implemented as the default branch when no count is pending. |

### Differentiators (Composition Capabilities Beyond Zellij Native)

Features that make SwitchTail's compose surface meaningfully better than pressing `Ctrl t, n` three times.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Parameterizable count: verb then digit (N lines or N boards in one gesture)** | "One pane or a hundred depending which buttons you press" — the core promise of v0.2. No Zellij-native equivalent exists. Eliminates the tedium of repeating a compose verb N times. | MEDIUM | Grammar: verb (`L` for line, `B` for board) then digit key (`1`–`9`, possibly `0` for 10). Resolves immediately on digit press for single-digit counts. The core tracks a `ComposeState` enum: `Idle` / `PendingCount { verb: ComposeVerb }`. |
| **Trunk: N parallel lines in one gesture** | Spawning a trunk (N simultaneous lines for one purpose) is the natural evolution of the count-add-lines capability. Directly surfaces the `trunk` concept from the domain vocabulary. | LOW-MEDIUM | "Add N lines" IS a trunk. The trunk concept requires no additional mechanism beyond the count-add-line feature; it can be named and logged as such. |
| **Board + N lines in a single compound gesture** | Add a board AND immediately fill it with N lines — "compose a full board in two gestures." Eliminates the context-switch between board-adding and line-adding. | HIGH | Deferred: makes the count grammar ambiguous (whose count is it — the board or the lines?). Keep v0.2 to orthogonal verbs; a compound "add board with N lines" is v0.3+ territory. |
| **Call log entry for each compose action** | Every spawned line and board appears in the call log as a `LineOpened` / `BoardOpened` event. The operator can see the composition history. | LOW | `LineOpened` calls already emit on `PaneUpdate` ingest. Board opens need a `BoardOpened` call kind. |
| **Configurable default agent per line type** | The operator can set a non-default agent for specific boards or spawn targets without editing a config file, via the pipe protocol. | HIGH | Deferred to v0.3+. v0.2 uses the `line_command` config key (already exists). |

### Anti-Features (Keep Out of v0.2)

Features that seem like natural extensions but would bloat the milestone, create scope drift, or contradict the "small, working, shippable" mandate.

| Feature | Why Requested | Why It Belongs After v0.2 | What to Do Instead |
|---------|---------------|--------------------------|-------------------|
| **Interactive builder / preview mode** | "I want to see a layout before committing it" | Contradicts the core model ("press and it happens, no builder mode"). Introduces an uncommitted state machine that fights the live-composition feel. Adds 3–5x more UI surface. | Live, immediate composition. The call log IS the record. Undo is "close what you just opened" — a future `close_line` capability, not a preview. |
| **Saved named layouts** | "I want to reuse my standard 3-line board" | Requires a persistence mechanism (config file round-trip or a layout KDL string), layout naming, a picker UI, and a new permission surface. v0.2 has no persistence layer yet. | `new_tabs_with_layout()` in the Zellij API (ChangeApplicationState) supports layout strings — this is the correct hook when layouts are added, but it's a later milestone. |
| **Per-line working directory (cwd)** | "I want each line to start in a specific project dir" | Explicitly out of scope by owner directive. The cwd concern is separable and likely rides with agent-session-wiring (a later seed). Mixing it into v0.2 forces cwd selection UI before the basic compose verbs are stable. | Boot lines wherever the plugin's cwd is. Add cwd selection in a dedicated later phase. |
| **Multi-digit count entry (e.g., "add 12 lines")** | "What if I want more than 9?" | Makes the grammar ambiguous: is `1`, `2` a 12 or two separate key events? Requires a terminator key (Enter), which breaks the "no commit step" feel. Counts >9 are rare in practice for a hands-on operator. | Single-digit count (1–9, plus optionally 0 → 10). A count of 9 lines covers the deck (deck keys go up to 9 on the home row); 10 covers the full first slot range. If more are needed, press the verb again. |
| **Named board / line from the compose verb** | "I want to name the board I'm creating" | Requires a text-input prompt (like the `i` patch-through prompt). It interrupts the flow and conflicts with immediate execution. Board renaming already exists in Zellij (Tab mode → r). | Let Zellij's own renaming handle it. The board/line gets an auto-name; the operator can rename via Zellij's native keybindings. |
| **Floating line spawn** | "Open the new line as a floating pane" | Adds an option dimension to every compose verb (tiled vs floating). Operators don't use floating panes as primary work surfaces; they're one-shot overlays. | Tiled only for v0.2. Floating is a future opt-in if demand arises. |
| **Shell as opt-out requiring a different key** | "Sometimes I want a bare shell, not claude" | In v0.2, the default is `claude`. A "shell" variant adds a second compose verb or a modifier, doubling the key surface. The operator can always open a shell via Zellij's native `Ctrl p, n` outside the plugin. | Configure `line_command` to `$SHELL` in the plugin config to revert to v0.1 behavior. A per-spawn shell opt-out is a v0.3+ concern. |

---

## Increment Grammar Analysis

### The three established idioms

**Vim: count-before-verb** (`{count}{verb}` → `3dd`, `5j`)
- Count is typed first; the verb fires on the action key.
- Zero starts a count (but `0` as a motion means "beginning of line" — ambiguous in Vim itself).
- Operator-pending mode: after `d`, the editor waits for a motion. The count can appear before the verb, between the verb and motion, or both (`2d3w` = delete 6 words).
- **Cognitive model**: "I know how many, then I act." Good for text editing where the quantity is planned before execution.
- **In a TUI plugin context**: the digit appears before any mode change, so the plugin must intercept digit keys in the idle state and buffer them — conflicts with deck keys `1`–`9` which already mean "focus line 1–9." This is a hard collision in SwitchTail's current key map.

**Helix/Kakoune: select-then-act**
- Selection is the operand, action transforms the selection. Count applies to selection expansion (`3w` selects 3 words), then the action fires on what's selected.
- Not directly applicable to "spawn N things" because there's nothing to select before spawning.

**Zellij two-press bind / tmux: verb-then-value**
- Zellij's design doc describes the keybinding idiom as "instruction then value" for two-press binds. The mode itself is the verb; a subsequent key is the value.
- tmux `send-keys -N {count}` exists for scripting but is not an interactive user idiom; interactive tmux has no count prefix.
- **SwitchTail v0.1 already uses this idiom**: `i` (verb = open patch-through prompt) then typed text (value). The `i` key opens a `Prompt` state in the core that consumes subsequent input. This is the established pattern in the codebase.

### Recommended grammar for v0.2: **verb then digit**

```
verb key → enter ComposeState::PendingCount { verb }
digit key (1–9, 0→10) → resolve: emit N × intent; return to Idle
Esc in PendingCount → cancel; return to Idle
```

**Why verb-then-digit:**

1. **Consistent with SwitchTail's existing idiom** — the `i`-prompt and the seat-swap flow (`m` then `s`) both use verb-first two-press patterns. Operators of v0.1 already have this muscle memory.

2. **Avoids the deck-key collision** — digit keys `1`–`9` are already bound as deck focus shortcuts. If count-before-verb is used, the plugin cannot distinguish "focus line 1" from "begin a count of 1." With verb-first, the digit is only consumed in `PendingCount` state, never in `Idle`; deck keys remain unchanged.

3. **Consistent with Zellij's own "instruction → value" description** — operators who read Zellij docs will find this intuitive.

4. **Immediate resolution on the digit** — for single-digit counts (the only counts v0.2 supports), the operator presses two keys and the action fires. No Enter required. This preserves the "no commit step" feel.

5. **Esc is a clear abort** — the operator can always bail out without side effects.

**Concrete key proposal (to be finalized in planning, not fixed here):**

| Key press | In Idle state | In PendingCount state |
|-----------|--------------|----------------------|
| `L` | Enter PendingCount { verb: AddLine } | — |
| `B` | Enter PendingCount { verb: AddBoard } | — |
| `1`–`9` | Focus deck line (existing) | Spawn N × (line or board); return to Idle |
| `0` | Focus deck line for key `0` if assigned; else no-op | Spawn 10 × (line or board); return to Idle |
| `n` | Add 1 line (existing v0.1 behavior) | — |
| Esc | HideSelf (existing) | Cancel; return to Idle |

Note: `L` and `B` are NOT the only possible verb keys — those are examples. The planning phase must choose non-colliding keys. The grammar structure (verb → state → digit) is what this research recommends.

### Multi-digit count: do not implement in v0.2

Multi-digit counts (e.g., 12 or 100 lines) require:
- A digit buffer and a terminator key (Enter), which introduces a commit step — contradicting the design.
- Deciding whether `0` is "zero" (abort-worthy) or the second digit of "10" — ambiguous.
- Guarding against absurd counts (100+ panes crashes or hangs the Zellij session).

Single-digit counts (1–9, with 0→10 as an opt-in) cover all practical cases for a hands-on operator. Counts above 10 can be achieved by pressing the verb again.

---

## Edge Cases and Default Behaviors

### Count 0

**Recommendation: treat as no-op with a log entry.** "Add 0 lines" is meaningless; silently swallowing it could confuse ("did I press the wrong key?"). A call-log note "compose: count 0, no action" tells the operator what happened without disrupting the board.

Do NOT map 0 to 10 in the Idle state (that changes the semantics of the existing deck key `0`). If 0→10 is desired in PendingCount, it is a deliberate mapping that only applies in that state.

### Very large counts (operator presses, e.g., `L` then `9` = 9 lines)

Nine lines is the practical maximum that still fits on a standard board layout without panes becoming unusably small. The Deck runs out of default keys at ~26 (digits + home row); beyond that, new lines get no deck key.

**Recommendation: no cap in v0.2.** A count of 9 is the max the digit grammar allows (or 10 if 0→10). Both are safe. If multi-digit counts are ever added later, a cap of 20 with a call-log warning is appropriate.

### Spawning lines onto a board that has no remaining space

Zellij itself will split the pane further regardless of size. There is no API signal that "the board is full" — Zellij will just make panes very small. SwitchTail cannot easily detect this.

**Recommendation: emit all N `OpenLine` intents without checking. Log each one on open.** The operator can see the call log. If the board looks cramped, they break panes into new boards using Zellij's native `Ctrl t, b`. SwitchTail does not need to manage pane geometry.

### Spawning a board when no board is currently focused

`new_tab()` is not focus-dependent — it creates a new tab in the session regardless of what is currently focused. This is the correct behavior.

**Recommendation: always safe to call; no guard needed.** Zellij returns the new tab's index; SwitchTail logs a `BoardOpened` event.

### Spawning a line when no board exists (empty session)

Extremely unlikely — the plugin itself lives in a board (tab). If somehow the exchange has zero boards, `open_terminal()` / `open_command_pane()` will still create a pane in the current Zellij context. No special case needed.

### Default agent is `claude` but `claude` is not on PATH

`open_command_pane()` will produce a pane that shows a shell error ("command not found"). The line will appear in the directory as exited, ring the call log, and the operator will see the failure.

**Recommendation: no pre-check in SwitchTail.** Let the shell error surface in the pane. The operator can configure `line_command` to point to the correct binary or use an absolute path. PATH validation at spawn time requires `RunCommands`-level introspection — not worth the permission cost.

---

## Critical Permission Gap (Affects Default Agent Feature)

This is a blocker that the roadmap must plan around.

**The gap:** `open_command_pane()` (zellij-tile-0.44.3 shim, line 591) requires `RunCommands` permission. SwitchTail deliberately withholds `RunCommands`. Therefore, the `HostIntent::OpenLine { command: vec!["claude".into()] }` path currently calls `open_command_pane()` in the adapter — but this will silently fail or be rejected at runtime.

**v0.1's `n` key used `$SHELL`** (empty `line_command`), which takes the `open_terminal()` branch (OpenTerminalsOrPlugins, declared). No collision in v0.1. v0.2 changes the default to `claude`, which hits the `open_command_pane()` branch — and the permission wall.

**Options (for planning phase to decide):**

1. **Declare `RunCommands`** — the most direct path. Trade: expands the permission surface area beyond the minimal posture. Enables arbitrary command spawning. Owner must make this call explicitly (it is an owner decision, not a default).

2. **Use `open_terminal()` and then `write_chars_to_pane_id()` to type the command** — `open_terminal()` only needs `OpenTerminalsOrPlugins`. After opening a shell, the adapter writes `claude\r` into the pane via `WriteToStdin` (declared). The pane runs `claude` as if the operator typed it. Downside: the pane's command field will show the shell, not `claude`; the SwitchTail directory entry shows `$SHELL` rather than `claude`. The call log and rename can compensate. This preserves the minimal-permission posture.

3. **Use `new_tabs_with_layout()` with a layout string that embeds the command** — `ChangeApplicationState` (declared) covers `new_tabs_with_layout()`. A layout KDL string can specify a command. This works for board spawning but is awkward for single-line spawning and creates a layout-KDL dependency. Not recommended for v0.2.

**Research conclusion:** Option 2 (shell + write `claude\r`) is the permission-safe path for v0.2. It preserves the withheld-`RunCommands` posture. The planning phase must explicitly decide between Options 1 and 2; this is an owner decision.

---

## Feature Dependencies

```
ComposeState in core (PendingCount)
    └──required-by──> Add-line-with-count
    └──required-by──> Add-board-with-count

Add-line-with-count
    └──requires──> Permission resolution (RunCommands vs shell+write)
    └──enhances──> Trunk vocabulary (N parallel lines = a trunk)

Add-board
    └──requires──> ChangeApplicationState (already declared)
    └──no-dependency-on──> Add-line-with-count (orthogonal)

Call-log BoardOpened event
    └──requires──> Add-board feature

Visual feedback of pending count
    └──requires──> ComposeState in core
    └──required-by──> Good UX (without it the operator is blind during mid-bind)
```

### Dependency Notes

- **ComposeState required by both compose verbs:** The two-key state machine is the shared mechanism. It must be in core before either verb is implemented. This is one small enum + a match arm in `key()`.
- **Permission resolution blocks default-agent spawning:** No amount of compose-key design fixes the `RunCommands` gap. This must be resolved (or a workaround committed to) before the "default is claude" feature ships.
- **Add-board is independent of Add-line-with-count:** Board creation via `new_tab()` (ChangeApplicationState, declared) can ship in the same phase or even before line-count support. The permissions are already in place.

---

## MVP Definition for v0.2

### Launch With (v0.2 milestone)

- [ ] **ComposeState machine in core** — `Idle` / `PendingCount { verb }` enum; `key()` handles verb keys and digit resolution; Esc in PendingCount returns to Idle with no action. Fully unit-testable with no Zellij dependency.
- [ ] **Visual feedback of pending count** — render shows "compose: [verb] × [N]" or equivalent in CB-safe styling (no red/green) while in PendingCount.
- [ ] **Add line (bare verb = 1)** — upgrades the existing `n` key behavior to use `claude` as the default command; resolves the permission gap by owner decision.
- [ ] **Add N lines (verb + digit)** — emits N `OpenLine` intents in sequence; the core tracks nothing after resolution (stateless result).
- [ ] **Add board (bare verb = 1)** — new key calls `new_tab()`; logs `BoardOpened` to the call log.
- [ ] **Add N boards (verb + digit)** — same grammar, calls `new_tab()` N times.
- [ ] **Call log entries** — `LineOpened` already fires on PaneUpdate ingest; `BoardOpened` needs a new `CallKind` variant and a `TabUpdate` ingest path to detect new boards.

### Add After Validation (v0.2.x)

- [ ] **`0` → 10 in PendingCount** — if operators ask for counts > 9; trivial to add.
- [ ] **Trunk labeling** — when N lines are spawned in one gesture, tag them as a trunk in the call log and optionally in the line directory.

### Future Consideration (v0.3+)

- [ ] **Compound gesture: add board with N lines** — requires compound intent or a two-phase state machine.
- [ ] **Per-spawn cwd** — rides with agent-session-wiring milestone.
- [ ] **Saved layouts** — requires persistence mechanism; `new_tabs_with_layout()` is the right hook.
- [ ] **Shell opt-out key** — second compose verb that always spawns `$SHELL`.
- [ ] **Floating line spawn** — tiled-only for v0.2.

---

## Feature Prioritization Matrix

| Feature | Operator Value | Implementation Cost | Priority |
|---------|---------------|---------------------|----------|
| ComposeState machine in core | HIGH (foundation for everything) | LOW (small enum + match arm) | P1 |
| Visual feedback of pending count | HIGH (without it, mid-bind is invisible) | LOW (render string only) | P1 |
| Add line (bare verb, default `claude`) | HIGH (core v0.2 promise) | MEDIUM (permission decision required) | P1 |
| Add N lines (verb + digit) | HIGH (the key differentiator of v0.2) | LOW (loop N × OpenLine intents) | P1 |
| Add board (bare verb) | HIGH (composition without boards is incomplete) | LOW (new_tab(), perm already declared) | P1 |
| Add N boards (verb + digit) | MEDIUM (less common than line counts) | LOW (same grammar, same loop) | P2 |
| Call log BoardOpened event | MEDIUM (observability) | LOW (new CallKind + TabUpdate ingest) | P2 |
| Trunk labeling | LOW (vocabulary clarity only) | LOW | P3 |

---

## Comparator Analysis (Zellij vs tmux vs SwitchTail v0.2)

| Capability | Zellij native | tmux native | SwitchTail v0.2 |
|-----------|--------------|-------------|-----------------|
| Open 1 line | `Ctrl p, n` (2 keys) | `Prefix, "` or `Prefix, %` (2 keys) | `n` (1 key) or `L, 1` (2 keys) |
| Open N lines | Repeat N times | Repeat N times or script | `L, N` (2 keys) |
| Open 1 board | `Ctrl t, n` (2 keys) | `Prefix, c` (2 keys) | `B` or `B, 1` |
| Open N boards | Repeat N times | Repeat N times | `B, N` (2 keys) |
| Default command | `$SHELL` | `$SHELL` | `claude` (configurable) |
| Count grammar | None | None (scripting only) | verb → digit (SwitchTail invention) |
| Esc to cancel | Mode exit | Prefix timeout | Cancel PendingCount |

---

## Sources

- Zellij default keybindings: `https://raw.githubusercontent.com/zellij-org/zellij/main/zellij-utils/assets/config/default.kdl` (fetched 2026-06-13, confirmed tab mode and pane mode key tables; no count/quantifier bindings present)
- Zellij plugin API commands: `https://zellij.dev/documentation/plugin-api-commands.html` (fetched 2026-06-13; permission requirements for `open_command_pane`, `open_terminal`, `new_tab`, `new_tabs_with_layout`)
- Vendored zellij-tile-0.44.3 source: `/home/jangmanj/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/zellij-tile-0.44.3/src/shim.rs` (confirmed `open_command_pane` at line 591, `new_tab` at line 949, `open_terminal` at line 491)
- Zellij keybinding presets: `https://zellij.dev/documentation/keybinding-presets` (confirmed "instruction → value" two-press bind idiom description)
- Vim grammar reference: `https://learnvim.irian.to/basics/vim_grammar/` (count-before-verb pattern; operator-pending mode)
- Helix vs Vim model: `https://github.com/helix-editor/helix/discussions/1324` (selection-then-action model; context for why SwitchTail's verb-first grammar is preferable)
- SwitchTail codebase (source-read): `crates/switchtail-core/src/exchange.rs`, `crates/switchtail-core/src/intent.rs`, `crates/switchtail-plugin/src/main.rs` — confirmed existing `HostIntent::OpenLine`, `open_command_pane` usage, and declared permissions

---
*Feature research for: SwitchTail v0.2 — composing the exchange (in-plugin board/line composition)*
*Researched: 2026-06-13*
